extends Node3D
## The Weaver Matron (arachnophobia: the Hollow Mother) - boss of the Heartseed Chamber.
##   setup({"arena_center": Vector3, "anchors": [ceiling Vector3...], "braziers": [boss_brazier nodes],
##          "arena_radius": 11.5 (optional: floor radius; the fight starts 3 m outside it, drops stay inside),
##          "crack": Vector3 (optional: the deep ceiling crack it flees into on defeat; default above the centre)})
## Loop: clings to a ceiling anchor -> maybe repositions to another anchor -> telegraphed DROP
## (a dark circle on the floor under the target spot + rattle, 1.2 s) -> slam.
##   * Slam hits Krystal: it rebounds and climbs back up (no opening).
##   * Slam misses: it is stuck for 2.5 s - the opening.
##   * Any brazier lit: it shrieks, is scorched off the ceiling, falls and is stunned for 5 s (the
##     big opening, takes x1.5 damage); the anchor nearest that brazier burns away for good.
## It can only be hurt while stuck/stunned; otherwise hits glance off with a spark and a hint.
## One stun window can take at most 40% of its health (then it scrambles back up), so the fight
## always has a few beats. HP 0 at any time -> defeat: it shrieks and retreats up into the deep
## crack above the arena (no death, no gore), flag "weaver_defeated", Events.boss_defeated and the
## Heartseed pickup appears at the arena centre (re-created on load if still needed, never twice).
## Gentle intensity: slower, lower damage (x0.6 via INTENSITY), longer stuns.
## Player death: the fight resets cleanly (boss back on the ceiling, dormant, bar hidden). By design
## lit braziers stay lit and burned anchors stay burned, and its wounds do not heal - a kinder
## retry. Reloading the area starts a fresh fight unless it was already defeated.

signal defeated
signal state_changed(new_state: String)
signal anchor_burned(anchor: Vector3)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Health := preload("res://src/combat/health.gd")
const WeaverVisual := preload("res://src/enemies/weaver_visual.gd")
const ShadeVisual := preload("res://src/enemies/shade_visual.gd")
const HeartseedPickup := preload("res://src/enemies/heartseed_pickup.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const BOSS_ID := "weaver_matron"
const ENGAGE_MARGIN := 3.0        # starts the fight this far outside the arena edge (entering)
const LEAVE_MARGIN := 9.0         # ...and stands down after she has been this far out for LEAVE_TIME
const LEAVE_TIME := 4.0
const SLAM_RADIUS := 2.4
const BRAZIER_CLEARANCE := 2.6    # a scorched fall never lands on (or right beside) a brazier
const CENTRE_CLEARANCE := 3.0     # ...nor on the arena's centrepiece (the Heartseed cocoon)
const WINDOW_CAP := 0.4
const SCORCHED_DAMAGE_MULT := 1.5
const WEAVER_SCALE := 2.6
const SHADE_SCALE := 2.3
const VULNERABLE_STATES := ["stuck", "scorched"]
const GROUND_STATES := ["rebound", "stuck", "scorched"]
## Timings per horror intensity: [Gentle, Standard, Intense]
const T_CLING := [[3.4, 4.6], [2.3, 3.3], [2.0, 2.9]]
const T_TELEGRAPH := [1.6, 1.2, 1.1]
const T_DROP := [0.6, 0.45, 0.42]
const T_STUCK := [3.5, 2.5, 2.3]
const T_SCORCHED := [7.0, 5.0, 4.6]
const T_CLIMB := [1.6, 1.3, 1.2]
const REPOSITION_SPEED := [3.2, 4.6, 5.2]
const T_REBOUND := 0.8
const T_SCORCH_FALL := 0.6
const T_INTRO := 2.2

var enemy_id: String = BOSS_ID
var data: Dictionary = {}
var health: Node
var visual: Node3D
var hit_radius: float = 1.8
var arena_center := Vector3.ZERO
var arena_radius: float = 11.5          # playable floor radius (drops stay inside it)
var anchors: Array = []            # remaining ceiling anchors
var initial_anchors: Array = []
var burned: Array = []
var braziers: Array = []
var state: String = "dormant"
var state_time: float = 0.0
var fight_started := false
var target_override: Node3D = null   # tests
var intensity_override: int = -1     # tests
var fast_defeat := false             # tests: skip the retreat animation
var crack_point := Vector3.ZERO      # where it retreats on defeat (setup "crack"; default: above the centre)
var _crack_set := false

var _state_len: float = 0.0
var _anchor := Vector3.ZERO          # current (or target) ceiling point
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _drop_target := Vector3.ZERO
var _pending_scorch := false
var _just_repositioned := false
var _window_damage: float = 0.0
var _ceiling_y: float = 8.0
var _floor_y: float = 0.0
var _shadow: Node3D
var _shadow_disc_mat: StandardMaterial3D
var _shadow_ring_mat: StandardMaterial3D
var _check_t: float = 0.0
var _away_t: float = 0.0
var _using_shade := false
var _defeat_started := false
var _gone := false
var _initialized := false
var _rng := RandomNumberGenerator.new()

static var _pending_seed: Node3D = null


func setup(params: Dictionary) -> void:
	var c: Variant = params.get("arena_center")
	if c is Vector3:
		arena_center = c
	arena_radius = maxf(float(params.get("arena_radius", arena_radius)), 3.0)
	var ck: Variant = params.get("crack")
	if ck is Vector3:
		crack_point = ck
		_crack_set = true
	initial_anchors.clear()
	var a: Variant = params.get("anchors", [])
	if a is PackedVector3Array or a is Array:
		for p in a:
			if p is Vector3:
				initial_anchors.append(p)
	for b in braziers:
		_disconnect_brazier(b)
	braziers.clear()
	for b in params.get("braziers", []):
		if b is Node and is_instance_valid(b):
			braziers.append(b)
			if b.has_signal("lit"):
				b.connect("lit", _on_brazier_lit.bind(b))
	if is_inside_tree() and data.size() > 0:
		_initialized = false
		_initialize()


func _ready() -> void:
	data = ItemDB.enemy(BOSS_ID)
	_rng.randomize()
	health = Health.new()
	health.name = "Health"
	health.max_hp = float(data.get("hp", 240.0))
	health.invulnerable = true
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	HitFx.ensure_hitstop()
	_initialize()


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	anchors = initial_anchors.duplicate()
	if anchors.is_empty():
		anchors = [arena_center + Vector3(0, 8, 0)]
	_ceiling_y = 0.0
	for p in anchors:
		_ceiling_y += (p as Vector3).y
	_ceiling_y /= float(anchors.size())
	_floor_y = arena_center.y
	if not _crack_set:
		crack_point = Vector3(arena_center.x, _ceiling_y, arena_center.z)
	if GameState.get_flag("weaver_defeated"):
		_gone = true
		state = "gone"
		visible = false
		if should_spawn_heartseed():
			ensure_heartseed(get_parent() if get_parent() != null else self, arena_center)
		return
	add_to_group("enemy")
	if visual == null or _using_shade != _arachno():
		_build_visual()
	if _shadow == null:
		_build_shadow()
	# Braziers that were already lit (persisted) have already burned their anchors.
	for b in braziers:
		if is_instance_valid(b) and b.has_method("is_lit") and b.is_lit():
			_burn_anchor_near((b as Node3D).global_position, false)
	_anchor = anchors[0]
	global_transform = _ceiling_pose(_anchor, _player_pos())
	_enter("dormant")


# --- Public API ------------------------------------------------------------------------------------

func is_threatening() -> bool:
	return fight_started and not _gone and not _defeat_started


func is_vulnerable() -> bool:
	return state in VULNERABLE_STATES


func intensity() -> int:
	return intensity_override if intensity_override >= 0 else Combat.current_intensity()


func get_aim_point() -> Vector3:
	if state in GROUND_STATES:
		return global_position + Vector3.UP * (1.4 if _using_shade else 0.9)
	return global_position + global_transform.basis.y * 1.2


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func slam_damage() -> float:
	return float(data.get("damage", 20.0)) * Combat.intensity_damage_mult(intensity())


## Hits while it is not stunned glance off its hide.
func on_hit_blocked(_attacker: Node, _dir: Vector3) -> void:
	if _gone or _defeat_started:
		return
	HitFx.spark(get_aim_point())
	Audio.play_3d("hit_soft", get_aim_point(), -2.0, 0.2)
	Events.hint.emit("boss_glance", "Its hide is too tough right now. Light a brazier with {interact}, or dodge its drop so it gets stuck!")


## Pure rule used on load: the Heartseed pickup must exist again if the boss was beaten but the seed
## was never taken home.
static func should_spawn_heartseed() -> bool:
	return bool(GameState.get_flag("weaver_defeated")) and not GameState.has_item("heartseed") and not bool(GameState.get_flag("ward_restored"))


## Returns the existing Heartseed pickup, or creates exactly one at `pos` under `parent`.
static func ensure_heartseed(parent: Node, pos: Vector3) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for n in tree.get_nodes_in_group("heartseed_pickup"):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				return n
	for c in parent.get_children():
		if c.get_script() == HeartseedPickup and not c.is_queued_for_deletion():
			return c
	if _pending_seed != null and is_instance_valid(_pending_seed) and not _pending_seed.is_inside_tree():
		return _pending_seed        # created this frame, added deferred
	var hs: Node3D = HeartseedPickup.new()
	_pending_seed = hs
	hs.name = "Heartseed"
	hs.position = pos
	if parent.is_inside_tree() and parent is Node3D:
		hs.position = (parent as Node3D).global_transform.affine_inverse() * pos
	parent.add_child.call_deferred(hs)
	return hs


# --- State machine -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _gone or _defeat_started:
		return
	state_time += delta
	_check_t -= delta
	var check := _check_t <= 0.0
	if check:
		_check_t = 0.2
	var p := _player()
	match state:
		"dormant":
			if check and p != null and _hunt_allowed(p) and _flat(p.global_position, arena_center) <= arena_radius + ENGAGE_MARGIN:
				start_fight()
		"intro":
			_face_player_on_ceiling(delta)
			if state_time >= T_INTRO:
				_enter_cling(1.0)
		"cling":
			_face_player_on_ceiling(delta)
			# Krystal withdrew from the chamber (e.g. to heal at the checkpoint): stand down quietly.
			if p == null or _flat(p.global_position, arena_center) > arena_radius + LEAVE_MARGIN:
				_away_t += delta
				if _away_t >= LEAVE_TIME:
					reset_fight()
					return
			else:
				_away_t = 0.0
			if state_time >= _state_len and p != null and _hunt_allowed(p) and _flat(p.global_position, arena_center) <= arena_radius + 0.5:
				if anchors.size() > 1 and not _just_repositioned and _rng.randf() < 0.45:
					_begin_reposition()
				else:
					_begin_telegraph()
		"reposition":
			var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			global_transform = _lerp_xform(_from, _to, e)
			if k >= 1.0:
				_just_repositioned = true
				_enter_cling(0.7)
		"telegraph":
			_update_shadow(clampf(state_time / _state_len, 0.0, 1.0))
			if state_time >= _state_len:
				_begin_drop()
		"drop":
			var k := clampf(state_time / _state_len, 0.0, 1.0)
			var e := k * k
			var xf := _lerp_xform(_from, _to, e)
			global_transform = xf
			_update_shadow(1.0)
			if k >= 1.0:
				_slam()
		"rebound":
			if state_time >= _state_len:
				_begin_climb()
		"stuck", "scorched":
			if state_time >= _state_len:
				_begin_climb()
		"scorch_fall":
			var k := clampf(state_time / _state_len, 0.0, 1.0)
			global_transform = _lerp_xform(_from, _to, k * k)
			if k >= 1.0:
				_land_scorched()
		"climb":
			var k := clampf(state_time / _state_len, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			global_transform = _lerp_xform(_from, _to, e)
			if k >= 1.0:
				_enter_cling(-1.0)


func _enter(s: String, length: float = 0.0) -> void:
	state = s
	state_time = 0.0
	_state_len = length
	health.invulnerable = not (s in VULNERABLE_STATES)
	health.damage_taken_mult = SCORCHED_DAMAGE_MULT if s == "scorched" else 1.0
	if s in VULNERABLE_STATES:
		_window_damage = 0.0
	_apply_visual_state(s, length)
	state_changed.emit(s)


## Mirrors the logic state on the (swappable) visual without touching any timers.
func _apply_visual_state(s: String, length: float) -> void:
	if visual != null and visual.has_method("set_state"):
		var vs := "idle"
		match s:
			"reposition", "climb":
				vs = "move"
			"telegraph":
				vs = "telegraph"
			"drop":
				vs = "lunge"
			"stuck", "scorched", "scorch_fall":
				vs = "stunned"
			"intro", "defeat":
				vs = "shriek"
			"rebound":
				vs = "recoil"
		visual.set_state(vs, length)
	if visual != null and visual.has_method("set_clinging"):
		visual.set_clinging(s in ["dormant", "intro", "cling", "reposition", "telegraph"])


func start_fight() -> void:
	if fight_started or _gone:
		return
	fight_started = true
	_emit_health()
	Audio.play_music("music_boss", 2.0)
	Audio.play_3d(_snd("shriek"), global_position, -4.0, 0.03, 60.0)
	Events.caption.emit(_caption("intro"))
	Events.hint.emit("boss_braziers", "Light the braziers with {interact} to burn it off the ceiling. Your Lantern can kindle them.")
	_notice_companions()
	if state == "dormant":
		_enter("intro", T_INTRO)


func _enter_cling(length: float) -> void:
	var r: Array = T_CLING[clampi(intensity(), 0, 2)]
	var l := length if length >= 0.0 else _rng.randf_range(float(r[0]), float(r[1]))
	if length < 0.0:
		_just_repositioned = false
	_enter("cling", l)


func _begin_reposition() -> void:
	var p := _player_pos()
	var best := _anchor
	var best_d := INF
	for a in anchors:
		if (a as Vector3).distance_to(_anchor) < 0.5:
			continue
		var d := _flat(a, p)
		if d < best_d:
			best_d = d
			best = a
	if best.distance_to(_anchor) < 0.5:
		_begin_telegraph()
		return
	_from = global_transform
	_to = _ceiling_pose(best, p)
	var dist := _anchor.distance_to(best)
	_anchor = best
	_enter("reposition", maxf(dist / float(REPOSITION_SPEED[clampi(intensity(), 0, 2)]), 0.6))
	Audio.play_3d(_snd("skitter"), global_position, -3.0, 0.1, 40.0)


func _begin_telegraph() -> void:
	var p := _player_pos()
	var t := Vector3(p.x, _floor_y, p.z)
	var off := Vector2(t.x - arena_center.x, t.z - arena_center.z)
	if off.length() > arena_radius - 1.5:
		off = off.normalized() * maxf(arena_radius - 1.5, 1.0)
		t = Vector3(arena_center.x + off.x, _floor_y, arena_center.z + off.y)
	_drop_target = _ground_at(t)
	_enter("telegraph", float(T_TELEGRAPH[clampi(intensity(), 0, 2)]))
	_show_shadow(true)
	Audio.play_3d(_snd("rattle"), global_position, 0.0, 0.05, 50.0)
	Events.caption.emit(_caption("rattle"))


func _begin_drop() -> void:
	_from = global_transform
	_to = _ground_pose(_drop_target, _player_pos())
	_enter("drop", float(T_DROP[clampi(intensity(), 0, 2)]))


func _slam() -> void:
	global_transform = _to
	_show_shadow(false)
	Audio.play_3d(_snd("drop"), _drop_target, 0.0, 0.05, 50.0)
	Events.camera_shake.emit(0.7, 0.4)
	HitFx.burst(_drop_target + Vector3.UP * 0.2, Color(0.72, 0.68, 0.76), 22, 4.5, 1.6, -9.0, 0.7, 85.0)
	var hit := false
	var p := _player()
	if p != null and _hunt_allowed(p):
		var flat := _flat(p.global_position, _drop_target)
		if flat <= SLAM_RADIUS and absf(p.global_position.y - _drop_target.y) < 2.2:
			var h := Combat.find_health(p)
			if h != null:
				var dir := p.global_position - _drop_target
				dir.y = 0.0
				dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.BACK
				var dealt: float = float(h.apply_damage(slam_damage(), self, dir))
				if dealt > 0.0:
					hit = true
					if p.has_method("knockback"):
						p.knockback(dir, float(data.get("knockback", 7.0)))
					Events.hitstop.emit(0.06)
	if _pending_scorch:
		_pending_scorch = false
		_land_scorched()
	elif hit:
		_enter("rebound", T_REBOUND)
	else:
		_enter("stuck", float(T_STUCK[clampi(intensity(), 0, 2)]))
		Events.hint.emit("boss_stuck", "It's stuck! Strike now with {attack}!")


func _begin_climb() -> void:
	var target := _nearest_anchor(global_position)
	_from = global_transform
	_to = _ceiling_pose(target, _player_pos())
	_anchor = target
	_enter("climb", float(T_CLIMB[clampi(intensity(), 0, 2)]))
	Audio.play_3d(_snd("skitter"), global_position, -2.0, 0.1, 40.0)


func _land_scorched() -> void:
	global_transform = _ground_pose(Vector3(global_position.x, _floor_y, global_position.z), _player_pos())
	HitFx.burst(global_position + Vector3.UP * 0.3, Color(0.72, 0.68, 0.76), 16, 3.5, 1.4, -9.0, 0.6)
	Audio.play_3d(_snd("drop"), global_position, 0.0, 0.05, 50.0)
	Events.camera_shake.emit(0.5, 0.3)
	_enter("scorched", float(T_SCORCHED[clampi(intensity(), 0, 2)]))
	Events.hint.emit("boss_scorched", "The light burned it off the ceiling! Strike while it's stunned!")


# --- Braziers ---------------------------------------------------------------------------------------------

func _on_brazier_lit(brazier: Node) -> void:
	if _gone or _defeat_started:
		return
	var bpos := global_position
	if brazier is Node3D and is_instance_valid(brazier):
		bpos = (brazier as Node3D).global_position
	_burn_anchor_near(bpos, true)
	if not fight_started:
		start_fight()
	Audio.play_3d(_snd("shriek"), global_position, -3.0, 0.05, 60.0)
	Events.caption.emit(_caption("scorch"))
	match state:
		"stuck", "scorched", "rebound":
			_enter("scorched", float(T_SCORCHED[clampi(intensity(), 0, 2)]))
		"drop":
			_pending_scorch = true
		"scorch_fall":
			pass
		_:
			_show_shadow(false)
			_from = global_transform
			var below := scorch_landing(global_position)
			_to = _ground_pose(_ground_at(below), _player_pos())
			_enter("scorch_fall", T_SCORCH_FALL)


## Where the scorched boss lands: below where it clung, but never on top of a brazier (the dungeon
## places them right under the anchors, and Krystal is standing next to the one she just lit) -
## nudged toward the arena centre just until it is BRAZIER_CLEARANCE away from every brazier, and
## never closer than CENTRE_CLEARANCE to the centre (the Heartseed cocoon sits there).
func scorch_landing(from: Vector3) -> Vector3:
	var p := Vector3(from.x, _floor_y, from.z)
	for step in 60:
		if not _near_brazier(p):
			break
		var to_c := Vector2(arena_center.x - p.x, arena_center.z - p.z)
		var l := to_c.length()
		if l <= CENTRE_CLEARANCE:
			break
		var d := to_c / l * minf(0.25, l - CENTRE_CLEARANCE)
		p.x += d.x
		p.z += d.y
	return p


func _near_brazier(p: Vector3) -> bool:
	for b in braziers:
		if b is Node3D and is_instance_valid(b) and (b as Node3D).is_inside_tree():
			if _flat((b as Node3D).global_position, p) < BRAZIER_CLEARANCE:
				return true
	return false


func _burn_anchor_near(pos: Vector3, fx: bool) -> void:
	if anchors.is_empty():
		return
	var best := 0
	for i in anchors.size():
		if _flat(anchors[i], pos) < _flat(anchors[best], pos):
			best = i
	var a: Vector3 = anchors[best]
	anchors.remove_at(best)
	burned.append(a)
	if fx:
		_spawn_burn_fx(a)
	anchor_burned.emit(a)
	if anchors.is_empty():
		pass     # it still has the deep crack above the centre to cling to (see _nearest_anchor)


func _nearest_anchor(pos: Vector3) -> Vector3:
	if anchors.is_empty():
		return Vector3(arena_center.x, _ceiling_y, arena_center.z)
	var best: Vector3 = anchors[0]
	for a in anchors:
		if (a as Vector3).distance_to(pos) < best.distance_to(pos):
			best = a
	return best


# --- Damage & defeat -----------------------------------------------------------------------------------------

func _on_damaged(amount: float, _source: Node, _dir: Vector3) -> void:
	HitFx.flash(self)
	HitFx.number(get_aim_point() + Vector3.UP * 0.8, amount)
	Audio.play_3d("enemy_hurt", get_aim_point(), -2.0, 0.1)
	if health.dead:
		return
	if health.hp <= 0.0:
		return        # the killing blow: `died` follows right after (no climb/shriek first)
	_window_damage += amount
	if state in VULNERABLE_STATES and _window_damage >= health.max_hp * WINDOW_CAP:
		Audio.play_3d(_snd("shriek"), global_position, -6.0, 0.1, 50.0)
		_begin_climb()


func _on_health_changed(_hp: float, _max_hp: float) -> void:
	if fight_started:
		_emit_health()


func _emit_health() -> void:
	Events.boss_health_changed.emit(BOSS_ID, health.hp, health.max_hp)


func _on_died() -> void:
	_begin_defeat()


func _begin_defeat() -> void:
	if _defeat_started or _gone:
		return
	_defeat_started = true
	state = "defeat"
	health.invulnerable = true
	_show_shadow(false)
	if visual != null and visual.has_method("set_state"):
		visual.set_state("shriek", 1.5)
	Audio.play_3d(_snd("shriek"), global_position, -3.0, 0.0, 70.0)
	Events.caption.emit(_caption("defeat"))
	Events.camera_shake.emit(0.5, 0.8)
	if is_inside_tree() and not fast_defeat:
		await get_tree().create_timer(1.4).timeout
		# Retreat up into the deep crack in the ceiling - no death on screen.
		var crack := crack_point
		if visual != null and visual.has_method("set_state"):
			visual.set_state("move", 0.0)
		var tw := create_tween()
		tw.tween_property(self, "global_position", crack + Vector3.DOWN * 1.5, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "global_position", crack + Vector3.UP * 9.0, 1.4).set_ease(Tween.EASE_IN)
		if visual != null:
			tw.parallel().tween_property(visual, "scale", Vector3.ONE * 0.4, 1.4)
		await tw.finished
	_finish_defeat()


func _finish_defeat() -> void:
	_gone = true
	state = "gone"
	visible = false
	remove_from_group("enemy")
	Events.boss_health_changed.emit(BOSS_ID, -1.0, health.max_hp)
	GameState.set_flag("weaver_defeated", true)
	Events.boss_defeated.emit(BOSS_ID)
	defeated.emit()
	Audio.stop_music(4.0)
	ensure_heartseed(get_parent() if get_parent() != null else self, arena_center)
	state_changed.emit("gone")


func _on_player_died() -> void:
	reset_fight()


## Clean reset after Krystal is defeated: back up on a remaining anchor, dormant, bar hidden.
## Lit braziers / burned anchors and its wounds are kept on purpose (a kinder retry).
func reset_fight() -> void:
	if _gone or _defeat_started or not _initialized:
		return
	_pending_scorch = false
	_away_t = 0.0
	_show_shadow(false)
	_anchor = _nearest_anchor(global_position)
	global_transform = _ceiling_pose(_anchor, _player_pos())
	if fight_started:
		fight_started = false
		Events.boss_health_changed.emit(BOSS_ID, -1.0, health.max_hp)
		Audio.stop_music(3.0)
	_enter("dormant")


# --- Poses ----------------------------------------------------------------------------------------------------

## Transform hanging from a ceiling point, facing toward `look` horizontally.
func _ceiling_pose(anchor: Vector3, look: Vector3) -> Transform3D:
	var fwd := Vector3(look.x - anchor.x, 0.0, look.z - anchor.z)
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	if _using_shade:
		var h: float = float(visual.call("body_height")) if visual != null and visual.has_method("body_height") else 4.5
		return Transform3D(_basis_up(Vector3.UP, fwd), anchor + Vector3.DOWN * (h + 0.1))
	return Transform3D(_basis_up(Vector3.DOWN, fwd), anchor + Vector3.DOWN * 0.05)


func _ground_pose(pos: Vector3, look: Vector3) -> Transform3D:
	var fwd := Vector3(look.x - pos.x, 0.0, look.z - pos.z)
	if fwd.length_squared() < 0.01:
		fwd = -global_transform.basis.z
		fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	return Transform3D(_basis_up(Vector3.UP, fwd.normalized()), pos)


static func _basis_up(up: Vector3, fwd: Vector3) -> Basis:
	var u := up.normalized()
	var f := fwd - u * fwd.dot(u)
	if f.length_squared() < 0.0001:
		f = Vector3.RIGHT
	f = f.normalized()
	var z := -f
	var x := u.cross(z).normalized()
	return Basis(x, u, z).orthonormalized()


static func _lerp_xform(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)
	return Transform3D(Basis(q), a.origin.lerp(b.origin, t))


func _face_player_on_ceiling(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	var target := _ceiling_pose(_anchor, p.global_position)
	global_transform = _lerp_xform(global_transform, target, clampf(delta * 1.5, 0.0, 1.0))


func _ground_at(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return p if hit.is_empty() else (hit["position"] as Vector3)


# --- Helpers ---------------------------------------------------------------------------------------------------

func _player() -> Node3D:
	if target_override != null:
		return target_override if is_instance_valid(target_override) else null
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _player_pos() -> Vector3:
	var p := _player()
	return p.global_position if p != null else arena_center


func _hunt_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "loading" or Game.mode == "cutscene":
		return false
	var h := Combat.find_health(p)
	return not (h != null and h.get("dead") == true)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _notice_companions() -> void:
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("notice_threat"):
			(c as Node).notice_threat(global_position)


func _disconnect_brazier(b: Variant) -> void:
	if b is Node and is_instance_valid(b) and (b as Node).has_signal("lit"):
		for con in (b as Node).get_signal_connection_list("lit"):
			var cb: Callable = con["callable"]
			if cb.get_object() == self:
				(b as Node).disconnect("lit", cb)


# --- Visuals ------------------------------------------------------------------------------------------------------

func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


func _build_visual() -> void:
	if visual != null:
		visual.queue_free()
		visual = null
	_using_shade = _arachno()
	if _using_shade:
		visual = ShadeVisual.new()
		visual.setup({"scale": SHADE_SCALE, "boss": true})
	else:
		visual = WeaverVisual.new()
		visual.setup({"scale": WEAVER_SCALE, "boss": true})
	visual.name = "Visual"
	add_child(visual)


func _on_settings_changed(key: String) -> void:
	if key != "arachnophobia" or _gone or _using_shade == _arachno():
		return
	_build_visual()
	# Re-seat on the ceiling with the new body's hanging offset; timers are left untouched.
	if state in ["dormant", "intro", "cling", "telegraph"]:
		global_transform = _ceiling_pose(_anchor, _player_pos())
	elif state in ["reposition", "climb"]:
		_to = _ceiling_pose(_anchor, _player_pos())
	_apply_visual_state(state, _state_len)


func _build_shadow() -> void:
	_shadow = Node3D.new()
	_shadow.name = "DropShadow"
	add_child(_shadow)
	_shadow.top_level = true
	_shadow_disc_mat = StandardMaterial3D.new()
	_shadow_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_disc_mat.albedo_color = Color(0.03, 0.01, 0.05, 0.6)
	var disc := Kit.cylinder(1.0, 1.0, 0.02, _shadow_disc_mat, 32)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.add_child(disc)
	_shadow_ring_mat = HitFx.new_additive(Color(0.9, 0.28, 0.22))
	var ring := Kit.torus(0.93, 1.0, _shadow_ring_mat)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_shadow, ring, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	_shadow.visible = false


func _show_shadow(on: bool) -> void:
	if _shadow == null:
		return
	_shadow.visible = on
	if on:
		_shadow.global_position = _drop_target + Vector3.UP * 0.04
		_update_shadow(0.0)


func _update_shadow(k: float) -> void:
	if _shadow == null or not _shadow.visible:
		return
	var r := SLAM_RADIUS * lerpf(0.45, 1.0, clampf(k * 1.4, 0.0, 1.0))
	_shadow.scale = Vector3(r, 1.0, r)
	var strength: float
	if HitFx.reduce_flashing():
		strength = lerpf(0.4, 0.6, k)          # steady ring that firms up: no strobing
	else:
		var pulse := 0.5 + 0.5 * sin(state_time * (10.0 + 14.0 * k))
		strength = 0.35 + 0.5 * pulse
	_shadow_ring_mat.albedo_color = Color(0.9 * strength, 0.28 * strength, 0.22 * strength)
	_shadow_disc_mat.albedo_color = Color(0.03, 0.01, 0.05, lerpf(0.35, 0.7, k))


func _spawn_burn_fx(a: Vector3) -> void:
	var parent: Node = get_parent() if get_parent() != null else self
	var fx := Node3D.new()
	fx.name = "BurnedAnchor"
	parent.add_child(fx)
	fx.global_position = a
	var glow := Kit.blob(0.35, Mat.glow(Color("ff8a3d"), 1.6), 9, 0.4, 0.4, 2)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(glow)
	var embers := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = 0.035
	m.height = 0.07
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color("ffb35c")
	m.material = pm
	embers.mesh = m
	embers.amount = 10
	embers.lifetime = 2.2
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.5
	embers.gravity = Vector3(0, -1.2, 0)
	embers.initial_velocity_min = 0.0
	embers.initial_velocity_max = 0.3
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(embers)
	embers.emitting = true
	HitFx.burst(a, Color("ffb35c"), 24, 3.0, 1.2, -6.0, 0.9, 120.0)


func _snd(kind: String) -> String:
	var shade := _using_shade
	match kind:
		"rattle":
			return "shade_telegraph" if shade else "weaver_rattle"
		"skitter":
			return "shade_drift" if shade else "weaver_skitter"
		"drop":
			return "hit_hard" if shade else "weaver_drop"
		"shriek":
			return "shade_shriek" if shade else "weaver_shriek"
	return kind


func _caption(kind: String) -> String:
	var shade := _using_shade
	match kind:
		"intro":
			return "[a hollow wail fills the chamber]" if shade else "[a piercing shriek echoes through the chamber]"
		"rattle":
			return "[a whisper gathers overhead]" if shade else "[a dry rattle overhead]"
		"scorch":
			return "[it wails as the light burns it]" if shade else "[it shrieks as the light scorches it]"
		"defeat":
			return "[the Hollow Mother wails and withdraws into the deep]" if shade else "[the Weaver shrieks and flees into the deep]"
	return ""
