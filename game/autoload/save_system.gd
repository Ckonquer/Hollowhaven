extends Node
## Versioned JSON saves with atomic writes and a recoverable backup.
## Files (in the user data folder, e.g. %APPDATA%/Hollowhaven/saves):
##   slot1.json      current save
##   slot1.bak.json  previous good save (used if the current one is missing/corrupt)
##   slot1.tmp       write in progress (a complete one is recovered after a crash)
##   slot1.corrupt-<unix>[-n].json         a damaged main save, moved aside for inspection
##   slot1.future-<ver>-<unix>[-n].json    a save from a NEWER game version, set aside only after the player
##                                         confirmed New Game (never deleted)
##   pre_v2_backup/slot1.v1-<unix>.json, pre_v2_backup/slot1.bak.v1-<unix>.json
##                   untouched copies of the Chapter-One (version 1) files, made once before the first
##                   version-2 write (never deleted or rewritten by the game; docs/SAVE_MIGRATION.md)
## Write procedure: serialise -> write slot1.tmp -> re-read and validate tmp -> rotate current to .bak
## -> rename tmp to current. A crash at any point leaves at least one valid file.
## Schema v2 (docs/CHAPTER_TWO_SPEC.md §3): migrate() adds the new sections to version-1 data (additive,
## deterministic, idempotent). A save from a newer version is refused IN PLACE: not corrupt, not moved, no
## fallback to an older backup, never overwritten (unless New Game was confirmed: replace_future_allowed).

const SAVE_VERSION := 2
const DEFAULT_DIR := "user://saves"
const SLOT := "slot1"
const UPGRADE_BACKUP_DIR := "pre_v2_backup"
## Shown when load_game() had to fall back to slot1.bak.json (also repeated by Game.continue_game()
## once the gameplay UI exists, because the title screen has no toasts).
const BACKUP_NOTICE := "Your latest save was damaged, so your previous save was restored."
## last_error when the save was written by a newer version (spec §3.3; the title shows it on Continue).
const FUTURE_ERROR := "This save was made by a newer version of Hollowhaven."
const LEGACY_FREE_PLAY_GOALS := ["opt_legacy_bond", "opt_legacy_heartbloom"]

var save_dir: String = DEFAULT_DIR
var last_error: String = ""
var recovered_from_backup: bool = false
## True after load_game()/peek()/has_save() found that the save to continue was made by a newer version.
var blocked_by_future: bool = false
var future_version: int = 0
## Set by the title's New Game confirmation: the next save may set a newer-version save aside
## (moved to slot1.future-<ver>-<unix>.json, never deleted). Consumed by that save.
var replace_future_allowed: bool = false
## Path of the last pre-v2 upgrade backup made in this session ("" = none made yet).
var upgrade_backup_path: String = ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)


## Tests use a dedicated directory; never point this at the real save folder in tests.
func set_save_dir(path: String) -> void:
	save_dir = path
	DirAccess.make_dir_recursive_absolute(save_dir)


func _path(suffix: String = ".json") -> String:
	return save_dir.path_join(SLOT + suffix)


func upgrade_backup_dir() -> String:
	return save_dir.path_join(UPGRADE_BACKUP_DIR)


## True when there is something to continue from - or a newer-version save that blocks it (so the title
## can explain why Continue is disabled and New Game asks before setting it aside).
func has_save() -> bool:
	if FileAccess.file_exists(_path()) or FileAccess.file_exists(_path(".bak.json")):
		return true
	# Rare: a crash between writing and renaming the very first save leaves only a complete temp file.
	var tmp_status: String = _read_status(_path(".tmp"))["status"]
	return tmp_status == "ok" or tmp_status == "future"


## Builds the save dictionary from GameState plus metadata.
func build_save_data() -> Dictionary:
	var obj: Dictionary = GameState.current_objective()
	return {
		"format": "hollowhaven-save",
		"version": SAVE_VERSION,
		"game_version": String(ProjectSettings.get_setting("application/config/version", "0")),
		"saved_unix": Time.get_unix_time_from_system(),
		"meta": {
			"day": GameState.day(),
			"chapter": int(obj.get("chapter", 1)),
			"step": String(obj.get("id", "")),
			"step_title": _step_title(obj),
			"play_seconds": float(GameState.stats.get("play_seconds", 0.0)),
			"area": String(GameState.player.get("area", "surface")),
		},
		"state": GameState.to_dict(),
	}


## Title of the current objective for the title screen (arachnophobia-aware, Chapter Two aware);
## "Chapter complete" / "Chapter Two complete" past the end.
func _step_title(obj: Dictionary) -> String:
	var t := String(obj.get("title", ""))
	if t != "":
		return t
	return "Chapter Two complete" if bool(GameState.get_flag("chapter_two_complete")) else "Chapter complete"


## Saves the current GameState. Returns true on success.
## quiet: background saves (surface autosave, New Game, closing the window) skip Events.game_saved
## on success, so no "Journey saved" toast/sound appears; a failure is still announced.
func save_game(quiet: bool = false) -> bool:
	last_error = ""
	if Game != null and Game.player != null and is_instance_valid(Game.player) and Game.player.has_method("write_to_state"):
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
	var cur := _path()
	var bak := _path(".bak.json")
	# 1. Newer-version files are never rotated, overwritten or deleted. A future main (or, with no usable
	#    main, a future temp/backup - the save the player would continue from) needs the player's
	#    confirmation (New Game); with it, they are moved aside. Any other future file is moved aside too.
	var cur_st := _read_status(cur)
	var tmp_st := _read_status(tmp)
	var bak_st := _read_status(bak)
	var needs_permission: bool = cur_st["status"] == "future" or (cur_st["status"] != "ok"
		and (tmp_st["status"] == "future" or bak_st["status"] == "future"))
	if needs_permission and not replace_future_allowed:
		blocked_by_future = true
		last_error = FUTURE_ERROR
		return false
	# 2. Before the first version-2 write over Chapter-One files, keep untouched copies (spec §3.2).
	if (cur_st["status"] == "ok" and int(cur_st["version"]) < 2) or (bak_st["status"] == "ok" and int(bak_st["version"]) < 2) \
			or (cur_st["status"] != "ok" and tmp_st["status"] == "ok" and int(tmp_st["version"]) < 2):
		if not _ensure_upgrade_backup(cur_st, tmp_st, bak_st):
			last_error = "could not back up the Chapter One save before upgrading it (%s)" % last_error
			return false
	for pair in [[cur, cur_st], [tmp, tmp_st], [bak, bak_st]]:
		if pair[1]["status"] == "future" and not _set_aside_future(pair[0], int(pair[1]["version"])):
			last_error = "could not set the newer-version save aside"
			return false
	# 3. The usual atomic write.
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
	if FileAccess.file_exists(cur):
		# Only rotate a current file that is itself valid, so a good backup is never replaced by junk.
		# (cur_st was read above; a newer-version main has already been set aside.)
		if cur_st["status"] == "ok":
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
	if needs_permission:
		replace_future_allowed = false   # the confirmation covered this one replacement
	blocked_by_future = false
	return true


## Reads a save file: {"status": "ok"|"missing"|"corrupt"|"future", "data": Dictionary (migrated, only
## for "ok"), "version": int (as written in the file)}. "future" = a well-formed hollowhaven save whose
## version is newer than SAVE_VERSION: it is NOT corrupt (spec §3.3).
func _read_status(path: String) -> Dictionary:
	var out := {"status": "missing", "data": {}, "version": 0}
	if not FileAccess.file_exists(path):
		return out
	out["status"] = "corrupt"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return out
	var json := JSON.new()
	if json.parse(text) != OK:
		return out
	var d = json.data
	if not (d is Dictionary):
		return out
	# Type checks first: comparing e.g. a float with a String is a script error in Godot 4.
	var fmt: Variant = d.get("format", "")
	if not (fmt is String) or fmt != "hollowhaven-save":
		return out
	var ver: Variant = d.get("version", 0)
	if not (ver is int or (ver is float and is_finite(ver))) or int(ver) < 1:
		return out
	out["version"] = int(ver)
	if int(ver) > SAVE_VERSION:
		out["status"] = "future"
		return out
	if not (d.get("state") is Dictionary):
		return out
	out["status"] = "ok"
	out["data"] = migrate(d)
	return out


## Reads a save file; returns the parsed (migrated) dictionary or {} if missing/corrupt/incompatible.
func _read_and_validate(path: String) -> Dictionary:
	return _read_status(path)["data"]


## Upgrades older save versions (pure: returns a new dictionary, the argument is not modified;
## deterministic, idempotent and cheap - it runs on every read of a save file). Tolerates a dict without
## "state". v1 -> v2 only ADDS: every missing schema-v2 section with its default, the new companion keys,
## capacity.backpack = max(32, inventory length), and the legacy free_play goals marked done when the
## legacy log already completed free_play. Legacy keys are never touched; unknown keys are kept.
func migrate(d: Dictionary) -> Dictionary:
	var out := d.duplicate(false)
	var raw: Variant = d.get("version", 1)
	var v: int = int(raw) if (raw is int or (raw is float and is_finite(raw))) else 1
	if v < 2 and d.get("state") is Dictionary:
		out["state"] = _migrate_state_v1(d["state"])
	out["version"] = maxi(v, SAVE_VERSION)
	return out


func _migrate_state_v1(src: Dictionary) -> Dictionary:
	var st := src.duplicate(false)
	var defaults: Dictionary = GameState.v2_section_defaults()
	for k in defaults:
		if not st.has(k):
			st[k] = defaults[k]
	if not src.has("capacity"):
		var inv: Variant = src.get("inventory")
		st["capacity"] = {"backpack": maxi(GameState.INVENTORY_SIZE, inv.size() if inv is Array else 0)}
	var comps: Variant = src.get("companions")
	if comps is Dictionary:
		var out_c := {}
		for id in comps:
			var rec: Variant = comps[id]
			if rec is Dictionary:
				var r2: Dictionary = (rec as Dictionary).duplicate(false)
				for k in GameState.COMPANION_V2_DEFAULTS:
					if not r2.has(k):
						r2[k] = GameState.COMPANION_V2_DEFAULTS[k]
				out_c[id] = r2
			else:
				out_c[id] = rec
		st["companions"] = out_c
	if not src.has("optional") and _legacy_free_play_done(src.get("quests")):
		var t: Variant = src.get("total_minutes", 0.0)
		var at: float = float(t) if (t is int or (t is float and is_finite(t))) else 0.0
		var opt := {}
		for id in LEGACY_FREE_PLAY_GOALS:
			opt[id] = {"done": true, "done_at": at}
		st["optional"] = opt
	return st


static func _legacy_free_play_done(q: Variant) -> bool:
	if not (q is Dictionary):
		return false
	var comp: Variant = q.get("completed")
	if comp is Array and (comp as Array).has("free_play"):
		return true
	var idx: Variant = q.get("index")
	return (idx is int or (idx is float and is_finite(idx))) and int(idx) >= preload("res://data/quests.gd").STEPS.size()


## Reads the best available save without applying it (for the title screen).
## Uses the same choice as load_game(): main file, else the newest valid of temp/backup.
## Returns {} when blocked by a newer-version save (see blocked_by_future).
func peek() -> Dictionary:
	return _best_available()["data"]


## Picks what load_game() would load: {"data": Dictionary ({} = nothing), "source": "main"|"tmp"|"bak"|
## "future"|"", "version": int as written}. A complete temp file only counts when the main file is
## unusable and it is at least as new as the backup (a crash between rotating the backup and renaming the
## temp leaves exactly that state). A newer-version main - or, with no usable main, a newer-version temp or
## backup - blocks loading ("future"): the game never silently continues from an older file instead.
func _best_available() -> Dictionary:
	blocked_by_future = false
	future_version = 0
	var m := _read_status(_path())
	if m["status"] == "ok":
		return {"data": m["data"], "source": "main", "version": m["version"]}
	var b := _read_status(_path(".bak.json"))
	var t := _read_status(_path(".tmp"))
	for st in [m, t, b]:
		if st["status"] == "future":
			blocked_by_future = true
			future_version = int(st["version"])
			return {"data": {}, "source": "future", "version": st["version"]}
	var bak: Dictionary = b["data"]
	var tmp: Dictionary = t["data"]
	if not tmp.is_empty() and (bak.is_empty() or _saved_time(tmp) >= _saved_time(bak)):
		return {"data": tmp, "source": "tmp", "version": t["version"]}
	if not bak.is_empty():
		return {"data": bak, "source": "bak", "version": b["version"]}
	return {"data": {}, "source": "", "version": 0}


static func _saved_time(d: Dictionary) -> float:
	var t: Variant = d.get("saved_unix", 0.0)
	return float(t) if (t is int or (t is float and is_finite(t))) else 0.0


## Loads the save into GameState. Falls back to the backup if the main file is unusable.
## A corrupt main file is moved aside as slot1.corrupt-<time>.json for inspection (never deleted
## blindly, and not re-copied on every later load). A stale temp file is ignored and cleaned up.
## A newer-version save is refused in place (last_error = FUTURE_ERROR): nothing is moved or written.
## Loading a version-1 save first copies the untouched v1 files to pre_v2_backup/ (spec §3.2).
func load_game() -> bool:
	last_error = ""
	recovered_from_backup = false
	var main_exists := FileAccess.file_exists(_path())
	var best := _best_available()
	var source: String = best["source"]
	if source == "future":
		last_error = FUTURE_ERROR
		return false
	var d: Dictionary = best["data"]
	if not d.is_empty() and int(best["version"]) < 2:
		if not _ensure_upgrade_backup():
			push_warning("SaveSystem: could not copy the version-1 save to %s (%s); saving stays refused until it succeeds" % [UPGRADE_BACKUP_DIR, last_error])
			last_error = ""
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


## Copies the untouched version-1 files (main - or a complete temp that is about to become the main -
## and the backup) into <save_dir>/pre_v2_backup/ as slot1.v1-<unix>.json / slot1.bak.v1-<unix>.json,
## byte for byte, once (spec §3.2): nothing is copied once that folder holds a slot1.v1-* copy, and a
## version-1 backup is not copied again when a slot1.bak.v1-* already exists (a torn main recovered from its
## backup leaves only that one; a v1 main appearing later is still copied). Statuses already read by the caller
## may be passed in. Returns false only when a copy was needed and failed.
func _ensure_upgrade_backup(main_st: Dictionary = {}, tmp_st: Dictionary = {}, bak_st: Dictionary = {}) -> bool:
	var dir := upgrade_backup_dir()
	if _backup_exists(SLOT + ".v1-"):
		return true
	var have_bak_copy := _backup_exists(SLOT + ".bak.v1-")
	if main_st.is_empty():
		main_st = _read_status(_path())
	if tmp_st.is_empty():
		tmp_st = _read_status(_path(".tmp"))
	if bak_st.is_empty():
		bak_st = _read_status(_path(".bak.json"))
	var sources: Array = []   # [source path, backup file name]
	var stamp := int(Time.get_unix_time_from_system())
	if main_st["status"] == "ok" and int(main_st["version"]) < 2:
		sources.append([_path(), "%s.v1-%d.json" % [SLOT, stamp]])
	elif main_st["status"] != "ok" and tmp_st["status"] == "ok" and int(tmp_st["version"]) < 2:
		sources.append([_path(".tmp"), "%s.v1-%d.json" % [SLOT, stamp]])
	if bak_st["status"] == "ok" and int(bak_st["version"]) < 2 and not have_bak_copy:
		sources.append([_path(".bak.json"), "%s.bak.v1-%d.json" % [SLOT, stamp]])
	if sources.is_empty():
		return true
	DirAccess.make_dir_recursive_absolute(dir)
	for s in sources:
		var target: String = dir.path_join(s[1])
		var err := DirAccess.copy_absolute(s[0], target)
		if err != OK or not FileAccess.file_exists(target):
			last_error = "copy failed (%s)" % error_string(err)
			return false
		upgrade_backup_path = target
	return true


## True when <save_dir>/pre_v2_backup already holds an upgrade backup (slot1.v1-* or slot1.bak.v1-*).
func _has_upgrade_backup() -> bool:
	return _backup_exists(SLOT + ".v1-") or _backup_exists(SLOT + ".bak.v1-")


## True when <save_dir>/pre_v2_backup holds a file whose name starts with `prefix`.
func _backup_exists(prefix: String) -> bool:
	var d := DirAccess.open(upgrade_backup_dir())
	if d == null:
		return false
	for f in d.get_files():
		if f.begins_with(prefix):
			return true
	return false


## Moves a newer-version file aside as slot1.future-<ver>-<unix>[-n].json (a temp/backup gets a "-tmp" /
## "-bak" tag). Never deletes it.
func _set_aside_future(path: String, ver: int) -> bool:
	var tag := ""
	if path.ends_with(".tmp"):
		tag = "-tmp"
	elif path.ends_with(".bak.json"):
		tag = "-bak"
	var stamp := int(Time.get_unix_time_from_system())
	var keep := _path(".future-%d-%d%s.json" % [ver, stamp, tag])
	var n := 1
	while FileAccess.file_exists(keep):
		keep = _path(".future-%d-%d%s-%d.json" % [ver, stamp, tag, n])
		n += 1
	if DirAccess.rename_absolute(path, keep) != OK:
		return false
	push_warning("SaveSystem: a save from a newer version was set aside as " + keep)
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


## Deletes save files. Only allowed for test directories (safety net for automated tests): the slot files,
## corrupt and future copies and the pre_v2_backup folder of the CURRENT test save_dir.
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
			if f.begins_with(SLOT + ".corrupt") or f.begins_with(SLOT + ".future"):
				dir.remove(f)
	var up := DirAccess.open(upgrade_backup_dir())
	if up:
		for f in up.get_files():
			if f.begins_with(SLOT + "."):
				up.remove(f)
		DirAccess.remove_absolute(upgrade_backup_dir())   # only succeeds when empty
