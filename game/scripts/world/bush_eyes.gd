class_name BushEyes
extends Node3D
## Eyes in the bushes (Unholy lands): now and then a pair of faint glowing eyes flares up in a bush
## ahead of the hero, stares for a moment and is gone. Never in a bush the hero is close to
## (NEAR): eyes that are open close at once when the hero comes nearer. Only works while the
## hero is in or near this zone (Scatter adds one per zone with "eyes").

const NEAR := 13.0           ## no eyes this close to the hero
const FAR := 55.0            ## nor farther away than this
const MAX_OPEN := 2
static var test := false     ## --eyes: many eyes, often (screenshots)

var spots: Array = []        ## [zone-local position of the bush, bush height]
var _next := 0.0
var _open: Array = []        ## [node, bush global position]
static var _eye_mat: StandardMaterial3D
static var _halo_mat: StandardMaterial3D


func _process(dt: float) -> void:
	var p := World.player
	if p == null or spots.is_empty():
		return
	var hero := p.global_position
	for k in range(_open.size() - 1, -1, -1):
		var o: Array = _open[k]
		if not is_instance_valid(o[0]):
			_open.remove_at(k)
		elif hero.distance_to(o[1]) < NEAR and not o[0].has_meta("closing"):
			_close(o[0], 0.05)
	_next -= dt
	if _next > 0.0:
		return
	_next = randf_range(0.05, 0.2) if test else randf_range(1.5, 5.0)
	if _open.size() >= (12 if test else MAX_OPEN) or p.camera == null:
		return
	# Zone is 512 m wide: skip when the hero is far from this zone.
	var local := to_local(hero)
	if absf(local.x) > Terrain.SIZE / 2 + FAR or absf(local.z) > Terrain.SIZE / 2 + FAR:
		return
	var look := -p.camera.global_transform.basis.z
	look.y = 0.0
	look = look.normalized()
	for _try in 24:
		var s: Array = spots[randi() % spots.size()]
		var pos := to_global(s[0])
		var d := pos - hero
		d.y = 0.0
		var dist := d.length()
		if dist < NEAR + 2.0 or dist > FAR or d.normalized().dot(look) < 0.55:
			continue
		_flare(pos, float(s[1]), hero)
		return


func _flare(bush: Vector3, h: float, hero: Vector3) -> void:
	_ensure_materials()
	var to_hero := hero - bush
	to_hero.y = 0.0
	to_hero = to_hero.normalized()
	var root := Node3D.new()
	add_child(root)
	root.global_position = bush + Vector3.UP * h * randf_range(0.4, 0.55) + to_hero * h * 0.72
	root.look_at(root.global_position - to_hero, Vector3.UP)   # -Z away from the hero: eyes face +Z
	var lids := Node3D.new()                                     # scaled in y to open and blink
	lids.scale = Vector3(1, 0.05, 1)
	root.add_child(lids)
	var gap := 0.12 * randf_range(0.9, 1.2)
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.065
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _eye_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.22)
	quad.material = _halo_mat
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = sphere
		e.position = Vector3(side * gap, 0, 0)
		e.scale = Vector3(1.5, 0.75, 1)                  # almond-shaped, slanted down to the middle
		e.rotation.z = side * 0.3
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lids.add_child(e)
		var halo := MeshInstance3D.new()
		halo.mesh = quad
		halo.position = Vector3(side * gap, 0, 0.02)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lids.add_child(halo)
	_open.append([root, bush])
	# Flare up (open fast, the halo slightly overshooting), stare, maybe blink, close.
	var tw := root.create_tween()
	tw.tween_property(lids, "scale", Vector3(1.1, 1.1, 1), 0.1)
	tw.tween_property(lids, "scale", Vector3.ONE, 0.12)
	tw.tween_interval(3.0 if test else randf_range(0.25, 0.6))
	if randf() < 0.4:
		tw.tween_property(lids, "scale", Vector3(1, 0.05, 1), 0.06)
		tw.tween_property(lids, "scale", Vector3.ONE, 0.06)
		tw.tween_interval(randf_range(0.2, 0.5))
	tw.tween_callback(_close.bind(root, 0.1))


func _close(root: Node3D, time: float) -> void:
	if root.has_meta("closing"):
		return
	root.set_meta("closing", true)
	var lids: Node3D = root.get_child(0)
	var tw := root.create_tween()
	tw.tween_property(lids, "scale", Vector3(1, 0.02, 1), time)
	tw.tween_callback(root.queue_free)


static func _ensure_materials() -> void:
	if _eye_mat:
		return
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(0.72, 0.82, 0.38)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_color = Color(0.45, 0.75, 0.15, 0.3)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_halo_mat.albedo_texture = tex
