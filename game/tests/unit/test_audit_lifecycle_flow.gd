extends "res://tests/test_case.gd"
## AUDIT (runtime lifecycle): drives the real Game flow headless (Game.load_area / change_area /
## on_player_died / goto_title) and checks what is left behind. The runner scene is protected by
## swapping get_tree().current_scene to a placeholder first, so the scene changes free the placeholder /
## area instead of the test runner.
## Regression guards for fixed audit findings:
##   * closing the window saves first (auto_accept_quit off + Game.save_before_close), New Game saves at
##     once and the surface autosaves quietly;
##   * the surface respawn after climbing out of the mine without a bed is the Haven, not the mine mouth;
##   * focus lost during the death screen still pauses once Krystal is back on her feet.
## The others are cheap guards for flows that were verified clean (pause->quit to title, death/respawn,
## hitstop never leaving Engine.time_scale slowed).

var _runner: Node = null
var _saved_mode: String = ""


func before_each() -> void:
	fresh_state()
	GameState.active = true
	_runner = get_tree().current_scene
	_saved_mode = Game.mode
	var ph := Node.new()
	ph.name = "AuditPlaceholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph


func after_each() -> void:
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game.mode = _saved_mode
	var cs := get_tree().current_scene
	if cs != null and cs != _runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "AuditPlaceholder" or n.name == "Title" or n.name == "Surface" or n.name == "Below" or n.name == "AuditHitstop":
			n.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


# --- helpers -----------------------------------------------------------------------------------------

func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


## Like _until, but bounded by real seconds (frame rate independent).
func _until_seconds(cond: Callable, seconds: float) -> bool:
	var end_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _playing() -> bool:
	return Game.mode == "playing" and not Game._transitioning and Game.player != null and is_instance_valid(Game.player)


## Loads an area through the real Game flow (not awaited: a hung coroutine must not hang the runner).
func _start_area(area_name: String, spawn: String) -> bool:
	Game.load_area(area_name, spawn, false)
	var ok: bool = await _until(_playing, 1200)
	await wait_frames(10)
	return ok


func _kill_player() -> void:
	var h: Node = Game.player.get("health")
	h.set("invulnerable", false)
	h.apply_damage(99999.0, null, Vector3.ZERO)


func _saved_flags() -> Dictionary:
	var saved: Dictionary = SaveSystem._read_and_validate(SaveSystem._path())
	var st: Variant = saved.get("state", {})
	var flags: Variant = (st as Dictionary).get("flags", {}) if st is Dictionary else {}
	return flags if flags is Dictionary else {}


# --- fixed findings ----------------------------------------------------------------------------------

## Closing the window (title-bar X / Alt+F4) on the surface: progress since the last save must not be
## silently thrown away. Game turns auto_accept_quit off and handles NOTIFICATION_WM_CLOSE_REQUEST with
## save_before_close() + quit. (The real notification is not sent here: the handler quits, which would
## end the test runner. Game._on_close_requested() is save_before_close() + Settings.save() + quit.)
func test_window_close_request_on_the_surface_keeps_progress() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	assert_true(SaveSystem.save_game(), "baseline save")
	GameState.set_flag("audit_progress_after_last_save", true)   # e.g. 30 minutes of gathering/building
	assert_true(Game.save_before_close(), "closing on the surface saves")
	assert_true(bool(_saved_flags().get("audit_progress_after_last_save", false)),
		"window close request saved the progress made since the last save")
	assert_true(get_tree().auto_accept_quit == false, "the game intercepts the close request (auto_accept_quit off)")


## Underground the lantern saves stand: closing there must not write a save (Krystal would otherwise
## Continue at a spot that isn't a lantern), and neither must closing on the title or the death screen.
func test_close_request_saves_only_where_a_manual_save_is_allowed() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	Game.mode = "dead"
	assert_false(Game.save_before_close(), "no save from the death screen")
	Game.mode = "playing"
	Game.area_id = "below"
	assert_false(Game.save_before_close(), "no save underground")
	Game.area_id = "surface"
	GameState.active = false
	assert_false(Game.save_before_close(), "no save without an active playthrough (title)")
	GameState.active = true


## New Game writes a save right away, so Continue exists from the first minute (before, the first save
## was the bed at quest step 8), and does it quietly (no "Journey saved" toast over the chapter card).
func test_new_game_saves_straight_away_and_quietly() -> void:
	SaveSystem.delete_test_saves()
	assert_false(SaveSystem.has_save(), "precondition: no save")
	var saved_sig: Array = []
	var cb := func(ok: bool) -> void: saved_sig.append(ok)
	Events.game_saved.connect(cb)
	Game.new_game()
	var ok: bool = await _until(_playing, 1200)
	# load_area's fade-in (0.6 s) ends before new_game() saves.
	await _until_seconds(func() -> bool: return SaveSystem.has_save(), 3.0)
	await wait_frames(2)
	Events.game_saved.disconnect(cb)
	assert_true(ok, "new game loaded")
	assert_true(SaveSystem.has_save(), "New Game wrote a save")
	assert_eq(saved_sig.size(), 0, "the New Game save is quiet (no game_saved toast)")


## The surface autosave: saves quietly once the countdown runs out, waits while a menu is open or
## Krystal is underground, and any save restarts the countdown.
func test_surface_autosave_is_quiet_and_waits_for_a_safe_moment() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	SaveSystem.delete_test_saves()
	var saved_sig: Array = []
	var cb := func(ok: bool) -> void: saved_sig.append(ok)
	Events.game_saved.connect(cb)
	assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS * 0.5), "not yet")
	assert_false(SaveSystem.has_save(), "nothing saved before the countdown ends")
	Game.push_ui("audit_menu")
	assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS), "waits while a menu is open")
	Game.pop_ui("audit_menu")
	GameState.set_flag("audit_autosaved", true)
	assert_true(Game._tick_autosave(Game.AUTOSAVE_RETRY + 0.1), "saves once the menu is closed")
	assert_true(bool(_saved_flags().get("audit_autosaved", false)), "the autosave holds the latest progress")
	assert_eq(saved_sig.size(), 0, "autosave is quiet")
	assert_false(Game._tick_autosave(1.0), "countdown restarted")
	Events.game_saved.emit(true)   # e.g. the bed
	assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS - 1.0), "any save restarts the countdown")
	Events.game_saved.disconnect(cb)
	Game.area_id = "below"
	assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS * 2.0), "no autosave underground")
	Game.area_id = "surface"


## Alt-tab while the death screen is up (mode "dead", nothing can pause): the pause menu must open
## once Krystal is back on her feet instead of the world running on unattended.
func test_focus_lost_on_the_death_screen_pauses_after_the_respawn() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	var keep: bool = Debug.keep_running_unfocused
	Debug.keep_running_unfocused = false
	_kill_player()
	assert_eq(Game.mode, "dead", "death screen")
	Game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var back: bool = await _until_seconds(func() -> bool: return Game.mode == "playing" and get_tree().paused, 8.0)
	var pause_open: bool = Game.ui != null and bool(Game.ui.call("is_open", "pause"))
	Debug.keep_running_unfocused = keep
	Game._focus_lost = false
	assert_true(back, "respawned and paused")
	assert_true(pause_open, "the pause menu is open after the respawn")


## GAME_SPEC: "Death -> wake at bed/Haven or last lit dungeon lantern". After climbing out of the mine
## (no bed built yet) Game.change_area sets the surface respawn to the arrival spawn "mine_exit", so a
## later death on the surface wakes Krystal at the mine mouth on the NE cliff instead of the Haven.
func test_surface_respawn_after_climbing_out_without_a_bed_is_the_haven() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	Game.change_area("below", "mine_entry")
	assert_true(await _until(func() -> bool: return _playing() and Game.area_id == "below", 1500), "below")
	await wait_seconds(0.8)
	Game.area.call("_climb_out", Game.player)
	assert_true(await _until(func() -> bool: return _playing() and Game.area_id == "surface", 1500), "surface again")
	await wait_seconds(0.8)
	var rs := String(GameState.player.get("respawn_spawn", ""))
	assert_true(rs == "bed" or rs.begins_with("haven"), "surface respawn after the mine is the Haven, got '%s'" % rs)
	_kill_player()
	assert_true(await _until(func() -> bool: return Game.mode == "playing", 900), "respawned")
	await wait_seconds(0.8)
	var p: Vector3 = Game.player.global_position
	var d := Vector2(p.x, p.z).length()
	assert_true(d < 25.0, "woke up in the Haven clearing (%.0f m from the Ward Stone)" % d)


# --- guards (pass today) -----------------------------------------------------------------------------

func test_surface_pause_then_quit_to_title_leaves_clean_state() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	Game.open_panel("pause")
	await wait_frames(3)
	assert_true(get_tree().paused, "pause menu pauses the tree")
	Game.quit_to_title()
	await wait_frames(20)
	assert_eq(Game.mode, "title", "mode after quit to title")
	assert_false(get_tree().paused, "tree unpaused on the title")
	assert_false(Game._transitioning, "no transition left pending")
	assert_eq(Engine.time_scale, 1.0, "time scale on the title")


func test_surface_death_respawns_cleanly() -> void:
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	var first_player: Node = Game.player
	_kill_player()
	assert_eq(Game.mode, "dead", "mode right after the killing blow")
	assert_true(await _until(func() -> bool: return Game.mode == "playing", 900), "respawned")
	await wait_seconds(1.2)     # the fade-in (0.6 s) ends before Events.player_respawned
	assert_true(is_instance_valid(first_player), "same-area respawn keeps the player node")
	assert_false(bool(Game.player.call("is_dead")), "player alive after respawn")
	assert_false(get_tree().paused, "not paused after respawn")
	assert_true(Game.gameplay_input_allowed(), "gameplay input allowed after respawn")
	assert_false(bool(Game.ui.get("hud").call("is_cinematic")), "HUD not cinematic after respawn")


## Hitstop (installed manually: HitFx.ensure_hitstop() is a no-op headless): a pause, a quit to title
## (scene change) and freeing the listener mid-dip must all leave Engine.time_scale at 1.0.
func test_hitstop_never_leaves_time_scale_slowed() -> void:
	var HitFx: Script = load("res://src/combat/hit_fx.gd")
	var l: Node = HitFx.HitstopListener.new()
	l.name = "AuditHitstop"
	get_tree().root.add_child(l)
	await wait_frames(1)
	Events.hitstop.emit(0.08)
	assert_almost(Engine.time_scale, 0.05, 0.001, "dip applied")
	get_tree().paused = true
	await wait_frames(2)
	assert_almost(Engine.time_scale, 1.0, 0.001, "pause restores")
	get_tree().paused = false
	assert_true(await _start_area("surface", "haven_start"), "surface loaded")
	Events.hitstop.emit(0.08)
	Game.quit_to_title()
	await wait_seconds(0.3)
	assert_almost(Engine.time_scale, 1.0, 0.001, "quit to title mid-dip restores")
	Events.hitstop.emit(0.08)
	l.free()
	assert_almost(Engine.time_scale, 1.0, 0.001, "freeing the listener mid-dip restores")
