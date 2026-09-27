extends Control
## Elegant chapter / area title card: a soft dark band with a large title, a subtitle and leafy
## ornaments. Fades in, holds, fades out, then frees itself. Emits `finished`.

signal finished

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var title_text := ""
var subtitle_text := ""
var hold := 3.4


func setup(p_title: String, p_subtitle: String, p_hold: float = 3.4) -> void:
	title_text = p_title
	subtitle_text = p_subtitle
	hold = p_hold


func _ready() -> void:
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
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = abs(UV.y - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.25, 1.0, x)) * (1.0 - smoothstep(0.35, 1.0, y));
	COLOR = vec4(0.1, 0.07, 0.11, a * 0.55);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
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
	var leaf_l := Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, Color("b5d977")), 44)
	leaf_l.flip_h = true
	orn.add_child(leaf_l)
	var s := Kit.label(subtitle_text, "HudTitle", HORIZONTAL_ALIGNMENT_CENTER)
	s.add_theme_font_size_override("font_size", 42)
	s.add_theme_color_override("font_color", Color("ffe2a0"))
	orn.add_child(s)
	orn.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, Color("b5d977")), 44))
	v.add_child(orn)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(self, "modulate:a", 0.0, 1.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())
