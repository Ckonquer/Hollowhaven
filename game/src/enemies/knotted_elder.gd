extends "res://src/enemies/enemy_base.gd"
## Knotted Elder (optional elite, the Bramblewatch pocket on the Thornthicket outskirts): a huge thorn-root
## guardian. Three attacks, each with its OWN tell (pose + tint colour + ground mark), data/enemies.gd:
##   root_sweep (close)  telegraph 1.3 s: one root arm rises and curls out to the side, the body winds up
##                       (amber tint) and a wide amber WEDGE (data arc_deg 150) is drawn -> a low sweep (one
##                       hit) -> recover 1.8 s. Step back out of the wedge or roll through.
##   charge (mid range)  telegraph 1.5 s: it plants its feet, leans in and its crown of thorns GLOWS (red
##                       tint), a red LANE is drawn -> a committed straight charge (one hit) -> recover 2.2 s
##                       with its back open. A wall or one of its own roots in the lane stops it with a bonk
##                       and a longer stun (and breaks that root): bait it into them.
##   roots               telegraph 1.6 s: both arms plunge into the ground (green tint) and green SPOTS mark
##                       where roots will rise around Krystal -> up to 4 temporary thorn roots rise in a broken
##                       ring (the side facing the Elder and one side always stay open, and adjacent roots
##                       leave walkable gaps), never on top of her or a companion; each lasts data duration
##                       (6 s) and can be cut ("Cut the root", E or a swing). At most MAX_ROOTS alive, a new
##                       ring only once the old one is gone. Nothing else is ever spawned.
## Elite rules: ordinary hits never stagger it; enough damage in a short time (POISE) breaks its poise for a
## short stun (which also cancels a wind-up). Comfort: elites count as boss mechanics for Settings
## "timing_assist" (like the Matron and the Quarry Warden): every wind-up and every recovery (the punish
## opening, also after a bonk) lasts TIMING_ASSIST_MULT longer. Its health bar shows while it is engaged
## (Events.boss_health_changed "knotted_elder", -1 hides it). On defeat it grants the content reward
## "rw_c1x_elder" once (resin + flag c1x_elder_defeated; setup key "reward_id", "" = none).
## Stats: data/enemies.gd "knotted_elder". Sounds (existing names only): dir_root_creak (sweep tell / alert),
## brambling_telegraph (charge tell), dig (roots tell / rise), tree_fall (bonk / defeat), chop (root cut),
## brambling_chatter (idle), enemy_hurt.

const Visual := preload("res://src/enemies/knotted_elder_visual.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const SWEEP_TIME := 0.55
const SWEEP_HIT_AT := 0.22
const SWEEP_REACH_BONUS := 0.5       # the sweep reaches data attack_range + this (+ her body)
const CHARGE_SPEED := 8.0
const CHARGE_START_FRACTION := 0.8
const LANE_WIDTH := 2.0
const HIT_AHEAD := 0.8
const BONK_EXTRA := 1.5
const ROOTING_TIME := 0.35
const ROOT_RING_RADIUS := 3.0        # roots rise on a ring this far around Krystal
const ROOT_SLOTS := 6                # 60 degrees apart: adjacent slot centres are 3 m apart
const ROOT_LENGTH := 1.5             # so neighbouring roots leave 1.5 m walkable gaps
const ROOT_MIN_CLEARANCE := 1.0      # never rises with any part of it within this of Krystal or a companion
const MAX_ROOTS := 6
const ROOTS_COOLDOWN := 12.0
const POISE := 40.0                  # damage within POISE_WINDOW that staggers it
const POISE_WINDOW := 5.0
const POISE_STUN := 1.2
const POISE_IMMUNITY := 8.0
const LANE_REFRESH := 0.1
const TIMING_ASSIST_MULT := 1.5      # Settings timing_assist: wind-ups and recoveries (as the Matron / Warden)
const BAR_ID := "knotted_elder"
const REWARD_ID := "rw_c1x_elder"
const BARK_CHIPS := Color("7a5a40")

var next_attack: String = ""         # tests / scripted fights: "root_sweep" | "charge" | "roots"
var attack_kind: String = ""
var reward_id: String = REWARD_ID
var arena_center := Vector3.ZERO
var arena_radius: float = 12.0
var roots: Array = []                # live ElderRoot nodes
var planned_roots: Array = []        # spots marked during the roots wind-up
var bar_shown := false
var _arena_set := false
var _radius_set := false
var _def: Dictionary = {}
var _intent_far := false
var _roots_cd: float = 0.0
var _poise_dmg: float = 0.0
var _poise_t: float = 0.0
var _poise_immune: float = 0.0
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _resolved := false
var _history: Array = []


## One temporary thorn root: blocks movement (structure layer) and is cuttable (a "hand" harvestable and an
## interactable, so the prompt reads "Cut the root"). Expires after `lifetime` seconds.
class ElderRoot extends Node3D:
	signal cut
	signal expired

	const RISE := 0.25
	const SINK := 0.3
	const RootMat := preload("res://src/art/mat.gd")
	const RootKit := preload("res://src/art/mesh_kit.gd")
	const RootFx := preload("res://src/combat/hit_fx.gd")
	const BARK := Color("5e3b28")
	const THORN := Color("e3c08a")

	var lifetime: float = 6.0
	var length: float = 1.5
	var height: float = 1.1
	var age: float = 0.0
	var is_cut := false
	var gone := false
	var _body: StaticBody3D
	var _visual: Node3D
	var _sink_t: float = -1.0

	func _ready() -> void:
		add_to_group("harvestable")
		add_to_group("interactable")
		add_to_group("elder_root")
		_body = StaticBody3D.new()
		_body.name = "RootBody"
		_body.collision_layer = 32 | 16          # blocks like a structure, found by the interaction probe
		_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, height, 0.55)
		cs.shape = box
		cs.position.y = height * 0.5
		_body.add_child(cs)
		add_child(_body)
		_visual = Node3D.new()
		add_child(_visual)
		var bark := RootMat.outlined(RootMat.toon(BARK, {"rim": 0.35, "noise": 0.2}), 0.012)
		var thorn := RootMat.outlined(RootMat.toon(THORN, {"rim": 0.3}), 0.008)
		for i in 3:
			var x := (float(i) - 1.0) * length * 0.32
			var cap := RootKit.capsule(0.13 - 0.02 * float(i % 2), height * 1.05, bark)
			RootKit.add(_visual, cap, Vector3(x, height * 0.45, 0.0), Vector3(0.0, 0.0, (float(i) - 1.0) * -14.0))
			RootKit.add(_visual, RootKit.cone(0.04, 0.16, thorn, 6), Vector3(x + 0.08, height * 0.6, -0.1), Vector3(-70, 0, -30))
		RootKit.add(_visual, RootKit.capsule(0.09, length * 0.95, bark), Vector3(0, 0.12, 0), Vector3(0, 0, 90))
		_visual.scale = Vector3(1.0, 0.05, 1.0)

	func _process(delta: float) -> void:
		advance(delta)

	## Ages the root (tests call it directly). Rises, lives `lifetime` s, then sinks away.
	func advance(delta: float) -> void:
		if gone:
			return
		age += delta
		if _sink_t >= 0.0:
			_sink_t += delta
			_visual.scale.y = maxf(1.0 - _sink_t / SINK, 0.02)
			if _sink_t >= SINK:
				gone = true
				queue_free()
			return
		_visual.scale.y = clampf(age / RISE, 0.05, 1.0)
		if age >= lifetime:
			_begin_sink()
			expired.emit()

	func is_active() -> bool:
		return not is_cut and not gone and _sink_t < 0.0

	func get_harvest_info() -> Dictionary:
		# kind "root": not a forageable (Mochi only forages bushes / grass), never a resource.
		return {"tool": "hand", "name": "Thorn Root", "kind": "root"} if is_active() else {}

	func harvest_hit(_player: Node, _tool_id: String) -> void:
		cut_root()

	func get_interaction(_player: Node) -> Dictionary:
		return {"text": "Cut the root", "enabled": true} if is_active() else {}

	func interact(_player: Node) -> void:
		cut_root()

	func cut_root() -> void:
		if not is_active():
			return
		is_cut = true
		Audio.play_3d("chop", global_position + Vector3.UP * 0.5, -2.0, 0.1)
		RootFx.chips(global_position + Vector3.UP * 0.5, Color("7a5a40"), 8, 2.6, 0.6)
		cut.emit()
		_begin_sink()

	func _begin_sink() -> void:
		if _sink_t >= 0.0:
			return
		_sink_t = 0.0
		remove_from_group("harvestable")
		remove_from_group("interactable")
		if _body != null:
			_body.collision_layer = 0


func _init() -> void:
	hit_color = Color(0.74, 0.62, 0.44)
	committed_states = ["sweep", "charge", "rooting"]
	needs_clear_shot = true


func setup(params: Dictionary) -> void:
	super.setup(params)
	reward_id = String(params.get("reward_id", reward_id))
	var c: Variant = params.get("arena_center")
	if c is Vector3:
		arena_center = c
		_arena_set = true
	if params.has("arena_radius"):
		arena_radius = maxf(float(params["arena_radius"]), 4.0)
		_radius_set = true


func _ready() -> void:
	super._ready()
	if not _arena_set:
		arena_center = home
	if not _radius_set:
		arena_radius = float(data.get("arena_radius", arena_radius))
	health.changed.connect(_on_health_changed)


func _exit_tree() -> void:
	super._exit_tree()
	clear_roots()
	_hide_bar()


func _default_id() -> String:
	return "knotted_elder"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.75


func _body_height() -> float:
	return 2.5


func _knockback_scale() -> float:
	return 0.15


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.3


func sweep_reach() -> float:
	return float(data.get("attack_range", 3.2)) + SWEEP_REACH_BONUS


func charge_distance() -> float:
	return float(attack_def("charge").get("distance", 9.0))


func attack_reach() -> float:
	var close := float(data.get("attack_range", 3.2))
	if next_attack == "charge" or next_attack == "roots" or (next_attack == "" and _intent_far):
		return maxf(close, charge_distance() * CHARGE_START_FRACTION)
	return close


## Length of the current / last charge lane (after clipping against walls and roots).
func lane_length() -> float:
	return _lane_len


func live_roots() -> int:
	for i in range(roots.size() - 1, -1, -1):
		var r: Variant = roots[i]
		if not is_instance_valid(r) or not bool((r as Node).call("is_active")):
			roots.remove_at(i)
	return roots.size()


func clear_roots() -> void:
	for r in roots:
		if is_instance_valid(r):
			(r as Node).queue_free()
	roots.clear()
	planned_roots.clear()


func _can_start_attack() -> bool:
	return _shot_clear


func _choose_attack() -> void:
	var kind := next_attack
	if kind == "":
		var dist := _flat_dist_to_player()
		var roots_ok := _roots_cd <= 0.0 and live_roots() == 0
		if dist <= float(data.get("attack_range", 3.2)):
			kind = "roots" if roots_ok and _rng.randf() < 0.25 else "root_sweep"
		else:
			kind = "roots" if roots_ok and _rng.randf() < 0.4 else "charge"
		# never the same attack three times in a row
		if _history.size() >= 2 and String(_history[-1]) == kind and String(_history[-2]) == kind:
			kind = "charge" if kind != "charge" else ("roots" if roots_ok else "root_sweep")
	next_attack = ""
	attack_kind = kind
	_def = attack_def(kind)
	_history.append(kind)
	if _history.size() > 3:
		_history.pop_front()
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack(kind)


func telegraph_duration() -> float:
	return attack_telegraph(_def) * assist_mult()


func recover_duration() -> float:
	return attack_recover(_def) * assist_mult()


## Settings "timing_assist" ("removes tight timing windows from ... boss mechanics"; elites count): x1.5.
func assist_mult() -> float:
	return TIMING_ASSIST_MULT if bool(Settings.get_value("timing_assist")) else 1.0


func _on_telegraph_start() -> void:
	_lane_clip_t = 0.0
	match attack_kind:
		"root_sweep":
			Audio.play_3d("dir_root_creak", global_position + Vector3.UP * 1.2, 0.0, 0.08)
			announce_tell(_def, "[roots creak and rise]")
		"charge":
			Audio.play_3d("brambling_telegraph", global_position + Vector3.UP * 1.5, 1.0, 0.05)
			announce_tell(_def, "[a deep growl; thorns crackle]")
		"roots":
			Audio.play_3d("dig", global_position + Vector3.UP * 0.3, 0.0, 0.08)
			announce_tell(_def, "[the ground rumbles]")
			_plan_roots()
	_update_mark(true)


## Root spots: ROOT_SLOTS evenly around Krystal; the slot facing the Elder and one side slot always stay open,
## roots rise in the others (4), each ROOT_LENGTH long along the ring. Spots too close to Krystal / a
## companion or outside the arena are skipped.
func _plan_roots() -> void:
	planned_roots.clear()
	var t := current_target()
	if t == null:
		return
	var c := t.global_position
	var to_elder := global_position - c
	to_elder.y = 0.0
	var base := atan2(to_elder.x, to_elder.z) if to_elder.length_squared() > 0.01 else 0.0
	var open_side := 1 if _rng.randf() < 0.5 else 5
	for i in ROOT_SLOTS:
		if i == 0 or i == open_side:
			continue
		var a := base + TAU * float(i) / float(ROOT_SLOTS)
		var p := c + Vector3(sin(a), 0.0, cos(a)) * ROOT_RING_RADIUS
		if arena_center.distance_to(Vector3(p.x, arena_center.y, p.z)) > arena_radius + 2.0:
			continue
		planned_roots.append({"pos": p, "yaw": a})


## The two ends of a root of `length` centred at `p` with yaw `yaw` (it lies along its local X axis).
static func root_ends(p: Vector3, yaw: float, length: float) -> Array:
	var ax := Vector3(cos(yaw), 0.0, -sin(yaw)) * (length * 0.5)
	return [p - ax, p + ax]


static func root_slot_angles(planned: Array) -> Array:
	var out: Array = []
	for r in planned:
		out.append(float((r as Dictionary)["yaw"]))
	return out


func _tick_extra(delta: float) -> void:
	_roots_cd = maxf(_roots_cd - delta, 0.0)
	_poise_immune = maxf(_poise_immune - delta, 0.0)
	if _poise_t > 0.0:
		_poise_t -= delta
		if _poise_t <= 0.0:
			_poise_dmg = 0.0
	if state == "telegraph":
		_lane_clip_t -= delta
		_update_mark(_lane_clip_t <= 0.0 and state_time <= _state_len * TELEGRAPH_TRACK)


func _update_mark(reclip: bool) -> void:
	var fwd := _forward()
	var locked := state_time > _state_len * TELEGRAPH_TRACK
	var m := mark()
	match attack_kind:
		"root_sweep":
			if not m.is_showing():
				m.show_arc(global_position, fwd, sweep_reach(), float(_def.get("arc_deg", 150.0)), TelegraphFx.WARN)
			elif not locked:
				m.move_arc(global_position, fwd)
		"charge":
			if reclip:
				_lane_clip_t = LANE_REFRESH
				_lane_len = float(lane_clip(global_position, fwd, charge_distance())["length"])
			if not m.is_showing():
				m.show_lane(global_position, global_position + fwd * _lane_len, LANE_WIDTH, TelegraphFx.DANGER)
			elif not locked:
				m.move_lane(global_position, global_position + fwd * _lane_len)
		"roots":
			if not m.is_showing():
				var pts: Array = []
				for r in planned_roots:
					pts.append((r as Dictionary)["pos"])
				m.show_spots(pts, ROOT_LENGTH * 0.5, TelegraphFx.ROOT)
			locked = true
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_resolved = false
	match attack_kind:
		"charge":
			_enter("charge", 0.0)
			_lane_len = charge_begin(_attack_dir, charge_distance(), CHARGE_SPEED)
			var m := mark()
			m.show_lane(global_position, charge_lane_end(), LANE_WIDTH, TelegraphFx.DANGER)
			m.set_progress(1.0, true)
		"roots":
			_enter("rooting", ROOTING_TIME)
			_raise_roots()
		_:
			_enter("sweep", SWEEP_TIME)
			mark().set_progress(1.0, true)


func _raise_roots() -> void:
	live_roots()
	var t := current_target()
	var parent := get_parent()
	if parent == null:
		return
	# [position, clearance]: Krystal, companions and the Elder itself. The clearance is measured to the root's
	# whole length (its axis segment), not only its centre, so a root never rises into anyone's body.
	var avoid: Array = []
	if t != null:
		avoid.append([t.global_position, ROOT_MIN_CLEARANCE])
	for id in Game.companion_nodes:
		var cn: Variant = Game.companion_nodes[id]
		if cn is Node3D and is_instance_valid(cn):
			avoid.append([(cn as Node3D).global_position, ROOT_MIN_CLEARANCE])
	avoid.append([global_position, _body_radius() + 0.6])
	var life := float(_def.get("duration", 6.0))
	for r in planned_roots:
		if roots.size() >= MAX_ROOTS:
			break
		var p: Vector3 = (r as Dictionary)["pos"]
		var ends := root_ends(p, float((r as Dictionary)["yaw"]), ROOT_LENGTH)
		var clear := true
		for q in avoid:
			if TelegraphFx.segment_distance(ends[0], ends[1], q[0]) < float(q[1]):
				clear = false
				break
		if not clear:
			continue
		var root := ElderRoot.new()
		root.name = "ElderRoot"
		root.lifetime = life
		root.length = ROOT_LENGTH
		parent.add_child(root)
		root.global_position = p
		root.rotation.y = float((r as Dictionary)["yaw"])        # lies along the ring (tangential)
		roots.append(root)
	planned_roots.clear()
	_roots_cd = ROOTS_COOLDOWN
	_intent_far = true
	Audio.play_3d("dig", global_position + Vector3.UP * 0.3, 1.0, 0.1)
	Events.camera_shake.emit(0.1, 0.25)


func _st_custom(state_name: String, delta: float) -> void:
	match state_name:
		"sweep":
			if not _resolved and state_time >= SWEEP_HIT_AT:
				_resolved = true
				var hits: Array = Combat.melee(self, global_position + Vector3.UP * 0.6, _attack_dir, sweep_reach(),
					float(_def.get("arc_deg", 150.0)), attack_damage_for(_def), ["player"], float(data.get("knockback", 7.5)))
				_on_attack_resolved(hits)
			if state_time >= SWEEP_TIME:
				_enter("recover", recover_duration())
		"charge":
			var r := charge_step(delta, HIT_AHEAD, LANE_WIDTH * 0.5, attack_damage_for(_def), float(data.get("knockback", 7.5)))
			match r:
				"hit", "done":
					_enter("recover", recover_duration())
				"wall":
					_bonk()
				_:
					if state_time > _lane_len / CHARGE_SPEED + 0.6:
						_enter("recover", recover_duration())
		"rooting":
			if state_time >= _state_len:
				_enter("recover", recover_duration())


## Ran into a wall or one of its own roots: breaks the nearest root ahead and is stunned for a long opening.
func _bonk() -> void:
	var ahead := global_position + _charge_dir * (_body_radius() + 0.9)
	for r in roots:
		if is_instance_valid(r) and bool((r as Node).call("is_active")) and (r as Node3D).global_position.distance_to(ahead) < 2.0:
			(r as Node).call("cut_root")
			break
	stun(recover_duration() + BONK_EXTRA)
	_cooldown = float(data.get("cooldown", 2.8))
	Audio.play_3d("tree_fall", global_position + Vector3.UP, -2.0, 0.1)
	HitFx.chips(ahead + Vector3.UP * 0.8, BARK_CHIPS, 12, 3.4, 0.7)
	Events.camera_shake.emit(0.2, 0.3)


## Elite: never flinches from ordinary hits; a poise break (POISE damage within POISE_WINDOW) staggers it.
func can_stagger(_amount: float, _source: Node) -> bool:
	return _poise_immune <= 0.0 and _poise_dmg >= POISE


func _stagger(_amount: float, _source: Node) -> void:
	_poise_dmg = 0.0
	_poise_t = 0.0
	_poise_immune = POISE_IMMUNITY
	stun(POISE_STUN)
	Audio.play_3d("tree_fall", global_position + Vector3.UP, -6.0, 0.15)


func poise_damage() -> float:
	return _poise_dmg


func _on_hurt(amount: float) -> void:
	_poise_dmg += amount
	_poise_t = POISE_WINDOW
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 1.4, -3.0, 0.1)
	HitFx.chips(get_aim_point(), BARK_CHIPS, 7, 3.0, 0.55)


func _on_alert() -> void:
	Audio.play_3d("dir_root_creak", global_position + Vector3.UP * 1.5, -2.0, 0.08)


func _idle_sound() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 1.5, -12.0, 0.05)


func _defeat_sound() -> String:
	return "tree_fall"


func _on_state_changed(prev: String, new_state: String) -> void:
	if new_state == "recover" and prev != "rooting":
		_intent_far = _rng.randf() < 0.5
	if new_state == "chase" and not bar_shown:
		_show_bar()
	elif new_state in ["return", "idle", "wander", "dead"]:
		_hide_bar()
		if new_state != "idle" and new_state != "wander":
			clear_roots()
	if new_state == "dead":
		_grant_reward()


func _on_player_died() -> void:
	super._on_player_died()
	clear_roots()


func _show_bar() -> void:
	bar_shown = true
	if health != null:
		Events.boss_health_changed.emit(BAR_ID, float(health.hp), float(health.max_hp))


func _hide_bar() -> void:
	if not bar_shown:
		return
	bar_shown = false
	Events.boss_health_changed.emit(BAR_ID, -1.0, float(health.max_hp) if health != null else 1.0)


func _on_health_changed(hp: float, max_hp: float) -> void:
	if bar_shown and hp > 0.0:
		Events.boss_health_changed.emit(BAR_ID, hp, max_hp)


func _grant_reward() -> void:
	if reward_id == "":
		return
	var b: Dictionary = ItemDB.reward_bundle(reward_id)
	# Rewards rule (docs/ch2/WAVE_A_REPORT.md): a content module grants only "content" bundles; step / goal
	# rewards (rw_<step>, rw_<goal>) are paid by the quest layer / optional log.
	if b.is_empty() or String(b.get("by", "")) != "content":
		if not b.is_empty():
			push_warning("KnottedElder: %s is not a content reward bundle; not granted" % reward_id)
		return
	var items: Variant = b.get("items", {})
	var flags: Variant = b.get("flags", [])
	GameState.grant_once(reward_id, items if items is Dictionary else {}, flags if flags is Array else [],
		"The Knotted Elder settles back into the earth.")


## Sinks slowly into the ground in a shower of bark and leaves (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(visual, "position:y", -1.2, 1.1).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "rotation:z", 0.25, 1.1)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.2)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.6
	HitFx.chips(pos, BARK_CHIPS, 16, 3.6, 0.9)
	HitFx.chips(pos, Palette.FOLIAGE, 10, 3.0, 0.9)
