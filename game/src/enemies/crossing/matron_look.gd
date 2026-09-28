extends Node3D
## The escaped Matron's look for the Weaver's Crossing (MP 13.2), built by COMPOSITION around the Chapter One
## visuals (weaver_visual.gd / shade_visual.gd are reused untouched as the inner body):
##   silk mode (arachnophobia OFF): the Weaver Matron (WeaverVisual, scale 2.6) + what she carries out of the
##       Heartseed Chamber: a dull ember SCAR ringing her abdomen (the braziers' burn) and a frayed MANTLE of
##       torn silk streamers trailing behind - a distinct silhouette from the Chapter One boss;
##   arachnophobia ON: the Hollow Mother (ShadeVisual, scale 2.3, upright, floats beneath the stone seals) +
##       two long drifting pale VEILS from her shoulders and a circlet of pale ROOTS above her hood.
## Both: a soft COIL HALO that brightens for the delayed pounce's final preparation (set_final_tell), steady
## with Settings reduce_flashing. The inner visual gets the boss's states unchanged (duck-typed contract:
## set_state, set_clinging, hit_flash, body_height, supports_state) - the swap happens live (set_alt).
##   var look = MatronLook.new(); look.setup({"alt": false}); boss.add_child(look)

const WeaverVisual := preload("res://src/enemies/weaver_visual.gd")
const ShadeVisual := preload("res://src/enemies/shade_visual.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const WEAVER_SCALE := 2.6
const SHADE_SCALE := 2.3
const SCAR := Color("7a3a22")
const SCAR_GLOW := Color("ff7a3a")
const MANTLE := Color(0.9, 0.88, 0.96, 0.75)
const VEIL := Color(0.86, 0.94, 0.84, 0.55)
const ROOT := Color("cdbfa3")
const HALO_SILK := Color(1.0, 0.8, 0.62)
const HALO_ALT := Color(0.95, 1.0, 0.86)

var alt := false
var inner: Node3D = null
var state: String = "idle"
var state_len: float = 0.0
var final_tell := false

var _extras: Node3D = null
var _streamers: Array = []
var _halo: MeshInstance3D = null
var _halo_mat: StandardMaterial3D = null
var _clinging := false
var _t: float = 0.0


func setup(p: Dictionary) -> void:
	alt = bool(p.get("alt", alt))


func _ready() -> void:
	_build()


## The live arachnophobia swap: rebuilds the body and extras; the boss's timers are untouched.
func set_alt(on: bool) -> void:
	if on == alt and inner != null:
		return
	alt = on
	_build()


func uses_shade() -> bool:
	return alt


# --- The inner visual's contract, forwarded -----------------------------------------------------------------

func set_state(s: String, length: float = 0.0) -> void:
	state = s
	state_len = length
	if inner != null and inner.has_method("set_state"):
		var vs := s
		if not supports_state(s):
			vs = "telegraph" if s in ["spit", "channel"] else "idle"
		inner.call("set_state", vs, length)


func set_clinging(on: bool) -> void:
	_clinging = on
	if inner != null and inner.has_method("set_clinging"):
		inner.call("set_clinging", on)


func supports_state(s: String) -> bool:
	if inner != null and inner.has_method("supports_state"):
		return bool(inner.call("supports_state", s))
	return s in ["idle", "move", "telegraph", "lunge", "recoil", "stunned", "shriek", "dead"]


func hit_flash(duration: float = 0.11) -> void:
	if inner != null and inner.has_method("hit_flash"):
		inner.call("hit_flash", duration)


func body_height() -> float:
	if inner != null and inner.has_method("body_height"):
		return float(inner.call("body_height"))
	return 1.2


## The delayed pounce's final preparation: the coil halo swells bright (visible half of the tell).
func set_final_tell(on: bool) -> void:
	final_tell = on


## Visual previews (tests/preview/preview_stage.gd --preview-anim=<name>): "final" shows the coil halo.
func play_anim(anim: String) -> void:
	if anim == "final":
		set_final_tell(true)
		set_state("telegraph", 1.5)
	elif inner != null and inner.has_method("play_anim"):
		inner.call("play_anim", anim)


func halo_strength() -> float:
	return _halo_mat.albedo_color.a if _halo_mat != null else 0.0


# --- Building -------------------------------------------------------------------------------------------------------

func _build() -> void:
	for n in [inner, _extras, _halo]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			(n as Node).queue_free()
	_streamers.clear()
	if alt:
		inner = ShadeVisual.new()
		inner.call("setup", {"scale": SHADE_SCALE, "boss": true})
	else:
		inner = WeaverVisual.new()
		inner.call("setup", {"scale": WEAVER_SCALE, "boss": true})
	inner.name = "Body"
	add_child(inner)
	_extras = Node3D.new()
	_extras.name = "Extras"
	add_child(_extras)
	if alt:
		_build_veils()
	else:
		_build_mantle()
	_halo_mat = HitFx.new_tint()
	_halo_mat.albedo_color = Color(HALO_ALT if alt else HALO_SILK, 0.0)
	_halo = Kit.sphere(1.0, _halo_mat, 10, 14)
	_halo.name = "CoilHalo"
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.set_meta("no_flash", true)
	add_child(_halo)
	var h := body_height()
	_halo.position = Vector3(0, h * (0.55 if alt else 0.5), 0)
	_halo.scale = Vector3.ONE * (h * (0.45 if alt else 1.1))
	inner.call("set_state", state if supports_state(state) else "idle", state_len)
	if inner.has_method("set_clinging"):
		inner.call("set_clinging", _clinging)


func _build_mantle() -> void:
	var s := WEAVER_SCALE
	var scar := Kit.torus(0.3, 0.36, Mat.toon(SCAR, {"rim": 0.2, "emission": SCAR_GLOW, "emission_energy": 0.35}))
	scar.name = "EmberScar"
	scar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_extras, scar, Vector3(0, (0.46 + 0.1) * s, 0.4 * s), Vector3(90, 0, 0), Vector3(s, s * 1.3, s * 0.6))
	var silk := Mat.transparent(MANTLE, false)
	for i in 4:
		var sx := (float(i) - 1.5) * 0.12 * s
		var strip := Kit.box(Vector3(0.07 * s, 0.012 * s, 0.9 * s), silk)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.name = "Streamer%d" % i
		Kit.add(_extras, strip, Vector3(sx, (0.46 + 0.02) * s, (0.72 + 0.45) * s), Vector3(-8.0 - 5.0 * float(i % 2), (float(i) - 1.5) * 7.0, 0))
		_streamers.append(strip)


func _build_veils() -> void:
	var s := SHADE_SCALE
	var veil := Mat.transparent(VEIL, true)
	for sx in [-1.0, 1.0]:
		var v := Kit.box(Vector3(0.22 * s, 1.1 * s, 0.01), veil)
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.name = "Veil"
		Kit.add(_extras, v, Vector3(float(sx) * 0.2 * s, 0.95 * s, 0.22 * s), Vector3(12.0, float(sx) * 14.0, 0))
		_streamers.append(v)
	var root := Mat.outlined(Mat.toon(ROOT, {"rim": 0.4}), 0.01)
	var circlet := Kit.torus(0.2, 0.24, root)
	circlet.name = "RootCirclet"
	circlet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_extras, circlet, Vector3(0, (0.22 + 1.55 + 0.34) * s, 0.02 * s), Vector3.ZERO, Vector3(s, s * 0.6, s))
	var bulb := Mat.glow(Color("d9f2c4"), 0.8)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var b := Kit.sphere(0.035 * s, bulb, 5, 6)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(_extras, b, Vector3(cos(a) * 0.22 * s, (0.22 + 1.55 + 0.36) * s, 0.02 * s + sin(a) * 0.22 * s))


func _process(delta: float) -> void:
	_t += delta
	for i in _streamers.size():
		var st := _streamers[i] as Node3D
		if st != null:
			st.rotation.x = deg_to_rad((12.0 if alt else -8.0) + sin(_t * (1.3 + 0.2 * float(i)) + float(i)) * 6.0)
	if _halo_mat == null:
		return
	var target := 0.0
	if final_tell:
		target = 0.34 if HitFx.reduce_flashing() else 0.24 + 0.14 * (0.5 + 0.5 * sin(_t * 18.0))
	var a := lerpf(_halo_mat.albedo_color.a, target, clampf(delta * 14.0, 0.0, 1.0))
	_halo_mat.albedo_color = Color(_halo_mat.albedo_color, a)
	_halo.visible = a > 0.01
