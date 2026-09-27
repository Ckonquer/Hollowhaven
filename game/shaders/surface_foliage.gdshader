// Hollowhaven foliage (tree crowns, bushes, tall grass tufts, reeds).
// Same storybook toon ramp as toon.gdshader, plus vertex colours (baked light gradient per crown),
// wind sway that grows with height, a little leaf flutter and soft back-light translucency.
// The wind function is duplicated EXACTLY in surface_foliage_outline.gdshader so outlines follow.
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.16;
uniform float mid_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float mid_strength : hint_range(0.0, 1.0) = 0.16;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.28;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform float noise_amount : hint_range(0.0, 0.5) = 0.09;
uniform float noise_scale = 0.8;
uniform float translucency : hint_range(0.0, 1.0) = 0.22;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.1;
uniform float wind_height = 5.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

varying vec3 world_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// --- keep identical to surface_foliage_outline.gdshader -------------------------------
vec3 wind_offset(vec3 local_v, vec3 origin, vec3 wp, float t_raw) {
	float h = clamp(local_v.y / max(wind_height, 0.01), 0.0, 1.6);
	h = h * h;
	float t = t_raw * wind_speed + origin.x * 0.21 + origin.z * 0.17;
	float gust = sin(t * 0.37 + origin.x * 0.05 + origin.z * 0.03) * 0.5 + 0.5;
	vec3 off = vec3(sin(t), 0.0, cos(t * 0.83) * 0.6) * wind_strength * h * (0.55 + 0.9 * gust);
	off += vec3(sin(t_raw * 3.1 + wp.y * 2.3 + wp.x * 1.7), 0.0, cos(t_raw * 2.7 + wp.z * 2.1)) * wind_strength * 0.22 * h;
	return off;
}
// ---------------------------------------------------------------------------------------

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (wind_strength > 0.0) {
		VERTEX += wind_offset(VERTEX, origin, wp, TIME);
	}
	world_pos = wp;
}

void fragment() {
	vec3 base = albedo.rgb * COLOR.rgb;
	float n = vnoise(world_pos * noise_scale) * 0.65 + vnoise(world_pos * noise_scale * 3.3) * 0.35;
	base *= 1.0 + (n - 0.5) * 2.0 * noise_amount;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
	float hi = smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, ndl);
	float shade = lit * (1.0 - mid_strength) + hi * mid_strength;
	float att = smoothstep(0.02, 0.55, ATTENUATION);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * shade * att;
	// Back-lit leaves glow softly (cheap translucency).
	float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += lc * ALBEDO * translucency * back * back * (1.0 - lit) * 1.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += lc * rim_color.rgb * fres * rim_strength * clamp(ndl + 0.6, 0.0, 1.0) * att;
}
