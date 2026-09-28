extends "res://tests/unit/test_companions_fixture.gd"
## Companion basic attacks (MP §6.1/6.2, spec §9): each friend damages an enemy Krystal fights with its own
## attack and numbers, on the animation's impact frame, at its interval; never through a wall, never a
## peaceful / invulnerable / refusing / stalker target, no bond from dummies or blocked hits; the auto-attack
## setting and the Stay close mode are honoured; a real Brambling from the enemy factory takes the hits.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const EnemyBase := preload("res://src/enemies/enemy_base.gd")
const Projectile := preload("res://src/combat/projectile.gd")
const Fx := preload("res://src/companions/companion_fx.gd")


func _hp(e: Node) -> float:
	return float(e.health.hp)


func _first_hit(e: Node, hp0: float, seconds: float) -> bool:
	return await _wait_until(func() -> bool: return float(e.health.hp) < hp0, seconds)


## Instance ids of the live stone-chip bursts (companion_fx.gd chips: one-shot CPUParticles3D with the shared
## chip mesh) anywhere in the tree.
func _chip_bursts() -> Dictionary:
	var mesh: Mesh = Fx._box(0.07)
	var ids := {}
	for node in get_tree().root.find_children("*", "CPUParticles3D", true, false):
		if (node as CPUParticles3D).mesh == mesh and not node.is_queued_for_deletion():
			ids[node.get_instance_id()] = true
	return ids


## Bursts alive now that were not in `before` (bursts left over from earlier tests may vanish meanwhile).
func _new_chip_bursts(before: Dictionary) -> int:
	var n := 0
	for k in _chip_bursts():
		if not before.has(k):
			n += 1
	return n


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


## Integration R62: one bump, one burst of stone chips. The visual's impact frame (pebble_visual.gd) throws them;
## the combat layer no longer adds a second burst at the target on the same frame.
func test_pebble_bump_throws_one_burst_of_chips() -> void:
	var p := _follower("pebble")
	p.set("_charge_cd", 999.0)          # only the basic attack here (the brave opener has its own single burst)
	var before := _chip_bursts()
	var bursts: Array = []
	# Connected after the companion's own handler: runs once the hit of this impact frame was resolved.
	p.visual.action_event.connect(func(a: String) -> void:
		if a == "stone_bump":
			bursts.append(_new_chip_bursts(before)))
	var e := _enemy(player.global_position + Vector3(0.0, 0.0, -3.5))
	var hp0 := _hp(e)
	assert_true(await _first_hit(e, hp0, 6.0), "Pebble bumps the enemy")
	assert_false(bursts.is_empty(), "the bump animation played")
	if not bursts.is_empty():
		assert_eq(int(bursts[0]), 1, "exactly one burst of stone chips per bump")


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


## Integration R60: a companion shot can only land on its target (projectile "only_target"): a peaceful enemy
## standing right in the line of fire is passed through, never clipped and never woken.
func test_shot_passes_a_peaceful_enemy_in_the_way() -> void:
	var l := _follower("lumi")
	var e := _enemy(player.global_position + Vector3(-0.5, 0.0, -4.0))
	var peaceful := _enemy(Vector3(20, 0.05, 20), false)
	peaceful.state = "idle"
	l.set_physics_process(false)        # hold Lumi still: the shot is fired by hand below
	await wait_physics(1)
	var from: Vector3 = l.combat.attack_origin()
	var to: Vector3 = l.combat.aim_point(e)
	var mid := from.lerp(to, 0.5)
	# Its aim point exactly on the flight line, half-way.
	peaceful.global_position = mid - (l.combat.aim_point(peaceful) - peaceful.global_position)
	Projectile.invalidate_targets()
	l.combat.call("_shoot", e)
	assert_true(await _first_hit(e, 60.0, 3.0), "the bolt reaches the enemy Krystal is fighting")
	assert_almost(_hp(e), 54.0, 0.001, "Light Bolt: 6 damage")
	assert_almost(_hp(peaceful), 60.0, 0.001, "the peaceful enemy in the way is untouched")
	assert_eq(peaceful.blocked, 0, "not even a blocked hit")
	assert_eq(int(GameState.companion("lumi")["bond_xp"]), 1, "bond from the real hit only")
	# Control: an unrestricted (harmless) shot along the same line does meet the peaceful enemy first.
	var met: Array = []
	var record := func(t: Node, _d: float) -> void:
		met.append(t)
	var p: Node3D = Projectile.fire({"shooter": l, "from": from, "target": e, "damage": 0.0, "groups": ["enemy"],
		"impact_fx": false, "on_hit": record})
	assert_not_null(p)
	await _wait_until(func() -> bool: return not met.is_empty(), 3.0)
	assert_eq(met.size(), 1)
	if not met.is_empty():
		assert_eq(met[0], peaceful, "the peaceful enemy really stands in the line of fire")


## Integration R61: boss hazards (meta "boss_hazard": the Matron's trip-lines and egg sacs are in group "enemy")
## are never noticed (Lumi), feared (Mochi), charged (Pebble) or targeted - even one claiming to threaten.
func test_boss_hazards_are_never_noticed_feared_charged_or_targeted() -> void:
	_befriend("mochi")
	_befriend("pebble")
	var l := _follower("lumi")
	var m := _make("mochi", "follow", Vector3(-1.2, 0.05, 6.8))
	var pb := _make("pebble", "follow", Vector3(0.0, 0.05, 7.4))
	pb.set("_charge_cd", 0.0)
	var hz := _enemy(player.global_position + Vector3(0.5, 0.0, -2.5))    # threatening = true: the worst case
	hz.set_meta("boss_hazard", true)
	CompanionScript._enemy_cache_ms = -100000     # re-read the shared enemy list now
	var seen: Array = []
	var t := 0.0
	while t < 2.5:
		for c in [l, m, pb]:
			var o := String(c.get("override"))
			if o in ["notice", "afraid", "charge", "attack"] and not seen.has(o):
				seen.append(o)
		await wait_physics(1)
		t += 1.0 / float(Engine.physics_ticks_per_second)
	assert_eq(seen, [], "no glance, no hiding, no charge, no attack at a boss hazard")
	assert_almost(_hp(hz), 60.0, 0.001, "never hit")
	assert_null(l.combat.target)
	assert_false(l.call("_enemies").has(hz), "left out of the shared enemy list")
	assert_false(l.combat.can_target(hz), "never a target")
	assert_false(l.get("_noticed").has(hz.get_instance_id()), "Lumi never noticed it")
	# Control: the same node without the meta is an ordinary enemy again.
	hz.remove_meta("boss_hazard")
	CompanionScript._enemy_cache_ms = -100000
	assert_true(await _wait_until(func() -> bool: return String(m.get("override")) == "afraid", 2.0), "Mochi hides from a real one")
	assert_true(bool(l.get("_noticed").has(hz.get_instance_id())), "Lumi glances at a real one")


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
