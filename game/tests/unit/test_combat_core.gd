extends "res://tests/test_case.gd"
## Combat core: health math, melee arc / reach / line of sight, knockback, blocked hits,
## light exposure and horror-intensity damage scaling.

const Combat := preload("res://src/combat/combat.gd")
const Health := preload("res://src/combat/health.gd")

var _nodes: Array = []


class Target extends CharacterBody3D:
	var health: Node
	var knocks: Array = []
	var blocked: int = 0

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cs.shape = cap
		cs.position.y = 0.9
		add_child(cs)

	func knockback(dir: Vector3, force: float) -> void:
		knocks.append([dir, force])

	func on_hit_blocked(_a: Node, _d: Vector3) -> void:
		blocked += 1


class LightSrc extends Node3D:
	var light_radius: float = 7.0
	var on := true

	func is_light_active() -> bool:
		return on


func before_each() -> void:
	_nodes.clear()
	Settings.set_value("horror_intensity", 1)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Settings.set_value("horror_intensity", 1)
	Combat.invalidate_light_cache()
	await wait_frames(1)


func _add(n: Node3D, pos: Vector3, group: String = "") -> Node3D:
	add_child(n)
	n.global_position = pos
	if group != "":
		n.add_to_group(group)
	_nodes.append(n)
	return n


func _attacker() -> Node3D:
	return _add(Node3D.new(), Vector3.ZERO)


# --- Health ------------------------------------------------------------------------------------

func test_health_damage_multiplier_and_death() -> void:
	var h: Node = Health.new()
	h.max_hp = 40.0
	add_child(h)
	_nodes.append(h)
	h.damage_taken_mult = 2.0
	assert_almost(h.apply_damage(10.0), 20.0, 0.001, "exposed targets take double")
	assert_almost(h.hp, 20.0)
	h.invulnerable = true
	assert_almost(h.apply_damage(10.0), 0.0, 0.001, "invulnerable ignores damage")
	h.invulnerable = false
	var died := [false]
	h.died.connect(func() -> void: died[0] = true)
	assert_almost(h.apply_damage(500.0), 20.0, 0.001, "damage is capped at remaining hp")
	assert_true(h.dead and died[0], "died emitted at 0")
	assert_almost(h.apply_damage(5.0), 0.0, 0.001, "no damage after death")


func test_find_health_property_and_child() -> void:
	var t: Node3D = _add(Target.new(), Vector3.ZERO)
	assert_eq(Combat.find_health(t), t.get("health"), "property lookup")
	var plain := Node3D.new()
	var h: Node = Health.new()
	h.name = "Health"
	plain.add_child(h)
	_add(plain, Vector3.ONE)
	assert_eq(Combat.find_health(plain), h, "child named Health")
	assert_null(Combat.find_health(Node3D.new()), "no health -> null")
	assert_null(Combat.find_health(null))


# --- Arc geometry -----------------------------------------------------------------------------------

func test_in_arc_geometry() -> void:
	var o := Vector3.ZERO
	var f := Vector3.FORWARD
	assert_true(Combat.in_arc(o, f, Vector3(0, 0.5, -2.0), 2.5, 90.0), "straight ahead in reach")
	assert_false(Combat.in_arc(o, f, Vector3(0, 0.5, -3.0), 2.5, 90.0), "too far")
	assert_false(Combat.in_arc(o, f, Vector3(0, 0.5, 2.0), 2.5, 90.0), "behind")
	assert_true(Combat.in_arc(o, f, Vector3(1.0, 0.5, -1.2), 2.5, 90.0), "~40 deg inside a 90 deg arc")
	assert_false(Combat.in_arc(o, f, Vector3(1.5, 0.5, -0.8), 2.5, 90.0), "~62 deg outside a 90 deg arc")
	assert_true(Combat.in_arc(o, f, Vector3(0.3, 0.5, 0.2), 2.5, 30.0), "overlapping targets always count")
	assert_false(Combat.in_arc(o, f, Vector3(0, 3.0, -1.0), 2.5, 90.0), "too high above (ceiling)")
	assert_true(Combat.in_arc(o, f, Vector3(1.5, 0.0, 1.5), 2.5, 360.0), "full circle")


# --- Melee ------------------------------------------------------------------------------------------------

func test_melee_hits_only_targets_in_front() -> void:
	var a := _attacker()
	var front: Node3D = _add(Target.new(), Vector3(0, 0, -1.6), "combat_test_target")
	var behind: Node3D = _add(Target.new(), Vector3(0, 0, 1.6), "combat_test_target")
	var far: Node3D = _add(Target.new(), Vector3(0, 0, -6.0), "combat_test_target")
	await wait_physics(2)
	var hits: Array = Combat.melee(a, Vector3(0, 1.0, 0), Vector3.FORWARD, 2.0, 100.0, 12.0, ["combat_test_target"], 4.0)
	assert_eq(hits.size(), 1, "exactly one hit")
	assert_true(hits.has(front), "the one in front")
	assert_almost(front.health.hp, 88.0, 0.01, "damage applied through health")
	assert_almost(behind.health.hp, 100.0, 0.01, "behind untouched")
	assert_almost(far.health.hp, 100.0, 0.01, "out of reach untouched")
	assert_eq(front.knocks.size(), 1, "knockback called")
	var kdir: Vector3 = front.knocks[0][0]
	assert_true(kdir.dot(Vector3.FORWARD) > 0.9, "knocked away from the attacker")
	assert_almost(float(front.knocks[0][1]), 4.0)


func test_melee_ignores_other_groups_and_self() -> void:
	var a: Node3D = _add(Target.new(), Vector3.ZERO, "combat_test_target")
	var companion: Node3D = _add(Target.new(), Vector3(0, 0, -1.2), "combat_test_friend")
	await wait_physics(2)
	var hits: Array = Combat.melee(a, Vector3(0, 1, 0), Vector3.FORWARD, 2.5, 360.0, 10.0, ["combat_test_target"], 0.0)
	assert_eq(hits.size(), 0, "attacker never hits itself, friends are not in the target group")
	assert_almost(companion.health.hp, 100.0)
	assert_almost(a.health.hp, 100.0)


func test_melee_blocked_by_wall() -> void:
	var a := _attacker()
	var t: Node3D = _add(Target.new(), Vector3(0, 0, -2.0), "combat_test_target")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.3)
	cs.shape = box
	wall.add_child(cs)
	_add(wall, Vector3(0, 1, -1.0))
	await wait_physics(3)
	var hits: Array = Combat.melee(a, Vector3(0, 1.0, 0), Vector3.FORWARD, 2.5, 90.0, 10.0, ["combat_test_target"], 0.0)
	assert_eq(hits.size(), 0, "no hits through walls")
	assert_almost(t.health.hp, 100.0)
	wall.queue_free()
	await wait_physics(3)
	hits = Combat.melee(a, Vector3(0, 1.0, 0), Vector3.FORWARD, 2.5, 90.0, 10.0, ["combat_test_target"], 0.0)
	assert_eq(hits.size(), 1, "hit once the wall is gone")


func test_melee_on_invulnerable_calls_blocked() -> void:
	var a := _attacker()
	var t: Node3D = _add(Target.new(), Vector3(0, 0, -1.5), "combat_test_target")
	t.health.invulnerable = true
	await wait_physics(2)
	var hits: Array = Combat.melee(a, Vector3(0, 1, 0), Vector3.FORWARD, 2.0, 90.0, 10.0, ["combat_test_target"], 3.0)
	assert_eq(hits.size(), 0, "invulnerable target is not a hit")
	assert_eq(t.blocked, 1, "on_hit_blocked notified (boss armour, stalker)")
	assert_eq(t.knocks.size(), 0, "no knockback on a blocked hit")


# --- Light --------------------------------------------------------------------------------------------------

func test_light_falloff_curve() -> void:
	assert_almost(Combat.light_falloff(0.0, 7.0), 1.0)
	assert_almost(Combat.light_falloff(7.0 * Combat.LIGHT_CORE, 7.0), 1.0, 0.001, "fully lit core")
	assert_almost(Combat.light_falloff(7.0, 7.0), 0.0, 0.001, "zero at the radius")
	assert_almost(Combat.light_falloff(9.0, 7.0), 0.0)
	var mid := Combat.light_falloff(5.0, 7.0)
	assert_true(mid > 0.3 and mid < 0.7, "fades between core and radius (%.2f)" % mid)
	assert_almost(Combat.light_falloff(1.0, 0.0), 0.0, 0.001, "no radius, no light")


func test_light_at_sources_active_and_combined() -> void:
	var s1: LightSrc = _add(LightSrc.new(), Vector3(0, 0, 0), "light_source")
	Combat.invalidate_light_cache()
	assert_almost(Combat.light_at(Vector3(0.5, 0, 0)), 1.0, 0.001, "next to a lit brazier")
	assert_almost(Combat.light_at(Vector3(20, 0, 0)), 0.0, 0.001, "far away is dark")
	s1.on = false
	Combat.invalidate_light_cache()
	assert_almost(Combat.light_at(Vector3(0.5, 0, 0)), 0.0, 0.001, "inactive sources give no light")
	s1.on = true
	var p := Vector3(5.5, 0, 0)
	var single := Combat.light_at(p)
	var s2: LightSrc = _add(LightSrc.new(), Vector3(11, 0, 0), "light_source")
	Combat.invalidate_light_cache()
	var both := Combat.light_at(p)
	assert_true(both > single, "two lights brighter than one (%.2f > %.2f)" % [both, single])
	assert_true(both <= 1.0, "clamped")
	s2.light_radius = 0.0
	Combat.invalidate_light_cache()
	assert_almost(Combat.light_at(p), single, 0.001)


func test_gloomling_exposure_threshold_matches_light() -> void:
	# A lit brazier (radius 7) exposes gloomlings (> 0.4) within ~5.4 m.
	_add(LightSrc.new(), Vector3.ZERO, "light_source")
	Combat.invalidate_light_cache()
	assert_true(Combat.light_at(Vector3(5.0, 0, 0)) > 0.4, "exposed at 5 m")
	assert_true(Combat.light_at(Vector3(6.0, 0, 0)) < 0.4, "safe in the gloom at 6 m")


# --- Intensity scaling --------------------------------------------------------------------------------------------

func test_damage_mult_by_intensity_and_area() -> void:
	assert_almost(Combat.intensity_damage_mult(0), 0.6, 0.001, "Gentle")
	assert_almost(Combat.intensity_damage_mult(1), 1.0, 0.001, "Standard")
	assert_almost(Combat.intensity_damage_mult(2), 1.15, 0.001, "Intense")
	assert_almost(Combat.intensity_damage_mult(9), 1.15, 0.001, "clamped")
	Settings.set_value("horror_intensity", 0)
	assert_almost(Combat.damage_mult_for_area("below"), 0.6, 0.001, "underground scales")
	assert_almost(Combat.damage_mult_for_area("surface"), 1.0, 0.001, "surface never scales")
	Settings.set_value("horror_intensity", 2)
	assert_almost(Combat.damage_mult_for_area("below"), 1.15, 0.001)


func test_truthy() -> void:
	assert_false(Combat.truthy(null))
	assert_false(Combat.truthy(false))
	assert_true(Combat.truthy(true))
	assert_true(Combat.truthy(1))
	assert_false(Combat.truthy("yes"), "strings are not flags")
