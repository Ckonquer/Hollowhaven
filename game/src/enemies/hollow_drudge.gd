extends "res://src/enemies/enemy_base.gd"
## Hollow Drudge (Tobin's annex, later the Works / Candleyard): an empty, mineral-crusted miner's coat that
## shambles on with a pickaxe. A zombie-like silhouette without gore. Two attacks with DIFFERENT tells:
##   pick_swing  telegraph (data 1.2 s): raises the pick high overhead, the pick glows amber, a NARROW amber
##               wedge (data arc_deg 40) is drawn on the ground -> swing (one hit) -> recover (data 1.6 s)
##   scrape      telegraph (data 1.4 s): a second, distinct tell - crouches and drags the pick back low along
##               the floor with sparks, a long pale-blue LANE (data length 4 m) is drawn -> scrape along the lane
##               (one hit) -> recover (data 1.4 s)
## Both marks follow its facing for the first 60% of the wind-up, then lock. Scrapes can start from further
## away (they reach along the lane) and never come twice in a row.
## Counterplay: step out of the narrow wedge / the lane, or roll through; punish the long recovery.
## Teaching fight (Tobin's annex lockers, the Works Tool Lockers): only Krystal's own hits flinch it out of a tell;
## a companion's bolt / puff / headbutt still hurts it but never cancels the wind-up (enemy_base
## holds_tell_against, COV-002), so both tells always play when a pet is out.
## Stats: data/enemies.gd "hollow_drudge" (underground: damage scales with horror intensity).
## Sounds (existing names only): gloomling_alert (alert), dir_creak (idle / pick raised), mine_hit (swing),
## dir_scratch (scrape tell), rock_break (scrape / defeat), enemy_hurt.

const Visual := preload("res://src/enemies/hollow_drudge_visual.gd")

const SWING_TIME := 0.42
const SWING_HIT_AT := 0.14
const SWING_REACH_BONUS := 0.3       # the swing reaches data attack_range + this (+ her body)
const SCRAPE_TIME := 0.5
const SCRAPE_HIT_AT := 0.22
const SCRAPE_WIDTH := 1.2            # full width of the marked scrape lane
const SCRAPE_LUNGE := 0.8            # metres it lurches forward while scraping
const SCRAPE_START_FRACTION := 0.9   # may start a scrape within 90% of the lane length
const LANE_REFRESH := 0.1
const CRUST := Color("7fc9c0")

var next_attack: String = ""         # tests / scripted fights: force the next attack ("pick_swing" | "scrape")
var attack_kind: String = ""
var _def: Dictionary = {}
var _since_scrape: int = 1
var _lane_a := Vector3.ZERO
var _lane_b := Vector3.ZERO
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _resolved := false


func _init() -> void:
	hit_color = Color(0.62, 0.8, 0.78)
	committed_states = ["swing", "scrape"]
	needs_clear_shot = true


func _default_id() -> String:
	return "hollow_drudge"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.38


func _body_height() -> float:
	return 1.8


func _knockback_scale() -> float:
	return 0.7


func swing_reach() -> float:
	return float(data.get("attack_range", 2.4)) + SWING_REACH_BONUS


func scrape_length() -> float:
	return float(attack_def("scrape").get("length", 4.0))


func attack_reach() -> float:
	var r := float(data.get("attack_range", 2.4))
	if next_attack == "scrape" or (next_attack == "" and _since_scrape >= 1):
		return maxf(r, scrape_length() * SCRAPE_START_FRACTION)
	return r


func _can_start_attack() -> bool:
	return _shot_clear


func _choose_attack() -> void:
	var kind := next_attack
	if kind == "":
		var dist := _flat_dist_to_player()
		if dist > float(data.get("attack_range", 2.4)):
			kind = "scrape"
		elif _since_scrape >= 1 and _rng.randf() < 0.35:
			kind = "scrape"
		else:
			kind = "pick_swing"
	next_attack = ""
	attack_kind = kind
	_def = attack_def(kind)
	if kind == "scrape":
		_since_scrape = 0
	else:
		_since_scrape += 1
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack(kind)


func telegraph_duration() -> float:
	return attack_telegraph(_def)


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	_lane_clip_t = 0.0
	if attack_kind == "scrape":
		Audio.play_3d("dir_scratch", global_position + Vector3.UP * 0.3, -2.0, 0.1)
		announce_tell(_def, "[a pick scrapes along the stone]")
	else:
		Audio.play_3d("dir_creak", global_position + Vector3.UP * 1.6, -2.0, 0.1)
		announce_tell(_def, "[a pickaxe creaks up overhead]")
	_update_mark(true)


func _tick_extra(delta: float) -> void:
	if state != "telegraph":
		return
	_lane_clip_t -= delta
	_update_mark(_lane_clip_t <= 0.0 and state_time <= _state_len * TELEGRAPH_TRACK)


func _update_mark(reclip: bool) -> void:
	var fwd := _forward()
	var locked := state_time > _state_len * TELEGRAPH_TRACK
	var m := mark()
	var k := state_time / maxf(_state_len, 0.001)
	if attack_kind == "scrape":
		if reclip:
			_lane_clip_t = LANE_REFRESH
			_lane_len = float(lane_clip(global_position, fwd, scrape_length())["length"])
		if not m.is_showing():
			m.show_lane(global_position, global_position + fwd * _lane_len, SCRAPE_WIDTH, TelegraphFx.COOL)
		elif not locked:
			m.move_lane(global_position, global_position + fwd * _lane_len)
	else:
		if not m.is_showing():
			m.show_arc(global_position, fwd, swing_reach(), float(_def.get("arc_deg", 40.0)), TelegraphFx.WARN)
		elif not locked:
			m.move_arc(global_position, fwd)
	m.set_progress(k, locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_resolved = false
	if attack_kind == "scrape":
		_lane_a = global_position
		_lane_len = float(lane_clip(_lane_a, _attack_dir, scrape_length())["length"])
		_lane_b = _lane_a + _attack_dir * _lane_len
		_enter("scrape", SCRAPE_TIME)
		var m := mark()
		m.show_lane(_lane_a, _lane_b, SCRAPE_WIDTH, TelegraphFx.COOL)
		m.set_progress(1.0, true)
	else:
		_enter("swing", SWING_TIME)
		mark().set_progress(1.0, true)


func _st_custom(state_name: String, _delta: float) -> void:
	match state_name:
		"swing":
			if state_time < SWING_HIT_AT:
				_desired_vel = _attack_dir * 1.5
			if not _resolved and state_time >= SWING_HIT_AT:
				_resolved = true
				var origin := global_position + Vector3.UP * 0.9
				var hits: Array = Combat.melee(self, origin, _attack_dir, swing_reach(), float(_def.get("arc_deg", 40.0)),
					attack_damage_for(_def), ["player"], float(data.get("knockback", 6.0)))
				Audio.play_3d("mine_hit", global_position + _attack_dir * 1.6 + Vector3.UP * 0.2, -1.0, 0.1)
				_on_attack_resolved(hits)
			if state_time >= SWING_TIME:
				_enter("recover", recover_duration())
		"scrape":
			if state_time < SCRAPE_HIT_AT:
				_desired_vel = _attack_dir * (SCRAPE_LUNGE / SCRAPE_HIT_AT)
			if not _resolved and state_time >= SCRAPE_HIT_AT:
				_resolved = true
				var t := current_target()
				if t != null and lane_hits(t, _lane_a, _lane_b, SCRAPE_WIDTH * 0.5):
					deal_damage_to(t, attack_damage_for(_def), _attack_dir, float(data.get("knockback", 6.0)))
				Audio.play_3d("rock_break", global_position + _attack_dir * 1.5, -3.0, 0.1)
				HitFx.burst(global_position + _attack_dir * 1.2 + Vector3.UP * 0.1, HitFx.SPARK_COLOR, 9, 4.0, 0.5, -12.0, 0.3, 80.0)
			if state_time >= SCRAPE_TIME:
				_enter("recover", recover_duration())


func _on_alert() -> void:
	Audio.play_3d("gloomling_alert", global_position + Vector3.UP * 1.5, -3.0, 0.05)


func _idle_sound() -> void:
	Audio.play_3d("dir_creak", global_position + Vector3.UP * 1.2, -12.0, 0.15)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 1.2, -3.0, 0.1)
	HitFx.chips(global_position + Vector3.UP * 1.3, CRUST, 6, 2.8, 0.55)


## The coat slumps empty to the floor and its crust crumbles (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	Audio.play_3d("rock_break", global_position + Vector3.UP * 0.6, -4.0, 0.1)
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.1, 0.35, 1.1), 0.55).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.25).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.4
	HitFx.chips(pos, CRUST, 12, 3.0, 0.8)
	HitFx.burst(pos, Color(0.6, 0.55, 0.5, 0.6), 10, 1.4, 1.4, 0.4, 0.8)
