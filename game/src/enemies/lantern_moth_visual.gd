extends Node3D
## Lantern Moth look: a round, fuzzy cream moth with two pairs of lamp-bright wings (warm glowing eye-spots),
## a fluffy collar, feathery antennae and big dark eyes. The local origin is the body centre: the moth script
## lifts this node to its hover height (parent.hover_y). Wingspan ~1.3 m, body ~0.5 m: a wide, flat, bright
## silhouette that reads against dusk.
## States (set_state): idle / wander / chase / return (quick flutter and bob), telegraph (wings spread wide and
## FLARE bright - a steady brightening, never a strobe - the body tilts back and an orb swells in front),
## recover / stunned (resting: wings fold up, slow breathing flutter), flinch (jolt), dead (wings fold).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BODY_COLOR := Color("f3e6c8")
const FUZZ_COLOR := Color("fff4e0")
const STRIPE_COLOR := Color("d9c296")
const WING_COLOR := Color("ffd98a")
const WING_LOW := Color("f5c46f")
const FLARE_COLOR := Color("fff0b8")
const SPOT_COLOR := Color("ff9f4a")
const ORB_COLOR := Color(1.0, 0.82, 0.46)
const PREVIEW_HEIGHT := 1.0

var state: String = "idle"
var state_len: float = 0.0
var preview := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _body: Node3D
var _wings: Array = []          # wing pivots, [left, right]
var _wing_meshes: Array = []
var _orb: MeshInstance3D
var _wing_mat: Material
var _wing_low_mat: Material
var _flare_mat: Material
var _flared := false
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 0.5


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var body_mat := Mat.outlined(Mat.toon(BODY_COLOR, {"rim": 0.6, "noise": 0.25}), 0.012)
	var thorax := Kit.blob(0.19, body_mat, 21, 0.12, 1.05, 3)
	_body.add_child(thorax)
	_tint_meshes.append(thorax)
	var abdomen := Kit.blob(0.15, body_mat, 22, 0.08, 1.0, 3)
	Kit.add(_body, abdomen, Vector3(0, -0.03, 0.2), Vector3(15, 0, 0), Vector3(0.9, 0.9, 1.35))
	_tint_meshes.append(abdomen)
	var stripe_mat := Mat.toon(STRIPE_COLOR, {"rim": 0.2, "noise": 0.0})
	for i in 2:
		Kit.add(_body, Kit.torus(0.1, 0.13, stripe_mat), Vector3(0, -0.03, 0.17 + 0.09 * float(i)), Vector3(90 - 15, 0, 0), Vector3(1.0, 1.0, 0.9))
	var fuzz_mat := Mat.outlined(Mat.toon(FUZZ_COLOR, {"rim": 0.7, "noise": 0.3}), 0.008)
	for i in 7:
		var a := TAU * float(i) / 7.0
		Kit.add(_body, Kit.sphere(0.07, fuzz_mat, 8, 10), Vector3(cos(a) * 0.14, sin(a) * 0.12 + 0.02, -0.1))
	var head := Kit.sphere(0.11, body_mat, 10, 14)
	Kit.add(_body, head, Vector3(0, 0.04, -0.2))
	_tint_meshes.append(head)
	var ink := Mat.toon(Palette.UI_INK, {"rim": 0.3, "noise": 0.0, "specular": 0.6})
	for sx in [-1.0, 1.0]:
		Kit.add(_body, Kit.sphere(0.055, ink, 10, 12), Vector3(sx * 0.07, 0.07, -0.27))
		var hl := Kit.sphere(0.014, Mat.glow(Palette.FLOWER_WHITE, 1.4), 6, 8)
		hl.set_meta("no_flash", true)
		Kit.add(_body, hl, Vector3(sx * 0.06, 0.1, -0.32))
		# feathery antennae
		var ant := Node3D.new()
		Kit.add(_body, ant, Vector3(sx * 0.05, 0.13, -0.24), Vector3(-35.0, 0.0, sx * -25.0))
		Kit.add(ant, Kit.capsule(0.012, 0.22, Mat.toon(STRIPE_COLOR)), Vector3(0, 0.1, 0))
		Kit.add(ant, Kit.sphere(0.06, fuzz_mat, 8, 10), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(0.5, 1.0, 0.18))
		# little dangling legs
		for j in 2:
			Kit.add(_body, Kit.capsule(0.012, 0.12, Mat.toon(STRIPE_COLOR)), Vector3(sx * 0.07, -0.16, -0.06 + 0.1 * float(j)), Vector3(0, 0, sx * 18.0))
	# Wings
	_wing_mat = Mat.outlined(Mat.toon(WING_COLOR, {"rim": 0.5, "noise": 0.05, "emission": Palette.LANTERN_GLOW, "emission_energy": 0.55}), 0.01)
	_wing_low_mat = Mat.outlined(Mat.toon(WING_LOW, {"rim": 0.5, "noise": 0.05, "emission": Palette.LANTERN_GLOW, "emission_energy": 0.45}), 0.01)
	_flare_mat = Mat.glow(FLARE_COLOR, 2.8)
	var spot_mat := Mat.glow(SPOT_COLOR, 1.6)
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "Wing"
		Kit.add(_body, pivot, Vector3(sx * 0.1, 0.06, -0.02))
		var upper := Kit.sphere(0.32, _wing_mat, 12, 16)
		Kit.add(pivot, upper, Vector3(sx * 0.32, 0.0, -0.06), Vector3(0, sx * -12.0, 0), Vector3(1.0, 0.06, 0.72))
		var lower := Kit.sphere(0.21, _wing_low_mat, 10, 14)
		Kit.add(pivot, lower, Vector3(sx * 0.2, -0.03, 0.17), Vector3(0, sx * 20.0, 0), Vector3(0.9, 0.05, 0.78))
		var spot := Kit.sphere(0.07, spot_mat, 8, 10)
		spot.set_meta("no_flash", true)
		Kit.add(pivot, spot, Vector3(sx * 0.4, 0.025, -0.08), Vector3.ZERO, Vector3(1.0, 0.25, 1.0))
		_wings.append(pivot)
		_wing_meshes.append(upper)
		_wing_meshes.append(lower)
		_tint_meshes.append(upper)
	# The orb that swells during the wind-up
	_orb = Kit.sphere(0.16, Mat.glow(ORB_COLOR, 2.4), 10, 14)
	_orb.name = "Orb"
	_orb.set_meta("no_flash", true)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_body, _orb, Vector3(0, 0.02, -0.4))
	_orb.scale = Vector3.ONE * 0.01
	_orb.visible = false


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func play_anim(anim: String) -> void:
	preview = true
	set_state("chase" if anim == "walk" else anim, 1.2)


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func is_flaring() -> bool:
	return _flared


func orb_scale() -> float:
	return _orb.scale.x if _orb.visible else 0.0


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var p := get_parent()
	var h := PREVIEW_HEIGHT
	if p != null and "hover_y" in p and not preview:
		h = float(p.get("hover_y"))
	var flap_freq := 9.0
	var flap_amp := 0.55
	var flap_base := 0.1
	var tilt := Vector3.ZERO
	var bob := sin(_t * 2.3) * 0.05
	var flare := false
	var orb_k := 0.0
	var wing_s := 1.0
	match state:
		"telegraph":
			var k := clampf(_st / maxf(state_len, 0.05), 0.0, 1.0)
			flap_freq = 26.0
			flap_amp = 0.05                          # wings held wide open, just trembling
			flap_base = -0.12
			wing_s = 1.0 + 0.15 * clampf(_st / 0.2, 0.0, 1.0)
			tilt.x = -0.3 * clampf(_st / 0.25, 0.0, 1.0)
			flare = true
			orb_k = k
			bob *= 0.3
		"recover", "stunned":
			flap_freq = 2.0
			flap_amp = 0.12
			flap_base = 1.05                          # resting: wings folded up
			tilt.x = 0.12
			bob = sin(_t * 1.6) * 0.02
		"flinch":
			tilt.x = 0.35 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			flap_freq = 3.0
			flap_amp = 0.2
			flap_base = 1.2
	var k_s := 1.0 - exp(-14.0 * delta)
	position.y = h + bob
	_body.rotation = _body.rotation.lerp(tilt, k_s)
	for i in _wings.size():
		var w := _wings[i] as Node3D
		var side := -1.0 if i == 0 else 1.0
		var ang := flap_base + sin(_t * flap_freq * TAU / 3.0) * flap_amp
		w.rotation.z = lerpf(w.rotation.z, -side * ang, clampf(k_s * 2.0, 0.0, 1.0))
		w.scale = w.scale.lerp(Vector3(wing_s, 1.0, wing_s), k_s)
	_set_flare(flare)
	_orb.visible = orb_k > 0.01
	if _orb.visible:
		_orb.scale = Vector3.ONE * lerpf(0.2, 1.0, orb_k)
	_apply_tint()


func _set_flare(on: bool) -> void:
	if on == _flared:
		return
	_flared = on
	for i in _wing_meshes.size():
		var mi := _wing_meshes[i] as MeshInstance3D
		if on:
			mi.material_override = _flare_mat
		else:
			mi.material_override = _wing_mat if i % 2 == 0 else _wing_low_mat


func _apply_tint() -> void:
	var on := _flash_t > 0.0
	if on:
		_tint_mat.albedo_color = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
