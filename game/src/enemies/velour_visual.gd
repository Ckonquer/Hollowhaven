extends Node3D
## Count Velour, the fighting figure (MP 13.1). An ORIGINAL small floating host: a round bat-mask over a pale
## face (no realistic face, no mouth, no lip-sync - two glowing eye-slits), big pointed bat ears, an OVERSIZED
## velvet cape (crimson outside, rose lining) that swirls and flares, a flamboyant two-fan collar with a gold
## neck ring, a tiny tilted crown with a jewel, and little white gloves. Matches the non-hostile resident
## (src/world/manor/count_resident.gd) so the freed Count is recognisably the same fellow.
## Local origin = the figure's centre (the boss lifts this node to its hover height; the height IS the reach tell).
##
## set_state(name, length) poses (the boss mirrors its logic states here, never the other way round):
##   dormant / intro   hand on heart, a slow theatrical bob (intro = a deep sweeping bow)
##   glide             hovering, cape billowing behind, head tilted toward Krystal
##   bow               the dash tell: bows deep, cape wrapped forward, red tint firming up (steady with reduce_flashing)
##   flourish          Intense feint: flicks the cape wide open and straightens (no tint - "not yet")
##   final_tell        Intense true tell: cape raised high, the CROWN FLASHES gold (a separate, distinct tell)
##   dash              pitched forward, cape streaming back
##   recoil / drain_rest / channel_rest   dizzy: tilted, three little stars circling his crown
##   drain_tele / drain   arms and cape spread wide, eye-slits glow, plum tint
##   disperse          spins and shrinks away (the boss then hides him while the bats fly)
##   reform            pops back from a swirl, dazed (stars); set_revealed(true) adds a gold candle-light halo
##   channel_fly / channel   leans toward the candle, cape billowing, violet tint (channel = stationary)
##   stagger           reeling from light: mask askew, cape limp, stars, sinks low
##   transition        a dramatic twirl with the cape flared (phase change)
## hit_flash(duration) is combined with the tint (one overlay). Emotes read with the sound muted.

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const CreatureFx := preload("res://src/enemies/creature_fx.gd")

const VELVET := Color("7d1e3c")
const LINING := Color("c2587e")
const MASK := Color("2a1830")
const SKIN := Color("d9c8e8")
const GOLD := Color("e2bd5e")
const GLOVE := Color("f6efe6")
const EYE := Color("ffd27a")
const EYE_HOT := Color("ff8fd0")
const DASH_TINT := Color(0.98, 0.34, 0.26)
const DRAIN_TINT := Color(0.86, 0.36, 0.62)
const CHANNEL_TINT := Color(0.55, 0.4, 0.95)
const REVEAL := Color(1.0, 0.86, 0.5)

var state: String = "dormant"
var state_len: float = 0.0
var revealed := false
var crown_glint: float = 0.0          # 0..1 (tests / final tell)
var flare: float = 0.0                # 0 wrapped .. 1 flared wide

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _root: Node3D
var _body: Node3D
var _head: Node3D
var _cape: Node3D
var _flaps: Array = []
var _hands: Array = []
var _eyes: Array = []
var _eye_mat: Material
var _eye_hot_mat: Material
var _eyes_hot := false
var _crown: Node3D
var _glint: MeshInstance3D
var _stars: Node3D
var _halo: Node3D
var _tint_mat: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 1.3


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0
	if new_state != "reform" and new_state != "stagger":
		revealed = false


func set_revealed(on: bool) -> void:
	revealed = on


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


## Preview stage (tests/preview): poses the figure at hover height above the stage floor.
func play_anim(anim: String) -> void:
	position.y = 1.4
	set_state(anim, 1.2)
	set_revealed(anim == "reform")


func eyes_hot() -> bool:
	return _eyes_hot


func tint_alpha() -> float:
	return _tint_mat.albedo_color.a if _tint_on else 0.0


# --- Build ---------------------------------------------------------------------------------------------------

func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	_body = Node3D.new()
	_body.name = "Body"
	_root.add_child(_body)
	var velvet := Mat.outlined(Mat.toon(VELVET, {"rim": 0.55, "noise": 0.1}), 0.016)
	var lining := Mat.toon(LINING, {"rim": 0.4})
	var mask := Mat.outlined(Mat.toon(MASK, {"rim": 0.5}), 0.012)
	var skin := Mat.outlined(Mat.toon(SKIN, {"rim": 0.45}), 0.012)
	var gold := Mat.toon(GOLD, {"rim": 0.6, "specular": 0.45})
	var glove := Mat.toon(GLOVE, {"rim": 0.3})
	# The oversized cape: a wide bell, its rose lining, and two big flaps that flare / wrap.
	_cape = Node3D.new()
	_cape.name = "Cape"
	_body.add_child(_cape)
	var bell := Kit.cylinder(0.17, 0.62, 0.98, velvet, 16)
	Kit.add(_cape, bell, Vector3(0, -0.2, 0))
	_tint_meshes.append(bell)
	Kit.add(_cape, Kit.cylinder(0.15, 0.52, 0.86, lining, 14), Vector3(0, -0.22, 0.1))
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "FlapL" if s < 0.0 else "FlapR"
		pivot.position = Vector3(float(s) * 0.16, 0.26, 0.0)
		pivot.set_meta("side", float(s))
		_cape.add_child(pivot)
		var f := Kit.sphere(0.34, velvet, 10, 12)
		Kit.add(pivot, f, Vector3(float(s) * 0.3, -0.34, 0.02), Vector3(0, 0, float(s) * 12.0), Vector3(0.95, 1.35, 0.16))
		Kit.add(pivot, Kit.sphere(0.3, lining, 8, 10), Vector3(float(s) * 0.29, -0.33, 0.055), Vector3(0, 0, float(s) * 12.0), Vector3(0.85, 1.2, 0.08))
		# Scalloped hem points (bat-wing edge).
		for k in 3:
			Kit.add(pivot, Kit.cone(0.06, 0.16, velvet, 5), Vector3(float(s) * (0.12 + 0.17 * float(k)), -0.8 + 0.06 * float(k), 0.02), Vector3(180, 0, 0))
		_tint_meshes.append(f)
		_flaps.append(pivot)
	# Flamboyant collar: two tall fans behind the head and the gold neck ring.
	for s in [-1.0, 1.0]:
		Kit.add(_body, Kit.sphere(0.27, velvet, 10, 12), Vector3(float(s) * 0.2, 0.44, -0.1), Vector3(0, 0, float(s) * -18.0), Vector3(0.9, 1.3, 0.18))
		Kit.add(_body, Kit.sphere(0.23, lining, 10, 12), Vector3(float(s) * 0.19, 0.43, -0.07), Vector3(0, 0, float(s) * -18.0), Vector3(0.8, 1.15, 0.1))
	Kit.add(_body, Kit.torus(0.14, 0.2, gold), Vector3(0, 0.25, 0))
	# Head: pale round face, the bat mask with glowing slits, bat ears, the tiny tilted crown.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.5, 0.02)
	_body.add_child(_head)
	var face := Kit.sphere(0.22, skin, 12, 16)
	_head.add_child(face)
	_tint_meshes.append(face)
	Kit.add(_head, Kit.sphere(0.18, mask, 8, 12), Vector3(0, 0.04, 0.12), Vector3.ZERO, Vector3(1.45, 0.55, 0.6))
	_eye_mat = Mat.glow(EYE, 2.0)
	_eye_hot_mat = Mat.glow(EYE_HOT, 3.2)
	for s in [-1.0, 1.0]:
		Kit.add(_head, Kit.sphere(0.11, mask, 8, 10), Vector3(float(s) * 0.24, 0.08, 0.08), Vector3(0, 0, float(s) * -25.0), Vector3(1.4, 0.6, 0.3))
		var e := Kit.sphere(0.032, _eye_mat, 6, 8)
		Kit.add(_head, e, Vector3(float(s) * 0.075, 0.05, 0.22), Vector3.ZERO, Vector3(1.4, 0.7, 1.0))
		_eyes.append(e)
		Kit.add(_head, Kit.cone(0.075, 0.24, mask, 8), Vector3(float(s) * 0.14, 0.3, -0.02), Vector3(0, 0, float(s) * -16.0))
	_crown = Node3D.new()
	_crown.name = "Crown"
	_crown.position = Vector3(0.04, 0.3, 0.0)
	_crown.rotation = Vector3(0, 0, deg_to_rad(-12.0))
	_head.add_child(_crown)
	Kit.add(_crown, Kit.cylinder(0.09, 0.08, 0.07, gold, 10))
	for k in 5:
		var a := TAU * float(k) / 5.0
		Kit.add(_crown, Kit.cone(0.022, 0.075, gold, 6), Vector3(cos(a) * 0.075, 0.07, sin(a) * 0.075))
	Kit.add(_crown, Kit.sphere(0.028, Mat.glow(Color("ff6f9a"), 1.6), 6, 8), Vector3(0, 0.03, 0.09))
	_glint = Kit.sphere(0.16, Mat.transparent(Color(1.0, 0.92, 0.6, 0.55), true), 8, 10)
	_crown.add_child(_glint)
	_glint.position = Vector3(0, 0.05, 0)
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.set_meta("no_flash", true)
	_glint.visible = false
	# Little white gloves.
	for s in [-1.0, 1.0]:
		var h := Kit.sphere(0.075, glove, 8, 10)
		Kit.add(_body, h, Vector3(float(s) * 0.26, 0.05, 0.22))
		_hands.append(h)
	# Dazed stars and the candle-light halo (reveal / stagger windows).
	_stars = Node3D.new()
	_stars.name = "Stars"
	_body.add_child(_stars)
	for k in 3:
		var st := Kit.sphere(0.05, Mat.glow(Color("fff1b0"), 2.2), 5, 6)
		var a := TAU * float(k) / 3.0
		Kit.add(_stars, st, Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3))
		st.set_meta("no_flash", true)
	_stars.visible = false
	# Candle-light reveal (CR-11: was a torus through the cape at waist height, read as a hula hoop): a soft warm
	# glow BEHIND the figure (the far half of a glow ball only, so it never veils him) and a thin gold halo ring
	# floating above the crown.
	_halo = Node3D.new()
	_halo.name = "RevealHalo"
	_body.add_child(_halo)
	var aura := Kit.sphere(1.3, CreatureFx.soft_glow(Color(REVEAL.r, REVEAL.g, REVEAL.b, 0.8), 1.2, 6.0, true), 14, 18)
	aura.set_meta("no_flash", true)
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_halo, aura, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(0.9, 1.1, 0.9))
	var ring := Kit.torus(0.14, 0.2, Mat.glow(REVEAL, 1.8))
	ring.set_meta("no_flash", true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_halo, ring, Vector3(0.03, 1.12, 0.0), Vector3(0, 0, -8))
	_halo.set_meta("no_flash", true)
	_halo.visible = false
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi != _glint and not (mi as Node).has_meta("no_flash"):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Animation -------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var k_len := clampf(_st / maxf(state_len, 0.01), 0.0, 1.0)
	var pitch := 0.0
	var roll := 0.0
	var spin := 0.0
	var want_flare := 0.25
	var wrap := 0.0
	var bob := sin(_t * 1.8) * 0.05
	var tint := 0.0
	var tint_col := DASH_TINT
	var hot := false
	var stars := false
	var glint := 0.0
	var scl := 1.0
	var hand_r := Vector3(0.26, 0.05, 0.22)
	var hand_l := Vector3(-0.26, 0.05, 0.22)
	match state:
		"dormant":
			hand_l = Vector3(-0.08, 0.18, 0.24)          # hand on heart
		"intro":
			pitch = sin(clampf(_st / 1.6, 0.0, 1.0) * PI) * 0.75
			hand_r = Vector3(0.42, -0.1, 0.3)
			want_flare = 0.6
		"glide":
			want_flare = 0.35 + sin(_t * 1.3) * 0.1
			roll = sin(_t * 0.9) * 0.08
		"bow":
			var k := clampf(_st / 0.45, 0.0, 1.0)
			pitch = 0.7 * k
			wrap = 1.0
			want_flare = 0.0
			hand_r = Vector3(0.36, -0.12, 0.34)
			tint = _tint_level(k_len)
		"flourish":
			want_flare = 1.0
			spin = sin(clampf(_st / maxf(state_len, 0.01), 0.0, 1.0) * PI) * 0.6
			hand_r = Vector3(0.5, 0.35, 0.1)
		"final_tell":
			want_flare = 0.9
			pitch = 0.35
			glint = 1.0
			hand_r = Vector3(0.3, 0.45, 0.1)
			tint = _tint_level(k_len)
		"dash":
			pitch = 1.0
			wrap = 0.6
			want_flare = 0.0
		"recoil", "drain_rest", "channel_rest":
			stars = true
			roll = sin(_t * 5.0) * 0.25
			pitch = -0.2
			want_flare = 0.2
			bob = sin(_t * 3.0) * 0.03
		"drain_tele", "drain":
			want_flare = 1.0
			hot = true
			hand_r = Vector3(0.55, 0.15, 0.2)
			hand_l = Vector3(-0.55, 0.15, 0.2)
			tint_col = DRAIN_TINT
			tint = _tint_level(1.0 if state == "drain" else k_len) * (0.7 if state == "drain" else 1.0)
		"disperse":
			spin = _st * 14.0
			scl = maxf(1.0 - k_len, 0.05)
			want_flare = 1.0
		"reform":
			stars = true
			scl = clampf(0.3 + _st / 0.4, 0.3, 1.0)
			roll = sin(_t * 4.0) * 0.2
			want_flare = 0.5
		"channel_fly", "channel":
			pitch = 0.3
			want_flare = 0.8 + sin(_t * 6.0) * 0.1
			hot = state == "channel"
			hand_r = Vector3(0.4, 0.1, 0.4)
			hand_l = Vector3(-0.4, 0.1, 0.4)
			tint_col = CHANNEL_TINT
			tint = _tint_level(k_len) * (0.8 if state == "channel" else 0.5)
		"stagger":
			stars = true
			pitch = -0.35
			roll = 0.3 + sin(_t * 3.0) * 0.12
			want_flare = 0.05
			bob = sin(_t * 2.0) * 0.02
		"transition":
			spin = _st * 9.0
			want_flare = 1.0
			hand_r = Vector3(0.5, 0.35, 0.1)
		"hidden":
			scl = 0.05
	var ks := 1.0 - exp(-10.0 * delta)
	flare = lerpf(flare, want_flare, ks)
	crown_glint = lerpf(crown_glint, glint, 1.0 - exp(-14.0 * delta))
	_root.rotation = Vector3(lerp_angle(_root.rotation.x, pitch, ks), spin, lerp_angle(_root.rotation.z, roll, ks))
	_root.scale = Vector3.ONE * scl
	_body.position.y = bob
	for p in _flaps:
		var s: float = float((p as Node).get_meta("side", 1.0))
		var open := flare * 1.1
		var fold := wrap * 0.9
		(p as Node3D).rotation = Vector3(0.0, s * -fold, s * (open + sin(_t * 2.2 + s) * 0.06))
	_cape.scale = Vector3(1.0 + flare * 0.15, 1.0, 1.0 + sin(_t * 2.0) * 0.03)
	(_hands[0] as Node3D).position = (_hands[0] as Node3D).position.lerp(hand_l, ks)
	(_hands[1] as Node3D).position = (_hands[1] as Node3D).position.lerp(hand_r, ks)
	if hot != _eyes_hot:
		_eyes_hot = hot
		for e in _eyes:
			(e as MeshInstance3D).material_override = _eye_hot_mat if hot else _eye_mat
	_glint.visible = crown_glint > 0.05
	if _glint.visible:
		var g := crown_glint * (1.0 if HitFx.reduce_flashing() else 0.8 + 0.2 * sin(_t * 16.0))
		_glint.scale = Vector3.ONE * (0.6 + 0.8 * g)
	_stars.visible = stars
	if stars:
		_stars.rotation.y = _t * 4.0
		_stars.position = Vector3(0, 0.95, 0)
	_halo.visible = revealed and (state == "reform" or state == "stagger")
	if _halo.visible:
		_halo.rotation.y = _t * 1.5
	_apply_tint(tint, tint_col)


func _tint_level(k: float) -> float:
	if HitFx.reduce_flashing():
		return 0.12 + 0.2 * k
	return 0.15 + 0.2 * k + 0.12 * (0.5 + 0.5 * sin(_st * 16.0))


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
