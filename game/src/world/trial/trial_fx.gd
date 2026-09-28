extends RefCounted
## Shared look of the Echo Trials (src/world/trial/*, the arena builders and the entry stone): the pale drifting
## motes that mark a memory, the echo stone, and the pale entry-pad ring. Static helpers, cached meshes /
## materials (Mat / Kit caches + one static mote mesh), nothing that processes per frame from here. No flashing:
## every glow is steady (comfort: reduce_flashing never has anything to calm here).

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const STONE := Color("6a6282")
const BAND := Color("cbb8ff")
const MOTE := Color(0.85, 0.8, 1.0, 0.7)

static var _mote_mesh: SphereMesh = null


static func _motes_mesh() -> SphereMesh:
	if _mote_mesh == null:
		_mote_mesh = SphereMesh.new()
		_mote_mesh.radius = 0.03
		_mote_mesh.height = 0.06
		_mote_mesh.radial_segments = 6
		_mote_mesh.rings = 3
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = MOTE
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mote_mesh.material = pm
	return _mote_mesh


## Slow pale motes rising through `extents` (half size) around `pos`: "this is a memory".
static func motes(parent: Node3D, pos: Vector3, extents: Vector3, amount: int = 48) -> CPUParticles3D:
	var m := CPUParticles3D.new()
	m.name = "EchoMotes"
	m.mesh = _motes_mesh()
	m.amount = amount
	m.lifetime = 6.0
	m.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3.UP
	m.spread = 30.0
	m.initial_velocity_min = 0.05
	m.initial_velocity_max = 0.2
	m.gravity = Vector3(0, 0.05, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	parent.add_child(m)
	return m


## The echo stone's body (a rounded pale stone with a steady violet band) under `parent`, standing on y = 0.
static func stone(parent: Node3D, radius: float = 0.4) -> void:
	var sm := Mat.outlined(Mat.toon(STONE, {"rim": 0.35, "noise": 0.18}), 0.014)
	Kit.add(parent, Kit.blob(radius, sm, 17, 0.16, 1.9, 2), Vector3(0, radius * 1.5, 0))
	var band := Kit.torus(radius * 1.02, radius * 1.12, Mat.glow(BAND, 1.2))
	Kit.add(parent, band, Vector3(0, radius * 1.8, 0), Vector3.ZERO, Vector3(1, 1.8, 1))
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A pale ring on the floor (the entry pad: safe, where the echo begins and ends).
static func pad_ring(parent: Node3D, pos: Vector3, radius: float) -> void:
	var ring := Kit.torus(radius - 0.12, radius, Mat.glow(BAND, 0.5))
	Kit.add(parent, ring, pos + Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.2, 1))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
