class_name CreatureAnim
extends RefCounted
## Plays a rigged creature's clips (tools/pipeline/creature_rig.py, tools/build_creatures.sh)
## through an AnimationTree, like CharAnimator for humanoids: idle, walk and run loops by speed
## (and the deaths, held on their last frame, the body lying on the ground) on the whole body;
## attack and hit as one-shots over them. Standing still a one-shot plays on the whole body;
## moving, only on the bones that aren't legs or the root (neck, head, chest, tail, claws), so
## the legs keep their gait instead of the creature sliding along in an attack pose.

const BLEND := 0.2
const LOOPS := ["idle", "walk", "run"]
const SHOTS := ["attack", "hit"]
## Bones that stay on the gait while a one-shot plays on the move: the roots (quadruped Hips,
## bug Body, snake Root) and the legs (quadruped FL_up..HR_lo, bug Leg0L_0..).
const ROOTS := ["Hips", "Body", "Root"]

var player: AnimationPlayer
var tree: AnimationTree
var speeds := {"walk": 1.0, "run": 2.0}   ## m/s of each loop at rate 1 (<model>_rig.json)
var dead := false
var _state := "idle"
var _loco: AnimationNodeTransition
var _shot_until := 0.0
var _shot := ""
var _dead_until := 0.0
var _skip := 0
var _acc := 0.0


static func _is_leg(bone: String) -> bool:
	return bone.begins_with("Leg") or (bone.length() > 3 and bone.substr(0, 2) in ["FL", "FR", "HL", "HR"] and bone[2] == "_")


## The animator for a rigged creature scene, or null for a static (procedural) one. Without
## `with_tree` the clips play straight on the AnimationPlayer (test line-ups of single clips).
static func attach(scene: Node, glb_path: String, with_tree := true) -> CreatureAnim:
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null
	var ca := CreatureAnim.new()
	ca.player = players[0]
	var json := glb_path.get_basename() + ".json"
	if FileAccess.file_exists(json):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(json))
		if d is Dictionary:
			for k: String in d:
				ca.speeds[k] = maxf(float(d[k]), 0.1)
	for n in ca.player.get_animation_list():
		ca.player.get_animation(n).loop_mode = Animation.LOOP_LINEAR if n in LOOPS else Animation.LOOP_NONE
	if not with_tree:
		return ca
	ca.player.stop()
	ca._build_tree(scene)
	# Herds don't breathe in step.
	ca.tree.advance(randf() * ca.player.get_animation("idle").length)
	ca._skip = randi() % 4
	return ca


func _build_tree(scene: Node) -> void:
	var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var bt := AnimationNodeBlendTree.new()
	_loco = AnimationNodeTransition.new()
	_loco.xfade_time = BLEND
	var states := ["idle", "walk", "run", "death"]
	if player.has_animation("death2"):
		states.append("death2")
	for i in states.size():
		_loco.add_input(states[i])
		var a := AnimationNodeAnimation.new()
		a.animation = states[i]
		bt.add_node(states[i], a)
	bt.add_node("loco", _loco)
	for i in states.size():
		bt.connect_node("loco", i, states[i])
	bt.add_node("speed", AnimationNodeTimeScale.new())
	bt.connect_node("speed", 0, "loco")
	# Whole body (under) and the bones above the legs (over), each with its own clip picker.
	bt.add_node("full", _shot_node(bt, "pick_full"))
	bt.connect_node("full", 0, "speed")
	bt.connect_node("full", 1, "pick_full")
	var upper := _shot_node(bt, "pick")
	upper.filter_enabled = true
	var root := player.get_node(player.root_node)
	var skel_path := String(root.get_path_to(skel))
	for i in skel.get_bone_count():
		var b := skel.get_bone_name(i)
		if b not in ROOTS and not _is_leg(b):
			upper.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("upper", upper)
	bt.connect_node("upper", 0, "full")
	bt.connect_node("upper", 1, "pick")
	bt.connect_node("output", 0, "upper")
	tree = AnimationTree.new()
	tree.tree_root = bt
	player.get_parent().add_child(tree)
	tree.root_node = tree.get_path_to(root)
	tree.anim_player = tree.get_path_to(player)
	# Advanced by tick() (level of detail by distance and visibility), not every frame.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true


func _shot_node(bt: AnimationNodeBlendTree, pick_name: String) -> AnimationNodeOneShot:
	var pick := AnimationNodeTransition.new()
	for i in SHOTS.size():
		pick.add_input(SHOTS[i])
		var a := AnimationNodeAnimation.new()
		a.animation = SHOTS[i]
		bt.add_node(pick_name + "_" + SHOTS[i], a)
	bt.add_node(pick_name, pick)
	for i in SHOTS.size():
		bt.connect_node(pick_name, i, pick_name + "_" + SHOTS[i])
	var one := AnimationNodeOneShot.new()
	one.fadein_time = 0.08
	one.fadeout_time = 0.15
	return one


## Advances the clips: every frame up close, every 2nd or 4th frame further away, not at all
## off screen or far away (dozens of creatures per zone; skinning them all cost 5 FPS). A dying
## creature always plays its fall to the end.
func tick(dt: float, pos: Vector3) -> void:
	if tree == null:
		return
	_acc += dt
	var cam := tree.get_viewport().get_camera_3d()
	var step := 1
	if cam:
		var d := cam.global_position.distance_to(pos)
		var seen := cam.is_position_in_frustum(pos + Vector3(0, 0.5, 0)) or d < 4.0
		if (not seen or d > 90.0) and not (dead and _now() < _dead_until):
			return
		step = 1 if d < 25.0 else (2 if d < 50.0 else 4)
	_skip += 1
	if _skip % step != 0:
		return
	tree.advance(minf(_acc, 1.0))
	_acc = 0.0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _set_state(st: String, blend := BLEND) -> void:
	if st != _state:
		_state = st
		_loco.xfade_time = blend
		tree.set("parameters/loco/transition_request", st)


## Ground speed (m/s): idle, walk or run, played at the rate that matches the speed. Starting
## to move during a whole-body attack hands the legs back to the gait.
func move(speed: float) -> void:
	if dead or tree == null:
		return
	var st := "idle"
	var rate := 1.0
	if speed > 0.1:
		st = "walk" if speed < 3.0 else "run"
		rate = clampf(speed / float(speeds[st]), 0.5, 2.6)
		if tree.get("parameters/full/active"):
			tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_set_state(st)
	tree.set("parameters/speed/scale", rate)


## A one-shot ("attack", "hit"); a hit does not cut off an attack.
func shot(clip: String) -> void:
	if dead or tree == null or not player.has_animation(clip):
		return
	if clip == "hit" and _shot == "attack" and _now() < _shot_until:
		return
	_shot = clip
	_shot_until = _now() + player.get_animation(clip).length - 0.12
	tree.set("parameters/pick/transition_request", clip)
	tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if _state == "idle":
		tree.set("parameters/pick_full/transition_request", clip)
		tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif tree.get("parameters/full/active"):
		tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func die() -> void:
	if tree == null:
		return
	dead = true
	var clip := "death2" if randf() < 0.5 and player.has_animation("death2") else "death"
	for o in ["full", "upper"]:
		tree.set("parameters/%s/request" % o, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_set_state(clip, 0.1)
	tree.set("parameters/speed/scale", 1.0)
	_dead_until = _now() + player.get_animation(clip).length + 0.5


func reset() -> void:
	if tree == null:
		return
	dead = false
	_shot_until = 0.0
	for o in ["full", "upper"]:
		tree.set("parameters/%s/request" % o, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_set_state("idle", 0.0)
