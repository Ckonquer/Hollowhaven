extends "res://tests/test_case.gd"
## Shared fixture for the Chapter Two companion suites (test_companions_combat / _skills / _nav / _courage /
## _areas / _home / _ui): a floor, a fake Krystal with a real Health (and a shield recorder), fake enemies
## that follow the combat conventions, and helpers. Holds no tests itself.

const CompanionScript := preload("res://src/companions/companion.gd")
const Spawner := preload("res://src/companions/companion_spawner.gd")
const Logic := preload("res://src/companions/companion_logic.gd")
const Support := preload("res://src/companions/companion_support.gd")
const CombatCtl := preload("res://src/companions/companion_combat.gd")
const Nav := preload("res://src/companions/companion_nav.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const HealthScript := preload("res://src/combat/health.gd")

var nodes: Array = []
var said: Array = []
var _say_cb: Callable
var _floor: StaticBody3D
var player: CharacterBody3D
var _saved := {}
var _saved_settings := {}


class FakePlayer extends CharacterBody3D:
	var health: Node
	var sprinting := false
	var shields: Array = []          # [amount, seconds, source] per add_shield call
	var with_shield_api := true

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)

	func _ready() -> void:
		add_to_group("player")
		collision_layer = 2
		collision_mask = 1 | 32

	func is_sprinting() -> bool:
		return sprinting

	func get_facing() -> Vector3:
		return Vector3(0, 0, -1)


## Krystal with the Chapter Two shield API on the player node (spec §9 `Game.player.add_shield`).
class ShieldPlayer extends FakePlayer:
	func add_shield(amount: float, seconds: float, source: String) -> float:
		shields.append([amount, seconds, source])
		return amount


## An enemy that follows the combat conventions (health child, is_threatening, stun, data, can_be_hit_by).
class FakeEnemy extends Node3D:
	var health: Node
	var threatening := true
	var refuse := false
	var data: Dictionary = {}
	var state := "chase"
	var stuns: Array = []
	var blocked: int = 0
	var damage_times: Array = []     # msec of every damaging hit

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 60.0
		add_child(health)
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damage_times.append(Time.get_ticks_msec()))

	func _ready() -> void:
		add_to_group("enemy")

	func is_threatening() -> bool:
		return threatening and not health.dead

	func can_be_hit_by(_source: Node) -> bool:
		return not refuse

	func stun(seconds: float) -> void:
		stuns.append(seconds)

	func on_hit_blocked(_a: Node, _d: Vector3) -> void:
		blocked += 1


func before_each() -> void:
	fresh_state()
	CompanionScript._last_any_say_ms = -100000     # the shared "someone spoke" throttle from earlier tests
	said = []
	_say_cb = func(speaker: String, text: String, _d: float) -> void: said.append([speaker, text])
	Events.say.connect(_say_cb)
	_saved = {"area_id": Game.area_id, "player": Game.player, "mode": Game.mode, "area": Game.area,
		"companions": Game.companion_nodes}
	for k in ["companion_auto_attack", "companion_autocast", "reduce_flashing", "arachnophobia"]:
		_saved_settings[k] = Settings.get_value(k)
	Settings.set_value("companion_auto_attack", true)
	Settings.set_value("companion_autocast", true)
	Game.area_id = ""
	Game.area = null
	Game.companion_nodes = {}
	_floor = _box_body(Vector3(160, 1, 160), Vector3(0, -0.5, 0))
	player = _make_player(ShieldPlayer.new())
	await wait_physics(2)


func after_each() -> void:
	if Events.say.is_connected(_say_cb):
		Events.say.disconnect(_say_cb)
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	Game.player = _saved.get("player")
	Game.companion_nodes = _saved.get("companions", {})
	Game.area_id = String(_saved.get("area_id", ""))
	Game.area = _saved.get("area")
	Game.mode = String(_saved.get("mode", Game.mode))
	for k in _saved_settings:
		Settings.set_value(k, _saved_settings[k])
	get_tree().paused = false
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(_floor):
		_floor.queue_free()
	await wait_frames(2)


func _make_player(p: CharacterBody3D) -> CharacterBody3D:
	add_child(p)
	p.global_position = Vector3(0, 0.05, 6)
	Game.player = p
	return p


func _box_body(size: Vector3, pos: Vector3, layer: int = 1) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	if b != _floor:
		nodes.append(b)
	return b


## A wall (world layer) between two points: `size` x 3 m high x 0.4 m thick, centred at `center`.
func _wall(center: Vector3, width: float, along_x: bool = true) -> StaticBody3D:
	var size := Vector3(width, 3.0, 0.4) if along_x else Vector3(0.4, 3.0, width)
	return _box_body(size, center + Vector3(0, 1.5, 0))


func _make(id: String, mode: String, pos: Vector3, extra: Dictionary = {}) -> Node3D:
	var params := {"id": id, "mode": mode, "home": Vector3(0, 0.05, 10), "wild": pos}
	params.merge(extra, true)
	var c: Node3D = CompanionScript.new()
	c.setup(params)
	add_child(c)
	c.global_position = pos
	nodes.append(c)
	Game.companion_nodes[id] = c
	return c


func _befriend(id: String, assignment: String = "home") -> void:
	GameState.companion(id)["befriended"] = true
	GameState.set_companion_assignment(id, assignment)


## A befriended follower standing beside Krystal.
func _follower(id: String, pos: Vector3 = Vector3(1.2, 0.05, 6.8)) -> Node3D:
	_befriend(id, "follow")
	return _make(id, "follow", pos)


func _enemy(pos: Vector3, threatening: bool = true) -> FakeEnemy:
	var e := FakeEnemy.new()
	e.threatening = threatening
	add_child(e)
	e.global_position = pos
	nodes.append(e)
	return e


func _said_contains(fragment: String) -> bool:
	for s in said:
		if String(s[1]).contains(fragment):
			return true
	return false


## Waits (physics frames) until cond() is true or `seconds` passed. Returns true if it became true.
func _wait_until(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if bool(cond.call()):
			return true
		await wait_physics(1)
		t += 1.0 / float(Engine.physics_ticks_per_second)
	return bool(cond.call())
