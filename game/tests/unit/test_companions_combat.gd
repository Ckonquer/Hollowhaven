extends "res://tests/unit/test_companions_fixture.gd"
## Companion basic attacks (MP §6.1/6.2, spec §9): each friend damages an enemy Krystal fights with its own
## attack and numbers, on the animation's impact frame, at its interval; never through a wall, never a
## peaceful / invulnerable / refusing / stalker target, no bond from dummies or blocked hits; the auto-attack
## setting and the Stay close mode are honoured; a real Brambling from the enemy factory takes the hits.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const EnemyBase := preload("res://src/enemies/enemy_base.gd")


func _hp(e: Node) -> float:
	return float(e.health.hp)


func _first_hit(e: Node, hp0: float, seconds: float) -> bool:
	return await _wait_until(func() -> bool: return float(e.health.hp) < hp0, seconds)


# --- Damage per companion -----------------------------------------------------------------------------------------

func test_mochi_spore_puff_hits_on_its_impact_frame() -> void:
	var m := _follower("mochi")
	var fired: Array = []
	m.visual.action_event.connect(func(a: String) -> void:
		if a == "spore_puff":
			fired.append(Time.get_ticks_msec()))
	var e := _enemy(player.global_position + Vector3(0.5, 0.0, -3.0))
	var hp0 := _hp(e)
	assert_true(await _first_hit(e, hp0, 6.0), "Mochi's spores reach the enemy Krystal is fighting")
	assert_almost(hp0 - _hp(e), 4.0, 0.001, "Spore Puff: 4 damage (stone tier)")
	assert_false(fired.is_empty(), "the puff animation played")
	if not fired.is_empty():
		var dt := int(e.damage_times[0]) - int(fired[0])
		assert_true(dt >= 0 and dt < 1500, "damage lands after the impact frame, after a short flight (%d ms)" % dt)
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 1, "+1 bond for working together")
	# The next puff follows the ~2.4 s cadence.
	assert_true(await _wait_until(func() -> bool: return e.damage_times.size() >= 2, 4.0), "a second puff")
	if e.damage_times.size() >= 2:
		var gap := (int(e.damage_times[1]) - int(e.damage_times[0])) / 1000.0
		assert_true(absf(gap - 2.4) < 0.35, "about every 2.4 s (%.2f s)" % gap)


func test_pebble_headbutt_lands_on_the_bump_frame() -> void:
	var p := _follower("pebble")
	var fired: Array = []
	p.visual.action_event.connect(func(a: String) -> void:
		if a == "stone_bump":
			fired.append(Time.get_ticks_msec()))
	var e := _enemy(player.global_position + Vector3(0.0, 0.0, -3.5))
	var hp0 := _hp(e)
	assert_true(await _first_hit(e, hp0, 6.0), "Pebble walks over and bumps the enemy")
	assert_almost(hp0 - _hp(e), 8.0, 0.001, "Stone Bump: 8 damage")
	assert_false(fired.is_empty(), "the headbutt animation played")
	if not fired.is_empty():
		assert_true(absi(int(e.damage_times[0]) - int(fired[0])) <= 20, "the hit happens on the bump frame")
	var d: float = p.global_position.distance_to(e.global_position)
	assert_true(d < 2.4, "Pebble is right at the enemy (%.2f m)" % d)
	assert_true(await _wait_until(func() -> bool: return e.damage_times.size() >= 2, 4.0), "a second bump")
	if e.damage_times.size() >= 2:
		var gap := (int(e.damage_times[1]) - int(e.damage_times[0])) / 1000.0
		assert_true(absf(gap - 2.4) < 0.35, "about every 2.4 s (%.2f s)" % gap)


func test_lumi_light_bolt_and_gear_tier_bonus() -> void:
	GameState.give_item("copper_sword", 1)          # tier 2: x1.1 (stable, never the held tool)
	var l := _follower("lumi")
	var e := _enemy(player.global_position + Vector3(-0.5, 0.0, -4.0))
	var hp0 := _hp(e)
	assert_true(await _first_hit(e, hp0, 6.0), "Lumi's light bolt reaches the enemy")
	assert_almost(hp0 - _hp(e), 6.6, 0.001, "Light Bolt: 6 x 1.1 with a copper sword owned")
	assert_true(await _wait_until(func() -> bool: return e.damage_times.size() >= 2, 4.0), "a second bolt")
	if e.damage_times.size() >= 2:
		var gap := (int(e.damage_times[1]) - int(e.damage_times[0])) / 1000.0
		assert_true(absf(gap - 2.2) < 0.35, "about every 2.2 s (%.2f s)" % gap)
	assert_true(l.combat.attacks_fired >= 2)


func test_a_real_brambling_from_the_factory_takes_the_hits() -> void:
	EnemyBase.reset_attack_tokens()
	var l := _follower("lumi")
	var b: Node = Factory.create("brambling", {"home": player.global_position + Vector3(0, 0, -4), "no_drops": true})
	add_child(b)
	nodes.append(b)
	(b as Node3D).global_position = player.global_position + Vector3(0, 0, -4)
	b.set_physics_process(false)
	b.set("target_override", player)
	b.call("_enter", "chase")
	assert_true(bool(b.is_threatening()), "the Brambling is fighting Krystal")
	var hp0 := float(b.health.hp)
	assert_true(await _wait_until(func() -> bool: return float(b.health.hp) < hp0, 6.0), "Lumi hits the Brambling")
	assert_almost(hp0 - float(b.health.hp), 6.0, 0.001)
	assert_eq(l.combat.target, b)
	EnemyBase.reset_attack_tokens()


# --- Never ------------------------------------------------------------------------------------------------------------

func test_no_attack_through_a_wall() -> void:
	var m := _follower("mochi")
	var e := _enemy(player.global_position + Vector3(0.0, 0.0, -4.0))
	_wall(player.global_position + Vector3(0, 0, -2.0), 14.0)
	var hp0 := _hp(e)
	await wait_seconds(4.0)
	assert_almost(_hp(e), hp0, 0.001, "no spores through the wall")
	assert_null(m.combat.target, "nothing targeted behind it")


func test_never_invulnerable_refusing_peaceful_or_stalker_targets() -> void:
	var l := _follower("lumi")
	var armoured := _enemy(player.global_position + Vector3(-2.0, 0.0, -3.0))
	armoured.health.invulnerable = true
	armoured.data = {"boss": true}
	var refusing := _enemy(player.global_position + Vector3(2.0, 0.0, -3.0))
	refusing.refuse = true
	var peaceful := _enemy(player.global_position + Vector3(0.0, 0.0, -4.0), false)
	peaceful.state = "idle"
	var stalker := _enemy(player.global_position + Vector3(0.0, 0.0, -2.0))
	stalker.add_to_group("stalker")
	await wait_seconds(4.0)
	for e in [armoured, refusing, peaceful, stalker]:
		assert_almost(_hp(e), 60.0, 0.001, "never hit")
	assert_null(l.combat.target)
	assert_eq(int(GameState.companion("lumi")["bond_xp"]), 0, "no bond from anything it could not hurt")
	assert_false(l.combat.can_target(armoured), "an armoured boss is not a target")
	assert_false(l.combat.can_target(stalker), "the stalker is never a target")


func test_no_bond_from_dummies_or_blocked_hits() -> void:
	var m := _follower("mochi")
	var dummy := _enemy(player.global_position + Vector3(0, 0, -2.0))
	dummy.add_to_group("practice_dummy")
	var dealt: float = m.combat.deliver(dummy, 4.0, Vector3.FORWARD, 0.0)
	assert_almost(dealt, 4.0, 0.001, "the dummy shows the hit")
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 0, "but gives no bond")
	var armoured := _enemy(player.global_position + Vector3(1, 0, -2.0))
	armoured.health.invulnerable = true
	assert_almost(float(m.combat.deliver(armoured, 4.0, Vector3.FORWARD, 0.0)), 0.0, 0.001)
	assert_eq(armoured.blocked, 1, "a blocked hit uses on_hit_blocked")
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 0)


func test_auto_attack_setting_off_keeps_support_only() -> void:
	Settings.set_value("companion_auto_attack", false)
	var l := _follower("lumi")
	var e := _enemy(player.global_position + Vector3(0, 0, -3.0))
	await wait_seconds(3.5)
	assert_almost(_hp(e), 60.0, 0.001, "no attacks with the setting off")
	var r: Dictionary = l.use_skill(true)
	assert_true(bool(r["ok"]), "the signature skill still works: %s" % str(r))


func test_stay_close_does_not_chase() -> void:
	var p := _follower("pebble")
	assert_true(bool(p.command("close")["ok"]))
	assert_eq(Support.mode("pebble"), "close", "saved in the record")
	var far := _enemy(player.global_position + Vector3(0, 0, -7.0))
	await wait_seconds(3.0)
	assert_almost(_hp(far), 60.0, 0.001, "an enemy 7 m out is left alone")
	assert_true(p.global_position.distance_to(player.global_position) < 3.5, "Pebble stays by Krystal")
	assert_ne(p.get_state(), "attack")
	var near := _enemy(player.global_position + Vector3(0.9, 0, -1.2))
	var hp0 := _hp(near)
	assert_true(await _first_hit(near, hp0, 5.0), "an enemy right at Krystal still gets bumped")


func test_pebble_charge_obeys_the_combat_rules() -> void:
	# The legacy brave opener (2 damage, then dizzy) never targets an armoured enemy.
	var p := _follower("pebble")
	var e := _enemy(player.global_position + Vector3(0, 0, -2.5))
	e.health.invulnerable = true
	p.set("_charge_cd", 0.0)
	await wait_seconds(1.5)
	assert_ne(p.get_state(), "charge", "no charge at an invulnerable enemy")
	assert_almost(_hp(e), 60.0, 0.001)


## Budget: three companions (one fighting follower, two at home) with eight enemies around stay cheap per
## physics frame (throttled scans, cached tables, no per-frame group scans).
func test_combat_layer_stays_cheap_per_frame() -> void:
	var p := _follower("pebble")
	_befriend("mochi")
	_befriend("lumi")
	var m := _make("mochi", "home", Vector3(-3, 0.05, 10))
	var l := _make("lumi", "home", Vector3(3, 0.05, 10))
	for i in 8:
		_enemy(player.global_position + Vector3(-6.0 + 1.6 * float(i), 0.0, -3.0 - float(i % 3)))
	await wait_seconds(1.0)
	for c in [p, m, l]:
		(c as Node).set_physics_process(false)
	var dt := 1.0 / 60.0
	var t0 := Time.get_ticks_usec()
	for f in 180:
		for c in [p, m, l]:
			c._physics_process(dt)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 180.0 / 1000.0
	print("    companions: %.3f ms per physics frame for 3 companions + 8 enemies" % per_frame_ms)
	assert_true(per_frame_ms < 2.0, "cheap enough (%.3f ms per frame)" % per_frame_ms)
