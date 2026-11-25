class_name TwoHandGrip
extends SkeletonModifier3D
## Two-handed weapons (Humanoid.set_two_handed): after the animation, every frame, the left arm
## is bent so the left palm holds `grip` (a point on the weapon below the right hand). Two-bone
## IK by the law of cosines: the elbow in the plane through shoulder, target and a pole low at
## the left of the chest (so it points down and out), the upper and lower arm turned onto it.

const PALM := 0.07                 ## m from the wrist (the hand bone's origin) to the palm

var grip: Node3D

var _upper := -1
var _lower := -1
var _hand := -1
var _chest := -1
var _left := Vector3.RIGHT         ## body directions in skeleton space (from the rest pose)
var _up := Vector3.UP
var _fwd := Vector3.FORWARD


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_upper = sk.find_bone("LeftUpperArm")
	_lower = sk.find_bone("LeftLowerArm")
	_hand = sk.find_bone("LeftHand")
	_chest = sk.find_bone("UpperChest") if sk.find_bone("UpperChest") >= 0 else sk.find_bone("Chest")
	var rest := func(b: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(b)).origin
	_left = (rest.call("LeftUpperArm") - rest.call("RightUpperArm")).normalized()
	_up = (rest.call("Head") - rest.call("Hips")).normalized()
	_fwd = _left.cross(_up).normalized()
	var toes: Vector3 = rest.call("LeftToes") - rest.call("LeftFoot") if sk.find_bone("LeftToes") >= 0 else _fwd
	if _fwd.dot(toes) < 0.0:
		_fwd = -_fwd


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or grip == null or not is_instance_valid(grip) or _upper < 0 or _lower < 0 or _hand < 0:
		return
	var to_sk := sk.global_transform.affine_inverse()
	var target := to_sk * grip.global_position
	var up_pose := sk.get_bone_global_pose(_upper)
	var lo_pose := sk.get_bone_global_pose(_lower)
	var hand_pose := sk.get_bone_global_pose(_hand)
	var s := up_pose.origin
	var e0 := lo_pose.origin
	var w0 := hand_pose.origin
	var a := e0.distance_to(s)
	var b := w0.distance_to(e0)
	# The wrist a palm's width short of the grip, along the line from the shoulder.
	var wt := target - (target - s).normalized() * PALM
	var dv := wt - s
	var d := clampf(dv.length(), 0.05, a + b - 0.001)
	var x := dv.normalized()
	var chest := sk.get_bone_global_pose(_chest).origin if _chest >= 0 else s
	var pole := chest + _left * 0.45 - _up * 0.35 + _fwd * 0.15
	var p := pole - s
	var y := (p - x * p.dot(x))
	if y.length() < 1e-4:
		y = -_up
	y = y.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := s + x * a * cos_a + y * a * sqrt(1.0 - cos_a * cos_a)
	# Upper arm: turned from where it points to the elbow.
	var turn_u := Quaternion((e0 - s).normalized(), (elbow - s).normalized())
	sk.set_bone_global_pose(_upper, Transform3D(Basis(turn_u) * up_pose.basis, s))
	# Lower arm (moved with the upper one): turned onto the wrist's target.
	lo_pose = sk.get_bone_global_pose(_lower)
	hand_pose = sk.get_bone_global_pose(_hand)
	var turn_l := Quaternion((hand_pose.origin - lo_pose.origin).normalized(), (wt - lo_pose.origin).normalized())
	sk.set_bone_global_pose(_lower, Transform3D(Basis(turn_l) * lo_pose.basis, lo_pose.origin))
