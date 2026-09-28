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


# --- Integration R81 / R82 -------------------------------------------------------------------------------

## setup "enemy_params" reach every spawned enemy through Factory.spawn; the spawner's own keys win.
func test_enemy_params_reach_the_enemy_and_spawner_keys_win() -> void:
	var p := _player(Vector3(0, 0, 20))
	var s := _spawner({"enemy": "brambling", "count": 2, "radius": 3.0, "spawner_id": "t_params", "wander_radius": 4.0,
		"enemy_params": {"damage_scale": 0.5, "home": Vector3(99, 0, 99), "wander_radius": 77.0, "defeat_flag": "t_params_flag"}}, p)
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 2)
	for e in s.alive:
		assert_almost(float(e.damage_scale), 0.5, 0.001, "an extra param reaches the enemy")
		assert_eq(String(e.defeat_flag), "t_params_flag")
		assert_true((e.home as Vector3).distance_to(Vector3(99, 0, 99)) > 50.0, "home comes from the spawner, not enemy_params")
		assert_almost(float(e.wander_radius), 4.0, 0.001, "wander_radius comes from the spawner")
		assert_eq(e.spawner, s, "spawner key set")


## The Knotted Elder's arena (Bramblewatch passes it through enemy_params).
func test_enemy_params_set_an_elite_arena() -> void:
	var p := _player(Vector3(0, 0, 20))
	var s := _spawner({"enemy": "knotted_elder", "count": 1, "radius": 1.0, "spawner_id": "t_elder_params",
		"enemy_params": {"arena_center": Vector3(3, 0, 4), "arena_radius": 10.0, "reward_id": ""}}, p)
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 1)
	if s.alive.is_empty():
		return
	var e: Node = s.alive[0]
	assert_true((e.arena_center as Vector3).is_equal_approx(Vector3(3, 0, 4)), "arena centre from enemy_params")
	assert_almost(float(e.arena_radius), 10.0, 0.001, "arena radius from enemy_params (data says 12)")


func _flat_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
	_nodes.append(body)


func _camera(pos: Vector3, look: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	_nodes.append(cam)
	return cam


## MP 7: repeatable groups never pop in within view. Points inside the camera frustum with a clear line of
## sight are rejected when a spawn point is chosen; with none hidden the wave waits (no spawn, no error).
func test_out_of_view_never_pops_in_within_view() -> void:
	_flat_floor()
	var p := _player(Vector3(0, 0, 16))
	var cam := _camera(Vector3(0, 2.5, 16), Vector3(0, 0.5, 0))
	await wait_physics(2)
	var s := _spawner({"enemy": "brambling", "count": 2, "radius": 3.0, "spawner_id": "t_view", "out_of_view": true}, p)
	s.camera_override = cam
	assert_true(bool(s.in_view(Vector3.ZERO)), "the spawner's ground is in plain view")
	assert_false(bool(s.in_view(Vector3(0, 0, 30))), "behind the camera is not in view")
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "nothing pops in where Krystal is looking")
	assert_true(int(s.view_waits) > 0, "the wave waits")
	s.update_spawner()
	assert_eq(s.alive.size(), 0, "still waiting on the next update")
	# A wall (world layer) between the camera and the spawn area hides it: the wave appears.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 8, 0.6)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(0, 3.0, 8.0)
	_nodes.append(wall)
	await wait_physics(2)
	assert_false(bool(s.in_view(Vector3.ZERO)), "hidden behind the wall")
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 2, "the whole wave appears once it is out of sight")


func test_out_of_view_turned_away_spawns_and_legacy_default_ignores_the_camera() -> void:
	_flat_floor()
	var p := _player(Vector3(0, 0, 16))
	var cam := _camera(Vector3(0, 2.5, 16), Vector3(0, 0.5, 40))       # looking away from the spawner
	await wait_physics(2)
	var s := _spawner({"enemy": "brambling", "count": 2, "radius": 3.0, "spawner_id": "t_view_away", "out_of_view": true}, p)
	s.camera_override = cam
	s.update_spawner()
	_freeze(s)
	assert_eq(s.alive.size(), 2, "the camera looks the other way: spawns at once")
	for e in s.alive:
		assert_false(bool(s.in_view((e as Node3D).global_position)), "spawned out of view")
	# Default (legacy) spawners never look at the camera.
	cam.global_position = Vector3(20, 2.5, 16)
	cam.look_at(Vector3(20, 0.5, 0), Vector3.UP)
	var holder := Node3D.new()
	add_child(holder)
	_nodes.append(holder)
	var legacy: Node3D = Spawner.new()
	legacy.setup({"enemy": "brambling", "count": 2, "radius": 3.0, "spawner_id": "t_view_legacy"})
	holder.add_child(legacy)
	legacy.global_position = Vector3(20, 0, 0)
	legacy.set_process(false)
	legacy.player_override = p
	legacy.camera_override = cam
	assert_false(bool(legacy.out_of_view), "off by default")
	legacy.update_spawner()
	_freeze(legacy)
	assert_eq(legacy.alive.size(), 2, "a default spawner spawns in view exactly as before")
