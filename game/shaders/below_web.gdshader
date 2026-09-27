// Procedural cobweb for The Below (Silk Hollows). Radial spokes + sagging spiral threads, with torn
// gaps. Drawn on a quad; the hub sits at `hub` (UV). Faint self-glow keeps webs readable in the dark,
// and they glisten when the lantern light hits them. Arachnophobia mode never uses this shader.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform vec4 web_color : source_color = vec4(0.91, 0.89, 0.94, 1.0);
uniform float opacity = 0.6;
uniform float glow = 0.12;
uniform float spokes = 13.0;
uniform float ring_spacing = 0.055;
uniform float line_px = 1.1;
instance uniform float seed = 0.0;
instance uniform vec2 hub = vec2(0.5, 0.5);
instance uniform float density = 1.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV - hub;
	float r = length(p);
	float a = atan(p.y, p.x);
	float n_spokes = floor(spokes * mix(0.7, 1.15, hash11(seed * 7.1)));
	float seg = 6.2831853 / n_spokes;
	float sa = a / seg + seed * 3.7;
	float spoke_id = floor(sa + 0.5);
	float jitter = (hash11(spoke_id + seed * 13.0) - 0.5) * 0.35;
	float d_spoke = abs(fract(sa + 0.5 + jitter) - 0.5) * seg * r;
	// Spiral threads sag between spokes (chords) and wobble a little.
	float local = fract(sa + 0.5) - 0.5;
	float sag = (0.25 - local * local) * 0.4 * ring_spacing;
	float rr = r + sag + sin(spoke_id * 1.7 + seed) * 0.006;
	float spacing = ring_spacing * mix(0.85, 1.2, hash11(seed * 3.3));
	float ring_id = floor(rr / spacing);
	float d_ring = abs(fract(rr / spacing) - 0.5) * spacing;
	float w = fwidth(r) * line_px + 0.0015;
	float spoke_line = 1.0 - smoothstep(w * 0.5, w * 1.5, d_spoke);
	float ring_line = 1.0 - smoothstep(w * 0.5, w * 1.5, d_ring);
	// Torn gaps: drop some ring segments and fade spokes near the hub.
	float torn = step(0.78 - 0.25 * (1.0 - density), hash21(vec2(spoke_id, ring_id) + seed));
	ring_line *= 1.0 - torn;
	ring_line *= step(0.035, r);
	float lines = max(spoke_line * smoothstep(0.0, 0.02, r), ring_line);
	// Circular falloff (webs attach at the quad edges)
	float edge = 1.0 - smoothstep(0.42, 0.5, r);
	float alpha = lines * edge * opacity * mix(0.55, 1.0, density);
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = web_color.rgb;
	ALPHA = alpha;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	EMISSION = web_color.rgb * glow * lines;
}
