class_name SpellBook
extends CanvasLayer
## The abilities menu (N; Oldworld2 game-design 7.3): on the left the 6 action-bar slots and the
## 3 passive slots, on the right the class's learned abilities and passives (the others appear
## when their level is reached); details of the selected entry at the bottom. A passive works only
## while it is in a passive slot.
## Keyboard first: Up/Down (W/S) move, Left/Right (A/D) switch sides, Space/Enter: on a known
## ability or passive puts it into the first free slot of its kind, or (none free, or already
## slotted) lets you pick the slot (one already slotted swaps places); on a slot takes it out.
## Esc cancels picking or closes; N closes. The mouse works too. Pauses the game.

const GILT := Color(0.95, 0.8, 0.45)
const INK := Color(0.95, 0.92, 0.86)
const FADED := Color(0.55, 0.52, 0.47)

var player: Player
var _left: VBoxContainer
var _right: VBoxContainer
var _details: VBoxContainer
var _status: Label
var _title: Label
var _side := 1                  ## 0 = slots, 1 = abilities and passives
var _row := [0, 0]
var _pending := ""              ## ability id or passive name waiting for a slot (picking mode)
var _pending_passive := false


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.07, 0.05, 0.92)
	st.border_color = Color(0.7, 0.55, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(940, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = _label("", 28, GILT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	box.add_child(cols)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(330, 0)
	cols.add_child(_left)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_right)
	var sep := ColorRect.new()
	sep.color = Color(0.7, 0.55, 0.3, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	box.add_child(sep)
	_details = VBoxContainer.new()
	_details.custom_minimum_size = Vector2(0, 92)
	box.add_child(_details)
	_status = _label("", 16, Color(1, 0.75, 0.5))
	box.add_child(_status)
	var hint := _label("Up/Down choose    Left/Right switch sides    Space put in / take out of a slot    Esc or N close", 14, FADED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	visible = false


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pending = ""
	_pending_passive = false
	_status.text = ""
	_refresh()


func close() -> void:
	visible = false
	_pending = ""
	get_tree().paused = false


## Right side: the class's abilities, then the passives ([kind, data]).
## Learned abilities and passives only (the rest stays hidden until its level).
func _entries() -> Array:
	var out: Array = []
	var lvl := player.stats.level
	for a in player.abilities():
		if lvl >= int(a.level):
			out.append(["active", a])
	for p: Array in AbilityText.PASSIVES.get(player.cls, []):
		if lvl >= int(p[0]):
			out.append(["passive", p])
	return out


func _count(side: int) -> int:
	return Player.SLOTS + Player.PASSIVE_SLOTS if side == 0 else _entries().size()


## Left rows: 0..5 action slots, 6..8 passive slots. While picking, only the matching group.
func _move(step: int) -> void:
	if _side == 0 and _pending != "":
		var lo := Player.SLOTS if _pending_passive else 0
		var n := Player.PASSIVE_SLOTS if _pending_passive else Player.SLOTS
		_row[0] = lo + (_row[0] - lo + step + n) % n
	else:
		_row[_side] = (_row[_side] + step + _count(_side)) % _count(_side)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _refresh() -> void:
	_title.text = "%s — abilities" % Player.CLASSES[player.cls].name
	for c in _left.get_children() + _right.get_children() + _details.get_children():
		c.queue_free()
	_left.add_child(_label("Action bar" + ("  — choose a slot" if _pending != "" and not _pending_passive else ""), 18, GILT))
	for i in Player.SLOTS:
		var a := player.slot_ability(i)
		_left.add_child(_entry_row(0, i, "%d   %s" % [i + 1, a.name if not a.is_empty() else "—"], "", INK if not a.is_empty() else FADED, String(a.get("name", ""))))
	_left.add_child(_label("Passive slots" + ("  — choose a slot" if _pending_passive else ""), 18, GILT))
	for j in Player.PASSIVE_SLOTS:
		var nm: String = player.passive_loadout[j]
		_left.add_child(_entry_row(0, Player.SLOTS + j, "◇   %s" % (nm if nm != "" else "—"), "", INK if nm != "" else FADED, nm))
	_right.add_child(_label("Abilities", 18, GILT))
	var lvl := player.stats.level
	var entries := _entries()
	var passive_header := false
	for k in entries.size():
		var e: Array = entries[k]
		if e[0] == "active":
			var a: Dictionary = e[1]
			var learned := lvl >= int(a.level)
			var s := player.slot_of(a.id)
			var where := ("key %d" % (s + 1)) if s >= 0 else ""
			_right.add_child(_entry_row(1, k, a.name, where if learned else "level %d" % int(a.level), INK if learned else FADED))
		else:
			if not passive_header:
				passive_header = true
				_right.add_child(_label("Passives", 18, GILT))
			var p: Array = e[1]
			var learned := lvl >= int(p[0])
			var ps := player.passive_loadout.find(p[1])
			_right.add_child(_entry_row(1, k, p[1], ("slot %d" % (ps + 1) if ps >= 0 else "") if learned else "level %d" % int(p[0]), INK if learned else FADED))
	_show_details()


func _entry_row(side: int, i: int, text: String, value: String, color: Color, icon_name := "_") -> Control:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 32)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var on: bool = _side == side and _row[side] == i
	var gem := _label("◆" if on else "", 18, GILT)
	gem.custom_minimum_size = Vector2(22, 0)
	h.add_child(gem)
	# The ability's or passive's icon before its name (dimmed when not learned yet).
	var tex := Icons.get_icon(text if icon_name == "_" else icon_name) if (icon_name != "") else null
	if tex:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.custom_minimum_size = Vector2(30, 30)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color.WHITE if color != FADED else Color(0.45, 0.45, 0.45)
		h.add_child(icon)
	var l := _label(text, 21, GILT if on else color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if value != "":
		h.add_child(_label(value, 16, FADED))
	h.mouse_entered.connect(func():
		if _side != side or _row[side] != i:
			if _pending == "" or side == 0:
				_side = side
				_row[side] = i
				_refresh())
	h.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_side = side
			_row[side] = i
			_select()
			_refresh())
	return h


func _show_details() -> void:
	var text := ""
	if _side == 0 and _row[0] >= Player.SLOTS:
		var nm: String = player.passive_loadout[_row[0] - Player.SLOTS]
		text = "Empty passive slot." if nm == "" else ""
		for p: Array in player.passives():
			if p[1] == nm:
				text = "%s\nPassive, level %d\n%s" % [p[1], int(p[0]), AbilityText.fill(p[2])]
	elif _side == 0:
		var a := player.slot_ability(_row[0])
		text = AbilityText.describe(player.cls, a, _row[0] + 1) if not a.is_empty() else "Empty slot (key %d)." % (_row[0] + 1)
	else:
		var e: Array = _entries()[_row[1]]
		if e[0] == "active":
			text = AbilityText.describe(player.cls, e[1], 0)
		else:
			var p: Array = e[1]
			text = "%s\nPassive, level %d\n%s" % [p[1], int(p[0]), AbilityText.fill(p[2])]
	var lines := text.split("\n")
	for k in lines.size():
		var l := _label(lines[k], 20 if k == 0 else 16, GILT if k == 0 else INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(890, 0)
		_details.add_child(l)


func _select() -> void:
	_status.text = ""
	if _side == 0 and _row[0] >= Player.SLOTS:
		var j: int = _row[0] - Player.SLOTS
		var pl := player.passive_loadout.duplicate()
		if _pending_passive:
			var old := pl.find(_pending)
			if old >= 0:
				pl[old] = pl[j]
			pl[j] = _pending
			_pending = ""
			_pending_passive = false
			_side = 1
		elif pl[j] != "":
			pl[j] = ""
		player.set_passive_loadout(pl)
		return
	if _side == 0:
		var i: int = _row[0]
		if _pending != "":
			# Put the waiting ability here; if it was on the bar already, the two swap.
			var old := player.slot_of(_pending)
			if old >= 0:
				player.loadout[old] = player.loadout[i]
			player.loadout[i] = _pending
			_pending = ""
			_side = 1
		elif player.loadout[i] != "":
			player.loadout[i] = ""
		player.loadout_changed.emit()
		return
	var e: Array = _entries()[_row[1]]
	if e[0] == "passive":
		var p: Array = e[1]
		if player.stats.level < int(p[0]):
			_status.text = "%s is learned at level %d." % [p[1], int(p[0])]
			return
		var pl := player.passive_loadout.duplicate()
		var pfree := pl.find("")
		if not p[1] in pl and pfree >= 0:
			pl[pfree] = p[1]
			player.set_passive_loadout(pl)
			return
		_pending = p[1]
		_pending_passive = true
		_side = 0
		_row[0] = Player.SLOTS + maxi(0, pl.find(p[1]))
		_status.text = "Choose a passive slot for %s (Esc cancels)." % p[1]
		return
	var a: Dictionary = e[1]
	if player.stats.level < int(a.level):
		_status.text = "%s is learned at level %d." % [a.name, int(a.level)]
		return
	var free := player.loadout.find("")
	if player.slot_of(a.id) < 0 and free >= 0:
		player.loadout[free] = a.id
		player.loadout_changed.emit()
		return
	# No free slot, or moving it: choose the slot.
	_pending = a.id
	_pending_passive = false
	_side = 0
	_row[0] = maxi(0, player.slot_of(a.id))
	_status.text = "Choose a slot for %s (Esc cancels)." % a.name


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("spellbook") and not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var handled := true
	match (event as InputEventKey).keycode:
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			if _pending == "":
				_side = 1 - _side
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_select()
		KEY_ESCAPE:
			if _pending != "":
				_pending = ""
				_pending_passive = false
				_side = 1
				_status.text = ""
			else:
				close()
		KEY_N:
			close()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
		if visible:
			_refresh()
