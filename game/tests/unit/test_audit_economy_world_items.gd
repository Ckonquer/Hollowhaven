extends "res://tests/test_case.gd"
## AUDIT (surface economy & world): world items with a full backpack. REGRESSION (fixed in companion.gd):
## Mochi (forager, following) used to gather berries/fiber every 25-40 s without checking backpack space,
## so a full backpack turned every forage into a new PERSISTENT pickup (GameState.dropped, saved forever)
## plus a "Backpack full!" toast & sound - an endless trickle. Now she skips foraging when nothing fits.

const CompanionScript := preload("res://src/companions/companion.gd")

var _floor: StaticBody3D
var _player: CharacterBody3D
var _nodes: Array = []
var _saved_area_id := ""


class FakePlayer extends CharacterBody3D:
	func _ready() -> void:
		add_to_group("player")
		collision_layer = 2
		collision_mask = 1 | 32

	func is_sprinting() -> bool:
		return false

	func get_facing() -> Vector3:
		return Vector3(0, 0, -1)


class FakeBush extends Node3D:
	func _ready() -> void:
		add_to_group("harvestable")

	func get_harvest_info() -> Dictionary:
		return {"tool": "hand", "name": "Berry Bush", "kind": "bush"}


func before_each() -> void:
	fresh_state()
	_saved_area_id = Game.area_id
	Game.area_id = ""
	_floor = StaticBody3D.new()
	_floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	_floor.add_child(cs)
	add_child(_floor)
	_player = FakePlayer.new()
	add_child(_player)
	_player.global_position = Vector3(0, 0.05, 6)
	Game.player = _player
	await wait_physics(2)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for n in get_tree().get_nodes_in_group("world_item"):
		n.queue_free()
	Game.player = null
	Game.companion_nodes = {}
	Game.area_id = _saved_area_id
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_floor):
		_floor.queue_free()
	await wait_frames(2)


func test_mochi_forage_with_full_backpack_leaves_no_drops() -> void:
	for i in GameState.INVENTORY_SIZE:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})
	assert_eq(GameState.inventory.space_for("berries"), 0, "backpack is full")
	var m: Node3D = CompanionScript.new()
	m.setup({"id": "mochi", "mode": "follow", "home": Vector3(0, 0.05, 10), "wild": Vector3(0, 0.05, 4)})
	add_child(m)
	m.global_position = Vector3(0, 0.05, 4)
	_nodes.append(m)
	Game.companion_nodes["mochi"] = m
	GameState.companion("mochi")["befriended"] = true
	GameState.set_companion_assignment("mochi", "follow")
	var bush := FakeBush.new()
	add_child(bush)
	_nodes.append(bush)
	bush.global_position = Vector3(1.5, 0.0, 4.5)
	var toasts: Array = []
	var cb := func(text: String, _kind: String) -> void: toasts.append(text)
	Events.notify.connect(cb)
	await wait_physics(2)
	var rounds := 3
	for r in rounds:
		m.set("_ability_t", 0.0)
		await wait_physics(2)
		await wait_seconds(3.0)
	Events.notify.disconnect(cb)
	var full_toasts := toasts.filter(func(t): return String(t).begins_with("Backpack full"))
	print("    after %d forages with a full backpack: %d persistent drops in GameState.dropped, %d 'Backpack full' toasts %s" % [
		rounds, GameState.dropped.size(), full_toasts.size(), str(full_toasts)])
	assert_eq(GameState.dropped.size(), 0, "Mochi does not keep producing persistent pickups when the backpack is full")
	assert_eq(full_toasts.size(), 0, "and no 'Backpack full!' toasts")
