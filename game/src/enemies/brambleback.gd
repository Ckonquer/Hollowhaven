extends "res://src/enemies/enemy_base.gd"
## Brambleback (surface, Bramblewatch pocket): a squat bark-backed creature built around ONE committed charge.
##   chase -> telegraph (paws the dirt, lowers its armoured head; a lane with an arrow marks the charge path,
##            tracking for the first 60% of the wind-up, then locking) -> charge (straight and fast, hits at
##            most once) -> recover (skids to a stop with glowing soft flanks: the punish window)
##   A wall / structure / root in its lane ends the charge early with a bonk and a longer stun.
## Counterplay: side-step out of the marked lane and hit its flank. Front armour (data "front_armor" 0.4) cuts
## hits from the front to 60% - never to nothing - and front hits never stagger it; flank and back hits deal
## full damage and can stagger the wind-up (the legacy flinch rule).
## Stats: data/enemies.gd "brambleback". Sounds (existing names only): dig (dirt scrape), brambling_telegraph
## (charge), brambling_chatter (alert / idle / stunned), tree_fall (bonk), enemy_hurt, hit_soft (glance).

const Visual := preload("res://src/enemies/brambleback_visual.gd")

const CHARGE_SPEED := 9.0
const CHARGE_START_FRACTION := 0.8   # winds up once Krystal is within 80% of its lane length
const LANE_WIDTH := 1.4              # full width of the marked lane; she is hit if her body overlaps it
const HIT_AHEAD := 0.7               # the hit zone reaches this far beyond its body while charging
const BONK_EXTRA := 1.0              # extra stun after running into a wall
const FRONT_ARC_DEG := 120.0         # hits from within this arc of its facing are "front" hits
const LANE_REFRESH := 0.1            # re-clip the tracked lane at 10 Hz (not every frame)
const BARK_CHIPS := Color("8a6a48")
const DIRT_CHIPS := Color("9c7650")

var last_hit_frontal := false
var _def: Dictionary = {}
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _scrape_sounds: int = 0


## Health with directional front armour: hits arriving from the front are reduced, never to zero.
class ArmoredHealth extends "res://src/combat/health.gd":
	var body: Node3D = null
	var front_armor: float = 0.0
	var front_arc_deg: float = 120.0
	var last_frontal := false

	func apply_damage(amount: float, source: Node = null, dir: Vector3 = Vector3.ZERO) -> float:
		last_frontal = is_frontal(source, dir)
		var a := amount
		if last_frontal and front_armor > 0.0 and amount > 0.0:
			a = maxf(amount * (1.0 - clampf(front_armor, 0.0, 0.9)), minf(amount, 1.0))
		return super.apply_damage(a, source, dir)

	## `dir` is the direction the hit travels (attacker -> target); the attacker sits at -dir.
	func is_frontal(source: Node, dir: Vector3) -> bool:
		if body == null or not is_instance_valid(body):
			return false
		var fwd := -body.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			return false
		var to_src := Vector3.ZERO
		if dir.length_squared() > 0.0001:
			to_src = -Vector3(dir.x, 0.0, dir.z)
		elif source is Node3D and is_instance_valid(source):
			to_src = (source as Node3D).global_position - body.global_position
			to_src.y = 0.0
		if to_src.length_squared() < 0.0001:
			return false
		return rad_to_deg(fwd.normalized().angle_to(to_src.normalized())) <= front_arc_deg * 0.5


func _init() -> void:
	hit_color = Color(0.8, 0.64, 0.44)
	committed_states = ["charge"]
	needs_clear_shot = true


func _ready() -> void:
	super._ready()
	var h := health as ArmoredHealth
	if h != null:
		h.front_armor = float(data.get("front_armor", 0.0))
		h.front_arc_deg = FRONT_ARC_DEG
	_def = attack_def("charge")


func _default_id() -> String:
	return "brambleback"


func _build_visual() -> Node3D:
	return Visual.new()


func _make_health() -> Node:
	var h := ArmoredHealth.new()
	h.body = self
	return h


func _body_radius() -> float:
	return 0.55


func _body_height() -> float:
	return 1.0


func _knockback_scale() -> float:
	return 0.55


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 0.6


func attack_reach() -> float:
	return maxf(charge_distance() * CHARGE_START_FRACTION, float(data.get("attack_range", 2.2)))


func charge_distance() -> float:
	return float(_def.get("distance", 7.0))


func lane_length() -> float:
	return _lane_len


func _can_start_attack() -> bool:
	return _shot_clear


func _choose_attack() -> void:
	_def = attack_def("charge")
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack("charge")


func telegraph_duration() -> float:
	return attack_telegraph(_def)


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	_scrape_sounds = 0
	_lane_clip_t = 0.0
	_lane_len = charge_distance()
	_update_lane(true)
	announce_tell(_def, "[claws scrape the dirt]")


func _tick_extra(delta: float) -> void:
	if state != "telegraph":
		return
	# Two dirt scrapes during the wind-up (the sound tell), the lane follows its facing until it locks.
	var k := state_time / maxf(_state_len, 0.001)
	if _scrape_sounds == 0 or (_scrape_sounds == 1 and k >= 0.45):
		_scrape_sounds += 1
		Audio.play_3d("dig", global_position, -1.0, 0.12)
	_lane_clip_t -= delta
	_update_lane(_lane_clip_t <= 0.0 and state_time <= _state_len * TELEGRAPH_TRACK)


func _update_lane(reclip: bool) -> void:
	var dir := _forward()
	if reclip:
		_lane_clip_t = LANE_REFRESH
		_lane_len = float(lane_clip(global_position, dir, charge_distance())["length"])
	var locked := state_time > _state_len * TELEGRAPH_TRACK
	var m := mark()
	if not m.is_showing():
		m.show_lane(global_position, global_position + dir * _lane_len, LANE_WIDTH, TelegraphFx.DANGER)
	elif not locked:
		m.move_lane(global_position, global_position + dir * _lane_len)
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	var dir := _forward()
	_enter("charge", 0.0)
	_lane_len = charge_begin(dir, charge_distance(), CHARGE_SPEED)
	var m := mark()
	m.show_lane(global_position, charge_lane_end(), LANE_WIDTH, TelegraphFx.DANGER)
	m.set_progress(1.0, true)
	Audio.play_3d("brambling_telegraph", global_position + Vector3.UP * 0.5, 0.0, 0.05)


func _st_custom(state_name: String, delta: float) -> void:
	if state_name != "charge":
		return
	var r := charge_step(delta, HIT_AHEAD, LANE_WIDTH * 0.5, attack_damage_for(_def), float(data.get("knockback", 6.5)))
	match r:
		"hit", "done":
			_enter("recover", recover_duration())
		"wall":
			_bonk()
		_:
			if state_time > _lane_len / CHARGE_SPEED + 0.6:      # safety net: never runs on past its lane
				_enter("recover", recover_duration())


func _bonk() -> void:
	stun(recover_duration() + BONK_EXTRA)
	_cooldown = float(data.get("cooldown", 2.0))
	Audio.play_3d("tree_fall", global_position + Vector3.UP * 0.5, -4.0, 0.1)
	HitFx.chips(global_position + Vector3.UP * 0.7 + _forward() * 0.6, BARK_CHIPS, 10, 3.2, 0.7)
	Events.camera_shake.emit(0.12, 0.2)


## Front hits never stagger it (armour); flank / back hits follow the legacy flinch rule.
func can_stagger(amount: float, source: Node) -> bool:
	var h := health as ArmoredHealth
	if h != null and h.last_frontal:
		return false
	return super.can_stagger(amount, source)


func _on_hurt(_amount: float) -> void:
	var h := health as ArmoredHealth
	last_hit_frontal = h != null and h.last_frontal
	if last_hit_frontal:
		HitFx.spark(get_aim_point() + _forward() * 0.5)          # glances off the bark brow (plays hit_soft)
	else:
		Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 0.6, -3.0, 0.12)
		HitFx.chips(global_position + Vector3.UP * 0.7, BARK_CHIPS, 7, 3.0, 0.55)


func _on_alert() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.6, -1.0, 0.08)


func _idle_sound() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.6, -9.0, 0.08)


func _on_state_changed(_prev: String, new_state: String) -> void:
	if new_state == "stunned" or new_state == "recover":
		Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.6, -6.0, 0.2)


## Rolls onto its back, then a puff of bark and leaves (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(visual, "rotation:z", 1.4, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.2).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.5
	HitFx.chips(pos, BARK_CHIPS, 14, 3.6, 0.8)
	HitFx.chips(pos, DIRT_CHIPS, 8, 3.0, 0.7)
	HitFx.burst(pos, Color(0.8, 0.9, 0.7, 0.6), 6, 1.2, 1.6, 0.5, 0.6)
