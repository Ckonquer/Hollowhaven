extends PanelContainer
## Build-mode bar (Events.build_mode_changed / build_selection_changed / build_placement_state):
## the placeable items you carry (selected one highlighted), live validity of the ghost preview and
## key hints (place, rotate, dismantle, exit) using the current bindings.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var selected_item := ""
var valid := true
var reason := ""
var active := false
var item_row: HBoxContainer
var name_l: Label
var state_l: Label
var keys_box: HBoxContainer
var _tw: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "HudCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := Kit.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := Kit.hbox(16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var tv := Kit.vbox(0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.custom_minimum_size.x = 300
	top.add_child(tv)
	var hdr := Kit.label("BUILD MODE", "Tiny")
	hdr.add_theme_color_override("font_color", ThemeFactory.TEAL.darkened(0.2))
	tv.add_child(hdr)
	name_l = Kit.label("", "CardTitle")
	tv.add_child(name_l)
	state_l = Kit.label("", "GoodText")
	tv.add_child(state_l)
	item_row = Kit.hbox(6)
	item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(item_row)
	keys_box = Kit.hbox(14)
	keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(keys_box)
	visible = false
	Events.build_mode_changed.connect(set_active)
	Events.build_selection_changed.connect(func(item_id: String) -> void:
		selected_item = item_id
		_refresh())
	Events.build_placement_state.connect(func(ok: bool, why: String) -> void:
		valid = ok
		reason = why
		_refresh_state())
	Events.inventory_changed.connect(func() -> void:
		if active:
			_refresh())


func set_active(on: bool) -> void:
	active = on
	if on:
		visible = true
		_refresh()
		modulate.a = 0.0
		var tw := Kit.retween(self, _tw, "fade")
		tw.tween_property(self, "modulate:a", 1.0, 0.2)
	else:
		var tw2 := Kit.retween(self, _tw, "fade")
		tw2.tween_property(self, "modulate:a", 0.0, 0.2)
		tw2.tween_callback(func() -> void:
			if not active:
				visible = false)


func _refresh() -> void:
	for c in item_row.get_children():
		c.queue_free()
	var totals: Dictionary = GameState.inventory.totals()
	var shown := 0
	for id in totals:
		if ItemDB.category(String(id)) != "placeable":
			continue
		if shown >= 8:
			break
		shown += 1
		var cell := PanelContainer.new()
		var sel := String(id) == selected_item
		cell.add_theme_stylebox_override("panel", ThemeFactory.box(ThemeFactory.PAPER_LIGHT if sel else Color(ThemeFactory.PAPER_DARK, 0.7), 12, 3 if sel else 1, ThemeFactory.ACCENT if sel else ThemeFactory.BORDER, 4))
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ov := Control.new()
		ov.custom_minimum_size = Vector2(54, 54)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Kit.icon_rect(IconFactory.item_icon(String(id)), 54)
		ov.add_child(ic)
		var cnt := Kit.label(str(int(totals[id])), "HudSmall", HORIZONTAL_ALIGNMENT_RIGHT)
		cnt.position = Vector2(0, 30)
		cnt.size = Vector2(52, 24)
		ov.add_child(cnt)
		cell.add_child(ov)
		item_row.add_child(cell)
	name_l.text = ItemDB.display_name(selected_item) if selected_item != "" else "Choose something to place"
	for c2 in keys_box.get_children():
		c2.queue_free()
	for pair in [["attack", "Place"], ["build_rotate", "Rotate"], ["build_dismantle", "Dismantle"], ["build", "Exit"]]:
		var h := Kit.hbox(6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(Kit.key_cap(Settings.action_label(String(pair[0]))))
		var l := Kit.label(String(pair[1]), "Small")
		l.add_theme_color_override("font_color", ThemeFactory.INK)
		h.add_child(l)
		keys_box.add_child(h)
	_refresh_state()


func _refresh_state() -> void:
	if selected_item == "":
		state_l.text = "Pick a buildable item from your hotbar"
		state_l.theme_type_variation = "Small"
		return
	if valid:
		state_l.text = "Ready to place"
		state_l.theme_type_variation = "GoodText"
	else:
		state_l.text = reason if reason != "" else "Can't place here"
		state_l.theme_type_variation = "BadText"
