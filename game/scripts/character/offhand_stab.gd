class_name OffhandStab
extends SkeletonModifier3D
## The off hand's strike (dual wield; Humanoid.offhand_stab): after the animation the left arm
## thrusts forward at chest height, the forearm straight along it. Eased in and out with
## `influence` (a quick jab).

var _bones := {}
var _left := Vector3.RIGHT
var _up := Vector3.UP
var _fwd := Vector3.FORWARD


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["LeftUpperArm", "LeftLowerArm", "LeftHand"]:
		_bones[b] = sk.find_bone(b)
	var rest := func(b: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(b)).origin
	_left = (rest.call("LeftUpperArm") - rest.call("RightUpperArm")).normalized()
	_up = (rest.call("Head") - rest.call("Hips")).normalized()
	_fwd = _left.cross(_up).normalized()
	var toes: Vector3 = rest.call("LeftToes") - rest.call("LeftFoot") if sk.find_bone("LeftToes") >= 0 else _fwd
	if _fwd.dot(toes) < 0.0:
		_fwd = -_fwd


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _bones.is_empty() or int(_bones.LeftUpperArm) < 0:
		return
	_aim(sk, int(_bones.LeftUpperArm), int(_bones.LeftLowerArm), (_fwd * 0.85 - _up * 0.25 - _left * 0.1).normalized())
	_aim(sk, int(_bones.LeftLowerArm), int(_bones.LeftHand), (_fwd - _left * 0.15).normalized())


func _aim(sk: Skeleton3D, b: int, c: int, dir: Vector3) -> void:
	if b < 0 or c < 0:
		return
	var bp := sk.get_bone_global_pose(b)
	var cp := sk.get_bone_global_pose(c)
	var now := cp.origin - bp.origin
	if now.length() < 1e-4:
		return
	sk.set_bone_global_pose(b, Transform3D(Basis(Quaternion(now.normalized(), dir)) * bp.basis, bp.origin))
