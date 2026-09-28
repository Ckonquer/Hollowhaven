extends Node3D
## Shared ground telegraphs for enemy attacks (Chapter Two): a flat decal that shows exactly where an
## attack will land, readable with the sound muted.
##   ring   circle outline + faint fill        (radial pulses, leap landing marks)
##   disc   small solid mark                   (spot marks)
##   lane   straight lane + arrow head         (charges, dash lines, ground scrapes)
##   arc    sector (wedge) + rim               (sweeps and narrow swings)
##   spots  up to MAX_SPOTS small rings        (where roots / hazards will rise)
## One node per enemy, created lazily by enemy_base.mark(): it is a top_level child of the enemy (so it is
## freed with it and never outlives a despawn) and is re-used for every wind-up. Meshes are unit shapes shared
## by every instance (static cache) and scaled per use; the pulse swaps between LEVELS cached alpha materials
## instead of animating a per-instance material, so a mark allocates nothing per frame.
## Comfort: with Settings reduce_flashing the mark does not pulse; it firms up steadily as the wind-up
## completes. The numbers of the footprint (radius, width, arc) are the SAME numbers the attack resolves with,
## so what is marked is what hits (tests compare them through footprint()).
##   var m := enemy.mark(); m.show_lane(a, b, 1.6, TelegraphFx.DANGER); m.set_progress(k, locked); m.hide_mark()

const HitFx := preload("res://src/combat/hit_fx.gd")

const DANGER := Color(0.96, 0.33, 0.24)      # committed melee / charges
const WARN := Color(1.0, 0.7, 0.28)          # sweeps and swings
const COOL := Color(0.72, 0.87, 1.0)         # ground scrapes (a different colour from the swing)
const ROOT := Color(0.64, 0.86, 0.42)        # roots / plant hazards
const PALE := Color(0.93, 0.92, 0.84)        # pale marks (arachnophobia-friendly leap mark)
const LEVELS := 8
const Y_OFFSET := 0.06
const MAX_SPOTS := 8
const RING_INNER := 0.84
const RIM_INNER := 0.9
const FAN_SEGMENTS := 36

var kind: String = ""
var color: Color = DANGER
var progress: float = 0.0
var locked := false
var center := Vector3.ZERO
var radius: float = 0.0
var from := Vector3.ZERO
var to := Vector3.ZERO
var width: float = 0.0
var facing := Vector3.FORWARD
var arc_deg: float = 0.0
var points: Array = []

var _t: float = 0.0
var _fill: MeshInstance3D
var _edge: MeshInstance3D
var _head: MeshInstance3D
var _spots: Array = []
var _fill_mats: Array = []
var _edge_mats: Array = []
var _level: int = -1

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


func _ready() -> void:
	top_level = true
	_ensure_parts()
	_clear()


func _ensure_parts() -> void:
	if _fill != null:
		return
	_fill = _new_part()
	_edge = _new_part()
	_head = _new_part()


func _new_part() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)          # hit flashes never tint the ground mark
	add_child(mi)
	return mi


# --- Public API ------------------------------------------------------------------------------------------

func show_ring(at: Vector3, r: float, col: Color = DANGER) -> void:
	_begin("ring", col)
	center = at
	radius = r
	global_transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * Y_OFFSET)
	_set_part(_fill, _disc_mesh(), Vector3(r, 1.0, r), Vector3.ZERO)
	_set_part(_edge, _ring_mesh(), Vector3(r, 1.0, r), Vector3(0.0, 0.004, 0.0))
	_finish_show()


func show_disc(at: Vector3, r: float, col: Color = DANGER) -> void:
	_begin("disc", col)
	center = at
	radius = r
	global_transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * Y_OFFSET)
	_set_part(_edge, _disc_mesh(), Vector3(r, 1.0, r), Vector3.ZERO)
	_finish_show()


## A straight lane from `a` to `b` of full width `w`, with an arrow head at `b`.
func show_lane(a: Vector3, b: Vector3, w: float, col: Color = DANGER) -> void:
	_begin("lane", col)
	from = a
	to = b
	width = w
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := d.length()
	facing = d / length if length > 0.001 else Vector3.FORWARD
	global_transform = Transform3D(_basis_toward(facing), a + Vector3.UP * Y_OFFSET)
	_set_part(_fill, _quad_mesh(), Vector3(w, 1.0, maxf(length, 0.01)), Vector3.ZERO)
	_set_part(_edge, _quad_frame_mesh(), Vector3(w, 1.0, maxf(length, 0.01)), Vector3(0.0, 0.004, 0.0))
	var head_len := minf(w * 0.8, maxf(length * 0.4, 0.05))
	_set_part(_head, _arrow_mesh(), Vector3(w * 0.9, 1.0, head_len), Vector3(0.0, 0.006, -(length - head_len)))
	_finish_show()


## Moves an already shown lane (cheap: no material lookups; used while a wind-up still tracks Krystal).
func move_lane(a: Vector3, b: Vector3) -> void:
	if kind != "lane":
		show_lane(a, b, width, color)
		return
	from = a
	to = b
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := d.length()
	facing = d / length if length > 0.001 else facing
	global_transform = Transform3D(_basis_toward(facing), a + Vector3.UP * Y_OFFSET)
	_fill.scale = Vector3(width, 1.0, maxf(length, 0.01))
	_edge.scale = _fill.scale
	var head_len := minf(width * 0.8, maxf(length * 0.4, 0.05))
	_head.scale = Vector3(width * 0.9, 1.0, head_len)
	_head.position = Vector3(0.0, 0.006, -(length - head_len))


## Turns / moves an already shown arc (cheap; used while a wind-up still tracks Krystal).
func move_arc(at: Vector3, dir: Vector3) -> void:
	if kind != "arc":
		show_arc(at, dir, radius, arc_deg, color)
		return
	center = at
	var f := Vector3(dir.x, 0.0, dir.z)
	if f.length_squared() > 0.0001:
		facing = f.normalized()
	global_transform = Transform3D(_basis_toward(facing), at + Vector3.UP * Y_OFFSET)


## A wedge of `arc` degrees (full width) and radius `r` around `dir` (flat) from `at`.
func show_arc(at: Vector3, dir: Vector3, r: float, arc: float, col: Color = WARN) -> void:
	_begin("arc", col)
	center = at
	radius = r
	arc_deg = clampf(arc, 1.0, 360.0)
	var f := Vector3(dir.x, 0.0, dir.z)
	facing = f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D(_basis_toward(facing), at + Vector3.UP * Y_OFFSET)
	_set_part(_fill, _sector_mesh(arc_deg), Vector3(r, 1.0, r), Vector3.ZERO)
	_set_part(_edge, _sector_rim_mesh(arc_deg), Vector3(r, 1.0, r), Vector3(0.0, 0.004, 0.0))
	_finish_show()


## Several small ring marks (bounded by MAX_SPOTS) at world positions.
func show_spots(at: Array, r: float, col: Color = ROOT) -> void:
	_begin("spots", col)
	radius = r
	points = []
	global_transform = Transform3D.IDENTITY
	for i in MAX_SPOTS:
		if i >= _spots.size():
			if i >= at.size():
				break
			_spots.append(_new_part())
		var mi: MeshInstance3D = _spots[i]
		if i < at.size() and at[i] is Vector3:
			var p: Vector3 = at[i]
			points.append(p)
			mi.mesh = _ring_mesh()
			mi.position = p + Vector3.UP * Y_OFFSET
			mi.scale = Vector3(r, 1.0, r)
			mi.visible = true
		else:
			mi.visible = false
	_finish_show()


## 0..1 wind-up progress; `lock` = the attack direction is now fixed (the mark firms up).
func set_progress(k: float, lock: bool = false) -> void:
	progress = clampf(k, 0.0, 1.0)
	locked = lock


func hide_mark() -> void:
	_clear()


func is_showing() -> bool:
	return kind != ""


## The marked area as numbers (tests compare it with the area the attack resolves with).
func footprint() -> Dictionary:
	return {"kind": kind, "center": center, "radius": radius, "from": from, "to": to, "width": width,
		"facing": facing, "arc_deg": arc_deg, "points": points.duplicate(), "locked": locked}


# --- Pure geometry (flat XZ; shared by the enemies' hit tests) ---------------------------------------------

## Closest point to `p` on the segment a-b, measured on the ground plane (y interpolated along the segment).
static func closest_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return a
	var t := clampf(Vector2(p.x - a.x, p.z - a.z).dot(ab) / l2, 0.0, 1.0)
	return a.lerp(b, t)


static func segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var c := closest_on_segment(a, b, p)
	return Vector2(p.x - c.x, p.z - c.z).length()


## Is `p` within `half_width` of the segment a-b (a lane / dash line), on the ground plane?
static func segment_hit(a: Vector3, b: Vector3, half_width: float, p: Vector3) -> bool:
	return segment_distance(a, b, p) <= half_width


## Is `p` inside the wedge of full width `arc` degrees and radius `r` around `dir` from `c` (flat)?
static func in_sector(c: Vector3, dir: Vector3, r: float, arc: float, p: Vector3) -> bool:
	var flat := Vector2(p.x - c.x, p.z - c.z)
	var dist := flat.length()
	if dist > r:
		return false
	if dist < 0.001 or arc >= 359.0:
		return true
	var f := Vector2(dir.x, dir.z)
	if f.length_squared() < 0.000001:
		return true
	return rad_to_deg(absf(f.normalized().angle_to(flat / dist))) <= arc * 0.5


static func in_ring(c: Vector3, r: float, p: Vector3) -> bool:
	return Vector2(p.x - c.x, p.z - c.z).length() <= r


# --- Animation ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if kind == "":
		return
	_t += delta
	var k := progress
	var s: float
	if HitFx.reduce_flashing():
		s = lerpf(0.3, 0.8, k) + (0.15 if locked else 0.0)       # steady, firming up (no strobe)
	else:
		var pulse := 0.5 + 0.5 * sin(_t * (7.0 + 9.0 * k))
		s = 0.2 + 0.45 * k + 0.3 * pulse * (1.0 - 0.5 * k)
		if locked:
			s = maxf(s, 0.75)
	var lvl := clampi(int(s * float(LEVELS)), 0, LEVELS - 1)
	if lvl != _level:
		_apply_level(lvl)


func _apply_level(lvl: int) -> void:
	_level = lvl
	if _fill_mats.size() < LEVELS or _edge_mats.size() < LEVELS:
		return
	var fm: Material = _fill_mats[lvl]
	var em: Material = _edge_mats[lvl]
	match kind:
		"disc":
			_edge.material_override = em
		"spots":
			for mi in _spots:
				(mi as MeshInstance3D).material_override = em
		_:
			_fill.material_override = fm
			_edge.material_override = em
			_head.material_override = em


func _begin(new_kind: String, col: Color) -> void:
	_ensure_parts()
	_clear()
	kind = new_kind
	color = col
	_t = 0.0
	_fill_mats = _mat_levels(col, false)
	_edge_mats = _mat_levels(col, true)


func _finish_show() -> void:
	visible = true
	set_process(true)
	_level = -1
	_apply_level(0)


func _clear() -> void:
	kind = ""
	progress = 0.0
	locked = false
	points = []
	visible = false
	set_process(false)
	for mi in [_fill, _edge, _head]:
		if mi != null:
			(mi as MeshInstance3D).visible = false
			(mi as MeshInstance3D).mesh = null
	for mi in _spots:
		(mi as MeshInstance3D).visible = false


func _set_part(mi: MeshInstance3D, mesh: Mesh, scl: Vector3, pos: Vector3) -> void:
	mi.mesh = mesh
	mi.scale = scl
	mi.position = pos
	mi.visible = true


static func _basis_toward(dir: Vector3) -> Basis:
	# Local -Z points along `dir` (flat), +Y stays up.
	var yaw := atan2(-dir.x, -dir.z)
	return Basis(Vector3.UP, yaw)


# --- Shared resources ----------------------------------------------------------------------------------------

static func _mat_levels(col: Color, edge: bool) -> Array:
	var key := "%s|%s" % [col.to_html(), "e" if edge else "f"]
	if _mats.has(key):
		return _mats[key]
	var out: Array = []
	for l in LEVELS:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		m.render_priority = 1
		var a := (0.35 + 0.09 * float(l)) if edge else (0.08 + 0.045 * float(l))
		m.albedo_color = Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))
		out.append(m)
	_mats[key] = out
	return out


static func _disc_mesh() -> Mesh:
	if _meshes.has("disc"):
		return _meshes["disc"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in FAN_SEGMENTS:
		var a0 := TAU * float(i) / float(FAN_SEGMENTS)
		var a1 := TAU * float(i + 1) / float(FAN_SEGMENTS)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
		st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
	var m := st.commit()
	_meshes["disc"] = m
	return m


static func _ring_mesh() -> Mesh:
	if _meshes.has("ring"):
		return _meshes["ring"]
	var m := _annulus(RING_INNER, 1.0, -PI, PI, FAN_SEGMENTS)
	_meshes["ring"] = m
	return m


## Unit quad from z = 0 to z = -1, x in [-0.5, 0.5].
static func _quad_mesh() -> Mesh:
	if _meshes.has("quad"):
		return _meshes["quad"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var p := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, -1)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.add_vertex(p[i])
	var m := st.commit()
	_meshes["quad"] = m
	return m


## Unit lane border: two thin side strips of the unit quad (8% of the width each).
static func _quad_frame_mesh() -> Mesh:
	if _meshes.has("frame"):
		return _meshes["frame"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for side in [-1.0, 1.0]:
		var x0: float = side * 0.5
		var x1: float = side * 0.42
		var p := [Vector3(x0, 0, 0), Vector3(x1, 0, 0), Vector3(x1, 0, -1), Vector3(x0, 0, -1)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(p[i])
	var m := st.commit()
	_meshes["frame"] = m
	return m


## Arrow head: a triangle pointing to -Z with its base at z = 0 (unit width, unit length).
static func _arrow_mesh() -> Mesh:
	if _meshes.has("arrow"):
		return _meshes["arrow"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(-0.5, 0, 0))
	st.add_vertex(Vector3(0.0, 0, -1))
	st.add_vertex(Vector3(0.5, 0, 0))
	var m := st.commit()
	_meshes["arrow"] = m
	return m


## Filled wedge of `arc` degrees around -Z, radius 1 (cached per whole degree).
static func _sector_mesh(arc: float) -> Mesh:
	var deg := clampi(int(round(arc)), 1, 360)
	var key := "sector|%d" % deg
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := deg_to_rad(float(deg)) * 0.5
	var segs := maxi(4, int(float(FAN_SEGMENTS) * float(deg) / 360.0) + 2)
	for i in segs:
		var a0 := -half + 2.0 * half * float(i) / float(segs)
		var a1 := -half + 2.0 * half * float(i + 1) / float(segs)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(_fan_point(a0, 1.0))
		st.add_vertex(_fan_point(a1, 1.0))
	var m := st.commit()
	_meshes[key] = m
	return m


static func _sector_rim_mesh(arc: float) -> Mesh:
	var deg := clampi(int(round(arc)), 1, 360)
	var key := "rim|%d" % deg
	if _meshes.has(key):
		return _meshes[key]
	var half := deg_to_rad(float(deg)) * 0.5
	var segs := maxi(4, int(float(FAN_SEGMENTS) * float(deg) / 360.0) + 2)
	var m := _annulus(RIM_INNER, 1.0, -half, half, segs, true)
	_meshes[key] = m
	return m


## Point at angle `a` (0 = straight ahead, -Z) and distance `r`.
static func _fan_point(a: float, r: float) -> Vector3:
	return Vector3(-sin(a) * r, 0.0, -cos(a) * r)


static func _annulus(inner: float, outer: float, a_from: float, a_to: float, segs: int, fan_axes: bool = false) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := a_from + (a_to - a_from) * float(i) / float(segs)
		var a1 := a_from + (a_to - a_from) * float(i + 1) / float(segs)
		var p0: Vector3
		var p1: Vector3
		var q0: Vector3
		var q1: Vector3
		if fan_axes:
			p0 = _fan_point(a0, inner)
			p1 = _fan_point(a1, inner)
			q0 = _fan_point(a0, outer)
			q1 = _fan_point(a1, outer)
		else:
			p0 = Vector3(cos(a0) * inner, 0, sin(a0) * inner)
			p1 = Vector3(cos(a1) * inner, 0, sin(a1) * inner)
			q0 = Vector3(cos(a0) * outer, 0, sin(a0) * outer)
			q1 = Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		st.add_vertex(p0)
		st.add_vertex(q0)
		st.add_vertex(q1)
		st.add_vertex(p0)
		st.add_vertex(q1)
		st.add_vertex(p1)
	return st.commit()
