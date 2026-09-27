extends Node
## Headless test runner.
##   Godot --headless --path game res://tests/runner.tscn -- --filter=inventory --results=out.json
## Discovers res://tests/unit/**/test_*.gd. Exit code 0 = all passed, 1 = failures.

var results: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
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
			await inst.before_each()
			await inst.call(m)
			await inst.after_each()
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
