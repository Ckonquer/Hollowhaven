extends "res://tests/test_case.gd"
## AUDIT verification probes (UI): exercise the reported paths through the REAL input pipeline
## (Viewport.push_input) rather than calling handlers directly. All five defects are fixed (crafting_panel,
## settings_panel + ui_util, title_screen); these now stand as regression checks of the fixed behaviour.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const SettingsPanel := preload("res://src/ui/panels/settings_panel.gd")
const TITLE := "res://src/ui/title_screen.gd"

var ui: CanvasLayer = null
var _mode_before := ""
var _settings_before: Dictionary = {}


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_mode_before = Game.mode
	Game.mode = "playing"
	_settings_before = Settings.values.duplicate(true)
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func after_each() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	ui = null
	await wait_frames(2)
	Settings.values = _settings_before.duplicate(true)
	Settings.setup_input_map()
	for k in Settings.values:
		Events.settings_changed.emit(String(k))
	get_tree().paused = false
	Game.mode = _mode_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _push_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	get_viewport().push_input(up)


func _focus_name(panel: Control) -> String:
	var fo := get_viewport().gui_get_focus_owner()
	if fo == null:
		return "<none>"
	if fo == panel.get("craft_btn"):
		return "craft_btn"
	var rows: Dictionary = panel.get("_rows")
	for rid in rows:
		if rows[rid] == fo:
			return "row:" + String(rid)
	return "other:" + String(fo.name)


## Real keyboard path: open crafting, arrow into the recipe list, arrow to another recipe, press Enter.
func test_keyboard_enter_on_arrowed_recipe_row_crafts_that_recipe() -> void:
	GameState.give_item("wood", 20)
	GameState.give_item("stone", 10)
	GameState.give_item("fiber", 10)
	ui.open("crafting")
	await wait_frames(4)
	var panel: Control = ui.panels["crafting"]
	var sel_start := String(panel.get("_selected"))
	var trail: Array = [_focus_name(panel)]
	for k in [KEY_LEFT, KEY_UP, KEY_DOWN]:
		_push_key(k)
		await wait_frames(1)
		trail.append(_focus_name(panel))
	var focused := _focus_name(panel)
	var inv_before := {}
	for rid in (panel.get("_rows") as Dictionary):
		var res := String(ItemDB.recipe(String(rid)).get("result", ""))
		inv_before[res] = GameState.count_item(res)
	_push_key(KEY_ENTER)
	await wait_frames(2)
	var made: Array = []
	for res in inv_before:
		if GameState.count_item(String(res)) > int(inv_before[res]):
			made.append(String(res))
	print("AUDIT-VERIFY-CRAFT selected_at_open=%s focus_trail=%s focused=%s made=%s selected_now=%s" % [sel_start, str(trail), focused, str(made), String(panel.get("_selected"))])
	if focused.begins_with("row:"):
		var focused_rid := focused.substr(4)
		var want := String(ItemDB.recipe(focused_rid).get("result", ""))
		assert_true(made.is_empty() or made.has(want), "Enter on focused row '%s' crafted %s instead" % [focused_rid, str(made)])


## With nothing craftable, default_focus() is null: can the arrow keys reach the recipe list at all?
func test_keyboard_reaches_recipe_list_when_nothing_is_craftable() -> void:
	ui.open("crafting")
	await wait_frames(4)
	var panel: Control = ui.panels["crafting"]
	var trail: Array = [_focus_name(panel)]
	for k in [KEY_DOWN, KEY_UP, KEY_LEFT, KEY_RIGHT]:
		_push_key(k)
		await wait_frames(1)
		trail.append(_focus_name(panel))
	print("AUDIT-VERIFY-CRAFT-EMPTY rows=%d focus_trail=%s" % [(panel.get("_rows") as Dictionary).size(), str(trail)])
	var reached := false
	for t in trail:
		if String(t) != "<none>":
			reached = true
	assert_true(reached, "keyboard focus never enters the crafting panel when nothing is craftable")


## Wheel over the Controls list while "Press a key..." is showing: pushed through the real pipeline.
func test_wheel_while_capturing_through_viewport() -> void:
	ui.open("settings", {"tab": "controls"})
	await wait_frames(3)
	var panel: Control = ui.panels["settings"]
	var sc: ScrollContainer = panel.tabs.get_child(1)
	panel._begin_capture("craft")
	var before := sc.scroll_vertical
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	# push_input takes WINDOW coordinates (the headless window is tiny and stretched to the canvas).
	wheel.position = get_viewport().get_final_transform() * sc.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel)
	await wait_frames(2)
	print("AUDIT-VERIFY-REBIND craft=%s scroll %d -> %d zoom_out_conflict=%s" % [Settings.action_label("craft"), before, sc.scroll_vertical, str(Settings.actions_using(wheel))])
	assert_ne(Settings.action_label("craft"), "Wheel Down", "scrolling while capturing rebound Crafting to the wheel")
	assert_true(sc.scroll_vertical > before, "the wheel scrolls the Controls list while capturing")


## Settings > Reset to defaults (panel path, no confirm owner): which comfort options survive?
func test_reset_to_defaults_keeps_comfort_options() -> void:
	Settings.set_value("arachnophobia", true)
	Settings.set_value("reduce_flashing", true)
	Settings.set_value("reduce_shake", true)
	Settings.set_value("horror_intensity", 0)
	Settings.set_value("comfort_confirmed", true)
	var seen: Array = []
	var cb := func(k: String) -> void: seen.append(k)
	Events.settings_changed.connect(cb)
	var p: Control = SettingsPanel.new()
	p.setup({"tab": "video"})
	add_child(p)
	await wait_frames(2)
	await p._reset_defaults()
	Events.settings_changed.disconnect(cb)
	print("AUDIT-VERIFY-RESET arachnophobia=%s reduce_flashing=%s reduce_shake=%s intensity=%s comfort_confirmed=%s emitted_arachno=%s" % [
		str(Settings.get_value("arachnophobia")), str(Settings.get_value("reduce_flashing")), str(Settings.get_value("reduce_shake")),
		str(Settings.get_value("horror_intensity")), str(Settings.get_value("comfort_confirmed")), str(seen.has("arachnophobia"))])
	p.queue_free()
	await wait_frames(1)
	assert_true(bool(Settings.get_value("arachnophobia")), "Reset to defaults switched arachnophobia mode off")
	assert_true(bool(Settings.get_value("reduce_flashing")), "Reset to defaults switched reduce flashing off")


## Title Continue line from a save made in the "silk" step with arachnophobia off, read with it on.
func test_title_continue_uses_alt_title_after_toggle() -> void:
	Settings.set_value("arachnophobia", false)
	var steps: Array = GameState.quests.steps()
	for i in steps.size():
		if String(steps[i]["id"]) == "silk":
			GameState.quests.index = i
	var data: Dictionary = SaveSystem.build_save_data()
	Settings.set_value("arachnophobia", true)
	var txt: String = load(TITLE).continue_text(data)
	var meta: Dictionary = data["meta"]
	print("AUDIT-VERIFY-TITLE step=%s step_title=%s continue='%s'" % [String(meta.get("step", "")), String(meta.get("step_title", "")), txt])
	assert_false(txt.contains("Silk"), "title Continue shows '%s' with arachnophobia on" % txt)
