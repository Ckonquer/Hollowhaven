extends "res://tests/test_case.gd"
## Story module C9 through the REAL Game flow (Game.load_area, the gameplay UI root, the story tracker):
## Krystal comes back up into Hallowmere Reach after the Choir -> ch2_returned_to_reach, the festival roads
## and the Commons' Lanternwake lantern appear; before the homecoming the lantern only points her home; after
## it, "Celebrate" there runs the whole ending: rewards committed and saved first, the celebration at the
## Commons, the Chapter Two ending screen on the real UI root, Continue -> free play in the same save, the
## lantern now a lasting safe light. The Haven side runs on the REAL surface too: the homecoming at the real Ward
## Stone, "Celebrate" from its menu, the festival ring around the real Haven (nothing inside a collider, nothing
## over the build area), a camera shot validated against the real world (or the player's own camera), the ending
## screen, the keepsake, and the keepsake rebuilt after a reload.
## The runner scene is protected like test_flow_ch2_roundtrip: current_scene is swapped for a placeholder.

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const ReachDressing := preload("res://src/world/story_ch2/reach_dressing.gd")
const HavenDressing := preload("res://src/world/story_ch2/haven_dressing.gd")
const Celebration := preload("res://src/world/story_ch2/celebration.gd")
const Reach := preload("res://data/hallowmere_layout.gd")

var _runner: Node = null
var _saved_mode: String = ""
var _secs := 9.0
var tracker: Node = null


func before_each() -> void:
	fresh_state()
	_runner = get_tree().current_scene
	_saved_mode = Game.mode
	_secs = Story.celebration_seconds
	var ph := Node.new()
	ph.name = "Ch2Placeholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	tracker = Story.new_tracker()
	add_child(tracker)


func after_each() -> void:
	Story.celebration_seconds = _secs
	if tracker != null and is_instance_valid(tracker):
		tracker.queue_free()
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game.mode = _saved_mode
	Game._bosses.clear()
	var cs := get_tree().current_scene
	if cs != null and cs != _runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "Ch2Placeholder" or n.name == "HallowmereReach" or n.name == "Surface":
			n.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


func _until(cond: Callable, max_frames: int = 1500) -> bool:
	for i in max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _end_of_chapter_state() -> void:
	GameState.active = true
	for f in ["ward_restored", "chapter_one_complete", "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons",
			"ch2_read_festival_map", "ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp",
			"ch2_garden_lamp_lit", "ch2_quarry_lamp_lit", "ch2_manor_lamp_lit", "ch2_read_preparations", "ch2_lamps_linked",
			"ch2_service_gate_open", "ch2_true_signal", "ch2_refuge_reached", "ch2_refuge_shortcut", "ch2_refuge_record",
			"ch2_line_water", "ch2_line_bell", "ch2_line_light", "ch2_crossing_cleared", "ch2_false_home_revealed",
			"ch2_choir_defeated"]:
		GameState.set_flag(f, true)
	GameState.quests.from_dict({"index": 15})
	GameState.give_item("lantern", 1)


func test_back_in_the_reach_then_celebrate_at_the_commons() -> void:
	_end_of_chapter_state()
	Story.celebration_seconds = 0.3
	Game.load_area("hallowmere_reach", "refuge_exit", false)
	assert_true(await _until(func() -> bool: return Game.mode == "playing" and Game.area_id == "hallowmere_reach" and not Game._transitioning), "arrived in the Reach")
	await wait_seconds(0.8)
	assert_true(Story.flag(Story.RETURNED_FLAG), "arriving after the Choir = ch2_returned_to_reach")
	assert_true(GameState.lore.has(Story.LORE_ROUTES))
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_routes_restored"), "step 18 complete")
	var dressing: Node3D = Game.area.get_node_or_null(ReachDressing.NODE_NAME)
	assert_not_null(dressing, "the festival dressing is in the region")
	if dressing == null:
		return
	var pole: Node3D = dressing.get_node_or_null(ReachDressing.POLE_NAME)
	assert_not_null(pole, "the Lanternwake lantern stands at the Commons")
	if pole == null:
		return
	# The road lanterns float clear of everything solid in the real region (arches, stalls, trunks, rocks, walls).
	var reach_area: Node3D = Game.area as Node3D
	var route := ReachDressing.route_points(ReachDressing.stage(), func(x: float, z: float) -> float: return float(reach_area.height_at(x, z)))
	assert_true(route.size() >= 20, "festival lanterns along the real roads (%d)" % route.size())
	var rspace: PhysicsDirectSpaceState3D = reach_area.get_world_3d().direct_space_state
	var rsph := SphereShape3D.new()
	rsph.radius = 0.35
	var blocked: Array = []
	for p in route:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = rsph
		q.transform = Transform3D(Basis.IDENTITY, (p as Dictionary)["pos"])
		q.collision_mask = 1 | 32
		if not rspace.intersect_shape(q, 1).is_empty():
			blocked.append((p as Dictionary)["pos"])
	assert_eq(blocked, [], "no road lantern inside anything solid")
	assert_true(await _until(func() -> bool: return bool(pole.get("placed")), 30), "placed")
	var region_pole := ReachDressing.find_region_pole(Game.area)
	assert_eq(bool(pole.get("attach")), region_pole != null, "attached to the region's own Commons pole when it has one")
	print("story_ch2 flow: region pole %s, lantern at %s, attach %s" % [region_pole != null, pole.global_position, pole.get("attach")])
	# Nothing of this module blocks the spawns she arrives at.
	for sid in ["commons_arch", "reach_respawn", "refuge_exit", "waygate_arrival"]:
		if (Game.area.get("spawns") as Dictionary).has(sid):
			var xf: Transform3D = Game.area.get_spawn(sid)
			assert_true(Vector2(xf.origin.x - pole.global_position.x, xf.origin.z - pole.global_position.z).length() > 3.0, "lantern clear of " + sid)
	var zone: String = Game.area.get_zone_at(pole.global_position)
	assert_eq(zone, "hr_commons", "at Lanternwake Commons")
	assert_true(Game.area.is_safe_zone(pole.global_position), "in a safe place")
	assert_false(bool(pole.get_interaction(Game.player)["enabled"]), "home first")
	# She goes home and speaks to the Ward Stone (covered elsewhere); back at the Commons, she celebrates.
	GameState.set_flag(Story.HOMECOMING_FLAG)
	assert_true(bool(pole.get_interaction(Game.player)["enabled"]))
	var state := {"done": false}
	pole.set("forced_choice", "celebrate")
	var runner := func() -> void:
		await pole.interact(Game.player)
		state["done"] = true
	runner.call()
	var ui: Node = Game.ui
	var overlay: Control = ui.get("overlay_layer") if ui != null else null
	var screen: Control = null
	var cring: Array = []
	var cshot: Dictionary = {}
	var seen_cel := false
	for i in 400:
		await get_tree().process_frame
		var cel := Game.area.get_node_or_null("StoryCh2Celebration") as Node3D
		if cel != null and not seen_cel:
			seen_cel = true
			cring = (cel.get("ring_points") as Array).duplicate()
			cshot = (cel.get("shot") as Dictionary).duplicate()
		if overlay != null:
			for c in overlay.get_children():
				if c.get("variant") != null:
					screen = c
		if screen != null or bool(state["done"]):
			break
	assert_true(Story.flag("chapter_two_complete"), "committed")
	# The Commons celebration: festival ring around the lantern, clear of stalls / posts / the outpost, and a
	# camera shot that is clear in the real region (or the player's own camera).
	assert_true(seen_cel, "the celebration played at the Commons")
	assert_true(cring.size() >= 6, "festival ring at the Commons (%d)" % cring.size())
	var cblocked: Array = []
	for p in cring:
		var pos: Vector3 = (p as Dictionary)["pos"]
		assert_true(Vector2(pos.x, pos.z).distance_to(Reach.OUTPOST_BUILD_AREA["center"]) > float(Reach.OUTPOST_BUILD_AREA["radius"]), "never over the outpost %s" % pos)
		var q2 := PhysicsShapeQueryParameters3D.new()
		q2.shape = rsph
		q2.transform = Transform3D(Basis.IDENTITY, pos)
		q2.collision_mask = 1 | 32
		if not rspace.intersect_shape(q2, 1).is_empty():
			cblocked.append(pos)
	assert_eq(cblocked, [], "no festival lantern inside a stall, post or tree")
	if not cshot.is_empty():
		var cg: float = float(reach_area.height_at((cshot["pos"] as Vector3).x, (cshot["pos"] as Vector3).z))
		assert_true(Celebration.shot_is_clear(rspace, cshot["pos"], cshot["look"], cg), "the Commons shot is clear in the real region")
	print("story_ch2 commons: ring %d, shot %s" % [cring.size(), "validated" if not cshot.is_empty() else "player camera"])
	var disk: Dictionary = SaveSystem._read_and_validate(SaveSystem._path())
	assert_true(bool(((disk.get("state", {}) as Dictionary).get("flags", {}) as Dictionary).get("chapter_two_complete", false)), "saved before the ending")
	if overlay != null:
		assert_not_null(screen, "the Chapter Two ending screen is on the UI root's overlay layer")
	else:
		fail("the gameplay UI root did not load (fallback UI in use): cannot check the ending screen")
	if screen != null:
		assert_eq(String(screen.get("variant")), "chapter_two")
		assert_eq(Game.mode, "cutscene", "a cutscene while the ending plays")
		screen.call("_show_final")
		screen.call("_finish")
	assert_true(await _until(func() -> bool: return bool(state["done"]), 600), "Continue -> back to play")
	assert_eq(Game.mode, "playing", "free play in the same save")
	assert_eq(Story.last_venue, "commons")
	dressing = Game.area.get_node_or_null(ReachDressing.NODE_NAME)
	var pole2: Node3D = dressing.get_node_or_null(ReachDressing.POLE_NAME) if dressing != null else null
	assert_true(pole2 != null and pole2.is_in_group("light_source"), "the lantern is a lasting safe light now")
	assert_eq(String(pole2.get_interaction(Game.player)["text"]) if pole2 != null else "", "Ring the festival chimes")
	assert_null(Game.area.get_node_or_null("StoryCh2Celebration"), "the celebration cleaned up")
	var cam: Camera3D = Game.player.get_camera() if Game.player != null and Game.player.has_method("get_camera") else null
	if cam != null:
		assert_eq(Game.area.get_viewport().get_camera_3d(), cam, "the player's camera is back")
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_finished())
	assert_eq(String(GameState.current_objective()["source"]), "legacy", "the tracker hands back: free play")


func _overlay_screen() -> Control:
	var ui: Node = Game.ui
	var overlay: Control = ui.get("overlay_layer") if ui != null else null
	if overlay == null:
		return null
	for c in overlay.get_children():
		if c.get("variant") != null:
			return c as Control
	return null


func test_homecoming_and_celebration_at_the_real_haven() -> void:
	_end_of_chapter_state()
	GameState.set_flag(Story.RETURNED_FLAG, true)
	Story.celebration_seconds = 0.6
	Game.load_area("surface", "haven_start", false)
	assert_true(await _until(func() -> bool: return Game.mode == "playing" and Game.area_id == "surface" and not Game._transitioning), "home")
	await wait_seconds(0.5)
	var ws: Node3D = null
	for n in get_tree().get_nodes_in_group("ward_stone"):
		if n is Node3D and Game.area.is_ancestor_of(n):
			ws = n
	assert_not_null(ws, "the real Ward Stone")
	if ws == null:
		return
	assert_null(Game.area.get_node_or_null(HavenDressing.NODE_NAME), "no keepsake before the ending")
	# Step 19: the first reading after the Choir is the homecoming (no menu, only the MP §17 line).
	var said: Array = []
	var on_say := func(_who: String, text: String, _secs: float) -> void: said.append(text)
	Events.say.connect(on_say)
	await ws.interact(Game.player)
	Events.say.disconnect(on_say)
	assert_true(Story.flag(Story.HOMECOMING_FLAG), "ch2_homecoming at the real stone")
	assert_eq(said, ["Light kept. Roads found. Welcome home, Krystal."], "only the MP §17 return line")
	GameState.chapter2.evaluate()
	assert_eq(String(GameState.current_objective()["id"]), "ch2_feast", "only the Lanternwake is left")
	# Step 20 from the stone's menu.
	ws.set("forced_choice", "celebrate")
	var state := {"done": false}
	var runner := func() -> void:
		await ws.interact(Game.player)
		state["done"] = true
	runner.call()
	var screen: Control = null
	var cel: Node3D = null
	var seen_cel := false
	var ring: Array = []
	var shot: Dictionary = {}
	var cam_ok := false
	for i in 600:
		await get_tree().process_frame
		var c := Game.area.get_node_or_null("StoryCh2Celebration") as Node3D
		if c != null and not seen_cel:
			await get_tree().physics_frame
			seen_cel = true
			cel = c
			ring = (c.get("ring_points") as Array).duplicate()
			shot = (c.get("shot") as Dictionary).duplicate()
			var ccam: Camera3D = c.get("camera")
			var pcam: Camera3D = Game.player.get_camera() if Game.player != null and Game.player.has_method("get_camera") else null
			var cur := Game.area.get_viewport().get_camera_3d()
			cam_ok = (ccam != null and cur == ccam) if not shot.is_empty() else (cur == pcam)
		screen = _overlay_screen()
		if screen != null or bool(state["done"]):
			break
	assert_true(seen_cel, "the celebration played at home")
	assert_true(Story.flag("chapter_two_complete"), "committed")
	assert_eq(Story.last_venue, "haven")
	assert_true(ring.size() >= Celebration.RING_COUNT - 4, "festival ring around the real Haven (%d)" % ring.size())
	var circles := Celebration.build_circles()
	var space: PhysicsDirectSpaceState3D = (Game.area as Node3D).get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	var inside_solid := 0
	for p in ring:
		var pos: Vector3 = (p as Dictionary)["pos"]
		assert_true(Celebration.outside_build(Vector2(pos.x, pos.z), Celebration.OUTSIDE_MARGIN - 0.01, circles), "outside the build area %s" % pos)
		var h: float = float(Game.area.height_at(pos.x, pos.z))
		assert_true(pos.y - h > 2.4, "floating above head height %s" % pos)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sph
		q.transform = Transform3D(Basis.IDENTITY, pos)
		q.collision_mask = 1 | 32
		if not space.intersect_shape(q, 1).is_empty():
			inside_solid += 1
	assert_eq(inside_solid, 0, "no festival lantern sits inside a trunk, rock or building")
	assert_true(cam_ok, "the validated shot (or the player's own camera) is the one in use")
	if not shot.is_empty():
		var g: float = float(Game.area.height_at((shot["pos"] as Vector3).x, (shot["pos"] as Vector3).z))
		assert_true(Celebration.shot_is_clear(space, shot["pos"], shot["look"], g), "the shot is clear in the real world")
	print("story_ch2 haven: ring %d, shot %s" % [ring.size(), "validated" if not shot.is_empty() else "player camera"])
	assert_not_null(screen, "the Chapter Two ending screen is on the UI root's overlay layer")
	if screen != null:
		screen.call("_show_final")
		screen.call("_finish")
	assert_true(await _until(func() -> bool: return bool(state["done"]), 600), "Continue -> back to play")
	assert_eq(Game.mode, "playing", "free play")
	assert_false(bool(ws.get("_busy")), "the stone is free again")
	assert_null(Game.area.get_node_or_null("StoryCh2Celebration"), "the celebration cleaned up")
	var pcam2: Camera3D = Game.player.get_camera() if Game.player != null and Game.player.has_method("get_camera") else null
	if pcam2 != null:
		assert_eq(Game.area.get_viewport().get_camera_3d(), pcam2, "the player's camera is back")
	assert_not_null(Game.area.get_node_or_null(HavenDressing.NODE_NAME), "the keepsake appears at once")
	var ids: Array = (ws.menu_options() as Array).map(func(o: Array) -> String: return String(o[0]))
	assert_false(ids.has("celebrate"), "no second celebration")
	# Reload the Haven: the keepsake is rebuilt from the flag, exactly once.
	Game.load_area("surface", "haven_start", false)
	await get_tree().process_frame
	assert_true(await _until(func() -> bool: return Game.mode == "playing" and Game.area_id == "surface" and not Game._transitioning), "home again")
	await wait_frames(2)
	var keepsakes := 0
	for c2 in Game.area.get_children():
		if String(c2.name).begins_with(HavenDressing.NODE_NAME):
			keepsakes += 1
	assert_eq(keepsakes, 1, "one keepsake after a reload")
