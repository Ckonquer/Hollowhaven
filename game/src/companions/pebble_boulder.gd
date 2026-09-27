extends Node3D
## The grumbling boulder at the quarry that pins Pebble. A pickaxe harvestable (4 hits at power 1)
## and an interactable (E also swings the best pickaxe; without one it says "Needs a Pickaxe").
## Wobbles and grumbles when Krystal is near, cracks a little more with every hit and finally
## bursts apart, releasing Pebble. Persistent via GameState.deplete("pebble_boulder", -1).
##   setup({"pebble": <companion node>, "front": Vector3})

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Fx := preload("res://src/companions/companion_fx.gd")
const Logic := preload("res://src/companions/companion_logic.gd")

const HITS_NEEDED := 4.0
const ROCK := Color("a39d92")
const ROCK_DARK := Color("7d776d")
const CRACK := Color("3b2f35")

var node_id: String = Logic.PINNED_BOULDER_ID
var pebble: Node3D = null
var front := Vector3.BACK
var damage: float = 0.0
var broken: bool = false

var _pivot: Node3D
var _cracks: Array = []
var _body: StaticBody3D
var _grumble_t: float = 3.0
var _hit_cd: float = 0.0
var _caption_cd: float = 0.0
var _wobble_tw: Tween
var _rng := RandomNumberGenerator.new()


func setup(params: Dictionary) -> void:
	if params.get("pebble") is Node3D:
		pebble = params["pebble"]
	if params.get("front") is Vector3:
		var f: Vector3 = params["front"]
		f.y = 0.0
		if f.length() > 0.01:
			front = f.normalized()


func _ready() -> void:
	_rng.randomize()
	name = "PebbleBoulder"
	add_to_group("harvestable")
	add_to_group("interactable")
	rotation.y = atan2(front.x, front.z)
	_pivot = Node3D.new()
	add_child(_pivot)
	var rock := Kit.blob(0.95, Mat.outlined(Mat.toon(ROCK, {"noise": 0.14, "noise_scale": 1.6, "rim": 0.25}), 0.02), 42, 0.16, 0.86, 3)
	Kit.add(_pivot, rock, Vector3(0, 0.78, -0.12))
	# Moss cap and a few pebbles scattered around, so it reads as an old, sleepy boulder.
	var moss := Kit.blob(0.5, Mat.outlined(Mat.toon(Palette.MOSS, {"noise": 0.15, "noise_scale": 3.0}), 0.015), 7, 0.3, 0.35, 2)
	Kit.add(_pivot, moss, Vector3(-0.15, 1.52, -0.25), Vector3(0, 0, 8))
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.6
		var peb := Kit.blob(0.12 + 0.04 * float(i % 2), Mat.toon(ROCK_DARK, {"noise": 0.1}), 60 + i, 0.2, 0.7, 2)
		Kit.add(self, peb, Vector3(cos(a) * 1.25, 0.05, sin(a) * 1.25 - 0.1))
	# Cracks (hidden until hit): dark thin slabs on the front face.
	var crack_specs := [[Vector3(0.1, 0.95, 0.68), Vector3(0, 0, 35), 0.34], [Vector3(-0.25, 0.7, 0.72), Vector3(0, 20, -50), 0.3],
		[Vector3(0.32, 0.55, 0.64), Vector3(0, -25, 70), 0.28], [Vector3(-0.05, 1.2, 0.5), Vector3(-35, 0, -15), 0.3]]
	for cs in crack_specs:
		var c := Kit.box(Vector3(float(cs[2]), 0.035, 0.05), Mat.toon(CRACK, {"noise": 0.0, "rim": 0.0}))
		Kit.add(_pivot, c, cs[0], cs[1])
		c.visible = false
		_cracks.append(c)
	# Solid for movement (world layer) and found by the interaction probe (interact layer).
	_body = StaticBody3D.new()
	_body.collision_layer = 1 | 16
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.92
	shape.shape = sph
	shape.position = Vector3(0, 0.72, -0.12)
	_body.add_child(shape)
	add_child(_body)
	if pebble != null and is_instance_valid(pebble) and pebble.has_method("link_boulder"):
		pebble.link_boulder(self)


func _process(delta: float) -> void:
	if broken:
		return
	_hit_cd = maxf(_hit_cd - delta, 0.0)
	_caption_cd = maxf(_caption_cd - delta, 0.0)
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var d := p.global_position.distance_to(global_position)
	if d > 16.0:
		return
	_grumble_t -= delta
	if _grumble_t <= 0.0:
		_grumble_t = _rng.randf_range(4.5, 8.0)
		_grumble(0.5)
		if _caption_cd <= 0.0 and d < 12.0:
			_caption_cd = 25.0
			Events.caption.emit("[the boulder grumbles]")


# --- Harvestable / interactable contract -------------------------------------------------------------

func get_harvest_info() -> Dictionary:
	return {"tool": "pickaxe", "name": "Grumbling Boulder"}


func get_interaction(_player: Node = null) -> Dictionary:
	if broken:
		return {}
	if GameState.best_tool("pickaxe") == "":
		return {"text": "Needs a Pickaxe", "enabled": false}
	return {"text": "Break the grumbling boulder", "enabled": true}


func interact(player: Node = null) -> void:
	var tool := GameState.best_tool("pickaxe")
	if tool == "":
		Events.hint.emit("pebble_boulder_pickaxe", "This boulder is too tough for bare hands. Craft a Stone Pickaxe.")
		_grumble(0.4)
		return
	harvest_hit(player, tool)


func harvest_hit(_player: Node, tool_item_id: String) -> void:
	if broken or _hit_cd > 0.0:
		return
	var d: Dictionary = ItemDB.item(tool_item_id) if tool_item_id != "" else {}
	if String(d.get("tool", "")) != "pickaxe":
		Events.hint.emit("pebble_boulder_pickaxe", "This boulder is too tough for bare hands. Craft a Stone Pickaxe.")
		return
	_hit_cd = 0.3
	damage += maxf(float(d.get("power", 1.0)), 0.25)
	var hit_pos := global_position + front * 0.8 + Vector3.UP * 0.7
	Audio.play_3d("mine_hit", hit_pos)
	Audio.play_3d("pebble_grunt", global_position + Vector3.UP * 0.5, 2.0)
	Fx.chips(get_parent(), hit_pos, ROCK, 9)
	Events.camera_shake.emit(0.12, 0.15)
	var stage := int(clampf(damage / HITS_NEEDED * float(_cracks.size()), 0.0, float(_cracks.size())))
	for i in _cracks.size():
		var c: Node3D = _cracks[i]
		c.visible = i < stage
	_grumble(1.0)
	if damage >= HITS_NEEDED - 0.001:
		_break()


func is_broken() -> bool:
	return broken


# --- Internals ----------------------------------------------------------------------------------------

func _grumble(strength: float) -> void:
	if _wobble_tw != null and _wobble_tw.is_valid():
		_wobble_tw.kill()
	_pivot.rotation = Vector3.ZERO
	_wobble_tw = create_tween()
	var a := deg_to_rad(4.5) * strength
	_wobble_tw.tween_property(_pivot, "rotation:z", a, 0.07)
	_wobble_tw.tween_property(_pivot, "rotation:z", -a * 0.8, 0.1)
	_wobble_tw.tween_property(_pivot, "rotation:z", a * 0.5, 0.1)
	_wobble_tw.tween_property(_pivot, "rotation:z", 0.0, 0.14)
	if strength < 0.9:
		Audio.play_3d("pebble_grunt", global_position + Vector3.UP * 0.5, -4.0)
	if pebble != null and is_instance_valid(pebble) and pebble.has_method("on_boulder_wobble"):
		pebble.on_boulder_wobble()


func _break() -> void:
	broken = true
	GameState.deplete(node_id, -1.0)
	remove_from_group("harvestable")
	remove_from_group("interactable")
	_body.collision_layer = 0
	var center := global_position + Vector3.UP * 0.7
	Audio.play_3d("rock_break", center)
	Events.camera_shake.emit(0.25, 0.3)
	Fx.poof(get_parent(), global_position + Vector3.UP * 0.2, Color("d8d2c6"), 22, 1.8)
	Fx.chips(get_parent(), center, ROCK, 14)
	GameState.give_item("stone", 2, global_position + front * 1.2)
	Events.harvested.emit("rock", "stone", 2, center)
	# Split into chunks that tumble outward and shrink away.
	_pivot.visible = false
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		var chunk := Kit.blob(0.32 + 0.06 * float(i % 2), Mat.outlined(Mat.toon(ROCK, {"noise": 0.14, "noise_scale": 1.6}), 0.015), 90 + i, 0.25, 0.8, 2)
		add_child(chunk)
		chunk.position = Vector3(cos(a) * 0.35, 0.7, sin(a) * 0.35 - 0.12)
		var out := Vector3(cos(a) * 1.4, 0.0, sin(a) * 1.4 - 0.12)
		var tw := chunk.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "position", out + Vector3(0, 0.25, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(chunk, "rotation", Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2), _rng.randf_range(-2, 2)), 0.6)
		tw.chain().tween_property(chunk, "position:y", 0.12, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.chain().tween_interval(1.4)
		tw.chain().tween_property(chunk, "scale", Vector3.ONE * 0.01, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if pebble != null and is_instance_valid(pebble) and pebble.has_method("release_from_boulder"):
		pebble.release_from_boulder()
	var done := create_tween()
	done.tween_interval(3.2)
	done.tween_callback(queue_free)
