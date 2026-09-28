extends "res://src/building/structure.gd"
## Companion Bed / Companion Perch (data/structures.gd interact "nook"; mapped by structure_factory.gd's
## LAZY_SCRIPTS, spec §9): interacting makes it a befriended companion's home spot (MP §6.5). Pressing again
## offers the next friend (a perch suggests Lumi first, a bed Mochi, then Pebble). The choice is saved in
## the companion record ("home_spot" [x,y,z] + "home_nook" uid) and in this structure's data ("companion");
## the spawner puts that companion's Haven home here, companion.gd walks it here, the Chapter Two quest layer
## and the optional goal "A Room for Friends" read home_spot. Dismantling the nook sends the friend back to
## its default home spot (companion.gd listens to Events.structure_removed; the spawner repairs old saves).

const Logic := preload("res://src/companions/companion_logic.gd")

const PERCH_ORDER := ["lumi", "mochi", "pebble"]
const BED_ORDER := ["mochi", "pebble", "lumi"]


func _setup_behaviour() -> void:
	add_to_group("companion_nook")


func is_perch() -> bool:
	return structure_id == "companion_perch"


## Companion whose home spot this is ("" = nobody yet).
func owner_id() -> String:
	var data: Variant = record().get("data", {})
	var cid := String((data as Dictionary).get("companion", "")) if data is Dictionary else ""
	if cid != "" and String(GameState.companion(cid).get("home_nook", "")) != uid:
		return ""        # it moved to another nook since
	return cid


## Who pressing "interact" would give this spot to next ("" = nobody to offer).
func next_candidate() -> String:
	var order: Array = PERCH_ORDER if is_perch() else BED_ORDER
	var cur := owner_id()
	var start := order.find(cur) + 1 if cur != "" else 0
	for k in order.size():
		var cid := String(order[(start + k) % order.size()])
		if cid != cur and GameState.companions.has(cid) and GameState.is_befriended(cid):
			return cid
	return ""


## The standing spot of this nook (world position; the nook itself is not solid).
func spot() -> Vector3:
	if is_inside_tree():
		return global_position
	var v: Variant = Logic.vec_from(record().get("pos"))
	return v if v is Vector3 else position


func get_interaction(_player: Node) -> Dictionary:
	if _removing:
		return {}
	var kind := "perch" if is_perch() else "bed"
	if not _at_haven():
		return {"text": display_name(), "enabled": false, "reason": "Your friends' beds and perches belong at home in the Haven"}
	var cur := owner_id()
	var cand := next_candidate()
	if cand == "":
		if cur != "":
			return {"text": "%s's %s" % [_name(cur), kind], "enabled": false, "reason": "Already its home spot"}
		return {"text": display_name(), "enabled": false, "reason": "Befriend a companion first"}
	return {"text": "Make this %s's %s" % [_name(cand), kind], "enabled": true}


func interact(_player: Node) -> void:
	var cand := next_candidate()
	if cand != "":
		assign(cand)


## Makes this nook `cid`'s home spot. Returns true when assigned.
func assign(cid: String) -> bool:
	if cid == "" or not GameState.is_befriended(cid) or uid == "":
		return false
	var rec_s := record()
	if rec_s.is_empty() or not _at_haven():
		return false
	var prev := owner_id()
	# The previous owner of this nook goes back to its default home spot.
	if prev != "" and prev != cid:
		_clear_owner(prev)
	# `cid` leaves its old nook (if any).
	var old_nook := String(GameState.companion(cid).get("home_nook", ""))
	if old_nook != "" and old_nook != uid and GameState.structures.has(old_nook):
		var od: Variant = GameState.structures[old_nook].get("data")
		if od is Dictionary:
			(od as Dictionary).erase("companion")
	var data: Variant = rec_s.get("data")
	if not (data is Dictionary):
		data = {}
		rec_s["data"] = data
	(data as Dictionary)["companion"] = cid
	var p := spot()
	var crec := GameState.companion(cid)
	crec["home_spot"] = [p.x, p.y, p.z]
	crec["home_nook"] = uid
	var node: Variant = Game.companion_nodes.get(cid)
	if node is Node and is_instance_valid(node):
		if (node as Node).has_method("set_home_spot"):
			(node as Node).call("set_home_spot", p)
		if (node as Node).has_method("react"):
			(node as Node).call("react", "happy")
	Events.notify.emit("This %s is %s's home spot now." % ["perch" if is_perch() else "bed", _name(cid)], "success")
	GameState.request_quest_eval()
	return true


func _clear_owner(cid: String) -> void:
	var crec := GameState.companion(cid)
	if String(crec.get("home_nook", "")) != uid:
		return
	crec["home_nook"] = ""
	crec["home_spot"] = null
	var node: Variant = Game.companion_nodes.get(cid)
	if node is Node and is_instance_valid(node) and (node as Node).has_method("set_home_spot"):
		(node as Node).call("set_home_spot", null)


## Home spots live in the Haven (the spawner applies them on the surface only; a nook elsewhere, e.g. from an
## old save or another build area, must not move a Haven home to other-area coordinates).
func _at_haven() -> bool:
	return Logic.is_surface_area(String(record().get("area", "surface")))


static func _name(cid: String) -> String:
	return String(ItemDB.creature(cid).get("name", cid.capitalize()))
