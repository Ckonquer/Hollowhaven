extends "res://src/enemies/enemy_base.gd"
## Brood Skitter (deeper Below pockets, the Works, the Matron's capped adds): a small skittering hollows-thing.
## Arachnophobia: the PALE SPROUT - a floating pale seed with a root lash. Different silhouette (no legs, a
## tall floating seed with hanging root tendrils instead of a low eight-legged body), different name
## (ItemDB alt_name) and a fully different set of sound names (SOUNDS vs ALT_SOUNDS share none). The setting
## can change while it is alive: the visual is rebuilt in place, the fight state is untouched.
##   chase -> telegraph: legs draw in (roots curl in) and a small ring is drawn on the ground where it will
##   land - the ring is FIXED once drawn -> leap (a short kinematic arc; the Pale Sprout floats and lashes a
##   root onto the ring) -> lands: one hit if Krystal is still on the ring -> recover (data 1.1 s)
## Easy to stagger (data "stagger_easy"): every non-lethal hit flinches it, even during its recovery, and a
## hit during the wind-up cancels the leap; only the leap itself is uninterruptible.
## Wind-up: data says 0.7 s, the shared committed-attack floor makes it 1.0 s (enemy_base
## MIN_COMMITTED_TELEGRAPH).
## Minion use (the Matron): Factory.spawn("brood_skitter", parent, xform, {"home": c, "wander_radius": r,
## "alert": true, "no_drops": true, "speed_scale": 0.8 (Gentle: a slower minion)}).
## Stats: data/enemies.gd "brood_skitter".

const Visual := preload("res://src/enemies/brood_skitter_visual.gd")

const LEAP_TIME := 0.4
const LEAP_HEIGHT := 0.8
const LAND_RADIUS := 0.9             # the landing ring; she is hit if her body overlaps it
## Sound names (existing names only). The two sets share NO name.
const SOUNDS := {"alert": "weaver_skitter", "telegraph": "weaver_rattle", "leap": "weaver_skitter",
	"land": "weaver_drop", "hurt": "enemy_hurt", "idle": "weaver_skitter", "defeat": "enemy_defeat"}
const ALT_SOUNDS := {"alert": "dir_root_creak", "telegraph": "shade_telegraph", "leap": "shade_drift",
	"land": "dig", "hurt": "grass_pull", "idle": "shade_drift", "defeat": "harvest_crop"}
const CAPTION := "[something skitters and tenses]"
const ALT_CAPTION := "[roots creak and curl]"
const BODY_CHIPS := Color("8e7ea8")
const ALT_CHIPS := Color("e9e3cf")

var using_alt := false
var speed_scale: float = 1.0
var _def: Dictionary = {}
var _land := Vector3.ZERO


func _init() -> void:
	hit_color = Color(0.86, 0.8, 0.92)
	committed_states = ["leap"]
	needs_clear_shot = true


func setup(params: Dictionary) -> void:
	super.setup(params)
	speed_scale = clampf(float(params.get("speed_scale", speed_scale)), 0.3, 1.5)


func _ready() -> void:
	super._ready()
	_def = attack_def("leap")
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func _default_id() -> String:
	return "brood_skitter"


static func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


func _build_visual() -> Node3D:
	using_alt = _arachno()
	var v: Node3D = Visual.new()
	v.call("setup", {"sprout": using_alt})
	v.name = "Visual"
	return v


func _body_radius() -> float:
	return 0.3


func _body_height() -> float:
	return 0.5


func _knockback_scale() -> float:
	return 1.5


func _speed_scale() -> float:
	return speed_scale


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * (0.62 if using_alt else 0.3)


## Name shown to the player (the Pale Sprout in arachnophobia mode).
func display_name() -> String:
	return ItemDB.enemy_display_name(enemy_id)


## Sound name for a cue in the current mode.
func snd(kind: String) -> String:
	return String((ALT_SOUNDS if using_alt else SOUNDS).get(kind, ""))


func leap_distance() -> float:
	return float(_def.get("distance", 3.0))


func landing_point() -> Vector3:
	return _land


func _can_start_attack() -> bool:
	return _shot_clear


func _choose_attack() -> void:
	_def = attack_def("leap")


func telegraph_duration() -> float:
	return attack_telegraph(_def)


func recover_duration() -> float:
	return attack_recover(_def)


func _on_telegraph_start() -> void:
	var t := current_target()
	var want := t.global_position if t != null else global_position + _forward() * leap_distance()
	_land = leap_target(want, leap_distance())
	_show_ring()
	Audio.play_3d(snd("telegraph"), global_position + Vector3.UP * 0.4, -2.0, 0.1)
	announce_tell(_def, ALT_CAPTION if using_alt else CAPTION)


func _show_ring() -> void:
	var m := mark()
	m.show_ring(_land, LAND_RADIUS, TelegraphFx.PALE if using_alt else TelegraphFx.DANGER)
	m.set_progress(state_time / maxf(_state_len, 0.001), true)


## The landing ring is fixed: it turns to face the ring (not Krystal) for the whole wind-up.
func _st_telegraph(delta: float) -> void:
	if not _can_hunt or _player == null or not is_instance_valid(_player):
		_enter("return")
		return
	var to := _land - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_face(to.normalized(), delta, 2.0)
	if _mark != null:
		_mark.set_progress(state_time / maxf(_state_len, 0.001), true)
	if state_time >= _state_len:
		_telegraph_finished()


func _telegraph_finished() -> void:
	_enter("leap", LEAP_TIME)
	_land = leap_begin(_land, LEAP_TIME, LEAP_HEIGHT, leap_distance())
	Audio.play_3d(snd("leap"), global_position + Vector3.UP * 0.4, -3.0, 0.1)


func _st_custom(state_name: String, delta: float) -> void:
	if state_name != "leap":
		return
	if leap_step(delta):
		leap_land_hit(LAND_RADIUS, attack_damage_for(_def), float(data.get("knockback", 3.5)))
		Audio.play_3d(snd("land"), global_position + Vector3.UP * 0.2, -3.0, 0.1)
		HitFx.chips(global_position + Vector3.UP * 0.1, ALT_CHIPS if using_alt else Color("6e6060"), 5, 2.0, 0.45)
		_enter("recover", recover_duration())
	elif state_time > LEAP_TIME + 0.25:
		_enter("recover", recover_duration())


func _easy() -> bool:
	return bool(data.get("stagger_easy", false))


## Easy to stagger: every non-lethal hit flinches it (no immunity window).
func can_stagger(amount: float, source: Node) -> bool:
	return true if _easy() else super.can_stagger(amount, source)


## Only the leap (and a stun) can't be interrupted; its recovery can.
func _is_uninterruptible() -> bool:
	if _easy():
		return state == "leap" or state == "stunned"
	return super._is_uninterruptible()


func _stagger(amount: float, source: Node) -> void:
	if _easy():
		_flinch_immune = 0.0
		_enter("flinch", FLINCH_TIME)
	else:
		super._stagger(amount, source)


func _on_settings_changed(key: String) -> void:
	if key != "arachnophobia" or using_alt == _arachno() or state == "dead":
		return
	if visual != null and is_instance_valid(visual):
		visual.queue_free()
	visual = _build_visual()
	add_child(visual)
	if visual.has_method("set_state"):
		visual.set_state(state, _state_len)
	if _mark != null and is_instance_valid(_mark) and _mark.is_showing() and (state == "telegraph" or state == "leap"):
		_show_ring()                               # recolour the ring for the new mode


func _on_alert() -> void:
	Audio.play_3d(snd("alert"), global_position + Vector3.UP * 0.4, -3.0, 0.12)


func _idle_sound() -> void:
	Audio.play_3d(snd("idle"), global_position + Vector3.UP * 0.4, -10.0, 0.15)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d(snd("hurt"), global_position + Vector3.UP * 0.4, -3.0, 0.12)
	HitFx.chips(get_aim_point(), ALT_CHIPS if using_alt else BODY_CHIPS, 5, 2.4, 0.45)


func _defeat_sound() -> String:
	return snd("defeat")


## Curls up and puffs away (the Pale Sprout bursts into seed fluff). No gore.
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.2, 0.5, 1.2), 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.18).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := get_aim_point()
	if using_alt:
		HitFx.burst(pos, Color(1.0, 0.98, 0.9, 0.8), 12, 1.4, 0.8, 0.6, 1.0, 150.0)
	else:
		HitFx.chips(pos, BODY_CHIPS, 8, 2.6, 0.6)
		HitFx.burst(pos, Color(0.8, 0.75, 0.9, 0.5), 6, 1.2, 1.2, 0.4, 0.6)
