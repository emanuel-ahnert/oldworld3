class_name Humanoid
extends Node3D
## A humanoid on the shared base body: gear slots (texture sets A and B per slot, see
## design/asset-pipeline.md), armor layers (WoW style geometry worn over the body, e.g. plate
## legs from tools/pipeline/armor.py, shown or hidden per gear), an optional helmet (the head shrinks under it, WoW style), a
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
	mat.set_shader_parameter("pick", PackedFloat32Array(cfg.get("pick", [0, 0, 0, 0, 0])))
	mat.set_shader_parameter("tint_a", cfg.get("tint_a", Color.WHITE))
	mat.set_shader_parameter("tint_b", cfg.get("tint_b", Color.WHITE))
	_mesh.material_override = mat
	for key in cfg.get("layers", {}):
		set_layer(key, cfg.layers[key])
	if cfg.has("helmet"):
		equip_model("helmet", cfg.helmet)
	if cfg.has("weapon"):
		equip_model("weapon", cfg.weapon, cfg.get("weapon_rot", Vector3(90, 0, 0)))
	for key in ["shield", "bow", "offhand"]:
		if cfg.has(key):
			equip_model(key, cfg[key])
	anim = CharAnimator.new(_body)
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
## Per-model fit of headgear: [offset, scale] (generated models differ in size and pivot).
## [offset, scale, rotation in degrees, head shrink]: the head shrinks under headgear so the hair
## doesn't poke through (WoW hides it). Closed helms, the coif and the cowl shrink it fully (the face
## sits in their shadow); the open cap doesn't (it would squash the face) and covers the hair.
## The hood is a layer (HEAD_LAYERS).
const HEAD_FIT := {
	"coif": [Vector3(0, 0.07, 0.02), 0.31, Vector3.ZERO, 1.0], "cap": [Vector3(0, 0.11, 0.01), 0.27, Vector3(0, 90, 0), 0.6],
	"cowl": [Vector3(0, 0.05, 0.04), 0.4, Vector3.ZERO, 1.0],
}
## Headgear worn as a layer fitted to the body instead of on the head bone: model -> [layer,
## head shrink]. The hood is fitted around the full-size head (tools/pipeline/hood_layer.py) and
## shows the face, so the head keeps its size (shrunk, the face looked tiny in the hood).
const HEAD_LAYERS := {"hood": ["res://assets/gear/hood_layer.glb", 0.0]}
var _shrink := 1.0
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


func has_layer(key: String) -> bool:
	return _layers.has(key)


## Puts a model into a hold (replacing what was there); path "" empties it. rot: optional
## rotation override (staves stand upright: Vector3.ZERO).
func equip_model(key: String, path: String, rot: Variant = null) -> void:
	if _held.has(key):
		(_held[key] as Node).queue_free()
		_held.erase(key)
	if key == "helmet":
		var layer: Array = HEAD_LAYERS.get(path.get_file().get_basename(), ["", 1.0])
		set_layer("head", layer[0], true)
		if layer[0] != "":
			helmet_worn = true
			_shrink = layer[1]
			return
	if path == "":
		if key == "helmet":
			helmet_worn = false
		return
	var h: Array = HOLD[key]
	var offset: Vector3 = h[1]
	var scale_f: float = h[3]
	var fit: Array = HEAD_FIT.get(path.get_file().get_basename(), [])
	if key == "helmet":
		_shrink = 1.0
	if key == "helmet" and not fit.is_empty():
		offset = fit[0]
		scale_f = fit[1]
		rot = fit[2]
		_shrink = fit[3]
	var att := _attach(h[0], path, offset, rot if rot != null else h[2], scale_f)
	if att:
		_held[key] = att
		if key == "bow":
			var m := att.get_child(0) as Node3D
			m.set_meta("rest", m.transform)
			m.set_meta("aim", _hold_xf(_skel.find_bone(h[0]), offset, BOW_AIM, scale_f))
		if stowed and key in STOWABLE:
			att.visible = false
	if key == "helmet":
		helmet_worn = att != null          # the body shader shrinks the head under it (no hair poking out)
	if key == "weapon":
		_fit_trail()


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


## The body shader shrinks the head under a helmet; it needs the head's mesh-local position of
## this frame's pose (after the animation: in _process it was a frame late, and in fast blows
## the head poked out of the helmet).
func _head_update() -> void:
	if mat == null:
		return
	mat.set_shader_parameter("head_shrink", _shrink if helmet_worn else 0.0)
	if not helmet_worn:
		return
	var to_mesh := _mesh.global_transform.affine_inverse() * _skel.global_transform
	var head := to_mesh * _skel.get_bone_global_pose(_head).origin
	var neck := to_mesh * _skel.get_bone_global_pose(_neck).origin
	var up := (head - neck).normalized()
	mat.set_shader_parameter("head_center", head + up * 0.1)
	mat.set_shader_parameter("neck_pos", head - up * 0.07)          # below the chin, so it shrinks too
	mat.set_shader_parameter("head_up", up)
