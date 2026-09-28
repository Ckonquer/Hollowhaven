extends "res://tests/test_case.gd"
## Count Velour phase A (module C6a, MP 13.1): the bow is a >= 1.0 s tell with his SHADOW stretched along the same
## lane the ground mark shows (tracks, then locks); the cape dash resolves on exactly that segment, hits at most
## once through the player's health path (dodge i-frames apply), never through a wall, and ends in a reachable
## RECOIL window at the far end (longer when the dash missed). Intense: a taught feint with a separate final tell.
## The drain tether: a visible link + ring during the warning, a channel meter, NO heal before the channel
## succeeds (then one hit through her health and a heal capped at the phase ceiling), and every break condition
## (line of sight, a lit candle pool, a hit, range) cancels it with no damage and no heal.
## Headless, manual ticks (boss process off), no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/count_velour.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)

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


var _saved_assist: Variant = false        # Settings "timing_assist" pinned off (exact timings below), restored after


func before_each() -> void:
	fresh_state()
	_saved_assist = Settings.get_value("timing_assist")
	Settings.set_value("timing_assist", false)
	_nodes.clear()


func after_each() -> void:
	Settings.set_value("timing_assist", _saved_assist)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await wait_frames(2)


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	w.add_child(cs)
	add_child(w)
	w.global_position = center
	_nodes.append(w)
	return w


func _candle(pos: Vector3, lit: bool = true) -> Node3D:
	var c: Node3D = WardCandle.new()
	c.setup({"id": "c%d" % _nodes.size(), "lit": lit, "pool_radius": 3.2})
	add_child(c)
	c.global_position = pos
	_nodes.append(c)
	return c


func _boss(target: Node3D, candles: Array = [], intensity: int = 1) -> Node3D:
	var b: Node3D = Factory.create("count_velour", {"arena_center": CENTER, "arena_radius": 12.0, "candles": candles, "seed": 5}, CENTER)
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


func _hp(d: Dummy) -> float:
	return float(d.health.hp)


# --- Bow -> dash -> recoil --------------------------------------------------------------------------------------

func test_bow_tell_shadow_lane_and_dash_hits_once_through_her_health() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.start_fight()
	b.next_action = "dash"
	_tick_until(b, "bow")
	assert_eq(String(b.state), "bow")
	var mark: Node3D = b.get("_lane_mark")
	var fx: Node3D = b.get("_fx")
	assert_eq(String(mark.get("kind")), "lane", "a ground lane marks the dash")
	assert_true(bool(fx.get("lane_visible")), "his shadow stretches along the lane")
	var bow_t := _tick_until(b, "dash")
	assert_true(bow_t >= 1.0 - 0.001, "the bow warns >= 1.0 s (%.2f)" % bow_t)
	var fp: Dictionary = mark.call("footprint")
	assert_true(bool(fp["locked"]), "the lane locked before the dash")
	var a: Vector3 = fp["from"]
	var e: Vector3 = fp["to"]
	var sa: Vector3 = fx.get("lane_from")
	var se: Vector3 = fx.get("lane_to")
	assert_true(Vector2(sa.x - a.x, sa.z - a.z).length() < 0.01 and Vector2(se.x - e.x, se.z - e.z).length() < 0.01, "shadow and mark show the same segment")
	assert_almost(float(fp["width"]), Boss.DASH_HALF_WIDTH * 2.0, 0.001, "marked width = hit width")
	assert_true(TelegraphFx.segment_hit(a, e, 0.2, d.global_position), "the lane runs through her")
	var hp0 := _hp(d)
	_tick_until(b, "recoil")
	assert_almost(hp0 - _hp(d), 16.0, 0.01, "one cape-dash hit (data 16, Standard)")
	assert_eq(int(b.dash_hits), 1)
	var end: Vector3 = b.global_position
	assert_true(Vector2(end.x - e.x, end.z - e.z).length() < 0.3, "he recoils at the far end of the marked lane")
	assert_false(bool(mark.call("is_showing")), "the mark is gone after the dash")
	# Recoil: reachable and hurtable, and shorter after a hit than after a miss.
	_tick(b, 0.2)
	assert_true(bool(b.is_reachable()) and bool(b.can_be_hit_by(d)), "the recoil is the attack window")
	var hit_len: float = float(b.get("_state_len"))
	assert_almost(hit_len, float(Boss.T_RECOIL_HIT[1]), 0.001)
	_tick(b, 3.0)
	assert_ne(String(b.state), "recoil", "the window closes on its own")
	assert_almost(hp0 - _hp(d), 16.0, 0.01, "never a second hit from one dash")


func test_sidestep_or_dodge_means_no_damage_and_a_long_window() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.start_fight()
	b.next_action = "dash"
	_tick_until(b, "bow")
	_tick(b, float(b.get("_state_len")) * 0.7)          # the lane has locked
	d.global_position += Vector3(2.5, 0, 0)            # sidestep out of the lane
	var hp0 := _hp(d)
	_tick_until(b, "recoil")
	assert_almost(_hp(d), hp0, 0.001, "a sidestep avoids the dash")
	assert_almost(float(b.get("_state_len")), float(Boss.T_RECOIL[1]), 0.001, "a missed dash leaves the full recoil window")
	# Dodge-roll i-frames: in the lane but invulnerable -> no damage, resolved once (never re-tested).
	var inward: Vector3 = CENTER - b.global_position
	inward.y = 0.0
	d.global_position = b.global_position + (inward.normalized() if inward.length() > 0.5 else Vector3(0, 0, 1)) * 5.0
	b.next_action = "dash"
	_tick_until(b, "bow")
	d.health.grant_iframes(5.0)
	var hp1 := _hp(d)
	_tick_until(b, "recoil")
	assert_almost(_hp(d), hp1, 0.001, "i-frames: the player's damage path refused the hit")
	assert_eq(int(b.dash_hits), 0)
	assert_eq(int(b.dashes), 2, "both dashes happened")
	assert_true(bool(b.get("_dash_resolved")), "she was in the lane: resolved once, never re-tested")


func test_the_dash_never_goes_through_walls() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.start_fight()
	b.next_action = "dash"
	_tick_until(b, "bow")
	var from: Vector3 = b.global_position
	var mid := (from + d.global_position) * 0.5
	var dir := Vector3(d.global_position.x - from.x, 0, d.global_position.z - from.z).normalized()
	var w := _wall(Vector3(mid.x, 1.5, mid.z), Vector3(6, 3, 0.4))
	w.look_at(w.global_position + dir, Vector3.UP)
	await wait_physics(2)
	_tick(b, 0.2)                                          # still tracking: the lane re-clips
	var fp: Dictionary = (b.get("_lane_mark") as Node3D).call("footprint")
	var lane_len := Vector2((fp["to"] as Vector3).x - (fp["from"] as Vector3).x, (fp["to"] as Vector3).z - (fp["from"] as Vector3).z).length()
	var wall_d := Vector2(mid.x - (fp["from"] as Vector3).x, mid.z - (fp["from"] as Vector3).z).length()
	assert_true(lane_len < wall_d, "the lane stops short of the wall (%.2f < %.2f)" % [lane_len, wall_d])
	var hp0 := _hp(d)
	_tick_until(b, "recoil")
	assert_almost(_hp(d), hp0, 0.001, "no damage through the wall")
	var at: Vector3 = b.global_position
	assert_true(Vector2(at.x - from.x, at.z - from.z).length() < wall_d, "he recoils on his side of the wall")


func test_intense_feint_then_a_separate_final_tell() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, [], 2)
	b.start_fight()
	b.next_action = "dash"
	b.force_feint = true
	var seen: Array = []
	b.state_changed.connect(func(s: String) -> void: seen.append(s))
	var hints: Array = []
	var on_hint := func(id: String, _t: String) -> void: hints.append(id)
	Events.hint.connect(on_hint)
	_tick_until(b, "dash", 20.0)
	Events.hint.disconnect(on_hint)
	var i_bow := seen.find("bow")
	var i_fl := seen.find("flourish")
	var i_fin := seen.find("final_tell")
	var i_dash := seen.find("dash")
	assert_true(i_bow >= 0 and i_bow < i_fl and i_fl < i_fin and i_fin < i_dash, "bow -> flourish -> final tell -> dash: %s" % str(seen))
	assert_eq(int(b.feints), 1)
	assert_true(hints.has("velour_feint"), "the feint is taught")
	# The final tell is its own full warning (>= 1.0 s) and re-aims the lane.
	var b2 := _boss(d, [], 2)
	b2.start_fight()
	b2.next_action = "dash"
	b2.force_feint = true
	_tick_until(b2, "final_tell", 20.0)
	assert_true(bool((b2.get("_lane_mark") as Node3D).call("is_showing")), "the lane is shown again for the real dash")
	var t := _tick_until(b2, "dash", 5.0)
	assert_true(t >= Boss.T_FINAL_TELL - 0.001, "final tell >= 1.0 s (%.2f)" % t)
	# Standard never feints.
	var b3 := _boss(d, [], 1)
	b3.start_fight()
	b3.next_action = "dash"
	b3.force_feint = true
	var seen3: Array = []
	b3.state_changed.connect(func(s: String) -> void: seen3.append(s))
	_tick_until(b3, "recoil", 20.0)
	assert_false(seen3.has("flourish"), "only Intense feints")


# --- Drain tether ----------------------------------------------------------------------------------------------

func _to_drain(b: Node3D) -> void:
	b.start_fight()
	b.next_action = "drain"
	_tick_until(b, "drain_tele", 20.0)


func test_drain_warns_channels_and_heals_only_when_it_succeeds() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	var results: Array = []
	b.drain_resolved.connect(func(r: String) -> void: results.append(r))
	b.health.set_hp(300.0)
	_to_drain(b)
	assert_eq(String(b.state), "drain_tele")
	var tether: Node3D = b.get("_tether")
	var ring: Node3D = b.get("_ring_mark")
	b.tick(DT)
	assert_true(bool(tether.call("is_showing")), "the connection is visible during the warning")
	assert_false(bool(tether.get("channeling")))
	assert_eq(String(ring.get("kind")), "ring", "a ring marks her")
	var tele_t := _tick_until(b, "drain", 5.0)
	assert_true(tele_t >= 1.0 - 0.001, "the drain warns >= 1.0 s")
	var hp_boss: float = float(b.health.hp)
	var hp_her := _hp(d)
	var last_k := 0.0
	var steps := 0
	while String(b.state) == "drain" and steps < 200:
		assert_almost(float(b.health.hp), hp_boss, 0.0001, "no heal before the channel succeeds")
		assert_almost(_hp(d), hp_her, 0.0001, "no damage before the channel succeeds")
		b.tick(DT)
		if String(b.state) == "drain":
			var k: float = float(tether.get("progress"))
			assert_true(k >= last_k, "the channel meter only grows")
			last_k = k
		steps += 1
	assert_true(last_k > 0.9, "the meter reached the end")
	assert_eq(results, ["complete"])
	assert_almost(hp_her - _hp(d), 8.0, 0.01, "one drain hit (data 8) through her health")
	assert_almost(float(b.health.hp) - hp_boss, 16.0, 0.01, "he heals by what was dealt x2")
	assert_eq(String(b.state), "drain_rest")
	assert_false(bool(tether.call("is_showing")), "the tether is gone")
	# The heal never lifts him above his phase's ceiling.
	var b2 := _boss(d)
	b2.health.set_hp(float(b2.health.max_hp) - 3.0)
	_to_drain(b2)
	_tick_until(b2, "drain_rest", 10.0)
	assert_almost(float(b2.health.hp), float(b2.health.max_hp), 0.001, "capped at max")


func test_drain_breaks_on_line_of_sight() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	var results: Array = []
	b.drain_resolved.connect(func(r: String) -> void: results.append(r))
	b.health.set_hp(300.0)
	_to_drain(b)
	_tick_until(b, "drain", 5.0)
	var hp_boss: float = float(b.health.hp)
	var hp_her := _hp(d)
	var mid: Vector3 = (b.get_aim_point() + d.global_position) * 0.5
	var dir: Vector3 = (d.global_position - b.global_position)
	dir.y = 0.0
	var w := _wall(Vector3(mid.x, 1.5, mid.z), Vector3(4, 3, 0.4))
	w.look_at(w.global_position + dir.normalized(), Vector3.UP)
	await wait_physics(2)
	_tick(b, 0.3)
	assert_eq(results, ["sight"], "cover cuts the tether")
	assert_eq(String(b.state), "drain_rest", "he is left dazed")
	assert_almost(float(b.health.hp), hp_boss, 0.0001, "no heal")
	assert_almost(_hp(d), hp_her, 0.0001, "no damage")
	assert_false(bool((b.get("_tether") as Node3D).call("is_showing")))


func test_drain_breaks_in_a_lit_candle_pool_but_not_an_unlit_one() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	var results: Array = []
	b.drain_resolved.connect(func(r: String) -> void: results.append(r))
	b.health.set_hp(300.0)
	_to_drain(b)
	_tick_until(b, "drain", 5.0)
	# Candles either side of the line between them; she steps next to each one on HIS side of it (the stand is
	# behind her, so the line of sight stays clear and only the pool decides).
	var bp: Vector3 = b.global_position
	var f := Vector3(d.global_position.x - bp.x, 0, d.global_position.z - bp.z).normalized()
	var r := Vector3(-f.z, 0, f.x)
	var cold := _candle(bp + f * 6.0 + r * 4.0, false)
	var lit := _candle(bp + f * 6.0 - r * 4.0, true)
	b.set("candles", [cold, lit])
	await wait_physics(2)
	var cp: Vector3 = cold.global_position
	d.global_position = cp + Vector3(bp.x - cp.x, 0, bp.z - cp.z).normalized() * 1.5
	_tick(b, 0.3)
	assert_eq(results, [], "an unlit candle gives no pool")
	var lp: Vector3 = lit.global_position
	d.global_position = lp + Vector3(bp.x - lp.x, 0, bp.z - lp.z).normalized() * 1.5
	_tick(b, 0.3)
	assert_eq(results, ["candle"], "a lit candle pool breaks the tether")
	assert_true(bool(b.call("in_candle_pool", d.global_position)))


func test_drain_breaks_on_a_hit_and_on_range() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	var results: Array = []
	b.drain_resolved.connect(func(r: String) -> void: results.append(r))
	b.health.set_hp(300.0)
	_to_drain(b)
	_tick(b, 0.7)                                         # he floats down into reach during the warning
	assert_true(bool(b.can_be_hit_by(d)), "strike him to break it")
	var before: float = float(b.health.hp)
	b.health.apply_damage(18.0, d, Vector3.FORWARD)
	assert_eq(results, ["hit"])
	assert_almost(float(b.health.hp), before - 18.0, 0.01, "and the blow lands")
	# Range.
	var b2 := _boss(d)
	var r2: Array = []
	b2.drain_resolved.connect(func(r: String) -> void: r2.append(r))
	_to_drain(b2)
	_tick_until(b2, "drain", 5.0)
	var away: Vector3 = d.global_position - b2.global_position
	away.y = 0.0
	d.global_position = b2.global_position + away.normalized() * 13.0
	_tick(b2, 0.3)
	assert_eq(r2, ["range"], "running out of range breaks it")


func test_gentle_tether_is_easier() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var lit := _candle(Vector3(5, 0, 3), true)
	var g := _boss(d, [lit], 0)
	g.start_fight()
	var pool: float = float(lit.get("pool_radius"))
	var edge := Vector3(5.0 - pool - 0.5, 0, 3)          # just outside the pool
	assert_false(bool(g.call("in_candle_pool", edge)), "outside the plain pool")
	assert_true(bool(g.call("in_candle_pool", edge, float(Boss.DRAIN_POOL_BONUS[0]))), "Gentle pools reach further")
	d.global_position = edge
	assert_eq(String(g.call("_drain_break_reason", d)), "candle", "Gentle: the wider pool breaks it")
	var n := _boss(d, [lit], 1)
	n.start_fight()
	assert_eq(String(n.call("_drain_break_reason", d)), "", "Standard: the plain pool")


# --- Review C6a: a hit that fells her ends the encounter inside the hit ---------------------------------------

## Game.on_player_died emits Events.player_died synchronously from inside her Health (died), i.e. INSIDE the
## boss's own _deal(): reset_fight() runs in the middle of the drain / dash. Nothing may resume afterwards (no
## heal, no drain rest, no glide or bow while the encounter is over).
func _fell_on_death(d: Dummy) -> Array:
	var falls: Array = [0]
	d.health.died.connect(func() -> void:
		falls[0] = int(falls[0]) + 1
		Events.player_died.emit())
	return falls


func test_a_drain_that_fells_her_resets_cleanly_and_nothing_resumes() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.auto_start = false                      # the arena restarts him, never proximity
	b.health.set_hp(300.0)
	var falls := _fell_on_death(d)
	_to_drain(b)
	_tick_until(b, "drain", 5.0)
	assert_eq(String(b.state), "drain")
	d.health.set_hp(5.0)                      # the drain (data 8) will fell her
	_tick_until(b, "dormant", 6.0)
	assert_eq(int(falls[0]), 1, "the completed drain felled her")
	assert_eq(String(b.state), "dormant", "a clean reset - not a drain rest after the encounter ended")
	assert_false(bool(b.fight_started))
	assert_false(b.is_in_group("enemy"))
	assert_almost(float(b.health.hp), 300.0, 0.001, "no heal from the drain that ended the encounter")
	d.health.reset()                          # she is back on her feet (checkpoint)
	var moved := false
	for i in 160:
		b.tick(DT)
		if String(b.state) != "dormant":
			moved = true
			break
	assert_false(moved, "nothing resumes until the arena restarts the encounter")


func test_a_dash_that_fells_her_at_the_lane_end_does_not_recoil_afterwards() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.auto_start = false
	var falls := _fell_on_death(d)
	d.health.set_hp(1.0)
	b.start_fight()
	b.next_action = "dash"
	_tick_until(b, "dash", 15.0)
	# She stands just past the end of the locked lane, so the blow and the end of the dash land in the SAME tick.
	var la: Vector3 = b.get("_lane_a")
	var lb: Vector3 = b.get("_lane_b")
	var dir: Vector3 = b.get("_lane_dir")
	d.global_position = lb + dir * (Boss.DASH_HALF_WIDTH + Boss.TARGET_BODY - 0.01)
	var lane_len := Vector2(lb.x - la.x, lb.z - la.z).length()
	assert_true(lane_len > 1.0, "a real lane (%.2f m)" % lane_len)
	b.tick((lane_len - 0.4) / float(Boss.DASH_SPEED[1]))
	assert_eq(int(falls[0]), 0, "not in reach yet")
	assert_eq(String(b.state), "dash")
	b.tick(0.2)                               # reaches the lane end - and her - in this one tick
	assert_eq(int(falls[0]), 1, "the dash felled her")
	assert_eq(String(b.state), "dormant")
	assert_false(bool(b.fight_started))
	b.tick(DT)
	assert_eq(String(b.state), "dormant", "no recoil / glide after the reset")
