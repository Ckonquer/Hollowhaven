extends PanelContainer
## Speech / inscription line box (Events.say): speaker name on a little ribbon tab, text types in,
## then auto-hides after its duration. Lines queue up; the timer pauses while a menu is open.

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var speaker_tab: PanelContainer
var speaker_l: Label
var text_l: RichTextLabel
var _queue: Array = []
var _time_left := 0.0
var _showing := false
var _tw: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := ThemeFactory.box(Color(ThemeFactory.PAPER, 0.96), 22, 3, Color(ThemeFactory.BORDER_DARK, 0.85), [34, 26, 34, 22], 14, Vector2(0, 6), Color(0.1, 0.05, 0.08, 0.35))
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(900, 0)
	material = ThemeFactory.paper_material()
	text_l = Kit.rich("", 820)
	text_l.add_theme_font_size_override("normal_font_size", 27)
	text_l.add_theme_font_size_override("italics_font_size", 27)
	add_child(text_l)
	speaker_tab = PanelContainer.new()
	speaker_tab.theme_type_variation = "Ribbon"
	speaker_tab.add_theme_stylebox_override("panel", ThemeFactory.box(ThemeFactory.ACCENT, 14, 3, ThemeFactory.ACCENT.darkened(0.35), [20, 3, 20, 5], 4, Vector2(0, 3)))
	speaker_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker_l = Kit.label("", "RibbonTitle")
	speaker_l.add_theme_font_size_override("font_size", 24)
	speaker_tab.add_child(speaker_l)
	add_child(speaker_tab)
	sort_children.connect(_place_tab)
	visible = false
	modulate.a = 0.0
	Events.say.connect(say)


func _place_tab() -> void:
	var ms := speaker_tab.get_combined_minimum_size()
	speaker_tab.size = ms
	speaker_tab.position = Vector2(30, -ms.y * 0.55)


func say(speaker: String, text: String, duration: float = 0.0) -> void:
	if text.strip_edges() == "":
		return
	var d := duration
	if d <= 0.0:
		d = clampf(2.6 + float(text.length()) * 0.05, 3.0, 9.0)
	_queue.append({"speaker": speaker, "text": text, "duration": d})
	if _queue.size() > 5:
		_queue.pop_front()
	if not _showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_hide()
		return
	var line: Dictionary = _queue.pop_front()
	_showing = true
	visible = true
	var sp := String(line["speaker"])
	speaker_tab.visible = sp != ""
	speaker_l.text = sp
	var is_inscription := sp == "" or sp.to_lower().contains("stone") or sp.to_lower().contains("inscription")
	text_l.text = ("[center][i]%s[/i][/center]" if is_inscription else "%s") % UiUtil.bb_escape(String(line["text"]))
	_time_left = float(line["duration"])
	text_l.visible_ratio = 0.0
	var type_time := clampf(float(String(line["text"]).length()) * 0.022, 0.25, 1.6)
	var tw := Kit.retween(self, _tw, "type")
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_property(text_l, "visible_ratio", 1.0, type_time)


func _hide() -> void:
	_showing = false
	var tw := Kit.retween(self, _tw, "type")
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		if not _showing:
			visible = false)


## Skip the typewriter / advance (used when the player presses interact while a line is showing).
func advance() -> void:
	if not _showing:
		return
	if text_l.visible_ratio < 1.0:
		text_l.visible_ratio = 1.0
	else:
		_next()


func is_showing() -> bool:
	return _showing


func _process(delta: float) -> void:
	if not _showing:
		return
	if Game.is_ui_open():
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_next()
