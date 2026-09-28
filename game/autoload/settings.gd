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
	"high_visibility_cues": false,  # extra-bold outlines/markers on puzzle & boss cues (never colour alone)
	"timing_assist": false,         # removes tight timing windows from puzzles and boss mechanics
	# Companions (Chapter Two)
	"companion_auto_attack": true,  # the follower attacks enemies Krystal fights (support always works)
	"companion_autocast": true,     # the follower uses its signature skill by itself when it helps
	# World
	"seasonal_decor": false,        # optional autumn touches along Hollowhaven Woods paths (never in the house)
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
	"companion_skill": ["key:%d" % KEY_T],
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
	["journal", "Journal"], ["map", "Map"], ["companion_command", "Companion: Follow / Wait"], ["companion_skill", "Companion Skill"],
]

## Valid ranges of numeric settings; set_value() and load_settings() clamp into them.
const RANGES := {
	"mouse_sensitivity": [0.1, 2.0], "fov": [55.0, 95.0], "camera_distance": [2.5, 8.0],
	"master_volume": [0.0, 1.0], "music_volume": [0.0, 1.0], "ambience_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0], "ui_volume": [0.0, 1.0],
	"horror_intensity": [0, 2], "max_fps": [0, 1000], "render_scale": [0.5, 1.0], "quality": [0, 2],
}

var values: Dictionary = {}


func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	var first_run := not FileAccess.file_exists(PATH)
	load_settings()
	if first_run:
		auto_quality.call_deferred()
	setup_input_map()
	apply_video.call_deferred()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


## Sets a value. Known keys are coerced to their default's type (a slider's 1.0 becomes the int 1 for
## "horror_intensity", 1 becomes 1.0 for "fov", ...) and clamped to RANGES; incompatible values are
## rejected with a warning so the settings never hold a wrong type.
func set_value(key: String, value: Variant) -> void:
	var v: Variant = coerce_value(key, value)
	if v == null:
		push_warning("Settings: rejected value %s for '%s'" % [str(value), key])
		return
	var cur: Variant = values.get(key)
	if values.has(key) and typeof(cur) == typeof(v) and cur == v:
		return
	values[key] = v
	if key == "bindings":
		setup_input_map()
	if key in ["fullscreen", "vsync", "max_fps", "render_scale"]:
		apply_video()
	Events.settings_changed.emit(key)


## Converts `value` to the type of DEFAULTS[key] (clamped to RANGES). Returns null when the value
## cannot represent that setting. Unknown keys pass through unchanged.
func coerce_value(key: String, value: Variant) -> Variant:
	if not DEFAULTS.has(key):
		return value
	var def: Variant = DEFAULTS[key]
	var out: Variant = null
	match typeof(def):
		TYPE_BOOL:
			if value is bool:
				out = value
			elif value is int or value is float:
				out = (value != 0)
			elif value is String:
				var s := String(value).strip_edges().to_lower()
				if s in ["true", "1", "on", "yes"]:
					out = true
				elif s in ["false", "0", "off", "no"]:
					out = false
		TYPE_INT:
			if value is int:
				out = value
			elif value is float and is_finite(value):
				out = roundi(value)
			elif value is bool:
				out = 1 if value else 0
			elif value is String and String(value).strip_edges().is_valid_int():
				out = String(value).strip_edges().to_int()
			if out != null and RANGES.has(key):
				out = clampi(int(out), int(RANGES[key][0]), int(RANGES[key][1]))
		TYPE_FLOAT:
			if value is int or value is float:
				out = float(value)
			elif value is String and String(value).strip_edges().is_valid_float():
				out = String(value).strip_edges().to_float()
			if out != null and not is_finite(float(out)):
				out = null
			if out != null and RANGES.has(key):
				out = clampf(float(out), float(RANGES[key][0]), float(RANGES[key][1]))
		TYPE_DICTIONARY:
			if value is Dictionary:
				out = sanitize_bindings(value) if key == "bindings" else value.duplicate(true)
	return out


## Keeps only known actions whose binding lists hold valid "key:<code>" / "mouse:<button>" strings.
func sanitize_bindings(b: Dictionary) -> Dictionary:
	var out := {}
	for action in b:
		if not (action is String or action is StringName) or not DEFAULT_BINDINGS.has(String(action)):
			continue
		var list: Variant = b[action]
		if not (list is Array or list is PackedStringArray):
			continue
		var clean: Array = []
		for e in list:
			if (e is String or e is StringName) and _deserialize(String(e)) != null and not clean.has(String(e)):
				clean.append(String(e))
		if not clean.is_empty():
			out[String(action)] = clean
	return out


## Loads persisted settings (the default path is the player's settings file; tests pass a temp path).
## Values are coerced/clamped like set_value(); unknown keys and invalid values are ignored.
## Call setup_input_map() afterwards if the bindings should take effect immediately.
func load_settings(path: String = PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for key in DEFAULTS:
		if cf.has_section_key("settings", key):
			var v: Variant = coerce_value(key, cf.get_value("settings", key))
			if v != null:
				values[key] = v


func save(path: String = PATH) -> void:
	var cf := ConfigFile.new()
	for key in values:
		cf.set_value("settings", key, values[key])
	var err := cf.save(path)
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
	# The engine window starts fullscreen (project.godot display/window/size/mode, matching the default
	# setting), so a windowed choice (setting off, or a debug/QA run with "-- --windowed") has to leave
	# fullscreen here. A maximized/minimized window counts as windowed and is left alone.
	var cur := DisplayServer.window_get_mode()
	var is_fs := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var want_fs: bool = bool(get_value("fullscreen")) and not cli_windowed
	if want_fs and not is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want_fs and is_fs:
		_enter_windowed()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("max_fps"))
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(get_value("render_scale")), 0.5, 1.0)


## Leaves fullscreen for a centred window of the project's window size (1600x900, shrunk to 90% of
## small screens so the title bar stays reachable). Needed because a window that was created
## fullscreen has no sensible size to restore to.
func _enter_windowed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var want := Vector2i(int(ProjectSettings.get_setting("display/window/size/window_width_override", 1600)),
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 900)))
	if want.x <= 0 or want.y <= 0:
		want = Vector2i(1600, 900)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x > 0 and usable.size.y > 0:
		want = Vector2i(mini(want.x, int(usable.size.x * 0.9)), mini(want.y, int(usable.size.y * 0.9)))
	DisplayServer.window_set_size(want)
	if usable.size.x > 0 and usable.size.y > 0:
		DisplayServer.window_set_position(usable.position + (usable.size - want) / 2)


## First launch only (no settings file yet): lighter defaults on integrated / software GPUs so a laptop
## starts smooth. Later launches keep whatever is saved; the player can change both in Settings > Video.
## Returns the preset chosen ("high" keeps the defaults).
func auto_quality(device_type: int = -1) -> String:
	if device_type < 0:
		if DisplayServer.get_name() == "headless":
			return "high"
		device_type = int(RenderingServer.get_video_adapter_type())
	var preset := "high"
	match device_type:
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			preset = "medium"
		RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			preset = "low"
	if preset == "medium":
		set_value("quality", 1)
		set_value("render_scale", 0.85)
	elif preset == "low":
		set_value("quality", 0)
		set_value("render_scale", 0.7)
	return preset


# --- Input map ---------------------------------------------------------------------

func setup_input_map() -> void:
	var raw_binds: Variant = values.get("bindings", {})
	var binds: Dictionary = raw_binds if raw_binds is Dictionary else {}
	for action in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var raw: Variant = binds.get(action, [])
		var list: Array = raw if raw is Array else []
		if list.is_empty():
			list = DEFAULT_BINDINGS[action]
		for b in list:
			var ev := _deserialize(str(b))
			if ev:
				InputMap.action_add_event(action, ev)


## Replaces the primary binding of `action` with `event` (secondary default kept for movement).
## If the new input was one of the action's secondary bindings it is not listed twice.
func rebind(action: String, event: InputEvent) -> void:
	if not DEFAULT_BINDINGS.has(action):
		push_warning("Settings: cannot rebind unknown action '%s'" % action)
		return
	var s := _serialize(event)
	if s == "":
		return
	var raw_binds: Variant = values.get("bindings", {})
	var binds: Dictionary = raw_binds.duplicate(true) if raw_binds is Dictionary else {}
	var existing: Variant = binds.get(action, DEFAULT_BINDINGS[action])
	var cur: Array = existing.duplicate() if existing is Array else []
	if cur.is_empty():
		cur = [s]
	else:
		cur[0] = s
	for i in range(cur.size() - 1, 0, -1):
		if str(cur[i]) == s:
			cur.remove_at(i)
	binds[action] = cur
	values["bindings"] = binds
	setup_input_map()
	Events.settings_changed.emit("bindings")


## Actions (from DEFAULT_BINDINGS) currently bound to the same key/button as `event`, e.g. to warn
## about conflicts in the rebinding UI.
func actions_using(event: InputEvent) -> Array:
	var s := _serialize(event)
	var out := []
	if s == "":
		return out
	var raw_binds: Variant = values.get("bindings", {})
	var binds: Dictionary = raw_binds if raw_binds is Dictionary else {}
	for action in DEFAULT_BINDINGS:
		var raw: Variant = binds.get(action, [])
		var list: Array = raw if (raw is Array and not raw.is_empty()) else DEFAULT_BINDINGS[action]
		for b in list:
			if str(b) == s:
				out.append(action)
				break
	return out


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
	if parts.size() != 2 or not parts[1].is_valid_int() or parts[1].to_int() <= 0:
		return null
	if parts[0] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = parts[1].to_int() as Key
		return k
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = parts[1].to_int() as MouseButton
		return m
	return null
