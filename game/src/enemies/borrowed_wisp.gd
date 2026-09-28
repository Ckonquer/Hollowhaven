extends "res://src/enemies/enemy_base.gd"
## Borrowed Wisp (the Hushed Works' deep rooms and small late encounters; the director's "hw_wisp_drift"): a false
## warm light in a little wooden mask. Its glow is emissive only - no Light3D, not in group "light_source" - so it
## lights NOTHING around it (Combat.light_at never counts it), which is exactly the clue.
##   veiled    (default) the false light floats at VEIL_HEIGHT and cannot be harmed: every hit passes through
##             (health invulnerable, can_be_hit_by false -> on_hit_blocked: a spark and a one-time hint).
##   revealed  real light on it (Krystal's raised lantern within ~4.5 m, or a lamp / brazier / ward: Combat.light_at
##             at its body >= REVEAL_ON) shows its true form: the light shrinks to a small cold flicker, a hooded
##             masked shape drops to REVEAL_HEIGHT (sword reach) and can be hurt. On being revealed it is DAZZLED for
##             DAZZLE_TIME (a free punish window before it can cast; a wind-up in progress is cancelled). It veils
##             again after REVEAL_HOLD s with the light below REVEAL_OFF.
##   sweep     telegraph (data 1.4 s): its ribbons lift to one side (amber tint) and an amber WEDGE (data arc_deg
##             120, radius data attack_range) is drawn, tracking for 60% then locked -> a DELAYED sweep: the locked mark
##             stays and brightens for data delay (0.8 s) -> one sweep (line of sight, player group only) -> recover.
## There is only ever ONE wisp body per spawn: it never splits into, or hides among, identical lethal clones.
## Intensity: Gentle = longer wind-ups / rests and no overlap with other wind-ups; Intense = shorter rests. Data
## "underground": damage scales with the horror intensity like the other deep threats.
## Stats: data/enemies.gd "borrowed_wisp". Sounds (existing names only): fake_lumi_chime (idle: a borrowed chime),
## shade_whisper (alert), gloomling_flinch (revealed), shade_telegraph (sweep tell), shade_drift (the sweep),
## hit_soft (blocked), enemy_hurt, lantern_off (defeat).

const Visual := preload("res://src/enemies/borrowed_wisp_visual.gd")

const VEIL_HEIGHT := 2.9             # out of sword reach (and unhittable) while veiled
const REVEAL_HEIGHT := 1.3
const HEIGHT_SPEED := 4.0
const LIGHT_SAMPLE_Y := 1.0          # where its true body is sampled for light (not up in the false glow)
const REVEAL_ON := 0.4
const REVEAL_OFF := 0.25
const REVEAL_HOLD := 2.0
const DAZZLE_TIME := 1.0
const SWEEP_TIME := 0.3
const SWEEP_START_FRACTION := 0.8
const GENTLE_COOLDOWN := 1.35
const INTENSE_COOLDOWN := 0.8
const GENTLE_TELEGRAPH_BONUS := 0.2
const EMBERS := Color(1.0, 0.78, 0.5, 0.7)
const REVEAL_CAPTION_GAP_MS := 6000

static var _reveal_caption_ms: int = -100000

var hover_y: float = VEIL_HEIGHT
var revealed := false
var light_override: float = -1.0     # tests: >= 0 replaces the light sample
var light_level: float = 0.0
var reveals: int = 0
var sweeps_done: int = 0
var blocked_hits: int = 0
var _def: Dictionary = {}
var _unlit_t: float = 0.0
var _resolved := false


func _init() -> void:
	hit_color = Color(1.0, 0.86, 0.62)
	committed_states = ["sweep_wait", "sweep"]
	needs_clear_shot = true


func _ready() -> void:
	super._ready()
	_def = attack_def("sweep")
	_apply_reveal(false)


func _default_id() -> String:
	return "borrowed_wisp"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.35


func _body_height() -> float:
	return 0.8


func _knockback_scale() -> float:
	return 0.9


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * hover_y


func attack_origin() -> Vector3:
	return global_position + Vector3.UP * minf(hover_y, 1.2)


func _line_of_sight(p: Node3D) -> bool:
	if not is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, global_position + Vector3.UP * 1.2, p.global_position + Vector3.UP * 0.9, [self, p], 1)


func sweep_reach() -> float:
	return float(data.get("attack_range", 5.0))


func sweep_arc() -> float:
	return float(attack_def("sweep").get("arc_deg", 120.0))


func sweep_delay() -> float:
	return float(attack_def("sweep").get("delay", 0.8))


func attack_reach() -> float:
	return sweep_reach() * SWEEP_START_FRACTION


# --- Light: the reveal ---------------------------------------------------------------------------------------------

func _perceive_extra() -> void:
	light_level = light_override if light_override >= 0.0 else Combat.light_at(global_position + Vector3.UP * LIGHT_SAMPLE_Y)
	if light_level >= REVEAL_ON:
		_unlit_t = 0.0
		if not revealed:
			_reveal()
	elif revealed:
		if light_level < REVEAL_OFF:
			_unlit_t += PERCEPTION_INTERVAL
			if _unlit_t >= REVEAL_HOLD:
				_unlit_t = 0.0
				_apply_reveal(false)
		else:
			_unlit_t = 0.0


func _reveal() -> void:
	_apply_reveal(true)
	reveals += 1
	Audio.play_3d("gloomling_flinch", get_aim_point(), -3.0, 0.1)
	var now := Time.get_ticks_msec()
	if now - _reveal_caption_ms >= REVEAL_CAPTION_GAP_MS:
		_reveal_caption_ms = now
		Events.caption.emit("[the warm light gutters - something small and masked is inside]")
	Events.hint.emit("hint_borrowed_wisp_reveal", "Your lantern shows a Borrowed Wisp's true form. Strike it now, before it casts.")
	if state in ["dead", "sweep_wait", "sweep"]:
		return
	stun(DAZZLE_TIME)                    # dazzled: a free punish window (cancels a wind-up in progress)


func _apply_reveal(on: bool) -> void:
	revealed = on
	if health != null:
		health.invulnerable = not on and not health.dead
	if visual != null and visual.has_method("set_revealed"):
		visual.set_revealed(on)


func can_be_hit_by(source: Node) -> bool:
	return revealed and super.can_be_hit_by(source)


## A blow through the false light: a spark, and (once) the hint to raise the lantern.
func on_hit_blocked(_attacker: Node, _dir: Vector3) -> void:
	blocked_hits += 1
	HitFx.spark(get_aim_point())
	Events.hint.emit("hint_borrowed_wisp_blocked", "Your blow passes straight through the false light. Raise your lantern ({lantern}) to reveal what hides in it.")


func _tick_extra(delta: float) -> void:
	var want := REVEAL_HEIGHT if revealed else VEIL_HEIGHT
	if state == "dead":
		want = hover_y
	hover_y = move_toward(hover_y, want, HEIGHT_SPEED * delta)
	if state == "telegraph":
		_update_mark()


# --- The delayed sweep ---------------------------------------------------------------------------------------------

func _can_start_attack() -> bool:
	return _shot_clear and not _gentle_blocked()


func _choose_attack() -> void:
	_def = attack_def("sweep")


func telegraph_duration() -> float:
	return attack_telegraph(_def) + _telegraph_bonus()


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	Audio.play_3d("shade_telegraph", get_aim_point(), -4.0, 0.1)
	announce_tell(_def, "[a hollow, borrowed hum]")
	_update_mark()


func _update_mark() -> void:
	var m := mark()
	var locked := state_time > _state_len * TELEGRAPH_TRACK
	if not m.is_showing():
		m.show_arc(global_position, _forward(), sweep_reach(), sweep_arc(), TelegraphFx.WARN)
	elif not locked:
		m.move_arc(global_position, _forward())
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_resolved = false
	_enter("sweep_wait", sweep_delay())
	mark().set_progress(1.0, true)


func _st_custom(state_name: String, _delta: float) -> void:
	match state_name:
		"sweep_wait":
			if state_time >= _state_len:
				_enter("sweep", SWEEP_TIME)
		"sweep":
			if not _resolved:
				_resolved = true
				var hits: Array = Combat.melee(self, global_position + Vector3.UP * 0.9, _attack_dir, sweep_reach(), sweep_arc(),
					attack_damage_for(_def), ["player"], float(data.get("knockback", 5.0)))
				sweeps_done += 1
				Audio.play_3d("shade_drift", global_position + _attack_dir * 2.0 + Vector3.UP, -1.0, 0.1)
				HitFx.burst(global_position + _attack_dir * 2.0 + Vector3.UP * 0.6, EMBERS, 10, 3.0, 0.6, -1.0, 0.4, 80.0)
				_on_attack_resolved(hits)
			if state_time >= _state_len:
				_enter("recover", recover_duration())


func _on_state_changed(_prev: String, new_state: String) -> void:
	if new_state == "recover":
		_cooldown *= _cooldown_mult()


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
	Audio.play_3d("shade_whisper", get_aim_point(), -8.0, 0.2)


func _idle_sound() -> void:
	Audio.play_3d("fake_lumi_chime", get_aim_point(), -14.0, 0.1)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", get_aim_point(), -3.0, 0.15)
	HitFx.burst(get_aim_point(), EMBERS, 6, 1.6, 0.6, -1.0, 0.5, 120.0)


func _defeat_sound() -> String:
	return "lantern_off"


## The borrowed light goes out; the little mask drops and the ribbons drift down (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(self, "hover_y", 0.3, 0.7).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.25).set_ease(Tween.EASE_IN)
	await tw.finished
	HitFx.burst(global_position + Vector3.UP * 0.4, EMBERS, 12, 1.4, 0.9, -0.3, 1.0, 160.0)
