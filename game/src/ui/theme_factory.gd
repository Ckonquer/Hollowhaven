extends RefCounted
## Storybook UI theme, built entirely in code (no .tres). Parchment panels with soft shadows and a
## warm border, Fredoka for headings and buttons, Nunito for body text, warm ink colours from the
## palette, buttons with hover / pressed / keyboard-focus states, sliders, checkboxes, switches, tabs,
## scroll bars, popups and tooltips. Sizes are authored for the 1920x1080 canvas (the project uses
## canvas_items stretch, so everything scales cleanly from 1280x720 to 4K).
##   const ThemeFactory := preload("res://src/ui/theme_factory.gd")
##   root_control.theme = ThemeFactory.get_theme()
##   label.theme_type_variation = "Heading"
## Variations: Heading, Title, Display, Subheading, Small, Tiny, Muted, GoodText, BadText, WarnText,
##   HudText, HudTitle, HudSmall, RibbonTitle, KeyCapLabel (Label); AccentButton, GhostButton,
##   TitleMenuButton, RoundButton, TabLike (Button); Card, Inset, HudCard, HudDark, Pill, Ribbon,
##   KeyCap, SlotPanel (PanelContainer).
## Small windows (visual QA UI-22): canvas_items stretch shrinks everything by the window's height, so at 1280x720 the
## 21 px "Small" text lands near 13 px on screen. apply_window_scale(window height) - called by the UI root and the
## title screen, and again whenever the window is resized - steps the small print (Small, Tiny, HudSmall, GhostButton,
## tooltips) up by SMALL_BOOST px and darkens Small / Tiny a shade below SMALL_WINDOW_H; 1080p and up are unchanged.

const Palette := preload("res://src/art/palette.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")

const FREDOKA_PATH := "res://assets/fonts/Fredoka-Variable.ttf"
const NUNITO_PATH := "res://assets/fonts/Nunito-Variable.ttf"

# --- Colours ----------------------------------------------------------------------------------
const INK := Palette.UI_INK
const INK_SOFT := Palette.UI_INK_SOFT
const PAPER := Palette.UI_PAPER
const PAPER_DARK := Palette.UI_PAPER_DARK
const PAPER_LIGHT := Color("fffaf0")
const PAPER_MID := Color("f1e2c3")
const CREAM := Color("fff4e0")
const BORDER := Color("c9a47e")
const BORDER_DARK := Color("8e6a4f")
const ACCENT := Palette.UI_ACCENT
const GOOD := Palette.UI_GOOD
const WARN := Palette.UI_WARN
const BAD := Palette.UI_BAD
const GOLD := Color("f2c14e")
const TEAL := Palette.TEAL
const SHADOW := Color(0.14, 0.08, 0.1, 0.32)
const DIM := Color(0.12, 0.09, 0.13, 0.58)
const HUD_DARK := Color(0.17, 0.12, 0.16, 0.74)

# --- Font sizes (1920x1080 canvas) ---------------------------------------------------------------
const FS_TINY := 18
const FS_SMALL := 21
const FS_BODY := 24
const FS_LARGE := 28
const FS_H3 := 30
const FS_H2 := 40
const FS_H1 := 56
const FS_DISPLAY := 96
const FS_HUD_SMALL := 19
const SMALL_WINDOW_H := 800        # window height (px) below which the small print steps up
const SMALL_BOOST := 2             # px added to the small print there (on the 1920x1080 canvas)

const WEIGHTS := {"body": 600, "body_bold": 800, "body_light": 500, "heading": 600, "heading_bold": 700,
	"heading_light": 450, "display": 700}

static var _theme: Theme = null
static var _small_boost := false
static var _fonts: Dictionary = {}
static var _paper_mat: ShaderMaterial = null


## Shared theme instance (built once).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
		if _small_boost:
			_apply_small_print(_theme, true)
	return _theme


## Steps the small print up (window shorter than SMALL_WINDOW_H) or back to the authored sizes. Returns true when
## it changed anything. Safe to call often (idempotent); every themed control updates by itself.
static func apply_window_scale(window_h: float) -> bool:
	var want := window_h > 0.0 and window_h < float(SMALL_WINDOW_H)
	if want == _small_boost:
		return false
	_small_boost = want
	if _theme != null:
		_apply_small_print(_theme, want)
	return true


static func small_print_boosted() -> bool:
	return _small_boost


static func _apply_small_print(t: Theme, on: bool) -> void:
	var b := SMALL_BOOST if on else 0
	t.set_font_size(&"font_size", &"Small", FS_SMALL + b)
	t.set_color(&"font_color", &"Small", INK_SOFT.darkened(0.2) if on else INK_SOFT)
	t.set_font_size(&"font_size", &"Tiny", FS_TINY + b)
	t.set_color(&"font_color", &"Tiny", INK_SOFT.darkened(0.2) if on else INK_SOFT)
	t.set_font_size(&"font_size", &"HudSmall", FS_HUD_SMALL + b)
	t.set_font_size(&"font_size", &"GhostButton", FS_SMALL + b)
	t.set_font_size(&"font_size", &"TooltipLabel", FS_SMALL + b)


## Font by role: body, body_bold, body_light (Nunito); heading, heading_bold, heading_light, display (Fredoka).
static func font(kind: String = "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path := FREDOKA_PATH if (kind.begins_with("heading") or kind == "display") else NUNITO_PATH
	var fv := FontVariation.new()
	if ResourceLoader.exists(path):
		var base: Font = load(path)
		if base != null:
			fv.base_font = base
	fv.variation_opentype = {"wght": int(WEIGHTS.get(kind, 600))}
	_fonts[kind] = fv
	return fv


## Rounded flat style box. margins = [left, top, right, bottom] (or a single number for all sides).
static func box(bg: Color, radius: int = 16, border_w: int = 0, border_col: Color = Color.TRANSPARENT,
		margins: Variant = 12, shadow_size: int = 0, shadow_off: Vector2 = Vector2(0, 4), shadow_col: Color = SHADOW) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.2
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	var m: Array = margins if margins is Array else [margins, margins, margins, margins]
	sb.content_margin_left = float(m[0])
	sb.content_margin_top = float(m[1])
	sb.content_margin_right = float(m[2])
	sb.content_margin_bottom = float(m[3])
	if shadow_size > 0:
		sb.shadow_size = shadow_size
		sb.shadow_offset = shadow_off
		sb.shadow_color = shadow_col
	return sb


## Keyboard focus ring (drawn around the focused control).
static func focus_ring(radius: int = 18, col: Color = ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(3)
	sb.border_color = col
	sb.set_corner_radius_all(radius)
	sb.set_expand_margin_all(4.0)
	sb.anti_aliasing = true
	return sb


static func parchment_style(alpha: float = 1.0) -> StyleBoxFlat:
	var bg := PAPER
	bg.a = alpha
	return box(bg, 26, 3, BORDER, [30, 26, 30, 26], 22, Vector2(0, 10), SHADOW)


## Canvas shader that gives parchment a subtle paper grain and soft blotches (applies to the node's
## own drawing only; children are unaffected). Shared by every parchment surface.
static func paper_material() -> ShaderMaterial:
	if _paper_mat != null:
		return _paper_mat
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float grain = 0.045;
uniform float blotch = 0.06;
varying vec2 lp;
float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1.0, 0.0)), f.x), mix(h12(i + vec2(0.0, 1.0)), h12(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float g = vn(lp * 0.55) * 0.6 + vn(lp * 1.7) * 0.4;
	float b = vn(lp * 0.011 + vec2(3.1, 7.7)) * 0.65 + vn(lp * 0.03 + vec2(1.3, 2.9)) * 0.35;
	float m = 1.0 - grain * (g - 0.5) * 2.0 - blotch * (b - 0.5) * 2.0;
	COLOR.rgb *= m;
}
"""
	_paper_mat = ShaderMaterial.new()
	_paper_mat.shader = sh
	return _paper_mat


# --- Theme -------------------------------------------------------------------------------------

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = FS_BODY
	_labels(t)
	_buttons(t)
	_panels(t)
	_toggles(t)
	_sliders(t)
	_scrollbars(t)
	_tabs(t)
	_popups(t)
	_misc(t)
	return t


static func _label_var(t: Theme, name: String, f: String, size: int, col: Color, outline: int = 0, outline_col: Color = INK) -> void:
	t.set_type_variation(name, "Label")
	t.set_font(&"font", name, font(f))
	t.set_font_size(&"font_size", name, size)
	t.set_color(&"font_color", name, col)
	if outline > 0:
		t.set_constant(&"outline_size", name, outline)
		t.set_color(&"font_outline_color", name, outline_col)
		t.set_color(&"font_shadow_color", name, Color(0, 0, 0, 0.25))
		t.set_constant(&"shadow_offset_x", name, 0)
		t.set_constant(&"shadow_offset_y", name, 2)


static func _labels(t: Theme) -> void:
	t.set_color(&"font_color", &"Label", INK)
	t.set_font(&"font", &"Label", font("body"))
	t.set_font_size(&"font_size", &"Label", FS_BODY)
	t.set_constant(&"line_spacing", &"Label", 2)
	_label_var(t, "Heading", "heading", FS_H2, INK)
	_label_var(t, "Title", "heading_bold", FS_H1, INK)
	_label_var(t, "Display", "display", FS_DISPLAY, CREAM, 14, Color(INK, 0.9))
	_label_var(t, "Subheading", "heading", FS_H3, INK)
	_label_var(t, "Small", "body", FS_SMALL, INK_SOFT)
	_label_var(t, "Tiny", "body_bold", FS_TINY, INK_SOFT)
	_label_var(t, "Muted", "body", FS_BODY, INK_SOFT)
	_label_var(t, "GoodText", "body_bold", FS_SMALL, GOOD.darkened(0.25))
	_label_var(t, "BadText", "body_bold", FS_SMALL, BAD)
	_label_var(t, "WarnText", "body_bold", FS_SMALL, WARN.darkened(0.3))
	_label_var(t, "HudText", "body_bold", 23, CREAM, 7, Color(INK, 0.85))
	_label_var(t, "HudTitle", "heading", 28, CREAM, 8, Color(INK, 0.85))
	_label_var(t, "HudSmall", "body_bold", FS_HUD_SMALL, CREAM, 6, Color(INK, 0.85))
	_label_var(t, "RibbonTitle", "heading", 34, CREAM)
	t.set_color(&"font_shadow_color", &"RibbonTitle", Color(INK, 0.35))
	t.set_constant(&"shadow_offset_y", &"RibbonTitle", 2)
	_label_var(t, "KeyCapLabel", "body_bold", 20, INK)
	_label_var(t, "CardTitle", "heading", 26, INK)


static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color(&"font_color", type, normal)
	t.set_color(&"font_hover_color", type, hover)
	t.set_color(&"font_pressed_color", type, pressed)
	t.set_color(&"font_hover_pressed_color", type, pressed)
	t.set_color(&"font_focus_color", type, hover)
	t.set_color(&"font_disabled_color", type, disabled)
	t.set_color(&"icon_normal_color", type, Color.WHITE)
	t.set_color(&"icon_disabled_color", type, Color(1, 1, 1, 0.45))


static func _buttons(t: Theme) -> void:
	var m := [24, 10, 24, 12]
	var normal := box(PAPER_MID, 18, 2, BORDER_DARK, m, 4, Vector2(0, 3), Color(0.2, 0.1, 0.1, 0.22))
	var hover := box(PAPER_LIGHT, 18, 2, ACCENT.darkened(0.15), m, 6, Vector2(0, 4), Color(0.2, 0.1, 0.1, 0.25))
	var pressed := box(PAPER_DARK.darkened(0.06), 18, 2, BORDER_DARK, [24, 12, 24, 10], 1, Vector2(0, 1), Color(0.2, 0.1, 0.1, 0.2))
	var disabled := box(Color(PAPER_DARK, 0.55), 18, 2, Color(BORDER, 0.5), m)
	for type in [&"Button", &"OptionButton", &"MenuButton"]:
		t.set_stylebox(&"normal", type, normal)
		t.set_stylebox(&"hover", type, hover)
		t.set_stylebox(&"pressed", type, pressed)
		t.set_stylebox(&"hover_pressed", type, pressed)
		t.set_stylebox(&"disabled", type, disabled)
		t.set_stylebox(&"focus", type, focus_ring(22))
		_button_colors(t, type, INK, INK, INK, Color(INK_SOFT, 0.55))
		t.set_constant(&"h_separation", type, 10)
		t.set_constant(&"icon_max_width", type, 36)
	t.set_font(&"font", &"Button", font("heading"))
	t.set_font_size(&"font_size", &"Button", 26)
	t.set_font(&"font", &"OptionButton", font("body_bold"))
	t.set_font_size(&"font_size", &"OptionButton", FS_BODY)
	t.set_icon(&"arrow", &"OptionButton", IconFactory.glyph("arrow_down", 28, 28))
	t.set_constant(&"arrow_margin", &"OptionButton", 14)
	# Accent (primary) button
	t.set_type_variation(&"AccentButton", &"Button")
	var am := [28, 10, 28, 12]
	t.set_stylebox(&"normal", &"AccentButton", box(ACCENT, 18, 2, ACCENT.darkened(0.35), am, 5, Vector2(0, 3), Color(0.3, 0.05, 0.05, 0.3)))
	t.set_stylebox(&"hover", &"AccentButton", box(ACCENT.lightened(0.1), 18, 2, ACCENT.darkened(0.4), am, 7, Vector2(0, 4), Color(0.3, 0.05, 0.05, 0.3)))
	t.set_stylebox(&"pressed", &"AccentButton", box(ACCENT.darkened(0.12), 18, 2, ACCENT.darkened(0.45), [28, 12, 28, 10], 1, Vector2(0, 1)))
	t.set_stylebox(&"hover_pressed", &"AccentButton", box(ACCENT.darkened(0.12), 18, 2, ACCENT.darkened(0.45), [28, 12, 28, 10], 1, Vector2(0, 1)))
	t.set_stylebox(&"disabled", &"AccentButton", box(Color(ACCENT, 0.35), 18, 2, Color(ACCENT.darkened(0.3), 0.4), am))
	_button_colors(t, "AccentButton", CREAM, Color.WHITE, CREAM, Color(CREAM, 0.7))
	# Ghost (flat) button
	t.set_type_variation(&"GhostButton", &"Button")
	var gm := [16, 8, 16, 8]
	t.set_stylebox(&"normal", &"GhostButton", box(Color(PAPER_DARK, 0.0), 14, 0, Color.TRANSPARENT, gm))
	t.set_stylebox(&"hover", &"GhostButton", box(Color(PAPER_DARK, 0.7), 14, 0, Color.TRANSPARENT, gm))
	t.set_stylebox(&"pressed", &"GhostButton", box(PAPER_DARK, 14, 0, Color.TRANSPARENT, gm))
	t.set_stylebox(&"hover_pressed", &"GhostButton", box(PAPER_DARK, 14, 0, Color.TRANSPARENT, gm))
	t.set_stylebox(&"disabled", &"GhostButton", box(Color(PAPER_DARK, 0.0), 14, 0, Color.TRANSPARENT, gm))
	_button_colors(t, "GhostButton", INK_SOFT, INK, INK, Color(INK_SOFT, 0.45))
	t.set_font(&"font", &"GhostButton", font("body_bold"))
	t.set_font_size(&"font_size", &"GhostButton", FS_SMALL)
	# Round icon button (close buttons)
	t.set_type_variation(&"RoundButton", &"Button")
	t.set_stylebox(&"normal", &"RoundButton", box(PAPER_MID, 40, 2, BORDER_DARK, 8, 3, Vector2(0, 2)))
	t.set_stylebox(&"hover", &"RoundButton", box(PAPER_LIGHT, 40, 2, ACCENT.darkened(0.1), 8, 4, Vector2(0, 3)))
	t.set_stylebox(&"pressed", &"RoundButton", box(PAPER_DARK, 40, 2, BORDER_DARK, 8))
	t.set_stylebox(&"hover_pressed", &"RoundButton", box(PAPER_DARK, 40, 2, BORDER_DARK, 8))
	t.set_stylebox(&"focus", &"RoundButton", focus_ring(40))
	# Tab-like toggle button (filters, station tabs, settings intensity cards)
	t.set_type_variation(&"TabLike", &"Button")
	var tm := [18, 8, 18, 10]
	t.set_stylebox(&"normal", &"TabLike", box(Color(PAPER_DARK, 0.7), 14, 2, Color(BORDER, 0.7), tm))
	t.set_stylebox(&"hover", &"TabLike", box(PAPER_LIGHT, 14, 2, BORDER_DARK, tm))
	t.set_stylebox(&"pressed", &"TabLike", box(PAPER_LIGHT, 14, 3, ACCENT, tm, 4, Vector2(0, 2), Color(0.2, 0.1, 0.1, 0.18)))
	t.set_stylebox(&"hover_pressed", &"TabLike", box(PAPER_LIGHT, 14, 3, ACCENT, tm, 4, Vector2(0, 2), Color(0.2, 0.1, 0.1, 0.18)))
	t.set_stylebox(&"disabled", &"TabLike", box(Color(PAPER_DARK, 0.4), 14, 2, Color(BORDER, 0.35), tm))
	_button_colors(t, "TabLike", INK_SOFT, INK, INK, Color(INK_SOFT, 0.5))
	t.set_font(&"font", &"TabLike", font("heading"))
	t.set_font_size(&"font_size", &"TabLike", 24)
	# Title menu buttons (big, over the 3D diorama)
	t.set_type_variation(&"TitleMenuButton", &"Button")
	var tmm := [28, 6, 28, 8]
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 34
	empty.content_margin_right = 28
	empty.content_margin_top = 6
	empty.content_margin_bottom = 8
	t.set_stylebox(&"normal", &"TitleMenuButton", empty)
	t.set_stylebox(&"disabled", &"TitleMenuButton", empty)
	var th := box(Color(1.0, 0.96, 0.88, 0.14), 20, 0, Color.TRANSPARENT, tmm)
	th.border_width_left = 6
	th.border_color = GOLD
	th.content_margin_left = 34
	t.set_stylebox(&"hover", &"TitleMenuButton", th)
	t.set_stylebox(&"focus", &"TitleMenuButton", th)
	t.set_stylebox(&"pressed", &"TitleMenuButton", th)
	t.set_stylebox(&"hover_pressed", &"TitleMenuButton", th)
	_button_colors(t, "TitleMenuButton", CREAM, GOLD.lightened(0.2), GOLD, Color(CREAM, 0.4))
	t.set_font(&"font", &"TitleMenuButton", font("heading"))
	t.set_font_size(&"font_size", &"TitleMenuButton", 44)
	t.set_constant(&"outline_size", &"TitleMenuButton", 10)
	t.set_color(&"font_outline_color", &"TitleMenuButton", Color(INK, 0.75))


static func _panels(t: Theme) -> void:
	t.set_stylebox(&"panel", &"PanelContainer", parchment_style())
	t.set_stylebox(&"panel", &"Panel", parchment_style())
	var variations := {
		"Card": box(PAPER_LIGHT, 18, 2, Color(BORDER, 0.85), 18, 3, Vector2(0, 2), Color(0.2, 0.1, 0.1, 0.12)),
		"Inset": box(Color(PAPER_DARK, 0.55), 16, 0, Color.TRANSPARENT, 16),
		"HudCard": box(Color(PAPER, 0.93), 20, 3, Color(BORDER_DARK, 0.75), [20, 14, 20, 16], 10, Vector2(0, 5), Color(0.1, 0.05, 0.08, 0.3)),
		"HudDark": box(HUD_DARK, 18, 0, Color.TRANSPARENT, [20, 10, 20, 12]),
		"Pill": box(Color(0.16, 0.11, 0.15, 0.8), 30, 2, Color(CREAM, 0.25), [14, 8, 22, 9]),
		"Ribbon": box(ACCENT, 16, 3, ACCENT.darkened(0.35), [40, 6, 40, 8], 6, Vector2(0, 4), Color(0.25, 0.05, 0.08, 0.3)),
		"KeyCap": _keycap_style(),
		"SlotPanel": box(Color(PAPER_DARK, 0.9), 14, 2, BORDER, 6),
		"Tooltip": box(PAPER_LIGHT, 14, 2, BORDER_DARK, 16, 8, Vector2(0, 4)),
	}
	for v in variations:
		t.set_type_variation(v, &"PanelContainer")
		t.set_stylebox(&"panel", v, variations[v])


static func _keycap_style() -> StyleBoxFlat:
	var sb := box(PAPER_LIGHT, 9, 2, Color(INK_SOFT, 0.9), [11, 2, 11, 3])
	sb.border_width_bottom = 5
	return sb


static func _toggles(t: Theme) -> void:
	var off := IconFactory.glyph("box_off", 38, 38)
	var on := IconFactory.glyph("box_on", 38, 38)
	var roff := IconFactory.glyph("radio_off", 38, 38)
	var ron := IconFactory.glyph("radio_on", 38, 38)
	var soff := IconFactory.glyph("switch_off", 68, 38)
	var son := IconFactory.glyph("switch_on", 68, 38, GOOD)
	var hov := box(Color(PAPER_DARK, 0.55), 12, 0, Color.TRANSPARENT, [10, 6, 10, 6])
	var nrm := box(Color(PAPER_DARK, 0.0), 12, 0, Color.TRANSPARENT, [10, 6, 10, 6])
	for type in [&"CheckBox", &"CheckButton"]:
		t.set_stylebox(&"normal", type, nrm)
		t.set_stylebox(&"pressed", type, nrm)
		t.set_stylebox(&"hover", type, hov)
		t.set_stylebox(&"hover_pressed", type, hov)
		t.set_stylebox(&"disabled", type, nrm)
		t.set_stylebox(&"focus", type, focus_ring(14))
		t.set_font(&"font", type, font("body_bold"))
		t.set_font_size(&"font_size", type, FS_BODY)
		_button_colors(t, type, INK, INK, INK, Color(INK_SOFT, 0.5))
		t.set_constant(&"h_separation", type, 12)
	t.set_icon(&"unchecked", &"CheckBox", off)
	t.set_icon(&"checked", &"CheckBox", on)
	t.set_icon(&"unchecked_disabled", &"CheckBox", off)
	t.set_icon(&"checked_disabled", &"CheckBox", on)
	t.set_icon(&"radio_unchecked", &"CheckBox", roff)
	t.set_icon(&"radio_checked", &"CheckBox", ron)
	t.set_icon(&"radio_unchecked_disabled", &"CheckBox", roff)
	t.set_icon(&"radio_checked_disabled", &"CheckBox", ron)
	t.set_icon(&"unchecked", &"CheckButton", soff)
	t.set_icon(&"checked", &"CheckButton", son)
	t.set_icon(&"unchecked_disabled", &"CheckButton", soff)
	t.set_icon(&"checked_disabled", &"CheckButton", son)
	t.set_icon(&"unchecked_mirrored", &"CheckButton", soff)
	t.set_icon(&"checked_mirrored", &"CheckButton", son)


static func _sliders(t: Theme) -> void:
	var track := box(PAPER_DARK.darkened(0.1), 8, 0, Color.TRANSPARENT, [0, 6, 0, 6])
	var fill := box(ACCENT, 8, 0, Color.TRANSPARENT, [0, 6, 0, 6])
	var fill_hi := box(ACCENT.lightened(0.12), 8, 0, Color.TRANSPARENT, [0, 6, 0, 6])
	for type in [&"HSlider"]:
		t.set_stylebox(&"slider", type, track)
		t.set_stylebox(&"grabber_area", type, fill)
		t.set_stylebox(&"grabber_area_highlight", type, fill_hi)
		t.set_stylebox(&"focus", type, focus_ring(14))
		t.set_icon(&"grabber", type, IconFactory.glyph("knob", 40, 40))
		t.set_icon(&"grabber_highlight", type, IconFactory.glyph("knob_hot", 40, 40))
		t.set_icon(&"grabber_disabled", type, IconFactory.glyph("knob", 40, 40))
		t.set_icon(&"tick", type, IconFactory.glyph("dot", 8, 8, BORDER_DARK))
	t.set_constant(&"center_grabber", &"HSlider", 0)


static func _scrollbars(t: Theme) -> void:
	var track := box(Color(PAPER_DARK, 0.65), 8, 0, Color.TRANSPARENT, [6, 6, 6, 6])
	var grab := box(Color(BORDER_DARK, 0.7), 8, 0, Color.TRANSPARENT, [6, 6, 6, 6])
	var grab_hi := box(Color(ACCENT, 0.85), 8, 0, Color.TRANSPARENT, [6, 6, 6, 6])
	for type in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", type, track)
		t.set_stylebox(&"scroll_focus", type, track)
		t.set_stylebox(&"grabber", type, grab)
		t.set_stylebox(&"grabber_highlight", type, grab_hi)
		t.set_stylebox(&"grabber_pressed", type, grab_hi)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox(&"panel", &"ScrollContainer", empty)
	t.set_stylebox(&"focus", &"ScrollContainer", empty)


static func _tabs(t: Theme) -> void:
	var sel := box(PAPER_LIGHT, 14, 2, BORDER, [22, 8, 22, 10])
	sel.border_width_bottom = 0
	sel.corner_radius_bottom_left = 0
	sel.corner_radius_bottom_right = 0
	var uns := box(Color(PAPER_DARK, 0.85), 14, 2, Color(BORDER, 0.55), [22, 8, 22, 10])
	uns.corner_radius_bottom_left = 0
	uns.corner_radius_bottom_right = 0
	var hov := box(PAPER_MID, 14, 2, BORDER, [22, 8, 22, 10])
	hov.corner_radius_bottom_left = 0
	hov.corner_radius_bottom_right = 0
	var panel := box(Color(PAPER_LIGHT, 0.9), 16, 2, BORDER, [22, 20, 22, 20])
	panel.corner_radius_top_left = 0
	for type in [&"TabContainer", &"TabBar"]:
		t.set_stylebox(&"tab_selected", type, sel)
		t.set_stylebox(&"tab_unselected", type, uns)
		t.set_stylebox(&"tab_hovered", type, hov)
		t.set_stylebox(&"tab_disabled", type, uns)
		t.set_stylebox(&"tab_focus", type, focus_ring(14))
		t.set_font(&"font", type, font("heading"))
		t.set_font_size(&"font_size", type, 25)
		t.set_color(&"font_selected_color", type, INK)
		t.set_color(&"font_unselected_color", type, INK_SOFT)
		t.set_color(&"font_hovered_color", type, INK)
		t.set_color(&"font_disabled_color", type, Color(INK_SOFT, 0.5))
		t.set_constant(&"h_separation", type, 8)
	t.set_stylebox(&"panel", &"TabContainer", panel)
	t.set_stylebox(&"tabbar_background", &"TabContainer", StyleBoxEmpty.new())
	t.set_constant(&"side_margin", &"TabContainer", 0)


static func _popups(t: Theme) -> void:
	var pm := box(PAPER_LIGHT, 14, 2, BORDER_DARK, [8, 8, 8, 8], 8, Vector2(0, 4))
	t.set_stylebox(&"panel", &"PopupMenu", pm)
	t.set_stylebox(&"hover", &"PopupMenu", box(PAPER_DARK, 10, 0, Color.TRANSPARENT, [10, 4, 10, 4]))
	t.set_font(&"font", &"PopupMenu", font("body_bold"))
	t.set_font_size(&"font_size", &"PopupMenu", FS_BODY)
	t.set_color(&"font_color", &"PopupMenu", INK)
	t.set_color(&"font_hover_color", &"PopupMenu", INK)
	t.set_color(&"font_disabled_color", &"PopupMenu", Color(INK_SOFT, 0.5))
	t.set_constant(&"v_separation", &"PopupMenu", 10)
	t.set_constant(&"item_start_padding", &"PopupMenu", 14)
	t.set_constant(&"item_end_padding", &"PopupMenu", 14)
	t.set_icon(&"radio_checked", &"PopupMenu", IconFactory.glyph("dot", 20, 20))
	t.set_icon(&"radio_unchecked", &"PopupMenu", IconFactory.glyph("dot", 20, 20, Color(0, 0, 0, 0)))
	t.set_icon(&"checked", &"PopupMenu", IconFactory.glyph("dot", 20, 20))
	t.set_icon(&"unchecked", &"PopupMenu", IconFactory.glyph("dot", 20, 20, Color(0, 0, 0, 0)))
	t.set_stylebox(&"panel", &"TooltipPanel", box(PAPER_LIGHT, 14, 2, BORDER_DARK, [16, 12, 16, 12], 8, Vector2(0, 4)))
	t.set_color(&"font_color", &"TooltipLabel", INK)
	t.set_font(&"font", &"TooltipLabel", font("body"))
	t.set_font_size(&"font_size", &"TooltipLabel", FS_SMALL)


static func _misc(t: Theme) -> void:
	# Rich text
	t.set_color(&"default_color", &"RichTextLabel", INK)
	t.set_font(&"normal_font", &"RichTextLabel", font("body"))
	t.set_font(&"bold_font", &"RichTextLabel", font("body_bold"))
	t.set_font(&"italics_font", &"RichTextLabel", font("body_light"))
	t.set_font(&"bold_italics_font", &"RichTextLabel", font("heading"))
	for fs in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size"]:
		t.set_font_size(fs, &"RichTextLabel", FS_BODY)
	t.set_constant(&"line_separation", &"RichTextLabel", 4)
	t.set_stylebox(&"normal", &"RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox(&"focus", &"RichTextLabel", StyleBoxEmpty.new())
	# Separators
	var line := StyleBoxLine.new()
	line.color = Color(BORDER, 0.8)
	line.thickness = 2
	t.set_stylebox(&"separator", &"HSeparator", line)
	t.set_constant(&"separation", &"HSeparator", 18)
	var vline := StyleBoxLine.new()
	vline.color = Color(BORDER, 0.8)
	vline.thickness = 2
	vline.vertical = true
	t.set_stylebox(&"separator", &"VSeparator", vline)
	t.set_constant(&"separation", &"VSeparator", 18)
	# Progress bars
	t.set_stylebox(&"background", &"ProgressBar", box(PAPER_DARK.darkened(0.08), 10, 0, Color.TRANSPARENT, [0, 6, 0, 6]))
	t.set_stylebox(&"fill", &"ProgressBar", box(GOOD, 10, 0, Color.TRANSPARENT, [0, 6, 0, 6]))
	t.set_color(&"font_color", &"ProgressBar", INK)
	t.set_font_size(&"font_size", &"ProgressBar", FS_TINY)
	# Line edits (not used much, but keep them on-theme)
	t.set_stylebox(&"normal", &"LineEdit", box(PAPER_LIGHT, 12, 2, BORDER, [12, 8, 12, 8]))
	t.set_stylebox(&"focus", &"LineEdit", focus_ring(12))
	t.set_color(&"font_color", &"LineEdit", INK)
	# Containers
	t.set_constant(&"separation", &"VBoxContainer", 10)
	t.set_constant(&"separation", &"HBoxContainer", 10)
	t.set_constant(&"h_separation", &"GridContainer", 10)
	t.set_constant(&"v_separation", &"GridContainer", 10)
