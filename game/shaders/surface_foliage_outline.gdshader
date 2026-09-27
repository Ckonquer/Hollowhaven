// Inverted-hull outline for swaying foliage. Applies the SAME wind as surface_foliage.gdshader
// (keep wind_offset identical) so the outline never slips off the leaves.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.17, 0.12, 0.16, 1.0);
uniform float thickness = 0.03;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.1;
uniform float wind_height = 5.0;

vec3 wind_offset(vec3 local_v, vec3 origin, vec3 wp, float t_raw) {
	float h = clamp(local_v.y / max(wind_height, 0.01), 0.0, 1.6);
	h = h * h;
	float t = t_raw * wind_speed + origin.x * 0.21 + origin.z * 0.17;
	float gust = sin(t * 0.37 + origin.x * 0.05 + origin.z * 0.03) * 0.5 + 0.5;
	vec3 off = vec3(sin(t), 0.0, cos(t * 0.83) * 0.6) * wind_strength * h * (0.55 + 0.9 * gust);
	off += vec3(sin(t_raw * 3.1 + wp.y * 2.3 + wp.x * 1.7), 0.0, cos(t_raw * 2.7 + wp.z * 2.1)) * wind_strength * 0.22 * h;
	return off;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 v = VERTEX;
	if (wind_strength > 0.0) {
		v += wind_offset(VERTEX, origin, wp, TIME);
	}
	VERTEX = v + NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
