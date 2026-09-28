extends "res://tests/test_case.gd"
## Title screen flows (headless): the New Game overwrite confirmation returns the player's choice,
## accepting it leads to the comfort screen, and backing out of either never starts a game.
## Saves only go to the runner's user://test_saves/ folder; settings are never written.

const TitleScreen := preload("res://src/ui/title_screen.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var title: Node


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	title = TitleScreen.new()
	add_child(title)
	await wait_frames(2)


func after_each() -> void:
	if title != null and is_instance_valid(title):
		title.queue_free()
	await wait_frames(2)
	SaveSystem.delete_test_saves()


func test_confirm_returns_the_choice() -> void:
	var state := {"choice": "<none>"}
	var run := func() -> void:
		state["choice"] = await title._confirm("Start a new journey?", "x", [["new", "Start fresh", "AccentButton"], ["cancel", "Keep", ""]])
	run.call()
	await wait_frames(2)
	assert_not_null(title._panel, "confirm card shown on the title")
	title._panel._choose("new")
	await wait_frames(2)
	assert_eq(String(state["choice"]), "new")
	# Esc on the title answers "cancel"
	run.call()
	await wait_frames(2)
	title._close_panel()
	await wait_frames(2)
	assert_eq(String(state["choice"]), "cancel")


func test_new_game_with_a_save_asks_then_shows_comfort() -> void:
	assert_true(SaveSystem.save_dir.contains("test"), "tests use the test save folder")
	assert_true(SaveSystem.save_game(), "a test save exists")
	title._refresh_continue()
	assert_true(title.continue_btn.visible, "Continue is offered when a save exists")
	var state := {"returned": false}
	var run := func() -> void:
		await title._on_new_game()
		state["returned"] = true
	run.call()
	await wait_frames(2)
	var dlg: Control = title._panel
	assert_true(dlg != null and dlg.has_signal("chosen"), "overwrite warning shown first")
	dlg._choose("new")
	await wait_frames(3)
	var comfort: Control = title._panel
	assert_true(comfort != null and comfort.has_signal("confirmed"), "comfort screen follows")
	assert_false(bool(state["returned"]), "waiting on the comfort screen")
	# Back out with Esc: stays on the title, no game started.
	title._close_panel()
	await wait_frames(3)
	assert_true(bool(state["returned"]), "flow finished")
	assert_false(bool(title._busy), "title still usable (no game started)")
	assert_ne(Game.mode, "loading")


func test_keep_my_save_cancels_new_game() -> void:
	SaveSystem.save_game()
	var run := func() -> void:
		await title._on_new_game()
	run.call()
	await wait_frames(2)
	title._panel._choose("cancel")
	await wait_frames(3)
	assert_null(title._panel, "nothing else opens after 'Keep my save'")
	assert_false(bool(title._busy))


## The Continue line resolves the saved step when shown, so it follows the arachnophobia option (a save
## made in "The Silk Hollows" reads "The Pale Hollows" with the option on), and it is refreshed when a
## panel (Settings) closes on the title.
func test_continue_line_follows_arachnophobia() -> void:
	var was := bool(Settings.get_value("arachnophobia"))
	Settings.set_value("arachnophobia", false)
	var steps: Array = GameState.quests.steps()
	for i in steps.size():
		if String(steps[i]["id"]) == "silk":
			GameState.quests.index = i
	assert_true(SaveSystem.save_game(), "test save written")
	title._refresh_continue()
	var off_text := String(title.continue_sub.text)
	title._on_settings()
	await wait_frames(2)
	Settings.set_value("arachnophobia", true)
	title._close_panel()
	await wait_frames(1)
	var on_text := String(title.continue_sub.text)
	var pure := TitleScreen.continue_text(SaveSystem.peek())
	Settings.set_value("arachnophobia", was)
	assert_true(off_text.contains("The Silk Hollows"), "option off: '%s'" % off_text)
	assert_true(on_text.contains("The Pale Hollows"), "option on after closing Settings: '%s'" % on_text)
	assert_false(on_text.contains("Silk"), "no spider wording with the option on: '%s'" % on_text)
	assert_true(pure.contains("The Pale Hollows"), "continue_text uses the live step title: '%s'" % pure)
	# Past the last step (or an unknown step) the stored title is used.
	assert_eq(TitleScreen.continue_text({"meta": {"day": 9, "step": "", "step_title": "Chapter complete"}}), "Day 9  ·  Chapter complete")
	assert_eq(TitleScreen.continue_text({"meta": {"day": 2, "step": "no_such_step", "step_title": "Old Title"}}), "Day 2  ·  Old Title")
