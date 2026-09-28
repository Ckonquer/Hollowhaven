extends Node3D
## Phase B resonance rings (MP §13.3 "visible expanding resonance rings"). A ring is a knee-high band of pale
## violet light rolling outward from the Choir; each ring has ONE marked opening (a pale lit lane from the
## centre to the edge, with two little posts and - with high_visibility_cues - bold outlined edge bars) that is
## shown BEFORE the ring launches. Stand in the lane, stay on the perimeter walk (rings fade before it), or
## dodge through. Readable with sound muted; timing assist slows the rings and widens the openings.
## Pure data + visuals: the boss decides who is hit (overlapping() + mark_hit(), one hit per ring).
##   rings.preview([{"dir": Vector3, "deg": 85.0}], r_max)   rings.launch(center, dir, deg, speed, r0, r_max, delay)
##   rings.tick(dt)   rings.overlapping(pos, safe_radius) -> [slot]   rings.mark_hit(slot)   rings.clear()

const Rules := preload("res://src/enemies/choir/choir_rules.gd")
const Art := preload("res://src/enemies/choir/choir_art.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const SEGMENTS := 48
const RING_HEIGHT := 0.9
const RING_COLOR := Color(0.82, 0.72, 1.0, 0.55)

var center: Vector3 = Vector3.ZERO
var hv: bool = false
var rings: Array = []            # per slot: {"active", "delay", "r", "r_prev", "speed", "gap_dir", "gap_deg", "r_max", "band", "hit"}
var launched: int = 0            # total rings launched (tests)

var _mm: Array = []              # MultiMeshInstance3D per slot
var _lanes: Array = []           # Node3D per slot (lane wash + posts + hv bars)
var _lane_fill: Array = []       # MeshInstance3D per slot
var _lane_hv: Array = []         # Node3D per slot

static var _seg_mesh: BoxMesh = null


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	for i in Rules.MAX_RINGS:
		rings.append(_empty())
		_build_slot(i)


func _empty() -> Dictionary:
	return {"active": false, "delay": 0.0, "r": 0.0, "r_prev": 0.0, "speed": 0.0, "gap_dir": Vector3.FORWARD,
		"gap_deg": 90.0, "r_max": 0.0, "band": Rules.RING_BAND, "hit": false}


static func _segment_mesh() -> BoxMesh:
	if _seg_mesh == null:
		_seg_mesh = BoxMesh.new()
		_seg_mesh.size = Vector3(1.0, RING_HEIGHT, Rules.RING_BAND)
	return _seg_mesh


func _build_slot(i: int) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Ring_%d" % i
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _segment_mesh()
	mm.instance_count = SEGMENTS
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = Mat.transparent(RING_COLOR, true)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_mm.append(mmi)
	var lane := Node3D.new()
	lane.name = "GapLane_%d" % i
	add_child(lane)
	lane.visible = false
	var fill := MeshInstance3D.new()
	fill.name = "Wash"
	fill.material_override = Mat.transparent(Art.SAFE_LANE, true)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lane.add_child(fill)
	fill.position = Vector3(0, 0.03, 0)
	_lanes.append(lane)
	_lane_fill.append(fill)
	var hvn := Node3D.new()
	hvn.name = "Hv"
	lane.add_child(hvn)
	_lane_hv.append(hvn)


func is_busy() -> bool:
	return active_count() > 0


func active_count() -> int:
	var n := 0
	for r in rings:
		if bool((r as Dictionary)["active"]):
			n += 1
	return n


func ring(slot: int) -> Dictionary:
	return (rings[slot] as Dictionary).duplicate() if slot >= 0 and slot < rings.size() else {}


## Shows the openings of the coming rings (before any ring launches). Each entry {"dir": Vector3, "deg": float}.
func preview(gaps: Array, r_max: float) -> void:
	for i in _lanes.size():
		if i < gaps.size():
			var g: Dictionary = gaps[i]
			_show_lane(i, g["dir"], float(g["deg"]), r_max)
		elif not bool((rings[i] as Dictionary)["active"]):
			(_lanes[i] as Node3D).visible = false


func _show_lane(i: int, dir: Vector3, deg: float, r_max: float) -> void:
	var lane: Node3D = _lanes[i]
	lane.visible = true
	lane.global_position = center
	var f := Vector3(dir.x, 0.0, dir.z)
	lane.rotation = Vector3(0.0, atan2(f.x, f.z) if f.length_squared() > 0.0001 else 0.0, 0.0)
	var fill: MeshInstance3D = _lane_fill[i]
	fill.mesh = Art.sector_mesh(deg, 0.15)
	fill.scale = Vector3(r_max, 1.0, r_max)
	var hvn: Node3D = _lane_hv[i]
	for c in hvn.get_children():
		c.queue_free()
	var half := deg_to_rad(deg) * 0.5
	for s in [-1.0, 1.0]:
		var edge := Vector3(sin(half * s), 0.0, cos(half * s))
		var post := Kit.cylinder(0.07, 0.09, 0.5, Art.dim_glow(1.6), 8)
		Kit.add(hvn, post, edge * (r_max - 0.2) + Vector3(0, 0.25, 0))
		post.name = "Post"
		if hv:
			Art.bold_bar(hvn, edge * 0.6, edge * r_max, 0.06)


## Launches one ring into a free slot (the first one whose lane is not taken). Returns the slot, or -1 when both
## slots are busy (the cap: never more than Rules.MAX_RINGS alive).
func launch(c: Vector3, gap_dir: Vector3, gap_deg: float, speed: float, r_start: float, r_max: float, delay: float = 0.0, slot_hint: int = -1) -> int:
	var slot := -1
	if slot_hint >= 0 and slot_hint < rings.size() and not bool((rings[slot_hint] as Dictionary)["active"]):
		slot = slot_hint
	else:
		for i in rings.size():
			if not bool((rings[i] as Dictionary)["active"]):
				slot = i
				break
	if slot < 0:
		return -1
	center = c
	var d := Vector3(gap_dir.x, 0.0, gap_dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	rings[slot] = {"active": true, "delay": maxf(delay, 0.0), "r": r_start, "r_prev": r_start, "speed": maxf(speed, 0.1),
		"gap_dir": d, "gap_deg": gap_deg, "r_max": r_max, "band": Rules.RING_BAND, "hit": false}
	launched += 1
	_show_lane(slot, d, gap_deg, r_max)
	_update_slot(slot)
	return slot


func tick(dt: float) -> void:
	for i in rings.size():
		var r: Dictionary = rings[i]
		if not bool(r["active"]):
			continue
		if float(r["delay"]) > 0.0:
			r["delay"] = float(r["delay"]) - dt
			(_mm[i] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
			continue
		r["r_prev"] = float(r["r"])
		r["r"] = float(r["r"]) + float(r["speed"]) * dt
		if float(r["r"]) >= float(r["r_max"]):
			_end_slot(i)
			continue
		_update_slot(i)


## Slots whose moving band passed over `pos` this step, outside their opening, not yet hit, and only inside
## `safe_radius` (the perimeter walk beyond it is always safe from rings).
func overlapping(pos: Vector3, safe_radius: float) -> Array:
	var out: Array = []
	if Rules.flat(center, pos) >= safe_radius:
		return out
	for i in rings.size():
		var r: Dictionary = rings[i]
		if not bool(r["active"]) or bool(r["hit"]) or float(r["delay"]) > 0.0:
			continue
		if not Rules.band_hit(center, float(r["r_prev"]), float(r["r"]), float(r["band"]), pos):
			continue
		if Rules.in_gap(center, r["gap_dir"], float(r["gap_deg"]), pos):
			continue
		out.append(i)
	return out


func mark_hit(slot: int) -> void:
	if slot >= 0 and slot < rings.size():
		(rings[slot] as Dictionary)["hit"] = true


func clear() -> void:
	for i in rings.size():
		_end_slot(i)
	for l in _lanes:
		(l as Node3D).visible = false


func _end_slot(i: int) -> void:
	var r: Dictionary = rings[i]
	r["active"] = false
	(_mm[i] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	(_lanes[i] as Node3D).visible = false


func _update_slot(i: int) -> void:
	var r: Dictionary = rings[i]
	var mm: MultiMesh = (_mm[i] as MultiMeshInstance3D).multimesh
	var rad := float(r["r"])
	var seg_len := TAU * rad / float(SEGMENTS) * 1.08
	var gap_dir: Vector3 = r["gap_dir"]
	var gap_deg := float(r["gap_deg"])
	var gap_ang := atan2(gap_dir.z, gap_dir.x)
	for k in SEGMENTS:
		var ang := TAU * (float(k) + 0.5) / float(SEGMENTS)
		var off := rad_to_deg(absf(wrapf(ang - gap_ang, -PI, PI)))
		if off <= gap_deg * 0.5:
			mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), center))
			continue
		var p := center + Vector3(cos(ang) * rad, RING_HEIGHT * 0.5, sin(ang) * rad)
		var basis := Basis(Vector3.UP, -ang + PI * 0.5) * Basis.from_scale(Vector3(seg_len, 1.0, 1.0))
		mm.set_instance_transform(k, Transform3D(basis, p))
	mm.visible_instance_count = SEGMENTS
