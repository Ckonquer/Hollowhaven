extends "res://tests/test_case.gd"
## Count Velour phase C and the reset policy (module C6a, MP 13.1): he flies to a lit ward candle (a ring marks
## it), hovers still and low (in reach) and channels; the channel completes -> that candle goes dark (candle API
## darken) and he rests; a hit while he channels, or relighting a dark candle with the lantern, STAGGERS him
## (generous window, x1.5) and the candle he was snuffing stays lit; the candle choice (Gentle: nearest to her).
## Reset: Krystal falls / the area pauses -> every candle back to the start state, nothing left in flight (bats,
## tether, stream, marks, helper), bar hidden and encounter over, wounds and phase kept, a clean restart.
## Headless, manual ticks (boss process off), no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/count_velour.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const EnemyBase := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)

var _nodes: Array = []
var _events: Array = []


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
	_events.clear()
	EnemyBase.reset_attack_tokens()
	Events.boss_encounter_changed.connect(_on_encounter)
	Events.boss_health_changed.connect(_on_health)


func after_each() -> void:
	Settings.set_value("timing_assist", _saved_assist)
	Events.boss_encounter_changed.disconnect(_on_encounter)
	Events.boss_health_changed.disconnect(_on_health)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.get_parent() == self:
			e.queue_free()
	_nodes.clear()
	EnemyBase.reset_attack_tokens()
	await wait_frames(2)


func _on_encounter(id: String, active: bool) -> void:
	_events.append(["encounter", id, active])


func _on_health(id: String, hp: float, _m: float) -> void:
	_events.append(["health", id, hp])


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


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


func test_channel_is_stationary_marked_and_darkens_the_candle() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	var darkened: Array = []
	b.candle_darkened.connect(func(c: Node3D) -> void: darkened.append(c))
	var c := _to_channel(b)
	assert_not_null(c, "he picks a lit candle")
	assert_true(bool(c.call("is_lit")))
	assert_eq(String((b.get("_ring_mark") as Node3D).get("kind")), "ring", "a ring marks the candle he is going for")
	var fly := _tick_until(b, "channel", 10.0)
	assert_true(fly >= 1.0 - 0.001, "he announces it (>= 1.0 s)")
	var at: Vector3 = b.global_position
	var cp: Vector3 = c.global_position
	assert_true(Vector2(at.x - cp.x, at.z - cp.z).length() < 1.6, "he hovers beside the candle")
	_tick(b, 0.3)
	assert_true(bool(b.is_reachable()), "low and within reach while he channels")
	assert_true(bool(b.can_be_hit_by(d)), "his exposed form")
	assert_true(bool((b.get("_stream") as Node3D).call("is_showing")), "the flame's light visibly streams into him")
	var still: Vector3 = b.global_position
	_tick(b, 1.0)
	assert_true(b.global_position.distance_to(still) < 0.001, "stationary")
	_tick_until(b, "channel_rest", 10.0)
	assert_false(bool(c.call("is_lit")), "the channel completed: the candle is dark")
	assert_eq(darkened, [c])
	assert_eq(int(b.candles_darkened), 1)
	assert_false(bool((b.get("_stream") as Node3D).call("is_showing")))


func test_a_hit_while_channelling_staggers_and_keeps_the_candle_lit() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	var c := _to_channel(b)
	_tick_until(b, "channel", 10.0)
	_tick(b, 0.5)
	var hp0: float = float(b.health.hp)
	var dealt: float = float(b.health.apply_damage(18.0, d, Vector3.FORWARD))
	assert_almost(dealt, 18.0, 0.01)
	assert_eq(String(b.state), "stagger", "the blow staggers him")
	assert_eq(int(b.c_staggers), 1)
	assert_true(bool(c.call("is_lit")), "the candle he was snuffing stays lit")
	assert_false(bool((b.get("_stream") as Node3D).call("is_showing")))
	assert_almost(float(b.get("_state_len")), float(Boss.T_STAGGER[1]), 0.001, "a generous window")
	_tick(b, 0.5)
	assert_true(bool(b.can_be_hit_by(d)))
	var before: float = float(b.health.hp)
	b.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_almost(before - float(b.health.hp), 10.0 * Boss.STAGGER_MULT, 0.01, "x1.5 while staggered")
	assert_true(hp0 > float(b.health.hp))
	_tick(b, float(Boss.T_STAGGER[1]))
	assert_ne(String(b.state), "stagger", "the stagger ends on its own")


func test_relighting_a_dark_candle_staggers_him_anywhere() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	var c := _to_channel(b)
	_tick_until(b, "channel_rest", 12.0)
	assert_false(bool(c.call("is_lit")))
	_tick_until(b, "glide", 5.0)
	_tick(b, 0.6)
	assert_false(bool(b.is_reachable()), "hovering out of reach")
	c.call("light", d)                                # Krystal relights it with her lantern
	assert_eq(String(b.state), "stagger", "light staggers him")
	assert_eq(int(b.light_staggers), 1)
	_tick(b, 1.0)
	assert_true(bool(b.is_reachable()), "he sinks into reach")
	assert_true(bool(b.can_be_hit_by(d)))
	# A relight during the stagger does not chain another one.
	c.call("darken", null)
	c.call("light", d)
	assert_eq(int(b.light_staggers), 1, "no chained staggers")


func test_candle_choice_gentle_nearest_standard_far_but_reachable() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(-6, 0, 3))                 # right by the south-west candle
	var g := _boss(d, cs, 0)
	var n := _boss(d, cs, 1)
	assert_eq(String((g.call("_pick_channel_candle", d) as Node).get("candle_id")), "southwest", "Gentle: the one nearest her")
	var pick: Node3D = n.call("_pick_channel_candle", d)
	assert_ne(String(pick.get("candle_id")), "southwest", "Standard: makes her move")
	assert_true(Vector2(pick.global_position.x - d.global_position.x, pick.global_position.z - d.global_position.z).length() <= Boss.CHANNEL_MAX_DIST)
	for c in cs:
		c.call("restore", false)
	assert_null(n.call("_pick_channel_candle", d), "no lit candle, no channel")
	n.start_fight()
	_tick_until(n, "glide")
	n.jump_to_phase(3)
	n.next_action = "channel"
	var seen: Array = []
	n.state_changed.connect(func(s: String) -> void: seen.append(s))
	_tick_until(n, "recoil", 20.0)
	assert_false(seen.has("channel_fly"), "with every candle dark he dashes instead")


func test_reset_policy_restores_the_start_state_and_clears_everything() -> void:
	var cs := _candles()
	var teach: Node3D = cs[1]
	teach.call("restore", false)                       # like the arena: the teaching candle starts dark...
	teach.call("light", null)                          # ...and Krystal lights it before he appears
	var d := _dummy(Vector3(0, 0, 4))
	var b := _boss(d, cs)
	b.start_fight()
	_tick_until(b, "glide")
	b.jump_to_phase(2)
	b.next_action = "disperse"
	_tick_until(b, "bats", 20.0)
	assert_not_null(b.call("helper_node"), "a helper joined")
	var helper: Node = b.call("helper_node")
	var hp_before: float = float(b.health.hp)
	# Mid-dispersal: she falls.
	_events.clear()
	Events.player_died.emit()
	assert_eq(String(b.state), "dormant", "he waits")
	assert_false(bool(b.fight_started))
	assert_false(bool((b.get("_swarm") as Node3D).call("is_active")), "no bats left in flight")
	assert_true(not is_instance_valid(helper) or helper.is_queued_for_deletion(), "the helper is gone")
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "encounter" and not bool(e[2])), "encounter over (music, saving)")
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "health" and float(e[2]) < 0.0), "boss bar hidden")
	assert_almost(float(b.health.hp), hp_before, 0.001, "his wounds are kept while the manor stays loaded")
	assert_eq(int(b.phase), 2, "and the phase")
	assert_true(bool(b.visual.visible), "he is himself again")
	# Phase C: a candle darkened and a channel in progress, then a reset -> the start state (all lit).
	b.start_fight()
	_tick_until(b, "glide", 5.0)
	b.jump_to_phase(3)
	b.next_action = "channel"
	_tick_until(b, "channel_rest", 15.0)
	var dark := 0
	for c in cs:
		if not bool(c.call("is_lit")):
			dark += 1
	assert_eq(dark, 1, "one candle snuffed")
	b.next_action = "channel"
	_tick_until(b, "channel", 15.0)
	b.reset_fight()
	for c in cs:
		assert_true(bool(c.call("is_lit")), "every candle back to the start state (%s)" % String(c.get("candle_id")))
	assert_false(bool((b.get("_stream") as Node3D).call("is_showing")), "no channel stream")
	assert_false(bool((b.get("_ring_mark") as Node3D).call("is_showing")), "no marks")
	assert_false(bool((b.get("_lane_mark") as Node3D).call("is_showing")))
	assert_false(bool((b.get("_tether") as Node3D).call("is_showing")))
	assert_eq(int(b.phase), 3)
	# The next start is clean and reads the candles again.
	b.start_fight()
	assert_true(bool(b.fight_started))
	assert_eq(String(b.state), "intro")
	assert_eq(int(b.resets), 2)


# --- Review C6a: the borrowed mask never swallows the channel interrupt -------------------------------------

func test_a_blow_at_the_mask_floor_still_interrupts_the_channel() -> void:
	var cs := _candles()
	var d := _dummy(Vector3(0, 0, 1))
	var b := _boss(d, cs)
	var c := _to_channel(b)
	_tick_until(b, "channel", 10.0)
	_tick(b, 0.5)
	# Strong gear already brought him down to the borrowed mask: no room is left above the floor.
	b.health.set_hp(float(b.health.floor_hp))
	assert_true(float(b.health.floor_hp) > 0.0 and int(b.c_staggers) == 0)
	# A companion outside the arena is refused (never counts, never staggers).
	var outsider := Node3D.new()
	outsider.add_to_group("companion")
	add_child(outsider)
	_nodes.append(outsider)
	outsider.global_position = Vector3(40, 0, 0)
	b.on_hit_blocked(outsider, Vector3.FORWARD)
	assert_eq(String(b.state), "channel", "a refused hit changes nothing")
	# Krystal's real swing (Combat.melee): the floor swallows the damage (0 = "blocked") - the channel still breaks.
	var bp: Vector3 = b.global_position
	var away := Vector3(bp.x - c.global_position.x, 0.0, bp.z - c.global_position.z).normalized()
	d.global_position = bp + away * 1.3
	var origin := d.global_position + Vector3.UP * 0.9
	var hits: Array = Combat.melee(d, origin, -away, 2.5, 120.0, 34.0, ["enemy"], 5.0)
	assert_eq(hits.size(), 0, "no damage at the mask floor")
	assert_eq(String(b.state), "stagger", "the blow on his exposed form staggers him all the same")
	assert_eq(int(b.c_staggers), 1)
	assert_true(bool(c.call("is_lit")), "the candle he was snuffing stays lit")
	assert_almost(float(b.health.floor_hp), 0.0, 0.001, "the candle rule was used: the mask floor is gone")
	_tick(b, 1.0)
	var before: float = float(b.health.hp)
	b.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_almost(before - float(b.health.hp), 10.0 * Boss.STAGGER_MULT, 0.01, "and the window pays out")
