extends "res://tests/test_case.gd"
## AUDIT (progression & softlocks), now a regression test: the comfort screen shown before the mine.
## On the title screen, closing it with Esc / X means "back out" (title_screen.gd checks `accepted`).
## The mine mouth now agrees: Esc / X keeps Krystal on the surface and the screen is offered again next
## time; only the Done button carries her into the Below and marks the screen as seen.
## Real surface + UI via Game.load_area headless (runner scene protected by a placeholder scene).

const UiUtil := preload("res://src/ui/ui_util.gd")

var _saved_mode: String = ""
var _runner: Node = null
var _saved_allow: bool = true
var _saved_confirmed: Variant = null
var _saved_zone: String = ""
var _saved_safe: bool = true


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	_saved_zone = Game.zone_id
	_saved_safe = Game.in_safe_zone
	_runner = get_tree().current_scene
	_saved_allow = UiUtil.allow_settings_save
	UiUtil.allow_settings_save = false          # never write the player's settings file
	_saved_confirmed = Settings.get_value("comfort_confirmed")


func after_each() -> void:
	var cur: Node = get_tree().current_scene
	if _runner != null and is_instance_valid(_runner):
		get_tree().current_scene = _runner
	if cur != null and is_instance_valid(cur) and cur != _runner:
		cur.queue_free()
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game.player = null
	Game.area = null
	Game.area_id = ""
	Game.director = null
	Game.companion_nodes = {}
	Game.mode = _saved_mode
	Game.zone_id = _saved_zone          # the loaded surface's zone poll changed these (runner ISOLATION note)
	Game.in_safe_zone = _saved_safe
	get_tree().paused = false
	Audio.stop_all()
	GameState.active = false
	Settings.set_value("comfort_confirmed", _saved_confirmed)
	UiUtil.allow_settings_save = _saved_allow
	await wait_frames(3)


## Loads the real surface at the mine mouth and returns the mine entrance node (or null).
func _mine_entrance() -> Node:
	var holder := Node.new()
	holder.name = "AuditHolder"
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	GameState.set_flag("mine_opened", true)
	await Game.load_area("surface", "mine_exit")
	assert_eq(Game.area_id, "surface", "on the surface")
	var lm: Variant = Game.area.get("landmarks")
	var me: Variant = lm.get("mine_entrance") if lm is Node else null
	assert_true(me is Node, "found the mine entrance")
	return me as Node if me is Node else null


## Waits up to ~4 s for the Below to finish loading.
func _wait_for_below() -> void:
	for i in 240:
		await get_tree().process_frame
		if Game.area_id == "below" and Game.mode == "playing":
			break


func test_closing_pre_mine_comfort_screen_stays_on_the_surface() -> void:
	var me: Node = await _mine_entrance()
	if me == null:
		return
	me.interact(null)                              # "Enter the Hollow Mine" (first time -> comfort screen)
	await wait_frames(3)
	assert_true(Game.ui.is_open("comfort"), "pre-mine comfort screen is showing")
	Game.ui.close("comfort")                       # exactly what Esc / the X button do (ui_root._input)
	await _wait_for_below()
	assert_eq(Game.area_id, "surface", "closing (not confirming) the comfort screen should cancel entering the mine")
	assert_false(bool(GameState.get_flag("mine_comfort_seen")), "a cancelled screen should be offered again next time")
	assert_false(bool(GameState.get_flag("entered_below")), "not marked as entered")
	if Game.area_id != "surface" or not is_instance_valid(me):
		return                                     # went below anyway: the surface (and `me`) is gone
	# The doorway is re-armed straight away and asks again.
	assert_false((me.get_interaction(null) as Dictionary).is_empty(), "the doorway still offers 'Enter the Hollow Mine'")
	me.interact(null)
	await wait_frames(3)
	assert_true(Game.ui.is_open("comfort"), "the comfort screen is offered again")
	Game.ui.close("comfort")
	await wait_frames(3)
	assert_eq(Game.area_id, "surface", "still on the surface after closing it again")


func test_confirming_pre_mine_comfort_screen_enters_the_mine() -> void:
	var me: Node = await _mine_entrance()
	if me == null:
		return
	me.interact(null)
	await wait_frames(3)
	assert_true(Game.ui.is_open("comfort"), "pre-mine comfort screen is showing")
	var panel: Node = Game.ui.panels.get("comfort")
	var done: Node = panel.find_child("Confirm", true, false) if panel != null else null
	assert_true(done is Button, "the Done button exists")
	if not (done is Button):
		return
	(done as Button).pressed.emit()                # the Done button
	await _wait_for_below()
	assert_eq(Game.area_id, "below", "Done carries Krystal into the mine")
	assert_true(bool(GameState.get_flag("mine_comfort_seen")), "the screen is marked as seen")
	assert_true(bool(GameState.get_flag("entered_below")), "marked as entered")
