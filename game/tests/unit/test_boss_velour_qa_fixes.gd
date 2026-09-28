extends "res://tests/test_case.gd"
## Count Velour regressions from the Chapter Two QA bot (qa/tmp/bot/BUGS_MERGED.md):
##   CH2-005  phase C: the ward-candle stand he channels beside must never sit between him and Krystal - the stand's
##            body is on the world layer (Combat.LOS_MASK), so Combat.melee dropped every straight-on blow at his
##            channelling form silently (no spark, no hint, the channel completed). He now hovers BESIDE the candle
##            (square to her line to it) and eases round the stand if she steps into its shadow.
##   CH2-013  the per-window cap (WINDOW_CAP of his max health) was checked only after a hit, so the last blow of a
##            window overshot it (21% in one stagger window). The cap now trims the blow before it lands.
## Real Combat.melee swings against real ward-candle stands (physics line of sight). Headless, manual ticks (boss
## process off), no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/count_velour.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const EnemyBase := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const SWORD_DAMAGE := 18.0          # copper sword (data/items.gd)
const SWORD_REACH := 2.5
const SWING_ARC := 110.0            # player_logic.gd MELEE_ARC
const STAND_RADIUS := 0.3           # ward_candle.gd StandBody cylinder

var _nodes: Array = []


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


var _saved_assist: Variant = false


func before_each() -> void:
	fresh_state()
	_saved_assist = Settings.get_value("timing_assist")
	Settings.set_value("timing_assist", false)
	_nodes.clear()
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


## The Gallery's three ward candles (manor_layout ARENA, relative to its centre), all burning.
func _candles() -> Array:
	var out: Array = []
	var spots := {"north": Vector3(0, 0, -7.5), "southwest": Vector3(-6.5, 0, 3.75), "southeast": Vector3(6.5, 0, 3.75)}
	for id in spots:
		var c: Node3D = WardCandle.new()
		c.setup({"id": String(id), "lit": true, "pool_radius": 3.2})
		add_child(c)
		c.global_position = spots[id]
		_nodes.append(c)
		out.append(c)
	return out


func _boss(target: Node3D, candles: Array, intensity: int = 1) -> Node3D:
	var b: Node3D = Factory.create("count_velour", {"arena_center": CENTER, "arena_radius": 12.0, "candles": candles, "seed": 21,
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


func _tick(b: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		b.tick(DT)
		t += DT


func _to_channel(b: Node3D) -> Node3D:
	b.start_fight()
	_tick_until(b, "glide")
	b.jump_to_phase(3)
	b.next_action = "channel"
	_tick_until(b, "channel_fly", 10.0)
	return b.get("_channel_candle")


## Distance (XZ) from `c` to the segment a-b.
static func _seg_dist(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf(ac.dot(ab) / l2, 0.0, 1.0)
	return (ac - ab * t).length()


## Krystal's real swing (player.gd _melee_hit): from her chest, facing him.
func _swing(d: Node3D, b: Node3D) -> Array:
	var aim: Vector3 = b.call("get_aim_point")
	var fwd := Vector3(aim.x - d.global_position.x, 0.0, aim.z - d.global_position.z).normalized()
	return Combat.melee(d, d.global_position + Vector3.UP * 0.9, fwd, SWORD_REACH, SWING_ARC, SWORD_DAMAGE, ["enemy"], 4.0)


# --- CH2-005: the candle stand never eats a blow at his channelling form ------------------------------------------

func test_ch2_005_walking_straight_at_his_channel_lands_the_blow() -> void:
	var cs := _candles()
	var start := Vector3(0, 0, 1)
	var d := _dummy(start)
	var b := _boss(d, cs)
	var c := _to_channel(b)
	assert_not_null(c)
	_tick_until(b, "channel", 10.0)
	_tick(b, 0.3)
	var bp: Vector3 = b.global_position
	var cp: Vector3 = c.global_position
	assert_true(Vector2(bp.x - cp.x, bp.z - cp.z).length() < 1.6, "he still hovers beside the candle")
	assert_true(_seg_dist(start, bp, cp) > STAND_RADIUS + 0.2, "the stand is not on her line of approach")
	# She walks straight at him and stops within sword reach.
	var to_him := Vector3(bp.x - start.x, 0.0, bp.z - start.z)
	d.global_position = start + to_him.normalized() * (to_him.length() - 2.0)
	await wait_physics(2)                    # the stand bodies are in the physics space
	var hits := _swing(d, b)
	assert_eq(hits.size(), 1, "the straight-on blow lands (the stand is not in the way)")
	assert_eq(String(b.state), "stagger", "and staggers him, as the hint promises")
	assert_true(bool(c.call("is_lit")), "the candle he was snuffing stays lit")


func test_ch2_005_he_eases_round_the_stand_when_she_steps_behind_it() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	var c := _to_channel(b)
	_tick_until(b, "channel", 10.0)
	_tick(b, 0.3)
	var cp: Vector3 = c.global_position
	var bp: Vector3 = b.global_position
	# She circles to the far side of the candle: the stand is exactly between them, and he is within her reach.
	var behind := Vector3(cp.x - bp.x, 0.0, cp.z - bp.z).normalized()
	d.global_position = Vector3(cp.x, 0.0, cp.z) + behind * 1.2
	assert_true(_seg_dist(d.global_position, bp, cp) < STAND_RADIUS, "set-up: the stand blocks her line")
	_tick(b, 0.8)
	assert_eq(String(b.state), "channel", "still channelling (no free interrupt)")
	var np: Vector3 = b.global_position
	assert_almost(Vector2(np.x - cp.x, np.z - cp.z).length(), float(Boss.CHANNEL_OFFSET), 0.05, "still beside the candle")
	assert_true(_seg_dist(d.global_position, np, cp) > STAND_RADIUS + 0.2, "he eased round the stand: her line is clear")
	assert_true(bool(b.is_reachable()), "low and in reach")
	await wait_physics(2)
	var hits := _swing(d, b)
	assert_eq(hits.size(), 1, "her blow lands")
	assert_eq(String(b.state), "stagger")
	# Once her line is clear he holds still again.
	var n := _boss(d, cs)
	var c2 := _to_channel(n)
	_tick_until(n, "channel", 10.0)
	_tick(n, 0.2)
	var cp2: Vector3 = c2.global_position
	var bp2: Vector3 = n.global_position
	d.global_position = Vector3(cp2.x, 0.0, cp2.z) + Vector3(cp2.x - bp2.x, 0.0, cp2.z - bp2.z).normalized() * 1.2
	_tick(n, 0.8)
	var settled: Vector3 = n.global_position
	_tick(n, 0.8)
	assert_true(n.global_position.distance_to(settled) < 0.001, "stationary once the stand is out of her line")


# --- CH2-013: one window never takes more than WINDOW_CAP ---------------------------------------------------------

func test_ch2_013_a_stagger_window_never_exceeds_the_cap() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	_to_channel(b)
	_tick_until(b, "channel", 10.0)
	_tick(b, 0.3)
	b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD)
	assert_eq(String(b.state), "stagger", "the blow on the channel staggers him")
	_tick(b, 0.6)
	var cap: float = float(b.health.max_hp) * Boss.WINDOW_CAP
	var hp0: float = float(b.health.hp)
	var last := 0.0
	var n := 0
	while String(b.state) == "stagger" and n < 20:
		last = float(b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD))
		n += 1
	assert_ne(String(b.state), "stagger", "the window closes at the cap")
	assert_true(hp0 - float(b.health.hp) <= cap + 0.01, "at most WINDOW_CAP in one window (took %.1f of %.1f)" % [hp0 - float(b.health.hp), cap])
	assert_almost(hp0 - float(b.health.hp), cap, 0.02, "the window pays out the whole cap")
	assert_true(last > 0.0 and last < SWORD_DAMAGE * Boss.STAGGER_MULT, "the last blow is trimmed to fit")
	assert_false(bool(b.can_be_hit_by(d)), "he whirled back out of reach")


func test_ch2_013_a_finishing_blow_is_never_trimmed() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	_to_channel(b)
	_tick_until(b, "channel", 10.0)
	_tick(b, 0.3)
	b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD)
	assert_eq(String(b.state), "stagger")
	assert_almost(float(b.health.floor_hp), 0.0, 0.001, "the borrowed mask is lifted")
	_tick(b, 0.6)
	var cap: float = float(b.health.max_hp) * Boss.WINDOW_CAP
	b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD)
	b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD)   # 54 of the window's 60.8 spent
	assert_eq(String(b.state), "stagger")
	# He has less left than her next blow: it defeats him whole instead of leaving a sliver to chase.
	b.health.set_hp(20.0)
	var dealt: float = float(b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD))
	assert_true(cap - 54.0 < 20.0, "set-up: the window's room is smaller than what he has left")
	assert_almost(dealt, 20.0, 0.01, "the finishing blow lands whole")
	assert_true(bool(b.health.dead), "defeated")


func test_ch2_013_a_recoil_window_is_trimmed_to_the_cap() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, [])
	b.start_fight()
	d.health.grant_iframes(3.0)
	b.next_action = "dash"
	_tick_until(b, "recoil", 20.0)
	d.health.grant_iframes(0.0)
	_tick(b, 0.2)
	var cap: float = float(b.health.max_hp) * Boss.WINDOW_CAP
	var hp0: float = float(b.health.hp)
	var n := 0
	while String(b.state) == "recoil" and n < 20:
		b.health.apply_damage(SWORD_DAMAGE, d, Vector3.FORWARD)
		n += 1
	assert_eq(String(b.state), "glide", "he whirls back up")
	assert_true(hp0 - float(b.health.hp) <= cap + 0.01, "at most WINDOW_CAP (took %.1f of %.1f)" % [hp0 - float(b.health.hp), cap])
	# One heavy blow alone can never take more than the cap either.
	b.next_action = "dash"
	d.health.grant_iframes(3.0)
	_tick_until(b, "recoil", 20.0)
	d.health.grant_iframes(0.0)
	_tick(b, 0.2)
	var hp1: float = float(b.health.hp)
	var dealt: float = float(b.health.apply_damage(200.0, d, Vector3.FORWARD))
	assert_true(dealt <= cap + 0.01, "a single big blow is trimmed to the cap (dealt %.1f)" % dealt)
	assert_almost(hp1 - float(b.health.hp), dealt, 0.01)
	assert_eq(String(b.state), "glide")


func test_ch2_013_the_blow_that_breaks_a_drain_counts_toward_the_cap() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, [])
	var results: Array = []
	b.drain_resolved.connect(func(r: String) -> void: results.append(r))
	b.start_fight()
	b.next_action = "drain"
	_tick_until(b, "drain_tele", 20.0)
	_tick(b, 0.7)
	assert_true(bool(b.can_be_hit_by(d)))
	var cap: float = float(b.health.max_hp) * Boss.WINDOW_CAP
	var hp0: float = float(b.health.hp)
	var dealt: float = float(b.health.apply_damage(100.0, d, Vector3.FORWARD))
	assert_eq(results, ["hit"], "the blow breaks the drain")
	assert_true(dealt <= cap + 0.01, "trimmed to the cap (dealt %.1f)" % dealt)
	assert_almost(hp0 - float(b.health.hp), dealt, 0.01)
	assert_eq(String(b.state), "glide", "the window is spent: he whirls up instead of resting in reach")
	assert_false(bool(b.can_be_hit_by(d)))
