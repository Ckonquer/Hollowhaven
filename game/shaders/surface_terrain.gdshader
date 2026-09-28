// Hollowhaven Woods terrain. Vertex colours carry the grass tint (linear); a 1 m splat texture
// (R path, G sand, B rock, A under-water) is thresholded per pixel with noise so paths, banks and
// cliffs get smooth, organic, storybook edges. Lighting matches toon.gdshader (two-step ramp).
shader_type spatial;

uniform sampler2D splat_tex : filter_linear, repeat_disable;
uniform vec2 terrain_origin = vec2(-128.0, -128.0);
uniform vec2 terrain_samples = vec2(257.0);   // grid samples (x, z); a square grid by default (Woods)
uniform vec4 path_color : source_color = vec4(0.79, 0.64, 0.43, 1.0);
uniform vec4 path_edge_color : source_color = vec4(0.61, 0.46, 0.31, 1.0);
uniform vec4 sand_color : source_color = vec4(0.9, 0.83, 0.64, 1.0);
uniform vec4 wet_color : source_color = vec4(0.64, 0.55, 0.39, 1.0);
uniform vec4 rock_color : source_color = vec4(0.72, 0.7, 0.65, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.56, 0.54, 0.5, 1.0);
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.24;
uniform float mid_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float mid_strength : hint_range(0.0, 1.0) = 0.12;

varying vec3 world_pos;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz - terrain_origin + 0.5) / terrain_samples;
	vec4 s = texture(splat_tex, uv);
	float n = vnoise(world_pos.xz * 0.45) * 0.6 + vnoise(world_pos.xz * 1.3) * 0.4;
	float n2 = vnoise(world_pos.xz * 3.1);
	float n3 = vnoise(world_pos.xz * 9.0);
	vec3 base = COLOR.rgb;
	// Painterly grass: soft blotches and tiny strokes.
	base *= 1.0 + (n - 0.5) * 0.18 + (n3 - 0.5) * 0.07;
	// Sandy banks
	float sand = smoothstep(0.42, 0.52, s.g + (n2 - 0.5) * 0.3);
	base = mix(base, sand_color.rgb * (0.94 + n3 * 0.1), sand);
	// Stream / pond bed
	float wet = smoothstep(0.35, 0.65, s.a);
	base = mix(base, wet_color.rgb * (0.9 + n2 * 0.2), wet);
	// Dirt paths with darker, broken edges and little pebbles
	float pth = s.r + (n - 0.5) * 0.3 + (n2 - 0.5) * 0.14;
	float pm = smoothstep(0.4, 0.47, pth);
	float inner = smoothstep(0.52, 0.66, pth);
	vec3 pc = mix(path_edge_color.rgb, path_color.rgb, 0.35 + inner * 0.65);
	pc *= 0.94 + n3 * 0.12;
	float pebble = step(0.955, hash12(floor(world_pos.xz * 5.0))) * step(0.35, n2) * inner;
	pc = mix(pc, path_edge_color.rgb * 1.05, pebble * 0.35);
	base = mix(base, pc, pm);
	// Rock on steep slopes: noise sampled across the face (x+z, y) so steep faces don't streak,
	// with soft horizontal strata.
	vec2 rp = vec2(world_pos.x * 0.7 + world_pos.z * 0.7, world_pos.y * 1.4);
	float rn = vnoise(rp * 0.8) * 0.6 + vnoise(rp * 2.7) * 0.4;
	float r = s.b + (rn - 0.5) * 0.35 + (n - 0.5) * 0.15;
	float rm = smoothstep(0.34, 0.46, r);
	vec3 rc = mix(rock_color.rgb, rock_dark.rgb, clamp(smoothstep(0.55, 0.95, s.b) * 0.6 + (rn - 0.5) * 0.5, 0.0, 1.0));
	rc *= 0.9 + 0.1 * sin(world_pos.y * 2.2 + rn * 4.0);
	base = mix(base, rc, rm);
	ALBEDO = base;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
	float hi = smoothstep(mid_threshold - band_softness, mid_threshold + band_softness, ndl);
	float shade = lit * (1.0 - mid_strength) + hi * mid_strength;
	float att = smoothstep(0.02, 0.55, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * shade * att;
}
