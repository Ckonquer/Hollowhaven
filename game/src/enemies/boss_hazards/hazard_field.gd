extends Node3D
## The Weaver Matron's floor hazards (MP section 8, phases 2-3) - owned and ticked by weaver_boss.gd.
## One node per encounter (child of the boss, top_level, world coordinates). It owns:
##   * web fans (web_fan.gd)      narrow telegraphed sheets that SLOW (bounded; never root)
##   * trip-lines (trip_line.gd)  between FIXED floor anchors (the posts, always visible while the
##                                Matron lives): snag = small slow + a little damage; cut / burn them
##   * egg sacs (egg_sac.gd)      late phase 2: shake, then release capped small minions (EnemyFactory
##                                id "brood_skitter", guarded) - never underfoot, never during a pounce
##   * the thread (boss_thread.gd) phase 3 brazier channel (the boss drives it)
## Caps: `cap` live fans+lines (set by the boss per phase/intensity; the oldest expires early), sacs
## per release, minions alive (MINION_CAP by intensity). Everything expires on its own and
## clear_all() removes it at once (phase transition, reset, defeat).
## The SLOW goes through GameState buff "slow" (docs/CHAPTER_TWO_SPEC.md section 9): the multiplier never
## drops below SLOW_FLOOR, a buff never outlasts SLOW_MAX_SECONDS, and after SLOW_CHAIN_CAP seconds of
## continuous slowing Krystal pulls free for SLOW_IMMUNE seconds (no permanent chaining). It is a bounded ZONE
## slow refreshed while she stands in a sheet, so it writes the buff directly, tagged "source": SLOW_SOURCE:
## the field only ever refreshes or erases ITS OWN slow (another source's slow is never overwritten, stacked or
## cleared). A cleanse while she is still in a sheet (Mochi's Bloomguard removes the buff) starts the same
## SLOW_IMMUNE break-free window, so the sheet cannot re-apply it on the next frame. A sheet never slows her
## while she is airborne (a jump over / through it; web_fan.slows()).
## Arachnophobia: every hazard swaps to the pale veil / root / pod look live (settings_changed).
## High-visibility cues (Settings "high_visibility_cues"): every hazard adds a bold cream outline, live.
## Pure helpers used by tests: default_posts, default_chords, route_exists, cap_for.

signal minion_spawned(minion: Node)
signal line_cut(how: String)

const WebFan := preload("res://src/enemies/boss_hazards/web_fan.gd")
const TripLine := preload("res://src/enemies/boss_hazards/trip_line.gd")
const EggSac := preload("res://src/enemies/boss_hazards/egg_sac.gd")
const BossThread := preload("res://src/enemies/boss_hazards/boss_thread.gd")
const Art := preload("res://src/enemies/boss_hazards/hazard_art.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

## Live fans + lines by phase: [Gentle, Standard, Intense]. Phase 3 = ONE ground hazard at a time.
const HAZARD_CAP := {2: [2, 3, 3], 3: [1, 1, 1]}
const TRIP_PER_CAST := [1, 2, 2]
const MINION_CAP := [1, 2, 2]
const FAN_HALF_DEG := [10.0, 12.0, 13.0]
const FAN_MIN_LEN := 5.0
const FAN_MAX_LEN := 9.0
const FAN_LIFE := [6.0, 7.0, 7.5]
const TRIP_LIFE := [10.0, 12.0, 12.0]
const FAN_SLOW := [0.7, 0.6, 0.55]
const SNAG_SLOW := [0.7, 0.55, 0.5]
const SNAG_SLOW_TIME := 1.2
const SNAG_DAMAGE := 6.0
const SNAG_DIST := 0.4
const SNAG_MAX_RISE := 0.5        # above the floor (a jump) clears a line
const SLOW_FLOOR := 0.5
const SLOW_LINGER := 0.5
const SLOW_MAX_SECONDS := 1.5
const SLOW_CHAIN_CAP := 3.0
const SLOW_IMMUNE := 2.0
const SLOW_SOURCE := "matron_field"   # tag of the field's own slow buff (only this one is refreshed / erased)
const CLEANSE_MARGIN := 0.05          # own slow missing although this much of it was left = removed (a cleanse)
const POST_RADIUS_FRAC := 0.62
const POST_COUNT := 6
const ENTRANCE_CLEAR := 3.0       # no line within this of the entrance point
const TRIP_MIN_PLAYER_DIST := 1.2 # a line never appears right under Krystal
const SAC_EDGE_INSET := 2.0
const SAC_MIN_PLAYER_DIST := 5.0
const SAC_CLEAR_DIST := 2.5       # a sac waits while Krystal stands this close (never underfoot)
const SAC_MAX_DELAY := 4.0        # ...and withers harmlessly if she camps on it that long
const SAC_SEPARATION := 3.0
const ROUTE_CELL := 0.4
const ROUTE_CLEARANCE := 0.35
const CENTRE_OBSTACLE := 1.0
const DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const ESCAPE_RAYS := 72
const MINION_REACH_MARGIN := 1.5  # a minion farther than radius + this from the centre is out of reach
const MINION_REACH_RISE := 1.5    # ...or this far above / below the floor (a ledge, a hole)

var boss: Node = null
var center := Vector3.ZERO
var radius: float = 11.5
var floor_y: float = 0.0
var intensity: int = 1
var cap: int = 3
var posts: Array = []             # floor points (Vector3) of the fixed trip-line anchors
var chords: Array = []            # [i, j] post pairs a line may span
var obstacles: Array = []         # [[Vector3, radius], ...] solid floor things for the route check
var entrance := Vector3.ZERO
var has_entrance := false
var hazards: Array = []           # fans + lines, oldest first
var sacs: Array = []
var minions: Array = []
var thread: Node3D = null
var minion_id: String = "brood_skitter"
var minion_parent: Node = null
var minion_params: Dictionary = {}
var minion_cap: int = 2
var minion_override: Callable     # tests: func(pos: Vector3, params: Dictionary) -> Node
var release_allowed: Callable     # boss: false while a pounce is telegraphed / falling
var route_targets: Array = []     # floor points Krystal must always be able to reach (the braziers)
var alt := false
var snags: int = 0
var released_count: int = 0

var _post_nodes: Array = []
var _ring_r: float = -1.0          # posts on a ring (default layout): its radius; else -1 (flood fill)
var _slow_chain: float = 0.0
var _slow_immune: float = 0.0
var _own_left: float = 0.0          # seconds left on the field's own slow at the end of the last tick (0 = none)
var _clock: float = 0.0             # seconds this field has been ticked (minion ages)
var _target: Node3D = null
var _target_pos := Vector3.ZERO


func setup(p: Dictionary) -> void:
	var c: Variant = p.get("center")
	if c is Vector3:
		center = c
	radius = maxf(float(p.get("radius", radius)), 3.0)
	floor_y = float(p.get("floor_y", center.y))
	intensity = clampi(int(p.get("intensity", intensity)), 0, 2)
	var e: Variant = p.get("entrance")
	if e is Vector3:
		entrance = e
		has_entrance = true
	obstacles.clear()
	for o in p.get("obstacles", []):
		if o is Array and (o as Array).size() >= 2 and o[0] is Vector3:
			obstacles.append([o[0], float(o[1])])
	var avoid: Array = []
	for o in obstacles:
		avoid.append(o[0])
	posts.clear()
	var tp: Variant = p.get("posts", [])
	if (tp is Array or tp is PackedVector3Array) and tp.size() >= 2:
		for v in tp:
			if v is Vector3:
				posts.append(Vector3(v.x, floor_y, v.z))
	else:
		posts = default_posts(center, radius, avoid, entrance if has_entrance else null, floor_y)
	chords = default_chords(posts, entrance if has_entrance else null)
	_ring_r = ring_radius(posts, center)
	var mp: Variant = p.get("minion_parent")
	if mp is Node:
		minion_parent = mp
	minion_id = String(p.get("minion_id", minion_id))
	alt = bool(p.get("alt", alt))


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	set_process(false)          # the boss ticks us (deterministic in tests)
	_build_posts()
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


static func cap_for(phase: int, level: int) -> int:
	var row: Array = HAZARD_CAP.get(clampi(phase, 2, 3), [3, 3, 3])
	return int(row[clampi(level, 0, 2)])


# --- Tick ----------------------------------------------------------------------------------------------

## target: Krystal (or the test dummy); null = nobody to affect.
func tick(delta: float, target: Node3D) -> void:
	# The field's own slow vanished although plenty of it was left: something removed it (a cleanse).
	var cleansed := _own_left > delta + CLEANSE_MARGIN and own_slow_left() <= 0.0
	_clock += delta
	_target = target if target != null and is_instance_valid(target) else null
	var has_t := _target != null
	if has_t:
		_target_pos = _target.global_position
	var lantern := has_t and _has_light(_target)
	var want := 1.0
	var i := hazards.size() - 1
	while i >= 0:
		var h = hazards[i]            # untyped: a freed hazard must not trip a typed assignment
		if not is_instance_valid(h):
			hazards.remove_at(i)
			i -= 1
			continue
		if h.kind == "fan":
			h.tick(delta, _target_pos, has_t)
			if has_t and h.slows(_target_pos):
				want = minf(want, float(h.slow_mult))
		else:
			h.tick(delta, _target_pos, has_t, lantern)
			if has_t and h.is_active() and h.distance_to(_target_pos) <= SNAG_DIST and _target_pos.y - floor_y <= SNAG_MAX_RISE:
				_snag(h)
		if h.is_done():
			hazards.remove_at(i)
			h.queue_free()
		i -= 1
	_update_slow(delta, want, cleansed)
	_own_left = own_slow_left()
	_tick_sacs(delta)
	if thread != null and is_instance_valid(thread):
		thread.tick(delta)


func _update_slow(delta: float, want: float, cleansed: bool = false) -> void:
	if _slow_immune > 0.0:
		_slow_immune = maxf(_slow_immune - delta, 0.0)
		return
	if want >= 1.0:
		_slow_chain = maxf(_slow_chain - delta * 2.0, 0.0)
		return
	if cleansed:
		# Cleansed while still in a sheet: she is free for SLOW_IMMUNE s (the cleanse is never undone next frame).
		_slow_chain = 0.0
		_slow_immune = SLOW_IMMUNE
		return
	if foreign_slow():
		return                  # another source's slow already holds her: never stacked, never chained on
	_slow_chain += delta
	apply_slow(want, SLOW_LINGER)
	if _slow_chain >= SLOW_CHAIN_CAP:
		_break_free()


## Krystal tears loose after a long slow: the field's slow ends and nothing can slow her for SLOW_IMMUNE s.
func _break_free() -> void:
	_slow_chain = 0.0
	_slow_immune = SLOW_IMMUNE
	_erase_own_slow()
	Events.caption.emit("[Krystal tears free of the veil]" if alt else "[Krystal tears free of the silk]")


## Bounded slow: never below SLOW_FLOOR, never longer than SLOW_MAX_SECONDS, refreshed in place. Only the
## field's own (tagged) slow is refreshed; while another source's slow is on her nothing is written.
func apply_slow(mult: float, seconds: float) -> void:
	if _slow_immune > 0.0:
		return
	var m := clampf(mult, SLOW_FLOOR, 1.0)
	var s := clampf(seconds, 0.0, SLOW_MAX_SECONDS)
	var b: Variant = GameState.buffs.get("slow")
	if b is Dictionary:
		var d := b as Dictionary
		if String(d.get("source", "")) != SLOW_SOURCE:
			return
		d["mult"] = clampf(minf(float(d.get("mult", 1.0)), m), SLOW_FLOOR, 1.0)
		d["remaining"] = clampf(maxf(float(d.get("remaining", 0.0)), s), 0.0, SLOW_MAX_SECONDS)
	else:
		GameState.add_buff("slow", m, s)
		(GameState.buffs["slow"] as Dictionary)["source"] = SLOW_SOURCE


func slow_immune() -> bool:
	return _slow_immune > 0.0


## Seconds left on the field's OWN slow buff (0 when there is none, or the slow belongs to someone else).
func own_slow_left() -> float:
	var b: Variant = GameState.buffs.get("slow")
	if b is Dictionary and String((b as Dictionary).get("source", "")) == SLOW_SOURCE:
		return maxf(float((b as Dictionary).get("remaining", 0.0)), 0.0)
	return 0.0


## True while a slow from another source (an enemy's clod, a trap...) is on her.
func foreign_slow() -> bool:
	var b: Variant = GameState.buffs.get("slow")
	return b is Dictionary and String((b as Dictionary).get("source", "")) != SLOW_SOURCE


## Removes the field's own slow only (never another source's).
func _erase_own_slow() -> void:
	var b: Variant = GameState.buffs.get("slow")
	if b is Dictionary and String((b as Dictionary).get("source", "")) == SLOW_SOURCE:
		GameState.buffs.erase("slow")
	_own_left = 0.0


func _snag(line: Node) -> void:
	line.snap("snag")
	snags += 1
	apply_slow(float(SNAG_SLOW[intensity]), SNAG_SLOW_TIME)
	var h := Combat.find_health(_target)
	if h != null:
		var dir := Vector3(_target_pos.x - line.nearest_point(_target_pos).x, 0.0, _target_pos.z - line.nearest_point(_target_pos).z)
		dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.BACK
		h.apply_damage(SNAG_DAMAGE * Combat.intensity_damage_mult(intensity), boss if boss != null and is_instance_valid(boss) else self, dir)
	Events.caption.emit("[a pale root snags her ankle]" if alt else "[a thread snags her ankle]")
	Events.hint.emit("boss_tripline", "Trip-lines snap when you walk into them. Cut them with {attack}, burn them with your lit lantern, or jump over.")
	line_cut.emit("snag")


func _has_light(t: Node) -> bool:
	var v: Variant = t.get("lantern_on")
	return v is bool and v


# --- Caps ----------------------------------------------------------------------------------------------------

func live_count() -> int:
	var n := 0
	for h in hazards:
		if is_instance_valid(h) and h.is_live():
			n += 1
	return n


func count_kind(k: String) -> int:
	var n := 0
	for h in hazards:
		if is_instance_valid(h) and h.is_live() and h.kind == k:
			n += 1
	return n


## Makes room for `n` new hazards under the cap by expiring the oldest live ones.
func _make_room(n: int) -> void:
	var guard := 0
	while live_count() + n > cap and guard < 16:
		guard += 1
		for h in hazards:
			if is_instance_valid(h) and h.is_live():
				if h.kind == "fan":
					h.expire()
				else:
					h.snap("expired")
				break


# --- Fans ----------------------------------------------------------------------------------------------------

## A narrow fan from `apex` (floor) toward `aim`; returns the node (telegraphing for `tele` s).
func begin_fan(apex: Vector3, aim: Vector3, tele: float) -> Node:
	var a := Vector3(apex.x, floor_y, apex.z)
	var to := Vector3(aim.x - a.x, 0.0, aim.z - a.z)
	# Lengths snap to 0.5 m so the shared sector meshes stay a small, bounded set.
	var length := snappedf(clampf(to.length() + 2.0, FAN_MIN_LEN, FAN_MAX_LEN), 0.5)
	_make_room(1)
	var f: Node3D = WebFan.new()
	f.setup({"apex": a, "dir": to if to.length_squared() > 0.01 else Vector3.FORWARD, "half_deg": FAN_HALF_DEG[intensity],
		"length": length, "tele": tele, "life": FAN_LIFE[intensity], "slow": FAN_SLOW[intensity], "alt": alt})
	f.name = "WebFan"
	add_child(f)
	hazards.append(f)
	return f


# --- Trip-lines ----------------------------------------------------------------------------------------------

## Stretches up to `n` lines between the fixed posts near Krystal (never under her, never across the
## entrance, never twice on one chord, and only while every brazier + the entrance stay reachable).
func begin_trips(n: int, tele: float, from: Vector3) -> Array:
	var out: Array = []
	if posts.size() < 2 or chords.is_empty():
		return out
	var free_chords: Array = []
	for c in chords:
		if not _chord_active(c):
			free_chords.append(c)
	free_chords.sort_custom(func(x: Array, y: Array) -> bool: return _chord_dist(x, from) < _chord_dist(y, from))
	var want := mini(n, cap)
	_make_room(want)
	for c in free_chords:
		if out.size() >= want:
			break
		if _chord_dist(c, from) < TRIP_MIN_PLAYER_DIST:
			continue
		var segs := active_segments()
		for l in out:
			segs.append([l.a, l.b])
		segs.append([posts[c[0]], posts[c[1]]])
		if not _routes_ok(from, segs):
			continue
		var line: Node3D = TripLine.new()
		line.setup({"a": posts[c[0]], "b": posts[c[1]], "tele": tele, "life": TRIP_LIFE[intensity], "alt": alt, "chord": c})
		line.name = "TripLine"
		add_child(line)
		line.cut.connect(_on_line_cut)
		hazards.append(line)
		out.append(line)
	return out


func _on_line_cut(how: String) -> void:
	if how != "snag":
		line_cut.emit(how)


func _chord_active(c: Array) -> bool:
	for h in hazards:
		if is_instance_valid(h) and h.is_live() and h.kind == "trip":
			var hc: Array = h.chord
			if hc.size() == 2 and ((int(hc[0]) == int(c[0]) and int(hc[1]) == int(c[1])) or (int(hc[0]) == int(c[1]) and int(hc[1]) == int(c[0]))):
				return true
	return false


func _chord_dist(c: Array, p: Vector3) -> float:
	var a: Vector3 = posts[c[0]]
	var b: Vector3 = posts[c[1]]
	return TripLine.seg_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(p.x, p.z))


## [[a, b], ...] of the lines that are live (forming or active).
func active_segments() -> Array:
	var out: Array = []
	for h in hazards:
		if is_instance_valid(h) and h.is_live() and h.kind == "trip":
			out.append([h.a, h.b])
	return out


## Would Krystal (at `from`) still reach every brazier and the entrance with lines `segs`?
## Posts on a ring (the default): every line is a full chord of that ring, so each floor region inside
## it is convex and a route exists iff Krystal - and every target inside the ring - can walk straight out
## past the ring (the band outside it is always open): ESCAPE_RAYS straight rays, cheap and exact up to the
## ray spacing (a gap narrower than that is treated as closed: conservative). Custom posts: one grid flood
## fill (route_exists). Tests cross-check both with the flood fill.
func _routes_ok(from: Vector3, segs: Array) -> bool:
	var circles := _route_circles()
	var targets: Array = route_targets.duplicate()
	if has_entrance:
		targets.append(entrance)
	if _ring_r > 0.0:
		if not _escapes(from, segs, circles):
			return false
		for t in targets:
			if not _escapes(t, segs, circles):
				return false
		return true
	return routes_from(from, targets, center, radius, segs, circles)


## Can someone at `from` walk in a straight line out past the post ring (clear of lines and solid
## circles by ROUTE_CLEARANCE)? Circles that already contain `from` are ignored (standing at a brazier).
func _escapes(from: Vector3, segs: Array, circles: Array) -> bool:
	var f := Vector2(from.x - center.x, from.z - center.z)
	var goal_r := _ring_r + 0.6
	if f.length() >= goal_r:
		return true
	for k in ESCAPE_RAYS:
		var ang := TAU * float(k) / float(ESCAPE_RAYS)
		var dir := Vector2(cos(ang), sin(ang))
		var b := f.dot(dir)
		var t := -b + sqrt(maxf(b * b - (f.length_squared() - goal_r * goal_r), 0.0))
		var e := f + dir * t
		var clear := true
		for sg in segs:
			var a: Vector3 = sg[0]
			var c: Vector3 = sg[1]
			if seg_seg_dist(f, e, Vector2(a.x - center.x, a.z - center.z), Vector2(c.x - center.x, c.z - center.z)) <= ROUTE_CLEARANCE:
				clear = false
				break
		if clear:
			for ci in circles:
				var cc: Vector3 = ci[0]
				var cp := Vector2(cc.x - center.x, cc.z - center.z)
				var rr := float(ci[1]) + ROUTE_CLEARANCE
				if cp.distance_to(f) <= rr:
					continue
				if TripLine.seg_dist(f, e, cp) <= rr:
					clear = false
					break
		if clear:
			return true
	return false


## 2D distance between segments ab and cd (0 when they cross).
static func seg_seg_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var d1 := (b - a).cross(c - a)
	var d2 := (b - a).cross(d - a)
	var d3 := (d - c).cross(a - c)
	var d4 := (d - c).cross(b - c)
	if ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0)):
		return 0.0
	return minf(minf(TripLine.seg_dist(a, b, c), TripLine.seg_dist(a, b, d)), minf(TripLine.seg_dist(c, d, a), TripLine.seg_dist(c, d, b)))


func _route_circles() -> Array:
	var out: Array = []
	for o in obstacles:
		out.append(o)
	for p in posts:
		out.append([p, 0.25])
	return out


# --- Sacs & minions ------------------------------------------------------------------------------------------

## Places `n` sacs on the arena edge, far from Krystal (>= SAC_MIN_PLAYER_DIST), apart from each other,
## the braziers and the entrance. Returns them (fewer when there is no fair spot).
func begin_sacs(n: int, warn: float, from: Vector3) -> Array:
	var out: Array = []
	var spots := sac_spots(from, n)
	for s in spots:
		var sac: Node3D = EggSac.new()
		sac.setup({"pos": s, "warn": warn, "alt": alt})
		sac.name = "EggSac"
		add_child(sac)
		sacs.append(sac)
		out.append(sac)
	return out


func sac_spots(from: Vector3, n: int) -> Array:
	var cands: Array = []
	var r := maxf(radius - SAC_EDGE_INSET, 2.0)
	for k in 16:
		var ang := TAU * float(k) / 16.0
		var p := Vector3(center.x + cos(ang) * r, floor_y, center.z + sin(ang) * r)
		if _flat(p, from) < SAC_MIN_PLAYER_DIST:
			continue
		var ok := true
		for o in obstacles:
			if _flat(p, o[0]) < 2.5:
				ok = false
		for q in posts:
			if _flat(p, q) < 1.5:
				ok = false
		if has_entrance and _flat(p, entrance) < 4.0:
			ok = false
		if ok:
			cands.append(p)
	cands.sort_custom(func(x: Vector3, y: Vector3) -> bool: return _flat(x, from) > _flat(y, from))
	var out: Array = []
	for p in cands:
		if out.size() >= n:
			break
		var far := true
		for q in out:
			if _flat(p, q) < SAC_SEPARATION:
				far = false
		if far:
			out.append(p)
	return out


func sacs_pending() -> bool:
	for s in sacs:
		if is_instance_valid(s) and s.is_pending():
			return true
	return false


func _tick_sacs(delta: float) -> void:
	var i := sacs.size() - 1
	while i >= 0:
		var s = sacs[i]
		if not is_instance_valid(s):
			sacs.remove_at(i)
			i -= 1
			continue
		s.tick(delta)
		if s.is_due():
			var near := _target != null and _flat(_target_pos, s.pos) < SAC_CLEAR_DIST
			var allowed := not release_allowed.is_valid() or bool(release_allowed.call())
			if s.t >= s.warn + SAC_MAX_DELAY:
				s.pop()          # she camped on it: it withers, no minion
			elif allowed and not near:
				var m := spawn_minion(s.pos)
				s.mark_released()
				if m == null:
					Events.caption.emit("[the pod splits open, empty]" if alt else "[the sac splits open, empty]")
		if s.is_done():
			sacs.remove_at(i)
			s.queue_free()
		i -= 1


func alive_minions() -> int:
	var n := 0
	for m in minions:
		if _minion_alive(m):
			n += 1
	return n


static func _minion_alive(m: Variant) -> bool:
	if m == null or not is_instance_valid(m) or (m as Node).is_queued_for_deletion():
		return false
	if (m as Node).has_method("is_dead") and bool(m.is_dead()):
		return false
	return true


## Spawns one minion at `pos` if under the cap (EnemyFactory id minion_id, guarded when that enemy's
## script is not available yet). Returns it or null.
func spawn_minion(pos: Vector3) -> Node:
	var i := minions.size() - 1
	while i >= 0:
		if not _minion_alive(minions[i]):
			minions.remove_at(i)
		i -= 1
	if minions.size() >= minion_cap:
		return null
	var params := minion_params.duplicate()
	params["home"] = center
	params["wander_radius"] = radius
	params["alert"] = true
	params["no_drops"] = true
	var m: Node = null
	if minion_override.is_valid():
		m = minion_override.call(pos, params)
	elif Factory.has_enemy(minion_id) and minion_parent != null and is_instance_valid(minion_parent) and minion_parent.is_inside_tree():
		m = Factory.spawn(minion_id, minion_parent, Transform3D(Basis.IDENTITY, pos), params)
	if m == null:
		return null
	m.set_meta("matron_minion", true)
	m.set_meta("matron_minion_born", _clock)
	minions.append(m)
	released_count += 1
	if m.has_method("pop_in"):
		m.call("pop_in")
	minion_spawned.emit(m)
	return m


## Seconds minion `m` has been out (field clock; 0 for one this field did not release).
func minion_age(m: Node) -> float:
	if m == null or not is_instance_valid(m):
		return 0.0
	return maxf(_clock - float(m.get_meta("matron_minion_born", _clock)), 0.0)


## Can Krystal reach minion `m` on the arena floor? (not off the floor's edge, not up on a ledge / down a hole)
func minion_reachable(m: Node) -> bool:
	if not (m is Node3D) or not is_instance_valid(m):
		return false
	var p := (m as Node3D).global_position
	return _flat(p, center) <= radius + MINION_REACH_MARGIN and absf(p.y - floor_y) <= MINION_REACH_RISE


## Living minions that still count for the boss's Gentle drop gate: out for at most `max_age` seconds and
## reachable. A minion stuck somewhere (or ignored) for longer, or out of reach, never stalls the fight.
func blocking_minions(max_age: float) -> int:
	var n := 0
	for m in minions:
		if _minion_alive(m) and minion_age(m) <= max_age and minion_reachable(m):
			n += 1
	return n


## The minions scatter into the dark (phase 3, reset, defeat): freed, no drops, no kill events.
func dismiss_minions() -> void:
	for m in minions:
		if _minion_alive(m):
			if m is Node3D:
				HitFx.wisps((m as Node3D).global_position + Vector3.UP * 0.4, Color(0.8, 0.78, 0.9, 0.6), 8, 1.0)
			(m as Node).queue_free()
	minions.clear()


# --- Thread -----------------------------------------------------------------------------------------------------

func begin_thread(top: Vector3, bottom: Vector3) -> Node3D:
	end_thread()
	var th: Node3D = BossThread.new()
	th.setup({"alt": alt, "floor_y": floor_y})
	th.name = "BossThread"
	add_child(th)
	th.set_ends(top, bottom)
	thread = th
	return th


func end_thread() -> void:
	if thread != null and is_instance_valid(thread):
		thread.queue_free()
	thread = null


# --- Clearing ------------------------------------------------------------------------------------------------------

## Removes every fan, line and sac at once (phase transition, reset, defeat). fx: fade them out.
func clear_all(fx: bool = true) -> void:
	for h in hazards:
		if is_instance_valid(h):
			if fx:
				if h.kind == "fan":
					h.expire()
				else:
					h.snap("cleared")
			else:
				h.queue_free()
	if not fx:
		hazards.clear()
	for s in sacs:
		if is_instance_valid(s):
			if fx:
				s.clear()
			else:
				s.queue_free()
	if not fx:
		sacs.clear()
	end_thread()
	_erase_own_slow()
	_slow_chain = 0.0
	_slow_immune = 0.0


func is_clear() -> bool:
	return live_count() == 0 and not sacs_pending() and (thread == null or not is_instance_valid(thread))


# --- Posts (fixed trip-line anchors) --------------------------------------------------------------------------------

## Mean distance of the posts from the centre when they all sit on one ring (within 0.3 m), else -1.
static func ring_radius(p_posts: Array, c: Vector3) -> float:
	if p_posts.size() < 3:
		return -1.0
	var sum := 0.0
	for p in p_posts:
		sum += _flat(p, c)
	var mean := sum / float(p_posts.size())
	for p in p_posts:
		if absf(_flat(p, c) - mean) > 0.3:
			return -1.0
	return mean


## POST_COUNT anchors on a ring (POST_RADIUS_FRAC of the radius), rotated so they sit as far as
## possible from `avoid` points (braziers) and the entrance. Deterministic.
static func default_posts(c: Vector3, r: float, avoid: Array, p_entrance: Variant, fy: float) -> Array:
	var angs: Array = []
	for a in avoid:
		if a is Vector3 and _flat(a, c) > 1.0:        # (the centrepiece has no direction)
			angs.append(atan2((a as Vector3).z - c.z, (a as Vector3).x - c.x))
	if p_entrance is Vector3:
		angs.append(atan2((p_entrance as Vector3).z - c.z, (p_entrance as Vector3).x - c.x))
	var step := TAU / float(POST_COUNT)
	var best_off := 0.0
	var best_score := -1.0
	for d in 60:
		var off := deg_to_rad(float(d)) * (step / deg_to_rad(60.0))
		var score := INF
		for k in POST_COUNT:
			var pa := off + step * float(k)
			for x in angs:
				score = minf(score, absf(angle_difference(pa, float(x))))
		if angs.is_empty():
			score = 0.0
		if score > best_score + 0.0001:
			best_score = score
			best_off = off
	var rr := r * POST_RADIUS_FRAC
	var out: Array = []
	for k in POST_COUNT:
		var pa := best_off + step * float(k)
		out.append(Vector3(c.x + cos(pa) * rr, fy, c.z + sin(pa) * rr))
	return out


## Allowed spans: neighbouring posts and posts two apart, never passing within ENTRANCE_CLEAR of the
## entrance.
static func default_chords(p_posts: Array, p_entrance: Variant) -> Array:
	var out: Array = []
	var n := p_posts.size()
	if n < 2:
		return out
	for i in n:
		for s in [1, 2]:
			var j: int = (i + int(s)) % n
			if j == i or (n <= 3 and s == 2):
				continue
			var dup := false
			for c in out:
				if (int(c[0]) == j and int(c[1]) == i):
					dup = true
			if dup:
				continue
			if p_entrance is Vector3:
				var a: Vector3 = p_posts[i]
				var b: Vector3 = p_posts[j]
				var e: Vector3 = p_entrance
				if TripLine.seg_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(e.x, e.z)) < ENTRANCE_CLEAR:
					continue
			out.append([i, j])
	return out


## The fixed trip-line anchors: a pale stake / root peg per post (hazard_art.build_post, CR-03 - never the old dark
## blob with two pale "eye" crescents). Rebuilt on an arachnophobia swap; the old posts leave the tree at once so
## a swap never shows (or counts) both sets.
func _build_posts() -> void:
	for n in _post_nodes:
		if is_instance_valid(n):
			if (n as Node).get_parent() == self:
				remove_child(n)
			(n as Node).queue_free()
	_post_nodes.clear()
	for k in posts.size():
		var p: Vector3 = posts[k]
		var holder := Node3D.new()
		holder.name = "TripPost%d" % k
		add_child(holder)
		holder.global_position = p
		Art.build_post(holder, alt)
		_post_nodes.append(holder)


# --- Arachnophobia ---------------------------------------------------------------------------------------------------

func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		set_high_vis(Art.high_vis())
		return
	if key != "arachnophobia":
		return
	set_alt(bool(Settings.get_value("arachnophobia")))


## Settings "high_visibility_cues" (comfort): every live fan / line / sac / thread shows (or hides) its bold
## cream outline at once; new hazards read the setting when they are built.
func set_high_vis(on: bool) -> void:
	for h in hazards:
		if is_instance_valid(h):
			h.set_high_vis(on)
	for s in sacs:
		if is_instance_valid(s):
			s.set_high_vis(on)
	if thread != null and is_instance_valid(thread):
		thread.set_high_vis(on)


func set_alt(on: bool) -> void:
	if on == alt:
		return
	alt = on
	for h in hazards:
		if is_instance_valid(h):
			h.set_alt(on)
	for s in sacs:
		if is_instance_valid(s):
			s.set_alt(on)
	if thread != null and is_instance_valid(thread):
		thread.set_alt(on)
	if is_inside_tree():
		_build_posts()


# --- Pure route check -------------------------------------------------------------------------------------------------

## Can Krystal walk from `from` to within 1.2 m of `to` on the arena disc (centre `c`, radius `r`)
## without crossing any segment ([[Vector3 a, Vector3 b], ...], treated as ROUTE_CLEARANCE wide) or
## entering a circle ([[Vector3 centre, radius], ...])? Grid flood fill, ROUTE_CELL spacing. Pure.
static func route_exists(from: Vector3, to: Vector3, c: Vector3, r: float, segs: Array, circles: Array, cell: float = ROUTE_CELL) -> bool:
	return routes_from(from, [to], c, r, segs, circles, cell)


## One flood fill from `from`; true when every point of `targets` is reached (within 1.2 m).
static func routes_from(from: Vector3, targets: Array, c: Vector3, r: float, segs: Array, circles: Array, cell: float = ROUTE_CELL) -> bool:
	var n := int(ceil(r * 2.0 / cell)) + 1
	var ox := c.x - r
	var oz := c.z - r
	var free := PackedByteArray()
	free.resize(n * n)
	for j in n:
		for i in n:
			var p := Vector2(ox + float(i) * cell, oz + float(j) * cell)
			var ok := p.distance_to(Vector2(c.x, c.z)) <= r - ROUTE_CLEARANCE
			if ok:
				for s in segs:
					var a: Vector3 = s[0]
					var b: Vector3 = s[1]
					if TripLine.seg_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), p) <= ROUTE_CLEARANCE:
						ok = false
						break
			if ok:
				for ci in circles:
					var cc: Vector3 = ci[0]
					if p.distance_to(Vector2(cc.x, cc.z)) <= float(ci[1]) + ROUTE_CLEARANCE:
						ok = false
						break
			free[j * n + i] = 1 if ok else 0
	var start := _nearest_free(free, n, ox, oz, cell, from)
	if start < 0:
		return false
	var goals: Array = []
	for t in targets:
		goals.append(Vector2((t as Vector3).x, (t as Vector3).z))
	var found := PackedByteArray()
	found.resize(goals.size())
	var left := goals.size()
	var seen := PackedByteArray()
	seen.resize(n * n)
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var k := queue[head]
		head += 1
		var ci := k % n
		var cj: int = int(k / n)
		var here := Vector2(ox + float(ci) * cell, oz + float(cj) * cell)
		for g in goals.size():
			if found[g] == 0 and here.distance_to(goals[g]) <= 1.2:
				found[g] = 1
				left -= 1
		if left <= 0:
			return true
		for d in DIRS:
			var ni: int = ci + int(d[0])
			var nj: int = cj + int(d[1])
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			if seen[nk] == 1 or free[nk] == 0:
				continue
			seen[nk] = 1
			queue.append(nk)
	return false


static func _nearest_free(free: PackedByteArray, n: int, ox: float, oz: float, cell: float, p: Vector3) -> int:
	var best := -1
	var best_d := INF
	var ci := clampi(int(round((p.x - ox) / cell)), 0, n - 1)
	var cj := clampi(int(round((p.z - oz) / cell)), 0, n - 1)
	for dj in range(-4, 5):
		for di in range(-4, 5):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= n or j >= n:
				continue
			if free[j * n + i] == 0:
				continue
			var d := Vector2(ox + float(i) * cell - p.x, oz + float(j) * cell - p.z).length()
			if d < best_d:
				best_d = d
				best = j * n + i
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
