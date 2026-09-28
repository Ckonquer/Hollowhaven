extends "res://tests/test_case.gd"
## Regression tests from the independent combat review: killing blows go straight to defeat (no
## flinch / boss climb first), leash healing waits after hits, the scorched boss never lands on a
## brazier, the stalker turns over smoothly when leaping from the floor back to the ceiling,
## position-based spawner ids resolve after positioning, reduce_flashing gives steady telegraph
## tints, and enemy drops become persistent world pickups.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Stalker := preload("res://src/enemies/stalker.gd")
const Spawner := preload("res://src/enemies/enemy_spawner.gd")
const BramblingVisual := preload("res://src/enemies/brambling_visual.gd")

const DT := 0.05

var _nodes: Array = []
var _saved_area: Node = null


class Dummy extends CharacterBody3D:
	var health: Node

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("reduce_flashing", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("world_item"):
		n.queue_free()
	for c in get_children():
		if c.name.begins_with("BurnedAnchor"):
			c.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("reduce_flashing", false)
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3) -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	_nodes.append(d)
	return d


func _enemy(id: String, target: Node3D, pos: Vector3 = Vector3.ZERO, drops: bool = false) -> Node:
	var e: Node = Factory.create(id, {"home": pos, "no_drops": not drops})
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _tick_until(n: Node, s: String, max_t: float = 10.0) -> float:
	var t := 0.0
	while n.state != s and t < max_t:
		n.tick(DT)
		t += DT
	return t


# --- Killing blows ----------------------------------------------------------------------------------

func test_killing_blow_goes_straight_to_defeat() -> void:
	var d := _dummy(Vector3(0, 0, -1.5))
	var e := _enemy("brambling", d)
	_tick_until(e, "telegraph", 5.0)
	assert_eq(e.state, "telegraph")
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_eq(seen, ["dead"], "no flinch/chase flicker before the defeat (got %s)" % str(seen))
	# A non-lethal hit still staggers the wind-up (unchanged behaviour).
	Base.reset_attack_tokens()
	var e2 := _enemy("brambling", d, Vector3(0, 0, -0.2))
	_tick_until(e2, "telegraph", 5.0)
	assert_eq(e2.state, "telegraph")
	e2.health.apply_damage(5.0, d, Vector3.FORWARD)
	assert_eq(e2.state, "flinch")


func test_boss_killing_blow_skips_the_window_cap_climb() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs: Array = []
	var anchors := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "rb%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x * 0.8, 0.0, anchors[i].z * 0.8)
		brs.append(b)
		_nodes.append(b)
	var boss: Node = Factory.create("weaver_matron", {"arena_center": Vector3.ZERO, "anchors": anchors, "braziers": brs})
	add_child(boss)
	boss.set_process(false)
	boss.target_override = d
	boss.intensity_override = 1
	boss.fast_defeat = true
	_nodes.append(boss)
	_tick_until(boss, "cling", 6.0)
	(brs[0] as Node).call("light")
	_tick_until(boss, "scorched", 2.0)
	assert_eq(boss.state, "scorched")
	boss.health.apply_damage(60.0)         # x1.5 = 90 this window (cap is 96): still down
	assert_eq(boss.state, "scorched")
	boss.health.set_hp(10.0)
	var seen: Array = []
	boss.state_changed.connect(func(s: String) -> void: seen.append(s))
	boss.health.apply_damage(10.0)         # lethal, and it also crosses the 40% window cap
	await wait_frames(2)
	assert_false(seen.has("climb"), "the killing blow does not trigger the window-cap climb (%s)" % str(seen))
	assert_eq(boss.state, "gone")
	assert_true(bool(GameState.get_flag("weaver_defeated")))


# --- Leash healing ------------------------------------------------------------------------------------

func test_leash_healing_waits_after_being_hit() -> void:
	var d := _dummy(Vector3(0, 0, -6.0))
	var e := _enemy("brambling", d)
	_tick_until(e, "chase", 3.0)
	(e as Node3D).global_position = Vector3(0, 0, -12.0)   # dragged away from home
	d.global_position = Vector3(0, 0, -40.0)              # Krystal beyond the leash
	_tick_until(e, "return", 2.0)
	assert_eq(e.state, "return")
	e.health.apply_damage(12.0, d, Vector3.FORWARD)          # a parting hit while it walks home
	var hp: float = e.health.hp
	_tick_until(e, "return", 1.0)                          # (a flinch resolves back to return)
	for i in 20:                                           # 1 s: still inside the no-heal window
		e.tick(DT)
	assert_almost(float(e.health.hp), hp, 0.001, "no leash regen right after being hit")
	for i in 40:                                           # 2 more s: past the 2.5 s window
		e.tick(DT)
	assert_true(float(e.health.hp) > hp, "regenerates once Krystal has stopped hitting it")


# --- Boss scorch landing --------------------------------------------------------------------------------

func test_scorched_fall_lands_clear_of_the_brazier() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	# Real-layout style: each brazier sits directly under its anchor.
	var anchors := [Vector3(6.1, 7.5, 3.5), Vector3(-6.1, 7.5, 3.5), Vector3(0.0, 7.7, -7.0)]
	var brs: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "sb%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x, 0.0, anchors[i].z)
		brs.append(b)
		_nodes.append(b)
	var boss: Node = Factory.create("weaver_matron", {"arena_center": Vector3.ZERO, "anchors": anchors, "braziers": brs})
	add_child(boss)
	boss.set_process(false)
	boss.target_override = d
	boss.intensity_override = 1
	_nodes.append(boss)
	_tick_until(boss, "cling", 6.0)
	var clung: Vector3 = boss.get("_anchor")
	var idx := 0
	for i in 3:
		if (anchors[i] as Vector3).distance_to(clung) < 0.1:
			idx = i
	(brs[idx] as Node).call("light")                        # light the brazier right below it
	assert_eq(boss.state, "scorch_fall")
	var to: Transform3D = boss.get("_to")
	var bp: Vector3 = (brs[idx] as Node3D).global_position
	var flat := Vector2(to.origin.x - bp.x, to.origin.z - bp.z).length()
	assert_true(flat >= Boss.BRAZIER_CLEARANCE - 0.01, "lands clear of the brazier it hung over (%.2f m)" % flat)
	var from_c := Vector2(to.origin.x, to.origin.z).length()
	assert_true(from_c < Vector2(bp.x, bp.z).length(), "nudged toward the arena centre, not out into the wall")
	assert_true(from_c >= Boss.CENTRE_CLEARANCE - 0.01, "but not onto the centrepiece (%.2f m from the centre)" % from_c)
	assert_true(flat <= Boss.BRAZIER_CLEARANCE + 0.3, "only as far as needed (%.2f m)" % flat)
	_tick_until(boss, "scorched", 2.0)
	assert_eq(boss.state, "scorched", "and is stunned there as before")


## The arena centre holds the Heartseed cocoon: a scorched landing that starts near it (a centre
## anchor, a ceiling route over it) is pushed straight out to CENTRE_CLEARANCE; dead centre falls
## toward Krystal; landings already clear are left alone.
func test_scorch_landing_keeps_clear_of_the_centrepiece() -> void:
	var d := _dummy(Vector3(0, 0, 6))
	var boss: Node = Factory.create("weaver_matron", {"arena_center": Vector3.ZERO, "anchors": [Vector3(6, 8, 0), Vector3(0, 8, 1)], "braziers": []})
	add_child(boss)
	boss.set_process(false)
	boss.target_override = d
	_nodes.append(boss)
	for from in [Vector3(0.0, 8.0, -1.0), Vector3(0.3, 8.0, 0.4), Vector3(-2.0, 8.0, 0.5)]:
		var p: Vector3 = boss.scorch_landing(from)
		var off := Vector2(p.x, p.z)
		assert_true(off.length() >= Boss.CENTRE_CLEARANCE - 0.01, "%s lands clear of the centre (%.2f m)" % [str(from), off.length()])
		assert_true(off.normalized().dot(Vector2(from.x, from.z).normalized()) > 0.99, "pushed straight out, on the side it fell from")
		assert_almost(p.y, 0.0, 0.001, "on the floor")
	var p0: Vector3 = boss.scorch_landing(Vector3(0.0, 8.0, 0.0))
	assert_almost(Vector2(p0.x, p0.z).length(), Boss.CENTRE_CLEARANCE, 0.01, "dead centre still lands clear")
	assert_true(p0.z > 0.0, "toward Krystal")
	var far: Vector3 = boss.scorch_landing(Vector3(5.0, 8.0, 1.0))
	assert_true(far.distance_to(Vector3(5.0, 0.0, 1.0)) < 0.001, "already clear: straight down (%s)" % str(far))


## Scorched while it drops onto Krystal kindling a brazier: it recoils clear of the brazier before it
## collapses, like any other scorched fall (it used to collapse on top of the bowl).
func test_scorch_during_a_drop_recoils_clear_of_the_brazier() -> void:
	var anchors := [Vector3(6.1, 7.5, 3.5), Vector3(-6.1, 7.5, 3.5), Vector3(0.0, 7.7, -7.0)]
	var brs: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "db%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x, 0.0, anchors[i].z)
		brs.append(b)
		_nodes.append(b)
	var bz: Vector3 = (brs[0] as Node3D).global_position
	var d := _dummy(bz + (Vector3.ZERO - bz).normalized() * 0.9)     # kindling it, right beside the bowl
	var boss: Node = Factory.create("weaver_matron", {"arena_center": Vector3.ZERO, "anchors": anchors, "braziers": brs})
	add_child(boss)
	boss.set_process(false)
	boss.target_override = d
	boss.intensity_override = 1
	_nodes.append(boss)
	_tick_until(boss, "drop", 15.0)
	assert_eq(boss.state, "drop", "it drops on Krystal's spot")
	(brs[0] as Node).call("light")                                   # the kindle completes mid-drop
	_tick_until(boss, "scorched", 2.0)
	assert_eq(boss.state, "scorched")
	var bp: Vector3 = (boss as Node3D).global_position
	var flat := Vector2(bp.x - bz.x, bp.z - bz.z).length()
	assert_true(flat >= Boss.BRAZIER_CLEARANCE - 0.01, "never collapses right beside a brazier (%.2f m)" % flat)
	assert_almost(bp.y, 0.0, 0.01, "on the floor")


# --- Stalker turn-over -----------------------------------------------------------------------------------

func test_stalker_turns_over_smoothly_when_leaping_back_up() -> void:
	# Pure helper: opposite normals still rotate (Vector3.slerp alone would stay stuck at UP).
	var n := Stalker.turn_normal(Vector3.UP, Vector3.DOWN, Vector3.UP * 3.0, 0.1)
	assert_true(n.y < 0.99, "starts tipping over (%s)" % str(n))
	assert_almost(n.length(), 1.0, 0.001)
	var m := Vector3.UP
	for i in 60:
		m = Stalker.turn_normal(m, Vector3.DOWN, Vector3(0.3, 1.0, 0.0), 0.067)
	assert_true(m.y < -0.95, "ends upside down on the ceiling (%s)" % str(m))
	# In context: after a lunge it lands on the floor, then climbs back up through tilted poses.
	var d := _dummy(Vector3(0, 0, 0.5))
	var route: Array = []
	for i in 6:
		route.append(Vector3(-7.5 + 3.0 * float(i), 4.0, 0.0))
	var s: Node = Factory.create("weaver", {"route": route, "ambush_points": [Vector3.ZERO], "zone": "silk"})
	add_child(s)
	s.set_process(false)
	s.target_override = d
	s.intensity_override = 1
	s.light_override = 0.0
	s.los_override = 1
	_nodes.append(s)
	_tick_until(s, "rattle", 15.0)
	_tick_until(s, "landed", 3.0)
	_tick_until(s, "retreat", 2.0)
	assert_eq(s.state, "retreat")
	var tilted := false
	for i in 40:
		s.tick(1.0 / 60.0)
		var ny: float = (s.get("_normal") as Vector3).y
		tilted = tilted or (ny > -0.9 and ny < 0.9)
	assert_true(tilted, "the body tips over on the way up instead of snapping")


func _wall(x: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 10.0, 8.0)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(x, 2.0, 0.0)
	_nodes.append(body)


func _route_stalker(route: Array, target: Node3D) -> Node:
	var s: Node = Factory.create("weaver", {"route": route, "ambush_points": [target.global_position], "zone": "silk"})
	add_child(s)
	s.set_process(false)
	s.target_override = target
	s.intensity_override = 1
	s.light_override = 0.0
	s.los_override = 1
	_nodes.append(s)
	return s


## Runs a pass to completion and returns [min x, max x] of the stalker's positions.
func _run_pass(s: Node) -> Array:
	var lo := INF
	var hi := -INF
	var t := 0.0
	while s.state != "hidden" and t < 20.0:
		s.tick(DT)
		t += DT
		var x: float = (s as Node3D).global_position.x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return [lo, hi]


func test_stalker_never_crawls_through_rock_between_route_stretches() -> void:
	_wall(0.0)                                   # rock between x = -2 and x = 2
	await wait_physics(2)
	var d := _dummy(Vector3(6, 0, 0))
	var route := [Vector3(-8, 4, 0), Vector3(-5, 4, 0), Vector3(-2, 4, 0), Vector3(2, 4, 0), Vector3(5, 4, 0), Vector3(8, 4, 0)]
	var s := _route_stalker(route, d)
	assert_true(s.pass_overhead(), "a pass starts")
	assert_false(s.segment_ok(2), "the wall splits the route")
	assert_true(s.segment_ok(1) and s.segment_ok(3), "the rest is crawlable")
	var span := _run_pass(s)
	assert_eq(s.state, "hidden", "the pass ends")
	assert_true(float(span[0]) > 0.5, "stays on Krystal's side of the rock the whole time (min x %.2f)" % float(span[0]))


func test_stalker_treats_long_route_gaps_as_breaks() -> void:
	var d := _dummy(Vector3(-6, 0, 0))
	var route := [Vector3(-8, 4, 0), Vector3(-5, 4, 0), Vector3(15, 4, 0), Vector3(18, 4, 0)]
	var s := _route_stalker(route, d)
	assert_true(s.pass_overhead())
	assert_false(s.segment_ok(1), "a 20 m jump is not a crawlable segment")
	var span := _run_pass(s)
	assert_true(float(span[1]) < -4.0, "never crosses the gap (max x %.2f)" % float(span[1]))
	# Ambush + retreat also stay on the near stretch.
	s.set("_cooldown", 0.0)
	assert_true(s.start_ambush())
	var t := 0.0
	var hi := -INF
	while s.state != "hidden" and t < 20.0:
		s.tick(DT)
		t += DT
		hi = maxf(hi, (s as Node3D).global_position.x)
	assert_eq(s.state, "hidden")
	assert_true(hi < -4.0, "the retreat does not tunnel to the far stretch (max x %.2f)" % hi)


# --- Spawner ids -------------------------------------------------------------------------------------------

func test_spawner_without_id_uses_its_final_position() -> void:
	var p := Node3D.new()
	add_child(p)
	_nodes.append(p)
	p.global_position = Vector3(500, 0, 500)
	var a: Node3D = Spawner.new()
	a.setup({"enemy": "brambling", "count": 1, "respawn_minutes": -1.0})
	add_child(a)                            # added first, positioned afterwards (common pattern)
	a.global_position = Vector3(20, 0, -30)
	a.set_process(false)
	a.player_override = p
	var b: Node3D = Spawner.new()
	b.setup({"enemy": "brambling", "count": 1, "respawn_minutes": -1.0})
	add_child(b)
	b.global_position = Vector3(-40, 0, 12)
	b.set_process(false)
	b.player_override = p
	_nodes.append(a)
	_nodes.append(b)
	a.update_spawner()
	b.update_spawner()
	assert_ne(a.cleared_flag(), b.cleared_flag(), "distinct ids for distinct spawners")
	assert_eq(a.cleared_flag(), "spawner_cleared_brambling_20_-30", "id from the real position")
	# Clearing one never clears the other.
	p.global_position = Vector3(20, 0, -20)
	a.update_spawner()
	for e in a.alive.duplicate():
		(e as Node).set_physics_process(false)
		e.health.apply_damage(999.0)
	assert_true(a.is_cleared())
	assert_false(b.is_cleared(), "the other spawner is untouched")


func test_spawner_never_places_enemies_on_top_of_walls() -> void:
	# A 2.5 m high block (a ruin wall) covers half of the spawn circle.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10.0, 2.5, 20.0)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(5.0, 1.25, 0.0)
	_nodes.append(body)
	await wait_physics(2)
	var p := Node3D.new()
	add_child(p)
	_nodes.append(p)
	p.global_position = Vector3(-30, 0, 0)
	var s: Node3D = Spawner.new()
	s.setup({"enemy": "brambling", "count": 8, "radius": 4.0, "respawn_minutes": -1.0, "spawner_id": "wall_test", "min_player_distance": 0.0})
	add_child(s)
	s.global_position = Vector3(-0.5, 0.0, 0.0)
	s.set_process(false)
	s.player_override = p
	_nodes.append(s)
	s.update_spawner()
	assert_eq(s.alive.size(), 8)
	var on_top := 0
	for e in s.alive:
		(e as Node).set_physics_process(false)
		if (e as Node3D).global_position.y > 1.0:
			on_top += 1
		_nodes.append(e)
	assert_eq(on_top, 0, "no enemy starts on top of the wall")


# --- Comfort --------------------------------------------------------------------------------------------------

func test_reduce_flashing_gives_a_steady_telegraph_tint() -> void:
	var v: Node3D = BramblingVisual.new()
	add_child(v)
	_nodes.append(v)
	Settings.set_value("reduce_flashing", true)
	v.set_state("telegraph", 0.7)
	var alphas: Array = []
	for i in 12:
		v._process(0.04)
		if i >= 6:                                          # after the 0.18 s crouch ramp
			alphas.append(float((v.get("_tint_mat") as StandardMaterial3D).albedo_color.a))
	var lo: float = alphas.min()
	var hi: float = alphas.max()
	assert_true(lo > 0.1, "still clearly tinted red (%.2f)" % lo)
	assert_almost(hi - lo, 0.0, 0.001, "no pulsing with reduce_flashing")
	Settings.set_value("reduce_flashing", false)
	alphas.clear()
	for i in 12:
		v._process(0.04)
		alphas.append(float((v.get("_tint_mat") as StandardMaterial3D).albedo_color.a))
	var lo2: float = alphas.min()
	var hi2: float = alphas.max()
	assert_true(hi2 - lo2 > 0.05, "pulses normally otherwise")


# --- Drops --------------------------------------------------------------------------------------------------

func test_drops_become_persistent_world_pickups() -> void:
	var d := _dummy(Vector3(0, 0, -6.0))
	var e := _enemy("brambling", d, Vector3.ZERO, true)
	var before := GameState.dropped.size()
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	var fiber := 0
	for it in GameState.dropped.slice(before):
		if String(it["item"]) == "fiber":
			fiber += int(it["count"])
	assert_true(fiber >= 1, "the guaranteed fiber drop is a persistent pickup (GameState.dropped)")
	assert_eq(GameState.count_item("fiber"), 0, "not teleported straight into the backpack")
	assert_true(get_tree().get_nodes_in_group("world_item").size() >= 1, "a pickup node exists in the world")
