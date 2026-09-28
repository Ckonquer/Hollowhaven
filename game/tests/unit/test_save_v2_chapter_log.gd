extends "res://tests/unit/test_core_base.gd"
## Chapter Two quest layer (src/core/chapter_log.gd + data/quests_ch2.gd; MP §11, spec §7-8): the 20 stable
## step ids, activation only after chapter_one_complete AND ch2_accepted, the lamp group shown together and
## done in any order, latching of objectives met early, rewards through the ledger exactly once, skips that
## prevent stalls, the final completion event, arachnophobia text and persistence by id.

const ChapterLog := preload("res://src/core/chapter_log.gd")
const Data := preload("res://data/quests_ch2.gd")
const DeepLayout := preload("res://data/works_layout_deep.gd")
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
## Display-only rows (shown with their done state, never required), in order, before the step's real objectives.
const DISPLAY_FLAGS := {"ch2_quarry": ["hr_warden_defeated", "ch2_winch_repaired"]}

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


## "New goal" announcements among recorded Events.notify calls, in order.
func _news(notes: Array) -> Array:
	var out: Array = []
	for n in notes:
		if String(n[0]).begins_with("New goal"):
			out.append(String(n[0]))
	return out


## Hint ids among recorded Events.hint calls, in order.
func _hint_ids(hints: Array) -> Array:
	var out: Array = []
	for h in hints:
		out.append(String(h[0]))
	return out


## A title's words, lower case, sorted (so "Three Lamps, Three Roads" == "Three Roads, Three Lamps").
func _title_words(t: String) -> Array:
	var words: Array = []
	for w in t.to_lower().replace(",", " ").replace(".", " ").replace(":", " ").split(" ", false):
		words.append(w)
	words.sort()
	return words


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
		var flags_shown: Array = []
		for o in s["objectives"]:
			assert_eq(o["type"], "flag", s["id"] + " uses flag objectives")
			if ChapterLog.is_display_objective(o):
				assert_true(flags_needed.is_empty(), s["id"] + ": display rows come before the real objectives")
				flags_shown.append(o["flag"])
			else:
				flags_needed.append(o["flag"])
		assert_eq(flags_needed, STEP_FLAGS[s["id"]], s["id"] + " flags")
		assert_eq(flags_shown, DISPLAY_FLAGS.get(s["id"], []), s["id"] + " display rows")
	var grouped: Array = []
	for s in Data.STEPS:
		if String(s.get("group", "")) == "lamps":
			grouped.append(s["id"])
	assert_eq(grouped, ["ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor"], "the lamp search and its three roads")
	# A group only works as consecutive steps (ChapterLog._pending_front walks STEPS in order).
	var seen_groups: Array = []
	var prev := ""
	for s in Data.STEPS:
		var g := String(s.get("group", ""))
		if g != "" and g != prev:
			assert_false(seen_groups.has(g), "group %s is consecutive" % g)
			seen_groups.append(g)
			assert_true(Data.GROUPS.has(g), "group %s has display data" % g)
		prev = g
	# Place-bound hints: each lamp road's hint waits until that lamp is found.
	var hint_flags := {}
	for s in Data.STEPS:
		if s.has("hint_when"):
			var w: Dictionary = s["hint_when"]
			assert_eq(String(w.get("type", "")), "flag", s["id"] + " hint_when is a flag check")
			hint_flags[s["id"]] = String(w.get("flag", ""))
	assert_eq(hint_flags, {"ch2_orchard": "ch2_found_orchard_lamp", "ch2_quarry": "ch2_found_quarry_lamp",
		"ch2_manor": "ch2_found_manor_lamp"})
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


## CH2-001: the lamp search and the three roads are current together as soon as the Commons is done, so a lit
## lamp completes its own road at once (seal, recipe flag, "Goal complete" + message) while the other lamps are
## not even found, and each road is recorded on its own (MP §9). Before the fix the roads only started once the
## manor lamp had been found, and the Garden / Quarry Seals waited until then.
func test_each_lit_lamp_pays_its_road_at_once() -> void:
	_activate()
	_finish("ch2_waygate")
	_finish("ch2_commons")
	var notes := record(Events.notify, 2)
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor"])
	assert_eq(log.display_title(), "Three Roads, Three Lamps")
	assert_eq(_news(notes), ["New goal: Three Roads, Three Lamps"], "one announcement for the whole group")
	# The garden lamp, found and lit first: the orchard road pays now, with the quarry and manor lamps unfound.
	GameState.set_flag("ch2_found_orchard_lamp")
	GameState.set_flag("ch2_garden_lamp_lit")
	assert_true(log.has_pending_completion(), "the 1 s poll sees the lit lamp")
	log.evaluate()
	assert_true(log.is_done("ch2_orchard"))
	assert_eq(_held("garden_seal"), 1)
	assert_true(GameState.get_flag("ch2_orchard_restored"), "its recipes unlock now")
	assert_true(notes.has(["Goal complete: Pumpkins With Opinions", "quest"]))
	assert_true(notes.has([String(log.step_by_id("ch2_orchard")["on_complete"]["message"]), "info"]))
	assert_false(log.is_done("ch2_outer_lamps"), "the search is still open")
	assert_eq(_ids(log.current_steps()), ["ch2_outer_lamps", "ch2_quarry", "ch2_manor"])
	# Then the quarry, the manor lamp still unfound: its own seal, the garden one untouched.
	GameState.set_flag("ch2_found_quarry_lamp")
	GameState.set_flag("ch2_quarry_lamp_lit")
	log.evaluate()
	assert_true(log.is_done("ch2_quarry"))
	assert_eq(_held("quarry_seal"), 1)
	assert_eq(_held("garden_seal"), 1)
	assert_true(GameState.get_flag("ch2_quarry_restored"), "Ironwood recipes before the manor")
	assert_eq(_ids(log.current_steps()), ["ch2_outer_lamps", "ch2_manor"])
	assert_eq(log.display_title(), "Three Roads, Three Lamps", "still the group")
	# Finding the manor lamp completes the search (its own record); the manor road stays open until it is lit.
	GameState.set_flag("ch2_found_manor_lamp")
	log.evaluate()
	assert_true(log.is_done("ch2_outer_lamps"))
	assert_true(notes.has(["Goal complete: Find the Three Lamps", "quest"]))
	assert_eq(_ids(log.current_steps()), ["ch2_manor"])
	assert_false(GameState.has_reward("rw_ch2_manor"))
	GameState.set_flag("ch2_manor_lamp_lit")
	log.evaluate()
	assert_eq(_held("manor_seal"), 1)
	assert_eq(_ids(log.current_steps()), ["ch2_prepare"])
	assert_eq(_news(notes), ["New goal: Three Roads, Three Lamps", "New goal: Made for the Journey"])


## CH2-001, old saves: a save the old build made while the lamp search held the roads back (the search current,
## the garden lamp already lit, the quarry lamp found) loads unchanged, and the next evaluation - the 1 s poll -
## pays the garden road at once (state based), starts the other roads without announcing the group again and
## gives the found quarry lamp its hint.
func test_old_save_stuck_in_the_lamp_search_pays_on_load() -> void:
	_activate()
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_garden_lamp_lit", "ch2_found_quarry_lamp"]:
		GameState.set_flag(f)
	# Exactly what the old build saved: done up to the Commons, only the lamp search started.
	var old := {"accepted": true, "done": ["ch2_light_beyond", "ch2_waygate", "ch2_commons"],
		"baselines": {"ch2_light_beyond": {}, "ch2_waygate": {}, "ch2_commons": {}, "ch2_outer_lamps": {}}}
	var saved: Dictionary = GameState.to_dict()
	saved["chapter2"] = old
	GameState.from_dict(json_norm(saved))
	log = GameState.chapter2
	assert_deep_eq(json_norm(log.to_dict()), json_norm(old), "loading changes nothing by itself")
	assert_false(GameState.has_reward("rw_ch2_orchard"))
	assert_true(log.has_pending_completion(), "the poll sees the lit garden lamp")
	var notes := record(Events.notify, 2)
	var hints := record(Events.hint, 2)
	log.evaluate()
	assert_true(log.is_done("ch2_orchard"), "the stuck road completes on load")
	assert_eq(_held("garden_seal"), 1)
	assert_true(GameState.get_flag("ch2_orchard_restored"))
	assert_true(notes.has(["Goal complete: Pumpkins With Opinions", "quest"]))
	assert_eq(_news(notes), [], "the old build announced the group already")
	assert_eq(_ids(log.current_steps()), ["ch2_outer_lamps", "ch2_quarry", "ch2_manor"])
	assert_eq(_hint_ids(hints), ["quest_ch2_quarry"], "the found quarry lamp's hint; none for the paid road")
	log.evaluate()
	assert_eq(_held("garden_seal"), 1, "paid once")
	assert_eq(_hint_ids(hints), ["quest_ch2_quarry"], "hints once")


## CH2-001 hints: when the lamp group starts at the Commons only the search's map hint goes out (not four cards
## about places Krystal has not reached); each road's hint waits until its lamp is found - she is standing at it -
## and goes out once. One the HUD hint card already showed (flag hint_quest_<id>, an earlier session) stays quiet.
func test_lamp_road_hints_wait_for_their_lamp() -> void:
	_activate()
	_finish("ch2_waygate")
	_finish("ch2_commons")
	var hints := record(Events.hint, 2)
	log.evaluate()
	assert_eq(_hint_ids(hints), ["quest_ch2_outer_lamps"])
	GameState.set_flag("ch2_found_quarry_lamp")
	log.evaluate()
	assert_eq(_hint_ids(hints), ["quest_ch2_outer_lamps", "quest_ch2_quarry"])
	if hints.size() > 1:
		assert_eq(String(hints[1][1]), String(log.step_by_id("ch2_quarry")["hint"]))
	log.evaluate()
	assert_eq(hints.size(), 2, "once")
	GameState.set_flag("hint_quest_ch2_manor", true)
	GameState.set_flag("ch2_found_orchard_lamp")
	GameState.set_flag("ch2_found_manor_lamp")
	log.evaluate()
	assert_true(log.is_done("ch2_outer_lamps"))
	assert_eq(_hint_ids(hints), ["quest_ch2_outer_lamps", "quest_ch2_quarry", "quest_ch2_orchard"])
	# A new session (loading) forgets what went out, the hint card's flags do not.
	GameState.set_flag("hint_quest_ch2_orchard", true)
	GameState.set_flag("hint_quest_ch2_quarry", true)
	log.from_dict(log.to_dict())
	log.evaluate()
	assert_eq(hints.size(), 3)


## CH2-012: a group title and a step title never read as the same goal twice (the old step 'Three Lamps, Three
## Roads' followed by 'New goal: Three Roads, Three Lamps'): no step title uses exactly the words of a group title.
func test_group_and_step_titles_never_repeat_each_other() -> void:
	for g in Data.GROUPS:
		var gw := _title_words(String(Data.GROUPS[g]["title"]))
		for s in Data.STEPS:
			for field in ["title", "alt_title"]:
				if s.has(field):
					assert_ne(_title_words(String(s[field])), gw, "%s %s vs the %s group title" % [s["id"], field, g])


## CH2-015: a step's hint goes out when the step starts - wherever Krystal is (Wake the Lines ends in whichever
## room restores the last line, often the Light Well) - and the journal shows it as the tip for as long as the
## step is current, so a hint never assumes where she stands. The crossing hint still names its checkpoint.
func test_step_hints_never_assume_where_krystal_stands() -> void:
	var relative := ["behind you", "in front of you", "ahead of you", "beside you", "next to you", "around you"]
	for s in Data.STEPS:
		for field in ["hint", "alt_hint"]:
			var h := String(s.get(field, "")).to_lower()
			for p in relative:
				assert_false(h.contains(p), "%s %s assumes where she stands ('%s')" % [s["id"], field, p])
	# The hint really goes out at the last line, far from the crossing.
	_activate()
	for id in MP_IDS.slice(1, 13):   # up to What They Left
		_finish(id)
	GameState.set_flag("ch2_line_water")
	GameState.set_flag("ch2_line_bell")
	log.evaluate()
	var hints := record(Events.hint, 2)
	GameState.set_flag("ch2_line_light")   # restored in the Light Well
	log.evaluate()
	assert_eq(_hint_ids(hints), ["quest_ch2_weaver_crossing"])
	assert_true(String(hints[0][1]).contains("checkpoint"), "the checkpoint is still mentioned: " + String(hints[0][1]))
	assert_true(String(hints[0][1]).contains("before the bridge"), "and where it is")


## CH2-016: the Choir falls in the vault and "Lanterns on Every Road" starts right there, as the vault's own
## bell-lift opens: the hint sent at that moment names that lift and where it goes (the Sunken Bellhouse, in the
## Reach), not the refuge shortcut or the Bellhouse stair five rooms back.
func test_after_the_choir_the_hint_names_the_vault_bell_lift() -> void:
	_activate()
	for id in MP_IDS.slice(1, 16):   # up to The House That Isn't
		_finish(id)
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_choir"])
	var hints := record(Events.hint, 2)
	GameState.set_flag("ch2_choir_defeated")
	log.evaluate()
	assert_eq(_ids(log.current_steps()), ["ch2_routes_restored"])
	assert_eq(_hint_ids(hints), ["quest_ch2_routes_restored"])
	var h := String(hints[0][1])
	assert_true(h.contains("bell-lift"), h)
	assert_true(h.contains("Sunken Bellhouse"), h)
	assert_false(h.begins_with("Take the refuge shortcut"), "the vault's exit comes first: " + h)
	# That lift really goes up to the Reach (choir_arena.gd rides it to works_layout_deep.gd VAULT_EXIT_TARGET).
	var exit_target: Dictionary = DeepLayout.VAULT_EXIT_TARGET
	assert_eq(String(exit_target["area"]), Data.REACH)
	assert_true(String(exit_target["spawn"]).begins_with("bellhouse"), str(exit_target))


## R38 / F03: the quarry step shows what its lamp needs ("Calm the Quarry Warden", "Mend the mineral winch")
## as display rows with their real done state, but completion still reads only ch2_quarry_lamp_lit.
func test_quarry_display_rows_are_shown_but_never_required() -> void:
	_activate()
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps"]:
		_finish(id)
	log.evaluate()
	var q: Dictionary = log.step_by_id("ch2_quarry")
	assert_eq(log.objective_status(q), [
		{"label": "Calm the Quarry Warden", "done": false, "progress": 0, "target": 1, "display": true},
		{"label": "Mend the mineral winch", "done": false, "progress": 0, "target": 1, "display": true},
		{"label": "Light the quarry lamp", "done": false, "progress": 0, "target": 1}])
	# Both display rows met: they tick, the step does not complete (nothing pending for the 1 s poll).
	GameState.set_flag("hr_warden_defeated")
	GameState.set_flag("ch2_winch_repaired")
	var rows: Array = log.objective_status(q)
	assert_eq([rows[0]["done"], rows[1]["done"], rows[2]["done"]], [true, true, false], "display rows show their state")
	assert_false(log.step_done(q), "display rows never complete a step")
	assert_false(log.has_pending_completion(), "nothing for the poll to do")
	log.evaluate()
	assert_false(log.is_done("ch2_quarry"))
	# The combined objective (tracker / journal / telemetry) lists them under the quarry step, in order.
	var labels: Array = []
	for st in GameState.current_objective()["status"]:
		if String(st["step"]) == "ch2_quarry":
			labels.append(String(st["label"]))
	assert_eq(labels, ["Calm the Quarry Warden", "Mend the mineral winch", "Light the quarry lamp"])
	GameState.set_flag("ch2_quarry_lamp_lit")
	assert_true(log.has_pending_completion())
	log.evaluate()
	assert_true(log.is_done("ch2_quarry"))
	assert_true(GameState.has_reward("rw_ch2_quarry"))


## A save with the quarry lamp lit but no Warden / winch flag (an old or repaired save, a fallback path) never
## stalls: the step completes on the lamp alone, through a real save round trip, and pays once.
func test_quarry_step_completes_on_the_lamp_alone() -> void:
	_activate()
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps"]:
		_finish(id)
	log.evaluate()
	GameState.set_flag("ch2_quarry_lamp_lit")
	assert_false(GameState.get_flag("hr_warden_defeated"))
	assert_false(GameState.get_flag("ch2_winch_repaired"))
	GameState.from_dict(json_norm(GameState.to_dict()))
	log = GameState.chapter2
	assert_false(log.is_done("ch2_quarry"), "loading completes nothing by itself")
	assert_true(log.has_pending_completion(), "the poll sees the lit lamp")
	log.evaluate()
	assert_true(log.is_done("ch2_quarry"), "completes without the Warden / winch rows")
	assert_eq(_held("quarry_seal"), 1)
	assert_eq(_ids(log.current_steps()), ["ch2_orchard", "ch2_manor"])
	log.evaluate()
	assert_eq(_held("quarry_seal"), 1, "paid once")


## The display-row rule of ChapterLog itself: a display objective reports "display": true (others keep their
## exact shape), a step whose only objectives are display rows never completes, and a display row that is not
## met does not block the step.
func test_display_rows_rule() -> void:
	GameState.set_flag("shown")
	assert_eq(ChapterLog.check_objective({"type": "flag", "flag": "shown", "label": "S", "display": true}),
		{"label": "S", "done": true, "progress": 1, "target": 1, "display": true})
	assert_eq(ChapterLog.check_objective({"type": "flag", "flag": "shown", "label": "S"}),
		{"label": "S", "done": true, "progress": 1, "target": 1}, "no display key on a real objective")
	assert_false(ChapterLog.is_display_objective({"type": "flag", "flag": "x", "display": false}))
	assert_false(log.step_done({"id": "only_display", "objectives": [{"type": "flag", "flag": "shown", "display": true}]}),
		"a step of display rows only never completes")
	assert_true(log.step_done({"id": "mixed", "objectives": [{"type": "flag", "flag": "unset", "display": true},
		{"type": "flag", "flag": "shown"}]}), "an unmet display row does not block")
	assert_false(log.step_done({"id": "mixed2", "objectives": [{"type": "flag", "flag": "shown", "display": true},
		{"type": "flag", "flag": "unset"}]}), "a met display row does not complete")


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
