extends RefCounted
## Describes every player-facing setting (tab, widget type, range, wording) and the pure logic that
## binds widgets to Settings: snapping, type coercion, value formatting. Used by the Settings panel
## and the Comfort screen so both explain options identically.

const HorrorData := preload("res://data/horror_events.gd")

const TABS := [["gameplay", "Gameplay"], ["controls", "Controls"], ["video", "Video"], ["audio", "Audio"], ["comfort", "Comfort"]]

const ROWS := [
	{"key": "mouse_sensitivity", "tab": "gameplay", "type": "slider", "label": "Mouse sensitivity", "desc": "How quickly the camera turns.", "min": 0.1, "max": 2.0, "step": 0.05, "fmt": "mult"},
	{"key": "invert_y", "tab": "gameplay", "type": "toggle", "label": "Invert camera up / down", "desc": "Push the mouse up to look down."},
	{"key": "fov", "tab": "gameplay", "type": "slider", "label": "Field of view", "desc": "Wider shows more of the world around Krystal.", "min": 55.0, "max": 95.0, "step": 1.0, "fmt": "deg"},
	{"key": "camera_distance", "tab": "gameplay", "type": "slider", "label": "Camera distance", "desc": "Default zoom. The mouse wheel adjusts it while playing.", "min": 2.5, "max": 8.0, "step": 0.1, "fmt": "m"},
	{"key": "show_hints", "tab": "gameplay", "type": "toggle", "label": "Show hints", "desc": "Friendly tips the first time you meet something new."},
	{"key": "companion_auto_attack", "tab": "gameplay", "type": "toggle", "label": "Friends join fights", "desc": "Your companion helps against enemies you're fighting. Their comfort and support work either way."},
	{"key": "companion_autocast", "tab": "gameplay", "type": "toggle", "label": "Friends use skills on their own", "desc": "Your companion uses their special skill by themselves when it helps. When off, they wait for you to ask."},
	{"key": "seasonal_decor", "tab": "gameplay", "type": "toggle", "label": "Seasonal decorations", "desc": "A few pumpkins and ribbons along the woodland paths. Never inside your home."},
	{"key": "fullscreen", "tab": "video", "type": "toggle", "label": "Fullscreen", "desc": "Play in a window or fill the screen."},
	{"key": "vsync", "tab": "video", "type": "toggle", "label": "V-Sync", "desc": "Smooth frames without tearing."},
	{"key": "max_fps", "tab": "video", "type": "option", "label": "Frame rate limit", "desc": "Cap the frame rate to keep your computer cool and quiet.", "options": [[0, "Unlimited"], [30, "30"], [60, "60"], [120, "120"], [144, "144"]]},
	{"key": "render_scale", "tab": "video", "type": "slider", "label": "Render scale", "desc": "Lower it if the game runs slowly. Text and menus stay sharp.", "min": 0.5, "max": 1.0, "step": 0.05, "fmt": "pct"},
	{"key": "quality", "tab": "video", "type": "option", "label": "Graphics quality", "desc": "Shadows, grass density and effects.", "options": [[0, "Low"], [1, "Medium"], [2, "High"]]},
	{"key": "show_fps", "tab": "video", "type": "toggle", "label": "Show FPS counter", "desc": "A small frame counter in the corner."},
	{"key": "master_volume", "tab": "audio", "type": "slider", "label": "Master volume", "desc": "", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct", "test_ui": "ui_notify"},
	{"key": "music_volume", "tab": "audio", "type": "slider", "label": "Music", "desc": "", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
	{"key": "ambience_volume", "tab": "audio", "type": "slider", "label": "Ambience", "desc": "Wind, birds, water and the sounds of deep places.", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct"},
	{"key": "sfx_volume", "tab": "audio", "type": "slider", "label": "Sound effects", "desc": "", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct", "test_sfx": "pickup"},
	{"key": "ui_volume", "tab": "audio", "type": "slider", "label": "Interface", "desc": "Menu clicks and chimes.", "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "pct", "test_ui": "ui_click"},
	{"key": "horror_intensity", "tab": "comfort", "type": "intensity", "label": "Horror intensity", "desc": "How frightening the deep places below the mine are. The surface is always cozy."},
	{"key": "arachnophobia", "tab": "comfort", "type": "toggle", "label": "Arachnophobia mode", "desc": "Replaces the spider-like Weaver with the Hollow Mother, a pale drifting shade with no legs. Webs become pale roots, silk becomes pale thread, and skittering sounds become soft drifting ones."},
	{"key": "reduce_shake", "tab": "comfort", "type": "toggle", "label": "Reduce camera shake", "desc": "Softens the camera shake from impacts and scares."},
	{"key": "reduce_flashing", "tab": "comfort", "type": "toggle", "label": "Reduce flashing", "desc": "Makes screen flashes faint and slow, and calms the low-health pulse."},
	{"key": "captions", "tab": "comfort", "type": "toggle", "label": "Captions", "desc": "Short text for important sounds, like [a faint whisper]."},
	{"key": "high_visibility_cues", "tab": "comfort", "type": "toggle", "label": "High-visibility cues", "desc": "Bolder outlines, markers and shapes on puzzle and boss cues, so nothing depends on colour alone."},
	{"key": "timing_assist", "tab": "comfort", "type": "toggle", "label": "Timing assist", "desc": "Longer warnings and roomier timing in puzzles and boss fights. Nothing is skipped or taken away."},
]

## The Comfort tab's toggles, in order (the horror intensity picker comes first). Every "comfort" toggle row
## above must be listed here, so each one the game honours can also be found in the menu.
const COMFORT_TOGGLES := ["arachnophobia", "reduce_shake", "reduce_flashing", "captions", "high_visibility_cues", "timing_assist"]


static func rows_for(tab: String) -> Array:
	var out: Array = []
	for r in ROWS:
		if String(r["tab"]) == tab:
			out.append(r)
	return out


static func row(key: String) -> Dictionary:
	for r in ROWS:
		if String(r["key"]) == key:
			return r
	return {}


## Clamps to the row's range and snaps to its step.
static func snap(r: Dictionary, v: float) -> float:
	var lo := float(r.get("min", 0.0))
	var hi := float(r.get("max", 1.0))
	var st := float(r.get("step", 0.0))
	var x := clampf(v, lo, hi)
	if st > 0.0:
		x = lo + roundf((x - lo) / st) * st
		x = clampf(x, lo, hi)
	return snappedf(x, 0.0001)


## Converts a widget value to the type Settings stores for `key` (bool / int / float).
static func coerce(key: String, v: Variant) -> Variant:
	var def: Variant = Settings.DEFAULTS.get(key)
	if def is bool:
		return bool(v)
	if def is int:
		return int(round(float(v)))
	if def is float:
		return float(v)
	return v


## Writes a value through Settings (snapped for sliders). Returns the stored value.
static func apply(key: String, v: Variant) -> Variant:
	var r := row(key)
	var val: Variant = v
	if String(r.get("type", "")) == "slider":
		val = snap(r, float(v))
	val = coerce(key, val)
	Settings.set_value(key, val)
	return val


static func format_value(r: Dictionary, v: float) -> String:
	match String(r.get("fmt", "")):
		"pct":
			return "%d%%" % int(round(v * 100.0))
		"deg":
			return "%d°" % int(round(v))
		"m":
			return "%.1f m" % v
		"mult":
			return "%.2f×" % v
	return str(v)


## Index of `value` in an option row (falls back to 0).
static func option_index(r: Dictionary, value: Variant) -> int:
	var opts: Array = r.get("options", [])
	for i in opts.size():
		if int(opts[i][0]) == int(value):
			return i
	return 0


## {name, desc} for a horror intensity level (0 Gentle, 1 Standard, 2 Intense).
static func intensity_info(level: int) -> Dictionary:
	var d: Dictionary = HorrorData.INTENSITY.get(clampi(level, 0, 2), {})
	return {"name": String(d.get("name", "Standard")), "desc": String(d.get("desc", ""))}
