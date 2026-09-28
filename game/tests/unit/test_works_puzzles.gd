extends "res://tests/test_case.gd"
## The three ward-line puzzles of the Hushed Works: the pure state machines (every state reachable, no timer,
## no irreversible fail, a wrong move only restarts), then the real nodes in the built area: solving from any
## state, in any order of lines, with independent flags; the lower ward door opens only with all three; the
## Light Well's reset lever and the alcove it reveals; visual state that does not depend on sound.

const Layout := preload("res://data/works_layout.gd")
const Puzzles := preload("res://src/world/works/works_puzzles.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"
const LINES := ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]
const WATER_Y := -19.86

var area: Node3D = null


var _saved_hv: Variant = false


func before_each() -> void:
	fresh_state()
	_saved_hv = Settings.get_value("high_visibility_cues")


func after_each() -> void:
	Settings.set_value("high_visibility_cues", _saved_hv)
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	a.use_deep = false
	add_child(a)
	await wait_physics(2)
	return a


# --- Pure state machines -------------------------------------------------------------------------------------------------

func test_sluice_state_machine() -> void:
	var solved := 0
	for a in 2:
		for b in 2:
			var f := Puzzles.sluice_flow(a, b)
			assert_true(bool(f["drain"]) or bool(f["middle"]), "water always goes somewhere (%d,%d)" % [a, b])
			if Puzzles.sluice_solved(a, b):
				solved += 1
				assert_true(bool(f["ward"]), "solved = water in the ward basin")
			else:
				assert_false(bool(f["ward"]), "(%d,%d) does not reach the basin" % [a, b])
	assert_eq(solved, 1, "exactly one solution")
	assert_eq(Puzzles.valve_next(0), 1)
	assert_eq(Puzzles.valve_next(1), 0, "a valve always turns back: nothing is irreversible")
	assert_false(Puzzles.sluice_solved(int(Puzzles.SLUICE_START[0]), int(Puzzles.SLUICE_START[1])), "does not start solved")
	# From every start state, at most two turns solve it.
	for a in 2:
		for b in 2:
			var aa := a
			var bb := b
			if aa != 1:
				aa = Puzzles.valve_next(aa)
			if bb != 1:
				bb = Puzzles.valve_next(bb)
			assert_true(Puzzles.sluice_solved(aa, bb), "reachable from (%d,%d)" % [a, b])


func test_bell_order_state_machine() -> void:
	var order: Array = Layout.BELL_ORDER
	assert_eq(order.size(), 4)
	for s in order:
		assert_true(Layout.BELLS.has(s), "bell %s has a striker" % s)
		assert_true(Layout.BELL_NAMES.has(s), "bell %s has a caption name" % s)
	var p := 0
	var r: Dictionary
	for i in order.size():
		r = Puzzles.bell_step(p, String(order[i]))
		p = int(r["progress"])
	assert_eq(String(r["result"]), "solved")
	assert_eq(p, 4)
	assert_eq(String(Puzzles.bell_step(4, "leaf")["result"]), "ignored", "nothing changes after solving")
	# A wrong strike never locks anything: it only restarts (or restarts at 1 when it is the first symbol).
	r = Puzzles.bell_step(2, "flame")
	assert_eq(String(r["result"]), "reset")
	assert_eq(int(r["progress"]), 0)
	r = Puzzles.bell_step(2, String(order[0]))
	assert_eq(int(r["progress"]), 1, "the first symbol starts a fresh attempt")
	assert_eq(String(Puzzles.bell_step(1, "nonsense")["result"]), "ignored")
	# Any sequence of mistakes followed by the order solves it.
	var seq := ["flame", "key", "leaf", "leaf", "moon", "flame"]
	p = 0
	for s in seq:
		p = int(Puzzles.bell_step(p, s)["progress"])
	for s in order:
		r = Puzzles.bell_step(p, String(s))
		p = int(r["progress"])
	assert_eq(String(r["result"]), "solved", "the order always works, whatever came before")


func test_light_well_state_machine() -> void:
	var solutions := 0
	for a in 4:
		for b in 4:
			var path := Puzzles.beam_path(a, b)
			assert_true((path["hits"] as Array).has("a"), "daylight always reaches mirror A")
			if bool(path["solved"]):
				solutions += 1
				assert_eq(path["hits"], ["a", "b", "target"])
	assert_eq(solutions, 1, "exactly one solution")
	assert_true(Puzzles.beam_solved(1, 2))
	assert_false(Puzzles.beam_solved(int(Puzzles.MIRROR_START[0]), int(Puzzles.MIRROR_START[1])), "does not start solved")
	var d := 0
	for i in 4:
		d = Puzzles.mirror_next(d)
	assert_eq(d, 0, "four quarter turns come back round")
	# Geometry matches the logic: B east of A, the crystal south of B.
	var pa: Vector3 = Layout.LIGHTWELL["mirror_a"]
	var pb: Vector3 = Layout.LIGHTWELL["mirror_b"]
	var pt: Vector3 = Layout.LIGHTWELL["target"]
	assert_true(absf(pa.z - pb.z) < 0.01 and pb.x > pa.x, "mirror B lies east of A")
	assert_true(absf(pb.x - pt.x) < 0.01 and pt.z > pb.z, "the crystal lies south of B")


# --- Real nodes ---------------------------------------------------------------------------------------------------------------

func test_sluice_node_solves_and_stays() -> void:
	area = await _make_area()
	var s: Node = area.sluice
	assert_false(bool(s.solved))
	assert_false(bool(GameState.get_flag("ch2_line_water")))
	# Wrong combination first: water in the drain, never the basin.
	s.turn(1)
	assert_false(bool(s.flow()["ward"]))
	s.turn(1)
	s.turn(0)
	assert_true(bool(s.flow()["middle"]), "the middle channel fills")
	assert_false(bool(GameState.get_flag("ch2_line_water")), "not yet")
	s.turn(1)
	assert_true(bool(GameState.get_flag("ch2_line_water")), "water line restored")
	assert_true(bool(s.solved))
	assert_false(s.turn(0), "valves stay put once the line flows")
	assert_false(bool(GameState.get_flag("ch2_line_bell")) or bool(GameState.get_flag("ch2_line_light")), "lines are independent")
	# The visible state: water planes up in the ward channel, the arrows point at the basin.
	var ward: Array = s.get("_water")["ward"]
	await wait_seconds(1.4)
	assert_almost((ward[0] as Node3D).position.y, WATER_Y, 0.02, "the ward channel shows water")
	# Interaction text names the destination; after solving it is disabled with a reason.
	var valve := area.find_child("ValveA", true, false)
	var it: Node = valve.get_node("Turn")
	assert_false(bool(it.get_interaction(null)["enabled"]))


func test_bells_node_order_with_mistakes() -> void:
	area = await _make_area()
	var b: Node = area.bells
	assert_eq(b.strike("flame"), "reset")
	assert_eq(b.strike("leaf"), "advance")
	assert_eq(b.strike("moon"), "advance")
	assert_eq(b.strike("flame"), "reset", "a wrong bell restarts")
	assert_eq(int(b.progress), 0)
	for s in Layout.BELL_ORDER:
		b.strike(String(s))
	assert_true(bool(GameState.get_flag("ch2_line_bell")), "bell line restored")
	assert_eq(b.strike("leaf"), "ignored", "solved stays solved")
	var lit := 0
	for n in b.get("_board_on"):
		if (n as Node3D).visible:
			lit += 1
	assert_eq(lit, 4, "all four plaque lamps lit (visible, not audio)")


func test_light_well_node_reset_and_alcove() -> void:
	area = await _make_area()
	var lw: Node = area.lightwell
	var door: Node = area.doors["alcove_shutter"]
	assert_false(bool(door.is_open), "alcove shut")
	lw.turn(0)
	lw.turn(0)
	lw.turn(1)
	assert_eq(lw.mirrors, [2, 0])
	lw.reset()
	assert_eq(lw.mirrors, Puzzles.MIRROR_START, "the lever sets both mirrors back")
	assert_eq(int(lw.resets), 1)
	# Solve from the start: A to east (1 turn), B to south (3 turns from west).
	lw.turn(0)
	for i in 3:
		lw.turn(1)
	assert_true(bool(GameState.get_flag("ch2_line_light")), "light line restored")
	assert_true(bool(lw.solved))
	assert_true(bool(door.is_open), "the shutter lifts for the alcove")
	assert_true(bool(lw.get("_crystal_glow").visible), "the crystal blazes")
	assert_false(lw.turn(0), "mirrors stay once solved")


func test_lines_in_any_order_open_the_ward_door_only_with_all_three() -> void:
	var orders := [[0, 1, 2], [2, 0, 1], [1, 2, 0]]
	for order in orders:
		fresh_state()
		area = await _make_area()
		var gate: Node = area.doors["ward_gate"]
		for k in 3:
			assert_false(bool(gate.is_open), "shut before line %d of %s" % [k, str(order)])
			_solve_line(int(order[k]))
		assert_true(bool(gate.is_open), "all three lines open it (%s)" % str(order))
		area.queue_free()
		area = null
		await wait_frames(2)


func _solve_line(i: int) -> void:
	match i:
		0:
			area.sluice.turn(0)
			area.sluice.turn(1)
		1:
			for s in Layout.BELL_ORDER:
				area.bells.strike(String(s))
		2:
			area.lightwell.turn(0)
			for k in 3:
				area.lightwell.turn(1)
	assert_true(bool(GameState.get_flag(LINES[i])), "line %s solved through its node" % LINES[i])


func test_ward_door_names_the_missing_lines() -> void:
	area = await _make_area()
	var gate: Node = area.doors["ward_gate"]
	var t: Dictionary = gate.get_interaction(null)
	assert_false(bool(t["enabled"]))
	for n in ["water", "bell", "light"]:
		assert_true(String(t["reason"]).contains(n), "reason names the %s line" % n)
	GameState.set_flag("ch2_line_bell", true)
	t = gate.get_interaction(null)
	assert_false(String(t["reason"]).contains("bell"), "a restored line is no longer named")
	# glyphs light one by one (visible cue)
	var glyphs: Dictionary = gate.get("_glyphs")
	assert_true((glyphs["ch2_line_bell"]["on"] as Node3D).visible)
	assert_false((glyphs["ch2_line_water"]["on"] as Node3D).visible)


func test_solved_state_restores_on_load() -> void:
	for f in LINES:
		GameState.set_flag(f, true)
	area = await _make_area()
	assert_true(bool(area.sluice.solved) and bool(area.bells.solved) and bool(area.lightwell.solved), "puzzles show solved")
	assert_eq(area.lightwell.mirrors, [1, 2], "mirrors at the solution")
	assert_true(bool(area.doors["ward_gate"].is_open), "ward door open")
	assert_true(bool(area.doors["alcove_shutter"].is_open), "alcove open")
	var conduits: Dictionary = area.get("_conduit_nodes")
	for f in LINES:
		assert_true(((conduits[f] as Array)[0] as Node3D).visible, "%s conduit glows" % f)


func test_high_visibility_markers() -> void:
	Settings.set_value("high_visibility_cues", true)
	area = await _make_area()
	var markers: Array = area.sluice.get("_markers")
	assert_true((markers[0] as Node3D).visible, "valve rings shown with high-visibility cues")
	var rings: Array = area.bells.get("_next_rings")
	assert_true((rings[0] as Node3D).visible, "the next plaque symbol is ringed")
	assert_false((rings[1] as Node3D).visible)
	Settings.set_value("high_visibility_cues", false)
	await wait_frames(1)
	assert_false((markers[0] as Node3D).visible, "hidden again when the setting is off")
