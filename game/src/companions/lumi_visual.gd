extends "res://src/companions/companion_visual.gd"
## LUMI - a small luminous fox-like woodland creature: cream-gold glowing fur, big ears with
## gold tips, a fluffy tail with a glowing tip and a soft warm OmniLight (~6.5 m). Floats a little
## above the ground and prances when moving, leaving a trail of golden motes. Dims when frightened
## or when it notices something in the dark (set_glow).

const FUR := Color("fff1c9")
const FLUFF := Color("fffaf0")
const FUR_GOLD := Color("fde2a2")
const GLOW := Color("ffd98a")
const TIPS := Color("f7c35c")
const INNER_EAR := Color("f2b86a")
const NOSE := Color("5a3f3a")
const LUMI_OUTLINE := Color(0.36, 0.24, 0.16)
const LIGHT_RANGE := 6.5
const LIGHT_ENERGY := 1.2

var head: Node3D
var ears: Array = []
var legs: Array = []
var tail_pivot: Node3D
var tail_segments: Array = []
var light: OmniLight3D
var halo: MeshInstance3D
var trail: CPUParticles3D
var _fur_mat: ShaderMaterial
var _fluff_mat: ShaderMaterial
var _gold_mat: ShaderMaterial
var _tip_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _glow_now := 1.0


func _build() -> void:
	emote_height = 0.95
	gait_speed_ref = 4.8
	outline_width = 0.01
	head_height = 0.36
	head_body_factor = 0.25
	var cfg: Dictionary = ItemDB.creature("lumi") if is_instance_valid(ItemDB) else {}
	var lcfg: Dictionary = cfg.get("light", {})
	# These materials are animated per instance (glow / dim), so the outline pass goes straight onto
	# them: Mat.outlined() would hand the meshes a cached *copy* that the glow code never touches.
	_fur_mat = Mat.toon_unique(FUR, {"emission": GLOW, "emission_energy": 0.35, "rim": 0.8, "noise": 0.04})
	_fluff_mat = Mat.toon_unique(FLUFF, {"emission": GLOW, "emission_energy": 0.3, "rim": 0.8, "noise": 0.03})
	var fur := _with_outline(_fur_mat, outline_width)
	var fluff := _with_outline(_fluff_mat, outline_width)
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tip_mat.albedo_color = TIPS
	_tip_mat.emission_enabled = true
	_tip_mat.emission = TIPS
	_tip_mat.emission_energy_multiplier = 1.6
	var tip := _with_outline(_tip_mat, outline_width * 0.8)
	_gold_mat = Mat.toon_unique(FUR_GOLD, {"emission": GLOW, "emission_energy": 0.35, "rim": 0.8, "noise": 0.05})
	var gold := _with_outline(_gold_mat, outline_width)
	# Torso (along Z, warmer gold on the back) and a big chest fluff.
	var torso := Kit.capsule(0.118, 0.31, gold)
	Kit.add(body, torso, Vector3(0, 0.19, -0.05), Vector3(90, 0, 0))
	var chest := Kit.blob(0.098, fluff, 4, 0.16, 1.0, 3)
	Kit.add(body, chest, Vector3(0, 0.2, 0.065), Vector3.ZERO, Vector3(1.0, 1.1, 0.85))
	# Short chibi legs (pivot at the hip so they can swing) with round paws.
	for p in [Vector3(-0.058, 0.13, 0.05), Vector3(0.058, 0.13, 0.05), Vector3(-0.062, 0.13, -0.14), Vector3(0.062, 0.13, -0.14)]:
		var lp := Node3D.new()
		body.add_child(lp)
		lp.position = p
		var leg := Kit.capsule(0.034, 0.1, fur)
		Kit.add(lp, leg, Vector3(0, -0.035, 0))
		var paw := Kit.sphere(0.034, fluff, 8, 10)
		Kit.add(lp, paw, Vector3(0, -0.078, 0.01), Vector3.ZERO, Vector3(1.0, 0.72, 1.2))
		legs.append(lp)
	# Head with snout, nose, big eyes, cheeks and big gold-tipped ears.
	head = Node3D.new()
	body.add_child(head)
	head.position = Vector3(0, 0.335, 0.1)
	var skull := Kit.sphere(0.145, fur, 16, 22)
	Kit.add(head, skull, Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.95, 0.98))
	var snout := Kit.sphere(0.062, fluff, 12, 16)
	Kit.add(head, snout, Vector3(0, -0.055, 0.112), Vector3.ZERO, Vector3(1.0, 0.7, 1.05))
	var nose := Kit.sphere(0.019, Mat.toon(NOSE, {"specular": 0.5, "noise": 0.0}), 8, 10)
	Kit.add(head, nose, Vector3(0, -0.035, 0.176), Vector3.ZERO, Vector3(1.2, 0.8, 0.9))
	make_eye(head, Vector3(-0.064, 0.014, 0.118), 0.046, -20.0)
	make_eye(head, Vector3(0.064, 0.014, 0.118), 0.046, 20.0)
	make_cheek(head, Vector3(-0.108, -0.045, 0.088), 0.027, -45.0)
	make_cheek(head, Vector3(0.108, -0.045, 0.088), 0.027, 45.0)
	for side in [-1.0, 1.0]:
		var ep := Node3D.new()
		head.add_child(ep)
		ep.position = Vector3(0.078 * side, 0.09, -0.02)
		var ear := Kit.cone(0.074, 0.22, fur, 14)
		Kit.add(ep, ear, Vector3(0, 0.11, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
		var inner := Kit.cone(0.046, 0.15, Mat.toon(INNER_EAR, {"emission": GLOW, "emission_energy": 0.25}), 10)
		Kit.add(ep, inner, Vector3(0, 0.08, 0.024), Vector3.ZERO, Vector3(1.0, 1.0, 0.3))
		var ear_tip := Kit.cone(0.036, 0.09, tip, 10)
		Kit.add(ep, ear_tip, Vector3(0, 0.175, 0), Vector3.ZERO, Vector3(1.03, 1.0, 0.64))
		ears.append(ep)
	# Big fluffy tail: overlapping puffs curling up into one soft volume, with a glowing tip.
	tail_pivot = Node3D.new()
	body.add_child(tail_pivot)
	tail_pivot.position = Vector3(0, 0.21, -0.19)
	var seg_data := [[Vector3(0, 0.0, -0.035), 0.056, 2, gold], [Vector3(0, 0.04, -0.095), 0.076, 6, gold],
		[Vector3(0, 0.1, -0.14), 0.09, 9, fur], [Vector3(0, 0.175, -0.155), 0.086, 3, fluff]]
	for sd in seg_data:
		var puff := Kit.blob(float(sd[1]), sd[3], int(sd[2]), 0.12, 1.0, 3)
		Kit.add(tail_pivot, puff, sd[0])
		tail_segments.append(puff)
	var tail_tip := Kit.blob(0.064, tip, 13, 0.14, 1.0, 3)
	Kit.add(tail_pivot, tail_tip, Vector3(0, 0.245, -0.14))
	# Soft aura (additive billboard), warm light and the mote trail.
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = Icons.icon("dot")
	_halo_mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.22)
	_halo_mat.disable_receive_shadows = true
	_halo_mat.proximity_fade_enabled = true     # no hard edge where the glow meets the ground
	_halo_mat.proximity_fade_distance = 0.4
	halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 0.95)
	halo.mesh = q
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(halo)
	halo.position = Vector3(0, 0.34, 0)
	light = OmniLight3D.new()
	light.name = "LumiLight"
	light.light_color = lcfg.get("color", GLOW)
	light.omni_range = float(lcfg.get("range", LIGHT_RANGE))
	light.light_energy = float(lcfg.get("energy", LIGHT_ENERGY))
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.light_specular = 0.2
	add_child(light)
	light.position = Vector3(0, 0.45, 0)
	trail = CPUParticles3D.new()
	trail.amount = 22
	trail.lifetime = 0.9
	trail.local_coords = false
	trail.mesh = Fx.quad(0.075)
	trail.material_override = Fx.particle_material(Icons.icon("dot"), true)
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.05
	trail.initial_velocity_max = 0.25
	trail.gravity = Vector3(0, 0.25, 0)
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.3
	trail.scale_amount_curve = Fx.pop_curve()
	trail.color = Color(1.0, 0.78, 0.38, 0.75)
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.07
	trail.emitting = false
	rig.add_child(trail)
	trail.position = Vector3(0, 0.45, -0.34)


## Adds the shared outline pass (same shader as Mat.outlined) directly to a per-instance material,
## so animating `base` is what the meshes show (and nothing piles up in Mat's static cache).
static func _with_outline(base: Material, width: float) -> Material:
	var o := ShaderMaterial.new()
	o.shader = Mat.OUTLINE
	o.set_shader_parameter("thickness", width)
	o.set_shader_parameter("outline_color", LUMI_OUTLINE)
	base.next_pass = o
	return base


## Lumi floats and prances: a gentle hover when still, light bounding arcs when moving.
func _gait(delta: float) -> void:
	var r := clampf(move_speed / gait_speed_ref, 0.0, 1.7)
	var hover := 0.13 + sin(_t * 2.1) * 0.03
	if r < 0.05:
		_phase = 0.0
		p_hop = hover
		p_tail = 0.2
		return
	_phase += delta * (6.0 + 5.0 * r)
	var s := sin(_phase)
	p_hop = hover + absf(s) * (0.06 + 0.07 * minf(r, 1.2))
	p_lean += 0.12 * minf(r, 1.0) - cos(_phase) * 0.06 * minf(r, 1.0)
	p_step = s
	p_step_lift = minf(r, 1.0)
	p_tail = 0.4 + 0.5 * minf(r, 1.0)


func _mood_pose(delta: float) -> void:
	super(delta)
	if mood == "scared":
		p_hop = minf(p_hop, 0.06)
	elif mood == "sleep":
		p_hop = 0.02
	elif mood == "alert":
		p_hop = 0.12


func _action_pose(a: String, k: float) -> void:
	super(a, k)
	if a == "glow_pulse":
		p_tail = 1.0


func _apply_pose(delta: float) -> void:
	_apply_common(delta)
	# The body pivots a little for looking; the head does the rest.
	head.rotation = Vector3(-p_head_pitch * 0.75, p_head_yaw * 0.75 + p_shake, p_roll * -0.4)
	# Ears: perk up on alert, flatten back when scared, flick now and then.
	var flick := maxf(0.0, sin(_t * 0.9) - 0.96) * 12.0
	for i in ears.size():
		var ep: Node3D = ears[i]
		var side := -1.0 if i == 0 else 1.0
		var back := 0.0
		if mood == "scared":
			back = 0.9
		elif mood == "sleep":
			back = 0.5
		var perk := 0.25 if (mood == "alert" or get_action() == "notice") else 0.0
		ep.rotation = Vector3(-0.12 - back + perk + flick * 0.15 * float(i == 0), 0.0, -side * (0.32 + back * 0.35 - perk * 0.2))
	# Legs: dangle while hovering, cycle when prancing.
	for i in legs.size():
		var lp: Node3D = legs[i]
		var front := i < 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var swing := p_step * 0.7 * p_step_lift * (1.0 if front else -1.0) * side
		var dangle := sin(_t * 2.1 + float(i)) * 0.08
		lp.rotation = Vector3(swing + dangle + (0.25 if not front else -0.1) * p_step_lift, 0.0, 0.0)
	# Tail: streams back when moving, wags when happy, tucks when scared.
	var wag := sin(_t * (3.0 + 6.0 * p_tail)) * (0.12 + 0.35 * p_tail)
	# Scared: the tail droops back and low (a positive tilt would swing it forward over the back,
	# poking the gold tip up behind the head).
	var tuck := -0.75 if mood == "scared" else 0.0
	# A little sideways curl so the fluffy tail reads from the front too (not like a hair bun).
	tail_pivot.rotation = Vector3(-0.35 + p_tail * 0.35 + tuck, 0.55 + wag, -0.25)
	# Glow: smooth toward the requested level (+ action boost), drive light, fur, tips, halo, trail.
	var target := clampf(glow_level + p_glow_boost * 0.6, 0.0, 2.0)
	_glow_now = lerpf(_glow_now, target, 1.0 - exp(-4.0 * delta))
	var flicker := 1.0 + sin(_t * 3.1) * 0.03 + sin(_t * 7.3) * 0.015
	light.light_energy = LIGHT_ENERGY * _glow_now * flicker
	light.visible = _glow_now > 0.02
	_fur_mat.set_shader_parameter("emission_energy", 0.08 + 0.3 * _glow_now)
	_fluff_mat.set_shader_parameter("emission_energy", 0.06 + 0.28 * _glow_now)
	_gold_mat.set_shader_parameter("emission_energy", 0.08 + 0.3 * _glow_now)
	_tip_mat.emission_energy_multiplier = 0.4 + 1.3 * _glow_now
	_halo_mat.albedo_color.a = 0.24 * clampf(_glow_now, 0.0, 1.5)
	halo.scale = Vector3.ONE * (0.85 + 0.15 * _glow_now + sin(_t * 2.0) * 0.03)
	trail.emitting = move_speed > 0.6 and _glow_now > 0.4


func _on_action_fire(a: String) -> void:
	super(a)
	if a == "glow_pulse" or a == "lumi_glow_spin":
		Fx.sparkles(_fx_parent(), global_position + Vector3.UP * 0.4, 0.35, 10, Color(1.0, 0.9, 0.55))
	elif a == "light_bolt":
		Fx.sparkles(_fx_parent(), global_position + Vector3.UP * 0.45 + global_basis.z * 0.2, 0.12, 5, Color(1.0, 0.92, 0.6))


func _preview_extra(a: String) -> void:
	super(a)
	if a == "notice":
		set_glow(0.3)
