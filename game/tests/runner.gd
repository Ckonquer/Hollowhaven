extends Node
## Headless test runner.
##   Godot --headless --path game res://tests/runner.tscn -- --filter=inventory --results=out.json
## Discovers res://tests/unit/**/test_*.gd. Exit code 0 = all passed, 1 = failures.
## Saves: SaveSystem points at user://test_saves/run_<pid>/<suite> (one folder per runner process, so parallel
## runs never share save files); the run folder is removed at the end.
## --filter: a file-name fragment, or several separated by commas (a file runs when ANY fragment matches), e.g.
##   tools/test.sh "test_boss_velour_fight,test_companions_node"   (bisecting an order-dependent failure).
## Isolation between test FILES (each file sees what it would see when run alone): after a file the runner
## frees stray nodes it left (children of the runner / scene root / Game that were not there at start), puts
## the runner back as current_scene, restores Game's flow state (mode, area, player, UI root, director,
## companions, boss encounters, a Chapter Two ending or a trip in flight), unpauses, restores Settings values,
## resets GameState to a fresh boot's and re-wires the session listeners (Game.wire_session_systems). Every repair
## except the GameState reset is printed as "ISOLATION <suite>: ..." so the suite that leaked it can be fixed.
## To reproduce / bisect an order-dependent failure WITHOUT that repair, add the user arg --no-isolation:
##   tools/godot.sh --headless --path game res://tests/runner.tscn -- --filter=suspect_a,victim --no-isolation

## Root children a suite may leave on purpose (self-managing helpers: the hitstop listener persists, the gathering
## sparkle frees itself once no resource node is left; both are re-created on demand).
const KEEP_ROOT_NODES := ["HitstopListener", "GatherSparkle"]
## Game's session children re-created by Game.wire_session_systems() (never strays).
const KEEP_GAME_NODES := ["StoryCh2Tracker", "OnboardingHints"]
## A live runner rewrites run_<pid>/.heartbeat (unix time) at start and before every suite. Another run's folder
## counts as stale (a killed run: removed at start) only when its heartbeat is older than this. The process id
## cannot decide it: OS.is_process_running() only knows processes THIS process started (Windows and Unix), so
## it reported every parallel runner as gone and a starting run wiped their live save folders mid-test.
const HEARTBEAT_FILE := ".heartbeat"
const STALE_RUN_SECONDS := 3 * 3600

var results: Array = []
var _catcher: ScriptErrorCatcher = null
var _root_baseline: Array = []          # scene-root children when the run started (autoloads + this runner)
var _game_children: Array = []          # Game's children when the run started (e.g. the story tracker)
var _game_baseline: Dictionary = {}     # Game's flow state when the run started
var _settings_baseline: Dictionary = {}
var no_isolation := false               # -- --no-isolation: files share whatever earlier files left (bisecting)
var _run_dir := "user://test_saves"     # user://test_saves/run_<pid>: this process's saves (removed at the end)


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
	var filters := _filters(Debug.arg("filter", ""))
	var files := []
	_collect("res://tests/unit", files)
	files.sort()
	# One save folder per runner PROCESS: several test runs at once (parallel agents / terminals) must never
	# read, overwrite or delete each other's save files (a roundtrip test once read another run's save).
	_run_dir = "user://test_saves/run_%d" % OS.get_process_id()
	_touch_heartbeat()
	_remove_stale_runs()
	no_isolation = Debug.has_arg("no-isolation")
	_record_baseline()
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		if not _matches(filters, String(path).get_file()):
			continue
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			print("ERROR cannot load %s (parse error?)" % path)
			results.append({"suite": path, "test": "<load>", "ok": false, "msgs": ["script failed to load"]})
			failed += 1
			total += 1
			continue
		var suite: String = String(path).get_file().get_basename()
		_touch_heartbeat()
		SaveSystem.set_save_dir(_run_dir.path_join(suite))
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
		if not no_isolation:
			await _isolate_after(suite)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	_remove_tree(_run_dir)
	print("==== %d tests, %d failed, %.1fs ====" % [total, failed, secs])
	var out := Debug.arg("results", "")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"total": total, "failed": failed, "seconds": secs, "results": results}, "\t"))
	get_tree().quit(1 if failed > 0 else 0)


## "a,b , c" -> ["a", "b", "c"]; "" -> [] (everything runs).
static func _filters(arg: String) -> Array:
	var out: Array = []
	for part in arg.split(",", false):
		var p := String(part).strip_edges()
		if p != "" and not out.has(p):
			out.append(p)
	return out


static func _matches(filters: Array, file_name: String) -> bool:
	if filters.is_empty():
		return true
	for f in filters:
		if file_name.contains(String(f)):
			return true
	return false


# --- Isolation between test files --------------------------------------------------------------------------

const GAME_STATE_KEYS := ["mode", "area_id", "zone_id", "in_safe_zone", "player", "area", "ui", "director"]


func _record_baseline() -> void:
	_root_baseline = get_tree().root.get_children()
	_game_children = Game.get_children()
	_game_baseline = {}
	for k in GAME_STATE_KEYS:
		_game_baseline[k] = Game.get(k)
	_settings_baseline = Settings.values.duplicate(true)


## Puts the shared world back the way the next file would find it when run alone (see the header). Prints what
## it had to repair, naming the suite that left it.
func _isolate_after(suite: String) -> void:
	var notes: Array = []
	var tree := get_tree()
	if tree.current_scene != self:
		notes.append("current_scene was %s" % _describe(tree.current_scene))
		tree.current_scene = self
	var ui_node: Node = _valid_node(Game.get("ui"))
	var stray: Array = []
	for c in get_children():
		if not c.is_queued_for_deletion():
			stray.append(c)
	for c in tree.root.get_children():
		if c != self and not _root_baseline.has(c) and not KEEP_ROOT_NODES.has(String(c.name)) and not c.is_queued_for_deletion():
			stray.append(c)
	for c in Game.get_children():
		if not _game_children.has(c) and c != ui_node and not KEEP_GAME_NODES.has(String(c.name)) and not c.is_queued_for_deletion():
			stray.append(c)
	# The UI root lives under Game: a leftover one is freed (a file run alone starts without one).
	if ui_node != null and ui_node != _valid_node(_game_baseline.get("ui")) and not ui_node.is_queued_for_deletion():
		stray.append(ui_node)
	if not stray.is_empty():
		var names: Array = stray.map(func(n: Node) -> String: return _describe(n))
		notes.append("freed %d stray node(s) %s" % [stray.size(), str(names)])
		for n in stray:
			(n as Node).queue_free()
	# Game's flow state.
	for k in GAME_STATE_KEYS:
		var want: Variant = _game_baseline[k]
		var have: Variant = Game.get(k)
		if _same(have, want):
			continue
		var freed: bool = typeof(have) == TYPE_OBJECT and not is_instance_valid(have)
		if not freed and k != "ui":
			notes.append("Game.%s was %s" % [k, _describe(have)])
		Game.set(k, want)
	var comps: Variant = Game.get("companion_nodes")
	if not (comps is Dictionary) or not (comps as Dictionary).is_empty():
		notes.append("Game.companion_nodes was %s" % (str((comps as Dictionary).keys()) if comps is Dictionary else "?"))
		Game.set("companion_nodes", {})
	var bosses: Variant = Game.get("_bosses")
	if bosses is Dictionary and not (bosses as Dictionary).is_empty():
		notes.append("Game._bosses was %s" % str((bosses as Dictionary).keys()))
		(bosses as Dictionary).clear()
	for k in ["_ch2_ending_running", "_transitioning", "_focus_lost"]:
		var v: Variant = Game.get(k)
		if v is bool and v:
			notes.append("Game.%s was true" % k)
			Game.set(k, false)
	var stack: Variant = Game.get("_ui_stack")
	if stack is Array and not (stack as Array).is_empty():
		notes.append("Game._ui_stack was %s" % str(stack))
		(stack as Array).clear()
	if tree.paused:
		notes.append("the tree was paused")
		tree.paused = false
	if not is_equal_approx(Engine.time_scale, 1.0):
		notes.append("Engine.time_scale was %.2f" % Engine.time_scale)
		Engine.time_scale = 1.0
	if Settings.values != _settings_baseline:
		var changed: Array = []
		for k in _settings_baseline:
			if not Settings.values.has(k) or not _same(Settings.values[k], _settings_baseline[k]):
				changed.append(k)
		notes.append("Settings changed %s" % str(changed))
		Settings.values = _settings_baseline.duplicate(true)
		if Settings.has_method("setup_input_map"):
			Settings.setup_input_map()
	# A fresh boot's GameState (reset() is what GameState._ready() ran): nothing a suite left in it leaks on.
	GameState.reset()
	GameState.active = false
	if Game.has_method("wire_session_systems"):
		Game.wire_session_systems()
	if not notes.is_empty():
		print("ISOLATION %s: %s" % [suite, "; ".join(PackedStringArray(notes))])
	await tree.process_frame
	await tree.process_frame


static func _valid_node(v: Variant) -> Node:
	if typeof(v) == TYPE_OBJECT and is_instance_valid(v) and v is Node:
		return v
	return null


## Equality that never touches a freed object (== / `is` on one is a script error).
static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_OBJECT:
		var va := is_instance_valid(a)
		var vb := is_instance_valid(b)
		if not va or not vb:
			return va == vb
	return a == b


static func _describe(n: Variant) -> String:
	if typeof(n) != TYPE_OBJECT:
		return str(n)
	if not is_instance_valid(n):
		return "<freed>"
	if not (n is Node):
		return str(n)
	var node: Node = n
	var s: Variant = node.get_script()
	var script_name := (s as Script).resource_path.get_file() if s is Script else node.get_class()
	var extra := ""
	var item: Variant = node.get("item_id")
	if item is String or item is StringName:
		extra = " item=%s uid=%s" % [String(item), str(node.get("uid"))]
	return "%s(%s%s)" % [String(node.name), script_name, extra]


## Marks this run's folder as alive (see HEARTBEAT_FILE).
func _touch_heartbeat() -> void:
	DirAccess.make_dir_recursive_absolute(_run_dir)
	var f := FileAccess.open(_run_dir.path_join(HEARTBEAT_FILE), FileAccess.WRITE)
	if f != null:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


## Removes the save folders of earlier runs that were killed before they could clean up: other runs' folders
## whose heartbeat is older than STALE_RUN_SECONDS. A parallel run's live folder is never touched.
static func _remove_stale_runs() -> void:
	var d := DirAccess.open("user://test_saves")
	if d == null:
		return
	var now := Time.get_unix_time_from_system()
	for sub in d.get_directories():
		if not sub.begins_with("run_") or not sub.trim_prefix("run_").is_valid_int():
			continue
		if sub.trim_prefix("run_").to_int() == OS.get_process_id():
			continue
		var dir_path := "user://test_saves".path_join(sub)
		if now - _last_alive(dir_path) > STALE_RUN_SECONDS:
			_remove_tree(dir_path)


## Unix time a run folder was last known alive: its heartbeat, else (a folder from an older runner, or one
## created a moment ago whose heartbeat is not written yet) the folder's own modified time; 0 when unknown.
static func _last_alive(dir_path: String) -> float:
	var hb := dir_path.path_join(HEARTBEAT_FILE)
	if FileAccess.file_exists(hb):
		var text := FileAccess.get_file_as_string(hb).strip_edges()
		if text.is_valid_float():
			return text.to_float()
		return float(FileAccess.get_modified_time(hb))
	return float(FileAccess.get_modified_time(dir_path))


## Deletes this run's save folder (only ever a folder under user://test_saves/run_*).
static func _remove_tree(dir_path: String) -> void:
	if not dir_path.begins_with("user://test_saves/run_"):
		return
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_remove_tree(dir_path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir_path)


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_collect(dir_path.path_join(sub), out)
