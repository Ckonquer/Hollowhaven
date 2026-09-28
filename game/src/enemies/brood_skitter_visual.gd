extends Node3D
## Brood Skitter looks. setup({"sprout": bool}) BEFORE add_child picks one of two completely different builds:
##   Skitter (arachnophobia off): a small, low, stylised hollows-spider - a round dusky abdomen with pale
##     markings, a small head with four soft glowing eyes and eight thin high-kneed legs. About 0.65 m wide and
##     0.35 m tall. Rounded and toy-like rather than realistic.
##   Pale Sprout (arachnophobia on): a floating pale SEED - an upright ovoid with green stripes, a pointed tip,
##     two little leaves and a dot-eyed face, bobbing ~0.6 m above the ground with three hanging root tendrils.
##     No legs, no eyes cluster, no body segments: a tall narrow floating silhouette (~0.35 m wide, ~0.95 m tall).
## Faces -Z, local origin on the ground.
## States (set_state): idle / wander / chase / return (skitter: quick leg cycle; sprout: bob + tendril sway),
## telegraph (skitter: legs DRAW IN tight and the body crouches; sprout: the roots CURL UP under it), leap
## (skitter: legs stretched back; sprout: the front root lashes forward and down), recover / stunned (dazed
## wobble), flinch, dead. Telegraph tint: steady with reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

# Skitter
const BODY_COLOR := Color("5b4d6b")
const HEAD_COLOR := Color("4d4160")
const MARK_COLOR := Color("cfc6dc")
const LEG_COLOR := Color("6a5c7c")
const EYE_COLOR := Color("d8ff9e")
const BODY_Y := 0.2
const L1 := 0.24                     # femur
const L2 := 0.36                     # tibia
const ELEV := 40.0                   # femur elevation (degrees)
const DROP := 80.0                   # tibia angle below the horizon (degrees)
const SKITTER_TINT := Color(0.9, 0.3, 0.42)
# Pale Sprout
const SEED_COLOR := Color("efe9d8")
const STRIPE_COLOR := Color("b9d99a")
const ROOT_COLOR := Color("b39c80")
const SEED_Y := 0.68
const SPROUT_TINT := Color(0.86, 0.96, 0.8)

var sprout := false
var state: String = "idle"
var state_len: float = 0.0
var move_speed: float = 0.0
var preview_walk := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _body: Node3D
var _legs: Array = []                # skitter: [{hip, femur, knee, side, yaw}]
var _tendrils: Array = []            # sprout: tendril pivots
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func setup(params: Dictionary) -> void:
	sprout = bool(params.get("sprout", sprout))


func _ready() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	if sprout:
		_build_sprout()
	else:
		_build_skitter()


func is_sprout() -> bool:
	return sprout


func leg_count() -> int:
	return _legs.size()


func tendril_count() -> int:
	return _tendrils.size()


func body_height() -> float:
	return 0.95 if sprout else 0.35


# --- Skitter ----------------------------------------------------------------------------------------------

func _build_skitter() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	Kit.add(_root, _body, Vector3(0, BODY_Y, 0))
	var body_mat := Mat.outlined(Mat.toon(BODY_COLOR, {"rim": 0.55, "noise": 0.08}), 0.01)
	var abd := Kit.blob(0.17, body_mat, 41, 0.05, 0.85, 3)
	Kit.add(_body, abd, Vector3(0, 0.04, 0.13), Vector3.ZERO, Vector3(1.0, 1.0, 1.2))
	_tint_meshes.append(abd)
	var mark_mat := Mat.toon(MARK_COLOR, {"rim": 0.2, "noise": 0.0})
	for i in 2:
		Kit.add(_body, Kit.sphere(0.05 - 0.012 * float(i), mark_mat, 8, 10), Vector3(0, 0.17 - 0.02 * float(i), 0.08 + 0.1 * float(i)), Vector3.ZERO, Vector3(1.5, 0.25, 0.8))
	var head := Kit.blob(0.11, Mat.outlined(Mat.toon(HEAD_COLOR, {"rim": 0.5}), 0.01), 43, 0.04, 0.85, 3)
	Kit.add(_body, head, Vector3(0, 0.0, -0.11))
	_tint_meshes.append(head)
	var eye_mat := Mat.glow(EYE_COLOR, 1.6)
	for e in [Vector3(-0.035, 0.05, -0.2), Vector3(0.035, 0.05, -0.2), Vector3(-0.07, 0.035, -0.18), Vector3(0.07, 0.035, -0.18)]:
		var eye := Kit.sphere(0.018, eye_mat, 6, 8)
		eye.set_meta("no_flash", true)
		Kit.add(_body, eye, e)
	var leg_mat := Mat.outlined(Mat.toon(LEG_COLOR, {"rim": 0.45}), 0.005)
	var yaws := [50.0, 18.0, -14.0, -44.0]
	for side in [1.0, -1.0]:
		for i in 4:
			var hip := Node3D.new()
			hip.name = "Leg"
			Kit.add(_root, hip, Vector3(side * 0.07, BODY_Y, -0.08 + 0.06 * float(i)))
			var yaw: float = float(yaws[i]) * side
			hip.rotation.y = deg_to_rad(yaw)
			var femur := Node3D.new()
			hip.add_child(femur)
			var fm := Kit.capsule(0.022, L1, leg_mat)
			Kit.add(femur, fm, Vector3(side * L1 * 0.5, 0, 0), Vector3(0, 0, 90))
			var knee := Node3D.new()
			Kit.add(femur, knee, Vector3(side * L1, 0, 0))
			var tb := Kit.capsule(0.018, L2, leg_mat)
			Kit.add(knee, tb, Vector3(side * L2 * 0.5, 0, 0), Vector3(0, 0, 90))
			femur.rotation.z = side * deg_to_rad(ELEV)                   # rest pose: feet on the ground
			knee.rotation.z = -side * deg_to_rad(ELEV + DROP)
			_legs.append({"hip": hip, "femur": femur, "knee": knee, "side": side, "yaw": deg_to_rad(yaw), "index": i})


func _animate_skitter(delta: float, speed: float) -> void:
	var draw := 0.0                  # 0 = relaxed, 1 = legs drawn in tight
	var stretch := 0.0               # leap: legs stretched back
	var body_y := BODY_Y
	var tilt := Vector3.ZERO
	var gait := 0.0
	match state:
		"telegraph":
			draw = clampf(_st / 0.3, 0.0, 1.0)
			body_y -= 0.07 * draw
			tilt.x = 0.12 * draw
		"leap":
			stretch = 1.0
			tilt.x = -0.3
		"recover", "stunned":
			tilt.z = sin(_st * 6.0) * 0.18
		"flinch":
			tilt.x = -0.4 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			draw = 1.0
			tilt.z = PI * 0.9
		_:
			if speed > 0.3:
				gait = 1.0
	var k_s := 1.0 - exp(-18.0 * delta)
	_root.position.y = lerpf(_root.position.y, body_y - BODY_Y, k_s)
	_body.rotation = _body.rotation.lerp(tilt, k_s)
	var ph := _t * (3.0 + speed * 1.2) * TAU
	for l in _legs:
		var hip := l["hip"] as Node3D
		var femur := l["femur"] as Node3D
		var knee := l["knee"] as Node3D
		var side: float = l["side"]
		var idx: int = l["index"]
		var step := sin(ph + float(idx) * PI * 0.5 + (0.0 if side > 0.0 else PI)) * 0.25 * gait
		var yaw: float = l["yaw"] * (1.0 - 0.55 * draw) + step - stretch * side * 0.5
		var elev := deg_to_rad(ELEV + 28.0 * draw - 25.0 * stretch)
		var drop := deg_to_rad(DROP + 20.0 * draw - 50.0 * stretch)
		hip.rotation.y = lerp_angle(hip.rotation.y, yaw, k_s)
		femur.rotation.z = lerpf(femur.rotation.z, side * elev, k_s)
		knee.rotation.z = lerpf(knee.rotation.z, -side * (elev + drop), k_s)


# --- Pale Sprout -----------------------------------------------------------------------------------------

func _build_sprout() -> void:
	_body = Node3D.new()
	_body.name = "Seed"
	Kit.add(_root, _body, Vector3(0, SEED_Y, 0))
	var seed_mat := Mat.outlined(Mat.toon(SEED_COLOR, {"rim": 0.6, "noise": 0.06}), 0.012)
	var seed := Kit.sphere(0.16, seed_mat, 14, 18)
	Kit.add(_body, seed, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.3, 0.9))
	_tint_meshes.append(seed)
	var tip := Kit.cone(0.07, 0.16, seed_mat, 10)
	Kit.add(_body, tip, Vector3(0, 0.26, 0))
	_tint_meshes.append(tip)
	var stripe_mat := Mat.toon(STRIPE_COLOR, {"rim": 0.3, "noise": 0.0})
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		Kit.add(_body, Kit.sphere(0.12, stripe_mat, 8, 12), Vector3(sin(a) * 0.1, 0.0, cos(a) * 0.1), Vector3(0, rad_to_deg(a), 0), Vector3(0.12, 1.5, 0.5))
	var leaf_mat := Mat.outlined(Mat.toon(Palette.FOLIAGE_LIGHT, {"rim": 0.4}), 0.008)
	for s in [-1.0, 1.0]:
		Kit.add(_body, Kit.sphere(0.08, leaf_mat, 8, 10), Vector3(s * 0.07, 0.34, 0), Vector3(0, 0, s * -35.0), Vector3(1.0, 0.18, 0.55))
	var ink := Mat.toon(Palette.UI_INK, {"rim": 0.0, "noise": 0.0})
	for s in [-1.0, 1.0]:
		Kit.add(_body, Kit.sphere(0.022, ink, 6, 8), Vector3(s * 0.05, 0.04, -0.135))
	Kit.add(_body, Kit.sphere(0.03, Mat.toon(Palette.BLOSSOM, {"noise": 0.0}), 6, 8), Vector3(0, -0.02, -0.14), Vector3.ZERO, Vector3(1.4, 0.4, 0.4))
	var root_mat := Mat.outlined(Mat.toon(ROOT_COLOR, {"rim": 0.35, "noise": 0.15}), 0.006)
	for i in 3:
		var a := TAU * float(i) / 3.0 + PI       # one tendril at the front (-Z)
		var piv := Node3D.new()
		piv.name = "Tendril"
		Kit.add(_body, piv, Vector3(sin(a) * 0.06, -0.18, cos(a) * 0.06))
		var seg := piv
		for j in 3:
			var cap := Kit.capsule(0.022 - 0.004 * float(j), 0.13, root_mat)
			Kit.add(seg, cap, Vector3(0, -0.06, 0))
			if j < 2:
				var nxt := Node3D.new()
				Kit.add(seg, nxt, Vector3(0, -0.11, 0))
				seg = nxt
		_tendrils.append(piv)


func _animate_sprout(delta: float) -> void:
	var curl := 0.0
	var lash := 0.0
	var bob := sin(_t * 2.2) * 0.05
	var tilt := Vector3.ZERO
	match state:
		"telegraph":
			curl = clampf(_st / 0.3, 0.0, 1.0)
			tilt.x = -0.15 * curl
		"leap":
			lash = clampf(_st / 0.2, 0.0, 1.0)
			tilt.x = 0.35
		"recover", "stunned":
			tilt.z = sin(_st * 5.0) * 0.2
			bob = -0.15 + sin(_t * 1.5) * 0.02
		"flinch":
			tilt.x = -0.4 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			curl = 1.0
			bob = -0.3
	var k_s := 1.0 - exp(-16.0 * delta)
	_body.position.y = lerpf(_body.position.y, SEED_Y + bob, k_s)
	_body.rotation = _body.rotation.lerp(tilt, k_s)
	for i in _tendrils.size():
		var piv := _tendrils[i] as Node3D
		var sway := sin(_t * 2.0 + float(i) * 2.1) * 0.18 * (1.0 - curl)
		var want := Vector3(sway, 0.0, cos(_t * 1.7 + float(i)) * 0.12 * (1.0 - curl))
		var scl := 1.0 - 0.55 * curl                         # roots curl up tight under the seed
		if i == 0 and lash > 0.0:
			want = Vector3(1.2 * lash, 0.0, 0.0)           # the front root lashes forward and down
			scl = 1.0 + 1.6 * lash
		piv.rotation = piv.rotation.lerp(want, k_s)
		piv.scale = piv.scale.lerp(Vector3(1.0, scl, 1.0), k_s)


# --- Shared ---------------------------------------------------------------------------------------------

func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	else:
		set_state(anim, 1.0)


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
	if sprout:
		_animate_sprout(delta)
	else:
		_animate_skitter(delta, speed)
	var tint := 0.0
	if state == "telegraph":
		var k := clampf(_st / 0.3, 0.0, 1.0)
		if HitFx.reduce_flashing():
			tint = 0.3 * k
		else:
			tint = 0.22 + 0.2 * (0.5 + 0.5 * sin(_st * 20.0))
	_apply_tint(tint)


func _apply_tint(tint: float) -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	elif tint > 0.0:
		c = Color(SPROUT_TINT if sprout else SKITTER_TINT, clampf(tint, 0.0, 1.0))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
