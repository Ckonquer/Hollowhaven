extends Node3D
## Base node for a placed Haven structure (created by structure_factory.gd from GameState.structures).
## Builds its model, a solid collider on layer "structure" (32) when the data says solid, and an
## interaction collider on layer "interact" (16) when it has an interaction. Colliders carry
## meta "surface" ("wood"/"stone") for footsteps and meta "structure_uid".
## Subclasses override _setup_behaviour(), get_interaction(player) and interact(player).

const Models := preload("res://src/building/structure_models.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Palette := preload("res://src/art/palette.gd")
const Tints := preload("res://src/building/tints.gd")
const PlacementRules := preload("res://src/building/placement.gd")

const LAYER_INTERACT := 16
const LAYER_STRUCTURE := 32

var uid: String = ""
var structure_id: String = ""
var def: Dictionary = {}
var parts: Dictionary = {}
var model: Node3D
var _bodies: Array = []
var _highlighted := false
var _removing := false
var _scale_tween: Tween
var _extra_opts: Dictionary = {}      # model options given at creation (previews without a saved record)


func setup(params: Dictionary) -> void:
	uid = String(params.get("uid", uid))
	structure_id = String(params.get("id", structure_id))
	var mo: Variant = params.get("model_opts")
	if mo is Dictionary:
		_extra_opts = (mo as Dictionary).duplicate()


func _ready() -> void:
	if def.is_empty():
		def = ItemDB.structure(structure_id)
	add_to_group("structure")
	set_meta("structure_uid", uid)
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	parts = Models.build(structure_id, model, model_opts())
	_apply_saved_tint()
	_build_colliders()
	if is_interactable():
		add_to_group("interactable")
	_setup_behaviour()


## Virtual: behaviour setup after the model and colliders exist.
func _setup_behaviour() -> void:
	pass


## Model options from the saved record (Chapter Two): {"face": pumpkin face id} when set, "level" (>= 1 for
## pieces upstairs: wall panels drop their stone footing), "mount_dir" (wall decor on a window: which way the
## window centre lies, see placement.gd mount_info). Preview nodes take them from setup({"model_opts": {...}}).
## Subclasses may add.
func model_opts() -> Dictionary:
	var o := _extra_opts.duplicate()
	var rec := record()
	var data: Variant = rec.get("data", {})
	if data is Dictionary and (data as Dictionary).has("face"):
		o["face"] = String((data as Dictionary)["face"])
	if not rec.is_empty():
		var lv := PlacementRules.level_of(rec)
		if lv >= 1:
			o["level"] = lv
		if PlacementRules.is_wall_mount(def):
			var md := PlacementRules.mount_dir_of(rec, GameState.structures)
			if md != 0:
				o["mount_dir"] = md
	return o


## Saved recolour (data.tint), applied right after the model is built.
func _apply_saved_tint() -> void:
	var t := Tints.tint_of(record())
	if t != Tints.NATURAL:
		Tints.apply(model, t, String(def.get("tint_family", "")))


## Recolours the model in place (the record's data.tint is the caller's job: BuildOps.recolor).
func apply_tint(tint_id: String) -> void:
	if model != null:
		Tints.apply(model, tint_id, String(def.get("tint_family", "")))


## Rebuilds the model from the saved record (e.g. a new pumpkin face), keeping colliders and behaviour.
func rebuild_model() -> void:
	if model == null or _removing:
		return
	for c in model.get_children():
		model.remove_child(c)
		c.queue_free()
	parts = Models.build(structure_id, model, model_opts())
	_apply_saved_tint()
	if _highlighted:
		_apply_overlay(model, U.highlight_mat())


func is_interactable() -> bool:
	return String(def.get("interact", "")) != ""


## Player-facing name (the data name; the arachnophobia alt_name when that setting is on).
func display_name() -> String:
	return ItemDB.structure_display_name(structure_id) if not def.is_empty() else structure_id


## GameState record for this structure ({} for preview-only nodes).
func record() -> Dictionary:
	var r: Variant = GameState.structures.get(uid)
	return r if r is Dictionary else {}


func _build_colliders() -> void:
	var surface := Models.surface_kind(structure_id)
	if bool(def.get("solid", false)):
		var body := StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = LAYER_STRUCTURE
		body.collision_mask = 0
		for s in Models.collision_shapes(structure_id):
			var cs := CollisionShape3D.new()
			cs.shape = s[0]
			cs.transform = s[1]
			body.add_child(cs)
		body.set_meta("surface", surface)
		body.set_meta("structure_uid", uid)
		add_child(body)
		_bodies.append(body)
	if is_interactable():
		var ib := StaticBody3D.new()
		ib.name = "Interact"
		ib.collision_layer = LAYER_INTERACT
		ib.collision_mask = 0
		var ishape: Array = Models.interact_shape(structure_id)
		var cs2 := CollisionShape3D.new()
		cs2.shape = ishape[0]
		cs2.transform = ishape[1]
		ib.add_child(cs2)
		ib.set_meta("surface", surface)
		ib.set_meta("structure_uid", uid)
		add_child(ib)
		_bodies.append(ib)


# --- Interaction contract (defaults: nothing to do) ----------------------------------------------

func get_interaction(_player: Node) -> Dictionary:
	# Structures whose behaviour script has not been built yet still honour the interaction contract.
	if is_interactable():
		return {"text": display_name(), "enabled": false, "reason": "Not ready yet"}
	return {}


func interact(_player: Node) -> void:
	pass


# --- Build-mode feedback -------------------------------------------------------------------------

## Red overlay on the piece that X would dismantle.
func set_highlight(on: bool) -> void:
	if on == _highlighted or model == null:
		return
	_highlighted = on
	_apply_overlay(model, U.highlight_mat() if on else null)


func _apply_overlay(n: Node, mat: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = mat
	for c in n.get_children():
		_apply_overlay(c, mat)


## Springy pop-in with a puff of dust (called right after placing).
func play_place_anim() -> void:
	if model == null:
		return
	_kill_scale_tween()
	model.scale = Vector3(0.55, 0.3, 0.55)
	_scale_tween = create_tween()
	_scale_tween.tween_property(model, "scale", Vector3.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_puff(global_position, 14)


## Interaction-probe hook: a tiny squash-and-settle when Krystal looks at this piece.
func set_focused(on: bool) -> void:
	if not on or model == null or _removing or not is_inside_tree():
		return
	_kill_scale_tween()
	_scale_tween = create_tween()
	_scale_tween.tween_property(model, "scale", Vector3(1.035, 0.965, 1.035), 0.07)
	_scale_tween.tween_property(model, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _kill_scale_tween() -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = null


## Removes colliders at once, shrinks away and frees itself.
func play_remove_and_free() -> void:
	if _removing:
		return
	_removing = true
	for g in ["interactable", "crafting_station", "light_source", "structure"]:
		if is_in_group(g):
			remove_from_group(g)
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	set_highlight(false)
	if not is_inside_tree() or model == null:
		queue_free()
		return
	_puff(global_position, 10)
	_kill_scale_tween()
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3(0.05, 0.05, 0.05), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _puff(at: Vector3, amount: int) -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.92
	p.mesh = Shapes.prim_sphere(0.09, 6, 8)
	p.material_override = _dust_mat()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var s: Vector2i = def.get("size", Vector2i.ONE)
	p.emission_box_extents = Vector3(float(s.x) * 0.45, 0.05, float(s.y) * 0.45)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -1.2, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at + Vector3.UP * 0.1
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _dust_mat() -> Material:
	return preload("res://src/art/mat.gd").toon(Palette.CLOTH_CREAM.lerp(Palette.DIRT, 0.35), {"rim": 0.2})
