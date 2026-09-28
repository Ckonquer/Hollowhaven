extends "res://tests/test_case.gd"
## The backpack's equipment slots and stats card (src/ui/panels/inventory_panel.gd): transactional equip /
## unequip (click, drag, double-click), full backpack, duplicates, the charm slot, readable stats, tooltips,
## grown backpacks fitting the canvas, and "opening a menu never unequips the lantern or changes the tool".

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const InventoryPanel := preload("res://src/ui/panels/inventory_panel.gd")
const ItemSlot := preload("res://src/ui/widgets/item_slot.gd")
const PlayerScript := preload("res://src/player/player.gd")
const CANVAS := Vector2(1920, 1080)

var ui: CanvasLayer
var _mode_before := ""
var _player_before: Node3D = null


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_mode_before = Game.mode
	_player_before = Game.player
	Game.mode = "playing"
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func after_each() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	Game.player = _player_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))
	for c in get_children():
		c.queue_free()
	await wait_frames(1)


func _open() -> Control:
	ui.open("inventory")
	await wait_frames(2)
	return ui.panels["inventory"]


func _slot_of(id: String) -> int:
	for i in GameState.inventory.size:
		var s: Variant = GameState.inventory.get_slot(i)
		if s != null and String(s["id"]) == id:
			return i
	return -1


func _total(id: String) -> int:
	return GameState.count_item(id) + GameState.equipped_count(id)


func _stat(panel: Control, id: String) -> String:
	for h in panel.stats_box.get_children():
		if h.has_meta("stat_id") and String(h.get_meta("stat_id")) == id and not h.is_queued_for_deletion():
			return String((h.get_child(1) as Label).text)
	return ""


func test_use_action_labels() -> void:
	assert_eq(InventoryPanel.use_action("padded_vest"), "Equip")
	assert_eq(InventoryPanel.use_action("gatherers_charm"), "Equip")
	assert_eq(InventoryPanel.use_action("berries"), "Eat", "legacy")
	assert_eq(InventoryPanel.use_action("stone"), "", "legacy")


func test_equip_and_unequip_by_click() -> void:
	GameState.give_item("padded_vest", 1)
	var panel: Control = await _open()
	assert_eq(panel.equip_slots.size(), 4, "head / body / boots / charm")
	var idx := _slot_of("padded_vest")
	assert_true(panel.equip_from_backpack(idx), "double-click / Equip wears it")
	assert_eq(GameState.equipped("body"), "padded_vest")
	assert_eq(GameState.count_item("padded_vest"), 0, "moved out of the backpack")
	await wait_frames(1)
	assert_eq(String(panel.equip_slots["body"].stack["id"]), "padded_vest", "the slot shows it")
	assert_eq(_stat(panel, "protection"), "3%", "stats card updated")
	panel._on_equip_pressed(panel.equip_slots["body"], MOUSE_BUTTON_LEFT, false, false, "body")
	assert_eq(GameState.equipped("body"), "", "clicking a worn piece takes it off")
	assert_eq(GameState.count_item("padded_vest"), 1, "back in the backpack")
	assert_eq(_total("padded_vest"), 1, "never duplicated")


func test_drag_only_onto_the_matching_slot() -> void:
	GameState.give_item("padded_hood", 1)
	var panel: Control = await _open()
	var idx := _slot_of("padded_hood")
	var src: Control = panel.slots[idx]
	panel.ctl._pick(src, 1)
	assert_true(panel.ctl.is_holding())
	assert_false(panel.equip_held("body"), "a hood doesn't go in the body slot")
	assert_true(panel.ctl.is_holding(), "still carried after a wrong drop")
	assert_true(String(panel.msg_l.text).contains("Head"), "says where it goes: " + String(panel.msg_l.text))
	assert_true(panel.equip_held("head"), "dropped on the head slot")
	assert_false(panel.ctl.is_holding())
	assert_eq(GameState.equipped("head"), "padded_hood")
	assert_eq(_total("padded_hood"), 1)


func test_swap_puts_the_old_piece_in_the_same_slot() -> void:
	GameState.give_item("padded_hood", 1)
	assert_true(GameState.equip("padded_hood"))
	GameState.give_item("copperwood_hood", 1)
	var panel: Control = await _open()
	var idx := _slot_of("copperwood_hood")
	assert_true(panel.equip_from_backpack(idx))
	assert_eq(GameState.equipped("head"), "copperwood_hood")
	assert_eq(String(GameState.inventory.get_slot(idx)["id"]), "padded_hood", "the old hood takes its place")


func test_full_backpack_refuses_to_take_off_and_loses_nothing() -> void:
	GameState.give_item("ironwood_mail", 1)
	assert_true(GameState.equip("ironwood_mail"))
	var fill := ["wood", "stone", "fiber", "copper_ore", "glowcap", "silk", "echo_shard", "shiny_pebble"]
	var k := 0
	while GameState.inventory.free_slots() > 0:
		GameState.inventory.add(String(fill[k % fill.size()]), ItemDB.stack_max(String(fill[k % fill.size()])))
		k += 1
	var panel: Control = await _open()
	var before: Array = GameState.inventory.to_array().duplicate(true)
	assert_false(panel.unequip_slot("body"), "refused")
	assert_eq(GameState.equipped("body"), "ironwood_mail", "still worn, not dropped")
	assert_true(String(panel.msg_l.text).to_lower().contains("full"), String(panel.msg_l.text))
	assert_eq(GameState.inventory.to_array(), before, "backpack untouched")
	assert_eq(_total("ironwood_mail"), 1)


func test_duplicates_and_charm_slot() -> void:
	GameState.give_item("ironwood_helm", 2)
	GameState.give_item("gatherers_charm", 1)
	GameState.give_item("swiftstep_charm", 1)
	var panel: Control = await _open()
	assert_true(panel.equip_from_backpack(_slot_of("ironwood_helm")))
	assert_eq(GameState.count_item("ironwood_helm"), 1, "the second helm stays in the backpack")
	assert_eq(GameState.equipped_count("ironwood_helm"), 1)
	assert_true(panel.equip_from_backpack(_slot_of("ironwood_helm")), "wearing the same kind again is a no-op success")
	assert_eq(_total("ironwood_helm"), 2, "two helms, never three, never one")
	assert_true(panel.equip_from_backpack(_slot_of("gatherers_charm")))
	assert_eq(GameState.equipped("charm"), "gatherers_charm", "charms go to the charm slot")
	assert_true(panel.equip_from_backpack(_slot_of("swiftstep_charm")))
	assert_eq(GameState.equipped("charm"), "swiftstep_charm", "one charm at a time")
	assert_eq(GameState.count_item("gatherers_charm"), 1, "the other charm is back in the backpack")
	GameState.give_item("berries", 1)
	assert_false(panel.equip_from_backpack(_slot_of("berries")), "food can't be worn")
	assert_eq(GameState.count_item("berries"), 1)


func test_stats_card_lists_rows_and_companion() -> void:
	GameState.give_item("copper_sword", 1)
	var panel: Control = await _open()
	assert_eq(_stat(panel, "damage"), "18", "damage row")
	assert_eq(_stat(panel, "protection"), "0%", "protection row")
	assert_eq(_stat(panel, "speed"), "normal", "speed row")
	assert_true(panel.companion_box.get_child_count() >= 1, "companion support section")


func test_opening_the_menu_keeps_the_lantern_and_the_selected_tool() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	GameState.give_item("stone_axe", 1)
	GameState.give_item("lantern", 1)
	GameState.give_item("padded_boots", 1)
	var player: CharacterBody3D = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	Game.player = player
	GameState.select_hotbar(1)
	player.set_lantern(true)
	await wait_physics(4)
	var inv_before: Array = GameState.inventory.to_array().duplicate(true)
	var panel: Control = await _open()
	await wait_frames(3)
	panel.equip_from_backpack(_slot_of("padded_boots"))
	ui.close("inventory")
	await wait_frames(3)
	assert_eq(GameState.hotbar_index, 1, "selected hotbar slot unchanged")
	assert_true(player.lantern_on, "lantern still raised")
	assert_true(bool(GameState.player["lantern_on"]))
	assert_true(GameState.has_item("lantern"), "the lantern is never equipped away")
	assert_eq(GameState.equip_slot_for("lantern"), "", "the lantern is not wearable gear")
	var inv_after: Array = GameState.inventory.to_array()
	for i in inv_before.size():
		var b: Variant = inv_before[i]
		if b != null and String(b["id"]) == "padded_boots":
			continue
		assert_eq(inv_after[i], b, "slot %d untouched" % i)


func test_grown_backpack_fits_the_canvas() -> void:
	assert_true(GameState.set_backpack_capacity(48))
	for id in ["wood", "stone", "fiber", "stone_axe", "lantern", "ironwood_mail", "sparkseed_wand"]:
		GameState.give_item(id, 1)
	GameState.inventory.set_slot(47, {"id": "berries", "count": 3})
	var panel: Control = await _open()
	assert_eq(panel.slots.size(), 48, "one slot per backpack slot")
	await wait_frames(2)
	var w: Control = panel.window
	var ms: Vector2 = w.get_combined_minimum_size()
	print("B3-LAYOUT inventory 48 slots min=", ms)
	assert_true(ms.x <= CANVAS.x, "width %.0f" % ms.x)
	assert_true(ms.y <= CANVAS.y, "height %.0f" % ms.y)
	assert_eq(String(panel.slots[47].stack["id"]), "berries", "the last slot is shown")
	assert_true(GameState.set_backpack_capacity(48) == false, "no shrink / no-op")


func test_capacity_growing_while_open_adds_slots() -> void:
	var panel: Control = await _open()
	assert_eq(panel.slots.size(), 32)
	assert_true(GameState.set_backpack_capacity(40))
	await wait_frames(1)
	assert_eq(panel.slots.size(), 40, "grid grows with the backpack")


func test_equipment_tooltip_lines() -> void:
	var mail: Array = ItemSlot.equipment_stat_lines("ironwood_mail")
	assert_true(" | ".join(PackedStringArray(mail)).contains("10% protection"), str(mail))
	assert_true(" | ".join(PackedStringArray(mail)).contains("Ironwood set: 20%"), str(mail))
	var charm: Array = ItemSlot.equipment_stat_lines("swiftstep_charm")
	assert_true(" | ".join(PackedStringArray(charm)).contains("Stamina costs -12%"), str(charm))
	var wand: Array = ItemSlot.equipment_stat_lines("sparkseed_wand")
	assert_true(" | ".join(PackedStringArray(wand)).contains("9 damage, up to 14 m"), str(wand))
	var tool: Array = ItemSlot.equipment_stat_lines("copper_axe")
	assert_true(" | ".join(PackedStringArray(tool)).contains("50%"), str(tool))
	assert_eq(ItemSlot.equipment_stat_lines("berries"), [], "no extra lines for food")
	assert_eq(ItemSlot.equipment_stat_lines("stone_axe"), ["Tier: Familiar"], "stone tools: just the tier")
