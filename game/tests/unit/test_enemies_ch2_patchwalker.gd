extends "res://tests/test_case.gd"
## Patchwalker (module C5): the rake (wind-up timing, marked wedge = hit wedge, one hit, stepping outside the arc,
## cutting the wind-up with a hit) and the mud clod (a separate LONGER tell, a marked throw line, a straight throw
## along the locked line so side-stepping avoids it, never through walls, one clod at a time) and its slow: bounded,
## only on a real hit, through the player's own API, and never chained.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Walker := preload("res://src/enemies/patchwalker.gd")
const SHARED_PROJECTILE := "res://src/combat/projectile.gd"

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null


class Krystal extends CharacterBody3D:
	var health: Node
	var damaged_count: int = 0
	var slows: Array = []
	var accept_slow := true

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		pass

	func apply_slow(mult: float, seconds: float, source: String = "") -> bool:
		if not accept_slow:
			return false
		slows.append({"mult": mult, "seconds": seconds, "source": source})
		return true


class Plain extends CharacterBody3D:
	var health: Node

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("stop_all")
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	GameState.buffs.erase("slow")
	Game.area = _saved_area
	await wait_frames(2)


func _krystal(pos: Vector3, group: String = "player") -> Krystal:
	var k := Krystal.new()
	add_child(k)
	k.global_position = pos
	k.add_to_group(group)
	_nodes.append(k)
	return k


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
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


func _walker(target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create("patchwalker", {"home": pos, "no_drops": true})
	(e as Node3D).position = pos
	add_child(e)
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _until(e: Node, s: String, max_t: float = 10.0) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		t += DT
	return t


func _fly(p: Node3D, max_t: float = 4.0) -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("invalidate_targets")
	p.set_physics_process(false)
	var t := 0.0
	while is_instance_valid(p) and String(p.get("result")) == "" and t < max_t:
		p.step(DT)
		t += DT


func test_rake_sequence_marked_wedge_one_hit() -> void:
	var k := _krystal(Vector3(0, 0, -2.4))
	var e := _walker(k)
	e.next_attack = "rake"
	_until(e, "telegraph", 4.0)
	assert_eq(String(e.attack_kind), "rake")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "arc", "a wedge marks the rake")
	assert_almost(float(m.footprint()["radius"]), float(e.rake_reach()), 0.001, "marked reach = hit reach")
	assert_almost(float(m.footprint()["arc_deg"]), 110.0, 0.001, "data arc_deg 110")
	var tele := _until(e, "rake", 3.0)
	assert_almost(tele, 1.1, DT * 2.0, "rake wind-up = data 1.1 s")
	assert_true(bool(m.footprint()["locked"]), "locked before the sweep")
	_until(e, "recover", 2.0)
	assert_eq(k.damaged_count, 1, "one hit")
	assert_almost(float(k.health.hp), 84.0, 0.001, "data damage 16")
	assert_almost(_until(e, "chase", 3.0), 1.5, DT * 2.0, "recover = data 1.5 s")


func test_stepping_outside_the_arc_avoids_the_rake() -> void:
	var k := _krystal(Vector3(0, 0, -2.4))
	var e := _walker(k)
	e.next_attack = "rake"
	_until(e, "telegraph", 4.0)
	while e.state_time < 1.0:
		e.tick(DT)
	k.global_position = Vector3(2.6, 0, 0.6)             # beside and slightly behind it: outside the 110 degree wedge
	_until(e, "recover", 2.0)
	assert_almost(float(k.health.hp), 100.0, 0.001, "outside the marked arc: safe")
	k.global_position = Vector3(0, 0, -3.8)
	assert_true(float(e.rake_reach()) + 0.45 < 3.8, "and beyond its reach")


func test_a_hit_cuts_the_rake_windup_once() -> void:
	var k := _krystal(Vector3(0, 0, -2.4))
	var e := _walker(k)
	e.next_attack = "rake"
	_until(e, "telegraph", 4.0)
	e.health.apply_damage(8.0, k, Vector3.FORWARD)
	assert_eq(e.state, "flinch", "a hit during the wind-up cuts it")
	assert_false(bool(e.mark().is_showing()), "and clears its mark")
	e.next_attack = "rake"
	_until(e, "telegraph", 4.0)
	e.health.apply_damage(8.0, k, Vector3.FORWARD)
	assert_eq(e.state, "telegraph", "but not again right away (flinch immunity): no stun-lock")


func test_mud_clod_long_tell_marked_line_and_one_hit_with_slow() -> void:
	var k := _krystal(Vector3(0, 0, -6.0))
	var e := _walker(k)
	_until(e, "telegraph", 4.0)
	assert_eq(String(e.attack_kind), "mud_clod", "from range it scoops mud")
	var m: Node3D = e.mark()
	assert_eq(String(m.footprint()["kind"]), "lane", "the throw line is drawn")
	assert_almost(float(m.footprint()["width"]), Walker.CLOD_LANE_WIDTH, 0.001)
	var tele := _until(e, "throw", 3.0)
	assert_almost(tele, 1.6, DT * 2.0, "a separate, longer tell than the rake (data 1.6 s)")
	_until(e, "recover", 1.0)
	var clod: Node3D = e.clod
	assert_not_null(clod, "a clod was thrown")
	assert_eq(int(e.clods_thrown), 1)
	assert_eq(String(clod.get("kind")), "mud_clod", "thrown through enemy_base.fire_projectile (kind passes through)")
	assert_eq(clod.get("shooter"), e)
	assert_false(bool(e.clod_ready()), "one clod at a time / cooldown")
	var captions: Array = []
	var cb := func(text: String) -> void: captions.append(text)
	Events.caption.connect(cb)
	_fly(clod)
	Events.caption.disconnect(cb)
	assert_true(captions.has("[mud splatters - your steps feel heavy]"), "the slow is captioned even right after the throw's tell caption (%s)" % str(captions))
	assert_eq(String(clod.get("result")), "hit", "the clod lands")
	assert_eq(k.damaged_count, 1, "one hit")
	assert_almost(float(k.health.hp), 92.0, 0.001, "clod data damage 8")
	assert_eq(k.slows.size(), 1, "the slow went through the player's own API")
	assert_almost(float(k.slows[0]["mult"]), 0.7, 0.001, "data slow 0.3 -> speed x 0.7")
	assert_almost(float(k.slows[0]["seconds"]), 2.0, 0.001, "data slow_seconds 2")
	assert_eq(String(k.slows[0]["source"]), "patchwalker")


func test_sidestepping_the_locked_line_dodges_the_clod() -> void:
	var k := _krystal(Vector3(0, 0, -6.0))
	var e := _walker(k)
	e.next_attack = "mud_clod"
	_until(e, "telegraph", 4.0)
	while e.state_time < 1.3:
		e.tick(DT)
	assert_true(bool(e.mark().footprint()["locked"]), "the line locked")
	k.global_position = Vector3(1.6, 0, -6.0)
	_until(e, "recover", 2.0)
	var clod: Node3D = e.clod
	assert_not_null(clod)
	_fly(clod)
	assert_ne(String(clod.get("result")), "hit", "the clod flies straight along the locked line and misses")
	assert_almost(float(k.health.hp), 100.0, 0.001, "no damage")
	assert_eq(k.slows.size(), 0, "no slow without a hit")


func test_slow_is_bounded_and_never_chains() -> void:
	var k := _krystal(Vector3(0, 0, -6.0))
	var e := _walker(k)
	e.call("_on_clod_hit", k, 8.0)
	assert_eq(k.slows.size(), 1, "first clod: slowed")
	e.call("_on_clod_hit", k, 8.0)
	assert_eq(k.slows.size(), 1, "a second clod right away cannot chain the slow")
	e.call("_on_clod_hit", k, 0.0)
	assert_eq(k.slows.size(), 1, "a blocked / dodged clod never slows")
	Base.clock_override_ms = 100000 + int((2.0 + 4.0) * 1000.0) + 10
	e.call("_on_clod_hit", k, 8.0)
	assert_eq(k.slows.size(), 2, "only after the slow and its data immunity (4 s) have passed")
	# Without a player API the buff itself is bounded (enemy_base clamps).
	Base.reset_attack_tokens()
	var p := Plain.new()
	add_child(p)
	p.add_to_group("player")
	_nodes.append(p)
	e.call("_on_clod_hit", p, 8.0)
	assert_true(GameState.buffs.has("slow"), "slow buff applied")
	assert_true(float(GameState.buffs["slow"]["mult"]) >= Base.SLOW_MIN_MULT, "never below the floor")
	assert_true(float(GameState.buffs["slow"]["remaining"]) <= Base.SLOW_MAX_SECONDS, "never longer than the cap")


## Integration pass 2 (P02): enemy_base.fire_projectile passes "dir" (fly straight along it; the target only gates
## the shot) and "on_hit" through to the shared projectile; without them it still aims at the target.
func test_fire_projectile_passes_dir_and_on_hit() -> void:
	var k := _krystal(Vector3(0, 0, -6.0))
	var e := _walker(k)
	var got: Array = []
	var cb := func(t: Node, dealt: float) -> void: got.append([t, dealt])
	var from: Vector3 = e.attack_origin()
	# "dir" away from her: it flies that way and never hits her.
	var p1: Node3D = e.fire_projectile(from, k, {"dir": Vector3(1, 0, 0), "on_hit": cb, "damage": 5.0, "speed": 9.0, "range": 8.0})
	assert_not_null(p1, "fired")
	if p1 != null:
		var v: Vector3 = p1.get("velocity")
		assert_true(v.normalized().dot(Vector3(1, 0, 0)) > 0.99, "launched along dir, not at her (%s)" % str(v))
		_fly(p1)
		assert_ne(String(p1.get("result")), "hit", "it went along dir, not at her")
	assert_almost(float(k.health.hp), 100.0, 0.001)
	assert_eq(got.size(), 0, "no hit, no callback")
	# "dir" at her + on_hit: the callback hears the real damage.
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("stop_all")
	var p2: Node3D = e.fire_projectile(from, k, {"dir": Vector3(0, 0, -1), "on_hit": cb, "damage": 5.0, "speed": 9.0, "range": 10.0})
	assert_not_null(p2)
	if p2 != null:
		_fly(p2)
		assert_eq(String(p2.get("result")), "hit")
	assert_eq(got.size(), 1, "on_hit called once")
	if got.size() == 1:
		assert_eq(got[0][0], k)
		assert_almost(float(got[0][1]), 5.0, 0.001, "with the damage dealt")
	# Default (no dir): aims at her, as before.
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("stop_all")
	k.global_position = Vector3(3, 0, -6.0)
	var p3: Node3D = e.fire_projectile(from, k, {"damage": 5.0, "speed": 9.0, "range": 12.0})
	assert_not_null(p3)
	if p3 != null:
		_fly(p3)
		assert_eq(String(p3.get("result")), "hit", "the default still aims at the target")
	assert_eq(String(p3.get("kind")) if p3 != null else "", "patchwalker", "kind defaults to the enemy id")


func test_no_throw_through_a_wall_and_companions_untouched() -> void:
	var k := _krystal(Vector3(0, 0, -6.0))
	var friend := _krystal(Vector3(0.2, 0, -3.0), "companion")
	var fence := _box(Vector3(0, 1.0, -1.5), Vector3(6, 3, 0.4))
	fence.collision_layer = 32                           # a structure: it sees her over it, but cannot throw through it
	var e := _walker(k)
	await wait_physics(3)
	var seen := false
	for i in 240:
		e.tick(DT)
		seen = seen or e.state == "chase"
	assert_true(seen, "it noticed her (sight ignores structures)")
	assert_ne(e.state, "throw", "no throw without a clear line")
	assert_ne(e.state, "telegraph", "no wind-up without a clear line")
	assert_eq(int(e.clods_thrown), 0)
	assert_almost(float(k.health.hp), 100.0, 0.001)
	assert_almost(float(friend.health.hp), 100.0, 0.001)
