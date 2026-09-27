extends CharacterBody3D
## Base behaviour for ground enemies (Brambling, Gloomling). A readable, fair state machine:
##   idle -> wander -> chase -> telegraph -> attack -> recover -> chase ...
##   plus flinch (short stagger when hit), stunned, return (leash home), dead.
## Subclasses: extends "res://src/enemies/enemy_base.gd" and override the hooks at the bottom.
## Attacks ONLY the player (target group "player"), never companions.
## All decisions live in tick(delta) so tests can drive the machine with manual delta steps
## (set `target_override` and call tick). Movement happens in _physics_process after tick.

signal defeated
signal state_changed(new_state: String)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Health := preload("res://src/combat/health.gd")
const WORLD_ITEM := "res://src/world/common/world_item.gd"

const GRAVITY := 22.0
const PERCEPTION_INTERVAL := 0.2
const FLINCH_TIME := 0.32
const FLINCH_IMMUNITY := 1.6
const ATTACK_TIME := 0.42            # lunge / swipe duration
const ATTACK_HIT_AT := 0.18          # when the hit resolves inside the attack
const ATTACK_ARC := 80.0
const TELEGRAPH_TRACK := 0.6         # fraction of the telegraph during which it still turns to the player
const TURN_RATE := 7.0
const LEASH_HEAL_PER_SEC := 0.35     # fraction of max hp regained per second while returning home
const LEASH_HEAL_DELAY := 2.5        # no leash healing this soon after taking a hit (no out-healing Krystal)
const THREAT_STATES := ["chase", "telegraph", "attack", "recover", "flinch", "backoff"]

var enemy_id: String = ""
var data: Dictionary = {}
var health: Node
var visual: Node3D
var state: String = "idle"
var state_time: float = 0.0
var home: Vector3 = Vector3.ZERO
var wander_radius: float = 5.0
var target_override: Node3D = null    # tests / scripted fights: the node treated as the player
var spawner: Node = null
var drops_enabled := true
var hit_color: Color = Color(1.0, 0.93, 0.8)
var move_speed_now: float = 0.0       # horizontal speed (read by visuals)
var damage_scale: float = 1.0         # extra per-instance scaling (director / tests)

var _home_set := false
var _perceive_t := 0.0
var _player: Node3D = null
var _player_dist: float = INF
var _player_visible := false
var _can_hunt := false
var _cooldown: float = 0.0
var _flinch_immune: float = 0.0
var _state_len: float = 0.0
var _move_target := Vector3.ZERO
var _desired_vel := Vector3.ZERO
var _knock := Vector3.ZERO
var _attack_dir := Vector3.FORWARD
var _attack_resolved := false
var _lunge_speed: float = 0.0
var _alert_boost: float = 0.0
var _stuck_t: float = 0.0
var _progress_ref := Vector3.ZERO
var _sidestep := Vector3.ZERO
var _sidestep_t: float = 0.0
var _chatter_t: float = 6.0
var _since_hurt: float = 999.0
var _separation := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

static var _enemy_cache: Array = []
static var _enemy_cache_frame: int = -100
## Pack fairness: at most MAX_ATTACKERS enemies wind up / attack at once and their wind-ups start
## at least ATTACK_STAGGER_MS apart. Waiting enemies circle at the edge of their reach.
const MAX_ATTACKERS := 2
const ATTACK_STAGGER_MS := 850
static var _attackers: Dictionary = {}
static var _last_attack_ms: int = -100000
static var _last_attacker: int = 0
static var clock_override_ms: int = -1     # tests: fixed clock for the stagger


static func _now_ms() -> int:
	return clock_override_ms if clock_override_ms >= 0 else Time.get_ticks_msec()


static func reset_attack_tokens() -> void:
	_attackers.clear()
	_last_attack_ms = -100000
	_last_attacker = 0


func _attack_token_available() -> bool:
	for id in _attackers.keys():
		if not is_instance_id_valid(int(id)):
			_attackers.erase(id)
	if _attackers.has(get_instance_id()):
		return true
	if _attackers.size() >= MAX_ATTACKERS:
		return false
	if _last_attacker == get_instance_id():
		return true                     # the stagger only spaces out *different* attackers
	return _now_ms() - _last_attack_ms >= ATTACK_STAGGER_MS


func setup(params: Dictionary) -> void:
	if params.has("enemy"):
		enemy_id = String(params["enemy"])
	var h: Variant = params.get("home")
	if h is Vector3:
		home = h
		_home_set = true
	wander_radius = float(params.get("wander_radius", params.get("radius", wander_radius)))
	var sp: Variant = params.get("spawner")
	if sp is Node:
		spawner = sp
	drops_enabled = not bool(params.get("no_drops", false))
	if bool(params.get("alert", false)):
		_alert_boost = 12.0
	damage_scale = float(params.get("damage_scale", damage_scale))


func _ready() -> void:
	if enemy_id == "":
		enemy_id = _default_id()
	data = ItemDB.enemy(enemy_id)
	add_to_group("enemy")
	collision_layer = 8
	collision_mask = 1 | 32
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _body_radius()
	cap.height = maxf(_body_height(), cap.radius * 2.0)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	health = Health.new()
	health.name = "Health"
	health.max_hp = float(data.get("hp", 30.0))
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	visual = _build_visual()
	if visual != null:
		add_child(visual)
	if not _home_set:
		home = global_position
	_rng.randomize()
	_cooldown = 0.8
	_chatter_t = _rng.randf_range(4.0, 10.0)
	_enter("idle", _rng.randf_range(0.6, 2.2))
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	HitFx.ensure_hitstop()


func _physics_process(delta: float) -> void:
	tick(delta)
	_apply_movement(delta)


func _exit_tree() -> void:
	_attackers.erase(get_instance_id())


# --- Public API -------------------------------------------------------------------------------------

func is_threatening() -> bool:
	return state in THREAT_STATES and not is_dead()


func is_dead() -> bool:
	return state == "dead" or (health != null and health.dead)


func knockback(dir: Vector3, force: float) -> void:
	if is_dead():
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		return
	_knock = d.normalized() * force * _knockback_scale()


func stun(seconds: float) -> void:
	if is_dead():
		return
	_enter("stunned", seconds)


## Point used for attacks aimed at this enemy.
func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * (_body_height() * 0.55)


## Small grow-in when a spawner creates it (avoids a harsh pop).
func pop_in() -> void:
	if visual == null:
		return
	visual.scale = Vector3.ONE * 0.2
	var tw := visual.create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func telegraph_duration() -> float:
	return float(data.get("telegraph", 0.7))


func recover_duration() -> float:
	return float(data.get("recover", 1.0))


func attack_damage() -> float:
	return float(data.get("damage", 10.0)) * Combat.damage_mult_for_area(String(data.get("area", ""))) * damage_scale


# --- State machine ------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if state == "dead":
		return
	state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_flinch_immune = maxf(_flinch_immune - delta, 0.0)
	_alert_boost = maxf(_alert_boost - delta, 0.0)
	_since_hurt += delta
	_perceive_t -= delta
	if _perceive_t <= 0.0:
		_perceive_t = PERCEPTION_INTERVAL
		_perceive()
	_desired_vel = Vector3.ZERO
	_tick_extra(delta)
	match state:
		"idle":
			_st_idle(delta)
		"wander":
			_st_wander(delta)
		"chase":
			_st_chase(delta)
		"telegraph":
			_st_telegraph(delta)
		"attack":
			_st_attack(delta)
		"recover":
			_st_recover(delta)
		"flinch":
			if state_time >= FLINCH_TIME:
				_resume_after_interrupt()
		"stunned":
			if state_time >= _state_len:
				_resume_after_interrupt()
		"return":
			_st_return(delta)
		_:
			_st_custom(state, delta)
	_chatter_t -= delta
	if _chatter_t <= 0.0:
		_chatter_t = _rng.randf_range(7.0, 14.0)
		if state in ["idle", "wander"] and _player_dist < 22.0:
			_idle_sound()


func _enter(new_state: String, length: float = 0.0) -> void:
	var prev := state
	state = new_state
	state_time = 0.0
	_state_len = length
	if new_state == "telegraph":
		_attackers[get_instance_id()] = true
		_last_attack_ms = _now_ms()
		_last_attacker = get_instance_id()
	elif new_state != "attack":
		_attackers.erase(get_instance_id())
	match new_state:
		"telegraph":
			_attack_resolved = false
			_on_telegraph_start()
		"attack":
			_attack_resolved = false
			var dist := _flat_dist_to_player()
			var lunge := clampf(dist - 0.75, 0.0, _lunge_distance())
			_lunge_speed = lunge / (ATTACK_TIME * 0.6)
			_on_attack_start()
		"recover":
			_cooldown = float(data.get("cooldown", 1.5))
		"chase":
			if prev in ["idle", "wander", "return"]:
				_on_alert()
		"wander":
			var a := _rng.randf_range(0.0, TAU)
			var r := sqrt(_rng.randf()) * wander_radius
			_move_target = home + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if visual != null and visual.has_method("set_state"):
		visual.set_state(new_state, length)
	state_changed.emit(new_state)


func _st_idle(_delta: float) -> void:
	if _should_aggro():
		_enter("chase")
	elif state_time >= _state_len:
		_enter("wander")


func _st_wander(delta: float) -> void:
	if _should_aggro():
		_enter("chase")
		return
	var to := _move_target - global_position
	to.y = 0.0
	if to.length() < 0.5 or state_time > 7.0:
		_enter("idle", _rng.randf_range(1.5, 3.8))
		return
	_steer(to.normalized(), float(data.get("speed", 3.0)) * 0.55, delta)


func _st_chase(delta: float) -> void:
	if not _chase_valid():
		_enter("return")
		return
	var to := _player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else _forward()
	var reach := float(data.get("attack_range", 1.8))
	if dist <= reach and _cooldown <= 0.0 and _can_start_attack():
		if _attack_token_available():
			_face(dir, delta, 3.0)
			_enter("telegraph", telegraph_duration())
			return
		# Someone else is winding up: circle at the edge of reach instead of piling in.
		var tangent := Vector3(-dir.z, 0.0, dir.x) * (1.0 if (get_instance_id() % 2) == 0 else -1.0)
		var back := -dir * clampf(reach * 0.9 - dist, 0.0, 1.0)
		_desired_vel = (tangent * 0.8 + back).normalized() * float(data.get("speed", 3.0)) * 0.45
		_face(dir, delta)
		return
	var speed := float(data.get("chase_speed", 4.0)) * _speed_scale()
	if dist > reach * 0.8:
		_steer(dir, speed, delta)
	else:
		_face(dir, delta)


func _st_telegraph(delta: float) -> void:
	if not _can_hunt or _player == null or not is_instance_valid(_player):
		_enter("return")
		return
	if state_time <= _state_len * TELEGRAPH_TRACK:
		var to := _player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.01:
			_face(to.normalized(), delta, 1.4)
	if state_time >= _state_len:
		_attack_dir = _forward()
		_enter("attack", ATTACK_TIME)


func _st_attack(_delta: float) -> void:
	if state_time < ATTACK_TIME * 0.6:
		_desired_vel = _attack_dir * _lunge_speed
	if not _attack_resolved and state_time >= ATTACK_HIT_AT:
		_attack_resolved = true
		var origin := global_position + Vector3.UP * (_body_height() * 0.5)
		var hits: Array = Combat.melee(self, origin, _attack_dir, float(data.get("attack_range", 1.8)) + 0.2, ATTACK_ARC,
			attack_damage(), ["player"], float(data.get("knockback", 5.0)))
		_on_attack_resolved(hits)
	if state_time >= ATTACK_TIME:
		_enter("recover", recover_duration())


func _st_recover(_delta: float) -> void:
	if state_time >= _state_len:
		_resume_after_interrupt()


func _st_return(delta: float) -> void:
	if _should_aggro() and _player_within_leash():
		_enter("chase")
		return
	if health != null and not health.dead and health.hp < health.max_hp and _since_hurt >= LEASH_HEAL_DELAY:
		health.heal(health.max_hp * LEASH_HEAL_PER_SEC * delta)
	var to := home - global_position
	to.y = 0.0
	if to.length() < 1.0 or state_time > 20.0:
		if state_time > 20.0 and to.length() > 3.0:
			global_position = home
		_enter("idle", _rng.randf_range(1.0, 2.5))
		return
	_steer(to.normalized(), float(data.get("speed", 3.0)), delta)


func _resume_after_interrupt() -> void:
	if _chase_valid():
		_enter("chase")
	elif (global_position - home).length() > wander_radius + 2.0:
		_enter("return")
	else:
		_enter("idle", _rng.randf_range(0.8, 2.0))


# --- Perception -------------------------------------------------------------------------------------------

func _perceive() -> void:
	_player = _find_player()
	if _player == null:
		_can_hunt = false
		_player_dist = INF
		_player_visible = false
		_perceive_extra()
		return
	_player_dist = global_position.distance_to(_player.global_position)
	_can_hunt = hunt_allowed(_player)
	_player_visible = _player_dist <= aggro_radius() * 2.2 and _line_of_sight(_player)
	_perceive_extra()


func _find_player() -> Node3D:
	if target_override != null:
		return target_override if is_instance_valid(target_override) else null
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	if not is_inside_tree():
		return null
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] as Node3D if not ps.is_empty() else null


## Whether this enemy may hunt the given player right now (alive, not respawning, not in a safe zone).
func hunt_allowed(p: Node3D) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	if Game.mode == "dead" or Game.mode == "cutscene" or Game.mode == "loading" or Game.mode == "title":
		return false
	var h := Combat.find_health(p)
	if h != null and Combat.truthy(h.get("dead")):
		return false
	if Combat.truthy(p.get("is_respawning")):
		return false
	var a: Node = Game.area
	if a != null and is_instance_valid(a) and a.has_method("is_safe_zone"):
		if bool(a.is_safe_zone(p.global_position)):
			return false
	return true


func aggro_radius() -> float:
	return float(data.get("aggro_radius", 9.0)) + _alert_boost


func _should_aggro() -> bool:
	return _can_hunt and _player != null and _player_visible and _player_dist <= aggro_radius() and _player_within_leash()


func _player_within_leash() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return home.distance_to(_player.global_position) <= float(data.get("leash_radius", 22.0))


func _chase_valid() -> bool:
	if not _can_hunt or _player == null or not is_instance_valid(_player):
		return false
	if not _player_within_leash():
		return false
	if global_position.distance_to(home) > float(data.get("leash_radius", 22.0)) + 4.0:
		return false
	return _player_dist <= aggro_radius() * 2.2


func _line_of_sight(p: Node3D) -> bool:
	if not is_inside_tree():
		return true
	var from := global_position + Vector3.UP * (_body_height() * 0.7)
	var to := p.global_position + Vector3.UP * 0.9
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, from, to, [self, p], 1)


func _flat_dist_to_player() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var d := _player.global_position - global_position
	d.y = 0.0
	return d.length()


# --- Movement helpers --------------------------------------------------------------------------------------

func _forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _face(dir: Vector3, delta: float, rate_mult: float = 1.0) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_RATE * rate_mult * delta, 0.0, 1.0))


func _steer(dir: Vector3, speed: float, delta: float) -> void:
	var d := dir
	if _sidestep_t > 0.0:
		_sidestep_t -= delta
		d = (dir * 0.35 + _sidestep).normalized()
	_desired_vel = d * speed
	_face(d, delta)


func _apply_movement(delta: float) -> void:
	if state == "dead":
		velocity = Vector3.ZERO
		return
	var v := _desired_vel + _separation_push()
	v += _knock
	_knock *= exp(-7.0 * delta)
	if _knock.length_squared() < 0.01:
		_knock = Vector3.ZERO
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	move_speed_now = Vector2(velocity.x, velocity.z).length()
	# Stuck detection while trying to move: sidestep around the obstacle for a moment.
	if _desired_vel.length_squared() > 0.5:
		_stuck_t += delta
		if _stuck_t > 0.8:
			if global_position.distance_to(_progress_ref) < 0.35:
				var side := Vector3(-_desired_vel.z, 0.0, _desired_vel.x).normalized()
				_sidestep = side if _rng.randf() < 0.5 else -side
				_sidestep_t = 0.7
			_progress_ref = global_position
			_stuck_t = 0.0
	# Fell out of the world: go home.
	if global_position.y < home.y - 25.0:
		global_position = home + Vector3.UP * 0.5
		velocity = Vector3.ZERO


## Gentle push away from other enemies so a pack doesn't stack into one blob.
func _separation_push() -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame - _enemy_cache_frame > 20:
		_enemy_cache_frame = frame
		_enemy_cache = get_tree().get_nodes_in_group("enemy")
	var push := Vector3.ZERO
	for e in _enemy_cache:
		if e == self or not is_instance_valid(e) or not (e is CharacterBody3D):
			continue
		var d: Vector3 = global_position - (e as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.001 and l < 1.3:
			push += d / l * (1.3 - l) * 2.5
	return push


# --- Damage & defeat ------------------------------------------------------------------------------------------

func _on_damaged(amount: float, source: Node, _dir: Vector3) -> void:
	HitFx.flash(self)
	HitFx.number(get_aim_point() + Vector3.UP * 0.5, amount)
	_on_hurt(amount)
	_since_hurt = 0.0
	# Health emits `damaged` before it flags `dead`: a killing blow must not start a flinch/chase.
	if health.dead or health.hp <= 0.0:
		return
	if source != null and is_instance_valid(source) and source is Node3D and source.is_in_group("player"):
		_player = source as Node3D
		_player_visible = true
		_alert_boost = maxf(_alert_boost, 6.0)
	if state == "attack" or state == "recover" or state == "stunned":
		return
	if _flinch_immune <= 0.0:
		_flinch_immune = FLINCH_IMMUNITY
		_enter("flinch", FLINCH_TIME)
	elif state in ["idle", "wander", "return"]:
		_enter("chase")


func _on_died() -> void:
	if state == "dead":
		return
	_enter("dead")
	collision_layer = 0
	remove_from_group("enemy")
	var pos := global_position
	if drops_enabled:
		_drop_loot(pos)
	GameState.stats["enemies_defeated"] = int(GameState.stats.get("enemies_defeated", 0)) + 1
	Events.enemy_killed.emit(enemy_id, pos)
	Audio.play_3d("enemy_defeat", pos, -2.0)
	defeated.emit()
	if is_inside_tree():
		await _play_defeat()
	queue_free()


## Rolls a drop table [{item, min, max, chance}] -> [{item, count}] (pure; used by tests).
static func roll_drops(drops: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for d in drops:
		if not (d is Dictionary):
			continue
		if rng.randf() > float(d.get("chance", 1.0)):
			continue
		var n := rng.randi_range(int(d.get("min", 1)), maxi(int(d.get("max", 1)), int(d.get("min", 1))))
		if n > 0:
			out.append({"item": String(d.get("item", "")), "count": n})
	return out


func _drop_loot(pos: Vector3) -> void:
	for d in roll_drops(data.get("drops", []), _rng):
		give_drop(String(d["item"]), int(d["count"]), pos + Vector3.UP * 0.4)


## World item pickup if the world module offers static spawn(item, count, pos); otherwise straight
## into the inventory (GameState handles overflow as persistent pickups).
static func give_drop(item: String, count: int, pos: Vector3) -> void:
	if item == "" or count <= 0 or not ItemDB.has_item(item):
		return
	if ResourceLoader.exists(WORLD_ITEM):
		var s: Script = load(WORLD_ITEM)
		if s != null and s.can_instantiate() and s.has_method("spawn"):
			for m in s.get_script_method_list():
				if String(m.get("name", "")) == "spawn" and (m.get("args", []) as Array).size() >= 3:
					var n: Variant = s.call("spawn", item, count, pos)
					if n != null:
						return
					break
	GameState.give_item(item, count, pos)


func _on_player_died() -> void:
	if state in ["chase", "telegraph", "flinch", "backoff"]:
		_enter("return")


# --- Hooks for subclasses ---------------------------------------------------------------------------------------

func _default_id() -> String:
	return "brambling"


func _build_visual() -> Node3D:
	return null


func _body_radius() -> float:
	return 0.4


func _body_height() -> float:
	return 1.0


func _lunge_distance() -> float:
	return 1.2


func _speed_scale() -> float:
	return 1.0


func _knockback_scale() -> float:
	return 1.0


func _can_start_attack() -> bool:
	return true


func _perceive_extra() -> void:
	pass


func _tick_extra(_delta: float) -> void:
	pass


func _st_custom(_state_name: String, _delta: float) -> void:
	pass


func _on_alert() -> void:
	pass


func _on_telegraph_start() -> void:
	pass


func _on_attack_start() -> void:
	pass


func _on_attack_resolved(_hits: Array) -> void:
	pass


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position, -3.0)


func _idle_sound() -> void:
	pass


## Defeat animation (coroutine). Default: shrink away.
func _play_defeat() -> void:
	if visual == null:
		return
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tw.finished
