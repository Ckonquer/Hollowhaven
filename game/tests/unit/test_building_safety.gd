extends "res://tests/test_case.gd"
## Review follow-ups: roof chains can't be left floating, neighbour-supported roofs line up, build mode
## respects a disabled player (sleeping), the live BuildMode enforces the enclosure / "standing in the
## way" rules through its physics context, and dismantling never double-refunds.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Farming := preload("res://src/farming/farming.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _area: Node3D
var _prev_mode := ""
var _prev_player: Node3D


func before_each() -> void:
	fresh_state()
	_prev_mode = Game.mode
	_prev_player = Game.player


func after_each() -> void:
	Game.mode = _prev_mode
	Game.player = _prev_player
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null


func _flat(_x: float, _z: float) -> float:
	return 0.0


## Tiny "surface" area with flat world collision at y = 0.
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


## A stand-in player: CharacterBody3D on the player layer with the input flags build mode looks at.
func _make_player(pos: Vector3) -> CharacterBody3D:
	var s := GDScript.new()
	s.source_code = "extends CharacterBody3D\nvar input_enabled: bool = true\nvar build_mode_active: bool = false\n" \
		+ "func set_input_enabled(on: bool) -> void:\n\tinput_enabled = on\n"
	s.reload()
	var p: CharacterBody3D = s.new()
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	p.add_child(cs)
	p.add_to_group("player")
	_area.add_child(p)
	p.global_position = pos
	Game.player = p
	return p


func _new_build_mode() -> Node:
	var bm: Node = load("res://src/building/build_mode.gd").new()
	_area.add_child(bm)
	Game.mode = "playing"
	return bm


# --- Roofs ---------------------------------------------------------------------------------------------

func test_roof_holding_up_a_neighbour_roof_must_wait_for_it() -> void:
	var wall := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	var a := GameState.add_structure("wood_roof", Vector3(3, 3, 1), 0)     # on the wall
	var b := GameState.add_structure("wood_roof", Vector3(5, 3, 1), 0)     # held only by roof a
	var res := Ops.dismantle(null, a)
	assert_false(bool(res["ok"]), "removing a would leave b floating")
	assert_eq(String(res["reason"]), Ops.MSG_ROOF_ON_ROOF)
	assert_true(GameState.structures.has(a))
	assert_eq(GameState.count_item("wood_roof"), 0, "no refund for a refused dismantle")
	assert_false(bool(Ops.dismantle(null, wall)["ok"]), "the wall still holds the roofs")
	assert_true(bool(Ops.dismantle(null, b)["ok"]), "outer tile first")
	assert_true(bool(Ops.dismantle(null, a)["ok"]), "then the inner one")
	assert_true(bool(Ops.dismantle(null, wall)["ok"]), "then the wall")
	assert_eq(GameState.count_item("wood_roof"), 2)
	assert_eq(GameState.count_item("wood_wall"), 1)


func test_an_already_floating_roof_never_locks_other_pieces() -> void:
	# e.g. from an older save: a roof with no support must not make every wall undismantlable.
	GameState.add_structure("wood_roof", Vector3(9, 3, 9), 0)
	var wall := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	assert_true(bool(Ops.can_dismantle(wall)["ok"]))


func test_neighbour_supported_roof_lines_up_with_its_neighbour() -> void:
	var structs := {
		"w": {"id": "wood_wall", "area": "surface", "pos": [3.0, 0.5, 0.0], "rot": 0.0, "data": {}},
		"r": {"id": "wood_roof", "area": "surface", "pos": [3.0, 3.5, 1.0], "rot": 0.0, "data": {}},
	}
	var ctx := {"structures": structs, "area_id": "surface", "height_fn": _flat}
	assert_almost(P.placement_y("wood_roof", Vector3(3, 0, 1), 0, ctx), 3.5, 0.001, "on the raised wall")
	assert_almost(P.placement_y("wood_roof", Vector3(5, 0, 1), 0, ctx), 3.5, 0.001, "neighbour tile at the same height, not ground + 3")


# --- Build mode vs. a disabled player -------------------------------------------------------------------

func test_build_mode_waits_while_the_player_is_asleep() -> void:
	_make_area()
	var p := _make_player(Vector3(0.5, 0, 9.5))
	var bm := _new_build_mode()
	GameState.give_item("fence", 2)
	p.set_input_enabled(false)
	assert_false(bm.can_start(), "no building behind the sleep fade")
	p.set_input_enabled(true)
	assert_true(bm.can_start())
	bm.begin("fence")
	assert_true(bm.is_active())
	assert_true(bool(p.build_mode_active), "player told to ignore gameplay input")
	p.set_input_enabled(false)
	bm._process(0.016)
	assert_false(bm.is_active(), "input switched off mid-way ends build mode")
	await wait_seconds(0.25)
	assert_false(bool(p.build_mode_active), "flag released after exit")


func test_sleeping_in_bed_blocks_build_mode_until_awake() -> void:
	_make_area()
	var p := _make_player(Vector3(0.5, 0, 9.5))
	var bm := _new_build_mode()
	var bed := Factory.spawn_structure(_area, GameState.add_structure("bed", Vector3(6.5, 0, 6), 0))
	GameState.total_minutes = 22.0 * 60.0
	bed.sleep(p)        # coroutine: runs on while we check
	assert_false(bool(p.input_enabled), "bed switched input off")
	assert_false(bm.can_start())
	var t := 0.0
	while not bool(p.input_enabled) and t < 5.0:
		await wait_seconds(0.1)
		t += 0.1
	assert_true(bool(p.input_enabled), "awake again")
	assert_true(bm.can_start())
	assert_almost(GameState.hour(), 7.0, 0.05)


# --- Live BuildMode rules (physics context) ----------------------------------------------------------------

func test_live_build_mode_never_shuts_krystal_in() -> void:
	# A 2 x 2 m room (x -6..-4, z 2..4) clear of the Haven's keep-clear circles, Krystal in the middle.
	_make_area()
	_make_player(Vector3(-5.0, 0, 3.0))
	await wait_physics(2)
	var bm := _new_build_mode()
	GameState.add_structure("wood_wall", Vector3(-5, 0, 2), 0)
	GameState.add_structure("wood_wall", Vector3(-5, 0, 4), 0)
	GameState.add_structure("wood_wall", Vector3(-6, 0, 3), 90)
	GameState.give_item("wood_wall", 1)
	GameState.give_item("wood_doorway", 1)
	bm.begin("wood_wall")
	bm.rot_deg = 90
	bm.debug_cursor = Vector3(-3.9, 0, 3.0)
	bm._update(0.016)
	assert_eq(String(bm.try_place()), "", "the fourth wall would trap her")
	assert_eq(String(bm.get_state()["reason"]), P.MSG_ENCLOSE)
	assert_eq(GameState.count_item("wood_wall"), 1, "nothing consumed")
	bm.begin("wood_doorway")
	bm.rot_deg = 90
	bm._update(0.016)
	assert_ne(String(bm.try_place()), "", "a doorway keeps the way out")
	assert_eq(GameState.count_item("wood_doorway"), 0)
	bm.end()
	await wait_frames(2)


func test_live_build_mode_refuses_solid_pieces_on_top_of_krystal() -> void:
	_make_area()
	_make_player(Vector3(-5.0, 0, 3.0))
	await wait_physics(2)
	var bm := _new_build_mode()
	GameState.give_item("storage_chest", 1)
	GameState.give_item("rug", 1)
	bm.begin("storage_chest")
	bm.rot_deg = 0
	bm.debug_cursor = Vector3(-4.8, 0, 3.2)
	bm._update(0.016)
	assert_eq(String(bm.try_place()), "", "chest would be placed inside her")
	assert_eq(String(bm.get_state()["reason"]), "You're standing in the way")
	assert_eq(GameState.count_item("storage_chest"), 1)
	bm.begin("rug")
	bm.debug_cursor = Vector3(-4.8, 0, 3.2)
	bm._update(0.016)
	assert_ne(String(bm.try_place()), "", "a rug under her feet is fine")
	bm.end()
	await wait_frames(2)


func test_dismantling_twice_quickly_refunds_once() -> void:
	_make_area()
	await wait_physics(2)
	var bm := _new_build_mode()
	GameState.give_item("fence", 1)
	bm.begin("fence")
	bm.debug_cursor = Vector3(5.5, 0, 5.5)
	bm._update(0.016)
	var uid: String = bm.try_place()
	assert_ne(uid, "")
	bm.begin("")
	bm._update(0.016)
	assert_true(bm.try_dismantle())
	bm._update(0.016)
	assert_false(bm.try_dismantle(), "already gone: nothing more to take apart")
	assert_eq(GameState.count_item("fence"), 1, "exactly one refund")
	bm.end()
	await wait_frames(2)


# --- Farming + dismantle -------------------------------------------------------------------------------------

func test_dismantling_a_ripe_plot_harvests_it() -> void:
	var uid := GameState.add_structure("crop_plot", Vector3(3, 0, 3), 0)
	GameState.give_item("sweetroot_seeds", 1)
	assert_true(Farming.plant(uid, "sweetroot_seeds"))
	GameState.total_minutes += 400.0
	assert_true(Farming.is_ripe(uid))
	assert_true(bool(Ops.dismantle(null, uid)["ok"]))
	assert_true(GameState.count_item("sweetroot") >= 2, "roots harvested, not lost")
	assert_true(GameState.count_item("sweetroot_seeds") >= 1, "seeds from the harvest")
	assert_eq(GameState.count_item("crop_plot"), 1, "plot refunded")
	assert_false(GameState.crops.has(uid))


func test_haven_keep_clear_circles_explain_themselves() -> void:
	var ctx := Ops.make_ctx(null)
	ctx["structures"] = {}
	ctx["height_fn"] = _flat
	assert_eq(String(P.validate("storage_chest", Vector3(0.5, 0, -5.5), 0, ctx)["reason"]), "Too close to the Ward Stone")
	assert_eq(String(P.validate("storage_chest", Vector3(4.5, 0, 3.5), 0, ctx)["reason"]), "Too close to the campfire")
	assert_eq(String(P.validate("storage_chest", Vector3(0.5, 0, 7.5), 0, ctx)["reason"]), P.MSG_CLEAR, "unnamed circle stays generic")
	var raw: Array = preload("res://data/world_layout.gd").BUILD_AREA["blocked"]
	assert_false((raw[0] as Dictionary).has("name"), "the shared layout data is never modified")
