extends "res://src/companions/companion_visual.gd"
## PEBBLE - a small chunky stone creature: grey rounded body with a moss tuft and a sprout,
## expressive thick eyebrows of darker stone, a determined little face and stubby arms.
## Waddles side to side and stomps; gets dizzy (orbiting stars) after bouncing off enemies.

const STONE := Color("9a948a")
const STONE_LIGHT := Color("b3ada2")
const STONE_DARK := Color("6f695f")
const BROW := Color("57524b")
const MOSS := Color("7dbb5b")
const MOSS_DARK := Color("5f9a45")
const SPROUT := Color("9ccf62")
const MOUTH := Color("3b2f35")
const CHEEK_STONE := Color("d7a19b")
const BODY_R := 0.26
const BODY_SEED := 11
const BODY_LUMP := 0.08
const BODY_SQUASH := 0.92
const BODY_CENTER := Vector3(0, 0.27, 0)

var face: Node3D
var _brow_rest: Array = []
var brows: Array = []
var arms: Array = []
var feet: Array = []
var mouth: MeshInstance3D
var moss_pivot: Node3D
var stars_pivot: Node3D
var _stars_t := 0.0
var _stomp_prev := 0.0


func _build() -> void:
	emote_height = 0.92
	gait_speed_ref = 4.2
	outline_width = 0.012
	head_height = 0.32
	head_body_factor = 0.7
	# Chunky rounded stone body (seeded lumps keep the silhouette hand-made).
	var b := Kit.blob(BODY_R, omat(STONE, {"rim": 0.3, "noise": 0.12, "noise_scale": 2.2}), BODY_SEED, BODY_LUMP, BODY_SQUASH, 3)
	Kit.add(body, b, BODY_CENTER)
	# Moss tuft with a little two-leaf sprout.
	moss_pivot = Node3D.new()
	body.add_child(moss_pivot)
	moss_pivot.position = Vector3(0.02, 0.495, -0.03)
	var moss := Kit.blob(0.13, omat(MOSS, {"noise": 0.15, "noise_scale": 3.0}), 5, 0.3, 0.42, 2)
	Kit.add(moss_pivot, moss, Vector3.ZERO)
	var moss2 := Kit.blob(0.075, omat(MOSS_DARK, {"noise": 0.15}), 8, 0.3, 0.5, 2)
	Kit.add(moss_pivot, moss2, Vector3(-0.09, -0.02, 0.06))
	var stem := Kit.cylinder(0.009, 0.012, 0.09, Mat.toon(MOSS_DARK), 6)
	Kit.add(moss_pivot, stem, Vector3(0.02, 0.07, 0.0), Vector3(0, 0, -8))
	for side in [-1.0, 1.0]:
		var leaf := Kit.sphere(0.035, omat(SPROUT), 8, 10)
		Kit.add(moss_pivot, leaf, Vector3(0.02 + 0.035 * side, 0.12, 0.0), Vector3(0, 0, -35.0 * side), Vector3(1.4, 0.35, 0.8))
	# Face: every feature sits exactly on the lumpy surface (see _surface()).
	face = Node3D.new()
	body.add_child(face)
	for side in [-1.0, 1.0]:
		var ep := _surface(Vector3(0.3 * side, 0.1, 0.95))
		make_eye(face, ep - Vector3(0, 0, 0.004), 0.05, 13.0 * side)
		var cp := _surface(Vector3(0.52 * side, -0.12, 0.84))
		make_cheek(face, cp, 0.03, 32.0 * side, CHEEK_STONE)
		var bp := Node3D.new()
		face.add_child(bp)
		bp.position = _surface(Vector3(0.3 * side, 0.36, 0.88)) + Vector3(0, 0, 0.006)
		var brow := Kit.capsule(0.021, 0.1, omat(BROW, {"noise": 0.1}))
		Kit.add(bp, brow, Vector3.ZERO, Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.85))
		brows.append(bp)
		_brow_rest.append(bp.position)
	mouth = Kit.capsule(0.011, 0.05, Mat.toon(MOUTH, {"noise": 0.0, "rim": 0.0}))
	Kit.add(face, mouth, _surface(Vector3(0.0, -0.2, 1.0)) + Vector3(0, 0, 0.002), Vector3(0, 0, 90))
	# Stubby arms.
	for side in [-1.0, 1.0]:
		var ap := Node3D.new()
		body.add_child(ap)
		ap.position = Vector3(0.235 * side, 0.26, 0.02)
		var arm := Kit.blob(0.07, omat(STONE_DARK, {"noise": 0.1}), 21 + int(side), 0.12, 1.0, 2)
		Kit.add(ap, arm, Vector3(0.03 * side, -0.06, 0.0), Vector3.ZERO, Vector3(0.85, 1.15, 0.85))
		arms.append(ap)
	# Stubby feet.
	for side in [-1.0, 1.0]:
		var fp := Node3D.new()
		body.add_child(fp)
		fp.position = Vector3(0.11 * side, 0.035, 0.03)
		var foot := Kit.blob(0.075, omat(STONE_DARK, {"noise": 0.1}), 31 + int(side), 0.1, 0.6, 2)
		Kit.add(fp, foot, Vector3.ZERO, Vector3.ZERO, Vector3(1.05, 1.0, 1.3))
		feet.append(fp)
	# Dizzy stars (hidden until needed).
	stars_pivot = Node3D.new()
	add_child(stars_pivot)
	stars_pivot.position = Vector3(0, 0.72, 0)
	for i in 3:
		var s := Sprite3D.new()
		s.texture = Icons.icon("star")
		s.pixel_size = 0.0016
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.render_priority = 9
		stars_pivot.add_child(s)
	stars_pivot.visible = false


## Point on the body blob's surface in direction `dir` (body space), using the same seeded noise
## as Kit.blob_mesh so features never sink into (or float off) the lumpy stone.
static func _surface(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var noise := FastNoiseLite.new()
	noise.seed = BODY_SEED
	noise.frequency = 1.3 / maxf(BODY_R, 0.05)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var n := noise.get_noise_3dv(d * BODY_R)
	var r := BODY_R * (1.0 + n * BODY_LUMP)
	return BODY_CENTER + Vector3(d.x * r, d.y * r * BODY_SQUASH, d.z * r)


## Pebble waddles: side-to-side roll with alternating foot lifts and a little stomp.
func _gait(delta: float) -> void:
	var r := clampf(move_speed / gait_speed_ref, 0.0, 1.7)
	if r < 0.05:
		_phase = 0.0
		return
	_phase += delta * (6.5 + 6.0 * r)
	var s := sin(_phase)
	p_roll += s * (0.1 + 0.06 * minf(r, 1.0))
	p_hop = absf(cos(_phase)) * 0.035 * minf(r + 0.3, 1.2)
	p_lean += 0.1 * minf(r, 1.0)
	p_step = s
	p_step_lift = 1.0
	p_arm_l = -s * 0.5 * minf(r + 0.2, 1.0)
	p_arm_r = s * 0.5 * minf(r + 0.2, 1.0)
	p_brow = -0.5 * minf(r, 1.0)     # determined when marching


func _mood_pose(delta: float) -> void:
	super(delta)
	if mood == "pinned":
		# Squashed under the boulder: only the feet and arms kick about.
		p_squash *= 0.8
		var k := sin(_t * 9.0)
		p_step = k
		p_step_lift = 1.3
		p_arm_l = 0.4 + 0.4 * sin(_t * 7.0)
		p_arm_r = 0.4 + 0.4 * sin(_t * 7.0 + 1.3)
		p_brow = -1.0
	elif mood == "scared":
		p_brow = 1.0


func _action_pose(a: String, k: float) -> void:
	super(a, k)
	var env := sin(k * PI)
	match a:
		"headbutt":
			p_arm_l = -0.6 * env
			p_arm_r = -0.6 * env
		"salute":
			p_arm_l = 0.0
			p_mouth = 0.2
		"dizzy":
			p_arm_l = sin(_t * 5.0) * 0.4
			p_arm_r = -sin(_t * 5.0) * 0.4
		"stomp":
			p_step = 1.0
			p_step_lift = 2.5 * env


func _apply_pose(delta: float) -> void:
	_apply_common(delta)
	for i in feet.size():
		var f: Node3D = feet[i]
		var side := -1.0 if i == 0 else 1.0
		var lift := maxf(0.0, p_step * -side) * 0.045 * p_step_lift
		f.position = Vector3(0.11 * side, 0.035 + lift, 0.03 + lift * 0.4)
	for i in arms.size():
		var ap: Node3D = arms[i]
		var side := -1.0 if i == 0 else 1.0
		var raise := p_arm_l if i == 0 else p_arm_r
		ap.rotation = Vector3(-raise * 0.9, 0.0, side * (0.15 + maxf(raise, 0.0) * 1.3))
	for i in brows.size():
		var bp: Node3D = brows[i]
		var side := -1.0 if i == 0 else 1.0
		# p_brow < 0: furrowed (inner ends down), > 0: raised & worried (inner ends up).
		# Resting pose is slightly determined.
		var inner_up := -0.2 + p_brow * 0.42
		bp.rotation = Vector3(0, 0, inner_up * -side)
		var rest: Vector3 = _brow_rest[i]
		bp.position = rest + Vector3(0, p_brow * 0.018 - (1.0 - clampf(p_eye, 0.0, 1.0)) * 0.012, 0)
	mouth.scale = Vector3(1.0 + p_mouth * 1.8, 1.0 + p_mouth * 0.6, 1.0 + p_mouth * 0.4)
	moss_pivot.rotation = Vector3(sin(_t * 2.1) * 0.05 - p_lean * 0.2, 0.0, sin(_t * 1.6) * 0.06 - p_roll * 0.5)
	# Dizzy stars orbit the head.
	var dizzy := get_action() == "dizzy"
	stars_pivot.visible = dizzy
	if dizzy:
		_stars_t += delta * 5.0
		var kids := stars_pivot.get_children()
		for i in kids.size():
			var s: Node3D = kids[i]
			var a := _stars_t + TAU * float(i) / float(kids.size())
			s.position = Vector3(cos(a) * 0.22, sin(a * 2.0) * 0.03, sin(a) * 0.22)


func _on_action_fire(a: String) -> void:
	super(a)
	match a:
		"headbutt", "stomp":
			Fx.chips(_fx_parent(), global_position + global_basis.z * 0.3 + Vector3.UP * 0.2, STONE, 5)
