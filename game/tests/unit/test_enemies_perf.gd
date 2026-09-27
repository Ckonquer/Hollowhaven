extends "res://tests/test_case.gd"
## Performance guard: the per-frame CPU cost of the enemy logic (state machine + movement) and of
## Combat.light_at must stay tiny, so a pack of enemies never threatens the 60 FPS target.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")

var _nodes: Array = []


class LightSrc extends Node3D:
	var light_radius: float = 7.0

	func is_light_active() -> bool:
		return true


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.reset_attack_tokens()
	await wait_frames(2)


func test_twenty_enemies_tick_cheaply() -> void:
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, 0)
	_nodes.append(target)
	var enemies: Array = []
	for i in 20:
		var id := "gloomling" if i % 3 == 0 else "brambling"
		var a := TAU * float(i) / 20.0
		var pos := Vector3(cos(a) * 6.0, 0.0, sin(a) * 6.0)
		var e: Node = Factory.create(id, {"home": pos, "no_drops": true})
		add_child(e)
		(e as Node3D).global_position = pos
		e.set_physics_process(false)
		e.target_override = target
		enemies.append(e)
		_nodes.append(e)
	await wait_physics(2)
	var t0 := Time.get_ticks_usec()
	var frames := 120
	for f in frames:
		for e in enemies:
			e.tick(1.0 / 60.0)
			e._apply_movement(1.0 / 60.0)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	print("PERF enemies: 20 enemies tick+move = %.3f ms per frame" % per_frame_ms)
	assert_true(per_frame_ms < 4.0, "20 enemies cost < 4 ms per frame (%.3f ms)" % per_frame_ms)


func test_light_queries_are_cheap() -> void:
	for i in 12:
		var s := LightSrc.new()
		add_child(s)
		s.global_position = Vector3(float(i) * 3.0, 0, 0)
		s.add_to_group("light_source")
		_nodes.append(s)
	Combat.invalidate_light_cache()
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in 2000:
		acc += Combat.light_at(Vector3(float(i % 40), 0.5, 1.0))
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	print("PERF light_at with 12 sources: %.2f us per query" % us)
	assert_true(us < 40.0, "light_at stays in the microseconds (%.2f us)" % us)
	assert_true(acc > 0.0)
