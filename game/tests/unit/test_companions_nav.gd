extends "res://tests/unit/test_companions_fixture.gd"
## Obstacle-aware approach (companion_nav.gd, MP §6.1 "no pet endlessly running into a wall"): the pure grid
## A* (around walls, never cutting a corner, bounded), and a follower that walks around a wall to Krystal in a
## test room without being teleported; the boss-room rule for recoveries.


## The boss-room rule reads Game.boss_active(): an encounter left over from an earlier suite (a boss freed
## mid-fight) would block every recovery here, so each test starts and ends without one.
func before_each() -> void:
	Game._bosses.clear()
	await super()


func after_each() -> void:
	Game._bosses.clear()
	await super()


## Grid helper: `blocked` holds Vector2i cells that are walls; floors at height 0.
func _walk_fn(blocked: Dictionary, size: int) -> Callable:
	return func(i: int, j: int) -> Variant:
		if i < 0 or j < 0 or i >= size or j >= size or blocked.has(Vector2i(i, j)):
			return null
		return Vector3(float(i), 0.0, float(j))


func _edge_fn() -> Callable:
	return func(_a: Vector2i, _b: Vector2i, fa: Vector3, fb: Vector3) -> bool:
		return absf(fa.y - fb.y) <= Nav.MAX_STEP


func test_grid_astar_goes_around_a_wall_without_cutting_corners() -> void:
	var size := 12
	var blocked := {}
	for j in 10:
		blocked[Vector2i(6, j)] = true           # a wall with a gap at j = 10, 11
	var walk := _walk_fn(blocked, size)
	var path: Array = Nav.astar(Vector2i(2, 5), Vector2i(10, 5), size, walk, _edge_fn(), 900)
	assert_false(path.is_empty(), "a way around exists")
	assert_eq(path[path.size() - 1], Vector2i(10, 5), "it ends at the goal")
	var prev := Vector2i(2, 5)
	var through_gap := false
	for c in path:
		var cc: Vector2i = c
		assert_false(blocked.has(cc), "never through the wall")
		var d := cc - prev
		assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "neighbouring steps")
		if d.x != 0 and d.y != 0:
			assert_true(walk.call(prev.x + d.x, prev.y) is Vector3 and walk.call(prev.x, prev.y + d.y) is Vector3, "no corner cutting at %s" % str(cc))
		if cc.x == 6:
			through_gap = cc.y >= 10
		prev = cc
	assert_true(through_gap, "through the gap")
	# Fully walled off: nothing (no partial path that leads nowhere).
	blocked[Vector2i(6, 10)] = true
	blocked[Vector2i(6, 11)] = true
	assert_true(Nav.astar(Vector2i(2, 5), Vector2i(10, 5), size, _walk_fn(blocked, size), _edge_fn(), 900).is_empty())


func test_grid_astar_respects_step_height_and_budget() -> void:
	var size := 10
	# A 1.2 m ledge across the middle is not a step the pet can take.
	var walk := func(i: int, j: int) -> Variant:
		if i < 0 or j < 0 or i >= size or j >= size:
			return null
		return Vector3(float(i), 1.2 if i >= 5 else 0.0, float(j))
	assert_true(Nav.astar(Vector2i(1, 5), Vector2i(8, 5), size, walk, _edge_fn(), 900).is_empty(), "no path up a 1.2 m ledge")
	# A tiny expansion budget returns a partial path toward the goal (or nothing), never an error.
	var open := _walk_fn({}, 40)
	var part: Array = Nav.astar(Vector2i(1, 1), Vector2i(38, 38), 40, open, _edge_fn(), 12)
	assert_true(part.size() <= 13, "bounded by the budget (%d cells)" % part.size())


func test_follower_walks_around_a_wall_to_krystal() -> void:
	player.global_position = Vector3(0, 0.05, 4)
	_wall(Vector3(0, 0, 0), 10.0)                 # x -5..5 at z = 0, 3 m high
	var m := _follower("mochi", Vector3(0.5, 0.05, -3.0))
	await wait_physics(2)
	var last: Vector3 = m.global_position
	var max_step := 0.0
	var reached := false
	for i in 60 * 9:
		await wait_physics(1)
		max_step = maxf(max_step, m.global_position.distance_to(last))
		last = m.global_position
		if m.global_position.distance_to(player.global_position) < 3.2 and m.global_position.z > 0.5:
			reached = true
			break
	assert_true(reached, "reached Krystal on the other side of the wall (now %.1f m away at %s)" % [m.global_position.distance_to(player.global_position), str(m.global_position)])
	assert_eq(int(m.recoveries), 0, "by walking, not by a teleport")
	assert_true(max_step < 0.5, "no jump in position (largest step %.2f m)" % max_step)
	assert_true(int(m.nav.searches) >= 1, "the local waypoint search planned the detour")
	assert_true(int(m.nav.get("_queries")) <= Nav.PROBE_BUDGET + 30, "within its physics-query budget (%d)" % int(m.nav.get("_queries")))


func test_direct_line_needs_no_search() -> void:
	var m := _follower("lumi", Vector3(0, 0.05, -2.0))
	for i in 60:
		await wait_physics(1)
	assert_eq(int(m.nav.searches), 0, "open ground: straight there, no path search")
	assert_true(m.global_position.distance_to(player.global_position) < 4.0)


## Bounded cost: Krystal walled in completely (unreachable goal) makes the search spend its whole budget; it
## stays within its physics-query and time budgets, and a failed search backs off instead of repeating.
func test_unreachable_goal_search_is_bounded_and_backs_off() -> void:
	player.global_position = Vector3(0, 0.05, 6)
	_wall(Vector3(0, 0, 3.5), 6.0)
	_wall(Vector3(0, 0, 8.5), 6.0)
	_wall(Vector3(-3.0, 0, 6.0), 5.4, false)
	_wall(Vector3(3.0, 0, 6.0), 5.4, false)
	var m := _follower("lumi", Vector3(0.5, 0.05, -4.0))
	await wait_physics(2)
	var worst := 0
	for i in 60 * 3:
		await wait_physics(1)
		worst = maxi(worst, int(m.nav.last_search_usec))
	var searches := int(m.nav.searches)
	print("    nav: %d searches in 3 s, worst %.2f ms, %d queries" % [searches, float(worst) / 1000.0, int(m.nav.get("_queries"))])
	assert_true(searches >= 1, "it tried")
	# One (partial) search toward the nearest wall, then a failed one backs off for SEARCH_FAIL_COOLDOWN
	# instead of repeating every SEARCH_COOLDOWN (that would be 4 in 3 s).
	assert_true(searches <= 3, "a failed search backs off (%d searches in 3 s)" % searches)
	assert_true(int(m.nav.get("_queries")) <= Nav.PROBE_BUDGET + 30, "physics-query budget (%d)" % int(m.nav.get("_queries")))
	assert_true(worst < Nav.SEARCH_USEC_BUDGET + 5000, "time budget per search (%.2f ms)" % (float(worst) / 1000.0))
	assert_true(m.global_position.distance_to(Vector3(0, 0.05, 6)) > 2.0, "it never walked through the walls")


## A pet that falls out of the world while Krystal fights a boss far away returns to the last floor it stood
## on (safe), never next to her in the closed arena.
func test_a_fall_mid_boss_fight_returns_to_its_last_floor() -> void:
	var m := _follower("pebble", Vector3(0, 0.05, 2.0))
	for i in 45:
		await wait_physics(1)
	var safe: Vector3 = m.get("_safe_floor")
	assert_true(safe != Vector3.INF, "a safe floor spot is remembered while following")
	Game._bosses["test_boss"] = true
	player.global_position = Vector3(30, 0.05, 0)
	m.global_position = Vector3(0, -45.0, 0)
	await wait_physics(3)
	Game._bosses.erase("test_boss")
	assert_eq(int(m.recoveries), 0, "no teleport to Krystal")
	assert_true(m.global_position.y > -1.0, "back on its floor (y %.1f)" % m.global_position.y)
	assert_true(Vector2(m.global_position.x - safe.x, m.global_position.z - safe.z).length() < 1.5, "where it last stood")
	assert_true(m.global_position.distance_to(player.global_position) > 20.0, "not in the arena")


func test_no_teleport_into_a_boss_fight_from_far_away() -> void:
	var m := _follower("pebble", Vector3(0, 0.05, 0))
	Game._bosses["test_boss"] = true
	player.global_position = Vector3(30, 0.05, 0)
	await wait_physics(3)
	var d: float = m.global_position.distance_to(player.global_position)
	Game._bosses.erase("test_boss")
	assert_eq(int(m.recoveries), 0, "no pop into the boss room")
	assert_true(d > 20.0, "it is still out there walking (%.1f m)" % d)
	await wait_physics(3)
	assert_true(m.global_position.distance_to(player.global_position) < 4.0, "the usual recovery once the fight is over")
