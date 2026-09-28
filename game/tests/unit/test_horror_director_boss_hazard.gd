extends "res://tests/test_case.gd"
## R71 (integration): the horror director's threat scan skips boss floor hazards (meta "boss_hazard":
## egg sacs, trip lines...). They sit in group "enemy" only so Krystal can strike them; they are neither
## a threat hunting her nor a room's own encounter.

const Director := preload("res://src/horror/director.gd")
const AreaBase := preload("res://src/world/area_base.gd")

const ENEMY_SRC := "extends Node3D\nvar hunting := false\nfunc is_threatening() -> bool:\n\treturn hunting\n"

var root: Node3D
var area: Node3D
var player: Node3D


func before_each() -> void:
	root = Node3D.new()
	root.name = "HazardScanRoot"
	add_child(root)
	area = AreaBase.new()
	area.name = "TestArea"
	area.add_zone("mine", Vector3.ZERO, 60.0, false)
	root.add_child(area)
	player = Node3D.new()
	player.name = "FakePlayer"
	player.add_to_group("player")
	area.add_child(player)
	await wait_frames(1)


func after_each() -> void:
	if is_instance_valid(root):
		root.queue_free()
	await wait_frames(2)


func _enemy(pos: Vector3, hunting: bool, hazard: bool) -> Node3D:
	var gs := GDScript.new()
	gs.source_code = ENEMY_SRC
	gs.reload()
	var e: Node3D = gs.new()
	e.set("hunting", hunting)
	e.add_to_group("enemy")
	if hazard:
		e.set_meta("boss_hazard", true)
	area.add_child(e)
	e.position = pos
	return e


func _director() -> Node:
	var d: Node = Director.new()
	d.setup({"area": area, "seed": 3})
	area.add_child(d)
	return d


func test_boss_hazards_are_not_threats_or_room_enemies() -> void:
	var sac := _enemy(Vector3(0, 0, -6), false, true)
	var line := _enemy(Vector3(3, 0, -4), true, true)      # even one that claimed to hunt is ignored
	var d := _director()
	var ctx: Dictionary = d.build_context(1.0)
	assert_eq(int(ctx["threats_nearby"]), 0, "hazards never count as threats")
	assert_eq(int(ctx["enemies_nearby"]), 0, "hazards are not a room's own encounter (ambush pile-on rule)")
	# A real idle enemy and a real hunting enemy next to them are still seen.
	var idle := _enemy(Vector3(-4, 0, -8), false, false)
	ctx = d.build_context(1.0)
	assert_eq(int(ctx["enemies_nearby"]), 1, "real idle enemy still counted")
	idle.set("hunting", true)
	ctx = d.build_context(1.0)
	assert_eq(int(ctx["threats_nearby"]), 1, "real hunting enemy still a threat")
	assert_eq(int(ctx["enemies_nearby"]), 0)
	# Meta set to false = an ordinary enemy again.
	sac.set_meta("boss_hazard", false)
	ctx = d.build_context(1.0)
	assert_eq(int(ctx["enemies_nearby"]), 1, "boss_hazard=false is not skipped")
	assert_true(is_instance_valid(line))
