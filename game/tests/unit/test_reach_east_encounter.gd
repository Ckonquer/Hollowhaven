extends "res://tests/test_case.gd"
## The Quarry Warden encounter scaffolding (src/world/reach/east/warden_arena.gd, quarry_pillar.gd,
## guarded_spawner.gd). The Warden enemy itself arrives in a later wave, so this proves the parts it will use:
##  * pillar API: crack() / reset() / is_intact(), contains(), a cracked pillar is a stump and re-knits by itself
##    (faster when every pillar is down), Settings timing_assist shortens the re-knit, high_visibility_cues ring
##  * retry: player death re-knits every pillar and sends a living Warden away (fresh next attempt); permanent
##    flags never reset
##  * guards: while EnemyFactory has no quarry_warden / bellcap_sentry script the spawners neither spawn nor
##    error; stepping into the empty arena clears it (completable), the debug hook clears it in debug builds,
##    and a real defeat (spawner clear / Events.boss_defeated / enemy_killed) sets hr_warden_defeated once
##  * the first clear shows TEXT["warden_clear"] exactly once (Events.notify "success", whichever path clears
##    first - the real Warden's boss_defeated reaches the arena before its spawner); a reload shows nothing
##  * the spawner hands the Warden its arena: centre, radius and the pillar nodes

const Q := preload("res://data/reach_east.gd")
const ArenaScript := preload("res://src/world/reach/east/warden_arena.gd")
const PillarScript := preload("res://src/world/reach/east/quarry_pillar.gd")
const SpawnerScript := preload("res://src/world/reach/east/guarded_spawner.gd")

var _holder: Node3D
var _toasts: Array = []


func before_each() -> void:
	fresh_state()
	_toasts.clear()
	if not Events.notify.is_connected(_on_notify):
		Events.notify.connect(_on_notify)
	SpawnerScript.availability_override = {}
	Settings.set_value("timing_assist", false)
	Settings.set_value("high_visibility_cues", false)
	_holder = Node3D.new()
	add_child(_holder)


func after_each() -> void:
	if Events.notify.is_connected(_on_notify):
		Events.notify.disconnect(_on_notify)
	SpawnerScript.availability_override = {}
	Settings.set_value("timing_assist", false)
	Settings.set_value("high_visibility_cues", false)
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	await wait_frames(2)


func _on_notify(text: String, kind: String) -> void:
	_toasts.append([text, kind])


## How many times the Warden's clear message was shown (as a "success" toast).
func _clear_toasts() -> int:
	return _toasts.filter(func(t: Array) -> bool: return String(t[0]) == String(Q.TEXT["warden_clear"]) and String(t[1]) == "success").size()


func _arena() -> Node3D:
	var a: Node3D = ArenaScript.new()
	a.setup({"radius": Q.ARENA_RADIUS, "pillars": [Vector3(4, 0, -5), Vector3(4, 0, 5), Vector3(-5, 0, 0)]})
	a.position = Vector3(50.0, 2.0, 50.0)
	_holder.add_child(a)
	return a


func test_pillar_api() -> void:
	var p: Node3D = PillarScript.new()
	p.setup({"id": "t", "regrow_seconds": 10.0})
	_holder.add_child(p)
	p.position = Vector3(3, 0, 3)
	assert_true(p.is_in_group("quarry_pillar"), "group")
	assert_true(bool(p.is_intact()), "intact")
	var body := p.get_node("Solid") as StaticBody3D
	assert_eq(body.collision_layer, 1, "solid on the world layer")
	var cs := body.get_child(0) as CollisionShape3D
	assert_almost(float((cs.shape as CylinderShape3D).height), Q.PILLAR_HEIGHT, 0.001, "full height")
	var got: Array = []
	p.cracked.connect(func(n: Node3D) -> void: got.append("cracked"))
	p.restored.connect(func(n: Node3D) -> void: got.append("restored"))
	assert_true(bool(p.crack()), "crack an intact pillar")
	assert_false(bool(p.is_intact()), "cracked")
	assert_false(bool(p.crack()), "a cracked pillar can't be cracked again")
	assert_almost(float((cs.shape as CylinderShape3D).height), Q.PILLAR_STUMP, 0.001, "a stump remains (still an obstacle)")
	assert_true(bool(p.contains(Vector3(3.5, 1, 3))), "contains()")
	assert_false(bool(p.contains(Vector3(6, 1, 3))), "not far away")
	assert_true((p.get_aim_point() as Vector3).y > 0.5, "aim point above ground")
	p._process(5.0)
	assert_false(bool(p.is_intact()), "still cracked halfway")
	p._process(5.5)
	assert_true(bool(p.is_intact()), "re-knits by itself (recoverable reset)")
	assert_eq(got, ["cracked", "restored"], "signals")
	p.crack()
	p.reset()
	assert_true(bool(p.is_intact()), "reset()")
	p.reset()
	assert_eq(got.size(), 4, "reset of an intact pillar is a no-op")


func test_high_visibility_ring() -> void:
	var p: Node3D = PillarScript.new()
	_holder.add_child(p)
	var ring := p.get_node("CueRing") as Node3D
	assert_false(ring.visible, "no ring by default")
	Settings.set_value("high_visibility_cues", true)
	Events.settings_changed.emit("high_visibility_cues")
	assert_true(ring.visible, "bold ring with high-visibility cues")
	p.crack()
	assert_false(ring.visible, "only on intact pillars")


func test_arena_retry_resets_pillars_and_keeps_progress() -> void:
	var a := _arena()
	assert_eq(a.pillars.size(), 3, "three pillars")
	assert_eq(int(a.intact_pillars()), 3, "all intact")
	a.pillars[0].crack()
	a.pillars[1].crack()
	assert_eq(int(a.intact_pillars()), 1, "two cracked")
	Events.player_died.emit()
	assert_eq(int(a.intact_pillars()), 3, "a retry re-knits every pillar")
	GameState.set_flag(Q.FLAG_WINCH, true)
	GameState.set_flag(Q.FLAG_WARDEN, true)
	Events.player_died.emit()
	assert_true(bool(GameState.get_flag(Q.FLAG_WINCH)) and bool(GameState.get_flag(Q.FLAG_WARDEN)), "permanent progress never resets")


func test_all_pillars_down_regrow_fast_and_timing_assist() -> void:
	var a := _arena()
	for pl in a.pillars:
		assert_almost(float(pl.regrow_seconds), Q.PILLAR_REGROW, 0.001, "normal re-knit time")
	for pl in a.pillars:
		pl.crack()
	for pl in a.pillars:
		assert_true(float(pl.regrow_left()) <= Q.PILLAR_REGROW_ALL + 0.001, "every pillar down: quick re-knit")
	Settings.set_value("timing_assist", true)
	Events.settings_changed.emit("timing_assist")
	for pl in a.pillars:
		assert_almost(float(pl.regrow_seconds), Q.PILLAR_REGROW_ASSIST, 0.001, "timing assist: shorter re-knit")
	var b := _arena()
	assert_almost(float(b.pillars[0].regrow_seconds), Q.PILLAR_REGROW_ASSIST, 0.001, "timing assist at build time too")


func test_missing_warden_never_softlocks() -> void:
	SpawnerScript.availability_override = {"quarry_warden": false}
	var a := _arena()
	var sp: Node3D = a.spawner
	assert_eq(String(sp.spawner_id), "hr_sp_quarry_warden", "spawner id")
	assert_eq(String(sp.enemy_id), "quarry_warden", "enemy id")
	assert_eq(String(sp.quest_flag_on_clear), Q.FLAG_WARDEN, "quest flag on clear")
	assert_true(float(sp.respawn_minutes) < 0.0, "the Warden never respawns")
	var kids := a.get_child_count()
	sp.update_spawner()
	assert_null(sp.spawn_one(), "nothing to spawn")
	assert_eq(a.get_child_count(), kids, "no enemy node created")
	a.check_player(a.position + Vector3(Q.ARENA_RADIUS + 2.0, 0, 0))
	assert_false(bool(GameState.get_flag(Q.FLAG_WARDEN)), "outside the arena: nothing")
	a.check_player(a.position + Vector3(0, 4.6, 2.0))
	assert_false(bool(GameState.get_flag(Q.FLAG_WARDEN)), "on the shelf above: nothing")
	a.check_player(a.position + Vector3(2.0, 0, 1.0))
	assert_true(bool(GameState.get_flag(Q.FLAG_WARDEN)), "stepping into the empty arena clears it")
	assert_true(bool(a.stand_in_used), "stand-in recorded")
	assert_true(bool(sp.is_cleared()), "the spawner counts as cleared")


func test_available_warden_is_not_auto_cleared_and_gets_its_arena() -> void:
	SpawnerScript.availability_override = {"quarry_warden": true}
	var a := _arena()
	await wait_frames(2)
	a.check_player(a.position + Vector3(1.0, 0, 1.0))
	assert_false(bool(GameState.get_flag(Q.FLAG_WARDEN)), "a real Warden must be beaten")
	var ex: Dictionary = a.spawner.extra_params
	assert_true((ex["arena_center"] as Vector3).is_equal_approx(a.global_position), "arena centre handed over")
	assert_almost(float(ex["arena_radius"]), Q.ARENA_RADIUS, 0.001, "arena radius")
	assert_eq((ex["pillars"] as Array).size(), 3, "pillar nodes handed over")
	assert_eq(ex["arena"], a, "the arena node")


## Integration with the enemy wave's real Quarry Warden (skipped while EnemyFactory has no working quarry_warden):
## the arena's spawner hands it this arena, its centre, radius and pillar nodes, its defeat clears the encounter
## exactly once through the normal paths (spawner clear + Events.boss_defeated + enemy_killed), the arena re-knits
## its pillars, and a cleared Warden never comes back.
func test_real_warden_gets_the_arena_and_its_defeat_clears_it() -> void:
	if not SpawnerScript.enemy_available(Q.WARDEN_ID):
		print("  (quarry_warden is not registered / does not compile yet - skipped)")
		return
	var a := _arena()
	await wait_frames(2)
	var sp: Node3D = a.spawner
	sp.extra_params["no_drops"] = true
	var dummy := Node3D.new()
	_holder.add_child(dummy)
	dummy.position = a.position + Vector3(0, 0, 30)
	sp.player_override = dummy
	sp.ignore_safe_zones = true
	var saved_mode := Game.mode
	Game.mode = "playing"
	sp.update_spawner()
	Game.mode = saved_mode
	assert_eq(sp.alive.size(), 1, "the real Warden spawned in its arena")
	if sp.alive.size() != 1:
		return
	var w: Node = sp.alive[0]
	assert_eq(w.get("arena"), a, "the Warden knows its arena")
	assert_true((w.get("arena_center") as Vector3).is_equal_approx(a.global_position), "arena centre")
	assert_almost(float(w.get("arena_radius")), Q.ARENA_RADIUS, 0.001, "arena radius from the quarry, not the data default")
	assert_eq((w.get("pillars") as Array).size(), a.pillars.size(), "the pillar nodes")
	var cleared: Array = []
	a.encounter_cleared.connect(func() -> void: cleared.append(1))
	a.pillars[0].crack()
	(w.get("health") as Node).call("apply_damage", 1.0e6)
	await wait_frames(3)
	assert_true(bool(GameState.get_flag(Q.FLAG_WARDEN)), "hr_warden_defeated")
	assert_true(bool(sp.is_cleared()), "the spawner is cleared")
	assert_eq(cleared.size(), 1, "cleared exactly once")
	assert_eq(_clear_toasts(), 1, "a real defeat shows the Warden's clear message exactly once")
	assert_eq(int(a.intact_pillars()), a.pillars.size(), "the pillars re-knit after the fight")
	Game.mode = "playing"
	sp.update_spawner()
	Game.mode = saved_mode
	assert_eq(sp.alive.size(), 0, "a defeated Warden never respawns")
	await wait_frames(30)


## hr_warden_defeated is the permanent progress: a save that has it (from any path) never meets the Warden again,
## even when the spawner's own clear flag is missing.
func test_permanent_flag_alone_keeps_the_warden_away() -> void:
	SpawnerScript.availability_override = {"quarry_warden": true}
	var a := _arena()
	var sp: Node3D = a.spawner
	assert_eq(String(sp.block_flag), Q.FLAG_WARDEN, "the Warden spawner is blocked by hr_warden_defeated")
	GameState.set_flag(Q.FLAG_WARDEN, true)
	assert_false(bool(sp.is_cleared()), "the spawner's own clear flag is missing in this save")
	var dummy := Node3D.new()
	_holder.add_child(dummy)
	dummy.position = a.position + Vector3(0, 0, 5)
	sp.player_override = dummy
	sp.ignore_safe_zones = true
	var saved_mode := Game.mode
	Game.mode = "playing"
	sp.update_spawner()
	Game.mode = saved_mode
	assert_eq(sp.alive.size(), 0, "no Warden after its defeat")
	assert_null(sp.spawn_one(dummy), "spawn_one refuses too")


func test_defeat_sets_the_flag_once() -> void:
	var a := _arena()
	var cleared: Array = []
	a.encounter_cleared.connect(func() -> void: cleared.append(1))
	Events.boss_defeated.emit("count_velour")
	assert_false(bool(GameState.get_flag(Q.FLAG_WARDEN)), "another boss does nothing")
	a.pillars[2].crack()
	Events.boss_defeated.emit(Q.WARDEN_ID)
	assert_true(bool(GameState.get_flag(Q.FLAG_WARDEN)), "hr_warden_defeated")
	assert_eq(int(a.intact_pillars()), 3, "the arena re-knits after the fight")
	Events.enemy_killed.emit(Q.WARDEN_ID, a.position)
	a.spawner.cleared.emit("hr_sp_quarry_warden")
	a.spawner._on_wave_cleared()          # the spawner's own clear after the arena's (a real defeat's order)
	assert_eq(cleared.size(), 1, "announced once")
	assert_eq(_clear_toasts(), 1, "the clear message once, although the spawner cleared after the arena")


## Order-independent: a spawner-first clear shows its clear_message and the arena stays quiet; a save that already
## has the Warden cleared (a reload) never shows it again, whatever event arrives.
func test_clear_message_once_on_any_path_and_never_after_a_reload() -> void:
	var a := _arena()
	a.spawner._on_wave_cleared()
	assert_eq(_clear_toasts(), 1, "spawner first: its clear_message, once")
	Events.boss_defeated.emit(Q.WARDEN_ID)
	Events.enemy_killed.emit(Q.WARDEN_ID, a.position)
	assert_eq(_clear_toasts(), 1, "the arena does not repeat it")
	a.queue_free()
	await wait_frames(1)
	_toasts.clear()
	var b := _arena()            # a reload: the flags are in the save
	assert_true(bool(b.is_cleared()), "cleared on load")
	Events.boss_defeated.emit(Q.WARDEN_ID)
	Events.enemy_killed.emit(Q.WARDEN_ID, b.position)
	b.spawner._on_wave_cleared()
	b.check_player(b.position)
	assert_eq(_clear_toasts(), 0, "nothing on a reload")
	assert_eq(_toasts.size(), 0, "no toast at all")


func test_spawner_clear_and_debug_hook() -> void:
	var a := _arena()
	a.spawner._on_wave_cleared()
	assert_true(bool(GameState.get_flag(Q.FLAG_WARDEN)), "a spawner clear sets hr_warden_defeated")
	fresh_state()
	var b := _arena()
	assert_eq(bool(b.debug_clear_encounter()), Debug.is_cheat_allowed(), "debug hook only in debug builds")
	if Debug.is_cheat_allowed():
		assert_true(bool(GameState.get_flag(Q.FLAG_WARDEN)), "debug clear sets the flag")
		assert_false(bool(b.debug_clear_encounter()), "only once")


func test_bellcap_pocket_spawner_is_guarded() -> void:
	SpawnerScript.availability_override = {"bellcap_sentry": false}
	var sp: Node3D = SpawnerScript.new()
	var sd: Dictionary = Q.SPAWNERS["hr_sp_bellcaps"]
	sp.setup({"enemy": sd["enemy"], "count": sd["count"], "radius": sd["radius"], "respawn_minutes": sd["respawn_minutes"], "spawner_id": "hr_sp_bellcaps"})
	_holder.add_child(sp)
	sp.player_override = _holder
	sp.ignore_safe_zones = true
	var saved_mode := Game.mode
	Game.mode = "playing"
	sp.update_spawner()
	Game.mode = saved_mode
	assert_eq(sp.alive.size(), 0, "nothing spawned while the enemy script is missing")
	assert_true(float(sp.respawn_minutes) > 0.0, "a renewable pocket")
	assert_eq(String(sp.quest_flag_on_clear), "", "no story flag")


func test_guarded_spawner_spawns_known_enemies_with_the_extra_params() -> void:
	var sp: Node3D = SpawnerScript.new()
	# "extra" is merged over the spawner's own params: a wander_radius in it must reach the enemy's setup
	sp.setup({"enemy": "brambling", "count": 1, "radius": 0.5, "respawn_minutes": -1.0, "spawner_id": "hr_sp_test_guard",
		"min_player_distance": 0.0, "wander_radius": 3.0, "extra": {"arena_radius": 9.0, "wander_radius": 1.25}})
	_holder.add_child(sp)
	sp.position = Vector3(200, 0, 200)
	var dummy := Node3D.new()
	_holder.add_child(dummy)
	dummy.position = Vector3(205, 0, 200)
	sp.player_override = dummy
	sp.ignore_safe_zones = true
	assert_true(bool(sp.is_enemy_available()), "brambling has a script")
	var saved_mode := Game.mode
	Game.mode = "playing"
	sp.update_spawner()
	Game.mode = saved_mode
	assert_eq(sp.alive.size(), 1, "one enemy spawned through the guarded path")
	if sp.alive.size() == 1:
		var e: Node = sp.alive[0]
		assert_almost(float(e.get("wander_radius")), 1.25, 0.001, "the extra params reached the enemy's setup")
		assert_eq(e.get("spawner"), sp, "the enemy knows its spawner (defeat -> clear)")
	sp.despawn_all()
	await wait_frames(2)
