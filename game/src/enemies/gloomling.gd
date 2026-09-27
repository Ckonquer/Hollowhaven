extends "res://src/enemies/enemy_base.gd"
## Gloomling (below): a small shadow imp. Its eyes flare red before a claw swipe (0.8 s).
## Light fear: when Combat.light_at(its position) > EXPOSE_ON it is "exposed": it takes double
## damage (health.damage_taken_mult = 2), squints, hisses (gloomling_flinch) and hesitates/backs off
## for a moment. Raising a light while it winds up cancels the swipe. After hesitating it steels
## itself for a few seconds (so light is a strong tool, not a force field).
## On defeat it dissolves into dark wisps (no gore).

const Visual := preload("res://src/enemies/gloomling_visual.gd")

const EXPOSE_ON := 0.4
const EXPOSE_OFF := 0.3
const EXPOSED_DAMAGE_MULT := 2.0
const BACKOFF_TIME := 1.3
const BRAVE_TIME := 3.5
const FLINCH_SOUND_COOLDOWN := 1.5
const WISP_COLOR := Color(0.2, 0.14, 0.3, 0.7)

var exposed := false
var light_level: float = 0.0
var light_override: float = -1.0       # tests: >= 0 replaces Combat.light_at
var _brave_t: float = 0.0
var _flinch_sound_t: float = 0.0


func _init() -> void:
	hit_color = Color(0.55, 0.45, 0.85)


func _default_id() -> String:
	return "gloomling"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.35


func _body_height() -> float:
	return 1.15


func _lunge_distance() -> float:
	return 0.9


func is_exposed() -> bool:
	return exposed


func _tick_extra(delta: float) -> void:
	_brave_t = maxf(_brave_t - delta, 0.0)
	_flinch_sound_t = maxf(_flinch_sound_t - delta, 0.0)
	if state == "chase" and exposed and _brave_t <= 0.0:
		_enter("backoff", BACKOFF_TIME)


func _perceive_extra() -> void:
	light_level = light_override if light_override >= 0.0 else Combat.light_at(global_position + Vector3.UP * 0.6)
	var was := exposed
	if not exposed and light_level > EXPOSE_ON:
		exposed = true
	elif exposed and light_level < EXPOSE_OFF:
		exposed = false
	if health != null:
		health.damage_taken_mult = EXPOSED_DAMAGE_MULT if exposed else 1.0
	if visual != null and visual.has_method("set_exposed"):
		visual.set_exposed(exposed)
	if exposed and not was:
		_on_exposed()


func _on_exposed() -> void:
	if state == "dead":
		return
	if _flinch_sound_t <= 0.0:
		_flinch_sound_t = FLINCH_SOUND_COOLDOWN
		Audio.play_3d("gloomling_flinch", global_position + Vector3.UP * 0.7, -2.0, 0.1)
	if state == "telegraph":
		_brave_t = 0.0
		_enter("backoff", BACKOFF_TIME)          # the lantern interrupts the wind-up
	elif state in ["idle", "wander", "chase"] and _brave_t <= 0.0:
		_enter("backoff", BACKOFF_TIME)


func _can_start_attack() -> bool:
	return not exposed or _brave_t > 0.0


func _st_custom(state_name: String, delta: float) -> void:
	if state_name != "backoff":
		return
	if _player != null and is_instance_valid(_player):
		var away := global_position - _player.global_position
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized()
			_desired_vel = away * float(data.get("speed", 3.0)) * 0.7
			_face(-away, delta, 1.5)
	if state_time >= _state_len:
		_brave_t = BRAVE_TIME
		_resume_after_interrupt()


func _on_alert() -> void:
	Audio.play_3d("gloomling_alert", global_position + Vector3.UP * 0.7, -1.0, 0.1)


func _on_telegraph_start() -> void:
	Audio.play_3d("gloomling_telegraph", global_position + Vector3.UP * 0.7, 0.0, 0.05)


func _idle_sound() -> void:
	Audio.play_3d("gloomling_hiss", global_position + Vector3.UP * 0.7, -8.0, 0.12)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 0.7, -3.0, 0.15)
	HitFx.wisps(global_position + Vector3.UP * 0.7, WISP_COLOR, 5, 1.0)


## Dissolves into rising dark wisps; the eyes linger a moment, then fade.
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	Audio.play_3d("gloomling_hiss", global_position + Vector3.UP * 0.7, -4.0, 0.2)
	HitFx.wisps(global_position + Vector3.UP * 0.6, WISP_COLOR, 18, 1.8)
	var tw := create_tween()
	tw.tween_property(visual, "fade", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "position:y", 0.5, 0.8)
	await tw.finished
