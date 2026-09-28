extends Node3D
## Brambleback look: a squat, wide, LOW creature under a ridged bark carapace (overlapping plates, a spine of
## thorns, moss tufts), a heavy armoured brow plate with two stubby horns, small amber eyes under the brow,
## four stubby legs and soft pale flank patches. Faces -Z, feet at y = 0; about 1.7 m long, 1.1 m tall and
## 1.2 m wide - a long low mound, clearly not the round Brambling.
## States (set_state): idle / wander / chase / return (trundling walk), telegraph (paws the dirt with a
## forepaw, head lowered behind the brow, body rocked back, orange tint - pulsing, or steady with
## reduce_flashing), charge (head down, fast gallop), recover / stunned (sags, the soft flanks glow = "hit me
## here", dizzy stars), flinch (squash), dead. play_anim(name) for previews.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BODY_Y := 0.52
const BODY_COLOR := Color("6d5a44")
const HEAD_COLOR := Color("5c4a38")
const SHELL_COLOR := Color("7b5836")
const SHELL_DARK := Color("4f3522")
const THORN_COLOR := Color("e3c08a")
const FLANK_COLOR := Color("e2ae8a")
const FLANK_GLOW := Color("ffd08a")
const EYE_COLOR := Color("ffb14a")
const TELEGRAPH_TINT := Color(0.98, 0.42, 0.18)
const DIRT := Color("9c7650")

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "charge"
var move_speed: float = 0.0
var preview_walk := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _dirt_t: float = 0.0
var _root: Node3D
var _body: Node3D
var _head: Node3D
var _legs: Array = []
var _flanks: Array = []
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false
var _flank_on := false
var _flank_mat: Material
var _flank_glow_mat: Material


func _ready() -> void:
	_build()


func body_height() -> float:
	return 1.0


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	# Legs first (under the body)
	var leg_mat := Mat.outlined(Mat.toon(Palette.BARK_DARK), 0.012)
	var foot_mat := Mat.outlined(Mat.toon(SHELL_DARK), 0.012)
	for p in [Vector3(-0.36, 0.34, -0.42), Vector3(0.36, 0.34, -0.42), Vector3(-0.36, 0.34, 0.42), Vector3(0.36, 0.34, 0.42)]:
		var leg := Node3D.new()
		leg.name = "Leg"
		_root.add_child(leg)
		leg.position = p
		Kit.add(leg, Kit.capsule(0.11, 0.38, leg_mat), Vector3(0, -0.14, 0))
		Kit.add(leg, Kit.sphere(0.12, foot_mat, 8, 12), Vector3(0, -0.3, -0.03), Vector3.ZERO, Vector3(1.1, 0.5, 1.3))
		_legs.append(leg)
	_body = Node3D.new()
	_body.name = "Body"
	_root.add_child(_body)
	_body.position.y = BODY_Y
	var torso := Kit.blob(0.5, Mat.outlined(Mat.toon(BODY_COLOR, {"rim": 0.4, "noise": 0.12}), 0.016), 5, 0.07, 0.72, 3)
	Kit.add(_body, torso, Vector3(0, 0, 0.05), Vector3.ZERO, Vector3(1.1, 1.0, 1.45))
	_tint_meshes.append(torso)
	# Bark carapace: two columns of overlapping plates over the back plus a skirt of side plates.
	var shell_mat := Mat.outlined(Mat.toon(SHELL_COLOR, {"rim": 0.35, "noise": 0.2}), 0.012)
	var shell_dark := Mat.outlined(Mat.toon(SHELL_DARK, {"rim": 0.3, "noise": 0.2}), 0.012)
	for r in 4:
		var z := 0.47 - float(r) * 0.27
		for c in [-1.0, 1.0]:
			var plate := Kit.box(Vector3(0.36, 0.09, 0.34), shell_mat if (r % 2 == 0) else shell_dark)
			Kit.add(_body, plate, Vector3(c * 0.2, 0.31 - 0.035 * absf(float(r) - 1.5), z), Vector3(-z * 38.0, 0.0, -c * 20.0))
			_tint_meshes.append(plate)
	for r in 3:
		var z := 0.36 - float(r) * 0.32
		for c in [-1.0, 1.0]:
			var skirt := Kit.box(Vector3(0.3, 0.08, 0.32), shell_dark)
			Kit.add(_body, skirt, Vector3(c * 0.44, 0.13, z), Vector3(-z * 30.0, 0.0, -c * 52.0))
			_tint_meshes.append(skirt)
	var thorn_mat := Mat.outlined(Mat.toon(THORN_COLOR, {"rim": 0.3}), 0.008)
	for i in 5:
		var z := 0.5 - float(i) * 0.2
		var thorn := Kit.cone(0.05, 0.2, thorn_mat, 7)
		Kit.add(_body, thorn, Vector3(0, 0.42 - 0.03 * absf(float(i) - 2.0), z), Vector3(25.0, 0, 0))
	var moss_mat := Mat.outlined(Mat.toon(Palette.MOSS, {"rim": 0.4, "noise": 0.2}), 0.01)
	for mp in [Vector3(0.22, 0.36, 0.3), Vector3(-0.25, 0.34, -0.05), Vector3(0.12, 0.37, -0.28)]:
		Kit.add(_body, Kit.blob(0.1, moss_mat, 11, 0.3, 0.6, 2), mp)
	Kit.add(_body, Kit.cone(0.1, 0.24, shell_dark, 8), Vector3(0, -0.05, 0.78), Vector3(80, 0, 0))
	# Soft flank patches (glow during the punish window)
	_flank_mat = Mat.outlined(Mat.toon(FLANK_COLOR, {"rim": 0.5, "noise": 0.05}), 0.01)
	_flank_glow_mat = Mat.glow(FLANK_GLOW, 1.3)
	for sx in [-1.0, 1.0]:
		var fl := Kit.sphere(0.2, _flank_mat, 10, 14)
		fl.name = "Flank"
		Kit.add(_body, fl, Vector3(sx * 0.53, -0.02, 0.08), Vector3.ZERO, Vector3(0.25, 0.8, 1.25))
		_flanks.append(fl)
	# Head with the armoured brow (its "front armour")
	_head = Node3D.new()
	_head.name = "Head"
	Kit.add(_body, _head, Vector3(0, 0.02, -0.66))
	var head := Kit.blob(0.26, Mat.outlined(Mat.toon(HEAD_COLOR, {"rim": 0.4, "noise": 0.1}), 0.014), 9, 0.06, 0.85, 3)
	Kit.add(_head, head, Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 1.0, 1.0))
	_tint_meshes.append(head)
	var brow := Kit.box(Vector3(0.6, 0.14, 0.26), shell_dark)
	Kit.add(_head, brow, Vector3(0, 0.15, -0.1), Vector3(-15, 0, 0))
	_tint_meshes.append(brow)
	for sx in [-1.0, 1.0]:
		Kit.add(_head, Kit.cone(0.06, 0.24, thorn_mat, 7), Vector3(sx * 0.2, 0.2, -0.14), Vector3(-62.0, 0.0, sx * -14.0))
		var eye := Kit.sphere(0.045, Mat.glow(EYE_COLOR, 1.8), 8, 10)
		eye.set_meta("no_flash", true)
		Kit.add(_head, eye, Vector3(sx * 0.11, 0.03, -0.24))
		Kit.add(_head, Kit.sphere(0.022, Mat.toon(Palette.UI_INK, {"rim": 0.0, "noise": 0.0}), 6, 8), Vector3(sx * 0.05, -0.08, -0.35))
	Kit.add(_head, Kit.blob(0.12, Mat.outlined(Mat.toon(Palette.BARK), 0.01), 4, 0.08, 0.8, 2), Vector3(0, -0.08, -0.26), Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
	# Dizzy stars (recover / stunned)
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, Kit.sphere(0.05, star_mat, 6, 8), Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3))
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
	else:
		set_state(anim, 1.2)


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func flanks_glowing() -> bool:
	return _flank_on


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := move_speed
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 3.0
	var body_y := BODY_Y
	var body_rot := Vector3.ZERO
	var head_rot := Vector3.ZERO
	var head_y := 0.02
	var tint := 0.0
	var gait := 0.0
	var gait_freq := 0.0
	var paw := 0.0
	var flank := false
	match state:
		"telegraph":
			var k := clampf(_st / 0.25, 0.0, 1.0)
			head_rot.x = 0.38 * k                       # head lowered behind the brow
			head_y -= 0.1 * k
			body_rot.x = -0.07 * k                       # rocked back on its haunches
			body_y -= 0.05 * k
			paw = sin(_st * 11.0) * 0.75 * k             # right forepaw scrapes the dirt
			if HitFx.reduce_flashing():
				tint = 0.3 * k
			else:
				tint = 0.22 + 0.2 * (0.5 + 0.5 * sin(_st * 20.0))
			_dirt_t -= delta
			if _dirt_t <= 0.0:
				_dirt_t = 0.3
				var fp := global_position + global_transform.basis * Vector3(0.36, 0.05, -0.55)
				HitFx.chips(fp, DIRT, 4, 2.0, 0.45)
		"charge":
			head_rot.x = 0.46
			head_y -= 0.12
			body_rot.x = 0.1
			gait = 0.75
			gait_freq = 4.8
		"recover", "stunned":
			body_y -= 0.07
			head_rot.x = 0.25
			head_rot.z = sin(_st * 4.0) * 0.14
			body_rot.z = sin(_st * 3.0) * 0.05
			flank = true
		"flinch":
			var f := 1.0 - clampf(_st / 0.3, 0.0, 1.0)
			body_y -= 0.08 * f
			body_rot.x = -0.15 * f
		"dead":
			head_rot.x = 0.3
		_:
			if speed > 0.3:
				gait = 0.5
				gait_freq = 1.4 + speed * 0.35
			else:
				body_rot.z = sin(_t * 1.1) * 0.02
				head_rot.x = 0.05 + sin(_t * 1.7) * 0.04
	var k_s := 1.0 - exp(-14.0 * delta)
	var ph := _t * gait_freq * TAU
	var bob := absf(sin(ph)) * 0.04 * gait
	_body.position.y = lerpf(_body.position.y, body_y + bob, k_s)
	_body.rotation = _body.rotation.lerp(body_rot, k_s)
	_head.rotation = _head.rotation.lerp(head_rot, k_s)
	_head.position.y = lerpf(_head.position.y, head_y, k_s)
	for i in _legs.size():
		var leg := _legs[i] as Node3D
		var diag := 1.0 if (i == 0 or i == 3) else -1.0      # diagonal pairs move together
		var want := sin(ph) * 0.7 * gait * diag
		if i == 1 and paw != 0.0:
			want = paw
		leg.rotation.x = lerpf(leg.rotation.x, want, k_s)
	_set_flank(flank)
	_stars.visible = state == "recover" or state == "stunned"
	if _stars.visible:
		_stars.rotation.y = _t * 4.0
		_stars.position = Vector3(0.0, _body.position.y + 0.62 + sin(_t * 6.0) * 0.02, -0.55)
	_apply_tint(tint)


func _set_flank(on: bool) -> void:
	if on == _flank_on:
		return
	_flank_on = on
	for f in _flanks:
		(f as MeshInstance3D).material_override = _flank_glow_mat if on else _flank_mat


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
