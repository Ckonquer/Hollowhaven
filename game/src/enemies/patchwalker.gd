extends "res://src/enemies/enemy_base.gd"
## Patchwalker (Hallowmere Reach: Pumpkintide Orchard field, the Candleyard): a lumbering straw-and-vine garden
## walker in a torn, patched coat, with a sack head (stitched smile, button eyes) and a rake. No gore.
## Two attacks with DIFFERENT tells (data/enemies.gd "patchwalker" attacks):
##   rake      telegraph (data 1.1 s): the rake is raised high behind its head (amber tint) and an amber WEDGE
##             (RAKE_REACH, data arc_deg 110) is drawn; it follows its facing for 60% of the wind-up, then locks
##             -> one wide sweep -> recover (data 1.5 s). Counter: step outside the arc, roll through it, or cut
##             the wind-up: a hit during the wind-up staggers it (the legacy flinch rule, 1.6 s immunity after).
##   mud_clod  a separate, LONGER tell (data 1.6 s): it crouches and scoops mud (a brown clod grows in its other
##             hand, brown tint) and a thin pale LANE shows the throw line, locking at 60% -> it throws the clod
##             STRAIGHT along the locked line (the shared pooled projectile; never through walls; one clod per
##             Patchwalker; no wind-up without a clear world|structure line) -> recover (data 1.6 s).
##             A clod that hits (after armour / i-frames) slows Krystal: speed x (1 - data slow) for data
##             slow_seconds, bounded by enemy_base.apply_slow (never below SLOW_MIN_MULT, never over SLOW_MAX_SECONDS)
##             and never chained: refused while a slow is active and for data slow_immunity s after it ends.
##             A dodged clod slows nothing. Throws wait CLOD_COOLDOWN between them.
## Intensity (enemy_base intensity_* / overlap_blocked): Gentle = longer wind-ups / rests, no overlapping wind-ups;
## Intense = shorter rests only - no feint (a feint is a boss / Intense-taught tell; among ordinary enemies only the
## Velvet Wing's dash has one). The clod's 1.6 s wind-up sits above the 1.0-1.4 s guideline on purpose: longer tells
## are fairer, never shorter (integration pass 2, P11).
## Stats: data/enemies.gd "patchwalker". Sounds (existing names only): dir_creak (rake raised / idle), swing (the
## sweep), dig (scooping mud), splash (throw / clod lands), grass_pull (alert / straw puffs), enemy_hurt.

const Visual := preload("res://src/enemies/patchwalker_visual.gd")

const RAKE_TIME := 0.5
const RAKE_HIT_AT := 0.2
const RAKE_REACH_BONUS := 0.4        # the rake reaches data attack_range + this (+ her body)
const THROW_TIME := 0.35
const THROW_AT := 0.12
const CLOD_SPEED := 9.0
const CLOD_RADIUS := 0.2
const CLOD_LANE_WIDTH := 0.9         # the marked throw line (clod + her body both fit inside it)
const CLOD_HEIGHT := 1.2             # throw height above its feet
const CLOD_START_FRACTION := 0.85    # may start a throw within 85% of the clod range
const CLOD_COOLDOWN := 7.0
const CLOD_KNOCKBACK := 2.0
const CLOD_COLOR := Color("7a5236")
const LANE_REFRESH := 0.1
const STRAW := Color("e0c070")

var next_attack: String = ""         # tests / scripted fights: "rake" | "mud_clod"
var attack_kind: String = ""
var clod: Node = null                # the last clod thrown (tests)
var clods_thrown: int = 0
var slows_applied: int = 0
var _def: Dictionary = {}
var _resolved := false
var _clod_cd: float = 0.0
var _lane_a := Vector3.ZERO
var _lane_b := Vector3.ZERO
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0


func _init() -> void:
	hit_color = Color(0.9, 0.78, 0.46)
	committed_states = ["rake", "throw"]
	needs_clear_shot = true


func _default_id() -> String:
	return "patchwalker"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.42


func _body_height() -> float:
	return 1.9


func _knockback_scale() -> float:
	return 0.6


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.1


func attack_origin() -> Vector3:
	return global_position + Vector3.UP * CLOD_HEIGHT


func rake_reach() -> float:
	return float(data.get("attack_range", 2.6)) + RAKE_REACH_BONUS


func rake_arc() -> float:
	return float(attack_def("rake").get("arc_deg", 110.0))


func clod_range() -> float:
	return float(attack_def("mud_clod").get("range", 10.0))


func clod_ready() -> bool:
	return _clod_cd <= 0.0 and not projectile_in_flight(clod)


func lane_length() -> float:
	return _lane_len


func attack_reach() -> float:
	var r := float(data.get("attack_range", 2.6))
	if next_attack == "mud_clod" or (next_attack == "" and clod_ready()):
		return maxf(r, clod_range() * CLOD_START_FRACTION)
	return r


func _can_start_attack() -> bool:
	return _shot_clear and not overlap_blocked()


func _choose_attack() -> void:
	var kind := next_attack
	if kind == "":
		var dist := _flat_dist_to_player()
		kind = "mud_clod" if clod_ready() and dist > rake_reach() - 0.2 else "rake"
	next_attack = ""
	attack_kind = kind
	_def = attack_def(kind)
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack(kind)


func telegraph_duration() -> float:
	return attack_telegraph(_def) + intensity_telegraph_bonus()


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	_lane_clip_t = 0.0
	if attack_kind == "mud_clod":
		Audio.play_3d("dig", global_position + Vector3.UP * 0.2, -3.0, 0.1)
		announce_tell(_def, "[a wet scoop of mud]")
	else:
		Audio.play_3d("dir_creak", global_position + Vector3.UP * 1.8, -2.0, 0.1)
		announce_tell(_def, "[a rake creaks up overhead]")
	_update_mark(true)


func _tick_extra(delta: float) -> void:
	_clod_cd = maxf(_clod_cd - delta, 0.0)
	if state != "telegraph":
		return
	_lane_clip_t -= delta
	_update_mark(_lane_clip_t <= 0.0 and state_time <= _state_len * TELEGRAPH_TRACK)


func _update_mark(reclip: bool) -> void:
	var fwd := _forward()
	var locked := state_time > _state_len * TELEGRAPH_TRACK
	var m := mark()
	if attack_kind == "mud_clod":
		if reclip:
			_lane_clip_t = LANE_REFRESH
			_lane_len = float(lane_clip(global_position, fwd, clod_range(), CLOD_HEIGHT)["length"])
		if not m.is_showing():
			m.show_lane(global_position, global_position + fwd * _lane_len, CLOD_LANE_WIDTH, TelegraphFx.COOL)
		elif not locked:
			m.move_lane(global_position, global_position + fwd * _lane_len)
	else:
		if not m.is_showing():
			m.show_arc(global_position, fwd, rake_reach(), rake_arc(), TelegraphFx.WARN)
		elif not locked:
			m.move_arc(global_position, fwd)
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_resolved = false
	if attack_kind == "mud_clod":
		_lane_a = global_position
		_lane_len = float(lane_clip(_lane_a, _attack_dir, clod_range(), CLOD_HEIGHT)["length"])
		_lane_b = _lane_a + _attack_dir * _lane_len
		_enter("throw", THROW_TIME)
		var m := mark()
		m.show_lane(_lane_a, _lane_b, CLOD_LANE_WIDTH, TelegraphFx.COOL)
		m.set_progress(1.0, true)
	else:
		_enter("rake", RAKE_TIME)
		mark().set_progress(1.0, true)


func _st_custom(state_name: String, _delta: float) -> void:
	match state_name:
		"rake":
			if state_time < RAKE_HIT_AT:
				_desired_vel = _attack_dir * 1.2
			if not _resolved and state_time >= RAKE_HIT_AT:
				_resolved = true
				var hits: Array = Combat.melee(self, global_position + Vector3.UP * 0.9, _attack_dir, rake_reach(), rake_arc(),
					attack_damage_for(_def), ["player"], float(data.get("knockback", 6.0)))
				Audio.play_3d("swing", global_position + _attack_dir * 1.5 + Vector3.UP * 0.8, -1.0, 0.1)
				HitFx.chips(global_position + _attack_dir * 1.8 + Vector3.UP * 0.2, STRAW, 5, 2.4, 0.4)
				_on_attack_resolved(hits)
			if state_time >= RAKE_TIME:
				_enter("recover", recover_duration())
		"throw":
			if not _resolved and state_time >= THROW_AT:
				_resolved = true
				_throw_clod()
			if state_time >= THROW_TIME:
				_enter("recover", recover_duration())


## Throws the clod straight along the locked lane (only with a clear line to her). Returns the projectile.
func _throw_clod() -> Node:
	_clod_cd = CLOD_COOLDOWN
	var t := current_target()
	if t == null or not has_clear_shot(t) or projectile_in_flight(clod):
		Audio.play_3d("dig", global_position + Vector3.UP * 0.4, -8.0, 0.1)      # no clear line: the mud drops
		return null
	var from := attack_origin() + _attack_dir * 0.4
	# enemy_base.fire_projectile: the shared pooled projectile flies STRAIGHT along the locked lane ("dir"; `t` only
	# gates the shot) and reports real hits to _on_clod_hit (the slow). The local fallback aims at `t` (no homing).
	var fired: Node = fire_projectile(from, t, {"dir": _attack_dir, "on_hit": Callable(self, "_on_clod_hit"),
		"damage": attack_damage_for(_def), "speed": CLOD_SPEED, "range": clod_range(), "radius": CLOD_RADIUS,
		"knockback": CLOD_KNOCKBACK, "color": CLOD_COLOR, "max_per_shooter": 1, "kind": "mud_clod", "homing": 0.0})
	if fired != null:
		clod = fired
		clods_thrown += 1
		Audio.play_3d("splash", from, -6.0, 0.15)
	return fired


## A clod that actually hurt her (after armour / i-frames) applies the bounded, never-chaining slow.
func _on_clod_hit(target: Node, dealt: float) -> void:
	if dealt <= 0.0 or target == null or not is_instance_valid(target):
		return
	var def := attack_def("mud_clod")
	var mult := 1.0 - clampf(float(def.get("slow", 0.3)), 0.0, 0.9)
	if apply_slow(target, mult, float(def.get("slow_seconds", 2.0)), float(def.get("slow_immunity", 4.0)), enemy_id):
		slows_applied += 1
		# Direct caption: announce_tell's per-enemy rate limit would swallow it (the throw's own tell caption played
		# well under CAPTION_GAP_MS ago). Slows never chain, so this can fire at most once per slow + immunity.
		Events.caption.emit("[mud splatters - your steps feel heavy]")
	if target is Node3D:
		HitFx.chips(Combat.aim_point(target as Node3D), CLOD_COLOR, 8, 2.4, 0.5)


func _on_state_changed(_prev: String, new_state: String) -> void:
	if new_state == "recover":
		_cooldown *= intensity_cooldown_mult()


# --- Feedback ------------------------------------------------------------------------------------------------------

func _on_alert() -> void:
	Audio.play_3d("grass_pull", global_position + Vector3.UP * 1.5, -3.0, 0.1)


func _idle_sound() -> void:
	Audio.play_3d("dir_creak", global_position + Vector3.UP * 1.5, -13.0, 0.15)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 1.3, -3.0, 0.1)
	HitFx.chips(get_aim_point(), STRAW, 7, 2.8, 0.55)


## Its coat slumps to the ground and the straw puffs out (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	Audio.play_3d("grass_pull", global_position + Vector3.UP * 0.8, -2.0, 0.1)
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", 1.35, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.25).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.4
	HitFx.chips(pos, STRAW, 16, 3.0, 0.9)
	HitFx.chips(pos, Color("4f6a3a"), 8, 2.6, 0.7)
