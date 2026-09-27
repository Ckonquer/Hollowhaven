extends "res://tests/test_case.gd"
## Every structure in data/structures.gd builds a node with the right colliders, groups and
## interactions; the bed sleep flow; the chest lid; lamps as light sources.

const Factory := preload("res://src/building/structure_factory.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _area: Node3D


func before_each() -> void:
	fresh_state()
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)


func after_each() -> void:
	if is_instance_valid(_area):
		_area.free()


func _bodies(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is CollisionObject3D:
			out.append(c)
	return out


func test_every_structure_builds_with_correct_physics() -> void:
	for sid in ItemDB.all_structure_ids():
		var def := ItemDB.structure(sid)
		var uid := GameState.add_structure(sid, Vector3(0, 0, 0), 0)
		var n := Factory.spawn_structure(_area, uid)
		assert_not_null(n, "spawned " + sid)
		if n == null:
			continue
		assert_true(n.get_node("Model").get_child_count() > 0, sid + " has a model")
		var solid := false
		var interact := false
		for b in _bodies(n):
			var co := b as CollisionObject3D
			assert_eq(co.collision_mask, 0, sid + " colliders don't scan")
			assert_true(co.has_meta("surface"), sid + " collider has a footstep surface")
			if co.collision_layer == 32:
				solid = true
			if co.collision_layer == 16:
				interact = true
		assert_eq(solid, bool(def.get("solid", false)), sid + " solid collider matches data")
		assert_eq(interact, String(def.get("interact", "")) != "", sid + " interaction collider matches data")
		if interact:
			assert_true(n.is_in_group("interactable"), sid + " interactable group")
			var info: Dictionary = n.get_interaction(null)
			assert_true(info.has("text") and info.has("enabled"), sid + " interaction contract")
		n.free()


func test_lamps_are_light_sources() -> void:
	for sid in ["lantern_post", "heartbloom_lamp"]:
		var n := Factory.spawn_structure(_area, GameState.add_structure(sid, Vector3.ZERO, 0))
		assert_true(n.is_in_group("light_source"), sid)
		assert_true(float(n.get("light_radius")) > 1.0, sid + " radius")
		assert_true(n.is_light_active())
		var light := n.get_node_or_null("Light") as OmniLight3D
		assert_not_null(light)
		assert_false(light.shadow_enabled, "no shadowed lights (performance)")
		n.free()


func test_chest_opens_storage_panel_and_lid() -> void:
	var uid := GameState.add_structure("storage_chest", Vector3.ZERO, 0)
	var n := Factory.spawn_structure(_area, uid)
	GameState.get_storage(uid).add("stone", 5)
	assert_true(String(n.get_interaction(null)["text"]).contains("(1/20)"), String(n.get_interaction(null)["text"]))
	n.interact(null)
	assert_true(n.is_open())
	await wait_seconds(0.45)
	assert_true(n.parts["lid"].rotation_degrees.x < -90.0, "lid swung open")
	Events.ui_stack_changed.emit(0)
	assert_false(n.is_open(), "closes with the UI")
	n.free()


func test_bed_sleep_skips_to_morning_heals_sets_respawn_and_saves() -> void:
	var uid := GameState.add_structure("bed", Vector3(2.5, 0, 3.0), 90)
	var n := Factory.spawn_structure(_area, uid)
	GameState.total_minutes = 21.5 * 60.0
	var day_before := GameState.day()
	GameState.player["hp"] = 12.0
	assert_true(bool(n.get_interaction(null)["enabled"]))
	await n.sleep(null)
	assert_eq(GameState.day(), day_before + 1, "next day")
	assert_almost(GameState.hour(), 7.0, 0.01, "woke at 7:00")
	assert_almost(float(GameState.player["hp"]), 100.0, 0.01, "healed")
	assert_eq(String(GameState.player["respawn_spawn"]), "bed")
	assert_true(bool(GameState.structures[uid]["data"]["respawn"]))
	assert_true(_area.spawns.has("bed"), "wake spawn registered")
	var wake: Transform3D = _area.spawns["bed"]
	assert_true(wake.origin.distance_to(n.global_position) > 0.9, "wakes beside the bed, not in it")
	assert_true(SaveSystem.has_save(), "journey saved")


func test_crafting_station_and_banner_text() -> void:
	var wb := Factory.spawn_structure(_area, GameState.add_structure("workbench", Vector3.ZERO, 0))
	assert_true(wb.is_in_group("crafting_station"))
	assert_eq(String(wb.station_id), "workbench")
	var banner := Factory.spawn_structure(_area, GameState.add_structure("haven_banner", Vector3(3, 0, 0), 0))
	var found := false
	for l in banner.find_children("*", "Label3D", true, false):
		if String((l as Label3D).text).contains("Krystal's"):
			found = true
	assert_true(found, "banner says Krystal's Haven")


func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var ix: Variant = arr[Mesh.ARRAY_INDEX]
			t += (ix as PackedInt32Array).size() / 3 if ix != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			var arr2 := mm.mesh.surface_get_arrays(0)
			t += (arr2[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 * mm.instance_count
	for c in n.get_children():
		t += _tris(c)
	return t


## Performance guard: every structure stays within a modest triangle budget (the whole cottage with
## garden is ~35 pieces) and uses few draw calls (meshes are baked per structure).
func test_structures_stay_within_geometry_budget() -> void:
	var report: PackedStringArray = []
	for sid in ItemDB.all_structure_ids():
		var n := Factory.spawn_structure(_area, GameState.add_structure(sid, Vector3.ZERO, 0))
		var tris := _tris(n.get_node("Model"))
		var meshes := n.get_node("Model").find_children("*", "GeometryInstance3D", true, false).size()
		report.append("%s=%d/%d" % [sid, tris, meshes])
		assert_true(tris < 9000, "%s has %d triangles" % [sid, tris])
		assert_true(meshes <= 8, "%s uses %d mesh instances" % [sid, meshes])
		n.free()
	print("Structure triangles/meshes: ", ", ".join(report))

