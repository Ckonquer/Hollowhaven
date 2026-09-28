extends "res://tests/test_case.gd"
## CH2-006 (QA bot S3): the Looking-Glass Hall's Velvet Wing kept "chasing" (threatening) Krystal through the
## hall / ballroom wall for 526 s: _chase_valid() only checked the leash and 2.2x the aggro distance, never line of
## sight, so Game._threat_near() refused every save / Lantern Road trip within 20 m for as long as she stood there.
## Fix (enemy_base): a hunt that has gone LOST_SIGHT_GIVE_UP (5 s) without seeing her ends in "return" (no longer
## threatening); a sighting or a hit resets the clock, so a short break round a corner never drops it; elites and
## bosses (arena fights with cover) never give up this way.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_mode: String = ""
var _saved_area_id: String = ""


class Dummy extends CharacterBody3D:
	var health: Node

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_mode = Game.mode
	_saved_area_id = Game.area_id
	Game.area = null
	Game.player = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	Game.area = _saved_area
	Game.player = _saved_player
	Game.mode = _saved_mode
	Game.area_id = _saved_area_id
	await wait_frames(2)


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	_nodes.append(d)
	return d


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
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


func _enemy(id: String, target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create(id, {"home": pos, "no_drops": true})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	if "ward_light_override" in e:
		e.ward_light_override = 0.0
	_nodes.append(e)
	return e


## Ticks (no movement: the enemy stays on its side of the wall) and keeps it from starting an attack, so the test
## watches the hunt itself. Returns the seconds ticked.
func _tick(e: Node, seconds: float) -> float:
	var t := 0.0
	while t < seconds:
		e._cooldown = 100.0
		e.tick(DT)
		t += DT
	return t


func _until_chase(e: Node, max_t: float = 4.0) -> void:
	var t := 0.0
	while e.state != "chase" and t < max_t:
		e._cooldown = 100.0
		e.tick(DT)
		t += DT


## Save / travel gate as the pause menu sees it (the surface: no safe-zone rule, only threats and bosses).
func _save_ok(d: Node3D) -> bool:
	Game.player = d
	Game.mode = "playing"
	Game.area_id = "surface"
	var ok := bool(Game.can_manual_save()["ok"])
	Game.mode = _saved_mode
	Game.area_id = _saved_area_id
	Game.player = null
	return ok


func test_velvet_wing_behind_a_wall_gives_up_and_saving_is_free_again() -> void:
	var d := _dummy(Vector3(0, 0, -3.5))
	var e := _enemy("velvet_wing", d)
	await wait_physics(2)
	_until_chase(e)
	assert_eq(e.state, "chase", "it notices her in the open")
	assert_true(e.is_threatening())
	assert_false(_save_ok(d), "while it hunts her in sight, saving is refused (unchanged)")
	# She slips round the doorway: a tall wall now stands between them, 3.5 m apart (the S3 spot).
	_wall(Vector3(0, 2.0, -1.75), Vector3(10, 6, 0.4))
	await wait_physics(2)
	_tick(e, 3.0)
	assert_true(e.is_threatening(), "a short break of sight never drops the hunt (it may follow her round a corner)")
	_tick(e, Base.LOST_SIGHT_GIVE_UP - 3.0 + 0.5)
	assert_false(e.is_threatening(), "out of sight for %.1f s: no longer hunting (state %s)" % [Base.LOST_SIGHT_GIVE_UP + 0.5, e.state])
	assert_true(e.state in ["return", "idle"], "it heads home (state %s)" % e.state)
	assert_true(_save_ok(d), "nothing hunts her any more: the pause menu may save again")
	_tick(e, 20.0)
	assert_false(e.is_threatening(), "and it never re-aggroes through the wall (state %s)" % e.state)


func test_brambling_forgets_her_behind_a_wall_but_not_round_a_corner() -> void:
	var d := _dummy(Vector3(0, 0, -4.0))
	var e := _enemy("brambling", d)
	await wait_physics(2)
	_until_chase(e)
	assert_eq(e.state, "chase")
	var wall := _wall(Vector3(0, 1.5, -2.0), Vector3(10, 4, 0.4))
	await wait_physics(2)
	_tick(e, 3.0)
	assert_eq(e.state, "chase", "3 s out of sight: still hunting")
	assert_true(float(e.unseen_time()) > 2.5, "the lost-sight clock runs while it cannot see her")
	# She steps back into view: the clock starts again.
	wall.queue_free()
	await wait_physics(2)
	_tick(e, 0.5)
	assert_almost(float(e.unseen_time()), 0.0, 0.001, "seeing her again resets the clock")
	var wall2 := _wall(Vector3(0, 1.5, -2.0), Vector3(10, 4, 0.4))
	await wait_physics(2)
	_tick(e, 3.0)
	assert_eq(e.state, "chase", "a second short break does not add up with the first")
	_tick(e, Base.LOST_SIGHT_GIVE_UP)
	assert_false(e.is_threatening(), "but a long one ends the hunt (state %s)" % e.state)
	wall2.queue_free()


func test_a_hit_from_out_of_sight_restarts_the_clock() -> void:
	var d := _dummy(Vector3(0, 0, -4.0))
	var e := _enemy("brambling", d)
	await wait_physics(2)
	_until_chase(e)
	_wall(Vector3(0, 1.5, -2.0), Vector3(10, 4, 0.4))
	await wait_physics(2)
	_tick(e, 4.0)
	e.health.apply_damage(1.0, d, Vector3.FORWARD)
	assert_almost(float(e.unseen_time()), 0.0, 0.001, "her hit gives her away")
	_tick(e, 3.0)
	assert_true(e.is_threatening(), "so it keeps hunting a while longer (state %s)" % e.state)


func test_elites_and_bosses_never_give_up_on_sight() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	for id in ["knotted_elder", "quarry_warden"]:
		var e := _enemy(id, d, Vector3(40, 0, 0))
		assert_eq(float(e.lose_sight_seconds()), INF, id + ": arena fights keep their own leash (pillars are cover)")
	for id in ["brambling", "velvet_wing", "hollow_drudge", "patchwalker", "lantern_moth"]:
		var e := _enemy(id, d, Vector3(-40, 0, 0))
		assert_almost(float(e.lose_sight_seconds()), Base.LOST_SIGHT_GIVE_UP, 0.001, id + ": ordinary enemies give up")
