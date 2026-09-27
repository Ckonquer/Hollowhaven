extends RefCounted
## Build operations shared by BuildMode, BuildingSystem and tests: the validation context for an area,
## placing (consumes exactly one item) and dismantling (100% refund, chest and roof rules).
## All state changes go through GameState; nodes are spawned/freed to match.

const Placement := preload("res://src/building/placement.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Farming := preload("res://src/farming/farming.gd")
const Layout := preload("res://data/world_layout.gd")
const InventoryScript := preload("res://src/core/inventory.gd")

## Debug builds only: the test arena (--area=arena) gets a generous build circle so build mode can be
## exercised there. Release builds only ever allow the Haven.
const DEBUG_BUILD_AREA := {"center": Vector2(0, 0), "radius": 30.0, "grid": 1.0, "blocked": []}

## Friendly names for the Haven's keep-clear circles (matched by centre), so a refusal says
## "Too close to the Ward Stone" instead of a generic message. Unknown circles stay generic.
const BLOCKED_NAMES := {Vector2(0, -6): "Ward Stone", Vector2(4, 3): "campfire"}

static var _haven_area: Dictionary = {}

const MSG_CHEST_FULL := "Empty the chest first. Your backpack can't hold everything inside."
const MSG_ROOF_ON_WALL := "Take down the roof resting on this wall first."
const MSG_ROOF_ON_ROOF := "Take down the roof tile leaning on this one first."


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


static func make_ctx(area: Node, player_pos: Variant = null) -> Dictionary:
	var aid := area_id_of(area)
	var ctx := {"structures": GameState.structures, "area_id": aid, "build_area": build_area_for(aid)}
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
static func place_structure(area: Node, item_id: String, pos: Vector3, rot_deg: float) -> String:
	var sid := structure_for_item(item_id)
	if sid == "":
		return ""
	if not GameState.take_item(item_id, 1):
		return ""
	var uid := GameState.add_structure(sid, pos, rot_deg, area_id_of(area))
	var node := Factory.spawn_structure(area, uid)
	if node != null and node.has_method("play_place_anim"):
		node.play_place_anim()
	var def := Placement.def_of(sid)
	if String(def.get("layer", "")) == "floor":
		reseat_objects(area, Placement.footprint(def, pos, rot_deg)["cells"])
	GameState.add_counter("structures_built")
	notify_area(area)
	Events.structure_placed.emit(uid, sid)
	Audio.play_3d("build_place", pos + Vector3.UP * 0.4)
	return uid


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
	if layer == "edge" or layer == "roof":
		# Walls hold roofs up, and a roof tile can hold up its neighbour: refuse if any roof that is
		# supported now would be left floating. (Roofs that were already unsupported never block.)
		var others: Dictionary = GameState.structures.duplicate()
		others.erase(uid)
		var area_id: String = String(rec.get("area", "surface"))
		var now_ctx := {"structures": GameState.structures, "area_id": area_id}
		var after_ctx := {"structures": others, "area_id": area_id}
		for ruid in others:
			var r: Dictionary = others[ruid]
			if String(r.get("area", "surface")) != area_id:
				continue
			var rdef := Placement.def_of(String(r.get("id", "")))
			if Placement.snap_kind(rdef) != "roof2":
				continue
			var fp := Placement.footprint(rdef, Placement.vec_from(r.get("pos")), float(r.get("rot", 0.0)))
			if Placement.roof_supported(fp, now_ctx) and not Placement.roof_supported(fp, after_ctx):
				return {"ok": false, "reason": MSG_ROOF_ON_WALL if layer == "edge" else MSG_ROOF_ON_ROOF}
	return {"ok": true, "reason": ""}


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
	if String(def.get("layer", "")) == "floor":
		reseat_objects(area, cells)
	if was_bed_spawn:
		_forget_bed_spawn(area)
	notify_area(area)
	Events.structure_removed.emit(uid, sid)
	Audio.play_3d("build_remove", drop)
	return {"ok": true, "reason": "", "refund": refund}


## Objects standing on floor tiles are lifted onto (or lowered off) the floor after it changes.
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
		if String(def.get("layer", "object")) in ["floor", "edge", "roof"]:
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
		var y := Placement.placement_y(sid, pos, rot, ctx)
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

## Footprints of every structure in an area: [{"uid", "id", "layer", "rect": Rect2 (x, z), "pos", "rot"}].
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
		out.append({"uid": uid, "id": sid, "layer": fp["layer"], "rect": fp["rect"], "pos": pos, "rot": float(rec.get("rot", 0.0))})
	return out


## Optional area hook: areas implementing on_structures_changed(footprints: Array) are told whenever the
## set of structures changes (e.g. the surface hides its GPU grass under floors, plots and furniture).
static func notify_area(area: Node) -> void:
	if area != null and is_instance_valid(area) and area.has_method("on_structures_changed"):
		area.on_structures_changed(footprints(area_id_of(area)))

