class_name WhirlFx
extends Node3D
## Wind around a spinning warrior (Whirlwind): open cylinders with streaks spiralling up
## (shaders/whirl.gdshader), a dusty one at the feet. set_on() fades them in and out.
## The streaks turn with the hero (`turn`, set by player.gd every frame) at about half its speed,
## each band at its own drifting pace, its radius wobbling and its plane tipping (one side
## lower than the other, changing at random), so the wind looks a bit chaotic. Shaped like a
## tornado: the higher a band, the wider, and each one flares out toward its top.

## Bands, low to high: [bottom radius min, max, height min, max, center y min, max, follow,
## bands, spiral turns, tint]; the top radius is the bottom's times FLARE.
const KINDS := [
	[0.7, 0.85, 0.4, 0.55, 0.22, 0.28, 0.3, 6.0, 0.3, Color(0.72, 0.64, 0.5, 0.55)],
	[0.8, 0.95, 0.9, 1.2, 0.6, 0.75, 0.43, 4.0, 0.7, Color(0.85, 0.9, 0.95, 0.5)],
	[0.95, 1.15, 1.1, 1.5, 0.95, 1.15, 0.55, 3.0, 0.9, Color(0.92, 0.95, 1.0, 0.7)],
	[1.25, 1.45, 0.8, 1.1, 1.4, 1.6, 0.6, 3.0, 1.1, Color(0.92, 0.95, 1.0, 0.45)],
]
const FLARE := Vector2(1.35, 1.6)
## The funnel is built twice, each with its own random draw: [radius factor min, max, opacity].
## The outer one is fainter; the dust ring (KINDS[0]) only in the inner one, and the outer one
## skips the middle band (KINDS[2]): six bands were a bit busy.
const LAYERS := [[0.55, 0.65, 1.0], [0.75, 0.9, 0.65]]

var turn := 0.0               ## the hero's spin in turns (negative: clockwise from above)
var _mats: Array[ShaderMaterial] = []
var _follow: Array[float] = []    ## each band's base share of the spin
var _pace: Array[float] = []      ## its current pace factor (drifts toward _goal)
var _goal: Array[float] = []
var _phase: Array[float] = []     ## its own turn so far
var _rings: Array[MeshInstance3D] = []
var _tip: Array[Vector2] = []     ## its current tip (rotation x, z in radians), easing toward _tip_goal
var _tip_goal: Array[Vector2] = []
var _tip_max: Array[float] = []   ## how far it may tip
const TIP := 0.3                  ## the most a band tips (about 17°); the dust at the feet half
var _last_turn := 0.0
var _amount := 0.0
var _on := false
var _retarget := 0.0


func _ready() -> void:
	var shader: Shader = load("res://shaders/whirl.gdshader")
	for li in LAYERS.size():
		var layer: Array = LAYERS[li]
		for ki in KINDS.size():
			if li > 0 and ki in [0, 2]:
				continue
			_add_band(shader, KINDS[ki], randf_range(layer[0], layer[1]), layer[2], 0.5 if ki == 0 else 1.0)
	visible = false


func _add_band(shader: Shader, k: Array, scale: float, opacity: float, tip: float) -> void:
	var r := randf_range(k[0], k[1]) * scale
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = r
	cyl.top_radius = r * randf_range(FLARE.x, FLARE.y)
	cyl.height = randf_range(k[2], k[3])
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 40
	cyl.rings = 4
	var m := ShaderMaterial.new()
	m.shader = shader
	var tint: Color = k[9]
	tint.a *= opacity
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("bands", k[7])
	m.set_shader_parameter("tilt", float(k[8]) * randf_range(0.8, 1.25))
	m.set_shader_parameter("seed", randf() * 100.0)
	cyl.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position.y = randf_range(k[4], k[5]) * randf_range(0.9, 1.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mats.append(m)
	_rings.append(mi)
	_tip.append(Vector2.ZERO)
	_tip_goal.append(Vector2.ZERO)
	_tip_max.append(TIP * tip)
	_follow.append(k[6])
	_pace.append(1.0)
	_goal.append(1.0)
	_phase.append(randf())


func set_on(on: bool) -> void:
	_on = on


func _process(dt: float) -> void:
	_amount = move_toward(_amount, 1.0 if _on else 0.0, dt * (5.0 if _on else 3.0))
	visible = _amount > 0.0
	var step := turn - _last_turn
	_last_turn = turn
	if not visible:
		return
	# Every so often each band picks a new pace (70–135% of its base) and eases toward it.
	_retarget -= dt
	if _retarget <= 0.0:
		_retarget = randf_range(0.3, 0.7)
		for i in _goal.size():
			_goal[i] = randf_range(0.7, 1.35)
			if randf() < 0.5:
				# Tips a new way now and then: one side lower, the other higher.
				var lim := _tip_max[i]
				_tip_goal[i] = Vector2(randf_range(-lim, lim), randf_range(-lim, lim))
	for i in _mats.size():
		_pace[i] = lerpf(_pace[i], _goal[i], 1.0 - exp(-3.0 * dt))
		_tip[i] = _tip[i].lerp(_tip_goal[i], 1.0 - exp(-2.5 * dt))
		_rings[i].rotation = Vector3(_tip[i].x, 0.0, _tip[i].y)
		_phase[i] += step * _follow[i] * _pace[i]
		_mats[i].set_shader_parameter("strength", _amount)
		_mats[i].set_shader_parameter("turn", _phase[i])
