extends Node3D
## Knotted Elder look: a huge thorn-root guardian (~3.1 m to the tip of its crown, ~1.7 m across the arms). A trunk of twisted
## roots on two root-cluster legs with splayed root toes, mossy shoulders, a knot-hole face with deep-set
## amber eyes, a crown of thorns, and two long root arms ending in root fingers that nearly reach the ground.
## Faces -Z, feet at y = 0.
## Each attack has its own readable pose AND tint colour (set_attack(kind) before set_state("telegraph")):
##   root_sweep  one arm swings out and up to the side, the trunk winds up (twists), amber tint
##   charge      feet planted wide, crouched and leaning in, head down, arms pulled back, the CROWN GLOWS, red tint
##   roots       both arms plunge down into the ground, the body bows low, green tint
## Other states: idle / wander / chase / return (heavy lumbering sway), sweep (the arm sweeps across the front),
## charge (leaning run), rooting (arms wrench up), recover (slumped, back open), stunned (dizzy stars), flinch, dead.
## Tints pulse, or stay steady with reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const HIP_Y := 1.0
const BARK := Color("6e5236")
const BARK_DARK := Color("4a3423")
const BARK_LIGHT := Color("8a6a48")
const THORN := Color("e3c08a")
const EYE := Color("ffb14a")
const CROWN_GLOW := Color("ff7a3d")
const SWEEP_TINT := Color(1.0, 0.72, 0.25)
const CHARGE_TINT := Color(0.98, 0.3, 0.2)
const ROOTS_TINT := Color(0.55, 0.9, 0.4)

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "root_sweep"
var move_speed: float = 0.0
var preview_walk := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _torso: Node3D
var _head: Node3D
var _crown: Node3D
var _legs: Array = []
var _arms: Array = []            # shoulder pivots [left, right]
var _forearms: Array = []
var _stars: Node3D
var _crown_meshes: Array = []
var _crown_mat: Material
var _crown_glow_mat: Material
var _crown_on := false
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 3.1


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	var bark := Mat.outlined(Mat.toon(BARK, {"rim": 0.35, "noise": 0.22}), 0.018)
	var bark_dark := Mat.outlined(Mat.toon(BARK_DARK, {"rim": 0.3, "noise": 0.22}), 0.016)
	var bark_light := Mat.outlined(Mat.toon(BARK_LIGHT, {"rim": 0.4, "noise": 0.2}), 0.016)
	var thorn := Mat.outlined(Mat.toon(THORN, {"rim": 0.3}), 0.01)
	var moss := Mat.outlined(Mat.toon(Palette.MOSS, {"rim": 0.4, "noise": 0.25}), 0.012)
	# Root-cluster legs with splayed toes
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg"
		Kit.add(_root, leg, Vector3(sx * 0.36, HIP_Y, 0))
		for j in 3:
			var off := Vector3((float(j) - 1.0) * 0.1, -0.5, (float(j % 2) - 0.5) * 0.12)
			var cap := Kit.capsule(0.13, 1.05, bark_dark if j == 1 else bark)
			Kit.add(leg, cap, off, Vector3((float(j) - 1.0) * 6.0, 0, sx * (4.0 + 4.0 * float(j))))
			_tint_meshes.append(cap)
		for j in 3:
			var ya := deg_to_rad(-40.0 + 40.0 * float(j) + sx * 25.0)
			var toe := Kit.cone(0.08, 0.42, bark_dark, 7)
			Kit.add(leg, toe, Vector3(sin(ya) * 0.22, -0.95, -cos(ya) * 0.22), Vector3(-80.0, rad_to_deg(ya), 0))
		_legs.append(leg)
	# Twisted trunk (pivots at the hips)
	_torso = Node3D.new()
	_torso.name = "Torso"
	Kit.add(_root, _torso, Vector3(0, HIP_Y, 0))
	var strands := [[Vector3(-0.14, 0.55, -0.08), Vector3(-8, 0, 12)], [Vector3(0.14, 0.55, -0.06), Vector3(-6, 0, -10)],
		[Vector3(-0.1, 0.55, 0.12), Vector3(8, 0, -9)], [Vector3(0.12, 0.55, 0.12), Vector3(9, 0, 11)]]
	for i in strands.size():
		var s: Array = strands[i]
		var cap := Kit.capsule(0.2, 1.25, bark if i % 2 == 0 else bark_dark)
		Kit.add(_torso, cap, s[0], s[1])
		_tint_meshes.append(cap)
	var chest := Kit.blob(0.5, bark_light, 61, 0.1, 0.85, 3)
	Kit.add(_torso, chest, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(1.25, 1.0, 0.9))
	_tint_meshes.append(chest)
	for sx in [-1.0, 1.0]:
		Kit.add(_torso, Kit.blob(0.24, moss, 63 + int(sx), 0.3, 0.6, 2), Vector3(sx * 0.46, 1.25, 0.02))
		Kit.add(_torso, Kit.sphere(0.12, Mat.outlined(Mat.toon(Palette.FOLIAGE, {"rim": 0.4}), 0.008), 8, 10), Vector3(sx * 0.52, 1.36, -0.08), Vector3(0, 0, sx * 30.0), Vector3(1.0, 0.25, 0.6))
	for tp in [Vector3(0.3, 0.7, 0.35), Vector3(-0.28, 0.9, 0.38), Vector3(0.05, 1.2, 0.4), Vector3(-0.35, 0.5, -0.3)]:
		Kit.add(_torso, Kit.cone(0.05, 0.22, thorn, 6), tp, Vector3(70.0 if tp.z > 0.0 else -70.0, 0, 0))
	# Head: knot-hole face, deep-set glowing eyes, crown of thorns
	_head = Node3D.new()
	_head.name = "Head"
	Kit.add(_torso, _head, Vector3(0, 1.48, -0.08))
	var head := Kit.blob(0.33, bark, 67, 0.12, 0.95, 3)
	_head.add_child(head)
	_tint_meshes.append(head)
	var hole := Mat.toon(Color("1c130d"), {"rim": 0.0, "noise": 0.0})
	for sx in [-1.0, 1.0]:
		Kit.add(_head, Kit.sphere(0.085, hole, 8, 10), Vector3(sx * 0.12, 0.05, -0.27), Vector3.ZERO, Vector3(1.0, 0.8, 0.5))
		var eye := Kit.sphere(0.04, Mat.glow(EYE, 2.0), 6, 8)
		eye.set_meta("no_flash", true)
		Kit.add(_head, eye, Vector3(sx * 0.12, 0.05, -0.3))
	Kit.add(_head, Kit.sphere(0.09, hole, 8, 10), Vector3(0, -0.14, -0.27), Vector3.ZERO, Vector3(1.4, 0.55, 0.5))
	_crown = Node3D.new()
	_crown.name = "Crown"
	Kit.add(_head, _crown, Vector3(0, 0.26, 0))
	_crown_mat = thorn
	_crown_glow_mat = Mat.glow(CROWN_GLOW, 2.2)
	for i in 9:
		var a := TAU * float(i) / 9.0
		var c := Kit.cone(0.055, 0.32 + 0.06 * float(i % 2), thorn, 7)
		Kit.add(_crown, c, Vector3(sin(a) * 0.24, 0.1, cos(a) * 0.24), Vector3(cos(a) * 25.0, 0, -sin(a) * 25.0))
		_crown_meshes.append(c)
	# Root arms (shoulder pivot + elbow pivot + root fingers)
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "Arm"
		Kit.add(_torso, arm, Vector3(sx * 0.58, 1.18, 0))
		var upper := Kit.capsule(0.14, 0.9, bark)
		Kit.add(arm, upper, Vector3(0, -0.4, 0))
		_tint_meshes.append(upper)
		var fore := Node3D.new()
		Kit.add(arm, fore, Vector3(0, -0.82, 0))
		var lower := Kit.capsule(0.12, 0.85, bark_dark)
		Kit.add(fore, lower, Vector3(0, -0.38, 0))
		_tint_meshes.append(lower)
		for j in 3:
			var fa := deg_to_rad(-30.0 + 30.0 * float(j))
			Kit.add(fore, Kit.cone(0.06, 0.38, bark_dark, 7), Vector3(sin(fa) * 0.08, -0.9, cos(fa) * 0.05 - 0.02), Vector3(180.0 + cos(fa) * 12.0, 0, rad_to_deg(fa) * 0.5))
		_arms.append(arm)
		_forearms.append(fore)
	# Dizzy stars (stunned)
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 4:
		var a := TAU * float(i) / 4.0
		Kit.add(_stars, Kit.sphere(0.07, star_mat, 6, 8), Vector3(cos(a) * 0.45, 0.0, sin(a) * 0.45))
	_stars.visible = false


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func set_attack(kind: String) -> void:
	attack_kind = kind


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	elif anim in ["root_sweep", "charge", "roots"]:
		set_attack(anim)
		set_state("telegraph", 1.4)
	else:
		set_state(anim, 1.4)


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func crown_glowing() -> bool:
	return _crown_on


## Current pose numbers (tests compare the three tells): {twist, lean, crouch, arm_l, arm_r, arm_out}.
func pose() -> Dictionary:
	return {"twist": _torso.rotation.y, "lean": -_torso.rotation.x, "crouch": -_root.position.y,
		"arm_l": (_arms[0] as Node3D).rotation.x, "arm_r": (_arms[1] as Node3D).rotation.x,
		"arm_out": (_arms[1] as Node3D).rotation.z}


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := move_speed
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 2.0
	var twist := 0.0
	var lean := 0.08
	var crouch := 0.0
	var arm_l := 0.12
	var arm_r := 0.12
	var arm_out := 0.0                 # right arm raised sideways (+ = out)
	var elbow := 0.2
	var head_x := 0.0
	var gait := 0.0
	var tint := 0.0
	var tint_col := SWEEP_TINT
	var crown := false
	match state:
		"telegraph":
			var k := clampf(_st / 0.4, 0.0, 1.0)
			match attack_kind:
				"charge":
					crouch = 0.22 * k
					lean = 0.08 + 0.35 * k
					head_x = 0.3 * k
					arm_l = 0.12 - 0.7 * k
					arm_r = 0.12 - 0.7 * k
					crown = true
					tint_col = CHARGE_TINT
				"roots":
					crouch = 0.3 * k
					lean = 0.08 + 0.55 * k
					arm_l = 0.12 + 0.95 * k       # both arms plunge down in front, into the ground
					arm_r = 0.12 + 0.95 * k
					elbow = 0.2 + 0.4 * k
					tint_col = ROOTS_TINT
				_:
					twist = 0.6 * k               # winds up to its right
					arm_out = 1.35 * k            # the right arm rises and curls out to the side
					arm_r = 0.12 + 0.3 * k
					elbow = 0.2 + 0.7 * k
					crouch = 0.08 * k
					tint_col = SWEEP_TINT
			if HitFx.reduce_flashing():
				tint = 0.3 * k
			else:
				tint = 0.22 + 0.2 * (0.5 + 0.5 * sin(_st * 16.0))
		"sweep":
			var s := clampf(_st / 0.3, 0.0, 1.0)
			twist = 0.6 - 1.3 * s
			arm_out = 1.35 - 0.3 * s
			arm_r = 0.42
			elbow = 0.3
			crouch = 0.1
		"charge":
			lean = 0.55
			crouch = 0.12
			head_x = 0.35
			arm_l = -0.9
			arm_r = -0.9
			gait = 1.6
			crown = true
		"rooting":
			var s := clampf(_st / 0.2, 0.0, 1.0)
			crouch = 0.3 - 0.2 * s
			lean = 0.63 - 0.4 * s
			arm_l = 1.07 - 0.9 * s
			arm_r = 1.07 - 0.9 * s
		"recover", "stunned":
			lean = 0.25 + sin(_st * 2.0) * 0.04
			head_x = 0.3
			arm_l = 0.3
			arm_r = 0.3
			crouch = 0.08
		"flinch":
			lean = -0.15
		"dead":
			lean = 0.5
			crouch = 0.3
		_:
			if speed > 0.3:
				gait = 1.0
			twist = sin(_t * 0.9) * 0.05
	var k_s := 1.0 - exp(-10.0 * delta)
	var ph := _t * (0.8 + speed * 0.3) * TAU
	_root.position.y = lerpf(_root.position.y, -crouch + absf(sin(ph)) * 0.04 * minf(gait, 1.0), k_s)
	_torso.rotation.x = lerpf(_torso.rotation.x, -lean, k_s)
	_torso.rotation.y = lerpf(_torso.rotation.y, twist, k_s)
	_torso.rotation.z = lerpf(_torso.rotation.z, sin(ph * 0.5) * 0.05 * minf(gait, 1.0), k_s)
	_head.rotation.x = lerpf(_head.rotation.x, -head_x, k_s)
	for i in _legs.size():
		var leg := _legs[i] as Node3D
		leg.rotation.x = lerpf(leg.rotation.x, sin(ph + (0.0 if i == 0 else PI)) * 0.35 * minf(gait, 1.3), k_s)
		leg.rotation.z = lerpf(leg.rotation.z, (-1.0 if i == 0 else 1.0) * -crouch * 0.4, k_s)
	var al := _arms[0] as Node3D
	var ar := _arms[1] as Node3D
	al.rotation.x = lerpf(al.rotation.x, arm_l + sin(ph) * 0.15 * minf(gait, 1.0), k_s)
	ar.rotation.x = lerpf(ar.rotation.x, arm_r - sin(ph) * 0.15 * minf(gait, 1.0), k_s)
	ar.rotation.z = lerpf(ar.rotation.z, arm_out, k_s)
	al.rotation.z = lerpf(al.rotation.z, -0.08, k_s)
	for f in _forearms:
		(f as Node3D).rotation.x = lerpf((f as Node3D).rotation.x, elbow, k_s)
	_set_crown(crown)
	_stars.visible = state == "stunned"
	if _stars.visible:
		_stars.rotation.y = _t * 3.0
		_stars.position.y = HIP_Y + 1.9 + _root.position.y
	_apply_tint(tint, tint_col)


func _set_crown(on: bool) -> void:
	if on == _crown_on:
		return
	_crown_on = on
	for c in _crown_meshes:
		(c as MeshInstance3D).material_override = _crown_glow_mat if on else _crown_mat


func _apply_tint(tint: float, col: Color) -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	elif tint > 0.0:
		c = Color(col, clampf(tint, 0.0, 1.0))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
