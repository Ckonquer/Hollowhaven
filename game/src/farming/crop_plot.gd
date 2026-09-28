extends "res://src/building/structure.gd"
## Farm structure (crop plot, and the Sturdy Planter through structure_factory LAZY_SCRIPTS): a view over
## GameState.crops[uid]. Plant seeds (E), watch 4 growth stages, harvest (E).
## Plants share one MultiMesh laid out for the planted crop (crop_models.gd plant_layout: sweetroot / sunflax 9,
## roseberry 4, pumpkin 1 on the 2 x 2 plot; 6 / 2 / 1 on the 2 x 1 planter); ripe crops twinkle.
## refresh() is cheap (compares crop + stage) and runs on crop events and about once per in-game minute.

const Farming := preload("res://src/farming/farming.gd")
const CropModels := preload("res://src/farming/crop_models.gd")

var debug_stage: int = -2          # previews: force a stage (-1 empty .. 3 ripe); -2 = use GameState
var debug_crop: String = ""        # previews: force a crop id ("" = the planted one)
var plants: MultiMeshInstance3D
var sparkles: CPUParticles3D
var _stage := -99
var _crop := ""                    # crop the plant layout is built for
var _shown := ""                   # crop whose mesh is shown
var _xforms: Array[Transform3D] = []  # plant transforms of the current layout (the headless renderer can't read them back)
var _tween: Tween


func setup(params: Dictionary) -> void:
	super.setup(params)
	debug_stage = int(params.get("stage", debug_stage))
	debug_crop = String(params.get("crop", debug_crop))


func _setup_behaviour() -> void:
	plants = MultiMeshInstance3D.new()
	plants.name = "Plants"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	var crop := current_crop()
	mm.mesh = CropModels.stage_mesh(0, crop if crop != "" else "sweetroot")
	plants.multimesh = mm
	_layout(crop if crop != "" else "sweetroot")
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
	var s: Vector2i = def.get("size", Vector2i(2, 2))
	sparkles.emission_box_extents = Vector3(float(s.x) * 0.4, 0.12, float(s.y) * 0.4)
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
	sparkles.position = Vector3(0, CropModels.soil_top(structure_id) + 0.27, 0)
	model.add_child(sparkles)
	Events.crop_planted.connect(_on_crop_event.unbind(1))
	Events.crop_harvested.connect(_on_crop_event.unbind(2))
	Events.time_of_day_changed.connect(_on_time_changed)
	refresh()


## (Re)builds the plant transforms for `crop` on this structure. Same seeded jitter as the legacy plot, so a
## sweetroot plot looks exactly as before.
func _layout(crop: String) -> void:
	_crop = crop
	var pos: Array = CropModels.plant_layout(structure_id, crop)
	var sc := CropModels.plant_scale(structure_id, crop)
	var mm := plants.multimesh
	mm.instance_count = pos.size()
	_xforms.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid if uid != "" else "preview")
	for i in pos.size():
		var s := rng.randf_range(0.88, 1.12) * sc
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.1), s))
		var jitter := Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.04, 0.04))
		var t := Transform3D(b, (pos[i] as Vector3) + jitter)
		mm.set_instance_transform(i, t)
		_xforms.append(t)


func _on_crop_event(event_uid: String) -> void:
	if event_uid == uid:
		refresh()


func _on_time_changed(_day: int, _tod: float) -> void:
	refresh()


func current_stage() -> int:
	return debug_stage if debug_stage > -2 else Farming.stage(uid)


## The crop shown ("" when empty).
func current_crop() -> String:
	if debug_crop != "":
		return debug_crop
	return Farming.crop_id(uid)


## Plants currently laid out (MultiMesh instances).
func plant_count() -> int:
	return plants.multimesh.instance_count if plants != null else 0


## Local transform of plant `i` in the current layout.
func plant_transform(i: int) -> Transform3D:
	return _xforms[i] if i >= 0 and i < _xforms.size() else Transform3D.IDENTITY


## Syncs visuals with the state (cheap when nothing changed).
func refresh() -> void:
	if plants == null:
		return
	var st := current_stage()
	var crop := current_crop()
	if st == _stage and (st < 0 or crop == _shown):
		return
	var grew := _stage >= 0 and st > _stage and crop == _shown
	_stage = st
	plants.visible = st >= 0
	if st >= 0:
		var c := crop if crop != "" else "sweetroot"
		if c != _crop:
			_layout(c)
		plants.multimesh.mesh = CropModels.stage_mesh(st, c)
		_shown = crop
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
