extends Node
## Surface day/night: WorldEnvironment (custom storybook sky, lavender ambient, soft fog, glow, SSAO,
## filmic tonemap), a shadowed sun and a soft moon. Driven by GameState.hour() every frame; cheap.
## Nights stay readable: blue moonlight and a lifted indigo ambient, never black.
##   daylight: 0 (night) .. 1 (full day)   is_night: bool     warmth: 0..1 (Ward restored glow)

const Palette := preload("res://src/art/palette.gd")
const SKY_SHADER := preload("res://shaders/surface_sky.gdshader")

## Keyframes: hour, sky top, horizon, ground, fog, ambient, ambient energy, sun colour, sun energy,
## moon energy, stars, cloud light, cloud dark, fog density, exposure
const KEYS := [
	[0.0, Color("141a3a"), Color("3b4575"), Color("1d2440"), Color("2e3660"), Color("4f5a94"), 0.95, Color("ffc28a"), 0.0, 0.62, 1.0, Color("4d5687"), Color("262c4d"), 0.0055, 1.12],
	[4.6, Color("18204a"), Color("47508a"), Color("20284a"), Color("343d6c"), Color("56609a"), 0.92, Color("ffb090"), 0.0, 0.55, 0.9, Color("5a6090"), Color("2b3055"), 0.0065, 1.1],
	[5.8, Color("4b5a9e"), Color("f2ada2"), Color("4a5070"), Color("b8a8b8"), Color("8e88b8"), 0.72, Color("ffae86"), 0.35, 0.2, 0.25, Color("ffc8b0"), Color("8e84aa"), 0.0075, 1.05],
	[6.8, Color("73a8de"), Color("ffd3aa"), Color("7a8a78"), Color("e6d6c8"), Color("aaa4cc"), 0.6, Color("ffcf9c"), 0.95, 0.0, 0.0, Color("fff0dc"), Color("c8b8c8"), 0.0055, 1.0],
	[9.0, Color("62a9e6"), Color("f6e4c6"), Color("8c9c84"), Color("dfe8e0"), Color("b9b4d6"), 0.56, Color("fff1d6"), 1.22, 0.0, 0.0, Color("ffffff"), Color("c9d0e2"), 0.0035, 1.0],
	[15.5, Color("5ea6e4"), Color("f8e2c4"), Color("8c9c84"), Color("e2e8de"), Color("b9b4d6"), 0.56, Color("fff0d2"), 1.25, 0.0, 0.0, Color("ffffff"), Color("c9d0e2"), 0.0035, 1.0],
	[18.3, Color("86a8dc"), Color("ffcf9e"), Color("8a8c7c"), Color("f0d8bc"), Color("bbaccc"), 0.56, Color("ffc28a"), 1.05, 0.0, 0.0, Color("fff0d6"), Color("d8b8b8"), 0.004, 1.0],
	[19.5, Color("5e6cae"), Color("f7a58e"), Color("6a6478"), Color("d8a8a8"), Color("a296c4"), 0.6, Color("ff9a6a"), 0.5, 0.05, 0.05, Color("ffc0a0"), Color("8e7aa4"), 0.005, 1.02],
	[20.4, Color("2c3470"), Color("7c6298"), Color("2e3050"), Color("5a5484"), Color("6a6aa4"), 0.8, Color("ff8a60"), 0.0, 0.4, 0.45, Color("8a76a8"), Color("3a3864"), 0.0055, 1.08],
	[22.0, Color("161c40"), Color("3e477a"), Color("1e2542"), Color("30386a"), Color("515c96"), 0.95, Color("ffc28a"), 0.0, 0.62, 1.0, Color("4d5687"), Color("262c4d"), 0.0055, 1.12],
	[24.0, Color("141a3a"), Color("3b4575"), Color("1d2440"), Color("2e3660"), Color("4f5a94"), 0.95, Color("ffc28a"), 0.0, 0.62, 1.0, Color("4d5687"), Color("262c4d"), 0.0055, 1.12],
]

const FOG_SCALE := 0.24

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var warmth := 0.0
## Area colour grade (Hallowmere Reach: plum twilight, amber sun; docs/ch2/maps/world_areas.md 6a step 5).
## tint.rgb multiplies the sky, cloud, fog and ambient colours, blended in by tint.a; sun_tint.rgb replaces
## the sun colour by sun_tint.a. Both default to alpha 0 = no change (Hollowhaven Woods is untouched).
var tint := Color(1, 1, 1, 0)
var sun_tint := Color(1, 1, 1, 0)
var daylight := 1.0
var is_night := false
var hour_override := -1.0
var _quality := -1


func _ready() -> void:
	name = "Sky"
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35
	env.fog_height = -1.5
	env.fog_height_density = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Palette.MOON
	moon.shadow_enabled = false
	add_child(moon)
	apply_quality()
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	update_sky()


func _on_settings_changed(key: String) -> void:
	if key == "quality":
		apply_quality()


func apply_quality() -> void:
	var q := int(Settings.get_value("quality"))
	if q == _quality:
		return
	_quality = q
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.0
	sun.directional_shadow_max_distance = [55.0, 85.0, 120.0][clampi(q, 0, 2)]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	env.glow_enabled = true


func current_hour() -> float:
	return hour_override if hour_override >= 0.0 else GameState.hour()


func _process(_delta: float) -> void:
	update_sky()


## Interpolated keyframe values for an hour: Array aligned with KEYS entries (minus the hour).
static func sample_keys(hour: float) -> Array:
	var hh := fposmod(hour, 24.0)
	var a: Array = KEYS[0]
	var b: Array = KEYS[1]
	for i in KEYS.size() - 1:
		if hh >= float(KEYS[i][0]) and hh <= float(KEYS[i + 1][0]):
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var span := maxf(float(b[0]) - float(a[0]), 0.0001)
	var t := clampf((hh - float(a[0])) / span, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var out: Array = []
	for k in range(1, a.size()):
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if va is Color:
			out.append((va as Color).lerp(vb, t))
		else:
			out.append(lerpf(float(va), float(vb), t))
	return out


## Direction TOWARD the sun for an hour (east at 6:00, south at 13:00, west at 20:00).
static func sun_direction(hour: float) -> Vector3:
	var phi := PI * clampf((hour - 6.0) / 14.0, 0.0, 1.0)
	var el := deg_to_rad(maxf(6.0, 58.0 * sin(phi)))
	return Vector3(cos(el) * cos(phi), sin(el), cos(el) * sin(phi) * 0.8 + 0.25).normalized()


static func moon_direction(hour: float) -> Vector3:
	var hh := fposmod(hour - 19.5, 24.0)
	var phi := PI * clampf(hh / 11.0, 0.0, 1.0)
	var el := deg_to_rad(maxf(10.0, 52.0 * sin(phi)))
	return Vector3(cos(el) * cos(phi) * 0.9, sin(el), -0.35 + cos(el) * sin(phi) * 0.5).normalized()


func _grade(c: Color) -> Color:
	return c.lerp(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a), clampf(tint.a, 0.0, 1.0))


func update_sky() -> void:
	if env == null:
		return
	var hour := current_hour()
	var v := sample_keys(hour)
	var top: Color = v[0]
	var horizon: Color = v[1]
	var ground: Color = v[2]
	var fog: Color = v[3]
	var amb: Color = v[4]
	var amb_e: float = v[5]
	var sun_c: Color = v[6]
	var sun_e: float = v[7]
	var moon_e: float = v[8]
	var stars: float = v[9]
	var cl: Color = v[10]
	var cd: Color = v[11]
	var fog_d: float = v[12]
	var expo: float = v[13]
	if warmth > 0.0:
		var warm := Color("ffd9a0")
		amb = amb.lerp(Color("d6b8c8"), warmth * 0.25)
		sun_c = sun_c.lerp(warm, warmth * 0.3)
		horizon = horizon.lerp(Color("ffd0b0"), warmth * 0.2)
		amb_e += warmth * 0.08
	if tint.a > 0.0:
		top = _grade(top)
		horizon = _grade(horizon)
		ground = _grade(ground)
		fog = _grade(fog)
		amb = _grade(amb)
		cl = _grade(cl)
		cd = _grade(cd)
	if sun_tint.a > 0.0:
		sun_c = sun_c.lerp(Color(sun_tint.r, sun_tint.g, sun_tint.b), clampf(sun_tint.a, 0.0, 1.0))
	daylight = clampf(sun_e / 1.2, 0.0, 1.0)
	is_night = sun_e < 0.2
	var sd := sun_direction(hour)
	var md := moon_direction(hour)
	sun.light_color = sun_c
	sun.light_energy = sun_e
	sun.visible = sun_e > 0.01
	if sun.visible:
		sun.global_transform.basis = Basis.looking_at(-sd, Vector3.UP)
	moon.light_energy = moon_e
	moon.visible = moon_e > 0.01
	if moon.visible:
		moon.global_transform.basis = Basis.looking_at(-md, Vector3.UP)
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.fog_light_color = fog
	env.fog_density = fog_d * FOG_SCALE
	env.tonemap_exposure = expo
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", ground)
	sky_mat.set_shader_parameter("sun_color", sun_c)
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("sun_visible", clampf(sun_e * 2.0, 0.0, 1.0) if sd.y > 0.0 else 0.0)
	sky_mat.set_shader_parameter("moon_visible", clampf(moon_e * 2.5, 0.0, 1.0))
	sky_mat.set_shader_parameter("star_intensity", stars)
	sky_mat.set_shader_parameter("cloud_light", cl)
	sky_mat.set_shader_parameter("cloud_dark", cd)
