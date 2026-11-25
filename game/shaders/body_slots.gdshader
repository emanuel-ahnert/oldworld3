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

varying float slot;
varying vec3 mesh_pos;
varying float height;      // above the feet (the mesh's origin is on the ground)

void vertex() {
	slot = COLOR.r * 8.0 - 0.5;
	height = VERTEX.y;
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
	if (robed && (s == 1 || ((s == 3 || s == 4) && height > 0.24))) {
		discard;
	}
	vec3 a = texture(tex_a, UV).rgb * tint_a.rgb;
	vec3 b = texture(tex_b, UV).rgb * tint_b.rgb;
	ALBEDO = mix(a, b, pick[s]);
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
