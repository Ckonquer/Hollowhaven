extends "res://src/enemies/enemy_spawner.gd"
## An EnemySpawner (src/enemies/enemy_spawner.gd) that waits quietly while its enemy id has no script yet:
## the Chapter Two enemies (bellcap_sentry, quarry_warden) arrive in a later wave, so until EnemyFactory knows
## the id this spawner neither spawns nor warns every tick. It wakes up by itself once the script exists.
## Extra setup keys:
##   "extra": Dictionary merged into every spawned enemy's setup params (the Warden gets its arena:
##            {"arena": node, "arena_center": Vector3, "arena_radius": float, "pillars": [nodes]}).
##   "block_flag": String - while this GameState flag is set, no new enemy is spawned (the Warden's permanent
##            hr_warden_defeated: a save that has it never meets the Warden again, even if the spawner's own
##            clear flag is missing).
##   is_enemy_available() -> bool   (cached, re-checked every few seconds)
##   availability_override          tests: {enemy_id: bool} pretends an enemy exists / is missing

## Tests only: {enemy_id: bool} overrides the availability check.
static var availability_override: Dictionary = {}

const RECHECK_MS := 5000

var extra_params: Dictionary = {}
var block_flag: String = ""
var _avail := false
var _avail_ms := -100000


func setup(params: Dictionary) -> void:
	super.setup(params)
	var ex: Variant = params.get("extra", {})
	if ex is Dictionary:
		extra_params = ex
	block_flag = String(params.get("block_flag", block_flag))


func is_blocked() -> bool:
	return block_flag != "" and Combat.truthy(GameState.get_flag(block_flag))


## Registered in EnemyFactory AND its script exists and compiles (a broken script counts as missing, so the
## arena's stand-in keeps the quarry completable instead of waiting on an enemy that can never spawn).
static func enemy_available(enemy: String) -> bool:
	if availability_override.has(enemy):
		return bool(availability_override[enemy])
	return Factory.can_spawn(enemy)


func is_enemy_available() -> bool:
	if availability_override.has(enemy_id):
		return bool(availability_override[enemy_id])
	var now := Time.get_ticks_msec()
	if now - _avail_ms >= RECHECK_MS:
		_avail_ms = now
		_avail = enemy_available(enemy_id)
	return _avail


func update_spawner() -> void:
	if not is_enemy_available():
		return
	super.update_spawner()


## As the base spawn_one, plus `extra_params` in the enemy's setup (nothing while blocked or unavailable).
func spawn_one(p: Node3D = null) -> Node:
	if is_blocked() or not is_enemy_available():
		return null
	var pos := _pick_position(p)
	var yaw := _rng.randf_range(0.0, TAU)
	var parent: Node = get_parent() if get_parent() != null else self
	var params := {"home": pos, "wander_radius": wander_radius if wander_radius > 0.0 else maxf(radius * 0.8, 3.0), "spawner": self}
	for k in extra_params:
		params[k] = extra_params[k]
	var e := Factory.spawn(enemy_id, parent, Transform3D(Basis(Vector3.UP, yaw), pos), params)
	if e == null:
		return null
	alive.append(e)
	if e.has_signal("defeated"):
		e.defeated.connect(_on_enemy_defeated.bind(e), CONNECT_ONE_SHOT)
	if e.has_method("pop_in"):
		e.pop_in()
	enemy_spawned.emit(e)
	return e
