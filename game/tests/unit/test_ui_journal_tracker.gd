extends "res://tests/unit/test_core_base.gd"
## B11 tracker (src/ui/hud/tracker.gd): the combined objective card for every stage of the journey -
## the legacy Chapter One chain, the gentle Ward Stone pointer once Chapter One is complete (never the legacy
## "OPTIONAL GOALS" free-play card), the accepted Chapter Two steps with the three lamps shown together (in any
## order, done lamps ticked), a signpost after the chapter, the "where to" line per area, and arachnophobia text.
## Runs the real tracker node too (pooled rows, signature refresh).

const Tracker := preload("res://src/ui/hud/tracker.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const Ch2 := preload("res://data/quests_ch2.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var _area_before := ""
var _zone_before := ""
var tracker: Control


func setup() -> void:
	fresh_state()
	GameState.active = true
	_area_before = Game.area_id
	_zone_before = Game.zone_id
	Settings.set_value("arachnophobia", false)


func teardown() -> void:
	if tracker != null and is_instance_valid(tracker):
		tracker.queue_free()
	tracker = null
	await wait_frames(1)
	Game.area_id = _area_before
	Game.zone_id = _zone_before


## Chapter One finished exactly like a real save: every legacy step before free_play completed + its flags.
func _complete_chapter_one() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})


func _accept() -> void:
	_complete_chapter_one()
	GameState.set_flag("ch2_accepted")
	GameState.chapter2.evaluate()


func _to_lamps() -> void:
	_accept()
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_found_quarry_lamp", "ch2_found_manor_lamp"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()


func _labels(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(String(r["label"]))
	return out


func _spawn_tracker() -> void:
	tracker = Tracker.new()
	add_child(tracker)
	await wait_frames(1)


# --- view model -----------------------------------------------------------------------------------------

func test_legacy_chain_until_chapter_one_completes() -> void:
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "legacy")
	assert_eq(String(vw["header"]), Tracker.HEADER_GOAL)
	assert_eq(String(vw["title"]), String(GameState.quests.current_step()["title"]))
	assert_eq(vw["rows"].size(), GameState.quests.objective_status().size())
	assert_eq(String(vw["targets"][0]["id"]), "haven")
	# where line: unchanged legacy wording, surface only, hidden inside the target landmark
	var key := Settings.action_label("map")
	assert_eq(Tracker.where_text(vw, "surface", Vector3(90, 0, 90)), "Head to Krystal's Haven   ·   %s Map" % key)
	assert_eq(Tracker.where_text(vw, "surface", Vector3(1, 0, 1)), "", "already there")
	assert_eq(Tracker.where_text(vw, "below", Vector3(90, 0, 90)), "", "legacy line is surface-only")
	# a mid-chapter step
	GameState.quests.from_dict({"index": 5})
	vw = Tracker.objective_view()
	assert_eq(String(vw["step_id"]), "mochi")
	assert_eq(String(vw["targets"][0]["name"]), "Berry Glade")


func test_pointer_after_chapter_one_never_the_free_play_card() -> void:
	_complete_chapter_one()
	assert_eq(GameState.quests.current_id(), "free_play", "legacy chain sits on free_play")
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "pointer")
	assert_eq(String(vw["title"]), "The Ward Stone has something new to say")
	assert_eq(String(vw["header"]), Tracker.HEADER_POINTER)
	assert_ne(String(vw["header"]), Tracker.HEADER_OPTIONAL)
	assert_eq(vw["rows"].size(), 0, "no free-play rows on the pointer")
	assert_eq(String(vw["targets"][0]["id"]), "haven")
	var key := Settings.action_label("map")
	assert_eq(Tracker.where_text(vw, "surface", Vector3(80, 0, 0)), Tracker.POINTER_WHERE + "   ·   %s Map" % key)
	assert_eq(Tracker.where_text(vw, "surface", Vector3(0, 0, 2)), Tracker.POINTER_WHERE, "at home: no map hint")
	assert_eq(Tracker.where_text(vw, "below", null), Tracker.POINTER_WHERE)
	# read once and stayed: softer wording, still there
	GameState.set_flag("read_ward_ch2")
	vw = Tracker.objective_view()
	assert_eq(String(vw["title"]), Tracker.POINTER_TITLE_READ)
	assert_eq(Tracker.where_text(vw, "surface", Vector3(80, 0, 0)), Tracker.POINTER_WHERE_READ)
	# the pointer also covers a save whose free_play goals were already done (legacy index past the end)
	GameState.quests.from_dict({"index": QuestsData.STEPS.size()})
	assert_eq(String(Tracker.objective_view()["kind"]), "pointer")


func test_accepted_chapter_two_step_and_cross_area_where() -> void:
	_accept()
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "chapter2")
	assert_eq(String(vw["step_id"]), "ch2_waygate")
	assert_eq(String(vw["title"]), "The Hallowmere Way")
	assert_eq(String(vw["header"]), Tracker.HEADER_GOAL)
	assert_eq(_labels(vw["rows"]), ["Repair the Lanternwake waygate"])
	assert_ne(String(vw["hint"]), "", "the step hint is carried for the journal tip")
	var t: Dictionary = vw["targets"][0]
	assert_eq([String(t["id"]), String(t["area"])], ["ruin", "surface"])
	var key := Settings.action_label("map")
	assert_eq(Tracker.where_text(vw, "surface", Vector3(90, 0, 90)), "Head to Moonlit Ruin   ·   %s Map" % key)
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3.ZERO), "Head to Moonlit Ruin, in Hollowhaven Woods")
	# the Commons step: a Reach target, seen from the woods and from inside the Commons
	for f in ["ch2_waygate_repaired"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	vw = Tracker.objective_view()
	assert_eq(String(vw["step_id"]), "ch2_commons")
	assert_eq(vw["rows"].size(), 2)
	assert_eq(Tracker.where_text(vw, "surface", Vector3.ZERO), "Head to Lanternwake Commons, in Hallowmere Reach")
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3(0, 0, 100)), "Head to Lanternwake Commons   ·   %s Map" % key)
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3(0, 0, 62)), "", "inside the Commons")


func test_three_lamps_shown_together_in_any_order() -> void:
	_to_lamps()
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "chapter2")
	assert_eq(String(vw["group"]), "lamps")
	assert_eq(String(vw["title"]), String(Ch2.GROUPS["lamps"]["title"]))
	assert_eq(_labels(vw["rows"]), ["Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"])
	assert_eq(vw["parts"].size(), 3)
	assert_eq(Tracker.pending_targets(vw).size(), 3)
	# light the MANOR lamp first: it stays listed, ticked; the others remain
	GameState.set_flag("ch2_manor_lamp_lit")
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_manor"))
	vw = Tracker.objective_view()
	assert_eq(String(vw["group"]), "lamps")
	assert_eq(_labels(vw["rows"]), ["Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"], "all three stay")
	assert_eq([bool(vw["rows"][0]["done"]), bool(vw["rows"][1]["done"]), bool(vw["rows"][2]["done"])], [false, false, true])
	var pend: Array = []
	for t in Tracker.pending_targets(vw):
		pend.append(String(t["id"]))
	assert_eq(pend, ["hr_orchard", "hr_quarry"])
	var key := Settings.action_label("map")
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3.ZERO), "Each is marked on your map   ·   %s Map" % key)
	assert_eq(Tracker.where_text(vw, "surface", Vector3.ZERO), "In Hallowmere Reach")
	# then the orchard and quarry: the chain moves on past the group
	GameState.set_flag("ch2_garden_lamp_lit")
	GameState.set_flag("ch2_quarry_lamp_lit")
	GameState.chapter2.evaluate()
	vw = Tracker.objective_view()
	assert_eq(String(vw["group"]), "")
	assert_eq(String(vw["step_id"]), "ch2_prepare")


func test_after_chapter_two_a_signpost_never_the_legacy_header() -> void:
	_accept()
	for s in Ch2.STEPS:
		for o in s["objectives"]:
			if String(o.get("type", "")) == "flag":
				GameState.set_flag(String(o["flag"]))
			elif String(o.get("type", "")) == "flags_all":
				for f in o["flags"]:
					GameState.set_flag(String(f))
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_finished())
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "signpost")
	assert_eq(String(vw["header"]), Tracker.HEADER_SIGNPOST)
	var g: Dictionary = GameState.optional_goals.goal(String(vw["step_id"]))
	assert_false(g.is_empty(), "a real optional goal")
	assert_eq(int(g["chapter"]), 2, "Chapter Two side activities come first")
	assert_false(GameState.optional_goals.is_done(String(vw["step_id"])))
	# nothing left at all -> hidden
	for og in GameState.optional_goals.goals():
		GameState.optional_goals.mark_done_silently(String(og["id"]))
	assert_eq(String(Tracker.objective_view()["kind"]), "done")


func test_arachnophobia_titles_and_rooms() -> void:
	_accept()
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor", "ch2_prepare",
			"ch2_lamps_linked", "ch2_service_gate", "ch2_true_signal", "ch2_refuge", "ch2_miners", "ch2_three_lines"]:
		for o in GameState.chapter2.step_by_id(id)["objectives"]:
			if String(o.get("type", "")) == "flag":
				GameState.set_flag(String(o["flag"]))
	GameState.chapter2.evaluate()
	assert_eq(String(Tracker.objective_view()["step_id"]), "ch2_weaver_crossing")
	assert_eq(String(Tracker.objective_view()["title"]), "Weaver's Crossing")
	assert_eq(MapView.place_name("hw_crossing", "hushed_works"), "Weaver's Crossing")
	Settings.set_value("arachnophobia", true)
	var vw := Tracker.objective_view()
	assert_eq(String(vw["title"]), "The Hollow Crossing")
	assert_false(String(vw["text"]).to_lower().contains("thread"), "alt story text")
	assert_eq(MapView.place_name("hw_crossing", "hushed_works"), "The Hollow Crossing")
	assert_eq(Tracker.where_text(vw, "hushed_works", null, "hw_refuge"), "Head to The Hollow Crossing   ·   %s Map" % Settings.action_label("map"))
	assert_eq(Tracker.where_text(vw, "hushed_works", null, "hw_crossing"), "", "standing in the room")


func test_every_chapter_two_hint_uses_known_tokens() -> void:
	# The hint card and the journal tip replace {tokens} through UiUtil.TOKEN_ACTIONS.
	var rx := RegEx.new()
	rx.compile("\\{([a-z_]+)\\}")
	var texts: Array = []
	for s in Ch2.STEPS:
		texts.append(String(s.get("hint", "")))
		texts.append(String(s.get("alt_hint", "")))
	for g in GameState.optional_goals.goals():
		texts.append(String(g.get("text", "")))
	for t in texts:
		for m in rx.search_all(String(t)):
			var tok := m.get_string(1)
			assert_true(UiUtil.TOKEN_ACTIONS.has(tok) or tok == "move", "unknown hint token {%s} in: %s" % [tok, t])


# --- the real node --------------------------------------------------------------------------------------

func test_tracker_node_follows_every_stage() -> void:
	await _spawn_tracker()
	assert_true(tracker.visible)
	assert_eq(tracker.view_kind, "legacy")
	assert_eq(tracker.title_l.text, String(GameState.quests.current_step()["title"]))
	_complete_chapter_one()
	Events.objectives_changed.emit()
	await wait_frames(1)
	assert_eq(tracker.view_kind, "pointer")
	assert_eq(tracker.title_l.text, Tracker.POINTER_TITLE)
	assert_ne(tracker.header.text, Tracker.HEADER_OPTIONAL)
	assert_eq(tracker.shown_rows().size(), 0)
	GameState.set_flag("ch2_accepted")
	GameState.chapter2.evaluate()           # emits objectives_changed
	await wait_frames(1)
	assert_eq(tracker.view_kind, "chapter2")
	assert_eq(tracker.title_l.text, "The Hallowmere Way")
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_found_quarry_lamp", "ch2_found_manor_lamp", "ch2_quarry_lamp_lit"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	await wait_frames(1)
	assert_eq(tracker.title_l.text, "Three Roads, Three Lamps")
	var rows: Array = tracker.shown_rows()
	assert_eq(rows.size(), 3, "three lamp rows (pooled rows reused, extras hidden)")
	assert_eq([bool(rows[0]["done"]), bool(rows[1]["done"]), bool(rows[2]["done"])], [false, true, false])
	# the where line follows the area on the 1 s poll / area load
	Game.area_id = "surface"
	tracker.refresh()
	await wait_frames(1)
	assert_true(tracker.where_l.visible)
	assert_eq(tracker.where_l.text, "In Hallowmere Reach")
	# not playing (title screen): hidden
	GameState.active = false
	tracker.refresh()
	assert_false(tracker.visible)


func test_tracker_node_live_arachnophobia_toggle() -> void:
	_accept()
	for id in ["ch2_waygate", "ch2_commons", "ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor", "ch2_prepare",
			"ch2_lamps_linked", "ch2_service_gate", "ch2_true_signal", "ch2_refuge", "ch2_miners", "ch2_three_lines"]:
		for o in GameState.chapter2.step_by_id(id)["objectives"]:
			if String(o.get("type", "")) == "flag":
				GameState.set_flag(String(o["flag"]))
	GameState.chapter2.evaluate()
	await _spawn_tracker()
	assert_eq(tracker.title_l.text, "Weaver's Crossing")
	Settings.set_value("arachnophobia", true)   # emits settings_changed("arachnophobia")
	await wait_frames(1)
	assert_eq(tracker.title_l.text, "The Hollow Crossing")


func test_quest_banner_drops_repeated_lines() -> void:
	var qb: Control = preload("res://src/ui/hud/quest_banner.gd").new()
	add_child(qb)
	await wait_frames(1)
	qb.show_text("New goal: Three Roads, Three Lamps")
	qb.show_text("New goal: Three Roads, Three Lamps")    # on screen already
	qb.show_text("Goal complete: Pumpkins With Opinions")
	qb.show_text("Goal complete: Pumpkins With Opinions") # already queued
	qb.show_text("Optional goal complete: The Tailor's Cache")
	assert_eq(qb.label.text, "Three Roads, Three Lamps")
	assert_eq(qb._queue, ["Goal complete: Pumpkins With Opinions", "Optional goal complete: The Tailor's Cache"])
	qb.queue_free()
