extends RefCounted
## Ashbell Quarry ground: the pure height function (local frame of data/reach_east.gd) and the terrain pass
## used by src/world/reach/districts/quarry.gd shape_terrain(). Deterministic, allocation-light, and it only
## ever edits samples strictly inside the hr_quarry landmark circle.
##   Shape.to_local(x, z) / Shape.to_world(uv)            frame conversions (Vector2 x/z <-> U/V)
##   Shape.level_at_local(u, v) -> float                   design height above the floor (ramps included)
##   Shape.weight_at(x, z) -> float                        0..1 shaping weight (rim, arch and north mouth blends)
##   Shape.shaped_height(x, z, natural, floor_y) -> float  what the terrain becomes at (x, z)
##   Shape.apply(terrain) -> Dictionary                    shapes a Reach terrain (see reach_terrain.gd API)
## apply() works with the region terrain (h / NX / NZ / HALF_X / HALF_Z, tint_disc, add_stone_disc, mark_path)
## and, for robustness, any heightfield exposing a PackedFloat32Array `h` or `heights` with NX/NZ (or N) and
## HALF_X/HALF_Z (or HALF, ORIGIN); a terrain it cannot read is left untouched (warning, never a crash).

const Q := preload("res://data/reach_east.gd")

## The last apply() report (tests / QA): {ok, floor, samples, grid, reason}.
static var last_report: Dictionary = {}


static func to_local(x: float, z: float) -> Vector2:
	var d := Vector2(x - Q.CENTER.x, z - Q.CENTER.y)
	return Vector2(d.dot(Q.AXIS_U), d.dot(Q.AXIS_V))


static func to_world(uv: Vector2) -> Vector2:
	return Q.CENTER + Q.AXIS_U * uv.x + Q.AXIS_V * uv.y


## Ramp dictionary covering local (u, v), or {} when none.
static func ramp_at_local(u: float, v: float) -> Dictionary:
	for r in Q.RAMPS:
		var ur: Array = r["u"]
		var vr: Array = r["v"]
		if u >= float(ur[0]) and u <= float(ur[1]) and v >= float(vr[0]) and v <= float(vr[1]):
			return r
	return {}


## Terrace index (0 apron, 1, 2, 3 shelf) at local (u, v), ignoring ramps.
static func terrace_at_local(u: float, v: float) -> int:
	if u < float(Q.STEP_U[0]):
		return 0
	if u < float(Q.STEP_U[1]):
		return 1
	if u < Q.U_CLIFF or v < Q.SHELF_WEST_V:
		return 2
	return 3


## Design height above the quarry floor at local (u, v).
static func level_at_local(u: float, v: float) -> float:
	var r := ramp_at_local(u, v)
	if not r.is_empty():
		var ur: Array = r["u"]
		var hr: Array = r["h"]
		var t := clampf((u - float(ur[0])) / (float(ur[1]) - float(ur[0])), 0.0, 1.0)
		return lerpf(float(hr[0]), float(hr[1]), t)
	return float(Q.LEVELS[terrace_at_local(u, v)])


## True when (x, z) is on the upper shelf (the winch-gated part), rim blend excluded.
static func is_shelf(x: float, z: float) -> bool:
	var l := to_local(x, z)
	return terrace_at_local(l.x, l.y) == 3 and Vector2(x, z).distance_to(Q.CENTER) <= Q.RIM_FLAT


static func weight_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.distance_to(Q.CENTER)
	if r >= Q.RIM_OUT:
		return 0.0
	var w := 1.0 - smoothstep(Q.RIM_FLAT, Q.RIM_OUT, r)
	w *= smoothstep(float(Q.ARCH_KEEP[0]), float(Q.ARCH_KEEP[1]), p.distance_to(Q.ARCH))
	w *= smoothstep(float(Q.NORTH_KEEP[0]), float(Q.NORTH_KEEP[1]), p.distance_to(Q.NORTH_MOUTH))
	return w


static func shaped_height(x: float, z: float, natural: float, floor_y: float) -> float:
	var w := weight_at(x, z)
	if w <= 0.0:
		return natural
	var l := to_local(x, z)
	return lerpf(natural, floor_y + level_at_local(l.x, l.y), w)


# --- Terrain pass ------------------------------------------------------------------------------------------

## Shapes `terrain` in place. Returns (and stores in last_report) {ok, floor, samples, grid, reason}.
static func apply(terrain: Object) -> Dictionary:
	var rep := {"ok": false, "floor": 0.0, "samples": 0, "grid": {}, "reason": ""}
	last_report = rep
	if terrain == null:
		rep["reason"] = "no terrain"
		push_warning("Ashbell Quarry: shape_terrain got no terrain; the quarry ground is left as it is")
		return rep
	var grid := detect_grid(terrain)
	if grid.is_empty():
		rep["reason"] = "unknown terrain layout"
		push_warning("Ashbell Quarry: can't read this terrain's height grid; the quarry ground is left as it is")
		return rep
	var arr_name := String(grid["array"])
	var arr: PackedFloat32Array = terrain.get(arr_name)
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var x0: float = grid["x0"]
	var z0: float = grid["z0"]
	var st: float = grid["step"]
	var floor_y := floor_level(terrain, arr, grid)
	var reach := Q.RIM_OUT
	var i0 := clampi(int(floor((Q.CENTER.x - reach - x0) / st)), 0, nx - 1)
	var i1 := clampi(int(ceil((Q.CENTER.x + reach - x0) / st)), 0, nx - 1)
	var j0 := clampi(int(floor((Q.CENTER.y - reach - z0) / st)), 0, nz - 1)
	var j1 := clampi(int(ceil((Q.CENTER.y + reach - z0) / st)), 0, nz - 1)
	var n := 0
	for j in range(j0, j1 + 1):
		var z := z0 + float(j) * st
		for i in range(i0, i1 + 1):
			var x := x0 + float(i) * st
			if Vector2(x, z).distance_to(Q.CENTER) >= Q.RIM_OUT:
				continue
			var k := j * nx + i
			var nv := shaped_height(x, z, arr[k], floor_y)
			if nv != arr[k]:
				arr[k] = nv
				n += 1
	terrain.set(arr_name, arr)
	_decorate(terrain)
	rep["ok"] = true
	rep["floor"] = floor_y
	rep["samples"] = n
	rep["grid"] = grid
	return rep


## Floor height G: the region's quarry-arch plaza (so the yard meets the arch), else the natural ground there.
static func floor_level(terrain: Object, arr: PackedFloat32Array, grid: Dictionary) -> float:
	if terrain.has_method("plaza_height"):
		var ph: Variant = terrain.get("plaza_heights")
		if ph is Dictionary and (ph as Dictionary).has("quarry_arch"):
			return float(terrain.call("plaza_height", "quarry_arch"))
	return sample(arr, grid, Q.ARCH)


## Nearest-sample read of a grid array at (x, z).
static func sample(arr: PackedFloat32Array, grid: Dictionary, p: Vector2) -> float:
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var st: float = grid["step"]
	var i := clampi(int(round((p.x - float(grid["x0"])) / st)), 0, nx - 1)
	var j := clampi(int(round((p.y - float(grid["z0"])) / st)), 0, nz - 1)
	return arr[j * nx + i]


## Ground colour, stone footsteps and dirt roads through the region terrain's own helpers (all clamped to
## the district's shaping limit by the terrain). Silently skipped on terrains without them.
static func _decorate(terrain: Object) -> void:
	if terrain.has_method("tint_disc"):
		for t in Q.TINTS:
			terrain.call("tint_disc", to_world(Vector2(float(t[0]), float(t[1]))), float(t[2]), float(t[3]), t[4], float(t[5]))
	if terrain.has_method("add_stone_disc"):
		terrain.call("add_stone_disc", Q.CENTER, Q.RIM_FLAT - 0.6)
	# the quarry's cut faces are its own copper stone, not the region's pale grey rock (no pale "teeth" between
	# the cliff boulders)
	if terrain.has_method("paint_rock_disc"):
		terrain.call("paint_rock_disc", Q.CENTER, Q.RIM_OUT + 1.0, Q.COL_ROCK_DARK)
	if terrain.has_method("mark_path"):
		for road in Q.ROADS:
			var pts: Array = []
			for uv in road["points"]:
				pts.append(to_world(uv))
			terrain.call("mark_path", pts, float(road["half"]), 0.85)


## Reads the height grid layout: {array, nx, nz, x0, z0, step} or {} when unknown.
static func detect_grid(t: Object) -> Dictionary:
	var arr_name := ""
	for n in ["h", "heights", "height_data"]:
		var v: Variant = _prop(t, n)
		if v is PackedFloat32Array and not (v as PackedFloat32Array).is_empty():
			arr_name = n
			break
	if arr_name == "":
		return {}
	var size: int = (t.get(arr_name) as PackedFloat32Array).size()
	var nx := _int_prop(t, ["NX", "nx", "SIZE_X", "N", "SIZE"])
	var nz := _int_prop(t, ["NZ", "nz", "SIZE_Z", "N", "SIZE"])
	if nx <= 0 and nz <= 0:
		var s := int(round(sqrt(float(size))))
		if s * s != size:
			return {}
		nx = s
		nz = s
	elif nx <= 0:
		nx = size / nz
	elif nz <= 0:
		nz = size / nx
	if nx <= 1 or nz <= 1 or nx * nz != size:
		return {}
	var st := _float_prop(t, ["STEP", "SPACING", "CELL"], 1.0)
	if st <= 0.0:
		st = 1.0
	var cands: Array = []
	var o: Variant = _prop(t, "ORIGIN")
	if o is Vector2:
		cands.append(Vector2(o))
	var hx: Variant = _prop(t, "HALF_X")
	var hz: Variant = _prop(t, "HALF_Z")
	if (hx is float or hx is int) and (hz is float or hz is int):
		cands.append(Vector2(-float(hx), -float(hz)))
	var hh: Variant = _prop(t, "HALF")
	if hh is float or hh is int:
		cands.append(Vector2(-float(hh), -float(hh)))
	cands.append(Vector2(-float(nx - 1) * st * 0.5, -float(nz - 1) * st * 0.5))
	var arr: PackedFloat32Array = t.get(arr_name)
	for c in cands:
		var g := {"array": arr_name, "nx": nx, "nz": nz, "x0": float(c.x), "z0": float(c.y), "step": st}
		if _verify(t, arr, g):
			return g
	return {}


## With a height_at() query, the candidate mapping must reproduce the array at a few vertices.
static func _verify(t: Object, arr: PackedFloat32Array, g: Dictionary) -> bool:
	if not t.has_method("height_at"):
		return true
	var nx: int = g["nx"]
	var nz: int = g["nz"]
	var st: float = g["step"]
	var probes := [Q.CENTER, Q.CENTER + Vector2(7.0, -5.0), Q.CENTER + Vector2(-9.0, 11.0), Q.CENTER + Vector2(3.0, 13.0)]
	for p in probes:
		var i := clampi(int(round((p.x - float(g["x0"])) / st)), 1, nx - 2)
		var j := clampi(int(round((p.y - float(g["z0"])) / st)), 1, nz - 2)
		var x := float(g["x0"]) + float(i) * st
		var z := float(g["z0"]) + float(j) * st
		var hv: Variant = t.call("height_at", x, z)
		if not (hv is float or hv is int):
			return false
		if absf(float(hv) - arr[j * nx + i]) > 0.001:
			return false
	return true


static func _prop(t: Object, n: String) -> Variant:
	var v: Variant = t.get(n)
	if v != null:
		return v
	var s: Variant = t.get_script()
	if s is Script:
		var cm: Dictionary = (s as Script).get_script_constant_map()
		if cm.has(n):
			return cm[n]
	return null


static func _int_prop(t: Object, names: Array) -> int:
	for n in names:
		var v: Variant = _prop(t, String(n))
		if v is int or v is float:
			return int(v)
	return 0


static func _float_prop(t: Object, names: Array, def: float) -> float:
	for n in names:
		var v: Variant = _prop(t, String(n))
		if v is int or v is float:
			return float(v)
	return def
