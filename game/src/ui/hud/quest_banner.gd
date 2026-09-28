extends Control
## Top-centre banner for quest notifications of both chapters and the optional goals ("New goal: ...",
## "Goal complete: ...", "Optional goal complete: ..."). Queued (max 4, a line already queued or on screen is
## not repeated), one at a time, with a soft drop-in and the ui_quest chime.
## Visual QA: the banner never grows wider than MAX_LABEL_W of text (UI-07: "Expedition begun: Manor Afterglow.
## Follow the ribbon lantern to ..." used to span ~1040 px over the goal tracker): a line whose part after the
## colon is a short title followed by more sentences shows the title big and the rest as a small wrapped line
## under it (split_text); anything else wraps. It also waits while `held` (UI root hush: a chapter card, a
## full-screen menu or modal, the ending), and a line cut short by such a moment plays again afterwards.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

const MAX_LABEL_W := 600.0        # title / detail text wrap width (the whole card stays under ~780 px)
const TITLE_MAX_CHARS := 44       # a first sentence longer than this is not split off as a title
const REQUEUE_BEFORE_MS := 1600   # a line held within this long of appearing plays again after the hold

var panel: PanelContainer
var label: Label
var sub: Label
var detail: Label
var held := false
var _queue: Array = []
var _busy := false
var _current := ""               # text on screen while _busy
var _shown_ms := 0
var _tween: Tween


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
	detail = Kit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	detail.visible = false
	v.add_child(detail)
	h.add_child(Kit.icon_rect(IconFactory.icon("ui_star", Color.WHITE, 64), 44))
	panel.visible = false


## "Kind: Title. More text." -> [KIND, Title, More text.]; "Kind: Title" -> [KIND, Title, ""]; no colon ->
## ["HOLLOWHAVEN", text, ""]. The rest after a short first sentence becomes the small detail line.
static func split_text(text: String) -> Array:
	var parts := text.split(":", true, 1)
	if parts.size() != 2:
		return ["HOLLOWHAVEN", text, ""]
	var head := parts[0].strip_edges().to_upper()
	var rest := parts[1].strip_edges()
	var dot := rest.find(". ")
	if dot > 0 and dot < TITLE_MAX_CHARS and rest.substr(dot + 2).strip_edges() != "":
		return [head, rest.substr(0, dot), rest.substr(dot + 2).strip_edges()]
	return [head, rest, ""]


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


## Hold (true) or release the banner (UI root hush). A line interrupted right after it appeared is queued again.
func set_held(on: bool) -> void:
	if on == held:
		return
	held = on
	if not on or not _busy:
		return
	if Time.get_ticks_msec() - _shown_ms < REQUEUE_BEFORE_MS and not _queue.has(_current):
		_queue.push_front(_current)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_busy = false
	_current = ""
	panel.visible = false


func _next() -> void:
	if _queue.is_empty() or Game.is_ui_open() or held:
		# (while a menu is open the banner would be hidden behind it: wait, see _process)
		_busy = false
		panel.visible = false
		return
	_busy = true
	var text: String = _queue.pop_front()
	_current = text
	_shown_ms = Time.get_ticks_msec()
	var p := split_text(text)
	sub.text = String(p[0])
	_fit(label, String(p[1]), "Subheading")
	detail.visible = String(p[2]) != ""
	_fit(detail, String(p[2]), "Small")
	panel.visible = true
	panel.reset_size()
	var ms := panel.get_combined_minimum_size()
	panel.size = ms
	var y := 132.0
	panel.position = Vector2(round((size.x - ms.x) * 0.5), y - 30.0)
	panel.modulate.a = 0.0
	Audio.play_ui("ui_quest")
	var tw := create_tween()
	_tween = tw
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_property(panel, "position:y", y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(3.2 + (1.2 if detail.visible else 0.0))
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(_next)


## Sets a label's text, wrapping it at MAX_LABEL_W only when it is wider than that.
static func _fit(l: Label, text: String, variation: String) -> void:
	l.text = text
	var f := l.get_theme_font("font", variation)
	var fs := l.get_theme_font_size("font_size", variation)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else 0.0
	if w > MAX_LABEL_W:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = MAX_LABEL_W
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size.x = 0.0


func _process(_delta: float) -> void:
	# Banners queued while a menu was open (or the HUD was hushed) play once it closes.
	if not _busy and not _queue.is_empty() and not Game.is_ui_open() and not held:
		_next()
