extends "res://tests/test_case.gd"
## Count Velour inside the real Moonveil Manor scene (module C6a with the manor area's hook): the area spawns him
## (registered in the enemy factory) with its three ward candles, curtains, cover and helper points; he waits
## until the TEACHING candle is lit with Krystal in the Gallery (never on proximity alone); leaving pauses him
## cleanly (the area relights the candles); victory commits ch2_velour_defeated inside the boss_defeated event,
## BEFORE any presentation or dialogue, exactly once; the freed resident says the MP 17 line once (the boss does
## not repeat it); a won save never spawns him again.
## Headless; the scene is loaded like the manor tests do; the boss is ticked by hand.

const Layout := preload("res://data/manor_layout.gd")
const SCENE := "res://scenes/moonveil_manor.tscn"
const DT := 0.05

var _area: Node3D = null
var _probe: Node3D = null
var _said: Array = []
var _log: Array = []


var _saved_assist: Variant = false        # Settings "timing_assist" pinned off (exact timings below), restored after


func before_each() -> void:
	fresh_state()
	_saved_assist = Settings.get_value("timing_assist")
	Settings.set_value("timing_assist", false)
	GameState.active = true
	GameState.give_item("lantern", 1)
	_said.clear()
	_log.clear()
	Events.say.connect(_on_say)
	Events.boss_defeated.connect(_on_defeated)
	Events.boss_encounter_changed.connect(_on_encounter)


func after_each() -> void:
	Settings.set_value("timing_assist", _saved_assist)
	Events.say.disconnect(_on_say)
	Events.boss_defeated.disconnect(_on_defeated)
	Events.boss_encounter_changed.disconnect(_on_encounter)
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
	_log.append(["say", text, bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED))])


func _on_defeated(id: String) -> void:
	# Connected after the area (loaded first): the area's listener has already run inside this same emit.
	_log.append(["defeated", id, bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED))])


func _on_encounter(id: String, active: bool) -> void:
	_log.append(["encounter", id, active])


func _load() -> Node3D:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
		await wait_frames(2)
	var ps: PackedScene = load(SCENE)
	_area = ps.instantiate()
	add_child(_area)
	await wait_physics(2)
	return _area


func _stand(at: Vector3) -> Node3D:
	if _probe == null or not is_instance_valid(_probe):
		_probe = Node3D.new()
		_probe.name = "ProbeKrystal"
		add_child(_probe)
	_probe.global_position = at
	return _probe


func _tick(b: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		b.tick(DT)
		t += DT


func _tick_until(b: Node, s: String, max_t: float = 15.0) -> void:
	var t := 0.0
	while String(b.state) != s and t < max_t:
		b.tick(DT)
		t += DT


func test_the_area_spawns_him_and_the_teaching_candle_starts_him() -> void:
	await _load()
	var b: Node3D = _area.get("boss")
	assert_not_null(b, "the manor spawns the Count")
	assert_false(bool(_area.get("boss_missing")))
	assert_eq(String(b.name), "CountVelour")
	b.set_process(false)
	assert_eq((b.get("candles") as Array).size(), 3, "the three ward candles")
	assert_eq((b.get("helper_points") as Array).size(), 2)
	assert_eq((b.get("cover") as Array).size(), 4)
	assert_false(bool(b.get("auto_start")), "the arena starts him")
	assert_false(bool(b.get("say_after_line")), "the resident owns the after-line")
	var p := _stand(Vector3(0, 0, -60))
	b.set("target_override", p)
	_area.set("player_override", p)
	_tick(b, 2.0)
	_area.call("update_encounter")
	assert_false(bool(b.get("fight_started")), "not before the teaching candle")
	assert_eq(String(b.state), "dormant")
	var teach: Node3D = _area.get("teach_candle")
	assert_false(bool(teach.call("is_lit")))
	teach.interact(null)
	assert_true(bool(b.get("fight_started")), "lighting it starts him")
	assert_true(_log.any(func(e: Array) -> bool: return String(e[0]) == "encounter" and String(e[1]) == "count_velour" and bool(e[2])))
	assert_true(bool(Game.boss_active()), "saving / travel gate sees the encounter")
	# Leaving the Gallery pauses him cleanly and relights every candle.
	_tick(b, 4.0)
	(_area.get("arena_candles") as Array)[0].call("darken", null)
	_stand(Vector3(0, 0, -41))
	_area.call("update_encounter")
	assert_false(bool(b.get("fight_started")))
	assert_eq(String(b.state), "dormant")
	for wc in _area.get("arena_candles"):
		assert_true(bool(wc.call("is_lit")), "candles lit again")
	assert_true(_log.any(func(e: Array) -> bool: return String(e[0]) == "encounter" and String(e[1]) == "count_velour" and not bool(e[2])),
		"encounter over (music released, saving allowed again)")


func test_victory_commits_before_presentation_once_and_the_resident_speaks() -> void:
	await _load()
	# Listen AFTER the area (connection order = call order), like any presentation / dialogue consumer would.
	Events.boss_defeated.disconnect(_on_defeated)
	Events.boss_defeated.connect(_on_defeated)
	var b: Node3D = _area.get("boss")
	b.set_process(false)
	b.set("fast_defeat", false)
	var p := _stand(Vector3(0, 0, -60))
	b.set("target_override", p)
	_area.set("player_override", p)
	(_area.get("teach_candle") as Node3D).interact(null)
	assert_true(bool(b.get("fight_started")))
	_tick_until(b, "glide")
	b.call("jump_to_phase", 3)
	var wc: Node3D = (_area.get("arena_candles") as Array)[0]
	wc.call("darken", null)
	wc.call("light", p)
	assert_eq(String(b.state), "stagger", "relighting staggers him")
	_tick(b, 1.0)
	b.get("health").apply_damage(9999.0, p, Vector3.FORWARD)
	var defs: Array = _log.filter(func(e: Array) -> bool: return String(e[0]) == "defeated")
	assert_eq(defs.size(), 1, "boss_defeated once")
	assert_true(bool(defs[0][2]), "ch2_velour_defeated is committed inside the event (before any presentation)")
	assert_true(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)))
	assert_eq(String(b.state), "defeat", "the presentation plays after the commit")
	assert_false(b.is_in_group("enemy"), "no longer a target while the enchantment disperses")
	assert_false(bool(_area.get("fight_active")))
	assert_not_null(_area.get("resident"), "the freed Count appears")
	assert_true(bool((_area.get("balcony_door") as Node).call("is_open")), "the way on opens")
	var early: Array = _log.filter(func(e: Array) -> bool: return String(e[0]) == "say" and String(e[1]) == Layout.VELOUR_AFTER)
	assert_eq(early.size(), 0, "no dialogue before the presentation")
	await wait_seconds(1.8)
	assert_eq(String(b.state), "gone", "the enchantment dispersed")
	var lines: Array = _log.filter(func(e: Array) -> bool: return String(e[0]) == "say" and String(e[1]) == Layout.VELOUR_AFTER)
	assert_eq(lines.size(), 1, "\"A dreadful host...\" said once (by the resident, not repeated by the boss)")
	assert_true(bool(lines[0][2]), "said after the commit")
	assert_eq(Layout.VELOUR_AFTER, "A dreadful host. I did not even offer you a chair.")
	# Nothing can repeat the victory.
	Events.player_died.emit()
	b.call("start_fight")
	assert_eq(_log.filter(func(e: Array) -> bool: return String(e[0]) == "defeated").size(), 1)
	# A won save never spawns him again.
	await _load()
	assert_null(_area.get("boss"), "no boss on a won save")
	assert_not_null(_area.get("resident"))


func test_dying_mid_fight_resets_to_the_arena_start_state() -> void:
	await _load()
	var b: Node3D = _area.get("boss")
	b.set_process(false)
	var p := _stand(Vector3(0, 0, -60))
	b.set("target_override", p)
	_area.set("player_override", p)
	(_area.get("teach_candle") as Node3D).interact(null)
	_tick_until(b, "glide")
	b.call("jump_to_phase", 3)
	b.set("next_action", "channel")
	_tick_until(b, "channel_rest", 15.0)
	var dark := 0
	for wc in _area.get("arena_candles"):
		if not bool(wc.call("is_lit")):
			dark += 1
	assert_eq(dark, 1, "he snuffed one")
	Events.player_died.emit()
	assert_false(bool(_area.get("fight_active")), "the area paused the encounter")
	assert_false(bool(b.get("fight_started")))
	for wc in _area.get("arena_candles"):
		assert_true(bool(wc.call("is_lit")), "candles back to the start state")
	assert_false(bool(GameState.get_flag(Layout.FLAG_VELOUR_DEFEATED)))
	# Standing in the arena again resumes at once (she already knows the candles).
	_area.call("update_encounter")
	assert_true(bool(b.get("fight_started")))
