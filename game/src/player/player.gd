extends CharacterBody3D
## Krystal - the player character (ARCHITECTURE.md "Player").
## Feet at the origin, capsule r 0.32 h 1.6, layer 2 (player), mask world|structure.
## Camera-relative movement with acceleration smoothing, sprint (stamina), jump (coyote + buffer),
## dodge roll (i-frames), tool/weapon swings (one strike per swing, one buffered click), interaction
## probe, food, lantern, companion follow/wait, fall recovery and health/state sync.
## Children (built in code): Health, CollisionShape, KrystalAvatar (top-level, interpolated),
## CameraRig (top-level), InteractionProbe.

const Logic := preload("res://src/player/player_logic.gd")
const AvatarScript := preload("res://src/player/krystal_avatar.gd")
const ProbeScript := preload("res://src/player/interaction_probe.gd")
const CameraRigScript := preload("res://src/camera/camera_rig.gd")
const HealthScript := preload("res://src/combat/health.gd")
const Layout := preload("res://data/world_layout.gd")
const COMBAT_PATH := "res://src/combat/combat.gd"
const DEMO_PATH := "res://src/player/player_demo.gd"
const HOTBAR_ACTIONS: Array[StringName] = [&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4", &"hotbar_5", &"hotbar_6", &"hotbar_7", &"hotbar_8"]
const HURT_IFRAMES := 0.6
const HURT_KNOCKBACK := 4.5
const DANGER_SECONDS := 5.0
const EAT_TIME := 1.0
const DEATH_RETRY := 2.5

# --- Contract ----------------------------------------------------------------------------------------
var health: Node                         # src/combat/health.gd
## Current stamina. Reads/writes go straight to the stamina model, so other systems (e.g. the bed refilling
## it) can simply assign `player.stamina = x` without the next physics tick overwriting it.
var stamina: float:
	get:
		return _stamina.value
	set(v):
		_stamina.value = clampf(v, 0.0, _stamina.max_value)
		if _stamina.value >= Logic.SPRINT_RESUME:
			_stamina.exhausted = false
		GameState.player["stamina"] = _stamina.value
var lantern_on: bool = false
var build_mode_active: bool = false
var light_radius: float = 6.0            # group "light_source" contract
var input_enabled: bool = true
var recoveries: int = 0                  # telemetry: how many times fall recovery kicked in

# --- Children ------------------------------------------------------------------------------------------
var avatar: AvatarScript
var rig: CameraRigScript
var probe: ProbeScript

# --- State -----------------------------------------------------------------------------------------------
var _stamina := Logic.Stamina.new()
var _swing := Logic.Swing.new()
var _jump := Logic.JumpAssist.new()
var _safe := Logic.SafeTracker.new()
var _dead: bool = false
var _recovering: bool = false
var _sprinting: bool = false
var _dodge_t: float = -1.0
var _dodge_dir := Vector3.FORWARD
var _dodge_cd: float = 0.0
var _stagger: float = 0.0
var _jump_lock: float = 0.0
var _jump_held: bool = false
var _air_time: float = 0.0
var _fall_speed: float = 0.0
var _was_grounded: bool = true
var _last_damage_ms: int = -1000000
var _iframes_until_ms: int = 0
var _swing_target: Node = null
var _swing_tool: String = ""
var _swing_harvest: bool = false
var _swing_face := Vector3.ZERO
var _eat_lock: float = 0.0
var _floor_collider: Object = null
var _facing_yaw: float = 0.0
var _turn_rate: float = 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _prev_yaw: float = 0.0
var _cur_yaw: float = 0.0
var _notify_ms: Dictionary = {}
var _combat: Script = null
var _combat_checked: bool = false
var _ground_check_t: float = 0.0
var _ground_h: float = NAN
var _owned_check_t: float = 0.0
var _wish := Vector3.ZERO
var _recover_seq: int = 0
var _death_wait: float = 0.0
var _visual_offset := Vector3.ZERO    # smooths step-ups so the avatar and camera glide instead of popping


func _init() -> void:
	name = "Player"
	health = HealthScript.new()
	health.name = "Health"
	health.max_hp = 100.0
	add_child(health)


func _ready() -> void:
	add_to_group("player")
	add_to_group("light_source")
	collision_layer = 2
	collision_mask = 1 | 32
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_stop_on_slope = true
	floor_block_on_wall = true
	max_slides = 6
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)
	avatar = AvatarScript.new()
	avatar.name = "KrystalAvatar"
	avatar.driven = true
	add_child(avatar)
	avatar.top_level = true
	avatar.footstep.connect(_on_footstep)
	rig = CameraRigScript.new()
	rig.setup(self)
	add_child(rig)
	probe = ProbeScript.new()
	probe.name = "InteractionProbe"
	probe.player = self
	add_child(probe)
	health.damaged.connect(_on_damaged)
	health.healed.connect(_on_healed)
	health.died.connect(_on_died)
	health.changed.connect(_on_health_changed)
	Events.build_mode_changed.connect(_on_build_mode_changed)
	_facing_yaw = rotation.y
	_cur_yaw = _facing_yaw
	_prev_yaw = _facing_yaw
	_cur_pos = global_position
	_prev_pos = _cur_pos
	_place_avatar(1.0)
	rig.snap(_facing_yaw)
	_refresh_owned()
	if Debug.is_cheat_allowed() and Debug.has_arg("player-demo") and ResourceLoader.exists(DEMO_PATH):
		var ds: Script = load(DEMO_PATH)
		if ds != null and ds.can_instantiate():
			var demo: Node = ds.new()
			demo.set("player", self)
			add_child(demo)


# =====================================================================================================
# Contract API
# =====================================================================================================

func teleport(xform: Transform3D) -> void:
	global_position = xform.origin
	var f := -xform.basis.z
	f.y = 0.0
	if f.length() > 0.01:
		_facing_yaw = Logic.yaw_for_dir(f.normalized())
	rotation = Vector3(0.0, _facing_yaw, 0.0)
	velocity = Vector3.ZERO
	_dodge_t = -1.0
	_stagger = 0.0
	_swing.cancel()
	_swing_target = null
	_air_time = 0.0
	_fall_speed = 0.0
	_jump.clear()
	_prev_pos = xform.origin
	_cur_pos = xform.origin
	_visual_offset = Vector3.ZERO
	_prev_yaw = _facing_yaw
	_cur_yaw = _facing_yaw
	_safe.clear()
	_safe.record(xform.origin)
	if avatar != null:
		avatar.reset_motion()
		_place_avatar(1.0)
	if rig != null:
		rig.snap(_facing_yaw)


func read_from_state() -> void:
	var p: Dictionary = GameState.player
	var mx: float = float(p.get("max_hp", 100.0))
	health.max_hp = maxf(mx, 1.0)
	var hp: float = float(p.get("hp", mx))
	if hp <= 0.0:
		hp = health.max_hp
	health.set_hp(hp)
	_stamina.reset(float(p.get("stamina", 100.0)), float(p.get("max_stamina", 100.0)))
	_dead = false
	_death_wait = 0.0
	_recovering = false
	if avatar != null:
		avatar.cancel_action(true)
	set_lantern(bool(p.get("lantern_on", false)) and GameState.has_item("lantern"), true)


func write_to_state() -> void:
	var p: Dictionary = GameState.player
	var pos: Variant = null
	if is_on_floor() and not _in_danger():
		pos = global_position
	elif _safe.has_point():
		pos = _safe.last()
	if pos is Vector3:
		var v: Vector3 = pos
		p["pos"] = [v.x, v.y, v.z]
	p["yaw"] = _facing_yaw
	p["hp"] = float(health.hp)
	p["max_hp"] = float(health.max_hp)
	p["stamina"] = _stamina.value
	p["max_stamina"] = _stamina.max_value
	p["lantern_on"] = lantern_on


func set_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		_sprinting = false
	if rig != null:
		rig.input_enabled = on


func get_camera() -> Camera3D:
	return rig.camera if rig != null else null


func set_lantern(on: bool, silent: bool = false) -> void:
	var changed := on != lantern_on
	lantern_on = on
	GameState.player["lantern_on"] = on
	if avatar != null:
		avatar.lantern_on = on
	if changed and not silent:
		Audio.play_sfx("lantern_on" if on else "lantern_off")


## Group "light_source" contract (combat.light_at, enemies that fear light).
func is_light_active() -> bool:
	return lantern_on


func is_sprinting() -> bool:
	return _sprinting and _hspeed() > 0.5


func is_dodging() -> bool:
	return _dodge_t >= 0.0


func is_moving() -> bool:
	return _hspeed() > 0.3


func is_dead() -> bool:
	return _dead


func get_prompt() -> Dictionary:
	if not can_probe() or probe == null:
		return {}
	return probe.prompt


func get_focus_target() -> Node:
	if probe == null or not can_probe():
		return null
	var f: Node = probe.focus
	return f if f != null and is_instance_valid(f) else null


func get_facing() -> Vector3:
	return Logic.dir_for_yaw(_facing_yaw)


## Emotes: "wave", "cheer", "flinch", "sleep" (loops until Krystal moves), plus "eat", "hurt", "tired".
## "" / "none" / "stop" ends the current emote (e.g. waking up from "sleep").
func play_emote(emote_name: String) -> void:
	if avatar == null:
		return
	if emote_name == "" or emote_name == "none" or emote_name == "stop":
		avatar.cancel_action()
	else:
		avatar.play_action(emote_name)


## Pushes Krystal away (dir = direction of the push). Replaces, never stacks; ignored while rolling.
func knockback(dir: Vector3, force: float) -> void:
	if _dodge_t >= 0.0 or _recovering:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		return
	d = d.normalized()
	var f := clampf(force, 0.0, 12.0)
	velocity.x = d.x * f
	velocity.z = d.z * f
	if is_on_floor():
		velocity.y = maxf(velocity.y, minf(2.5, f * 0.3))
	_stagger = 0.3


## Interpolated render position (physics runs at 60 Hz; visuals are smooth at any frame rate).
func get_visual_position() -> Vector3:
	return _prev_pos.lerp(_cur_pos, Engine.get_physics_interpolation_fraction()) + _visual_offset


func set_avatar_visible(v: bool) -> void:
	if avatar != null:
		avatar.set_body_visible(v)


## True when the interaction probe should look for targets.
func can_probe() -> bool:
	return _can_act() and not build_mode_active


## Seconds since Krystal last took damage.
func seconds_since_damage() -> float:
	return float(Time.get_ticks_msec() - _last_damage_ms) / 1000.0


# =====================================================================================================
# Physics
# =====================================================================================================

func _physics_process(delta: float) -> void:
	var dt := delta
	if _dead:
		# Game.on_player_died() ignores deaths outside "playing" (e.g. a hit during the lift ride cutscene).
		# Without this retry Krystal would stay down with input disabled once the cutscene ends.
		_death_wait += dt
		if _death_wait >= DEATH_RETRY and Game.mode == "playing" and Game.has_method("on_player_died"):
			_death_wait = 0.0
			Game.on_player_died()
	if _recovering:
		velocity = Vector3.ZERO
		_store_visual_state()
		return
	var grounded := is_on_floor()
	var can_act := _can_act()
	_dodge_cd = maxf(0.0, _dodge_cd - dt)
	_eat_lock = maxf(0.0, _eat_lock - dt)
	_jump_lock = maxf(0.0, _jump_lock - dt)
	_stagger = maxf(0.0, _stagger - dt)
	_jump.tick(dt, grounded and _jump_lock <= 0.0)
	# Input -> camera-relative wish direction
	var raw := Vector2.ZERO
	if can_act:
		raw = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_yaw: float = rig.yaw if rig != null else _facing_yaw
	_wish = Logic.camera_relative(raw, cam_yaw)
	if raw.length() > 0.15 and avatar != null:
		var act: String = avatar.current_action()
		if act == "sleep" or act == "wave" or act == "cheer" or act == "tired":
			avatar.cancel_action()
	# Sprint & stamina
	var hs := _hspeed()
	_sprinting = can_act and Input.is_action_pressed("sprint") and _wish.length() > 0.2 and _stamina.can_sprint() and _dodge_t < 0.0 and not _swing.active and _eat_lock <= 0.0
	_stamina.tick(dt, _sprinting and hs > 1.0, GameState.buff_mult("stamina_regen"))
	# Horizontal velocity
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if _dodge_t >= 0.0:
		_dodge_t += dt
		var k := _dodge_t / Logic.DODGE_TIME
		if k >= 1.0:
			_end_dodge()
		else:
			hv = _dodge_dir * Logic.dodge_speed(k)
	if _dodge_t < 0.0:
		var top := Logic.SPRINT_SPEED if _sprinting else Logic.WALK_SPEED
		if _swing.active:
			top *= 0.35
		if _eat_lock > 0.0:
			top *= 0.55
		if _dead:
			top = 0.0
		if _stagger > 0.0:
			hv = hv.move_toward(_wish * top, Logic.AIR_DECEL * dt)
		else:
			hv = Logic.approach(hv, _wish * top, grounded, dt)
	# Gravity, jump cut and jump
	if not grounded:
		var g := Logic.GRAVITY * (Logic.FALL_GRAVITY_MULT if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * dt, -Logic.TERMINAL_FALL)
	if _jump_held and velocity.y > 0.0 and not (can_act and Input.is_action_pressed("jump")):
		velocity.y *= Logic.JUMP_CUT
		_jump_held = false
	if can_act and _dodge_t < 0.0 and not _swing.active and _eat_lock <= 0.0 and _jump.try_consume():
		_do_jump()
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	if grounded and _wish.length() > 0.1 and _jump_lock <= 0.0 and _dodge_t < 0.0 and is_on_wall():
		_try_step_up(hv)
	# Landing / air time / floor surface
	var now_g := is_on_floor()
	if now_g:
		if not _was_grounded:
			_on_land()
		_air_time = 0.0
		_fall_speed = 0.0
		_update_floor_collider()
	else:
		_air_time += dt
		_fall_speed = maxf(_fall_speed, -velocity.y)
	_was_grounded = now_g
	_update_facing(dt)
	# Safe ground & recovery
	var safe_now := now_g and _dodge_t < 0.0 and not _dead and _stagger <= 0.0 and seconds_since_damage() > 1.0 and _in_world_bounds()
	_safe.tick(dt, global_position, safe_now)
	_check_recovery(dt)
	# Swing timing
	var ev := _swing.tick(dt)
	if ev & Logic.Swing.STRIKE:
		_on_strike()
	if ev & Logic.Swing.FINISHED:
		_on_swing_finished()
	GameState.player["stamina"] = _stamina.value
	_store_visual_state()


func _store_visual_state() -> void:
	_prev_pos = _cur_pos
	_cur_pos = global_position
	_prev_yaw = _cur_yaw
	_cur_yaw = _facing_yaw


func _process(delta: float) -> void:
	_place_avatar(Engine.get_physics_interpolation_fraction())
	_feed_avatar()
	_visual_offset = _visual_offset.lerp(Vector3.ZERO, 1.0 - exp(-16.0 * minf(delta, 0.1)))
	_owned_check_t -= delta
	if _owned_check_t <= 0.0:
		_owned_check_t = 0.5
		_refresh_owned()


func _place_avatar(f: float) -> void:
	if avatar == null:
		return
	var p := _prev_pos.lerp(_cur_pos, f) + _visual_offset
	var y := lerp_angle(_prev_yaw, _cur_yaw, f)
	avatar.global_transform = Transform3D(Basis(Vector3.UP, y + PI), p)


func _feed_avatar() -> void:
	if avatar == null:
		return
	avatar.speed = _hspeed() if not _dead else 0.0
	avatar.grounded = is_on_floor() or _air_time < 0.1
	avatar.vertical_speed = velocity.y
	avatar.turn_rate = _turn_rate
	avatar.sprinting = _sprinting
	if _swing.active:
		avatar.swing_kind = _swing.kind
		var f := Engine.get_physics_interpolation_fraction() * get_physics_process_delta_time()
		avatar.swing_t = clampf((_swing.t + f) / _swing.duration, 0.0, 1.0)
	else:
		avatar.swing_t = -1.0
	avatar.roll_t = clampf(_dodge_t / Logic.DODGE_TIME, 0.0, 1.0) if _dodge_t >= 0.0 else -1.0
	avatar.lantern_on = lantern_on
	var focus := get_focus_target()
	if focus is Node3D and is_instance_valid(focus):
		avatar.has_look_target = true
		avatar.look_target = (focus as Node3D).global_position + Vector3.UP * 0.6
	else:
		avatar.has_look_target = false


func _refresh_owned() -> void:
	var owned := GameState.has_item("lantern")
	if avatar != null:
		avatar.lantern_owned = owned
		avatar.lantern_energy_scale = Logic.lantern_scale(Game.area_id, GameState.hour())
	if lantern_on and not owned:
		set_lantern(false)


func _hspeed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _update_facing(dt: float) -> void:
	var desired := _facing_yaw
	var rate := Logic.TURN_RATE
	if _dodge_t >= 0.0:
		desired = Logic.yaw_for_dir(_dodge_dir)
		rate = 30.0
	elif _swing.active and _swing_face.length() > 0.1:
		desired = Logic.yaw_for_dir(_swing_face)
		rate = 24.0
	elif _wish.length() > 0.1 and not _dead and _stagger <= 0.0:
		desired = Logic.yaw_for_dir(_wish)
	var new_yaw := lerp_angle(_facing_yaw, desired, 1.0 - exp(-rate * dt))
	_turn_rate = angle_difference(_facing_yaw, new_yaw) / maxf(dt, 0.0001)
	_facing_yaw = wrapf(new_yaw, -PI, PI)
	rotation = Vector3(0.0, _facing_yaw, 0.0)


func _update_floor_collider() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y > 0.6:
			_floor_collider = col.get_collider()
			return


## Steps over small lips (<= STEP_HEIGHT) that the capsule would otherwise treat as walls:
## raise, move forward, settle down onto a walkable surface. Real walls and steep slopes are rejected.
func _try_step_up(hv: Vector3) -> bool:
	var dir := Vector3(hv.x, 0.0, hv.z)
	if dir.length() < 0.2:
		dir = _wish
	if dir.length() < 0.05:
		return false
	dir = dir.normalized()
	if get_wall_normal().dot(dir) > -0.25:
		return false
	var start := global_transform
	var up := Vector3.UP * Logic.STEP_HEIGHT
	if test_move(start, up):
		return false
	var raised := start.translated(up)
	var fwd := dir * 0.24
	if test_move(raised, fwd):
		return false
	var ahead := raised.translated(fwd)
	var col := KinematicCollision3D.new()
	if not test_move(ahead, Vector3.DOWN * (Logic.STEP_HEIGHT + 0.06), col):
		return false
	var landing := ahead.origin + col.get_travel()
	var rise := landing.y - start.origin.y
	if rise < 0.02 or rise > Logic.STEP_HEIGHT + 0.01:
		return false
	var min_up := cos(floor_max_angle)
	if col.get_normal().y < min_up:
		# The capsule may rest on an edge; accept if the surface under its centre is walkable.
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(landing + Vector3.UP * 0.35, landing + Vector3.DOWN * 0.25, collision_mask, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty() or Vector3(hit["normal"]).y < min_up:
			return false
	_visual_offset -= landing - start.origin
	global_position = landing
	velocity.y = 0.0
	apply_floor_snap()
	return true


func _do_jump() -> void:
	velocity.y = Logic.JUMP_VELOCITY
	_jump_lock = 0.15
	_jump_held = true
	_air_time = 0.01
	if avatar != null:
		avatar.play_action("jump")
	Audio.play_3d("jump", global_position, -6.0, 0.08, 20.0)


func _on_land() -> void:
	var fs := _fall_speed
	if _air_time > 0.2 or fs > 3.0:
		if avatar != null:
			avatar.play_action("land", fs * 0.3)
		Audio.play_3d("land", global_position, lerpf(-12.0, -3.0, clampf(fs / 14.0, 0.0, 1.0)), 0.08, 20.0)
		if fs > 12.0:
			Events.camera_shake.emit(0.12, 0.18)


# =====================================================================================================
# Input
# =====================================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or not _can_act():
		return
	if event.is_action_pressed("jump"):
		_jump.press()
	elif event.is_action_pressed("dodge"):
		_try_dodge()
	elif event.is_action_pressed("attack"):
		_on_attack_pressed()
	elif event.is_action_pressed("use_item"):
		_use_item()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("lantern"):
		_toggle_lantern()
	elif event.is_action_pressed("companion_command"):
		_companion_command()
	else:
		for i in HOTBAR_ACTIONS.size():
			if event.is_action_pressed(HOTBAR_ACTIONS[i]):
				GameState.select_hotbar(i)
				break


func _can_act() -> bool:
	return input_enabled and not _dead and not _recovering and Game.gameplay_input_allowed()


# --- Dodge -------------------------------------------------------------------------------------------------

func _try_dodge() -> void:
	if _dodge_t >= 0.0 or _dodge_cd > 0.0 or _dead or _eat_lock > 0.0:
		return
	if not is_on_floor() and _jump.coyote_left <= 0.0:
		return
	if _swing.active and not _swing.can_cancel():
		return
	if not _stamina.try_spend(Logic.DODGE_COST):
		if avatar != null and avatar.current_action() == "":
			avatar.play_action("tired")
		return
	_swing.cancel()
	_swing_target = null
	var dir := _wish
	if dir.length() < 0.1:
		dir = get_facing()
	_dodge_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_dodge_t = 0.0
	_facing_yaw = Logic.yaw_for_dir(_dodge_dir)
	_grant_iframes(Logic.DODGE_IFRAMES)
	Audio.play_3d("dodge", global_position, -5.0, 0.08, 20.0)
	if avatar != null:
		avatar.cancel_action()


func _end_dodge() -> void:
	_dodge_t = -1.0
	_dodge_cd = Logic.DODGE_COOLDOWN


func _grant_iframes(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	if until > _iframes_until_ms:
		_iframes_until_ms = until
		health.grant_iframes(seconds)


# --- Attack / gather ------------------------------------------------------------------------------------------

func _on_attack_pressed() -> void:
	if build_mode_active or _dodge_t >= 0.0 or _eat_lock > 0.0:
		return
	if not _swing.request():
		return
	_start_swing()


func _start_swing() -> void:
	_swing_target = null
	_swing_harvest = false
	_swing_tool = ""
	_swing_face = Vector3.ZERO
	var kind := "hands"
	if probe != null:
		probe.refresh()
	var target: Node = probe.focused_harvestable() if probe != null else null
	# Fighting comes first: with an enemy right in front of her, a click swings at it instead of gathering
	# the grass / berry bush / tree that happens to be focused.
	var foe_dir := _soft_lock_dir()
	if foe_dir.length() > 0.1:
		target = null
	if target != null:
		var info: Dictionary = probe.focus_harvest
		var tool := String(info.get("tool", "hand"))
		var owned := ""
		if tool == "hand" or tool == "":
			owned = "hand"
		else:
			owned = GameState.best_tool(tool)
		if owned != "":
			_swing_harvest = true
			_swing_target = target
			_swing_tool = "" if owned == "hand" else owned
			kind = "gather" if owned == "hand" else tool
			if target is Node3D:
				_swing_face = _flat_dir_to((target as Node3D).global_position)
		else:
			_need_tool_notice(tool)
	if not _swing_harvest:
		_swing_tool = GameState.best_weapon()
		var d: Dictionary = ItemDB.item(_swing_tool) if _swing_tool != "" else {}
		kind = Logic.weapon_kind(_swing_tool, String(d.get("cat", "")), String(d.get("tool", "")))
		_swing_face = foe_dir
		if _swing_face.length() < 0.1 and _wish.length() > 0.1:
			_swing_face = _wish.normalized()
	var full := _stamina.spend_soft(Logic.SWING_COST)
	var mult := 1.0 if full else Logic.TIRED_SWING_MULT
	_swing.start(kind, Logic.SWING_TIME * mult, Logic.SWING_STRIKE * mult)
	if avatar != null:
		avatar.cancel_action()
		avatar.show_tool(kind, Logic.SWING_TIME * mult + 0.35)


func _need_tool_notice(tool: String) -> void:
	var verb := Logic.harvest_verb(tool).to_lower()
	_notify("You need %s to %s this." % [Logic.tool_article_name(tool), verb], "warn", "need_" + tool, 3.0)
	Events.hint.emit("need_tool", "Trees need an Axe and rocks need a Pickaxe. Open crafting with {craft} to make tools.")


func _on_strike() -> void:
	Audio.play_3d("swing", global_position + Vector3.UP, -4.0, 0.1, 20.0)
	if _swing_harvest:
		var t := _swing_target
		_swing_target = null
		if t != null and is_instance_valid(t) and t.has_method("harvest_hit"):
			if not (t is Node3D) or (t as Node3D).global_position.distance_to(global_position) < 4.5:
				t.harvest_hit(self, _swing_tool)
		return
	_melee_hit()


func _on_swing_finished() -> void:
	_swing_target = null
	if _swing.take_buffer() and _can_act() and _dodge_t < 0.0:
		_start_swing()


func _melee_hit() -> Array:
	var dmg := Logic.HAND_DAMAGE
	var reach := Logic.HAND_REACH
	if _swing_tool != "" and ItemDB.has_item(_swing_tool):
		var d: Dictionary = ItemDB.item(_swing_tool)
		dmg = maxf(float(d.get("damage", dmg)), Logic.HAND_DAMAGE)
		reach = float(d.get("reach", reach))
	var origin := global_position + Vector3.UP * 0.9
	var fwd := get_facing()
	var combat := _combat_script()
	var hits: Array = []
	if combat != null:
		hits = combat.melee(self, origin, fwd, reach, Logic.MELEE_ARC, dmg, ["enemy"], 4.0)
	else:
		hits = _fallback_melee(origin, fwd, reach, Logic.MELEE_ARC, dmg, 4.0)
	if not hits.is_empty():
		Events.camera_shake.emit(0.1, 0.12)
	return hits


func _combat_script() -> Script:
	if not _combat_checked:
		_combat_checked = true
		if ResourceLoader.exists(COMBAT_PATH):
			var s: Script = load(COMBAT_PATH)
			if s != null and s.can_instantiate() and s.has_method("melee"):
				_combat = s
	return _combat


## Used only if src/combat/combat.gd is missing: simple arc query over group "enemy".
func _fallback_melee(origin: Vector3, fwd: Vector3, reach: float, arc_deg: float, dmg: float, force: float) -> Array:
	var hits: Array = []
	var half := deg_to_rad(arc_deg * 0.5)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not is_instance_valid(e) or e == self:
			continue
		var n3 := e as Node3D
		var to := n3.global_position - origin
		if absf(to.y + 0.9) > 1.8:
			continue
		to.y = 0.0
		var dist := to.length()
		if dist > reach + 0.45:
			continue
		if dist > 0.6 and fwd.angle_to(to / dist) > half:
			continue
		var h: Variant = e.get("health")
		if not (h is Node):
			h = e.get_node_or_null("Health")
		if h is Node and (h as Node).has_method("apply_damage"):
			var dir := to.normalized() if dist > 0.01 else fwd
			var dealt: float = float(h.apply_damage(dmg, self, dir))
			if dealt > 0.0:
				if e.has_method("knockback"):
					e.knockback(dir, force)
				hits.append(e)
	return hits


func _soft_lock_dir() -> Vector3:
	var best: Node3D = null
	var best_d := 3.2
	var facing := get_facing()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		var h: Variant = e.get("health")
		if h is Node and Logic._truthy((h as Node).get("dead"), false):
			continue
		var to := (e as Node3D).global_position - global_position
		if absf(to.y) > 1.8:
			continue     # e.g. the stalker on the ceiling: not something a swing can reach
		to.y = 0.0
		var d := to.length()
		if d < 0.05 or d >= best_d:
			continue
		if facing.dot(to / d) > -0.2 or d < 1.5:
			best = e
			best_d = d
	if best == null:
		return Vector3.ZERO
	return _flat_dir_to(best.global_position)


func _flat_dir_to(p: Vector3) -> Vector3:
	var to := p - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else Vector3.ZERO


# --- Interact / use item / lantern / companion ---------------------------------------------------------------

func _interact() -> void:
	if build_mode_active or _swing.active or _dodge_t >= 0.0 or probe == null:
		return
	probe.refresh()
	var t: Node = probe.focus
	if t == null or not is_instance_valid(t):
		return
	# Trees / rocks / ore: E does what the prompt says (swing the tool, one hit per swing) instead of the
	# node's instant interact(), so harvesting always has the swing, the stamina cost and the lockout.
	if probe.focused_harvestable() != null:
		var tool := String(probe.focus_harvest.get("tool", "hand"))
		if tool != "hand" and tool != "":
			if GameState.best_tool(tool) == "":
				_need_tool_notice(tool)
			else:
				_on_attack_pressed()
			return
	if not t.has_method("interact"):
		return
	var info: Dictionary = probe.focus_interaction
	if info.is_empty() or not Logic._truthy(info.get("enabled", true), true):
		return
	if t is Node3D:
		var d := _flat_dir_to((t as Node3D).global_position)
		if d.length() > 0.1:
			_facing_yaw = Logic.yaw_for_dir(d)
	if avatar != null:
		avatar.play_action("interact")
	t.interact(self)
	probe.refresh()


func _use_item() -> void:
	if build_mode_active or _swing.active or _dodge_t >= 0.0:
		return
	var slot: Variant = GameState.selected_slot()
	if not (slot is Dictionary):
		return
	var id := String((slot as Dictionary).get("id", ""))
	if id == "" or not ItemDB.has_item(id):
		return
	match ItemDB.category(id):
		"food":
			eat(id)
		"placeable":
			var bm := get_tree().get_first_node_in_group("build_mode")
			if bm != null and bm.has_method("begin"):
				bm.begin(id)
			else:
				_notify("You can build this in your Haven.", "info", "no_build", 2.5)
		"seed":
			_notify("Plant seeds in a crop plot: look at one and press %s." % Settings.action_label("interact"), "info", "seed_hint", 3.0)
		"equipment":
			if id == "lantern":
				_toggle_lantern()
		"tool", "weapon":
			_notify("Tools and weapons are used automatically with %s." % Settings.action_label("attack"), "info", "tool_hint", 4.0)


## Eats one of `id` from the backpack. Returns true when eaten.
func eat(id: String) -> bool:
	if _eat_lock > 0.0 or _dead:
		return false
	var d: Dictionary = ItemDB.item(id)
	var heal := float(d.get("heal", 0.0))
	var buff: Variant = d.get("buff", null)
	var has_buff := buff is Dictionary and not (buff as Dictionary).is_empty()
	if health.hp >= health.max_hp - 0.01 and not has_buff:
		_notify("You're already at full health.", "info", "full_hp", 2.0)
		return false
	if not GameState.take_item(id, 1):
		return false
	_eat_lock = EAT_TIME
	var healed: float = float(health.heal(heal))
	if has_buff:
		var bd: Dictionary = buff
		var secs := float(bd.get("seconds", 60.0))
		for k in bd:
			if String(k) != "seconds":
				GameState.add_buff(String(k), float(bd[k]), secs)
	Audio.play_sfx("eat")
	Events.item_consumed.emit(id)
	if avatar != null:
		var c: Variant = d.get("color", Color.WHITE)
		if c is Color:
			avatar.set_food_color(c)
		avatar.play_action("eat")
	var msg := "Yum! %s" % ItemDB.display_name(id)
	if healed >= 1.0:
		msg += " restored %d health" % roundi(healed)
	if has_buff and (buff as Dictionary).has("stamina_regen"):
		msg += (" and" if healed >= 1.0 else "") + " warms you up: stamina recovers faster for a while"
	Events.notify.emit(msg + ".", "success")
	return true


func _toggle_lantern() -> void:
	if not GameState.has_item("lantern"):
		_notify("You don't have a lantern yet.", "info", "no_lantern", 2.0)
		return
	set_lantern(not lantern_on)


func _companion_command() -> void:
	var nodes: Dictionary = Game.companion_nodes
	var id := GameState.active_companion
	var node: Node = null
	if id != "" and nodes.has(id) and is_instance_valid(nodes[id]):
		node = nodes[id]
	if node != null:
		if node.has_method("command"):
			if _command_ok(node.command("wait")):
				_notify("%s will wait here." % _companion_name(id), "info", "comp_cmd", 0.5)
				if avatar != null:
					avatar.play_action("interact")
		return
	# No follower: call back the nearest companion that is waiting nearby.
	var best: Node3D = null
	var best_id := ""
	var best_d := 35.0
	for cid in nodes:
		var c: Variant = nodes[cid]
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		if String(GameState.companion(String(cid)).get("assignment", "")) != "wait":
			continue
		var d := (c as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best = c
			best_id = String(cid)
			best_d = d
	if best == null or not best.has_method("command"):
		_notify("No companion is with you right now.", "info", "comp_none", 2.0)
		return
	if not _command_ok(best.command("follow")):
		return
	_notify("%s is following you again." % _companion_name(best_id), "info", "comp_cmd", 0.5)
	if avatar != null:
		avatar.play_action("wave")


## companion.command() returns {"ok": bool, ...}; anything else (older/other implementations) counts as ok.
## A refused or debounced command must not show a "will wait here" toast.
func _command_ok(result: Variant) -> bool:
	if result is Dictionary and (result as Dictionary).has("ok"):
		return Logic._truthy((result as Dictionary)["ok"], true)
	return true


func _companion_name(id: String) -> String:
	var c: Dictionary = ItemDB.creature(id)
	return String(c.get("name", id.capitalize()))


func _notify(text: String, kind: String, key: String, cooldown: float) -> void:
	var now := Time.get_ticks_msec()
	if int(_notify_ms.get(key, -1000000)) + int(cooldown * 1000.0) > now:
		return
	_notify_ms[key] = now
	Events.notify.emit(text, kind)


func _on_build_mode_changed(active: bool) -> void:
	build_mode_active = active
	if active and probe != null:
		probe.clear()


# =====================================================================================================
# Health
# =====================================================================================================

func _on_damaged(amount: float, source: Node, dir: Vector3) -> void:
	_last_damage_ms = Time.get_ticks_msec()
	_grant_iframes(HURT_IFRAMES)
	Audio.play_sfx("hurt")
	Events.player_damaged.emit(amount, source)
	Events.camera_shake.emit(clampf(0.15 + amount * 0.012, 0.15, 0.45), 0.28)
	var d := dir
	if d.length() < 0.01 and source is Node3D and is_instance_valid(source):
		d = global_position - (source as Node3D).global_position
	if not health.dead:
		if d.length() > 0.01:
			knockback(d, HURT_KNOCKBACK)
		if _swing.can_cancel():
			_swing.cancel()
			_swing_target = null
		if avatar != null:
			avatar.play_action("hurt")


func _on_healed(amount: float) -> void:
	Events.player_healed.emit(amount)


func _on_health_changed(hp: float, max_hp: float) -> void:
	GameState.player["hp"] = hp
	GameState.player["max_hp"] = max_hp


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_death_wait = 0.0
	_sprinting = false
	_swing.cancel()
	_swing_target = null
	_dodge_t = -1.0
	if avatar != null:
		avatar.play_action("death")
	Audio.play_sfx("death")
	if Game.has_method("on_player_died"):
		Game.on_player_died()


func _in_danger() -> bool:
	return _dead or _recovering or seconds_since_damage() < DANGER_SECONDS or not is_on_floor()


# =====================================================================================================
# Footsteps
# =====================================================================================================

func _on_footstep(_foot: int) -> void:
	if not is_on_floor() or _dead:
		return
	Audio.play_3d("step_" + surface_name(), global_position, -5.0 if _sprinting else -9.0, 0.12, 18.0)


## Surface under Krystal's feet: floor collider meta "surface" (or its parent's), structures = wood,
## otherwise stone in the Below and grass on the surface.
## On surface terrain ("grass" meta) the area's surface_at() refines it (stream water, rocky patches, quarry).
func surface_name() -> String:
	var s := ""
	var c := _floor_collider
	if c != null and is_instance_valid(c):
		if c.has_meta("surface"):
			s = String(c.get_meta("surface"))
		elif c is Node and (c as Node).get_parent() != null and (c as Node).get_parent().has_meta("surface"):
			s = String((c as Node).get_parent().get_meta("surface"))
		elif c is CollisionObject3D and ((c as CollisionObject3D).collision_layer & 32) != 0:
			return "wood"
	if Game.area_id == "below":
		return s if s != "" else "stone"
	if s == "" or s == "grass":
		var a := _current_area()
		if a != null and a.has_method("surface_at"):
			var r: Variant = a.surface_at(global_position)
			if r is String and String(r) != "":
				return String(r)
	return s if s != "" else "grass"


# =====================================================================================================
# Fall recovery
# =====================================================================================================

func _in_world_bounds() -> bool:
	if Game.area_id != "surface":
		return true
	var p := global_position
	return absf(p.x) <= Layout.WORLD_HALF_EXTENT + 2.0 and absf(p.z) <= Layout.WORLD_HALF_EXTENT + 2.0


func _current_area() -> Node:
	if Game.area != null and is_instance_valid(Game.area):
		return Game.area
	return get_tree().current_scene if is_inside_tree() else null


func _check_recovery(dt: float) -> void:
	if _recovering or _dead:
		return
	_ground_check_t -= dt
	if _ground_check_t <= 0.0:
		_ground_check_t = 0.5
		_ground_h = NAN
		# Only consider "below the terrain" while airborne: legit caves under the terrain have floors.
		if _air_time > 0.4 and Game.area_id == "surface":
			var a := _current_area()
			if a != null and a.has_method("height_at"):
				_ground_h = float(a.height_at(global_position.x, global_position.z))
	var reason := Logic.recovery_reason(global_position, Game.area_id, Layout.KILL_Y, Layout.WORLD_HALF_EXTENT, _ground_h, _air_time)
	if reason != "":
		recover(reason)


## Puts Krystal back on the last safe ground (with a quick fade). Awaitable.
func recover(reason: String = "") -> void:
	if _recovering:
		return
	_recovering = true
	recoveries += 1
	_recover_seq += 1
	var seq := _recover_seq
	velocity = Vector3.ZERO
	var dest := _pick_recovery_point()
	var keep_yaw := _facing_yaw
	var ui: Node = Game.ui
	var faded := false
	if ui != null and is_instance_valid(ui) and ui.has_method("fade_out") and is_inside_tree():
		# Failsafe: never leave Krystal frozen if the fade does not finish for any reason.
		get_tree().create_timer(3.0).timeout.connect(_recover_failsafe.bind(seq, dest, keep_yaw))
		await ui.fade_out(0.25)
		faded = true
	if not is_inside_tree() or seq != _recover_seq or not _recovering:
		return
	teleport(Transform3D(Basis(Vector3.UP, keep_yaw), dest))
	var msg := "Oops! Krystal scrambles back to safe ground."
	match reason:
		"outside":
			msg = "The woods end here. Krystal heads back toward the path."
		"below_floor", "falling":
			msg = "Krystal finds her footing again."
	_notify(msg, "info", "recover", 1.0)
	if faded and ui != null and is_instance_valid(ui) and ui.has_method("fade_in"):
		await ui.fade_in(0.35)
	_recovering = false


func _recover_failsafe(seq: int, dest: Vector3, yaw: float) -> void:
	if not is_instance_valid(self) or not is_inside_tree() or seq != _recover_seq or not _recovering:
		return
	teleport(Transform3D(Basis(Vector3.UP, yaw), dest))
	_recovering = false
	var ui: Node = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("fade_in"):
		ui.fade_in(0.35)


func _pick_recovery_point() -> Vector3:
	var a := _current_area()
	var fallback := global_position
	if a != null and a.has_method("get_spawn"):
		var sp := String(GameState.player.get("spawn", "haven_respawn"))
		var xf: Transform3D = a.get_spawn(sp)
		fallback = xf.origin
	var tries := 0
	while _safe.has_point() and tries < 4:
		var cand := _safe.recovery_point(fallback)
		if a != null and a.has_method("validate_position"):
			var ok: Variant = a.validate_position(cand)
			if ok is Vector3:
				return ok
			_safe.drop_last()
			tries += 1
		else:
			return cand
	return fallback
