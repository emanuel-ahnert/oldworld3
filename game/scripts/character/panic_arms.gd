class_name PanicArms
extends SkeletonModifier3D
## Panic (Fear, Humanoid.set_panic): after the animation (a run), both arms are thrown up over
## the head and flail: the upper arms up and a little out, the forearms up, each swinging on its
## own beat. Faded in and out with `influence`.

var _bones := {}                   ## "LeftUpperArm" etc. -> index
var _left := Vector3.RIGHT         ## body directions in skeleton space (rest pose)
var _up := Vector3.UP
var _fwd := Vector3.FORWARD
var _t := 0.0


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]:
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
	_t += get_process_delta_time() if is_inside_tree() else 0.016
	for side: float in [1.0, -1.0]:
		var pre := "Left" if side > 0.0 else "Right"
		var ph := _t * 11.0 + (0.0 if side > 0.0 else 2.1)
		var out := _left * side
		# Up and out, waving to and fro (the flail).
		var upper_dir := (_up * 1.0 + out * 0.42 + _fwd * (0.12 + 0.28 * sin(ph)) + out * 0.15 * sin(ph * 0.7)).normalized()
		var lower_dir := (_up * 1.0 - out * 0.12 + _fwd * (0.2 + 0.35 * sin(ph + 1.2))).normalized()
		_aim(sk, int(_bones[pre + "UpperArm"]), int(_bones[pre + "LowerArm"]), upper_dir)
		_aim(sk, int(_bones[pre + "LowerArm"]), int(_bones[pre + "Hand"]), lower_dir)


## Turns bone `b` (global pose, skeleton space) so its child `c` lies along `dir` from it.
func _aim(sk: Skeleton3D, b: int, c: int, dir: Vector3) -> void:
	if b < 0 or c < 0:
		return
	var bp := sk.get_bone_global_pose(b)
	var cp := sk.get_bone_global_pose(c)
	var now := cp.origin - bp.origin
	if now.length() < 1e-4:
		return
	var turn := Quaternion(now.normalized(), dir)
	sk.set_bone_global_pose(b, Transform3D(Basis(turn) * bp.basis, bp.origin))
