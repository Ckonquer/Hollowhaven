extends Node3D
## Brambling look: a grumpy round thornball on stubby legs with cross little eyes, a leaf sprout
## and a berry crown. Cute-grumpy, never scary. Faces -Z. Built entirely from Kit primitives.
## States (set_state): idle / wander / chase / return (hop when moving), telegraph (crouch + wiggle
## + bristling thorns + pulsing red tint), attack (stretch-lunge, fangs), recover / stunned (dizzy
## wobble with orbiting stars), flinch (squash), dead. play_anim(name) = set_state(name) for previews.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BODY_R := 0.42
const BALL_Y := 0.55
const BODY_COLOR := Color("56803d")
const THORN_COLOR := Color("e3c08a")
const TELEGRAPH_TINT := Color(0.95, 0.2, 0.16)

var state: String = "idle"
var state_len: float = 0.0
var move_speed: float = 0.0          # used when the parent doesn't expose move_speed_now (previews)
var preview_walk := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _ball: Node3D
var _thorns: MeshInstance3D
var _pupils: Array = []
var _brows: Array = []
var _legs: Array = []
var _fangs: Node3D
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false

static var _thorn_mesh: ArrayMesh


func _ready() -> void:
	_build()


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	add_child(_root)
	# Stubby legs (stay under the ball; they squash with the crouch)
	var leg_mat := Mat.outlined(Mat.toon(Palette.BARK), 0.012)
	var foot_mat := Mat.outlined(Mat.toon(Palette.BARK_DARK), 0.012)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := Node3D.new()
			_root.add_child(leg)
			leg.position = Vector3(sx * 0.2, 0.28, sz * 0.15)
			var shin := Kit.capsule(0.07, 0.26, leg_mat)
			Kit.add(leg, shin, Vector3(0, -0.11, 0))
			var foot := Kit.sphere(0.085, foot_mat, 8, 12)
			Kit.add(leg, foot, Vector3(0, -0.24, -0.03), Vector3.ZERO, Vector3(1.0, 0.55, 1.25))
			_legs.append(leg)
	# The ball
	_ball = Node3D.new()
	_root.add_child(_ball)
	_ball.position.y = BALL_Y
	var body := Kit.blob(BODY_R, Mat.outlined(Mat.toon(BODY_COLOR, {"rim": 0.5, "noise": 0.12}), 0.016), 11, 0.1, 0.94, 3)
	_ball.add_child(body)
	_tint_meshes.append(body)
	_thorns = MeshInstance3D.new()
	_thorns.mesh = _get_thorn_mesh()
	_thorns.material_override = Mat.outlined(Mat.toon(THORN_COLOR, {"rim": 0.3}), 0.008)
	_ball.add_child(_thorns)
	_tint_meshes.append(_thorns)
	# Face
	var white := Mat.toon(Palette.FLOWER_WHITE, {"rim": 0.1, "noise": 0.0})
	var ink := Mat.toon(Palette.UI_INK, {"rim": 0.0, "noise": 0.0})
	for sx in [-1.0, 1.0]:
		var eye := Kit.sphere(0.092, Mat.outlined(white, 0.01), 12, 16)
		Kit.add(_ball, eye, Vector3(sx * 0.135, 0.07, -0.36), Vector3.ZERO, Vector3(1.0, 1.08, 0.6))
		var pupil := Node3D.new()
		Kit.add(_ball, pupil, Vector3(sx * 0.122, 0.055, -0.41))
		Kit.add(pupil, Kit.sphere(0.047, ink, 8, 12), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
		Kit.add(pupil, Kit.sphere(0.014, Mat.glow(Palette.FLOWER_WHITE, 1.2), 6, 8), Vector3(sx * -0.012, 0.02, -0.025))
		_pupils.append(pupil)
		var brow := Kit.box(Vector3(0.17, 0.045, 0.06), Mat.toon(Palette.BARK_DARK, {"noise": 0.0}))
		Kit.add(_ball, brow, Vector3(sx * 0.135, 0.19, -0.35), Vector3(-18.0, 0.0, sx * 24.0))
		_brows.append(brow)
		var blush := Kit.sphere(0.055, Mat.toon(Palette.BLOSSOM, {"noise": 0.0, "rim": 0.2}), 8, 12)
		Kit.add(_ball, blush, Vector3(sx * 0.215, -0.055, -0.345), Vector3(0, sx * 30.0, 0), Vector3(1.15, 0.5, 0.3))
	var mouth := Kit.box(Vector3(0.13, 0.026, 0.04), ink)
	Kit.add(_ball, mouth, Vector3(0, -0.105, -0.395), Vector3(-10, 0, 0))
	_fangs = Node3D.new()
	Kit.add(_ball, _fangs, Vector3(0, -0.12, -0.4))
	for sx in [-1.0, 1.0]:
		var fang := Kit.cone(0.022, 0.055, white, 8)
		Kit.add(_fangs, fang, Vector3(sx * 0.038, -0.02, 0), Vector3(180, 0, 0))
	# Leaf sprout + berry crown
	var leaf_mat := Mat.outlined(Mat.toon(Palette.FOLIAGE_LIGHT, {"rim": 0.4}), 0.01)
	var stem := Kit.cylinder(0.018, 0.024, 0.12, Mat.toon(Palette.FOLIAGE_DARK), 6)
	Kit.add(_ball, stem, Vector3(0.02, BODY_R + 0.03, 0.02), Vector3(0, 0, -8))
	for s in [-1.0, 1.0]:
		var leaf := Kit.sphere(0.09, leaf_mat, 8, 12)
		Kit.add(_ball, leaf, Vector3(0.02 + s * 0.07, BODY_R + 0.1, 0.02), Vector3(0, 30, s * -32.0), Vector3(1.0, 0.16, 0.5))
	var berry_mat := Mat.outlined(Mat.toon(Palette.BERRY, {"rim": 0.6, "specular": 0.5}), 0.01)
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var berry := Kit.sphere(0.052, berry_mat, 8, 12)
		Kit.add(_ball, berry, Vector3(cos(a) * 0.12 - 0.08, BODY_R - 0.03, sin(a) * 0.1 + 0.12))
	# Dizzy stars (recover / stunned)
	_stars = Node3D.new()
	_root.add_child(_stars)
	_stars.position.y = BALL_Y + BODY_R + 0.2
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var star := Kit.sphere(0.05, star_mat, 6, 8)
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, star, Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3))
	_stars.visible = false


## Thorns merged into one mesh (shared by every Brambling): cones along a Fibonacci sphere,
## leaving the face and the underside clear.
static func _get_thorn_mesh() -> ArrayMesh:
	if _thorn_mesh != null:
		return _thorn_mesh
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.2
	cone.radial_segments = 7
	cone.rings = 1
	var st := SurfaceTool.new()
	var n := 34
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		var y := 1.0 - (float(i) + 0.5) / float(n) * 2.0
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var th := golden * float(i)
		var dir := Vector3(cos(th) * r, y, sin(th) * r)
		if dir.y < -0.55:
			continue
		if dir.z < -0.45 and dir.y < 0.55 and dir.y > -0.5:
			continue                       # keep the face clear
		var len_s := 0.8 + 0.4 * absf(sin(float(i) * 12.9898))
		var b := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1.0, len_s, 1.0))
		st.append_from(cone, 0, Transform3D(b, dir * (BODY_R * 0.9 + 0.08 * len_s)))
	_thorn_mesh = st.commit()
	return _thorn_mesh


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	else:
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
	var ball_y := BALL_Y
	var sq := Vector3.ONE
	var tilt := Vector3.ZERO
	var fwd := 0.0
	var hop := 0.0
	var thorn_s := 1.0
	var tint := 0.0
	var fang_s := 1.0
	var pupil_s := 1.0
	var pupil_off := Vector2.ZERO
	var leg_swing := 0.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.18, 0.0, 1.0)
			ball_y -= 0.13 * k
			sq = Vector3(1.0 + 0.15 * k, 1.0 - 0.2 * k, 1.0 + 0.15 * k)
			tilt.z = sin(_st * 38.0) * 0.15 * k
			tilt.x = 0.12 * k
			thorn_s = 1.0 + 0.12 * k
			if HitFx.reduce_flashing():
				tint = 0.3 * k                        # steady red tint, no strobing (comfort)
			else:
				var pulse := 0.5 + 0.5 * sin(_st * 22.0)
				tint = 0.26 + 0.24 * pulse
			pupil_s = 0.75
		"attack":
			sq = Vector3(0.9, 0.9, 1.3)
			tilt.x = -0.35
			fwd = -0.18
			fang_s = 1.8
			hop = 0.12 * sin(clampf(_st / 0.3, 0.0, 1.0) * PI)
		"recover", "stunned":
			tilt.x = sin(_st * 5.0) * 0.2
			tilt.z = cos(_st * 5.0) * 0.2
			pupil_off = Vector2(cos(_t * 9.0), sin(_t * 9.0)) * 0.018
			sq = Vector3(1.04, 0.95, 1.04)
		"flinch":
			var f := 1.0 - clampf(_st / 0.3, 0.0, 1.0)
			sq = Vector3(1.0 + 0.2 * f, 1.0 - 0.25 * f, 1.0 + 0.2 * f)
			tilt.x = 0.35 * f
			pupil_s = 0.6
		"dead":
			pupil_off = Vector2(cos(_t * 14.0), sin(_t * 14.0)) * 0.02
		_:
			if speed > 0.4:
				var freq := 1.8 + speed * 0.45
				var ph := _t * freq * TAU
				var h := absf(sin(ph * 0.5))
				hop = h * (0.1 + minf(speed, 5.0) * 0.022)
				var land := 1.0 - clampf(h * 4.0, 0.0, 1.0)
				sq = Vector3(1.0 + 0.1 * land, 1.0 - 0.12 * land + 0.06 * h, 1.0 + 0.1 * land)
				leg_swing = sin(ph) * 0.6
				tilt.x = -0.1
			else:
				sq = Vector3(1.0 - 0.02 * sin(_t * 2.4), 1.0 + 0.035 * sin(_t * 2.4), 1.0 - 0.02 * sin(_t * 2.4))
				tilt.z = sin(_t * 1.3) * 0.05
	var k_s := 1.0 - exp(-16.0 * delta)
	_root.position.y = lerpf(_root.position.y, hop, 0.5 if hop > _root.position.y else k_s)
	_ball.position = _ball.position.lerp(Vector3(0.0, ball_y, fwd), k_s)
	_ball.scale = _ball.scale.lerp(sq, k_s)
	_ball.rotation = _ball.rotation.lerp(tilt, k_s)
	_thorns.scale = _thorns.scale.lerp(Vector3.ONE * thorn_s, k_s)
	_fangs.scale = _fangs.scale.lerp(Vector3.ONE * fang_s, k_s)
	for i in _pupils.size():
		var pu := _pupils[i] as Node3D
		pu.scale = pu.scale.lerp(Vector3.ONE * pupil_s, k_s)
		var sx := -1.0 if i == 0 else 1.0
		pu.position = Vector3(sx * 0.122 + pupil_off.x, 0.055 + pupil_off.y, -0.41)
	for i in _legs.size():
		var leg := _legs[i] as Node3D
		var side := 1.0 if (i % 2 == 0) == (i < 2) else -1.0
		leg.rotation.x = lerpf(leg.rotation.x, leg_swing * side, k_s)
		leg.position.y = lerpf(leg.position.y, 0.28 - (BALL_Y - ball_y) * 0.6, k_s)
	_stars.visible = state == "recover" or state == "stunned"
	if _stars.visible:
		_stars.rotation.y = _t * 4.0
		_stars.position.y = _ball.position.y + BODY_R + 0.18 + sin(_t * 6.0) * 0.02
	_apply_tint(tint)


func _apply_tint(tint: float) -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	elif tint > 0.0:
		c = Color(TELEGRAPH_TINT, clampf(tint, 0.0, 1.0))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
