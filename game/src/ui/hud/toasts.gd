extends VBoxContainer
## Notification toasts (Events.notify) and aggregated item pickups (Events.item_added -> "+3 Wood").
## Stacked bottom-right, newest at the bottom, each with a kind colour stripe and icon; they fade out.
## Quest notifications are shown by the quest banner instead (see quest_banner.gd).
## held (set by the UI root's hush, visual QA T4): while a chapter card, a full-screen menu / modal or the ending is
## up, toasts still queue (and merge) but their timers pause; they play out once it ends. A notify chime is not
## played for a toast that nobody can see yet.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Palette := preload("res://src/art/palette.gd")

const KIND_COLORS := {"info": Color("8fb6f0"), "success": Color("6fae4f"), "warn": Color("e9a15b"),
	"item": Color("c48a55"), "quest": Color("f2c14e"), "bond": Color("ff8fa8"), "save": Color("3fa7a0")}
const KIND_LIFE := {"info": 4.6, "success": 4.2, "warn": 5.2, "item": 3.4, "quest": 5.5, "bond": 5.0}
const MAX_TEXT_W := 520.0            # longer texts wrap at this width
const MAX_CARD_W := 620.0            # widest card: text + icon + padding (the UI root keeps this corner clear)

var model: RefCounted = UiUtil.ToastModel.new()
var views: Dictionary = {}          # entry id -> {panel, label, icon}
var quest_banner: Node = null        # set by the UI root; receives "quest" notifications
var held := false                    # UI root hush: queue, but pause the timers (see set_held)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 8)
	Events.notify.connect(_on_notify)
	Events.item_added.connect(_on_item_added)
	Events.key_item_added.connect(_on_key_item)
	Events.game_saved.connect(_on_saved)


func _on_saved(ok: bool) -> void:
	if not GameState.active:
		return
	var e: Dictionary = model.push_text("Journey saved" if ok else "The game couldn't be saved", "save" if ok else "warn", 3.0)
	_sync(e)
	Audio.play_ui("ui_save" if ok else "ui_error")


func _on_key_item(item_id: String) -> void:
	if not ItemDB.has_item(item_id):
		return
	var e: Dictionary = model.push_key_item(item_id, "Obtained: %s" % ItemDB.display_name(item_id))
	_sync(e)
	Audio.play_ui("ui_quest", -4.0)


func _on_item_added(item_id: String, count: int) -> void:
	if not GameState.active or not ItemDB.has_item(item_id) or ItemDB.is_quest_item(item_id):
		return
	var e: Dictionary = model.push_item(item_id, count, KIND_LIFE["item"])
	_sync(e)


func _on_notify(text: String, kind: String) -> void:
	if text.strip_edges() == "":
		return
	if model.has_key("key:" + text):
		return   # already shown with the item's icon (key item pickup)
	if kind == "quest" and quest_banner != null and quest_banner.has_method("show_text"):
		quest_banner.show_text(text)
		return
	var e: Dictionary = model.push_text(text, kind, float(KIND_LIFE.get(kind, 4.5)))
	_sync(e)
	if held:
		return
	match kind:
		"bond":
			Audio.play_ui("ui_bond")
		"warn":
			Audio.play_ui("ui_notify", -3.0)
		_:
			Audio.play_ui("ui_notify", -6.0)


func _sync(e: Dictionary) -> void:
	var id := int(e["id"])
	if views.has(id):
		var v: Dictionary = views[id]
		var bl: Label = v["label"]
		bl.text = String(e["text"])
		var p: Control = v["panel"]
		p.modulate = Color(1.2, 1.15, 1.05, 1.0)
		var tw := p.create_tween()
		tw.tween_property(p, "modulate", Color.WHITE, 0.35)
		return
	var kind := String(e["kind"])
	var col: Color = KIND_COLORS.get(kind, KIND_COLORS["info"])
	var panel := PanelContainer.new()
	var sb := ThemeFactory.box(Color(ThemeFactory.PAPER, 0.95), 16, 2, Color(ThemeFactory.BORDER_DARK, 0.6), [14, 8, 20, 9], 8, Vector2(0, 4), Color(0.1, 0.05, 0.08, 0.28))
	sb.border_width_left = 7
	sb.border_color = col
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var h := Kit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(h)
	var tex: Texture2D
	if kind == "item" and String(e["item"]) != "":
		tex = IconFactory.item_icon(String(e["item"]))
	else:
		tex = _kind_icon(kind)
	h.add_child(Kit.icon_rect(tex, 40))
	var l := Kit.label(String(e["text"]))
	l.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	l.add_theme_font_size_override("font_size", 22)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# long texts wrap at a comfortable width; short ones stay on one line
	var w := ThemeFactory.font("body_bold").get_string_size(String(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	if w > MAX_TEXT_W:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = MAX_TEXT_W
	h.add_child(l)
	add_child(panel)
	views[id] = {"panel": panel, "label": l}
	panel.modulate.a = 0.0
	var tw2 := panel.create_tween()
	tw2.tween_property(panel, "modulate:a", 1.0, 0.18)


static func _kind_icon(kind: String) -> Texture2D:
	match kind:
		"success":
			return IconFactory.icon("ui_check", Color.WHITE, 48)
		"warn":
			return IconFactory.icon("ui_warn", Color.WHITE, 48)
		"bond":
			return IconFactory.icon("ui_heart", Color("ff8fa8"), 48)
		"quest":
			return IconFactory.icon("ui_star", Color.WHITE, 48)
		"item":
			return IconFactory.icon("ui_bag", Color.WHITE, 48)
		"save":
			return IconFactory.icon("ui_save", Color.WHITE, 48)
	return IconFactory.icon("ui_info", Color.WHITE, 48)


## Hold (true) or release the toasts: held toasts keep their place in the queue and their remaining time.
func set_held(on: bool) -> void:
	held = on


func _process(delta: float) -> void:
	if views.is_empty() or held:
		return
	var gone: Array = model.tick(delta)
	for id in gone:
		if views.has(id):
			var p: Control = views[id]["panel"]
			views.erase(id)
			var tw := p.create_tween()
			tw.tween_property(p, "modulate:a", 0.0, 0.35)
			tw.tween_callback(p.queue_free)
	# keep the view list in sync if the model dropped old entries (overflow)
	if views.size() > model.entries.size():
		var alive := {}
		for e in model.entries:
			alive[int(e["id"])] = true
		for id2 in views.keys():
			if not alive.has(id2):
				var p2: Control = views[id2]["panel"]
				views.erase(id2)
				p2.queue_free()
