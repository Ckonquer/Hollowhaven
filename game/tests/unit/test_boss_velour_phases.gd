extends "res://tests/test_case.gd"
## Count Velour (module C6a, MP 13.1): registration and spawn, the encounter events (boss_encounter_changed,
## boss_phase_changed, boss bar), the reach tell (out of reach and armoured while hovering), phase thresholds with the
## health floor (a big hit never skips a phase), the transition beat, the per-window damage cap, the phase-C
## "borrowed mask" floor, the defeat committed first and exactly once, companions only in exposed windows, the
## intensity tables (Gentle / Intense) and the arachnophobia rule (nothing spider-like in either mode).
## Headless, manual ticks (boss process off), no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/count_velour.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const Combat := preload("res://src/combat/combat.gd")
const Layout := preload("res://data/manor_layout.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)

var _nodes: Array = []
var _events: Array = []
var _said: Array = []


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
	_said.clear()
	Settings.set_value("arachnophobia", false)
	Events.boss_phase_changed.connect(_on_phase)
	Events.boss_encounter_changed.connect(_on_encounter)
	Events.boss_defeated.connect(_on_defeated)
	Events.boss_health_changed.connect(_on_health)
	Events.say.connect(_on_say)


func after_each() -> void:
	Settings.set_value("timing_assist", _saved_assist)
	Events.boss_phase_changed.disconnect(_on_phase)
	Events.boss_encounter_changed.disconnect(_on_encounter)
	Events.boss_defeated.disconnect(_on_defeated)
	Events.boss_health_changed.disconnect(_on_health)
	Events.say.disconnect(_on_say)
	Settings.set_value("arachnophobia", false)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.get_parent() == self:
			e.queue_free()
	_nodes.clear()
	await wait_frames(2)


func _on_phase(id: String, p: int) -> void:
	_events.append(["phase", id, p])


func _on_encounter(id: String, active: bool) -> void:
	_events.append(["encounter", id, active])


func _on_defeated(id: String) -> void:
	_events.append(["defeated", id])


func _on_health(id: String, hp: float, _max: float) -> void:
	_events.append(["health", id, hp])


func _on_say(speaker: String, text: String, _d: float) -> void:
	_said.append([speaker, text])


func _count(kind: String) -> int:
	return _events.filter(func(e: Array) -> bool: return String(e[0]) == kind).size()


func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _candle(id: String, pos: Vector3, lit: bool = true) -> Node3D:
	var c: Node3D = WardCandle.new()
	c.setup({"id": id, "lit": lit, "pool_radius": 3.2})
	add_child(c)
	c.global_position = pos
	_nodes.append(c)
	return c


func _boss(target: Node3D, candles: Array = [], intensity: int = 1, extra: Dictionary = {}) -> Node3D:
	var p := {"arena_center": CENTER, "arena_radius": 12.0, "candles": candles, "seed": 11,
		"helper_points": [Vector3(-10, 1.4, 9), Vector3(10, 1.4, 9)]}
	p.merge(extra, true)
	var b: Node3D = Factory.create("count_velour", p, CENTER)
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


## Drives him into a recoil window right in front of the stand-in (a dash that misses her).
func _recoil(b: Node, d: Node3D) -> void:
	d.health.grant_iframes(3.0)
	b.next_action = "dash"
	_tick_until(b, "recoil", 20.0)
	d.health.grant_iframes(0.0)
	_tick(b, 0.2)


# --- Registration & start -------------------------------------------------------------------------------------

func test_registered_and_spawns_dormant_until_started() -> void:
	assert_true(Factory.has_enemy("count_velour"), "registered in the enemy factory")
	assert_true(Factory.can_spawn("count_velour"), "compiles")
	var d := _dummy(Vector3(0, 0, 4))
	var owner_area := Node.new()
	add_child(owner_area)
	_nodes.append(owner_area)
	var b := _boss(d, [], 1, {"area": owner_area})
	assert_false(b.is_in_group("enemy"), "dormant he is scenery, not an enemy")
	assert_eq(String(b.state), "dormant")
	assert_eq(float(b.health.max_hp), float(ItemDB.enemy("count_velour")["hp"]), "data hp")
	var hp: float = float(b.health.max_hp)
	assert_true(hp >= 340.0 and hp <= 420.0, "MP 13.1: 340-420 hp")
	assert_false(bool(b.auto_start), "an owning area starts him itself (teaching candle first)")
	_tick(b, 3.0)
	assert_eq(String(b.state), "dormant", "never starts on proximity when the arena owns the start")
	assert_false(bool(b.can_be_hit_by(d)), "untouchable while dormant")
	assert_false(bool(b.is_threatening()))
	assert_eq(_count("encounter"), 0)
	b.start_fight()
	assert_true(bool(b.fight_started))
	assert_true(b.is_in_group("enemy"), "an enemy while the encounter runs")
	assert_eq(_events.filter(func(e: Array) -> bool: return String(e[0]) == "encounter" and bool(e[2])).size(), 1, "encounter on")
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "phase" and String(e[1]) == "count_velour" and int(e[2]) == 1), "phase 1 event (music)")
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "health" and float(e[2]) > 0.0), "boss bar shown")
	assert_eq(String(b.state), "intro")
	b.start_fight()
	assert_eq(_count("encounter"), 1, "start_fight is idempotent")


func test_auto_start_without_an_area_and_stand_down() -> void:
	var d := _dummy(Vector3(0, 0, 30))
	var b := _boss(d)
	assert_true(bool(b.auto_start))
	_tick(b, 1.0)
	assert_false(bool(b.fight_started), "not while she is outside")
	d.global_position = Vector3(0, 0, 6)
	_tick(b, 0.5)
	assert_true(bool(b.fight_started), "starts when she enters the arena")
	d.global_position = Vector3(0, 0, 40)
	_tick(b, 5.0)
	assert_false(bool(b.fight_started), "stands down after she left for a while")
	assert_eq(String(b.state), "dormant")


func test_out_of_reach_while_hovering_and_reachable_in_windows() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.start_fight()
	_tick_until(b, "glide")
	assert_true(float(b.hover_y) > 2.6, "hovers above her reach")
	assert_false(bool(b.is_reachable()))
	assert_false(bool(b.can_be_hit_by(d)))
	assert_true(bool(b.health.invulnerable), "armoured while hovering (companions and projectiles see it)")
	# A real swing from right under him finds nothing to hit.
	d.global_position = Vector3(b.global_position.x, 0, b.global_position.z + 1.0)
	var hits: Array = Combat.melee(d, d.global_position + Vector3.UP * 0.9, Vector3(0, 0, -1), 2.5, 110.0, 18.0, ["enemy"], 4.0)
	assert_eq(hits.size(), 0, "out of reach overhead")
	d.global_position = Vector3(0, 0, 3)
	_recoil(b, d)
	assert_eq(String(b.state), "recoil")
	assert_true(bool(b.is_reachable()), "the recoil brings him down within reach")
	assert_true(bool(b.can_be_hit_by(d)))
	var to: Vector3 = b.global_position - d.global_position
	to.y = 0.0
	d.global_position = b.global_position - to.normalized() * 1.5
	d.global_position.y = 0.0
	var before: float = float(b.health.hp)
	hits = Combat.melee(d, d.global_position + Vector3.UP * 0.9, to.normalized(), 2.5, 110.0, 18.0, ["enemy"], 4.0)
	assert_eq(hits.size(), 1, "a real swing lands in the window")
	assert_almost(float(b.health.hp), before - 18.0, 0.01)


func test_phase_thresholds_floor_transition_and_events() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.start_fight()
	_recoil(b, d)
	var mx: float = float(b.health.max_hp)
	var dealt: float = float(b.health.apply_damage(9999.0, d, Vector3.FORWARD))
	assert_almost(float(b.health.hp), mx * 0.66, 0.01, "a huge hit stops at the phase-B threshold")
	assert_almost(dealt, mx - mx * 0.66, 0.01)
	assert_eq(int(b.phase), 2)
	assert_eq(String(b.state), "transition", "a theatrical transition beat")
	assert_true(bool(b.health.invulnerable), "invulnerable during the transition")
	assert_false(bool(b.can_be_hit_by(d)))
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "phase" and int(e[2]) == 2), "phase 2 event")
	assert_eq(float(b.health.apply_damage(50.0, d, Vector3.FORWARD)), 0.0, "no damage during the transition")
	_tick(b, 2.5)
	assert_eq(String(b.state), "glide", "back to the dance after the transition")
	assert_true(_said.any(func(s: Array) -> bool: return String(s[0]) == Layout.VELOUR_NAME), "a brief text line (no voice)")
	# Phase C through the same rule.
	b.jump_to_phase(3)
	assert_eq(int(b.phase), 3)
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "phase" and int(e[2]) == 3), "phase 3 event")
	assert_eq(Boss.phase_for(mx * 0.66, mx), 2, "the exact threshold already counts as the next phase")
	assert_eq(Boss.phase_for(mx * 0.33, mx), 3)
	assert_eq(Boss.phase_for(mx, mx), 1)


func test_window_cap_sends_him_back_up() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	b.start_fight()
	_recoil(b, d)
	var mx: float = float(b.health.max_hp)
	var hp0: float = float(b.health.hp)
	var n := 0
	while String(b.state) == "recoil" and n < 20:
		b.health.apply_damage(18.0, d, Vector3.FORWARD)
		n += 1
	assert_ne(String(b.state), "recoil", "the window closes once the cap is reached")
	assert_true(hp0 - float(b.health.hp) <= mx * Boss.WINDOW_CAP + 18.0 + 0.01, "one window takes at most WINDOW_CAP (+ the last swing)")
	assert_eq(String(b.state), "glide")
	assert_false(bool(b.can_be_hit_by(d)), "he whirled back out of reach")


func test_phase_c_borrowed_mask_needs_the_candle_rule() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var c := _candle("north", Vector3(7, 0, -6), true)
	var b := _boss(d, [c])
	b.start_fight()
	_tick_until(b, "glide")
	b.jump_to_phase(3)
	var mx: float = float(b.health.max_hp)
	_recoil(b, d)
	# Strong gear in every window: the mask holds at MASK_FLOOR until light has staggered him once.
	for i in 12:
		if String(b.state) != "recoil":
			_recoil(b, d)
		b.health.apply_damage(60.0, d, Vector3.FORWARD)
	assert_almost(float(b.health.hp), mx * Boss.MASK_FLOOR, 0.01, "the borrowed mask holds")
	assert_false(bool(b.health.dead))
	if String(b.state) != "recoil":
		_recoil(b, d)
	assert_eq(float(b.health.apply_damage(60.0, d, Vector3.FORWARD)), 0.0, "blocked at the mask floor")
	var hints: Array = []
	var on_hint := func(id: String, _t: String) -> void: hints.append(id)
	Events.hint.connect(on_hint)
	b.on_hit_blocked(d, Vector3.FORWARD)
	Events.hint.disconnect(on_hint)
	assert_true(hints.has("velour_mask"), "the glance teaches the candle rule")
	# Light (a relit candle) staggers him and lifts the floor.
	c.call("darken", null)
	c.call("light", d)
	assert_eq(String(b.state), "stagger", "light staggers him")
	assert_eq(int(b.c_staggers), 1)
	assert_almost(float(b.health.floor_hp), 0.0, 0.001, "the mask floor is gone")
	_tick(b, 1.0)
	assert_true(bool(b.can_be_hit_by(d)), "a generous window")
	assert_almost(float(b.health.damage_taken_mult), Boss.STAGGER_MULT, 0.001)
	b.health.apply_damage(9999.0, d, Vector3.FORWARD)
	assert_true(bool(b.health.dead), "defeatable once the rule was used")


func test_defeat_commits_first_and_exactly_once() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var c := _candle("north", Vector3(7, 0, -6), true)
	var b := _boss(d, [c])
	var sig: Array = []
	b.defeated.connect(func() -> void: sig.append(_count("defeated")))
	b.start_fight()
	_tick_until(b, "glide")
	b.jump_to_phase(3)
	c.call("darken", null)
	c.call("light", d)
	_tick(b, 1.0)
	b.health.apply_damage(9999.0, d, Vector3.FORWARD)
	assert_eq(_count("defeated"), 1, "Events.boss_defeated once")
	assert_true(_events.any(func(e: Array) -> bool: return String(e[0]) == "defeated" and String(e[1]) == "count_velour"), "data id")
	assert_eq(sig, [1], "the defeated signal follows the committed event")
	# Commit order: bar hidden and encounter over BEFORE boss_defeated; no line before the commit.
	var i_def := -1
	var i_enc := -1
	var i_bar := -1
	for i in _events.size():
		var e: Array = _events[i]
		if String(e[0]) == "defeated":
			i_def = i
		elif String(e[0]) == "encounter" and not bool(e[2]):
			i_enc = i
		elif String(e[0]) == "health" and float(e[2]) < 0.0:
			i_bar = i
	assert_true(i_bar >= 0 and i_enc >= 0 and i_bar < i_def and i_enc < i_def, "bar hidden + encounter off, then the defeat event")
	assert_eq(String(b.state), "gone", "the enchantment dispersed")
	assert_false(b.is_in_group("enemy"))
	assert_false(bool(b.visible))
	assert_eq(_said.filter(func(s: Array) -> bool: return String(s[1]) == Layout.VELOUR_AFTER).size(), 1,
		"without an owning arena he says the MP 17 line himself, once")
	# Nothing can repeat it.
	b.health.apply_damage(50.0, d, Vector3.FORWARD)
	b.start_fight()
	b.reset_fight()
	Events.player_died.emit()
	_tick(b, 1.0)
	assert_eq(_count("defeated"), 1, "never twice")
	assert_eq(int(b.defeat_events), 1)


func test_trial_mode_never_emits_the_story_event() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var c := _candle("north", Vector3(7, 0, -6), true)
	var b := _boss(d, [c], 1, {"mode": "trial"})
	var fired: Array = []
	b.defeated.connect(func() -> void: fired.append(true))
	b.start_fight()
	_tick_until(b, "glide")
	b.jump_to_phase(3)
	c.call("darken", null)
	c.call("light", d)
	_tick(b, 1.0)
	b.health.apply_damage(9999.0, d, Vector3.FORWARD)
	assert_eq(_count("defeated"), 0, "trial: no Events.boss_defeated (no story flags)")
	assert_eq(fired.size(), 1, "the trial still hears the defeated signal")
	assert_false(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)))


func test_story_boss_stays_gone_on_a_won_save() -> void:
	GameState.set_flag(Layout.FLAG_VELOUR_DEFEATED, true)
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	assert_true(bool(b.is_gone()), "never fights again once the arena committed the victory")
	assert_false(b.is_in_group("enemy"))
	b.start_fight()
	assert_false(bool(b.fight_started))


func test_companions_only_in_exposed_windows_and_inside_the_arena() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	var pal := Node3D.new()
	pal.add_to_group("companion")
	add_child(pal)
	_nodes.append(pal)
	pal.global_position = Vector3(1, 0, 3)
	b.start_fight()
	_tick_until(b, "glide")
	assert_false(bool(b.can_be_hit_by(pal)), "not while he hovers")
	_recoil(b, d)
	assert_true(bool(b.can_be_hit_by(pal)), "companions join in his windows")
	pal.global_position = Vector3(0, 0, 30)
	assert_false(bool(b.can_be_hit_by(pal)), "never from outside the arena")


func test_only_krystal_is_ever_hurt() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d)
	var pal := Dummy.new()
	pal.add_to_group("companion")
	pal.add_to_group("player")
	add_child(pal)
	_nodes.append(pal)
	var deco := Dummy.new()
	add_child(deco)
	_nodes.append(deco)
	assert_eq(float(b.call("_deal", pal, 20.0, Vector3.FORWARD, 0.0)), 0.0, "companions are never damaged")
	assert_eq(float(b.call("_deal", deco, 20.0, Vector3.FORWARD, 0.0)), 0.0, "decor / pets / anything else never")
	assert_almost(float(b.call("_deal", d, 20.0, Vector3.FORWARD, 0.0)), 20.0, 0.01, "Krystal (stand-in) through her health path")


func test_intensity_tables() -> void:
	for i in 3:
		assert_true(float(Boss.T_BOW[i]) >= 1.0, "committed warnings never under 1.0 s")
		assert_true(float(Boss.T_DRAIN_TELE[i]) >= 1.0)
		assert_true(float(Boss.SWEEP_TELE[i]) >= 1.4)
		assert_true(float(Boss.T_CH_FLY[i]) >= 1.0)
	assert_true(float(Boss.T_FINAL_TELL) >= 1.0, "the Intense final tell is a full warning")
	assert_true(float(Boss.DASH_SPEED[0]) < float(Boss.DASH_SPEED[1]), "Gentle: slower dash")
	assert_true(float(Boss.T_BOW[0]) > float(Boss.T_BOW[1]), "Gentle: longer bow")
	assert_true(float(Boss.T_DRAIN[0]) > float(Boss.T_DRAIN[1]) and float(Boss.DRAIN_POOL_BONUS[0]) > 0.0 and float(Boss.DRAIN_RANGE[0]) < float(Boss.DRAIN_RANGE[1]),
		"Gentle: an easier tether (longer channel to react, bigger pools, shorter range)")
	assert_eq(int(Boss.SWEEP_PATTERNS[0]), 1, "Gentle: one sweep pattern")
	assert_eq(int(Boss.SWEEP_PATTERNS[1]), 2)
	var mid_n: float = (float((Boss.T_GLIDE[1] as Array)[0]) + float((Boss.T_GLIDE[1] as Array)[1])) * 0.5
	var mid_i: float = (float((Boss.T_GLIDE[2] as Array)[0]) + float((Boss.T_GLIDE[2] as Array)[1])) * 0.5
	assert_true(mid_i < mid_n, "Intense: less idle time")
	assert_true(float(Combat.intensity_damage_mult(0)) < 1.0, "Gentle hits softer")
	var d := _dummy(Vector3(0, 0, 3))
	var g := _boss(d, [], 0)
	var n := _boss(d, [], 1)
	assert_true(float(g.call("_damage", "cape_dash", 16.0)) < float(n.call("_damage", "cape_dash", 16.0)))
	assert_eq((g.call("sweep_specs") as Array).size(), 1)
	var specs: Array = n.call("sweep_specs")
	assert_eq(specs.size(), 2)
	assert_ne(String((specs[0] as Dictionary)["orientation"]), String((specs[1] as Dictionary)["orientation"]), "two different patterns")


func test_arachnophobia_nothing_spider_like_in_either_mode() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var captions: Array = []
	var on_cap := func(t: String) -> void: captions.append(t.to_lower())
	Events.caption.connect(on_cap)
	for mode in [false, true]:
		Settings.set_value("arachnophobia", mode)
		var b := _boss(d)
		b.start_fight()
		b.next_action = "drain"
		_tick_until(b, "glide")
		_tick(b, 6.0)
		b.jump_to_phase(2)
		b.next_action = "disperse"
		_tick(b, 8.0)
		Events.settings_changed.emit("arachnophobia")
		assert_true(bool(b.fight_started), "a live settings change never disturbs the fight")
		b.reset_fight()
	Events.caption.disconnect(on_cap)
	for t in captions:
		for word in ["spider", "web", "silk", "skitter", "arachn"]:
			assert_false(String(t).contains(word), "no spider-like caption: " + String(t))
	assert_true(captions.size() > 3, "captions name his sounds")


# --- Review C6a: comfort "timing_assist" and Intense never warning shorter --------------------------------------

func test_timing_assist_stretches_warnings_windows_and_channels() -> void:
	Settings.set_value("timing_assist", true)
	var m: float = Boss.TIMING_ASSIST_MULT
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, [])
	b.start_fight()
	_tick_until(b, "glide")
	b.next_action = "dash"
	_tick_until(b, "bow")
	assert_almost(float(b.get("_state_len")), float(Boss.T_BOW[1]) * m, 0.001, "a longer bow")
	_tick_until(b, "recoil")
	var rec: Array = Boss.T_RECOIL_HIT if bool(b.get("_dash_hit")) else Boss.T_RECOIL
	assert_almost(float(b.get("_state_len")), float(rec[1]) * m, 0.001, "a longer recoil window")
	var specs: Array = b.call("sweep_specs")
	assert_almost(float((specs[0] as Dictionary)["tele"]), float(Boss.SWEEP_TELE[1]) * m, 0.001, "longer sweep warnings")
	assert_almost(float((specs[0] as Dictionary)["gap"]), float(Boss.SWEEP_GAP[1]) * m, 0.001)
	assert_almost(float(b.call("_tt", Boss.T_CHANNEL)), float(Boss.T_CHANNEL[1]) * m, 0.001, "a longer candle channel to interrupt")
	assert_almost(float(b.call("_tt", Boss.T_DRAIN)), float(Boss.T_DRAIN[1]) * m, 0.001, "more time to break the tether")
	assert_almost(float(b.call("_tt", Boss.T_STAGGER)), float(Boss.T_STAGGER[1]) * m, 0.001)
	Settings.set_value("timing_assist", false)
	assert_almost(float(b.call("_tt", Boss.T_BOW)), float(Boss.T_BOW[1]), 0.001, "off: the plain tables")


func test_intense_never_warns_shorter_than_standard() -> void:
	for table in [Boss.T_BOW, Boss.T_DRAIN_TELE, Boss.SWEEP_TELE, Boss.SWEEP_GAP]:
		assert_true(float(table[2]) >= float(table[1]), "Intense keeps the Standard warning (%s)" % str(table))
		assert_true(float(table[0]) >= float(table[1]), "Gentle warns at least as long (%s)" % str(table))


func test_without_any_ward_candle_phase_c_never_holds_an_unliftable_floor() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var b := _boss(d, [])
	b.start_fight()
	_tick_until(b, "glide")
	b.jump_to_phase(3)
	assert_almost(float(b.health.floor_hp), 0.0, 0.001, "no candle to play the rule with: no mask floor (never unwinnable)")
	var c := _candle("north", Vector3(7, 0, -6), true)
	var b2 := _boss(d, [c])
	b2.start_fight()
	_tick_until(b2, "glide")
	b2.jump_to_phase(3)
	assert_true(float(b2.health.floor_hp) > 0.0, "with candles the borrowed mask holds until the candle rule is used")
