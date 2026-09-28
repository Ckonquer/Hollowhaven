extends "res://tests/unit/test_core_base.gd"
## Settings (autoload/settings.gd): defaults, typed set/get, crafted cfg loading (temp path only),
## save/load round trip, rebinding (InputMap + labels), reset. The base restores Settings.values and
## the InputMap after every test; the player's real user://settings.cfg must never change.

const HorrorData := preload("res://data/horror_events.gd")

var _real_cfg_state: Array = []


func setup() -> void:
	_real_cfg_state = _real_cfg_fingerprint()
	Settings.reset_to_defaults()


func teardown() -> void:
	if FileAccess.file_exists(_cfg()):
		DirAccess.remove_absolute(_cfg())
	assert_eq(_real_cfg_fingerprint(), _real_cfg_state, "the real settings.cfg was not touched")


func _real_cfg_fingerprint() -> Array:
	if not FileAccess.file_exists(Settings.PATH):
		return [false]
	return [true, FileAccess.get_modified_time(Settings.PATH), FileAccess.get_file_as_string(Settings.PATH).md5_text()]


func _cfg() -> String:
	return SaveSystem.save_dir.path_join("settings_test.cfg")


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k


func _mouse(b: MouseButton) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = b
	return m


# --- defaults & get/set ------------------------------------------------------------------------------------

func test_defaults_and_default_bindings() -> void:
	assert_deep_eq(Settings.values, Settings.DEFAULTS.duplicate(true), "values")
	assert_eq(Settings.get_value("fov"), 70.0)
	assert_eq(Settings.get_value("horror_intensity"), 1)
	assert_eq(Settings.get_value("arachnophobia"), false)
	assert_eq(Settings.get_value("captions"), true)
	assert_eq(Settings.action_label("interact"), "E")
	assert_eq(Settings.action_label("attack"), "Left Mouse")
	assert_eq(Settings.action_label("use_item"), "Right Mouse")
	assert_eq(Settings.action_label("jump"), "Space")
	assert_eq(Settings.action_label("inventory"), "Tab")
	assert_eq(Settings.action_label("pause"), "Escape")
	assert_eq(Settings.action_label("zoom_in"), "Wheel Up")
	assert_eq(Settings.action_label("no_such_action"), "?")
	assert_eq(InputMap.action_get_events("move_forward").size(), 2, "WASD plus arrow keys")


func test_every_default_binding_is_valid_and_conflict_free() -> void:
	var used := {}
	for action in Settings.DEFAULT_BINDINGS:
		assert_true(InputMap.has_action(action), action + " exists in the InputMap")
		var list: Array = Settings.DEFAULT_BINDINGS[action]
		assert_false(list.is_empty(), action + " has a default")
		assert_eq(InputMap.action_get_events(action).size(), list.size(), action + " events installed")
		for b in list:
			assert_not_null(Settings._deserialize(b), "%s: %s parses" % [action, b])
			assert_false(used.has(b), "%s shares %s with %s" % [action, b, used.get(b, "")])
			used[b] = action
	for pair in Settings.REBINDABLE:
		assert_true(Settings.DEFAULT_BINDINGS.has(pair[0]), "rebindable %s has defaults" % pair[0])
	for n in 8:
		assert_true(Settings.DEFAULT_BINDINGS.has("hotbar_%d" % (n + 1)))


func test_get_value_falls_back_to_defaults() -> void:
	Settings.values.erase("fov")
	assert_eq(Settings.get_value("fov"), 70.0)
	assert_null(Settings.get_value("not_a_setting"))


func test_set_value_coerces_to_the_default_type() -> void:
	Settings.set_value("fov", 80)
	assert_eq(typeof(Settings.get_value("fov")), TYPE_FLOAT)
	assert_eq(Settings.get_value("fov"), 80.0)
	Settings.set_value("horror_intensity", 2.0)   # e.g. from a slider
	assert_eq(typeof(Settings.get_value("horror_intensity")), TYPE_INT)
	assert_eq(Settings.get_value("horror_intensity"), 2)
	assert_true(HorrorData.INTENSITY.has(Settings.get_value("horror_intensity")), "usable as a data key")
	Settings.set_value("horror_intensity", 0.6)
	assert_eq(Settings.get_value("horror_intensity"), 1, "rounded")
	Settings.set_value("invert_y", 1)
	assert_eq(Settings.get_value("invert_y"), true)
	Settings.set_value("mouse_sensitivity", "0.75")
	assert_eq(Settings.get_value("mouse_sensitivity"), 0.75)
	Settings.set_value("arachnophobia", "true")
	assert_eq(Settings.get_value("arachnophobia"), true)
	Settings.set_value("max_fps", "144")
	assert_eq(Settings.get_value("max_fps"), 144)


func test_set_value_clamps_to_ranges() -> void:
	Settings.set_value("fov", 200.0)
	assert_eq(Settings.get_value("fov"), 95.0)
	Settings.set_value("fov", 10)
	assert_eq(Settings.get_value("fov"), 55.0)
	Settings.set_value("horror_intensity", 7)
	assert_eq(Settings.get_value("horror_intensity"), 2)
	Settings.set_value("horror_intensity", -1)
	assert_eq(Settings.get_value("horror_intensity"), 0)
	Settings.set_value("music_volume", -0.5)
	assert_eq(Settings.get_value("music_volume"), 0.0)
	Settings.set_value("master_volume", 3)
	assert_eq(Settings.get_value("master_volume"), 1.0)
	Settings.set_value("render_scale", 0.1)
	assert_eq(Settings.get_value("render_scale"), 0.5)
	for key in Settings.RANGES:
		assert_true(Settings.DEFAULTS.has(key), "range for a real setting: " + key)
		var r: Array = Settings.RANGES[key]
		assert_true(float(Settings.DEFAULTS[key]) >= float(r[0]) and float(Settings.DEFAULTS[key]) <= float(r[1]), key + " default inside its range")


func test_set_value_rejects_incompatible_values() -> void:
	var ch := record(Events.settings_changed, 1)
	Settings.set_value("fov", "wide")
	Settings.set_value("arachnophobia", {})
	Settings.set_value("quality", "high")
	Settings.set_value("mouse_sensitivity", NAN)
	Settings.set_value("bindings", "E")
	assert_eq(Settings.get_value("fov"), 70.0)
	assert_eq(Settings.get_value("arachnophobia"), false)
	assert_eq(Settings.get_value("quality"), 2)
	assert_eq(Settings.get_value("mouse_sensitivity"), 0.5)
	assert_eq(Settings.get_value("bindings"), {})
	assert_eq(ch.size(), 0, "nothing changed, nothing emitted")
	assert_true(logged("rejected value"), "warned")


func test_set_value_emits_only_on_change() -> void:
	var ch := record(Events.settings_changed, 1)
	Settings.set_value("fov", 80.0)
	Settings.set_value("fov", 80.0)
	Settings.set_value("fov", 80)   # same after coercion
	assert_eq(ch, [["fov"]])
	Settings.set_value("custom_ui_flag", "abc")   # unknown keys pass through
	Settings.set_value("custom_ui_flag", "abc")
	Settings.set_value("custom_ui_flag", 5)       # type change is not a script error
	assert_eq(Settings.get_value("custom_ui_flag"), 5)
	assert_eq(ch.size(), 3)


func test_coerce_value_table() -> void:
	assert_eq(Settings.coerce_value("captions", 0), false)
	assert_eq(Settings.coerce_value("captions", "off"), false)
	assert_null(Settings.coerce_value("captions", "maybe"))
	assert_eq(Settings.coerce_value("quality", true), 1)
	assert_null(Settings.coerce_value("quality", [1]))
	assert_eq(Settings.coerce_value("fov", " 66.5 "), 66.5)
	assert_null(Settings.coerce_value("fov", INF))
	assert_eq(Settings.coerce_value("anything_else", [1, 2]), [1, 2])


# --- loading & saving (temp paths only) -----------------------------------------------------------------------

func test_load_crafted_cfg() -> void:
	write_text(_cfg(), """[settings]

fov=80
horror_intensity=1.0
arachnophobia=true
master_volume=5.0
mouse_sensitivity="fast"
reduce_shake=1
quality=7
render_scale=0.2
unknown_key=3
bindings={
"attack": ["mouse:2", "mouse:2", 5],
"bogus_action": ["key:65"],
"dodge": ["key:abc", "mouse:0"],
"interact": ["key:82"],
"jump": "garbage"
}
""")
	Settings.load_settings(_cfg())
	assert_eq(Settings.get_value("fov"), 80.0, "int in the file becomes the float setting")
	assert_eq(typeof(Settings.get_value("horror_intensity")), TYPE_INT, "float in the file becomes the int setting")
	assert_eq(Settings.get_value("horror_intensity"), 1)
	assert_eq(Settings.get_value("arachnophobia"), true)
	assert_eq(Settings.get_value("master_volume"), 1.0, "clamped")
	assert_eq(Settings.get_value("mouse_sensitivity"), 0.5, "invalid value ignored")
	assert_eq(Settings.get_value("reduce_shake"), true)
	assert_eq(Settings.get_value("quality"), 2)
	assert_eq(Settings.get_value("render_scale"), 0.5)
	assert_false(Settings.values.has("unknown_key"))
	assert_eq(Settings.get_value("bindings"), {"attack": ["mouse:2"], "interact": ["key:%d" % KEY_R]}, "bindings sanitised")
	Settings.setup_input_map()
	assert_eq(Settings.action_label("interact"), "R")
	assert_eq(Settings.action_label("attack"), "Right Mouse")
	assert_eq(Settings.action_label("jump"), "Space", "garbage binding falls back to the default")
	assert_eq(Settings.action_label("dodge"), "Ctrl")


func test_load_missing_or_garbage_file_keeps_values() -> void:
	Settings.set_value("fov", 90.0)
	var before := Settings.values.duplicate(true)
	Settings.load_settings(SaveSystem.save_dir.path_join("does_not_exist.cfg"))
	assert_deep_eq(Settings.values, before, "missing file")
	write_text(_cfg(), "this is ][ not a config = = =")
	expect_error("ConfigFile")   # the engine may report the parse error; values must stay intact
	expect_error("parse")
	Settings.load_settings(_cfg())
	assert_deep_eq(Settings.values, before, "garbage file")


func test_save_and_load_round_trip_on_a_temp_path() -> void:
	Settings.set_value("fov", 88.0)
	Settings.set_value("arachnophobia", true)
	Settings.set_value("horror_intensity", 0)
	Settings.rebind("interact", _key(KEY_R))
	var expected := Settings.values.duplicate(true)
	Settings.save(_cfg())
	assert_true(FileAccess.file_exists(_cfg()))
	Settings.reset_to_defaults()
	assert_eq(Settings.action_label("interact"), "E")
	Settings.load_settings(_cfg())
	Settings.setup_input_map()
	assert_deep_eq(Settings.values, expected, "values")
	assert_eq(Settings.action_label("interact"), "R")


# --- rebinding ------------------------------------------------------------------------------------------------------

func test_rebind_changes_input_map_and_label() -> void:
	var ch := record(Events.settings_changed, 1)
	Settings.rebind("interact", _key(KEY_R))
	var evs := InputMap.action_get_events("interact")
	assert_eq(evs.size(), 1)
	assert_true(evs[0] is InputEventKey and evs[0].physical_keycode == KEY_R)
	assert_eq(Settings.action_label("interact"), "R")
	assert_true(InputMap.event_is_action(_key(KEY_R), "interact"), "R now interacts")
	assert_false(InputMap.event_is_action(_key(KEY_E), "interact"), "E no longer does")
	assert_eq(Settings.get_value("bindings")["interact"], ["key:%d" % KEY_R])
	assert_eq(ch, [["bindings"]])


func test_rebind_keeps_secondary_and_avoids_duplicates() -> void:
	Settings.rebind("move_forward", _key(KEY_I))
	assert_eq(Settings.get_value("bindings")["move_forward"], ["key:%d" % KEY_I, "key:%d" % KEY_UP], "arrow key kept")
	assert_eq(Settings.action_label("move_forward"), "I")
	Settings.rebind("move_forward", _key(KEY_UP))
	assert_eq(Settings.get_value("bindings")["move_forward"], ["key:%d" % KEY_UP], "not listed twice")
	assert_eq(InputMap.action_get_events("move_forward").size(), 1)


func test_rebind_mouse_and_logical_keycodes() -> void:
	Settings.rebind("attack", _mouse(MOUSE_BUTTON_RIGHT))
	assert_eq(Settings.action_label("attack"), "Right Mouse")
	assert_true(InputMap.action_get_events("attack")[0] is InputEventMouseButton)
	var k := InputEventKey.new()
	k.keycode = KEY_T   # no physical keycode
	Settings.rebind("lantern", k)
	assert_eq(Settings.action_label("lantern"), "T")


func test_rebind_ignores_unknown_actions_and_unsupported_events() -> void:
	Settings.rebind("fly", _key(KEY_Z))
	assert_eq(Settings.get_value("bindings"), {})
	assert_true(logged("cannot rebind unknown action"))
	Settings.rebind("jump", InputEventJoypadButton.new())
	assert_eq(Settings.get_value("bindings"), {})
	assert_eq(Settings.action_label("jump"), "Space")


func test_reset_bindings() -> void:
	Settings.rebind("interact", _key(KEY_R))
	Settings.rebind("attack", _mouse(MOUSE_BUTTON_MIDDLE))
	var ch := record(Events.settings_changed, 1)
	Settings.reset_bindings()
	assert_eq(Settings.get_value("bindings"), {})
	assert_eq(Settings.action_label("interact"), "E")
	assert_eq(Settings.action_label("attack"), "Left Mouse")
	assert_true(InputMap.event_is_action(_key(KEY_E), "interact"))
	assert_eq(ch, [["bindings"]])


func test_reset_to_defaults_can_keep_bindings() -> void:
	Settings.set_value("fov", 90.0)
	Settings.rebind("interact", _key(KEY_R))
	Settings.reset_to_defaults(true)
	assert_eq(Settings.get_value("fov"), 70.0)
	assert_eq(Settings.action_label("interact"), "R", "bindings kept")
	Settings.reset_to_defaults()
	assert_eq(Settings.action_label("interact"), "E")


func test_set_value_bindings_updates_input_map() -> void:
	Settings.set_value("bindings", {"interact": ["key:%d" % KEY_R], "nonsense": ["key:1"]})
	assert_eq(Settings.get_value("bindings"), {"interact": ["key:%d" % KEY_R]})
	assert_eq(Settings.action_label("interact"), "R")


func test_actions_using_reports_conflicts() -> void:
	assert_eq(Settings.actions_using(_key(KEY_E)), ["interact"])
	assert_eq(Settings.actions_using(_key(KEY_UP)), ["move_forward"], "secondary bindings count")
	Settings.rebind("jump", _key(KEY_E))
	assert_eq(Settings.actions_using(_key(KEY_E)), ["jump", "interact"])
	assert_eq(Settings.actions_using(_key(KEY_K)), [])
	assert_eq(Settings.actions_using(InputEventJoypadButton.new()), [])


func test_event_labels() -> void:
	assert_eq(Settings.event_label(_mouse(MOUSE_BUTTON_MIDDLE)), "Middle Mouse")
	assert_eq(Settings.event_label(_mouse(MOUSE_BUTTON_WHEEL_DOWN)), "Wheel Down")
	assert_eq(Settings.event_label(_mouse(MOUSE_BUTTON_XBUTTON1)), "Mouse %d" % MOUSE_BUTTON_XBUTTON1)
	assert_eq(Settings.event_label(_key(KEY_SHIFT)), "Shift")


func test_sanitize_bindings() -> void:
	var out := Settings.sanitize_bindings({"jump": PackedStringArray(["key:%d" % KEY_K]), "dodge": [], "craft": ["mouse:-1", "key:0", "pad:3"], 5: ["key:65"]})
	assert_eq(out, {"jump": ["key:%d" % KEY_K]})


func test_auto_quality_picks_lighter_presets_for_weak_gpus() -> void:
	var saved_q: Variant = Settings.get_value("quality")
	var saved_rs: Variant = Settings.get_value("render_scale")
	assert_eq(Settings.auto_quality(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU), "high")
	assert_eq(int(Settings.get_value("quality")), int(saved_q), "a dedicated GPU keeps the defaults")
	assert_eq(Settings.auto_quality(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU), "medium")
	assert_eq(int(Settings.get_value("quality")), 1)
	assert_almost(float(Settings.get_value("render_scale")), 0.85, 0.001)
	assert_eq(Settings.auto_quality(RenderingDevice.DEVICE_TYPE_CPU), "low")
	assert_eq(int(Settings.get_value("quality")), 0)
	Settings.set_value("quality", saved_q)
	Settings.set_value("render_scale", saved_rs)
