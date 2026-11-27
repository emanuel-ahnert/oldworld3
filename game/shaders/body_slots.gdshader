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
uniform float face_low = -1.0;   // a mask: only the band of the face above this shows (the eyes)
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
// The hero's own head (tools/pipeline/head_map.py): head_map tells for each texel of the head
// where it is on it (up, ahead, side from the head's middle, m / 0.4 + 0.5; A = on the head),
// whatever the pose. hair_color recolours the hair (a = 0: the texture's own brown); beard 0..1
// grows a beard (0.5: a short one, 1: a full one) in beard_color, with some volume.
uniform sampler2D head_map : filter_linear, repeat_disable;
uniform vec4 hair_color : source_color = vec4(0.0);
uniform float beard = 0.0;
uniform vec3 beard_color : source_color = vec3(0.05, 0.04, 0.035);
uniform int head_debug = 0;
// The heroes' painted face (on the bald head, Humanoid cfg "bald"): the whole head one skin
// (skin_tone), its features drawn where the base face has them (head map positions): eyes with
// lids and an iris (eye_color), brows (brow_color), nostrils, lips; soft shade in the eye
// sockets, under the nose and the lower lip. The base texture's face had its own baked light
// (one side darker) and never matched the scalp.
uniform bool face_paint = false;
uniform vec3 skin_tone : source_color = vec3(0.83, 0.64, 0.5);
uniform vec3 eye_color : source_color = vec3(0.32, 0.42, 0.5);
uniform vec3 brow_color : source_color = vec3(0.2, 0.14, 0.1);
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

// The painted face at head position h = (up, ahead, side), m; base: the skin there.
vec3 painted_face(vec3 h, vec3 base) {
	float side = abs(h.z);
	float front = smoothstep(0.045, 0.065, h.y);
	vec3 c = base;
	// Eye sockets: a soft shade round each eye, deepest at the inner corner.
	vec2 so = vec2((side - 0.029) / 0.022, (h.x - 0.008) / 0.014);
	c *= 1.0 - 0.13 * exp(-dot(so, so)) * front;
	// Under the nose and the lower lip, the cheeks' side: shade; a touch of warmth on the cheeks.
	c *= 1.0 - 0.12 * exp(-sq(side / 0.016) - sq((h.x + 0.054) / 0.006)) * front;
	c *= 1.0 - 0.1 * exp(-sq(side / 0.02) - sq((h.x + 0.09) / 0.008)) * front;
	c = mix(c, c * vec3(1.06, 0.92, 0.9), exp(-sq((side - 0.042) / 0.016) - sq((h.x + 0.03) / 0.016)) * front * 0.6);
	// Nostrils.
	vec2 nd = vec2((side - 0.0095) / 0.0045, (h.x + 0.046) / 0.0026);
	c = mix(c, c * 0.35, (1.0 - smoothstep(0.6, 1.0, length(nd))) * front);
	// Lips: the upper lip a little darker, the lower fuller; the mouth's line between.
	float mx = side / 0.021;
	float lip_u = (1.0 - smoothstep(0.8, 1.0, length(vec2(mx, (h.x + 0.0705) / 0.0035)))) ;
	float lip_l = (1.0 - smoothstep(0.75, 1.0, length(vec2(mx * 1.1, (h.x + 0.0785) / 0.0045))));
	vec3 lip = c * vec3(0.86, 0.6, 0.58);
	c = mix(c, lip * 0.92, lip_u * front);
	c = mix(c, lip, lip_l * front);
	float line_ = (1.0 - smoothstep(0.0006, 0.0014, abs(h.x + 0.0742 + 0.004 * sq(mx)))) * (1.0 - smoothstep(0.85, 1.05, mx));
	c = mix(c, c * 0.35, line_ * front);
	// Brows: an arc over each eye, thick inside, thin out.
	float by = 0.024 + 0.03 * sq(side - 0.026) * 40.0 * 0.0 + 0.006 * (1.0 - sq((side - 0.03) / 0.018));
	float bt = mix(0.0026, 0.0014, smoothstep(0.015, 0.045, side));
	float brow_w = (1.0 - smoothstep(bt * 0.6, bt, abs(h.x - by))) * smoothstep(0.009, 0.014, side) * (1.0 - smoothstep(0.044, 0.05, side));
	c = mix(c, brow_color, brow_w * front * 0.85);
	// The eyes: almond shapes, the white, an iris with its pupil looking ahead, the upper lid a
	// dark line, the lower soft.
	vec2 ed = vec2((side - 0.031) / 0.0115, (h.x - 0.007 + 0.12 * (side - 0.031)) / 0.0048);
	float er = length(ed);
	float eye = 1.0 - smoothstep(0.85, 1.0, er);
	vec2 id = vec2((side - 0.0305) / 0.0042, (h.x - 0.0072) / 0.0042);
	float ir = length(id);
	vec3 ec = mix(vec3(0.86, 0.83, 0.78), eye_color * mix(1.2, 0.7, smoothstep(0.2, 1.0, ir)), 1.0 - smoothstep(0.9, 1.05, ir));
	ec = mix(ec, vec3(0.03), 1.0 - smoothstep(0.38, 0.5, ir));
	ec *= 1.0 - 0.35 * smoothstep(0.2, 1.0, ed.y);          // the lid's shadow on the eye's top
	c = mix(c, ec, eye * front);
	float lid = smoothstep(0.75, 0.95, er) * (1.0 - smoothstep(1.0, 1.35, er)) * smoothstep(-0.3, 0.3, ed.y);
	c = mix(c, vec3(0.1, 0.07, 0.06), lid * front * 0.9);
	float lid_low = smoothstep(0.85, 1.0, er) * (1.0 - smoothstep(1.0, 1.2, er)) * (1.0 - smoothstep(-0.3, 0.1, ed.y));
	c = mix(c, c * 0.7, lid_low * front);
	return c;
}

// Where a beard grows (0..1), from a head-map position h = (up, ahead, side) in m: below the
// cheeks from the sideburns (in front of the ears, joining the hair) round the jaw and chin and a
// little down the throat, a moustache over the lip, the lips left free. Measured on the base
// body: the eyes at up 0, the nose tip -0.03, the mouth -0.06, the chin's bottom -0.095.
float beard_area(vec3 h, float amount) {
	float up = h.x;
	float ahead = h.y;
	float side = abs(h.z);
	// The cheek line: just under the nose in front, rising to the sideburns at the ears.
	float cheek = mix(-0.012, -0.038, smoothstep(0.0, 0.06, ahead));
	// Sideburns: in front of the ear up to the hair.
	cheek = mix(cheek, max(cheek, 0.03), 1.0 - smoothstep(0.0, 0.022, abs(ahead)));
	float a = 1.0 - smoothstep(cheek - 0.008, cheek + 0.004, up);
	a *= smoothstep(-0.03, -0.012, ahead);                          // not behind the ears
	a *= smoothstep(-0.135, -0.115, up);                            // down the throat a little
	// Not on the nose's sides: the cheek line's front part runs along the nostrils.
	a *= 1.0 - (1.0 - smoothstep(0.018, 0.03, side)) * smoothstep(-0.04, -0.03, up);
	// The lips stay bare (the moustache over them, the beard under them).
	float lips = 1.0 - smoothstep(0.8, 1.1, length(vec2(side / 0.02, (up + 0.06) / 0.006)));
	a *= 1.0 - lips * smoothstep(0.06, 0.08, ahead);
	// A short beard (amount < 1): only in front, a chin beard and a moustache.
	a *= mix(smoothstep(0.045, 0.07, ahead), 1.0, smoothstep(0.6, 0.95, amount));
	return clamp(a, 0.0, 1.0);
}

void vertex() {
	slot = COLOR.r * 8.0 - 0.5;
	height = VERTEX.y;
	head_h = 1.0;
	head_ahead = 1.0;
	head_az = 0.0;
	head_lat = 1.0;
	if (beard > 0.0 && slot < 0.5) {
		// The beard's volume: pushed out along the normal, the chin's part hanging lower.
		vec4 hm = textureLod(head_map, UV, 0.0);
		if (hm.a > 0.5) {
			// Where on the head from the vertex itself (head_center etc. follow the head every
			// frame, Humanoid._head_update): both copies of a vertex on a UV seam move alike (by
			// the map, read a little differently on each side, the beard tore open there).
			vec3 rel = VERTEX - head_center;
			vec3 h = vec3(dot(rel, head_up), dot(rel, head_fwd), dot(rel, normalize(cross(head_up, head_fwd)))) / head_size;
			float w = beard_area(h, beard);
			float chin_w = smoothstep(-0.07, -0.1, h.x) * smoothstep(0.02, 0.06, h.y);
			// Out from the head's middle (the mesh's axes: side x, up y, ahead z), not along the
			// normal: split normals at UV seams tore the beard open.
			vec3 out_ = normalize(rel + head_up * 0.02 * head_size);
			// Thickest on the chin and jaw's front, thin toward the sideburns (it stood off the
			// cheeks like a mask).
			float thick = mix(0.25, 1.0, smoothstep(0.02, 0.07, h.y)) * smoothstep(-0.01, -0.06, h.x);
			VERTEX += out_ * w * beard * 0.006 * thick;
			VERTEX.y -= w * chin_w * beard * beard * 0.014;
			VERTEX += out_ * w * chin_w * beard * beard * 0.005;
		}
	}
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
		bool face = up < brow && up > face_low && dot(normalize(flat_ + head_fwd * 1e-4), head_fwd) > face_cos;
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
	if (s == 0 && face_paint) {
		// The painted head: one skin (a little uneven), the face's features drawn on it.
		vec4 fm = texture(head_map, UV);
		vec3 sk = skin_tone * (0.96 + 0.06 * t_noise(UV * 90.0));
		ALBEDO = fm.a > 0.5 ? painted_face((fm.rgb - 0.5) * 0.4, sk) : sk;
	}
	float rough_hair = 0.0;               // hair and beard: matt (the texture's hair shone like plastic)
	if (s == 0 && (hair_color.a > 0.0 || beard > 0.0)) {
		vec4 hm = texture(head_map, UV);
		if (hm.a > 0.5) {
			vec3 h = (hm.rgb - 0.5) * 0.4;
			float lum = dot(ALBEDO, vec3(0.3, 0.59, 0.11));
			if (hair_color.a > 0.0) {
				// The hair: the dark texels over the brows' line in front, anywhere on the sides
				// and back. Recoloured keeping the texture's light and dark strands.
				// Round the sides the hair comes down to the ears' top, at the back to the nape.
				float low = mix(-0.09, 0.0, smoothstep(-0.06, 0.0, h.y));
				float region = max(smoothstep(0.018, 0.03, h.x), (1.0 - smoothstep(0.035, 0.06, h.y)) * smoothstep(low - 0.01, low + 0.006, h.x));
				float brows = smoothstep(-0.006, 0.004, h.x) * smoothstep(0.06, 0.075, h.y) * (1.0 - region);
				float dark = 1.0 - smoothstep(0.17, 0.3, lum);
				// On top and round the back it is all hair: its painted highlights too (they kept
				// a plastic shine on dark hair). The forehead under the fringe keeps the dark test.
				float crown = max(smoothstep(0.05, 0.07, h.x), 1.0 - smoothstep(0.0, 0.03, h.y)) * smoothstep(low, low + 0.02, h.x);
				dark = max(dark, crown * (1.0 - smoothstep(0.5, 0.7, lum)));
				dark = max(dark, smoothstep(0.075, 0.095, h.x));     // the top: all hair, highlights too
				vec3 dyed = hair_color.rgb * clamp(pow(lum / 0.13, 0.7), 0.6, 1.6);
				float hw = dark * (region + 0.6 * brows) * hair_color.a;
				ALBEDO = mix(ALBEDO, dyed, hw);
				rough_hair = max(rough_hair, hw * region);
			}
			if (beard > 0.0) {
				// The beard: strands running down (noise stretched along the head's up axis), a
				// ragged edge, darker deep in, stubble where it thins out.
				float w = beard_area(h, beard);
				float strand = t_noise(vec2((h.z + h.y * 0.7) * 520.0, h.x * 55.0)) * 0.6 + t_noise(vec2((h.z - h.y * 0.4) * 1300.0, h.x * 120.0)) * 0.4;
				float edge = t_noise(vec2(h.z * 160.0 + h.y * 90.0, h.x * 160.0));
				float cover = smoothstep(0.15, 0.55, w + (edge - 0.5) * 0.35);
				vec3 bcol = max(beard_color, vec3(0.045, 0.034, 0.026));
				float clump = t_noise(vec2(h.z * 90.0 + h.y * 60.0, h.x * 40.0));
				vec3 bc = bcol * mix(0.4, 1.35, strand * strand) * mix(0.7, 1.15, clump) * mix(0.75, 1.0, w);
				ALBEDO = mix(ALBEDO, bc, cover);
				rough_hair = max(rough_hair, cover);
				// Stubble just outside it.
				ALBEDO = mix(ALBEDO, ALBEDO * mix(vec3(1.0), beard_color * 3.0, 0.5), smoothstep(0.02, 0.2, w) * (1.0 - cover) * 0.5);
			}
		}
	}
	if (s == 0 && head_debug > 0) {
		vec4 hm = texture(head_map, UV);
		vec3 h = (hm.rgb - 0.5) * 0.4;
		float band = mod(floor(h.x / 0.02), 2.0);
		ALBEDO = hm.a < 0.5 ? vec3(1, 0, 1) : mix(vec3(0.2, 0.2, 0.9), vec3(0.9, 0.9, 0.2), band) * (h.x > 0.0 ? 1.0 : 0.6);
		if (abs(h.x) < 0.003) ALBEDO = vec3(1, 0, 0);
		if (abs(h.x + 0.1) < 0.003) ALBEDO = vec3(0, 1, 0);
		if (abs(h.z) < 0.002) ALBEDO = vec3(1, 1, 1);
		if (head_debug == 2) ALBEDO = mix(texture(tex_a, UV).rgb, vec3(1.0, 0.0, 0.0), beard_area(h, beard) * 0.7) + vec3(abs(h.x + 0.04) < 0.002 ? 1.0 : 0.0, abs(h.x + 0.02) < 0.002 ? 1.0 : 0.0, abs(h.y - 0.06) < 0.002 ? 1.0 : 0.0);
	}
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
	ROUGHNESS = mix(mr.g, 0.85, rough_hair);
	METALLIC = mr.b * (1.0 - rough_hair);
	NORMAL_MAP = mix(texture(normal_a, UV).rgb, texture(normal_b, UV).rgb, pick[s]);
	NORMAL_MAP_DEPTH = normal_strength;
	if (show_slots) {
		vec3 c[5] = vec3[](vec3(1, .9, .2), vec3(.9, .2, .2), vec3(.2, .8, .3), vec3(.2, .4, 1), vec3(.7, .3, .9));
		ALBEDO = c[s];
	}
}
