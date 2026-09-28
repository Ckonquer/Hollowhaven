extends Node
## Base class for unit/integration tests. Put tests in res://tests/unit/test_<topic>.gd:
##   extends "res://tests/test_case.gd"
##   func test_stacking() -> void:
##       assert_eq(inv.add("wood", 120), 0)
## Methods named test_* run in file order. before_each()/after_each() wrap every test.
## Tests may `await` (e.g. await wait_frames(2)). Never touch the real save folder:
## the runner points SaveSystem at user://test_saves/run_<pid>/<suite> before each suite (one folder per runner
## process, so parallel test runs never share save files).

var _failures: Array = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	_failures.append(msg)


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	var numeric := (actual is int or actual is float) and (expected is int or expected is float)
	if typeof(actual) != typeof(expected) and not numeric:
		fail("%s expected %s (%s) got %s (%s)" % [msg, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
	elif actual != expected:
		fail("%s expected %s got %s" % [msg, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if actual == unexpected:
		fail("%s did not expect %s" % [msg, str(actual)])


func assert_almost(actual: float, expected: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s expected %.4f (+/- %.4f) got %.4f" % [msg, expected, eps, actual])


func assert_not_null(v: Variant, msg: String = "expected non-null") -> void:
	if v == null:
		fail(msg)


func assert_null(v: Variant, msg: String = "expected null") -> void:
	if v != null:
		fail(msg)


func wait_frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame


func wait_physics(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func wait_seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Fresh playthrough state for a test (does not load any scene).
func fresh_state() -> void:
	GameState.new_game()
