class_name GameMenu
extends CanvasLayer
## The in-game menu (Esc): resume, options, save and back to the title, save and quit. Options
## (also from the title screen, options_only): quality, day and night, sound effects and music
## volume. Keyboard like the title screen (Oldworld2 style): Up/Down (W/S) choose, Left/Right
## (A/D) change a setting, Enter/Space select, Esc back/close; the mouse works too.
## Settings are stored in user://settings.cfg and applied at once.

const SETTINGS := "user://settings.cfg"
const QUALITY := {
	"Low": {"scale": 0.6, "shadow": 30.0, "clutter": [14.0, 0.35], "shadows": false,   # blob shadows instead
		"view": 100.0, "far": 180.0},
	"Medium": {"scale": 0.75, "shadow": 45.0, "clutter": [20.0, 0.55], "view": 160.0, "far": 600.0},
	"High": {"scale": 1.0, "shadow": 70.0, "clutter": [36.0, 1.3], "view": 160.0, "far": 600.0},
}
## clutter: radius m, density. view: m to the last trees, rocks and bushes; far: m to the end of
## the world drawn (Low: thick fog hides where it ends, World.set_view).

const GILT := Color(0.95, 0.8, 0.45)
const INK := Color(0.95, 0.92, 0.86)
const FADED := Color(0.72, 0.68, 0.6)
const MAIN_ITEMS := ["Resume", "Options", "Save and back to the title", "Save and quit"]
const OPTION_ITEMS := ["Quality", "Day and night", "Sound effects", "Music", "Back"]
const VOLUME_STEP := 10           ## % per Left/Right

var player: Player
var sun: DirectionalLight3D
var daynight: DayNight
var _panel: PanelContainer
var _rows: VBoxContainer
var _cursor := 0
var _options := false             ## on the options page
var options_only := false         ## opened from the title screen: only the options, no pausing
var _title: Label
signal closed


func _items() -> Array:
	return OPTION_ITEMS if _options else MAIN_ITEMS


## Volume in % (0–100) of "sfx" or "music", from the settings.
static func load_volume(kind: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return int(cfg.get_value("audio", kind, 100 if kind == "sfx" else 50))
	return 100 if kind == "sfx" else 50


## The "SFX" and "Music" buses (made here if missing) at the saved volumes.
static func apply_volumes() -> void:
	for kind in ["sfx", "music"]:
		var bus := "SFX" if kind == "sfx" else "Music"
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			i = AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
		var v := load_volume(kind)
		AudioServer.set_bus_mute(i, v <= 0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 1) / 100.0))


static func load_quality() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return String(cfg.get_value("video", "quality", "Medium"))
	return "Medium"


static func load_daynight() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return bool(cfg.get_value("video", "daynight", true))
	return true


static func apply_quality(name: String, viewport: Viewport, p_sun: DirectionalLight3D) -> void:
	var q: Dictionary = QUALITY.get(name, QUALITY.Medium)
	viewport.scaling_3d_scale = q.scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q.scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	if p_sun:
		p_sun.directional_shadow_max_distance = q.shadow
		p_sun.shadow_enabled = q.get("shadows", true)
	BlobShadow.enabled = not q.get("shadows", true)
	Clutter.set_quality(float(q.clutter[0]), float(q.clutter[1]))
	World.set_view(float(q.view), float(q.far))


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP     # nothing under the menu takes clicks
	add_child(dim)
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.07, 0.05, 0.9)
	st.border_color = Color(0.7, 0.55, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(22)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", st)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(520, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var t := Label.new()
	_title = t
	t.text = "Menu"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", GILT)
	box.add_child(t)
	_rows = VBoxContainer.new()
	box.add_child(_rows)
	var hint := Label.new()
	hint.text = "Up/Down choose    Left/Right or click change    Enter select    Esc close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", FADED)
	box.add_child(hint)
	visible = false


func open() -> void:
	visible = true
	if not options_only:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cursor = 0
	_options = options_only
	_refresh()


func close() -> void:
	if _options and not options_only:
		_options = false              # Esc on the options page: back to the menu
		_cursor = 1
		_refresh()
		return
	visible = false
	if not options_only:
		get_tree().paused = false
	closed.emit()


func _value(item: String) -> String:
	match item:
		"Quality":
			return "<  %s  >" % load_quality()
		"Day and night":
			return "<  %s  >" % ("on" if load_daynight() else "off (morning)")
		"Sound effects":
			return _bar(load_volume("sfx"))
		"Music":
			return _bar(load_volume("music"))
	return ""


## "<  ■■■■■■□□□□  60%  >"
func _bar(v: int) -> String:
	var n := v / VOLUME_STEP
	return "<  %s%s  %d%%  >" % ["■".repeat(n), "□".repeat(100 / VOLUME_STEP - n), v]


func _refresh() -> void:
	_title.text = "Options" if _options else "Menu"
	for c in _rows.get_children():
		c.queue_free()
	var ITEMS := _items()
	for i in ITEMS.size():
		var h := HBoxContainer.new()
		h.custom_minimum_size = Vector2(0, 40)
		h.add_theme_constant_override("separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		var gem := Label.new()
		gem.text = "◆" if i == _cursor else ""
		gem.custom_minimum_size = Vector2(28, 0)
		gem.add_theme_font_size_override("font_size", 20)
		gem.add_theme_color_override("font_color", GILT)
		h.add_child(gem)
		var l := Label.new()
		l.text = ITEMS[i]
		l.custom_minimum_size = Vector2(190 if _value(ITEMS[i]) != "" else 0, 0)
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", GILT if i == _cursor else INK)
		h.add_child(l)
		var v := _value(ITEMS[i])
		if ITEMS[i] in VOLUMES:
			_volume_bar(h, VOLUMES[ITEMS[i]])
		elif v != "":
			var vl := Label.new()
			vl.text = v
			vl.add_theme_font_size_override("font_size", 22)
			vl.add_theme_color_override("font_color", INK)
			h.add_child(vl)
		h.mouse_entered.connect(func():
			if _cursor != i:
				_cursor = i
				_refresh())
		h.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_cursor = i
				_select())
		_rows.add_child(h)


const VOLUMES := {"Sound effects": "sfx", "Music": "music"}
const BAR_W := 260.0


## A volume row's value: "<" and ">" step it, a click (or a drag) on the bar sets it to where
## the mouse is (rounded to whole %).
func _volume_bar(h: HBoxContainer, kind: String) -> void:
	var lt := _arrow("<", kind, -1)
	h.add_child(lt)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(BAR_W, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pct := Label.new()
	bar.draw.connect(func():
		var v := load_volume(kind) / 100.0
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(0.1, 0.09, 0.08, 0.9))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * v, bar.size.y)), GILT * Color(1, 1, 1, 0.85))
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), FADED, false, 1.5))
	bar.gui_input.connect(func(ev: InputEvent):
		var set_it: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT))
		if set_it:
			_store_volume(kind, roundi(clampf(ev.position.x / bar.size.x, 0.0, 1.0) * 100.0))
			if kind == "sfx" and ev is InputEventMouseButton:
				Audio.sfx("miss")
			pct.text = "%d%%" % load_volume(kind)
			bar.queue_redraw()
			bar.accept_event())
	h.add_child(bar)
	pct.text = "%d%%" % load_volume(kind)
	pct.custom_minimum_size = Vector2(64, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_font_size_override("font_size", 22)
	pct.add_theme_color_override("font_color", INK)
	h.add_child(pct)
	h.add_child(_arrow(">", kind, 1))


func _arrow(text: String, kind: String, step: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", INK)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_set_volume(kind, step)
			if kind == "sfx":
				Audio.sfx("miss")
			l.accept_event()
			_refresh.call_deferred())
	return l


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var handled := true
	var ITEMS := _items()
	match (event as InputEventKey).keycode:
		KEY_UP, KEY_W:
			_cursor = (_cursor + ITEMS.size() - 1) % ITEMS.size()
		KEY_DOWN, KEY_S:
			_cursor = (_cursor + 1) % ITEMS.size()
		KEY_LEFT, KEY_A:
			_change(-1)
		KEY_RIGHT, KEY_D:
			_change(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_select()
		KEY_ESCAPE:
			if not event.echo:
				close()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
		if visible:
			_refresh()


func _change(step: int) -> void:
	match _items()[_cursor]:
		"Quality":
			_cycle_quality(step)
		"Day and night":
			_toggle_daynight()
		"Sound effects":
			_set_volume("sfx", step)
			Audio.sfx("miss")           # a sample at the new volume
		"Music":
			_set_volume("music", step)


func _set_volume(kind: String, step: int) -> void:
	# Onto the step grid (a click may have left it at, say, 47%).
	var v := load_volume(kind)
	v = clampi((v / VOLUME_STEP + step) * VOLUME_STEP if step > 0 or v % VOLUME_STEP == 0 else v / VOLUME_STEP * VOLUME_STEP, 0, 100)
	_store_volume(kind, v)


func _store_volume(kind: String, v: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", kind, v)
	cfg.save(SETTINGS)
	apply_volumes()


func _select() -> void:
	match _items()[_cursor]:
		"Resume":
			close()
		"Options":
			_options = true
			_cursor = 0
		"Back":
			close()
		"Quality":
			_cycle_quality(1)
		"Day and night":
			_toggle_daynight()
		"Sound effects", "Music":
			_change(1)
		"Save and back to the title":
			Game.write_save(player)
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/title.tscn")
		"Save and quit":
			Game.write_save(player)
			Game.quit(get_tree())
	if visible:
		_refresh()


func _cycle_quality(step := 1) -> void:
	var names := QUALITY.keys()
	var next: String = names[(names.find(load_quality()) + step + names.size()) % names.size()]
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("video", "quality", next)
	cfg.save(SETTINGS)
	apply_quality(next, get_viewport(), sun)
	if daynight:
		daynight.apply()          # the fog for the new view range at once


func _toggle_daynight() -> void:
	var on := not load_daynight()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("video", "daynight", on)
	cfg.save(SETTINGS)
	if daynight:
		daynight.enabled = on
		daynight.apply()
