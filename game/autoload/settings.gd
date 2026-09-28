extends Node
## Player settings (persisted to user://settings.cfg) and the input map (rebindable).
## Read: Settings.get_value("mouse_sensitivity")   Write: Settings.set_value("fov", 75.0)
## Every change emits Events.settings_changed(key). Call save() to persist (UI does this on close).
## QA runs may pass the user arg --settings-file=<abs path>: that file is read AND written instead, so an automated
## session never touches the player's real settings (settings_path).

const PATH := "user://settings.cfg"
## Used when --settings-file is given but is not an absolute path: still never the player's real file.
const QA_FALLBACK_PATH := "user://settings_qa.cfg"

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
	# Chapter Two build-mode keys (build_mode.gd prefers these actions over its FALLBACK_KEYS, same keys).
	"build_undo": ["key:%d" % KEY_Z],
	"build_recolor": ["key:%d" % KEY_P],
	"build_variant": ["key:%d" % KEY_N],
	# Chapter Two wardrobe (ui_root HOTKEYS; O is free: not Q/E, which switch wardrobe categories).
	"wardrobe": ["key:%d" % KEY_O],
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
	["build_undo", "Build: Undo last piece"], ["build_recolor", "Build: Recolour"], ["build_variant", "Build: Pumpkin face"],
	["journal", "Journal"], ["map", "Map"], ["wardrobe", "Wardrobe"], ["companion_command", "Companion: Follow / Wait"],
	["companion_skill", "Companion Skill"],
]

## Valid ranges of numeric settings; set_value() and load_settings() clamp into them.
const RANGES := {
	"mouse_sensitivity": [0.1, 2.0], "fov": [55.0, 95.0], "camera_distance": [2.5, 8.0],
	"master_volume": [0.0, 1.0], "music_volume": [0.0, 1.0], "ambience_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0], "ui_volume": [0.0, 1.0],
	"horror_intensity": [0, 2], "max_fps": [0, 1000], "render_scale": [0.5, 1.0], "quality": [0, 2],
}

var values: Dictionary = {}
## The file load_settings()/save() use by default: PATH, or the --settings-file override.
var settings_path: String = PATH


func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	settings_path = settings_path_from_args(OS.get_cmdline_user_args())
	var first_run := not FileAccess.file_exists(settings_path)
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


## Settings file named by the command-line user arg --settings-file=<abs path> (read and written instead of
## user://settings.cfg); PATH when the arg is absent, QA_FALLBACK_PATH when it is not an absolute path.
static func settings_path_from_args(user_args: PackedStringArray) -> String:
	for a in user_args:
		var s := String(a)
		if not s.begins_with("--settings-file="):
			continue
		var p := s.substr("--settings-file=".length()).strip_edges()
		if p != "" and p.is_absolute_path():
			return p
		push_warning("Settings: --settings-file needs an absolute path ('%s'); using %s" % [p, QA_FALLBACK_PATH])
		return QA_FALLBACK_PATH
	return PATH


## Loads persisted settings (default: settings_path, i.e. the player's settings file unless --settings-file was
## given; tests pass a temp path). Values are coerced/clamped like set_value(); unknown keys and invalid values are
## ignored. Call setup_input_map() afterwards if the bindings should take effect immediately.
func load_settings(path: String = "") -> void:
	if path == "":
		path = settings_path
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for key in DEFAULTS:
		if cf.has_section_key("settings", key):
			var v: Variant = coerce_value(key, cf.get_value("settings", key))
			if v != null:
				values[key] = v


## Writes the settings to `path` (default: settings_path).
func save(path: String = "") -> void:
	if path == "":
		path = settings_path
	if path != PATH:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
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
	var user_args := OS.get_cmdline_user_args()
	# QA second-monitor runs (--qa-window / --qa-screen / --qa-no-focus) are never fullscreen.
	var qa_rect := qa_window_rect(user_args)
	var qa_placed := qa_rect.size.x > 0 and qa_rect.size.y > 0
	var qa_windowed := qa_placed or user_args.has("--qa-no-focus")
	var cli_windowed := args.has("--windowed") or args.has("-w") or args.has("--resolution") or user_args.has("--windowed") or qa_windowed
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
	elif qa_placed:
		_place_qa_window(qa_rect)      # already windowed (e.g. a QA launcher created it so): only move it
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("max_fps"))
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(get_value("render_scale")), 0.5, 1.0)


## Leaves fullscreen for a centred window of the project's window size (1600x900, shrunk to 90% of
## small screens so the title bar stays reachable). Needed because a window that was created
## fullscreen has no sensible size to restore to.
func _enter_windowed() -> void:
	var qa_rect := qa_window_rect(OS.get_cmdline_user_args())
	if qa_rect.size.x > 0 and qa_rect.size.y > 0:
		if OS.get_cmdline_user_args().has("--qa-no-focus"):
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_place_qa_window(qa_rect)
		return
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


## QA window rect from the user args --qa-window=<x>,<y>,<w>,<h> (DisplayServer desktop coordinates; with the
## primary monitor at 0,0 they equal Windows' own, e.g. 1920,0,1920,1080 = a second 1080p monitor to the right)
## or --qa-screen=<n> (that whole screen). --qa-window wins. Empty Rect2i when neither is given or valid.
func qa_window_rect(user_args: PackedStringArray) -> Rect2i:
	var screen := -1
	for a in user_args:
		var s := String(a)
		if s.begins_with("--qa-window="):
			var p := s.substr("--qa-window=".length()).split(",")
			var ok := p.size() == 4
			for part in p:
				ok = ok and String(part).strip_edges().is_valid_int()
			if ok and p[2].strip_edges().to_int() >= 64 and p[3].strip_edges().to_int() >= 64:
				return Rect2i(p[0].strip_edges().to_int(), p[1].strip_edges().to_int(), p[2].strip_edges().to_int(),
					p[3].strip_edges().to_int())
			push_warning("Settings: ignoring %s (expected --qa-window=<x>,<y>,<w>,<h>, size >= 64)" % s)
		elif s.begins_with("--qa-screen="):
			var n := s.substr("--qa-screen=".length()).strip_edges()
			if n.is_valid_int() and n.to_int() >= 0 and n.to_int() < DisplayServer.get_screen_count():
				screen = n.to_int()
			else:
				push_warning("Settings: ignoring %s (%d screen(s))" % [s, DisplayServer.get_screen_count()])
	if screen >= 0:
		var size := DisplayServer.screen_get_size(screen)
		if size.x >= 64 and size.y >= 64:
			return Rect2i(DisplayServer.screen_get_position(screen), size)
	return Rect2i()


## QA runs: a borderless window exactly on `rect` (never fullscreen, so never exclusive). With --qa-no-focus it is
## made non-activating first, so neither the style change nor the move takes focus from the owner's window.
func _place_qa_window(rect: Rect2i) -> void:
	if OS.get_cmdline_user_args().has("--qa-no-focus"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	if DisplayServer.window_get_position() != rect.position:
		DisplayServer.window_set_position(rect.position)
	if DisplayServer.window_get_size() != rect.size:
		DisplayServer.window_set_size(rect.size)
	if DisplayServer.window_get_position() != rect.position:
		DisplayServer.window_set_position(rect.position)


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

## Installs every DEFAULT_BINDINGS action. An action with no saved binding (e.g. a settings file from before the
## wardrobe / Chapter Two build actions existed) gets its default keys; nothing is written back to the file.
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
