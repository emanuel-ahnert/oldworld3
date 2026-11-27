class_name Tip
extends CanvasLayer
## The game's tooltip: a dark panel anchored to the right of the mouse cursor (flipped to its
## left only where it would leave the screen), following it while it rests on a control.
## First line the name (gold), second line the small print (grey), then the description.
## Tip.attach(control, text or Callable returning the text).

static var instance: Tip

const GAP := Vector2(20, -10)        ## from the cursor to the panel's top left corner
const WIDTH := 340.0

var _panel: PanelContainer
var _text: RichTextLabel
var _owner: Control
var _source: Variant             ## the text or the Callable giving it (re-read while shown)
var _last := ""


func _ready() -> void:
	instance = self
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.94)
	sb.border_color = Color(0.62, 0.5, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(WIDTH, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 17)
	_text.add_theme_color_override("default_color", Color(0.92, 0.9, 0.84))
	_panel.add_child(_text)
	add_child(_panel)
	_panel.visible = false


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Shows `text` for `control` while the mouse rests on it. text: a String or a Callable
## returning one (read when the mouse arrives, so it is current).
static func attach(control: Control, text: Variant) -> void:
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_entered.connect(func():
		if instance:
			instance._source = text
			instance._show(control, String(text.call()) if text is Callable else String(text)))
	control.mouse_exited.connect(func():
		if instance and instance._owner == control:
			instance._hide())
	control.tree_exiting.connect(func():
		if instance and instance._owner == control:
			instance._hide())


func _show(control: Control, text: String) -> void:
	if text.strip_edges() == "":
		_hide()
		return
	_owner = control
	_last = text
	var lines := text.split("\n")
	var out := "[b][color=#f2cc73]%s[/color][/b]" % lines[0].replace("[", "[lb]")
	if lines.size() > 1 and lines[1] != "":
		out += "\n[color=#a59d8e]%s[/color]" % lines[1].replace("[", "[lb]")
	if lines.size() > 2:
		out += "\n" + "\n".join(lines.slice(2)).replace("[", "[lb]")
	_text.text = out
	_panel.visible = true
	_panel.reset_size()
	_place()


func _hide() -> void:
	_owner = null
	_panel.visible = false


func _process(_dt: float) -> void:
	if _panel.visible:
		if _owner == null or not is_instance_valid(_owner) or not _owner.is_visible_in_tree():
			_hide()
			return
		if _source is Callable:
			var t := String(_source.call())
			if t != _last:
				_show(_owner, t)              # live (a buff's seconds)
		_place()


func _place() -> void:
	var vp := _panel.get_viewport_rect().size
	var m := _panel.get_viewport().get_mouse_position()
	var s := _panel.size
	var p := m + GAP
	if p.x + s.x > vp.x - 4:
		p.x = m.x - GAP.x - s.x               # no room on the right: on the cursor's left
	p.y = clampf(p.y, 4, vp.y - s.y - 4)
	_panel.position = p
