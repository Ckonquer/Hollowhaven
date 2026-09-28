extends RefCounted
## Hallowmere Reach terrain (docs/ch2/maps/world_areas.md 6a, docs/CHAPTER_TWO_SPEC.md §7.2 / §10).
## A 321 x 257 height field at 1 m spacing covering x in [-160, 160], z in [-128, 128]; the playable
## Reach is x in [-140, 140], z in [-110, 110] (walls at Reach.WALL_HALF_*), soft hills rise beyond it.
## Deterministic (own fixed noise seeds), same query names as src/world/surface/terrain.gd so the shared
## Grass, Props, ResourceNode, terrain_body.gd and world_item scripts work unchanged.
##
## Generation is split so the districts can shape their own ground BEFORE meshes and collision exist:
##   t.generate_base()      base noise + soft boundary hills, plazas, roads, Thimblebrook, the Bellhouse
##   (districts)            each district's static shape_terrain(t) runs inside a shaping limit (its
##                          landmark circle); src/world/reach/reach_districts.gd keeps edits inside it
##   t.finish()             protected arch plazas, normals, autumn colours, splat and grass masks
##   t.generate()           = generate_base() + finish() (tests, no districts)
##
## Queries: height_at(x, z) (exact render/collision surface), normal_at, water_level_at, is_water,
## path_at, stream_distance (Thimblebrook), rock_at, pond_distance, surface_at ("grass"|"stone"|"water"),
## nearest_stream_point, edge_metric, plaza_height(id), clear_grass(x, z, r), *_image() for the shaders.
## Builders: build_meshes(parent, material), build_collision(parent, body_script) (layer 1).
##
## District shaping API (use inside static func shape_terrain(terrain)); every call is clamped to the
## current shaping limit and the loader discards anything outside the district's landmark circle anyway:
##   NX, NZ, HALF_X, HALF_Z, ORIGIN, h (PackedFloat32Array, k = j * NX + i), idx(i, j), index_of(x, z),
##   sample_x(i), sample_z(j), raw_height(x, z), get_height(x, z), set_height(x, z, v),
##   each_in(center: Vector2, radius, fn: Callable(k, x, z, d)), flatten(center, flat_r, blend_r, height),
##   blend_to(center, r0, r1, height, strength), raise(center, radius, amount), set_water(x, z, level),
##   set_water_disc(center, radius, level), add_stone_disc(center, radius), tint_disc(center, r0, r1, color, amount),
##   mark_path(points: Array[Vector2], half_width, strength).

const Reach := preload("res://data/hallowmere_layout.gd")

const NX := 321
const NZ := 257
const HALF_X := 160.0
const HALF_Z := 128.0
const ORIGIN := Vector2(-160.0, -128.0)
const CHUNK := 32
const NO_WATER := -1000.0
const FAR := 999.0
const PATH_EDGE := 1.3

# Autumn ground palette.
const G_BASE := Color("a39c50")
const G_LIGHT := Color("cfb45e")
const G_DARK := Color("6d783d")
const G_RUSSET := Color("b0663a")
const G_RED := Color("94412f")
const G_HILL := Color("7c6a48")

var h := PackedFloat32Array()          # heights
var nrm := PackedVector3Array()        # normals
var path_w := PackedFloat32Array()     # 0..1 path weight
var stream_d := PackedFloat32Array()   # distance to the Thimblebrook centreline
var bank_d := PackedFloat32Array()     # distance beyond the brook's water edge (negative = in the channel)
var splat := PackedByteArray()         # RGBA8: path, sand, rock, under-water
var water := PackedFloat32Array()      # water surface level or NO_WATER
var col := PackedColorArray()          # sRGB vertex colours
var grass := PackedByteArray()         # RGBA8: density, height, tint variant, rock
var rock := PackedFloat32Array()       # 0..1 rockiness (steep slopes)
var no_grass := PackedByteArray()      # 1 = keep grass off (buildings, stair, tower)

var stream_pts := PackedVector3Array() # brook centreline samples (x, water level, z), upstream -> downstream
var stream_half := PackedFloat32Array()
var path_curves: Dictionary = {}       # road id -> PackedVector2Array (dense centreline)
var plaza_heights: Dictionary = {}     # plaza id -> float
var ponds: Array = []                  # [[Vector2 centre, float radius, float level], ...] still water
var stone_discs: Array = []            # [[Vector2 centre, float radius], ...] footsteps "stone"
var tint_ops: Array = []               # [[centre, r0, r1, Color, amount], ...] applied by the colour pass
var bellhouse_level := 0.0             # forecourt height of the Sunken Bellhouse
var gen_ms := 0.0
var times: Dictionary = {}

## Shaping limit for district edits: Vector3(cx, cz, radius); radius < 0 = no limit (region code).
var limit := Vector3(0.0, 0.0, -1.0)

var _dens := PackedFloat32Array()
var _gh := PackedFloat32Array()
var _gv := PackedFloat32Array()
var _base_done := false


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


static func smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 0 at the centre, 1.0 on the playable rectangle's edge (rounded corners); hills rise past ~0.84.
static func edge_metric(x: float, z: float) -> float:
	var ax := absf(x) / Reach.HALF_X
	var az := absf(z) / Reach.HALF_Z
	return maxf(maxf(ax, az), sqrt(ax * ax + az * az) * 0.86)


func _noise_bytes(seed_value: int, freq: float, octaves: int) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	fn.fractal_octaves = octaves
	fn.offset = Vector3(-HALF_X, -HALF_Z, 0.0)
	var img := fn.get_image(NX, NZ, false, false, false)
	return img.get_data()


func idx(i: int, j: int) -> int:
	return clampi(j, 0, NZ - 1) * NX + clampi(i, 0, NX - 1)


func sample_x(i: int) -> float:
	return float(i) - HALF_X


func sample_z(j: int) -> float:
	return float(j) - HALF_Z


## Index of the sample nearest to (x, z), or -1 outside the grid.
func index_of(x: float, z: float) -> int:
	var i := int(round(x + HALF_X))
	var j := int(round(z + HALF_Z))
	if i < 0 or j < 0 or i >= NX or j >= NZ:
		return -1
	return j * NX + i


# --- Generation -----------------------------------------------------------------------------------

func generate() -> void:
	generate_base()
	finish()


func generate_base() -> void:
	var t0 := Time.get_ticks_usec()
	var total := NX * NZ
	h.resize(total)
	path_w.resize(total)
	path_w.fill(0.0)
	stream_d.resize(total)
	stream_d.fill(FAR)
	bank_d.resize(total)
	bank_d.fill(FAR)
	water.resize(total)
	water.fill(NO_WATER)
	no_grass.resize(total)
	no_grass.fill(0)
	ponds.clear()
	stone_discs.clear()
	tint_ops.clear()
	plaza_heights.clear()
	var steps := [_base_pass, _plaza_pass, _path_pass, _brook_pass, _bellhouse_pass]
	var names := ["base", "plazas", "paths", "brook", "bellhouse"]
	for s in steps.size():
		var ts := Time.get_ticks_usec()
		(steps[s] as Callable).call()
		times[names[s]] = float(Time.get_ticks_usec() - ts) / 1000.0
	_base_done = true
	gen_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func finish() -> void:
	if not _base_done:
		generate_base()
	limit = Vector3(0.0, 0.0, -1.0)
	var t0 := Time.get_ticks_usec()
	_protect_pass()
	var ts := Time.get_ticks_usec()
	_normal_pass()
	times["normals"] = float(Time.get_ticks_usec() - ts) / 1000.0
	ts = Time.get_ticks_usec()
	_color_pass()
	times["colors"] = float(Time.get_ticks_usec() - ts) / 1000.0
	gen_ms += float(Time.get_ticks_usec() - t0) / 1000.0


func _base_pass() -> void:
	var n_low := _noise_bytes(5101, 0.012, 3)
	var n_det := _noise_bytes(5102, 0.07, 2)
	var n_hill := _noise_bytes(5103, 0.03, 3)
	var n_cliff := _noise_bytes(5104, 0.045, 2)
	for j in NZ:
		var z := float(j) - HALF_Z
		var row := j * NX
		var north := smooth(-35.0, -95.0, z) * 2.6
		for i in NX:
			var x := float(i) - HALF_X
			var k := row + i
			var hh := (float(n_low[k]) / 127.5 - 1.0) * 2.4 + (float(n_det[k]) / 127.5 - 1.0) * 0.3 - z * 0.026
			hh += smooth(40.0, 115.0, x) * 2.4 + north
			var e := edge_metric(x, z)
			if e > 0.84:
				var t := smooth(0.84, 1.1, e)
				hh += t * 10.0 + t * t * 6.0 + t * (float(n_hill[k]) / 127.5 - 1.0) * 4.5
				# a few crags on the outer hills (read as cliffs behind the trees)
				var c := float(n_cliff[k]) / 255.0
				hh += smooth(0.6, 0.72, c) * t * 5.0
			h[k] = hh


## Loops over the samples inside a square around `c` and calls fn(k, x, z, d) for those within radius.
func each_in(c: Vector2, radius: float, fn: Callable) -> void:
	var i0 := clampi(int(floor(c.x - radius + HALF_X)), 0, NX - 1)
	var i1 := clampi(int(ceil(c.x + radius + HALF_X)), 0, NX - 1)
	var j0 := clampi(int(floor(c.y - radius + HALF_Z)), 0, NZ - 1)
	var j1 := clampi(int(ceil(c.y + radius + HALF_Z)), 0, NZ - 1)
	for j in range(j0, j1 + 1):
		var z := float(j) - HALF_Z
		for i in range(i0, i1 + 1):
			var x := float(i) - HALF_X
			var d := Vector2(x - c.x, z - c.y).length()
			if d <= radius and _in_limit(x, z):
				fn.call(j * NX + i, x, z, d)


## Alias kept for code written against src/world/surface/terrain.gd.
func _each_in(c: Vector2, radius: float, fn: Callable) -> void:
	each_in(c, radius, fn)


func _in_limit(x: float, z: float) -> bool:
	if limit.z < 0.0:
		return true
	return Vector2(x - limit.x, z - limit.y).length() <= limit.z


## Flattens toward `height`: fully inside flat_r, blending out to blend_r.
func flatten(center: Vector2, flat_r: float, blend_r: float, height: float) -> void:
	each_in(center, blend_r, func(k: int, _x: float, _z: float, d: float) -> void:
		var w := 1.0 - smooth(flat_r, blend_r, d)
		h[k] = lerpf(h[k], height, w))


func blend_to(center: Vector2, r0: float, r1: float, height: float, strength: float) -> void:
	each_in(center, r1, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] = lerpf(h[k], height, (1.0 - smooth(r0, r1, d)) * clampf(strength, 0.0, 1.0)))


## A soft bump (amount > 0) or dip (amount < 0) of the given radius.
func raise(center: Vector2, radius: float, amount: float) -> void:
	each_in(center, radius, func(k: int, _x: float, _z: float, d: float) -> void:
		h[k] += amount * (1.0 - smooth(0.0, radius, d)))


func get_height(x: float, z: float) -> float:
	var k := index_of(x, z)
	return h[k] if k >= 0 else 0.0


func set_height(x: float, z: float, v: float) -> void:
	var k := index_of(x, z)
	if k >= 0 and _in_limit(x, z):
		h[k] = v


func set_water(x: float, z: float, level: float) -> void:
	var k := index_of(x, z)
	if k >= 0 and _in_limit(x, z):
		water[k] = level


func set_water_disc(center: Vector2, radius: float, level: float) -> void:
	each_in(center, radius, func(k: int, _x: float, _z: float, _d: float) -> void:
		water[k] = level)


func add_stone_disc(center: Vector2, radius: float) -> void:
	if limit.z >= 0.0:
		radius = minf(radius, maxf(limit.z - center.distance_to(Vector2(limit.x, limit.y)), 0.0))
	if radius > 0.0:
		stone_discs.append([center, radius])


## Recorded now, applied by the colour pass in finish() (clamped to the shaping limit).
func tint_disc(center: Vector2, r0: float, r1: float, color: Color, amount: float) -> void:
	if limit.z >= 0.0:
		var room := maxf(limit.z - center.distance_to(Vector2(limit.x, limit.y)), 0.0)
		r1 = minf(r1, room)
		r0 = minf(r0, r1)
	if r1 > 0.0:
		tint_ops.append([center, r0, r1, color, clampf(amount, 0.0, 1.0)])


## Paints a path weight along a polyline (Catmull-Rom smoothed); does not change heights.
func mark_path(points: Array, half_width: float, strength: float = 1.0) -> void:
	var curve := catmull_rom(points, 0.5)
	for c in curve:
		each_in(c, half_width + PATH_EDGE, func(k: int, _x: float, _z: float, d: float) -> void:
			var w := (1.0 - smooth(half_width, half_width + PATH_EDGE, d)) * strength
			if w > path_w[k]:
				path_w[k] = w)


func _base_at(p: Vector2) -> float:
	return h[idx(int(round(p.x + HALF_X)), int(round(p.y + HALF_Z)))]


func _plaza(id: String) -> Array:
	return Reach.PLAZAS[id]


## Flat walkable plazas. The Commons keeps its natural height; the arrival stands a little above it
## (the first view looks down into the festival); the outpost lot shares the Commons level.
func _plaza_pass() -> void:
	var order := ["commons", "outpost", "arrival", "crossroads", "conservatory", "refuge_hatch", "orchard_arch",
		"quarry_arch", "manor_arch", "manor_door", "bellhouse"]
	for id in order:
		var pl: Array = _plaza(String(id))
		var c: Vector2 = pl[0]
		var target := _base_at(c)
		match String(id):
			"outpost":
				target = float(plaza_heights["commons"])
			"arrival":
				target = maxf(target, float(plaza_heights["commons"]) + 1.3)
			"conservatory":
				target += 0.3
		plaza_heights[id] = target
		flatten(c, float(pl[1]), float(pl[2]), target)
	bellhouse_level = float(plaza_heights["bellhouse"])


func _path_pass() -> void:
	var ph := PackedFloat32Array()
	ph.resize(NX * NZ)
	for id in Reach.PATHS:
		var half: float = float(Reach.PATH_WIDTHS.get(id, 1.5))
		var reach := half + PATH_EDGE + 0.5
		var curve := catmull_rom(Reach.PATHS[id], 0.5)
		path_curves[id] = curve
		for c in curve:
			var hc := raw_height(c.x, c.y)
			var i0 := clampi(int(floor(c.x - reach + HALF_X)), 0, NX - 1)
			var i1 := clampi(int(ceil(c.x + reach + HALF_X)), 0, NX - 1)
			var j0 := clampi(int(floor(c.y - reach + HALF_Z)), 0, NZ - 1)
			var j1 := clampi(int(ceil(c.y + reach + HALF_Z)), 0, NZ - 1)
			for j in range(j0, j1 + 1):
				var dz := float(j) - HALF_Z - c.y
				for i in range(i0, i1 + 1):
					var dx := float(i) - HALF_X - c.x
					var d := sqrt(dx * dx + dz * dz)
					var w := 1.0 - smooth(half, half + PATH_EDGE, d)
					var k := j * NX + i
					if w > path_w[k]:
						path_w[k] = w
						ph[k] = hc
	for k in NX * NZ:
		var w := path_w[k]
		if w > 0.0:
			h[k] = lerpf(h[k], ph[k], w * 0.7)
	for patch in Reach.DIRT_PATCHES:
		var pc: Vector2 = patch[0]
		var pr: float = patch[1]
		var ps: float = patch[2]
		each_in(pc, pr, func(k: int, _x: float, _z: float, d: float) -> void:
			path_w[k] = maxf(path_w[k], ps * (1.0 - smooth(pr * 0.55, pr, d))))


## Thimblebrook: a shallow brook (<= ~0.6 m deep in the middle) with gentle sandy banks, always
## flowing downhill (running minimum), carved like the Woods stream.
func _brook_pass() -> void:
	var curve := catmull_rom(Reach.BROOK_POINTS, 0.75)
	var levels := PackedFloat32Array()
	levels.resize(curve.size())
	var prev := 1e9
	for k in curve.size():
		var p := curve[k]
		var b := minf(raw_height(p.x, p.y), minf(raw_height(p.x + 1.5, p.y), raw_height(p.x - 1.5, p.y)))
		prev = minf(prev, b - 0.55)
		levels[k] = prev
	for _pass in 4:
		var sm := levels.duplicate()
		for k in range(1, curve.size() - 1):
			sm[k] = minf((levels[k - 1] + levels[k] * 2.0 + levels[k + 1]) * 0.25, sm[k - 1])
		levels = sm
	stream_pts.resize(curve.size())
	stream_half.resize(curve.size())
	var s_len := 0.0
	for k in curve.size():
		if k > 0:
			s_len += curve[k].distance_to(curve[k - 1])
		stream_pts[k] = Vector3(curve[k].x, levels[k], curve[k].y)
		stream_half[k] = Reach.BROOK_HALF_WIDTH + 0.25 * sin(s_len * 0.13) + 0.15 * sin(s_len * 0.31 + 1.1)
	var best_k := PackedInt32Array()
	best_k.resize(NX * NZ)
	best_k.fill(-1)
	var best_d2 := PackedFloat32Array()
	best_d2.resize(NX * NZ)
	best_d2.fill(1e9)
	for s in stream_pts.size():
		var c := Vector2(stream_pts[s].x, stream_pts[s].z)
		var reach := stream_half[s] + 5.5
		var i0 := clampi(int(floor(c.x - reach + HALF_X)), 0, NX - 1)
		var i1 := clampi(int(ceil(c.x + reach + HALF_X)), 0, NX - 1)
		var j0 := clampi(int(floor(c.y - reach + HALF_Z)), 0, NZ - 1)
		var j1 := clampi(int(ceil(c.y + reach + HALF_Z)), 0, NZ - 1)
		for j in range(j0, j1 + 1):
			var dz := float(j) - HALF_Z - c.y
			for i in range(i0, i1 + 1):
				var dx := float(i) - HALF_X - c.x
				var d2 := dx * dx + dz * dz
				var k := j * NX + i
				if d2 < best_d2[k]:
					best_d2[k] = d2
					best_k[k] = s
	for k in NX * NZ:
		var s := best_k[k]
		if s < 0:
			continue
		var d := sqrt(best_d2[k])
		stream_d[k] = d
		var half := stream_half[s]
		bank_d[k] = d - half
		if d > half + 5.5:
			continue
		var w := stream_pts[s].y
		var target: float
		if d <= half:
			var r := d / half
			target = w - 0.12 - 0.54 * (1.0 - r * r)
		else:
			target = w - 0.12 + (d - half) * 0.4
		var v := lerpf(target, h[k], smooth(half + 1.2, half + 5.0, d))
		if d > half + 0.9:
			v = maxf(v, w + 0.2)
		h[k] = v
		if d < half + 0.6:
			water[k] = w


## The Sunken Bellhouse: a still pond around the half-sunken tower and the stairwell to the service gate,
## carved below the forecourt (the stair is sealed by stone slabs until ch2_lamps_linked).
func _bellhouse_pass() -> void:
	var B: Dictionary = Reach.BELLHOUSE
	var hb := bellhouse_level
	var pc: Vector2 = B["pond"]
	var pr: float = B["pond_radius"]
	var level := hb - 0.95
	var sx: float = B["stair_x"]
	var wall_outer: float = B["wall_outer"]
	var tower: Rect2 = B["tower"]
	var top_z: float = B["ramp_top_z"]
	var bot_z: float = B["ramp_bottom_z"]
	var depth: float = B["depth"]
	var end_z: float = B["bottom_end_z"]
	ponds.append([pc, pr, level])
	each_in(pc, pr + 4.5, func(k: int, x: float, z: float, d: float) -> void:
		if absf(x - sx) <= wall_outer + 0.6 and z <= top_z + 0.5:
			return
		var bed := hb - 1.9 + smooth(pr * 0.7, pr, d) * 1.2
		var v := lerpf(bed, h[k], smooth(pr, pr + 4.5, d))
		h[k] = minf(h[k], v)
		if d < pr - 0.4 and h[k] < level - 0.02:
			water[k] = level)
	# Tower footprint: a stone base just under the water line (the tower is built on it).
	for j in range(int(floor(tower.position.y + HALF_Z)), int(ceil(tower.end.y + HALF_Z)) + 1):
		for i in range(int(floor(tower.position.x + HALF_X)), int(ceil(tower.end.x + HALF_X)) + 1):
			var k := idx(i, j)
			h[k] = minf(h[k], hb - 1.2)
			water[k] = NO_WATER
			no_grass[k] = 1
	# Stairwell: a ramp from the forecourt down `depth` metres, then a flat landing under the tower.
	var bottom := hb - depth
	for j in range(int(floor(end_z - 0.5 + HALF_Z)), int(ceil(top_z + 0.5 + HALF_Z)) + 1):
		var z := float(j) - HALF_Z
		for i in range(int(floor(sx - wall_outer + 0.5 + HALF_X)), int(ceil(sx + wall_outer - 0.5 + HALF_X)) + 1):
			var x := float(i) - HALF_X
			var k := idx(i, j)
			water[k] = NO_WATER
			no_grass[k] = 1
			if absf(x - sx) > 2.05:
				h[k] = maxf(h[k], hb)      # under the stairwell walls: solid ground at forecourt level
				continue
			var t := clampf((top_z - z) / (top_z - bot_z), 0.0, 1.0)
			if z > top_z:
				h[k] = hb
			else:
				h[k] = lerpf(hb, bottom, t)
	stone_discs.append([Vector2(B["forecourt"]), 6.5])
	stone_discs.append([Vector2(sx, (top_z + end_z) * 0.5), 6.0])


## Re-levels the arch plazas after the districts shaped their ground (the arches are the region's).
func _protect_pass() -> void:
	for id in Reach.PROTECTED_PLAZAS:
		var pl: Array = _plaza(String(id))
		var c: Vector2 = pl[0]
		var target := _base_at(c)
		plaza_heights[id] = target
		flatten(c, float(pl[1]) - 0.5, float(pl[1]) + 2.5, target)


func _normal_pass() -> void:
	nrm.resize(NX * NZ)
	rock.resize(NX * NZ)
	for j in NZ:
		var jm := maxi(j - 1, 0) * NX
		var jp := mini(j + 1, NZ - 1) * NX
		var row := j * NX
		for i in NX:
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, NX - 1)
			var n := Vector3(h[row + im] - h[row + ip], 2.0, h[jm + i] - h[jp + i]).normalized()
			nrm[row + i] = n
			rock[row + i] = smooth(0.8, 0.63, n.y)


func _tint(center: Vector2, r0: float, r1: float, color: Color, amount: float, g_h: float, g_v: float, g_d: float) -> void:
	var saved := limit
	limit = Vector3(0.0, 0.0, -1.0)
	each_in(center, r1, func(k: int, _x: float, _z: float, d: float) -> void:
		var w := (1.0 - smooth(r0, r1, d))
		col[k] = col[k].lerp(color, w * amount)
		if g_h >= 0.0:
			_gh[k] = lerpf(_gh[k], g_h, w)
			_gv[k] = lerpf(_gv[k], g_v, w)
			_dens[k] = lerpf(_dens[k], g_d, w))
	limit = saved


func _color_pass() -> void:
	var total := NX * NZ
	col.resize(total)
	grass.resize(total * 4)
	var n1 := _noise_bytes(5201, 0.03, 2)
	var n2 := _noise_bytes(5202, 0.085, 2)
	var n3 := _noise_bytes(5203, 0.3, 1)
	var n4 := _noise_bytes(5204, 0.07, 2)
	_dens.resize(total)
	_gh.resize(total)
	_gv.resize(total)
	var ihx := 1.0 / Reach.HALF_X
	var ihz := 1.0 / Reach.HALF_Z
	for j in NZ:
		var z := float(j) - HALF_Z
		var az := absf(z) * ihz
		var row := j * NX
		for i in NX:
			var k := row + i
			var a := float(n1[k]) / 255.0
			var b := float(n2[k]) / 255.0
			var lf := float(n4[k]) / 255.0
			var c := G_BASE.lerp(G_LIGHT, clampf(a * 1.5 - 0.35, 0.0, 1.0) * 0.7)
			c = c.lerp(G_DARK, clampf(b * 1.6 - 0.8, 0.0, 1.0) * 0.5)
			# drifts of fallen copper and red leaves (inlined smoothsteps: this loop is hot)
			if lf > 0.6:
				var s1 := clampf((lf - 0.6) / 0.18, 0.0, 1.0)
				c = c.lerp(G_RUSSET, s1 * s1 * (3.0 - 2.0 * s1) * 0.5)
				if lf > 0.74:
					var s2 := clampf((lf - 0.74) / 0.12, 0.0, 1.0)
					c = c.lerp(G_RED, s2 * s2 * (3.0 - 2.0 * s2) * 0.3)
			var ax := absf(float(i) - HALF_X) * ihx
			var e := maxf(maxf(ax, az), sqrt(ax * ax + az * az) * 0.86)
			if e > 0.84:
				var s3 := clampf((e - 0.84) / 0.21, 0.0, 1.0)
				c = c.lerp(G_HILL, s3 * s3 * (3.0 - 2.0 * s3) * 0.5)
			col[k] = c
			_dens[k] = 0.72 + b * 0.25
			_gh[k] = 0.5
			_gv[k] = 0.35 + lf * 0.4
	# Neighbourhood character (colour, grass height, tint variant, density).
	_tint(Vector2(0, 60), 10.0, 26.0, Color("d6b25c"), 0.3, 0.2, 0.7, 0.75)
	_tint(Vector2(0, 98), 4.0, 12.0, Color("d6b25c"), 0.25, 0.25, 0.7, 0.8)
	_tint(Vector2(0, 6), 8.0, 19.0, Color("97a55a"), 0.3, 0.35, 0.3, 0.85)
	_tint(Vector2(-82, 36), 12.0, 30.0, Color("d4a646"), 0.28, 0.75, 0.9, 0.9)
	_tint(Vector2(-44, -8), 6.0, 18.0, Color("7fa062"), 0.35, 0.85, 0.2, 1.0)
	_tint(Vector2(-86, -60), 8.0, 22.0, Color("7b6c8c"), 0.42, 0.35, 0.1, 0.7)
	_tint(Vector2(86, 18), 10.0, 30.0, Color("b5694a"), 0.45, 0.3, 0.9, 0.35)
	_tint(Vector2(18, -74), 10.0, 26.0, Color("735c66"), 0.35, 0.4, 0.4, 0.8)
	_tint(Vector2(72, -80), 6.0, 16.0, Color("7b8986"), 0.35, 0.45, 0.2, 0.7)
	for op in tint_ops:
		_tint(op[0], float(op[1]), float(op[2]), op[3], float(op[4]), -1.0, 0.0, 0.0)
	# Sandy shores around the still ponds (only near them: cheap).
	var shore := PackedFloat32Array()
	shore.resize(total)
	shore.fill(0.0)
	for p in ponds:
		var pc: Vector2 = p[0]
		var pr: float = p[1]
		var rr := pr + 2.5
		for j in range(clampi(int(floor(pc.y - rr + HALF_Z)), 0, NZ - 1), clampi(int(ceil(pc.y + rr + HALF_Z)), 0, NZ - 1) + 1):
			for i in range(clampi(int(floor(pc.x - rr + HALF_X)), 0, NX - 1), clampi(int(ceil(pc.x + rr + HALF_X)), 0, NX - 1) + 1):
				var pd := Vector2(float(i) - HALF_X - pc.x, float(j) - HALF_Z - pc.y).length() - pr
				if pd < 2.5:
					var k := j * NX + i
					shore[k] = maxf(shore[k], (1.0 - smooth(0.2, 2.5, pd)) * 0.8)
	splat.resize(total * 4)
	for k in total:
		var hh := h[k]
		var sand := shore[k]
		var bd := bank_d[k]
		if bd < 2.2:
			var sb := clampf((bd - 0.5) / 1.7, 0.0, 1.0)
			sand = maxf(sand, 1.0 - sb * sb * (3.0 - 2.0 * sb))
		var wl := water[k]
		var under := 0.0
		if wl > NO_WATER:
			under = clampf((wl - hh) * 5.0, 0.0, 1.0)
			sand = maxf(sand, 0.0)
		var pw := path_w[k]
		var rk := rock[k]
		var dens := _dens[k]
		var pt := clampf((pw + (float(n3[k]) / 255.0 - 0.5) * 0.4 - 0.15) / 0.35, 0.0, 1.0)
		dens *= 1.0 - pt * pt * (3.0 - 2.0 * pt)
		if rk > 0.25:
			var rt := clampf((rk - 0.25) / 0.35, 0.0, 1.0)
			dens *= 1.0 - rt * rt * (3.0 - 2.0 * rt)
		if sand > 0.2:
			var st := clampf((sand - 0.2) / 0.3, 0.0, 1.0)
			dens *= 1.0 - st * st * (3.0 - 2.0 * st)
		if under > 0.0 or no_grass[k] != 0:
			dens = 0.0
		_dens[k] = dens
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

## Bilinear sample of the height array (generation helper; height_at is the exact surface).
func raw_height(x: float, z: float) -> float:
	var fx := clampf(x + HALF_X, 0.0, float(NX - 1) - 0.001)
	var fz := clampf(z + HALF_Z, 0.0, float(NZ - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var k := j * NX + i
	var a := lerpf(h[k], h[k + 1], tx)
	var b := lerpf(h[k + NX], h[k + NX + 1], tx)
	return lerpf(a, b, tz)


## Exact height of the rendered and collision surface (cells split along the (i+1,j)-(i,j+1) diagonal,
## which is how Godot's Jolt height field triangulates; build_meshes uses the same split).
func height_at(x: float, z: float) -> float:
	if h.is_empty():
		return 0.0
	var fx := clampf(x + HALF_X, 0.0, float(NX - 1) - 0.0001)
	var fz := clampf(z + HALF_Z, 0.0, float(NZ - 1) - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var k := j * NX + i
	var h00 := h[k]
	var h10 := h[k + 1]
	var h01 := h[k + NX]
	var h11 := h[k + NX + 1]
	# Same split as the Jolt height field (measured): the (i+1, j)-(i, j+1) diagonal. The render mesh uses it too.
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func _nearest(x: float, z: float) -> int:
	return idx(int(round(x + HALF_X)), int(round(z + HALF_Z)))


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


## Signed distance to the nearest still pond's shore (negative = in the pond); FAR without ponds.
func pond_distance(x: float, z: float) -> float:
	var best := FAR
	for p in ponds:
		best = minf(best, Vector2(x, z).distance_to(p[0]) - float(p[1]))
	return best


func plaza_height(id: String) -> float:
	return float(plaza_heights.get(id, 0.0))


func surface_at(x: float, z: float) -> String:
	if is_water(x, z):
		return "water"
	for s in stone_discs:
		if Vector2(x, z).distance_to(s[0]) <= float(s[1]):
			return "stone"
	if rock_at(x, z) > 0.5:
		return "stone"
	return "grass"


## Nearest brook centreline point: {"pos": Vector3 (water level y), "index", "tangent", "half"}.
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


func min_height() -> float:
	var m := 1e9
	for v in h:
		m = minf(m, v)
	return m


# --- Builders -----------------------------------------------------------------------------------------

func build_meshes(parent: Node3D, material: Material) -> Array:
	var out: Array = []
	var cnx := (NX - 1) / CHUNK
	var cnz := (NZ - 1) / CHUNK
	var vn := CHUNK + 1
	var indices := PackedInt32Array()
	indices.resize(CHUNK * CHUNK * 6)
	var t := 0
	for jj in CHUNK:
		for ii in CHUNK:
			var a := jj * vn + ii
			# split along (i+1, j)-(i, j+1), like the collision height field (same winding as before)
			indices[t] = a
			indices[t + 1] = a + 1
			indices[t + 2] = a + vn
			indices[t + 3] = a + 1
			indices[t + 4] = a + vn + 1
			indices[t + 5] = a + vn
			t += 6
	var lin := PackedColorArray()
	lin.resize(col.size())
	for k in col.size():
		lin[k] = col[k].srgb_to_linear()
	for cj in cnz:
		for ci in cnx:
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
					var k := j * NX + i
					verts[v] = Vector3(float(i) - HALF_X, h[k], float(j) - HALF_Z)
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
	# Jolt only builds a real (fast) height field for SQUARE maps; a 321 x 257 map falls back to a slow
	# triangle mesh. So the collider is 321 x 321 (z in [-160, 160]): the extra rows beyond z = +-128 lie
	# under the boundary hills and repeat the edge rows. Inside the grid it is exactly h.
	var pad := (NX - NZ) / 2
	var first := h.slice(0, NX)
	var last := h.slice((NZ - 1) * NX, NZ * NX)
	var sq := PackedFloat32Array()
	for j in pad:
		sq.append_array(first)
	sq.append_array(h)
	for j in pad:
		sq.append_array(last)
	shape.map_width = NX
	shape.map_depth = NX
	shape.map_data = sq
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


func height_image() -> Image:
	return Image.create_from_data(NX, NZ, false, Image.FORMAT_RF, h.to_byte_array())


func color_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(NX * NZ * 4)
	for k in col.size():
		var c: Color = col[k]
		var b := k * 4
		bytes[b] = c.r8
		bytes[b + 1] = c.g8
		bytes[b + 2] = c.b8
		bytes[b + 3] = 255
	return Image.create_from_data(NX, NZ, false, Image.FORMAT_RGBA8, bytes)


func splat_image() -> Image:
	return Image.create_from_data(NX, NZ, false, Image.FORMAT_RGBA8, splat)


func grass_image() -> Image:
	return Image.create_from_data(NX, NZ, false, Image.FORMAT_RGBA8, grass)


## Clears grass density in a small radius (so props such as sticks and stones aren't hidden).
func clear_grass(x: float, z: float, radius: float) -> void:
	if grass.is_empty():
		return
	var i0 := clampi(int(floor(x - radius + HALF_X)), 0, NX - 1)
	var i1 := clampi(int(ceil(x + radius + HALF_X)), 0, NX - 1)
	var j0 := clampi(int(floor(z - radius + HALF_Z)), 0, NZ - 1)
	var j1 := clampi(int(ceil(z + radius + HALF_Z)), 0, NZ - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(float(i) - HALF_X - x, float(j) - HALF_Z - z).length()
			if d <= radius:
				var k := (j * NX + i) * 4
				grass[k] = int(float(grass[k]) * clampf(d / radius, 0.0, 1.0) * 0.5)
