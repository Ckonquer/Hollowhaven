// Hollowhaven flowers (MultiMesh). Vertex colour alpha marks tintable petals; the petal colour comes
// from INSTANCE_CUSTOM.rgb. INSTANCE_CUSTOM.a = distance from bloom_center (restoration flowers only):
// instances scale in as bloom_radius sweeps outward (ending bloom). Gentle wind sway.
shader_type spatial;
render_mode cull_disabled;

uniform float bloom_radius = 100000.0;
uniform float bloom_width = 3.0;
uniform float wind_strength = 0.05;
uniform float emission_boost = 0.0;
uniform float band_softness : hint_range(0.0, 0.5) = 0.2;
uniform sampler2D occ_tex : filter_linear, repeat_disable, hint_default_black;   // built structures (1 = occupied)
uniform vec2 terrain_origin = vec2(-128.0, -128.0);
uniform vec2 terrain_samples = vec2(257.0);   // grid samples (x, z); a square grid by default (Woods)

varying vec3 v_col;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float grow = smoothstep(INSTANCE_CUSTOM.a - bloom_width, INSTANCE_CUSTOM.a, bloom_radius);
	grow *= 1.0 - step(0.3, textureLod(occ_tex, (origin.xz - terrain_origin + 0.5) / terrain_samples, 0.0).r);
	float pop = 1.0 + 0.25 * sin(clamp((bloom_radius - INSTANCE_CUSTOM.a) / bloom_width, 0.0, 1.0) * 3.14159);
	VERTEX *= grow * pop;
	float h = clamp(VERTEX.y / 0.4, 0.0, 1.0);
	float t = TIME * 1.6 + origin.x * 0.4 + origin.z * 0.3;
	VERTEX.x += sin(t) * wind_strength * h;
	VERTEX.z += cos(t * 0.8) * wind_strength * h * 0.6;
	v_col = mix(COLOR.rgb, COLOR.rgb * INSTANCE_CUSTOM.rgb, COLOR.a);
}

void fragment() {
	ALBEDO = v_col;
	EMISSION = v_col * emission_boost;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl) * 0.8 + 0.2;
	float att = smoothstep(0.02, 0.55, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit * att;
}
