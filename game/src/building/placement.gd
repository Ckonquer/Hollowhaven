extends RefCounted
## Pure placement rules for the Haven build system: grid snapping, footprints, occupancy layers,
## validation and the "never shut Krystal in" rule. No scene access: everything the rules need comes
## in through a `ctx` Dictionary, so the logic is unit-testable. BuildMode fills ctx from the scene.
##
## Grid (see data/structures.gd):
##   cell    footprint on the 1 m grid, rotation 0/90/180/270 (size swaps at 90/270)
##   floor2  2x2 m tile on the even 2 m grid
##   edge2   2 m wall on a 2 m grid line; rot 0 = along X (line z = 2m), rot 90 = along Z (line x = 2k)
##   roof2   2x2 m tile at wall height on top of walls
## Edge keys are Vector3i(k, m, dir): dir 0 spans x in [2k, 2k+2] at z = 2m, dir 1 spans z in [2m, 2m+2]
## at x = 2k. Cell keys are Vector2i(x, z) for the 1 m cell [x, x+1] x [z, z+1].
##
## ctx keys (all optional):
##   structures: Dictionary   GameState.structures-shaped records (default GameState.structures)
##   area_id: String          only records of this area count (default "surface")
##   build_area: Dictionary   {"center": Vector2, "radius": float, "blocked": [{"center", "radius", "name"?}]}
##                            missing/empty = building not allowed here at all
##   height_fn: Callable      (x: float, z: float) -> float ground height; missing = flat at pos.y
##   player_pos: Vector3      used for the enclosure rule
##   physics_fn: Callable     (structure_id, pos: Vector3, rot: int) -> String ("" = clear) for live checks
##   occupancy: Dictionary    cached build_occupancy() result (rebuilt when missing)

const TILE := 2.0
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.22
const FLOOR_TOP := 0.12          # walkable top of a wooden floor tile
const MAX_UNEVEN := 0.45         # max ground height difference across a footprint (m)
const OBSTACLE_SHRINK := 0.7     # blocked circles count as solid obstacles at this fraction of their radius

const MSG_OUTSIDE := "You can only build at the Haven"
const MSG_CLEAR := "This spot needs to stay clear"
const MSG_UNEVEN := "The ground is too bumpy here"
const MSG_ROOF := "Roofs need a wall to rest on"
const MSG_ENCLOSE := "That would shut you in! Leave a doorway"


# --- Basics -------------------------------------------------------------------------------------

static func def_of(structure_id: String) -> Dictionary:
	return ItemDB.structure(structure_id)


static func snap_kind(def: Dictionary) -> String:
	return String(def.get("snap", "cell"))


## Rotation normalised to 0/90/180/270 (edge2 walls: 0/90).
static func norm_rot(snap: String, rot_deg: float) -> int:
	var r := posmod(int(roundf(rot_deg / 90.0)) * 90, 360)
	if snap == "edge2":
		r = r % 180
	return r


## Next rotation step for the R key.
static func next_rot(snap: String, rot_deg: float) -> int:
	return norm_rot(snap, float(norm_rot(snap, rot_deg) + 90))


static func rotated_size(def: Dictionary, rot: int) -> Vector2i:
	var s: Vector2i = def.get("size", Vector2i.ONE)
	if rot == 90 or rot == 270:
		return Vector2i(s.y, s.x)
	return s


static func vec_from(p: Variant) -> Vector3:
	if p is Vector3:
		return p
	if p is Array and p.size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.ZERO


## Snaps a free point (e.g. where the camera ray hits the ground) to the structure's grid.
## Returns the structure origin (footprint centre, bottom) with y = point.y (see placement_y()).
static func snap_position(def: Dictionary, point: Vector3, rot_deg: float) -> Vector3:
	var snap := snap_kind(def)
	var rot := norm_rot(snap, rot_deg)
	match snap:
		"floor2", "roof2":
			return Vector3(floorf(point.x / TILE) * TILE + 1.0, point.y, floorf(point.z / TILE) * TILE + 1.0)
		"edge2":
			if rot == 0:
				return Vector3(floorf(point.x / TILE) * TILE + 1.0, point.y, roundf(point.z / TILE) * TILE)
			return Vector3(roundf(point.x / TILE) * TILE, point.y, floorf(point.z / TILE) * TILE + 1.0)
		_:
			var s := rotated_size(def, rot)
			var ix := roundf(point.x - float(s.x) * 0.5)
			var iz := roundf(point.z - float(s.y) * 0.5)
			return Vector3(ix + float(s.x) * 0.5, point.y, iz + float(s.y) * 0.5)


## {"layer", "cells": [Vector2i], "edges": [Vector3i], "rect": Rect2 (x,z world), "rot": int}
static func footprint(def: Dictionary, pos: Vector3, rot_deg: float) -> Dictionary:
	var snap := snap_kind(def)
	var rot := norm_rot(snap, rot_deg)
	var cells: Array = []
	var edges: Array = []
	var rect := Rect2()
	match snap:
		"floor2", "roof2":
			var tx := int(floorf(pos.x / TILE))
			var tz := int(floorf(pos.z / TILE))
			for dx in 2:
				for dz in 2:
					cells.append(Vector2i(tx * 2 + dx, tz * 2 + dz))
			rect = Rect2(tx * 2, tz * 2, 2, 2)
		"edge2":
			if rot == 0:
				var k := int(floorf(pos.x / TILE))
				var m := int(roundf(pos.z / TILE))
				edges.append(Vector3i(k, m, 0))
				rect = Rect2(k * 2, m * 2 - WALL_THICKNESS * 0.5, 2, WALL_THICKNESS)
			else:
				var k := int(roundf(pos.x / TILE))
				var m := int(floorf(pos.z / TILE))
				edges.append(Vector3i(k, m, 1))
				rect = Rect2(k * 2 - WALL_THICKNESS * 0.5, m * 2, WALL_THICKNESS, 2)
		_:
			var s := rotated_size(def, rot)
			var ix := int(roundf(pos.x - float(s.x) * 0.5))
			var iz := int(roundf(pos.z - float(s.y) * 0.5))
			for dx in s.x:
				for dz in s.y:
					cells.append(Vector2i(ix + dx, iz + dz))
			rect = Rect2(ix, iz, s.x, s.y)
	return {"layer": String(def.get("layer", "object")), "cells": cells, "edges": edges, "rect": rect, "rot": rot}


# --- Occupancy ------------------------------------------------------------------------------------

static func _records(ctx: Dictionary) -> Dictionary:
	var s: Variant = ctx.get("structures")
	return s if s is Dictionary else GameState.structures


static func _area(ctx: Dictionary) -> String:
	return String(ctx.get("area_id", "surface"))


## {layer: {Vector2i|Vector3i: uid}} for every structure of `area_id`.
static func build_occupancy(structures: Dictionary, area_id: String) -> Dictionary:
	var occ := {}
	for uid in structures:
		var rec: Dictionary = structures[uid]
		if String(rec.get("area", "surface")) != area_id:
			continue
		var def := def_of(String(rec.get("id", "")))
		if def.is_empty():
			continue
		var fp := footprint(def, vec_from(rec.get("pos")), float(rec.get("rot", 0.0)))
		var layer: String = fp["layer"]
		if not occ.has(layer):
			occ[layer] = {}
		var lm: Dictionary = occ[layer]
		for c in fp["cells"]:
			lm[c] = uid
		for e in fp["edges"]:
			lm[e] = uid
	return occ


static func _occupancy(ctx: Dictionary) -> Dictionary:
	var o: Variant = ctx.get("occupancy")
	if o is Dictionary:
		return o
	var built := build_occupancy(_records(ctx), _area(ctx))
	ctx["occupancy"] = built
	return built


## uid of the structure occupying any of the footprint's cells/edges in its layer ("" if free).
static func overlap_uid(fp: Dictionary, occ: Dictionary) -> String:
	var lm: Dictionary = occ.get(fp["layer"], {})
	for c in fp["cells"]:
		if lm.has(c):
			return String(lm[c])
	for e in fp["edges"]:
		if lm.has(e):
			return String(lm[e])
	return ""


## Structure uid at a ground point, preferring objects, then walls within `edge_tolerance`, then floors.
static func structure_at_point(point: Vector3, ctx: Dictionary, edge_tolerance: float = 0.45) -> String:
	var occ := _occupancy(ctx)
	var cell := Vector2i(int(floorf(point.x)), int(floorf(point.z)))
	for layer in occ:
		if layer == "floor" or layer == "roof" or layer == "edge":
			continue
		if occ[layer].has(cell):
			return String(occ[layer][cell])
	var edges: Dictionary = occ.get("edge", {})
	if not edges.is_empty():
		var best := ""
		var best_d := edge_tolerance
		var kx := int(floorf(point.x / TILE))
		var kz := int(floorf(point.z / TILE))
		var candidates := [Vector3i(kx, int(roundf(point.z / TILE)), 0), Vector3i(int(roundf(point.x / TILE)), kz, 1)]
		for e in candidates:
			if edges.has(e):
				var d: float = absf(point.z - float(e.y) * TILE) if e.z == 0 else absf(point.x - float(e.x) * TILE)
				if d <= best_d:
					best_d = d
					best = String(edges[e])
		if best != "":
			return best
	var floors: Dictionary = occ.get("floor", {})
	if floors.has(cell):
		return String(floors[cell])
	return ""


# --- Heights ----------------------------------------------------------------------------------------

static func ground_at(x: float, z: float, fallback_y: float, ctx: Dictionary) -> float:
	var f: Variant = ctx.get("height_fn")
	if f is Callable and (f as Callable).is_valid():
		var h: Variant = (f as Callable).call(x, z)
		if h is float or h is int:
			return float(h)
	return fallback_y


static func _sample_points(rect: Rect2) -> Array:
	var inset := 0.08
	var r: Rect2 = rect.grow(-inset) if rect.size.x > inset * 3.0 and rect.size.y > inset * 3.0 else rect
	return [r.get_center(), r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]


## Final y of a structure placed at `pos` (bottom of the model).
static func placement_y(structure_id: String, pos: Vector3, rot_deg: float, ctx: Dictionary) -> float:
	var def := def_of(structure_id)
	var fp := footprint(def, pos, rot_deg)
	var rect: Rect2 = fp["rect"]
	var hs: Array = []
	for p in _sample_points(rect):
		hs.append(ground_at(p.x, p.y, pos.y, ctx))
	var hmin: float = hs.min()
	var hmax: float = hs.max()
	var centre: float = hs[0]
	match snap_kind(def):
		"floor2":
			return hmax
		"edge2":
			return hmin
		"roof2":
			var base := _roof_base(fp, ctx)
			if base > -INF:
				return base + WALL_HEIGHT
			# Held up by a neighbouring roof tile only: line up with it (never with the ground below).
			var nb := _neighbour_roof_y(fp, ctx)
			return nb if nb > -INF else centre + WALL_HEIGHT
	# Objects stand on a floor tile if one covers any of their cells.
	var top := -INF
	var floors: Dictionary = _occupancy(ctx).get("floor", {})
	var recs := _records(ctx)
	for c in fp["cells"]:
		if floors.has(c) and recs.has(floors[c]):
			top = maxf(top, vec_from(recs[floors[c]].get("pos")).y + FLOOR_TOP)
	if def.get("layer", "object") != "floor" and top > -INF:
		return maxf(top, centre)
	return centre


## Highest base y of the walls around a roof tile (-INF if none).
static func _roof_base(fp: Dictionary, ctx: Dictionary) -> float:
	var base := -INF
	var edges: Dictionary = _occupancy(ctx).get("edge", {})
	var recs := _records(ctx)
	for e in tile_edges(fp):
		if edges.has(e) and recs.has(edges[e]):
			base = maxf(base, vec_from(recs[edges[e]].get("pos")).y)
	return base


## Highest y of the wall-supported roof tiles right next to a roof footprint (-INF if none).
static func _neighbour_roof_y(fp: Dictionary, ctx: Dictionary) -> float:
	var occ := _occupancy(ctx)
	var edges: Dictionary = occ.get("edge", {})
	var roofs: Dictionary = occ.get("roof", {})
	var recs := _records(ctx)
	var rect: Rect2 = fp["rect"]
	var y := -INF
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c := Vector2i(int(rect.position.x) + d.x, int(rect.position.y) + d.y)
		if not roofs.has(c) or not recs.has(roofs[c]):
			continue
		for e in tile_edges({"rect": Rect2(c.x, c.y, 2, 2)}):
			if edges.has(e):
				y = maxf(y, vec_from(recs[roofs[c]].get("pos")).y)
				break
	return y


## The 4 wall edges around a 2x2 tile footprint.
static func tile_edges(fp: Dictionary) -> Array:
	var rect: Rect2 = fp["rect"]
	var tx := int(floorf(rect.position.x / TILE))
	var tz := int(floorf(rect.position.y / TILE))
	return [Vector3i(tx, tz, 0), Vector3i(tx, tz + 1, 0), Vector3i(tx, tz, 1), Vector3i(tx + 1, tz, 1)]


## A roof tile is supported by a wall on one of its edges, or by a neighbouring roof tile that is.
static func roof_supported(fp: Dictionary, ctx: Dictionary) -> bool:
	var occ := _occupancy(ctx)
	var edges: Dictionary = occ.get("edge", {})
	for e in tile_edges(fp):
		if edges.has(e):
			return true
	var roofs: Dictionary = occ.get("roof", {})
	var rect: Rect2 = fp["rect"]
	var ox := int(rect.position.x)
	var oz := int(rect.position.y)
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c := Vector2i(ox + d.x, oz + d.y)
		if roofs.has(c):
			var nfp := {"rect": Rect2(c.x, c.y, 2, 2)}
			for e in tile_edges(nfp):
				if edges.has(e):
					return true
	return false


# --- Build area ------------------------------------------------------------------------------------

static func rect_inside_circle(rect: Rect2, center: Vector2, radius: float) -> bool:
	for p in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		if (p as Vector2).distance_to(center) > radius:
			return false
	return true


static func rect_hits_circle(rect: Rect2, center: Vector2, radius: float) -> bool:
	var cx := clampf(center.x, rect.position.x, rect.end.x)
	var cz := clampf(center.y, rect.position.y, rect.end.y)
	return Vector2(cx, cz).distance_to(center) < radius


static func in_build_area(point: Vector3, build_area: Dictionary) -> bool:
	if build_area.is_empty():
		return false
	return Vector2(point.x, point.z).distance_to(build_area.get("center", Vector2.ZERO)) <= float(build_area.get("radius", 0.0))


# --- Validation ----------------------------------------------------------------------------------------

## Full rule check. Returns {"ok": bool, "reason": String, "blocker": uid ("" if none), "y": float}.
static func validate(structure_id: String, pos: Vector3, rot_deg: float, ctx: Dictionary) -> Dictionary:
	var def := def_of(structure_id)
	if def.is_empty():
		return _res(false, "That can't be built", "", pos.y)
	var fp := footprint(def, pos, rot_deg)
	var rect: Rect2 = fp["rect"]
	var y := placement_y(structure_id, pos, rot_deg, ctx)
	var ba: Variant = ctx.get("build_area")
	if not (ba is Dictionary) or (ba as Dictionary).is_empty():
		return _res(false, MSG_OUTSIDE, "", y)
	if not rect_inside_circle(rect, ba.get("center", Vector2.ZERO), float(ba.get("radius", 0.0))):
		return _res(false, MSG_OUTSIDE, "", y)
	for b in ba.get("blocked", []):
		if rect_hits_circle(rect, b.get("center", Vector2.ZERO), float(b.get("radius", 0.0))):
			var nm: String = String(b.get("name", ""))
			return _res(false, ("Too close to the %s" % nm) if nm != "" else MSG_CLEAR, "", y)
	var blocker := overlap_uid(fp, _occupancy(ctx))
	if blocker != "":
		var rec: Dictionary = _records(ctx).get(blocker, {})
		var nm2: String = String(def_of(String(rec.get("id", ""))).get("name", "something"))
		return _res(false, "The %s is in the way" % nm2, blocker, y)
	if snap_kind(def) == "roof2":
		if not roof_supported(fp, ctx):
			return _res(false, MSG_ROOF, "", y)
	else:
		var hs: Array = []
		for p in _sample_points(rect):
			hs.append(ground_at(p.x, p.y, pos.y, ctx))
		if float(hs.max()) - float(hs.min()) > MAX_UNEVEN:
			return _res(false, MSG_UNEVEN, "", y)
	if blocks_movement(def) and ctx.get("player_pos") is Vector3:
		# Refuse only pieces that would *cause* the enclosure (if she's already in a pen, e.g. after
		# hopping a fence, building elsewhere stays possible; dismantling always opens things up).
		if would_enclose(ctx["player_pos"], ctx, fp) and not would_enclose(ctx["player_pos"], ctx):
			return _res(false, MSG_ENCLOSE, "", y)
	var pf: Variant = ctx.get("physics_fn")
	if pf is Callable and (pf as Callable).is_valid():
		var why: Variant = (pf as Callable).call(structure_id, Vector3(pos.x, y, pos.z), int(fp["rot"]))
		if why is String and why != "":
			return _res(false, why, "", y)
	return _res(true, "", "", y)


static func _res(ok: bool, reason: String, blocker: String, y: float) -> Dictionary:
	return {"ok": ok, "reason": reason, "blocker": blocker, "y": y}


## Solid, ground-level pieces that stop Krystal walking (doorways and floors don't).
static func blocks_movement(def: Dictionary) -> bool:
	if not bool(def.get("solid", false)) or bool(def.get("passable", false)):
		return false
	var layer: String = String(def.get("layer", "object"))
	return layer != "floor" and layer != "roof"


# --- Enclosure rule --------------------------------------------------------------------------------------

## True if the player at `player_pos` would have no way out after adding `extra_fp` (optional).
## Flood fill on the 1 m grid: solid objects block cells, non-passable walls block cell crossings,
## blocked circles (Ward Stone, campfire...) count as obstacles. Reaching the ring outside the bounding
## box of all obstacles means there is a way out.
static func would_enclose(player_pos: Vector3, ctx: Dictionary, extra_fp: Dictionary = {}) -> bool:
	var solid_cells := {}
	var walls := {}           # Vector3i(line_coord, cell_coord, dir) -> true (see _crossing_key)
	var recs := _records(ctx)
	var area_id := _area(ctx)
	for uid in recs:
		var rec: Dictionary = recs[uid]
		if String(rec.get("area", "surface")) != area_id:
			continue
		var def := def_of(String(rec.get("id", "")))
		if def.is_empty() or not blocks_movement(def):
			continue
		_add_blockers(footprint(def, vec_from(rec.get("pos")), float(rec.get("rot", 0.0))), solid_cells, walls)
	if not extra_fp.is_empty():
		_add_blockers(extra_fp, solid_cells, walls)
	if solid_cells.is_empty() and walls.is_empty():
		return false
	var bmin := Vector2i(1 << 29, 1 << 29)
	var bmax := Vector2i(-(1 << 29), -(1 << 29))
	for c in solid_cells:
		bmin = Vector2i(mini(bmin.x, c.x), mini(bmin.y, c.y))
		bmax = Vector2i(maxi(bmax.x, c.x), maxi(bmax.y, c.y))
	for w in walls:
		# dir 0: line z = w.x between cells z-1 and z at x = w.y ; dir 1: line x = w.x between x-1 and x at z = w.y
		if w.z == 0:
			bmin = Vector2i(mini(bmin.x, w.y), mini(bmin.y, w.x - 1))
			bmax = Vector2i(maxi(bmax.x, w.y), maxi(bmax.y, w.x))
		else:
			bmin = Vector2i(mini(bmin.x, w.x - 1), mini(bmin.y, w.y))
			bmax = Vector2i(maxi(bmax.x, w.x), maxi(bmax.y, w.y))
	# Blocked circles act as obstacles inside the bounding box only (they never extend it).
	var ba: Variant = ctx.get("build_area")
	if ba is Dictionary:
		for b in ba.get("blocked", []):
			var bc: Vector2 = b.get("center", Vector2.ZERO)
			var br := float(b.get("radius", 0.0)) * OBSTACLE_SHRINK
			for x in range(int(floorf(bc.x - br)), int(ceilf(bc.x + br)) + 1):
				for z in range(int(floorf(bc.y - br)), int(ceilf(bc.y + br)) + 1):
					if Vector2(x + 0.5, z + 0.5).distance_to(bc) <= br:
						solid_cells[Vector2i(x, z)] = true
	var start := Vector2i(int(floorf(player_pos.x)), int(floorf(player_pos.z)))
	if start.x < bmin.x or start.y < bmin.y or start.x > bmax.x or start.y > bmax.y:
		return false
	if solid_cells.has(start):
		return false      # standing "inside" something already: don't make things worse by refusing
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var steps := [
			[Vector2i(c.x + 1, c.y), Vector3i(c.x + 1, c.y, 1)],
			[Vector2i(c.x - 1, c.y), Vector3i(c.x, c.y, 1)],
			[Vector2i(c.x, c.y + 1), Vector3i(c.y + 1, c.x, 0)],
			[Vector2i(c.x, c.y - 1), Vector3i(c.y, c.x, 0)],
		]
		for s in steps:
			var n: Vector2i = s[0]
			if walls.has(s[1]) or seen.has(n) or solid_cells.has(n):
				continue
			if n.x < bmin.x or n.y < bmin.y or n.x > bmax.x or n.y > bmax.y:
				return false      # escaped the obstacle bounding box
			seen[n] = true
			queue.append(n)
	return true


## Crossing keys: dir 1 = line x = X crossed at row z = Z -> Vector3i(X, Z, 1);
##                dir 0 = line z = Z crossed at column x = X -> Vector3i(Z, X, 0).
static func _add_blockers(fp: Dictionary, solid_cells: Dictionary, walls: Dictionary) -> void:
	for c in fp["cells"]:
		solid_cells[c] = true
	for e in fp["edges"]:
		if e.z == 0:
			# along X from x = 2k..2k+2 at line z = 2m
			walls[Vector3i(e.y * 2, e.x * 2, 0)] = true
			walls[Vector3i(e.y * 2, e.x * 2 + 1, 0)] = true
		else:
			# along Z from z = 2m..2m+2 at line x = 2k
			walls[Vector3i(e.x * 2, e.y * 2, 1)] = true
			walls[Vector3i(e.x * 2, e.y * 2 + 1, 1)] = true
