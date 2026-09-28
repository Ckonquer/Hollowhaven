extends RefCounted
## ENTRY POINT of the Haven building system (called by Game right after the surface area loads, and in
## Hallowmere Reach for the small optional outpost at the Commons):
##   BuildingSystem.attach(area)
## Spawns every saved structure of that area (GameState.structures) under area/"Structures" and adds
## the BuildMode node (group "build_mode": begin(item_id), is_active()).
## Other modules may also use:
##   BuildingSystem.spawn_structure(area, uid) -> Node3D
##   BuildingSystem.find_structure(uid) -> Node3D       (in the current area)
##   BuildingSystem.build_mode() -> Node                 (the active BuildMode node or null)
##   BuildingSystem.footprints(area_id) -> Array          [{uid, id, layer, rect: Rect2(x, z), pos, rot}]
## Areas may implement on_structures_changed(footprints: Array); it is called after attach and after
## every place/dismantle (e.g. to hide grass under floors, crop plots and furniture).

const Factory := preload("res://src/building/structure_factory.gd")
const Ops := preload("res://src/building/build_ops.gd")
const BuildModeScript := preload("res://src/building/build_mode.gd")


static func attach(area: Node) -> void:
	if area == null or not is_instance_valid(area):
		return
	var aid := Ops.area_id_of(area)
	Factory.structures_root(area)
	var count := 0
	for uid in GameState.structures.keys():
		var rec: Variant = GameState.structures[uid]
		if rec is Dictionary and String(rec.get("area", "surface")) == aid:
			if Factory.spawn_structure(area, String(uid)) != null:
				count += 1
	Ops.notify_area(area)
	Ops.update_upstairs_flag(aid)     # repairs "A House With an Upstairs" for a save made before the flag existed
	if area.get_node_or_null("BuildMode") == null:
		var bm: Node = BuildModeScript.new()
		bm.name = "BuildMode"
		area.add_child(bm)
	if count > 0:
		print("BuildingSystem: spawned %d structures in %s" % [count, aid])
		if OS.is_debug_build():
			_report_audit(aid)


## Debug builds: one line about grandfathered pieces that today's rules would refuse (reported, never touched).
static func _report_audit(aid: String) -> void:
	var issues := Ops.audit(aid)
	if issues.is_empty():
		return
	var kinds := {}
	for i in issues:
		var k := String(i["issue"]).get_slice(":", 0)
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("BuildingSystem: kept %d saved pieces as they are (%s), e.g. %s" % [issues.size(), str(kinds), str(issues[0])])


static func spawn_structure(area: Node, uid: String) -> Node3D:
	return Factory.spawn_structure(area, uid)


static func find_structure(uid: String) -> Node3D:
	return Factory.find_node(Game.area, uid)


static func build_mode() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("build_mode")


static func footprints(area_id: String = "surface") -> Array:
	return Ops.footprints(area_id)

