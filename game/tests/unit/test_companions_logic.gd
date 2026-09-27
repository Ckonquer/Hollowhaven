extends "res://tests/test_case.gd"
## Pure companion decision logic (src/companions/companion_logic.gd): spawn planning per area/state,
## bond rules, Mochi's refusal at the mine, stuck detection, follow targets and prompts.

const Logic := preload("res://src/companions/companion_logic.gd")

var defs: Dictionary = {}


func before_each() -> void:
	defs = {}
	for id in ItemDB.creature_ids():
		defs[id] = ItemDB.creature(id)


func _rec(befriended: bool, assignment: String, wait_area: String = "", wait_pos: Variant = null) -> Dictionary:
	return {"befriended": befriended, "bond_xp": 0, "assignment": assignment, "wait_area": wait_area,
		"wait_pos": wait_pos, "last_pet_day": -1, "last_gift_day": -1, "last_fed_day": -1}


func _modes(plan: Dictionary) -> Dictionary:
	var out := {}
	for sp in plan["spawns"]:
		out[sp["id"]] = sp["mode"]
	return out


func _change_for(plan: Dictionary, id: String) -> Dictionary:
	for ch in plan["changes"]:
		if ch["id"] == id:
			return ch
	return {}


# --- Spawn planning -----------------------------------------------------------------------------------

func test_fresh_surface_everyone_is_wild_and_pebble_is_pinned() -> void:
	var recs := {"mochi": _rec(false, "wild"), "pebble": _rec(false, "wild"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "", "haven_start", defs, false, Vector3(50, 0, -66))
	var m := _modes(plan)
	assert_eq(m.size(), 3, "all three spawn on the surface")
	assert_eq(m["mochi"], "wild")
	assert_eq(m["pebble"], "pinned", "pebble waits under its boulder")
	assert_eq(m["lumi"], "wild")
	assert_true(plan["boulder"], "boulder must be spawned")
	assert_true(plan["changes"].is_empty(), "no state changes for a fresh game")


func test_broken_boulder_frees_unbefriended_pebble() -> void:
	var recs := {"mochi": _rec(false, "wild"), "pebble": _rec(false, "wild"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "", "haven_start", defs, true, null)
	assert_eq(_modes(plan)["pebble"], "wild", "boulder gone -> free (never stuck forever)")
	assert_false(plan["boulder"])


func test_surface_follower_home_and_wild_mix() -> void:
	var recs := {"mochi": _rec(true, "follow"), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "mochi", "haven_start", defs, true, null)
	var m := _modes(plan)
	assert_eq(m["mochi"], "follow")
	assert_eq(m["pebble"], "home")
	assert_eq(m["lumi"], "wild")


func test_waiting_in_same_area_spawns_at_wait_spot() -> void:
	var recs := {"mochi": _rec(true, "wait", "surface", [3.0, 1.0, -4.0]), "pebble": _rec(false, "wild"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "", "haven_start", defs, false, Vector3(50, 0, -66))
	var sp: Dictionary = plan["spawns"][0]
	assert_eq(sp["id"], "mochi")
	assert_eq(sp["mode"], "wait")
	assert_eq(sp["pos"], Vector3(3, 1, -4), "restored wait position")
	assert_true(_change_for(plan, "mochi").is_empty(), "no change needed")


func test_waiting_in_other_area_goes_home() -> void:
	var recs := {"mochi": _rec(false, "wild"), "pebble": _rec(true, "wait", "below", [1.0, 0.0, 2.0]), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "", "haven_start", defs, true, null)
	assert_eq(_modes(plan)["pebble"], "home", "found its way home")
	assert_eq(_change_for(plan, "pebble").get("assignment"), "home", "state updated to home")


func test_inconsistent_follow_without_active_goes_home() -> void:
	var recs := {"mochi": _rec(true, "follow"), "pebble": _rec(true, "follow"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "pebble", "haven_start", defs, true, null)
	var m := _modes(plan)
	assert_eq(m["pebble"], "follow", "the active companion follows")
	assert_eq(m["mochi"], "home", "only one follower")
	assert_eq(_change_for(plan, "mochi").get("assignment"), "home")


func test_mine_exit_reunites_mochi_waiting_at_threshold() -> void:
	var th := Vector3(50, 2, -66)
	var recs := {"mochi": _rec(true, "wait", "surface", [50.5, 2.0, -65.0]), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "", "mine_exit", defs, true, th)
	assert_eq(_modes(plan)["mochi"], "reunite", "Mochi bounces over and rejoins")
	assert_eq(_change_for(plan, "mochi").get("assignment"), "follow")
	# Arriving anywhere else: Mochi simply keeps waiting.
	var plan2 := Logic.plan_spawns("surface", recs, "", "haven_start", defs, true, th)
	assert_eq(_modes(plan2)["mochi"], "wait")


func test_mine_exit_with_other_follower_sends_mochi_home_happily() -> void:
	var th := Vector3(50, 2, -66)
	var recs := {"mochi": _rec(true, "wait", "surface", [50.0, 2.0, -66.0]), "pebble": _rec(true, "follow"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("surface", recs, "pebble", "mine_exit", defs, true, th)
	var m := _modes(plan)
	assert_eq(m["pebble"], "follow")
	assert_eq(m["mochi"], "reunite_home", "one follower rule kept")
	assert_eq(_change_for(plan, "mochi").get("assignment"), "home")


func test_below_only_the_brave_follower_spawns() -> void:
	var recs := {"mochi": _rec(true, "home"), "pebble": _rec(true, "follow"), "lumi": _rec(true, "home")}
	var plan := Logic.plan_spawns("below", recs, "pebble", "mine_entry", defs, true, null)
	var m := _modes(plan)
	assert_eq(m.size(), 1, "only the follower")
	assert_eq(m["pebble"], "follow")
	recs["pebble"]["assignment"] = "home"
	recs["lumi"]["assignment"] = "follow"
	plan = Logic.plan_spawns("below", recs, "lumi", "mine_entry", defs, true, null)
	assert_eq(_modes(plan).get("lumi"), "follow", "Lumi dares to enter")


func test_below_mochi_waits_at_surface_threshold_instead() -> void:
	var th := Vector3(50, 0, -66)
	var recs := {"mochi": _rec(true, "follow"), "pebble": _rec(true, "home"), "lumi": _rec(false, "wild")}
	var plan := Logic.plan_spawns("below", recs, "mochi", "mine_entry", defs, true, th)
	assert_true(plan["spawns"].is_empty(), "Mochi never comes below")
	var ch := _change_for(plan, "mochi")
	assert_eq(ch.get("assignment"), "wait")
	assert_eq(ch.get("wait_area"), "surface")
	assert_eq(ch.get("wait_pos"), th)


func test_below_keeps_companions_waiting_down_there() -> void:
	# Krystal told Lumi to wait in the Below, then continued from a lantern save down there.
	var recs := {"mochi": _rec(true, "wait", "surface", [50.0, 0.0, -66.0]), "pebble": _rec(true, "follow"),
		"lumi": _rec(true, "wait", "below", [3.0, -6.0, -60.0])}
	var plan := Logic.plan_spawns("below", recs, "pebble", "cp_shrine", defs, true, null)
	var m := _modes(plan)
	assert_eq(m.get("pebble"), "follow", "the follower beside Krystal")
	assert_eq(m.get("lumi"), "wait", "Lumi is still where she was left")
	assert_false(m.has("mochi"), "Mochi waits on the surface, never below")
	for sp in plan["spawns"]:
		if sp["id"] == "lumi":
			assert_eq(sp.get("pos"), Vector3(3, -6, -60), "at her wait spot")
	assert_true(plan["changes"].is_empty(), "nothing to repair")
	# Waiting on the surface: not spawned below (she'll be at her spot when Krystal comes up).
	recs["lumi"]["wait_area"] = "surface"
	assert_false(_modes(Logic.plan_spawns("below", recs, "pebble", "cp_shrine", defs, true, null)).has("lumi"))
	# A corrupt wait record for a timid creature below is ignored, not spawned.
	recs["mochi"]["wait_area"] = "below"
	assert_false(_modes(Logic.plan_spawns("below", recs, "pebble", "cp_shrine", defs, true, null)).has("mochi"))


func test_arena_behaves_like_surface() -> void:
	var recs := {"mochi": _rec(true, "home"), "pebble": _rec(true, "home"), "lumi": _rec(true, "follow")}
	var plan := Logic.plan_spawns("arena", recs, "lumi", "haven_start", defs, true, null)
	assert_eq(_modes(plan).size(), 3)


# --- Bond rules ----------------------------------------------------------------------------------------

func test_pet_bond_once_per_day() -> void:
	var r := _rec(true, "home")
	assert_eq(Logic.pet_bond(r, 3), Logic.PET_BOND, "first pet today")
	assert_eq(Logic.pet_bond(r, 3), 0, "second pet same day gives nothing")
	assert_eq(Logic.pet_bond(r, 4), Logic.PET_BOND, "next day again")


func test_feed_rules() -> void:
	var r := _rec(true, "home")
	assert_eq(Logic.feed_check(r, 2, false), "no_food")
	assert_eq(Logic.feed_check(r, 2, true), "ok")
	assert_eq(Logic.feed_bond(r, 2), Logic.FEED_BOND)
	assert_eq(Logic.feed_check(r, 2, true), "full", "already fed today")
	assert_eq(Logic.feed_bond(r, 2), 0)
	assert_eq(Logic.feed_check(r, 3, true), "ok", "hungry again tomorrow")


func test_work_bond_capped_per_day() -> void:
	var r := _rec(true, "follow")
	var total := 0
	for i in 8:
		total += Logic.work_bond(r, 1)
	assert_eq(total, Logic.WORK_BOND_DAILY_MAX, "at most 5 per day")
	assert_eq(Logic.work_bond(r, 2), 1, "resets the next day")


func test_zone_bond_first_time_only() -> void:
	var r := _rec(true, "follow")
	assert_eq(Logic.zone_bond(r, "glade"), Logic.ZONE_BOND)
	assert_eq(Logic.zone_bond(r, "glade"), 0, "only once per zone")
	assert_eq(Logic.zone_bond(r, "quarry"), Logic.ZONE_BOND)
	assert_eq(Logic.zone_bond(r, ""), 0, "no zone, no bond")
	assert_eq(r["zones"].size(), 2)


func test_zone_bond_tolerates_a_damaged_save_value() -> void:
	var r := _rec(true, "follow")
	r["zones"] = "oops"
	assert_eq(Logic.zone_bond(r, "glade"), Logic.ZONE_BOND, "no script error, bond still works")
	assert_eq(r["zones"], ["glade"])


func test_daily_rewards_are_not_repeated_after_save_and_load() -> void:
	# The companion record (incl. the module's extra keys) round-trips through JSON like a real save,
	# and every once-per-day / once-per-zone reward stays spent afterwards.
	GameState.new_game()
	var day := GameState.day()
	var rec := GameState.companion("pebble")
	rec["befriended"] = true
	assert_eq(Logic.pet_bond(rec, day), Logic.PET_BOND)
	assert_eq(Logic.feed_bond(rec, day), Logic.FEED_BOND)
	assert_eq(Logic.zone_bond(rec, "quarry"), Logic.ZONE_BOND)
	for i in Logic.WORK_BOND_DAILY_MAX:
		Logic.work_bond(rec, day)
	rec["last_gift_day"] = day
	var saved: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(saved)
	var back := GameState.companion("pebble")
	assert_eq(Logic.pet_bond(back, day), 0, "already petted today")
	assert_eq(Logic.feed_check(back, day, true), "full", "already fed today")
	assert_eq(Logic.zone_bond(back, "quarry"), 0, "zone already explored together")
	assert_eq(Logic.work_bond(back, day), 0, "work bond cap still reached today")
	assert_false(Logic.gift_due(back, day), "today's gift already given")
	assert_eq(Logic.pet_bond(back, day + 1), Logic.PET_BOND, "tomorrow works again")
	GameState.new_game()


func test_gift_due_once_per_day() -> void:
	var r := _rec(true, "follow")
	assert_true(Logic.gift_due(r, 5))
	r["last_gift_day"] = 5
	assert_false(Logic.gift_due(r, 5))
	assert_true(Logic.gift_due(r, 6))
	assert_false(Logic.gift_due(_rec(false, "wild"), 6), "no gifts before befriending")


# --- Mochi at the mine ---------------------------------------------------------------------------------------

func test_mochi_refuses_near_threshold_once_per_approach() -> void:
	assert_true(Logic.should_refuse(false, "follow", 7.5, false), "close while following -> refuse")
	assert_false(Logic.should_refuse(false, "follow", 7.5, true), "already refused this approach")
	assert_false(Logic.should_refuse(false, "follow", 9.0, false), "not close enough yet")
	assert_false(Logic.should_refuse(false, "wait", 3.0, false), "only a follower refuses")
	assert_false(Logic.should_refuse(true, "follow", 3.0, false), "brave companions enter")
	assert_false(Logic.approach_reset(10.0), "still near: stay refused")
	assert_true(Logic.approach_reset(15.0), "walked away: next approach may refuse again")
	var mochi: Dictionary = defs["mochi"]
	assert_false(bool(mochi["enters_below"]), "data: Mochi never enters the mine")


# --- Following ------------------------------------------------------------------------------------------------

func test_stuck_detection() -> void:
	var tr := Logic.new_stuck_tracker()
	assert_eq(Logic.stuck_update(tr, 25.0, 0.016, 2.6), "far", "too far -> recover now")
	assert_eq(Logic.stuck_update(tr, 3.0, 0.5, 2.6), "", "close enough is fine")
	# Lagging with no progress for 4 s -> stuck
	var result := ""
	for i in 50:
		result = Logic.stuck_update(tr, 9.0, 0.1, 2.6)
		if result != "":
			break
	assert_eq(result, "stuck", "no progress for 4 s")
	# Making progress keeps resetting the timer
	tr = Logic.new_stuck_tracker()
	var d := 12.0
	for i in 60:
		d -= 0.06
		result = Logic.stuck_update(tr, d, 0.1, 2.6)
		assert_eq(result, "", "progressing is never stuck (step %d)" % i)
		if result != "":
			break


func test_progress_detector_catches_hopping_in_place() -> void:
	var tr := {}
	var stuck := false
	# Wants to move but only jitters around the same spot (e.g. hopping against a wall).
	for i in 60:
		var p := Vector3(0.1 * sin(float(i)), 0.4 * absf(sin(float(i) * 0.5)), 0.0)
		stuck = Logic.progress_update(tr, p, true, 0.1) or stuck
	assert_true(stuck, "no net progress for 4 s while wanting to move -> stuck")
	# Actually walking is never stuck.
	tr = {}
	stuck = false
	for i in 80:
		stuck = Logic.progress_update(tr, Vector3(0, 0, -0.35 * float(i)), true, 0.1) or stuck
	assert_false(stuck, "walking makes progress")
	# Standing still on purpose (no goal) is never stuck.
	tr = {}
	stuck = false
	for i in 80:
		stuck = Logic.progress_update(tr, Vector3.ZERO, false, 0.1) or stuck
	assert_false(stuck, "resting is not being stuck")


func test_los_detector() -> void:
	var tr := {}
	var fired := false
	for i in 60:
		fired = Logic.los_update(tr, false, 3.0, 0.1) or fired
	assert_false(fired, "6 s without line of sight is tolerated")
	for i in 15:
		fired = Logic.los_update(tr, false, 3.0, 0.1) or fired
	assert_true(fired, "cut off from Krystal for 7 s -> recover")
	tr = {}
	fired = false
	for i in 100:
		fired = Logic.los_update(tr, i % 20 != 0, 3.0, 0.1) or fired
	assert_false(fired, "seeing her now and then resets it")


func test_goal_candidates_cover_both_sides() -> void:
	var c := Logic.goal_candidates(Vector3.ZERO, Vector3(0, 0, -1), 1.0, 2.6)
	assert_eq(c.size(), 6)
	var first: Vector3 = c[0]
	var second: Vector3 = c[1]
	assert_true(first.x > 0.5 and first.z > 0.5, "own side, behind")
	assert_true(second.x < -0.5 and second.z > 0.5, "other side, behind")
	var last: Vector3 = c[5]
	assert_true(last.z < 0.0, "a spot ahead as a last resort (e.g. back against a wall)")
	for p in c:
		var d := (p as Vector3).length()
		assert_true(d > 1.0 and d < 3.0, "never on top of Krystal, never far (%.2f)" % d)


func test_follow_goal_is_behind_and_beside() -> void:
	var g := Logic.follow_goal(Vector3.ZERO, Vector3(0, 0, -1), 1.0, 2.6)
	assert_true(g.z > 1.0, "behind Krystal (she faces -Z)")
	assert_true(g.x > 0.8, "on the right side")
	var g2 := Logic.follow_goal(Vector3.ZERO, Vector3(0, 0, -1), -1.0, 2.6)
	assert_true(g2.x < -0.8, "other side")
	var g3 := Logic.follow_goal(Vector3(5, 1, 5), Vector3.ZERO, 1.0, 2.6)
	assert_almost(g3.y, 1.0, 0.001, "zero forward handled")


func test_camera_safe_pushes_out_of_view_corridor() -> void:
	var cam := Vector3(0, 3, 6)
	var player := Vector3(0, 0, 0)
	var blocking := Vector3(0.2, 0, 3)
	var fixed := Logic.camera_safe(blocking, player, cam, 1.0)
	assert_true(absf(fixed.x) >= 1.09, "pushed sideways out of the corridor (%s)" % fixed)
	assert_true(Logic.in_camera_corridor(blocking, player, cam))
	var beside := Vector3(2.0, 0, 2.0)
	assert_eq(Logic.camera_safe(beside, player, cam, 1.0), beside, "already clear")
	var ahead := Vector3(0, 0, -3)
	assert_eq(Logic.camera_safe(ahead, player, cam, 1.0), ahead, "beyond Krystal is fine")


func test_follow_speed() -> void:
	var ms := 4.6
	assert_eq(Logic.follow_speed(0.1, ms, 0.0), 0.0, "arrived")
	assert_true(Logic.follow_speed(8.0, ms, 4.0) > 7.5, "sprints to catch up")
	assert_true(Logic.follow_speed(0.8, ms, 4.3) >= 4.3, "never slower than a walking Krystal")
	assert_true(Logic.follow_speed(0.6, ms, 0.0) < Logic.follow_speed(2.0, ms, 0.0), "eases in when she stops")
	assert_true(Logic.follow_speed(20.0, ms, 12.0) <= ms * 1.9 + 0.001 or Logic.follow_speed(20.0, ms, 12.0) >= 12.0, "bounded")


func test_breadcrumb_trail() -> void:
	var trail: Array = []
	assert_true(Logic.trail_push(trail, Vector3(0, 0, 0)))
	assert_false(Logic.trail_push(trail, Vector3(0.1, 0, 0)), "too close to last crumb")
	for i in 60:
		Logic.trail_push(trail, Vector3(0, 0, -float(i + 1)))
	assert_eq(trail.size(), 48, "trail length capped")
	# Companion standing near crumb 20 resumes from there, not from the oldest crumb.
	var near: Vector3 = trail[20]
	var nxt: Variant = Logic.trail_next(trail, near + Vector3(0.1, 0, 0))
	assert_true(nxt is Vector3)
	assert_true((nxt as Vector3).z < near.z, "next crumb is ahead (toward Krystal)")
	assert_eq(trail.size(), 27, "crumbs behind were dropped")
	var empty: Array = []
	assert_null(Logic.trail_next(empty, Vector3.ZERO))


func test_placement_prefers_behind_camera() -> void:
	var player := Vector3(0, 0, 0)
	var cam := Vector3(0, 2.5, 5)
	var c := Logic.placement_candidates(player, Vector3(0, 0, -1), cam, 1.0)
	assert_true(c.size() >= 5)
	var first: Vector3 = c[0]
	assert_true(first.z > 5.0, "first candidate is behind the camera (out of view)")
	assert_false(Logic.in_view(cam, Vector3(0, -0.4, -1).normalized(), first), "and not visible")
	var c2 := Logic.placement_candidates(player, Vector3(0, 0, -1), null, 1.0)
	assert_true(c2.size() >= 4, "works without a camera")
	var first2: Vector3 = c2[0]
	assert_true(first2.z > 1.0, "then behind Krystal")


func test_in_view() -> void:
	var cam := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	assert_true(Logic.in_view(cam, fwd, Vector3(0, 0, -5)))
	assert_false(Logic.in_view(cam, fwd, Vector3(0, 0, 5)))
	assert_false(Logic.in_view(cam, fwd, Vector3(10, 0, -1)))


# --- Prompts ---------------------------------------------------------------------------------------------------

func test_wild_prompts() -> void:
	var p := Logic.wild_prompt("mochi", defs["mochi"], {"have": 1, "item_name": "Berries"})
	assert_false(p["enabled"])
	assert_true(String(p["text"]).contains("1/3"), "shows progress: %s" % p["text"])
	p = Logic.wild_prompt("mochi", defs["mochi"], {"have": 3, "item_name": "Berries"})
	assert_true(p["enabled"])
	assert_eq(p["text"], "Offer 3 Berries")
	p = Logic.wild_prompt("mochi", defs["mochi"], {"have": 5, "item_name": "Berries", "scared": true})
	assert_false(p["enabled"], "not while frightened")
	p = Logic.wild_prompt("lumi", defs["lumi"], {"ruin_cleared": false})
	assert_false(p["enabled"])
	p = Logic.wild_prompt("lumi", defs["lumi"], {"ruin_cleared": true})
	assert_true(p["enabled"])
	assert_eq(p["text"], "Reach out to the little light")
	p = Logic.wild_prompt("pebble", defs["pebble"], {"pinned": true})
	assert_false(p["enabled"])


func test_static_methods_are_discoverable_on_scripts() -> void:
	# The companions call other modules' static funcs via load(path).has_method/call (farming.tend).
	var s: Script = load("res://src/companions/companion_logic.gd")
	assert_true(s.has_method("plan_spawns"), "has_method works for static funcs on a Script")
	var r: Variant = s.call("zone_bond", {"zones": []}, "x")
	assert_eq(r, Logic.ZONE_BOND, "call() works for static funcs on a Script")


func test_emote_textures_render() -> void:
	var Icons: Script = load("res://src/companions/emote_icons.gd")
	var t0 := Time.get_ticks_msec()
	Icons.prewarm()
	var ms := Time.get_ticks_msec() - t0
	print("emote textures generated in %d ms" % ms)
	assert_true(ms < 1500, "prewarm stays cheap (%d ms)" % ms)
	for k in Icons.BUBBLE_KINDS:
		var tex: Texture2D = Icons.bubble(k)
		assert_not_null(tex, "bubble %s" % k)
		var img := tex.get_image()
		assert_eq(img.get_width(), 96)
		assert_almost(img.get_pixel(1, 1).a, 0.0, 0.01, "%s: transparent corner" % k)
		assert_true(img.get_pixel(48, 40).a > 0.95, "%s: solid bubble centre" % k)
	for k in ["heart", "star", "sparkle", "z", "note"]:
		var img2 := (Icons.icon(k) as Texture2D).get_image()
		assert_true(img2.get_pixel(48, 48).a > 0.5 or img2.get_pixel(48, 52).a > 0.5, "%s icon has a body" % k)
	assert_eq(Icons.bubble("nonsense"), Icons.bubble("dots"), "unknown kinds fall back")
	assert_true(Icons.bubble("heart") == Icons.bubble("heart"), "cached")


func test_every_voice_cue_maps_to_a_real_sound_name() -> void:
	# ARCHITECTURE.md audio names for the companions (the Audio module generates exactly these).
	var names := ["mochi_chirp", "mochi_happy", "mochi_scared", "pebble_clack", "pebble_happy", "pebble_grunt",
		"lumi_chime", "lumi_happy", "lumi_warn"]
	var C: Script = load("res://src/companions/companion.gd")
	var vm: Dictionary = C.get_script_constant_map()["VOICE_MAP"]
	for id in ["mochi", "pebble", "lumi"]:
		var voice := String(ItemDB.creature(id).get("voice", id))
		for cue in ["chirp", "happy", "scared", "warn", "grunt", "clack", "chime"]:
			var full := "%s_%s" % [voice, String(vm[id].get(cue, cue))]
			assert_true(names.has(full), "%s cue '%s' -> %s exists" % [id, cue, full])
