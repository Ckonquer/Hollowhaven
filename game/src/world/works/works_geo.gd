extends RefCounted
## Room-table helpers for the Hushed Works (static, pure): the merged room table of data/works_layout.gd
## (rooms 1-8) + data/works_layout_deep.gd (rooms 9-14), room / zone lookups that respect each room's
## vertical range, floors of sloped passages, and the sloped-passage builder used by both works modules.

const Builder := preload("res://src/world/below/below_builder.gd")

const UP := Vector3.UP


## Merges the two room tables. Rooms 1-8 win on an id clash (reported in "conflicts").
## Returns {"rooms": Dictionary, "conflicts": Array[String]}.
static func merge_rooms(upper: Dictionary, deep: Dictionary) -> Dictionary:
	var out: Dictionary = upper.duplicate(true)
	var conflicts: Array = []
	for id in deep:
		if out.has(id):
			conflicts.append(String(id))
			continue
		out[id] = (deep[id] as Dictionary).duplicate(true)
	return {"rooms": out, "conflicts": conflicts}


## The ROOMS constant of a layout script ({} when the file is missing or broken).
static func load_rooms(path: String) -> Dictionary:
	if path == "" or not ResourceLoader.exists(path):
		return {}
	var s: Variant = load(path)
	if not (s is Script):
		return {}
	var consts: Dictionary = (s as Script).get_script_constant_map()
	var r: Variant = consts.get("ROOMS", {})
	return r if r is Dictionary else {}


static func room_y_range(r: Dictionary) -> Vector2:
	var y: float = float(r["y"])
	var lo: float = float(r.get("ylo", y - 1.0))
	var hi: float = float(r.get("yhi", y + float(r["h"]) + 0.5))
	return Vector2(lo, hi)


static func room_center(r: Dictionary) -> Vector3:
	var cx := (float(r["x0"]) + float(r["x1"])) * 0.5
	var cz := (float(r["z0"]) + float(r["z1"])) * 0.5
	return Vector3(cx, floor_y_at(r, cx, cz), cz)


static func contains_xz(r: Dictionary, pos: Vector3) -> bool:
	return pos.x >= float(r["x0"]) and pos.x <= float(r["x1"]) and pos.z >= float(r["z0"]) and pos.z <= float(r["z1"])


## Room id containing pos ("" if none). Boxes overlapping on XZ are told apart by their y range.
static func room_at(rooms: Dictionary, pos: Vector3) -> String:
	for id in rooms:
		var r: Dictionary = rooms[id]
		var yr := room_y_range(r)
		if pos.y < yr.x or pos.y > yr.y:
			continue
		if contains_xz(r, pos):
			return String(id)
	return ""


## Nearest room by distance to its box (vertical distance counts double), for points just outside.
static func nearest_room(rooms: Dictionary, pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for id in rooms:
		var r: Dictionary = rooms[id]
		var yr := room_y_range(r)
		var dy: float = 0.0
		if pos.y < yr.x:
			dy = yr.x - pos.y
		elif pos.y > yr.y:
			dy = pos.y - yr.y
		var dx: float = maxf(maxf(float(r["x0"]) - pos.x, 0.0), pos.x - float(r["x1"]))
		var dz: float = maxf(maxf(float(r["z0"]) - pos.z, 0.0), pos.z - float(r["z1"]))
		var d := Vector3(dx, dy * 2.0, dz).length()
		if d < best_d:
			best_d = d
			best = String(id)
	return best


static func zone_of_room(rooms: Dictionary, room_id: String) -> String:
	return String((rooms.get(room_id, {}) as Dictionary).get("zone", ""))


## Floor height inside a room at (x, z): flat rooms return y, sloped passages interpolate their slope.
static func floor_y_at(r: Dictionary, x: float, z: float) -> float:
	var s: Variant = r.get("slope")
	if not (s is Dictionary):
		return float(r["y"])
	var sd: Dictionary = s
	var y0: float = float(sd["y0"])
	var y1: float = float(sd["y1"])
	var t: float
	if String(sd.get("axis", "x")) == "x":
		t = inverse_lerp(float(r["x0"]), float(r["x1"]), x)
	else:
		t = inverse_lerp(float(r["z0"]), float(r["z1"]), z)
	return lerpf(y0, y1, clampf(t, 0.0, 1.0))


## Builds a sloped passage from its table entry: ramp (or stairs over a ramp collider) along the slope axis,
## a tilted ceiling slab h above the floor, full-height side walls between the neighbours' wall slabs and an
## optional end cap (entry "cap": "n" | "s" | "w" | "e"). Call between b.begin(id) and b.finish().
static func sloped_passage(b: Builder, id: String, floor_col: Color, wall_col: Color, ceil_col: Color, edge_col: Color, step_rise: float = 0.22) -> void:
	var r: Dictionary = b.rooms[id]
	var s: Dictionary = r["slope"]
	var axis := String(s.get("axis", "x"))
	var y0: float = float(s["y0"])
	var y1: float = float(s["y1"])
	var h: float = float(r["h"])
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	var a: Vector3
	var c: Vector3
	var width: float
	if axis == "x":
		var zm := (z0 + z1) * 0.5
		a = Vector3(x0, y0, zm)
		c = Vector3(x1, y1, zm)
		width = z1 - z0
	else:
		var xm := (x0 + x1) * 0.5
		a = Vector3(xm, y0, z0)
		c = Vector3(xm, y1, z1)
		width = x1 - x0
	if bool(r.get("stairs", false)):
		b.stairs(a, c, width, step_rise, floor_col, edge_col)
	else:
		b.ramp(a, c, width, floor_col)
	# Ceiling: a slab parallel to the floor, its underside h above it.
	b.ramp(a + UP * (h + 0.5), c + UP * (h + 0.5), width + 2.0, ceil_col, "stone", true, 0.5)
	var lo := minf(y0, y1) - 0.6
	var hi := maxf(y0, y1) + h + 0.6
	var cy := (lo + hi) * 0.5
	var sy := hi - lo
	var cap := String(r.get("cap", ""))
	# Side walls run between the neighbouring rooms' wall slabs (they already close the first/last metre).
	if axis == "x":
		var wa := x0 + (0.0 if cap == "w" else Builder.WALL_T)
		var wb := x1 - (0.0 if cap == "e" else Builder.WALL_T)
		for side_z in [z0 - 0.5, z1 + 0.5]:
			b.solid(Vector3((wa + wb) * 0.5, cy, side_z), Vector3(wb - wa, sy, 1.0), wall_col)
	else:
		var wa := z0 + (0.0 if cap == "n" else Builder.WALL_T)
		var wb := z1 - (0.0 if cap == "s" else Builder.WALL_T)
		for side_x in [x0 - 0.5, x1 + 0.5]:
			b.solid(Vector3(side_x, cy, (wa + wb) * 0.5), Vector3(1.0, sy, wb - wa), wall_col)
	match cap:
		"w":
			b.solid(Vector3(x0 - 0.5, cy, (z0 + z1) * 0.5), Vector3(1.0, sy, z1 - z0 + 2.0), wall_col)
		"e":
			b.solid(Vector3(x1 + 0.5, cy, (z0 + z1) * 0.5), Vector3(1.0, sy, z1 - z0 + 2.0), wall_col)
		"n":
			b.solid(Vector3((x0 + x1) * 0.5, cy, z0 - 0.5), Vector3(x1 - x0 + 2.0, sy, 1.0), wall_col)
		"s":
			b.solid(Vector3((x0 + x1) * 0.5, cy, z1 + 0.5), Vector3(x1 - x0 + 2.0, sy, 1.0), wall_col)


## Every wall opening of a room as [side, from, to, height] (tests and dressing).
static func openings(r: Dictionary) -> Array:
	var out: Array = []
	var od: Dictionary = r.get("open", {})
	for side in od:
		var v: Variant = od[side]
		if v is Array:
			for o in v:
				out.append([String(side), float(o[0]), float(o[1]), float(o[2])])
	return out
