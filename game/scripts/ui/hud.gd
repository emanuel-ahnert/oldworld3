class_name Hud
extends CanvasLayer
## HUD (design/game-design.md, section 6): hero and target frames, action bar with cooldowns,
## XP bar, money, stamina, messages, frame rate and the controls (F1 toggles them).

var player: Player
var _info: Label
var _help: Label
var _msg: Label
var _msg_until := 0.0
var _stamina: ProgressBar
var _hero: Dictionary
var _target: Dictionary
var _slots: Array = []
var _bar_box: HBoxContainer
var _xp: ProgressBar
var _cast: ProgressBar
var _cast_label: Label
var _map: Minimap
var _xp_label: Label
var _xp_text: Label
var _quests: Label
var _hero_auras: HFlowContainer
var _target_auras: HFlowContainer
var _auras_at := 0.0
var _combat: Control      ## the crossed swords while in combat
var _fresh := {}          ## ability id -> time until its slot stops glowing (just learned)


## WoW-style cooldown clock on an action button: a dark pie over the part of the cooldown that
## is still to run, shrinking clockwise from 12 o'clock, with a bright edge line.
class Sweep extends Control:
	var frac := 0.0:                    ## 1 = just started, 0 = ready
		set(v):
			if absf(v - frac) > 0.002 or (v == 0.0) != (frac == 0.0):
				frac = v
				queue_redraw()

	func _draw() -> void:
		if frac <= 0.0:
			return
		var c := size / 2.0
		var r := size.length()                       # past the corners: the pie covers the square
		var start := -PI / 2.0 + TAU * (1.0 - frac)  # the part already run (from the top) stays clear
		var pts := PackedVector2Array([c])
		var n := maxi(3, int(48 * frac))
		for k in n + 1:
			var a := start + TAU * frac * k / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var rect := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
		for poly in Geometry2D.intersect_polygons(pts, rect):
			draw_colored_polygon(poly, Color(0, 0, 0, 0.62))
		# The clock hand: from the center to the button's edge.
		var d := Vector2(cos(start), sin(start))
		var tx := INF if absf(d.x) < 1e-4 else ((size.x - c.x) / d.x if d.x > 0.0 else -c.x / d.x)
		var ty := INF if absf(d.y) < 1e-4 else ((size.y - c.y) / d.y if d.y > 0.0 else -c.y / d.y)
		draw_line(c, c + d * minf(tx, ty), Color(1, 0.9, 0.55, 0.85), 1.5)


## Two crossed swords (in combat), drawn: blades, cross-guards, grips and pommels, outlined.
class CombatIcon extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var dark := Color(0, 0, 0, 0.85)
		for pass_ in 2:                       # all outlines first, then the swords over them
			for side in [-1.0, 1.0]:
				var d := Vector2(side, -1.0).normalized()      # from the hilt (bottom) to the tip (top)
				var n := Vector2(-d.y, d.x)
				var hilt := c - d * r * 0.62
				var guard := hilt + d * r * 0.3
				var tip := c + d * r * 0.95
				var blade := PackedVector2Array([guard + n * r * 0.1, tip - d * r * 0.18 + n * r * 0.1, tip,
					tip - d * r * 0.18 - n * r * 0.1, guard - n * r * 0.1])
				var g0 := guard + n * r * 0.32
				var g1 := guard - n * r * 0.32
				if pass_ == 0:
					var mid := (guard + tip) / 2.0
					var ol := PackedVector2Array()
					for q in blade:
						ol.append(q + (q - mid).normalized() * 2.0)
					draw_colored_polygon(ol, dark)
					draw_line(hilt, guard, dark, r * 0.17 + 4.0)
					draw_line(g0 + n * 2.0, g1 - n * 2.0, dark, r * 0.1 + 4.0)
					draw_circle(hilt, r * 0.1 + 2.0, dark)
				else:
					draw_colored_polygon(blade, Color(0.86, 0.86, 0.9))
					draw_line(guard + d * r * 0.02, tip - d * r * 0.12, Color(0.62, 0.62, 0.7), maxf(1.0, r * 0.04))
					draw_line(hilt, guard, Color(0.45, 0.25, 0.12), r * 0.17)
					draw_line(g0, g1, Color(0.95, 0.72, 0.25), r * 0.1)
					draw_circle(hilt, r * 0.1, Color(0.95, 0.72, 0.25))


const HELP := """W/S forward/back   A/D turn (strafe with right mouse)   Q/E strafe   Space jump   Shift sprint
left drag look   right drag steer   middle button re-center   both buttons run   wheel or - / . zoom   Tab target
F auto-attack   F2 autorun   1–6 abilities   R potion   C camp   B bags   M map   N abilities
right-click enemy attack   F1 hide help   Esc clear target / menu"""


func _ready() -> void:
	_info = _label(Vector2(16, 0), 16)
	_info.anchor_top = 1.0
	_info.offset_top = -154
	_help = _label(Vector2(16, 0), 15)
	_help.text = HELP
	_help.anchor_top = 1.0
	_help.offset_top = -130
	_hero = _frame(Vector2(16, 14), Color(0.25, 0.75, 0.3), true)
	_target = _frame(Vector2(330, 14), Color(0.8, 0.25, 0.2), false)
	_hero_auras = _aura_row(Vector2(16, 82))
	_target_auras = _aura_row(Vector2(0, 54), _target.root)
	_msg = _label(Vector2(0, 0), 26)
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.offset_left = -400
	_msg.offset_right = 400
	_msg.offset_top = 150
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	_stamina = _bar(Color(0.95, 0.8, 0.25))
	_stamina.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina.offset_left = -120
	_stamina.offset_right = 120
	_stamina.offset_top = -150
	_stamina.offset_bottom = -142
	add_child(_stamina)
	_cast = _bar(Color(0.95, 0.75, 0.3))
	_cast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cast.offset_left = -160
	_cast.offset_right = 160
	_cast.offset_top = -190
	_cast.offset_bottom = -172
	_cast.visible = false
	add_child(_cast)
	_cast_label = _label(Vector2.ZERO, 14, _cast)
	_cast_label.size = Vector2(320, 18)
	_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# XP bar right under the action bar, as wide as it, the numbers on it; money and potions
	# below.
	_xp = _bar(Color(0.55, 0.35, 0.9))
	_xp.anchor_left = 0.5
	_xp.anchor_right = 0.5
	_xp.anchor_top = 1.0
	_xp.anchor_bottom = 1.0
	_xp.offset_left = -3 * 74 + 3
	_xp.offset_right = 3 * 74 - 3
	_xp.offset_top = -40
	_xp.offset_bottom = -26
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0.6)
	frame.border_color = Color(0.55, 0.45, 0.3)
	frame.set_border_width_all(1)
	_xp.add_theme_stylebox_override("background", frame)
	add_child(_xp)
	_xp_text = _label(Vector2(0, -3), 12, _xp)
	_xp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_text.offset_top = -3
	_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label = _label(Vector2(0, 0), 13)
	_xp_label.anchor_left = 0.5
	_xp_label.anchor_right = 0.5
	_xp_label.anchor_top = 1.0
	_xp_label.anchor_bottom = 1.0
	_xp_label.offset_left = -200
	_xp_label.offset_right = 200
	_xp_label.offset_top = -24
	_xp_label.offset_bottom = -4
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(pos: Vector2, size: int, parent: Node = null) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	(parent if parent else self).add_child(l)
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override("background", back)
	return b


## A unit frame: name/level line, health bar with numbers, optional rage bar.
func _frame(pos: Vector2, color: Color, rage: bool) -> Dictionary:
	var root := Control.new()
	root.position = pos
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.size = Vector2(300, 64 if rage else 50)
	root.add_child(bg)
	var name := _label(Vector2(8, 2), 16, root)
	var hp := _bar(color)
	hp.position = Vector2(8, 24)
	hp.size = Vector2(284, 18)
	root.add_child(hp)
	var hp_text := _label(Vector2(8, 23), 13, root)
	hp_text.size = Vector2(284, 18)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f := {"root": root, "name": name, "hp": hp, "hp_text": hp_text}
	if rage:
		var r := _bar(Color(0.85, 0.15, 0.15))
		r.position = Vector2(8, 46)
		r.size = Vector2(284, 10)
		root.add_child(r)
		f["rage"] = r
	return f


## A row of buffs and debuffs under a unit frame.
func _aura_row(pos: Vector2, parent: Node = null) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.position = pos
	row.size = Vector2(300, 0)
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(row)
	return row


## Shows a unit's buffs (green frame) then debuffs (red frame), each with the seconds left.
func _show_auras(row: HFlowContainer, s: Combatant) -> void:
	var list: Array = s.auras() if s else []
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.debuff) < int(b.debuff))
	while row.get_child_count() < list.size():
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.8)
		sb.set_border_width_all(1)
		sb.set_content_margin_all(3)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		chip.add_theme_stylebox_override("panel", sb)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		chip.add_child(l)
		row.add_child(chip)
	for i in row.get_child_count():
		var chip := row.get_child(i) as PanelContainer
		chip.visible = i < list.size()
		if not chip.visible:
			continue
		var a: Dictionary = list[i]
		var l := chip.get_child(0) as Label
		var left := float(a.left)
		l.text = String(a.name) + (("  %d" % ceili(left)) if left >= 0.0 else "")
		var c := Color(0.95, 0.4, 0.3) if a.debuff else Color(0.45, 0.9, 0.45)
		l.add_theme_color_override("font_color", c.lerp(Color.WHITE, 0.45))
		(chip.get_theme_stylebox("panel") as StyleBoxFlat).border_color = c


func _build_action_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -3 * 74
	bar.offset_right = 3 * 74
	bar.offset_top = -112
	bar.offset_bottom = -46
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	_bar_box = bar
	if not player.loadout_changed.is_connected(_rebuild_bar):
		player.loadout_changed.connect(_rebuild_bar)
	for i in Player.SLOTS:
		var a := player.slot_ability(i)
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(68, 64)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.1, 0.08, 0.85)
		sb.border_color = Color(0.55, 0.45, 0.3)
		sb.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", sb)
		bar.add_child(slot)
		var key := _label(Vector2(5, 1), 14, slot)
		key.text = str(i + 1)
		if a.is_empty():
			sb.bg_color = Color(0.08, 0.07, 0.06, 0.55)
			_slots.append({"a": a})
			continue
		slot.tooltip_text = AbilityText.describe(player.cls, a, i + 1)
		var nm := _label(Vector2(4, 18), 11, slot)
		nm.text = String(a.name).replace(" ", "\n")
		var cost := _label(Vector2(42, 1), 12, slot)
		var c := int(a.get("rage", 0)) + int(a.get("mana", 0)) + int(a.get("energy", 0))
		cost.text = "%d" % c if c > 0 else ""
		cost.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if a.has("rage") else (Color(0.5, 0.7, 1.0) if a.has("mana") else Color(1, 0.9, 0.3)))
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.size = Vector2(68, 64)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(shade)
		var sweep := Sweep.new()
		sweep.size = Vector2(68, 64)
		sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(sweep)
		var cd := _label(Vector2(0, 20), 20, slot)
		cd.size = Vector2(68, 24)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_slots.append({"a": a, "slot": slot, "shade": shade, "sweep": sweep, "cd": cd, "style": sb, "name": nm})


## The abilities menu changed the bar: built again on the next frame.
func _rebuild_bar() -> void:
	if _bar_box:
		_bar_box.queue_free()
		_bar_box = null
	_slots.clear()


## The zone's name in large letters when entering it, fading out after a few seconds.
func show_zone(name: String, subtitle: String) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -500
	box.offset_right = 500
	box.offset_top = 210
	add_child(box)
	var t := _label(Vector2.ZERO, 54, box)
	t.text = name
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	var st := _label(Vector2.ZERO, 22, box)
	st.text = subtitle
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.8)
	tw.tween_interval(3.5)
	tw.tween_property(box, "modulate:a", 0.0, 1.2)
	tw.tween_callback(box.queue_free)


## Level up: "Level N" in large letters and below it what was learned; the new abilities'
## slots glow on the bar for a while.
func show_level(level: int, learned: Array) -> void:
	_banner("Level %d" % level, learned, Color(1, 0.85, 0.25), Color(0.75, 0.95, 1.0))
	for ab in player.abilities():
		if int(ab.level) == level:
			_fresh[ab.id] = Combatant.now() + 12.0


## After a death: the penalty, under a red "You died".
func show_death(lines: Array) -> void:
	_banner("You died", lines, Color(0.95, 0.25, 0.2), Color(1.0, 0.85, 0.75))


## A big title in the upper middle with lines under it, fading in and out.
func _banner(title: String, lines: Array, title_color: Color, line_color: Color) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -500
	box.offset_right = 500
	box.offset_top = 190
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var t := _label(Vector2.ZERO, 58, box)
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", title_color)
	for line: String in lines:
		var l := _label(Vector2.ZERO, 24, box)
		l.text = line
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", line_color)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.4)
	tw.tween_interval(4.0 + 1.5 * lines.size())
	tw.tween_property(box, "modulate:a", 0.0, 1.2)
	tw.tween_callback(box.queue_free)


func show_message(text: String, seconds := 2.5) -> void:
	_msg.text = text
	_msg_until = Combatant.now() + seconds


## A tip: like a message, but it stays longer.
func show_hint(text: String) -> void:
	show_message(text, 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_help.visible = not _help.visible


func _process(_dt: float) -> void:
	if player == null:
		return
	if _slots.is_empty():
		_build_action_bar()
	if _map == null:
		_map = Minimap.new()
		_map.player = player
		_map.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_map.offset_left = -Minimap.SIZE_PX - 16
		_map.offset_top = 14
		add_child(_map)
		_quests = _label(Vector2.ZERO, 15)
		_quests.anchor_left = 1.0
		_quests.anchor_right = 1.0
		_quests.offset_left = -Minimap.SIZE_PX - 16
		_quests.offset_right = -16
		_quests.offset_top = Minimap.SIZE_PX + 44
		_quests.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_quests.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		player.quests_changed.connect(_update_quests)
		player.level_banner.connect(show_level)
		player.death_banner.connect(show_death)
		_combat = CombatIcon.new()
		_combat.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_combat.offset_left = -26
		_combat.offset_right = 26
		_combat.offset_top = 14
		_combat.offset_bottom = 66
		add_child(_combat)
		_update_quests()
		if player.stats.uses_mana or player.stats.uses_energy:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(0.25, 0.45, 0.95) if player.stats.uses_mana else Color(0.95, 0.85, 0.2)
			_hero.rage.add_theme_stylebox_override("fill", fill)
	var t := Combatant.now()
	var s := player.stats
	_hero.name.text = "%s   level %d" % [s.display_name, s.level]
	_hero.hp.value = float(s.hp) / s.max_hp
	_hero.hp_text.text = "%d / %d" % [s.hp, s.max_hp]
	_hero.rage.value = (s.mana / s.max_mana) if s.uses_mana else (s.energy / 100.0 if s.uses_energy else s.rage / 100.0)
	_cast.visible = not player.casting.is_empty()
	if _cast.visible:
		var c: Dictionary = player.casting
		_cast.value = (t - float(c.start)) / maxf(float(c.end) - float(c.start), 0.01)
		_cast_label.text = c.a.name
	var e := player.target
	if t > _auras_at:
		_auras_at = t + 0.2
		_show_auras(_hero_auras, s)
		_show_auras(_target_auras, e.stats if e else null)
	_target.root.visible = e != null
	if e:
		var es := e.stats
		_target.name.text = "%s   level %d%s" % [es.display_name, es.level, "   Elite" if es.tier == "elite" else ("   Champion" if es.tier == "champion" else "")]
		_target.hp.value = float(es.hp) / es.max_hp
		_target.hp_text.text = "%d / %d" % [es.hp, es.max_hp]
	for sl in _slots:
		var a: Dictionary = sl.a
		if a.is_empty():
			continue
		var why := player.ability_problem(a)
		# The clock runs over the ability's own cooldown or the global cooldown, whichever ends
		# later.
		var own := float(player.cooldowns.get(a.id, 0.0)) - t
		var gcd := (player.gcd_until - t) if a.id != "battle_cry" else 0.0
		var left := maxf(own, gcd)
		var total := float(a.cd) if own >= gcd else Player.GCD
		var learned := s.level >= int(a.level)
		sl.sweep.frac = clampf(left / maxf(total, 0.01), 0.0, 1.0) if left > 0.0 and learned else 0.0
		sl.cd.text = ("%d" % ceili(left)) if left > 1.5 else ""
		# Under the global cooldown's sweep the slot still shows whether the ability could be used
		# once it ends (Overwhelm without a dodge stays dark); the name is white only when it can
		# be used right now.
		var after_gcd := player.ability_problem(a, true) if why != "" else ""
		sl.shade.visible = why != "" and (sl.sweep.frac == 0.0 or (own <= 0.0 and after_gcd != ""))
		sl.shade.color = Color(0, 0, 0, 0.75) if not learned else Color(0, 0, 0, 0.45)
		(sl.name as Label).add_theme_color_override("font_color", Color.WHITE if why == "" else Color(0.55, 0.53, 0.5))
		sl.style.border_color = Color(1, 0.85, 0.3) if (a.id == "overwhelm" and after_gcd == "" and learned) else Color(0.55, 0.45, 0.3)
		if t < float(_fresh.get(a.id, 0.0)):      # just learned: the border pulses
			sl.style.border_color = Color(0.55, 0.45, 0.3).lerp(Color(0.5, 0.95, 1.0), 0.5 + 0.5 * sin(t * 6.0))
	_combat.visible = s.in_combat() and not s.dead
	_stamina.value = player.stamina
	_stamina.visible = player.stamina < 0.999
	var need := Rules.xp_to_next(s.level)
	_xp.value = float(player.xp) / need
	_xp_text.text = "XP %d / %d" % [player.xp, need]
	_xp_label.text = "%s      potions %d" % [Items.money_text(player.money), player.potion_count()]
	if t > _msg_until:
		_msg.text = ""
	var p := player.global_position
	_info.text = "%d FPS    x %.0f  z %.0f" % [Engine.get_frames_per_second(), p.x, p.z]


## The quest tracker under the minimap: active quests and their progress.
func _update_quests() -> void:
	var lines := []
	for q in player.quests.active:
		if int(q.have) >= int(q.need):
			lines.append("%s  — done, return to the inn" % q.title)
		else:
			lines.append("%s  %d/%d" % [q.title, int(q.have), int(q.need)])
	_quests.text = ("Quests\n" + "\n".join(lines)) if not lines.is_empty() else ""
