extends "res://tests/test_case.gd"
## Crafting panel, Chapter Two (headless UI): every station tab, the furnace queue view (add to queue, progress,
## collect), the "Also use nearby chests" toggle with where-from text, special recipe rows (backpack, patterns,
## dyes), the festival table choice, and the window still fits the 1920x1080 canvas with all of it shown.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Crafting := preload("res://src/crafting/crafting.gd")
const Furnace := preload("res://src/crafting/furnace.gd")

var ui: CanvasLayer
var _mode_before := ""


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_mode_before = Game.mode
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
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))
	Crafting.set_use_chests(false)


func _panel(args: Dictionary) -> Control:
	ui.open("crafting", args)
	await wait_frames(3)
	return ui.panels["crafting"]


func _fits(p: Control) -> void:
	var ms: Vector2 = p.window.get_combined_minimum_size()
	print("CRAFTING-PANEL min size ", ms, " filter ", p.filter)
	assert_true(ms.x <= 1920.0 and ms.y <= 1080.0, "crafting window fits 1920x1080 (%s, %s)" % [ms, p.filter])


func test_all_station_tabs_exist_and_fit() -> void:
	var p := await _panel({"station": "hand"})
	for t in ["all", "hand", "workbench", "campfire", "furnace", "loom", "kitchen"]:
		assert_true(p._tab_buttons.has(t), "tab " + t)
	for t in ["all", "furnace", "loom", "kitchen"]:
		p._set_filter(t)
		await wait_frames(2)
		_fits(p)
	p._set_filter("hand")
	assert_eq(String(p._rows.keys()[0]), "stone_axe", "legacy order kept")
	assert_false(p._rows.has("chest_upgrade_40"), "chest upgrade lives in the storage panel")


func test_furnace_queue_view_add_progress_collect() -> void:
	var uid := GameState.add_structure("furnace", Vector3(0, 0, 0), 0)
	GameState.stats["play_seconds"] = 0.0
	GameState.give_item("copper_ore", 20)
	var p := await _panel({"station": "furnace", "uid": uid})
	assert_eq(p.filter, "furnace")
	assert_eq(p.furnace_uid, uid)
	assert_true(p.queue_box.visible, "queue shown on the furnace tab")
	assert_true(p._rows.has("copper_bar"))
	p._selected = "copper_bar"
	p._refresh_status()
	assert_eq(String(p.craft_btn.text), "Add to queue")
	assert_false(p.craft_btn.disabled)
	for i in Furnace.capacity(uid):
		p._craft()
	await wait_frames(1)
	assert_eq(Furnace.queue(uid).size(), Furnace.capacity(uid))
	assert_true(p.craft_btn.disabled, "queue full")
	assert_true(String(p.craft_btn.tooltip_text).contains("full"), p.craft_btn.tooltip_text)
	var bars: Array = p.queue_box.find_children("*", "ProgressBar", true, false)
	assert_eq(bars.size(), Furnace.capacity(uid), "one progress bar per job")
	_fits(p)
	GameState.stats["play_seconds"] = 999.0
	Events.station_queue_changed.emit(uid)
	await wait_frames(1)
	Furnace.settle(uid)
	await wait_frames(1)
	p._collect()
	assert_eq(GameState.count_item("copper_bar"), Furnace.capacity(uid))
	assert_eq(Furnace.output(uid), {})


func test_furnace_tab_without_a_furnace_explains() -> void:
	GameState.give_item("copper_ore", 2)
	var p := await _panel({"station": "hand"})
	p._set_filter("furnace")
	await wait_frames(1)
	assert_true(p.queue_box.visible)
	var chk: Dictionary = p._check("copper_bar")
	assert_false(bool(chk["ok"]))
	assert_true(String(chk["reason"]).contains("Furnace"), String(chk["reason"]))


func test_chest_toggle_uses_nearby_chests_and_says_where_from() -> void:
	var a := GameState.add_structure("storage_chest", Vector3(2, 0, 0), 0)
	GameState.get_storage(a).add("wood", 8)
	GameState.get_storage(a).add("stone", 2)
	var p := await _panel({"station": "hand", "pos": Vector3.ZERO})
	p._selected = "workbench"
	p._refresh_status()
	assert_true(p.craft_btn.disabled, "without chests nothing to craft with")
	assert_true(String(p.chest_info_l.text).contains("1 chest"), p.chest_info_l.text)
	p.chest_toggle.button_pressed = true   # emits toggled
	await wait_frames(1)
	assert_true(Crafting.use_chests())
	assert_eq(p.sources, [a])
	assert_false(p.craft_btn.disabled, "chest ingredients count")
	var texts: PackedStringArray = []
	for l in p.detail.find_children("*", "Label", true, false):
		texts.append(String((l as Label).text))
	var joined := " | ".join(texts)
	assert_true(joined.contains("Chest 1"), "where-from names the chest: " + joined)
	p._craft()
	assert_eq(GameState.count_item("workbench"), 1)
	assert_true(GameState.get_storage(a).is_empty())


func test_loom_rows_backpack_pattern_dye() -> void:
	GameState.set_flag("c1x_tailor_cache", true)
	GameState.give_item("woven_cloth", 5)
	GameState.give_item("copper_bar", 2)
	GameState.give_item("roseberries", 4)
	var p := await _panel({"station": "loom"})
	assert_true(p._rows.has("backpack_40"))
	assert_true(p._rows.has("pattern_ribbon_bow"))
	assert_true(p._rows.has("dye:rose"))
	p._selected = "backpack_40"
	p._refresh_status()
	assert_eq(String(p.craft_btn.text), "Upgrade")
	p._craft()
	assert_eq(int(GameState.inventory.size), 40)
	p._selected = "dye:rose"
	p._refresh_status()
	assert_eq(String(p.craft_btn.text), "Mix dye")
	p._craft()
	assert_true(Crafting.owns_palette("rose"))
	p._build_list()
	assert_false(p._rows.has("backpack_40"), "a finished backpack upgrade leaves the list")
	assert_true(p._rows.has("backpack_48"))
	_fits(p)


func test_kitchen_festival_table_choice() -> void:
	GameState.set_flag("ch2_accepted", true)
	var p := await _panel({"station": "kitchen"})
	var buttons: Array = p.list_box.find_children("*", "Button", true, false)
	var found := false
	for b in buttons:
		if String((b as Button).text) == "Pumpkins":
			found = true
			(b as Button).pressed.emit()
	assert_true(found, "table choice shown at the kitchen")
	await wait_frames(1)
	assert_true(bool(GameState.get_flag("ch2_table_decorated")))
	assert_eq(Crafting.table_decor(), "pumpkins")
	_fits(p)
