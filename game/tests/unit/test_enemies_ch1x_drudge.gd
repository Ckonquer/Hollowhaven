extends "res://tests/test_case.gd"
## Hollow Drudge: pick_swing (telegraph 1.2 s, NARROW amber wedge, raised pick) -> swing -> recover 1.6 s and
## scrape (telegraph 1.4 s, a second distinct tell: pale-blue lane + pick dragged low) -> scrape -> recover
## 1.4 s; one hit each through the health path; the swing is narrow, the lane can be side-stepped; the two
## tells differ in pose, colour and mark; never two scrapes in a row; horror-intensity scaling.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Drudge := preload("res://src/enemies/hollow_drudge.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null


class Dummy extends CharacterBody3D:
	var health: Node
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("reduce_flashing", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3) -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	_nodes.append(d)
	return d


func _drudge(target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create("hollow_drudge", {"home": pos, "no_drops": true})
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _until(e: Node, s: String, max_t: float = 10.0) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		t += DT
	return t


func _visual_steps(e: Node, n: int) -> void:
	for i in n:
		e.visual._process(DT)


func test_pick_swing_sequence_and_one_hit() -> void:
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _drudge(d)
	e.next_attack = "pick_swing"
	assert_eq(e.state, "idle", "starts idle")
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "telegraph", 4.0)
	assert_eq(String(e.attack_kind), "pick_swing")
	var m: Node3D = e.mark()
	assert_eq(m.footprint()["kind"], "arc", "a wedge is drawn for the swing")
	assert_almost(float(m.footprint()["arc_deg"]), 40.0, 0.001, "narrow: data arc_deg 40")
	assert_eq(m.get("color"), TelegraphFx.WARN, "amber")
	var tele := _until(e, "swing", 3.0)
	assert_almost(tele, 1.2, DT * 2.0, "wind-up lasts data telegraph (1.2 s)")
	assert_almost(float(d.health.hp), 100.0, 0.001, "nothing during the wind-up")
	_until(e, "recover", 1.0)
	assert_almost(float(d.health.hp), 85.0, 0.001, "swing lands data damage (15)")
	assert_eq(d.damaged_count, 1, "once")
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, 1.6, DT * 2.0, "recover data 1.6 s")
	assert_eq(seen.slice(0, 5), ["chase", "telegraph", "swing", "recover", "chase"], "sequence (%s)" % str(seen))


func test_swing_is_narrow() -> void:
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _drudge(d)
	e.next_attack = "pick_swing"
	_until(e, "telegraph", 4.0)
	while e.state_time < 0.9:
		e.tick(DT)
	d.global_position = Vector3(1.5, 0, -1.6)            # ~43 degrees off its locked facing
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "a small side-step leaves the narrow swing")


func test_scrape_sequence_lane_and_one_hit() -> void:
	var d := _dummy(Vector3(0, 0, -3.3))
	var e := _drudge(d)
	e.next_attack = "scrape"
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "telegraph", 4.0)
	assert_eq(String(e.attack_kind), "scrape", "a scrape can start from further away")
	var m: Node3D = e.mark()
	var f: Dictionary = m.footprint()
	assert_eq(f["kind"], "lane", "a lane is drawn for the scrape")
	assert_almost(float(f["width"]), Drudge.SCRAPE_WIDTH, 0.001)
	assert_almost(((f["to"] as Vector3) - (f["from"] as Vector3)).length(), 4.0, 0.01, "data length 4 m")
	assert_eq(m.get("color"), TelegraphFx.COOL, "pale blue, not the swing's amber")
	var tele := _until(e, "scrape", 3.0)
	assert_almost(tele, 1.4, DT * 2.0, "wind-up lasts data telegraph (1.4 s)")
	_until(e, "recover", 1.0)
	assert_almost(float(d.health.hp), 86.0, 0.001, "scrape lands data damage (14) along the lane")
	assert_eq(d.damaged_count, 1, "once")
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, 1.4, DT * 2.0, "recover data 1.4 s")
	assert_eq(seen.slice(0, 5), ["chase", "telegraph", "scrape", "recover", "chase"], "sequence (%s)" % str(seen))


func test_scrape_can_be_sidestepped() -> void:
	var d := _dummy(Vector3(0, 0, -3.3))
	var e := _drudge(d)
	e.next_attack = "scrape"
	_until(e, "telegraph", 4.0)
	while e.state_time < 1.0:
		e.tick(DT)
	d.global_position = Vector3(1.1, 0, -3.3)            # out of the 1.2 m lane
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "stepping out of the lane avoids it")


func test_two_tells_are_distinct() -> void:
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _drudge(d)
	e.next_attack = "pick_swing"
	_until(e, "telegraph", 4.0)
	_visual_steps(e, 40)
	var swing_pick: float = e.visual.pick_head_height()
	var swing_col: Color = e.visual.tint_col_for_pick()
	Base.reset_attack_tokens()
	var e2 := _drudge(d, Vector3(6, 0, 0))
	d.global_position = Vector3(6, 0, -3.3)
	e2.next_attack = "scrape"
	_until(e2, "telegraph", 4.0)
	_visual_steps(e2, 40)
	var scrape_pick: float = e2.visual.pick_head_height()
	var scrape_col: Color = e2.visual.tint_col_for_pick()
	assert_true(swing_pick > 1.9, "the pick is raised high overhead for the swing (%.2f m)" % swing_pick)
	assert_true(scrape_pick < 0.9, "the pick is dragged low for the scrape (%.2f m)" % scrape_pick)
	assert_ne(swing_col, scrape_col, "different tell colours")
	assert_ne(e.mark().footprint()["kind"], e2.mark().footprint()["kind"], "different ground marks")


func test_never_two_scrapes_in_a_row() -> void:
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _drudge(d)
	for i in 30:
		e.set("_since_scrape", 0)                        # it just scraped
		assert_almost(float(e.attack_reach()), float(ItemDB.enemy("hollow_drudge")["attack_range"]), 0.001, "only swing reach right after a scrape")
		e._choose_attack()
		assert_eq(String(e.attack_kind), "pick_swing", "the next attack is a swing")


func test_underground_damage_scales() -> void:
	Settings.set_value("horror_intensity", 0)
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _drudge(d)
	e.next_attack = "pick_swing"
	_until(e, "recover", 5.0)
	assert_almost(float(d.health.hp), 100.0 - 15.0 * 0.6, 0.01, "Gentle: 60% damage")
