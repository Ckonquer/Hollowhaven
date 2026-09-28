extends "res://tests/unit/test_boss_choir_harness.gd"
## CH2-014: Phase B "Stolen rhythm" needs only the resonator plates. The Choir switches the lantern anchors off for the
## whole phase (lantern_anchor.gd `enabled`: no prompt, no focus, a raise is refused) - in the real vault the east
## anchor stands ~2.3 m from the east resonator's Leaf plate and used to take the interaction focus from it during the
## 12 s sequence. Phases A / C, a reset (death / leaving), a dismissal, a mid-fight teardown and the victory switch
## them back on (the arena's default state).

const HP := 5000.0
const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const Probe := preload("res://src/player/interaction_probe.gd")


func _enabled(list: Array) -> Array:
	var out: Array = []
	for a in list:
		out.append(bool((a as Node).get("enabled")))
	return out


func _to_phase_c(b: Node, rs: Array) -> void:
	for r in rs:
		strike_sequence(r)
	assert_true(until(b, "b_exposed") >= 0.0, "both resonators = exposed")
	b.health.apply_damage(99999.0, b.target_override)
	assert_true(until(b, "c_gather") >= 0.0, "phase C begins")


func test_phase_b_switches_the_anchors_off_and_phase_c_back_on() -> void:
	make_arena()
	var d := dummy(Vector3(-9.0, 0, 0), false, HP)
	var b := make_boss(d)
	start_in_phase(b, 1)
	assert_true(until(b, "a_gather") >= 0.0, "phase A")
	assert_eq(_enabled(anchors), [true, true, true], "phase A: the anchors answer")
	b.queue_free()
	await wait_frames(1)
	var b2 := make_boss(d)
	start_in_phase(b2, 2)
	assert_true(until(b2, "b_gather") >= 0.0, "phase B begins")
	assert_eq(_enabled(anchors), [false, false, false], "phase B: every anchor switched off")
	for a in anchors:
		assert_eq((a as Node).call("get_interaction", d), {}, "no anchor prompt in phase B")
		assert_false(bool((a as Node).call("raise", null)), "a raise is refused")
		assert_false(bool((a as Node).call("is_raised")))
	assert_true(until(b2, "b_idle") >= 0.0)
	assert_eq(_enabled(anchors), [false, false, false], "still off through the whole phase")
	_to_phase_c(b2, resonators)
	assert_eq(_enabled(anchors), [true, true, true], "phase C: the kept flame needs the anchors again")
	assert_eq(String(((anchors[0] as Node).call("get_interaction", d) as Dictionary).get("text", "")), "Raise your lantern at the anchor")


func test_resets_and_teardowns_switch_the_anchors_back_on() -> void:
	make_arena()
	var d := dummy(Vector3(3, 0, -4), false, HP)
	var b := make_boss(d)
	start_in_phase(b, 2)
	assert_true(until(b, "b_gather") >= 0.0)
	assert_eq(_enabled(anchors), [false, false, false])
	Events.player_died.emit()
	assert_eq(String(b.state), "dormant", "she fell: the encounter resets")
	assert_eq(_enabled(anchors), [true, true, true], "a reset puts the anchors back to their default")
	b.start_fight()
	assert_true(until(b, "b_gather", 3.0) >= 0.0, "the retry picks phase B up again")
	assert_eq(_enabled(anchors), [false, false, false], "and switches them off again")
	# a Choir freed mid-phase (trial teardown, a failing script) never leaves them off
	b.free()
	assert_eq(_enabled(anchors), [true, true, true], "a mid-fight teardown restores them")
	# a flag set elsewhere dismisses the Choir quietly: the anchors come back too
	var b3 := make_boss(d)
	start_in_phase(b3, 2)
	assert_true(until(b3, "b_gather") >= 0.0)
	assert_eq(_enabled(anchors), [false, false, false])
	GameState.set_flag("ch2_choir_defeated", true)
	assert_true(bool(b3.is_gone()), "dismissed")
	assert_eq(_enabled(anchors), [true, true, true], "a dismissal restores them")


## The QA spot in the REAL vault (choir_arena.gd layout): Krystal in front of the east resonator's Leaf plate, 2.2 m
## from the east anchor. Facing the plate focuses the plate; in phase B no facing at all focuses an anchor; in
## phase C the same spot facing the anchor focuses it again.
func test_in_the_real_vault_the_east_anchor_never_takes_the_plates_focus_in_phase_b() -> void:
	var arena: Node3D = ChoirArena.new()
	arena.set("save_on_clear", false)
	add_child(arena)
	var ans: Array = arena.call("anchor_nodes")
	var rs: Array = arena.call("resonator_nodes")
	var east_anchor: Node3D = ans[1]
	var leaf: Node3D = (rs[1] as Node).get_node("Plate_leaf/Strike_leaf")
	var spot := Vector3(165.0, -32.0, 62.5)
	assert_almost(Vector2(spot.x - east_anchor.global_position.x, spot.z - east_anchor.global_position.z).length(), 2.18, 0.05,
		"the QA spot is ~2.2 m from the east anchor")
	var d := dummy(spot, false, HP)
	Base.reset_attack_tokens()
	var b: Node = Factory.create(BOSS_ID, arena.call("boss_params"), arena.call("arena_center"))
	add_child(b)
	b.set_process(false)
	b.target_override = d
	b.intensity_override = 1
	b.fast_defeat = true
	start_in_phase(b, 2)
	assert_true(until(b, "b_gather") >= 0.0, "phase B")
	for w in b.wisp_nodes():
		(w as Node).set_physics_process(false)
	var probe: Node = Probe.new()
	probe.set("player", d)
	add_child(probe)
	probe.set_physics_process(false)
	await wait_physics(3)
	var to_leaf := leaf.global_position - spot
	d.look_at(spot + Vector3(to_leaf.x, 0.0, to_leaf.z).normalized(), Vector3.UP)
	probe.call("refresh")
	assert_eq(probe.get("focus"), leaf, "facing the Leaf plate focuses it")
	assert_eq(String((probe.get("focus_interaction") as Dictionary).get("text", "")), "Strike the Leaf plate")
	var stolen: Array = []
	for k in 24:
		var ang := TAU * float(k) / 24.0
		d.look_at(spot + Vector3(cos(ang), 0.0, sin(ang)), Vector3.UP)
		probe.call("refresh")
		if ans.has(probe.get("focus")):
			stolen.append(k * 15)
	assert_eq(stolen, [], "phase B: no facing at this spot focuses a lantern anchor (degrees %s)" % str(stolen))
	_to_phase_c(b, rs)
	var to_anchor := east_anchor.global_position - spot
	d.look_at(spot + Vector3(to_anchor.x, 0.0, to_anchor.z).normalized(), Vector3.UP)
	probe.call("refresh")
	assert_eq(probe.get("focus"), east_anchor, "phase C: facing the anchor focuses it again")
	probe.queue_free()
	b.queue_free()
	arena.queue_free()
	await wait_frames(2)
