extends Node3D
## Lanternwake Expeditions in Hallowmere Reach (module D2): one node under the Reach area root, named
## NODE_NAME, added by attach(area): by Expeditions' Events.area_loaded listener on a Reach load while a run is
## going, by Expeditions.start() when the run begins in the Reach, and by hand in tests.
## It is a VIEW of the saved run (src/expeditions/expeditions.gd); nothing here is saved by itself:
##   * a ribbon lantern (expedition_beacon.gd) stands at the current stop, then at the cache;
##   * the stop's group (the plan's seeded group, minus the ones already defeated) appears only while Krystal
##     is within SPAWN_RADIUS of that lantern, outside every safe zone, no boss fight on, and only at authored
##     points that are NOT in view (outside the camera frustum, farther than VIEW_DISTANCE, or hidden behind
##     world geometry) and at least MIN_SPAWN_DISTANCE from her. A point in view simply waits;
##   * every enemy it spawns carries (template, run, stop) so only defeats of THIS stop of THIS run count;
##   * respawn-safe: when she dies / respawns or walks beyond DESPAWN_RADIUS, the living ones go away and
##     come back (never the defeated ones) when she returns; a save/quit resumes at the saved stop;
##   * after the last stop the cache (expedition_cache.gd) waits at its authored place; opening it calls
##     Expeditions.complete() (rewards once per run) and it folds away.
## Polls the saved run every TICK seconds (no per-frame work, no group scans; physics queries only while a
## group is being placed). Never writes a flag; spawned enemies get no defeat_flag.

const Ex := preload("res://src/expeditions/expeditions.gd")
const Data := preload("res://data/expeditions.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Beacon := preload("res://src/expeditions/expedition_beacon.gd")
const Cache := preload("res://src/expeditions/expedition_cache.gd")

const SCRIPT_PATH := "res://src/expeditions/expedition_runner.gd"
const NODE_NAME := "Expeditions"
const TICK := 0.25
const GROUND_MASK := 1 | 32
const VIEW_MASK := 1 | 32              # world + structures hide a point (same as EnemySpawner.in_view)
const EYE_HEIGHTS := [0.4, 1.6]
const SPAWN_LOG_MAX := 32

var player_override: Node3D = null      # tests: the node treated as Krystal
var camera_override: Camera3D = null    # tests: the camera deciding "in view"
var use_camera := true                  # false: nothing counts as in view (headless tests without a camera)
var ignore_safe_zones := false          # tests
var alive: Array = []                   # enemies of the current stop in the world now
var beacon: Node3D = null
var cache: Node3D = null
var spawn_log: Array = []               # tests / QA: the last SPAWN_LOG_MAX spawns [{enemy, point: Vector2, stop}]

var _template: String = ""
var _run: int = -1
var _stop: int = -1
var _plan: Dictionary = {}
var _stop_count: int = 0
var _centre := Vector3.ZERO
var _points3: Array = []                # current stop's spawn points on the ground (plan order)
var _busy: Array = []                   # point index -> enemy standing there (or null)
var _t: float = 0.0
var _ray: PhysicsRayQueryParameters3D = null


## Adds the runner to `area` once (idempotent); returns it.
static func attach(area: Node) -> Node:
	if area == null or not is_instance_valid(area):
		return null
	var existing := area.get_node_or_null(NODE_NAME)
	if existing != null and not existing.is_queued_for_deletion():
		return existing
	var s: Script = load(SCRIPT_PATH)
	var r: Node3D = s.new()
	r.name = NODE_NAME
	area.add_child(r)
	return r


func _ready() -> void:
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = VIEW_MASK
	Events.player_respawned.connect(_on_player_respawned)
	_t = 0.0
	update_runner()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	update_runner()


# --- Reconcile with the saved run -----------------------------------------------------------------------------

func update_runner() -> void:
	var a := Ex.active()
	if a.is_empty():
		if _template != "":
			clear_all()
		return
	if String(a["template"]) != _template or int(a["run"]) != _run or int(a["stop"]) != _stop:
		_rebuild(a)
	if _stop < _stop_count:
		_update_group(a)


func _rebuild(a: Dictionary) -> void:
	despawn_all()
	_template = String(a["template"])
	_run = int(a["run"])
	_stop = int(a["stop"])
	_plan = Ex.plan(_template, int(a["seed"]))
	_stop_count = (_plan.get("stops", []) as Array).size()
	_points3.clear()
	_busy.clear()
	var target := Vector2.ZERO
	if _stop < _stop_count:
		var s: Dictionary = _plan["stops"][_stop]
		target = s["pos"]
		for p in s["points"]:
			_points3.append(ground_point(p))
			_busy.append(null)
		if cache != null and is_instance_valid(cache):
			cache.queue_free()
		cache = null
		_centre = ground_point(target)
	else:
		# The lantern stands beside the cache; the cache faces the last stop.
		target = (_plan["cache"] as Dictionary).get("pos", Vector2.ZERO)
		var last: Vector2 = (_plan["stops"][_stop_count - 1] as Dictionary)["pos"] if _stop_count > 0 else target
		_centre = ground_point(last)
		_ensure_cache()
		_centre = ground_point(target + (last - target).normalized() * 1.6 if last.distance_to(target) > 0.1 else target)
	if beacon == null or not is_instance_valid(beacon):
		beacon = Beacon.new()
		beacon.name = "ExpeditionLantern"
		add_child(beacon)
	beacon.call("place", _centre, "cache" if _stop >= _stop_count else "stop")


## Forgets the run's world nodes (no run any more: abandoned or completed).
func clear_all() -> void:
	despawn_all()
	if beacon != null and is_instance_valid(beacon):
		beacon.queue_free()
	beacon = null
	if cache != null and is_instance_valid(cache):
		cache.queue_free()
	cache = null
	_template = ""
	_run = -1
	_stop = -1
	_plan = {}
	_stop_count = 0
	_points3.clear()
	_busy.clear()


# --- The stop's group -----------------------------------------------------------------------------------------

func _update_group(a: Dictionary) -> void:
	_prune()
	var p := _player()
	if p == null:
		return
	var d := p.global_position.distance_to(_centre)
	if d > Data.DESPAWN_RADIUS:
		if not alive.is_empty():
			despawn_all()
		return
	if d > Data.SPAWN_RADIUS or not _spawning_allowed(p):
		return
	var s: Dictionary = _plan["stops"][_stop]
	if int(s["needed"]) - int(a["defeated"]) - alive.size() <= 0:
		return
	spawn_missing(p)


## Spawns every missing enemy of the current stop that has a free, out-of-view point right now.
## Returns how many appeared.
func spawn_missing(p: Node3D = null) -> int:
	if _stop < 0 or _stop >= _stop_count:
		return 0
	var who := p if p != null else _player()
	var idx := _free_point(who)
	if idx < 0:
		return 0             # every free point is in view (or too close): wait, without building any list
	var n := 0
	for id in _missing_ids():
		if idx < 0:
			break
		if _spawn_at(String(id), idx) != null:
			n += 1
		idx = _free_point(who)
	return n


## Enemy ids of the current stop still to be met: the plan's group minus the saved defeats ("down") minus
## the ones in the world.
func _missing_ids() -> Array:
	var a := Ex.active()
	var s: Dictionary = _plan["stops"][_stop]
	var left: Dictionary = {}
	for e in s["enemies"]:
		left[e] = int(left.get(e, 0)) + 1
	var down: Dictionary = a.get("down", {}) if a.get("down") is Dictionary else {}
	var extra_down := int(a["defeated"])
	for e in down:
		var k := mini(int(down[e]), int(left.get(e, 0)))
		if k > 0:
			left[e] = int(left[e]) - k
			extra_down -= k
	for e in s["enemies"]:
		if extra_down <= 0:
			break
		if int(left.get(e, 0)) > 0:
			left[e] = int(left[e]) - 1
			extra_down -= 1
	for en in alive:
		var eid := String((en as Node).get_meta("exp_enemy", ""))
		if int(left.get(eid, 0)) > 0:
			left[eid] = int(left[eid]) - 1
	var out: Array = []
	for e in s["enemies"]:
		if int(left.get(e, 0)) > 0:
			left[e] = int(left[e]) - 1
			out.append(e)
	return out


func _free_point(p: Node3D) -> int:
	for i in _points3.size():
		var b: Variant = _busy[i]
		if b != null and is_instance_valid(b) and not (b as Node).is_queued_for_deletion():
			continue
		var pt: Vector3 = _points3[i]
		if p != null and pt.distance_to(p.global_position) < Data.MIN_SPAWN_DISTANCE:
			continue
		if is_point_in_view(pt):
			continue
		return i
	return -1


func _spawn_at(enemy_id: String, idx: int) -> Node:
	var pos: Vector3 = _points3[idx]
	var to_c := _centre - pos
	var yaw := atan2(-to_c.x, -to_c.z) if Vector2(to_c.x, to_c.z).length() > 0.01 else 0.0
	var e := Factory.spawn(enemy_id, self, Transform3D(Basis(Vector3.UP, yaw), pos),
		{"home": pos, "wander_radius": Data.ENEMY_WANDER})
	if e == null:
		# A missing/broken enemy script must never stall a run: it counts as met.
		push_warning("Expeditions: '%s' could not appear; counted as met" % enemy_id)
		Ex.record_defeat(_template, _run, _stop, enemy_id)
		return null
	e.set_meta("exp_enemy", enemy_id)
	alive.append(e)
	_busy[idx] = e
	if e.has_signal("defeated"):
		e.connect("defeated", _on_enemy_defeated.bind(e, enemy_id, _template, _run, _stop), CONNECT_ONE_SHOT)
	if e.has_method("pop_in"):
		e.call("pop_in")
	if spawn_log.size() >= SPAWN_LOG_MAX:
		spawn_log.pop_front()
	spawn_log.append({"enemy": enemy_id, "point": Vector2(pos.x, pos.z), "stop": _stop})
	return e


func _on_enemy_defeated(e: Node, enemy_id: String, template_id: String, run: int, stop: int) -> void:
	alive.erase(e)
	Ex.record_defeat(template_id, run, stop, enemy_id)


func despawn_all() -> void:
	for e in alive:
		if is_instance_valid(e):
			(e as Node).queue_free()
	alive.clear()
	for i in _busy.size():
		_busy[i] = null


func _prune() -> void:
	for i in range(alive.size() - 1, -1, -1):
		var e: Variant = alive[i]
		if not is_instance_valid(e) or (e as Node).is_queued_for_deletion():
			alive.remove_at(i)


func _on_player_respawned() -> void:
	despawn_all()


func _spawning_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "loading" or Game.mode == "cutscene":
		return false
	if Game.has_method("boss_active") and bool(Game.boss_active()):
		return false
	if ignore_safe_zones:
		return true
	var area := get_parent()
	if area != null and area.has_method("is_safe_zone"):
		if bool(area.call("is_safe_zone", p.global_position)) or bool(area.call("is_safe_zone", _centre)):
			return false
	return true


# --- View and ground ------------------------------------------------------------------------------------------

## True when a creature standing at `pos` could be seen: inside the camera frustum, within VIEW_DISTANCE and
## not hidden behind world geometry (checked at knee and head height). No camera -> never in view.
func is_point_in_view(pos: Vector3) -> bool:
	var cam := _camera()
	if cam == null:
		return false
	var eye := cam.global_position
	for h in EYE_HEIGHTS:
		var t := pos + Vector3.UP * float(h)
		if eye.distance_to(t) > Data.VIEW_DISTANCE or not cam.is_position_in_frustum(t):
			continue
		if not is_inside_tree():
			return true
		_ray.from = eye
		_ray.to = t
		if get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
			return true
	return false


func _camera() -> Camera3D:
	if camera_override != null and is_instance_valid(camera_override):
		return camera_override
	if not use_camera or not is_inside_tree():
		return null
	return get_viewport().get_camera_3d()


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


## An authored Vector2(x, z) on the ground: the area's height, then a ray onto whatever stands there.
func ground_point(p: Vector2) -> Vector3:
	var area := get_parent()
	var y := 0.0
	if area != null and area.has_method("height_at"):
		y = float(area.call("height_at", p.x, p.y))
	var pos := Vector3(p.x, y, p.y)
	if not is_inside_tree():
		return pos
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.5, pos + Vector3.DOWN * 6.0, GROUND_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return pos
	return (hit["position"] as Vector3) + Vector3.UP * 0.05


# --- The cache ------------------------------------------------------------------------------------------------

func _ensure_cache() -> void:
	if cache != null and is_instance_valid(cache):
		return
	var c: Dictionary = _plan.get("cache", {})
	cache = Cache.new()
	cache.name = "ExpeditionCache"
	cache.call("setup", {"name": String(c.get("name", "the cache")), "handler": Callable(self, "open_cache")})
	add_child(cache)
	cache.global_position = ground_point(c.get("pos", Vector2.ZERO))
	var to_b := _centre - cache.global_position
	if Vector2(to_b.x, to_b.z).length() > 0.01:
		cache.rotation.y = atan2(-to_b.x, -to_b.z)


## The cache's handler: pays the run once (Expeditions.complete) and lets the cache fold away by itself.
func open_cache(_player_node: Node = null) -> Dictionary:
	var r := Ex.complete()
	if r.is_empty():
		return r
	if cache != null and is_instance_valid(cache):
		var c := cache
		cache = null
		c.call("play_open")
	update_runner()
	return r
