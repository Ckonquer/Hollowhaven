extends "res://src/ui/panels/panel_base.gd"
## Storage chest <-> backpack. Same pointer rules as the backpack (pick / place / drag / split);
## shift-click moves a whole stack to the other side; "Take all" / "Store all" buttons.
## args: {"uid": structure uid}. Chest contents live in GameState.get_storage(uid).
## Chapter Two: grids follow the real capacities (backpack 32 / 40 / 48 = GameState.inventory.size, chest 20 / 40
## = its Inventory size) and a chest that can grow shows "Upgrade to 40 slots" with the exact cost, where it is
## taken from (backpack first, then this chest) and what changes (same chest, same contents, same order).

const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")
const SlotController := preload("res://src/ui/widgets/slot_controller.gd")
const Crafting := preload("res://src/crafting/crafting.gd")

const SLOT := 88.0
const SLOT_COMPACT := 80.0        # used when the chest has 40 slots or the backpack more than 32

var uid := ""
var chest: RefCounted = null
var ctl: Control
var chest_slots: Array = []
var bag_slots: Array = []
var chest_title: Label
var info_l: Label
var chest_grid: GridContainer
var upgrade_box: VBoxContainer
var upgrade_btn: Button
var upgrade_l: Label


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	uid = String(p_args.get("uid", ""))
	title = "Storage Chest"
	window_min = Vector2(1540, 0)


func _slot_size() -> float:
	var n: int = int(chest.size) if chest != null else 0
	return SLOT_COMPACT if n > 20 or int(GameState.inventory.size) > GameState.INVENTORY_SIZE else SLOT


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
	chest_grid = GridContainer.new()
	chest_grid.add_theme_constant_override("h_separation", 10)
	chest_grid.add_theme_constant_override("v_separation", 10)
	left.add_child(chest_grid)
	_build_chest_slots()
	if chest == null:
		left.add_child(Kit.wrap_label("This chest seems to be stuck shut.", "Muted", 400))
	info_l = Kit.label("", "Small")
	left.add_child(info_l)
	upgrade_box = Kit.vbox(6)
	left.add_child(upgrade_box)
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
	var ss := _slot_size()
	for i in int(GameState.inventory.size):
		var s2 := ItemSlot.new(ss)
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


## (Re)creates the chest slot widgets for the chest's current size (5 columns up to 20 slots, 8 beyond).
func _build_chest_slots() -> void:
	for s in chest_slots:
		(ctl.get("slots") as Array).erase(s)   # the controller must never touch a freed slot
		if is_instance_valid(s):
			(s as Node).queue_free()
	chest_slots.clear()
	var n: int = int(chest.size) if chest != null else 0
	chest_grid.columns = 5 if n <= 20 else 8
	var ss := _slot_size()
	for i in n:
		var s := ItemSlot.new(ss)
		s.index = i
		s.inv = chest
		chest_slots.append(s)
		ctl.register(s)
		chest_grid.add_child(s)


func refresh() -> void:
	for s in chest_slots:
		var c: Control = s
		if is_instance_valid(c):
			c.set_stack(chest.get_slot(c.index) if chest != null else null)
	for s2 in bag_slots:
		var c2: Control = s2
		c2.set_stack(GameState.inventory.get_slot(c2.index))
	if chest != null:
		info_l.text = "%d of %d spaces free" % [int(chest.free_slots()), int(chest.size)]
	_refresh_upgrade()


# --- Chest upgrade (recipe chest_upgrade_40) --------------------------------------------------------------

func _refresh_upgrade() -> void:
	if upgrade_box == null:
		return
	var info := Crafting.chest_upgrade_info(uid) if uid != "" and chest != null else {}
	var offer := bool(info.get("offer", false))
	upgrade_box.visible = offer
	if not offer:
		return
	if upgrade_btn == null:
		var h := Kit.hbox(12)
		upgrade_box.add_child(h)
		upgrade_btn = Kit.button("Upgrade to 40 slots", _upgrade, "AccentButton")
		h.add_child(upgrade_btn)
		upgrade_l = Kit.wrap_label("", "Small", 420)
		upgrade_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		upgrade_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(upgrade_l)
	upgrade_btn.text = "Upgrade to %d slots" % int(info["to"])
	upgrade_btn.disabled = not bool(info["ok"])
	upgrade_btn.tooltip_text = String(info.get("reason", ""))
	upgrade_l.text = upgrade_preview_text(info)


## "Costs 6 Wood (you have 10), 2 Iron Bar (you have 1). 20 -> 40 slots; ..." (exact cost and source).
static func upgrade_preview_text(info: Dictionary) -> String:
	var cost: Dictionary = info.get("cost", {})
	var bits: PackedStringArray = []
	var src: Array = info.get("sources", [])
	for id in cost:
		bits.append("%d %s (you have %d)" % [int(cost[id]), ItemDB.display_name(String(id)), Crafting.count_available(String(id), src)])
	var text := "Costs " + ", ".join(bits) + ". %d -> %d slots: same chest, everything inside stays where it is." % [int(info.get("from", 20)), int(info.get("to", 40))]
	var pl: Dictionary = info.get("plan", {})
	var chests: Array = pl.get("chests", [])
	if not chests.is_empty():
		var inside := {}
		for c in chests:
			var items: Dictionary = c["items"]
			for id in items:
				inside[id] = int(inside.get(id, 0)) + int(items[id])
		text += " Uses %s from this chest." % Crafting.describe_items(inside)
	elif not bool(info.get("ok", false)) and String(info.get("reason", "")) != "":
		text += " " + String(info["reason"])
	return text


func _upgrade() -> void:
	ctl.cancel()
	if Crafting.upgrade_chest(uid):
		Audio.play_ui("ui_craft")
		_build_chest_slots()
		refresh()
	else:
		Audio.play_ui("ui_error")
		info_l.text = Crafting.last_reason


# --- Moving items ----------------------------------------------------------------------------------------------

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
	for i in range(GameState.HOTBAR_SIZE, int(GameState.inventory.size)):
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
