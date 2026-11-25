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

// Helmet worn (WoW style): head vertices above the neck are pulled toward the head center, so
// hair and ears end up inside the helmet instead of clipping through it. Positions are in the
// mesh's local space, updated every frame from the skeleton (player.gd).
uniform float head_shrink = 0.0;     // 0 = no helmet, 1 = full shrink
uniform vec3 head_center = vec3(0.0, 1.72, 0.0);
uniform vec3 neck_pos = vec3(0.0, 1.6, 0.0);
uniform vec3 head_up = vec3(0.0, 1.0, 0.0);

varying float slot;

void vertex() {
	slot = COLOR.r * 8.0 - 0.5;
	if (head_shrink > 0.0 && slot < 0.5) {
		float above = smoothstep(0.0, 0.05, dot(VERTEX - neck_pos, head_up));
		VERTEX = mix(VERTEX, head_center + (VERTEX - head_center) * 0.45, above * head_shrink);
	}
}

void fragment() {
	int s = clamp(int(round(slot)), 0, 4);
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
