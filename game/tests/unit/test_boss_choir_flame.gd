extends "res://tests/unit/test_boss_choir_harness.gd"
## The Borrowed Choir, Phase C "The kept flame" (MP §13.3): the true flame hangs on a fixed anchor hook and is a
## real light (Combat.light_at), the false cozy lights light nothing; the hush is marked (1.0-1.4 s), strikes every
## unlit place inside the ring once and spares the true flame's lit sector and the perimeter walk; raising the
## lantern at the true flame's anchor exposes the Choir (a raise during the hush waits for it to pass), a wrong
## anchor only answers with a caption; EXACTLY three exposures end the fight - strong gear only shortens windows;
## Intense feints the flame toward another hook first; Gentle lights a wider sector; the bold high-visibility
## markers follow the setting.

const HP := 5000.0


func _phase_c(intensity: int = 1, pos: Vector3 = Vector3(0, 0, -9)) -> Node:
	var d := dummy(pos, false, HP)
	var b := make_boss(d, intensity)
	start_in_phase(b, 3)
	assert_true(until(b, "c_gather") >= 0.0, "phase C begins")
	return b


static func _lights_in(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _lights_in(ch)
	return c


func _expose_once(b: Node) -> void:
	assert_true(until(b, "c_open") >= 0.0, "the flame settles and the hush passes")
	raise(int(b.flame_anchor))
	assert_eq(String(b.state), "c_exposed", "the lantern at the true flame's anchor exposes it")


func test_true_flame_is_anchored_real_light_and_false_lights_light_nothing() -> void:
	make_arena()
	var b := _phase_c()
	assert_true(until(b, "c_hush_tele") >= 0.0)
	var k := int(b.flame_anchor)
	assert_true(k >= 0 and k < 3, "the flame hangs on one of the three fixed anchors")
	var lt: Node = b.lights
	assert_true(bool(lt.get("settled")))
	var hook: Vector3 = b.hook_pos(k)
	assert_true((lt.call("flame_position") as Vector3).distance_to(hook) < 0.05, "on its anchor's hook")
	assert_true(bool(lt.call("flame_is_light")), "the kept flame is a light source")
	Combat.invalidate_light_cache()
	assert_true(Combat.light_at(Vector3(hook.x, 0.6, hook.z)) > 0.3, "it really lights the floor under it")
	assert_eq(int(lt.call("false_count")), int(Rules.FALSE_LIGHTS[1]), "Standard: two false cozy lights")
	for f in lt.call("false_lights_nodes"):
		var fn: Node3D = f
		if not fn.visible:
			continue
		assert_eq(_lights_in(fn), 0, "a false light has no Light3D")
		assert_false(fn.is_in_group("light_source"), "and is no light source")
		assert_true(Combat.light_at(Vector3(fn.global_position.x, 0.6, fn.global_position.z)) < 0.05, "its floor stays dark")
	for f in b.forms:
		assert_false((f as Node3D).visible, "no phase A forms linger")


func test_hush_marks_all_but_the_lit_sector_and_spares_the_perimeter() -> void:
	make_arena()
	var b := _phase_c()
	var d: Node3D = b.target_override
	assert_true(until(b, "c_hush_tele") >= 0.0)
	var tell := float(b._state_len)
	assert_true(tell >= 1.0 and tell <= 1.4, "hush warning 1.0-1.4 s")
	var lit: Vector3 = b.lit_dir()
	var fp: Dictionary = b.mark_fx.footprint()
	assert_eq(String(fp["kind"]), "arc")
	assert_almost(float(fp["arc_deg"]), 360.0 - float(b.lit_arc()), 0.001, "everything but the lit sector is marked")
	assert_almost(float(fp["radius"]), PERIM, 0.001, "up to the perimeter walk")
	assert_true((fp["facing"] as Vector3).distance_to(-lit) < 0.01, "centred opposite the true flame")
	assert_false(b.in_hush(flat_at(lit, 6.0)), "the true flame's lit sector is safe")
	assert_true(b.in_hush(flat_at(-lit, 5.0)), "an unlit place is hushed")
	assert_false(b.in_hush(flat_at(-lit, PERIM + 0.3)), "the perimeter walk is always safe")
	for f in b.lights.call("false_lights_nodes"):
		var fn: Node3D = f
		if fn.visible:
			assert_true(b.in_hush(Vector3(fn.global_position.x, 0.0, fn.global_position.z)), "a cozy false light's floor is NOT safe")
	d.global_position = flat_at(lit, 6.0)
	assert_true(until(b, "c_open") >= 0.0)
	assert_eq((d as Object).get("hits").size(), 0, "untouched in the lit sector")
	assert_true(until(b, "c_hush_tele") >= 0.0, "unanswered, the flame moves and the hush returns")
	d.global_position = flat_at(-b.lit_dir(), 5.0)
	assert_true(until(b, "c_open") >= 0.0)
	var hits: Array = (d as Object).get("hits")
	assert_eq(hits.size(), 1, "one hit")
	assert_almost(float(hits[0]), 18.0, 0.001, "data kept_flame damage x Standard")


func test_raise_at_the_true_flame_exposes_a_wrong_anchor_only_answers() -> void:
	make_arena()
	var b := _phase_c()
	var d: Node3D = b.target_override
	assert_true(until(b, "c_open") >= 0.0)
	var k := int(b.flame_anchor)
	raise((k + 1) % 3)
	assert_eq(String(b.state), "c_open", "a wrong anchor exposes nothing")
	assert_true(has_caption("true flame hangs elsewhere"), "and says so")
	assert_false(b.can_be_hit_by(d))
	raise(k)
	assert_eq(String(b.state), "c_exposed")
	assert_true(b.can_be_hit_by(d))
	run(b, 0.7)
	assert_true(absf(b.get_aim_point().y - (d.global_position.y + 0.9)) <= Combat.MAX_VERTICAL_REACH, "drawn down within reach")
	assert_true(Rules.flat(b.global_position, b.hook_pos(k)) < 3.0, "beside the true flame")
	# a raise DURING the hush waits for the hush to pass
	assert_true(until(b, "c_hush_tele") >= 0.0)
	raise(int(b.flame_anchor))
	assert_eq(String(b.state), "c_hush_tele", "the committed hush still lands")
	assert_true(bool(b._pending_expose))
	assert_true(until(b, "c_exposed", 2.0) >= 0.0, "then the Choir is exposed")


func test_exactly_three_exposures_end_it_gear_only_shortens_windows() -> void:
	make_arena()
	var b := _phase_c()
	var d: Node3D = b.target_override
	var max_hp: float = b.health.max_hp
	var third := Rules.budget(max_hp) / 3.0
	_expose_once(b)
	assert_true(until(b, "c_recover") > 5.0, "weak gear: the whole window runs")
	assert_almost(float(b.health.hp), Rules.phase_start_hp(3, max_hp) - third, 0.001, "one exposure = a third of the phase")
	assert_eq(int(b.exposures), 1)
	_expose_once(b)
	var dealt := float(b.health.apply_damage(9999.0, d))
	assert_almost(dealt, third, 0.001, "strong gear cannot take more than the exposure")
	assert_eq(String(b.state), "c_recover", "it only ends the window early")
	assert_eq(int(b.exposures), 2)
	assert_true(float(b.health.hp) > 0.0, "never skips an exposure")
	assert_eq(defeats.size(), 0)
	_expose_once(b)
	b.health.apply_damage(9999.0, d)
	assert_eq(int(b.exposures), 3)
	assert_true(bool(b.is_defeated()), "three exposures end the fight")
	assert_eq(defeats, [BOSS_ID], "Events.boss_defeated once")
	assert_true(bool(GameState.get_flag("ch2_choir_defeated")))


func test_three_timed_out_exposures_also_end_it() -> void:
	make_arena()
	var b := _phase_c()
	for k in 3:
		_expose_once(b)
		until(b, "gone" if k == 2 else "c_recover")
	assert_eq(int(b.exposures), 3)
	assert_true(bool(b.is_defeated()), "the reveal itself is the lesson: no attack needed to finish")
	assert_eq(defeats.size(), 1)


func test_intense_feint_and_gentle_wider_sector() -> void:
	assert_true(Rules.pick(Rules.LIT_ARC, 0) > Rules.pick(Rules.LIT_ARC, 1) and Rules.pick(Rules.LIT_ARC, 1) > Rules.pick(Rules.LIT_ARC, 2), "Gentle lights a wider sector")
	make_arena()
	var b := _phase_c(2)
	assert_true(until(b, "c_settle") >= 0.0)
	var k := int(b.flame_anchor)
	var via: Vector3 = b.lights.get("_move_via")
	assert_true(via.is_finite(), "Intense: the flame heads for another hook first")
	var dur := float(b._state_len)
	run(b, dur * 0.45)
	var fpos: Vector3 = b.lights.call("flame_position")
	assert_true(fpos.distance_to(via) < fpos.distance_to(b.hook_pos(k)), "the feint is readable: it is still going the wrong way")
	until(b, "c_hush_tele")
	assert_true((b.lights.call("flame_position") as Vector3).distance_to(b.hook_pos(k)) < 0.05, "then settles on its real hook before the hush")


func test_high_visibility_marks_the_true_flame() -> void:
	make_arena()
	var b := _phase_c()
	assert_true(until(b, "c_hush_tele") >= 0.0)
	assert_false(bool(b.lights.call("hv_visible")), "off by default")
	Settings.set_value("high_visibility_cues", true)
	await wait_frames(1)
	assert_true(bool(b.lights.call("hv_visible")), "bold ring + sector edges when high visibility cues are on")
	var hv: Node = b.lights.get_node("Hv")
	var ring: Node = hv.find_child("HvRing", true, false)
	assert_true(ring != null and Rules.flat((ring as Node3D).global_position, (anchors[b.flame_anchor] as Node3D).global_position) < 0.1, "round the true flame's anchor")
	assert_eq(hv.find_children("HvEdge*", "", true, false).size(), 2, "and both sector edges")
	Settings.set_value("high_visibility_cues", false)
	await wait_frames(1)
	assert_false(bool(b.lights.call("hv_visible")))


func test_reading_the_flame_early_counts_but_not_during_an_intense_feint() -> void:
	make_arena()
	var b := _phase_c(1)
	assert_true(until(b, "c_settle") >= 0.0)
	raise(int(b.flame_anchor))
	assert_true(bool(b._pending_expose), "Standard: raising at the hook the flame is heading for counts")
	assert_true(until(b, "c_exposed", 4.0) >= 0.0, "exposed right after the hush")
	for c in get_children():
		c.queue_free()
	await wait_frames(1)
	anchors.clear()
	resonators.clear()
	make_arena()
	var bi := _phase_c(2)
	assert_true(until(bi, "c_settle") >= 0.0)
	raise(int(bi.flame_anchor))
	assert_false(bool(bi._pending_expose), "Intense: an early guess during the feint does not count")
	assert_true(has_caption("true flame hangs elsewhere"))


## Review regression: a raised anchor refuses a new raise (its prompt is disabled) until it burns out - 8 s, 16 with
## timing assist, longer than the wait after an Intense feint. A lantern already on the hook the flame then settles
## on used to lock her out of the one anchor that mattered. The hook is now freed when the flame settles, so one
## press through the anchor's REAL prompt counts (the harness raise() lowers first and would hide this).
func test_a_lantern_already_on_the_flames_hook_never_locks_her_out() -> void:
	make_arena()
	var b := _phase_c(2)
	var d: Node3D = b.target_override
	assert_true(until(b, "c_settle") >= 0.0)
	var a: Node = anchors[int(b.flame_anchor)]
	assert_true(bool((a.call("get_interaction", d) as Dictionary).get("enabled")))
	a.call("interact", null)
	assert_false(bool(b._pending_expose), "an early guess during the Intense feint still does not count")
	assert_true(until(b, "c_hush_tele") >= 0.0)
	assert_false(bool(a.call("is_raised")), "the hook is freed when the flame settles on it")
	assert_true(has_caption("raise your lantern there again"), "and she is told so")
	assert_true(bool((a.call("get_interaction", d) as Dictionary).get("enabled")), "its prompt is live again")
	a.call("interact", null)
	assert_true(bool(b._pending_expose), "one press counts")
	assert_true(until(b, "c_exposed", 3.0) >= 0.0, "exposed right after the hush")
	# a leftover lantern (every anchor lit before the flame chose one) is handled the same way
	b.health.apply_damage(99999.0, d)
	assert_eq(String(b.state), "c_recover")
	for i in anchors.size():
		raise(i)
	assert_true(until(b, "c_hush_tele") >= 0.0)
	var k := int(b.flame_anchor)
	for i in anchors.size():
		assert_eq(bool((anchors[i] as Node).call("is_raised")), i != k, "only the flame's hook is freed (%d)" % i)
	assert_false(bool(b._pending_expose), "a lantern raised before the flame chose its hook is a guess")
	(anchors[k] as Node).call("interact", null)
	assert_true(until(b, "c_exposed", 3.0) >= 0.0, "one press after the settle exposes it")
