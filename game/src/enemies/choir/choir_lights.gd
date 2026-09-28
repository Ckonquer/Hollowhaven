extends Node3D
## Phase C "The kept flame" (MP §13.3): false cozy lights compete with ONE visibly anchored true flame.
##   * the true flame hangs from a lantern anchor's hook on a short chain (anchored: it never floats free), is a
##     real OmniLight3D + light source (choir_true_flame.gd) and washes its SECTOR of the floor with warm light
##     (a lit wedge from the centre to the perimeter walk) - the one safe place from the hush inside the ring;
##   * the false cozy lights are round paper lanterns that bob over the other sectors (a warm glowing paper globe in
##     a cage of four wooden ribs, a wooden cap with a hanger loop and a wooden base, a ribbon tail - CR-14: never a
##     warm sphere with dark polar caps, which read as eyeballs): warm and inviting, but emissive only - no Light3D,
##     not light sources, their floor stays dark (the Borrowed Porch rule);
##   * high_visibility_cues: a bold outlined ring round the true flame's anchor and bold bars along its sector
##     edges (shape, never colour alone).
## Visual + geometry only; the boss owns timing and damage (Rules.in_hush / in_lit_sector use the same numbers).
##   lights.begin(n_false)  lights.move_flame(from, to, len, via := INF)  lights.settle(anchor_pos, hook_pos,
##   lit_dir, lit_deg, radius)  lights.unsettle()  lights.place_false([Vector3...])  lights.clear()

const Art := preload("res://src/enemies/choir/choir_art.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")
const FlameMarker := preload("res://src/enemies/choir/choir_true_flame.gd")
const Rules := preload("res://src/enemies/choir/choir_rules.gd")

const MAX_FALSE := 3
const FALSE_Y := 2.2
const LANTERN_PAPER := Color("ffb870")
const LANTERN_RIB := Color("c0703a")
const LANTERN_WOOD := Color("8a5a3c")
const LANTERN_RIBS := 4

var center: Vector3 = Vector3.ZERO
var hv: bool = false
var settled: bool = false
var lit_dir: Vector3 = Vector3.FORWARD
var lit_deg: float = 80.0
var lit_radius: float = 10.0
var anchor_pos: Vector3 = Vector3.ZERO

var _flame: Node3D
var _flame_light: OmniLight3D
var _flame_marker: Node3D
var _chain: MeshInstance3D
var _sector: MeshInstance3D
var _hv: Node3D
var _false: Array = []
var _false_home: Array = []
var _t: float = 0.0
var _move_from := Vector3.ZERO
var _move_to := Vector3.ZERO
var _move_via := Vector3.INF
var _move_t: float = 0.0
var _move_len: float = 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_flame = Node3D.new()
	_flame.name = "TrueFlame"
	add_child(_flame)
	Kit.add(_flame, Kit.cylinder(0.16, 0.2, 0.34, Mat.transparent(Color(1.0, 0.9, 0.7, 0.35), true), 10))
	Kit.add(_flame, Kit.sphere(0.11, Mat.glow(Palette.LANTERN_GLOW, 3.4), 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.5, 1))
	Kit.add(_flame, Kit.cylinder(0.2, 0.2, 0.05, Mat.toon(Color("3b3238")), 10), Vector3(0, 0.2, 0))
	_chain = Kit.cylinder(0.02, 0.02, 1.0, Mat.toon(Color("3b3238")), 5)
	Kit.add(_flame, _chain, Vector3(0, 0.7, 0))
	_flame_light = OmniLight3D.new()
	_flame_light.name = "Light"
	_flame_light.light_color = Palette.LANTERN_GLOW
	_flame_light.omni_range = 5.0
	_flame_light.light_energy = 1.7
	_flame_light.shadow_enabled = false
	_flame.add_child(_flame_light)
	_flame_marker = FlameMarker.new()
	_flame_marker.name = "LightSource"
	_flame.add_child(_flame_marker)
	_sector = MeshInstance3D.new()
	_sector.name = "LitSector"
	_sector.material_override = Mat.transparent(Art.LIT_FLOOR, true)
	_sector.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sector)
	_hv = Node3D.new()
	_hv.name = "Hv"
	add_child(_hv)
	for i in MAX_FALSE:
		var f := Node3D.new()
		f.name = "FalseLight_%d" % i
		add_child(f)
		_build_lantern(f, i)
		_false.append(f)
		_false_home.append(Vector3.ZERO)
	clear()
	set_process(false)


## A round paper lantern: warm, cozy, and lighting nothing at all (emissive paper, no Light3D). Shared meshes /
## materials, no shadows (it floats; a shadow blob under it would suggest real light).
static func _build_lantern(f: Node3D, i: int) -> void:
	var paper := Kit.sphere(0.3, Mat.glow(LANTERN_PAPER, 1.6), 10, 12)
	paper.name = "Paper"
	Kit.add(f, paper, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.08, 1.0))
	var parts: Array = [paper]
	var rib := Mat.toon(LANTERN_RIB, {"rim": 0.3})
	for k in LANTERN_RIBS:
		var r := Kit.torus(0.285, 0.315, rib)
		r.name = "Rib%d" % k
		Kit.add(f, r, Vector3.ZERO, Vector3(90.0, 180.0 / float(LANTERN_RIBS) * float(k), 0.0), Vector3(1.0, 1.0, 1.08))
		parts.append(r)
	var wood := Mat.toon(LANTERN_WOOD, {"rim": 0.3})
	var cap := Kit.cylinder(0.17, 0.2, 0.07, wood, 12)
	cap.name = "Cap"
	Kit.add(f, cap, Vector3(0, 0.3, 0))
	var hanger := Kit.torus(0.05, 0.075, wood)
	hanger.name = "Hanger"
	Kit.add(f, hanger, Vector3(0, 0.38, 0), Vector3(90, 0, 0))
	var base := Kit.cylinder(0.2, 0.17, 0.07, wood, 12)
	base.name = "Base"
	Kit.add(f, base, Vector3(0, -0.3, 0))
	parts.append_array([cap, hanger, base])
	for mi in parts:
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Art.ribbon(f, Vector3(0, -0.34, 0), 0.5, Art.RIBBONS[(i + 1) % Art.RIBBONS.size()], 0.05)


func begin(n_false: int, c: Vector3) -> void:
	center = c
	visible = true
	_flame.visible = true
	(_flame_marker as Node).set("lit", true)
	_flame.global_position = c + Vector3.UP * 3.0
	for i in _false.size():
		(_false[i] as Node3D).visible = i < n_false


func clear() -> void:
	settled = false
	visible = false
	if _flame_marker != null:
		(_flame_marker as Node).set("lit", false)
	if _sector != null:
		_sector.visible = false
	if _hv != null:
		_clear_hv()
	_move_len = 0.0


func false_count() -> int:
	var n := 0
	for f in _false:
		if (f as Node3D).visible:
			n += 1
	return n


## True light facts (tests): the flame is a light source, the false lights are not.
func flame_is_light() -> bool:
	return _flame_marker != null and bool(_flame_marker.call("is_light_active"))


func false_lights_nodes() -> Array:
	return _false.duplicate()


func flame_node() -> Node3D:
	return _flame


func flame_position() -> Vector3:
	return _flame.global_position


## The flame travels to `to` (a hook) over `length` s; with a finite `via` it first heads there (Intense feint)
## and swings to `to` for the last part (Rules.INTENSE_FEINT_AT).
func move_flame(from: Vector3, to: Vector3, length: float, via: Vector3 = Vector3.INF) -> void:
	unsettle()
	_move_from = from
	_move_to = to
	_move_via = via
	_move_t = 0.0
	_move_len = maxf(length, 0.01)
	_flame.global_position = from


func place_false(points: Array) -> void:
	for i in _false.size():
		var f: Node3D = _false[i]
		if i < points.size() and f.visible:
			_false_home[i] = points[i]
			f.global_position = (points[i] as Vector3) + Vector3.UP * FALSE_Y


## The flame is on its hook: its sector lights up (the only safe wedge inside the ring).
func settle(a_pos: Vector3, hook: Vector3, dir: Vector3, deg: float, radius: float) -> void:
	settled = true
	anchor_pos = a_pos
	_move_len = 0.0
	_flame.global_position = hook
	lit_dir = Vector3(dir.x, 0.0, dir.z).normalized() if Vector3(dir.x, 0.0, dir.z).length_squared() > 0.0001 else Vector3.FORWARD
	lit_deg = deg
	lit_radius = radius
	_sector.visible = true
	_sector.mesh = Art.sector_mesh(deg, 0.12)
	_sector.global_transform = Transform3D(Basis(Vector3.UP, atan2(lit_dir.x, lit_dir.z)).scaled(Vector3(radius, 1.0, radius)), center + Vector3.UP * 0.035)
	_chain.visible = true
	_clear_hv()
	if hv:
		var ring := Art.bold_ring(_hv, 1.45, 0.06)
		ring.global_position = a_pos + Vector3.UP * 0.06
		var half := deg_to_rad(deg) * 0.5
		var base_ang := atan2(lit_dir.x, lit_dir.z)
		for s in [-1.0, 1.0]:
			var e := Vector3(sin(base_ang + half * s), 0.0, cos(base_ang + half * s))
			var bar := Art.bold_bar(_hv, center + e * 1.2, center + e * radius, 0.05)
			bar.name = "HvEdgeL" if s < 0.0 else "HvEdgeR"


func unsettle() -> void:
	settled = false
	_sector.visible = false
	_clear_hv()


func set_hv(on: bool) -> void:
	hv = on
	if settled:
		settle(anchor_pos, _flame.global_position, lit_dir, lit_deg, lit_radius)


func hv_visible() -> bool:
	return _hv.get_child_count() > 0 and visible


## The false lights gutter while the Choir is exposed at the true flame (they cannot bear real light).
func gutter_false(on: bool) -> void:
	for f in _false:
		(f as Node3D).scale = Vector3.ONE * (0.55 if on else 1.0)


func _clear_hv() -> void:
	for c in _hv.get_children():
		_hv.remove_child(c)
		c.queue_free()


## Driven by the boss's tick (one deterministic clock; tests drive it).
func tick(delta: float) -> void:
	_t += delta
	if _move_len > 0.0:
		_move_t = minf(_move_t + delta, _move_len)
		var k := _move_t / _move_len
		var p: Vector3
		if _move_via.is_finite():
			var fk: float = Rules.INTENSE_FEINT_AT
			if k < fk:
				var e := k / fk
				p = _move_from.lerp(_move_via, e * e * (3.0 - 2.0 * e))
			else:
				var e2 := (k - fk) / maxf(1.0 - fk, 0.01)
				p = _move_via.lerp(_move_to, e2 * e2 * (3.0 - 2.0 * e2))
		else:
			p = _move_from.lerp(_move_to, k * k * (3.0 - 2.0 * k))
		p.y += sin(k * PI) * 0.8
		_flame.global_position = p
		_chain.visible = false
		if _move_t >= _move_len:
			_move_len = 0.0
	for i in _false.size():
		var f: Node3D = _false[i]
		if f.visible:
			var h: Vector3 = _false_home[i]
			f.global_position = h + Vector3(sin(_t * 0.7 + float(i)) * 0.35, FALSE_Y + sin(_t * 1.3 + float(i) * 2.0) * 0.18, cos(_t * 0.6 + float(i)) * 0.35)

