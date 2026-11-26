class_name WorldMap
extends CanvasLayer
## The world map (M): the zone grid around the hero. Visited zones show their name, type and
## difficulty; their neighbors show only the type's color (seen from the border); the rest is
## unknown. Doesn't pause the game.

const RADIUS := 4                 ## cells shown in each direction
const CELL := 94.0
const COLORS := {
	"grassland": Color(0.36, 0.58, 0.3), "north": Color(0.82, 0.87, 0.93), "desert": Color(0.85, 0.7, 0.42),
	"ancient": Color(0.93, 0.8, 0.52), "mediterranean": Color(0.45, 0.66, 0.8), "unholy": Color(0.42, 0.3, 0.46),
}

var player: Player
var seed := 1
var _canvas: Control
var _pan := Vector2i.ZERO          ## the view moved by the arrow keys (cells)
var _arrows := {}                  ## action -> its arrow-key events, taken out while the map is open
const ARROWS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


func _ready() -> void:
	layer = 6
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		_show(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("menu"):
		_show(false)
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed:
		# The arrow keys scroll the map a zone at a time.
		var k := (event as InputEventKey).physical_keycode
		var d: Vector2i = {KEY_UP: Vector2i(0, -1), KEY_DOWN: Vector2i(0, 1), KEY_LEFT: Vector2i(-1, 0), KEY_RIGHT: Vector2i(1, 0)}.get(k, Vector2i.ZERO)
		if d != Vector2i.ZERO:
			_pan += d
			get_viewport().set_input_as_handled()


## Opening re-centres on the hero; while open the arrow keys scroll the map, not the hero (their
## events are taken out of the movement actions and put back on closing; WASD still moves).
func _show(on: bool) -> void:
	visible = on
	_pan = Vector2i.ZERO
	for action in ["move_forward", "move_back", "turn_left", "turn_right"]:
		if on:
			var keep := []
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey and (ev as InputEventKey).physical_keycode in ARROWS:
					keep.append(ev)
					InputMap.action_erase_event(action, ev)
			_arrows[action] = keep
		else:
			for ev in _arrows.get(action, []):
				InputMap.action_add_event(action, ev)
	if not on:
		_arrows.clear()


func _process(_dt: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _draw_map() -> void:
	if player == null:
		return
	var vp := _canvas.size
	var span := CELL * (2 * RADIUS + 1)
	var origin := (vp - Vector2(span, span)) / 2.0
	_canvas.draw_rect(Rect2(origin - Vector2(20, 60), Vector2(span + 40, span + 110)), Color(0.06, 0.05, 0.04, 0.92))
	var font := _canvas.get_theme_default_font()
	_canvas.draw_string(font, origin + Vector2(0, -24), "World map", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.45))
	var hero_cell := Vector2i(roundi(player.global_position.x / Terrain.SIZE), roundi(player.global_position.z / Terrain.SIZE))
	var here := hero_cell + _pan
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var cell := here + Vector2i(dx, dz)
			var r := Rect2(origin + Vector2(dx + RADIUS, dz + RADIUS) * CELL, Vector2(CELL, CELL)).grow(-2)
			var key := Quests.key_of(cell)
			var known := player.visited.has(key)
			var seen := known or _next_to_visited(cell)
			if not seen:
				_canvas.draw_rect(r, Color(0.12, 0.11, 0.1))
				continue
			var type := ZoneTypes.type_at(cell, seed)
			var col: Color = COLORS.get(type, Color.GRAY)
			_canvas.draw_rect(r, col if known else col.darkened(0.55))
			if type == "ancient":
				var c := r.get_center() + Vector2(0, 14)
				_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(14, 8), c + Vector2(-14, 8)]), col.darkened(0.35))
			var ink := Color(0.1, 0.08, 0.06) if col.get_luminance() > 0.45 or not known else Color(0.95, 0.92, 0.85)
			if known:
				var info: Dictionary = ZoneTypes.TYPES[type]
				var name := ZoneNames.make(info.names, hash([seed, cell.x, cell.y]))
				_canvas.draw_multiline_string(font, r.position + Vector2(5, 16), name, HORIZONTAL_ALIGNMENT_LEFT, CELL - 10, 12, 4, ink)
				_canvas.draw_string(font, r.position + Vector2(5, CELL - 10), "%s  %d" % [info.name, ZoneTypes.difficulty(cell)], HORIZONTAL_ALIGNMENT_LEFT, CELL - 10, 11, ink)
			else:
				_canvas.draw_string(font, r.get_center() + Vector2(-5, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.85, 0.7))
			if cell == ZoneTypes.home:
				_canvas.draw_rect(r.grow(-3), Color(1, 0.85, 0.4), false, 2.0)
	# The hero inside the current cell (when it is in view).
	var local := Vector2(player.global_position.x, player.global_position.z) / Terrain.SIZE - Vector2(here)
	if absf(local.x) <= RADIUS + 0.5 and absf(local.y) <= RADIUS + 0.5:
		var p := origin + (Vector2(RADIUS, RADIUS) + local + Vector2(0.5, 0.5)) * CELL
		_canvas.draw_circle(p, 6.0, Color(0, 0, 0))
		_canvas.draw_circle(p, 4.5, Color(1, 1, 1))
	_canvas.draw_string(font, origin + Vector2(0, span + 30), "North is up. Gold frame: where you started. Difficulty rises outward. Arrow keys scroll, M or Esc closes.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.78, 0.7))


func _next_to_visited(cell: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if player.visited.has(Quests.key_of(cell + d)):
			return true
	return false
