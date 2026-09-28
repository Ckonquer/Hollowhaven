extends "res://tests/unit/test_core_base.gd"
## Schema-v2 migration matrix (MP §20.2; docs/SAVE_MIGRATION.md). Every scenario is a committed fixture
## file under res://tests/fixtures/saves/ (built by tests/unit/ch2_save_fixtures.gd from real GameState
## calls). Each one is loaded through SaveSystem in user://test_saves/<suite>/ and checked:
## * canonical pre/post: every field MP §2.1 preserves (structures uid/type/area/pos/rot/data, chest
##   bindings/contents/order, crops, inventory quantities & order, key pouch, hotbar, companions, flags,
##   quest index/completed, lore, clock, counters, dropped ...) - only documented additive changes;
## * the pre-v2 upgrade backup holds the untouched v1 bytes and is made once; loading never writes;
## * the written v2 file preserves the same fields; save -> load is stable;
## * gameplay evaluation after loading, saving and loading again grants nothing twice.
## The first v2 write of every scenario is copied to user://test_saves/test_save_v2_matrix/migrated/
## (<name>.v2.json) for tools/qa/save_integrity.py.

const Fixtures := preload("res://tests/unit/ch2_save_fixtures.gd")
const MIGRATED := "user://test_saves/test_save_v2_matrix/migrated"


func setup() -> void:
	assert_true(SaveSystem.save_dir.begins_with("user://test_saves/"), "tests only touch user://test_saves")
	SaveSystem.delete_test_saves()
	fresh_state()
	GameState.active = false


func teardown() -> void:
	SaveSystem.delete_test_saves()
	SaveSystem.replace_future_allowed = false
	SaveSystem.blocked_by_future = false
	Fixtures.remove_fake_items()
	for id in ["moon_harp", "star_jelly", "comet_mail", "sky_key", "meteor_chunk", "older_orphan"]:
		ItemDB._items.erase(id)


# --- helpers -------------------------------------------------------------------------------------------------

func _main() -> String:
	return SaveSystem.save_dir.path_join("slot1.json")


func _bak() -> String:
	return SaveSystem.save_dir.path_join("slot1.bak.json")


func _files_in(dir: String, prefix: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.begins_with(prefix):
				out.append(f)
	out.sort()
	return out


func _upgrade_backups() -> Array:
	return _files_in(SaveSystem.upgrade_backup_dir(), "slot1.")


func _install(name: String) -> Dictionary:
	var f := Fixtures.load_files(name)
	assert_ne(String(f["main"]), "", name + ": fixture file exists (res://tests/fixtures/saves/%s.json)" % name)
	write_text(_main(), f["main"])
	if String(f["bak"]) != "":
		write_text(_bak(), f["bak"])
	return f


## Parses JSON quietly (JSON.parse_string logs an engine error for the torn fixture).
func _json(text: String) -> Variant:
	var j := JSON.new()
	return j.data if text != "" and j.parse(text) == OK else null


func _parse(text: String) -> Dictionary:
	var d: Variant = _json(text)
	return d if d is Dictionary else {}


func _state_now() -> Dictionary:
	return json_norm(GameState.to_dict())


## The full v1 scenario check. Returns {"pre", "post", "after_eval"} (JSON-normalised states).
func _check_v1(name: String, with_bak_backup: bool = false) -> Dictionary:
	var f := _install(name)
	var pre: Dictionary = _parse(f["main"]).get("state", {})
	assert_true(SaveSystem.load_game(), name + ": loads")
	assert_eq(SaveSystem.last_error, "", name + ": no error")
	assert_eq(read_text(_main()), f["main"], name + ": loading never rewrites the v1 file")
	var ups := _upgrade_backups()
	assert_eq(ups.size(), 2 if with_bak_backup else 1, name + ": upgrade backup files %s" % str(ups))
	if ups.size() >= 1:
		assert_true(String(ups[ups.size() - 1]).begins_with("slot1.v1-"), name + ": main copy name " + str(ups))
		assert_eq(read_text(SaveSystem.upgrade_backup_dir().path_join(ups[ups.size() - 1])), f["main"], name + ": v1 bytes kept")
	var post := _state_now()
	assert_eq(Fixtures.preserved_diff(pre, post), [], name + ": everything preserved on load")
	assert_eq(Fixtures.missing_v2_sections(post), [], name + ": every v2 section present")
	assert_eq(int(post["schema"]), 2)
	# The first v2 write.
	assert_true(SaveSystem.save_game(true), name + ": saves as v2")
	var written := _parse(read_text(_main()))
	assert_eq(int(written.get("version", 0)), 2, name + ": version 2 on disk")
	assert_eq(Fixtures.preserved_diff(pre, written.get("state", {})), [], name + ": the written v2 file preserves everything")
	assert_eq(_upgrade_backups(), ups, name + ": backup made once, untouched by the write")
	write_text(MIGRATED.path_join(name + ".v2.json"), read_text(_main()))
	# Reload: identical (migration is idempotent, the round trip is stable).
	GameState.reset()
	assert_true(SaveSystem.load_game(), name + ": v2 reloads")
	assert_deep_eq(_state_now(), post, name + " second load")
	# Gameplay evaluation, save, load, evaluate again: nothing is granted twice.
	GameState.active = true
	GameState._do_eval()
	var after_eval := _state_now()
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	GameState.active = true
	GameState._do_eval()
	assert_deep_eq(_state_now(), after_eval, name + " re-evaluated after reload")
	GameState.active = false
	return {"pre": pre, "post": post, "after_eval": after_eval}


# --- the committed files match the builders --------------------------------------------------------------

func test_fixture_files_match_the_builders() -> void:
	if Debug.has_arg("write-fixtures") and Debug.is_cheat_allowed():
		var paths := Fixtures.write_all()
		print("ch2_save_fixtures: wrote %d files" % paths.size())
	for name in Fixtures.scenario_names():
		var built := Fixtures.build(name)
		var files := Fixtures.load_files(name)
		for part in ["main", "bak"]:
			var a := String(built[part])
			var b := String(files[part])
			var pa: Variant = _json(a)
			var pb: Variant = _json(b)
			if pa is Dictionary and pb is Dictionary:
				var diff := deep_diff(json_norm(pb), json_norm(pa), name + "." + part)
				assert_eq(diff, "", "fixture file is stale (regenerate: see ch2_save_fixtures.gd)")
			else:
				assert_eq(b, a, "%s.%s fixture text is stale (regenerate: see ch2_save_fixtures.gd)" % [name, part])
	GameState.reset()


# --- MP §20.2 scenarios ------------------------------------------------------------------------------------------

func test_01_fresh_new_game() -> void:
	var r := _check_v1("01_fresh_new_game")
	assert_eq(GameState.quests.current_id(), "wake")
	assert_eq(GameState.inventory.size, 32)
	assert_eq(GameState.appearance, GameState.LEGACY_LOOK_IDS, "the Chapter-One look by default")
	assert_false(GameState.chapter2.is_available())
	assert_eq(GameState.ledger, {})


func test_01b_no_save_at_all_changes_nothing() -> void:
	assert_false(SaveSystem.has_save())
	assert_false(SaveSystem.load_game())
	assert_eq(SaveSystem.last_error, "No valid save found.")
	assert_false(DirAccess.dir_exists_absolute(SaveSystem.upgrade_backup_dir()), "no backup folder for nothing")


func test_02_early_before_pets() -> void:
	_check_v1("02_early_before_pets")
	assert_eq(GameState.quests.current_id(), "mochi")
	assert_eq(GameState.quests.baselines["chop"]["trees_felled"], 0, "since_start baseline kept")
	assert_eq(GameState.hotbar_index, 1)


func test_03_mid_home_full_bag_and_waiting_companion() -> void:
	var r := _check_v1("03_mid_home_full_bag")
	assert_eq(GameState.inventory.free_slots(), 0, "the full backpack is still full")
	assert_eq(GameState.inventory.size, 32)
	assert_eq(GameState.companion("mochi")["assignment"], "wait")
	assert_eq(GameState.companion("mochi")["wait_pos"], [5.0, 0.25, -3.0])
	assert_eq(GameState.companion("mochi")["combat_mode"], "assist", "new companion keys get defaults")
	assert_eq(GameState.active_companion, "pebble")
	assert_eq(GameState.quests.current_id(), "lumi")
	var chests := 0
	for uid in GameState.structures:
		if GameState.structures[uid]["id"] == "storage_chest":
			chests += 1
			assert_eq(GameState.get_storage(uid).size, 20, "legacy chests keep 20 slots")
	assert_eq(chests, 2)


func test_04_before_matron_in_the_below() -> void:
	_check_v1("04_before_matron")
	assert_eq(GameState.player["area"], "below")
	assert_eq(GameState.player["below_respawn"], "cp_arena")
	assert_eq(GameState.key_items, {"foreman_key": 1})
	assert_eq(GameState.quests.current_id(), "silk")
	assert_eq(GameState.best_weapon(), "copper_sword", "lower-tier gear still usable")


func test_05_weaver_defeated_heartseed_not_returned() -> void:
	_check_v1("05_weaver_defeated")
	assert_eq(GameState.key_items.get("heartseed", 0), 1)
	assert_eq(GameState.quests.current_id(), "return")
	assert_false(bool(GameState.get_flag("ward_restored")))


func test_06_interrupted_restoration_completes_once() -> void:
	var r := _check_v1("06_interrupted_restoration")
	var post: Dictionary = r["post"]
	assert_false(post["flags"].has("chapter_one_complete"), "loading alone never completes anything")
	var after: Dictionary = r["after_eval"]
	assert_true(bool(after["flags"].get("chapter_one_complete", false)), "evaluation reconciles the legitimate completion")
	assert_eq(int(after["quests"]["index"]), 15, "on free_play")
	var banners := 0
	for s in after["inventory"]:
		if s is Dictionary and s["id"] == "haven_banner":
			banners += int(s["count"])
	assert_eq(banners, 1, "the banner is granted exactly once across reloads")
	assert_eq(GameState.count_item("haven_banner"), 1)


func test_07_complete_at_free_play_goals_not_done() -> void:
	_check_v1("07_c1_complete_free_play")
	assert_eq(GameState.quests.current_id(), "free_play")
	assert_false(GameState.optional_goals.is_done("opt_legacy_bond"))
	assert_false(GameState.optional_goals.is_done("opt_legacy_heartbloom"))
	assert_true(GameState.chapter2.is_available(), "Chapter Two can be offered")
	assert_false(GameState.chapter2.is_active(), "but it never starts by itself")
	assert_eq(GameState.current_objective()["source"], "legacy")
	assert_eq(GameState.count_structures("haven_banner"), 1)


func test_08_complete_with_free_play_goals_done_marks_them_silently() -> void:
	var f := _install("08_c1_complete_goals_done")
	var notes := record(Events.notify, 2)
	var done := record(Events.optional_goal_completed, 1)
	assert_true(SaveSystem.load_game())
	assert_true(GameState.optional_goals.is_done("opt_legacy_bond"))
	assert_true(GameState.optional_goals.is_done("opt_legacy_heartbloom"))
	assert_eq(done, [], "silent: no completion event")
	for n in notes:
		assert_false(String(n[0]).begins_with("Optional goal complete"), "silent: no toast (%s)" % n[0])
	assert_false(GameState.ledger.has("rw_opt_legacy_bond"), "no reward ledger entry for a silent carry-over")
	GameState.reset()
	SaveSystem.delete_test_saves()
	_check_v1("08_c1_complete_goals_done")
	assert_eq(done, [], "evaluation does not complete them again")


func test_09_dense_two_storey_home_with_overflow() -> void:
	var r := _check_v1("09_dense_home_overflow")
	var pre: Dictionary = r["pre"]
	assert_eq(GameState.structures.size(), (pre["structures"] as Dictionary).size(), "every structure")
	var raised := 0
	for uid in GameState.structures:
		if float(GameState.structures[uid]["pos"][1]) > 2.0:
			raised += 1
	assert_true(raised >= 30, "the raised storey is still up there (%d)" % raised)
	assert_eq(GameState.dropped.size(), 4, "dropped items kept (one in the Below, three at home)")
	var banner_drop := false
	for dr in GameState.dropped:
		banner_drop = banner_drop or (dr["item"] == "haven_banner" and dr["area"] == "surface")
	assert_true(banner_drop, "the overflowed banner is still waiting at home")
	assert_eq(GameState.crops.size(), 5)


func test_10_custom_save_dir() -> void:
	SaveSystem.set_save_dir("user://test_saves/test_save_v2_matrix/custom test dir/My Saves")
	var r := _check_v1("10_custom_save_dir")
	assert_eq(GameState.player_name, "Krys")
	assert_true(SaveSystem.upgrade_backup_dir().begins_with("user://test_saves/test_save_v2_matrix/custom test dir/My Saves"),
		"the upgrade backup lives next to the custom save")
	assert_eq(_upgrade_backups().size(), 1)
	SaveSystem.delete_test_saves()
	assert_false(FileAccess.file_exists(_main()))


func test_11_current_schema_loaded_twice() -> void:
	Fixtures.install_fake_items()
	var f := _install("11_current_schema_twice")
	var pre: Dictionary = _parse(f["main"])["state"]
	assert_true(SaveSystem.load_game())
	assert_eq(_upgrade_backups(), [], "a v2 save needs no upgrade backup")
	var post := _state_now()
	assert_eq(Fixtures.preserved_diff(pre, post), [])
	for k in ["appearance", "wardrobe", "equipment", "capacity", "optional", "chapter2", "ledger", "mastery",
			"discovered", "trials", "orphans", "stations"]:
		assert_deep_eq(post[k], json_norm(pre[k]), "v2 section " + k)
	assert_eq(GameState.inventory.size, 40)
	assert_eq(GameState.inventory.get_slot(36), {"id": "fixture_charm", "count": 1})
	assert_eq(GameState.equipment["head"], "fixture_hood")
	assert_eq(GameState.chapter2.current_steps()[0]["id"], "ch2_outer_lamps")
	# Load twice with gameplay evaluation in between: no duplicated rewards, items or ledger entries.
	GameState.active = true
	GameState._do_eval()
	var first := _state_now()
	assert_true(SaveSystem.save_game(true))
	for i in 2:
		GameState.reset()
		assert_true(SaveSystem.load_game())
		GameState.active = true
		GameState._do_eval()
		assert_deep_eq(_state_now(), first, "load #%d" % (i + 2))
		assert_true(SaveSystem.save_game(true))
	GameState.active = false


func test_12a_malformed_main_with_valid_backup() -> void:
	var f := _install("12a_malformed_main_good_bak")
	var pre: Dictionary = _parse(f["bak"])["state"]
	assert_true(SaveSystem.load_game())
	assert_true(SaveSystem.recovered_from_backup)
	assert_eq(_files_in(SaveSystem.save_dir, "slot1.corrupt").size(), 1, "the torn main is kept for inspection")
	var ups := _upgrade_backups()
	assert_eq(ups.size(), 1)
	if ups.size() == 1:
		assert_true(String(ups[0]).begins_with("slot1.bak.v1-"), str(ups))
		assert_eq(read_text(SaveSystem.upgrade_backup_dir().path_join(ups[0])), f["bak"], "backup bytes kept")
	assert_eq(Fixtures.preserved_diff(pre, _state_now()), [])
	assert_true(SaveSystem.save_game(true))
	assert_true(SaveSystem.save_game(true))
	assert_eq(_upgrade_backups(), ups, "the v1 copy survives rotation of the old backup")


func test_12b_future_main_is_refused_in_place() -> void:
	var f := _install("12b_future_main")
	GameState.give_item("wood", 9)
	assert_true(SaveSystem.has_save(), "Continue/New Game know a save is there")
	assert_eq(SaveSystem.peek(), {}, "nothing to continue from")
	assert_true(SaveSystem.blocked_by_future)
	assert_false(SaveSystem.load_game())
	assert_eq(SaveSystem.last_error, "This save was made by a newer version of Hollowhaven.")
	assert_eq(SaveSystem.future_version, 3)
	assert_false(SaveSystem.recovered_from_backup, "no quiet fallback to the older backup")
	assert_eq(GameState.count_item("wood"), 9, "current state untouched")
	assert_eq(read_text(_main()), f["main"], "future main untouched")
	assert_eq(read_text(_bak()), f["bak"], "backup untouched")
	assert_eq(_files_in(SaveSystem.save_dir, "slot1.corrupt"), [], "not treated as corrupt")
	assert_eq(_upgrade_backups(), [], "nothing written")
	# A save without the player's permission is refused and changes nothing.
	expect_error("save failed")
	assert_false(SaveSystem.save_game(true))
	assert_eq(SaveSystem.last_error, SaveSystem.FUTURE_ERROR)
	assert_eq(read_text(_main()), f["main"])
	assert_false(FileAccess.file_exists(SaveSystem.save_dir.path_join("slot1.tmp")))
	# New Game confirmed: the future save is set aside (never deleted) and the new game saves.
	GameState.new_game()
	SaveSystem.replace_future_allowed = true
	assert_true(SaveSystem.save_game(true))
	assert_false(SaveSystem.replace_future_allowed, "permission consumed")
	var aside := _files_in(SaveSystem.save_dir, "slot1.future-3-")
	assert_eq(aside.size(), 1, str(aside))
	if aside.size() == 1:
		assert_eq(read_text(SaveSystem.save_dir.path_join(aside[0])), f["main"], "set aside byte for byte")
	assert_eq(int(_parse(read_text(_main()))["version"]), 2)
	assert_eq(_upgrade_backups().size(), 1, "the v1 backup was copied before the first v2 write")
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.quests.current_id(), "wake", "the new journey loads")


# --- real-build samples: files the SHIPPED game wrote (QA bot playthroughs, not Krystal's save) ----------------

func test_real_samples_are_untouched_copies() -> void:
	for name in Fixtures.real_sample_names():
		var f := Fixtures.load_files(name)
		var info: Dictionary = Fixtures.REAL_SAMPLES[name]
		assert_eq(String(f["main"]).sha256_text(), info["sha256"], name + ": the committed copy is byte-identical to its source")
		assert_eq(String(f["bak"]).sha256_text(), info["sha256_bak"], name + ".bak: byte-identical")
		var d := _parse(f["main"])
		assert_eq(int(d.get("version", 0)), 1, name + ": written by a version-1 build")
		assert_true(String(d.get("game_version", "")).begins_with("0.9"), name + ": " + str(d.get("game_version")))


func test_16_real_handoff_sample_chapter_one_complete() -> void:
	var r := _check_v1("16_real_handoff_c1_complete", true)
	var pre: Dictionary = r["pre"]
	var post: Dictionary = r["post"]
	assert_eq(GameState.quests.current_id(), "free_play")
	assert_true(bool(GameState.get_flag("chapter_one_complete")))
	assert_true(bool(GameState.get_flag("ward_restored")))
	assert_true(GameState.chapter2.is_available(), "Chapter Two can be offered")
	assert_false(GameState.chapter2.is_active(), "but it never starts by itself")
	assert_eq(GameState.current_objective()["source"], "legacy")
	assert_eq(GameState.structures.size(), (pre["structures"] as Dictionary).size())
	assert_eq(GameState.active_companion, "lumi")
	assert_eq(GameState.companion("lumi")["zones"], pre["companions"]["lumi"]["zones"], "companion_logic keys survive")
	assert_eq(GameState.companion("pebble")["work_xp"], 2)
	assert_eq(GameState.appearance, GameState.LEGACY_LOOK_IDS, "she still looks like herself")
	assert_eq(GameState.inventory.size, 32)
	var after: Dictionary = r["after_eval"]
	assert_deep_eq(after["inventory"], post["inventory"], "evaluating a finished Chapter One gives nothing")
	assert_deep_eq(after["key_items"], post["key_items"])
	assert_deep_eq(after["ledger"], {}, "no reward recorded just by loading and evaluating")
	assert_deep_eq(after["dropped"], post["dropped"])
	assert_eq(int(after["quests"]["index"]), 15)


func test_16b_real_handoff_backup_when_the_main_is_torn() -> void:
	var f := Fixtures.load_files("16_real_handoff_c1_complete")
	write_text(_main(), String(f["main"]).substr(0, 900))   # a torn write of the real file
	write_text(_bak(), f["bak"])
	var pre: Dictionary = _parse(f["bak"])["state"]
	assert_true(SaveSystem.load_game())
	assert_true(SaveSystem.recovered_from_backup)
	assert_eq(Fixtures.preserved_diff(pre, _state_now()), [], "the real backup loads with everything preserved")
	assert_eq(GameState.quests.current_id(), "return")
	assert_eq(GameState.key_items.get("heartseed", 0), 1)
	var ups := _upgrade_backups()
	assert_eq(ups.size(), 1)
	if ups.size() == 1:
		assert_eq(read_text(SaveSystem.upgrade_backup_dir().path_join(ups[0])), f["bak"], "the v1 backup bytes are kept")
	assert_eq(_files_in(SaveSystem.save_dir, "slot1.corrupt").size(), 1, "the torn main is kept for inspection")


func test_17_real_release_sample_in_the_below() -> void:
	var r := _check_v1("17_real_release_below_silk", true)
	var pre: Dictionary = r["pre"]
	assert_eq(GameState.player["area"], "below")
	assert_eq(GameState.key_items, {"foreman_key": 1})
	assert_eq(GameState.quests.current_id(), "silk")
	assert_eq(GameState.dropped.size(), (pre["dropped"] as Array).size(), "the dropped item is still there")
	assert_false(GameState.chapter2.is_available())
	var after: Dictionary = r["after_eval"]
	assert_eq(int(after["quests"]["index"]), 13, "nothing advances by itself")
	assert_deep_eq(after["ledger"], {})


# --- extra cases (state map §12 g) ----------------------------------------------------------------------------

func test_13_empty_state_loads_with_defaults() -> void:
	_check_v1("13_state_empty")
	assert_eq(GameState.quests.current_id(), "wake")
	assert_eq(GameState.inventory.size, 32)


func test_14_stuck_dungeon_step_with_ward_restored_repairs_once() -> void:
	var r := _check_v1("14_stuck_dungeon_ward_restored")
	var after: Dictionary = r["after_eval"]
	assert_eq(int(after["quests"]["index"]), 15, "skipped dungeon steps pass, return completes")
	assert_true(bool(after["flags"].get("chapter_one_complete", false)))
	assert_eq(GameState.count_item("haven_banner"), 1, "banner once")


func test_15_v2_unknown_ids_are_kept_and_written_back() -> void:
	var f := _install("15_v2_unknown_ids")
	var pre: Dictionary = _parse(f["main"])["state"]
	assert_true(SaveSystem.load_game())
	assert_eq(Fixtures.preserved_diff(pre, _state_now()), [], "unknown ids moved to orphans, nothing else changed")
	var where := {}
	for o in GameState.orphans:
		where[String(o["stack"]["id"])] = [String(o["where"]), int(o["slot"])]
	assert_eq(where.get("moon_harp"), ["inventory", 12])
	assert_eq(String(where.get("star_jelly", [""])[0]).begins_with("storage:"), true)
	assert_eq(int(where.get("star_jelly", ["", -1])[1]), 3)
	assert_eq(where.get("comet_mail"), ["equipment", 1])
	assert_eq(where.get("sky_key"), ["key_items", -1])
	assert_eq(where.get("meteor_chunk"), ["dropped", -1])
	assert_eq(where.get("older_orphan"), ["inventory", 30])
	assert_eq(GameState.equipment.get("back"), "cape_of_tomorrow", "unknown equipment slot kept")
	assert_true(GameState.structures.has("s800"), "unknown structure kept")
	assert_eq(GameState.extra.get("chapter3"), {"done": [], "note": "from a newer patch"})
	assert_eq(GameState.companion("mochi").get("mood"), "sleepy")
	assert_true(GameState.companions.has("pipkin"))
	assert_true(GameState.optional_goals.records.has("opt_from_the_future"))
	assert_true(GameState.chapter2.done.has("ch2_step_from_the_future"))
	var post := _state_now()
	assert_true(SaveSystem.save_game(true))
	var written: Dictionary = _parse(read_text(_main()))["state"]
	assert_deep_eq(written, post, "written back")
	assert_eq(written["storages"]["s800"], json_norm(pre["storages"]["s800"]), "chest of an unknown structure kept verbatim")
	assert_eq(written["chapter3"], json_norm(pre["chapter3"]))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_deep_eq(_state_now(), post, "stable")
	# A later build knows the ids again: everything returns to where it was.
	for id in ["moon_harp", "star_jelly", "comet_mail", "sky_key", "meteor_chunk", "older_orphan"]:
		var d: Dictionary = ItemDB.ITEM_DEFAULTS.duplicate()
		d["id"] = id
		d["name"] = id
		ItemDB._items[id] = d
	ItemDB._items["comet_mail"]["cat"] = "armor"
	ItemDB._items["comet_mail"]["slot"] = "body"
	ItemDB._items["sky_key"]["cat"] = "key"
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.orphans, [], "every orphan restored")
	assert_eq(GameState.inventory.get_slot(12), {"id": "moon_harp", "count": 1})
	assert_eq(GameState.inventory.get_slot(30), {"id": "older_orphan", "count": 2})
	assert_eq(GameState.equipment["body"], "comet_mail")
	assert_eq(GameState.key_items.get("sky_key"), 1)
	var found := false
	for dr in GameState.dropped:
		if dr["item"] == "meteor_chunk" and int(dr["count"]) == 2:
			found = true
	assert_true(found, "dropped item restored")
