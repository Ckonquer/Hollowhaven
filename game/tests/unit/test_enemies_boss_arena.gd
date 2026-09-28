extends "res://tests/test_case.gd"
## The Weaver Matron in the REAL Heartseed Chamber (below_world.gd): a scorched fall never lands on or
## inside the Heartseed cocoon at the arena centre, so the stun window it opens can always be used.
## (The centre anchor sits 1.0 m from the cocoon, and some ceiling routes pass right over it.)
## Headless, manual ticks, no saves written.

const Boss := preload("res://src/enemies/weaver_boss.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const PlayerLogic := preload("res://src/player/player_logic.gd")
const WORLD := "res://src/world/below/below_world.gd"

const DT := 0.05
const COCOON_R := 0.95                  # heartseed_cocoon.gd StaticBody radius

var _nodes: Array = []
var area: Node3D = null
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_mode: String = ""
var _saved_area_id: String = ""
var _saved_companions: Dictionary = {}
var _saved_director: Node = null


class Dummy extends CharacterBody3D:
	var health: Node

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


## Records every director.suppress(seconds) call the chamber makes.
class DirectorStub extends Node:
	var calls: Array = []

	func suppress(seconds: float, _replace: bool = false) -> void:
		calls.append(seconds)


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_mode = Game.mode
	_saved_area_id = Game.area_id
	_saved_companions = Game.companion_nodes
	_saved_director = Game.director
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Game.area = _saved_area
	Game.player = _saved_player
	Game.mode = _saved_mode
	Game.area_id = _saved_area_id
	Game.companion_nodes = _saved_companions
	Game.director = _saved_director
	Combat.invalidate_light_cache()
	await wait_frames(2)


func _dummy(pos: Vector3, parent: Node) -> Node3D:
	var d := Dummy.new()
	parent.add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


func _tick_until(n: Node, s: String, max_t: float) -> void:
	var t := 0.0
	while String(n.get("state")) != s and t < max_t:
		n.call("tick", DT)
		t += DT


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A Copper Sword swing exactly like player.gd _melee_hit() (18 dmg, reach 2.5).
func _swing(attacker: Node3D, facing: Vector3) -> Array:
	return Combat.melee(attacker, attacker.global_position + Vector3.UP * 0.9, facing, 2.5, PlayerLogic.MELEE_ARC, 18.0, ["enemy"], 4.0)


func _arena_boss() -> Node:
	area = load(WORLD).new()
	add_child(area)
	await wait_physics(3)
	var boss: Node = area.get("boss")
	if boss != null:
		boss.set_process(false)
		boss.intensity_override = 1
	return boss


## Clinging at the centre anchor (the one nearest Krystal when she fights beside the cocoon), it is
## scorched by the south-east brazier mid-telegraph. It must land clear of the cocoon, and walking
## straight back from the brazier she just lit must reach it.
func test_scorched_from_the_centre_anchor_lands_clear_of_the_cocoon() -> void:
	var boss: Node = await _arena_boss()
	assert_not_null(boss, "the real Below builds its boss")
	if boss == null:
		return
	var c := Layout.ARENA_CENTER
	var brs: Array = area.get("braziers")
	var bz: Vector3 = (brs[0] as Node3D).global_position
	var target := _dummy(Vector3(105.0, -12.0, -135.5), area)     # Krystal fighting beside the cocoon
	boss.target_override = target
	boss.call("_enter_cling", 0.1)
	boss.call("_begin_reposition")
	_tick_until(boss, "cling", 6.0)
	var a3: Vector3 = Layout.ARENA_ANCHORS[3]
	assert_true((boss.get("_anchor") as Vector3).distance_to(a3) < 0.1, "precondition: it clings to the centre anchor")
	target.global_position = bz + (Vector3(c.x, bz.y, c.z) - bz).normalized() * 1.2   # now kindling the SE brazier
	boss.call("_begin_telegraph")
	(brs[0] as Node).call("light")
	assert_eq(String(boss.state), "scorch_fall", "the kindle completes mid-telegraph")
	var fall_to: Transform3D = boss.get("_to")
	assert_almost(fall_to.origin.y, c.y, 0.05, "it falls to the floor")
	_tick_until(boss, "scorched", 2.0)
	assert_eq(String(boss.state), "scorched")
	var bp: Vector3 = (boss as Node3D).global_position
	assert_true(_flat(bp, c) >= Boss.CENTRE_CLEARANCE - 0.01, "lands at least CENTRE_CLEARANCE from the cocoon (%.2f m)" % _flat(bp, c))
	assert_true(_flat(bp, bz) >= Boss.BRAZIER_CLEARANCE - 0.01, "and clear of the brazier (%.2f m)" % _flat(bp, bz))
	assert_almost(bp.y, c.y, 0.05, "standing on the floor")
	var aim: Vector3 = boss.get_aim_point()
	var space := (boss as Node3D).get_world_3d().direct_space_state
	var dir := Vector3(aim.x - bz.x, 0.0, aim.z - bz.z).normalized()
	var blocked: Array = []
	for i in 5:
		var dist := 2.0 + 0.5 * float(i)          # 2.0 .. 4.0 m: inside sword reach + its body radius
		var pos := Vector3(aim.x, c.y, aim.z) - dir * dist
		if not Combat.has_line_of_sight(space, pos + Vector3.UP * 0.9, aim, []):
			blocked.append(dist)
	assert_eq(blocked.size(), 0, "nothing blocks the straight approach from the lit brazier (blocked at %s m)" % str(blocked))
	var hp0: float = boss.health.hp
	var att := _dummy(Vector3(aim.x, c.y, aim.z) - dir * 2.5, area)
	var hits: Array = _swing(att, dir)
	assert_true(hits.size() > 0 and float(boss.health.hp) < hp0, "a sword swing from that side lands (hp %.0f -> %.0f)" % [hp0, float(boss.health.hp)])


## Scorched halfway along a ceiling route that passes right over the cocoon (A1 -> A4 passes 0.47 m
## from the centre): the fall must aim at the floor beside it, never the cocoon's top, and it must
## never end up standing inside the cocoon's collider.
func test_scorched_over_the_cocoon_lands_on_the_floor_beside_it() -> void:
	var boss: Node = await _arena_boss()
	assert_not_null(boss, "the real Below builds its boss")
	if boss == null:
		return
	var c := Layout.ARENA_CENTER
	var brs: Array = area.get("braziers")
	var target := _dummy(Vector3(105.0, -12.0, -135.5), area)
	boss.target_override = target
	var a1: Vector3 = Layout.ARENA_ANCHORS[1]
	boss.set("_anchor", a1)
	(boss as Node3D).global_transform = boss.call("_ceiling_pose", a1, target.global_position)
	boss.call("_enter_cling", 0.1)
	target.global_position = Vector3(110.0, -12.0, -141.0)        # Krystal runs to the south-east
	boss.call("_begin_reposition")
	assert_eq(String(boss.state), "reposition")
	boss.tick(float(boss.get("_state_len")) * 0.5)                 # halfway along the ceiling
	assert_true(_flat((boss as Node3D).global_position, c) < COCOON_R, "precondition: right above the cocoon (%.2f m)" % _flat((boss as Node3D).global_position, c))
	(brs[2] as Node).call("light")                                 # the north brazier
	assert_eq(String(boss.state), "scorch_fall")
	var fall_to: Transform3D = boss.get("_to")
	assert_almost(fall_to.origin.y, c.y, 0.05, "the fall aims at the floor, not the cocoon's top (aims at y %.2f)" % fall_to.origin.y)
	_tick_until(boss, "scorched", 2.0)
	assert_eq(String(boss.state), "scorched")
	var bp: Vector3 = (boss as Node3D).global_position
	assert_true(_flat(bp, c) >= Boss.CENTRE_CLEARANCE - 0.01, "lands clear of the cocoon (%.2f m from the centre)" % _flat(bp, c))
	assert_almost(bp.y, c.y, 0.05, "on the floor (y %.2f)" % bp.y)
	var out := Vector3(bp.x - c.x, 0.0, bp.z - c.z).normalized()
	var att := _dummy(Vector3(bp.x, c.y, bp.z) + out * 2.5, area)
	var hp0: float = boss.health.hp
	var hits: Array = _swing(att, -out)
	assert_true(hits.size() > 0 and float(boss.health.hp) < hp0, "the stunned boss can be hit (hp %.0f -> %.0f)" % [hp0, float(boss.health.hp)])


## Chapter Two rework (module B9): the fixed trip-line posts, egg-sac spots and trip-lines in the REAL
## chamber are fair - inside the walls, clear of the braziers, the cocoon and the entrance ramp, standing
## on floor, and every brazier + the entrance stays reachable whatever lines are stretched near Krystal.
func test_real_arena_hazard_anchors_and_lines_are_fair() -> void:
	var boss: Node = await _arena_boss()
	assert_not_null(boss, "the real Below builds its boss")
	if boss == null:
		return
	var field: Node = boss.get("field")
	assert_not_null(field, "the hazard field exists")
	var c := Layout.ARENA_CENTER
	var room: Dictionary = Layout.ROOMS["arena"]
	var space := (boss as Node3D).get_world_3d().direct_space_state
	var brs: Array = area.get("braziers")
	var entrance: Vector3 = field.get("entrance")
	assert_true(bool(field.get("has_entrance")), "below_world passes the arena mouth")
	for p in field.get("posts"):
		var pv: Vector3 = p
		assert_true(pv.x > float(room["x0"]) + 1.5 and pv.x < float(room["x1"]) - 1.5 and pv.z > float(room["z0"]) + 1.5 and pv.z < float(room["z1"]) - 1.5, "post %s well inside the walls" % str(pv))
		assert_true(_flat(pv, c) >= 2.5, "post clear of the cocoon")
		for b in brs:
			assert_true(_flat(pv, (b as Node3D).global_position) >= 2.5, "post clear of every brazier")
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pv + Vector3.UP * 2.0, pv + Vector3.DOWN * 2.0, 1))
		assert_false(hit.is_empty(), "post %s stands on floor" % str(pv))
	var target := _dummy(Vector3(105.0, -12.0, -131.0), area)
	for sp in field.sac_spots(target.global_position, 2):
		var sv: Vector3 = sp
		assert_true(sv.x > float(room["x0"]) + 0.8 and sv.x < float(room["x1"]) - 0.8 and sv.z > float(room["z0"]) + 0.8 and sv.z < float(room["z1"]) - 0.8, "sac spot %s inside the walls" % str(sv))
		assert_true(_flat(sv, entrance) >= 4.0, "no sac at the entrance")
	var circles: Array = []
	for o in field.get("obstacles"):
		circles.append(o)
	var checked := 0
	for x in [98.0, 101.0, 105.0, 109.0, 112.0]:
		for z in [-144.0, -140.0, -135.0, -131.0]:
			var p := Vector3(x, c.y, z)
			if _flat(p, c) < 2.0 or _flat(p, c) > 9.5:
				continue
			field.call("clear_all", false)
			field.call("begin_trips", 2, 1.2, p)
			var segs: Array = field.call("active_segments")
			for b in brs:
				assert_true(field.route_exists(p, (b as Node3D).global_position, c, float(boss.get("arena_radius")), segs, circles), "brazier reachable from %s" % str(p))
			assert_true(field.route_exists(p, entrance, c, float(boss.get("arena_radius")), segs, circles), "entrance reachable from %s" % str(p))
			checked += 1
	assert_true(checked >= 10, "sampled %d spots" % checked)
	field.call("clear_all", false)


## MP section 14 (module B9): the random director is held for the whole encounter even when the Matron
## wakes on her own - Krystal coming down the entrance ramp is inside its engage radius before the room
## tracker counts her as "in the arena" - and the hold is released to a normal quiet period when the
## encounter stands down because she walked back out through the antechamber.
func test_director_hold_follows_the_encounter_even_when_she_wakes_on_her_own() -> void:
	var stub := DirectorStub.new()
	add_child(stub)
	_nodes.append(stub)
	Game.director = stub
	Game.mode = "playing"
	var boss: Node = await _arena_boss()
	assert_not_null(boss, "the real Below builds its boss")
	if boss == null:
		return
	var ramp := Vector3(105.0, -11.6, -124.0)
	assert_eq(Layout.room_at(ramp + Vector3.UP * 0.3), "arena_way", "precondition: on the entrance ramp, not yet in the arena room")
	assert_true(_flat(ramp, Layout.ARENA_CENTER) <= float(boss.get("arena_radius")) + Boss.ENGAGE_MARGIN, "precondition: inside the engage radius")
	var d := _dummy(ramp, area)
	boss.target_override = d
	assert_false(bool(area.get("fight_active")))
	_tick_until(boss, "intro", 1.0)
	assert_true(bool(boss.get("fight_started")), "she wakes as Krystal comes down the ramp")
	assert_true(bool(area.get("fight_active")), "the chamber takes its fight hold at once")
	assert_true(stub.calls.size() > 0 and float(stub.calls.back()) >= 600.0, "the director is held for the fight (%s)" % str(stub.calls))
	var n_calls := stub.calls.size()
	area.call("on_room_changed", "arena_way", "arena")
	assert_eq(stub.calls.size(), n_calls, "walking on into the arena does not start a second hold")
	d.global_position = Vector3(105.0, -10.0, -112.0)          # back up through the antechamber
	_tick_until(boss, "dormant", 12.0)
	assert_eq(String(boss.get("state")), "dormant", "the encounter stood down")
	assert_false(bool(area.get("fight_active")), "the fight hold is released")
	assert_true(stub.calls.size() > n_calls and float(stub.calls.back()) < 600.0, "a normal quiet period follows (%s)" % str(stub.calls))
	assert_false(bool(GameState.get_flag("weaver_defeated")), "no progress flag touched")
