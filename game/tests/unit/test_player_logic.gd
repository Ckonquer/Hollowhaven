extends "res://tests/test_case.gd"
## Pure player logic: stamina, swings, jump assist, safe-position tracking, recovery rules,
## interaction prompts / scoring and movement helpers (src/player/player_logic.gd).

const Logic := preload("res://src/player/player_logic.gd")


# --- Stamina ------------------------------------------------------------------------------------------

func test_sprint_drains_at_rate() -> void:
	var st := Logic.Stamina.new()
	st.reset(100.0, 100.0)
	for i in 60:
		st.tick(1.0 / 60.0, true)
	assert_almost(st.value, 100.0 - Logic.SPRINT_DRAIN, 0.01, "one second of sprint")
	assert_true(st.can_sprint(), "still can sprint")


func test_regen_waits_for_delay_then_regenerates() -> void:
	var st := Logic.Stamina.new()
	st.reset(50.0, 100.0)
	st.tick(0.1, true)                       # use -> delay restarts
	var after_use := st.value
	st.tick(0.5, false)                      # still inside the 0.6 s delay
	assert_almost(st.value, after_use, 0.0001, "no regen inside the delay")
	st.tick(0.5, false)                      # 0.1 s of delay left, 0.4 s of regen
	assert_almost(st.value, after_use + Logic.STAMINA_REGEN * 0.4, 0.001, "regen after the delay (carry-over within one tick)")


func test_regen_respects_buff_multiplier_and_cap() -> void:
	var st := Logic.Stamina.new()
	st.reset(10.0, 100.0)
	st.tick(1.0, false, 1.6)
	assert_almost(st.value, 10.0 + Logic.STAMINA_REGEN * 1.6, 0.001, "buffed regen")
	st.tick(20.0, false, 1.6)
	assert_almost(st.value, 100.0, 0.0001, "capped at max")


func test_exhaustion_hysteresis() -> void:
	var st := Logic.Stamina.new()
	st.reset(5.0, 100.0)
	st.tick(0.5, true)
	assert_almost(st.value, 0.0, 0.0001, "never negative")
	assert_true(st.exhausted, "exhausted at zero")
	assert_false(st.can_sprint(), "cannot sprint when exhausted")
	st.tick(0.6 + 0.5, false)                # 11 stamina
	assert_false(st.can_sprint(), "still exhausted below the resume threshold")
	st.tick(1.0, false)                      # 33 stamina
	assert_true(st.can_sprint(), "sprint resumes above the threshold")


func test_costs_all_or_nothing_and_soft() -> void:
	var st := Logic.Stamina.new()
	st.reset(15.0, 100.0)
	assert_false(st.try_spend(Logic.DODGE_COST), "dodge refused without enough stamina")
	assert_almost(st.value, 15.0, 0.0001, "refused dodge costs nothing")
	assert_true(st.try_spend(10.0), "affordable cost")
	assert_almost(st.value, 5.0, 0.0001)
	assert_false(st.spend_soft(Logic.SWING_COST), "soft spend reports it was not fully paid")
	assert_almost(st.value, 0.0, 0.0001, "soft spend floors at zero")
	assert_almost(st.delay_left, Logic.REGEN_DELAY, 0.0001, "spending restarts the regen delay")


# --- Swings ------------------------------------------------------------------------------------------------

func test_swing_strikes_exactly_once() -> void:
	var sw := Logic.Swing.new()
	assert_true(sw.start("axe"), "starts")
	assert_false(sw.start("axe"), "cannot start a second swing while one runs")
	var strikes := 0
	var finished := 0
	for i in 60:
		var ev := sw.tick(1.0 / 60.0)
		if ev & Logic.Swing.STRIKE:
			strikes += 1
		if ev & Logic.Swing.FINISHED:
			finished += 1
	assert_eq(strikes, 1, "one strike per swing")
	assert_eq(finished, 1, "finishes once")
	assert_false(sw.active, "inactive after finishing")
	assert_eq(sw.tick(0.1), 0, "no events when idle")


func test_swing_big_step_reports_strike_and_finish_together() -> void:
	var sw := Logic.Swing.new()
	sw.start("sword", 0.5, 0.22)
	var ev := sw.tick(1.0)
	assert_true((ev & Logic.Swing.STRIKE) != 0, "strike not skipped by a long frame")
	assert_true((ev & Logic.Swing.FINISHED) != 0, "finished in the same tick")


func test_swing_buffers_at_most_one_click() -> void:
	var sw := Logic.Swing.new()
	assert_true(sw.request(), "idle: a click starts a swing right away")
	sw.start("hands")
	sw.tick(0.05)
	assert_false(sw.request(), "a click right after starting is ignored...")
	assert_false(sw.buffered, "...and not buffered (double-click protection)")
	sw.tick(0.1)
	sw.request()
	sw.request()
	sw.request()
	assert_true(sw.buffered, "later click buffered")
	assert_true(sw.take_buffer(), "buffer returned once")
	assert_false(sw.take_buffer(), "and cleared")


func test_swing_cancel_only_before_strike() -> void:
	var sw := Logic.Swing.new()
	sw.start("axe", 0.5, 0.22)
	sw.tick(0.1)
	assert_true(sw.can_cancel(), "wind-up can be cancelled")
	sw.tick(0.15)
	assert_false(sw.can_cancel(), "after the strike the swing plays out")
	sw.cancel()
	assert_false(sw.active)
	assert_almost(sw.progress(), 0.0, 0.0001, "progress 0 when inactive")


# --- Jump assist ------------------------------------------------------------------------------------------

func test_coyote_time() -> void:
	var j := Logic.JumpAssist.new()
	j.tick(0.016, true)
	j.tick(0.1, false)                     # left the ledge 0.1 s ago
	j.press()
	assert_true(j.try_consume(), "jump allowed within coyote time")
	assert_false(j.try_consume(), "only once")
	var k := Logic.JumpAssist.new()
	k.tick(0.016, true)
	k.tick(0.15, false)
	k.press()
	assert_false(k.try_consume(), "too late after leaving the ledge")


func test_jump_buffer() -> void:
	var j := Logic.JumpAssist.new()
	j.tick(0.5, false)
	j.press()                              # pressed in the air
	j.tick(0.1, false)
	assert_false(j.try_consume(), "no jump while airborne")
	j.tick(0.016, true)                    # lands 0.116 s after the press
	assert_true(j.try_consume(), "buffered press jumps on landing")
	var k := Logic.JumpAssist.new()
	k.tick(0.5, false)
	k.press()
	k.tick(0.2, false)
	k.tick(0.016, true)
	assert_false(k.try_consume(), "stale press is dropped")


# --- Safe position tracking & recovery -----------------------------------------------------------------------

func test_safe_tracker_interval_and_safety() -> void:
	var s := Logic.SafeTracker.new()
	assert_false(s.tick(0.3, Vector3(0, 0, 0), true), "not before the interval")
	assert_true(s.tick(0.3, Vector3(0, 0, 0), true), "records after 0.5 s")
	assert_false(s.tick(0.6, Vector3(5, 0, 0), false), "unsafe spots are never recorded")
	assert_true(s.tick(0.016, Vector3(5, 0, 0), true), "records as soon as it is safe again")
	assert_eq(s.points.size(), 2)


func test_safe_tracker_history_and_recovery_point() -> void:
	var s := Logic.SafeTracker.new()
	assert_eq(s.recovery_point(Vector3(9, 9, 9)), Vector3(9, 9, 9), "fallback when empty")
	s.record(Vector3(0, 0, 0))
	assert_eq(s.recovery_point(Vector3.ZERO), Vector3(0, 0, 0), "single point")
	s.record(Vector3(0.1, 0, 0))
	assert_eq(s.points.size(), 1, "tiny moves replace the newest point")
	for i in 12:
		s.record(Vector3(float(i + 1), 0, 0))
	assert_eq(s.points.size(), Logic.SafeTracker.HISTORY, "history is capped")
	assert_eq(s.last(), Vector3(12, 0, 0))
	assert_eq(s.recovery_point(Vector3.ZERO), Vector3(11, 0, 0), "one sample back from the edge")
	s.drop_last()
	assert_eq(s.last(), Vector3(11, 0, 0))


func test_recovery_reasons() -> void:
	var half := 110.0
	assert_eq(Logic.recovery_reason(Vector3(0, -41, 0), "below", -40.0, half, NAN, 0.0), "fell")
	assert_eq(Logic.recovery_reason(Vector3(125, 5, 0), "surface", -40.0, half, NAN, 0.0), "outside")
	assert_eq(Logic.recovery_reason(Vector3(125, 5, 0), "below", -40.0, half, NAN, 0.0), "", "world bounds only on the surface")
	assert_eq(Logic.recovery_reason(Vector3(0, 1.0, 0), "surface", -40.0, half, 4.0, 0.5), "below_floor")
	assert_eq(Logic.recovery_reason(Vector3(0, 3.0, 0), "surface", -40.0, half, 4.0, 0.5), "", "slightly under the sampled height is fine")
	assert_eq(Logic.recovery_reason(Vector3(0, 10, 0), "arena", -40.0, half, NAN, 7.0), "falling")
	assert_eq(Logic.recovery_reason(Vector3(3, 0, 3), "surface", -40.0, half, 0.0, 0.0), "", "normal ground")


# --- Prompts & targeting ------------------------------------------------------------------------------------

func test_prompt_interaction_wins() -> void:
	var p := Logic.build_prompt({"text": "Open chest", "enabled": true}, {}, "")
	assert_eq(p, {"text": "Open chest", "action": "interact", "enabled": true})
	var hand := Logic.build_prompt({"text": "Pick Berries", "enabled": true}, {"tool": "hand", "name": "Berry Bush"}, "hand")
	assert_eq(hand, {"text": "Pick Berries", "action": "interact", "enabled": true}, "hand harvestables prompt their E interaction")
	var q := Logic.build_prompt({"text": "Locked", "enabled": false, "reason": "Needs a key"}, {}, "")
	assert_false(bool(q["enabled"]), "disabled interaction stays disabled")
	assert_eq(String(q.get("reason", "")), "Needs a key", "the reason is passed on to the HUD")
	assert_true(bool(Logic.build_prompt({"text": "Odd", "enabled": null}, {}, "")["enabled"]), "a null flag never errors")
	assert_eq(Logic.build_prompt({}, {}, ""), {}, "nothing -> empty prompt")
	assert_eq(Logic.build_prompt({"text": ""}, {}, ""), {}, "empty text is not a prompt")


func test_prompt_tool_harvestables_prompt_the_attack_action() -> void:
	# Real resource nodes answer get_interaction too ("Chop Oak Tree" / "Oak Tree - Needs an Axe");
	# the HUD must still teach the tool action (LMB), matching the swing that E also triggers.
	var owned := Logic.build_prompt({"text": "Chop Oak Tree", "enabled": true}, {"tool": "axe", "name": "Oak Tree"}, "stone_axe")
	assert_eq(owned, {"text": "Chop Oak Tree", "action": "attack", "enabled": true})
	var missing := Logic.build_prompt({"text": "Oak Tree - Needs an Axe", "enabled": false}, {"tool": "axe", "name": "Oak Tree"}, "")
	assert_eq(missing, {"text": "Needs an Axe", "action": "attack", "enabled": false})
	var boulder := Logic.build_prompt({"text": "Break the grumbling boulder", "enabled": true}, {"tool": "pickaxe", "name": "Grumbling Boulder"}, "stone_pickaxe")
	assert_eq(String(boulder["action"]), "attack")


func test_prompt_harvest_with_and_without_tool() -> void:
	assert_eq(Logic.build_prompt({}, {"tool": "axe", "name": "Oak Tree"}, "stone_axe"), {"text": "Chop Oak Tree", "action": "attack", "enabled": true})
	assert_eq(Logic.build_prompt({}, {"tool": "pickaxe", "name": "Rock"}, "stone_pickaxe"), {"text": "Mine Rock", "action": "attack", "enabled": true})
	assert_eq(Logic.build_prompt({}, {"tool": "axe", "name": "Oak Tree"}, ""), {"text": "Needs an Axe", "action": "attack", "enabled": false})
	assert_eq(Logic.build_prompt({}, {"tool": "pickaxe", "name": "Copper Vein"}, ""), {"text": "Needs a Pickaxe", "action": "attack", "enabled": false})
	assert_eq(Logic.build_prompt({}, {"tool": "hand", "name": "Berry Bush"}, ""), {"text": "Gather Berry Bush", "action": "attack", "enabled": true})


func test_weapon_kind_mapping() -> void:
	assert_eq(Logic.weapon_kind("", "", ""), "hands")
	assert_eq(Logic.weapon_kind("copper_sword", "weapon", ""), "sword")
	assert_eq(Logic.weapon_kind("stone_axe", "tool", "axe"), "axe")
	assert_eq(Logic.weapon_kind("stone_pickaxe", "tool", "pickaxe"), "pickaxe")
	for id in ["stone_axe", "stone_pickaxe", "copper_sword"]:
		var d := ItemDB.item(id)
		assert_ne(Logic.weapon_kind(id, String(d["cat"]), String(d["tool"])), "hands", "%s has a swing" % id)


func test_candidate_scoring() -> void:
	var pp := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	var ahead := Logic.score_candidate(pp, fwd, Vector3(0, 0, -1.5), 1.2, 2.6, false)
	var side := Logic.score_candidate(pp, fwd, Vector3(1.5, 0, 0), 1.2, 2.6, false)
	var behind := Logic.score_candidate(pp, fwd, Vector3(0, 0, 1.5), 1.2, 2.6, false)
	var far := Logic.score_candidate(pp, fwd, Vector3(0, 0, -4), 3.5, 2.6, false)
	var too_high := Logic.score_candidate(pp, fwd, Vector3(0, 4, -1), 0.5, 2.6, false)
	assert_true(ahead < side, "facing target preferred over one at the side")
	assert_eq(behind, INF, "behind the player is rejected")
	assert_eq(far, INF, "out of reach is rejected")
	assert_eq(too_high, INF, "far above is rejected")
	var ray := Logic.score_candidate(pp, fwd, Vector3(1.5, 0, 0), 1.2, 2.6, true)
	assert_true(ray < side, "camera-ray candidates get a bonus")
	var touching := Logic.score_candidate(pp, fwd, Vector3(0, 0, 0.3), 0.2, 2.6, false)
	assert_true(touching < INF, "a target the player is touching counts even if slightly behind")


# --- Movement helpers ------------------------------------------------------------------------------------------

func test_camera_relative_directions() -> void:
	var f := Logic.camera_relative(Vector2(0, -1), 0.0)
	assert_true(f.distance_to(Vector3(0, 0, -1)) < 0.001, "W at yaw 0 is -Z")
	var r := Logic.camera_relative(Vector2(1, 0), 0.0)
	assert_true(r.distance_to(Vector3(1, 0, 0)) < 0.001, "D at yaw 0 is +X")
	var f90 := Logic.camera_relative(Vector2(0, -1), PI * 0.5)
	assert_true(f90.distance_to(Vector3(-1, 0, 0)) < 0.001, "W at yaw 90 is -X")
	var diag := Logic.camera_relative(Vector2(1, -1), 0.3)
	assert_almost(diag.length(), 1.0, 0.0001, "diagonal input is not faster")
	var soft := Logic.camera_relative(Vector2(0, -0.4), 0.0)
	assert_almost(soft.length(), 0.4, 0.0001, "analog magnitude kept")


func test_yaw_dir_roundtrip() -> void:
	for yaw in [0.0, 0.7, -2.1, 3.0]:
		var d := Logic.dir_for_yaw(yaw)
		assert_almost(angle_difference(Logic.yaw_for_dir(d), yaw), 0.0, 0.0001, "yaw %s" % yaw)


func test_lantern_scale_by_time_and_area() -> void:
	assert_almost(Logic.lantern_scale("below", 12.0), 1.0, 0.0001, "full strength underground at noon")
	assert_almost(Logic.lantern_scale("surface", 12.0), 0.45, 0.0001, "soft in daylight")
	assert_almost(Logic.lantern_scale("surface", 23.0), 1.0, 0.0001, "full at night")
	assert_almost(Logic.lantern_scale("surface", 2.0), 1.0, 0.0001, "full before dawn")
	var dusk := Logic.lantern_scale("surface", 18.25)
	assert_true(dusk > 0.45 and dusk < 1.0, "ramps up at dusk (%.2f)" % dusk)
	var dawn := Logic.lantern_scale("surface", 6.75)
	assert_true(dawn > 0.45 and dawn < 1.0, "ramps down at dawn (%.2f)" % dawn)
	assert_almost(Logic.lantern_scale("surface", 36.0), 0.45, 0.0001, "hours wrap")


func test_dodge_speed_curve() -> void:
	assert_almost(Logic.dodge_speed(0.0), Logic.DODGE_SPEED_START, 0.0001)
	assert_almost(Logic.dodge_speed(1.0), Logic.DODGE_SPEED_END, 0.0001)
	var prev := 999.0
	for i in 11:
		var s := Logic.dodge_speed(float(i) / 10.0)
		assert_true(s <= prev, "monotonic ease-out")
		prev = s
	var dist := 0.0
	for i in 27:
		dist += Logic.dodge_speed(float(i) / 27.0) / 60.0
	assert_true(dist > 2.2 and dist < 3.4, "a roll covers ~2.5-3 m (got %.2f)" % dist)


func test_acceleration_and_deceleration() -> void:
	var v := Vector3.ZERO
	var target := Vector3(0, 0, -Logic.WALK_SPEED)
	var frames := 0
	while v.distance_to(target) > 0.001 and frames < 100:
		v = Logic.approach(v, target, true, 1.0 / 60.0)
		frames += 1
	assert_true(frames >= 6 and frames <= 12, "reaches walk speed in ~0.1-0.2 s (%d frames)" % frames)
	var air := Logic.approach(Vector3.ZERO, target, false, 1.0 / 60.0)
	assert_true(air.length() < Logic.approach(Vector3.ZERO, target, true, 1.0 / 60.0).length(), "less control in the air")
	var stop := Logic.approach(Vector3(0, 0, -4.2), Vector3.ZERO, true, 1.0)
	assert_eq(stop, Vector3.ZERO, "stops without overshoot")


# --- Airborne speed cap (lead decision for MP 6.2: jumps never stretch unpredictably) ------------------------------

func test_air_move_mult_caps_bonuses_but_never_slows() -> void:
	assert_almost(Logic.air_move_mult(1.0), 1.0, 0.0001, "legacy: no bonus, nothing changes")
	assert_almost(Logic.air_move_mult(1.05), 1.05, 0.0001, "small bonuses below the cap stay")
	assert_almost(Logic.air_move_mult(1.3), Logic.AIR_MOVE_MULT_CAP, 0.0001, "+30% -> +10% in the air")
	assert_almost(Logic.AIR_MOVE_MULT_CAP, 1.10, 0.0001)
	assert_almost(Logic.air_move_mult(0.5), 0.5, 0.0001, "slows apply fully")
	assert_almost(Logic.air_move_mult(0.65), 0.65, 0.0001, "a buff under a slow is not trimmed")
	var hv := Vector3(3.0, 0.0, -6.0)
	assert_eq(Logic.jump_takeoff(hv, 1.0), hv, "legacy take-off unchanged")
	assert_eq(Logic.jump_takeoff(hv, 1.08), hv, "below the cap: unchanged")
	assert_eq(Logic.jump_takeoff(hv, 0.5), hv, "slowed: unchanged")
	var fast := Logic.jump_takeoff(Vector3(0, 0, -Logic.SPRINT_SPEED * 1.3), 1.3)
	assert_almost(fast.length(), Logic.SPRINT_SPEED * 1.1, 0.0001, "sprinting at +30% leaves the ground at sprint x 1.10")
	assert_true(fast.normalized().is_equal_approx(Vector3(0, 0, -1)), "direction kept")
	assert_eq(Logic.jump_takeoff(Vector3.ZERO, 1.3), Vector3.ZERO)


## Horizontal reach of a held full jump taken at full speed (`base` = sprint or walk top speed), simulated with the
## same Logic steps as player.gd _physics_process: take-off trim, airborne approach toward the capped top speed,
## gravity with the heavier fall, landing back at take-off height. `capped` = false replays the old behaviour
## (whole multiplier in the air, no take-off trim) as a control.
static func _jump_reach(base: float, move_mult: float, capped: bool = true) -> float:
	var dt := 1.0 / 60.0
	var hv := Vector3(0.0, 0.0, -base * move_mult)            # ground speed keeps the whole multiplier
	if capped:
		hv = Logic.jump_takeoff(hv, move_mult)
	var air_mult := Logic.air_move_mult(move_mult) if capped else move_mult
	var air_target := Vector3(0.0, 0.0, -base * air_mult)
	var vy := Logic.JUMP_VELOCITY
	var y := 0.0
	var dist := 0.0
	for i in 600:
		var g := Logic.GRAVITY * (Logic.FALL_GRAVITY_MULT if vy < 0.0 else 1.0)
		vy = maxf(vy - g * dt, -Logic.TERMINAL_FALL)
		hv = Logic.approach(hv, air_target, false, dt)
		y += vy * dt
		dist += hv.length() * dt
		if y <= 0.0:
			break
	return dist


func test_jump_reach_with_a_speed_buff_and_while_slowed() -> void:
	for base in [Logic.SPRINT_SPEED, Logic.WALK_SPEED]:
		var normal := _jump_reach(base, 1.0)
		var buffed := _jump_reach(base, 1.3)
		var slowed := _jump_reach(base, 0.5)
		var both := _jump_reach(base, 1.3 * 0.5)
		assert_true(normal > base * 0.55, "a full jump covers ground (%.2f m at %.1f m/s)" % [normal, base])
		assert_true(buffed / normal <= 1.105, "+30%% speed stretches the jump by at most ~10%% (%.3f)" % (buffed / normal))
		assert_true(buffed / normal >= 1.08, "the capped bonus still counts in the air (%.3f)" % (buffed / normal))
		assert_almost(slowed / normal, 0.5, 0.02, "a slow shortens the jump fully (%.3f)" % (slowed / normal))
		assert_almost(both / normal, 0.65, 0.02, "buffed and slowed: the slow applies to the whole multiplier (%.3f)" % (both / normal))
		var old := _jump_reach(base, 1.3, false)
		assert_true(old / normal > 1.25, "control: uncapped, +30%% stretched the jump by ~30%% (%.3f)" % (old / normal))
