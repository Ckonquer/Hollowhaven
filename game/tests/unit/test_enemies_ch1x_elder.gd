extends "res://tests/test_case.gd"
## Knotted Elder (elite): root_sweep (1.3 s, wide 150 degree amber wedge) -> sweep -> recover 1.8 s; charge
## (1.5 s, glowing crown, red lane) -> one hit -> recover 2.2 s; roots (1.6 s, green spots) -> at most 4 roots
## in a broken ring (the side facing the Elder and one side open, walkable gaps, never on Krystal or a
## companion), expiring after 6 s, cuttable; a charge into a root bonks and breaks it; poise stagger only;
## health bar while engaged; the content reward rw_c1x_elder is granted exactly once; roots are cleaned up.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Elder := preload("res://src/enemies/knotted_elder.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null
var _saved_companions: Dictionary = {}


class Dummy extends CharacterBody3D:
	var health: Node
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	_saved_area = Game.area
	Game.area = null
	_saved_companions = Game.companion_nodes
	Game.companion_nodes = {}


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for c in get_children():
		if c.is_in_group("elder_root"):
			c.queue_free()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("timing_assist", false)
	Game.area = _saved_area
	Game.companion_nodes = _saved_companions
	await wait_frames(2)


func _dummy(pos: Vector3, group: String = "player") -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group(group)
	_nodes.append(d)
	return d


func _floor() -> void:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	w.add_child(cs)
	add_child(w)
	w.global_position = Vector3(0, -0.5, 0)
	_nodes.append(w)


func _elder(target: Node3D, pos: Vector3 = Vector3.ZERO, params: Dictionary = {}) -> Node:
	var p := params.duplicate()
	p["home"] = pos
	p["no_drops"] = true
	if not p.has("reward_id"):
		p["reward_id"] = ""
	var e: Node = Factory.create("knotted_elder", p)
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _step(e: Node, move: bool) -> void:
	e.tick(DT)
	if move:
		e._apply_movement(DT)


func _until(e: Node, s: String, max_t: float = 10.0, move: bool = false) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		_step(e, move)
		t += DT
	return t


func _raise_roots(e: Node) -> void:
	e.next_attack = "roots"
	_until(e, "rooting", 6.0)


func test_root_sweep_sequence_and_wide_arc() -> void:
	var d := _dummy(Vector3(0, 0, -2.4))
	var e := _elder(d)
	assert_eq(e.state, "idle", "starts idle")
	e.next_attack = "root_sweep"
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "telegraph", 4.0)
	var m: Node3D = e.mark()
	assert_eq(m.footprint()["kind"], "arc")
	assert_almost(float(m.footprint()["arc_deg"]), 150.0, 0.001, "data arc_deg 150")
	assert_almost(float(m.footprint()["radius"]), float(e.sweep_reach()), 0.001, "marked radius = sweep reach")
	assert_eq(m.get("color"), TelegraphFx.WARN)
	while e.state_time < 0.9:
		e.tick(DT)
	d.global_position = Vector3(2.08, 0, -1.2)           # 60 degrees off: still inside a 150 degree sweep
	var tele := 0.9 + _until(e, "sweep", 2.0)
	assert_almost(tele, 1.3, DT * 2.0, "data telegraph 1.3 s")
	_until(e, "recover", 1.0)
	assert_almost(float(d.health.hp), 84.0, 0.001, "sweep data damage (16) once")
	assert_eq(d.damaged_count, 1)
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, 1.8, DT * 2.0, "recover data 1.8 s")
	assert_eq(seen.slice(0, 5), ["chase", "telegraph", "sweep", "recover", "chase"], "sequence (%s)" % str(seen))


## R86: elites count as boss mechanics for Settings timing_assist: every wind-up (and recovery) x1.5.
func test_timing_assist_stretches_its_telegraphs_like_a_boss() -> void:
	var d := _dummy(Vector3(0, 0, -2.4))
	Settings.set_value("timing_assist", true)
	var e := _elder(d)
	assert_almost(float(Elder.TIMING_ASSIST_MULT), 1.5, 0.001, "same stretch as the Matron / Warden")
	e.next_attack = "root_sweep"
	_until(e, "telegraph", 4.0)
	var m: Node3D = e.mark()
	assert_eq(m.footprint()["kind"], "arc", "the same readable mark")
	var tele := _until(e, "sweep", 4.0)
	assert_almost(tele, 1.3 * 1.5, DT * 2.0, "assisted sweep wind-up 1.95 s")
	_until(e, "recover", 1.0)
	var rec := _until(e, "chase", 5.0)
	assert_almost(rec, 1.8 * 1.5, DT * 2.0, "assisted punish opening 2.7 s")
	for atk in ["charge", "roots"]:
		e.set("_def", e.attack_def(atk))
		assert_almost(float(e.telegraph_duration()), float(e.attack_def(atk)["telegraph"]) * 1.5, 0.001, "%s wind-up x1.5" % atk)
	Settings.set_value("timing_assist", false)
	for atk in ["root_sweep", "charge", "roots"]:
		e.set("_def", e.attack_def(atk))
		assert_almost(float(e.telegraph_duration()), float(e.attack_def(atk)["telegraph"]), 0.001, "assist off: data %s wind-up" % atk)
		assert_almost(float(e.recover_duration()), float(e.attack_def(atk)["recover"]), 0.001, "assist off: data %s recovery" % atk)


func test_charge_sequence_and_hit() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -6))
	var e := _elder(d)
	await wait_physics(2)
	e.next_attack = "charge"
	_until(e, "telegraph", 4.0, true)
	var m: Node3D = e.mark()
	assert_eq(m.footprint()["kind"], "lane")
	assert_almost(float(m.footprint()["width"]), Elder.LANE_WIDTH, 0.001)
	assert_eq(m.get("color"), TelegraphFx.DANGER)
	var tele := _until(e, "charge", 3.0, true)
	assert_almost(tele, 1.5, DT * 2.0, "data telegraph 1.5 s")
	_until(e, "recover", 3.0, true)
	assert_almost(float(d.health.hp), 82.0, 0.001, "charge data damage (18) once")
	assert_eq(d.damaged_count, 1)
	var rec := _until(e, "chase", 4.0, true)
	assert_almost(rec, 2.2, DT * 2.0, "recover data 2.2 s")


func test_three_tells_are_distinct() -> void:
	var d := _dummy(Vector3(0, 0, -2.4))
	var poses := {}
	var marks := {}
	var x := 0.0
	for kind in ["root_sweep", "charge", "roots"]:
		Base.reset_attack_tokens()
		d.global_position = Vector3(x, 0, -2.4)
		var e := _elder(d, Vector3(x, 0, 0))
		x += 30.0
		e.next_attack = kind
		_until(e, "telegraph", 4.0)
		for i in 40:
			e.visual._process(DT)
		poses[kind] = e.visual.pose()
		poses[kind]["crown"] = bool(e.visual.crown_glowing())
		marks[kind] = [e.mark().footprint()["kind"], e.mark().get("color")]
	assert_eq(marks["root_sweep"][0], "arc")
	assert_eq(marks["charge"][0], "lane")
	assert_eq(marks["roots"][0], "spots")
	assert_ne(marks["root_sweep"][1], marks["charge"][1], "sweep and charge marks differ in colour")
	assert_ne(marks["roots"][1], marks["charge"][1])
	assert_true(bool(poses["charge"]["crown"]), "the crown glows only for the charge")
	assert_false(bool(poses["root_sweep"]["crown"]))
	assert_false(bool(poses["roots"]["crown"]))
	assert_true(float(poses["root_sweep"]["twist"]) > 0.4 and float(poses["root_sweep"]["arm_out"]) > 1.0, "sweep: winds up with an arm out to the side (%s)" % str(poses["root_sweep"]))
	assert_true(float(poses["charge"]["lean"]) > 0.3 and float(poses["charge"]["arm_r"]) < -0.3, "charge: leans in, arms back (%s)" % str(poses["charge"]))
	assert_true(float(poses["roots"]["arm_l"]) > 0.8 and float(poses["roots"]["lean"]) > 0.5, "roots: bows and plunges its arms down (%s)" % str(poses["roots"]))
	assert_true(absf(float(poses["charge"]["twist"])) < 0.1 and absf(float(poses["roots"]["twist"])) < 0.1, "only the sweep twists")


func test_roots_are_bounded_gapped_timed_and_cuttable() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _elder(d)
	e.next_attack = "roots"
	_until(e, "telegraph", 4.0)
	var f: Dictionary = e.mark().footprint()
	assert_eq(f["kind"], "spots", "spots mark where roots will rise")
	var planned := (f["points"] as Array).size()
	assert_eq(e.mark().get("color"), TelegraphFx.ROOT)
	var tele := _until(e, "rooting", 3.0)
	assert_almost(tele, 1.6, DT * 2.0, "data telegraph 1.6 s")
	var roots: Array = e.roots.duplicate()
	assert_true(roots.size() >= 3 and roots.size() <= 4, "a broken ring of at most 4 roots (%d)" % roots.size())
	assert_eq(roots.size(), planned, "every marked spot rises (none blocked here)")
	assert_true(roots.size() <= Elder.MAX_ROOTS)
	var to_elder := Vector2(0, 5).normalized()
	var slots := {}
	for r in roots:
		var p: Vector3 = (r as Node3D).global_position
		var rel := Vector2(p.x - d.global_position.x, p.z - d.global_position.z)
		assert_true(rel.length() >= Elder.ROOT_MIN_CLEARANCE, "never on Krystal")
		var ang := rad_to_deg(absf(to_elder.angle_to(rel.normalized())))
		assert_true(ang > 50.0, "the side facing the Elder stays open (%.0f deg)" % ang)
		slots[int(round(fposmod(rad_to_deg(to_elder.angle_to(rel.normalized())), 360.0) / 60.0)) % 6] = true
	assert_true(6 - slots.size() >= 2, "at least two of six directions fully open (%s)" % str(slots.keys()))
	for i in roots.size():
		for j in range(i + 1, roots.size()):
			var gap := (roots[i] as Node3D).global_position.distance_to((roots[j] as Node3D).global_position) - Elder.ROOT_LENGTH
			assert_true(gap >= 1.2, "walkable gap between roots (%.2f m)" % gap)
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, Elder.ROOTING_TIME + 1.0, DT * 2.0, "rooting then data recover 1.0 s")
	# Cutting
	var r0: Node = roots[0]
	assert_eq(String(r0.get_interaction(d)["text"]), "Cut the root", "prompt")
	assert_eq(String(r0.get_harvest_info()["tool"]), "hand", "no tool needed (no softlock)")
	r0.harvest_hit(d, "")
	assert_true(bool(r0.is_cut))
	assert_false(bool(r0.is_active()))
	assert_true((r0.get_interaction(d) as Dictionary).is_empty(), "no prompt once cut")
	(roots[1] as Node).interact(d)
	assert_true(bool((roots[1] as Node).is_cut), "E cuts too")
	assert_eq(int(e.live_roots()), roots.size() - 2)
	# Expiry
	for r in roots:
		if is_instance_valid(r):
			(r as Node).advance(6.5)
			(r as Node).advance(0.5)
	assert_eq(int(e.live_roots()), 0, "every root expires after data duration (6 s)")
	await wait_frames(2)
	for r in roots:
		assert_false(is_instance_valid(r), "and is freed")


func test_roots_never_rise_on_krystal_or_a_companion() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _elder(d)
	e.next_attack = "roots"
	_until(e, "telegraph", 4.0)
	var planned: Array = e.planned_roots.duplicate()
	assert_true(planned.size() >= 3)
	var pebble := _dummy((planned[0] as Dictionary)["pos"], "companion")
	Game.companion_nodes = {"pebble": pebble}
	d.global_position = (planned[1] as Dictionary)["pos"]      # Krystal walks onto a marked spot
	_until(e, "rooting", 3.0)
	assert_eq((e.roots as Array).size(), planned.size() - 2, "the two occupied spots stay empty")
	for r in e.roots:
		var p: Vector3 = (r as Node3D).global_position
		assert_true(p.distance_to(pebble.global_position) >= Elder.ROOT_MIN_CLEARANCE, "not on the companion")
		assert_true(p.distance_to(d.global_position) >= Elder.ROOT_MIN_CLEARANCE, "not on Krystal")


## The clearance is measured to the root's whole length, not its centre: Krystal standing just beyond the end
## of a marked root (centre > ROOT_MIN_CLEARANCE away, but the root would rise into her body) keeps it down.
func test_roots_clear_krystals_body_along_their_length() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _elder(d)
	e.next_attack = "roots"
	_until(e, "telegraph", 4.0)
	var planned: Array = e.planned_roots.duplicate()
	assert_true(planned.size() >= 3)
	var r1: Dictionary = planned[1]
	var ends: Array = Elder.root_ends(r1["pos"], float(r1["yaw"]), Elder.ROOT_LENGTH)
	var ax: Vector3 = ((ends[1] as Vector3) - (ends[0] as Vector3)).normalized()
	d.global_position = (r1["pos"] as Vector3) + ax * (Elder.ROOT_LENGTH * 0.5 + 0.35)
	assert_true(d.global_position.distance_to(r1["pos"]) >= Elder.ROOT_MIN_CLEARANCE, "her centre is clear of the root's centre")
	_until(e, "rooting", 3.0)
	assert_eq((e.roots as Array).size(), planned.size() - 1, "the root that would rise into her stays down")
	for r in e.roots:
		var re: Array = Elder.root_ends((r as Node3D).global_position, (r as Node3D).rotation.y, Elder.ROOT_LENGTH)
		assert_true(TelegraphFx.segment_distance(re[0], re[1], d.global_position) >= Elder.ROOT_MIN_CLEARANCE,
			"no root within %.1f m of her along its length" % Elder.ROOT_MIN_CLEARANCE)
		assert_true(TelegraphFx.segment_distance(re[0], re[1], (e as Node3D).global_position) >= 1.0, "nor on the Elder")


func test_only_content_reward_bundles_are_granted() -> void:
	var log_id := ""
	var rewards: Dictionary = load("res://data/sources.gd").REWARDS
	for id in rewards:
		if String((rewards[id] as Dictionary).get("by", "")) in ["chapter_log", "optional_log"]:
			log_id = String(id)
			break
	assert_ne(log_id, "", "a quest-layer reward exists to try")
	var d := _dummy(Vector3(0, 0, -6))
	var e := _elder(d, Vector3.ZERO, {"reward_id": log_id})
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_false(GameState.has_reward(log_id), "a step / goal reward (%s) is never paid by the Elder" % log_id)


func test_charge_into_a_root_bonks_and_breaks_it() -> void:
	_floor()
	var d := _dummy(Vector3(0, 0, -7))
	var e := _elder(d)
	var root: Node3D = Elder.ElderRoot.new()
	add_child(root)
	root.global_position = Vector3(0, 0, -3.5)
	(e.roots as Array).append(root)
	await wait_physics(3)
	e.next_attack = "charge"
	_until(e, "charge", 5.0, true)
	assert_true(float(e.lane_length()) < 3.5, "the lane stops at the root (%.2f)" % float(e.lane_length()))
	_until(e, "stunned", 2.0, true)
	assert_eq(e.state, "stunned", "bonks into its own root")
	assert_true(bool(root.is_cut), "and breaks it")
	assert_almost(float(d.health.hp), 100.0, 0.001, "Krystal behind the root is safe")
	var stun := _until(e, "chase", 6.0, true)
	assert_almost(stun, 2.2 + Elder.BONK_EXTRA, DT * 2.0, "a long opening")


func test_poise_is_the_only_stagger() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var e := _elder(d)
	_until(e, "chase", 3.0)
	for i in 3:
		e.health.apply_damage(10.0, d, Vector3.FORWARD)
		assert_eq(e.state, "chase", "ordinary hits never flinch an elite")
	e.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_eq(e.state, "stunned", "40 damage within the window breaks its poise")
	var stun := _until(e, "chase", 3.0)
	assert_almost(stun, Elder.POISE_STUN, DT * 2.0)
	for i in 5:
		e.health.apply_damage(10.0, d, Vector3.FORWARD)
	assert_ne(e.state, "stunned", "poise immunity afterwards")
	# The window drains
	e.set("_poise_immune", 0.0)
	e.set("_poise_dmg", 0.0)
	e.health.apply_damage(30.0, d, Vector3.FORWARD)
	for i in int((Elder.POISE_WINDOW + 0.2) / DT):
		e.tick(DT)
	assert_almost(float(e.poise_damage()), 0.0, 0.001, "damage older than the window is forgotten")


func test_health_bar_and_reward_granted_once() -> void:
	var events: Array = []
	var cb := func(id: String, hp: float, _m: float) -> void:
		if id == Elder.BAR_ID:
			events.append(hp)
	Events.boss_health_changed.connect(cb)
	var d := _dummy(Vector3(0, 0, -6))
	var e := _elder(d, Vector3.ZERO, {"reward_id": "rw_c1x_elder"})
	_until(e, "chase", 3.0)
	assert_true(bool(e.bar_shown), "health bar while engaged")
	assert_almost(float(events[0]), 240.0, 0.001, "data hp 240")
	e.health.apply_damage(20.0, d, Vector3.FORWARD)
	assert_almost(float(events[-1]), 220.0, 0.001, "bar follows its health")
	var resin_before := GameState.count_item("resin")
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_true(float(events[-1]) < 0.0, "bar hidden on defeat")
	assert_true(GameState.has_reward("rw_c1x_elder"), "content reward in the ledger")
	assert_true(bool(GameState.get_flag("c1x_elder_defeated")), "unlock flag from the reward bundle")
	var bundle: Dictionary = ItemDB.reward_bundle("rw_c1x_elder")
	assert_eq(GameState.count_item("resin") - resin_before, int(bundle["items"]["resin"]), "resin from the bundle")
	var e2 := _elder(d, Vector3(10, 0, 0), {"reward_id": "rw_c1x_elder"})
	var resin_mid := GameState.count_item("resin")
	e2.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_eq(GameState.count_item("resin"), resin_mid, "never granted twice")
	Events.boss_health_changed.disconnect(cb)


func test_roots_cleaned_up_on_defeat_and_player_death() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _elder(d)
	_raise_roots(e)
	var roots: Array = e.roots.duplicate()
	assert_true(roots.size() > 0)
	Events.player_died.emit()
	await wait_frames(2)
	for r in roots:
		assert_false(is_instance_valid(r), "roots vanish when Krystal falls")
	Base.reset_attack_tokens()
	var e2 := _elder(d, Vector3(20, 0, 0))
	d.global_position = Vector3(20, 0, -5)
	_raise_roots(e2)
	roots = e2.roots.duplicate()
	assert_true(roots.size() > 0)
	e2.health.apply_damage(999.0, d, Vector3.FORWARD)
	await wait_frames(2)
	for r in roots:
		assert_false(is_instance_valid(r), "roots vanish when the Elder is defeated")


func test_attack_variety() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	var e := _elder(d)
	e.tick(DT)
	var last: Array = []
	for i in 80:
		e.set("_roots_cd", 0.0)
		e._choose_attack()
		last.append(String(e.attack_kind))
	for i in range(2, last.size()):
		assert_false(last[i] == last[i - 1] and last[i] == last[i - 2], "never the same attack three times running (%s)" % str(last.slice(i - 2, i + 1)))
	assert_true(last.has("charge") and last.has("roots"), "mid range mixes charges and roots")
