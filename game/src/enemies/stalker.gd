extends Node3D
## The Weaver stalker (arachnophobia: the Hollow Shade) that haunts the Silk Hollows passages.
## It never fights fair-and-square in the passage: it appears, watches, and retreats. It cannot be
## killed there (hits just drive it off).
##   setup({"route": [Vector3...], "ambush_points": [Vector3...], "zone": "silk", "normals": [...]})
## * Route points are on the ceiling/walls (authored by the dungeon). The body is oriented to the
##   surface normal at each point (upside down on ceilings); normals are probed with raycasts
##   unless given. It moves in a creepy stop-start rhythm.
## * pass_overhead(): director hook - it emerges at the far end, crawls part of the route and
##   retreats into the dark.
## * Ambush: if Krystal lingers in darkness (light < 0.25) near an ambush point for a while, it
##   emerges above her and RATTLES for 1.0 s (sound + caption) before lunging. Counterplay: dodge
##   away, raise the lantern (light >= 0.4 makes it recoil and flee) or break line of sight.
##   A lunge that connects deals data damage (18) x horror intensity multiplier, then it flees.
## * Gentle intensity: it never lunges and only shows itself at a distance.
## Swaps Weaver/Shade visuals live on Events.settings_changed("arachnophobia").

signal ambush_started
signal state_changed(new_state: String)
signal retreated

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Health := preload("res://src/combat/health.gd")
const WeaverVisual := preload("res://src/enemies/weaver_visual.gd")
const ShadeVisual := preload("res://src/enemies/shade_visual.gd")

const LINGER_RADIUS := 6.5
const DARK_THRESHOLD := 0.25
const LIGHT_REPEL := 0.4
const RATTLE_TIME := 1.0
const LUNGE_TIME := 0.45
const LAND_TIME := 0.55
const HIT_RADIUS := 1.35
const MAX_AMBUSH_REACH := 9.0
const LINGER_TIME := [999999.0, 5.0, 3.5]      # by horror intensity (Gentle never ambushes)
const AMBUSH_COOLDOWN := [999999.0, 30.0, 20.0]
const GENTLE_MIN_DIST := 10.0
const CRAWL_SPEED := 4.2
const RETREAT_SPEED := 8.0
const PASS_MAX_TIME := 7.0
const MAX_SEGMENT := 14.0          # longer gaps between consecutive route points are never crawled
const SEGMENT_CLEARANCE := 0.8     # segments are tested this far off the surface for rock in between
const RETREAT_FAR := 12.0          # a retreat ends (it slips into the dark) this far from Krystal
const CHECK_INTERVAL := 0.15
const VISIBLE_STATES := ["emerge", "pass", "rattle", "lunge", "landed", "retreat", "recoil"]

var enemy_id: String = "weaver"
var data: Dictionary = {}
var route: Array = []
var normals: Array = []
var ambush_points: Array = []
var zone: String = "silk"
var state: String = "hidden"
var state_time: float = 0.0
var health: Node
var visual: Node3D
var hit_radius: float = 0.7
var target_override: Node3D = null      # tests
var intensity_override: int = -1        # tests
var light_override: float = -1.0        # tests: replaces Combat.light_at for every query
var los_override: int = -1              # tests: 0 = blocked, 1 = clear

var _pos := Vector3.ZERO                # point on the surface the creature clings to
var _normal := Vector3.DOWN
var _path: Array = []                   # [{"pos": Vector3, "n": Vector3}]
var _path_i: int = 0
var _moving := false
var _rhythm_t: float = 0.0
var _speed: float = CRAWL_SPEED
var _linger: float = 0.0
var _cooldown: float = 0.0
var _check_t: float = 0.0
var _lunge_from := Vector3.ZERO
var _lunge_to := Vector3.ZERO
var _hit_done := false
var _normals_ready := false
var _seg_ok: Array = []                 # _seg_ok[i]: route[i] -> route[i + 1] can be crawled
var _segments_ready := false
var _using_shade := false
var _appear_scale: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(params: Dictionary) -> void:
	route = _vec_array(params.get("route", []))
	normals = _vec_array(params.get("normals", []))
	ambush_points = _vec_array(params.get("ambush_points", []))
	zone = String(params.get("zone", zone))
	_normals_ready = normals.size() == route.size() and not route.is_empty()
	_segments_ready = false


static func _vec_array(v: Variant) -> Array:
	var out: Array = []
	if v is PackedVector3Array:
		for p in (v as PackedVector3Array):
			out.append(p)
	elif v is Array:
		for p in (v as Array):
			if p is Vector3:
				out.append(p)
	return out


func _ready() -> void:
	add_to_group("stalker")
	data = ItemDB.enemy(enemy_id)
	health = Health.new()
	health.name = "Health"
	health.max_hp = float(data.get("hp", 999.0))
	health.invulnerable = true
	add_child(health)
	_rng.randomize()
	_build_visual()
	_hide_now()
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	HitFx.ensure_hitstop()


func _process(delta: float) -> void:
	tick(delta)


# --- Public API ------------------------------------------------------------------------------------

func is_threatening() -> bool:
	return state in ["rattle", "lunge", "landed"]


func is_visible_threat() -> bool:
	return state in VISIBLE_STATES


func intensity() -> int:
	return intensity_override if intensity_override >= 0 else Combat.current_intensity()


func get_aim_point() -> Vector3:
	return global_position + global_transform.basis.y * 0.5


## Director hook: a brief crawl overhead at a distance, then it retreats. Returns false if busy.
func pass_overhead() -> bool:
	if state != "hidden" or route.size() < 2:
		return false
	_ensure_normals()
	var p := _player()
	var ref := p.global_position if p != null else global_position
	# Only the connected stretch of route nearest to Krystal (it never crawls through rock between
	# stretches): emerge at the end of it farther from her and crawl a few points toward her.
	var stretch := stretch_around(nearest_route_index(ref))
	var lo: int = stretch[0]
	var hi: int = stretch[1]
	if hi <= lo:
		return false                     # an isolated point: nothing to crawl along
	var forward: bool = route[lo].distance_to(ref) >= route[hi].distance_to(ref)
	var start: int = lo if forward else hi
	var step: int = 1 if forward else -1
	if intensity() == 0 and p != null and route[start].distance_to(ref) < GENTLE_MIN_DIST:
		return false
	_path.clear()
	var i := start
	for k in _rng.randi_range(2, 4):
		i += step
		if i < lo or i > hi:
			break
		_path.append({"pos": route[i], "n": normals[i]})
	_place(route[start], normals[start])
	_enter("emerge")
	_notice_companions()
	Audio.play_3d(_snd("skitter"), _pos, -6.0, 0.1)
	return true


## Forces an immediate ambush attempt (debug / scripted beats). Returns false if not possible.
func start_ambush() -> bool:
	var p := _player()
	if p == null or state != "hidden" or intensity() == 0:
		return false
	_ensure_normals()
	var best := -1
	var best_d := MAX_AMBUSH_REACH
	for i in route.size():
		var d: float = route[i].distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	_place(route[best], normals[best])
	_path.clear()
	_enter("rattle")
	_linger = 0.0
	Audio.play_3d(_snd("rattle"), _pos, 0.0, 0.05)
	Events.caption.emit(_caption("rattle"))
	_notice_companions()
	ambush_started.emit()
	Events.horror_event.emit("authored:stalker_ambush", {"zone": zone})
	return true


## Hits never hurt it here; they drive it away.
func on_hit_blocked(_attacker: Node, _dir: Vector3) -> void:
	if state in ["rattle", "lunge", "landed", "emerge", "pass"]:
		HitFx.spark(get_aim_point())
		_retreat(true)


func knockback(_dir: Vector3, _force: float) -> void:
	pass


# --- Core update (testable) ---------------------------------------------------------------------------

func tick(delta: float) -> void:
	state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_check_t -= delta
	var check := _check_t <= 0.0
	if check:
		_check_t = CHECK_INTERVAL
	match state:
		"hidden":
			if check:
				_update_linger(CHECK_INTERVAL)
		"emerge":
			_appear_scale = minf(_appear_scale + delta / 0.35, 1.0)
			if check and _repelled_by_light():
				_recoil()
			elif state_time >= 0.35:
				_enter("pass")
		"pass":
			if check and _repelled_by_light():
				_recoil()
				return
			if check and intensity() == 0 and _dist_to_player() < GENTLE_MIN_DIST:
				_retreat(false)
				return
			_crawl(delta, true)
			if _path_i >= _path.size() or state_time > PASS_MAX_TIME:
				_retreat(false)
		"rattle":
			_appear_scale = minf(_appear_scale + delta / 0.25, 1.0)
			var tp := _player()
			if tp != null:
				_apply_transform(tp.global_position - _pos, clampf(delta * 6.0, 0.0, 1.0))   # eyes on Krystal
			if check:
				if _repelled_by_light():
					_recoil()
					return
				if not _has_los():
					_retreat(false)
					return
			if state_time >= RATTLE_TIME:
				_begin_lunge()
		"lunge":
			var k := clampf(state_time / LUNGE_TIME, 0.0, 1.0)
			var p := _lunge_from.lerp(_lunge_to, k) + Vector3.UP * sin(k * PI) * 0.8
			global_position = p
			_orient(Vector3.UP, _lunge_to - _lunge_from, delta * 8.0, true)
			if k >= 1.0:
				_land()
		"landed":
			if state_time >= LAND_TIME:
				_retreat(false)
		"retreat":
			if _path_i < _path.size():
				_appear_scale = minf(_appear_scale + delta * 4.0, 1.0)
				_crawl(delta, false)
			else:
				_fade_out_step(delta)
		"recoil":
			if state_time >= 0.6:
				_retreat(false)
	if visual != null:
		visual.scale = Vector3.ONE * maxf(_appear_scale, 0.01)


func _enter(s: String) -> void:
	state = s
	state_time = 0.0
	var vis := s in VISIBLE_STATES
	visible = vis
	if vis:
		if not is_in_group("enemy"):
			add_to_group("enemy")
	elif is_in_group("enemy"):
		remove_from_group("enemy")
	_apply_visual_state(s)
	if s == "emerge" or s == "rattle":
		_appear_scale = 0.0 if s == "emerge" else maxf(_appear_scale, 0.3)
	_moving = true
	_rhythm_t = 0.0
	state_changed.emit(s)


## Mirrors the logic state on the (swappable) visual without touching any timers.
func _apply_visual_state(s: String) -> void:
	if visual == null or not visual.has_method("set_state"):
		return
	var vs := "idle"
	match s:
		"pass", "retreat":
			vs = "move"
		"rattle":
			vs = "telegraph"
		"lunge":
			vs = "lunge"
		"recoil":
			vs = "recoil"
	visual.set_state(vs, 0.0)


func _update_linger(dt: float) -> void:
	if intensity() == 0 or _cooldown > 0.0 or route.is_empty():
		_linger = 0.0
		return
	var p := _player()
	if p == null or not _hunt_allowed(p):
		_linger = 0.0
		return
	var near := false
	for a in ambush_points:
		var d := Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
		if d <= LINGER_RADIUS:
			near = true
			break
	if near and _light(p.global_position + Vector3.UP) < DARK_THRESHOLD:
		_linger += dt
	else:
		_linger = maxf(_linger - dt * 2.0, 0.0)
	if _linger >= float(LINGER_TIME[clampi(intensity(), 0, 2)]):
		if not start_ambush():
			_linger = 0.0


func _begin_lunge() -> void:
	var p := _player()
	if p == null or intensity() == 0:
		_retreat(false)
		return
	_lunge_from = global_position
	_lunge_to = p.global_position
	_hit_done = false
	_enter("lunge")
	Audio.play_3d(_snd("skitter"), global_position, 0.0, 0.1)


func _land() -> void:
	global_position = _lunge_to
	_enter("landed")
	Audio.play_3d(_snd("drop"), _lunge_to, -2.0, 0.08)
	HitFx.burst(_lunge_to + Vector3.UP * 0.2, Color(0.75, 0.72, 0.8), 10, 2.5, 1.0, -8.0, 0.5)
	var p := _player()
	if p == null or _hit_done:
		return
	_hit_done = true
	var flat := Vector2(p.global_position.x - _lunge_to.x, p.global_position.z - _lunge_to.z).length()
	if flat <= HIT_RADIUS and absf(p.global_position.y - _lunge_to.y) < 1.6:
		var h := Combat.find_health(p)
		if h != null:
			var dir := p.global_position - _lunge_from
			dir.y = 0.0
			dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
			var dealt: float = float(h.apply_damage(lunge_damage(), self, dir))
			if dealt > 0.0:
				if p.has_method("knockback"):
					p.knockback(dir, float(data.get("knockback", 6.0)))
				Events.hitstop.emit(0.06)
				Events.camera_shake.emit(0.4, 0.25)
				HitFx.impact(p.global_position + Vector3.UP, dealt, Color(0.9, 0.85, 0.95))


func lunge_damage() -> float:
	return float(data.get("damage", 18.0)) * Combat.intensity_damage_mult(intensity())


func _recoil() -> void:
	_enter("recoil")
	Audio.play_3d(_snd("skitter"), global_position, -2.0, 0.15)
	_cooldown = maxf(_cooldown, float(AMBUSH_COOLDOWN[clampi(intensity(), 0, 2)]) * 0.5)


## Flee along the connected stretch of route, away from Krystal, then slip into the dark (never
## through rock to a disconnected part of the route).
func _retreat(quick: bool) -> void:
	if state == "hidden":
		return
	_ensure_normals()
	_path.clear()
	_path_i = 0
	var p := _player()
	var ref := p.global_position if p != null else global_position
	if not route.is_empty():
		var near_i := nearest_route_index(global_position)
		var step := _away_step(near_i, ref)
		var i := near_i
		_path.append({"pos": route[i], "n": normals[i]})
		while step != 0:
			var nxt := i + step
			if nxt < 0 or nxt >= route.size() or not segment_ok(mini(i, nxt)):
				break
			i = nxt
			_path.append({"pos": route[i], "n": normals[i]})
			if route[i].distance_to(ref) >= RETREAT_FAR:
				break
	if state == "landed" or state == "lunge":
		# On the floor: leap straight back up to the nearest route point first.
		_pos = global_position
		_normal = Vector3.UP
	_enter("retreat")
	_speed = RETREAT_SPEED * (1.3 if quick else 1.0)
	_cooldown = maxf(_cooldown, float(AMBUSH_COOLDOWN[clampi(intensity(), 0, 2)]))
	_linger = 0.0
	if quick:
		Audio.play_3d(_snd("skitter"), global_position, 0.0, 0.1)


func _fade_out_step(delta: float) -> void:
	_appear_scale -= delta * 3.0
	global_position += -_normal * delta * 0.8
	if _appear_scale <= 0.0:
		_hide_now()
		retreated.emit()


func _hide_now() -> void:
	_appear_scale = 0.0
	_path.clear()
	_path_i = 0
	_enter("hidden")


# --- Movement --------------------------------------------------------------------------------------------

func _crawl(delta: float, rhythm: bool) -> void:
	if _path_i >= _path.size():
		return
	if rhythm:
		_rhythm_t -= delta
		if _rhythm_t <= 0.0:
			_moving = not _moving
			_rhythm_t = _rng.randf_range(0.25, 0.7) if _moving else _rng.randf_range(0.35, 1.2)
			if visual != null and visual.has_method("set_state"):
				visual.set_state("move" if _moving else "idle", 0.0)
		if not _moving:
			return
	var target: Dictionary = _path[_path_i]
	var tp: Vector3 = target["pos"]
	var to := tp - _pos
	var step := _speed * delta
	if to.length() <= step:
		_pos = tp
		_normal = target["n"]
		_path_i += 1
	else:
		_pos += to.normalized() * step
		_normal = turn_normal(_normal, target["n"], to, clampf(delta * 4.0, 0.0, 1.0))
	_apply_transform(to, delta * 10.0)


## Slerps a surface normal toward `target`. Opposite normals (leaping from the floor back up to the
## ceiling after a lunge) have no slerp axis - Vector3.slerp would just lerp through zero and the
## body would stay upright, then snap upside down - so it first tips over along the travel direction.
static func turn_normal(from: Vector3, target: Vector3, travel: Vector3, weight: float) -> Vector3:
	var n := from.normalized()
	var t := target.normalized()
	if n.dot(t) < -0.95:
		var tip := travel - n * travel.dot(n)
		if tip.length_squared() < 0.0001:
			tip = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
		n = (n + tip.normalized() * 0.35).normalized()
	return n.slerp(t, weight).normalized()


func _place(p: Vector3, n: Vector3) -> void:
	_pos = p
	_normal = n
	_path_i = 0
	_apply_transform(Vector3.ZERO, 1.0)


func _apply_transform(travel: Vector3, rate: float) -> void:
	var aligned: bool = visual != null and visual.get("surface_aligned") == true
	var origin := _pos + _normal * 0.04
	if not aligned:
		var h: float = float(visual.call("body_height")) if visual != null and visual.has_method("body_height") else 1.9
		origin = _pos + _normal * 0.3
		if _normal.y < -0.5:
			origin = _pos + Vector3.DOWN * (h + 0.1)
	global_position = origin
	_orient(_normal if aligned else Vector3.UP, travel, rate, false)


## Rotates so local +Y = up and -Z faces the travel direction (projected onto the surface plane).
func _orient(up: Vector3, travel: Vector3, rate: float, _airborne: bool) -> void:
	var u := up.normalized()
	var fwd := travel - u * travel.dot(u)
	if fwd.length_squared() < 0.0001:
		fwd = -global_transform.basis.z
		fwd = fwd - u * fwd.dot(u)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD if absf(u.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		fwd = fwd - u * fwd.dot(u)
	fwd = fwd.normalized()
	var z := -fwd
	var x := u.cross(z).normalized()
	var target := Basis(x, u, z).orthonormalized()
	var cur := global_transform.basis.orthonormalized()
	var q := cur.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), clampf(rate, 0.0, 1.0))
	global_transform.basis = Basis(q)


func _ensure_normals() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	if not _normals_ready:
		_normals_ready = true
		_probe_normals(space)
	if not _segments_ready:
		_segments_ready = true
		_seg_ok.clear()
		for i in range(route.size() - 1):
			_seg_ok.append(_segment_clear(space, i))


## A route segment can be crawled when it is not too long and no world geometry lies between the
## two points (tested a little off the surface, so ceiling bumps don't count).
func _segment_clear(space: PhysicsDirectSpaceState3D, i: int) -> bool:
	var a: Vector3 = route[i]
	var b: Vector3 = route[i + 1]
	if a.distance_to(b) > MAX_SEGMENT:
		return false
	if space == null:
		return true
	var na: Vector3 = normals[i]
	var nb: Vector3 = normals[i + 1]
	var q := PhysicsRayQueryParameters3D.create(a + na * SEGMENT_CLEARANCE, b + nb * SEGMENT_CLEARANCE, 1)
	return space.intersect_ray(q).is_empty()


func segment_ok(i: int) -> bool:
	return i >= 0 and i < _seg_ok.size() and bool(_seg_ok[i])


## [lo, hi]: the run of route indices connected to `i` by crawlable segments.
func stretch_around(i: int) -> Array:
	_ensure_normals()
	if route.is_empty():
		return [0, -1]
	var lo := clampi(i, 0, route.size() - 1)
	var hi := lo
	while lo > 0 and segment_ok(lo - 1):
		lo -= 1
	while hi < route.size() - 1 and segment_ok(hi):
		hi += 1
	return [lo, hi]


func nearest_route_index(pos: Vector3) -> int:
	var best := 0
	for i in route.size():
		if route[i].distance_to(pos) < route[best].distance_to(pos):
			best = i
	return best


## +1 / -1: the connected neighbour of route[i] that leads away from `ref` (0 = nowhere farther to go).
## Never returns a neighbour that is closer to `ref`: at a chain end it fades in place instead of
## "fleeing" toward Krystal.
func _away_step(i: int, ref: Vector3) -> int:
	var best := 0
	var best_d: float = route[i].distance_to(ref)
	for s in [-1, 1]:
		var j: int = i + int(s)
		if j >= 0 and j < route.size() and segment_ok(mini(i, j)):
			var d: float = route[j].distance_to(ref)
			if d > best_d:
				best = int(s)
				best_d = d
	return best


func _probe_normals(space: PhysicsDirectSpaceState3D) -> void:
	normals.clear()
	for i in route.size():
		var p: Vector3 = route[i]
		var n := Vector3.DOWN
		if space != null:
			var best_d := INF
			for dir in [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var q := PhysicsRayQueryParameters3D.create(p - dir * 0.6, p + dir * 1.4, 1)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					var d: float = (hit["position"] as Vector3).distance_to(p)
					if d < best_d:
						best_d = d
						n = hit["normal"]
						route[i] = hit["position"]
		normals.append(n)


# --- Perception helpers ----------------------------------------------------------------------------------

func _player() -> Node3D:
	if target_override != null:
		return target_override if is_instance_valid(target_override) else null
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _hunt_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "cutscene" or Game.mode == "loading":
		return false
	var h := Combat.find_health(p)
	if h != null and h.get("dead") == true:
		return false
	var a: Node = Game.area
	if a != null and is_instance_valid(a) and a.has_method("is_safe_zone"):
		if bool(a.is_safe_zone(p.global_position)):
			return false
	return true


func _dist_to_player() -> float:
	var p := _player()
	return INF if p == null else global_position.distance_to(p.global_position)


func _light(pos: Vector3) -> float:
	return light_override if light_override >= 0.0 else Combat.light_at(pos)


func _repelled_by_light() -> bool:
	if _light(global_position) >= LIGHT_REPEL:
		return true
	# Krystal's own light only counts while it hangs right above her (the rattle). A director pass emerges
	# 20+ m away: it shrinks back only if it crawls into a lit pool itself.
	var p := _player()
	if p != null and state == "rattle" and _light(p.global_position + Vector3.UP) >= LIGHT_REPEL:
		return true
	return false


func _has_los() -> bool:
	if los_override >= 0:
		return los_override == 1
	var p := _player()
	if p == null:
		return false
	if not is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, global_position + _normal * 0.3, p.global_position + Vector3.UP * 1.0, [p], 1)


func _notice_companions() -> void:
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("notice_threat"):
			(c as Node).notice_threat(global_position)


func _on_player_died() -> void:
	if state != "hidden":
		_retreat(false)
	_linger = 0.0


# --- Visual & sounds ----------------------------------------------------------------------------------------

func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


func _build_visual() -> void:
	if visual != null:
		visual.queue_free()
		visual = null
	_using_shade = _arachno()
	visual = ShadeVisual.new() if _using_shade else WeaverVisual.new()
	visual.name = "Visual"
	add_child(visual)
	if visual.has_method("set_clinging"):
		visual.set_clinging(true)
	enemy_id = "weaver"


func _on_settings_changed(key: String) -> void:
	if key != "arachnophobia" or _using_shade == _arachno():
		return
	_build_visual()
	visual.scale = Vector3.ONE * maxf(_appear_scale, 0.01)
	if state != "hidden" and state != "lunge" and state != "landed":
		_apply_transform(Vector3.ZERO, 1.0)
	_apply_visual_state(state)


func _snd(kind: String) -> String:
	var shade := _using_shade
	match kind:
		"rattle":
			return "shade_telegraph" if shade else "weaver_rattle"
		"skitter":
			return "shade_drift" if shade else "weaver_skitter"
		"drop":
			return "hit_hard" if shade else "weaver_drop"
		"shriek":
			return "shade_shriek" if shade else "weaver_shriek"
	return kind


func _caption(kind: String) -> String:
	if kind == "rattle":
		return "[a hollow whisper right above you]" if _using_shade else "[a dry rattle right above you]"
	return ""
