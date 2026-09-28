extends Node
## Local horror director for the Below. Pure gameplay pacing: no network, no LLM, no paid APIs.
## Game creates it for the "below" area: setup({"area": area, "seed": int}) before add_child under
## the area root (Game.director references it). Once a second it reads the world into a small
## context (zone, safety, player health / movement, threats, companion, intensity, anchors), asks
## director_core.gd for a decision and lets event_runner.gd execute it.
##
## Anchors: Marker3D nodes in group "director_anchor" with metadata "zone" (mine/ruins/silk),
## "kind" (sound/doorway/ceiling/floor/spawn) and optional "room". A cheap visibility test (in the
## camera view and not blocked by world geometry) decides where things may appear.
##
## Cancels pending work on pause, safe zones, cutscenes, player death, area exit and authored
## moments (Events.horror_event "authored:<id>"). Emits Events.horror_state_changed and
## Events.horror_event for every executed event.
## When the runner cannot carry out a chosen event (blocked anchor, no light, busy stalker...) the
## core rolls its pacing back (director_core.gd on_event_failed), so nothing "phantom" costs a recovery.
## Chapter Two (additive): Game also creates it for "hushed_works" (Game.DIRECTOR_AREAS); an area may hand
## its own tables through director_config() (see _core_params), and hold(id) / release(id) give puzzles,
## bosses and authored scenes a stacking-safe quiet period next to suppress().
## Debug: --director-log=<path> writes the decision log to a file;
##        --director-force=<id>[,<id>...] (debug builds) fires events a few seconds after start;
##        --director-probe (debug builds) checks every spawn anchor against real physics and logs it.

const Core := preload("res://src/horror/director_core.gd")
const Runner := preload("res://src/horror/event_runner.gd")
const HorrorData := preload("res://data/horror_events.gd")

const THREAT_RADIUS := 20.0
const ANCHOR_RANGE := 48.0
const ANCHOR_REFRESH := 4.0
const LINGER_RADIUS := 2.0
const RETREAT_MEMORY := 12.0
const DESPAWN_DISTANCE := 30.0
const WORLD_MASK := 1 | 32
const VIEW_MARGIN := 0.06            # screen fraction: points just outside the frame count as visible
const BLOCKING_MODES := ["dead", "loading", "cutscene"]
const ONCE_FLAG_PREFIX := "horror_once_"   # GameState flag per "once" event: once per playthrough
const HELD_ZONE := "held"                   # pseudo zone reported to the core while any hold() is active

var core: Core = null
var runner: Runner = null
var area: Node = null
var seed_value: int = 0
var tick_seconds: float = 1.0
var enabled: bool = true
var last_decision: Dictionary = {}
var last_context: Dictionary = {}

## The core's human-readable decision log (most recent last).
var debug_log: Array[String]:
	get:
		if core != null:
			return core.debug_log
		return _no_log

var _no_log: Array[String] = []
var _accum: float = 0.0
var _clock: float = 0.0
var _anchor_nodes: Array = []
var _anchor_age: float = 1.0e9
var _linger_origin: Vector3 = Vector3.ZERO
var _linger_time: float = 0.0
var _has_linger_origin: bool = false
var _last_threat_pos: Vector3 = Vector3.ZERO
var _last_threat_time: float = -1.0e9
var _prev_threat_dist: float = -1.0
var _enemies_nearby: int = 0
var _force_queue: Array = []
var _force_t: float = 0.0
var _probe_at: float = -1.0
var _holds: Dictionary = {}          # hold id -> true (hold()/release(); Chapter Two)


func setup(params: Dictionary) -> void:
	var a: Variant = params.get("area", null)
	if a is Node:
		area = a
	seed_value = int(params.get("seed", 0))
	tick_seconds = maxf(float(HorrorData.DIRECTOR.get("tick_seconds", 1.0)), 0.1)
	core = Core.new()
	core.setup(_core_params(params))


## Chapter Two (additive): the core gets the event / tuning / intensity tables passed in `params`, else the
## ones the area offers through director_config() -> {"events", "tuning", "intensity"} (the Hushed Works),
## else the Chapter One defaults (the Below: identical to before).
func _core_params(params: Dictionary) -> Dictionary:
	var out := {"seed": seed_value}
	var cfg: Dictionary = {}
	if params.has("events") or params.has("tuning") or params.has("intensity"):
		cfg = params
	elif area != null and area.has_method("director_config"):
		var c: Variant = area.director_config()
		if c is Dictionary:
			cfg = c
	for k in ["events", "tuning", "intensity"]:
		if cfg.get(k) is Dictionary:
			out[k] = cfg[k]
	return out


func _ready() -> void:
	if core == null:
		setup({})
	if area == null:
		area = get_parent()
	runner = Runner.new()
	runner.name = "EventRunner"
	runner.setup({"seed": seed_value + 7919, "log": core.log_line, "visibility": is_point_visible})
	add_child(runner)
	runner.event_failed.connect(_on_runner_event_failed)
	core.state_changed.connect(_on_core_state_changed)
	_restore_once_events()
	Events.paused_changed.connect(_on_paused_changed)
	Events.safe_zone_changed.connect(_on_safe_zone_changed)
	Events.area_exiting.connect(_on_area_exiting)
	Events.player_died.connect(_on_player_died)
	Events.horror_event.connect(_on_horror_event)
	Events.cutscene_changed.connect(_on_cutscene_changed)
	if Debug.has_arg("director-log"):
		core.set_log_file(Debug.arg("director-log"))
	if Debug.is_cheat_allowed() and Debug.has_arg("director-force"):
		_force_queue = Array(Debug.arg("director-force").split(",", false))
		_force_t = -3.0
	if Debug.is_cheat_allowed() and Debug.has_arg("director-probe"):
		_probe_at = 2.0
	core.log_line("director ready (seed %d, intensity %s)" % [seed_value, str(Settings.get_value("horror_intensity"))])
	Events.horror_state_changed.emit(core.state)


func _process(delta: float) -> void:
	if not enabled:
		return
	_accum += delta
	if _accum >= tick_seconds:
		var dt := _accum
		_accum = 0.0
		tick_now(dt)
	if not _force_queue.is_empty():
		_force_t += delta
		if _force_t >= 0.0:
			_force_t = -4.0
			debug_force(String(_force_queue.pop_front()))
	if _probe_at > 0.0:
		_probe_at -= delta
		if _probe_at <= 0.0:
			_probe_at = -1.0
			debug_probe_anchors()


# --- Public API ---------------------------------------------------------------------------------

func get_state() -> String:
	return core.state if core != null else "calm"


## Hands-off period (authored scenes). Pending work is cancelled. Overlapping calls keep the longest
## time, but a very long "hold" (suppress(9999) during the boss fight) is replaced by the next call.
func suppress(seconds: float, replace: bool = false) -> void:
	if core != null:
		core.suppress(seconds, replace)
	if runner != null:
		runner.cancel_all("suppressed")


## Stacking-safe quiet period (Chapter Two, additive): while ANY hold id is active the director treats
## Krystal's zone as quiet (tension frozen, nothing fires, pending work cancelled once). Unlike suppress(),
## holds never replace each other: puzzles, bosses and authored scenes each hold and release their own id.
## Releasing the last hold re-enters the real zone with the core's usual start grace.
func hold(hold_id: String) -> void:
	if hold_id == "" or _holds.has(hold_id):
		return
	_holds[hold_id] = true
	if runner != null:
		runner.cancel_all("held by " + hold_id)
	if core != null:
		core.log_line("held by '%s' (%d hold(s))" % [hold_id, _holds.size()])


func release(hold_id: String) -> void:
	if not _holds.has(hold_id):
		return
	_holds.erase(hold_id)
	if core != null:
		core.log_line("hold '%s' released (%d left)" % [hold_id, _holds.size()])


func is_held() -> bool:
	return not _holds.is_empty()


func held_ids() -> Array:
	return _holds.keys()


## One director step. Called every tick_seconds; tests call it directly.
func tick_now(dt: float) -> Dictionary:
	_clock += dt
	var ctx := build_context(dt)
	last_context = ctx
	var d: Dictionary = core.tick(dt, ctx)
	last_decision = d
	if bool(d.get("cancel", false)) and runner != null:
		runner.cancel_all(String(d.get("reason", "")))
	if String(d.get("event_id", "")) != "":
		_execute(d, ctx)
	if core.state == "calm" and runner != null:
		var p := _player()
		if p != null:
			runner.despawn_far(p.global_position, DESPAWN_DISTANCE)
	return d


## Debug/QA only: fire an event now (still needs a usable anchor). Returns the decision.
func debug_force(event_id: String) -> Dictionary:
	if not Debug.is_cheat_allowed() or core == null:
		return {}
	var ctx := build_context(0.0)
	var d: Dictionary = core.force(event_id, ctx)
	if String(d.get("event_id", "")) != "":
		_execute(d, ctx)
	return d


## Debug/QA only: checks every spawn anchor in the scene against real physics (ground under it,
## clearance, the same-room nudge the runner uses; player distance and visibility are ignored) and
## logs one verdict per anchor. Returns [{name, ok, reason, nudged}].
func debug_probe_anchors() -> Array:
	var out: Array = []
	if not Debug.is_cheat_allowed() or runner == null or not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group("director_anchor"):
		if not is_instance_valid(n) or not (n is Node3D) or String(n.get_meta("kind", "")) != "spawn":
			continue
		var node := n as Node3D
		var a := {"name": String(node.name), "kind": "spawn", "zone": String(node.get_meta("zone", "")),
			"room": String(node.get_meta("room", "")), "pos": node.global_position}
		var r: Dictionary = runner.probe_spawn_anchor(a, {"area": area})
		var row := {"name": a["name"], "ok": bool(r.get("ok", false)), "reason": String(r.get("reason", "")),
			"nudged": float(r.get("nudged", 0.0))}
		out.append(row)
		core.log_line("probe %s: %s%s" % [row["name"], "ok" if row["ok"] else "UNUSABLE - " + String(row["reason"]),
			(" (nudged %.1fm)" % float(row["nudged"])) if float(row["nudged"]) > 0.0 else ""])
	return out


## Reads the world into the core's context dictionary.
func build_context(dt: float) -> Dictionary:
	var ctx := {"zone": "", "in_safe_zone": false, "paused": false, "player_hp_ratio": 1.0,
		"sprinting": false, "retreating": false, "lingering_seconds": 0.0, "threats_nearby": 0, "enemies_nearby": 0,
		"active_director_threats": 0, "companion": "", "intensity": _intensity(), "anchors": [],
		"time": _clock}
	var player := _player()
	if player == null or not is_inside_tree():
		ctx["paused"] = true
		return ctx
	# Hold still while the world is frozen, during death / loading / cutscenes, and while a gameplay
	# panel is open (the companion menu does not pause the tree, but Krystal cannot move or defend).
	var blocked := Game.area == area and (BLOCKING_MODES.has(Game.mode) or (Game.has_method("is_ui_open") and bool(Game.is_ui_open())))
	ctx["paused"] = get_tree().paused or blocked
	var ppos := player.global_position
	if Game.area == area and area != null:
		ctx["zone"] = Game.zone_id
		ctx["in_safe_zone"] = Game.in_safe_zone
	elif area != null:
		if area.has_method("get_zone_at"):
			ctx["zone"] = String(area.get_zone_at(ppos))
		if area.has_method("is_safe_zone"):
			ctx["in_safe_zone"] = bool(area.is_safe_zone(ppos))
	if not _holds.is_empty():
		ctx["zone"] = HELD_ZONE        # no event lists it: the core stays quiet ("zone 'held' is quiet")
		ctx["held"] = _holds.keys()
	ctx["player_hp_ratio"] = _player_hp_ratio(player)
	if player.has_method("is_sprinting"):
		ctx["sprinting"] = bool(player.is_sprinting())
	ctx["lingering_seconds"] = _update_linger(ppos, dt)
	ctx["threats_nearby"] = _scan_threats(ppos)
	ctx["enemies_nearby"] = _enemies_nearby
	ctx["retreating"] = _is_retreating(ppos)
	ctx["active_director_threats"] = runner.active_threat_count() if runner != null else 0
	var comp := _companion_node()
	ctx["companion"] = GameState.active_companion if comp != null else ""
	ctx["anchors"] = _anchor_context(ppos, dt)
	return ctx


## Cheap visibility test: inside the camera frame (with a small margin) and not blocked by the world.
func is_point_visible(pos: Vector3) -> bool:
	var cam := _camera()
	if cam == null or not cam.is_inside_tree():
		return false
	if cam.is_position_behind(pos):
		return false
	var vp := cam.get_viewport()
	if vp == null:
		return false
	var size := vp.get_visible_rect().size
	var sp := cam.unproject_position(pos)
	var rect := Rect2(Vector2.ZERO, size).grow(size.x * VIEW_MARGIN)
	if not rect.has_point(sp):
		return false
	var space := _space()
	if space == null:
		return true
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, pos, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(pos) < 0.4


# --- Context helpers -----------------------------------------------------------------------------

func _player() -> Node3D:
	var p: Variant = Game.player
	if is_instance_valid(p) and p is Node3D and (p as Node3D).is_inside_tree():
		return p
	if not is_inside_tree():
		return null
	var list := get_tree().get_nodes_in_group("player")
	for n in list:
		if is_instance_valid(n) and n is Node3D:
			return n
	return null


func _camera() -> Camera3D:
	var p := _player()
	if p != null and p.has_method("get_camera"):
		var c: Variant = p.get_camera()
		if is_instance_valid(c) and c is Camera3D:
			return c
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


func _space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	return w.direct_space_state if w != null else null


func _intensity() -> int:
	return clampi(int(Settings.get_value("horror_intensity")), 0, 2)


func _player_hp_ratio(player: Node) -> float:
	var h: Variant = player.get("health")
	if is_instance_valid(h) and h is Object and (h as Object).has_method("ratio"):
		return clampf(float(h.ratio()), 0.0, 1.0)
	var mx := float(GameState.player.get("max_hp", 100.0))
	if mx > 0.0:
		return clampf(float(GameState.player.get("hp", mx)) / mx, 0.0, 1.0)
	return 1.0


func _update_linger(ppos: Vector3, dt: float) -> float:
	if not _has_linger_origin or ppos.distance_to(_linger_origin) > LINGER_RADIUS:
		_linger_origin = ppos
		_has_linger_origin = true
		_linger_time = 0.0
	else:
		_linger_time += dt
	return _linger_time


## Counts enemies hunting Krystal within THREAT_RADIUS. Idle dungeon enemies that close (a room's own
## encounter that has not started yet) are counted separately in _enemies_nearby.
## Boss floor hazards (egg sacs, trip lines, threads: meta "boss_hazard") are in group "enemy" only so
## Krystal can hit them; they are neither threats nor a room's encounter, so they are skipped (R71).
func _scan_threats(ppos: Vector3) -> int:
	var n := 0
	var idle := 0
	var nearest := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D) or not e.has_method("is_threatening"):
			continue
		if bool((e as Node).get_meta("boss_hazard", false)):
			continue
		var d := (e as Node3D).global_position.distance_to(ppos)
		if d > THREAT_RADIUS:
			continue
		if not bool(e.is_threatening()):
			var dead: bool = e.has_method("is_dead") and bool(e.is_dead())
			if not dead and not (e as Node).has_meta("director_spawned"):
				idle += 1
			continue
		n += 1
		if d < nearest:
			nearest = d
			_last_threat_pos = (e as Node3D).global_position
	_enemies_nearby = idle
	if n > 0:
		_last_threat_time = _clock
	return n


## Moving away from the last threat seen (recently): the director eases off.
func _is_retreating(ppos: Vector3) -> bool:
	if _clock - _last_threat_time > RETREAT_MEMORY:
		_prev_threat_dist = -1.0
		return false
	var d := ppos.distance_to(_last_threat_pos)
	var retreating := _prev_threat_dist >= 0.0 and d > _prev_threat_dist + 0.8
	_prev_threat_dist = d
	return retreating


func _companion_node() -> Node:
	var id := GameState.active_companion
	if id == "":
		return null
	var n: Variant = Game.companion_nodes.get(id)
	if is_instance_valid(n) and n is Node and (n as Node).is_inside_tree():
		return n
	return null


func _anchor_context(ppos: Vector3, dt: float) -> Array:
	_anchor_age += dt
	if _anchor_age >= ANCHOR_REFRESH or _anchors_stale():
		_anchor_age = 0.0
		_anchor_nodes = get_tree().get_nodes_in_group("director_anchor")
	var out: Array = []
	for n in _anchor_nodes:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var node := n as Node3D
		var pos := node.global_position
		var dist := pos.distance_to(ppos)
		if dist > ANCHOR_RANGE:
			continue
		out.append({"name": String(node.name), "kind": String(node.get_meta("kind", "")),
			"zone": String(node.get_meta("zone", "")), "room": String(node.get_meta("room", "")),
			"pos": pos, "dist": dist, "visible": is_point_visible(pos + Vector3.UP * 0.6)})
	return out


func _anchors_stale() -> bool:
	for n in _anchor_nodes:
		if not is_instance_valid(n):
			return true
	return false


func _execute(d: Dictionary, ctx: Dictionary) -> void:
	if runner == null:
		return
	var env := {"player": _player(), "area": area, "companion_node": _companion_node(),
		"intensity": int(ctx.get("intensity", 1)), "arachnophobia": bool(Settings.get_value("arachnophobia")),
		"reduce_flashing": bool(Settings.get_value("reduce_flashing"))}
	var res: Dictionary = runner.execute(d, env)
	if not bool(res.get("ok", false)):
		core.on_event_failed(String(d["event_id"]), String(res.get("note", "")))
		return
	if bool((d.get("event", {}) as Dictionary).get("once", false)):
		_remember_once(String(d["event_id"]))
	Events.horror_event.emit(String(d["event_id"]), {"kind": String(d.get("kind", "")),
		"zone": String(ctx.get("zone", "")), "state": core.state, "major": bool(d.get("major", false)),
		"pos": res.get("pos", Vector3.ZERO)})


## "once" events stay used across visits and save/load (GameState flags).
func _restore_once_events() -> void:
	for id in core.events:
		var ev: Dictionary = core.events[id]
		if bool(ev.get("once", false)) and bool(GameState.get_flag(ONCE_FLAG_PREFIX + String(id))):
			core.fired_once[String(id)] = true


func _remember_once(event_id: String) -> void:
	GameState.set_flag(ONCE_FLAG_PREFIX + event_id, true)


# --- Signals ------------------------------------------------------------------------------------------

func _on_core_state_changed(new_state: String, _reason: String) -> void:
	Events.horror_state_changed.emit(new_state)


## A delayed part of an event failed after execute() had accepted it (every ambusher's spawn point
## turned out blocked or visible when the telegraph ended).
func _on_runner_event_failed(event_id: String, reason: String) -> void:
	if core != null:
		core.on_event_failed(event_id, reason)


func _on_paused_changed(paused: bool) -> void:
	if paused and runner != null:
		runner.cancel_all("paused")


func _on_safe_zone_changed(in_safe: bool) -> void:
	if in_safe and runner != null:
		runner.cancel_all("safe zone")


func _on_cutscene_changed(active: bool) -> void:
	if active and runner != null:
		runner.cancel_all("cutscene")


func _on_area_exiting(_area_id: String) -> void:
	enabled = false
	if runner != null:
		runner.cancel_all("area exiting")
	if core != null:
		core.log_line("area exiting: director stopped. %s" % core.summary())


func _on_player_died() -> void:
	if core != null:
		core.on_player_died()
	if runner != null:
		runner.cancel_all("player died")


func _on_horror_event(event_id: String, _data: Dictionary) -> void:
	if not event_id.begins_with("authored:"):
		return
	if core != null:
		core.on_authored_event(event_id.substr(9))
	if runner != null:
		runner.cancel_all("authored moment")
