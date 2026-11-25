// A caster's robe (tools/pipeline/robe_layer.py, after Oldworld2's): woollen cloth in `tint`
// with soft drape wrinkles; a narrow front panel, the collar, the hem and the
// cuffs in `accent` with a subtle embroidery in `trim`; a leather belt with a small buckle.
// UV: the robe u around (0.5 at the front), v 0 at the collar to 1 at the hem (the belt at
// BELT); the sleeves v 1.1 at the shoulder to 2.0 at the cuff.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 tint : source_color = vec4(0.17, 0.22, 0.42, 1.0);
uniform vec4 trim : source_color = vec4(0.7, 0.66, 0.5, 1.0);
uniform vec4 accent : source_color = vec4(0.08, 0.1, 0.2, 1.0);
uniform float stealth = 0.0;
const float BELT = 0.379;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Drape: long soft wrinkles running down the cloth, a little wavy (broad only: fine patterns
// shimmered at a distance).
float drape(vec2 uv) {
	return vnoise(vec2(uv.x * 24.0 + vnoise(uv * vec2(4.0, 3.0)) * 2.0, uv.y * 2.5));
}

// A small embroidered pattern: a running vine of dots and short strokes; x along, y 0..1 across.
float embroidery(float x, float y, float reps) {
	vec2 c = vec2(fract(x * reps) - 0.5, y - 0.5);
	float wave = step(abs(c.y - 0.22 * sin(fract(x * reps) * 6.2832)), 0.07);
	float dot_ = step(length(c * vec2(1.0, 1.4)), 0.13);
	float edge = step(abs(y - 0.1), 0.035) + step(abs(y - 0.9), 0.035);
	return clamp(wave * 0.8 + dot_ + edge, 0.0, 1.0);
}

void fragment() {
	float u = UV.x, v = UV.y;
	vec3 cloth = tint.rgb * (0.93 + 0.1 * vnoise(UV * vec2(6.0, 4.0)));
	vec3 col = cloth;
	float metal = 0.0;
	float cloth_area = 1.0;
	vec2 duv = vec2(u * (v > 1.05 ? 0.5 : 1.0), v);
	if (v > 1.05) {
		float sv = (v - 1.1) / 0.9;
		float cuff = step(0.9, sv) * step(sv, 0.99);
		col = mix(col, mix(accent.rgb, trim.rgb, embroidery(u, (sv - 0.9) / 0.09, 14.0) * 0.7), cuff);
		cloth_area = 1.0 - cuff;
	} else {
		float skirt = smoothstep(BELT, BELT + 0.1, v);
		float a = (1.5708 + u * 6.2832) * 11.0 + 0.6 + 2.0 * (v - BELT) / (1.0 - BELT);
		col *= mix(1.0, 0.88 + 0.12 * smoothstep(-1.0, 1.0, sin(a)), skirt);
		// The narrow front panel, collar to hem.
		float px = (u - 0.5) / 0.022;
		float panel = step(abs(px), 1.0);
		col = mix(col, mix(accent.rgb, trim.rgb, embroidery(v * 0.5, px * 0.5 + 0.5, 46.0) * 0.6), panel);
		// The collar.
		float collar = step(v, 0.03);
		col = mix(col, mix(accent.rgb, trim.rgb, embroidery(u, v / 0.03, 36.0) * 0.6), collar);
		// The hem.
		float hem = step(0.945, v) * step(v, 0.99);
		col = mix(col, mix(accent.rgb, trim.rgb, embroidery(u, (v - 0.945) / 0.045, 70.0) * 0.6), hem);
		col = mix(col, accent.rgb * 0.8, step(0.99, v));
		// The belt: leather, a small brass buckle at the front.
		float belt = step(abs(v - BELT), 0.016);
		vec3 leather = vec3(0.13, 0.085, 0.05);
		float buckle = step(abs(u - 0.5) * 60.0, 1.0) * step(abs(v - BELT), 0.02);
		col = mix(col, leather, belt);
		col = mix(col, vec3(0.62, 0.48, 0.24), buckle);
		metal = buckle;
		cloth_area = (1.0 - panel) * (1.0 - collar) * (1.0 - hem) * (1.0 - belt);
	}
	// The drape, as light and shade and as surface relief.
	float e = 0.004;
	float hx = drape(duv + vec2(e, 0.0)) - drape(duv - vec2(e, 0.0));
	float hy = drape(duv + vec2(0.0, e)) - drape(duv - vec2(0.0, e));
	NORMAL_MAP = normalize(vec3(-hx * 3.0, -hy * 1.0, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.4 * cloth_area;
	col *= 0.92 + 0.08 * drape(duv);
	col = mix(col, col * vec3(0.18, 0.2, 0.3), stealth);
	ALBEDO = col;
	METALLIC = metal * 0.7;
	ROUGHNESS = mix(0.92, 0.4, metal);
	SPECULAR = 0.25;
	if (!FRONT_FACING) {
		ALBEDO *= 0.5;
	}
}
