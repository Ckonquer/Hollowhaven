extends "res://tests/test_case.gd"
## Placing & dismantling (refunds, chest rules, roof rules, bed respawn), persistence round trips and
## the live BuildMode node driven through its debug cursor in a tiny test area with physics.

const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const BuildingSystem := preload("res://src/building/building_system.gd")
const Farming := preload("res://src/farming/farming.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _removed: Array = []
var _placed: Array = []
var _area: Node3D
var _prev_mode := ""


func before_each() -> void:
	fresh_state()
	_removed = []
	_placed = []
	_prev_mode = Game.mode
	if not Events.structure_removed.is_connected(_on_removed):
		Events.structure_removed.connect(_on_removed)
	if not Events.structure_placed.is_connected(_on_placed):
		Events.structure_placed.connect(_on_placed)


func after_each() -> void:
	Events.structure_removed.disconnect(_on_removed)
	Events.structure_placed.disconnect(_on_placed)
	Game.mode = _prev_mode
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null


func _on_removed(uid: String, sid: String) -> void:
	_removed.append([uid, sid])


func _on_placed(uid: String, sid: String) -> void:
	_placed.append([uid, sid])


## A tiny "surface" area with flat ground collision (layer world) at y = 0.
func _make_area() -> Node3D:
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)
	return _area


func test_dismantle_refunds_the_item() -> void:
	var uid := GameState.add_structure("workbench", Vector3(2, 0, 2.5), 0)
	var res := Ops.dismantle(null, uid)
	assert_true(bool(res["ok"]), String(res.get("reason", "")))
	assert_eq(GameState.count_item("workbench"), 1, "100% refund")
	assert_false(GameState.structures.has(uid))
	assert_eq(_removed, [[uid, "workbench"]])
	assert_false(bool(Ops.dismantle(null, uid)["ok"]), "can't dismantle twice")
	assert_eq(GameState.count_item("workbench"), 1, "no double refund")


func test_chest_contents_move_to_backpack_when_they_fit() -> void:
	var uid := GameState.add_structure("storage_chest", Vector3(2.5, 0, 2.5), 0)
	GameState.get_storage(uid).add("stone", 30)
	GameState.get_storage(uid).add("berries", 7)
	assert_true(bool(Ops.dismantle(null, uid)["ok"]))
	assert_eq(GameState.count_item("stone"), 30)
	assert_eq(GameState.count_item("berries"), 7)
	assert_eq(GameState.count_item("storage_chest"), 1)
	assert_false(GameState.storages.has(uid))


func test_chest_refuses_when_contents_do_not_fit() -> void:
	var uid := GameState.add_structure("storage_chest", Vector3(2.5, 0, 2.5), 0)
	GameState.get_storage(uid).add("stone", 10)
	for i in GameState.inventory.size:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})
	var before: Array = GameState.inventory.to_array()
	var res := Ops.dismantle(null, uid)
	assert_false(bool(res["ok"]))
	assert_eq(String(res["reason"]), Ops.MSG_CHEST_FULL)
	assert_true(GameState.structures.has(uid), "chest stays")
	assert_eq(GameState.get_storage(uid).count_of("stone"), 10, "contents stay")
	assert_eq(GameState.inventory.to_array(), before, "backpack untouched")
	assert_eq(_removed.size(), 0)


func test_empty_chest_with_full_backpack_drops_refund_instead_of_losing_it() -> void:
	var uid := GameState.add_structure("storage_chest", Vector3(2.5, 0, 2.5), 0)
	for i in GameState.inventory.size:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})
	assert_true(bool(Ops.dismantle(null, uid)["ok"]))
	var dropped := GameState.dropped.filter(func(d): return d["item"] == "storage_chest")
	assert_eq(dropped.size(), 1, "refund dropped as a persistent pickup")


func test_walls_holding_a_roof_must_wait_for_the_roof() -> void:
	var wall := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	var roof := GameState.add_structure("wood_roof", Vector3(3, 3, 1), 0)
	var res := Ops.dismantle(null, wall)
	assert_false(bool(res["ok"]))
	assert_eq(String(res["reason"]), Ops.MSG_ROOF_ON_WALL)
	assert_true(bool(Ops.dismantle(null, roof)["ok"]))
	assert_true(bool(Ops.dismantle(null, wall)["ok"]))
	assert_eq(GameState.count_item("wood_wall"), 1)
	assert_eq(GameState.count_item("wood_roof"), 1)


func test_second_wall_keeps_the_roof_up() -> void:
	var w1 := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	GameState.add_structure("wood_wall", Vector3(3, 0, 2), 0)
	GameState.add_structure("wood_roof", Vector3(3, 3, 1), 0)
	assert_true(bool(Ops.dismantle(null, w1)["ok"]), "the other wall still holds the roof")


func test_dismantling_a_growing_plot_returns_the_seed() -> void:
	var uid := GameState.add_structure("crop_plot", Vector3(3, 0, 3), 0)
	GameState.give_item("sweetroot_seeds", 1)
	assert_true(Farming.plant(uid, "sweetroot_seeds"))
	assert_eq(GameState.count_item("sweetroot_seeds"), 0)
	assert_true(bool(Ops.dismantle(null, uid)["ok"]))
	assert_eq(GameState.count_item("sweetroot_seeds"), 1, "seed back")
	assert_eq(GameState.count_item("crop_plot"), 1)
	assert_false(GameState.crops.has(uid))


func test_removing_the_respawn_bed_resets_the_wake_point() -> void:
	var uid := GameState.add_structure("bed", Vector3(2.5, 0, 3), 0)
	GameState.structures[uid]["data"]["respawn"] = true
	Game.set_respawn("surface", "bed")
	assert_true(bool(Ops.dismantle(null, uid)["ok"]))
	assert_eq(String(GameState.player["respawn_spawn"]), "haven_respawn")


func test_place_structure_consumes_exactly_one_and_spawns_the_node() -> void:
	var area := _make_area()
	GameState.give_item("workbench", 2)
	var uid := Ops.place_structure(area, "workbench", Vector3(2, 0, 4.5), 90)
	assert_ne(uid, "")
	assert_eq(GameState.count_item("workbench"), 1)
	var rec: Dictionary = GameState.structures[uid]
	assert_eq(String(rec["id"]), "workbench")
	assert_almost(float(rec["rot"]), 90.0)
	var node := Factory.find_node(area, uid)
	assert_not_null(node, "node spawned under Structures")
	assert_almost(node.rotation_degrees.y, 90.0, 0.01)
	assert_eq(_placed, [[uid, "workbench"]])
	assert_eq(Ops.place_structure(area, "wood", Vector3.ZERO, 0), "", "not a placeable")
	GameState.take_item("workbench", 1)
	assert_eq(Ops.place_structure(area, "workbench", Vector3(6, 0, 4.5), 0), "", "none left")


func test_floor_placed_under_furniture_lifts_it() -> void:
	var area := _make_area()
	await wait_physics(2)
	GameState.give_item("table", 1)
	GameState.give_item("wood_floor", 1)
	var t := Ops.place_structure(area, "table", Vector3(2.5, 0, 2.5), 0)
	Ops.place_structure(area, "wood_floor", Vector3(3, 0, 3), 0)
	assert_almost(float(GameState.structures[t]["pos"][1]), 0.12, 0.001, "table lifted onto the floor")
	assert_almost(Factory.find_node(area, t).position.y, 0.12, 0.001)
	var f := ""
	for u in GameState.structures:
		if GameState.structures[u]["id"] == "wood_floor":
			f = u
	assert_true(bool(Ops.dismantle(area, f)["ok"]))
	assert_almost(float(GameState.structures[t]["pos"][1]), 0.0, 0.001, "back on the ground")


func test_structures_survive_state_round_trip_and_respawn() -> void:
	var a := GameState.add_structure("storage_chest", Vector3(2.5, 0, 2.5), 90)
	GameState.get_storage(a).add("copper_ore", 5)
	var p := GameState.add_structure("crop_plot", Vector3(5, 0, 5), 0)
	GameState.give_item("sweetroot_seeds", 2)
	Farming.plant(p, "sweetroot_seeds")
	Farming.tend(p, 30.0)
	var b := GameState.add_structure("bed", Vector3(-3.5, 0, 3), 180)
	GameState.structures[b]["data"]["respawn"] = true
	var w := GameState.add_structure("wood_wall", Vector3(1, 0, 6), 90)
	# Through JSON, exactly like a save file.
	var text := JSON.stringify(GameState.to_dict())
	GameState.reset()
	assert_eq(GameState.structures.size(), 0)
	GameState.from_dict(JSON.parse_string(text))
	assert_eq(GameState.structures.size(), 4)
	assert_eq(String(GameState.structures[a]["id"]), "storage_chest")
	assert_almost(float(GameState.structures[a]["rot"]), 90.0)
	assert_eq(GameState.get_storage(a).count_of("copper_ore"), 5, "chest contents")
	assert_eq(Farming.crop_id(p), "sweetroot")
	assert_almost(float(GameState.crops[p]["tended_minutes"]), 30.0)
	assert_true(bool(GameState.structures[b]["data"]["respawn"]))
	# Spawning them again through the entry point
	var area := _make_area()
	BuildingSystem.attach(area)
	await wait_frames(2)
	for uid in [a, p, b, w]:
		assert_not_null(Factory.find_node(area, uid), "spawned " + uid)
	assert_almost(Factory.find_node(area, a).position.x, 2.5, 0.001)
	assert_almost(Factory.find_node(area, w).rotation_degrees.y, 90.0, 0.01)
	assert_not_null(area.get_node_or_null("BuildMode"), "build mode attached")
	assert_true(area.spawns.has("bed"), "last-slept bed restores the wake spawn")
	BuildingSystem.attach(area)
	assert_eq(area.get_node("Structures").get_child_count(), 4, "attach twice never duplicates")


func test_save_and_load_keep_structures() -> void:
	var uid := GameState.add_structure("lantern_post", Vector3(-4.5, 0, 2.5), 180)
	assert_true(SaveSystem.save_game())
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_true(GameState.structures.has(uid))
	assert_almost(float(GameState.structures[uid]["pos"][0]), -4.5)


func test_build_mode_places_validates_and_dismantles() -> void:
	var area := _make_area()
	await wait_physics(2)
	var bm: Node = load("res://src/building/build_mode.gd").new()
	area.add_child(bm)
	Game.mode = "playing"
	GameState.give_item("fence", 3)
	GameState.give_item("storage_chest", 1)
	var states: Array = []
	var cb := func(v: bool, r: String) -> void: states.append([v, r])
	Events.build_placement_state.connect(cb)
	bm.begin("fence")
	assert_true(bm.is_active())
	assert_eq(String(bm.selected_item), "fence")
	assert_true(bm.is_in_group("build_mode"))
	bm.debug_cursor = Vector3(5.2, 0, 5.3)
	bm._update(0.016)
	var u1: String = bm.try_place()
	assert_ne(u1, "", "first fence placed")
	assert_eq(GameState.count_item("fence"), 2)
	bm._update(0.016)
	assert_eq(String(bm.try_place()), "", "same cell is taken")
	assert_eq(GameState.count_item("fence"), 2, "no item consumed by a failed placement")
	bm.debug_cursor = Vector3(6.4, 0, 5.3)
	bm._update(0.016)
	assert_ne(String(bm.try_place()), "")
	assert_eq(GameState.count_item("fence"), 1)
	# Outside the Haven
	bm.debug_cursor = Vector3(30.5, 0, 0.5)
	bm._update(0.016)
	assert_eq(String(bm.try_place()), "")
	assert_false(bool(states.back()[0]))
	# Cycling the selection
	bm.cycle(1)
	assert_eq(String(bm.selected_item), "storage_chest")
	# Dismantle the first fence (cursor over it)
	bm.debug_cursor = Vector3(5.5, 0, 5.5)
	bm._update(0.016)
	assert_true(bm.try_dismantle())
	assert_false(GameState.structures.has(u1))
	assert_eq(GameState.count_item("fence"), 2, "refunded")
	Events.build_placement_state.disconnect(cb)
	bm.end()
	assert_false(bm.is_active())
	await wait_frames(2)


func test_build_mode_refuses_outside_play_and_ends_when_ui_opens() -> void:
	var area := _make_area()
	var bm: Node = load("res://src/building/build_mode.gd").new()
	area.add_child(bm)
	Game.mode = "title"
	bm.begin("")
	assert_false(bm.is_active(), "only while playing")
	Game.mode = "playing"
	bm.begin("")
	assert_true(bm.is_active(), "enters even with nothing to place (dismantle only)")
	assert_eq(String(bm.selected_item), "")
	Events.ui_stack_changed.emit(1)
	assert_false(bm.is_active(), "a panel opening closes build mode")
