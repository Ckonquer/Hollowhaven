extends "res://tests/test_case.gd"
## Echo Trials through the REAL Game flow (Game.load_area / change_area / on_player_died / continue_game, the real
## origin areas and their echo stones; module D1), headless:
##   * Count Velour: from the manor's ballroom rest candles into the echo; entering never saves and keeps the origin as
##     the respawn; the pale door (leave) returns to the ballroom candles; a fall in the echo wakes Krystal there too
##     (a loss: nothing changes); a save written inside the echo continues at the origin, never in the trial;
##   * the Borrowed Choir: from the Bell Throat into the echo and back through the pale door;
##   * a repeat clear's gift (lead decision L08) is paid on arrival back at the origin, never inside the echo.
## Story flags are identical before and after every trip. The runner scene is protected like
## test_flow_ch2_roundtrip (current_scene swapped for a placeholder).

const EchoTrial := preload("res://src/world/areas_ch2/echo_trial.gd")
const STORY_FLAGS := ["weaver_defeated", "ward_restored", "chapter_one_complete", "ch2_accepted", "ch2_velour_defeated",
	"ch2_manor_restored", "ch2_choir_defeated", "ch2_crossing_cleared", "chapter_two_complete"]

var _runner: Node = null
var _saved_mode: String = ""
var _ended: Array = []


func before_each() -> void:
	fresh_state()
	_runner = get_tree().current_scene
	_saved_mode = Game.mode
	_reset_game()
	SaveSystem.delete_test_saves()
	var ph := Node.new()
	ph.name = "TrialsPlaceholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	_ended.clear()
	Events.trial_ended.connect(_on_ended)


func after_each() -> void:
	Events.trial_ended.disconnect(_on_ended)
	_reset_game()
	Game.mode = _saved_mode
	EchoTrial.pending_trial = ""
	var cs := get_tree().current_scene
	if cs != null and cs != _runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "TrialsPlaceholder" or n.name == "MoonveilManor" or n.name == "HushedWorks" or n.name == "EchoTrial":
			n.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	GameState.active = false
	SaveSystem.delete_test_saves()
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


func _on_ended(id: String, won: bool) -> void:
	_ended.append([id, won])


func _reset_game() -> void:
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game._travel_seq += 1
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game._bosses.clear()


func _playing() -> bool:
	return Game.mode == "playing" and not Game._transitioning and Game.player != null and is_instance_valid(Game.player)


func _until(cond: Callable, max_frames: int = 1500) -> bool:
	for i in max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _arrived(area_name: String) -> bool:
	var ok: bool = await _until(func() -> bool: return _playing() and Game.area_id == area_name)
	await wait_seconds(0.8)
	await wait_frames(4)
	return ok


func _near_spawn(spawn: String, tol: float = 1.2) -> bool:
	if Game.area == null or Game.player == null:
		return false
	var xf: Transform3D = Game.area.get_spawn(spawn)
	var p: Vector3 = Game.player.global_position
	return Vector2(p.x - xf.origin.x, p.z - xf.origin.z).length() < tol


func _saved_area() -> String:
	var saved: Dictionary = SaveSystem._read_and_validate(SaveSystem._path())
	var st: Variant = saved.get("state", {})
	return String(((st as Dictionary).get("player", {}) as Dictionary).get("area", "")) if st is Dictionary else ""


## _saved_area(), re-read for a few frames while it comes back empty: a freshly renamed save file can be briefly
## unreadable on Windows (a scanner holding it; seen once in a loaded parallel run). Only "" is retried, so a save
## written for another area still fails the assertion at once.
func _saved_area_settled() -> String:
	var a := _saved_area()
	for i in 30:
		if a != "":
			break
		await get_tree().process_frame
		a = _saved_area()
	return a


func _respawn() -> Array:
	return [String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))]


func _story() -> Dictionary:
	var out := {}
	for f in STORY_FLAGS:
		out[f] = bool(GameState.get_flag(f))
	return out


func _completed_journey() -> void:
	for f in ["chapter_one_complete", "weaver_defeated", "ward_restored", "ch2_accepted", "ch2_velour_defeated",
			"ch2_manor_restored", "ch2_crossing_cleared", "ch2_choir_defeated", "ch2_line_water", "ch2_line_bell", "ch2_line_light",
			"ch2_false_home_revealed", "mm_ballroom_solved"]:
		GameState.set_flag(f, true)
	GameState.give_item("lantern", 1)


func test_velour_echo_returns_to_the_ballroom_candles() -> void:
	_completed_journey()
	Game.load_area("moonveil_manor", "manor_ballroom", false)
	assert_true(await _arrived("moonveil_manor"), "in the manor")
	Game.set_respawn("moonveil_manor", "manor_ballroom")
	assert_true(SaveSystem.save_game(true), "a save at the candles")
	var story := _story()
	var entry: Node = Game.area.get("echo_entry")
	assert_not_null(entry, "the echo stone stands by the ballroom candles")
	if entry == null:
		return
	# In through the stone (the confirm menu is the UI's; enter() is what "Enter the echo" does).
	assert_true(bool(entry.call("enter")))
	assert_true(await _arrived("echo_trial"), "in the echo")
	assert_eq(String(Game.area.get("trial_id")), "velour", "the Count's echo")
	var boss: Node = Game.area.get("boss")
	assert_true(boss != null and String(boss.get("mode")) == "trial", "the real Count in trial mode")
	assert_true(_near_spawn("trial_start"), "on the entry pad")
	assert_true(bool(Game.area.is_safe_zone(Game.player.global_position)), "the pad is safe")
	assert_eq(await _saved_area_settled(), "moonveil_manor", "entering a trial doesn't save")
	assert_eq(_respawn(), ["moonveil_manor", "manor_ballroom"], "the origin is the respawn")
	assert_false(bool(Game.can_manual_save()["ok"]), "no saving in a trial")
	# The pale door: back to the candles.
	Game.area.call("leave")
	assert_true(await _arrived("moonveil_manor"), "the pale door leads back to the manor")
	assert_true(_near_spawn("manor_ballroom"), "at the ballroom candles")
	assert_eq(_ended, [["velour", false]], "leaving ends the echo (not a clear)")
	assert_eq(_story(), story, "story flags untouched")
	assert_eq(int(EchoTrial.record("velour")["clears"]), 0, "no clear recorded")
	# A fall inside the echo: she wakes at the candles.
	_ended.clear()
	(Game.area.get("echo_entry") as Node).call("enter")
	assert_true(await _arrived("echo_trial"), "in the echo again")
	Game.on_player_died()
	assert_true(await _arrived("moonveil_manor"), "a fall in the echo wakes her in the manor")
	assert_true(_near_spawn("manor_ballroom"), "by the ballroom candles")
	assert_eq(_ended, [["velour", false]], "a loss")
	assert_eq(_story(), story, "story flags untouched")
	# A save written inside the echo (by some other system) continues at the origin.
	(Game.area.get("echo_entry") as Node).call("enter")
	assert_true(await _arrived("echo_trial"), "in the echo a third time")
	assert_true(SaveSystem.save_game(true), "forced save inside the trial")
	assert_eq(await _saved_area_settled(), "echo_trial")
	fresh_state()
	Game.continue_game()
	assert_true(await _arrived("moonveil_manor"), "Continue leaves the echo for the manor")
	assert_true(_near_spawn("manor_ballroom"), "at the ballroom candles after Continue")
	assert_eq(_story(), story, "story flags as saved")


## Lead decision L08, through the real flow: with a full backpack a repeat win drops nothing inside the echo; the
## gift waits in the trial's record and the arrival back at the ballroom candles pays it once (what does not fit drops
## there, a pickup of the manor). A save written between a win and the arrival, then Continue, pays it exactly once.
func test_a_repeat_gift_is_paid_on_arrival_at_the_origin() -> void:
	_completed_journey()
	EchoTrial.record_clear("velour", 200.0)           # the first clear is already in the ledger
	Game.load_area("moonveil_manor", "manor_ballroom", false)
	assert_true(await _arrived("moonveil_manor"), "in the manor")
	Game.set_respawn("moonveil_manor", "manor_ballroom")
	for i in GameState.inventory.size:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})
	var notes: Array = []
	var on_note := func(t: String, _k: String) -> void: notes.append(t)
	Events.notify.connect(on_note)
	var story := _story()
	var entry: Node = Game.area.get("echo_entry")
	assert_not_null(entry, "the echo stone stands by the ballroom candles")
	if entry == null:
		Events.notify.disconnect(on_note)
		return
	assert_true(bool(entry.call("enter")))
	assert_true(await _arrived("echo_trial"), "in the echo")
	var dropped_before := GameState.dropped.size()
	Game.area.call("_on_boss_defeated")                # a win (the fight itself: test_trials_velour)
	assert_eq(EchoTrial.record("velour").get("pending", {}), {"lantern_wax": 2, "moonpetal": 2}, "the gift waits")
	assert_eq(GameState.dropped.size(), dropped_before, "a full backpack drops nothing inside the echo")
	assert_eq(GameState.dropped_in_area("echo_trial"), [])
	assert_true(notes.has("The echo's gift waits for you back at the ballroom candles."), "she is told where it waits")
	notes.clear()
	# Home through the pale door (the win arms it; leave() is what its timer calls).
	Game.area.call("leave")
	assert_true(await _arrived("moonveil_manor"), "back at the ballroom candles")
	assert_eq(GameState.dropped_in_area("echo_trial"), [], "still nothing inside the echo")
	var sp: Vector3 = (Game.area.get_spawn("manor_ballroom") as Transform3D).origin
	var got := {}
	for d in GameState.dropped_in_area("moonveil_manor"):
		got[String(d["item"])] = int(got.get(String(d["item"]), 0)) + int(d["count"])
		var p: Array = d["pos"]
		assert_true(Vector3(float(p[0]), float(p[1]), float(p[2])).distance_to(sp) < 1.5, "dropped at the safe origin checkpoint")
	assert_eq(got, {"lantern_wax": 2, "moonpetal": 2}, "the overflow waits at the origin")
	var rec := EchoTrial.record("velour")
	assert_false(rec.has("pending"), "paid")
	assert_eq(int(rec.get("repeat_paid", 0)), 1)
	assert_eq(notes.filter(func(t: Variant) -> bool: return String(t).begins_with("The echo's gift: ")).size(), 1, "one toast")
	assert_true(await _until(func() -> bool: return _saved_area() == "moonveil_manor", 240), "the arrival saved (with the gift paid)")
	# A save written between a win and the arrival (by some other system), then Continue: paid exactly once.
	(Game.area.get("echo_entry") as Node).call("enter")
	assert_true(await _arrived("echo_trial"), "in the echo again")
	Game.area.call("_on_boss_defeated")                # the third clear: + the bonus
	assert_true(SaveSystem.save_game(true), "forced save inside the trial")
	fresh_state()
	Game.continue_game()
	assert_true(await _arrived("moonveil_manor"), "Continue leaves the echo for the manor")
	got = {}
	for d in GameState.dropped_in_area("moonveil_manor"):
		got[String(d["item"])] = int(got.get(String(d["item"]), 0)) + int(d["count"])
	assert_eq(got, {"lantern_wax": 4, "moonpetal": 4, "woven_cloth": 1}, "the second gift paid once on arrival")
	rec = EchoTrial.record("velour")
	assert_false(rec.has("pending"), "nothing waits any more")
	assert_eq(int(rec.get("repeat_paid", 0)), 2)
	assert_eq(int(rec.get("clears", 0)), 3)
	assert_eq(EchoTrial.pay_pending("moonveil_manor"), {}, "a later arrival pays nothing more")
	assert_eq(GameState.dropped_in_area("echo_trial"), [])
	assert_eq(_story(), story, "story flags untouched")
	Events.notify.disconnect(on_note)


func test_choir_echo_returns_to_the_bell_throat() -> void:
	_completed_journey()
	Game.load_area("hushed_works", "bell_throat", false)
	assert_true(await _arrived("hushed_works"), "in the Works")
	Game.set_respawn("hushed_works", "bell_throat")
	var story := _story()
	var entry: Node = Game.area.get("echo_entry")
	assert_not_null(entry, "the echo stone stands in the Bell Throat")
	if entry == null:
		return
	assert_true(bool(entry.call("enter")))
	assert_true(await _arrived("echo_trial"), "in the echo")
	assert_eq(String(Game.area.get("trial_id")), "choir", "the Choir's echo")
	var boss: Node = Game.area.get("boss")
	assert_true(boss != null and String(boss.get("mode")) == "trial", "the real Choir in trial mode")
	assert_eq(_respawn(), ["hushed_works", "bell_throat"], "the origin is the respawn")
	var door: Node = (Game.area.get("exits") as Dictionary).get("leave")
	assert_eq(door.call("destination"), {"area": "hushed_works", "spawn": "bell_throat"}, "the pale door leads to the Bell Throat")
	door.interact(Game.player)
	assert_true(await _arrived("hushed_works"), "back in the Works")
	assert_true(_near_spawn("bell_throat"), "at the Bell Throat")
	assert_eq(_story(), story, "story flags untouched")
