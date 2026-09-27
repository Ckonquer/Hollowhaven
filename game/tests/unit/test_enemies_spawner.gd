extends "res://tests/test_case.gd"
## Enemy spawner: distance-based spawn/despawn, wave clear -> flags (persisted through a save
## round-trip), respawn cooldown, never-again spawners, safe zones.

const Spawner := preload("res://src/enemies/enemy_spawner.gd")
const Base := preload("res://src/enemies/enemy_base.gd")

var _nodes: Array = []
var _saved_area: Node = null


class SafeArea extends Node3D:
	var safe := true

	func is_safe_zone(_p: Vector3) -> bool:
		return safe


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and is_ancestor_of(e):
			e.queue_free()
	# Defeated Bramblings drop persistent world pickups (under the current scene when no area is
	# loaded): remove them so they don't leak into later suites (test_world_nodes counts pickups).
	for w in get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(w):
			w.queue_free()
	_nodes.clear()
	Game.area = _saved_area
	await wait_frames(2)


func _player(pos: Vector3) -> Node3D:
	var p := Node3D.new()
	add_child(p)
	p.global_position = pos
	_nodes.append(p)
	return p


func _spawner(params: Dictionary, p: Node3D) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	_nodes.append(holder)
	var s: Node3D = Spawner.new()
	s.setup(params)
	holder.add_child(s)
	s.global_position = Vector3.ZERO
	s.set_process(false)
	s.player_override = p
	return s


func _freeze(s: Node3D) -> void:
	for e in s.alive:
		if is_instance_valid(e):
			(e as Node).set_physics_process(false)


func _kill_all(s: Node3D) -> void:
	for e in s.alive.duplicate():
		if is_instance_valid(e):
			e.health.apply_damage(9999.0)


func test_spawns_near_despawns_far() -> void:
	var p := _player(Vector3(0, 0, 60))
	var s := _spawner({"enemy": "brambling", "count": 3, "radius": 5.0, "spawner_id": "t_near"}, p)
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "nothing while Krystal is 60 m away")
	p.global_position = Vector3(0, 0, 30)
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 3, "a full wave within 45 m")
	for e in s.alive:
		var d := Vector2((e as Node3D).global_position.x, (e as Node3D).global_position.z).length()
		assert_true(d <= 5.01, "inside the spawn radius")
		assert_eq((e as Node).get_parent(), s.get_parent(), "enemies live beside the spawner, not under it")
	s.update_spawner()
	assert_eq(s.alive.size(), 3, "keeps count, never more")
	p.global_position = Vector3(0, 0, 90)
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "despawned when far away")
	p.global_position = Vector3(0, 0, 20)
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 3, "they come back")


func test_partial_wave_remembered_across_despawn() -> void:
	var p := _player(Vector3(0, 0, 20))
	var s := _spawner({"enemy": "brambling", "count": 3, "radius": 4.0, "spawner_id": "t_partial"}, p)
	s.update_spawner()
	_freeze(s)
	(s.alive[0] as Node).health.apply_damage(9999.0)
	assert_eq(s.defeated_in_wave, 1)
	assert_eq(s.alive.size(), 2)
	p.global_position = Vector3(0, 0, 100)
	s.update_spawner()
	p.global_position = Vector3(0, 0, 20)
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 2, "only the survivors return")
	assert_false(s.is_cleared())


func test_clear_sets_flags_and_persists() -> void:
	var p := _player(Vector3(0, 0, 20))
	var s := _spawner({"enemy": "brambling", "count": 3, "radius": 4.0, "respawn_minutes": -1.0,
		"spawner_id": "ruin_test", "quest_flag_on_clear": "ruin_cleared_test"}, p)
	var cleared := [0]
	s.cleared.connect(func(_id: String) -> void: cleared[0] += 1)
	s.update_spawner()
	_freeze(s)
	(s.alive[0] as Node).health.apply_damage(9999.0)
	(s.alive[0] as Node).health.apply_damage(9999.0)
	assert_false(bool(GameState.get_flag("ruin_cleared_test")), "not cleared until the whole wave is down")
	_kill_all(s)
	assert_eq(cleared[0], 1, "cleared once")
	assert_true(bool(GameState.get_flag("spawner_cleared_ruin_test")), "persistent spawner flag")
	assert_true(bool(GameState.get_flag("ruin_cleared_test")), "quest flag")
	await wait_frames(2)
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "respawn_minutes < 0: never again")
	# Save round-trip, then a fresh spawner with the same id (area reload)
	var saved := GameState.to_dict()
	GameState.reset()
	assert_false(bool(GameState.get_flag("ruin_cleared_test")))
	GameState.from_dict(saved)
	var s2 := _spawner({"enemy": "brambling", "count": 3, "radius": 4.0, "respawn_minutes": -1.0,
		"spawner_id": "ruin_test", "quest_flag_on_clear": "ruin_cleared_test"}, p)
	assert_true(s2.is_cleared(), "cleared state survives save/load")
	s2.update_spawner()
	assert_eq(s2.alive.size(), 0, "still empty after reload")


func test_respawn_after_cooldown() -> void:
	var p := _player(Vector3(0, 0, 20))
	var s := _spawner({"enemy": "brambling", "count": 2, "radius": 3.0, "respawn_minutes": 120.0, "spawner_id": "t_cool"}, p)
	s.update_spawner()
	_freeze(s)
	_kill_all(s)
	assert_true(s.is_cleared())
	await wait_frames(2)
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "cooling down")
	GameState.total_minutes += 60.0
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "still cooling after an hour")
	GameState.total_minutes += 61.0
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 2, "a new wave after the cooldown")


func test_no_spawning_in_safe_zone() -> void:
	var p := _player(Vector3(0, 0, 10))
	var area := SafeArea.new()
	add_child(area)
	_nodes.append(area)
	Game.area = area
	var s := _spawner({"enemy": "brambling", "count": 2, "radius": 3.0, "spawner_id": "t_safe"}, p)
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "never spawns while Krystal is in a safe zone")
	area.safe = false
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 2)


func test_spawn_prefers_distance_from_player() -> void:
	var p := _player(Vector3(0, 0, 0))
	var s := _spawner({"enemy": "brambling", "count": 3, "radius": 10.0, "spawner_id": "t_far", "min_player_distance": 4.0}, p)
	s.update_spawner()
	_freeze(s)
	for e in s.alive:
		assert_true((e as Node3D).global_position.distance_to(p.global_position) >= 3.99, "not spawned on top of Krystal")
