extends "res://tests/test_case.gd"
## HUD tip card, fight tips (src/ui/hud/hint_card.gd FIGHT_TIP_PREFIXES; final 2.0.1 run: Crossing Matron tips spilled
## past her defeat and a Weaver tip showed over the Chapter One ending): a newer fight tip replaces an older queued one
## (whose once-per-save flag is given back), the fight tip on screen makes room after FIGHT_TIP_MIN_SECONDS when a newer
## one waits, and the end of the encounter drops every fight tip at once (also while the card is held); ordinary tips
## are never dropped by any of this.
## 2.0.3 (native 2.0.2 run: the Quarry Warden's attack tells "tell_quarry_warden_*" queued like ordinary tips, showed up
## to 26 s late and past its defeat, and its "shell is open" tip was dropped unshown): tip_priority - openings above
## instructions above elite attack tells above ordinary tips; fight tips queue ahead of ordinary ones, an ordinary tip on
## screen makes room after FIGHT_TIP_MIN_SECONDS (and comes back if it was cut before half of its reading time), a tell
## never replaces or cuts short an instruction, an opening takes over after OPENING_MIN_SECONDS; the Warden's bench tip
## outlives the encounter it ends, and a hidden boss bar (the Knotted Elder) ends the fight tips too.

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
	for id in ["boss_crossing_exposed", "boss_channel", "velour_dash", "choir_sweep", "hint_quarry_warden_pillars",
			"tell_quarry_warden_charge", "tell_quarry_warden_pulses", "tell_knotted_elder_roots"]:
		assert_true(HintCard.is_fight_tip(id), id)
	for id in ["ob_wand", "tell_brood_skitter_leap", "quest_ch2_false_home", "hint_borrowed_wisp_reveal", "bed_respawn",
			"hint_quarry_warden_bench", "tell_borrowed_wisp_sweep", "hr_quarry_winch"]:
		assert_false(HintCard.is_fight_tip(id), id)


func test_tip_priorities() -> void:
	# 2.0.3 (native 2.0.2 run): the Warden's attack tells are fight tips one step below the fight's instructions, and
	# the "strike now" openings sit above every other tip.
	for id in ["hint_quarry_warden_exposed", "boss_crossing_exposed", "choir_exposed", "boss_stuck", "boss_scorched",
			"boss_snapped", "boss_crossing_stranded"]:
		assert_eq(HintCard.tip_priority(id), HintCard.OPENING, id + " is an opening")
	for id in ["hint_quarry_warden_pillars", "hint_quarry_warden_pulses", "boss_phase2", "boss_crossing_phase3",
			"velour_phase3", "velour_dash", "choir_rings", "boss_braziers"]:
		assert_eq(HintCard.tip_priority(id), 2, id + " is an instruction")
	for id in ["tell_quarry_warden_slam", "tell_quarry_warden_charge", "tell_quarry_warden_pulses", "tell_knotted_elder_charge"]:
		assert_eq(HintCard.tip_priority(id), 1, id + " is an attack tell")
	for id in ["hr_quarry_winch", "quest_ch2_quarry", "tell_brood_skitter_leap", "hint_quarry_warden_bench", "ob_wand"]:
		assert_eq(HintCard.tip_priority(id), 0, id + " is an ordinary tip")


func test_a_newer_fight_tip_replaces_an_older_queued_one() -> void:
	assert_true(card.on_hint("t_first", "A first tip."))
	assert_eq(card.current_id(), "t_first")
	assert_true(card.on_hint("boss_a", "Light the brazier."))
	assert_true(card.on_hint("t_second", "A second tip."))
	assert_eq(_queued_ids(), ["boss_a", "t_second"])
	assert_true(card.on_hint("boss_b", "Strike now!"))
	# (2.0.3: a fight tip queues ahead of the ordinary tips; 2.0.2 put it behind them)
	assert_eq(_queued_ids(), ["boss_b", "t_second"], "the older fight tip left the queue, the ordinary one stayed")
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


func test_an_ordinary_tip_makes_room_for_a_fight_tip_after_the_minimum_reading_time() -> void:
	# 2.0.3 (native 2.0.2 run: the Quarry Warden's first attack tell showed 16 s late behind two quest tips): 2.0.2 let
	# an ordinary tip on screen keep its full time; now it keeps FIGHT_TIP_MIN_SECONDS while a fight tip waits.
	assert_true(card.on_hint("t_first", "A first tip that stays readable."))      # 7 s of reading time
	assert_true(card.on_hint("t_waiting", "Another ordinary tip."))
	card._process(5.0)
	assert_eq(card.current_id(), "t_first", "an ordinary tip never cuts another one short")
	var c1: Control = HintCard.new()
	add_child(c1)
	await wait_frames(1)
	c1.set_process(false)
	GameState.set_flag("hint_t_first", false)
	assert_true(c1.on_hint("t_first", "A first tip that stays readable."))
	assert_true(c1.on_hint("boss_b", "Strike now!"))
	c1._process(3.0)
	assert_eq(c1.current_id(), "t_first", "inside the minimum reading time")
	c1._process(1.2)
	assert_false(c1.is_showing(), "made room after %.1f s" % HintCard.FIGHT_TIP_MIN_SECONDS)
	assert_eq(c1.queued_count(), 1, "read for more than half of its time: it does not come back")
	await wait_seconds(0.6)
	assert_eq(c1.current_id(), "boss_b", "the fight tip follows")
	c1.queue_free()
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


# --- 2.0.3: priorities (native 2.0.2 run, the Quarry Warden) --------------------------------------------------------

const WINCH := "A cracked gear, a jammed pawl and a slack chain. With a little wood, stone and iron ore the old winch could lower its gangway again."
const QUEST := "The Quarry Warden guards the lamp. Mend the old winch to reach the upper terraces."
const SLAM := "Rears up and its cracked bell glows before a heavy slam. Side-step and punish."
const CHARGE := "Scrapes the ground and aims at you before charging. Bait it into a mineral pillar to crack its shell open."
const PULSES := "Three rings are drawn one after another before three spaced ground pulses."
const EXPOSED := "The Warden's shell is open! Strike the glowing bell before it closes."
const PILLARS := "Blows only glance off its shell now! Stand with a mineral pillar behind you, then side-step its charge so it crashes into the pillar."


func test_the_wardens_first_tell_goes_ahead_of_the_quest_tips() -> void:
	# The recorded order: two ordinary tips just before the fight, then its first attack tell.
	assert_true(card.on_hint("hr_quarry_winch", WINCH))
	assert_true(card.on_hint("quest_ch2_quarry", QUEST))
	card._process(1.0)
	assert_true(card.on_hint("tell_quarry_warden_slam", SLAM))
	assert_eq(_queued_ids(), ["tell_quarry_warden_slam", "quest_ch2_quarry"], "the fight tip queues ahead")
	card._process(2.5)
	assert_eq(card.current_id(), "hr_quarry_winch", "the ordinary tip keeps its minimum reading time")
	card._process(0.6)
	assert_false(card.is_showing(), "then makes room")
	var q: Array = card.get("_queue")
	assert_eq(_queued_ids(), ["tell_quarry_warden_slam", "hr_quarry_winch", "quest_ch2_quarry"],
		"cut before half of its reading time: it comes back first among the ordinary tips")
	assert_true(float((q[1] as Dictionary).get("time", 0.0)) > 6.0, "for the rest of its time (%s)" % str(q[1]))
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "tell_quarry_warden_slam", "the tell is on screen within ~4 s of the fight")
	assert_true(bool(GameState.get_flag("hint_hr_quarry_winch")), "the cut tip stays remembered (it is queued)")


func test_attack_tells_never_starve_an_instruction() -> void:
	assert_true(card.on_hint("tell_quarry_warden_slam", SLAM))
	assert_true(card.on_hint("hint_quarry_warden_pillars", PILLARS))
	assert_true(card.on_hint("tell_quarry_warden_charge", CHARGE))
	assert_eq(_queued_ids(), ["hint_quarry_warden_pillars", "tell_quarry_warden_charge"],
		"a newer tell neither replaces nor passes a waiting instruction")
	assert_true(card.on_hint("tell_quarry_warden_pulses", PULSES))
	assert_eq(_queued_ids(), ["hint_quarry_warden_pillars", "tell_quarry_warden_pulses"], "a newer tell replaces an older tell")
	assert_false(bool(GameState.get_flag("hint_tell_quarry_warden_charge")), "which gets its flag back")
	card._process(4.1)
	assert_false(card.is_showing(), "the tell on screen made room for the instruction")
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "hint_quarry_warden_pillars")
	card._process(6.0)
	assert_eq(card.current_id(), "hint_quarry_warden_pillars", "a waiting tell never cuts an instruction short")
	card._process(8.0)
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "tell_quarry_warden_pulses", "the tell follows once the instruction is read")


func test_an_opening_shows_within_a_second() -> void:
	assert_true(card.on_hint("tell_quarry_warden_charge", CHARGE))
	card._process(0.5)
	assert_true(card.on_hint("hint_quarry_warden_exposed", EXPOSED))
	card._process(0.3)
	assert_eq(card.current_id(), "tell_quarry_warden_charge", "not a sub-second flash")
	card._process(0.3)
	assert_false(card.is_showing(), "made room after %.1f s" % HintCard.OPENING_MIN_SECONDS)
	assert_false(bool(GameState.get_flag("hint_tell_quarry_warden_charge")), "a tell cut that soon counts as unread")
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "hint_quarry_warden_exposed")
	# on screen: a tell waits behind it, an instruction cuts it after the minimum reading time (its window is over)
	assert_true(card.on_hint("tell_quarry_warden_pulses", PULSES))
	card._process(5.0)
	assert_eq(card.current_id(), "hint_quarry_warden_exposed", "a tell never cuts an opening short")
	assert_true(card.on_hint("hint_quarry_warden_pillars", PILLARS))
	assert_eq(_queued_ids(), ["hint_quarry_warden_pillars"], "a newer instruction replaces a waiting tell")
	assert_false(bool(GameState.get_flag("hint_tell_quarry_warden_pulses")), "which gets its flag back")
	card._process(0.1)
	assert_false(card.is_showing(), "an instruction takes over after %.1f s" % HintCard.FIGHT_TIP_MIN_SECONDS)
	assert_true(bool(GameState.get_flag("hint_hint_quarry_warden_exposed")), "read long enough: stays remembered")


func test_an_opening_is_never_replaced_by_an_instruction() -> void:
	assert_true(card.on_hint("t_first", "An ordinary tip on screen."))
	assert_true(card.on_hint("boss_crossing_exposed", "The light burned her off the anchor! Strike now!"))
	assert_true(card.on_hint("boss_crossing_phase2", "She fled to the other side of the bridge."))
	assert_eq(_queued_ids(), ["boss_crossing_exposed", "boss_crossing_phase2"], "the opening stays first")
	card._process(1.1)
	assert_false(card.is_showing(), "an ordinary tip makes room for an opening after %.1f s" % HintCard.OPENING_MIN_SECONDS)
	assert_eq(_queued_ids(), ["boss_crossing_exposed", "boss_crossing_phase2", "t_first"],
		"and comes back after the fight tips")


func test_nothing_of_the_warden_fight_outlives_it() -> void:
	assert_true(card.on_hint("hr_quarry_winch", WINCH))
	card._process(4.5)
	assert_true(card.on_hint("tell_quarry_warden_slam", SLAM))
	card._process(0.1)
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "tell_quarry_warden_slam")
	assert_true(card.on_hint("quest_ch2_quarry", QUEST))
	assert_true(card.on_hint("hint_quarry_warden_exposed", EXPOSED))
	assert_true(card.on_hint("tell_quarry_warden_pulses", PULSES))
	assert_eq(_queued_ids(), ["hint_quarry_warden_exposed", "tell_quarry_warden_pulses", "hr_quarry_winch", "quest_ch2_quarry"])
	Events.boss_encounter_changed.emit("quarry_warden", false)     # its defeat commits before boss_defeated
	Events.boss_defeated.emit("quarry_warden")
	assert_eq(card.current_id(), "", "the tell on screen leaves at once")
	assert_eq(_queued_ids(), ["hr_quarry_winch", "quest_ch2_quarry"], "the opening and the tell are dropped too")
	assert_false(bool(GameState.get_flag("hint_hint_quarry_warden_exposed")), "unshown: given back")
	assert_false(bool(GameState.get_flag("hint_tell_quarry_warden_pulses")), "unshown: given back")
	await wait_seconds(0.6)
	assert_eq(card.current_id(), "hr_quarry_winch", "the ordinary tips still show afterwards")


func test_the_bench_tip_outlives_the_encounter_it_ends() -> void:
	# quarry_warden.gd: the give-up emits the bench tip, and the same tick walks it home (boss_encounter_changed false).
	assert_true(card.on_hint("hint_quarry_warden_bench", "The Warden won't leave its bench - it goes back to rest and mends."))
	Events.boss_encounter_changed.emit("quarry_warden", false)
	assert_eq(card.current_id(), "hint_quarry_warden_bench", "still on screen")
	assert_true(bool(GameState.get_flag("hint_hint_quarry_warden_bench")))


func test_a_hidden_boss_bar_ends_the_elders_fight_tips() -> void:
	# The Knotted Elder has no encounter event: its bar hiding (boss_health_changed hp < 0) is the end of its fight.
	assert_true(card.on_hint("tell_knotted_elder_charge", "Plants its feet and its crown of thorns glows before a charge."))
	assert_true(card.on_hint("tell_knotted_elder_roots", "Temporary roots burst up around the arena."))
	Events.boss_health_changed.emit("knotted_elder", 120.0, 240.0)
	assert_eq(card.current_id(), "tell_knotted_elder_charge", "a health update changes nothing")
	Events.boss_health_changed.emit("knotted_elder", -1.0, 240.0)
	assert_eq(card.current_id(), "", "its bar hid: its tells go")
	assert_eq(card.queued_count(), 0)
	assert_false(bool(GameState.get_flag("hint_tell_knotted_elder_roots")), "the unshown one is given back")


## Replays `events` ([time, id, text]; id "" = the Warden's defeat frame: bar hidden, encounter over, boss_defeated)
## through card `c` with a fake 60 fps clock - its _process and its fade tweens stepped by hand in one synchronous loop
## (the tree runs no frame in between) - from `t0` to `t1`. Returns [id, shown_at, hidden_at] for every tip shown.
func _replay(c: Control, events: Array, t0: float, t1: float) -> Array:
	var dt := 1.0 / 60.0
	var shown: Array = []
	var cur := ""
	var i := 0
	var t := t0
	while t < t1:
		while i < events.size() and float((events[i] as Array)[0]) <= t:
			var e: Array = events[i]
			i += 1
			if String(e[1]) == "":
				Events.boss_health_changed.emit("quarry_warden", -1.0, 300.0)
				Events.boss_encounter_changed.emit("quarry_warden", false)
				Events.boss_defeated.emit("quarry_warden")
			else:
				c.on_hint(String(e[1]), String(e[2]))
			cur = _track(c, shown, cur, t)
		c._process(dt)
		for tw in (c.get("_tw") as Dictionary).values():
			if tw is Tween and (tw as Tween).is_valid() and (tw as Tween).is_running():
				(tw as Tween).custom_step(dt)
		t += dt
		cur = _track(c, shown, cur, t)
	return shown


func _track(c: Control, shown: Array, cur: String, t: float) -> String:
	var now := String(c.call("current_id"))
	if now == cur:
		return cur
	if cur != "":
		(shown[shown.size() - 1] as Array)[2] = t
	if now != "":
		shown.append([now, t, -1.0])
	return now


func _first_shown(shown: Array, id: String) -> Array:
	for s in shown:
		if String((s as Array)[0]) == id:
			return s
	return []


func test_the_recorded_warden_fight_replayed() -> void:
	# Every Events.hint of the Quarry Warden fight in the native 2.0.2 run (qa/tmp/bot/chain/native_202_visible, g2
	# telemetry: a New-Game save, packaged build) at its recorded time, then its defeat frame. The 2.0.2 card showed the
	# first tell 16 s late, kept the charge and pulses tells up to 13 s past the defeat (screenshots s2_020 / s2_021) and
	# dropped "the shell is open" unshown at the defeat.
	var defeat := 216.16
	var events := [[177.13, "hr_quarry_winch", WINCH], [177.28, "quest_ch2_quarry", QUEST],
		[185.33, "tell_quarry_warden_slam", SLAM], [190.30, "tell_quarry_warden_charge", CHARGE],
		[192.70, "hint_quarry_warden_exposed", EXPOSED], [197.77, "tell_quarry_warden_pulses", PULSES],
		[207.02, "hint_quarry_warden_exposed", EXPOSED], [214.47, "hint_quarry_warden_exposed", EXPOSED],
		[defeat, "", ""]]
	var shown := _replay(card, events, 177.0, 250.0)
	var exposed := _first_shown(shown, "hint_quarry_warden_exposed")
	assert_false(exposed.is_empty(), "the shell-open tip shows (%s)" % str(shown))
	if not exposed.is_empty():
		assert_true(float(exposed[1]) - 192.70 <= 1.0, "promptly, during its window (%.2f s late)" % (float(exposed[1]) - 192.70))
		assert_true(float(exposed[2]) - float(exposed[1]) >= HintCard.FIGHT_TIP_MIN_SECONDS, "and stays readable (%s)" % str(exposed))
	var slam := _first_shown(shown, "tell_quarry_warden_slam")
	assert_false(slam.is_empty(), "the first attack tell shows")
	if not slam.is_empty():
		assert_true(float(slam[1]) - 185.33 <= HintCard.FIGHT_TIP_MIN_SECONDS + 0.5,
			"within the quest tip's minimum reading time (%.2f s late)" % (float(slam[1]) - 185.33))
	var pulses := _first_shown(shown, "tell_quarry_warden_pulses")
	assert_true(not pulses.is_empty() and float(pulses[1]) < defeat, "the pulses tell shows during the fight (%s)" % str(pulses))
	for s in shown:
		var sid := String((s as Array)[0])
		if sid.begins_with("tell_quarry_warden_") or sid.begins_with("hint_quarry_warden_") or HintCard.is_fight_tip(sid):
			assert_true(float(s[1]) < defeat and float(s[2]) >= 0.0 and float(s[2]) <= defeat + 0.05,
				"no tip of the fight on screen after the defeat (%s)" % str(s))
	for id in ["hr_quarry_winch", "quest_ch2_quarry"]:
		assert_false(_first_shown(shown, id).is_empty(), id + ": the ordinary tips still show")
	assert_eq(card.queued_count(), 0, "nothing left waiting")
	assert_false(card.is_showing(), "and nothing lingers")


func test_defeat_and_area_change_are_wired() -> void:
	for sig in [Events.boss_defeated, Events.area_exiting, Events.boss_encounter_changed, Events.boss_health_changed]:
		var found := false
		for c in (sig as Signal).get_connections():
			if (c["callable"] as Callable).get_object() == card:
				found = true
		assert_true(found, "the card listens to %s" % (sig as Signal).get_name())
