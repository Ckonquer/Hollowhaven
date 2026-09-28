extends "res://tests/test_case.gd"
## Borrowed Wisp (module C5): its light lights nothing (no Light3D, not a light source, Combat.light_at unchanged);
## veiled, every hit passes through (blocked, with the one-time hint) and it floats out of reach; real light (a raised
## lantern / a lamp) reveals a REACHABLE, vulnerable target and dazzles it first (a wind-up in progress is cancelled);
## it veils again once the light is gone; the sweep is marked and DELAYED (nothing lands before telegraph + delay,
## stepping out of the locked wedge avoids it); one body only - never clones; underground damage scaling.
## Integration pass 2: a dazzle at most once per DAZZLE_COOLDOWN (lantern toggling never stun-locks it, P08), Lumi's
## Glimmerstep expose(seconds) = a forced lantern-like reveal (D04), and the "raise your lantern" hint once when
## Krystal comes close to a veiled wisp that threatens her (P10).

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Wisp := preload("res://src/enemies/borrowed_wisp.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null


class Dummy extends CharacterBody3D:
	var health: Node
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


class Lamp extends Node3D:
	var light_radius: float = 6.0

	func is_light_active() -> bool:
		return true


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	_saved_area = Game.area
	Game.area = null
	Combat.invalidate_light_cache()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	Game.area = _saved_area
	Combat.invalidate_light_cache()
	await wait_frames(2)


func _dummy(pos: Vector3, group: String = "player") -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group(group)
	_nodes.append(d)
	return d


func _wisp(target: Node3D, pos: Vector3 = Vector3.ZERO, light: float = 0.0) -> Node:
	var e: Node = Factory.create("borrowed_wisp", {"home": pos, "no_drops": true})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	e.light_override = light
	_nodes.append(e)
	return e


func _until(e: Node, s: String, max_t: float = 10.0) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		t += DT
	return t


func _run(e: Node, seconds: float) -> void:
	for i in int(seconds / DT):
		e.tick(DT)


func _reachable(e: Node, d: Node3D) -> bool:
	var aim: Vector3 = e.get_aim_point()
	return absf(aim.y - (d.global_position.y + 0.9)) <= Combat.MAX_VERTICAL_REACH


static func _lights(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _lights(ch)
	return c


func test_its_light_lights_nothing() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _wisp(d, Vector3(40, 0, 40), -1.0)
	assert_eq(_lights(e), 0, "no Light3D anywhere in the wisp")
	assert_false(e.is_in_group("light_source"), "not a light source")
	Combat.invalidate_light_cache()
	assert_almost(Combat.light_at(Vector3(40, 1.0, 40.5)), 0.0, 0.001, "the ground beside its glow stays dark")
	_run(e, 0.5)
	assert_false(bool(e.revealed), "its own glow never reveals it")


func test_veiled_hits_pass_through_and_it_floats_out_of_reach() -> void:
	var d := _dummy(Vector3(0, 0, -1.4))
	var e := _wisp(d)
	_run(e, 1.0)
	assert_false(bool(e.revealed), "veiled in the dark")
	assert_false(_reachable(e, d), "floats out of sword reach")
	assert_false(bool(e.can_be_hit_by(d)), "cannot be hit")
	var hp0: float = e.health.hp
	var got: float = e.health.apply_damage(20.0, d, Vector3.FORWARD)
	assert_almost(got, 0.0, 0.001, "damage passes straight through")
	assert_almost(float(e.health.hp), hp0, 0.001)
	var hints: Array = []
	var cb := func(id: String, _t: String) -> void: hints.append(id)
	Events.hint.connect(cb)
	var m := Combat.melee(d, d.global_position + Vector3.UP * 0.9, Vector3(0, 0, 1), 3.5, 360.0, 18.0, ["enemy"], 0.0)
	Events.hint.disconnect(cb)
	assert_eq(m.size(), 0, "a swing never lands on the false light")
	# (the aim point is out of the vertical reach; test the blocked feedback directly too)
	e.on_hit_blocked(d, Vector3.FORWARD)
	assert_true(int(e.blocked_hits) >= 1, "blocked feedback")


func test_lantern_light_reveals_a_reachable_target_first() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _wisp(d)
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph", "it can wind up while veiled")
	e.light_override = 0.8                        # she raises her lantern
	_run(e, 0.25)
	assert_true(bool(e.revealed), "lantern light reveals it")
	assert_eq(e.state, "stunned", "dazzled: the wind-up is cancelled")
	assert_false(bool(e.mark().is_showing()), "its mark goes away")
	assert_eq(int(e.reveals), 1)
	_run(e, 0.6)
	assert_true(_reachable(e, d), "the true form drops within reach")
	assert_true(bool(e.can_be_hit_by(d)), "and can be hit")
	var hits := Combat.melee(d, d.global_position + Vector3.UP * 0.9, Vector3(0, 0, 1), 3.0, 110.0, 18.0, ["enemy"], 0.0)
	assert_eq(hits.size(), 1, "her swing connects")
	assert_almost(float(e.health.hp), 65.0 - 18.0, 0.001, "full damage")
	assert_almost(float(d.health.hp), 100.0, 0.001, "no sweep came out of the dazzle")


func test_a_lamp_reveals_it_through_real_light() -> void:
	var d := _dummy(Vector3(0, 0, -8))
	var e := _wisp(d, Vector3.ZERO, -1.0)
	_run(e, 0.5)
	assert_false(bool(e.revealed))
	var lamp := Lamp.new()
	add_child(lamp)
	lamp.add_to_group("light_source")
	lamp.global_position = Vector3(1.0, 1.0, 0.0)
	_nodes.append(lamp)
	Combat.invalidate_light_cache()
	_run(e, 0.5)
	assert_true(bool(e.revealed), "a real light source reveals it")


func test_veils_again_when_the_light_leaves() -> void:
	var d := _dummy(Vector3(0, 0, -8))
	var e := _wisp(d, Vector3.ZERO, 0.8)
	_run(e, 0.5)
	assert_true(bool(e.revealed))
	e.light_override = 0.0
	_run(e, Wisp.REVEAL_HOLD - 0.5)
	assert_true(bool(e.revealed), "lingers a moment after the light moves away")
	_run(e, 1.0)
	assert_false(bool(e.revealed), "veiled again")
	assert_true(bool(e.health.invulnerable), "and untouchable again")


func test_sweep_is_marked_and_delayed() -> void:
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _wisp(d)
	_until(e, "telegraph", 4.0)
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "arc", "a wedge marks the sweep")
	assert_almost(float(m.footprint()["radius"]), float(e.sweep_reach()), 0.001, "marked reach = hit reach")
	assert_almost(float(m.footprint()["arc_deg"]), 120.0, 0.001, "data arc 120")
	var tele := _until(e, "sweep_wait", 3.0)
	assert_almost(tele, 1.4, DT * 2.0, "wind-up = data 1.4 s")
	assert_true(bool(m.footprint()["locked"]), "locked")
	assert_true(bool(m.is_showing()), "the mark stays through the delay")
	var wait := _until(e, "sweep", 2.0)
	assert_almost(wait, 0.8, DT * 2.0, "then a delay (data 0.8 s)")
	assert_almost(float(d.health.hp), 100.0, 0.001, "nothing lands before the delay is over")
	_until(e, "recover", 1.0)
	assert_eq(d.damaged_count, 1, "one sweep hit")
	assert_almost(float(d.health.hp), 84.0, 0.001, "data damage 16 (Standard)")


func test_stepping_out_of_the_locked_wedge_avoids_the_sweep() -> void:
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _wisp(d)
	_until(e, "sweep_wait", 5.0)
	d.global_position = Vector3(0, 0, 3.0)        # behind it, out of the 120 degree wedge
	_until(e, "recover", 2.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "outside the marked wedge: safe")


func test_one_body_never_clones() -> void:
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _wisp(d)
	var before := get_tree().get_nodes_in_group("enemy").size()
	for cycle in 4:
		_until(e, "recover", 8.0)
		_until(e, "chase", 4.0)
	e.light_override = 0.9
	_run(e, 2.0)
	assert_eq(get_tree().get_nodes_in_group("enemy").size(), before, "never spawns copies or decoys")
	assert_eq((e as Node).get_parent().get_children().filter(func(n: Node) -> bool: return n.get_script() == Wisp).size(), 1, "exactly one wisp")


func test_underground_damage_follows_intensity() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _wisp(d)
	var def: Dictionary = e.attack_def("sweep")
	Settings.set_value("horror_intensity", 0)
	assert_almost(float(e.attack_damage_for(def)), 16.0 * 0.6, 0.001, "Gentle 0.6")
	Settings.set_value("horror_intensity", 2)
	assert_almost(float(e.attack_damage_for(def)), 16.0 * 1.15, 0.001, "Intense 1.15")


# --- Integration pass 2 ----------------------------------------------------------------------------------------------

## P08: toggling the lantern re-reveals it (reachable, vulnerable) but only the first reveal in DAZZLE_COOLDOWN
## dazzles; a wind-up in progress then carries on. After the cooldown a reveal dazzles again.
func test_lantern_toggling_cannot_stun_lock_it() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _wisp(d)
	_until(e, "telegraph", 4.0)
	e.light_override = 0.8                        # she raises her lantern
	_run(e, 0.25)
	assert_eq(e.state, "stunned", "the first reveal dazzles")
	assert_eq(int(e.dazzles), 1)
	e.light_override = 0.0                        # ... lowers it
	assert_true(_until(e, "telegraph", 3.0) < 3.0, "it shakes off the dazzle and winds up again")
	e._apply_reveal(false)                        # (the dark long enough to veil it again)
	assert_false(bool(e.revealed))
	e.light_override = 0.8                        # ... and raises it again, well inside the cooldown
	_run(e, 0.25)
	assert_true(bool(e.revealed), "a reveal inside the cooldown still reveals it")
	assert_eq(int(e.reveals), 2)
	assert_eq(int(e.dazzles), 1, "but does not dazzle again")
	assert_eq(e.state, "telegraph", "the wind-up is not cancelled (no stun-lock)")
	assert_true(bool(e.mark().is_showing()), "its mark stays up")
	_run(e, 0.3)
	assert_true(bool(e.can_be_hit_by(d)), "vulnerable")
	assert_true(_reachable(e, d), "and within reach")
	e.light_override = 0.0
	_run(e, Wisp.DAZZLE_COOLDOWN)                 # the cooldown runs out (it sweeps / rests meanwhile)
	_until(e, "recover", 8.0)
	assert_true(_until(e, "telegraph", 8.0) < 8.0, "a fresh wind-up")
	e._apply_reveal(false)
	e.light_override = 0.8
	_run(e, 0.25)
	assert_eq(e.state, "stunned", "after the cooldown a reveal dazzles again")
	assert_eq(int(e.dazzles), 2)


## D04: Glimmerstep's expose(seconds) is a forced reveal exactly like a lantern reveal - revealed at once, dazzled,
## dropping within reach and vulnerable - that holds for `seconds` even in the dark, then the usual veil rule.
func test_glimmerstep_expose_is_a_forced_reveal() -> void:
	var d := _dummy(Vector3(0, 0, -8))
	var e := _wisp(d)
	_run(e, 0.5)
	assert_false(bool(e.revealed), "veiled in the dark")
	e.expose(3.0)
	assert_true(bool(e.revealed), "revealed at once")
	assert_eq(int(e.reveals), 1)
	assert_eq(e.state, "stunned", "dazzled like a lantern reveal")
	assert_true(bool(e.can_be_hit_by(d)), "vulnerable")
	_run(e, 0.6)
	assert_true(_reachable(e, d), "the true form drops within reach")
	_run(e, 2.0)
	assert_true(bool(e.revealed), "still revealed while the exposure lasts (no light at all)")
	_run(e, 1.0 + Wisp.REVEAL_HOLD + 0.6)
	assert_false(bool(e.revealed), "then the usual rule veils it again")
	assert_true(bool(e.health.invulnerable))
	# Inside the dazzle cooldown a second expose reveals it without a second dazzle.
	var e2 := _wisp(d, Vector3(6, 0, 0))
	e2.expose(3.0)
	assert_eq(e2.state, "stunned")
	e2._apply_reveal(false)
	_run(e2, 1.2)
	e2.expose(3.0)
	assert_true(bool(e2.revealed))
	assert_eq(int(e2.dazzles), 1, "never dazzled twice within DAZZLE_COOLDOWN")
	assert_ne(e2.state, "stunned")


## P10: a veiled wisp floats above sword reach (a swing gives no contact), so the "raise your lantern" hint shows
## the first time Krystal comes within BLOCKED_HINT_DIST of a veiled, visible wisp that threatens her - once.
func test_a_veiled_wisp_close_by_teaches_the_lantern_once() -> void:
	var hints: Array = []
	var cb := func(id: String, text: String) -> void:
		if id == Wisp.HINT_BLOCKED:
			hints.append(text)
	Events.hint.connect(cb)
	var d := _dummy(Vector3(0, 0, -8))
	var e := _wisp(d)
	_run(e, 1.0)
	assert_true(bool(e.is_threatening()), "it hunts her")
	assert_eq(hints.size(), 0, "8 m away: no hint yet")
	d.global_position = Vector3(0, 0, -3.5)
	_run(e, 0.5)
	assert_eq(hints.size(), 1, "within 4 m of the veiled false light: the hint")
	if hints.size() == 1:
		assert_true(String(hints[0]).contains("{lantern}"), "it names the lantern key")
	_run(e, 3.0)
	assert_eq(hints.size(), 1, "only once")
	# Never for a revealed wisp (it can be hit - nothing to teach).
	var lit := _wisp(d, Vector3(2, 0, -2), 0.9)
	_run(lit, 1.0)
	assert_false(bool(lit.near_hint_shown), "a revealed wisp does not show it")
	Events.hint.disconnect(cb)
