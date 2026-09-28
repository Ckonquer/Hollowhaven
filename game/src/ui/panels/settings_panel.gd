extends "res://src/ui/panels/panel_base.gd"
## Settings: Gameplay (camera, hints, companion fighting / skills, seasonal decorations), Controls (rebinding
## with "press a key" capture, conflict warnings, reset), Video, Audio (with test sounds) and Comfort (horror
## intensity, arachnophobia, shake, flashing, captions, high-visibility cues, timing assist, each explained).
## Changes apply live; the owner saves Settings when the panel closes.
## args: {"tab": "controls"} opens a specific tab.

const Rows := preload("res://src/ui/widgets/setting_rows.gd")
const Schema := preload("res://src/ui/settings_schema.gd")

const ROW_W := 1200.0
## Settings "Reset to defaults" leaves alone: the key bindings (they have their own reset) and every
## comfort choice, which a player may depend on (e.g. arachnophobia mode, timing assist).
const RESET_KEEPS := ["bindings", "comfort_confirmed", "arachnophobia", "reduce_shake", "reduce_flashing", "captions", "horror_intensity",
	"high_visibility_cues", "timing_assist"]

var tabs: TabContainer
var _capturing := ""
var _capture_btn: Button = null
var _bind_rows: Dictionary = {}     # action -> {"btn", "alt", "warn"}
var _done_btn: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Settings"
	window_min = Vector2(1400, 0)


func _build() -> void:
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1320, 660)
	body.add_child(tabs)
	for t in Schema.TABS:
		var id := String(t[0])
		var sc := ScrollContainer.new()
		sc.name = String(t[1])
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(sc)
		var v := Kit.vbox(18)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mc := Kit.margin([8, 6, 22, 6])
		mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mc.add_child(v)
		sc.add_child(mc)
		match id:
			"controls":
				_build_controls(v)
			"comfort":
				_build_comfort(v)
			_:
				for r in Schema.rows_for(id):
					v.add_child(Rows.build(String(r["key"]), ROW_W))
					v.add_child(_thin_sep())
				if id == "gameplay" and GameState.active:
					var h := Kit.hbox(16)
					var b := Kit.button("Show tips again", _reset_hints)
					h.add_child(b)
					var l := Kit.wrap_label("Brings back every onboarding tip you've already seen.", "Small", 600)
					l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					h.add_child(l)
					v.add_child(h)
	var want := String(args.get("tab", ""))
	for i in Schema.TABS.size():
		if String(Schema.TABS[i][0]) == want:
			tabs.current_tab = i
	var bottom := Kit.hbox(16)
	body.add_child(bottom)
	bottom.add_child(Kit.button("Reset to defaults", _reset_defaults, "GhostButton"))
	bottom.add_child(Kit.expander())
	_done_btn = Kit.button("Done", request_close, "AccentButton")
	_done_btn.custom_minimum_size.x = 200
	bottom.add_child(_done_btn)


func _thin_sep() -> Control:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 2)
	s.modulate.a = 0.6
	return s


func _build_comfort(v: VBoxContainer) -> void:
	var r := Schema.row("horror_intensity")
	v.add_child(Kit.label(String(r["label"]), "Subheading"))
	v.add_child(Kit.wrap_label(String(r["desc"]), "Small", ROW_W))
	v.add_child(Rows.intensity_picker(ROW_W, 96.0))
	v.add_child(_thin_sep())
	for key in Schema.COMFORT_TOGGLES:
		v.add_child(Rows.build(String(key), ROW_W))
		v.add_child(_thin_sep())


func _build_controls(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 8)
	var intro := Kit.wrap_label("Click a key, then press the new key or mouse button. Esc or clicking elsewhere cancels.", "Small", ROW_W)
	v.add_child(intro)
	for pair in Settings.REBINDABLE:
		var action := String(pair[0])
		var h := Kit.hbox(18)
		h.custom_minimum_size.x = ROW_W
		var nl := Kit.label(String(pair[1]))
		nl.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		nl.custom_minimum_size.x = 380
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(nl)
		var btn := Kit.button("", _begin_capture.bind(action))
		btn.custom_minimum_size = Vector2(260, 48)
		btn.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		h.add_child(btn)
		var alt := Kit.label("", "Small")
		alt.custom_minimum_size.x = 170
		alt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(alt)
		var warn := Kit.label("", "WarnText")
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size.x = 300
		h.add_child(warn)
		v.add_child(h)
		_bind_rows[action] = {"btn": btn, "alt": alt, "warn": warn}
	var reset := Kit.button("Reset all keys", func() -> void:
		_cancel_capture()
		Settings.reset_bindings()
		_refresh_bindings())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(reset)
	_refresh_bindings()


func refresh() -> void:
	_refresh_bindings()


## Every action whose bindings are checked for conflicts (movement, menus, hotbar...).
static func all_actions() -> Array:
	return Settings.DEFAULT_BINDINGS.keys()


func _refresh_bindings() -> void:
	var names := {}
	for pair in Settings.REBINDABLE:
		names[String(pair[0])] = String(pair[1])
	for action in _bind_rows:
		var row: Dictionary = _bind_rows[action]
		var btn: Button = row["btn"]
		if action == _capturing:
			btn.text = "Press a key..."
		else:
			btn.text = Settings.action_label(action)
		var evs: Array = InputMap.action_get_events(action) if InputMap.has_action(action) else []
		var alt: Label = row["alt"]
		alt.text = ("or  " + Settings.event_label(evs[1])) if evs.size() > 1 else ""
		var warn: Label = row["warn"]
		var codes := UiUtil.action_codes(action)
		var clashes: Array = []
		if not codes.is_empty():
			clashes = UiUtil.find_conflicts(action, String(codes[0]), all_actions(), Callable(UiUtil, "action_codes"))
		if clashes.is_empty():
			warn.text = ""
		else:
			var nice: Array = []
			for c in clashes:
				nice.append(String(names.get(c, String(c).replace("_", " ").capitalize())))
			warn.text = "Also used by: " + ", ".join(PackedStringArray(nice))


func _begin_capture(action: String) -> void:
	_cancel_capture()
	_capturing = action
	_capture_btn = _bind_rows[action]["btn"]
	_capture_btn.text = "Press a key..."
	_capture_btn.theme_type_variation = "AccentButton"


func _cancel_capture() -> void:
	if _capture_btn != null and is_instance_valid(_capture_btn):
		_capture_btn.theme_type_variation = ""
	_capturing = ""
	_capture_btn = null
	_refresh_bindings()


func is_capturing_input() -> bool:
	return _capturing != ""


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		get_viewport().set_input_as_handled()
		var k: InputEventKey = event
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		if code == KEY_ESCAPE:
			_cancel_capture()
			Audio.play_ui("ui_close")
			return
		_apply_capture(event)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return   # never a binding: let the Controls list scroll
		if mb.button_index == MOUSE_BUTTON_LEFT and not _click_on_capture_button(mb):
			# Clicking elsewhere (Done, a tab, another row) backs out and the click goes through.
			_cancel_capture()
			return
		get_viewport().set_input_as_handled()
		_apply_capture(event)


## True if the mouse event is over the box that shows "Press a key..." (a left click there binds Left Mouse).
func _click_on_capture_button(mb: InputEventMouseButton) -> bool:
	if _capture_btn == null or not is_instance_valid(_capture_btn) or not _capture_btn.is_inside_tree():
		return false
	var local: InputEventMouseButton = _capture_btn.make_input_local(mb)
	return Rect2(Vector2.ZERO, _capture_btn.size).has_point(local.position)


func _apply_capture(event: InputEvent) -> void:
	if not UiUtil.is_bindable(event):
		return
	var action := _capturing
	Settings.rebind(action, event)
	Audio.play_ui("ui_click")
	_cancel_capture()
	var row: Dictionary = _bind_rows.get(action, {})
	if not row.is_empty():
		(row["btn"] as Button).grab_focus()


func _reset_hints() -> void:
	for k in GameState.flags.keys():
		if String(k).begins_with("hint_"):
			GameState.flags.erase(k)
	Audio.play_ui("ui_notify")


func _reset_defaults() -> void:
	if ui_root != null and ui_root.has_method("confirm"):
		var choice: String = await ui_root.confirm("Reset settings?", "Put every setting back to how it started? Your key bindings and comfort options stay as they are.",
			[["reset", "Reset", "AccentButton"], ["cancel", "Cancel", ""]])
		if choice != "reset":
			return
	# Key by key through set_value: only settings that actually change are announced (no needless live
	# rebuilds), and the bindings and comfort choices (arachnophobia, shake, flashing...) are never touched.
	for key in Settings.DEFAULTS:
		if RESET_KEEPS.has(String(key)):
			continue
		Settings.set_value(String(key), Settings.DEFAULTS[key])
	_refresh_bindings()


func default_focus() -> Control:
	return _done_btn


func on_close() -> void:
	_cancel_capture()
