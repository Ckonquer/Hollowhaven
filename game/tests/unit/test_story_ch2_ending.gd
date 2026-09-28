extends "res://tests/unit/test_core_base.gd"
## Story module C9: the Chapter Two ending ("The Lanternwake", MP §11 step 20, §17, §2.4).
##   * the ending grants exactly once: called twice, and again after a save / reload
##   * it never calls Game.complete_chapter() and never touches a Chapter One flag, quest or item
##   * a crash during the presentation resumes in a completed world: the save on disk already holds the
##     flags, the ledger entry, the items and the wardrobe unlocks when the presentation starts
##   * overflow is safe (a full backpack drops persistent pickups)
##   * the in-game presentation order: commit + save -> companions / chapter2_completed -> the celebration
##     (lights outside the build area, validated camera) -> the ending UI -> the camera back, the lasting
##     dressing, free play; and the ending screen fallback on the UI root's overlay layer
##   * "Celebrate" from the Ward Stone (home) and from the Commons festival lantern

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")
const Pole := preload("res://src/world/story_ch2/lanternwake_pole.gd")
const Celebration := preload("res://src/world/story_ch2/celebration.gd")
## MP 11 step 20 + MP 17 "a few supplies": the final step's give = data/sources.gd rw_ch2_feast = the ending's list.
const FEAST_TOTALS := {"candy": 6, "pumpkin": 4, "lantern_wax": 4, "sugarcap": 3, "moonpetal": 3}


class StubArea extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0


class StubUi extends CanvasLayer:
	var endings: Array = []
	var probe: Callable

	func show_chapter_two_ending() -> void:
		endings.append(probe.call() if probe.is_valid() else {})
		await get_tree().process_frame


class OverlayUi extends CanvasLayer:
	var overlay_layer: Control
	var closed := 0

	func _ready() -> void:
		overlay_layer = Control.new()
		add_child(overlay_layer)

	func close_all() -> void:
		closed += 1


var tracker: Node = null
var _saved := {}


func setup() -> void:
	fresh_state()
	GameState.active = true
	# A realistic save at the end of Chapter Two: every story flag up to the homecoming.
	for f in ["ward_restored", "chapter_one_complete", "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons",
			"ch2_read_festival_map", "ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp",
			"ch2_garden_lamp_lit", "ch2_quarry_lamp_lit", "ch2_manor_lamp_lit", "ch2_read_preparations", "ch2_lamps_linked",
			"ch2_service_gate_open", "ch2_true_signal", "ch2_refuge_reached", "ch2_refuge_shortcut", "ch2_refuge_record",
			"ch2_line_water", "ch2_line_bell", "ch2_line_light", "ch2_crossing_cleared", "ch2_false_home_revealed",
			"ch2_choir_defeated", "ch2_returned_to_reach", "ch2_homecoming"]:
		GameState.set_flag(f, true)
	GameState.chapter2.evaluate()
	assert_eq(String(GameState.current_objective()["id"]), "ch2_feast", "only the Lanternwake is left")
	_saved = {"mode": Game.mode, "ui": Game.ui, "area": Game.area, "area_id": Game.area_id, "player": Game.player,
		"companions": Game.companion_nodes, "secs": Story.celebration_seconds}
	Game.mode = "boot"
	Game.companion_nodes = {}
	Game.ui = null          # isolated from whatever an earlier suite left loaded
	Game.area = null
	Game.area_id = ""
	# Game's session tracker steps aside (leaving the tree disconnects it): these tests drive exactly one tracker.
	var session: Node = Game.get_node_or_null("StoryCh2Tracker")
	if session != null:
		Game.remove_child(session)
		session.queue_free()
	tracker = Story.new_tracker()
	add_child(tracker)


func teardown() -> void:
	Game.mode = String(_saved["mode"])
	Game.ui = _saved["ui"]
	Game.area = _saved["area"]
	Game.area_id = String(_saved["area_id"])
	Game.player = _saved["player"]
	Game.companion_nodes = _saved["companions"]
	Story.celebration_seconds = float(_saved["secs"])
	if tracker != null and is_instance_valid(tracker):
		tracker.queue_free()
	await wait_frames(2)
	if Game.has_method("wire_session_systems"):
		Game.call("wire_session_systems")     # the session tracker is back for the next suite


func _held(id: String) -> int:
	var n := GameState.count_item(id)
	for d in GameState.dropped:
		if String(d["item"]) == id:
			n += int(d["count"])
	return n


## The state section of the save file on disk right now.
func _disk_state() -> Dictionary:
	var path := SaveSystem.save_dir.path_join("slot1.json")
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d as Dictionary).get("state", {}) if d is Dictionary else {}


static func _disk_count(st: Dictionary, id: String) -> int:
	var n := 0
	var inv: Variant = st.get("inventory", [])
	if inv is Array:
		for s in inv:
			if s is Dictionary and String((s as Dictionary).get("id", "")) == id:
				n += int((s as Dictionary).get("count", 0))
	for d in st.get("dropped", []):
		if String((d as Dictionary).get("item", "")) == id:
			n += int((d as Dictionary).get("count", 0))
	return n


# --- Rewards once --------------------------------------------------------------------------------------------

func test_ending_grants_once_even_across_reloads() -> void:
	var ended := record(Events.chapter2_completed, 0)
	var rewards: Dictionary = Game.chapter_two_rewards()
	assert_deep_eq(json_norm(rewards), json_norm(FEAST_TOTALS), "the ending pays exactly the Lanternwake list")
	assert_true(await Game.complete_chapter_two(rewards), "completes")
	assert_eq(ended.size(), 1, "chapter2_completed once")
	var counts := {}
	for id in rewards:
		counts[id] = _held(String(id))
		assert_eq(int(counts[id]), int(rewards[id]), "granted " + String(id))
	assert_true(Story.flag("chapter_two_complete") and Story.flag("ch2_feast"))
	assert_true(GameState.has_reward("rw_ch2_feast"))
	assert_false(await Game.complete_chapter_two(rewards), "a second call does nothing")
	assert_false(await Story.celebrate("haven"), "and neither does celebrating again")
	for id in rewards:
		assert_eq(_held(String(id)), int(counts[id]), "not twice: " + String(id))
	GameState.reset()
	assert_true(SaveSystem.load_game(), "reloaded")
	GameState.active = true
	assert_false(await Game.complete_chapter_two(rewards), "after a reload: nothing")
	GameState.chapter2.evaluate()     # the chapter log's own path to rw_ch2_feast is the same ledger entry
	for id in rewards:
		assert_eq(_held(String(id)), int(counts[id]), "still once after the reload: " + String(id))
	assert_eq((GameState.wardrobe["owned"] as Array).count(Story.FEAST_PATTERN), 1, "the Lanternwake outfit, once")
	assert_eq((GameState.wardrobe["palettes"] as Array).count("midnight"), 1)
	assert_eq((GameState.wardrobe["palettes"] as Array).count("cream"), 1)
	assert_eq(ended.size(), 1, "the ending never shows again")
	assert_true(GameState.chapter2.is_finished(), "the chapter log is finished")
	assert_eq(String(GameState.current_objective()["source"]), "legacy", "free play: the tracker hands back")


## The chapter log's own path to rw_ch2_feast (chapter_two_complete already set, e.g. a save repaired by hand)
## pays exactly what the ending pays: the step data lists the same items (no path pays less, none pays twice).
func test_chapter_log_path_pays_the_same_lanternwake() -> void:
	GameState.set_flag("chapter_two_complete")
	GameState.chapter2.evaluate()
	assert_true(GameState.has_reward("rw_ch2_feast"), "the chapter log paid the final step")
	for id in FEAST_TOTALS:
		assert_eq(_held(String(id)), int(FEAST_TOTALS[id]), "chapter log pays " + String(id))
	assert_false(await Game.complete_chapter_two(Game.chapter_two_rewards()), "the ending then pays nothing more")
	for id2 in FEAST_TOTALS:
		assert_eq(_held(String(id2)), int(FEAST_TOTALS[id2]), "not twice: " + String(id2))


func test_ending_never_replays_chapter_one() -> void:
	GameState.give_item("heartseed", 1)
	var ch1 := record(Events.chapter_completed, 0)
	var before := {}
	for f in GameState.flags:
		before[f] = GameState.flags[f]
	var quest_index: int = GameState.quests.index
	var quest_done: Array = (GameState.quests.to_dict().get("completed", []) as Array).duplicate()
	assert_true(await Story.celebrate("haven"))
	assert_eq(ch1.size(), 0, "Events.chapter_completed (Chapter One) never emitted")
	assert_eq(GameState.count_item("heartseed"), 1, "Game.complete_chapter() never ran (it takes the seed)")
	assert_eq(GameState.quests.index, quest_index, "legacy quest index untouched")
	assert_eq(GameState.quests.to_dict().get("completed", []), quest_done, "legacy completed steps untouched")
	for f in before:
		assert_eq(GameState.flags[f], before[f], "flag %s unchanged" % f)
	for f in GameState.flags:
		if not before.has(f):
			var fs := String(f)
			assert_true(fs.begins_with("ch2_") or fs == "chapter_two_complete" or fs.begins_with("hint_"),
				"the ending only adds Chapter Two flags (%s)" % fs)
	assert_true(Story.flag("ward_restored"), "Chapter One stays complete")


# --- Crash safety ---------------------------------------------------------------------------------------------

func test_crash_during_the_ending_resumes_in_a_completed_world() -> void:
	var at_presentation: Array = []
	listen(Events.chapter2_completed, func() -> void: at_presentation.append(_disk_state()))
	var rewards: Dictionary = Game.chapter_two_rewards()
	assert_true(await Story.celebrate("haven"))
	assert_eq(at_presentation.size(), 1)
	var st: Dictionary = at_presentation[0]
	assert_false(st.is_empty(), "a save existed when the presentation began")
	assert_true(bool((st.get("flags", {}) as Dictionary).get("chapter_two_complete", false)), "flag on disk")
	assert_true(bool((st.get("flags", {}) as Dictionary).get("ch2_feast", false)), "unlock flag on disk")
	assert_true((st.get("ledger", {}) as Dictionary).has("rw_ch2_feast"), "ledger entry on disk")
	for id in rewards:
		assert_eq(_disk_count(st, String(id)), int(rewards[id]), "items on disk: " + String(id))
	var wd: Dictionary = st.get("wardrobe", {})
	assert_true((wd.get("owned", []) as Array).has(Story.FEAST_PATTERN), "the outfit is owned on disk")
	assert_true((wd.get("palettes", []) as Array).has("midnight") and (wd.get("palettes", []) as Array).has("cream"), "finishes on disk")
	# "Crash": throw the running state away and continue from that file.
	GameState.reset()
	assert_true(SaveSystem.load_game())
	GameState.active = true
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_finished(), "resumes in a completed chapter")
	assert_false(Story.can_celebrate(), "no second celebration offered")
	var ws: Node3D = WardStone.new()
	add_child(ws)
	var ids: Array = (ws.menu_options() as Array).map(func(o: Array) -> String: return String(o[0]))
	assert_false(ids.has("celebrate"))
	ws.queue_free()
	for id in rewards:
		assert_eq(_held(String(id)), int(rewards[id]), "nothing lost or repeated: " + String(id))
	Events.game_loaded.emit()
	assert_true(GameState.lore.has(Story.LORE_LANTERNWAKE), "the journal note is repaired from the flag")


func test_overflow_goes_to_persistent_pickups() -> void:
	fill_backpack("stone")
	var rewards: Dictionary = Game.chapter_two_rewards()
	assert_true(await Game.complete_chapter_two(rewards))
	for id in rewards:
		assert_eq(_held(String(id)), int(rewards[id]), "nothing lost: " + String(id))
	assert_true(GameState.dropped.size() >= 1, "dropped as pickups")
	var ok := SaveSystem.save_game(true)
	assert_true(ok)
	GameState.reset()
	assert_true(SaveSystem.load_game())
	for id in rewards:
		assert_eq(_held(String(id)), int(rewards[id]), "pickups survive a reload: " + String(id))


# --- The in-game presentation ---------------------------------------------------------------------------------

func test_in_game_presentation_order_and_cleanup() -> void:
	var area := StubArea.new()
	add_child(area)
	# Stage it far from anything an earlier suite may have left in the world: the Ward Stone is the focus.
	var ws: Node3D = WardStone.new()
	area.add_child(ws)
	ws.global_position = Vector3(4000, 0, 4000)
	var cam := Camera3D.new()
	area.add_child(cam)
	cam.make_current()
	var ui := StubUi.new()
	add_child(ui)
	var order: Array = []
	listen(Events.chapter2_completed, func() -> void: order.append("chapter2_completed"))
	listen(Events.cutscene_changed, func(on: bool) -> void: order.append("cutscene_%s" % on))
	ui.probe = func() -> Dictionary:
		var cel := area.get_node_or_null("StoryCh2Celebration")
		order.append("ending_ui")
		return {"disk": _disk_state(), "celebration": cel != null,
			"lights": (cel.get("ring_points") as Array).size() if cel != null else 0,
			"camera_is_celebration": cel != null and cel.get("camera") != null and area.get_viewport().get_camera_3d() == cel.get("camera")}
	Game.ui = ui
	Game.area = area
	Game.area_id = "surface"
	Game.player = null
	Game.mode = "playing"
	Story.celebration_seconds = 0.2
	assert_true(await Story.celebrate("haven"))
	assert_eq(Story.last_venue, "haven")
	assert_eq(order, ["cutscene_true", "chapter2_completed", "ending_ui", "cutscene_false"], "commit, event, celebration, ending, play")
	assert_eq(ui.endings.size(), 1)
	var probe: Dictionary = ui.endings[0]
	assert_true(bool(((probe["disk"] as Dictionary).get("flags", {}) as Dictionary).get("chapter_two_complete", false)), "saved before the ending UI")
	assert_true(bool(probe["celebration"]), "the celebration plays behind the ending")
	assert_true(int(probe["lights"]) >= 20, "festival lights around the Haven")
	assert_true(bool(probe["camera_is_celebration"]), "an open viewpoint was validated and used")
	await wait_frames(2)
	assert_null(area.get_node_or_null("StoryCh2Celebration"), "the celebration is removed")
	assert_eq(area.get_viewport().get_camera_3d(), cam, "the player's camera is back")
	assert_not_null(area.get_node_or_null("StoryCh2HavenDressing"), "the lasting keepsake appears at once")
	assert_eq(Game.mode, "playing", "free play")
	assert_true(GameState.lore.has(Story.LORE_LANTERNWAKE))
	area.queue_free()
	ui.queue_free()


func _mouse(button: int, pressed: bool = true) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button as MouseButton
	ev.pressed = pressed
	return ev


func _key(pressed: bool, echo: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	ev.echo = echo
	return ev


## Skipping the celebration: a deliberate key press or mouse click after SKIP_AFTER seconds; never the mouse wheel
## (looking around / a stray tick) and never a held key's repeat.
func test_celebration_skip_ignores_the_wheel_and_key_repeats() -> void:
	for b in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		assert_false(Celebration.is_skip_input(_mouse(b)), "wheel button %d never skips" % int(b))
	assert_false(Celebration.is_skip_input(_key(true, true)), "a key echo never skips")
	assert_false(Celebration.is_skip_input(_key(false)), "a key release never skips")
	assert_false(Celebration.is_skip_input(_mouse(MOUSE_BUTTON_LEFT, false)), "a button release never skips")
	assert_false(Celebration.is_skip_input(InputEventMouseMotion.new()), "moving the mouse never skips")
	assert_true(Celebration.is_skip_input(_key(true)), "a key press skips")
	for b2 in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		assert_true(Celebration.is_skip_input(_mouse(b2)), "mouse button %d skips" % int(b2))
	# The running node: nothing skips before SKIP_AFTER; after it the wheel still does not, a click does.
	var area := StubArea.new()
	add_child(area)
	var cel: Node3D = Celebration.new()
	cel.setup({"area": area, "area_id": "", "duration": 60.0})
	area.add_child(cel)
	var state := {"done": false}
	var runner := func() -> void:
		await cel.play()
		state["done"] = true
	runner.call()
	await wait_frames(1)
	cel.set("_t", 0.2)
	cel.call("_input", _mouse(MOUSE_BUTTON_LEFT))
	assert_false(bool(cel.get("skipped")), "too early to skip")
	cel.set("_t", Celebration.SKIP_AFTER + 0.5)
	cel.call("_input", _mouse(MOUSE_BUTTON_WHEEL_DOWN))
	cel.call("_input", _key(true, true))
	assert_false(bool(cel.get("skipped")), "the wheel and a key repeat never skip")
	assert_false(bool(state["done"]), "still playing")
	cel.call("_input", _mouse(MOUSE_BUTTON_LEFT))
	assert_true(bool(cel.get("skipped")), "a click skips")
	await wait_frames(1)
	assert_true(bool(state["done"]), "play() returned")
	cel.call("finish")
	area.queue_free()
	await wait_frames(1)


func test_ending_screen_on_the_ui_root_overlay() -> void:
	var ui := OverlayUi.new()
	add_child(ui)
	Game.ui = ui
	Game.area = null
	Game.player = null
	Game.mode = "playing"
	var state := {"done": false, "ok": false}
	var runner := func() -> void:
		state["ok"] = await Game.complete_chapter_two(Game.chapter_two_rewards())
		state["done"] = true
	runner.call()
	var screen: Control = null
	for i in 30:
		await wait_frames(1)
		if ui.overlay_layer.get_child_count() > 0:
			screen = ui.overlay_layer.get_child(0) as Control
			break
	assert_not_null(screen, "the Chapter Two ending screen was shown")
	if screen == null:
		return
	assert_eq(String(screen.get("variant")), "chapter_two")
	assert_eq(ui.closed, 1, "panels closed first")
	assert_false(bool(state["done"]), "the ending waits for the player")
	screen.call("_show_final")
	screen.call("_finish")
	for i in 40:
		if bool(state["done"]):
			break
		await wait_seconds(0.1)
	assert_true(bool(state["done"]) and bool(state["ok"]), "Continue returns to free play")
	assert_eq(Game.mode, "playing")
	ui.queue_free()


# --- Where to celebrate ------------------------------------------------------------------------------------------

func test_celebrate_from_the_ward_stone() -> void:
	var ws: Node3D = WardStone.new()
	add_child(ws)
	ws.forced_choice = "celebrate"
	await ws.interact(null)
	assert_true(Story.flag("chapter_two_complete"), "the Ward Stone's Celebrate option ends the chapter")
	assert_eq(Story.last_venue, "haven")
	assert_false(bool(ws.get("_busy")), "the stone is free again")
	var ids: Array = (ws.menu_options() as Array).map(func(o: Array) -> String: return String(o[0]))
	assert_false(ids.has("celebrate"), "no second celebration")
	ws.queue_free()


func test_celebrate_from_the_commons_lantern() -> void:
	GameState.flags.erase("ch2_homecoming")
	var pole: Node3D = Pole.new()
	pole.setup({"candidates": [Vector2(9, 54)], "stage": 2})
	add_child(pole)
	var it: Dictionary = pole.get_interaction(null)
	assert_false(bool(it["enabled"]), "not before the homecoming")
	assert_eq(String(it.get("reason", "")), Pole.NOT_YET)
	await pole.interact(null)
	assert_false(Story.flag("chapter_two_complete"))
	GameState.set_flag("ch2_homecoming")
	it = pole.get_interaction(null)
	assert_true(bool(it["enabled"]) and String(it["text"]) == "Celebrate the Lanternwake")
	pole.forced_choice = "cancel"
	await pole.interact(null)
	assert_false(Story.flag("chapter_two_complete"), "'Not yet' changes nothing")
	pole.forced_choice = "celebrate"
	await pole.interact(null)
	assert_true(Story.flag("chapter_two_complete"))
	assert_eq(Story.last_venue, "commons")
	assert_eq(String(pole.get_interaction(null)["text"]), "Ring the festival chimes", "a pleasant interaction afterwards")
	var caps := record(Events.caption, 1)
	await pole.interact(null)
	assert_eq(caps, [[Pole.CHIME_CAPTION]], "visual + caption, never audio only")
	pole.queue_free()
