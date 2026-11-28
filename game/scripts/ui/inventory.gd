class_name Inventory
extends CanvasLayer
## The bags window (B or I): equipped items on the left (click to take off), the hero's numbers,
## the bag (click: equip or drink, right-click at a merchant: sell, elsewhere: throw away, asked
## once) and, close to an inn, the
## merchant's goods (click to buy). Doesn't pause the game.

var player: Player
var _panel: PanelContainer
var _equip_box: GridContainer
var _bag_grid: GridContainer
var _stats: Label
var _money: Label
var _shop_box: VBoxContainer
var _shop_list: VBoxContainer
var _shop: Array = []
var _shop_for := -1.0          ## merchant_until when the stock was made (a new visit restocks)
var _dirty := true


func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_right = -24
	_panel.offset_top = -300
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.9)
	style.border_color = Color(0.55, 0.45, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)

	var left := VBoxContainer.new()
	row.add_child(left)
	left.add_child(_title("Equipment"))
	_equip_box = GridContainer.new()
	_equip_box.columns = 1
	left.add_child(_equip_box)
	_stats = _text(15)
	left.add_child(_stats)

	var mid := VBoxContainer.new()
	row.add_child(mid)
	mid.add_child(_title("Bags"))
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 4
	mid.add_child(_bag_grid)
	_money = _text(17)
	mid.add_child(_money)
	var hint := _text(13)
	hint.text = "Click: equip / drink    Right-click: sell at a merchant, else throw away\nHover for details    B or I closes"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	mid.add_child(hint)

	_shop_box = VBoxContainer.new()
	row.add_child(_shop_box)
	_shop_box.add_child(_title("Merchant"))
	_shop_list = VBoxContainer.new()
	_shop_box.add_child(_shop_list)
	visible = false


func _title(text: String) -> Label:
	var l := _text(20)
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	return l


func _text(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	return l


func _item_button(item: Dictionary, width: float, text: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 46)
	b.text = text
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 13)
	if not item.is_empty():
		var c := Items.color(item)
		b.add_theme_color_override("font_color", c)
		b.add_theme_color_override("font_hover_color", c.lightened(0.3))
		b.tooltip_text = Items.describe(item, player.cls, player.stats.level)
		if Items.problem(item, player.cls, player.stats.level) != "":
			b.add_theme_color_override("font_color", Color(0.85, 0.3, 0.25))
	b.focus_mode = Control.FOCUS_NONE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.14, 0.12, 0.95)
	st.border_color = Items.color(item).darkened(0.4) if not item.is_empty() else Color(0.3, 0.27, 0.22)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.26, 0.22, 0.17, 0.95)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	return b


func toggle() -> void:
	visible = not visible
	_dirty = true
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("bags"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("menu"):
		visible = false
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if player == null:
		return
	if not player.inventory_changed.is_connected(_mark):
		player.inventory_changed.connect(_mark)
		player.leveled_up.connect(func(_l): _mark())
	if not visible:
		return
	var shop_open := player.near_merchant()
	if shop_open != _shop_box.visible:
		_shop_box.visible = shop_open
		_dirty = true
	if shop_open and _shop_for < 0.0:
		_restock()
	if not shop_open:
		_shop_for = -1.0
	if _dirty:
		_dirty = false
		_rebuild()


func _mark() -> void:
	_dirty = true


## The merchant's stock: potions and a few plain items for the hero's class and level.
func _restock() -> void:
	_shop_for = player.merchant_until
	_shop.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_shop.append(Items.POTION.duplicate(true))
	var lvl := player.stats.level
	for slot in ["main", "chest", "legs", "head", "off", "feet"]:
		if slot == "off" and player.cls in ["hunter"]:
			continue
		_shop.append(Items.make(slot, lvl, "common", player.cls, rng, true))
	if rng.randf() < 0.5:
		_shop.append(Items.make(Items.SLOTS[rng.randi() % Items.SLOTS.size()], lvl, "uncommon", player.cls, rng, true))
	_dirty = true


func _rebuild() -> void:
	for c in _equip_box.get_children():
		c.queue_free()
	for slot in Items.SLOTS:
		var it: Dictionary = player.equipped.get(slot, {})
		var label := "%s:  %s" % [Items.SLOT_NAMES[slot], it.name if not it.is_empty() else "—"]
		var b := _item_button(it, 300, label)
		b.custom_minimum_size.y = 34
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if it.is_empty():
			b.add_theme_color_override("font_color", Color(0.55, 0.55, 0.5))
		b.pressed.connect(player.unequip.bind(slot))
		_equip_box.add_child(b)
	var s := player.stats
	var first := "Health %d" % s.max_hp + ("   Mana %d" % roundi(s.max_mana) if s.uses_mana else "")
	var off := Items.weapon_damage(player.equipped.get("off", {}))
	var weapon := "Weapon damage %d (x%.2f)" % [roundi(maxf(s.weapon_damage, 0.0)), s.weapon_mult]
	if off > 0:
		weapon += "   off hand %d (x%.2f)" % [off, Rules.weapon_mult(off)]
	_stats.text = "%s\n%s\nAttack %d   Defense %d\nMagic %d   Resistance %d\nCrit %.0f%%" % [first,
		weapon, roundi(s.attack), roundi(s.defense), roundi(s.magic), roundi(s.resistance), s.crit_chance * 100.0]

	for c in _bag_grid.get_children():
		c.queue_free()
	for i in Items.BAG_SIZE:
		var it: Dictionary = player.bag[i] if i < player.bag.size() else {}
		var text := ""
		if not it.is_empty():
			text = it.name if it.slot != "potion" else "%s x%d" % [it.name, int(it.count)]
		var b := _item_button(it, 130, text)
		if not it.is_empty() and it.slot != "potion":
			var cur: Dictionary = player.equipped.get(it.slot, {})
			b.tooltip_text += "\n\nInstead of %s: %s" % [cur.name if not cur.is_empty() else "nothing", Items.compare(it, cur)]
		if not it.is_empty():
			b.pressed.connect(player.equip.bind(i))
			b.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					# At a merchant: sell; anywhere else: throw away (asked once first).
					if player.near_merchant():
						player.sell(i)
					else:
						player.discard(i))
			if player.discard_pending(i):
				b.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
				b.text = "Throw away?  " + b.text
		_bag_grid.add_child(b)
	_money.text = "Money: %s    Potions (G): %d" % [Items.money_text(player.money), player.potion_count()]

	for c in _shop_list.get_children():
		c.queue_free()
	for it in _shop:
		var b := _item_button(it, 260, "%s — %s" % [it.name, Items.money_text(Items.buy_price(it, player.stats.level))])
		b.custom_minimum_size.y = 34
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			if player.buy(it) and it.slot != "potion":
				_shop.erase(it)
				_dirty = true)
		_shop_list.add_child(b)
