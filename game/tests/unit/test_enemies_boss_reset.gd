extends "res://tests/test_case.gd"
## The Matron's ONE reset policy (weaver_boss.gd header, MP section 8 "Failure, replay, comfort"):
## Krystal falling or walking out resets the ACTIVE encounter cleanly (dormant on a remaining anchor,
## bar hidden, boss_encounter_changed(false), every fan / trip-line / sac / thread gone, minions
## scattered, channel cancelled) while wounds, the phase reached, burned anchors and lit braziers stay -
## braziers and phases are never mismatched (phase-3 braziers stay reusable; a smothered one relights
## after its cooldown). A reload is a fresh encounter. Completed saves never see the story boss again
## and nothing here ever writes or clears "weaver_defeated"; a trial-mode Matron runs on a completed
## save, pays no Heartseed, sets no flag and emits no boss_defeated.
## Headless, manual ticks, no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const ANCHORS := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]

var _nodes: Array = []
var _bar: Array = []
var _encounter: Array = []
var _defeats: Array = []


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 5000.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	_bar.clear()
	_encounter.clear()
	_defeats.clear()
	Settings.set_value("arachnophobia", false)
	Settings.set_value("timing_assist", false)
	Events.boss_health_changed.connect(_on_bar)
	Events.boss_encounter_changed.connect(_on_encounter)
	Events.boss_defeated.connect(_on_defeat)


func after_each() -> void:
	Events.boss_health_changed.disconnect(_on_bar)
	Events.boss_encounter_changed.disconnect(_on_encounter)
	Events.boss_defeated.disconnect(_on_defeat)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	for c in get_children():
		if c.name.begins_with("BurnedAnchor"):
			c.queue_free()
	_nodes.clear()
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _on_bar(id: String, hp: float, mx: float) -> void:
	_bar.append([id, hp, mx])


func _on_encounter(id: String, active: bool) -> void:
	_encounter.append([id, active])


func _on_defeat(id: String) -> void:
	_defeats.append(id)


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _braziers() -> Array:
	var out: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "rb%d" % i})
		add_child(b)
		var a: Vector3 = ANCHORS[i]
		b.global_position = Vector3(a.x * 0.8, 0.0, a.z * 0.8)
		b.set_process(false)
		out.append(b)
		_nodes.append(b)
	return out


func _boss(target: Node3D, brs: Array, extra: Dictionary = {}) -> Node:
	var p := {"arena_center": CENTER, "anchors": ANCHORS, "braziers": brs}
	p.merge(extra, true)
	var b: Node = Factory.create("weaver_matron", p)
	add_child(b)
	b.set_process(false)
	b.target_override = target
	b.intensity_override = 1
	b.fast_defeat = true
	_nodes.append(b)
	return b


func _tick_until(b: Node, s: String, max_t: float = 15.0) -> float:
	var t := 0.0
	while b.state != s and t < max_t:
		b.tick(DT)
		t += DT
	return t


func _flags() -> Dictionary:
	return GameState.flags.duplicate(true)


## A busy phase-2 moment: a fan, trip-lines, shaking sacs and one live minion on the floor.
func _busy_phase_two(b: Node, d: Node3D, spawned: Array) -> void:
	b.field.minion_override = func(pos: Vector3, _params: Dictionary) -> Node:
		var n := Node3D.new()
		add_child(n)
		n.global_position = pos
		_nodes.append(n)
		spawned.append(n)
		return n
	_tick_until(b, "cling", 6.0)
	b.health.set_hp(120.0)
	b.call("_set_phase", 2)
	b.field.minion_cap = 2
	b.field.begin_fan(Vector3.ZERO, d.global_position, 0.0)
	b.field.begin_trips(1, 0.0, d.global_position)
	b.field.begin_sacs(1, 3.0, d.global_position)
	b.field.spawn_minion(Vector3(8, 0, 0))
	b.set("_release_done", true)
	b.call("_enter_cling", 0.05)


func test_death_resets_the_active_encounter_and_keeps_progress() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	(brs[0] as Node).call("light")         # lit before the fight (as after an earlier attempt)
	var b := _boss(d, brs)
	var spawned: Array = []
	assert_eq((b.anchors as Array).size(), 2, "its anchor is already burned")
	_busy_phase_two(b, d, spawned)
	assert_true(int(b.field.live_count()) >= 2 and bool(b.field.sacs_pending()) and int(b.field.alive_minions()) == 1, "precondition: a busy floor")
	var anchors: int = (b.anchors as Array).size()
	_encounter.clear()
	_bar.clear()
	Events.player_died.emit()
	assert_eq(b.state, "dormant", "back up and waiting")
	assert_false(bool(b.fight_started))
	assert_eq(_encounter, [["weaver_matron", false]], "encounter ended (music, saving)")
	assert_true(_bar.size() > 0 and float(_bar.back()[1]) < 0.0, "bar hidden")
	assert_true(bool(b.field.is_clear()), "no fan, line, sac or thread left")
	assert_eq((b.field.hazards as Array).size(), 0, "freed at once")
	assert_true(GameState.buffs.get("slow") == null, "no lingering slow")
	await wait_frames(1)
	assert_eq(int(b.field.alive_minions()), 0, "minions scattered")
	assert_eq(int(b.phase), 2, "the phase reached is kept")
	assert_almost(float(b.health.hp), 120.0, 0.001, "wounds kept")
	assert_eq((b.anchors as Array).size(), anchors, "burned anchors stay burned")
	assert_true(bool((brs[0] as Node).is_lit()), "lit braziers stay lit")
	assert_false(bool(b.get("_release_done")), "the retry gets its release again (a fresh encounter state)")
	# The retry resumes phase 2 cleanly from the top of its rotation.
	_tick_until(b, "intro", 2.0)
	assert_eq(b.state, "intro", "wakes when she walks back in")
	_tick_until(b, "fan_tele", 8.0)
	assert_eq(b.state, "fan_tele", "phase 2 rotation restarts with the fan")


func test_walking_out_is_the_same_clean_reset() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	var spawned: Array = []
	_busy_phase_two(b, d, spawned)
	_tick_until(b, "cling", 4.0)
	d.global_position = Vector3(0, 0, 40)
	_tick_until(b, "dormant", 8.0)
	assert_eq(b.state, "dormant", "stood down")
	assert_true(bool(b.field.is_clear()), "the floor is clear")
	await wait_frames(1)
	assert_eq(int(b.field.alive_minions()), 0)
	assert_eq(int(b.phase), 2)


func test_death_mid_channel_never_leaves_a_mismatched_brazier() -> void:
	GameState.give_item("lantern", 1)
	var d := _dummy(Vector3(5, 0, 5))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	b.health.set_hp(60.0)
	b.call("_set_phase", 3)
	(brs[1] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.call("_begin_climb")
	_tick_until(b, "cling", 3.0)
	b.set("_channel_cd", 0.0)
	b.call("_enter_cling", 0.05)
	_tick_until(b, "channel", 3.0)
	assert_eq(b.state, "channel")
	for i in 30:
		b.tick(DT)
	assert_true(float((brs[1] as Node).dim_amount()) > 0.2)
	Events.player_died.emit()
	assert_eq(b.state, "dormant")
	assert_null(b.field.thread, "thread gone")
	assert_true(bool((brs[1] as Node).is_lit()), "the brazier is still lit")
	assert_almost(float((brs[1] as Node).dim_amount()), 0.0, 0.001, "and burns fully")
	assert_true(bool((brs[1] as Node).reusable), "phase 3 braziers stay reusable after the reset")
	assert_eq(int(b.phase), 3)


func test_reload_is_a_fresh_encounter() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "cling", 6.0)
	b.health.set_hp(60.0)
	b.call("_set_phase", 3)
	b.queue_free()
	await wait_frames(1)
	var b2 := _boss(d, _braziers())
	assert_eq(int(b2.phase), 1, "phase 1 again")
	assert_almost(float(b2.health.hp), 240.0, 0.001, "full health")
	assert_eq((b2.anchors as Array).size(), 3, "every anchor")
	for br in b2.braziers:
		assert_false(bool(br.is_lit()), "cold braziers")


func test_completed_save_never_respawns_the_story_boss_and_flags_stay() -> void:
	GameState.set_flag("weaver_defeated", true)
	GameState.set_flag("ward_restored", true)
	var before := _flags()
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	for i in 60:
		b.tick(DT)
	assert_eq(b.state, "gone", "the story boss stays gone")
	assert_false(b.is_in_group("enemy"))
	assert_false(bool(b.fight_started))
	assert_null(b.field, "no hazards are even built")
	Events.player_died.emit()
	b.reset_fight()
	assert_eq(_flags(), before, "no flag touched")
	assert_eq(get_tree().get_nodes_in_group("heartseed_pickup").size(), 0, "no Heartseed after it was returned")


func test_story_defeat_sets_the_flag_once_and_trial_defeat_never_does() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.set_hp(5.0)
	b.health.apply_damage(10.0)
	await wait_frames(2)
	assert_eq(b.state, "gone")
	assert_true(bool(GameState.get_flag("weaver_defeated")), "story: flag set")
	assert_eq(_defeats, ["weaver_matron"], "story: boss_defeated once")
	assert_true(_encounter.has(["weaver_matron", false]), "encounter closed")
	# A trial Matron on this (now completed) save.
	var before := _flags()
	_defeats.clear()
	_encounter.clear()
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	await wait_frames(1)
	var brs2 := _braziers()
	var t := _boss(d, brs2, {"mode": "trial"})
	assert_ne(t.state, "gone", "the trial Matron runs on a completed save")
	assert_true(t.is_in_group("enemy"))
	var defeated := [false]
	t.defeated.connect(func() -> void: defeated[0] = true)
	_tick_until(t, "cling", 6.0)
	assert_true(bool(t.fight_started))
	(brs2[0] as Node).call("light")
	_tick_until(t, "scorched", 2.0)
	t.health.set_hp(5.0)
	t.health.apply_damage(10.0)
	await wait_frames(2)
	assert_eq(t.state, "gone")
	assert_true(defeated[0], "the trial hears `defeated`")
	assert_eq(_defeats, [], "no Events.boss_defeated from a trial")
	assert_true(_encounter.has(["weaver_matron", false]), "its encounter still closes (music)")
	assert_eq(_flags(), before, "the trial wrote no flag")
	assert_eq(get_tree().get_nodes_in_group("heartseed_pickup").size(), 0, "and no Heartseed")


## MP section 8 "Explain checkpoint behaviour": after a reset the next attempt explains the retry rule once
## (wounds and burned anchors are kept while she stays in the Below; leaving lets it recover). Story only.
func test_the_retry_rule_is_explained_when_she_walks_back_in() -> void:
	var hints: Array = []
	var cb := func(id: String, _text: String) -> void: hints.append(id)
	Events.hint.connect(cb)
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "cling", 6.0)
	assert_false(hints.has("boss_retry"), "not on the first attempt")
	Events.player_died.emit()
	assert_eq(b.state, "dormant")
	_tick_until(b, "intro", 2.0)
	assert_eq(b.state, "intro", "she wakes again when Krystal walks back in")
	assert_true(hints.has("boss_retry"), "the retry rule is explained")
	var t := _boss(d, _braziers(), {"mode": "trial"})
	hints.clear()
	_tick_until(t, "cling", 6.0)
	Events.player_died.emit()
	_tick_until(t, "intro", 2.0)
	assert_false(hints.has("boss_retry"), "an echo trial never talks about the Below")
	Events.hint.disconnect(cb)


## Defeat clears the floor: every fan / line / sac fades during the retreat (the field keeps ticking while
## the defeat plays) and nothing is left behind once she is gone; minions scatter; no slow lingers.
func test_defeat_leaves_no_hazard_behind() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	var spawned: Array = []
	_busy_phase_two(b, d, spawned)
	# The retreat animation (fast_defeat off) awaits real timers; here its first half is stepped by hand:
	# _begin_defeat clears the floor with a fade, and tick() keeps fading it while the defeat plays.
	b.set("_defeat_started", true)
	b.field.clear_all(true)
	assert_true((b.field.hazards as Array).size() > 0, "precondition: hazards are fading, not yet freed")
	for i in 20:
		b.tick(DT)                     # 1 s of the retreat
	assert_eq((b.field.hazards as Array).size(), 0, "the cleared hazards faded out and were freed")
	assert_eq((b.field.sacs as Array).size(), 0, "sacs too")
	b.set("_defeat_started", false)
	# The real (fast) defeat with a fresh fan on the floor: nothing survives her going.
	b.field.begin_fan(Vector3.ZERO, d.global_position, 0.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.set_hp(5.0)
	b.health.apply_damage(10.0)
	assert_eq(b.state, "gone")
	assert_eq((b.field.hazards as Array).size(), 0, "no hazard left behind")
	assert_true(bool(b.field.is_clear()))
	assert_true(GameState.buffs.get("slow") == null, "no lingering slow")
	await wait_frames(1)
	assert_eq(int(b.field.alive_minions()), 0, "minions scattered")
