extends "res://tests/test_case.gd"
## AUDIT (persistence integration, surface): builds the real surface through Game.load_area (headless),
## saves, resets GameState, loads and re-enters the area, then checks that the WORLD matches the state.
## Game.load_area uses change_scene_to_file, so each load first swaps in a throwaway current scene: the
## runner (our parent) is never freed.

const BuildingSystem := preload("res://src/building/building_system.gd")
const Farming := preload("res://src/farming/farming.gd")
const Logic := preload("res://src/companions/companion_logic.gd")

var _runner: Node = null
var _saved_mode: String = "boot"


func before_each() -> void:
	_runner = get_parent()
	_saved_mode = Game.mode
	fresh_state()


func after_each() -> void:
	await _leave_game()


# --- harness -----------------------------------------------------------------------------------------

func _enter(area_id: String, spawn_id: String, use_saved: bool) -> Node:
	var tree := get_tree()
	if tree.current_scene == _runner or tree.current_scene == null:
		var ph := Node.new()
		ph.name = "AuditPlaceholder"
		tree.root.add_child(ph)
		tree.current_scene = ph
	await Game.load_area(area_id, spawn_id, use_saved)
	await wait_physics(3)
	return Game.area


func _continue() -> bool:
	var tree := get_tree()
	if tree.current_scene == _runner or tree.current_scene == null:
		var ph := Node.new()
		ph.name = "AuditPlaceholder"
		tree.root.add_child(ph)
		tree.current_scene = ph
	var ok: bool = await Game.continue_game()
	await wait_physics(3)
	return ok


## Save -> wipe the runtime state -> load from disk (like quitting and pressing Continue).
func _save_reset_load() -> void:
	assert_true(SaveSystem.save_game(), "save ok")
	GameState.reset()
	GameState.active = false
	assert_true(SaveSystem.load_game(), "load ok")


func _leave_game() -> void:
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur != _runner and is_instance_valid(cur):
		cur.queue_free()
	tree.current_scene = _runner
	Game.mode = _saved_mode
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game._ui_stack.clear()
	Game._transitioning = false
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	for n in tree.root.get_children():
		if n != _runner and String(n.name) in ["AuditPlaceholder", "Title", "Surface", "Below"]:
			n.queue_free()
	tree.paused = false
	Engine.time_scale = 1.0
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


func _structure_node(uid: String) -> Node3D:
	return BuildingSystem.find_structure(uid)


func _world_items(uid: String) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and String(n.get("uid")) == uid:
			out.append(n)
	return out


# --- structures ----------------------------------------------------------------------------------------

func test_structures_chest_crop_bed_come_back_with_their_data() -> void:
	var chest := GameState.add_structure("storage_chest", Vector3(6, 0, 6), 90.0)
	var plot := GameState.add_structure("crop_plot", Vector3(-6, 0, 8), 0.0)
	var bed := GameState.add_structure("bed", Vector3(8, 0, -2), 180.0)
	GameState.get_storage(chest).add("wood", 17)
	GameState.get_storage(chest).add("berries", 4)
	GameState.give_item("sweetroot_seeds", 1)
	assert_true(Farming.plant(plot, "sweetroot_seeds"), "planted")
	GameState.crops[plot]["planted_at"] = GameState.total_minutes - 200.0   # 200/360: leafy
	var area := await _enter("surface", "haven_start", false)
	assert_not_null(area, "surface loaded")
	var bnode := _structure_node(bed)
	assert_not_null(bnode, "bed spawned")
	# Sleep for real (saves through SaveSystem, marks the bed as the respawn).
	await bnode.sleep(Game.player)
	assert_eq(String(GameState.player["respawn_spawn"]), "bed", "respawn at the bed")
	var stage_before := Farming.stage(plot)
	var minutes := GameState.total_minutes
	GameState.reset()
	GameState.active = false
	var ok := await _continue()
	assert_true(ok, "continue ok")
	assert_eq(Game.area_id, "surface", "back on the surface")
	var cnode := _structure_node(chest)
	assert_not_null(cnode, "chest respawned")
	if cnode != null:
		assert_true(cnode.position.distance_to(Vector3(6, cnode.position.y, 6)) < 0.01, "chest position")
		assert_almost(rad_to_deg(cnode.rotation.y), 90.0, 0.5, "chest rotation")
	assert_eq(GameState.get_storage(chest).count_of("wood"), 17, "chest wood")
	assert_eq(GameState.get_storage(chest).count_of("berries"), 4, "chest berries")
	var pnode := _structure_node(plot)
	assert_not_null(pnode, "plot respawned")
	assert_almost(GameState.total_minutes, minutes, 5.0, "clock restored")
	assert_eq(Farming.stage(plot), stage_before, "crop stage restored")
	if pnode != null:
		assert_eq(int(pnode.current_stage()), stage_before, "plot view shows the saved stage")
	assert_not_null(_structure_node(bed), "bed respawned")
	await wait_frames(2)
	assert_true(Game.area.spawns.has("bed"), "bed spawn registered again after continue")
	assert_eq(String(GameState.player["respawn_spawn"]), "bed", "respawn still the bed")
	var bxf: Transform3D = Game.area.get_spawn("bed")
	assert_true(Game.player.global_position.distance_to(bxf.origin) < 1.5, "Krystal wakes beside the bed on continue (%s vs %s)" % [str(Game.player.global_position), str(bxf.origin)])


# --- harvestables ----------------------------------------------------------------------------------------

func _far_node(area: Node, kind: String) -> Node3D:
	var nodes: Dictionary = area.vegetation.resource_nodes
	var ids: Array = nodes.keys()
	ids.sort()
	for id in ids:
		var n: Node3D = nodes[id]
		if String(n.get("kind")) == kind and n.global_position.distance_to(Game.player.global_position) > 12.0:
			return n
	return null


func test_felled_tree_stays_felled_after_continue_and_regrows_on_time() -> void:
	var area := await _enter("surface", "haven_start", false)
	GameState.give_item("stone_axe", 1)
	var tree := _far_node(area, "tree")
	assert_not_null(tree, "a tree")
	if tree == null:
		return
	var tid := String(tree.get("node_id"))
	for i in 6:
		tree.harvest_hit(Game.player, "stone_axe")
	assert_true(bool(tree.get("depleted")), "felled")
	assert_true(GameState.depleted.has(tid), "depletion recorded")
	var due := float(GameState.depleted[tid])
	_save_reset_load()
	await _enter("surface", "haven_start", true)
	var tree2: Node3D = Game.area.vegetation.resource_nodes.get(tid)
	assert_not_null(tree2, "same tree id after reload")
	if tree2 == null:
		return
	assert_true(bool(tree2.get("depleted")), "still felled after continue")
	assert_false(tree2.is_in_group("harvestable"), "a stump is not harvestable")
	# Time passes: once the respawn time is reached the tree grows back within a few seconds.
	GameState.total_minutes = due + 1.0
	await wait_seconds(2.6)
	assert_false(bool(tree2.get("depleted")), "regrew once the respawn time passed")
	assert_false(GameState.depleted.has(tid), "record cleared")


# --- dropped overflow ------------------------------------------------------------------------------------

func test_overflow_drop_reappears_exactly_once_and_never_after_pickup() -> void:
	await _enter("surface", "haven_start", false)
	# Fill the backpack with single, unstackable tools.
	while GameState.inventory.space_for("stone_axe") > 0:
		GameState.inventory.add("stone_axe", 1)
	var dpos: Vector3 = Game.player.global_position + Vector3(3.0, 0.0, 0.0)
	var added := GameState.give_item("wood", 7, dpos)
	assert_eq(added, 0, "backpack full")
	assert_eq(GameState.dropped.size(), 1, "one drop record")
	var uid := String(GameState.dropped[0]["uid"])
	await wait_frames(2)
	assert_eq(_world_items(uid).size(), 1, "one pickup node now")
	_save_reset_load()
	await _enter("surface", "haven_start", true)
	assert_eq(GameState.dropped.size(), 1, "still one drop record")
	assert_eq(_world_items(uid).size(), 1, "exactly one pickup after continue")
	# Re-entering the area (e.g. down to the mine and back) must not duplicate it either.
	await _enter("surface", "haven_start", false)
	assert_eq(_world_items(uid).size(), 1, "exactly one pickup after a second load")
	# Make room and pick it up; after save/load it is gone for good.
	GameState.inventory.from_array([])
	var items := _world_items(uid)
	if items.size() == 1:
		assert_eq(int(items[0].collect(Game.player)), 7, "picked up all 7")
	assert_eq(GameState.count_item("wood"), 7, "wood in the bag")
	assert_eq(GameState.dropped.size(), 0, "drop record removed")
	_save_reset_load()
	await _enter("surface", "haven_start", true)
	assert_eq(get_tree().get_nodes_in_group("world_item").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion()).size(), 0, "no pickups come back")
	assert_eq(GameState.count_item("wood"), 7, "wood kept")



# --- companions --------------------------------------------------------------------------------------------

func _befriend_all() -> void:
	for id in ["mochi", "pebble", "lumi"]:
		GameState.companion(id)["befriended"] = true
		GameState.companion(id)["assignment"] = "home"
	GameState.deplete(Logic.PINNED_BOULDER_ID, -1.0)


func test_companions_follow_wait_home_restore_in_place() -> void:
	_befriend_all()
	var area := await _enter("surface", "haven_start", false)
	var wait_spot: Vector3 = area.get_spawn("haven_start").origin + Vector3(6.0, 0.0, 3.0)
	wait_spot.y = float(area.height_at(wait_spot.x, wait_spot.z))
	GameState.set_companion_assignment("mochi", "follow")
	GameState.set_companion_assignment("pebble", "wait", "surface", wait_spot)
	GameState.set_companion_assignment("lumi", "home")
	_save_reset_load()
	await _enter("surface", String(GameState.player.get("spawn", "haven_start")), true)
	var nodes: Dictionary = Game.companion_nodes
	assert_eq(nodes.size(), 3, "three companions")
	assert_eq(GameState.active_companion, "mochi", "mochi still the follower")
	if nodes.has("mochi"):
		assert_eq(String(nodes["mochi"].mode), "follow", "mochi follows")
		assert_true((nodes["mochi"] as Node3D).global_position.distance_to(Game.player.global_position) < 4.0, "mochi beside Krystal")
	if nodes.has("pebble"):
		assert_eq(String(nodes["pebble"].mode), "wait", "pebble waits")
		var pp: Vector3 = (nodes["pebble"] as Node3D).global_position
		assert_true(Vector2(pp.x - wait_spot.x, pp.z - wait_spot.z).length() < 0.5, "pebble at its wait spot (%s vs %s)" % [str(pp), str(wait_spot)])
	if nodes.has("lumi"):
		assert_eq(String(nodes["lumi"].mode), "home", "lumi at home")


func test_mochi_waits_at_the_threshold_through_a_below_save_and_rejoins_on_the_way_out() -> void:
	_befriend_all()
	GameState.give_item("lantern", 1)
	await _enter("surface", "haven_start", false)
	GameState.set_companion_assignment("mochi", "follow")
	# Straight into the mine with Mochi following (Game.change_area autosaves on arrival).
	await Game.change_area("below", "mine_entry")
	await wait_physics(3)
	assert_eq(Game.area_id, "below", "in the Below")
	assert_false(Game.companion_nodes.has("mochi"), "Mochi never comes below")
	var rec := GameState.companion("mochi")
	assert_eq(String(rec["assignment"]), "wait", "Mochi waits")
	assert_eq(String(rec["wait_area"]), "surface", "...on the surface")
	# Quit and continue in the Below.
	GameState.reset()
	GameState.active = false
	assert_true(await _continue(), "continue")
	assert_eq(Game.area_id, "below", "continued below")
	assert_false(Game.companion_nodes.has("mochi"), "still no Mochi below")
	# Climb out: Mochi bounces over and rejoins.
	await Game.change_area("surface", "mine_exit")
	await wait_physics(10)
	assert_eq(GameState.active_companion, "mochi", "Mochi rejoins as follower")
	var m: Node3D = Game.companion_nodes.get("mochi")
	assert_not_null(m, "Mochi on the surface")
	if m != null:
		var thr: Vector3 = Game.area.get_spawn("mine_threshold").origin
		assert_true(Vector2(m.global_position.x - thr.x, m.global_position.z - thr.z).length() < 8.0, "Mochi near the threshold (%s vs %s)" % [str(m.global_position), str(thr)])
		assert_true(absf(m.global_position.y - float(Game.area.height_at(m.global_position.x, m.global_position.z))) < 1.0, "Mochi on the ground, not buried (%s, ground %.2f)" % [str(m.global_position), float(Game.area.height_at(m.global_position.x, m.global_position.z))])


func test_lumi_told_to_wait_below_is_still_there_after_a_lantern_save() -> void:
	_befriend_all()
	GameState.give_item("lantern", 1)
	await _enter("surface", "haven_start", false)
	GameState.set_companion_assignment("lumi", "follow")
	await Game.change_area("below", "mine_entry")
	await wait_physics(5)
	var lumi: Node3D = Game.companion_nodes.get("lumi")
	assert_not_null(lumi, "Lumi came below")
	if lumi == null:
		return
	lumi.command("wait")
	var wp: Vector3 = lumi.global_position
	assert_eq(String(GameState.companion("lumi")["wait_area"]), "below", "waiting below")
	# Save at the landing lantern, quit, continue.
	var cp: Node = Game.area.checkpoints.get("landing")
	assert_not_null(cp, "landing lantern")
	if cp != null:
		cp.interact(Game.player)
	GameState.reset()
	GameState.active = false
	assert_true(await _continue(), "continue")
	var l2: Node3D = Game.companion_nodes.get("lumi")
	assert_not_null(l2, "Lumi is still below")
	if l2 != null:
		assert_eq(String(l2.mode), "wait", "still waiting")
		assert_true(Vector2(l2.global_position.x - wp.x, l2.global_position.z - wp.z).length() < 0.6, "where Krystal left her")




# --- player position -----------------------------------------------------------------------------------------

## Writes the current GameState to slot1.json exactly as it is (SaveSystem.save_game would let the live
## player node overwrite player.pos first).
func _write_save_as_is() -> void:
	var f := FileAccess.open(SaveSystem.save_dir.path_join("slot1.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(SaveSystem.build_save_data()))
	f.close()


func test_saved_on_a_stream_crossing_continues_there() -> void:
	# Krystal saves (pause menu) while standing in the middle of a bridge / on the stepping stones.
	var area := await _enter("surface", "haven_start", false)
	var crossings: Array = area.water.crossings
	assert_eq(crossings.size(), 3, "three crossings")
	var space := (area as Node3D).get_world_3d().direct_space_state
	var report: Array = []
	for c in crossings:
		var center: Vector3 = c["pos"]
		var q := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 6.0, center + Vector3.DOWN * 6.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			report.append("%s: no walkway under the centre" % c["style"])
			continue
		var top: Vector3 = hit["position"]
		var ok: Variant = area.validate_position(top + Vector3.UP * 0.02)
		var depth: float = float(area.water_level_at(top.x, top.z)) - float(area.height_at(top.x, top.z))
		if not (ok is Vector3) or (ok as Vector3).distance_to(top) > 0.5:
			report.append("%s at %s (water %.2f m deep): validate_position -> %s" % [c["style"], str(top.snapped(Vector3.ONE * 0.01)), depth, str(ok)])
	assert_true(report.is_empty(), "a position saved on a crossing is accepted: " + str(report))
	# End to end on the stepping stones: Continue resumes there (it used to fall back to the last
	# arrival spawn - the Haven start, or the mine mouth after a trip below).
	var center0: Vector3 = crossings[0]["pos"]
	var hit0 := space.intersect_ray(PhysicsRayQueryParameters3D.create(center0 + Vector3.UP * 6.0, center0 + Vector3.DOWN * 6.0, 1))
	var top0: Vector3 = hit0["position"] if not hit0.is_empty() else center0
	GameState.player["pos"] = [top0.x, top0.y + 0.02, top0.z]
	_write_save_as_is()
	GameState.reset()
	GameState.active = false
	assert_true(await _continue(), "continue")
	assert_true(Game.player.global_position.distance_to(top0) < 1.0, "Continue resumes on the crossing (saved %s, resumed at %s)" % [str(top0), str(Game.player.global_position)])
