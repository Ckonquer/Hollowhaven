extends Node3D
## Gloomling look: a small hovering shadow imp with glowing amber eyes, swept-back ears, little
## horns, thin clawed arms and a smoky tail instead of legs, shedding soft dark wisps. Faces -Z.
## States: idle / wander / chase / return (hover + sway), telegraph (eyes flare red-hot and grow,
## claw arm winds back), attack (swipe), recover (slumped, eyes dim), flinch, backoff, dead.
## set_exposed(true) = caught in light: eyes squint to slits, body shivers, wisps thin out.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BODY_COLOR := Color("1b1526")
const RIM_COLOR := Color(0.66, 0.54, 1.0)
const GLOW_COLOR := Color(0.2, 0.1, 0.34)
const CLAW_COLOR := Color("c3b4d6")
const EYE_IDLE := Color("ffcf5a")
const EYE_FLARE := Color("ff5a3a")
const WISP_COLOR := Color(0.16, 0.1, 0.26, 0.6)
const HOVER_Y := 0.34

var state: String = "idle"
var state_len: float = 0.0
var exposed := false
var move_speed: float = 0.0
var preview_walk := false
var fade: float = 1.0                 # 1 = solid, 0 = dissolved (defeat)

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _float: Node3D
var _body: Node3D
var _head: Node3D
var _eyes: Array = []
var _arms: Array = []
var _tail: Array = []
var _wisps: CPUParticles3D
var _shadow: MeshInstance3D
var _eye_idle_mat: Material
var _eye_flare_mat: Material
var _eye_dim_mat: Material
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false
var _eye_mode := ""

static var _body_mat: Material
static var _smoke_mat: Material
static var _wisp_mesh: SphereMesh
static var _wisp_ramp: Gradient
static var _wisp_curve: Curve


func _ready() -> void:
	_build()


static func body_material() -> Material:
	if _body_mat == null:
		var m: ShaderMaterial = Mat.toon(BODY_COLOR, {"rim": 1.3, "noise": 0.1, "softness": 0.2, "emission": GLOW_COLOR, "emission_energy": 0.28}).duplicate()
		m.set_shader_parameter("rim_color", RIM_COLOR)
		_body_mat = Mat.outlined(m, 0.012, Color(0.06, 0.03, 0.09))
	return _body_mat


## Semi-transparent smoky material for the tail tip.
static func smoke_material() -> Material:
	if _smoke_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.13, 0.09, 0.2, 0.55)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_receive_shadows = true
		_smoke_mat = m
	return _smoke_mat


static func _wisp_resources() -> void:
	if _wisp_mesh != null:
		return
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.disable_receive_shadows = true
	_wisp_mesh = SphereMesh.new()
	_wisp_mesh.radius = 0.07
	_wisp_mesh.height = 0.14
	_wisp_mesh.radial_segments = 8
	_wisp_mesh.rings = 4
	_wisp_mesh.material = m
	_wisp_ramp = Gradient.new()
	_wisp_ramp.set_color(0, Color(WISP_COLOR, 0.0))
	_wisp_ramp.set_color(1, Color(WISP_COLOR, 0.0))
	_wisp_ramp.add_point(0.2, WISP_COLOR)
	_wisp_ramp.add_point(0.6, Color(WISP_COLOR, 0.35))
	_wisp_curve = Curve.new()
	_wisp_curve.add_point(Vector2(0.0, 0.5))
	_wisp_curve.add_point(Vector2(0.4, 1.0))
	_wisp_curve.add_point(Vector2(1.0, 0.3))


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_eye_idle_mat = Mat.glow(EYE_IDLE, 2.6)
	_eye_flare_mat = Mat.glow(EYE_FLARE, 5.5)
	_eye_dim_mat = Mat.glow(EYE_IDLE.darkened(0.4), 1.1)
	var bm := body_material()
	# Soft contact shadow so the floating imp reads grounded
	_shadow = Kit.cylinder(0.3, 0.3, 0.01, Mat.transparent(Color(0.04, 0.02, 0.06, 0.45), true), 20)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.set_meta("no_flash", true)
	add_child(_shadow)
	_shadow.position.y = 0.02
	_float = Node3D.new()
	add_child(_float)
	_float.position.y = HOVER_Y
	_body = Node3D.new()
	_float.add_child(_body)
	_body.position.y = 0.36
	var torso := Kit.blob(0.25, bm, 21, 0.16, 1.1, 3)
	_body.add_child(torso)
	_tint_meshes.append(torso)
	# Smoky tail: shrinking lumps trailing down, the last one see-through
	for i in 3:
		var r := 0.18 - float(i) * 0.05
		var lump := Kit.blob(r, bm if i < 2 else smoke_material(), 30 + i, 0.3, 1.25, 2)
		Kit.add(_float, lump, Vector3(0.0, 0.16 - float(i) * 0.14, 0.05 * float(i)))
		_tail.append(lump)
		if i < 2:
			_tint_meshes.append(lump)
	# Head: big for a small body (reads cute-creepy), swept-back ears, stubby horns
	_head = Node3D.new()
	_body.add_child(_head)
	_head.position = Vector3(0, 0.33, -0.04)
	var skull := Kit.blob(0.27, bm, 44, 0.08, 0.9, 3)
	_head.add_child(skull)
	_tint_meshes.append(skull)
	for sx in [-1.0, 1.0]:
		var horn := Kit.cone(0.05, 0.15, bm, 8)
		Kit.add(_head, horn, Vector3(sx * 0.1, 0.22, 0.04), Vector3(-25.0, 0.0, sx * -22.0))
		var ear := Kit.cone(0.075, 0.3, bm, 6)
		Kit.add(_head, ear, Vector3(sx * 0.25, 0.06, 0.06), Vector3(-35.0, 0.0, sx * -62.0), Vector3(1.0, 1.0, 0.4))
		var socket := Kit.sphere(0.075, Mat.toon(Color("0b0812"), {"rim": 0.0, "noise": 0.0}), 8, 12)
		Kit.add(_head, socket, Vector3(sx * 0.1, 0.0, -0.215), Vector3(0, 0, sx * -14.0), Vector3(1.3, 0.8, 0.45))
		var eye := Kit.sphere(0.058, _eye_idle_mat, 10, 14)
		Kit.add(_head, eye, Vector3(sx * 0.102, 0.004, -0.24), Vector3(0, 0, sx * -16.0), Vector3(1.3, 0.8, 0.55))
		eye.set_meta("no_flash", true)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_eyes.append(eye)
	# Thin arms ending in pale claws
	var claw_mat := Mat.outlined(Mat.toon(CLAW_COLOR, {"rim": 0.5}), 0.006)
	for sx in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		_body.add_child(shoulder)
		shoulder.position = Vector3(sx * 0.21, 0.08, -0.03)
		var arm := Kit.capsule(0.04, 0.4, bm)
		Kit.add(shoulder, arm, Vector3(0, -0.18, 0))
		var hand := Node3D.new()
		Kit.add(shoulder, hand, Vector3(0, -0.38, 0))
		for c in 3:
			var claw := Kit.cone(0.017, 0.13, claw_mat, 6)
			Kit.add(hand, claw, Vector3((float(c) - 1.0) * 0.03, -0.045, -0.02), Vector3(165.0, (float(c) - 1.0) * 20.0, 0.0))
		shoulder.rotation = Vector3(0.2, 0.0, sx * 0.25)
		_arms.append(shoulder)
	# Wisps shed from the edges
	_wisp_resources()
	_wisps = CPUParticles3D.new()
	_wisps.mesh = _wisp_mesh
	_wisps.amount = 12
	_wisps.lifetime = 1.3
	_wisps.local_coords = false
	_wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_wisps.emission_sphere_radius = 0.26
	_wisps.direction = Vector3.UP
	_wisps.spread = 35.0
	_wisps.initial_velocity_min = 0.15
	_wisps.initial_velocity_max = 0.45
	_wisps.gravity = Vector3(0.0, 0.25, 0.0)
	_wisps.damping_min = 0.3
	_wisps.damping_max = 0.8
	_wisps.scale_amount_min = 0.7
	_wisps.scale_amount_max = 1.5
	_wisps.scale_amount_curve = _wisp_curve
	_wisps.color_ramp = _wisp_ramp
	_wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wisps.set_meta("no_flash", true)
	_body.add_child(_wisps)
	_wisps.emitting = true


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func set_exposed(on: bool) -> void:
	exposed = on


func play_anim(anim: String) -> void:
	match anim:
		"walk":
			preview_walk = true
			set_state("chase")
		"exposed":
			exposed = true
			set_state("backoff", 1.3)
		_:
			set_state(anim, 1.2)


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := move_speed
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 4.0
	var bob := sin(_t * 2.6) * 0.05
	var lean := 0.0
	var eye_s := Vector3(1.3, 0.8, 0.55)
	var eye_mode := "idle"
	var arm_r := Vector3(0.2, 0.0, 0.25)
	var arm_l := Vector3(0.2, 0.0, -0.25)
	var body_s := Vector3.ONE
	var shiver := 0.0
	var head_tilt := 0.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.25, 0.0, 1.0)
			eye_s = Vector3(1.3, 0.8, 0.55) * (1.0 + 0.22 * k)
			eye_mode = "flare"
			arm_r = Vector3(-1.9 * k + 0.2, 0.3 * k, 0.5 * k + 0.25)     # right claw winds back and up
			lean = 0.18 * k
			body_s = Vector3(1.0 + 0.07 * k, 1.0 + 0.1 * k, 1.0 + 0.07 * k)
			bob *= 0.3
			head_tilt = -0.15 * k
			shiver = 0.006 * k
		"attack":
			var k := clampf(_st / 0.2, 0.0, 1.0)
			eye_mode = "flare"
			eye_s = Vector3(1.3, 0.8, 0.55) * 1.15
			arm_r = Vector3(lerpf(-1.7, 1.3, k), lerpf(0.3, -0.7, k), 0.3)   # swipe across
			lean = lerpf(0.18, -0.4, k)
		"recover":
			eye_mode = "dim"
			eye_s = Vector3(1.3, 0.55, 0.55)
			lean = 0.3
			bob = -0.06 + sin(_t * 1.5) * 0.02
			arm_r = Vector3(0.5, 0.0, 0.15)
			arm_l = Vector3(0.5, 0.0, -0.15)
			head_tilt = 0.25
		"flinch", "stunned":
			var f := 1.0 - clampf(_st / 0.32, 0.0, 1.0)
			lean = 0.45 * f
			shiver = 0.03 * f
			eye_s = Vector3(1.3, 0.3, 0.55)
		"backoff":
			shiver = 0.018
			lean = 0.3
			arm_r = Vector3(-0.9, 0.0, 0.5)
			arm_l = Vector3(-0.9, 0.0, -0.5)
		"dead":
			eye_mode = "dim"
		_:
			if speed > 0.4:
				lean = -0.22
				bob = sin(_t * 7.0) * 0.035
				arm_r = Vector3(0.8, 0.0, 0.35)
				arm_l = Vector3(0.8, 0.0, -0.35)
	if exposed and state != "dead":
		eye_s.y = minf(eye_s.y, 0.28)
		shiver = maxf(shiver, 0.015)
		if eye_mode == "idle":
			eye_mode = "dim"
	var k_s := 1.0 - exp(-14.0 * delta)
	_float.position = Vector3(sin(_t * 61.0) * shiver, HOVER_Y + bob, 0.0)
	_body.rotation.x = lerpf(_body.rotation.x, -lean, k_s)
	_body.scale = _body.scale.lerp(body_s * maxf(fade, 0.01), k_s)
	_head.rotation.x = lerpf(_head.rotation.x, head_tilt, k_s)
	_head.rotation.z = sin(_t * 1.7) * 0.06
	for i in _eyes.size():
		var e := _eyes[i] as MeshInstance3D
		e.scale = e.scale.lerp(eye_s, 1.0 - exp(-22.0 * delta))
	if eye_mode != _eye_mode:
		_eye_mode = eye_mode
		var em: Material = _eye_idle_mat
		if eye_mode == "flare":
			em = _eye_flare_mat
		elif eye_mode == "dim":
			em = _eye_dim_mat
		for e in _eyes:
			(e as MeshInstance3D).material_override = em
	var ar := _arms[1] as Node3D
	ar.rotation = ar.rotation.lerp(arm_r, 1.0 - exp(-(24.0 if state == "attack" else 12.0) * delta))
	var al := _arms[0] as Node3D
	al.rotation = al.rotation.lerp(arm_l, k_s)
	for i in _tail.size():
		var lump := _tail[i] as Node3D
		lump.position.x = sin(_t * 3.0 - float(i) * 0.8) * 0.04 * float(i + 1)
		lump.position.z = 0.05 * float(i) + (0.06 * float(i + 1) if speed > 0.4 else 0.0)
		lump.scale = Vector3.ONE * maxf(fade, 0.01)
	_wisps.speed_scale = 0.6 if exposed else 1.0
	_wisps.emitting = fade > 0.05
	_shadow.scale = Vector3.ONE * (0.85 - bob * 1.5) * maxf(fade, 0.01)
	_apply_tint()


func _apply_tint() -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.7))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
