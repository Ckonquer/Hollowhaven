extends "res://tests/test_case.gd"
## Pumpkin Mimic (module C5): dormant = decor (not an enemy, an "Inspect twitching pumpkin" interactable whose stem
## twitches in pairs), waking = exactly two more twitches over data wake_telegraph before it joins the fight,
## lingering beside it wakes it, never dormant in a safe zone or beside a crop plot (it retires instead), the bite
## (timings, wedge = hit area, one hit), the roll unlocked only after a bite (lane = hit width, one hit, stuck
## afterwards - longer after a wall, never through it), side-stepping the lane, and a spawner clear flag set once.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Mimic := preload("res://src/enemies/pumpkin_mimic.gd")
const SpawnerScript := preload("res://src/enemies/enemy_spawner.gd")

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


class SafeArea extends Node3D:
	var safe := true

	func is_safe_zone(_p: Vector3) -> bool:
		return safe


class Plot extends Node3D:
	var structure_id := "crop_plot"


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("timing_assist", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3, group: String = "player") -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group(group)
	_nodes.append(d)
	return d


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	add_child(w)
	w.global_position = pos
	_nodes.append(w)
	return w


func _mimic(target: Node3D, pos: Vector3 = Vector3.ZERO, params: Dictionary = {}) -> Node:
	var p := {"home": pos, "no_drops": true}
	for k in params:
		p[k] = params[k]
	var e: Node = Factory.create("pumpkin_mimic", p)
	(e as Node3D).position = pos                      # placed before _ready, like EnemyFactory.spawn (this node is at the origin)
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _step(e: Node, move: bool) -> void:
	e.tick(DT)
	if move:
		e._apply_movement(DT)


func _until(e: Node, s: String, max_t: float = 10.0, move: bool = false) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		_step(e, move)
		t += DT
	return t


func test_dormant_is_decor_that_twitches_in_pairs() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _mimic(d, Vector3.ZERO, {"dormant": true})
	assert_eq(e.state, "dormant", "starts dormant")
	assert_false(e.is_in_group("enemy"), "a dormant mimic is not an enemy (companions / swings / save gates ignore it)")
	assert_true(e.is_in_group("interactable"), "it is an interactable")
	assert_false(bool(e.is_threatening()), "not threatening")
	var area: Area3D = e.inspect_area
	assert_not_null(area, "interaction collider")
	assert_eq(area.collision_layer, 16, "on the interact layer")
	var it: Dictionary = e.get_interaction(d)
	assert_eq(String(it.get("text", "")), "Inspect twitching pumpkin", "the announced interaction text (data inspect_text)")
	assert_false(bool(e.visual.eyes_open()), "eyes shut: it reads as a pumpkin")
	var twitch_times: Array = []
	var last := int(e.stem_twitches)
	var t := 0.0
	while t < 14.0:
		e.tick(DT)
		t += DT
		if int(e.stem_twitches) != last:
			last = int(e.stem_twitches)
			twitch_times.append(t)
	assert_eq(e.state, "dormant", "Krystal far away: it stays dormant")
	assert_true(twitch_times.size() >= 4, "the stem twitches now and then (%d)" % twitch_times.size())
	assert_eq(twitch_times.size() % 2, 0, "always in pairs (two twitches)")
	for i in range(0, twitch_times.size() - 1, 2):
		assert_almost(float(twitch_times[i + 1]) - float(twitch_times[i]), Mimic.TWITCH_GAP, DT * 2.0, "a quick double twitch")


func test_inspect_wakes_it_after_exactly_two_twitches() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _mimic(d, Vector3.ZERO, {"dormant": true})
	var before := int(e.stem_twitches)
	e.interact(d)
	assert_eq(e.state, "waking", "inspecting it starts the wake")
	assert_false(e.is_in_group("interactable"), "no more prompt")
	assert_true(e.get_interaction(d).is_empty(), "prompt gone")
	assert_false(e.is_in_group("enemy"), "not hunting yet")
	var wake := _until(e, "chase", 4.0)
	assert_almost(wake, float(ItemDB.enemy("pumpkin_mimic")["wake_telegraph"]), DT * 2.0, "wake tell lasts data wake_telegraph (1.4 s)")
	assert_eq(int(e.stem_twitches) - before, 2, "the stem twitched twice before it woke")
	assert_true(e.is_in_group("enemy"), "awake: an enemy now")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage during the wake")
	assert_false(bool(e.wake()), "waking twice does nothing")


func test_lingering_beside_it_wakes_it() -> void:
	var d := _dummy(Vector3(0, 0, -1.6))
	var e := _mimic(d, Vector3.ZERO, {"dormant": true})
	var t := _until(e, "waking", 3.0)
	assert_eq(e.state, "waking", "standing right beside it wakes it")
	assert_true(t >= Mimic.WAKE_LINGER - 0.01, "only after lingering (%.2f s)" % t)


func test_never_dormant_in_a_safe_zone_or_beside_a_crop() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var home := SafeArea.new()
	add_child(home)
	_nodes.append(home)
	Game.area = home
	assert_false(Mimic.spot_allowed(Vector3(5, 0, 5)), "the safe home never holds a mimic")
	var e := _mimic(d, Vector3(5, 0, 5), {"dormant": true})
	assert_true(bool(e.retired), "a dormant mimic placed in a safe zone retires at once")
	assert_false(e.is_in_group("enemy"), "and is nothing")
	await wait_frames(1)
	assert_false(is_instance_valid(e), "freed")
	home.safe = false
	var plot := Plot.new()
	add_child(plot)
	plot.global_position = Vector3(20, 0, 0)
	plot.add_to_group("structure")
	_nodes.append(plot)
	assert_false(Mimic.spot_allowed(Vector3(21, 0, 0.5)), "never beside a planted crop plot")
	assert_true(Mimic.spot_allowed(Vector3(30, 0, 0)), "fine away from crops and the home")
	var e2 := _mimic(d, Vector3(21, 0, 0.5), {"dormant": true})
	assert_true(bool(e2.retired), "a mimic never replaces / sits on a crop plot")
	var e3 := _mimic(d, Vector3(30, 0, 0), {"dormant": true})
	assert_false(bool(e3.retired), "a legal spot keeps it")
	assert_eq(e3.state, "dormant")
	# Even awake next to her in the home, nothing hunts there (base hunt rule).
	home.safe = true
	d.global_position = Vector3(30, 0, -1.2)
	for i in 90:
		e3.tick(DT)
	assert_eq(e3.state, "dormant", "a dormant mimic never wakes while Krystal is in the safe home")


func test_bite_sequence_one_hit() -> void:
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _mimic(d)
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph", "winds up a bite")
	assert_eq(String(e.attack_kind), "bite", "first attack is always a bite (the roll comes later)")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "arc", "a wedge marks the bite")
	assert_almost(float(m.footprint()["radius"]), float(e.bite_reach()), 0.001, "marked reach = hit reach")
	assert_almost(float(m.footprint()["arc_deg"]), Mimic.BITE_ARC, 0.001, "marked arc = hit arc")
	var tele := _until(e, "bite", 3.0)
	assert_almost(tele, 1.0, DT * 2.0, "the bite wind-up is readable (data 0.9 -> committed floor 1.0 s)")
	_until(e, "recover", 2.0)
	assert_almost(float(d.health.hp), 87.0, 0.001, "one bite of data damage (13)")
	assert_eq(d.damaged_count, 1)
	assert_eq(int(e.bites_done), 1)
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, 1.4, DT * 2.0, "recovery lasts data recover (1.4 s)")
	assert_eq(seen.slice(0, 4), ["chase", "telegraph", "bite", "recover"], "sequence %s" % str(seen))


func test_roll_comes_later_marked_and_leaves_it_stuck() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _mimic(d)
	await wait_physics(2)
	assert_false(bool(e.roll_unlocked()), "no roll before the first bite")
	for i in 150:
		_step(e, false)
	assert_ne(e.state, "telegraph", "at 5 m a fresh mimic does not roll yet")
	e.bites_done = 1
	assert_true(bool(e.roll_unlocked()), "a bite unlocks the roll")
	e.global_position = Vector3.ZERO
	e.rotation = Vector3.ZERO
	_until(e, "telegraph", 4.0, true)
	assert_eq(String(e.attack_kind), "roll", "now it rolls from range")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "lane", "a lane marks the roll")
	assert_almost(float(m.footprint()["width"]), Mimic.LANE_WIDTH, 0.001, "marked width = hit width")
	var tele := _until(e, "roll", 3.0, true)
	assert_almost(tele, 1.4, DT * 2.0, "roll wind-up = data 1.4 s")
	assert_true(bool(m.footprint()["locked"]), "the lane locked before it rolled")
	_until(e, "stuck", 3.0, true)
	assert_eq(e.state, "stuck", "every roll ends stuck")
	assert_eq(d.damaged_count, 1, "one hit")
	assert_almost(float(d.health.hp), 85.0, 0.001, "roll data damage (15)")
	assert_true(bool(e.is_threatening()), "stuck still counts as a fight")
	e.health.apply_damage(5.0, d, Vector3.FORWARD)
	assert_eq(e.state, "stuck", "hits never cut the stuck window short")
	var stuck := _until(e, "chase", 4.0, true)
	assert_almost(stuck + DT, 2.0, DT * 3.0, "stuck for data recover (2.0 s)")


func test_sidestepping_the_roll_lane() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _mimic(d)
	e.bites_done = 1
	e.next_attack = "roll"
	await wait_physics(2)
	_until(e, "telegraph", 4.0, true)
	while e.state_time < 1.0:
		_step(e, true)
	d.global_position = Vector3(1.4, 0, -5.0)          # out of the locked 1.2 m lane
	_until(e, "stuck", 4.0, true)
	assert_eq(e.state, "stuck")
	assert_almost(float(d.health.hp), 100.0, 0.001, "side-stepping the marked lane avoids the roll")


func test_no_roll_through_a_wall() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var d := _dummy(Vector3(0, 0, -6.0))
	_box(Vector3(0, 1, -3.0), Vector3(6, 3, 0.4))
	var e := _mimic(d)
	e.bites_done = 1
	e.next_attack = "roll"
	await wait_physics(3)
	for i in 180:
		_step(e, true)
	assert_false(e.state in ["telegraph", "roll"], "no roll wind-up without a clear line (%s)" % e.state)
	assert_almost(float(d.health.hp), 100.0, 0.001)


func test_roll_into_a_wall_is_stuck_longer_and_never_passes() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _mimic(d)
	e.bites_done = 1
	e.next_attack = "roll"
	await wait_physics(2)
	_until(e, "telegraph", 4.0, true)
	assert_eq(e.state, "telegraph")
	var wall := _box(Vector3(0, 1, -2.4), Vector3(6, 3, 0.4))      # she ducks behind a hay bale mid wind-up
	await wait_physics(3)
	_until(e, "roll", 3.0, true)
	assert_true(float(e.lane_length()) < 2.4, "the lane is clipped at the wall (%.2f m)" % e.lane_length())
	_until(e, "stuck", 3.0, true)
	assert_eq(e.state, "stuck", "it bumps the wall and sticks")
	assert_true((e as Node3D).global_position.z > wall.global_position.z, "never passes through the wall")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no hit through the wall")
	var stuck := _until(e, "chase", 5.0, true)
	assert_almost(stuck + DT, 2.0 + Mimic.STUCK_WALL_EXTRA, DT * 3.0, "a bump sticks it longer (%.2f s)" % stuck)


func test_spawner_clears_once_with_its_flag() -> void:
	var d := _dummy(Vector3(3, 0, 3))
	var sp: Node3D = SpawnerScript.new()
	sp.setup({"enemy": "pumpkin_mimic", "count": 2, "radius": 2.0, "respawn_minutes": -1.0, "spawner_id": "hr_sp_test_mimics",
		"quest_flag_on_clear": "test_mimics_cleared", "min_player_distance": 0.0})
	add_child(sp)
	_nodes.append(sp)
	sp.player_override = d
	sp.ignore_safe_zones = true
	var saved_mode: String = Game.mode
	Game.mode = "playing"
	sp.update_spawner()
	Game.mode = saved_mode
	assert_eq(sp.alive.size(), 2, "two mimics spawned")
	var flags: Array = []
	var cb := func(f: String, v: Variant) -> void:
		if f == "test_mimics_cleared" and v == true:
			flags.append(f)
	Events.flag_set.connect(cb)
	for m in sp.alive.duplicate():
		assert_true((m as Node).is_in_group("enemy"), "spawned mimics start awake (the pocket twitched its props first)")
		m.set_physics_process(false)
		m.drops_enabled = false
		m.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_true(bool(GameState.get_flag("test_mimics_cleared")), "quest flag on clear")
	assert_eq(flags.size(), 1, "set once")
	Events.flag_set.disconnect(cb)
