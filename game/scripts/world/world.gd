class_name World
extends RefCounted
## Shared references between hero, enemies and HUD (one world at a time).

static var player: Player
static var zones: ZoneManager
static var view_range := 160.0
static var fog_end := 0.0     ## > 0: the world ends in thick fog at this distance (Low quality)
static var root: Node3D
static var enemies: Array[Enemy] = []
static var smokes: Array[Dictionary] = []    ## {pos: Vector3, radius: float, until: float, node}


## Floating combat text above a position (damage numbers, "Miss", XP). With `follow` it rises
## relative to that character, so it stays with them when they (or the camera) move instead of
## being left behind in the world.
## Floating combat text. sticky (crits, like WoW): it pops in large, shrinks back and stays put
## for a moment before it rises and fades.
static func float_text(pos: Vector3, text: String, color: Color, size := 48, follow: Node3D = null, sticky := false) -> void:
	if root == null:
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.font_size = size
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.0072
	root.add_child(l)
	var start := pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	var offset := start - follow.global_position if follow else Vector3.ZERO
	l.global_position = start
	var hold := 0.7 if sticky else 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	if sticky:
		l.render_priority = 1                       # over the other numbers
		l.scale = Vector3.ONE * 1.9
		tw.tween_property(l, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(k: float) -> void:
		var base := start
		if is_instance_valid(follow) and follow.is_inside_tree():
			base = follow.global_position + offset
		var rise := clampf((k * (1.1 + hold) - hold) / 1.1, 0.0, 1.0)
		l.global_position = base + Vector3(0, 1.4 * rise, 0), 0.0, 1.0, 1.1 + hold)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.4 + hold)
	tw.chain().tween_callback(l.queue_free)


## How far the world is drawn: vegetation and rocks to `view`, everything to `far`. Below 500 m
## the end is hidden by fog that thickens from a quarter of the way to full at the end (DayNight).
static func set_view(view: float, far: float) -> void:
	view_range = view
	fog_end = far * 0.92 if far < 500.0 else 0.0
	if player and player.camera:
		player.camera.far = far
	if zones:
		for z: Zone in zones.zones.values():
			if z.scatter:
				z.scatter.set_view(minf(view, float(z.info.get("view_range", 1000.0))))


## Terrain height at a world position (whichever zone it is in).
static func height_at(x: float, z: float) -> float:
	return zones.height_at(x, z) if zones else 0.0


static func in_smoke(pos: Vector3) -> bool:
	var t := Combatant.now()
	for s in smokes:
		if t < float(s.until) and pos.distance_to(s.pos) < float(s.radius):
			return true
	return false


static func add_smoke(pos: Vector3, radius: float, duration: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 1.2
	mi.mesh = sm
	var mat := ShaderMaterial.new()          # soft, swirling (shaders/smoke.gdshader)
	mat.shader = load("res://shaders/smoke.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	smokes.append({"pos": pos, "radius": radius, "until": Combatant.now() + duration, "node": mi})
	var tw := mi.create_tween()
	tw.tween_interval(duration - 1.0)
	tw.tween_method(func(a: float): mat.set_shader_parameter("alpha", a), 0.5, 0.0, 1.0)
	tw.tween_callback(mi.queue_free)
