extends Node
## Player settings (persisted to user://settings.cfg) and the input map (rebindable).
## Read: Settings.get_value("mouse_sensitivity")   Write: Settings.set_value("fov", 75.0)
## Every change emits Events.settings_changed(key). Call save() to persist (UI does this on close).

const PATH := "user://settings.cfg"

const DEFAULTS := {
	# Gameplay / camera
	"mouse_sensitivity": 0.5,       # 0.1 .. 2.0
	"invert_y": false,
	"fov": 70.0,                    # 55 .. 95
	"camera_distance": 5.0,         # default zoom (2.5 .. 8)
	"show_hints": true,
	# Audio (linear 0..1)
	"master_volume": 0.85,
	"music_volume": 0.6,
	"ambience_volume": 0.8,
	"sfx_volume": 0.85,
	"ui_volume": 0.7,
	# Comfort & horror
	"horror_intensity": 1,          # 0 Gentle, 1 Standard, 2 Intense (data/horror_events.gd INTENSITY)
	"arachnophobia": false,         # replaces spider visuals/sounds/icons/names with a non-arachnid threat
	"reduce_shake": false,
	"reduce_flashing": false,
	"captions": true,               # show text captions for important sounds
	"comfort_confirmed": false,     # player has seen the comfort screen
	# Video
	"fullscreen": true,
	"vsync": true,
	"max_fps": 0,                   # 0 = unlimited (vsync still applies)
	"render_scale": 1.0,            # 0.5 .. 1.0
	"quality": 2,                   # 0 Low, 1 Medium, 2 High
	"show_fps": false,
	# Input (action -> serialised binding list), filled from DEFAULT_BINDINGS when empty
	"bindings": {},
}

## Default bindings. Each entry: "key:<physical keycode>" or "mouse:<button index>".
const DEFAULT_BINDINGS := {
	"move_forward": ["key:%d" % KEY_W, "key:%d" % KEY_UP],
	"move_back": ["key:%d" % KEY_S, "key:%d" % KEY_DOWN],
	"move_left": ["key:%d" % KEY_A, "key:%d" % KEY_LEFT],
	"move_right": ["key:%d" % KEY_D, "key:%d" % KEY_RIGHT],
	"jump": ["key:%d" % KEY_SPACE],
	"sprint": ["key:%d" % KEY_SHIFT],
	"dodge": ["key:%d" % KEY_CTRL, "key:%d" % KEY_V],
	"attack": ["mouse:%d" % MOUSE_BUTTON_LEFT],
	"use_item": ["mouse:%d" % MOUSE_BUTTON_RIGHT, "key:%d" % KEY_Q],
	"interact": ["key:%d" % KEY_E],
	"lantern": ["key:%d" % KEY_F],
	"inventory": ["key:%d" % KEY_TAB, "key:%d" % KEY_I],
	"craft": ["key:%d" % KEY_C],
	"build": ["key:%d" % KEY_B],
	"journal": ["key:%d" % KEY_J],
	"map": ["key:%d" % KEY_M],
	"companion_command": ["key:%d" % KEY_G],
	"pause": ["key:%d" % KEY_ESCAPE],
	"help": ["key:%d" % KEY_F1],
	"screenshot": ["key:%d" % KEY_F12],
	"build_rotate": ["key:%d" % KEY_R],
	"build_dismantle": ["key:%d" % KEY_X],
	"zoom_in": ["mouse:%d" % MOUSE_BUTTON_WHEEL_UP],
	"zoom_out": ["mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN],
	"hotbar_1": ["key:%d" % KEY_1], "hotbar_2": ["key:%d" % KEY_2], "hotbar_3": ["key:%d" % KEY_3], "hotbar_4": ["key:%d" % KEY_4],
	"hotbar_5": ["key:%d" % KEY_5], "hotbar_6": ["key:%d" % KEY_6], "hotbar_7": ["key:%d" % KEY_7], "hotbar_8": ["key:%d" % KEY_8],
}

## Actions shown in the rebinding UI, in order, with friendly names.
const REBINDABLE := [
	["move_forward", "Move Forward"], ["move_back", "Move Back"], ["move_left", "Move Left"], ["move_right", "Move Right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["dodge", "Dodge Roll"], ["attack", "Attack / Gather"], ["use_item", "Use / Eat Item"],
	["interact", "Interact"], ["lantern", "Lantern"], ["inventory", "Inventory"], ["craft", "Crafting"], ["build", "Build Mode"],
	["journal", "Journal"], ["map", "Map"], ["companion_command", "Companion: Follow / Wait"],
]

var values: Dictionary = {}


func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	load_settings()
	setup_input_map()
	apply_video.call_deferred()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	if key in ["fullscreen", "vsync", "max_fps", "render_scale"]:
		apply_video()
	Events.settings_changed.emit(key)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for key in DEFAULTS:
		if cf.has_section_key("settings", key):
			var v = cf.get_value("settings", key)
			if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and (v is int or v is float)):
				values[key] = float(v) if DEFAULTS[key] is float else v


func save() -> void:
	var cf := ConfigFile.new()
	for key in values:
		cf.set_value("settings", key, values[key])
	var err := cf.save(PATH)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


func reset_to_defaults(keep_bindings: bool = false) -> void:
	var b = values.get("bindings", {})
	values = DEFAULTS.duplicate(true)
	if keep_bindings:
		values["bindings"] = b
	setup_input_map()
	apply_video()
	for key in values:
		Events.settings_changed.emit(key)


# --- Video ------------------------------------------------------------------------

func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var args := OS.get_cmdline_args()
	var cli_windowed := args.has("--windowed") or args.has("-w") or args.has("--resolution") or OS.get_cmdline_user_args().has("--windowed")
	if not cli_windowed:
		var want_fs: bool = get_value("fullscreen")
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("max_fps"))
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(get_value("render_scale")), 0.5, 1.0)


# --- Input map ---------------------------------------------------------------------

func setup_input_map() -> void:
	var binds: Dictionary = values.get("bindings", {})
	for action in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var list: Array = binds.get(action, DEFAULT_BINDINGS[action])
		if list.is_empty():
			list = DEFAULT_BINDINGS[action]
		for b in list:
			var ev := _deserialize(String(b))
			if ev:
				InputMap.action_add_event(action, ev)


## Replaces the primary binding of `action` with `event` (secondary default kept for movement).
func rebind(action: String, event: InputEvent) -> void:
	var s := _serialize(event)
	if s == "":
		return
	var binds: Dictionary = values.get("bindings", {}).duplicate(true)
	var cur: Array = binds.get(action, DEFAULT_BINDINGS.get(action, [])).duplicate()
	if cur.is_empty():
		cur = [s]
	else:
		cur[0] = s
	binds[action] = cur
	values["bindings"] = binds
	setup_input_map()
	Events.settings_changed.emit("bindings")


func reset_bindings() -> void:
	values["bindings"] = {}
	setup_input_map()
	Events.settings_changed.emit("bindings")


## Human-readable label of the primary binding, e.g. "E", "Left Mouse", "Tab".
func action_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var evs := InputMap.action_get_events(action)
	if evs.is_empty():
		return "-"
	return event_label(evs[0])


func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		var local := DisplayServer.keyboard_get_keycode_from_physical(code) if DisplayServer.get_name() != "headless" else code
		return OS.get_keycode_string(local if local != 0 else code)
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			_: return "Mouse %d" % ev.button_index
	return ev.as_text()


func _serialize(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return "key:%d" % code
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


func _deserialize(s: String) -> InputEvent:
	var parts := s.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1])
		return k
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1])
		return m
	return null
