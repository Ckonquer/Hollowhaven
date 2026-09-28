extends Node3D
## Base class for the companion visuals (mochi_visual.gd, pebble_visual.gd, lumi_visual.gd).
## Everything is procedural: a small pose solver combines a gait (per creature), a mood (idle,
## sleep, scared, alert, pinned, rest), a one-shot action (happy, celebrate, gather, headbutt ...),
## head look-at, breathing and blinking, then the subclass maps the pose onto its parts.
## Models face +Z; the owner rotates this node (rotation.y) toward where the creature is heading.
##
## API used by companion.gd (and the preview stage):
##   set_motion(speed, grounded)       horizontal speed in m/s drives the gait
##   set_look_target(pos_or_null)      world position to look at (head turns, clamped)
##   set_mood(name)                    idle | sleep | scared | alert | pinned | rest
##   play_action(name) -> float        one-shot action, returns its length in seconds
##   show_emote(kind, seconds)         bubble above the head (see emote_icons.gd)
##   set_glow(level)                   0..1.5, only Lumi uses it (dims / brightens)
##   play_anim(name)                   preview helper: any action, mood, or "walk"/"run"
## Signals: action_event(name) at the impact moment of an action, action_finished(name).

signal action_event(action_name: String)
signal action_finished(action_name: String)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Icons := preload("res://src/companions/emote_icons.gd")
const Fx := preload("res://src/companions/companion_fx.gd")

const EYE_DARK := Color("2b2a3f")
const CHEEK := Color("f4a3a8")
const OUTLINE_COLOR := Color(0.2, 0.13, 0.15)

## Action lengths (seconds) and the normalised time at which action_event fires.
const ACTIONS := {
	"happy": [1.1, 0.25], "celebrate": [2.4, 0.1], "notice": [1.5, 0.05], "dizzy": [2.0, 0.0],
	"gather": [1.5, 0.6], "headbutt": [0.85, 0.45], "pat": [1.6, 0.5], "eat": [1.4, 0.35],
	"refuse": [1.9, 0.1], "present": [1.5, 0.55], "glow_pulse": [1.3, 0.3], "salute": [1.7, 0.4],
	"wave": [1.3, 0.2], "polish": [2.2, 0.5], "stretch": [1.6, 0.5], "tumble": [1.0, 0.8],
	"sniff": [1.6, 0.5], "bounce_off": [0.7, 0.1], "stomp": [0.7, 0.5], "peek": [1.1, 0.35],
	# Chapter Two (MP §6): basic attacks (the damage lands on the impact frame, see companion_combat.gd),
	# the signature-skill cast, Mochi's brave step and the 5-heart affectionate animations.
	"spore_puff": [0.75, 0.42], "stone_bump": [0.8, 0.45], "light_bolt": [0.7, 0.4], "cast": [1.0, 0.35],
	"brave_step": [1.6, 0.55], "mochi_twirl": [1.8, 0.4], "pebble_hug": [1.8, 0.4], "lumi_glow_spin": [1.8, 0.4],
}
const MOODS := ["idle", "sleep", "scared", "alert", "pinned", "rest"]

# --- Tunables (subclasses change these in _build) ---
var emote_height := 0.85
var gait_speed_ref := 4.5
var outline_width := 0.012
var head_body_factor := 1.0     # how much of the head look is applied to the whole body (no neck)
var head_height := 0.3

# --- Inputs ---
var move_speed := 0.0
var grounded := true
var look_target: Variant = null
var mood := "idle"
var glow_level := 1.0

# --- Pose parameters (reset every frame; gait/mood/action write them; subclass applies them) ---
var p_hop := 0.0
var p_squash := 1.0
var p_lean := 0.0
var p_roll := 0.0
var p_spin := 0.0
var p_shake := 0.0
var p_tremble := 0.0
var p_shrink := 1.0
var p_head_yaw := 0.0
var p_head_pitch := 0.0
var p_arm_l := 0.0
var p_arm_r := 0.0
var p_brow := 0.0
var p_mouth := 0.0
var p_eye := 1.0
var p_eye_happy := 0.0           # 1 = "^ ^" squint-smile
var p_step := 0.0
var p_step_lift := 0.0
var p_tail := 0.0
var p_glow_boost := 0.0
var p_freeze := false

# --- Parts ---
var rig: Node3D
var body: Node3D
var eye_nodes: Array = []
var emote_anchor: Node3D

var _emote: Sprite3D
var _emote_t := 0.0
var _emote_len := 0.0
var _emote_kind := ""
var _t := 0.0
var _phase := 0.0
var _blink_timer := 2.0
var _blink_t := -1.0
var _double_blink := false
var _action := ""
var _action_t := 0.0
var _action_len := 0.0
var _action_fire_at := 0.0
var _action_fired := false
var _look_yaw := 0.0
var _look_pitch := 0.0
var _glance_timer := 2.0
var _glance_yaw := 0.0
var _sm_shrink := 1.0
var _sm_lean := 0.0
var _sm_roll := 0.0
var _preview_speed := -1.0
var _preview_loop := ""
var _sleep_z_t := 0.0
var _last_hop := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	body = Node3D.new()
	body.name = "Body"
	rig.add_child(body)
	emote_anchor = Node3D.new()
	emote_anchor.name = "EmoteAnchor"
	add_child(emote_anchor)
	_build()
	emote_anchor.position = Vector3(0, emote_height, 0)
	_emote = Sprite3D.new()
	_emote.name = "Emote"
	_emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote.pixel_size = 0.0042
	_emote.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_emote.render_priority = 10
	_emote.visible = false
	emote_anchor.add_child(_emote)
	_blink_timer = _rng.randf_range(1.0, 3.5)
	_glance_timer = _rng.randf_range(1.5, 4.0)


## Optional preview/setup params: {"anim": "happy"}.
func setup(params: Dictionary) -> void:
	if params.has("anim"):
		play_anim.call_deferred(String(params["anim"]))


# --- Public API ---------------------------------------------------------------------------------

func set_motion(speed: float, is_grounded: bool = true) -> void:
	move_speed = speed
	grounded = is_grounded


func set_look_target(pos: Variant) -> void:
	look_target = pos if pos is Vector3 else null


func set_mood(m: String) -> void:
	if not MOODS.has(m):
		m = "idle"
	if m == mood:
		return
	var was := mood
	mood = m
	_on_mood_changed(was, m)
	if m == "sleep":
		_sleep_z_t = 0.0
	elif was == "sleep" and _emote_kind == "zz":
		hide_emote()


func get_action() -> String:
	return _action


func is_busy() -> bool:
	return _action != ""


## Starts a one-shot action. Returns its length (0 if unknown).
func play_action(action_name: String) -> float:
	if not ACTIONS.has(action_name):
		return 0.0
	if _action != "" and _action != action_name:
		action_finished.emit(_action)
	var spec: Array = ACTIONS[action_name]
	_action = action_name
	_action_t = 0.0
	_action_len = float(spec[0])
	_action_fire_at = float(spec[1])
	_action_fired = false
	_on_action_started(action_name)
	return _action_len


func stop_action() -> void:
	if _action != "":
		var a := _action
		_action = ""
		action_finished.emit(a)


func show_emote(kind: String, seconds: float = 1.8) -> void:
	if _emote == null:
		return
	_emote.texture = Icons.bubble(kind)
	_emote_kind = kind
	_emote_t = 0.0
	_emote_len = maxf(seconds, 0.4)
	_emote.visible = true
	_emote.modulate = Color(1, 1, 1, 1)
	_emote.scale = Vector3.ONE * 0.2


func hide_emote() -> void:
	if _emote != null:
		_emote.visible = false
	_emote_kind = ""


func get_emote_kind() -> String:
	return _emote_kind if _emote != null and _emote.visible else ""


func set_glow(level: float) -> void:
	glow_level = clampf(level, 0.0, 1.6)


## World position just above the head (emotes, effects).
func head_world_position() -> Vector3:
	return emote_anchor.global_position if emote_anchor != null and emote_anchor.is_inside_tree() else global_position + Vector3.UP * emote_height


## Preview helper used by tests/preview/preview_stage.gd (--preview-anim=<name>).
func play_anim(anim_name: String) -> void:
	match anim_name:
		"walk":
			_preview_speed = gait_speed_ref * 0.45
		"run":
			_preview_speed = gait_speed_ref * 1.0
		"idle":
			_preview_speed = 0.0
		_:
			if MOODS.has(anim_name):
				set_mood(anim_name)
			elif ACTIONS.has(anim_name):
				_preview_loop = anim_name
				play_action(anim_name)
				_preview_extra(anim_name)


# --- Frame update -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _preview_speed >= 0.0:
		move_speed = _preview_speed
	if _preview_loop != "" and _action == "":
		play_action(_preview_loop)
	_reset_pose()
	if not p_freeze:
		_gait(delta)
	_breathe()
	_mood_pose(delta)
	_update_action(delta)
	_update_look(delta)
	_update_blink(delta)
	_apply_pose(delta)
	_update_emote(delta)


func _reset_pose() -> void:
	p_hop = 0.0
	p_squash = 1.0
	p_lean = 0.0
	p_roll = 0.0
	p_spin = 0.0
	p_shake = 0.0
	p_tremble = 0.0
	p_shrink = 1.0
	p_head_yaw = 0.0
	p_head_pitch = 0.0
	p_arm_l = 0.0
	p_arm_r = 0.0
	p_brow = 0.0
	p_mouth = 0.0
	p_eye = 1.0
	p_eye_happy = 0.0
	p_step = 0.0
	p_step_lift = 0.0
	p_tail = 0.0
	p_glow_boost = 0.0
	p_freeze = mood == "alert" or mood == "pinned"


## Gait: subclasses override (hop / waddle / float). Default: gentle bob.
func _gait(delta: float) -> void:
	var r := clampf(move_speed / gait_speed_ref, 0.0, 1.6)
	_phase += delta * (2.0 + 7.0 * r)
	p_hop = absf(sin(_phase)) * 0.05 * r


func _breathe() -> void:
	var still := clampf(1.0 - move_speed / 0.8, 0.0, 1.0)
	p_squash *= 1.0 + sin(_t * 2.3) * 0.022 * still


func _mood_pose(delta: float) -> void:
	match mood:
		"sleep":
			p_eye = 0.0
			p_squash *= 0.94 + sin(_t * 1.25) * 0.035
			p_lean += 0.12
			p_head_pitch -= 0.12
			p_mouth = 0.15 + sin(_t * 1.25) * 0.1
			_sleep_z_t -= delta
			if _sleep_z_t <= 0.0:
				_sleep_z_t = 3.2
				show_emote("zz", 2.8)
		"scared":
			p_tremble = 0.012
			p_shrink = 0.86
			p_brow = 1.0
			p_eye = 1.15
			p_lean -= 0.08
		"alert":
			p_brow = 0.7
			p_eye = 1.15
			p_shrink = 0.97
		"rest":
			p_squash *= 0.93
		"pinned":
			pass


func _update_action(delta: float) -> void:
	if _action == "":
		return
	_action_t += delta
	var k := clampf(_action_t / maxf(_action_len, 0.01), 0.0, 1.0)
	if not _action_fired and k >= _action_fire_at:
		_action_fired = true
		_on_action_fire(_action)
		action_event.emit(_action)
	_action_pose(_action, k)
	if _action_t >= _action_len:
		var a := _action
		_action = ""
		action_finished.emit(a)


## Generic action poses; subclasses may extend (call super) for part-specific motion.
func _action_pose(a: String, k: float) -> void:
	var env := sin(k * PI)           # 0 -> 1 -> 0 envelope
	match a:
		"happy":
			p_hop += absf(sin(k * TAU)) * 0.2
			p_squash *= 1.0 + sin(k * TAU * 2.0) * 0.12
			p_eye_happy = env
			p_mouth = 0.8 * env
			p_arm_l = env
			p_arm_r = env
			p_tail = env
		"celebrate":
			var e := ease(k, -2.0)
			p_spin += e * TAU * 2.0
			p_hop += absf(sin(k * PI * 4.0)) * 0.22
			p_eye_happy = env
			p_mouth = env
			p_arm_l = 1.0 * env
			p_arm_r = 1.0 * env
			p_tail = env
			p_glow_boost = 0.5 * env
		"notice":
			p_freeze = true
			p_hop = 0.0
			p_brow = 1.0
			p_eye = 1.25
			p_lean -= 0.1 * env
			p_shrink *= 1.0 - 0.04 * env
		"dizzy":
			p_roll += sin(_t * 7.0) * 0.18 * (1.0 - k * 0.5)
			p_head_pitch += cos(_t * 7.0) * 0.1
			p_eye = 0.55
			p_mouth = 0.4
			p_brow = -0.3
		"gather":
			var dip := absf(sin(k * PI * 2.0))
			p_lean += 0.45 * dip
			p_arm_l = 0.7 * dip
			p_arm_r = 0.7 * dip
			p_mouth = 0.3 * dip
		"headbutt", "stone_bump":
			if k < 0.35:
				p_lean -= 0.35 * (k / 0.35)
				p_squash *= 1.0 - 0.08 * (k / 0.35)
			elif k < 0.5:
				p_lean += lerpf(-0.35, 0.7, (k - 0.35) / 0.15)
			else:
				p_lean += 0.7 * (1.0 - (k - 0.5) / 0.5)
			p_brow = -1.0
			if a == "stone_bump" and k > 0.35 and k < 0.6:
				p_hop += 0.08 * sin((k - 0.35) / 0.25 * PI)     # a little leap into the bump
		"spore_puff":
			# Crouch and gather (wind-up), then a round "puff!" at the impact frame.
			if k < 0.42:
				var w := k / 0.42
				p_squash *= 1.0 - 0.16 * w
				p_lean -= 0.12 * w
				p_mouth = 0.2 * w
			else:
				var r := (k - 0.42) / 0.58
				p_squash *= 1.0 + 0.2 * (1.0 - r) * sin(r * PI * 0.5 + PI * 0.5)
				p_hop += 0.1 * (1.0 - r)
				p_mouth = 0.9 * (1.0 - r)
				p_lean += 0.18 * (1.0 - r)
			p_brow = -0.3
		"light_bolt":
			# Rear back while the glow gathers, then flick forward as the bolt leaves.
			if k < 0.4:
				p_lean -= 0.25 * (k / 0.4)
				p_glow_boost = 0.8 * (k / 0.4)
			else:
				var r2 := (k - 0.4) / 0.6
				p_lean += 0.3 * (1.0 - r2)
				p_glow_boost = 1.2 * (1.0 - r2)
			p_brow = -0.4
			p_tail = env
		"cast":
			p_hop += 0.14 * env
			p_squash *= 1.0 + 0.1 * env
			p_arm_l = 1.1 * env
			p_arm_r = 1.1 * env
			p_eye_happy = 0.5 * env
			p_glow_boost = env
			p_mouth = 0.6 * env
		"brave_step":
			# A deep breath, a determined look, one small step forward.
			p_brow = -0.8
			p_eye = 1.1
			if k < 0.5:
				p_squash *= 1.0 + 0.08 * sin(k / 0.5 * PI)
				p_lean -= 0.06 * sin(k / 0.5 * PI)
			else:
				var s2 := (k - 0.5) / 0.5
				p_step = 1.0
				p_step_lift = 2.0 * sin(s2 * PI)
				p_hop += 0.06 * sin(s2 * PI)
				p_lean += 0.12 * sin(s2 * PI)
			p_mouth = 0.3 * env
		"mochi_twirl", "lumi_glow_spin":
			p_spin += ease(k, -1.8) * TAU
			p_hop += absf(sin(k * PI * 3.0)) * 0.16
			p_eye_happy = env
			p_mouth = 0.8 * env
			p_tail = env
			p_arm_l = 0.8 * env
			p_arm_r = 0.8 * env
			if a == "lumi_glow_spin":
				p_glow_boost = env
		"pebble_hug":
			p_arm_l = 1.3 * env
			p_arm_r = 1.3 * env
			p_lean += 0.2 * env
			p_squash *= 1.0 - 0.06 * env
			p_eye_happy = env
			p_roll += sin(k * PI * 4.0) * 0.06 * env
		"pat":
			p_lean += 0.35 * env
			p_hop += absf(sin(k * PI * 6.0)) * 0.04
			p_arm_l = 0.8 * env
			p_arm_r = 0.8 * env
			p_eye_happy = 0.6 * env
		"eat":
			p_head_pitch += absf(sin(k * PI * 8.0)) * 0.22 * env
			p_mouth = absf(sin(k * PI * 8.0)) * env
			p_eye_happy = 0.8 * env
			p_squash *= 1.0 + 0.05 * sin(k * PI * 8.0)
		"refuse":
			p_shake = sin(k * PI * 6.0) * 0.5 * env
			p_tremble = 0.01
			p_shrink *= 1.0 - 0.1 * env
			p_brow = 1.0
			p_lean -= 0.12 * env
		"present":
			p_hop += absf(sin(k * PI * 2.0)) * 0.15
			p_arm_l = 0.9 * env
			p_arm_r = 0.9 * env
			p_brow = 0.8 * env
			p_mouth = 0.5 * env
			p_eye_happy = 0.5 * env
		"glow_pulse":
			p_glow_boost = env
			p_hop += 0.06 * env
		"salute":
			p_arm_r = 1.4 * env
			p_brow = -0.6
			p_squash *= 1.0 + 0.06 * env
			p_lean -= 0.1 * env
		"wave":
			p_arm_r = 1.0 * env
			p_roll += sin(k * PI * 4.0) * 0.08 * env
			p_eye_happy = 0.5 * env
		"polish":
			p_arm_r = 0.5 + sin(k * PI * 8.0) * 0.4
			p_eye_happy = 0.8 * env
			p_roll += sin(k * PI * 4.0) * 0.05
		"stretch":
			p_squash *= 1.0 + 0.18 * env
			p_mouth = env
			p_eye = 1.0 - env
			p_arm_l = env
			p_arm_r = env
		"tumble":
			p_lean += (1.0 - ease(k, 0.4)) * 1.6
			p_hop += absf(sin(k * PI * 2.0)) * 0.18
		"sniff":
			p_lean += 0.2 * env
			p_head_pitch += sin(k * PI * 10.0) * 0.06 * env
			p_eye_happy = 0.4 * env
		"bounce_off":
			p_lean -= 0.6 * env
			p_hop += 0.2 * env
			p_brow = 1.0
			p_eye = 1.2
		"peek":
			# Pops up out of the tall grass, has a curious look around, drops back down.
			p_hop += sin(k * PI) * 0.42
			p_squash *= 1.0 + 0.18 * env - 0.15 * float(k > 0.85)
			p_eye = 1.2
			p_brow = 0.6
			p_head_yaw += sin(k * TAU) * 0.6 * env
		"stomp":
			p_hop += 0.12 * env
			p_squash *= 1.0 - 0.12 * (1.0 - env) * float(k > 0.5)
			p_brow = -1.0


func _update_look(delta: float) -> void:
	var want_yaw := 0.0
	var want_pitch := 0.0
	if look_target is Vector3 and is_inside_tree():
		var local: Vector3 = to_local(look_target)
		var flat := Vector2(local.x, local.z)
		if flat.length() > 0.05:
			want_yaw = clampf(atan2(local.x, local.z), -1.15, 1.15)
			want_pitch = clampf(atan2(local.y - head_height, flat.length()), -0.45, 0.45)
	else:
		_glance_timer -= delta
		if _glance_timer <= 0.0:
			_glance_timer = _rng.randf_range(1.8, 4.5)
			_glance_yaw = _rng.randf_range(-0.6, 0.6) if _rng.randf() < 0.6 else 0.0
		if move_speed < 0.3 and mood == "idle":
			want_yaw = _glance_yaw
	var rate := 1.0 - exp(-7.0 * delta)
	_look_yaw = lerpf(_look_yaw, want_yaw, rate)
	_look_pitch = lerpf(_look_pitch, want_pitch, rate)
	p_head_yaw += _look_yaw
	p_head_pitch += _look_pitch


func _update_blink(delta: float) -> void:
	if _blink_t >= 0.0:
		_blink_t += delta
		var b := 1.0 - sin(clampf(_blink_t / 0.13, 0.0, 1.0) * PI)
		p_eye *= b
		if _blink_t >= 0.13:
			_blink_t = -1.0
			if _double_blink:
				_double_blink = false
				_blink_timer = 0.12
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_t = 0.0
			_double_blink = _rng.randf() < 0.2
			_blink_timer = _rng.randf_range(2.2, 5.0)


func _update_emote(delta: float) -> void:
	if _emote == null or not _emote.visible:
		return
	_emote_t += delta
	var pop := clampf(_emote_t / 0.28, 0.0, 1.0)
	var s := _elastic(pop)
	var fade := clampf((_emote_len - _emote_t) / 0.3, 0.0, 1.0)
	_emote.scale = Vector3.ONE * maxf(s * lerpf(0.6, 1.0, fade), 0.01)
	_emote.modulate.a = fade
	_emote.position = Vector3(0, sin(_emote_t * 3.0) * 0.025 + p_hop * 0.6, 0)
	if _emote_t >= _emote_len:
		hide_emote()


static func _elastic(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (TAU / 3.0)) + 1.0


## Applies the common rig transform (squash at the feet, hop, tremble, lean/roll/spin).
func _apply_common(delta: float) -> void:
	var r := 1.0 - exp(-10.0 * delta)
	_sm_shrink = lerpf(_sm_shrink, p_shrink, r)
	_sm_lean = lerpf(_sm_lean, p_lean, 1.0 - exp(-14.0 * delta))
	_sm_roll = lerpf(_sm_roll, p_roll, 1.0 - exp(-14.0 * delta))
	var sq := clampf(p_squash, 0.5, 1.6)
	var xz := 1.0 / sqrt(sq)
	rig.scale = Vector3(xz, sq, xz) * _sm_shrink
	var tr := Vector3(sin(_t * 53.0), 0.0, cos(_t * 41.0)) * p_tremble
	rig.position = Vector3(0.0, p_hop, 0.0) + tr
	body.rotation = Vector3(_sm_lean + p_head_pitch * head_body_factor * -1.0,
		p_spin + p_shake + p_head_yaw * head_body_factor, _sm_roll)
	for e in eye_nodes:
		var en: Node3D = e
		var open := clampf(p_eye, 0.04, 1.3)
		var sy := open * (1.0 - 0.8 * p_eye_happy)
		en.scale = Vector3(1.0 + (open - 1.0) * 0.3, sy, 1.0)
		# Closed / smiling eyes become a soft dark line: hide the shiny highlights.
		var shiny := sy > 0.42
		for k in range(1, en.get_child_count()):
			var hl := en.get_child(k) as Node3D
			if hl != null and hl.visible != shiny:
				hl.visible = shiny


# --- Subclass hooks --------------------------------------------------------------------------------

func _build() -> void:
	var s := Kit.sphere(0.25, Mat.outlined(Mat.toon(Palette.CLOTH_CREAM), outline_width, OUTLINE_COLOR))
	Kit.add(body, s, Vector3(0, 0.25, 0))


func _apply_pose(delta: float) -> void:
	_apply_common(delta)


func _on_action_started(_a: String) -> void:
	pass


func _on_action_fire(a: String) -> void:
	var parent := _fx_parent()
	match a:
		"happy":
			Fx.hearts(parent, head_world_position(), 3)
		"celebrate":
			Fx.sparkles(parent, global_position + Vector3.UP * 0.4, 0.45, 16)
		"present":
			Fx.sparkles(parent, global_position + Vector3.UP * 0.35 + global_basis.z * 0.25, 0.2, 8)
		"spore_puff":
			Fx.poof(parent, global_position + Vector3.UP * 0.45 + global_basis.z * 0.25, Color(1.0, 0.86, 0.9), 8, 0.55)
		"cast":
			Fx.sparkles(parent, global_position + Vector3.UP * 0.45, 0.4, 10)
		"mochi_twirl", "pebble_hug", "lumi_glow_spin":
			Fx.hearts(parent, head_world_position(), 3)


func _on_mood_changed(_was: String, _now: String) -> void:
	pass


func _preview_extra(a: String) -> void:
	match a:
		"happy":
			show_emote("heart", 2.0)
		"celebrate":
			show_emote("sparkle", 2.0)
		"notice":
			show_emote("exclaim", 2.0)
		"refuse":
			show_emote("drop", 2.0)


func _fx_parent() -> Node:
	var p := get_parent()
	while p != null and p.get_parent() != null and not (p.get_parent() is Window):
		p = p.get_parent()
	return p if p != null else self


# --- Helpers for subclasses ---------------------------------------------------------------------------

## Outlined toon material in the creature style.
func omat(c: Color, opts: Dictionary = {}) -> Material:
	return Mat.outlined(Mat.toon(c, opts), outline_width, OUTLINE_COLOR)


## Builds a big shiny eye: a pivot (scaled for blinks) holding the eyeball and two highlights.
func make_eye(parent: Node3D, pos: Vector3, radius: float, yaw_deg: float, color: Color = EYE_DARK) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = pos
	pivot.rotation_degrees = Vector3(0, yaw_deg, 0)
	var ball := Kit.sphere(radius, Mat.toon(color, {"rim": 0.15, "specular": 0.6, "noise": 0.0}), 12, 16)
	Kit.add(pivot, ball, Vector3.ZERO, Vector3.ZERO, Vector3(0.82, 1.0, 0.5))
	var hl := Kit.sphere(radius * 0.34, Mat.glow(Color(1, 1, 1), 1.1), 8, 10)
	Kit.add(pivot, hl, Vector3(-radius * 0.3, radius * 0.38, radius * 0.42))
	var hl2 := Kit.sphere(radius * 0.16, Mat.glow(Color(1, 1, 1), 1.0), 6, 8)
	Kit.add(pivot, hl2, Vector3(radius * 0.28, -radius * 0.3, radius * 0.44))
	eye_nodes.append(pivot)
	return pivot


func make_cheek(parent: Node3D, pos: Vector3, radius: float, yaw_deg: float, color: Color = CHEEK) -> MeshInstance3D:
	var c := Kit.sphere(radius, Mat.toon(color, {"rim": 0.1, "noise": 0.0}), 8, 12)
	Kit.add(parent, c, pos, Vector3(0, yaw_deg, 0), Vector3(1.0, 0.62, 0.35))
	return c
