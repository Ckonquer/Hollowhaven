extends RefCounted
## Obstacle-aware approach for ONE companion (owned by companion.gd as `nav`; MP §6.1 "no pet endlessly
## running into a wall"). Proportional to need, cheapest first:
##   1. direct: one throttled ray (chest height, world|structure) to the goal; clear -> walk straight (the
##      body's hop handles low steps and fences);
##   2. a local waypoint search (grid A* over 0.9 m cells around the pet and the goal, walkability probed
##      lazily with a floor ray + a half-cell overlap sphere, so any wall between two cell centres blocks at
##      least one of them; edges only check the step height),
##      bounded by a physics-query budget, at most one search per physics frame for all companions and one
##      per SEARCH_COOLDOWN per pet; the path is string-pulled and followed waypoint by waypoint;
##   3. whisker steering (fan of short rays, sticky side) while no path is known.
## The follow code's breadcrumbs (Krystal's own path) stay the first choice when she is out of sight; this
## is what gets a pet around a wall when there is no trail (after a teleport, when Krystal stood still, an
## attack approach). The stuck detectors + safe teleport remain the last resort (not during a boss fight).
## Pure grid search: static astar() (unit tested without physics).

const MASK := 1 | 32
const CELL := 0.9
const MAX_STEP := 0.75             # the hop clears about 0.8 m
const PROBE_BUDGET := 700          # physics queries per search
const SEARCH_USEC_BUDGET := 3000    # and wall-clock time per search (a slow machine gets a shorter, partial search)
const SEARCH_COOLDOWN := 0.8
const SEARCH_FAIL_COOLDOWN := 2.5   # after a search found nothing (goal on a roof, walled off): wait longer
const CHECK_INTERVAL := 0.25
const REPATH_MOVE := 1.5           # the goal moved this far from the path's end -> drop the path
const WAYPOINT_REACH := 0.55
const KNEE := 0.3
const CHEST := 0.9
const BODY_RADIUS := 0.24
const PROBE_RADIUS := 0.42         # > (CELL - thinnest wall 0.06) / 2: a wall between two centres touches one
const WHISKER_LEN := 1.6
const WHISKER_ANGLES := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 125.0, -125.0]
const PROGRESS_MS := 2500

static var _search_frame: int = -1

var body: CharacterBody3D
var path: Array = []
var path_goal := Vector3.INF
var searches: int = 0
var last_search_usec: int = 0       # wall-clock cost of the last search (tests / telemetry)
var last_result: String = ""        # "direct" | "path" | "whisker" | "none"
var _check_t: float = 0.0
var _direct: bool = true
var _search_cd: float = 0.0
var _last_wp_ms: int = -100000
var _whisker_dir := Vector3.ZERO
var _whisker_t: float = 0.0
var _whisker_side: float = 1.0
var _queries: int = 0
var _sq: PhysicsShapeQueryParameters3D
var _ray: PhysicsRayQueryParameters3D


func _init(owner_body: CharacterBody3D) -> void:
	body = owner_body
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = MASK
	_ray.collide_with_areas = false
	_sq = PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = PROBE_RADIUS
	_sq.shape = s
	_sq.collision_mask = MASK
	# The pet's own body never blocks its probes. Set once (a new exclude array per ray would allocate).
	if owner_body != null:
		var ex: Array[RID] = [owner_body.get_rid()]
		_ray.exclude = ex
		_sq.exclude = ex


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Forget the current plan (teleports, state changes).
func reset() -> void:
	path.clear()
	path_goal = Vector3.INF
	_check_t = 0.0
	_direct = true
	_whisker_dir = Vector3.ZERO


## True while the pet walks a found path and keeps reaching waypoints (the stuck detectors wait meanwhile).
func progressing() -> bool:
	return not path.is_empty() and Time.get_ticks_msec() - _last_wp_ms < PROGRESS_MS


## The point to steer toward this frame on the way to `goal`.
func route(goal: Vector3, delta: float) -> Vector3:
	if body == null or not body.is_inside_tree():
		return goal
	var from := body.global_position
	_search_cd = maxf(_search_cd - delta, 0.0)
	if _flat(goal - from).length() < 1.2 and absf(goal.y - from.y) < 1.2:
		path.clear()
		last_result = "direct"
		return goal
	if not path.is_empty() and _flat(path_goal - goal).length() > REPATH_MOVE:
		path.clear()
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_INTERVAL
		_direct = _clear(from + Vector3.UP * CHEST, goal + Vector3.UP * CHEST)
	if _direct:
		path.clear()
		last_result = "direct"
		return goal
	if not path.is_empty():
		last_result = "path"
		return _follow_path(from, goal)
	var frame := Engine.get_physics_frames()
	if _search_cd <= 0.0 and _search_frame != frame:
		_search_frame = frame
		_search_cd = SEARCH_COOLDOWN
		searches += 1
		path = search(from, goal)
		path_goal = goal
		if not path.is_empty():
			_last_wp_ms = Time.get_ticks_msec()
			last_result = "path"
			return _follow_path(from, goal)
		_search_cd = SEARCH_FAIL_COOLDOWN
	last_result = "whisker"
	return from + _whisker(from, goal, delta) * 2.0


func _follow_path(from: Vector3, goal: Vector3) -> Vector3:
	while not path.is_empty():
		var wp: Vector3 = path[0]
		if _flat(wp - from).length() <= WAYPOINT_REACH and absf(wp.y - from.y) < 1.2:
			path.pop_front()
			_last_wp_ms = Time.get_ticks_msec()
			continue
		return wp
	return goal


## Fan of short chest-height rays around the wanted direction; keeps the side that worked last.
func _whisker(from: Vector3, goal: Vector3, delta: float) -> Vector3:
	var want := _flat(goal - from)
	if want.length() < 0.01:
		return Vector3.ZERO
	want = want.normalized()
	_whisker_t -= delta
	if _whisker_t > 0.0 and _whisker_dir != Vector3.ZERO:
		return _whisker_dir
	_whisker_t = 0.12
	var origin := from + Vector3.UP * CHEST * 0.6
	for a in WHISKER_ANGLES:
		var ang := deg_to_rad(float(a)) * _whisker_side
		var d := want.rotated(Vector3.UP, ang)
		if _clear(origin, origin + d * WHISKER_LEN):
			_whisker_dir = d
			if absf(float(a)) > 1.0:
				_whisker_side = signf(float(a)) * _whisker_side
			return d
	_whisker_side = -_whisker_side
	_whisker_dir = -want
	return _whisker_dir


func _space() -> PhysicsDirectSpaceState3D:
	return body.get_world_3d().direct_space_state if body != null and body.is_inside_tree() else null


func _clear(a: Vector3, b: Vector3) -> bool:
	var space := _space()
	if space == null:
		return true
	_queries += 1
	_ray.from = a
	_ray.to = b
	return space.intersect_ray(_ray).is_empty()


## Floor under a cell centre (or null when blocked / no floor / too steep). `top`/`bottom`: ray span.
func _probe(x: float, z: float, top: float, bottom: float) -> Variant:
	var space := _space()
	if space == null:
		return null
	_queries += 2
	_ray.from = Vector3(x, top, z)
	_ray.to = Vector3(x, bottom, z)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return null
	var n: Vector3 = hit["normal"]
	if n.y < 0.6:
		return null
	var p: Vector3 = hit["position"]
	_sq.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (PROBE_RADIUS + 0.18))
	if not space.intersect_shape(_sq, 1).is_empty():
		return null
	return p


## Local grid A* from `from` to `goal` with physics probes. Returns waypoints (floor points) or [].
func search(from: Vector3, goal: Vector3) -> Array:
	if _space() == null:
		return []
	_queries = 0
	var center := (from + goal) * 0.5
	var dist := _flat(goal - from).length()
	var half := clampi(int(ceil(dist * 0.5 / CELL)) + 6, 6, 16)
	var size := half * 2 + 1
	var top := maxf(from.y, goal.y) + 1.5
	var bottom := minf(from.y, goal.y) - 3.0
	var ox := center.x - float(half) * CELL
	var oz := center.z - float(half) * CELL
	var floors: Dictionary = {}
	var t0 := Time.get_ticks_usec()
	var info := {"exhausted": false}
	var walk := func(i: int, j: int) -> Variant:
		var key := i * 4096 + j
		if floors.has(key):
			return floors[key]
		if _queries >= PROBE_BUDGET or Time.get_ticks_usec() - t0 > SEARCH_USEC_BUDGET:
			info["exhausted"] = true      # unknown, not proven blocked: a partial path is still worth taking
			return null
		var f: Variant = _probe(ox + float(i) * CELL, oz + float(j) * CELL, top, bottom)
		floors[key] = f
		return f
	var edge := func(_a: Vector2i, _b: Vector2i, fa: Vector3, fb: Vector3) -> bool:
		return absf(fa.y - fb.y) <= MAX_STEP
	var s := Vector2i(clampi(roundi((from.x - ox) / CELL), 0, size - 1), clampi(roundi((from.z - oz) / CELL), 0, size - 1))
	var g := Vector2i(clampi(roundi((goal.x - ox) / CELL), 0, size - 1), clampi(roundi((goal.z - oz) / CELL), 0, size - 1))
	var cells := astar(s, g, size, walk, edge, 900, info)
	last_search_usec = Time.get_ticks_usec() - t0
	if cells.is_empty():
		return []
	var pts: Array = []
	for cc in cells:
		var f: Variant = floors.get(int(cc.x) * 4096 + int(cc.y))
		if f is Vector3:
			pts.append(f)
	return _smooth(from, pts)


## String pulling: skip waypoints the pet can walk to directly (bounded rays).
func _smooth(from: Vector3, pts: Array) -> Array:
	if pts.size() <= 2:
		return pts
	var out: Array = []
	var cur := from
	var i := 0
	var checks := 0
	while i < pts.size():
		var far := i
		var k := pts.size() - 1
		while k > i and checks < 24:
			checks += 1
			var p: Vector3 = pts[k]
			if absf(p.y - cur.y) <= MAX_STEP and _clear(cur + Vector3.UP * KNEE, p + Vector3.UP * KNEE):
				far = k
				break
			k -= 1
		out.append(pts[far])
		cur = pts[far]
		i = far + 1
	return out


## Pure grid A* (8-connected, no corner cutting). `walk(i, j) -> Vector3 | null` (floor point of a cell or
## null when not walkable), `edge(a, b, floor_a, floor_b) -> bool`. `size` cells per side. Stops after
## `max_expand` expansions and then returns the path to the expanded cell closest to the goal (a partial
## path) when that cell is clearly closer than the start; a goal proven unreachable (every reachable cell
## searched) gives []. `info.exhausted` (set by `walk` when its probe budget ran out) means some cells are
## unknown rather than blocked, so running out of open cells is not a proof: a partial path is returned then.
## Returns the cells after `start` up to the goal ([] = none).
static func astar(start: Vector2i, goal: Vector2i, size: int, walk: Callable, edge: Callable, max_expand: int = 900, info: Dictionary = {}) -> Array:
	var sf: Variant = walk.call(start.x, start.y)
	if not (sf is Vector3):
		# Standing on an edge the probe rejects (a doorway, a slope): start from the best free neighbour.
		var alt := _free_neighbour(start, size, walk)
		if alt == Vector2i(-1, -1):
			return []
		start = alt
	var gf: Variant = walk.call(goal.x, goal.y)
	if not (gf is Vector3):
		var alt2 := _free_neighbour(goal, size, walk)
		if alt2 == Vector2i(-1, -1):
			return []
		goal = alt2
	if start == goal:
		return [goal]
	var open_keys: Array = []          # binary heap of [f, key]
	var g_cost: Dictionary = {}
	var came: Dictionary = {}
	var closed: Dictionary = {}
	var sk := start.x * 4096 + start.y
	g_cost[sk] = 0.0
	_heap_push(open_keys, [_octile(start, goal), sk])
	var best_key := sk
	var best_h := _octile(start, goal)
	var expanded := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var gk := goal.x * 4096 + goal.y
	while not open_keys.is_empty() and expanded < max_expand:
		var top: Array = _heap_pop(open_keys)
		var k := int(top[1])
		if closed.has(k):
			continue
		closed[k] = true
		expanded += 1
		var cur := Vector2i(k / 4096, k % 4096)
		if k == gk:
			best_key = k
			break
		var hc := _octile(cur, goal)
		if hc < best_h:
			best_h = hc
			best_key = k
		var fc: Variant = walk.call(cur.x, cur.y)
		if not (fc is Vector3):
			continue
		for d in dirs:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size:
				continue
			var nk := n.x * 4096 + n.y
			if closed.has(nk):
				continue
			var fn: Variant = walk.call(n.x, n.y)
			if not (fn is Vector3):
				continue
			if d.x != 0 and d.y != 0:
				# Diagonal: both orthogonal neighbours must be free (never cut a wall corner).
				if not (walk.call(cur.x + d.x, cur.y) is Vector3) or not (walk.call(cur.x, cur.y + d.y) is Vector3):
					continue
			if not bool(edge.call(cur, n, fc, fn)):
				continue
			var step := 1.4142 if (d.x != 0 and d.y != 0) else 1.0
			var ng := float(g_cost[k]) + step
			if ng < float(g_cost.get(nk, INF)):
				g_cost[nk] = ng
				came[nk] = k
				_heap_push(open_keys, [ng + _octile(n, goal), nk])
	var reached := came.has(gk) or closed.has(gk)
	if not reached and open_keys.is_empty() and not bool(info.get("exhausted", false)):
		return []                    # searched everything reachable: the goal is walled off / out of reach
	var end := gk if reached else best_key
	if end == sk:
		return []
	if end != gk and best_h >= _octile(start, goal) - 1.5:
		return []                    # a "partial" path (budget ran out) that gets nowhere
	var out: Array = []
	var cur_k := end
	while cur_k != sk:
		out.push_front(Vector2i(cur_k / 4096, cur_k % 4096))
		if not came.has(cur_k):
			return []
		cur_k = int(came[cur_k])
	return out


static func _free_neighbour(c: Vector2i, size: int, walk: Callable) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var n: Vector2i = c + d
		if n.x >= 0 and n.y >= 0 and n.x < size and n.y < size and walk.call(n.x, n.y) is Vector3:
			return n
	return Vector2i(-1, -1)


static func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.4142 * float(mini(dx, dy))


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var tmp: Array = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and float(h[l][0]) < float(h[m][0]):
			m = l
		if r < n and float(h[r][0]) < float(h[m][0]):
			m = r
		if m == i:
			break
		var tmp: Array = h[m]
		h[m] = h[i]
		h[i] = tmp
		i = m
	return top
