class_name Proportions
extends SkeletonModifier3D
## A different build on the shared skeleton (goblins: stubby): after the animation, every frame,
## the thighs (and with them the shins and feet) scaled by `legs`, the head by `head`. The
## Humanoid lowers itself by what the legs lose, so the feet stay on the ground.

var legs := 1.0
var head := 1.0

var _bones := {}


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["LeftUpperLeg", "RightUpperLeg", "Head"]:
		_bones[b] = sk.find_bone(b)


## How far the hips sink (in the body's units) with the legs scaled: what the hip joints lose.
func drop() -> float:
	var sk := get_skeleton()
	if sk == null or int(_bones.get("LeftUpperLeg", -1)) < 0:
		return 0.0
	return sk.get_bone_global_rest(int(_bones["LeftUpperLeg"])).origin.y * (1.0 - legs)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["LeftUpperLeg", "RightUpperLeg"]:
		if int(_bones.get(b, -1)) >= 0:
			sk.set_bone_pose_scale(int(_bones[b]), Vector3.ONE * legs)
	if int(_bones.get("Head", -1)) >= 0:
		sk.set_bone_pose_scale(int(_bones["Head"]), Vector3.ONE * head)
