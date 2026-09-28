extends RefCounted
## Shared creature-look helpers (visual QA pass, CR-06 / CR-07 / CR-09 / CR-11). Three small shaders built in code
## (compiled once, cached) and cached materials, so a telegraph never floods the model with one flat colour again:
##   * TELL TINT  - the per-visual overlay (a StandardMaterial3D from HitFx.new_tint(), so its albedo alpha stays the
##                  wash the tests read) plus a fresnel RIM next pass in the tell colour. The wash is capped
##                  (WASH_CAP * WASH_K), the rim carries the warning, so the toon bands, the lavender shadows and the
##                  outlines stay readable under it. A hit flash stays a flat, strong flash (rim off).
##                    var tint := CreatureFx.new_tint()             # once per visual
##                    CreatureFx.apply_tint(tint, col, strength)    # telegraph (strength = the old flat alpha)
##                    CreatureFx.apply_flash(tint, col, alpha)      # hit flash
##   * SOFT GLOW  - a glow ball with a bright centre that fades to nothing at the edge (reads as light, not as a
##                  flat disc). back_only = draw the far half only: a halo BEHIND a figure that never veils it.
##   * ORB        - an opaque, self-lit ball: hot core colour facing the camera, warmer edge colour at the limb.
##   * EDGE LIGHT - an additive fresnel rim for dark silhouettes in dark rooms (chained after an outline pass).
## Materials are cached by parameters (identical calls share one material); only new_tint() makes per-visual ones.

const HitFx := preload("res://src/combat/hit_fx.gd")
const Mat := preload("res://src/art/mat.gd")

const WASH_CAP := 0.45          # the flat part of a tell never exceeds WASH_CAP * WASH_K (~0.25)
const WASH_K := 0.55
const RIM_K := 1.9              # rim alpha = strength * RIM_K ...
const RIM_MAX := 0.85           # ... capped

const _RIM_CODE := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float power = 1.6;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = rim_color.rgb;
	ALPHA = rim_color.a * clamp(pow(f, power) * 1.35, 0.0, 1.0);
}
"

const _GLOW_CODE := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, %s, shadows_disabled;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float power = 1.6;
uniform float energy = 1.0;
void fragment() {
	float d = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	ALBEDO = glow_color.rgb * energy;
	ALPHA = glow_color.a * pow(d, power);
}
"

const _ORB_CODE := "shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform vec4 core_color : source_color = vec4(1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float energy = 1.4;
void fragment() {
	float d = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(edge_color.rgb, core_color.rgb, smoothstep(0.15, 0.95, d)) * energy;
}
"

const _EDGE_CODE := "shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 edge_color : source_color = vec4(0.7, 0.72, 1.0, 1.0);
uniform float strength = 0.5;
uniform float power = 2.2;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = edge_color.rgb * strength * pow(f, power);
}
"

static var _shaders: Dictionary = {}
static var _mats: Dictionary = {}


static func _shader(kind: String) -> Shader:
	if _shaders.has(kind):
		return _shaders[kind]
	var s := Shader.new()
	match kind:
		"rim":
			s.code = _RIM_CODE
		"glow_back":
			s.code = _GLOW_CODE % "cull_front"
		"glow":
			s.code = _GLOW_CODE % "cull_back"
		"orb":
			s.code = _ORB_CODE
		_:
			s.code = _EDGE_CODE
	_shaders[kind] = s
	return s


# --- Tell tint -----------------------------------------------------------------------------------------------------

## A per-visual telegraph / hit-flash overlay: HitFx.new_tint() with a fresnel rim as its next pass.
static func new_tint() -> StandardMaterial3D:
	var m := HitFx.new_tint()
	var rim := ShaderMaterial.new()
	rim.shader = _shader("rim")
	rim.render_priority = 2
	rim.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0, 0.0))
	m.next_pass = rim
	return m


## Telegraph tint: `strength` is the old flat overlay alpha (0 .. ~0.5, pulsing or steady). The flat wash is capped,
## the rim takes the colour. No allocations (two parameter writes).
static func apply_tint(m: StandardMaterial3D, col: Color, strength: float) -> void:
	m.albedo_color = Color(col.r, col.g, col.b, minf(strength, WASH_CAP) * WASH_K)
	var rim := m.next_pass as ShaderMaterial
	if rim != null:
		rim.set_shader_parameter("rim_color", Color(col.r, col.g, col.b, clampf(strength * RIM_K, 0.0, RIM_MAX)))


## Hit flash: a flat overlay as before (the rim is switched off).
static func apply_flash(m: StandardMaterial3D, col: Color, alpha: float) -> void:
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	var rim := m.next_pass as ShaderMaterial
	if rim != null:
		rim.set_shader_parameter("rim_color", Color(col.r, col.g, col.b, 0.0))


## The rim alpha the tint currently draws (tests).
static func rim_alpha(m: StandardMaterial3D) -> float:
	var rim := m.next_pass as ShaderMaterial
	if rim == null:
		return 0.0
	var c: Variant = rim.get_shader_parameter("rim_color")
	return (c as Color).a if c is Color else 0.0


# --- Glows -----------------------------------------------------------------------------------------------------------

## Cached soft glow (bright centre -> transparent edge). `col.a` = the peak alpha. back_only: only the far half is
## drawn (a halo behind a figure).
static func soft_glow(col: Color, energy: float = 1.0, power: float = 1.6, back_only: bool = false) -> ShaderMaterial:
	var key := "glow|%s|%.2f|%.2f|%s" % [col.to_html(), energy, power, back_only]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("glow_back" if back_only else "glow")
	m.set_shader_parameter("glow_color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("power", power)
	m.render_priority = 1
	_mats[key] = m
	return m


## Cached opaque self-lit orb: `core` facing the camera, `edge` at the limb (volume without any light).
static func orb(core: Color, edge: Color, energy: float = 1.4) -> ShaderMaterial:
	var key := "orb|%s|%s|%.2f" % [core.to_html(), edge.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("orb")
	m.set_shader_parameter("core_color", core)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("energy", energy)
	_mats[key] = m
	return m


## Cached additive fresnel edge light (a next pass for dark bodies in dark rooms).
static func edge_light(col: Color, strength: float = 0.5, power: float = 2.2) -> ShaderMaterial:
	var key := "edge|%s|%.2f|%.2f" % [col.to_html(), strength, power]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("edge")
	m.set_shader_parameter("edge_color", col)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("power", power)
	m.render_priority = 1
	_mats[key] = m
	return m


## Cached toon + outline + edge light chain (the outline pass keeps the ink line; the edge light rides on top).
static func toon_outlined_edge(base: ShaderMaterial, thickness: float, outline: Color, edge: Color, strength: float, power: float = 2.2) -> Material:
	var key := "toe|%d|%.3f|%s|%s|%.2f|%.2f" % [base.get_instance_id(), thickness, outline.to_html(), edge.to_html(), strength, power]
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial = base.duplicate()
	var o := ShaderMaterial.new()
	o.shader = Mat.OUTLINE
	o.set_shader_parameter("thickness", thickness)
	o.set_shader_parameter("outline_color", outline)
	o.next_pass = edge_light(edge, strength, power)
	m.next_pass = o
	_mats[key] = m
	return m
