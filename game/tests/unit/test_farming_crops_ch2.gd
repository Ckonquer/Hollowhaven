extends "res://tests/test_case.gd"
## Chapter Two farming (MP 3 / 16, spec 4.4): sunflax / roseberry / pumpkin grow with the legacy framework and
## stage rules, every harvest returns seeds, the restored-Haven blessing (x1.5) never compounds across loads,
## optional-goal flags on real harvests, the Sturdy Planter works like a plot, and each crop has its own
## stage meshes within the geometry budget (numeric checks; the look itself still needs a visual pass).

const Farming := preload("res://src/farming/farming.gd")
const CropModels := preload("res://src/farming/crop_models.gd")
const CropPlot := preload("res://src/farming/crop_plot.gd")
const AreaBase := preload("res://src/world/area_base.gd")

const NEW_CROPS := ["sunflax", "roseberry", "pumpkin"]

var _plot := ""
var _area: Node3D


func before_each() -> void:
	fresh_state()
	_plot = GameState.add_structure("crop_plot", Vector3(3, 0, 3), 0)
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)


func after_each() -> void:
	if is_instance_valid(_area):
		_area.free()


func _seed(crop: String) -> String:
	return String(ItemDB.crop(crop)["seed"])


func _grow(crop: String) -> float:
	return float(ItemDB.crop(crop)["grow_minutes"])


func _roundtrip() -> void:
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))


func test_new_crops_plant_grow_in_stages_and_ripen() -> void:
	for crop in NEW_CROPS:
		fresh_state()
		var plot := GameState.add_structure("crop_plot", Vector3(3, 0, 3), 0)
		GameState.give_item(_seed(crop), 1)
		assert_eq(Farming.crop_for_seed(_seed(crop)), crop)
		assert_true(Farming.plant(plot), crop)
		var g := _grow(crop)
		assert_true(g >= 300.0 and g <= 600.0, "%s grows in 5-10 active minutes (%.0f)" % [crop, g])
		var t0 := GameState.total_minutes
		assert_eq(Farming.stage(plot), Farming.STAGE_SPROUT, crop)
		GameState.total_minutes = t0 + g * 0.34
		assert_eq(Farming.stage(plot), Farming.STAGE_LEAVES, crop)
		GameState.total_minutes = t0 + g * 0.67
		assert_eq(Farming.stage(plot), Farming.STAGE_BUSHY, crop)
		GameState.total_minutes = t0 + g - 1.0
		assert_false(Farming.is_ripe(plot), crop)
		GameState.total_minutes = t0 + g
		assert_true(Farming.is_ripe(plot), crop)


func test_every_harvest_returns_seeds_and_the_produce() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for crop in NEW_CROPS:
		for i in 30:
			var y := Farming.roll_yield(crop, rng)
			assert_true(int(y.get(_seed(crop), 0)) >= 1, "%s always returns a seed" % crop)
			assert_true(int(y.get(Farming.produce_item(crop), 0)) >= 1, "%s gives produce" % crop)
	assert_eq(Farming.produce_item("roseberry"), "roseberries")
	assert_eq(Farming.produce_item("sweetroot"), "sweetroot")
	assert_eq(Farming.produce_item("pumpkin"), "pumpkin")


func test_harvest_sets_optional_goal_flags() -> void:
	var harvested: Array = []
	var cb := func(uid: String, crop: String, count: int) -> void: harvested.append([crop, count])
	Events.crop_harvested.connect(cb)
	for crop in ["sweetroot", "pumpkin", "roseberry"]:
		GameState.give_item(_seed(crop), 1)
		assert_true(Farming.plant(_plot, _seed(crop)))
		GameState.total_minutes += _grow(crop)
		var got := Farming.harvest(_plot)
		assert_false(got.is_empty(), crop)
		if crop == "sweetroot":
			assert_false(bool(GameState.get_flag("c1x_grew_new_crop")), "sweetroot is not a new crop")
			assert_false(bool(GameState.get_flag("ch2_pumpkin_harvested")))
		elif crop == "pumpkin":
			assert_true(bool(GameState.get_flag("ch2_pumpkin_harvested")), "A Pumpkin With a Face")
			assert_false(bool(GameState.get_flag("c1x_grew_new_crop")), "pumpkin is not sunflax/roseberry")
		else:
			assert_true(bool(GameState.get_flag("c1x_grew_new_crop")), "A Gardener's Afternoon")
	Events.crop_harvested.disconnect(cb)
	assert_eq(harvested.size(), 3)
	assert_true(int(harvested[2][1]) >= 3, "headline count = roseberries (%d)" % int(harvested[2][1]))
	assert_eq(GameState.get_counter("crops_harvested"), 3)


func test_unripe_harvest_sets_no_flag() -> void:
	GameState.give_item("sunflax_seeds", 1)
	Farming.plant(_plot)
	GameState.total_minutes += 10.0
	assert_eq(Farming.harvest(_plot), {})
	assert_false(bool(GameState.get_flag("c1x_grew_new_crop")))


func test_blessing_is_x1_5_and_never_compounds_on_reload() -> void:
	GameState.give_item("pumpkin_seeds", 1)
	assert_true(Farming.plant(_plot))
	var g := _grow("pumpkin")
	GameState.total_minutes += g * 0.3
	Farming.tend(_plot, 20.0)
	var p_normal := Farming.progress(_plot)
	GameState.set_flag("ward_restored", true)
	var p_blessed := Farming.progress(_plot)
	assert_almost(p_blessed, p_normal * Farming.WARD_GROWTH_MULT, 0.0001, "x1.5 while blessed")
	var rec_before: Dictionary = GameState.crops[_plot].duplicate()
	for i in 4:
		_roundtrip()
	assert_almost(Farming.progress(_plot), p_blessed, 0.0001, "loading four times changes nothing")
	assert_almost(float(GameState.crops[_plot]["planted_at"]), float(rec_before["planted_at"]), 0.0001)
	assert_almost(float(GameState.crops[_plot]["tended_minutes"]), float(rec_before["tended_minutes"]), 0.0001, "care is not multiplied")
	assert_almost(Farming.minutes_remaining(_plot), (1.0 - p_blessed) * g / 1.5, 0.01)


func test_sturdy_planter_works_like_a_plot() -> void:
	var planter := GameState.add_structure("sturdy_planter", Vector3(6, 0, 3), 0)
	assert_true(Farming.is_plot(planter), "farm record created")
	GameState.give_item("roseberry_seeds", 2)
	assert_true(Farming.plant(planter))
	assert_eq(Farming.crop_id(planter), "roseberry")
	assert_eq(Farming.plots_needing_care("surface"), [planter])
	assert_true(Farming.tend(planter, 30.0))
	GameState.total_minutes += _grow("roseberry")
	assert_eq(Farming.ripe_plots("surface"), [planter])
	_roundtrip()
	assert_true(Farming.is_ripe(planter), "planted state saved")
	assert_false(Farming.harvest(planter).is_empty())
	assert_true(GameState.count_item("roseberries") >= 3)


# --- Visuals (numeric) -----------------------------------------------------------------------------------------

func _tris(mesh: Mesh) -> int:
	var t := 0
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return t


func test_each_crop_has_distinct_stage_meshes_within_budget() -> void:
	var plot_tris := _tris(U_baked_plot())
	var report: PackedStringArray = []
	var seen := {}
	for crop in ["sweetroot"] + NEW_CROPS:
		var prev_h := -1.0
		for st in 4:
			var m := CropModels.stage_mesh(st, crop)
			assert_not_null(m)
			assert_true(m.get_surface_count() > 0, "%s stage %d has geometry" % [crop, st])
			assert_false(seen.has(m.get_rid()), "%s stage %d is its own mesh" % [crop, st])
			seen[m.get_rid()] = true
			var aabb := m.get_aabb()
			var n := CropModels.plant_layout("crop_plot", crop).size()
			var tris := plot_tris + _tris(m) * n
			report.append("%s/%d=%d tris h%.2f w%.2f" % [crop, st, tris, aabb.end.y, maxf(aabb.size.x, aabb.size.z)])
			if crop != "sweetroot":   # legacy sweetroot shapes are unchanged (reported only)
				assert_true(tris < 9000, "%s stage %d plot has %d triangles" % [crop, st, tris])
			if crop != "sweetroot":
				assert_true(aabb.end.y >= prev_h - 0.001, "%s grows taller or stays (stage %d)" % [crop, st])
			prev_h = aabb.end.y
	print("Crop stage budgets: ", ", ".join(report))
	# Recognisable silhouettes: sunflax is tall and slim, the ripe pumpkin is wide, roseberry is a round bush.
	var sun := CropModels.stage_mesh(3, "sunflax").get_aabb()
	var pum := CropModels.stage_mesh(3, "pumpkin").get_aabb()
	var rose := CropModels.stage_mesh(3, "roseberry").get_aabb()
	assert_true(sun.size.y > maxf(sun.size.x, sun.size.z), "sunflax taller than wide")
	assert_true(maxf(pum.size.x, pum.size.z) > 0.9, "the pumpkin vine spreads out")
	assert_true(rose.size.y > 0.35 and rose.size.y < 0.8, "roseberry bush height %.2f" % rose.size.y)


func U_baked_plot() -> Mesh:
	var root := Node3D.new()
	CropModels.plot(root)
	var mi := root.get_child(0) as MeshInstance3D
	var m := mi.mesh
	root.free()
	return m


func test_layouts_fit_their_structure() -> void:
	for sid in ["crop_plot", "sturdy_planter"]:
		var size: Vector2i = ItemDB.structure(sid)["size"]
		for crop in ["sweetroot"] + NEW_CROPS:
			var pos := CropModels.plant_layout(sid, crop)
			var sc := CropModels.plant_scale(sid, crop)
			var ripe := CropModels.stage_mesh(3, crop).get_aabb()
			var half := maxf(absf(ripe.position.x), absf(ripe.end.x))
			var halfz := maxf(absf(ripe.position.z), absf(ripe.end.z))
			for p in pos:
				var v: Vector3 = p
				assert_almost(v.y, CropModels.soil_top(sid), 0.0001, sid + " soil height")
				# plants stay over the structure (a little leafy overhang is fine)
				assert_true(absf(v.x) + half * sc * 1.12 <= float(size.x) * 0.5 + 0.35, "%s %s x within footprint" % [sid, crop])
				assert_true(absf(v.z) + halfz * sc * 1.12 <= float(size.y) * 0.5 + 0.35, "%s %s z within footprint" % [sid, crop])
	assert_eq(CropModels.plant_layout("crop_plot", "sweetroot"), CropModels.plant_positions(), "legacy layout unchanged")
	assert_eq(CropModels.plant_layout("crop_plot", "roseberry").size(), 4)
	assert_eq(CropModels.plant_layout("crop_plot", "pumpkin").size(), 1)
	assert_eq(CropModels.plant_layout("sturdy_planter", "sunflax").size(), 6)


func test_planter_model_soil_matches_the_plants() -> void:
	var root := Node3D.new()
	CropModels.planter(root)
	var mi := root.get_child(0) as MeshInstance3D
	var aabb := mi.mesh.get_aabb()
	assert_true(aabb.end.y >= CropModels.PLANTER_SOIL_TOP and aabb.end.y <= float(ItemDB.structure("sturdy_planter")["height"]) + 0.02, "rim top %.2f" % aabb.end.y)
	assert_true(aabb.size.x <= 2.05 and aabb.size.z <= 1.05, "fits 2 x 1 m: %s" % aabb.size)
	assert_true(_tris(mi.mesh) < 6000)
	root.free()


# --- Plot node -------------------------------------------------------------------------------------------------

func _spawn(uid: String, sid: String) -> Node3D:
	var n: Node3D = CropPlot.new()
	n.setup({"uid": uid, "id": sid})
	n.name = "S_" + uid
	_area.add_child(n)
	return n


func test_plot_node_switches_layout_and_mesh_per_crop() -> void:
	var n := _spawn(_plot, "crop_plot")
	assert_eq(n.plant_count(), 9, "legacy 3x3 while empty")
	assert_false(n.plants.visible)
	GameState.give_item("pumpkin_seeds", 1)
	n.interact(null)
	assert_eq(Farming.crop_id(_plot), "pumpkin")
	assert_eq(n.plant_count(), 1, "one pumpkin vine")
	assert_true(n.plants.multimesh.mesh == CropModels.stage_mesh(0, "pumpkin"))
	GameState.total_minutes += _grow("pumpkin")
	n.refresh()
	assert_true(n.plants.multimesh.mesh == CropModels.stage_mesh(3, "pumpkin"))
	assert_true(n.sparkles.emitting)
	n.interact(null)
	assert_true(GameState.count_item("pumpkin") >= 1)
	assert_false(n.plants.visible)
	GameState.take_item("pumpkin_seeds", GameState.count_item("pumpkin_seeds"))   # else choose_seed() replants them
	GameState.give_item("sunflax_seeds", 1)
	n.interact(null)
	assert_eq(n.plant_count(), 9)
	assert_true(n.plants.multimesh.mesh == CropModels.stage_mesh(0, "sunflax"))
	n.free()


func test_planter_node_plants_sit_on_its_soil() -> void:
	var planter := GameState.add_structure("sturdy_planter", Vector3(6, 0, 3), 0)
	var n := _spawn(planter, "sturdy_planter")
	assert_true(n.is_in_group("interactable"))
	GameState.give_item("sunflax_seeds", 1)
	assert_true(String(n.get_interaction(null)["text"]).begins_with("Plant"))
	n.interact(null)
	assert_eq(n.plant_count(), 6)
	for i in n.plant_count():
		var t: Transform3D = n.plant_transform(i)
		assert_almost(t.origin.y, CropModels.PLANTER_SOIL_TOP, 0.0001)
		assert_true(absf(t.origin.x) <= 0.7 and absf(t.origin.z) <= 0.3, "plant %d inside the box" % i)
	n.free()


func test_preview_params_force_crop_and_stage() -> void:
	var n: Node3D = CropPlot.new()
	n.setup({"uid": "", "id": "crop_plot", "stage": 3, "crop": "roseberry"})
	_area.add_child(n)
	assert_eq(n.current_crop(), "roseberry")
	assert_eq(n.plant_count(), 4)
	assert_true(n.plants.visible)
	n.free()


## "A Gardener's Afternoon": the world sets c1x_found_new_crops, a real sunflax / roseberry harvest at home sets
## c1x_grew_new_crop, and the real optional log completes the goal.
func test_gardeners_afternoon_goal_completes_on_a_new_crop_harvest() -> void:
	GameState.set_flag("c1x_found_new_crops", true)
	GameState.optional_goals.evaluate()
	assert_false(GameState.optional_goals.is_done("opt_gardeners_afternoon"))
	GameState.give_item("sunflax_seeds", 1)
	assert_true(Farming.plant(_plot))
	GameState.total_minutes += _grow("sunflax")
	assert_false(Farming.harvest(_plot).is_empty())
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_gardeners_afternoon"))

