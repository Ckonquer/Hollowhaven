extends "res://tests/test_case.gd"
## QA CH2-003, the Weaver Matron's pacing (weaver_boss.gd PACING, MP section 8 "phases and decisions over
## health inflation"): the three one-use brazier scorches used to win in ~23 s after the intro shriek - each
## 5 s scorch carried her across the next phase threshold, so fans, trip-lines, the release, the channel and
## stoking were never needed. With 240 HP unchanged:
##   * a blow that crosses the next threshold stops exactly on it and the transition plays;
##   * in phases 2-3 one stun window takes at most LATE_WINDOW_CAP (two openings per later phase; phase 1
##     keeps the Chapter One 40%);
##   * a brazier lit / stoked while she is overhead before the phase's first action still burns its anchor,
##     but the scorch is BANKED and lands when that action ends (fan / trip-lines / release; the channel,
##     the combo's pounce);
##   * full fights simulated in the QA bot's styles (tools/qa/playthrough.py --matron-style fast|thorough)
##     meet every phase's mechanic and last minutes, not seconds.
## Headless, manual ticks (boss and brazier processing off), no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const ANCHORS := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]
# The simulated Krystal (player_logic.gd: walk 4.2, sprint 7.0, a 0.5 s swing that strikes 0.22 s in).
const RUN_SPEED := 5.5
const SPRINT_SPEED := 7.0
const REACH := 1.5
const SWORD := 18.0                 # Copper Sword
const SWING := 0.5
const SWING_STRIKE := 0.22
const FLOOR_R := 8.0                # she keeps to the open floor (the arena radius is 11.5)
## The boss states in which the QA bot goes to a brazier (playthrough.py BOSS_CEILING).
const BOT_CEILING := ["dormant", "intro", "cling", "reposition", "recover", "release", "phase_shriek", "trip_tele",
	"combo_gap", "climb"]
const KIT := ["fan_tele", "trip_tele", "release", "channel", "telegraph"]

var _nodes: Array = []
var _hints: Array = []
var _hint_texts: Dictionary = {}     # hint id -> the last text emitted with it


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
	_hints.clear()
	_hint_texts.clear()
	Settings.set_value("arachnophobia", false)
	Settings.set_value("timing_assist", false)
	Settings.set_value("high_visibility_cues", false)
	Events.hint.connect(_on_hint)


func after_each() -> void:
	Events.hint.disconnect(_on_hint)
	Settings.set_value("timing_assist", false)
	Settings.set_value("arachnophobia", false)
	await _free_nodes()
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _on_hint(id: String, text: String) -> void:
	_hints.append(id)
	_hint_texts[id] = text


func _free_nodes() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	for c in get_children():
		if c.name.begins_with("BurnedAnchor"):
			c.queue_free()
	await wait_frames(1)


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
		b.setup({"id": "pc%d" % i})
		add_child(b)
		var a: Vector3 = ANCHORS[i]
		b.global_position = Vector3(a.x * 0.8, 0.0, a.z * 0.8)
		b.set_process(false)
		out.append(b)
		_nodes.append(b)
	return out


func _boss(target: Node3D, brs: Array, level: int = 1, extra: Dictionary = {}) -> Node:
	var p := {"arena_center": CENTER, "anchors": ANCHORS, "braziers": brs}
	p.merge(extra, true)
	var b: Node = Factory.create("weaver_matron", p)
	add_child(b)
	b.set_process(false)
	b.target_override = target
	b.intensity_override = level
	b.fast_defeat = true
	_nodes.append(b)
	b.field.minion_override = func(pos: Vector3, _params: Dictionary) -> Node:
		var n := Node3D.new()
		add_child(n)
		n.global_position = pos
		_nodes.append(n)
		return n
	return b


func _tick_until(b: Node, s: String, max_t: float = 15.0) -> float:
	var t := 0.0
	while String(b.state) != s and t < max_t:
		b.tick(DT)
		t += DT
	return t


## Starts the fight and lights brazier 0 (phase 1: scorched at once), then takes it to phase 2 exactly.
func _to_phase_two(b: Node, brs: Array) -> void:
	_tick_until(b, "cling", 6.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.apply_damage(64.0)            # x1.5 = 96: 240 -> 144, the 60% threshold
	assert_eq(int(b.phase), 2, "precondition: phase 2")
	assert_eq(String(b.state), "climb", "precondition: the transition climb")


# --- The phase threshold stops a blow; later windows take half a band ----------------------------------------

func test_one_blow_never_carries_her_across_two_thresholds() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.set_hp(150.0)
	b.health.apply_damage(200.0, d, Vector3.FORWARD)          # x1.5: far past 60% and 30% (and 0)
	assert_false(bool(b.health.dead), "a phase-1 opening can never finish her")
	assert_almost(float(b.health.hp), 144.0, 0.001, "the blow stops on the 60% threshold")
	assert_eq(int(b.phase), 2, "phase 2 - never straight to phase 3")
	assert_eq(String(b.state), "climb", "and the transition plays (shriek + climb)")
	# Phase 2 -> 3: the same rule (a missed drop's opening this time).
	_tick_until(b, "cling", 6.0)
	b.set("_kit_shown", true)
	b.set("_release_done", true)
	b.health.set_hp(80.0)
	_tick_until(b, "telegraph", 15.0)
	d.global_position = Vector3(6, 0, 3)
	_tick_until(b, "stuck", 3.0)
	assert_eq(String(b.state), "stuck")
	b.health.apply_damage(500.0, d, Vector3.FORWARD)
	assert_false(bool(b.health.dead), "a phase-2 opening can never finish her")
	assert_almost(float(b.health.hp), 72.0, 0.001, "the blow stops on the 30% threshold")
	assert_eq(int(b.phase), 3)
	assert_eq(String(b.state), "climb")
	# The last phase has no floor, only its window cap (36 = half the band) for ordinary blows: the copper sword
	# needs two openings; a blow that would finish her always lands (lead decision, like Count Velour).
	b.set("_kit_shown", true)
	for opening in 2:
		_tick_until(b, "cling", 6.0)
		b.set("_channel_cd", 99.0)
		_tick_until(b, "telegraph", 15.0)
		d.global_position = Vector3(-6, 0, 3) if d.global_position.x > 0.0 else Vector3(6, 0, 3)
		_tick_until(b, "stuck", 4.0)
		assert_eq(String(b.state), "stuck", "opening %d" % opening)
		if opening == 0:
			for i in 3:
				if String(b.state) == "stuck":
					b.health.apply_damage(SWORD, d, Vector3.FORWARD)
			assert_false(bool(b.health.dead), "one phase-3 opening of ordinary blows takes at most its cap")
			assert_almost(float(b.health.hp), 36.0, 0.001, "72 -> 36")
			assert_eq(String(b.state), "climb")
		else:
			b.health.apply_damage(500.0, d, Vector3.FORWARD)
	await wait_frames(1)
	assert_eq(String(b.state), "gone", "phase 3 can be finished")


func test_later_phases_cap_one_window_at_half_a_band() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	assert_almost(float(b.window_cap()), 96.0, 0.001, "phase 1: the Chapter One 40%")
	(brs[0] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	for i in 3:
		b.health.apply_damage(SWORD, d, Vector3.FORWARD)   # 27 each while scorched
	assert_eq(String(b.state), "scorched", "phase 1: 81 of 96 - still down")
	# Phase 2 (its kit already shown): another scorch, two blows end the window.
	b.health.set_hp(140.0)
	b.call("_set_phase", 2)
	b.set("_kit_shown", true)
	b.set("_release_done", true)
	b.set("_phase_pending", false)
	assert_almost(float(b.window_cap()), 36.0, 0.001, "phases 2-3: 15% = half of a 72 hp band")
	(brs[1] as Node).call("light")                         # scorched again where she lies: a fresh window
	assert_eq(String(b.state), "scorched")
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	assert_eq(String(b.state), "scorched", "27 of 36")
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	assert_eq(String(b.state), "climb", "the cap reached: she scrambles back up - a later phase needs two openings")
	assert_almost(float(b.health.hp), 104.0, 0.001, "27 + 9 (trimmed): the window took 36, never 54")
	assert_eq(int(b.phase), 2)


## QA (real play): the late-window cap was only tested AFTER a blow, so the blow that crossed it landed whole
## and one phase-2 window took 54 hp (22.5%). The blow that would overshoot is now trimmed to the room left
## (the excess goes back to health before the death test) and ends the window - before a phase threshold,
## except for a blow that finishes her (lead decision: finishing blows always land).
func test_the_blow_that_would_overshoot_a_late_window_is_trimmed_to_the_cap() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_to_phase_two(b, brs)
	_tick_until(b, "cling", 6.0)
	b.set("_kit_shown", true)
	b.set("_release_done", true)
	var shown: Array = []
	b.health.damaged.connect(func(_a: float, _s: Node, _dir: Vector3) -> void: shown.append(float(b.health.hp)))
	# Phase 2, scorched (x1.5 = 27 a blow): the real-play window, 27 + 27 against a 36 hp cap.
	b.health.set_hp(140.0)
	b.call("_enter", "scorched", 5.0)
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	assert_eq(String(b.state), "scorched", "27 of 36: still down")
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	assert_almost(float(b.health.hp), 104.0, 0.001, "the second blow is trimmed to the 9 hp left (not 86)")
	assert_almost(float(b.get("_window_damage")), 36.0, 0.001, "the window took exactly its cap")
	assert_eq(String(b.state), "climb", "and the trimmed blow ends the window")
	assert_eq(int(b.phase), 2)
	# Same timings as before: the climb back up is the ordinary one.
	var climb_t := _tick_until(b, "cling", 6.0)
	assert_eq(String(b.state), "cling", "back on the ceiling after the ordinary climb (%.2f s)" % climb_t)
	# The cap binds before the phase threshold: 115 -> 88, then a blow that would reach 72 stops at 79.
	b.health.set_hp(115.0)
	b.call("_enter", "scorched", 5.0)
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	assert_almost(float(b.health.hp), 79.0, 0.001, "trimmed to the window's 9 hp, short of the 72 threshold")
	assert_eq(int(b.phase), 2, "so phase 3 waits for the next opening")
	assert_eq(String(b.state), "climb")
	# Phase 3 (no threshold left): a blow that would FINISH her lands whole even past the window cap (lead
	# decision, like Count Velour: a boss escaping to the ceiling at a sliver of health feels unfair).
	b.call("_set_phase", 3)
	b.set("_kit_shown", true)
	b.set("_phase_pending", false)
	b.health.set_hp(50.0)
	b.call("_enter", "scorched", 5.0)
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)          # 50 -> 23
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)          # 27 >= 23: the finisher is never trimmed
	await wait_frames(1)
	assert_true(bool(b.health.dead), "a finishing blow always lands")
	assert_eq(String(b.state), "gone")
	assert_eq(shown.slice(0, 5), [113.0, 104.0, 88.0, 79.0, 23.0], "later `damaged` listeners already see the trimmed health")


# --- Phases 2-3 show their kit before a scorch lands ------------------------------------------------------------

## The CH2-003 repro: a brazier lit during the phase-2 transition (climb / shriek) used to knock her down
## at once; now its anchor burns, the scorch is banked and lands right when her first web fan ends.
func test_a_light_during_the_phase_two_transition_is_banked_until_her_first_fan() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_to_phase_two(b, brs)
	var anchors_before: int = (b.anchors as Array).size()
	var seen: Array = []
	b.state_changed.connect(func(s: String) -> void: seen.append(s))
	(brs[1] as Node).call("light")
	assert_eq((b.anchors as Array).size(), anchors_before - 1, "the light counts: its anchor burns at once")
	assert_eq(String(b.state), "climb", "but she clings on - no scorch fall yet")
	assert_true(bool(b.scorch_banked()), "the scorch is banked")
	assert_true(_hints.has("boss_banked"), "and explained")
	var fx: Node = b.get_node_or_null("BankedEmbers")
	assert_true(fx != null and bool(fx.get("emitting")), "embers smoulder on her while it is banked")
	_tick_until(b, "scorched", 20.0)
	assert_eq(String(b.state), "scorched", "the banked scorch lands (%s)" % str(seen))
	var i_fan := seen.find("fan_tele")
	var i_fall := seen.find("scorch_fall")
	assert_true(seen.has("phase_shriek"), "the transition played")
	assert_true(i_fan >= 0 and i_fall > i_fan, "only after her first phase-2 action, the web fan (%s)" % str(seen))
	assert_eq(seen.slice(i_fan, i_fall + 1), ["fan_tele", "scorch_fall"], "right as the fan ends (%s)" % str(seen))
	assert_eq(int(b.field.count_kind("fan")), 1, "the fan itself was cast")
	assert_false(bool(b.scorch_banked()))
	assert_false(bool(fx.get("emitting")), "embers out")
	# The phase has been shown: from now on a light brings her down at once.
	b.call("_begin_climb")
	_tick_until(b, "cling", 3.0)
	(brs[2] as Node).call("light")
	assert_eq(String(b.state), "scorch_fall", "after the introduction the light scorches at once")


## COV-004: with arachnophobia on - here switched on mid-fight, after she was built as the Weaver - the banked-scorch
## ("clings on") and trip-line ("Trip-lines") hints use the comfort wording like every sibling hint and caption
## (the '[it wails, smouldering, but holds on]' caption, the phase-2 hint's "root lines"); switched back, the
## originals return. The text is picked when the hint is emitted.
func test_banked_and_tripline_hints_follow_arachnophobia_live() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_to_phase_two(b, brs)
	Settings.set_value("arachnophobia", true)
	assert_true(bool(b.get("_using_shade")), "precondition: the Hollow Mother now")
	(brs[1] as Node).call("light")
	assert_true(bool(b.scorch_banked()), "precondition: the scorch is banked")
	assert_eq(String(_hint_texts.get("boss_banked", "")),
		"It holds on through the heat! Watch what it does next - the light will still bring it down.", "comfort banked hint")
	b.call("_begin_trips")
	assert_eq(String(b.state), "trip_tele", "precondition: root lines were cast")
	var trip := String(_hint_texts.get("boss_tripline", ""))
	assert_eq(trip, "Root lines snap when you walk into them. Cut them with {attack}, burn them with your lit lantern, or jump over.",
		"comfort trip-line hint")
	for h in [String(_hint_texts.get("boss_banked", "")), trip]:
		for word in ["clings", "trip-line", "web", "silk", "thread", "spider"]:
			assert_false(h.to_lower().contains(word), "no spider-mode word '%s' in: %s" % [word, h])
	# Switched back mid-fight: the Weaver's own wording.
	Settings.set_value("arachnophobia", false)
	assert_false(bool(b.get("_using_shade")), "precondition: the Weaver again")
	b.call("_bank_scorch")
	assert_eq(String(_hint_texts.get("boss_banked", "")),
		"It clings on through the heat! Watch what it does next - the light will still bring it down.", "original banked hint")
	b.field.clear_all(false)
	b.call("_begin_trips")
	assert_true(String(_hint_texts.get("boss_tripline", "")).begins_with("Trip-lines snap"), String(_hint_texts.get("boss_tripline", "")))


func test_trip_lines_and_the_release_also_introduce_phase_two() -> void:
	for first in ["trips", "release"]:
		var d := _dummy(Vector3(0, 0, 3))
		var brs := _braziers()
		var b := _boss(d, brs)
		_to_phase_two(b, brs)
		_tick_until(b, "cling", 6.0)
		if first == "trips":
			b.set("_p2_step", 2)                      # the rotation's trip-line slot comes up first
		else:
			b.health.set_hp(100.0)                    # late phase 2 (a retry): the release comes first
		(brs[1] as Node).call("light")
		assert_true(bool(b.scorch_banked()), "%s: banked" % first)
		var want := "trip_tele" if first == "trips" else "release"
		_tick_until(b, want, 8.0)
		assert_eq(String(b.state), want, "%s: her first action" % first)
		assert_true(bool(b.scorch_banked()), "%s: still banked while it plays" % first)
		_tick_until(b, "scorch_fall", 3.0)
		assert_eq(String(b.state), "scorch_fall", "%s: the scorch lands when it ends" % first)
		await _free_nodes()


## Phase 3: a brazier lit during the transition is banked until her first phase-3 action. Snapping the
## smothering channel's thread (here: her lantern) turns the fall into the scorch.
func test_phase_three_banks_a_light_until_the_channel_and_the_snap_scorches_her() -> void:
	GameState.give_item("lantern", 1)
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_to_phase_two(b, brs)
	_tick_until(b, "cling", 6.0)
	b.set("_kit_shown", true)
	(brs[1] as Node).call("light")
	_tick_until(b, "scorched", 2.0)
	b.health.set_hp(80.0)
	b.health.apply_damage(10.0, d, Vector3.FORWARD)          # x1.5 = 15: stops on 72
	assert_almost(float(b.health.hp), 72.0, 0.001)
	assert_eq(int(b.phase), 3)
	(brs[2] as Node).call("light")                          # beside Krystal, during the climb
	assert_true(bool(b.scorch_banked()), "banked")
	assert_ne(String(b.state), "scorch_fall")
	_tick_until(b, "channel", 15.0)
	assert_eq(String(b.state), "channel", "her first phase-3 action: smothering a far brazier")
	assert_true(bool(b.scorch_banked()), "still banked while she channels")
	var cb: Node3D = b.get("_channel_brazier")
	assert_true(cb == brs[0] or cb == brs[1], "a far lit brazier")
	d.lantern_on = true
	d.global_position = cb.global_position + Vector3(0, 0, 1.5)
	b.tick(DT)
	assert_eq(String(b.state), "snap_fall", "the light snaps the thread")
	_tick_until(b, "scorched", 2.0)
	assert_eq(String(b.state), "scorched", "and the banked scorch turns the fall into a scorch")
	assert_false(bool(b.scorch_banked()))


## Phase 3 without a brazier to smother: the one-hazard + delayed-pounce combo is her first action; a
## banked scorch waits through the fan and the mark and catches her as the pounce lands.
func test_phase_three_combo_pounce_lands_a_banked_scorch() -> void:
	GameState.give_item("lantern", 1)
	var brs := _braziers()
	var d := _dummy((brs[0] as Node3D).global_position + Vector3(1.2, 0, 1.2))    # at the only lit brazier
	var b := _boss(d, brs)
	_tick_until(b, "cling", 6.0)
	b.health.set_hp(60.0)
	b.call("_set_phase", 3)
	b.call("_enter_cling", 0.05)
	(brs[0] as Node).call("light")
	assert_true(bool(b.scorch_banked()), "phase 3 before any action: banked")
	var seen: Array = []
	b.state_changed.connect(func(s: String) -> void: seen.append(s))
	_tick_until(b, "telegraph", 15.0)
	assert_eq(String(b.state), "telegraph", "the delayed pounce (%s)" % str(seen))
	assert_true(seen.has("fan_tele") and seen.has("combo_gap"), "after its one ground hazard (%s)" % str(seen))
	assert_true(bool(b.scorch_banked()), "still banked through the combo")
	d.global_position = Vector3(5, 0, 5)
	_tick_until(b, "scorched", 4.0)
	assert_eq(String(b.state), "scorched", "the pounce lands scorched, not merely stuck (%s)" % str(seen))
	assert_false(seen.has("stuck"))


func test_two_lights_during_the_introduction_both_land_and_a_reset_drops_a_banked_one() -> void:
	var d := _dummy(Vector3(0, 0, 3))
	var brs := _braziers()
	var b := _boss(d, brs)
	_to_phase_two(b, brs)
	(brs[1] as Node).call("light")
	(brs[2] as Node).call("light")
	assert_eq((b.anchors as Array).size(), 0, "both anchors burn at once")
	_tick_until(b, "scorched", 20.0)
	assert_eq(String(b.state), "scorched", "the first lands after the fan")
	assert_true(bool(b.scorch_banked()), "the second is still kept")
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	b.health.apply_damage(SWORD, d, Vector3.FORWARD)
	assert_eq(String(b.state), "climb", "window capped")
	_tick_until(b, "scorch_fall", 4.0)
	assert_eq(String(b.state), "scorch_fall", "the second lands at her next cling")
	assert_false(bool(b.scorch_banked()))
	await _free_nodes()
	# A reset (Krystal fell) drops a banked scorch; the brazier stays lit, the phase and wounds stay.
	var d2 := _dummy(Vector3(0, 0, 3))
	var brs2 := _braziers()
	var b2 := _boss(d2, brs2)
	_to_phase_two(b2, brs2)
	(brs2[1] as Node).call("light")
	assert_true(bool(b2.scorch_banked()))
	Events.player_died.emit()
	assert_eq(String(b2.state), "dormant")
	assert_false(bool(b2.scorch_banked()), "a reset drops the banked scorch")
	var fx: Node = b2.get_node_or_null("BankedEmbers")
	assert_true(fx == null or not bool(fx.get("emitting")), "no embers left on her")
	assert_true(bool((brs2[1] as Node).is_lit()), "the brazier stays lit")
	assert_eq(int(b2.phase), 2)
	assert_almost(float(b2.health.hp), 144.0, 0.001)


# --- Whole fights: the QA bot's play styles ---------------------------------------------------------------------

## One simulated fight. A near-perfect Krystal (see the constants) walks in, sprints clear of every drop /
## pounce mark and sideways out of every fan wedge, runs in and swings during every opening, answers every
## channel with her lit lantern, and uses the braziers like the QA bot (playthrough.py boss_fight):
##   "rush"     = --matron-style fast (the CH2-003 repro): one brazier in phase 1, a second the moment
##                phase 2 starts, every brazier that can be lit or stoked in phase 3;
##   "thorough" = the default style: one in phase 1, a second in phase 2 only after 100 s, phase-3
##                braziers after 7 s or once she has channelled.
## Only while the Matron is overhead, as the bot does. Trial mode (no story flags), seeded.
func _simulate(style: String, level: int, rng_seed: int) -> Dictionary:
	GameState.give_item("lantern", 1)
	var d := _dummy(Vector3(0, 0, 9.5))
	d.lantern_on = true
	var brs := _braziers()
	var b := _boss(d, brs, level, {"mode": "trial"})
	(b.get("_rng") as RandomNumberGenerator).seed = rng_seed
	var clock := [0.0]
	var events: Array = []
	var openings := [0, 0, 0, 0]
	var scorches := [0, 0, 0, 0]
	var prev := [String(b.state)]
	b.state_changed.connect(func(s: String) -> void:
		var ph := int(b.phase)
		var was: String = prev[0]
		prev[0] = s
		if s in ["stuck", "scorched"] and not (was in ["stuck", "scorched"]):
			openings[ph] += 1
		if s == "scorched" and was != "scorched":
			scorches[ph] += 1
		if s in KIT or s in ["scorched", "stuck"]:
			events.append([ph, s, snappedf(float(clock[0]), 0.01)]))
	var t := 0.0
	var start := -1.0
	var phase_start := {}
	var goal := Vector3.ZERO
	var dodging := false
	var fan_dodging := false
	var swing_cd := SWING_STRIKE
	var kindling: Node = null
	var hits := 0
	while t < 900.0 and String(b.state) != "gone":
		b.tick(DT)
		for br in brs:
			(br as Node)._process(DT)
		t += DT
		clock[0] = t
		var st := String(b.state)
		if st == "gone":
			break
		if start < 0.0 and bool(b.fight_started):
			start = t
		var ph := int(b.phase)
		if not phase_start.has(ph):
			phase_start[ph] = t
		var me := d.global_position
		var bp := (b as Node3D).global_position
		# 1) a drop / pounce mark: sprint clear of it once (even mid-kindle - the bot does the same)
		if st == "telegraph" or st == "drop":
			if not dodging:
				dodging = true
				goal = _clear_spot(b.get("_drop_target"), me, 4.5)
			_step(d, goal, SPRINT_SPEED)
			continue
		dodging = false
		# kindling / stoking: stay by the bowl until it takes
		if kindling != null and bool(kindling.call("is_kindling")):
			continue
		kindling = null
		# 2) a fan wedge aimed at her: 3 m sideways, once
		if st == "fan_tele":
			if not fan_dodging:
				fan_dodging = true
				var away := Vector3(me.x - bp.x, 0, me.z - bp.z)
				var side := Vector3(-away.z, 0, away.x).normalized() if away.length() > 0.1 else Vector3.RIGHT
				goal = _inside(me + side * 3.0)
			_step(d, goal, SPRINT_SPEED)
			continue
		fan_dodging = false
		# 3) an opening: run in, then swing
		if st in ["stuck", "scorched"]:
			var off := Vector3(me.x - bp.x, 0, me.z - bp.z)
			if off.length() < 0.1:
				off = Vector3(0, 0, 1)
			if off.length() > REACH + 0.05:
				_step(d, bp + off.normalized() * REACH, RUN_SPEED)
				swing_cd = SWING_STRIKE
				continue
			swing_cd -= DT
			if swing_cd <= 0.0:
				swing_cd += SWING
				if float(b.health.apply_damage(SWORD, d, -off.normalized())) > 0.0:
					hits += 1
			continue
		swing_cd = SWING_STRIKE
		# 4) a channel: bring the lit lantern to the brazier she smothers
		if st == "channel":
			var cb: Variant = b.get("_channel_brazier")
			if cb is Node3D and is_instance_valid(cb):
				var cp := (cb as Node3D).global_position
				var to_me := Vector3(me.x - cp.x, 0, me.z - cp.z)
				_step(d, cp + (to_me.normalized() if to_me.length() > 0.1 else Vector3.BACK) * 1.5, RUN_SPEED)
			continue
		# 5) braziers by style, only while she is overhead
		if st in BOT_CEILING:
			var lit_n := 0
			for br in brs:
				if bool((br as Node).call("is_lit")):
					lit_n += 1
			var in_phase := t - float(phase_start[ph])
			var channels := 0
			for e in events:
				if String(e[1]) == "channel":
					channels += 1
			var want := false
			if style == "rush":
				want = (ph == 1 and lit_n < 1) or (ph == 2 and lit_n < 2) or ph >= 3
			elif style == "thorough":
				want = (ph == 1 and lit_n < 1) or (ph == 2 and lit_n < 2 and in_phase > 100.0) \
					or (ph >= 3 and (in_phase > 7.0 or channels > 0))
			if want:
				var pick: Node3D = null
				for br in brs:
					var info: Dictionary = (br as Node).call("get_interaction", d)
					if bool(info.get("enabled", false)) and (pick == null or _flat((br as Node3D).global_position, me) < _flat(pick.global_position, me)):
						pick = br
				if pick != null:
					var bz := pick.global_position
					var off2 := Vector3(me.x - bz.x, 0, me.z - bz.z)
					if off2.length() > 1.6:
						_step(d, bz + (off2.normalized() if off2.length() > 0.1 else Vector3.BACK) * 1.5, RUN_SPEED)
					else:
						pick.call("interact", d)
						kindling = pick
					continue
		# 6) nothing to do: wait on the 6 m ring
		var ring := Vector3(me.x, 0, me.z)
		if ring.length() < 0.1:
			ring = Vector3(0, 0, 1)
		_step(d, ring.normalized() * 6.0, 4.2)
	start = maxf(start, 0.0)
	var per := [0.0, 0.0, 0.0]
	for ph in [1, 2, 3]:
		if phase_start.has(ph):
			var t0: float = start if ph == 1 else float(phase_start[ph])
			var to: float = float(phase_start[ph + 1]) if phase_start.has(ph + 1) else t
			per[ph - 1] = snappedf(to - t0, 0.1)
	var out := {"done": String(b.state) == "gone", "t": snappedf(t - start, 0.1), "per_phase": per,
		"phases": phase_start.keys(), "events": events, "openings": openings.slice(1), "scorches": scorches.slice(1),
		"hits": hits}
	await _free_nodes()
	return out


## Nearest spot `dist` from the mark, on the open floor.
func _clear_spot(mark: Vector3, me: Vector3, dist: float) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for k in 12:
		var ang := TAU * float(k) / 12.0
		var p := Vector3(mark.x + cos(ang) * dist, 0, mark.z + sin(ang) * dist)
		if Vector2(p.x, p.z).length() > FLOOR_R:
			continue
		var dd := _flat(p, me)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func _inside(p: Vector3) -> Vector3:
	var v := Vector2(p.x, p.z)
	if v.length() > FLOOR_R:
		v = v.normalized() * FLOOR_R
	return Vector3(v.x, 0, v.y)


func _step(d: Node3D, target: Vector3, speed: float) -> void:
	var off := Vector3(target.x - d.global_position.x, 0, target.z - d.global_position.z)
	var l := off.length()
	var s := speed * DT
	if l <= s:
		d.global_position = Vector3(target.x, 0, target.z)
	else:
		d.global_position += off / l * s


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Index of the first event of `phase` whose state is in `states` (-1 if none).
static func _first(events: Array, phase: int, states: Array) -> int:
	for i in events.size():
		if int(events[i][0]) == phase and String(events[i][1]) in states:
			return i
	return -1


func _describe(style: String, level: int, r: Dictionary) -> String:
	return "Matron %s (%s): %.1f s engaged [phase 1 %.1f / 2 %.1f / 3 %.1f s], %d hits, openings %s, scorches %s" % [
		style, ["Gentle", "Standard", "Intense"][level], float(r["t"]), float(r["per_phase"][0]), float(r["per_phase"][1]),
		float(r["per_phase"][2]), int(r["hits"]), str(r["openings"]), str(r["scorches"])]


## The CH2-003 repro, played to the end with the bot's "fast" style: every phase now shows its mechanics
## (phase 2: a fan / trip-lines before any scorch, and the late release; phase 3: the channel or the combo
## before any scorch) and each later phase takes two openings. Flawless simulated play went from 14 s (the
## real bot: 22.8 s) to ~40 s engaged - a few minutes for a first encounter - without becoming a sponge.
func test_the_bots_brazier_rush_now_meets_every_phase() -> void:
	for rng_seed in [3, 17, 29]:
		var r: Dictionary = await _simulate("rush", 1, rng_seed)
		var info := _describe("rush", 1, r)
		print(info)
		var ev: Array = r["events"]
		assert_true(bool(r["done"]), "finished: %s" % info)
		assert_eq((r["phases"] as Array).size(), 3, "all three phases: %s" % info)
		var p2_kit := _first(ev, 2, ["fan_tele", "trip_tele", "release"])
		var p2_scorch := _first(ev, 2, ["scorched"])
		assert_true(p2_kit >= 0 and (p2_scorch < 0 or p2_kit < p2_scorch), "phase 2 shows a fan / trip-lines before a scorch: %s %s" % [info, str(ev)])
		assert_true(_first(ev, 2, ["release"]) >= 0, "the late-phase-2 release comes up: %s %s" % [info, str(ev)])
		var p3_kit := _first(ev, 3, ["channel", "telegraph", "fan_tele"])
		var p3_scorch := _first(ev, 3, ["scorched"])
		assert_true(p3_kit >= 0 and (p3_scorch < 0 or p3_kit < p3_scorch), "phase 3 shows the channel / combo before a scorch: %s %s" % [info, str(ev)])
		assert_true(int(r["openings"][1]) >= 2 and int(r["openings"][2]) >= 2, "two openings in each later phase: %s" % info)
		assert_true(float(r["t"]) >= 35.0, "no longer a 14 s scorch rush: %s" % info)
		assert_true(float(r["t"]) <= 180.0, "not a sponge: %s" % info)


## The bot's default ("thorough") style, and the rush on Gentle / Intense: every fight is finished through
## all three phases within minutes (durations printed for the QA report).
func test_other_styles_and_intensities_finish_in_minutes() -> void:
	var cases := [["thorough", 1, 5], ["thorough", 1, 41], ["rush", 0, 7], ["rush", 2, 7]]
	for c in cases:
		var r: Dictionary = await _simulate(String(c[0]), int(c[1]), int(c[2]))
		var info := _describe(String(c[0]), int(c[1]), r)
		print(info)
		assert_true(bool(r["done"]), "finished: %s" % info)
		assert_eq((r["phases"] as Array).size(), 3, "all three phases: %s" % info)
		assert_true(int(r["openings"][1]) >= 2 and int(r["openings"][2]) >= 2, "two openings in each later phase: %s" % info)
		assert_true(float(r["t"]) >= 30.0 and float(r["t"]) <= 300.0, "not seconds, and not a sponge: %s" % info)
