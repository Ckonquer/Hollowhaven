extends Node3D
## One of the Choir's three forms in Phase A "False welcome" (MP §13.3), the same rule the Bell Throat practice
## reveal teaches. Every form is a floating cracked bell with a wooden mask and harvest ribbons beside a carved
## floor plate (the "marked nearby surface", a step behind it toward the centre - see PLATE_OFFSET). ONLY the
## genuine form:
##   1. lights its plate - a real OmniLight3D and a lit glow disc, faint all the time (consistent) and bright while
##      a lantern burns on an anchor (revealed); a false form glows warmly above but its plate stays dark stone;
##   2. moves right - a slow, living sway with ribbons that trail behind; false forms tick stiffly in lockstep
##      like a metronome, ribbons rigid;
##   3. (Settings high_visibility_cues) gets a bold outlined ring round its plate while revealed - a shape, never
##      colour alone.
## Picking: interact ("Point out this form") or strike it while an anchor's light is up. The form never takes
## damage: it is in group "enemy" only so Krystal's blows reach it (can_be_hit_by -> false -> on_hit_blocked ->
## the pick); companions never target it (invulnerable, can_be_hit_by false), nothing counts it as a threat.
##   form.setup({"index": 0, "picker": Callable(boss, "pick_form"), "text_func": Callable(boss, "form_prompt")})

const Art := preload("res://src/enemies/choir/choir_art.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")
const Health := preload("res://src/combat/health.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BODY_Y := 1.45
const PLATE_R := 0.72
## The plate sits this far from the form on the side AWAY from its facing (toward the empty centre). The form faces
## its lantern anchor; with the plate on the anchor side (+1.05, radius 5.45 in the vault) the anchor's carved ring,
## its raised glow ring and its bold high-visibility ring (radius 1.4 round the anchor at 7 m) all crossed EVERY
## plate - a bold ring on false plates too, and the raised anchor's light washed the nearest (maybe false) plate
## almost as brightly as the genuine plate light. On the centre side (radius 3.35) the plate + its own bold ring
## (outer edge 4.38) stay > 1 m clear of all of them (test_boss_choir_reveal).
const PLATE_OFFSET := -1.05
const FAINT_ENERGY := 0.5
const BRIGHT_ENERGY := 1.9
const TICK_PERIOD := 0.5            # false forms' stiff metronome

var index: int = 0
var genuine: bool = false
var revealed: bool = false
var hv: bool = false
var pickable: bool = false
var folded: bool = false
var health: Node
var hit_radius: float = 0.6
var hit_color: Color = Color(1.0, 0.9, 0.7)
var picker: Callable
var text_func: Callable
var picks_blocked: int = 0

var _body: Node3D
var _ribbons: Array = []
var _plate_glow: MeshInstance3D
var _plate_light: OmniLight3D
var _hv: MeshInstance3D
var _area: Area3D
var _t: float = 0.0
var _drift_from := Vector3.ZERO
var _drift_to := Vector3.ZERO
var _drift_t: float = 0.0
var _drift_len: float = 0.0
var _fold_tw: Tween = null


func setup(p: Dictionary) -> void:
	index = int(p.get("index", index))
	if p.get("picker") is Callable:
		picker = p["picker"]
	if p.get("text_func") is Callable:
		text_func = p["text_func"]


func _ready() -> void:
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0
	health.invulnerable = true
	add_child(health)
	_build()
	_area = Area3D.new()
	_area.name = "InteractArea"
	_area.collision_layer = 0
	_area.collision_mask = 0
	_area.monitoring = false
	_area.monitorable = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.5, 2.6, 1.5)
	cs.shape = sh
	cs.position = Vector3(0, 1.3, 0)
	_area.add_child(cs)
	add_child(_area)
	set_pickable(false)
	_apply()
	set_process(false)          # the boss ticks its forms (one deterministic clock; tests drive it)


func _build() -> void:
	# the carved floor plate (the marked surface), a step behind the form (toward the empty centre)
	var plate := Node3D.new()
	plate.name = "Plate"
	add_child(plate)
	plate.position = Vector3(0, 0.0, PLATE_OFFSET)
	Kit.add(plate, Kit.cylinder(PLATE_R, PLATE_R + 0.04, 0.05, Mat.outlined(Mat.toon(Color("5a4e46"), {"noise": 0.15}), 0.012), 20), Vector3(0, 0.025, 0))
	Kit.add(plate, Kit.torus(PLATE_R - 0.16, PLATE_R - 0.08, Mat.toon(Color("3e342e"))), Vector3(0, 0.055, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	_plate_glow = Kit.cylinder(PLATE_R - 0.06, PLATE_R - 0.06, 0.02, Mat.glow(Palette.LANTERN_GLOW, 0.5), 20)
	Kit.add(plate, _plate_glow, Vector3(0, 0.065, 0))
	_plate_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plate_light = OmniLight3D.new()
	_plate_light.name = "PlateLight"
	_plate_light.light_color = Palette.LANTERN_GLOW
	_plate_light.omni_range = 2.4
	_plate_light.light_energy = FAINT_ENERGY
	_plate_light.shadow_enabled = false
	plate.add_child(_plate_light)
	_plate_light.position = Vector3(0, 0.9, 0)
	_hv = Art.bold_ring(plate, PLATE_R + 0.22, 0.07)
	# the floating form
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_body.position = Vector3(0, BODY_Y, 0)
	var b := Art.bell(_body, Vector3(0, 0.25, 0), 1.35)
	b.name = "FormBell"
	Art.mask(_body, Vector3(0, 0.62, 0.12), 0.0, 0.95)
	Art.mote(_body, Vector3(0, -0.1, 0), 0.09, 1.3)          # the borrowed warm glow (lights nothing)
	for k in 3:
		var c: Color = Art.RIBBONS[(index * 2 + k) % Art.RIBBONS.size()]
		_ribbons.append(Art.ribbon(_body, Vector3(-0.22 + 0.22 * float(k), -0.15, 0.26), 0.85, c))


# --- State ---------------------------------------------------------------------------------------------------

func set_genuine(on: bool) -> void:
	genuine = on
	_apply()


func set_revealed(on: bool) -> void:
	if revealed == on:
		return
	revealed = on
	_apply()


func set_hv(on: bool) -> void:
	hv = on
	_apply()


## Joins / leaves the pickable groups (only while the Choir waits for a pick).
func set_pickable(on: bool) -> void:
	pickable = on and not folded
	if pickable:
		if not is_in_group("enemy"):
			add_to_group("enemy")
		if not is_in_group("interactable"):
			add_to_group("interactable")
	else:
		if is_in_group("enemy"):
			remove_from_group("enemy")
		if is_in_group("interactable"):
			remove_from_group("interactable")
	if _area != null:
		_area.collision_layer = 16 if pickable else 0


## True when this form's plate is really lit (the genuine form only) - what tests and the practice rule check.
func plate_lit() -> bool:
	return genuine and not folded and _plate_light != null and _plate_light.visible


func plate_light_energy() -> float:
	return _plate_light.light_energy if plate_lit() else 0.0


func hv_marker_visible() -> bool:
	return _hv != null and _hv.visible and visible


## "living" (genuine: slow sway, trailing ribbons) or "stiff" (false: lockstep metronome).
func motion_kind() -> String:
	return "living" if genuine else "stiff"


func _apply() -> void:
	if _plate_light == null:
		return
	_plate_light.visible = genuine and not folded
	_plate_light.light_energy = BRIGHT_ENERGY if revealed else FAINT_ENERGY
	_plate_glow.visible = genuine and not folded
	_plate_glow.material_override = Mat.glow(Palette.LANTERN_GLOW, 1.9 if revealed else 0.5)
	_hv.visible = genuine and revealed and hv and not folded


func show_form(at: Vector3, facing: Vector3) -> void:
	if _fold_tw != null and _fold_tw.is_valid():
		_fold_tw.kill()
	_fold_tw = null
	folded = false
	visible = true
	_body.scale = Vector3.ONE
	_body.visible = true
	global_position = at
	_face(facing)
	_drift_len = 0.0
	_apply()


## Drifts from `from` to `to` over `length` s (the gather), facing `facing` (flat).
func drift(from: Vector3, to: Vector3, length: float, facing: Vector3) -> void:
	show_form(from, facing)
	_drift_from = from
	_drift_to = to
	_drift_t = 0.0
	_drift_len = maxf(length, 0.01)


func fold_away() -> void:
	folded = true
	set_pickable(false)
	_apply()
	if is_inside_tree():
		if _fold_tw != null and _fold_tw.is_valid():
			_fold_tw.kill()
		_fold_tw = create_tween()
		_fold_tw.tween_property(_body, "scale", Vector3.ONE * 0.05, 0.45).set_ease(Tween.EASE_IN)
		_fold_tw.tween_callback(_hide_body)
	else:
		_hide_body()


func _hide_body() -> void:
	if folded:
		visible = false


## A wrong pick: the false form bursts into drifting ribbons (harmless).
func burst() -> void:
	if is_inside_tree():
		HitFx.burst(_body.global_position, Art.RIBBONS[index % Art.RIBBONS.size()], 14, 2.4, 1.1, -2.0, 0.9, 120.0)
	fold_away()


func hide_form() -> void:
	folded = true
	set_pickable(false)
	visible = false
	_apply()


func _face(dir: Vector3) -> void:
	var f := Vector3(dir.x, 0.0, dir.z)
	if f.length_squared() > 0.0001:
		rotation = Vector3(0.0, atan2(f.x, f.z), 0.0)


## tests/preview hook (--preview=res://src/enemies/choir/choir_form.gd --preview-anim=genuine|revealed|hv|false):
## shows one form standing at the origin, animated by its own process.
func play_anim(anim: String) -> void:
	show_form(Vector3.ZERO, Vector3.BACK)
	set_genuine(anim != "false")
	set_revealed(anim == "revealed" or anim == "hv")
	set_hv(anim == "hv")
	set_process(true)


func _process(delta: float) -> void:
	tick(delta)


## Driven by the boss's tick (never its own _process, except in the preview above).
func tick(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _drift_len > 0.0:
		_drift_t = minf(_drift_t + delta, _drift_len)
		var k := _drift_t / _drift_len
		var e := k * k * (3.0 - 2.0 * k)
		global_position = _drift_from.lerp(_drift_to, e)
		if _drift_t >= _drift_len:
			_drift_len = 0.0
	if folded:
		return
	if genuine:
		# living: two slow frequencies, a gentle bob, ribbons trailing a beat behind
		_body.rotation.z = sin(_t * 1.6) * 0.09
		_body.rotation.y = sin(_t * 0.9) * 0.14
		_body.position.y = BODY_Y + sin(_t * 1.1) * 0.07
		for i in _ribbons.size():
			(_ribbons[i] as Node3D).rotation.z = sin(_t * 1.6 - 0.9 - float(i) * 0.35) * 0.22
	else:
		# stiff: the whole form snaps between two tilts in lockstep, ribbons rigid
		var tick_on := int(floorf(_t / TICK_PERIOD)) % 2 == 0
		_body.rotation.z = 0.07 if tick_on else -0.07
		_body.rotation.y = 0.0
		_body.position.y = BODY_Y
		for r in _ribbons:
			(r as Node3D).rotation.z = 0.0


# --- Combat / interaction contracts ------------------------------------------------------------------------

func is_threatening() -> bool:
	return false


func can_be_hit_by(_source: Node) -> bool:
	return false


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func get_aim_point() -> Vector3:
	return _body.global_position if _body != null and is_inside_tree() else global_position + Vector3.UP * BODY_Y


## Krystal's blow (or wand spark) on this form = pointing it out. Companions' blows never land here.
func on_hit_blocked(attacker: Node, _dir: Vector3) -> void:
	if folded or not pickable:
		return
	if is_inside_tree():
		HitFx.spark(get_aim_point())
	var is_krystal := attacker != null and is_instance_valid(attacker) and attacker.is_in_group("player") and not attacker.is_in_group("companion")
	if not is_krystal:
		return
	if picker.is_valid():
		picker.call(index, attacker)


func get_interaction(_player: Node = null) -> Dictionary:
	if not pickable:
		return {}
	if text_func.is_valid():
		var d: Variant = text_func.call(index)
		if d is Dictionary:
			return d
	return {"text": "Point out this form", "enabled": true}


func interact(player: Node = null) -> void:
	if not pickable:
		return
	if picker.is_valid():
		picker.call(index, player)
