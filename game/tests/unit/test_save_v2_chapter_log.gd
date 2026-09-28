extends "res://tests/unit/test_core_base.gd"
## Chapter Two quest layer (src/core/chapter_log.gd + data/quests_ch2.gd; MP §11, spec §7-8): the 20 stable
## step ids, activation only after chapter_one_complete AND ch2_accepted, the lamp group shown together and
## done in any order, latching of objectives met early, rewards through the ledger exactly once, skips that
## prevent stalls, the final completion event, arachnophobia text and persistence by id.

const ChapterLog := preload("res://src/core/chapter_log.gd")
const Data := preload("res://data/quests_ch2.gd")
const MP_IDS := ["ch2_light_beyond", "ch2_waygate", "ch2_commons", "ch2_outer_lamps", "ch2_orchard", "ch2_quarry",
	"ch2_manor", "ch2_prepare", "ch2_lamps_linked", "ch2_service_gate", "ch2_true_signal", "ch2_refuge", "ch2_miners",
	"ch2_three_lines", "ch2_weaver_crossing", "ch2_false_home", "ch2_choir", "ch2_routes_restored", "ch2_homecoming",
	"ch2_feast"]
## Flags that complete each step, in order (spec §7.4 + the module brief).
const STEP_FLAGS := {
	"ch2_light_beyond": ["ch2_accepted"], "ch2_waygate": ["ch2_waygate_repaired"],
	"ch2_commons": ["ch2_arch_commons", "ch2_read_festival_map"],
	"ch2_outer_lamps": ["ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp"],
	"ch2_orchard": ["ch2_garden_lamp_lit"], "ch2_quarry": ["ch2_quarry_lamp_lit"], "ch2_manor": ["ch2_manor_lamp_lit"],
	"ch2_prepare": ["ch2_read_preparations"], "ch2_lamps_linked": ["ch2_lamps_linked"],
	"ch2_service_gate": ["ch2_service_gate_open"], "ch2_true_signal": ["ch2_true_signal"],
	"ch2_refuge": ["ch2_refuge_reached", "ch2_refuge_shortcut"], "ch2_miners": ["ch2_refuge_record"],
	"ch2_three_lines": ["ch2_line_water", "ch2_line_bell", "ch2_line_light"],
	"ch2_weaver_crossing": ["ch2_crossing_cleared"], "ch2_false_home": ["ch2_false_home_revealed"],
	"ch2_choir": ["ch2_choir_defeated"], "ch2_routes_restored": ["ch2_returned_to_reach"],
	"ch2_homecoming": ["ch2_homecoming"], "ch2_feast": ["chapter_two_complete"]}

var log: RefCounted


func setup() -> void:
	fresh_state()
	GameState.active = false   # the tests drive evaluate() themselves
	log = GameState.chapter2


func _activate() -> void:
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")


func _ids(steps: Array) -> Array:
	var out: Array = []
	for s in steps:
		out.append(s["id"])
	return out


func _finish(step_id: String) -> void:
	for f in STEP_FLAGS[step_id]:
		GameState.set_flag(f)


## Reward-item total, whether the item is known (backpack/pouch) or not yet defined (orphans).
func _held(id: String) -> int:
	var n := GameState.count_item(id)
	for o in GameState.orphans:
		if o["stack"]["id"] == id:
			n += int(o["stack"]["count"])
	return n


# --- data ----------------------------------------------------------------------------------------------------

func test_twenty_steps_with_the_design_ids_in_order() -> void:
	assert_eq(_ids(Data.STEPS), MP_IDS)
	for s in Data.STEPS:
		assert_ne(String(s.get("title", "")), "", s["id"] + " title")
		assert_ne(String(s.get("text", "")), "", s["id"] + " text")
		assert_true((s.get("objectives", []) as Array).size() > 0, s["id"] + " objectives")
		# Same shape as data/quests.gd (the tracker/journal/map read String(step.target)) + the target's area.
		assert_true(s.get("target") is String, s["id"] + " target is a landmark id String")
		assert_true(String(s.get("target_area", "")) in ["surface", Data.REACH, Data.WORKS, Data.MANOR], s["id"] + " target_area")
		var flags_needed: Array = []
		for o in s["objectives"]:
			assert_eq(o["type"], "flag", s["id"] + " uses flag objectives")
			flags_needed.append(o["flag"])
		assert_eq(flags_needed, STEP_FLAGS[s["id"]], s["id"] + " flags")
	var grouped: Array = []
	for s in Data.STEPS:
		if String(s.get("group", "")) == "lamps":
			grouped.append(s["id"])
	assert_eq(grouped, ["ch2_orchard", "ch2_quarry", "ch2_manor"])
	assert_eq(Data.FINAL_STEP, "ch2_feast")
	# Hints are shown by the HUD hint card: every {token} must be one the UI knows how to fill in.
	var tokens: Array = preload("res://src/ui/ui_util.gd").TOKEN_ACTIONS.keys() + ["move"]
	var rx := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for s in Data.STEPS:
		for field in ["hint", "alt_hint"]:
			for m in rx.search_all(String(s.get(field, ""))):
				assert_true(tokens.has(m.get_string(1)), "%s %s token {%s}" % [s["id"], field, m.get_string(1)])


func test_targets_name_real_landmarks_and_zones() -> void:
	var surface: Dictionary = preload("res://data/world_layout.gd").LANDMARKS
	# spec §7.2: Works zone ids (the Works has no landmark table of its own).
	var works := ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge", "hw_lightwell",
		"hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]
	var reach: Dictionary = {}
	if ResourceLoader.exists("res://data/hallowmere_layout.gd"):
		var sc: Script = load("res://data/hallowmere_layout.gd")
		reach = sc.get_script_constant_map().get("LANDMARKS", {})
	for s in Data.STEPS:
		var t := String(s["target"])
		var where := "%s -> %s/%s" % [s["id"], s["target_area"], t]
		if t == "":
			continue
		match String(s["target_area"]):
			"surface":
				assert_true(surface.has(t), where + " is a data/world_layout.gd landmark")
			Data.REACH:
				assert_true(t.begins_with("hr_"), where + " uses the spec §7.2 Reach id")
				if not reach.is_empty():
					assert_true(reach.has(t), where + " is a data/hallowmere_layout.gd landmark")
			Data.WORKS:
				assert_true(works.has(t), where + " is a spec §7.2 Works zone")
			_:
				fail(where + ": unexpected area")


## Rewards are real items, and the data module's reward catalogue (data/sources.gd REWARDS, read by its
## obtainability tests) describes what really happens: an entry with the same id ("rw_" + step id) mirrors the
## step's items and flags exactly, and every entry it says the quest layer pays ("by": "chapter_log") names a
## real step. Game.complete_chapter_two() and this layer both grant rw_ch2_feast from this data.
func test_rewards_are_known_items_and_match_the_reward_catalogue() -> void:
	var bundles := _catalogue_rewards()
	for s in Data.STEPS:
		var rid := "rw_" + String(s["id"])
		var oc: Dictionary = s.get("on_complete", {})
		var give: Dictionary = oc.get("give", {})
		for id in give:
			assert_true(ItemDB.has_item(String(id)), "%s gives a known item '%s'" % [rid, id])
			assert_true(int(give[id]) > 0, rid + " positive count")
		assert_false(oc.has("patterns"), rid + ": step rewards grant no patterns directly (use a recipe unlock flag)")
		var b: Dictionary = bundles.get(rid, {})
		if b.is_empty():
			continue
		assert_deep_eq(json_norm(give), json_norm(b.get("items", {})), rid + " items match data/sources.gd REWARDS")
		var mine: Array = (oc.get("flags", []) as Array).duplicate()
		var theirs: Array = (b.get("flags", []) as Array).duplicate()
		mine.sort()
		theirs.sort()
		assert_eq(mine, theirs, rid + " flags match data/sources.gd REWARDS")
		assert_eq((b.get("patterns", []) as Array).size(), 0, rid + ": the catalogue expects no directly granted pattern")
	for bid in bundles:
		if String(bundles[bid].get("by", "")) == "chapter_log":
			assert_false(log.step_by_id(String(bid).trim_prefix("rw_")).is_empty(), "%s: data/sources.gd names a step that exists" % bid)


## data/sources.gd REWARDS ({} while the data module has not delivered it).
func _catalogue_rewards() -> Dictionary:
	if not ResourceLoader.exists("res://data/sources.gd"):
		return {}
	var sc: Script = load("res://data/sources.gd")
	var r: Variant = sc.get_script_constant_map().get("REWARDS", {})
	return r if r is Dictionary else {}


# --- activation ------------------------------------------------------------------------------------------------

func test_inactive_until_chapter_one_complete_and_accepted() -> void:
	assert_false(log.is_available())
	GameState.set_flag("ch2_accepted")
	assert_false(log.is_active(), "accepting alone is not enough")
	GameState.flags.erase("ch2_accepted")
	GameState.set_flag("chapter_one_complete")
	assert_true(log.is_available())
	assert_false(log.is_active())
	assert_eq(log.current_steps(), [])
	log.evaluate()
	assert_eq(log.done, [], "nothing happens before acceptance")
	GameState.set_flag("ch2_accepted")
	assert_true(log.is_active())
	assert_eq(_ids(log.current_steps()), ["ch2_light_beyond"])


func test_steps_progress_in_order_with_events() -> void:
	var started := record(Events.chapter2_step_started, 1)
	var completed := record(Events.chapter2_step_completed, 1)
	var notes := record(Events.notify, 2)
	_activate()
	log.evaluate()
	assert_eq(log.done, ["ch2_light_beyond"])
	assert_eq(_ids(log.current_steps()), ["ch2_waygate"])
	assert_eq(started, [["ch2_light_beyond"], ["ch2_waygate"]])
	assert_eq(completed, [["ch2_light_beyond"]])
	assert_true(notes.has(["New goal: The Hallowmere Way", "quest"]))
	assert_false(notes.has(["New goal: A Light Beyond", "quest"]), "a step done on arrival is not announced as new")
	log.evaluate()
	assert_eq(started.size(), 2, "no repeated start events")
	_finish("ch2_waygate")
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_commons"])
	assert_eq(log.objective_status(), [{"label": "Light the Commons arch", "done": false, "progress": 0, "target": 1},
		{"label": "Read the festival map", "done": false, "progress": 0, "target": 1}])


func test_lamp_steps_are_shown_together_and_done_in_any_order() -> void:
	_activate()
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps"]:
		_finish(id)
	var notes := record(Events.notify, 2)
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_orchard", "ch2_quarry", "ch2_manor"])
	assert_eq(log.display_title(), "Three Roads, Three Lamps")
	var announced: Array = notes.filter(func(n: Array) -> bool: return String(n[0]).begins_with("New goal"))
	assert_eq(announced, [["New goal: Three Roads, Three Lamps", "quest"]], "the group is announced once, by its title")
	_finish("ch2_quarry")
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_orchard", "ch2_manor"])
	_finish("ch2_manor")
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_orchard"])
	assert_eq(log.display_title(), "Three Roads, Three Lamps", "still the group")
	_finish("ch2_orchard")
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_prepare"])
	assert_true(GameState.get_flag("ch2_orchard_restored"), "lamp steps set their recipe unlock flags")
	assert_true(GameState.get_flag("ch2_quarry_restored"))
	assert_true(GameState.get_flag("ch2_manor_restored"))


func test_objectives_met_early_latch_when_the_step_is_reached() -> void:
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor",
			"ch2_prepare", "ch2_lamps_linked"]:
		_finish(id)
	GameState.set_flag("ch2_three_lines_early", true)
	GameState.set_flag("ch2_line_water")      # a later step's flag too
	_activate()
	log.evaluate()
	assert_eq(log.done, MP_IDS.slice(0, 9), "one evaluation latches every step already satisfied")
	assert_eq(_ids(log.current_steps()), ["ch2_service_gate"])
	assert_eq(log.objective_status(log.step_by_id("ch2_three_lines"))[0]["done"], true, "state based: done before it is reached")


func test_rewards_are_granted_once_through_the_ledger() -> void:
	_activate()
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps", "ch2_orchard"]:
		_finish(id)
	log.evaluate()
	for id in ["ch2_light_beyond", "ch2_waygate", "ch2_commons", "ch2_outer_lamps", "ch2_orchard"]:
		assert_true(GameState.has_reward("rw_" + id), "ledger rw_" + id)
	assert_eq(_held("garden_seal"), 1)
	assert_eq(_held("pumpkin_seeds"), 6, "3 from the Commons + 3 from the orchard")
	assert_eq(_held("roseberry_seeds"), 2)
	var ledger_before: Dictionary = GameState.ledger.duplicate()
	# A repaired/edited save that forgot the done list: the steps complete again, the rewards do not.
	log.from_dict({"done": [], "baselines": {}})
	log.evaluate()
	assert_eq(_held("garden_seal"), 1, "never twice")
	assert_eq(_held("roseberry_seeds"), 2)
	assert_eq(_held("pumpkin_seeds"), 6)
	assert_eq(GameState.ledger, ledger_before)


func test_skips_prevent_a_stall_after_a_sequence_break() -> void:
	_activate()
	for id in MP_IDS.slice(1, 9):
		_finish(id)
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_service_gate"])
	var notes := record(Events.notify, 2)
	GameState.set_flag("ch2_choir_defeated")   # the dungeon was finished before the tracker got there
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_routes_restored"])
	for n in notes:
		assert_false(String(n[0]).contains("Hask's Rail"), "skipped steps pass silently")
	assert_true(notes.has(["Goal complete: No Welcome in That Voice", "quest"]))
	assert_true(GameState.has_reward("rw_ch2_weaver_crossing"), "a skipped step still records its reward")
	assert_eq(_held("thread_veil"), 1)


## The log itself never emits Events.chapter2_completed: Game.complete_chapter_two() (the ending flow) is the
## single emitter (lead integration decision). The final step still latches once and sets its flag.
func test_final_step_emits_chapter2_completed_once() -> void:
	var done := record(Events.chapter2_completed, 0)
	_activate()
	for id in MP_IDS:
		_finish(id)
	log.evaluate()
	assert_eq(done.size(), 0, "the ending flow, not the log, announces the chapter")
	assert_true(log.is_finished())
	assert_eq(log.done, MP_IDS)
	assert_eq(log.current_steps(), [])
	assert_true(GameState.get_flag("ch2_feast"), "the final step sets its unlock flag")
	log.evaluate()
	log.from_dict(log.to_dict())
	log.evaluate()
	assert_eq(done.size(), 0, "never from the log, also after reload")
	assert_eq(GameState.current_objective()["source"], "legacy", "a finished chapter hands the tracker back")


func test_arachnophobia_text() -> void:
	var s: Dictionary = log.step_by_id("ch2_weaver_crossing")
	Settings.set_value("arachnophobia", false)
	assert_eq(log.step_string(s, "title"), "Weaver's Crossing")
	Settings.set_value("arachnophobia", true)
	assert_eq(log.step_string(s, "title"), "The Hollow Crossing")
	assert_false(log.step_string(s, "text").contains("threads"))
	assert_eq(log.step_string(log.step_by_id("ch2_choir"), "title"), "No Welcome in That Voice", "no alt: plain text")


func test_persistence_by_stable_id() -> void:
	_activate()
	_finish("ch2_waygate")
	log.evaluate()
	var d: Dictionary = log.to_dict()
	assert_eq(d["accepted"], true)
	assert_eq(d["done"], ["ch2_light_beyond", "ch2_waygate"])
	var started := record(Events.chapter2_step_started, 1)
	var fresh: RefCounted = ChapterLog.new()
	fresh.from_dict(json_norm({"done": ["ch2_waygate", "ch2_light_beyond", "ch2_from_a_newer_build", 5, "ch2_waygate"],
		"baselines": {"ch2_commons": {"x": 2.0, "bad": "y"}, "junk": 3}}))
	assert_eq(fresh.done, ["ch2_waygate", "ch2_light_beyond", "ch2_from_a_newer_build"], "order irrelevant, unknown kept")
	assert_eq(fresh.baselines, {"ch2_commons": {"x": 2}})
	assert_eq(_ids(fresh.current_steps()), ["ch2_commons"])
	assert_eq(started, [], "loading emits nothing")
	# The whole state round trip keeps it.
	GameState.from_dict(json_norm(GameState.to_dict()))
	assert_eq(GameState.chapter2.done, ["ch2_light_beyond", "ch2_waygate"])
	assert_eq(_ids(GameState.chapter2.current_steps()), ["ch2_commons"])


func test_objective_types() -> void:
	assert_eq(ChapterLog.check_objective({"type": "flags_all", "flags": ["a", "b", "c"], "label": "L"}),
		{"label": "L", "done": false, "progress": 0, "target": 3})
	GameState.set_flag("a")
	GameState.set_flag("c", "yes")
	assert_eq(ChapterLog.check_objective({"type": "flags_all", "flags": ["a", "b", "c"]})["progress"], 2)
	GameState.discover("hallowmere_reach", "orchard")
	assert_true(ChapterLog.check_objective({"type": "discovered", "area": "hallowmere_reach", "landmark": "orchard"})["done"])
	assert_false(ChapterLog.check_objective({"type": "discovered", "area": "hallowmere_reach", "landmark": "quarry"})["done"])
	assert_eq(ChapterLog.check_objective({"type": "discovered", "area": "hallowmere_reach", "count": 2})["progress"], 1)
	GameState.add_structure("table", Vector3.ZERO, 0.0)
	assert_true(ChapterLog.check_objective({"type": "placed_any", "structures": ["stool", "table"], "count": 1})["done"])
	GameState.companion("mochi")["home_spot"] = [1.0, 0.0, 1.0]
	assert_true(ChapterLog.check_objective({"type": "companion_home_spot", "count": 1})["done"])
	GameState.add_counter("c", 5)
	assert_eq(ChapterLog.check_objective({"type": "counter", "counter": "c", "count": 3, "since_start": true}, {"c": 4})["progress"], 1)
	GameState.set_flag("flag_with_a_string", "hello")
	assert_true(ChapterLog.check_objective({"type": "flag", "flag": "flag_with_a_string"})["done"], "non-bool flags never error")
	Settings.set_value("arachnophobia", true)
	assert_eq(ChapterLog.check_objective({"type": "flag", "flag": "x", "label": "Webs", "alt_label": "Roots"})["label"], "Roots")


func test_has_pending_completion_drives_the_poll() -> void:
	_activate()
	assert_true(log.has_pending_completion(), "light_beyond is done on arrival")
	log.evaluate()
	assert_false(log.has_pending_completion())
	GameState.flags["ch2_waygate_repaired"] = true
	assert_true(log.has_pending_completion())
