extends PanelContainer
## Onboarding hints (Events.hint): shown once per id (remembered in GameState flags "hint_<id>" so they
## never repeat after loading), key tokens like {interact} become highlighted key labels, can be turned
## off with Settings "show_hints". Queued; each stays long enough to read.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var text_l: RichTextLabel
var _queue: Array = []
var _time_left := 0.0
var _showing := false
var _tw: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "HudCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 470
	var h := Kit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var ic := Kit.icon_rect(IconFactory.icon("ui_hint", Color.WHITE, 96), 54)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := Kit.label("TIP", "Tiny")
	t.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
	v.add_child(t)
	text_l = Kit.rich("", 370)
	text_l.add_theme_font_size_override("normal_font_size", 22)
	text_l.add_theme_font_size_override("bold_font_size", 22)
	v.add_child(text_l)
	visible = false
	modulate.a = 0.0
	Events.hint.connect(on_hint)
	Events.settings_changed.connect(func(k: String) -> void:
		if k == "show_hints" and not bool(Settings.get_value("show_hints")):
			_queue.clear()
			_hide())


## Formats hint text: tokens -> accent-coloured bold key labels (BBCode).
static func format_hint(text: String, label_fn: Callable) -> String:
	var safe := UiUtil.bb_escape(text)
	var open := "[color=#%s][b]" % ThemeFactory.ACCENT.darkened(0.2).to_html(false)
	return UiUtil.fill_tokens(safe, label_fn, open, "[/b][/color]")


## Returns true if the hint was accepted for display (not shown before and hints enabled).
func on_hint(hint_id: String, text: String) -> bool:
	if not bool(Settings.get_value("show_hints")) or text.strip_edges() == "":
		return false
	var flag := "hint_" + hint_id
	if GameState.get_flag(flag):
		return false
	for q in _queue:
		if String(q["id"]) == hint_id:
			return false
	GameState.set_flag(flag, true)
	_queue.append({"id": hint_id, "text": text})
	if not _showing:
		_next()
	return true


func _next() -> void:
	if _queue.is_empty():
		_hide()
		return
	var h: Dictionary = _queue.pop_front()
	_showing = true
	visible = true
	text_l.text = format_hint(String(h["text"]), Callable(UiUtil, "settings_label"))
	_time_left = clampf(5.0 + float(String(h["text"]).length()) * 0.06, 7.0, 13.0)
	Audio.play_ui("ui_notify", -8.0)
	var tw := Kit.retween(self, _tw, "fade")
	tw.tween_property(self, "modulate:a", 1.0, 0.3)


func _hide() -> void:
	_showing = false
	var tw := Kit.retween(self, _tw, "fade")
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		if not _showing:
			visible = false)


func is_showing() -> bool:
	return _showing


func queued_count() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	if not _showing or Game.is_ui_open():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		var tw := Kit.retween(self, _tw, "fade")
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		_showing = false
		tw.tween_callback(func() -> void:
			if not _showing:
				_next())
