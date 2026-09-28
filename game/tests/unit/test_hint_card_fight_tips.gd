extends "res://tests/test_case.gd"
## HUD tip card, fight tips (src/ui/hud/hint_card.gd FIGHT_TIP_PREFIXES; final 2.0.1 run: Crossing Matron tips spilled
## past her defeat and a Weaver tip showed over the Chapter One ending): a newer fight tip replaces an older queued one
## (whose once-per-save flag is given back), the fight tip on screen makes room after FIGHT_TIP_MIN_SECONDS when a newer
## one waits, and the end of the encounter drops every fight tip at once (also while the card is held); ordinary tips
## are never cut short or dropped by any of this.

const HintCard := preload("res://src/ui/hud/hint_card.gd")

var card: Control = null
var _settings := {}


func before_each() -> void:
	fresh_state()
	_settings = Settings.values.duplicate(true)
	Settings.values["show_hints"] = true
	card = HintCard.new()
	add_child(card)
	await wait_frames(1)
	card.set_process(false)           # the tests step _process themselves


func after_each() -> void:
	Settings.values = _settings
	if is_instance_valid(card):
		card.queue_free()
	card = null
	await wait_frames(1)


func _queued_ids() -> Array:
	var out: Array = []
	for q in card.get("_queue"):
		out.append(String((q as Dictionary)["id"]))
	return out


func test_which_tips_are_fight_tips() -> void:
	for id in ["boss_crossing_exposed", "boss_channel", "velour_dash", "choir_sweep", "hint_quarry_warden_pillars"]:
		assert_true(HintCard.is_fight_tip(id), id)
	for id in ["ob_wand", "tell_brood_skitter_leap", "quest_ch2_false_home", "hint_borrowed_wisp_reveal", "bed_respawn"]:
		assert_false(HintCard.is_fight_tip(id), id)


func test_a_newer_fight_tip_replaces_an_older_queued_one() -> void:
	assert_true(card.on_hint("t_first", "A first tip."))
	assert_eq(card.current_id(), "t_first")
	assert_true(card.on_hint("boss_a", "Light the brazier."))
	assert_true(card.on_hint("t_second", "A second tip."))
	assert_eq(_queued_ids(), ["boss_a", "t_second"])
	assert_true(card.on_hint("boss_b", "Strike now!"))
	assert_eq(_queued_ids(), ["t_second", "boss_b"], "the older fight tip left the queue, the ordinary one stayed")
	assert_false(bool(GameState.get_flag("hint_boss_a")), "a fight tip dropped unshown can teach a later attempt")
	assert_true(bool(GameState.get_flag("hint_boss_b")))
	assert_true(card.on_hint("boss_a", "Light the brazier."), "so it is accepted again")


func test_the_fight_tip_on_screen_makes_room_for_a_newer_one() -> void:
	assert_true(card.on_hint("boss_a", "Light the brazier under her anchor."))
	assert_eq(card.current_id(), "boss_a")
	card._process(3.0)
	assert_eq(card.current_id(), "boss_a", "nothing waiting: a fight tip keeps its full time")
	assert_true(card.on_hint("boss_b", "Strike now!"))
	card._process(0.5)
	assert_eq(card.current_id(), "boss_a", "still inside the minimum reading time")
	card._process(1.0)
	assert_false(card.is_showing(), "made room after %.1f s" % HintCard.FIGHT_TIP_MIN_SECONDS)
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "boss_b", "the newer fight tip follows")


func test_ordinary_tips_keep_their_full_time() -> void:
	assert_true(card.on_hint("t_first", "A first tip that stays readable."))
	assert_true(card.on_hint("boss_b", "Strike now!"))
	card._process(5.0)
	assert_eq(card.current_id(), "t_first", "an ordinary tip is not cut short by a waiting fight tip")
	assert_true(card.on_hint("boss_c", "Dodge!"))
	assert_eq(card.current_id(), "t_first")
	card._process(0.5)
	assert_eq(card.current_id(), "t_first")
	# and a fight tip with only an ordinary tip behind it keeps its time too
	var c2: Control = HintCard.new()
	add_child(c2)
	await wait_frames(1)
	c2.set_process(false)
	GameState.set_flag("hint_boss_x", false)
	assert_true(c2.on_hint("boss_x", "Light the brazier."))
	assert_true(c2.on_hint("t_other", "Another tip."))
	c2._process(5.0)
	assert_eq(c2.current_id(), "boss_x")
	c2.queue_free()


func test_the_end_of_the_encounter_drops_the_fight_tips() -> void:
	assert_true(card.on_hint("boss_a", "Light the brazier."))
	assert_true(card.on_hint("t_other", "An ordinary tip."))
	assert_true(card.on_hint("boss_b", "Strike now!"))
	Events.boss_encounter_changed.emit("test_boss", true)
	assert_eq(card.current_id(), "boss_a", "the start of an encounter changes nothing")
	Events.boss_encounter_changed.emit("test_boss", false)
	assert_eq(card.current_id(), "", "the fight tip on screen leaves at once")
	assert_eq(_queued_ids(), ["t_other"], "queued fight tips are gone, the ordinary one waits")
	assert_true(bool(GameState.get_flag("hint_boss_a")), "a tip that was shown stays remembered")
	assert_false(bool(GameState.get_flag("hint_boss_b")), "an unshown one is given back")
	await wait_seconds(0.5)
	assert_eq(card.current_id(), "t_other", "the ordinary tip follows")


func test_a_held_fight_tip_never_comes_back_after_the_fight() -> void:
	assert_true(card.on_hint("boss_channel", "It is smothering a brazier!"))
	card.set_held(true)                # e.g. the ending or a chapter card
	card.drop_fight_tips()             # the boss was defeated meanwhile
	card.set_held(false)
	await wait_frames(2)
	assert_ne(card.current_id(), "boss_channel")
	assert_false(card.is_showing(), "nothing stale over the world")
	await wait_seconds(0.6)
	assert_false(card.visible, "the card hid")


func test_defeat_and_area_change_are_wired() -> void:
	for sig in [Events.boss_defeated, Events.area_exiting, Events.boss_encounter_changed]:
		var found := false
		for c in (sig as Signal).get_connections():
			if (c["callable"] as Callable).get_object() == card:
				found = true
		assert_true(found, "the card listens to %s" % (sig as Signal).get_name())
