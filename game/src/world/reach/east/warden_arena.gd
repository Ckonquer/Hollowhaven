extends Node3D
## The Quarry Warden's arena on Ashbell's L2 bench (MP §12 "Ashbell elite - Quarry Warden"): an open, flat,
## readable floor ringed by pale marker stones, fixed mineral pillars (quarry_pillar.gd) and the Warden's
## spawner hr_sp_quarry_warden (enemy quarry_warden, never respawns, quest_flag_on_clear hr_warden_defeated).
## Retry rules: pillars and combat state reset (player death -> the living Warden is despawned so it returns
## fresh, every pillar re-knits); permanent progress (hr_warden_defeated, the winch) never resets.
## The Warden script arrives in a later wave. Until EnemyFactory knows "quarry_warden" the encounter stays
## completable: when Krystal steps into the empty arena the stand-in clears it (warning in the log), and debug /
## test builds can call debug_clear_encounter().
##   setup({"center": Vector3, "radius": float, "pillars": [Vector3 local offsets], "floor_y": float})
##   is_cleared(), pillars (Array of nodes), spawner, intact_pillars() -> int, reset_combat(),
##   check_player(pos) (the throttled poll; tests call it directly), debug_clear_encounter() -> bool
##   player_override (tests)

signal encounter_cleared

const Q := preload("res://data/reach_east.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const PillarScript := preload("res://src/world/reach/east/quarry_pillar.gd")
const SpawnerScript := preload("res://src/world/reach/east/guarded_spawner.gd")

const POLL := 0.5

var radius: float = Q.ARENA_RADIUS
var pillar_offsets: Array = []
var pillars: Array = []
var spawner: Node3D = null
var stand_in_used := false
var player_override: Node3D = null

var _poll_t := 0.0


func setup(p: Dictionary) -> void:
	radius = float(p.get("radius", radius))
	pillar_offsets = (p.get("pillars", []) as Array).duplicate()


func _ready() -> void:
	name = "WardenArena"
	add_to_group("quarry_warden_arena")
	_build_ring()
	var i := 0
	for off in pillar_offsets:
		var pl: Node3D = PillarScript.new()
		pl.setup({"id": "hr_pillar_%d" % i, "variant": i, "regrow_seconds": _regrow_time()})
		add_child(pl)
		pl.position = off
		pl.cracked.connect(_on_pillar_cracked)
		pillars.append(pl)
		i += 1
	var sd: Dictionary = Q.SPAWNERS[Q.WARDEN_SPAWNER]
	spawner = SpawnerScript.new()
	spawner.name = Q.WARDEN_SPAWNER
	spawner.setup({"enemy": sd["enemy"], "count": sd["count"], "radius": sd["radius"], "respawn_minutes": sd["respawn_minutes"],
		"spawner_id": Q.WARDEN_SPAWNER, "quest_flag_on_clear": sd["quest_flag_on_clear"], "clear_message": Q.TEXT["warden_clear"],
		"block_flag": Q.FLAG_WARDEN,
		"wander_radius": float(sd.get("wander", 3.0)), "min_player_distance": 0.0,
		"extra": {"arena": self, "arena_center": Vector3.ZERO, "arena_radius": radius, "pillars": pillars}})
	add_child(spawner)
	spawner.cleared.connect(_on_spawner_cleared)
	# The spawner extra params need world positions once we are placed.
	_refresh_extra.call_deferred()
	if not Events.boss_defeated.is_connected(_on_boss_defeated):
		Events.boss_defeated.connect(_on_boss_defeated)
		Events.enemy_killed.connect(_on_enemy_killed)
		Events.player_died.connect(reset_combat)
		Events.settings_changed.connect(_on_settings_changed)
	set_process(not is_cleared())


func _refresh_extra() -> void:
	if spawner == null or not is_inside_tree():
		return
	spawner.extra_params["arena_center"] = global_position
	spawner.extra_params["pillars"] = pillars


func is_cleared() -> bool:
	return bool(GameState.get_flag(Q.FLAG_WARDEN))


func intact_pillars() -> int:
	var n := 0
	for pl in pillars:
		if is_instance_valid(pl) and pl.is_intact():
			n += 1
	return n


## Retry: every pillar re-knits and a living Warden leaves, so the next attempt starts fresh.
## Permanent flags (hr_warden_defeated, the winch) are never touched.
func reset_combat() -> void:
	for pl in pillars:
		if is_instance_valid(pl):
			pl.reset()
	if spawner != null and is_instance_valid(spawner) and not is_cleared():
		spawner.despawn_all()
		spawner.defeated_in_wave = 0


func _process(delta: float) -> void:
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL
	var p := _player()
	if p != null:
		check_player(p.global_position)


## Throttled arena logic: the missing-Warden stand-in (see header).
func check_player(pos: Vector3) -> void:
	if is_cleared() or spawner == null:
		return
	var c := global_position if is_inside_tree() else position
	if Vector2(pos.x - c.x, pos.z - c.z).length() > radius or absf(pos.y - c.y) > 3.0:
		return
	if not spawner.is_enemy_available():
		push_warning("Ashbell Quarry: enemy 'quarry_warden' has no script yet; the empty arena clears itself so the quarry stays completable")
		stand_in_used = true
		_clear_encounter()


## Debug / test hook (never in a release build): marks the Warden encounter cleared like a real defeat.
func debug_clear_encounter() -> bool:
	if not Debug.is_cheat_allowed():
		return false
	if is_cleared():
		return false
	_clear_encounter()
	return true


func _clear_encounter() -> void:
	var first := not is_cleared()
	GameState.set_flag(Q.FLAG_WARDEN, true)
	if spawner != null and is_instance_valid(spawner):
		GameState.set_flag(spawner.cleared_flag(), true)
	for pl in pillars:
		if is_instance_valid(pl):
			pl.reset()
	set_process(false)
	if first:
		Events.caption.emit(Q.TEXT["warden_quiet"])
		if GameState.has_method("request_quest_eval"):
			GameState.request_quest_eval()
		encounter_cleared.emit()


func _on_spawner_cleared(_id: String) -> void:
	_clear_encounter()


func _on_boss_defeated(boss_id: String) -> void:
	if boss_id == Q.WARDEN_ID:
		_clear_encounter()


func _on_enemy_killed(enemy_id: String, pos: Vector3) -> void:
	if enemy_id != Q.WARDEN_ID:
		return
	var c := global_position if is_inside_tree() else position
	if Vector2(pos.x - c.x, pos.z - c.z).length() <= radius + 20.0:
		_clear_encounter()


func _on_pillar_cracked(_pl: Node3D) -> void:
	# Every pillar down with the Warden still up: they re-knit quickly (the arena can never become unwinnable).
	if intact_pillars() == 0 and not is_cleared():
		for pl in pillars:
			if is_instance_valid(pl):
				pl.hurry_regrow(Q.PILLAR_REGROW_ALL)


func _regrow_time() -> float:
	return Q.PILLAR_REGROW_ASSIST if bool(Settings.get_value("timing_assist")) else Q.PILLAR_REGROW


func _on_settings_changed(key: String) -> void:
	if key != "timing_assist":
		return
	for pl in pillars:
		if is_instance_valid(pl):
			pl.regrow_seconds = _regrow_time()


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


## Pale marker stones around the open floor (readable arena edge) - one merged mesh.
func _build_ring() -> void:
	var m := NV.Merger.new()
	var n := 22
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := Vector3(cos(a) * radius, 0.02, sin(a) * radius)
		QV.add_boulder(m, p, 0.32 + 0.06 * float(i % 3), i, a, Color("d9c7b8"), 0.45)
	var mi := NV._mi(m.commit(), QV.stone_material(), "ArenaRing")
	NV.set_visibility_range(mi, 110.0, false)
	add_child(mi)
