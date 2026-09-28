extends "res://tests/test_case.gd"
## Bellcap Sentry (module C5): the swell (data 1.3 s, never interrupted by hits), the ring mark = the pulse radius,
## muted-readable symbols (outward arrows standing ON the ring, a bell glyph) and the swelling cap, one radial pulse
## (inside hit once, outside safe, walls and floors block it, companions never hit), and a clear recovery window.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Bellcap := preload("res://src/enemies/bellcap_sentry.gd")

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
	Settings.set_value("reduce_flashing", false)
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


func _bell(target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create("bellcap_sentry", {"home": pos, "no_drops": true})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _until(e: Node, s: String, max_t: float = 10.0) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		e.visual._process(DT)
		t += DT
	return t


func test_swell_ring_symbols_and_one_pulse() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var friend := _dummy(Vector3(1.0, 0, 1.0), "companion")
	var e := _bell(d)
	_until(e, "telegraph", 4.0)
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "ring", "a ring marks the pulse")
	assert_almost(float(m.footprint()["radius"]), float(ItemDB.enemy("bellcap_sentry")["attacks"][0]["radius"]), 0.001, "marked radius = data radius")
	assert_true((m.footprint()["center"] as Vector3).distance_to(Vector3.ZERO) < 0.01, "centred on the bell")
	for i in 40:
		e.tick(DT)
		e.visual._process(DT)
	assert_true(bool(e.visual.symbols_visible()), "pale arrow symbols and a bell glyph are shown (muted-readable)")
	for p in e.visual.arrow_positions():
		var q: Vector3 = p
		assert_almost(Vector2(q.x, q.z).length(), float(e.pulse_radius()), 0.2, "each arrow stands on the ring")
	assert_true(float(e.visual.swell) > 0.3, "the bell cap visibly swells")
	var tele := _until(e, "pulse", 3.0) + 40.0 * DT
	assert_almost(tele, 1.3, DT * 2.0, "wind-up = data 1.3 s")
	assert_almost(float(d.health.hp), 100.0, 0.001, "nothing during the swell")
	_until(e, "recover", 1.0)
	assert_eq(d.damaged_count, 1, "one pulse hit")
	assert_almost(float(d.health.hp), 85.0, 0.001, "data damage 15")
	assert_almost(float(friend.health.hp), 100.0, 0.001, "companions never hit")
	assert_eq(int(e.pulses_done), 1)
	assert_false(bool(m.is_showing()), "ring gone in recovery")
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, 1.8, DT * 2.0, "a clear recovery: data 1.8 s")


func test_stepping_out_of_the_ring_is_safe_and_there_is_time_to() -> void:
	var d := _dummy(Vector3(0, 0, -3.6))
	var e := _bell(d)
	for i in 120:
		e.tick(DT)
	assert_ne(e.state, "telegraph", "it only winds up once she is well inside the ring (%.1f m)" % e.attack_reach())
	d.global_position = Vector3(0, 0, -3.0)
	_until(e, "telegraph", 3.0)
	assert_eq(e.state, "telegraph")
	var needed: float = float(e.pulse_radius()) + 0.45 - 3.0
	assert_true(needed / 1.3 < 4.0, "walking out at a stroll (%.1f m in 1.3 s) is enough" % needed)
	d.global_position = Vector3(0, 0, -4.8)
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "outside the ring: safe")
	assert_eq(int(e.last_pulse_hits), 0)


func test_hits_never_interrupt_the_swell() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _bell(d)
	_until(e, "telegraph", 4.0)
	e.health.apply_damage(10.0, d, Vector3.FORWARD)
	e.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_eq(e.state, "telegraph", "the heavy swell cannot be stagger-locked")
	_until(e, "recover", 3.0)
	assert_eq(int(e.pulses_done), 1, "the pulse still comes")


func test_no_pulse_through_walls_or_floors() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _bell(d)
	_until(e, "telegraph", 4.0)
	_box(Vector3(0, 1.0, -1.4), Vector3(6, 3, 0.3))
	await wait_physics(2)
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "a wall between the bell and her blocks the pulse")
	# A ledge above the ring: never through a floor / ceiling.
	var up := _dummy(Vector3(1.5, 3.0, 0))
	assert_eq(e.pulse_hits(Vector3.ZERO, 4.0, 15.0, 0.0).size(), 0, "nothing on a ledge 3 m above")
	assert_almost(float(up.health.hp), 100.0, 0.001)


func test_reduce_flashing_keeps_the_tint_steady() -> void:
	Settings.set_value("reduce_flashing", true)
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _bell(d)
	_until(e, "telegraph", 4.0)
	var prev := -1.0
	var ok := true
	for i in 60:
		e.tick(DT)
		e.visual._process(DT)
		var a: float = e.visual.tint_alpha()
		if prev >= 0.0 and a < prev - 0.001:
			ok = false
		prev = a
	assert_true(ok, "with reduce_flashing the tint only firms up (no strobe)")
