extends "res://tests/test_case.gd"
## The Matron's floor hazards (src/enemies/boss_hazards/*), driven directly through the hazard field:
## web fan geometry + BOUNDED slow (floor, max length, chain cap -> pull free) + expiry; the live cap
## (oldest expires first); fixed trip-line posts that avoid braziers and the entrance; trip-lines never
## under Krystal and always leaving every brazier + the entrance reachable (grid flood fill); snag /
## jump / cut by attack (Krystal only) / burn by lantern; egg sacs far from Krystal, never releasing
## underfoot, poppable, withering; minion cap + guard for a missing enemy script; arachnophobia swap.
## Headless, manual ticks, no saves written.

const Field := preload("res://src/enemies/boss_hazards/hazard_field.gd")
const WebFan := preload("res://src/enemies/boss_hazards/web_fan.gd")
const TripLine := preload("res://src/enemies/boss_hazards/trip_line.gd")
const Combat := preload("res://src/combat/combat.gd")

const DT := 0.05
const CENTER := Vector3.ZERO
const BRAZIERS := [Vector3(6.1, 0, 3.5), Vector3(-6.1, 0, 3.5), Vector3(0, 0, -7.0)]
const ENTRANCE := Vector3(0, 0, 11.0)

var _nodes: Array = []
var _captions: Array = []


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	_captions.clear()
	Settings.set_value("arachnophobia", false)
	Settings.set_value("high_visibility_cues", false)
	Events.caption.connect(_on_caption)


func after_each() -> void:
	Events.caption.disconnect(_on_caption)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("high_visibility_cues", false)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _on_caption(t: String) -> void:
	_captions.append(t)


func _dummy(pos: Vector3, player := false) -> Dummy:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	if player:
		d.add_to_group("player")
	_nodes.append(d)
	return d


func _field(intensity: int = 1) -> Node:
	var f: Node = Field.new()
	var obs: Array = [[CENTER, Field.CENTRE_OBSTACLE]]
	for b in BRAZIERS:
		obs.append([b, 0.6])
	f.setup({"center": CENTER, "radius": 11.5, "floor_y": 0.0, "intensity": intensity, "obstacles": obs, "entrance": ENTRANCE})
	f.route_targets = BRAZIERS.duplicate()
	add_child(f)
	f.cap = Field.cap_for(2, intensity)
	_nodes.append(f)
	return f


func _run(f: Node, d: Node3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		f.tick(DT, d)
		t += DT


func _slow() -> Dictionary:
	var b: Variant = GameState.buffs.get("slow")
	return b if b is Dictionary else {}


# --- Web fan -------------------------------------------------------------------------------------------

func test_fan_is_narrow_telegraphed_and_slows_within_bounds() -> void:
	assert_true(WebFan.sector_contains(CENTER, Vector3.FORWARD, 12.0, 0.5, 7.0, Vector3(0, 0, -4)), "inside the wedge")
	assert_false(WebFan.sector_contains(CENTER, Vector3.FORWARD, 12.0, 0.5, 7.0, Vector3(2.0, 0, -4)), "a step to the side is out (narrow)")
	assert_false(WebFan.sector_contains(CENTER, Vector3.FORWARD, 12.0, 0.5, 7.0, Vector3(0, 0, -8)), "beyond its length")
	var f := _field()
	var d := _dummy(Vector3(0, 0, -4))
	var fan: Node = f.begin_fan(CENTER, d.global_position, 1.2)
	_run(f, d, 1.1)
	assert_false(fan.is_active(), "still only a warning at 1.1 s")
	assert_true(_slow().is_empty(), "a warning never slows")
	_run(f, d, 0.3)
	assert_true(fan.is_active(), "the sheet lands after the 1.2 s warning")
	var s := _slow()
	assert_false(s.is_empty(), "standing in it slows")
	assert_almost(float(s.get("mult", 1.0)), 0.6, 0.001, "Standard fan slow x0.6")
	assert_true(float(s.get("mult", 0.0)) >= Field.SLOW_FLOOR, "never below the floor")
	assert_true(float(s.get("remaining", 99.0)) <= Field.SLOW_MAX_SECONDS, "a short, refreshed slow")
	# Stepping out: the field stops refreshing it (the buff runs out on its own).
	GameState.buffs.erase("slow")
	d.global_position = Vector3(3.0, 0, -4)
	_run(f, d, 0.5)
	assert_true(_slow().is_empty(), "out of the wedge = not slowed")


func test_slow_cannot_chain_forever() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, -4))
	f.begin_fan(CENTER, d.global_position, 0.0)
	_run(f, d, Field.SLOW_CHAIN_CAP - 0.2)
	assert_false(_slow().is_empty(), "slowed while standing in the veil")
	_run(f, d, 0.4)
	assert_true(_slow().is_empty(), "after %.1f s she tears free" % Field.SLOW_CHAIN_CAP)
	assert_true(bool(f.slow_immune()), "and is briefly immune")
	assert_true(_captions.has("[Krystal tears free of the silk]"), "captioned")
	_run(f, d, Field.SLOW_IMMUNE - 0.2)
	assert_true(_slow().is_empty(), "no slow during the immunity")
	f.apply_slow(0.1, 30.0)
	assert_true(_slow().is_empty(), "apply_slow respects the immunity too")
	_run(f, d, 0.4)
	var s := _slow()
	assert_false(s.is_empty(), "slowed again afterwards (the fan is still there)")
	f.apply_slow(0.1, 30.0)
	s = _slow()
	assert_almost(float(s["mult"]), Field.SLOW_FLOOR, 0.001, "clamped to the floor")
	assert_true(float(s["remaining"]) <= Field.SLOW_MAX_SECONDS + 0.001, "clamped in length")


func test_fans_expire_and_the_live_cap_drops_the_oldest() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, -4))
	var first: Node = f.begin_fan(CENTER, Vector3(0, 0, -4), 0.2)
	assert_eq(int(f.cap), 3, "Standard phase 2: three live hazards")
	var later: Array = []
	for i in 4:
		later.append(f.begin_fan(CENTER, Vector3(float(i) - 2.0, 0, -4), 0.2))
	assert_true(int(f.live_count()) <= 3, "never more than the cap (%d)" % int(f.live_count()))
	assert_false(first.is_live(), "the oldest expired early to make room")
	_run(f, d, 0.2 + float(Field.FAN_LIFE[1]) + WebFan.FADE + 0.2)
	assert_eq(int(f.live_count()), 0, "every fan expires on its own")
	assert_eq((f.hazards as Array).size(), 0, "and is removed")
	assert_eq(Field.cap_for(2, 0), 2, "Gentle phase 2 cap")
	assert_eq(Field.cap_for(3, 2), 1, "phase 3: one ground hazard at a time")


# --- Trip-lines -------------------------------------------------------------------------------------------

func test_posts_are_fixed_and_avoid_braziers_and_the_entrance() -> void:
	var f := _field()
	var posts: Array = f.posts
	assert_eq(posts.size(), Field.POST_COUNT)
	for p in posts:
		var pv: Vector3 = p
		assert_true(Vector2(pv.x, pv.z).length() < 11.5 - 3.0, "post inside the arena with a wide gap to the wall")
		for b in BRAZIERS:
			assert_true(Vector2(pv.x - b.x, pv.z - b.z).length() >= 2.5, "post clear of brazier %s" % str(b))
	var again := Field.default_posts(CENTER, 11.5, [CENTER] + BRAZIERS, ENTRANCE, 0.0)
	assert_eq(again, posts, "deterministic")
	for c in f.chords:
		var a: Vector3 = posts[c[0]]
		var b: Vector3 = posts[c[1]]
		assert_true(TripLine.seg_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(ENTRANCE.x, ENTRANCE.z)) >= Field.ENTRANCE_CLEAR, "no chord across the entrance")
	assert_true((f.chords as Array).size() >= 6, "enough spans to choose from")


func test_route_check_is_a_real_flood_fill() -> void:
	var wall := [[Vector3(-12, 0, 0), Vector3(12, 0, 0)]]
	assert_false(Field.route_exists(Vector3(0, 0, 5), Vector3(0, 0, -5), CENTER, 11.5, wall, []), "a full-width line blocks")
	var gap := [[Vector3(-12, 0, 0), Vector3(8, 0, 0)]]
	assert_true(Field.route_exists(Vector3(0, 0, 5), Vector3(0, 0, -5), CENTER, 11.5, gap, []), "a line with a gap at one end does not")
	assert_true(Field.route_exists(Vector3(0, 0, 5), Vector3(0, 0, -5), CENTER, 11.5, [], []), "open floor")


func test_trip_lines_never_under_krystal_and_always_leave_routes() -> void:
	var f := _field(2)
	var tested := 0
	for x in range(-8, 9, 4):
		for z in range(-8, 9, 4):
			var p := Vector3(float(x), 0, float(z))
			if Vector2(p.x, p.z).length() > 9.0 or Vector2(p.x, p.z).length() < 1.5:
				continue
			f.clear_all(false)
			var lines: Array = f.begin_trips(2, 1.2, p)
			assert_true(lines.size() >= 1, "lines found for Krystal at %s" % str(p))
			var segs: Array = f.active_segments()
			for l in lines:
				assert_true(float(l.distance_to(p)) >= Field.TRIP_MIN_PLAYER_DIST, "never under her (%s)" % str(p))
			var circles: Array = []
			for o in f.obstacles:
				circles.append(o)
			for b in BRAZIERS:
				assert_true(Field.route_exists(p, b, CENTER, 11.5, segs, circles), "brazier %s reachable from %s" % [str(b), str(p)])
			assert_true(Field.route_exists(p, ENTRANCE, CENTER, 11.5, segs, circles), "entrance reachable from %s" % str(p))
			tested += 1
	assert_true(tested >= 8, "sampled %d spots" % tested)


func test_trip_line_snags_once_and_a_jump_clears_it() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, 9))
	var lines: Array = f.begin_trips(1, 1.2, d.global_position)
	assert_eq(lines.size(), 1)
	var line: Node = lines[0]
	var mid: Vector3 = (line.a + line.b) * 0.5
	d.global_position = mid + Vector3(0, 0.8, 0)          # mid-jump over it while it forms
	_run(f, d, 1.3)
	assert_true(line.is_active(), "formed after 1.2 s")
	assert_eq(int(f.snags), 0, "a jump clears it")
	assert_almost(float(d.health.hp), 100.0, 0.001)
	d.global_position = mid
	_run(f, d, DT)
	assert_eq(String(line.cut_by), "snag", "walking into it snaps it")
	assert_almost(float(d.health.hp), 100.0 - Field.SNAG_DAMAGE, 0.001, "a little damage (Standard)")
	assert_almost(float(_slow().get("mult", 1.0)), float(Field.SNAG_SLOW[1]), 0.001, "a short bounded slow")
	_run(f, d, 1.0)
	assert_eq(int(f.snags), 1, "only once")


func test_trip_line_is_cut_by_krystal_and_burned_by_her_lantern() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, 9), true)
	var lines: Array = f.begin_trips(1, 0.0, d.global_position)
	var line: Node = lines[0]
	var near: Vector3 = line.nearest_point(d.global_position)
	var away := Vector3(d.global_position.x - near.x, 0, d.global_position.z - near.z).normalized()
	# A companion (not Krystal) is refused by the contract and cannot cut it even if it swings.
	var pet := _dummy(near + away * 1.5)
	assert_false(bool(line.can_be_hit_by(pet)), "companions leave lines alone")
	assert_true(bool(line.can_be_hit_by(d)), "Krystal can cut it")
	_run(f, d, DT)
	Combat.melee(pet, pet.global_position + Vector3.UP * 0.9, -away, 2.2, 110.0, 5.0, ["enemy"], 0.0)
	assert_true(line.is_active(), "a stray companion hit does not cut it")
	d.global_position = near + away * 1.5
	_run(f, d, DT)
	var hits: Array = Combat.melee(d, d.global_position + Vector3.UP * 0.9, -away, 2.2, 110.0, 5.0, ["enemy"], 0.0)
	assert_true(hits.has(line), "her swing reaches the line")
	assert_eq(String(line.cut_by), "attack", "cut")
	# Burn: a lit lantern held close for BURN_TIME.
	f.clear_all(false)
	var d2 := _dummy(Vector3(0, 0, 9), true)
	var l2: Node = (f.begin_trips(1, 0.0, d2.global_position) as Array)[0]
	var n2: Vector3 = l2.nearest_point(d2.global_position)
	d2.global_position = n2 + Vector3(d2.global_position.x - n2.x, 0, d2.global_position.z - n2.z).normalized() * 1.2
	_run(f, d2, 0.6)
	assert_true(l2.is_active(), "no light, no burn")
	d2.lantern_on = true
	_run(f, d2, TripLine.BURN_TIME + 0.1)
	assert_eq(String(l2.cut_by), "lantern", "burned by her lantern")


# --- Sacs & minions -------------------------------------------------------------------------------------------

func test_sacs_hatch_far_away_never_underfoot_and_can_be_popped() -> void:
	var f := _field()
	var spawned: Array = []
	f.minion_cap = 2
	f.minion_override = func(pos: Vector3, _params: Dictionary) -> Node:
		var n := Node3D.new()
		add_child(n)
		n.global_position = pos
		_nodes.append(n)
		spawned.append(n)
		return n
	var d := _dummy(Vector3(0, 0, 3))
	var sacs: Array = f.begin_sacs(2, 3.0, d.global_position)
	assert_eq(sacs.size(), 2, "two sacs on Standard")
	for s in sacs:
		assert_true(Vector2(s.pos.x - 0.0, s.pos.z - 3.0).length() >= Field.SAC_MIN_PLAYER_DIST, "far from Krystal")
	assert_true(Vector2(sacs[0].pos.x - sacs[1].pos.x, sacs[0].pos.z - sacs[1].pos.z).length() >= Field.SAC_SEPARATION, "apart")
	assert_true(bool(f.sacs_pending()))
	# She rushes the first one and stands right on it as it becomes due: it waits.
	d.global_position = sacs[0].pos + Vector3(0.5, 0, 0)
	_run(f, d, 3.2)
	assert_eq(spawned.size(), 1, "only the other one hatched (never underfoot)")
	assert_true(Vector2(spawned[0].global_position.x - d.global_position.x, spawned[0].global_position.z - d.global_position.z).length() >= Field.SAC_CLEAR_DIST, "and not next to her")
	assert_true(bool(sacs[0].is_pending()), "the one she stands on is still waiting")
	# She pops it.
	sacs[0].health.apply_damage(20.0, d, Vector3.FORWARD)
	assert_true(bool(sacs[0].popped), "popped by an attack")
	_run(f, d, 1.0)
	assert_eq(spawned.size(), 1, "a popped sac releases nothing")
	assert_false(bool(f.sacs_pending()))
	assert_eq(int(f.alive_minions()), 1)


func test_sac_withers_if_she_camps_on_it_and_minions_are_capped() -> void:
	var f := _field(0)
	var spawned: Array = []
	f.minion_cap = 1
	f.minion_override = func(pos: Vector3, _params: Dictionary) -> Node:
		var n := Node3D.new()
		add_child(n)
		n.global_position = pos
		_nodes.append(n)
		spawned.append(n)
		return n
	var d := _dummy(Vector3(0, 0, 3))
	var sacs: Array = f.begin_sacs(1, 3.6, d.global_position)
	assert_eq(sacs.size(), 1, "Gentle: one sac")
	d.global_position = sacs[0].pos
	_run(f, d, 3.6 + Field.SAC_MAX_DELAY + 0.3)
	assert_eq(spawned.size(), 0, "camping on it lets it wither harmlessly")
	assert_true(bool(sacs[0].popped))
	# Cap: a second spawn beyond the cap is refused.
	d.global_position = Vector3(0, 0, 3)
	assert_not_null(f.spawn_minion(Vector3(8, 0, 0)))
	assert_null(f.spawn_minion(Vector3(-8, 0, 0)), "Gentle cap = 1 alive")
	f.dismiss_minions()
	await wait_frames(1)
	assert_eq(int(f.alive_minions()), 0, "dismissed minions are gone")


func test_missing_minion_script_is_guarded() -> void:
	var f := _field()
	f.minion_id = "no_such_enemy_b9"
	f.minion_cap = 2
	f.minion_parent = self
	assert_null(f.spawn_minion(Vector3(8, 0, 0)), "no script -> no minion, no crash")
	var d := _dummy(Vector3(0, 0, 3))
	f.begin_sacs(2, 0.5, d.global_position)
	_run(f, d, 1.0)
	assert_eq(int(f.alive_minions()), 0)
	assert_true(_captions.has("[the sac splits open, empty]"), "an empty sac is captioned")


# --- Clearing & arachnophobia -------------------------------------------------------------------------------

func test_clear_all_removes_everything_at_once() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, 3))
	f.begin_fan(CENTER, d.global_position, 0.0)
	f.begin_trips(2, 0.0, d.global_position)
	f.begin_sacs(2, 3.0, d.global_position)
	f.begin_thread(Vector3(0, 8, 0), Vector3(6.1, 1.5, 3.5))
	f.apply_slow(0.6, 1.0)
	assert_true(int(f.live_count()) >= 2)
	f.clear_all(true)
	assert_eq(int(f.live_count()), 0, "no live fan/line")
	assert_false(bool(f.sacs_pending()), "no pending sac")
	assert_true(f.thread == null, "no thread")
	assert_true(_slow().is_empty(), "no lingering slow")
	assert_true(bool(f.is_clear()))
	_run(f, d, 1.0)
	assert_eq((f.hazards as Array).size(), 0, "faded out and freed")


func test_arachnophobia_swaps_every_hazard_live() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, 9))
	var fan: Node = f.begin_fan(CENTER, Vector3(0, 0, -4), 0.0)
	var line: Node = (f.begin_trips(1, 0.0, d.global_position) as Array)[0]
	var sac: Node = (f.begin_sacs(1, 3.0, d.global_position) as Array)[0]
	var th: Node = f.begin_thread(Vector3(0, 8, 0), Vector3(6.1, 1.5, 3.5))
	Settings.set_value("arachnophobia", true)
	await wait_frames(1)
	assert_true(bool(f.alt) and bool(fan.alt) and bool(line.alt) and bool(sac.alt) and bool(th.alt), "all switched to the veil / root / pod look")
	assert_true(fan.is_active() and line.is_active() and bool(sac.is_pending()), "their state is untouched")
	d.global_position = line.nearest_point(d.global_position)
	_run(f, d, DT)
	assert_true(_captions.has("[a pale root snags her ankle]"), "non-arachnid caption")
	Settings.set_value("arachnophobia", false)
	await wait_frames(1)
	assert_false(bool(fan.alt), "and back")


## Settings "high_visibility_cues" (comfort): every live hazard shows a bold cream outline at once (fan wedge
## edges + arc, the trip-line, the sac's outer ring, the knot's collar), new ones are built with it, an ended
## hazard drops it, and the arachnophobia rebuild keeps it.
func test_high_visibility_cues_outline_every_hazard_live() -> void:
	var f := _field()
	var d := _dummy(Vector3(0, 0, 9))
	var fan: Node = f.begin_fan(CENTER, Vector3(0, 0, -4), 1.0)
	var line: Node = (f.begin_trips(1, 1.0, d.global_position) as Array)[0]
	var sac: Node = (f.begin_sacs(1, 3.0, d.global_position) as Array)[0]
	var th: Node = f.begin_thread(Vector3(0, 8, 0), Vector3(6.1, 1.5, 3.5))
	for h in [fan, line, sac, th]:
		assert_false(bool(h.bold_visible()), "no outline by default (%s)" % String(h.name))
	Settings.set_value("high_visibility_cues", true)
	for h in [fan, line, sac, th]:
		assert_true(bool(h.bold_visible()), "outlined live (%s)" % String(h.name))
	var fan2: Node = f.begin_fan(CENTER, Vector3(3, 0, -4), 1.0)
	assert_true(bool(fan2.bold_visible()), "a new hazard is built with it")
	line.snap("attack")
	sac.pop()
	assert_false(bool(line.bold_visible()), "a cut line drops its outline")
	assert_false(bool(sac.bold_visible()), "a popped sac too")
	Settings.set_value("arachnophobia", true)
	await wait_frames(1)
	assert_true(bool(fan2.bold_visible()) and bool(th.bold_visible()), "kept through the arachnophobia rebuild")
	Settings.set_value("high_visibility_cues", false)
	assert_false(bool(fan2.bold_visible()) or bool(th.bold_visible()), "and off again")


# --- Performance -------------------------------------------------------------------------------------------------

## A full phase-2 floor (cap hazards, two sacs, a thread) ticks cheaply: well under a tenth of a
## millisecond per frame on average (no group scans, no per-frame allocations in the loop).
func test_a_busy_floor_ticks_cheaply() -> void:
	var f := _field(2)
	var d := _dummy(Vector3(0, 0, 3))
	f.begin_fan(CENTER, Vector3(0, 0, -4), 0.0)
	f.begin_trips(2, 0.0, d.global_position)
	f.begin_sacs(2, 99.0, d.global_position)
	f.begin_thread(Vector3(0, 8, 0), Vector3(6.1, 1.5, 3.5))
	var t0 := Time.get_ticks_usec()
	for i in 1200:
		d.global_position = Vector3(sin(float(i) * 0.05) * 3.0, 0, 3.0)
		f.tick(1.0 / 60.0, d)
	var us := float(Time.get_ticks_usec() - t0) / 1200.0
	assert_true(us < 150.0, "%.1f us per tick" % us)
