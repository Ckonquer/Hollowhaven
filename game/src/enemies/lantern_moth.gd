extends "res://src/enemies/enemy_base.gd"
## Lantern Moth (surface dusk pocket by Mirror Pond, Tobin's annex): a round moth with lamp-bright wings.
##   It flies at HOVER_HEIGHT (out of melee reach) and keeps a little distance while it cannot shoot.
##   chase -> telegraph (wings spread and FLARE, an orb swells in front of it; data 1.1 s) -> it releases ONE
##   slow drifting orb (only with a clear world|structure line to Krystal: never through walls) -> recover =
##   it settles to data "rest_height" (1.2 m, inside melee reach) and rests while its orb is still drifting
##   (bounded by the orb's flight time), then for data recover (1.8 s): the punish window after a dodge is
##   never used up watching a slow orb cross the room.
##   Under a low ceiling / overhang it flies lower (HEADROOM under it, never below the rest height), so it never
##   hovers or shoots from inside a ceiling; one upward ray per perception tick (0.2 s).
## One orb per moth at a time (the shared pooled src/combat/projectile.gd with max_per_shooter 1, or the local
## enemy_projectile.gd fallback); the number of projectiles alive is capped globally by that script.
## Counterplay: roll through the orb (dodge i-frames) or step behind cover, then hit it while it rests.
## Stats: data/enemies.gd "lantern_moth". Sounds (existing names only): lantern_on (flare), shade_drift
## (release / flutter), lantern_off (fizzle / defeat), shade_whisper (alert / idle), enemy_hurt.

const Visual := preload("res://src/enemies/lantern_moth_visual.gd")

const HOVER_HEIGHT := 2.9            # body centre while flying: |2.9 - 0.9| > Combat.MAX_VERTICAL_REACH
const HEIGHT_SPEED := 3.2            # m/s when rising / settling
const KEEP_AWAY := 4.0               # drifts back if Krystal is closer than this while it cannot shoot
const ORB_COLOR := Color(1.0, 0.82, 0.46)
const ORB_HOMING := 0.5              # rad/s of gentle drift toward her during the first half of its flight
const HEADROOM := 0.45               # keeps the body centre this far under a ceiling / overhang
const DUST := Color(1.0, 0.92, 0.7, 0.7)

var hover_y: float = HOVER_HEIGHT
var hover_cap: float = HOVER_HEIGHT  # flying height allowed by the ceiling above it (perception, 0.2 s)
var orb: Node = null
var shots_fired: int = 0
var _def: Dictionary = {}
var _orb_hold: float = 0.0           # rest held (at most this much longer) while its orb drifts
var _head_q: PhysicsRayQueryParameters3D = null


func _init() -> void:
	hit_color = Color(1.0, 0.9, 0.62)
	needs_clear_shot = true


func _ready() -> void:
	super._ready()
	_def = attack_def("dust_orb")


func _default_id() -> String:
	return "lantern_moth"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.3


func _body_height() -> float:
	return 0.6


func _knockback_scale() -> float:
	return 1.2


func rest_height() -> float:
	return float(data.get("rest_height", 1.2))


## Aim point follows the flying body (out of reach while hovering, reachable while resting).
func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * hover_y


func attack_origin() -> Vector3:
	return global_position + Vector3.UP * hover_y + _forward() * 0.35


func is_resting() -> bool:
	return hover_y <= rest_height() + 0.05


func _line_of_sight(p: Node3D) -> bool:
	if not is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, get_aim_point(), p.global_position + Vector3.UP * 0.9, [self, p], 1)


func _target_height() -> float:
	if state == "recover" or state == "stunned" or state == "dead":
		return rest_height()
	return minf(HOVER_HEIGHT, hover_cap)


func _perceive_extra() -> void:
	hover_cap = _headroom()


## Flying height the space above allows: HOVER_HEIGHT in the open, else HEADROOM under the ceiling (never
## below the rest height). One reused upward ray.
func _headroom() -> float:
	if not is_inside_tree():
		return HOVER_HEIGHT
	if _head_q == null:
		_head_q = PhysicsRayQueryParameters3D.new()
		_head_q.collision_mask = Combat.LOS_MASK
		var ex: Array[RID] = [get_rid()]
		_head_q.exclude = ex
	_head_q.from = global_position + Vector3.UP * 0.3
	_head_q.to = global_position + Vector3.UP * (HOVER_HEIGHT + HEADROOM)
	var hit := get_world_3d().direct_space_state.intersect_ray(_head_q)
	if hit.is_empty():
		return HOVER_HEIGHT
	return maxf((hit["position"] as Vector3).y - global_position.y - HEADROOM, rest_height())


## The moth's tell is on its body (flaring wings + a swelling orb), not on the ground: the orb drifts.
func _tick_extra(delta: float) -> void:
	# Ducks quickly under a ceiling it has just flown beneath; settles / rises at the calm speed otherwise.
	var rate := HEIGHT_SPEED * (3.0 if hover_y > hover_cap + 0.05 else 1.0)
	hover_y = move_toward(hover_y, _target_height(), rate * delta)


func has_orb_in_flight() -> bool:
	return projectile_in_flight(orb)


func _can_start_attack() -> bool:
	return _shot_clear and not has_orb_in_flight()


func _st_chase(delta: float) -> void:
	if _chase_valid() and _player != null:
		var to := _player.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < KEEP_AWAY and dist > 0.01 and (_cooldown > 0.0 or not _can_start_attack()):
			_desired_vel = -to / dist * float(data.get("speed", 2.4)) * 0.8
			_face(to / dist, delta)
			return
	super._st_chase(delta)


func _choose_attack() -> void:
	_def = attack_def("dust_orb")


func telegraph_duration() -> float:
	return attack_telegraph(_def)


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	Audio.play_3d("lantern_on", get_aim_point(), -2.0, 0.08)
	announce_tell(_def, "[wings hum and flare]")


func _telegraph_finished() -> void:
	var t := current_target()
	var fired: Node = null
	if t != null and _release_clear(t) and not has_orb_in_flight():
		fired = fire_projectile(attack_origin(), t, {
			"damage": attack_damage_for(_def), "speed": float(_def.get("speed", 5.0)),
			"range": float(_def.get("range", 12.0)), "knockback": float(data.get("knockback", 3.0)),
			"homing": ORB_HOMING, "color": ORB_COLOR, "radius": 0.18})
	_orb_hold = 0.0
	if fired != null:
		orb = fired
		shots_fired += 1
		_orb_hold = float(_def.get("range", 12.0)) / maxf(float(_def.get("speed", 5.0)), 0.5) + 0.25
		Audio.play_3d("shade_drift", get_aim_point(), -2.0, 0.1)
	else:
		Audio.play_3d("lantern_off", get_aim_point(), -6.0, 0.1)      # no clear line: the flare fizzles
	_enter("recover", recover_duration())


## A clear line from the release point to her AND from its body to the release point (the orb appears a little
## in front of the body: never on the far side of a wall edge or overhang lip). Two rays, once per shot.
func _release_clear(t: Node3D) -> bool:
	if not has_clear_shot(t):
		return false
	if not is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, get_aim_point(), attack_origin(), [self], Combat.LOS_MASK)


## Rests while its orb still drifts (at most the orb's flight time), then for data recover.
func _st_recover(delta: float) -> void:
	if _orb_hold > 0.0:
		_orb_hold -= delta
		if has_orb_in_flight():
			state_time = 0.0
		else:
			_orb_hold = 0.0
	super._st_recover(delta)


func _on_alert() -> void:
	Audio.play_3d("shade_whisper", get_aim_point(), -8.0, 0.2)


func _idle_sound() -> void:
	Audio.play_3d("shade_drift", get_aim_point(), -12.0, 0.2)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", get_aim_point(), -3.0, 0.2)
	HitFx.burst(get_aim_point(), DUST, 8, 1.6, 0.6, -1.0, 0.6, 120.0)


func _defeat_sound() -> String:
	return "lantern_off"


## Flutters down, the glow fades out in a puff of warm dust (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(self, "hover_y", 0.25, 0.6).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "rotation:y", visual.rotation.y + TAU, 0.6)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.2).set_ease(Tween.EASE_IN)
	await tw.finished
	HitFx.burst(global_position + Vector3.UP * 0.3, DUST, 14, 1.8, 0.9, -0.5, 0.9, 150.0)
