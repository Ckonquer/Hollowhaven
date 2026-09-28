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
##   stair2  2x4 m stairs on the even 2 m grid (the stairwell is exactly two floor tiles); rot 0 rises toward
##           -Z (entry at +Z, top landing tile beyond -Z), 90 toward -X, 180 toward +Z, 270 toward +X
## Edge keys are Vector3i(k, m, dir): dir 0 spans x in [2k, 2k+2] at z = 2m, dir 1 spans z in [2m, 2m+2]
## at x = 2k. Cell keys are Vector2i(x, z) for the 1 m cell [x, x+1] x [z, z+1].
##
## Storeys (Chapter Two): a structure record's data.level (absent = 0; upper floors are always 1). Level 0
## keeps the legacy occupancy keys byte-identical ("floor", "edge", ...); level n uses "<layer>@n". An upper
## floor tile sits LEVEL_HEIGHT above the base of what holds it up: a full-height wall/window/doorway on one
## of its edges, a support post on one of its cells, or a neighbouring upper tile that is itself held up that
## way. Pieces upstairs need an upper floor under them (walls: on one side). Validation only: nothing ever
## collapses; dismantling something that holds a piece up is refused (build_ops.gd).
##
## ctx keys (all optional):
##   structures: Dictionary   GameState.structures-shaped records (default GameState.structures)
##   area_id: String          only records of this area count (default "surface")
##   build_area: Dictionary   {"center": Vector2, "radius": float, "blocked": [{"center", "radius", "name"?}],
##                            "extra": [{"center", "radius", "blocked"?}] (more buildable circles),
##                            "exclude": [structure ids not allowed here] (with "exclude_reason": String)
##                                       or {structure id: reason},
##                            "outside_reason": String (default MSG_OUTSIDE)}
##                            missing/empty = building not allowed here at all
##   height_fn: Callable      (x: float, z: float) -> float ground height; missing = flat at pos.y
##   player_pos: Vector3      used for the enclosure rule
##   player_level: int        the storey Krystal stands on (default: from player_pos.y above the ground)
##   level: int               storey the cursor points at (0 ground, 1 upstairs); pieces that can go
##                            upstairs are placed there
##   physics_fn: Callable     (structure_id, pos: Vector3, rot: int) -> String ("" = clear) for live checks
##   occupancy: Dictionary    cached build_occupancy() result (rebuilt when missing)

const TILE := 2.0
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.22
const FLOOR_TOP := 0.12          # walkable top of a wooden floor tile
const MAX_UNEVEN := 0.45         # max ground height difference across a footprint (m)
const OBSTACLE_SHRINK := 0.7     # blocked circles count as solid obstacles at this fraction of their radius
## Chapter Two storeys.
const LEVEL_HEIGHT := WALL_HEIGHT            # one storey
const MAX_LEVEL := 1                         # two storeys: ground (0) and upstairs (1)
const UPPER_TOP := FLOOR_TOP                 # walkable top of an upper floor tile above its origin
const STAIR_RISE := LEVEL_HEIGHT + UPPER_TOP # the stair ramp ends flush with the landing's walkable top
const SUPPORT_HEIGHT := 2.95                 # full-height edge pieces (legacy walls too) hold up upper floors
const UPSTAIRS_CLEARANCE := 1.5              # standing this far above the ground = on the upper storey
## The landing at the top of the stairs may sit at most this far above the end of the ramp (one small step:
## the player steps up 0.3 m). A landing lower than the ramp is a small step down and always fine. Only
## matters on sloped ground, where walls and stairs rest on different ground heights.
const STAIR_TOP_TOLERANCE := 0.28

## Legacy pieces (their data entries never change) that may also be built upstairs; new pieces say
## `level_ok` in data/structures.gd. The crop plot and the ground floor tile stay downstairs.
const LEGACY_LEVEL_OK := ["wood_wall", "wood_window", "wood_doorway", "wood_roof", "fence", "lantern_post",
	"flower_pot", "rug", "table", "stool", "storage_chest", "bed", "workbench", "pebble_cairn", "echo_chime",
	"heartbloom_lamp", "haven_banner"]

const MSG_OUTSIDE := "You can only build at the Haven"
const MSG_CLEAR := "This spot needs to stay clear"
const MSG_UNEVEN := "The ground is too bumpy here"
const MSG_ROOF := "Roofs need a wall to rest on"
const MSG_ENCLOSE := "That would shut you in! Leave a doorway"
const MSG_UPPER := "Upper floors need a wall or post below them"
const MSG_GROUND_ONLY := "That only goes on the ground floor"
const MSG_NEEDS_UPPER := "Upstairs pieces need an upper floor under them"
const MSG_STAIRWELL := "Keep the stairwell open"
const MSG_STAIR_FOOT := "Keep the foot of the stairs clear"
const MSG_STAIR_TOP := "That would block the top of the stairs"
const MSG_STAIR_CUT := "That would cut through the stairs"
const MSG_STAIR_ROOF := "A roof is in the way of the stairs"
const MSG_ROOF_OVER_UPPER := "There's an upper floor here: roofs go on the walls upstairs"
const MSG_UPPER_UNDER_ROOF := "There's a roof here. Take it down to build upstairs"
const MSG_STAIR_HEIGHT := "The stairs wouldn't reach that floor: the ground here is too uneven"


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


## Storey of a saved record: data.level (absent = 0, JSON floats cast), upper floors at least 1.
static func level_of(rec: Dictionary) -> int:
	var lv := 0
	var data: Variant = rec.get("data", {})
	if data is Dictionary:
		var v: Variant = (data as Dictionary).get("level", 0)
		if v is int or v is float:
			lv = int(v)
	if bool(def_of(String(rec.get("id", ""))).get("upper", false)):
		lv = maxi(lv, 1)
	return clampi(lv, 0, MAX_LEVEL)


## Occupancy layer key: the legacy layer name on the ground storey, "<layer>@<level>" above it.
static func layer_key(layer: String, level: int) -> String:
	return layer if level <= 0 else "%s@%d" % [layer, level]


## May this piece be built on an upper floor?
static func is_level_ok(structure_id: String, def: Dictionary = {}) -> bool:
	var d: Dictionary = def if not def.is_empty() else def_of(structure_id)
	return bool(d.get("level_ok", false)) or bool(d.get("upper", false)) or LEGACY_LEVEL_OK.has(structure_id)


## Does this piece hold up an upper floor above it? Full-height edge pieces (legacy walls, windows and
## doorways by rule) and pieces flagged `support` that reach a full storey (porch posts).
static func supports_upper(def: Dictionary) -> bool:
	if def.is_empty() or bool(def.get("stairs", false)):
		return false
	var tall := float(def.get("height", 0.0)) >= SUPPORT_HEIGHT
	if String(def.get("layer", "object")) == "edge":
		return tall and bool(def.get("solid", false))
	return tall and bool(def.get("support", false))


static func is_stairs(def: Dictionary) -> bool:
	return snap_kind(def) == "stair2" or bool(def.get("stairs", false))


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
		"stair2":
			# Footprint corner on the even 2 m grid, the stairwell centred on the cursor.
			var ss := rotated_size(def, rot)
			var cx := roundf((point.x - float(ss.x) * 0.5) / TILE) * TILE
			var cz := roundf((point.z - float(ss.y) * 0.5) / TILE) * TILE
			return Vector3(cx + float(ss.x) * 0.5, point.y, cz + float(ss.y) * 0.5)
		_:
			var s := rotated_size(def, rot)
			var ix := roundf(point.x - float(s.x) * 0.5)
			var iz := roundf(point.z - float(s.y) * 0.5)
			return Vector3(ix + float(s.x) * 0.5, point.y, iz + float(s.y) * 0.5)


## {"layer" (occupancy key, see layer_key), "cells": [Vector2i], "edges": [Vector3i], "rect": Rect2 (x,z world),
##  "rot": int, "level": int}
static func footprint(def: Dictionary, pos: Vector3, rot_deg: float, level: int = 0) -> Dictionary:
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
	var lv := clampi(level, 0, MAX_LEVEL)
	return {"layer": layer_key(String(def.get("layer", "object")), lv), "cells": cells, "edges": edges, "rect": rect, "rot": rot, "level": lv}


## Footprint of a saved record at its own storey.
static func record_footprint(rec: Dictionary) -> Dictionary:
	var def := def_of(String(rec.get("id", "")))
	return footprint(def, vec_from(rec.get("pos")), float(rec.get("rot", 0.0)), level_of(rec))


# --- Occupancy ------------------------------------------------------------------------------------

static func _records(ctx: Dictionary) -> Dictionary:
	var s: Variant = ctx.get("structures")
	return s if s is Dictionary else GameState.structures


static func _area(ctx: Dictionary) -> String:
	return String(ctx.get("area_id", "surface"))


## {layer key: {Vector2i|Vector3i: uid}} for every structure of `area_id`.
static func build_occupancy(structures: Dictionary, area_id: String) -> Dictionary:
	var occ := {}
	for uid in structures:
		var rec: Dictionary = structures[uid]
		if String(rec.get("area", "surface")) != area_id:
			continue
		var def := def_of(String(rec.get("id", "")))
		if def.is_empty():
			continue
		var fp := footprint(def, vec_from(rec.get("pos")), float(rec.get("rot", 0.0)), level_of(rec))
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


## Structure uid at a point, preferring objects, then walls within `edge_tolerance`, then floors. `level` is
## the storey to search (-1 = ctx.level, default 0 = the legacy ground search).
static func structure_at_point(point: Vector3, ctx: Dictionary, edge_tolerance: float = 0.45, level: int = -1) -> String:
	var lv: int = level if level >= 0 else clampi(int(ctx.get("level", 0)), 0, MAX_LEVEL)
	var occ := _occupancy(ctx)
	var cell := Vector2i(int(floorf(point.x)), int(floorf(point.z)))
	var fk := layer_key("floor", lv)
	var rk := layer_key("roof", lv)
	var ek := layer_key("edge", lv)
	for layer in occ:
		var ls := String(layer)
		if ls == fk or ls == rk or ls == ek:
			continue
		if (lv == 0 and ls.contains("@")) or (lv > 0 and not ls.ends_with("@%d" % lv)):
			continue
		if occ[layer].has(cell):
			return String(occ[layer][cell])
	var edges: Dictionary = occ.get(ek, {})
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
	var floors: Dictionary = occ.get(fk, {})
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


## Storey a new piece goes on: upper floors always upstairs, stairs always on the ground, roofs on the storey
## whose walls hold them up (upstairs walls win), everything else where the cursor points (ctx.level).
static func requested_level(structure_id: String, pos: Vector3, rot_deg: float, ctx: Dictionary) -> int:
	var def := def_of(structure_id)
	if bool(def.get("upper", false)):
		return 1
	if snap_kind(def) == "stair2":
		return 0
	var want := clampi(int(ctx.get("level", 0)), 0, MAX_LEVEL)
	if snap_kind(def) == "roof2" and want < MAX_LEVEL:
		if roof_supported(footprint(def, pos, rot_deg, 1), ctx):
			return 1
	return want


## Final y of a structure placed at `pos` (bottom of the model), on the storey requested_level() picks.
static func placement_y(structure_id: String, pos: Vector3, rot_deg: float, ctx: Dictionary) -> float:
	return placement_y_at(structure_id, pos, rot_deg, ctx, requested_level(structure_id, pos, rot_deg, ctx))


static func placement_y_at(structure_id: String, pos: Vector3, rot_deg: float, ctx: Dictionary, level: int) -> float:
	var def := def_of(structure_id)
	var fp := footprint(def, pos, rot_deg, level)
	var rect: Rect2 = fp["rect"]
	var hs: Array = []
	for p in _sample_points(rect):
		hs.append(ground_at(p.x, p.y, pos.y, ctx))
	var hmin: float = hs.min()
	var hmax: float = hs.max()
	var centre: float = hs[0]
	if int(fp["level"]) >= 1:
		return _upper_piece_y(def, fp, ctx, centre)
	match snap_kind(def):
		"floor2", "stair2":
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


## y of a piece upstairs: upper floors on their supports, walls/objects on the upper floor, roofs on the
## upstairs walls. With nothing to rest on, one storey above the ground (the preview; validation refuses it).
static func _upper_piece_y(def: Dictionary, fp: Dictionary, ctx: Dictionary, ground: float) -> float:
	var level: int = fp["level"]
	var storey := LEVEL_HEIGHT * float(level)
	match snap_kind(def):
		"floor2":
			var y := upper_floor_y(fp, ctx)
			return y if y > -INF else ground + storey
		"roof2":
			var base := _roof_base(fp, ctx)
			if base > -INF:
				return base + WALL_HEIGHT
			var nb := _neighbour_roof_y(fp, ctx)
			return nb if nb > -INF else ground + storey + WALL_HEIGHT
		"edge2":
			var fy := -INF
			var floors: Dictionary = _occupancy(ctx).get(layer_key("floor", level), {})
			var recs := _records(ctx)
			for t in edge_tiles(fp["edges"][0]):
				if floors.has(t) and recs.has(floors[t]):
					fy = maxf(fy, vec_from(recs[floors[t]].get("pos")).y)
			return fy if fy > -INF else ground + storey
	var top := -INF
	var ups: Dictionary = _occupancy(ctx).get(layer_key("floor", level), {})
	var rs := _records(ctx)
	for c in fp["cells"]:
		if ups.has(c) and rs.has(ups[c]):
			top = maxf(top, vec_from(rs[ups[c]].get("pos")).y + UPPER_TOP)
	return top if top > -INF else ground + storey + UPPER_TOP


## Highest base y of the walls (of the roof's storey) around a roof tile (-INF if none).
static func _roof_base(fp: Dictionary, ctx: Dictionary) -> float:
	var base := -INF
	var edges: Dictionary = _occupancy(ctx).get(layer_key("edge", int(fp.get("level", 0))), {})
	var recs := _records(ctx)
	for e in tile_edges(fp):
		if _holds_roof(edges, e, recs):
			base = maxf(base, vec_from(recs[edges[e]].get("pos")).y)
	return base


## A roof rests on a full-height edge piece (every legacy wall, window and doorway; not a railing or a half
## wall, which would leave the roof floating above them).
static func _holds_roof(edges: Dictionary, e: Vector3i, recs: Dictionary) -> bool:
	if not edges.has(e):
		return false
	var r: Variant = recs.get(edges[e])
	if not (r is Dictionary):
		return false
	return supports_upper(def_of(String((r as Dictionary).get("id", ""))))


## Highest y of the wall-supported roof tiles right next to a roof footprint (-INF if none).
static func _neighbour_roof_y(fp: Dictionary, ctx: Dictionary) -> float:
	var lv := int(fp.get("level", 0))
	var occ := _occupancy(ctx)
	var edges: Dictionary = occ.get(layer_key("edge", lv), {})
	var roofs: Dictionary = occ.get(layer_key("roof", lv), {})
	var recs := _records(ctx)
	var rect: Rect2 = fp["rect"]
	var y := -INF
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c := Vector2i(int(rect.position.x) + d.x, int(rect.position.y) + d.y)
		if not roofs.has(c) or not recs.has(roofs[c]):
			continue
		for e in tile_edges({"rect": Rect2(c.x, c.y, 2, 2)}):
			if _holds_roof(edges, e, recs):
				y = maxf(y, vec_from(recs[roofs[c]].get("pos")).y)
				break
	return y


## The 4 wall edges around a 2x2 tile footprint.
static func tile_edges(fp: Dictionary) -> Array:
	var rect: Rect2 = fp["rect"]
	var tx := int(floorf(rect.position.x / TILE))
	var tz := int(floorf(rect.position.y / TILE))
	return [Vector3i(tx, tz, 0), Vector3i(tx, tz + 1, 0), Vector3i(tx, tz, 1), Vector3i(tx + 1, tz, 1)]


## First cells (tile origins, even grid) of the two 2x2 tiles that share an edge.
static func edge_tiles(e: Vector3i) -> Array:
	if e.z == 0:
		return [Vector2i(e.x * 2, e.y * 2 - 2), Vector2i(e.x * 2, e.y * 2)]
	return [Vector2i(e.x * 2 - 2, e.y * 2), Vector2i(e.x * 2, e.y * 2)]


## A roof tile is supported by a full-height wall (of its storey) on one of its edges, or by a neighbouring
## roof tile that is.
static func roof_supported(fp: Dictionary, ctx: Dictionary) -> bool:
	var lv := int(fp.get("level", 0))
	var occ := _occupancy(ctx)
	var recs := _records(ctx)
	var edges: Dictionary = occ.get(layer_key("edge", lv), {})
	for e in tile_edges(fp):
		if _holds_roof(edges, e, recs):
			return true
	var roofs: Dictionary = occ.get(layer_key("roof", lv), {})
	var rect: Rect2 = fp["rect"]
	var ox := int(rect.position.x)
	var oz := int(rect.position.y)
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c := Vector2i(ox + d.x, oz + d.y)
		if roofs.has(c):
			var nfp := {"rect": Rect2(c.x, c.y, 2, 2)}
			for e in tile_edges(nfp):
				if _holds_roof(edges, e, recs):
					return true
	return false


# --- Upper floors -------------------------------------------------------------------------------------

## Base y of what holds an upper tile up directly (-INF: nothing): full-height edge pieces of the storey
## below on its 4 edges, and support posts standing on one of its 4 cells (posts count from the ground they
## stand on, so a post-held tile lines up with a wall-held one).
static func upper_support_base(fp: Dictionary, ctx: Dictionary) -> float:
	var below := maxi(int(fp.get("level", 1)) - 1, 0)
	var occ := _occupancy(ctx)
	var recs := _records(ctx)
	var base := -INF
	var edges: Dictionary = occ.get(layer_key("edge", below), {})
	for e in tile_edges(fp):
		if edges.has(e) and recs.has(edges[e]):
			var r: Dictionary = recs[edges[e]]
			if supports_upper(def_of(String(r.get("id", "")))):
				base = maxf(base, vec_from(r.get("pos")).y)
	var objs: Dictionary = occ.get(layer_key("object", below), {})
	for c in fp["cells"]:
		if objs.has(c) and recs.has(objs[c]):
			var r2: Dictionary = recs[objs[c]]
			if supports_upper(def_of(String(r2.get("id", "")))):
				var p := vec_from(r2.get("pos"))
				base = maxf(base, ground_at(p.x, p.z, p.y, ctx) if below == 0 else p.y)
	return base


## Highest y of the directly supported upper tiles right next to an upper footprint (-INF if none).
static func _neighbour_upper_y(fp: Dictionary, ctx: Dictionary) -> float:
	var lv := int(fp.get("level", 1))
	var ups: Dictionary = _occupancy(ctx).get(layer_key("floor", lv), {})
	var recs := _records(ctx)
	var rect: Rect2 = fp["rect"]
	var y := -INF
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var c := Vector2i(int(rect.position.x) + d.x, int(rect.position.y) + d.y)
		if not ups.has(c) or not recs.has(ups[c]):
			continue
		var nfp := {"rect": Rect2(c.x, c.y, 2, 2), "cells": _tile_cells(c), "level": lv}
		if upper_support_base(nfp, ctx) > -INF:
			y = maxf(y, vec_from(recs[ups[c]].get("pos")).y)
	return y


static func _tile_cells(origin: Vector2i) -> Array:
	return [origin, Vector2i(origin.x, origin.y + 1), Vector2i(origin.x + 1, origin.y), Vector2i(origin.x + 1, origin.y + 1)]


## y an upper tile rests at (-INF: nothing holds it up).
static func upper_floor_y(fp: Dictionary, ctx: Dictionary) -> float:
	var base := upper_support_base(fp, ctx)
	if base > -INF:
		return base + LEVEL_HEIGHT
	return _neighbour_upper_y(fp, ctx)


static func upper_supported(fp: Dictionary, ctx: Dictionary) -> bool:
	return upper_support_base(fp, ctx) > -INF or _neighbour_upper_y(fp, ctx) > -INF


## Does something of the storey hold up this upstairs piece? (floors: supports; roofs: walls; walls: an upper
## floor on one side; objects: an upper floor under every cell). "" = yes, else the reason.
static func upper_rest_reason(def: Dictionary, fp: Dictionary, ctx: Dictionary) -> String:
	var lv := int(fp.get("level", 1))
	match snap_kind(def):
		"floor2":
			return "" if upper_supported(fp, ctx) else MSG_UPPER
		"roof2":
			return "" if roof_supported(fp, ctx) else MSG_ROOF
		"stair2":
			return MSG_GROUND_ONLY
		"edge2":
			var ups: Dictionary = _occupancy(ctx).get(layer_key("floor", lv), {})
			for t in edge_tiles(fp["edges"][0]):
				if ups.has(t):
					return ""
			return MSG_NEEDS_UPPER
	var floors: Dictionary = _occupancy(ctx).get(layer_key("floor", lv), {})
	for c in fp["cells"]:
		if not floors.has(c):
			return MSG_NEEDS_UPPER
	return ""


# --- Stairs ---------------------------------------------------------------------------------------------

## Where a stair footprint meets the rest of the house: {"top_edge", "bottom_edge", "mid_edge": Vector3i,
## "landing": Vector2i (first cell of the tile beyond the top), "landing_row": [2 cells next to the top edge],
## "entry": [2 cells just in front of the bottom step], "tiles": [2 tile origins], "up": Vector2i}.
static func stair_ends(fp: Dictionary) -> Dictionary:
	var rect: Rect2 = fp["rect"]
	var x0 := int(rect.position.x)
	var z0 := int(rect.position.y)
	var kx := int(floorf(float(x0) / TILE))
	var kz := int(floorf(float(z0) / TILE))
	match int(fp.get("rot", 0)):
		90:      # rises toward -X: top at x0
			return {"up": Vector2i(-1, 0), "top_edge": Vector3i(kx, kz, 1), "bottom_edge": Vector3i(kx + 2, kz, 1), "mid_edge": Vector3i(kx + 1, kz, 1),
				"landing": Vector2i(x0 - 2, z0), "landing_row": [Vector2i(x0 - 1, z0), Vector2i(x0 - 1, z0 + 1)],
				"entry": [Vector2i(x0 + 4, z0), Vector2i(x0 + 4, z0 + 1)], "tiles": [Vector2i(x0, z0), Vector2i(x0 + 2, z0)]}
		180:     # rises toward +Z: top at z0 + 4
			return {"up": Vector2i(0, 1), "top_edge": Vector3i(kx, kz + 2, 0), "bottom_edge": Vector3i(kx, kz, 0), "mid_edge": Vector3i(kx, kz + 1, 0),
				"landing": Vector2i(x0, z0 + 4), "landing_row": [Vector2i(x0, z0 + 4), Vector2i(x0 + 1, z0 + 4)],
				"entry": [Vector2i(x0, z0 - 1), Vector2i(x0 + 1, z0 - 1)], "tiles": [Vector2i(x0, z0), Vector2i(x0, z0 + 2)]}
		270:     # rises toward +X: top at x0 + 4
			return {"up": Vector2i(1, 0), "top_edge": Vector3i(kx + 2, kz, 1), "bottom_edge": Vector3i(kx, kz, 1), "mid_edge": Vector3i(kx + 1, kz, 1),
				"landing": Vector2i(x0 + 4, z0), "landing_row": [Vector2i(x0 + 4, z0), Vector2i(x0 + 4, z0 + 1)],
				"entry": [Vector2i(x0 - 1, z0), Vector2i(x0 - 1, z0 + 1)], "tiles": [Vector2i(x0, z0), Vector2i(x0 + 2, z0)]}
	# 0: rises toward -Z: top at z0
	return {"up": Vector2i(0, -1), "top_edge": Vector3i(kx, kz, 0), "bottom_edge": Vector3i(kx, kz + 2, 0), "mid_edge": Vector3i(kx, kz + 1, 0),
		"landing": Vector2i(x0, z0 - 2), "landing_row": [Vector2i(x0, z0 - 1), Vector2i(x0 + 1, z0 - 1)],
		"entry": [Vector2i(x0, z0 + 4), Vector2i(x0 + 1, z0 + 4)], "tiles": [Vector2i(x0, z0), Vector2i(x0, z0 + 2)]}


## Every stair piece of the ctx area: [{"uid", "fp", "ends"}] (cached in ctx).
static func stairs_in(ctx: Dictionary) -> Array:
	var cached: Variant = ctx.get("_stairs")
	if cached is Array:
		return cached
	var out: Array = []
	var recs := _records(ctx)
	var seen := {}
	for c in _occupancy(ctx).get("stair", {}).values():
		var uid := String(c)
		if seen.has(uid) or not recs.has(uid):
			continue
		seen[uid] = true
		var fp := record_footprint(recs[uid])
		out.append({"uid": uid, "fp": fp, "ends": stair_ends(fp)})
	ctx["_stairs"] = out
	return out


## True when some stairs lead up to an upper floor tile she can step onto (a reachable upstairs): the landing
## tile is there, nothing solid stands across the top of the stairs, and the ramp meets the landing's height.
static func has_reachable_upstairs(ctx: Dictionary) -> bool:
	var ups: Dictionary = _occupancy(ctx).get(layer_key("floor", 1), {})
	var upper_edges: Dictionary = _occupancy(ctx).get(layer_key("edge", 1), {})
	var recs := _records(ctx)
	for s in stairs_in(ctx):
		var ends: Dictionary = s["ends"]
		if not ups.has(ends["landing"]) or not recs.has(ups[ends["landing"]]):
			continue
		var te: Vector3i = ends["top_edge"]
		if upper_edges.has(te) and recs.has(upper_edges[te]) and blocks_movement(def_of(String(recs[upper_edges[te]].get("id", "")))):
			continue
		var stair_y := vec_from(recs[s["uid"]].get("pos")).y
		if not stair_meets_landing(stair_y, vec_from(recs[ups[ends["landing"]]].get("pos")).y):
			continue
		return true
	return false


## Do stairs standing at `stair_y` meet an upper floor tile resting at `landing_y` (the tile's origin)? The
## landing's walkable top may be up to STAIR_TOP_TOLERANCE above the end of the ramp; lower is always fine.
static func stair_meets_landing(stair_y: float, landing_y: float) -> bool:
	return (landing_y + UPPER_TOP) - (stair_y + STAIR_RISE) <= STAIR_TOP_TOLERANCE


## Height check between new stairs and the upper floor tile at their top, or a new upper floor tile and the
## stairs that lead onto it: {"reason": "" | MSG_STAIR_HEIGHT, "blocker": uid}.
static func _stair_height_conflict(def: Dictionary, fp: Dictionary, y: float, ctx: Dictionary) -> Dictionary:
	var snap := snap_kind(def)
	var recs := _records(ctx)
	if snap == "stair2":
		var ups: Dictionary = _occupancy(ctx).get(layer_key("floor", 1), {})
		var lc: Vector2i = stair_ends(fp)["landing"]
		if ups.has(lc) and recs.has(ups[lc]) and not stair_meets_landing(y, vec_from(recs[ups[lc]].get("pos")).y):
			return _conflict(MSG_STAIR_HEIGHT, String(ups[lc]))
	elif snap == "floor2" and int(fp.get("level", 0)) >= 1:
		var rect: Rect2 = fp["rect"]
		var origin := Vector2i(int(rect.position.x), int(rect.position.y))
		for s in stairs_in(ctx):
			var landing: Vector2i = s["ends"]["landing"]
			if landing == origin and recs.has(s["uid"]) and not stair_meets_landing(vec_from(recs[s["uid"]].get("pos")).y, y):
				return _conflict(MSG_STAIR_HEIGHT, String(s["uid"]))
	return _conflict("", "")


## Cross-storey conflicts that plain same-layer overlap can't see (stairwells, roofs vs upper floors, the
## foot and top of the stairs). {"reason": "" (none) | message, "blocker": uid}.
static func _storey_conflict(def: Dictionary, fp: Dictionary, ctx: Dictionary) -> Dictionary:
	var occ := _occupancy(ctx)
	var recs := _records(ctx)
	var lv: int = fp["level"]
	var snap := snap_kind(def)
	var raw_layer := String(def.get("layer", "object"))
	var blocks := blocks_movement(def)
	if snap == "stair2":
		var ends := stair_ends(fp)
		var objs: Dictionary = occ.get("object", {})
		var decor: Dictionary = occ.get("decor", {})
		var roofs: Dictionary = occ.get("roof", {})
		var ups: Dictionary = occ.get(layer_key("floor", 1), {})
		for c in fp["cells"]:
			for lm in [objs, decor]:
				if (lm as Dictionary).has(c):
					return _conflict(MSG_STAIRWELL, String(lm[c]))
			if ups.has(c):
				return _conflict(MSG_STAIRWELL, String(ups[c]))
			if roofs.has(c):
				return _conflict(MSG_STAIR_ROOF, String(roofs[c]))
		if roofs.has(ends["landing"]):
			return _conflict(MSG_STAIR_ROOF, String(roofs[ends["landing"]]))
		var edges: Dictionary = occ.get("edge", {})
		if edges.has(ends["mid_edge"]):
			return _conflict(MSG_STAIR_CUT, String(edges[ends["mid_edge"]]))
		if edges.has(ends["bottom_edge"]) and _uid_blocks(recs, edges[ends["bottom_edge"]]):
			return _conflict(MSG_STAIR_FOOT, String(edges[ends["bottom_edge"]]))
		for c in ends["entry"]:
			if objs.has(c) and _uid_blocks(recs, objs[c]):
				return _conflict(MSG_STAIR_FOOT, String(objs[c]))
		var up_edges: Dictionary = occ.get(layer_key("edge", 1), {})
		if up_edges.has(ends["top_edge"]) and _uid_blocks(recs, up_edges[ends["top_edge"]]):
			return _conflict(MSG_STAIR_TOP, String(up_edges[ends["top_edge"]]))
		var up_objs: Dictionary = occ.get(layer_key("object", 1), {})
		for c in ends["landing_row"]:
			if up_objs.has(c) and _uid_blocks(recs, up_objs[c]):
				return _conflict(MSG_STAIR_TOP, String(up_objs[c]))
		return _conflict("", "")
	var stairs := stairs_in(ctx)
	if stairs.is_empty() and lv == 0 and snap != "roof2":
		return _conflict("", "")      # ground-floor pieces only ever clash with stairs
	match snap:
		"floor2":
			if lv >= 1:
				for s in stairs:
					for c in fp["cells"]:
						if (s["fp"]["cells"] as Array).has(c):
							return _conflict(MSG_STAIRWELL, String(s["uid"]))
				var roofs0: Dictionary = occ.get(layer_key("roof", lv - 1), {})
				for c in fp["cells"]:
					if roofs0.has(c):
						return _conflict(MSG_UPPER_UNDER_ROOF, String(roofs0[c]))
		"roof2":
			var above: Dictionary = occ.get(layer_key("floor", lv + 1), {}) if lv < MAX_LEVEL else {}
			for c in fp["cells"]:
				if above.has(c):
					return _conflict(MSG_ROOF_OVER_UPPER, String(above[c]))
			if lv == 0:
				for s in stairs:
					var ends2: Dictionary = s["ends"]
					for c in fp["cells"]:
						if (s["fp"]["cells"] as Array).has(c) or c == ends2["landing"]:
							return _conflict(MSG_STAIR_ROOF, String(s["uid"]))
		"edge2":
			var e: Vector3i = fp["edges"][0]
			for s in stairs:
				var ends3: Dictionary = s["ends"]
				if lv == 0 and e == ends3["mid_edge"]:
					return _conflict(MSG_STAIR_CUT, String(s["uid"]))
				if lv == 0 and blocks and e == ends3["bottom_edge"]:
					return _conflict(MSG_STAIR_FOOT, String(s["uid"]))
				if lv == 1 and blocks and e == ends3["top_edge"]:
					return _conflict(MSG_STAIR_TOP, String(s["uid"]))
		_:
			for s in stairs:
				var ends4: Dictionary = s["ends"]
				for c in fp["cells"]:
					if lv == 0 and (raw_layer == "object" or raw_layer == "decor") and (s["fp"]["cells"] as Array).has(c):
						return _conflict(MSG_STAIRWELL, String(s["uid"]))
					if lv == 0 and blocks and (ends4["entry"] as Array).has(c):
						return _conflict(MSG_STAIR_FOOT, String(s["uid"]))
					if lv == 1 and blocks and (ends4["landing_row"] as Array).has(c):
						return _conflict(MSG_STAIR_TOP, String(s["uid"]))
	return _conflict("", "")


static func _conflict(reason: String, blocker: String) -> Dictionary:
	return {"reason": reason, "blocker": blocker}


static func _uid_blocks(recs: Dictionary, uid: Variant) -> bool:
	var r: Variant = recs.get(uid)
	return r is Dictionary and blocks_movement(def_of(String((r as Dictionary).get("id", ""))))


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


## Is a point inside the build area (the main circle or one of its extra regions)?
static func in_build_area(point: Vector3, build_area: Dictionary) -> bool:
	if build_area.is_empty():
		return false
	return _in_any_region(Vector2(point.x, point.z), build_area)


## What to say when a piece is outside this build area (the Haven by default; the Reach outpost says so).
static func outside_reason(ba: Dictionary) -> String:
	return String(ba.get("outside_reason", MSG_OUTSIDE))


static func _in_any_region(p: Vector2, ba: Dictionary) -> bool:
	if p.distance_to(ba.get("center", Vector2.ZERO)) <= float(ba.get("radius", 0.0)):
		return true
	for r in ba.get("extra", []):
		if r is Dictionary and p.distance_to((r as Dictionary).get("center", Vector2.ZERO)) <= float((r as Dictionary).get("radius", 0.0)):
			return true
	return false


## Does the whole footprint lie in the build area? Inside the main circle: the legacy corner test. Otherwise
## (the Haven expansion) every corner, edge midpoint and the centre must be in the main circle or a region.
static func rect_in_build_area(rect: Rect2, ba: Dictionary) -> bool:
	if rect_inside_circle(rect, ba.get("center", Vector2.ZERO), float(ba.get("radius", 0.0))):
		return true
	var extra: Variant = ba.get("extra", [])
	if not (extra is Array) or (extra as Array).is_empty():
		return false
	var e := rect.end
	var o := rect.position
	var c := rect.get_center()
	for p in [o, Vector2(e.x, o.y), Vector2(o.x, e.y), e, c, Vector2(c.x, o.y), Vector2(c.x, e.y), Vector2(o.x, c.y), Vector2(e.x, c.y)]:
		if not _in_any_region(p, ba):
			return false
	return true


## Keep-clear circles that apply to a footprint: the main list always; an extra region's own list only for
## footprints that reach outside the legacy circle (legacy placements keep exactly the legacy rules).
static func blocked_for(rect: Rect2, ba: Dictionary) -> Array:
	var out: Array = (ba.get("blocked", []) as Array).duplicate()
	if rect_inside_circle(rect, ba.get("center", Vector2.ZERO), float(ba.get("radius", 0.0))):
		return out
	for r in ba.get("extra", []):
		if r is Dictionary:
			out.append_array((r as Dictionary).get("blocked", []))
	return out


# --- Validation ----------------------------------------------------------------------------------------

## Full rule check. Returns {"ok": bool, "reason": String, "blocker": uid ("" if none), "y": float,
## "level": int (the storey the piece goes on)}.
static func validate(structure_id: String, pos: Vector3, rot_deg: float, ctx: Dictionary) -> Dictionary:
	var def := def_of(structure_id)
	if def.is_empty():
		return _res(false, "That can't be built", "", pos.y)
	var level := requested_level(structure_id, pos, rot_deg, ctx)
	var fp := footprint(def, pos, rot_deg, level)
	var rect: Rect2 = fp["rect"]
	var y := placement_y_at(structure_id, pos, rot_deg, ctx, level)
	var ba: Variant = ctx.get("build_area")
	if not (ba is Dictionary) or (ba as Dictionary).is_empty():
		return _res(false, MSG_OUTSIDE, "", y, level)
	if not rect_in_build_area(rect, ba):
		return _res(false, outside_reason(ba), "", y, level)
	var excluded: Variant = (ba as Dictionary).get("exclude", [])
	if excluded is Dictionary and (excluded as Dictionary).has(structure_id):
		return _res(false, String((excluded as Dictionary)[structure_id]), "", y, level)
	if excluded is Array and (excluded as Array).has(structure_id):
		return _res(false, String((ba as Dictionary).get("exclude_reason", MSG_OUTSIDE)), "", y, level)
	for b in blocked_for(rect, ba):
		if rect_hits_circle(rect, b.get("center", Vector2.ZERO), float(b.get("radius", 0.0))):
			var nm: String = String(b.get("name", ""))
			return _res(false, ("Too close to the %s" % nm) if nm != "" else MSG_CLEAR, "", y, level)
	if level >= 1 and not is_level_ok(structure_id, def):
		return _res(false, MSG_GROUND_ONLY, "", y, level)
	var blocker := overlap_uid(fp, _occupancy(ctx))
	if blocker != "":
		var rec: Dictionary = _records(ctx).get(blocker, {})
		var bid := String(rec.get("id", ""))
		# Display name (arachnophobia: the Thread Veil is a "Pale Veil Drape"); same as the data name otherwise.
		var nm2: String = ItemDB.structure_display_name(bid) if not def_of(bid).is_empty() else "something"
		return _res(false, "The %s is in the way" % nm2, blocker, y, level)
	var conflict := _storey_conflict(def, fp, ctx)
	if String(conflict["reason"]) != "":
		return _res(false, String(conflict["reason"]), String(conflict["blocker"]), y, level)
	if level >= 1:
		var why := upper_rest_reason(def, fp, ctx)
		if why != "":
			return _res(false, why, "", y, level)
	elif snap_kind(def) == "roof2":
		if not roof_supported(fp, ctx):
			return _res(false, MSG_ROOF, "", y, level)
	else:
		var hs: Array = []
		for p in _sample_points(rect):
			hs.append(ground_at(p.x, p.y, pos.y, ctx))
		if float(hs.max()) - float(hs.min()) > MAX_UNEVEN:
			return _res(false, MSG_UNEVEN, "", y, level)
	var reach := _stair_height_conflict(def, fp, y, ctx)
	if String(reach["reason"]) != "":
		return _res(false, String(reach["reason"]), String(reach["blocker"]), y, level)
	if blocks_movement(def) and ctx.get("player_pos") is Vector3:
		# Refuse only pieces that would *cause* the enclosure (if she's already in a pen, e.g. after
		# hopping a fence, building elsewhere stays possible; dismantling always opens things up).
		if would_enclose(ctx["player_pos"], ctx, fp) and not would_enclose(ctx["player_pos"], ctx):
			return _res(false, MSG_ENCLOSE, "", y, level)
	var pf: Variant = ctx.get("physics_fn")
	if pf is Callable and (pf as Callable).is_valid():
		var why2: Variant = (pf as Callable).call(structure_id, Vector3(pos.x, y, pos.z), int(fp["rot"]))
		if why2 is String and why2 != "":
			return _res(false, why2, "", y, level)
	return _res(true, "", "", y, level)


static func _res(ok: bool, reason: String, blocker: String, y: float, level: int = 0) -> Dictionary:
	return {"ok": ok, "reason": reason, "blocker": blocker, "y": y, "level": level}


## Solid pieces that stop Krystal walking (doorways, floors, roofs and stairs don't).
static func blocks_movement(def: Dictionary) -> bool:
	if not bool(def.get("solid", false)) or bool(def.get("passable", false)) or bool(def.get("stairs", false)):
		return false
	var layer: String = String(def.get("layer", "object"))
	return layer != "floor" and layer != "roof" and layer != "stair"


# --- Enclosure rule --------------------------------------------------------------------------------------

## Storey Krystal stands on: ctx.player_level, else from how far above the ground she is.
static func player_level(player_pos: Vector3, ctx: Dictionary) -> int:
	var pl: Variant = ctx.get("player_level")
	if pl is int or pl is float:
		return clampi(int(pl), 0, MAX_LEVEL)
	var g := ground_at(player_pos.x, player_pos.z, 0.0, ctx)
	return 1 if player_pos.y - g > UPSTAIRS_CLEARANCE else 0


## True if the player at `player_pos` would have no way out after adding `extra_fp` (optional).
## Flood fill on the 1 m grid of her storey: solid objects block cells, non-passable walls block cell
## crossings, blocked circles (Ward Stone, campfire...) count as obstacles on the ground. Reaching the ring
## outside the bounding box of all obstacles means there is a way out; upstairs, so does reaching any cell
## without an upper floor (she can drop down: there is no fall damage).
static func would_enclose(player_pos: Vector3, ctx: Dictionary, extra_fp: Dictionary = {}) -> bool:
	var level := player_level(player_pos, ctx)
	var solid_cells := {}
	var walls := {}           # Vector3i(line_coord, cell_coord, dir) -> true (see _crossing_key)
	var recs := _records(ctx)
	var area_id := _area(ctx)
	for uid in recs:
		var rec: Dictionary = recs[uid]
		if String(rec.get("area", "surface")) != area_id:
			continue
		var def := def_of(String(rec.get("id", "")))
		if def.is_empty() or not blocks_movement(def) or level_of(rec) != level:
			continue
		_add_blockers(footprint(def, vec_from(rec.get("pos")), float(rec.get("rot", 0.0))), solid_cells, walls)
	if not extra_fp.is_empty() and int(extra_fp.get("level", 0)) == level:
		_add_blockers(extra_fp, solid_cells, walls)
	if level >= 1:
		return _enclosed_upstairs(player_pos, _occupancy(ctx).get(layer_key("floor", level), {}), solid_cells, walls)
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


## Upstairs flood fill: cells without an upper floor tile are a way down (the stairwell, the edge).
static func _enclosed_upstairs(player_pos: Vector3, floors: Dictionary, solid_cells: Dictionary, walls: Dictionary) -> bool:
	var start := Vector2i(int(floorf(player_pos.x)), int(floorf(player_pos.z)))
	if not floors.has(start) or solid_cells.has(start):
		return false
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
			if not floors.has(n):
				return false      # a way down
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
