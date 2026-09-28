extends Node3D
## One turning candelabrum of the ballroom candle-routing puzzle (candle_route_puzzle.gd owns the state).
## A brass candelabrum on a little turntable; its brass hand (and the chevron on the floor, bold with
## high_visibility_cues) points along the gilt runner the flame will follow. Interaction: "Turn the
## candelabrum" -> puzzle.turn(node_id). Lit (the flame reached it): three candles glow; it is then a
## small light source (light_radius) like any real candle.

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const BRASS := Color("d6ad55")
const BRASS_DARK := Color("8e6a2c")
const WAX := Color("f7ecd8")
const FLAME := Color("ffc562")

var node_id: String = ""
var puzzle: Node = null
var light_radius: float = 2.4
var _lit := false
var _arm: Node3D
var _flames: Array = []
var _light: OmniLight3D
var _chevron: MeshInstance3D
var _bold: MeshInstance3D
var _target_yaw := 0.0
var _tw: Tween = null


func setup(params: Dictionary) -> void:
	node_id = String(params.get("id", node_id))
	puzzle = params.get("puzzle", null)


func _ready() -> void:
	name = "Candelabrum_" + node_id
	add_to_group("interactable")
	add_to_group("light_source")
	add_to_group("mm_candelabrum")
	_build()
	set_lit(false)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func is_light_active() -> bool:
	return _lit


func is_lit() -> bool:
	return _lit


func set_lit(on: bool) -> void:
	_lit = on
	for f in _flames:
		(f as Node3D).visible = on
	if _light != null:
		_light.visible = on


## Points the hand at a world XZ point (yaw about +Y, forward = -Z).
func point_at(target: Vector3, animate: bool = true) -> void:
	var here := global_position if is_inside_tree() else position
	var d := Vector2(target.x - here.x, target.z - here.z)
	if d.length() < 0.01:
		return
	_target_yaw = atan2(-d.x, -d.y)
	if _arm == null:
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if animate and is_inside_tree():
		var cur := _arm.rotation.y
		var goal := cur + wrapf(_target_yaw - cur, -PI, PI)
		_tw = create_tween()
		_tw.tween_property(_arm, "rotation:y", goal, 0.3).set_trans(Tween.TRANS_SINE)
	else:
		_arm.rotation.y = _target_yaw


func arm_yaw() -> float:
	return _target_yaw


func get_interaction(_player: Node = null) -> Dictionary:
	if puzzle == null or not is_instance_valid(puzzle):
		return {}
	if bool(puzzle.call("is_solved")):
		return {"text": "The candelabrum has found its partner", "enabled": false}
	return {"text": "Turn the candelabrum", "enabled": true}


func interact(_player: Node = null) -> void:
	if puzzle == null or not is_instance_valid(puzzle) or bool(puzzle.call("is_solved")):
		return
	puzzle.call("turn", node_id)


func _build() -> void:
	var brass := Mat.outlined(Mat.toon(BRASS, {"rim": 0.5, "specular": 0.35}), 0.012)
	var dark := Mat.toon(BRASS_DARK, {"rim": 0.3})
	Kit.add(self, Kit.cylinder(0.5, 0.56, 0.1, dark, 18), Vector3(0, 0.05, 0))
	Kit.add(self, Kit.torus(0.44, 0.52, brass), Vector3(0, 0.1, 0))
	_arm = Node3D.new()
	_arm.name = "Arm"
	add_child(_arm)
	Kit.add(_arm, Kit.cylinder(0.05, 0.07, 1.25, brass, 10), Vector3(0, 0.72, 0))
	Kit.add(_arm, Kit.sphere(0.09, brass, 8, 10), Vector3(0, 0.62, 0))
	Kit.add(_arm, Kit.box(Vector3(0.9, 0.05, 0.05), brass), Vector3(0, 1.32, 0))
	var wax := Mat.toon(WAX, {"rim": 0.25})
	var glow := Mat.glow(FLAME, 3.0)
	for x in [-0.42, 0.0, 0.42]:
		Kit.add(_arm, Kit.cylinder(0.08, 0.05, 0.06, brass, 10), Vector3(float(x), 1.37, 0))
		Kit.add(_arm, Kit.cylinder(0.04, 0.045, 0.2 if x != 0.0 else 0.28, wax, 8), Vector3(float(x), 1.49 if x != 0.0 else 1.53, 0))
		var f := Kit.sphere(0.045, glow, 6, 8)
		Kit.add(_arm, f, Vector3(float(x), 1.63 if x != 0.0 else 1.71, 0), Vector3.ZERO, Vector3(1.0, 1.9, 1.0))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.append(f)
	# The brass hand: a little pointing glove on a rod (forward = -Z).
	Kit.add(_arm, Kit.box(Vector3(0.05, 0.05, 0.5), brass), Vector3(0, 0.92, -0.27))
	Kit.add(_arm, Kit.sphere(0.11, brass, 8, 10), Vector3(0, 0.92, -0.56), Vector3.ZERO, Vector3(1.0, 0.7, 1.3))
	Kit.add(_arm, Kit.cone(0.06, 0.22, brass, 8), Vector3(0, 0.92, -0.74), Vector3(-90, 0, 0))
	# Floor chevron on the turntable (bold version for high_visibility_cues).
	_chevron = Kit.prism(Vector3(0.5, 0.42, 0.03), Mat.glow(Color("ffd98a"), 0.9))
	Kit.add(_arm, _chevron, Vector3(0, 0.12, -0.2), Vector3(-90, 0, 0))
	_chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bold = Kit.prism(Vector3(0.9, 1.1, 0.03), Mat.glow(Color("fff4d0"), 1.6))
	Kit.add(_arm, _bold, Vector3(0, 0.035, -1.05), Vector3(-90, 0, 0))
	_bold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bold.visible = bool(Settings.get_value("high_visibility_cues"))
	_light = OmniLight3D.new()
	_light.name = "CandelabrumLight"
	_light.light_color = FLAME
	_light.light_energy = 0.9
	_light.omni_range = 3.4
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 24.0
	_light.distance_fade_length = 8.0
	_light.position = Vector3(0, 1.8, 0)
	add_child(_light)
	var body := StaticBody3D.new()
	body.name = "StandBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 1.5
	cs.shape = cyl
	cs.position = Vector3(0, 0.75, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.85
	ics.shape = sph
	ics.position = Vector3(0, 1.0, 0)
	ib.add_child(ics)
	add_child(ib)
	_arm.rotation.y = _target_yaw


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _bold != null:
		_bold.visible = bool(Settings.get_value("high_visibility_cues"))
