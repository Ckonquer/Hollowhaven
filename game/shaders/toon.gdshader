// Hollowhaven storybook toon shader.
// Soft two-step lighting ramp, coloured ambient shadows (from the Environment), gentle rim light,
// painterly value noise, optional vertex colours, emission and wind sway for foliage.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.02;
uniform float band_softness : hint_range(0.0, 0.5) = 0.10;
uniform float mid_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float mid_strength : hint_range(0.0, 1.0) = 0.18;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float noise_amount : hint_range(0.0, 0.5) = 0.07;
uniform float noise_scale = 0.45;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.3;
uniform float wind_height = 1.0;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wind_strength > 0.0) {
		float h = clamp(VERTEX.y / max(wind_height, 0.01), 0.0, 1.5);
		float t = TIME * wind_speed + world_pos.x * 0.35 + world_pos.z * 0.27;
		VERTEX.x += sin(t) * wind_strength * h;
		VERTEX.z += cos(t * 0.83) * wind_strength * h * 0.6;
	}
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}
	float n = vnoise(world_pos * noise_scale) * 0.65 + vnoise(world_pos * noise_scale * 3.1) * 0.35;
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
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += lc * rim_color.rgb * fres * rim_strength * clamp(ndl + 0.6, 0.0, 1.0) * att;
	if (specular_amount > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float s = pow(max(dot(NORMAL, h), 0.0), 48.0);
		SPECULAR_LIGHT += lc * smoothstep(0.45, 0.55, s) * specular_amount * att;
	}
}
