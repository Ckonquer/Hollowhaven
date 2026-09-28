extends Node3D
## Patchwalker look: a tall, lumbering garden walker (~1.95 m): straw-stuffed trouser legs with straw tufts at the
## ankles, a torn moss-green coat with ragged tails and bright mismatched patches, vines wrapped round its middle
## and arms, a burlap sack head with two button eyes and a stitched smile under a floppy straw hat. Its right hand
## holds a long garden rake; its left hand scoops mud. Faces -Z, feet at y = 0 - a tall narrow silhouette with a
## long rake, clearly unlike the round pumpkin or the bell-capped sentry. No gore.
## States (set_state): idle / wander / chase / return (a slow, swaying lumber), telegraph + "rake" (the rake is
## raised high behind its head, body leaning back, amber tint), rake (a wide sweep), telegraph + "mud_clod" (it
## crouches, scoops, and a mud clod grows in its left hand held back to throw, brown tint), throw, recover
## (slumps, head lolls, dizzy stars), flinch, dead. play_anim(name) for previews. Tints pulse, or stay steady with
## Settings reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const HIP_Y := 0.92
const COAT := Color("4f6a4a")
const COAT_DARK := Color("3a4e38")
const STRAW := Color("e0c070")
const SACK := Color("cdb08a")
const TROUSERS := Color("6b4a36")
const VINE := Color("5f8a3e")
const HAT := Color("d9b060")
const PATCHES := [Color("d9546a"), Color("f2c14e"), Color("8fb6f0")]
const WOOD := Color("8e5f3a")
const IRON := Color("7d8290")
const MUD := Color("7a5236")
const RAKE_TINT := Color(1.0, 0.66, 0.24)
const MUD_TINT := Color(0.62, 0.42, 0.26)

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "rake"
var preview_walk := false
var rake_raise: float = 0.0            # 0 lowered .. 1 raised overhead (tests)
var mud_size: float = 0.0              # 0 .. 1 the clod in its hand (tests)

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _legs: Array = []
var _mud: MeshInstance3D
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 1.95


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	var trouser := Mat.outlined(Mat.toon(TROUSERS, {"rim": 0.35, "noise": 0.2}), 0.012)
	var straw := Mat.outlined(Mat.toon(STRAW, {"rim": 0.4, "noise": 0.25}), 0.008)
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg"
		_root.add_child(leg)
		leg.position = Vector3(sx * 0.17, HIP_Y, 0)
		var thigh := Kit.capsule(0.12, 0.85, trouser)
		Kit.add(leg, thigh, Vector3(0, -0.42, 0))
		_tint_meshes.append(thigh)
		for i in 3:
			var a := TAU * float(i) / 3.0
			Kit.add(leg, Kit.cone(0.05, 0.2, straw, 5), Vector3(cos(a) * 0.08, -0.84, sin(a) * 0.08), Vector3(180 + cos(a) * 25.0, 0, sin(a) * 25.0))
		_legs.append(leg)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_root.add_child(_hips)
	_hips.position.y = HIP_Y
	_torso = Node3D.new()
	_torso.name = "Torso"
	_hips.add_child(_torso)
	var stuffing := Kit.blob(0.3, Mat.outlined(Mat.toon(STRAW, {"rim": 0.4, "noise": 0.3}), 0.012), 31, 0.18, 1.3, 2)
	Kit.add(_torso, stuffing, Vector3(0, 0.38, 0.02))
	var coat_mat := Mat.outlined(Mat.toon(COAT, {"rim": 0.35, "noise": 0.18}), 0.014)
	var coat_dark := Mat.outlined(Mat.toon(COAT_DARK, {"rim": 0.3, "noise": 0.18}), 0.012)
	var coat := Kit.box(Vector3(0.62, 0.66, 0.38), coat_mat)
	Kit.add(_torso, coat, Vector3(0, 0.42, 0))
	_tint_meshes.append(coat)
	# Ragged coat tails (uneven lengths) and the collar
	for i in 5:
		var x := -0.24 + 0.12 * float(i)
		var h := 0.28 + 0.12 * float((i * 7) % 3)
		var tail := Kit.box(Vector3(0.12, h, 0.05), coat_dark if i % 2 == 0 else coat_mat)
		Kit.add(_torso, tail, Vector3(x, 0.1 - h * 0.5, 0.17), Vector3(8, 0, (float(i) - 2.0) * 4.0))
		_tint_meshes.append(tail)
	Kit.add(_torso, Kit.box(Vector3(0.66, 0.1, 0.42), coat_dark), Vector3(0, 0.76, 0), Vector3(-6, 0, 0))
	for i in PATCHES.size():
		var pc: Color = PATCHES[i]
		var pos := [Vector3(-0.16, 0.5, -0.195), Vector3(0.18, 0.3, -0.195), Vector3(0.0, 0.62, 0.195)][i] as Vector3
		Kit.add(_torso, Kit.box(Vector3(0.14, 0.12, 0.02), Mat.toon(pc, {"rim": 0.2})), pos, Vector3(0, 0, float(i) * 11.0 - 8.0))
	var vine := Mat.outlined(Mat.toon(VINE, {"rim": 0.4, "noise": 0.2}), 0.008)
	Kit.add(_torso, Kit.torus(0.3, 0.36, vine), Vector3(0, 0.2, 0), Vector3(8, 0, -6), Vector3(1.05, 1.0, 0.7))
	Kit.add(_torso, Kit.sphere(0.05, Mat.toon(Palette.FLOWER_RED), 6, 8), Vector3(0.26, 0.24, -0.16))
	# Sack head, button eyes, stitched smile, floppy straw hat
	_head = Node3D.new()
	_head.name = "Head"
	Kit.add(_torso, _head, Vector3(0, 0.98, -0.02))
	var sack := Kit.blob(0.2, Mat.outlined(Mat.toon(SACK, {"rim": 0.45, "noise": 0.3}), 0.012), 32, 0.12, 1.15, 2)
	_head.add_child(sack)
	_tint_meshes.append(sack)
	var ink := Mat.toon(Palette.UI_INK, {"rim": 0.2, "noise": 0.0, "specular": 0.5})
	for sx in [-1.0, 1.0]:
		Kit.add(_head, Kit.cylinder(0.045, 0.045, 0.02, ink, 10), Vector3(sx * 0.08, 0.04, -0.19), Vector3(90, 0, 0))
	for i in 5:
		Kit.add(_head, Kit.box(Vector3(0.035, 0.012, 0.012), ink), Vector3(-0.08 + 0.04 * float(i), -0.07 - 0.012 * absf(float(i) - 2.0) * -1.0, -0.195), Vector3(0, 0, 90 if i % 2 == 0 else 0))
	var hat_mat := Mat.outlined(Mat.toon(HAT, {"rim": 0.35, "noise": 0.25}), 0.01)
	Kit.add(_head, Kit.cylinder(0.36, 0.38, 0.03, hat_mat, 14), Vector3(0, 0.16, 0), Vector3(-6, 0, 8))
	Kit.add(_head, Kit.cylinder(0.14, 0.18, 0.2, hat_mat, 12), Vector3(0.01, 0.26, 0.01), Vector3(-10, 0, 14))
	# Arms: right holds the rake, left scoops mud
	var sleeve := Mat.outlined(Mat.toon(COAT, {"rim": 0.35, "noise": 0.18}), 0.012)
	_arm_r = _arm(sleeve, straw, 1.0)
	_arm_l = _arm(sleeve, straw, -1.0)
	var wood := Mat.outlined(Mat.toon(WOOD, {"rim": 0.3}), 0.01)
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.5, "specular": 0.4}), 0.008)
	var rake := Node3D.new()
	rake.name = "Rake"
	Kit.add(_arm_r, rake, Vector3(0, -0.62, 0), Vector3(-90, 0, 0))
	Kit.add(rake, Kit.cylinder(0.03, 0.03, 1.7, wood, 8), Vector3(0, 0.55, 0))
	Kit.add(rake, Kit.box(Vector3(0.5, 0.05, 0.06), iron), Vector3(0, 1.4, 0))
	for i in 6:
		Kit.add(rake, Kit.box(Vector3(0.025, 0.16, 0.025), iron), Vector3(-0.22 + 0.088 * float(i), 1.47, -0.03), Vector3(20, 0, 0))
	_mud = Kit.sphere(0.2, Mat.outlined(Mat.toon(MUD, {"rim": 0.3, "noise": 0.35}), 0.01), 8, 10)
	Kit.add(_arm_l, _mud, Vector3(0, -0.7, -0.05))
	_mud.visible = false
	# Dizzy stars
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, Kit.sphere(0.05, star_mat, 6, 8), Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3))
	_stars.visible = false


func _arm(sleeve: Material, straw: Material, side: float) -> Node3D:
	var arm := Node3D.new()
	arm.name = "ArmR" if side > 0.0 else "ArmL"
	Kit.add(_torso, arm, Vector3(side * 0.38, 0.68, 0))
	var up := Kit.capsule(0.1, 0.62, sleeve)
	Kit.add(arm, up, Vector3(0, -0.3, 0))
	_tint_meshes.append(up)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(arm, Kit.cone(0.04, 0.16, straw, 5), Vector3(cos(a) * 0.05, -0.66, sin(a) * 0.05), Vector3(180 + cos(a) * 30.0, 0, sin(a) * 30.0))
	return arm


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func set_attack(kind: String) -> void:
	attack_kind = kind


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	elif anim == "rake" or anim == "mud_clod":
		attack_kind = anim
		set_state("telegraph", 1.4)
	else:
		set_state(anim, 1.2)


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
	var arm_r := Vector3(0.0, 0.0, 0.12)
	var arm_l := Vector3(0.0, 0.0, -0.12)
	var want_raise := 0.0
	var want_mud := 0.0
	var tint := 0.0
	var tint_col := RAKE_TINT
	var gait := 0.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.4, 0.0, 1.0)
			tint = _tint_level(k)
			if attack_kind == "mud_clod":
				tint_col = MUD_TINT
				var scoop := clampf(_st / maxf(state_len * 0.45, 0.01), 0.0, 1.0)
				hip_y -= 0.18 * (1.0 - absf(scoop * 2.0 - 1.0))
				torso_rot.x = 0.45 * (1.0 - absf(scoop * 2.0 - 1.0))
				if scoop < 1.0:
					arm_l = Vector3(0.9 * scoop, 0.0, -0.1)
				else:
					arm_l = Vector3(-2.2, 0.0, -0.25)
				want_mud = clampf((_st - state_len * 0.3) / maxf(state_len * 0.4, 0.01), 0.0, 1.0)
			else:
				want_raise = k
				arm_r = Vector3(-2.7 * k, 0.0, 0.2 * k)
				torso_rot.x = -0.2 * k
				head_rot.x = -0.15 * k
		"rake":
			var s := clampf(_st / 0.25, 0.0, 1.0)
			arm_r = Vector3(lerpf(-2.7, 0.5, s), 0.0, 0.2)
			torso_rot = Vector3(0.25 * s, lerpf(0.5, -0.7, s), 0.0)
			want_raise = 1.0 - s
		"throw":
			var s2 := clampf(_st / 0.2, 0.0, 1.0)
			arm_l = Vector3(lerpf(-2.2, 0.8, s2), 0.0, -0.2)
			torso_rot = Vector3(0.2 * s2, 0.3 * s2, 0.0)
			want_mud = 0.0 if s2 > 0.5 else 1.0
		"recover":
			torso_rot.x = 0.3
			head_rot = Vector3(0.35, 0.0, sin(_st * 3.0) * 0.3)
			hip_y -= 0.06
			arm_r = Vector3(0.3, 0.0, 0.25)
			arm_l = Vector3(0.3, 0.0, -0.25)
		"flinch":
			var f := 1.0 - clampf(_st / 0.3, 0.0, 1.0)
			torso_rot.x = -0.25 * f
			head_rot.x = -0.3 * f
		"dead":
			torso_rot.x = 0.4
		_:
			if speed > 0.3:
				gait = 1.0
			head_rot.z = sin(_t * 0.9) * 0.12
	var k_s := 1.0 - exp(-12.0 * delta)
	var ph := _t * (1.2 + speed * 0.3) * TAU
	var sway := sin(ph * 0.5) * 0.12 * gait
	_hips.position.y = lerpf(_hips.position.y, hip_y + absf(sin(ph)) * 0.04 * gait, k_s)
	_torso.rotation = _torso.rotation.lerp(torso_rot + Vector3(0.0, 0.0, sway), k_s)
	_head.rotation = _head.rotation.lerp(head_rot, k_s)
	_arm_r.rotation = _arm_r.rotation.lerp(arm_r + Vector3(sin(ph) * 0.3 * gait, 0.0, 0.0), k_s)
	_arm_l.rotation = _arm_l.rotation.lerp(arm_l + Vector3(-sin(ph) * 0.3 * gait, 0.0, 0.0), k_s)
	for i in _legs.size():
		var leg := _legs[i] as Node3D
		var side := 1.0 if i == 0 else -1.0
		leg.rotation.x = lerpf(leg.rotation.x, sin(ph) * 0.45 * gait * side, k_s)
	rake_raise = lerpf(rake_raise, want_raise, k_s)
	mud_size = lerpf(mud_size, want_mud, k_s)
	_mud.visible = mud_size > 0.05
	_mud.scale = Vector3.ONE * maxf(mud_size, 0.05)
	_stars.visible = state == "recover"
	if _stars.visible:
		_stars.rotation.y = _t * 4.0
		_stars.position = Vector3(0.0, 2.1, 0.0)
	_apply_tint(tint, tint_col)


func _tint_level(k: float) -> float:
	if HitFx.reduce_flashing():
		return 0.3 * k
	return 0.2 + 0.2 * (0.5 + 0.5 * sin(_st * 18.0))


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
