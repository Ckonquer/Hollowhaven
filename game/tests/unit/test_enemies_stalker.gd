extends "res://tests/test_case.gd"
## Stalker: lingering in darkness near an ambush point -> 1.0 s rattle -> lunge; counterplay by
## light / breaking line of sight / dodging; hits drive it off (it cannot be killed here);
## Gentle never lunges; the director's pass_overhead; live arachnophobia swap.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Combat := preload("res://src/combat/combat.gd")
const Stalker := preload("res://src/enemies/stalker.gd")

const DT := 0.05

var _nodes: Array = []


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


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Settings.set_value("arachnophobia", false)


func after_each() -> void:
	Settings.set_value("arachnophobia", false)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await wait_frames(2)


func _dummy(pos: Vector3) -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _stalker(target: Node3D, intensity: int = 1) -> Node:
	var route: Array = []
	for i in 6:
		route.append(Vector3(-7.5 + 3.0 * float(i), 4.0, 0.0))
	var s: Node = Factory.create("weaver", {"route": route, "ambush_points": [Vector3.ZERO], "zone": "silk"})
	add_child(s)
	s.set_process(false)
	s.target_override = target
	s.intensity_override = intensity
	s.light_override = 0.0
	s.los_override = 1
	_nodes.append(s)
	return s


func _tick_until(s: Node, st: String, max_t: float = 20.0) -> float:
	var t := 0.0
	while s.state != st and t < max_t:
		s.tick(DT)
		t += DT
	return t


func test_hidden_until_krystal_lingers_in_the_dark() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	assert_eq(s.state, "hidden")
	assert_false((s as Node3D).visible, "not visible while hidden")
	assert_false(s.is_in_group("enemy"), "not an active threat while hidden")
	s.light_override = 0.6                      # lantern up: nothing happens
	for i in 200:
		s.tick(DT)
	assert_eq(s.state, "hidden", "no ambush in the light")
	s.light_override = 0.0
	var t := _tick_until(s, "rattle", 15.0)
	assert_eq(s.state, "rattle", "ambush after lingering in darkness")
	assert_true(t >= 5.0 - 0.001 and t <= 5.4, "after ~5 s at Standard (%.2f)" % t)
	assert_true((s as Node3D).visible and s.is_in_group("enemy"))
	assert_true((s as Node3D).global_position.y > 2.0, "appears overhead, on the ceiling")


func test_rattle_then_lunge_hits_for_scaled_damage() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	_tick_until(s, "rattle", 15.0)
	var rattle := _tick_until(s, "lunge", 3.0)
	assert_almost(rattle, 1.0, DT + 0.001, "1.0 s rattle warning")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage before the lunge")
	_tick_until(s, "landed", 2.0)
	assert_almost(float(d.health.hp), 82.0, 0.001, "18 damage at Standard")
	assert_eq(d.knocks, 1)
	_tick_until(s, "retreat", 2.0)
	assert_eq(s.state, "retreat", "then it flees")
	_tick_until(s, "hidden", 10.0)
	assert_eq(s.state, "hidden", "and vanishes")
	for i in 100:
		s.tick(DT)
	assert_eq(s.state, "hidden", "cooldown before another ambush")


func test_dodging_the_lunge_avoids_damage() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	_tick_until(s, "lunge", 15.0)
	d.global_position = Vector3(0, 0, 3.5)       # rolled away
	_tick_until(s, "landed", 2.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "a well-timed dodge avoids it")


func test_raising_the_lantern_makes_it_recoil() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	_tick_until(s, "rattle", 15.0)
	s.tick(0.3)
	s.light_override = 0.5
	s.tick(DT)
	s.tick(0.2)
	assert_eq(s.state, "recoil", "light >= 0.4 makes it recoil")
	_tick_until(s, "hidden", 10.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "no lunge happened")


func test_breaking_line_of_sight_cancels() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	_tick_until(s, "rattle", 15.0)
	s.los_override = 0
	s.tick(0.2)
	assert_eq(s.state, "retreat", "loses Krystal behind cover and gives up")


func test_cannot_be_killed_hits_drive_it_off() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	_tick_until(s, "landed", 20.0)
	assert_almost(float(s.health.apply_damage(500.0)), 0.0, 0.001, "invulnerable")
	var attacker := _dummy(Vector3(0, 0, 2.0))
	var hits: Array = Combat.melee(attacker, Vector3(0, 1, 2.0), Vector3(0, 0, -1), 3.0, 120.0, 18.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 0, "a sword swing doesn't hurt it")
	assert_eq(s.state, "retreat", "but it makes it flee")


func test_gentle_never_lunges() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d, 0)
	for i in 600:
		s.tick(DT)
	assert_eq(s.state, "hidden", "Gentle: no ambushes, ever")
	assert_false(s.start_ambush(), "even when forced")
	assert_false(s.pass_overhead(), "and no pass right above Krystal")
	d.global_position = Vector3(40, 0, 20)
	assert_true(s.pass_overhead(), "only at a distance")


func test_intense_is_quicker_and_harder() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d, 2)
	var t := _tick_until(s, "rattle", 15.0)
	assert_true(t <= 3.9, "shorter linger at Intense (%.2f)" % t)
	_tick_until(s, "landed", 3.0)
	assert_almost(float(d.health.hp), 100.0 - 18.0 * 1.15, 0.01)


func test_pass_overhead_crawls_and_retreats() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var s := _stalker(d)
	assert_true(s.pass_overhead(), "director pass accepted")
	assert_eq(s.state, "emerge")
	assert_false(s.pass_overhead(), "busy")
	_tick_until(s, "pass", 1.0)
	var start: Vector3 = (s as Node3D).global_position
	for i in 40:
		s.tick(DT)
	assert_true((s as Node3D).global_position.distance_to(start) > 0.5, "it crawls along the route")
	var up: Vector3 = (s as Node3D).global_transform.basis.y
	assert_true(up.y < -0.9, "upside down on the ceiling")
	_tick_until(s, "hidden", 15.0)
	assert_eq(s.state, "hidden", "and melts back into the dark")
	assert_almost(float(d.health.hp), 100.0, 0.001, "a pass never attacks")


func test_arachnophobia_swaps_visual_live() -> void:
	var d := _dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	assert_true(s.visual.get_script() == preload("res://src/enemies/weaver_visual.gd"), "Weaver by default")
	Settings.set_value("arachnophobia", true)
	await wait_frames(1)
	assert_true(s.visual.get_script() == preload("res://src/enemies/shade_visual.gd"), "Hollow Shade when arachnophobia is on")
	Settings.set_value("arachnophobia", false)
	await wait_frames(1)
	assert_true(s.visual.get_script() == preload("res://src/enemies/weaver_visual.gd"), "and back")


class LitDummy extends Dummy:
	var light_radius: float = 6.0

	func _init() -> void:
		super._init()
		add_to_group("light_source")

	func is_light_active() -> bool:
		return true


func _lit_dummy(pos: Vector3) -> Node3D:
	var d := LitDummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	Combat.invalidate_light_cache()
	return d


func test_pass_plays_out_while_krystal_carries_a_lantern() -> void:
	# Audit regression: a director pass 12 m away used to recoil at once because Krystal's OWN lantern
	# counted as if it lit the stalker. It must crawl, and only shrink back from light at its own position.
	var d := _lit_dummy(Vector3(0, 0, 12))
	var s := _stalker(d)
	s.light_override = -1.0
	assert_true(s.pass_overhead(), "director pass accepted")
	_tick_until(s, "pass", 2.0)
	assert_eq(s.state, "pass", "reaches the crawl instead of recoiling from a lantern 12 m away")
	var start: Vector3 = (s as Node3D).global_position
	for i in 30:
		s.tick(DT)
	assert_true((s as Node3D).global_position.distance_to(start) > 0.5, "it crawls along the route")


func test_real_lantern_still_repels_a_rattle_overhead() -> void:
	var d := _lit_dummy(Vector3(0, 0, 0.5))
	var s := _stalker(d)
	s.light_override = -1.0
	assert_true(s.start_ambush(), "ambush starts")
	var t := _tick_until(s, "recoil", 1.0)
	assert_eq(s.state, "recoil", "a raised lantern right below it still drives it back")
	assert_true(t < 1.0, "before the rattle ends")


func test_retreat_never_steps_toward_krystal() -> void:
	var d := _dummy(Vector3(-9.0, 0, 0))                    # just past the route's west end
	var s := _stalker(d)
	var ref: Vector3 = d.global_position
	s.stretch_around(0)                                   # builds the (lazy) crawlable-segment data
	assert_true(s.segment_ok(0), "route segments are crawlable in this test (otherwise the check is vacuous)")
	var moves := 0
	for i in (s.route as Array).size():
		var step: int = s._away_step(i, ref)
		if step != 0:
			moves += 1
			var here: float = (s.route[i] as Vector3).distance_to(ref)
			var there: float = (s.route[i + step] as Vector3).distance_to(ref)
			assert_true(there > here, "node %d: the retreat step leads away (%.2f -> %.2f)" % [i, here, there])
	assert_true(moves > 0, "some nodes do have a way to back off")
	assert_eq(s._away_step((s.route as Array).size() - 1, ref), 0, "the far end has nowhere farther to go: fade in place")
