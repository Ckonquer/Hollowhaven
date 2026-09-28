extends Node3D
## Borrowed Wisp look. The local origin is the wisp's centre: the enemy lifts this node to parent.hover_y.
##   veiled    a big, soft, WARM orb of false light (emissive only: there is deliberately NO Light3D anywhere in
##             this visual, so nothing around it is lit) in a faint halo, a small carved wooden mask floating in
##             front and three harvest ribbons trailing below.
##   revealed  (set_revealed(true)) the orb shrinks to a small, COLD flicker, a dark hood and a wispy tail form
##             around it and the mask grows bold and close - a hooded masked shape: a different SIZE, SHAPE and
##             HEIGHT from the veiled light (never colour alone).
## States (set_state): idle / wander / chase / return (a slow bob, ribbons drifting), telegraph (the ribbons lift
## and sweep back to one side, amber tint), sweep_wait (held back, brightening), sweep (the ribbons swing across),
## recover / stunned (droops; stunned = dazzled, the mask tilts and spins slowly), flinch, dead.
## play_anim(name) for previews ("revealed" shows the true form). Tints stay steady with reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const FALSE_GLOW := Color("ffb45e")
const HALO := Color(1.0, 0.78, 0.45, 0.22)
const TRUE_FLAME := Color("bfe0ff")
const HOOD := Color("3b3346")
const MASK := Color("d8b88a")
const MASK_DARK := Color("6e5236")
const RIBBONS := [Color("e9a15b"), Color("d9546a"), Color("f2c14e")]
const SWEEP_TINT := Color(1.0, 0.68, 0.26)
const PREVIEW_HEIGHT := 1.4

var state: String = "idle"
var state_len: float = 0.0
var revealed := false
var preview := false
var reveal_k: float = 0.0              # 0 veiled .. 1 revealed (tests)

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _float: Node3D
var _orb: MeshInstance3D
var _halo: MeshInstance3D
var _flame: MeshInstance3D
var _true: Node3D
var _mask: Node3D
var _ribbons: Array = []
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 0.8


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_float = Node3D.new()
	_float.name = "Float"
	add_child(_float)
	# The false light (veiled)
	_orb = Kit.sphere(0.32, Mat.glow(FALSE_GLOW, 2.2), 12, 16)
	_orb.name = "FalseLight"
	_orb.set_meta("no_flash", true)
	_float.add_child(_orb)
	_halo = Kit.sphere(0.55, Mat.transparent(HALO, true), 10, 14)
	_halo.name = "Halo"
	_halo.set_meta("no_flash", true)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float.add_child(_halo)
	# The true form (revealed): hood, tail and a small cold flame
	_true = Node3D.new()
	_true.name = "TrueForm"
	_float.add_child(_true)
	var hood := Mat.outlined(Mat.toon(HOOD, {"rim": 0.6, "noise": 0.2}), 0.012)
	var head := Kit.sphere(0.26, hood, 10, 14)
	Kit.add(_true, head, Vector3(0, 0.08, 0.02), Vector3.ZERO, Vector3(1.0, 1.1, 1.0))
	_tint_meshes.append(head)
	var tail := Kit.cone(0.24, 0.7, hood, 10)
	Kit.add(_true, tail, Vector3(0, -0.42, 0.06), Vector3(180 - 12, 0, 0))
	_tint_meshes.append(tail)
	Kit.add(_true, Kit.cone(0.1, 0.22, hood, 8), Vector3(0, 0.36, 0.08), Vector3(-25, 0, 0))
	_flame = Kit.sphere(0.09, Mat.glow(TRUE_FLAME, 1.6), 8, 10)
	_flame.set_meta("no_flash", true)
	Kit.add(_true, _flame, Vector3(0, 0.05, -0.12))
	# The carved mask (both forms; bold and close when revealed)
	_mask = Node3D.new()
	_mask.name = "Mask"
	Kit.add(_float, _mask, Vector3(0, 0.02, -0.36))
	var mask := Mat.outlined(Mat.toon(MASK, {"rim": 0.35, "noise": 0.2}), 0.01)
	var face := Kit.cylinder(0.16, 0.16, 0.04, mask, 16)
	Kit.add(_mask, face, Vector3.ZERO, Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.2))
	_tint_meshes.append(face)
	var dark := Mat.toon(MASK_DARK, {"rim": 0.0, "noise": 0.0})
	for sx in [-1.0, 1.0]:
		Kit.add(_mask, Kit.sphere(0.035, dark, 6, 8), Vector3(sx * 0.06, 0.04, -0.02), Vector3.ZERO, Vector3(1.0, 1.3, 0.5))
	Kit.add(_mask, Kit.box(Vector3(0.1, 0.018, 0.02), dark), Vector3(0, -0.06, -0.02))
	# Harvest ribbons trailing below
	for i in RIBBONS.size():
		var piv := Node3D.new()
		piv.name = "Ribbon"
		Kit.add(_float, piv, Vector3((float(i) - 1.0) * 0.12, -0.2, 0.05))
		var col: Color = RIBBONS[i]
		var strip := Kit.box(Vector3(0.05, 0.5, 0.012), Mat.outlined(Mat.toon(col, {"rim": 0.3}), 0.006))
		Kit.add(piv, strip, Vector3(0, -0.25, 0))
		_ribbons.append(piv)
	_apply_form(0.0)


func set_revealed(on: bool) -> void:
	revealed = on


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func play_anim(anim: String) -> void:
	preview = true
	if anim == "revealed":
		revealed = true
		set_state("chase")
	elif anim == "sweep":
		set_state("telegraph", 1.4)
	else:
		set_state(anim, 1.2)


func _apply_form(k: float) -> void:
	_orb.scale = Vector3.ONE * lerpf(1.0, 0.25, k)
	_halo.visible = k < 0.9
	_halo.scale = Vector3.ONE * lerpf(1.0, 0.4, k)
	_true.visible = k > 0.05
	_true.scale = Vector3.ONE * maxf(k, 0.05)
	_mask.scale = Vector3.ONE * lerpf(0.7, 1.35, k)
	_mask.position = Vector3(0, 0.1 * k, lerpf(-0.36, -0.3, k))


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var h := PREVIEW_HEIGHT
	var p := get_parent()
	if p != null and "hover_y" in p and not preview:
		h = float(p.get("hover_y"))
	position.y = h
	reveal_k = move_toward(reveal_k, 1.0 if revealed else 0.0, delta * 4.0)
	_apply_form(reveal_k)
	var bob := sin(_t * 1.6) * 0.06
	var lean := Vector3.ZERO
	var ribbon := sin(_t * 2.0) * 0.25
	var tint := 0.0
	match state:
		"telegraph":
			var k := clampf(_st / 0.3, 0.0, 1.0)
			ribbon = lerpf(ribbon, -1.6, k)
			lean = Vector3(0.0, 0.5 * k, 0.15 * k)
			tint = (0.3 * k) if HitFx.reduce_flashing() else (0.2 + 0.2 * (0.5 + 0.5 * sin(_st * 16.0)))
		"sweep_wait":
			ribbon = -1.7
			lean = Vector3(0.0, 0.6, 0.18)
			tint = 0.45
		"sweep":
			var s := clampf(_st / 0.2, 0.0, 1.0)
			ribbon = lerpf(-1.7, 1.6, s)
			lean = Vector3(0.0, lerpf(0.6, -0.6, s), 0.0)
			tint = 0.3
		"recover":
			bob -= 0.1
			lean.x = 0.3
			ribbon = 0.1
		"stunned":
			lean = Vector3(0.2, _st * 3.0, sin(_st * 5.0) * 0.3)
		"flinch":
			lean.x = -0.4 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			ribbon = 0.0
	var k_s := 1.0 - exp(-10.0 * delta)
	_float.position.y = lerpf(_float.position.y, bob, k_s)
	_float.rotation = _float.rotation.lerp(lean, k_s)
	for i in _ribbons.size():
		var r := _ribbons[i] as Node3D
		r.rotation.z = lerpf(r.rotation.z, ribbon + sin(_t * 3.0 + float(i)) * 0.15, k_s)
	if not HitFx.reduce_flashing():
		_flame.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * 11.0))
	_apply_tint(tint)


func _apply_tint(tint: float) -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	elif tint > 0.0:
		c = Color(SWEEP_TINT, clampf(tint, 0.0, 1.0))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null


func tint_alpha() -> float:
	return _tint_mat.albedo_color.a if _tint_on else 0.0
