extends "res://tests/unit/test_boss_choir_harness.gd"
## The Borrowed Choir, Phase B "Stolen rhythm" (MP §13.3): the two fixed resonators take the symbol order taught
## on the Bellmaker's Floor, each woken resonator drops one protection layer and both expose the Choir; a half-done
## sequence slips after the resonator window (never with timing assist); the whole puzzle works muted (captions +
## lit plates); at most two Borrowed Wisps (Gentle one), released once and never refilled, dismissed in phase C;
## the Choir never starts an attack over the committed cap (wisp wind-ups count) and holds a shared attack token
## while committed; rings show their opening BEFORE launch, spare the opening and the perimeter walk, hit once per
## ring and not through walls; strike zones are marked, delayed, hit once and never through a ceiling.

const HP := 5000.0


func _phase_b(intensity: int = 1, pos: Vector3 = Vector3(-9.0, 0, 0)) -> Node:
	var d := dummy(pos, false, HP)
	var b := make_boss(d, intensity)
	start_in_phase(b, 2)
	assert_true(until(b, "b_gather") >= 0.0, "phase B begins")
	return b


func _freeze_wisps(b: Node) -> Array:
	var ws: Array = b.wisp_nodes()
	for w in ws:
		(w as Node).set_physics_process(false)
	return ws


func test_taught_order_drops_a_layer_per_resonator_then_exposes() -> void:
	make_arena()
	var b := _phase_b()
	var seq := taught_ids()
	assert_eq(seq, ["leaf", "moon", "key", "flame"], "the Bellmaker's Floor order (data/works_layout.gd BELL_ORDER)")
	assert_eq(int(b.layers.count()), 2, "two protection layers")
	for r in resonators:
		assert_true(bool((r as Node).get("enabled")), "resonators enabled in phase B")
		assert_eq((r as Node).get("sequence"), seq, "set to the taught order")
	assert_false(b.can_be_hit_by(b.target_override), "protected")
	var r0: Node = resonators[0]
	for k in seq.size():
		var res := String(r0.call("strike", String(seq[k])))
		assert_eq(res, "done" if k == seq.size() - 1 else "progress", "plate %s" % seq[k])
	assert_eq(int(b.layers.count()), 1, "one layer falls")
	assert_eq(b.layers.standing(), [false, true], "the outer ring of bells went first")
	for k in seq.size():
		assert_true(has_caption("(%d of %d)" % [k + 1, seq.size()]), "every strike captioned (%d)" % (k + 1))
	var r1: Node = resonators[1]
	assert_eq(String(r1.call("strike", String(seq[1]))), "wrong", "a wrong plate restarts gently (never damage)")
	assert_eq(int(r1.get("progress")), 0)
	assert_eq(strike_sequence(r1), "done")
	assert_true(until(b, "b_exposed") >= 0.0, "both resonators = exposed")
	assert_eq(int(b.layers.count()), 0)
	assert_true(b.can_be_hit_by(b.target_override))
	assert_almost(float(b._state_len), float(Rules.T_WINDOW_B[1]), 0.001, "Standard window 7.5 s")
	var max_hp: float = b.health.max_hp
	var dealt := float(b.health.apply_damage(9999.0, b.target_override))
	assert_almost(dealt, Rules.budget(max_hp), 0.001, "one exposure may take the whole phase budget, never more")
	assert_eq(String(b.state), "phase_shriek", "straight on to the next phase")
	assert_eq(int(b.phase), 3)
	assert_true(phase_list().has(3), "Events.boss_phase_changed(borrowed_choir, 3)")


func test_weak_gear_floor_and_the_second_cycle_reforms() -> void:
	make_arena()
	var b := _phase_b()
	for r in resonators:
		strike_sequence(r)
	assert_true(until(b, "b_exposed") >= 0.0)
	var max_hp: float = b.health.max_hp
	assert_true(until(b, "b_reform") >= 0.0, "the window runs out")
	assert_almost(float(b.health.hp), Rules.phase_start_hp(2, max_hp) - Rules.window_floor(2, max_hp), 0.001, "half the phase is seared away regardless")
	assert_eq(int(b.layers.count()), 2, "the layers re-form")
	for r in resonators:
		assert_false(bool((r as Node).call("is_active")), "resonators reset for the second cycle")
		assert_true(bool((r as Node).get("enabled")))
	assert_true(until(b, "b_idle") >= 0.0)
	for r in resonators:
		strike_sequence(r)
	assert_true(until(b, "b_exposed") >= 0.0)
	until(b, "phase_shriek")
	assert_eq(int(b.phase), 3, "at most two resonator cycles")


func test_window_slips_without_timing_assist_never_with_it() -> void:
	make_arena()
	var b := _phase_b()
	var seq := taught_ids()
	var r0: Node = resonators[0]
	assert_true(until(b, "b_idle") >= 0.0)
	assert_eq(String(r0.call("strike", String(seq[0]))), "progress")
	run(b, 12.6)
	assert_eq(int(r0.get("progress")), 0, "a half-done sequence left 12 s restarts")
	assert_eq(int(b.resonance.get("slips")), 1)
	assert_true(has_caption("start the sequence again"), "and says so")
	Settings.set_value("timing_assist", true)
	assert_eq(float(b.resonance.call("window")), INF, "timing assist: no window at all")
	assert_eq(String(r0.call("strike", String(seq[0]))), "progress")
	run(b, 30.0)
	assert_eq(int(r0.get("progress")), 1, "the plate waits as long as she needs")
	assert_eq(int(b.resonance.get("slips")), 1)
	assert_eq(strike_sequence_from(r0, 1), "done")


func strike_sequence_from(r: Node, start: int) -> String:
	var seq: Array = r.get("sequence")
	var last := ""
	for k in range(start, seq.size()):
		last = String(r.call("strike", String(seq[k])))
	return last


func test_fully_playable_muted() -> void:
	make_arena()
	var saved_master: Variant = Settings.get_value("master_volume")
	var saved_sfx: Variant = Settings.get_value("sfx_volume")
	Settings.set_value("master_volume", 0.0)
	Settings.set_value("sfx_volume", 0.0)
	var b := _phase_b()
	var seq := taught_ids()
	var n0 := captions.size()
	for r in resonators:
		for k in seq.size():
			(r as Node).call("strike", String(seq[k]))
			var plates: Dictionary = (r as Node).get("_plates")
			var lit: MeshInstance3D = (plates[String(seq[k])] as Dictionary)["lit"]
			assert_true(lit.visible, "the struck plate lights up (visible progress, no sound needed)")
	assert_true(captions.size() - n0 >= seq.size() * 2, "every strike is captioned")
	assert_true(until(b, "b_exposed") >= 0.0, "exposed without hearing anything")
	Settings.set_value("master_volume", saved_master)
	Settings.set_value("sfx_volume", saved_sfx)


func test_wisp_cap_released_once_never_refilled_dismissed_later() -> void:
	make_arena()
	assert_true(Factory.can_spawn("borrowed_wisp"), "enemy id borrowed_wisp is available")
	var b := _phase_b()
	var ws := _freeze_wisps(b)
	assert_eq(ws.size(), 2, "Standard: two Borrowed Wisps")
	assert_eq(int(b.wisps_released), 2)
	for w in ws:
		assert_eq(String((w as Node).get("enemy_id")), "borrowed_wisp")
		assert_true(bool((w as Node).get("drops_enabled")) == false, "boss helpers drop nothing")
	(ws[0] as Node).queue_free()
	await wait_frames(1)
	assert_eq(int(b.wisps_alive()), 1)
	run(b, 20.0)
	assert_eq(int(b.wisps_alive()), 1, "never refilled - not an add factory")
	assert_eq(int(b.wisps_released), 2)
	for r in resonators:
		strike_sequence(r)
	until(b, "b_exposed")
	b.health.apply_damage(9999.0, b.target_override)
	assert_true(until(b, "c_gather") >= 0.0)
	assert_eq(int(b.wisps_alive()), 0, "phase C: the wisps are dismissed")


func test_gentle_releases_one_wisp() -> void:
	make_arena()
	var b := _phase_b(0)
	assert_eq(_freeze_wisps(b).size(), 1, "Gentle: one wisp")
	assert_eq(Rules.wisp_cap(2), 2, "Intense still two")


func test_committed_cap_counts_wisp_windups_and_holds_a_token() -> void:
	make_arena()
	var b := _phase_b()
	var ws := _freeze_wisps(b)
	assert_true(until(b, "b_idle") >= 0.0)
	(ws[0] as Node).set("state", "telegraph")
	(ws[1] as Node).set("state", "sweep")
	assert_eq(int(b.committed_wisps()), 2)
	run(b, 6.0)
	assert_eq(String(b.state), "b_idle", "Standard: no Choir attack over two wisp wind-ups")
	(ws[1] as Node).set("state", "chase")
	assert_true(until(b, "b_ring_tele", 1.0) >= 0.0, "one wisp wind-up + the Choir = the Standard cap (2)")
	assert_true(Base._attackers.has(b.get_instance_id()), "committed: holds a slot of the shared attack-token table")
	assert_true(until(b, "b_idle") >= 0.0)
	assert_false(Base._attackers.has(b.get_instance_id()), "released after the attack")
	assert_true(Rules.may_commit(0, 0) and not Rules.may_commit(0, 1), "Gentle never overlaps")
	assert_true(Rules.may_commit(1, 1) and not Rules.may_commit(1, 2))
	assert_true(Rules.may_commit(2, 1) and not Rules.may_commit(2, 2), "Intense adds a feint / less idle, never more overlap")
	for i in 3:
		assert_true(Rules.picki(Rules.MAX_COMMITTED, i) <= Base.MAX_ATTACKERS, "never past the shared attack-token table (%d)" % i)


## Integration pass 2 (P23): the Choir goes through enemy_base's claim_attack_token / release_attack_token - never a
## third attacker in the MAX_ATTACKERS table, and a new claim waits out the stagger after another attacker's wind-up.
func test_the_choir_claims_the_shared_token_table_through_enemy_base() -> void:
	make_arena()
	var b := _phase_b()
	_freeze_wisps(b)
	assert_true(until(b, "b_idle") >= 0.0)
	var id: int = b.get_instance_id()
	Base.clock_override_ms = 200000
	var a1 := Node.new()
	var a2 := Node.new()
	add_child(a1)
	add_child(a2)
	assert_true(Base.claim_attack_token(a1.get_instance_id()), "a first attacker claims a slot")
	assert_true(Base.claim_attack_token(a1.get_instance_id()), "re-claiming a held token is fine")
	assert_false(Base.claim_attack_token(a2.get_instance_id()), "a different attacker waits out the stagger")
	Base.clock_override_ms += Base.ATTACK_STAGGER_MS
	assert_true(Base.claim_attack_token(a2.get_instance_id()), "after the stagger: the second slot")
	Base.clock_override_ms += Base.ATTACK_STAGGER_MS
	assert_false(Base.attack_token_available_for(id), "MAX_ATTACKERS (2) reached")
	run(b, 6.0)
	assert_eq(String(b.state), "b_idle", "no Choir attack while two others hold the table (never a third)")
	assert_false(Base._attackers.has(id))
	assert_eq(Base._attackers.size(), Base.MAX_ATTACKERS)
	Base.release_attack_token(a1.get_instance_id())
	Base.release_attack_token(a1.get_instance_id())               # releasing twice is a no-op
	assert_true(until(b, "b_ring_tele", 1.0) >= 0.0, "a slot is free: the Choir claims it and winds up")
	assert_true(Base._attackers.has(id), "it holds the slot while committed")
	assert_eq(Base._attackers.size(), Base.MAX_ATTACKERS, "still never more than MAX_ATTACKERS")
	assert_false(Base.claim_attack_token(a1.get_instance_id()), "and the table is full for anyone else")
	assert_true(until(b, "b_idle") >= 0.0)
	assert_false(Base._attackers.has(id), "released after the attack")
	Base.release_attack_token(a2.get_instance_id())
	Base.clock_override_ms = -1


func _ring_case(offset_from_gap: float, dist: float, iframes: bool = false, walled: bool = false) -> Array:
	var d := dummy(Vector3(0, 0, -6), false, HP)
	var b := make_boss(d, 1)
	start_in_phase(b, 2)
	_freeze_wisps(b)
	assert_true(until(b, "b_ring_tele") >= 0.0, "the first attack is a ring volley")
	var tell := float(b._state_len)
	assert_true(tell >= 1.0 and tell <= 1.4, "ring warning 1.0-1.4 s")
	assert_eq(int(b.rings.active_count()), 0, "nothing launched during the warning")
	var fp: Dictionary = b.mark_fx.footprint()
	assert_eq(String(fp["kind"]), "ring")
	var gap: Dictionary = b._ring_gaps[0]
	for i in b._ring_gaps.size():
		assert_true((b.rings.get("_lanes")[i] as Node3D).visible, "the opening of ring %d is shown before launch" % i)
	var gdir: Vector3 = gap["dir"]
	d.global_position = flat_at(gdir.rotated(Vector3.UP, deg_to_rad(offset_from_gap)), dist)
	if iframes:
		d.health.grant_iframes(30.0)
	if walled:
		var dir := Rules.bearing(CENTER, d.global_position)
		var w := wall(CENTER + dir * (dist * 0.5) + Vector3.UP, Vector3(3.0, 3.0, 0.4))
		w.rotation.y = atan2(dir.x, dir.z)
		await wait_physics(2)
	assert_true(until(b, "b_rings") >= 0.0)
	var hits_before := d.hits.size()
	assert_true(until(b, "b_idle") >= 0.0, "the volley passes")
	var marked := 0
	for s in b.rings.rings.size():
		if bool((b.rings.ring(s) as Dictionary)["hit"]):
			marked += 1
	var out := [d.hits.size() - hits_before, marked, b._ring_gaps.size()]
	b.queue_free()
	await wait_frames(1)
	return out


func test_rings_spare_the_opening_and_the_perimeter_and_hit_once_each() -> void:
	make_arena()
	var r: Array = await _ring_case(180.0, 6.0)
	assert_eq(r[2], 2, "Standard volley: two rings")
	assert_eq(r[0], 2, "outside the opening: one hit per ring, never more")
	r = await _ring_case(0.0, 6.0)
	assert_eq(r[0], 0, "standing in the lit opening: untouched")
	r = await _ring_case(180.0, PERIM + 0.3)
	assert_eq(r[0], 0, "the perimeter walk is outside every ring")
	r = await _ring_case(180.0, 6.0, true)
	assert_eq(r[0], 0, "dodged (i-frames)")
	assert_eq(r[1], 2, "...and a dodged ring never re-tests her")
	r = await _ring_case(180.0, 6.0, false, true)
	assert_eq(r[0], 0, "no ring through a wall")


func test_ring_geometry_intense_and_timing_assist() -> void:
	assert_true(Rules.band_hit(CENTER, 5.8, 6.0, 0.6, Vector3(0, 0, 6.2)), "the band passing over her")
	assert_false(Rules.band_hit(CENTER, 3.0, 3.2, 0.6, Vector3(0, 0, 6.2)), "not yet")
	assert_true(Rules.in_gap(CENTER, Vector3.FORWARD, 85.0, Vector3(0.5, 0, -6)), "inside the opening")
	assert_false(Rules.in_gap(CENTER, Vector3.FORWARD, 85.0, Vector3(0, 0, 6)), "opposite side")
	make_arena()
	var d := dummy(Vector3(0, 0, -6), false, HP)
	var b := make_boss(d, 2)
	start_in_phase(b, 2)
	_freeze_wisps(b)
	until(b, "b_ring_tele")
	var g0: Vector3 = (b._ring_gaps[0] as Dictionary)["dir"]
	var g1: Vector3 = (b._ring_gaps[1] as Dictionary)["dir"]
	assert_almost(rad_to_deg(g0.angle_to(g1)), Rules.INTENSE_GAP_SHIFT, 0.5, "Intense: the second opening is turned (shown in advance)")
	b.queue_free()
	Settings.set_value("timing_assist", true)
	var b2 := make_boss(d, 1)
	start_in_phase(b2, 2)
	_freeze_wisps(b2)
	until(b2, "b_rings")
	assert_almost(float((b2._ring_gaps[0] as Dictionary)["deg"]), Rules.RING_GAP[1] + Rules.ASSIST_GAP_BONUS, 0.001, "timing assist: wider openings")
	assert_almost(float((b2.rings.ring(0) as Dictionary)["speed"]), Rules.RING_SPEED[1] * Rules.ASSIST_RING_SPEED, 0.001, "...and slower rings")


func _strike_case(intensity: int, move_out: bool = false, ceiling: bool = false) -> Array:
	var d := dummy(Vector3(3, 0, -4), false, HP)
	var b := make_boss(d, intensity)
	start_in_phase(b, 2)
	_freeze_wisps(b)
	assert_true(until(b, "b_idle") >= 0.0)
	b._b_rings_next = false
	assert_true(until(b, "b_strike_tele") >= 0.0, "a strike-zone volley")
	var tell := float(b._state_len)
	assert_true(tell >= 1.0 and tell <= 1.4, "strike delay 1.0-1.4 s")
	var pts: Array = (b.strikes.get("points") as Array).duplicate()
	assert_true(Rules.flat(pts[0], d.global_position) < 0.01, "the first zone is marked where she stands")
	for f in b.strikes.footprints():
		assert_almost(float((f as Dictionary)["radius"]), Rules.STRIKE_RADIUS, 0.001, "marked radius == hit radius")
	if move_out:
		for k in 16:
			var cand := flat_at(Vector3(cos(TAU * k / 16.0), 0, sin(TAU * k / 16.0)), 8.0)
			if not bool(b.strikes.call("hits", cand)):
				d.global_position = cand
				break
	if ceiling:
		wall(d.global_position + Vector3.UP * 2.1, Vector3(3.0, 0.3, 3.0))
		await wait_physics(2)
	run(b, tell - 0.1)
	var early := d.hits.size()
	assert_true(until(b, "b_idle") >= 0.0)
	var out := [early, d.hits.size(), pts.size()]
	b.queue_free()
	await wait_frames(1)
	return out


func test_strike_zones_marked_delayed_once_and_never_through_a_ceiling() -> void:
	make_arena()
	var r: Array = await _strike_case(1)
	assert_eq(r[2], 2, "Standard: two zones")
	assert_eq(r[0], 0, "nothing lands during the delay")
	assert_eq(r[1], 1, "one hit even where zones overlap")
	r = await _strike_case(1, true)
	assert_eq(r[1], 0, "stepping out of the marks avoids it")
	r = await _strike_case(1, false, true)
	assert_eq(r[1], 0, "no strike through a ceiling")
	r = await _strike_case(0)
	assert_eq(r[2], 1, "Gentle: one zone")
	r = await _strike_case(2)
	assert_eq(r[2], Rules.MAX_STRIKES, "Intense: capped at three")


## Review regression: the zones used to follow her onto the warm perimeter band (centres clamped only to the
## vault wall), breaking the one rule every other Choir attack keeps - the perimeter walk is always safe.
func test_strike_zones_never_reach_the_perimeter_walk() -> void:
	make_arena()
	for intensity in 3:
		var d := dummy(Vector3(0, 0, -(PERIM + 0.5)), false, HP)
		var b := make_boss(d, intensity)
		start_in_phase(b, 2)
		_freeze_wisps(b)
		assert_true(until(b, "b_idle") >= 0.0)
		b._b_rings_next = false
		assert_true(until(b, "b_strike_tele") >= 0.0, "a strike-zone volley (%d)" % intensity)
		for p in b.strikes.get("points"):
			var reach := Rules.flat(p, CENTER) + Rules.STRIKE_RADIUS + 0.35
			assert_true(reach <= PERIM + 0.001, "zone hit area ends at the perimeter walk (%.2f m)" % reach)
		assert_false(bool(b.strikes.call("hits", d.global_position)), "she stands on the perimeter: outside every zone")
		assert_true(until(b, "b_idle") >= 0.0)
		assert_eq(d.hits.size(), 0, "untouched on the perimeter walk (%d)" % intensity)
		# ...while at a resonator's plates (just inside the walk) the first zone still reaches her
		d.global_position = Vector3(0, 0, -8.9)
		b._b_rings_next = false
		assert_true(until(b, "b_strike_tele") >= 0.0)
		assert_true(bool(b.strikes.call("hits", d.global_position)), "at the plates she is still inside the first zone")
		b.queue_free()
		d.queue_free()
		await wait_frames(1)
