class_name WeaponTrail
extends MeshInstance3D
## A fading ribbon behind the blade while a swing cuts (WoW style), so a fast blow reads as an
## arc. Samples the blade's base and tip every frame during the clip's cutting window
## (WINDOWS) and draws a strip through the last samples, smoothed with Catmull-Rom curves
## (frames are far apart at low frame rates), fading out with age.

## Clip -> [start, end] of the cutting part in seconds (tools/pipeline/skeleton.py keys at 24 fps).
const WINDOWS := {"attack1": [0.24, 0.52], "attack2": [0.24, 0.52], "attack3": [0.2, 0.36], "strike": [0.32, 0.58]}
const LIFE := 0.3            ## seconds a sample stays visible
const SUB := 4               ## curve points between two samples

var weapon: Node3D           ## the held model (its blade runs from `base` to `tip`, local)
var base := Vector3.ZERO
var tip := Vector3(0, 0, 1)
var color := Color(1.0, 0.97, 0.9, 0.6)
var sustain := false          ## samples all the time (the warrior's Whirlwind), not just in swings

var _im := ImmediateMesh.new()
var _samples: Array = []     ## [time, base (global), tip (global)]
var _start := -1.0
var _window := [0.0, 0.0]
static var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.vertex_color_use_as_albedo = true
		_mat.no_depth_test = false
	material_override = _mat


## Blade ends in the weapon model's space: the long axis of its bounds, the tip at the end
## away from the grip (the model's origin).
func fit(model: Node3D) -> void:
	weapon = model
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var xf := _relative(mi, model)
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var axis := box.get_longest_axis_index()
	var lo := box.position[axis]
	var hi := box.end[axis]
	var c := box.get_center()
	var a := c
	var b2 := c
	a[axis] = lo
	b2[axis] = hi
	# The grip is near the origin: the far end is the tip; the blade starts a fifth of the way.
	if absf(lo) > absf(hi):
		var t := a
		a = b2
		b2 = t
	tip = b2
	base = a.lerp(b2, 0.25)


func _relative(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## A swing started (CharAnimator.play_shot): sample during its cutting window.
func swing(clip: String) -> void:
	if not WINDOWS.has(clip):
		return
	_start = Time.get_ticks_msec() / 1000.0
	_window = WINDOWS[clip]


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if weapon and is_instance_valid(weapon) and _start >= 0.0:
		var t := now - _start
		if (sustain or (t >= float(_window[0]) and t <= float(_window[1]))) and weapon.is_visible_in_tree():
			var g := weapon.global_transform
			_samples.append([now, g * base, g * tip])
		elif t > float(_window[1]) and not sustain:
			_start = -1.0
	elif sustain and weapon and is_instance_valid(weapon) and weapon.is_visible_in_tree():
		var g := weapon.global_transform
		_samples.append([now, g * base, g * tip])
	while not _samples.is_empty() and now - float(_samples[0][0]) > LIFE:
		_samples.pop_front()
	_im.clear_surfaces()
	if _samples.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _samples.size()
	for i in n - 1:
		var p0: Array = _samples[maxi(i - 1, 0)]
		var p1: Array = _samples[i]
		var p2: Array = _samples[i + 1]
		var p3: Array = _samples[mini(i + 2, n - 1)]
		for k in SUB:
			var s := float(k) / SUB
			var age := now - lerpf(float(p1[0]), float(p2[0]), s)
			var a := clampf(1.0 - age / LIFE, 0.0, 1.0)
			var col := Color(color.r, color.g, color.b, color.a * a)
			var bpos := _cr(p0[1], p1[1], p2[1], p3[1], s)
			var tpos := _cr(p0[2], p1[2], p2[2], p3[2], s)
			_im.surface_set_color(Color(col.r, col.g, col.b, col.a * 0.15))
			_im.surface_add_vertex(bpos)
			_im.surface_set_color(col)
			_im.surface_add_vertex(tpos)
	var last: Array = _samples[n - 1]
	_im.surface_set_color(Color(color.r, color.g, color.b, 0.0))
	_im.surface_add_vertex(last[1])
	_im.surface_set_color(color)
	_im.surface_add_vertex(last[2])
	_im.surface_end()



static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
