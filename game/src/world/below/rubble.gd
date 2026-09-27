extends Node3D
## Collapsed rubble blocking a passage (pickaxe harvestable). A few satisfying hits clear it for good:
## flag "gallery_cleared" (+ GameState.deplete(node_id, -1)). Cleared rubble leaves loose debris only.
##   var r = Rubble.new(); r.setup({"size": Vector3(4, 3, 3.5), "flag": "gallery_cleared"})

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var size: Vector3 = Vector3(4.0, 3.0, 3.5)
var flag: String = "gallery_cleared"
var node_id: String = "below_gallery_rubble"
var hits_needed: int = 4
var display_name: String = "Collapsed Rubble"
var hits: int = 0
var cleared: bool = false

var _pile: Node3D
var _body: StaticBody3D
var _area: Area3D
var _debris: Node3D
var _tween: Tween
var _rocks: Array = []


func setup(p: Dictionary) -> void:
	size = p.get("size", size)
	flag = String(p.get("flag", flag))
	node_id = String(p.get("node_id", node_id))
	hits_needed = int(p.get("hits", hits_needed))


func _ready() -> void:
	_build()
	if bool(GameState.get_flag(flag)):
		_set_cleared(false)
	else:
		add_to_group("harvestable")


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var cols := [Palette.MINE_ROCK, Palette.MINE_ROCK.lerp(Palette.MINE_ROCK_DARK, 0.4), Palette.MINE_ROCK.lerp(Palette.DIRT_DARK, 0.35)]
	_pile = Node3D.new()
	_pile.name = "Pile"
	add_child(_pile)
	for i in 16:
		var fx := rng.randf_range(-0.5, 0.5)
		var fz := rng.randf_range(-0.45, 0.45)
		var layer := rng.randf()
		var r := rng.randf_range(0.45, 0.85) * (1.0 - layer * 0.35)
		var y := layer * size.y * 0.75 + r * 0.5
		var c: Color = cols[rng.randi_range(0, cols.size() - 1)]
		var rock := Kit.blob(r, Mat.outlined(Mat.toon(c.lightened(rng.randf_range(0.0, 0.08))), 0.025), rng.randi_range(1, 30), 0.3, 0.8)
		_pile.add_child(rock)
		rock.position = Vector3(fx * size.x, y, fz * size.z)
		rock.rotation = Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)
		_rocks.append(rock)
	# Broken timber poking out
	var wood := Mat.outlined(Mat.toon(Color("6e4a31")), 0.02)
	var beam := Kit.box(Vector3(0.26, 0.26, size.x * 0.9), wood)
	_pile.add_child(beam)
	beam.position = Vector3(0.1, size.y * 0.55, 0.3)
	beam.rotation = Vector3(0.4, PI * 0.5, 0.35)
	var beam2 := Kit.box(Vector3(0.22, 0.22, 2.0), wood)
	_pile.add_child(beam2)
	beam2.position = Vector3(-0.5, size.y * 0.3, -0.6)
	beam2.rotation = Vector3(-0.6, 0.3, 0.2)
	# Blocking collider
	_body = StaticBody3D.new()
	_body.name = "Block"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size.x, size.y + 1.0, size.z)
	cs.shape = sh
	cs.position = Vector3(0, (size.y + 1.0) * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)
	# Probe collider (interact layer) slightly larger so the pickaxe reaches it
	_area = Area3D.new()
	_area.name = "HarvestArea"
	_area.collision_layer = 16
	_area.collision_mask = 0
	_area.monitoring = false
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(size.x + 0.6, size.y, size.z + 0.6)
	acs.shape = ash
	acs.position = Vector3(0, size.y * 0.5, 0)
	_area.add_child(acs)
	add_child(_area)
	# Debris shown once cleared (walkable: no collision)
	_debris = Node3D.new()
	_debris.name = "Debris"
	_debris.visible = false
	add_child(_debris)
	for i in 9:
		var r := rng.randf_range(0.12, 0.3)
		var d := Kit.blob(r, Mat.toon(cols[i % cols.size()]), rng.randi_range(40, 60), 0.3, 0.6)
		_debris.add_child(d)
		var side := -1.0 if i % 2 == 0 else 1.0
		d.position = Vector3(rng.randf_range(-size.x * 0.45, size.x * 0.45), r * 0.2, side * rng.randf_range(size.z * 0.3, size.z * 0.48))


func get_harvest_info() -> Dictionary:
	if cleared:
		return {}
	return {"tool": "pickaxe", "name": display_name}


func harvest_hit(player: Node, tool_item_id: String = "") -> void:
	if cleared:
		return
	var power := 1.0
	if tool_item_id != "" and ItemDB.has_item(tool_item_id):
		power = maxf(float(ItemDB.item(tool_item_id).get("power", 1.0)), 1.0)
	hits += int(roundf(power))
	var at := global_position + Vector3(0, size.y * 0.4, 0)
	if player is Node3D:
		at = global_position.lerp((player as Node3D).global_position, 0.25) + Vector3(0, 1.0, 0)
	Audio.play_3d("mine_hit", at)
	_chips(at)
	if hits >= hits_needed:
		Audio.play_3d("rock_break", at)
		GameState.give_item("stone", 2, at)
		Events.harvested.emit("rock", "stone", 2, at)
		_set_cleared(true)
	else:
		_wobble()


func _wobble() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_pile.rotation = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_pile, "rotation:z", 0.035, 0.05)
	_tween.tween_property(_pile, "rotation:z", -0.025, 0.07)
	_tween.tween_property(_pile, "rotation:z", 0.0, 0.08)
	# knock the topmost rock loose a little each hit
	var idx := clampi(_rocks.size() - 1 - hits, 0, _rocks.size() - 1)
	var rock: Node3D = _rocks[idx]
	if is_instance_valid(rock):
		var t2 := create_tween()
		t2.tween_property(rock, "position:y", maxf(rock.position.y - 0.4, 0.2), 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _chips(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = Mat.toon(Palette.MINE_ROCK.lightened(0.1))
	p.mesh = bm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _set_cleared(animate: bool) -> void:
	cleared = true
	remove_from_group("harvestable")
	GameState.set_flag(flag, true)
	GameState.deplete(node_id, -1.0)
	if _body != null:
		_body.queue_free()
		_body = null
	if _area != null:
		_area.queue_free()
		_area = null
	_debris.visible = true
	if animate:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_parallel(true)
		for rock in _rocks:
			if is_instance_valid(rock):
				_tween.tween_property(rock, "scale", Vector3.ONE * 0.05, 0.45).set_delay(randf() * 0.25)
				_tween.tween_property(rock, "position:y", 0.1, 0.45)
		_tween.chain().tween_callback(_pile.hide)
		Events.camera_shake.emit(0.25, 0.3)
	else:
		_pile.visible = false
