extends Control
## Chapter ending: "Chapter One Complete - The Dimming Ward", a short thank-you, a gentle credits
## scroll, then "Continue exploring your Haven". Skippable (any key / click) after a few seconds.
## play() is awaitable and returns when the player continues.
## Chapter Two variant (setup({"variant": "chapter_two"}), module C9; MP §17): "Chapter Two Complete - The
## Lanterns of Hallowmere" with autumn ornaments, the Chapter Two ending card (MP §17, verbatim), the credits
## (still "For Krystal" / "from Ali" with the hearts, plus the Chapter Two line), then "Chapter Two Complete"
## with what the Lanternwake left at home, and Continue = free play in the same save. The Chapter Two variant
## asks for no music: the music director plays Every Road Leads Home (m27) on Events.chapter2_completed.
## The default variant ("chapter_one") is exactly the Chapter One ending it always was.
## Visual QA (UI-09, UI-15): the Chapter Two card reads over the bright, busy Haven - a deeper warm dim from the start
## (CH2_DIM_TITLE / CH2_DIM_FINAL) and the ending paragraph in bold cream with a thicker outline at a narrower
## measure - and its closing card says "Chapter Two Complete" like the opening one. The UI root holds toasts and
## banners while any ending shows.

signal finished

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

const SKIPPABLE_AFTER := 4.0
const SCROLL_SECONDS := 30.0

const VARIANT_ONE := "chapter_one"
const VARIANT_TWO := "chapter_two"
## MP §17 "Chapter Two ending card" (verbatim; Game.CH2_ENDING_TEXT is the same line).
const CH2_ENDING_CARD := "The lanterns shine beyond the trees. The quiet below is quiet again. There are pumpkins to plant, walls to raise, and friends waiting by the fire. The road will keep. Tonight is yours."
const CH2_TITLE := "Chapter Two Complete"
const CH2_SUBTITLE := "The Lanterns of Hallowmere"
const CH2_FINAL := "Chapter Two Complete"
const CH2_FINAL_SUB := "The lanterns stay lit. Build, grow, dress up and wander both woods with your friends."
const CH2_CONTINUE := "  Continue exploring  "
const CH2_RECAP_PREFIX := "Waiting for you: "
const STORY_SCRIPT := "res://src/world/story_ch2/story_ch2.gd"
const AUTUMN_LEAF := Color("e9a15b")
const CH1_DIM_TITLE := 0.42         # Chapter One: unchanged
const CH1_DIM_FINAL := 0.55
const CH2_DIM_TITLE := 0.6          # Chapter Two: its card is a whole paragraph over the daytime Haven
const CH2_DIM_FINAL := 0.64
const CH2_CARD_W := 1180.0
const CH2_CARD_OUTLINE := 9
const CH2_SHADE_ALPHA := 0.5

var variant: String = VARIANT_ONE
var recap: Array = []            # chapter two: what the Lanternwake left at home (from story_ch2 when not given)
var bg: ColorRect
var card_shade: TextureRect = null    # Chapter Two: a warm dark vignette under the card text (follows title_box)
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


## Optional, before add_child: {"variant": "chapter_one" | "chapter_two", "recap": [String, ...]}.
func setup(params: Dictionary) -> void:
	variant = VARIANT_TWO if String(params.get("variant", VARIANT_ONE)) == VARIANT_TWO else VARIANT_ONE
	var r: Variant = params.get("recap", null)
	if r is Array:
		recap = (r as Array).duplicate()


func is_chapter_two() -> bool:
	return variant == VARIANT_TWO


func _ready() -> void:
	var two := is_chapter_two()
	if two and recap.is_empty():
		recap = _story_recap()
	Kit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	bg = ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.11, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(bg))
	if two:
		card_shade = _make_card_shade()
		add_child(card_shade)
	# Title
	title_box = Kit.vbox(6)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(title_box))
	title_box.offset_bottom = -120
	var t1 := Kit.label(CH2_TITLE if two else "Chapter One Complete", "Display", HORIZONTAL_ALIGNMENT_CENTER)
	t1.add_theme_font_size_override("font_size", 92)
	title_box.add_child(t1)
	var orn := Kit.hbox(18)
	orn.alignment = BoxContainer.ALIGNMENT_CENTER
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var leaf_col := AUTUMN_LEAF if two else Color("b5d977")
	var l1 := Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, leaf_col), 48)
	l1.flip_h = true
	orn.add_child(l1)
	if two:
		orn.add_child(Kit.icon_rect(IconFactory.item_icon("pumpkin_lantern", 64), 44))
	var t2 := Kit.label(CH2_SUBTITLE if two else "The Dimming Ward", "HudTitle", HORIZONTAL_ALIGNMENT_CENTER)
	t2.add_theme_font_size_override("font_size", 46)
	t2.add_theme_color_override("font_color", Color("ffe2a0"))
	orn.add_child(t2)
	if two:
		orn.add_child(Kit.icon_rect(IconFactory.item_icon("pumpkin_lantern", 64), 44))
	orn.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, leaf_col), 48))
	title_box.add_child(orn)
	title_box.add_child(Kit.spacer(0, 40))
	var thanks_text := CH2_ENDING_CARD if two else "The Ward Stone shines again. The Heartseed is home, and your friends are safe.\nSomething still stirs in the deep... but tonight, the lights are on."
	thanks = Kit.wrap_label(thanks_text, "HudText", CH2_CARD_W if two else 1400.0, HORIZONTAL_ALIGNMENT_CENTER)
	thanks.add_theme_font_size_override("font_size", 30)
	if two:
		thanks.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		thanks.add_theme_constant_override("outline_size", CH2_CARD_OUTLINE)
		thanks.add_theme_color_override("font_outline_color", Color(ThemeFactory.INK, 0.95))
		thanks.add_theme_constant_override("line_spacing", 6)
	thanks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thanks.modulate.a = 0.0
	title_box.add_child(thanks)
	title_box.modulate.a = 0.0
	# Credits
	credits_clip = Control.new()
	credits_clip.clip_contents = true
	credits_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(credits_clip))
	credits = build_credits(1100.0, true, 2 if two else 1)
	credits_clip.add_child(credits)
	credits_clip.visible = false
	# Final
	final_box = Kit.vbox(26)
	final_box.alignment = BoxContainer.ALIGNMENT_CENTER
	final_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(final_box))
	var fl := Kit.label(CH2_FINAL if two else "Continue exploring your Haven", "Display", HORIZONTAL_ALIGNMENT_CENTER)
	fl.add_theme_font_size_override("font_size", 64)
	final_box.add_child(fl)
	var fs := Kit.label(CH2_FINAL_SUB if two else "Build, farm, decorate, and spend time with Mochi, Pebble and Lumi.", "HudText", HORIZONTAL_ALIGNMENT_CENTER)
	fs.add_theme_font_size_override("font_size", 28)
	if two:
		fs.add_theme_font_override("font", ThemeFactory.font("body_bold"))
		fs.add_theme_constant_override("outline_size", CH2_CARD_OUTLINE)
		fs.add_theme_color_override("font_outline_color", Color(ThemeFactory.INK, 0.95))
	final_box.add_child(fs)
	if two and not recap.is_empty():
		var rl := Kit.wrap_label(recap_text(recap), "HudSmall", 1200, HORIZONTAL_ALIGNMENT_CENTER)
		rl.name = "Recap"
		rl.add_theme_font_size_override("font_size", 24)
		rl.add_theme_color_override("font_color", Color("ffe2a0"))
		rl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		final_box.add_child(rl)
	continue_btn = Kit.button(CH2_CONTINUE if two else "  Continue  ", _finish, "AccentButton")
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


## "Waiting for you: a, b and c." (a sentence from the recap list).
static func recap_text(items: Array) -> String:
	var parts: Array = []
	for it in items:
		if String(it) != "":
			parts.append(String(it))
	if parts.is_empty():
		return ""
	var body := String(parts[0])
	if parts.size() > 1:
		body = ", ".join(PackedStringArray(parts.slice(0, parts.size() - 1))) + " and " + String(parts[parts.size() - 1])
	return CH2_RECAP_PREFIX + body + "."


func _story_recap() -> Array:
	if not ResourceLoader.exists(STORY_SCRIPT):
		return []
	var s: Script = load(STORY_SCRIPT)
	if s == null or not s.can_instantiate():
		return []
	var r: Variant = s.call("feast_recap")
	return r if r is Array else []


## Runs the whole sequence; returns when the player continues.
func play() -> void:
	if not is_chapter_two():
		Audio.request_music("restoration", "music_ending", 2.0)     # no restart: the restoration already asked for m14
	var tw := Kit.retween(self, _tw, "main")
	tw.tween_property(bg, "color:a", CH2_DIM_TITLE if is_chapter_two() else CH1_DIM_TITLE, 1.2)
	tw.parallel().tween_property(title_box, "modulate:a", 1.0, 1.6).set_delay(0.4)
	tw.tween_interval(1.6)
	tw.tween_property(thanks, "modulate:a", 1.0, 1.2)
	tw.tween_interval(7.5 if is_chapter_two() else 4.8)      # the Chapter Two card is longer: time to read it
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
	tw.tween_property(bg, "color:a", CH2_DIM_FINAL if is_chapter_two() else CH1_DIM_FINAL, 1.0)
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


## A soft oval of warm dark behind the title and the ending paragraph (it fades with them).
static func _make_card_shade() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.05, 0.08, CH2_SHADE_ALPHA))
	g.set_color(1, Color(0.09, 0.05, 0.08, 0.0))
	g.add_point(0.62, Color(0.09, 0.05, 0.08, CH2_SHADE_ALPHA * 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.anchor_left = 0.08
	tr.anchor_right = 0.92
	tr.anchor_top = 0.2
	tr.anchor_bottom = 0.7
	tr.modulate.a = 0.0
	return tr


func _process(delta: float) -> void:
	if card_shade != null:
		var a := title_box.modulate.a if title_box.visible else 0.0
		if final_box.visible:
			a = maxf(a, final_box.modulate.a)
		card_shade.modulate.a = a
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
## `chapter` 2 adds the Chapter Two line under the Chapter One one; everything else (the dedication
## "For Krystal" with its hearts, "from Ali" with its heart, friends, tools, thanks) is the same.
static func build_credits(width: float = 1000.0, on_dark: bool = false, chapter: int = 1) -> VBoxContainer:
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
	]
	if chapter >= 2:
		lines.append(["sub", "Chapter Two: The Lanterns of Hallowmere"])
	lines.append_array([
		["gap", ""],
		["heart", "For Krystal"],
		["from", "from Ali"],
		["gap", ""],
		["h", "Friends"],
	])
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
