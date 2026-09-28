extends "res://tests/unit/test_core_base.gd"
## B11 QA telemetry additions (src/qa/qa_telemetry.gd, read-only): area / zone / map kind / discoveries, the
## Chapter Two step state, what the tracker shows, optional goals, equipment, companion signature cooldowns
## and the music cue, plus the new message kinds. Nothing here may change game state.

const QaTelemetry := preload("res://src/qa/qa_telemetry.gd")

var qa: Node
var _area_before := ""
var _zone_before := ""


func setup() -> void:
	fresh_state()
	GameState.active = true
	_area_before = Game.area_id
	_zone_before = Game.zone_id
	qa = QaTelemetry.new()      # no setup(): no file, _process writes nothing
	add_child(qa)
	await wait_frames(1)


func teardown() -> void:
	if qa != null and is_instance_valid(qa):
		qa.queue_free()
	qa = null
	await wait_frames(1)
	Game.area_id = _area_before
	Game.zone_id = _zone_before


func _accept_to_lamps() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	for f in ["ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_found_quarry_lamp", "ch2_found_manor_lamp", "ch2_garden_lamp_lit"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()


func test_progress_snapshot_fields() -> void:
	_accept_to_lamps()
	Game.area_id = "hallowmere_reach"
	Game.zone_id = "hr_commons"
	GameState.discover("hallowmere_reach", "hr_commons")
	GameState.equipment["charm"] = "gatherers_charm"
	GameState.befriend("pebble")
	GameState.stats["play_seconds"] = 100.0
	GameState.companions["pebble"]["skill_ready_at"] = 112.5
	var before := JSON.stringify(GameState.to_dict())
	var p: Dictionary = qa.progress_snapshot()
	assert_eq(JSON.stringify(GameState.to_dict()), before, "read-only: state unchanged")
	for k in ["area_info", "chapter2", "tracker", "optional", "equipment", "companion_skills", "music"]:
		assert_true(p.has(k), "has " + k)
	var a: Dictionary = p["area_info"]
	assert_eq([a["area"], a["zone"], a["map"]], ["hallowmere_reach", "hr_commons", "reach"])
	assert_eq(a["discovered"], ["hr_commons"])
	var c2: Dictionary = p["chapter2"]
	assert_true(bool(c2["available"]) and bool(c2["active"]))
	assert_false(bool(c2["finished"]))
	assert_eq(int(c2["chapter"]), 2)
	assert_eq(c2["current"], ["ch2_quarry", "ch2_manor"])
	assert_eq(String(c2["title"]), "Three Roads, Three Lamps")
	assert_true((c2["done"] as Array).has("ch2_orchard"))
	var tr: Dictionary = p["tracker"]
	assert_eq(String(tr["kind"]), "chapter2")
	assert_eq((tr["targets"] as Array).size(), 2, "the two unlit lamps")
	assert_eq(String(p["equipment"]["charm"]), "gatherers_charm")
	var sk: Dictionary = p["companion_skills"]
	assert_true(sk.has("pebble"))
	assert_false(sk.has("lumi"), "only befriended companions")
	assert_eq(String(sk["pebble"]["skill"]), "stoneheart")
	assert_almost(float(sk["pebble"]["left"]), 12.5, 0.05)
	assert_false(bool(sk["pebble"]["ready"]))
	assert_true(float(sk["pebble"]["cooldown"]) > 0.0)
	var op: Dictionary = p["optional"]
	assert_true((op["pending"] as Array).has("opt_counts_wardrobe"), "Chapter Two goals visible after acceptance")
	assert_false((op["pending"] as Array).has("opt_bramblewatch"), "hidden goals are not listed")


func test_messages_and_music_cue() -> void:
	Events.music_cue_changed.emit("m15")
	Events.chapter2_step_completed.emit("ch2_waygate")
	Events.optional_goal_completed.emit("opt_tailors_cache")
	Events.landmark_discovered.emit("hallowmere_reach", "hr_pools")
	Events.companion_skill_used.emit("mochi", "bloomguard")
	Events.equipment_changed.emit("head", "padded_hood")
	var kinds: Array = []
	for m in qa._messages:
		kinds.append(String(m["k"]) + "|" + String(m["text"]))
	for want in ["music|m15", "quest|ch2 completed ch2_waygate", "quest|optional completed opt_tailors_cache",
			"discover|hallowmere_reach:hr_pools", "skill|mochi: bloomguard", "equip|head=padded_hood"]:
		assert_true(kinds.has(want), "message " + want)
	assert_eq(String(qa.progress_snapshot()["music"]["cue"]), "m15")


func test_snapshot_merges_progress_and_stays_json() -> void:
	_accept_to_lamps()
	qa._progress = qa.progress_snapshot()
	var d: Dictionary = qa._snapshot()
	assert_true(d.has("chapter2") and d.has("tracker") and d.has("companion_skills"))
	assert_true(d.has("objective"), "the combined objective stays")
	var txt := JSON.stringify(d)
	assert_true(txt.length() > 10)
	var back: Variant = JSON.parse_string(txt)
	assert_true(back is Dictionary, "serialisable")


func test_legacy_and_pointer_states() -> void:
	var p: Dictionary = qa.progress_snapshot()
	assert_eq(String(p["tracker"]["kind"]), "legacy")
	assert_false(bool(p["chapter2"]["available"]))
	assert_eq(p["chapter2"]["current"], [])
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	p = qa.progress_snapshot()
	assert_eq(String(p["tracker"]["kind"]), "pointer")
	assert_true(bool(p["chapter2"]["available"]))
	assert_false(bool(p["chapter2"]["active"]))
