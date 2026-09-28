extends "res://tests/test_case.gd"
## Loading card (perf finding qa/tmp/perf/packaged_v200_nofocus: an area builds all its children in ONE blocking
## main-thread frame - 0.85-2.8 s cold in the packaged build - and Continue from the title had no fade, so the screen
## froze on whatever was drawn last). Game.load_area() must have its loading card (src/ui/screens/loading_card.gd)
## FULLY shown, with frames showing it already drawn, BEFORE the scene change removes the old scene and before the new
## area root enters the tree (its _ready is the blocking build), and must remove it only after the area is built,
## while the UI root fades the area in.
## Probes: the old scene's tree_exiting, SceneTree.node_added for the new area root (added to the tree root before its
## _ready builds anything) and Events.area_loaded. Runs the REAL flow headless: Continue from a real title scene (no UI
## root yet: the title's own fade + the card) and an area change with the UI root present (its fade + the card + the
## HUD hush). The runner scene is protected like the other flow suites (current_scene is swapped for a placeholder).
## Saves only go to the runner's user://test_saves/ folder; settings are never written.

const TitleScreen := preload("res://src/ui/title_screen.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const CardScript := preload("res://src/ui/screens/loading_card.gd")

const AREA := "tobin_annex"
const SPAWN := "annex_entry"
const AREA_SCENE := "res://scenes/tobin_annex.tscn"
const AREA_TITLE := "Tobin's Annex"
## Frames with the full card that must already have been drawn when the build starts (the card's PRESENT_FRAMES, never
## fewer than two: the frozen frame must keep showing a presented card, whatever the swap chain's latency).
const MIN_FRAMES_DRAWN := 2

var _runner: Node = null
var _placeholder: Node = null
var _saved_mode: String = ""
var _flashing_was: Variant = false
var _watch_scene := ""             # scene_file_path of the area root node_added should report
var _probe: Array = []             # snapshots, see _snapshot()


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	GameState.active = false
	_runner = get_tree().current_scene
	_saved_mode = Game.mode
	_flashing_was = Settings.get_value("reduce_flashing")
	Game._transitioning = false
	Game._travel_seq += 1          # a trip left over from an earlier suite never saves into this one
	Game.hide_loading_card(0.0)
	Game.release_prefetches()
	SaveSystem.delete_test_saves()
	_probe = []
	_watch_scene = ""
	_placeholder = Node.new()
	_placeholder.name = "LoadingCardPlaceholder"
	get_tree().root.add_child(_placeholder)
	get_tree().current_scene = _placeholder


func after_each() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if Events.area_loaded.is_connected(_on_area_loaded):
		Events.area_loaded.disconnect(_on_area_loaded)
	Game.hide_loading_card(0.0)
	Settings.set_value("reduce_flashing", _flashing_was)
	if is_instance_valid(Game.ui):
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
	Game._bosses.clear()
	var cs := get_tree().current_scene
	if cs != null and cs != _runner and is_instance_valid(cs):
		cs.queue_free()
	if is_instance_valid(_placeholder):
		_placeholder.queue_free()
	get_tree().current_scene = _runner
	get_tree().paused = false
	GameState.active = false
	SaveSystem.delete_test_saves()
	Game.release_prefetches()
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


# --- helpers -----------------------------------------------------------------------------------------------

func _until(cond: Callable, seconds: float = 30.0) -> bool:
	var end_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _playing_in(area_name: String) -> bool:
	return Game.mode == "playing" and not Game._transitioning and Game.area_id == area_name \
		and is_instance_valid(Game.player)


## load_area has finished: playing, and the card has gone (it dissolves during the UI root's fade-in).
func _settled_in(area_name: String) -> bool:
	return _playing_in(area_name) and not Game.loading_card_showing() \
		and (not is_instance_valid(Game.ui) or float(Game.ui.fade_rect.color.a) <= 0.001)


## What the screen shows at one moment of a load.
func _snapshot(at: String) -> Dictionary:
	var c: Node = Game.loading_card
	var has_card := is_instance_valid(c)
	var ui: Node = Game.ui
	var has_ui := is_instance_valid(ui) and ui.get("fade_rect") is ColorRect
	var shown := int(c.get("shown_frame")) if has_card else -1
	return {
		"at": at,
		"card_full": has_card and bool(c.is_fully_shown()),
		"card_up": has_card and bool(c.is_showing()),
		"frames_drawn": (Engine.get_process_frames() - shown) if shown >= 0 else -1,
		"has_ui": has_ui,
		"ui_black": has_ui and float((ui.get("fade_rect") as ColorRect).color.a) >= 0.999,
		"hush": String(ui.hush_reason()) if has_ui and ui.has_method("hush_reason") else "",
		"mode": Game.mode,
	}


func _on_node_added(n: Node) -> void:
	if _watch_scene != "" and n.get_parent() == get_tree().root and n.scene_file_path == _watch_scene:
		_probe.append(_snapshot("area_added"))


func _on_area_loaded(_a: String) -> void:
	_probe.append(_snapshot("area_loaded"))


func _snap(at: String) -> Dictionary:
	for s in _probe:
		if String((s as Dictionary)["at"]) == at:
			return s
	return {}


## Watches the next load of `scene_path`: the scene that leaves (`leaving`), the area root entering and area_loaded.
func _watch(scene_path: String, leaving: Node) -> void:
	_watch_scene = scene_path
	_probe = []
	get_tree().node_added.connect(_on_node_added)
	Events.area_loaded.connect(_on_area_loaded)
	leaving.tree_exiting.connect(func() -> void: _probe.append(_snapshot("old_scene_exit")), CONNECT_ONE_SHOT)


## The card was fully on screen, with at least PRESENT_FRAMES frames showing it drawn, when the heavy work started.
func _assert_card_before_build(label: String) -> void:
	for s in _probe:     # evidence in the test log
		print("  LOADING %s @%s: card_full=%s frames_drawn=%d ui_black=%s hush=%s mode=%s" % [label, s["at"],
			str(s["card_full"]), int(s["frames_drawn"]), str(s["ui_black"]) if bool(s["has_ui"]) else "no-ui", s["hush"], s["mode"]])
	for at in ["old_scene_exit", "area_added"]:
		var s := _snap(at)
		assert_false(s.is_empty(), "%s: %s observed" % [label, at])
		if s.is_empty():
			continue
		assert_true(bool(s["card_full"]), "%s: the loading card is fully shown at %s %s" % [label, at, str(s)])
		assert_true(int(s["frames_drawn"]) >= maxi(MIN_FRAMES_DRAWN, CardScript.PRESENT_FRAMES),
			"%s: at %s, %d frame(s) with the full card were already drawn (need %d) %s" % [label, at, int(s["frames_drawn"]), maxi(MIN_FRAMES_DRAWN, CardScript.PRESENT_FRAMES), str(s)])
		assert_eq(String(s["mode"]), "loading", "%s: %s happens while loading" % [label, at])
	# Removed only AFTER the build: still up when the area reports loaded (the dissolve starts right after).
	var done := _snap("area_loaded")
	assert_false(done.is_empty(), "%s: area_loaded observed" % label)
	if not done.is_empty():
		assert_true(bool(done["card_full"]), "%s: the card is still fully shown when the area is built %s" % [label, str(done)])


# --- Continue from the title -------------------------------------------------------------------------------

## Continue: the title fades to black, Game covers it with the loading card, and only then does the scene change
## remove the title and add the area (whose _ready is the frozen frame). Afterwards the card is gone and the area has
## faded in.
func test_continue_from_the_title_shows_the_card_before_the_build_and_removes_it_after() -> void:
	GameState.player["area"] = AREA
	GameState.player["spawn"] = SPAWN
	assert_true(SaveSystem.save_game(true), "a save in the annex")
	var title := TitleScreen.new()
	_placeholder.add_child(title)          # the title belongs to the scene the change removes, as in the game
	await wait_frames(3)
	assert_true(title.continue_btn.visible, "Continue is offered")
	assert_true(Game.is_prefetching(AREA_SCENE) or ResourceLoader.has_cached(AREA_SCENE),
		"the title started compiling the area Continue resumes in")
	assert_false(Game.loading_card_showing(), "no card on the title")
	_watch(AREA_SCENE, _placeholder)
	title._on_continue()
	assert_true(await _until(func() -> bool: return _playing_in(AREA)), "Continue arrived in the annex")
	_assert_card_before_build("Continue")
	var s := _snap("area_added")
	if not s.is_empty():
		assert_false(bool(s["has_ui"]), "from the title there is no UI root yet: the card alone covers the build")
	assert_eq(String(Game.loading_card.name_l.text), AREA_TITLE, "the card names the area")
	assert_true(await _until(func() -> bool: return _settled_in(AREA), 5.0), "the card dissolved and the area faded in")
	assert_false(Game.loading_card.visible, "the card is hidden after the load")
	assert_false(Game.loading_card_showing())
	assert_almost(float(Game.ui.fade_rect.color.a), 0.0, 0.001, "the area faded in")
	assert_eq(String(Game.ui.hush_reason()), "", "the HUD chatter is free again")


## New Game after "Meet Krystal" goes through the same load_area: the card is up before the Haven builds. (Game.new_game
## is called directly: the title's hand-over is Game.new_game.call_deferred(look) after the same fade as Continue.)
func test_new_game_shows_the_card_before_the_haven_builds() -> void:
	_watch("res://scenes/surface.tscn", _placeholder)
	var state := {"done": false}
	var run := func() -> void:
		await Game.new_game({})
		state["done"] = true
	run.call()
	assert_true(await _until(func() -> bool: return bool(state["done"]), 60.0), "the Haven loaded and New Game finished")
	_assert_card_before_build("New Game")
	assert_eq(String(Game.loading_card.name_l.text), "Hollowhaven Woods", "the card names the Woods")
	assert_false(Game.loading_card_showing(), "the card has gone once new_game() returns")


# --- Area change with the UI root (Lantern Road, doors, mine) ---------------------------------------------------

## Travelling between areas: the UI root fades to black, the card comes up over it (HUD chatter hushed "loading"),
## frames with it are drawn, THEN the old area leaves and the new one builds; afterwards the card dissolves while the
## UI fades in, and change_area's arrival save still happens.
func test_area_change_fades_and_shows_the_card_before_the_build_then_fades_in() -> void:
	Game.load_area(AREA, SPAWN, false)
	assert_true(await _until(func() -> bool: return _settled_in(AREA)), "first load finished")
	var old_area: Node = Game.area
	assert_not_null(old_area)
	_watch(AREA_SCENE, old_area)
	var old_id := old_area.get_instance_id()
	Game.change_area(AREA, SPAWN)
	assert_true(await _until(func() -> bool: return _playing_in(AREA) and is_instance_valid(Game.area) and Game.area.get_instance_id() != old_id), "arrived again")
	_assert_card_before_build("area change")
	for at in ["old_scene_exit", "area_added"]:
		var s := _snap(at)
		if s.is_empty():
			continue
		assert_true(bool(s["has_ui"]) and bool(s["ui_black"]), "%s: the UI root had faded to black %s" % [at, str(s)])
		assert_eq(String(s["hush"]), "loading", "%s: the HUD chatter waits behind the card" % at)
	assert_true(await _until(func() -> bool: return _settled_in(AREA), 5.0), "the card dissolved and the area faded in")
	assert_false(Game.loading_card.visible)
	assert_eq(String(Game.ui.hush_reason()), "", "hush released")
	await wait_seconds(0.3)
	assert_eq(String(SaveSystem.peek().get("meta", {}).get("area", "")), AREA, "change_area still saved on arrival")


# --- The card itself --------------------------------------------------------------------------------------------

## show_card() returns only after PRESENT_FRAMES more frames with the card fully shown; hide_card() removes it.
## The lantern's glow pulses gently, and holds one steady glow with reduce_flashing.
func test_card_waits_for_drawn_frames_and_respects_reduce_flashing() -> void:
	var c: Node = Game.loading_card
	assert_not_null(c, "Game owns a loading card")
	if c == null:
		return
	assert_eq(c.layer, CardScript.LAYER)
	assert_true(c.layer > 50, "above the UI root (layer 50) and the title (10)")
	Settings.set_value("reduce_flashing", false)
	await c.show_card("hallowmere_reach")
	assert_true(c.is_fully_shown(), "fully shown when show_card returns")
	assert_true(Engine.get_process_frames() - int(c.shown_frame) >= MIN_FRAMES_DRAWN, "frames with it were drawn first")
	assert_eq(String(c.name_l.text), "Hallowmere Reach")
	assert_true(c.is_pulsing(), "the lantern glow breathes")
	assert_eq(c.backdrop.mouse_filter, Control.MOUSE_FILTER_STOP, "clicks don't reach whatever is behind it")
	c.hide_card()
	assert_true(c.is_hiding())
	assert_true(await _until(func() -> bool: return not c.is_showing(), 2.0), "dissolved")
	assert_false(c.visible)
	assert_false(c.is_pulsing(), "no animation while hidden")
	Settings.set_value("reduce_flashing", true)
	await c.show_card("moonveil_manor", 0.0)
	assert_true(c.is_fully_shown())
	assert_false(c.is_pulsing(), "reduce_flashing: no pulse")
	assert_almost(float(c.glow.modulate.a), CardScript.GLOW_STEADY, 0.001, "one steady glow")
	c.hide_card(0.0)
	assert_false(c.is_showing(), "fade 0 hides at once")
	assert_eq(CardScript.area_title("no_such_area"), CardScript.FALLBACK_TITLE, "areas without a name get the game's")


## Continue resumes where continue_game() would (shared rule), and the title prefetches exactly that area.
func test_continue_target_and_title_prefetch() -> void:
	var t: Dictionary = Game.continue_target({"area": "hallowmere_reach", "spawn": "x"})
	assert_eq(t, {"area": "hallowmere_reach", "spawn": "x", "use_saved": true})
	t = Game.continue_target({"area": "echo_trial", "spawn": "trial_start", "respawn_area": "hushed_works", "respawn_spawn": "works_lockers"})
	assert_eq(t, {"area": "hushed_works", "spawn": "works_lockers", "use_saved": false}, "a trial resumes at its origin")
	t = Game.continue_target({"area": "echo_trial", "respawn_area": "echo_trial"})
	assert_eq(t, {"area": "surface", "spawn": "haven_respawn", "use_saved": false})
	t = Game.continue_target({"area": "nowhere", "spawn": "s"})
	assert_eq(t, {"area": "surface", "spawn": "s", "use_saved": true}, "an unknown area becomes the surface")
	assert_eq(Game.continue_target({}), {"area": "surface", "spawn": "haven_respawn", "use_saved": true})
	assert_eq(Game.prefetch_continue({}), 0, "no save, nothing to prefetch")
	# A save made in the manor: the title asks for the manor while it shows Continue.
	GameState.player["area"] = "moonveil_manor"
	GameState.player["spawn"] = "manor_entry"
	assert_true(SaveSystem.save_game(true))
	Game.release_prefetches()
	var title := TitleScreen.new()
	add_child(title)
	await wait_frames(3)
	var scene := "res://scenes/moonveil_manor.tscn"
	assert_true(Game.is_prefetching(scene) or ResourceLoader.has_cached(scene), "the manor is compiling while the title is up")
	title.queue_free()


## Static guard on the order inside load_area (the runtime tests above prove it; this names the contract).
func test_load_area_orders_card_scene_change_and_removal() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/game.gd")
	var at := src.find("func load_area(")
	assert_true(at >= 0)
	var end := src.find("\nfunc ", at + 10)
	var body := src.substr(at, end - at)
	var fade := body.find("ui.fade_out(")
	var show := body.find("await show_loading_card(")
	var change := body.find("_change_to_area_scene(")
	var loaded := body.find("Events.area_loaded.emit(")
	var hide := body.find("hide_loading_card(")
	var fade_in := body.find("ui.fade_in(")
	assert_true(fade >= 0 and show > fade, "the card comes up after the UI's fade to black")
	assert_true(change > show, "the scene change comes after the card is on screen (awaited)")
	assert_true(loaded > change and hide > loaded, "the card is removed only after the area is built")
	assert_true(fade_in > hide, "and dissolves while the UI fades in")
