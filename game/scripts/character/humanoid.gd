class_name Humanoid
extends Node3D
## A humanoid on the shared base body: gear slots (texture sets A and B per slot, see
## design/asset-pipeline.md), armor layers (WoW style geometry worn over the body, e.g. plate
## legs from tools/pipeline/armor.py, shown or hidden per gear), optional headgear (a layer around the full-size head), a
## weapon in the right hand, and the animation tree. Faces -Z like the game's units.

const BODY := "res://assets/characters/warrior/body"

var anim: CharAnimator
var trail: WeaponTrail        ## the swoosh behind the main weapon
var mat: ShaderMaterial
var helmet_worn := false
var _mesh: MeshInstance3D
var _skel: Skeleton3D
var _body: Node3D
var _head := -1
var _neck := -1


## cfg: {outfit: "res://…/plate" (texture prefix for set B), pick: [5 floats], helmet: path,
##       weapon: path, tint_a: Color, tint_b: Color}
func build(cfg: Dictionary) -> void:
	_body = load(BODY + ".glb").instantiate()
	_body.rotation.y = PI      # the generated body faces +Z; units face -Z
	add_child(_body)
	_mesh = _body.find_children("*", "MeshInstance3D", true, false)[0]
	_skel = _body.find_children("*", "Skeleton3D", true, false)[0]
	_head = _skel.find_bone("Head")
	_neck = _skel.find_bone("Neck")
	_skel.skeleton_updated.connect(_head_update)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/body_slots.gdshader")
	var b: String = cfg.get("outfit", BODY)
	if not ResourceLoader.exists(b + "_color.png"):
		b = BODY          # outfit not generated yet: plain clothes
	for k in [["tex_a", BODY + "_color.png"], ["mr_a", BODY + "_mr.png"], ["normal_a", BODY + "_normal.png"],
			["tex_b", b + "_color.png"], ["mr_b", b + "_mr.png"], ["normal_b", b + "_normal.png"]]:
		if ResourceLoader.exists(k[1]):
			mat.set_shader_parameter(k[0], load(k[1]))
	_pick = PackedFloat32Array(cfg.get("pick", [0, 0, 0, 0, 0]))
	mat.set_shader_parameter("pick", _pick)
	mat.set_shader_parameter("tint_a", cfg.get("tint_a", Color.WHITE))
	mat.set_shader_parameter("tint_b", cfg.get("tint_b", Color.WHITE))
	# Ragged clothes and a different build (goblins): body_slots tatter, Proportions.
	mat.set_shader_parameter("tatter", float(cfg.get("tatter", 0.0)))
	mat.set_shader_parameter("fur", float(cfg.get("fur", 0.0)))
	if cfg.has("fur_color"):
		mat.set_shader_parameter("fur_color", cfg.fur_color)
	mat.set_shader_parameter("skin_hands", bool(cfg.get("skin_hands", false)))
	if cfg.has("head_tint"):
		mat.set_shader_parameter("head_tint", cfg.head_tint)
	head_egg = float(cfg.get("head_egg", 0.0))
	mat.set_shader_parameter("head_egg", head_egg)
	var bld: Vector3 = cfg.get("build", Vector3.ONE)
	mat.set_shader_parameter("head_unbuild", Vector3(1.0 / bld.x, 1.0 / bld.y, 1.0 / bld.z))
	if cfg.has("ears"):
		_add_ears(cfg.get("skin", Color(0.36, 0.5, 0.2)), float(cfg.ears), cfg.get("build", Vector3.ONE))
	if cfg.has("skin"):
		mat.set_shader_parameter("skin", cfg.skin)
	if cfg.has("legs") or cfg.has("head_size"):
		var pr := Proportions.new()
		pr.legs = float(cfg.get("legs", 1.0))
		pr.head = float(cfg.get("head_size", 1.0))
		_skel.add_child(pr)
		_body.position.y = -pr.drop()
	_mesh.material_override = mat
	for key in cfg.get("layers", {}):
		set_layer(key, cfg.layers[key])
	if cfg.has("robe"):
		set_robe(cfg.robe[0], cfg.robe[1], cfg.robe[2] if cfg.robe.size() > 2 else Color(-1, 0, 0))
	if cfg.has("helmet"):
		equip_model("helmet", cfg.helmet)
	if cfg.has("weapon"):
		equip_model("weapon", cfg.weapon, cfg.get("weapon_rot", Vector3(90, 0, 0)))
	for key in ["shield", "bow", "offhand"]:
		if cfg.has(key):
			equip_model(key, cfg[key])
	anim = CharAnimator.new(_body)
	anim.keep_arms_in_air = String(cfg.get("weapon", "")).get_file().begins_with("staff")
	trail = WeaponTrail.new()
	add_child(trail)
	_fit_trail()
	anim.shot_started.connect(trail.swing)


## Where held items sit: bone, offset, rotation (degrees), scale. The shield on the left forearm
## facing outward; the bow in the left fist: at rest held slanting, the lower limb forward and down
## past the knee, the upper one back and out past the hip (across the forearm it went through
## the leg); in combat and shooting turned to BOW_AIM (set_bow_aim), across the forearm like a
## sword's grip, so it stands upright when the arm is raised, its string toward the archer.
const HOLD := {
	"weapon": ["RightHand", Vector3(0, -0.075, 0.01), Vector3(90, 0, 0), 1.0],
	"shield": ["LeftLowerArm", Vector3(0.06, -0.12, 0.0), Vector3(0, 90, 0), 0.6],
	"bow": ["LeftHand", Vector3(0, -0.07, 0.0), Vector3(120, 0, 15), 1.0],
	"offhand": ["LeftHand", Vector3(0, -0.075, 0.01), Vector3(90, 0, 0), 1.0],
	"helmet": ["Head", Vector3(0, 0.085, 0.04), Vector3.ZERO, 0.30],
}
const BOW_AIM := Vector3(90, 0, 0)
const STAFF_SCALE := 0.75
static var STAFF_GRIP := Vector3(0.0, -0.16, 0.03)     ## the hand about the staff's middle
static var STAFF_TILT := Vector3(-12, 0, -5)          ## upright in the idle hand, off the robe
## Headgear is worn as a layer built around the full-size head (tools/pipeline/headgear.py):
## item model -> [layer, kind for shaders/headgear.gdshader (0 cloth, 1 mail, 2 leather,
## 3 plate)]. The head keeps its size: shrunk to fit generated helmets, it showed small inside the
## open ones.
const HEAD_LAYERS := {
	"hood": ["res://assets/gear/head_hood.glb", 0], "coif": ["res://assets/gear/head_coif.glb", 1],
	"cowl": ["res://assets/gear/head_cowl.glb", 2], "cap": ["res://assets/gear/head_cowl.glb", 2],
	"helmet": ["res://assets/gear/head_helm.glb", 3],
}
## What of the head still shows under each kind (body_slots.gdshader hide_hair): [cos of the
## face's half width, brow m above the head's middle] (the openings of headgear.py's KINDS).
const FACE_SHOWN := [[0.6, 0.036], [0.68, 0.036], [0.24, 0.034], [2.0, 0.0]]
var _face_shown := []
var head_egg := 0.0             ## > 0: the head egg-shaped, wide on top (goblins; body_slots)
const HEAD_AHEAD := 0.09
const HEAD_SIDE := 0.032       ## the face's center line is this far to the side of the head bone (headgear.py CX)
const HOOD_TINT := [Color(0.42, 0.36, 0.29), Color(0.30, 0.25, 0.19)]   ## a plain hood: tint, hem
var _robe_colors := HOOD_TINT
var _held := {}
var _layers := {}             ## key -> MeshInstance3D on the body's skeleton
static var _layer_mat: ShaderMaterial


## An armor layer (a skinned mesh on the shared skeleton, tools/pipeline/armor.py) under `key`
## ("legs"); path "" takes it off. The layer replaces nothing: the body's own slot texture stays
## underneath and shows only in the gaps between plates.
func set_layer(key: String, path: String, own_material := false) -> void:
	if _layers.has(key):
		if (_layers[key] as Node).get_meta("path", "") == path:
			return
		(_layers[key] as Node).queue_free()
		_layers.erase(key)
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene: Node = load(path).instantiate()
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	mi.get_parent().remove_child(mi)
	scene.free()
	_skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.set_meta("path", path)
	if not own_material:
		if _layer_mat == null:
			_layer_mat = ShaderMaterial.new()          # polished steel, brass trim (armor.py's data)
			_layer_mat.shader = load("res://shaders/armor.gdshader")
		mi.material_override = _layer_mat
	_layers[key] = mi


var _pick := PackedFloat32Array([0, 0, 0, 0, 0])


## Which texture set each body part shows (head, chest, hands, legs, feet): 1 the outfit
## (set B), 0 the plain clothes under it (set A: shirt, cloth trousers, shoes).
func set_pick(pick: Array) -> void:
	_pick = PackedFloat32Array(pick)
	if mat:
		mat.set_shader_parameter("pick", _pick)


## A caster's robe (tools/pipeline/robe_layer.py): the skirt layer coloured by shaders/robe.
## Color.TRANSPARENT tint takes it off.
func set_robe(tint: Color, trim: Color, accent := Color(-1, 0, 0)) -> void:
	if mat:
		mat.set_shader_parameter("robed", tint.a > 0.0)
	_robe_colors = HOOD_TINT if tint.a <= 0.0 else [tint, trim]
	_tint_hood()
	if tint.a <= 0.0:
		set_layer("robe", "")
		return
	set_layer("robe", ROBE, true)
	var mi := _layers.get("robe") as MeshInstance3D
	if mi == null:
		return
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/robe.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("trim", trim)
	m.set_shader_parameter("accent", accent if accent.r >= 0.0 else tint * 0.42)
	mi.material_override = m


const ROBE := "res://assets/gear/robe_layer.glb"


## A cloth hood takes the robe's colors (cloth and hem), a plain brown without one.
func _tint_hood() -> void:
	var mi := _layers.get("head") as MeshInstance3D
	if mi == null or not (mi.material_override is ShaderMaterial):
		return
	var hm := mi.material_override as ShaderMaterial
	hm.set_shader_parameter("tint", _robe_colors[0])
	hm.set_shader_parameter("trim", _robe_colors[1])


func has_layer(key: String) -> bool:
	return _layers.has(key)


## Puts a model into a hold (replacing what was there); path "" empties it. rot: optional
## rotation override (staves stand upright: Vector3.ZERO).
func equip_model(key: String, path: String, rot: Variant = null, size := 1.0) -> void:
	if _held.has(key):
		(_held[key] as Node).queue_free()
		_held.erase(key)
	if key == "helmet":
		var layer: Array = HEAD_LAYERS.get(path.get_file().get_basename(), ["", 0])
		set_layer("head", layer[0], true)
		helmet_worn = layer[0] != ""
		_face_shown = FACE_SHOWN[int(layer[1])] if helmet_worn else []
		if helmet_worn:
			var hm := ShaderMaterial.new()
			hm.shader = load("res://shaders/headgear.gdshader")
			hm.set_shader_parameter("kind", int(layer[1]))
			(_layers["head"] as MeshInstance3D).material_override = hm
			_tint_hood()
			return
	if path == "":
		if key == "helmet":
			helmet_worn = false
		return
	var h: Array = HOLD[key]
	var offset: Vector3 = h[1]
	var scale_f: float = h[3] * size
	if key == "weapon" and path.get_file().begins_with("staff"):
		scale_f *= STAFF_SCALE        # staves were too long: they stood far over the head
		# Held about the middle, the top tipped a little outward and forward (clear of the robe).
		offset = STAFF_GRIP
		rot = STAFF_TILT
	var att := _attach(h[0], path, offset, rot if rot != null else h[2], scale_f)
	if att:
		_held[key] = att
		if key == "weapon":
			_grip = null
			(att.get_child(0) as Node3D).set_meta("staff", path.get_file().begins_with("staff"))
			(att.get_child(0) as Node3D).set_meta("rest", (att.get_child(0) as Node3D).transform)
		if key == "bow":
			var m := att.get_child(0) as Node3D
			m.set_meta("rest", m.transform)
			m.set_meta("aim", _hold_xf(_skel.find_bone(h[0]), offset, BOW_AIM, scale_f))
		if stowed and key in STOWABLE:
			att.visible = false
	if key == "helmet":
		helmet_worn = att != null
	if key == "weapon":
		_fit_trail()
		_update_grip()
		if anim:
			anim.keep_arms_in_air = path.get_file().begins_with("staff")


## Something carried on a bone (a spell's glow in the hand): returns the attachment; free it to
## take it off.
func attach_to_bone(bone: String, node: Node3D, offset := Vector3.ZERO) -> BoneAttachment3D:
	if _skel.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skel.add_child(att)
	att.add_child(node)
	node.position = offset
	return att


## Weapons and shield put away (sitting at a camp fire): hidden until drawn again.
const STOWABLE := ["weapon", "shield", "bow", "offhand"]
var stowed := false


func stow(on: bool) -> void:
	stowed = on
	for key in STOWABLE:
		if _held.has(key):
			(_held[key] as Node3D).visible = not on


func _fit_trail() -> void:
	if trail == null:
		return
	var att: Node = _held.get("weapon")
	trail.weapon = null
	if att and att.get_child_count() > 0:
		trail.fit(att.get_child(0) as Node3D)


func _attach(bone: String, path: String, offset: Vector3, rot_deg: Vector3, scale_f: float) -> BoneAttachment3D:
	var idx := _skel.find_bone(bone)
	if idx < 0 or not ResourceLoader.exists(path):
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	_skel.add_child(att)
	var m: Node3D = load(path).instantiate()
	m.transform = _hold_xf(idx, offset, rot_deg, scale_f)
	att.add_child(m)
	return att


## Long pointed ears (goblins): a cupped leaf each side of the head on the head bone, pointing
## out, a little up and back. `length` in m (the body's units, before any head scaling).
func _add_ears(skin: Color, length: float, build := Vector3.ONE) -> void:
	var idx := _skel.find_bone("Head")
	if idx < 0:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = skin * 0.85        # thin and in full light: a little darker than the face to match
	m.roughness = 0.95
	m.metallic_specular = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := _ear_mesh(length)
	for sgn in [-1.0, 1.0]:
		var att := BoneAttachment3D.new()
		att.bone_name = "Head"
		_skel.add_child(att)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		att.add_child(mi)
		# On the side of the head at eye height (the face's line is HEAD_SIDE off the bone), the
		# base a little inside the skin, pointing out and up (40 degrees) and a little back.
		var off := Vector3(HEAD_SIDE + sgn * 0.064, 0.095, 0.035)
		var rot := Vector3(0, -15 * sgn, 40 * sgn)
		var xf := _hold_xf(idx, off, rot, 1.0)
		if sgn < 0:
			xf.basis = xf.basis * Basis.from_scale(Vector3(-1, 1, 1))   # mirrored (built along +X)
		# The body's build (a non-uniform scale on the whole model) is taken back out of the ears,
		# like out of the head (body_slots head_unbuild): stretched, the base stood off the head.
		var rel := Transform3D()
		var nn: Node = _skel
		while nn != _body:
			rel = (nn as Node3D).transform * rel
			nn = nn.get_parent()
		var rb := (rel * _skel.get_bone_global_rest(idx)).basis.orthonormalized()
		var unbuild := rb.inverse() * Basis.from_scale(Vector3(1.0 / build.x, 1.0 / build.y, 1.0 / build.z)) * rb
		mi.transform = Transform3D(unbuild, Vector3.ZERO) * xf


## An ear: a pointed leaf along +X (base at 0), widest near the base, cupped forward, a little
## thicker at the rim.
static func _ear_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var w := 5
	var pts := []
	for i in n + 1:
		var t := float(i) / n
		var half := length * 0.22 * pow(1.0 - t, 0.75) * (0.6 + 0.4 * sin(PI * minf(t * 1.6, 1.0)))
		var row := []
		for j in w + 1:
			var u := float(j) / w * 2.0 - 1.0          # -1 bottom .. 1 top edge
			var cup := (1.0 - u * u) * half * 0.35      # the middle forward, a hollow behind
			row.append(Vector3(t * length, u * half - t * length * 0.08, cup))
		pts.append(row)
	for i in n:
		for j in w:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Two-handed weapons: the left hand holds the grip below the right one (TwoHandGrip on the
## skeleton, its target on the weapon GRIP2 m toward the pommel), so every swing is two-handed:
## the right arm leads, the left follows the hilt.
const GRIP2 := 0.14
var two_handed := false
var _ik: TwoHandGrip
var _grip: Node3D


func set_two_handed(on: bool) -> void:
	two_handed = on
	if not on:
		_stance = 0.0
		if anim:
			anim.set_two_handed(0.0)
	_update_grip()


## Out of combat a two-hander is carried in the right hand like a one-hander; in combat
## (`fighting`) both hands take it: the two-handed hold and the left hand on the grip ease in
## over STANCE_TIME s (and out again).
const STANCE_TIME := 0.35
var _stance := 0.0


func set_two_hand_stance(fighting: bool, dt: float) -> void:
	if not two_handed:
		return
	var want := 1.0 if fighting else 0.0
	if is_equal_approx(_stance, want):
		return
	_stance = move_toward(_stance, want, dt / STANCE_TIME)
	var k := _stance * _stance * (3.0 - 2.0 * _stance)
	if anim:
		anim.set_two_handed(k)
	if _ik:
		_ik.influence = k
		_ik.active = k > 0.0


func _update_grip() -> void:
	var att := _held.get("weapon") as BoneAttachment3D
	if not two_handed or att == null or att.get_child_count() == 0:
		if _ik:
			_ik.active = false
		return
	var m := att.get_child(0) as Node3D
	if _ik == null:
		_ik = TwoHandGrip.new()
		_ik.name = "TwoHandGrip"
		_skel.add_child(_ik)
	if _grip == null or not is_instance_valid(_grip) or _grip.get_parent() != m:
		# The grip below the right hand: along the model's long axis, away from the blade's tip
		# (the end farther from the model's origin, which is where the right hand holds it).
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var bx := (m.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			box = bx if first else box.merge(bx)
			first = false
		var axis := box.get_longest_axis_index()
		var dir := Vector3.ZERO
		dir[axis] = -1.0 if absf(box.end[axis]) > absf(box.position[axis]) else 1.0   # toward the pommel
		_grip = Node3D.new()
		_grip.name = "Grip2"
		m.add_child(_grip)
		_grip.position = dir * GRIP2 / maxf(m.scale.x, 0.001)
	_ik.grip = _grip
	var k := _stance * _stance * (3.0 - 2.0 * _stance)
	_ik.influence = k
	_ik.active = k > 0.0
	if anim:
		anim.set_two_handed(k)


## A held model's transform under its bone: placed in character space (Y up, +Z = the body's
## front) relative to the bone's rest.
func _hold_xf(idx: int, offset: Vector3, rot_deg: Vector3, scale_f: float) -> Transform3D:
	var rel := Transform3D()
	var n: Node = _skel
	while n != _body:
		rel = (n as Node3D).transform * rel
		n = n.get_parent()
	var rest := rel * _skel.get_bone_global_rest(idx)
	var want := Transform3D(Basis.from_euler(rot_deg * PI / 180.0).scaled(Vector3.ONE * scale_f), rest.origin + offset)
	return rest.affine_inverse() * want


## A staff stays upright in the hand whatever the arm does (walking, casting with the hand
## raised: it turned upside down with the hand), turned about the grip, its top leaning a little
## in and its foot out, clear of the robe; in a melee swing it swings with the hand.
const STAFF_LEAN := 0.08           ## radians: the foot outward
const STAFF_FORWARD := 0.06        ## radians: the top forward
var _staff_up := 1.0


func _staff_update() -> void:
	if not _held.has("weapon"):
		return
	var att := _held["weapon"] as BoneAttachment3D
	if not is_instance_valid(att) or att.get_child_count() == 0:
		return
	var m := att.get_child(0) as Node3D
	if not m.get_meta("staff", false):
		return
	var dt := get_process_delta_time()
	_staff_up = move_toward(_staff_up, 0.0 if (anim and anim.swinging()) else 1.0, dt * 6.0)
	var rest: Transform3D = m.get_meta("rest")
	var held := att.global_transform * rest
	if _staff_up <= 0.0:
		m.transform = rest
		return
	# The fist: along the hand from the wrist (the bone's origin).
	var grip := att.global_position + att.global_basis.y.normalized() * 0.075
	var local_grip := held.affine_inverse() * grip
	var scale_v := held.basis.get_scale()
	# Upright in the character's frame: the foot out to the hand's side, the top a bit forward.
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var out := grip - global_position
	out.y = 0.0
	out = (out - fwd * out.dot(fwd)).normalized() if out.length() > 0.01 else Vector3.ZERO
	var up := (Vector3.UP * cos(STAFF_LEAN) - out * sin(STAFF_LEAN)).normalized()
	grip += out * 0.06 + fwd * 0.04        # the shaft beside the fist, clear of the robe
	up = (up * cos(STAFF_FORWARD) + fwd * sin(STAFF_FORWARD)).normalized()
	var z := fwd - up * fwd.dot(up)
	z = z.normalized()
	var x := up.cross(z)
	var target := Basis(x, up, z)
	var q := held.basis.orthonormalized().get_rotation_quaternion().slerp(target.get_rotation_quaternion(), _staff_up)
	var b := Basis(q).scaled(scale_v)
	m.global_transform = Transform3D(b, grip - b * local_grip)


var _bow_aim := 0.0


## The bow from its rest hold (0) to its shooting hold (1), eased over about 0.2 s.
func set_bow_aim(on: bool, dt: float) -> void:
	if not _held.has("bow"):
		return
	var m := (_held["bow"] as Node).get_child(0) as Node3D
	var goal := 1.0 if on else 0.0
	if is_equal_approx(_bow_aim, goal) and m.has_meta("set"):
		return
	_bow_aim = move_toward(_bow_aim, goal, dt * 5.0)
	m.set_meta("set", true)
	var a: Transform3D = m.get_meta("rest")
	m.transform = a.interpolate_with(m.get_meta("aim"), _bow_aim)


## Every frame after the animation: the staff's hold; under headgear the head's middle and
## directions for the body shader (what of the head is drawn), in the mesh's space of this frame's
## pose (in _process it was a frame late).
func _head_update() -> void:
	_staff_update()
	if mat == null:
		return
	mat.set_shader_parameter("hide_hair", not _face_shown.is_empty())
	if _face_shown.is_empty() and head_egg <= 0.0:
		return
	var to_mesh := _mesh.global_transform.affine_inverse() * _skel.global_transform
	var pose := _skel.get_bone_global_pose(_head)
	var turn := to_mesh.basis * pose.basis * _skel.get_bone_global_rest(_head).basis.inverse()
	var hs := turn.get_scale().x           # a scaled head (Proportions): the offsets scale with it
	var up := (turn * Vector3.UP).normalized()
	var fwd := (turn * Vector3.BACK).normalized()
	# The head's middle (headgear.py's HC): 10 cm over the head bone and 9 cm ahead of it (the
	# bone sits at the back of the neck; from there the ears counted as "ahead" and showed).
	var side := (turn * Vector3.RIGHT).normalized()
	mat.set_shader_parameter("head_center", to_mesh * pose.origin + (up * 0.10 + fwd * HEAD_AHEAD + side * HEAD_SIDE) * hs)
	mat.set_shader_parameter("head_up", up)
	mat.set_shader_parameter("head_fwd", fwd)
	mat.set_shader_parameter("head_size", hs)
	if not _face_shown.is_empty():
		mat.set_shader_parameter("face_cos", _face_shown[0])
		mat.set_shader_parameter("brow", _face_shown[1])
