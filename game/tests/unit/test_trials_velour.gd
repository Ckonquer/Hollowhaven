extends "res://tests/unit/test_trials_harness.gd"
## Echo Trial "The Last Waltz" (Count Velour; data/trials.gd "velour", src/world/trial/velour_trial.gd, module D1):
## a remembered copy of the Count's Gallery with the REAL boss script in trial mode and fresh ward candles; the
## entry pad is safe and beyond his stand-down line; a win pays the first-clear bundle once (only its pattern flag),
## then modest renewable resources through the trial's own ledger (paid on arrival back at the ballroom candles); a
## win or a loss never changes a story flag, never emits boss_defeated (even on a save whose story fight is NOT won);
## arachnophobia: nothing spider-like.

const ManorLayout := preload("res://data/manor_layout.gd")
const VelourTrial := preload("res://src/world/trial/velour_trial.gd")
const VelourBoss := preload("res://src/enemies/count_velour.gd")


func test_the_real_count_spawns_in_trial_mode_in_a_faithful_gallery() -> void:
	completed_save()
	var a := await trial_area("velour")
	assert_eq(String(a.get("trial_id")), "velour")
	assert_eq(EchoTrial.pending_trial, "", "the area consumed the pending trial")
	var boss: Node = a.get("boss")
	assert_not_null(boss, "Count Velour is here")
	if boss == null:
		return
	assert_true(String(boss.get_script().resource_path).ends_with("count_velour.gd"), "the real boss script")
	assert_eq(String(boss.get("mode")), "trial")
	assert_false(bool(boss.call("is_story")))
	assert_false(bool(boss.call("is_gone")), "he fights although ch2_velour_defeated is set (a memory)")
	assert_false(bool(boss.get("fight_started")), "waiting until Krystal walks in")
	assert_null(boss.get("area"), "no owning area: he never reports to the manor")
	var ar: Dictionary = a.get("arena")
	assert_eq((ar["candles"] as Array).size(), 3, "three ward candles")
	var order: Array = ManorLayout.ARENA["candle_order"]
	for i in 3:
		var c: Node3D = ar["candles"][i]
		assert_true(bool(c.call("is_lit")), "candle %d burns" % i)
		var want := VelourTrial.rel(ManorLayout.ARENA["candles"][order[i]])
		assert_true(c.global_position.distance_to(Vector3(want.x, 0, want.z)) < 0.01, "candle %d where it stands in the Gallery" % i)
		assert_true(c.is_in_group("light_source"), "a real light source")
	assert_eq((boss.get("candles") as Array).size(), 3, "the boss plays with them")
	assert_eq((boss.get("cover") as Array).size(), 4, "pillars and statues")
	assert_eq((boss.get("helper_points") as Array).size(), 2)
	assert_almost(float(boss.get("arena_radius")), float(ManorLayout.ARENA["radius"]), 0.001)
	# Spawn, pad and door.
	assert_true((a.spawns as Dictionary).has("trial_start"))
	var start: Vector3 = (a.spawns["trial_start"] as Transform3D).origin
	assert_true(bool(a.is_safe_zone(start)), "the entry pad is safe")
	assert_false(bool(a.is_safe_zone(Vector3.ZERO)), "the Gallery is not")
	assert_eq(String(a.get_zone_at(Vector3.ZERO)), "trial")
	var r := float(boss.get("arena_radius"))
	var leave_margin: float = VelourBoss.LEAVE_MARGIN          # his stand-down margin (count_velour.gd)
	for k in 12:
		var p := start + Vector3(cos(TAU * k / 12.0), 0, sin(TAU * k / 12.0)) * 2.8
		assert_true(Vector2(p.x, p.z).length() > r + leave_margin, "every point of the pad is past his stand-down line")
	assert_true(Vector2(start.x, start.z).length() > r, "arriving never wakes him")
	var exit: Node = (a.get("exits") as Dictionary).get("leave")
	assert_not_null(exit, "the pale door")
	assert_true(bool(exit.get_meta("trial_exit", false)))
	# Geometry: floor under the fight, walls all round except the doors, corridor walled.
	var space := a.get_world_3d().direct_space_state
	for p in [Vector3.ZERO, Vector3(10, 0, 10), Vector3(-10, 0, -10), Vector3(0, 0, 12), start]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0, 1))
		assert_false(hit.is_empty(), "floor at %s" % str(p))
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), 0.0, 0.05, "flat floor at %s" % str(p))
	for k in 16:
		var dir := Vector3(cos(TAU * k / 16.0), 0, sin(TAU * k / 16.0))
		if dir.z > 0.95:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 5.0, 0), Vector3(0, 5.0, 0) + dir * 30.0, 1))
		assert_false(hit.is_empty(), "walled toward %s" % str(dir))
	for sx in [-1.0, 1.0]:
		assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 18), Vector3(sx * 6.0, 1, 18), 1)).is_empty(), "corridor walled")
	assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 20), Vector3(0, 1, 30), 1)).is_empty(), "the corridor ends in a wall")
	# Cover really blocks (his drain tether needs line of sight).
	var cv: Vector3 = (ar["cover"] as Array)[0]
	assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(cv + Vector3(-2, 1.2, 0), cv + Vector3(2, 1.2, 0), 1)).is_empty(), "a pillar blocks sight")


func test_a_win_pays_the_first_clear_once_then_bounded_repeats_and_no_story_flag() -> void:
	completed_save()
	var before: Dictionary = GameState.flags.duplicate(true)
	var stories := story_flags()
	var a := await trial_area("velour")
	await win_velour(a)
	assert_eq(String(a.get("result")), "won")
	assert_eq(ended, [["velour", true]], "Events.trial_ended(velour, true) once")
	assert_eq(defeats, [], "no Events.boss_defeated")
	assert_eq(int(EchoTrial.record("velour")["clears"]), 1, "the trial's own counter")
	assert_true(GameState.has_reward("rw_trial_velour_first"), "first-clear bundle through the ledger")
	assert_eq(flag_diff(before), ["ch2_trial_velour"], "only the reward's pattern-unlock flag appears")
	assert_eq(story_flags(), stories, "story flags untouched")
	assert_true(bool((a.get("last_clear") as Dictionary)["first"]))
	assert_true(float(a.get("_return_t")) > 0.0, "the way home is armed")
	var ledger_n := GameState.ledger.size()
	var wax := GameState.count_item("lantern_wax")
	var petal := GameState.count_item("moonpetal")
	# Second visit: the modest repeat.
	ended.clear()
	var a2 := await trial_area("velour")
	await win_velour(a2)
	assert_eq(ended, [["velour", true]])
	var rec := EchoTrial.record("velour")
	assert_eq(int(rec["clears"]), 2)
	assert_eq(GameState.ledger.size(), ledger_n, "the first-clear bundle never pays twice")
	# The repeat gift waits for the trip home (lead decision L08), then the arrival at the origin pays it once.
	assert_eq(GameState.count_item("lantern_wax"), wax, "nothing is given inside the echo")
	assert_eq(rec.get("pending", {}), {"lantern_wax": 2, "moonpetal": 2}, "the gift waits in the trial's record")
	assert_eq(int(rec.get("repeat_paid", 0)), 0, "not paid yet")
	assert_eq(EchoTrial.pay_pending("echo_trial"), {}, "never paid inside a trial")
	assert_eq(EchoTrial.pay_pending("moonveil_manor"), {"lantern_wax": 2, "moonpetal": 2}, "paid on arrival at the origin")
	assert_eq(EchoTrial.pay_pending("moonveil_manor"), {}, "once")
	rec = EchoTrial.record("velour")
	assert_eq(GameState.count_item("lantern_wax"), wax + 2, "modest lantern wax")
	assert_eq(GameState.count_item("moonpetal"), petal + 2, "and moonpetals")
	assert_eq(int(rec.get("repeat_paid", 0)), 1, "the trial ledger counts the paid repeat")
	assert_eq(rec.get("paid", {}), {"lantern_wax": 2, "moonpetal": 2})
	assert_false(rec.has("pending"), "nothing waits any more")
	before["ch2_trial_velour"] = true
	assert_eq(GameState.flags, before, "a repeat clear writes no flag at all")
	assert_eq(defeats, [], "still no boss_defeated")


func test_a_loss_changes_nothing_and_the_echo_resets() -> void:
	completed_save()
	var before: Dictionary = GameState.flags.duplicate(true)
	var trials_before: Dictionary = GameState.trials.duplicate(true)
	var ledger_before: Dictionary = GameState.ledger.duplicate(true)
	var a := await trial_area("velour")
	var boss := control(a, Vector3(0, 0, 3))
	boss.call("start_fight")
	tick_until(boss, "glide", 10.0)
	assert_true(bool(a.get("fighting")), "the fight (and its clock) started")
	tick(boss, 1.0)
	assert_true(float(a.get("elapsed")) >= 0.0)
	Events.player_died.emit()
	Events.player_died.emit()
	assert_eq(ended, [["velour", false]], "ended once, as a loss")
	assert_eq(String(a.get("result")), "lost")
	assert_eq(String(boss.get("state")), "dormant", "the echo resets")
	for c in (a.get("arena") as Dictionary)["candles"]:
		assert_true(bool((c as Node).call("is_lit")), "every candle back to its start state")
	assert_eq(GameState.flags, before, "no flag changed")
	assert_eq(GameState.trials, trials_before, "no clear recorded")
	assert_eq(GameState.ledger, ledger_before, "no reward")
	assert_eq(defeats, [])


## Walking back to the safe pad stands the Count down (the echo waits, neither a win nor a loss) and the trial's clock
## pauses, so the best time counts engaged fighting only; walking back into the Gallery wakes him again.
func test_the_pad_stands_him_down_and_pauses_the_clock() -> void:
	completed_save()
	var a := await trial_area("velour")
	var boss := control(a, Vector3(0, 0, 3))
	var d: Node3D = boss.get("target_override")
	boss.call("start_fight")
	tick_until(boss, "glide", 10.0)
	assert_true(bool(a.get("fighting")), "the fight is on")
	await wait_frames(3)
	assert_true(float(a.get("elapsed")) > 0.0, "the clock runs while the fight is on")
	d.global_position = (a.spawns["trial_start"] as Transform3D).origin
	tick(boss, 5.0)
	assert_eq(String(boss.get("state")), "dormant", "he stands down while she waits on the pad")
	assert_false(bool(a.get("fighting")), "the clock stops")
	var t := float(a.get("elapsed"))
	await wait_frames(4)
	assert_almost(float(a.get("elapsed")), t, 0.00001, "and stays stopped")
	assert_eq(String(a.get("result")), "", "neither a win nor a loss")
	assert_eq(ended, [], "the echo goes on")
	d.global_position = Vector3(0, 0, 3)
	tick(boss, 0.5)
	assert_true(bool(boss.get("fight_started")), "he wakes when she walks back in")
	assert_true(bool(a.get("fighting")), "the clock runs again")


## Never fake trial victory flags over story flags: even a save whose Count is NOT freed (e.g. a debug entry)
## gets a trial-mode fight whose win writes neither ch2_velour_defeated nor any other story flag.
func test_a_trial_win_never_writes_the_story_flag_even_on_an_unfinished_save() -> void:
	GameState.give_item("lantern", 1)
	assert_false(EchoTrial.is_available("velour"), "not offered before the Count is freed")
	var a := await trial_area("velour")
	var boss: Node = a.get("boss")
	assert_false(bool(boss.call("is_gone")))
	await win_velour(a)
	assert_eq(String(a.get("result")), "won")
	assert_false(bool(GameState.get_flag(ManorLayout.FLAG_VELOUR_DEFEATED)), "ch2_velour_defeated never written by a trial")
	assert_false(bool(GameState.get_flag("ch2_manor_restored")))
	assert_eq(defeats, [], "no Events.boss_defeated")


func test_arachnophobia_nothing_spider_like() -> void:
	completed_save()
	Settings.set_value("arachnophobia", true)
	var a := await trial_area("velour")
	a.call("on_player_spawned", dummy(a, Vector3(0, 0, 21.8)))
	var boss := control(a, Vector3(0, 0, 3))
	boss.call("start_fight")
	tick(boss, 8.0)
	boss.call("jump_to_phase", 2)
	tick(boss, 8.0)
	var texts: Array = label_texts(a)
	for s in said:
		texts.append(String(s[1]))
	texts.append_array(captions)
	var m := EchoTrial.menu_text("velour")
	texts.append(String(m["title"]))
	texts.append(String(m["body"]))
	for t in texts:
		assert_eq(has_spider_word(String(t)), "", "no spider-like wording: " + String(t))
	assert_true(texts.size() > 4, "something was said / captioned / labelled")
	for n in a.find_children("*", "", true, false):
		for g in ["spider", "web", "brood_skitter"]:
			assert_false(n.is_in_group(g), "no spider-like node")
