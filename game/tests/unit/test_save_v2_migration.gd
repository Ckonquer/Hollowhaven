extends "res://tests/unit/test_core_base.gd"
## SaveSystem schema v2 (docs/CHAPTER_TWO_SPEC.md §3, docs/SAVE_MIGRATION.md): pure/idempotent migrate(),
## file classification (ok / missing / corrupt / future), newer-version refusal in place (main, temp-only,
## backup-only), New Game permission to set a newer save aside, the pre-v2 upgrade backup, the new save
## meta and delete_test_saves() hygiene. Files live in user://test_saves/<suite> only.

const Fixtures := preload("res://tests/unit/ch2_save_fixtures.gd")


func setup() -> void:
	assert_true(SaveSystem.save_dir.begins_with("user://test_saves/"), "tests only touch user://test_saves")
	SaveSystem.delete_test_saves()
	fresh_state()


func teardown() -> void:
	SaveSystem.delete_test_saves()
	SaveSystem.replace_future_allowed = false
	SaveSystem.blocked_by_future = false


func _p(suffix: String = ".json") -> String:
	return SaveSystem.save_dir.path_join("slot1" + suffix)


func _files(prefix: String, dir: String = "") -> Array:
	var out: Array = []
	var d := DirAccess.open(SaveSystem.save_dir if dir == "" else dir)
	if d:
		for f in d.get_files():
			if f.begins_with(prefix):
				out.append(f)
	out.sort()
	return out


func _future_text(ver: int = 3) -> String:
	return JSON.stringify({"format": "hollowhaven-save", "version": ver, "saved_unix": 5.0, "meta": {"day": 99},
		"state": {"player_name": "Future", "new_shape": [1, 2, 3]}})


func _v1_text() -> String:
	return String(Fixtures.load_files("07_c1_complete_free_play")["main"])


func _v1() -> Dictionary:
	return JSON.parse_string(_v1_text())


# --- version, meta -------------------------------------------------------------------------------------------

func test_save_version_is_2_and_meta_names_the_chapter() -> void:
	assert_eq(SaveSystem.SAVE_VERSION, 2)
	var d := SaveSystem.build_save_data()
	assert_eq(d["version"], 2)
	assert_eq(d["meta"]["chapter"], 1)
	assert_eq(d["meta"]["step"], "wake")
	assert_eq(d["meta"]["step_title"], "A Dim Haven")
	assert_eq(d["state"]["schema"], 2)
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")
	GameState.chapter2.evaluate()
	d = SaveSystem.build_save_data()
	assert_eq(d["meta"]["chapter"], 2)
	assert_eq(d["meta"]["step"], "ch2_waygate")
	assert_eq(d["meta"]["step_title"], "The Hallowmere Way", "the combined accessor's title")
	GameState.quests.from_dict({"index": GameState.quests.steps().size()})
	GameState.chapter2.done = []
	for s in GameState.chapter2.steps():
		GameState.chapter2.done.append(s["id"])
	GameState.set_flag("chapter_two_complete")
	d = SaveSystem.build_save_data()
	assert_eq(d["meta"]["step"], "")
	assert_eq(d["meta"]["step_title"], "Chapter Two complete")


# --- migrate() -------------------------------------------------------------------------------------------------

func test_migrate_is_pure_idempotent_and_only_adds() -> void:
	var v1 := _v1()
	var untouched: Dictionary = v1.duplicate(true)
	var m1 := SaveSystem.migrate(v1)
	assert_deep_eq(v1, untouched, "the argument is not modified")
	assert_eq(int(m1["version"]), 2)
	for k in untouched["state"]:
		if k == "companions":
			continue
		assert_deep_eq(m1["state"][k], untouched["state"][k], "legacy key " + k)
	for id in untouched["state"]["companions"]:
		for k in untouched["state"]["companions"][id]:
			assert_deep_eq(m1["state"]["companions"][id][k], untouched["state"]["companions"][id][k], "companion %s/%s" % [id, k])
		for k in GameState.COMPANION_V2_DEFAULTS:
			assert_deep_eq(m1["state"]["companions"][id][k], GameState.COMPANION_V2_DEFAULTS[k], "new companion key " + k)
	assert_eq(Fixtures.missing_v2_sections(m1["state"]), [])
	assert_deep_eq(m1["state"]["appearance"], GameState.LEGACY_LOOK_IDS)
	assert_deep_eq(m1["state"]["capacity"], {"backpack": 32})
	assert_deep_eq(m1["state"]["optional"], {}, "satisfied goals are not pre-marked")
	assert_deep_eq(m1["state"]["chapter2"], {"accepted": false, "done": [], "baselines": {}})
	for k in ["format", "game_version", "saved_unix", "meta"]:
		assert_deep_eq(m1[k], untouched[k], "top-level " + k)
	var m2 := SaveSystem.migrate(m1)
	assert_deep_eq(m2, m1, "idempotent")
	assert_deep_eq(SaveSystem.migrate(_v1()), m1, "deterministic")


func test_migrate_tolerates_dicts_without_a_usable_state() -> void:
	assert_eq(SaveSystem.migrate({"version": 1}), {"version": 2})
	assert_eq(SaveSystem.migrate({}), {"version": 2})
	assert_eq(SaveSystem.migrate({"version": 1, "state": 5}), {"version": 2, "state": 5})
	assert_eq(SaveSystem.migrate({"version": "one"})["version"], 2)
	assert_eq(int(SaveSystem.migrate({"version": 1.0, "state": {}})["state"]["schema"]), 2)
	assert_eq(SaveSystem.migrate({"version": 2, "state": {}}), {"version": 2, "state": {}}, "v2 data is not re-migrated")


func test_migrate_capacity_follows_the_saved_backpack() -> void:
	var big := []
	big.resize(40)
	assert_deep_eq(SaveSystem.migrate({"version": 1, "state": {"inventory": big}})["state"]["capacity"], {"backpack": 40})
	assert_deep_eq(SaveSystem.migrate({"version": 1, "state": {"inventory": [null]}})["state"]["capacity"], {"backpack": 32})


func test_migrate_keeps_existing_sections_and_unknown_keys() -> void:
	var st := {"ledger": {"rw_x": 3.0}, "mystery": {"a": 1}, "companions": {"mochi": {"work_day": 4, "ribbon": "blue"}, "odd": 7}}
	var m := SaveSystem.migrate({"version": 1, "state": st})
	assert_deep_eq(m["state"]["ledger"], {"rw_x": 3.0}, "an existing section is never replaced")
	assert_deep_eq(m["state"]["mystery"], {"a": 1})
	assert_eq(m["state"]["companions"]["mochi"]["work_day"], 4)
	assert_eq(m["state"]["companions"]["mochi"]["ribbon"], "blue", "existing companion values win")
	assert_eq(m["state"]["companions"]["mochi"]["combat_mode"], "assist")
	assert_eq(m["state"]["companions"]["odd"], 7, "malformed records are left for the loader")


func test_migrate_marks_legacy_free_play_goals_done() -> void:
	var done_state := {"quests": {"index": 16, "completed": ["free_play"]}, "total_minutes": 9000.0}
	var m := SaveSystem.migrate({"version": 1, "state": done_state})
	assert_deep_eq(m["state"]["optional"], {"opt_legacy_bond": {"done": true, "done_at": 9000.0},
		"opt_legacy_heartbloom": {"done": true, "done_at": 9000.0}})
	assert_eq(SaveSystem.migrate({"version": 1, "state": {"quests": {"index": 16.0}}})["state"]["optional"].size(), 2, "index past the end")
	assert_deep_eq(SaveSystem.migrate({"version": 1, "state": {"quests": {"index": 15, "completed": []}}})["state"]["optional"], {},
		"free_play still pending: nothing marked")


# --- file classification -----------------------------------------------------------------------------------------

func test_read_status_classifies_files() -> void:
	assert_eq(SaveSystem._read_status(_p())["status"], "missing")
	write_text(_p(), "garbage")
	assert_eq(SaveSystem._read_status(_p())["status"], "corrupt")
	write_text(_p(), JSON.stringify({"format": "hollowhaven-save", "version": 1}))
	assert_eq(SaveSystem._read_status(_p())["status"], "corrupt", "a current version needs a state")
	write_text(_p(), JSON.stringify({"format": "other", "version": 9, "state": {}}))
	assert_eq(SaveSystem._read_status(_p())["status"], "corrupt", "not ours")
	write_text(_p(), JSON.stringify({"format": "hollowhaven-save", "version": 7}))
	var fut := SaveSystem._read_status(_p())
	assert_eq(fut["status"], "future", "a newer file needs no particular shape")
	assert_eq(fut["version"], 7)
	assert_eq(fut["data"], {})
	write_text(_p(), "{\"format\": \"hollowhaven-save\", \"version\": 1e99999, \"state\": {}}")
	assert_eq(SaveSystem._read_status(_p())["status"], "corrupt", "an infinite version is damage, not the future")
	write_text(_p(), _v1_text())
	var ok := SaveSystem._read_status(_p())
	assert_eq(ok["status"], "ok")
	assert_eq(ok["version"], 1, "the version as written")
	assert_eq(int(ok["data"]["version"]), 2, "data comes back migrated")
	assert_eq(SaveSystem._read_and_validate(_p())["state"]["schema"], 2)


# --- newer versions ----------------------------------------------------------------------------------------------

func test_future_main_is_refused_without_loading_or_writing() -> void:
	write_text(_p(), _future_text())
	write_text(_p(".bak.json"), _v1_text())
	GameState.give_item("wood", 9)
	var loaded := record(Events.game_loaded, 0)
	assert_false(SaveSystem.load_game())
	assert_eq(SaveSystem.last_error, SaveSystem.FUTURE_ERROR)
	assert_eq(SaveSystem.FUTURE_ERROR, "This save was made by a newer version of Hollowhaven.")
	assert_true(SaveSystem.blocked_by_future)
	assert_eq(loaded.size(), 0)
	assert_eq(GameState.count_item("wood"), 9)
	assert_eq(read_text(_p()), _future_text(), "left in place")
	assert_eq(read_text(_p(".bak.json")), _v1_text())
	assert_eq(_files("slot1.corrupt"), [])
	assert_false(DirAccess.dir_exists_absolute(SaveSystem.upgrade_backup_dir()), "no upgrade backup, nothing written")


func test_future_temp_only_blocks_too() -> void:
	write_text(_p(".tmp"), _future_text())
	assert_true(SaveSystem.has_save(), "the title offers Continue (disabled) and asks before New Game")
	assert_eq(SaveSystem.peek(), {})
	assert_true(SaveSystem.blocked_by_future)
	assert_false(SaveSystem.load_game())
	assert_eq(SaveSystem.last_error, SaveSystem.FUTURE_ERROR)
	assert_eq(read_text(_p(".tmp")), _future_text(), "the temp is not promoted, not deleted")
	assert_false(FileAccess.file_exists(_p()))
	expect_error("save failed")
	assert_false(SaveSystem.save_game(true), "a save would destroy it: refused")
	assert_eq(read_text(_p(".tmp")), _future_text())


func test_future_backup_behind_a_corrupt_main_blocks_and_moves_nothing() -> void:
	write_text(_p(), "torn {{")
	write_text(_p(".bak.json"), _future_text(4))
	assert_false(SaveSystem.load_game())
	assert_eq(SaveSystem.last_error, SaveSystem.FUTURE_ERROR)
	assert_eq(SaveSystem.future_version, 4)
	assert_eq(read_text(_p()), "torn {{", "not moved aside either: nothing changes while blocked")
	assert_eq(_files("slot1.corrupt"), [])
	assert_eq(read_text(_p(".bak.json")), _future_text(4))


func test_future_backup_behind_a_valid_main_is_set_aside_by_the_next_save() -> void:
	assert_true(SaveSystem.save_game(true))
	write_text(_p(".bak.json"), _future_text())
	assert_true(SaveSystem.load_game(), "the valid main wins")
	assert_false(SaveSystem.blocked_by_future)
	assert_true(SaveSystem.save_game(true))
	var aside := _files("slot1.future-3-")
	assert_eq(aside.size(), 1, str(aside))
	if aside.size() == 1:
		assert_true(String(aside[0]).ends_with("-bak.json"), aside[0])
		assert_eq(read_text(SaveSystem.save_dir.path_join(aside[0])), _future_text(), "kept byte for byte")
	assert_eq(int(JSON.parse_string(read_text(_p(".bak.json")))["version"]), 2, "normal rotation continues")


func test_new_game_permission_sets_the_future_main_aside_once() -> void:
	write_text(_p(), _future_text())
	expect_error("save failed")
	assert_false(SaveSystem.save_game(true))
	assert_eq(read_text(_p()), _future_text(), "never overwritten without permission")
	SaveSystem.replace_future_allowed = true
	GameState.give_item("wood", 3)
	assert_true(SaveSystem.save_game(true))
	assert_false(SaveSystem.replace_future_allowed, "consumed by that save")
	var aside := _files("slot1.future-3-")
	assert_eq(aside.size(), 1)
	if aside.size() == 1:
		assert_eq(read_text(SaveSystem.save_dir.path_join(aside[0])), _future_text())
	assert_eq(int(JSON.parse_string(read_text(_p()))["version"]), 2)
	assert_false(FileAccess.file_exists(_p(".bak.json")), "the future file is not rotated into the backup")
	assert_true(SaveSystem.save_game(true), "later saves need no permission")
	assert_eq(_files("slot1.future").size(), 1)


# --- pre-v2 upgrade backup -----------------------------------------------------------------------------------------

func test_upgrade_backup_copies_v1_bytes_once_before_the_first_v2_write() -> void:
	var main_text := _v1_text()
	var bak_text := String(Fixtures.load_files("03_mid_home_full_bag")["main"])
	write_text(_p(), main_text)
	write_text(_p(".bak.json"), bak_text)
	assert_true(SaveSystem.load_game())
	var dir := SaveSystem.upgrade_backup_dir()
	assert_eq(dir, SaveSystem.save_dir.path_join("pre_v2_backup"))
	var ups := _files("slot1.", dir)
	assert_eq(ups.size(), 2, str(ups))
	for f in ups:
		var expect := bak_text if String(f).begins_with("slot1.bak.v1-") else main_text
		assert_true(String(f).begins_with("slot1.v1-") or String(f).begins_with("slot1.bak.v1-"), f)
		assert_eq(read_text(dir.path_join(f)), expect, f + " byte for byte")
	assert_true(SaveSystem.upgrade_backup_path.begins_with(dir))
	assert_true(SaveSystem.save_game(true))
	assert_true(SaveSystem.save_game(true))
	assert_eq(_files("slot1.", dir), ups, "never rewritten, never repeated")
	write_text(_p(), main_text)                    # another v1 file appears: the folder already has a backup
	assert_true(SaveSystem.load_game())
	assert_eq(_files("slot1.", dir), ups)


## A folder holding only a backup-file copy (a torn main was once recovered from slot1.bak.json) still gets
## the main copy when a version-1 main shows up later; the backup copy is not repeated.
func test_a_bak_only_upgrade_backup_does_not_block_the_main_copy() -> void:
	var dir := SaveSystem.upgrade_backup_dir()
	write_text(dir.path_join("slot1.bak.v1-1.json"), "an older backup copy")
	write_text(_p(), _v1_text())
	write_text(_p(".bak.json"), _v1_text())
	assert_true(SaveSystem.load_game())
	var mains := _files("slot1.v1-", dir)
	assert_eq(mains.size(), 1, "the v1 main is copied")
	if mains.size() == 1:
		assert_eq(read_text(dir.path_join(mains[0])), _v1_text())
	assert_eq(_files("slot1.bak.v1-", dir), ["slot1.bak.v1-1.json"], "the existing backup copy is not repeated")
	assert_eq(read_text(dir.path_join("slot1.bak.v1-1.json")), "an older backup copy", "and never rewritten")
	var all := _files("slot1.", dir)
	assert_true(SaveSystem.save_game(true))
	assert_true(SaveSystem.save_game(true))
	assert_eq(_files("slot1.", dir), all, "made once")


func test_new_game_over_a_v1_save_backs_it_up_first() -> void:
	write_text(_p(), _v1_text())
	GameState.new_game()
	assert_true(SaveSystem.save_game(true), "New Game saves without loading the old file")
	var ups := _files("slot1.v1-", SaveSystem.upgrade_backup_dir())
	assert_eq(ups.size(), 1)
	if ups.size() == 1:
		assert_eq(read_text(SaveSystem.upgrade_backup_dir().path_join(ups[0])), _v1_text())
	assert_eq(int(JSON.parse_string(read_text(_p(".bak.json")))["version"]), 1, "the old save rotated to the backup as usual")


func test_a_failed_upgrade_backup_refuses_the_v2_write() -> void:
	write_text(_p(), _v1_text())
	write_text(SaveSystem.upgrade_backup_dir(), "a file where the folder should be")
	expect_error("save failed")
	expect_error("Failed")
	expect_error("Condition")
	assert_false(SaveSystem.save_game(true))
	assert_true(SaveSystem.last_error.contains("back up"), SaveSystem.last_error)
	assert_eq(read_text(_p()), _v1_text(), "the v1 file is untouched")
	DirAccess.remove_absolute(SaveSystem.upgrade_backup_dir())
	assert_true(SaveSystem.save_game(true), "works once the backup can be made")
	assert_eq(_files("slot1.v1-", SaveSystem.upgrade_backup_dir()).size(), 1)


# --- test hygiene --------------------------------------------------------------------------------------------------

func test_delete_test_saves_cleans_the_new_files_only() -> void:
	write_text(_p(".future-3-1.json"), "x")
	write_text(_p(".corrupt-1.json"), "x")
	write_text(SaveSystem.upgrade_backup_dir().path_join("slot1.v1-1.json"), "x")
	write_text(SaveSystem.save_dir.path_join("keep_me.txt"), "mine")
	SaveSystem.delete_test_saves()
	assert_eq(_files("slot1"), [])
	assert_false(DirAccess.dir_exists_absolute(SaveSystem.upgrade_backup_dir()))
	assert_eq(read_text(SaveSystem.save_dir.path_join("keep_me.txt")), "mine", "other files are not touched")
	DirAccess.remove_absolute(SaveSystem.save_dir.path_join("keep_me.txt"))
	SaveSystem.save_dir = "user://saves_guard_probe_v2"   # not a test dir: refused, nothing touched
	expect_error("refusing to delete non-test saves")
	SaveSystem.delete_test_saves()
	assert_false(DirAccess.dir_exists_absolute("user://saves_guard_probe_v2"))
