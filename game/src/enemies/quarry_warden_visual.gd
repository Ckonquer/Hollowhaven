extends Node3D
## Quarry Warden look: a broad, low stone guardian (~2.6 m wide, ~2.4 m tall) of copper-red quarry rock - two
## stumpy pillar legs, two massive arms with boulder fists, a small heavy-browed head sunk between the shoulders
## with amber eyes, and a humped SHELL of overlapping rock plates on its back with a cracked bronze BELL set into its
## front. Three pips on the bell rim count the pulses. Faces -Z, feet at y = 0: a wide, heavy, hunched silhouette.
## States (set_state): idle / wander / chase / return (a heavy knuckle-walk), telegraph + "slam" (rears up, both
## fists overhead, the bell glows, amber tint), slam, telegraph + "pulses" (fists planted, the bell hums and the three
## pips light one after another, pale tint), pulses (the bell swells with every pulse, one pip goes out each time),
## telegraph + "charge" (head down, a foot scrapes the ground, red tint), charge (leaning in, legs pumping),
## exposed (the shell plates SPLIT OPEN around the brightly glowing bell, it sags forward, dizzy stars - the big
## punish window), recover / stunned (slumps, the bell dims, stars), flinch, dead. set_phase(2): a faint glow in the
## crack from then on. play_anim(name) for previews. Tints stay steady with Settings reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const HIP_Y := 0.75
const ROCK := Color("b8674a")
const ROCK_DARK := Color("8a4a36")
const ROCK_LIGHT := Color("d08a62")
const SHELL := Color("7a4232")
const BRONZE := Color("c9933e")
const BELL_GLOW := Color("ffd27a")
const CRACK_GLOW := Color("ffb85a")
const EYE := Color("ffb14a")
const CRYSTAL := Color("cfe0ff")
const SLAM_TINT := Color(1.0, 0.66, 0.24)
const PULSE_TINT := Color(0.98, 0.9, 0.62)
const CHARGE_TINT := Color(0.98, 0.34, 0.2)
const PLATES := 6

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "slam"
var phase: int = 1
var pips_lit: int = 0
var preview_walk := false
var shell_open: float = 0.0            # 0 closed .. 1 split open (tests)

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _legs: Array = []
var _plates: Array = []            # [{"node", "home"}]
var _bell: Node3D
var _bell_core: MeshInstance3D
var _crack: MeshInstance3D
var _pips: Array = []
var _pip_on: Material
var _pip_off: Material
var _core_dim: Material
var _core_glow: Material
var _crack_dark: Material
var _crack_glow: Material
var _core_is_glow := false
var _crack_is_glow := false
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 2.4


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	var rock := Mat.outlined(Mat.toon(ROCK, {"rim": 0.4, "noise": 0.25}), 0.018)
	var rock_dark := Mat.outlined(Mat.toon(ROCK_DARK, {"rim": 0.35, "noise": 0.25}), 0.016)
	var shell_mat := Mat.outlined(Mat.toon(SHELL, {"rim": 0.35, "noise": 0.3}), 0.016)
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg"
		_root.add_child(leg)
		leg.position = Vector3(sx * 0.5, HIP_Y, 0.15)
		var l := Kit.blob(0.32, rock_dark, 61 + int(sx), 0.12, 1.5, 2)
		Kit.add(leg, l, Vector3(0, -0.27, 0))
		_tint_meshes.append(l)
		_legs.append(leg)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_root.add_child(_hips)
	_hips.position.y = HIP_Y
	_torso = Node3D.new()
	_torso.name = "Torso"
	_hips.add_child(_torso)
	var chest := Kit.blob(0.8, rock, 63, 0.1, 0.85, 3)
	Kit.add(_torso, chest, Vector3(0, 0.75, 0), Vector3.ZERO, Vector3(1.35, 1.0, 1.0))
	_tint_meshes.append(chest)
	Kit.add(_torso, Kit.blob(0.3, Mat.outlined(Mat.toon(ROCK_LIGHT, {"rim": 0.4, "noise": 0.2}), 0.012), 64, 0.15, 0.8, 2), Vector3(0.0, 0.45, -0.62))
	# Shell: overlapping plates humped over the back (split open when exposed)
	for i in PLATES:
		var a := -0.9 + 1.8 * float(i) / float(PLATES - 1)
		var home := Vector3(sin(a) * 0.62, 1.3 + cos(a) * 0.12, 0.35 + absf(sin(a)) * 0.05)
		var plate := Kit.blob(0.42, shell_mat, 70 + i, 0.18, 0.45, 2)
		Kit.add(_torso, plate, home, Vector3(-25.0, 0.0, -rad_to_deg(a) * 0.6), Vector3(1.0, 1.0, 1.15))
		_plates.append({"node": plate, "home": home})
		_tint_meshes.append(plate)
	# The cracked bronze bell set into the front of the shell, its glowing core, the crack and the three pips
	_bell = Node3D.new()
	_bell.name = "Bell"
	Kit.add(_torso, _bell, Vector3(0, 1.35, -0.45), Vector3(-15, 0, 0))
	var bronze := Mat.outlined(Mat.toon(BRONZE, {"rim": 0.5, "specular": 0.5}), 0.012)
	var bell_body := Kit.cylinder(0.2, 0.42, 0.55, bronze, 18)
	_bell.add_child(bell_body)
	_tint_meshes.append(bell_body)
	Kit.add(_bell, Kit.sphere(0.21, bronze, 10, 14), Vector3(0, 0.26, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
	_core_dim = Mat.toon(Color("6e4a2a"), {"rim": 0.1, "noise": 0.0})
	_core_glow = Mat.glow(BELL_GLOW, 2.2)
	_bell_core = Kit.sphere(0.2, _core_dim, 10, 12)
	_bell_core.set_meta("no_flash", true)
	Kit.add(_bell, _bell_core, Vector3(0, -0.18, -0.08), Vector3.ZERO, Vector3(1.4, 0.5, 1.0))
	_crack_dark = Mat.toon(Color("2e1c14"), {"rim": 0.0, "noise": 0.0})
	_crack_glow = Mat.glow(CRACK_GLOW, 1.6)
	_crack = Kit.box(Vector3(0.05, 0.42, 0.02), _crack_dark)
	_crack.set_meta("no_flash", true)
	Kit.add(_bell, _crack, Vector3(0.05, 0.0, -0.33), Vector3(0, 0, 14))
	_pip_off = Mat.toon(Color("5a4030"), {"rim": 0.1})
	_pip_on = Mat.glow(PULSE_TINT, 2.0)
	for i in 3:
		var pip := Kit.sphere(0.055, _pip_off, 6, 8)
		pip.set_meta("no_flash", true)
		Kit.add(_bell, pip, Vector3(-0.2 + 0.2 * float(i), -0.26, -0.36))
		_pips.append(pip)
	# Head sunk between the shoulders
	_head = Node3D.new()
	_head.name = "Head"
	Kit.add(_torso, _head, Vector3(0, 0.95, -0.72))
	var head := Kit.blob(0.26, rock, 65, 0.1, 0.85, 2)
	_head.add_child(head)
	_tint_meshes.append(head)
	Kit.add(_head, Kit.box(Vector3(0.5, 0.12, 0.2), rock_dark), Vector3(0, 0.12, -0.12), Vector3(-12, 0, 0))
	for sx in [-1.0, 1.0]:
		var eye := Kit.sphere(0.05, Mat.glow(EYE, 1.8), 8, 10)
		eye.set_meta("no_flash", true)
		Kit.add(_head, eye, Vector3(sx * 0.1, 0.03, -0.22))
	# Arms with boulder fists
	_arm_l = _arm(rock, rock_dark, -1.0)
	_arm_r = _arm(rock, rock_dark, 1.0)
	# Crystal flecks on the shoulders
	for sx in [-1.0, 1.0]:
		Kit.add(_torso, Kit.cone(0.07, 0.3, Mat.outlined(Mat.toon(CRYSTAL, {"rim": 0.6}), 0.008), 6), Vector3(sx * 0.85, 1.15, 0.1), Vector3(0, 0, sx * -35.0))
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, Kit.sphere(0.07, star_mat, 6, 8), Vector3(cos(a) * 0.45, 0.0, sin(a) * 0.45))
	_stars.visible = false


func _arm(rock: Material, rock_dark: Material, side: float) -> Node3D:
	var arm := Node3D.new()
	arm.name = "ArmR" if side > 0.0 else "ArmL"
	Kit.add(_torso, arm, Vector3(side * 1.0, 1.0, -0.1))
	var upper := Kit.capsule(0.24, 0.9, rock)
	Kit.add(arm, upper, Vector3(0, -0.4, 0), Vector3(0, 0, side * 10.0))
	_tint_meshes.append(upper)
	var fist := Kit.blob(0.34, rock_dark, 66 + int(side), 0.14, 0.9, 2)
	Kit.add(arm, fist, Vector3(side * 0.08, -0.9, -0.05))
	_tint_meshes.append(fist)
	return arm


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0
	if new_state != "telegraph" and new_state != "pulses":
		set_pips(0)


func set_attack(kind: String) -> void:
	attack_kind = kind


func set_phase(p: int) -> void:
	phase = p


func set_pips(n: int) -> void:
	pips_lit = clampi(n, 0, _pips.size())
	for i in _pips.size():
		(_pips[i] as MeshInstance3D).material_override = _pip_on if i < pips_lit else _pip_off


func pulse_fired(left: int) -> void:
	set_pips(left)
	_st = 0.0


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	elif anim in ["slam", "pulses", "charge"]:
		attack_kind = anim
		set_state("telegraph", 1.6)
	else:
		set_state(anim, 2.0)


func bell_glowing() -> bool:
	return _core_is_glow


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := 0.0
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 2.0
	var hip_y := HIP_Y
	var torso_rot := Vector3.ZERO
	var head_rot := Vector3.ZERO
	var arm_l := Vector3.ZERO
	var arm_r := Vector3.ZERO
	var want_open := 0.0
	var glow := false
	var bell_scale := 1.0
	var tint := 0.0
	var tint_col := SLAM_TINT
	var gait := 0.0
	var scrape := 0.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.4, 0.0, 1.0)
			tint = (0.3 * k) if HitFx.reduce_flashing() else (0.2 + 0.2 * (0.5 + 0.5 * sin(_st * 14.0)))
			match attack_kind:
				"slam":
					torso_rot.x = -0.35 * k
					arm_l = Vector3(-2.8 * k, 0.0, 0.3 * k)
					arm_r = Vector3(-2.8 * k, 0.0, -0.3 * k)
					glow = true
				"pulses":
					tint_col = PULSE_TINT
					hip_y -= 0.15 * k
					torso_rot.x = 0.25 * k
					arm_l = Vector3(0.6 * k, 0.0, -0.2)
					arm_r = Vector3(0.6 * k, 0.0, 0.2)
					glow = true
					if not HitFx.reduce_flashing():
						bell_scale = 1.0 + 0.06 * sin(_st * 10.0)
				_:
					tint_col = CHARGE_TINT
					torso_rot.x = 0.3 * k
					head_rot.x = 0.3 * k
					scrape = sin(_st * 9.0) * 0.6 * k
		"slam":
			var s := clampf(_st / 0.25, 0.0, 1.0)
			torso_rot.x = lerpf(-0.35, 0.35, s)
			arm_l = Vector3(lerpf(-2.8, 0.9, s), 0.0, 0.1)
			arm_r = Vector3(lerpf(-2.8, 0.9, s), 0.0, -0.1)
			glow = true
		"pulses":
			hip_y -= 0.15
			torso_rot.x = 0.25
			arm_l = Vector3(0.6, 0.0, -0.2)
			arm_r = Vector3(0.6, 0.0, 0.2)
			glow = true
			bell_scale = 1.0 + 0.2 * maxf(1.0 - _st / 0.3, 0.0)
			tint = 0.25
			tint_col = PULSE_TINT
		"charge":
			torso_rot.x = 0.4
			head_rot.x = 0.35
			gait = 1.4
		"exposed":
			want_open = 1.0
			glow = true
			torso_rot.x = 0.3
			hip_y -= 0.18
			head_rot = Vector3(0.3, 0.0, sin(_st * 3.0) * 0.2)
			arm_l = Vector3(0.4, 0.0, -0.3)
			arm_r = Vector3(0.4, 0.0, 0.3)
		"recover", "stunned":
			torso_rot.x = 0.2
			hip_y -= 0.1
			head_rot.z = sin(_st * 3.0) * 0.15
			arm_l = Vector3(0.3, 0.0, -0.15)
			arm_r = Vector3(0.3, 0.0, 0.15)
		"flinch":
			torso_rot.x = -0.1 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			torso_rot.x = 0.5
			hip_y -= 0.3
		_:
			if speed > 0.3:
				gait = 1.0
	var k_s := 1.0 - exp(-10.0 * delta)
	var ph := _t * (0.9 + speed * 0.3) * TAU
	_hips.position.y = lerpf(_hips.position.y, hip_y + absf(sin(ph)) * 0.05 * gait, k_s)
	_torso.rotation = _torso.rotation.lerp(torso_rot + Vector3(0.0, 0.0, sin(ph * 0.5) * 0.06 * gait), k_s)
	_head.rotation = _head.rotation.lerp(head_rot, k_s)
	_arm_l.rotation = _arm_l.rotation.lerp(arm_l + Vector3(sin(ph) * 0.4 * gait, 0.0, 0.0), k_s)
	_arm_r.rotation = _arm_r.rotation.lerp(arm_r + Vector3(-sin(ph) * 0.4 * gait, 0.0, 0.0), k_s)
	for i in _legs.size():
		var leg := _legs[i] as Node3D
		var side := 1.0 if i == 0 else -1.0
		var want := sin(ph) * 0.4 * gait * side
		if i == 1 and scrape != 0.0:
			want = scrape
		leg.rotation.x = lerpf(leg.rotation.x, want, k_s)
	shell_open = lerpf(shell_open, want_open, k_s)
	for pd in _plates:
		var d: Dictionary = pd
		var node := d["node"] as Node3D
		var home: Vector3 = d["home"]
		var out := Vector3(home.x, 0.0, 0.0).normalized() if absf(home.x) > 0.01 else Vector3.UP
		node.position = home + (out * 0.35 + Vector3(0, 0.15, 0.12)) * shell_open
	_bell.scale = Vector3.ONE * lerpf(_bell.scale.x, bell_scale, k_s)
	_set_glow(glow or shell_open > 0.5)
	_stars.visible = state == "exposed" or state == "recover" or state == "stunned"
	if _stars.visible:
		_stars.rotation.y = _t * 3.0
		_stars.position = Vector3(0.0, 2.6, 0.0)
	_apply_tint(tint, tint_col)


func _set_glow(on: bool) -> void:
	if on != _core_is_glow:
		_core_is_glow = on
		_bell_core.material_override = _core_glow if on else _core_dim
	var crack_on := on or phase >= 2
	if crack_on != _crack_is_glow:
		_crack_is_glow = crack_on
		_crack.material_override = _crack_glow if crack_on else _crack_dark


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


func tint_alpha() -> float:
	return _tint_mat.albedo_color.a if _tint_on else 0.0
