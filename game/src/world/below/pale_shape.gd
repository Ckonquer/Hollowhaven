extends Node3D
## A pale, unsettling shape glimpsed at a distance (authored moments only; it never attacks).
## variant "spider": long-legged pale weaver silhouette.   variant "shade" (arachnophobia mode):
## a tall, hunched, faceless drifting figure. Readable from ~25 m: pale, slightly self-lit, no light cast.
##   var s = PaleShape.new(); s.setup({"variant": "shade"}); add_child(s)
##   await s.cross(from, to, 2.2)            walks/drifts across then vanishes
##   s.cling(pos)  /  await s.recoil(to, 0.6) ceiling cling + retreat into a crack

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const PALE := Color("e6e1e8")
const PALE_DARK := Color("b9b0bf")

var variant: String = "spider"
var moving: bool = false
var upside_down: bool = false

var _rig: Node3D
var _legs: Array = []          # [pivot, phase, side]
var _arms: Array = []
var _t: float = 0.0
var _tween: Tween


func setup(p: Dictionary) -> void:
	variant = String(p.get("variant", variant))


func _ready() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	if variant == "shade":
		_build_shade()
	else:
		_build_spider()


func _body_mat(c: Color = PALE) -> Material:
	return Mat.outlined(Mat.toon(c, {"rim": 0.9, "emission": c, "emission_energy": 0.18, "noise": 0.05}), 0.02, Color(0.1, 0.08, 0.12))


func _build_spider() -> void:
	var mat := _body_mat()
	var dark := _body_mat(PALE_DARK)
	Kit.add(_rig, Kit.blob(0.5, mat, 12, 0.12, 0.8), Vector3(0, 0.75, 0.55), Vector3.ZERO, Vector3(0.95, 0.9, 1.25))
	Kit.add(_rig, Kit.blob(0.3, mat, 13, 0.1, 0.85), Vector3(0, 0.62, -0.2))
	Kit.add(_rig, Kit.sphere(0.16, dark, 8, 10), Vector3(0, 0.6, -0.48))
	# Tiny cold eye glints (no light cast)
	for sx in [-1.0, 1.0]:
		Kit.add(_rig, Kit.sphere(0.035, Mat.glow(Color("dfe8ff"), 1.4), 4, 6), Vector3(sx * 0.07, 0.66, -0.6))
	var ul := 0.95        # upper segment: rises outward at 0.7 rad
	var ll := 1.35        # lower segment: drops to the floor at -1.25 rad
	var knee_pos := Vector3(ul * cos(0.7), ul * sin(0.7), 0.0)
	for side in [-1.0, 1.0]:
		for i in 4:
			var spread := 0.9 - float(i) * 0.45
			var pivot := Node3D.new()
			_rig.add_child(pivot)
			pivot.position = Vector3(side * 0.18, 0.64, -0.3 + float(i) * 0.16)
			# local +X points outward: forward-most leg first
			pivot.rotation.y = spread if side > 0.0 else PI - spread
			var upper := Node3D.new()
			pivot.add_child(upper)
			var up_seg := Kit.cylinder(0.035, 0.045, ul, dark, 6)
			upper.add_child(up_seg)
			up_seg.position = knee_pos * 0.5
			up_seg.rotation.z = 0.7 - PI * 0.5
			var knee := Node3D.new()
			upper.add_child(knee)
			knee.position = knee_pos
			var low := Kit.cylinder(0.012, 0.035, ll, dark, 6)
			knee.add_child(low)
			low.position = Vector3(ll * 0.5 * cos(-1.25), ll * 0.5 * sin(-1.25), 0)
			low.rotation.z = -1.25 - PI * 0.5
			_legs.append([pivot, float(i) * 1.6 + (0.0 if side > 0.0 else 0.8), side])


func _build_shade() -> void:
	var mat := _body_mat()
	var dark := _body_mat(PALE_DARK)
	var torso := Node3D.new()
	_rig.add_child(torso)
	torso.position = Vector3(0, 0.15, 0)
	# Ragged cloak widening toward the floor, with a torn hem
	Kit.add(torso, Kit.cylinder(0.3, 0.62, 1.35, mat, 10), Vector3(0, 0.72, 0.05))
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.2
		var len := 0.35 + 0.25 * absf(sin(float(i) * 2.3))
		Kit.add(torso, Kit.cone(0.13, len, mat, 5), Vector3(cos(a) * 0.52, 0.05 - len * 0.2, sin(a) * 0.52 + 0.05), Vector3(180, 0, 0))
	# Hunched shoulders and back, bent forward
	var upper := Node3D.new()
	torso.add_child(upper)
	upper.position = Vector3(0, 1.35, 0.05)
	upper.rotation_degrees.x = 24.0
	Kit.add(upper, Kit.blob(0.44, mat, 21, 0.14, 1.0), Vector3(0, 0.25, 0.05), Vector3.ZERO, Vector3(1.25, 0.95, 0.95))
	# Hood reaching forward, a hollow darkness where a face should be
	var head := Node3D.new()
	upper.add_child(head)
	head.position = Vector3(0, 0.62, -0.28)
	head.rotation_degrees.x = 18.0
	Kit.add(head, Kit.blob(0.3, mat, 22, 0.12, 1.1), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.05, 1.2))
	Kit.add(head, Kit.cone(0.16, 0.34, mat, 6), Vector3(0, 0.26, 0.2), Vector3(-40, 0, 0))
	Kit.add(head, Kit.sphere(0.2, Mat.toon(Color(0.04, 0.035, 0.06), {"rim": 0.0}), 8, 10), Vector3(0, -0.06, -0.2), Vector3.ZERO, Vector3(1.0, 1.15, 0.7))
	for sx in [-1.0, 1.0]:
		Kit.add(head, Kit.sphere(0.022, Mat.glow(Color("dfe8ff"), 1.3), 4, 6), Vector3(sx * 0.065, -0.02, -0.33))
		# Long thin arms hanging from the shoulders, fingers like drips
		var arm := Node3D.new()
		upper.add_child(arm)
		arm.position = Vector3(sx * 0.46, 0.35, -0.12)
		Kit.add(arm, Kit.cylinder(0.035, 0.06, 1.25, dark, 6), Vector3(0, -0.62, 0))
		for f in 3:
			Kit.add(arm, Kit.cone(0.025, 0.22, dark, 5), Vector3((float(f) - 1.0) * 0.04, -1.32, 0), Vector3(180, 0, (float(f) - 1.0) * 10.0))
		arm.rotation.z = sx * 0.1
		_arms.append(arm)


func _process(delta: float) -> void:
	_t += delta
	var speed := 9.0 if moving else 1.2
	if variant == "spider":
		for l in _legs:
			var pivot: Node3D = l[0]
			var ph: float = l[1]
			var upper: Node3D = pivot.get_child(0)
			upper.rotation.z = sin(_t * speed + ph) * (0.28 if moving else 0.04)
			upper.rotation.y = cos(_t * speed + ph) * (0.22 if moving else 0.02)
		_rig.position.y = sin(_t * speed * 2.0) * (0.03 if moving else 0.005)
	else:
		_rig.position.y = 0.15 + sin(_t * 1.7) * 0.06
		_rig.rotation.z = sin(_t * 1.1) * 0.04
		for i in _arms.size():
			var arm: Node3D = _arms[i]
			arm.rotation.x = sin(_t * 1.9 + float(i)) * 0.12 + (0.25 if moving else 0.0)


## Walk / drift from `from` to `to` over `seconds`, then vanish (queue_free). Awaitable.
func cross(from: Vector3, to: Vector3, seconds: float, linear: bool = false) -> void:
	global_position = from
	_face(to - from)
	moving = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var tw := _tween.tween_property(self, "global_position", to, seconds)
	if linear:
		tw.set_trans(Tween.TRANS_LINEAR)
	else:
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	moving = false
	queue_free()


## Cling to a ceiling point (upside down), idle.
func cling(pos: Vector3, facing: Vector3 = Vector3.FORWARD) -> void:
	upside_down = true
	global_position = pos
	_face(facing)
	_rig.rotation.z = PI if variant == "spider" else 0.0
	if variant == "shade":
		# hangs head-down from the ceiling like a draped sheet
		_rig.rotation.x = PI
		_rig.position = Vector3(0, 0.0, 0)


## Scurry / fold away to `to` and vanish. Awaitable.
func recoil(to: Vector3, seconds: float) -> void:
	moving = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "global_position", to, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "scale", Vector3(0.5, 0.2, 0.5), seconds).set_delay(seconds * 0.4)
	await _tween.finished
	queue_free()


func _face(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	rotation.y = atan2(-flat.x, -flat.z)
