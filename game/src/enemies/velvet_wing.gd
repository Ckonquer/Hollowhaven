extends "res://src/enemies/enemy_base.gd"
## Velvet Wing (Moonveil Manor approach and galleries, the manor grounds' topiary pocket): a masked little vampire
## bat in a tiny velvet cape. Its body flies at a virtual height `hover_y` (like the Lantern Moth: the collision
## body stays on the ground, the aim point and the visual rise), so HOW HIGH it is decides whether a sword reaches it:
##   idle      hangs still upside down at HANG_HEIGHT, cloak wrapped (out of reach; never wanders)
##   chase     flies at FLY_HEIGHT (out of reach), keeping a little distance while it cannot attack
##   dash      telegraph (data 1.0 s): hovers still and FOLDS its cloak (red tint) while a red LANE (data distance
##             7 m, clipped at walls) shows the dash line through Krystal; it tracks for 60%, then locks -> it dashes
##             down along the lane to chest height (one hit at most) -> recover at data rest_height (1.4 m): a
##             missed (or landed) dash always leaves it within sword reach for data recover (1.4 s).
##   drain     telegraph (data 1.5 s) + channel (data 2.0 s): it hovers at DRAIN_HEIGHT (within reach) and a glowing
##             drain MARK under Krystal (it follows her through the wind-up, then stays put for the channel) plus a
##             visible tether link them. The link breaks - it recoils, reachable, for data recover (1.2 s) - when a
##             wall or structure cuts the line of sight ("sight"), when WARD-LIGHT reaches her ("light", the lead rule
##             of integration pass 2):
##               * light sources at her position of at least WARD_LIGHT (ward_light_at): lit ward candles, lamps /
##                 lantern posts / placed light structures, braziers, and Lumi's Glimmerstep pulse (a deliberate skill:
##                 its "GlimmerPulse" light, which Glimmerstep's expose() call also breaks at once) - but NOT a
##                 companion's passive glow (group "companion": Lumi beside her never breaks it) and not Krystal's own
##                 body light;
##               * Krystal's raised lantern while she stands INSIDE the drain mark (DRAIN_MARK_RADIUS of its centre);
##             when she walks out of range ("range"), or when the wing takes a hit ("hit"). Only a channel that
##             finishes drains: ONE hit of data damage through her health (i-frames, armour and shields apply) and it
##             heals by exactly the damage dealt (0 = nothing). There is no other lifesteal. Drains wait DRAIN_COOLDOWN.
## expose(seconds) (Lumi's Glimmerstep): breaks a drain in progress with reason "light"; otherwise nothing.
## Intensity (enemy_base intensity_* / overlap_blocked): Gentle = longer wind-ups / rests, no overlapping wind-ups;
## Intense = shorter rests and, once a real dash has been seen, sometimes a dash FEINT (the only ordinary enemy with
## one: feints are an Intense-taught tell): halfway through the fold it flicks its cloak open, then re-folds with a
## full separate final tell (the lane is re-shown and a second sound plays) - never faster or invisible.
## Stats: data/enemies.gd "velvet_wing". Sounds (existing names only): dir_wrong_squeak (alert / idle squeaks),
## shade_drift (cloak folds / dash whoosh), dodge (the dash), shade_telegraph (drain tell), shade_whisper (drain
## lands), gloomling_flinch (link broken), enemy_hurt, lantern_off (defeat).

const Visual := preload("res://src/enemies/velvet_wing_visual.gd")

const HANG_HEIGHT := 3.0             # |3.0 - 0.9| > Combat.MAX_VERTICAL_REACH: out of reach while hanging
const FLY_HEIGHT := 2.8
const DASH_HEIGHT := 1.1
const DRAIN_HEIGHT := 1.7            # within reach while it drains
const HEIGHT_SPEED := 3.5
const KEEP_AWAY := 3.5
const DASH_SPEED := 12.0
const DASH_LANE_WIDTH := 1.2
const DASH_HIT_AHEAD := 0.4
const DASH_START_FRACTION := 0.85
const DASH_DESCENT := 0.4            # fraction of the lane over which it swoops down to DASH_HEIGHT
const DRAIN_MIN_DIST := 2.5
const DRAIN_MAX_DIST := 9.0
const DRAIN_BREAK_DIST := 11.0
const DRAIN_COOLDOWN := 9.0
const DRAIN_CHECK := 0.2
const DRAIN_MARK_RADIUS := 0.7
const DRAIN_COLOR := Color(0.86, 0.36, 0.62)
const WARD_LIGHT := 0.45
const FEINT_CHANCE := 0.35
const FEINT_AT := 0.5
const LANE_REFRESH := 0.1
const VELVET := Color(0.62, 0.22, 0.38)
const BREAK_CAPTIONS := {
	"light": "[light floods the drain mark - the link snaps]",
	"sight": "[the drain link is cut off - the mark snaps]",
	"range": "[the drain link stretches too thin and snaps]",
	"hit": "[the drain mark snaps]",
	"target": "[the drain mark snaps]",
}
const HINT_DRAIN := "hint_velvet_wing_drain"
const DRAIN_HINT_TEXT := "A Velvet Wing drained you. Break its mark next time: raise your lantern ({lantern}) inside the mark, step into candle or lamp light, out of its sight, or strike it."

var hover_y: float = HANG_HEIGHT
var next_attack: String = ""         # tests / scripted fights: "dash" | "drain"
var attack_kind: String = ""
var ward_light_override: float = -1.0   # tests: >= 0 replaces the ward-light sample at Krystal (not her lantern)
var dashes_done: int = 0
var dashes_missed: int = 0
var feints: int = 0
var drains_completed: int = 0
var drains_broken: int = 0
var last_break_reason: String = ""
var healed_total: float = 0.0
var _def: Dictionary = {}
var _drain_cd: float = 0.0
var _drain_check_t: float = 0.0
var _dash_from_y: float = FLY_HEIGHT
var _dash_hit := false
var _feint_pending := false
var _feint_used := false
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _tether: MeshInstance3D = null


func _init() -> void:
	hit_color = Color(0.86, 0.58, 0.74)
	committed_states = ["dash", "drain"]
	needs_clear_shot = true


func _default_id() -> String:
	return "velvet_wing"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.3


func _body_height() -> float:
	return 0.6


func _knockback_scale() -> float:
	return 1.1


func _exit_tree() -> void:
	super._exit_tree()
	_hide_tether()


func rest_height() -> float:
	return float(data.get("rest_height", 1.4))


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * hover_y


func attack_origin() -> Vector3:
	return global_position + Vector3.UP * hover_y


func is_reachable_height() -> bool:
	return hover_y <= 0.9 + Combat.MAX_VERTICAL_REACH - 0.05


func _line_of_sight(p: Node3D) -> bool:
	if not is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, get_aim_point(), p.global_position + Vector3.UP * 0.9, [self, p], 1)


func _target_height() -> float:
	match state:
		"idle", "wander", "return":
			return HANG_HEIGHT
		"telegraph":
			return DRAIN_HEIGHT if attack_kind == "drain" else FLY_HEIGHT
		"drain":
			return DRAIN_HEIGHT
		"recover", "stunned", "flinch", "dead":
			return rest_height()
	return FLY_HEIGHT


## Hangs still: never wanders off its roost.
func _st_idle(_delta: float) -> void:
	if _should_aggro():
		_enter("chase")


func _st_wander(_delta: float) -> void:
	_enter("idle", 1.0)


func _st_chase(delta: float) -> void:
	if _chase_valid() and _player != null:
		var to := _player.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < KEEP_AWAY and dist > 0.01 and (_cooldown > 0.0 or not _can_start_attack()):
			_desired_vel = -to / dist * float(data.get("speed", 3.0)) * 0.8
			_face(to / dist, delta)
			return
	super._st_chase(delta)


# --- Attacks -----------------------------------------------------------------------------------------------------

func dash_distance() -> float:
	return float(attack_def("dash").get("distance", 7.0))


func drain_ready() -> bool:
	return _drain_cd <= 0.0


func lane_length() -> float:
	return _lane_len


func attack_reach() -> float:
	if next_attack == "drain" or (next_attack == "" and drain_ready()):
		return DRAIN_MAX_DIST
	return dash_distance() * DASH_START_FRACTION


func _can_start_attack() -> bool:
	return _shot_clear and not overlap_blocked()


func _choose_attack() -> void:
	var kind := next_attack
	if kind == "":
		var dist := _flat_dist_to_player()
		var dash_ok := dist <= dash_distance() * DASH_START_FRACTION
		if drain_ready() and dist >= DRAIN_MIN_DIST and (not dash_ok or health.hp < health.max_hp or _rng.randf() < 0.35):
			kind = "drain"
		else:
			kind = "dash"
	next_attack = ""
	attack_kind = kind
	_def = attack_def(kind)
	_feint_pending = false
	if kind == "dash" and not _feint_used and dashes_done >= 1 and Combat.current_intensity() == 2 and _rng.randf() < FEINT_CHANCE:
		_feint_pending = true
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack(kind)


func telegraph_duration() -> float:
	return attack_telegraph(_def) + intensity_telegraph_bonus()


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	_lane_clip_t = 0.0
	_drain_check_t = 0.0
	if attack_kind == "drain":
		Audio.play_3d("shade_telegraph", get_aim_point(), -3.0, 0.1)
		announce_tell(_def, "[a thin, hungry hum]")
	else:
		Audio.play_3d("shade_drift", get_aim_point(), -2.0, 0.1)
		announce_tell(_def, "[a velvet cape snaps shut]")
	_update_mark(true)


## Forces the Intense feint on the next dash wind-up (tests).
func force_feint() -> void:
	_feint_pending = true
	_feint_used = false


func _tick_extra(delta: float) -> void:
	_drain_cd = maxf(_drain_cd - delta, 0.0)
	if state != "dash":
		hover_y = move_toward(hover_y, _target_height(), HEIGHT_SPEED * delta)
	if state == "telegraph":
		if attack_kind == "dash" and _feint_pending and state_time >= _state_len * FEINT_AT:
			_feint_pending = false
			_feint_used = true
			feints += 1
			_enter("telegraph", telegraph_duration())     # a separate, full final tell (lane re-tracks, sound replays)
			return
		_lane_clip_t -= delta
		_update_mark(_lane_clip_t <= 0.0 and state_time <= _state_len * TELEGRAPH_TRACK)
		if attack_kind == "drain":
			_drain_watch(delta)
	elif state == "drain":
		_update_tether()
		_drain_watch(delta)


func _update_mark(reclip: bool) -> void:
	var m := mark()
	var locked := state_time > _state_len * TELEGRAPH_TRACK
	if attack_kind == "drain":
		var t := current_target()
		if t != null:
			if not m.is_showing() or m.kind != "ring":
				m.show_ring(t.global_position, DRAIN_MARK_RADIUS, DRAIN_COLOR)
			else:
				m.move_ring(t.global_position)        # the mark follows her through the wind-up (no reallocation)
			_update_tether()
		m.set_progress(state_time / maxf(_state_len, 0.001), true)
		return
	var fwd := _forward()
	if reclip:
		_lane_clip_t = LANE_REFRESH
		_lane_len = float(lane_clip(global_position, fwd, dash_distance())["length"])
	if not m.is_showing() or m.kind != "lane":
		m.show_lane(global_position, global_position + fwd * _lane_len, DASH_LANE_WIDTH, TelegraphFx.DANGER)
	elif not locked:
		m.move_lane(global_position, global_position + fwd * _lane_len)
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	if attack_kind == "drain":
		var t := current_target()
		var why := _drain_break_reason(t)
		if why != "":
			_break_drain(why)
			return
		_enter("drain", float(_def.get("channel", 2.0)))
		_drain_check_t = DRAIN_CHECK
		_update_tether()
		return
	_dash_from_y = hover_y
	_dash_hit = false
	_enter("dash", 0.0)
	_lane_len = charge_begin(_attack_dir, dash_distance(), DASH_SPEED)
	var m := mark()
	m.show_lane(global_position, charge_lane_end(), DASH_LANE_WIDTH, TelegraphFx.DANGER)
	m.set_progress(1.0, true)
	Audio.play_3d("dodge", get_aim_point(), -2.0, 0.1)


func _st_custom(state_name: String, delta: float) -> void:
	match state_name:
		"dash":
			var r := charge_step(delta, DASH_HIT_AHEAD, DASH_LANE_WIDTH * 0.5, attack_damage_for(_def), float(data.get("knockback", 4.5)))
			var k := clampf(_charge_travel / maxf(_lane_len * DASH_DESCENT, 0.01), 0.0, 1.0)
			hover_y = lerpf(_dash_from_y, DASH_HEIGHT, k)
			match r:
				"hit":
					_dash_hit = true
					_end_dash()
				"done", "wall":
					_end_dash()
				_:
					if state_time > _lane_len / DASH_SPEED + 0.6:
						_end_dash()
		"drain":
			if state_time >= _state_len:
				_finish_drain()


func _end_dash() -> void:
	dashes_done += 1
	if not _dash_hit:
		dashes_missed += 1
	hover_y = minf(hover_y, maxf(rest_height(), DASH_HEIGHT))
	_enter("recover", recover_duration())


# --- Drain -------------------------------------------------------------------------------------------------------

## Why the drain link would break right now ("" = it holds): "sight" (a wall / structure cuts the line),
## "light" (ward-light reaches her, or her raised lantern inside the drain mark), "range" (too far) or "target"
## (no valid target).
func _drain_break_reason(t: Node3D) -> String:
	if t == null or not is_instance_valid(t) or not is_valid_victim(t) or not _can_hunt:
		return "target"
	var p := t.global_position
	if Vector2(p.x - global_position.x, p.z - global_position.z).length() > DRAIN_BREAK_DIST:
		return "range"
	if not has_clear_shot(t):
		return "sight"
	if lantern_in_mark(t) or ward_light_at(p + Vector3.UP * 0.9) >= WARD_LIGHT:
		return "light"
	return ""


## Krystal's raised lantern (the target's `lantern_on`: Game.player in play) is ward-light for the drain only while
## she stands inside the drain mark (DRAIN_MARK_RADIUS of its centre, flat).
func lantern_in_mark(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not Combat.truthy(t.get("lantern_on")):
		return false
	var c := drain_mark_center(t)
	var p := t.global_position
	return Vector2(p.x - c.x, p.z - c.z).length() <= DRAIN_MARK_RADIUS


## Centre of the drain mark on the ground (it follows her through the wind-up and stays put for the channel);
## her own position while no drain mark is shown.
func drain_mark_center(t: Node3D) -> Vector3:
	if _mark != null and is_instance_valid(_mark) and String(_mark.get("kind")) == "ring":
		var c: Vector3 = _mark.get("center")
		return c
	if t != null and is_instance_valid(t):
		return t.global_position
	return global_position


## Lumi's Glimmerstep (companion_combat.gd calls expose(seconds) on enemies inside its light pulse): a deliberate
## burst of ward-light, so a drain in progress (wind-up or channel) breaks at once with reason "light". Nothing else.
func expose(_seconds: float) -> void:
	if is_dead() or not is_draining():
		return
	_break_drain("light")


func _drain_watch(delta: float) -> void:
	_drain_check_t -= delta
	if _drain_check_t > 0.0:
		return
	_drain_check_t = DRAIN_CHECK
	var why := _drain_break_reason(current_target())
	if why != "":
		_break_drain(why)


## Ward-light at `pos` from the light sources that break a drain: lit ward candles, lamps / lantern posts / placed
## light structures, braziers and Lumi's Glimmerstep pulse ("GlimmerPulse", a child light that is NOT in group
## "companion"). Skipped: Krystal herself (group "player": her lantern counts only inside the mark, lantern_in_mark)
## and companions' passive glow (group "companion": Lumi glowing beside her never breaks a drain).
func ward_light_at(pos: Vector3) -> float:
	if ward_light_override >= 0.0:
		return ward_light_override
	if not is_inside_tree():
		return 0.0
	var dark := 1.0
	for n in get_tree().get_nodes_in_group("light_source"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if (n as Node).is_in_group("player") or (n as Node).is_in_group("companion"):
			continue
		if n.has_method("is_light_active") and not Combat.truthy(n.call("is_light_active")):
			continue
		var r: Variant = n.get("light_radius")
		if not (r is float or r is int):
			continue
		var strength := 1.0
		var s: Variant = n.get("light_strength")
		if s is float or s is int:
			strength = clampf(float(s), 0.0, 1.0)
		dark *= 1.0 - clampf(Combat.light_falloff((n as Node3D).global_position.distance_to(pos), float(r)) * strength, 0.0, 1.0)
	return clampf(1.0 - dark, 0.0, 1.0)


func _break_drain(reason: String) -> void:
	drains_broken += 1
	last_break_reason = reason
	_drain_cd = DRAIN_COOLDOWN
	_hide_tether()
	hide_mark()
	Audio.play_3d("gloomling_flinch", get_aim_point(), -4.0, 0.1)
	Events.caption.emit(String(BREAK_CAPTIONS.get(reason, BREAK_CAPTIONS["hit"])))
	_def = attack_def("drain")
	_enter("recover", recover_duration())


## The channel held to the end: one hit through her health; it heals by exactly what was dealt.
func _finish_drain() -> void:
	_drain_cd = DRAIN_COOLDOWN
	var t := current_target()
	var dealt := 0.0
	if t != null and _drain_break_reason(t) == "":
		var dir := t.global_position - global_position
		dealt = deal_damage_to(t, attack_damage_for(_def), dir, 1.5)
	if dealt > 0.0 and health != null and not health.dead:
		healed_total += float(health.heal(dealt))
	if dealt > 0.0:
		Events.hint.emit(HINT_DRAIN, DRAIN_HINT_TEXT)     # once per save (HUD): how to break the next one
	drains_completed += 1
	_hide_tether()
	Audio.play_3d("shade_whisper", get_aim_point(), -4.0, 0.1)
	_enter("recover", recover_duration())


func is_draining() -> bool:
	return state == "drain" or (state == "telegraph" and attack_kind == "drain")


func tether_visible() -> bool:
	return _tether != null and is_instance_valid(_tether) and _tether.visible


func _update_tether() -> void:
	var t := current_target()
	if t == null or not is_inside_tree():
		return
	if _tether == null or not is_instance_valid(_tether):
		_tether = MeshInstance3D.new()
		_tether.name = "DrainTether"
		_tether.top_level = true
		_tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tether.set_meta("no_flash", true)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 1.0
		cm.radial_segments = 6
		cm.rings = 1
		_tether.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(DRAIN_COLOR, 0.75)
		_tether.material_override = mat
		add_child(_tether)
	var a := get_aim_point()
	var b := Combat.aim_point(t)
	var d := b - a
	var l := d.length()
	if l < 0.05:
		_tether.visible = false
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_tether.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)
	_tether.visible = true


func _hide_tether() -> void:
	if _tether != null and is_instance_valid(_tether):
		_tether.visible = false


# --- Reactions -----------------------------------------------------------------------------------------------------

## A hit on the wing breaks a drain in progress (its wind-up or its channel).
func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", get_aim_point(), -3.0, 0.15)
	HitFx.burst(get_aim_point(), VELVET, 6, 1.6, 0.6, -2.0, 0.5, 120.0)
	if is_draining() and not health.dead and health.hp > 0.0:
		_break_drain("hit")


func _on_state_changed(_prev: String, new_state: String) -> void:
	if new_state == "recover":
		_cooldown *= intensity_cooldown_mult()
		_feint_used = false
	if new_state != "drain" and new_state != "telegraph":
		_hide_tether()


func _on_player_died() -> void:
	super._on_player_died()
	_hide_tether()


# --- Feedback ------------------------------------------------------------------------------------------------------

func _on_alert() -> void:
	Audio.play_3d("dir_wrong_squeak", get_aim_point(), -6.0, 0.15)


func _idle_sound() -> void:
	Audio.play_3d("dir_wrong_squeak", get_aim_point(), -14.0, 0.2)


func _defeat_sound() -> String:
	return "lantern_off"


## Tumbles down in a swirl of velvet and dust (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(self, "hover_y", 0.25, 0.55).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "rotation:y", visual.rotation.y + TAU, 0.55)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.2).set_ease(Tween.EASE_IN)
	await tw.finished
	HitFx.burst(global_position + Vector3.UP * 0.3, VELVET, 12, 1.6, 0.8, -0.5, 0.8, 150.0)
