extends "res://tests/test_case.gd"
## Quarry Warden regressions from the natural chain runs (qa/tmp/bot/chain/bugs.json):
## CHAIN-001 - with Krystal on the L1 terrace just below its bench (1.4 m lower, ~7 m away, no clear line) it stood in
##   "chase" for minutes: no attack, no approach, no reset. Now it fights only on its arena floor: no attack across
##   levels, it follows her to the bench edge but never off its level, and after UNREACHABLE_GIVE_UP s it walks home
##   and resets cleanly, waiting for her on its floor. On the floor it never gives up (a pillar hide never heals it) and
##   with no clear line it comes round instead of standing frozen.
## CHAIN-002 - slam punishes and poise stuns alone finished it with no pillar exposure. Now blows stop at
##   SHELL_FLOOR_RATIO until its shell was cracked open once in the attempt (one-time hint; then it charges at any
##   range), never while no intact pillar stands (always winnable), and a retry owes the exposure again. A scripted
##   copper-sword fight (the QA bot's two styles) needs 1-3 exposures and prints its length.
## Every check reads the new API through has_method / the constant map, so against the old Warden they fail by
## assertion (not by a script error).

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Warden := preload("res://src/enemies/quarry_warden.gd")
const PillarScript := preload("res://src/world/reach/east/quarry_pillar.gd")
const Q := preload("res://data/reach_east.gd")
const Shape := preload("res://src/world/reach/east/quarry_shape.gd")

const DT := 1.0 / 60.0
const COPPER := 18.0            # the starting copper sword (data/items.gd)
const SWING := 0.5              # player_logic.gd SWING_TIME
const SWORD_REACH := 2.9        # centre to centre: sword reach 2.5 + part of the Warden's 0.9 m body
const WALK := 4.2               # player_logic.gd WALK_SPEED
const SPRINT := 7.0             # player_logic.gd SPRINT_SPEED (dodges / repositioning)

var _nodes: Array = []
var _saved_area: Node = null
var _saved_mode: String = ""
var _hints: Array = []
var _hint_cb: Callable


class Dummy extends CharacterBody3D:
	var health: Node
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 300.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("timing_assist", false)
	_saved_area = Game.area
	_saved_mode = Game.mode
	Game.area = null
	_hints = []
	_hint_cb = func(id: String, _text: String) -> void: _hints.append(id)
	Events.hint.connect(_hint_cb)


func after_each() -> void:
	if Events.hint.is_connected(_hint_cb):
		Events.hint.disconnect(_hint_cb)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	Game.area = _saved_area
	Game.mode = _saved_mode
	await wait_frames(2)


# --- helpers ---------------------------------------------------------------------------------------------------------

func _dummy(pos: Vector3) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	_nodes.append(d)
	return d


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	add_child(w)
	w.global_position = pos
	_nodes.append(w)
	return w


func _floor() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))


## The run1 geometry: the arena bench (L2, top y 0) ends at z = -11 (1 m past a 10 m arena ring) and the L1 terrace
## lies 1.4 m lower beyond it.
const EDGE_Z := -11.0

func _bench_and_terrace() -> void:
	_box(Vector3(0, -0.5, EDGE_Z + 20.0), Vector3(80, 1, 40))           # L2: z from -11 to +29
	_box(Vector3(0, -1.9, EDGE_Z - 20.0), Vector3(80, 1, 40))           # L1: z from -51 to -11, top y -1.4


func _pillar(pos: Vector3, id: String = "t") -> Node3D:
	var p: Node3D = PillarScript.new()
	p.setup({"id": id, "regrow_seconds": 25.0})
	add_child(p)
	p.global_position = pos
	_nodes.append(p)
	return p


func _warden(target: Node3D, pos: Vector3, pillars: Array, radius: float = 10.0) -> Node:
	var e: Node = Factory.create("quarry_warden", {"home": pos, "no_drops": true, "arena_center": Vector3.ZERO,
		"arena_radius": radius, "pillars": pillars})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _step(e: Node, move: bool = true) -> void:
	e.tick(DT)
	if move:
		e._apply_movement(DT)


func _until(e: Node, s: String, max_t: float, move: bool = true) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		_step(e, move)
		t += DT
	return t


## A constant of quarry_warden.gd by name (the fallback when the Warden lacks it).
func _k(name: String, fallback: float) -> float:
	var script: Script = Warden
	return float(script.get_script_constant_map().get(name, fallback))


## Calls a (new) Warden method, or returns `fallback` when the Warden has no such method.
func _q(e: Node, method: String, fallback: Variant) -> Variant:
	return e.call(method) if e.has_method(method) else fallback


## Copper blows while its shell is held open (a long recover), `n` of them; returns the health it lost.
func _open_blows(e: Node, d: Node3D, n: int) -> float:
	var hp0 := float(e.health.hp)
	e._enter("recover", 100.0)
	for i in n:
		if bool(e.health.dead):
			break
		e.health.apply_damage(COPPER, d, Vector3.FORWARD)
	return hp0 - float(e.health.hp)


## Engages the Warden (Krystal in view on its floor) and returns once it hunts.
func _engage(e: Node) -> void:
	_until(e, "chase", 3.0, false)


## Charge baited into `pl`: Krystal stands in front of the pillar, side-steps once the lane has locked.
func _baited_charge(e: Node, d: Dummy) -> void:
	e.next_attack = "charge"
	_until(e, "telegraph", 5.0)
	while e.state == "telegraph" and e.state_time < 1.2:
		_step(e)
	d.global_position = Vector3(2.8, d.global_position.y, d.global_position.z)
	var t := 0.0
	while e.state in ["telegraph", "charge"] and t < 4.0:
		_step(e)
		t += DT


# --- CHAIN-001: Krystal off its arena floor -------------------------------------------------------------------------

func test_chain001_below_its_bench_it_goes_home_and_resets_then_waits_for_her() -> void:
	_bench_and_terrace()
	var pl := _pillar(Vector3(4, 0, 5))
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	var enc: Array = []
	var cb := func(id: String, on: bool) -> void:
		if id == Warden.BAR_ID:
			enc.append(on)
	Events.boss_encounter_changed.connect(cb)
	_engage(e)
	assert_eq(e.state, "chase", "engaged on its floor")
	e.slams_done = 1                                  # mid-fight, hurt: charge reach 9 m, stand-off 7.2 m (as in run1,
	e.health.set_hp(210.0)                            # where its pulses had played and it had 4.2 HP left)
	pl.crack()
	# She rolls off the bench onto the terrace: 1.4 m lower, ~7 m from its charge stand-off, no clear line (run1).
	d.global_position = Vector3(0, -1.4, EDGE_Z - 1.5)
	var attacks := 0
	var lowest := 0.0
	var nearest_z := 0.0
	var gone_home_at := -1.0
	var t := 0.0
	while t < 12.0:
		var prev: String = e.state
		_step(e)
		t += DT
		if e.state == "telegraph" and prev != "telegraph":
			attacks += 1
		lowest = minf(lowest, (e as Node3D).global_position.y)
		nearest_z = minf(nearest_z, (e as Node3D).global_position.z)
		if gone_home_at < 0.0 and e.state in ["return", "idle"]:
			gone_home_at = t
	assert_eq(attacks, 0, "no attack across levels / through the step")
	assert_eq(d.damaged_count, 0, "nothing reached her down there")
	assert_true(lowest > -0.3, "it never left its bench (lowest y %.2f)" % lowest)
	assert_true(nearest_z > EDGE_Z, "it stopped at the bench edge, not past it (z %.2f)" % nearest_z)
	assert_true(nearest_z > -10.0 - 0.3, "it waited at its arena ring, never beyond it after her (z %.2f)" % nearest_z)
	assert_true(nearest_z < -8.0, "it followed her to the edge, not frozen at its stand-off (z %.2f)" % nearest_z)
	var give_up := _k("UNREACHABLE_GIVE_UP", 5.0)
	assert_true(gone_home_at > 0.0, "it gave up and walked home (state %s after 12 s - CHAIN-001 froze in chase)" % e.state)
	var in_time := gone_home_at >= give_up - 0.1 and gone_home_at <= give_up + 0.5
	assert_true(in_time, "after about %.0f s (%.2f s)" % [give_up, gone_home_at])
	assert_eq(int(e.get("give_ups") if e.get("give_ups") != null else 0), 1, "counted once")
	assert_true(_hints.has("hint_quarry_warden_bench"), "a hint says why it turned back")
	assert_false(bool(e.engaged), "the encounter ended (bar hidden, saving free)")
	assert_true(enc.size() >= 2 and enc[enc.size() - 1] == false, "boss_encounter_changed(false) (%s)" % str(enc))
	_until(e, "idle", 25.0)
	assert_eq(e.state, "idle", "back home")
	assert_almost(float(e.health.hp), 300.0, 0.001, "the clean leash reset: whole again")
	assert_true(bool(pl.is_intact()), "its pillars re-knit")
	assert_eq(int(e.slams_done), 0, "the lesson restarts")
	# She stays down there: it waits (no re-engage, no flicker); a blow from below never drags it back out.
	var n_enc := enc.size()
	e.health.apply_damage(9.0, d, Vector3.FORWARD)
	for i in int(8.0 / DT):
		_step(e)
	assert_ne(e.state, "chase", "it stays home while she is off its floor")
	assert_eq(enc.size(), n_enc, "no new encounter from below (%s)" % str(enc))
	# Back up on its floor: a fresh fight.
	d.global_position = Vector3(0, 0, -6.0)
	_until(e, "chase", 3.0)
	assert_eq(e.state, "chase", "on its floor again it engages")
	assert_false(bool(_q(e, "has_given_up", true)), "the give-up cleared")
	Events.boss_encounter_changed.disconnect(cb)


func test_chain001_no_slam_across_the_step_even_with_a_clear_line() -> void:
	_bench_and_terrace()
	var d := _dummy(Vector3(0, 0, -7.0))
	var e := _warden(d, Vector3(0, 0, -8.5), [_pillar(Vector3(4, 0, 5))])
	await wait_physics(3)
	_engage(e)
	e.slams_done = 1
	(e as Node3D).global_position = Vector3(0, 0, EDGE_Z + 1.3)          # it stands at the bench edge ...
	d.global_position = Vector3(0, -1.4, EDGE_Z - 1.2)                   # ... she is just below, 2.5 m away, in view
	var attacks := 0
	var t := 0.0
	while t < 4.5:
		var prev: String = e.state
		_step(e)
		t += DT
		if e.state == "telegraph" and prev != "telegraph":
			attacks += 1
	assert_eq(attacks, 0, "no slam / charge / pulses at her on the level below (%s)" % e.state)
	assert_eq(d.damaged_count, 0)
	assert_true((e as Node3D).global_position.y > -0.3, "still on its bench")
	_until(e, "return", 2.0)
	assert_eq(e.state, "return", "then it gives up like above")


func test_chain001_hiding_behind_a_pillar_inside_the_arena_never_resets_it() -> void:
	_floor()
	var pl := _pillar(Vector3(0, 0, -4.5))
	var d := _dummy(Vector3(3.0, 0, -7.0))                               # in view first
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_engage(e)
	e.slams_done = 1
	e.health.set_hp(200.0)
	d.global_position = Vector3(0, 0, -7.0)                              # now right behind the pillar, 7 m away
	var attacked_at := -1.0
	var t := 0.0
	while t < 12.0 and attacked_at < 0.0:
		_step(e)
		t += DT
		if e.state == "telegraph":
			attacked_at = t
		if e.state in ["return", "idle"]:
			break
	assert_true(bool(e.engaged), "hiding inside its arena never ends the fight (state %s)" % e.state)
	assert_true(float(e.health.hp) <= 200.0 + 0.001, "and never heals it (%.1f)" % float(e.health.hp))
	assert_eq(int(e.get("give_ups") if e.get("give_ups") != null else 0), 0, "no give-up on its floor")
	assert_true(attacked_at > 0.0, "it came round the pillar and attacked (never frozen at its stand-off; state %s)" % e.state)
	assert_true(bool(pl.is_intact()), "walking round it cracks nothing")


# --- CHAIN-002: the pillar exposure is required ---------------------------------------------------------------------

func test_chain002_blows_alone_stop_at_the_shell_floor_until_a_pillar_exposure() -> void:
	_floor()
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -6.5))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	var fl := 300.0 * _k("SHELL_FLOOR_RATIO", 0.5)
	assert_true(bool(_q(e, "exposure_owed", false)), "a fresh attempt owes a pillar exposure")
	_open_blows(e, d, 60)                                                 # 60 copper blows, shell open: 1080 damage
	assert_false(bool(e.health.dead), "slam punishes / poise stuns alone never finish it (CHAIN-002)")
	assert_almost(float(e.health.hp), fl, 0.01, "blows stop at the shell floor (%.1f)" % float(e.health.hp))
	assert_eq(_hints.count("hint_quarry_warden_pillars"), 1, "one hint points at the pillars (%s)" % str(_hints))
	assert_true(bool(_q(e, "shell_holds", false)), "its shell holds")
	# The real bait: a charge into the pillar opens it and lifts the floor for the rest of the attempt.
	e.slams_done = 1
	e._enter("chase")
	Base.clock_override_ms += 5000
	e._cooldown = 0.0
	_baited_charge(e, d)
	assert_eq(e.state, "exposed", "baited into the pillar (%s, %s)" % [e.state, e.last_charge_result])
	assert_false(bool(_q(e, "exposure_owed", true)), "the exposure is paid")
	var hp0 := float(e.health.hp)
	e.health.apply_damage(COPPER, d, Vector3.FORWARD)
	assert_true(float(e.health.hp) < hp0 - 1.0, "the exposed bell takes damage below the old floor")
	# Its pulses (owed since phase 2) still play first; then blows can finish it.
	_until(e, "pulses", 15.0, false)
	_until(e, "recover", 5.0, false)
	assert_eq(int(e.pulses_fired), 3, "the three pulses played")
	for i in 30:
		e.health.apply_damage(COPPER, d, Vector3.FORWARD)
	assert_true(bool(e.health.dead), "after its exposure blows can finish it")


func test_chain002_once_its_shell_holds_it_charges_even_up_close() -> void:
	_floor()
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -2.5))                                  # inside slam reach
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_engage(e)
	e.slams_done = 1
	e.health.set_hp(190.0)                                                # phase 2: its pulses come first ...
	_until(e, "pulses", 10.0)
	_until(e, "recover", 5.0)
	assert_eq(int(e.pulses_fired), 3, "... and play")
	_open_blows(e, d, 20)
	assert_almost(float(e.health.hp), 300.0 * _k("SHELL_FLOOR_RATIO", 0.5), 0.01, "stopped at the shell floor")
	e._enter("chase")
	e._cooldown = 0.0
	d.global_position = (e as Node3D).global_position + Vector3(0, 0, -2.5)
	Base.clock_override_ms += 5000
	_until(e, "telegraph", 4.0)
	assert_eq(String(e.attack_kind), "charge", "blows stopped working: it scrapes for a charge even up close (not a slam)")


func test_chain002_with_every_pillar_cracked_blows_still_win() -> void:
	var a := _pillar(Vector3(5, 0, 5), "a")
	var b := _pillar(Vector3(-5, 0, 5), "b")
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _warden(d, Vector3.ZERO, [a, b])
	a.crack()
	b.crack()
	assert_false(bool(_q(e, "exposure_owed", false)), "no intact pillar: nothing is owed")
	_open_blows(e, d, 20)
	var left := float(e.health.hp)
	assert_true(left < 300.0 * _k("SHELL_FLOOR_RATIO", 0.5) - 1.0, "no shell floor while every pillar is down (%.1f)" % left)
	assert_false(_hints.has("hint_quarry_warden_pillars"), "no pillar hint without a pillar")
	var none := _warden(d, Vector3(40, 0, 40), [])
	none.health.apply_damage(1.0e6, d, Vector3.FORWARD)
	assert_true(bool(none.health.dead), "a Warden without any pillar is never held back")


func test_chain002_a_retry_owes_the_exposure_again() -> void:
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _warden(d, Vector3.ZERO, [pl])
	_engage(e)
	e._expose()
	assert_false(bool(_q(e, "exposure_owed", true)), "exposed once: nothing owed")
	Events.player_died.emit()
	assert_true(bool(_q(e, "exposure_owed", false)), "a fresh attempt owes it again")
	_open_blows(e, d, 40)
	assert_almost(float(e.health.hp), 300.0 * _k("SHELL_FLOOR_RATIO", 0.5), 0.01, "the shell floor is back")


# --- A scripted copper-sword fight (the QA bot's two styles + a slower one) ------------------------------------------

## The real arena layout (data/reach_east.gd), flat, centred on the origin: [warden home, pillar offsets, start].
func _layout() -> Array:
	var c: Vector2 = Q.ARENA
	var pls: Array = []
	for p in Q.PILLARS:
		var w: Vector2 = Shape.to_world(p) - c
		pls.append(Vector3(w.x, 0, w.y))
	var h: Vector2 = Shape.to_world(Q.SPAWNERS[Q.WARDEN_SPAWNER]["at"]) - c
	var s: Vector2 = Shape.to_world(Vector2(8.0, -9.0)) - c              # where the QA bot enters the bench
	return [Vector3(h.x, 0, h.y), pls, Vector3(s.x, 0, s.y)]


## Where to stand so pillar `p` is straight behind her as seen from the Warden (2.4 m in front of it).
func _bait_spot(wp: Vector3, p: Vector3) -> Vector3:
	var to := Vector3(wp.x - p.x, 0, wp.z - p.z)
	return p + to.normalized() * 2.4


## One fight with the copper sword. style "hug": stays close, dodges every tell, strikes whenever in reach (shell
## included) - the CHAIN-002 bot - and baits only while the pillar hint's shell floor holds; style "bait": after the slam
## lesson stands with a pillar behind her so it charges into it, strikes only in open windows (the intended way);
## style "casual": "bait" played slower - walks instead of sprinting, reacts later, swings every 0.65 s and starts a
## punish 0.4 s into the window. Every style is flawless at dodging: the times are a floor for real first attempts.
## `entry`: 0 = where the QA bot steps onto the bench, 1 / 2 = that point turned 120 / 240 degrees round the arena.
## Returns {t, exposures, hits_taken, slams, pulses, dead}.
func _fight(style: String, entry: int, max_t: float = 240.0) -> Dictionary:
	var lay := _layout()
	var pls: Array = []
	var i := 0
	for off in lay[1]:
		pls.append(_pillar(off, "p%d" % i))
		i += 1
	var start: Vector3 = (lay[2] as Vector3).rotated(Vector3.UP, TAU / 3.0 * float(entry))
	var d := _dummy(start)
	var e := _warden(d, lay[0], pls, Q.ARENA_RADIUS)
	await wait_physics(3)
	e._rng.seed = 11 + entry
	var baiting := style != "hug"
	var casual := style == "casual"
	var fast := WALK if casual else SPRINT
	var swing_every := 0.65 if casual else SWING
	var react := 0.1 if casual else 0.0
	var t := 0.0
	var swing_cd := 0.0
	var dodge_side := 1.0
	var slams := 0
	var prev := ""
	while not bool(e.health.dead) and t < max_t:
		if style == "hug":                                    # she reads the hint, and mashes again once it is open
			baiting = _hints.has("hint_quarry_warden_pillars") and bool(_q(e, "shell_holds", false))
		var wp: Vector3 = (e as Node3D).global_position
		var me := d.global_position
		var to_w := Vector3(wp.x - me.x, 0, wp.z - me.z)
		var dist := to_w.length()
		var dir := to_w / dist if dist > 0.01 else Vector3.FORWARD
		var goal := me
		var speed := WALK
		var st: String = e.state
		if st == "slam" and prev != "slam":
			slams += 1
		prev = st
		var open: bool = st in ["recover", "stunned", "exposed"]
		match st:
			"telegraph":
				var frac: float = float(e.state_time) / maxf(float(e._state_len), 0.001)
				match String(e.attack_kind):
					"slam":
						if frac >= 0.6 + react and dist < float(e.slam_reach()) + 0.7:
							goal = wp - dir * (float(e.slam_reach()) + 0.8)
							speed = SPRINT
					"pulses":
						if frac >= 0.3 + react:
							goal = wp - dir * (float(e.pulse_radius()) + 0.8)
							speed = SPRINT
					"charge":
						if frac < 0.5 and baiting:
							var best := _best_bait(e, pls, wp, me)
							if best.is_finite():
								goal = best
						elif frac >= 0.6 + react * 0.5:
							var f: Vector3 = e._forward()
							var lat := Vector3(-f.z, 0, f.x)
							var off := (me - wp).dot(lat)
							dodge_side = 1.0 if off >= 0.0 else -1.0
							goal = me + lat * dodge_side * maxf(2.4 - absf(off), 0.0)
							speed = SPRINT
			"slam", "pulses":
				pass                                            # already out of the wedge / ring
			"charge":
				var f2: Vector3 = e._forward()
				var lat2 := Vector3(-f2.z, 0, f2.x)
				var off2 := (me - wp).dot(lat2)
				if absf(off2) < 2.2 and (me - wp).dot(f2) > -1.0:
					goal = me + lat2 * (1.0 if off2 >= 0.0 else -1.0) * 1.0
					speed = SPRINT
			_:
				if open:
					goal = wp - dir * 2.0
					speed = fast
				elif baiting and bool(e.charge_unlocked()):
					var b := _best_bait(e, pls, wp, me)
					goal = b if b.is_finite() else wp - dir * 2.4
					speed = fast
				else:
					goal = wp - dir * 2.4
		var step := goal - me
		step.y = 0.0
		if step.length() > speed * DT:
			step = step.normalized() * speed * DT
		d.global_position = me + step
		swing_cd -= DT
		var reach_now := Vector3(wp.x - d.global_position.x, 0, wp.z - d.global_position.z).length()
		var punish: bool = open and (not casual or float(e.state_time) >= 0.4)
		var strike: bool = punish or (style == "hug" and not baiting and st in ["chase", "telegraph"])
		if swing_cd <= 0.0 and reach_now <= SWORD_REACH and strike:
			swing_cd = swing_every
			e.health.apply_damage(COPPER, d, dir)
		_step(e)
		t += DT
	var out := {"t": t, "exposures": int(e.exposures), "hits_taken": d.damaged_count, "slams": slams,
		"pulses": int(e.pulses_fired), "dead": bool(e.health.dead)}
	for n in [e, d] + pls:
		_nodes.erase(n)
		n.queue_free()
	await wait_frames(2)
	Base.reset_attack_tokens()
	return out


## The nearest spot with an intact pillar behind her that keeps her beyond slam reach of the Warden, or INF.
func _best_bait(e: Node, pls: Array, wp: Vector3, me: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for p in pls:
		if not bool(p.is_intact()):
			continue
		var pp: Vector3 = (p as Node3D).global_position
		if Vector2(pp.x - wp.x, pp.z - wp.z).length() < float(e.slam_reach()) + 2.4 + 0.6:
			continue
		var spot := _bait_spot(wp, pp)
		var dd := spot.distance_to(me)
		if dd < best_d:
			best_d = dd
			best = spot
	return best


func test_chain002_copper_sword_fights_need_one_to_three_exposures() -> void:
	_floor()
	var rows: Array = []
	for style in ["hug", "bait", "casual"]:
		for entry in [0, 1, 2]:
			_hints.clear()
			Base.clock_override_ms = -1
			var r: Dictionary = await _fight(style, entry)
			rows.append([style, entry, r])
			print("  warden copper fight %-6s entry %d: %s in %.1f s, %d exposures, %d slams, %d pulses, %d hits taken" % [
				style, entry, "won" if r["dead"] else "NOT won", r["t"], r["exposures"], r["slams"], r["pulses"], r["hits_taken"]])
	for row in rows:
		var r: Dictionary = row[2]
		var tag := "%s/%d" % [row[0], row[1]]
		assert_true(bool(r["dead"]), "%s: the copper sword wins (%.0f s)" % [tag, r["t"]])
		assert_true(int(r["exposures"]) >= 1, "%s: at least one pillar exposure is needed (CHAIN-002: %d)" % [tag, r["exposures"]])
		assert_true(int(r["exposures"]) <= 3, "%s: early gear needs at most three (%d)" % [tag, r["exposures"]])
		assert_true(float(r["t"]) <= 150.0, "%s: no health sponge (%.0f s)" % [tag, r["t"]])
		assert_true(int(r["pulses"]) >= 3, "%s: the three pulses played" % tag)
