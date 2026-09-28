extends Node3D
## Pumpkin Mimic look: a squat, slightly crooked jack-o'-lantern (seven chunky ribs, a deeper orange than the
## orchard's round pumpkins), a curly green stem with one leaf, a carved jagged mouth with a warm candle glow
## inside, two triangular carved eyes and four stubby vine feet. Faces -Z, feet at y = 0; ~0.95 m wide, 0.85 m
## tall - low and round, clearly not a walker or a bell.
## States (set_state): dormant (eyes shut to dark slits, mouth a closed seam, feet tucked, a crooked lean: it
## reads as a pumpkin - only the stem twitch gives it away), waking (a little hop, the eyes blink open),
## idle / wander / chase / return (waddling on its vine feet), telegraph + attack "bite" (the mouth gapes wide,
## the top tips back, orange tint), telegraph + attack "roll" (the feet tuck in, it leans into the lane, red tint),
## bite, roll (spinning along the lane), stuck (tilted in the dirt, wobbling, dizzy stars), recover (panting
## mouth, stars), flinch, dead. twitch() plays one quick stem twitch (the tell). play_anim(name) for previews.
## Tints pulse, or stay steady with Settings reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BODY_Y := 0.42
const RIB_COUNT := 7
const SKIN := Color("d9772f")
const SKIN_DEEP := Color("b85e24")
const STEM := Color("5f7a38")
const LEAF := Color("7fae57")
const VINE := Color("6c9a45")
const GLOW := Color("ffb347")
const INSIDE := Color("5a2a18")
const LID := Color("6e3a1c")
const BITE_TINT := Color(1.0, 0.62, 0.2)
const ROLL_TINT := Color(0.98, 0.34, 0.2)
const TWITCH_TIME := 0.28
const ROLL_RADIUS := 0.42

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "bite"
var preview_walk := false
var twitching := false
var mouth_open: float = 0.0            # 0 closed seam .. 1 wide (read by tests)
var feet_out: float = 1.0              # 0 tucked .. 1 out

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _twitch_t: float = -1.0
var _spin: float = 0.0
var _root: Node3D
var _body: Node3D
var _shell: Node3D
var _stem: Node3D
var _mouth: Node3D
var _eyes: Array = []
var _lids: Array = []
var _feet: Array = []
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 0.85


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	# Stubby vine feet (tucked while dormant / rolling)
	var vine_mat := Mat.outlined(Mat.toon(VINE, {"rim": 0.4, "noise": 0.15}), 0.01)
	for p in [Vector3(-0.24, 0.1, -0.2), Vector3(0.24, 0.1, -0.2), Vector3(-0.24, 0.1, 0.22), Vector3(0.24, 0.1, 0.22)]:
		var foot := Node3D.new()
		foot.name = "Foot"
		_root.add_child(foot)
		foot.position = p
		Kit.add(foot, Kit.capsule(0.07, 0.26, vine_mat), Vector3(0, -0.02, 0), Vector3(0, 0, 18.0 * signf(p.x)))
		Kit.add(foot, Kit.sphere(0.075, vine_mat, 6, 8), Vector3(0.03 * signf(p.x), -0.1, -0.02), Vector3.ZERO, Vector3(1.2, 0.6, 1.4))
		_feet.append(foot)
	_body = Node3D.new()
	_body.name = "Body"
	_root.add_child(_body)
	_body.position.y = BODY_Y
	_shell = Node3D.new()
	_shell.name = "Shell"
	_body.add_child(_shell)
	var skin := Mat.outlined(Mat.toon(SKIN, {"rim": 0.45, "noise": 0.12}), 0.016)
	var skin_deep := Mat.outlined(Mat.toon(SKIN_DEEP, {"rim": 0.4, "noise": 0.12}), 0.016)
	for i in RIB_COUNT:
		var a := TAU * float(i) / float(RIB_COUNT)
		var rib := Kit.sphere(0.3, skin if i % 2 == 0 else skin_deep, 10, 14)
		Kit.add(_shell, rib, Vector3(sin(a) * 0.19, 0.0, cos(a) * 0.19), Vector3(0.0, rad_to_deg(a), 0.0), Vector3(0.62, 0.95, 1.0))
		_tint_meshes.append(rib)
	var core := Kit.sphere(0.34, skin, 12, 16)
	Kit.add(_shell, core, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.85, 1.0))
	_tint_meshes.append(core)
	# Curly stem + one leaf on its own pivot (the twitch)
	_stem = Node3D.new()
	_stem.name = "Stem"
	Kit.add(_shell, _stem, Vector3(0.02, 0.26, 0.02))
	var stem_mat := Mat.outlined(Mat.toon(STEM, {"rim": 0.3}), 0.01)
	Kit.add(_stem, Kit.cylinder(0.035, 0.06, 0.2, stem_mat, 8), Vector3(0, 0.09, 0), Vector3(0, 0, -12))
	Kit.add(_stem, Kit.torus(0.035, 0.06, stem_mat), Vector3(-0.05, 0.2, 0), Vector3(90, 0, 20), Vector3(1, 1, 1))
	Kit.add(_stem, Kit.prism(Vector3(0.18, 0.12, 0.02), Mat.outlined(Mat.toon(LEAF), 0.008)), Vector3(0.1, 0.12, 0.02), Vector3(0, 30, -70))
	# Carved eyes (glow) + dark lids (dormant)
	var glow := Mat.glow(GLOW, 1.7)
	var lid := Mat.toon(LID, {"rim": 0.1, "noise": 0.0})
	for sx in [-1.0, 1.0]:
		var eye := Kit.prism(Vector3(0.13, 0.11, 0.05), glow)
		eye.set_meta("no_flash", true)
		Kit.add(_shell, eye, Vector3(sx * 0.12, 0.1, -0.31), Vector3(-18, 0, sx * 8.0))
		_eyes.append(eye)
		var slit := Kit.box(Vector3(0.12, 0.018, 0.03), lid)
		Kit.add(_shell, slit, Vector3(sx * 0.12, 0.08, -0.325), Vector3(-18, 0, sx * -10.0))
		_lids.append(slit)
	# Jagged mouth: a dark inside with a candle glow and a row of teeth (scaled open / shut)
	_mouth = Node3D.new()
	_mouth.name = "Mouth"
	Kit.add(_shell, _mouth, Vector3(0, -0.08, -0.3), Vector3(-10, 0, 0))
	Kit.add(_mouth, Kit.box(Vector3(0.36, 0.14, 0.05), Mat.toon(INSIDE, {"rim": 0.0, "noise": 0.0})), Vector3(0, 0, 0.01))
	var inner := Kit.box(Vector3(0.26, 0.07, 0.03), Mat.glow(GLOW, 1.2))
	inner.set_meta("no_flash", true)
	Kit.add(_mouth, inner, Vector3(0, -0.01, 0.025))
	var tooth_mat := Mat.toon(SKIN, {"rim": 0.3})
	for i in 4:
		var x := -0.12 + 0.08 * float(i)
		Kit.add(_mouth, Kit.prism(Vector3(0.05, 0.06, 0.04), tooth_mat), Vector3(x, 0.05, -0.01), Vector3(0, 0, 180))
		Kit.add(_mouth, Kit.prism(Vector3(0.05, 0.06, 0.04), tooth_mat), Vector3(x + 0.04, -0.05, -0.01))
	# Dizzy stars (stuck / recover)
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, Kit.sphere(0.045, star_mat, 6, 8), Vector3(cos(a) * 0.26, 0.0, sin(a) * 0.26))
	_stars.visible = false


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0
	if new_state == "dormant" and _eyes.size() > 0:
		_show_eyes(false)                  # snaps shut at once: it must never look awake while dormant
		feet_out = 0.0
		mouth_open = 0.0


func _show_eyes(on: bool) -> void:
	for e in _eyes:
		(e as Node3D).visible = on
	for l in _lids:
		(l as Node3D).visible = not on


func set_attack(kind: String) -> void:
	attack_kind = kind


## One quick stem twitch (the tell).
func twitch() -> void:
	_twitch_t = 0.0
	twitching = true


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	elif anim == "twitch":
		set_state("dormant")
		twitch()
	elif anim == "bite" or anim == "roll":
		attack_kind = anim
		set_state("telegraph", 1.2)
	else:
		set_state(anim, 1.2)


func eyes_open() -> bool:
	return not _eyes.is_empty() and (_eyes[0] as Node3D).visible


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := 0.0
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 2.5
	var body_y := BODY_Y
	var lean := Vector3.ZERO
	var shell_tip := 0.0
	var want_mouth := 0.12
	var want_feet := 1.0
	var tint := 0.0
	var tint_col := BITE_TINT
	var eyes := true
	var waddle := 0.0
	var spinning := false
	match state:
		"dormant":
			eyes = false
			want_mouth = 0.0
			want_feet = 0.0
			lean = Vector3(0.0, 0.0, 0.12)
			body_y = BODY_Y - 0.08
		"waking":
			var k := clampf(_st / maxf(state_len, 0.01), 0.0, 1.0)
			eyes = k > 0.7
			want_feet = clampf((k - 0.5) * 2.0, 0.0, 1.0)
			want_mouth = 0.0 if k < 0.7 else 0.3
			body_y = BODY_Y - 0.08 + (sin(clampf((k - 0.75) * 4.0, 0.0, 1.0) * PI) * 0.18)
			lean = Vector3(0.0, 0.0, 0.12 * (1.0 - k))
		"telegraph":
			var k2 := clampf(_st / 0.3, 0.0, 1.0)
			tint = _tint_level(k2)
			if attack_kind == "roll":
				tint_col = ROLL_TINT
				want_feet = 0.0
				lean.x = 0.25 * k2
				body_y = BODY_Y - 0.08 * k2
				want_mouth = 0.1
			else:
				want_mouth = 1.0
				shell_tip = -0.32 * k2
				lean.x = -0.12 * k2
		"bite":
			want_mouth = 0.35
			shell_tip = 0.12
			lean.x = 0.2
		"roll":
			want_feet = 0.0
			spinning = true
			want_mouth = 0.1
		"stuck":
			want_feet = 0.2
			lean = Vector3(0.3, 0.0, sin(_st * 5.0) * 0.18)
			body_y = BODY_Y - 0.1
			want_mouth = 0.4
		"recover":
			want_mouth = 0.4 + 0.15 * sin(_st * 7.0)
		"flinch":
			var f := 1.0 - clampf(_st / 0.3, 0.0, 1.0)
			body_y -= 0.06 * f
			lean.x = -0.18 * f
		"dead":
			want_mouth = 1.0
			eyes = false
		_:
			if speed > 0.3:
				waddle = 1.0
	var k_s := 1.0 - exp(-14.0 * delta)
	mouth_open = lerpf(mouth_open, want_mouth, k_s)
	feet_out = lerpf(feet_out, want_feet, k_s)
	var bob := absf(sin(_t * 7.0)) * 0.05 * waddle
	_body.position.y = lerpf(_body.position.y, body_y + bob, k_s)
	if spinning:
		_spin -= speed / ROLL_RADIUS * delta if speed > 0.1 else 8.0 * delta
		_body.rotation = Vector3(_spin, 0.0, 0.0)
	else:
		_spin = 0.0
		var wob := Vector3(0.0, 0.0, sin(_t * 7.0) * 0.1 * waddle)
		_body.rotation = _body.rotation.lerp(lean + wob, k_s)
	_shell.rotation.x = lerpf(_shell.rotation.x, shell_tip, k_s)
	_mouth.scale = Vector3(1.0, maxf(0.12 + mouth_open * 1.6, 0.05), 1.0)
	_show_eyes(eyes)
	for i in _feet.size():
		var f2 := _feet[i] as Node3D
		f2.scale = Vector3.ONE * lerpf(0.15, 1.0, feet_out)
		f2.rotation.x = sin(_t * 9.0 + float(i) * PI) * 0.5 * waddle
	_update_twitch(delta)
	_stars.visible = state == "stuck" or state == "recover"
	if _stars.visible:
		_stars.rotation.y = _t * 4.0
		_stars.position = Vector3(0.0, _body.position.y + 0.5, 0.0)
	_apply_tint(tint, tint_col)


func _update_twitch(delta: float) -> void:
	if _twitch_t < 0.0:
		_stem.rotation.z = lerpf(_stem.rotation.z, 0.0, 1.0 - exp(-10.0 * delta))
		return
	_twitch_t += delta
	var k := _twitch_t / TWITCH_TIME
	if k >= 1.0:
		_twitch_t = -1.0
		twitching = false
		return
	_stem.rotation.z = sin(k * PI) * 0.7


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
