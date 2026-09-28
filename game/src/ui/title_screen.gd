extends Node
## Title screen: a cosy 3D clearing at dusk behind a storybook menu. "Hollowhaven" logo with a warm
## glow, the dedication "For Krystal", and Continue (shows day & goal from SaveSystem.peek(); hidden
## without a save) / New Game (overwrite warning) / Settings / Credits / Quit.
## New Game -> comfort screen -> Game.new_game().

const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const Kit := preload("res://src/ui/ui_kit.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Diorama := preload("res://src/ui/title/title_diorama.gd")
const ComfortScreen := preload("res://src/ui/screens/comfort_screen.gd")
const ConfirmDialog := preload("res://src/ui/screens/confirm_dialog.gd")
const SettingsPanel := preload("res://src/ui/panels/settings_panel.gd")
const CreditsPanel := preload("res://src/ui/panels/credits_panel.gd")

var diorama: Node3D
var canvas: CanvasLayer
var root: Control
var menu: VBoxContainer
var logo_box: VBoxContainer
var continue_btn: Button
var continue_sub: Label
var new_btn: Button
var msg_l: Label
var fade: ColorRect
var _panel: Control = null
var _busy := false
var _save_meta: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	diorama = Diorama.new()
	add_child(diorama)
	canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	root = Control.new()
	Kit.full_rect(root)
	root.theme = ThemeFactory.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	_build_backdrop_shade()
	_build_logo_and_menu()
	_build_footer()
	fade = ColorRect.new()
	fade.color = Color(0.07, 0.05, 0.08, 1.0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(Kit.full_rect(fade))
	_refresh_continue()
	Audio.play_music("music_title", 3.0)
	# gentle intro
	logo_box.modulate.a = 0.0
	menu.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(logo_box, "modulate:a", 1.0, 1.6).set_delay(0.5)
	tw.parallel().tween_property(menu, "modulate:a", 1.0, 1.0).set_delay(1.2)
	_focus_menu.call_deferred()
	if Debug.is_cheat_allowed() and Debug.has_arg("title-show"):
		_debug_show.call_deferred(Debug.arg("title-show"))


func _build_backdrop_shade() -> void:
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.1, 0.07, 0.12, 0.72))
	grad.set_color(1, Color(0.1, 0.07, 0.12, 0.0))
	grad.add_point(0.55, Color(0.1, 0.07, 0.12, 0.42))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0.0
	shade.anchor_right = 0.62
	shade.anchor_top = 0.0
	shade.anchor_bottom = 1.0
	root.add_child(shade)


func _build_logo_and_menu() -> void:
	var mc := Kit.margin([128, 96, 40, 90])
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(Kit.full_rect(mc))
	var col := Kit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(col)
	logo_box = Kit.vbox(0)
	logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(logo_box)
	var logo := Kit.label("Hollowhaven", "Display")
	logo.add_theme_font_size_override("font_size", 144)
	logo.add_theme_constant_override("outline_size", 18)
	logo.add_theme_color_override("font_outline_color", Color("3b2432"))
	logo.add_theme_color_override("font_shadow_color", Color(1.0, 0.78, 0.45, 0.4))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 0)
	logo.add_theme_constant_override("shadow_outline_size", 42)
	logo.add_theme_color_override("font_color", Color("fff1d6"))
	logo_box.add_child(logo)
	var ded := Kit.hbox(14)
	ded.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ded.alignment = BoxContainer.ALIGNMENT_CENTER
	var lf := Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, Color("b5d977")), 40)
	lf.flip_h = true
	ded.add_child(lf)
	var for_k := Kit.label("For Krystal", "HudTitle")
	for_k.add_theme_font_override("font", ThemeFactory.font("heading_light"))
	for_k.add_theme_font_size_override("font_size", 40)
	for_k.add_theme_color_override("font_color", Color("ffe2a0"))
	for_k.add_theme_constant_override("outline_size", 8)
	for_k.add_theme_color_override("font_outline_color", Color(0.23, 0.14, 0.2, 0.8))
	ded.add_child(for_k)
	ded.add_child(Kit.icon_rect(IconFactory.icon("ui_heart", Color("ff8fa8"), 48), 26))
	ded.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, Color("b5d977")), 40))
	logo_box.add_child(ded)
	col.add_child(Kit.spacer(0, 64))
	menu = Kit.vbox(6)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.custom_minimum_size.x = 520
	col.add_child(menu)
	continue_btn = _menu_button("Continue", _on_continue)
	continue_sub = Kit.label("", "HudSmall")
	continue_sub.add_theme_font_size_override("font_size", 25)
	continue_sub.add_theme_color_override("font_color", Color("ffe2a0"))
	var sub_m := Kit.margin([40, -8, 0, 8])
	sub_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_m.add_child(continue_sub)
	menu.add_child(sub_m)
	new_btn = _menu_button("New Game", _on_new_game)
	_menu_button("Settings", _on_settings)
	_menu_button("Credits", _on_credits)
	_menu_button("Quit", _on_quit)
	msg_l = Kit.label("", "HudSmall")
	msg_l.visible = false
	menu.add_child(msg_l)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Kit.button(text, cb, "TitleMenuButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_FILL
	b.focus_entered.connect(func() -> void: Audio.play_ui("ui_hover", -12.0))
	menu.add_child(b)
	return b


func _build_footer() -> void:
	var v := Kit.label("Chapter One  ·  The Dimming Ward  ·  v%s" % String(ProjectSettings.get_setting("application/config/version", "0.1")), "HudSmall", HORIZONTAL_ALIGNMENT_RIGHT)
	v.modulate.a = 0.75
	v.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.offset_right = -36
	v.offset_bottom = -26
	root.add_child(v)


## "Day 4  ·  A Timid Friend" from a save's metadata ("" if nothing to show). Pure; see tests.
static func continue_text(save_data: Dictionary) -> String:
	var meta: Dictionary = save_data.get("meta", {}) if save_data.get("meta", {}) is Dictionary else {}
	if meta.is_empty():
		return ""
	var parts: Array = []
	if meta.has("day"):
		parts.append("Day %d" % int(meta["day"]))
	# The saved step id is resolved now, so the title follows the arachnophobia option as it is set today;
	# the title text baked into the save is only a fallback (e.g. "Chapter complete", unknown steps).
	var st := String(meta.get("step_title", ""))
	var step_id := String(meta.get("step", ""))
	if step_id != "" and GameState.quests != null:
		var step: Dictionary = GameState.quests.step_by_id(step_id)
		if not step.is_empty():
			st = String(GameState.quests.step_string(step, "title"))
	if st != "":
		parts.append(st)
	var secs := float(meta.get("play_seconds", 0.0))
	if secs >= 60.0:
		var mins := int(secs / 60.0)
		parts.append("%dh %02dm played" % [mins / 60, mins % 60] if mins >= 60 else "%d min played" % mins)
	return "  ·  ".join(PackedStringArray(parts))


func _refresh_continue() -> void:
	_save_meta = SaveSystem.peek() if SaveSystem.has_save() else {}
	var has := not _save_meta.is_empty()
	continue_btn.visible = has
	continue_sub.get_parent().visible = has
	continue_sub.text = continue_text(_save_meta)


func _focus_menu() -> void:
	if _panel != null:
		return
	if continue_btn.visible:
		continue_btn.grab_focus()
	else:
		new_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _panel != null and event.is_action_pressed("pause"):
		if _panel.has_method("is_capturing_input") and _panel.is_capturing_input():
			return
		_close_panel()
		get_viewport().set_input_as_handled()


# --- Panels on the title ---------------------------------------------------------------------------

func _open_panel(p: Control) -> void:
	if _panel != null:
		_close_panel()
	_panel = p
	p.close_requested.connect(_close_panel)
	root.add_child(p)
	if "focus_behavior_recursive" in menu:
		menu.set("focus_behavior_recursive", 1)
	fade.move_to_front()
	Audio.play_ui("ui_open")


func _close_panel() -> void:
	if _panel == null:
		return
	var p := _panel
	_panel = null
	if "focus_behavior_recursive" in menu:
		menu.set("focus_behavior_recursive", 0)
	if p.has_method("on_close"):
		p.on_close()
	# Persist settings however the panel was closed (Esc skips the Done button's close_requested hook,
	# and closing the window never reaches Game.quit_game()).
	UiUtil.save_settings()
	_refresh_continue()   # the Continue line may read differently now (e.g. arachnophobia toggled)
	if p.has_method("animate_out_and_free"):
		p.animate_out_and_free()
	else:
		p.queue_free()
	Audio.play_ui("ui_close")
	_focus_menu.call_deferred()


func _confirm(title: String, text: String, buttons: Array) -> String:
	var d := ConfirmDialog.new()
	d.setup({"title": title, "text": text, "buttons": buttons})
	_open_panel(d)
	# A one-argument signal resumes `await` with that argument itself (not an Array).
	var res: Variant = await d.chosen
	if res is Array:
		return String(res[0]) if not (res as Array).is_empty() else "cancel"
	return String(res) if (res is String or res is StringName) else "cancel"


# --- Menu actions --------------------------------------------------------------------------------------

func _on_continue() -> void:
	if _busy:
		return
	if SaveSystem.peek().is_empty():
		_show_msg("We couldn't find a save to continue.")
		_refresh_continue()
		return
	_busy = true
	await _fade_to_black(0.9)
	Game.continue_game.call_deferred()
	# If loading fails, Game stays on the title: bring the menu back instead of leaving a black screen.
	# (A bound-method connection is dropped automatically when the title is freed by the scene change.)
	get_tree().create_timer(2.5).timeout.connect(_on_continue_timeout)


func _on_continue_timeout() -> void:
	if Game.mode != "title" or not is_inside_tree():
		return
	_busy = false
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.6)
	Audio.play_music("music_title", 1.5)
	_refresh_continue()
	_show_msg("Your save couldn't be loaded. %s" % SaveSystem.last_error)
	_focus_menu()


func _on_new_game() -> void:
	if _busy:
		return
	if SaveSystem.has_save():
		var choice := await _confirm("Start a new journey?", "Your current save will be replaced.",
			[["new", "Start fresh", "AccentButton"], ["cancel", "Keep my save", ""]])
		if choice != "new":
			return
	var c := ComfortScreen.new()
	c.setup({"first_time": true})
	_open_panel(c)
	await c.confirmed
	if not c.accepted:
		return   # closed with Esc / X: stay on the title
	_busy = true
	await _fade_to_black(1.1)
	Game.new_game.call_deferred()


func _on_settings() -> void:
	var p := SettingsPanel.new()
	p.setup({})
	p.close_requested.connect(func() -> void: UiUtil.save_settings())
	_open_panel(p)


func _on_credits() -> void:
	var p := CreditsPanel.new()
	p.setup({})
	_open_panel(p)


func _on_quit() -> void:
	if _busy:
		return
	Game.quit_game()


func _fade_to_black(t: float) -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, t)
	Audio.stop_music(t)
	await tw.finished


func _show_msg(text: String) -> void:
	msg_l.text = text
	msg_l.visible = true


## Debug/QA screenshots only.
func _debug_show(what: String) -> void:
	await get_tree().create_timer(1.6).timeout
	match what:
		"settings":
			_on_settings()
		"credits":
			_on_credits()
		"comfort":
			var c := ComfortScreen.new()
			c.setup({"first_time": true})
			_open_panel(c)
		"continue":
			_on_continue()
		"newgame":
			_on_new_game()
			await get_tree().create_timer(1.0).timeout
			if _panel != null:
				_panel.set("accepted", true)
				_panel.request_close()
		"confirm":
			_confirm("Start a new journey?", "Your current save will be replaced.", [["new", "Start fresh", "AccentButton"], ["cancel", "Keep my save", ""]])
