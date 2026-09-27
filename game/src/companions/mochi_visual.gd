extends "res://src/companions/companion_visual.gd"
## MOCHI - a round puffball mushroom sprite: big red cap with cream spots, soft cream body,
## tiny stubby feet, huge shiny eyes and rosy cheeks. Moves by hopping with squash & stretch;
## the cap jiggles a beat behind the body.

const CAP := Color("e4665c")
const CAP_DARK := Color("c94f4a")
const SPOTS := Color("fff4e0")
const BODY := Color("f6e7cf")
const BODY_SHADE := Color("ead5b4")
const GILLS := Color("e9cfa8")
const MOUTH := Color("5a3440")

const SPOT_LAYOUT := [
	# [theta (from top, rad), phi (around, rad), radius]
	[0.22, 3.6, 0.075], [0.95, 0.35, 0.068], [1.05, 1.75, 0.058], [0.9, 2.9, 0.072],
	[1.0, 4.25, 0.062], [1.12, 5.35, 0.048], [0.55, 5.9, 0.042], [0.6, 2.2, 0.038], [0.62, 0.95, 0.034],
]

var cap_pivot: Node3D
var face: Node3D
var mouth: MeshInstance3D
var feet: Array = []
var nubs: Array = []
var _cap_wobble := 0.0
var _cap_vel := 0.0
var _prev_hop := 0.0


func _build() -> void:
	emote_height = 0.9
	gait_speed_ref = 4.6
	outline_width = 0.011
	head_height = 0.28
	head_body_factor = 0.85
	# Body: a soft, slightly wide cream puff.
	var b := Kit.sphere(0.225, omat(BODY, {"rim": 0.45}), 20, 28)
	Kit.add(body, b, Vector3(0, 0.215, 0), Vector3.ZERO, Vector3(1.08, 0.97, 1.02))
	# Tiny stubby feet.
	for side in [-1.0, 1.0]:
		var f := Kit.sphere(0.058, omat(BODY_SHADE), 10, 14)
		var fp := Node3D.new()
		body.add_child(fp)
		fp.position = Vector3(0.095 * side, 0.03, 0.06)
		Kit.add(fp, f, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.62, 1.35))
		feet.append(fp)
	# Little arm nubs (mostly tucked in; they pop out when happy/gathering).
	for side in [-1.0, 1.0]:
		var n := Kit.sphere(0.045, omat(BODY_SHADE), 8, 12)
		var np := Node3D.new()
		body.add_child(np)
		np.position = Vector3(0.225 * side, 0.15, 0.03)
		Kit.add(np, n, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.1, 0.9))
		nubs.append(np)
	# Face (eyes, cheeks, mouth) on the front of the body.
	face = Node3D.new()
	body.add_child(face)
	face.position = Vector3(0, 0.2, 0)
	make_eye(face, Vector3(-0.086, 0.0, 0.2), 0.066, -14.0)
	make_eye(face, Vector3(0.086, 0.0, 0.2), 0.066, 14.0)
	make_cheek(face, Vector3(-0.152, -0.058, 0.163), 0.037, -40.0)
	make_cheek(face, Vector3(0.152, -0.058, 0.163), 0.037, 40.0)
	mouth = Kit.sphere(0.02, Mat.toon(MOUTH, {"noise": 0.0, "rim": 0.0}), 8, 10)
	Kit.add(face, mouth, Vector3(0, -0.072, 0.218), Vector3.ZERO, Vector3(1.2, 0.55, 0.5))
	# Cap: a big red dome with gills underneath and cream spots.
	cap_pivot = Node3D.new()
	body.add_child(cap_pivot)
	cap_pivot.position = Vector3(0, 0.36, -0.01)
	var gills := Kit.cylinder(0.278, 0.2, 0.05, omat(GILLS), 24)
	Kit.add(cap_pivot, gills, Vector3(0, 0.035, 0))
	var dome := Kit.sphere(0.29, omat(CAP, {"rim": 0.5, "specular": 0.12}), 20, 28)
	Kit.add(cap_pivot, dome, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
	var spot_mat := Mat.toon(SPOTS, {"rim": 0.3, "noise": 0.03})
	for s in SPOT_LAYOUT:
		var th: float = s[0]
		var ph: float = s[1]
		var r: float = s[2]
		var p := Vector3(0.29 * sin(th) * sin(ph), 0.203 * cos(th), 0.29 * sin(th) * cos(ph))
		var n := Vector3(p.x / 0.0841, p.y / 0.0412, p.z / 0.0841).normalized()
		var spot := Kit.sphere(r, spot_mat, 10, 16)
		cap_pivot.add_child(spot)
		spot.position = Vector3(0, 0.06, 0) + p - n * 0.006
		spot.basis = _basis_from_up(n, 0.3)


## Basis whose local Y is `up` (scaled by y_scale, so spheres become flat discs on a surface).
static func _basis_from_up(up: Vector3, y_scale: float = 1.0) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up * y_scale, z)


## Mochi hops: bouncy arcs with squash on landing and stretch in the air.
func _gait(delta: float) -> void:
	var r := clampf(move_speed / gait_speed_ref, 0.0, 1.7)
	if r < 0.05:
		_phase = 0.0
		return
	_phase += delta * (7.5 + 5.0 * r)
	var s := sin(_phase)
	var air := absf(s)
	p_hop = air * (0.07 + 0.09 * minf(r, 1.2))
	# stretch while rising, squash near the ground
	var ground := 1.0 - air
	p_squash *= 1.0 + (air - 0.5) * 0.16 * minf(r + 0.3, 1.0) - pow(ground, 6.0) * 0.12
	p_lean += 0.12 * minf(r, 1.0)
	p_step = cos(_phase)
	p_step_lift = air


func _mood_pose(delta: float) -> void:
	super(delta)
	if mood == "scared":
		p_squash *= 0.9
		p_arm_l = 0.4
		p_arm_r = 0.4


func _apply_pose(delta: float) -> void:
	_apply_common(delta)
	# Cap jiggle: a damped spring driven by vertical acceleration of the hop.
	var hop_v := (p_hop - _prev_hop) / maxf(delta, 0.001)
	_prev_hop = p_hop
	_cap_vel += (-_cap_wobble * 160.0 - _cap_vel * 9.0 - hop_v * 2.2) * delta
	_cap_wobble = clampf(_cap_wobble + _cap_vel * delta, -0.35, 0.35)
	cap_pivot.rotation = Vector3(_cap_wobble * 0.5 + p_shake * 0.1, p_shake * 0.2, sin(_t * 1.7) * 0.02 + p_roll * 0.3)
	cap_pivot.scale = Vector3(1.0 + _cap_wobble * 0.15, 1.0 - _cap_wobble * 0.3, 1.0 + _cap_wobble * 0.15)
	# Feet: little alternate shuffles, tucked when hopping.
	for i in feet.size():
		var f: Node3D = feet[i]
		var side := -1.0 if i == 0 else 1.0
		var lift := p_step_lift * 0.03
		f.position = Vector3(0.095 * side, 0.03 + lift * (0.6 + 0.4 * side * p_step), 0.06 + p_step * side * 0.015)
	# Arm nubs pop out with excitement.
	for i in nubs.size():
		var n: Node3D = nubs[i]
		var side := -1.0 if i == 0 else 1.0
		var raise := p_arm_l if i == 0 else p_arm_r
		n.position = Vector3((0.215 + 0.03 * absf(raise)) * side, 0.15 + 0.07 * raise, 0.03 + 0.02 * raise)
		n.rotation = Vector3(0, 0, side * raise * 0.6)
	mouth.scale = Vector3(1.2 + p_mouth * 0.4, 0.55 + p_mouth * 1.1, 0.5)


func _on_action_started(a: String) -> void:
	if a == "happy" or a == "celebrate":
		_cap_vel -= 3.0
