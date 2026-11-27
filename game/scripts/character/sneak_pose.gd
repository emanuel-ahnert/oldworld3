class_name SneakPose
extends SkeletonModifier3D
## Sneaking (a rogue in stealth; Humanoid.set_sneak): after the animation the hips go down
## CROUCH m with the feet kept where the animation put them (each leg's knee bent by two-bone
## IK, the knee forward), the back hunched forward LEAN degrees over spine and chest, the neck
## and head turned back up to look ahead. Eased with `influence`.

const CROUCH := 0.13
const LEAN := 22.0

var _b := {}
var _left := Vector3.RIGHT          ## body directions in skeleton space (rest pose)
var _up := Vector3.UP
var _fwd := Vector3.FORWARD


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for n in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperArm", "RightUpperArm"]:
		_b[n] = sk.find_bone(n)
	var rest := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
	_left = (rest.call("LeftUpperArm") - rest.call("RightUpperArm")).normalized()
	_up = (rest.call("Head") - rest.call("Hips")).normalized()
	_fwd = _left.cross(_up).normalized()
	var toes: Vector3 = rest.call("LeftToes") - rest.call("LeftFoot")
	if _fwd.dot(toes) < 0.0:
		_fwd = -_fwd


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _b.is_empty() or int(_b.Hips) < 0:
		return
	# The feet as animated (they stay there), with their turn.
	var feet := {}
	for side in ["Left", "Right"]:
		feet[side] = sk.get_bone_global_pose(int(_b[side + "Foot"]))
	# Hips down.
	var hp := sk.get_bone_global_pose(int(_b.Hips))
	hp.origin -= _up * CROUCH
	sk.set_bone_global_pose(int(_b.Hips), hp)
	# The back hunched forward (around the body's left axis), split over spine and chest.
	for n in ["Spine", "Chest"]:
		var i := int(_b[n])
		if i < 0:
			continue
		var p := sk.get_bone_global_pose(i)
		p.basis = Basis(_left, deg_to_rad(LEAN * 0.5)) * p.basis
		sk.set_bone_global_pose(i, p)
	# Neck and head back up, eyes ahead.
	for n in ["Neck", "Head"]:
		var i := int(_b[n])
		if i < 0:
			continue
		var p := sk.get_bone_global_pose(i)
		p.basis = Basis(_left, deg_to_rad(-LEAN * 0.45)) * p.basis
		sk.set_bone_global_pose(i, p)
	# The legs: each knee bent so the foot is back where it was.
	for side in ["Left", "Right"]:
		_leg(sk, int(_b[side + "UpperLeg"]), int(_b[side + "LowerLeg"]), int(_b[side + "Foot"]), feet[side])


## Two-bone IK: thigh and shin turned so the ankle reaches `foot`'s origin, the knee forward;
## the foot keeps its animated turn.
func _leg(sk: Skeleton3D, upper: int, lower: int, foot_i: int, foot: Transform3D) -> void:
	if upper < 0 or lower < 0 or foot_i < 0:
		return
	var up_pose := sk.get_bone_global_pose(upper)
	var lo_pose := sk.get_bone_global_pose(lower)
	var ft_pose := sk.get_bone_global_pose(foot_i)
	var s := up_pose.origin
	var a := s.distance_to(lo_pose.origin)
	var b := lo_pose.origin.distance_to(ft_pose.origin)
	var t := foot.origin
	var dv := t - s
	var d := clampf(dv.length(), 0.05, a + b - 0.001)
	var x := dv.normalized()
	var pole := _fwd - x * _fwd.dot(x)
	if pole.length() < 1e-4:
		pole = _fwd
	pole = pole.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var knee := s + x * a * cos_a + pole * a * sqrt(1.0 - cos_a * cos_a)
	var turn_u := Quaternion((lo_pose.origin - s).normalized(), (knee - s).normalized())
	sk.set_bone_global_pose(upper, Transform3D(Basis(turn_u) * up_pose.basis, s))
	lo_pose = sk.get_bone_global_pose(lower)
	ft_pose = sk.get_bone_global_pose(foot_i)
	var turn_l := Quaternion((ft_pose.origin - lo_pose.origin).normalized(), (s + x * d - lo_pose.origin).normalized())
	sk.set_bone_global_pose(lower, Transform3D(Basis(turn_l) * lo_pose.basis, lo_pose.origin))
	ft_pose = sk.get_bone_global_pose(foot_i)
	sk.set_bone_global_pose(foot_i, Transform3D(foot.basis, ft_pose.origin))
