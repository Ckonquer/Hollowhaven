extends "res://src/enemies/enemy_base.gd"
## Pumpkin Mimic (Hallowmere Reach, Pumpkintide Orchard's marked patch; MP 12 / 14 "The Pumpkin That Turned"):
## a squat jack-o'-lantern with a carved mouth and stubby vine feet.
##   dormant   (setup key "dormant": true) sits still like a pumpkin - eyes shut, mouth a closed seam, feet
##             tucked - but now and then its stem twitches TWICE (the tell). It is NOT in group "enemy" while
##             dormant (companions, travel / save gates and every swing ignore it: it is decor until it wakes),
##             it is an interactable ("Inspect twitching pumpkin", data inspect_text) and it wakes when inspected
##             or when Krystal lingers right beside it (WAKE_NEAR for WAKE_LINGER s, never in a safe zone).
##             A dormant mimic is never placed in a safe zone or beside a player's crop plot / planter
##             (spot_allowed): such a spawn retires itself at once - a mimic never replaces a planted crop.
##   waking    data wake_telegraph (1.4 s): the stem twitches twice more, the eyes blink open, it hops up; only
##             then does it join group "enemy" and hunt.
##   bite      telegraph (data, never under 1.0 s): the carved mouth gapes wide (orange tint) and a short amber
##             WEDGE is drawn -> a hop and one snap (arc BITE_ARC) -> recover (data 1.4 s).
##   roll      unlocked "later": after its first bite or below ROLL_UNLOCK_RATIO health. Telegraph (data 1.4 s):
##             tucks its vine feet in, red tint, a red LANE (data distance 8 m, clipped at walls) is drawn and
##             locks after 60% -> it rolls along the lane (one hit at most) -> stuck: it wobbles in the dirt for
##             data recover (2.0 s, +STUCK_WALL_EXTRA after bumping a wall) - the punish window.
## Spawned by a spawner without "dormant" (the orchard pocket twitches its own props first) it starts awake.
## Spawners must NOT pass "dormant" (integration pass 2, P12): spot_allowed() rejects crop / safe spots and a retired
## mimic would be re-spawned by its spawner every tick. Dormant mimics are hand-placed only (no district uses them).
## Setup key "seed" (int, optional): seeds this mimic's RNG (twitch gaps, idle waits) for deterministic tests;
## default: randomized.
## Intensity: Gentle = longer wind-ups, longer rests and no overlapping wind-ups with other enemies;
## Intense = shorter rests (never faster tells, never invisible, never louder).
## Stats: data/enemies.gd "pumpkin_mimic". Sounds (existing names only): grass_pull (stem twitch), brambling_chatter
## (wake / alert / idle), brambling_telegraph (bite tell), chest_close (the snap), dig (roll tell / stuck),
## mine_cart (rolling), land (bump), enemy_hurt, harvest_crop (defeat).

const Visual := preload("res://src/enemies/pumpkin_mimic_visual.gd")

const BITE_TIME := 0.45
const BITE_HIT_AT := 0.16
const BITE_REACH_BONUS := 0.3        # the bite reaches data attack_range + this (+ her body)
const BITE_ARC := 70.0
const BITE_HOP := 1.2                # metres it hops forward while snapping
const ROLL_SPEED := 8.0
const ROLL_START_FRACTION := 0.8     # a roll wind-up may start within 80% of the lane length
const LANE_WIDTH := 1.2              # full width of the marked roll lane (= the hit width)
const HIT_AHEAD := 0.45
const STUCK_WALL_EXTRA := 1.0
const ROLL_UNLOCK_RATIO := 0.7
const WAKE_NEAR := 2.0
const WAKE_LINGER := 0.5
const WAKE_ASSIST_MULT := 1.3        # Settings timing_assist: a calmer wake
const TWITCH_GAP := 0.4              # seconds between the two twitches of a pair
const TWITCH_REST_MIN := 3.5
const TWITCH_REST_MAX := 6.5
const CROP_CLEARANCE := 2.5
const CROP_STRUCTURES := ["crop_plot", "sturdy_planter"]
const INSPECT_TEXT := "Inspect twitching pumpkin"
const LANE_REFRESH := 0.1
const PULP := Color("f2a042")
const SEEDS := Color("fff0c8")
const DIRT := Color("9c7650")

var dormant := false                 # setup key "dormant"
var rng_seed: int = -1               # setup key "seed" (>= 0 = deterministic RNG; tests)
var next_attack: String = ""         # tests / scripted fights: "bite" | "roll"
var attack_kind: String = ""
var bites_done: int = 0
var rolls_done: int = 0
var stem_twitches: int = 0           # every single stem twitch so far (the tell; tests count them)
var retired := false
var inspect_area: Area3D = null
var _def: Dictionary = {}
var _resolved := false
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _near_t: float = 0.0
var _twitch_t: float = 3.0
var _pair_left: int = 0
var _pair_t: float = 0.0
var _since_roll: int = 1
var _stuck_wall := false


func _init() -> void:
	hit_color = Color(1.0, 0.72, 0.36)
	committed_states = ["bite", "roll"]
	needs_clear_shot = true


func setup(params: Dictionary) -> void:
	super.setup(params)
	dormant = bool(params.get("dormant", dormant))
	if params.has("seed"):
		rng_seed = maxi(int(params["seed"]), 0)


func _ready() -> void:
	super._ready()                       # randomizes the RNG ...
	if rng_seed >= 0:
		_rng.seed = rng_seed             # ... unless a seed was given: re-draw what the base drew unseeded, so the
		_chatter_t = _rng.randf_range(4.0, 10.0)            # whole schedule (chatter, first wait, twitches) is fixed
		if state == "idle":
			_state_len = _rng.randf_range(0.6, 2.2)
	_def = attack_def("bite")
	if dormant:
		if not spot_allowed(global_position):
			_retire()
			return
		remove_from_group("enemy")
		add_to_group("interactable")
		_build_inspect_area()
		_twitch_t = _rng.randf_range(1.0, 3.0)
		_enter("dormant")


func _default_id() -> String:
	return "pumpkin_mimic"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.42


func _body_height() -> float:
	return 0.8


func _knockback_scale() -> float:
	return 0.8


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 0.42


# --- Dormant / placement rules --------------------------------------------------------------------------------

## May a dormant mimic sit at `pos`? Never inside a safe zone (the home never grows a mimic) and never beside a
## player's crop plot / planter (a mimic never replaces a planted crop).
static func spot_allowed(pos: Vector3) -> bool:
	var a: Node = Game.area
	if a != null and is_instance_valid(a) and a.has_method("is_safe_zone") and bool(a.call("is_safe_zone", pos)):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	for s in tree.get_nodes_in_group("structure"):
		if not (s is Node3D) or not is_instance_valid(s):
			continue
		var sid := str(s.get("structure_id"))
		if not (s.has_method("current_crop") or CROP_STRUCTURES.has(sid)):
			continue
		var p := (s as Node3D).global_position
		if Vector2(p.x - pos.x, p.z - pos.z).length() < CROP_CLEARANCE:
			return false
	return true


func _retire() -> void:
	retired = true
	remove_from_group("enemy")
	collision_layer = 0
	visible = false
	set_physics_process(false)
	push_warning("Pumpkin Mimic: a dormant mimic may not sit in a safe zone or beside a crop plot; removed")
	queue_free()


func _build_inspect_area() -> void:
	inspect_area = Area3D.new()
	inspect_area.name = "InspectArea"
	inspect_area.collision_layer = 16
	inspect_area.collision_mask = 0
	inspect_area.monitoring = false
	inspect_area.monitorable = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.75
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	inspect_area.add_child(cs)
	add_child(inspect_area)


func is_dormant() -> bool:
	return state == "dormant"


## Interaction contract (only while dormant).
func get_interaction(_p: Node) -> Dictionary:
	if state != "dormant":
		return {}
	return {"text": String(data.get("inspect_text", INSPECT_TEXT)), "enabled": true}


func interact(_p: Node) -> void:
	wake()


## Starts the wake: two more stem twitches over data wake_telegraph, then it hunts. False unless dormant.
func wake() -> bool:
	if state != "dormant":
		return false
	remove_from_group("interactable")
	if inspect_area != null and is_instance_valid(inspect_area):
		inspect_area.collision_layer = 0
	_enter("waking", wake_duration())
	_twitch()
	_pair_left = 1
	_pair_t = TWITCH_GAP
	announce_tell(attack_def("bite"), "[a pumpkin stem twitches twice]")
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.5, -3.0, 0.1)
	return true


func wake_duration() -> float:
	var t := float(data.get("wake_telegraph", 1.4)) + intensity_telegraph_bonus()
	if bool(Settings.get_value("timing_assist")):
		t *= WAKE_ASSIST_MULT
	return maxf(t, MIN_COMMITTED_TELEGRAPH)


func _finish_wake() -> void:
	dormant = false
	if not is_in_group("enemy"):
		add_to_group("enemy")
	_cooldown = maxf(_cooldown, 0.8)
	_alert_boost = maxf(_alert_boost, 6.0)
	if _chase_valid():
		_enter("chase")
	else:
		_enter("idle", _rng.randf_range(0.6, 1.2))


func _twitch() -> void:
	stem_twitches += 1
	if visual != null and visual.has_method("twitch"):
		visual.twitch()
	Audio.play_3d("grass_pull", global_position + Vector3.UP * 0.7, -10.0, 0.15)


func _tick_dormant(delta: float) -> void:
	# Idle tell: pairs of stem twitches every few seconds.
	if _pair_left > 0:
		_pair_t -= delta
		if _pair_t <= 0.0:
			_pair_left -= 1
			_twitch()
	else:
		_twitch_t -= delta
		if _twitch_t <= 0.0:
			_twitch_t = _rng.randf_range(TWITCH_REST_MIN, TWITCH_REST_MAX)
			_twitch()
			_pair_left = 1
			_pair_t = TWITCH_GAP
	var near := _can_hunt and _player != null and is_instance_valid(_player) and _flat_dist_to_player() <= WAKE_NEAR
	_near_t = _near_t + delta if near else 0.0
	if _near_t >= WAKE_LINGER:
		wake()


# --- Attacks -----------------------------------------------------------------------------------------------------

func bite_reach() -> float:
	return float(data.get("attack_range", 2.0)) + BITE_REACH_BONUS


func roll_distance() -> float:
	return float(attack_def("roll").get("distance", 8.0))


func roll_unlocked() -> bool:
	return bites_done >= 1 or (health != null and health.ratio() <= ROLL_UNLOCK_RATIO)


func lane_length() -> float:
	return _lane_len


func attack_reach() -> float:
	var r := float(data.get("attack_range", 2.0))
	if next_attack == "roll" or (next_attack == "" and roll_unlocked() and _since_roll >= 1):
		return maxf(r, roll_distance() * ROLL_START_FRACTION)
	return r


func _can_start_attack() -> bool:
	return _shot_clear and not overlap_blocked()


func _choose_attack() -> void:
	var kind := next_attack
	if kind == "":
		var dist := _flat_dist_to_player()
		if roll_unlocked() and _since_roll >= 1 and (dist > float(data.get("attack_range", 2.0)) or _rng.randf() < 0.3):
			kind = "roll"
		else:
			kind = "bite"
	next_attack = ""
	attack_kind = kind
	_def = attack_def(kind)
	if kind == "roll":
		_since_roll = 0
	else:
		_since_roll += 1
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack(kind)


func telegraph_duration() -> float:
	return attack_telegraph(_def) + intensity_telegraph_bonus()


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	_lane_clip_t = 0.0
	if attack_kind == "roll":
		Audio.play_3d("dig", global_position + Vector3.UP * 0.2, -2.0, 0.1)
		announce_tell(_def, "[a pumpkin tucks in its vines]")
	else:
		Audio.play_3d("brambling_telegraph", global_position + Vector3.UP * 0.5, -2.0, 0.12)
		announce_tell(_def, "[a carved mouth creaks open]")
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
	if attack_kind == "roll":
		if reclip:
			_lane_clip_t = LANE_REFRESH
			_lane_len = float(lane_clip(global_position, fwd, roll_distance())["length"])
		if not m.is_showing():
			m.show_lane(global_position, global_position + fwd * _lane_len, LANE_WIDTH, TelegraphFx.DANGER)
		elif not locked:
			m.move_lane(global_position, global_position + fwd * _lane_len)
	else:
		if not m.is_showing():
			m.show_arc(global_position, fwd, bite_reach(), BITE_ARC, TelegraphFx.WARN)
		elif not locked:
			m.move_arc(global_position, fwd)
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_resolved = false
	if attack_kind == "roll":
		_enter("roll", 0.0)
		_lane_len = charge_begin(_attack_dir, roll_distance(), ROLL_SPEED)
		var m := mark()
		m.show_lane(global_position, charge_lane_end(), LANE_WIDTH, TelegraphFx.DANGER)
		m.set_progress(1.0, true)
		Audio.play_3d("mine_cart", global_position + Vector3.UP * 0.3, -6.0, 0.1)
	else:
		_enter("bite", BITE_TIME)
		mark().set_progress(1.0, true)


func _st_custom(state_name: String, delta: float) -> void:
	match state_name:
		"dormant":
			_tick_dormant(delta)
		"waking":
			if _pair_left > 0:
				_pair_t -= delta
				if _pair_t <= 0.0:
					_pair_left -= 1
					_twitch()
			if state_time >= _state_len:
				_finish_wake()
		"bite":
			if state_time < BITE_HIT_AT:
				_desired_vel = _attack_dir * (BITE_HOP / BITE_HIT_AT)
			if not _resolved and state_time >= BITE_HIT_AT:
				_resolved = true
				var hits: Array = Combat.melee(self, global_position + Vector3.UP * 0.5, _attack_dir, bite_reach(), BITE_ARC,
					attack_damage_for(_def), ["player"], float(data.get("knockback", 5.0)))
				Audio.play_3d("chest_close", global_position + _attack_dir * 0.6 + Vector3.UP * 0.4, -2.0, 0.12)
				bites_done += 1
				_on_attack_resolved(hits)
			if state_time >= BITE_TIME:
				_enter("recover", recover_duration())
		"roll":
			var r := charge_step(delta, HIT_AHEAD, LANE_WIDTH * 0.5, attack_damage_for(_def), float(data.get("knockback", 5.0)))
			match r:
				"hit", "done":
					_get_stuck(false)
				"wall":
					_get_stuck(true)
				_:
					if state_time > _lane_len / ROLL_SPEED + 0.6:      # safety net: never rolls on past its lane
						_get_stuck(false)
		"stuck":
			if state_time >= _state_len:
				_cooldown = float(data.get("cooldown", 2.2)) * intensity_cooldown_mult()
				_resume_after_interrupt()


## The end of every roll: it wobbles, stuck in the dirt, for its data recover (longer after bumping a wall).
func _get_stuck(wall: bool) -> void:
	rolls_done += 1
	_stuck_wall = wall
	_enter("stuck", recover_duration() + (STUCK_WALL_EXTRA if wall else 0.0))
	Audio.play_3d("land" if wall else "dig", global_position + Vector3.UP * 0.3, -3.0, 0.1)
	HitFx.chips(global_position + Vector3.UP * 0.2, DIRT, 8, 2.6, 0.6)
	if wall:
		Events.camera_shake.emit(0.08, 0.15)


func is_stuck() -> bool:
	return state == "stuck"


func is_threatening() -> bool:
	if state in ["dormant", "dead"] or retired:
		return false
	return super.is_threatening() or state == "stuck" or state == "waking"


func _is_uninterruptible() -> bool:
	return super._is_uninterruptible() or state in ["stuck", "waking", "dormant"]


func _on_player_died() -> void:
	if state == "waking":
		_finish_wake()
		_enter("return")
		return
	if state == "stuck":
		_enter("return")
		return
	super._on_player_died()


func _on_state_changed(_prev: String, new_state: String) -> void:
	if new_state == "recover":
		_cooldown *= intensity_cooldown_mult()


# --- Feedback ------------------------------------------------------------------------------------------------------

func _on_alert() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.5, -3.0, 0.1)


func _idle_sound() -> void:
	if state == "dormant":
		return
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.5, -12.0, 0.1)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 0.5, -3.0, 0.12)
	HitFx.chips(get_aim_point(), PULP, 6, 2.8, 0.5)


func _defeat_sound() -> String:
	return "harvest_crop"


## Flops open, then pops into pulp, seeds and leaves (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.25, 0.55, 1.25), 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.2).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.35
	HitFx.chips(pos, PULP, 12, 3.2, 0.8)
	HitFx.chips(pos, SEEDS, 8, 2.6, 0.7)
	HitFx.burst(pos, Color(0.6, 0.8, 0.45, 0.6), 6, 1.2, 1.2, 0.5, 0.6)
