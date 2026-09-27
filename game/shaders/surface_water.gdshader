// Hollowhaven water (stream ribbon + Mirror Pond). Colour gradient by depth (from the depth buffer),
// soft foam where the water meets the banks, gentle moving highlights and toon sun/moon glints.
// is_stream = 1: UV.x runs across the stream (0..1), UV.y along it (metres / width) -> flowing streaks.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 shallow_color : source_color = vec4(0.42, 0.76, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.25, 0.56, 0.69, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float depth_scale = 0.9;
uniform float foam_width = 0.13;
uniform float flow_speed = 0.45;
uniform float is_stream = 1.0;
uniform float alpha_shallow = 0.5;
uniform float alpha_deep = 0.9;
uniform float glint_strength = 0.8;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.2 + wpos.x * 0.6 + wpos.z * 0.45) * 0.015;
}

void fragment() {
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thick = max(-view.z - (-VERTEX.z), 0.0);
	// Approximate vertical depth: thickness along the view ray times how steeply we look down.
	vec3 vdir = normalize(-VERTEX);
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float depth = thick * clamp(dot(vdir, up_view), 0.15, 1.0);
	float t = clamp(depth / depth_scale, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, t));

	vec2 fuv;
	if (is_stream > 0.5) {
		fuv = vec2(UV.x * 3.0, UV.y * 1.2 - TIME * flow_speed);
	} else {
		fuv = wpos.xz * 0.35 + vec2(TIME * 0.03, TIME * 0.02);
	}
	float n1 = vnoise(fuv * vec2(2.2, 1.0));
	float n2 = vnoise(fuv * vec2(5.0, 1.6) + vec2(3.1, TIME * 0.2));
	float sv = n1 * 0.6 + n2 * 0.4;
	float streak = smoothstep(0.66, 0.7, sv) * (1.0 - smoothstep(0.72, 0.78, sv));
	col = mix(col, vec3(0.93, 0.98, 1.0), streak * 0.3);

	// Foam along the banks (soft, broken, slowly moving).
	float fn = vnoise(wpos.xz * 2.2 + vec2(TIME * 0.25, -TIME * 0.18));
	float foam = 1.0 - smoothstep(foam_width * 0.35, foam_width * (0.8 + fn * 0.9), depth);
	col = mix(col, foam_color.rgb, foam * 0.7);

	// Rippled normal for glints.
	float e = 0.15;
	float hx = vnoise((wpos.xz + vec2(e, 0.0)) * 1.3 + TIME * 0.4) - vnoise((wpos.xz - vec2(e, 0.0)) * 1.3 + TIME * 0.4);
	float hz = vnoise((wpos.xz + vec2(0.0, e)) * 1.3 - TIME * 0.35) - vnoise((wpos.xz - vec2(0.0, e)) * 1.3 - TIME * 0.35);
	vec3 wn = normalize(vec3(-hx * 0.9, 1.0, -hz * 0.9));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	ALBEDO = col;
	ALPHA = clamp(mix(alpha_shallow, alpha_deep, t) + foam * 0.4, 0.0, 1.0) * COLOR.a;
	ROUGHNESS = 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (smoothstep(-0.3, 0.4, ndl) * 0.75 + 0.25) * ATTENUATION;
	vec3 hv = normalize(LIGHT + VIEW);
	float s = pow(max(dot(NORMAL, hv), 0.0), 140.0);
	SPECULAR_LIGHT += LIGHT_COLOR * smoothstep(0.35, 0.55, s) * glint_strength * ATTENUATION;
}
