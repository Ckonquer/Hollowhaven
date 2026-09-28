extends Control
## Elegant chapter / area title card: a soft dark band with a large title, a subtitle and leafy
## ornaments. Fades in, holds, fades out, then frees itself. Emits `finished`.
## Styles (module C9): "leaf" (the Chapter One look: green leaves on a dusky band) and "autumn" (Chapter Two:
## amber leaves, a carved pumpkin and a plum-tinted band). setup(title, subtitle[, hold[, style]]); style ""
## picks "autumn" for titles starting with "Chapter Two", else "leaf" - so ui_root.show_chapter_card(title,
## subtitle) needs no change.

signal finished

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

const STYLE_LEAF := "leaf"
const STYLE_AUTUMN := "autumn"
const STYLES := {
	"leaf": {"leaf": Color("b5d977"), "band": Color(0.1, 0.07, 0.11), "pumpkin": false},
	"autumn": {"leaf": Color("e9a15b"), "band": Color(0.16, 0.07, 0.14), "pumpkin": true},
}

var title_text := ""
var subtitle_text := ""
var hold := 3.4
var style := ""


func setup(p_title: String, p_subtitle: String, p_hold: float = 3.4, p_style: String = "") -> void:
	title_text = p_title
	subtitle_text = p_subtitle
	hold = p_hold
	style = p_style


## The style a card with this title uses when none is given.
static func style_for(p_title: String, p_style: String = "") -> String:
	if STYLES.has(p_style):
		return p_style
	return STYLE_AUTUMN if p_title.begins_with("Chapter Two") else STYLE_LEAF


func _ready() -> void:
	style = style_for(title_text, style)
	var st: Dictionary = STYLES[style]
	var band_col: Color = st["band"]
	var leaf_col: Color = st["leaf"]
	Kit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := ColorRect.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.26
	band.anchor_bottom = 0.26
	band.offset_top = -120
	band.offset_bottom = 150
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec3 band_color = vec3(0.1, 0.07, 0.11);
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = abs(UV.y - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.25, 1.0, x)) * (1.0 - smoothstep(0.35, 1.0, y));
	COLOR = vec4(band_color, a * 0.55);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("band_color", Vector3(band_col.r, band_col.g, band_col.b))
	band.material = mat
	add_child(band)
	var v := Kit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.anchor_left = 0.0
	v.anchor_right = 1.0
	v.anchor_top = 0.26
	v.anchor_bottom = 0.26
	v.offset_top = -95
	v.offset_bottom = 125
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	var t := Kit.label(title_text, "Display", HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_size_override("font_size", 84)
	v.add_child(t)
	var orn := Kit.hbox(18)
	orn.alignment = BoxContainer.ALIGNMENT_CENTER
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var leaf_l := Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, leaf_col), 44)
	leaf_l.flip_h = true
	orn.add_child(leaf_l)
	if bool(st["pumpkin"]):
		orn.add_child(Kit.icon_rect(IconFactory.item_icon("pumpkin_lantern", 64), 40))
	var s := Kit.label(subtitle_text, "HudTitle", HORIZONTAL_ALIGNMENT_CENTER)
	s.add_theme_font_size_override("font_size", 42)
	s.add_theme_color_override("font_color", Color("ffe2a0"))
	orn.add_child(s)
	if bool(st["pumpkin"]):
		orn.add_child(Kit.icon_rect(IconFactory.item_icon("pumpkin_lantern", 64), 40))
	orn.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, leaf_col), 44))
	v.add_child(orn)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(self, "modulate:a", 0.0, 1.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())
