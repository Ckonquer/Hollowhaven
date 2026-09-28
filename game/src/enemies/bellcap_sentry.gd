extends "res://src/enemies/enemy_base.gd"
## Bellcap Sentry (Ashbell Quarry's marked pocket, the Hushed Works' Bellmaker's Floor): a heavy, slow mushroom
## guardian whose cap is a bell. ONE attack, readable with the sound muted:
##   pulse   telegraph (data 1.3 s): it plants itself, the bell cap visibly SWELLS and glows (red tint), a red RING
##           of exactly the pulse radius (data radius 4 m) is drawn around it, pale outward ARROW symbols stand on
##           that ring and a bell symbol hangs over its cap -> one radial pulse (a shock ring sweeps out to the
##           radius): full circle, only group "player", line of sight from the bell to her (no pulse through walls
##           or floors) -> recover (data 1.8 s): the cap droops and the clapper swings - a clear punish window.
## Counterplay: step outside the ring, or roll through the pulse (normal dodge i-frames). The wind-up is heavy:
## hits never interrupt it (you cannot stagger-lock the bell), outside it the legacy flinch rule applies.
## It winds up once Krystal is within PULSE_START_FRACTION of the radius, so she always has the whole wind-up to
## walk out. Intensity: Gentle = longer wind-ups / rests and no overlap with other wind-ups; Intense = shorter rests.
## Stats: data/enemies.gd "bellcap_sentry". Sounds (existing names only): ward_hum (the bell swells / idle hum),
## mine_hit (the toll), dir_pebbles (alert), dir_creak (drooping), enemy_hurt, rock_break (defeat).

const Visual := preload("res://src/enemies/bellcap_sentry_visual.gd")

const PULSE_TIME := 0.35
const PULSE_AT := 0.06
const PULSE_START_FRACTION := 0.8
const GENTLE_COOLDOWN := 1.35
const INTENSE_COOLDOWN := 0.8
const GENTLE_TELEGRAPH_BONUS := 0.2
const SPORES := Color(0.95, 0.86, 0.7, 0.7)
const TOLL_CAPTION_GAP_MS := 4000     # the toll caption is shared by every sentry (no caption spam from a pocket)

static var _toll_caption_ms: int = -100000

var pulses_done: int = 0
var last_pulse_hits: int = 0
var _def: Dictionary = {}
var _center := Vector3.ZERO
var _resolved := false


func _init() -> void:
	hit_color = Color(0.95, 0.72, 0.6)
	committed_states = ["pulse"]
	needs_clear_shot = true


func _ready() -> void:
	super._ready()
	_def = attack_def("pulse")
	if visual != null and visual.has_method("set_radius"):
		visual.set_radius(pulse_radius())


func _default_id() -> String:
	return "bellcap_sentry"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.55


func _body_height() -> float:
	return 1.6


func _knockback_scale() -> float:
	return 0.3


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 0.9


func pulse_radius() -> float:
	return float(attack_def("pulse").get("radius", 4.0))


func pulse_center() -> Vector3:
	return _center


func attack_reach() -> float:
	return pulse_radius() * PULSE_START_FRACTION


func _can_start_attack() -> bool:
	return _shot_clear and not _gentle_blocked()


func _choose_attack() -> void:
	_def = attack_def("pulse")


func telegraph_duration() -> float:
	return attack_telegraph(_def) + _telegraph_bonus()


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	_center = global_position
	var m := mark()
	m.show_ring(_center, pulse_radius(), TelegraphFx.DANGER)
	m.set_progress(0.0, true)
	Audio.play_3d("ward_hum", global_position + Vector3.UP * 1.2, -2.0, 0.05)
	announce_tell(_def, "[a bell hums, swelling]")


## Rooted while it swells: it neither walks nor turns; the ring only firms up.
func _st_telegraph(_delta: float) -> void:
	if not _can_hunt or _player == null or not is_instance_valid(_player):
		_enter("return")
		return
	mark().set_progress(state_time / maxf(_state_len, 0.001), true)
	if state_time >= _state_len:
		_telegraph_finished()


func _telegraph_finished() -> void:
	_resolved = false
	_enter("pulse", PULSE_TIME)
	mark().set_progress(1.0, true)


func _st_custom(state_name: String, _delta: float) -> void:
	if state_name != "pulse":
		return
	if not _resolved and state_time >= PULSE_AT:
		_resolved = true
		var hits: Array = pulse_hits(_center, pulse_radius(), attack_damage_for(_def), float(data.get("knockback", 7.0)))
		last_pulse_hits = hits.size()
		pulses_done += 1
		Audio.play_3d("mine_hit", global_position + Vector3.UP * 1.3, 1.0, 0.03)
		var now := Time.get_ticks_msec()
		if now - _toll_caption_ms >= TOLL_CAPTION_GAP_MS:
			_toll_caption_ms = now
			Events.caption.emit("[a deep bell tolls]")
		Events.camera_shake.emit(0.1, 0.2)
		HitFx.burst(_center + Vector3.UP * 0.3, SPORES, 12, 3.5, 0.8, -1.0, 0.5, 90.0)
		_on_attack_resolved(hits)
	if state_time >= PULSE_TIME:
		_enter("recover", recover_duration())


## The swell is heavy: hits never interrupt it (no stagger-lock); otherwise the legacy flinch rule.
func can_stagger(amount: float, source: Node) -> bool:
	if state == "telegraph":
		return false
	return super.can_stagger(amount, source)


func _on_state_changed(prev: String, new_state: String) -> void:
	if new_state == "recover":
		_cooldown *= _cooldown_mult()
		if prev == "pulse":
			Audio.play_3d("dir_creak", global_position + Vector3.UP * 1.2, -6.0, 0.1)


# --- Intensity (Gentle / Intense) ---------------------------------------------------------------------------------

func _cooldown_mult() -> float:
	match Combat.current_intensity():
		0:
			return GENTLE_COOLDOWN
		2:
			return INTENSE_COOLDOWN
	return 1.0


func _telegraph_bonus() -> float:
	return GENTLE_TELEGRAPH_BONUS if Combat.current_intensity() == 0 else 0.0


func _gentle_blocked() -> bool:
	if Combat.current_intensity() != 0:
		return false
	for id in _attackers.keys():
		if int(id) != get_instance_id() and is_instance_id_valid(int(id)):
			return true
	return false


# --- Feedback ------------------------------------------------------------------------------------------------------

func _on_alert() -> void:
	Audio.play_3d("dir_pebbles", global_position + Vector3.UP * 0.8, -3.0, 0.1)


func _idle_sound() -> void:
	Audio.play_3d("ward_hum", global_position + Vector3.UP * 1.2, -16.0, 0.1)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 1.0, -3.0, 0.1)
	HitFx.burst(get_aim_point(), SPORES, 6, 1.8, 0.6, -2.0, 0.5, 120.0)


func _defeat_sound() -> String:
	return "rock_break"


## The cap rings one last soft note and settles into a puff of spores (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.2, 0.4, 1.2), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.25).set_ease(Tween.EASE_IN)
	await tw.finished
	HitFx.burst(global_position + Vector3.UP * 0.5, SPORES, 16, 1.6, 1.2, 0.3, 1.0, 160.0)
