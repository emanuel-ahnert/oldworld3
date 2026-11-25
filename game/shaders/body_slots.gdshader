// Base body with gear slots (game copy of the spike shader): the vertex color R channel holds the slot (slot / 8 + 1/16, see
// tools/pipeline/skeleton.py). Each slot takes its texture from outfit A or B.
shader_type spatial;

uniform sampler2D tex_a : source_color, filter_linear_mipmap;
uniform sampler2D tex_b : source_color, filter_linear_mipmap;
// glTF metallic/roughness layout: G = roughness, B = metallic
uniform sampler2D mr_a : hint_default_white, filter_linear_mipmap;
uniform sampler2D mr_b : hint_default_white, filter_linear_mipmap;
// Normal maps baked from each outfit's generated geometry (plate edges, folds, rivets).
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap;
uniform float normal_strength = 0.8;
uniform vec4 tint_a : source_color = vec4(1.0);
uniform vec4 tint_b : source_color = vec4(1.0);
uniform float pick[5];
uniform float stealth = 0.0;    // rogue in stealth: dark and bluish          // 0 = outfit A, 1 = outfit B; head, chest, hands, legs, feet
uniform bool show_slots = false;
// Wearing a robe (robe_layer.py): the chest (arms included) and the legs above the hem are
// under it and not drawn, so nothing pokes through it.
uniform bool robed = false;
uniform float robe_legs = 9.0;     // m: under a robe the legs are drawn up to here (all: a cut left holes in a stride)

// Under headgear (headgear.py's shells around the full-size head) the head is drawn only where it
// shows: the face (within face_cos of straight ahead, below `brow` m above the head's middle) and
// the neck (below `chin`, near its axis). Hair and the back of the head would poke through the
// shell (WoW hides them too). Positions in the mesh's space, set every frame (Humanoid).
uniform bool hide_hair = false;
uniform vec3 head_center = vec3(0.0, 1.72, 0.0);
uniform vec3 head_up = vec3(0.0, 1.0, 0.0);
uniform vec3 head_fwd = vec3(0.0, 0.0, 1.0);
uniform float face_cos = 0.5;
uniform float brow = 0.07;
uniform float chin = -0.12;

// Clothes in tatters (goblins): holes torn in the outfit showing `skin`, frayed dark edges round
// them, the cloth faded and stained. 0 = whole.
uniform float tatter = 0.0;
// Goblins: the base body's face recoloured (head_tint, the skin; its dark hair kept near black),
// fur instead of the outfit's cloth (fur 0..1, fur_color), bare skin on the hands (skin_hands).
uniform vec3 head_tint = vec3(1.0);
uniform float fur = 0.0;
uniform vec3 fur_color : source_color = vec3(0.30, 0.22, 0.14);
uniform bool skin_hands = false;
// An egg-shaped head (goblins): the crown wider, the jaw narrower, a little taller. Needs
// head_center / head_up (set every frame by Humanoid); head_size: the head's bone scale.
uniform float head_egg = 0.0;
uniform float head_size = 1.0;
uniform vec3 head_unbuild = vec3(1.0);   // 1 / the body's build: the head keeps its proportions
uniform vec3 skin : source_color = vec3(0.42, 0.55, 0.25);

varying float slot;
varying vec3 mesh_pos;
varying float head_h;      // height above the head's middle (m, head-scaled; head_egg only)
varying float head_ahead;  // how far ahead of the head's middle (m; the face is > 0.06)
varying float head_az;     // angle around the head's up axis (radians; the hair's strands)
varying float head_lat;    // sideways from the face's line (m, before the reshaping; eyes, mouth)

float sq(float x) {
	return x * x;
}

float t_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float t_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(t_hash(i), t_hash(i + vec2(1, 0)), f.x), mix(t_hash(i + vec2(0, 1)), t_hash(i + vec2(1, 1)), f.x), f.y);
}
varying float height;      // above the feet (the mesh's origin is on the ground)

void vertex() {
	slot = COLOR.r * 8.0 - 0.5;
	height = VERTEX.y;
	head_h = 1.0;
	head_ahead = 1.0;
	head_az = 0.0;
	head_lat = 1.0;
	if (head_egg > 0.0 && slot < 0.5) {
		vec3 rel = VERTEX - head_center;
		rel = mix(rel, rel * head_unbuild, smoothstep(-0.2, -0.1, dot(rel, head_up) / head_size));
		float up = dot(rel, head_up) / head_size;
		head_h = up;
		vec3 flat_ = rel - head_up * up * head_size;
		float on_head = smoothstep(-0.15, -0.08, up);          // the neck stays as it is
		// A wide jaw (masculine): the sides below the cheekbones a little out.
		float k = 1.0 + head_egg * 0.22 * exp(-sq((up + 0.08) / 0.05));
		float ku = 1.0 + head_egg * 0.16 * smoothstep(0.0, 0.14, up);
		// Goblin features on the face (ahead of the head's middle): a long pointed nose, a heavy
		// brow ridge, a jutting chin. Distances in the head's own size.
		float ahead = dot(flat_, head_fwd) / head_size;
		head_ahead = ahead;
		// A goblin's skull: a low, flat forehead sloping back from the brow, the crown narrowing,
		// the back of the skull kept (swept back). Above the brows the head is held inside an
		// ellipse (front and sides shrinking with height, the back long); outside it is pulled in.
		vec3 sv = normalize(cross(head_up, head_fwd));
		float la = dot(flat_, sv) / head_size;
		head_lat = la;
		float over = max(up - 0.012, 0.0);
		// In profile the forehead follows a quarter ellipse from the brow (at the face's depth)
		// round into the crown: no straight steep slope meeting the top at a corner.
		float a_front = max(0.108 * sqrt(max(1.0 - sq(over / 0.15), 0.0)), 0.035);
		float a_side = max(0.072 - 0.25 * over, 0.04);
		float a_back = 0.14 - 0.15 * over;
		// Front and back axes blended across the middle: a hard switch left a notch in the crown.
		float a_fb = mix(a_back, a_front, smoothstep(-0.06, 0.06, ahead));
		float ax = ahead / a_fb;
		float e = length(vec2(ax, la / a_side));
		// The base hair (its dark texels, read here) down to the cheeks too: bangs and side locks
		// hung out of the narrow skull. Not the eyes and brows in the middle of the face.
		float hair_v = 1.0 - smoothstep(0.12, 0.3, dot(textureLod(tex_a, UV, 0.0).rgb, vec3(0.3, 0.59, 0.11)));
		// Not the face itself (eyes, brows: also dark): only hair standing off it, or above the brow.
		float not_eyes = max(1.0 - smoothstep(0.045, 0.065, ahead), smoothstep(0.03, 0.045, up));
		float w_sk = max(smoothstep(0.0, 0.025, up), hair_v * not_eyes * smoothstep(-0.09, -0.04, up) * smoothstep(-0.05, 0.02, ahead)) * head_egg;
		if (e > 1.0) {
			float f = mix(1.0, 1.0 / e, 0.92 * w_sk);
			flat_ *= f;
			ahead *= f;
		}
		vec3 egg_pos = head_center + head_up * up * head_size * ku + flat_ * k;
		vec3 sidev = sv;
		float lat = dot(flat_, sidev) / head_size;
		head_az = atan(lat, ahead);
		float front = smoothstep(0.05, 0.1, ahead);
		// A beak: a long narrow bridge from the brow down, the tip hooked downward.
		float nose = exp(-sq(lat / 0.018) - sq((up + 0.02) / 0.042)) * front;
		float tip = exp(-sq(lat / 0.016) - sq((up + 0.05) / 0.02)) * front;
		float ridge = exp(-sq(lat / 0.07) - sq((up - 0.035) / 0.014)) * front;
		float jut = exp(-sq(lat / 0.035) - sq((up + 0.11) / 0.025)) * front;
		egg_pos += head_fwd * head_size * head_egg * (0.05 * nose + 0.025 * tip + 0.012 * ridge + 0.014 * jut);
		egg_pos -= head_up * head_size * head_egg * (0.01 * nose + 0.035 * tip);   // the tip hooks down
		// The forehead slanting back into the crown: the upper front lowered the further ahead it
		// is (no flat top with a corner over the brow).
		egg_pos -= head_up * head_size * head_egg * 0.12 * max(ahead, 0.0) * smoothstep(0.05, 0.12, up);
		VERTEX = mix(VERTEX, egg_pos, on_head);
	}
	mesh_pos = VERTEX;
}

void fragment() {
	int s = clamp(int(round(slot)), 0, 4);
	if (hide_hair && s == 0) {
		vec3 rel = mesh_pos - head_center;
		float up = dot(rel, head_up);
		vec3 flat_ = rel - head_up * up;
		bool face = up < brow && dot(normalize(flat_ + head_fwd * 1e-4), head_fwd) > face_cos;
		bool neck = up < chin && length(flat_) < 0.075;
		if (!face && !neck) {
			discard;
		}
	}
	// Under a robe: the chest and arms aren't drawn, the legs and feet only below the hem (the
	// ankles and shoes show from any side; a foot kicked up behind in a stride doesn't float
	// behind the hem).
	if (robed && (s == 1 || ((s == 3 || s == 4) && height > robe_legs))) {
		discard;
	}
	vec3 a = texture(tex_a, UV).rgb * tint_a.rgb;
	vec3 b = texture(tex_b, UV).rgb * tint_b.rgb;
	ALBEDO = mix(a, b, pick[s]);
	if (s == 0 && head_tint != vec3(1.0)) {
		// The face in the skin's colour, the hair (the dark texels) near black.
		float lum = dot(ALBEDO, vec3(0.3, 0.59, 0.11));
		// The hair's texels in the skin's colour, a few thin black strands on the crown and the back
		// of the head (goblins: sparse, stringy hair).
		// Hair: the dark texels above the eyes or away from the face (the eyes and brows stay).
		float dark = 1.0 - smoothstep(0.12, 0.3, lum);
		float hair_area = dark * max(smoothstep(0.022, 0.04, head_h), 1.0 - smoothstep(0.03, 0.07, head_ahead));
		// Hair from a hairline above the brows over the whole crown: streaks of black with skin
		// between them (thin, stringy), a little patchy.
		// Strands run down from the crown on every side (in the head's own angles, not the UVs).
		float streak = t_noise(vec2(head_az * 70.0, head_h * 9.0)) * 0.7 + t_noise(vec2(head_az * 150.0, head_h * 16.0)) * 0.3;
		// The hairline: above the brows in front, lower at the back and sides (down to the nape).
		float hairline = mix(0.03, -0.05, smoothstep(0.02, -0.06, head_ahead));
		float strands = smoothstep(0.3, 0.44, streak) * (0.75 + 0.25 * smoothstep(0.3, 0.6, t_noise(UV * 14.0)))
			* smoothstep(hairline, hairline + 0.02, head_h);
		vec3 skin_c = mix(ALBEDO, vec3(0.62, 0.5, 0.42), hair_area) * head_tint;
		skin_c *= 0.9 + 0.2 * t_noise(UV * 60.0);
		// The face (its front surface): even goblin skin, no painted human shading, and its own
		// features: yellow almond eyes with slit pupils, a wide down-turned mouth with two fangs.
		float face = smoothstep(0.05, 0.075, head_ahead) * (1.0 - smoothstep(0.03, 0.05, head_h)) * smoothstep(-0.13, -0.1, head_h);
		vec3 flat_skin = skin * 1.45 * (0.93 + 0.14 * t_noise(UV * 45.0));
		vec3 f = flat_skin;
		vec2 ed = vec2((abs(head_lat) - 0.032) / 0.019, (head_h - 0.004 + 0.12 * (abs(head_lat) - 0.032)) / 0.0095);
		float er = length(ed);
		float eye = 1.0 - smoothstep(0.85, 1.0, er);
		float lid = smoothstep(0.75, 0.95, er) * (1.0 - smoothstep(1.0, 1.25, er));
		vec3 iris = mix(vec3(0.95, 0.78, 0.12), vec3(0.75, 0.45, 0.05), smoothstep(0.0, 0.8, er));
		float pupil = (1.0 - smoothstep(0.14, 0.22, abs(ed.x))) * (1.0 - smoothstep(0.7, 0.85, er));
		f = mix(f, f * 0.45, lid);
		f = mix(f, mix(iris, vec3(0.02), pupil), eye);
		float mx = head_lat / 0.04;
		float my = (head_h + 0.078 + 0.012 * sq(mx)) / 0.006;             // the corners turned down
		float mouth = (1.0 - smoothstep(0.75, 1.0, length(vec2(mx, my)))) * step(abs(mx), 1.0);
		f = mix(f, vec3(0.09, 0.03, 0.02), mouth);
		for (int i = 0; i < 2; i++) {
			float tx = (head_lat - (i == 0 ? -0.016 : 0.016)) / 0.0045;
			float ty = (head_h + 0.081) / 0.009;                            // from the upper lip down
			float fang = step(0.0, ty) * step(ty, 1.0) * step(abs(tx), 1.0 - ty);
			f = mix(f, vec3(0.92, 0.88, 0.72), fang * (1.0 - step(0.0, -ty)));
		}
		skin_c = mix(skin_c, f, face);
		ALBEDO = mix(skin_c, vec3(0.02, 0.018, 0.016), strands);
	}
	if (skin_hands && s == 2) {
		ALBEDO = skin * (0.85 + 0.15 * t_noise(UV * 40.0));
	}
	if (fur > 0.0 && (s == 1 || s == 3 || s == 4)) {
		// Fur: patches of lighter and darker hide, fine strands running down, the outfit's
		// shading (its folds) kept a little.
		float patch_ = t_noise(UV * 6.0) * 0.55 + t_noise(UV * 17.0) * 0.45;
		// Strands: fine, short, their direction wandering with the patches.
		vec2 su = UV + vec2(t_noise(UV * 11.0), t_noise(UV * 11.0 + 5.3)) * 0.02;
		float strand = t_noise(vec2(su.x * 1300.0, su.y * 260.0)) * 0.5 + t_noise(vec2(su.x * 2600.0, su.y * 520.0)) * 0.5;
		vec3 tip = fur_color * vec3(1.35, 1.3, 1.2);
		vec3 hide = mix(fur_color * 0.55, tip, patch_) * mix(0.75, 1.15, strand);
		float shade = mix(1.0, clamp(dot(ALBEDO, vec3(0.3, 0.59, 0.11)) * 3.0, 0.7, 1.2), 0.35);
		ALBEDO = mix(ALBEDO, hide * shade, fur);
	}
	if (tatter > 0.0 && s > 0) {
		bool torn = s == 1 || s == 3;          // rips in the shirt and trousers only
		// Rips (on the clothes, not the head): ragged holes from layered noise, a dark frayed
		// band round each, faded and stained cloth everywhere else.
		float n = t_noise(UV * 14.0) * 0.6 + t_noise(UV * 55.0) * 0.28 + t_noise(UV * 150.0) * 0.12;
		float cut = 0.79 - 0.06 * tatter;
		float hole = torn ? smoothstep(cut, cut + 0.012, n) : 0.0;
		float fray = torn ? smoothstep(cut - 0.035, cut, n) * (1.0 - hole) : 0.0;
		float stain = t_noise(UV * 9.0 + 3.7);
		float grey = dot(ALBEDO, vec3(0.3, 0.59, 0.11));
		vec3 cloth = mix(ALBEDO, vec3(grey) * vec3(0.95, 0.88, 0.75), 0.45 * tatter);
		cloth *= mix(1.0, 0.55 + 0.45 * stain, 0.7 * tatter);
		cloth *= 1.0 - 0.55 * fray;
		ALBEDO = mix(cloth, skin * (0.85 + 0.15 * t_noise(UV * 40.0)), hole);
	}
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.18, 0.2, 0.3), stealth);
	vec3 mr = mix(texture(mr_a, UV).rgb, texture(mr_b, UV).rgb, pick[s]);
	ROUGHNESS = mr.g;
	METALLIC = mr.b;
	NORMAL_MAP = mix(texture(normal_a, UV).rgb, texture(normal_b, UV).rgb, pick[s]);
	NORMAL_MAP_DEPTH = normal_strength;
	if (show_slots) {
		vec3 c[5] = vec3[](vec3(1, .9, .2), vec3(.9, .2, .2), vec3(.2, .8, .3), vec3(.2, .4, 1), vec3(.7, .3, .9));
		ALBEDO = c[s];
	}
}
