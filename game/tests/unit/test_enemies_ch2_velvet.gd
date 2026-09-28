extends "res://tests/test_case.gd"
## Velvet Wing (module C5): hangs still out of reach (never wanders), the dash (folded-cloak tell, marked lane = hit
## lane, one hit) and the reachable height it is left at after a dash - hit or missed - so Krystal's swing reaches it;
## the drain: a visible mark + tether, broken by line of sight, by ward-light (not her own lantern) or by a hit, and a
## completed channel heals it by exactly the damage dealt (a dodge heals nothing); Intense's dash feint always ends
## with a full separate final tell; no feint below Intense.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Wing := preload("res://src/enemies/velvet_wing.gd")

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


class Lamp extends Node3D:
	var light_radius: float = 5.0
	var on := true

	func is_light_active() -> bool:
		return on


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
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


func _dummy(pos: Vector3, group: String = "player") -> Dummy:
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


func _wing(target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create("velvet_wing", {"home": pos, "no_drops": true})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	e.ward_light_override = 0.0
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


func _reachable(e: Node, d: Node3D) -> bool:
	var aim: Vector3 = e.get_aim_point()
	return absf(aim.y - (d.global_position.y + 0.9)) <= Combat.MAX_VERTICAL_REACH


func test_hangs_still_out_of_reach() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _wing(d, Vector3(2, 0, 2))
	for i in 600:
		e.tick(DT)
	assert_eq(e.state, "idle", "hangs still")
	assert_true((e as Node3D).global_position.distance_to(Vector3(2, 0, 2)) < 0.01, "never wanders off its roost")
	assert_almost(float(e.hover_y), Wing.HANG_HEIGHT, 0.01, "hangs at its roost height")
	d.global_position = Vector3(2, 0, 2.5)
	assert_false(_reachable(e, d), "out of sword reach while hanging")
	e.visual._process(DT)
	assert_true(bool(e.visual.hanging), "hangs upside down (visual)")


func test_dash_folded_tell_lane_one_hit_then_reachable() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var d := _dummy(Vector3(0, 0, -4.0))
	var e := _wing(d)
	e.next_attack = "dash"
	await wait_physics(2)
	_until(e, "telegraph", 4.0, true)
	assert_eq(String(e.attack_kind), "dash")
	for i in 20:
		e.visual._process(DT)
	assert_true(float(e.visual.fold) > 0.8, "it folds its cloak (visual tell)")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "lane", "the dash line is drawn")
	assert_almost(float(m.footprint()["width"]), Wing.DASH_LANE_WIDTH, 0.001, "marked width = hit width")
	assert_false(_reachable(e, d), "out of reach while it winds up")
	var tele := _until(e, "dash", 3.0, true)
	assert_almost(tele, 1.0, DT * 2.0, "wind-up = data 1.0 s")
	_until(e, "recover", 2.0, true)
	assert_eq(d.damaged_count, 1, "one hit")
	assert_almost(float(d.health.hp), 89.0, 0.001, "data damage 11")
	assert_true(_reachable(e, d), "after the dash it is within sword reach")
	for i in 30:
		e.tick(DT)
		assert_true(_reachable(e, d), "and stays reachable through its recovery")
	assert_almost(_until(e, "chase", 3.0, true) + 0.5, 1.4, DT * 3.0, "recover = data 1.4 s")


func test_missed_dash_leaves_it_reachable_for_a_swing() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var d := _dummy(Vector3(0, 0, -4.0))
	var e := _wing(d)
	e.next_attack = "dash"
	await wait_physics(2)
	_until(e, "telegraph", 4.0, true)
	while e.state_time < 0.8:
		_step(e, true)
	d.global_position = Vector3(1.8, 0, -4.0)
	_until(e, "recover", 3.0, true)
	assert_almost(float(d.health.hp), 100.0, 0.001, "side-stepping the lane avoids the dash")
	assert_eq(int(e.dashes_missed), 1, "recorded as a miss")
	# Krystal walks up and swings: the real melee query reaches it.
	var wp: Vector3 = (e as Node3D).global_position
	d.global_position = wp + Vector3(0, 0, 1.4)
	await wait_physics(1)
	var hp0: float = e.health.hp
	var hits: Array = Combat.melee(d, d.global_position + Vector3.UP * 0.9, Vector3(0, 0, -1), 2.5, 110.0, 18.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 1, "her swing connects")
	assert_true(float(e.health.hp) < hp0, "it takes the hit")


func test_completed_drain_heals_exactly_what_it_dealt() -> void:
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _wing(d)
	e.health.set_hp(30.0)
	e.next_attack = "drain"
	_until(e, "telegraph", 4.0)
	assert_eq(String(e.attack_kind), "drain")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "ring", "a drain mark under her")
	assert_true(Vector2(m.footprint()["center"].x, m.footprint()["center"].z).distance_to(Vector2(0, -5)) < 0.05, "the mark sits on Krystal")
	assert_true(bool(e.tether_visible()), "a visible tether links them")
	var tele := 0.0
	while e.state == "telegraph" and tele < 3.0:
		e.tick(DT)
		tele += DT
		if tele >= 0.6 and e.state == "telegraph":
			assert_true(_reachable(e, d), "it settles within reach early in the wind-up (%.2f s)" % tele)
	assert_eq(e.state, "drain")
	assert_almost(tele, 1.5, DT * 2.0, "drain wind-up = data 1.5 s")
	assert_true(_reachable(e, d), "within reach while it drains")
	assert_almost(float(d.health.hp), 100.0, 0.001, "nothing drained before the channel finishes")
	assert_almost(float(e.health.hp), 30.0, 0.001, "and no healing yet")
	var ch := _until(e, "recover", 3.0)
	assert_almost(ch, 2.0, DT * 2.0, "channel = data 2.0 s")
	assert_eq(d.damaged_count, 1, "one drain hit")
	assert_almost(float(d.health.hp), 94.0, 0.001, "data drain damage 6")
	assert_almost(float(e.health.hp), 36.0, 0.001, "healed by exactly the damage dealt")
	assert_almost(float(e.healed_total), 6.0, 0.001)
	assert_false(bool(e.tether_visible()), "tether gone")


func test_dodged_drain_heals_nothing() -> void:
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _wing(d)
	e.health.set_hp(30.0)
	e.next_attack = "drain"
	_until(e, "drain", 5.0)
	d.health.grant_iframes(5.0)
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "i-frames: nothing drained")
	assert_almost(float(e.health.hp), 30.0, 0.001, "and nothing healed: no unavoidable lifesteal")


func test_drain_breaks_when_a_wall_cuts_the_line() -> void:
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _wing(d)
	e.health.set_hp(30.0)
	e.next_attack = "drain"
	_until(e, "drain", 5.0)
	_box(Vector3(0, 1.5, -2.5), Vector3(6, 4, 0.4))
	await wait_physics(2)
	_until(e, "recover", 1.0)
	assert_eq(String(e.last_break_reason), "sight", "broken by line of sight")
	assert_true(e.state_time < 0.5, "it broke within a check or two")
	for i in 150:
		e.tick(DT)
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage")
	assert_almost(float(e.health.hp), 30.0, 0.001, "no heal")


func test_drain_breaks_in_ward_light_but_not_her_own_lantern() -> void:
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _wing(d)
	e.ward_light_override = -1.0
	# Her own lantern (the player is a light source) never counts as ward-light.
	var own := Lamp.new()
	d.add_child(own)
	own.add_to_group("player")
	own.add_to_group("light_source")
	assert_almost(float(e.ward_light_at(d.global_position + Vector3.UP * 0.9)), 0.0, 0.001, "her lantern is not ward-light")
	e.next_attack = "drain"
	_until(e, "drain", 5.0)
	assert_eq(e.state, "drain", "the channel starts in the dark")
	var lamp := Lamp.new()
	add_child(lamp)
	lamp.add_to_group("light_source")
	lamp.global_position = Vector3(0.5, 1.0, -5.0)
	_nodes.append(lamp)
	assert_true(float(e.ward_light_at(d.global_position + Vector3.UP * 0.9)) >= Wing.WARD_LIGHT, "a lamp beside her is ward-light")
	_until(e, "recover", 1.0)
	assert_eq(String(e.last_break_reason), "light", "stepping into ward-light breaks the drain")
	assert_almost(float(d.health.hp), 100.0, 0.001)


func test_a_hit_breaks_the_drain_and_it_is_open() -> void:
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _wing(d)
	e.next_attack = "drain"
	_until(e, "telegraph", 5.0)
	e.health.apply_damage(5.0, d, Vector3.FORWARD)
	assert_eq(e.state, "recover", "a hit during the wind-up breaks it")
	assert_eq(String(e.last_break_reason), "hit")
	Base.reset_attack_tokens()
	e.set("_drain_cd", 0.0)
	e.next_attack = "drain"
	_until(e, "drain", 8.0)
	assert_eq(e.state, "drain")
	e.health.apply_damage(5.0, d, Vector3.FORWARD)
	assert_eq(e.state, "recover", "a hit during the channel breaks it")
	assert_eq(int(e.drains_broken), 2)
	assert_true(_reachable(e, d), "it recoils within reach")
	assert_almost(float(d.health.hp), 100.0, 0.001, "nothing drained")


func test_intense_feint_ends_with_a_full_final_tell() -> void:
	Settings.set_value("horror_intensity", 2)
	var d := _dummy(Vector3(0, 0, -4.0))
	var e := _wing(d)
	e.dashes_done = 1
	e.next_attack = "dash"
	var tells: Array = []
	var cb := func(s: String) -> void:
		if s == "telegraph":
			tells.append(s)
	e.state_changed.connect(cb)
	_until(e, "telegraph", 4.0)
	e.force_feint()
	var t := _until(e, "dash", 4.0)
	assert_eq(int(e.feints), 1, "one feint")
	assert_eq(tells.size(), 2, "the feint restarts the tell (a separate final tell)")
	assert_true(t >= 0.5 + 1.0 - DT * 2.0, "final tell still lasts the full wind-up (%.2f s total)" % t)
	assert_true(bool(e.mark().is_showing()), "the lane is shown")


func test_no_feint_below_intense() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	for level in [0, 1]:
		Settings.set_value("horror_intensity", level)
		Base.reset_attack_tokens()
		var d := _dummy(Vector3(0, 0, -4.0))
		d.health.invulnerable = true                   # every dash runs its whole course
		var e := _wing(d)
		e.dashes_done = 3
		for i in 20:
			e.next_attack = "dash"
			_until(e, "telegraph", 6.0)
			_until(e, "recover", 4.0)
			_until(e, "chase", 4.0)
		assert_eq(int(e.feints), 0, "no feints at intensity %d" % level)
		e.queue_free()
		d.queue_free()
		await wait_frames(1)
