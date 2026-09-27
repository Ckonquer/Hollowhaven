extends Node
## Executes horror director decisions in the world (child of director.gd).
## Kinds: sound, wrong_sound, flicker, glimpse, notice, scratch, silence, spawn, stalker_pass.
## Every executor fails gracefully: a missing module, sound, anchor, light or companion is logged and
## skipped - never an error. Delayed actions (the ambush after its warning hiss) run in _process, so
## they freeze while the game is paused and are dropped by cancel_all().
##
## execute(decision, env) -> {"ok": bool, "note": String, "pos": Vector3, "id": String, "kind": String}
##   decision: from director_core.gd tick()/force()
##   env: {"player": Node3D, "area": Node (parent for spawned things), "companion_node": Node,
##         "intensity": int, "arachnophobia": bool, "reduce_flashing": bool}
## A delayed part that fails after execute() returned ok (every ambusher blocked when the telegraph
## ends) emits event_failed so the director can roll its pacing back.

signal event_failed(event_id: String, reason: String)

const HorrorData := preload("res://data/horror_events.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Silhouette := preload("res://src/horror/silhouette.gd")

const ENEMY_FACTORY := "res://src/enemies/enemy_factory.gd"
const THREAT_GROUP := "director_threat"
const WORLD_MASK := 1 | 32
const FLICKER_RADIUS := 16.0
const GLIMPSE_MIN_DISTANCE := 12.0
const SPAWN_TELEGRAPH := 0.9          # seconds between the warning hiss and the ambush
const SPAWN_SPACING := 1.3
const SPAWN_NUDGE_RINGS := [0.9, 1.8, 2.7]   # search around a spawn anchor blocked by a prop (rubble, cart)
const SPAWN_NUDGE_DIRS := 8
const SPAWN_MAX_STEP := 0.6           # ground higher than this above the anchor = standing on a prop
const STALKER_REAL_RANGE := 28.0      # the real stalker is used only if its route passes this close...
const STALKER_HEAR_RANGE := 12.0      # ...and in view, or this close (heard right overhead)
const LIGHT_CACHE_SECONDS := 8.0

var rng := RandomNumberGenerator.new()
var log_fn: Callable = Callable()          # (String) -> void
var visibility_fn: Callable = Callable()   # (Vector3) -> bool: is this point on screen?
var min_spawn_distance: float = 9.0
var max_spawn_distance: float = 22.0
var max_threats: int = 3
var enemy_factory_override: Script = null  # tests inject a stand-in factory
var last_results: Array = []

var _clock: float = 0.0
var _pending: Array = []                   # [{"at": float, "fn": Callable, "spawns": int}]
var _pending_spawns: int = 0
var _fx: Array = []                        # silhouettes / particles alive right now
var _threats: Array = []                   # director-spawned enemies
var _dimmed: Dictionary = {}               # light instance id -> {"light", "base", "tween"}
var _light_cache: Array = []
var _light_cache_t: float = -1000.0
var _dust_mesh: SphereMesh = null


func setup(params: Dictionary) -> void:
	rng.seed = int(params.get("seed", 0))
	var lf: Variant = params.get("log", null)
	if lf is Callable:
		log_fn = lf
	var vf: Variant = params.get("visibility", null)
	if vf is Callable:
		visibility_fn = vf
	min_spawn_distance = float(HorrorData.DIRECTOR.get("min_spawn_distance", 9.0))
	max_spawn_distance = float(HorrorData.DIRECTOR.get("max_spawn_distance", 22.0))
	max_threats = int(HorrorData.DIRECTOR.get("max_active_threats", 3))


func _process(delta: float) -> void:
	_clock += delta
	if _pending.is_empty():
		return
	var due: Array = []
	var keep: Array = []
	for p in _pending:
		if float(p["at"]) <= _clock:
			due.append(p)
		else:
			keep.append(p)
	_pending = keep
	for p in due:
		_pending_spawns = maxi(_pending_spawns - int(p.get("spawns", 0)), 0)
		var fn: Callable = p["fn"]
		if fn.is_valid():
			fn.call()


# --- Public API ------------------------------------------------------------------------------

func execute(decision: Dictionary, env: Dictionary) -> Dictionary:
	var id := String(decision.get("event_id", ""))
	var ev: Dictionary = decision.get("event", {})
	var kind := String(decision.get("kind", ""))
	if kind == "" and not ev.is_empty():
		kind = String(ev.get("kind", ""))
	_prune_fx()
	var res: Dictionary
	if id == "" or ev.is_empty():
		res = _fail("empty decision")
	else:
		match kind:
			"sound", "wrong_sound":
				res = _run_sound(decision, ev, env, kind == "wrong_sound")
			"flicker":
				res = _run_flicker(decision, ev, env)
			"glimpse":
				res = _run_glimpse(decision, ev, env)
			"notice":
				res = _run_notice(decision, ev, env)
			"scratch":
				res = _run_scratch(decision, ev, env)
			"silence":
				res = _run_silence(decision, ev, env)
			"spawn":
				res = _run_spawn(decision, ev, env)
			"stalker_pass":
				res = _run_stalker_pass(decision, ev, env)
			_:
				res = _fail("unknown event kind '%s'" % kind)
	res["id"] = id
	res["kind"] = kind
	last_results.append(res)
	while last_results.size() > 24:
		last_results.pop_front()
	_log("  -> %s %s: %s" % [id, "done" if bool(res["ok"]) else "skipped", String(res["note"])])
	return res


## Drops pending actions, fades out live effects and restores dimmed lights. Spawned enemies stay
## (they are real enemies now); the ambush that has only hissed so far is called off.
func cancel_all(reason: String = "") -> void:
	var n := _pending.size()
	_pending.clear()
	_pending_spawns = 0
	var fx := 0
	for node in _fx:
		if is_instance_valid(node):
			fx += 1
			if node.has_method("cancel"):
				node.cancel()
			else:
				node.queue_free()
	_fx.clear()
	var lights := _dimmed.size()
	restore_lights()
	if n + fx + lights > 0:
		_log("cancelled %d pending, %d effects, %d lights (%s)" % [n, fx, lights, reason])


## Director-spawned enemies still alive (plus ambushes that are about to spawn).
func active_threat_count() -> int:
	_prune_threats()
	return _threats.size() + _pending_spawns


func tracked_threats() -> Array:
	_prune_threats()
	return _threats.duplicate()


## Removes director-spawned enemies that are far from the player and not hunting (director calm).
func despawn_far(player_pos: Vector3, distance: float) -> int:
	_prune_threats()
	var removed := 0
	for e in _threats.duplicate():
		var n3 := e as Node3D
		if n3 == null:
			continue
		if n3.global_position.distance_to(player_pos) < distance:
			continue
		if n3.has_method("is_threatening") and bool(n3.is_threatening()):
			continue
		if visibility_fn.is_valid() and bool(visibility_fn.call(n3.global_position)):
			continue
		_threats.erase(e)
		n3.queue_free()
		removed += 1
	if removed > 0:
		_log("despawned %d far director threat(s)" % removed)
	return removed


func restore_lights() -> void:
	for key in _dimmed:
		var rec: Dictionary = _dimmed[key]
		var tw: Variant = rec.get("tween")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		var l: Variant = rec.get("light")
		if is_instance_valid(l) and l is Light3D:
			(l as Light3D).light_energy = float(rec["base"])
	_dimmed.clear()


func pending_count() -> int:
	return _pending.size()


## Live effects only (silhouettes and dust free themselves when done).
func _prune_fx() -> void:
	var keep: Array = []
	for node in _fx:
		if is_instance_valid(node) and not (node as Node).is_queued_for_deletion():
			keep.append(node)
	_fx = keep


# --- Executors ---------------------------------------------------------------------------------

func _run_sound(decision: Dictionary, ev: Dictionary, env: Dictionary, wrong: bool) -> Dictionary:
	var arach := bool(env.get("arachnophobia", false))
	var sname := _sound_name(ev, arach)
	var pos := _event_position(decision, env, 7.0)
	var vol := _trim_db(env)
	if wrong:
		vol -= 3.0                       # familiar, but far away and not quite right
	if not _play_3d(sname, pos, vol, 0.03 if wrong else 0.08):
		return _fail("sound '%s' missing" % sname)
	_caption(_caption_text(ev, arach))
	if wrong:
		var comp: Variant = env.get("companion_node")
		if is_instance_valid(comp) and comp is Node and (comp as Node).has_method("react"):
			_schedule(0.8, _companion_react.bind(comp, "scared"))
	return _ok("played %s" % sname, pos)


func _run_flicker(_decision: Dictionary, ev: Dictionary, env: Dictionary) -> Dictionary:
	var ppos := _player_pos(env)
	var seconds := rng.randf_range(1.2, 2.0)
	var n := 0
	for node in get_tree().get_nodes_in_group("flicker_light"):
		if is_instance_valid(node) and node is Node3D and node.has_method("flicker"):
			if (node as Node3D).global_position.distance_to(ppos) <= FLICKER_RADIUS:
				node.flicker(seconds)
				n += 1
	var how := "flicker_light"
	if n == 0:
		how = "dimmed"
		var gentle := bool(env.get("reduce_flashing", false))
		for l in _nearby_lights(ppos, env):
			_dim_light(l, seconds, gentle)
			n += 1
	if n == 0:
		return _fail("no lights near the player")
	_play_3d(_sound_name(ev, false), ppos + Vector3.UP * 1.6, _trim_db(env) - 4.0, 0.1)
	_caption(_caption_text(ev, bool(env.get("arachnophobia", false))))
	return _ok("%s %d light(s) for %.1fs" % [how, n, seconds], ppos)


func _run_glimpse(decision: Dictionary, _ev: Dictionary, env: Dictionary) -> Dictionary:
	var anchor: Dictionary = decision.get("anchor", {})
	if anchor.is_empty() or not anchor.get("pos") is Vector3:
		return _fail("no doorway anchor")
	var pos: Vector3 = anchor["pos"]
	var player := _player(env)
	if player != null and pos.distance_to(player.global_position) < GLIMPSE_MIN_DISTANCE:
		return _fail("doorway too close (%.1fm)" % pos.distance_to(player.global_position))
	# Doorway anchors sit a little above the floor: stand the figure on the ground.
	var floor_hit: Variant = _ground_below(pos, 1.0, 2.0)
	if floor_hit is Vector3:
		pos = floor_hit
	var parent := _fx_parent(env)
	if parent == null:
		return _fail("no scene to show the glimpse in")
	var variant: String = "shade" if bool(env.get("arachnophobia", false)) else "spider"
	var sil: Node3D = Silhouette.new()
	sil.setup({"variant": variant, "mode": "glimpse", "duration": rng.randf_range(0.8, 1.2),
		"target": player, "slip_dir": _slip_direction(pos, player)})
	parent.add_child(sil)
	sil.global_position = pos
	_fx.append(sil)
	_stinger("stinger_soft", env, -3.0)
	return _ok("%s glimpse at %s" % [variant, String(anchor.get("name", "doorway"))], pos)


func _run_notice(decision: Dictionary, ev: Dictionary, env: Dictionary) -> Dictionary:
	var comp: Variant = env.get("companion_node")
	if not is_instance_valid(comp) or not (comp is Node):
		return _fail("companion not present")
	var needs := String(ev.get("needs_companion", ""))
	var cid: Variant = (comp as Node).get("companion_id")
	if needs != "" and cid != null and String(cid) != needs:
		return _fail("companion is not %s" % needs)
	if not (comp as Node).has_method("notice_threat"):
		return _fail("companion has no notice_threat()")
	var pos := _event_position(decision, env, 14.0)
	comp.notice_threat(pos)
	_caption(_caption_text(ev, bool(env.get("arachnophobia", false))))
	return _ok("%s notices something" % needs, pos)


func _run_scratch(decision: Dictionary, ev: Dictionary, env: Dictionary) -> Dictionary:
	var anchor: Dictionary = decision.get("anchor", {})
	if anchor.is_empty() or not anchor.get("pos") is Vector3:
		return _fail("no ceiling anchor")
	var pos: Vector3 = anchor["pos"]
	var arach := bool(env.get("arachnophobia", false))
	var sname := _sound_name(ev, arach)
	var heard := _play_3d(sname, pos, _trim_db(env), 0.08)
	if heard:
		_caption(_caption_text(ev, arach))
	var dusted := _spawn_dust(pos, env)
	if not heard and not dusted:
		return _fail("sound '%s' missing and nowhere to drop dust" % sname)
	return _ok("scratching above%s%s" % ["" if heard else " (sound missing)", " + dust" if dusted else ""], pos)


func _run_silence(_decision: Dictionary, ev: Dictionary, env: Dictionary) -> Dictionary:
	if not Audio.has_method("duck_ambience"):
		return _fail("Audio.duck_ambience unavailable")
	Audio.duck_ambience(-18.0, 12.0)
	_caption(_caption_text(ev, bool(env.get("arachnophobia", false))))
	return _ok("ambience ducked -18 dB for 12 s", _player_pos(env))


func _run_spawn(decision: Dictionary, ev: Dictionary, env: Dictionary) -> Dictionary:
	var enemy_id := String(ev.get("enemy", "gloomling"))
	var factory := _enemy_factory()
	if factory == null:
		return _fail("enemy module missing (%s)" % ENEMY_FACTORY)
	var anchor: Dictionary = decision.get("anchor", {})
	if anchor.is_empty() or not anchor.get("pos") is Vector3:
		return _fail("no spawn anchor")
	var count := clampi(int(decision.get("count", 1)), 1, max_threats)
	var room := max_threats - active_threat_count()
	if room <= 0:
		return _fail("threat budget full")
	count = mini(count, room)
	var player := _player(env)
	var check := _find_spawn_point(anchor, player, env, true)
	if not bool(check["ok"]):
		return _fail("anchor %s rejected: %s" % [String(anchor.get("name", "?")), String(check["reason"])])
	var ground: Vector3 = check["pos"]
	if float(check.get("nudged", 0.0)) > 0.0:
		_log("  spawn anchor %s is blocked; using a clear spot %.1fm away" % [String(anchor.get("name", "?")), float(check["nudged"])])
	# Fair warning first: a hiss from the dark, then the ambush a moment later.
	var arach := bool(env.get("arachnophobia", false))
	if _play_3d(_sound_name(ev, arach), ground + Vector3.UP * 0.8, _trim_db(env), 0.06):
		_caption(_caption_text(ev, arach))
	_pending_spawns += count
	_pending.append({"at": _clock + SPAWN_TELEGRAPH, "spawns": count,
		"fn": _do_spawn.bind(factory, enemy_id, ground, count, env, String(decision.get("event_id", "")))})
	return _ok("ambush of %d %s telegraphed at %s" % [count, enemy_id, String(anchor.get("name", "?"))], ground)


func _run_stalker_pass(decision: Dictionary, ev: Dictionary, env: Dictionary) -> Dictionary:
	var arach := bool(env.get("arachnophobia", false))
	var ppos := _player_pos(env)
	var best: Node = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("stalker"):
		if is_instance_valid(s) and s is Node3D and s.has_method("pass_overhead"):
			var dd := _stalker_distance(s as Node3D, ppos)
			if dd < best_d:
				best_d = dd
				best = s
	# The real stalker only when its route passes where Krystal can see or hear it; otherwise its crawl
	# would happen out of view while the caption, sting and shake claim something is overhead (the
	# silhouette stands in at the nearby ceiling anchor instead).
	if best != null and best_d <= STALKER_REAL_RANGE and _stalker_perceivable(best as Node3D, ppos):
		var passed: Variant = best.pass_overhead()
		if passed is bool and not bool(passed):
			return _fail("the stalker is busy")
		_caption(_caption_text(ev, arach))
		_stinger("stinger_major", env, -2.0)
		Events.camera_shake.emit(0.12, 0.5)      # consumers scale by reduce_shake
		return _ok("stalker passes overhead", (best as Node3D).global_position)
	# Fallback: a silhouette crosses the ceiling anchor, left to right across the player's view.
	var anchor: Dictionary = decision.get("anchor", {})
	if anchor.is_empty() or not anchor.get("pos") is Vector3:
		return _fail("no stalker and no ceiling anchor")
	var parent := _fx_parent(env)
	if parent == null:
		return _fail("no scene for the crossing")
	var pos: Vector3 = anchor["pos"]
	if not _perceivable(pos + Vector3.DOWN * 0.8, ppos):
		return _fail("ceiling %s is out of sight and earshot" % String(anchor.get("name", "anchor")))
	var side := _facing(env).cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	if rng.randf() < 0.5:
		side = -side
	var path := _crossing_path(pos, side, _facing(env))
	if path.is_empty():
		return _fail("no room to cross the ceiling at %s" % String(anchor.get("name", "ceiling")))
	var from: Vector3 = path[0]
	var to: Vector3 = path[1]
	var sil: Node3D = Silhouette.new()
	sil.setup({"variant": "shade" if arach else "spider", "mode": "cross", "to": to,
		"duration": clampf(from.distance_to(to) / 4.5, 1.0, 2.2), "ceiling": true})
	parent.add_child(sil)
	sil.global_position = from
	_fx.append(sil)
	if _play_3d(_sound_name(ev, arach), pos, _trim_db(env), 0.06):
		_caption(_caption_text(ev, arach))
	_stinger("stinger_major", env, -2.0)
	Events.camera_shake.emit(0.12, 0.5)          # consumers scale by reduce_shake
	return _ok("silhouette crosses the ceiling at %s" % String(anchor.get("name", "ceiling")), pos)


# --- Spawning ------------------------------------------------------------------------------------

func _do_spawn(factory: Script, enemy_id: String, ground: Vector3, count: int, env: Dictionary, event_id: String = "") -> void:
	var player := _player(env)
	var parent := _fx_parent(env)
	if parent == null:
		_log("  ambush called off: no scene")
		event_failed.emit(event_id, "no scene for the ambush")
		return
	var toward := Vector3.FORWARD
	if player != null:
		toward = player.global_position - ground
		toward.y = 0.0
	var side := Vector3.UP.cross(toward)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var spawned := 0
	for i in count:
		if active_threat_count() >= max_threats:
			break
		var offset := Vector3.ZERO
		if i > 0:
			var sgn: float = 1.0 if i % 2 == 1 else -1.0
			offset = side * SPAWN_SPACING * sgn * floorf(float(i + 1) * 0.5)
		var check := _validate_spawn_point(ground + offset, player)
		if not bool(check["ok"]):
			_log("  ambush spawn %d skipped: %s" % [i, String(check["reason"])])
			continue
		var p: Vector3 = check["pos"]
		var xform := Transform3D(Basis.IDENTITY, p)
		if player != null:
			var look := player.global_position - p
			look.y = 0.0
			if look.length_squared() > 0.0001:
				xform.basis = Basis(Vector3.UP, atan2(look.x, look.z))
		var node: Variant = factory.spawn(enemy_id, parent, xform, {"alert": true})
		if is_instance_valid(node) and node is Node:
			(node as Node).set_meta("director_spawned", true)
			(node as Node).add_to_group(THREAT_GROUP)
			_threats.append(node)
			spawned += 1
		else:
			_log("  enemy factory returned nothing for '%s'" % enemy_id)
	if spawned > 0:
		_stinger("stinger_soft", env, 0.0)
	_log("  ambush: %d/%d %s spawned" % [spawned, count, enemy_id])
	if spawned == 0 and count > 0:
		event_failed.emit(event_id, "every ambush spot was blocked or in view when the telegraph ended")


## Debug/QA: can this spawn anchor ever be used? Same checks and nudge as a real ambush, minus the
## player distance and visibility. Returns {ok, reason, pos, nudged}.
func probe_spawn_anchor(anchor: Dictionary, env: Dictionary) -> Dictionary:
	if not anchor.get("pos") is Vector3:
		return {"ok": false, "reason": "anchor has no position"}
	return _find_spawn_point(anchor, null, env, false)


## The spawn anchor itself, or - when a prop (rubble, a cart) blocks it or it hangs over a gap - the
## nearest clear spot around it in the same room, preferring the side facing the player (open
## floor). Every candidate passes the full _validate_spawn_point() rules.
func _find_spawn_point(anchor: Dictionary, player: Node3D, env: Dictionary, check_visibility: bool) -> Dictionary:
	var pos: Vector3 = anchor["pos"]
	var first := _validate_spawn_point(pos, player, check_visibility)
	if bool(first["ok"]):
		return first
	var why := String(first["reason"])
	if not (why.begins_with("inside geometry") or why.begins_with("no ground")):
		return first
	var base := 0.0
	if player != null:
		var to := player.global_position - pos
		if Vector2(to.x, to.z).length_squared() > 0.0001:
			base = atan2(to.z, to.x)
	var area: Variant = env.get("area")
	for r in SPAWN_NUDGE_RINGS:
		for k in SPAWN_NUDGE_DIRS:
			# 0, +1, -1, +2, -2 ... steps around the ring, starting toward the player.
			var step: int = ((k + 1) >> 1) if k % 2 == 1 else -(k >> 1)
			var a := base + TAU * float(step) / float(SPAWN_NUDGE_DIRS)
			var c := pos + Vector3(cos(a), 0.0, sin(a)) * float(r)
			if not _same_space(area, pos, c):
				continue
			var chk := _validate_spawn_point(c, player, check_visibility)
			if bool(chk["ok"]):
				chk["nudged"] = float(r)
				return chk
	first["reason"] = why + "; no clear spot within %.1fm" % float(SPAWN_NUDGE_RINGS[SPAWN_NUDGE_RINGS.size() - 1])
	return first


## A nudged spawn spot must stay in the anchor's room (never through a wall into the next space).
## Uses the area's optional get_room_at(pos), else its zones; without either, anything goes.
func _same_space(area: Variant, anchor_pos: Vector3, candidate: Vector3) -> bool:
	if not (is_instance_valid(area) and area is Node):
		return true
	var a := area as Node
	if a.has_method("get_room_at"):
		var ra := String(a.get_room_at(anchor_pos + Vector3.UP * 0.5))
		if ra != "":
			return String(a.get_room_at(candidate + Vector3.UP * 0.5)) == ra
	if a.has_method("get_zone_at"):
		return String(a.get_zone_at(candidate)) == String(a.get_zone_at(anchor_pos))
	return true


## Spawn point must be: within the distance band, off screen, on the ground and not inside geometry.
func _validate_spawn_point(pos: Vector3, player: Node3D, check_visibility: bool = true) -> Dictionary:
	if player != null:
		var d := pos.distance_to(player.global_position)
		if d < min_spawn_distance:
			return {"ok": false, "reason": "too close (%.1fm)" % d}
		if d > max_spawn_distance + 2.0:
			return {"ok": false, "reason": "too far (%.1fm)" % d}
	var space := _space()
	if space == null:
		return {"ok": false, "reason": "no physics space"}
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 3.0, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "no ground under the anchor"}
	var ground: Vector3 = hit["position"]
	if ground.y > pos.y + SPAWN_MAX_STEP:
		return {"ok": false, "reason": "inside geometry (a prop stands on the anchor)"}
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.9)
	sq.collision_mask = WORLD_MASK
	if not space.intersect_shape(sq, 1).is_empty():
		return {"ok": false, "reason": "inside geometry"}
	if check_visibility:
		for probe in [ground + Vector3.UP * 0.4, ground + Vector3.UP * 1.3]:
			if visibility_fn.is_valid() and bool(visibility_fn.call(probe)):
				return {"ok": false, "reason": "visible to the player"}
	return {"ok": true, "pos": ground + Vector3.UP * 0.05, "reason": ""}


## Floor point below `pos` (searching `up` above it to `down` below it), or null.
func _ground_below(pos: Vector3, up: float, down: float) -> Variant:
	var space := _space()
	if space == null:
		return null
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * up, pos + Vector3.DOWN * down, WORLD_MASK))
	if hit.is_empty():
		return null
	return hit["position"]


## A major "overhead" cue is only fair if Krystal can perceive it: in view, or close enough to hear.
func _perceivable(point: Vector3, ppos: Vector3) -> bool:
	if point.distance_to(ppos) <= STALKER_HEAR_RANGE:
		return true
	return visibility_fn.is_valid() and bool(visibility_fn.call(point))


## Some point of the stalker's route (just under the ceiling) can be seen or heard from here.
func _stalker_perceivable(s: Node3D, ppos: Vector3) -> bool:
	var r: Variant = s.get("route")
	var pts: Array = []
	if r is Array or r is PackedVector3Array:
		for p in r:
			if p is Vector3:
				pts.append(p)
	if pts.is_empty():
		pts.append(s.global_position)
	for p in pts:
		var v := p as Vector3
		if v.distance_to(ppos) <= STALKER_REAL_RANGE and _perceivable(v + Vector3.DOWN * 0.5, ppos):
			return true
	return false


## Closest approach of a stalker's ceiling route to the player (its node position if no route).
func _stalker_distance(s: Node3D, ppos: Vector3) -> float:
	var best := s.global_position.distance_to(ppos)
	var r: Variant = s.get("route")
	if r is Array or r is PackedVector3Array:
		for p in r:
			if p is Vector3:
				best = minf(best, (p as Vector3).distance_to(ppos))
	return best


## Start/end of a ceiling crossing through open space: up to 5 m each way along `side`, stopping
## short of walls (so nothing clips through rock in narrow tunnels); falls back to `forward` when the
## tunnel is too narrow sideways. Returns [] when there is no room at all.
func _crossing_path(pos: Vector3, side: Vector3, forward: Vector3) -> Array:
	var space := _space()
	var probe := pos + Vector3.DOWN * 0.6        # the figure hangs below the ceiling surface
	for dir in [side, forward]:
		var d := dir as Vector3
		if d.length_squared() < 0.0001:
			continue
		var a := _clear_extent(space, probe, -d, 5.0)
		var b := _clear_extent(space, probe, d, 5.0)
		if a + b >= 3.0:
			return [pos - d * a, pos + d * b]
	return []


func _clear_extent(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_dist: float) -> float:
	if space == null:
		return max_dist
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return max_dist
	return maxf(from.distance_to(hit["position"]) - 0.8, 0.0)


func _enemy_factory() -> Script:
	if enemy_factory_override != null:
		return enemy_factory_override
	if not ResourceLoader.exists(ENEMY_FACTORY):
		return null
	var s: Variant = load(ENEMY_FACTORY)
	if not (s is Script) or not (s as Script).can_instantiate():
		return null
	if not (s as Script).has_method("spawn"):
		return null
	return s


func _prune_threats() -> void:
	var keep: Array = []
	for e in _threats:
		if not is_instance_valid(e) or not (e as Node).is_inside_tree() or (e as Node).is_queued_for_deletion():
			continue
		var h: Variant = (e as Node).get("health")
		if is_instance_valid(h) and h is Object and bool((h as Object).get("dead")):
			continue
		keep.append(e)
	_threats = keep


# --- Effects ---------------------------------------------------------------------------------------

func _spawn_dust(pos: Vector3, env: Dictionary) -> bool:
	var parent := _fx_parent(env)
	if parent == null:
		return false
	if _dust_mesh == null:
		_dust_mesh = SphereMesh.new()
		_dust_mesh.radius = 0.02
		_dust_mesh.height = 0.04
		_dust_mesh.radial_segments = 6
		_dust_mesh.rings = 3
	var p := CPUParticles3D.new()
	p.name = "ScratchDust"
	p.one_shot = true
	p.emitting = false
	p.amount = 26
	p.lifetime = 2.4
	p.explosiveness = 0.55
	p.randomness = 0.5
	p.mesh = _dust_mesh
	p.material_override = Mat.toon(Palette.DIRT, {"rim": 0.1, "noise": 0.0})
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.DOWN
	p.spread = 20.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0.0, -0.9, 0.0)
	p.damping_min = 0.2
	p.damping_max = 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	# A couple of tiny pebbles for the eye to follow (duplicated before any signal is connected).
	var pb := p.duplicate() as CPUParticles3D
	parent.add_child(p)
	p.global_position = pos + Vector3.DOWN * 0.15
	p.emitting = true
	p.finished.connect(p.queue_free)
	_fx.append(p)
	pb.name = "ScratchPebbles"
	pb.amount = 3
	pb.lifetime = 1.0
	pb.explosiveness = 0.8
	pb.scale_amount_min = 1.8
	pb.scale_amount_max = 2.6
	pb.gravity = Vector3(0.0, -6.0, 0.0)
	pb.material_override = Mat.toon(Palette.MINE_ROCK)
	parent.add_child(pb)
	pb.global_position = pos + Vector3.DOWN * 0.15
	pb.emitting = true
	pb.finished.connect(pb.queue_free)
	_fx.append(pb)
	return true


func _nearby_lights(ppos: Vector3, env: Dictionary) -> Array:
	if _clock - _light_cache_t > LIGHT_CACHE_SECONDS or _light_cache.is_empty():
		_light_cache_t = _clock
		_light_cache = []
		var root := _fx_parent(env)
		if root != null:
			for l in root.find_children("*", "OmniLight3D", true, false):
				_light_cache.append(l)
			for l in root.find_children("*", "SpotLight3D", true, false):
				_light_cache.append(l)
	var out: Array = []
	for l in _light_cache:
		if not is_instance_valid(l):
			continue
		var light := l as Light3D
		if not light.is_visible_in_tree() or (light.light_energy <= 0.01 and not _dimmed.has(light.get_instance_id())):
			continue
		if light.global_position.distance_to(ppos) <= FLICKER_RADIUS:
			out.append(light)
	return out


## Smoothly dips a light a few times and restores it. Gentle (reduce_flashing): one slow dip.
func _dim_light(light: Light3D, seconds: float, gentle: bool) -> void:
	var key := light.get_instance_id()
	var base := light.light_energy
	if _dimmed.has(key):
		var rec: Dictionary = _dimmed[key]
		base = float(rec["base"])
		var old: Variant = rec.get("tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := light.create_tween()
	if gentle:
		tw.tween_property(light, "light_energy", base * 0.55, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(maxf(seconds - 1.3, 0.2))
		tw.tween_property(light, "light_energy", base, 0.8).set_trans(Tween.TRANS_SINE)
	else:
		var steps := 6
		for i in steps:
			var f: float = rng.randf_range(0.12, 0.55) if i % 2 == 0 else rng.randf_range(0.6, 0.95)
			tw.tween_property(light, "light_energy", base * f, seconds / float(steps) * rng.randf_range(0.6, 1.0)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(light, "light_energy", base, 0.4).set_trans(Tween.TRANS_SINE)
	tw.finished.connect(_on_light_restored.bind(key))
	_dimmed[key] = {"light": light, "base": base, "tween": tw}


func _on_light_restored(key: int) -> void:
	_dimmed.erase(key)


# --- Helpers ----------------------------------------------------------------------------------------

func _sound_name(ev: Dictionary, arach: bool) -> String:
	if arach and bool(ev.get("spider", false)) and String(ev.get("alt_sound", "")) != "":
		return String(ev["alt_sound"])
	return String(ev.get("sound", ""))


func _caption_text(ev: Dictionary, arach: bool) -> String:
	if arach and bool(ev.get("spider", false)) and String(ev.get("alt_caption", "")) != "":
		return String(ev["alt_caption"])
	return String(ev.get("caption", ""))


func _caption(text: String) -> void:
	if text != "":
		Events.caption.emit(text)


func _play_3d(sname: String, pos: Vector3, vol_db: float, pitch_var: float) -> bool:
	if sname == "" or not Audio.has_sound(sname):
		return false
	Audio.play_3d(sname, pos, vol_db, pitch_var, 40.0)
	return true


## Non-diegetic sting at the intensity's stinger volume (never ear-splitting; master has a limiter).
func _stinger(sname: String, env: Dictionary, extra_db: float) -> void:
	if not Audio.has_sound(sname):
		return
	var itab: Dictionary = HorrorData.INTENSITY.get(clampi(int(env.get("intensity", 1)), 0, 2), {})
	Audio.play_sfx(sname, float(itab.get("stinger_db", -6.0)) + extra_db, 0.03)


func _trim_db(env: Dictionary) -> float:
	return -3.0 if int(env.get("intensity", 1)) == 0 else 0.0


func _player(env: Dictionary) -> Node3D:
	var p: Variant = env.get("player")
	if is_instance_valid(p) and p is Node3D and (p as Node3D).is_inside_tree():
		return p
	return null


func _player_pos(env: Dictionary) -> Vector3:
	var p := _player(env)
	return p.global_position if p != null else Vector3.ZERO


func _facing(env: Dictionary) -> Vector3:
	var p := _player(env)
	if p == null:
		return Vector3.FORWARD
	var f := Vector3.ZERO
	if p.has_method("get_facing"):
		var v: Variant = p.get_facing()
		if v is Vector3:
			f = v
	if f.length_squared() < 0.0001:
		f = -p.global_basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.FORWARD
	return f.normalized()


## The chosen anchor's position, or somewhere behind / beside the player (sounds you can't see).
func _event_position(decision: Dictionary, env: Dictionary, dist: float) -> Vector3:
	var anchor: Dictionary = decision.get("anchor", {})
	if anchor.get("pos") is Vector3:
		return anchor["pos"]
	var f := _facing(env)
	var right := f.cross(Vector3.UP).normalized()
	var back := -f * rng.randf_range(dist * 0.8, dist * 1.3)
	var side := right * rng.randf_range(-dist * 0.6, dist * 0.6)
	return _player_pos(env) + back + side + Vector3.UP * 1.4


func _slip_direction(pos: Vector3, player: Node3D) -> Vector3:
	var slip := Vector3.RIGHT
	if player != null:
		var to := player.global_position - pos
		to.y = 0.0
		if to.length_squared() > 0.0001:
			slip = Vector3.UP.cross(to).normalized()
	if rng.randf() < 0.5:
		slip = -slip
	return slip


func _fx_parent(env: Dictionary) -> Node:
	var a: Variant = env.get("area")
	if is_instance_valid(a) and a is Node and (a as Node).is_inside_tree():
		return a
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_parent()


func _space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	return w.direct_space_state if w != null else null


func _schedule(delay: float, fn: Callable) -> void:
	_pending.append({"at": _clock + delay, "fn": fn, "spawns": 0})


func _companion_react(comp: Variant, reaction: String) -> void:
	if is_instance_valid(comp) and comp is Node and (comp as Node).has_method("react"):
		comp.react(reaction)


func _ok(note: String, pos: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"ok": true, "note": note, "pos": pos}


func _fail(note: String) -> Dictionary:
	return {"ok": false, "note": note, "pos": Vector3.ZERO}


func _log(text: String) -> void:
	if log_fn.is_valid():
		log_fn.call(text)
