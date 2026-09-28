extends Control
## Top-centre banner for quest notifications of both chapters and the optional goals ("New goal: ...",
## "Goal complete: ...", "Optional goal complete: ..."). Queued (max 4, a line already queued or on screen is
## not repeated), one at a time, with a soft drop-in and the ui_quest chime.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var panel: PanelContainer
var label: Label
var sub: Label
var _queue: Array = []
var _busy := false
var _current := ""               # text on screen while _busy


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var sb := ThemeFactory.box(Color(ThemeFactory.PAPER, 0.97), 22, 3, ThemeFactory.GOLD.darkened(0.25), [30, 12, 30, 14], 14, Vector2(0, 6), Color(0.1, 0.05, 0.08, 0.35))
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var h := Kit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(h)
	h.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 64), 44))
	var v := Kit.vbox(0)
	h.add_child(v)
	sub = Kit.label("", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	sub.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
	v.add_child(sub)
	label = Kit.label("", "Subheading", HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(label)
	h.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 64), 44))
	panel.visible = false


func show_text(text: String) -> void:
	# The same line twice in a row (e.g. a Chapter One and a Chapter Two evaluation announcing together, or a
	# repeated notify while the banner waits behind a menu) is shown once.
	if _queue.has(text) or (_busy and _current == text):
		return
	_queue.append(text)
	if _queue.size() > 4:
		_queue.pop_front()
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty() or Game.is_ui_open():
		# (while a menu is open the banner would be hidden behind it: wait, see _process)
		_busy = false
		panel.visible = false
		return
	_busy = true
	var text: String = _queue.pop_front()
	_current = text
	var parts := text.split(":", true, 1)
	if parts.size() == 2:
		sub.text = parts[0].strip_edges().to_upper()
		label.text = parts[1].strip_edges()
	else:
		sub.text = "HOLLOWHAVEN"
		label.text = text
	panel.visible = true
	panel.reset_size()
	var ms := panel.get_combined_minimum_size()
	panel.size = ms
	var y := 132.0
	panel.position = Vector2(round((size.x - ms.x) * 0.5), y - 30.0)
	panel.modulate.a = 0.0
	Audio.play_ui("ui_quest")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_property(panel, "position:y", y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(3.2)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(_next)


func _process(_delta: float) -> void:
	# Banners queued while a menu was open play once it closes.
	if not _busy and not _queue.is_empty() and not Game.is_ui_open():
		_next()
