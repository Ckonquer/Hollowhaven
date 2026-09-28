extends Node3D
## Bellcap Sentry look: a heavy, squat mushroom guardian (~1.7 m): a thick cream stem with a sleepy little face,
## two stubby feet, and a wide BELL-shaped cap (russet with cream spots, a bronze rim) with a round clapper hanging
## underneath. Faces -Z, feet at y = 0 - a wide top-heavy bell silhouette, unlike the tall Patchwalker.
## States (set_state): idle / wander / chase / return (a heavy waddle, the clapper sways), telegraph (the cap
## SWELLS up to SWELL_SCALE and glows red; pale outward ARROW symbols stand on the ground on the pulse ring and a
## bell symbol hangs above the cap - the whole attack reads with the sound muted), pulse (the cap squashes and a
## shock ring sweeps out to the pulse radius), recover (the cap droops and tilts, the clapper swings, dizzy stars),
## flinch, dead. set_radius(r) places the symbols on the pulse ring. play_anim(name) for previews.
## Tints / symbols pulse gently, or stay steady with Settings reduce_flashing.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const CAP_Y := 1.05
const STEM := Color("efe0c4")
const CAP := Color("a8452e")
const CAP_DARK := Color("7e3322")
const SPOT := Color("f7ecd6")
const BRONZE := Color("c9933e")
const SYMBOL := Color("fff2c8")
const PULSE_TINT := Color(0.98, 0.36, 0.24)
const SWELL_SCALE := 1.35
const ARROWS := 8
const SHOCK_TIME := 0.3

var state: String = "idle"
var state_len: float = 0.0
var radius: float = 4.0
var preview_walk := false
var swell: float = 0.0                 # 0 rest .. 1 fully swollen (tests)

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _body: Node3D
var _cap: Node3D
var _clapper: Node3D
var _feet: Array = []
var _symbols: Node3D
var _arrows: Array = []
var _glyph: Node3D
var _shock: MeshInstance3D
var _stars: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 1.7


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	var stem := Mat.outlined(Mat.toon(STEM, {"rim": 0.45, "noise": 0.15}), 0.014)
	for sx in [-1.0, 1.0]:
		var foot := Kit.blob(0.2, stem, 51 + int(sx), 0.1, 0.6, 2)
		Kit.add(_root, foot, Vector3(sx * 0.24, 0.1, -0.05), Vector3.ZERO, Vector3(1.0, 1.0, 1.3))
		_feet.append(foot)
	_body = Node3D.new()
	_body.name = "Body"
	_root.add_child(_body)
	var trunk := Kit.blob(0.4, stem, 52, 0.08, 1.35, 3)
	Kit.add(_body, trunk, Vector3(0, 0.55, 0))
	_tint_meshes.append(trunk)
	var ink := Mat.toon(Palette.UI_INK, {"rim": 0.2, "noise": 0.0, "specular": 0.5})
	for sx in [-1.0, 1.0]:
		Kit.add(_body, Kit.box(Vector3(0.08, 0.02, 0.02), ink), Vector3(sx * 0.11, 0.72, -0.38), Vector3(0, 0, sx * -8.0))
	Kit.add(_body, Kit.sphere(0.035, Mat.toon(Palette.BLOSSOM), 6, 8), Vector3(0, 0.62, -0.39), Vector3.ZERO, Vector3(1.4, 0.8, 0.6))
	# The bell cap (pivot for the swell / droop), its spots, bronze rim and clapper
	_cap = Node3D.new()
	_cap.name = "Cap"
	Kit.add(_body, _cap, Vector3(0, CAP_Y, 0))
	var cap_mat := Mat.outlined(Mat.toon(CAP, {"rim": 0.5, "noise": 0.15}), 0.016)
	var cap_dark := Mat.outlined(Mat.toon(CAP_DARK, {"rim": 0.4, "noise": 0.15}), 0.014)
	var bell := Kit.cylinder(0.3, 0.66, 0.5, cap_mat, 20)
	Kit.add(_cap, bell, Vector3(0, 0.08, 0))
	_tint_meshes.append(bell)
	var dome := Kit.sphere(0.31, cap_mat, 12, 18)
	Kit.add(_cap, dome, Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
	_tint_meshes.append(dome)
	Kit.add(_cap, Kit.cylinder(0.08, 0.1, 0.14, cap_dark, 10), Vector3(0, 0.56, 0))
	Kit.add(_cap, Kit.torus(0.6, 0.7, Mat.outlined(Mat.toon(BRONZE, {"rim": 0.5, "specular": 0.5}), 0.008)), Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
	var spot := Mat.toon(SPOT, {"rim": 0.2})
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		var r := 0.42 if i % 2 == 0 else 0.34
		var y := 0.02 if i % 2 == 0 else 0.2
		Kit.add(_cap, Kit.sphere(0.07, spot, 6, 8), Vector3(cos(a) * r, y, sin(a) * r), Vector3.ZERO, Vector3(1.0, 0.45, 1.0))
	_clapper = Node3D.new()
	_clapper.name = "Clapper"
	Kit.add(_cap, _clapper, Vector3(0, -0.02, 0))
	Kit.add(_clapper, Kit.cylinder(0.025, 0.025, 0.22, Mat.toon(BRONZE), 6), Vector3(0, -0.1, 0))
	Kit.add(_clapper, Kit.sphere(0.1, Mat.outlined(Mat.toon(BRONZE, {"specular": 0.5}), 0.008), 8, 10), Vector3(0, -0.24, 0))
	# Muted-readable symbols: outward arrows on the pulse ring + a bell glyph over the cap (hidden at rest)
	_symbols = Node3D.new()
	_symbols.name = "Symbols"
	_symbols.top_level = true
	add_child(_symbols)
	var sym_mat := Mat.glow(SYMBOL, 1.4)
	for i in ARROWS:
		var arrow := Node3D.new()
		arrow.name = "Arrow"
		_symbols.add_child(arrow)
		var head := Kit.prism(Vector3(0.36, 0.3, 0.05), sym_mat)
		head.set_meta("no_flash", true)
		Kit.add(arrow, head, Vector3(0, 0.05, 0.0), Vector3(-90, 0, 0))
		var shaft := Kit.box(Vector3(0.1, 0.03, 0.3), sym_mat)
		shaft.set_meta("no_flash", true)
		Kit.add(arrow, shaft, Vector3(0, 0.05, 0.25))
		_arrows.append(arrow)
	_glyph = Node3D.new()
	_glyph.name = "BellGlyph"
	_symbols.add_child(_glyph)
	var g1 := Kit.cylinder(0.08, 0.2, 0.22, sym_mat, 10)
	g1.set_meta("no_flash", true)
	_glyph.add_child(g1)
	var g2 := Kit.sphere(0.05, sym_mat, 6, 8)
	g2.set_meta("no_flash", true)
	Kit.add(_glyph, g2, Vector3(0, -0.16, 0))
	_symbols.visible = false
	# Shock ring of the pulse (expands to the radius)
	_shock = MeshInstance3D.new()
	_shock.name = "Shock"
	_shock.top_level = true
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 4
	_shock.mesh = tm
	_shock.material_override = Mat.transparent(Color(1.0, 0.9, 0.7, 0.55), true)
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock.set_meta("no_flash", true)
	_shock.visible = false
	add_child(_shock)
	_stars = Node3D.new()
	_stars.name = "Stars"
	_root.add_child(_stars)
	var star_mat := Mat.glow(Palette.FLOWER_YELLOW, 2.2)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Kit.add(_stars, Kit.sphere(0.05, star_mat, 6, 8), Vector3(cos(a) * 0.35, 0.0, sin(a) * 0.35))
	_stars.visible = false


func set_radius(r: float) -> void:
	radius = maxf(r, 0.5)


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	elif anim == "pulse":
		set_state("telegraph", 1.3)
	else:
		set_state(anim, 1.2)


func symbols_visible() -> bool:
	return _symbols.visible


## World positions of the arrow symbols (tests: they stand on the pulse ring).
func arrow_positions() -> Array:
	var out: Array = []
	for a in _arrows:
		out.append((a as Node3D).global_position)
	return out


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := 0.0
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 1.6
	var want_swell := 0.0
	var cap_rot := Vector3.ZERO
	var body_rot := Vector3.ZERO
	var squash := 1.0
	var tint := 0.0
	var show_symbols := false
	var clap := sin(_t * 2.0) * 0.12
	match state:
		"telegraph":
			var k := clampf(_st / maxf(state_len, 0.01), 0.0, 1.0)
			want_swell = k
			tint = (0.15 + 0.2 * k) if HitFx.reduce_flashing() else (0.18 + 0.22 * k * (0.6 + 0.4 * sin(_st * 14.0)))
			show_symbols = true
			clap = sin(_st * 20.0) * 0.08 * k
		"pulse":
			want_swell = 0.2
			squash = 0.75
			tint = 0.3
			show_symbols = true
		"recover":
			cap_rot = Vector3(0.25, 0.0, sin(_st * 2.4) * 0.2)
			body_rot.x = 0.08
			clap = sin(_st * 6.0) * 0.6
		"flinch":
			body_rot.x = -0.12 * (1.0 - clampf(_st / 0.3, 0.0, 1.0))
		"dead":
			cap_rot = Vector3(0.4, 0.0, 0.3)
		_:
			if speed > 0.2:
				body_rot.z = sin(_t * 5.0) * 0.08
				clap = sin(_t * 5.0) * 0.35
	var k_s := 1.0 - exp(-12.0 * delta)
	swell = lerpf(swell, want_swell, k_s * 1.5)
	var s := lerpf(1.0, SWELL_SCALE, swell)
	_cap.scale = _cap.scale.lerp(Vector3(s, s * squash, s), k_s * 1.5)
	_cap.rotation = _cap.rotation.lerp(cap_rot, k_s)
	_body.rotation = _body.rotation.lerp(body_rot, k_s)
	_clapper.rotation.x = lerpf(_clapper.rotation.x, clap, k_s)
	_update_symbols(show_symbols)
	_update_shock()
	_stars.visible = state == "recover"
	if _stars.visible:
		_stars.rotation.y = _t * 4.0
		_stars.position = Vector3(0.0, CAP_Y + 0.9, 0.0)
	_apply_tint(tint)


func _update_symbols(on: bool) -> void:
	_symbols.visible = on
	if not on:
		return
	var c := global_position
	var bob := 0.0 if HitFx.reduce_flashing() else sin(_st * 6.0) * 0.08
	for i in _arrows.size():
		var a := TAU * float(i) / float(_arrows.size())
		var dir := Vector3(sin(a), 0.0, cos(a))
		var arrow := _arrows[i] as Node3D
		# the arrow tip points away from the bell ("step out"), standing on the ring
		arrow.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), c + dir * radius + Vector3.UP * 0.02)
		arrow.position += dir * bob
	_glyph.global_position = c + Vector3.UP * (CAP_Y + 1.25 + bob)


func _update_shock() -> void:
	if state != "pulse":
		_shock.visible = false
		return
	var k := clampf(_st / SHOCK_TIME, 0.0, 1.0)
	_shock.visible = k < 1.0
	var r := lerpf(0.4, radius, k)
	_shock.global_transform = Transform3D(Basis.from_scale(Vector3(r, 0.4, r)), global_position + Vector3.UP * 0.25)


func _apply_tint(tint: float) -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	elif tint > 0.0:
		c = Color(PULSE_TINT, clampf(tint, 0.0, 1.0))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null


func tint_alpha() -> float:
	return _tint_mat.albedo_color.a if _tint_on else 0.0
