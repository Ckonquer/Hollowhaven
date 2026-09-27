extends "res://tests/unit/test_core_base.gd"
## Self-test of the core QA harness (test_core_base.gd): proves that a runtime script error inside
## code under test is detected (the plain runner would report such a test as PASS) and that the
## base restores globals.


func test_logger_is_registered_with_the_engine() -> void:
	# A warning travels the same engine path as script errors (which the mutation runs proved are
	# caught); a real error is not triggered here to keep the test log free of false alarms.
	push_warning("core harness self-test: this warning is expected")
	assert_true(logged("core harness self-test"), "the engine delivers log entries to the catcher")


func test_unexpected_errors_fail_the_test_but_warnings_do_not() -> void:
	var no_bt: Array[ScriptBacktrace] = []
	_catcher._log_error("f", "res://probe.gd", 3, "Invalid access to key 'probe_key'", "", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	_catcher._log_error("f", "res://probe.gd", 4, "probe push_error", "", false, Logger.ERROR_TYPE_ERROR, no_bt)
	_catcher._log_error("f", "res://probe.gd", 5, "probe warning", "", false, Logger.ERROR_TYPE_WARNING, no_bt)
	var bad := _unexpected_errors()
	assert_eq(bad.size(), 2, "script error and error are reported, the warning is not")
	assert_true(String(bad[0]).begins_with("unexpected script error"), str(bad))
	expect_error("probe_key")
	assert_eq(_unexpected_errors().size(), 1, "expect_error whitelists by fragment")
	expect_error("probe push_error")   # whitelist it so this test itself passes
	assert_eq(_unexpected_errors().size(), 0)


func test_record_and_listen_capture_signals() -> void:
	var got := record(Events.notify, 2)
	Events.notify.emit("hello", "info")
	assert_eq(got, [["hello", "info"]])


func test_listeners_are_disconnected_after_each() -> void:
	# The previous test connected to Events.notify; after_each must have removed it.
	for c in Events.notify.get_connections():
		var cb: Callable = c["callable"]
		assert_false(cb.get_object() == self and cb.is_custom(), "no stale test lambda left on Events.notify")


func test_deep_diff_is_type_strict() -> void:
	assert_eq(deep_diff({"a": 1}, {"a": 1}, ""), "")
	assert_ne(deep_diff({"a": 1}, {"a": 1.0}, ""), "", "int vs float differs")
	assert_ne(deep_diff([1, 2], [1], ""), "")
	assert_ne(deep_diff({"a": {"b": [1]}}, {"a": {"b": [2]}}, ""), "")
	assert_true(deep_diff({"a": {"b": [2]}}, {"a": {"b": [3]}}, "root").begins_with("root/a/b[0]"), "reports the path")
