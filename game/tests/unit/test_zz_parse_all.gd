extends "res://tests/test_case.gd"
## Loads every script in the project so parse/compile errors fail loudly.
## Run alone with: tools/test.sh parse_all

const ROOTS := ["res://autoload", "res://data", "res://src", "res://scenes", "res://tests/preview"]


func test_all_scripts_compile() -> void:
	var files := []
	for r in ROOTS:
		_collect(r, files)
	assert_true(files.size() > 10, "found scripts")
	for path in files:
		var s = load(path)
		if s == null:
			fail("failed to load " + path)
		elif s is GDScript and not s.can_instantiate():
			fail("cannot instantiate (compile error?) " + path)


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_collect(dir_path.path_join(sub), out)
