extends VBoxContainer
## Hotbar: the first 8 backpack slots with icons, counts, key numbers and a selection highlight.
## Click a slot to select it; the selected item's name floats above briefly after a change.

const Kit := preload("res://src/ui/ui_kit.gd")
const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")

const SLOT := 86.0

var slots: Array = []
var name_label: Label
var _tw: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 10)
	name_label = Kit.label("", "HudText", HORIZONTAL_ALIGNMENT_CENTER)
	name_label.modulate.a = 0.0
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(name_label)
	var row := Kit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	for i in GameState.HOTBAR_SIZE:
		var s := ItemSlot.new(SLOT)
		s.hud_style = true
		s.key_number = i + 1
		s.index = i
		s.pressed_slot.connect(_on_pressed)
		row.add_child(s)
		slots.append(s)
	Events.inventory_changed.connect(refresh)
	Events.hotbar_selected.connect(_on_selected)
	Events.item_added.connect(_on_item_added)
	Events.settings_changed.connect(func(k: String) -> void:
		if k == "arachnophobia":
			for s2 in slots:
				s2.queue_redraw())
	refresh()


func refresh() -> void:
	for i in slots.size():
		var s: Control = slots[i]
		s.set_stack(GameState.inventory.get_slot(i))
		var sel := i == GameState.hotbar_index
		if s.selected != sel:
			s.selected = sel
			s.queue_redraw()


func _on_selected(i: int) -> void:
	refresh()
	var st: Variant = GameState.inventory.get_slot(i)
	name_label.text = ItemDB.display_name(String(st["id"])) if st != null else ""
	if name_label.text == "":
		return
	var tw := Kit.retween(self, _tw, "name")
	name_label.modulate.a = 1.0
	tw.tween_interval(1.3)
	tw.tween_property(name_label, "modulate:a", 0.0, 0.5)


func _on_item_added(item_id: String, _n: int) -> void:
	for s in slots:
		if s.stack != null and String(s.stack["id"]) == item_id:
			s.pop()


func _on_pressed(slot: Control, button: int, _shift: bool, _double: bool) -> void:
	if button == MOUSE_BUTTON_LEFT:
		GameState.select_hotbar(slot.index)
		Audio.play_ui("ui_click", -6.0)
