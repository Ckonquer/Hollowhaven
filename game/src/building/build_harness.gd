extends Node3D
## Debug-only QA harness (never used in play). Runs through the preview entry point, then loads a
## real area through Game and drives BuildMode like a player would (debug cursor instead of the
## mouse): builds a cottage, plants crops, shows valid/invalid ghosts, dismantles, and saves PNGs.
##   tools/godot.sh --path game --windowed --resolution 1600x900 -- \
##     --preview=res://src/building/build_harness.gd --preview-wait=120 --shot-dir=<abs dir> \
##     --preview-args='{"area":"surface","origin":[-8,0,2]}'
## Writes <shot-dir>/harness.json with every placement result.

const Preview := preload("res://src/building/preview_all.gd")
const Placement := preload("res://src/building/placement.gd")
const Farming := preload("res://src/farming/farming.gd")

var area_name := "surface"
var origin := Vector3(-8, 0, 2)
var hour := 10.0
var _log: Array = []
var _cam: Camera3D
var _dir := ""


func setup(p: Dictionary) -> void:
	area_name = String(p.get("area", area_name))
	var o: Variant = p.get("origin")
	if o is Array and o.size() == 3:
		origin = Vector3(float(o[0]), float(o[1]), float(o[2]))
	hour = float(p.get("hour", hour))


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		queue_free()
		return
	_run.call_deferred()


func _run() -> void:
	# Let the preview stage settle, then survive the scene change by moving under the root window.
	await get_tree().process_frame
	await get_tree().process_frame
	reparent(get_tree().root)
	_dir = Debug.arg("shot-dir", "user://harness")
	DirAccess.make_dir_recursive_absolute(_dir)
	# Sleeping in the bed saves the game: never let the harness touch the player's real save slot.
	if not Debug.has_arg("save-dir"):
		SaveSystem.set_save_dir("user://test_saves/harness_building")
	GameState.new_game()
	Settings.set_value("comfort_confirmed", true)
	GameState.total_minutes = hour * 60.0
	var give := {"workbench": 1, "storage_chest": 2, "bed": 1, "crop_plot": 2, "wood_floor": 4, "wood_wall": 6,
		"wood_window": 5, "wood_doorway": 1, "wood_roof": 4, "fence": 6, "lantern_post": 2, "flower_pot": 3,
		"rug": 1, "table": 1, "stool": 2, "pebble_cairn": 1, "echo_chime": 1, "heartbloom_lamp": 1,
		"haven_banner": 1, "sweetroot_seeds": 5}
	for id in give:
		GameState.give_item(id, int(give[id]))
	await Game.load_area(area_name, "haven_start", false)
	await get_tree().create_timer(0.5).timeout
	if area_name != "surface":
		var bs: Script = load("res://src/building/building_system.gd")
		bs.attach(Game.area)
	_note("after_load", {"mode": Game.mode, "ui_open": Game.is_ui_open(), "paused": get_tree().paused,
		"placeables": GameState.inventory.totals().size()})
	var bm: Node = get_tree().get_first_node_in_group("build_mode")
	if bm == null:
		_note("no build mode node", {})
		_finish()
		return
	_cam = Camera3D.new()
	_cam.fov = 55.0
	Game.area.add_child(_cam)
	# 1) Build the cottage piece by piece through BuildMode.
	for e in Preview.house_layout():
		var sid: String = e[0]
		var local: Vector3 = e[1]
		await _place(bm, sid, origin + Vector3(local.x, 0, local.z), int(e[2]))
	# Plant the two plots at different times so they show different stages.
	var plots: Array = []
	for uid in GameState.structures:
		if GameState.structures[uid]["id"] == "crop_plot":
			plots.append(uid)
	for i in plots.size():
		Farming.plant(String(plots[i]), "sweetroot_seeds")
		if i == 0:
			Farming.tend(String(plots[i]), 400.0)
		else:
			Farming.tend(String(plots[i]), 150.0)
	Events.time_of_day_changed.emit(GameState.day(), GameState.time_of_day())
	bm.end()
	bm.debug_cursor = null
	await _frames(10)
	_note("perf_after_build", {"fps": Engine.get_frames_per_second(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"structures": GameState.structures.size()})
	# 2) Overview shots
	await _shot("house_front", origin + Vector3(1.5, 4.2, 11.5), origin + Vector3(1, 1.2, 1))
	await _shot("house_side", origin + Vector3(11.5, 5.5, 6.5), origin + Vector3(1.5, 1.0, 1))
	await _shot("house_back", origin + Vector3(-7, 6.5, -8), origin + Vector3(0.5, 1.2, 0.5))
	await _shot("interior", origin + Vector3(1.0, 2.2, 1.2), origin + Vector3(-1.2, 0.3, -1.2))
	# 3) Ghosts: valid (green) next to the house, invalid (red) on the bed.
	bm.begin("storage_chest")
	bm.rot_deg = 0
	bm.debug_cursor = origin + Vector3(-3.4, 0, 3.6)
	await _frames(8)
	_note("ghost_valid", bm.get_state())
	await _shot("ghost_valid", origin + Vector3(-1.5, 3.2, 8.5), origin + Vector3(-3.0, 0.4, 3.0))
	bm.begin("wood_wall")
	bm.debug_cursor = origin + Vector3(1.0, 0, 2.05)
	await _frames(8)
	_note("ghost_wall_on_doorway", bm.get_state())
	await _shot("ghost_invalid", origin + Vector3(3.5, 3.6, 8.5), origin + Vector3(1.0, 1.0, 2.0))
	bm.begin("fence")
	bm.debug_cursor = origin + Vector3(20.0, 0, 20.0)
	await _frames(6)
	_note("ghost_outside", bm.get_state())
	# 4) Dismantle a flower pot through the cursor and verify the refund.
	var before := GameState.count_item("flower_pot")
	bm.debug_cursor = origin + Vector3(-1.5, 0, 2.5)
	await _frames(4)
	var ok: bool = bm.try_dismantle()
	await _frames(20)
	_note("dismantle_flower_pot", {"ok": ok, "before": before, "after": GameState.count_item("flower_pot")})
	bm.end()
	# 5) Real camera ray (no debug cursor): ghost in front of the player.
	bm.debug_cursor = null
	var pcam: Camera3D = null
	if Game.player != null and Game.player.has_method("get_camera"):
		pcam = Game.player.get_camera()
	if pcam == null:
		pcam = Game.player.get("cam") if Game.player != null else null
	if pcam != null:
		pcam.make_current()
		bm.begin("lantern_post")
		await _frames(10)
		_note("ray_ghost", bm.get_state())
		await _save("ray_ghost")
		bm.end()
	# 6) The real interaction probe finds our interactables (player placed in front, facing them).
	for probe in [["storage_chest", Vector3(-6.5, 0.12, 1.65), 0.0], ["bed", Vector3(-8.45, 0.12, 1.0), 90.0],
			["workbench", Vector3(-4.0, 0.0, 6.7), 0.0], ["crop_plot", Vector3(-5.7, 0.0, 1.0), -90.0]]:
		await _probe(String(probe[0]), probe[1], float(probe[2]))
	# 6b) Walk tests with real input: through the doorway onto the floor, and into a wall.
	await _walk("walk_doorway", origin + Vector3(1.0, 0, 5.0), 2.4)
	await _walk("walk_wall", origin + Vector3(-1.0, 0, 5.0), 2.0)
	# 7) The inventory "Place" button: begin() while a panel is open starts once it closes.
	Game.open_panel("inventory")
	await _frames(3)
	bm.begin("fence")
	var during: bool = bm.is_active()
	Game.close_panel("inventory")
	await get_tree().create_timer(0.6).timeout
	_note("pending_begin", {"active_while_panel_open": during, "active_after_close": bm.is_active(), "ui_open": Game.is_ui_open()})
	bm.end()
	await _frames(3)
	# 8) Sleep in the bed through its interaction (fade, clock skip, respawn, save to the test folder).
	var bed: Node = null
	for n in get_tree().get_nodes_in_group("structure"):
		if n.get("structure_id") == "bed":
			bed = n
	if bed != null:
		GameState.total_minutes = floorf(GameState.total_minutes / 1440.0) * 1440.0 + 22.0 * 60.0
		GameState.player["hp"] = 40.0
		bed.interact(Game.player)
		await get_tree().create_timer(4.0).timeout
		_note("slept", {"hour": GameState.hour(), "day": GameState.day(), "hp": GameState.player.get("hp"),
			"respawn": GameState.player.get("respawn_spawn"), "bed_spawn": Game.area.spawns.has("bed"),
			"save_dir": SaveSystem.save_dir, "saved": SaveSystem.has_save()})
	# 9) Evening mood with warm lanterns.
	GameState.total_minutes = GameState.day() * 1440.0 - 1440.0 + 20.5 * 60.0
	Events.time_of_day_changed.emit(GameState.day(), GameState.time_of_day())
	await _frames(6)
	await _shot("house_evening", origin + Vector3(1.5, 4.2, 11.5), origin + Vector3(1, 1.2, 1))
	# 10) Steady-state cost of the structures: same view with the Structures node shown vs hidden.
	var root: Node3D = Game.area.get_node_or_null("Structures")
	if root != null:
		var shown := await _perf_sample()
		root.visible = false
		var hidden := await _perf_sample()
		root.visible = true
		_note("perf_structures", {"shown": shown, "hidden": hidden})
	_finish()


func _perf_sample() -> Dictionary:
	await get_tree().create_timer(2.5).timeout
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 1500000:
		await get_tree().process_frame
		frames += 1
	var secs := float(Time.get_ticks_usec() - t0) / 1000000.0
	return {"fps": snappedf(float(frames) / secs, 0.1),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}


func _probe(sid: String, pos: Vector3, yaw_deg: float) -> void:
	var p: Node3D = Game.player
	if p == null:
		return
	var y := pos.y
	if Game.area.has_method("height_at"):
		y += float(Game.area.height_at(pos.x, pos.z))
	p.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(pos.x, y + 0.05, pos.z)))
	await get_tree().create_timer(0.45).timeout
	var target: Node = p.get_focus_target() if p.has_method("get_focus_target") else null
	var prompt: Dictionary = p.get_prompt() if p.has_method("get_prompt") else {}
	_note("probe " + sid, {"focus": String(target.get("structure_id")) if target != null else "", "prompt": prompt})
	if sid == "storage_chest":
		_cam.global_position = p.global_position + Vector3(-1.0, 1.9, 1.3)
		_cam.look_at(p.global_position + Vector3(0.35, 0.5, -1.0), Vector3.UP)
		_cam.make_current()
		await _frames(10)
		await _save("probe_chest")


func _walk(what: String, start: Vector3, seconds: float) -> void:
	var p: Node3D = Game.player
	if p == null:
		return
	var y := 0.0
	if Game.area.has_method("height_at"):
		y = float(Game.area.height_at(start.x, start.z))
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(start.x, y + 0.05, start.z)))
	await get_tree().create_timer(0.3).timeout
	Input.action_press("move_forward")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.3).timeout
	var pos := p.global_position
	var ground := float(Game.area.height_at(pos.x, pos.z)) if Game.area.has_method("height_at") else 0.0
	_note(what, {"start": [start.x, start.z], "end": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"above_ground": snappedf(pos.y - ground, 0.01)})


func _place(bm: Node, sid: String, pos: Vector3, rot: int) -> void:
	var item: String = String(ItemDB.structure(sid).get("item", sid))
	bm.begin(item)
	bm.rot_deg = rot
	bm.debug_cursor = pos
	bm._update(0.016)
	var st: Dictionary = bm.get_state()
	var uid: String = bm.try_place()
	_note("place " + sid, {"pos": [pos.x, pos.y, pos.z], "rot": rot, "uid": uid, "valid": st["valid"], "reason": st["reason"]})
	await _frames(1)


func _note(what: String, data: Dictionary) -> void:
	var d := data.duplicate()
	d.erase("placeables")
	_log.append({"what": what, "data": d})
	print("Harness: ", what, " ", JSON.stringify(d))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	var d := at - from
	if d.length() > 0.01 and absf(d.normalized().dot(Vector3.UP)) < 0.999:
		_cam.look_at(at, Vector3.UP)
	_cam.make_current()
	await _frames(12)
	await _save(name)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dir.path_join(name + ".png"))
	print("Harness: saved ", name)


func _finish() -> void:
	var f := FileAccess.open(_dir.path_join("harness.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_log, "\t"))
	get_tree().quit()
