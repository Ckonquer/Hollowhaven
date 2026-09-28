extends "res://tests/test_case.gd"
## Weaver Matron / Hollow Mother rules: armour except while stunned, telegraphed drop (hit ->
## rebound, miss -> stuck), braziers scorch it down and burn anchors, stun-window cap, defeat ->
## flag + boss events + exactly one Heartseed (also after a reload), player-death reset, Gentle.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const ANCHORS := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]

var _nodes: Array = []
var _bar: Array = []
var _defeats: Array = []


class Dummy extends CharacterBody3D:
	var health: Node
	var knocks: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		knocks += 1


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	_bar.clear()
	_defeats.clear()
	Settings.set_value("arachnophobia", false)
	Events.boss_health_changed.connect(_on_bar)
	Events.boss_defeated.connect(_on_defeat)


func after_each() -> void:
	Events.boss_health_changed.disconnect(_on_bar)
	Events.boss_defeated.disconnect(_on_defeat)
	Settings.set_value("arachnophobia", false)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	for c in get_children():
		if c.name.begins_with("BurnedAnchor") or c.name.begins_with("Heartseed"):
			c.queue_free()
	_nodes.clear()
	await wait_frames(2)


func _on_bar(id: String, hp: float, mx: float) -> void:
	_bar.append([id, hp, mx])


func _on_defeat(id: String) -> void:
	_defeats.append(id)


func _dummy(pos: Vector3) -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _braziers() -> Array:
	var out: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "b%d" % i})
		add_child(b)
		var a: Vector3 = ANCHORS[i]
		b.global_position = Vector3(a.x * 0.8, 0.0, a.z * 0.8)
		out.append(b)
		_nodes.append(b)
	return out


func _boss(target: Node3D, brs: Array, intensity: int = 1) -> Node:
	var b: Node = Factory.create("weaver_matron", {"arena_center": CENTER, "anchors": ANCHORS, "braziers": brs})
	add_child(b)
	b.set_process(false)
	b.target_override = target
	b.intensity_override = intensity
	b.fast_defeat = true
	_nodes.append(b)
	return b


func _tick_until(b: Node, s: String, max_t: float = 15.0) -> float:
	var t := 0.0
	while b.state != s and t < max_t:
		b.tick(DT)
		t += DT
	return t


func test_dormant_until_engaged_and_armoured() -> void:
	var d := _dummy(Vector3(0, 0, 40))
	var b := _boss(d, _braziers())
	for i in 20:
		b.tick(DT)
	assert_eq(b.state, "dormant", "waits until Krystal enters the chamber")
	assert_almost(float(b.health.apply_damage(50.0)), 0.0, 0.001, "armoured while clinging")
	d.global_position = Vector3(0, 0, 8)
	_tick_until(b, "intro", 1.0)
	assert_eq(b.state, "intro")
	assert_true(b.fight_started)
	assert_true(_bar.size() > 0 and _bar[0][0] == "weaver_matron" and float(_bar[0][1]) == 240.0, "boss bar shown at 240")
	assert_true(b.is_threatening())


func test_drop_miss_gets_stuck_and_vulnerable() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "telegraph", 12.0)
	assert_eq(b.state, "telegraph", "telegraphs a drop")
	var target: Vector3 = b.get("_drop_target")
	assert_true(Vector2(target.x - 0.0, target.z - 3.0).length() < 0.1, "shadow circle under Krystal's spot")
	var tele := _tick_until(b, "drop", 3.0)
	assert_almost(tele, 1.2, DT + 0.001, "1.2 s rattle before the drop")
	d.global_position = Vector3(5, 0, 3)          # sidestep out of the circle
	_tick_until(b, "stuck", 2.0)
	assert_eq(b.state, "stuck", "missed slam -> stuck")
	assert_almost(float(d.health.hp), 100.0, 0.001, "dodged")
	assert_true(b.is_vulnerable())
	assert_almost(float(b.health.apply_damage(18.0)), 18.0, 0.001, "damageable while stuck")
	var stuck := _tick_until(b, "climb", 5.0)
	assert_almost(stuck, 2.5, DT + 0.001, "2.5 s opening")
	assert_almost(float(b.health.apply_damage(18.0)), 0.0, 0.001, "armoured again while climbing")


func test_drop_hit_rebounds_without_opening() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "drop", 15.0)
	_tick_until(b, "rebound", 2.0)
	assert_eq(b.state, "rebound", "a hit means no opening")
	assert_almost(float(d.health.hp), 80.0, 0.001, "slam deals data damage (20) at Standard")
	assert_eq(d.knocks, 1)
	assert_false(b.is_vulnerable())


func test_brazier_scorches_and_burns_nearest_anchor() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	(brs[1] as Node).call("light")
	assert_eq(b.state, "scorch_fall", "shrieks and falls when a brazier is lit")
	assert_eq((b.anchors as Array).size(), 2, "one anchor burned")
	assert_false((b.anchors as Array).has(ANCHORS[1]), "the anchor nearest to that brazier")
	assert_true((brs[1] as Node).is_in_group("light_source"), "lit brazier is a light source")
	_tick_until(b, "scorched", 2.0)
	assert_eq(b.state, "scorched")
	assert_almost(float(b.health.apply_damage(10.0)), 15.0, 0.001, "scorched: x1.5 damage")
	var t := _tick_until(b, "climb", 10.0)
	assert_almost(t, 5.0, 0.12, "5 s big window")


func test_window_cap_ends_stun_early() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	for i in 3:
		b.health.apply_damage(20.0)       # 30 each while scorched
	assert_eq(b.state, "scorched", "still down after 90")
	b.health.apply_damage(20.0)           # 120 >= 40% of 240
	assert_eq(b.state, "climb", "scrambles back up after 40% in one window")
	assert_almost(float(b.health.hp), 120.0, 0.001)


func test_hits_glance_off_through_combat_melee() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "drop", 15.0)
	_tick_until(b, "rebound", 2.0)
	var attacker := _dummy(Vector3(0, 0, 0))
	var aim: Vector3 = b.get_aim_point()
	var hits: Array = Combat.melee(attacker, aim + Vector3(0, 0, 1.5), Vector3(0, 0, -1), 2.5, 120.0, 18.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 0, "hits glance off unless stunned")
	assert_almost(float(b.health.hp), 240.0, 0.001)


func test_defeat_sets_flag_and_spawns_one_heartseed() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	(brs[2] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.set_hp(5.0)
	b.health.apply_damage(10.0)
	await wait_frames(2)
	assert_eq(b.state, "gone", "retreated into the crack")
	assert_true(bool(GameState.get_flag("weaver_defeated")), "flag set")
	assert_eq(_defeats, ["weaver_matron"], "Events.boss_defeated once")
	assert_true(_bar.size() > 0 and float(_bar[_bar.size() - 1][1]) < 0.0, "boss bar hidden (-1)")
	assert_false(b.is_in_group("enemy"))
	assert_eq(get_tree().get_nodes_in_group("heartseed_pickup").size(), 1, "one Heartseed")
	Boss.ensure_heartseed(self, CENTER)
	await wait_frames(1)
	assert_eq(get_tree().get_nodes_in_group("heartseed_pickup").size(), 1, "never duplicated")


func test_heartseed_after_reload_rules() -> void:
	GameState.set_flag("weaver_defeated", true)
	assert_true(Boss.should_spawn_heartseed(), "beaten, seed not taken -> must exist")
	var b := _boss(_dummy(Vector3.ZERO), _braziers())
	await wait_frames(2)
	assert_eq(b.state, "gone", "no second fight after reload")
	assert_false(b.is_in_group("enemy"))
	var seeds := get_tree().get_nodes_in_group("heartseed_pickup")
	assert_eq(seeds.size(), 1, "pickup restored on load")
	var b2 := _boss(_dummy(Vector3.ZERO), [])
	await wait_frames(2)
	assert_eq(get_tree().get_nodes_in_group("heartseed_pickup").size(), 1, "a second load does not duplicate it")
	# Take it
	(seeds[0] as Node).interact(null)
	assert_true(GameState.has_item("heartseed"), "Heartseed goes to the key pouch")
	await wait_frames(2)
	assert_false(Boss.should_spawn_heartseed(), "not again while carried")
	GameState.take_item("heartseed", 1)
	GameState.set_flag("ward_restored", true)
	assert_false(Boss.should_spawn_heartseed(), "not after it was returned")
	var _unused := b2


func test_player_death_resets_fight_cleanly() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.apply_damage(20.0)
	var hp: float = b.health.hp
	_bar.clear()
	Events.player_died.emit()
	assert_eq(b.state, "dormant", "back up and waiting")
	assert_false(b.fight_started)
	assert_true(_bar.size() > 0 and float(_bar[_bar.size() - 1][1]) < 0.0, "bar hidden")
	assert_true((b as Node3D).global_position.y > 5.0, "on the ceiling again")
	assert_eq((b.anchors as Array).size(), 2, "burned anchors stay burned (kinder retry)")
	assert_true((brs[0] as Node).is_lit(), "lit braziers stay lit")
	assert_almost(float(b.health.hp), hp, 0.001, "wounds kept")
	assert_false(b.is_vulnerable())


func test_gentle_is_slower_softer_and_longer_stuns() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers(), 0)
	_tick_until(b, "telegraph", 15.0)
	var tele := _tick_until(b, "drop", 3.0)
	assert_almost(tele, 1.6, DT + 0.001, "longer rattle")
	_tick_until(b, "rebound", 2.0)
	assert_almost(float(d.health.hp), 100.0 - 20.0 * 0.6, 0.01, "Gentle slam damage")
	assert_almost(float(Boss.T_STUCK[0]), 3.5, 0.001)
	assert_almost(float(Boss.T_SCORCHED[0]), 7.0, 0.001)


func test_brazier_needs_lantern_and_kindles() -> void:
	var brs := _braziers()
	var br: Node = brs[0]
	var info: Dictionary = br.get_interaction(null)
	assert_false(bool(info["enabled"]), "needs a lantern")
	GameState.give_item("lantern", 1)
	info = br.get_interaction(null)
	assert_true(bool(info["enabled"]))
	assert_eq(info["text"], "Light the brazier")
	var lit := [false]
	br.lit.connect(func() -> void: lit[0] = true)
	br.interact(null)
	assert_false(br.is_lit(), "kindling takes a moment")
	for i in 20:
		br._process(0.05)
	assert_false(br.is_lit())
	for i in 12:
		br._process(0.05)
	assert_true(br.is_lit(), "lit after ~1.5 s")
	assert_true(lit[0], "lit signal")
	assert_true(br.is_light_active())
	assert_almost(float(br.light_radius), 7.0, 0.001)


## Krystal goes down mid-kindle: the kindle fizzles (like walking away) instead of finishing on the
## death screen, whether the game's death flow runs or only her health hits zero.
func test_kindling_fizzles_when_krystal_goes_down() -> void:
	GameState.give_item("lantern", 1)
	var brs := _braziers()
	var br: Node = brs[0]
	br.set_process(false)
	var d := _dummy((br as Node3D).global_position + Vector3(0, 0, 1.4))
	br.interact(d)
	br._process(0.5)
	assert_true(float(br.kindle_progress) > 0.2, "kindling")
	Events.player_died.emit()
	assert_almost(float(br.kindle_progress), 0.0, 0.001, "her death snuffs the spark")
	for i in 40:
		br._process(0.05)
	assert_false(br.is_lit(), "the kindle does not finish during the death screen")
	assert_true(bool(br.get_interaction(d)["enabled"]), "and can be started again")
	br.interact(d)
	br._process(0.3)
	d.health.apply_damage(999.0)                     # down without the death flow (e.g. mid-cutscene)
	for i in 40:
		br._process(0.05)
	assert_false(br.is_lit(), "a fallen kindler cannot finish it either")
	var d2 := _dummy((br as Node3D).global_position + Vector3(0, 0, -1.4))
	br.interact(d2)
	for i in 32:
		br._process(0.05)
	assert_true(br.is_lit(), "control: a kindle by someone still standing completes")


## A brazier that lights while Krystal is down (a kindle that slipped through, a scripted or debug
## light) burns its anchor, but must not restart the fight: no scorch fall, bar or music while she
## is on the death screen. It no longer hangs from the burned anchor either.
func test_brazier_lit_while_krystal_is_down_keeps_the_boss_dormant() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	assert_true(b.fight_started, "fight on")
	var clung: Vector3 = b.get("_anchor")
	d.health.apply_damage(999.0)
	Events.player_died.emit()
	assert_eq(b.state, "dormant", "death reset")
	assert_true((b.get("_anchor") as Vector3).distance_to(clung) < 0.01, "back on the anchor it clung to")
	_bar.clear()
	(brs[0] as Node).call("light")                   # the brazier right below that anchor
	assert_eq(b.state, "dormant", "no scorch fall while she is down")
	assert_false(b.fight_started, "the fight stays reset")
	assert_false(b.is_threatening())
	assert_eq(_bar.size(), 0, "no boss bar re-shown")
	assert_eq((b.anchors as Array).size(), 2, "the anchor still burns (kinder retry)")
	assert_false((b.burned as Array).has(b.get("_anchor")), "it moved off the burned anchor")
	assert_true((b as Node3D).global_position.y > 5.0, "still up on the ceiling")
	for i in 40:
		b.tick(DT)
	assert_eq(b.state, "dormant", "and waits while she is down")


func test_arachnophobia_swap_keeps_fight_state() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	assert_true(b.visual.get_script() == preload("res://src/enemies/weaver_visual.gd"), "the Weaver Matron by default")
	_tick_until(b, "telegraph", 12.0)
	b.tick(0.5)
	var t: float = b.state_time
	Settings.set_value("arachnophobia", true)
	await wait_frames(1)
	assert_true(b.visual.get_script() == preload("res://src/enemies/shade_visual.gd"), "the Hollow Mother when arachnophobia is on")
	assert_eq(b.state, "telegraph", "same fight state")
	assert_almost(float(b.state_time), t, 0.001, "timers untouched by the swap")
	assert_true((b as Node3D).global_position.y < 8.0 - 3.0, "re-seated with the Shade's hanging offset")
	Settings.set_value("arachnophobia", false)
	await wait_frames(1)
	assert_true(b.visual.get_script() == preload("res://src/enemies/weaver_visual.gd"), "and back")
	assert_true((b as Node3D).global_position.y > 7.5, "the Weaver clings right at the anchor")


func test_drops_stay_inside_the_arena() -> void:
	var d := _dummy(Vector3(0, 0, 13.5))           # on the entrance ramp: engaged, but outside the floor
	var b: Node = Factory.create("weaver_matron", {"arena_center": CENTER, "anchors": ANCHORS, "braziers": [], "arena_radius": 11.0})
	add_child(b)
	b.set_process(false)
	b.target_override = d
	b.intensity_override = 1
	_nodes.append(b)
	_tick_until(b, "cling", 5.0)
	assert_true(b.fight_started, "the fight starts as Krystal walks in")
	for i in 120:
		b.tick(DT)
	assert_eq(b.state, "cling", "no drops while she is still outside the arena floor")
	d.global_position = Vector3(0, 0, 11.2)       # just inside the edge
	_tick_until(b, "telegraph", 8.0)
	var target: Vector3 = b.get("_drop_target")
	assert_true(Vector2(target.x, target.z).length() <= 9.51, "the drop circle is clamped inside the floor (%.2f)" % Vector2(target.x, target.z).length())


func test_stands_down_when_krystal_leaves() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "cling", 6.0)
	assert_true(b.fight_started)
	d.global_position = Vector3(0, 0, 40)          # back up the ramp to the checkpoint
	_bar.clear()
	_tick_until(b, "dormant", 8.0)
	assert_eq(b.state, "dormant", "stands down after a few seconds")
	assert_false(b.fight_started)
	assert_true(_bar.size() > 0 and float(_bar[_bar.size() - 1][1]) < 0.0, "boss bar hidden")
	d.global_position = Vector3(0, 0, 5)
	_tick_until(b, "intro", 2.0)
	assert_eq(b.state, "intro", "and wakes again when she returns")
