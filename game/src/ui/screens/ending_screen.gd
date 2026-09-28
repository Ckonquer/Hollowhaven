extends Control
## Chapter ending: "Chapter One Complete - The Dimming Ward", a short thank-you, a gentle credits
## scroll, then "Continue exploring your Haven". Skippable (any key / click) after a few seconds.
## play() is awaitable and returns when the player continues.

signal finished

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

const SKIPPABLE_AFTER := 4.0
const SCROLL_SECONDS := 30.0

var bg: ColorRect
var title_box: VBoxContainer
var thanks: Label
var credits_clip: Control
var credits: VBoxContainer
var final_box: VBoxContainer
var continue_btn: Button
var skip_l: Label
var _t := 0.0
var _phase := 0
var _done := false
var _tw: Dictionary = {}


func _ready() -> void:
	Kit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	bg = ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.11, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(bg))
	# Title
	title_box = Kit.vbox(6)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(title_box))
	title_box.offset_bottom = -120
	var t1 := Kit.label("Chapter One Complete", "Display", HORIZONTAL_ALIGNMENT_CENTER)
	t1.add_theme_font_size_override("font_size", 92)
	title_box.add_child(t1)
	var orn := Kit.hbox(18)
	orn.alignment = BoxContainer.ALIGNMENT_CENTER
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l1 := Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, Color("b5d977")), 48)
	l1.flip_h = true
	orn.add_child(l1)
	var t2 := Kit.label("The Dimming Ward", "HudTitle", HORIZONTAL_ALIGNMENT_CENTER)
	t2.add_theme_font_size_override("font_size", 46)
	t2.add_theme_color_override("font_color", Color("ffe2a0"))
	orn.add_child(t2)
	orn.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, Color("b5d977")), 48))
	title_box.add_child(orn)
	title_box.add_child(Kit.spacer(0, 40))
	thanks = Kit.wrap_label("The Ward Stone shines again. The Heartseed is home, and your friends are safe.\nSomething still stirs in the deep... but tonight, the lights are on.", "HudText", 1400, HORIZONTAL_ALIGNMENT_CENTER)
	thanks.add_theme_font_size_override("font_size", 30)
	thanks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thanks.modulate.a = 0.0
	title_box.add_child(thanks)
	title_box.modulate.a = 0.0
	# Credits
	credits_clip = Control.new()
	credits_clip.clip_contents = true
	credits_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(credits_clip))
	credits = build_credits(1100.0, true)
	credits_clip.add_child(credits)
	credits_clip.visible = false
	# Final
	final_box = Kit.vbox(26)
	final_box.alignment = BoxContainer.ALIGNMENT_CENTER
	final_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(final_box))
	var fl := Kit.label("Continue exploring your Haven", "Display", HORIZONTAL_ALIGNMENT_CENTER)
	fl.add_theme_font_size_override("font_size", 64)
	final_box.add_child(fl)
	var fs := Kit.label("Build, farm, decorate, and spend time with Mochi, Pebble and Lumi.", "HudText", HORIZONTAL_ALIGNMENT_CENTER)
	fs.add_theme_font_size_override("font_size", 28)
	final_box.add_child(fs)
	continue_btn = Kit.button("  Continue  ", _finish, "AccentButton")
	continue_btn.add_theme_font_size_override("font_size", 32)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	final_box.add_child(continue_btn)
	final_box.visible = false
	skip_l = Kit.label("Press any key to skip", "HudSmall", HORIZONTAL_ALIGNMENT_RIGHT)
	skip_l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip_l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skip_l.offset_right = -40
	skip_l.offset_bottom = -30
	skip_l.modulate.a = 0.0
	add_child(skip_l)


## Runs the whole sequence; returns when the player continues.
func play() -> void:
	Audio.play_music("music_ending", 2.0)
	var tw := Kit.retween(self, _tw, "main")
	tw.tween_property(bg, "color:a", 0.42, 1.2)
	tw.parallel().tween_property(title_box, "modulate:a", 1.0, 1.6).set_delay(0.4)
	tw.tween_interval(1.6)
	tw.tween_property(thanks, "modulate:a", 1.0, 1.2)
	tw.tween_interval(4.8)
	tw.tween_callback(_start_credits)
	await finished


func _start_credits() -> void:
	if _phase >= 2:
		return
	_phase = 2
	var tw := Kit.retween(self, _tw, "main")
	tw.tween_property(title_box, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(bg, "color:a", 0.86, 1.4)
	tw.tween_callback(func() -> void:
		title_box.visible = false
		credits_clip.visible = true
		credits.reset_size()
		credits.position = Vector2((size.x - credits.size.x) * 0.5, size.y + 20.0))
	tw.tween_method(func(y: float) -> void: credits.position.y = y, size.y + 20.0, -credits.get_combined_minimum_size().y - 40.0, SCROLL_SECONDS)
	tw.tween_callback(_show_final)


func _show_final() -> void:
	if _phase >= 3:
		return
	_phase = 3
	var tw := Kit.retween(self, _tw, "main")
	title_box.visible = false
	credits_clip.visible = false
	final_box.visible = true
	final_box.modulate.a = 0.0
	skip_l.visible = false
	tw.tween_property(bg, "color:a", 0.55, 1.0)
	tw.parallel().tween_property(final_box, "modulate:a", 1.0, 1.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(continue_btn):
			continue_btn.grab_focus())


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := Kit.retween(self, _tw, "main")
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _process(delta: float) -> void:
	_t += delta
	if _phase < 3 and _t > SKIPPABLE_AFTER and skip_l.modulate.a < 1.0:
		skip_l.modulate.a = minf(skip_l.modulate.a + delta * 2.0, 0.85)


func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed:
		return
	if _phase < 3 and _t > SKIPPABLE_AFTER:
		get_viewport().set_input_as_handled()
		_show_final()
	elif _phase < 3:
		get_viewport().set_input_as_handled()


## Credits content (also shown from the title screen). `on_dark` = cream text for dark backdrops.
static func build_credits(width: float = 1000.0, on_dark: bool = false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size.x = width
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := "HudTitle" if on_dark else "Heading"
	var body := "HudText" if on_dark else ""
	var small := "HudSmall" if on_dark else "Small"
	var lines: Array = [
		["display", "Hollowhaven"],
		["sub", "Chapter One: The Dimming Ward"],
		["gap", ""],
		["heart", "For Krystal"],
		["from", "from Ali"],
		["gap", ""],
		["h", "Friends"],
	]
	for id in ItemDB.creature_ids():
		var c := ItemDB.creature(id)
		lines.append(["b", "%s the %s" % [String(c.get("name", id)), String(c.get("species", ""))]])
	lines.append_array([
		["gap", ""],
		["h", "Built with"],
		["b", "Godot Engine (MIT)"],
		["b", "Fonts: Fredoka and Nunito (SIL OFL)"],
		["gap", ""],
		["s", "All art, music and sound are original and generated for this game."],
		["gap", ""],
		["h", "Thank you for playing"],
	])
	for ln in lines:
		var kind := String(ln[0])
		var text := String(ln[1])
		match kind:
			"gap":
				v.add_child(Kit.spacer(0, 34))
			"display":
				var l := Kit.label(text, "Display" if on_dark else "Title", HORIZONTAL_ALIGNMENT_CENTER)
				l.add_theme_font_size_override("font_size", 88 if on_dark else 76)
				if not on_dark:
					l.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.25))
				v.add_child(l)
			"sub":
				var l2 := Kit.label(text, head, HORIZONTAL_ALIGNMENT_CENTER)
				l2.add_theme_font_size_override("font_size", 36)
				if on_dark:
					l2.add_theme_color_override("font_color", Color("ffe2a0"))
				v.add_child(l2)
			"heart":
				var h := Kit.hbox(14)
				h.alignment = BoxContainer.ALIGNMENT_CENTER
				h.mouse_filter = Control.MOUSE_FILTER_IGNORE
				h.add_child(Kit.icon_rect(IconFactory.icon("ui_heart", Color("ff8fa8"), 64), 40))
				var l3 := Kit.label(text, head, HORIZONTAL_ALIGNMENT_CENTER)
				l3.add_theme_font_size_override("font_size", 46)
				h.add_child(l3)
				h.add_child(Kit.icon_rect(IconFactory.icon("ui_heart", Color("ff8fa8"), 64), 40))
				v.add_child(h)
			"from":
				# "from Ali" + a drawn heart (the fonts have no emoji glyphs, so the heart is an icon)
				var hf := Kit.hbox(10)
				hf.alignment = BoxContainer.ALIGNMENT_CENTER
				hf.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var lf := Kit.label(text, head, HORIZONTAL_ALIGNMENT_CENTER)
				lf.add_theme_font_size_override("font_size", 38)
				if on_dark:
					lf.add_theme_color_override("font_color", Color("ffe2a0"))
				hf.add_child(lf)
				hf.add_child(Kit.icon_rect(IconFactory.icon("ui_heart", Color("e4665c"), 64), 34))
				v.add_child(hf)
			"h":
				var l4 := Kit.label(text, head, HORIZONTAL_ALIGNMENT_CENTER)
				l4.add_theme_font_size_override("font_size", 34)
				if on_dark:
					l4.add_theme_color_override("font_color", Color("ffe2a0"))
				else:
					l4.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
				v.add_child(l4)
			"b":
				var l5 := Kit.label(text, body, HORIZONTAL_ALIGNMENT_CENTER)
				l5.add_theme_font_size_override("font_size", 28)
				v.add_child(l5)
			"s":
				var l6 := Kit.wrap_label(text, small, width * 0.8, HORIZONTAL_ALIGNMENT_CENTER)
				l6.add_theme_font_size_override("font_size", 24)
				l6.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				v.add_child(l6)
	return v
