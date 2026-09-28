extends Node3D
## Velvet Wing look: a round, plum-velvet little bat (~0.95 m wingspan) with big pointed ears, a cream masquerade
## half-mask with rosy eyes, two tiny white fangs (cute, never gory), a tiny crimson velvet cape with a gold clasp
## and scalloped membrane wings. The local origin is the body centre: the enemy lifts this node to its virtual
## height (parent.hover_y). A small, round, caped silhouette - unlike the moth's wide bright wings.
## States (set_state): idle / wander / return (hangs UPSIDE DOWN from a little twig, wings wrapped like a cloak,
## a slow sway), chase (flapping), telegraph + "dash" (hovers still and FOLDS the cloak tight around itself, body
## pitched toward the lane, red tint), dash (wings swept back), telegraph + "drain" / drain (wings spread wide, the
## mask's eyes glow, plum tint), recover / stunned (a low tired flutter, dizzy stars), flinch, dead.
## play_anim(name) for previews. Tints pulse, or stay steady with Settings reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const CreatureFx := preload("res://src/enemies/creature_fx.gd")

const FUR := Color("4a2d5a")
const FUR_LIGHT := Color("7a5a8a")
const WING := Color("3a2244")
const CAPE := Color("9b2d4a")
const CAPE_LINING := Color("e6b8c8")
const MASK := Color("f3e6c8")
const GOLD := Color("d9b25a")
const EYE := Color("ff8fb0")
const TWIG := Color("5e3b28")
const DASH_TINT := Color(0.98, 0.34, 0.26)
const DRAIN_TINT := Color(0.86, 0.36, 0.62)
const PREVIEW_HEIGHT := 1.2
const FOOT_Y := -0.2                   # root space: the little feet under the belly...
const TWIG_Y := -0.265                 # ...grip the roost twig here (CR-01: above the body once it hangs upside down)

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "dash"
var preview := false
var fold: float = 1.0                  # 0 wings open .. 1 wrapped / folded as a cloak (tests)
var hanging := true

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _body: Node3D
var _wings: Array = []
var _cape: Node3D
var _eyes: Array = []
var _eye_mat: Material
var _eye_glow_mat: Material
var _eyes_glow := false
var _twig: Node3D
var _feet: Array = []
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false
var _tint_level_now: float = 0.0


func _ready() -> void:
	_build()


func body_height() -> float:
	return 0.5


func _build() -> void:
	_tint_mat = CreatureFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	_body = Node3D.new()
	_body.name = "Body"
	_root.add_child(_body)
	var fur := Mat.outlined(Mat.toon(FUR, {"rim": 0.6, "noise": 0.25}), 0.012)
	var torso := Kit.blob(0.19, fur, 41, 0.1, 1.05, 3)
	_body.add_child(torso)
	_tint_meshes.append(torso)
	Kit.add(_body, Kit.sphere(0.12, Mat.toon(FUR_LIGHT, {"rim": 0.5, "noise": 0.2}), 8, 10), Vector3(0, -0.04, -0.1), Vector3.ZERO, Vector3(1.0, 1.1, 0.6))
	var head := Kit.sphere(0.14, fur, 10, 14)
	Kit.add(_body, head, Vector3(0, 0.17, -0.06))
	_tint_meshes.append(head)
	for sx in [-1.0, 1.0]:
		var ear := Kit.cone(0.06, 0.2, fur, 7)
		Kit.add(_body, ear, Vector3(sx * 0.08, 0.34, -0.04), Vector3(0, 0, sx * -18.0))
		Kit.add(_body, Kit.cone(0.03, 0.12, Mat.toon(Palette.BLOSSOM), 6), Vector3(sx * 0.08, 0.33, -0.07), Vector3(-8, 0, sx * -18.0))
	# Masquerade half-mask with rosy eyes and tiny fangs
	var mask_mat := Mat.outlined(Mat.toon(MASK, {"rim": 0.3, "specular": 0.4}), 0.008)
	Kit.add(_body, Kit.box(Vector3(0.24, 0.07, 0.04), mask_mat), Vector3(0, 0.2, -0.19), Vector3(-8, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.add(_body, Kit.prism(Vector3(0.08, 0.06, 0.04), mask_mat), Vector3(sx * 0.13, 0.23, -0.18), Vector3(0, 0, sx * -60.0))
	_eye_mat = Mat.toon(Palette.UI_INK, {"rim": 0.3, "noise": 0.0, "specular": 0.6})
	_eye_glow_mat = Mat.glow(EYE, 2.0)
	for sx in [-1.0, 1.0]:
		var eye := Kit.sphere(0.03, _eye_mat, 6, 8)
		eye.set_meta("no_flash", true)
		Kit.add(_body, eye, Vector3(sx * 0.055, 0.205, -0.215))
		_eyes.append(eye)
	var fang := Mat.toon(Palette.FLOWER_WHITE, {"rim": 0.2})
	for sx in [-1.0, 1.0]:
		Kit.add(_body, Kit.cone(0.012, 0.035, fang, 5), Vector3(sx * 0.025, 0.1, -0.19), Vector3(180, 0, 0))
	# Tiny velvet cape with a gold clasp
	_cape = Node3D.new()
	_cape.name = "Cape"
	Kit.add(_body, _cape, Vector3(0, 0.1, 0.08))
	var cape := Mat.outlined(Mat.toon(CAPE, {"rim": 0.5, "noise": 0.15}), 0.01)
	var lining := Mat.toon(CAPE_LINING, {"rim": 0.3})
	for sx in [-1.0, 1.0]:
		var half := Kit.box(Vector3(0.16, 0.3, 0.025), cape)
		Kit.add(_cape, half, Vector3(sx * 0.07, -0.13, 0.05), Vector3(10, sx * 12.0, 0))
		_tint_meshes.append(half)
		Kit.add(_cape, Kit.box(Vector3(0.14, 0.26, 0.01), lining), Vector3(sx * 0.07, -0.12, 0.035), Vector3(10, sx * 12.0, 0))
	Kit.add(_cape, Kit.sphere(0.03, Mat.outlined(Mat.toon(GOLD, {"specular": 0.6}), 0.006), 6, 8), Vector3(0, 0.0, -0.1))
	# Scalloped membrane wings
	var wing := Mat.outlined(Mat.toon(WING, {"rim": 0.55, "noise": 0.1}), 0.008)
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if sx < 0.0 else "WingR"
		Kit.add(_body, pivot, Vector3(sx * 0.14, 0.06, 0.0))
		for i in 3:
			var seg := Kit.sphere(0.13, wing, 8, 10)
			Kit.add(pivot, seg, Vector3(sx * (0.1 + 0.11 * float(i)), -0.02 * float(i), 0.0), Vector3(0, 0, sx * (8.0 * float(i))), Vector3(0.95, 0.75 - 0.12 * float(i), 0.1))
			_tint_meshes.append(seg)
		Kit.add(pivot, Kit.cone(0.02, 0.08, Mat.toon(FUR), 5), Vector3(sx * 0.1, 0.1, 0.0), Vector3(0, 0, sx * -30.0))
		_wings.append(pivot)
	# Two little hooked feet under the belly (they grip the twig while it hangs)
	var claw := Mat.outlined(Mat.toon(FUR, {"rim": 0.5}), 0.006)
	_feet = []
	for sx in [-1.0, 1.0]:
		var foot := Node3D.new()
		foot.name = "Foot"
		Kit.add(_body, foot, Vector3(sx * 0.055, FOOT_Y + 0.03, 0.02))
		Kit.add(foot, Kit.capsule(0.022, 0.08, claw), Vector3.ZERO)
		Kit.add(foot, Kit.cone(0.02, 0.05, claw, 5), Vector3(0, -0.05, -0.012), Vector3(160, 0, 0))
		_feet.append(foot)
	# The roost twig (shown while hanging): at the FEET in root space, so it sits above the flipped bat
	_twig = Node3D.new()
	_twig.name = "Twig"
	_root.add_child(_twig)
	_twig.position = Vector3(0, TWIG_Y, 0)
	Kit.add(_twig, Kit.cylinder(0.025, 0.03, 0.7, Mat.outlined(Mat.toon(TWIG), 0.008), 6), Vector3(0, 0, 0), Vector3(0, 0, 90))
	Kit.add(_twig, Kit.sphere(0.05, Mat.toon(Palette.FOLIAGE_AUTUMN), 6, 8), Vector3(0.28, -0.02, 0.02), Vector3(0, 0, 180), Vector3(1.4, 0.5, 1.0))
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, Kit.sphere(0.035, star_mat, 6, 8), Vector3(cos(a) * 0.2, 0.0, sin(a) * 0.2))
	_stars.visible = false


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func set_attack(kind: String) -> void:
	attack_kind = kind


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func play_anim(anim: String) -> void:
	preview = true
	if anim == "walk" or anim == "fly":
		set_state("chase")
	elif anim == "dash" or anim == "drain":
		attack_kind = anim
		set_state("telegraph", 1.2)
	else:
		set_state(anim, 1.2)


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var h := PREVIEW_HEIGHT
	var p := get_parent()
	if p != null and "hover_y" in p and not preview:
		h = float(p.get("hover_y"))
	position.y = h
	var want_fold := 0.0
	var flap_amp := 0.9
	var flap_freq := 8.0
	var pitch := 0.0
	var hang := false
	var tint := 0.0
	var tint_col := DASH_TINT
	var glow_eyes := false
	match state:
		"idle", "wander", "return":
			hang = true
			want_fold = 1.0
			flap_amp = 0.0
		"telegraph":
			var k := clampf(_st / 0.3, 0.0, 1.0)
			tint = _tint_level(k)
			if attack_kind == "drain":
				tint_col = DRAIN_TINT
				want_fold = 0.0
				flap_amp = 0.25
				flap_freq = 4.0
				glow_eyes = true
			else:
				want_fold = 1.0
				flap_amp = 0.0
				pitch = 0.5 * k
		"dash":
			want_fold = 0.7
			flap_amp = 0.0
			pitch = 1.1
		"drain":
			want_fold = 0.0
			flap_amp = 0.3
			flap_freq = 4.0
			glow_eyes = true
			tint = _tint_level(1.0) * 0.6
			tint_col = DRAIN_TINT
		"recover", "stunned":
			flap_amp = 0.5
			flap_freq = 4.5
			pitch = -0.15
		"flinch":
			flap_amp = 0.2
			pitch = -0.4 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			want_fold = 1.0
			flap_amp = 0.0
	var k_s := 1.0 - exp(-12.0 * delta)
	fold = lerpf(fold, want_fold, k_s)
	hanging = hang
	_twig.visible = hang
	var root_rot := Vector3(0.0, 0.0, PI if hang else 0.0)
	if hang:
		root_rot.z += sin(_t * 1.2) * 0.05
	_root.rotation = _root.rotation.lerp(root_rot, k_s * 0.6)
	_body.rotation = _body.rotation.lerp(Vector3(pitch, 0.0, 0.0), k_s)
	_body.position.y = sin(_t * flap_freq * 0.5) * 0.03 * minf(flap_amp, 1.0)
	var flap := sin(_t * flap_freq) * flap_amp
	for i in _wings.size():
		var w := _wings[i] as Node3D
		var side := -1.0 if i == 0 else 1.0
		# open: flapping around z; folded: wrapped forward around the body like a cloak
		w.rotation = Vector3(0.0, side * -1.35 * fold, side * (flap * (1.0 - fold)))
	_cape.scale = Vector3(1.0 + 0.25 * fold, 1.0, 1.0)
	if glow_eyes != _eyes_glow:
		_eyes_glow = glow_eyes
		for e in _eyes:
			(e as MeshInstance3D).material_override = _eye_glow_mat if glow_eyes else _eye_mat
	_stars.visible = state == "recover" or state == "stunned"
	if _stars.visible:
		_stars.rotation.y = _t * 4.0
		_stars.position = Vector3(0.0, 0.45, 0.0)
	_apply_tint(tint, tint_col)


## World height of the roost twig above the body centre while hanging (tests: > 0, it hangs FROM the twig).
func twig_height() -> float:
	return _twig.global_position.y - _body.global_position.y


## Gap (m) between the nearest foot tip and the twig axis (tests: the feet really grip the twig).
func foot_to_twig() -> float:
	var best := INF
	for f in _feet:
		var tip: Vector3 = (f as Node3D).global_transform * Vector3(0, -0.07, 0)
		var q: Vector3 = _twig.global_transform.affine_inverse() * tip
		best = minf(best, Vector2(q.y, q.z).length())
	return best


func eyes_glowing() -> bool:
	return _eyes_glow


func _tint_level(k: float) -> float:
	if HitFx.reduce_flashing():
		return 0.3 * k
	return 0.2 + 0.2 * (0.5 + 0.5 * sin(_st * 18.0))


func _apply_tint(tint: float, col: Color) -> void:
	# CR-09: a capped wash + a fresnel rim in the tell colour (CreatureFx), so the shading and outlines stay.
	var on := false
	if _flash_t > 0.0:
		_tint_level_now = HitFx.flash_strength(0.75)
		CreatureFx.apply_flash(_tint_mat, HitFx.FLASH_COLOR, _tint_level_now)
		on = true
	elif tint > 0.01:
		_tint_level_now = clampf(tint, 0.0, 1.0)
		CreatureFx.apply_tint(_tint_mat, col, _tint_level_now)
		on = true
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null


## The tell strength (the old flat overlay alpha; the drawn wash is capped, the rim carries the colour).
func tint_alpha() -> float:
	return _tint_level_now if _tint_on else 0.0
