extends Node3D
## A stone brazier in the Heartseed Chamber. Interactable: "Light the brazier" (needs the Lantern).
## Pressing interact starts a 1.5 s kindling (a spark grows into flame while Krystal stays near;
## walking far away lets it fizzle). Once lit it joins group "light_source" (light_radius 7),
## burns with flame particles + a warm OmniLight3D, plays brazier_light and emits `lit`.
##   var B = load("res://src/enemies/boss_brazier.gd"); var b: Node3D = B.new()
##   b.setup({"id": "brazier_1"}); area.add_child(b); b.global_position = ...
## Optional setup keys: "lit": true (start lit), "persist_flag": "boss_brazier_1" (saved via GameState).

signal lit
signal kindling_started

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Combat := preload("res://src/combat/combat.gd")

const KINDLE_TIME := 1.5
const KINDLE_MAX_DIST := 4.0
const BOWL_Y := 1.28
const FLAME_COLOR := Color("ffb347")

var brazier_id: String = ""
var light_radius: float = 7.0
var persist_flag: String = ""
var kindle_progress: float = 0.0        # 0..1 while kindling

var _lit := false
var _kindling := false
var _kindler: Node3D = null
var _t: float = 0.0
var _light: OmniLight3D
var _fire: CPUParticles3D
var _flame: Node3D
var _rune: MeshInstance3D
var _embers: Array = []
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

static var _fire_mesh: SphereMesh
static var _fire_ramp: Gradient
static var _fire_curve: Curve


func setup(params: Dictionary) -> void:
	brazier_id = String(params.get("id", brazier_id))
	persist_flag = String(params.get("persist_flag", persist_flag))
	light_radius = float(params.get("light_radius", light_radius))
	if Combat.truthy(params.get("lit", false)):
		_lit = true


func _ready() -> void:
	add_to_group("interactable")
	_build()
	if persist_flag != "" and Combat.truthy(GameState.get_flag(persist_flag)):
		_lit = true
	if _lit:
		_apply_lit(true)


# --- Interaction contract -------------------------------------------------------------------------

func get_interaction(_player: Node) -> Dictionary:
	if _lit:
		return {"text": "The brazier burns brightly", "enabled": false}
	if _kindling:
		return {"text": "Kindling...", "enabled": false}
	if not GameState.has_item("lantern"):
		return {"text": "Light the brazier (you need a Lantern)", "enabled": false}
	return {"text": "Light the brazier", "enabled": true}


func interact(player: Node) -> void:
	if _lit or _kindling or not GameState.has_item("lantern"):
		return
	_kindling = true
	_kindler = player as Node3D
	kindle_progress = 0.0
	Audio.play_3d("lantern_on", global_position + Vector3.UP * BOWL_Y, -2.0)
	kindling_started.emit()


func is_lit() -> bool:
	return _lit


func is_light_active() -> bool:
	return _lit


## Lights immediately (debug, scripted beats, tests).
func light() -> void:
	if _lit:
		return
	_kindling = false
	kindle_progress = 1.0
	_lit = true
	_apply_lit(false)
	if persist_flag != "":
		GameState.set_flag(persist_flag, true)
	Audio.play_3d("brazier_light", global_position + Vector3.UP * BOWL_Y, 0.0, 0.05)
	Events.caption.emit("[the brazier roars to life]")
	lit.emit()


func _process(delta: float) -> void:
	_t += delta
	if _kindling:
		if _kindler != null and is_instance_valid(_kindler) and _kindler.global_position.distance_to(global_position) > KINDLE_MAX_DIST:
			_fizzle()
		else:
			kindle_progress = minf(kindle_progress + delta / KINDLE_TIME, 1.0)
			if kindle_progress >= 1.0:
				light()
	# Visual update
	if _lit:
		_light.light_energy = 2.2 + sin(_t * 11.0) * 0.12 + sin(_t * 17.3) * 0.08
		_flame.scale = Vector3(1.0 + sin(_t * 9.0) * 0.06, 1.0 + sin(_t * 13.0) * 0.1, 1.0 + cos(_t * 8.0) * 0.06)
	elif _kindling:
		var k := kindle_progress
		_flame.visible = true
		_flame.scale = Vector3.ONE * (0.15 + 0.6 * k) * (1.0 + sin(_t * 20.0) * 0.1)
		_light.visible = true
		_light.light_energy = 0.4 + 1.2 * k
		_ring.visible = true
		_ring.scale = Vector3.ONE * lerpf(1.25, 1.0, k)
		_ring_mat.albedo_color = Color(FLAME_COLOR, 0.25 + 0.6 * k)
	for i in _embers.size():
		var e := _embers[i] as Node3D
		e.scale = Vector3.ONE * (0.8 + 0.35 * sin(_t * (2.0 + float(i) * 0.7) + float(i)))


func _fizzle() -> void:
	_kindling = false
	_kindler = null
	kindle_progress = 0.0
	_flame.visible = false
	_light.visible = false
	_ring.visible = false
	HitFx.burst(global_position + Vector3.UP * (BOWL_Y + 0.2), Color(0.5, 0.45, 0.5, 0.8), 6, 1.2, 1.0, 0.8, 0.8)


# --- Building -----------------------------------------------------------------------------------------

func _build() -> void:
	var stone := Mat.outlined(Mat.toon(Palette.RUIN_STONE, {"rim": 0.3, "noise": 0.14}), 0.014)
	var stone_dark := Mat.outlined(Mat.toon(Palette.RUIN_STONE_DARK, {"rim": 0.25, "noise": 0.12}), 0.014)
	var bronze := Mat.outlined(Mat.toon(Palette.COPPER.darkened(0.25), {"rim": 0.45, "specular": 0.4}), 0.014)
	Kit.add(self, Kit.cylinder(0.42, 0.5, 0.22, stone_dark, 12), Vector3(0, 0.11, 0))
	Kit.add(self, Kit.cylinder(0.2, 0.26, 0.8, stone, 10), Vector3(0, 0.6, 0))
	Kit.add(self, Kit.torus(0.2, 0.3, stone_dark), Vector3(0, 0.34, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
	# Faintly glowing rune band: readable as "something you can use" even in the dark
	_rune = Kit.torus(0.215, 0.245, Mat.glow(Palette.LANTERN_GLOW, 0.7))
	Kit.add(self, _rune, Vector3(0, 0.72, 0), Vector3.ZERO, Vector3(1, 3.0, 1))
	_rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, Kit.cylinder(0.6, 0.3, 0.34, bronze, 14), Vector3(0, 1.12, 0))
	Kit.add(self, Kit.torus(0.54, 0.64, bronze), Vector3(0, 1.29, 0))
	var coal := Kit.blob(0.44, Mat.toon(Color("2d2426"), {"rim": 0.2, "noise": 0.2}), 3, 0.3, 0.3, 2)
	Kit.add(self, coal, Vector3(0, BOWL_Y - 0.02, 0))
	var ember_mat := Mat.glow(Color("ff7a3a"), 1.3)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.4
		var e := Kit.sphere(0.035, ember_mat, 6, 8)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(self, e, Vector3(cos(a) * 0.22 * (0.6 + 0.4 * float(i % 2)), BOWL_Y + 0.05, sin(a) * 0.22))
		_embers.append(e)
	# Flame core (hidden until kindled)
	_flame = Node3D.new()
	Kit.add(self, _flame, Vector3(0, BOWL_Y + 0.02, 0))
	var outer := Kit.cone(0.34, 0.9, Mat.glow(FLAME_COLOR, 2.4), 12)
	Kit.add(_flame, outer, Vector3(0, 0.42, 0))
	var inner := Kit.cone(0.2, 0.55, Mat.glow(Color("fff1b0"), 3.2), 10)
	Kit.add(_flame, inner, Vector3(0, 0.28, 0))
	for m in [outer, inner]:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	# Kindling ring
	_ring_mat = HitFx.new_tint()
	_ring = Kit.torus(0.66, 0.72, _ring_mat)
	Kit.add(self, _ring, Vector3(0, BOWL_Y + 0.06, 0))
	_ring.visible = false
	# Light (warm, shadowed: there are only three of these)
	_light = OmniLight3D.new()
	_light.light_color = Palette.LANTERN_GLOW
	_light.omni_range = light_radius + 2.0
	_light.omni_attenuation = 1.2
	_light.light_energy = 2.2
	_light.shadow_enabled = true
	_light.position = Vector3(0, BOWL_Y + 0.9, 0)
	_light.visible = false
	add_child(_light)
	# Fire particles
	_fire_resources()
	_fire = CPUParticles3D.new()
	_fire.mesh = _fire_mesh
	_fire.amount = 26
	_fire.lifetime = 0.75
	_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_fire.emission_sphere_radius = 0.25
	_fire.direction = Vector3.UP
	_fire.spread = 12.0
	_fire.initial_velocity_min = 1.0
	_fire.initial_velocity_max = 2.0
	_fire.gravity = Vector3(0, 1.5, 0)
	_fire.scale_amount_min = 0.8
	_fire.scale_amount_max = 1.5
	_fire.scale_amount_curve = _fire_curve
	_fire.color_ramp = _fire_ramp
	_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fire.position = Vector3(0, BOWL_Y + 0.1, 0)
	_fire.emitting = false
	add_child(_fire)
	# Collision: solid pedestal + interaction area on layer 16
	var body_shape := CylinderShape3D.new()
	body_shape.radius = 0.55
	body_shape.height = 1.4
	Kit.static_collider(self, body_shape, Vector3(0, 0.7, 0), 1)
	var area := Area3D.new()
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.2
	cs.shape = sph
	area.add_child(cs)
	add_child(area)
	area.position = Vector3(0, 1.0, 0)


static func _fire_resources() -> void:
	if _fire_mesh != null:
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.disable_receive_shadows = true
	_fire_mesh = SphereMesh.new()
	_fire_mesh.radius = 0.13
	_fire_mesh.height = 0.26
	_fire_mesh.radial_segments = 8
	_fire_mesh.rings = 4
	_fire_mesh.material = m
	_fire_ramp = Gradient.new()
	_fire_ramp.set_color(0, Color(1.0, 0.95, 0.6))
	_fire_ramp.set_color(1, Color(0.4, 0.05, 0.02))
	_fire_ramp.add_point(0.4, Color(1.0, 0.55, 0.15))
	_fire_curve = Curve.new()
	_fire_curve.add_point(Vector2(0.0, 0.7))
	_fire_curve.add_point(Vector2(0.3, 1.0))
	_fire_curve.add_point(Vector2(1.0, 0.0))


func _apply_lit(instant: bool) -> void:
	add_to_group("light_source")
	_kindling = false
	_ring.visible = false
	_flame.visible = true
	_light.visible = true
	_fire.emitting = true
	(_rune as MeshInstance3D).material_override = Mat.glow(Palette.LANTERN_GLOW, 2.2)
	for e in _embers:
		(e as MeshInstance3D).material_override = Mat.glow(Color("ffb060"), 2.6)
	if instant:
		_flame.scale = Vector3.ONE
	else:
		HitFx.burst(global_position + Vector3.UP * (BOWL_Y + 0.3), FLAME_COLOR, 18, 4.0, 1.4, -3.0, 0.7)
		_flame.scale = Vector3.ONE * 0.3
		var tw := create_tween()
		tw.tween_property(_flame, "scale", Vector3.ONE * 1.25, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_flame, "scale", Vector3.ONE, 0.3)
