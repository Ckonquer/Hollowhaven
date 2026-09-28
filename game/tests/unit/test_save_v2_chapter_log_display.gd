extends "res://tests/unit/test_core_base.gd"
## Display rows of the Chapter Two layer (src/core/chapter_log.gd "display": true; R38 / F03, integration pass 2)
## as the player sees them: the tracker / journal view (Tracker.objective_view) lists the quarry step's
## "Calm the Quarry Warden" and "Mend the mineral winch" rows before its lamp row, each with its own done state,
## and once the step is done (the lamp alone completes it) all of its rows read as done.

const Tracker := preload("res://src/ui/hud/tracker.gd")

const QUARRY_ROWS := ["Calm the Quarry Warden", "Mend the mineral winch", "Light the quarry lamp"]


func setup() -> void:
	fresh_state()
	GameState.active = true
	Settings.set_value("arachnophobia", false)


func _to_lamps() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	GameState.set_flag("ch2_accepted")
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_found_quarry_lamp", "ch2_found_manor_lamp"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()


func _quarry_part(vw: Dictionary) -> Dictionary:
	for p in vw.get("parts", []):
		if String(p["id"]) == "ch2_quarry":
			return p
	return {}


func _rows_of(part: Dictionary) -> Array:
	var out: Array = []
	for r in part.get("rows", []):
		out.append([String(r["label"]), bool(r["done"])])
	return out


func test_tracker_view_lists_the_quarry_display_rows_with_their_state() -> void:
	_to_lamps()
	var vw := Tracker.objective_view()
	assert_eq(String(vw["kind"]), "chapter2")
	assert_eq(String(vw["group"]), "lamps")
	var part := _quarry_part(vw)
	assert_false(part.is_empty(), "the quarry step is shown")
	assert_eq(_rows_of(part), [[QUARRY_ROWS[0], false], [QUARRY_ROWS[1], false], [QUARRY_ROWS[2], false]])
	# The Warden calmed: its row ticks, the step stays open (the lamp row still waits).
	GameState.set_flag("hr_warden_defeated")
	GameState.chapter2.evaluate()
	vw = Tracker.objective_view()
	part = _quarry_part(vw)
	assert_eq(_rows_of(part), [[QUARRY_ROWS[0], true], [QUARRY_ROWS[1], false], [QUARRY_ROWS[2], false]])
	assert_false(bool(part["done"]))
	# The flat row list keeps the step order: the lamp search (shown with the lamps since CH2-001), garden,
	# the quarry's three rows, manor.
	var labels: Array = []
	for r in vw["rows"]:
		labels.append(String(r["label"]))
	assert_eq(labels, ["Find the orchard lamp", "Find the quarry lamp", "Find the manor lamp", "Light the garden lamp"] + QUARRY_ROWS + ["Light the manor lamp"])


func test_the_lamp_alone_completes_the_step_and_its_rows_read_done() -> void:
	_to_lamps()
	GameState.set_flag("ch2_quarry_lamp_lit")   # no Warden / winch flag (a fallback or an older save)
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_quarry"))
	var part := _quarry_part(Tracker.objective_view())
	assert_true(bool(part["done"]), "the done step stays listed with the group")
	assert_eq(_rows_of(part), [[QUARRY_ROWS[0], true], [QUARRY_ROWS[1], true], [QUARRY_ROWS[2], true]],
		"a done step reads done on every row")
