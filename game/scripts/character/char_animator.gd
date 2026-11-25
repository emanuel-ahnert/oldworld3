class_name CharAnimator
extends RefCounted
## Animation tree for humanoids on the shared skeleton (hero, bandits, goblins):
## locomotion (idle, walk, run, jump, sit, death) on the whole body; attacks, casts and hit
## reactions as one-shots. Standing still a one-shot plays on the whole body (the hips and legs
## drive the blow); moving, only on the upper body so the legs keep running. Two one-shots fire
## together for that: the whole-body one under the upper-body one, and the whole-body one fades
## out as soon as the character starts moving.

const UPPER := ["Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const LOOPING := ["idle", "walk", "run", "ready"]
## Ground speed (m/s) each locomotion clip covers at playback rate 1, so feet don't slide:
## rate = speed / CLIP_SPEED. Printed by tools/pipeline/anim_dev.py on export ("speed").
const CLIP_SPEED := {"run": 7.0, "walk": 1.6}
## The hand-keyed jump clip (0.65 s, tucked after 0.12 s, last pose held) fits the ~0.65 s
## airtime at rate 1.
const JUMP_RATE := 1.0
const SHOTS := ["attack1", "attack2", "attack3", "strike", "hit", "cast", "release"]
## Standing states: one-shots play on the whole body here.
const STANDING := ["idle", "ready"]
## Whirlwind (warrior): the upper body holds a pose taken from a slash with the arms swung out
## (WHIRL_CLIP at WHIRL_AT of its length) while the hero's model spins (player.gd).
const WHIRL_CLIP := "attack2"
static var WHIRL_AT := 0.6

signal shot_started(name: String)

var tree: AnimationTree
var _state := "idle"
var _loco: AnimationNodeTransition
var _shot := ""             ## the last one-shot started
var _has := {}               ## clip name -> true for the clips this body has


func _init(body: Node3D) -> void:
	var ap: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
	var skel: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var lib := ap.get_animation_library("")
	for n in lib.get_animation_list():
		_has[String(n)] = true
	for n in lib.get_animation_list():
		lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR if n in LOOPING else Animation.LOOP_NONE
	ap.stop()

	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeTransition.new()
	loco.xfade_time = 0.2
	_loco = loco
	var states := ["idle", "walk", "run", "death"]
	for extra in ["jump", "sit", "ready", "death2"]:
		if lib.has_animation(extra):
			states.append(extra)
	for i in states.size():
		loco.add_input(states[i])
		var a := AnimationNodeAnimation.new()
		a.animation = states[i]
		bt.add_node(states[i], a)
	bt.add_node("loco", loco)
	for i in states.size():
		bt.connect_node("loco", i, states[i])
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "loco")

	# Whole body (under) and upper body (over), each with its own clip picker.
	bt.add_node("full", _shot_node(bt, "pick_full"))
	bt.connect_node("full", 0, "speed")
	bt.connect_node("full", 1, "pick_full")
	var one := _shot_node(bt, "pick")
	one.filter_enabled = true
	var root := ap.get_node(ap.root_node)
	var skel_path := String(root.get_path_to(skel))
	for b in UPPER:
		if skel.find_bone(b) >= 0:
			one.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("oneshot", one)
	bt.connect_node("oneshot", 0, "full")
	bt.connect_node("oneshot", 1, "pick")
	# Over everything: the Whirlwind pose on the upper body, faded in and out (set_whirl).
	var whirl_out := "oneshot"
	if lib.has_animation(WHIRL_CLIP):
		lib.add_animation("whirl", _pose_of(lib.get_animation(WHIRL_CLIP), WHIRL_AT))
		var wa := AnimationNodeAnimation.new()
		wa.animation = "whirl"
		bt.add_node("whirl", wa)
		var mix := AnimationNodeBlend2.new()
		mix.filter_enabled = true
		for b in UPPER:
			if skel.find_bone(b) >= 0:
				mix.set_filter_path(NodePath(skel_path + ":" + b), true)
		bt.add_node("whirl_mix", mix)
		bt.connect_node("whirl_mix", 0, "oneshot")
		bt.connect_node("whirl_mix", 1, "whirl")
		whirl_out = "whirl_mix"
		_has["whirl"] = true
	bt.connect_node("output", 0, whirl_out)

	tree = AnimationTree.new()
	tree.tree_root = bt
	ap.get_parent().add_child(tree)
	tree.root_node = tree.get_path_to(root)
	tree.anim_player = tree.get_path_to(ap)
	tree.active = true


## A looping one-key clip: `src` held at `frac` of its length.
static func _pose_of(src: Animation, frac: float) -> Animation:
	var t := src.length * frac
	var out := Animation.new()
	out.length = 0.1
	out.loop_mode = Animation.LOOP_LINEAR
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		var j := out.add_track(ty)
		out.track_set_path(j, src.track_get_path(i))
		match ty:
			Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(j, 0.0, src.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(j, 0.0, src.position_track_interpolate(i, t))
			Animation.TYPE_SCALE_3D:
				out.scale_track_insert_key(j, 0.0, src.scale_track_interpolate(i, t))
			Animation.TYPE_VALUE:
				out.track_insert_key(j, 0.0, src.value_track_interpolate(i, t))
	return out


var _whirl := 0.0


## Whirlwind pose on the upper body: fades toward `on` (call every frame while it changes).
func set_whirl(on: bool, dt: float) -> void:
	if not _has.get("whirl", false):
		return
	_whirl = move_toward(_whirl, 1.0 if on else 0.0, dt * 8.0)
	tree.set("parameters/whirl_mix/blend_amount", _whirl)


## A one-shot node whose shot input is a transition `pick` over the SHOTS clips.
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
	one.fadein_time = 0.06
	one.fadeout_time = 0.15
	return one


## Locomotion: state idle/walk/run/death and playback rate (negative plays backward).
func set_move(state: String, rate := 1.0) -> void:
	if not _has.get(state, false):
		state = "idle" if state == "ready" else state      # bodies without the combat stance
	if state == "death":
		# Two deaths (backward, or onto the knees and forward); keep the one already playing.
		if _state.begins_with("death"):
			state = _state
		elif _has.get("death2", false) and randf() < 0.5:
			state = "death2"
	if state not in STANDING and tree.get("parameters/full/active"):
		# Started moving mid-swing: the legs go back to the gait, the arms finish the blow.
		tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	if state != _state:
		# Into the jump almost at once (a slow blend makes it lag behind the take-off).
		_loco.xfade_time = 0.05 if state == "jump" else 0.2
		_state = state
		tree.set("parameters/loco/transition_request", state)
	tree.set("parameters/speed/scale", rate)


## One-shot (SHOTS): on the whole body when standing, else on the upper body only.
func play_shot(name: String) -> void:
	if name == "hit" and _shot != "hit" and tree.get("parameters/oneshot/active"):
		return               # a flinch doesn't cut off a swing or a cast
	_shot = name
	shot_started.emit(name)
	tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if not _has.get(name, false):
		name = "attack1" if name == "attack3" else name    # bodies exported before attack3
	tree.set("parameters/pick/transition_request", name)
	if _state in STANDING:
		tree.set("parameters/pick_full/transition_request", name)
		tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif tree.get("parameters/full/active"):
		tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func is_dead_state() -> bool:
	return _state.begins_with("death")
