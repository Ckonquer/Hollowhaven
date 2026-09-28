extends "res://tests/test_case.gd"
## New Game with a look from the creation screen (autoload/game.gd new_game(look), R01): a confirmed look
## counts for "A Look of Your Own" (flag c1x_look_chosen) and the one-time wardrobe notice is not needed
## (wardrobe.notice_shown) - set by Game itself right after the look is applied, so it holds even when the
## creation screen's own one-shot hook (CreationScreen.arm_new_journey_marks) never ran. New Game without a
## look sets neither. Both reach the first (quiet) save. Runs the REAL new_game() -> load_area("surface").
## The runner scene is protected like test_flow_ch2_roundtrip: current_scene is swapped for a placeholder.

const LOOK := {"hair": "bob", "hair_color": "honey"}

var _runner: Node = null
var _saved_mode: String = ""


func before_each() -> void:
	fresh_state()
	GameState.active = false
	_runner = get_tree().current_scene
	_saved_mode = Game.mode
	Game._transitioning = false
	Game._travel_seq += 1          # a trip left over from an earlier suite never saves into this one
	SaveSystem.delete_test_saves()
	var ph := Node.new()
	ph.name = "Ch2Placeholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph


func after_each() -> void:
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
		if n.name == "Ch2Placeholder" or n.name == "Surface":
			n.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	GameState.active = false
	SaveSystem.delete_test_saves()
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


func _until(cond: Callable, max_frames: int = 1500) -> bool:
	for i in max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


## Runs Game.new_game(look) to the end (the Haven loaded and the first quiet save written).
func _new_game(look: Dictionary) -> bool:
	var state := {"done": false}
	var run := func() -> void:
		await Game.new_game(look)
		state["done"] = true
	run.call()
	var ok: bool = await _until(func() -> bool: return bool(state["done"]))
	await wait_frames(2)
	return ok and Game.area_id == "surface"


func _saved_state() -> Dictionary:
	var saved: Dictionary = SaveSystem._read_and_validate(SaveSystem._path())
	var st: Variant = saved.get("state", {})
	return st if st is Dictionary else {}


func test_new_game_with_a_look_marks_it_chosen() -> void:
	assert_true(await _new_game(LOOK), "the Haven loaded")
	assert_true(bool(GameState.get_flag("c1x_look_chosen")), "A Look of Your Own: the look was chosen at creation")
	assert_true(bool(GameState.wardrobe.get("notice_shown", false)), "no wardrobe notice for a look just styled")
	assert_eq(String(GameState.appearance.get("hair", "")), "bob", "the look itself was applied")
	var st := _saved_state()
	assert_false(st.is_empty(), "the first quiet save exists")
	assert_true(bool((st.get("flags", {}) as Dictionary).get("c1x_look_chosen", false)), "the flag is in the first save")
	assert_true(bool((st.get("wardrobe", {}) as Dictionary).get("notice_shown", false)), "notice_shown is in the first save")


func test_new_game_without_a_look_marks_nothing() -> void:
	GameState.set_flag("c1x_look_chosen", true)     # from an earlier journey: new_game() resets it
	GameState.wardrobe["notice_shown"] = true
	assert_true(await _new_game({}), "the Haven loaded")
	assert_false(bool(GameState.get_flag("c1x_look_chosen")), "no look chosen: the goal stays open")
	assert_false(bool(GameState.wardrobe.get("notice_shown", true)), "the wardrobe notice is still to come")
	var st := _saved_state()
	assert_false(st.is_empty(), "the first quiet save exists")
	assert_false(bool((st.get("flags", {}) as Dictionary).get("c1x_look_chosen", false)), "not in the first save either")
