extends Control
## Full-screen feedback layers: a soft damage vignette (with a gentle low-health pulse) and the
## screen flash consumer (Events.screen_flash). Both respect Settings "reduce_flashing": flashes become
## faint and slow, the vignette is subtler and never pulses. Nothing here ever hard-flashes the screen.

const Palette := preload("res://src/art/palette.gd")

const MAX_FLASH_ALPHA := 0.5
const CALM_FLASH_ALPHA := 0.14

var vignette: ColorRect
var flash: ColorRect
var _hit := 0.0
var _t := 0.0
var _flash_tw: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(0.62, 0.1, 0.16, 1.0);
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.35;
	float d = length(uv);
	float v = smoothstep(0.34, 0.86, d);
	COLOR = vec4(tint.rgb, v * intensity);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vignette.material = mat
	add_child(vignette)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0)
	add_child(flash)
	Events.player_damaged.connect(_on_damaged)
	Events.screen_flash.connect(on_screen_flash)
	Events.player_respawned.connect(func() -> void: _hit = 0.0)


func _on_damaged(amount: float, _source: Node) -> void:
	var calm := bool(Settings.get_value("reduce_flashing"))
	_hit = clampf(_hit + clampf(amount / 25.0, 0.25, 0.8), 0.0, 0.45 if calm else 0.85)


## Soft, capped flash. reduce_flashing -> much fainter and slower.
func on_screen_flash(color: Color, duration: float) -> void:
	var calm := bool(Settings.get_value("reduce_flashing"))
	var peak := minf(color.a if color.a > 0.0 else 0.4, CALM_FLASH_ALPHA if calm else MAX_FLASH_ALPHA)
	var dur := maxf(duration, 0.2)
	if calm:
		dur = maxf(dur * 2.0, 0.8)
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	flash.color = Color(color.r, color.g, color.b, 0.0)
	_flash_tw = create_tween()
	_flash_tw.tween_property(flash, "color:a", peak, dur * (0.35 if calm else 0.12))
	_flash_tw.tween_property(flash, "color:a", 0.0, dur * (0.65 if calm else 0.88)).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	_hit = maxf(_hit - delta * 1.1, 0.0)
	var calm := bool(Settings.get_value("reduce_flashing"))
	var low := 0.0
	var hp := float(GameState.player.get("hp", 100.0))
	var mx := maxf(float(GameState.player.get("max_hp", 100.0)), 1.0)
	if Game.player != null and is_instance_valid(Game.player):
		var hv: Variant = Game.player.get("health")
		if hv is Node and is_instance_valid(hv):
			hp = float((hv as Node).get("hp"))
			mx = maxf(float((hv as Node).get("max_hp")), 1.0)
	var r := hp / mx
	if r < 0.3 and hp > 0.0:
		low = 0.1 + 0.3 * (1.0 - r / 0.3)
		if not calm:
			low *= 0.75 + 0.25 * sin(_t * 3.2)
	var inten := clampf(_hit + low, 0.0, 0.9)
	if calm:
		inten *= 0.55
	(vignette.material as ShaderMaterial).set_shader_parameter("intensity", inten)
	vignette.visible = inten > 0.002
