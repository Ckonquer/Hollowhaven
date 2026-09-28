extends "res://tests/unit/test_core_base.gd"
## Optional goals (src/core/optional_log.gd + data/optional_goals.gd; MP §7, §15, §2.4): the goal ids,
## well-formed data, visibility gating, latching with rewards through the ledger exactly once, the legacy
## free_play carry-over (silent) and persistence of unknown records.

const OptionalLog := preload("res://src/core/optional_log.gd")
const ChapterLog := preload("res://src/core/chapter_log.gd")
const Data := preload("res://data/optional_goals.gd")
const IDS := ["opt_look_of_your_own", "opt_brave_little_steps", "opt_copper_courage", "opt_tailors_cache",
	"opt_bramblewatch", "opt_gardeners_afternoon", "opt_tobins_shift", "opt_upstairs", "opt_pumpkin_face",
	"opt_counts_wardrobe", "opt_groundskeeper", "opt_hat_too_large", "opt_long_way_home", "opt_harvest_table",
	"opt_room_for_friends", "opt_miner_came_back", "opt_legacy_bond", "opt_legacy_heartbloom"]
const TYPES := ["flag", "flags_all", "item", "item_any", "placed", "placed_any", "befriended", "counter",
	"discovered", "equipped", "companion_home_spot"]

var opt: RefCounted


func setup() -> void:
	fresh_state()
	GameState.active = false
	opt = GameState.optional_goals


func _ids(goals: Array) -> Array:
	var out: Array = []
	for g in goals:
		out.append(g["id"])
	return out


func _held(id: String) -> int:
	var n := GameState.count_item(id)
	for o in GameState.orphans:
		if o["stack"]["id"] == id:
			n += int(o["stack"]["count"])
	return n


func test_goal_ids_and_data_are_well_formed() -> void:
	assert_eq(_ids(Data.GOALS), IDS)
	for g in Data.GOALS:
		var id := String(g["id"])
		assert_true(id.begins_with("opt_"), id)
		assert_ne(String(g.get("title", "")), "", id + " title")
		assert_ne(String(g.get("text", "")), "", id + " text")
		assert_true(int(g.get("chapter", 0)) in [1, 2], id + " chapter")
		assert_true(g.get("visible_if") is Array, id + " visible_if")
		assert_true((g.get("objectives", []) as Array).size() > 0, id + " objectives")
		for o in g["objectives"] + g["visible_if"]:
			assert_true(TYPES.has(String(o.get("type", ""))), "%s: objective type %s" % [id, str(o.get("type"))])
			if String(o["type"]).begins_with("flag"):
				for f in (o.get("flags", [o.get("flag", "")]) as Array):
					var fs := String(f)
					assert_true(fs.begins_with("c1x_") or fs.begins_with("ch2_") or fs.begins_with("ta_") or fs in
						["ruin_cleared", "mine_opened", "chapter_one_complete"], "%s: namespaced flag %s" % [id, fs])
		assert_true(g.get("reward") is Dictionary, id + " reward")
		for k in g["reward"]:
			assert_true(k in ["give", "flags", "patterns", "message"], "%s reward key %s" % [id, k])


## Rewards are real items/patterns; a bundle with the same id in data/sources.gd REWARDS (the data module's
## obtainability model) grants exactly the same; and a goal never repeats an item kind that the content bundle
## setting one of its own objective flags already gives (no second miner lamp for one activity).
func test_rewards_match_the_catalogue_and_never_repeat_a_content_bundle() -> void:
	var bundles: Dictionary = {}
	if ResourceLoader.exists("res://data/sources.gd"):
		var sc: Script = load("res://data/sources.gd")
		bundles = sc.get_script_constant_map().get("REWARDS", {})
	var patterns: Dictionary = {}
	if ResourceLoader.exists("res://data/appearance.gd"):
		var ac: Script = load("res://data/appearance.gd")
		patterns = ac.get_script_constant_map().get("PATTERNS", {})
	for g in Data.GOALS:
		var rid := "rw_" + String(g["id"])
		var rw: Dictionary = g["reward"]
		var give: Dictionary = rw.get("give", {})
		for id in give:
			assert_true(ItemDB.has_item(String(id)), "%s gives a known item '%s'" % [rid, id])
		for p in rw.get("patterns", []):
			if not patterns.is_empty():
				assert_true(patterns.has(p), "%s grants a known pattern '%s'" % [rid, p])
		var own: Dictionary = bundles.get(rid, {})
		if not own.is_empty():
			assert_deep_eq(json_norm(give), json_norm(own.get("items", {})), rid + " items match data/sources.gd REWARDS")
			var f1: Array = (rw.get("flags", []) as Array).duplicate()
			var f2: Array = (own.get("flags", []) as Array).duplicate()
			f1.sort()
			f2.sort()
			assert_eq(f1, f2, rid + " flags match data/sources.gd REWARDS")
			assert_eq(rw.get("patterns", []), own.get("patterns", []), rid + " patterns match data/sources.gd REWARDS")
		var objective_flags: Array = []
		for o in g["objectives"]:
			if o.has("flag"):
				objective_flags.append(String(o["flag"]))
			for f in o.get("flags", []):
				objective_flags.append(String(f))
		for bid in bundles:
			if bid == rid:
				continue
			var b: Dictionary = bundles[bid]
			var same_activity := false
			for f in b.get("flags", []):
				same_activity = same_activity or objective_flags.has(String(f))
			if not same_activity:
				continue
			for id in give:
				assert_false((b.get("items", {}) as Dictionary).has(id),
					"%s gives '%s' again: %s already gives it for the same activity" % [rid, id, bid])
	for bid in bundles:
		if String(bundles[bid].get("by", "")) == "optional_log":
			assert_false(opt.goal(String(bid).trim_prefix("rw_")).is_empty(), "%s: data/sources.gd names a goal that exists" % bid)


func test_a_hat_too_large_grants_its_pattern_exactly_once() -> void:
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")
	GameState.set_flag("ch2_witch_hat_found")
	opt.evaluate()
	assert_true(opt.is_done("opt_hat_too_large"))
	assert_eq((GameState.wardrobe["owned"] as Array).count("pat_witch_hat"), 1, "the pattern is owned")
	GameState.from_dict(json_norm(GameState.to_dict()))
	GameState.optional_goals.records.erase("opt_hat_too_large")   # even a lost record never grants it twice
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_hat_too_large"))
	assert_eq((GameState.wardrobe["owned"] as Array).count("pat_witch_hat"), 1)


func test_visibility_gates_chapter_two_goals() -> void:
	GameState.set_flag("ch2_witch_hat_found")
	assert_false(_ids(opt.visible_goals()).has("opt_hat_too_large"))
	opt.evaluate()
	assert_false(opt.is_done("opt_hat_too_large"), "hidden goals do not latch")
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")
	assert_true(_ids(opt.visible_goals()).has("opt_hat_too_large"))
	assert_true(opt.has_pending_completion())
	opt.evaluate()
	assert_true(opt.is_done("opt_hat_too_large"), "latches as soon as it is visible")
	assert_true(_ids(opt.visible_goals()).has("opt_look_of_your_own"), "Chapter One goals are always listed")
	assert_false(_ids(opt.pending_goals()).has("opt_hat_too_large"))


func test_goal_latches_and_rewards_once() -> void:
	var done := record(Events.optional_goal_completed, 1)
	var notes := record(Events.notify, 2)
	GameState.set_flag("ruin_cleared")
	GameState.set_flag("c1x_bramblewatch_found")
	opt.evaluate()
	assert_false(opt.is_done("opt_bramblewatch"))
	assert_eq(opt.objective_status(opt.goal("opt_bramblewatch")).map(func(s): return s["done"]), [true, false])
	GameState.set_flag("c1x_elder_defeated")
	GameState.total_minutes = 2222.0
	opt.evaluate()
	assert_true(opt.is_done("opt_bramblewatch"))
	assert_eq(opt.records["opt_bramblewatch"], {"done": true, "done_at": 2222.0})
	assert_eq(done, [["opt_bramblewatch"]])
	assert_true(notes.has(["Optional goal complete: Bramblewatch", "quest"]))
	assert_true(GameState.has_reward("rw_opt_bramblewatch"))
	assert_eq(_held("resin"), 0, "resin comes from the Elder's own bundle (rw_c1x_elder), not twice")
	assert_eq(_held("sturdy_planter"), 1)
	opt.evaluate()
	assert_eq(done.size(), 1, "never twice")
	opt.records.erase("opt_bramblewatch")   # a save that lost the record: completes again, rewards do not repeat
	opt.evaluate()
	assert_eq(_held("sturdy_planter"), 1)
	assert_eq(opt.done_count(), 1)


func test_done_goals_stay_done_and_reward_flags_are_set() -> void:
	var uid := GameState.add_structure("heartbloom_lamp", Vector3.ZERO, 0.0)
	opt.evaluate()
	assert_true(opt.is_done("opt_legacy_heartbloom"))
	GameState.remove_structure(uid)
	opt.evaluate()
	assert_true(opt.is_done("opt_legacy_heartbloom"), "latched")
	assert_eq(opt.objective_status(opt.goal("opt_legacy_heartbloom"))[0]["done"], true, "a done goal reports done")
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")
	GameState.set_counter_max("ch2_seasonal_dishes", 2)
	GameState.set_flag("ch2_table_decorated")
	opt.evaluate()
	assert_true(opt.is_done("opt_harvest_table"))
	assert_true(GameState.get_flag("ch2_harvest_table"), "reward flag (recipe unlock) set")


func test_legacy_free_play_completion_marks_both_goals_silently_on_load() -> void:
	var done := record(Events.optional_goal_completed, 1)
	var notes := record(Events.notify, 2)
	var d := GameState.to_dict()
	d["quests"] = {"index": 16, "completed": [], "baselines": {}}
	GameState.from_dict(json_norm(d))
	assert_true(GameState.optional_goals.is_done("opt_legacy_bond"))
	assert_true(GameState.optional_goals.is_done("opt_legacy_heartbloom"))
	assert_eq(done, [])
	assert_eq(notes, [])
	assert_eq(GameState.ledger, {}, "no rewards for the carry-over")
	d["quests"] = {"index": 15, "completed": [], "baselines": {}}
	GameState.from_dict(json_norm(d))
	assert_false(GameState.optional_goals.is_done("opt_legacy_bond"), "free_play still pending: nothing pre-marked")


func test_legacy_goals_latch_normally_during_play() -> void:
	GameState.add_bond("mochi", 100)
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_legacy_bond"))
	assert_false(GameState.optional_goals.is_done("opt_legacy_heartbloom"))


func test_records_round_trip_and_unknown_goals_are_kept() -> void:
	var log: RefCounted = OptionalLog.new()
	log.from_dict(json_norm({"opt_bramblewatch": {"done": true, "done_at": 5}, "opt_from_the_future": {"done": 1, "done_at": "x", "extra": [1]},
		"bad": 7, "opt_open": {"done": false}}))
	assert_eq(log.records, {"opt_bramblewatch": {"done": true, "done_at": 5.0},
		"opt_from_the_future": {"done": true, "done_at": 0.0, "extra": [1.0]}, "opt_open": {"done": false, "done_at": 0.0}})
	assert_true(log.is_done("opt_bramblewatch"))
	assert_false(log.is_done("opt_open"))
	assert_eq(log.to_dict(), log.records)
	GameState.optional_goals.records = log.records.duplicate(true)
	GameState.from_dict(json_norm(GameState.to_dict()))
	assert_true(GameState.optional_goals.records.has("opt_from_the_future"))


## "A House With an Upstairs" needs stairs that really lead up and Krystal walking up them (c1x_upstairs_reachable,
## set by build_ops.check_upstairs_walk, COV-005), not just a staircase and a floor piece somewhere; a latched goal
## stays done.
func test_upstairs_needs_a_reachable_upper_floor() -> void:
	GameState.add_structure("workbench", Vector3(9, 0, 9), 0.0)
	var g: Dictionary = opt.goal("opt_upstairs")
	var flags: Array = []
	for o in g["objectives"]:
		if String(o["type"]) == "flag":
			flags.append(String(o["flag"]))
	assert_eq(flags, ["c1x_upstairs_reachable"], "the reachability objective")
	GameState.add_structure("wood_stairs", Vector3(0, 0, 4), 0.0)
	GameState.add_structure("upper_floor", Vector3(20, 3, 20), 0.0)   # a floor piece nowhere near the stairs
	opt.evaluate()
	assert_false(opt.is_done("opt_upstairs"), "stairs and a floor that do not meet are not an upstairs")
	assert_eq(opt.objective_status(g).map(func(s): return s["done"]), [true, true, false])
	GameState.set_flag("c1x_upstairs_reachable")
	opt.evaluate()
	assert_true(opt.is_done("opt_upstairs"))
	assert_eq(_held("wood_railing"), 4, "its railings, once")
	# Latched: taking the building apart later never un-completes it or pays again.
	GameState.flags.erase("c1x_upstairs_reachable")
	for uid in GameState.structures.keys():
		GameState.remove_structure(String(uid))
	opt.evaluate()
	assert_true(opt.is_done("opt_upstairs"), "latched")
	GameState.from_dict(json_norm(GameState.to_dict()))
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_upstairs"), "latched across a reload")
	assert_eq(_held("wood_railing"), 4)


func test_room_for_friends_uses_companion_home_spots() -> void:
	GameState.set_flag("chapter_one_complete")
	var g: Dictionary = opt.goal("opt_room_for_friends")
	assert_true(opt.is_visible(g))
	GameState.companion("pebble")["home_spot"] = [2.0, 0.0, 2.0]
	assert_eq(opt.objective_status(g)[0]["done"], true)
	assert_eq(opt.objective_status(g)[1]["done"], false)
