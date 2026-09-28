extends "res://tests/test_case.gd"
## Settings UI binding logic: the schema matches Settings, values snap / coerce / format correctly,
## writes go through Settings (with change events), and the rebinding capture flow works.

const Schema := preload("res://src/ui/settings_schema.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const SettingsPanel := preload("res://src/ui/panels/settings_panel.gd")
const HorrorData := preload("res://data/horror_events.gd")

var _saved_values: Dictionary = {}
var _changes: Array = []


func before_each() -> void:
	UiUtil.allow_settings_save = false
	_saved_values = Settings.values.duplicate(true)
	_changes = []


func after_each() -> void:
	Settings.values = _saved_values.duplicate(true)
	Settings.setup_input_map()
	if Events.settings_changed.is_connected(_on_changed):
		Events.settings_changed.disconnect(_on_changed)


func _on_changed(key: String) -> void:
	_changes.append(key)


func test_schema_keys_exist_with_sane_ranges() -> void:
	for r in Schema.ROWS:
		var key := String(r["key"])
		assert_true(Settings.DEFAULTS.has(key), "schema key %s exists in Settings" % key)
		var def: Variant = Settings.DEFAULTS[key]
		match String(r["type"]):
			"toggle":
				assert_true(def is bool, "%s toggle is bool" % key)
			"slider":
				assert_true(float(def) >= float(r["min"]) and float(def) <= float(r["max"]), "%s default inside range" % key)
				assert_true(float(r["step"]) > 0.0, "%s has a step" % key)
			"option":
				var found := false
				for o in r["options"]:
					if int(o[0]) == int(def):
						found = true
				assert_true(found, "%s default is one of the options" % key)
	# every tab has content, and comfort covers what the comfort screen promises
	for t in Schema.TABS:
		if String(t[0]) != "controls":
			assert_true(Schema.rows_for(String(t[0])).size() > 0, "tab %s has rows" % t[0])
	for key in ["horror_intensity", "arachnophobia", "reduce_shake", "reduce_flashing", "captions"]:
		assert_eq(String(Schema.row(key).get("tab", "")), "comfort", key)


func test_snap_clamps_and_steps() -> void:
	var fov := Schema.row("fov")
	assert_almost(Schema.snap(fov, 120.0), 95.0)
	assert_almost(Schema.snap(fov, 10.0), 55.0)
	assert_almost(Schema.snap(fov, 70.4), 70.0)
	var sens := Schema.row("mouse_sensitivity")
	assert_almost(Schema.snap(sens, 0.52), 0.5, 0.0001)
	assert_almost(Schema.snap(sens, 0.53), 0.55, 0.0001)


func test_coerce_matches_stored_types() -> void:
	assert_eq(typeof(Schema.coerce("fov", 70)), TYPE_FLOAT)
	assert_eq(typeof(Schema.coerce("quality", 1.6)), TYPE_INT)
	assert_eq(Schema.coerce("quality", 1.6), 2)
	assert_eq(typeof(Schema.coerce("captions", 1)), TYPE_BOOL)


func test_apply_writes_settings_and_emits_change() -> void:
	Events.settings_changed.connect(_on_changed)
	var v: Variant = Schema.apply("fov", 81.3)
	assert_almost(float(v), 81.0)
	assert_almost(float(Settings.get_value("fov")), 81.0)
	assert_true(_changes.has("fov"), "settings_changed emitted")
	Schema.apply("horror_intensity", 0)
	assert_eq(int(Settings.get_value("horror_intensity")), 0)
	assert_eq(typeof(Settings.get_value("horror_intensity")), TYPE_INT)


func test_value_formatting() -> void:
	assert_eq(Schema.format_value(Schema.row("master_volume"), 0.85), "85%")
	assert_eq(Schema.format_value(Schema.row("fov"), 70.0), "70°")
	assert_eq(Schema.format_value(Schema.row("camera_distance"), 5.0), "5.0 m")
	assert_eq(Schema.format_value(Schema.row("mouse_sensitivity"), 0.5), "0.50×")
	assert_eq(Schema.option_index(Schema.row("max_fps"), 60), 2)
	assert_eq(Schema.option_index(Schema.row("max_fps"), 999), 0, "unknown values fall back to the first option")


func test_intensity_descriptions_come_from_horror_data() -> void:
	for lvl in 3:
		var info := Schema.intensity_info(lvl)
		assert_eq(String(info["name"]), String(HorrorData.INTENSITY[lvl]["name"]))
		assert_eq(String(info["desc"]), String(HorrorData.INTENSITY[lvl]["desc"]))


func test_rebind_capture_flow() -> void:
	var p: Control = SettingsPanel.new()
	p.setup({"tab": "controls"})
	add_child(p)
	await wait_frames(2)
	assert_false(p.is_capturing_input())
	p._begin_capture("jump")
	assert_true(p.is_capturing_input(), "waiting for a key")
	# Escape cancels without changing anything
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	var before := Settings.action_label("jump")
	p._input(esc)
	assert_false(p.is_capturing_input(), "escape cancels capture")
	assert_eq(Settings.action_label("jump"), before)
	# A real key rebinds
	p._begin_capture("jump")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	k.pressed = true
	p._input(k)
	assert_false(p.is_capturing_input())
	assert_eq(UiUtil.action_codes("jump")[0], "key:%d" % KEY_K, "jump now uses K")
	# Rebinding onto an existing key shows a conflict warning
	p._begin_capture("jump")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	p._input(e)
	var warn: Label = p._bind_rows["jump"]["warn"]
	assert_true(warn.text.contains("Interact"), "conflict names the other action: " + warn.text)
	p.queue_free()
	await wait_frames(1)


func test_rebindable_actions_are_all_defined() -> void:
	for pair in Settings.REBINDABLE:
		assert_true(Settings.DEFAULT_BINDINGS.has(String(pair[0])), String(pair[0]))
		assert_true(String(pair[1]) != "", "friendly name for " + String(pair[0]))


func _mouse(button: int, at: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = button as MouseButton
	mb.pressed = true
	mb.position = at
	mb.global_position = at
	return mb


## While "Press a key..." shows: the wheel never binds (it scrolls), a left click elsewhere backs out
## without binding, a left click on the capturing box binds Left Mouse, other buttons bind as before.
func test_rebind_capture_ignores_the_wheel_and_clicks_elsewhere() -> void:
	var p: Control = SettingsPanel.new()
	p.setup({"tab": "controls"})
	add_child(p)
	await wait_frames(3)
	var before := Settings.action_label("jump")
	p._begin_capture("jump")
	for wb in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		p._input(_mouse(int(wb)))
	assert_true(p.is_capturing_input(), "the wheel doesn't end the capture")
	assert_eq(Settings.action_label("jump"), before, "the wheel is never bound")
	p._input(_mouse(MOUSE_BUTTON_LEFT, (p._done_btn as Control).get_global_rect().get_center()))
	assert_false(p.is_capturing_input(), "clicking elsewhere (Done) cancels the capture")
	assert_eq(Settings.action_label("jump"), before, "and binds nothing")
	var box: Button = p._bind_rows["use_item"]["btn"]
	p._begin_capture("use_item")
	p._input(_mouse(MOUSE_BUTTON_LEFT, box.get_global_rect().get_center()))
	assert_false(p.is_capturing_input())
	assert_eq(UiUtil.action_codes("use_item")[0], "mouse:%d" % MOUSE_BUTTON_LEFT, "a click on the capturing box binds Left Mouse")
	p._begin_capture("jump")
	p._input(_mouse(MOUSE_BUTTON_MIDDLE))
	assert_eq(UiUtil.action_codes("jump")[0], "mouse:%d" % MOUSE_BUTTON_MIDDLE, "other mouse buttons still bind")
	p.queue_free()
	await wait_frames(1)


## Real input pipeline: the wheel over the (scrolling) Controls list scrolls it while capturing.
func test_wheel_scrolls_the_controls_list_while_capturing() -> void:
	var p: Control = SettingsPanel.new()
	p.setup({"tab": "controls"})
	add_child(p)
	await wait_frames(3)
	var sc: ScrollContainer = p.tabs.get_child(1)
	var need: float = (sc.get_child(0) as Control).get_combined_minimum_size().y
	p._begin_capture("craft")
	var before: int = sc.scroll_vertical
	# push_input takes window coordinates (the headless window is tiny and stretched to the 1920x1080 canvas).
	var at: Vector2 = get_viewport().get_final_transform() * sc.get_global_rect().get_center()
	get_viewport().push_input(_mouse(MOUSE_BUTTON_WHEEL_DOWN, at))
	await wait_frames(2)
	assert_true(p.is_capturing_input(), "still waiting for a key")
	assert_ne(Settings.action_label("craft"), "Wheel Down", "the wheel was not bound")
	if need > sc.size.y + 1.0:
		assert_true(sc.scroll_vertical > before, "the list scrolled (%d -> %d)" % [before, sc.scroll_vertical])
	p.queue_free()
	await wait_frames(1)


## "Reset to defaults" restores the other settings but keeps the key bindings and every comfort choice,
## and announces only the settings that actually changed (no live arachnophobia rebuild).
func test_reset_to_defaults_keeps_bindings_and_comfort_options() -> void:
	Settings.set_value("arachnophobia", true)
	Settings.set_value("reduce_flashing", true)
	Settings.set_value("reduce_shake", true)
	Settings.set_value("captions", false)
	Settings.set_value("horror_intensity", 0)
	Settings.set_value("comfort_confirmed", true)
	Settings.set_value("invert_y", false)
	Settings.set_value("fov", 90.0)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	k.pressed = true
	Settings.rebind("jump", k)
	var p: Control = SettingsPanel.new()
	p.setup({"tab": "video"})
	add_child(p)
	await wait_frames(2)
	Events.settings_changed.connect(_on_changed)
	await p._reset_defaults()
	assert_true(bool(Settings.get_value("arachnophobia")), "arachnophobia mode kept")
	assert_true(bool(Settings.get_value("reduce_flashing")), "reduce flashing kept")
	assert_true(bool(Settings.get_value("reduce_shake")), "reduce shake kept")
	assert_false(bool(Settings.get_value("captions")), "captions choice kept")
	assert_eq(int(Settings.get_value("horror_intensity")), 0, "horror intensity kept")
	assert_true(bool(Settings.get_value("comfort_confirmed")), "comfort screen stays confirmed")
	assert_eq(UiUtil.action_codes("jump")[0], "key:%d" % KEY_K, "key bindings kept")
	assert_almost(float(Settings.get_value("fov")), float(Settings.DEFAULTS["fov"]), 0.001, "other settings reset")
	assert_true(_changes.has("fov"), "changed settings are announced")
	assert_false(_changes.has("arachnophobia"), "no arachnophobia change announced")
	assert_false(_changes.has("invert_y"), "unchanged settings are not announced")
	assert_false(_changes.has("bindings"), "bindings not touched")
	p.queue_free()
	await wait_frames(1)
