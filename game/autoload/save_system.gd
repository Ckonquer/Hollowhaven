extends Node
## Versioned JSON saves with atomic writes and a recoverable backup.
## Files (in the user data folder, e.g. %APPDATA%/Hollowhaven/saves):
##   slot1.json      current save
##   slot1.bak.json  previous good save (used if the current one is missing/corrupt)
## Write procedure: serialise -> write slot1.tmp -> re-read and validate tmp -> rotate current to .bak
## -> rename tmp to current. A crash at any point leaves at least one valid file.

const SAVE_VERSION := 1
const DEFAULT_DIR := "user://saves"
const SLOT := "slot1"
## Shown when load_game() had to fall back to slot1.bak.json (also repeated by Game.continue_game()
## once the gameplay UI exists, because the title screen has no toasts).
const BACKUP_NOTICE := "Your latest save was damaged, so your previous save was restored."

var save_dir: String = DEFAULT_DIR
var last_error: String = ""
var recovered_from_backup: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)


## Tests use a dedicated directory; never point this at the real save folder in tests.
func set_save_dir(path: String) -> void:
	save_dir = path
	DirAccess.make_dir_recursive_absolute(save_dir)


func _path(suffix: String = ".json") -> String:
	return save_dir.path_join(SLOT + suffix)


func has_save() -> bool:
	if FileAccess.file_exists(_path()) or FileAccess.file_exists(_path(".bak.json")):
		return true
	# Rare: a crash between writing and renaming the very first save leaves only a complete temp file.
	return not _read_and_validate(_path(".tmp")).is_empty()


## Builds the save dictionary from GameState plus metadata.
func build_save_data() -> Dictionary:
	return {
		"format": "hollowhaven-save",
		"version": SAVE_VERSION,
		"game_version": String(ProjectSettings.get_setting("application/config/version", "0")),
		"saved_unix": Time.get_unix_time_from_system(),
		"meta": {
			"day": GameState.day(),
			"step": GameState.quests.current_id(),
			"step_title": _step_title(),
			"play_seconds": float(GameState.stats.get("play_seconds", 0.0)),
			"area": String(GameState.player.get("area", "surface")),
		},
		"state": GameState.to_dict(),
	}


## Title of the current step for the title screen (arachnophobia-aware), "Chapter complete" past the end.
func _step_title() -> String:
	var s: Dictionary = GameState.quests.current_step()
	if s.is_empty():
		return "Chapter complete"
	return String(GameState.quests.step_string(s, "title"))


## Saves the current GameState. Returns true on success.
## quiet: background saves (surface autosave, New Game, closing the window) skip Events.game_saved
## on success, so no "Journey saved" toast/sound appears; a failure is still announced.
func save_game(quiet: bool = false) -> bool:
	last_error = ""
	if Game.player != null and is_instance_valid(Game.player) and Game.player.has_method("write_to_state"):
		Game.player.write_to_state()
	var data := build_save_data()
	var text := JSON.stringify(data, "\t")
	var ok := _atomic_write(text)
	if not ok or not quiet:
		Events.game_saved.emit(ok)
	if not ok:
		push_error("SaveSystem: save failed: " + last_error)
	return ok


func _atomic_write(text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var tmp := _path(".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "cannot open temp file (%s)" % error_string(FileAccess.get_open_error())
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# Validate what actually hit the disk before replacing anything.
	var check := _read_and_validate(tmp)
	if check.is_empty():
		last_error = "temp file failed validation"
		DirAccess.remove_absolute(tmp)
		return false
	var cur := _path()
	var bak := _path(".bak.json")
	if FileAccess.file_exists(cur):
		# Only rotate a current file that is itself valid, so a good backup is never replaced by junk.
		if not _read_and_validate(cur).is_empty():
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			var e1 := DirAccess.rename_absolute(cur, bak)
			if e1 != OK:
				last_error = "could not rotate backup (%s)" % error_string(e1)
				return false
		else:
			_preserve_corrupt_main()   # keep the damaged file for inspection instead of deleting it
	var e2 := DirAccess.rename_absolute(tmp, cur)
	if e2 != OK:
		last_error = "could not move temp into place (%s)" % error_string(e2)
		return false
	return true


## Reads a save file; returns the parsed dictionary or {} if missing/corrupt/incompatible.
func _read_and_validate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var d = json.data
	if not (d is Dictionary):
		return {}
	# Type checks first: comparing e.g. a float with a String is a script error in Godot 4.
	var fmt: Variant = d.get("format", "")
	if not (fmt is String) or fmt != "hollowhaven-save":
		return {}
	var ver: Variant = d.get("version", 0)
	if not (ver is int or ver is float) or int(ver) < 1 or int(ver) > SAVE_VERSION:
		return {}
	if not (d.get("state") is Dictionary):
		return {}
	return migrate(d)


## Upgrades older save versions in place. Version 1 is current.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	# if v < 2: ... future migrations go here, then set d["version"] = 2
	d["version"] = max(v, SAVE_VERSION)
	return d


## Reads the best available save without applying it (for the title screen).
## Uses the same choice as load_game(): main file, else the newest valid of temp/backup.
func peek() -> Dictionary:
	return _best_available()["data"]


## Picks what load_game() would load: {"data": Dictionary ({} = nothing), "source": "main"|"tmp"|"bak"|""}.
## A complete temp file only counts when the main file is unusable and it is at least as new as the
## backup (a crash between rotating the backup and renaming the temp leaves exactly that state).
func _best_available() -> Dictionary:
	var d := _read_and_validate(_path())
	if not d.is_empty():
		return {"data": d, "source": "main"}
	var bak := _read_and_validate(_path(".bak.json"))
	var tmp := _read_and_validate(_path(".tmp"))
	if not tmp.is_empty() and (bak.is_empty() or _saved_time(tmp) >= _saved_time(bak)):
		return {"data": tmp, "source": "tmp"}
	if not bak.is_empty():
		return {"data": bak, "source": "bak"}
	return {"data": {}, "source": ""}


static func _saved_time(d: Dictionary) -> float:
	var t: Variant = d.get("saved_unix", 0.0)
	return float(t) if (t is int or (t is float and is_finite(t))) else 0.0


## Loads the save into GameState. Falls back to the backup if the main file is unusable.
## A corrupt main file is moved aside as slot1.corrupt-<time>.json for inspection (never deleted
## blindly, and not re-copied on every later load). A stale temp file is ignored and cleaned up.
func load_game() -> bool:
	last_error = ""
	recovered_from_backup = false
	var main_exists := FileAccess.file_exists(_path())
	var best := _best_available()
	var d: Dictionary = best["data"]
	var source: String = best["source"]
	if source != "main" and main_exists:
		_preserve_corrupt_main()
	if d.is_empty():
		last_error = "No valid save found."
		return false
	if source == "main":
		if FileAccess.file_exists(_path(".tmp")):
			DirAccess.remove_absolute(_path(".tmp"))   # leftover of an interrupted/failed write
	elif source == "tmp":
		# Promote the complete temp file so the next save rotates it into the backup normally.
		if DirAccess.rename_absolute(_path(".tmp"), _path()) != OK:
			push_warning("SaveSystem: could not promote the recovered temp save")
	else:
		recovered_from_backup = true
	GameState.from_dict(d["state"])
	Events.game_loaded.emit()
	if recovered_from_backup:
		Events.notify.emit(BACKUP_NOTICE, "warn")
	return true


func _preserve_corrupt_main() -> void:
	var stamp := int(Time.get_unix_time_from_system())
	var keep := _path(".corrupt-%d.json" % stamp)
	var n := 1
	while FileAccess.file_exists(keep):
		keep = _path(".corrupt-%d-%d.json" % [stamp, n])
		n += 1
	if DirAccess.rename_absolute(_path(), keep) != OK:
		DirAccess.copy_absolute(_path(), keep)
	push_warning("SaveSystem: main save unreadable; preserved as " + keep)


## Deletes save files. Only allowed for test directories (safety net for automated tests).
func delete_test_saves() -> void:
	if not save_dir.contains("test"):
		push_error("SaveSystem: refusing to delete non-test saves")
		return
	for suffix in [".json", ".bak.json", ".tmp"]:
		if FileAccess.file_exists(_path(suffix)):
			DirAccess.remove_absolute(_path(suffix))
	var dir := DirAccess.open(save_dir)
	if dir:
		for f in dir.get_files():
			if f.begins_with(SLOT + ".corrupt"):
				dir.remove(f)
