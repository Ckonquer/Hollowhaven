extends "res://tests/test_case.gd"
## Quarry Warden (module C5, MP 12 "Ashbell elite"): the lesson order (slam first; the charge only after a slam),
## shell armour (reduced, never nothing; open in recovery; x EXPOSED_MULT while exposed), the pillar bait (a charge
## into an intact quarry_pillar cracks it and exposes the Warden; a plain wall only bonks while pillars stand; with no
## intact pillar left any wall exposes it), three spaced pulses in phase 2 (timings, ring = radius, outside safe),
## companions only while its shell is open, poise, encounter events (engage / bar / phase / defeated once), the
## reset policy (Krystal's defeat or leaving the leash: every pillar whole, the Warden whole) and the real arena
## (warden_arena.gd): the spawner hands over the pillars, defeat commits hr_warden_defeated + the spawner flag
## BEFORE any presentation, and a retry after Krystal's defeat starts fresh.
## Integration pass 2 (D06): the charge lane ends within arena_radius - 1 m of the arena centre (the mark shows the
## clipped length) and a ledge ahead (no floor within 1 m below) bonks it like a wall - it never falls to L1.
## QA CH2-004 (balance): one exposure takes at most EXPOSE_CAP of its health (then the shell closes), phase 2 opens
## with its pulses and holds a floor until they played, so early gear needs 2-3 exposures and always meets the pulses.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Warden := preload("res://src/enemies/quarry_warden.gd")
const PillarScript := preload("res://src/world/reach/east/quarry_pillar.gd")
const ArenaScript := preload("res://src/world/reach/east/warden_arena.gd")
const SpawnerScript := preload("res://src/world/reach/east/guarded_spawner.gd")
const Q := preload("res://data/reach_east.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null
var _saved_mode: String = ""


class Dummy extends CharacterBody3D:
	var health: Node
	var damaged_count: int = 0
	var hit_times: Array = []
	var clock: float = 0.0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 300.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void:
			damaged_count += 1
			hit_times.append(clock))

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("timing_assist", false)
	SpawnerScript.availability_override = {}
	_saved_area = Game.area
	_saved_mode = Game.mode
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	SpawnerScript.availability_override = {}
	Game.area = _saved_area
	Game.mode = _saved_mode
	await wait_frames(2)


func _dummy(pos: Vector3, group: String = "player") -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group(group)
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


func _pillar(pos: Vector3, id: String = "t") -> Node3D:
	var p: Node3D = PillarScript.new()
	p.setup({"id": id, "regrow_seconds": 25.0})
	add_child(p)
	p.global_position = pos
	_nodes.append(p)
	return p


func _warden(target: Node3D, pos: Vector3 = Vector3.ZERO, pillars: Array = []) -> Node:
	var e: Node = Factory.create("quarry_warden", {"home": pos, "no_drops": true, "arena_center": pos, "arena_radius": 14.0, "pillars": pillars})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _step(e: Node, move: bool, d: Dummy = null) -> void:
	e.tick(DT)
	if move:
		e._apply_movement(DT)
	if d != null:
		d.clock += DT


func _until(e: Node, s: String, max_t: float = 10.0, move: bool = false, d: Dummy = null) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		_step(e, move, d)
		t += DT
	return t


## Runs a charge at Krystal standing in front of `obstacle_z`, and side-steps her once the lane has locked.
func _baited_charge(e: Node, d: Dummy) -> void:
	e.slams_done = 1
	e.next_attack = "charge"
	_until(e, "telegraph", 5.0, true)
	assert_eq(String(e.attack_kind), "charge", "it winds up a charge")
	while e.state == "telegraph" and e.state_time < 1.2:
		_step(e, true)
	assert_true(bool(e.mark().footprint()["locked"]), "the lane locked")
	d.global_position = Vector3(2.8, 0, d.global_position.z)     # side-step out of the 2.2 m lane
	var t := 0.0
	while e.state in ["telegraph", "charge"] and t < 4.0:
		_step(e, true)
		t += DT


# --- The lesson ----------------------------------------------------------------------------------------------------

func test_slam_first_then_charges_from_range() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -7.0))
	var e := _warden(d)
	await wait_physics(2)
	assert_false(bool(e.charge_unlocked()), "no charge before its first slam")
	_until(e, "telegraph", 8.0, true)
	assert_eq(String(e.attack_kind), "slam", "the first lesson is the slam")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "arc")
	assert_almost(float(m.footprint()["radius"]), float(e.slam_reach()), 0.001, "marked reach = hit reach")
	var tele := _until(e, "slam", 3.0, true)
	assert_almost(tele, 1.4, DT * 2.0, "slam wind-up = data 1.4 s")
	_until(e, "recover", 1.0, true)
	assert_eq(int(e.slams_done), 1)
	assert_eq(d.damaged_count, 1, "one slam")
	assert_almost(float(d.health.hp), 300.0 - 18.0, 0.001, "slam data damage 18")
	assert_almost(float(e.armor_mult()), Warden.OPEN_MULT, 0.001, "shell open in the recovery (punish window)")
	var rec := _until(e, "chase", 3.0, true)
	assert_almost(rec, 1.8, DT * 2.0, "slam recover = data 1.8 s")
	assert_true(bool(e.charge_unlocked()), "the charge is taught next")
	d.global_position = (e as Node3D).global_position + Vector3(0, 0, -7.0)
	Base.clock_override_ms += 5000
	_until(e, "telegraph", 6.0, true)
	assert_eq(String(e.attack_kind), "charge", "from range it now charges")


func test_shell_reduces_never_nullifies() -> void:
	var d := _dummy(Vector3(0, 0, -20))
	var e := _warden(d)
	assert_almost(float(e.armor_mult()), Warden.SHELL_MULT, 0.001, "shelled")
	assert_almost(float(e.health.apply_damage(18.0, d, Vector3.FORWARD)), 18.0 * Warden.SHELL_MULT, 0.001, "half damage through the shell")
	assert_almost(float(e.health.apply_damage(5.0, d, Vector3.FORWARD)), 2.5, 0.001, "early tools still hurt")
	e._enter("recover", 1.0)
	assert_almost(float(e.health.apply_damage(18.0, d, Vector3.FORWARD)), 18.0, 0.001, "open in the recovery")
	e._enter("exposed", 1.0)
	assert_almost(float(e.health.apply_damage(18.0, d, Vector3.FORWARD)), 18.0 * Warden.EXPOSED_MULT, 0.001, "exposed: extra damage")


# --- The pillar bait ------------------------------------------------------------------------------------------------

func test_charge_into_a_pillar_cracks_it_and_exposes_the_warden() -> void:
	_floor()
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -6.5))
	var friend := _dummy(Vector3(3, 0, -3), "companion")
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	assert_false(bool(e.can_be_hit_by(friend)), "companions wait while the shell is closed")
	_baited_charge(e, d)
	assert_eq(e.state, "exposed", "baited into the pillar: exposed (%s, %s)" % [e.state, e.last_charge_result])
	assert_eq(String(e.last_charge_result), "pillar")
	assert_false(bool(pl.is_intact()), "the pillar cracked")
	assert_eq(int(e.pillars_cracked), 1)
	assert_almost(float(d.health.hp), 300.0, 0.001, "the side-step avoided the charge")
	assert_true((e as Node3D).global_position.z > -9.0 + 0.85, "never passes through the pillar")
	assert_almost(float(e.armor_mult()), Warden.EXPOSED_MULT, 0.001, "exposed damage")
	assert_true(bool(e.can_be_hit_by(friend)), "companions join in while it is exposed")
	assert_true(bool(e.is_threatening()), "still a fight")
	e.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_eq(e.state, "exposed", "hits never cut the window short")
	var t := _until(e, "chase", 8.0, true)
	assert_almost(t + DT, Warden.EXPOSE_TIME, DT * 3.0, "exposed for EXPOSE_TIME (%.2f)" % t)
	assert_false(bool(e.can_be_hit_by(friend)), "shell closed again")


func test_timing_assist_lengthens_the_window() -> void:
	Settings.set_value("timing_assist", true)
	var d := _dummy(Vector3(0, 0, -20))
	var e := _warden(d)
	assert_almost(float(e.expose_time()), Warden.EXPOSE_TIME_ASSIST, 0.001)
	Settings.set_value("timing_assist", false)


func test_plain_wall_only_bonks_while_pillars_stand() -> void:
	_floor()
	var pl := _pillar(Vector3(12, 0, 12))
	_box(Vector3(0, 1.5, -9.0), Vector3(8, 3, 0.6))
	var d := _dummy(Vector3(0, 0, -6.5))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_baited_charge(e, d)
	assert_eq(e.state, "stunned", "a plain wall bonks it (%s)" % e.state)
	assert_eq(String(e.last_charge_result), "wall")
	assert_true(bool(pl.is_intact()), "the far pillar is untouched")
	assert_almost(float(e.armor_mult()), Warden.OPEN_MULT, 0.001, "stunned: open, but not exposed")


func test_with_no_intact_pillar_any_wall_exposes_it() -> void:
	_floor()
	var pl := _pillar(Vector3(12, 0, 12))
	pl.crack()
	_box(Vector3(0, 1.5, -9.0), Vector3(8, 3, 0.6))
	var d := _dummy(Vector3(0, 0, -6.5))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_baited_charge(e, d)
	assert_eq(e.state, "exposed", "never unwinnable: with every pillar down a wall exposes it")
	assert_eq(String(e.last_charge_result), "wall_exposed")


func test_pillars_found_by_group_near_the_arena() -> void:
	var pl := _pillar(Vector3(5, 0, 5))
	var far := _pillar(Vector3(60, 0, 60), "far")
	var d := _dummy(Vector3(0, 0, -20))
	var e := _warden(d)
	var got: Array = e.pillar_nodes()
	assert_true(got.has(pl), "a pillar inside its arena counts")
	assert_false(got.has(far), "a far pillar does not")


func test_missed_charge_is_a_long_open_window() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -6.5))
	var e := _warden(d)
	await wait_physics(2)
	_baited_charge(e, d)
	assert_eq(e.state, "recover", "nothing in the way: it skids to a stop")
	assert_eq(String(e.last_charge_result), "missed")
	assert_almost(float(e.armor_mult()), Warden.OPEN_MULT, 0.001, "open")
	assert_almost(_until(e, "chase", 5.0, true) + DT, 3.5, DT * 3.0, "data charge recover 3.5 s")


# --- The charge stays in its arena (integration pass 2, D06) ----------------------------------------------------------

func _warden_in(target: Node3D, pos: Vector3, center: Vector3, radius: float, pillars: Array = []) -> Node:
	var e: Node = Factory.create("quarry_warden", {"home": pos, "no_drops": true, "arena_center": center, "arena_radius": radius, "pillars": pillars})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func test_arena_lane_limit_geometry() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _warden_in(d, Vector3.ZERO, Vector3.ZERO, 10.0)
	var r := 10.0 - Warden.ARENA_EDGE_MARGIN
	assert_almost(float(e.arena_lane_limit(Vector3.ZERO, Vector3(1, 0, 0))), r, 0.001, "from the centre: arena_radius - 1 m")
	assert_almost(float(e.arena_lane_limit(Vector3(5, 0, 0), Vector3(1, 0, 0))), r - 5.0, 0.001, "heading out")
	assert_almost(float(e.arena_lane_limit(Vector3(5, 0, 0), Vector3(-1, 0, 0))), r + 5.0, 0.001, "heading across")
	assert_almost(float(e.arena_lane_limit(Vector3(9.5, 0, 0), Vector3(1, 0, 0))), 0.0, 0.001, "already past the inner ring, heading out: no lane")
	assert_almost(float(e.charge_reach(Vector3.ZERO, Vector3(0, 0, -1))), r, 0.001, "data 12 m clipped to 9 m")
	var wide := _warden_in(d, Vector3(50, 0, 50), Vector3(50, 0, 50), 20.0)
	assert_almost(float(wide.charge_reach(Vector3(50, 0, 50), Vector3(0, 0, -1))), 12.0, 0.001, "a big arena keeps the data distance")


func test_a_charge_lane_ends_inside_the_arena() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -10.0))
	var e := _warden_in(d, Vector3(0, 0, -4.0), Vector3.ZERO, 10.0)      # 4 m from the centre, arena ring 10 m
	await wait_physics(2)
	_baited_charge(e, d)
	var want := 10.0 - Warden.ARENA_EDGE_MARGIN - 4.0
	assert_almost(float(e.lane_length()), want, 0.1, "the lane is clipped to the arena (%.2f m)" % e.lane_length())
	var p: Vector3 = (e as Node3D).global_position
	assert_true(Vector2(p.x, p.z).length() <= 10.0 - Warden.ARENA_EDGE_MARGIN + 0.3, "it stopped inside the arena (%.2f m out)" % Vector2(p.x, p.z).length())
	assert_eq(String(e.last_charge_result), "missed", "nothing in the way: it skids to a stop at the lane's end")
	assert_almost(float(d.health.hp), 300.0, 0.001)


func test_the_lane_mark_shows_the_clipped_length() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -10.0))
	var e := _warden_in(d, Vector3(0, 0, -4.0), Vector3.ZERO, 10.0)
	await wait_physics(2)
	e.slams_done = 1
	e.next_attack = "charge"
	_until(e, "telegraph", 5.0, true)
	for i in 10:
		_step(e, true)
	var fp: Dictionary = e.mark().footprint()
	var marked := Vector2((fp["to"] as Vector3).x - (fp["from"] as Vector3).x, (fp["to"] as Vector3).z - (fp["from"] as Vector3).z).length()
	assert_eq(String(fp["kind"]), "lane")
	assert_true(marked <= 10.0 - Warden.ARENA_EDGE_MARGIN - 4.0 + 0.3, "the red lane shows the clipped length (%.2f m)" % marked)
	assert_almost(marked, float(e.lane_length()), 0.01, "mark = charge lane")


func _ledge_floor() -> void:
	# L2 (y 0) up to the edge at z = -3, then a 1.4 m step down to L1 (like the quarry's L1|L2 bench edge).
	_box(Vector3(0, -0.5, 18.5), Vector3(80, 1, 43))
	_box(Vector3(0, -1.9, -23.0), Vector3(80, 1, 40))


func test_a_charge_baited_off_the_ledge_bonks_at_the_edge() -> void:
	_ledge_floor()
	var far := _pillar(Vector3(12, 0, 12))
	# She baits it at the very edge of L2 and side-steps: the 12 m lane runs on past the edge (QA CHAIN-001: it never
	# starts an attack at her while she stands down on L1 itself, so the bait is on its own level).
	var d := _dummy(Vector3(0, 0, -2.6))
	var e := _warden(d, Vector3.ZERO, [far])
	await wait_physics(3)
	assert_true(bool(e.floor_ahead(Vector3(0, 0, -1), 0.1)), "floor ahead where it stands")
	_baited_charge(e, d)
	assert_eq(int(e.ledge_stops), 1, "the ledge stopped the charge")
	assert_eq(e.state, "stunned", "a pillar still stands: a bonk and a stun (%s)" % e.state)
	assert_eq(String(e.last_charge_result), "wall")
	assert_true(bool(far.is_intact()), "the far pillar is untouched")
	for i in 30:
		_step(e, true)
	var p: Vector3 = (e as Node3D).global_position
	assert_true(p.z > -3.0, "it stays on L2 (z %.2f)" % p.z)
	assert_true(p.y > -0.3, "it never dropped to L1 (y %.2f)" % p.y)
	assert_almost(float(d.health.hp), 300.0, 0.001)


func test_with_no_intact_pillar_the_ledge_exposes_it() -> void:
	_ledge_floor()
	var gone := _pillar(Vector3(12, 0, 12))
	gone.crack()
	var d := _dummy(Vector3(0, 0, -2.6))              # baited at the L2 edge (see above)
	var e := _warden(d, Vector3.ZERO, [gone])
	await wait_physics(3)
	_baited_charge(e, d)
	assert_eq(int(e.ledge_stops), 1)
	assert_eq(e.state, "exposed", "never unwinnable: with every pillar down the ledge exposes it like a wall")
	assert_eq(String(e.last_charge_result), "wall_exposed")


# --- Phase 2: three spaced pulses -------------------------------------------------------------------------------------

func test_three_spaced_pulses_in_phase_two() -> void:
	var events: Array = []
	var cb := func(id: String, ph: int) -> void:
		if id == Warden.BAR_ID:
			events.append(ph)
	Events.boss_phase_changed.connect(cb)
	var d := _dummy(Vector3(0, 0, -3.0))
	var safe := _dummy(Vector3(0, 0, 6.0))
	var e := _warden(d)
	e.health.set_hp(300.0 * 0.6)
	assert_eq(int(e.phase), 2, "below 66% health: phase 2")
	assert_eq(events, [2], "boss_phase_changed(quarry_warden, 2) once")
	Events.boss_phase_changed.disconnect(cb)
	e.next_attack = "pulses"
	_until(e, "telegraph", 4.0)
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "ring")
	assert_almost(float(m.footprint()["radius"]), 5.0, 0.001, "ring = data radius 5")
	var tele := _until(e, "pulses", 3.0)
	assert_almost(tele, 1.6, DT * 2.0, "pulses wind-up = data 1.6 s")
	assert_eq(int(e.visual.pips_lit), 3, "three pips lit on the bell (count, muted-readable)")
	d.clock = 0.0
	_until(e, "recover", 4.0, false, d)
	assert_eq(int(e.pulses_fired), 3, "three pulses")
	assert_eq(d.damaged_count, 3, "standing in the ring takes each one")
	assert_eq(d.hit_times.size(), 3)
	if d.hit_times.size() == 3:
		assert_almost(float(d.hit_times[1]) - float(d.hit_times[0]), 0.9, DT * 2.0, "spaced by data spacing 0.9 s")
		assert_almost(float(d.hit_times[2]) - float(d.hit_times[1]), 0.9, DT * 2.0)
	assert_almost(float(safe.health.hp), 300.0, 0.001, "outside the ring: safe")
	assert_almost(float(e.armor_mult()), Warden.OPEN_MULT, 0.001, "open after the pulses")


# --- Balance: capped exposures, phase 2 always plays its pulses (QA CH2-004) ----------------------------------------
# The QA bot's Chapter-One gear: the starting copper sword, 18 damage every ~0.45 s. Before the fix one pillar
# exposure (6 s, x1.6, no cap) took ~250 of 300 and phase 2 (the three pulses) began and ended inside it.

const COPPER := 18.0
const COPPER_EVERY := 0.45


## A constant of quarry_warden.gd by name (a default when it is missing, so these checks fail by assertion - not by
## a parse error of this file - against a Warden without them).
func _k(name: String, fallback: float) -> float:
	var script: Script = Warden
	return float(script.get_script_constant_map().get(name, fallback))


## Strikes with the copper sword while the Warden stays in state `s` (at most max_t s); returns the health it lost.
func _strike_while(e: Node, d: Dummy, s: String, max_t: float) -> float:
	var hp0 := float(e.health.hp)
	var t := 0.0
	var next := 0.0
	while e.state == s and t < max_t and not bool(e.health.dead):
		if t >= next - 0.0001:
			next += COPPER_EVERY
			e.health.apply_damage(COPPER, d, Vector3.FORWARD)
			if e.state != s or bool(e.health.dead):
				break
		_step(e, false)
		t += DT
	return hp0 - float(e.health.hp)


func test_one_exposure_takes_at_most_its_cap_then_the_shell_closes() -> void:
	_floor()
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -6.5))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_baited_charge(e, d)
	assert_eq(e.state, "exposed", "baited into the pillar")
	var captions: Array = []
	var cb := func(text: String) -> void: captions.append(text)
	Events.caption.connect(cb)
	var t := 0.0
	var lost := 0.0
	var hp0 := float(e.health.hp)
	var next := 0.0
	while e.state == "exposed" and t < Warden.EXPOSE_TIME + 1.0 and not bool(e.health.dead):
		if t >= next - 0.0001:
			next += COPPER_EVERY
			e.health.apply_damage(COPPER, d, Vector3.FORWARD)
			if e.state != "exposed" or bool(e.health.dead):
				break
		_step(e, true)
		t += DT
	lost = hp0 - float(e.health.hp)
	Events.caption.disconnect(cb)
	var cap := 300.0 * _k("EXPOSE_CAP", 0.35)
	assert_false(bool(e.health.dead), "one exposure never finishes it (it lost %.1f of 300)" % lost)
	assert_true(lost <= cap + 0.01, "one exposure takes at most %.0f of 300 (it lost %.1f)" % [cap, lost])
	assert_almost(lost, cap, 0.01, "the copper sword reaches the cap: the blow that gets there is trimmed to it")
	assert_ne(e.state, "exposed", "at the cap the shell closes at once")
	assert_true(t < Warden.EXPOSE_TIME - 1.0, "well before the window's time ran out (%.2f s)" % t)
	assert_true(captions.has("[the Warden's shell grinds shut over its bell]"), "a caption says why the window ended")
	assert_eq(int(e.get("exposures_capped")), 1, "counted as a capped exposure")
	assert_almost(float(e.armor_mult()), Warden.SHELL_MULT, 0.001, "shelled again")
	assert_eq(int(e.phase), 2, "from full health one capped exposure reaches phase 2 ...")
	assert_eq(int(e.pulses_fired), 0, "... with its pulses still ahead")
	e.health.apply_damage(COPPER, d, Vector3.FORWARD)
	assert_almost(float(e.health.hp), 300.0 - cap - COPPER * Warden.SHELL_MULT, 0.01, "the cap is per exposure: the shell still takes its share")


func test_phase_two_opens_with_the_pulses_even_from_charge_range() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -7.0))
	var e := _warden(d)
	await wait_physics(2)
	e.slams_done = 1
	e.health.set_hp(190.0)
	assert_eq(int(e.phase), 2, "phase 2")
	_until(e, "telegraph", 8.0, true)
	assert_eq(String(e.attack_kind), "pulses", "phase 2 opens with its three pulses (Krystal stood at charge range)")
	var p: Vector3 = (e as Node3D).global_position
	var gap := Vector2(p.x - d.global_position.x, p.z - d.global_position.z).length()
	assert_true(gap <= float(e.pulse_radius()), "it walked into pulse reach first (%.2f m): the ring is a real threat" % gap)
	_until(e, "recover", 6.0, true)
	assert_eq(int(e.pulses_fired), 3, "three spaced pulses played")
	assert_false(bool(e.pulses_owed()), "the debt is paid")
	d.global_position = (e as Node3D).global_position + Vector3(0, 0, -7.0)
	Base.clock_override_ms += 5000
	_until(e, "telegraph", 8.0, true)
	assert_eq(String(e.attack_kind), "charge", "afterwards phase 2 picks its attacks as before (a charge from range)")


func test_owed_pulses_hold_a_floor_until_the_cycle_played() -> void:
	var hints: Array = []
	var hcb := func(id: String, _text: String) -> void: hints.append(id)
	Events.hint.connect(hcb)
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _warden(d)
	e.health.set_hp(190.0)
	e._enter("recover", 2.0)                         # shell open: full damage
	for i in 20:
		e.health.apply_damage(COPPER, d, Vector3.FORWARD)
	var fl := 300.0 * _k("PULSE_FLOOR_RATIO", 0.3)
	assert_false(bool(e.health.dead), "a burst can't finish it before its phase-2 pulses played")
	assert_almost(float(e.health.hp), fl, 0.01, "blows stop at the floor (%.1f)" % float(e.health.hp))
	assert_true(hints.has("hint_quarry_warden_pulses"), "a hint says what the fight is waiting for")
	Events.hint.disconnect(hcb)
	_until(e, "pulses", 10.0)
	_until(e, "recover", 4.0)
	assert_eq(int(e.pulses_fired), 3, "the pulses played")
	for i in 10:
		e.health.apply_damage(COPPER, d, Vector3.FORWARD)
	assert_true(bool(e.health.dead), "after its pulses it can be finished")


func test_a_retry_forgets_the_owed_pulses() -> void:
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _warden(d)
	_until(e, "chase", 3.0)
	e.health.set_hp(150.0)
	assert_true(bool(e.pulses_owed()), "phase 2 owes its pulses")
	Events.player_died.emit()
	assert_false(bool(e.pulses_owed()), "a fresh attempt starts at the lesson again")
	assert_almost(float(e.pulse_floor()), 0.0, 0.001, "no floor in phase 1")
	e.health.apply_damage(1.0e6, d, Vector3.FORWARD)
	assert_true(bool(e.health.dead), "outside the owed pulses nothing holds a blow back")


## A whole fight with the copper sword, striking only in the exposure windows (the pillar bait itself is covered
## above: the exposure is started directly here), with and without punishing the pulse recovery: two or three
## exposures, and the three pulses always play before it falls.
func test_early_gear_needs_two_or_three_exposures_and_meets_the_pulses() -> void:
	for punish in [false, true]:
		Base.reset_attack_tokens()
		var d := _dummy(Vector3(0, 0, -3.0))
		var e := _warden(d)
		e.slams_done = 1
		_until(e, "chase", 3.0)
		var pulses_at_defeat := -1
		var worst := 0.0
		var guard := 0
		while not bool(e.health.dead) and guard < 6:
			guard += 1
			e._expose()
			var hp0 := float(e.health.hp)
			_strike_while(e, d, "exposed", 9.0)
			worst = maxf(worst, hp0 - float(e.health.hp))
			if bool(e.health.dead):
				pulses_at_defeat = int(e.pulses_fired)
				break
			if e.has_method("pulses_owed") and bool(e.pulses_owed()):
				_until(e, "pulses", 10.0)
				_until(e, "recover", 4.0)
				if punish:
					_strike_while(e, d, "recover", 3.0)
				if bool(e.health.dead):
					pulses_at_defeat = int(e.pulses_fired)
					break
			_until(e, "chase", 6.0)
		var n := int(e.exposures)
		assert_true(bool(e.health.dead), "defeated (punish %s)" % punish)
		assert_true(n >= 2 and n <= 3, "early gear needs 2-3 exposures (punish %s: %d)" % [punish, n])
		assert_true(worst <= 300.0 * _k("EXPOSE_CAP", 0.35) + 0.01, "no exposure took more than the cap (%.1f)" % worst)
		assert_true(pulses_at_defeat >= 3, "the three pulses played before it fell (punish %s: %d)" % [punish, pulses_at_defeat])


func test_gentle_spaces_the_pulses_further() -> void:
	Settings.set_value("horror_intensity", 0)
	var d := _dummy(Vector3(0, 0, -20))
	var e := _warden(d)
	assert_almost(float(e.pulse_spacing()), 0.9 + Warden.GENTLE_PULSE_SPACING, 0.001)


# --- Filters, poise, events -----------------------------------------------------------------------------------------

func test_poise_is_the_only_stagger() -> void:
	var d := _dummy(Vector3(0, 0, -3.0))
	var e := _warden(d)
	_until(e, "telegraph", 4.0)
	e.health.apply_damage(20.0, d, Vector3.FORWARD)
	assert_eq(e.state, "telegraph", "ordinary hits never stagger it")
	for i in 4:
		e.health.apply_damage(20.0, d, Vector3.FORWARD)
	assert_eq(e.state, "stunned", "poise break (%.0f damage)" % e.poise_damage())


func test_encounter_events_bar_and_single_defeat() -> void:
	var log: Array = []
	var enc := func(id: String, on: bool) -> void:
		if id == Warden.BAR_ID:
			log.append("enc:%s" % on)
	var bar := func(id: String, hp: float, _m: float) -> void:
		if id == Warden.BAR_ID:
			log.append("bar:%d" % int(hp))
	var dead := func(id: String) -> void:
		if id == Warden.BAR_ID:
			log.append("defeated")
	Events.boss_encounter_changed.connect(enc)
	Events.boss_health_changed.connect(bar)
	Events.boss_defeated.connect(dead)
	var d := _dummy(Vector3(0, 0, -6.0))
	var e := _warden(d)
	_until(e, "chase", 3.0)
	assert_true(bool(e.engaged), "engaged")
	assert_true(log.has("enc:true"), "boss_encounter_changed(quarry_warden, true)")
	assert_true(log.has("bar:300"), "health bar shown at data hp 300")
	e.health.apply_damage(20.0, d, Vector3.FORWARD)
	assert_true(log.has("bar:290"), "bar follows the (shelled) health")
	e.health.apply_damage(9999.0, d, Vector3.FORWARD)
	assert_eq(log.count("defeated"), 1, "boss_defeated once")
	assert_true(log.has("enc:false"), "encounter ended")
	assert_true(log.has("bar:-1"), "bar hidden")
	assert_true(log.find("enc:false") < log.find("defeated"), "ended before / with the defeat")
	Events.boss_encounter_changed.disconnect(enc)
	Events.boss_health_changed.disconnect(bar)
	Events.boss_defeated.disconnect(dead)


# --- Reset policy ----------------------------------------------------------------------------------------------------

func test_krystal_defeat_resets_pillars_and_the_warden() -> void:
	_floor()
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -6.5))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_baited_charge(e, d)
	assert_eq(e.state, "exposed")
	e.health.apply_damage(100.0, d, Vector3.FORWARD)
	e.health.set_hp(150.0)
	assert_eq(int(e.phase), 2)
	Events.player_died.emit()
	assert_true(bool(pl.is_intact()), "every pillar whole again")
	assert_almost(float(e.health.hp), 300.0, 0.001, "the Warden whole again")
	assert_eq(int(e.phase), 1, "phase 1")
	assert_eq(int(e.slams_done), 0, "the lesson restarts")
	assert_false(bool(e.engaged), "bar hidden, encounter over")
	assert_eq(e.state, "return")


func test_leaving_the_leash_resets_consistently() -> void:
	var pl := _pillar(Vector3(0, 0, -9.0))
	var d := _dummy(Vector3(0, 0, -5.0))
	var e := _warden(d, Vector3.ZERO, [pl])
	_until(e, "chase", 3.0)
	pl.crack()
	e.health.apply_damage(60.0, d, Vector3.FORWARD)
	d.global_position = Vector3(0, 0, -60.0)
	_until(e, "idle", 5.0)
	assert_eq(e.state, "idle", "back home")
	assert_true(bool(pl.is_intact()), "pillars whole")
	assert_almost(float(e.health.hp), 300.0, 0.001, "whole again: never mismatched props")
	assert_false(bool(e.engaged))


func test_leaving_while_exposed_near_home_is_the_same_clean_reset() -> void:
	# The Warden stops within wander_radius + 2 of home, so when Krystal has left it goes idle straight from the
	# exposed window (no "return" leg): that must still be the full reset, never a hurt / phase-2 Warden waiting.
	_floor()
	var pl := _pillar(Vector3(0, 0, -7.0))
	var d := _dummy(Vector3(0, 0, -4.5))
	var e := _warden(d, Vector3.ZERO, [pl])
	await wait_physics(3)
	_baited_charge(e, d)
	assert_eq(e.state, "exposed", "baited into the near pillar (%s)" % e.last_charge_result)
	assert_true((e as Node3D).global_position.length() < float(e.wander_radius) + 2.0, "it stopped near home")
	# Hurt into phase 2 while it stays exposed (CH2-004: a blow that reaches the exposure cap would close the shell
	# at once and send it back to chase, and this case is about leaving while it is still exposed).
	e.health.set_hp(230.0)
	e.health.apply_damage(40.0, d, Vector3.FORWARD)
	assert_eq(e.state, "exposed", "still exposed under the cap")
	assert_eq(int(e.phase), 2, "hurt into phase 2")
	d.global_position = Vector3(0, 0, -60.0)
	var t := 0.0
	while e.state == "exposed" and t < 10.0:
		_step(e, true)
		t += DT
	_until(e, "idle", 25.0, true)
	assert_eq(e.state, "idle", "the encounter ended")
	assert_false(bool(e.engaged), "bar hidden")
	assert_true(bool(pl.is_intact()), "pillar whole again")
	assert_almost(float(e.health.hp), 300.0, 0.001, "whole again (not left at partial health)")
	assert_eq(int(e.phase), 1, "phase 1 again")
	assert_eq(int(e.slams_done), 0, "the lesson restarts")


func test_the_encounter_stays_inside_its_arena() -> void:
	_floor()
	var d := _dummy(Vector3(0, 4.6, -8.0))          # up on a ledge above the arena floor (the crystal shelf)
	var e := _warden(d)
	await wait_physics(2)
	for i in 120:
		_step(e, false)
	assert_false(bool(e.engaged), "Krystal up on the shelf never engages it")
	assert_ne(e.state, "chase")
	d.global_position = Vector3(0, 0, -8.0)
	_until(e, "chase", 3.0)
	assert_true(bool(e.engaged), "on the arena floor it engages")
	d.global_position = Vector3(0, 4.6, -8.0)
	_until(e, "idle", 6.0)
	assert_false(bool(e.engaged), "climbing out of its reach ends the encounter (no endless bar / save block)")
	d.global_position = Vector3(0, 0, -8.0)
	_until(e, "chase", 3.0)
	assert_true(bool(e.engaged))
	var bound: float = float(e.arena_radius) + Warden.ARENA_LEASH_MARGIN
	d.global_position = Vector3(0, 0, -(bound + 2.0))    # inside the data leash (30 m) but past the arena bound
	assert_true(bound + 2.0 < float(ItemDB.enemy("quarry_warden")["leash_radius"]), "the case the data leash alone misses")
	_until(e, "idle", 6.0)
	assert_false(bool(e.engaged), "walking away from the arena ends the encounter")


func test_timing_assist_stretches_its_tells_recoveries_and_pulse_beats() -> void:
	var d := _dummy(Vector3(0, 0, -20))
	var e := _warden(d)
	var base := {}
	for assist in [false, true]:
		Settings.set_value("timing_assist", assist)
		for kind in ["slam", "pulses", "charge"]:
			e.next_attack = kind
			e._choose_attack()
			base["%s_t_%s" % [kind, assist]] = float(e.telegraph_duration())
			base["%s_r_%s" % [kind, assist]] = float(e.recover_duration())
		base["spacing_%s" % assist] = float(e.pulse_spacing())
	Settings.set_value("timing_assist", false)
	for kind in ["slam", "pulses", "charge"]:
		assert_almost(float(base["%s_t_true" % kind]), float(base["%s_t_false" % kind]) * Warden.TIMING_ASSIST_MULT, 0.001, "%s wind-up x assist" % kind)
		assert_almost(float(base["%s_r_true" % kind]), float(base["%s_r_false" % kind]) * Warden.TIMING_ASSIST_MULT, 0.001, "%s recovery x assist" % kind)
	assert_almost(float(base["slam_t_false"]), 1.4, 0.001, "off: the data wind-up exactly")
	assert_almost(float(base["spacing_true"]), 0.9 * Warden.TIMING_ASSIST_MULT, 0.001, "pulse beats spaced further apart")


# --- The real arena ----------------------------------------------------------------------------------------------------

func _arena(d: Node3D) -> Node3D:
	var a: Node3D = ArenaScript.new()
	a.setup({"radius": Q.ARENA_RADIUS, "pillars": [Vector3(4, 0, -5), Vector3(4, 0, 5), Vector3(-5, 0, 0)]})
	a.position = Vector3(50.0, 0.0, 50.0)
	add_child(a)
	_nodes.append(a)
	a.player_override = d
	return a


func _spawn_in(a: Node3D, d: Node3D) -> Node:
	var sp: Node3D = a.spawner
	sp.player_override = d
	sp.ignore_safe_zones = true
	Game.mode = "playing"
	sp.update_spawner()
	if sp.alive.is_empty():
		return null
	var w: Node = sp.alive[0]
	w.set_physics_process(false)
	w.target_override = d
	return w


func test_arena_hands_over_pillars_and_defeat_commits_first() -> void:
	var d := _dummy(Vector3(52, 0, 52))
	var a := _arena(d)
	await wait_frames(2)
	var w := _spawn_in(a, d)
	assert_not_null(w, "the arena spawner now spawns the real Warden")
	if w == null:
		return
	assert_eq(String(w.enemy_id), "quarry_warden")
	assert_eq((w.pillars as Array).size(), 3, "the three arena pillars handed over")
	assert_eq(int(w.intact_pillars()), 3)
	assert_true((w.arena_center as Vector3).is_equal_approx(a.global_position), "arena centre")
	assert_eq(w.arena, a, "arena node")
	a.pillars[0].crack()
	# QA CHAIN-002: no defeat before its shell was cracked open once - the pillar exposure (the charge into pillar 0
	# above) opens it, then the finishing blow may land.
	w._expose()
	w._end_exposure(false)
	var captions: Array = []
	var cb := func(text: String) -> void: captions.append([text, bool(GameState.get_flag(Q.FLAG_WARDEN))])
	Events.caption.connect(cb)
	w.drops_enabled = false
	w.health.apply_damage(9999.0, d, Vector3.FORWARD)
	Events.caption.disconnect(cb)
	assert_true(bool(GameState.get_flag(Q.FLAG_WARDEN)), "hr_warden_defeated committed")
	assert_true(bool(GameState.get_flag("spawner_cleared_" + Q.WARDEN_SPAWNER)), "the spawner's clear flag")
	assert_true(captions.size() >= 1, "a defeat caption was shown")
	for c in captions:
		assert_true(bool(c[1]), "every caption / presentation came AFTER the flag was committed (%s)" % c[0])
	assert_eq(int(a.intact_pillars()), 3, "the arena re-knits its pillars after the victory")
	Game.mode = "playing"
	a.spawner.update_spawner()
	assert_eq(a.spawner.alive.size(), 0, "a defeated Warden never respawns")


func test_retry_after_krystal_falls_starts_fresh() -> void:
	var d := _dummy(Vector3(52, 0, 52))
	var a := _arena(d)
	await wait_frames(2)
	var w := _spawn_in(a, d)
	assert_not_null(w)
	if w == null:
		return
	w.health.apply_damage(100.0, d, Vector3.FORWARD)
	a.pillars[1].crack()
	Events.player_died.emit()
	assert_eq(int(a.intact_pillars()), 3, "pillars reset on retry")
	await wait_frames(2)
	assert_false(is_instance_valid(w), "the living Warden left (fresh next attempt)")
	assert_false(bool(GameState.get_flag(Q.FLAG_WARDEN)), "no progress was granted")
	var w2 := _spawn_in(a, d)
	assert_not_null(w2, "a fresh Warden on the next approach")
	if w2 != null:
		assert_almost(float(w2.health.hp), 300.0, 0.001, "at full health")
