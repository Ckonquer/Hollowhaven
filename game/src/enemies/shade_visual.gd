extends Node3D
## The Hollow Shade look (arachnophobia ON): a hooded, drifting shadow figure with a pale, blank
## mask and long wispy arms. Clearly not an arachnid: one body, a hood, two arms, no legs.
## Faces -Z, upright (it does not flip onto ceilings; it hangs just beneath them), origin at the
## bottom of its hem. setup({"scale": 2.4, "boss": true}) for the Hollow Mother.
## States: idle, move, telegraph (arms rise and spread, mask tilts, eyes kindle), lunge, recoil
## (arms shield the mask), stunned (slumped, arms limp), shriek, dead.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

var surface_aligned := false          # stays upright; hangs beneath ceilings
const ROBE_COLOR := Color("262233")
const RIM_COLOR := Color(0.62, 0.66, 0.95)
const MASK_COLOR := Color("efe6d6")
const FINGER_COLOR := Color("d9d0c2")
const EYE_COLOR := Color("bfe6ff")
const EYE_HOT := Color("f2fbff")
const MARK_COLOR := Color("8f7aa8")
const HEIGHT := 1.95
const HOVER := 0.22

var size_scale: float = 1.0
var is_boss := false
var state: String = "idle"
var state_len: float = 0.0
var move_speed: float = 0.0
var clinging := false
var preview_walk := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _float: Node3D
var _robe: MeshInstance3D
var _head: Node3D
var _mask: Node3D
var _arms: Array = []          # [{shoulder, segs: [Node3D], side}]
var _eyes: Array = []
var _eye_mat: Material
var _eye_hot_mat: Material
var _eye_hot := false
var _smoke: CPUParticles3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false

static var _robe_mesh: ArrayMesh
static var _robe_mat: Material


func setup(params: Dictionary) -> void:
	size_scale = float(params.get("scale", size_scale))
	is_boss = bool(params.get("boss", is_boss))


func _ready() -> void:
	_build()


func body_height() -> float:
	return HEIGHT * size_scale


static func robe_material() -> Material:
	if _robe_mat == null:
		var m: ShaderMaterial = Mat.toon(ROBE_COLOR, {"rim": 1.1, "noise": 0.1, "softness": 0.18, "emission": Color(0.08, 0.07, 0.16), "emission_energy": 0.5}).duplicate()
		m.set_shader_parameter("rim_color", RIM_COLOR)
		_robe_mat = Mat.outlined(m, 0.014, Color(0.05, 0.04, 0.08))
	return _robe_mat


## Cloak built as a surface of revolution with a tattered, wavy hem.
static func robe_mesh() -> ArrayMesh:
	if _robe_mesh != null:
		return _robe_mesh
	# profile: (radius, height) from hem to neck
	var prof := [Vector2(0.44, 0.0), Vector2(0.4, 0.25), Vector2(0.33, 0.6), Vector2(0.27, 0.95), Vector2(0.25, 1.18),
		Vector2(0.27, 1.3), Vector2(0.22, 1.42), Vector2(0.12, 1.5), Vector2(0.0, 1.53)]
	var segs := 20
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for r in prof.size():
		var ring: Array = []
		for s in segs + 1:
			var a := TAU * float(s) / float(segs)
			var p: Vector2 = prof[r]
			var y := p.y
			var rad := p.x
			if r == 0:
				y += 0.07 * sin(a * 5.0) + 0.035 * sin(a * 11.0 + 1.3) - 0.05
				rad += 0.03 * sin(a * 7.0)
			elif r == 1:
				y += 0.03 * sin(a * 5.0)
			ring.append(Vector3(cos(a) * rad, y, sin(a) * rad))
		rings.append(ring)
	for r in prof.size() - 1:
		for s in segs:
			var a: Vector3 = rings[r][s]
			var b: Vector3 = rings[r][s + 1]
			var c: Vector3 = rings[r + 1][s + 1]
			var d: Vector3 = rings[r + 1][s]
			# Godot front faces are clockwise as seen from outside.
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	_robe_mesh = st.commit()
	return _robe_mesh


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_eye_mat = Mat.glow(EYE_COLOR, 2.2)
	_eye_hot_mat = Mat.glow(EYE_HOT, 5.0)
	var rm := robe_material()
	_root = Node3D.new()
	add_child(_root)
	_root.scale = Vector3.ONE * size_scale
	_float = Node3D.new()
	_root.add_child(_float)
	_float.position.y = HOVER
	_robe = MeshInstance3D.new()
	_robe.mesh = robe_mesh()
	_robe.material_override = rm
	_float.add_child(_robe)
	_tint_meshes.append(_robe)
	# Hood
	_head = Node3D.new()
	_float.add_child(_head)
	_head.position = Vector3(0, 1.55, 0.02)
	var hood := Kit.blob(0.27, rm, 5, 0.06, 1.18, 3)
	_head.add_child(hood)
	_tint_meshes.append(hood)
	var tip := Kit.cone(0.13, 0.32, rm, 10)
	Kit.add(_head, tip, Vector3(0, 0.2, 0.17), Vector3(55.0, 0, 0))
	var hollow := Kit.sphere(0.2, Mat.toon(Color("07060b"), {"rim": 0.0, "noise": 0.0}), 12, 16)
	Kit.add(_head, hollow, Vector3(0, -0.02, -0.14), Vector3.ZERO, Vector3(0.95, 1.12, 0.6))
	# Pale mask with hollow eyes and faint painted tear marks
	_mask = Node3D.new()
	Kit.add(_head, _mask, Vector3(0, -0.03, -0.235))
	var mask := Kit.sphere(0.15, Mat.outlined(Mat.toon(MASK_COLOR, {"rim": 0.25, "noise": 0.03, "emission": MASK_COLOR, "emission_energy": 0.28}), 0.008), 14, 18)
	mask.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_mask, mask, Vector3.ZERO, Vector3.ZERO, Vector3(0.88, 1.12, 0.42))
	_tint_meshes.append(mask)
	var hole_mat := Mat.toon(Color("0a080e"), {"rim": 0.0, "noise": 0.0})
	var mark_mat := Mat.toon(MARK_COLOR, {"rim": 0.0, "noise": 0.0})
	for sx in [-1.0, 1.0]:
		var hole := Kit.sphere(0.04, hole_mat, 8, 10)
		Kit.add(_mask, hole, Vector3(sx * 0.052, 0.035, -0.052), Vector3(0, 0, sx * 18.0), Vector3(1.25, 0.7, 0.4))
		var eye := Kit.sphere(0.013, _eye_mat, 6, 8)
		eye.set_meta("no_flash", true)
		Kit.add(_mask, eye, Vector3(sx * 0.052, 0.033, -0.066))
		_eyes.append(eye)
		var tear := Kit.sphere(0.012, mark_mat, 6, 8)
		Kit.add(_mask, tear, Vector3(sx * 0.055, -0.03, -0.058), Vector3.ZERO, Vector3(0.7, 3.0, 0.4))
	# Long wispy arms: 4 tapering segments + long pale fingers
	var finger_mat := Mat.outlined(Mat.toon(FINGER_COLOR, {"rim": 0.3}), 0.005)
	for sx in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		Kit.add(_float, shoulder, Vector3(sx * 0.27, 1.3, -0.02))
		var segs: Array = []
		var parent: Node3D = shoulder
		for i in 4:
			var seg := Node3D.new()
			Kit.add(parent, seg, Vector3(0, -0.28 if i > 0 else 0.0, 0))
			var r := 0.06 - 0.01 * float(i)
			var piece := Kit.capsule(r, 0.34, rm)
			Kit.add(seg, piece, Vector3(0, -0.14, 0))
			_tint_meshes.append(piece)
			segs.append(seg)
			parent = seg
		var hand := Node3D.new()
		Kit.add(parent, hand, Vector3(0, -0.3, 0))
		for f in 4:
			var finger := Kit.cone(0.014, 0.24, finger_mat, 6)
			Kit.add(hand, finger, Vector3((float(f) - 1.5) * 0.022, -0.1, 0), Vector3(180.0, 0, (float(f) - 1.5) * 9.0))
		_arms.append({"shoulder": shoulder, "segs": segs, "side": sx})
	# Trailing smoke at the hem
	_smoke = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 8
	sm.rings = 4
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.vertex_color_is_srgb = true
	sm.material = pm
	_smoke.mesh = sm
	_smoke.amount = 18
	_smoke.lifetime = 1.1
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_smoke.emission_ring_axis = Vector3.UP
	_smoke.emission_ring_radius = 0.38
	_smoke.emission_ring_inner_radius = 0.2
	_smoke.emission_ring_height = 0.05
	_smoke.direction = Vector3.DOWN
	_smoke.spread = 40.0
	_smoke.initial_velocity_min = 0.05
	_smoke.initial_velocity_max = 0.25
	_smoke.gravity = Vector3(0, 0.1, 0)
	_smoke.scale_amount_min = 0.8
	_smoke.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.1, 0.08, 0.16, 0.0))
	ramp.set_color(1, Color(0.1, 0.08, 0.16, 0.0))
	ramp.add_point(0.25, Color(0.1, 0.08, 0.16, 0.55))
	_smoke.color_ramp = ramp
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float.add_child(_smoke)
	_smoke.position.y = 0.05
	_smoke.emitting = true


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func set_clinging(on: bool) -> void:
	clinging = on


func play_anim(anim: String) -> void:
	match anim:
		"walk":
			preview_walk = true
			set_state("move")
		_:
			set_state(anim, 1.5)


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := move_speed
	if preview_walk:
		speed = 2.0
	var moving := speed > 0.2 or state == "move"
	var hover := HOVER + sin(_t * 1.4) * 0.05
	var lean := 0.0
	var head_pitch := 0.0
	var head_roll := sin(_t * 0.9) * 0.05
	var arm_raise := 0.0           # shoulder lift (rad, outward)
	var arm_fwd := 0.0             # shoulder pitch forward (rad)
	var wave_amp := 0.12
	var eye_hot := false
	var tremble := 0.0
	var scale_y := 1.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.3, 0.0, 1.0)
			arm_raise = 1.9 * k
			arm_fwd = 0.5 * k
			head_pitch = -0.2 * k
			head_roll = 0.35 * k
			hover += 0.18 * k
			wave_amp = 0.25
			eye_hot = true
			tremble = 0.01 * k
			scale_y = 1.0 + 0.06 * k
		"lunge":
			arm_fwd = 1.5
			arm_raise = 0.4
			lean = 0.45
			wave_amp = 0.05
			eye_hot = true
		"recoil":
			var k := 1.0 - clampf(_st / 0.7, 0.0, 1.0)
			arm_fwd = 2.3 * k
			arm_raise = 0.9 * k
			head_pitch = 0.35 * k
			lean = -0.3 * k
			tremble = 0.012 * k
		"stunned":
			hover = 0.02
			lean = 0.35
			head_pitch = 0.5
			head_roll = 0.3 + sin(_t * 2.0) * 0.05
			wave_amp = 0.04
			scale_y = 0.9
		"shriek":
			var k := clampf(_st / 0.3, 0.0, 1.0)
			arm_raise = 2.3 * k
			head_pitch = -0.55 * k
			lean = -0.2 * k
			tremble = 0.02 * k
			eye_hot = true
		"dead":
			hover = 0.0
			lean = 0.4
		_:
			if moving:
				lean = 0.22
				arm_fwd = -0.35
				wave_amp = 0.2
	var k_s := 1.0 - exp(-9.0 * delta)
	var jit := Vector3(sin(_t * 71.0), 0.0, sin(_t * 53.0)) * tremble
	_float.position = _float.position.lerp(Vector3(0, hover, 0), k_s) + jit
	_float.rotation.x = lerpf(_float.rotation.x, -lean, k_s)
	_float.scale = _float.scale.lerp(Vector3(1.0, scale_y, 1.0), k_s)
	_head.rotation.x = lerpf(_head.rotation.x, head_pitch, k_s)
	_head.rotation.z = lerpf(_head.rotation.z, head_roll, k_s)
	for a in _arms:
		var side: float = float(a["side"])
		var sh := a["shoulder"] as Node3D
		sh.rotation.z = lerpf(sh.rotation.z, side * (0.12 + arm_raise), k_s)
		sh.rotation.x = lerpf(sh.rotation.x, arm_fwd + sin(_t * 1.1 + side) * 0.05, k_s)
		var segs: Array = a["segs"]
		for i in range(1, segs.size()):
			var sg := segs[i] as Node3D
			sg.rotation.x = sin(_t * 1.8 - float(i) * 0.7 + side) * wave_amp * float(i) * 0.6
			sg.rotation.z = side * (0.05 + sin(_t * 1.3 - float(i) * 0.9) * wave_amp * 0.4)
	if eye_hot != _eye_hot:
		_eye_hot = eye_hot
		for e in _eyes:
			(e as MeshInstance3D).material_override = _eye_hot_mat if eye_hot else _eye_mat
			(e as MeshInstance3D).scale = Vector3.ONE * (1.6 if eye_hot else 1.0)
	_apply_tint()


func _apply_tint() -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.6))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
