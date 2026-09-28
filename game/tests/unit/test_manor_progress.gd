extends "res://tests/test_case.gd"
## Moonveil Manor progress on the real area scene: rest candles set the manor respawn and save; the Count's
## encounter hook (missing boss -> candle fallback; a stand-in boss -> start/pause calls, first bow once;
## Events.boss_defeated / the debug hook -> ch2_velour_defeated first, balcony open, resident); the lantern
## sets ONLY ch2_manor_lamp_lit and the quest layer pays rw_ch2_manor exactly once; scraps are taken once
## and stay gone; "The Empty Waltz" runs once per save with Gentle / Intense variants and a light reveal;
## the balcony shortcut sets both of its flags once; everything survives a save / load round trip.

const Layout := preload("res://data/manor_layout.gd")
const SCENE := "res://scenes/moonveil_manor.tscn"
const ManorWorld := preload("res://src/world/areas_ch2/moonveil_manor_world.gd")

var _area: Node3D = null
var _said: Array = []
var _probe: Node3D = null
var _saved_intensity: Variant = null


class FakeBoss extends Node3D:
	var calls: Array = []
	func start_fight() -> void:
		calls.append("start_fight")
	func reset_fight() -> void:
		calls.append("reset_fight")


func before_each() -> void:
	fresh_state()
	GameState.active = true
	GameState.give_item("lantern", 1)
	_said.clear()
	if not Events.say.is_connected(_on_say):
		Events.say.connect(_on_say)
	_saved_intensity = Settings.get_value("horror_intensity")


func after_each() -> void:
	Settings.set_value("horror_intensity", _saved_intensity)
	if Events.say.is_connected(_on_say):
		Events.say.disconnect(_on_say)
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
	_probe = null
	GameState.active = false
	await wait_frames(3)


func _on_say(speaker: String, text: String, _d: float) -> void:
	_said.append([speaker, text])


func _load() -> Node3D:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
		await wait_frames(2)
	var ps: PackedScene = load(SCENE)
	_area = ps.instantiate()
	add_child(_area)
	await wait_physics(2)
	return _area


## A stand-in for Krystal the area / moment controllers can read (never in group "player").
func _stand(at: Vector3) -> Node3D:
	if _probe == null or not is_instance_valid(_probe):
		_probe = Node3D.new()
		_probe.name = "ProbeKrystal"
		add_child(_probe)
	_probe.global_position = at
	return _probe


func _texts() -> Array:
	return _said.map(func(s: Array) -> String: return String(s[1]))


# --- Checkpoints ---------------------------------------------------------------------------------------------

func test_rest_candles_set_the_manor_respawn_and_save() -> void:
	await _load()
	var cps: Dictionary = _area.get("checkpoints")
	assert_eq(cps.keys().size(), 2, "two rest points")
	var ball: Node3D = cps["manor_ballroom"]
	assert_true(ball.is_in_group("checkpoint") and ball.is_in_group("interactable"))
	assert_eq(String(ball.get_interaction(null)["text"]), "Rest by the candles (save)")
	ball.interact(null)
	assert_eq(String(GameState.player.get("respawn_area", "")), "moonveil_manor", "respawn area")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "manor_ballroom", "respawn spawn")
	assert_eq(Game.area_respawn_of("moonveil_manor"), "manor_ballroom", "per-area respawn memory")
	assert_eq(String(GameState.player.get("spawn", "")), "manor_ballroom", "Continue resumes here")
	assert_true(bool(GameState.get_flag("mm_cp_manor_ballroom")), "candles lit for good")
	var saved: Dictionary = SaveSystem._read_and_validate(SaveSystem._path())
	assert_eq(String(saved.get("state", {}).get("player", {}).get("spawn", "")), "manor_ballroom", "saved at the rest point")
	var bal: Node3D = cps["manor_balcony"]
	bal.set("save_enabled", false)
	bal.interact(null)
	assert_eq(Game.area_respawn_of("moonveil_manor"), "manor_balcony", "the balcony takes over")
	assert_true(_area.is_safe_zone((bal as Node3D).global_position), "rest points stand in safe ground")


# --- The Count ---------------------------------------------------------------------------------------------------

func test_missing_boss_fallback_and_debug_hook_never_softlock() -> void:
	await _load()
	if not bool(_area.get("boss_missing")):
		# A later wave registered the Count: simulate his script failing after the spawn (node gone, no
		# defeat) so this path stays covered instead of silently passing.
		var b: Node = _area.get("boss")
		if b != null and is_instance_valid(b):
			b.free()
	_area.set("player_override", _stand(Vector3(0, 0, -60)))
	_area.call("update_encounter")
	assert_true(bool(_area.get("boss_missing")), "no Count to fight")
	assert_false(bool(_area.get("fight_active")), "no fight without a boss")
	assert_true(_texts().any(func(t: String) -> bool: return t.contains("ward candles")), "the fallback is explained")
	_area.call("update_encounter")
	assert_eq(_texts().filter(func(t: String) -> bool: return t.contains("ward candles")).size(), 1, "explained once")
	var cands: Array = _area.get("arena_candles")
	for wc in cands:
		assert_false(bool(wc.call("is_lit")), "fallback: every ward candle waits dark")
	cands[0].interact(null)
	cands[1].interact(null)
	assert_false(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)), "two candles are not enough")
	cands[2].interact(null)
	assert_true(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)), "all three break the enchantment")
	await wait_physics(2)
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "balcony doors open")
	await wait_seconds(ManorWorld.RESIDENT_DELAY + 0.3)          # a live win: he appears after the dispersal beat
	assert_not_null(_area.get("resident"), "the Count is a resident now")
	# The debug hook (debug builds only) is idempotent.
	assert_false(bool(_area.call("debug_mark_velour_defeated")), "already cleared")


func test_boss_hook_start_pause_and_defeat_event() -> void:
	await _load()
	var fake := FakeBoss.new()
	_area.add_child(fake)
	_area.set("boss", fake)
	_area.set("boss_missing", false)
	# The Count is present: two ward candles burn, the teaching candle waits dark (MP §13.1).
	var teach: Node3D = _area.get("teach_candle")
	assert_not_null(teach, "a teaching candle")
	assert_eq(String(teach.get("candle_id")), String(Layout.ARENA["teach_candle"]))
	for wc in _area.get("arena_candles"):
		wc.call("restore", wc != teach)
	var hints: Array = []
	var on_hint := func(id: String, _t: String) -> void: hints.append(id)
	Events.hint.connect(on_hint)
	_area.set("player_override", _stand(Vector3(0, 0, -52.6)))
	_area.call("update_encounter")
	assert_false(bool(_area.get("fight_active")), "the doorway itself does not start it")
	_stand(Vector3(0, 0, -60))
	_area.call("update_encounter")
	assert_false(bool(_area.get("fight_active")), "not before the teaching candle is lit")
	assert_eq(fake.calls, [], "the Count waits")
	assert_eq(hints, ["mm_ward_candle"], "a hint teaches the candle (no audio-only cue)")
	_area.call("update_encounter")
	assert_eq(hints.size(), 1, "taught once")
	Events.hint.disconnect(on_hint)
	assert_true(bool(teach.get_interaction(null)["enabled"]), "lightable with the ordinary Lantern")
	teach.interact(null)
	assert_true(bool(_area.get("fight_active")), "lighting it in the arena starts the encounter")
	assert_eq(fake.calls, ["start_fight"])
	assert_true(_said.any(func(s: Array) -> bool: return String(s[0]) == Layout.VELOUR_NAME and String(s[1]) == Layout.VELOUR_FIRST_BOW), "first bow, MP §17 verbatim")
	assert_false(bool((_area.get("tapestry") as Node).call("is_open")), "the dressing-room tapestry holds during the fight")
	# The Count darkens a candle, then Krystal leaves: the pause relights every candle for a fair restart.
	(_area.get("arena_candles") as Array)[0].call("darken", fake)
	_stand(Vector3(0, 0, -41))
	_area.call("update_encounter")
	assert_false(bool(_area.get("fight_active")), "leaving the Gallery pauses it")
	assert_eq(fake.calls, ["start_fight", "reset_fight"])
	for wc in _area.get("arena_candles"):
		assert_true(bool(wc.call("is_lit")), "every ward candle burns again after a pause")
	_stand(Vector3(0, 0, -60))
	_area.call("update_encounter")
	assert_true(bool(_area.get("fight_active")), "coming back resumes at once (she already knows the candles)")
	assert_eq(_said.filter(func(s: Array) -> bool: return String(s[1]) == Layout.VELOUR_FIRST_BOW).size(), 1, "the bow is said once per visit")
	assert_eq(int(_area.get("encounter_starts")), 2)
	# Dying pauses it too.
	Events.player_died.emit()
	assert_false(bool(_area.get("fight_active")), "a defeat pauses the encounter")
	_area.call("update_encounter")
	assert_true(bool(_area.get("fight_active")), "and it resumes when she stands in the arena again")
	# Victory arrives through Events.boss_defeated with the data id.
	assert_null(_area.get("resident"), "no resident before the defeat")
	Events.boss_defeated.emit("weaver_matron")
	assert_false(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)), "another boss id changes nothing")
	Events.boss_defeated.emit("count_velour")
	assert_true(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)), "ch2_velour_defeated")
	assert_false(bool(_area.get("fight_active")), "encounter over")
	assert_null(_area.get("resident"), "not while his enchantment disperses")
	await wait_seconds(ManorWorld.RESIDENT_DELAY + 0.3)
	var res: Node3D = _area.get("resident")
	assert_not_null(res, "the resident appears")
	assert_false(res.is_in_group("enemy"), "never hostile")
	assert_true(bool((_area.get("tapestry") as Node).call("is_open")), "tapestry open again")
	for wc in _area.get("arena_candles"):
		assert_true(bool(wc.call("is_lit")), "the Gallery's candles burn calmly")
	# Resident lines: MP §17 first, no branching, cycling.
	var first := String(res.call("say_next"))
	assert_eq(first, Layout.VELOUR_AFTER)
	assert_eq(first, "A dreadful host. I did not even offer you a chair.")
	for i in Layout.RESIDENT_LINES.size() - 1:
		res.call("say_next")
	assert_eq(String(res.call("say_next")), Layout.VELOUR_AFTER, "lines wrap around")
	assert_eq(String(res.get_interaction(null)["text"]), "Talk to Count Velour")
	fake.queue_free()


## A spawned Count whose node vanishes without a defeat (a later-wave script freeing itself) must not lock the
## Gallery: the next time Krystal stands in the arena the three-candle fallback takes over. A defeat flag
## committed by someone else (a boss using enemy_base "defeat_flag") still opens the house without a reload.
func test_a_vanished_count_falls_back_and_a_foreign_defeat_flag_opens_the_house() -> void:
	await _load()
	var fake := FakeBoss.new()
	_area.add_child(fake)
	_area.set("boss", fake)
	_area.set("boss_missing", false)
	var teach: Node3D = _area.get("teach_candle")
	for wc in _area.get("arena_candles"):
		wc.call("restore", wc != teach)
	fake.free()
	_area.set("player_override", _stand(Vector3(0, 0, -60)))
	_area.call("update_encounter")
	assert_false(bool(_area.get("fight_active")), "no fight with a vanished Count")
	assert_true(bool(_area.get("boss_missing")), "the candle fallback takes over")
	for wc in _area.get("arena_candles"):
		assert_false(bool(wc.call("is_lit")), "all three ward candles wait dark")
	assert_true(_texts().any(func(t: String) -> bool: return t.contains("ward candles")), "and the house says so")
	for wc in _area.get("arena_candles"):
		wc.interact(null)
	assert_true(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)), "lighting them breaks the enchantment")
	await wait_physics(2)
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "the balcony opens")
	# A defeat flag set elsewhere (not through Events.boss_defeated): picked up on the next encounter tick.
	fresh_state()
	GameState.active = true
	GameState.give_item("lantern", 1)
	await _load()
	assert_null(_area.get("resident"), "fresh save: no resident")
	GameState.set_flag(Layout.FLAG_VELOUR_DEFEATED, true)
	_area.call("update_encounter")
	await wait_physics(2)
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "balcony open without a reload")
	await wait_seconds(ManorWorld.RESIDENT_DELAY + 0.3)
	assert_not_null(_area.get("resident"), "the resident appears")
	assert_false(bool(_area.get("fight_active")))
	for wc in _area.get("arena_candles"):
		assert_true(bool(wc.call("is_lit")), "the Gallery's candles burn calmly")


func test_resident_only_appears_after_the_defeat() -> void:
	await _load()
	assert_null(_area.get("resident"), "no resident in a fresh save")
	assert_eq(_area.find_children("CountVelourResident", "", true, false).size(), 0)
	GameState.set_flag(Layout.FLAG_VELOUR_DEFEATED, true)
	await _load()
	assert_not_null(_area.get("resident"), "resident on load after the defeat")
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "balcony open on load")
	assert_null(_area.get("boss"), "the boss is never spawned again")
	assert_false(bool(_area.call("mark_velour_defeated", "boss")), "defeat is committed once")


# --- The lantern -----------------------------------------------------------------------------------------------

func test_lantern_sets_only_its_flag_once_and_the_quest_layer_pays_once() -> void:
	for f in ["chapter_one_complete", "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map",
			"ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp"]:
		GameState.set_flag(f, true)
	GameState.chapter2.evaluate()
	await _load()
	var lamp: Node3D = _area.get("lantern")
	var info: Dictionary = lamp.get_interaction(null)
	assert_false(bool(info["enabled"]), "cold before the Count is freed")
	assert_true(String(info.get("reason", "")).contains("Gallery"), "and says where to look")
	assert_false(bool(lamp.call("wake")), "cannot be woken early")
	_area.call("debug_mark_velour_defeated")
	assert_true(bool(lamp.get_interaction(null)["enabled"]), "ready after the defeat")
	var hv_before: Variant = Settings.get_value("high_visibility_cues")
	Settings.set_value("high_visibility_cues", true)
	assert_true(bool(lamp.call("beckon_visible")), "high_visibility_cues: a bold ring while it waits")
	var ledger_before: Dictionary = GameState.ledger.duplicate()
	lamp.interact(null)
	assert_false(bool(lamp.call("beckon_visible")), "gone once lit")
	Settings.set_value("high_visibility_cues", hv_before)
	assert_true(bool(GameState.get_flag(Layout.FLAG_LAMP_LIT)), "ch2_manor_lamp_lit")
	assert_eq(GameState.ledger, ledger_before, "the manor itself grants nothing")
	assert_eq(GameState.count_item("manor_seal"), 0, "no seal from the manor module")
	GameState.chapter2.evaluate()
	assert_true(GameState.has_reward("rw_ch2_manor"), "the quest layer pays rw_ch2_manor")
	assert_eq(GameState.count_item("manor_seal"), 1, "one Manor Seal")
	assert_true(bool(GameState.get_flag("ch2_manor_restored")), "tailoring patterns unlocked by the quest layer")
	assert_false(bool(lamp.call("wake")), "waking twice does nothing")
	assert_eq(int(lamp.get("wakes")), 1)
	GameState.chapter2.evaluate()
	GameState.chapter2.evaluate()
	assert_eq(GameState.count_item("manor_seal"), 1, "still one seal")
	await _load()
	assert_true(bool((_area.get("lantern") as Node).call("is_lit")), "lit again on load")
	assert_false(bool((_area.get("lantern") as Node).get_interaction(null)["enabled"]), "and stays lit")


# --- Count's Wardrobe -------------------------------------------------------------------------------------------

func test_scraps_are_taken_once_and_stay_gone() -> void:
	GameState.set_flag("ch2_accepted", true)
	await _load()
	var scraps: Dictionary = _area.get("scraps")
	assert_eq(scraps.keys().size(), 3, "three scraps placed")
	for s in Layout.SCRAPS:
		var zone := String(_area.get_zone_at(s["pos"]))
		assert_true(["mm_hall", "mm_ballroom", "mm_gallery"].has(zone), "%s in an optional side room of %s" % [s["id"], zone])
		assert_true(Layout.ROOMS[String(s["room"])].get("side_room", false), "%s room is a side room" % s["id"])
	var one: Node3D = scraps["mm_scrap_1"]
	assert_eq(String(one.get_interaction(null)["text"]), "Pick up the velvet scrap")
	one.interact(null)
	assert_eq(GameState.count_item("velvet_scrap"), 1, "one scrap in the pouch")
	assert_true(bool(GameState.get_flag("ch2_velvet_scrap_1")))
	assert_false(bool(one.call("collect")), "a second pick-up does nothing")
	assert_eq(GameState.count_item("velvet_scrap"), 1, "still one")
	await _load()
	var again: Dictionary = _area.get("scraps")
	assert_false(again.has("mm_scrap_1"), "gone after reloading the area")
	assert_eq(_area.find_children("VelvetScrap_mm_scrap_1", "", true, false).size(), 0)
	again["mm_scrap_2"].interact(null)
	again["mm_scrap_3"].interact(null)
	assert_eq(GameState.count_item("velvet_scrap"), 3)
	GameState.optional_goals.evaluate()
	assert_true(bool(GameState.optional_goals.call("is_done", "opt_counts_wardrobe")), "The Count's Wardrobe completes (optional log)")
	assert_true(bool(GameState.get_flag("ch2_count_wardrobe")), "cape pattern unlock paid by the optional log")


# --- The Empty Waltz ------------------------------------------------------------------------------------------------

func _waltz_at_intensity(level: int) -> Node3D:
	Settings.set_value("horror_intensity", level)
	await _load()
	var w: Node3D = _area.get("waltz")
	w.set("player_override", _stand(Vector3(0, 0, -41)))
	return w


func test_empty_waltz_runs_once_per_save() -> void:
	var w: Node3D = await _waltz_at_intensity(1)
	var events: Array = []
	var on_event := func(id: String, data: Dictionary) -> void: events.append([id, String(w.get("state")), data.get("pos")])
	Events.horror_event.connect(on_event)
	w.call("check", 0.1)
	assert_eq(String(w.get("state")), "playing", "the music box plays while Krystal is in the ballroom")
	w.call("check", 10.0)
	assert_eq(String(w.get("state")), "playing")
	assert_eq(events, [], "no silence while the waltz plays")
	w.call("check", 13.0)
	assert_eq(String(w.get("state")), "stopped", "the waltz winds down")
	assert_false(bool(GameState.get_flag(Layout.FLAG_WALTZ)), "not committed before the movement")
	# The waltz music really stops: the music director is asked for an authored silence at the stop,
	# BEFORE any cloak moves (areas never call play_music / stop_music).
	assert_eq(events.size(), 1, "one authored-silence request")
	if events.size() == 1:
		assert_eq(String(events[0][0]), "authored:empty_waltz")
		assert_eq(String(events[0][1]), "stopped", "sent when the waltz stops")
		assert_true(events[0][2] is Vector3 and Layout.room_at(events[0][2]) == "ballroom", "points at the cloaks (a following Mochi glances there)")
	assert_true(float(w.call("timing")["delay"]) >= 4.0, "the cloaks wait for the music director's 4 s fade")
	w.call("check", 3.1)
	assert_eq(String(w.get("state")), "stopped", "the waltz is still fading")
	w.call("check", 1.5)
	assert_eq(String(w.get("state")), "turning", "then one pair turns")
	Events.horror_event.disconnect(on_event)
	assert_eq(events.size(), 1, "the turn itself asks nothing more of the music")
	assert_true(bool(GameState.get_flag(Layout.FLAG_WALTZ)), "ch2_moment_empty_waltz set first")
	w.call("check", 5.0)
	assert_eq(String(w.get("state")), "done")
	assert_almost(float(w.call("pair_yaw")), deg_to_rad(150.0), 0.01, "the pair ends in its bow")
	# Harmless: nothing entered the enemy group, the player's health was never touched.
	assert_eq(_area.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.is_in_group("enemy")).size(), 0, "no enemy involved")
	# Once per save: a reload shows the finished pose and never replays.
	await _load()
	var w2: Node3D = _area.get("waltz")
	assert_eq(String(w2.get("state")), "done", "done on reload")
	w2.set("player_override", _stand(Vector3(0, 0, -41)))
	w2.call("check", 60.0)
	assert_eq(String(w2.get("state")), "done", "never replays")


func test_empty_waltz_intensity_variants_and_music_cue() -> void:
	var g: Node3D = await _waltz_at_intensity(0)
	g.call("check", 0.1)
	assert_eq(int(g.get("intensity")), 0)
	assert_true(float(g.call("timing")["preview"]) > float(Layout.WALTZ["timing"][1]["preview"]), "Gentle: longer preview")
	g.call("check", 100.0)
	g.call("check", 4.1)
	assert_eq(String(g.get("state")), "turning")
	assert_true(_texts().any(func(t: String) -> bool: return t.contains("Only the cloaks")), "Gentle: explicit hint line")
	fresh_state()
	GameState.active = true
	var i: Node3D = await _waltz_at_intensity(2)
	i.call("check", 0.1)
	assert_eq(float(i.call("timing")["preview"]), 0.0, "Intense: no preview")
	assert_true(float(i.call("timing")["delay"]) > float(Layout.WALTZ["timing"][1]["delay"]), "Intense: delayed final movement")
	# The waltz cue ending stops the music box early (once she has been here a little while).
	Events.music_cue_changed.emit("m20")
	Events.music_cue_changed.emit("")
	i.call("check", 3.0)
	assert_eq(String(i.get("state")), "playing", "not before min_seconds")
	i.call("check", 3.5)
	assert_eq(String(i.get("state")), "stopped", "the cue ended -> the waltz stops")
	i.call("check", 5.0)
	assert_eq(String(i.get("state")), "stopped", "Intense still waits")
	i.call("check", 3.1)
	assert_eq(String(i.get("state")), "turning")


func test_empty_waltz_only_counts_time_in_the_ballroom_and_light_reveals_the_wires() -> void:
	var w: Node3D = await _waltz_at_intensity(1)
	w.set("player_override", _stand(Vector3(0, 0, -20)))
	w.call("check", 100.0)
	assert_eq(String(w.get("state")), "idle", "nothing happens outside the ballroom")
	w.set("player_override", _stand(Vector3(0, 0, -41)))
	w.call("check", 30.0)
	w.call("check", 30.0)
	w.call("check", 10.0)
	w.call("check", 5.0)
	assert_eq(String(w.get("state")), "done")
	assert_false(bool(w.call("wires_shown")), "wires hidden in the dark")
	var rail: Node3D = w.get("rail_candle")
	rail.interact(null)
	w.call("check", 0.1)
	assert_true(bool(w.call("wires_shown")), "candle-light shows the supports")
	assert_true(bool(GameState.get_flag(Layout.FLAG_WALTZ_REVEALED)), "revealed once")
	assert_true(GameState.lore.has("lore_ch2_manor_dancing_rail"), "the rail note is in the journal")
	var n := _texts().filter(func(t: String) -> bool: return t.contains("mechanical dance")).size()
	w.call("check", 0.1)
	assert_eq(_texts().filter(func(t: String) -> bool: return t.contains("mechanical dance")).size(), n, "explained once")


# --- Looking-Glass Hall, shortcut, found flag, save / load ------------------------------------------------------------

func test_looking_glass_lesson() -> void:
	await _load()
	var lg: Node3D = _area.get("looking_glass")
	assert_false(bool(lg.call("collar_visible")), "the collar shows only in true light")
	(lg.get("practice_candle") as Node).interact(null)
	assert_true(bool(lg.call("is_revealed")))
	assert_true(bool(lg.call("collar_visible")), "the true bat's golden collar appears in the glass")
	assert_true(bool(GameState.get_flag(Layout.FLAG_MIRROR_CLUE)))
	assert_true(GameState.lore.has("lore_ch2_manor_looking_glass"), "the rule is in the journal")
	var collar: Node3D = lg.get_node("CollarGlint")
	assert_true(collar.global_position.x < Layout.MIRROR_X, "the glint is behind the glass (a reflection)")
	await _load()
	assert_true(bool((_area.get("looking_glass") as Node).call("collar_visible")), "stays revealed on load")


func test_balcony_shortcut_opens_once_with_both_flags() -> void:
	await _load()
	var ex: Dictionary = _area.get("exits")
	assert_false(bool(ex["servants_up"].get_interaction(null)["enabled"]), "bolted from the other side")
	assert_false(bool(ex["balcony_stair"].call("is_unlocked")))
	var gate: Node3D = _area.get("shortcut_gate")
	assert_true(bool(gate.call("open_gate")), "unbolted")
	assert_true(bool(GameState.get_flag(Layout.FLAG_SHORTCUT)), "mm_balcony_shortcut")
	assert_true(bool(GameState.get_flag(Layout.FLAG_SHORTCUT_GOAL)), "ch2_shortcut_manor (The Long Way Home)")
	assert_false(bool(gate.call("open_gate")), "once")
	assert_eq(gate.get_interaction(null), {}, "no prompt once open")
	assert_true(bool(ex["servants_up"].get_interaction(null)["enabled"]), "the servants' stair works from the Cloakroom")
	assert_eq(ex["servants_up"].call("destination"), {"area": "moonveil_manor", "spawn": "manor_balcony"})
	assert_eq(ex["servants_down"].call("destination"), {"area": "moonveil_manor", "spawn": "manor_entry"})
	assert_eq(ex["balcony_stair"].call("destination"), {"area": "hallowmere_reach", "spawn": "manor_door"}, "garden stair -> outside the door")
	assert_eq(ex["front_door"].call("destination"), {"area": "hallowmere_reach", "spawn": "manor_door"})


## The house is quiet, the balcony hears the night; zone changes of other areas are ignored.
func test_zone_ambience_quiet_house_and_night_balcony() -> void:
	await _load()
	for z in Layout.ZONE_ORDER:
		assert_true(Layout.AMBIENCE.has(z), "ambience decided for %s" % z)
		var amb := String(Layout.AMBIENCE[z])
		if amb != "":
			assert_true(Audio.has_sound(amb), "%s uses an existing loop (%s)" % [z, amb])
	assert_eq(String(Layout.AMBIENCE["mm_balcony"]), "amb_forest_night", "night air on the balcony")
	for z in ["mm_cloakroom", "mm_hall", "mm_ballroom", "mm_gallery"]:
		assert_eq(String(Layout.AMBIENCE[z]), "", "%s: no forest indoors" % z)
	_area.call("apply_zone_ambience", "mm_balcony")
	assert_eq(String(_area.get("ambience_zone")), "mm_balcony")
	if Audio.has_sound("amb_forest_night"):
		assert_eq(Audio.current_ambience(), "amb_forest_night", "balcony: the night outside")
	_area.call("apply_zone_ambience", "mm_hall")
	assert_eq(Audio.current_ambience(), "", "indoors: the ambience fades out")
	_area.call("apply_zone_ambience", "hr_commons")
	assert_eq(String(_area.get("ambience_zone")), "mm_hall", "foreign zones are ignored")
	_area.call("on_player_spawned", _stand(Vector3(0, 1.8, -90)))
	assert_eq(String(_area.get("ambience_zone")), "mm_balcony", "spawning on the balcony applies its ambience")
	Audio.stop_ambience(0.0)


## Spec §1: Velour's echo trial is entered from the ballroom rest candles - only after he is freed, and only
## once src/world/areas_ch2/echo_trial.gd offers a "velour" trial (a later wave). Never before.
func test_echo_trial_hook_waits_for_the_trial_module() -> void:
	await _load()
	assert_false(bool(_area.call("echo_trial_available")), "never before the Count is freed")
	assert_eq(_area.find_children("EchoTrialEntry", "", true, false).size(), 0)
	_area.call("debug_mark_velour_defeated")
	var s: Script = load("res://src/world/areas_ch2/echo_trial.gd")
	var offered := s != null and not (s.call("trial_info", Layout.ECHO_TRIAL_ID) as Dictionary).is_empty()
	assert_eq(bool(_area.call("echo_trial_available")), offered, "available exactly when the trial module offers it")
	var entry: Node = _area.get("echo_entry")
	assert_eq(entry != null, offered, "the echo stone appears only with the trial")
	if entry != null:
		assert_true(_area.is_safe_zone((entry as Node3D).global_position), "beside the ballroom rest candles (safe)")
		assert_true(bool(entry.get_interaction(null)["enabled"]))


func test_entering_the_manor_counts_as_finding_the_lamp() -> void:
	await _load()
	assert_false(bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)))
	_area.call("on_player_spawned", _stand(Vector3(0, 0, -3)))
	assert_true(bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)), "safety net for ch2_found_manor_lamp")


func test_manor_state_survives_save_and_load() -> void:
	await _load()
	(_area.get("puzzle") as Node).call("light_source", null)
	(_area.get("puzzle") as Node).call("turn", "c3")
	(_area.get("puzzle") as Node).call("turn", "c4")
	(_area.get("scraps") as Dictionary)["mm_scrap_2"].interact(null)
	_area.call("debug_mark_velour_defeated")
	(_area.get("lantern") as Node).call("wake")
	(_area.get("shortcut_gate") as Node).call("open_gate")
	((_area.get("looking_glass") as Node).get("practice_candle") as Node).interact(null)
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_false(bool(GameState.get_flag(Layout.FLAG_BALLROOM_SOLVED)), "state really cleared")
	assert_true(SaveSystem.load_game(), "loaded")
	GameState.active = true
	for f in [Layout.FLAG_BALLROOM_SOLVED, Layout.FLAG_VELOUR_DEFEATED, Layout.FLAG_LAMP_LIT, Layout.FLAG_SHORTCUT,
			Layout.FLAG_SHORTCUT_GOAL, "ch2_velvet_scrap_2", Layout.FLAG_MIRROR_CLUE]:
		assert_true(bool(GameState.get_flag(f)), "%s survives" % f)
	assert_eq(GameState.count_item("velvet_scrap"), 1, "the scrap survives in the pouch")
	await _load()
	assert_true(bool((_area.get("gallery_door") as Node).call("is_open")), "Gallery doors open")
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "Balcony doors open")
	assert_true(bool((_area.get("puzzle") as Node).call("is_solved")), "puzzle solved")
	assert_true(bool((_area.get("lantern") as Node).call("is_lit")), "lantern lit")
	assert_true(bool((_area.get("shortcut_gate") as Node).call("is_open")), "gate open")
	assert_not_null(_area.get("resident"), "resident present")
	assert_false((_area.get("scraps") as Dictionary).has("mm_scrap_2"), "scrap 2 stays gone")
	assert_true((_area.get("scraps") as Dictionary).has("mm_scrap_1"), "scrap 1 still waits")
