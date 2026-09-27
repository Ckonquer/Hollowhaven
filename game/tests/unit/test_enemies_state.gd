extends "res://tests/test_case.gd"
## Ground enemy state machine, driven with manual delta ticks (physics disabled):
## telegraph -> attack -> recover timings, fairness (no damage before the wind-up ends, one
## attacker at a time), flinch, leash, player death, safe zones, gloomling light exposure, defeat.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05

var _nodes: Array = []
var _saved_area: Node = null


class Dummy extends CharacterBody3D:
	var health: Node
	var knocks: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		knocks += 1


class SafeArea extends Node3D:
	var safe := true

	func is_safe_zone(_p: Vector3) -> bool:
		return safe


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	_saved_area = Game.area


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3) -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	_nodes.append(d)
	return d


func _enemy(id: String, target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create(id, {"home": pos, "no_drops": true})
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


## Ticks until the state changes (or `max_t` seconds). Returns the elapsed time.
func _tick_until(e: Node, s: String, max_t: float = 10.0) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		t += DT
	return t


func test_factory_spawns_known_ids_only() -> void:
	var e: Node = Factory.spawn("brambling", self, Transform3D(Basis.IDENTITY, Vector3(3, 0, 3)))
	_nodes.append(e)
	assert_not_null(e, "brambling spawned")
	assert_true(e.is_in_group("enemy"), "group enemy")
	assert_eq((e as CharacterBody3D).collision_layer, 8, "enemy layer")
	assert_eq((e as CharacterBody3D).collision_mask, 1 | 32, "collides with world|structure")
	assert_almost((e as Node3D).global_position.x, 3.0, 0.001)
	assert_almost(float(e.health.max_hp), 30.0, 0.001, "hp from data")
	assert_null(Factory.spawn("dragon", self, Transform3D.IDENTITY), "unknown id -> null")


func test_telegraph_attack_recover_timings() -> void:
	var d := _dummy(Vector3(0, 0, -1.5))
	var e := _enemy("brambling", d)
	_tick_until(e, "chase", 3.0)
	assert_eq(e.state, "chase", "aggro when Krystal is close")
	_tick_until(e, "telegraph", 3.0)
	assert_eq(e.state, "telegraph", "winds up once in reach")
	var tele := _tick_until(e, "attack", 3.0)
	assert_almost(tele, 0.7, DT + 0.001, "telegraph lasts data.telegraph (0.7 s)")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage during the wind-up")
	var atk := _tick_until(e, "recover", 3.0)
	assert_almost(atk, Base.ATTACK_TIME, DT + 0.001, "short attack")
	assert_almost(float(d.health.hp), 90.0, 0.001, "bite lands for data damage (10)")
	assert_eq(d.knocks, 1, "and knocks back")
	var rec := _tick_until(e, "chase", 5.0)
	assert_almost(rec, 1.1, DT + 0.001, "dizzy recovery lasts data.recover (1.1 s)")
	# Cooldown: no instant second wind-up
	var gap := _tick_until(e, "telegraph", 5.0)
	assert_true(gap >= 1.6 - 1.1 - 0.001, "cooldown respected before the next telegraph (%.2f)" % gap)


func test_dodge_out_of_reach_avoids_damage() -> void:
	var d := _dummy(Vector3(0, 0, -1.5))
	var e := _enemy("brambling", d)
	_tick_until(e, "telegraph", 5.0)
	d.global_position = Vector3(0, 0, -5.5)       # Krystal rolls away during the wiggle
	_tick_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "a readable telegraph can be dodged")


func test_one_attacker_at_a_time() -> void:
	var d := _dummy(Vector3(0, 0, 0))
	var a := _enemy("brambling", d, Vector3(1.4, 0, 0))
	var b := _enemy("brambling", d, Vector3(-1.4, 0, 0))
	var t := 0.0
	while a.state != "telegraph" and b.state != "telegraph" and t < 4.0:
		a.tick(DT)
		b.tick(DT)
		t += DT
	var first: Node = a if a.state == "telegraph" else b
	var second: Node = b if first == a else a
	assert_eq(first.state, "telegraph", "someone winds up")
	for i in 12:
		a.tick(DT)
		b.tick(DT)
		assert_false(second.state == "telegraph", "the other waits while the stagger window is closed")
	assert_true(second.is_threatening(), "the waiting one is still engaged (circling)")
	Base.clock_override_ms += Base.ATTACK_STAGGER_MS + 10
	var joined := false
	for i in 10:
		a.tick(DT)
		b.tick(DT)
		joined = joined or second.state == "telegraph"
	assert_true(joined, "second winds up once the stagger has passed")


func test_flinch_interrupts_windup_once() -> void:
	var d := _dummy(Vector3(0, 0, -1.5))
	var e := _enemy("brambling", d)
	_tick_until(e, "telegraph", 5.0)
	e.health.apply_damage(5.0, d, Vector3.FORWARD)
	assert_eq(e.state, "flinch", "a hit staggers the wind-up")
	_tick_until(e, "telegraph", 5.0)
	e.health.apply_damage(5.0, d, Vector3.FORWARD)
	assert_eq(e.state, "telegraph", "flinch immunity: the next wind-up goes through")


func test_leash_and_return_home() -> void:
	var d := _dummy(Vector3(0, 0, -6.0))
	var e := _enemy("brambling", d)
	_tick_until(e, "chase", 3.0)
	assert_eq(e.state, "chase")
	assert_true(e.is_threatening(), "threatening while chasing")
	d.global_position = Vector3(0, 0, -40.0)     # far beyond the leash radius (22)
	_tick_until(e, "return", 2.0)
	assert_eq(e.state, "return", "gives up and walks home")
	assert_false(e.is_threatening(), "not threatening when leashing home")


func test_player_death_and_safe_zone_stop_hunting() -> void:
	var d := _dummy(Vector3(0, 0, -2.0))
	var e := _enemy("brambling", d)
	_tick_until(e, "chase", 3.0)
	Events.player_died.emit()
	assert_eq(e.state, "return", "stops hunting when Krystal falls")
	d.health.apply_damage(1000.0)
	for i in 40:
		e.tick(DT)
	assert_false(e.state in ["chase", "telegraph"], "never re-aggros on a defeated player")
	# Safe zone
	var d2 := _dummy(Vector3(0, 0, -2.0))
	var e2 := _enemy("brambling", d2, Vector3(10, 0, 0))
	(e2 as Node3D).global_position = Vector3(0, 0, 0)
	var area := SafeArea.new()
	add_child(area)
	_nodes.append(area)
	Game.area = area
	for i in 30:
		e2.tick(DT)
	assert_false(e2.state in ["chase", "telegraph", "attack"], "no hunting inside a safe zone")
	area.safe = false
	_tick_until(e2, "chase", 3.0)
	assert_eq(e2.state, "chase", "hunts again outside it")


func test_gloomling_light_exposure() -> void:
	var d := _dummy(Vector3(0, 0, -1.6))
	var g := _enemy("gloomling", d)
	g.light_override = 0.0
	_tick_until(g, "telegraph", 5.0)
	assert_eq(g.state, "telegraph", "attacks in the dark")
	assert_almost(float(g.health.damage_taken_mult), 1.0, 0.001)
	g.light_override = 0.8                        # lantern raised mid-wind-up
	for i in 5:
		g.tick(DT)
	assert_true(g.exposed, "exposed in light")
	assert_eq(g.state, "backoff", "the light cancels the swipe and it backs off")
	assert_almost(float(g.health.damage_taken_mult), 2.0, 0.001, "double damage while exposed")
	var dealt: float = g.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_almost(dealt, 20.0, 0.001)
	# Hysteresis: 0.35 keeps it exposed, below 0.3 clears it
	g.light_override = 0.35
	for i in 5:
		g.tick(DT)
	assert_true(g.exposed, "still exposed at 0.35")
	g.light_override = 0.1
	for i in 5:
		g.tick(DT)
	assert_false(g.exposed, "hidden again in the gloom")
	assert_almost(float(g.health.damage_taken_mult), 1.0, 0.001)


func test_gloomling_steels_itself_after_hesitating() -> void:
	var d := _dummy(Vector3(0, 0, -1.6))
	var g := _enemy("gloomling", d)
	g.light_override = 0.9
	_tick_until(g, "backoff", 1.0)
	assert_eq(g.state, "backoff", "hesitates as soon as it is caught in the light")
	var hes := _tick_until(g, "chase", 3.0)
	assert_almost(hes, 1.3, DT + 0.001, "hesitation lasts 1.3 s")
	_tick_until(g, "telegraph", 3.0)
	assert_eq(g.state, "telegraph", "then braves the light for a moment (light is a tool, not a force field)")
	assert_true(g.exposed, "but it is still exposed (double damage) while it does")


func test_gloomling_damage_scales_with_intensity() -> void:
	Settings.set_value("horror_intensity", 0)
	var d := _dummy(Vector3(0, 0, -1.6))
	var g := _enemy("gloomling", d)
	g.light_override = 0.0
	_tick_until(g, "recover", 6.0)
	assert_almost(float(d.health.hp), 100.0 - 12.0 * 0.6, 0.01, "Gentle: 60% damage underground")


func test_defeat_emits_and_counts() -> void:
	var d := _dummy(Vector3(0, 0, -4.0))
	var e := _enemy("brambling", d)
	var killed: Array = []
	var cb := func(id: String, _p: Vector3) -> void: killed.append(id)
	Events.enemy_killed.connect(cb)
	var defeated := [false]
	e.defeated.connect(func() -> void: defeated[0] = true)
	var before := int(GameState.stats.get("enemies_defeated", 0))
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	Events.enemy_killed.disconnect(cb)
	assert_eq(e.state, "dead")
	assert_true(defeated[0], "defeated signal")
	assert_eq(killed, ["brambling"], "Events.enemy_killed")
	assert_eq(int(GameState.stats["enemies_defeated"]), before + 1, "stat counted")
	assert_false(e.is_in_group("enemy"), "leaves the enemy group at once")
	assert_false(e.is_threatening())


func test_roll_drops_table() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var table := [{"item": "fiber", "min": 1, "max": 3, "chance": 1.0}, {"item": "berries", "min": 1, "max": 2, "chance": 0.0}]
	for i in 20:
		var out: Array = Base.roll_drops(table, rng)
		assert_eq(out.size(), 1, "guaranteed drop only")
		var n := int(out[0]["count"])
		assert_true(n >= 1 and n <= 3, "count within min..max")
		assert_eq(out[0]["item"], "fiber")
	var none: Array = Base.roll_drops([{"item": "glowcap", "min": 0, "max": 0, "chance": 1.0}], rng)
	assert_eq(none.size(), 0, "zero-count rolls drop nothing")


func test_knockback_and_threat_flags() -> void:
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _enemy("brambling", d)
	e.knockback(Vector3(0, 0, 1), 5.0)
	assert_true((e.get("_knock") as Vector3).z > 4.0, "knockback stored as horizontal push")
	e.knockback(Vector3.UP, 5.0)
	assert_true((e.get("_knock") as Vector3).z > 4.0, "a purely vertical push is ignored")
