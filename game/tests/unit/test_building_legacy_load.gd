extends "res://tests/test_case.gd"
## Chapter One homes load identically under the Chapter Two building rules: the committed save fixtures
## (including the REAL v0.9.0 Chapter-One-complete sample) keep every structure record byte-for-byte
## (uid, id, pos, rot, data: no storey or tint is added), every node spawns at the saved position and
## rotation on the ground storey, the occupancy keys are the legacy ones, and the non-destructive audit
## changes nothing.

const Fixtures := preload("res://tests/unit/ch2_save_fixtures.gd")
const BuildingSystem := preload("res://src/building/building_system.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Ops := preload("res://src/building/build_ops.gd")
const P := preload("res://src/building/placement.gd")
const AreaBase := preload("res://src/world/area_base.gd")

const FIXTURES := ["07_c1_complete_free_play", "09_dense_home_overflow", "16_real_handoff_c1_complete"]

var _area: Node3D


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null


func _load_fixture(name: String) -> Dictionary:
	var text := String(Fixtures.load_files(name)["main"])
	assert_true(text != "", name + " fixture exists")
	var d: Variant = JSON.parse_string(text)
	assert_true(d is Dictionary, name + " parses")
	var st: Dictionary = SaveSystem.migrate(d)["state"]
	GameState.from_dict(st)
	return (d as Dictionary)["state"].get("structures", {})


func test_legacy_homes_load_identically() -> void:
	var total := 0
	for name in FIXTURES:
		fresh_state()
		var raw: Dictionary = _load_fixture(name)
		var before: Dictionary = GameState.structures.duplicate(true)
		assert_eq(before.size(), raw.size(), name + ": every saved structure is loaded")
		_area = AreaBase.new()
		_area.area_id = "surface"
		add_child(_area)
		BuildingSystem.attach(_area)
		await wait_frames(2)
		for uid in raw:
			var r: Dictionary = raw[uid]
			var rec: Dictionary = GameState.structures.get(uid, {})
			assert_eq(String(rec.get("id", "")), String(r["id"]), "%s %s id" % [name, uid])
			for i in 3:
				assert_almost(float(rec["pos"][i]), float(r["pos"][i]), 0.00001, "%s %s pos[%d]" % [name, uid, i])
			assert_almost(float(rec["rot"]), float(r["rot"]), 0.00001, "%s %s rot" % [name, uid])
			var rd: Dictionary = r.get("data", {})
			var nd: Dictionary = rec.get("data", {})
			assert_eq(nd.keys().size(), rd.keys().size(), "%s %s: no data added (%s)" % [name, uid, str(nd)])
			assert_false(nd.has("level") or nd.has("tint"), "%s %s: no storey or tint added" % [name, uid])
			assert_eq(P.level_of(rec), 0, "%s %s is on the ground storey" % [name, uid])
			if String(rec.get("area", "surface")) == "surface" and not ItemDB.structure(String(rec["id"])).is_empty():
				var n := Factory.find_node(_area, uid)
				assert_not_null(n, "%s %s spawned" % [name, uid])
				if n != null:
					assert_true(n.position.distance_to(P.vec_from(rec["pos"])) < 0.0001, "%s %s at its saved position" % [name, uid])
					assert_almost(wrapf(n.rotation_degrees.y - float(rec["rot"]), -180.0, 180.0), 0.0, 0.01, "%s %s rotation" % [name, uid])
			total += 1
		for layer in P.build_occupancy(GameState.structures, "surface"):
			assert_false(String(layer).contains("@"), "%s: legacy occupancy keys only (%s)" % [name, layer])
		var issues := Ops.audit("surface")
		assert_eq(GameState.structures, before, name + ": attach + audit never change a record")
		if not issues.is_empty():
			print("%s audit (reported, kept): %s" % [name, str(issues)])
		_area.free()
		_area = null
	assert_true(total >= 10, "checked %d legacy structures" % total)


func test_legacy_home_round_trips_through_a_v2_save() -> void:
	var raw: Dictionary = _load_fixture("09_dense_home_overflow")
	var text := JSON.stringify(GameState.to_dict())
	GameState.reset()
	GameState.from_dict(JSON.parse_string(text))
	for uid in raw:
		var r: Dictionary = raw[uid]
		var rec: Dictionary = GameState.structures[uid]
		assert_eq(String(rec["id"]), String(r["id"]))
		assert_eq((rec.get("data", {}) as Dictionary).keys().size(), (r.get("data", {}) as Dictionary).keys().size(), uid + " data unchanged")
		assert_eq(P.level_of(rec), 0)
