extends RefCounted
## Build operations shared by BuildMode, BuildingSystem and tests: the validation context for an area,
## placing (consumes exactly one item) and dismantling (100% refund, chest, roof and storey rules), plus the
## Chapter Two operations: undoing a placement (exact refund, the build counter goes back too, so place/undo
## loops never farm anything), recolouring a piece in place (uid and chest contents kept) and a
## non-destructive audit of saved pieces that newer rules would dislike (grandfathered, never removed).
## All state changes go through GameState; nodes are spawned/freed to match.

const Placement := preload("res://src/building/placement.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Farming := preload("res://src/farming/farming.gd")
const Layout := preload("res://data/world_layout.gd")
const HallowmereLayout := preload("res://data/hallowmere_layout.gd")
const InventoryScript := preload("res://src/core/inventory.gd")
const Tints := preload("res://src/building/tints.gd")

## Debug builds only: the test arena (--area=arena) gets a generous build circle so build mode can be
## exercised there. Release builds only ever allow the Haven.
const DEBUG_BUILD_AREA := {"center": Vector2(0, 0), "radius": 30.0, "grid": 1.0, "blocked": []}

## Friendly names for the Haven's keep-clear circles (matched by centre), so a refusal says
## "Too close to the Ward Stone" instead of a generic message. Unknown circles stay generic.
const BLOCKED_NAMES := {Vector2(0, -6): "Ward Stone", Vector2(4, 3): "campfire"}

## Hallowmere Reach: a small optional outpost at the Commons cottage foundation (never a replacement home, so
## the bed and the companions' home spots stay at the Haven: a companion's home spot is a Haven position).
## The Commons is already a safe zone.
const MSG_OUTPOST_BED := "Your bed belongs at home in the Haven."
const MSG_OUTPOST_NOOK := "Your friends' beds and perches belong at home in the Haven."
const OUTPOST_EXCLUDE := {"bed": MSG_OUTPOST_BED, "companion_bed": MSG_OUTPOST_NOOK, "companion_perch": MSG_OUTPOST_NOOK}
const MSG_OUTPOST_OUTSIDE := "In the Reach you can build at the cottage foundation by the Commons"

static var _haven_area: Dictionary = {}
static var _outpost_area: Dictionary = {}

const MSG_CHEST_FULL := "Empty the chest first. Your backpack can't hold everything inside."
const MSG_ROOF_ON_WALL := "Take down the roof resting on this wall first."
const MSG_ROOF_ON_ROOF := "Take down the roof tile leaning on this one first."
const MSG_UPPER_ON_SUPPORT := "Take down the upper floor resting on this first."
const MSG_UPPER_ON_UPPER := "Take down the upper floor tile leaning on this one first."
const MSG_UPPER_CARRIES := "Clear what stands on this upper floor first."
const MSG_DECOR_ON_WALL := "Take down the %s hanging on this wall first."
const MSG_NOTHING_TO_UNDO := "Nothing to undo."
## Set (once, never cleared) when stairs lead onto an upper floor she can step onto: the optional goal "A House
## With an Upstairs" (data/optional_goals.gd opt_upstairs, set by building). Checked after every place and
## dismantle while unset, and repaired on load (BuildingSystem.attach).
const FLAG_UPSTAIRS := "c1x_upstairs_reachable"
const MSG_NO_TINT := "This piece can't be recoloured."
const MSG_TINT_LOCKED := "Make that dye at the Loom first."


static func area_id_of(area: Node) -> String:
	if area != null and is_instance_valid(area):
		var a: Variant = area.get("area_id")
		if a is String and String(a) != "":
			return String(a)
	return Game.area_id if Game.area_id != "" else "surface"


static func build_area_for(area_id: String) -> Dictionary:
	if area_id == "surface":
		if _haven_area.is_empty():
			_haven_area = _with_blocked_names(Layout.BUILD_AREA)
		return _haven_area
	if area_id == HallowmereLayout.AREA_ID:
		if _outpost_area.is_empty():
			_outpost_area = {"center": HallowmereLayout.OUTPOST_BUILD_AREA["center"], "radius": float(HallowmereLayout.OUTPOST_BUILD_AREA["radius"]),
				"grid": 1.0, "blocked": [], "exclude": OUTPOST_EXCLUDE, "outside_reason": MSG_OUTPOST_OUTSIDE}
		return _outpost_area
	if area_id == "arena" and Debug.is_cheat_allowed():
		return DEBUG_BUILD_AREA
	return {}


static func _with_blocked_names(ba: Dictionary) -> Dictionary:
	var out: Dictionary = ba.duplicate(true)
	for b in out.get("blocked", []):
		if b is Dictionary and not (b as Dictionary).has("name") and BLOCKED_NAMES.has(b.get("center")):
			b["name"] = BLOCKED_NAMES[b.get("center")]
	return out


## Ground height function for an area: area.height_at(x, z) if provided, else a downward ray on "world".
static func height_fn(area: Node) -> Callable:
	if area != null and is_instance_valid(area) and area.has_method("height_at"):
		return Callable(area, "height_at")
	if area is Node3D and (area as Node3D).is_inside_tree():
		var world := (area as Node3D).get_world_3d()
		return func(x: float, z: float) -> float:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -80.0, z), 1)
			var hit := world.direct_space_state.intersect_ray(q)
			return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0
	return Callable()


## `level`: the storey the cursor points at (0 ground, 1 upstairs; see placement.gd).
static func make_ctx(area: Node, player_pos: Variant = null, level: int = 0) -> Dictionary:
	var aid := area_id_of(area)
	var ctx := {"structures": GameState.structures, "area_id": aid, "build_area": build_area_for(aid), "level": level}
	var hf := height_fn(area)
	if hf.is_valid():
		ctx["height_fn"] = hf
	if player_pos is Vector3:
		ctx["player_pos"] = player_pos
	return ctx


## Structure id placed by an item ("" if the item isn't placeable).
static func structure_for_item(item_id: String) -> String:
	if not ItemDB.has_item(item_id):
		return ""
	var sid: String = String(ItemDB.item(item_id).get("place", ""))
	return sid if sid != "" and not ItemDB.structure(sid).is_empty() else ""


# --- Placing -------------------------------------------------------------------------------------

## Consumes exactly one `item_id`, records the structure in GameState and spawns its node.
## The caller validates first (BuildMode does). Returns the new uid or "" on failure.
## `level` = storey (upper floors are always 1; recorded as data.level only above the ground, so ground
## pieces keep the legacy record shape). `data` = extra record data set before the node spawns
## (e.g. {"face": "cat"} for a carved pumpkin, {"tint": "rose"}).
static func place_structure(area: Node, item_id: String, pos: Vector3, rot_deg: float, level: int = 0, data: Dictionary = {}) -> String:
	var sid := structure_for_item(item_id)
	if sid == "":
		return ""
	var def := Placement.def_of(sid)
	var lv := 1 if bool(def.get("upper", false)) else clampi(level, 0, Placement.MAX_LEVEL)
	if not GameState.take_item(item_id, 1):
		return ""
	var uid := GameState.add_structure(sid, pos, rot_deg, area_id_of(area))
	var rec: Dictionary = GameState.structures[uid]
	if not (rec.get("data") is Dictionary):
		rec["data"] = {}
	if lv > 0:
		rec["data"]["level"] = lv
	for k in data:
		rec["data"][k] = data[k]
	var node := Factory.spawn_structure(area, uid)
	if node != null and node.has_method("play_place_anim"):
		node.play_place_anim()
	if String(def.get("layer", "")) == "floor" and lv == 0:
		reseat_objects(area, Placement.footprint(def, pos, rot_deg)["cells"])
	GameState.add_counter("structures_built")
	notify_area(area)
	update_upstairs_flag(area_id_of(area))
	Events.structure_placed.emit(uid, sid)
	Audio.play_3d("build_place", pos + Vector3.UP * 0.4)
	return uid


## Sets FLAG_UPSTAIRS the first time `area_id` has stairs leading onto a reachable upper floor. Cheap while
## there are no stairs; never clears the flag (the goal latches). Returns the flag's value.
static func update_upstairs_flag(area_id: String) -> bool:
	if bool(GameState.get_flag(FLAG_UPSTAIRS)):
		return true
	if GameState.count_structures("wood_stairs") == 0:
		return false
	if Placement.has_reachable_upstairs({"structures": GameState.structures, "area_id": area_id}):
		GameState.set_flag(FLAG_UPSTAIRS)
		return true
	return false


# --- Dismantling ------------------------------------------------------------------------------------

## Pure rule check: {"ok": bool, "reason": String}.
static func can_dismantle(uid: String) -> Dictionary:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return {"ok": false, "reason": "There's nothing to take apart here."}
	var sid: String = String(rec.get("id", ""))
	var def := Placement.def_of(sid)
	if String(def.get("interact", "")) == "storage":
		var inv: Variant = GameState.storages.get(uid)
		if inv != null and not inv.is_empty():
			var sim: RefCounted = InventoryScript.new(GameState.inventory.size)
			sim.from_array(GameState.inventory.snapshot())
			for s in inv.slots:
				if s != null and int(sim.add(String(s["id"]), int(s["count"]))) > 0:
					return {"ok": false, "reason": MSG_CHEST_FULL}
	var layer: String = String(def.get("layer", ""))
	var area_id: String = String(rec.get("area", "surface"))
	var others: Dictionary = {}
	var now_ctx := {}
	var after_ctx := {}
	if layer == "edge" or layer == "roof" or layer == "floor" or layer == "object":
		others = GameState.structures.duplicate()
		others.erase(uid)
		now_ctx = {"structures": GameState.structures, "area_id": area_id}
		after_ctx = {"structures": others, "area_id": area_id}
	if layer == "edge" or layer == "roof":
		# Walls hold roofs up, and a roof tile can hold up its neighbour: refuse if any roof that is
		# supported now would be left floating. (Roofs that were already unsupported never block.)
		for ruid in others:
			var r: Dictionary = others[ruid]
			if String(r.get("area", "surface")) != area_id:
				continue
			var rdef := Placement.def_of(String(r.get("id", "")))
			if Placement.snap_kind(rdef) != "roof2":
				continue
			var fp := Placement.record_footprint(r)
			if Placement.roof_supported(fp, now_ctx) and not Placement.roof_supported(fp, after_ctx):
				return {"ok": false, "reason": MSG_ROOF_ON_WALL if layer == "edge" else MSG_ROOF_ON_ROOF}
	if layer == "edge":
		# Wall decor hangs on its wall (data mount "wall"): the wall stays while something hangs on it.
		var hung := Placement.decor_on_wall(uid, now_ctx)
		if not hung.is_empty():
			var hid := String(GameState.structures[hung[0]].get("id", ""))
			return {"ok": false, "reason": MSG_DECOR_ON_WALL % ItemDB.structure_display_name(hid)}
	if not others.is_empty():
		var why := _storey_dependent(Placement.level_of(rec), layer, others, now_ctx, after_ctx, area_id)
		if why != "":
			return {"ok": false, "reason": why}
	return {"ok": true, "reason": ""}


## Upstairs pieces that rest on the piece being removed (validation only: nothing ever collapses). Returns the
## refusal reason, or "" when nothing that is held up now would be left floating. Pieces that were already
## unsupported (grandfathered) never block.
static func _storey_dependent(level: int, layer: String, others: Dictionary, now_ctx: Dictionary, after_ctx: Dictionary, area_id: String) -> String:
	for ouid in others:
		var r: Dictionary = others[ouid]
		if String(r.get("area", "surface")) != area_id:
			continue
		if Placement.level_of(r) < 1:
			continue
		var rdef := Placement.def_of(String(r.get("id", "")))
		var fp := Placement.record_footprint(r)
		if Placement.snap_kind(rdef) == "floor2":
			if Placement.upper_supported(fp, now_ctx) and not Placement.upper_supported(fp, after_ctx):
				return MSG_UPPER_ON_UPPER if (layer == "floor" and level >= 1) else MSG_UPPER_ON_SUPPORT
		elif Placement.snap_kind(rdef) != "roof2":
			if Placement.upper_rest_reason(rdef, fp, now_ctx) == "" and Placement.upper_rest_reason(rdef, fp, after_ctx) != "":
				return MSG_UPPER_CARRIES
	return ""


## Takes a structure apart: 100% refund of its item (overflow drops as a pickup, never lost), chest
## contents back into the backpack (only when they fit), crops harvested/seed returned.
## Returns {"ok", "reason", "refund"}.
static func dismantle(area: Node, uid: String) -> Dictionary:
	var chk := can_dismantle(uid)
	if not bool(chk["ok"]):
		return chk
	var rec: Dictionary = GameState.structures[uid]
	var sid: String = String(rec.get("id", ""))
	var def := Placement.def_of(sid)
	var pos := Placement.vec_from(rec.get("pos"))
	var drop := pos + Vector3.UP * 0.6
	var interact_kind: String = String(def.get("interact", ""))
	if interact_kind == "storage":
		var inv: Variant = GameState.storages.get(uid)
		if inv != null:
			for s in (inv.slots as Array).duplicate():
				if s != null:
					GameState.give_item(String(s["id"]), int(s["count"]), drop)
			inv.from_array([])
	if interact_kind == "farm" and Farming.is_planted(uid):
		if Farming.is_ripe(uid):
			Farming.harvest(uid, drop)
		else:
			var seed: String = String(ItemDB.crop(Farming.crop_id(uid)).get("seed", ""))
			if seed != "":
				GameState.give_item(seed, 1, drop)
	var data: Variant = rec.get("data", {})
	var was_bed_spawn: bool = sid == "bed" and data is Dictionary and bool(data.get("respawn", false))
	var level := Placement.level_of(rec)
	var cells: Array = Placement.footprint(def, pos, float(rec.get("rot", 0.0)))["cells"]
	GameState.remove_structure(uid)
	var node := Factory.find_node(area, uid)
	if node != null:
		if node.has_method("play_remove_and_free"):
			node.play_remove_and_free()
		else:
			node.queue_free()
	var refund: String = String(def.get("item", sid))
	GameState.give_item(refund, 1, drop)
	if String(def.get("layer", "")) == "floor" and level == 0:
		reseat_objects(area, cells)
	if was_bed_spawn:
		_forget_bed_spawn(area)
	notify_area(area)
	update_upstairs_flag(String(rec.get("area", "surface")))     # e.g. a wall taken down at the top of the stairs
	Events.structure_removed.emit(uid, sid)
	Audio.play_3d("build_remove", drop)
	return {"ok": true, "reason": "", "refund": refund}


## Undoes a placement made with `item_id` (BuildMode keeps the list): the same rules and exact refund as
## dismantling, and the build counter goes back down, so placing and undoing never adds progress (mastery
## only ever rewards the FIRST placement of each structure id; see data/mastery.gd). A piece that no longer
## exists (already dismantled or undone) refunds nothing. Returns {"ok", "reason", "refund"}.
static func undo_place(area: Node, uid: String, item_id: String) -> Dictionary:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary) or structure_for_item(item_id) != String((rec as Dictionary).get("id", "")):
		return {"ok": false, "reason": MSG_NOTHING_TO_UNDO}
	var res := dismantle(area, uid)
	if bool(res.get("ok", false)) and GameState.get_counter("structures_built") > 0:
		GameState.add_counter("structures_built", -1)
	return res


# --- Recolouring (uid, position and contents never change) -------------------------------------------------

## Tints this piece can take right now: [""(natural), owned dye palettes...] ([] = not recolourable).
static func tint_options(uid: String) -> Array:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return []
	return Tints.options_for(String((rec as Dictionary).get("id", "")))


## Recolours one placed piece in place: data.tint = a dye palette id Krystal owns ("" = natural wood). Keeps
## the uid, position, rotation, storage contents and crops; free (dyes are made once at the Loom).
## Returns {"ok", "reason", "tint"}.
static func recolor(area: Node, uid: String, tint_id: String) -> Dictionary:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return {"ok": false, "reason": "There's nothing to recolour here.", "tint": ""}
	var opts := tint_options(uid)
	if opts.is_empty():
		return {"ok": false, "reason": MSG_NO_TINT, "tint": ""}
	if not opts.has(tint_id):
		return {"ok": false, "reason": MSG_TINT_LOCKED, "tint": Tints.tint_of(rec)}
	var r: Dictionary = rec
	if not (r.get("data") is Dictionary):
		r["data"] = {}
	if tint_id == Tints.NATURAL:
		(r["data"] as Dictionary).erase("tint")
	else:
		r["data"]["tint"] = tint_id
	var node := Factory.find_node(area, uid)
	if node != null and node.has_method("apply_tint"):
		node.apply_tint(tint_id)
	return {"ok": true, "reason": "", "tint": tint_id}


## The next tint in the piece's options after its current one ("" when it can't be recoloured).
static func next_tint(uid: String) -> String:
	var opts := tint_options(uid)
	if opts.is_empty():
		return ""
	var cur := Tints.tint_of(GameState.structures.get(uid, {}))
	return String(opts[(maxi(opts.find(cur), 0) + 1) % opts.size()])


# --- Non-destructive audit ----------------------------------------------------------------------------------

## Saved pieces of an area that today's rules would not accept as new placements: [{"uid", "id", "issue"}]
## with issue "overlap:<uid>" (same occupancy cell/edge), "unsupported_roof", "unsupported_upper",
## "floating_upstairs", "outside_build_area" or "unknown_structure". Grandfathered: nothing is moved,
## dismantled or deleted; this only reports (BuildingSystem.attach prints it in debug builds).
static func audit(area_id: String) -> Array:
	var out: Array = []
	var ctx := {"structures": GameState.structures, "area_id": area_id}
	var ba := build_area_for(area_id)
	var seen := {}
	var uids: Array = GameState.structures.keys()
	uids.sort()
	for uid in uids:
		var rec: Dictionary = GameState.structures[uid]
		if String(rec.get("area", "surface")) != area_id:
			continue
		var sid := String(rec.get("id", ""))
		var def := Placement.def_of(sid)
		if def.is_empty():
			out.append({"uid": uid, "id": sid, "issue": "unknown_structure"})
			continue
		var fp := Placement.record_footprint(rec)
		var keys: Array = []
		for c in fp["cells"]:
			keys.append("%s|%s" % [fp["layer"], str(c)])
		for e in fp["edges"]:
			keys.append("%s|%s" % [fp["layer"], str(e)])
		for key in keys:
			if seen.has(key):
				out.append({"uid": uid, "id": sid, "issue": "overlap:%s" % seen[key]})
				break
			seen[key] = uid
		if not ba.is_empty() and not Placement.rect_in_build_area(fp["rect"], ba):
			out.append({"uid": uid, "id": sid, "issue": "outside_build_area"})
		var lv := int(fp["level"])
		if Placement.snap_kind(def) == "roof2":
			if not Placement.roof_supported(fp, ctx):
				out.append({"uid": uid, "id": sid, "issue": "unsupported_roof"})
		elif lv >= 1 and Placement.snap_kind(def) == "floor2":
			if not Placement.upper_supported(fp, ctx):
				out.append({"uid": uid, "id": sid, "issue": "unsupported_upper"})
		elif lv >= 1 and Placement.upper_rest_reason(def, fp, ctx) != "":
			out.append({"uid": uid, "id": sid, "issue": "floating_upstairs"})
	return out


## Objects standing on (ground) floor tiles are lifted onto (or lowered off) the floor after it changes.
## Upstairs pieces and stairs keep their height.
static func reseat_objects(area: Node, cells: Array) -> void:
	if cells.is_empty():
		return
	var ctx := make_ctx(area)
	var aid: String = ctx["area_id"]
	var cellset := {}
	for c in cells:
		cellset[c] = true
	for uid in GameState.structures:
		var rec: Dictionary = GameState.structures[uid]
		if String(rec.get("area", "surface")) != aid:
			continue
		var sid: String = String(rec.get("id", ""))
		var def := Placement.def_of(sid)
		if String(def.get("layer", "object")) in ["floor", "edge", "roof", "stair"] or Placement.level_of(rec) > 0:
			continue
		var pos := Placement.vec_from(rec.get("pos"))
		var rot := float(rec.get("rot", 0.0))
		var hit := false
		for c in Placement.footprint(def, pos, rot)["cells"]:
			if cellset.has(c):
				hit = true
				break
		if not hit:
			continue
		var y := Placement.placement_y_at(sid, pos, rot, ctx, 0)
		if absf(y - pos.y) > 0.004:
			rec["pos"] = [pos.x, y, pos.z]
			var n := Factory.find_node(area, uid)
			if n != null:
				n.position.y = y


static func _forget_bed_spawn(area: Node) -> void:
	if area != null and is_instance_valid(area):
		var sp: Variant = area.get("spawns")
		if sp is Dictionary:
			(sp as Dictionary).erase("bed")
	if String(GameState.player.get("respawn_spawn", "")) == "bed":
		Game.set_respawn(area_id_of(area), "haven_respawn")
		Events.notify.emit("Without your bed, you'll wake up in the Haven clearing.", "info")


# --- Area hook ------------------------------------------------------------------------------------------

## Footprints of every structure in an area: [{"uid", "id", "layer", "rect": Rect2 (x, z), "pos", "rot", "level"}]
## ("layer" is the plain data layer; "level" 0 = ground, 1 = upstairs).
static func footprints(area_id: String) -> Array:
	var out: Array = []
	for uid in GameState.structures:
		var rec: Dictionary = GameState.structures[uid]
		if String(rec.get("area", "surface")) != area_id:
			continue
		var sid: String = String(rec.get("id", ""))
		var def := Placement.def_of(sid)
		if def.is_empty():
			continue
		var pos := Placement.vec_from(rec.get("pos"))
		var fp := Placement.footprint(def, pos, float(rec.get("rot", 0.0)))
		out.append({"uid": uid, "id": sid, "layer": fp["layer"], "rect": fp["rect"], "pos": pos, "rot": float(rec.get("rot", 0.0)),
			"level": Placement.level_of(rec)})
	return out


## Optional area hook: areas implementing on_structures_changed(footprints: Array) are told whenever the
## set of structures changes (e.g. the surface hides its GPU grass under floors, plots and furniture).
static func notify_area(area: Node) -> void:
	if area != null and is_instance_valid(area) and area.has_method("on_structures_changed"):
		area.on_structures_changed(footprints(area_id_of(area)))

