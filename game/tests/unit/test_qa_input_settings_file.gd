extends "res://tests/unit/test_core_base.gd"
## --settings-file=<abs path> (Settings.settings_path): QA runs read AND write that file, never the player's real
## user://settings.cfg. Only files under user://test_saves/ are written here.

var _path_backup: String = ""
var _real_cfg_state: Array = []


func setup() -> void:
	_path_backup = Settings.settings_path
	_real_cfg_state = _real_cfg_fingerprint()


func teardown() -> void:
	Settings.settings_path = _path_backup
	var f := _override()
	if FileAccess.file_exists(f):
		DirAccess.remove_absolute(f)
	assert_eq(_real_cfg_fingerprint(), _real_cfg_state, "the real settings.cfg was not touched")


func _real_cfg_fingerprint() -> Array:
	if not FileAccess.file_exists(Settings.PATH):
		return [false]
	return [true, FileAccess.get_modified_time(Settings.PATH), FileAccess.get_file_as_string(Settings.PATH).md5_text()]


func _override() -> String:
	return SaveSystem.save_dir.path_join("qa_run/qa_settings.cfg")


func test_path_from_args() -> void:
	assert_eq(Settings.settings_path_from_args(PackedStringArray([])), Settings.PATH, "no arg: the player's file")
	assert_eq(Settings.settings_path_from_args(PackedStringArray(["--windowed", "--settings-file=C:/qa/run/s.cfg"])), "C:/qa/run/s.cfg")
	assert_eq(Settings.settings_path_from_args(PackedStringArray(["--settings-file=user://test_saves/x.cfg"])), "user://test_saves/x.cfg")
	for bad in ["--settings-file=relative/s.cfg", "--settings-file=", "--settings-file=s.cfg"]:
		var p: String = Settings.settings_path_from_args(PackedStringArray([bad]))
		assert_eq(p, Settings.QA_FALLBACK_PATH, "not absolute -> isolated fallback: " + bad)
		assert_ne(p, Settings.PATH, "never the real file")


func test_save_and_load_use_the_override_file() -> void:
	Settings.settings_path = _override()
	assert_false(FileAccess.file_exists(_override()), "starts empty")
	Settings.set_value("fov", 81.0)
	Settings.set_value("arachnophobia", true)
	Settings.save()        # no argument: the override path (its folder is created)
	assert_true(FileAccess.file_exists(_override()), "written to --settings-file")
	var cf := ConfigFile.new()
	assert_eq(cf.load(_override()), OK)
	assert_eq(cf.get_value("settings", "fov"), 81.0)
	# Edit the file outside the game; load_settings() without an argument reads it back.
	cf.set_value("settings", "fov", 66.0)
	cf.set_value("settings", "master_volume", 0.25)
	cf.save(_override())
	Settings.set_value("fov", 90.0)
	Settings.load_settings()
	assert_eq(Settings.get_value("fov"), 66.0, "read from --settings-file")
	assert_eq(Settings.get_value("master_volume"), 0.25)
	assert_eq(Settings.get_value("arachnophobia"), true)
	assert_eq(_real_cfg_fingerprint(), _real_cfg_state, "user://settings.cfg untouched by save/load")


func test_explicit_paths_still_win() -> void:
	Settings.settings_path = _override()
	var other := SaveSystem.save_dir.path_join("qa_run/other.cfg")
	Settings.set_value("fov", 77.0)
	Settings.save(other)
	assert_true(FileAccess.file_exists(other))
	assert_false(FileAccess.file_exists(_override()), "an explicit path is not redirected")
	DirAccess.remove_absolute(other)
