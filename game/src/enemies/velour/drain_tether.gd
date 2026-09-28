extends Node3D
## A visible velvet-light link between two points with a channel meter (Count Velour, MP 13.1). Used for:
##   * the DRAIN tether (Krystal -> the Count): during the wind-up a thin pulsing ribbon shows the connection
##     (the warning); during the channel a bright FILL creeps from her end toward him - he heals only when the
##     fill reaches him (the channel succeeded). Near the end the fill turns pale gold ("about to heal");
##   * the CANDLE stream in phase C (flame -> the Count): the same ribbon drinking the flame's light.
## Readable with the sound muted (shape + motion + brightness, never colour alone). With Settings reduce_flashing
## nothing pulses: the ribbon brightens steadily with the channel instead.
## top_level: positioned in world space, freed with its owner. Never casts shadows, never takes hit flashes.
##   var t := DrainTether.new(); t.setup({"color": Color(...)}); owner.add_child(t)
##   t.show_link(from, to, progress, channeling)   # every frame while it lasts
##   t.hide_link()

const HitFx := preload("res://src/combat/hit_fx.gd")

const WARN_RADIUS := 0.022
const CHANNEL_RADIUS := 0.045
const FILL_RADIUS := 0.07
const BEADS := 3
const LATE := 0.7                        # progress after which the fill shows the "about to heal" warning

var color: Color = Color(0.86, 0.36, 0.62)
var late_color: Color = Color(1.0, 0.9, 0.62)
var progress: float = 0.0
var channeling := false
var from_point := Vector3.ZERO
var to_point := Vector3.ZERO

var _t: float = 0.0
var _link: MeshInstance3D
var _fill: MeshInstance3D
var _beads: Array = []
var _link_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _bead_mat: StandardMaterial3D
var _showing := false

static var _cyl: CylinderMesh = null
static var _sph: SphereMesh = null


func setup(params: Dictionary) -> void:
	var c: Variant = params.get("color")
	if c is Color:
		color = c
	var l: Variant = params.get("late_color")
	if l is Color:
		late_color = l


func _ready() -> void:
	top_level = true
	name = name if name != "" else "Tether"
	_link_mat = _new_mat(color)
	_fill_mat = _new_mat(color.lightened(0.25))
	_bead_mat = _new_mat(Color(1.0, 0.95, 0.9))
	_link = _part(_cylinder(), _link_mat)
	_fill = _part(_cylinder(), _fill_mat)
	for i in BEADS:
		_beads.append(_part(_sphere(), _bead_mat))
	hide_link()


func is_showing() -> bool:
	return _showing


## Shows / updates the link from `a` (her end, or the flame) to `b` (his end). `k` = channel progress 0..1.
func show_link(a: Vector3, b: Vector3, k: float, is_channel: bool) -> void:
	if _link == null:
		return
	from_point = a
	to_point = b
	progress = clampf(k, 0.0, 1.0)
	channeling = is_channel
	_showing = true
	visible = true
	var r := CHANNEL_RADIUS if is_channel else WARN_RADIUS
	_place(_link, a, b, r)
	if is_channel and progress > 0.001:
		_place(_fill, a, a.lerp(b, progress), FILL_RADIUS)
		_fill.visible = true
	else:
		_fill.visible = false
	set_process(true)
	_apply_look()


func hide_link() -> void:
	_showing = false
	visible = false
	progress = 0.0
	channeling = false
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	_apply_look()


func _apply_look() -> void:
	if not _showing:
		return
	var calm := HitFx.reduce_flashing()
	var pulse := 0.5 + 0.5 * sin(_t * (6.0 if not channeling else 9.0))
	var a_link: float
	if channeling:
		a_link = (0.55 + 0.35 * progress) if calm else (0.5 + 0.25 * pulse + 0.2 * progress)
	else:
		a_link = 0.4 if calm else (0.25 + 0.45 * pulse)
	_link_mat.albedo_color = Color(color, clampf(a_link, 0.1, 1.0))
	var late := progress >= LATE
	var fc := late_color if late else color.lightened(0.25)
	var a_fill: float = 0.85 if calm else (0.7 + 0.3 * pulse if late else 0.8)
	_fill_mat.albedo_color = Color(fc, a_fill)
	# Beads travel from her end toward his: the direction the light is being drawn.
	for i in _beads.size():
		var mi := _beads[i] as MeshInstance3D
		mi.visible = channeling
		if not channeling:
			continue
		var f := fposmod(_t * 0.9 + float(i) / float(BEADS), 1.0)
		mi.global_position = from_point.lerp(to_point, f)
		var s := 0.06 + 0.03 * progress
		mi.scale = Vector3.ONE * s / 0.5


func _place(mi: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.02:
		mi.visible = false
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x * (radius / 0.5), y * l, z * (radius / 0.5)), (a + b) * 0.5)
	mi.visible = true


func _part(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	add_child(mi)
	return mi


static func _new_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c, 0.6)
	m.disable_receive_shadows = true
	return m


## Unit cylinder (radius 0.5, height 1) shared by every tether.
static func _cylinder() -> CylinderMesh:
	if _cyl == null:
		_cyl = CylinderMesh.new()
		_cyl.top_radius = 0.5
		_cyl.bottom_radius = 0.5
		_cyl.height = 1.0
		_cyl.radial_segments = 6
		_cyl.rings = 1
	return _cyl


static func _sphere() -> SphereMesh:
	if _sph == null:
		_sph = SphereMesh.new()
		_sph.radius = 0.5
		_sph.height = 1.0
		_sph.radial_segments = 8
		_sph.rings = 4
	return _sph
