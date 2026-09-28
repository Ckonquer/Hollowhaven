extends "res://tests/test_case.gd"
## Chapter One additions - shared enemy mechanics (module B8): factory registration + safe loading, legacy
## defaults unchanged, hit / stagger / faction rules, bounded non-chaining slows, the shared ground telegraph,
## the local enemy projectile (one hit through the health path, walls block it, dodge passes, global cap),
## the committed-attack telegraph floor, horror-intensity scaling, existing sound names only, and a perf guard.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Health := preload("res://src/combat/health.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Projectile := preload("res://src/enemies/enemy_projectile.gd")
const Skitter := preload("res://src/enemies/brood_skitter.gd")

const DT := 0.05
const NEW_IDS := ["brambleback", "lantern_moth", "hollow_drudge", "brood_skitter", "knotted_elder"]
## Every sound name the new enemies play (they must all exist today; no new audio files were added).
const USED_SOUNDS := ["dig", "brambling_telegraph", "brambling_chatter", "tree_fall", "enemy_hurt", "hit_soft",
	"lantern_on", "shade_drift", "lantern_off", "shade_whisper", "gloomling_alert", "dir_creak", "mine_hit",
	"dir_scratch", "rock_break", "weaver_skitter", "weaver_rattle", "weaver_drop", "enemy_defeat",
	"dir_root_creak", "shade_telegraph", "grass_pull", "harvest_crop", "chop"]

var _nodes: Array = []
var _saved_area: Node = null


class Dummy extends CharacterBody3D:
	var health: Node
	var knocks: int = 0
	var damaged_count: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		knocks += 1


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("reduce_flashing", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("reduce_flashing", false)
	GameState.buffs.erase("slow")
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3, group: String = "player") -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	if group != "":
		d.add_to_group(group)
	_nodes.append(d)
	return d


func _enemy(id: String, target: Node3D, pos: Vector3 = Vector3.ZERO, params: Dictionary = {}) -> Node:
	var p := params.duplicate()
	p["home"] = pos
	p["no_drops"] = true
	var e: Node = Factory.create(id, p)
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	add_child(w)
	w.global_position = pos
	_nodes.append(w)
	return w


# --- Factory -----------------------------------------------------------------------------------------------

func test_factory_registers_new_ids_and_loads_safely() -> void:
	for id in NEW_IDS:
		assert_true(Factory.has_enemy(id), "%s registered" % id)
		assert_true(Factory.can_spawn(id), "%s script exists and compiles" % id)
		assert_true(Factory.script_path(id).begins_with("res://src/enemies/"), "%s path" % id)
		var e: Node = Factory.spawn(id, self, Transform3D(Basis.IDENTITY, Vector3(40, 0, 40)), {"no_drops": true})
		_nodes.append(e)
		assert_not_null(e, "%s spawned" % id)
		if e == null:
			continue
		e.set_physics_process(false)
		assert_true(e.is_in_group("enemy"), "%s in group enemy" % id)
		assert_eq((e as CharacterBody3D).collision_layer, 8, "%s on the enemy layer" % id)
		assert_eq((e as CharacterBody3D).collision_mask, 1 | 32, "%s collides with world|structure" % id)
		assert_almost(float(e.health.max_hp), float(ItemDB.enemy(id)["hp"]), 0.001, "%s hp from data" % id)
		assert_not_null(e.visual, "%s has a procedural visual" % id)
	assert_false(Factory.can_spawn("dragon"), "unknown id")
	assert_eq(Factory.script_path("dragon"), "", "no path for unknown ids")
	# A data id whose script is not registered yet (later waves add them) is refused without a crash.
	for eid in (load("res://data/enemies.gd").ENEMIES as Dictionary).keys():
		if not Factory.has_enemy(String(eid)):
			assert_null(Factory.create(String(eid)), "unregistered data id '%s' is refused (no crash)" % eid)
			break


func test_legacy_enemies_keep_their_defaults() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	for id in ["brambling", "gloomling"]:
		var e := _enemy(id, d, Vector3(3.0 if id == "gloomling" else 0.0, 0, 0))
		assert_eq((e.committed_states as Array).size(), 0, "%s has no committed custom states" % id)
		assert_false(bool(e.needs_clear_shot), "%s: no extra shot ray" % id)
		assert_almost(float(e.attack_reach()), float(ItemDB.enemy(id)["attack_range"]), 0.001, "%s reach = data attack_range" % id)
		assert_eq(e.health.get_script(), Health, "%s uses the plain health component" % id)
		assert_eq(String(e._defeat_sound()), "enemy_defeat", "%s defeat sound" % id)
		assert_eq(String(e.defeat_flag), "", "%s sets no flag on defeat" % id)
		for s in ["attack", "recover", "stunned"]:
			e.state = s
			assert_true(bool(e._is_uninterruptible()), "%s: %s is uninterruptible (legacy)" % [id, s])
		for s in ["idle", "chase", "telegraph", "flinch", "wander"]:
			e.state = s
			assert_false(bool(e._is_uninterruptible()), "%s: %s can be interrupted (legacy)" % [id, s])
		e.state = "idle"
		assert_true(bool(e.can_stagger(5.0, d)), "%s: first hit may flinch" % id)
		e.set("_flinch_immune", 1.0)
		assert_false(bool(e.can_stagger(5.0, d)), "%s: flinch immunity still applies" % id)


func test_can_be_hit_by_and_faction_filter() -> void:
	var d := _dummy(Vector3(0, 0, -8))
	var e := _enemy("brambleback", d)
	var other := _enemy("brambling", d, Vector3(5, 0, 0))
	var friend := _dummy(Vector3(2, 0, 0), "companion")
	var decor := _dummy(Vector3(3, 0, 0), "")
	assert_true(bool(e.can_be_hit_by(d)), "the player may hit it")
	assert_true(bool(e.can_be_hit_by(friend)), "a companion may hit it")
	assert_false(bool(e.can_be_hit_by(other)), "enemies never hit each other")
	e.health.invulnerable = true
	assert_false(bool(e.can_be_hit_by(d)), "not while invulnerable")
	e.health.invulnerable = false
	assert_true(bool(e.is_valid_victim(d)), "Krystal (player group / target) is a victim")
	assert_false(bool(e.is_valid_victim(friend)), "companions are never damaged")
	assert_false(bool(e.is_valid_victim(decor)), "decor is never damaged")
	assert_false(bool(e.is_valid_victim(other)), "other enemies are never damaged")
	assert_almost(float(e.deal_damage_to(friend, 10.0, Vector3.FORWARD, 3.0)), 0.0, 0.001, "damage refused for a companion")
	assert_almost(float(friend.health.hp), 100.0, 0.001)
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_false(bool(e.can_be_hit_by(d)), "not once defeated")


func test_slow_is_bounded_and_never_chains() -> void:
	var d := _dummy(Vector3.ZERO)
	var friend := _dummy(Vector3(2, 0, 0), "companion")
	assert_false(Base.apply_slow(friend, 0.5, 1.0), "only Krystal can be slowed")
	assert_true(Base.apply_slow(d, 0.1, 10.0, 4.0), "a slow applies")
	var b: Dictionary = GameState.buffs["slow"]
	assert_almost(float(b["mult"]), Base.SLOW_MIN_MULT, 0.001, "clamped to the strongest allowed slow")
	assert_almost(float(b["remaining"]), Base.SLOW_MAX_SECONDS, 0.001, "clamped duration")
	assert_false(Base.apply_slow(d, 0.7, 1.0), "never stacks / refreshes while active")
	GameState.buffs.erase("slow")
	Base.clock_override_ms += 3000
	assert_false(Base.apply_slow(d, 0.7, 1.0), "immune right after a slow (3 s + 4 s window)")
	Base.clock_override_ms += 4100
	assert_true(Base.apply_slow(d, 0.7, 1.0), "applies again once the immunity passed")
	assert_almost(float(GameState.buffs["slow"]["mult"]), 0.7, 0.001)


func test_committed_telegraph_floor_and_data_timings() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var expect := {"brambleback": {"charge": 1.0}, "lantern_moth": {"dust_orb": 1.1},
		"hollow_drudge": {"pick_swing": 1.2, "scrape": 1.4}, "brood_skitter": {"leap": 1.0},
		"knotted_elder": {"root_sweep": 1.3, "charge": 1.5, "roots": 1.6}}
	var x := 0.0
	for id in expect:
		var e := _enemy(id, d, Vector3(x, 0, 0))
		x += 6.0
		for atk in expect[id]:
			var t: float = e.attack_telegraph(e.attack_def(atk))
			assert_almost(t, float(expect[id][atk]), 0.001, "%s %s wind-up" % [id, atk])
			assert_true(t >= Base.MIN_COMMITTED_TELEGRAPH, "committed attacks wind up >= 1.0 s")
			assert_almost(float(e.attack_recover(e.attack_def(atk))), float(e.attack_def(atk)["recover"]), 0.001, "recover from data")
	# The floor applies whatever data says (0.7 today; the integrator may raise it to match the runtime).
	var raw := float(ItemDB.enemy("brood_skitter")["telegraph"])
	var sk := _enemy("brood_skitter", d, Vector3(x, 0, 0))
	assert_almost(float(sk.attack_telegraph({"telegraph": raw})), maxf(raw, Base.MIN_COMMITTED_TELEGRAPH), 0.001, "data %.2f s -> runtime floor" % raw)
	assert_almost(float(sk.attack_telegraph({"telegraph": 0.4})), Base.MIN_COMMITTED_TELEGRAPH, 0.001, "anything shorter is raised to the floor")


func test_underground_damage_follows_intensity() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var drudge := _enemy("hollow_drudge", d)
	var bb := _enemy("brambleback", d, Vector3(8, 0, 0))
	Settings.set_value("horror_intensity", 0)
	assert_almost(float(drudge.attack_damage_for(drudge.attack_def("pick_swing"))), 15.0 * 0.6, 0.01, "Gentle: underground damage x0.6")
	assert_almost(float(bb.attack_damage_for(bb.attack_def("charge"))), 13.0, 0.01, "surface enemies never scale")
	Settings.set_value("horror_intensity", 2)
	assert_almost(float(drudge.attack_damage_for(drudge.attack_def("pick_swing"))), 15.0 * 1.15, 0.01, "Intense x1.15")
	Settings.set_value("horror_intensity", 1)
	assert_almost(float(drudge.attack_damage_for(drudge.attack_def("scrape"))), 14.0, 0.01, "Standard: data damage")


## Integration R80: threat scaling follows the area the enemy fights in (Combat.damage_mult_for_area), not its
## data home; the Echo Trial and unknown / empty area ids keep the data rule. Legacy numbers never change.
func test_threat_scaling_follows_the_area_fought_in() -> void:
	var saved_id: String = Game.area_id
	var d := _dummy(Vector3(0, 0, -30))
	var drudge := _enemy("hollow_drudge", d)
	var skitter := _enemy("brood_skitter", d, Vector3(8, 0, 0))
	var bb := _enemy("brambleback", d, Vector3(16, 0, 0))
	var bramble := _enemy("brambling", d, Vector3(24, 0, 0))
	var gloom := _enemy("gloomling", d, Vector3(32, 0, 0))
	var swing: Dictionary = drudge.attack_def("pick_swing")
	var leap: Dictionary = skitter.attack_def("leap")
	var charge: Dictionary = bb.attack_def("charge")
	Settings.set_value("horror_intensity", 0)
	Game.area_id = "hallowmere_reach"
	assert_almost(float(drudge.attack_damage_for(swing)), 15.0, 0.01, "a Drudge in the Reach's candle yard hits like a surface threat")
	assert_almost(float(skitter.attack_damage_for(leap)), 7.0, 0.01, "nothing scales outdoors")
	Game.area_id = "hushed_works"
	assert_almost(float(drudge.attack_damage_for(swing)), 15.0 * 0.6, 0.01, "Gentle x0.6 underground")
	assert_almost(float(skitter.attack_damage_for(leap)), 7.0 * 0.6, 0.01, "a Skitter in the Works scales")
	assert_almost(float(bb.attack_damage_for(charge)), 13.0 * 0.6, 0.01, "whatever its data home, underground scales")
	Game.area_id = "tobin_annex"
	assert_almost(float(drudge.attack_damage_for(swing)), 15.0 * 0.6, 0.01, "the annex is underground")
	Game.area_id = "moonveil_manor"
	assert_almost(float(drudge.attack_damage_for(swing)), 15.0, 0.01, "interiors never scale")
	for keep in ["echo_trial", "", "arena", "not_an_area"]:
		Game.area_id = String(keep)
		assert_almost(float(skitter.attack_damage_for(leap)), 7.0 * 0.6, 0.01, "'%s': data rule (underground scales)" % keep)
		assert_almost(float(drudge.attack_damage_for(swing)), 15.0 * 0.6, 0.01, "'%s': data rule (drudge underground)" % keep)
		assert_almost(float(bb.attack_damage_for(charge)), 13.0, 0.01, "'%s': data rule (surface enemy never scales)" % keep)
	# Legacy enemies keep their exact numbers everywhere (attack_damage() follows their data area).
	for where in ["", "surface", "below", "hallowmere_reach", "hushed_works", "echo_trial"]:
		Game.area_id = String(where)
		assert_almost(float(bramble.attack_damage()), 10.0, 0.001, "Brambling unchanged in '%s'" % where)
		assert_almost(float(gloom.attack_damage()), 12.0 * 0.6, 0.001, "Gloomling (Below, Gentle) unchanged in '%s'" % where)
	Settings.set_value("horror_intensity", 1)
	for where in ["", "surface", "below", "hushed_works"]:
		Game.area_id = String(where)
		assert_almost(float(bramble.attack_damage()), 10.0, 0.001, "Standard Brambling in '%s'" % where)
		assert_almost(float(gloom.attack_damage()), 12.0, 0.001, "Standard Gloomling in '%s'" % where)
	Game.area_id = saved_id


func test_defeat_flag_setup_key() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _enemy("hollow_drudge", d, Vector3.ZERO, {"defeat_flag": "c1x_drudge_defeated"})
	assert_false(bool(GameState.get_flag("c1x_drudge_defeated")))
	e.health.apply_damage(999.0, d, Vector3.FORWARD)
	assert_true(bool(GameState.get_flag("c1x_drudge_defeated")), "content modules can pass a defeat flag")


func test_sounds_are_existing_names_only() -> void:
	for s in USED_SOUNDS:
		assert_true(Audio.has_sound(String(s), true), "sound '%s' exists" % s)
	for k in Skitter.SOUNDS:
		assert_true(USED_SOUNDS.has(String(Skitter.SOUNDS[k])), "skitter sound listed: %s" % Skitter.SOUNDS[k])
		assert_true(USED_SOUNDS.has(String(Skitter.ALT_SOUNDS[k])), "sprout sound listed: %s" % Skitter.ALT_SOUNDS[k])


# --- Telegraph FX --------------------------------------------------------------------------------------------

func test_telegraph_geometry_helpers() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(0, 0, -4)
	assert_true(TelegraphFx.segment_hit(a, b, 0.6, Vector3(0.5, 0, -2)), "inside the lane")
	assert_false(TelegraphFx.segment_hit(a, b, 0.6, Vector3(0.7, 0, -2)), "beside the lane")
	assert_false(TelegraphFx.segment_hit(a, b, 0.6, Vector3(0, 0, -4.8)), "beyond the lane end")
	assert_almost(TelegraphFx.segment_distance(a, b, Vector3(1, 3, -1)), 1.0, 0.001, "flat distance")
	assert_true(TelegraphFx.in_sector(a, Vector3.FORWARD, 3.0, 40.0, Vector3(0.3, 0, -2)), "inside a narrow wedge")
	assert_false(TelegraphFx.in_sector(a, Vector3.FORWARD, 3.0, 40.0, Vector3(1.5, 0, -1.5)), "45 degrees off a 40 degree wedge")
	assert_true(TelegraphFx.in_sector(a, Vector3.FORWARD, 3.0, 150.0, Vector3(1.5, 0, -1.5)), "inside a 150 degree sweep")
	assert_true(TelegraphFx.in_ring(a, 1.0, Vector3(0.6, 0, 0.6)))
	assert_false(TelegraphFx.in_ring(a, 1.0, Vector3(0.8, 0, 0.8)))


func test_telegraph_marks_footprint_share_resources_and_bound_spots() -> void:
	var holder := Node3D.new()
	add_child(holder)
	_nodes.append(holder)
	var m1: Node3D = TelegraphFx.new()
	var m2: Node3D = TelegraphFx.new()
	holder.add_child(m1)
	holder.add_child(m2)
	m1.show_lane(Vector3(1, 0, 1), Vector3(1, 0, -5), 1.4, TelegraphFx.DANGER)
	var f: Dictionary = m1.footprint()
	assert_eq(f["kind"], "lane")
	assert_almost(float(f["width"]), 1.4, 0.001)
	assert_true((f["facing"] as Vector3).is_equal_approx(Vector3(0, 0, -1)), "faces along the lane")
	assert_true(m1.top_level, "marks never move with the enemy body")
	m2.show_lane(Vector3(4, 0, 0), Vector3(4, 0, 3), 2.0, TelegraphFx.DANGER)
	assert_eq(m1.get("_fill").mesh, m2.get("_fill").mesh, "unit meshes are shared")
	assert_eq(m1.get("_fill").material_override, m2.get("_fill").material_override, "alpha materials are shared per colour")
	m1.move_lane(Vector3(1, 0, 1), Vector3(5, 0, 1))
	assert_true((m1.footprint()["facing"] as Vector3).is_equal_approx(Vector3(1, 0, 0)), "move_lane turns it")
	m2.show_arc(Vector3.ZERO, Vector3.FORWARD, 2.7, 40.0, TelegraphFx.WARN)
	assert_eq(m2.footprint()["kind"], "arc")
	assert_almost(float(m2.footprint()["arc_deg"]), 40.0, 0.001)
	var pts: Array = []
	for i in 12:
		pts.append(Vector3(float(i), 0, 0))
	m2.show_spots(pts, 0.75)
	assert_eq((m2.footprint()["points"] as Array).size(), TelegraphFx.MAX_SPOTS, "spot marks are bounded")
	m2.hide_mark()
	assert_false(bool(m2.is_showing()))
	assert_false(m2.visible)


func test_reduce_flashing_marks_do_not_pulse() -> void:
	var m: Node3D = TelegraphFx.new()
	add_child(m)
	_nodes.append(m)
	m.show_ring(Vector3.ZERO, 1.0)
	m.set_progress(0.5, false)
	Settings.set_value("reduce_flashing", true)
	var levels := {}
	for i in 40:
		m._process(0.037)
		levels[int(m.get("_level"))] = true
	assert_eq(levels.size(), 1, "steady with reduce_flashing (%s)" % str(levels.keys()))
	Settings.set_value("reduce_flashing", false)
	levels.clear()
	for i in 40:
		m._process(0.037)
		levels[int(m.get("_level"))] = true
	assert_true(levels.size() > 1, "pulses otherwise")


# --- Projectile ----------------------------------------------------------------------------------------------

func _orb(target: Node3D, from: Vector3, params: Dictionary = {}) -> Node3D:
	var p: Node3D = Projectile.new()
	var prm := {"target": target, "damage": 9.0, "speed": 5.0, "range": 12.0, "homing": 0.0}
	prm.merge(params, true)
	p.setup(prm)
	add_child(p)
	p.set_physics_process(false)
	p.launch(from, target)
	_nodes.append(p)
	return p


func _fly(p: Node3D, max_t: float = 4.0) -> void:
	var t := 0.0
	while is_instance_valid(p) and String(p.get("result")) == "" and t < max_t:
		p.step(1.0 / 60.0)
		t += 1.0 / 60.0


func test_projectile_hits_once_through_the_health_path() -> void:
	var d := _dummy(Vector3(0, 0, -4))
	var p := _orb(d, Vector3(0, 0.9, 0))
	_fly(p)
	assert_eq(String(p.get("result")), "hit")
	assert_almost(float(d.health.hp), 91.0, 0.001, "9 damage")
	assert_eq(d.damaged_count, 1, "exactly one hit")
	assert_eq(d.knocks, 1, "knockback once")


func test_projectile_never_passes_walls() -> void:
	var d := _dummy(Vector3(0, 0, -5))
	_wall(Vector3(0, 1, -2.5), Vector3(4, 4, 0.3))
	await wait_physics(3)
	var p := _orb(d, Vector3(0, 0.9, 0))
	_fly(p)
	assert_eq(String(p.get("result")), "wall", "popped on the wall")
	assert_true((p.global_position.z) > -2.5, "stopped at the wall (z %.2f)" % p.global_position.z)
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage behind a wall")


func test_projectile_dodge_passes_and_never_hits_twice() -> void:
	var d := _dummy(Vector3(0, 0, -3))
	d.health.grant_iframes(0.2)
	var p := _orb(d, Vector3(0, 0.9, 0), {"range": 8.0})
	_fly(p, 0.7)
	assert_true(bool(p.get("dodged")), "rolled through it")
	assert_almost(float(d.health.hp), 100.0, 0.001)
	d.health.set("_iframe_until_ms", 0)
	_fly(p)
	assert_almost(float(d.health.hp), 100.0, 0.001, "a dodged orb cannot come back for a second hit")
	assert_eq(String(p.get("result")), "expired")


func test_projectile_ignores_companions_and_is_capped() -> void:
	var d := _dummy(Vector3(0, 0, -6))
	var friend := _dummy(Vector3(0, 0, -3), "companion")
	var p := _orb(d, Vector3(0, 0.9, 0))
	_fly(p)
	assert_almost(float(friend.health.hp), 100.0, 0.001, "flies past a companion")
	assert_eq(String(p.get("result")), "hit")
	await wait_frames(1)
	var orbs: Array = []
	for i in Projectile.MAX_LIVE:
		orbs.append(_orb(d, Vector3(float(i) * 2.0, 0.9, 20)))
	assert_false(Projectile.can_fire(), "capped at MAX_LIVE (%d)" % Projectile.MAX_LIVE)
	for o in orbs:
		o.queue_free()
	await wait_frames(1)
	assert_true(Projectile.can_fire(), "free again once they are gone")


# --- Leap landing height ----------------------------------------------------------------------------------------

func test_leap_target_heights() -> void:
	var d := _dummy(Vector3(0, 0, -30))
	var e := _enemy("brood_skitter", d)
	await wait_physics(2)
	var full: Vector3 = e.leap_target(Vector3(0, 0.8, -2.0), 3.0)
	assert_almost(full.z, -2.0, 0.001, "reaches a target inside its range")
	assert_almost(full.y, 0.8, 0.001, "lands at the target's height")
	var capped: Vector3 = e.leap_target(Vector3(0, 1.2, -6.0), 3.0)
	assert_almost(capped.z, -3.0, 0.001, "capped at its max distance")
	assert_almost(capped.y, 0.6, 0.001, "capped short of her: follows the slope (not her full height)")
	_wall(Vector3(0, 1, -1.5), Vector3(4, 2, 0.3))
	await wait_physics(2)
	var walled: Vector3 = e.leap_target(Vector3(0, 0.8, -2.5), 3.0)
	assert_true(walled.z > -1.5, "stopped short of the wall (z %.2f)" % walled.z)
	assert_almost(walled.y, 0.0, 0.001, "stays on its own level in front of a wall")


# --- Committed states / perf --------------------------------------------------------------------------------

func test_committed_states_keep_the_token_and_threaten() -> void:
	var d := _dummy(Vector3(0, 0, -4))
	var e := _enemy("brambleback", d)
	var t := 0.0
	while e.state != "charge" and t < 5.0:
		e.tick(DT)
		t += DT
	assert_eq(e.state, "charge")
	assert_true(Base._attackers.has(e.get_instance_id()), "the charge holds the attack token")
	assert_true(bool(e.is_threatening()), "a charge is threatening (saving / director gate)")
	Events.player_died.emit()
	assert_eq(e.state, "return", "Krystal's defeat ends a committed attack")
	assert_false(Base._attackers.has(e.get_instance_id()), "and releases the token")
	assert_false(bool(e.mark().is_showing()), "and hides its ground mark")


func test_ten_new_enemies_tick_cheaply() -> void:
	var target := _dummy(Vector3.ZERO)
	var enemies: Array = []
	for i in 10:
		var id: String = NEW_IDS[i % NEW_IDS.size()]
		var a := TAU * float(i) / 10.0
		var pos := Vector3(cos(a) * 7.0, 0.0, sin(a) * 7.0)
		enemies.append(_enemy(id, target, pos))
	await wait_physics(2)
	var t0 := Time.get_ticks_usec()
	var frames := 120
	for f in frames:
		for e in enemies:
			e.tick(1.0 / 60.0)
			e._apply_movement(1.0 / 60.0)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	print("PERF ch1x enemies: 10 new enemies tick+move = %.3f ms per frame" % per_frame_ms)
	assert_true(per_frame_ms < 3.0, "10 new enemies cost < 3 ms per frame (%.3f ms)" % per_frame_ms)
