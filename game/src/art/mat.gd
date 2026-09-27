extends RefCounted
## Material factory. All world/character art uses these so shading is consistent.
## Materials are cached by parameters: identical calls share one material (better batching).
##   const Mat := preload("res://src/art/mat.gd")
##   mesh_instance.material_override = Mat.toon(Palette.WOOD)
##   Mat.toon(c, {"rim": 0.5, "noise": 0.1, "emission": Color.ORANGE, "emission_energy": 2.0, "wind": 0.08})
##   Mat.outlined(Mat.toon(c), 0.02)          -> new material with an inverted-hull outline pass

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

static var _cache: Dictionary = {}


## Stylised toon material. opts: rim, noise, noise_scale, vertex_color, emission, emission_energy,
## specular, wind, wind_speed, wind_height, softness, mid
static func toon(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "toon|%s|%s" % [color.to_html(), str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_strength", float(opts.get("rim", 0.35)))
	m.set_shader_parameter("noise_amount", float(opts.get("noise", 0.07)))
	m.set_shader_parameter("noise_scale", float(opts.get("noise_scale", 0.45)))
	m.set_shader_parameter("use_vertex_color", bool(opts.get("vertex_color", false)))
	m.set_shader_parameter("band_softness", float(opts.get("softness", 0.10)))
	m.set_shader_parameter("mid_strength", float(opts.get("mid", 0.18)))
	if opts.has("emission"):
		m.set_shader_parameter("emission_color", opts["emission"])
		m.set_shader_parameter("emission_energy", float(opts.get("emission_energy", 1.0)))
	if opts.has("specular"):
		m.set_shader_parameter("specular_amount", float(opts["specular"]))
	if opts.has("wind"):
		m.set_shader_parameter("wind_strength", float(opts["wind"]))
		m.set_shader_parameter("wind_speed", float(opts.get("wind_speed", 1.3)))
		m.set_shader_parameter("wind_height", float(opts.get("wind_height", 1.0)))
	_cache[key] = m
	return m


## Returns a (cached) copy of `base` with an outline next pass.
static func outlined(base: Material, thickness: float = 0.018, color: Color = Color(0.17, 0.12, 0.16)) -> Material:
	var key := "outl|%d|%.3f|%s" % [base.get_instance_id(), thickness, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m: Material = base.duplicate()
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("thickness", thickness)
	o.set_shader_parameter("outline_color", color)
	m.next_pass = o
	_cache[key] = m
	return m


## Bright self-lit material (glows, eyes, lantern flames). Not affected by lights.
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


## Soft transparent material (water sheen, webs, ghost previews, glass).
static func transparent(color: Color, unshaded: bool = false, double_sided: bool = true) -> StandardMaterial3D:
	var key := "tr|%s|%s|%s" % [color.to_html(), unshaded, double_sided]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.roughness = 0.6
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Non-cached unique toon material (for per-instance animated parameters such as hit flashes).
static func toon_unique(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	return toon(color, opts).duplicate()
