extends "res://tests/unit/test_companions_fixture.gd"
## Integration pass 2 (lead rule L01 + D04): a REAL Lumi (companion.gd, follower) and a real Glimmerstep cast
## (companion_combat.gd) against the Chapter Two light-fearing enemies.
##  * Lumi's passive glow beside Krystal never breaks a Velvet Wing's drain (a companion is not ward-light);
##  * the Glimmerstep light pulse ("GlimmerPulse") does - even for a wing outside the pulse radius (its light
##    reaches Krystal), and at once through expose(seconds) for a wing inside it;
##  * a veiled Borrowed Wisp inside the pulse is revealed at once (expose = a forced lantern-like reveal).
## Uses the companions fixture (floor, a fake Krystal = Game.player, companion helpers); manual enemy ticks.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Wing := preload("res://src/enemies/velvet_wing.gd")

const DT := 1.0 / 60.0


func _lumi() -> Node3D:
	var l := _follower("lumi")
	await wait_physics(2)
	l.set_physics_process(false)          # no auto-attacks / glow changes while the enemies are ticked by hand
	return l


func _enemy_at(id: String, pos: Vector3, params: Dictionary = {}) -> Node:
	Base.reset_attack_tokens()
	var p := {"home": pos, "no_drops": true}
	p.merge(params, true)
	var e: Node = Factory.create(id, p)
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = player
	nodes.append(e)
	return e


func _until(e: Node, s: String, max_t: float) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		t += DT
	return t


func _cast(l: Node3D) -> void:
	GameState.companion("lumi")["skill_ready_at"] = 0.0
	var r: Dictionary = l.use_skill(true)
	assert_true(bool(r.get("ok", false)), "Glimmerstep cast: %s" % str(r))


func test_lumis_glow_never_breaks_a_drain_but_her_glimmerstep_pulse_does() -> void:
	var l: Node3D = await _lumi()
	assert_true(l.is_in_group("light_source") and l.is_in_group("companion"), "Lumi is a companion light source")
	if not bool(l.call("is_light_active")):
		l.set("_glow_target", 1.0)
	assert_true(bool(l.call("is_light_active")), "Lumi glows beside Krystal")
	# The wing hangs 7.8 m from Krystal but 8.9 m from Lumi: outside the 6 m pulse (no expose() call).
	var e := _enemy_at("velvet_wing", Vector3(-2.0, 0.05, -1.5))
	var at_her: Vector3 = player.global_position + Vector3.UP * 0.9
	assert_almost(float(e.ward_light_at(at_her)), 0.0, 0.001, "Lumi's passive glow is not ward-light")
	e.next_attack = "drain"
	_until(e, "drain", 6.0)
	assert_eq(e.state, "drain", "the drain channel starts with Lumi glowing beside her")
	_until(e, "recover", 3.0)
	assert_eq(String(e.last_break_reason), "", "Lumi's glow never broke it")
	assert_eq(int(e.drains_completed), 1)
	assert_true(float(player.health.hp) < 100.0, "the drain landed")
	# Next drain: Lumi casts Glimmerstep mid-channel. Its pulse light at Krystal breaks the link.
	e.set("_drain_cd", 0.0)
	Base.reset_attack_tokens()
	e.next_attack = "drain"
	_until(e, "drain", 8.0)
	assert_eq(e.state, "drain")
	assert_true((e as Node3D).global_position.distance_to(l.global_position) > 6.0, "outside the pulse radius")
	_cast(l)
	assert_true(bool(l.combat.pulse_active()), "the Glimmerstep pulse is lit")
	assert_true(float(e.ward_light_at(at_her)) >= Wing.WARD_LIGHT, "the pulse is ward-light at Krystal")
	var hp: float = player.health.hp
	_until(e, "recover", 1.0)
	assert_eq(String(e.last_break_reason), "light", "the Glimmerstep pulse breaks the drain")
	assert_almost(float(player.health.hp), hp, 0.001, "nothing drained")


func test_glimmerstep_exposes_a_draining_wing_and_a_veiled_wisp_at_once() -> void:
	var l: Node3D = await _lumi()
	# Both within Lumi's 6 m pulse radius (Lumi stands at (1.2, 0, 6.8)).
	var wing := _enemy_at("velvet_wing", Vector3(1.2, 0.05, 1.5))
	wing.ward_light_override = 0.0         # only expose() may break it here
	wing.next_attack = "drain"
	_until(wing, "telegraph", 6.0)
	assert_eq(String(wing.attack_kind), "drain")
	var wisp := _enemy_at("borrowed_wisp", Vector3(-2.5, 0.05, 2.6), {"no_drops": true})
	wisp.light_override = 0.0              # dark: only expose() may reveal it here
	for i in 30:
		wisp.tick(DT)
	assert_false(bool(wisp.revealed), "the wisp is veiled")
	assert_true(wisp.global_position.distance_to(l.global_position) <= 6.0, "inside the pulse")
	_cast(l)
	assert_eq(wing.state, "recover", "expose(): the drain wind-up broke at once")
	assert_eq(String(wing.last_break_reason), "light")
	assert_true(bool(wisp.revealed), "expose(): the wisp's true form shows at once")
	assert_true(bool(wisp.can_be_hit_by(player)), "and it can be hurt")
	assert_eq(wisp.state, "stunned", "dazzled, like a lantern reveal")
	for i in int(2.5 / DT):
		wisp.tick(DT)
	assert_true(bool(wisp.revealed), "still revealed while the exposure lasts, even in the dark")
