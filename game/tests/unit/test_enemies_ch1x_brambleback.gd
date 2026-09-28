extends "res://tests/test_case.gd"
## Brambleback: idle -> chase -> telegraph (1.0 s, marked lane that locks) -> charge -> recover (1.5 s) timings,
## one hit through Krystal's health path, side-stepping the lane, front armour (reduced, never nothing; front
## hits never stagger), the charge never goes through a wall (no wind-up without a clear line, a wall that
## appears mid-wind-up ends the charge in a bonk with a longer stun), companions are never hit, pack cap.
## Movement tests step tick() + _apply_movement() at the physics rate on a real floor.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Brambleback := preload("res://src/enemies/brambleback.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null


class Dummy extends CharacterBody3D:
	var health: Node
	var knocks: int = 0
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		knocks += 1


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
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3, group: String = "player") -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group(group)
	_nodes.append(d)
	return d


func _box(pos: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = layer
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	add_child(w)
	w.global_position = pos
	_nodes.append(w)
	return w


func _floor() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))


func _enemy(target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create("brambleback", {"home": pos, "no_drops": true})
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _step(e: Node, move: bool) -> void:
	e.tick(DT)
	if move:
		e._apply_movement(DT)


## Steps until the state changes to `s` (or max_t). Returns the elapsed seconds.
func _until(e: Node, s: String, max_t: float = 10.0, move: bool = false) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		_step(e, move)
		t += DT
	return t


func test_state_sequence_timings_and_one_hit() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -4.5))
	var e := _enemy(d)
	await wait_physics(2)
	assert_eq(e.state, "idle", "starts idle")
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "telegraph", 4.0, true)
	assert_eq(e.state, "telegraph", "winds up when Krystal is within its charge range")
	var m: Node3D = e.mark()
	assert_true(bool(m.is_showing()), "a lane is drawn on the ground")
	assert_eq(m.footprint()["kind"], "lane")
	assert_almost(float(m.footprint()["width"]), Brambleback.LANE_WIDTH, 0.001, "marked width = hit width")
	var tele := _until(e, "charge", 3.0, true)
	assert_almost(tele, 1.0, DT * 2.0, "wind-up lasts data telegraph (1.0 s)")
	assert_true(bool(m.footprint()["locked"]), "the lane locked before the charge")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage during the wind-up")
	_until(e, "recover", 2.0, true)
	assert_eq(e.state, "recover")
	assert_almost(float(d.health.hp), 87.0, 0.001, "the charge lands data damage (13) once")
	assert_eq(d.damaged_count, 1, "one hit through the health path")
	assert_eq(d.knocks, 1, "one knockback")
	assert_false(bool(m.is_showing()), "the mark is gone once it recovers")
	var rec := _until(e, "chase", 3.0, true)
	assert_almost(rec, 1.5, DT * 2.0, "recovery (flank window) lasts data recover (1.5 s)")
	assert_eq(seen.slice(0, 4), ["chase", "telegraph", "charge", "recover"], "state sequence (%s)" % str(seen))


func test_sidestep_out_of_the_lane_avoids_the_charge() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -4.5))
	var e := _enemy(d)
	await wait_physics(2)
	_until(e, "telegraph", 4.0, true)
	while e.state_time < 0.7:
		_step(e, true)
	d.global_position = Vector3(1.6, 0, -4.5)          # steps out of the locked 1.4 m lane
	_until(e, "recover", 3.0, true)
	assert_eq(e.state, "recover", "the charge runs its lane and stops")
	assert_almost(float(d.health.hp), 100.0, 0.001, "side-stepping out of the marked lane avoids it")


func test_front_armor_reduces_but_never_nullifies() -> void:
	var d := _dummy(Vector3(0, 0, -10))
	var e := _enemy(d)
	var front := Vector3(0, 0, 1)                      # hit travelling toward +Z = coming from its front (-Z)
	assert_almost(float(e.health.apply_damage(10.0, d, front)), 6.0, 0.001, "front hits take 60% (front_armor 0.4)")
	assert_true(bool(e.last_hit_frontal), "recorded as a front hit (glance feedback)")
	assert_almost(float(e.health.apply_damage(10.0, d, Vector3(-1, 0, 0))), 10.0, 0.001, "flank hits take full damage")
	assert_false(bool(e.last_hit_frontal), "recorded as a flank hit")
	assert_almost(float(e.health.apply_damage(10.0, d, Vector3(0, 0, -1))), 10.0, 0.001, "hits in the back take full damage")
	assert_almost(float(e.health.apply_damage(1.0, d, front)), 1.0, 0.001, "tiny hits are never reduced to nothing")
	assert_almost(float(e.health.apply_damage(5.0, d, front)), 3.0, 0.001, "early tools still hurt (hand 5 -> 3)")
	# Through the real melee path, from the front
	var attacker := _dummy(Vector3(0, 0, -1.5), "combat_probe")
	await wait_physics(2)
	var hp0: float = e.health.hp
	var hits: Array = Combat.melee(attacker, Vector3(0, 0.9, -1.5), Vector3(0, 0, 1), 2.5, 110.0, 18.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 1, "the sword connects")
	assert_almost(hp0 - float(e.health.hp), 18.0 * 0.6, 0.01, "front sword hit reduced")


func test_front_hits_never_stagger_flank_hits_do() -> void:
	var d := _dummy(Vector3(0, 0, -4.5))
	var e := _enemy(d)
	_until(e, "telegraph", 4.0)
	e.health.apply_damage(8.0, d, Vector3(0, 0, 1))
	assert_eq(e.state, "telegraph", "a front hit glances off: the wind-up goes on")
	e.health.apply_damage(8.0, d, Vector3(1, 0, 0))
	assert_eq(e.state, "flinch", "a flank hit staggers the wind-up")


func test_no_windup_through_a_wall() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -4.5))
	_box(Vector3(0, 1, -2.2), Vector3(5, 3, 0.4))
	var e := _enemy(d)
	await wait_physics(3)
	for i in 180:
		_step(e, true)
	assert_false(e.state in ["telegraph", "charge"], "no charge wind-up without a clear line (state %s)" % e.state)
	assert_almost(float(d.health.hp), 100.0, 0.001)


func test_wall_mid_windup_ends_the_charge_in_a_bonk() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _enemy(d)
	await wait_physics(2)
	_until(e, "telegraph", 4.0, true)
	assert_eq(e.state, "telegraph")
	var wall := _box(Vector3(0, 1, -2.4), Vector3(5, 3, 0.4))     # she ducks behind a pillar
	await wait_physics(3)
	_until(e, "charge", 3.0, true)
	var lane: float = e.lane_length()
	assert_true(lane < 2.4, "the charge lane is clipped at the wall (%.2f m)" % lane)
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "stunned", 2.0, true)
	assert_eq(e.state, "stunned", "it bonks into the wall (%s)" % str(seen))
	assert_true((e as Node3D).global_position.z > wall.global_position.z, "never passes through the wall")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage behind the wall")
	var stun := _until(e, "chase", 5.0, true)
	assert_almost(stun, 1.5 + Brambleback.BONK_EXTRA, DT * 2.0, "a bonk opens a longer punish window")


func test_charge_never_hits_companions() -> void:
	_floor()
	var d := _dummy(Vector3(3.5, 0, -3.5))
	var e := _enemy(d)
	await wait_physics(2)
	_until(e, "charge", 4.0, true)
	var dir: Vector3 = -(e as Node3D).global_transform.basis.z
	var friend := _dummy((e as Node3D).global_position + dir * 1.2, "companion")
	d.global_position = Vector3(-6, 0, 6)              # Krystal is elsewhere; Pebble stands in the lane
	_until(e, "recover", 2.0, true)
	assert_almost(float(friend.health.hp), 100.0, 0.001, "companions are never damaged")


func test_pack_cap_on_committed_charges() -> void:
	var d := _dummy(Vector3(0, 0, 0))
	var pack: Array = []
	for i in 3:
		var a := TAU * float(i) / 3.0
		pack.append(_enemy(d, Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)))
	var most := 0
	for f in 600:
		Base.clock_override_ms += int(DT * 1000.0)
		var n := 0
		for e in pack:
			_step(e, false)
			if e.state in ["telegraph", "charge"]:
				n += 1
		most = maxi(most, n)
	assert_true(most >= 1, "they do attack")
	assert_true(most <= Base.MAX_ATTACKERS, "never more than %d committed at once (saw %d)" % [Base.MAX_ATTACKERS, most])
