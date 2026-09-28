extends "res://tests/test_case.gd"
## Headless physics: a CharacterBody3D capsule with the player's settings (radius 0.32, height 1.6, floor
## angle 46 deg, snap 0.35) walks from the foot of real placed stairs up onto the upper-floor landing, and back
## down; a companion-like capsule (52 deg) does the same. The house is built through Placement.validate and
## BuildOps.place_structure exactly like build mode does, so the heights are the real ones.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _area: Node3D


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _make_area() -> void:
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(60, 1, 60)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)


func _ctx(level: int = 0) -> Dictionary:
	return {"structures": GameState.structures, "area_id": "surface", "build_area": Ops.build_area_for("surface"),
		"height_fn": _flat, "level": level}


## Validates then places (consumes the item) like build mode; fails the test if refused.
func _build(sid: String, pos: Vector3, rot: float, level: int = 0) -> String:
	var res := P.validate(sid, pos, rot, _ctx(level))
	assert_true(bool(res["ok"]), "%s at %s: %s" % [sid, str(pos), String(res["reason"])])
	GameState.give_item(sid, 1)
	return Ops.place_structure(_area, sid, Vector3(pos.x, float(res["y"]), pos.z), rot, int(res["level"]))


## Stairs rot 0 at x -6..-4, z 2..6 rising toward -Z onto an upper floor landing (x -6..-4, z 0..2) held up by
## walls, with a railing on the landing's open side. Clear of the Haven's keep-clear circles.
func _house() -> void:
	_build("wood_wall", Vector3(-5, 0, 0), 0)
	_build("wood_wall", Vector3(-6, 0, 1), 90)
	_build("wood_wall", Vector3(-4, 0, 1), 90)
	_build("wood_stairs", Vector3(-5, 0, 4), 0)
	_build("upper_floor", Vector3(-5, 0, 1), 0)
	_build("wood_railing", Vector3(-5, 0, 0), 0, 1)
	assert_true(P.has_reachable_upstairs(_ctx()), "the stairs reach the landing")


func _walker(max_angle_deg: float) -> CharacterBody3D:
	var s := GDScript.new()
	s.source_code = "extends CharacterBody3D\nvar dir := Vector3.ZERO\nvar speed := 3.0\n" \
		+ "func _physics_process(delta: float) -> void:\n" \
		+ "\tvelocity.x = dir.x * speed\n\tvelocity.z = dir.z * speed\n" \
		+ "\tif is_on_floor():\n\t\tvelocity.y = 0.0\n\telse:\n\t\tvelocity.y -= 9.8 * delta\n" \
		+ "\tmove_and_slide()\n"
	s.reload()
	var b: CharacterBody3D = s.new()
	b.collision_layer = 2
	b.collision_mask = 1 | 32
	b.floor_max_angle = deg_to_rad(max_angle_deg)
	b.floor_snap_length = 0.35
	b.floor_stop_on_slope = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	b.add_child(cs)
	_area.add_child(b)
	return b


## Walks `b` along `dir` until `done` holds or `max_frames` physics frames pass. Returns the frames used.
func _walk(b: CharacterBody3D, dir: Vector3, done: Callable, max_frames: int) -> int:
	b.set("dir", dir)
	var i := 0
	while i < max_frames and not bool(done.call(b)):
		await wait_physics(1)
		i += 1
	b.set("dir", Vector3.ZERO)
	await wait_physics(10)
	return i


func _climb(max_angle_deg: float, label: String) -> void:
	var b := _walker(max_angle_deg)
	b.global_position = Vector3(-5.0, 0.05, 7.2)
	await wait_physics(6)
	assert_true(b.is_on_floor(), label + " starts on the ground")
	var landing_top: float = P.LEVEL_HEIGHT + P.UPPER_TOP
	await _walk(b, Vector3(0, 0, -1), func(n: CharacterBody3D) -> bool: return n.global_position.z < 1.0, 360)
	var p := b.global_position
	assert_true(p.z < 1.4 and p.z > 0.2, "%s reached the landing tile (z %.2f)" % [label, p.z])
	assert_almost(p.y, landing_top, 0.12, label + " stands on the upper floor")
	assert_true(b.is_on_floor(), label + " is on the floor up there")
	# ...and back down to the ground.
	await _walk(b, Vector3(0, 0, 1), func(n: CharacterBody3D) -> bool: return n.global_position.z > 7.0, 360)
	assert_almost(b.global_position.y, 0.0, 0.12, label + " walked back down")
	b.queue_free()


func test_krystal_walks_up_the_stairs_onto_the_landing() -> void:
	_make_area()
	_house()
	await wait_physics(3)
	await _climb(46.0, "Krystal")


func test_a_companion_walks_up_the_stairs_too() -> void:
	_make_area()
	_house()
	await wait_physics(3)
	await _climb(52.0, "companion")


func test_the_landing_edge_and_railing_hold_her_upstairs() -> void:
	_make_area()
	_house()
	await wait_physics(3)
	var b := _walker(46.0)
	b.global_position = Vector3(-5.0, P.LEVEL_HEIGHT + P.UPPER_TOP + 0.05, 1.0)
	await wait_physics(6)
	assert_true(b.is_on_floor(), "stands on the landing")
	await _walk(b, Vector3(0, 0, -1), func(n: CharacterBody3D) -> bool: return n.global_position.z < -0.5, 90)
	assert_true(b.global_position.z > -0.2, "the railing stops her at the landing's edge")
	assert_almost(b.global_position.y, P.LEVEL_HEIGHT + P.UPPER_TOP, 0.12, "still upstairs")
	b.queue_free()
