extends Node3D
## A stylised dark figure the horror director shows for a heartbeat: standing in a far doorway
## (glimpse) or crossing a ceiling (stalker-pass fallback). Two variants:
##   "spider" - the Weaver: low, wide, eight jointed legs, a cluster of small ember eyes.
##   "shade"  - the Hollow Shade (arachnophobia-safe): a tall hooded figure with long thin arms.
## Dark, softly rim-lit (it reads against lantern light), with subtle glowing eyes. It fades in,
## holds, slips sideways out of view and frees itself. Always faces the player.
##
##   var s = preload("res://src/horror/silhouette.gd").new()
##   s.setup({"variant": "shade", "mode": "glimpse", "duration": 1.0, "target": player, "slip_dir": Vector3.RIGHT})
##   area.add_child(s)
##   s.global_position = doorway_pos
## Modes: "static" (stays visible, used by previews), "glimpse", "cross" ({"to": Vector3, "ceiling": true}).
## cancel() fades it out quickly (director cancels on pause / safe zone / death).

signal finished

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const BODY_COLOR := Color(0.085, 0.07, 0.105)      # violet-black: darker than any dungeon surface
const HOLLOW_COLOR := Color(0.01, 0.006, 0.016)     # inside the hood
const SHADE_EYES := Color("d6ecff")                 # cold, pale (the shade)
const SHADE_HEIGHT := 2.15

var variant: String = ""                # "" = pick from the arachnophobia setting
var mode: String = "static"
var duration: float = 1.0               # hold time (glimpse) or travel time (cross)
var target: Node3D = null               # faces this (the player)
var face_point: Vector3 = Vector3.ZERO
var has_face_point: bool = false
var slip_dir: Vector3 = Vector3.RIGHT
var slip_distance: float = 1.4
var cross_to: Vector3 = Vector3.ZERO
var on_ceiling: bool = false
var fade_in_time: float = 0.3

var _root: Node3D
var _body_mat: StandardMaterial3D
var _hollow_mat: StandardMaterial3D
var _eyes: Array[Node3D] = []
var _eye_scale: Array[float] = []
var _sway_parts: Array[Node3D] = []
var _alpha: float = 0.0
var _tween: Tween
var _t: float = 0.0
var _phase: float = 0.0
var _done: bool = false
var _cancelled: bool = false
var _cross_from: Vector3 = Vector3.ZERO


func setup(params: Dictionary) -> void:
	variant = String(params.get("variant", variant))
	mode = String(params.get("mode", mode))
	duration = float(params.get("duration", duration))
	slip_distance = float(params.get("slip_distance", slip_distance))
	on_ceiling = bool(params.get("ceiling", on_ceiling))
	var tg: Variant = params.get("target", null)
	if tg is Node3D:
		target = tg
	var fp: Variant = params.get("face", null)
	if fp is Vector3:
		face_point = fp
		has_face_point = true
	var sd: Variant = params.get("slip_dir", null)
	if sd is Vector3 and (sd as Vector3).length_squared() > 0.0001:
		slip_dir = (sd as Vector3).normalized()
	var to: Variant = params.get("to", null)
	if to is Vector3:
		cross_to = to


func _ready() -> void:
	if variant != "spider" and variant != "shade":
		variant = "shade" if bool(Settings.get_value("arachnophobia")) else "spider"
	_phase = float(get_instance_id() % 1000) * 0.37
	_build()
	match mode:
		"glimpse":
			_set_alpha(0.0)
			_start_glimpse()
		"cross":
			_set_alpha(0.0)
			_start_cross.call_deferred()   # after the caller has placed us (global_position)
		_:
			_set_alpha(1.0)
	_face_target(true)


func _process(delta: float) -> void:
	_t += delta
	# Subtle life: a slow breath and sway, never big enough to look cartoonish.
	var breath := sin(_t * 1.7 + _phase)
	if variant == "shade":
		_root.rotation.z = deg_to_rad(1.6) * sin(_t * 0.9 + _phase)
		for p in _sway_parts:
			p.rotation.x = deg_to_rad(3.0) * breath
	else:
		for p in _sway_parts:
			p.scale = Vector3.ONE * (1.0 + 0.025 * breath)
	if mode != "cross":
		_face_target(false)


## Quick fade and free (director cancel: pause, safe zone, death, authored moments).
func cancel() -> void:
	if _done or not is_inside_tree():
		return
	_cancelled = true                   # a crossing whose deferred start is still queued must not begin
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _alpha, 0.0, 0.2)
	_tween.tween_callback(_finish)


func is_finished() -> bool:
	return _done


# --- Animation ----------------------------------------------------------------------------

func _start_glimpse() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_alpha, 0.0, 1.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(maxf(duration, 0.2))
	_tween.tween_callback(_slip_away)


func _slip_away() -> void:
	_kill_tween()
	var dest := global_position + slip_dir * slip_distance
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "global_position", dest, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_method(_set_alpha, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_finish)


func _start_cross() -> void:
	if not is_inside_tree() or _done or _cancelled:
		return
	_kill_tween()
	_cross_from = global_position
	var travel := cross_to - _cross_from
	travel.y = 0.0
	if travel.length_squared() > 0.0001:
		global_rotation = Vector3(0.0, atan2(travel.x, travel.z), 0.0)
	var t := maxf(duration, 0.4)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "global_position", cross_to, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_alpha, 0.0, 1.0, minf(0.3, t * 0.25))
	_tween.tween_method(_set_alpha, 1.0, 0.0, minf(0.4, t * 0.3)).set_delay(t - minf(0.4, t * 0.3))
	_tween.chain().tween_callback(_finish)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_alpha(a: float) -> void:
	_alpha = clampf(a, 0.0, 1.0)
	if _body_mat != null:
		_body_mat.albedo_color.a = _alpha
	if _hollow_mat != null:
		_hollow_mat.albedo_color.a = _alpha
	# Eyes open after the body has half appeared and close first.
	var e := smoothstep(0.45, 1.0, _alpha)
	for i in _eyes.size():
		var s: float = _eye_scale[i] * e
		_eyes[i].scale = Vector3.ONE * maxf(s, 0.001)
		_eyes[i].visible = s > 0.01


func _face_target(_instant: bool) -> void:
	var look := Vector3.ZERO
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		look = target.global_position
	elif has_face_point:
		look = face_point
	else:
		return
	if not is_inside_tree():
		return
	var to := look - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	global_rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)


# --- Construction ---------------------------------------------------------------------------

func _build() -> void:
	_body_mat = Mat.transparent(BODY_COLOR, false, false).duplicate()
	_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_body_mat.roughness = 1.0
	_body_mat.metallic_specular = 0.1
	_body_mat.rim_enabled = true
	_body_mat.rim = 0.55
	_body_mat.rim_tint = 0.35
	_hollow_mat = _body_mat.duplicate()
	_hollow_mat.albedo_color = HOLLOW_COLOR
	_hollow_mat.rim_enabled = false
	_root = Node3D.new()
	_root.name = "Figure"
	add_child(_root)
	if variant == "spider":
		_build_spider()
	else:
		_build_shade()
	for mi in _root.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if on_ceiling:
		if variant == "spider":
			_root.rotation.z = PI            # clings upside-down, feet on the ceiling
		else:
			_root.position.y = -SHADE_HEIGHT # drifts just below the ceiling


func _build_shade() -> void:
	var body := Node3D.new()
	_root.add_child(body)
	_sway_parts.append(body)
	# Robe: a soft tapered column; the hem frays into a few hanging tatters that just brush the floor.
	Kit.add(body, Kit.cylinder(0.22, 0.44, 1.2, _body_mat, 14), Vector3(0, 0.78, 0))
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.3
		var r := 0.36 + 0.03 * sin(float(i) * 2.1)
		var h := 0.24 + 0.06 * float(i % 3)
		Kit.add(body, Kit.cone(0.085, h, _body_mat, 6), Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(180, 0, 0))
	# Hunched shoulders and a deep hood whose tip droops down the back.
	Kit.add(body, Kit.blob(0.36, _body_mat, 5, 0.16, 1.05), Vector3(0, 1.42, -0.04))
	var head := Node3D.new()
	body.add_child(head)
	head.position = Vector3(0, 1.8, 0.1)
	head.rotation_degrees = Vector3(16, 0, 0)
	Kit.add(head, Kit.blob(0.28, _body_mat, 9, 0.08, 1.12), Vector3.ZERO)
	Kit.add(head, Kit.cone(0.15, 0.42, _body_mat, 10), Vector3(0, 0.1, -0.3), Vector3(-112, 0, 0))
	# The hood opening: a void in which only the eyes show.
	Kit.add(head, Kit.sphere(0.19, _hollow_mat, 12, 16), Vector3(0, 0.0, 0.2), Vector3.ZERO, Vector3(0.86, 1.06, 0.55))
	for sx in [-1.0, 1.0]:
		_add_eye(head, Vector3(0.058 * sx, 0.025, 0.3), 0.026, Mat.glow(SHADE_EYES, 2.4))
	# Long thin arms that hang too low, with long fingers.
	for sx in [-1.0, 1.0]:
		var shoulder := Vector3(0.33 * sx, 1.46, 0.04)
		var elbow := Vector3(0.42 * sx, 0.98, 0.12)
		var wrist := Vector3(0.4 * sx, 0.52, 0.16)
		_limb(body, shoulder, elbow, 0.065)
		_limb(body, elbow, wrist, 0.055)
		for f in 3:
			var tip := wrist + Vector3((0.05 * float(f - 1)) + 0.02 * sx, -0.3 - 0.04 * float(f % 2), 0.05 * float(f - 1))
			_limb(body, wrist, tip, 0.018)


func _build_spider() -> void:
	var body := Node3D.new()
	_root.add_child(body)
	var abdomen := Kit.blob(0.52, _body_mat, 21, 0.1, 0.82)
	Kit.add(body, abdomen, Vector3(0, 0.92, -0.62))
	_sway_parts.append(abdomen)
	Kit.add(body, Kit.blob(0.2, _body_mat, 23, 0.1, 0.9), Vector3(0, 0.78, -0.12))
	Kit.add(body, Kit.blob(0.32, _body_mat, 22, 0.1, 0.78), Vector3(0, 0.74, 0.16))
	# Eight jointed legs: up to a high knee, down to an ankle, then a thin foot that touches the floor.
	var zs := [0.36, 0.2, 0.04, -0.14]
	var spread := [0.75, 0.3, -0.25, -0.7]
	for sx in [-1.0, 1.0]:
		for i in 4:
			var hip := Vector3(0.2 * sx, 0.74, float(zs[i]))
			var knee := Vector3(0.74 * sx, 1.34 - 0.06 * float(i), float(zs[i]) + float(spread[i]) * 0.5)
			var ankle := Vector3((1.12 + 0.05 * float(i % 2)) * sx, 0.3, float(zs[i]) + float(spread[i]) * 0.98)
			var tip := Vector3((1.3 + 0.05 * float(i % 2)) * sx, 0.0, float(zs[i]) + float(spread[i]) * 1.2)
			_limb(body, hip, knee, 0.052)
			_limb(body, knee, ankle, 0.04)
			_limb(body, ankle, tip, 0.024)
			Kit.add(body, Kit.sphere(0.058, _body_mat, 6, 8), knee)
	# Pedipalps
	for sx in [-1.0, 1.0]:
		_limb(body, Vector3(0.1 * sx, 0.66, 0.4), Vector3(0.16 * sx, 0.42, 0.56), 0.035)
	# Eye cluster: two larger, four smaller embers.
	var ember := Mat.glow(Palette.THREAT_EYES, 2.2)
	for sx in [-1.0, 1.0]:
		_add_eye(body, Vector3(0.075 * sx, 0.86, 0.42), 0.042, ember)
		_add_eye(body, Vector3(0.155 * sx, 0.9, 0.36), 0.026, ember)
		_add_eye(body, Vector3(0.045 * sx, 0.95, 0.4), 0.022, ember)


func _add_eye(parent: Node3D, pos: Vector3, radius: float, mat: Material) -> void:
	var eye := Kit.sphere(radius, mat, 8, 10)
	Kit.add(parent, eye, pos)
	_eyes.append(eye)
	_eye_scale.append(1.0)


## A capsule between two points (legs, arms, fingers).
func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float) -> void:
	var v := to - from
	var length := v.length()
	if length < 0.001:
		return
	var mi := Kit.capsule(radius, length + radius * 2.0, _body_mat)
	parent.add_child(mi)
	var dir := v / length
	var b := Basis.IDENTITY
	if absf(dir.dot(Vector3.UP)) < 0.9999:
		b = Basis(Quaternion(Vector3.UP, dir))
	mi.transform = Transform3D(b, from + v * 0.5)
