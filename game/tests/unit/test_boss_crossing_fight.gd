extends "res://tests/test_case.gd"
## Weaver's Crossing rematch - the boss state machine (src/enemies/crossing_matron.gd) on a bare test deck
## (a floor slab + three real line-braziers at the crossing's coordinates, a stand-in for Krystal, manual
## ticks): encounter events, the thread cast then the pounce with its timings, ONE hit through Krystal's
## health path, knockback along the bridge, the stranded window + cap, exposure only under her anchor (wasted
## flares elsewhere), the side change + phase events, the delayed pounce's audible AND visible final tell (and
## the Intense feint), the capped release INSTEAD of - never with - a pounce (caps per intensity), line of
## sight / no pounce through the deck, companions only in exposed phases, the reset policy, the defeat
## committed exactly once before any presentation (weaver_defeated untouched), the arachnophobia swap, and the
## scorch that keeps her from being a health sponge. Headless, no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/crossing_matron.gd")
const Rules := preload("res://src/enemies/crossing/crossing_rules.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const ShadeVisual := preload("res://src/enemies/shade_visual.gd")
const WeaverVisual := preload("res://src/enemies/weaver_visual.gd")

const DT := 0.05
const ID := "crossing_matron"

var _nodes: Array = []
var _events: Array = []
var _caps: Array = []
var _saved := {}


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false
	var knocks: Array = []
	var hits: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 5000.0
		add_child(health)
		collision_layer = 2
		collision_mask = 0
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: hits += 1)

	func knockback(dir: Vector3, force: float) -> void:
		knocks.append([dir, force])


class RealKrystal extends CharacterBody3D:
	var health: Node
	var lantern_on := false
	var knocks: Array = []
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/player/player_health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		collision_mask = 0
		add_to_group("player")
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(dir: Vector3, force: float) -> void:
		knocks.append([dir, force])


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	_events.clear()
	_caps.clear()
	for k in ["arachnophobia", "timing_assist", "high_visibility_cues", "reduce_flashing"]:
		_saved[k] = Settings.get_value(k)
		Settings.set_value(k, false)
	Events.boss_encounter_changed.connect(_on_enc)
	Events.boss_phase_changed.connect(_on_phase)
	Events.boss_health_changed.connect(_on_hp)
	Events.boss_defeated.connect(_on_def)
	Events.caption.connect(_on_cap)


func after_each() -> void:
	Events.boss_encounter_changed.disconnect(_on_enc)
	Events.boss_phase_changed.disconnect(_on_phase)
	Events.boss_health_changed.disconnect(_on_hp)
	Events.boss_defeated.disconnect(_on_def)
	Events.caption.disconnect(_on_cap)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("hw_thread"):
		n.queue_free()
	_nodes.clear()
	for k in _saved:
		Settings.set_value(k, _saved[k])
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _on_enc(id: String, active: bool) -> void:
	_events.append(["enc", id, active])


func _on_phase(id: String, p: int) -> void:
	_events.append(["phase", id, p])


func _on_hp(id: String, hp: float, mx: float) -> void:
	_events.append(["hp", id, hp, mx])


func _on_def(id: String) -> void:
	_events.append(["defeated", id])


func _on_cap(t: String) -> void:
	_caps.append(t)


func _count(kind: String, id: String = ID) -> int:
	var n := 0
	for e in _events:
		if e[0] == kind and e[1] == id:
			n += 1
	return n


# --- Fixture ---------------------------------------------------------------------------------------------

func _deck() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(44.0, 0.4, 12.0)
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(88.0, -18.2, 0.0)
	_nodes.append(body)


func _braziers() -> Array:
	var out: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "tcb%d" % i})
		b.set_meta("anchor_index", i)
		add_child(b)
		b.global_position = Layout.CROSSING["braziers"][i]
		b.set_process(false)
		out.append(b)
		_nodes.append(b)
	return out


func _dummy(pos: Vector3, groups: Array = ["player"]) -> Dummy:
	var d := Dummy.new()
	for g in groups:
		d.add_to_group(g)
	add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _boss(target: Node3D, brs: Array, level: int = 1) -> Node:
	var b: Node = Factory.create(ID, {"arena_center": Layout.CROSSING["center"], "arena_radius": Layout.CROSSING["radius"],
		"anchors": Layout.CROSSING["anchors"], "braziers": brs, "crack": Layout.CROSSING["crack"],
		"bridge": Layout.CROSSING["bridge"], "deck_y": Layout.CROSSING["deck_y"]})
	assert_not_null(b, "factory knows crossing_matron")
	b.target_override = target
	b.intensity_override = level
	b.fast_defeat = true
	add_child(b)
	b.set_process(false)
	_nodes.append(b)
	return b


func _setup(level: int = 1, kpos: Vector3 = Vector3(74.0, -18.0, 2.0)) -> Array:
	_deck()
	var brs := _braziers()
	var k := _dummy(kpos)
	var b := _boss(k, brs, level)
	await wait_physics(2)          # the deck and the braziers are in the physics space (landing / sight rays)
	b.start_fight()
	return [b, k, brs]


func _tick(b: Node, seconds: float) -> void:
	var n := int(ceil(seconds / DT))
	for i in n:
		b.tick(DT)


## Ticks until cond() is true (or max seconds); returns the time it took (INF if never).
func _until(b: Node, cond: Callable, max_s: float = 30.0) -> float:
	var t := 0.0
	while t < max_s:
		if bool(cond.call()):
			return t
		b.tick(DT)
		t += DT
	return INF if not bool(cond.call()) else t


func _to_state(b: Node, s: String, max_s: float = 30.0) -> bool:
	return _until(b, func() -> bool: return String(b.state) == s, max_s) < INF


## Drives her to the next cling (skipping the intro / recovery).
func _to_cling(b: Node) -> void:
	_to_state(b, "cling", 20.0)


## Exposes her through the real rule: the line-brazier under her anchor flares; then waits out the window.
func _expose(b: Node, brs: Array) -> void:
	_to_cling(b)
	var br: Node = brs[int(b.held_line)]
	if bool(br.call("is_lit")):
		br.call("flare")
	else:
		br.call("light")


# --- Tests -------------------------------------------------------------------------------------------------

func test_start_emits_the_encounter_events_and_she_holds_the_far_north_line() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var brs: Array = s[2]
	assert_eq(_count("enc"), 1, "boss_encounter_changed(crossing_matron, true)")
	assert_true(_events.has(["enc", ID, true]))
	assert_true(_events.has(["phase", ID, 1]), "boss_phase_changed(crossing_matron, 1)")
	assert_true(_events.has(["hp", ID, 320.0, 320.0]), "the bar shows 320 hp (data)")
	assert_eq(String(b.state), "intro")
	assert_eq(int(b.held_line), 2, "the far north line (ahead of Krystal coming from the gate)")
	assert_eq(int(b.side), -1, "north lane")
	assert_true(bool(b.health.invulnerable), "armoured on the ceiling")
	assert_true(b.is_in_group("enemy") and b.is_threatening(), "a threat while the fight is on (no saving)")
	for br in brs:
		assert_true(bool(br.get("reusable")), "line-braziers can be stoked again once lit")
	assert_false(bool(GameState.get_flag("weaver_defeated")), "Chapter One untouched")


func test_threads_then_a_pounce_hits_once_through_her_health_along_the_bridge() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	assert_true(_to_state(b, "cast"), "the first action teaches the threads")
	var marks := 0
	for m in b.find_children("ThreadMark*", "", false, false):
		if bool(m.call("is_showing")):
			marks += 1
	assert_eq(marks, 2, "two floor marks show where the threads will fall")
	var t_cast := _until(b, func() -> bool: return String(b.state) != "cast")
	assert_almost(t_cast, float(Rules.T_THREAD_TELE[1]), DT * 1.5, "thread marks for 1.2 s")
	assert_eq(int(b.live_threads()), 2, "two threads across the north lane")
	for t in b.thread_nodes():
		var tn: Node3D = t
		assert_true(tn.global_position.z < 0.0, "the guarded brazier's lane")
		assert_true(absf(tn.global_position.x - 98.0) > 1.3, "either side of the brazier")
	assert_eq(String(b.state), "recover", "a recovery beat after the cast")
	assert_true(_to_state(b, "pounce_tele"), "then a pounce at the other route")
	var fp: Dictionary = b.pounce_mark().call("footprint")
	assert_true(bool(fp["visible"]) and not bool(fp["delayed"]), "the ring is shown")
	assert_false(bool(b.pounce_mark().call("inner_visible")), "a plain pounce is a single ring")
	assert_almost(float(fp["radius"]), Rules.POUNCE_RADIUS, 0.001, "the ring IS the hit test")
	assert_true(Rules.flat(fp["center"], k.global_position) <= Rules.POUNCE_MAX_OFFSET, "at Krystal")
	var t_tele := _until(b, func() -> bool: return String(b.state) != "pounce_tele")
	assert_almost(t_tele, float(Rules.T_POUNCE_TELE[1]), DT * 1.5, "1.3 s warning (Standard)")
	assert_true(_to_state(b, "rebound", 2.0), "she lands on Krystal")
	assert_eq(k.hits, 1, "ONE hit through Krystal's health")
	assert_almost(float(k.health.max_hp - k.health.hp), 20.0, 0.01, "data damage x Standard 1.0")
	assert_eq(k.knocks.size(), 1)
	var dir: Vector3 = k.knocks[0][0]
	assert_eq(dir.z, 0.0, "knocked along the bridge, never toward a rail or the pit")
	assert_almost(absf(dir.x), 1.0, 0.001)
	assert_false(b.is_vulnerable(), "a pounce that hit leaves no opening")
	assert_eq(int(b.stats["hits"]), 1)


func test_a_missed_pounce_strands_her_with_a_capped_window() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	assert_true(_to_state(b, "pounce_tele"))
	k.global_position += Vector3(0.0, 0.0, -5.0) if k.global_position.z > 0.0 else Vector3(0.0, 0.0, 5.0)
	k.global_position = Vector3(float(b.current_landing().x) + 4.0, -18.0, k.global_position.z)
	var t := _until(b, func() -> bool: return String(b.state) == "stranded", 3.0)
	assert_true(t < INF, "missed: stranded")
	assert_eq(k.hits, 0, "dodged")
	assert_almost(float(b.get("_state_len")), float(Rules.T_STRANDED[1]), 0.001, "~2.5 s recovery after a missed pounce")
	assert_true(b.is_vulnerable() and not bool(b.health.invulnerable))
	var companion := _dummy(Vector3(88.0, -18.0, 0.0), ["companion"])
	var outside := _dummy(Vector3(50.0, -18.0, 0.0), ["companion"])
	assert_true(bool(b.can_be_hit_by(k)), "Krystal may strike")
	assert_true(bool(b.can_be_hit_by(companion)), "a companion on the bridge may join in")
	assert_false(bool(b.can_be_hit_by(outside)), "never from outside the crossing")
	var hp0: float = float(b.health.hp)
	for i in 5:
		b.health.apply_damage(20.0, k, Vector3.ZERO)
	var cap := 320.0 * Rules.WINDOW_CAP_STRANDED
	assert_true(hp0 - float(b.health.hp) <= cap + 20.0, "the stranded window is capped (%.1f)" % (hp0 - float(b.health.hp)))
	assert_eq(String(b.state), "climb", "she scrambles back up once the cap is reached")


func test_exposure_only_under_her_anchor_then_she_changes_sides() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var brs: Array = s[2]
	_to_cling(b)
	assert_eq(int(b.held_line), 2)
	(brs[0] as Node).call("light")
	assert_eq(int(b.exposures), 0, "a flare under an empty anchor exposes nothing")
	assert_eq(int(b.stats["wasted_flares"]), 1)
	assert_true(_caps.has("[the light flares under an empty anchor]"), "captioned (muted play)")
	assert_true(b.is_overhead())
	(brs[2] as Node).call("light")
	assert_eq(int(b.exposures), 1, "the brazier under HER anchor exposes her")
	assert_eq(String(b.state), "scorch_fall")
	assert_true(_events.has(["phase", ID, 2]), "boss_phase_changed(crossing_matron, 2)")
	assert_eq(int(b.phase), 2)
	assert_true(_to_state(b, "exposed", 2.0))
	assert_almost(float(b.health.hp), 320.0 * (1.0 - Rules.SCORCH_FRAC), 0.01, "the flare scorched her (10%)")
	assert_true(b.is_vulnerable())
	assert_almost(float(b.health.damage_taken_mult), Rules.EXPOSED_MULT, 0.001)
	assert_almost(float(b.get("_state_len")), float(Rules.T_EXPOSED[1]), 0.001, "a long opening")
	assert_eq(int(b.live_threads()), 0, "the light burned her threads")
	assert_true(bool(b.anchor_marks().call("exposed_glowing", 2)), "the exposed anchor glows")
	assert_true(_to_state(b, "climb", 8.0), "then she climbs away...")
	assert_eq(int(b.side), 1, "...to the other side")
	assert_eq(int(b.held_line), 1, "the south line")
	assert_true(_caps.has("[she scrambles across the ceiling to the far side]"))
	# ...and really across the ceiling: straight up first, never a diagonal flight through the open hall
	var start: Vector3 = b.global_position
	var high := float(b.climb_xform(1.0).origin.y)
	for i in 21:
		var p: Vector3 = b.climb_xform(float(i) / 20.0).origin
		if Rules.flat(p, start) > 0.5:
			assert_true(p.y >= high - 0.5, "away from where she lay only under the ceiling (y %.2f at step %d)" % [p.y, i])
	_to_cling(b)
	assert_true(Rules.flat(b.global_position, Layout.CROSSING["anchors"][1]) < 0.5, "hanging from the south anchor")


func test_delayed_pounce_has_an_audible_and_visible_final_tell() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	var brs: Array = s[2]
	_expose(b, brs)
	k.global_position = Vector3(80.0, -18.0, 2.0)
	assert_true(_to_state(b, "pounce_tele", 30.0))
	# phase 2 rotation: threads, then the delayed pounce
	var fp: Dictionary = b.pounce_mark().call("footprint")
	assert_true(bool(fp["delayed"]), "phase 2 brings the delayed pounce")
	assert_true(bool(b.pounce_mark().call("inner_visible")), "a double ring from the start (shape cue, not only a pulse rhythm)")
	var d := Rules.delayed_times(1, false)
	var t_final := _until(b, func() -> bool: return bool(b.final_tell_shown()), 5.0)
	assert_almost(t_final, float(d["final_at"]), DT * 1.5, "the final preparation at %.2f s" % float(d["final_at"]))
	assert_true(_caps.has("[a sharp final rattle - she lets go!]"), "audible half, captioned")
	fp = b.pounce_mark().call("footprint")
	assert_true(bool(fp["final"]), "visible half: the ring snaps solid")
	assert_true(bool(b.pounce_mark().call("strand_visible")), "visible half: a strand drops to the mark")
	assert_true(bool(b.look.get("final_tell")), "visible half: she coils (halo)")
	assert_eq(String(b.state), "pounce_tele", "she has not dropped yet")
	var t_drop := _until(b, func() -> bool: return String(b.state) != "pounce_tele", 3.0)
	assert_almost(t_drop, float(d["total"]) - float(d["final_at"]), DT * 1.5, "the drop follows the final tell by its lead")
	assert_eq(int(b.stats["feints"]), 0, "no feint on Standard")
	assert_true(float(d["total"]) >= 1.0 and float(d["final_at"]) >= 1.0, "a readable warning first")


func test_intense_adds_a_feint_but_keeps_the_separate_final_tell() -> void:
	var s: Array = await _setup(2)
	var b: Node = s[0]
	var brs: Array = s[2]
	_expose(b, brs)
	assert_true(_to_state(b, "pounce_tele", 30.0))
	var d := Rules.delayed_times(2, false)
	_until(b, func() -> bool: return int(b.stats["feints"]) > 0, 3.0)
	assert_eq(int(b.stats["feints"]), 1, "Intense: one feint shiver")
	assert_false(bool(b.final_tell_shown()), "the feint is not the final tell")
	assert_true(_caps.has("[she shifts her grip...]"))
	var t_final := _until(b, func() -> bool: return bool(b.final_tell_shown()), 3.0)
	assert_true(t_final < INF, "the final tell still comes")
	assert_true(float(d["total"]) - float(d["final_at"]) >= 0.55, "with its full lead")


func test_release_replaces_the_delayed_pounce_and_never_overlaps_a_pounce_caps_per_intensity() -> void:
	for level in 3:
		for n in _nodes:
			if is_instance_valid(n):
				n.queue_free()
		_nodes.clear()
		await wait_frames(1)
		var s: Array = await _setup(level)
		var b: Node = s[0]
		var k: Dummy = s[1]
		var spawned: Array = []
		var make := func(pos: Vector3, params: Dictionary) -> Node:
			var m := Node3D.new()
			m.set_meta("params", params)
			add_child(m)
			m.global_position = pos
			_nodes.append(m)
			spawned.append(m)
			return m
		b.release_node().set("minion_override", make)
		# phase 3 (two exposures made)
		b.exposures = 2
		b.phase = 3
		b.side = Rules.side_for(2)
		_to_cling(b)
		b._step = 1                   # the rotation slot of the release
		k.global_position = Vector3(76.0, -18.0, 2.0)
		b.set("_state_len", 0.0)
		b.tick(DT)
		assert_eq(String(b.state), "release", "level %d: the release instead of the delayed pounce" % level)
		var sacs: Array = b.release_node().get("sacs")
		assert_eq(sacs.size(), int(Rules.MINIONS[level]), "level %d: sac cap" % level)
		for sac in sacs:
			assert_true(Rules.flat((sac as Node3D).global_position, k.global_position) >= Rules.SAC_MIN_PLAYER_DIST, "never underfoot")
		assert_false(bool(b.call("_begin_pounce", true)), "no delayed pounce while a sac is pending")
		assert_false(bool(b.call("_begin_pounce", false)), "no pounce at all while a sac is pending")
		# a pending sac never hatches during a pounce telegraph / drop
		b.call("_enter", "pounce_tele", 10.0)
		b.release_node().call("tick", float(Rules.SAC_WARN[level]) + 0.5, k, bool(b.call("_release_allowed")))
		assert_eq(spawned.size(), 0, "never hatches while a pounce is telegraphed")
		b.call("_enter", "recover", 0.5)
		b.release_node().call("tick", 0.1, k, bool(b.call("_release_allowed")))
		assert_eq(spawned.size(), int(Rules.MINIONS[level]), "level %d: minion cap" % level)
		assert_eq(int(b.minions_alive()), int(Rules.MINIONS[level]))
		if level == 0:
			assert_true(float((spawned[0] as Node).get_meta("params")["speed_scale"]) < 1.0, "Gentle: one slower minion")
		assert_false(bool(b.call("_begin_pounce", true)), "never the most demanding pounce with minions")
		assert_false(bool(b.call("_begin_pounce", false)), "no committed attack while minions live")
		assert_true(bool(b.get("_release_done")), "one release per attempt")
		assert_eq(int(b.release_node().call("spawn_minion", Vector3(100.0, -18.0, 0.0)) != null), 0, "the cap holds")
		for m in spawned:
			(m as Node).queue_free()
		await wait_frames(1)
		assert_eq(int(b.minions_alive()), 0)
		k.global_position = Vector3(80.0, -18.0, 2.0)
		assert_true(bool(b.call("_begin_pounce", true)), "pounces return once the brood is gone")


func test_no_pounce_off_the_deck_or_without_line_of_sight() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	_to_cling(b)
	k.global_position = Vector3(88.0, -26.0, 0.0)      # the pit under the bridge
	assert_false(bool(b.call("_begin_pounce", false)), "never through the deck")
	k.global_position = Vector3(70.0, -18.0, 0.0)      # the gate ledge
	assert_false(bool(b.call("_begin_pounce", false)), "only onto the bridge deck")
	k.global_position = Vector3(92.0, -18.0, 2.0)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(30.0, 0.5, 12.0)
	cs.shape = sh
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(88.0, -10.0, 0.0)   # a ceiling between her anchor and the deck
	_nodes.append(wall)
	await wait_physics(2)
	assert_false(bool(b.call("_begin_pounce", false)), "no pounce through a ceiling / wall")
	wall.queue_free()
	await wait_physics(2)
	assert_true(bool(b.call("_begin_pounce", false)), "clear line of sight: the pounce")
	var land: Vector3 = b.current_landing()
	for br in s[2]:
		assert_true(Rules.flat(land, (br as Node3D).global_position) >= Rules.BRAZIER_CLEAR - 0.01, "a valid landing")


func test_companions_only_in_exposed_phases() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	var brs: Array = s[2]
	var comp := _dummy(Vector3(88.0, -18.0, 0.0), ["companion"])
	_to_cling(b)
	assert_false(bool(b.can_be_hit_by(comp)), "not while she hangs overhead")
	assert_false(bool(b.can_be_hit_by(k)), "not even Krystal")
	var hp0: float = float(b.health.hp)
	b.health.apply_damage(30.0, comp, Vector3.ZERO)
	assert_almost(float(b.health.hp), hp0, 0.001, "armoured")
	(brs[int(b.held_line)] as Node).call("light")
	_to_state(b, "exposed", 2.0)
	assert_true(bool(b.can_be_hit_by(comp)), "companions attack the exposed phase")
	var e := _dummy(Vector3(88.0, -18.0, 0.0), ["enemy"])
	assert_false(bool(b.can_be_hit_by(e)), "enemies never hit her")


func test_reset_on_death_keeps_wounds_and_clears_everything() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	var brs: Array = s[2]
	_expose(b, brs)
	_to_state(b, "exposed", 2.0)
	b.health.apply_damage(40.0, k, Vector3.ZERO)
	var hp_after: float = float(b.health.hp)
	assert_true(_to_state(b, "cast", 30.0), "a new cast on the new side")
	_to_state(b, "recover", 3.0)
	assert_true(int(b.live_threads()) > 0)
	_to_state(b, "pounce_tele", 20.0)
	_events.clear()
	Events.player_died.emit()
	assert_eq(String(b.state), "dormant", "stands down")
	assert_false(bool(b.fight_started))
	assert_true(_events.has(["enc", ID, false]), "encounter event off")
	assert_true(_events.has(["hp", ID, -1.0, 320.0]), "bar hidden")
	await wait_frames(1)
	assert_eq(int(b.live_threads()), 0, "threads gone")
	assert_false(bool(b.pounce_mark().call("is_showing")), "the ring is gone")
	assert_eq(int(b.minions_alive()), 0)
	assert_false(bool(b.sacs_pending()))
	assert_almost(float(b.health.hp), hp_after, 0.001, "her wounds are kept (the kinder retry)")
	assert_eq(int(b.exposures), 1, "the exposure made is kept")
	assert_eq(int(b.side), 1, "on her current side - never a mismatched prop")
	assert_true(Rules.flat(b.global_position, Layout.CROSSING["anchors"][int(b.held_line)]) < 0.5, "back on a line anchor")
	assert_eq(int(b.anchor_marks().get("held")), int(b.held_line), "the held anchor's mark + tether follow her (no mismatched prop)")
	assert_true(bool((brs[2] as Node).call("is_lit")) and bool((brs[2] as Node).get("reusable")), "lit braziers stay lit and stokable")
	b.start_fight()
	assert_eq(String(b.state), "intro", "the retry starts cleanly")
	assert_true(_events.has(["enc", ID, true]))
	assert_true(_events.has(["phase", ID, 2]), "and in the phase she reached")
	# walking far away (no arena node) also stands her down
	k.global_position = Vector3(20.0, -18.0, 0.0)
	_tick(b, Rules.T_INTRO + 5.0)
	assert_eq(String(b.state), "dormant", "stands down when Krystal leaves")


func test_defeat_commits_once_before_any_presentation_and_chapter_one_is_untouched() -> void:
	for weaver_before in [false, true]:
		for n in _nodes:
			if is_instance_valid(n):
				n.queue_free()
		_nodes.clear()
		_events.clear()
		await wait_frames(1)
		fresh_state()
		GameState.set_flag("weaver_defeated", weaver_before)
		var s: Array = await _setup()
		var b: Node = s[0]
		var k: Dummy = s[1]
		var brs: Array = s[2]
		b.fast_defeat = weaver_before       # the first run plays the whole retreat
		var seen := []
		var cb := func(id: String) -> void:
			seen.append([id, String(b.state), b.visible, bool(b.is_gone()), GameState.has_reward("rw_ch2_crossing")])
		Events.boss_defeated.connect(cb)
		_expose(b, brs)
		_to_state(b, "exposed", 2.0)
		b.health.set_hp(10.0)
		b.health.apply_damage(50.0, k, Vector3.ZERO)
		Events.boss_defeated.disconnect(cb)
		assert_eq(seen.size(), 1, "boss_defeated exactly once")
		assert_eq(String(seen[0][0]), ID, "with the data id")
		assert_eq(String(seen[0][1]), "defeat", "committed at once...")
		assert_true(bool(seen[0][2]) and not bool(seen[0][3]), "...before the retreat is shown")
		assert_true(_events.has(["enc", ID, false]) and _events.has(["hp", ID, -1.0, 320.0]), "bar hidden, encounter over")
		assert_true(GameState.has_reward("rw_ch2_crossing") and bool(GameState.get_flag("ch2_crossing_cleared")), "no arena listener: the bundle is committed once")
		var t0: float = float(GameState.ledger["rw_ch2_crossing"])
		assert_eq(bool(GameState.get_flag("weaver_defeated")), weaver_before, "weaver_defeated untouched")
		assert_false(GameState.has_item("heartseed"), "never the Heartseed")
		# nothing re-commits: more damage, a flag echo, a death, a reset, another died signal
		b.health.apply_damage(50.0, k, Vector3.ZERO)
		b.health.died.emit()
		Events.player_died.emit()
		b.reset_fight()
		GameState.set_flag("ch2_crossing_cleared", true)
		assert_eq(_count("defeated"), 1, "still once")
		assert_eq(float(GameState.ledger["rw_ch2_crossing"]), t0, "reward once")
		assert_true(float(b.retreat_seconds()) > 1.0, "a retreat presentation follows")
		var gone_t := 0.0
		while not bool(b.is_gone()) and gone_t < 8.0:
			await wait_frames(1)
			gone_t += maxf(get_process_delta_time(), 0.001)
		assert_true(bool(b.is_gone()), "she retreats (defeat = retreat, no death)")
		assert_false(b.is_in_group("enemy"))


func test_arachnophobia_swap_mid_telegraph_keeps_the_fight() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	assert_true(_to_state(b, "pounce_tele"))
	_tick(b, 0.5)
	var st: float = float(b.state_time)
	assert_true(b.look.get("inner").get_script() == WeaverVisual, "the Matron")
	assert_eq(String(b.sound_name("rattle")), "weaver_rattle")
	Settings.set_value("arachnophobia", true)
	assert_eq(String(b.state), "pounce_tele", "state untouched")
	assert_almost(float(b.state_time), st, 0.0001, "timer untouched")
	assert_true(b.look.get("inner").get_script() == ShadeVisual, "the Hollow Mother")
	assert_true(bool(b.uses_shade()))
	assert_true(bool(b.pounce_mark().call("footprint")["alt"]), "the mark swaps to the pale look")
	assert_eq(int(b.anchor_marks().call("seal_count")), 5, "stone seals at every anchor")
	assert_eq(int(b.anchor_marks().call("silk_count")), 0, "no silk anywhere")
	assert_eq(ItemDB.enemy_display_name(ID), "The Hollow Mother", "the boss bar name")
	for kind in ["rattle", "skitter", "drop", "shriek", "threads", "final", "feint"]:
		assert_false(String(b.sound_name(kind)).begins_with("weaver") or String(b.sound_name(kind)).contains("web"), "no spider sound for %s" % kind)
	for kind in ["intro", "threads", "pounce", "delayed", "feint", "final", "exposed", "side", "release", "wrong", "defeat"]:
		var c := String(b.caption_text(kind)).to_lower()
		for bad in ["silk", "web", "thread", "sac", "spider", "matron", "leg"]:
			assert_false(c.contains(bad), "caption '%s' avoids '%s'" % [c, bad])
	# in the shade look she floats upright beneath the seal
	b.call("_enter_cling", 5.0)
	b.call("_on_settings_changed", "arachnophobia")
	var up: Vector3 = b.global_transform.basis.y
	assert_true(up.y > 0.9, "upright (never an inverted leggy close-up)")
	Settings.set_value("arachnophobia", false)
	assert_true(b.look.get("inner").get_script() == WeaverVisual, "and back")


func test_scorch_ends_it_even_without_weapon_damage() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	var brs: Array = s[2]
	var n := 0
	while not bool(b.is_defeated()) and n < 10:
		k.global_position = Vector3(88.0, -18.0, 0.0)
		_to_cling(b)
		var br: Node = brs[int(b.held_line)]
		if bool(br.call("is_lit")):
			br.call("flare")
		else:
			br.call("light")
		n += 1
		_until(b, func() -> bool: return String(b.state) == "climb" or bool(b.is_defeated()), 12.0)
	assert_true(bool(b.is_defeated()), "the flares alone end it")
	assert_true(n <= 6, "within six exposures (%d)" % n)
	assert_eq(_count("defeated"), 1, "once")


func test_good_damage_ends_it_in_two_or_three_exposures() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	var brs: Array = s[2]
	var n := 0
	while not bool(b.is_defeated()) and n < 6:
		_expose(b, brs)
		n += 1
		_to_state(b, "exposed", 2.0)
		# a copper sword (18) twice a second for the whole window
		var t := 0.0
		while String(b.state) == "exposed" and t < 10.0 and not bool(b.is_defeated()):
			b.health.apply_damage(18.0, k, Vector3.ZERO)
			_tick(b, 0.5)
			t += 0.5
	assert_true(bool(b.is_defeated()), "defeated")
	assert_true(n >= 2 and n <= 3, "two or three exposures plus damage (%d)" % n)


func test_the_pounce_goes_through_krystals_damage_intake_once() -> void:
	# armour first, then the shield, then health - one hit, i-frames stop a second
	GameState.give_item("padded_vest", 1)
	assert_true(GameState.equip("padded_vest"), "armour on")
	_deck()
	var brs := _braziers()
	var k := RealKrystal.new()
	add_child(k)
	k.global_position = Vector3(76.0, -18.0, 2.0)
	_nodes.append(k)
	var b := _boss(k, brs, 1)
	await wait_physics(2)
	b.start_fight()
	var red: float = preload("res://src/core/stats.gd").damage_reduction()
	assert_true(red > 0.0, "the vest reduces damage (%.3f)" % red)
	k.health.add_shield(5.0, 30.0, "test")
	assert_true(_to_state(b, "pounce_tele", 20.0))
	assert_true(_to_state(b, "rebound", 3.0), "it lands on her")
	assert_eq(k.damaged_count, 1, "one hit")
	var hit: Dictionary = k.health.last_hit
	assert_almost(float(hit["raw"]), 20.0, 0.001, "raw pounce damage")
	assert_almost(float(hit["mitigated"]), 20.0 * (1.0 - red), 0.01, "armour applied first")
	assert_almost(float(hit["absorbed"]), 5.0, 0.01, "then the shield")
	assert_almost(100.0 - float(k.health.hp), 20.0 * (1.0 - red) - 5.0, 0.01, "then health")
	_tick(b, 0.6)
	assert_eq(k.damaged_count, 1, "the landing is processed once (no second hit while she rebounds)")
	assert_eq(k.knocks.size(), 1)
	assert_eq((k.knocks[0][0] as Vector3).z, 0.0, "along the bridge")


func test_a_companions_real_melee_lands_only_in_an_exposed_window() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var brs: Array = s[2]
	var comp := _dummy(Vector3(88.0, -18.0, 0.0), ["companion"])
	var Combat := preload("res://src/combat/combat.gd")
	_to_cling(b)
	(brs[int(b.held_line)] as Node).call("light")
	assert_true(_to_state(b, "exposed", 2.0))
	comp.global_position = b.global_position + Vector3(1.4, 0.0, 0.0)
	var hp0: float = float(b.health.hp)
	var hits: Array = Combat.melee(comp, comp.global_position + Vector3.UP * 0.8, Vector3(-1, 0, 0), 2.0, 120.0, 10.0, ["enemy"], 0.0)
	assert_true(hits.has(b), "the companion's blow lands on the exposed Matron")
	assert_true(float(b.health.hp) < hp0)
	_until(b, func() -> bool: return String(b.state) == "climb", 10.0)
	b.global_transform = Transform3D(b.global_transform.basis, comp.global_position + Vector3(-1.4, 0.0, 0.0))
	var hp1: float = float(b.health.hp)
	var again: Array = Combat.melee(comp, comp.global_position + Vector3.UP * 0.8, Vector3(-1, 0, 0), 2.0, 120.0, 10.0, ["enemy"], 0.0)
	assert_false(again.has(b), "refused outside the window (can_be_hit_by)")
	assert_almost(float(b.health.hp), hp1, 0.001)


func test_comfort_settings_stretch_warnings_and_bold_the_mark() -> void:
	Settings.set_value("timing_assist", true)
	Settings.set_value("high_visibility_cues", true)
	var s: Array = await _setup()
	var b: Node = s[0]
	assert_true(_to_state(b, "cast"))
	assert_almost(float(b.get("_state_len")), float(Rules.T_THREAD_TELE[1]) * Rules.TIMING_ASSIST_MULT, 0.001, "thread marks stretched")
	assert_true(bool(b.call("cast_bold_visible")), "high-visibility: the thread marks get bold rails too")
	var sg: Array = (b.get("_cast_segs") as Array)[0]
	var bold := b.get_node("CastBold0") as Node3D
	var endp: Vector3 = bold.global_transform * Vector3(0.0, 0.0, -1.0)
	assert_true(Rules.flat(endp, sg[1]) < 0.05 and Rules.flat(bold.global_position, sg[0]) < 0.05, "the rails run along the marked landing")
	assert_true(_to_state(b, "pounce_tele", 20.0))
	assert_almost(float(b.get("_state_len")), float(Rules.T_POUNCE_TELE[1]) * Rules.TIMING_ASSIST_MULT, 0.001, "pounce warning stretched")
	assert_true(bool(b.pounce_mark().call("bold_visible")), "high-visibility: a bold outline ring (shape, not colour alone)")
	Settings.set_value("reduce_flashing", true)
	b.pounce_mark().call("_process", 0.1)
	assert_true(bool(b.pounce_mark().call("is_showing")), "reduce_flashing: the ring stays (steady, no strobe)")
	Settings.set_value("high_visibility_cues", false)
	assert_false(bool(b.pounce_mark().call("bold_visible")), "toggles live")
	_to_state(b, "stranded", 3.0)
	if String(b.state) == "stranded":
		assert_almost(float(b.get("_state_len")), float(Rules.T_STRANDED[1]) * Rules.TIMING_ASSIST_MULT, 0.001, "opening stretched")


func test_a_knockout_pounce_resets_cleanly_and_she_stays_down() -> void:
	# In the game Krystal's died signal reaches Game.on_player_died, which emits Events.player_died at once -
	# from INSIDE the pounce's apply_damage. The reset runs inside the landing; nothing of that landing may run
	# on after it (no knockback on a fallen Krystal, no rebound / climb / new attack behind a reset fight).
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	k.health.max_hp = 10.0
	k.health.hp = 10.0
	k.health.died.connect(func() -> void: Events.player_died.emit())
	assert_true(_to_state(b, "pounce_tele"))
	var casts := int(b.stats["casts"])
	var pounces := int(b.stats["pounces"]) + int(b.stats["delayed"])
	assert_true(_to_state(b, "dormant", 3.0), "the knockout resets her (not a rebound behind a reset fight)")
	assert_eq(k.hits, 1, "one hit")
	assert_true(bool(k.health.dead))
	assert_eq(k.knocks.size(), 0, "no knockback on a fallen Krystal")
	assert_false(bool(b.fight_started))
	assert_true(b.is_overhead(), "back up on her anchor")
	assert_false(bool(b.pounce_mark().call("is_showing")))
	# Krystal wakes at the checkpoint gate: the reset fight stays reset until she comes back onto the bridge
	k.health.reset()
	k.global_position = Vector3(64.2, -18.0, 0.9)
	_events.clear()
	_tick(b, 10.0)
	assert_eq(String(b.state), "dormant", "still dormant")
	assert_eq(int(b.stats["casts"]), casts, "no thread cast behind a reset fight")
	assert_eq(int(b.stats["pounces"]) + int(b.stats["delayed"]), pounces, "no pounce behind a reset fight")
	assert_eq(_count("enc"), 0, "no encounter events while she waits")


func test_the_fight_never_starts_while_krystal_is_down() -> void:
	_deck()
	var brs := _braziers()
	var k := _dummy(Vector3(76.0, -18.0, 2.0))
	var b := _boss(k, brs, 1)
	await wait_physics(2)
	k.health.hp = 0.0
	k.health.dead = true
	b.start_fight()
	assert_false(bool(b.fight_started), "no fight on the death screen")
	assert_eq(_count("enc"), 0, "no encounter event, bar or intro caption")
	assert_eq(String(b.state), "dormant")
	k.health.reset()
	_tick(b, 0.5)
	assert_true(bool(b.fight_started), "once she is up on the crossing again, it starts")
	assert_eq(_count("enc"), 1)


func test_a_strong_weapon_still_needs_two_exposures() -> void:
	GameState.give_item("lantern", 1)           # the brazier rule is playable (boss_brazier needs the Lantern)
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	var brs: Array = s[2]
	var hints: Array = []
	var hcb := func(id: String, _text: String) -> void: hints.append(id)
	Events.hint.connect(hcb)
	# No exposure yet: an enormous blow in a missed-pounce window stops at the 60% floor and ends the window
	_to_cling(b)
	b.call("_enter", "stranded", 2.5)
	b.health.apply_damage(1000.0, k, Vector3.ZERO)
	assert_false(bool(b.is_defeated()), "no win without the brazier rule")
	assert_almost(float(b.health.hp), 320.0 * 0.6, 0.01, "held at the 60% floor")
	assert_eq(String(b.state), "climb", "the window ends: she tears free and climbs")
	assert_true(bool(b.at_floor()))
	assert_true(hints.has("boss_crossing_floor"), "a hint points at the brazier")
	# at the floor a missed pounce leaves no false opening
	assert_true(_to_state(b, "pounce_tele", 20.0))
	k.global_position = Vector3(clampf(float(b.current_landing().x) + 4.5, 74.0, 103.0), -18.0, 0.0)
	if Rules.flat(k.global_position, b.current_landing()) < Rules.POUNCE_RADIUS + 1.0:
		k.global_position = Vector3(float(b.current_landing().x) - 4.5, -18.0, 0.0)
	_until(b, func() -> bool: return not (String(b.state) in ["pounce_tele", "drop"]), 4.0)
	assert_eq(k.hits, 0, "dodged")
	assert_eq(String(b.state), "rebound", "no stranded window while blows can't wound her")
	assert_false(b.is_vulnerable())
	# first exposure: the scorch still burns through; now the floor is 25%
	_expose(b, brs)
	assert_true(_to_state(b, "exposed", 2.0))
	assert_almost(float(b.health.hp), 320.0 * 0.6 - 32.0, 0.01, "the flare's scorch is never held by the floor")
	b.health.apply_damage(1000.0, k, Vector3.ZERO)
	assert_false(bool(b.is_defeated()), "one exposure is not enough")
	assert_almost(float(b.health.hp), 320.0 * 0.25, 0.01, "held at the 25% floor")
	# second exposure: nothing holds her up any more
	_expose(b, brs)
	assert_true(_to_state(b, "exposed", 2.0))
	b.health.apply_damage(1000.0, k, Vector3.ZERO)
	Events.hint.disconnect(hcb)
	assert_true(bool(b.is_defeated()), "the second exposure lets a strong weapon finish her")
	assert_eq(int(b.exposures), 2)
	assert_eq(_count("defeated"), 1)


func test_the_retreat_stays_inside_the_hall_and_under_its_ceiling() -> void:
	var room: Dictionary = Layout.ROOMS["hw_crossing"]
	var ceiling := float(room["y"]) + float(room["h"])
	var wall_z := float(room["z0"])
	var opening: Array = (room["open"] as Dictionary)["n"][0]
	var deck := float(Layout.CROSSING["deck_y"])
	for alt in [false, true]:
		for n in _nodes:
			if is_instance_valid(n):
				n.queue_free()
		_nodes.clear()
		await wait_frames(1)
		Settings.set_value("arachnophobia", alt)
		var s: Array = await _setup()
		var b: Node = s[0]
		_expose(b, s[2])
		assert_true(_to_state(b, "exposed", 2.0))
		var path: Array = b.retreat_path()
		assert_eq(path.size(), 4)
		var top := float(b.look.call("body_height")) if alt else 0.3
		for i in 3:
			var p: Vector3 = path[i]
			assert_true(p.y + top <= ceiling - 0.2, "%s: waypoint %d stays under the ceiling (top %.2f)" % ["alt" if alt else "silk", i, p.y + top])
			assert_true(p.z > wall_z + 0.1, "waypoint %d stays in the hall (z %.2f)" % [i, p.z])
		var mouth: Vector3 = path[2]
		var crack: Vector3 = path[3]
		assert_true(crack.z < wall_z, "the crack is behind the north wall")
		assert_almost(mouth.y, crack.y, 0.001, "the last leg runs level through the route's mouth...")
		# by the mouth she has withdrawn to RETREAT_SHRINK (silk top: a generous 1.5 x her body height)
		var small := float(b.look.call("body_height")) * (1.0 if alt else 1.5) * Boss.RETREAT_SHRINK
		assert_true(crack.y >= deck and crack.y + small <= deck + float(opening[2]), "...inside the opening's height (top %.2f)" % (crack.y + small))
		assert_true(crack.x >= float(opening[0]) and crack.x <= float(opening[1]), "...and its width")
		assert_true(float(b.retreat_seconds()) > 2.0 and float(b.retreat_seconds()) < 7.0, "a short readable retreat")
	Settings.set_value("arachnophobia", false)


func test_without_a_lantern_the_floor_never_softlocks_the_fight() -> void:
	# boss_brazier can't be lit without the Lantern: then blows alone must still be able to finish her
	if GameState.has_item("lantern"):
		GameState.take_item("lantern", GameState.count_item("lantern"))
	assert_false(GameState.has_item("lantern"))
	var s: Array = await _setup()
	var b: Node = s[0]
	var k: Dummy = s[1]
	assert_eq(float(b.hp_floor()), 0.0, "no floor when the brazier rule can't be played")
	_to_cling(b)
	b.call("_enter", "stranded", 2.5)
	b.health.apply_damage(1000.0, k, Vector3.ZERO)
	assert_true(bool(b.is_defeated()), "a missed-pounce window can finish her")
	assert_eq(_count("defeated"), 1)


func test_a_reset_mid_exposure_moves_her_anchor_marks_with_her() -> void:
	var s: Array = await _setup()
	var b: Node = s[0]
	var brs: Array = s[2]
	_to_cling(b)
	assert_eq(int(b.anchor_marks().get("held")), 2)
	(brs[2] as Node).call("light")
	assert_true(_to_state(b, "exposed", 2.0))
	Events.player_died.emit()                 # she falls mid-window: the reset puts the Matron on her new side
	assert_eq(int(b.side), 1)
	assert_eq(int(b.held_line), 1, "the south line after one exposure")
	assert_eq(int(b.anchor_marks().get("held")), 1, "the held mark + tether moved with her (never the old anchor)")
	assert_true(Rules.flat(b.global_position, Layout.CROSSING["anchors"][1]) < 0.5)
