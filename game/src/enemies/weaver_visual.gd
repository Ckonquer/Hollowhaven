extends Node3D
## The Weaver look (arachnophobia OFF): a pale, stylised spider-thing. Unsettling but never gory:
## a smooth pale body with faint violet markings, a cluster of small glowing eyes, and eight long,
## thin, high-kneed legs that move with a slow, deliberate gait and small twitches.
## Faces -Z, local +Y is "away from the surface it stands on" (feet at y = 0), so the stalker can
## orient it to ceilings. setup({"scale": 2.6, "boss": true}) for the Matron.
## States: idle, move, telegraph (rattle: front legs raised, whole body trembling, eyes blaze),
## lunge, recoil, stunned (legs curled, twitching), shriek, cling (flatter pose), dead.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

var surface_aligned := true           # stalker orients local +Y to the surface normal
const BODY_COLOR := Color("ddd5e6")
const HEAD_COLOR := Color("cbc1d9")
const MARK_COLOR := Color("8e7ea8")
const LEG_COLOR := Color("d6cde2")
const LEG_TIP := Color("5e5272")
const JOINT_COLOR := Color("a497b6")
const EYE_COLOR := Color("d8ff9e")
const EYE_HOT := Color("f4ffd0")
const GLOW_TINT := Color("8f86a8")       # faint pale self-light so the silhouette reads in dark caves
const L1 := 0.7
const L2 := 0.95
const ELEV := 36.0
const DROP := 66.0
const BODY_Y := 0.46

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
var _gait: float = 0.0
var _root: Node3D
var _body: Node3D
var _abdomen: Node3D
var _legs: Array = []          # [{hip, femur, knee, base_yaw, side, index}]
var _eyes: Array = []
var _eye_mat: Material
var _eye_hot_mat: Material
var _eye_hot := false
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false
var _twitch_leg: int = -1
var _twitch_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(params: Dictionary) -> void:
	size_scale = float(params.get("scale", size_scale))
	is_boss = bool(params.get("boss", is_boss))


func _ready() -> void:
	_rng.randomize()
	_build()


## Height of the body above the surface (used to hang it from ceilings / place it on floors).
func body_height() -> float:
	return BODY_Y * size_scale


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_eye_mat = Mat.glow(EYE_COLOR, 2.4)
	_eye_hot_mat = Mat.glow(EYE_HOT, 5.0)
	_root = Node3D.new()
	add_child(_root)
	_root.scale = Vector3.ONE * size_scale
	_body = Node3D.new()
	_root.add_child(_body)
	_body.position.y = BODY_Y
	var body_mat := Mat.outlined(Mat.toon(BODY_COLOR, {"rim": 0.6, "noise": 0.08, "emission": GLOW_TINT, "emission_energy": 0.32}), 0.012)
	var head_mat := Mat.outlined(Mat.toon(HEAD_COLOR, {"rim": 0.55, "noise": 0.06, "emission": GLOW_TINT, "emission_energy": 0.26}), 0.012)
	_abdomen = Node3D.new()
	Kit.add(_body, _abdomen, Vector3(0, 0.08, 0.36))
	var abd := Kit.blob(0.33, body_mat, 7, 0.06, 0.85, 3)
	Kit.add(_abdomen, abd, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 1.35))
	_tint_meshes.append(abd)
	var mark_mat := Mat.toon(MARK_COLOR, {"rim": 0.2, "noise": 0.0})
	for i in 3:
		var mk := Kit.sphere(0.07 - 0.012 * float(i), mark_mat, 8, 12)
		Kit.add(_abdomen, mk, Vector3(0, 0.26 - 0.02 * float(i), -0.1 + 0.16 * float(i)), Vector3(-10.0 * float(i), 0, 0), Vector3(1.6, 0.25, 0.7))
	var head := Kit.blob(0.22, head_mat, 17, 0.05, 0.8, 3)
	Kit.add(_body, head, Vector3(0, 0.0, -0.13))
	_tint_meshes.append(head)
	# Eye cluster: two big, two medium, four small
	var eye_spots := [
		[Vector3(-0.055, 0.1, -0.33), 0.036], [Vector3(0.055, 0.1, -0.33), 0.036],
		[Vector3(-0.12, 0.08, -0.29), 0.024], [Vector3(0.12, 0.08, -0.29), 0.024],
		[Vector3(-0.04, 0.155, -0.3), 0.018], [Vector3(0.04, 0.155, -0.3), 0.018],
		[Vector3(-0.15, 0.13, -0.24), 0.016], [Vector3(0.15, 0.13, -0.24), 0.016]]
	for e in eye_spots:
		var eye := Kit.sphere(float(e[1]), _eye_mat, 8, 10)
		eye.set_meta("no_flash", true)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(_body, eye, e[0])
		_eyes.append(eye)
	# Small pale chelicerae (not fangs dripping anything, just little hooks)
	var palp_mat := Mat.outlined(Mat.toon(JOINT_COLOR), 0.006)
	for sx in [-1.0, 1.0]:
		var palp := Kit.capsule(0.03, 0.16, palp_mat)
		Kit.add(_body, palp, Vector3(sx * 0.06, -0.08, -0.3), Vector3(-30.0, 0, sx * 10.0))
	# Legs
	var leg_mat := Mat.outlined(Mat.toon(LEG_COLOR, {"rim": 0.5, "emission": GLOW_TINT, "emission_energy": 0.22}), 0.006)
	var tip_mat := Mat.outlined(Mat.toon(LEG_TIP, {"rim": 0.3}), 0.005)
	var joint_mat := Mat.toon(JOINT_COLOR, {"rim": 0.3})
	var yaws := [58.0, 22.0, -14.0, -46.0]
	for side in [1.0, -1.0]:
		for i in 4:
			var base_yaw: float = yaws[i] if side > 0.0 else 180.0 - float(yaws[i])
			var hip := Node3D.new()
			Kit.add(_body, hip, Vector3(side * 0.12, 0.02, -0.12 + 0.07 * float(i)))
			hip.rotation_degrees.y = base_yaw
			var femur := Node3D.new()
			hip.add_child(femur)
			femur.rotation_degrees.z = ELEV
			var seg1 := Kit.cylinder(0.022, 0.03, L1, leg_mat, 6)
			Kit.add(femur, seg1, Vector3(L1 * 0.5, 0, 0), Vector3(0, 0, -90))
			var knee := Node3D.new()
			Kit.add(femur, knee, Vector3(L1, 0, 0))
			knee.rotation_degrees.z = -(ELEV + DROP)
			Kit.add(knee, Kit.sphere(0.027, joint_mat, 6, 8))
			var seg2 := Kit.cylinder(0.012, 0.022, L2 * 0.62, leg_mat, 6)
			Kit.add(knee, seg2, Vector3(L2 * 0.31, 0, 0), Vector3(0, 0, -90))
			var seg3 := Kit.cylinder(0.004, 0.012, L2 * 0.38, tip_mat, 5)
			Kit.add(knee, seg3, Vector3(L2 * 0.81, 0, 0), Vector3(0, 0, -90))
			_legs.append({"hip": hip, "femur": femur, "knee": knee, "base_yaw": base_yaw, "side": side, "index": i})


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
		"cling":
			clinging = true
			set_state("idle")
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
	_gait += delta * (2.0 + minf(speed, 8.0) * 1.1) * (1.0 if moving else 0.0)
	var body_y := BODY_Y
	var body_pitch := 0.0
	var body_roll := 0.0
	var tremble := 0.0
	var eye_hot := false
	var abd_bob := sin(_t * 1.6) * 0.012
	var elev_add := 0.0
	var drop_add := 0.0
	var front_raise := 0.0
	var curl := 0.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.25, 0.0, 1.0)
			tremble = 0.012 * k
			front_raise = 55.0 * k
			body_pitch = -0.28 * k
			body_y += 0.08 * k
			eye_hot = true
		"lunge":
			front_raise = 25.0
			body_pitch = 0.2
			elev_add = -10.0
			eye_hot = true
		"recoil":
			var k := 1.0 - clampf(_st / 0.6, 0.0, 1.0)
			front_raise = 35.0 * k
			body_pitch = -0.35 * k
			body_y -= 0.1 * k
			tremble = 0.01 * k
		"stunned":
			curl = 1.0
			body_y = 0.22
			body_roll = sin(_t * 3.0) * 0.08
			tremble = 0.004
		"shriek":
			var k := clampf(_st / 0.3, 0.0, 1.0)
			front_raise = 70.0 * k
			body_pitch = -0.45 * k
			body_y += 0.12 * k
			tremble = 0.02 * k
			eye_hot = true
		"dead":
			curl = 1.0
			body_y = 0.2
	if clinging and state in ["idle", "move"]:
		elev_add -= 12.0
		drop_add -= 10.0
		body_y -= 0.1
	var k_s := 1.0 - exp(-12.0 * delta)
	var jitter := Vector3(sin(_t * 73.0), sin(_t * 91.0), sin(_t * 57.0)) * tremble
	_body.position = _body.position.lerp(Vector3(0, body_y, 0), k_s) + jitter
	_body.rotation.x = lerpf(_body.rotation.x, body_pitch, k_s)
	_body.rotation.z = lerpf(_body.rotation.z, body_roll, k_s)
	_abdomen.position.y = 0.08 + abd_bob
	# Idle twitches: one leg lifts and taps now and then
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = _rng.randf_range(0.7, 2.2)
		_twitch_leg = _rng.randi_range(0, 7) if not moving else -1
	for L in _legs:
		var idx: int = int(L["index"])
		var side: float = float(L["side"])
		var li: int = idx + (0 if side > 0.0 else 4)
		var group := (idx % 2 == 0) == (side > 0.0)
		var ph := _gait + (0.0 if group else PI)
		var yaw_off := 0.0
		var lift := 0.0
		if moving:
			yaw_off = sin(ph) * 13.0
			lift = maxf(cos(ph), 0.0) * 16.0
		elif li == _twitch_leg and state == "idle":
			lift = maxf(sin(_twitch_t * 9.0), 0.0) * 10.0
		var raise := front_raise if idx == 0 else (front_raise * 0.35 if idx == 1 else 0.0)
		var hip := L["hip"] as Node3D
		var femur := L["femur"] as Node3D
		var knee := L["knee"] as Node3D
		var target_yaw := float(L["base_yaw"]) + yaw_off * side
		var elev := ELEV + elev_add + lift + raise + tremble * 400.0 * sin(_t * 60.0 + float(li))
		var drop := DROP + drop_add + raise * 0.4
		if curl > 0.0:
			elev = lerpf(elev, 70.0 + sin(_t * 7.0 + float(li) * 1.7) * 6.0, curl)
			drop = lerpf(drop, 150.0, curl)
		hip.rotation_degrees.y = lerpf(hip.rotation_degrees.y, target_yaw, k_s)
		femur.rotation_degrees.z = lerpf(femur.rotation_degrees.z, elev, k_s)
		knee.rotation_degrees.z = lerpf(knee.rotation_degrees.z, -(elev + drop), k_s)
	if eye_hot != _eye_hot:
		_eye_hot = eye_hot
		for e in _eyes:
			(e as MeshInstance3D).material_override = _eye_hot_mat if eye_hot else _eye_mat
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
