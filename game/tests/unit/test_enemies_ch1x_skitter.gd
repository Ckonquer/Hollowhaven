extends "res://tests/test_case.gd"
## Brood Skitter / Pale Sprout: telegraph (legs draw in, a FIXED ring on the landing spot; 1.0 s floor) -> leap
## (0.4 s arc) -> one landing hit through the health path -> recover 1.1 s; stepping off the ring avoids it; a
## wall stops the leap short and protects her; easy to stagger; arachnophobia swaps silhouette, name and every
## sound name (live, fight state untouched); minion params.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Skitter := preload("res://src/enemies/brood_skitter.gd")
const SkitterVisual := preload("res://src/enemies/brood_skitter_visual.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []
var _saved_area: Node = null


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
	Settings.set_value("arachnophobia", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("arachnophobia", false)
	Game.area = _saved_area
	await wait_frames(2)


func _dummy(pos: Vector3) -> Node3D:
	var d := Dummy.new()
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	_nodes.append(d)
	return d


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


func _skitter(target: Node3D, pos: Vector3 = Vector3.ZERO, params: Dictionary = {}) -> Node:
	var p := params.duplicate()
	p["home"] = pos
	p["no_drops"] = true
	var e: Node = Factory.create("brood_skitter", p)
	add_child(e)
	(e as Node3D).global_position = pos
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


static func _aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree() and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var ab: AABB = (inv * mi.global_transform) * mi.get_aabb()
			out = ab if first else out.merge(ab)
			first = false
	return out


func test_leap_sequence_mark_and_one_hit() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _skitter(d)
	assert_eq(e.state, "idle", "starts idle")
	var seen: Array = []
	e.state_changed.connect(func(s: String) -> void: seen.append(s))
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph")
	var m: Node3D = e.mark()
	var f: Dictionary = m.footprint()
	assert_eq(f["kind"], "ring", "a small ring marks the landing spot")
	assert_almost(float(f["radius"]), Skitter.LAND_RADIUS, 0.001, "ring = landing hit radius")
	assert_true((f["center"] as Vector3).distance_to(d.global_position) < 0.05, "the ring is where Krystal stood")
	var tele := _until(e, "leap", 3.0)
	assert_almost(tele, 1.0, DT * 2.0, "wind-up floored to 1.0 s (data 0.7)")
	var leap := _until(e, "recover", 2.0)
	assert_almost(leap, Skitter.LEAP_TIME, DT * 2.0, "a short 0.4 s leap")
	assert_true((e as Node3D).global_position.distance_to(Vector3(f["center"]) ) < 0.1, "lands on the mark")
	assert_almost(float(d.health.hp), 93.0, 0.001, "data damage (7) once")
	assert_eq(d.damaged_count, 1)
	var rec := _until(e, "chase", 3.0)
	assert_almost(rec, 1.1, DT * 2.0, "recover data 1.1 s")
	assert_eq(seen.slice(0, 5), ["chase", "telegraph", "leap", "recover", "chase"], "sequence (%s)" % str(seen))


func test_stepping_off_the_fixed_mark_avoids_it() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _skitter(d)
	_until(e, "telegraph", 4.0)
	var center: Vector3 = e.mark().footprint()["center"]
	for i in 20:
		e.tick(DT)
	d.global_position = Vector3(1.6, 0, -2.5)
	for i in 10:
		e.tick(DT)
	assert_true((e.mark().footprint()["center"] as Vector3).is_equal_approx(center), "the ring does not follow her")
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 100.0, 0.001, "off the ring = no damage")


func test_no_leap_through_walls() -> void:
	var d := _dummy(Vector3(0, 0, -2.6))
	var wall := _box(Vector3(0, 1, -1.3), Vector3(4, 3, 0.3))
	var e := _skitter(d)
	await wait_physics(3)
	for i in 180:
		e.tick(DT)
	assert_false(e.state in ["telegraph", "leap"], "no wind-up without a clear line (state %s)" % e.state)
	wall.queue_free()
	await wait_physics(3)
	_until(e, "telegraph", 4.0)
	assert_eq(e.state, "telegraph")
	_box(Vector3(0, 1, -1.3), Vector3(4, 3, 0.3))       # cover appears mid-wind-up
	await wait_physics(3)
	_until(e, "recover", 3.0)
	assert_true((e as Node3D).global_position.z > -1.3, "lands short of the wall (z %.2f)" % (e as Node3D).global_position.z)
	assert_almost(float(d.health.hp), 100.0, 0.001, "no damage behind the wall")


func test_easy_to_stagger() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _skitter(d)
	_until(e, "telegraph", 4.0)
	e.health.apply_damage(3.0, d, Vector3.FORWARD)
	assert_eq(e.state, "flinch", "a hit cancels the leap wind-up")
	e.tick(DT)
	e.health.apply_damage(3.0, d, Vector3.FORWARD)
	assert_eq(e.state, "flinch", "no flinch immunity: every hit staggers it")
	assert_almost(float(e.get("_flinch_immune")), 0.0, 0.001)
	_until(e, "leap", 5.0)
	assert_eq(e.state, "leap")
	e.health.apply_damage(3.0, d, Vector3.FORWARD)
	assert_eq(e.state, "leap", "the leap itself is not interrupted")
	_until(e, "recover", 2.0)
	e.health.apply_damage(3.0, d, Vector3.FORWARD)
	assert_eq(e.state, "flinch", "even its recovery can be staggered")


func test_arachnophobia_swaps_silhouette_name_and_sounds_live() -> void:
	var d := _dummy(Vector3(0, 0, -2.5))
	var e := _skitter(d)
	assert_false(bool(e.visual.is_sprout()))
	assert_eq(int(e.visual.leg_count()), 8, "eight legs")
	assert_eq(String(e.display_name()), "Brood Skitter")
	assert_eq(String(e.snd("telegraph")), "weaver_rattle")
	_until(e, "telegraph", 4.0)
	var st_before: String = e.state
	var t_before: float = e.state_time
	var land: Vector3 = e.landing_point()
	var old_visual: Node = e.visual
	Settings.set_value("arachnophobia", true)
	assert_ne(e.visual, old_visual, "visual rebuilt live")
	assert_true(bool(e.visual.is_sprout()), "Pale Sprout visual")
	assert_eq(int(e.visual.leg_count()), 0, "no legs at all")
	assert_eq(int(e.visual.tendril_count()), 3, "three root tendrils instead")
	assert_eq(String(e.display_name()), "Pale Sprout", "alt name from data")
	assert_eq(ItemDB.enemy_display_desc("brood_skitter"), String(ItemDB.enemy("brood_skitter")["alt_desc"]), "alt description")
	assert_eq(e.state, st_before, "fight state untouched")
	assert_almost(float(e.state_time), t_before, 0.0001, "timers untouched")
	assert_true((e.landing_point() as Vector3).is_equal_approx(land), "landing untouched")
	assert_eq(e.mark().get("color"), TelegraphFx.PALE, "the ring recoloured for the mode")
	var normal: Array = Skitter.SOUNDS.values()
	for k in Skitter.ALT_SOUNDS:
		var alt := String(Skitter.ALT_SOUNDS[k])
		assert_false(normal.has(alt), "alt sound '%s' is not in the spider set" % alt)
		assert_eq(String(e.snd(k)), alt, "plays the alt set now (%s)" % k)
		assert_true(Audio.has_sound(alt, true), "alt sound exists: %s" % alt)
	_until(e, "recover", 3.0)
	assert_almost(float(d.health.hp), 93.0, 0.001, "same attack, same damage")
	# Spawned while the option is on: a sprout from the start.
	var e2 := _skitter(d, Vector3(8, 0, 0))
	assert_true(bool(e2.visual.is_sprout()))
	Settings.set_value("arachnophobia", false)
	assert_false(bool(e2.visual.is_sprout()), "and back")


func test_silhouettes_differ() -> void:
	var holder := Node3D.new()
	add_child(holder)
	_nodes.append(holder)
	var spider: Node3D = SkitterVisual.new()
	spider.setup({"sprout": false})
	holder.add_child(spider)
	var sprout: Node3D = SkitterVisual.new()
	sprout.setup({"sprout": true})
	holder.add_child(sprout)
	sprout.position = Vector3(5, 0, 0)
	var a := _aabb(spider)
	var b := _aabb(sprout)
	assert_true(a.size.y < 0.5 and a.size.x > 0.5, "skitter: low and wide (%s)" % str(a.size))
	assert_true(b.size.y > 0.8 and b.size.x < 0.5, "sprout: tall and narrow (%s)" % str(b.size))
	assert_true(b.position.y > 0.1, "the sprout floats (lowest point %.2f m)" % b.position.y)
	assert_true(a.position.y < 0.05, "the skitter stands on the ground (%.2f m)" % a.position.y)


func test_minion_params() -> void:
	var d := _dummy(Vector3(0, 0, -12))
	var e := _skitter(d, Vector3.ZERO, {"speed_scale": 0.8, "alert": true})
	assert_almost(float(e._speed_scale()), 0.8, 0.001, "slower Gentle minion")
	assert_true(float(e.aggro_radius()) > float(ItemDB.enemy("brood_skitter")["aggro_radius"]), "released alert")
	assert_false(bool(e.drops_enabled), "boss adds drop nothing")
