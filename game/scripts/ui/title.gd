extends Control
## Title screen in Oldworld2's style (design/game-design.md, 7.4), made for the keyboard:
##   Main page: Continue (if a save exists), New game, Quit.
##   New game:  Class < … >, Zone < … >, Seed, Start, Back, with the class's description,
##              affinities and first abilities, and the class's hero standing on the right.
##   Confirm:   starting a new game replaces the save.
## Keys: Up/Down or W/S move the cursor, Left/Right or A/D change a value, Enter or Space
## selects, Escape or B goes back, digits type the seed (Backspace deletes). The mouse works too
## (hover moves the cursor, click selects). Test runs with command line arguments (see main.gd)
## skip this screen.

enum Page { MAIN, SETUP, CONFIRM }
const ROWS := ["Class", "Zone", "Seed", "Start", "Back"]
const CLASS_IDS := ["warrior", "mage", "rogue", "priest", "paladin", "warlock", "hunter", "shaman", "druid"]
const GILT := Color(0.95, 0.8, 0.45)
const INK := Color(0.95, 0.92, 0.86)
const FADED := Color(0.72, 0.68, 0.6)

var _page := Page.MAIN
var _opts: GameMenu              ## the options (GameMenu's page), opened from the main page
var _cursor := 0
var _class := 0
var _zone := 0
var _seed := str(Game.DEFAULT_SEED)
var _seed_typed := false          ## the first digit replaces the default seed
var _has_save := false
var _shot := ""
var _frames := 0
var _panel: PanelContainer
var _rows: VBoxContainer
var _info: VBoxContainer
var _preview: SubViewportContainer
var _preview_vp: SubViewport
var _hero: Humanoid
var _hero_class := ""
var _hint: Label
var _pic: TextureRect
var _pic_path := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_shot = args[1] if args.size() == 2 and args[0] == "--title-shot" else ""
	if not args.is_empty() and _shot == "":
		Game.seed = 1
		for i in args.size():
			if args[i] == "--seed" and i + 1 < args.size():
				Game.seed = int(args[i + 1])
			if args[i] == "--class" and i + 1 < args.size():
				Game.cls = args[i + 1]
		Game.loaded = {}
		Game.home = Vector2i.ZERO
		if "--continue" in args and Game.has_save():
			Game.loaded = Game.read_save()
			Game.seed = int(Game.loaded.get("seed", 1))
			Game.cls = String(Game.loaded.get("class", "warrior"))
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameMenu.apply_volumes()
	if _shot == "":
		var m := AudioStreamPlayer.new()
		var st: AudioStreamOggVorbis = load("res://assets/audio/music/title.ogg")
		st.loop = true
		m.stream = st
		m.volume_db = -8
		m.bus = "Music"
		add_child(m)
		m.play()
		tree_exiting.connect(func():       # a stream playing at exit leaks (engine warnings)
			m.stop()
			m.stream = null)
	_has_save = Game.has_save()
	_class = maxi(0, CLASS_IDS.find(Game.cls))
	_zone = maxi(0, ZoneTypes.START_TYPES.find(Game.start_type))
	_build()
	_refresh()


# --- layout ----------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# A picture from the game itself (the pyramids at dusk, made with --nohud).
	# The picture follows the chosen start zone on the new-game page (title_<type>.jpg, made
	# with --nohud in each zone type); the main page shows the zone of the saved game, or the
	# pyramids (title_bg.jpg) without one.
	_pic = TextureRect.new()
	_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_pic)
	_has_save = Game.has_save()
	_set_background(_main_background())
	var logo := Label.new()
	logo.text = "Oldworld3"
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_top = 70
	logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_size_override("font_size", 84)
	logo.add_theme_color_override("font_color", GILT)
	logo.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04))
	logo.add_theme_constant_override("outline_size", 14)
	add_child(logo)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	_panel = _fancy_panel()
	row.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	col.add_child(_rows)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 2)
	col.add_child(_info)

	# The chosen class's hero, standing in a frame on the right (its own little 3D world).
	var frame := _fancy_panel()
	row.add_child(frame)
	_preview = SubViewportContainer.new()
	_preview.custom_minimum_size = Vector2(260, 400)
	_preview.stretch = true
	frame.add_child(_preview)
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	_preview.add_child(_preview_vp)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.0, -3.6)
	_preview_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 160, 0)
	sun.light_energy = 1.4
	_preview_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.68)
	env.environment.ambient_light_energy = 0.8
	_preview_vp.add_child(env)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -60
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", INK)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 6)
	add_child(_hint)


## Main page: the zone the saved game continues in (its type's picture), else the pyramids.
func _main_background() -> String:
	if _has_save:
		var save := Game.read_save()
		var p: Array = save.get("pos", [])
		if p.size() == 3:
			var cell := Vector2i(roundi(float(p[0]) / Terrain.SIZE), roundi(float(p[2]) / Terrain.SIZE))
			var path := "res://assets/ui/title_%s.jpg" % ZoneTypes.type_at(cell, int(save.get("seed", 1)))
			if ResourceLoader.exists(path):
				return path
	return "res://assets/ui/title_bg.jpg"


func _set_background(path: String) -> void:
	if path == _pic_path or not ResourceLoader.exists(path):
		return
	_pic_path = path
	_pic.texture = load(path)
	_pic.modulate.a = 0.4
	_pic.create_tween().tween_property(_pic, "modulate:a", 1.0, 0.35)


func _fancy_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.07, 0.05, 0.86)
	st.border_color = Color(0.7, 0.55, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(22)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 8
	p.add_theme_stylebox_override("panel", st)
	return p


func _items() -> Array:
	match _page:
		Page.MAIN:
			return (["Continue"] if _has_save else []) + ["New game", "Options", "Quit"]
		Page.CONFIRM:
			return ["Start the new game", "Back"]
	return ROWS


## Rebuilds the rows and info text for the current page and cursor.
func _refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for c in _info.get_children():
		c.queue_free()
	var items := _items()
	_cursor = clampi(_cursor, 0, items.size() - 1)
	for i in items.size():
		var label: String = items[i]
		var value := ""
		if _page == Page.SETUP:
			match label:
				"Class":
					value = "<  %s  >" % Player.CLASSES[CLASS_IDS[_class]].name
				"Zone":
					value = "<  %s  >" % ZoneTypes.TYPES[ZoneTypes.START_TYPES[_zone]].name
				"Seed":
					value = _seed if _seed != "" else "random"
					if i == _cursor and _frames % 60 < 30:
						value += "_"
		if _page == Page.MAIN and label == "Continue":
			var save := Game.read_save()
			value = "%s, level %d" % [String(save.get("class", "warrior")).capitalize(), int(save.get("level", 1))]
		_rows.add_child(_row(i, label, value))
	_panel.custom_minimum_size = Vector2(520 if _page != Page.MAIN else 420, 0)
	_set_background(_main_background() if _page == Page.MAIN else "res://assets/ui/title_%s.jpg" % ZoneTypes.START_TYPES[_zone])
	var show_hero := _page != Page.MAIN
	_preview.get_parent().visible = show_hero
	if _page == Page.SETUP:
		var cid: String = CLASS_IDS[_class]
		var c: Dictionary = Player.CLASSES[cid]
		_sep()
		_line(c.desc, INK, 19)
		_line("Affinity: " + ", ".join(c.affinities), FADED, 16)
		var first := Player.abilities_of(cid).filter(func(a): return int(a.level) == 1).map(func(a): return a.name)
		_line("Starts with: " + ", ".join(first), FADED, 16)
		_line("Zone: " + _zone_text(), FADED, 16)
		_show_hero(cid)
	elif _page == Page.CONFIRM:
		_sep()
		_line("This replaces your saved game.", Color(1, 0.6, 0.5), 18)
	_hint.text = {
		Page.MAIN: "Up/Down choose    Enter select",
		Page.SETUP: "Up/Down choose    Left/Right change    digits type the seed    Enter select    Esc back",
		Page.CONFIRM: "Enter start    Esc back",
	}[_page]


func _zone_text() -> String:
	var t: String = ZoneTypes.START_TYPES[_zone]
	return "you start at the inn of the nearest %s zone (difficulty 1)" % ZoneTypes.TYPES[t].name


func _row(i: int, label: String, value: String) -> Control:
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
	l.text = label
	l.custom_minimum_size = Vector2(110 if _page == Page.SETUP else 0, 0)
	l.add_theme_font_size_override("font_size", 25)
	l.add_theme_color_override("font_color", GILT if i == _cursor else INK)
	h.add_child(l)
	if value != "":
		var v := Label.new()
		v.text = value
		v.add_theme_font_size_override("font_size", 25 if _page == Page.SETUP else 18)
		v.add_theme_color_override("font_color", INK if _page == Page.SETUP else FADED)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
	h.mouse_entered.connect(func():
		if _cursor != i:
			_cursor = i
			_refresh())
	h.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_cursor = i
			_select())
	return h


func _sep() -> void:
	var s := ColorRect.new()
	s.color = Color(0.7, 0.55, 0.3, 0.6)
	s.custom_minimum_size = Vector2(0, 1)
	_info.add_child(s)


func _line(text: String, color: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(470, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_info.add_child(l)


func _show_hero(cid: String) -> void:
	if cid == _hero_class:
		return
	_hero_class = cid
	if _hero:
		_hero.queue_free()
	_hero = Humanoid.new()
	_preview_vp.add_child(_hero)
	_hero.build(Player.look_of(cid))
	_hero.anim.set_move("idle")


# --- input -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or (_opts and _opts.visible):
		return
	var k := (event as InputEventKey).keycode
	var handled := true
	match k:
		KEY_UP, KEY_W:
			_cursor = (_cursor + _items().size() - 1) % _items().size()
		KEY_DOWN, KEY_S:
			_cursor = (_cursor + 1) % _items().size()
		KEY_LEFT, KEY_A:
			_change(-1)
		KEY_RIGHT, KEY_D:
			_change(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_select()
				return
		KEY_ESCAPE, KEY_B:
			if not event.echo:
				_back()
				return
		KEY_BACKSPACE:
			if _page == Page.SETUP and _seed != "":
				_seed = _seed.substr(0, _seed.length() - 1)
				_seed_typed = true
				_cursor = ROWS.find("Seed")
		_:
			var ch := (event as InputEventKey).unicode
			if _page == Page.SETUP and ch >= 48 and ch <= 57:
				if not _seed_typed:
					_seed = ""
					_seed_typed = true
				if _seed.length() < 9:
					_seed += char(ch)
				_cursor = ROWS.find("Seed")
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()
		_refresh()


func _change(d: int) -> void:
	if _page != Page.SETUP:
		return
	match ROWS[_cursor]:
		"Class":
			_class = (_class + d + CLASS_IDS.size()) % CLASS_IDS.size()
		"Zone":
			_zone = (_zone + d + ZoneTypes.START_TYPES.size()) % ZoneTypes.START_TYPES.size()


func _select() -> void:
	var item: String = _items()[_cursor]
	match _page:
		Page.MAIN:
			match item:
				"Continue":
					_continue()
					return
				"New game":
					_page = Page.SETUP
					_cursor = 0
				"Options":
					if _opts == null:
						_opts = GameMenu.new()
						_opts.options_only = true
						add_child(_opts)
						_opts.closed.connect(func(): _panel.visible = true)
					_panel.visible = false
					_opts.open()
					return
				"Quit":
					Game.quit(get_tree())
					return
		Page.SETUP:
			match item:
				"Class":
					_change(1)
				"Zone":
					_change(1)
				"Start":
					if _has_save:
						_page = Page.CONFIRM
						_cursor = 0
					else:
						_new_game()
						return
				"Back":
					_back()
					return
		Page.CONFIRM:
			if item == "Back":
				_back()
				return
			_new_game()
			return
	_refresh()


func _back() -> void:
	if _page == Page.CONFIRM:
		_page = Page.SETUP
		_cursor = ROWS.find("Start")
	elif _page == Page.SETUP:
		_page = Page.MAIN
		_cursor = 0
	_refresh()


func _continue() -> void:
	var save := Game.read_save()
	Game.seed = int(save.get("seed", 1))
	Game.cls = String(save.get("class", "warrior"))
	Game.loaded = save
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _new_game() -> void:
	Game.cls = CLASS_IDS[_class]
	Game.start_type = ZoneTypes.START_TYPES[_zone]
	Game.seed = int(_seed) if _seed.is_valid_int() else randi() % 1000000
	Game.home = ZoneTypes.nearest(Game.start_type, Game.seed)
	Game.loaded = {}
	Game.delete_save()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _process(dt: float) -> void:
	_frames += 1
	if _hero:
		_hero.rotation.y = sin(_frames / 120.0) * 0.35     # facing the camera, turning a little
	if _page == Page.SETUP and ROWS[_cursor] == "Seed" and _frames % 30 == 0:
		_refresh()                    # blinking text cursor
	if _shot != "":
		# Test: TITLE_KEYS="enter,down,right,enter" presses keys before the screenshot.
		var keys := OS.get_environment("TITLE_KEYS")
		var list := keys.split(",") if keys != "" else PackedStringArray()
		if _frames >= 4 and _frames < 4 + list.size():
			var ev := InputEventKey.new()
			ev.keycode = {"down": KEY_DOWN, "up": KEY_UP, "left": KEY_LEFT, "right": KEY_RIGHT, "enter": KEY_ENTER,
				"esc": KEY_ESCAPE, "1": KEY_1, "7": KEY_7, "back": KEY_BACKSPACE}[list[_frames - 4]]
			ev.unicode = ev.keycode if ev.keycode >= KEY_0 and ev.keycode <= KEY_9 else 0
			ev.pressed = true
			Input.parse_input_event(ev)
		if _frames == 24:
			print("TITLE page %d class %s zone %s seed %s" % [_page, CLASS_IDS[_class], ZoneTypes.START_TYPES[_zone], _seed])
		if _frames == 26:
			get_viewport().get_texture().get_image().save_png(_shot)
			get_tree().quit()
