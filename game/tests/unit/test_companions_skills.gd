extends "res://tests/unit/test_companions_fixture.gd"
## Signature skills (MP §6.1-6.3, spec §3/§9): ONE cooldown per companion shared by the manual Companion Skill
## action and the autocast, on the play_seconds timeline (frozen while paused, kept through save/load, pet
## switching and node re-creation); bond perks from the bond level (old saves unlock them at once);
## Bloomguard heals exactly its total over time (no overheal spam, cleanses a slow at 3 hearts); Stoneheart
## through the player's add_shield (guarded) and a stagger that never touches bosses or elites; Glimmerstep
## through GameState.add_buff("glimmerstep") with a light pulse that exposes shadow enemies.

const CombatStatic := preload("res://src/combat/combat.gd")
const PLAYER_HEALTH := "res://src/player/player_health.gd"


class ExposeEnemy extends "res://tests/unit/test_companions_fixture.gd".FakeEnemy:
	var exposed_for: float = 0.0

	func expose(seconds: float) -> void:
		exposed_for = seconds


func _hurt(amount: float) -> void:
	player.health.hp = float(player.health.max_hp) - amount


# --- One shared cooldown ------------------------------------------------------------------------------------------

func test_cooldown_is_shared_by_manual_and_autocast() -> void:
	var m := _follower("mochi")
	_hurt(60.0)
	var r: Dictionary = m.use_skill(true)
	assert_true(bool(r["ok"]), "manual Bloomguard: %s" % str(r))
	assert_almost(Support.remaining("mochi"), 25.0, 0.01, "25 s cooldown")
	assert_false(m.combat.try_autocast(), "the autocast asks for the SAME skill: still recharging")
	var r2: Dictionary = m.use_skill(false)
	assert_false(bool(r2["ok"]))
	assert_true(String(r2["reason"]).contains("recharging"), String(r2["reason"]))
	assert_eq(String(m.command("skill")["text"]), String(m.combat.skill_check(true)["reason"]), "the panel / command path too")


func test_cooldown_frozen_while_paused() -> void:
	var m := _follower("lumi")
	Game.mode = "playing"
	assert_true(bool(m.use_skill(true)["ok"]))
	var r0 := Support.remaining("lumi")
	await wait_seconds(0.6)
	var r1 := Support.remaining("lumi")
	assert_true(r1 < r0 - 0.3, "recharges while playing (%.2f -> %.2f)" % [r0, r1])
	get_tree().paused = true
	await wait_seconds(0.7)
	var r2 := Support.remaining("lumi")
	get_tree().paused = false
	assert_almost(r2, r1, 0.02, "frozen while paused")


func test_cooldown_survives_save_load_switching_and_new_nodes() -> void:
	var m := _follower("mochi")
	_befriend("pebble")
	var p := _make("pebble", "home", Vector3(-2, 0.05, 8))
	_hurt(50.0)
	assert_true(bool(m.use_skill(true)["ok"]))
	var rem := Support.remaining("mochi")
	# Save / load (JSON round trip like the real save file).
	var d: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(d)
	assert_almost(Support.remaining("mochi"), rem, 0.01, "kept through save/load")
	# Switching pets never refreshes it.
	p.set("_last_command_ms", -100000)
	assert_true(bool(p.command("follow")["ok"]))
	assert_true(bool(p.use_skill(true)["ok"]), "Pebble has its own skill")
	m.set("_last_command_ms", -100000)
	assert_true(bool(m.command("follow")["ok"]))
	assert_false(bool(m.use_skill(true)["ok"]), "Mochi is still recharging after the switch back")
	assert_almost(Support.remaining("mochi"), rem, 0.05)
	# A new node (area change / reload) reads the same record.
	m.queue_free()
	await wait_frames(2)
	var m2 := _make("mochi", "follow", Vector3(1.0, 0.05, 7.0))
	assert_false(bool(m2.use_skill(true)["ok"]), "still recharging on a fresh node")


func test_skill_needs_the_follower_beside_krystal() -> void:
	var m := _follower("mochi")
	_hurt(40.0)
	m.set("_last_command_ms", -100000)
	m.command("wait")
	var r: Dictionary = m.use_skill(true)
	assert_false(bool(r["ok"]))
	assert_true(String(r["reason"]).contains("following"), String(r["reason"]))
	assert_almost(Support.remaining("mochi"), 0.0, 0.001, "a refused request costs nothing")


func test_skill_ready_event_fires_when_recharged() -> void:
	var l := _follower("lumi")
	assert_true(bool(l.use_skill(true)["ok"]))
	var got: Array = []
	var cb := func(id: String) -> void: got.append(id)
	Events.companion_skill_ready.connect(cb)
	GameState.companion("lumi")["skill_ready_at"] = Support.now() - 0.1
	await wait_seconds(0.5)
	Events.companion_skill_ready.disconnect(cb)
	assert_eq(got, ["lumi"], "announced once (the HUD flashes)")


# --- Bond perks ---------------------------------------------------------------------------------------------------------

func test_perks_follow_the_bond_level_including_old_saves() -> void:
	_befriend("mochi")
	_befriend("pebble")
	_befriend("lumi")
	assert_almost(float(Support.signature("mochi")["heal"]), 18.0, 0.001)
	assert_almost(float(Support.table("mochi")["passive"]["heal_received"]), 0.08, 0.0001)
	assert_true(Support.next_perk_text("mochi").begins_with("Next at 2 hearts"), Support.next_perk_text("mochi"))
	# An existing Chapter One bond (xp written straight into the record, as an old save has it).
	GameState.companion("mochi")["bond_xp"] = 25
	assert_almost(float(Support.table("mochi")["passive"]["heal_received"]), 0.1, 0.0001, "2 hearts: 10%")
	assert_true(Support.passive_text("mochi").contains("10%"), Support.passive_text("mochi"))
	GameState.companion("mochi")["bond_xp"] = 45
	assert_eq(int(Support.signature("mochi").get("cleanse_slow", 0)), 1, "3 hearts: cleanse")
	GameState.companion("mochi")["bond_xp"] = 100
	assert_almost(float(Support.signature("mochi")["heal"]), 22.0, 0.001, "5 hearts: heals 22")
	assert_eq(Support.ribbon("mochi"), Support.RIBBON_BOND, "and a bond ribbon")
	assert_eq(Support.next_perk_text("mochi"), "", "every perk unlocked")
	GameState.companion("pebble")["bond_xp"] = 25
	assert_almost(float(Support.signature("pebble")["shield"]), 28.0, 0.001)
	GameState.companion("pebble")["bond_xp"] = 100
	assert_almost(float(Support.signature("pebble")["shield"]), 32.0, 0.001)
	GameState.companion("lumi")["bond_xp"] = 25
	assert_almost(float(Support.table("lumi")["passive"]["move"]), 0.1, 0.0001)
	GameState.companion("lumi")["bond_xp"] = 100
	assert_almost(float(Support.signature("lumi")["duration"]), 6.0, 0.001)


# --- Bloomguard ----------------------------------------------------------------------------------------------------------

func test_bloomguard_heals_exactly_its_total_over_six_seconds() -> void:
	var m := _follower("mochi")
	await wait_physics(2)
	m.set_physics_process(false)             # tick the caster by hand (deterministic)
	player.health.hp = 50.0
	assert_true(bool(m.use_skill(true)["ok"]))
	var ticks := 0
	var at3 := 0.0
	for i in 140:
		m.combat.tick(0.05)
		ticks += 1
		if i == 59:
			at3 = float(player.health.hp)
	assert_true(at3 >= 57.4 and at3 <= 59.1, "about half the heal after 3 s, in 0.5 s ticks (%.2f)" % at3)
	assert_almost(float(player.health.hp), 68.0, 0.001, "18 over 6 s, exactly")
	assert_true(m.combat.hot.is_empty(), "then it ends")
	# Five hearts: 22.
	GameState.companion("mochi")["bond_xp"] = 100
	GameState.companion("mochi")["skill_ready_at"] = 0.0
	player.health.hp = 50.0
	assert_true(bool(m.use_skill(true)["ok"]))
	for i in 140:
		m.combat.tick(0.05)
	assert_almost(float(player.health.hp), 72.0, 0.001, "22 at five hearts")


func test_bloomguard_no_overheal_spam() -> void:
	var m := _follower("mochi")
	var r: Dictionary = m.use_skill(true)
	assert_false(bool(r["ok"]), "nothing to heal at full health")
	assert_eq(String(r["reason"]), "You're not hurt.")
	assert_almost(Support.remaining("mochi"), 0.0, 0.001, "no cooldown spent")
	_hurt(8.0)
	assert_false(m.combat.try_autocast(), "a scratch is not 'meaningfully wounded'")
	_hurt(60.0)
	assert_true(m.combat.try_autocast(), "autocast when Krystal is really hurt")
	assert_false(m.combat.hot.is_empty())
	Settings.set_value("companion_autocast", false)
	GameState.companion("mochi")["skill_ready_at"] = 0.0
	m.combat.hot = {}
	assert_false(m.combat.try_autocast(), "the autocast setting turns it off")


func test_bloomguard_clears_a_slow_at_three_hearts() -> void:
	var m := _follower("mochi")
	_hurt(40.0)
	GameState.add_buff("slow", 0.7, 3.0)
	assert_true(bool(m.use_skill(true)["ok"]))
	assert_true(GameState.buffs.has("slow"), "no cleanse below three hearts")
	GameState.companion("mochi")["bond_xp"] = 45
	GameState.companion("mochi")["skill_ready_at"] = 0.0
	m.combat.hot = {}
	assert_true(bool(m.use_skill(true)["ok"]))
	assert_false(GameState.buffs.has("slow"), "one clinging slow cleared")


# --- Stoneheart -----------------------------------------------------------------------------------------------------------

func test_stoneheart_shields_krystal_and_staggers_ordinary_enemies_only() -> void:
	var p := _follower("pebble")
	var grunt := _enemy(player.global_position + Vector3(1.5, 0, -1.5))
	var boss := _enemy(player.global_position + Vector3(-1.5, 0, -1.5))
	boss.data = {"boss": true}
	var elite := _enemy(player.global_position + Vector3(0, 0, -2.5))
	elite.data = {"elite": true}
	var idle := _enemy(player.global_position + Vector3(0, 0, 2.0), false)
	idle.state = "idle"
	await wait_physics(2)
	p.set("_scan_t", 0.0)
	await wait_physics(2)
	var r: Dictionary = p.use_skill(true)
	assert_true(bool(r["ok"]), str(r))
	var shields: Array = (player as FakePlayer).shields
	assert_eq(shields.size(), 1, "one shield")
	if shields.size() == 1:
		assert_eq(shields[0], [25.0, 6.0, "stoneheart"], "25 points for up to 6 s via add_shield")
	assert_eq(grunt.stuns, [0.8], "an ordinary enemy is briefly staggered")
	assert_eq(boss.stuns, [], "never a boss")
	assert_eq(elite.stuns, [], "never an elite")
	assert_eq(idle.stuns, [], "never a peaceful one")
	assert_almost(Support.remaining("pebble"), 26.0, 0.01)


func test_stoneheart_without_a_shield_api_is_safe() -> void:
	# An older player node: no add_shield on the player, nor on its Health.
	player.queue_free()
	player = _make_player(FakePlayer.new())
	await wait_physics(2)
	var p := _follower("pebble")
	await wait_physics(2)
	assert_true(bool(p.use_skill(true)["ok"]), "cast anyway (the stagger still helps)")
	if not ResourceLoader.exists(PLAYER_HEALTH):
		return
	# Krystal's real Health (player_health.gd) carries the shield.
	var hs: Script = load(PLAYER_HEALTH)
	if hs == null or not hs.can_instantiate():
		return
	var h: Node = hs.new()
	h.name = "PlayerHealth"
	h.max_hp = 100.0
	player.add_child(h)
	player.health = h
	GameState.companion("pebble")["skill_ready_at"] = 0.0
	assert_true(bool(p.use_skill(true)["ok"]))
	assert_almost(float(h.get("shield")), 25.0, 0.001, "the shield lands on Krystal's Health")


# --- Glimmerstep -----------------------------------------------------------------------------------------------------------

func test_glimmerstep_buff_light_pulse_and_perks() -> void:
	var l := _follower("lumi")
	await wait_physics(2)
	l.set_physics_process(false)
	var shadow := ExposeEnemy.new()
	add_child(shadow)
	nodes.append(shadow)
	shadow.global_position = l.global_position + Vector3(3.0, 0, 0)
	var probe: Vector3 = l.global_position + Vector3(4.5, 0.6, 0)
	CombatStatic.invalidate_light_cache()
	var before := CombatStatic.light_at(probe)
	assert_true(bool(l.use_skill(true)["ok"]))
	assert_true(GameState.buffs.has("glimmerstep"), "GameState.add_buff('glimmerstep')")
	assert_almost(float(GameState.buffs["glimmerstep"]["mult"]), 0.12, 0.0001, "+12% move")
	assert_almost(float(GameState.buffs["glimmerstep"]["remaining"]), 4.0, 0.001, "for 4 s")
	assert_false(GameState.buffs.has("sprint_saver"), "the stamina perk needs 3 hearts")
	assert_true(l.combat.pulse_active(), "a light pulse")
	await wait_frames(1)
	CombatStatic.invalidate_light_cache()
	var after := CombatStatic.light_at(probe)
	assert_true(before < 0.4 and after > 0.4, "bright enough to expose a Gloomling 4.5 m away (%.2f -> %.2f)" % [before, after])
	assert_almost(shadow.exposed_for, 3.0, 0.001, "shadow enemies with expose() are told")
	for i in 70:
		l.combat.tick(0.05)
	assert_false(l.combat.pulse_active(), "the pulse fades after its 3 s")
	# Perks: 3 hearts halves sprint stamina meanwhile, 5 hearts lasts 6 s.
	GameState.companion("lumi")["bond_xp"] = 100
	GameState.companion("lumi")["skill_ready_at"] = 0.0
	GameState.buffs.clear()
	assert_true(bool(l.use_skill(true)["ok"]))
	assert_almost(float(GameState.buffs["glimmerstep"]["remaining"]), 6.0, 0.001)
	assert_almost(float(GameState.buffs["sprint_saver"]["mult"]), 0.5, 0.0001)


# --- The Companion Skill action --------------------------------------------------------------------------------------------

func test_skill_key_only_for_the_follower_and_never_through_ui() -> void:
	var l := _follower("lumi")
	_befriend("pebble")
	var p := _make("pebble", "home", Vector3(-2, 0.05, 8))
	Game.mode = "playing"
	var ev := InputEventAction.new()
	ev.action = "companion_skill"
	ev.pressed = true
	Game.push_ui("test_panel")
	l._unhandled_input(ev)
	assert_almost(Support.remaining("lumi"), 0.0, 0.001, "a menu is open: the key does nothing")
	Game.pop_ui("test_panel")
	p._unhandled_input(ev)
	assert_almost(Support.remaining("pebble"), 0.0, 0.001, "only the follower answers")
	l._unhandled_input(ev)
	assert_almost(Support.remaining("lumi"), 24.0, 0.05, "the follower casts Glimmerstep")
	var up := InputEventAction.new()
	up.action = "companion_skill"
	up.pressed = false
	GameState.companion("lumi")["skill_ready_at"] = 0.0
	l._unhandled_input(up)
	assert_almost(Support.remaining("lumi"), 0.0, 0.001, "releasing the key does nothing")


# --- Five-heart affection -------------------------------------------------------------------------------------------------

func test_five_hearts_pet_plays_the_affectionate_animation() -> void:
	var p := _follower("pebble")
	await wait_physics(2)
	p.command("pet")
	assert_ne(String(p.visual.get_action()), "pebble_hug", "below five hearts: the usual happy reaction")
	GameState.companion("pebble")["bond_xp"] = 100
	GameState.companion("pebble")["last_pet_day"] = -1
	p.visual.stop_action()
	said.clear()
	var r: Dictionary = p.command("pet")
	assert_true(bool(r["ok"]))
	assert_eq(String(p.visual.get_action()), "pebble_hug", "the 5-heart perk's special animation")
	assert_true(_said_contains("boot"), "with its affectionate line: %s" % str(said))
