extends "res://tests/test_case.gd"
## The reworked Weaver Matron, phases 1 -> 2 -> 3 (MP section 8): HP thresholds (60% / 30%), the
## transition (shriek + climb, hazards cleared, Events.boss_phase_changed), the phase-2 rotation (fan,
## drop, trip-lines, drop) with its warnings and recovery beats, the ONE late release of capped minions
## per intensity (never during a pounce, never underfoot; Gentle: one slower minion and no drop while it
## lives), phase 3 (reusable braziers with a readable cooldown, the smothering channel and both ways to
## interrupt it, the one-hazard + delayed-pounce combo) and can_be_hit_by for companions.
## Headless, manual ticks (boss process off), no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Field := preload("res://src/enemies/boss_hazards/hazard_field.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const ANCHORS := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]

var _nodes: Array = []
var _phases: Array = []
var _encounter: Array = []


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
	_phases.clear()
	_encounter.clear()
	Settings.set_value("arachnophobia", false)
	Settings.set_value("timing_assist", false)
	Settings.set_value("high_visibility_cues", false)
	Events.boss_phase_changed.connect(_on_phase)
	Events.boss_encounter_changed.connect(_on_encounter)


func after_each() -> void:
	Events.boss_phase_changed.disconnect(_on_phase)
	Events.boss_encounter_changed.disconnect(_on_encounter)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("timing_assist", false)
	Settings.set_value("high_visibility_cues", false)
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


func _on_phase(id: String, p: int) -> void:
	_phases.append([id, p])


func _on_encounter(id: String, active: bool) -> void:
	_encounter.append([id, active])


func _dummy(pos: Vector3, player := false) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	if player:
		d.add_to_group("player")
	_nodes.append(d)
	return d


func _braziers() -> Array:
	var out: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "pb%d" % i})
		add_child(b)
		var a: Vector3 = ANCHORS[i]
		b.global_position = Vector3(a.x * 0.8, 0.0, a.z * 0.8)
		b.set_process(false)
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


func _minions_to(b: Node, list: Array) -> void:
	b.field.minion_override = func(pos: Vector3, params: Dictionary) -> Node:
		var n := Node3D.new()
		n.set_meta("params", params)
		add_child(n)
		n.global_position = pos
		_nodes.append(n)
		list.append(n)
		return n


func _tick_until(b: Node, s: String, max_t: float = 15.0) -> float:
	var t := 0.0
	while b.state != s and t < max_t:
		b.tick(DT)
		t += DT
	return t


func _tick(b: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		b.tick(DT)
		t += DT


## Fight started, clinging, then forced into `phase` with `hp` (as if the thresholds were crossed).
func _in_phase(b: Node, phase: int, hp: float) -> void:
	_tick_until(b, "cling", 6.0)
	b.health.set_hp(hp)
	b.call("_set_phase", phase)
	b.call("_enter_cling", 0.05)


## Records the attack states it enters (ignoring clings / recovers / repositions).
func _attack_log(b: Node) -> Array:
	var log: Array = []
	b.state_changed.connect(func(s: String) -> void:
		if s in ["fan_tele", "telegraph", "trip_tele", "release", "channel"]:
			log.append(s))
	return log


# --- Thresholds and the transition ------------------------------------------------------------------------

func test_phase_thresholds() -> void:
	assert_eq(Boss.phase_for(240.0, 240.0), 1)
	assert_eq(Boss.phase_for(145.0, 240.0), 1)
	assert_eq(Boss.phase_for(144.0, 240.0), 2, "60%")
	assert_eq(Boss.phase_for(73.0, 240.0), 2)
	assert_eq(Boss.phase_for(72.0, 240.0), 3, "30%")
	assert_eq(Boss.phase_for(1.0, 240.0), 3)
	assert_almost(float(ItemDB.enemy("weaver_matron")["hp"]), 240.0, 0.001, "HP stays at the 240 baseline")


func test_crossing_60_percent_shrieks_climbs_and_clears_hazards() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	assert_eq(_encounter, [["weaver_matron", true]], "boss_encounter_changed(true) when the fight starts")
	assert_eq(_phases, [["weaver_matron", 1]], "phase 1 announced at the start")
	b.field.cap = 3
	b.field.begin_fan(Vector3(0, 0, 0), d.global_position, 0.0)       # a leftover hazard
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.apply_damage(40.0)            # 60 -> hp 180: still phase 1
	assert_eq(int(b.phase), 1)
	assert_eq(b.state, "scorched")
	b.health.apply_damage(24.0)            # 36 more -> hp 144 = 60%
	assert_eq(int(b.phase), 2, "phase 2 at 60%")
	assert_eq(_phases.back(), ["weaver_matron", 2], "Events.boss_phase_changed(id, 2)")
	assert_eq(b.state, "climb", "the window ends: it scrambles up")
	assert_eq(int(b.field.live_count()), 0, "hazards cleared on the transition")
	assert_almost(float(b.health.apply_damage(10.0)), 0.0, 0.001, "invulnerable while climbing")
	_tick_until(b, "phase_shriek", 3.0)
	assert_eq(b.state, "phase_shriek", "shrieks on the ceiling")
	var t := _tick_until(b, "cling", 4.0)
	assert_almost(t, Boss.T_PHASE_SHRIEK, DT + 0.001, "a 2 s transition beat")
	b.health.set_hp(80.0)
	b.set("_release_done", true)           # (the late-phase-2 release has its own test)
	_tick_until(b, "telegraph", 15.0)
	assert_eq(b.state, "telegraph", "phase 2 still drops")
	d.global_position = Vector3(6, 0, 3)   # step out of the mark
	_tick_until(b, "stuck", 3.0)
	assert_eq(b.state, "stuck")
	b.health.apply_damage(10.0)            # 70 = under 30%
	assert_eq(int(b.phase), 3, "phase 3 at 30%")
	assert_eq(_phases.back(), ["weaver_matron", 3])
	assert_eq(b.state, "climb")


func test_phase_two_rotation_warnings_and_recovery() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_in_phase(b, 2, 140.0)
	assert_eq(int(b.field.cap), 3, "Standard phase 2: three live hazards")
	var log := _attack_log(b)
	_tick_until(b, "fan_tele", 2.0)
	assert_almost(float(b.get("_state_len")), 1.2, 0.001, "fan warning 1.2 s")
	assert_eq(int(b.field.count_kind("fan")), 1, "the fan is marked on the floor")
	var fan: Node = b.field.hazards[0]
	assert_false(fan.is_active(), "not active during the warning")
	_tick_until(b, "recover", 2.0)
	assert_almost(float(b.get("_state_len")), 1.4, 0.001, "a recovery beat after the fan")
	_tick(b, 0.2)
	assert_true(fan.is_active(), "the sheet is down")
	for i in 600:
		b.tick(DT)
		if log.size() >= 4:
			break
	assert_eq(log.slice(0, 4), ["fan_tele", "telegraph", "trip_tele", "telegraph"], "readable rotation (got %s)" % str(log))
	assert_true(int(b.field.count_kind("trip")) >= 1, "trip-lines were stretched")
	assert_true(int(b.field.live_count()) <= 3, "within the cap")


func test_warnings_and_recovery_numbers() -> void:
	for i in 3:
		for tbl in [Boss.T_TELEGRAPH, Boss.T_FAN_TELE, Boss.T_TRIP_TELE, Boss.T_POUNCE_TELE]:
			assert_true(float(tbl[i]) >= 1.0 and float(tbl[i]) <= 1.6, "warnings stay in 1.0-1.6 s (%s)" % str(tbl))
	for tbl in [Boss.T_TELEGRAPH, Boss.T_FAN_TELE, Boss.T_TRIP_TELE, Boss.T_POUNCE_TELE]:
		assert_true(float(tbl[1]) >= 1.0 and float(tbl[1]) <= 1.4, "Standard warnings 1.0-1.4 s")
	assert_almost(float(Boss.T_STUCK[1]), 2.5, 0.001, "~2.5 s after a missed pounce")
	assert_true(float(Boss.T_SCORCHED[1]) > float(Boss.T_STUCK[1]), "a scorch opens a longer window")
	assert_true(float(Boss.T_POUNCE_TELE[1]) > float(Boss.T_TELEGRAPH[1]), "the phase-3 pounce is the delayed one")


# --- The release -------------------------------------------------------------------------------------------

func test_late_phase_two_release_is_capped_per_intensity() -> void:
	for level in [0, 1, 2]:
		var d := _dummy(Vector3(0, 0, 3))
		var b := _boss(d, _braziers(), level)
		var spawned: Array = []
		_minions_to(b, spawned)
		_in_phase(b, 2, 150.0)
		_tick(b, 0.2)
		assert_ne(b.state, "release", "not early in phase 2 (HP above 45%)")
		b.health.set_hp(100.0)
		var log := _attack_log(b)
		_tick_until(b, "release", 20.0)
		assert_eq(b.state, "release", "late phase 2: the release (intensity %d)" % level)
		var cap := int(Field.MINION_CAP[level])
		assert_eq((b.field.sacs as Array).size(), cap, "%d sac(s) (intensity %d)" % [cap, level])
		for s in b.field.sacs:
			assert_true(Vector2(s.pos.x - 0.0, s.pos.z - 3.0).length() >= Field.SAC_MIN_PLAYER_DIST, "sacs far from Krystal")
		log.clear()
		var t := 0.0
		while t < float(Boss.SAC_WARN[level]) + 0.5:
			b.tick(DT)
			t += DT
			if bool(b.field.sacs_pending()):
				assert_false(b.state in ["telegraph", "drop"], "no pounce while a sac shakes")
		assert_eq(spawned.size(), cap, "%d minion(s) hatched" % cap)
		for m in spawned:
			assert_true(Vector2((m as Node3D).global_position.x, (m as Node3D).global_position.z - 3.0).length() >= Field.SAC_CLEAR_DIST, "never underfoot")
			var params: Dictionary = (m as Node).get_meta("params")
			assert_almost(float(params["speed_scale"]), float(Boss.MINION_SPEED[level]), 0.001, "speed scale")
			assert_true(bool(params["no_drops"]) and bool(params["alert"]))
		if level == 0:
			assert_almost(float((spawned[0] as Node).get_meta("params")["speed_scale"]), 0.75, 0.001, "Gentle: one slower minion")
		# No second release, however long the phase lasts.
		for i in 400:
			b.tick(DT)
		assert_eq(int(b.field.released_count), cap, "only one release per attempt")
		if level == 0:
			assert_false(log.has("telegraph"), "Gentle: no drop while its minion lives (%s)" % str(log))
		b.queue_free()
		for m in spawned:
			(m as Node).queue_free()
		await wait_frames(1)


# --- Phase 3 ------------------------------------------------------------------------------------------------

func test_phase_three_braziers_reusable_after_a_readable_cooldown() -> void:
	GameState.give_item("lantern", 1)
	var d := _dummy(Vector3(0, 0, 3), true)
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	var br: Node = brs[0]
	br.call("light")
	_tick_until(b, "scorched", 2.0)
	assert_false(bool(br.reusable), "phases 1-2: one scorch per brazier")
	assert_eq(String(br.get_interaction(d)["text"]), "The brazier burns brightly")
	var anchors_before: int = (b.anchors as Array).size()
	b.health.set_hp(80.0)
	b.health.apply_damage(10.0)            # -> phase 3
	assert_eq(int(b.phase), 3)
	assert_true(bool(br.reusable), "phase 3: lit braziers become reusable")
	assert_almost(float(br.cooldown_left()), float(Boss.BRAZIER_COOLDOWN[1]), 0.001, "gathering heat (11 s)")
	var info: Dictionary = br.get_interaction(d)
	assert_false(bool(info["enabled"]))
	assert_true(String(info["text"]).begins_with("The brazier is gathering heat (11"), "readable countdown: %s" % info["text"])
	for i in 112:
		br._process(0.1)
	assert_eq(String(br.get_interaction(d)["text"]), "Stoke the brazier", "ready again")
	_tick_until(b, "cling", 8.0)
	b.target_override = d
	d.global_position = (br as Node3D).global_position + Vector3(0, 0, 1.4)
	br.interact(d)
	for i in 21:
		br._process(0.05)
	assert_eq(b.state, "scorch_fall", "a stoke scorches it again")
	assert_eq((b.anchors as Array).size(), anchors_before, "without burning another anchor")
	assert_almost(float(br.cooldown_left()), float(Boss.BRAZIER_COOLDOWN[1]), 0.06, "the cooldown restarts")


func test_channel_targets_the_far_brazier_and_a_thread_strike_interrupts_it() -> void:
	var d := _dummy(Vector3(0, 0, 3), true)
	var brs := _braziers()
	var b := _boss(d, brs)
	_in_phase(b, 3, 60.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.call("_begin_climb")
	_tick_until(b, "cling", 3.0)
	(brs[2] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.call("_begin_climb")
	_tick_until(b, "cling", 3.0)
	b.set("_channel_cd", 0.0)
	d.global_position = (brs[2] as Node3D).global_position + Vector3(0, 0, -1.5)   # Krystal by the north brazier
	b.call("_enter_cling", 0.05)
	_tick_until(b, "channel", 3.0)
	assert_eq(b.state, "channel", "it lowers a thread onto a brazier")
	assert_true(b.get("_channel_brazier") == brs[0], "the lit brazier farthest from Krystal")
	assert_almost(float(b.get("_state_len")), 4.0, 0.001, "a 4 s visible channel (Standard)")
	var th: Node = b.field.thread
	assert_not_null(th, "the thread exists")
	_tick(b, 1.0)
	assert_true(float((brs[0] as Node).dim_amount()) > 0.2, "the flame visibly shrinks")
	# Krystal runs over and strikes the knot.
	var aim: Vector3 = th.get_aim_point()
	assert_true(aim.y >= 1.5 and aim.y <= 2.3, "the knot hangs within reach (%.2f m)" % aim.y)
	var bz := (brs[0] as Node3D).global_position
	var dir := Vector3(aim.x - bz.x, 0, aim.z - bz.z).normalized()
	d.global_position = Vector3(aim.x, 0, aim.z) + dir * 1.6
	var hits: Array = Combat.melee(d, d.global_position + Vector3.UP * 0.9, -dir, 2.2, 110.0, 18.0, ["enemy"], 4.0)
	assert_true(hits.has(th), "the swing reaches the thread")
	assert_eq(b.state, "snap_fall", "the thread snaps and it falls")
	assert_true(bool((brs[0] as Node).is_lit()), "the brazier survives")
	assert_almost(float((brs[0] as Node).dim_amount()), 0.0, 0.001, "and burns fully again")
	_tick_until(b, "stuck", 2.0)
	assert_eq(b.state, "stuck", "an opening")
	assert_true(b.is_vulnerable())
	var bp := (b as Node3D).global_position
	for br in brs:
		var p := (br as Node3D).global_position
		assert_true(Vector2(bp.x - p.x, bp.z - p.z).length() >= Boss.BRAZIER_CLEARANCE - 0.01, "never lands on a brazier")


func test_channel_is_interrupted_by_bringing_the_lantern_close() -> void:
	var d := _dummy(Vector3(0, 0, 3), true)
	var brs := _braziers()
	var b := _boss(d, brs)
	_in_phase(b, 3, 60.0)
	(brs[1] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.call("_begin_climb")
	_tick_until(b, "cling", 3.0)
	b.set("_channel_cd", 0.0)
	d.global_position = Vector3(5, 0, 5)
	b.call("_enter_cling", 0.05)
	_tick_until(b, "channel", 3.0)
	assert_eq(b.state, "channel")
	d.global_position = (brs[1] as Node3D).global_position + Vector3(1.5, 0, 0)
	_tick(b, 0.3)
	assert_eq(b.state, "channel", "no light, no interrupt")
	d.lantern_on = true
	b.tick(DT)
	assert_eq(b.state, "snap_fall", "her lantern breaks the channel")
	assert_null(b.field.thread, "thread gone")


func test_a_finished_channel_smothers_the_brazier_until_its_cooldown() -> void:
	GameState.give_item("lantern", 1)
	var d := _dummy(Vector3(0, 0, 3), true)
	var brs := _braziers()
	var b := _boss(d, brs)
	_in_phase(b, 3, 60.0)
	var br: Node = brs[1]
	br.call("light")
	_tick_until(b, "scorched", 2.0)
	b.call("_begin_climb")
	_tick_until(b, "cling", 3.0)
	var anchors_before: int = (b.anchors as Array).size()
	b.set("_channel_cd", 0.0)
	d.global_position = Vector3(5, 0, 5)
	b.call("_enter_cling", 0.05)
	_tick_until(b, "channel", 3.0)
	_tick_until(b, "recover", 5.0)
	assert_eq(b.state, "recover", "a recovery beat after the channel")
	assert_false(bool(br.is_lit()), "the brazier was smothered")
	assert_false(br.is_in_group("light_source"), "and gives no light")
	var info: Dictionary = br.get_interaction(d)
	assert_false(bool(info["enabled"]))
	assert_true(String(info["text"]).begins_with("The brazier is still smouldering"), info["text"])
	for i in 111:
		br._process(0.1)
	assert_eq(String(br.get_interaction(d)["text"]), "Light the brazier", "relightable after the cooldown")
	_tick_until(b, "cling", 4.0)
	br.call("light")
	assert_eq(b.state, "scorch_fall", "relighting scorches it")
	assert_eq((b.anchors as Array).size(), anchors_before, "no second anchor burns for the same brazier")


func test_phase_three_combo_is_one_hazard_then_a_delayed_pounce() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_in_phase(b, 3, 60.0)
	assert_eq(int(b.field.cap), 1, "phase 3: one ground hazard at a time")
	_tick_until(b, "fan_tele", 8.0)
	assert_eq(b.state, "fan_tele", "the ground hazard first (no lit brazier to smother)")
	_tick_until(b, "combo_gap", 2.0)
	assert_almost(float(b.get("_state_len")), float(Boss.T_COMBO_GAP[1]), 0.001, "a beat before the pounce")
	_tick_until(b, "telegraph", 2.0)
	assert_almost(float(b.get("_state_len")), 1.4, 0.001, "the delayed pounce shows its mark for 1.4 s")
	assert_true(int(b.field.live_count()) <= 1, "never a stack of hazards")
	d.global_position = Vector3(6, 0, 3)          # she steps out of the mark
	_tick_until(b, "stuck", 3.0)
	assert_eq(b.state, "stuck", "a missed pounce leaves it stuck")
	var t := _tick_until(b, "climb", 4.0)
	assert_almost(t, 2.5, DT + 0.001, "~2.5 s recovery window")


func test_phase_three_scatters_minions_and_clears_the_floor() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	var spawned: Array = []
	_minions_to(b, spawned)
	_in_phase(b, 2, 100.0)
	b.field.minion_cap = 2
	b.field.spawn_minion(Vector3(8, 0, 0))
	b.field.begin_fan(Vector3.ZERO, d.global_position, 0.0)
	assert_eq(int(b.field.alive_minions()), 1)
	b.call("_set_phase", 3)
	assert_eq(int(b.field.live_count()), 0, "hazards extinguished")
	await wait_frames(1)
	assert_eq(int(b.field.alive_minions()), 0, "minions scattered")


# --- Companions -----------------------------------------------------------------------------------------------

func test_companions_cannot_hit_it_overhead_or_from_outside_the_arena() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_tick_until(b, "cling", 6.0)
	var pet := _dummy(Vector3(1, 0, 2))
	assert_false(bool(b.can_be_hit_by(pet)), "overhead: no")
	assert_false(bool(b.can_be_hit_by(d)), "overhead: not Krystal either")
	_tick_until(b, "telegraph", 12.0)
	d.global_position = Vector3(6, 0, 3)
	_tick_until(b, "stuck", 3.0)
	assert_eq(b.state, "stuck")
	assert_true(bool(b.can_be_hit_by(pet)), "stuck and inside the arena: yes")
	pet.global_position = Vector3(0, 0, 20)
	assert_false(bool(b.can_be_hit_by(pet)), "never from outside the arena")


## Review fix: the "outside the arena" rule is for helpers only. Krystal striking a stunned Matron from the
## arena mouth lands (no "too tough right now" glance on a visibly stunned boss), a companion standing in
## the same spot is still refused, and a companion's refused blow never shows Krystal the glance hint.
func test_krystal_at_the_arena_mouth_may_strike_a_stunned_matron() -> void:
	var d := _dummy(Vector3(0, 0, 3), true)
	var b := _boss(d, _braziers())
	var hints: Array = []
	var cb := func(id: String, _text: String) -> void: hints.append(id)
	Events.hint.connect(cb)
	_tick_until(b, "cling", 6.0)
	var pet := _dummy(Vector3(1, 0, 2))
	pet.add_to_group("companion")
	b.on_hit_blocked(pet, Vector3.FORWARD)
	assert_false(hints.has("boss_glance"), "a companion's refused blow teaches Krystal nothing")
	b.on_hit_blocked(d, Vector3.FORWARD)
	assert_true(hints.has("boss_glance"), "her own glancing blow shows the rule")
	_tick_until(b, "telegraph", 12.0)
	d.global_position = Vector3(6, 0, 3)
	_tick_until(b, "stuck", 3.0)
	assert_eq(b.state, "stuck")
	var mouth := Vector3(0, 0, float(b.arena_radius) + 1.6)       # on the entrance ramp, just outside
	d.global_position = mouth
	pet.global_position = mouth
	assert_true(bool(b.can_be_hit_by(d)), "Krystal may strike it from the mouth")
	assert_false(bool(b.can_be_hit_by(pet)), "a companion there may not")
	var hp0 := float(b.health.hp)
	assert_true(float(b.health.apply_damage(18.0, d, Vector3.FORWARD)) > 0.0 and float(b.health.hp) < hp0, "her blow lands")
	Events.hint.disconnect(cb)


# --- Comfort settings ------------------------------------------------------------------------------------------

## Settings "timing_assist" ("removes tight timing windows from ... boss mechanics"): every warning, opening,
## recovery beat, the sac warning and the smothering channel last TIMING_ASSIST_MULT longer (Standard here).
func test_timing_assist_stretches_every_window() -> void:
	Settings.set_value("timing_assist", true)
	var m := float(Boss.TIMING_ASSIST_MULT)
	assert_true(m >= 1.4, "a real stretch (x%.2f)" % m)
	var d := _dummy(Vector3(0, 0, 3), true)
	var brs := _braziers()
	var b := _boss(d, brs)
	_minions_to(b, [])
	_tick_until(b, "telegraph", 12.0)
	assert_almost(float(b.get("_state_len")), 1.2 * m, 0.001, "drop warning")
	d.global_position = Vector3(6, 0, 3)
	_tick_until(b, "stuck", 4.0)
	assert_eq(b.state, "stuck")
	assert_almost(float(b.get("_state_len")), 2.5 * m, 0.001, "opening after a missed drop")
	(brs[0] as Node).call("light")
	assert_eq(b.state, "scorched")
	assert_almost(float(b.get("_state_len")), 5.0 * m, 0.001, "scorched opening")
	# Phase 2: the fan warning (the wedge on the floor uses the same length) and the recovery beat.
	b.health.set_hp(140.0)
	b.call("_set_phase", 2)
	b.set("_phase_pending", false)
	b.set("_release_done", true)
	b.call("_begin_climb")
	_tick_until(b, "cling", 4.0)
	b.call("_enter_cling", 0.05)
	_tick_until(b, "fan_tele", 3.0)
	assert_eq(b.state, "fan_tele")
	assert_almost(float(b.get("_state_len")), 1.2 * m, 0.001, "fan warning")
	assert_almost(float((b.field.hazards as Array).back().tele), 1.2 * m, 0.001, "the wedge warns as long")
	_tick_until(b, "recover", 4.0)
	assert_almost(float(b.get("_state_len")), 1.4 * m, 0.001, "recovery beat")
	# The late release: the sacs shake longer.
	b.set("_release_done", false)
	b.health.set_hp(100.0)
	_tick_until(b, "release", 20.0)
	assert_eq(b.state, "release")
	assert_almost(float((b.field.sacs as Array)[0].warn), 3.0 * m, 0.001, "sac warning")
	# Phase 3: the channel is slower to finish (more time to strike the knot or bring light).
	b.health.set_hp(60.0)
	b.call("_set_phase", 3)
	b.set("_phase_pending", false)
	b.call("_enter_cling", 0.05)
	_tick_until(b, "cling", 3.0)
	b.set("_channel_cd", 0.0)
	d.global_position = Vector3(6, 0, 3)
	b.call("_enter_cling", 0.05)
	_tick_until(b, "channel", 3.0)
	assert_eq(b.state, "channel", "brazier 0 is lit and far from Krystal")
	assert_almost(float(b.get("_state_len")), 4.0 * m, 0.001, "channel")
	Settings.set_value("timing_assist", false)
	assert_almost(float(b.call("_t", 1.2)), 1.2, 0.0001, "off: the exact tables")


## Settings "high_visibility_cues": the drop / pounce mark gets a bold outline (live toggle), and a ready
## phase-3 brazier's ring turns solid and wider.
func test_high_visibility_cues_outline_the_drop_mark_and_a_ready_brazier() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	var bold: MeshInstance3D = b.get("_shadow_bold")
	assert_not_null(bold, "the outline exists")
	assert_false(bold.visible, "off by default")
	Settings.set_value("high_visibility_cues", true)
	assert_true(bold.visible, "toggled live")
	_tick_until(b, "telegraph", 12.0)
	assert_true(bold.is_visible_in_tree(), "the drop mark shows its bold outline")
	Settings.set_value("high_visibility_cues", false)
	assert_false(bold.is_visible_in_tree(), "and hides it again")
	var br: Node = brs[2]
	br.call("light")
	br.call("set_reusable", true, 0.0)
	Settings.set_value("high_visibility_cues", true)
	br._process(0.1)
	var ring: MeshInstance3D = br.get("_ring")
	assert_true(ring.visible and ring.scale.x > 1.1, "a ready brazier's ring is bold (%.2f)" % ring.scale.x)
	Settings.set_value("high_visibility_cues", false)
	br._process(0.1)
	assert_almost(ring.scale.x, 1.0, 0.01, "normal ring without the setting")


## Integration with the real Brood Skitter (built by the enemies module in parallel): when its script is
## available the release hatches real enemies (home = arena centre, alert, no drops, Gentle speed
## scale), capped; when it is not, the sacs split open empty (guarded, see the hazards suite).
func test_real_brood_skitters_hatch_when_available() -> void:
	var path := String(Factory.SCRIPTS.get("brood_skitter", ""))
	if path == "" or not ResourceLoader.exists(path):
		assert_false(Factory.has_enemy("brood_skitter") and ResourceLoader.exists(path), "guarded: nothing to check yet")
		return
	for level in [0, 1]:
		var d := _dummy(Vector3(0, 0, 3))
		var b := _boss(d, _braziers(), level)
		_in_phase(b, 2, 100.0)
		_tick_until(b, "release", 10.0)
		assert_eq(b.state, "release")
		var t := 0.0
		while t < float(Boss.SAC_WARN[level]) + 0.5:
			b.tick(DT)
			t += DT
		var ms: Array = (b.field.minions as Array).duplicate()
		assert_eq(ms.size(), int(Field.MINION_CAP[level]), "capped (intensity %d)" % level)
		for m in ms:
			assert_true(is_instance_valid(m) and (m as Node).is_in_group("enemy"), "a real enemy")
			assert_eq(String((m as Node).get("enemy_id")), "brood_skitter")
			assert_true(((m as Node).get("home") as Vector3).distance_to(CENTER) < 0.01, "leashed to the arena")
			assert_false(bool((m as Node).get("drops_enabled")), "no drops from boss adds")
			if level == 0:
				assert_almost(float((m as Node).get("speed_scale")), 0.75, 0.001, "Gentle: slower")
			_nodes.append(m)
		Events.player_died.emit()
		await wait_frames(1)
		for m in ms:
			assert_false(is_instance_valid(m) and not (m as Node).is_queued_for_deletion(), "scattered on reset")
		b.queue_free()
		await wait_frames(1)


# --- Budget -------------------------------------------------------------------------------------------------------

## A long phase-2 fight (rotation, hazards forming / snagging / expiring, drops) ticks cheaply and keeps its
## node count bounded: the posts, at most `cap` live hazards plus the few still fading out.
func test_a_long_phase_two_fight_ticks_cheaply_with_bounded_nodes() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_in_phase(b, 2, 140.0)
	var cap := int(b.field.cap)
	var posts := (b.field.posts as Array).size()
	var most := 0
	var most_live := 0
	var acts: Array = []                # (a lambda captures locals by value: count in an Array)
	b.state_changed.connect(func(s: String) -> void:
		if s in ["fan_tele", "trip_tele", "telegraph"]:
			acts.append(s))
	var t0 := Time.get_ticks_usec()
	for i in 1800:                      # 30 s at 60 fps
		d.global_position = Vector3(sin(float(i) * 0.02) * 5.0, 0, cos(float(i) * 0.02) * 5.0)
		b.tick(1.0 / 60.0)
		most = maxi(most, b.field.get_child_count())
		most_live = maxi(most_live, int(b.field.live_count()))
	var us := float(Time.get_ticks_usec() - t0) / 1800.0
	assert_true(acts.size() >= 4, "the rotation kept going (%s)" % str(acts))
	assert_true(most_live <= cap, "never more than %d live hazards (%d)" % [cap, most_live])
	assert_true(most <= posts + cap + 3, "bounded hazard nodes (%d)" % most)
	assert_true(us < 300.0, "%.1f us per boss tick" % us)


## "Not a health sponge" (MP section 8): a scripted, near-perfect Krystal with the Copper Sword (18 damage,
## one swing per 0.5 s) who dodges every drop mark, needs a second to reach the stunned Matron and never
## lights a brazier still needs a real fight through all three phases - and not an endless one. Real play
## (misses, hits taken, healing, positioning, companions, braziers) lands around 2-4x this idealised time,
## i.e. a few engaged minutes. Standard intensity.
func test_an_idealised_fight_is_minutes_not_a_sponge() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, _braziers())
	_minions_to(b, [])
	var seen_phases: Array = []
	var t := 0.0
	var window_t := -1.0
	var swing_cd := 0.0
	var hits := 0
	var dodged := false
	while t < 600.0 and String(b.state) != "gone":
		b.tick(DT)
		t += DT
		if not seen_phases.has(int(b.phase)):
			seen_phases.append(int(b.phase))
		var st := String(b.state)
		if st == "telegraph":
			if not dodged:
				dodged = true
				# Step 4.5 m out of the mark, staying on the arena floor.
				var tgt: Vector3 = b.get("_drop_target")
				for k in 8:
					var ang := TAU * float(k) / 8.0
					var p := tgt + Vector3(cos(ang), 0, sin(ang)) * 4.5
					if Vector2(p.x, p.z).length() <= 8.0:
						d.global_position = Vector3(p.x, 0, p.z)
						break
		else:
			dodged = false
		if st in ["stuck", "scorched"]:
			if window_t < 0.0:
				window_t = 0.0
			window_t += DT
			if window_t >= 1.0:          # a second to run in, then swing
				var bp := (b as Node3D).global_position
				var off := Vector3(d.global_position.x - bp.x, 0, d.global_position.z - bp.z)
				if off.length() > 1.6 or off.length() < 0.1:
					off = Vector3(0, 0, 1)
				d.global_position = Vector3(bp.x, 0, bp.z) + off.normalized() * 1.5
				swing_cd -= DT
				if swing_cd <= 0.0:
					swing_cd = 0.5
					if float(b.health.apply_damage(18.0, d, -off.normalized())) > 0.0:
						hits += 1
		else:
			window_t = -1.0
			swing_cd = 0.0
	assert_eq(String(b.state), "gone", "the fight can be finished without a single brazier")
	assert_eq(seen_phases, [1, 2, 3], "through all three phases")
	assert_true(t >= 50.0, "not trivial even when played perfectly (%.0f s, %d hits)" % [t, hits])
	assert_true(t <= 150.0, "not a sponge: %.0f s idealised (%d hits)" % [t, hits])
	print("Matron idealised fight: %.1f s, %d hits" % [t, hits])
