extends Node3D
## Phase B short delayed strike zones (MP §13.3): up to Rules.MAX_STRIKES round floor marks (the shared
## src/enemies/telegraph_fx.gd ring: outline + fill that firms up as the delay runs out; steady with
## reduce_flashing), each with a small cracked bell hanging above it that drops when the zone strikes - so the
## warning reads with sound muted. The boss owns the timing and the one hit; this node owns the marks and the
## geometry (what is marked is what hits: hits() uses the same centre / radius the marks show).
##   strikes.place([Vector3...], radius)  strikes.set_progress(k)  strikes.hits(pos) -> bool  strikes.clear()

const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Rules := preload("res://src/enemies/choir/choir_rules.gd")
const Art := preload("res://src/enemies/choir/choir_art.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const BELL_HEIGHT := 3.4
const BODY := 0.35
const MAX_DY := 1.5

var radius: float = Rules.STRIKE_RADIUS
var points: Array = []
var placed: int = 0                # total zones ever placed (tests)
var hv: bool = false

var _marks: Array = []
var _bells: Array = []
var _hv_rings: Array = []
var _k: float = 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	for i in Rules.MAX_STRIKES:
		var m: Node3D = TelegraphFx.new()
		m.name = "StrikeMark_%d" % i
		add_child(m)
		_marks.append(m)
		var holder := Node3D.new()
		holder.name = "StrikeBell_%d" % i
		add_child(holder)
		holder.visible = false
		Art.bell(holder, Vector3.ZERO, 1.1)
		var ring := Art.bold_ring(holder, Rules.STRIKE_RADIUS + 0.15, 0.0)
		ring.visible = false
		_hv_rings.append(ring)
		_bells.append(holder)


func count() -> int:
	return points.size()


func is_showing() -> bool:
	return not points.is_empty()


## Marks zones at `at` (capped to Rules.MAX_STRIKES).
func place(at: Array, r: float) -> void:
	clear()
	radius = r
	for i in mini(at.size(), Rules.MAX_STRIKES):
		var p: Vector3 = at[i]
		points.append(p)
		(_marks[i] as Node3D).call("show_ring", p, r, TelegraphFx.DANGER)
		var b: Node3D = _bells[i]
		b.visible = true
		b.global_position = p + Vector3.UP * BELL_HEIGHT
		var hvr: MeshInstance3D = _hv_rings[i]
		hvr.visible = hv
		hvr.position = Vector3(0, -BELL_HEIGHT + 0.05, 0)
		placed += 1
	_k = 0.0


func set_progress(k: float, locked: bool = true) -> void:
	_k = clampf(k, 0.0, 1.0)
	for i in points.size():
		(_marks[i] as Node3D).call("set_progress", _k, locked)
		var b: Node3D = _bells[i]
		var p: Vector3 = points[i]
		# the bell sinks and starts to swing as the delay runs out
		b.global_position = p + Vector3.UP * lerpf(BELL_HEIGHT, BELL_HEIGHT - 1.0, _k)
		b.rotation.z = sin(_k * 18.0) * 0.12 * _k


## Is `pos` (her feet) inside any marked zone, at a reachable height?
func hits(pos: Vector3) -> bool:
	for p in points:
		var c: Vector3 = p
		if absf(pos.y - c.y) > MAX_DY:
			continue
		if Rules.flat(c, pos) <= radius + BODY:
			return true
	return false


## The zones strike: the bells drop onto the marks (FX only).
func strike_fx() -> void:
	for i in points.size():
		var p: Vector3 = points[i]
		var b: Node3D = _bells[i]
		b.global_position = p + Vector3.UP * 0.6
		if is_inside_tree():
			HitFx.burst(p + Vector3.UP * 0.2, Color(0.82, 0.72, 1.0), 10, 3.4, 1.0, -8.0, 0.5, 80.0)


func clear() -> void:
	points.clear()
	for m in _marks:
		(m as Node3D).call("hide_mark")
	for b in _bells:
		(b as Node3D).visible = false
	for r in _hv_rings:
		(r as Node3D).visible = false


func footprints() -> Array:
	var out: Array = []
	for i in points.size():
		out.append((_marks[i] as Node3D).call("footprint"))
	return out
