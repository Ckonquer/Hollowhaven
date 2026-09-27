extends "res://src/ui/panels/panel_base.gd"
## Storage chest <-> backpack. Same pointer rules as the backpack (pick / place / drag / split);
## shift-click moves a whole stack to the other side; "Take all" / "Store all" buttons.
## args: {"uid": structure uid}. Chest contents live in GameState.get_storage(uid).

const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")
const SlotController := preload("res://src/ui/widgets/slot_controller.gd")

const SLOT := 88.0

var uid := ""
var chest: RefCounted = null
var ctl: Control
var chest_slots: Array = []
var bag_slots: Array = []
var chest_title: Label
var info_l: Label


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	uid = String(p_args.get("uid", ""))
	title = "Storage Chest"
	window_min = Vector2(1540, 0)


func _build() -> void:
	chest = GameState.get_storage(uid) if uid != "" else null
	ctl = SlotController.new()
	add_child(ctl)
	ctl.quick_move = _quick_move
	var cols := Kit.hbox(40)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	# chest
	var left := Kit.vbox(10)
	cols.add_child(left)
	var lh := Kit.hbox(10)
	left.add_child(lh)
	lh.add_child(section_title("Chest"))
	lh.add_child(Kit.expander())
	lh.add_child(Kit.button("Take all", _take_all))
	var cg := GridContainer.new()
	cg.columns = 5
	cg.add_theme_constant_override("h_separation", 10)
	cg.add_theme_constant_override("v_separation", 10)
	left.add_child(cg)
	var n: int = int(chest.size) if chest != null else 0
	for i in n:
		var s := ItemSlot.new(SLOT)
		s.index = i
		s.inv = chest
		chest_slots.append(s)
		ctl.register(s)
		cg.add_child(s)
	if chest == null:
		left.add_child(Kit.wrap_label("This chest seems to be stuck shut.", "Muted", 400))
	info_l = Kit.label("", "Small")
	left.add_child(info_l)
	cols.add_child(VSeparator.new())
	# backpack
	var right := Kit.vbox(10)
	cols.add_child(right)
	var rh := Kit.hbox(10)
	right.add_child(rh)
	rh.add_child(section_title("Backpack"))
	rh.add_child(Kit.expander())
	var dep := Kit.button("Store all", _store_all)
	dep.tooltip_text = "Store everything except your hotbar."
	rh.add_child(dep)
	var bg := GridContainer.new()
	bg.columns = 8
	bg.add_theme_constant_override("h_separation", 10)
	bg.add_theme_constant_override("v_separation", 10)
	right.add_child(bg)
	for i in GameState.INVENTORY_SIZE:
		var s2 := ItemSlot.new(SLOT)
		s2.index = i
		s2.inv = GameState.inventory
		s2.hotbar_row = i < GameState.HOTBAR_SIZE
		s2.key_number = i + 1 if i < GameState.HOTBAR_SIZE else 0
		bag_slots.append(s2)
		ctl.register(s2)
		bg.add_child(s2)
	body.add_child(Kit.wrap_label("Click to pick up and place  ·  Drag to move  ·  Shift-click: send to the other side  ·  Right-click: take half", "Small", 1400, HORIZONTAL_ALIGNMENT_CENTER))
	Events.inventory_changed.connect(refresh)
	if chest != null and chest.has_signal("changed"):
		chest.connect("changed", refresh)


func refresh() -> void:
	for s in chest_slots:
		var c: Control = s
		c.set_stack(chest.get_slot(c.index) if chest != null else null)
	for s2 in bag_slots:
		var c2: Control = s2
		c2.set_stack(GameState.inventory.get_slot(c2.index))
	if chest != null:
		info_l.text = "%d of %d spaces free" % [int(chest.free_slots()), int(chest.size)]


func _quick_move(s: Control) -> void:
	if chest == null:
		return
	var other: RefCounted = GameState.inventory if s.inv == chest else chest
	var moved := int(s.inv.transfer_slot_to(other, s.index))
	if moved <= 0:
		Audio.play_ui("ui_error", -4.0)


func _take_all() -> void:
	if chest == null:
		return
	ctl.cancel()
	var any := false
	for i in int(chest.size):
		if chest.get_slot(i) != null:
			if int(chest.transfer_slot_to(GameState.inventory, i)) > 0:
				any = true
	Audio.play_ui("ui_click" if any else "ui_error")
	if chest.free_slots() < int(chest.size) and not any:
		info_l.text = "Your backpack is full."


func _store_all() -> void:
	if chest == null:
		return
	ctl.cancel()
	var any := false
	for i in range(GameState.HOTBAR_SIZE, GameState.INVENTORY_SIZE):
		if GameState.inventory.get_slot(i) != null:
			if int(GameState.inventory.transfer_slot_to(chest, i)) > 0:
				any = true
	Audio.play_ui("ui_click" if any else "ui_error")


func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed("pause") and ctl.is_holding():
		ctl.cancel()
		return true
	return false


func on_close() -> void:
	ctl.cancel()
	if chest != null and chest.has_signal("changed") and chest.is_connected("changed", refresh):
		chest.disconnect("changed", refresh)
