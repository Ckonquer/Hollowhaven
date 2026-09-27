extends "res://tests/test_case.gd"
## Farming: planting, growth stages over in-game time, tending, the ward bonus, harvest yields and the
## crop plot node's interaction flow.

const Farming := preload("res://src/farming/farming.gd")
const Factory := preload("res://src/building/structure_factory.gd")

var _planted: Array = []
var _harvested: Array = []
var _plot := ""


func before_each() -> void:
	fresh_state()
	_planted = []
	_harvested = []
	Events.crop_planted.connect(_on_planted)
	Events.crop_harvested.connect(_on_harvested)
	_plot = GameState.add_structure("crop_plot", Vector3(3, 0, 3), 0)


func after_each() -> void:
	Events.crop_planted.disconnect(_on_planted)
	Events.crop_harvested.disconnect(_on_harvested)


func _on_planted(uid: String, crop: String) -> void:
	_planted.append([uid, crop])


func _on_harvested(uid: String, crop: String, count: int) -> void:
	_harvested.append([uid, crop, count])


func _grow() -> float:
	return float(ItemDB.crop("sweetroot")["grow_minutes"])


func test_plant_consumes_one_seed_and_records_state() -> void:
	GameState.give_item("sweetroot_seeds", 3)
	var t0 := GameState.total_minutes
	assert_true(Farming.plant(_plot))
	assert_eq(GameState.count_item("sweetroot_seeds"), 2, "exactly one seed")
	var rec: Dictionary = GameState.crops[_plot]
	assert_eq(String(rec["crop"]), "sweetroot")
	assert_almost(float(rec["planted_at"]), t0)
	assert_almost(float(rec["tended_minutes"]), 0.0)
	assert_eq(GameState.get_counter("crops_planted"), 1)
	assert_eq(_planted, [[_plot, "sweetroot"]])
	assert_false(Farming.plant(_plot), "already planted")
	assert_eq(GameState.count_item("sweetroot_seeds"), 2)


func test_plant_needs_seeds_and_a_real_plot() -> void:
	assert_eq(Farming.choose_seed(), "")
	assert_false(Farming.plant(_plot), "no seeds")
	GameState.give_item("sweetroot_seeds", 1)
	assert_false(Farming.plant("not_a_plot"))
	assert_false(Farming.plant(_plot, "wood"), "wood isn't a seed")
	assert_eq(GameState.count_item("sweetroot_seeds"), 1, "nothing consumed")
	GameState.select_hotbar(4)
	assert_eq(Farming.choose_seed(), "sweetroot_seeds", "finds seeds anywhere in the bag")
	GameState.inventory.move(0, 4)
	assert_eq(Farming.choose_seed(), "sweetroot_seeds", "selected hotbar seed")


func test_growth_stages_follow_in_game_time() -> void:
	GameState.give_item("sweetroot_seeds", 1)
	Farming.plant(_plot)
	var g := _grow()
	var t0 := GameState.total_minutes
	assert_eq(Farming.stage(_plot), Farming.STAGE_SPROUT)
	GameState.total_minutes = t0 + g * 0.34
	assert_eq(Farming.stage(_plot), Farming.STAGE_LEAVES)
	GameState.total_minutes = t0 + g * 0.7
	assert_eq(Farming.stage(_plot), Farming.STAGE_BUSHY)
	GameState.total_minutes = t0 + g - 1.0
	assert_eq(Farming.stage(_plot), Farming.STAGE_BUSHY, "one minute before ripe")
	assert_almost(Farming.minutes_remaining(_plot), 1.0, 0.01)
	GameState.total_minutes = t0 + g
	assert_eq(Farming.stage(_plot), Farming.STAGE_RIPE)
	assert_true(Farming.is_ripe(_plot))
	GameState.total_minutes = t0 + g * 5.0
	assert_almost(Farming.progress(_plot), 1.0, 0.0001, "progress clamps")
	var empty := GameState.add_structure("crop_plot", Vector3(7, 0, 3), 0)
	assert_eq(Farming.stage(empty), -1)
	assert_almost(Farming.progress(empty), 0.0)


func test_tending_speeds_growth_only_while_growing() -> void:
	assert_false(Farming.tend(_plot, 60.0), "empty plot")
	GameState.give_item("sweetroot_seeds", 1)
	Farming.plant(_plot)
	var g := _grow()
	GameState.total_minutes += g * 0.25
	assert_eq(Farming.stage(_plot), Farming.STAGE_SPROUT)
	assert_true(Farming.tend(_plot, g * 0.15))
	assert_eq(Farming.stage(_plot), Farming.STAGE_LEAVES, "care moved it along")
	assert_false(Farming.tend(_plot, -5.0))
	assert_false(Farming.tend(_plot, 0.0))
	assert_true(Farming.tend(_plot, g))
	assert_true(Farming.is_ripe(_plot))
	var before := float(GameState.crops[_plot]["tended_minutes"])
	assert_false(Farming.tend(_plot, 10.0), "ripe crops need no tending")
	assert_almost(float(GameState.crops[_plot]["tended_minutes"]), before)
	assert_eq(Farming.plots_needing_care("surface"), [])
	assert_eq(Farming.ripe_plots("surface"), [_plot])


func test_restored_ward_grows_crops_faster() -> void:
	GameState.give_item("sweetroot_seeds", 1)
	Farming.plant(_plot)
	var g := _grow()
	GameState.total_minutes += g / 1.5
	assert_false(Farming.is_ripe(_plot), "normal speed: not yet")
	GameState.set_flag("ward_restored", true)
	assert_true(Farming.is_ripe(_plot), "x1.5 after the ward is restored")


func test_harvest_gives_yield_in_range_and_resets_plot() -> void:
	GameState.give_item("sweetroot_seeds", 1)
	Farming.plant(_plot)
	assert_eq(Farming.harvest(_plot), {}, "not ripe yet")
	assert_eq(GameState.count_item("sweetroot"), 0)
	GameState.total_minutes += _grow()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var got := Farming.harvest(_plot, null, rng)
	var y: Dictionary = ItemDB.crop("sweetroot")["yield"]
	for item in y:
		var n := int(got.get(item, 0))
		assert_true(n >= int(y[item][0]) and n <= int(y[item][1]), "%s yield %d in range" % [item, n])
		assert_eq(GameState.count_item(String(item)), n, "given to the player")
	assert_eq(Farming.stage(_plot), -1, "plot empty again")
	assert_eq(String(GameState.crops[_plot]["crop"]), "")
	assert_eq(GameState.get_counter("crops_harvested"), 1)
	assert_eq(_harvested.size(), 1)
	assert_eq(int(_harvested[0][2]), int(got["sweetroot"]))
	assert_eq(Farming.harvest(_plot), {}, "can't harvest twice")


func test_yield_rolls_cover_the_whole_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var seen := {}
	for i in 200:
		seen[int(Farming.roll_yield("sweetroot", rng)["sweetroot"])] = true
	assert_eq(seen.keys().size(), 2, "both 2 and 3 roots happen")
	assert_true(seen.has(2) and seen.has(3))


func test_format_minutes() -> void:
	assert_eq(Farming.format_minutes(130.0), "2h 10m")
	assert_eq(Farming.format_minutes(45.2), "46m")
	assert_eq(Farming.format_minutes(120.0), "2h")
	assert_eq(Farming.format_minutes(0.0), "a moment")


func test_crop_plot_node_plants_shows_progress_and_harvests() -> void:
	var node := Factory.spawn_structure(self_area(), _plot)
	assert_not_null(node)
	assert_true(node.is_in_group("interactable"))
	var info: Dictionary = node.get_interaction(null)
	assert_false(bool(info["enabled"]), "no seeds yet")
	GameState.give_item("sweetroot_seeds", 2)
	info = node.get_interaction(null)
	assert_true(bool(info["enabled"]))
	assert_true(String(info["text"]).begins_with("Plant"), String(info["text"]))
	node.interact(null)
	assert_eq(GameState.count_item("sweetroot_seeds"), 1)
	assert_eq(node.current_stage(), Farming.STAGE_SPROUT)
	assert_true(node.plants.visible, "sprouts visible")
	assert_true(String(node.get_interaction(null)["text"]).contains("ripe in"), String(node.get_interaction(null)["text"]))
	GameState.total_minutes += _grow()
	node.refresh()
	assert_eq(node.current_stage(), Farming.STAGE_RIPE)
	assert_true(node.sparkles.emitting, "ripe crops sparkle")
	assert_true(String(node.get_interaction(null)["text"]).begins_with("Harvest"))
	node.interact(null)
	assert_true(GameState.count_item("sweetroot") >= 2, "harvested")
	assert_eq(node.current_stage(), -1)
	assert_false(node.plants.visible)
	assert_false(node.sparkles.emitting)


var _area_node: Node3D


func self_area() -> Node3D:
	if _area_node == null or not is_instance_valid(_area_node):
		_area_node = Node3D.new()
		add_child(_area_node)
	return _area_node


func test_companion_hooks_are_callable_through_the_script() -> void:
	# The companion module loads farming.gd at runtime and calls these by name.
	var fs: Script = load("res://src/farming/farming.gd")
	for m in ["tend", "plots_needing_care", "plot_position"]:
		assert_true(fs.has_method(m), "farming.gd exposes " + m)
	GameState.give_item("sweetroot_seeds", 1)
	Farming.plant(_plot)
	assert_eq(fs.call("plots_needing_care", "surface"), [_plot])
	assert_eq(fs.call("plot_position", _plot), Vector3(3, 0, 3))
	assert_true(bool(fs.call("tend", _plot, 12.0)))
	assert_almost(float(GameState.crops[_plot]["tended_minutes"]), 12.0)

