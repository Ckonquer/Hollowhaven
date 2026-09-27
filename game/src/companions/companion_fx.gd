extends RefCounted
## Small one-shot effects for the companions: poofs, floating hearts, sparkles, stone chips and
## music notes. Every effect frees itself. Materials and meshes are cached and shared.
##   const Fx := preload("res://src/companions/companion_fx.gd")
##   Fx.poof(get_parent(), global_position)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Icons := preload("res://src/companions/emote_icons.gd")

static var _cache: Dictionary = {}


static func quad(size: float) -> QuadMesh:
	var key := "quad|%.3f" % size
	if not _cache.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		_cache[key] = q
	return _cache[key]


static func _sphere(r: float) -> SphereMesh:
	var key := "sph|%.3f" % r
	if not _cache.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 10
		s.rings = 6
		_cache[key] = s
	return _cache[key]


static func _box(s: float) -> BoxMesh:
	var key := "box|%.3f" % s
	if not _cache.has(key):
		var b := BoxMesh.new()
		b.size = Vector3(s, s * 0.8, s * 0.9)
		_cache[key] = b
	return _cache[key]


## Billboard particle material with a texture; vertex colour drives tint and fade.
static func particle_material(tex: Texture2D, additive: bool = false) -> StandardMaterial3D:
	var key := "pm|%d|%s" % [tex.get_instance_id(), additive]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	_cache[key] = m
	return m


static func _fade_ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	g.add_point(0.7, c)
	return g


static func pop_curve() -> Curve:
	if _cache.has("pop_curve"):
		return _cache["pop_curve"]
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.2))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(0.7, 0.85))
	c.add_point(Vector2(1.0, 0.0))
	_cache["pop_curve"] = c
	return c


static func _auto_free(node: Node, seconds: float) -> void:
	if not node.is_inside_tree():
		node.queue_free()
		return
	var tw := node.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(node.queue_free)


static func _valid_parent(parent: Node) -> bool:
	return parent != null and is_instance_valid(parent) and parent.is_inside_tree()


## Soft cloud poof (teleports, befriending, boulder dust).
static func poof(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.97, 0.92), amount: int = 14, size: float = 1.0) -> void:
	if not _valid_parent(parent):
		return
	var p := CPUParticles3D.new()
	p.emitting = false          # emitting defaults to true: never burst at the origin before placement
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.75
	p.explosiveness = 0.92
	p.mesh = _sphere(0.11 * size)
	p.material_override = Mat.toon(color, {"rim": 0.6, "noise": 0.0})
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.9 * size
	p.initial_velocity_max = 2.2 * size
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.scale_amount_curve = pop_curve()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25 * size
	parent.add_child(p)
	p.global_position = pos + Vector3.UP * 0.25
	p.emitting = true
	_auto_free(p, 1.4)


## A few hearts that float up and fade (happy / pet / befriend).
static func hearts(parent: Node, pos: Vector3, count: int = 3) -> void:
	if not _valid_parent(parent):
		return
	var p := CPUParticles3D.new()
	p.emitting = false          # emitting defaults to true: never burst at the origin before placement
	p.one_shot = true
	p.amount = count
	p.lifetime = 1.3
	p.explosiveness = 0.55
	p.mesh = quad(0.2)
	p.material_override = particle_material(Icons.icon("heart"))
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 0.7
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, 0.15, 0)
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.scale_amount_curve = pop_curve()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.18
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, 2.0)


## Golden sparkles around a point (celebrate, befriend, Lumi's glow pulse).
static func sparkles(parent: Node, pos: Vector3, radius: float = 0.5, count: int = 12, color: Color = Color(1, 0.93, 0.6)) -> void:
	if not _valid_parent(parent):
		return
	var p := CPUParticles3D.new()
	p.emitting = false          # emitting defaults to true: never burst at the origin before placement
	p.one_shot = true
	p.amount = count
	p.lifetime = 1.0
	p.explosiveness = 0.6
	p.mesh = quad(0.16)
	p.material_override = particle_material(Icons.icon("sparkle"))
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, -0.4, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.scale_amount_curve = pop_curve()
	p.color = color
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, 1.7)


## Stone chips (boulder hits, Pebble's headbutt).
static func chips(parent: Node, pos: Vector3, color: Color = Palette.STONE, count: int = 8) -> void:
	if not _valid_parent(parent):
		return
	var p := CPUParticles3D.new()
	p.emitting = false          # emitting defaults to true: never burst at the origin before placement
	p.one_shot = true
	p.amount = count
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.mesh = _box(0.07)
	p.material_override = Mat.toon(color)
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -12.0, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = pop_curve()
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, 1.3)


## A single music note that drifts up (happy humming).
static func note(parent: Node, pos: Vector3) -> void:
	if not _valid_parent(parent):
		return
	var s := Sprite3D.new()
	s.texture = Icons.icon("note")
	s.pixel_size = 0.0022
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.render_priority = 8
	parent.add_child(s)
	s.global_position = pos
	s.scale = Vector3.ONE * 0.2
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "position", s.position + Vector3(0.18, 0.55, 0.0), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.chain().tween_callback(s.queue_free)
