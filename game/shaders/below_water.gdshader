// Still, murky shrine water for The Below. Opaque (so screen-space reflections apply), dark teal,
// with slow ripples perturbing the normal, a fresnel sheen and glossy highlights so lantern light
// and the cold shaft from above glint across it. Subtle by design.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.06, 0.13, 0.14, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.22, 0.38, 0.39, 1.0);
uniform float ripple_scale = 0.55;
uniform float ripple_speed = 0.18;
uniform float ripple_strength = 0.22;
uniform float gloss = 0.07;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float height_at(vec2 p, float t) {
	return vnoise(p + vec2(t, t * 0.6)) * 0.6 + vnoise(p * 2.3 - vec2(t * 0.8, -t * 0.5)) * 0.4;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * ripple_speed;
	vec2 p = wpos.xz * ripple_scale;
	float e = 0.05;
	float h = height_at(p, t);
	float hx = height_at(p + vec2(e, 0.0), t);
	float hz = height_at(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3(-(hx - h) / e * ripple_strength, 1.0, -(hz - h) / e * ripple_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep_color.rgb, sheen_color.rgb, fres * 0.7);
	ROUGHNESS = gloss;
	METALLIC = 0.0;
	SPECULAR = 0.75;
}
