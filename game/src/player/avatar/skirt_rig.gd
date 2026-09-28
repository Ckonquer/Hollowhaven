extends RefCounted
## Procedural skirt / dress sway (no cloth simulation). A ring of N panels hangs from the hips; every panel
## pivot (Hips space: position (r sin th, y0, r cos th), rotation (-flare, th, side)) gets
##   flare = base + bell (uniform billow: falling, turning, running) + trail . outward (hem lags behind motion)
##           + a little running flutter, then pushed OUT by the legs (hard constraint from the thigh / shin
##           points of the current pose so legs never poke through), clamped to [min_flare, max_flare];
##   side  = the tangential part of the trail (panels swing sideways), clamped to +-max_side.
## Pure math on packed arrays (no allocation per frame); krystal_avatar.gd feeds it after posing the joints.
## Model space: +Z forward, +X = Krystal's left. Leg joints sit at (+-LEG_X, LEG_Y, 0) under the hips.

const LEG_X := 0.092
const LEG_Y := -0.005
const THIGH := 0.235
const THIGH_R := 0.082
const SHIN_R := 0.07
const MARGIN := 0.025

var count: int = 0
var radius: float = 0.18
var y0: float = 0.05
var length: float = 0.25
var base_flare: float = 0.2
var min_flare: float = 0.04
var max_flare: float = 1.3
var max_side: float = 0.3
var theta := PackedFloat32Array()
var flare := PackedFloat32Array()
var side := PackedFloat32Array()
var _dir := PackedVector2Array()        # outward (x, z) of each panel
var _trail := Vector2.ZERO              # hem offset direction in (x, z), spring
var _trail_v := Vector2.ZERO
var _bell: float = 0.0
var _bell_v: float = 0.0
var _pts := PackedVector3Array()        # leg sample points (hips space), reused every frame
var _rad := PackedFloat32Array()


## spec: {theta: [rad...], radius, y0, length, base, max}
func setup(spec: Dictionary) -> void:
	var th: Array = spec.get("theta", [])
	count = th.size()
	radius = float(spec.get("radius", radius))
	y0 = float(spec.get("y0", y0))
	length = float(spec.get("length", length))
	base_flare = float(spec.get("base", base_flare))
	max_flare = float(spec.get("max", max_flare))
	min_flare = minf(0.04, base_flare)
	theta.resize(count)
	flare.resize(count)
	side.resize(count)
	_dir.resize(count)
	for i in count:
		theta[i] = float(th[i])
		_dir[i] = Vector2(sin(theta[i]), cos(theta[i]))
		flare[i] = base_flare
		side[i] = 0.0
	_pts.resize(6)
	_rad.resize(6)
	reset()


func reset() -> void:
	_trail = Vector2.ZERO
	_trail_v = Vector2.ZERO
	_bell = 0.0
	_bell_v = 0.0
	for i in count:
		flare[i] = base_flare
		side[i] = 0.0


## lv / acc: local velocity / acceleration (model space); legs / knees: the pose Euler rotations of the leg and
## knee joints (left, right); t: time; run_w: 0..1 running weight; turn: yaw rate.
func update(dt: float, lv: Vector3, acc: Vector3, leg_l: Vector3, leg_r: Vector3, knee_l: Vector3, knee_r: Vector3,
		t: float, run_w: float, turn: float) -> void:
	if count == 0:
		return
	var tgt := Vector2(clampf(-lv.x * 0.07 - acc.x * 0.008, -0.45, 0.45), clampf(-lv.z * 0.07 - acc.z * 0.008, -0.5, 0.5))
	_trail_v += ((tgt - _trail) * 60.0 - _trail_v * 7.0) * dt
	_trail += _trail_v * dt
	_trail = _trail.limit_length(0.6)
	var bell_t := clampf(-lv.y * 0.05 + absf(turn) * 0.04 + run_w * 0.05, -0.12, 0.45)
	_bell_v += ((bell_t - _bell) * 50.0 - _bell_v * 6.0) * dt
	_bell = clampf(_bell + _bell_v * dt, -0.2, 0.6)
	_leg_points(0, leg_l, knee_l, LEG_X)
	_leg_points(3, leg_r, knee_r, -LEG_X)
	for i in count:
		var o := _dir[i]
		var f := base_flare + _bell + (_trail.x * o.x + _trail.y * o.y) + sin(t * 13.0 + float(i) * 1.7) * 0.05 * run_w
		f = maxf(f, required_flare(i))
		flare[i] = clampf(f, min_flare, max_flare)
		side[i] = clampf(_trail.x * o.y - _trail.y * o.x, -max_side, max_side)


## Minimum flare of panel i so the current leg sample points stay inside the skirt (ignores points below
## the hem or beside the panel's reach).
func required_flare(i: int) -> float:
	var o := _dir[i]
	var need := -1.0
	for k in _pts.size():
		var p := _pts[k]
		var rho := p.x * o.x + p.z * o.y
		var out := rho + _rad[k] + MARGIN - radius
		if out <= 0.0:
			continue
		var h := y0 - p.y
		var reach := Vector2(rho - radius, h).length()
		if reach > length + _rad[k]:
			continue
		need = maxf(need, atan2(out, maxf(h, 0.001)))
	return need


## Current leg sample points of one leg (hips space): mid thigh, knee, mid shin.
func _leg_points(at: int, leg: Vector3, knee: Vector3, x: float) -> void:
	var origin := Vector3(x, LEG_Y, 0.0)
	var lb := Basis.from_euler(leg)
	var kb := lb * Basis.from_euler(knee)
	var k := origin + lb * Vector3(0, -THIGH, 0)
	_pts[at] = origin + lb * Vector3(0, -0.12, 0)
	_pts[at + 1] = k
	_pts[at + 2] = k + kb * Vector3(0, -0.12, 0)
	_rad[at] = THIGH_R
	_rad[at + 1] = THIGH_R
	_rad[at + 2] = SHIN_R


## Leg sample points of the last update (hips space) and their radii - for tests / debugging.
func leg_points() -> PackedVector3Array:
	return _pts


func leg_radii() -> PackedFloat32Array:
	return _rad
