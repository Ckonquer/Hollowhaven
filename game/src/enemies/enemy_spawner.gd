extends Node3D
## Places a small group of enemies in the world (placed by the area modules).
##   var S = load("res://src/enemies/enemy_spawner.gd")
##   var sp: Node3D = S.new()
##   sp.setup({"enemy": "brambling", "count": 3, "radius": 7.0, "respawn_minutes": 1440.0,
##             "spawner_id": "ruin_bramblings", "quest_flag_on_clear": "ruin_cleared"})
##   area.add_child(sp); sp.global_position = Vector3(...)
## Rules:
## * Spawns (a "wave" of `count`) when the player is within SPAWN_DISTANCE and not in a safe zone.
## * Despawns the living ones when the player is farther than DESPAWN_DISTANCE (they come back later;
##   enemies already defeated in the current wave stay defeated).
## * When every enemy of a wave is defeated the spawner is "cleared": flag "spawner_cleared_<id>" and
##   the optional quest flag are set (persisted by GameState). respawn_minutes < 0 = never again;
##   otherwise a new wave may appear after that many in-game minutes (persisted via GameState.deplete).
## Optional params: "clear_message" (toast on first clear), "wander_radius", "min_player_distance".

signal cleared(spawner_id: String)
signal enemy_spawned(enemy: Node)

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Combat := preload("res://src/combat/combat.gd")

const SPAWN_DISTANCE := 45.0
const DESPAWN_DISTANCE := 70.0
const TICK := 0.5
const GROUND_MASK := 1 | 32
const MAX_SPAWN_STEP := 1.6        # max ground height difference from the spawner's own base

var enemy_id: String = "brambling"
var count: int = 3
var radius: float = 6.0
var respawn_minutes: float = 1440.0
var spawner_id: String = ""
var quest_flag_on_clear: String = ""
var clear_message: String = ""
var wander_radius: float = -1.0
var min_player_distance: float = 7.0
var alive: Array = []
var defeated_in_wave: int = 0
var player_override: Node3D = null      # tests
var ignore_safe_zones := false          # tests / scripted fights

var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(params: Dictionary) -> void:
	enemy_id = String(params.get("enemy", enemy_id))
	count = maxi(int(params.get("count", count)), 1)
	radius = maxf(float(params.get("radius", radius)), 0.0)
	respawn_minutes = float(params.get("respawn_minutes", respawn_minutes))
	spawner_id = String(params.get("spawner_id", spawner_id))
	quest_flag_on_clear = String(params.get("quest_flag_on_clear", quest_flag_on_clear))
	clear_message = String(params.get("clear_message", clear_message))
	wander_radius = float(params.get("wander_radius", wander_radius))
	min_player_distance = float(params.get("min_player_distance", min_player_distance))


func _ready() -> void:
	if spawner_id != "":
		_rng.seed = hash(spawner_id)
	_t = TICK * 0.5


## Without an explicit spawner_id the id comes from the position - resolved lazily (first update)
## because callers often add_child() first and set global_position afterwards; resolving it in
## _ready would give every such spawner the same id (and one clear would clear them all).
func _ensure_id() -> void:
	if spawner_id != "":
		return
	var p := global_position if is_inside_tree() else position
	spawner_id = "%s_%d_%d" % [enemy_id, int(roundf(p.x)), int(roundf(p.z))]
	_rng.seed = hash(spawner_id)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	update_spawner()


# --- Persistence helpers ---------------------------------------------------------------------------------

func cleared_flag() -> String:
	_ensure_id()
	return "spawner_cleared_" + spawner_id


func cooldown_id() -> String:
	_ensure_id()
	return "spawner_" + spawner_id


func is_cleared() -> bool:
	return Combat.truthy(GameState.get_flag(cleared_flag()))


## True if a (new) wave may be spawned right now according to the saved state.
func wave_available() -> bool:
	if is_cleared() and respawn_minutes < 0.0:
		return false
	return not GameState.is_depleted(cooldown_id())


# --- Main update (throttled) ------------------------------------------------------------------------------

func update_spawner() -> void:
	_ensure_id()
	_prune()
	var p := _player()
	if p == null:
		return
	var d := global_position.distance_to(p.global_position)
	if d > DESPAWN_DISTANCE:
		if not alive.is_empty():
			despawn_all()
		return
	if d > SPAWN_DISTANCE or not wave_available() or not _spawning_allowed(p):
		return
	var missing := count - defeated_in_wave - alive.size()
	for i in missing:
		spawn_one(p)


func _spawning_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "loading" or Game.mode == "cutscene":
		return false
	if ignore_safe_zones:
		return true
	var a: Node = Game.area
	if a != null and is_instance_valid(a) and a.has_method("is_safe_zone"):
		if bool(a.is_safe_zone(p.global_position)) or bool(a.is_safe_zone(global_position)):
			return false
	return true


func spawn_one(p: Node3D = null) -> Node:
	var pos := _pick_position(p)
	var yaw := _rng.randf_range(0.0, TAU)
	var parent: Node = get_parent() if get_parent() != null else self
	var e := Factory.spawn(enemy_id, parent, Transform3D(Basis(Vector3.UP, yaw), pos),
		{"home": pos, "wander_radius": wander_radius if wander_radius > 0.0 else maxf(radius * 0.8, 3.0), "spawner": self})
	if e == null:
		return null
	alive.append(e)
	if e.has_signal("defeated"):
		e.defeated.connect(_on_enemy_defeated.bind(e), CONNECT_ONE_SHOT)
	if e.has_method("pop_in"):
		e.pop_in()
	enemy_spawned.emit(e)
	return e


func despawn_all() -> void:
	for e in alive:
		if is_instance_valid(e):
			e.queue_free()
	alive.clear()


func _on_enemy_defeated(e: Node) -> void:
	alive.erase(e)
	defeated_in_wave += 1
	if defeated_in_wave >= count:
		_on_wave_cleared()


func _on_wave_cleared() -> void:
	defeated_in_wave = 0
	var first := not is_cleared()
	GameState.set_flag(cleared_flag(), true)
	if quest_flag_on_clear != "":
		GameState.set_flag(quest_flag_on_clear, true)
	if respawn_minutes >= 0.0:
		GameState.deplete(cooldown_id(), respawn_minutes)
	if first and clear_message != "":
		Events.notify.emit(clear_message, "success")
	cleared.emit(spawner_id)


func _prune() -> void:
	for i in range(alive.size() - 1, -1, -1):
		var e: Variant = alive[i]
		if not is_instance_valid(e) or (e as Node).is_queued_for_deletion():
			alive.remove_at(i)


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	var tree := get_tree()
	if tree == null:
		return null
	var ps := tree.get_nodes_in_group("player")
	return ps[0] as Node3D if not ps.is_empty() else null


## Random ground point inside the spawn radius, preferring points away from the player. Points
## whose ground is far above/below the spawner (the top of a ruin wall, a pillar, a pit) are
## skipped, so an enemy never starts somewhere Krystal can't reach (the Ruin's clear gates a quest).
func _pick_position(p: Node3D) -> Vector3:
	var base := global_position          # areas place spawners on the ground
	var best := base
	var best_d := -1.0
	for attempt in 8:
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var cand := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		cand = _ground(cand)
		if absf(cand.y - base.y) > MAX_SPAWN_STEP:
			continue
		var pd := 999.0 if p == null else cand.distance_to(p.global_position)
		if pd >= min_player_distance:
			return cand
		if pd > best_d:
			best_d = pd
			best = cand
	return best


func _ground(pos: Vector3) -> Vector3:
	if not is_inside_tree():
		return pos
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 4.0, pos + Vector3.DOWN * 8.0, GROUND_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos
	return (hit["position"] as Vector3) + Vector3.UP * 0.05
