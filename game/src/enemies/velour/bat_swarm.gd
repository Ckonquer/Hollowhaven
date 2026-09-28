extends Node3D
## Phase B "The ballroom in flight" (MP 13.1): Count Velour has burst into bats. One node per boss (top_level
## child, freed with it); the boss drives it with tick(delta, target) and reads its signals.
##
## A PATTERN splits the arena into three parallel lanes across the sweep axis ("ns": lanes run north-south and the
## bats fly along z; "ew": along x). ONE broad SAFE lane (SAFE_SHARE of the width, marked by a dotted row of pale
## gold rings) stays untouched while bats sweep the two other lanes (each marked as a red lane with an arrow
## showing the flight direction) - shapes differ, never colour alone. Fairness rules:
##   * the safe lane is always a lane NEXT to the one Krystal stands in when the marks appear (Gentle: the nearer
##     neighbour), so it is reachable by walking within the warning;
##   * the danger lane she stands in sweeps LAST (after `gap` more seconds);
##   * each lane can hit her at most once, only when the bat front actually crosses her, through her health path
##     (dodge i-frames, armour and shields apply) and never through a wall / pillar (line of sight from the bats).
## RETURN: the bats fly home. One bat wears his collar ruff, gold neck ring and tiny crown (the TRUE bat); it homes
## toward Krystal while decoys scatter. If it flies into a LIT ward-candle pool it is caught by candle-light:
## `returned(true, where)` - revealed early (the boss reforms there, dazzled, for a longer window). Otherwise it
## reforms REFORM_DIST from her when it arrives or the return time runs out: `returned(false, where)`.
## Nothing here lasts forever: every stage has a fixed length (the boss also caps the whole dispersal).
##   var s := BatSwarm.new(); s.setup({"center", "half", "candles", "hit_func": Callable(t, dir) -> float})
##   s.begin([{"orientation": "ns", "tele": 1.8, "gap": 1.0, "sweep": 1.2, "pause": 0.8}, ...], return_time, gentle, krystal)
##   s.tick(delta, target)          # signals: lane_marked(pattern), sweep_hit(lane, dealt), returned(revealed, at)

signal lane_marked(pattern: Dictionary)
signal sweep_hit(lane: int, dealt: float)
signal returned(was_revealed: bool, at: Vector3)

const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Combat := preload("res://src/combat/combat.gd")
const Fx := preload("res://src/enemies/velour/velour_fx.gd")

const LANES := 3
const SAFE_SHARE := 0.4
const BAT_HEIGHT := 1.2
const BATS_PER_LANE := 7
const DECOYS := 5
const LOS_BACK := 1.5
const RETURN_HEIGHT := 2.1
const REFORM_DIST := 2.4
const EDGE_PAD := 1.0
const MAX_DY := 2.5
const SAFE_COLOR := Color(1.0, 0.86, 0.5)
const SAFE_SPOTS := 6

var center := Vector3.ZERO
var half: float = 12.0
var candles: Array = []
var hit_func: Callable = Callable()
var rng := RandomNumberGenerator.new()

var stage: String = "idle"            # idle | tele | sweep | pause | return | done
var stage_time: float = 0.0
var pattern: Dictionary = {}          # the current pattern (with its resolved "safe", "order", "signs")
var lanes: Array = []                 # current layout: 3 dicts (see lane_layout)
var patterns_done: int = 0
var hits: int = 0
var revealed := false
var return_time: float = 2.2
var gentle := false
var true_pos := Vector3.ZERO
var last_target_lane: int = -1

var _queue: Array = []
var _fronts: Dictionary = {}          # lane index -> previous front coordinate (along the sweep axis)
var _hit_lanes: Dictionary = {}       # lane index -> true once it has hit (or passed) her
var _marks: Array = []                # TelegraphFx: [danger A, danger B, safe]
var _lane_bats: Array = []            # 2 x BATS_PER_LANE bat nodes
var _true_bat: Node3D = null
var _decoys: Array = []
var _decoy_dirs: Array = []
var _true_speed: float = 5.0
var _t: float = 0.0


func setup(params: Dictionary) -> void:
	var c: Variant = params.get("center")
	if c is Vector3:
		center = c
	half = maxf(float(params.get("half", half)), 3.0)
	candles = []
	for n in params.get("candles", []):
		if n is Node and is_instance_valid(n):
			candles.append(n)
	var hf: Variant = params.get("hit_func")
	if hf is Callable:
		hit_func = hf
	if params.has("seed"):
		rng.seed = int(params["seed"])
	else:
		rng.randomize()


func _ready() -> void:
	top_level = true
	for i in 3:
		var m: Node3D = TelegraphFx.new()
		m.name = "SweepMark%d" % i
		add_child(m)
		_marks.append(m)
	visible = true


func is_active() -> bool:
	return stage != "idle" and stage != "done"


## Starts the dispersal: `specs` = one dict per sweep pattern (orientation, tele, gap, sweep, pause).
func begin(specs: Array, ret_time: float, is_gentle: bool, target: Node3D = null) -> void:
	_queue = specs.duplicate(true)
	return_time = maxf(ret_time, 0.5)
	gentle = is_gentle
	patterns_done = 0
	hits = 0
	revealed = false
	pattern = {}
	lanes = []
	_hide_bats()
	_next_pattern(target)


## Stops everything at once (reset / phase change / defeat): marks, bats, return - nothing lingers.
func stop() -> void:
	stage = "idle"
	stage_time = 0.0
	_queue.clear()
	pattern = {}
	lanes = []
	for m in _marks:
		(m as Node3D).call("hide_mark")
	_hide_bats()


func tick(delta: float, target: Node3D) -> void:
	_t += delta
	if stage == "idle" or stage == "done":
		return
	stage_time += delta
	match stage:
		"tele":
			_update_marks(clampf(stage_time / maxf(float(pattern.get("tele", 1.8)), 0.01), 0.0, 1.0))
			_gather_bats()
			if stage_time >= float(pattern.get("tele", 1.8)):
				_begin_sweep()
		"sweep":
			_tick_sweep(target)
		"pause":
			if stage_time >= float(pattern.get("pause", 0.0)):
				_next_pattern(target)
		"return":
			_tick_return(delta, target)


# --- Lanes (pure geometry) -----------------------------------------------------------------------------------

## Sweep axis (the bats' flight direction, unit) for an orientation.
static func axis_of(orientation: String) -> Vector3:
	return Vector3(1, 0, 0) if orientation == "ew" else Vector3(0, 0, 1)


## Lateral axis (across the lanes) for an orientation.
static func lateral_of(orientation: String) -> Vector3:
	return Vector3(0, 0, 1) if orientation == "ew" else Vector3(1, 0, 0)


## Three lanes across the square [c +- h]: the safe lane is SAFE_SHARE of the width, the other two split the rest.
## Each lane: {"index", "safe", "v0", "v1", "vc", "width"} (v = lateral coordinate from the centre). The outer
## lanes extend beyond the square for membership (every point belongs to exactly one lane).
static func lane_layout(h: float, safe: int) -> Array:
	var out: Array = []
	var total := 2.0 * h
	var ws := total * SAFE_SHARE
	var wd := (total - ws) * 0.5
	var v := -h
	for i in LANES:
		var w := ws if i == safe else wd
		out.append({"index": i, "safe": i == safe, "v0": v, "v1": v + w, "vc": v + w * 0.5, "width": w})
		v += w
	return out


## Lane index of lateral coordinate `v` in a layout (outer lanes are open-ended).
static func lane_of(layout: Array, v: float) -> int:
	for i in layout.size():
		if v < float((layout[i] as Dictionary)["v1"]) or i == layout.size() - 1:
			return i
	return layout.size() - 1


## Lane index at a world point for the current pattern (-1 when no pattern is shown).
func lane_index_at(pos: Vector3) -> int:
	if lanes.is_empty():
		return -1
	var lat := lateral_of(String(pattern.get("orientation", "ns")))
	return lane_of(lanes, (pos - center).dot(lat))


func safe_lane() -> int:
	return int(pattern.get("safe", -1))


func danger_lanes() -> Array:
	return (pattern.get("order", []) as Array).duplicate()


## Picks the safe lane for a pattern from where Krystal stands (`v` lateral): always a NEIGHBOUR of her lane in
## an equal-thirds split (so it is reachable within the warning); Gentle takes the nearer neighbour.
static func choose_safe(h: float, v: float, is_gentle: bool, r: RandomNumberGenerator) -> int:
	var third := 2.0 * h / 3.0
	var p := clampi(int(floor((v + h) / third)), 0, LANES - 1)
	var options: Array = []
	if p - 1 >= 0:
		options.append(p - 1)
	if p + 1 < LANES:
		options.append(p + 1)
	if options.size() == 1:
		return int(options[0])
	if is_gentle:
		var mid := -h + third * (float(p) + 0.5)
		return p - 1 if v < mid else p + 1
	return int(options[r.randi_range(0, options.size() - 1)])


# --- Stages --------------------------------------------------------------------------------------------------

func _next_pattern(target: Node3D) -> void:
	if _queue.is_empty():
		_begin_return(target)
		return
	var spec: Dictionary = _queue.pop_front()
	var orient := String(spec.get("orientation", "ns"))
	var ax := axis_of(orient)
	var lat := lateral_of(orient)
	var tp := center
	if target != null and is_instance_valid(target):
		tp = target.global_position
	var v := (tp - center).dot(lat)
	var safe := int(spec["safe"]) if spec.has("safe") else choose_safe(half, v, gentle, rng)
	lanes = lane_layout(half, safe)
	var her := lane_of(lanes, v)
	last_target_lane = her
	var order: Array = []
	for i in LANES:
		if i != safe and i != her:
			order.append(i)
	if her != safe:
		order.append(her)           # her own lane sweeps last
	pattern = spec.duplicate()
	pattern["orientation"] = orient
	pattern["safe"] = safe
	pattern["order"] = order
	pattern["axis"] = ax
	pattern["lateral"] = lat
	var signs := {}
	for k in order.size():
		signs[int(order[k])] = 1.0 if k % 2 == 0 else -1.0
	pattern["signs"] = signs
	_fronts.clear()
	_hit_lanes.clear()
	stage = "tele"
	stage_time = 0.0
	_show_marks()
	_update_marks(0.0)
	lane_marked.emit(pattern)


func _begin_sweep() -> void:
	stage = "sweep"
	stage_time = 0.0
	for m in _marks:
		(m as Node3D).call("set_progress", 1.0, true)
	for l in pattern["order"]:
		_fronts[int(l)] = _front_at(int(l), 0.0)


func _front_at(lane: int, t: float) -> float:
	var sg: float = float((pattern["signs"] as Dictionary).get(lane, 1.0))
	var k := clampf(t / maxf(float(pattern.get("sweep", 1.2)), 0.01), 0.0, 1.0)
	return sg * lerpf(-(half + EDGE_PAD), half + EDGE_PAD, k)


func _tick_sweep(target: Node3D) -> void:
	var order: Array = pattern["order"]
	var gap := float(pattern.get("gap", 1.0))
	var sweep_len := float(pattern.get("sweep", 1.2))
	var all_done := true
	for k in order.size():
		var lane := int(order[k])
		var t := stage_time - float(k) * gap
		if t < sweep_len:
			all_done = false
		if t < 0.0:
			continue
		var prev: float = float(_fronts.get(lane, _front_at(lane, 0.0)))
		var now := _front_at(lane, t)
		_fronts[lane] = now
		_place_lane_bats(k, lane, now, t < sweep_len)
		if t >= sweep_len:
			(_marks[k] as Node3D).call("hide_mark")
		if not _hit_lanes.has(lane) and target != null and is_instance_valid(target):
			_test_hit(lane, prev, now, target)
			if stage != "sweep":
				return             # that hit felled her and the boss stopped the swarm inside it: nothing may restart
	if all_done:
		patterns_done += 1
		for m in _marks:
			(m as Node3D).call("hide_mark")
		_hide_lane_bats()
		if _queue.is_empty():
			_begin_return(target)
		else:
			stage = "pause"
			stage_time = 0.0


## Did the bat front of `lane` cross her (moving prev -> now) while she stood in that lane? One hit at most.
func _test_hit(lane: int, prev: float, now: float, target: Node3D) -> void:
	var ax: Vector3 = pattern["axis"]
	var lat: Vector3 = pattern["lateral"]
	var p := target.global_position
	var u := (p - center).dot(ax)
	var sg: float = float((pattern["signs"] as Dictionary).get(lane, 1.0))
	var crossed := (prev < u and u <= now) if sg > 0.0 else (prev > u and u >= now)
	if not crossed:
		return
	_hit_lanes[lane] = true            # the front passed her: this lane has resolved for her
	if lane_of(lanes, (p - center).dot(lat)) != lane:
		return
	if absf(p.y - center.y) > MAX_DY:
		return
	var from := center + ax * (u - sg * LOS_BACK) + lat * (p - center).dot(lat) + Vector3.UP * BAT_HEIGHT
	if is_inside_tree() and target.is_inside_tree():
		if not Combat.has_line_of_sight(get_world_3d().direct_space_state, from, Combat.aim_point(target), [target], Combat.LOS_MASK):
			return
	var dealt := 0.0
	if hit_func.is_valid():
		dealt = float(hit_func.call(target, ax * sg))
	if dealt > 0.0:
		hits += 1
	sweep_hit.emit(lane, dealt)


func _begin_return(target: Node3D) -> void:
	stage = "return"
	stage_time = 0.0
	for m in _marks:
		(m as Node3D).call("hide_mark")
	_hide_lane_bats()
	var start := center
	if not pattern.is_empty():
		var order: Array = pattern["order"]
		var last := int(order[order.size() - 1]) if not order.is_empty() else 0
		var ax: Vector3 = pattern["axis"]
		var lat: Vector3 = pattern["lateral"]
		var sg: float = float((pattern["signs"] as Dictionary).get(last, 1.0))
		start = center + ax * sg * (half - 0.5) + lat * float((lanes[last] as Dictionary)["vc"])
	true_pos = Vector3(start.x, center.y + RETURN_HEIGHT, start.z)
	var tp := true_pos
	if target != null and is_instance_valid(target):
		tp = target.global_position
	var d := Vector2(tp.x - true_pos.x, tp.z - true_pos.z).length()
	_true_speed = maxf(d / maxf(return_time * 0.85, 0.3), 4.0)
	_ensure_return_bats()
	if _true_bat != null:
		_true_bat.visible = true
		_true_bat.global_position = true_pos
	for i in _decoys.size():
		var b := _decoys[i] as Node3D
		b.visible = true
		b.global_position = true_pos + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.3, 0.5), rng.randf_range(-1.2, 1.2))
		var a := rng.randf_range(0.0, TAU)
		_decoy_dirs[i] = Vector3(cos(a), rng.randf_range(0.1, 0.5), sin(a)).normalized() * rng.randf_range(3.5, 5.5)


func _tick_return(delta: float, target: Node3D) -> void:
	var tp := true_pos
	if target != null and is_instance_valid(target):
		tp = target.global_position
	var to := Vector3(tp.x - true_pos.x, 0.0, tp.z - true_pos.z)
	var dist := to.length()
	var step := _true_speed * delta
	if dist > 0.001:
		var wob := Vector3(-to.z, 0.0, to.x) / dist * sin(_t * 5.0) * 0.6 * delta
		true_pos += to / dist * minf(step, maxf(dist - REFORM_DIST * 0.8, 0.0)) + wob
	var k := clampf(stage_time / return_time, 0.0, 1.0)
	true_pos.y = center.y + lerpf(RETURN_HEIGHT, 1.5, k)
	if _true_bat != null:
		_true_bat.global_position = true_pos
		Fx.flap(_true_bat, _t, 1.0)
		if dist > 0.01:
			_true_bat.rotation.y = atan2(-to.x, -to.z)
	for i in _decoys.size():
		var b := _decoys[i] as Node3D
		b.global_position += (_decoy_dirs[i] as Vector3) * delta
		Fx.flap(b, _t + float(i) * 0.37, 1.0)
		b.scale = Vector3.ONE * maxf(1.0 - k, 0.05)
	# Candle-light catches the true bat: revealed early.
	for c in candles:
		if is_instance_valid(c) and bool(c.call("is_lit")) and bool(c.call("in_pool", true_pos)):
			revealed = true
			_finish_return(true)
			return
	var flat := Vector2(tp.x - true_pos.x, tp.z - true_pos.z).length()
	if flat <= REFORM_DIST or stage_time >= return_time:
		_finish_return(false)


func _finish_return(was_revealed: bool) -> void:
	stage = "done"
	var at := Vector3(true_pos.x, center.y, true_pos.z)
	_hide_bats()
	returned.emit(was_revealed, at)


# --- Marks & bats (views) -------------------------------------------------------------------------------------

func _show_marks() -> void:
	var ax: Vector3 = pattern["axis"]
	var lat: Vector3 = pattern["lateral"]
	var order: Array = pattern["order"]
	for k in 2:
		var m := _marks[k] as Node3D
		if k >= order.size():
			m.call("hide_mark")
			continue
		var lane := int(order[k])
		var l: Dictionary = lanes[lane]
		var sg: float = float((pattern["signs"] as Dictionary).get(lane, 1.0))
		var base := center + lat * float(l["vc"])
		m.call("show_lane", base - ax * sg * half, base + ax * sg * half, float(l["width"]) - 0.2, TelegraphFx.DANGER)
	var s: Dictionary = lanes[int(pattern["safe"])]
	var pts: Array = []
	for i in SAFE_SPOTS:
		var u := lerpf(-half + 1.5, half - 1.5, float(i) / float(SAFE_SPOTS - 1))
		pts.append(center + lat * float(s["vc"]) + ax * u)
	var r := 1.1 if bool(Settings.get_value("high_visibility_cues")) else 0.8
	(_marks[2] as Node3D).call("show_spots", pts, r, SAFE_COLOR)


func _update_marks(k: float) -> void:
	for m in _marks:
		(m as Node3D).call("set_progress", k, k >= 0.6)


func _ensure_lane_bats() -> void:
	if not _lane_bats.is_empty():
		return
	for i in 2 * BATS_PER_LANE:
		var b := Fx.bat_node(rng.randf_range(0.85, 1.15), false)
		add_child(b)
		b.visible = false
		_lane_bats.append(b)


func _ensure_return_bats() -> void:
	if _true_bat == null:
		_true_bat = Fx.bat_node(1.7, true)
		add_child(_true_bat)
		_true_bat.visible = false
	while _decoys.size() < (2 if gentle else DECOYS):
		var b := Fx.bat_node(rng.randf_range(0.85, 1.1), false)
		add_child(b)
		b.visible = false
		_decoys.append(b)
		_decoy_dirs.append(Vector3.ZERO)


## Before the sweep: each flock hovers at the start edge of its lane.
func _gather_bats() -> void:
	_ensure_lane_bats()
	var order: Array = pattern["order"]
	for k in order.size():
		var lane := int(order[k])
		var sg: float = float((pattern["signs"] as Dictionary).get(lane, 1.0))
		_place_lane_bats(k, lane, -sg * (half + EDGE_PAD * 0.5), true)


func _place_lane_bats(slot: int, lane: int, front: float, on: bool) -> void:
	_ensure_lane_bats()
	var ax: Vector3 = pattern["axis"]
	var lat: Vector3 = pattern["lateral"]
	var l: Dictionary = lanes[lane]
	var sg: float = float((pattern["signs"] as Dictionary).get(lane, 1.0))
	for i in BATS_PER_LANE:
		var b := _lane_bats[slot * BATS_PER_LANE + i] as Node3D
		b.visible = on
		if not on:
			continue
		var f := (float(i) + 0.5) / float(BATS_PER_LANE)
		var v := lerpf(float(l["v0"]) + 0.4, float(l["v1"]) - 0.4, f)
		var lag := sin(float(i) * 2.3) * 0.5
		var h := BAT_HEIGHT + sin(_t * 3.0 + float(i)) * 0.25
		b.global_position = center + ax * (front - sg * absf(lag)) + lat * v + Vector3.UP * h
		b.rotation.y = atan2(-ax.x * sg, -ax.z * sg)
		Fx.flap(b, _t + float(i) * 0.31, 1.0)


func _hide_lane_bats() -> void:
	for b in _lane_bats:
		(b as Node3D).visible = false


func _hide_bats() -> void:
	_hide_lane_bats()
	if _true_bat != null:
		_true_bat.visible = false
	for b in _decoys:
		(b as Node3D).visible = false


func true_bat_node() -> Node3D:
	return _true_bat


func true_bat_position() -> Vector3:
	return true_pos
