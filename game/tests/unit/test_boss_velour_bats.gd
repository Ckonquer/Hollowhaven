extends "res://tests/test_case.gd"
## Count Velour phase B (module C6a, MP 13.1) - src/enemies/velour/bat_swarm.gd and the boss around it: lane
## geometry (three lanes, ONE broad safe lane, every point in exactly one lane), the safe lane always a neighbour
## of hers (Gentle: the nearer one), her own lane sweeping last, a lane hitting at most once and only when the bat
## front crosses her, never through a wall; the TRUE returning bat wears his collar / crown, candle-light reveals it
## early (longer, stronger window) and otherwise he reforms beside her; the dispersal is capped (never invulnerable
## indefinitely); Gentle one pattern, Standard two; at most ONE Velvet Wing helper alive (Gentle one in total) and
## it never winds up while he commits to an attack.
## Headless, manual ticks, no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/count_velour.gd")
const Swarm := preload("res://src/enemies/velour/bat_swarm.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const EnemyBase := preload("res://src/enemies/enemy_base.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const SPEC := {"orientation": "ns", "tele": 1.8, "gap": 1.0, "sweep": 1.2, "pause": 0.8}

var _nodes: Array = []
var _hits: Array = []


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false

	func _init() -> void:
		health = preload("res://src/player/player_health.gd").new()
		health.name = "Health"
		health.max_hp = 5000.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


var _saved_assist: Variant = false        # Settings "timing_assist" pinned off (exact timings below), restored after


func before_each() -> void:
	fresh_state()
	_saved_assist = Settings.get_value("timing_assist")
	Settings.set_value("timing_assist", false)
	_nodes.clear()
	_hits.clear()
	EnemyBase.reset_attack_tokens()


func after_each() -> void:
	Settings.set_value("timing_assist", _saved_assist)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.get_parent() == self:
			e.queue_free()
	_nodes.clear()
	EnemyBase.reset_attack_tokens()
	await wait_frames(2)


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _candle(pos: Vector3, lit: bool = true) -> Node3D:
	var c: Node3D = WardCandle.new()
	c.setup({"id": "c%d" % _nodes.size(), "lit": lit, "pool_radius": 3.2})
	add_child(c)
	c.global_position = pos
	_nodes.append(c)
	return c


func _swarm(candles: Array = []) -> Node3D:
	var s: Node3D = Swarm.new()
	s.setup({"center": CENTER, "half": 12.0, "candles": candles, "seed": 4, "hit_func": Callable(self, "_hit")})
	add_child(s)
	_nodes.append(s)
	return s


func _hit(t: Node3D, _dir: Vector3) -> float:
	var h: Node = t.get("health")
	var dealt: float = float(h.apply_damage(12.0, null, Vector3.FORWARD))
	_hits.append(dealt)
	return dealt


func _run(s: Node3D, target: Node3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001 and String(s.get("stage")) != "done":
		s.call("tick", DT, target)
		t += DT


## Lateral coordinate at the centre of lane `i` of the current pattern.
func _lane_point(s: Node3D, i: int, u: float = 0.0) -> Vector3:
	var p: Dictionary = s.get("pattern")
	var lanes: Array = s.get("lanes")
	var lat: Vector3 = p["lateral"]
	var ax: Vector3 = p["axis"]
	return CENTER + lat * float((lanes[i] as Dictionary)["vc"]) + ax * u


func _boss(target: Node3D, candles: Array = [], intensity: int = 1) -> Node3D:
	var b: Node3D = Factory.create("count_velour", {"arena_center": CENTER, "arena_radius": 12.0, "candles": candles, "seed": 9,
		"helper_points": [Vector3(-10, 0, 9), Vector3(10, 0, 9)]}, CENTER)
	add_child(b)
	b.set_process(false)
	b.target_override = target
	b.intensity_override = intensity
	b.fast_defeat = true
	_nodes.append(b)
	return b


func _tick_until(b: Node, s: String, max_t: float = 15.0) -> float:
	var t := 0.0
	while String(b.state) != s and t < max_t:
		b.tick(DT)
		t += DT
	return t


# --- Lane geometry ---------------------------------------------------------------------------------------------

func test_lane_layout_one_broad_safe_lane_covering_everything() -> void:
	for safe in 3:
		var lanes: Array = Swarm.lane_layout(12.0, safe)
		assert_eq(lanes.size(), 3)
		var total := 0.0
		var safes := 0
		for l in lanes:
			total += float(l["width"])
			if bool(l["safe"]):
				safes += 1
				assert_almost(float(l["width"]), 24.0 * Swarm.SAFE_SHARE, 0.001, "the safe lane is the broad one")
			else:
				assert_true(float(l["width"]) < 24.0 * Swarm.SAFE_SHARE, "danger lanes are narrower")
		assert_eq(safes, 1, "exactly one safe lane")
		assert_almost(total, 24.0, 0.001, "the lanes span the arena")
		assert_eq(Swarm.lane_of(lanes, -40.0), 0, "outer lanes are open-ended")
		assert_eq(Swarm.lane_of(lanes, 40.0), 2)
		for i in 3:
			assert_eq(Swarm.lane_of(lanes, float((lanes[i] as Dictionary)["vc"])), i)


func test_safe_lane_is_always_a_reachable_neighbour() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for k in 60:
		var v := -11.5 + 23.0 * float(k) / 59.0
		var p := clampi(int(floor((v + 12.0) / 8.0)), 0, 2)
		for gentle in [false, true]:
			var s := Swarm.choose_safe(12.0, v, gentle, r)
			assert_eq(absi(s - p), 1, "safe lane %d next to her lane %d (v %.1f)" % [s, p, v])
			if gentle:
				var mid := -12.0 + 8.0 * (float(p) + 0.5)
				var want := 1
				if p == 1:
					want = 0 if v < mid else 2
				assert_eq(s, want, "Gentle: the nearer neighbour")


# --- Sweeps -----------------------------------------------------------------------------------------------------

func test_safe_lane_is_safe_and_her_lane_sweeps_last() -> void:
	var d := _dummy(Vector3(-11, 0, 0))
	var s := _swarm()
	var marked: Array = []
	s.lane_marked.connect(func(p: Dictionary) -> void: marked.append(p))
	s.call("begin", [SPEC], 2.2, false, d)
	assert_eq(String(s.get("stage")), "tele")
	var safe := int(s.call("safe_lane"))
	var order: Array = s.call("danger_lanes")
	assert_eq(order.size(), 2, "two lanes are swept")
	assert_false(order.has(safe))
	assert_eq(int(order[1]), int(s.call("lane_index_at", d.global_position)), "the lane she stands in sweeps last")
	var marks: Array = s.get("_marks")
	assert_eq(String((marks[0] as Node3D).get("kind")), "lane", "danger lanes: red lanes with arrows")
	assert_eq(String((marks[2] as Node3D).get("kind")), "spots", "the safe lane: a dotted row of rings (a different shape)")
	# Step into the safe lane during the warning: nothing touches her.
	d.global_position = _lane_point(s, safe, 3.0)
	var hp0: float = float(d.health.hp)
	_run(s, d, 12.0)
	assert_eq(_hits.size(), 0, "the safe lane stays safe")
	assert_almost(float(d.health.hp), hp0, 0.001)
	assert_eq(String(s.get("stage")), "done")
	assert_eq(marked.size(), 1)


func test_a_danger_lane_hits_once_when_the_front_crosses_her() -> void:
	var d := _dummy(Vector3(-8, 0, 0))
	var s := _swarm()
	var sweeps: Array = []
	s.sweep_hit.connect(func(lane: int, dealt: float) -> void: sweeps.append([lane, dealt]))
	s.call("begin", [SPEC], 2.2, false, d)
	var order: Array = s.call("danger_lanes")
	var first := int(order[0])
	d.global_position = _lane_point(s, first, 2.0)
	# Nothing during the warning.
	var t := 0.0
	while t < 1.75:
		s.call("tick", DT, d)
		t += DT
	assert_eq(_hits.size(), 0, "no damage during the warning")
	_run(s, d, 12.0)
	assert_eq(_hits.size(), 1, "one hit from her lane")
	assert_almost(float(_hits[0]), 12.0, 0.01, "through her health")
	assert_eq(sweeps.size(), 1)
	assert_eq(int(sweeps[0][0]), first)


func test_no_sweep_damage_behind_a_wall() -> void:
	var d := _dummy(Vector3(-8, 0, 0))
	var s := _swarm()
	s.call("begin", [SPEC], 2.2, false, d)
	var order: Array = s.call("danger_lanes")
	var first := int(order[0])
	var sg: float = float(((s.get("pattern") as Dictionary)["signs"] as Dictionary)[first])
	var ax: Vector3 = (s.get("pattern") as Dictionary)["axis"]
	d.global_position = _lane_point(s, first, 2.0)
	# A wall just upstream of her (the side the bats come from).
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 3.0, 1.2)
	cs.shape = bs
	w.add_child(cs)
	add_child(w)
	_nodes.append(w)
	bs.size = Vector3(0.6, 3.0, 1.2) if absf(ax.x) > 0.5 else Vector3(1.2, 3.0, 0.6)
	w.global_position = d.global_position - ax * sg * 0.8 + Vector3.UP * 1.5
	await wait_physics(2)
	_run(s, d, 12.0)
	assert_eq(_hits.size(), 0, "cover blocks the sweep")


# --- Return / reveal --------------------------------------------------------------------------------------------

func test_true_bat_wears_the_collar_and_candle_light_reveals_it() -> void:
	var c := _candle(Vector3(0, 0, 6), true)
	var d := _dummy(Vector3(0, 0, 6))        # standing in the lit pool
	var s := _swarm([c])
	var got: Array = []
	s.returned.connect(func(rv: bool, at: Vector3) -> void: got.append([rv, at]))
	s.call("begin", [SPEC], 2.2, false, d)
	d.global_position = Vector3(1.0, 0, 6)       # she waits in the lit pool while the bats return
	_run(s, d, 30.0)
	assert_eq(got.size(), 1, "the bats return once")
	var tb: Node3D = s.call("true_bat_node")
	assert_not_null(tb)
	assert_eq(String(tb.name), "TrueBat", "a distinct returning bat")
	assert_true(tb.scale.x > 1.3, "bigger than the others")
	assert_true(tb.find_children("*", "MeshInstance3D", true, false).size() > 12, "collar ruff, gold ring and crown pieces")
	assert_true(bool(got[0][0]), "candle-light revealed it")
	var at: Vector3 = got[0][1]
	assert_true(bool(c.call("in_pool", at)), "revealed inside the pool")


func test_without_candle_light_he_reforms_beside_her() -> void:
	var c := _candle(Vector3(0, 0, 6), false)
	var d := _dummy(Vector3(1, 0, 6))
	var s := _swarm([c])
	var got: Array = []
	s.returned.connect(func(rv: bool, at: Vector3) -> void: got.append([rv, at]))
	s.call("begin", [SPEC], 2.2, false, d)
	_run(s, d, 30.0)
	assert_eq(got.size(), 1)
	assert_false(bool(got[0][0]), "an unlit candle reveals nothing")
	var at: Vector3 = got[0][1]
	assert_true(Vector2(at.x - d.global_position.x, at.z - d.global_position.z).length() <= Swarm.REFORM_DIST + 0.3, "reforms beside her")


func test_boss_dispersal_reform_windows_and_cap() -> void:
	var c := _candle(Vector3(4, 0, 4), true)
	var d := _dummy(Vector3(4.5, 0, 4.5))       # in the lit pool
	var b := _boss(d, [c])
	b.start_fight()
	b.jump_to_phase(2)
	b.next_action = "disperse"
	_tick_until(b, "bats", 20.0)
	assert_eq(String(b.state), "bats")
	assert_false(bool(b.visual.visible), "he is the bats now")
	assert_false(bool(b.can_be_hit_by(d)), "untouchable while dispersed")
	var t := _tick_until(b, "reform", 30.0)
	assert_true(t < Boss.MAX_DISPERSED, "the dispersal ends on its own (%.1f s)" % t)
	assert_eq(int(b.reveals), 1, "the candle pool revealed him")
	assert_almost(float(b.get("_state_len")), float(Boss.T_REFORM[1]) + Boss.REVEAL_BONUS, 0.001, "a longer window")
	assert_almost(float(b.health.damage_taken_mult), Boss.REVEAL_MULT, 0.001, "and a stronger one")
	b.tick(DT)
	assert_true(bool(b.is_reachable()) and bool(b.can_be_hit_by(d)), "reformed at reachable height")
	# Hard cap: even if the swarm never returned, he reforms after MAX_DISPERSED.
	var b2 := _boss(d, [], 1)
	b2.start_fight()
	b2.jump_to_phase(2)
	b2.next_action = "disperse"
	_tick_until(b2, "bats", 20.0)
	(b2.get("_swarm") as Node3D).set("return_time", 999.0)
	(b2.get("_swarm") as Node3D).set("_queue", [SPEC, SPEC, SPEC, SPEC, SPEC, SPEC])
	var t2 := _tick_until(b2, "reform", 40.0)
	assert_eq(String(b2.state), "reform")
	assert_true(t2 <= Boss.MAX_DISPERSED + 0.2, "never invulnerable longer than the cap (%.1f s)" % t2)


func test_gentle_one_pattern_standard_two() -> void:
	var d := _dummy(Vector3(0, 0, 4))
	for i in [0, 1]:
		var b := _boss(d, [], i)
		b.start_fight()
		b.jump_to_phase(2)
		b.next_action = "disperse"
		_tick_until(b, "bats", 20.0)
		_tick_until(b, "reform", 30.0)
		var done := int((b.get("_swarm") as Node3D).get("patterns_done"))
		assert_eq(done, 1 if i == 0 else 2, "intensity %d: %d pattern(s)" % [i, done])
		b.reset_fight()


# --- Helper -----------------------------------------------------------------------------------------------------

func _wings() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.is_queued_for_deletion() and String(e.get("enemy_id")) == "velvet_wing":
			out.append(e)
	return out


func test_at_most_one_helper_and_it_never_overlaps_his_attacks() -> void:
	var d := _dummy(Vector3(0, 0, 4))
	var b := _boss(d, [], 2)
	b.start_fight()
	b.jump_to_phase(2)
	var max_alive := 0
	for n in 3:
		b.next_action = "disperse"
		_tick_until(b, "disperse", 20.0)
		max_alive = maxi(max_alive, _wings().size())
		var w: Node = b.call("helper_node")
		if w != null:
			assert_true(float(w.get("_cooldown")) >= 0.0)
		# While he commits (bats), the helper is held.
		b.tick(DT)
		if w != null:
			assert_true(float(w.get("_cooldown")) >= 0.5, "the helper cannot wind up while he commits")
		_tick_until(b, "reform", 30.0)
		max_alive = maxi(max_alive, _wings().size())
		b.set("_helper_cd", 0.0)                     # ready again: the cap alone must hold
	assert_eq(max_alive, 1, "never more than one Velvet Wing")
	assert_eq(int(b.helpers_summoned), 1, "a living helper is never replaced")
	# Once it is gone, another may come (Standard / Intense) - still one at a time.
	var w2: Node = b.call("helper_node")
	if w2 != null:
		w2.queue_free()
	await wait_frames(1)
	b.next_action = "disperse"
	_tick_until(b, "disperse", 20.0)
	assert_eq(int(b.helpers_summoned), 2)
	assert_eq(_wings().size(), 1)


func test_gentle_summons_one_helper_in_total_and_phase_c_dismisses_it() -> void:
	var d := _dummy(Vector3(0, 0, 4))
	var b := _boss(d, [], 0)
	b.start_fight()
	b.jump_to_phase(2)
	b.next_action = "disperse"
	_tick_until(b, "disperse", 20.0)
	assert_eq(int(b.helpers_summoned), 1)
	var w: Node = b.call("helper_node")
	assert_not_null(w)
	w.queue_free()
	await wait_frames(1)
	b.set("_helper_cd", 0.0)
	_tick_until(b, "reform", 30.0)
	b.next_action = "disperse"
	_tick_until(b, "disperse", 20.0)
	assert_eq(int(b.helpers_summoned), 1, "Gentle: one helper in total")
	# Standard: the helper leaves when phase C begins.
	var b2 := _boss(d, [], 1)
	b2.start_fight()
	b2.jump_to_phase(2)
	b2.next_action = "disperse"
	_tick_until(b2, "disperse", 20.0)
	var h: Node = b2.call("helper_node")
	assert_not_null(h)
	b2.jump_to_phase(3)
	assert_null(b2.call("helper_node"), "phase C clears the helper")
	assert_true(not is_instance_valid(h) or h.is_queued_for_deletion())


# --- Review C6a: a sweep hit that ends the encounter stops the swarm for good ------------------------------------

## The boss's hit_func can fell her, and Game emits player_died synchronously: the boss's reset stops the swarm
## INSIDE that hit. The sweep tick must not carry on and start the return flight of a stopped swarm (frozen bats).
func test_a_hit_that_stops_the_swarm_never_restarts_the_return() -> void:
	var d := _dummy(Vector3(0, 0, 0))
	var s: Node3D = Swarm.new()
	var stops: Array = [0]
	var fell := func(_t: Node3D, _dir: Vector3) -> float:
		stops[0] = int(stops[0]) + 1
		s.call("stop")                        # what reset_fight does when the hit fells her
		return 12.0
	s.setup({"center": CENTER, "half": 12.0, "seed": 4, "hit_func": fell})
	add_child(s)
	_nodes.append(s)
	# One pattern (tele 1, gap 1, sweep 1): her lane (the last, flying toward -z) crosses her on the very tick it ends.
	var spec := {"orientation": "ns", "tele": 1.0, "gap": 1.0, "sweep": 1.0, "pause": 0.0, "safe": 2}
	s.call("begin", [spec], 2.0, false, d)
	d.global_position = _lane_point(s, 1, -(12.0 + Swarm.EDGE_PAD) + 0.1)
	assert_eq(int(s.call("lane_index_at", d.global_position)), 1)
	assert_eq(int((s.call("danger_lanes") as Array)[-1]), 1, "her lane sweeps last")
	var t := 0.0
	while t < 5.0 and int(stops[0]) == 0:
		s.call("tick", 0.25, d)
		t += 0.25
	assert_eq(int(stops[0]), 1, "the sweep reached her")
	assert_eq(String(s.get("stage")), "idle", "stopped means stopped")
	assert_false(bool(s.call("is_active")))
	var tb: Node3D = s.call("true_bat_node")
	assert_true(tb == null or not tb.visible, "no returning bat frozen in the Gallery")
