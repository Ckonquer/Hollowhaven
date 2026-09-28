extends Node3D
## A shaking egg sac at the arena edge (arachnophobia: a pale seed pod). Placed by the hazard field
## late in phase 2, well away from Krystal. It shakes harder over a GENEROUS warning (a ring on the
## floor shows where the minion will stand), then asks the field to release one small minion. It never
## releases while Krystal stands right on top of it (the field checks the distance) - and she can pop
## it early with any attack (health 15, `can_be_hit_by` = Krystal only): no minion then.
##   var s = EggSac.new(); s.setup({"pos": Vector3, "warn": 3.0, "alt": false}); field.add_child(s)

const Art := preload("res://src/enemies/boss_hazards/hazard_art.gd")
const Health := preload("res://src/combat/health.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const FADE := 0.35
const HP := 15.0

var kind := "sac"
var pos := Vector3.ZERO
var warn: float = 3.0
var alt := false
var t: float = 0.0
var released := false
var popped := false
var fading: float = -1.0
var health: Node
var hit_radius: float = 0.55
var hit_color := Art.SAC

var high_vis := false             # Settings "high_visibility_cues" (the field toggles it live)

var _body: Node3D
var _ring: MeshInstance3D
var _bold: MeshInstance3D         # bold outer ring while it is still pending (high_vis)
var _mats_built := false


func setup(p: Dictionary) -> void:
	var v: Variant = p.get("pos")
	if v is Vector3:
		pos = v
	warn = maxf(float(p.get("warn", warn)), 0.5)
	alt = bool(p.get("alt", alt))
	hit_color = Art.POD if alt else Art.SAC


func _ready() -> void:
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, pos)
	add_to_group("enemy")
	set_meta("boss_hazard", true)     # auto-aim may rank it below real enemies (integrator note)
	health = Health.new()
	health.name = "Health"
	health.max_hp = HP
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_popped)
	high_vis = Art.high_vis()
	_build()


# --- Combat contract ------------------------------------------------------------------------------------

func can_be_hit_by(source: Node) -> bool:
	if released or popped or fading >= 0.0:
		return false
	return source == null or (is_instance_valid(source) and source.is_in_group("player"))


func is_threatening() -> bool:
	return false


func get_aim_point() -> Vector3:
	return pos + Vector3.UP * 0.5


func hit_flash(_d: float = 0.1) -> void:
	pass


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func _on_damaged(_amount: float, source: Node, _dir: Vector3) -> void:
	if source != null and is_instance_valid(source) and not source.is_in_group("player") and health.hp > 0.0:
		health.set_hp(health.max_hp)


func _on_popped() -> void:
	pop()


# --- Life ------------------------------------------------------------------------------------------------

func is_pending() -> bool:
	return not released and not popped and fading < 0.0


## Ready to release its minion (the field adds the distance / overlap checks).
func is_due() -> bool:
	return is_pending() and t >= warn


func is_done() -> bool:
	return fading >= FADE


func tick(delta: float) -> void:
	t += delta
	if fading >= 0.0:
		fading += delta
		if _body != null:
			_body.scale = Vector3.ONE * maxf(1.0 - fading / FADE, 0.05)
		if _ring != null:
			_ring.transparency = clampf(fading / FADE, 0.0, 1.0)
		return
	var k := clampf(t / warn, 0.0, 1.0)
	if _body != null:
		var amp := 0.04 + 0.16 * k * k
		_body.rotation = Vector3(sin(t * (9.0 + 10.0 * k)) * amp, 0.0, cos(t * (11.0 + 9.0 * k)) * amp)
		_body.scale = Vector3.ONE * (1.0 + 0.08 * k * (0.5 + 0.5 * sin(t * 6.0)))
	if _ring != null:
		_ring.transparency = 1.0 - Art.pulse_alpha(t, 0.3, 0.75, 7.0 + 6.0 * k) * lerpf(0.5, 1.0, k)


## The minion came out (the field spawned it): the empty husk fades.
func mark_released() -> void:
	if not is_pending():
		return
	released = true
	remove_from_group("enemy")
	HitFx.burst(pos + Vector3.UP * 0.5, hit_color, 14, 2.6, 1.0, -6.0, 0.6)
	Audio.play_3d("dir_root_creak" if alt else "dir_scratch", pos, -3.0, 0.1, 30.0)
	fading = 0.0
	_apply_high_vis()


## Popped by Krystal (or withered / cleared): no minion.
func pop() -> void:
	if not is_pending():
		return
	popped = true
	remove_from_group("enemy")
	HitFx.burst(pos + Vector3.UP * 0.5, hit_color, 10, 2.0, 0.9, -8.0, 0.5)
	Audio.play_3d("hit_soft", pos, -4.0, 0.1, 25.0)
	fading = 0.0
	_apply_high_vis()


func clear() -> void:
	if fading >= 0.0:
		return
	if is_pending():
		popped = true
		remove_from_group("enemy")
	fading = 0.0
	_apply_high_vis()


## Settings "high_visibility_cues": a bold outer ring marks a sac that can still hatch.
func set_high_vis(on: bool) -> void:
	high_vis = on
	_apply_high_vis()


func bold_visible() -> bool:
	return _bold != null and is_instance_valid(_bold) and _bold.visible


func _apply_high_vis() -> void:
	if _bold != null and is_instance_valid(_bold):
		_bold.visible = high_vis and is_pending()


# --- Visuals ---------------------------------------------------------------------------------------------

func set_alt(on: bool) -> void:
	if on == alt:
		return
	alt = on
	hit_color = Art.POD if alt else Art.SAC
	for c in get_children():
		if c != health:
			c.queue_free()
	_body = null
	_ring = null
	_bold = null
	_build()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var m := Art.sac_mat(alt)
	var vein := Art.vein_mat(alt)
	if alt:
		# Pale seed pod: an upright teardrop with a green seam, a little stalk and two leaf curls.
		var pod := MeshInstance3D.new()
		pod.mesh = Kit.blob_mesh(0.34, 41, 0.08, 1.45, 2)
		pod.material_override = m
		_body.add_child(pod)
		pod.position = Vector3(0, 0.5, 0)
		var seam := Kit.cylinder(0.018, 0.018, 0.8, vein, 6)
		Kit.add(_body, seam, Vector3(0, 0.5, -0.3), Vector3(-6, 0, 0))
		var stalk := Kit.cylinder(0.04, 0.06, 0.25, vein, 6)
		Kit.add(_body, stalk, Vector3(0, 0.12, 0))
	else:
		# Egg sac: a lumpy pale ball in a loose wrap of silk, faint violet veins.
		var sac := MeshInstance3D.new()
		sac.mesh = Kit.blob_mesh(0.38, 29, 0.14, 0.9, 2)
		sac.material_override = m
		_body.add_child(sac)
		sac.position = Vector3(0, 0.4, 0)
		for i in 3:
			var v := Kit.torus(0.36, 0.385, vein)
			Kit.add(_body, v, Vector3(0, 0.4, 0), Vector3(20.0 + 50.0 * float(i), 60.0 * float(i), 0), Vector3(1, 1, 1))
	_ring = Kit.torus(0.62, 0.72, Art.warn_mat(alt))
	add_child(_ring)
	_ring.position = Vector3(0, 0.03, 0)
	_ring.scale = Vector3(1, 0.2, 1)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bold = Kit.torus(0.82, 0.94, Art.bold_mat())
	add_child(_bold)
	_bold.position = Vector3(0, 0.04, 0)
	_bold.scale = Vector3(1, 0.2, 1)
	_bold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_high_vis()
