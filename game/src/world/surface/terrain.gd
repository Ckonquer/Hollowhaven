extends RefCounted
## Hollowhaven Woods terrain data + mesh/collision builders.
## A 257 x 257 height field at 1 m spacing covering x,z in [-128, 128] (the playable area is ~[-104, 104];
## hills rise beyond it). Everything is deterministic (fixed noise seeds), so heights, paths and node
## placement are identical on every run.
##   var t = Terrain.new(); t.generate()
##   t.height_at(x, z)            exact height of the rendered/collision surface (same triangulation)
##   t.water_level_at(x, z)       water surface height or NO_WATER
##   t.surface_at(x, z)           "grass" | "stone" | "water"  (footstep surface)
##   t.path_at(x, z)              0..1 dirt path weight
##   t.stream_distance(x, z)      distance to the stream centreline (999 far away)
##   t.build_meshes(parent, mat)  chunked vertex-coloured ArrayMesh terrain (8 x 8 chunks)
##   t.build_collision(parent)    StaticBody3D + HeightMapShape3D (layer 1)

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Palette := preload("res://src/art/palette.gd")

const N := 257
const HALF := 128.0
const CHUNK := 32
const NO_WATER := -1000.0
const FAR := 999.0

var h := PackedFloat32Array()          # heights
var nrm := PackedVector3Array()        # normals
var path_w := PackedFloat32Array()     # 0..1 path weight
var stream_d := PackedFloat32Array()   # distance to stream centreline
var bank_d := PackedFloat32Array()     # distance beyond the stream's water edge (negative = in the channel)
var splat := PackedByteArray()         # RGBA8: path, sand, rock, under-water
var water := PackedFloat32Array()      # water surface level or NO_WATER
var col := PackedColorArray()          # sRGB vertex colours
var grass := PackedByteArray()         # RGBA8: density, height, tint variant, rock
var rock := PackedFloat32Array()       # 0..1 rockiness (steep slopes, cliffs)

var stream_pts := PackedVector3Array() # centreline samples (x, water level, z), north -> south
var stream_half := PackedFloat32Array()
var path_curves: Dictionary = {}       # id -> PackedVector2Array (dense centreline)
var pond_level := 0.0
var pond_center := Vector2(46, 52)
var mine_floor := 0.0
var gen_ms := 0.0

var _dens := PackedFloat32Array()
var _gh := PackedFloat32Array()
var _gv := PackedFloat32Array()


static func catmull_rom(points: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() < 2:
		for p in points:
			out.append(p)
		return out
	var pts: Array = [points[0] + (points[0] - points[1])]
	pts.append_array(points)
	pts.append(points[points.size() - 1] + (points[points.size() - 1] - points[points.size() - 2]))
	for s in range(1, pts.size() - 2):
		var p0: Vector2 = pts[s - 1]
		var p1: Vector2 = pts[s]
		var p2: Vector2 = pts[s + 1]
		var p3: Vector2 = pts[s + 2]
		var n := maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for k in n:
			var t := float(k) / float(n)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[points.size() - 1])
	return out


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _noise_bytes(seed_value: int, freq: float, octaves: int) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	fn.fractal_octaves = octaves
	fn.offset = Vector3(-HALF, -HALF, 0.0)
	var img := fn.get_image(N, N, false, false, false)
	return img.get_data()


func idx(i: int, j: int) -> int:
	return clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)


# --- Generation ---------------------------------------------------------------------------------

func generate() -> void:
	var t0 := Time.get_ticks_usec()
	var total := N * N
	h.resize(total)
	path_w.resize(total)
	path_w.fill(0.0)
	stream_d.resize(total)
	stream_d.fill(FAR)
	bank_d.resize(total)
	bank_d.fill(FAR)
	water.resize(total)
	water.fill(NO_WATER)
	_base_pass()
	_landmark_pass()
	_path_pass()
	_water_pass()
	_normal_pass()
	_color_pass()
	gen_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _base_pass() -> void:
	var n_low := _noise_bytes(1234, 0.011, 3)
	var n_det := _noise_bytes(777, 0.06, 2)
	var n_hill := _noise_bytes(4321, 0.028, 3)
	for j in N:
		var z := float(j) - HALF
		var row := j * N
		for i in N:
			var x := float(i) - HALF
			var k := row + i
			var hh := (float(n_low[k]) / 127.5 - 1.0) * 2.6 + (float(n_det[k]) / 127.5 - 1.0) * 0.28 - z * 0.017
			var ax := absf(x)
			var az := absf(z)
			var e := maxf(maxf(ax, az), sqrt(x * x + z * z) * 0.86)
			if e > 86.0:
				var t := clampf((e - 86.0) / 42.0, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				hh += t * 11.0 + t * t * 6.0 + t * (float(n_hill[k]) / 127.5 - 1.0) * 5.0
			var r2 := x * x + z * z
			if r2 < 1369.0:
				var w := 1.0 - clampf((sqrt(r2) - 19.0) / 18.0, 0.0, 1.0)
				w = w * w * (3.0 - 2.0 * w)
				hh = lerpf(hh, 0.0, w)
			h[k] = hh


## Loops over the samples inside a square around `c` and calls fn(k, x, z, d).
func _each_in(c: Vector2, radius: float, fn: Callable) -> void:
	var i0 := clampi(int(floor(c.x - radius + HALF)), 0, N - 1)
	var i1 := clampi(int(ceil(c.x + radius + HALF)), 0, N - 1)
	var j0 := clampi(int(floor(c.y - radius + HALF)), 0, N - 1)
	var j1 := clampi(int(ceil(c.y + radius + HALF)), 0, N - 1)
	for j in range(j0, j1 + 1):
		var z := float(j) - HALF
		for i in range(i0, i1 + 1):
			var x := float(i) - HALF
			var d := Vector2(x - c.x, z - c.y).length()
			if d <= radius:
				fn.call(j * N + i, x, z, d)


func _landmark_pass() -> void:
	var n_det := _noise_bytes(778, 0.09, 2)
	var hc := {}
	for id in Layout.LANDMARKS:
		var p: Vector2 = Layout.LANDMARKS[id]["pos"]
		hc[id] = h[idx(int(round(p.x + HALF)), int(round(p.y + HALF)))]
	# Pebble Quarry: a flat stony floor with terraces stepping up to the east.
	var q: Vector2 = Layout.LANDMARKS["quarry"]["pos"]
	var qdir := SL.QUARRY_TERRACE_DIR.normalized()
	var qperp := Vector2(-qdir.y, qdir.x)
	var qcc := q + qdir * 34.0
	_each_in(q, 42.0, func(k: int, x: float, z: float, d: float) -> void:
		var floor_w := 1.0 - _smooth(12.0, 24.0, d)
		var v := lerpf(h[k], 0.9, floor_w)
		var rel := Vector2(x, z) - q
		var nz := float(n_det[k]) / 127.5 - 1.0
		# Curved terraces (an amphitheatre around a point behind the quarry wall).
		var s := 34.0 - Vector2(x, z).distance_to(qcc) + nz * 1.1
		var lat := absf(rel.dot(qperp))
		if s > 5.0:
			var steps := (s - 5.0) / 4.4
			var lvl := floorf(steps) + _smooth(0.5, 0.95, steps - floorf(steps))
			var lw := 1.0 - _smooth(12.0 + nz * 3.0, 24.0, lat)
			v = maxf(v, 0.9 + minf(lvl, 3.0) * 1.45 * lw + nz * 0.3 * lw)
		h[k] = v)
	# Moonlit Ruin: a gentle mound with a flat top.
	var rp: Vector2 = Layout.LANDMARKS["ruin"]["pos"]
	var rtop: float = float(hc["ruin"]) + 2.2
	_each_in(rp, 26.0, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] = lerpf(h[k], rtop, 1.0 - _smooth(10.0, 25.0, d)))
	# The Old Oak stands on a little knoll.
	_each_in(Layout.LANDMARKS["old_oak"]["pos"], 12.0, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] += 0.9 * (1.0 - _smooth(3.0, 12.0, d)))
	# Berry Glade: a soft hollow.
	var gp: Vector2 = Layout.LANDMARKS["glade"]["pos"]
	var gl: float = float(hc["glade"]) - 0.4
	_each_in(gp, 24.0, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] = lerpf(h[k], gl, (1.0 - _smooth(8.0, 23.0, d)) * 0.7))
	# Sunny Meadow: open and smooth.
	var mp: Vector2 = Layout.LANDMARKS["meadow"]["pos"]
	var ml: float = float(hc["meadow"]) + 0.3
	_each_in(mp, 28.0, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] = lerpf(h[k], ml, (1.0 - _smooth(10.0, 27.0, d)) * 0.65))
	# Thornthicket: lumpy ground.
	_each_in(Layout.LANDMARKS["thicket"]["pos"], 20.0, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] += (float(n_det[k]) / 127.5 - 1.0) * 0.8 * (1.0 - _smooth(8.0, 20.0, d)))
	# Mirror Pond basin: level the surroundings so the shore is even.
	var pc: float = float(hc["pond"])
	_each_in(pond_center, 32.0, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] = lerpf(h[k], pc, 1.0 - _smooth(15.0, 31.0, d)))
	# Hollow Mine: a flat apron in front of a rocky cliff that joins the northern hills.
	var m := SL.MINE_MOUTH
	var f := SL.MINE_FACING.normalized()
	var perp := Vector2(-f.y, f.x)
	mine_floor = h[idx(int(round(50.0 + HALF)), int(round(-68.0 + HALF)))]
	var n_hill := _noise_bytes(4322, 0.05, 2)
	_each_in(m, 46.0, func(k: int, x: float, z: float, _d: float) -> void:
		var rel := Vector2(x, z) - m
		var behind := rel.dot(-f)
		var lat := rel.dot(perp)
		var alat := absf(lat)
		var v := h[k]
		# apron
		var ap := _smooth(-15.0, -6.0, behind) * (1.0 - _smooth(8.0, 14.0, alat))
		if behind < 1.0:
			v = lerpf(v, mine_floor, ap)
		# Cliff: a curved rocky face that recedes at the sides, kept away from the stream (west).
		var nz := float(n_hill[k]) / 127.5 - 1.0
		var g := behind + 0.011 * lat * lat + nz * 1.4 * _smooth(3.0, 7.0, alat)
		var lf := 1.0 - _smooth(12.0, 21.0, lat) if lat > 0.0 else 1.0
		var c := _smooth(0.2, 4.2, g) * lf
		if c > 0.0:
			var top := mine_floor + 10.5 + nz * 3.2 + _smooth(4.0, 30.0, g) * 6.0
			v = maxf(v, lerpf(v, top, c))
		h[k] = v)


func _path_pass() -> void:
	var total := N * N
	var ph := PackedFloat32Array()
	ph.resize(total)
	var edge := SL.PATH_EDGE
	for id in SL.PATHS:
		var half: float = float(SL.PATH_WIDTHS.get(id, SL.PATH_HALF_WIDTH))
		var reach := half + edge + 0.5
		var curve := catmull_rom(SL.PATHS[id], 0.5)
		path_curves[id] = curve
		var fade_in: float = float(SL.PATH_FADE_IN.get(id, 0.0))
		var along := 0.0
		var prev_c: Vector2 = curve[0] if curve.size() > 0 else Vector2.ZERO
		for c in curve:
			along += c.distance_to(prev_c)
			prev_c = c
			var strength := 1.0 if fade_in <= 0.0 else _smooth(0.0, fade_in, along)
			var hc := _raw_height(c.x, c.y)
			var i0 := clampi(int(floor(c.x - reach + HALF)), 0, N - 1)
			var i1 := clampi(int(ceil(c.x + reach + HALF)), 0, N - 1)
			var j0 := clampi(int(floor(c.y - reach + HALF)), 0, N - 1)
			var j1 := clampi(int(ceil(c.y + reach + HALF)), 0, N - 1)
			for j in range(j0, j1 + 1):
				var dz := float(j) - HALF - c.y
				for i in range(i0, i1 + 1):
					var dx := float(i) - HALF - c.x
					var d := sqrt(dx * dx + dz * dz)
					var w := (1.0 - _smooth(half, half + edge, d)) * strength
					var k := j * N + i
					if w > path_w[k]:
						path_w[k] = w
						ph[k] = hc
	for k in total:
		var w := path_w[k]
		if w > 0.0:
			h[k] = lerpf(h[k], ph[k], w * 0.75)
	for patch in SL.DIRT_PATCHES:
		var pc: Vector2 = patch[0]
		var pr: float = patch[1]
		var ps: float = patch[2]
		_each_in(pc, pr, func(k: int, _x: float, _z: float, d: float) -> void:
			path_w[k] = maxf(path_w[k], ps * (1.0 - _smooth(pr * 0.55, pr, d))))


func pond_edge(angle: float) -> float:
	return SL.POND_RADIUS + 1.7 * sin(3.0 * angle + 0.7) + 0.9 * sin(5.0 * angle + 2.1)


func _water_pass() -> void:
	# Stream centreline: smoothed through the layout points and on into the pond.
	var ctrl: Array = []
	for p in Layout.STREAM_POINTS:
		ctrl.append(p)
	ctrl.append(SL.STREAM_END)
	var curve := catmull_rom(ctrl, 0.75)
	var levels := PackedFloat32Array()
	levels.resize(curve.size())
	var prev := 1e9
	for k in curve.size():
		var b := minf(_raw_height(curve[k].x, curve[k].y), minf(_raw_height(curve[k].x + 1.5, curve[k].y), _raw_height(curve[k].x - 1.5, curve[k].y)))
		prev = minf(prev, b - 0.6)
		levels[k] = prev
	for _pass in 4:
		var sm := levels.duplicate()
		for k in range(1, curve.size() - 1):
			sm[k] = (levels[k - 1] + levels[k] * 2.0 + levels[k + 1]) * 0.25
		levels = sm
	pond_level = levels[curve.size() - 1]
	stream_pts.resize(curve.size())
	stream_half.resize(curve.size())
	var s_len := 0.0
	for k in curve.size():
		if k > 0:
			s_len += curve[k].distance_to(curve[k - 1])
		stream_pts[k] = Vector3(curve[k].x, levels[k], curve[k].y)
		var wv := 2.0 + 0.35 * sin(s_len * 0.11) + 0.2 * sin(s_len * 0.27 + 1.3)
		if curve[k].y < -95.0:
			wv *= lerpf(0.75, 1.0, clampf((curve[k].y + 112.0) / 17.0, 0.0, 1.0))
		stream_half[k] = wv
	# Pond first (bed + shore), then the stream channel (skipping the pond water itself).
	var L := pond_level
	var pond_reach := SL.POND_RADIUS + 12.0
	_each_in(pond_center, pond_reach, func(k: int, x: float, z: float, d: float) -> void:
		var edge := pond_edge(atan2(z - pond_center.y, x - pond_center.x))
		var v := h[k]
		if d < edge:
			v = L - 0.12 - 0.95 * _smooth(edge, edge * 0.35, d)
			water[k] = L
		else:
			var bank := L - 0.12 + (d - edge) * 0.32
			var t := _smooth(edge + 1.0, edge + 7.5, d)
			v = lerpf(bank, v, t)
			if d > edge + 0.9:
				v = maxf(v, L + 0.22)
			if d < edge + 0.6:
				water[k] = L
		h[k] = v)
	var best_k := PackedInt32Array()
	best_k.resize(N * N)
	best_k.fill(-1)
	var best_d2 := PackedFloat32Array()
	best_d2.resize(N * N)
	best_d2.fill(1e9)
	for s in stream_pts.size():
		var c := Vector2(stream_pts[s].x, stream_pts[s].z)
		var reach := stream_half[s] + 5.5
		var i0 := clampi(int(floor(c.x - reach + HALF)), 0, N - 1)
		var i1 := clampi(int(ceil(c.x + reach + HALF)), 0, N - 1)
		var j0 := clampi(int(floor(c.y - reach + HALF)), 0, N - 1)
		var j1 := clampi(int(ceil(c.y + reach + HALF)), 0, N - 1)
		for j in range(j0, j1 + 1):
			var dz := float(j) - HALF - c.y
			for i in range(i0, i1 + 1):
				var dx := float(i) - HALF - c.x
				var d2 := dx * dx + dz * dz
				var k := j * N + i
				if d2 < best_d2[k]:
					best_d2[k] = d2
					best_k[k] = s
	for k in N * N:
		var s := best_k[k]
		if s < 0:
			continue
		var d := sqrt(best_d2[k])
		stream_d[k] = d
		var x := float(k % N) - HALF
		var z := float(k / N) - HALF
		var pd := Vector2(x, z).distance_to(pond_center)
		if pd < pond_edge(atan2(z - pond_center.y, x - pond_center.x)) + 0.5:
			continue
		var half := stream_half[s]
		bank_d[k] = d - half
		if d > half + 5.5:
			continue
		var w := stream_pts[s].y
		var target: float
		if d <= half:
			var r := d / half
			target = w - 0.12 - 0.5 * (1.0 - r * r)
		else:
			target = w - 0.12 + (d - half) * 0.4
		var v := lerpf(target, h[k], _smooth(half + 1.2, half + 5.0, d))
		if d > half + 0.9:
			v = maxf(v, w + 0.2)
		h[k] = v
		if d < half + 0.6:
			water[k] = w


func _normal_pass() -> void:
	nrm.resize(N * N)
	rock.resize(N * N)
	for j in N:
		var jm := maxi(j - 1, 0) * N
		var jp := mini(j + 1, N - 1) * N
		var row := j * N
		for i in N:
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, N - 1)
			var n := Vector3(h[row + im] - h[row + ip], 2.0, h[jm + i] - h[jp + i]).normalized()
			nrm[row + i] = n
			rock[row + i] = _smooth(0.8, 0.63, n.y)


func _color_pass() -> void:
	var total := N * N
	col.resize(total)
	grass.resize(total * 4)
	var n1 := _noise_bytes(501, 0.03, 2)
	var n2 := _noise_bytes(502, 0.085, 2)
	var n3 := _noise_bytes(503, 0.3, 1)
	# Members (not locals): the tint lambda below writes into them, and lambdas capture locals by value.
	_dens.resize(total)
	_gh.resize(total)
	_gv.resize(total)
	var hill_col := Color("5a8f4a")
	for k in total:
		var a := float(n1[k]) / 255.0
		var b := float(n2[k]) / 255.0
		var c := Palette.GRASS.lerp(Palette.GRASS_LIGHT, clampf(a * 1.5 - 0.35, 0.0, 1.0) * 0.8)
		c = c.lerp(Palette.GRASS_DARK, clampf(b * 1.6 - 0.8, 0.0, 1.0) * 0.55)
		var hh := h[k]
		if hh > 3.0:
			c = c.lerp(hill_col, _smooth(3.0, 14.0, hh) * 0.55)
		col[k] = c
		_dens[k] = 0.75 + b * 0.25
		_gh[k] = 0.5
		_gv[k] = 0.3
	# Landmark tints (and grass character).
	var tint := func(center: Vector2, r0: float, r1: float, color: Color, amount: float, g_h: float, g_v: float, g_d: float) -> void:
		_each_in(center, r1, func(k: int, _x: float, _z: float, d: float) -> void:
			var w := (1.0 - _smooth(r0, r1, d))
			col[k] = col[k].lerp(color, w * amount)
			_gh[k] = lerpf(_gh[k], g_h, w)
			_gv[k] = lerpf(_gv[k], g_v, w)
			_dens[k] = lerpf(_dens[k], g_d, w))
	tint.call(Vector2.ZERO, 12.0, 24.0, Palette.GRASS_LIGHT, 0.35, 0.12, 0.15, 0.9)
	tint.call(Layout.LANDMARKS["meadow"]["pos"], 12.0, 28.0, Palette.MEADOW_GOLD, 0.38, 0.95, 0.75, 1.0)
	tint.call(Layout.LANDMARKS["glade"]["pos"], 10.0, 24.0, Color("6fb356"), 0.35, 0.7, 1.0, 1.0)
	tint.call(Layout.LANDMARKS["thicket"]["pos"], 8.0, 20.0, Color("577f3d"), 0.5, 0.85, 0.6, 0.9)
	tint.call(Layout.LANDMARKS["ruin"]["pos"], 6.0, 20.0, Palette.MOSS, 0.4, 0.55, 0.5, 0.8)
	tint.call(Layout.LANDMARKS["old_oak"]["pos"], 3.0, 11.0, Palette.GRASS_DARK, 0.3, 0.45, 0.8, 0.7)
	tint.call(pond_center, 14.0, 26.0, Color("86c46a"), 0.3, 0.7, 1.0, 1.0)
	tint.call(Layout.LANDMARKS["quarry"]["pos"], 9.0, 18.0, Color("b9ab8f"), 0.75, 0.3, 0.2, 0.15)
	var mm := SL.MINE_MOUTH + SL.MINE_FACING.normalized() * 5.0
	tint.call(mm, 4.0, 11.0, Palette.DIRT_DARK, 0.6, 0.3, 0.2, 0.2)
	# Splat (path, sand, rock, under-water) for the terrain shader; grass density follows it.
	splat.resize(total * 4)
	for k in total:
		var x := float(k % N) - HALF
		var z := float(k / N) - HALF
		var hh := h[k]
		var sand := 0.0
		if bank_d[k] < 4.0:
			sand = 1.0 - _smooth(0.5, 2.3, bank_d[k])
		var pd := Vector2(x, z).distance_to(pond_center)
		if pd < SL.POND_RADIUS + 9.0:
			var edge := pond_edge(atan2(z - pond_center.y, x - pond_center.x))
			sand = maxf(sand, 1.0 - _smooth(edge + 0.5, edge + 2.8, pd))
		var wl := water[k]
		var under := 0.0
		if wl > NO_WATER:
			under = clampf((wl - hh) * 5.0, 0.0, 1.0)
		var pw := path_w[k]
		var rk := rock[k]
		var brk := (float(n3[k]) / 255.0 - 0.5) * 0.4
		_dens[k] *= 1.0 - _smooth(0.15, 0.5, pw + brk)
		_dens[k] *= 1.0 - _smooth(0.25, 0.6, rk)
		_dens[k] *= 1.0 - _smooth(0.2, 0.5, sand)
		if under > 0.0:
			_dens[k] = 0.0
		var si := k * 4
		splat[si] = int(clampf(pw, 0.0, 1.0) * 255.0)
		splat[si + 1] = int(clampf(sand, 0.0, 1.0) * 255.0)
		splat[si + 2] = int(clampf(rk, 0.0, 1.0) * 255.0)
		splat[si + 3] = int(under * 255.0)
		grass[si] = int(clampf(_dens[k], 0.0, 1.0) * 255.0)
		grass[si + 1] = int(clampf(_gh[k], 0.0, 1.0) * 255.0)
		grass[si + 2] = int(clampf(_gv[k], 0.0, 1.0) * 255.0)
		grass[si + 3] = int(clampf(rk, 0.0, 1.0) * 255.0)


# --- Queries ----------------------------------------------------------------------------------------

## Bilinear sample of the height array (used during generation before triangulation matters).
func _raw_height(x: float, z: float) -> float:
	var fx := clampf(x + HALF, 0.0, float(N - 1) - 0.001)
	var fz := clampf(z + HALF, 0.0, float(N - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var k := j * N + i
	var a := lerpf(h[k], h[k + 1], tx)
	var b := lerpf(h[k + N], h[k + N + 1], tx)
	return lerpf(a, b, tz)


## Exact height of the rendered and collision surface (cells split along the (i,j)-(i+1,j+1) diagonal).
func height_at(x: float, z: float) -> float:
	if h.is_empty():
		return 0.0
	var fx := clampf(x + HALF, 0.0, float(N - 1) - 0.0001)
	var fz := clampf(z + HALF, 0.0, float(N - 1) - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var k := j * N + i
	var h00 := h[k]
	var h10 := h[k + 1]
	var h01 := h[k + N]
	var h11 := h[k + N + 1]
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func _nearest(x: float, z: float) -> int:
	return idx(int(round(x + HALF)), int(round(z + HALF)))


func water_level_at(x: float, z: float) -> float:
	if water.is_empty():
		return NO_WATER
	return water[_nearest(x, z)]


func is_water(x: float, z: float) -> bool:
	var wl := water_level_at(x, z)
	return wl > NO_WATER and height_at(x, z) < wl - 0.02


func path_at(x: float, z: float) -> float:
	if path_w.is_empty():
		return 0.0
	return path_w[_nearest(x, z)]


func stream_distance(x: float, z: float) -> float:
	if stream_d.is_empty():
		return FAR
	return stream_d[_nearest(x, z)]


func rock_at(x: float, z: float) -> float:
	if rock.is_empty():
		return 0.0
	return rock[_nearest(x, z)]


func pond_distance(x: float, z: float) -> float:
	## Signed distance to the pond shoreline (negative = in the water).
	return Vector2(x, z).distance_to(pond_center) - pond_edge(atan2(z - pond_center.y, x - pond_center.x))


func surface_at(x: float, z: float) -> String:
	if is_water(x, z):
		return "water"
	if rock_at(x, z) > 0.5:
		return "stone"
	var q: Vector2 = Layout.LANDMARKS["quarry"]["pos"]
	if Vector2(x, z).distance_to(q) < 13.0:
		return "stone"
	return "grass"


## Nearest point on the stream centreline: {"pos": Vector3 (water level y), "index": int, "tangent": Vector3}.
func nearest_stream_point(x: float, z: float) -> Dictionary:
	var best := -1
	var bd := 1e9
	for k in stream_pts.size():
		var d := Vector2(stream_pts[k].x - x, stream_pts[k].z - z).length_squared()
		if d < bd:
			bd = d
			best = k
	if best < 0:
		return {}
	var a := stream_pts[maxi(best - 2, 0)]
	var b := stream_pts[mini(best + 2, stream_pts.size() - 1)]
	var tng := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	return {"pos": stream_pts[best], "index": best, "tangent": tng, "half": stream_half[best]}


# --- Builders -----------------------------------------------------------------------------------------

func build_meshes(parent: Node3D, material: Material) -> Array:
	var out: Array = []
	var cn := (N - 1) / CHUNK
	var vn := CHUNK + 1
	var indices := PackedInt32Array()
	indices.resize(CHUNK * CHUNK * 6)
	var t := 0
	for jj in CHUNK:
		for ii in CHUNK:
			var a := jj * vn + ii
			indices[t] = a
			indices[t + 1] = a + 1
			indices[t + 2] = a + vn + 1
			indices[t + 3] = a
			indices[t + 4] = a + vn + 1
			indices[t + 5] = a + vn
			t += 6
	var lin := PackedColorArray()
	lin.resize(col.size())
	for k in col.size():
		lin[k] = col[k].srgb_to_linear()
	for cj in cn:
		for ci in cn:
			var verts := PackedVector3Array()
			verts.resize(vn * vn)
			var norms := PackedVector3Array()
			norms.resize(vn * vn)
			var cols := PackedColorArray()
			cols.resize(vn * vn)
			var v := 0
			for jj in vn:
				var j := cj * CHUNK + jj
				for ii in vn:
					var i := ci * CHUNK + ii
					var k := j * N + i
					verts[v] = Vector3(float(i) - HALF, h[k], float(j) - HALF)
					norms[v] = nrm[k]
					cols[v] = lin[k]
					v += 1
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = mesh
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			parent.add_child(mi)
			out.append(mi)
	return out


func build_collision(parent: Node3D, body_script: Script = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	if body_script != null:
		body.set_script(body_script)
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "grass")
	var cs := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = h
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


func height_image() -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RF, h.to_byte_array())


func color_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(N * N * 4)
	for k in col.size():
		var c: Color = col[k]
		var b := k * 4
		bytes[b] = c.r8
		bytes[b + 1] = c.g8
		bytes[b + 2] = c.b8
		bytes[b + 3] = 255
	return Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, bytes)


func splat_image() -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, splat)


func grass_image() -> Image:
	return Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, grass)


## Clears grass density in a small radius (so props such as sticks and stones aren't hidden).
func clear_grass(x: float, z: float, radius: float) -> void:
	var i0 := clampi(int(floor(x - radius + HALF)), 0, N - 1)
	var i1 := clampi(int(ceil(x + radius + HALF)), 0, N - 1)
	var j0 := clampi(int(floor(z - radius + HALF)), 0, N - 1)
	var j1 := clampi(int(ceil(z + radius + HALF)), 0, N - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(float(i) - HALF - x, float(j) - HALF - z).length()
			if d <= radius:
				var k := (j * N + i) * 4
				grass[k] = int(float(grass[k]) * clampf(d / radius, 0.0, 1.0) * 0.5)
