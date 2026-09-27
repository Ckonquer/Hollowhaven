extends "res://tests/unit/test_core_base.gd"
## SaveSystem (autoload/save_system.gd) + GameState.to_dict/from_dict: full-state round trip,
## atomic writes / temp files, corrupt-file recovery, rejection of bad files, backup rotation, peek().
## All files live in SaveSystem.save_dir, which the runner points at user://test_saves/<suite>.

const Layout := preload("res://data/world_layout.gd")
const EXPECTED_STATE_KEYS := ["active_companion", "buffs", "companions", "counters", "crops", "depleted",
	"dropped", "flags", "hotbar_index", "inventory", "key_items", "lore", "next_uid", "player",
	"player_name", "quests", "stats", "storages", "structures", "total_minutes"]


func setup() -> void:
	assert_true(SaveSystem.save_dir.begins_with("user://test_saves/"), "tests only touch user://test_saves")
	_wipe()
	fresh_state()


func teardown() -> void:
	_wipe()


func _cur() -> String:
	return SaveSystem.save_dir.path_join("slot1.json")


func _bak() -> String:
	return SaveSystem.save_dir.path_join("slot1.bak.json")


func _tmp() -> String:
	return SaveSystem.save_dir.path_join("slot1.tmp")


func _corrupt_files() -> Array:
	var out := []
	var d := DirAccess.open(SaveSystem.save_dir)
	if d:
		for f in d.get_files():
			if f.begins_with("slot1.corrupt"):
				out.append(f)
	return out


func _wipe() -> void:
	for p in [_cur(), _bak(), _tmp()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for f in _corrupt_files():
		DirAccess.remove_absolute(SaveSystem.save_dir.path_join(f))


## Wood count stored in a save file (-1 if unreadable).
func _wood_in(path: String) -> int:
	var json := JSON.new()
	if json.parse(read_text(path)) != OK:
		return -1
	var d = json.data
	if not (d is Dictionary):
		return -1
	var n := 0
	for s in d["state"]["inventory"]:
		if s is Dictionary and s["id"] == "wood":
			n += int(s["count"])
	return n


func _save_with_wood(n: int) -> void:
	GameState.inventory.from_array([])
	GameState.give_item("wood", n)
	assert_true(SaveSystem.save_game(), "save with %d wood" % n)


## A complete save file text for the current state, with an explicit timestamp.
func _save_text(saved_unix: float) -> String:
	var data := SaveSystem.build_save_data()
	data["saved_unix"] = saved_unix
	return JSON.stringify(data, "\t")


# --- full round trip -----------------------------------------------------------------------------------

func _build_rich_state() -> void:
	GameState.player_name = "Krys"
	GameState.give_item("wood", 150)
	GameState.give_item("stone_axe", 1)
	GameState.inventory.set_slot(10, {"id": "berries", "count": 7})
	GameState.inventory.set_slot(31, {"id": "lantern", "count": 1})
	GameState.give_item("foreman_key", 1)
	GameState.select_hotbar(3)
	GameState.player["hp"] = 72.5
	GameState.player["stamina"] = 40.0
	GameState.player["pos"] = [12.5, 1.25, -8.0]
	GameState.player["yaw"] = 1.57
	GameState.player["spawn"] = "bed"
	GameState.player["respawn_area"] = "below"
	GameState.player["respawn_spawn"] = "lantern_2"
	GameState.player["lantern_on"] = true
	GameState.set_flag("read_ward_intro")
	GameState.set_flag("ruin_cleared")
	GameState.set_flag("note", "hello")
	GameState.quests.evaluate()   # -> gather_basics
	GameState.give_item("stone", 2)
	GameState.give_item("fiber", 2)
	GameState.quests.evaluate()   # -> craft_axe (has an axe) -> chop, with a counter baseline
	GameState.add_counter("trees_felled", 4)
	GameState.add_counter("crops_planted")
	GameState.befriend("mochi")
	GameState.befriend("pebble")
	GameState.add_bond("mochi", 30)
	GameState.set_companion_assignment("mochi", "wait", "surface", Vector3(1, 0, 2))
	GameState.companion("mochi")["last_pet_day"] = 2
	GameState.companion("pebble")["last_gift_day"] = 3
	var chest := GameState.add_structure("storage_chest", Vector3(2, 0, 3), 90.0)
	GameState.get_storage(chest).add("wood", 12)
	GameState.get_storage(chest).set_slot(5, {"id": "glowcap", "count": 3})
	var plot := GameState.add_structure("crop_plot", Vector3(-4, 0, 2), 0.0)
	GameState.crops[plot] = {"crop": "sweetroot", "planted_at": 600.5, "tended_minutes": 12.25}
	GameState.add_structure("bed", Vector3(-6, 0, 5), 270.0)
	GameState.structures[chest]["data"] = {"label": "Treasures"}
	GameState.deplete("tree_1", 60.0)
	GameState.deplete("mine_rubble", -1.0)
	GameState.add_dropped("stone", 4, "surface", Vector3(3, 0.5, -1))
	GameState.add_dropped("glowcap", 2, "below", Vector3(-7, -20, 5))
	GameState.discover_lore("ward_intro")
	GameState.discover_lore("foreman_note")
	GameState.total_minutes = 2.0 * 1440.0 + 13.0 * 60.0 + 17.5
	GameState.stats["deaths"] = 2
	GameState.stats["enemies_defeated"] = 5
	GameState.stats["items_crafted"] = 3
	GameState.stats["play_seconds"] = 1234.5
	GameState.add_buff("stamina_regen", 1.6, 42.5)


func test_round_trip_restores_every_field_exactly() -> void:
	var fresh := GameState.to_dict()
	_build_rich_state()
	var before := GameState.to_dict()
	var keys: Array = before.keys()
	keys.sort()
	assert_eq(keys, EXPECTED_STATE_KEYS, "to_dict() fields (update this test when adding state)")
	for k in keys:
		assert_true(deep_diff(before[k], fresh[k], k) != "", "rich state exercises '%s'" % k)
	assert_eq(before["quests"]["index"], 3, "quests advanced to chop")
	assert_true(SaveSystem.save_game())
	GameState.reset()
	GameState.active = false
	assert_true(SaveSystem.load_game())
	assert_true(GameState.active, "a loaded game is active")
	var after := GameState.to_dict()
	for k in keys:
		assert_deep_eq(after[k], before[k], k)   # strict: ints come back as ints
	assert_deep_eq(json_norm(after), json_norm(before), "json")
	# behaviour after load, not only data
	assert_eq(GameState.quests.current_id(), "chop")
	assert_eq(GameState.quests.objective_status()[0]["progress"], 2, "4 trees since the step began, clamped to the target")
	assert_eq(GameState.quests.baselines["chop"]["trees_felled"], 0)
	assert_eq(GameState.bond_level("mochi"), 2)
	assert_eq(GameState.active_companion, "pebble")
	assert_true(GameState.is_depleted("mine_rubble"))
	assert_almost(GameState.buff_mult("stamina_regen"), 1.6)
	assert_eq(GameState.get_storage(GameState.structures.keys()[0]).count_of("glowcap"), 3)


func test_loaded_numbers_have_runtime_types() -> void:
	_build_rich_state()
	GameState.from_dict(json_norm(GameState.to_dict()))
	assert_eq(typeof(GameState.hotbar_index), TYPE_INT)
	assert_eq(typeof(GameState.next_uid), TYPE_INT)
	assert_eq(typeof(GameState.counters["trees_felled"]), TYPE_INT)
	assert_eq(typeof(GameState.key_items["foreman_key"]), TYPE_INT)
	assert_eq(typeof(GameState.companion("mochi")["bond_xp"]), TYPE_INT)
	assert_eq(typeof(GameState.companion("mochi")["last_pet_day"]), TYPE_INT)
	assert_eq(typeof(GameState.inventory.get_slot(0)["count"]), TYPE_INT)
	assert_eq(typeof(GameState.dropped[0]["count"]), TYPE_INT)
	assert_eq(typeof(GameState.stats["deaths"]), TYPE_INT)
	assert_eq(typeof(GameState.stats["play_seconds"]), TYPE_FLOAT)
	assert_eq(typeof(GameState.quests.baselines["chop"]["trees_felled"]), TYPE_INT)


func test_load_emits_signals_and_save_reports_ok() -> void:
	var saved := record(Events.game_saved, 1)
	var loaded := record(Events.game_loaded, 0)
	assert_true(SaveSystem.save_game())
	assert_eq(saved, [[true]])
	assert_true(SaveSystem.load_game())
	assert_eq(loaded.size(), 1)
	assert_false(SaveSystem.recovered_from_backup)
	assert_eq(SaveSystem.last_error, "")


# --- atomic write & temp files -----------------------------------------------------------------------------

func test_leftover_garbage_tmp_is_ignored_and_cleaned() -> void:
	_save_with_wood(4)
	write_text(_tmp(), "{ half a save")
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 4)
	assert_false(SaveSystem.recovered_from_backup)
	assert_false(FileAccess.file_exists(_tmp()), "stale temp file cleaned up")


func test_leftover_valid_tmp_is_ignored_when_main_is_valid() -> void:
	_save_with_wood(4)
	GameState.give_item("wood", 90)
	write_text(_tmp(), _save_text(Time.get_unix_time_from_system() + 1000.0))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 4, "the main file wins")
	assert_false(FileAccess.file_exists(_tmp()))


func test_save_overwrites_leftover_tmp() -> void:
	write_text(_tmp(), "garbage")
	_save_with_wood(6)
	assert_false(FileAccess.file_exists(_tmp()), "temp renamed into place")
	assert_eq(_wood_in(_cur()), 6)
	assert_false(FileAccess.file_exists(_bak()), "no backup of a first save")


func test_crash_between_rotation_and_rename_recovers_newest() -> void:
	_save_with_wood(1)
	_save_with_wood(2)
	# Simulate a crash in save #3 after the current file was rotated to the backup but before the
	# temp file was renamed: cur missing, bak = #2, tmp = complete #3.
	GameState.inventory.from_array([])
	GameState.give_item("wood", 3)
	var text := _save_text(Time.get_unix_time_from_system() + 5.0)
	assert_eq(DirAccess.rename_absolute(_cur(), _bak()), OK)
	write_text(_tmp(), text)
	assert_true(SaveSystem.has_save())
	assert_eq(_wood_in(_tmp()), 3)
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 3, "newest complete save recovered")
	assert_false(SaveSystem.recovered_from_backup, "nothing was lost")
	assert_true(FileAccess.file_exists(_cur()), "temp promoted to the main file")
	assert_false(FileAccess.file_exists(_tmp()))
	_save_with_wood(4)
	assert_eq(_wood_in(_cur()), 4)
	assert_eq(_wood_in(_bak()), 3, "rotation continues normally")


func test_tmp_older_than_backup_is_not_used() -> void:
	GameState.give_item("wood", 2)
	write_text(_bak(), _save_text(2000.0))
	GameState.inventory.from_array([])
	GameState.give_item("wood", 1)
	write_text(_tmp(), _save_text(1000.0))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 2, "backup is newer than the stale temp")
	assert_true(SaveSystem.recovered_from_backup)


# --- corrupt / missing / rejected files -----------------------------------------------------------------------

func test_corrupt_main_restores_backup_and_preserves_corrupt_copy() -> void:
	_save_with_wood(1)
	_save_with_wood(2)
	write_text(_cur(), "garbage {{{")
	var notes := record(Events.notify, 2)
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 1, "previous save restored")
	assert_true(SaveSystem.recovered_from_backup)
	assert_true(notes.has(["Your latest save was damaged, so your previous save was restored.", "warn"]), "player is told")
	var corrupt := _corrupt_files()
	assert_eq(corrupt.size(), 1, "corrupt copy preserved")
	if corrupt.size() == 1:
		assert_eq(read_text(SaveSystem.save_dir.path_join(corrupt[0])), "garbage {{{", "byte-for-byte")
	assert_false(FileAccess.file_exists(_cur()), "moved aside, so it is not re-read")
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(_corrupt_files().size(), 1, "a second load does not duplicate the corrupt copy")


func test_both_missing_fails_cleanly() -> void:
	GameState.give_item("wood", 9)
	assert_false(SaveSystem.has_save())
	assert_eq(SaveSystem.peek(), {})
	assert_false(SaveSystem.load_game())
	assert_eq(SaveSystem.last_error, "No valid save found.")
	assert_eq(GameState.count_item("wood"), 9, "current state untouched")
	assert_true(GameState.active)
	assert_eq(_corrupt_files().size(), 0)


func test_bad_files_are_rejected_without_script_errors() -> void:
	var future := {"format": "hollowhaven-save", "version": SaveSystem.SAVE_VERSION + 1, "state": GameState.to_dict()}
	var cases := {
		"empty": "",
		"blank": "   \n ",
		"garbage": "not json at all",
		"truncated": "{\"format\": \"hollowhaven-save\", \"version\": 1, \"state\": {\"inventory\": [",
		"array": "[1, 2, 3]",
		"string": "\"hello\"",
		"wrong format": JSON.stringify({"format": "other-game", "version": 1, "state": {}}),
		"numeric format": JSON.stringify({"format": 5, "version": 1, "state": {}}),
		"missing format": JSON.stringify({"version": 1, "state": {}}),
		"future version": JSON.stringify(future),
		"version zero": JSON.stringify({"format": "hollowhaven-save", "version": 0, "state": {}}),
		"string version": JSON.stringify({"format": "hollowhaven-save", "version": "1", "state": {}}),
		"dict version": JSON.stringify({"format": "hollowhaven-save", "version": {}, "state": {}}),
		"array state": JSON.stringify({"format": "hollowhaven-save", "version": 1, "state": []}),
		"missing state": JSON.stringify({"format": "hollowhaven-save", "version": 1}),
	}
	GameState.give_item("wood", 9)
	var n := 0
	for name in cases:
		write_text(_cur(), cases[name])
		assert_eq(SaveSystem.peek(), {}, name + ": peek rejects")
		assert_false(SaveSystem.load_game(), name + ": load rejects")
		assert_eq(GameState.count_item("wood"), 9, name + ": state untouched")
		n += 1
		assert_eq(_corrupt_files().size(), n, name + ": preserved for inspection")


func test_valid_minimal_save_loads_with_defaults() -> void:
	write_text(_cur(), JSON.stringify({"format": "hollowhaven-save", "version": 1, "state": {}}))
	GameState.give_item("wood", 9)
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 0)
	assert_eq(GameState.quests.current_id(), "wake")
	assert_eq(GameState.companions.size(), ItemDB.creature_ids().size())


# --- rotation -------------------------------------------------------------------------------------------------------

func test_save_after_load_keeps_backup_rotation_sane() -> void:
	_save_with_wood(1)
	assert_eq([_wood_in(_cur()), _wood_in(_bak())], [1, -1])
	_save_with_wood(2)
	assert_eq([_wood_in(_cur()), _wood_in(_bak())], [2, 1])
	assert_true(SaveSystem.load_game())
	_save_with_wood(3)
	assert_eq([_wood_in(_cur()), _wood_in(_bak())], [3, 2], "load + save rotates the loaded file into the backup")
	# recover from a corrupt main file, then keep playing
	write_text(_cur(), "garbage")
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.count_item("wood"), 2)
	_save_with_wood(4)
	assert_eq([_wood_in(_cur()), _wood_in(_bak())], [4, 2], "the good backup is kept, never replaced by junk")
	_save_with_wood(5)
	assert_eq([_wood_in(_cur()), _wood_in(_bak())], [5, 4])
	assert_eq(_corrupt_files().size(), 1)


func test_corrupt_backup_is_replaced_by_rotation() -> void:
	_save_with_wood(1)
	write_text(_bak(), "junk")
	_save_with_wood(2)
	assert_eq([_wood_in(_cur()), _wood_in(_bak())], [2, 1])


func test_new_game_save_over_corrupt_main_preserves_it() -> void:
	write_text(_cur(), "junk that used to be a save")
	_save_with_wood(3)
	assert_eq(_wood_in(_cur()), 3)
	assert_eq(_corrupt_files().size(), 1, "never deleted blindly")


# --- peek / has_save --------------------------------------------------------------------------------------------------

func test_peek_metadata() -> void:
	GameState.set_flag("read_ward_intro")
	GameState.quests.evaluate()
	GameState.total_minutes = 2.0 * 1440.0 + 9.0 * 60.0
	GameState.stats["play_seconds"] = 321.5
	GameState.player["area"] = "below"
	assert_true(SaveSystem.save_game())
	GameState.reset()
	var p := SaveSystem.peek()
	assert_eq(p["format"], "hollowhaven-save")
	assert_eq(int(p["version"]), SaveSystem.SAVE_VERSION)
	assert_eq(p["game_version"], String(ProjectSettings.get_setting("application/config/version", "0")))
	assert_true(float(p["saved_unix"]) > 0.0)
	assert_eq(int(p["meta"]["day"]), 3)
	assert_eq(p["meta"]["step"], "gather_basics")
	assert_eq(p["meta"]["step_title"], "Gather Supplies")
	assert_almost(float(p["meta"]["play_seconds"]), 321.5)
	assert_eq(p["meta"]["area"], "below")
	assert_true(p["state"] is Dictionary)
	assert_eq(GameState.quests.current_id(), "wake", "peek does not apply the save")


func test_peek_after_chapter_complete_and_backup_fallback() -> void:
	GameState.quests.from_dict({"index": QuestsData.STEPS.size()})
	assert_true(SaveSystem.save_game())
	assert_eq(SaveSystem.peek()["meta"]["step_title"], "Chapter complete")
	assert_eq(SaveSystem.peek()["meta"]["step"], "")
	_save_with_wood(1)
	write_text(_cur(), "junk")
	assert_eq(int(SaveSystem.peek()["meta"]["day"]), 1, "falls back to the backup")
	assert_true(FileAccess.file_exists(_cur()), "peek is read-only")
	assert_eq(_corrupt_files().size(), 0)


func test_has_save() -> void:
	assert_false(SaveSystem.has_save())
	write_text(_tmp(), "junk")
	assert_false(SaveSystem.has_save(), "a broken temp file is not a save")
	write_text(_tmp(), _save_text(10.0))
	assert_true(SaveSystem.has_save(), "a complete temp file is recoverable")
	DirAccess.remove_absolute(_tmp())
	write_text(_bak(), _save_text(10.0))
	assert_true(SaveSystem.has_save(), "backup only")


func test_migrate_keeps_current_version() -> void:
	assert_eq(int(SaveSystem.migrate({"version": 1})["version"]), SaveSystem.SAVE_VERSION)
	assert_eq(int(SaveSystem.build_save_data()["version"]), SaveSystem.SAVE_VERSION)


func test_delete_refuses_non_test_directory() -> void:
	SaveSystem.save_dir = "user://saves_guard_probe"   # not created, nothing is touched
	expect_error("refusing to delete non-test saves")
	SaveSystem.delete_test_saves()
	assert_true(logged("refusing to delete non-test saves"))
	assert_false(DirAccess.dir_exists_absolute("user://saves_guard_probe"))


# --- damaged state dictionaries (valid JSON, wrong content) --------------------------------------------------------------

func test_from_dict_tolerates_wrong_types() -> void:
	GameState.from_dict({"player_name": 5, "inventory": "x", "key_items": [], "hotbar_index": "3", "player": 7,
		"flags": [], "counters": {"a": "b", "c": 2.0}, "quests": 5,
		"companions": {"mochi": "x", "pebble": {"befriended": 1, "bond_xp": "lots", "assignment": 9, "wait_pos": [1, "a", 3]}},
		"active_companion": 3,
		"structures": {"s1": {"id": 5}, "s2": "x", "s3": {"id": "storage_chest", "pos": "here", "rot": "left"}},
		"storages": {"s3": "bad"}, "crops": 1, "depleted": {"a": "b", "t": 5},
		"dropped": [1, {"item": "wood", "count": "x"}, {"item": "wood", "count": 2, "pos": [1, 2]}, {"item": "ghost", "count": 1}],
		"lore": [1, "x", "x"], "total_minutes": "noon", "stats": {"deaths": "many", "play_seconds": 5},
		"buffs": {"a": 1, "b": {"mult": 2, "remaining": 3}, "c": {"mult": 1.5, "remaining": -1.0}}, "next_uid": "9"})
	assert_eq(GameState.player_name, "Krystal")
	assert_true(GameState.inventory.is_empty())
	assert_eq(GameState.hotbar_index, 0)
	assert_eq(GameState.player["hp"], 100.0)
	assert_eq(GameState.flags, {})
	assert_eq(GameState.counters, {"c": 2})
	assert_eq(GameState.companion("mochi")["assignment"], "wild")
	assert_eq(GameState.companion("pebble")["befriended"], true)
	assert_eq(GameState.companion("pebble")["bond_xp"], 0)
	assert_eq(GameState.companion("pebble")["assignment"], "home", "invalid assignment repaired")
	assert_null(GameState.companion("pebble")["wait_pos"])
	assert_eq(GameState.active_companion, "")
	assert_eq(GameState.structures.keys(), ["s3"])
	assert_eq(GameState.structures["s3"]["pos"], [0.0, 0.0, 0.0])
	assert_eq(GameState.structures["s3"]["rot"], 0.0)
	assert_true(GameState.get_storage("s3").is_empty())
	assert_eq(GameState.crops, {})
	assert_eq(GameState.depleted, {"t": 5.0})
	assert_eq(GameState.dropped.size(), 1, "only the valid drop (unknown items skipped)")
	assert_eq(GameState.dropped[0]["pos"], [0.0, 0.0, 0.0])
	assert_ne(GameState.dropped[0]["uid"], "", "missing uid gets a fresh one instead of being discarded")
	assert_eq(GameState.lore, ["x"])
	assert_eq(GameState.total_minutes, 480.0)
	assert_eq(GameState.stats["deaths"], 0)
	assert_eq(GameState.stats["play_seconds"], 5.0)
	assert_eq(GameState.buffs, {"b": {"mult": 2.0, "remaining": 3.0}})
	assert_eq(GameState.quests.current_id(), "wake")
	assert_true(GameState.next_uid > 3, "above the used uid s3")


func test_from_dict_repairs_one_follower() -> void:
	var d := GameState.to_dict()
	for id in ["mochi", "pebble", "lumi"]:
		d["companions"][id]["befriended"] = true
		d["companions"][id]["assignment"] = "follow"
	d["active_companion"] = "lumi"
	GameState.from_dict(json_norm(d))
	assert_eq(GameState.active_companion, "lumi")
	assert_eq([GameState.companion("mochi")["assignment"], GameState.companion("pebble")["assignment"], GameState.companion("lumi")["assignment"]], ["home", "home", "follow"])
	d["active_companion"] = ""
	GameState.from_dict(json_norm(d))
	var followers := 0
	for id in GameState.companions:
		if GameState.companions[id]["assignment"] == "follow":
			followers += 1
			assert_eq(GameState.active_companion, id)
	assert_eq(followers, 1)
	d["active_companion"] = "ghost"
	for id in ["mochi", "pebble", "lumi"]:
		d["companions"][id]["assignment"] = "home"
	GameState.from_dict(json_norm(d))
	assert_eq(GameState.active_companion, "", "a follower id without a following companion is cleared")


func test_from_dict_repairs_uids_crops_and_aliasing() -> void:
	var d := GameState.to_dict()
	d["structures"] = {"s7": {"id": "crop_plot", "area": "surface", "pos": [1, 0, 1], "rot": 0, "data": {}},
		"s8": {"id": "crop_plot", "area": "surface", "pos": [3, 0, 1], "rot": 0, "data": {}}}
	d["crops"] = {"s7": {"crop": "sweetroot", "planted_at": 500, "tended_minutes": 3}, "s99": {"crop": "sweetroot"}}
	d["dropped"] = [{"uid": "d9", "item": "wood", "count": 1, "area": "surface", "pos": [0, 0, 0]},
		{"uid": "d9", "item": "stone", "count": 2, "area": "surface", "pos": [0, 0, 0]}]
	d["next_uid"] = 2
	GameState.from_dict(d)
	assert_eq(GameState.crops.keys().size(), 2, "orphan crop pruned, missing crop record created")
	assert_eq(GameState.crops["s7"], {"crop": "sweetroot", "planted_at": 500.0, "tended_minutes": 3.0})
	assert_eq(GameState.crops["s8"]["crop"], "")
	assert_eq(GameState.dropped.size(), 2, "duplicate uid relabelled, not lost")
	assert_ne(GameState.dropped[0]["uid"], GameState.dropped[1]["uid"])
	assert_true(GameState.next_uid > 10, "next_uid moved above every used uid")
	var s := GameState.new_uid("s")
	assert_false(GameState.structures.has(s), "new uids never collide")
	d["structures"]["s7"]["pos"][0] = 999
	assert_eq(GameState.structures["s7"]["pos"][0], 1.0, "state does not alias the loaded dictionary")


func test_non_finite_numbers_never_brick_or_poison_a_save() -> void:
	# NaN at runtime: JSON writes null, so saving still works and loading falls back to the default.
	GameState.give_item("wood", 3)
	GameState.player["yaw"] = NAN
	GameState.player["pos"] = [1.0, NAN, 2.0]
	assert_true(SaveSystem.save_game(), "a NaN never makes saving fail")
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.player["yaw"], 0.0, "NaN yaw -> default")
	assert_null(GameState.player["pos"], "a position with NaN is dropped (the spawn point is used)")
	assert_eq(GameState.count_item("wood"), 3)
	# INF survives JSON (the engine writes 1e99999 and reads it back as INF): the loader must reject it
	# everywhere, or one runtime glitch would stop the clock / break the player for good.
	var st := GameState.to_dict()
	st["total_minutes"] = "@INF@"
	st["player"]["pos"] = [0.0, "@INF@", 0.0]
	st["player"]["hp"] = "@INF@"
	st["player"]["max_hp"] = "@INF@"
	st["counters"] = {"trees_felled": "@INF@", "ok": 2}
	st["key_items"] = {"foreman_key": "@INF@"}
	st["inventory"] = [{"id": "wood", "count": "@INF@"}, {"id": "stone", "count": 4}]
	st["depleted"] = {"tree_1": "@INF@"}
	st["buffs"] = {"stamina_regen": {"mult": "@INF@", "remaining": 5.0}}
	st["stats"]["play_seconds"] = "@INF@"
	st["quests"] = {"index": "@INF@", "completed": [], "baselines": {"wake": {"x": "@INF@"}}}
	st["companions"]["mochi"]["bond_xp"] = "@INF@"
	var data := {"format": "hollowhaven-save", "version": 1, "saved_unix": "@INF@", "state": st}
	var text := JSON.stringify(data).replace("\"@INF@\"", JSON.stringify(INF))
	assert_true(text.contains("1e99999"), "INF is written the way the engine writes it")
	write_text(_cur(), text)
	assert_true(SaveSystem.load_game(), "still a loadable save")
	assert_almost(GameState.total_minutes, float(Layout.CLOCK["new_game_hour"]) * 60.0, 0.001, "clock falls back")
	assert_eq(GameState.day(), 1)
	assert_true(is_finite(GameState.hour()))
	assert_null(GameState.player["pos"])
	assert_eq(GameState.player["hp"], 100.0)
	assert_eq(GameState.player["max_hp"], 100.0)
	assert_eq(GameState.counters, {"ok": 2})
	assert_eq(GameState.key_items, {})
	assert_eq(GameState.inventory.totals(), {"stone": 4})
	assert_false(GameState.depleted.has("tree_1"))
	assert_eq(GameState.buffs, {})
	assert_eq(GameState.stats["play_seconds"], 0.0)
	assert_eq(GameState.quests.index, 0)
	assert_eq(GameState.quests.baselines.get("wake", {}), {})
	assert_eq(GameState.companion("mochi")["bond_xp"], 0)


func test_load_wakes_player_healthy() -> void:
	var d := GameState.to_dict()
	d["player"]["hp"] = 0.0
	d["player"]["stamina"] = -5.0
	GameState.from_dict(d)
	assert_eq(GameState.player["hp"], 100.0, "a save never leaves Krystal at 0 hp")
	assert_eq(GameState.player["stamina"], 0.0)
	d["player"]["hp"] = 250.0
	d["player"]["pos"] = null
	GameState.from_dict(d)
	assert_eq(GameState.player["hp"], 100.0, "clamped to max_hp")
	assert_null(GameState.player["pos"])
