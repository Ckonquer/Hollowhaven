extends "res://tests/test_case.gd"
## Shared base for the CORE QA suites (test_core_*.gd). Has no tests of its own.
##
## Why it exists:
## * A GDScript runtime error aborts the running function but the runner still reports PASS.
##   This base installs a Logger for every test and FAILS the test on any script error or
##   push_error that the test did not explicitly expect (expect_error()).
## * It restores every global it may touch after each test: GameState, Settings values +
##   InputMap, SaveSystem directory/flags, and disconnects every signal listener it added.
##
## Suites override setup()/teardown() (not before_each/after_each).

const Inventory := preload("res://src/core/inventory.gd")
const QuestLog := preload("res://src/core/quest_log.gd")
const QuestsData := preload("res://data/quests.gd")


class ErrorCatcher extends Logger:
	var entries: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		entries.append({"type": error_type, "text": ("%s %s" % [code, rationale]).strip_edges(), "file": file, "line": line})
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func snapshot() -> Array:
		_mutex.lock()
		var out := entries.duplicate(true)
		_mutex.unlock()
		return out


var _catcher: ErrorCatcher = null
var _expected_errors: Array = []
var _connections: Array = []            # [Signal, Callable]
var _settings_backup: Dictionary = {}
var _save_dir_backup: String = ""


func before_each() -> void:
	_expected_errors = []
	_connections = []
	_settings_backup = Settings.values.duplicate(true)
	_save_dir_backup = SaveSystem.save_dir
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	await setup()


func after_each() -> void:
	await teardown()
	for c in _connections:
		var sig: Signal = c[0]
		var owner_obj: Object = sig.get_object()
		if owner_obj != null and is_instance_valid(owner_obj) and sig.is_connected(c[1]):
			sig.disconnect(c[1])
	_connections = []
	if _catcher != null:
		OS.remove_logger(_catcher)
		for msg in _unexpected_errors():
			fail(msg)
		_catcher = null
	# Restore globals.
	if Settings.values != _settings_backup:
		Settings.values = _settings_backup.duplicate(true)
	Settings.setup_input_map()
	SaveSystem.save_dir = _save_dir_backup
	SaveSystem.last_error = ""
	SaveSystem.recovered_from_backup = false
	GameState.reset()
	GameState.player_name = "Krystal"
	GameState.active = false
	GameState._minute_accum = 0.0
	GameState._quest_poll = 0.0


## Override in suites.
func setup() -> void:
	pass


## Override in suites.
func teardown() -> void:
	pass


## Failure messages for every logged error/script error not whitelisted with expect_error().
## Warnings never fail a test.
func _unexpected_errors() -> Array:
	var out := []
	if _catcher == null:
		return out
	for e in _catcher.snapshot():
		var t: int = int(e["type"])
		if t == Logger.ERROR_TYPE_WARNING or _is_expected(String(e["text"])):
			continue
		out.append("unexpected %s: %s (%s:%d)" % ["script error" if t == Logger.ERROR_TYPE_SCRIPT else "error", e["text"], e["file"], int(e["line"])])
	return out


## Allows errors whose text contains `fragment` in the current test.
func expect_error(fragment: String) -> void:
	_expected_errors.append(fragment)


func _is_expected(text: String) -> bool:
	for f in _expected_errors:
		if text.contains(String(f)):
			return true
	return false


## True if an error/warning containing `fragment` was logged so far in this test.
func logged(fragment: String) -> bool:
	if _catcher == null:
		return false
	for e in _catcher.snapshot():
		if String(e["text"]).contains(fragment):
			return true
	return false


## Connects `cb` to `sig` for the duration of the current test.
func listen(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


## Records every emission of `sig` (with `arity` arguments) into the returned Array as an Array of args.
func record(sig: Signal, arity: int) -> Array:
	var rec_log: Array = []
	var cb: Callable
	match arity:
		0:
			cb = func() -> void: rec_log.append([])
		1:
			cb = func(a: Variant) -> void: rec_log.append([a])
		2:
			cb = func(a: Variant, b: Variant) -> void: rec_log.append([a, b])
		3:
			cb = func(a: Variant, b: Variant, c: Variant) -> void: rec_log.append([a, b, c])
		_:
			cb = func(a: Variant, b: Variant, c: Variant, d: Variant) -> void: rec_log.append([a, b, c, d])
	listen(sig, cb)
	return rec_log


## Deep-normalises a value the way a save file does (all numbers become floats).
func json_norm(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


## Deep equality that reports the first differing path (strict: int 1 != float 1.0).
func assert_deep_eq(actual: Variant, expected: Variant, path: String = "") -> void:
	var diff := deep_diff(actual, expected, path)
	if diff != "":
		fail(diff)


func deep_diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: type %s (%s) != expected %s (%s)" % [path, type_string(typeof(a)), str(a), type_string(typeof(b)), str(b)]
	if a is Dictionary:
		for k in b:
			if not a.has(k):
				return "%s: missing key '%s'" % [path, str(k)]
		for k in a:
			if not b.has(k):
				return "%s: unexpected key '%s'" % [path, str(k)]
			var d := deep_diff(a[k], b[k], "%s/%s" % [path, str(k)])
			if d != "":
				return d
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: size %d != expected %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := deep_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if a != b:
		return "%s: %s != expected %s" % [path, str(a), str(b)]
	return ""


## Fills every backpack slot with full stacks of `id` (default stone).
func fill_backpack(id: String = "stone") -> void:
	var inv = GameState.inventory
	for i in inv.size:
		inv.set_slot(i, {"id": id, "count": ItemDB.stack_max(id)})


func save_dir_path() -> String:
	return SaveSystem.save_dir


func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
