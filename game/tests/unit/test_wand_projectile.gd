extends "res://tests/test_case.gd"
## Shared pooled projectile (src/combat/projectile.gd, spec section 9): hits the first target of its groups,
## stops at world / structures (LOS), finite range, per-shooter and global caps, pooling, can_be_hit_by /
## on_hit_blocked, knockback, and the player's damage path (armor) when enemies throw at Krystal.

const Projectile := preload("res://src/combat/projectile.gd")
const HealthScript := preload("res://src/combat/health.gd")
const PlayerHealth := preload("res://src/player/player_health.gd")
const Combat := preload("res://src/combat/combat.gd")

var _hits: Array = []


func before_each() -> void:
	fresh_state()
	Projectile.stop_all()
	_hits = []


func after_each() -> void:
	Projectile.stop_all()
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


## A target in `group` with 30 hp at `pos` (no collider: bosses and test fakes have none).
class Target extends Node3D:
	var health: Node
	var blocked: int = 0
	var knocked: float = 0.0
	var refuse: bool = false
	var hit_radius: float = 0.45

	func _ready() -> void:
		health = load("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 30.0
		add_child(health)

	func can_be_hit_by(_src: Node) -> bool:
		return not refuse

	func on_hit_blocked(_a: Node, _d: Vector3) -> void:
		blocked += 1

	func knockback(_d: Vector3, f: float) -> void:
		knocked = f


func _target(pos: Vector3, group: String = "enemy") -> Target:
	var t := Target.new()
	add_child(t)
	t.add_to_group(group)
	t.global_position = pos
	Projectile.invalidate_targets()
	return t


func _wall(pos: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b


func _record(t: Node, dealt: float) -> void:
	_hits.append([t, dealt])


func _fire(extra: Dictionary) -> Node3D:
	var p := {"shooter": self_node(), "from": Vector3(0, 0.8, 0), "dir": Vector3(0, 0, -1), "damage": 9.0,
		"speed": 16.0, "range": 14.0, "groups": ["enemy"], "parent": self, "on_hit": _record}
	p.merge(extra, true)
	return Projectile.fire(p)


var _shooter: Node3D = null


func self_node() -> Node3D:
	if _shooter == null or not is_instance_valid(_shooter):
		_shooter = Node3D.new()
		add_child(_shooter)
	return _shooter


func test_segment_distance_math() -> void:
	var d := Projectile.segment_distance(Vector3(0, 0, 0), Vector3(0, 0, -10), Vector3(1, -1, -5), Vector3(1, 1, -5))
	assert_almost(d.x, 1.0, 0.0001, "1 m apart")
	assert_almost(d.y, 0.5, 0.0001, "closest halfway along the flight")
	d = Projectile.segment_distance(Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, -3), Vector3(0, 1, -3))
	assert_almost(d.x, 4.0, 0.0001, "beyond the end: 2 m (squared 4)")
	assert_almost(d.y, 1.0, 0.0001)


func test_hits_the_target_once_and_reports_it() -> void:
	var t := _target(Vector3(0, 0, -6))
	var p := _fire({"knockback": 1.5})
	assert_not_null(p, "fired")
	assert_eq(Projectile.live_count(), 1)
	await wait_physics(30)
	assert_almost(float(t.health.hp), 21.0, 0.001, "9 damage, once")
	assert_eq(String(p.result), "hit")
	assert_eq(_hits.size(), 1, "on_hit called once")
	assert_almost(float(_hits[0][1]), 9.0, 0.001)
	assert_almost(t.knocked, 1.5, 0.001, "knockback applied")
	assert_eq(Projectile.live_count(), 0, "finished")


func test_world_and_structures_block_it() -> void:
	var t := _target(Vector3(0, 0, -8))
	_wall(Vector3(0, 1, -4), Vector3(4, 3, 0.4), 1)
	var p := _fire({})
	await wait_physics(40)
	assert_almost(float(t.health.hp), 30.0, 0.001, "never through a wall")
	assert_eq(String(p.result), "wall")
	assert_true(p.global_position.z > -4.3, "stopped at the wall (%s)" % str(p.global_position))
	var t2 := _target(Vector3(6, 0, -8))
	_wall(Vector3(6, 1, -4), Vector3(4, 3, 0.4), 32)
	var p2 := _fire({"from": Vector3(6, 0.8, 0)})
	await wait_physics(40)
	assert_almost(float(t2.health.hp), 30.0, 0.001, "structures block too")
	assert_eq(String(p2.result), "wall")


func test_finite_range() -> void:
	var t := _target(Vector3(0, 0, -20))
	var p := _fire({"range": 14.0})
	await wait_physics(80)
	assert_almost(float(t.health.hp), 30.0, 0.001, "out of range")
	assert_eq(String(p.result), "expired")
	assert_true(float(p.travelled) <= 14.01, "flew %.2f m" % float(p.travelled))


func test_only_its_target_groups() -> void:
	var friend := _target(Vector3(0, 0, -4), "companion")
	var foe := _target(Vector3(0, 0, -8), "enemy")
	_fire({})
	await wait_physics(50)
	assert_almost(float(friend.health.hp), 30.0, 0.001, "companions are never targets")
	assert_almost(float(foe.health.hp), 21.0, 0.001, "flies on to the enemy")


func test_can_be_hit_by_is_respected() -> void:
	var t := _target(Vector3(0, 0, -5))
	t.refuse = true
	var p := _fire({})
	await wait_physics(30)
	assert_almost(float(t.health.hp), 30.0, 0.001, "a refusing target (boss overhead) takes nothing")
	assert_eq(t.blocked, 1, "on_hit_blocked called")
	assert_eq(String(p.result), "blocked")
	assert_almost(float(_hits[0][1]), 0.0, 0.001, "reported as dealt 0 (no xp for invulnerable targets)")


func test_caps_and_pool() -> void:
	var a := _fire({"max_per_shooter": 3})
	var b := _fire({"max_per_shooter": 3})
	var c := _fire({"max_per_shooter": 3})
	var d := _fire({"max_per_shooter": 3})
	assert_not_null(a)
	assert_not_null(b)
	assert_not_null(c)
	assert_null(d, "a fourth spark from the same shooter is refused")
	assert_eq(Projectile.live_count(self_node()), 3)
	var others: Array = []
	for i in Projectile.MAX_LIVE + 5:
		var o := Node3D.new()
		add_child(o)
		var p := Projectile.fire({"shooter": o, "from": Vector3(0, 30, 0), "dir": Vector3.UP, "damage": 1.0, "parent": self})
		if p != null:
			others.append(p)
	assert_eq(Projectile.live_count(), Projectile.MAX_LIVE, "global cap")
	Projectile.stop_all()
	assert_eq(Projectile.live_count(), 0)
	var pooled := Projectile.pool_size()
	assert_true(pooled > 0 and pooled <= Projectile.POOL_MAX, "finished sparks are pooled (%d)" % pooled)
	var again := _fire({})
	assert_true(others.has(again) or again == a or again == b or again == c, "a pooled projectile is reused")
	assert_eq(Projectile.pool_size(), pooled - 1)


func test_enemy_throw_goes_through_the_player_damage_path() -> void:
	var fake := Node3D.new()
	add_child(fake)
	fake.add_to_group("player")
	var h: Node = PlayerHealth.new()
	h.name = "Health"
	fake.add_child(h)
	fake.global_position = Vector3(0, 0, -6)
	Projectile.invalidate_targets()
	for id in ["ironwood_helm", "ironwood_mail", "ironwood_boots"]:
		GameState.give_item(id, 1)
		GameState.equip(id)
	var p := _fire({"groups": ["player"], "damage": 20.0})
	await wait_physics(30)
	assert_almost(float(h.hp), 84.0, 0.001, "20 x (1 - 20% armor)")
	assert_eq(String(p.result), "hit")
	h.grant_iframes(1.0)
	var p2 := _fire({"groups": ["player"], "damage": 20.0})
	await wait_physics(30)
	assert_almost(float(h.hp), 84.0, 0.001, "dodge / hurt i-frames make it harmless")
	assert_eq(String(p2.result), "blocked")


## Review fix: the projectile skips its own shooter by instance id, so a shooter standing in its own target
## group is never hit, and a shooter freed mid-flight (an enemy defeated while its orb flies) is never touched.
func test_shooter_freed_mid_flight_and_never_hits_itself() -> void:
	var shooter := _target(Vector3(0, 0, 0))
	var t := _target(Vector3(0, 0, -8))
	var p := Projectile.fire({"shooter": shooter, "from": Vector3(0, 0.8, 0), "dir": Vector3(0, 0, -1), "damage": 9.0,
		"speed": 16.0, "range": 14.0, "groups": ["enemy"], "parent": self})
	assert_not_null(p, "fired")
	p.step(1.0 / 60.0)
	assert_almost(float(shooter.health.hp), 30.0, 0.001, "never hits its own shooter, even at point blank")
	shooter.free()
	await wait_physics(40)
	assert_almost(float(t.health.hp), 21.0, 0.001, "still lands after its shooter is gone")
	assert_eq(String(p.result), "hit")


## Review addition: Combat.melee honours can_be_hit_by exactly like the projectile (refused = blocked: no
## damage, no knockback, on_hit_blocked), and hits normally once the target accepts hits again.
func test_melee_respects_can_be_hit_by_too() -> void:
	var t := _target(Vector3(0, 0, -1.5))
	t.refuse = true
	var a := self_node()
	a.global_position = Vector3.ZERO
	var hits: Array = Combat.melee(a, Vector3(0, 0.8, 0), Vector3(0, 0, -1), 2.5, 110.0, 18.0, ["enemy"], 4.0)
	assert_eq(hits.size(), 0, "refused")
	assert_almost(float(t.health.hp), 30.0, 0.001, "no damage while it refuses hits")
	assert_eq(t.blocked, 1, "on_hit_blocked called")
	assert_almost(t.knocked, 0.0, 0.001, "no knockback")
	t.refuse = false
	hits = Combat.melee(a, Vector3(0, 0.8, 0), Vector3(0, 0, -1), 2.5, 110.0, 18.0, ["enemy"], 4.0)
	assert_eq(hits.size(), 1, "accepted again")
	assert_almost(float(t.health.hp), 12.0, 0.001, "one 18-damage hit")
	assert_almost(t.knocked, 4.0, 0.001)
