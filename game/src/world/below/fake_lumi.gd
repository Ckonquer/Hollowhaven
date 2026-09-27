extends Node3D
## THE IMITATION: something wearing Lumi's shape. Fair, readable tells (see GAME_SPEC):
##  * its glow is cold blue-white (real Lumi is warm gold)
##  * it casts NO light on the ground or the water (there is no light node at all)
##  * it moves in stiff, snapping jerks and never blinks
##  * its chime is reversed (fake_lumi_chime)
## fold() makes it collapse into the dark with a hiss. It never harms anyone.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const BODY := Color("dfe7f3")
const EARS := Color("b3c6e4")
const COLD_GLOW := Color("cfe6ff")

signal folded

var hover: float = 0.55
var chime_interval: Vector2 = Vector2(4.5, 7.0)
var active: bool = true
var folding: bool = false

var _rig: Node3D
var _head: Node3D
var _next_jerk: float = 0.4
var _next_chime: float = 1.2
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _captioned: bool = false
var _tween: Tween


const LUMI_VISUAL := "res://src/companions/lumi_visual.gd"

var facing_plus_z: bool = false      # the real Lumi visual faces +Z, the fallback body faces -Z
var _visual: Node3D = null


func _ready() -> void:
	_rng.seed = 6660
	_rig = Node3D.new()
	add_child(_rig)
	_rig.position.y = hover
	if not _build_from_real_lumi():
		_build_fallback()


## Wear Lumi's exact shape (the imitation is convincing at a distance), but frozen (never blinks,
## no gait, no motes), lightless and recoloured cold blue-white.
func _build_from_real_lumi() -> bool:
	if not ResourceLoader.exists(LUMI_VISUAL):
		return false
	var s: Script = load(LUMI_VISUAL)
	if s == null or not s.can_instantiate():
		return false
	var v: Node3D = s.new()
	_rig.add_child(v)
	v.scale = Vector3.ONE * 1.15
	v.position.y = -hover + 0.14
	v.process_mode = Node.PROCESS_MODE_DISABLED
	# Strip everything that emits light or motes (detached at once, then freed).
	for cls in ["Light3D", "GPUParticles3D", "CPUParticles3D"]:
		for n in v.find_children("*", cls, true, false):
			n.get_parent().remove_child(n)
			n.queue_free()
	for gi in v.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		var m := g.material_override
		if m is StandardMaterial3D and (m as StandardMaterial3D).billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			g.visible = false        # the warm halo: the imitation has none
			continue
		if m != null:
			g.material_override = _cold(m)
	# Dead eyes: no sparkle highlights (the real Lumi's eyes always shine).
	var eyes: Variant = v.get("eye_nodes")
	if eyes is Array:
		for e in eyes:
			if e is Node3D:
				var kids: Array = (e as Node3D).get_children()
				for i in kids.size():
					if i > 0 and kids[i] is Node3D:
						(kids[i] as Node3D).visible = false
				(e as Node3D).scale = Vector3(1.12, 1.12, 1.0)
	var h: Variant = v.get("head")
	if h is Node3D:
		_head = h
	else:
		_head = Node3D.new()
		_rig.add_child(_head)
	_visual = v
	facing_plus_z = true
	return true


static func _cold_color(c: Color) -> Color:
	var l := c.get_luminance()
	return Color(l * 0.82, l * 0.9, minf(l * 1.08 + 0.04, 1.0), c.a)


func _cold(m: Material) -> Material:
	var out: Material = m.duplicate()
	if out is ShaderMaterial:
		var sm := out as ShaderMaterial
		var alb: Variant = sm.get_shader_parameter("albedo")
		if alb is Color:
			sm.set_shader_parameter("albedo", _cold_color(alb))
		var em: Variant = sm.get_shader_parameter("emission_color")
		if em is Color and (em as Color).get_luminance() > 0.01:
			sm.set_shader_parameter("emission_color", COLD_GLOW)
	elif out is StandardMaterial3D:
		var st := out as StandardMaterial3D
		st.albedo_color = _cold_color(st.albedo_color)
		if st.emission_enabled:
			st.emission = COLD_GLOW
	if m.next_pass != null:
		out.next_pass = m.next_pass
	return out


func _build_fallback() -> void:
	var body_mat := Mat.outlined(Mat.toon(BODY, {"rim": 1.0, "emission": BODY, "emission_energy": 0.35}), 0.018, Color(0.1, 0.1, 0.16))
	var ear_mat := Mat.outlined(Mat.toon(EARS, {"rim": 0.9, "emission": EARS, "emission_energy": 0.3}), 0.015, Color(0.1, 0.1, 0.16))
	Kit.add(_rig, Kit.sphere(0.27, body_mat, 12, 16), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.92, 0.95))
	Kit.add(_rig, Kit.sphere(0.16, Mat.toon(Color("f4f8ff"), {"emission": Color("f4f8ff"), "emission_energy": 0.4}), 8, 10), Vector3(0, -0.06, -0.17), Vector3.ZERO, Vector3(1.0, 0.8, 0.5))
	_head = Node3D.new()
	_rig.add_child(_head)
	for sx in [-1.0, 1.0]:
		var ear := Kit.add(_head, Kit.cone(0.1, 0.34, ear_mat, 8), Vector3(sx * 0.15, 0.3, 0.02), Vector3(0, 0, -sx * 24.0))
		ear.scale = Vector3(1.0, 1.0, 0.55)
		# Wide, fixed, unblinking eyes
		Kit.add(_head, Kit.sphere(0.07, Mat.toon(Color(0.05, 0.05, 0.08), {"rim": 0.0}), 8, 10), Vector3(sx * 0.1, 0.05, -0.23), Vector3.ZERO, Vector3(0.9, 1.25, 0.6))
		Kit.add(_head, Kit.sphere(0.02, Mat.glow(Color("eef6ff"), 1.5), 4, 6), Vector3(sx * 0.1 + 0.02, 0.09, -0.27))
	# Antenna with the cold glow orb (Lumi's is warm gold)
	Kit.add(_head, Kit.cylinder(0.01, 0.014, 0.22, ear_mat, 6), Vector3(0, 0.36, 0.0), Vector3(-12, 0, 0))
	Kit.add(_head, Kit.sphere(0.07, Mat.glow(COLD_GLOW, 3.2), 8, 10), Vector3(0, 0.49, 0.03))
	Kit.add(_head, Kit.sphere(0.12, Mat.transparent(Color(0.8, 0.9, 1.0, 0.18), true), 8, 10), Vector3(0, 0.49, 0.03))
	Kit.add(_rig, Kit.torus(0.03, 0.09, body_mat), Vector3(0, -0.1, 0.27), Vector3(70, 0, 0))
	# A cold point of light hovering above it, readable across the water (it lights nothing).
	Kit.add(_rig, Kit.sphere(0.05, Mat.glow(COLD_GLOW, 4.0), 6, 8), Vector3(0, 0.75, 0))


func _process(delta: float) -> void:
	if not active or folding:
		return
	_t += delta
	_next_jerk -= delta
	if _next_jerk <= 0.0:
		_next_jerk = _rng.randf_range(0.35, 0.95)
		# Snap (no easing) to a slightly different pose.
		_rig.position = Vector3(_rng.randf_range(-0.05, 0.05), hover + _rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.04, 0.04))
		if _rng.randf() < 0.18:
			_head.rotation = Vector3(0, 0, deg_to_rad(_rng.randf_range(55.0, 80.0)) * (1.0 if _rng.randf() < 0.5 else -1.0))
		else:
			_head.rotation = Vector3(deg_to_rad(_rng.randf_range(-8, 8)), deg_to_rad(_rng.randf_range(-15, 15)), deg_to_rad(_rng.randf_range(-12, 12)))
	_next_chime -= delta
	if _next_chime <= 0.0:
		_next_chime = _rng.randf_range(chime_interval.x, chime_interval.y)
		chime()


func chime() -> void:
	Audio.play_3d("fake_lumi_chime", global_position + Vector3(0, hover, 0), -3.0, 0.0, 40.0)
	if not _captioned:
		_captioned = true
		Events.caption.emit("[a familiar chime... played backwards]")


## Turn to face a point (snaps, like everything else it does).
func stare_at(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		rotation.y = atan2(d.x, d.z) if facing_plus_z else atan2(-d.x, -d.z)


## Collapse into the darkness with a hiss. hiss_db is intensity-scaled by the caller.
func fold(hiss_db: float, flash: bool) -> void:
	if folding:
		return
	folding = true
	Audio.play_3d("gloomling_hiss", global_position + Vector3(0, hover, 0), hiss_db, 0.0, 30.0)
	Audio.play_sfx("stinger_soft", hiss_db - 2.0, 0.0)
	Events.caption.emit("[a hiss, and the light folds away]")
	if flash:
		Events.screen_flash.emit(Color(0.75, 0.88, 1.0, 0.12), 0.12)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# one last stiff jerk toward the wall, then it folds flat and thin into nothing
	_tween.tween_property(_rig, "scale", Vector3(1.35, 0.35, 1.35), 0.12)
	_tween.tween_property(_rig, "scale", Vector3(0.04, 1.8, 0.04), 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_tween.tween_property(_rig, "scale", Vector3(0.01, 0.01, 0.01), 0.12)
	_tween.tween_callback(_finish_fold)


func _finish_fold() -> void:
	active = false
	visible = false
	folded.emit()
	queue_free()


## Quietly gone (the player walked away without approaching).
func vanish() -> void:
	active = false
	queue_free()
