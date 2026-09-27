extends RefCounted
## Hit feedback helpers (all static, all safe to call from anywhere):
##   HitFx.flash(node)                 short white-rose flash on a node's meshes (or node.hit_flash())
##   HitFx.impact(pos, damage, color)  restrained particle burst + hit_soft / hit_hard sound
##   HitFx.burst(pos, color, amount)   generic one-shot particle puff
##   HitFx.spark(pos)                  "glance" sparks when a hit is shrugged off
##   HitFx.wisps(pos, color)           slow rising wisps (dissolving shadows)
##   HitFx.number(pos, amount)         subtle floating damage number
##   HitFx.ensure_hitstop()            installs the Events.hitstop consumer (tiny Engine.time_scale dip)
## Flashes respect Settings.reduce_flashing (softer tint). Nothing here flashes the screen.

const Palette := preload("res://src/art/palette.gd")

const FLASH_COLOR := Color(1.0, 0.86, 0.9)
const DEFAULT_IMPACT := Color(1.0, 0.93, 0.8)
const SPARK_COLOR := Color(1.0, 0.85, 0.55)
const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"
const MAX_HITSTOP := 0.08

static var _mats: Dictionary = {}
static var _pmesh: SphereMesh
static var _chip_mesh: PrismMesh
static var _pmat: StandardMaterial3D
static var _shrink: Curve
static var _font: Font
static var _font_tried := false
static var _hitstop: Node = null
static var show_numbers := true


# --- Materials ------------------------------------------------------------------------------------

## Cached additive unshaded overlay material (flashes, telegraph tints).
static func additive(color: Color) -> StandardMaterial3D:
	var key := "add|%s" % color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := new_additive(color)
	_mats[key] = m
	return m


## Non-cached additive material (for per-instance animated tints).
static func new_additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.disable_receive_shadows = true
	m.no_depth_test = false
	return m


## Non-cached alpha-blended unshaded overlay: mixes a surface toward a colour (telegraph tints and
## hit flashes read clearly on any base colour, unlike additive light). Animate albedo_color.a.
static func new_tint() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0)
	m.disable_receive_shadows = true
	m.render_priority = 1
	return m


static func reduce_flashing() -> bool:
	return bool(Settings.get_value("reduce_flashing"))


## Flash strength scaled by the comfort setting.
static func flash_strength(base: float = 0.6) -> float:
	return base * (0.45 if reduce_flashing() else 1.0)


# --- Flash ------------------------------------------------------------------------------------------

## Briefly tints every mesh under `target`. Nodes that implement hit_flash(duration) handle it
## themselves (enemy visuals combine it with their telegraph tint).
static func flash(target: Node, duration: float = 0.11, color: Color = FLASH_COLOR) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if target.has_method("hit_flash"):
		target.hit_flash(duration)
		return
	var v: Variant = target.get("visual")
	if v is Node and is_instance_valid(v) and (v as Node).has_method("hit_flash"):
		(v as Node).hit_flash(duration)
		return
	var s := flash_strength()
	var mat := additive(Color(color.r * s, color.g * s, color.b * s))
	var meshes: Array = []
	_collect_meshes(target, meshes)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.material_overlay != mat:
			m.set_meta("hitfx_prev", m.material_overlay)
			m.material_overlay = mat
	var tree := target.get_tree()
	tree.create_timer(duration, true, false, true).timeout.connect(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == mat:
				var prev: Variant = (mi as MeshInstance3D).get_meta("hitfx_prev", null)
				(mi as MeshInstance3D).material_overlay = prev as Material)


static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).visible and not n.has_meta("no_flash"):
		out.append(n)
	for c in n.get_children():
		if c is Node3D:
			_collect_meshes(c, out)


# --- Particles -------------------------------------------------------------------------------------

static func _particle_mesh() -> SphereMesh:
	if _pmesh == null:
		_pmat = StandardMaterial3D.new()
		_pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pmat.vertex_color_use_as_albedo = true
		_pmat.vertex_color_is_srgb = true
		_pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pmat.disable_receive_shadows = true
		_pmesh = SphereMesh.new()
		_pmesh.radius = 0.06
		_pmesh.height = 0.12
		_pmesh.radial_segments = 8
		_pmesh.rings = 4
		_pmesh.material = _pmat
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(0.6, 0.75))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _pmesh


static func _fx_parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


## One-shot particle puff. Returns the particles node (frees itself).
static func burst(pos: Vector3, color: Color, amount: int = 10, speed: float = 3.2, size: float = 1.0, gravity: float = -9.0, lifetime: float = 0.45, spread: float = 70.0) -> CPUParticles3D:
	var parent := _fx_parent()
	if parent == null or DisplayServer.get_name() == "headless":
		return null
	var p := CPUParticles3D.new()
	p.mesh = _particle_mesh()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.55 * size
	p.scale_amount_max = 1.15 * size
	p.scale_amount_curve = _shrink
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(lifetime + 0.4, false).timeout.connect(p.queue_free)
	return p


## Little flakes (leaves, thorns, bark) that tumble out along their flight direction.
static func chips(pos: Vector3, color: Color, amount: int = 8, speed: float = 3.2, lifetime: float = 0.6) -> CPUParticles3D:
	var p := burst(pos, color, amount, speed, 1.0, -11.0, lifetime, 75.0)
	if p == null:
		return null
	if _chip_mesh == null:
		_chip_mesh = PrismMesh.new()
		_chip_mesh.size = Vector3(0.13, 0.2, 0.03)
		_chip_mesh.material = _pmat
	p.mesh = _chip_mesh
	p.particle_flag_align_y = true
	return p


## Impact of a successful hit: small burst + impact sound.
static func impact(pos: Vector3, damage: float, color: Color = DEFAULT_IMPACT) -> void:
	var heavy := damage >= 15.0
	burst(pos, color, 10 if heavy else 7, 4.4 if heavy else 3.6, 0.7 if heavy else 0.55, -10.0, 0.3, 80.0)
	Audio.play_3d("hit_hard" if heavy else "hit_soft", pos, -2.0)


## Bright little sparks when an attack glances off armour.
static func spark(pos: Vector3) -> void:
	burst(pos, SPARK_COLOR, 9, 4.5, 0.5, -12.0, 0.3, 80.0)
	Audio.play_3d("hit_soft", pos, -4.0, 0.2)


## Slow, rising wisps (shadow creatures dissolving). Colour alpha is respected.
static func wisps(pos: Vector3, color: Color, amount: int = 14, size: float = 1.6) -> void:
	var p := burst(pos, color, amount, 1.1, size, 1.2, 1.3, 60.0)
	if p != null:
		p.explosiveness = 0.55
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.3


## Subtle floating damage number (rounded font, soft colours, fades in ~0.7 s).
static func number(pos: Vector3, amount: float, color: Color = Palette.UI_PAPER) -> void:
	if not show_numbers or amount < 0.5:
		return
	var parent := _fx_parent()
	if parent == null or DisplayServer.get_name() == "headless":
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.0032
	l.font_size = 44
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = Color(Palette.UI_INK, 0.85)
	l.double_sided = true
	l.render_priority = 5
	l.outline_render_priority = 4
	var f := _get_font()
	if f != null:
		l.font = f
	parent.add_child(l)
	var jitter := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	l.global_position = pos + jitter
	l.scale = Vector3.ONE * 0.6
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 0.7, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.35).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


static func _get_font() -> Font:
	if not _font_tried:
		_font_tried = true
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH)
	return _font


# --- Hitstop -----------------------------------------------------------------------------------------

## Installs (once) a persistent node under the root that answers Events.hitstop with a very short
## Engine.time_scale dip measured in real time (so it can never get stuck).
static func ensure_hitstop() -> void:
	if _hitstop != null and is_instance_valid(_hitstop):
		return
	if DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var existing := tree.root.get_node_or_null("HitstopListener")
	if existing != null:
		_hitstop = existing
		return
	_hitstop = HitstopListener.new()
	_hitstop.name = "HitstopListener"
	tree.root.add_child.call_deferred(_hitstop)


class HitstopListener extends Node:
	const SLOW := 0.05
	var _end_ms: int = 0
	var _active := false
	var _restore := 1.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Events.hitstop.connect(_on_hitstop)

	func _on_hitstop(duration: float) -> void:
		if duration <= 0.0 or get_tree().paused:
			return
		var end := Time.get_ticks_msec() + int(clampf(duration, 0.0, 0.08) * 1000.0)
		_end_ms = maxi(_end_ms, end)
		if not _active:
			_active = true
			_restore = Engine.time_scale if Engine.time_scale > SLOW else 1.0
			Engine.time_scale = SLOW

	func _process(_delta: float) -> void:
		if _active and (Time.get_ticks_msec() >= _end_ms or get_tree().paused):
			_active = false
			Engine.time_scale = _restore

	func _exit_tree() -> void:
		if _active:
			_active = false
			Engine.time_scale = _restore
