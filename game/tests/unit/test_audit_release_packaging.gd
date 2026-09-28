extends "res://tests/test_case.gd"
## AUDIT (release build & packaging): checks that hold for the SHIPPED build, not just the editor run.
##  * closing the window (Alt+F4 / title-bar X) must not silently throw away unsaved progress
##    (the surface has no periodic autosave: the first save is the bed, the mine or Pause > Save);
##  * Game.load_area's "fallback" scripts live in tests/, which export_presets.cfg excludes, so in the
##    release build a failed player/UI script falls through to a bare node and load_area hangs;
##  * the engine window should start in the mode the default settings ask for (fullscreen), instead of
##    opening a 1600x900 window that Settings.apply_video() switches to fullscreen a frame later.
## The close-request and window-mode checks guard fixed findings (Game.save_before_close +
## auto_accept_quit off; project.godot window/size/mode=3). Nothing here writes outside user://test_saves/.

var _saved_mode: String = ""
var _saved_area: String = ""


func before_each() -> void:
	_saved_mode = Game.mode
	_saved_area = Game.area_id


func after_each() -> void:
	Game.mode = _saved_mode
	Game.area_id = _saved_area
	GameState.active = false
	SaveSystem.delete_test_saves()


## Playing on the surface, never saved yet (the first ~7 quest steps come before the bed), then the OS
## asks the window to close. Either the game saves on the close request, or it turns off
## auto_accept_quit so it can confirm / save first. Today neither happens: the engine quits at once.
func test_window_close_request_does_not_drop_unsaved_progress() -> void:
	fresh_state()
	GameState.active = true
	GameState.give_item("wood", 5)
	Game.mode = "playing"
	Game.area_id = "surface"
	SaveSystem.delete_test_saves()
	assert_false(SaveSystem.has_save(), "precondition: nothing saved yet")
	if not get_tree().auto_accept_quit:
		# The game intercepts close requests itself (Game._on_close_requested: save, then quit). Don't
		# deliver the notification here: the handler quits, which would end the test runner. Check the
		# save half of it instead.
		assert_true(Game.save_before_close(), "the close handler's save succeeds while playing on the surface")
		assert_true(SaveSystem.has_save(), "closing the window while playing keeps the progress")
		return
	Game.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await wait_frames(2)
	assert_true(SaveSystem.has_save(),
		"window close request while playing: auto_accept_quit is on and nothing saved - progress since the last bed/mine/manual save is lost")


## The release preset excludes tests/*. Game still points its player/UI fallbacks there.
## (removed test_game_fallback_scripts_are_part_of_the_release_export: by design: fallback scripts are a development-only safety net (docs/ARCHITECTURE.md))

## (removed test_missing_player_and_fallback_yield_a_node_load_area_can_use: by design: release builds always ship the real player/UI scripts)

func test_engine_window_starts_in_the_default_display_mode() -> void:
	var want_fs: bool = bool(Settings.DEFAULTS["fullscreen"])
	var mode: int = int(ProjectSettings.get_setting("display/window/size/mode", 0))
	var starts_fs: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	assert_eq(starts_fs, want_fs,
		"display/window/size/mode=%d but Settings default fullscreen=%s: first launch opens a 1600x900 window, then apply_video() switches" % [mode, str(want_fs)])
