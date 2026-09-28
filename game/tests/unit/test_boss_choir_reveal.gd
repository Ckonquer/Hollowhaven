extends "res://tests/unit/test_boss_choir_harness.gd"
## The Borrowed Choir, Phase A "False welcome" (MP §13.3): the genuine form's cues (a REALLY lit floor plate + the
## living sway; false forms dark + stiff lockstep), raising the lantern at a fixed anchor resolves it (bright plate +
## the bold high-visibility ring, never colour alone), a pick needs that reveal, correct = an exposure window whose
## cap / floor bound the damage, wrong = a harmless burst + a marked, delayed, NEVER lethal sweep; the sweep's marked
## wedge is exactly what hits (the perimeter walk is outside it), it respects line of sight and lands once through
## Krystal's health path; forms reshuffle every cycle; companions can neither hit nor pick a form.

const DROP_WAIT := 0.7


func _to_wait(b: Node) -> void:
	b.start_fight()
	assert_true(until(b, "a_wait") >= 0.0, "the forms settle and wait")


func _lit_forms(b: Node) -> Array:
	var out: Array = []
	for f in b.forms:
		if bool((f as Node).call("plate_lit")):
			out.append(f)
	return out


static func _visible_lights(n: Node) -> int:
	var c := 1 if (n is Light3D and (n as Light3D).visible and (n as Node3D).is_visible_in_tree()) else 0
	for ch in n.get_children():
		c += _visible_lights(ch)
	return c


func test_genuine_form_lights_its_plate_and_moves_alive() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	_to_wait(b)
	var g: int = b.genuine
	assert_eq(b.forms.size(), 3, "three forms")
	assert_eq(_lit_forms(b).size(), 1, "exactly one form lights its floor plate")
	for i in 3:
		var f: Node3D = b.forms[i]
		assert_true(f.visible and bool(f.get("pickable")), "form %d stands at its station, pickable" % i)
		assert_true(Rules.flat(f.global_position, b.station(i)) < 0.05, "form %d at the station before anchor %d" % [i, i])
		if i == g:
			assert_true(bool(f.call("plate_lit")), "the genuine plate is lit")
			assert_eq(_visible_lights(f), 1, "by a real light (OmniLight3D), consistently - even before any reveal")
			assert_almost(float(f.call("plate_light_energy")), 0.5, 0.001, "faint until an anchor burns")
			assert_eq(String(f.call("motion_kind")), "living")
		else:
			assert_false(bool(f.call("plate_lit")), "a false form's plate stays dark")
			assert_eq(_visible_lights(f), 0, "no light at all on a false form (its glow lights nothing)")
			assert_eq(String(f.call("motion_kind")), "stiff")
	# the motion cue: false forms tick in lockstep between two fixed tilts, the genuine one sways smoothly
	for f in b.forms:
		(f as Node).call("tick", 0.13)
	var tilts: Array = []
	for i in 3:
		var body: Node3D = (b.forms[i] as Node3D).get_node("Body")
		if i != g:
			tilts.append(snappedf(body.rotation.z, 0.0001))
			assert_almost(absf(body.rotation.z), 0.07, 0.0001, "stiff metronome tilt")
	assert_eq(tilts[0], tilts[1], "false forms move in lockstep")
	assert_false(b.revealed, "nothing revealed yet")


## Review regression: each plate (and the genuine plate's bold ring) stays clear of every lantern anchor's carved
## ring, raised glow ring and bold high-visibility ring. With the plate on the anchor side, the anchor's bold ring
## crossed EVERY plate (false ones too), so with high_visibility_cues the marker meant for the genuine plate lost
## its meaning, and the raised anchor's own light washed the nearest plate.
func test_plates_stay_clear_of_the_anchor_rings() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	_to_wait(b)
	var plate_r := float((load("res://src/enemies/choir/choir_form.gd") as Script).get_script_constant_map()["PLATE_R"])
	var plate_hv_outer := plate_r + 0.22 + 0.09                      # Art.bold_ring(plate, PLATE_R + 0.22) half-width 0.09
	var anchor_hv_outer := float(AnchorScript.RING_RADIUS) + 0.25 + 0.09  # lantern_anchor.gd bold ring
	for i in 3:
		var plate: Node3D = (b.forms[i] as Node).get_node("Plate")
		assert_true(Rules.flat(plate.global_position, b.station(i)) <= 1.1, "plate %d at its form's feet" % i)
		for a in anchors:
			var gap := Rules.flat(plate.global_position, (a as Node3D).global_position) - anchor_hv_outer - plate_hv_outer
			assert_true(gap >= 0.5, "plate %d clear of an anchor's rings (gap %.2f m)" % [i, gap])
		for j in 3:
			if j != i:
				var other: Node3D = (b.forms[j] as Node).get_node("Plate")
				assert_true(Rules.flat(plate.global_position, other.global_position) > 2.0 * plate_hv_outer + 1.0, "plates %d/%d well apart" % [i, j])


func test_raising_an_anchor_resolves_it_with_a_bold_marker() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	_to_wait(b)
	var g: Node = b.forms[b.genuine]
	assert_false(bool(g.call("hv_marker_visible")), "no marker before the reveal")
	raise(2)
	b.tick(DT)
	assert_true(b.revealed, "a lantern on any fixed anchor reveals")
	assert_almost(float(g.call("plate_light_energy")), 1.9, 0.001, "the genuine plate blazes")
	assert_false(bool(g.call("hv_marker_visible")), "high visibility off: no extra marker")
	assert_true(has_caption("lights the floor at its feet"), "captioned (sound muted playable)")
	Settings.set_value("high_visibility_cues", true)
	await wait_frames(1)
	assert_true(bool(g.call("hv_marker_visible")), "high_visibility_cues: a bold ring round the genuine plate")
	var ring: Node = (g as Node).find_child("HvRing", true, false)
	assert_true(ring is MeshInstance3D and (ring as MeshInstance3D).mesh is TorusMesh, "a SHAPE (outlined torus), not colour alone")
	for i in 3:
		if i != b.genuine:
			assert_false(bool((b.forms[i] as Node).call("hv_marker_visible")), "no marker on false forms")
	lower_all()
	b.tick(DT)
	assert_false(b.revealed, "the reveal ends with the lantern")
	assert_false(bool(g.call("hv_marker_visible")))


func test_pick_needs_the_reveal_correct_pick_opens_a_bounded_window() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	_to_wait(b)
	var g: int = b.genuine
	assert_eq(String(b.pick_form(g, d)), "not_revealed", "no pick without a lantern on an anchor")
	assert_eq(String(b.state), "a_wait")
	assert_false(b.can_be_hit_by(d), "armoured while veiled")
	assert_true(bool(b.health.invulnerable))
	raise(0)
	b.tick(DT)
	assert_eq(String(b.pick_form(g, d)), "correct")
	assert_eq(String(b.state), "a_exposed", "correct reveal = damage window")
	assert_almost(float(b._state_len), float(Rules.T_WINDOW_A[1]), 0.001, "Standard window 6.5 s")
	assert_true(b.can_be_hit_by(d), "Krystal may strike")
	assert_true(b.can_be_hit_by(companion(Vector3(2, 0, 2))), "a companion inside the vault hits the exposed form")
	assert_false(b.can_be_hit_by(companion(Vector3(30, 0, 0))), "...never from outside")
	for i in 3:
		assert_false(bool((b.forms[i] as Node).get("pickable")), "forms fold away")
	run(b, DROP_WAIT)
	assert_true(absf(b.get_aim_point().y - (d.global_position.y + 0.9)) <= Combat.MAX_VERTICAL_REACH, "the exposed Choir is within sword reach")
	var max_hp: float = b.health.max_hp
	assert_almost(float(b.health.apply_damage(30.0, d)), 30.0, 0.001)
	var dealt := float(b.health.apply_damage(500.0, d))
	assert_almost(dealt, Rules.window_cap(1, max_hp) - 30.0, 0.001, "one exposure never takes more than its cap")
	assert_eq(String(b.state), "a_recover", "good gear ends the window early")
	assert_almost(float(b.health.hp), max_hp - Rules.window_cap(1, max_hp), 0.001)
	assert_false(b.can_be_hit_by(d), "armoured again")
	assert_true(until(b, "a_wait") >= 0.0, "a new cycle")
	assert_ne(int(b.genuine), g, "the forms reshuffle: never the same genuine form twice in a row")


func test_weak_gear_still_progresses_the_window_floor() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	_to_wait(b)
	raise(1)
	b.tick(DT)
	b.pick_form(b.genuine, d)
	var max_hp: float = b.health.max_hp
	assert_true(until(b, "a_recover") > 6.0, "the whole window runs when nobody strikes")
	assert_almost(float(b.health.hp), max_hp - Rules.window_floor(1, max_hp), 0.001, "the true light sears a third of the phase")
	assert_true(has_caption("borrowed shape frays"))
	# three floor-only exposures reach phase B: never a sponge
	for k in 2:
		assert_true(until(b, "a_wait") >= 0.0)
		raise(k)
		b.tick(DT)
		b.pick_form(b.genuine, d)
		until(b, "phase_shriek" if k == 1 else "a_recover")
	assert_eq(int(b.phase), 2, "phase A takes exactly three correct reveals")
	assert_almost(float(b.health.hp), Rules.phase_start_hp(2, max_hp), 0.001, "exactly at the phase boundary (no bleed)")


func test_wrong_pick_is_a_marked_delayed_sweep_that_never_kills() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -6))
	d.health.set_hp(5.0)
	var b := make_boss(d)
	_to_wait(b)
	raise(0)
	b.tick(DT)
	var w := wrong_form(b)
	assert_eq(String(b.pick_form(w, d)), "wrong")
	assert_eq(int(b.wrong_picks), 1)
	assert_true(bool((b.forms[w] as Node).get("folded")), "the false form bursts (harmless)")
	assert_eq(String(b.state), "a_sweep_tele", "a telegraphed sweep, not instant damage")
	var tell := float(b._state_len)
	assert_true(tell >= 1.0 and tell <= 1.4, "committed tell 1.0-1.4 s (got %.2f)" % tell)
	var fp: Dictionary = b.mark_fx.footprint()
	assert_eq(String(fp["kind"]), "arc", "the wedge is marked on the floor")
	assert_almost(float(fp["radius"]), PERIM, 0.001, "it reaches the perimeter walk, not onto it")
	assert_almost(float(fp["arc_deg"]), float(b.sweep_arc()), 0.001, "marked arc == hit arc")
	run(b, tell - 0.1)
	assert_eq(d.hits.size(), 0, "nothing lands during the warning")
	assert_true(until(b, "a_recover") >= 0.0)
	assert_eq(d.hits.size(), 1, "one hit")
	assert_almost(float(d.health.hp), 1.0, 0.001, "a wrong choice is survivable: never below 1 hp")
	assert_false(bool(d.health.dead))


## Review regression: the "never below 1 hp" cap is taken before her health's damage_taken_mult, not after.
func test_wrong_pick_sweep_stays_survivable_with_a_damage_taken_mult() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -6))
	d.health.set_hp(10.0)
	d.health.damage_taken_mult = 3.0
	var b := make_boss(d)
	_to_wait(b)
	raise(0)
	b.tick(DT)
	assert_eq(String(b.pick_form(wrong_form(b), d)), "wrong")
	assert_true(until(b, "a_recover") >= 0.0)
	assert_eq(d.hits.size(), 1, "one hit")
	assert_almost(float(d.health.hp), 1.0, 0.001, "still exactly 1 hp left")
	assert_false(bool(d.health.dead))


func test_sweep_lands_once_through_her_health_path_and_the_perimeter_is_safe() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -6), true)
	var b := make_boss(d)
	_to_wait(b)
	raise(0)
	b.tick(DT)
	b.pick_form(wrong_form(b), d)
	until(b, "a_recover")
	assert_eq(d.hits.size(), 1, "damage applied once")
	var last: Dictionary = d.health.get("last_hit")
	assert_almost(float(last["raw"]), 14.0, 0.001, "data false_welcome damage x Standard 1.0, through player_health (armour/shield order)")
	# the impatient sweep (waiting too long) - stepping onto the perimeter walk avoids it
	assert_true(until(b, "a_wait") >= 0.0)
	assert_true(until(b, "a_sweep_tele") > 12.0, "the Choir waits T_WAIT before growing impatient")
	assert_true(b.in_sweep(d.global_position), "she stands in the tracked wedge")
	d.global_position = flat_at(b.sweep_dir(), PERIM + 0.4)
	assert_false(b.in_sweep(d.global_position), "the perimeter walk is outside every sweep")
	d.health.set("_iframe_until_ms", 0)
	until(b, "a_recover")
	assert_eq(d.hits.size(), 1, "no second hit on the perimeter")
	assert_eq(int(b.sweeps), 2)


func test_sweep_respects_line_of_sight() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -6))
	var b := make_boss(d)
	wall(Vector3(0, 1.0, -3.5), Vector3(6.0, 3.0, 0.4))
	await wait_physics(2)
	_to_wait(b)
	raise(0)
	b.tick(DT)
	b.pick_form(wrong_form(b), d)
	until(b, "a_recover")
	assert_eq(d.hits.size(), 0, "no sweep through a wall")


func test_forms_refuse_companions_and_krystal_strikes_pick() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -9))
	var b := make_boss(d)
	_to_wait(b)
	raise(0)
	b.tick(DT)
	var w := wrong_form(b)
	var f: Node3D = b.forms[w]
	assert_true(f.is_in_group("enemy"), "pickable forms can be struck")
	var c := companion(f.global_position + Vector3(0, 0, 1.2))
	assert_false(bool(f.call("can_be_hit_by", c)), "never a companion target")
	assert_true(bool((f.get("health") as Node).get("invulnerable")), "invulnerable (companions skip it)")
	var hit_c: Array = Combat.melee(c, c.global_position + Vector3.UP * 0.9, f.global_position - c.global_position, 3.0, 360.0, 20.0, ["enemy"], 0.0)
	assert_eq(hit_c.size(), 0)
	assert_eq(String(b.state), "a_wait", "a companion's blow never picks")
	assert_false(b.can_be_hit_by(c), "nor hurts the veiled Choir")
	# Krystal's strike on a revealed false form = pointing it out
	d.global_position = f.global_position + Rules.bearing(CENTER, f.global_position) * 1.4
	var fwd := Vector3(f.global_position.x - d.global_position.x, 0.0, f.global_position.z - d.global_position.z)
	var hits: Array = Combat.melee(d, d.global_position + Vector3.UP * 0.9, fwd, 2.5, 110.0, 18.0, ["enemy"], 4.0)
	assert_eq(hits.size(), 0, "forms never take damage")
	assert_eq(String(b.state), "a_sweep_tele", "her strike on a false form is a (wrong) pick")
	assert_false(f.is_in_group("enemy"), "and it leaves the target groups")


func test_veiled_choir_is_out_of_reach_and_blocks_with_a_hint() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -2))
	var b := make_boss(d)
	_to_wait(b)
	assert_true(b.get_aim_point().y - (d.global_position.y + 0.9) > Combat.MAX_VERTICAL_REACH, "veiled: out of sword reach")
	var hints: Array = []
	var cb := func(id: String, _t: String) -> void: hints.append(id)
	Events.hint.connect(cb)
	b.on_hit_blocked(d, Vector3.FORWARD)
	Events.hint.disconnect(cb)
	assert_true(hints.has("choir_glance_a"), "a blocked blow explains the rule")


func test_timing_assist_and_intensity_tables() -> void:
	make_arena()
	var d := dummy(Vector3(0, 0, -6))
	Settings.set_value("timing_assist", true)
	var b := make_boss(d)
	_to_wait(b)
	assert_almost(float(b._state_len), Rules.T_WAIT[1] * Rules.ASSIST_MULT, 0.001, "timing assist: more time to read")
	raise(0)
	b.tick(DT)
	b.pick_form(wrong_form(b), d)
	assert_almost(float(b._state_len), Rules.T_SWEEP_TELE[1] * Rules.ASSIST_MULT, 0.001, "and longer warnings")
	for i in 3:
		assert_true(Rules.tell(Rules.T_SWEEP_TELE, i, false) >= Rules.MIN_TELL, "never under 1.0 s")
		assert_true(Rules.pick(Rules.T_SWEEP_TELE, i) <= 1.4, "committed warnings stay in 1.0-1.4 s")
	assert_true(Rules.pick(Rules.T_WAIT, 0) > Rules.pick(Rules.T_WAIT, 2), "Gentle waits longer, Intense idles less")
	assert_true(Rules.pick(Rules.T_WINDOW_A, 0) > Rules.pick(Rules.T_WINDOW_A, 2), "Gentle windows are longer")
