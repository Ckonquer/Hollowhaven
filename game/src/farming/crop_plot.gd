extends "res://src/building/structure.gd"
## Crop plot: a view over GameState.crops[uid]. Plant seeds (E), watch 4 growth stages, harvest (E).
## Nine plants share one MultiMesh; ripe crops show orange roots and twinkling sparkles.

const Farming := preload("res://src/farming/farming.gd")
const CropModels := preload("res://src/farming/crop_models.gd")

var debug_stage: int = -2          # previews: force a stage (-1 empty .. 3 ripe); -2 = use GameState
var plants: MultiMeshInstance3D
var sparkles: CPUParticles3D
var _stage := -99
var _tween: Tween


func setup(params: Dictionary) -> void:
	super.setup(params)
	debug_stage = int(params.get("stage", debug_stage))


func _setup_behaviour() -> void:
	plants = MultiMeshInstance3D.new()
	plants.name = "Plants"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = CropModels.stage_mesh(0)
	var pos: Array = CropModels.plant_positions()
	mm.instance_count = pos.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid if uid != "" else "preview")
	for i in pos.size():
		var s := rng.randf_range(0.88, 1.12)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.1), s))
		var jitter := Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.04, 0.04))
		mm.set_instance_transform(i, Transform3D(b, (pos[i] as Vector3) + jitter))
	plants.multimesh = mm
	plants.material_override = CropModels.plant_material()
	model.add_child(plants)
	sparkles = CPUParticles3D.new()
	sparkles.name = "Sparkles"
	sparkles.amount = 7
	sparkles.lifetime = 1.6
	sparkles.mesh = Shapes.star(0.075)
	sparkles.local_coords = true
	sparkles.material_override = U.sparkle_mat(Palette.WARD_GLOW)
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparkles.emission_box_extents = Vector3(0.8, 0.12, 0.8)
	sparkles.direction = Vector3.UP
	sparkles.spread = 25.0
	sparkles.gravity = Vector3(0, 0.12, 0)
	sparkles.initial_velocity_min = 0.05
	sparkles.initial_velocity_max = 0.15
	sparkles.scale_amount_min = 0.7
	sparkles.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	sparkles.scale_amount_curve = curve
	sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparkles.emitting = false
	sparkles.position = Vector3(0, 0.45, 0)
	model.add_child(sparkles)
	Events.crop_planted.connect(_on_crop_event.unbind(1))
	Events.crop_harvested.connect(_on_crop_event.unbind(2))
	Events.time_of_day_changed.connect(_on_time_changed)
	refresh()


func _on_crop_event(event_uid: String) -> void:
	if event_uid == uid:
		refresh()


func _on_time_changed(_day: int, _tod: float) -> void:
	refresh()


func current_stage() -> int:
	return debug_stage if debug_stage > -2 else Farming.stage(uid)


## Syncs visuals with the state (cheap when nothing changed).
func refresh() -> void:
	if plants == null:
		return
	var st := current_stage()
	if st == _stage:
		return
	var grew := _stage >= 0 and st > _stage
	_stage = st
	plants.visible = st >= 0
	if st >= 0:
		plants.multimesh.mesh = CropModels.stage_mesh(st)
	sparkles.emitting = st == Farming.STAGE_RIPE
	if grew and is_inside_tree():
		_bounce(Vector3(1.0, 0.6, 1.0))


func _bounce(from: Vector3) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	plants.scale = from
	_tween = create_tween()
	_tween.tween_property(plants, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _crop_name(crop: String) -> String:
	return String(ItemDB.crop(crop).get("name", crop.capitalize()))


func get_interaction(_player: Node) -> Dictionary:
	var st := Farming.stage(uid)
	if st < 0:
		var seed := Farming.choose_seed()
		if seed == "":
			return {"text": "Plant seeds (you have none)", "enabled": false}
		return {"text": "Plant %s" % ItemDB.display_name(seed), "enabled": true}
	var crop := Farming.crop_id(uid)
	if st == Farming.STAGE_RIPE:
		return {"text": "Harvest %s" % _crop_name(crop), "enabled": true}
	return {"text": "%s: %s, ripe in ~%s" % [_crop_name(crop), Farming.stage_name(st).to_lower(), Farming.format_minutes(Farming.minutes_remaining(uid))], "enabled": true}


func interact(_player: Node) -> void:
	var st := Farming.stage(uid)
	if st < 0:
		var seed := Farming.choose_seed()
		if Farming.plant(uid, seed, global_position):
			Events.notify.emit("Planted %s." % ItemDB.display_name(seed), "info")
			Events.hint.emit("farming_growth", "Crops grow as time passes. A friend at home will tend them so they grow faster.")
			refresh()
			_bounce(Vector3(1.2, 0.3, 1.2))
		return
	if st == Farming.STAGE_RIPE:
		var got := Farming.harvest(uid, global_position + Vector3.UP * 0.6)
		if not got.is_empty():
			var bits: PackedStringArray = []
			for item in got:
				bits.append("%d %s" % [int(got[item]), ItemDB.display_name(String(item))])
			Events.notify.emit("Harvested " + ", ".join(bits) + "!", "success")
			_puff(global_position, 10)
		refresh()
		return
	Events.notify.emit("The %s is %s. Ripe in about %s." % [_crop_name(Farming.crop_id(uid)), Farming.stage_name(st).to_lower(), Farming.format_minutes(Farming.minutes_remaining(uid))], "info")
	_bounce(Vector3(1.08, 0.85, 1.08))
