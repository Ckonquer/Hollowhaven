extends "res://tests/test_case.gd"
## Title screen with schema v2 (spec §3.3): a save made by a NEWER version keeps Continue visible but
## disabled with the refusal reason, and New Game asks first and then passes the player's permission to
## set that save aside (SaveSystem.replace_future_allowed). Saves only go to user://test_saves/.

const TitleScreen := preload("res://src/ui/title_screen.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var title: Node


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	SaveSystem.delete_test_saves()
	title = TitleScreen.new()
	add_child(title)
	await wait_frames(2)


func after_each() -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
	await wait_frames(2)
	SaveSystem.replace_future_allowed = false
	SaveSystem.blocked_by_future = false
	SaveSystem.delete_test_saves()
	GameState.reset()
	GameState.active = false


func _write_future() -> void:
	var path := SaveSystem.save_dir.path_join("slot1.json")
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "hollowhaven-save", "version": SaveSystem.SAVE_VERSION + 1, "state": {}}))
	f.close()


func test_continue_is_disabled_with_the_newer_version_reason() -> void:
	assert_true(SaveSystem.save_dir.contains("test"))
	_write_future()
	title._refresh_continue()
	assert_true(title.continue_btn.visible, "Continue stays visible")
	assert_true(title.continue_btn.disabled, "but disabled")
	assert_eq(String(title.continue_sub.text), "This save was made by a newer version of Hollowhaven.")
	title._on_continue()
	assert_false(bool(title._busy), "nothing starts")
	assert_eq(String(title.msg_l.text), SaveSystem.FUTURE_ERROR)
	assert_true(FileAccess.file_exists(SaveSystem.save_dir.path_join("slot1.json")), "the file is left alone")
	# An ordinary save enables Continue again.
	SaveSystem.delete_test_saves()
	assert_true(SaveSystem.save_game(true))
	title._refresh_continue()
	assert_true(title.continue_btn.visible)
	assert_false(title.continue_btn.disabled)
	assert_ne(String(title.continue_sub.text), SaveSystem.FUTURE_ERROR)


func test_new_game_over_a_newer_save_asks_then_grants_permission() -> void:
	_write_future()
	title._refresh_continue()
	var run := func() -> void:
		await title._on_new_game()
	run.call()
	await wait_frames(2)
	var dlg: Control = title._panel
	assert_true(dlg != null and dlg.has_signal("chosen"), "the overwrite warning comes first")
	if dlg == null:
		return
	assert_true(String(dlg.get("text")).contains(SaveSystem.FUTURE_ERROR), "it names the newer save")
	assert_true(String(dlg.get("text")).contains("kept, not deleted"))
	dlg._choose("new")
	await wait_frames(3)
	var comfort: Control = title._panel
	assert_true(comfort != null and comfort.has_signal("confirmed"), "comfort screen follows")
	assert_false(SaveSystem.replace_future_allowed, "no permission before the comfort screen is accepted")
	if comfort == null:
		return
	comfort.set("accepted", true)
	comfort.request_close()
	await wait_frames(3)
	assert_true(SaveSystem.replace_future_allowed, "confirmed New Game may set the newer save aside")
	title.queue_free()   # stop before the fade hands over to Game.new_game()


func test_keep_my_save_grants_nothing() -> void:
	_write_future()
	var run := func() -> void:
		await title._on_new_game()
	run.call()
	await wait_frames(2)
	title._panel._choose("cancel")
	await wait_frames(3)
	assert_false(SaveSystem.replace_future_allowed)
	assert_true(FileAccess.file_exists(SaveSystem.save_dir.path_join("slot1.json")))
