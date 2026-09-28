extends "res://tests/unit/test_boss_choir_harness.gd"
## The Borrowed Choir as an encounter (MP §13.3, §14, spec §9-10): factory registration and data hp, the events
## (boss_encounter_changed on/off once, boss_phase_changed 1/2/3 for the m26 layers, the bar), the victory commit
## BEFORE any presentation and exactly once (arena listener or the boss's own fallback, never in trial mode), a won
## save never replays the fight, a flag set elsewhere dismisses it quietly, the reset policy (death / leaving ->
## clean reset to the phase checkpoint, every prop back to default), the director hold, only Krystal is ever hit,
## the real Choir Vault integration (choir_arena.gd boss_params, commit through the arena), and a pacing model.

const HP := 5000.0
const DeepHost := preload("res://src/world/works/deep/deep_preview_host.gd")
const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const VaultLayout := preload("res://data/works_layout_deep.gd")


## Plays the fight like a perfect bot: instant reveals / picks / plates / raises; `strong` = one huge blow per
## exposure. Returns the seconds of fight clock until the Choir is gone (mechanics only: no walking modelled).
func _bot(b: Node, strong: bool, max_t: float = 900.0) -> float:
	var t := 0.0
	var struck_window := false
	while not bool(b.is_gone()) and t < max_t:
		match String(b.state):
			"a_wait":
				if not bool(b.revealed):
					raise(0)
				b.pick_form(b.genuine, b.target_override)
			"b_idle", "b_gather", "b_reform":
				for r in resonators:
					if not bool((r as Node).call("is_active")) and bool((r as Node).get("enabled")):
						strike_sequence(r)
			"c_open":
				raise(int(b.flame_anchor))
		if strong and b.is_vulnerable() and not struck_window:
			struck_window = true
			b.health.apply_damage(99999.0, b.target_override)
		if not b.is_vulnerable():
			struck_window = false
		b.tick(DT)
		t += DT
	return t


func test_factory_registration_and_data() -> void:
	assert_true(Factory.has_enemy(BOSS_ID), "EnemyFactory knows borrowed_choir")
	assert_true(Factory.can_spawn(BOSS_ID), "and its script compiles")
	var hp := float(ItemDB.enemy(BOSS_ID).get("hp", 0.0))
	assert_true(hp >= 480.0 and hp <= 620.0, "data hp inside the MP range (%d)" % int(hp))
	make_arena()
	var b := make_boss(dummy(Vector3(0, 0, -9)))
	assert_almost(float(b.health.max_hp), hp, 0.001, "the boss reads data/enemies.gd")
	assert_eq(int(b.phase), 1, "a fresh Choir (quit / reload) always starts in phase A")
	assert_true(b.is_in_group("enemy"))
	assert_false(b.is_threatening(), "dormant until the fight starts")


func test_events_follow_phases_and_the_encounter_ends_once() -> void:
	make_arena()
	var b := make_boss(dummy(Vector3(0, 0, -9), false, HP))
	b.start_fight()
	assert_eq(encounters, [[BOSS_ID, true]], "boss_encounter_changed(on)")
	assert_eq(phase_list(), [1], "boss_phase_changed(1) at the start (m26 layer 1)")
	assert_eq(bars.back(), [BOSS_ID, 540.0, 540.0], "the bar shows")
	assert_true(b.is_threatening())
	var t := _bot(b, true)
	assert_true(bool(b.is_gone()), "the bot finishes the fight (%.0f s)" % t)
	assert_eq(phase_list(), [1, 2, 3], "phases 1 -> 2 -> 3, each once, in order")
	assert_eq(encounters.back(), [BOSS_ID, false], "boss_encounter_changed(off)")
	var offs := 0
	for e in encounters:
		if not bool(e[1]):
			offs += 1
	assert_eq(offs, 1, "ended once")
	assert_eq(defeats, [BOSS_ID], "Events.boss_defeated('borrowed_choir') exactly once")
	assert_almost(float((bars.back() as Array)[1]), -1.0, 0.001, "the bar is hidden")
	var last_hp := 99999.0
	for e in bars:
		if float(e[1]) >= 0.0:
			assert_true(float(e[1]) <= last_hp + 0.001, "the bar never refills during a clean run")
			last_hp = float(e[1])


func test_victory_commits_before_presentation_and_never_twice() -> void:
	make_arena()
	var b := make_boss(dummy(Vector3(0, 0, -9), false, HP))
	b.fast_defeat = false
	var at_signal: Array = []
	b.defeated.connect(func() -> void: at_signal.append([bool(GameState.get_flag("ch2_choir_defeated")), defeats.duplicate(), String(b.state)]))
	start_in_phase(b, 3)
	for k in 3:
		assert_true(until(b, "c_open") >= 0.0)
		raise(int(b.flame_anchor))
		b.health.apply_damage(99999.0, b.target_override)
	assert_eq(at_signal.size(), 1, "`defeated` once")
	assert_true(bool(at_signal[0][0]), "ch2_choir_defeated is committed before anything else happens")
	assert_eq(at_signal[0][1], [BOSS_ID], "boss_defeated already emitted")
	assert_eq(String(b.state), "defeat", "the presentation is still running after the commit")
	assert_false(b.is_in_group("enemy"), "no longer a target")
	assert_false(b.can_be_hit_by(b.target_override))
	assert_eq(encounters.back(), [BOSS_ID, false])
	run(b, 1.5)
	assert_true(has_caption("gentle chimes"), "the echoes rise as chimes (captioned)")
	run(b, 3.0)
	assert_eq(String(b.state), "gone", "masks and ribbons have fallen; the vault is quiet")
	assert_false(b.visible)
	b._begin_defeat()
	b.dismiss()
	assert_eq(defeats.size(), 1, "never twice")
	# a later load of the won save: no replayed fight
	var again := make_boss(dummy(Vector3(0, 0, -9)))
	assert_true(bool(again.is_gone()), "a won story save never spawns a live Choir")
	assert_false(again.is_in_group("enemy"))
	var n := encounters.size()
	again.start_fight()
	assert_eq(encounters.size(), n, "and it cannot be restarted")


func test_trial_mode_writes_no_flag() -> void:
	make_arena()
	GameState.set_flag("ch2_choir_defeated", true)
	var b := make_boss(dummy(Vector3(0, 0, -9), false, HP), 1, {"mode": "trial"})
	assert_false(bool(b.is_gone()), "the echo trial fights even after the story victory")
	GameState.set_flag("ch2_choir_defeated", false)
	var got := [false]
	b.defeated.connect(func() -> void: got[0] = true)
	start_in_phase(b, 3)
	_bot(b, true)
	assert_true(bool(got[0]), "the trial module hears `defeated`")
	assert_eq(defeats.size(), 0, "no Events.boss_defeated from a trial")
	assert_false(bool(GameState.get_flag("ch2_choir_defeated")), "and no story flag")


func test_flag_set_elsewhere_dismisses_quietly() -> void:
	make_arena()
	var b := make_boss(dummy(Vector3(0, 0, -9)))
	b.start_fight()
	assert_true(until(b, "a_wait") >= 0.0)
	GameState.set_flag("ch2_choir_defeated", true)
	assert_true(bool(b.is_gone()), "gone at once")
	assert_eq(defeats.size(), 0, "no boss_defeated of its own")
	assert_eq(encounters.back(), [BOSS_ID, false], "the encounter ends (music, saving)")
	assert_almost(float((bars.back() as Array)[1]), -1.0, 0.001, "the bar hides")
	for f in b.forms:
		assert_false((f as Node3D).visible, "no forms left behind")
	var b2 := make_boss(dummy(Vector3(0, 0, -9)), 1, {"mode": "trial"})
	GameState.set_flag("ch2_choir_defeated", false)
	b2.start_fight()
	Events.boss_defeated.emit("count_velour")
	assert_false(bool(b2.is_gone()), "other bosses are ignored")


func test_death_resets_cleanly_to_the_phase_checkpoint() -> void:
	make_arena()
	var d := dummy(Vector3(3, 0, -4), false, HP)
	var b := make_boss(d)
	start_in_phase(b, 2)
	assert_true(until(b, "b_idle") >= 0.0)
	for r in resonators:
		strike_sequence(r)
	assert_true(until(b, "b_exposed") >= 0.0)
	b.health.apply_damage(50.0, d)
	assert_true(until(b, "b_idle") >= 0.0, "a second cycle")
	strike_sequence(resonators[0])
	(resonators[1] as Node).call("strike", String(taught_ids()[0]))
	raise(1)
	b._b_rings_next = false
	assert_true(until(b, "b_strike_tele") >= 0.0)
	assert_true(int(b.strikes.count()) > 0 and int(b.layers.count()) == 1 and int(b.wisps_alive()) > 0, "mid-fight props")
	Events.player_died.emit()
	assert_eq(String(b.state), "dormant", "she fell: the encounter resets")
	assert_false(bool(b.fight_started))
	assert_eq(encounters.back(), [BOSS_ID, false], "music released / saving gate opened")
	assert_almost(float((bars.back() as Array)[1]), -1.0, 0.001, "bar hidden")
	assert_eq(int(b.phase), 2, "the phase she reached is kept (checkpoint)")
	assert_almost(float(b.health.hp), Rules.phase_start_hp(2, float(b.health.max_hp)), 0.001, "hp back to that phase's start - never mismatched")
	for r in resonators:
		assert_eq(int((r as Node).get("progress")), 0, "resonators reset")
		assert_false(bool((r as Node).call("is_active")))
		assert_true(bool((r as Node).get("enabled")), "and back to their default")
	for a in anchors:
		assert_false(bool((a as Node).call("is_raised")), "anchors lowered")
	assert_eq(int(b.layers.count()), 0)
	assert_eq(int(b.strikes.count()), 0, "no hazard left behind")
	assert_eq(int(b.rings.active_count()), 0)
	assert_false(bool(b.mark_fx.call("is_showing")))
	assert_false(Base._attackers.has(b.get_instance_id()), "attack token released")
	await wait_frames(1)
	assert_eq(int(b.wisps_alive()), 0, "wisps dismissed")
	b.start_fight()
	assert_eq(phase_list().back(), 2, "re-engaging announces phase 2 again (music layers match)")
	assert_true(bool(b.retry))
	assert_true(until(b, "b_gather", 3.0) >= 0.0, "a short intro on a retry")
	assert_eq(int(b.layers.count()), 2, "props rebuilt from scratch")
	assert_eq(int(b.wisps_alive()), 2, "wisps within the cap again")


## Integration pass 2 (P57): the retry hint names the real way to a full recovery - leaving the Hushed Works in the
## story, the pale door inside the Echo Trial (its own hint id, so the story hint still teaches once in the Works).
func test_retry_hint_names_the_way_out_per_mode() -> void:
	make_arena()
	var hints: Array = []
	var cb := func(id: String, text: String) -> void:
		if id.begins_with("choir_retry"):
			hints.append([id, text])
	Events.hint.connect(cb)
	for mode in ["story", "trial"]:
		hints.clear()
		var d := dummy(Vector3(0, 0, -9), false, HP)
		var b := make_boss(d, 1, {"mode": mode})
		b.start_fight()
		assert_true(until(b, "a_wait") >= 0.0)
		assert_eq(hints.size(), 0, "%s: no retry hint on the first attempt" % mode)
		Events.player_died.emit()
		assert_eq(String(b.state), "dormant", "%s: she fell, the encounter reset" % mode)
		b.start_fight()
		assert_true(bool(b.retry))
		assert_eq(hints.size(), 1, "%s: one retry hint" % mode)
		if hints.size() == 1:
			var id := String(hints[0][0])
			var text := String(hints[0][1])
			if mode == "trial":
				assert_eq(id, "choir_retry_trial", "the Echo Trial has its own hint id")
				assert_true(text.contains("pale door") and text.contains("afresh"), "trial wording: %s" % text)
				assert_false(text.contains("Hushed Works"), "never sends her out of the Works from inside a memory")
			else:
				assert_eq(id, "choir_retry")
				assert_true(text.contains("Leaving the Hushed Works"), "story wording: %s" % text)
		b.queue_free()
		d.queue_free()
		await wait_frames(1)
	Events.hint.disconnect(cb)


func test_leaving_the_vault_stands_down() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	b.start_fight()
	assert_true(until(b, "a_wait") >= 0.0)
	d.global_position = Vector3(0, 0, -20)
	run(b, 2.5)
	assert_true(bool(b.fight_started), "a brief step outside is fine")
	run(b, 1.0)
	assert_eq(String(b.state), "dormant", "gone for LEAVE_TIME: stand down")
	assert_eq(encounters.back(), [BOSS_ID, false])
	for f in b.forms:
		assert_false((f as Node3D).visible)
	d.global_position = Vector3(0, 0, -8)
	run(b, 0.3)
	assert_true(bool(b.fight_started), "walking back in starts it again")


func test_the_director_is_held_for_the_whole_fight() -> void:
	make_arena()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar holds: Array = []\nfunc director_hold(id: String) -> void:\n\tholds.append(\"+\" + id)\nfunc director_release(id: String) -> void:\n\tholds.append(\"-\" + id)\n"
	s.reload()
	var stub: Node3D = s.new()
	add_child(stub)
	Game.area = stub
	var b := make_boss(dummy(Vector3(0, 0, -9)))
	b.start_fight()
	assert_eq(stub.get("holds"), ["+choir_fight"], "held when the fight starts")
	b.reset_fight()
	assert_eq(stub.get("holds"), ["+choir_fight", "-choir_fight"], "released on a reset")
	Game.area = null


func test_only_krystal_is_ever_hit() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -6), false, HP)
	var pal: Node3D = companion(Vector3(0.6, 0, -6.2))
	var ph: Node = preload("res://src/combat/health.gd").new()
	ph.name = "Health"
	ph.set("max_hp", 50.0)
	pal.add_child(ph)
	pal.set("health", ph)
	var b := make_boss(d)
	b.start_fight()
	assert_true(until(b, "a_wait") >= 0.0)
	raise(0)
	b.tick(DT)
	b.pick_form(wrong_form(b), d)
	until(b, "a_recover")
	assert_eq(d.hits.size(), 1, "Krystal is hit")
	assert_almost(float(ph.get("hp")), 50.0, 0.001, "a companion standing beside her never is")
	var foe := Node3D.new()
	add_child(foe)
	foe.add_to_group("enemy")
	b.health.set("invulnerable", false)
	b.state = "a_exposed"
	assert_false(b.can_be_hit_by(foe), "enemies never damage the Choir")


func test_real_vault_integration_through_the_arena() -> void:
	var host: Node3D = DeepHost.new()
	host.set("with_environment", false)
	add_child(host)
	await wait_physics(3)
	var arena: Node = (host.get("deep") as Node).get("choir")
	arena.set("save_on_clear", false)
	assert_true(ChoirArena.boss_available(), "the arena's guarded hook now finds the boss")
	arena.call("start_encounter")
	var b: Node = arena.get("boss")
	assert_not_null(b, "spawned through EnemyFactory with boss_params()")
	assert_false(bool(arena.get("fallback")), "no fallback when the boss exists")
	b.set_process(false)
	assert_eq(b.anchor_nodes.size(), 3, "the three fixed lantern anchors")
	assert_eq(b.resonator_nodes.size(), 2, "the two fixed resonators")
	assert_eq(b.taught_sequence(), taught_ids(), "the Bellmaker's symbol order")
	assert_almost(float(b.perimeter_radius), float(VaultLayout.VAULT["perimeter"]), 0.001)
	assert_true(b.arena_center.distance_to(VaultLayout.VAULT["center"]) < 0.01)
	for i in 3:
		var st: Vector3 = b.station(i)
		assert_true(bool(arena.call("is_inside", st)) and not bool(arena.call("is_on_perimeter", st)), "form station %d inside the vault, off the perimeter" % i)
	var c: Vector3 = VaultLayout.VAULT["center"]
	var d := dummy(c + Vector3(0, 0, -8), false, HP)
	b.target_override = d
	b.fast_defeat = true
	for w in b.get_parent().get_children():
		if w != b and w.is_in_group("enemy"):
			w.set_physics_process(false)
	start_in_phase(b, 3)
	assert_true(Game.boss_active(), "saving / fast travel are blocked during the fight")
	var flag_when_defeated := [false]
	b.defeated.connect(func() -> void: flag_when_defeated[0] = bool(GameState.get_flag("ch2_choir_defeated")) and bool(arena.get("cleared")))
	var ans: Array = arena.call("anchor_nodes")
	for k in 3:
		assert_true(until(b, "c_open") >= 0.0)
		(ans[int(b.flame_anchor)] as Node).call("lower")
		(ans[int(b.flame_anchor)] as Node).call("raise", null)
		assert_eq(String(b.state), "c_exposed", "the vault's own anchor exposes it (%d)" % k)
		b.health.apply_damage(99999.0, d)
	assert_true(bool(flag_when_defeated[0]), "the arena committed ch2_choir_defeated before the presentation")
	assert_true(bool(arena.get("cleared")))
	assert_false(Game.boss_active(), "the fight is over for saving / travel")
	await wait_physics(2)
	assert_true(bool(arena.call("exit_open")), "the exit opens")
	host.queue_free()
	await wait_frames(2)
	var host2: Node3D = DeepHost.new()
	host2.set("with_environment", false)
	add_child(host2)
	await wait_physics(2)
	var arena2: Node = (host2.get("deep") as Node).get("choir")
	assert_true(bool(arena2.get("cleared")), "the won save loads completed")
	arena2.call("start_encounter")
	assert_null(arena2.get("boss"), "no replayed fight, nothing granted twice")


func test_pacing_model_is_not_a_sponge() -> void:
	make_arena()
	var fast := make_boss(dummy(Vector3(0, 0, -9), false, HP))
	fast.start_fight()
	var t_fast := _bot(fast, true)
	fast.queue_free()
	GameState.set_flag("ch2_choir_defeated", false)       # a second, independent first encounter
	var slow := make_boss(dummy(Vector3(0, 0, -9), false, HP))
	slow.start_fight()
	var t_slow := _bot(slow, false)
	print("CHOIR PACING (mechanics only, no walking): strong/instant %.0f s, never-attacking/instant %.0f s" % [t_fast, t_slow])
	assert_true(bool(fast.is_gone()) and bool(slow.is_gone()), "both bots finish")
	assert_true(t_fast >= 30.0, "no burst skips a lesson: 7+ exposures, each with its own beats (%.0f s)" % t_fast)
	assert_true(t_slow <= 180.0, "never a sponge: without hitting at all the reveals alone end it (%.0f s of mechanics)" % t_slow)
	assert_true(int(fast.reveals) == 3, "phase A always takes three correct reveals")
	assert_true(t_slow > t_fast, "good gear shortens the fight")


func test_visual_qa_stage_runs_every_mode_headless() -> void:
	for anim in ["a", "exposed", "b", "c", "victory"]:
		var stage: Node3D = load("res://src/enemies/choir/choir_preview.gd").new()
		add_child(stage)
		var b: Node = stage.get("boss")
		assert_not_null(b, "the stage builds the boss (%s)" % anim)
		b.set_process(false)
		stage.set_process(false)
		stage.call("play_anim", anim)
		for i in 1200:
			stage.call("_process", DT)
			b.tick(DT)
			if anim == "victory" and bool(b.is_gone()):
				break
		match anim:
			"a":
				assert_true(bool(b.revealed), "stage a: an anchor burns over the forms")
			"exposed":
				assert_true(int(b.reveals) >= 1, "stage exposed: a correct reveal happened")
			"b":
				assert_eq(int(b.phase), 2)
			"c":
				assert_eq(int(b.phase), 3)
			"victory":
				assert_true(bool(b.is_gone()), "stage victory: the presentation completes")
		assert_false(bool(GameState.get_flag("ch2_choir_defeated")), "the QA stage is a trial: it never writes the story flag")
		stage.queue_free()
		await wait_frames(1)
