extends Node3D
## The Weaver Matron (arachnophobia: the Hollow Mother) - boss of the Heartseed Chamber, reworked into
## three escalating phases (MP section 8). Also runs the optional Echo Trial copy ("mode": "trial").
##   setup({"arena_center": Vector3, "anchors": [ceiling Vector3...], "braziers": [boss_brazier nodes],
##          "arena_radius": 11.5 (optional: floor radius; the fight starts 3 m outside it, drops stay inside),
##          "crack": Vector3 (optional: the deep ceiling crack it flees into on defeat; default above the centre),
##          "trip_anchors": [floor Vector3...] (optional: fixed trip-line posts; default: a ring of 6),
##          "entrance": Vector3 (optional: arena mouth - no trip-line or egg sac is ever put across it),
##          "mode": "story" | "trial" (optional; trial = no flags, no Heartseed, no boss_defeated event),
##          "minion_id": "brood_skitter"})
##
## PHASE 1 (HP 100% .. 60%) "Something overhead" - the Chapter One fight, unchanged: it tracks between
## ceiling anchors (clings, sometimes repositions toward Krystal) and telegraphs a DROP (ground mark +
## rattle, 1.2 s Standard):
##   * the slam hits Krystal: it rebounds and climbs back up (no opening);
##   * the slam misses: it is STUCK for 2.5 s - the opening;
##   * a brazier is lit: shriek, scorched off the ceiling, stunned 5 s (x1.5 damage); the anchor nearest
##     that brazier burns away for good.
## PHASE 2 (60% .. 30%) "The floor becomes a web" - a readable rotation (fan, drop, trip-lines, drop):
##   * WEB FAN: a narrow wedge telegraphed on the floor (1.2 s), then a sheet that SLOWS (bounded,
##     expires; arachnophobia: a drifting pale veil) - then a recovery beat;
##   * TRIP-LINES: 1-2 visible lines between FIXED floor posts, always leaving the braziers and the
##     entrance reachable; cut them with any attack or burn them with the lit lantern (or jump);
##   * late in the phase (HP <= 45%), ONE release: shaking egg sacs (pale pods) at the far edge hatch
##     2 Brood Skitters (Pale Sprouts) on Standard/Intense, 1 slower one on Gentle, after a generous
##     warning - never underfoot, and no drop/pounce starts while a sac is still shaking;
##   * hazards are capped (Gentle 2 / Standard & Intense 3 live) and each expires on its own.
## PHASE 3 (30% .. 0) "Desperate weaving":
##   * lit braziers become REUSABLE: each gathers heat for a readable cooldown (a ring fills round the
##     bowl) and can then be stoked again for another scorch;
##   * CHANNEL: it lowers a visible thread onto a lit brazier (the one farthest from Krystal) to smother
##     it over 4 s. Strike the thread's glowing knot, or bring the lit lantern within 3 m, to snap it:
##     it loses its grip, falls and is stuck (an opening). If the channel finishes, the brazier goes out
##     and smoulders (relight it after the cooldown);
##   * COMBO: ONE ground hazard (a web fan) and then, after a beat, a DELAYED pounce (1.4 s mark) -
##     never a stack of attacks. Only one ground hazard is live at a time.
## Every major action is followed by a recovery window (recover on the ceiling, or stuck on the floor
## ~2.5 s after a missed pounce). Warnings for major attacks are >= 1.1 s (1.0-1.6 s by intensity).
## Phase changes: at the threshold it shrieks and climbs (invulnerable), every hazard is cleared,
## minions scatter when phase 3 begins, and Events.boss_phase_changed(id, phase) fires (music layers).
## Armour: it can only be hurt while stuck/scorched; otherwise hits glance off with a spark + hint.
## PACING (QA CH2-003: three brazier scorches used to win in ~23 s, skipping phases 2-3; MP section 8
## "phases and decisions over health inflation" - 240 HP is unchanged):
##   * a blow that crosses the next phase threshold stops exactly on it (never two thresholds in one
##     opening), then the transition plays - every phase starts with its whole HP band;
##   * one stun window takes at most WINDOW_CAP (40%: phase 1 = the Chapter One rule, one scorch can end
##     it) or, in phases 2-3, LATE_WINDOW_CAP (15% = half a band): each later phase needs two openings. The
##     blow that would overshoot the cap is trimmed to fit (the excess goes back to health before the death
##     test, a would-be lethal blow included) and ends the window - never 54 hp in a 36 hp window;
##   * phases 2-3 introduce their kit first: a brazier lit / stoked while it is overhead before it has
##     performed that phase's first action (fan / trip-lines / release in phase 2; the channel, the
##     combo's pounce or a fan in phase 3) still burns its anchor and still scorches it, but the scorch is
##     BANKED (shriek, embers, caption + hint) and lands the moment that first action ends.
## HP 0 -> defeat: it
## shrieks and retreats up into the deep crack (no death, no gore): story mode sets "weaver_defeated",
## emits Events.boss_defeated and the Heartseed pickup appears (re-created on load if still needed,
## never twice). A completed save never spawns the story boss again (state "gone").
## Companions: can_be_hit_by(source) is false while it is overhead/armoured and for any attacker
## outside the arena (so companions never chip it from the ceiling or finish it from outside).
##
## RESET POLICY (one rule, MP section 8 "Failure, replay, comfort"):
##   * Krystal falls, or walks out of the chamber (stand-down): the ACTIVE encounter resets cleanly -
##     back up on a remaining anchor, dormant, bar hidden, music released, every fan / trip-line / sac /
##     thread removed, minions scattered, any channel cancelled (its brazier stays lit), a banked scorch
##     dropped. Her wounds, the phase reached (and whether its kit was shown), burned anchors and lit
##     braziers are kept (a kinder retry that can never be
##     mismatched: in phases 1-2 missed drops always open it up, in phase 3 every lit brazier can be
##     stoked again and a smothered one relit after its cooldown).
##   * Quitting / reloading the area: nothing about an unfinished fight is saved - a fresh encounter
##     (240 HP, phase 1, cold braziers, all anchors).
##   * Won progression is never touched: "weaver_defeated" is never reset; the trial never writes it.
## Gentle: slower, softer (x0.6), longer stuns and warnings, fewer hazards, one slower minion and no
## drop while it is alive (unless it has been out longer than MINION_DROP_GATE s or is out of reach: a stuck or
## ignored minion never stalls the fight). Intense: repositions ("stalks") more, slightly shorter pauses - never shorter
## warnings than 1.1 s.
## Comfort settings: "timing_assist" stretches every warning, opening, recovery beat and the channel by
## TIMING_ASSIST_MULT (no tight windows); "high_visibility_cues" adds bold cream outlines to the drop /
## pounce mark and to every hazard (fan wedge, trip-lines, sacs, the thread knot, a ready brazier) - live.
## QA (cheats only): --matron-phase=2|3 starts the fight in that phase.

signal defeated
signal state_changed(new_state: String)
signal anchor_burned(anchor: Vector3)
signal phase_changed(phase: int)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Health := preload("res://src/combat/health.gd")
const WeaverVisual := preload("res://src/enemies/weaver_visual.gd")
const ShadeVisual := preload("res://src/enemies/shade_visual.gd")
const HeartseedPickup := preload("res://src/enemies/heartseed_pickup.gd")
const HazardField := preload("res://src/enemies/boss_hazards/hazard_field.gd")
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
const WINDOW_CAP := 0.4           # phase 1: one stun window takes at most this share of max HP (the whole band)
const LATE_WINDOW_CAP := 0.15     # phases 2-3: at most this share (36 of 240 = half a band): two openings each
const SCORCHED_DAMAGE_MULT := 1.5
const WEAVER_SCALE := 2.6
const SHADE_SCALE := 2.3
const VULNERABLE_STATES := ["stuck", "scorched"]
const GROUND_STATES := ["rebound", "stuck", "scorched"]
## States in which it hangs from the ceiling (visual "clinging", re-seated on an arachnophobia swap).
const CEILING_STATES := ["dormant", "intro", "cling", "reposition", "telegraph", "fan_tele", "trip_tele",
	"recover", "release", "channel", "phase_shriek", "combo_gap"]
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
# --- Phases 2-3 ------------------------------------------------------------------------------------
const PHASE_AT := [1.0, 0.6, 0.3]         # HP fraction at (or below) which phase 1 / 2 / 3 runs
const LATE_PHASE2_AT := 0.45              # the one minion release happens once HP <= this (late phase 2)
const MINION_DROP_GATE := 20.0            # Gentle: a minion out longer than this (or unreachable) no longer holds drops back
const T_PHASE_SHRIEK := 2.0
const T_FAN_TELE := [1.4, 1.2, 1.1]       # web fan warning
const T_TRIP_TELE := [1.4, 1.2, 1.1]      # trip-lines form (harmless) for this long
const T_POUNCE_TELE := [1.6, 1.4, 1.3]    # phase 3: the delayed pounce's mark
const T_COMBO_GAP := [1.2, 0.8, 0.7]      # phase 3: beat between the ground hazard and the pounce mark
const T_RECOVER := [1.8, 1.4, 1.2]        # after each major action (fan, trip-lines, release, channel)
const T_RELEASE := 1.0
const T_CHANNEL := [5.0, 4.0, 3.6]
const CHANNEL_CD := [14.0, 11.0, 10.0]
const CHANNEL_FIRST_DELAY := 3.0          # first channel no sooner than this after phase 3 starts
const CHANNEL_LIGHT_DIST := [3.6, 3.0, 2.8]
const BRAZIER_COOLDOWN := [9.0, 11.0, 12.0]
const SAC_WARN := [3.6, 3.0, 2.8]
const MINION_SPEED := [0.75, 1.0, 1.0]
const MINION_DAMAGE := [0.8, 1.0, 1.0]
const REPOSITION_CHANCE := [0.3, 0.45, 0.6]
const P2_CYCLE := ["fan", "drop", "trips", "drop"]
const THREAD_BOTTOM := 1.55               # above the brazier's foot (just over the bowl)
## Settings "timing_assist" (comfort: "removes tight timing windows from ... boss mechanics"): every
## warning (drop / pounce mark, fan wedge, trip-lines forming, the combo beat, shaking sacs), every opening
## (stuck, scorched), every recovery beat and the smothering channel last this much longer. Off by
## default, so the tables above stay exact (and phase 1 stays the Chapter One fight).
const TIMING_ASSIST_MULT := 1.5
const HIGH_VIS_COLOR := Color("fff1c9")    # Settings "high_visibility_cues": bold cream outlines (shape, not colour)

var enemy_id: String = BOSS_ID
var boss_id: String = BOSS_ID
var mode: String = "story"
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
var phase: int = 1
var field: Node3D = null             # boss_hazards/hazard_field.gd
var trip_anchors: Array = []
var entrance := Vector3.ZERO
var has_entrance := false
var minion_id: String = "brood_skitter"
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
var _shadow_bold: MeshInstance3D = null     # high_visibility_cues outline of the drop / pounce mark
var _check_t: float = 0.0
var _away_t: float = 0.0
var _using_shade := false
var _defeat_started := false
var _gone := false
var _initialized := false
var _rng := RandomNumberGenerator.new()
var _phase_pending := false
var _combo := false
var _pounce := false
var _release_done := false
var _p2_step: int = 0
var _p3_step: int = 0
var _channel_cd: float = 0.0
var _channel_brazier: Node = null
var _brazier_burned: Dictionary = {}   # brazier instance id -> true once its anchor burned
var _retry := false                     # the encounter was reset once (explains the retry rule on re-entry)
var _exit_released := false             # _exit_tree released the encounter (only once)
var _kit_shown := false                 # phases 2-3: it has performed this phase's first action (see PACING)
var _banked: int = 0                    # scorches waiting for that first action to end (one lands per opening)
var _banked_fx: CPUParticles3D = null    # embers smouldering on it while a scorch is banked

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
	mode = "trial" if String(params.get("mode", mode)) == "trial" else "story"
	boss_id = String(params.get("boss_id", boss_id))
	minion_id = String(params.get("minion_id", minion_id))
	var e: Variant = params.get("entrance")
	if e is Vector3:
		entrance = e
		has_entrance = true
	trip_anchors.clear()
	var ta: Variant = params.get("trip_anchors", [])
	if ta is Array or ta is PackedVector3Array:
		for p in ta:
			if p is Vector3:
				trip_anchors.append(p)
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
			if b.has_signal("flared"):
				b.connect("flared", _on_brazier_flared.bind(b))
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
	if is_story() and GameState.get_flag("weaver_defeated"):
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
	_build_field()
	# Braziers that were already lit (persisted) have already burned their anchors.
	for b in braziers:
		if is_instance_valid(b) and b.has_method("is_lit") and b.is_lit():
			_burn_anchor_near((b as Node3D).global_position, false)
			_brazier_burned[(b as Node).get_instance_id()] = true
	# (Every anchor burned by pre-lit braziers: it clings to the deep crack instead - never index an empty list.)
	_anchor = anchors[0] if not anchors.is_empty() else _nearest_anchor(arena_center)
	global_transform = _ceiling_pose(_anchor, _player_pos())
	_enter("dormant")


func _build_field() -> void:
	if field != null and is_instance_valid(field):
		field.dismiss_minions()
		field.queue_free()
	var obstacles: Array = [[arena_center, HazardField.CENTRE_OBSTACLE]]
	var targets: Array = []
	for b in braziers:
		if b is Node3D and is_instance_valid(b) and (b as Node3D).is_inside_tree():
			var bp := (b as Node3D).global_position
			obstacles.append([bp, 0.6])
			targets.append(bp)
	field = HazardField.new()
	field.name = "HazardField"
	var p := {"center": arena_center, "radius": arena_radius, "floor_y": arena_center.y, "intensity": intensity(),
		"obstacles": obstacles, "minion_parent": get_parent(), "minion_id": minion_id, "alt": _arachno()}
	if has_entrance:
		p["entrance"] = entrance
	if trip_anchors.size() >= 2:
		p["posts"] = trip_anchors
	field.setup(p)
	field.boss = self
	field.route_targets = targets
	field.release_allowed = Callable(self, "_release_ok")
	add_child(field)


# --- Public API ------------------------------------------------------------------------------------

func is_story() -> bool:
	return mode != "trial"


func is_threatening() -> bool:
	return fight_started and not _gone and not _defeat_started


func is_vulnerable() -> bool:
	return state in VULNERABLE_STATES


func is_overhead() -> bool:
	return state in CEILING_STATES or state == "climb"


## Spec section 9: false while it is overhead / armoured, and for any helper (companion, anything that is
## not Krystal) standing outside the arena - companions never chip it from the ceiling or finish the
## encounter from outside (MP section 8). Krystal herself may always strike it while it is down: at the
## arena mouth a stunned Matron must never answer her blow with the "too tough right now" glance.
func can_be_hit_by(source: Node) -> bool:
	if _gone or _defeat_started or not is_vulnerable():
		return false
	if source == null or not is_instance_valid(source) or not (source is Node3D):
		return true
	if _is_krystal(source):
		return true
	return _flat((source as Node3D).global_position, arena_center) <= arena_radius + 1.0


static func _is_krystal(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player") and not n.is_in_group("companion")


func intensity() -> int:
	return intensity_override if intensity_override >= 0 else Combat.current_intensity()


## Phase for a health value: 1 above PHASE_AT[1], 2 above PHASE_AT[2], else 3.
static func phase_for(hp: float, max_hp: float) -> int:
	var r := hp / maxf(max_hp, 0.001)
	if r <= float(PHASE_AT[2]):
		return 3
	if r <= float(PHASE_AT[1]):
		return 2
	return 1


## HP at which the next phase begins (a blow that crosses it stops there), or 0 in the last phase.
func next_phase_hp() -> float:
	if phase >= PHASE_AT.size():
		return 0.0
	return float(health.max_hp) * float(PHASE_AT[phase])


## The most one stun window may take in the current phase (see PACING).
func window_cap() -> float:
	return float(health.max_hp) * (WINDOW_CAP if phase <= 1 else LATE_WINDOW_CAP)


## True while a brazier's scorch waits for this phase's first action to end (see PACING).
func scorch_banked() -> bool:
	return _banked > 0


func get_aim_point() -> Vector3:
	if state in GROUND_STATES:
		return global_position + Vector3.UP * (1.4 if _using_shade else 0.9)
	return global_position + global_transform.basis.y * 1.2


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func slam_damage() -> float:
	return float(data.get("damage", 20.0)) * Combat.intensity_damage_mult(intensity())


## Hits while it is not stunned glance off its hide. The hint is Krystal's (a companion's refused blow only
## sparks - it must not teach her a rule she did not trigger).
func on_hit_blocked(attacker: Node, _dir: Vector3) -> void:
	if _gone or _defeat_started:
		return
	HitFx.spark(get_aim_point())
	Audio.play_3d("hit_soft", get_aim_point(), -2.0, 0.2)
	if attacker == null or not is_instance_valid(attacker) or _is_krystal(attacker):
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


## Freed mid-fight without an area change (e.g. a scripted removal, a trial torn down): nothing else would
## ever release the encounter, so Game.boss_active() would stay true (no saving, no travel). Release it once:
## hide the bar and end the encounter; minions it released leave with it (no drops, no kill events).
func _exit_tree() -> void:
	if not fight_started or _gone or _exit_released:
		return
	_exit_released = true
	Events.boss_health_changed.emit(boss_id, -1.0, float(health.max_hp) if health != null else 1.0)
	Events.boss_encounter_changed.emit(boss_id, false)
	if field != null and is_instance_valid(field):
		for m in field.minions:
			if is_instance_valid(m) and not (m as Node).is_queued_for_deletion():
				(m as Node).queue_free()


func tick(delta: float) -> void:
	if _gone:
		return
	if _defeat_started:
		if field != null:
			field.tick(delta, null)      # the hazards cleared at the defeat fade out during the retreat
		return
	state_time += delta
	_check_t -= delta
	var check := _check_t <= 0.0
	if check:
		_check_t = 0.2
	var p := _player()
	if fight_started:
		_channel_cd = maxf(_channel_cd - delta, 0.0)
	if field != null:
		field.intensity = intensity()
		field.tick(delta, p if p != null and fight_started and _hunt_allowed(p) else null)
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
				_choose_action()
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
		"snap_fall":
			var k := clampf(state_time / _state_len, 0.0, 1.0)
			global_transform = _lerp_xform(_from, _to, k * k)
			if k >= 1.0:
				_land_snapped()
		"climb":
			var k := clampf(state_time / _state_len, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			global_transform = _lerp_xform(_from, _to, e)
			if k >= 1.0:
				_enter_cling(-1.0)
		"recover", "phase_shriek", "release", "trip_tele":
			_face_player_on_ceiling(delta)
			if state_time >= _state_len:
				if state == "recover" or state == "phase_shriek":
					_enter_cling(-1.0)
				else:
					_finish_action()
		"fan_tele":
			_face_player_on_ceiling(delta)
			if state_time >= _state_len:
				if _combo:
					_enter("combo_gap", _t(float(T_COMBO_GAP[_i()])))
				else:
					_finish_action()
		"combo_gap":
			_face_player_on_ceiling(delta)
			if state_time >= _state_len:
				if field != null and field.sacs_pending():
					_combo = false
					_finish_action()
				else:
					_begin_telegraph(true)
		"channel":
			_tick_channel(p)


func _i() -> int:
	return clampi(intensity(), 0, 2)


## A warning / opening / recovery / channel length after Settings "timing_assist" (x TIMING_ASSIST_MULT).
func _t(base: float) -> float:
	return base * TIMING_ASSIST_MULT if bool(Settings.get_value("timing_assist")) else base


func _enter(s: String, length: float = 0.0) -> void:
	if state == "channel" and s != "channel":
		_release_channel()
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
		var rich := visual.has_method("supports_state")
		match s:
			"reposition", "climb":
				vs = "move"
			"telegraph":
				vs = "telegraph"
			"fan_tele", "trip_tele":
				vs = "spit" if rich and bool(visual.call("supports_state", "spit")) else "telegraph"
			"channel":
				vs = "channel" if rich and bool(visual.call("supports_state", "channel")) else "telegraph"
			"drop":
				vs = "lunge"
			"stuck", "scorched", "scorch_fall", "snap_fall":
				vs = "stunned"
			"intro", "defeat", "phase_shriek", "release":
				vs = "shriek"
			"rebound":
				vs = "recoil"
		visual.set_state(vs, length)
	if visual != null and visual.has_method("set_clinging"):
		visual.set_clinging(s in CEILING_STATES)


func start_fight() -> void:
	if fight_started or _gone:
		return
	fight_started = true
	_debug_phase_jump()
	_emit_health()
	Events.boss_encounter_changed.emit(boss_id, true)
	Events.boss_phase_changed.emit(boss_id, phase)
	if field != null:
		field.cap = HazardField.cap_for(maxi(phase, 2), _i())
	Audio.request_music("boss_matron", "music_boss", 2.0)
	Audio.play_3d(_snd("shriek"), global_position, -4.0, 0.03, 60.0)
	Events.caption.emit(_caption("intro"))
	Events.hint.emit("boss_braziers", "Light the braziers with {interact} to burn it off the ceiling. Your Lantern can kindle them.")
	if _retry and is_story():
		Events.hint.emit("boss_retry", "It still bears its wounds, and burned anchors stay burned, while you stay in the Below. Leaving the Below lets it recover fully.")
	_notice_companions()
	if state == "dormant":
		_enter("intro", T_INTRO)


## QA only (cheats): --matron-phase=2|3 starts the fight at that phase (for screenshots / real-input runs).
func _debug_phase_jump() -> void:
	if phase != 1 or not Debug.is_cheat_allowed() or not Debug.has_arg("matron-phase"):
		return
	var n := clampi(int(Debug.arg("matron-phase", "1")), 1, 3)
	if n <= 1:
		return
	health.set_hp(floorf(health.max_hp * float(PHASE_AT[n - 1])) - 1.0)
	_set_phase(n)


func _enter_cling(length: float) -> void:
	if _phase_pending:
		_phase_pending = false
		_enter("phase_shriek", T_PHASE_SHRIEK)
		return
	if _banked > 0 and _kit_shown:
		_fire_banked_scorch()        # a second light kept during the introduction (see _bank_scorch)
		return
	var r: Array = T_CLING[clampi(intensity(), 0, 2)]
	var l := length if length >= 0.0 else _rng.randf_range(float(r[0]), float(r[1]))
	if length < 0.0:
		_just_repositioned = false
	_enter("cling", l)


func _enter_recover() -> void:
	_combo = false
	_enter("recover", _t(float(T_RECOVER[_i()])))


## A major action (fan, trip-lines, release, channel) ended: normally a recovery beat. In phases 2-3 the
## first one also completes the phase's introduction - a scorch banked meanwhile lands now instead.
func _finish_action() -> void:
	_mark_kit_shown()
	if _banked > 0:
		_fire_banked_scorch()
		return
	_enter_recover()


func _mark_kit_shown() -> void:
	if phase >= 2:
		_kit_shown = true


## What it does when a cling ends (Krystal inside the arena, allowed to be hunted).
func _choose_action() -> void:
	match phase:
		1:
			# Chapter One behaviour, unchanged.
			if anchors.size() > 1 and not _just_repositioned and _rng.randf() < 0.45:
				_begin_reposition()
			else:
				_begin_telegraph()
		2:
			_choose_phase2()
		_:
			_choose_phase3()


func _choose_phase2() -> void:
	if _sacs_due():
		_begin_release()
		return
	var act: String = P2_CYCLE[_p2_step % P2_CYCLE.size()]
	if act == "trips" and not _can_trip():
		act = "drop"
	if act == "drop" and not _drop_allowed():
		act = "fan"
	if act == "drop" and anchors.size() > 1 and not _just_repositioned and _rng.randf() < float(REPOSITION_CHANCE[_i()]):
		_begin_reposition()
		return
	_p2_step += 1
	match act:
		"fan":
			_begin_fan(false)
		"trips":
			_begin_trips()
		_:
			_begin_telegraph()


func _choose_phase3() -> void:
	if _channel_cd <= 0.0:
		var b := _pick_channel_brazier()
		if b != null:
			_begin_channel(b)
			return
	if anchors.size() > 1 and not _just_repositioned and _rng.randf() < float(REPOSITION_CHANCE[_i()]):
		_begin_reposition()
		return
	_p3_step += 1
	if _i() == 0 and _p3_step % 2 == 0 and _drop_allowed():
		_begin_telegraph()          # Gentle: every other action is a plain drop (less overlap)
		return
	_begin_fan(_drop_allowed())


## No drop/pounce while a sac is still shaking (a release never overlaps the main pounce); on Gentle
## also not while its minion is alive - as long as it is fresh (<= MINION_DROP_GATE s) and reachable, so a
## minion stuck on a ledge or left alone never freezes the fight into fans only.
func _drop_allowed() -> bool:
	if field == null:
		return true
	if field.sacs_pending():
		return false
	if _i() == 0 and field.blocking_minions(MINION_DROP_GATE) > 0:
		return false
	return true


func _release_ok() -> bool:
	return not (state in ["telegraph", "drop", "combo_gap"])


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


## The drop telegraph (phase 1-2), or the phase-3 DELAYED pounce (`pounce`: a longer mark).
func _begin_telegraph(pounce: bool = false) -> void:
	_pounce = pounce
	_combo = false
	var p := _player_pos()
	var t := Vector3(p.x, _floor_y, p.z)
	var off := Vector2(t.x - arena_center.x, t.z - arena_center.z)
	if off.length() > arena_radius - 1.5:
		off = off.normalized() * maxf(arena_radius - 1.5, 1.0)
		t = Vector3(arena_center.x + off.x, _floor_y, arena_center.z + off.y)
	_drop_target = _ground_at(t)
	var tlen: float = _t(float(T_POUNCE_TELE[_i()]) if pounce else float(T_TELEGRAPH[clampi(intensity(), 0, 2)]))
	_enter("telegraph", tlen)
	_show_shadow(true)
	Audio.play_3d(_snd("rattle"), global_position, 0.0, 0.05, 50.0)
	Events.caption.emit(_caption("pounce" if pounce else "rattle"))


func _begin_drop() -> void:
	_from = global_transform
	_to = _ground_pose(_drop_target, _player_pos())
	_enter("drop", float(T_DROP[clampi(intensity(), 0, 2)]))


func _slam() -> void:
	global_transform = _to
	_show_shadow(false)
	_pounce = false
	# Phases 2-3: a landed drop / pounce completes the phase's introduction; a banked scorch catches it now.
	_mark_kit_shown()
	if _banked > 0:
		_take_banked_scorch()
		_pending_scorch = true
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
		var land := scorch_landing(global_position)
		if _flat(land, global_position) > 0.3:
			# Scorched on the way down onto a brazier (or right beside the cocoon): it recoils clear
			# before collapsing, like any other scorched fall.
			_from = global_transform
			_to = _ground_pose(_ground_at(land), _player_pos())
			_enter("scorch_fall", T_SCORCH_FALL)
		else:
			_land_scorched()
	elif hit:
		_enter("rebound", T_REBOUND)
	else:
		_enter("stuck", _t(float(T_STUCK[clampi(intensity(), 0, 2)])))
		Events.hint.emit("boss_stuck", "It's stuck! Strike now with {attack}!")


func _begin_climb() -> void:
	var target := _nearest_anchor(global_position)
	_from = global_transform
	_to = _ceiling_pose(target, _player_pos())
	_anchor = target
	_enter("climb", float(T_CLIMB[clampi(intensity(), 0, 2)]))
	Audio.play_3d(_snd("skitter"), global_position, -2.0, 0.1, 40.0)


func _land_scorched() -> void:
	# Re-ground on the real floor under it (the same point scorch_fall aimed at), never a raw floor
	# height that could sit inside a collider such as the Heartseed cocoon.
	global_transform = _ground_pose(_ground_at(Vector3(global_position.x, _floor_y, global_position.z)), _player_pos())
	HitFx.burst(global_position + Vector3.UP * 0.3, Color(0.72, 0.68, 0.76), 16, 3.5, 1.4, -9.0, 0.6)
	Audio.play_3d(_snd("drop"), global_position, 0.0, 0.05, 50.0)
	Events.camera_shake.emit(0.5, 0.3)
	_enter("scorched", _t(float(T_SCORCHED[clampi(intensity(), 0, 2)])))
	Events.hint.emit("boss_scorched", "The light burned it off the ceiling! Strike while it's stunned!")


## The channel thread snapped under it: down on the floor, stuck (an ordinary opening).
func _land_snapped() -> void:
	global_transform = _ground_pose(_ground_at(Vector3(global_position.x, _floor_y, global_position.z)), _player_pos())
	HitFx.burst(global_position + Vector3.UP * 0.3, Color(0.72, 0.68, 0.76), 14, 3.2, 1.3, -9.0, 0.6)
	Audio.play_3d(_snd("drop"), global_position, -1.0, 0.05, 50.0)
	Events.camera_shake.emit(0.4, 0.25)
	if _pending_scorch:
		_pending_scorch = false
		_enter("scorched", _t(float(T_SCORCHED[_i()])))
		return
	_enter("stuck", _t(float(T_STUCK[_i()])))
	Events.hint.emit("boss_snapped", "It lost its grip! Strike now with {attack}!")


# --- Phase 2: fans, trip-lines, the release -----------------------------------------------------------

func _begin_fan(combo: bool) -> void:
	_combo = combo
	var tele := _t(float(T_FAN_TELE[_i()]))
	if field != null:
		field.begin_fan(Vector3(global_position.x, _floor_y, global_position.z), _player_pos(), tele)
	_enter("fan_tele", tele)
	Audio.play_3d(_snd("skitter"), global_position, -2.0, 0.1, 45.0)
	Events.caption.emit(_caption("fan"))
	Events.hint.emit("boss_fan", "A pale wedge marks where it will spin a web sheet. Step out of the wedge - the sheet only slows you." if not _using_shade
		else "A pale wedge marks where the veil will drift down. Step out of the wedge - the veil only slows you.")


func _can_trip() -> bool:
	return field != null and field.count_kind("trip") < int(HazardField.TRIP_PER_CAST[_i()])


func _begin_trips() -> void:
	var tele := _t(float(T_TRIP_TELE[_i()]))
	var lines: Array = []
	if field != null:
		lines = field.begin_trips(int(HazardField.TRIP_PER_CAST[_i()]), tele, _player_pos())
	if lines.is_empty():
		if _drop_allowed():
			_begin_telegraph()
		else:
			_begin_fan(false)
		return
	_enter("trip_tele", tele)
	Audio.play_3d(_snd("skitter"), global_position, -3.0, 0.1, 45.0)
	Events.caption.emit(_caption("trips"))
	Events.hint.emit("boss_tripline", "Trip-lines snap when you walk into them. Cut them with {attack}, burn them with your lit lantern, or jump over.")


func _sacs_due() -> bool:
	return phase == 2 and not _release_done and fight_started and field != null \
		and health.hp <= health.max_hp * LATE_PHASE2_AT


func _begin_release() -> void:
	_release_done = true
	var n := int(HazardField.MINION_CAP[_i()])
	field.minion_cap = n
	field.minion_params = {"damage_scale": float(MINION_DAMAGE[_i()]), "speed_scale": float(MINION_SPEED[_i()])}
	field.begin_sacs(n, _t(float(SAC_WARN[_i()])), _player_pos())
	_enter("release", T_RELEASE)
	Audio.play_3d(_snd("shriek"), global_position, -8.0, 0.1, 50.0)
	Events.caption.emit(_caption("sacs"))
	Events.hint.emit("boss_sacs", "Something is about to hatch at the edge of the chamber. Pop the shaking sacs with {attack}, or get ready." if not _using_shade
		else "Pale pods at the edge of the chamber are about to split. Pop them with {attack}, or get ready.")


# --- Phase 3: reusable braziers and the channel ------------------------------------------------------------

## The lit brazier farthest from Krystal (not one she is standing at or stoking), or null.
func _pick_channel_brazier() -> Node:
	var p := _player_pos()
	var best: Node = null
	var best_d := -1.0
	for b in braziers:
		if not (b is Node3D) or not is_instance_valid(b) or not (b as Node3D).is_inside_tree():
			continue
		if not b.has_method("is_lit") or not bool(b.is_lit()):
			continue
		if b.has_method("is_kindling") and bool(b.is_kindling()):
			continue
		var d := _flat((b as Node3D).global_position, p)
		if d <= float(CHANNEL_LIGHT_DIST[_i()]) + 1.0:
			continue
		if d > best_d:
			best_d = d
			best = b
	return best


func _begin_channel(b: Node) -> void:
	_channel_brazier = b
	var th: Node3D = field.begin_thread(_thread_top(), _thread_bottom()) if field != null else null
	if th != null and th.has_signal("snapped"):
		th.connect("snapped", _on_thread_snapped)
	_enter("channel", _t(float(T_CHANNEL[_i()])))
	Audio.play_3d(_snd("skitter"), global_position, -1.0, 0.05, 50.0)
	Events.caption.emit(_caption("channel"))
	Events.hint.emit("boss_channel", "It is smothering a brazier! Strike the glowing knot on its thread with {attack}, or bring your lit lantern close." if not _using_shade
		else "It is smothering a brazier! Strike the glowing knot on its tether with {attack}, or bring your lit lantern close.")


func _tick_channel(p: Node3D) -> void:
	var b := _channel_brazier
	if b == null or not is_instance_valid(b) or not bool(b.is_lit()):
		_channel_cd = float(CHANNEL_CD[_i()]) * 0.5
		_finish_action()
		return
	var bp := (b as Node3D).global_position
	global_transform = _lerp_xform(global_transform, _ceiling_pose(_anchor, bp), 0.1)
	var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
	b.set_dim(k)
	if field != null and field.thread != null and is_instance_valid(field.thread):
		field.thread.set_ends(_thread_top(), _thread_bottom())
	if p != null and _hunt_allowed(p) and _has_light(p) and _flat(p.global_position, bp) <= float(CHANNEL_LIGHT_DIST[_i()]):
		_interrupt_channel("light")
		return
	if state_time >= _state_len:
		_complete_channel()


func _on_thread_snapped(_source: Node) -> void:
	if state == "channel":
		_interrupt_channel("thread")


## Interrupted (thread struck / lantern light): it loses its grip and falls - an opening.
func _interrupt_channel(_how: String) -> void:
	_channel_cd = float(CHANNEL_CD[_i()])
	_release_channel()
	Audio.play_3d(_snd("shriek"), global_position, -3.0, 0.05, 60.0)
	Events.caption.emit(_caption("snap"))
	_from = global_transform
	var land := scorch_landing(global_position)
	_to = _ground_pose(_ground_at(land), _player_pos())
	_enter("snap_fall", T_SCORCH_FALL)
	# The channel was this phase's first action: a banked scorch turns the snapped fall into a scorch.
	_mark_kit_shown()
	if _banked > 0:
		_take_banked_scorch()
		_pending_scorch = true


func _complete_channel() -> void:
	var b := _channel_brazier
	_channel_cd = float(CHANNEL_CD[_i()])
	_release_channel()
	if b != null and is_instance_valid(b) and bool(b.is_lit()) and b.has_method("extinguish"):
		b.extinguish(float(BRAZIER_COOLDOWN[_i()]))
	Events.hint.emit("boss_smothered", "A smothered brazier smoulders for a while - then you can light it again.")
	_finish_action()


func _release_channel() -> void:
	if field != null:
		field.end_thread()
	if _channel_brazier != null and is_instance_valid(_channel_brazier) and _channel_brazier.has_method("set_dim"):
		_channel_brazier.set_dim(0.0)
	_channel_brazier = null


func _thread_top() -> Vector3:
	return global_position + global_transform.basis.y * 1.0


func _thread_bottom() -> Vector3:
	if _channel_brazier is Node3D and is_instance_valid(_channel_brazier):
		return (_channel_brazier as Node3D).global_position + Vector3.UP * THREAD_BOTTOM
	return Vector3(global_position.x, _floor_y + THREAD_BOTTOM, global_position.z)


func _has_light(p: Node) -> bool:
	var v: Variant = p.get("lantern_on")
	return v is bool and v


# --- Phases -----------------------------------------------------------------------------------------------

func _set_phase(np: int) -> void:
	if np <= phase:
		return
	phase = np
	_kit_shown = false            # PACING: the new phase shows its first action before a scorch lands
	_release_channel()
	_combo = false
	if field != null:
		field.clear_all(true)
		field.cap = HazardField.cap_for(np, _i())
		if np >= 3:
			field.dismiss_minions()
	if np >= 3:
		_channel_cd = CHANNEL_FIRST_DELAY
		for b in braziers:
			if is_instance_valid(b) and b.has_method("set_reusable"):
				b.set_reusable(true, float(BRAZIER_COOLDOWN[_i()]))
	Events.boss_phase_changed.emit(boss_id, np)
	phase_changed.emit(np)
	Events.caption.emit(_caption("phase%d" % np))
	if np == 2:
		Events.hint.emit("boss_phase2", "The floor is turning to web! Step out of the pale wedges, and cut or burn the trip-lines." if not _using_shade
			else "Pale veils are drifting down! Step out of the pale wedges, and cut or burn the root lines.")
	elif np == 3:
		Events.hint.emit("boss_phase3", "Braziers can now be stoked again once their ring glows. Don't let it smother one!")


# --- Braziers ---------------------------------------------------------------------------------------------

func _on_brazier_lit(brazier: Node) -> void:
	_brazier_scorch(brazier, true)


## Phase 3: a reusable brazier was stoked again - another scorch (its anchor burned long ago).
func _on_brazier_flared(brazier: Node) -> void:
	_brazier_scorch(brazier, false)


func _brazier_scorch(brazier: Node, burn: bool) -> void:
	if _gone or _defeat_started:
		return
	var bpos := global_position
	if brazier is Node3D and is_instance_valid(brazier):
		bpos = (brazier as Node3D).global_position
	var bid := brazier.get_instance_id() if brazier != null and is_instance_valid(brazier) else 0
	if burn and not _brazier_burned.has(bid):
		_brazier_burned[bid] = true
		_burn_anchor_near(bpos, true)
	if not fight_started:
		var p := _player()
		if p != null and not _hunt_allowed(p):
			# Lit while Krystal is down, loading or in a cutscene (e.g. a kindle finishing on the death
			# screen): the anchor stays burned (the kinder retry), but nothing re-engages - no shriek,
			# scorch fall, boss bar or music - until she walks back in. Never hang from a burned anchor.
			if state == "dormant" and burned.has(_anchor):
				_anchor = _nearest_anchor(global_position)
				global_transform = _ceiling_pose(_anchor, _player_pos())
			return
		start_fight()
	if _scorch_gated():
		_bank_scorch()
		return
	Audio.play_3d(_snd("shriek"), global_position, -3.0, 0.05, 60.0)
	Events.caption.emit(_caption("scorch"))
	_apply_scorch()


## PACING: phases 2-3 show their kit before the light can bring it down - a scorch that arrives while it is
## overhead (not mid-drop: a landing drop completes the introduction anyway) before that is banked.
func _scorch_gated() -> bool:
	return phase >= 2 and not _kit_shown and is_overhead() and state != "drop"


## The anchor already burned (the light counts); it shrieks and clings on, smouldering, and the scorch
## lands when this phase's first action ends (_finish_action / _slam / _interrupt_channel). A second light
## meanwhile is kept too: it lands at the next cling after the first scorch window (_enter_cling).
func _bank_scorch() -> void:
	_banked += 1
	Audio.play_3d(_snd("shriek"), global_position, -5.0, 0.05, 60.0)
	Events.caption.emit(_caption("banked"))
	Events.hint.emit("boss_banked", "It clings on through the heat! Watch what it does next - the light will still bring it down.")
	HitFx.burst(get_aim_point(), Color("ffb35c"), 16, 2.6, 1.1, 1.5, 0.8, 120.0)
	_set_banked_fx(true)


## Consumes a banked scorch (the caller brings it down): the embers go out, the scorch shriek and caption play.
func _take_banked_scorch() -> void:
	_banked = maxi(_banked - 1, 0)
	if _banked == 0:
		_set_banked_fx(false)
	Audio.play_3d(_snd("shriek"), global_position, -3.0, 0.05, 60.0)
	Events.caption.emit(_caption("scorch"))


func _fire_banked_scorch() -> void:
	_take_banked_scorch()
	_combo = false
	_apply_scorch()


## Brings it down scorched from wherever it is (the light reached it).
func _apply_scorch() -> void:
	match state:
		"stuck", "scorched", "rebound":
			_enter("scorched", _t(float(T_SCORCHED[clampi(intensity(), 0, 2)])))
		"drop", "snap_fall":
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
## never closer than CENTRE_CLEARANCE to the centre (the Heartseed cocoon sits there: a fall from a
## centre anchor or a ceiling route over it is pushed straight out, toward Krystal if dead centre).
func scorch_landing(from: Vector3) -> Vector3:
	var p := Vector3(from.x, _floor_y, from.z)
	var off := Vector2(p.x - arena_center.x, p.z - arena_center.z)
	if off.length() < CENTRE_CLEARANCE:
		var dir := Vector2(0.0, 1.0)
		if off.length() > 0.05:
			dir = off / off.length()
		else:
			var pp := _player_pos()
			var to_p := Vector2(pp.x - arena_center.x, pp.z - arena_center.z)
			if to_p.length() > 0.05:
				dir = to_p / to_p.length()
		p.x = arena_center.x + dir.x * CENTRE_CLEARANCE
		p.z = arena_center.z + dir.y * CENTRE_CLEARANCE
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
	var max_r := maxf(arena_radius - 1.5, CENTRE_CLEARANCE)
	var r := Vector2(p.x - arena_center.x, p.z - arena_center.z)
	if r.length() > max_r:
		r = r / r.length() * max_r
		p.x = arena_center.x + r.x
		p.z = arena_center.z + r.y
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
	var before: float = health.hp + amount      # apply_damage already took the blow (before its death test)
	var shown := amount
	var crossed := false
	# PACING: a blow that crosses the next phase threshold stops exactly on it (set here, inside
	# apply_damage, before its death test), so one opening never carries it across two thresholds and every
	# phase starts with its whole band. Only a blow that started above the threshold is clamped.
	var th := next_phase_hp()
	if th > 0.0 and health.hp < th and before > th + 0.001:
		shown = before - th
		crossed = true
	# PACING (QA: one phase-2 window took 54 of its 36 hp): the blow that would overshoot this window's cap is
	# trimmed to the room left - checked BEFORE the window-end test, the excess goes back to health before
	# apply_damage's death test (the count_velour / quarry_warden technique), so a window never takes more than
	# window_cap(). Exception (lead decision, like Count Velour): a blow that would finish her in her last phase
	# goes through - a boss escaping at a sliver of health to the ceiling feels unfair.
	var finishing := before - shown <= 0.0      # after the threshold clamp: only a blow that really ends the fight
	if state in VULNERABLE_STATES and not finishing:
		var room := maxf(window_cap() - _window_damage, 0.0)
		if shown > room:
			shown = room
			crossed = crossed and before - shown <= th + 0.001
	if shown < amount:
		health.hp = before - shown
	HitFx.flash(self)
	HitFx.number(get_aim_point() + Vector3.UP * 0.8, shown)
	Audio.play_3d("enemy_hurt", get_aim_point(), -2.0, 0.1)
	if health.dead:
		return
	if health.hp <= 0.0:
		return        # the killing blow: `died` follows right after (no climb/shriek first)
	_window_damage += shown
	var np := phase_for(health.hp, health.max_hp)
	if crossed:
		np = maxi(np, phase + 1)
	if np > phase:
		# Phase threshold: the window ends at once - it shrieks, climbs, and the new phase begins up there.
		_set_phase(np)
		Audio.play_3d(_snd("shriek"), global_position, -4.0, 0.05, 60.0)
		_phase_pending = true
		if state in VULNERABLE_STATES or state == "rebound":
			_begin_climb()
		return
	if state in VULNERABLE_STATES and _window_damage >= window_cap() - 0.001:
		Audio.play_3d(_snd("shriek"), global_position, -6.0, 0.1, 50.0)
		_begin_climb()


func _on_health_changed(_hp: float, _max_hp: float) -> void:
	if fight_started:
		_emit_health()


func _emit_health() -> void:
	Events.boss_health_changed.emit(boss_id, health.hp, health.max_hp)


func _on_died() -> void:
	_begin_defeat()


func _begin_defeat() -> void:
	if _defeat_started or _gone:
		return
	_defeat_started = true
	state = "defeat"
	health.invulnerable = true
	_show_shadow(false)
	_banked = 0
	_set_banked_fx(false)
	_release_channel()
	if field != null:
		field.clear_all(true)
		field.dismiss_minions()
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
	if field != null:
		field.clear_all(false)      # anything still fading is gone with her (no frozen leftovers)
		field.dismiss_minions()
	Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
	Events.boss_encounter_changed.emit(boss_id, false)
	if is_story():
		GameState.set_flag("weaver_defeated", true)
		Events.boss_defeated.emit(boss_id)
	defeated.emit()
	Audio.release_music("boss_matron", 4.0)
	if is_story():
		ensure_heartseed(get_parent() if get_parent() != null else self, arena_center)
	state_changed.emit("gone")


func _on_player_died() -> void:
	reset_fight()


## Clean reset (Krystal fell, or walked out of the chamber): back up on a remaining anchor, dormant,
## bar hidden, every hazard / sac / thread gone, minions scattered, channel cancelled. Its wounds, the
## phase, lit braziers and burned anchors are kept on purpose (see RESET POLICY above).
func reset_fight() -> void:
	if _gone or _defeat_started or not _initialized:
		return
	_pending_scorch = false
	_phase_pending = false
	_banked = 0
	_set_banked_fx(false)
	_combo = false
	_pounce = false
	_release_done = false
	_p2_step = 0
	_p3_step = 0
	_away_t = 0.0
	_release_channel()
	if phase >= 3:
		_channel_cd = CHANNEL_FIRST_DELAY
	if field != null:
		field.clear_all(false)
		field.dismiss_minions()
	_show_shadow(false)
	_anchor = _nearest_anchor(global_position)
	global_transform = _ceiling_pose(_anchor, _player_pos())
	if fight_started:
		fight_started = false
		_retry = true
		Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
		Events.boss_encounter_changed.emit(boss_id, false)
		Audio.release_music("boss_matron", 3.0)
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
	if not (b is Node) or not is_instance_valid(b):
		return
	for sig in ["lit", "flared"]:
		if (b as Node).has_signal(sig):
			for con in (b as Node).get_signal_connection_list(sig):
				var cb: Callable = con["callable"]
				if cb.get_object() == self:
					(b as Node).disconnect(sig, cb)


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
	if key == "high_visibility_cues":
		if _shadow_bold != null:
			_shadow_bold.visible = bool(Settings.get_value("high_visibility_cues"))
		return
	if key != "arachnophobia" or _gone or _using_shade == _arachno():
		return
	_build_visual()
	# Re-seat on the ceiling with the new body's hanging offset; timers are left untouched.
	if state in CEILING_STATES and state != "reposition":
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
	# Settings "high_visibility_cues": a bold cream outline just outside the red ring - the mark reads by
	# shape and brightness, never by colour alone (toggled live in _on_settings_changed).
	_shadow_bold = Kit.torus(1.04, 1.16, Mat.glow(HIGH_VIS_COLOR, 1.3))
	_shadow_bold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_shadow, _shadow_bold, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	_shadow_bold.visible = bool(Settings.get_value("high_visibility_cues"))
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
		# The phase-3 pounce pulses twice as slowly at first (a "delayed" read), then quickens.
		var rate := (6.0 + 16.0 * k) if _pounce else (10.0 + 14.0 * k)
		var pulse := 0.5 + 0.5 * sin(state_time * rate)
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


## Warm embers smouldering on it while a scorch is banked (PACING): "the light has it - it just hasn't let
## go yet". Built on first use; soft, slow and steady (no flashing).
func _set_banked_fx(on: bool) -> void:
	if not on:
		if _banked_fx != null and is_instance_valid(_banked_fx):
			_banked_fx.emitting = false
		return
	if _banked_fx == null or not is_instance_valid(_banked_fx):
		_banked_fx = CPUParticles3D.new()
		_banked_fx.name = "BankedEmbers"
		var m := SphereMesh.new()
		m.radius = 0.05
		m.height = 0.1
		m.radial_segments = 6
		m.rings = 3
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = Color("ffb35c")
		m.material = pm
		_banked_fx.mesh = m
		_banked_fx.amount = 14
		_banked_fx.lifetime = 1.3
		_banked_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_banked_fx.emission_sphere_radius = 0.9
		_banked_fx.gravity = Vector3(0, 1.2, 0)
		_banked_fx.initial_velocity_min = 0.1
		_banked_fx.initial_velocity_max = 0.4
		_banked_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_banked_fx.position = Vector3(0, 1.0, 0)
		add_child(_banked_fx)
	_banked_fx.emitting = true


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
		"pounce":
			return "[a slow, gathering whisper overhead]" if shade else "[a slow, deliberate rattle overhead]"
		"scorch":
			return "[it wails as the light burns it]" if shade else "[it shrieks as the light scorches it]"
		"banked":
			return "[it wails, smouldering, but holds on]" if shade else "[it shrieks, smouldering, but clings on]"
		"defeat":
			return "[the Hollow Mother wails and withdraws into the deep]" if shade else "[the Weaver shrieks and flees into the deep]"
		"fan":
			return "[a pale veil drifts down]" if shade else "[silk hisses down from above]"
		"trips":
			return "[pale roots creep taut across the floor]" if shade else "[threads twang taut across the floor]"
		"sacs":
			return "[pale pods along the wall begin to tremble]" if shade else "[egg sacs along the wall begin to shake]"
		"channel":
			return "[a pale tether sinks toward a brazier]" if shade else "[a thread lowers toward a brazier]"
		"snap":
			return "[the tether snaps - she loses her hold]" if shade else "[the thread snaps - it loses its grip]"
		"phase2":
			return "[the Hollow Mother wails; pale veils stir]" if shade else "[the Matron shrieks; silk begins to fall]"
		"phase3":
			return "[the Hollow Mother's wail turns desperate]" if shade else "[the Matron's shriek turns desperate]"
	return ""
