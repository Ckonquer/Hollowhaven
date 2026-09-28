extends CharacterBody3D
## Base behaviour for ground enemies (Brambling, Gloomling). A readable, fair state machine:
##   idle -> wander -> chase -> telegraph -> attack -> recover -> chase ...
##   plus flinch (short stagger when hit), stunned, return (leash home), dead.
## Subclasses: extends "res://src/enemies/enemy_base.gd" and override the hooks at the bottom.
## Attacks ONLY the player (target group "player"), never companions.
## All decisions live in tick(delta) so tests can drive the machine with manual delta steps
## (set `target_override` and call tick). Movement happens in _physics_process after tick.
##
## Chapter Two shared mechanics (ADDITIVE: with the defaults every legacy enemy behaves exactly as before):
##   committed_states          custom attack states (charge, leap, swing...) that keep the attack token (the
##                             MAX_ATTACKERS cap counts them), count as threatening and are never flinched
##   attack_reach() / _choose_attack() / _telegraph_finished()   hooks around the chase -> telegraph -> attack step
##   attack_def(id), attack_telegraph(def), attack_recover(def), attack_damage_for(def)   data/enemies.gd "attacks"
##   can_be_hit_by(source), can_stagger(amount, source), _is_uninterruptible(), _stagger(...)
##   mark() / hide_mark()      this enemy's ground telegraph (src/enemies/telegraph_fx.gd)
##   charge_begin/charge_step, leap_begin/leap_step/leap_land_hit, lane_clip, lane_hits, pulse_hits,
##   deal_damage_to, fire_projectile (params dir / on_hit / kind pass through), apply_slow (static), announce_tell
##   intensity_cooldown_mult(), intensity_telegraph_bonus(), overlap_blocked()   OPT-IN horror-intensity rules of the
##                             Chapter Two ordinary enemies (Gentle: wind-ups +0.2 s, rests x1.35, never winds up while
##                             another enemy winds up; Intense: rests x0.8; tells never shorter). Legacy / Chapter One
##                             extra enemies never call them, so they keep their behaviour.
##   claim_attack_token(id) / release_attack_token(id) (static)   the shared MAX_ATTACKERS table for attackers that are
##                             not enemy_base nodes (the Borrowed Choir); same cap and stagger rule as a wind-up
##   setup key "defeat_flag"   flag set once when this enemy is defeated (content modules)

signal defeated
signal state_changed(new_state: String)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Health := preload("res://src/combat/health.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const WORLD_ITEM := "res://src/world/common/world_item.gd"
const LOCAL_PROJECTILE := "res://src/enemies/enemy_projectile.gd"
const SHARED_PROJECTILE := "res://src/combat/projectile.gd"

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
# Chapter Two shared mechanics
const MIN_COMMITTED_TELEGRAPH := 1.0 # committed attacks never wind up faster than this (MP 8 / 12)
const TARGET_BODY_RADIUS := 0.35     # Krystal's body radius for lane / landing hit tests
const SLOW_MIN_MULT := 0.5           # the strongest slow an enemy may apply (spec 9: bounded)
const SLOW_MAX_SECONDS := 3.0
const CAPTION_GAP_MS := 6000
# Chapter Two horror-intensity rules (opt-in helpers below; the C5 enemies use them)
const INTENSITY_GENTLE_REST := 1.35        # Gentle: every rest (cooldown after an attack) x this
const INTENSITY_INTENSE_REST := 0.8        # Intense: shorter rests (never faster, never invisible tells)
const INTENSITY_GENTLE_TELL_BONUS := 0.2   # Gentle: every wind-up + this (seconds)

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

# --- Chapter Two shared mechanics (defaults keep the legacy behaviour) ---
var committed_states: Array = []      # subclass: custom committed attack states (see header)
var needs_clear_shot := false         # subclass: perception also checks a world|structure line to the target
var defeat_flag: String = ""          # setup key: flag set once when this enemy is defeated
var _shot_clear := true
var _mark: Node3D = null
var _leap_active := false
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _leap_t: float = 0.0
var _leap_len: float = 0.4
var _leap_height: float = 0.8
var _charge_active := false
var _charge_dir := Vector3.FORWARD
var _charge_len: float = 0.0
var _charge_travel: float = 0.0
var _charge_speed: float = 0.0
var _charge_wall := false
var _charge_hit := false

static var _slow_immune_until_ms: int = -1
static var _told: Dictionary = {}        # hint ids already emitted this session
static var _captioned: Dictionary = {}   # enemy id -> last caption msec

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
	_slow_immune_until_ms = -1              # Chapter Two: shared slow immunity (tests / area loads)


func _attack_token_available() -> bool:
	return attack_token_available_for(get_instance_id())


## May instance `id` hold an attack token now? True when it already holds one; else a slot must be free
## (MAX_ATTACKERS) and, unless `id` was the last attacker, ATTACK_STAGGER_MS must have passed since the last wind-up
## began. Tokens of freed instances are dropped first. No side effects besides that clean-up.
static func attack_token_available_for(id: int) -> bool:
	for k in _attackers.keys():
		if not is_instance_id_valid(int(k)):
			_attackers.erase(k)
	if _attackers.has(id):
		return true
	if _attackers.size() >= MAX_ATTACKERS:
		return false
	if _last_attacker == id:
		return true                     # the stagger only spaces out *different* attackers
	return _now_ms() - _last_attack_ms >= ATTACK_STAGGER_MS


## Claims a slot of the shared attack-token table for instance `id` (an attacker that is not an enemy_base node,
## e.g. the Borrowed Choir while it is committed). Same rules as an enemy's wind-up: refused while MAX_ATTACKERS
## others hold one or inside the stagger of a different attacker's wind-up. A NEW claim starts the stagger clock
## (like entering "telegraph"); re-claiming a held token changes nothing. Returns whether `id` holds a token.
static func claim_attack_token(id: int) -> bool:
	if not attack_token_available_for(id):
		return false
	if not _attackers.has(id):
		_attackers[id] = true
		_last_attack_ms = _now_ms()
		_last_attacker = id
	return true


## Gives back the token of instance `id` (no-op when it holds none).
static func release_attack_token(id: int) -> void:
	_attackers.erase(id)


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
	defeat_flag = String(params.get("defeat_flag", defeat_flag))


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
	health = _make_health()
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
	return (state in THREAT_STATES or state in committed_states) and not is_dead()


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
	_leap_active = false                    # a new state always ends a leap / charge in progress
	_charge_active = false
	if _mark != null and new_state != "telegraph" and not (new_state in committed_states):
		hide_mark()
	if new_state == "telegraph":
		_attackers[get_instance_id()] = true
		_last_attack_ms = _now_ms()
		_last_attacker = get_instance_id()
	elif new_state != "attack" and not (new_state in committed_states):
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
	_on_state_changed(prev, new_state)
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
	var reach := attack_reach()
	if dist <= reach and _cooldown <= 0.0 and _can_start_attack():
		if _attack_token_available():
			_face(dir, delta, 3.0)
			_choose_attack()
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
		_telegraph_finished()


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
	if needs_clear_shot:
		_shot_clear = _player_visible and _can_hunt and has_clear_shot(_player)
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
	if _leap_active:
		velocity = Vector3.ZERO             # leaps are kinematic (leap_step moves the body inside tick)
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
	if _is_uninterruptible():
		return
	if can_stagger(amount, source):
		_stagger(amount, source)
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
	if defeat_flag != "":
		GameState.set_flag(defeat_flag, true)
	GameState.stats["enemies_defeated"] = int(GameState.stats.get("enemies_defeated", 0)) + 1
	Events.enemy_killed.emit(enemy_id, pos)
	Audio.play_3d(_defeat_sound(), pos, -2.0)
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
	if state in ["chase", "telegraph", "flinch", "backoff"] or state in committed_states:
		_enter("return")


# --- Chapter Two shared mechanics ----------------------------------------------------------------------------------

## Whether `source` may damage this enemy right now (spec 9: companion attacks and projectiles respect it).
## False when defeated or invulnerable; enemies never damage each other.
func can_be_hit_by(source: Node) -> bool:
	if is_dead() or health == null or bool(health.invulnerable):
		return false
	if source != null and is_instance_valid(source) and source != self and source.is_in_group("enemy"):
		return false
	return true


## Stagger eligibility: may a non-lethal hit of `amount` from `source` interrupt the current state with a
## flinch? Default = the legacy rule (not within FLINCH_IMMUNITY of the previous flinch).
func can_stagger(_amount: float, _source: Node) -> bool:
	return _flinch_immune <= 0.0


## The node this enemy hunts right now (Game.player or target_override), or null.
func current_target() -> Node3D:
	return _player if _player != null and is_instance_valid(_player) else null


## Faction / target filter: only Krystal (group "player", or the scripted target_override) can be damaged by
## enemy attacks. Companions, wildlife, decorations and other enemies never are.
func is_valid_victim(t: Node) -> bool:
	if t == null or not is_instance_valid(t) or t == self:
		return false
	if t == target_override:
		return true
	return t.is_in_group("player") and not t.is_in_group("companion") and not t.is_in_group("enemy")


## One entry of data "attacks" by id ({} if missing). Allocation-free (chase reach checks call it every tick).
func attack_def(attack_id: String) -> Dictionary:
	var list: Variant = data.get("attacks")
	if list is Array:
		for a in list:
			if a is Dictionary and (a as Dictionary).get("id") == attack_id:
				return a
	return {}


## Wind-up of an attack from data, never shorter than MIN_COMMITTED_TELEGRAPH (readable committed attacks).
func attack_telegraph(def: Dictionary) -> float:
	return maxf(float(def.get("telegraph", data.get("telegraph", MIN_COMMITTED_TELEGRAPH))), MIN_COMMITTED_TELEGRAPH)


func attack_recover(def: Dictionary) -> float:
	return float(def.get("recover", data.get("recover", 1.0)))


## Horror intensity x rest (OPT-IN, Chapter Two ordinary enemies): Gentle INTENSITY_GENTLE_REST (1.35), Standard 1,
## Intense INTENSITY_INTENSE_REST (0.8). Multiply the cooldown that starts with a recovery by it.
func intensity_cooldown_mult() -> float:
	match Combat.current_intensity():
		0:
			return INTENSITY_GENTLE_REST
		2:
			return INTENSITY_INTENSE_REST
	return 1.0


## Horror intensity + wind-up (OPT-IN): Gentle adds INTENSITY_GENTLE_TELL_BONUS (0.2 s); Standard / Intense add
## nothing (Intense never shortens a tell). Add it to attack_telegraph(def), which keeps the 1.0 s committed floor.
func intensity_telegraph_bonus() -> float:
	return INTENSITY_GENTLE_TELL_BONUS if Combat.current_intensity() == 0 else 0.0


## Gentle "no overlapping attacks" (OPT-IN): true while another enemy holds an attack token (winds up / attacks),
## so this one must not start a wind-up. Always false on Standard / Intense (the MAX_ATTACKERS cap still applies).
func overlap_blocked() -> bool:
	if Combat.current_intensity() != 0:
		return false
	for id in _attackers.keys():
		if int(id) != get_instance_id() and is_instance_id_valid(int(id)):
			return true
	return false


## Damage of an attack: data damage x horror intensity (underground threats only) x damage_scale.
func attack_damage_for(def: Dictionary) -> float:
	return float(def.get("damage", data.get("damage", 10.0))) * threat_damage_mult() * damage_scale


## Horror-intensity damage multiplier (Gentle 0.6 / Standard 1.0 / Intense 1.15) for the attacks above.
## It follows WHERE the enemy fights (spec 9: underground areas scale, the surface / Reach / interiors never):
## while Game.area_id is a real area (Game.AREAS) other than a transient one (the Echo Trial replays every
## area's fights), Combat.damage_mult_for_area(Game.area_id) decides, so a Hollow Drudge in the Reach's
## candle yard hits like a surface threat and a Brood Skitter in the Works like an underground one.
## In the Echo Trial and without a real area (tests, previews) the data rule stays: enemies marked
## "underground" in data (and legacy "below" ones) scale, everything else does not.
## Legacy enemies are untouched: their attacks go through attack_damage() (data area), not this.
func threat_damage_mult() -> float:
	var here: String = Game.area_id
	if here != "" and Game.AREAS.has(here) and not Game.TRANSIENT_AREAS.has(here):
		return Combat.damage_mult_for_area(here)
	if bool(data.get("underground", false)) or String(data.get("area", "")) == "below":
		return Combat.intensity_damage_mult(Combat.current_intensity())
	return 1.0


## Where this enemy's attacks and shot checks start.
func attack_origin() -> Vector3:
	return global_position + Vector3.UP * (_body_height() * 0.6)


## A clear world|structure line from `from` (default attack_origin()) to `t`'s aim point. One ray: call it at
## decisions (perception, wind-up start, release), never every frame.
func has_clear_shot(t: Node3D, from: Vector3 = Vector3.INF) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if not is_inside_tree() or not t.is_inside_tree():
		return true
	var o := attack_origin() if not from.is_finite() else from
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, o, Combat.aim_point(t), [self, t], Combat.LOS_MASK)


## Clips a flat lane from `from` along `dir` against world|structure (one ray at `height`).
## Returns {"length": clipped length (a body radius short of the obstacle), "wall": true when a wall - not a
## walkable slope - ended the lane early}.
func lane_clip(from: Vector3, dir: Vector3, length: float, height: float = 0.6) -> Dictionary:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001 or length <= 0.0 or not is_inside_tree():
		return {"length": maxf(length, 0.0), "wall": false}
	d = d.normalized()
	var o := from + Vector3.UP * height
	var q := PhysicsRayQueryParameters3D.create(o, o + d * (length + _body_radius()), Combat.LOS_MASK)
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"length": length, "wall": false}
	var hp: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var dist := Vector2(hp.x - o.x, hp.z - o.z).length()
	return {"length": clampf(dist - _body_radius() - 0.05, 0.0, length), "wall": n.y < 0.6}


## Dash-line / lane helper: is `t` inside the lane a-b (`half_width` either side plus her body radius), at a
## reachable height, with no wall between the lane and her?
func lane_hits(t: Node3D, a: Vector3, b: Vector3, half_width: float, max_dy: float = 1.4) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var p := t.global_position
	var c := TelegraphFx.closest_on_segment(a, b, p)
	if absf(p.y - c.y) > max_dy:
		return false
	if Vector2(p.x - c.x, p.z - c.z).length() > half_width + TARGET_BODY_RADIUS:
		return false
	return has_clear_shot(t, c + Vector3.UP * 0.6)


## Radial pulse (full circle, LOS-checked) of `radius` around `center`; only the player group is hit.
func pulse_hits(center: Vector3, radius: float, damage: float, knockback_force: float) -> Array:
	return Combat.melee(self, center + Vector3.UP * 0.8, _forward(), radius, 360.0, damage, ["player"], knockback_force)


## Applies ONE hit to `t` through its health (dodge i-frames, armour and shields apply there), with knockback,
## impact feedback and a tiny hitstop. Returns the damage dealt (0 = dodged / blocked / not a valid victim).
func deal_damage_to(t: Node3D, damage: float, dir: Vector3, knockback_force: float) -> float:
	if not is_valid_victim(t) or damage <= 0.0:
		return 0.0
	var h := Combat.find_health(t)
	if h == null:
		return 0.0
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else _forward()
	var dealt := float(h.apply_damage(damage, self, d))
	if dealt <= 0.0:
		if t.has_method("on_hit_blocked"):
			t.on_hit_blocked(self, d)
		return 0.0
	if knockback_force > 0.0 and t.has_method("knockback"):
		t.knockback(d, knockback_force)
	var col: Variant = t.get("hit_color")
	HitFx.impact(Combat.aim_point(t) - d * 0.25, dealt, col if col is Color else HitFx.DEFAULT_IMPACT)
	Events.hitstop.emit(Combat.HITSTOP_HEAVY if dealt >= 15.0 else Combat.HITSTOP_LIGHT)
	return dealt


## Starts a committed straight charge along `dir` (call right after entering the charge state). The lane is
## clipped once against world|structure; returns its length.
func charge_begin(dir: Vector3, distance: float, speed: float) -> float:
	var d := Vector3(dir.x, 0.0, dir.z)
	_charge_dir = d.normalized() if d.length_squared() > 0.0001 else _forward()
	_charge_speed = maxf(speed, 0.1)
	var clip := lane_clip(global_position, _charge_dir, distance)
	_charge_len = float(clip["length"])
	_charge_wall = bool(clip["wall"])
	_charge_travel = 0.0
	_charge_hit = false
	_charge_active = true
	_attack_dir = _charge_dir
	return _charge_len


## One charge tick: runs along the lane and hits the target at most once when she is in the lane just ahead
## (`hit_ahead` metres beyond the body, `half_width` either side). Returns "run" (still going), "hit" (struck
## her: the charge ends), "wall" (bonked into a wall / structure: the charge ends early) or "done" (lane end).
## A dodged hit (i-frames) lets the charge run on and never re-tests her.
func charge_step(delta: float, hit_ahead: float, half_width: float, damage: float, knockback_force: float) -> String:
	if not _charge_active:
		return "done"
	_desired_vel = _charge_dir * _charge_speed
	_face(_charge_dir, delta, 3.0)
	_charge_travel += _charge_speed * delta
	var t := current_target()
	if not _charge_hit and t != null and is_valid_victim(t):
		var a := global_position
		var b := a + _charge_dir * (_body_radius() + hit_ahead)
		if lane_hits(t, a, b, half_width):
			_charge_hit = true
			var lat := Vector3(-_charge_dir.z, 0.0, _charge_dir.x)
			var s := signf(lat.dot(t.global_position - a))
			var kdir := (_charge_dir + lat * (s if s != 0.0 else 1.0) * 0.7).normalized()
			if deal_damage_to(t, damage, kdir, knockback_force) > 0.0:
				_charge_active = false
				return "hit"
	if is_inside_tree() and _charge_travel > 0.4 and is_on_wall():
		_charge_active = false
		return "wall"
	if _charge_travel >= _charge_len:
		_charge_active = false
		return "wall" if _charge_wall else "done"
	return "run"


## End point of the current / planned charge lane.
func charge_lane_end() -> Vector3:
	return global_position + _charge_dir * _charge_len


## Starts a kinematic leap toward `to` (flat distance capped at `max_distance`, stopped short of walls) that
## lasts `duration` s with apex `height`. Returns the landing point. Call right after entering the leap state;
## leap_step() then moves the body inside tick (no move_and_slide while airborne).
func leap_begin(to: Vector3, duration: float, height: float, max_distance: float = INF) -> Vector3:
	var from := global_position
	var land := leap_target(to, max_distance)
	var flat := Vector3(land.x - from.x, 0.0, land.z - from.z)
	var dir := flat.normalized() if flat.length_squared() > 0.000001 else _forward()
	_leap_from = from
	_leap_to = land
	_leap_len = maxf(duration, 0.05)
	_leap_height = height
	_leap_t = 0.0
	_leap_active = true
	_attack_dir = dir
	return land


## Where a leap toward `to` would land: flat distance capped at `max_distance`, stopped a body radius short of
## any wall or structure in between (one ray). Use it to place the landing mark before the leap starts.
func leap_target(to: Vector3, max_distance: float = INF) -> Vector3:
	var from := global_position
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var want := flat.length()
	var dir := flat / want if want > 0.001 else _forward()
	var dist := minf(want, max_distance)
	var got := float(lane_clip(from, dir, dist, 0.5)["length"])
	var land := from + dir * got
	if got < dist - 0.01:
		land.y = from.y                                          # stopped short by a wall: stay on its own level
	elif dist < want - 0.01:
		land.y = lerpf(from.y, to.y, dist / want)                # capped short of `to`: follow the slope toward it
	else:
		land.y = to.y
	return land


## One leap tick along the arc. True on the tick it lands.
func leap_step(delta: float) -> bool:
	if not _leap_active:
		return false
	_leap_t = minf(_leap_t + delta, _leap_len)
	var k := _leap_t / _leap_len
	var p := _leap_from.lerp(_leap_to, k)
	p.y += sin(k * PI) * _leap_height
	global_position = p
	move_speed_now = _leap_from.distance_to(_leap_to) / _leap_len
	if k >= 1.0:
		_leap_active = false
		return true
	return false


## Landing hit: damages the target once if she stands within `radius` (+ her body) of where it landed, at a
## reachable height, with a clear line. Returns the damage dealt.
func leap_land_hit(radius: float, damage: float, knockback_force: float) -> float:
	var t := current_target()
	if t == null or not is_valid_victim(t):
		return 0.0
	var c := global_position
	var p := t.global_position
	if absf(p.y - c.y) > 1.3:
		return 0.0
	if Vector2(p.x - c.x, p.z - c.z).length() > radius + TARGET_BODY_RADIUS:
		return 0.0
	if not has_clear_shot(t, c + Vector3.UP * 0.5):
		return 0.0
	var dir := Vector3(p.x - c.x, 0.0, p.z - c.z)
	return deal_damage_to(t, damage, dir if dir.length_squared() > 0.0001 else _attack_dir, knockback_force)


## Fires one projectile at `t` from `from`: the shared pooled src/combat/projectile.gd (spec 9) when it is
## present, else the local src/enemies/enemy_projectile.gd. Either way it is parented to the area (never to
## the shooter, so it outlives a defeated shooter), checks walls on every step, targets only group "player",
## damages at most once and the number alive is capped. params: damage, speed, range, knockback, color, radius,
## homing (local only), max_per_shooter (default 1), and for the shared projectile: dir (a non-zero Vector3: fly
## straight along it, e.g. a throw along a locked lane - `t` then only gates the shot; default: aim at `t`),
## on_hit (Callable(target, dealt) after a hit, dealt 0 = blocked) and kind (tag; default enemy_id).
## Returns the node, or null when refused.
func fire_projectile(from: Vector3, t: Node3D, params: Dictionary) -> Node:
	if t == null or not is_valid_victim(t):
		return null
	var shared := _shared_projectile_script()
	if shared != null:
		var sp := {"shooter": self, "from": from, "groups": ["player"], "hitstop": true,
			"kind": String(params.get("kind", enemy_id)),
			"damage": float(params.get("damage", 8.0)), "speed": float(params.get("speed", 6.0)),
			"range": float(params.get("range", 12.0)), "knockback": float(params.get("knockback", 0.0)),
			"radius": float(params.get("radius", 0.22)), "max_per_shooter": int(params.get("max_per_shooter", 1)),
			"light": bool(params.get("light", false))}
		var d: Variant = params.get("dir")
		if d is Vector3 and (d as Vector3).length_squared() > 0.0001:
			sp["dir"] = d                   # projectile.gd prefers "target" over "dir": pass only one
		else:
			sp["target"] = t
		var oh: Variant = params.get("on_hit")
		if oh is Callable and (oh as Callable).is_valid():
			sp["on_hit"] = oh
		if params.get("color") is Color:
			sp["color"] = params["color"]
		var fired: Variant = shared.call("fire", sp)
		return fired as Node if fired is Node else null
	var script := _projectile_script()
	if script == null or not bool(script.call("can_fire")):
		return null
	var parent: Node = null
	if Game.area != null and is_instance_valid(Game.area) and Game.area.is_inside_tree():
		parent = Game.area
	elif get_parent() != null:
		parent = get_parent()
	if parent == null:
		return null
	var p: Node = script.new()
	var prm := params.duplicate()
	prm["shooter"] = self
	prm["target"] = t
	p.call("setup", prm)
	parent.add_child(p)
	p.call("launch", from, t)
	return p


## Is `p` (a projectile this enemy fired) still flying for it? Pooled shared projectiles stay valid after they
## land (hidden, re-used later by anyone), so validity alone is not enough.
func projectile_in_flight(p: Variant) -> bool:
	if p == null or not is_instance_valid(p) or not (p is Node) or not (p as Node).is_inside_tree():
		return false
	var n := p as Node
	if "active" in n:
		return bool(n.get("active")) and n.get("shooter") == self
	return String(n.get("result")) == ""


static var _proj_script: Script = null
static var _shared_proj: Script = null
static var _shared_checked := false


## The shared projectile script if it exists, compiles and offers static fire(params) (else null).
static func _shared_projectile_script() -> Script:
	if not _shared_checked:
		_shared_checked = true
		if ResourceLoader.exists(SHARED_PROJECTILE):
			var s: Script = load(SHARED_PROJECTILE)
			if s != null and s.can_instantiate() and s.has_method("fire"):
				_shared_proj = s
	return _shared_proj


static func _projectile_script() -> Script:
	if _proj_script == null and ResourceLoader.exists(LOCAL_PROJECTILE):
		var s: Script = load(LOCAL_PROJECTILE)
		if s != null and s.can_instantiate():
			_proj_script = s
	return _proj_script


## Applies a bounded, non-chaining slow to Krystal (GameState buff "slow", consumed by Stats / the player):
## mult is clamped to [SLOW_MIN_MULT, 0.95] and seconds to SLOW_MAX_SECONDS; it is refused while a slow is
## active and for `immunity` seconds after one ends, so slows can never chain. Only the player can be slowed.
## When the target offers its own `apply_slow(mult, seconds, source) -> bool` (player.gd: Stats bounds, its own
## immunity, stat refresh) the slow goes through it; otherwise the buff is written directly.
static func apply_slow(t: Node, mult: float, seconds: float, immunity: float = 4.0, source: String = "") -> bool:
	if t == null or not is_instance_valid(t) or not t.is_in_group("player"):
		return false
	var now := _now_ms()
	if GameState.buffs.has("slow") or (_slow_immune_until_ms >= 0 and now < _slow_immune_until_ms):
		return false
	var m := clampf(mult, SLOW_MIN_MULT, 0.95)
	var s := clampf(seconds, 0.1, SLOW_MAX_SECONDS)
	var applied := true
	if t.has_method("apply_slow"):
		applied = Combat.truthy(t.call("apply_slow", m, s, source))
	else:
		GameState.add_buff("slow", m, s)
	if applied:
		_slow_immune_until_ms = now + int((s + maxf(immunity, 0.0)) * 1000.0)
	return applied


## This enemy's ground telegraph (src/enemies/telegraph_fx.gd): created on first use as a top_level child, so
## it is freed with the enemy; hidden automatically when a state other than telegraph / committed starts.
func mark() -> Node3D:
	if _mark == null or not is_instance_valid(_mark):
		_mark = TelegraphFx.new()
		_mark.name = "Telegraph"
		add_child(_mark)
	return _mark


func hide_mark() -> void:
	if _mark != null and is_instance_valid(_mark):
		_mark.hide_mark()


## Teaches an attack: the data "tell" (alt_tell in arachnophobia mode) as a one-time hint (the HUD also keeps
## it once per save), plus an optional rate-limited sound caption so every tell reads with the sound muted.
func announce_tell(def: Dictionary, caption: String = "") -> void:
	var tell := String(def.get("tell", ""))
	if bool(Settings.get_value("arachnophobia")) and String(def.get("alt_tell", "")) != "":
		tell = String(def["alt_tell"])
	var hid := "tell_%s_%s" % [enemy_id, String(def.get("id", "attack"))]
	if tell != "" and not _told.has(hid):
		_told[hid] = true
		Events.hint.emit(hid, tell)
	if caption != "":
		var now := Time.get_ticks_msec()
		if now - int(_captioned.get(enemy_id, -100000)) >= CAPTION_GAP_MS:
			_captioned[enemy_id] = now
			Events.caption.emit(caption)


# --- Hooks for subclasses ---------------------------------------------------------------------------------------

## Distance at which the chase may start a wind-up (default: data attack_range).
func attack_reach() -> float:
	return float(data.get("attack_range", 1.8))


## Called right before a wind-up starts (pick the attack here; telegraph_duration() may read it).
func _choose_attack() -> void:
	pass


## Called when the telegraph ends. Default: the legacy short lunge attack.
func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_enter("attack", ATTACK_TIME)


## Called at the end of every _enter (after the state's own setup, before the visual update).
func _on_state_changed(_prev: String, _new_state: String) -> void:
	pass


## States in which hits never interrupt. Default: attack, recover, stunned and every committed state.
func _is_uninterruptible() -> bool:
	return state == "attack" or state == "recover" or state == "stunned" or state in committed_states


## Reaction to a staggering hit. Default: the legacy flinch with its immunity window.
func _stagger(_amount: float, _source: Node) -> void:
	_flinch_immune = FLINCH_IMMUNITY
	_enter("flinch", FLINCH_TIME)


## The health component (a subclass may return a health.gd subclass, e.g. directional armour).
func _make_health() -> Node:
	return Health.new()


func _defeat_sound() -> String:
	return "enemy_defeat"


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
