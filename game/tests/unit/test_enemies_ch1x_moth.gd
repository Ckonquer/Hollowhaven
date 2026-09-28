extends "res://tests/test_case.gd"
## Lantern Moth: chase -> telegraph (wings flare 1.1 s) -> ONE slow orb -> recover (rests 1.8 s at data rest
## height) timings; out of melee reach while flying, inside it while resting; the orb damages once through
## Krystal's health path; no wind-up without a clear line and an orb never passes a wall; one orb at a time.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Moth := preload("res://src/enemies/lantern_moth.gd")
const SHARED_PROJECTILE := "res://src/combat/projectile.gd"
const LOCAL_PROJECTILE := "res://src/enemies/enemy_projectile.gd"

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
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_stop_orbs()
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


func _stop_orbs() -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("stop_all")
	for p in get_children():
		if p.get_script() != null and p.get_script().resource_path == LOCAL_PROJECTILE:
			p.queue_free()


## Steps an orb by hand until it lands (the shared projectile caches its target groups: refresh them first).
func _fly(orb: Node3D, max_t: float = 4.0) -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("invalidate_targets")
	orb.set_physics_process(false)
	var t := 0.0
	while is_instance_valid(orb) and String(orb.get("result")) == "" and t < max_t:
		orb.step(DT)
		t += DT


func _moth(target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create("lantern_moth", {"home": pos, "no_drops": true})
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


func _reachable(e: Node, d: Node3D) -> bool:
	var aim: Vector3 = e.get_aim_point()
	return absf(aim.y - (d.global_position.y + 0.9)) <= Combat.MAX_VERTICAL_REACH


func test_sequence_timings_and_rest_height() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _moth(d)
	assert_eq(e.state, "idle", "starts idle")
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	assert_false(_reachable(e, d), "flying out of melee reach (aim %.2f m)" % float(e.get_aim_point().y))
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph", "starts its flare within range")
	var tele := _until(e, "recover", 3.0)
	assert_almost(tele, 1.1, DT * 2.0, "wing flare lasts data telegraph (1.1 s)")
	assert_eq(int(e.shots_fired), 1, "exactly one orb released")
	assert_not_null(e.orb, "the orb is alive")
	for i in 40:
		e.tick(DT)
	assert_true(bool(e.is_resting()), "settled to its rest height (%.2f)" % float(e.hover_y))
	assert_almost(float(e.hover_y), float(ItemDB.enemy("lantern_moth")["rest_height"]), 0.01, "rest height from data")
	assert_true(_reachable(e, d), "resting inside melee reach")
	# It keeps resting while its orb still drifts toward her (the punish window is not spent on the orb)...
	for i in int(1.6 / DT):
		e.tick(DT)
	assert_eq(e.state, "recover", "still resting 2.3 s after the release: its orb is still in flight")
	assert_true(_reachable(e, d))
	# ...and rests for data recover once the orb has landed / been dodged.
	_fly(e.orb as Node3D)
	assert_false(bool(e.has_orb_in_flight()))
	var rest := _until(e, "chase", 3.0)
	assert_almost(rest, 1.8, DT * 3.0, "rests for data recover (1.8 s) after the orb resolves")
	for i in 60:
		e.tick(DT)
	assert_false(_reachable(e, d), "back out of reach once it flies again")
	assert_eq(seen.slice(0, 4), ["chase", "telegraph", "recover", "chase"], "sequence (%s)" % str(seen))


func test_rest_hold_is_bounded_by_the_orb_flight() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _moth(d)
	_until(e, "recover", 5.0)
	var orb: Node3D = e.orb
	orb.set_physics_process(false)                       # the orb just hangs there (never lands)
	var def: Dictionary = e.attack_def("dust_orb")
	var cap := float(def["range"]) / float(def["speed"]) + 0.25 + float(def["recover"])
	var rest := _until(e, "chase", 8.0)
	assert_eq(e.state, "chase", "the rest always ends")
	assert_true(rest <= cap + DT * 3.0, "held at most the orb's flight time + data recover (%.2f <= %.2f)" % [rest, cap])
	assert_true(rest >= float(def["recover"]), "never shorter than data recover")


func test_flies_lower_under_a_ceiling() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _moth(d)
	await wait_physics(2)
	for i in 30:
		e.tick(DT)
	assert_almost(float(e.hover_cap), Moth.HOVER_HEIGHT, 0.001, "open sky: full hover height")
	assert_almost(float(e.hover_y), Moth.HOVER_HEIGHT, 0.01)
	_box(Vector3(0, 2.6, 0), Vector3(4, 0.4, 4))              # a low ceiling, underside at 2.4 m
	await wait_physics(2)
	for i in 30:
		e.tick(DT)
	assert_almost(float(e.hover_cap), 2.4 - Moth.HEADROOM, 0.02, "cap = ceiling - headroom")
	assert_true(float(e.hover_y) <= 2.4 - Moth.HEADROOM + 0.02, "ducked under it (%.2f)" % float(e.hover_y))
	assert_true(float(e.attack_origin().y) < 2.4, "never shoots from inside the ceiling")
	_box(Vector3(0, 1.3, 0), Vector3(4, 0.4, 4))              # absurdly low: never below its rest height
	await wait_physics(2)
	for i in 30:
		e.tick(DT)
	assert_almost(float(e.hover_cap), float(e.rest_height()), 0.001, "clamped to the rest height")


func test_player_melee_only_reaches_it_at_rest() -> void:
	var d := _dummy(Vector3(0, 0, -1.6))
	var e := _moth(d)
	await wait_physics(2)
	var hits: Array = Combat.melee(d, d.global_position + Vector3.UP * 0.9, Vector3(0, 0, 1), 2.2, 110.0, 5.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 0, "a swing cannot reach it while it hovers")
	e.hover_y = float(e.rest_height())
	hits = Combat.melee(d, d.global_position + Vector3.UP * 0.9, Vector3(0, 0, 1), 2.2, 110.0, 5.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 1, "a swing reaches it while it rests")


func test_orb_hits_once_through_the_health_path() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _moth(d)
	_until(e, "recover", 5.0)
	var orb: Node3D = e.orb
	assert_not_null(orb)
	var want := SHARED_PROJECTILE if ResourceLoader.exists(SHARED_PROJECTILE) else LOCAL_PROJECTILE
	assert_eq(orb.get_script().resource_path, want, "uses the shared projectile when present")
	assert_true(bool(e.has_orb_in_flight()))
	_fly(orb)
	assert_eq(String(orb.get("result")), "hit")
	assert_almost(float(d.health.hp), 91.0, 0.001, "data damage (9)")
	assert_eq(d.damaged_count, 1, "exactly one hit")
	assert_false(bool(e.has_orb_in_flight()), "a landed (pooled) orb no longer counts as its orb")


func test_no_shot_through_a_wall_and_orbs_stop_at_walls() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var wall := _box(Vector3(0, 1.5, -3), Vector3(6, 5, 0.4))
	var e := _moth(d)
	await wait_physics(3)
	for i in 300:
		e.tick(DT)
	assert_eq(int(e.shots_fired), 0, "never winds up without a clear line to her")
	assert_false(e.state == "telegraph")
	wall.queue_free()
	await wait_physics(3)
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph")
	_until(e, "recover", 3.0)
	var orb: Node3D = e.orb
	assert_not_null(orb)
	orb.set_physics_process(false)
	_box(Vector3(0, 1.5, -3), Vector3(6, 5, 0.4))            # she steps behind cover as it flies
	await wait_physics(3)
	_fly(orb)
	assert_eq(String(orb.get("result")), "wall", "the orb pops on the cover")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage behind cover")


## An overhang lip between its body and the release point (the orb appears 0.35 m in front of the body) while
## the line from the body down to her passes under the lip: the old check (release point -> her) was clear, so
## the orb would have started on the far side of the lip. Now the flare fizzles.
func test_orb_never_starts_beyond_a_lip() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _moth(d)
	_box(Vector3(0, 3.025, -0.27), Vector3(2, 0.35, 0.1))     # lip: y 2.85..3.2, z -0.32..-0.22
	await wait_physics(3)
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph", "it still sees her under the lip and winds up")
	_until(e, "recover", 3.0)
	assert_eq(int(e.shots_fired), 0, "no orb released through the lip")
	assert_null(e.orb)


func test_one_orb_at_a_time() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _moth(d)
	_until(e, "recover", 5.0)
	var orb: Node3D = e.orb
	orb.set_physics_process(false)                       # the orb just hangs there
	for i in int(6.0 / DT):
		e.tick(DT)
	assert_eq(int(e.shots_fired), 1, "no second orb while its first one is still alive")
	_fly(orb, 6.0)                                       # it lands / fades
	await wait_frames(1)
	_until(e, "telegraph", 6.0)
	assert_eq(e.state, "telegraph", "flares again once its orb is gone")


func test_dodge_roll_passes_the_orb() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _moth(d)
	_until(e, "recover", 5.0)
	var orb: Node3D = e.orb
	d.health.grant_iframes(3.0)
	_fly(orb)
	assert_almost(float(d.health.hp), 100.0, 0.001, "dodge i-frames avoid it")
	assert_true(String(orb.get("result")) in ["blocked", "expired"], "rolled through: no hit (%s)" % String(orb.get("result")))
	assert_eq(d.damaged_count, 0)
