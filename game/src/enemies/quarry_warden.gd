extends "res://src/enemies/enemy_base.gd"
## Quarry Warden (Ashbell elite, MP 12; spawned by the arena's guarded spawner hr_sp_quarry_warden with setup
## {"arena": node, "arena_center": Vector3, "arena_radius": float, "pillars": [quarry_pillar nodes]}): a broad stone
## guardian with a cracked bronze bell set in its shell. Three attacks with their OWN tells (data "attacks"):
##   slam     (the lesson: side-step and punish) telegraph (data 1.4 s): it rears up, both fists overhead, the bell
##            glows (amber tint), an amber WEDGE (slam_reach, data arc_deg 70) is drawn and locks at 60% -> one
##            heavy slam -> recover (data 1.8 s) with its shell OPEN (full damage): the punish window.
##   pulses   (phase 2, below PHASE2_RATIO health) telegraph (data 1.6 s): fists planted, the bell hums and three pips
##            on it light one after another while a red RING of the pulse radius (data 5 m) is drawn -> three
##            SPACED ground pulses (data count 3, spacing 0.9 s), each full circle, line of sight, player only ->
##            recover (data 2.0 s, shell open). Step out of the ring, or roll each beat.
##   charge   (after its first slam, when Krystal stands beyond slam reach) telegraph (data 1.6 s): it scrapes the
##            ground and lowers its head (red tint), a red LANE (LANE_WIDTH, data distance 12 m, clipped at walls
##            and pillars, and at the arena: its end stays within arena_radius - ARENA_EDGE_MARGIN of arena_center, the
##            mark shows the clipped length) tracks her for 60% then locks -> a committed straight charge (one hit):
##              * into an INTACT mineral pillar: the pillar cracks (quarry_pillar.crack()) and the Warden is EXPOSED
##                for EXPOSE_TIME: its shell splits open around the glowing bell, it takes EXPOSED_MULT damage and
##                companions may join in - but one exposure takes at most EXPOSE_CAP of its health (the blow that
##                reaches the cap is trimmed to it and the shell grinds shut at once; QA CH2-004: one uncapped window
##                took ~250 of 300 with the starting copper sword and skipped the pulse phase). Early gear needs about
##                2-3 exposures;
##              * into a plain wall - or up to a LEDGE (no floor within LEDGE_PROBE_DEPTH below its next step, so a
##                charge baited at the L2 edge never carries it down to L1): a bonk and a stun (shell open);
##              * nothing in the way: it skids to a stop and recovers for data recover (3.5 s, shell open).
## Shell: outside those windows the shell takes SHELL_MULT of every hit (never nothing: early tools still work).
## Phase 2 always shows its pulses (MP 12 "then introduce three spaced ground pulses"; QA CH2-004): crossing
## PHASE2_RATIO makes the pulses OWED - its next attack is the pulses (from pulse reach) - and while they are owed
## blows never take it below PULSE_FLOOR_RATIO of its health (the excess glances off, a hint explains). The first
## full pulse cycle pays the debt; after that phase 2 picks its attacks as before. Never a softlock: the pulses are
## an ordinary committed attack it starts as soon as Krystal is within reach.
## Never unwinnable: pillars come from the arena (3, re-knitting by themselves) or group "quarry_pillar" near the
## arena; when NO intact pillar is left (or none exists) a charge into any wall exposes it too.
## Companions (spec 9) may only hit it while exposed or recovering (can_be_hit_by). Ordinary hits never stagger it;
## POISE damage within POISE_WINDOW breaks its poise for a short stun.
## Encounter events (elite, ids of data/enemies.gd): engaging emits Events.boss_encounter_changed("quarry_warden",
## true) and shows its health bar (boss_health_changed; -1 hides it), phase 2 emits boss_phase_changed(id, 2); a
## director present in the area is held for the fight. Defeat commits FIRST - boss_encounter_changed(false),
## Events.boss_defeated("quarry_warden") (the arena's listener sets hr_warden_defeated), enemy_killed and the
## spawner's clear (its quest flag) - and only then plays the defeat.
## Reset policy (retry): Krystal's defeat or walking out of its leash ends the encounter: the bar hides, every pillar
## re-knits, and once home (or idle) it is whole again (full health, phase 1, lesson restarted). The leash is bound
## to the arena (ring + ARENA_LEASH_MARGIN, same level within ARENA_LEASH_DY), so it never stays engaged below the
## crystal shelf. The arena additionally despawns a living Warden on her defeat. Permanent progress
## (hr_warden_defeated, the winch) is never touched here.
## Intensity (enemy_base intensity_* / overlap_blocked): Gentle = longer wind-ups / rests / pulse spacing; Intense =
## shorter rests only (no feint; the 1.6 s pulse / charge wind-ups stay above the 1.0-1.4 s guideline on purpose:
## longer tells are fairer, never shorter - integration pass 2, P11). Settings timing_assist (elites count as boss
## mechanics): every wind-up, recovery and the pulse spacing x TIMING_ASSIST_MULT, the exposure EXPOSE_TIME_ASSIST.
## Stats: data/enemies.gd "quarry_warden". Sounds (existing names only): dir_pebbles (alert), dir_creak (slam tell),
## rock_break (slam / bonk), ward_hum (pulse tell), mine_hit (each pulse), dig (charge tell), mine_cart (charging),
## heartseed_pulse (exposed), hit_soft (shell glance), enemy_hurt, tree_fall (defeat).

const Visual := preload("res://src/enemies/quarry_warden_visual.gd")

const BAR_ID := "quarry_warden"
const HOLD_ID := "quarry_warden"
const SLAM_TIME := 0.55
const SLAM_HIT_AT := 0.25
const SLAM_REACH_BONUS := 0.4
const PULSE_FIRST_AT := 0.1
const PULSE_TAIL := 0.25
const GENTLE_PULSE_SPACING := 0.2
const CHARGE_SPEED := 9.0
const CHARGE_START_FRACTION := 0.75
const LANE_WIDTH := 2.2
const HIT_AHEAD := 0.8
const BONK_EXTRA := 1.0
const PILLAR_REACH := 1.0            # a pillar within this gap ahead of its body when the charge stops was hit
const EXPOSE_TIME := 6.0
const EXPOSE_TIME_ASSIST := 7.5      # Settings timing_assist
const TIMING_ASSIST_MULT := 1.5      # Settings timing_assist: wind-ups, recoveries and pulse spacing (as the bosses)
const ARENA_LEASH_MARGIN := 6.0      # the fight follows Krystal this far past its arena ring, no further
const ARENA_LEASH_DY := 3.0          # ... and only on about the arena's own level (never up on the crystal shelf)
const ARENA_EDGE_MARGIN := 1.0       # a charge lane ends at least this far inside the arena ring
const LEDGE_PROBE_DEPTH := 1.0       # no floor within this below its next charge step = a ledge: bonk
const LEDGE_PROBE_LEAD := 0.45       # ... probed this far ahead of that step (its front half stays on the floor)
const SHELL_MULT := 0.5
const OPEN_MULT := 1.0
const EXPOSED_MULT := 1.6
const EXPOSE_CAP := 0.35             # of max health: the most one exposure can take (then the shell grinds shut)
const PHASE2_RATIO := 0.66
const PULSE_FLOOR_RATIO := 0.3       # of max health: blows stop here while the phase-2 pulses are still owed
const SLAMS_BEFORE_CHARGE := 1
const POISE := 45.0
const POISE_WINDOW := 5.0
const POISE_STUN := 1.0
const POISE_IMMUNITY := 8.0
const LANE_REFRESH := 0.1
const STONE := Color("b8674a")
const CRYSTAL := Color("cfe0ff")

var arena: Node = null
var arena_center := Vector3.ZERO
var arena_radius: float = 14.0
var pillars: Array = []
var next_attack: String = ""         # tests / scripted fights: "slam" | "pulses" | "charge"
var attack_kind: String = ""
var phase: int = 1
var engaged := false
var slams_done: int = 0
var charges_done: int = 0
var pulses_fired: int = 0
var exposures: int = 0
var exposures_capped: int = 0        # exposures cut short by EXPOSE_CAP
var exposure_damage: float = 0.0     # health taken in the current / last exposure (<= expose_cap())
var pillars_cracked: int = 0
var last_charge_result: String = ""  # "hit" | "missed" | "pillar" | "wall" | "wall_exposed"
var ledge_stops: int = 0             # charges stopped by a ledge (no floor ahead) - they bonk like a wall
var _arena_set := false
var _radius_set := false
var _def: Dictionary = {}
var _resolved := false
var _center := Vector3.ZERO
var _pulse_i: int = 0
var _since_pulses: int = 2
var _pulses_owed := false
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _poise_dmg: float = 0.0
var _poise_t: float = 0.0
var _poise_immune: float = 0.0


func _init() -> void:
	hit_color = Color(0.86, 0.6, 0.46)
	committed_states = ["slam", "pulses", "charge"]
	needs_clear_shot = true


func setup(params: Dictionary) -> void:
	super.setup(params)
	var a: Variant = params.get("arena")
	if a is Node:
		arena = a
	var c: Variant = params.get("arena_center")
	if c is Vector3:
		arena_center = c
		_arena_set = true
	if params.has("arena_radius"):
		arena_radius = maxf(float(params["arena_radius"]), 4.0)
		_radius_set = true
	var pl: Variant = params.get("pillars")
	if pl is Array:
		pillars = (pl as Array).duplicate()


func _ready() -> void:
	super._ready()
	if not _radius_set:
		arena_radius = float(data.get("arena_radius", arena_radius))
	# It spawns inside its arena: a centre farther than the arena radius from its home is a stale / unset value
	# (e.g. the spawner's placeholder before the arena refreshed its world position) - the leash and the pillar
	# search would then never match. Fall back to home.
	if not _arena_set or Vector2(arena_center.x - home.x, arena_center.z - home.z).length() > arena_radius:
		arena_center = home
	health.changed.connect(_on_health_changed)
	_update_armor()


func _exit_tree() -> void:
	super._exit_tree()
	_disengage()


func _default_id() -> String:
	return "quarry_warden"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.9


func _body_height() -> float:
	return 2.3


func _knockback_scale() -> float:
	return 0.1


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


# --- Encounter bookkeeping ---------------------------------------------------------------------------------------

func _engage() -> void:
	if engaged:
		return
	engaged = true
	Events.boss_encounter_changed.emit(BAR_ID, true)
	if health != null:
		Events.boss_health_changed.emit(BAR_ID, float(health.hp), float(health.max_hp))
	var d: Node = Game.director
	if d != null and is_instance_valid(d) and d.has_method("hold"):
		d.call("hold", HOLD_ID)


func _disengage() -> void:
	if not engaged:
		return
	engaged = false
	Events.boss_health_changed.emit(BAR_ID, -1.0, float(health.max_hp) if health != null else 1.0)
	Events.boss_encounter_changed.emit(BAR_ID, false)
	var d: Node = Game.director
	if d != null and is_instance_valid(d) and d.has_method("release"):
		d.call("release", HOLD_ID)


func _on_health_changed(hp: float, max_hp: float) -> void:
	if engaged and hp > 0.0:
		Events.boss_health_changed.emit(BAR_ID, hp, max_hp)
	if phase == 1 and hp > 0.0 and max_hp > 0.0 and hp / max_hp <= PHASE2_RATIO:
		phase = 2
		_since_pulses = 2
		_pulses_owed = true                         # phase 2 opens with its pulses (never skipped by a burst)
		Events.boss_phase_changed.emit(BAR_ID, 2)
		Events.caption.emit("[the cracked bell begins to hum]")
		if visual != null and visual.has_method("set_phase"):
			visual.set_phase(2)


## Every pillar this Warden may be baited into (setup "pillars", else group "quarry_pillar" around its arena).
func pillar_nodes() -> Array:
	var out: Array = []
	for p in pillars:
		if p is Node3D and is_instance_valid(p):
			out.append(p)
	if not out.is_empty() or not is_inside_tree():
		return out
	for p in get_tree().get_nodes_in_group("quarry_pillar"):
		if p is Node3D and is_instance_valid(p):
			var g := (p as Node3D).global_position
			if Vector2(g.x - arena_center.x, g.z - arena_center.z).length() <= arena_radius + 3.0:
				out.append(p)
	return out


func intact_pillars() -> int:
	var n := 0
	for p in pillar_nodes():
		if bool(p.call("is_intact")):
			n += 1
	return n


func _reset_pillars() -> void:
	for p in pillar_nodes():
		if p.has_method("reset"):
			p.call("reset")


## Clean retry state: every pillar whole, the Warden whole, the lesson restarts (never mismatched props).
func reset_encounter() -> void:
	_disengage()
	_reset_pillars()
	if health != null and not health.dead:
		health.set_hp(health.max_hp)
	phase = 1
	slams_done = 0
	_since_pulses = 2
	_pulses_owed = false
	exposure_damage = 0.0
	_poise_dmg = 0.0
	_poise_t = 0.0
	_poise_immune = 0.0
	if visual != null and visual.has_method("set_phase"):
		visual.set_phase(1)


# --- Attacks -----------------------------------------------------------------------------------------------------

func slam_reach() -> float:
	return float(data.get("attack_range", 3.4)) + SLAM_REACH_BONUS


func slam_arc() -> float:
	return float(attack_def("slam").get("arc_deg", 70.0))


func charge_distance() -> float:
	return float(attack_def("charge").get("distance", 12.0))


## The charge length from `from` along `dir` before walls: data distance, clipped so the lane's end stays within
## arena_radius - ARENA_EDGE_MARGIN of arena_center (flat). The lane mark and the charge use the same number.
func charge_reach(from: Vector3, dir: Vector3) -> float:
	return minf(charge_distance(), arena_lane_limit(from, dir))


## How far a flat lane from `from` along `dir` may run before leaving the circle of radius
## arena_radius - ARENA_EDGE_MARGIN around arena_center (0 when it starts outside heading further out).
func arena_lane_limit(from: Vector3, dir: Vector3) -> float:
	var d := Vector2(dir.x, dir.z)
	if d.length_squared() < 0.000001:
		return 0.0
	d = d.normalized()
	var r := maxf(arena_radius - ARENA_EDGE_MARGIN, 0.5)
	var f := Vector2(from.x - arena_center.x, from.z - arena_center.z)
	var b := f.dot(d)
	var disc := b * b - (f.length_squared() - r * r)
	if disc < 0.0:
		return 0.0
	return maxf(-b + sqrt(disc), 0.0)


## Is there floor (world | structure) within LEDGE_PROBE_DEPTH below the point `step` metres ahead along `dir`
## (+ LEDGE_PROBE_LEAD)? One short ray. Outside the tree (pure tests) the floor is assumed.
func floor_ahead(dir: Vector3, step: float) -> bool:
	if not is_inside_tree():
		return true
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		return true
	var p := global_position + d.normalized() * (maxf(step, 0.0) + LEDGE_PROBE_LEAD)
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p - Vector3.UP * LEDGE_PROBE_DEPTH, Combat.LOS_MASK)
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func pulse_radius() -> float:
	return float(attack_def("pulses").get("radius", 5.0))


func pulse_count() -> int:
	return maxi(int(attack_def("pulses").get("count", 3)), 1)


func pulse_spacing() -> float:
	var s := float(attack_def("pulses").get("spacing", 0.9)) + (GENTLE_PULSE_SPACING if Combat.current_intensity() == 0 else 0.0)
	return s * assist_mult()


## Settings timing_assist ("removes tight timing windows from ... boss mechanics"): like the bosses, every wind-up,
## recovery and the pulse spacing last TIMING_ASSIST_MULT longer (the exposure window has its own EXPOSE_TIME_ASSIST).
func assist_mult() -> float:
	return TIMING_ASSIST_MULT if bool(Settings.get_value("timing_assist")) else 1.0


func pulse_time(i: int) -> float:
	return PULSE_FIRST_AT + float(i) * pulse_spacing()


func charge_unlocked() -> bool:
	return slams_done >= SLAMS_BEFORE_CHARGE


func lane_length() -> float:
	return _lane_len


func expose_time() -> float:
	return EXPOSE_TIME_ASSIST if bool(Settings.get_value("timing_assist")) else EXPOSE_TIME


func attack_reach() -> float:
	var close := float(data.get("attack_range", 3.4))
	if next_attack == "pulses" or (next_attack == "" and _pulses_owed):
		return maxf(close, pulse_radius() * 0.8)
	if next_attack == "charge" or (next_attack == "" and charge_unlocked()):
		return maxf(close, charge_distance() * CHARGE_START_FRACTION)
	return close


## True from the moment phase 2 begins until its first full pulse cycle has played (its next attack is the pulses).
func pulses_owed() -> bool:
	return _pulses_owed


## The most health one exposure can take (EXPOSE_CAP of max health).
func expose_cap() -> float:
	return float(health.max_hp) * EXPOSE_CAP if health != null else 0.0


## Blows never take it below this now: PULSE_FLOOR_RATIO of max health while the phase-2 pulses are owed, else 0.
func pulse_floor() -> float:
	if not _pulses_owed or health == null:
		return 0.0
	return float(health.max_hp) * PULSE_FLOOR_RATIO


func _can_start_attack() -> bool:
	return _shot_clear and not overlap_blocked()


func _choose_attack() -> void:
	var kind := next_attack
	if kind == "" and _pulses_owed:
		kind = "pulses"
	if kind == "":
		var dist := _flat_dist_to_player()
		var pulses_ok := phase >= 2 and _since_pulses >= 2
		if dist <= slam_reach() - 0.2:
			kind = "pulses" if pulses_ok and _rng.randf() < 0.5 else "slam"
		elif charge_unlocked():
			kind = "pulses" if pulses_ok and dist <= pulse_radius() * 0.8 and _rng.randf() < 0.35 else "charge"
		else:
			kind = "slam"
	next_attack = ""
	attack_kind = kind
	_def = attack_def(kind)
	if kind == "pulses":
		_since_pulses = 0
	else:
		_since_pulses += 1
	if visual != null and visual.has_method("set_attack"):
		visual.set_attack(kind)


func telegraph_duration() -> float:
	return (attack_telegraph(_def) + intensity_telegraph_bonus()) * assist_mult()


func recover_duration() -> float:
	return attack_recover(_def) * assist_mult()


## The fight stays inside its arena (MP 12: safe arena boundaries). Besides the data leash, Krystal counts as within
## reach of the encounter only while she stands within ARENA_LEASH_MARGIN of the arena ring and on about its level
## (ARENA_LEASH_DY): walking away or climbing out of its reach (the crystal shelf above the arena) ends the encounter
## with the clean reset below, instead of a Warden that stays engaged - bar up, saving blocked - under a ledge.
func _player_within_leash() -> bool:
	if not super._player_within_leash():
		return false
	var p := _player.global_position
	if absf(p.y - arena_center.y) > ARENA_LEASH_DY:
		return false
	return Vector2(p.x - arena_center.x, p.z - arena_center.z).length() <= arena_radius + ARENA_LEASH_MARGIN


func _on_telegraph_start() -> void:
	_lane_clip_t = 0.0
	_center = global_position
	match attack_kind:
		"slam":
			Audio.play_3d("dir_creak", global_position + Vector3.UP * 2.0, 0.0, 0.08)
			announce_tell(_def, "[stone grinds; the cracked bell glows]")
		"pulses":
			Audio.play_3d("ward_hum", global_position + Vector3.UP * 1.6, 1.0, 0.05)
			announce_tell(_def, "[the cracked bell hums three times]")
		"charge":
			Audio.play_3d("dig", global_position + Vector3.UP * 0.3, 0.0, 0.08)
			announce_tell(_def, "[heavy feet scrape the stone]")
	_update_mark(true)


func _tick_extra(delta: float) -> void:
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
		"pulses":
			if not m.is_showing():
				m.show_ring(_center, pulse_radius(), TelegraphFx.DANGER)
			locked = true
			if visual != null and visual.has_method("set_pips"):
				visual.set_pips(clampi(int(state_time / maxf(_state_len, 0.001) * float(pulse_count() + 1)), 0, pulse_count()))
		"charge":
			if reclip:
				_lane_clip_t = LANE_REFRESH
				_lane_len = float(lane_clip(global_position, fwd, charge_reach(global_position, fwd))["length"])
			if not m.is_showing():
				m.show_lane(global_position, global_position + fwd * _lane_len, LANE_WIDTH, TelegraphFx.DANGER)
			elif not locked:
				m.move_lane(global_position, global_position + fwd * _lane_len)
		_:
			if not m.is_showing():
				m.show_arc(global_position, fwd, slam_reach(), slam_arc(), TelegraphFx.WARN)
			elif not locked:
				m.move_arc(global_position, fwd)
	m.set_progress(state_time / maxf(_state_len, 0.001), locked)


func _telegraph_finished() -> void:
	_attack_dir = _forward()
	_resolved = false
	match attack_kind:
		"charge":
			_enter("charge", 0.0)
			_lane_len = charge_begin(_attack_dir, charge_reach(global_position, _attack_dir), CHARGE_SPEED)
			var m := mark()
			m.show_lane(global_position, charge_lane_end(), LANE_WIDTH, TelegraphFx.DANGER)
			m.set_progress(1.0, true)
			Audio.play_3d("mine_cart", global_position + Vector3.UP * 0.8, -2.0, 0.05)
		"pulses":
			_pulse_i = 0
			_enter("pulses", pulse_time(pulse_count() - 1) + PULSE_TAIL)
			mark().set_progress(1.0, true)
			if visual != null and visual.has_method("set_pips"):
				visual.set_pips(pulse_count())
		_:
			_enter("slam", SLAM_TIME)
			mark().set_progress(1.0, true)


func _st_custom(state_name: String, delta: float) -> void:
	match state_name:
		"slam":
			if not _resolved and state_time >= SLAM_HIT_AT:
				_resolved = true
				var hits: Array = Combat.melee(self, global_position + Vector3.UP * 1.0, _attack_dir, slam_reach(), slam_arc(),
					attack_damage_for(_def), ["player"], float(data.get("knockback", 8.0)))
				slams_done += 1
				Audio.play_3d("rock_break", global_position + _attack_dir * 2.0, 0.0, 0.08)
				HitFx.chips(global_position + _attack_dir * 2.2 + Vector3.UP * 0.2, STONE, 10, 3.2, 0.6)
				Events.camera_shake.emit(0.2, 0.25)
				_on_attack_resolved(hits)
			if state_time >= SLAM_TIME:
				_enter("recover", recover_duration())
		"pulses":
			while _pulse_i < pulse_count() and state_time >= pulse_time(_pulse_i):
				_pulse_i += 1
				pulses_fired += 1
				var hits2: Array = pulse_hits(_center, pulse_radius(), attack_damage_for(_def), float(data.get("knockback", 8.0)))
				Audio.play_3d("mine_hit", global_position + Vector3.UP * 1.6, 1.0, 0.03)
				Events.camera_shake.emit(0.12, 0.18)
				HitFx.chips(_center + Vector3.UP * 0.2, STONE, 8, 3.0, 0.5)
				if visual != null and visual.has_method("pulse_fired"):
					visual.pulse_fired(pulse_count() - _pulse_i)
				_on_attack_resolved(hits2)
				if _pulse_i >= pulse_count():
					_pulses_owed = false                # a full cycle played: the phase-2 floor lifts
			if state_time >= _state_len:
				_enter("recover", recover_duration())
		"charge":
			if _charge_active and not floor_ahead(_charge_dir, CHARGE_SPEED * delta):
				_charge_active = false                 # a ledge ahead (e.g. the L2 edge): it bonks, never falls to L1
				ledge_stops += 1
				_charge_stopped_at_wall()
				return
			var r := charge_step(delta, HIT_AHEAD, LANE_WIDTH * 0.5, attack_damage_for(_def), float(data.get("knockback", 8.0)))
			match r:
				"hit":
					_end_charge("hit")
				"done":
					_end_charge("missed")
				"wall":
					_charge_stopped_at_wall()
				_:
					if state_time > _lane_len / CHARGE_SPEED + 0.6:
						_end_charge("missed")
		"exposed":
			if state_time >= _state_len:
				_end_exposure(false)


func _end_charge(result: String) -> void:
	charges_done += 1
	last_charge_result = result
	_enter("recover", recover_duration())


## The charge was stopped by something solid: an intact pillar cracks and exposes it; a plain wall only bonks it -
## unless no intact pillar is left anywhere (then any wall exposes it: the arena is never unwinnable).
func _charge_stopped_at_wall() -> void:
	charges_done += 1
	var pl := _pillar_ahead()
	if pl != null:
		pl.call("crack")
		pillars_cracked += 1
		last_charge_result = "pillar"
		_expose()
		return
	if intact_pillars() == 0:
		last_charge_result = "wall_exposed"
		_expose()
		return
	last_charge_result = "wall"
	stun(recover_duration() + BONK_EXTRA)
	_cooldown = float(data.get("cooldown", 3.0))
	Audio.play_3d("rock_break", global_position + _charge_dir * 1.2, -2.0, 0.1)
	Events.camera_shake.emit(0.18, 0.25)


func _pillar_ahead() -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	var g := global_position
	for p in pillar_nodes():
		if not bool(p.call("is_intact")):
			continue
		var pp := (p as Node3D).global_position
		var to := Vector3(pp.x - g.x, 0.0, pp.z - g.z)
		var dist := to.length()
		var hr: Variant = p.get("hit_radius")
		var pr: float = float(hr) if (hr is float or hr is int) else 0.85
		var gap := dist - _body_radius() - pr
		if gap > PILLAR_REACH:
			continue
		if dist > 0.01 and (to / dist).dot(_charge_dir) < 0.4:
			continue
		if gap < best_gap:
			best_gap = gap
			best = p as Node3D
	return best


func _expose() -> void:
	exposures += 1
	exposure_damage = 0.0
	_enter("exposed", expose_time())
	Audio.play_3d("heartseed_pulse", global_position + Vector3.UP * 1.6, 0.0, 0.05)
	HitFx.chips(global_position + Vector3.UP * 1.8, CRYSTAL, 12, 3.4, 0.8)
	Events.camera_shake.emit(0.25, 0.3)
	Events.caption.emit("[the Warden's shell cracks open around its glowing bell]")
	Events.hint.emit("hint_quarry_warden_exposed", "The Warden's shell is open! Strike the glowing bell before it closes.")


## The exposure ends - its time ran out, or it took expose_cap() (`capped`): the shell closes over the bell (its
## poise starts fresh: the bell blows never bank a stun for right after) and it fights on.
func _end_exposure(capped: bool) -> void:
	_poise_dmg = 0.0
	_poise_t = 0.0
	if capped:
		exposures_capped += 1
		Audio.play_3d("dir_creak", global_position + Vector3.UP * 1.6, -2.0, 0.08)
		HitFx.chips(global_position + Vector3.UP * 1.8, STONE, 8, 2.6, 0.5)
		Events.caption.emit("[the Warden's shell grinds shut over its bell]")
	_cooldown = float(data.get("cooldown", 3.0)) * intensity_cooldown_mult()
	_resume_after_interrupt()


func is_exposed() -> bool:
	return state == "exposed"


# --- Armour, stagger, filters ----------------------------------------------------------------------------------------

func _update_armor() -> void:
	if health == null:
		return
	match state:
		"exposed":
			health.damage_taken_mult = EXPOSED_MULT
		"recover", "stunned", "dead":
			health.damage_taken_mult = OPEN_MULT
		_:
			health.damage_taken_mult = SHELL_MULT


func armor_mult() -> float:
	return float(health.damage_taken_mult) if health != null else 1.0


## Companions (spec 9) only join in while its shell is open (exposed / recovering / stunned).
func can_be_hit_by(source: Node) -> bool:
	if not super.can_be_hit_by(source):
		return false
	if source != null and is_instance_valid(source) and source.is_in_group("companion"):
		return state in ["exposed", "recover", "stunned"]
	return true


## Elite: never flinches from ordinary hits; a poise break (POISE damage within POISE_WINDOW) stuns it briefly.
func can_stagger(_amount: float, _source: Node) -> bool:
	return state != "exposed" and _poise_immune <= 0.0 and _poise_dmg >= POISE


func _stagger(_amount: float, _source: Node) -> void:
	_poise_dmg = 0.0
	_poise_t = 0.0
	_poise_immune = POISE_IMMUNITY
	stun(POISE_STUN)
	Audio.play_3d("rock_break", global_position + Vector3.UP * 1.2, -6.0, 0.15)


func poise_damage() -> float:
	return _poise_dmg


func is_threatening() -> bool:
	return super.is_threatening() or state == "exposed"


func _is_uninterruptible() -> bool:
	return super._is_uninterruptible() or state == "exposed"


func _on_state_changed(prev: String, new_state: String) -> void:
	_update_armor()
	match new_state:
		"recover":
			_cooldown *= intensity_cooldown_mult()
		"chase":
			_engage()
		"return":
			_disengage()
			_reset_pillars()
		"idle":
			# Idle = the encounter is over (it also goes idle straight from recover / exposed / stunned when Krystal
			# left while it stood near home, without a "return"): always the same clean reset, never a Warden that
			# keeps its lost health / phase 2 or cracked pillars for the next approach.
			if prev == "return" or engaged or phase != 1 or (health != null and not health.dead and health.hp < health.max_hp):
				reset_encounter()
			else:
				_disengage()
		"dead":
			_disengage()
			Events.boss_defeated.emit(BAR_ID)        # commit (arena listener: hr_warden_defeated) before any presentation


func _on_player_died() -> void:
	if state in ["exposed", "stunned", "recover"]:
		_enter("return")
	else:
		super._on_player_died()
	reset_encounter()


# --- Damage limits (QA CH2-004) -----------------------------------------------------------------------------------

## Health emits `damaged` after taking the blow but before it tests for death: the part of a blow past the
## exposure cap or the owed-pulses floor is handed back here, so it never kills or skips through them.
func _on_damaged(amount: float, source: Node, dir: Vector3) -> void:
	var shown := _limit_damage(amount)
	if shown <= 0.0 and amount > 0.0 and health != null and health.hp > 0.0:
		HitFx.spark(get_aim_point() + _forward() * 0.6)      # nothing got through: it glances off
		return
	super._on_damaged(shown, source, dir)
	if state == "exposed" and health != null and health.hp > 0.0 and exposure_damage >= expose_cap() - 0.01:
		_end_exposure(true)


## The share of a blow (`amount`, already taken from health) it may keep: at most what is left of expose_cap() in
## an exposure, and never below pulse_floor(). The rest goes back to health.
func _limit_damage(amount: float) -> float:
	if health == null or amount <= 0.0:
		return amount
	var allowed := amount
	if state == "exposed":
		allowed = minf(allowed, maxf(expose_cap() - exposure_damage, 0.0))
	var fl := pulse_floor()
	if fl > 0.0:
		var floored := maxf(float(health.hp) + amount - fl, 0.0)
		if floored < allowed:
			allowed = floored
			_floor_hint()
	if allowed < amount:
		health.hp += amount - allowed
	if state == "exposed":
		exposure_damage += allowed
	return allowed


func _floor_hint() -> void:
	Events.hint.emit("hint_quarry_warden_pulses", "The cracked bell is humming - the Warden won't give way until it has rung its three pulses. Step out of the red ring, or roll on each beat!")


# --- Feedback ------------------------------------------------------------------------------------------------------

func _on_hurt(amount: float) -> void:
	_poise_dmg += amount
	_poise_t = POISE_WINDOW
	if armor_mult() < 1.0:
		HitFx.spark(get_aim_point() + _forward() * 0.6)      # glances off the shell (plays hit_soft)
	else:
		Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 1.4, -3.0, 0.1)
		HitFx.chips(get_aim_point(), STONE, 7, 3.0, 0.55)


func _on_alert() -> void:
	Audio.play_3d("dir_pebbles", global_position + Vector3.UP * 1.5, -1.0, 0.08)


func _idle_sound() -> void:
	Audio.play_3d("ward_hum", global_position + Vector3.UP * 1.5, -16.0, 0.05)


func _defeat_sound() -> String:
	return "tree_fall"


## Settles into stillness: it kneels, the bell's glow fades and a few crystal chips fall (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	Events.caption.emit("[the cracked bell rings once, softly, and falls quiet]")
	var tw := create_tween()
	tw.tween_property(visual, "position:y", -0.6, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.3).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.8
	HitFx.chips(pos, STONE, 18, 3.4, 1.0)
	HitFx.chips(pos, CRYSTAL, 10, 2.6, 0.9)
