class_name TorsoTwist
extends SkeletonModifier3D
## Strafing like WoW (Player._animate): the legs run toward where the hero moves (the model
## turned that way), the upper body turned back by `angle` (rad, about the body's up axis) so the
## chest, shoulders and head keep facing ahead. After the animation, spread over the spine.

const SHARES := {"Spine": 0.3, "Chest": 0.3, "UpperChest": 0.25, "Neck": 0.15}

var angle := 0.0

var _bones := {}
var _up := Vector3.UP


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in SHARES:
		_bones[b] = sk.find_bone(b)
	var hips := sk.find_bone("Hips")
	var head := sk.find_bone("Head")
	if hips >= 0 and head >= 0:
		_up = (sk.get_bone_global_rest(head).origin - sk.get_bone_global_rest(hips).origin).normalized()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or absf(angle) < 0.001:
		return
	for b in SHARES:
		var i: int = _bones.get(b, -1)
		if i < 0:
			continue
		var g := sk.get_bone_global_pose(i)
		g.basis = Basis(_up, angle * float(SHARES[b])) * g.basis
		sk.set_bone_global_pose(i, g)
