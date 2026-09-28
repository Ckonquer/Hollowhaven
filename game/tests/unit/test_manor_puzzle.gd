extends "res://tests/test_case.gd"
## Moonveil Manor puzzles and the candle API: the ballroom candle-routing state machine (pure logic and the
## real node: hearth candle needs the Lantern, turning, reset, solving once, persistence through the flag),
## the ward candle API the Count Velour boss module uses (is_lit / light / darken / signals / pools /
## light_source contract), the sealed Gallery doors opening on the solve, and no timing anywhere.

const Layout := preload("res://data/manor_layout.gd")
const Route := preload("res://src/world/manor/candle_route.gd")
const PuzzleScript := preload("res://src/world/manor/candle_route_puzzle.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const Combat := preload("res://src/combat/combat.gd")
const SCENE := "res://scenes/moonveil_manor.tscn"

var _nodes: Array = []
var _saved_hv: Variant = null


func before_each() -> void:
	fresh_state()
	GameState.give_item("lantern", 1)
	_saved_hv = Settings.get_value("high_visibility_cues")


func after_each() -> void:
	Settings.set_value("high_visibility_cues", _saved_hv)
	for n in _nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	await wait_frames(2)


func _add(n: Node) -> Node:
	add_child(n)
	_nodes.append(n)
	return n


# --- Pure logic ------------------------------------------------------------------------------------------------

func test_route_logic_initial_state_and_solutions() -> void:
	var p: Dictionary = Layout.PUZZLE
	var arms := Route.initial_arms(p)
	assert_eq(arms.keys().size(), 4, "four candelabra")
	var dark := Route.trace(p, arms, false)
	assert_eq(dark["lit"], [], "nothing burns before the hearth candle is lit")
	var t := Route.trace(p, arms, true)
	assert_eq(t["lit"], ["c1", "c3"], "the flame reaches c1 then c3, whose hand points back")
	assert_false(bool(t["solved"]), "not solved at the start")
	assert_eq(Route.min_turns(p, arms), 2, "the shortest solve needs two turns (short, but a real choice)")
	var sol := Route.solution(p)
	assert_false(sol.is_empty(), "a solution exists")
	assert_true(bool(Route.trace(p, sol, true)["solved"]), "the stored solution solves")
	# Every arm target is a real node or the lock, and every runner joins two real points.
	for id in Route.node_ids(p):
		for target in p["nodes"][id]["arms"]:
			assert_true(p["nodes"].has(target) or String(target) == "T", "%s points at a real place (%s)" % [id, target])
	assert_eq(Route.runners(p).size(), 6, "six gilt runners")


func test_route_logic_turns_loops_and_reset() -> void:
	var p: Dictionary = Layout.PUZZLE
	var arms := Route.initial_arms(p)
	arms = Route.turned(p, arms, "c3")
	assert_eq(Route.arm_target(p, arms, "c3"), "c4")
	var t := Route.trace(p, arms, true)
	assert_eq(t["lit"], ["c1", "c3", "c4"], "the flame walks on to c4")
	assert_false(bool(t["solved"]))
	arms = Route.turned(p, arms, "c4")
	assert_eq(Route.arm_target(p, arms, "c4"), "T")
	assert_true(bool(Route.trace(p, arms, true)["solved"]), "c4 -> the crescent lock solves it")
	# The other road works too, and a loop simply stops (no infinite walk).
	var b := Route.initial_arms(p)
	b = Route.turned(p, b, "c1")             # c1 -> c2
	b = Route.turned(p, b, "c2")             # c2 -> c4
	var lp := Route.trace(p, b, true)
	assert_eq(lp["lit"], ["c1", "c2", "c4", "c3"], "c4 still points at c3; c3 points back to c1 (already lit) and stops")
	assert_false(bool(lp["solved"]))
	b = Route.turned(p, b, "c4")
	assert_true(bool(Route.trace(p, b, true)["solved"]), "second route solves")
	# Arms cycle around.
	var c := Route.initial_arms(p)
	for i in 3:
		c = Route.turned(p, c, "c4")
	assert_eq(int(c["c4"]), 0, "three turns bring c4 back")


# --- The real puzzle node ---------------------------------------------------------------------------------------

func test_puzzle_node_state_machine_with_reset_and_solve_once() -> void:
	var pz: Node3D = _add(PuzzleScript.new())
	await wait_frames(1)
	var solved_signals := [0]
	pz.connect("solved_now", func() -> void: solved_signals[0] += 1)
	assert_false(bool(pz.call("is_solved")))
	assert_eq(pz.call("lit_nodes"), [], "dark before the hearth candle")
	# The hearth candle: lit through its own interaction, which needs the Lantern (no timing, no hold).
	var hearth: Node3D = pz.get("source_candle")
	assert_true(bool(hearth.get_interaction(null)["enabled"]), "lightable with the Lantern")
	hearth.interact(null)
	assert_true(bool(pz.get("source_lit")), "hearth lit -> the flame starts walking")
	assert_eq(pz.call("lit_nodes"), ["c1", "c3"])
	# Visual state follows the logic: lit candelabra, glowing runners.
	var cands: Dictionary = pz.get("candelabra")
	assert_true(bool(cands["c1"].call("is_lit")) and bool(cands["c3"].call("is_lit")), "c1 and c3 glow")
	assert_false(bool(cands["c2"].call("is_lit")), "c2 stays dark")
	# Turning via the candelabrum interactions.
	assert_eq(String(cands["c3"].get_interaction(null)["text"]), "Turn the candelabrum")
	cands["c3"].interact(null)
	assert_eq(pz.call("lit_nodes"), ["c1", "c3", "c4"])
	# Reset brings every hand back (the hearth stays lit).
	var lever: Node3D = pz.get("reset_lever")
	assert_true(bool(lever.get_interaction(null)["enabled"]))
	lever.interact(null)
	assert_eq(pz.get("arms"), Route.initial_arms(Layout.PUZZLE), "reset restored the arms")
	assert_eq(int(pz.get("resets")), 1)
	assert_true(bool(pz.get("source_lit")), "reset keeps the hearth candle burning")
	assert_eq(pz.call("lit_nodes"), ["c1", "c3"])
	# Solve.
	assert_false(bool(GameState.get_flag(Layout.FLAG_BALLROOM_SOLVED)))
	pz.call("turn", "c3")
	pz.call("turn", "c4")
	assert_true(bool(pz.call("is_solved")), "solved")
	assert_true(bool(GameState.get_flag(Layout.FLAG_BALLROOM_SOLVED)), "flag mm_ballroom_solved")
	assert_eq(solved_signals[0], 1, "solved_now once")
	# Once solved nothing turns or resets any more.
	assert_false(bool(pz.call("turn", "c1")), "no turning after the solve")
	assert_false(bool(pz.call("reset")), "no reset after the solve")
	assert_false(bool(cands["c1"].get_interaction(null)["enabled"]))
	assert_eq(solved_signals[0], 1, "still once")


func test_puzzle_without_lantern_explains_why() -> void:
	GameState.take_item("lantern", 1)
	var pz: Node3D = _add(PuzzleScript.new())
	await wait_frames(1)
	var hearth: Node3D = pz.get("source_candle")
	var info: Dictionary = hearth.get_interaction(null)
	assert_false(bool(info["enabled"]), "greyed without a Lantern")
	assert_true(String(info.get("reason", "")).contains("Lantern"), "and says why")
	hearth.interact(null)
	assert_false(bool(pz.get("source_lit")), "nothing lit")


func test_solved_puzzle_is_restored_from_the_flag() -> void:
	GameState.set_flag(Layout.FLAG_BALLROOM_SOLVED, true)
	var pz: Node3D = _add(PuzzleScript.new())
	await wait_frames(1)
	assert_true(bool(pz.call("is_solved")), "solved on load")
	assert_true(bool(pz.call("trace")["solved"]), "the candelabra show a finished route")
	assert_true(bool(pz.get("source_candle").call("is_lit")), "the hearth candle burns")


func test_gallery_doors_open_when_the_puzzle_is_solved_in_the_manor() -> void:
	var ps: PackedScene = load(SCENE)
	var area: Node3D = _add(ps.instantiate())
	await wait_physics(2)
	var door: Node3D = area.get("gallery_door")
	assert_false(bool(door.call("is_open")), "sealed at first")
	assert_false(bool(door.get_interaction(null)["enabled"]), "greyed prompt")
	assert_true(String(door.get_interaction(null)["reason"]).contains("crescent"), "the prompt explains the crescent lock")
	var pz: Node3D = area.get("puzzle")
	pz.call("light_source", null)
	pz.call("turn", "c3")
	pz.call("turn", "c4")
	await wait_physics(2)
	assert_true(bool(door.call("is_open")), "the Gallery doors open")
	var blocker: CollisionShape3D = door.get_node("Blocker").get_child(0)
	assert_true(blocker.disabled, "and stop blocking")


# --- Ward candles (boss API) --------------------------------------------------------------------------------------

func test_ward_candle_api_for_the_boss_module() -> void:
	var c: Node3D = WardCandle.new()
	c.setup({"id": "north", "lit": true, "pool_radius": 3.2})
	_add(c)
	c.position = Vector3(40, 0, 40)
	await wait_frames(1)
	assert_true(c.is_in_group("ward_candle") and c.is_in_group("light_source"), "groups")
	assert_true(bool(c.call("is_lit")), "starts lit")
	var events: Array = []
	c.connect("lit", func(n: Node3D) -> void: events.append(["lit", n]))
	c.connect("darkened", func(n: Node3D) -> void: events.append(["dark", n]))
	c.connect("state_changed", func(n: Node3D, on: bool) -> void: events.append(["state", on]))
	assert_true(c.call("in_pool", Vector3(41.5, 0, 41.5)), "inside the lit pool")
	assert_false(c.call("in_pool", Vector3(44, 0, 44)), "outside the pool")
	assert_true(Combat.light_at(Vector3(40, 0.5, 40)) > 0.9, "a lit candle lights its pool (light_source contract)")
	var boss := Node3D.new()
	assert_true(bool(c.call("darken", boss)), "the Count can darken it")
	assert_false(bool(c.call("darken", boss)), "darkening twice changes nothing")
	assert_eq(c.get("last_source"), boss, "remembers who did it")
	assert_false(bool(c.call("is_lit")))
	assert_false(c.call("in_pool", Vector3(40.5, 0, 40.5)), "no pool while dark")
	assert_almost(Combat.light_at(Vector3(40, 0.5, 40)), 0.0, 0.001, "no light while dark")
	assert_true(bool(c.get_interaction(null)["enabled"]), "relightable by Krystal")
	c.interact(null)
	assert_true(bool(c.call("is_lit")), "relit with the Lantern (instant, no hold)")
	assert_eq(events.map(func(e: Array) -> String: return str(e[0])), ["dark", "state", "lit", "state"], "signals in order")
	assert_false(bool(c.get_interaction(null)["enabled"]), "a lit candle can't be put out by Krystal")
	c.call("set_interactable", false)
	assert_eq(c.get_interaction(null), {}, "a scripted beat can hide the prompt")
	boss.free()


func test_high_visibility_adds_a_bold_pool_ring() -> void:
	Settings.set_value("high_visibility_cues", false)
	var c: Node3D = WardCandle.new()
	c.setup({"id": "hv", "lit": true})
	_add(c)
	await wait_frames(1)
	var bold: Node3D = c.get_node("BoldPool")
	assert_false(bold.visible, "subtle by default")
	Settings.set_value("high_visibility_cues", true)
	assert_true(bold.visible, "bold ring with high_visibility_cues (live)")
	var beckon: Node3D = c.get_node("BoldBeckon")
	assert_false(beckon.visible, "no 'light me' ring on a lit candle")
	c.call("darken", null)
	assert_true(beckon.visible, "a dark candle waiting to be lit gets a bold ring")
	assert_false(bold.visible, "and no pool ring")
	c.call("set_interactable", false)
	assert_false(beckon.visible, "not while a scripted beat owns the candle")
	c.call("set_interactable", true)
	Settings.set_value("high_visibility_cues", false)
	assert_false(beckon.visible, "subtle again when the setting is off")


func test_arena_candles_are_exposed_by_the_area() -> void:
	var ps: PackedScene = load(SCENE)
	var area: Node3D = _add(ps.instantiate())
	await wait_physics(2)
	var cands: Array = area.get("arena_candles")
	assert_eq(cands.size(), 3, "three ward candles in the Gallery")
	var c: Vector3 = Layout.ARENA["center"]
	for wc in cands:
		var d := Vector2((wc as Node3D).global_position.x - c.x, (wc as Node3D).global_position.z - c.z).length()
		assert_true(d > 5.0 and d < float(Layout.ARENA["radius"]) - 2.0, "candle %s inside the arena, away from the centre (%.1f m)" % [wc.get("candle_id"), d])
	assert_eq((area.get("curtains") as Array).size(), 5, "curtain markers")
	assert_not_null(area.get("fixture"), "central fixture")
	assert_eq((area.get("cover_points") as Array).size(), 4, "visible cover")
	assert_true(cands.has(area.get("teach_candle")), "the teaching candle is one of the three")
	# Missing boss script (this wave): the candles start dark so the fallback can be completed by hand.
	if not preload("res://src/enemies/enemy_factory.gd").can_spawn("count_velour"):
		assert_true(bool(area.get("boss_missing")), "boss missing is detected")
		for wc in cands:
			assert_false(bool(wc.call("is_lit")), "fallback: candles wait to be lit")
	else:
		# With the Count: two burn, the teaching candle waits for Krystal (MP §13.1).
		for wc in cands:
			assert_eq(bool(wc.call("is_lit")), wc != area.get("teach_candle"), "only the teaching candle waits dark")
