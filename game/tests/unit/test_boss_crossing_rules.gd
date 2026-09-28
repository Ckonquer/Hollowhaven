extends "res://tests/test_case.gd"
## Weaver's Crossing rematch - the pure rules (src/enemies/crossing/crossing_rules.gd): phases by exposures and
## the side changes, line choice, warnings per intensity (1.0-1.4 s committed, the delayed pounce's final tell
## and the Intense feint), caps per intensity, thread placement (one lane only, never on Krystal, a route to
## every brazier and both deck ends always open), pounce landings (on the deck, inside the rails, clear of
## braziers and threads, never off the deck), the knockback axis (along the bridge: never into the pit or a
## rail), the scorch that keeps her from being a health sponge, and the sac spots (never underfoot, in front).
## Uses the real crossing geometry numbers (data/works_layout_deep.gd CROSSING).

const Rules := preload("res://src/enemies/crossing/crossing_rules.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const PounceMark := preload("res://src/enemies/crossing/pounce_mark.gd")

var BRIDGE: Rect2 = Layout.CROSSING["bridge"]
var RAIL: float = float(Layout.CROSSING["rail"])
var DECK: float = float(Layout.CROSSING["deck_y"])
var ANCHORS: Array = Layout.CROSSING["anchors"]
var BRAZ: Array = Layout.CROSSING["braziers"]


func _walk_rect() -> Rect2:
	# deck + the solid end ledges (x 68..72 and 104..108); the pit is only ACROSS the bridge (behind the rails)
	return Rect2(BRIDGE.position.x - 4.0, -RAIL, BRIDGE.size.x + 8.0, RAIL * 2.0)


func test_phases_follow_exposures_and_she_changes_sides_every_time() -> void:
	assert_eq(Rules.phase_for(0), 1)
	assert_eq(Rules.phase_for(1), 2)
	assert_eq(Rules.phase_for(2), 3)
	assert_eq(Rules.phase_for(5), 3, "phase 3 stays after the third exposure")
	assert_eq(Rules.side_for(0), -1, "phase 1 holds the north lane")
	assert_eq(Rules.side_for(1), 1, "after one exposure she changes sides")
	assert_eq(Rules.side_for(2), -1, "and back again")
	var lines: Array = ANCHORS.slice(0, 3)
	assert_eq(Rules.lines_on_side(lines, -1), [0, 2], "north lines")
	assert_eq(Rules.lines_on_side(lines, 1), [1], "south line")
	# She takes the far line (ahead of Krystal, who comes in from the west gate)
	assert_eq(Rules.pick_line(lines, -1, Vector3(74.0, DECK, 0.0)), 2, "far north line from the west end")
	assert_eq(Rules.pick_line(lines, -1, Vector3(100.0, DECK, 0.0)), 0, "far north line from the east end")
	assert_eq(Rules.pick_line(lines, 1, Vector3(98.0, DECK, 0.0), 2), 1, "the only south line")
	# a tie goes to the line exposed fewer times; never the line just exposed while another exists
	assert_eq(Rules.pick_line(lines, -1, Vector3(88.0, DECK, 0.0), -1, {2: 1}), 0, "tie -> fewer exposures")
	assert_eq(Rules.pick_line(lines, -1, Vector3(74.0, DECK, 0.0), 2), 0, "never the just-exposed line when another exists")
	assert_eq(Rules.rotation(1), ["threads", "pounce", "pounce"], "phase 1 teaches threads + the plain pounce")
	assert_true(Rules.rotation(2).has("delayed") and not Rules.rotation(1).has("delayed"), "the delayed pounce arrives in phase 2")
	assert_true(Rules.rotation(3).has("release") and not Rules.rotation(2).has("release"), "the release is a phase-3 action")


func test_warnings_per_intensity_are_readable_and_the_delayed_pounce_has_a_final_tell() -> void:
	for i in 3:
		var t := float(Rules.T_POUNCE_TELE[i])
		assert_true(t >= 1.0 and t <= 1.4, "committed pounce warning %.2f s within 1.0-1.4 (level %d)" % [t, i])
		assert_true(float(Rules.T_THREAD_TELE[i]) >= 1.0, "thread marks show >= 1 s")
		var d := Rules.delayed_times(i, false)
		assert_true(float(d["total"]) > t, "the delayed pounce waits longer than the plain one")
		assert_true(float(d["final_at"]) >= 1.0, "its ring shows >= 1 s before the final tell")
		assert_true(float(d["total"]) - float(d["final_at"]) >= 0.55, "the final preparation comes >= 0.55 s before the drop")
		assert_true(float(Rules.T_STRANDED[i]) >= 2.3, "~2.5 s recovery after a missed pounce")
		assert_true(float(Rules.T_EXPOSED[i]) > float(Rules.T_STRANDED[i]), "longer vulnerability after an exposure")
		assert_true(float(Rules.T_RECOVER[i]) >= 1.0, "a recovery beat after every action")
	assert_true(float(Rules.T_POUNCE_TELE[0]) >= float(Rules.T_POUNCE_TELE[1]) and float(Rules.T_POUNCE_TELE[1]) >= float(Rules.T_POUNCE_TELE[2]), "Gentle warns longest")
	assert_eq(float(Rules.delayed_times(0, false)["feint_at"]), -1.0, "no feint on Gentle")
	assert_eq(float(Rules.delayed_times(1, false)["feint_at"]), -1.0, "no feint on Standard")
	var di := Rules.delayed_times(2, false)
	assert_true(float(di["feint_at"]) > 0.0 and float(di["feint_at"]) <= float(di["final_at"]) - Rules.FEINT_GAP, "Intense: a feint well before the separate final tell")
	# the feint's shiver is over before the real final tell starts: two separate cues, never one blurred one
	assert_true(Rules.FEINT_GAP > PounceMark.FEINT_TIME, "the gap outlasts the feint shiver")
	for assist in [false, true]:
		var dd := Rules.delayed_times(2, assist)
		assert_true(float(dd["feint_at"]) + PounceMark.FEINT_TIME < float(dd["final_at"]), "shiver ends before the final tell (assist %s)" % str(assist))
	var da := Rules.delayed_times(1, true)
	var dn := Rules.delayed_times(1, false)
	assert_almost(float(da["total"]), float(dn["total"]) * Rules.TIMING_ASSIST_MULT, 0.001, "timing assist stretches the warning")
	assert_true(float(da["total"]) - float(da["final_at"]) > float(dn["total"]) - float(dn["final_at"]), "and the final tell's lead")
	# Intense: less idle, never shorter warnings than the Standard floor of the MP range
	assert_true(float(Rules.T_CLING[2][1]) < float(Rules.T_CLING[1][1]), "Intense idles less")
	assert_true(float(Rules.T_CLING[0][0]) > float(Rules.T_CLING[1][0]), "Gentle idles more")


func test_caps_per_intensity() -> void:
	assert_eq(Rules.THREADS_PER_CAST, [1, 2, 2], "one hazard set: Gentle one thread, else two")
	assert_eq(Rules.MINIONS, [1, 2, 2], "capped release: Gentle one, else two")
	assert_true(float(Rules.MINION_SPEED[0]) < 1.0, "Gentle's minion is slower")
	assert_eq(Rules.MAX_COMMITTED, 1, "one committed attack at a time")


func test_threads_fall_across_one_lane_never_on_krystal_and_leave_every_route() -> void:
	var b2: Vector3 = BRAZ[2]
	var k := Vector3(74.0, DECK, 2.0)
	var segs := Rules.thread_segments(b2, -1, k, 2, BRIDGE, RAIL, DECK)
	assert_eq(segs.size(), 2, "two threads fence the guarded brazier's lane")
	for sg in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		assert_true(a.z < 0.0 and b.z < 0.0, "only across the north lane (the brazier's route)")
		assert_true(absf(b.z) <= Rules.LANE_INNER + 0.001, "stops at the centre line: the other lane stays open")
		assert_true(absf(a.z) <= RAIL, "from the rail")
		assert_true(absf(a.x - b2.x) >= 1.4 and absf(a.x - b2.x) <= Rules.PEN_HALF + 0.01, "either side of the brazier")
		assert_true(Rules.seg_dist(a, b, k) >= Rules.KEEP_CLEAR, "never on Krystal")
	assert_true(absf((segs[0][0] as Vector3).x - (b2.x - Rules.PEN_HALF)) < 0.01, "the thread facing Krystal first")
	var one := Rules.thread_segments(b2, -1, k, 1, BRIDGE, RAIL, DECK)
	assert_eq(one.size(), 1, "Gentle: one thread")
	# Krystal standing where a thread would fall: that one is skipped
	var near := Rules.thread_segments(b2, -1, Vector3(b2.x - Rules.PEN_HALF, DECK, -2.0), 2, BRIDGE, RAIL, DECK)
	assert_eq(near.size(), 1, "the thread over Krystal is skipped")
	for sg in near:
		assert_true(Rules.seg_dist(sg[0], sg[1], Vector3(b2.x - Rules.PEN_HALF, DECK, -2.0)) >= Rules.KEEP_CLEAR)
	# Routes: from anywhere on the deck, every brazier and both ends stay reachable with both threads down
	var targets := Rules.route_targets(BRAZ, BRIDGE)
	var circles := Rules.brazier_circles(BRAZ)
	for line in 3:
		var bz: Vector3 = BRAZ[line]
		var s := -1 if bz.z < 0.0 else 1
		var x := BRIDGE.position.x + 1.0
		while x < BRIDGE.end.x:
			for z in [-3.5, 0.0, 3.5]:
				var from := Vector3(x, DECK, float(z))
				var sg_set := Rules.thread_segments(bz, s, from, 2, BRIDGE, RAIL, DECK)
				assert_true(Rules.route_ok(from, targets, BRIDGE, RAIL, sg_set, circles), "route to every brazier and both ends from %s (line %d)" % [str(from), line])
			x += 4.0
	# ...and the check really does catch a closed route (a thread right across the whole deck)
	var wall := [[Vector3(90.0, DECK, -RAIL), Vector3(90.0, DECK, RAIL)]]
	assert_false(Rules.route_ok(Vector3(80.0, DECK, 0.0), targets, BRIDGE, RAIL, wall, circles), "a full-width wall is refused")


func test_pounce_landings_are_valid_and_never_off_the_deck() -> void:
	var x := BRIDGE.position.x + 0.5
	while x < BRIDGE.end.x:
		for z in [-4.6, -2.0, 0.0, 2.0, 4.6]:
			var k := Vector3(x, DECK, float(z))
			var r := Rules.pounce_landing(k, BRIDGE, RAIL, DECK, BRAZ, [])
			if bool(r["ok"]):
				var p: Vector3 = r["pos"]
				assert_true(Rules.landing_valid(p, BRIDGE, RAIL, DECK, BRAZ, []), "valid landing for %s" % str(k))
				assert_true(absf(p.z) <= RAIL - Rules.LANDING_RAIL_INSET + 0.01, "inside the rails")
				assert_true(Rules.flat(p, k) <= Rules.POUNCE_MAX_OFFSET, "a pounce AT her")
				for b in BRAZ:
					assert_true(Rules.flat(p, b) >= Rules.BRAZIER_CLEAR - 0.01, "never on a brazier")
		x += 1.5
	# Krystal at a brazier: the landing is pushed clear of it (still a pounce at her)
	var at_b := Vector3(98.0, DECK, -2.6)
	var rb := Rules.pounce_landing(at_b, BRIDGE, RAIL, DECK, BRAZ, [])
	assert_true(bool(rb["ok"]), "a pounce can still threaten her beside the brazier")
	assert_true(Rules.flat(rb["pos"], BRAZ[2]) >= Rules.BRAZIER_CLEAR - 0.01)
	# Off the deck: the pit under the bridge, the ledges, the gate corridor - no pounce (never through the deck)
	for off in [Vector3(88.0, -26.0, 0.0), Vector3(70.0, DECK, 0.0), Vector3(106.0, DECK, 6.0), Vector3(65.0, DECK, 0.0), Vector3(88.0, DECK, 8.0)]:
		var ro := Rules.pounce_landing(off, BRIDGE, RAIL, DECK, BRAZ, [])
		assert_false(bool(ro["ok"]), "no pounce at %s (off the deck)" % str(off))
		assert_eq(String(ro["reason"]), "off_deck")
	# Standing threads: the landing keeps clear of them
	var segs := [[Vector3(90.0, DECK, -4.75), Vector3(90.0, DECK, -0.4)]]
	var rt := Rules.pounce_landing(Vector3(90.3, DECK, -2.0), BRIDGE, RAIL, DECK, BRAZ, segs)
	if bool(rt["ok"]):
		assert_true(Rules.seg_dist(segs[0][0], segs[0][1], rt["pos"]) >= Rules.THREAD_CLEAR - 0.01, "never on a thread")
	# The hit test is the marked ring
	var land := Vector3(88.0, DECK, 0.0)
	assert_true(Rules.pounce_hits(land, Vector3(89.9, DECK, 0.0)), "inside the ring")
	assert_true(Rules.pounce_hits(land, Vector3(88.0 + Rules.POUNCE_RADIUS + 0.1, DECK, 0.0)), "her body over the edge")
	assert_false(Rules.pounce_hits(land, Vector3(88.0 + Rules.POUNCE_RADIUS + 0.3, DECK, 0.0)), "outside the ring")
	assert_false(Rules.pounce_hits(land, Vector3(88.0, -26.0, 0.0)), "not through the deck")


func test_knockback_runs_along_the_bridge_never_into_a_void() -> void:
	var walk := _walk_rect()
	var x := BRIDGE.position.x + 1.4
	while x <= BRIDGE.end.x - 1.4:
		for lz in [-3.8, 0.0, 3.8]:
			var land := Vector3(x, DECK, float(lz))
			for dx in [-2.0, -0.5, 0.0, 0.5, 2.0]:
				for dz in [-2.0, 0.0, 2.0]:
					var t := Vector3(clampf(x + float(dx), BRIDGE.position.x, BRIDGE.end.x), DECK, clampf(float(lz) + float(dz), -RAIL, RAIL))
					var d := Rules.push_dir(land, t, BRIDGE)
					assert_eq(d.z, 0.0, "never toward a rail / the pit")
					assert_almost(absf(d.x), 1.0, 0.0001, "along the bridge")
					assert_true(Rules.push_is_safe(t, d, Rules.PUSH_SAFE_DIST, walk, RAIL), "pushed %s -> %s stays on the floor" % [str(t), str(d)])
		x += 2.0
	# at the very ends it pushes toward the middle when dead centre
	assert_eq(Rules.push_dir(Vector3(73.4, DECK, 0.0), Vector3(73.4, DECK, 0.0), BRIDGE), Vector3(1, 0, 0))
	assert_eq(Rules.push_dir(Vector3(102.6, DECK, 0.0), Vector3(102.6, DECK, 0.0), BRIDGE), Vector3(-1, 0, 0))


func test_scorch_keeps_her_from_being_a_health_sponge() -> void:
	# With no weapon damage at all, the flares alone end it in a bounded number of exposures.
	var hp := 320.0
	var n := 0
	while hp > 0.0 and n < 20:
		n += 1
		hp -= 320.0 * Rules.scorch_fraction(n)
	assert_true(n <= 6, "at most six exposures even with zero damage (%d)" % n)
	# Two or three exposures + capped windows: good damage ends it at the second, fair damage by the third.
	var per_window := 320.0 * Rules.WINDOW_CAP_EXPOSED
	assert_true(2.0 * (per_window + 320.0 * Rules.SCORCH_FRAC) >= 320.0, "two maxed exposures can end it")
	assert_true(3.0 * (0.6 * per_window + 320.0 * Rules.SCORCH_FRAC) >= 320.0, "three fair exposures end it")
	assert_true(per_window + 320.0 * Rules.SCORCH_FRAC < 320.0, "never in one")
	# A strong weapon can't skip the rule: blows alone hold at the floor for the exposures made, so the
	# fastest possible win (every window maxed, every missed pounce punished) still takes two exposures.
	assert_almost(Rules.hp_floor(320.0, 0), 192.0, 0.001, "60% before the first exposure")
	assert_almost(Rules.hp_floor(320.0, 1), 80.0, 0.001, "25% before the second")
	assert_eq(Rules.hp_floor(320.0, 2), 0.0, "nothing holds her up from the second exposure on")
	var best := 320.0
	var ex := 0
	while best > 0.0 and ex < 10:
		best = Rules.hp_floor(320.0, ex)                  # unlimited weapon damage before this exposure
		if best <= 0.0:
			break
		ex += 1
		best -= 320.0 * Rules.scorch_fraction(ex)          # the flare
		best = maxf(best - per_window, Rules.hp_floor(320.0, ex))
	assert_eq(ex, 2, "the fastest win takes exactly two exposures")
	# ...and the floors never stop a win: after the second exposure the scorch + one window can end it
	assert_true(Rules.hp_floor(320.0, 1) - 320.0 * Rules.scorch_fraction(2) <= per_window, "exposure two can finish her")


func test_sac_spots_are_in_front_never_underfoot() -> void:
	var k := Vector3(80.0, DECK, 1.0)
	var toward := Vector3(98.0, -5.6, -3.9)
	var spots := Rules.sac_spots(k, toward, 2, BRIDGE, RAIL, DECK, BRAZ, [])
	assert_eq(spots.size(), 2)
	for s in spots:
		var v: Vector3 = s
		assert_true(Rules.flat(v, k) >= Rules.SAC_MIN_PLAYER_DIST, "never underfoot")
		assert_true(v.x > k.x, "in front of her (toward the Matron): no camera spin needed")
		assert_true(absf(v.z) <= RAIL - 1.0, "inside the rails")
		for b in BRAZ:
			assert_true(Rules.flat(v, b) >= Rules.SAC_BRAZIER_CLEAR, "clear of the braziers")
	assert_true(Rules.flat(spots[0], spots[1]) >= Rules.SAC_SEPARATION, "apart")
	var one := Rules.sac_spots(k, toward, 1, BRIDGE, RAIL, DECK, BRAZ, [])
	assert_eq(one.size(), 1, "Gentle: one sac")
