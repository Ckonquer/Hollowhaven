extends Node
## Headless test runner.
##   Godot --headless --path game res://tests/runner.tscn -- --filter=inventory --results=out.json
## Discovers res://tests/unit/**/test_*.gd. Exit code 0 = all passed, 1 = failures.

var results: Array = []
var _catcher: ScriptErrorCatcher = null


## Records GDScript runtime errors (type SCRIPT) so a test whose code crashes mid-way FAILS instead of
## silently passing. push_error()/warnings are not counted here (suites may expect those).
class ScriptErrorCatcher extends Logger:
	var entries: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		entries.append("SCRIPT ERROR %s %s (%s:%d)" % [code, rationale, file, line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n := entries.size()
		_mutex.unlock()
		return n

	func since(n: int) -> Array:
		_mutex.lock()
		var out := entries.slice(n)
		_mutex.unlock()
		return out


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_catcher = ScriptErrorCatcher.new()
	OS.add_logger(_catcher)
	var filter := Debug.arg("filter", "")
	var files := []
	_collect("res://tests/unit", files)
	files.sort()
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		if filter != "" and not String(path).get_file().contains(filter):
			continue
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			print("ERROR cannot load %s (parse error?)" % path)
			results.append({"suite": path, "test": "<load>", "ok": false, "msgs": ["script failed to load"]})
			failed += 1
			total += 1
			continue
		var suite: String = String(path).get_file().get_basename()
		SaveSystem.set_save_dir("user://test_saves/" + suite)
		var inst: Node = script.new()
		add_child(inst)
		var methods := []
		for m in script.get_script_method_list():
			var n: String = m["name"]
			if n.begins_with("test_") and not methods.has(n):
				methods.append(n)
		for m in methods:
			total += 1
			inst._failures = []
			GameState.active = false
			var err_mark := _catcher.count()
			await inst.before_each()
			await inst.call(m)
			await inst.after_each()
			for e in _catcher.since(err_mark):
				inst._failures.append(e)
			var ok: bool = inst._failures.is_empty()
			if not ok:
				failed += 1
			results.append({"suite": suite, "test": m, "ok": ok, "msgs": inst._failures.duplicate()})
			print("%s %s.%s %s" % ["PASS" if ok else "FAIL", suite, m, "" if ok else str(inst._failures)])
		inst.queue_free()
		SaveSystem.delete_test_saves()
		await get_tree().process_frame
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("==== %d tests, %d failed, %.1fs ====" % [total, failed, secs])
	var out := Debug.arg("results", "")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"total": total, "failed": failed, "seconds": secs, "results": results}, "\t"))
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_collect(dir_path.path_join(sub), out)
