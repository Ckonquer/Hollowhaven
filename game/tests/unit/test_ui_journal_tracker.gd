extends "res://tests/unit/test_core_base.gd"
## B11 tracker (src/ui/hud/tracker.gd): the combined objective card for every stage of the journey -
## the legacy Chapter One chain, the gentle Ward Stone pointer once Chapter One is complete (never the legacy
## "OPTIONAL GOALS" free-play card), the accepted Chapter Two steps with the three lamps shown together (in any
## order, done lamps ticked), a signpost after the chapter, the "where to" line per area, and arachnophobia text.
## A Lanternwake Expedition under way takes the card only where it would be a signpost / done / hidden (P36).
## Runs the real tracker node too (pooled rows, signature refresh).

const Tracker := preload("res://src/ui/hud/tracker.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const Ch2 := preload("res://data/quests_ch2.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Ex := preload("res://src/expeditions/expeditions.gd")
const ExData := preload("res://data/expeditions.gd")

var _area_before := ""
var _zone_before := ""
var tracker: Control
var _ex_listening := false


func setup() -> void:
	fresh_state()
	GameState.active = true
	_area_before = Game.area_id
	_zone_before = Game.zone_id
	_ex_listening = Ex.is_listening()
	Settings.set_value("arachnophobia", false)


func teardown() -> void:
	if tracker != null and is_instance_valid(tracker):
		tracker.queue_free()
	tracker = null
	await wait_frames(1)
	Game.area_id = _area_before
	Game.zone_id = _zone_before
	if not _ex_listening:
		Ex.shutdown()


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


## The rows a step needs (display-only signpost rows, "display": true in data/quests_ch2.gd, left out).
func _counted(rows: Array) -> Array:
	return rows.filter(func(r: Dictionary) -> bool: return not bool(r.get("display", false)))


## The lamp roads' rows (the lamp search's "Find the ... lamp" rows, shown first in the group, left out).
func _road_rows(rows: Array) -> Array:
	return rows.filter(func(r: Dictionary) -> bool: return String(r.get("step", "")) != "ch2_outer_lamps")


func _part_ids(vw: Dictionary) -> Array:
	var out: Array = []
	for p in vw["parts"]:
		out.append(String(p["id"]))
	return out


## Every display row is labelled and flagged (they are shown with their real done state, never required).
func _check_display_rows(rows: Array) -> void:
	for r in rows:
		if bool((r as Dictionary).get("display", false)):
			assert_ne(String(r["label"]), "", "a display row has a label")
			assert_true(r.has("done"))


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
	assert_eq(_labels(_counted(_road_rows(vw["rows"]))), ["Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"])
	_check_display_rows(vw["rows"])
	assert_eq(_part_ids(vw), ["ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor"])
	assert_true(bool(vw["parts"][0]["done"]), "every lamp found: the search reads done")
	assert_eq(Tracker.pending_targets(vw).size(), 3)
	# light the MANOR lamp first: it stays listed, ticked; the others remain
	GameState.set_flag("ch2_manor_lamp_lit")
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_manor"))
	vw = Tracker.objective_view()
	assert_eq(String(vw["group"]), "lamps")
	var lamps := _counted(_road_rows(vw["rows"]))
	assert_eq(_labels(lamps), ["Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"], "all three stay")
	assert_eq([bool(lamps[0]["done"]), bool(lamps[1]["done"]), bool(lamps[2]["done"])], [false, false, true])
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


## CH2-001: right after the Commons the card already shows the lamp search AND the three roads under the group
## title (not 'Find the manor lamp' alone until every lamp is found): a lamp lit while the others are unfound ticks
## its road at once. The map marks the three roads' places and the Conservatory they start from (the search).
func test_lamp_search_and_roads_shown_together_from_the_commons() -> void:
	_accept()
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "chapter2")
	assert_eq(String(vw["group"]), "lamps")
	assert_eq(String(vw["title"]), String(Ch2.GROUPS["lamps"]["title"]))
	assert_eq(String(vw["text"]), String(Ch2.GROUPS["lamps"]["text"]))
	assert_eq(_part_ids(vw), ["ch2_outer_lamps", "ch2_orchard", "ch2_quarry", "ch2_manor"])
	assert_eq(_labels(_counted(vw["rows"])), ["Find the orchard lamp", "Find the quarry lamp", "Find the manor lamp",
		"Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"])
	var pend: Array = []
	for t in Tracker.pending_targets(vw):
		pend.append(String(t["id"]))
	assert_eq(pend, ["hr_conservatory", "hr_orchard", "hr_quarry", "hr_manor_grounds"], "the hub and the three roads")
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3.ZERO), "Each is marked on your map   ·   %s Map" % Settings.action_label("map"))
	# The garden lamp found and lit, the other two never seen: its road is done and ticked now.
	GameState.set_flag("ch2_found_orchard_lamp")
	GameState.set_flag("ch2_garden_lamp_lit")
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_orchard"))
	vw = Tracker.objective_view()
	assert_eq(String(vw["group"]), "lamps")
	var done_by_label := {}
	for r in vw["rows"]:
		done_by_label[String(r["label"])] = bool(r["done"])
	assert_true(bool(done_by_label["Light the garden lamp"]))
	assert_true(bool(done_by_label["Find the orchard lamp"]))
	assert_false(bool(done_by_label["Find the manor lamp"]))
	assert_false(bool(done_by_label["Light the quarry lamp"]))
	assert_true(bool(vw["parts"][1]["done"]), "the orchard road reads done")
	assert_false(bool(vw["parts"][0]["done"]), "the search is still open")
	pend = []
	for t in Tracker.pending_targets(vw):
		pend.append(String(t["id"]))
	assert_eq(pend, ["hr_conservatory", "hr_quarry", "hr_manor_grounds"], "the lit road's place is no longer marked")


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


# --- Lanternwake Expeditions (P36) ---------------------------------------------------------------------------

## Every Chapter Two step done (the chapter is finished) - the only time the post-Choir board is buildable.
func _finish_chapter_two() -> void:
	_accept()
	for s in Ch2.STEPS:
		for o in s["objectives"]:
			if String(o.get("type", "")) == "flag":
				GameState.set_flag(String(o["flag"]))
			elif String(o.get("type", "")) == "flags_all":
				for f in o["flags"]:
					GameState.set_flag(String(f))
	GameState.chapter2.evaluate()


## Starts the Orchard Patrol from the woods (no Reach area loaded, so no runner is attached).
func _start_patrol() -> void:
	GameState.flags["ch2_orchard_restored"] = true
	Game.area_id = "surface"
	assert_true(Ex.start("orchard_patrol", 5))


func test_expedition_card_replaces_the_signpost_and_done_views() -> void:
	_finish_chapter_two()
	assert_true(GameState.chapter2.is_finished())
	assert_eq(String(Tracker.objective_view()["kind"]), "signpost", "no run: the signpost")
	_start_patrol()
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "expedition", "a run under way takes the signpost's place")
	assert_eq(String(vw["header"]), "EXPEDITION")
	assert_eq(String(vw["title"]), "Orchard Patrol")
	assert_true(bool(vw["optional"]))
	assert_eq(_labels(vw["rows"]).size(), Ex.stop_count("orchard_patrol") + 1, "every stop + the cache")
	assert_eq(String(_labels(vw["rows"])[0]), "Scarecrow Meadow")
	var pt := Tracker.pending_targets(vw)
	assert_eq(pt.size(), 1, "only the current stop is a target")
	assert_eq(String(pt[0]["id"]), "exp_op_meadow")
	assert_eq(String(pt[0]["area"]), "hallowmere_reach")
	# the where line is the view's own, with the map key in the Reach; hidden while she stands at the stop
	var key := Settings.action_label("map")
	var stop: Vector2 = ExData.TEMPLATES["orchard_patrol"]["stops"][0]["pos"]
	assert_eq(Tracker.where_text(vw, "surface", Vector3.ZERO), String(vw["where"]))
	assert_true(Tracker.where_text(vw, "surface", Vector3.ZERO).contains("Scarecrow Meadow"))
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3(0, 0, 60)), String(vw["where"]) + "   ·   %s Map" % key)
	assert_eq(Tracker.where_text(vw, "hallowmere_reach", Vector3(stop.x + 1.0, 0, stop.y)), "", "standing at the stop")
	# every optional goal done: "done" would hide the card; the run still shows
	for og in GameState.optional_goals.goals():
		GameState.optional_goals.mark_done_silently(String(og["id"]))
	assert_eq(String(Tracker.objective_view()["kind"]), "expedition")
	assert_true(Ex.abandon())
	assert_eq(String(Tracker.objective_view()["kind"]), "done", "set aside: back to the calm done state")


func test_expedition_never_replaces_chapter_legacy_or_pointer_steps() -> void:
	GameState.extra[ExData.STATE_KEY] = {"active": {"template": "orchard_patrol", "seed": 5, "stop": 0, "defeated": 0,
		"run": 1, "down": {}, "started_at": 0.0}}
	assert_true(Ex.is_active(), "a (debug-made) run in every stage below")
	assert_eq(String(Tracker.objective_view()["kind"]), "legacy", "Chapter One step wins")
	_complete_chapter_one()
	assert_eq(String(Tracker.objective_view()["kind"]), "pointer", "the Ward Stone pointer wins")
	_to_lamps()
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "chapter2", "a Chapter Two step wins")
	assert_eq(String(vw["group"]), "lamps")
	for t in Tracker.pending_targets(vw):
		assert_false(String(t["id"]).begins_with("exp_"), "no expedition target on a chapter card")


func test_tracker_node_shows_the_expedition_card() -> void:
	_finish_chapter_two()
	_start_patrol()
	await _spawn_tracker()
	assert_true(tracker.visible)
	assert_eq(tracker.view_kind, "expedition")
	assert_eq(tracker.header.text, "EXPEDITION")
	assert_eq(tracker.title_l.text, "Orchard Patrol")
	var rows: Array = tracker.shown_rows()
	assert_eq(rows.size(), Ex.stop_count("orchard_patrol") + 1)
	assert_false(bool(rows[0]["done"]))
	assert_true(tracker.where_l.visible)
	assert_true(tracker.where_l.text.contains("Scarecrow Meadow"))
	# a defeat updates the card (Events.objectives_changed)
	var a := Ex.active()
	var s: Dictionary = Ex.current_plan()["stops"][0]
	for e in s["enemies"]:
		assert_true(Ex.record_defeat("orchard_patrol", int(a["run"]), 0, String(e)))
	await wait_frames(1)
	rows = tracker.shown_rows()
	assert_true(bool(rows[0]["done"]), "the first stop is ticked")
	assert_true(tracker.where_l.text.contains("Western Hedgerow"), "the where line moves on")
	assert_true(Ex.abandon())
	await wait_frames(1)
	assert_eq(tracker.view_kind, "signpost", "set aside: the signpost is back")


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
	var vrows: Array = Tracker.objective_view()["rows"]
	# every lamp found: the card leaves out the done search's rows (R3-03), the view keeps them
	var card_rows := _road_rows(vrows)
	assert_eq(card_rows.size(), vrows.size() - 3, "the view still has the three search rows")
	assert_eq(rows.size(), card_rows.size(), "one row per card row (pooled rows reused, extras hidden)")
	assert_eq(_labels(rows), _labels(card_rows))
	var lamps := _counted(_road_rows(vrows))
	assert_eq(lamps.size(), 3, "three lamp rows")
	var done_by_label := {}
	for r in rows:
		done_by_label[String(r["label"])] = bool(r["done"])
	assert_eq([bool(done_by_label[String(lamps[0]["label"])]), bool(done_by_label[String(lamps[1]["label"])]),
		bool(done_by_label[String(lamps[2]["label"])])], [false, true, false])
	for vr in vrows:
		if String((vr as Dictionary).get("step", "")) == "ch2_quarry":
			assert_true(bool(vr["done"]), "every row of the lit quarry step reads done (display rows too): %s" % vr["label"])
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


## R3-03: once all three lamps are found (ch2_outer_lamps done) the HUD card drops the search's three
## "Find the ... lamp" rows (it listed up to 8 rows) and keeps the lamp roads; the journal / map view
## (objective_view, shared with journal_panel.gd and map_panel.gd) keeps them, ticked.
func test_tracker_card_drops_the_lamp_search_rows_once_found() -> void:
	_accept()
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_found_quarry_lamp"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	await _spawn_tracker()
	assert_eq(tracker.title_l.text, "Three Roads, Three Lamps")
	var search := ["Find the orchard lamp", "Find the quarry lamp", "Find the manor lamp"]
	var vw := Tracker.objective_view()
	assert_false(GameState.chapter2.is_done("ch2_outer_lamps"), "one lamp still unfound")
	assert_eq(_labels(tracker.shown_rows()), _labels(vw["rows"]), "search open: the card lists every row")
	for l in search:
		assert_true(l in _labels(tracker.shown_rows()), "search open: '%s' on the card" % l)
	# the last lamp found: the search is done and its rows leave the card
	GameState.set_flag("ch2_found_manor_lamp")
	GameState.chapter2.evaluate()               # emits objectives_changed
	await wait_frames(1)
	assert_true(GameState.chapter2.is_done("ch2_outer_lamps"))
	vw = Tracker.objective_view()
	var shown := _labels(tracker.shown_rows())
	for l in search:
		assert_false(l in shown, "'%s' left the HUD card" % l)
	assert_eq(shown, _labels(_road_rows(vw["rows"])), "the card keeps every lamp-road row, in order")
	assert_eq(_labels(_counted(_road_rows(vw["rows"]))), ["Light the garden lamp", "Light the quarry lamp", "Light the manor lamp"])
	assert_eq(tracker.title_l.text, "Three Roads, Three Lamps", "same group card")
	# the journal keeps them, ticked
	var in_view := {}
	for r in vw["rows"]:
		in_view[String(r["label"])] = bool(r["done"])
	for l in search:
		assert_true(in_view.has(l) and bool(in_view[l]), "the journal view still lists '%s', ticked" % l)
	assert_eq(String(vw["parts"][0]["id"]), "ch2_outer_lamps")
	assert_eq((vw["parts"][0]["rows"] as Array).size(), 3, "the search part keeps its three rows")


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
