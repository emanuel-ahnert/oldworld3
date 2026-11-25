class_name Minimap
extends Control
## Map around the hero (north up, the hero in the middle), drawn from the loaded zones' data (no
## extra camera): rim, roads, lakes, settlement, shrines, crossings, nearby enemies and the
## hero's arrow. Neighbouring zones continue across the border.

const SIZE_PX := 230.0
const SPAN := 260.0          ## m across the map

var player: Player
var _view: Control           ## the map square (clips what lies outside it)
var _center := Vector2.ZERO  ## the hero's position (x, z) this frame


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = Control.new()
	_view.size = size
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_map)
	add_child(_view)


func _process(_dt: float) -> void:
	queue_redraw()
	_view.queue_redraw()


## World (x, z) -> map pixels.
func _w(world: Vector2) -> Vector2:
	return (world - _center) * (SIZE_PX / SPAN) + Vector2(SIZE_PX, SIZE_PX) / 2


func _draw() -> void:
	if player == null or World.zones == null:
		return
	var z := World.zones.zone_at(player.global_position)
	if z == null:
		return
	draw_string(get_theme_default_font(), Vector2(4, SIZE_PX + 16), z.zone_name, HORIZONTAL_ALIGNMENT_LEFT, SIZE_PX, 14, Color(1, 0.9, 0.6))


func _draw_map() -> void:
	if player == null or World.zones == null:
		return
	_center = Vector2(player.global_position.x, player.global_position.z)
	var v := _view
	var k := SIZE_PX / SPAN
	v.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE_PX, SIZE_PX)), Color(0.1, 0.1, 0.1, 0.8))
	var zones: Array = World.zones.zones.values()
	for z: Zone in zones:
		if z.terrain == null:
			continue
		var o := Vector2(z.position.x, z.position.z)
		if o.distance_to(_center) > Terrain.SIZE + SPAN:
			continue
		var ground := Color(0.33, 0.45, 0.25, 0.85)
		match z.type:
			"north":
				ground = Color(0.8, 0.85, 0.9, 0.85)
			"desert":
				ground = Color(0.8, 0.68, 0.45, 0.85)
		v.draw_rect(Rect2(_w(o - Vector2(200, 200)), Vector2(400, 400) * k), ground)
	for z: Zone in zones:
		if z.terrain == null:
			continue
		var o := Vector2(z.position.x, z.position.z)
		if o.distance_to(_center) > Terrain.SIZE + SPAN:
			continue
		var t := z.terrain
		for l in t.lakes:
			v.draw_circle(_w(o + l.center), float(l.radius) * k, Color(0.75, 0.85, 0.95) if t.frozen else Color(0.25, 0.45, 0.7))
		for road in t.roads:
			var pts := PackedVector2Array()
			for q in road:
				pts.append(_w(o + q))
			v.draw_polyline(pts, Color(0.42, 0.43, 0.46) if z.type == "north" else Color(0.55, 0.42, 0.3), 2.0)
		for c in t.crossings:
			v.draw_circle(_w(o + c), 4.0, Color(1, 0.9, 0.5))
		v.draw_rect(Rect2(_w(o + Vector2(-12, -38)), Vector2(14, 14) * k), Color(0.95, 0.85, 0.6))     # inn
		for ch in z.chests:
			var cw := Vector2(ch.global_position.x, ch.global_position.z)
			if not ch.opened and cw.distance_to(_center) < 40.0:
				v.draw_rect(Rect2(_w(cw) - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.8, 0.2))
		for c in z.landmarks:
			var m := _w(o + Vector2(c.x, c.z))
			v.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -6), m + Vector2(6, 4), m + Vector2(-6, 4)]), Color(0.9, 0.78, 0.5))
		for s in Settlement.shrine_spots(t):
			v.draw_circle(_w(o + Vector2(s.x, s.z)), 3.0, Color(0.5, 0.75, 1.0))
		for e in z.enemies:
			if e.stats.dead or not e.visible:
				continue
			var ew := Vector2(e.global_position.x, e.global_position.z)
			if e.champion != "":
				v.draw_circle(_w(ew), 5.0, Color(0, 0, 0))
				v.draw_circle(_w(ew), 3.5, Color(1, 0.55, 0.1))
			elif ew.distance_to(_center) < 120.0:
				v.draw_circle(_w(ew), 2.0, Color(1, 0.3, 0.25) if e.state == Enemy.State.CHASE else Color(0.95, 0.75, 0.3))
	# The hero in the middle: an arrow in the facing direction (-Z forward).
	var p := Vector2(SIZE_PX, SIZE_PX) / 2
	var f := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
	var r := Vector2(-f.y, f.x)
	v.draw_colored_polygon(PackedVector2Array([p + f * 8.0, p - f * 5.0 + r * 5.0, p - f * 5.0 - r * 5.0]), Color(1, 1, 1))
	v.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE_PX, SIZE_PX)), Color(0.55, 0.45, 0.3), false, 2.0)
