extends "res://tests/test_case.gd"
## Lanternwake Expeditions (module D2) rules without a world: seeded plans are deterministic and vary, the
## board shows difficulty and reward types before starting, locked routes are refused, start / progress /
## complete / abandon, the rewards come once per run (not twice, not after a reload), keepsakes, one run at a
## time, save / load mid-run through the real SaveSystem (GameState.extra), damaged state repair, the tracker /
## map views (read-only: they never create the saved section) - and expeditions never write a flag, never touch the
## reward ledger or the quest layers. A route's first completion gives Wayfinding mastery xp once (P39); a dye
## keepsake reads as "a new dye colour", never a recipe (P42).

const Ex := preload("res://src/expeditions/expeditions.gd")
const Data := preload("res://data/expeditions.gd")
const Mastery := preload("res://src/core/mastery.gd")

const UNLOCKS := ["ch2_orchard_restored", "ch2_quarry_restored", "ch2_manor_restored"]

var _was_listening := false


func before_each() -> void:
	fresh_state()
	_was_listening = Ex.is_listening()


func after_each() -> void:
	if not _was_listening:
		Ex.shutdown()


func _unlock_all() -> void:
	for f in UNLOCKS:
		GameState.flags[f] = true


## Defeats every enemy of the current stop through the public rule (as the runner's enemies would).
func _clear_stop() -> void:
	var a := Ex.active()
	var s: Dictionary = Ex.current_plan()["stops"][int(a["stop"])]
	var t := String(a["template"])
	var run := int(a["run"])
	var stop := int(a["stop"])
	for e in s["enemies"]:
		assert_true(Ex.record_defeat(t, run, stop, String(e)), "defeat counts")


func _counts(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = GameState.count_item(String(id))
	return out


# --- Plans and seeds -----------------------------------------------------------------------------------------------

func test_seeded_plans_are_deterministic() -> void:
	for id in Data.ORDER:
		var a := str(Ex.plan(id, 1234))
		Ex.plan(Data.ORDER[0] if id != Data.ORDER[0] else Data.ORDER[1], 77)   # evict the one-entry cache
		var b := str(Ex.plan(id, 1234))
		assert_eq(a, b, "%s: same seed, same plan" % id)
		var p := Ex.plan(id, 1234)
		var t: Dictionary = Data.TEMPLATES[id]
		assert_eq((p["stops"] as Array).size(), (t["stops"] as Array).size())
		for i in (p["stops"] as Array).size():
			var ps: Dictionary = p["stops"][i]
			var ts: Dictionary = t["stops"][i]
			assert_eq(String(ps["id"]), String(ts["id"]), "stops keep their authored order")
			assert_true((ts["groups"] as Array).has(ps["group"]), "the group is one of the authored ones")
			var n := 0
			for pair in ps["group"]:
				n += int(pair[1])
			assert_eq(int(ps["needed"]), n)
			assert_eq((ps["enemies"] as Array).size(), n)
			var sorted_a: Array = (ps["points"] as Array).duplicate()
			var sorted_b: Array = (ts["points"] as Array).duplicate()
			sorted_a.sort()
			sorted_b.sort()
			assert_eq(sorted_a, sorted_b, "the seed only reorders the authored points")
		var rw: Dictionary = t["rewards"]
		for item in rw["base"]:
			var r: Array = rw["base"][item]
			assert_true(int(p["rewards"].get(item, 0)) >= int(r[0]) and int(p["rewards"].get(item, 0)) <= int(r[1]), "%s base %s in range" % [id, item])
		assert_eq((p["rewards"] as Dictionary).size(), (rw["base"] as Dictionary).size() + int(rw["picks"]["count"]), "base + picks")


func test_seeds_vary_groups_and_rewards() -> void:
	for id in Data.ORDER:
		var groups := {}
		var rewards := {}
		for sd in range(1, 41):
			var p := Ex.plan(id, sd)
			var gs: Array = []
			for s in p["stops"]:
				gs.append(str(s["group"]))
			groups[str(gs)] = true
			rewards[str(p["rewards"])] = true
		assert_true(groups.size() >= 4, "%s: seeds pick different groups (%d kinds)" % [id, groups.size()])
		assert_true(rewards.size() >= 4, "%s: seeds vary the rewards (%d kinds)" % [id, rewards.size()])
	var r := Ex.roll_seed()
	assert_true(r >= 1 and r <= Data.SEED_MAX, "a small seed")


func test_preview_shows_difficulty_and_reward_types_not_the_roll() -> void:
	_unlock_all()
	var pv := Ex.preview("quarry_circuit")
	assert_eq(String(pv["name"]), "Quarry Circuit")
	assert_eq(String(pv["difficulty_name"]), "Brisk")
	assert_eq(int(pv["pips"]), 2)
	assert_true(String(pv["difficulty_text"]) != "")
	assert_eq((pv["stops"] as Array).size(), 4)
	assert_true((pv["reward_types"] as Array).size() >= 2)
	assert_true((pv["enemies"] as Array).has("Bellcap Sentry"), "display names of who may be met")
	assert_false(pv.has("rewards"), "the exact roll is never shown before starting")
	assert_true(bool(pv["unlocked"]))
	assert_eq(Ex.preview("nope"), {})


func test_locked_routes_are_refused_and_reads_flags_only() -> void:
	for id in Data.ORDER:
		assert_false(Ex.is_unlocked(id), "%s closed on a fresh save" % id)
		assert_true(Ex.lock_reason(id) != "")
		assert_false(Ex.start(id), "%s refused while closed" % id)
	assert_false(Ex.is_active())
	GameState.flags["ch2_orchard_restored"] = true
	assert_true(Ex.is_unlocked("orchard_patrol"))
	assert_false(Ex.is_unlocked("manor_afterglow"))
	assert_false(Ex.start("not_a_route"))


# --- Runs ----------------------------------------------------------------------------------------------------------

func test_start_progress_and_complete_pay_the_run_once() -> void:
	_unlock_all()
	GameState.total_minutes = 5000.0
	assert_true(Ex.start("orchard_patrol", 42))
	var a := Ex.active()
	assert_eq(String(a["template"]), "orchard_patrol")
	assert_eq(int(a["seed"]), 42)
	assert_eq(int(a["stop"]), 0)
	assert_almost(float(a["started_at"]), 5000.0)
	assert_eq(int(a["run"]), 1)
	assert_false(Ex.start("quarry_circuit"), "one expedition at a time")
	# Only this run's current stop counts.
	assert_false(Ex.record_defeat("quarry_circuit", 1, 0, "brambling"))
	assert_false(Ex.record_defeat("orchard_patrol", 2, 0, "brambling"))
	assert_false(Ex.record_defeat("orchard_patrol", 1, 1, "brambling"))
	assert_eq(int(Ex.active()["defeated"]), 0)
	var p := Ex.plan("orchard_patrol", 42)
	var n := (p["stops"] as Array).size()
	for i in n:
		assert_eq(Ex.current_stop_index(), i)
		assert_false(Ex.in_cache_phase())
		assert_eq(Ex.complete(), {}, "no reward before the route is walked")
		_clear_stop()
	assert_true(Ex.in_cache_phase(), "every stop quiet: the cache waits")
	assert_eq(String(Ex.current_target()["kind"]), "cache")
	var before := _counts((p["rewards"] as Dictionary).keys())
	var r := Ex.complete()
	assert_false(r.is_empty())
	for item in p["rewards"]:
		assert_eq(GameState.count_item(String(item)), int(before[item]) + int(p["rewards"][item]), "got %s" % item)
	assert_eq(r["items"], p["rewards"])
	assert_false(Ex.is_active(), "the run ended")
	assert_eq(Ex.completions("orchard_patrol"), 1)
	assert_eq(String(Ex.last_result()["template"]), "orchard_patrol")
	# Never twice.
	var after := _counts((p["rewards"] as Dictionary).keys())
	assert_eq(Ex.complete(), {})
	assert_eq(_counts((p["rewards"] as Dictionary).keys()), after, "a second opening gives nothing")
	# ...and a fresh run is a fresh run (its own reward).
	assert_true(Ex.start("orchard_patrol", 42))
	assert_eq(int(Ex.active()["run"]), 2)


func test_rewards_once_even_across_a_save_and_reload() -> void:
	_unlock_all()
	assert_true(Ex.start("manor_afterglow", 9))
	for i in Ex.stop_count("manor_afterglow"):
		_clear_stop()
	var p := Ex.plan("manor_afterglow", 9)
	assert_false(Ex.complete().is_empty())
	var got := _counts((p["rewards"] as Dictionary).keys())
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_false(Ex.is_active(), "the finished run stays finished")
	assert_eq(Ex.complete(), {})
	assert_eq(_counts((p["rewards"] as Dictionary).keys()), got)
	assert_eq(Ex.completions("manor_afterglow"), 1, "completion counts survive a reload")


func test_abandoning_is_free_and_a_new_run_can_start() -> void:
	_unlock_all()
	GameState.give_item("candy", 2)
	assert_true(Ex.start("quarry_circuit", 5))
	_clear_stop()
	var inv := str(GameState.inventory.to_array())
	var hp := float(GameState.player["hp"])
	assert_true(Ex.abandon())
	assert_false(Ex.is_active())
	assert_eq(str(GameState.inventory.to_array()), inv, "nothing is taken")
	assert_almost(float(GameState.player["hp"]), hp)
	assert_eq(int(Ex.state()["abandoned"]), 1)
	assert_eq(Ex.completions("quarry_circuit"), 0)
	assert_false(Ex.abandon(), "nothing left to set aside")
	assert_true(Ex.start("orchard_patrol"))


func test_save_and_load_mid_run_resume_at_the_current_stop() -> void:
	_unlock_all()
	assert_true(Ex.start("quarry_circuit", 321))
	_clear_stop()
	var s: Dictionary = Ex.current_plan()["stops"][1]
	var first := String(s["enemies"][0])
	assert_true(Ex.record_defeat("quarry_circuit", 1, 1, first))
	var want := Ex.active().duplicate(true)
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_false(Ex.is_active(), "reset forgets the run")
	assert_true(SaveSystem.load_game())
	var a := Ex.active()
	assert_eq(String(a["template"]), "quarry_circuit")
	for k in ["seed", "stop", "defeated", "run"]:
		assert_true(a[k] is int, "%s is an int again after JSON" % k)
		assert_eq(int(a[k]), int(want[k]), k)
	assert_almost(float(a["started_at"]), float(want["started_at"]))
	assert_eq(int((a["down"] as Dictionary)[first]), 1, "which ones are down survives")
	assert_eq(Ex.current_stop_index(), 1)
	assert_eq(str(Ex.current_plan()), str(Ex.plan("quarry_circuit", 321)), "the same seed, the same route")
	# Carry on to the end after the reload.
	var needed := int(s["needed"])
	for i in needed - 1:
		assert_true(Ex.record_defeat("quarry_circuit", 1, 1, String(s["enemies"][i + 1])))
	assert_eq(Ex.current_stop_index(), 2)


func test_damaged_or_unknown_runs_are_repaired_never_a_crash() -> void:
	_unlock_all()
	GameState.extra[Data.STATE_KEY] = {"active": {"template": "future_route", "seed": 3.0, "stop": 0.0, "defeated": 0.0, "run": 1.0}}
	assert_false(Ex.is_active(), "an unknown route is dropped")
	GameState.extra[Data.STATE_KEY] = {"active": {"template": "orchard_patrol", "seed": 3.0, "stop": 9.0}}
	assert_false(Ex.is_active(), "an out-of-range stop is dropped")
	GameState.extra[Data.STATE_KEY] = "junk"
	assert_false(Ex.is_active())
	assert_eq(int(Ex.state()["runs"]), 0)
	var needed := int(Ex.plan("orchard_patrol", 3)["stops"][0]["needed"])
	GameState.extra[Data.STATE_KEY] = {"runs": 2.0, "completed": {"orchard_patrol": 1.0},
		"active": {"template": "orchard_patrol", "seed": 3.0, "stop": 0.0, "defeated": float(needed), "run": 2.0, "down": {"x": "y"}}}
	assert_true(Ex.is_active())
	assert_eq(Ex.current_stop_index(), 1, "a count covering the whole group finishes that stop")
	assert_eq(int(Ex.active()["defeated"]), 0)
	assert_eq(Ex.completions("orchard_patrol"), 1)
	assert_eq(int(Ex.state()["runs"]), 2)


func test_keepsakes_first_time_always_then_occasional_dyes_before_decor() -> void:
	_unlock_all()
	var rw: Dictionary = Data.TEMPLATES["orchard_patrol"]["rewards"]
	var chance := float(rw["keepsake_chance"])
	var k1 := Ex.keepsake_for("orchard_patrol", {"keepsake_roll": 0.99, "keepsake_pick": 0}, true)
	assert_eq(String(k1["kind"]), "dye", "a route's first completion always brings a keepsake, a dye first")
	assert_eq(Ex.keepsake_for("orchard_patrol", {"keepsake_roll": minf(chance + 0.01, 0.999), "keepsake_pick": 0}, false), {}, "usually none")
	var k2 := Ex.keepsake_for("orchard_patrol", {"keepsake_roll": chance * 0.5, "keepsake_pick": 1}, false)
	assert_eq(String(k2["kind"]), "dye")
	GameState.wardrobe["palettes"] = ["pumpkin", "rose"]
	var k3 := Ex.keepsake_for("orchard_patrol", {"keepsake_roll": 0.0, "keepsake_pick": 0}, false)
	assert_eq(String(k3["kind"]), "decor", "every dye owned: a decoration instead")
	# Completing pays the dye as a Loom palette (not a flag).
	GameState.wardrobe["palettes"] = []
	assert_true(Ex.start("orchard_patrol", 11))
	for i in Ex.stop_count("orchard_patrol"):
		_clear_stop()
	var r := Ex.complete()
	var k: Dictionary = r["keepsake"]
	assert_eq(String(k["kind"]), "dye", "first completion")
	assert_true((GameState.wardrobe["palettes"] as Array).has(String(k["id"])), "the dye recipe is now hers")


func test_expeditions_never_write_flags_or_touch_the_quest_layers() -> void:
	_unlock_all()
	GameState.flags["ch2_accepted"] = true
	GameState.flags["chapter_one_complete"] = true
	var flags_before := GameState.flags.duplicate(true)
	var ledger_before := GameState.ledger.duplicate(true)
	var ch2_before := str(GameState.chapter2.to_dict())
	var opt_before := str(GameState.optional_goals.to_dict())
	var quests_before := str(GameState.quests.to_dict())
	var seen: Array = []
	var rec := func(f: String, _v: Variant) -> void: seen.append(f)
	Events.flag_set.connect(rec)
	assert_true(Ex.start("manor_afterglow", 77))
	for i in Ex.stop_count("manor_afterglow"):
		_clear_stop()
	assert_false(Ex.complete().is_empty())
	assert_true(Ex.start("orchard_patrol", 78))
	_clear_stop()
	assert_true(Ex.abandon())
	Events.flag_set.disconnect(rec)
	assert_eq(seen, [], "no flag was set")
	assert_eq(GameState.flags, flags_before, "flags unchanged")
	assert_eq(GameState.ledger, ledger_before, "the reward ledger is untouched")
	assert_eq(str(GameState.chapter2.to_dict()), ch2_before, "the Chapter Two layer is untouched")
	assert_eq(str(GameState.optional_goals.to_dict()), opt_before)
	assert_eq(str(GameState.quests.to_dict()), quests_before, "the Chapter One quest log is untouched")
	for k in GameState.to_dict():
		assert_false(String(k).begins_with("exp") and String(k) != Data.STATE_KEY, "only the documented state key")


# --- Views ---------------------------------------------------------------------------------------------------------

func test_tracker_map_and_summary_views() -> void:
	_unlock_all()
	assert_eq(Ex.tracker_view(), {})
	assert_eq(Ex.map_marks(Data.AREA_ID), [])
	assert_eq(Ex.summary_line(), "")
	assert_true(Ex.start("orchard_patrol", 3))
	var v := Ex.tracker_view()
	assert_eq(String(v["kind"]), "expedition")
	assert_eq(String(v["title"]), "Orchard Patrol")
	assert_true(bool(v["optional"]), "an optional card, never a chapter step")
	assert_eq((v["rows"] as Array).size(), Ex.stop_count("orchard_patrol") + 1, "every stop + the cache")
	assert_eq(String(v["current"]), "exp_op_meadow")
	assert_true(String(v["where"]).contains("Scarecrow Meadow"))
	assert_eq(String(v["group"]), "", "not a group card: the journal lists its rows")
	var tg: Array = v["targets"]
	assert_eq(tg.size(), 1, "only the current place is a target (one pulse, one head-to line)")
	assert_eq(String(tg[0]["id"]), "exp_op_meadow")
	assert_eq(String(tg[0]["area"]), Data.AREA_ID)
	assert_false(bool(tg[0]["done"]))
	var marks := Ex.map_marks(Data.AREA_ID)
	assert_eq(marks.size(), 4)
	assert_true(bool(marks[0]["current"]))
	assert_eq(int(marks[0]["n"]), 1)
	assert_eq(String(marks[3]["kind"]), "cache")
	assert_false(bool(marks[3]["current"]))
	assert_eq(Ex.map_marks("surface"), [], "pins only on the Reach map")
	assert_eq(Ex.place_disc("exp_op_hedgerow")["pos"], Data.TEMPLATES["orchard_patrol"]["stops"][1]["pos"])
	assert_eq(Ex.place_disc("hr_orchard"), {})
	assert_true(Ex.summary_line().contains("stop 1 of 3"))
	_clear_stop()
	assert_true(bool(Ex.tracker_view()["rows"][0]["done"]))
	assert_eq(String(Ex.current_target()["id"]), "exp_op_hedgerow")
	assert_eq(String(Ex.tracker_view()["targets"][0]["id"]), "exp_op_hedgerow", "the target moves on")
	var m2 := Ex.map_marks(Data.AREA_ID)
	assert_true(bool(m2[0]["done"]) and not bool(m2[0]["current"]))
	assert_true(bool(m2[1]["current"]))
	for i in Ex.stop_count("orchard_patrol") - 1:
		_clear_stop()
	var m3 := Ex.map_marks(Data.AREA_ID)
	assert_true(bool(m3[3]["current"]), "the cache is current once every stop is quiet")
	assert_eq(String(Ex.tracker_view()["targets"][0]["id"]), "exp_op_cache")
	assert_eq(Ex.place_disc("exp_op_cache")["pos"], Data.TEMPLATES["orchard_patrol"]["cache"]["pos"])
	assert_true(Ex.abandon())
	assert_eq(Ex.map_marks(Data.AREA_ID), [], "nothing once the run is set aside")
	assert_eq(Ex.place_disc("exp_op_meadow"), {})


## The HUD polls these views every second from New Game on: without a saved run they answer "none" WITHOUT adding
## an "expeditions" section to a save that never used the board.
func test_views_are_read_only_without_a_run() -> void:
	GameState.extra.erase(Data.STATE_KEY)
	assert_false(Ex.is_active())
	assert_eq(Ex.current_plan(), {})
	assert_eq(Ex.current_target(), {})
	assert_eq(Ex.tracker_view(), {})
	assert_eq(Ex.map_marks(Data.AREA_ID), [])
	assert_eq(Ex.place_disc("exp_op_meadow"), {})
	assert_eq(Ex.summary_line(), "")
	assert_false(GameState.extra.has(Data.STATE_KEY), "polling the views never creates the saved section")
	# a saved run with JSON floats is normalised by the first read, never a crash
	GameState.extra[Data.STATE_KEY] = {"active": {"template": "orchard_patrol", "seed": 3.0, "stop": 0.0, "defeated": 0.0, "run": 1.0, "down": {}}}
	assert_true(Ex.is_active())
	assert_eq(String(Ex.current_target()["id"]), "exp_op_meadow")


# --- Mastery (P39) and keepsake words (P42) ------------------------------------------------------------------------

func _walk(template_id: String, seed_value: int) -> Dictionary:
	assert_true(Ex.start(template_id, seed_value))
	for i in Ex.stop_count(template_id):
		_clear_stop()
	return Ex.complete()


## MP 5.3: masteries grow with ordinary play. A route's FIRST completion gives Wayfinding xp once (deduped per route
## through Mastery's first-time kinds, so a second run or a reload never repeats it); nothing else changes.
func test_first_completion_of_a_route_gives_wayfinding_xp_once() -> void:
	_unlock_all()
	var xp0 := Mastery.xp("wayfinding")
	var g0 := Mastery.xp("gathering")
	var h0 := Mastery.xp("hearthcraft")
	assert_false(_walk("orchard_patrol", 21).is_empty())
	assert_eq(Mastery.xp("wayfinding"), xp0 + Data.FIRST_ROUTE_WAYFINDING_XP, "first completion of the route")
	assert_true(Mastery.has_seen("wayfinding", "expedition:orchard_patrol"), "remembered per route")
	assert_eq(Mastery.xp("gathering"), g0, "only Wayfinding")
	assert_eq(Mastery.xp("hearthcraft"), h0)
	assert_false(_walk("orchard_patrol", 22).is_empty())
	assert_eq(Mastery.xp("wayfinding"), xp0 + Data.FIRST_ROUTE_WAYFINDING_XP, "a second run of the same route gives none")
	# ...not after a reload either
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_false(_walk("orchard_patrol", 23).is_empty())
	assert_eq(Mastery.xp("wayfinding"), xp0 + Data.FIRST_ROUTE_WAYFINDING_XP, "the dedupe survives a reload")
	# another route is another first
	assert_false(_walk("quarry_circuit", 24).is_empty())
	assert_eq(Mastery.xp("wayfinding"), xp0 + 2 * Data.FIRST_ROUTE_WAYFINDING_XP)
	# an abandoned run gives nothing
	assert_true(Ex.start("manor_afterglow", 25))
	_clear_stop()
	assert_true(Ex.abandon())
	assert_eq(Mastery.xp("wayfinding"), xp0 + 2 * Data.FIRST_ROUTE_WAYFINDING_XP)
	assert_false(Mastery.has_seen("wayfinding", "expedition:manor_afterglow"))


## The dye keepsake unlocks the Loom palette directly (a gift): every text says "a new dye colour", never a recipe.
func test_dye_keepsake_reads_as_a_new_dye_colour() -> void:
	_unlock_all()
	assert_eq(Ex.keepsake_text({"kind": "dye", "id": "pumpkin"}), "a new dye colour (Pumpkin)")
	assert_eq(Ex.keepsake_text({"kind": "dye", "id": "midnight"}), "a new dye colour (Midnight)")
	assert_eq(Ex.keepsake_text({"kind": "decor", "item": "pumpkin_lights", "count": 2}),
		"%s x2" % ItemDB.display_name("pumpkin_lights"))
	assert_eq(Ex.keepsake_text({}), "")
	for id in Data.ORDER:
		var said := false
		for r in Data.TEMPLATES[id]["reward_types"]:
			assert_false(String(r).to_lower().contains("recipe"), "%s: no recipe promise (%s)" % [id, r])
			said = said or String(r).contains("a new dye colour")
		assert_true(said, "%s names its dye keepsake as a new dye colour" % id)
		# the colours named are the route's own dye keepsakes
		for k in Data.TEMPLATES[id]["rewards"]["keepsakes"]:
			if String(k["kind"]) == "dye":
				var nm := String(ItemDB.dye_palette(String(k["id"]))["name"]).trim_suffix(" Dye")
				assert_true(str(Data.TEMPLATES[id]["reward_types"]).contains(nm), "%s names %s" % [id, nm])
	var toasts: Array = []
	var rec := func(t: String, _k: String) -> void: toasts.append(t)
	Events.notify.connect(rec)
	GameState.wardrobe["palettes"] = []
	var r := _walk("orchard_patrol", 11)
	Events.notify.disconnect(rec)
	assert_eq(String(r["keepsake"]["kind"]), "dye", "first completion: a dye")
	var done: Array = toasts.filter(func(t: String) -> bool: return t.begins_with("Expedition complete"))
	assert_eq(done.size(), 1)
	assert_true(String(done[0]).contains(Ex.keepsake_text(r["keepsake"])), "the toast names the new colour: %s" % done[0])
	assert_false(String(done[0]).to_lower().contains("recipe"))
	assert_true((GameState.wardrobe["palettes"] as Array).has(String(r["keepsake"]["id"])), "the palette is hers at once")


func test_the_reach_listener_wires_once() -> void:
	Ex.shutdown()
	assert_false(Ex.is_listening())
	var n0 := Events.area_loaded.get_connections().size()
	Ex.init()
	Ex.init()
	assert_true(Ex.is_listening())
	assert_eq(Events.area_loaded.get_connections().size(), n0 + 1, "connected exactly once")
	Ex.shutdown()
	assert_eq(Events.area_loaded.get_connections().size(), n0)
	assert_false(Ex.is_listening())
	if _was_listening:
		Ex.init()
