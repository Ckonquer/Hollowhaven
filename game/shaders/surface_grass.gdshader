// Hollowhaven GPU grass. One MultiMesh patch of grass clumps follows the camera (snapped to a grid
// so blades never swim); each clump reads the terrain height, colour and a density/height/tint mask
// from textures, so there is no per-blade CPU work. Wind sway, a gentle push away from the player,
// root-to-tip colour gradient matched to the ground, distance fade. Lighting matches the terrain.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform sampler2D color_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D occ_tex : filter_linear, repeat_disable, hint_default_black;   // built structures (1 = occupied)
uniform vec2 terrain_origin = vec2(-128.0, -128.0);
uniform float terrain_samples = 257.0;
uniform float fade_start = 24.0;
uniform float fade_end = 34.0;
uniform float blade_height = 0.52;
uniform float density_scale = 1.0;
uniform vec3 player_pos = vec3(0.0, -1000.0, 0.0);
uniform float wind_strength = 0.1;
uniform vec4 tip_warm : source_color = vec4(0.85, 0.81, 0.45, 1.0);
uniform float band_softness : hint_range(0.0, 0.5) = 0.3;

varying vec3 v_base;
varying vec3 v_tip;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 wp = origin.xz;
	vec2 uv = (wp - terrain_origin + 0.5) / terrain_samples;
	vec4 m = textureLod(mask_tex, uv, 0.0);
	m.r *= 1.0 - smoothstep(0.15, 0.5, textureLod(occ_tex, uv, 0.0).r);
	float rnd = hash12(floor(wp * 8.0) + 0.37);
	float rnd2 = hash12(floor(wp * 8.0) + 11.1);
	float dist = length(wp - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	float keep = step(rnd, m.r * density_scale) * fade;
	float s = keep * (0.3 + m.g * 1.15) * (0.75 + rnd2 * 0.5);
	float ang = rnd2 * 6.2831;
	float ca = cos(ang);
	float sa = sin(ang);
	vec3 v = VERTEX;
	v = vec3(v.x * ca - v.z * sa, v.y * s * blade_height, v.x * sa + v.z * ca) * vec3(0.7 + 0.3 * keep, 1.0, 0.7 + 0.3 * keep);
	float tipf = UV.y;
	float t = TIME * 1.3 + wp.x * 0.23 + wp.y * 0.17;
	float gust = sin(TIME * 0.4 + wp.x * 0.04 + wp.y * 0.02) * 0.5 + 0.5;
	vec2 wind = vec2(sin(t), cos(t * 0.8) * 0.5) * wind_strength * (0.4 + gust);
	vec2 away = wp + v.xz - player_pos.xz;
	float pd = length(away);
	float h = textureLod(height_tex, uv, 0.0).r;
	vec2 push = vec2(0.0);
	if (pd < 1.1 && abs(player_pos.y - h) < 2.0) {
		push = normalize(away + vec2(0.0001)) * (1.1 - pd) * 0.55;
	}
	v.xz += (wind + push) * tipf * tipf * s;
	v.y -= length(push) * tipf * 0.35 * s;
	VERTEX = v + vec3(0.0, h - 0.03, 0.0);
	vec3 ground = textureLod(color_tex, uv, 0.0).rgb;
	v_base = ground * 0.84;
	v_tip = mix(ground * 1.14, tip_warm.rgb, m.b * 0.38 + rnd * 0.06);
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(v_base, v_tip, smoothstep(0.0, 1.0, UV.y));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl);
	float att = smoothstep(0.02, 0.55, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit * att;
}
