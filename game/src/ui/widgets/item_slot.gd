extends Control
## One inventory / hotbar / chest slot. Draws its own background, icon, count, hotbar key number and
## selection / hover / drop highlights. Emits pointer signals; the owning panel implements the rules
## (click-to-pick, drag-and-drop, split, quick-move). Tooltips show the item's name, description and stats.

signal pressed_slot(slot: Control, button: int, shift: bool, double: bool)
signal released_slot(slot: Control, button: int)
signal hovered(slot: Control)
signal unhovered(slot: Control)

const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Palette := preload("res://src/art/palette.gd")

var index: int = -1
var inv: RefCounted = null              # owning inventory (for the panel's bookkeeping)
var stack: Variant = null              # {"id", "count"} or null
var key_number: int = 0                # 1..8 shows a hotbar key badge
var selected: bool = false
var hud_style: bool = false            # translucent HUD look
var dimmed: bool = false               # source of the stack being carried
var drop_hint: bool = false
var hotbar_row: bool = false           # subtle tint for the hotbar row inside the backpack
var slot_size: float = 92.0
var _hover := false
var _pop := 0.0


func _init(p_size: float = 92.0) -> void:
	slot_size = p_size
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(self)
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		unhovered.emit(self)
		queue_redraw())


func set_stack(s: Variant) -> void:
	var changed_item := false
	if s == null:
		changed_item = stack != null
	elif stack == null or String(stack["id"]) != String(s["id"]) or int(stack["count"]) != int(s["count"]):
		changed_item = true
	stack = null if s == null else {"id": String(s["id"]), "count": int(s["count"])}
	tooltip_text = "" if stack == null else ItemDB.display_name(String(stack["id"]))
	if changed_item:
		queue_redraw()


## A short scale "pop" (e.g. when items are added).
func pop() -> void:
	_pop = 1.0
	set_process(true)


func _process(delta: float) -> void:
	if _pop <= 0.0:
		set_process(false)
		return
	_pop = maxf(_pop - delta * 4.0, 0.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			pressed_slot.emit(self, mb.button_index, mb.shift_pressed, mb.double_click)
		else:
			released_slot.emit(self, mb.button_index)
		accept_event()


func _make_custom_tooltip(_for_text: String) -> Object:
	if stack == null:
		return null
	return build_tooltip(String(stack["id"]))


## Tooltip card for an item (also used by the crafting panel).
static func build_tooltip(item_id: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeFactory.box(ThemeFactory.PAPER_LIGHT, 14, 2, ThemeFactory.BORDER_DARK, [18, 12, 18, 14], 8, Vector2(0, 4)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var name_l := Label.new()
	name_l.text = ItemDB.display_name(item_id)
	name_l.add_theme_font_override("font", ThemeFactory.font("heading"))
	name_l.add_theme_font_size_override("font_size", 26)
	name_l.add_theme_color_override("font_color", ThemeFactory.INK)
	v.add_child(name_l)
	var cat := Label.new()
	cat.text = UiUtil.category_name(ItemDB.category(item_id))
	cat.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	cat.add_theme_font_size_override("font_size", 17)
	cat.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	v.add_child(cat)
	var desc := Label.new()
	desc.text = ItemDB.display_desc(item_id)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 340
	desc.add_theme_font_size_override("font_size", 20)
	desc.add_theme_color_override("font_color", ThemeFactory.INK)
	v.add_child(desc)
	for line in UiUtil.item_stat_lines(item_id):
		var sl := Label.new()
		sl.text = "•  " + String(line)
		sl.add_theme_font_size_override("font_size", 19)
		sl.add_theme_color_override("font_color", ThemeFactory.INK_SOFT)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size.x = 340
		v.add_child(sl)
	return p


func _draw() -> void:
	var sz := size
	var r := Rect2(Vector2.ZERO, sz)
	var grow := (_pop * _pop) * 4.0
	var bg: Color
	var border: Color
	var bw := 2
	if hud_style:
		bg = Color(ThemeFactory.PAPER, 0.86)
		border = Color(ThemeFactory.BORDER_DARK, 0.85)
	else:
		bg = ThemeFactory.PAPER_MID if not hotbar_row else ThemeFactory.PAPER_MID.lerp(Color("f3d9a8"), 0.45)
		border = Color(ThemeFactory.BORDER, 0.95)
	if _hover:
		bg = bg.lightened(0.25)
		border = ThemeFactory.ACCENT.darkened(0.1)
	if drop_hint:
		border = ThemeFactory.GOOD.darkened(0.1)
		bw = 3
	if selected:
		bg = Color(ThemeFactory.PAPER_LIGHT, 0.97)
		border = ThemeFactory.ACCENT
		bw = 4
	var sb := ThemeFactory.box(bg, 16, bw, border, 0, 6 if selected else 3, Vector2(0, 3), Color(0.15, 0.08, 0.1, 0.28 if hud_style else 0.16))
	draw_style_box(sb, r.grow(grow))
	# inner soft well
	var inner := r.grow(-7.0)
	draw_style_box(ThemeFactory.box(Color(1, 1, 1, 0.16 if not selected else 0.3), 11), inner)
	if stack != null:
		var id := String(stack["id"])
		var tex := IconFactory.item_icon(id)
		var pad := sz.x * 0.1 - grow
		var ir := Rect2(Vector2(pad, pad), sz - Vector2(pad, pad) * 2.0)
		draw_texture_rect(tex, ir, false, Color(1, 1, 1, 0.35 if dimmed else 1.0))
		var n := int(stack["count"])
		if n > 1 or ItemDB.stack_max(id) > 1:
			if n > 1:
				var f := ThemeFactory.font("body_bold")
				var fs := int(round(sz.x * 0.25))
				var txt := str(n)
				var pos := Vector2(4.0, sz.y - 8.0)
				draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_RIGHT, sz.x - 12.0, fs, 7, Color(ThemeFactory.INK, 0.95))
				draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_RIGHT, sz.x - 12.0, fs, ThemeFactory.CREAM)
	if key_number > 0:
		var kc := Vector2(15, 15)
		draw_circle(kc, 12.5, ThemeFactory.ACCENT if selected else Color(ThemeFactory.INK, 0.78), true, -1.0, true)
		var f2 := ThemeFactory.font("body_bold")
		draw_string(f2, Vector2(3, 22), str(key_number), HORIZONTAL_ALIGNMENT_CENTER, 24, 18, ThemeFactory.CREAM)
	if selected and hud_style:
		# little marker above the selected slot
		var cx := sz.x * 0.5
		var tri := PackedVector2Array([Vector2(cx - 9, -14), Vector2(cx + 9, -14), Vector2(cx, -4)])
		draw_colored_polygon(tri, ThemeFactory.ACCENT)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(ThemeFactory.INK, 0.8), 2.0, true)
