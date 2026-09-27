// Hollowhaven storybook sky: soft gradient, warm sun disc with halo, a gentle moon, twinkling stars
// at night and slow painterly clouds. Colours are driven from src/world/surface/sky.gd every frame.
shader_type sky;

uniform vec4 top_color : source_color = vec4(0.5, 0.72, 0.91, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.99, 0.9, 0.78, 1.0);
uniform vec4 ground_color : source_color = vec4(0.55, 0.62, 0.55, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform vec4 moon_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform vec4 cloud_dark : source_color = vec4(0.78, 0.8, 0.9, 1.0);
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_visible = 1.0;
uniform float moon_visible = 0.0;
uniform float star_intensity = 0.0;
uniform float cloud_amount = 0.55;
uniform float cloud_speed = 0.006;
uniform float horizon_glow = 0.35;
uniform float sky_energy = 1.3;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col;
	if (y >= 0.0) {
		float t = pow(clamp(y, 0.0, 1.0), 0.55);
		col = mix(horizon_color.rgb, top_color.rgb, smoothstep(0.0, 1.0, t));
	} else {
		col = mix(horizon_color.rgb, ground_color.rgb, smoothstep(0.0, 0.12, -y));
	}
	// Warm glow on the horizon toward the sun (sunrise / sunset).
	vec3 sd = normalize(sun_dir);
	float toward = clamp(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sd.x, 0.0, sd.z) + vec3(0.0001))), 0.0, 1.0);
	float low_sun = 1.0 - smoothstep(0.05, 0.45, sd.y);
	col += sun_color.rgb * horizon_glow * low_sun * pow(toward, 3.0) * exp(-abs(y) * 7.0) * sun_visible;

	if (!AT_CUBEMAP_PASS) {
		// Stars (only well above the horizon).
		if (star_intensity > 0.001 && y > 0.02) {
			vec3 p = d * 150.0;
			vec3 cell = floor(p);
			float hs = hash13(cell);
			if (hs > 0.9965) {
				float dist = length(fract(p) - 0.5);
				float tw = 0.65 + 0.35 * sin(TIME * (1.5 + hs * 3.0) + hs * 80.0);
				float s = smoothstep(0.32, 0.0, dist) * tw * smoothstep(0.02, 0.25, y);
				col += vec3(1.0, 0.96, 0.88) * s * star_intensity * 1.6;
			}
			// A few bigger, softer stars.
			vec3 p2 = d * 45.0;
			float hs2 = hash13(floor(p2) + 17.0);
			if (hs2 > 0.993) {
				float dist2 = length(fract(p2) - 0.5);
				col += vec3(0.95, 0.93, 1.0) * smoothstep(0.22, 0.0, dist2) * star_intensity * smoothstep(0.05, 0.3, y);
			}
		}
		// Clouds: soft, slow, painterly; lit from the sun side.
		if (y > 0.0 && cloud_amount > 0.001) {
			vec2 uv = d.xz / (y + 0.12) * 0.7 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
			float c = fbm(uv * 0.8) + (fbm(uv * 0.23 + 4.7) - 0.5) * 0.45;
			float thr = 0.62 - cloud_amount * 0.14;
			float mask = smoothstep(thr, thr + 0.06, c);
			mask *= smoothstep(0.03, 0.2, y);
			float lit = clamp(0.5 + dot(d, sd) * 0.5, 0.0, 1.0);
			float puff = smoothstep(thr, thr + 0.25, c);
			vec3 cc = mix(cloud_dark.rgb, cloud_light.rgb, clamp(lit * 0.5 + puff * 0.6, 0.0, 1.0));
			col = mix(col, cc, mask * 0.92);
		}
	}
	// Sun disc with a soft halo.
	float sdot = dot(d, sd);
	float disc = smoothstep(0.9988, 0.9993, sdot);
	float halo = pow(max(sdot, 0.0), 180.0) * 0.6 + pow(max(sdot, 0.0), 12.0) * 0.12;
	col += sun_color.rgb * (disc * 2.2 + halo) * sun_visible;
	// Moon: a pale disc with a shaded crescent edge.
	vec3 md = normalize(moon_dir);
	float mdot = dot(d, md);
	float mdisc = smoothstep(0.99935, 0.99965, mdot);
	vec3 side = normalize(cross(md, vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
	float shade = smoothstep(0.99925, 0.99965, dot(d, normalize(md + side * 0.012)));
	vec3 moon = moon_color.rgb * mdisc * (1.0 - shade * 0.55) * 1.4;
	col = mix(col, moon, mdisc * moon_visible);
	col += moon_color.rgb * pow(max(mdot, 0.0), 400.0) * 0.35 * moon_visible;
	COLOR = col * sky_energy;
}
