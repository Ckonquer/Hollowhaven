// Toon campfire flame on a Y-billboarded quad: a wobbling teardrop cut out with scrolling noise and
// three hard colour bands (red rim, orange body, yellow core). Unshaded + emissive so glow picks it up.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.66, 0.28, 1.0);
uniform vec4 outer_color : source_color = vec4(0.95, 0.38, 0.2, 1.0);
uniform float intensity = 2.2;
uniform float seed = 0.0;
uniform float speed = 2.2;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Y-axis billboard (stays upright), keeps the node's scale.
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = normalize(cross(right, vec3(0.0, 1.0, 0.0)));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * sx, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	float h = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME * speed;
	float n = vnoise(vec2(UV.x * 3.0 + seed * 7.1, h * 2.4 - t));
	float n2 = vnoise(vec2(UV.x * 7.0 - seed * 3.3, h * 5.5 - t * 1.6));
	float wobble = (n - 0.5) * 0.5 * h;
	float width = (1.0 - pow(h, 0.85)) * (smoothstep(0.0, 0.18, h) * 0.55 + 0.45);
	float d = abs(x + wobble) / max(width, 0.001);
	float flame = 1.0 - d - (n2 - 0.5) * 0.7 * h - h * 0.2;
	if (flame < 0.02) {
		discard;
	}
	vec3 col = outer_color.rgb;
	if (flame > 0.28) {
		col = mid_color.rgb;
	}
	if (flame > 0.58) {
		col = core_color.rgb;
	}
	ALBEDO = col;
	EMISSION = col * intensity;
}
