extends "res://tests/test_case.gd"
## Chest 20 -> 40 upgrade in place (MP 3 / 5.4 / 16, spec 3.4 / 4.3): same uid, same contents in the same slots,
## data.slots = 40 saved and honoured on load, refused without ingredients or when already 40, ingredients from
## the backpack first and then this chest, and the storage panel's upgrade button with an exact cost preview.

const Crafting := preload("res://src/crafting/crafting.gd")
const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const StoragePanel := preload("res://src/ui/panels/storage_panel.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")

var _uid := ""
var ui: CanvasLayer
var _mode_before := ""


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_uid = GameState.add_structure("storage_chest", Vector3(1.5, 0, 1.5), 90)
	_mode_before = Game.mode


func after_each() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
		ui = null
		await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _fill_chest() -> Array:
	var inv = GameState.get_storage(_uid)
	var ids := ["stone", "fiber", "berries", "glowcap", "echo_shard"]
	for i in inv.size:
		if i % 3 != 2:
			inv.set_slot(i, {"id": ids[i % ids.size()], "count": i + 1})
	return inv.to_array()


func test_upgrade_keeps_uid_contents_and_order() -> void:
	var before := _fill_chest()
	var rec_before: Dictionary = GameState.structures[_uid].duplicate(true)
	var inv_obj = GameState.get_storage(_uid)
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 2)
	var info := Crafting.chest_upgrade_info(_uid)
	assert_true(bool(info["offer"]))
	assert_true(bool(info["ok"]), String(info["reason"]))
	assert_eq(info["cost"], {"wood": 6, "iron_bar": 2})
	assert_true(Crafting.upgrade_chest(_uid), Crafting.last_reason)
	var inv = GameState.get_storage(_uid)
	assert_true(inv == inv_obj, "same Inventory object (open panels keep their connection)")
	assert_eq(int(inv.size), 40)
	assert_eq(inv.to_array().slice(0, 20), before, "every stack in its old slot")
	for i in range(20, 40):
		assert_null(inv.get_slot(i), "new slot %d empty" % i)
	assert_eq(int(GameState.structures[_uid]["data"]["slots"]), 40)
	for k in ["id", "area", "pos", "rot"]:
		assert_eq(GameState.structures[_uid][k], rec_before[k], "record %s unchanged" % k)
	assert_eq(GameState.count_item("wood"), 0)
	assert_eq(GameState.count_item("iron_bar"), 0)
	assert_false(bool(Crafting.chest_upgrade_info(_uid)["offer"]), "no second upgrade")
	assert_false(Crafting.upgrade_chest(_uid))
	# Save / load (twice): the chest stays at 40 and keeps a stack in its new slot.
	inv.set_slot(39, {"id": "resin", "count": 3})
	for n in 2:
		GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	var inv2 = GameState.get_storage(_uid)
	assert_eq(int(inv2.size), 40)
	assert_eq(inv2.get_slot(39), {"id": "resin", "count": 3})
	assert_eq(inv2.to_array().slice(0, 20), before)
	assert_true(GameState.structures.has(_uid), "same uid after load")


func test_upgrade_refused_without_ingredients_changes_nothing() -> void:
	var before := _fill_chest()
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 1)
	var bag: Array = GameState.inventory.to_array()
	var info := Crafting.chest_upgrade_info(_uid)
	assert_true(bool(info["offer"]))
	assert_false(bool(info["ok"]))
	assert_true(String(info["reason"]).contains("Iron Bar"), String(info["reason"]))
	assert_false(Crafting.upgrade_chest(_uid))
	assert_eq(int(GameState.get_storage(_uid).size), 20)
	assert_eq(GameState.get_storage(_uid).to_array(), before)
	assert_eq(GameState.inventory.to_array(), bag)
	assert_false((GameState.structures[_uid]["data"] as Dictionary).has("slots"))


func test_upgrade_takes_backpack_first_then_this_chest() -> void:
	GameState.give_item("wood", 4)
	GameState.give_item("iron_bar", 2)
	GameState.get_storage(_uid).add("wood", 5)
	var info := Crafting.chest_upgrade_info(_uid)
	assert_true(bool(info["ok"]), String(info["reason"]))
	assert_eq(info["plan"]["backpack"], {"wood": 4, "iron_bar": 2})
	assert_eq(info["plan"]["chests"], [{"uid": _uid, "items": {"wood": 2}}])
	assert_true(StoragePanel.upgrade_preview_text(info).contains("from this chest"), StoragePanel.upgrade_preview_text(info))
	assert_true(Crafting.upgrade_chest(_uid))
	assert_eq(GameState.get_storage(_uid).count_of("wood"), 3)
	assert_eq(int(GameState.get_storage(_uid).size), 40)


func test_only_real_storage_chests_can_be_upgraded() -> void:
	var bench := GameState.add_structure("workbench", Vector3(4, 0, 0), 0)
	GameState.give_item("wood", 20)
	GameState.give_item("iron_bar", 6)
	assert_false(bool(Crafting.chest_upgrade_info(bench)["offer"]))
	assert_false(Crafting.upgrade_chest(bench))
	assert_false(Crafting.upgrade_chest("s_missing"))
	assert_false(bool(Crafting.check("chest_upgrade_40", ["hand"])["ok"]), "needs a target chest")
	assert_eq(GameState.count_item("iron_bar"), 6)


func test_upgraded_chest_other_area_record_kept_on_load() -> void:
	var reach := GameState.add_structure("storage_chest", Vector3(0, 0, 0), 0, "hallowmere_reach")
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 2)
	assert_true(Crafting.upgrade_chest(reach))
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(int(GameState.get_storage(reach).size), 40)
	assert_eq(int(GameState.get_storage(_uid).size), 20, "other chests untouched")


## Dismantling an upgraded chest (the real BuildOps flow) returns its contents, the chest item AND the upgrade kit,
## once; a plain chest gives no kit; a refund done before the removal is never paid again.
func test_dismantling_an_upgraded_chest_returns_the_kit_once() -> void:
	var area: Node3D = AreaBase.new()
	area.area_id = "surface"
	add_child(area)
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 2)
	assert_true(Crafting.upgrade_chest(_uid))
	GameState.get_storage(_uid).set_slot(35, {"id": "stone", "count": 4})
	var n := Factory.spawn_structure(area, _uid)
	assert_not_null(n)
	var res := Ops.dismantle(area, _uid)
	assert_true(bool(res["ok"]), String(res.get("reason", "")))
	assert_eq(GameState.count_item("wood"), 6, "upgrade kit: wood back")
	assert_eq(GameState.count_item("iron_bar"), 2, "upgrade kit: iron bars back")
	assert_eq(GameState.count_item("stone"), 4, "contents back (BuildOps)")
	assert_eq(GameState.count_item("storage_chest"), 1, "the chest item (BuildOps)")
	if is_instance_valid(n):
		n.play_remove_and_free()
	assert_eq(GameState.count_item("iron_bar"), 2, "never twice")
	# A plain 20-slot chest gives no kit.
	var plain := GameState.add_structure("storage_chest", Vector3(4.5, 0, 1.5), 0)
	Factory.spawn_structure(area, plain)
	assert_true(bool(Ops.dismantle(area, plain)["ok"]))
	assert_eq(GameState.count_item("iron_bar"), 2)
	assert_eq(GameState.count_item("storage_chest"), 2)
	# A refund done before the removal (an explicit build_ops hook) marks the record: the node pays nothing more.
	var third := GameState.add_structure("storage_chest", Vector3(-3.5, 0, 1.5), 0)
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 2)
	assert_true(Crafting.upgrade_chest(third))
	Factory.spawn_structure(area, third)
	assert_eq(Crafting.refund_chest_upgrade(GameState.structures[third]), {"wood": 6, "iron_bar": 2})
	assert_eq(Crafting.refund_chest_upgrade(GameState.structures[third]), {}, "marked")
	assert_true(bool(Ops.dismantle(area, third)["ok"]))
	assert_eq(GameState.count_item("iron_bar"), 4, "kit paid once per upgrade")
	area.free()


# --- Storage panel -----------------------------------------------------------------------------------------

func _open_ui() -> void:
	Game.mode = "playing"
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func test_storage_panel_upgrade_button_and_grid_rebuild() -> void:
	await _open_ui()
	_fill_chest()
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 2)
	ui.open("storage", {"uid": _uid})
	await wait_frames(3)
	var p: Control = ui.panels["storage"]
	assert_eq(p.chest_slots.size(), 20)
	assert_eq(p.bag_slots.size(), int(GameState.inventory.size))
	assert_true(p.upgrade_box.visible, "upgrade offered")
	assert_false(p.upgrade_btn.disabled)
	assert_true(String(p.upgrade_l.text).contains("6 Wood") and String(p.upgrade_l.text).contains("2 Iron Bar"), String(p.upgrade_l.text))
	p._upgrade()
	await wait_frames(2)
	assert_eq(p.chest_slots.size(), 40, "grid rebuilt for 40 slots")
	assert_eq(p.chest_grid.columns, 8)
	assert_false(p.upgrade_box.visible, "no further upgrade")
	var w: Control = p.window
	assert_true(w.get_combined_minimum_size().x <= 1920.0 and w.get_combined_minimum_size().y <= 1080.0, "fits the canvas: %s" % w.get_combined_minimum_size())
	ui.close("storage")
	await wait_frames(2)


func test_storage_panel_follows_a_48_slot_backpack_and_fits() -> void:
	GameState.set_backpack_capacity(48)
	GameState.inventory.set_slot(47, {"id": "stone", "count": 3})
	GameState.give_item("wood", 6)
	GameState.give_item("iron_bar", 2)
	assert_true(Crafting.upgrade_chest(_uid))
	await _open_ui()
	ui.open("storage", {"uid": _uid})
	await wait_frames(3)
	var p: Control = ui.panels["storage"]
	assert_eq(p.bag_slots.size(), 48)
	assert_eq(p.chest_slots.size(), 40)
	var ms: Vector2 = p.window.get_combined_minimum_size()
	print("STORAGE-48/40 min size ", ms)
	assert_true(ms.x <= 1920.0 and ms.y <= 1080.0, "48-slot backpack + 40-slot chest fit 1920x1080: %s" % ms)
	# Store all reaches the extra slots.
	p._store_all()
	assert_null(GameState.inventory.get_slot(47), "slot 47 stored")
	assert_eq(GameState.get_storage(_uid).count_of("stone"), 3)
	ui.close("storage")
	await wait_frames(2)
