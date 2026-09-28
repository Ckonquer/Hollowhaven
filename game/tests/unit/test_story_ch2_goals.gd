extends "res://tests/unit/test_core_base.gd"
## Story module C9: the cross-area activity tracker and the story beats it owns - the five cross-area optional
## goals complete once from state and from other modules' events (and never pay twice across a reload), their
## derived state survives save / load, ch2_returned_to_reach after the Choir, the homecoming at the Ward Stone,
## the Lanternwake unlocks applied inside grant_once, and the "Chapter Two" title card on acceptance.

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")


class StubUi extends CanvasLayer:
	var cards: Array = []

	func show_chapter_card(title: String, subtitle: String = "") -> void:
		cards.append([title, subtitle])


var tracker: Node = null
var opt: RefCounted
var _ui_before: Node = null


func setup() -> void:
	fresh_state()
	GameState.active = true
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")
	opt = GameState.optional_goals
	_ui_before = Game.ui
	tracker = Story.new_tracker()
	add_child(tracker)


func teardown() -> void:
	if tracker != null and is_instance_valid(tracker):
		tracker.queue_free()
	tracker = null
	Game.ui = _ui_before
	await wait_frames(1)


func _held(id: String) -> int:
	var n := GameState.count_item(id)
	for d in GameState.dropped:
		if String(d["item"]) == id:
			n += int(d["count"])
	return n


func _reload() -> void:
	assert_true(SaveSystem.save_game(true), "saved")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "loaded")
	GameState.active = true


func test_long_way_home_mirrors_the_manor_balcony_flag() -> void:
	var g: Dictionary = opt.goal("opt_long_way_home")
	GameState.set_flag("ta_hatch_open")
	GameState.set_flag("ch2_refuge_shortcut")
	opt.evaluate()
	assert_false(opt.is_done("opt_long_way_home"), "two of three")
	GameState.set_flag("mm_balcony_shortcut")      # the manor module's own flag
	assert_true(Story.flag("ch2_shortcut_manor"), "mirrored by the tracker at once")
	opt.evaluate()
	assert_true(opt.is_done("opt_long_way_home"))
	assert_true(Story.flag("ch2_map_pins_upgraded"), "reward flag")
	assert_eq(opt.objective_status(g)[0]["progress"], 3)
	# From state alone (no event: an old save): sync repairs the mirror.
	GameState.flags.erase("ch2_shortcut_manor")
	assert_true(Story.sync_state(), "repaired")
	assert_true(Story.flag("ch2_shortcut_manor"))


func test_harvest_table_counts_different_dishes_and_a_table() -> void:
	var done := record(Events.optional_goal_completed, 1)
	Events.crafted.emit("pumpkin_soup", "pumpkin_soup", 1)
	Events.crafted.emit("pumpkin_soup", "pumpkin_soup", 1)
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 1, "the same dish twice counts once")
	Events.crafted.emit("candy", "candy", 3)
	Events.crafted.emit("wood_wall", "wood_wall", 1)
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 1, "candy / non-food do not count")
	Events.crafted.emit("roseberry_tart", "roseberry_tart", 1)
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 2)
	opt.evaluate()
	assert_false(opt.is_done("opt_harvest_table"), "no table yet")
	GameState.add_structure("table", Vector3(2, 0, 2), 0.0)
	Events.structure_placed.emit("s_test", "table")
	assert_true(Story.flag(Story.TABLE_FLAG))
	opt.evaluate()
	assert_true(opt.is_done("opt_harvest_table"))
	assert_true(Story.flag("ch2_harvest_table"), "the Lanternwake Table / candy recipes unlock")
	assert_eq(done, [["opt_harvest_table"]])
	# A crafting module that keeps its own count never lowers ours (max semantics) and vice versa.
	GameState.set_counter_max(Story.DISH_COUNTER, 1)
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 2)


func test_harvest_table_from_saved_state_and_round_trip() -> void:
	GameState.set_flag(Story.DISH_FLAG_PREFIX + "moonpetal_tea")
	GameState.set_flag(Story.DISH_FLAG_PREFIX + "lanternwake_platter")
	GameState.add_structure("lanternwake_table", Vector3(3, 0, 3), 0.0)
	# A save written without the tracker running (older build): load it with no tracker...
	tracker.queue_free()
	await wait_frames(1)
	_reload()
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 0, "nothing derived yet")
	assert_false(Story.flag(Story.TABLE_FLAG))
	# ... then the tracker starts (Game creates it once) and repairs everything from the saved state.
	tracker = Story.new_tracker()
	add_child(tracker)
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 2)
	assert_true(Story.flag(Story.TABLE_FLAG))
	GameState.reset()
	assert_true(SaveSystem.load_game(), "loaded again")
	assert_eq(GameState.get_counter(Story.DISH_COUNTER), 2, "a load with the tracker running (game_loaded) keeps it right")
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_harvest_table"))
	_reload()
	assert_true(GameState.optional_goals.is_done("opt_harvest_table"), "the latch is saved")
	assert_true(Story.flag(Story.DISH_FLAG_PREFIX + "moonpetal_tea"), "dish flags are saved")


func test_miner_who_came_back_from_lore_once() -> void:
	GameState.discover_lore("lore_ch2_tobin_note")
	assert_true(Story.flag("c1x_tobin_letter_found"), "Tobin's note (annex)")
	GameState.lore.append("lore_ch2_hask_note")      # found in a save made before the tracker existed
	assert_false(Story.flag("ch2_hask_note_found"))
	Story.sync_state()
	assert_true(Story.flag("ch2_hask_note_found"), "Hask's note (refuge), repaired from state")
	opt.evaluate()
	assert_true(opt.is_done("opt_miner_came_back"))
	assert_eq(_held("miner_lamp"), 1, "the miner's lamp")
	var ledger: Dictionary = GameState.ledger.duplicate()
	_reload()
	opt = GameState.optional_goals
	opt.records.erase("opt_miner_came_back")        # even a save that lost the latch pays nothing twice
	opt.evaluate()
	assert_eq(_held("miner_lamp"), 1, "once, ever")
	assert_deep_eq(GameState.ledger, json_norm(ledger))


func test_pumpkin_with_a_face_and_room_for_friends() -> void:
	Events.crop_harvested.emit("c1", "sweetroot", 2)
	assert_false(Story.flag(Story.PUMPKIN_FLAG), "only a pumpkin counts")
	Events.crop_harvested.emit("c1", "pumpkin", 1)
	assert_true(Story.flag(Story.PUMPKIN_FLAG))
	GameState.add_structure("pumpkin_lantern", Vector3(1, 0, 4), 0.0)
	GameState.companion("mochi")["home_spot"] = [2.0, 0.0, 5.0]
	GameState.add_structure("companion_bed", Vector3(2, 0, 5), 0.0)
	opt.evaluate()
	assert_true(opt.is_done("opt_pumpkin_face"))
	assert_true(Story.flag("ch2_pumpkin_face"), "Pumpkin Patch pattern unlock")
	assert_true(opt.is_done("opt_room_for_friends"))
	var n: int = opt.done_count()
	opt.evaluate()
	assert_eq(opt.done_count(), n, "nothing twice")


func test_return_to_the_reach_after_the_choir() -> void:
	var notes := record(Events.notify, 2)
	Events.area_loaded.emit("hallowmere_reach")
	assert_false(Story.flag(Story.RETURNED_FLAG), "not before the Choir")
	GameState.set_flag(Story.CHOIR_FLAG)
	Events.area_loaded.emit("surface")
	assert_false(Story.flag(Story.RETURNED_FLAG), "home is not the Reach")
	Events.area_loaded.emit("hallowmere_reach")
	assert_true(Story.flag(Story.RETURNED_FLAG), "arriving in the Reach")
	assert_true(GameState.lore.has(Story.LORE_ROUTES), "journal note")
	assert_true(notes.has([Story.ROUTES_NOTICE, "info"]))
	var shown := notes.size()
	Events.area_loaded.emit("hallowmere_reach")
	assert_eq(notes.size(), shown, "announced once")
	# The chapter log takes it from there (step 18 latches).
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_garden_lamp_lit", "ch2_quarry_lamp_lit",
			"ch2_manor_lamp_lit", "ch2_lamps_linked"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	assert_true(GameState.chapter2.is_done("ch2_routes_restored"))
	assert_true(Story.flag(Story.TRIALS_FLAG), "step 18 opens the optional trials")
	assert_eq(String(GameState.current_objective()["id"]), "ch2_homecoming")


func test_homecoming_at_the_ward_stone() -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag(Story.CHOIR_FLAG)
	var said := record(Events.say, 3)
	var hints := record(Events.hint, 2)
	var ws: Node3D = WardStone.new()
	add_child(ws)
	ws.forced_choice = "read"
	await ws.interact(null)
	assert_true(Story.flag(Story.HOMECOMING_FLAG), "ch2_homecoming")
	assert_eq(said.size(), 1, "one line only")
	assert_eq(String(said[0][1]), "Light kept. Roads found. Welcome home, Krystal.", "MP §17 return line")
	assert_true(GameState.lore.has(Story.LORE_HOMECOMING))
	assert_true(hints.has(["ch2_celebrate", Story.CELEBRATE_HINT]), "the Celebrate hint")
	assert_true(Story.can_celebrate())
	var ids: Array = (ws.menu_options() as Array).map(func(o: Array) -> String: return String(o[0]))
	assert_true(ids.has("celebrate"))
	ws.homecoming()     # a second call is a no-op
	assert_eq(said.size(), 1)
	ws.queue_free()


func test_lanternwake_unlocks_apply_inside_grant_once() -> void:
	var owned_before: Array = (GameState.wardrobe.get("owned", []) as Array).duplicate()
	assert_false(owned_before.has(Story.FEAST_PATTERN))
	var seen: Array = []
	# The tracker connected first, so by the time any later listener (Game's save) runs, it is done.
	listen(Events.reward_granted, func(rid: String) -> void:
		if rid == Story.FEAST_REWARD:
			seen.append((GameState.wardrobe.get("owned", []) as Array).has(Story.FEAST_PATTERN)))
	assert_true(GameState.grant_once(Story.FEAST_REWARD, {"candy": 6}, ["chapter_two_complete", "ch2_feast"]))
	assert_eq(seen, [true], "owned before anything else reacts to the grant")
	var pal: Array = GameState.wardrobe["palettes"]
	assert_true(pal.has("midnight") and pal.has("cream"), "gothic / cottage finishes")
	assert_false(Story.sync_feast_unlocks(), "idempotent")
	_reload()
	assert_eq((GameState.wardrobe["palettes"] as Array).count("midnight"), 1, "no duplicates after a reload")
	assert_true((GameState.wardrobe["owned"] as Array).has(Story.FEAST_PATTERN))


func test_title_card_on_acceptance() -> void:
	var ui := StubUi.new()
	add_child(ui)
	Game.ui = ui
	Events.choice_made.emit("ch2_lantern_road", "stay")
	assert_null(tracker.get("_card_timer"), "declining shows nothing")
	Events.choice_made.emit("ch2_lantern_road", "follow")
	assert_not_null(tracker.get("_card_timer"), "the card is scheduled after the reassurance line")
	tracker.call("_show_chapter_card")
	assert_eq(ui.cards, [["Chapter Two", "The Lanterns of Hallowmere"]])
	Game.ui = _ui_before
	ui.queue_free()


func test_debug_jump_to_the_closing_beats() -> void:
	if not Debug.is_cheat_allowed():
		assert_false(Story.debug_state("celebrate"), "never in release")
		return
	assert_false(Story.debug_state("nonsense"))
	assert_true(Story.debug_state("choir"))
	assert_true(Story.flag(Story.CHOIR_FLAG))
	assert_false(Story.flag(Story.RETURNED_FLAG), "stops at the Choir")
	assert_true(Story.debug_state("celebrate"))
	assert_true(Story.can_celebrate(), "the Ward Stone / Commons lantern now offer Celebrate")
	assert_false(Story.flag(Story.COMPLETE_FLAG), "the ending itself is never faked")
	GameState.chapter2.evaluate()
	assert_eq(String(GameState.current_objective()["id"]), "ch2_feast")


func test_step_reward_flags_repaired_for_older_saves() -> void:
	# Never from nothing: without the steps' ledger entries neither flag appears.
	Story.sync_state()
	assert_false(Story.flag(Story.SAFE_ROUTES_FLAG))
	assert_false(Story.flag(Story.TRIALS_FLAG))
	# A save that paid these steps before their on_complete flags existed: grant_once now refuses them, so the
	# ledger entry is the evidence the tracker repairs from on load.
	GameState.grant_once("rw_ch2_lamps_linked", {}, [])
	GameState.grant_once("rw_ch2_routes_restored", {}, [])
	assert_false(GameState.grant_once("rw_ch2_routes_restored", {}, [Story.TRIALS_FLAG]), "the ledger refuses a second payment")
	assert_false(Story.flag(Story.TRIALS_FLAG))
	_reload()
	assert_true(Story.flag(Story.SAFE_ROUTES_FLAG), "persistent safe-light routes repaired")
	assert_true(Story.flag(Story.TRIALS_FLAG), "optional trial access repaired")
