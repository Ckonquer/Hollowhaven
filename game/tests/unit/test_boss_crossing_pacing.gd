extends "res://tests/test_case.gd"
## Weaver's Crossing rematch - PACING (QA CH2-007: the bot won the rematch in ~22 s by burning the held anchor at
## once, skipping the pounce, the delayed pounce and the release). A scripted Krystal plays the whole fight on a
## bare test deck (floor slab + three real line-braziers at the crossing's coordinates, ticked by hand with their
## real kindle / stoke / cooldown timings) with the Chapter One copper sword (18 per swing, one swing / 0.45 s,
## sprint 7 m/s or a 5 m/s jog, threads ignored), no companions:
##   "rusher"   - the QA bot's fast style: lights / stokes the brazier under the anchor she holds as soon as it
##                can (primes it before she commits), dodges every pounce, strikes every opening, stokes rather
##                than fights the brood when the light is ready.
##   "reactive" - a competent player who knows the rule: jogs, waits for her to commit before going for the
##                light, strikes openings, kills the brood first, and does not try to dodge her first plain and
##                first delayed pounce.
## Checks: every phase shows its new attack before the exposure that ends it (a pounce before exposure 1, a
## delayed pounce before exposure 2, the release before exposure 3), no exposure crosses more than one phase
## boundary (exactly three exposures), no softlock and no health sponge at every intensity, with timing assist.
## Measured engaged time (start_fight -> defeat; this suite prints "[pacing]" lines), 2026-09-28:
##   rusher    Gentle ~55 s, Standard ~43-44 s, Intense ~41 s, Standard + timing assist ~51 s
##   reactive  Gentle ~68 s, Standard ~57-58 s, Intense ~52 s
## Before the fix (QA CH2-007) the same rusher won in 14.4 s (reactive 16-17 s): two exposures, no pounce, no
## delayed pounce, no release. These are scripted floors: a first encounter adds reading the rule, walking round
## threads, the real brood chasing her, being hit and retries on top (the ~2-4 min target of MP 8 / 13).

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Rules := preload("res://src/enemies/crossing/crossing_rules.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Layout := preload("res://data/works_layout_deep.gd")

const ID := "crossing_matron"
const DT := 0.05
const SPRINT := 7.0          # player_logic.SPRINT_SPEED
const JOG := 5.0
const COPPER := 18.0         # items.gd copper_sword
const SWING := 0.45
const REACH := 2.2
const REACT := 0.35          # seconds after a ring appears before Krystal moves out of it
const MINION_HP := 28.0      # Brood Skitter 24-32 hp (MP 12)

var _nodes: Array = []
var _saved := {}
var _minions: Array = []
var _now: float = 0.0
var _snaps: Array = []
var _boss: Node = null


class Krystal extends CharacterBody3D:
	var health: Node
	var lantern_on := false
	var knocks: Array = []
	var hits: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100000.0
		add_child(health)
		collision_layer = 2
		collision_mask = 0
		add_to_group("player")
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: hits += 1)

	func knockback(dir: Vector3, force: float) -> void:
		knocks.append([dir, force])


func before_each() -> void:
	fresh_state()
	GameState.give_item("lantern", 1)          # the brazier rule is playable (and the HP floors apply)
	_nodes.clear()
	for k in ["arachnophobia", "timing_assist", "high_visibility_cues", "reduce_flashing"]:
		_saved[k] = Settings.get_value(k)
		Settings.set_value(k, false)


func after_each() -> void:
	_clear()
	for n in get_tree().get_nodes_in_group("hw_thread"):
		n.queue_free()
	for k in _saved:
		Settings.set_value(k, _saved[k])
	GameState.buffs.erase("slow")
	await wait_frames(2)


func _clear() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_minions.clear()
	_snaps.clear()
	_boss = null


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
		b.setup({"id": "tcp%d" % i})
		b.set_meta("anchor_index", i)
		add_child(b)
		b.global_position = Layout.CROSSING["braziers"][i]
		b.set_process(false)                   # ticked by the simulation
		out.append(b)
		_nodes.append(b)
	return out


func _make_minion(pos: Vector3, _params: Dictionary) -> Node:
	var m := Node3D.new()
	m.name = "SimBrood"
	m.set_meta("hp", MINION_HP)
	add_child(m)
	m.global_position = pos
	_nodes.append(m)
	_minions.append(m)
	return m


func _on_exposed(_line: int, count: int) -> void:
	var s: Dictionary = _boss.stats
	_snaps.append({"count": count, "t": _now, "pounces": int(s["pounces"]), "delayed": int(s["delayed"]),
		"releases": int(s["releases"]), "hp_before_scorch": float(_boss.health.hp)})


## One scripted fight. Returns {"won", "t", "exposures", "stats", "snaps", "hits"}.
func _play(style: String, level: int, max_s: float = 400.0) -> Dictionary:
	_clear()
	await wait_frames(1)
	fresh_state()                               # each fight on a fresh save (a win sets ch2_crossing_cleared)
	GameState.give_item("lantern", 1)
	_deck()
	var brs := _braziers()
	var k := Krystal.new()
	add_child(k)
	k.global_position = Vector3(74.0, -18.0, 2.0)
	_nodes.append(k)
	var b: Node = Factory.create(ID, {"arena_center": Layout.CROSSING["center"], "arena_radius": Layout.CROSSING["radius"],
		"anchors": Layout.CROSSING["anchors"], "braziers": brs, "crack": Layout.CROSSING["crack"],
		"bridge": Layout.CROSSING["bridge"], "deck_y": Layout.CROSSING["deck_y"]})
	assert_not_null(b, "factory knows crossing_matron")
	b.target_override = k
	b.intensity_override = level
	b.fast_defeat = true
	add_child(b)
	b.set_process(false)
	_nodes.append(b)
	_boss = b
	b.release_node().set("minion_override", _make_minion)
	b.exposed.connect(_on_exposed)
	await wait_physics(2)
	b.start_fight()
	var speed := SPRINT if style == "rusher" else JOG
	var swing := 0.0
	_now = 0.0
	while _now < max_s and not bool(b.is_defeated()):
		swing = maxf(swing - DT, 0.0)
		if _krystal_step(style, b, k, brs, speed, swing <= 0.0):
			swing = SWING
		for br in brs:
			(br as Node).call("_process", DT)
		b.tick(DT)
		_now += DT
	var out := {"won": bool(b.is_defeated()), "t": _now, "exposures": int(b.exposures), "stats": (b.stats as Dictionary).duplicate(),
		"snaps": _snaps.duplicate(true), "hits": k.hits}
	print("[pacing] %s level %d: %s in %.1f s, exposures %d, pounces %d, delayed %d, releases %d, primed %d, hits on Krystal %d" % [
		style, level, "won" if out["won"] else "NOT won", _now, int(b.exposures), int(b.stats["pounces"]), int(b.stats["delayed"]),
		int(b.stats["releases"]), int(b.stats.get("primed", 0)), k.hits])
	return out


## Krystal's decision for one tick: dodge > keep kindling > strike an opening > the light > the brood > wait.
## True when she swung.
func _krystal_step(style: String, b: Node, k: Krystal, brs: Array, speed: float, can_swing: bool) -> bool:
	var kp := k.global_position
	var st := String(b.state)
	var held := clampi(int(b.held_line), 0, brs.size() - 1)
	var hb: Node3D = brs[held]
	var stand := Vector3(hb.global_position.x, kp.y, hb.global_position.z - signf(hb.global_position.z) * 1.0)
	var alive: Array = []
	for m in _minions:
		if is_instance_valid(m) and not (m as Node).is_queued_for_deletion():
			alive.append(m)
	var goal := kp
	var decided := false
	var swung := false
	# 1. out of a pounce ring, and stay out until she has landed (the reactive player misses her first plain and
	#    her first delayed pounce)
	var ring_on := (st == "pounce_tele" and float(b.state_time) >= REACT) or st == "drop"
	var land: Vector3 = b.current_landing()
	var keep_out := Rules.POUNCE_RADIUS + Rules.HIT_BODY + 0.6
	var dodging := false
	var escaping := false
	if ring_on:
		var delayed := bool(b.get("_pounce_delayed"))
		var n := int(b.stats["delayed"]) if delayed else int(b.stats["pounces"])
		dodging = style == "rusher" or n >= 2
		if dodging and Rules.flat(kp, land) < keep_out:
			var dx := signf(kp.x - land.x)
			if dx == 0.0:
				dx = 1.0
			if land.x + dx * 4.0 > 103.0 or land.x + dx * 4.0 < 73.0:
				dx = -dx
			goal = Vector3(land.x + dx * (keep_out + 0.6), kp.y, kp.z)
			decided = true
			escaping = true
	# 2. finish a kindle already started
	if not decided and bool(hb.call("is_kindling")):
		goal = stand
		decided = true
	# 3. strike an opening
	if not decided and bool(b.is_vulnerable()):
		var bp: Vector3 = b.global_position
		goal = bp
		if Rules.flat(kp, bp) <= REACH:
			goal = kp
			if can_swing:
				b.health.apply_damage(COPPER, k, (bp - kp).normalized())
				swung = true
		decided = true
	# 4. the light under HER anchor (the rusher primes it before she commits; the reactive player waits for her
	#    to commit first) - or 5. the brood
	var want_light := false
	if not decided:
		var ready := bool((hb.call("get_interaction", k) as Dictionary).get("enabled", false))
		var engaged := bool(b.call("is_engaged")) if b.has_method("is_engaged") else true
		var primed := bool(b.call("is_primed")) if b.has_method("is_primed") else false
		if style == "rusher":
			want_light = ready and (engaged or not primed)
		else:
			want_light = ready and engaged and alive.is_empty()
	if not decided and want_light:
		goal = stand
		if Rules.flat(kp, stand) <= 1.0:
			hb.call("interact", k)
			goal = kp
		decided = true
	if not decided and not alive.is_empty():
		var m: Node3D = alive[0]
		goal = m.global_position
		if Rules.flat(kp, goal) <= REACH:
			goal = kp
			if can_swing:
				m.set_meta("hp", float(m.get_meta("hp")) - COPPER)
				swung = true
				if float(m.get_meta("hp")) <= 0.0:
					m.queue_free()
		decided = true
	if not decided and style == "rusher":
		goal = stand                            # waits by the light, ready to stoke it again
	if dodging and not escaping and Rules.flat(goal, land) < keep_out:
		goal = kp                               # never walks back into a ring that is still coming down
	# move (along the deck, inside the rails; threads are ignored: cut / burned / walked round in play)
	var d := Vector3(goal.x - kp.x, 0.0, goal.z - kp.z)
	var step := speed * DT
	if d.length() > step:
		d = d.normalized() * step
	var np := kp + d
	k.global_position = Vector3(clampf(np.x, 72.6, 103.4), -18.0, clampf(np.z, -4.3, 4.3))
	return swung


# --- Tests -------------------------------------------------------------------------------------------------

## QA CH2-007 regression: the bot's fast style - burn the held anchor as soon as it can - still meets her whole kit,
## one phase per exposure, and the fight is no longer over in ~20 s.
func test_a_rusher_who_burns_her_anchor_at_once_still_meets_her_whole_kit() -> void:
	var r: Dictionary = await _play("rusher", 1)
	assert_true(bool(r["won"]), "the rusher wins (%.1f s)" % float(r["t"]))
	assert_eq(int(r["exposures"]), 3, "one exposure per phase: no exposure crosses two phase boundaries")
	var snaps: Array = r["snaps"]
	assert_eq(snaps.size(), 3)
	if snaps.size() == 3:
		assert_true(int(snaps[0]["pounces"]) + int(snaps[0]["delayed"]) >= 1, "phase 1: she pounced before the light could burn her")
		assert_true(int(snaps[1]["delayed"]) >= 1, "phase 2: the delayed pounce (final tell) came before exposure 2")
		assert_true(int(snaps[2]["releases"]) >= 1, "phase 3: the release came before exposure 3")
	assert_true(float(r["t"]) >= 38.0, "a real encounter, not a 20 s skip (%.1f s)" % float(r["t"]))


## No softlock and no health sponge at any intensity, for either style; timing assist only stretches it.
func test_every_intensity_and_style_ends_in_three_exposures_within_a_few_minutes() -> void:
	for style in ["rusher", "reactive"]:
		for level in 3:
			var r: Dictionary = await _play(style, level)
			var tag := "%s level %d" % [style, level]
			assert_true(bool(r["won"]), "%s: won (%.1f s)" % [tag, float(r["t"])])
			assert_eq(int(r["exposures"]), 3, "%s: three exposures" % tag)
			assert_true(float(r["t"]) <= 240.0, "%s: never a health sponge (%.1f s)" % [tag, float(r["t"])])
			assert_true(int((r["stats"] as Dictionary)["releases"]) == 1, "%s: the release once" % tag)
			assert_true(int((r["stats"] as Dictionary)["delayed"]) >= 1, "%s: the delayed pounce" % tag)
	Settings.set_value("timing_assist", true)
	var a: Dictionary = await _play("rusher", 1)
	Settings.set_value("timing_assist", false)
	assert_true(bool(a["won"]) and int(a["exposures"]) == 3, "timing assist: the same fight, only slower (%.1f s)" % float(a["t"]))
