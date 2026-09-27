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
