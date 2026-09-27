extends Node3D
## Third-person camera rig for Krystal. Top-level node that follows its target with smoothing.
##   yaw -> pitch -> (SpringArm3D probe) ; Camera3D placed at the smoothed arm length.
## Mouse orbit only while the mouse is captured (Game manages capture). Pitch is clamped, zoom is
## 2.5..8 m (wheel), FOV/sensitivity/invert/distance come from Settings and update live.
## Walls: a SpringArm3D (world|structure) finds obstructions; the camera pulls in quickly and eases
## back out. Shake comes only from Events.camera_shake, scaled to zero by "reduce_shake".
## The rig never moves the camera by itself (no auto-recentering); only teleports snap it.

const PITCH_MIN := -1.1345          # -65 deg (looking down)
const PITCH_MAX := 0.6109           # +35 deg (looking up)
const DEFAULT_PITCH := -0.3
const ZOOM_MIN := 2.5
const ZOOM_MAX := 8.0
const ZOOM_STEP := 0.55
const TARGET_HEIGHT := 1.38
const SHOULDER := 0.36
const BASE_SENS := 0.0045           # radians per pixel at sensitivity 1.0
const MAX_SHAKE := 0.6
const HIDE_DIST := 1.0              # camera closer than this to the head hides the avatar (her head would fill the view)
const SHOW_DIST := 1.15             # ...and she reappears beyond this (hysteresis: no flicker at the threshold)
const COLLISION_MASK := 1 | 32
const SIDE_PAD := 0.12              # extra clearance (on top of the 0.16 m probe sphere) between the shifted arm and a wall

var target: Node3D = null
var yaw: float = 0.0
var pitch: float = DEFAULT_PITCH
var zoom_target: float = 5.0
var camera: Camera3D
var input_enabled: bool = true      # false = ignore mouse/zoom (e.g. player input disabled)

var _yaw_node: Node3D
var _pitch_node: Node3D
var _spring: SpringArm3D
var _zoom: float = 5.0
var _arm_len: float = 5.0
var _sens: float = 0.5
var _invert: bool = false
var _reduce_shake: bool = false
var _base_fov: float = 70.0
var _fov_kick: float = 0.0
var _trauma: float = 0.0
var _trauma_decay: float = 1.0
var _shake_t: float = 0.0
var _avatar_hidden: bool = false
var _snap_next: bool = true
var _shoulder: float = SHOULDER
var _side_q := PhysicsShapeQueryParameters3D.new()
var _arm_q := PhysicsShapeQueryParameters3D.new()
var _snap_physics_frame: int = 0


func _init() -> void:
	top_level = true
	name = "CameraRig"
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_yaw_node.add_child(_pitch_node)
	_spring = SpringArm3D.new()
	_spring.name = "SpringArm"
	_spring.collision_mask = COLLISION_MASK
	_spring.margin = 0.12
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_spring.shape = probe
	var side := SphereShape3D.new()
	side.radius = 0.16
	_side_q.shape = side
	_side_q.collision_mask = COLLISION_MASK
	_side_q.collide_with_areas = false
	_side_q.collide_with_bodies = true
	_arm_q.shape = probe
	_arm_q.collision_mask = COLLISION_MASK
	_arm_q.collide_with_areas = false
	_arm_q.collide_with_bodies = true
	_spring.spring_length = _zoom
	_pitch_node.add_child(_spring)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.05
	camera.far = 600.0
	_pitch_node.add_child(camera)


func _ready() -> void:
	_read_settings()
	zoom_target = clampf(float(Settings.get_value("camera_distance")), ZOOM_MIN, ZOOM_MAX)
	_zoom = zoom_target
	_arm_len = _zoom
	camera.fov = _base_fov
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	if not Events.camera_shake.is_connected(_on_camera_shake):
		Events.camera_shake.connect(_on_camera_shake)
	camera.make_current()
	_apply_rotation()


func setup(p_target: Node3D) -> void:
	target = p_target


func get_camera() -> Camera3D:
	return camera


## Places the rig behind the target immediately (spawn / teleport / recovery).
func snap(p_yaw: float, reset_pitch: bool = true) -> void:
	yaw = p_yaw
	if reset_pitch:
		pitch = DEFAULT_PITCH
	_snap_next = true
	_snap_physics_frame = Engine.get_physics_frames()
	_apply_rotation()
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		global_position = _target_point()
	_arm_len = _zoom


## Current smoothed camera arm length (after wall collisions).
func arm_length() -> float:
	return _arm_len


## Horizontal forward direction of the camera (for camera-relative movement).
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


# --- Input -------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or get_tree().paused:
		return
	if event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		rotate_by(rel)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# factor > 1 when several notches arrive in one event; < 1 for precise touchpad scrolling.
		var f: float = (event as InputEventMouseButton).factor
		var steps: float = clampf(f, 0.2, 4.0) if f > 0.0 else 1.0
		if event.is_action_pressed("zoom_in"):
			zoom_by(-ZOOM_STEP * steps)
		elif event.is_action_pressed("zoom_out"):
			zoom_by(ZOOM_STEP * steps)


## Applies a mouse delta (pixels) with the current sensitivity / invert settings.
func rotate_by(rel: Vector2) -> void:
	var s := BASE_SENS * _sens
	yaw = wrapf(yaw - rel.x * s, -PI, PI)
	var dy := rel.y * s
	pitch = clampf(pitch + (dy if _invert else -dy), PITCH_MIN, PITCH_MAX)
	_apply_rotation()


func zoom_by(amount: float) -> void:
	zoom_target = clampf(zoom_target + amount, ZOOM_MIN, ZOOM_MAX)


# --- Per frame ------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var dt := minf(delta, 0.1)
	var goal := _target_point()
	if _snap_next:
		global_position = goal
		_snap_next = false
	else:
		var p := global_position
		var kxz := 1.0 - exp(-14.0 * dt)
		var ky := 1.0 - exp(-7.5 * dt)
		p.x = lerpf(p.x, goal.x, kxz)
		p.z = lerpf(p.z, goal.z, kxz)
		p.y = lerpf(p.y, goal.y, ky)
		# Never lag so far that the target leaves the frame (fast falls, knockback).
		if p.distance_to(goal) > 2.5:
			p = goal + (p - goal).normalized() * 2.5
		global_position = p
	_apply_rotation()
	# Zoom & wall avoidance
	_zoom = lerpf(_zoom, zoom_target, 1.0 - exp(-8.0 * dt))
	_spring.spring_length = _zoom
	# Right after a snap (spawn, respawn, recovery, bed, lift) the SpringArm3D has not run a physics step at
	# the new place yet: its hit length is stale (0 on the very first frame, which used to start every area
	# with the camera inside Krystal's head, zooming out over ~1.5 s). Place the arm directly from a cast.
	var fresh := Engine.get_physics_frames() <= _snap_physics_frame + 1
	if fresh:
		var room0 := _shoulder_room(SHOULDER)
		_shoulder = room0
		_arm_len = _direct_arm_length(room0)
	else:
		var want := clampf(_spring.get_hit_length(), 0.2, _zoom)
		if want < _arm_len:
			_arm_len = minf(lerpf(_arm_len, want, 1.0 - exp(-28.0 * dt)), want + 0.2)
		else:
			_arm_len = lerpf(_arm_len, want, 1.0 - exp(-3.5 * dt))
		# Right-shoulder offset as a real lateral offset of the arm (not Camera3D.h_offset, which moves the
		# eye sideways past what the spring arm checked and let it slip behind walls on Krystal's right).
		# The room on the right is probed every frame: it shrinks quickly near a wall and eases back out.
		var desired := SHOULDER * clampf(_arm_len / 3.2, 0.25, 1.0)
		var room := _shoulder_room(desired)
		if room < _shoulder:
			_shoulder = minf(lerpf(_shoulder, room, 1.0 - exp(-30.0 * dt)), room + 0.02)
		else:
			_shoulder = lerpf(_shoulder, room, 1.0 - exp(-4.0 * dt))
	_spring.position = Vector3(_shoulder, 0.0, 0.0)
	camera.position = Vector3(_shoulder, 0.0, _arm_len)
	camera.h_offset = 0.0
	# FOV with a gentle sprint kick
	var sprinting := target.has_method("is_sprinting") and bool(target.is_sprinting())
	_fov_kick = lerpf(_fov_kick, 4.0 if sprinting else 0.0, 1.0 - exp(-4.0 * dt))
	camera.fov = _base_fov + _fov_kick
	_update_shake(dt)
	_update_avatar_visibility()


## Arm length (like the SpringArm3D: probe sphere + margin) cast right now from the shifted arm origin.
func _direct_arm_length(shoulder: float) -> float:
	if not is_inside_tree():
		return _zoom
	var origin := _pitch_node.global_transform * Vector3(shoulder, 0.0, 0.0)
	var back := _pitch_node.global_basis.z.normalized()
	_arm_q.transform = Transform3D(Basis.IDENTITY, origin)
	_arm_q.motion = back * _zoom
	var res := get_world_3d().direct_space_state.cast_motion(_arm_q)
	if res.size() < 2 or float(res[0]) >= 1.0:
		return _zoom
	return clampf(float(res[0]) * _zoom - _spring.margin, 0.2, _zoom)


## How far the arm may shift to the right (up to `desired`) before a small sphere from the pivot would
## touch world|structure geometry.
func _shoulder_room(desired: float) -> float:
	if desired <= 0.001 or not is_inside_tree():
		return maxf(desired, 0.0)
	var right := _yaw_node.global_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return desired
	_side_q.transform = Transform3D(Basis.IDENTITY, global_position)
	_side_q.motion = right.normalized() * (desired + SIDE_PAD)
	var res := get_world_3d().direct_space_state.cast_motion(_side_q)
	if res.size() < 2 or float(res[0]) >= 1.0:
		return desired
	return clampf(float(res[0]) * (desired + SIDE_PAD) - SIDE_PAD, 0.0, desired)


func _target_point() -> Vector3:
	var base: Vector3 = target.get_visual_position() if target.has_method("get_visual_position") else target.global_position
	return base + Vector3(0.0, TARGET_HEIGHT, 0.0)


func _apply_rotation() -> void:
	_yaw_node.rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)


func _update_shake(dt: float) -> void:
	if _trauma <= 0.0:
		camera.rotation = Vector3.ZERO
		camera.v_offset = 0.0
		return
	_trauma = maxf(0.0, _trauma - _trauma_decay * dt)
	_shake_t += dt
	var a := _trauma
	var n1 := sin(_shake_t * 37.1) * 0.6 + sin(_shake_t * 23.3 + 1.7) * 0.4
	var n2 := sin(_shake_t * 31.7 + 0.5) * 0.6 + sin(_shake_t * 19.1 + 2.9) * 0.4
	var n3 := sin(_shake_t * 27.3 + 4.1)
	camera.rotation = Vector3(n1 * 0.03 * a, n2 * 0.03 * a, n3 * 0.02 * a)
	camera.v_offset = n2 * 0.05 * a


func _update_avatar_visibility() -> void:
	if not target.has_method("set_avatar_visible"):
		return
	var head := _target_point()
	var d := camera.global_position.distance_to(head)
	var close := d < (SHOW_DIST if _avatar_hidden else HIDE_DIST)
	if close != _avatar_hidden:
		_avatar_hidden = close
		target.set_avatar_visible(not close)


# --- Settings & comfort ------------------------------------------------------------------------------------

func _read_settings() -> void:
	_sens = clampf(float(Settings.get_value("mouse_sensitivity")), 0.05, 3.0)
	_invert = bool(Settings.get_value("invert_y"))
	_reduce_shake = bool(Settings.get_value("reduce_shake"))
	_base_fov = clampf(float(Settings.get_value("fov")), 40.0, 110.0)


func _on_settings_changed(key: String) -> void:
	_read_settings()
	if key == "camera_distance":
		zoom_target = clampf(float(Settings.get_value("camera_distance")), ZOOM_MIN, ZOOM_MAX)
	if key == "reduce_shake" and _reduce_shake:
		_trauma = 0.0


func _on_camera_shake(strength: float, duration: float) -> void:
	add_shake(strength, duration)


## Adds trauma (respects the reduce_shake comfort setting; clamped small).
func add_shake(strength: float, duration: float) -> void:
	if _reduce_shake or strength <= 0.0:
		return
	var s := clampf(strength, 0.0, MAX_SHAKE)
	if s >= _trauma:
		_trauma = s
		_trauma_decay = s / maxf(duration, 0.05)


func shake_amount() -> float:
	return _trauma
