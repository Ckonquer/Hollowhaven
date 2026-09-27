extends HBoxContainer
## Active companion portrait with name, bond hearts and what they're doing. Hidden when nobody follows.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var portrait: Control
var name_l: Label
var hearts_box: HBoxContainer
var _tex: Texture2D
var _id := ""
var _level := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	portrait = Control.new()
	portrait.custom_minimum_size = Vector2(78, 78)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.draw.connect(_draw_portrait)
	add_child(portrait)
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	name_l = Kit.label("", "HudText")
	name_l.add_theme_font_override("font", ThemeFactory.font("heading"))
	name_l.add_theme_font_size_override("font_size", 26)
	v.add_child(name_l)
	hearts_box = Kit.hbox(0)
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hearts_box)
	Events.companion_assignment_changed.connect(func(_i: String, _a: String) -> void: refresh())
	Events.companion_bond_changed.connect(func(_i: String, _l: int) -> void: refresh(true))
	Events.companion_befriended.connect(func(_i: String) -> void: refresh())
	Events.area_loaded.connect(func(_a: String) -> void: refresh())
	Events.game_loaded.connect(refresh)
	refresh()


func refresh(bump: bool = false) -> void:
	var id := GameState.active_companion
	if id == "" or ItemDB.creature(id).is_empty():
		visible = false
		_id = ""
		return
	visible = true
	var lvl := GameState.bond_level(id)
	if id != _id:
		_id = id
		_tex = IconFactory.portrait(id)
		portrait.queue_redraw()
		name_l.text = String(ItemDB.creature(id).get("name", id.capitalize()))
	if lvl != _level:
		_level = lvl
		for c in hearts_box.get_children():
			c.queue_free()
		var hb := Kit.hearts(lvl, 5, 26)
		hearts_box.add_child(hb)
	if bump:
		modulate = Color(1.3, 1.15, 1.2)
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color.WHITE, 0.8)


func _draw_portrait() -> void:
	var c := portrait.size * 0.5
	var r := 36.0
	portrait.draw_circle(c + Vector2(0, 3), r + 3.0, Color(0, 0, 0, 0.25), true, -1.0, true)
	portrait.draw_circle(c, r + 3.0, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
	if _tex != null:
		portrait.draw_texture_rect(_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	portrait.draw_arc(c, r + 1.5, 0.0, TAU, 64, ThemeFactory.INK, 3.0, true)
