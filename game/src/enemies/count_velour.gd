extends Node3D
## COUNT VELOUR - boss of the Count's Gallery in Moonveil Manor (MP 13.1; data/enemies.gd "count_velour";
## docs/CHAPTER_TWO_SPEC.md sections 9-10). A small floating bat-masked host in an oversized velvet cape
## (src/enemies/velour_visual.gd). Spawned by the manor area (moonveil_manor_world.gd _place_boss) with
##   setup({"arena_center": Vector3, "arena_radius": 12.0, "candles": [ward_candle nodes], "teach_candle": Node3D,
##          "curtains": [Marker3D], "fixture": Node3D, "cover": [Vector3], "helper_points": [Vector3],
##          "entry": Vector3, "area": Node, "no_drops": true})
## optional keys: "mode": "story" | "trial" (trial: never emits Events.boss_defeated), "auto_start": bool (default:
## true only without an "area" - the manor starts him itself once the teaching candle burns), "seed": int.
## In group "enemy" only while the encounter runs (dormant he is part of the Gallery's scenery).
## Public API: start_fight(), reset_fight(), is_threatening(), can_be_hit_by(source), get_aim_point(), is_vulnerable(),
## is_reachable(), phase_for(hp, max) (static); signals defeated, state_changed, phase_changed, drain_resolved(result),
## candle_darkened(candle). Tests: tick(delta) with process off, target_override, intensity_override, next_action,
## force_feint, fast_defeat.
##
## HEIGHT IS THE REACH TELL. He hovers at HOVER_Y (out of sword reach, a small shadow below him) and only comes
## down into reach in his WINDOWS - the only states in which he can be hurt (health.invulnerable + can_be_hit_by):
##   recoil (after a dash), drain wind-up / channel / rest, reform (after the bats), channel (phase C) and stagger.
## Every committed attack warns >= 1.0 s with a shape on the floor and a pose (the sound is optional: captions).
##
## PHASE A (100% .. 66%) "An invitation too close"
##   * BOW -> CAPE DASH: he bows and his SHADOW stretches along the coming lane (plus a red lane mark with an arrow;
##     it follows Krystal for 60% of the bow, then locks). He dashes along it (one hit at most, through her health:
##     i-frames -> armour -> shield) and RECOILS at the far end, dizzy and within reach: the attack window (shorter
##     if the dash hit her). Intense: once a dash has been seen, sometimes a FEINT - halfway through the bow he
##     flicks the cape open ("not yet"), then gives a SEPARATE FINAL TELL (his crown flashes, the lane re-shows and
##     re-aims) before the real dash - never shorter than 1.0 s, never invisible.
##   * DRAIN TETHER (after two dashes): he floats down and a thin ribbon links them (+ a ring under her): the
##     warning. Then the channel: a bright fill creeps from her to him; ONLY if it reaches him does the drain land -
##     one hit of data damage through her health, and he heals by what was dealt (x DRAIN_HEAL_MULT, never above his
##     current phase). It BREAKS (no damage, no heal, he is left dazed and reachable) if a wall / pillar / statue cuts
##     the line of sight, if she stands in a lit candle pool, if he is struck, or if she runs out of range.
## PHASE B (66% .. 33%) "The ballroom in flight"
##   * He disperses into bats (src/enemies/velour/bat_swarm.gd): one broad safe lane (dotted gold rings), bats sweep
##     the two other lanes (red arrows); her own lane sweeps last. Gentle: ONE pattern; Standard / Intense: two
##     patterns (the second across the other axis). Then the bats return: the TRUE bat wears his collar, gold ring
##     and crown and homes toward her; if it flies into a lit candle pool it is revealed early and he reforms right
##     there, dazzled, for a longer window (x1.25 damage); otherwise he reforms beside her for a normal window.
##     Dispersal is capped (MAX_DISPERSED s) - never invulnerable indefinitely. Dashes alternate with dispersals.
##   * At most ONE Velvet Wing helper at a time (data max_helpers; Gentle: one in total), summoned at a dispersal from
##     the arena's helper points; it never winds up while he commits to an attack (and he waits for it) - no overlap.
## PHASE C (33% .. 0) "Drop the borrowed mask"
##   * He flies to a lit ward candle and CHANNELS to darken it: stationary, low, in reach. Strike him while he
##     channels, or relight a dark candle with the Lantern (any time in this phase): the light STAGGERS him -
##     a generous window (x1.5 damage). If the channel completes the candle goes dark (relight it to stagger him).
##   * The borrowed mask holds: until light has staggered him once in this phase he cannot drop below MASK_FLOOR
##     (strong gear helps, but at least one real interaction with the candle rule is required).
## Phase changes: a theatrical twirl (invulnerable, TRANSITION s), everything in flight is cleared, the phase event
## fires (music layers). A single big hit never skips a phase (the health floor stops at the threshold). One window
## can take at most WINDOW_CAP of his health, then he whirls back up - no health sponge, no burst skip either.
##
## DEFEAT: the enchantment disperses (bats scatter, the borrowed mask falls and fades - no gore). The victory is
## COMMITTED FIRST: bar hidden, Events.boss_encounter_changed(false), Events.boss_defeated("count_velour") (the manor
## area sets ch2_velour_defeated and shows the freed resident, who says "A dreadful host. I did not even offer you a
## chair."), all before any presentation. Without an owning area (mode trial / tests) he says that line himself.
## Emitted exactly once.
##
## RESET POLICY (one rule): Krystal falls, or the area pauses the encounter (she left the Gallery): a CLEAN reset -
## bats, tether, marks, channel and the helper are removed, every arena candle returns to the state it had when the
## fight started (the arena's start state), bar hidden, music / director released, he waits (dormant). His wounds and
## phase are kept while the manor stays loaded (a kinder retry that can never mismatch: every prop is back to its
## start). Quitting / reloading: nothing is saved - a fresh encounter (full health, phase A, the arena's own start
## state). A won encounter is never reset (the flag is the arena's). Her fall arrives synchronously INSIDE his own
## hit (Game.on_player_died emits player_died from her Health): every caller of _deal() stops when the reset ran.
## Gentle: slower dash, longer warnings, easier tether (longer channel, bigger candle pools, shorter range, softer
## hits), one sweep pattern, one helper in total. Intense: a taught feint + separate final tell, less idle time -
## never shorter warnings, never invisible, never louder.
## Comfort: Settings "timing_assist" stretches every warning, channel, opening and recovery x TIMING_ASSIST_MULT;
## reduce_flashing keeps the tints / crown glint / tether steady; camera shakes go through Events.
## Sounds (existing names only): shade_drift, dodge, gloomling_flinch, shade_telegraph, shade_whisper,
## dir_wrong_squeak, checkpoint_light, brazier_light, lantern_off, stinger_soft, ward_restore, enemy_hurt, hit_soft.

signal defeated
signal state_changed(new_state: String)
signal phase_changed(phase: int)
signal drain_resolved(result: String)       # "complete" | "sight" | "candle" | "hit" | "range" | "target"
signal candle_darkened(candle: Node3D)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const VelourHealth := preload("res://src/enemies/velour/velour_health.gd")
const Visual := preload("res://src/enemies/velour_visual.gd")
const BatSwarm := preload("res://src/enemies/velour/bat_swarm.gd")
const Tether := preload("res://src/enemies/velour/drain_tether.gd")
const Fx := preload("res://src/enemies/velour/velour_fx.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const ManorLayout := preload("res://data/manor_layout.gd")

const BOSS_ID := "count_velour"
const HELPER_ID := "velvet_wing"
const HOLD_ID := "boss_count_velour"
const LINE_BATS := "The ballroom is in flight! Do mind the lanes, dear guest."
const LINE_CANDLES := "Enough manners. Let us dim the lights."
const LINE_DRAIN := "A small toll for the host. Do hold still."
const LINE_STAGGER := "Ah! Too bright, too bright!"

# Heights above the floor (the reach tell). Krystal's blade reaches aim points up to 0.9 + MAX_VERTICAL_REACH.
const HOVER_Y := 3.2
const BOW_Y := 2.9
const DASH_Y := 1.15
const RECOIL_Y := 1.3
const DRAIN_Y := 1.7
const CHANNEL_Y := 1.5
const STAGGER_Y := 1.0
const REFORM_Y := 1.3
const HEIGHT_SPEED := 3.4
const REACH_TOP := 2.5
# Geometry
const KEEP_DIST := 6.5
const ARENA_MARGIN := 2.0
const COVER_CLEAR := 1.6
const DASH_HALF_WIDTH := 0.8
const TARGET_BODY := 0.35
const DASH_HIT_DY := 1.4
const DASH_DESCENT := 0.35
const LANE_REFRESH := 0.1
const CHANNEL_OFFSET := 1.1
const CHANNEL_MAX_DIST := 14.0
const LEAVE_MARGIN := 6.0
const LEAVE_TIME := 4.0
# Rules
const PHASE_AT := [1.0, 0.66, 0.33]
const WINDOW_CAP := 0.16
const MASK_FLOOR := 0.08          # lifted by the first light stagger; a companion's blow on the channel counts too (kept: lead decision P16)
const STAGGER_MULT := 1.5
const REVEAL_MULT := 1.25
const DRAIN_HEAL_MULT := 2.0
const FEINT_CHANCE := 0.4
const FEINT_AT := 0.5
const BOW_TRACK := 0.6
const FINAL_TRACK := 0.4
const MAX_DISPERSED := 18.0
const DEFEAT_PRESENT := 1.4
const VULNERABLE := ["recoil", "drain_tele", "drain", "drain_rest", "reform", "channel", "channel_rest", "stagger"]
const COMMITTED := ["bow", "flourish", "final_tell", "dash", "drain_tele", "drain", "disperse", "bats", "channel_fly", "channel"]
const HELPER_BUSY := ["telegraph", "dash", "drain"]
# Timings per horror intensity: [Gentle, Standard, Intense]
const T_INTRO := 2.4
const T_GLIDE := [[2.6, 3.4], [1.7, 2.5], [1.1, 1.7]]
const GLIDE_SPEED := [2.6, 3.2, 3.6]
const T_BOW := [1.4, 1.2, 1.2]
const T_FLOURISH := 0.4
const T_FINAL_TELL := 1.0
const DASH_SPEED := [9.0, 13.0, 13.0]
const T_RECOIL := [3.0, 2.4, 2.2]
const T_RECOIL_HIT := [1.4, 1.0, 1.0]
const T_DRAIN_TELE := [1.9, 1.6, 1.6]
const T_DRAIN := [3.2, 2.5, 2.4]
const T_DRAIN_REST := [2.2, 1.6, 1.4]
const DRAIN_CD := [14.0, 11.0, 9.0]
const DRAIN_RANGE := [10.0, 12.0, 12.0]
const DRAIN_POOL_BONUS := [0.8, 0.0, 0.0]
const T_DISPERSE := 0.9
const SWEEP_TELE := [2.4, 1.8, 1.8]          # Intense never warns shorter than Standard (less idle, not less warning)
const SWEEP_GAP := [1.3, 1.0, 1.0]
const SWEEP_TIME := [1.6, 1.2, 1.1]
const SWEEP_PAUSE := [0.0, 0.8, 0.6]
const SWEEP_PATTERNS := [1, 2, 2]
const T_RETURN := [2.8, 2.2, 2.0]
const T_REFORM := [3.6, 2.8, 2.6]
const REVEAL_BONUS := 1.4
const HELPER_CD := [999.0, 20.0, 16.0]
const T_CH_FLY := [2.2, 2.0, 1.8]
const T_CHANNEL := [5.0, 4.0, 3.6]
const T_CH_REST := [2.0, 1.4, 1.2]
const CHANNEL_CD := [10.0, 8.0, 7.0]
const T_STAGGER := [5.0, 4.2, 3.8]
const T_TRANSITION := 2.4
## Settings "timing_assist" (comfort: "removes tight timing windows from ... boss mechanics", like the Matron,
## the Crossing Matron and the Choir): every warning, channel, opening and recovery beat x TIMING_ASSIST_MULT.
const TIMING_ASSIST_MULT := 1.5
## How long he waits for the Velvet Wing helper's committed attack before his own (covers its full drain).
const HELPER_WAIT := 5.0

var enemy_id: String = BOSS_ID
var boss_id: String = BOSS_ID
var mode: String = "story"
var data: Dictionary = {}
var health: Node
var visual: Node3D
var hit_radius: float = 0.75
var hit_color: Color = Color(0.86, 0.5, 0.7)
var arena_center := Vector3.ZERO
var arena_radius: float = 12.0
var candles: Array = []
var teach_candle: Node3D = null
var curtains: Array = []
var fixture: Node3D = null
var cover: Array = []
var helper_points: Array = []
var entry := Vector3.ZERO
var area: Node = null
var auto_start := true
var say_after_line := true

var state: String = "dormant"
var state_time: float = 0.0
var phase: int = 1
var fight_started := false
var hover_y: float = HOVER_Y
var target_override: Node3D = null     # tests
var intensity_override: int = -1       # tests
var next_action: String = ""           # tests: "dash" | "drain" | "disperse" | "channel"
var force_feint := false               # tests: the next Intense bow feints
var fast_defeat := false               # tests: skip the defeat presentation wait
# Counters (tests / QA telemetry)
var dashes: int = 0
var dash_hits: int = 0
var feints: int = 0
var drains_completed: int = 0
var drains_broken: int = 0
var last_drain_result: String = ""
var healed_total: float = 0.0
var dispersals: int = 0
var reveals: int = 0
var helpers_summoned: int = 0
var channels_started: int = 0
var candles_darkened: int = 0
var light_staggers: int = 0
var c_staggers: int = 0
var encounter_starts: int = 0
var resets: int = 0
var defeat_events: int = 0

var _state_len: float = 0.0
var _floor_y: float = 0.0
var _rng := RandomNumberGenerator.new()
var _gone := false
var _defeat_started := false
var _initialized := false
var _window_damage: float = 0.0
var _window_mult: float = 1.0
var _phase_pending: int = 0
var _lane_a := Vector3.ZERO
var _lane_b := Vector3.ZERO
var _lane_dir := Vector3.FORWARD
var _lane_len: float = 0.0
var _lane_clip_t: float = 0.0
var _dash_travel: float = 0.0
var _dash_resolved := false
var _dash_hit := false
var _dash_from_y: float = BOW_Y
var _feint_pending := false
var _drain_cd: float = 0.0
var _drain_check: float = 0.0
var _channel_cd: float = 0.0
var _channel_candle: Node3D = null
var _channel_spot := Vector3.ZERO
var _channel_from := Vector3.ZERO
var _glide_target := Vector3.ZERO
var _glide_wait: float = 0.0
var _b_step: int = 0
var _disperse_t: float = 0.0
var _helper: Node = null
var _helper_cd: float = 0.0
var _start_candles: Dictionary = {}
var _lane_mark: Node3D = null
var _ring_mark: Node3D = null
var _fx: Node3D = null
var _tether: Node3D = null
var _stream: Node3D = null
var _swarm: Node3D = null
var _away_t: float = 0.0
var _check_t: float = 0.0
var _said: Dictionary = {}
var _retry := false
var _director_held := false
var _spawn_pos := Vector3.ZERO
var _face_yaw: float = 0.0


func setup(params: Dictionary) -> void:
	var c: Variant = params.get("arena_center")
	if c is Vector3:
		arena_center = c
	arena_radius = maxf(float(params.get("arena_radius", arena_radius)), 4.0)
	mode = "trial" if String(params.get("mode", mode)) == "trial" else "story"
	for n in candles:
		_disconnect_candle(n)
	candles.clear()
	for n in params.get("candles", []):
		if n is Node3D and is_instance_valid(n):
			candles.append(n)
			if n.has_signal("lit") and not n.is_connected("lit", _on_candle_lit):
				n.connect("lit", _on_candle_lit)
	var tc: Variant = params.get("teach_candle")
	teach_candle = tc if tc is Node3D else null
	curtains = (params.get("curtains", []) as Array).duplicate() if params.get("curtains") is Array else []
	var fx: Variant = params.get("fixture")
	fixture = fx if fx is Node3D else null
	cover.clear()
	for p in params.get("cover", []):
		if p is Vector3:
			cover.append(p)
	helper_points.clear()
	for p in params.get("helper_points", []):
		if p is Vector3:
			helper_points.append(p)
	var e: Variant = params.get("entry")
	if e is Vector3:
		entry = e
	var a: Variant = params.get("area")
	area = a if a is Node else null
	auto_start = bool(params.get("auto_start", area == null))
	say_after_line = bool(params.get("say_after_line", not (area != null and area.has_method("mark_velour_defeated"))))
	if params.has("seed"):
		_rng.seed = int(params["seed"])
	else:
		_rng.randomize()
	if is_inside_tree() and data.size() > 0:
		_initialized = false
		_initialize()


func _ready() -> void:
	data = ItemDB.enemy(BOSS_ID)
	health = VelourHealth.new()
	health.name = "Health"
	health.max_hp = float(data.get("hp", 380.0))
	health.invulnerable = true
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	HitFx.ensure_hitstop()
	_initialize()


func _exit_tree() -> void:
	_director_hold(false)


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_floor_y = arena_center.y
	if is_story() and bool(GameState.get_flag(ManorLayout.FLAG_VELOUR_DEFEATED)):
		_gone = true
		state = "gone"
		visible = false
		return
	if visual == null:
		visual = Visual.new()
		visual.name = "Visual"
		add_child(visual)
	if _fx == null:
		_fx = Fx.new()
		_fx.name = "Shadows"
		add_child(_fx)
		_lane_mark = TelegraphFx.new()
		_lane_mark.name = "DashMark"
		add_child(_lane_mark)
		_ring_mark = TelegraphFx.new()
		_ring_mark.name = "RingMark"
		add_child(_ring_mark)
		_tether = Tether.new()
		_tether.name = "DrainTether"
		add_child(_tether)
		_stream = Tether.new()
		_stream.name = "CandleStream"
		_stream.setup({"color": Color(0.55, 0.4, 0.95), "late_color": Color(0.3, 0.2, 0.5)})
		add_child(_stream)
		_swarm = BatSwarm.new()
		_swarm.name = "BatSwarm"
		add_child(_swarm)
		_swarm.connect("returned", _on_swarm_returned)
	# (Re)configured on every initialize, so a later setup() with another arena / candle set reaches the bats too.
	_swarm.call("stop")
	_swarm.call("setup", {"center": arena_center, "half": arena_radius, "candles": candles, "hit_func": Callable(self, "_bat_hit"),
		"seed": _rng.randi()})
	# He waits across the Gallery from the doors (or north of the centre), hovering, hand on heart.
	var away := arena_center - entry
	away.y = 0.0
	if entry == Vector3.ZERO or away.length_squared() < 0.01:
		away = Vector3(0, 0, -1)
	_spawn_pos = arena_center + away.normalized() * minf(4.5, arena_radius * 0.4)
	_spawn_pos.y = _floor_y
	global_position = _spawn_pos
	hover_y = HOVER_Y
	_face_yaw = atan2(-away.x, -away.z)
	_enter("dormant")
	_sync_view(0.0)


# --- Public API ------------------------------------------------------------------------------------------------

func is_story() -> bool:
	return mode != "trial"


func is_gone() -> bool:
	return _gone


func is_threatening() -> bool:
	return fight_started and not _gone and not _defeat_started


func is_vulnerable() -> bool:
	return fight_started and not _gone and not _defeat_started and state in VULNERABLE


## Within sword reach right now (the reach tell: his height).
func is_reachable() -> bool:
	return hover_y <= REACH_TOP


func intensity() -> int:
	return intensity_override if intensity_override >= 0 else Combat.current_intensity()


## Spec section 9: false while he is out of reach / armoured (not in a window) and for any helper (companion,
## anything that is not Krystal) outside the arena - companions attack exposed phases only.
func can_be_hit_by(source: Node) -> bool:
	if not is_vulnerable() or not is_reachable():
		return false
	if source == null or not is_instance_valid(source) or not (source is Node3D):
		return true
	if _is_krystal(source) or source == target_override:
		return true
	return _flat((source as Node3D).global_position, arena_center) <= arena_radius + 1.0


## Phase for a health value: 1 above PHASE_AT[1], 2 above PHASE_AT[2], else 3 (a tiny epsilon so the exact
## threshold - where the health floor stops a hit - already counts as the next phase).
static func phase_for(hp: float, max_hp: float) -> int:
	var r := hp / maxf(max_hp, 0.001)
	if r <= float(PHASE_AT[2]) + 0.0005:
		return 3
	if r <= float(PHASE_AT[1]) + 0.0005:
		return 2
	return 1


func get_aim_point() -> Vector3:
	return Vector3(global_position.x, _floor_y + hover_y, global_position.z)


func knockback(_dir: Vector3, _force: float) -> void:
	pass


## Hits that find him out of reach / armoured spark off; the hint is Krystal's only.
func on_hit_blocked(attacker: Node, _dir: Vector3) -> void:
	if _gone or _defeat_started:
		return
	HitFx.spark(get_aim_point())
	# A blow on his exposed, channelling form always interrupts the channel - also when the borrowed mask's floor
	# swallows its damage (a hit that finds no room above the floor comes back as "blocked"): the candle rule.
	if state == "channel" and fight_started and can_be_hit_by(attacker) and not health.invulnerable:
		_light_stagger("hit")
		return
	Audio.play_3d("hit_soft", get_aim_point(), -4.0, 0.2)
	if attacker != null and is_instance_valid(attacker) and not _is_krystal(attacker) and attacker != target_override:
		return
	if phase == 3 and c_staggers == 0 and state in VULNERABLE and health.hp <= health.floor_hp + 0.01:
		Events.hint.emit("velour_mask", "The borrowed mask holds! Light is his weakness now: strike him while he snuffs a candle, or relight a dark candle with {interact}.")
	elif state == "bats" or state == "disperse":
		Events.hint.emit("velour_bats_glance", "He has scattered into bats. Keep to the lane marked with golden rings, then watch for the bat wearing his collar.")
	else:
		Events.hint.emit("velour_glance", "He floats out of reach. Sidestep his dash: he recoils within reach at the far end.")


# --- State machine ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _gone or _defeat_started or not _initialized:
		return
	state_time += delta
	_check_t -= delta
	var check := _check_t <= 0.0
	if check:
		_check_t = 0.2
	var p := _player()
	if fight_started:
		_drain_cd = maxf(_drain_cd - delta, 0.0)
		_channel_cd = maxf(_channel_cd - delta, 0.0)
		_helper_cd = maxf(_helper_cd - delta, 0.0)
		_hold_helper()
		if check and area == null and _stand_down_due(p, 0.2):
			reset_fight()
			return
	if state != "dash":
		hover_y = move_toward(hover_y, _target_height(), HEIGHT_SPEED * delta)
	match state:
		"dormant":
			if auto_start and check and p != null and _hunt_allowed(p) and _flat(p.global_position, arena_center) <= arena_radius:
				start_fight()
		"intro":
			_face_toward(p, delta)
			if state_time >= _state_len:
				_enter_glide()
		"glide":
			_tick_glide(delta, p)
		"bow", "final_tell":
			_tick_bow(delta, p)
		"flourish":
			_face_toward(p, delta)
			if state_time >= _state_len:
				_enter("final_tell", _assisted(T_FINAL_TELL))
				_lane_clip_t = 0.0
				_update_lane(p, true)
				Audio.play_3d("shade_telegraph", get_aim_point(), -3.0, 0.05, 40.0)
				Events.caption.emit("[his little crown flashes - here he comes]")
		"dash":
			_tick_dash(delta, p)
		"recoil", "drain_rest", "channel_rest", "reform", "stagger":
			if state_time >= _state_len:
				_end_window()
		"drain_tele":
			_tick_drain(delta, p, false)
		"drain":
			_tick_drain(delta, p, true)
		"disperse":
			if state_time >= _state_len:
				_begin_bats(p)
		"bats":
			_disperse_t += delta
			if _swarm != null:
				_swarm.call("tick", delta, p if p != null and _hunt_allowed(p) else null)
			if state == "bats" and _disperse_t >= MAX_DISPERSED:
				if _swarm != null:
					_swarm.call("stop")
				_reform(_clamp_in_arena(global_position, ARENA_MARGIN), false)
		"channel_fly":
			_tick_channel_fly(delta)
		"channel":
			_tick_channel(delta, p)
		"transition":
			if state_time >= _state_len:
				_enter_glide()
	_refresh_armour()
	_sync_view(delta)


func _i() -> int:
	return clampi(intensity(), 0, 2)


## A warning / channel / opening / recovery length after Settings "timing_assist" (x TIMING_ASSIST_MULT).
func _assisted(base: float) -> float:
	return base * TIMING_ASSIST_MULT if bool(Settings.get_value("timing_assist")) else base


## `table[intensity]` (a timing table) after timing_assist.
func _tt(table: Array) -> float:
	return _assisted(float(table[_i()]))


func _enter(s: String, length: float = 0.0) -> void:
	var prev := state
	state = s
	state_time = 0.0
	_state_len = length
	var vul := s in VULNERABLE
	if vul and not (prev in VULNERABLE):
		_window_damage = 0.0
	if not vul:
		_window_mult = 1.0
	if not (s in ["bow", "final_tell", "dash"]):
		if _lane_mark != null:
			_lane_mark.call("hide_mark")
		if _fx != null:
			_fx.call("hide_lane")
	if s != "drain_tele" and s != "drain":
		if _tether != null:
			_tether.call("hide_link")
		if _ring_mark != null and not (s in ["channel_fly", "channel"]):
			_ring_mark.call("hide_mark")
	if s != "channel" and _stream != null:
		_stream.call("hide_link")
	_refresh_armour()
	if visual != null:
		visual.visible = s != "bats" and s != "gone" and s != "defeat"
		var vs := s
		if s == "bats":
			vs = "hidden"
		visual.call("set_state", vs, length)
	state_changed.emit(s)


func _target_height() -> float:
	match state:
		"bow", "flourish", "final_tell":
			return BOW_Y
		"recoil":
			return RECOIL_Y
		"drain_tele", "drain", "drain_rest":
			return DRAIN_Y
		"reform":
			return REFORM_Y
		"channel", "channel_rest":
			return CHANNEL_Y
		"channel_fly":
			return HOVER_Y if state_time < _state_len * 0.6 else CHANNEL_Y
		"stagger":
			return STAGGER_Y
	return HOVER_Y


func _refresh_armour() -> void:
	if health == null:
		return
	health.invulnerable = not (is_vulnerable() and is_reachable())
	health.damage_taken_mult = _window_mult


## Start (the manor calls this once Krystal stands in the Gallery with the teaching candle lit).
func start_fight() -> void:
	if fight_started or _gone or _defeat_started or not _initialized:
		return
	fight_started = true
	encounter_starts += 1
	add_to_group("enemy")                # only while the encounter runs (dormant he is scenery, not a threat)
	_record_candles()
	_update_floor()
	_emit_health()
	Events.boss_encounter_changed.emit(boss_id, true)
	Events.boss_phase_changed.emit(boss_id, phase)
	_director_hold(true)
	_notice_companions()
	Audio.play_3d("shade_drift", get_aim_point(), -2.0, 0.03, 50.0)
	Events.caption.emit("[a velvet cape sweeps the air: the host bows low]")
	if _retry:
		if is_story():
			Events.hint.emit("velour_retry", "The Count keeps his wounds while you stay in the manor, and every candle is lit afresh.")
		else:
			# Separate id: the Echo Trial's rule has its own wording, and the story hint still shows once later.
			Events.hint.emit("velour_retry_trial", "The echo keeps his wounds while you stay in the memory. Leave through the pale door and it starts afresh.")
	if state == "dormant":
		_enter("intro", T_INTRO if encounter_starts == 1 else 1.2)
	if Debug.is_cheat_allowed() and Debug.has_arg("velour-phase"):
		jump_to_phase(int(Debug.arg("velour-phase", "1")))


## Tests / QA only (cheats: --velour-phase=2|3 when the fight starts): puts him in phase `n` with his health just
## under its threshold. Everything in flight is cleared; the transition beat is skipped.
func jump_to_phase(n: int) -> void:
	var np := clampi(n, 1, 3)
	if np <= phase or _gone or _defeat_started:
		return
	_clear_attacks()
	phase = np
	if np >= 3:
		_dismiss_helper()
		_channel_cd = 0.0
	health.floor_hp = 0.0
	health.set_hp(floorf(health.max_hp * float(PHASE_AT[np - 1])) - 1.0)
	_update_floor()
	Events.boss_phase_changed.emit(boss_id, np)
	phase_changed.emit(np)
	if fight_started and state != "dormant":
		_enter_glide()


func _enter_glide() -> void:
	if _phase_pending > 0:
		_begin_transition(_phase_pending)
		return
	var r: Array = T_GLIDE[_i()]
	_enter("glide", _rng.randf_range(float(r[0]), float(r[1])))
	_glide_wait = 0.0
	_pick_glide_target(_player())


func _tick_glide(delta: float, p: Node3D) -> void:
	var pos := global_position
	var to := Vector3(_glide_target.x - pos.x, 0.0, _glide_target.z - pos.z)
	var d := to.length()
	if d > 0.05:
		global_position += to / d * minf(float(GLIDE_SPEED[_i()]) * delta, d)
	_face_toward(p, delta)
	if state_time < _state_len:
		return
	if p == null or not _hunt_allowed(p) or _flat(p.global_position, arena_center) > arena_radius + 1.0:
		return                        # she is away / down: keep hovering (the area pauses him if she leaves)
	if _helper_busy() and _glide_wait < HELPER_WAIT:
		_glide_wait += delta          # never wind up over the helper's committed attack
		return
	_choose_action(p)


func _pick_glide_target(p: Node3D) -> void:
	var c := arena_center
	var pp := p.global_position if p != null else c
	var from_p := Vector3(global_position.x - pp.x, 0.0, global_position.z - pp.z)
	if from_p.length_squared() < 0.01:
		from_p = Vector3(0, 0, -1)
	var ang := atan2(from_p.z, from_p.x) + _rng.randf_range(-0.9, 0.9)
	var t := pp + Vector3(cos(ang), 0.0, sin(ang)) * KEEP_DIST
	_glide_target = _avoid_cover(_clamp_in_arena(t, ARENA_MARGIN))


func _choose_action(p: Node3D) -> void:
	var a := next_action
	next_action = ""
	if a == "":
		match phase:
			1:
				a = "drain" if dashes >= 2 and _drain_cd <= 0.0 and _drain_break_reason(p) == "" and _flat(p.global_position, global_position) >= 3.0 else "dash"
			2:
				a = "disperse" if _b_step % 2 == 0 else "dash"
				_b_step += 1
			_:
				var must: bool = c_staggers == 0 and float(health.hp) <= float(health.floor_hp) + 0.5
				a = "channel" if (_channel_cd <= 0.0 or must) and _pick_channel_candle(p) != null else "dash"
	match a:
		"drain":
			_begin_drain(p)
		"disperse":
			_begin_disperse(p)
		"channel":
			if not _begin_channel(p):
				_begin_bow(p)
		_:
			_begin_bow(p)


# --- Phase A: bow -> cape dash -> recoil ---------------------------------------------------------------------------

func _begin_bow(p: Node3D) -> void:
	_feint_pending = _i() == 2 and (force_feint or (dashes >= 1 and _rng.randf() < FEINT_CHANCE))
	force_feint = false
	_enter("bow", _tt(T_BOW))
	_lane_clip_t = 0.0
	_update_lane(p, true)
	Audio.play_3d("shade_drift", get_aim_point(), -2.0, 0.08, 40.0)
	Events.caption.emit("[a velvet cape sweeps into a bow]")
	Events.hint.emit("velour_dash", "When Count Velour bows, his shadow points where he will dash. Step aside: he recoils at the far end, within reach.")


func _tick_bow(delta: float, p: Node3D) -> void:
	var track := BOW_TRACK if state == "bow" else FINAL_TRACK
	var tracking := state_time <= _state_len * track
	_lane_clip_t -= delta
	_update_lane(p, tracking and _lane_clip_t <= 0.0)
	var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
	if _lane_mark != null:
		_lane_mark.call("set_progress", k, not tracking)
	if state == "bow" and _feint_pending and state_time >= _state_len * FEINT_AT:
		_feint_pending = false
		feints += 1
		_enter("flourish", T_FLOURISH)
		Audio.play_3d("shade_drift", get_aim_point(), -6.0, 0.2, 40.0)
		Events.caption.emit("[a teasing flourish of the cape - not yet]")
		Events.hint.emit("velour_feint", "A flourish is a feint! Wait for his little crown to flash, then sidestep the real dash.")
		return
	if state_time >= _state_len:
		_begin_dash()


## Re-aims (when `retrack`) and re-shows the dash lane: from him through Krystal, clipped by walls / cover and
## kept inside the arena. The shadow and the ground mark show the SAME segment the dash resolves on.
func _update_lane(p: Node3D, retrack: bool) -> void:
	var a := Vector3(global_position.x, _floor_y, global_position.z)
	if retrack:
		_lane_clip_t = LANE_REFRESH
		if p != null:
			var d := Vector3(p.global_position.x - a.x, 0.0, p.global_position.z - a.z)
			if d.length_squared() > 0.04:
				_lane_dir = d.normalized()
		_lane_len = _clip_lane(a, _lane_dir, float(_attack("cape_dash").get("distance", 10.0)))
	_lane_a = a
	_lane_b = a + _lane_dir * _lane_len
	if _lane_mark != null:
		var m := _lane_mark
		if not bool(m.call("is_showing")) or String(m.get("kind")) != "lane":
			m.call("show_lane", _lane_a, _lane_b, DASH_HALF_WIDTH * 2.0, TelegraphFx.DANGER)
		else:
			m.call("move_lane", _lane_a, _lane_b)
	if _fx != null:
		_fx.call("show_lane", _lane_a, _lane_b, clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0))


## Lane length along `dir`: capped by the arena circle and stopped short of walls / pillars / statues.
func _clip_lane(a: Vector3, dir: Vector3, want: float) -> float:
	var length := want
	var rel := Vector2(a.x - arena_center.x, a.z - arena_center.z)
	var dv := Vector2(dir.x, dir.z)
	var b := rel.dot(dv)
	var cc := rel.length_squared() - (arena_radius + 0.5) * (arena_radius + 0.5)
	var disc := b * b - cc
	if disc >= 0.0:
		length = minf(length, maxf(-b + sqrt(disc), 0.0))
	if is_inside_tree():
		var o := a + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * (length + 0.6), Combat.LOS_MASK)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			length = minf(length, maxf(Vector2(hp.x - o.x, hp.z - o.z).length() - 0.6, 0.0))
	return maxf(length, 0.0)


func _begin_dash() -> void:
	_enter("dash", 0.0)
	_dash_travel = 0.0
	_dash_resolved = false
	_dash_hit = false
	_dash_from_y = hover_y
	if _lane_mark != null:
		_lane_mark.call("set_progress", 1.0, true)
	Audio.play_3d("dodge", get_aim_point(), -1.0, 0.08, 40.0)
	Events.caption.emit("[a rush of velvet]")


func _tick_dash(delta: float, p: Node3D) -> void:
	var speed := float(DASH_SPEED[_i()])
	var prev := Vector3(global_position.x, _floor_y, global_position.z)
	_dash_travel = minf(_dash_travel + speed * delta, _lane_len)
	var now := _lane_a + _lane_dir * _dash_travel
	global_position = Vector3(now.x, _floor_y, now.z)
	var k := _dash_travel / maxf(_lane_len, 0.01)
	hover_y = lerpf(_dash_from_y, DASH_Y, clampf(k / DASH_DESCENT, 0.0, 1.0))
	if not _dash_resolved and p != null and _is_victim(p):
		var pp := p.global_position
		if TelegraphFx.segment_distance(prev, now, pp) <= DASH_HALF_WIDTH + TARGET_BODY and absf(Combat.aim_point(p).y - get_aim_point().y) <= DASH_HIT_DY:
			_dash_resolved = true      # she was in the lane as he passed: resolved (a dodge lets it run on)
			if _los(get_aim_point(), Combat.aim_point(p), p):
				var lat := Vector3(-_lane_dir.z, 0.0, _lane_dir.x)
				var sd := signf(lat.dot(pp - now))
				var kdir := (_lane_dir + lat * (sd if sd != 0.0 else 1.0) * 0.7).normalized()
				var dealt := _deal(p, _damage("cape_dash", 16.0), kdir, float(data.get("knockback", 6.5)))
				if state != "dash" or not fight_started:
					return             # the blow felled her: reset_fight already ran inside _deal (player_died)
				if dealt > 0.0:
					_dash_hit = true
					dash_hits += 1
	if _dash_travel >= _lane_len - 0.0001 or state_time > _lane_len / speed + 0.5:
		_end_dash()


func _end_dash() -> void:
	dashes += 1
	_enter("recoil", _tt(T_RECOIL_HIT) if _dash_hit else _tt(T_RECOIL))
	Audio.play_3d("gloomling_flinch", get_aim_point(), -4.0, 0.1, 30.0)
	Events.caption.emit("[a dizzy little gasp]")


# --- Phase A: drain tether -------------------------------------------------------------------------------------

func _begin_drain(p: Node3D) -> void:
	_enter("drain_tele", _tt(T_DRAIN_TELE))
	_drain_check = 0.0
	Audio.play_3d("shade_telegraph", get_aim_point(), -3.0, 0.08, 40.0)
	Events.caption.emit("[a thin, hungry hum]")
	Events.hint.emit("velour_drain", "A tether means he is draining you. Break it: step behind cover, stand in a candle's pool, or strike him.")
	_say_once("drain", LINE_DRAIN, 3.5)
	_show_drain(p, false)


func _tick_drain(delta: float, p: Node3D, channel: bool) -> void:
	_face_toward(p, delta)
	_show_drain(p, channel)
	_drain_check -= delta
	if _drain_check <= 0.0:
		_drain_check = 0.1
		var why := _drain_break_reason(p)
		if why != "":
			_break_drain(why)
			return
	if state_time >= _state_len:
		if not channel:
			_enter("drain", _tt(T_DRAIN))
			_drain_check = 0.1
			_show_drain(p, true)
		else:
			_finish_drain(p)


func _show_drain(p: Node3D, channel: bool) -> void:
	if p == null or not is_instance_valid(p):
		return
	var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0) if channel else 0.0
	if _tether != null:
		_tether.call("show_link", Combat.aim_point(p), get_aim_point(), k, channel)
	if _ring_mark != null:
		if not bool(_ring_mark.call("is_showing")) or String(_ring_mark.get("kind")) != "ring":
			_ring_mark.call("show_ring", p.global_position, 0.7, Color(0.86, 0.36, 0.62))
		else:
			(_ring_mark as Node3D).global_position = p.global_position + Vector3.UP * TelegraphFx.Y_OFFSET
		_ring_mark.call("set_progress", k if channel else clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0), channel)


## Why the tether would break right now ("" = it holds): "target", "range", "sight" (a wall / pillar / statue cuts
## the line), "candle" (she stands in a lit ward-candle pool; Gentle pools reach a little further).
func _drain_break_reason(p: Node3D) -> String:
	if p == null or not is_instance_valid(p) or not _is_victim(p) or not _hunt_allowed(p):
		return "target"
	if _flat(p.global_position, global_position) > float(DRAIN_RANGE[_i()]):
		return "range"
	if not _los(get_aim_point(), Combat.aim_point(p), p):
		return "sight"
	if in_candle_pool(p.global_position, float(DRAIN_POOL_BONUS[_i()])):
		return "candle"
	return ""


## True when `pos` is inside a LIT arena candle's pool (+ `bonus` metres).
func in_candle_pool(pos: Vector3, bonus: float = 0.0) -> bool:
	for c in candles:
		if not is_instance_valid(c) or not bool(c.call("is_lit")):
			continue
		var cp: Vector3 = c.call("pool_center")
		if Vector2(pos.x - cp.x, pos.z - cp.z).length() <= float(c.get("pool_radius")) + bonus:
			return true
	return false


func _break_drain(why: String) -> void:
	drains_broken += 1
	last_drain_result = why
	_drain_cd = float(DRAIN_CD[_i()])
	Audio.play_3d("gloomling_flinch", get_aim_point(), -4.0, 0.1, 30.0)
	Events.caption.emit("[the tether snaps]")
	_enter("drain_rest", _tt(T_DRAIN_REST))
	drain_resolved.emit(why)


## The channel held to the end: ONE hit through her health; he heals by what was dealt (x DRAIN_HEAL_MULT), never
## above the top of his current phase. Nothing heals him before this moment.
func _finish_drain(p: Node3D) -> void:
	var why := _drain_break_reason(p)
	if why != "":
		_break_drain(why)
		return
	var dir := p.global_position - global_position
	var dealt := _deal(p, _damage("drain", 8.0), dir, 1.5)
	if state != "drain" or not fight_started:
		return             # the drain felled her: reset_fight already ran inside _deal (player_died) - no heal, no rest
	if dealt > 0.0 and not health.dead:
		healed_total += float(health.call("heal_capped", dealt * DRAIN_HEAL_MULT, _phase_ceiling()))
	drains_completed += 1
	last_drain_result = "complete"
	_drain_cd = float(DRAIN_CD[_i()])
	Audio.play_3d("shade_whisper", get_aim_point(), -4.0, 0.1, 30.0)
	Events.caption.emit("[a satisfied little sigh]")
	_enter("drain_rest", _tt(T_DRAIN_REST))
	drain_resolved.emit("complete")


func _phase_ceiling() -> float:
	return health.max_hp * float(PHASE_AT[clampi(phase - 1, 0, 2)])


# --- Phase B: the ballroom in flight ------------------------------------------------------------------------------

func _begin_disperse(p: Node3D) -> void:
	dispersals += 1
	_disperse_t = 0.0
	_enter("disperse", T_DISPERSE)
	Audio.play_3d("dir_wrong_squeak", get_aim_point(), -2.0, 0.1, 50.0)
	Audio.play_3d("shade_drift", get_aim_point(), -4.0, 0.1, 50.0)
	Events.caption.emit("[his cape bursts into a cloud of squeaking bats]")
	Events.hint.emit("velour_bats", "He has become bats! Stand in the lane marked with golden rings. Then watch for the bat wearing his collar: candle-light reveals him.")
	_maybe_summon_helper(p)


## The sweep patterns of one dispersal: Gentle one (always north-south), Standard / Intense two (the second across
## the other axis).
func sweep_specs() -> Array:
	var i := _i()
	var out: Array = []
	var first := "ns"
	if i > 0 and _rng.randf() < 0.5:
		first = "ew"
	for n in int(SWEEP_PATTERNS[i]):
		var o := first if n % 2 == 0 else ("ew" if first == "ns" else "ns")
		out.append({"orientation": o, "tele": _assisted(float(SWEEP_TELE[i])), "gap": _assisted(float(SWEEP_GAP[i])),
			"sweep": float(SWEEP_TIME[i]), "pause": float(SWEEP_PAUSE[i])})
	return out


func _begin_bats(p: Node3D) -> void:
	_enter("bats", 0.0)
	if _swarm != null:
		_swarm.call("begin", sweep_specs(), float(T_RETURN[_i()]), _i() == 0, p)
	Audio.play_3d("dir_wrong_squeak", arena_center + Vector3.UP * 2.0, -4.0, 0.2, 50.0)
	Events.caption.emit("[a rush of wings circles the Gallery]")


## Sweep damage (bat_swarm hit_func): one hit through her health.
func _bat_hit(t: Node3D, dir: Vector3) -> float:
	return _deal(t, _damage("bat_sweep", 12.0), dir, 4.0)


func _on_swarm_returned(was_revealed: bool, at: Vector3) -> void:
	if state != "bats":
		return
	_reform(at, was_revealed)


func _reform(at: Vector3, was_revealed: bool) -> void:
	var pos := _avoid_cover(_clamp_in_arena(at, 1.2))
	global_position = Vector3(pos.x, _floor_y, pos.z)
	hover_y = REFORM_Y
	var length := _tt(T_REFORM)
	if was_revealed:
		reveals += 1
		length += _assisted(REVEAL_BONUS)
	_enter("reform", length)
	if was_revealed:
		_window_mult = REVEAL_MULT
		if visual != null:
			visual.call("set_revealed", true)
		Audio.play_3d("checkpoint_light", get_aim_point(), -4.0, 0.05, 40.0)
		Events.caption.emit("[candle-light catches a bat wearing a golden collar]")
	else:
		Audio.play_3d("shade_drift", get_aim_point(), -4.0, 0.1, 40.0)
		Events.caption.emit("[the bats fold back into the Count]")
	_refresh_armour()


func _maybe_summon_helper(p: Node3D) -> void:
	if _helper_alive() or helper_points.is_empty() or _helper_cd > 0.0:
		return
	if _i() == 0 and helpers_summoned >= 1:
		return
	if not Factory.can_spawn(HELPER_ID):
		return
	var parent: Node = get_parent() if get_parent() != null else self
	var pp := p.global_position if p != null else arena_center
	var best: Vector3 = helper_points[0]
	for hp in helper_points:
		if _flat(hp, pp) > _flat(best, pp):
			best = hp
	var h: Node = Factory.spawn(HELPER_ID, parent, Transform3D(Basis.IDENTITY, best),
		{"home": best, "wander_radius": 2.0, "alert": true, "no_drops": true})
	if h == null:
		return
	_helper = h
	helpers_summoned += 1
	_helper_cd = float(HELPER_CD[_i()])
	if target_override != null and "target_override" in h:
		h.set("target_override", target_override)
	Events.caption.emit("[a Velvet Wing answers the Count's call]")


func _helper_alive() -> bool:
	if _helper == null or not is_instance_valid(_helper) or _helper.is_queued_for_deletion():
		return false
	if _helper.has_method("is_dead") and bool(_helper.call("is_dead")):
		return false
	return true


func helper_node() -> Node:
	return _helper if _helper_alive() else null


## The helper never starts a wind-up while he commits to an attack (and he waits for its own - see glide).
func _hold_helper() -> void:
	if not _helper_alive() or not (state in COMMITTED):
		return
	if "_cooldown" in _helper:
		_helper.set("_cooldown", maxf(float(_helper.get("_cooldown")), 0.6))


func _helper_busy() -> bool:
	return _helper_alive() and String(_helper.get("state")) in HELPER_BUSY


func _dismiss_helper() -> void:
	if _helper != null and is_instance_valid(_helper) and not _helper.is_queued_for_deletion():
		if _helper is Node3D and (_helper as Node3D).is_inside_tree():
			HitFx.burst((_helper as Node3D).global_position + Vector3.UP * 1.2, Color(0.62, 0.22, 0.38), 10, 1.6, 0.7, -1.0, 0.6, 150.0)
		_helper.queue_free()
	_helper = null


# --- Phase C: drop the borrowed mask ----------------------------------------------------------------------------

## The lit candle he goes for: Gentle the one nearest Krystal; otherwise the farthest one she can still reach.
func _pick_channel_candle(p: Node3D) -> Node3D:
	var pp := p.global_position if p != null else arena_center
	var best: Node3D = null
	var best_d := -1.0
	for c in candles:
		if not is_instance_valid(c) or not bool(c.call("is_lit")):
			continue
		var d := _flat((c as Node3D).global_position, pp)
		if _i() == 0:
			if best == null or d < best_d:
				best = c
				best_d = d
		elif d <= CHANNEL_MAX_DIST and d > best_d:
			best = c
			best_d = d
	if best == null and _i() > 0:
		for c in candles:
			if is_instance_valid(c) and bool(c.call("is_lit")):
				return c
	return best


func _begin_channel(p: Node3D) -> bool:
	var c := _pick_channel_candle(p)
	if c == null:
		return false
	_channel_candle = c
	channels_started += 1
	var cp := c.global_position
	var pp := p.global_position if p != null else arena_center
	var away := Vector3(cp.x - pp.x, 0.0, cp.z - pp.z)
	if away.length_squared() < 0.01:
		away = Vector3(cp.x - arena_center.x, 0.0, cp.z - arena_center.z)
	if away.length_squared() < 0.01:
		away = Vector3(0, 0, -1)
	_channel_spot = _clamp_in_arena(cp + away.normalized() * CHANNEL_OFFSET, 1.0)
	_channel_from = Vector3(global_position.x, _floor_y, global_position.z)
	_enter("channel_fly", _tt(T_CH_FLY))
	if _ring_mark != null:
		_ring_mark.call("show_ring", cp, float(c.get("pool_radius")), Color(0.55, 0.4, 0.95))
		_ring_mark.call("set_progress", 0.0, false)
	Audio.play_3d("shade_whisper", get_aim_point(), -4.0, 0.1, 40.0)
	Events.caption.emit("[he glides toward a ward candle, humming to its flame]")
	Events.hint.emit("velour_candle", "He means to snuff a candle! Strike him while he channels, or relight a dark candle with {interact}: light staggers him.")
	return true


func _tick_channel_fly(_delta: float) -> void:
	if _channel_candle == null or not is_instance_valid(_channel_candle) or not bool(_channel_candle.call("is_lit")):
		_channel_candle = null
		_enter_glide()
		return
	var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var at := _channel_from.lerp(_channel_spot, e)
	global_position = Vector3(at.x, _floor_y, at.z)
	_face_dir(_channel_candle.global_position - global_position, 1.0)
	if _ring_mark != null:
		_ring_mark.call("set_progress", k * 0.5, false)
	if state_time >= _state_len:
		_enter("channel", _tt(T_CHANNEL))
		Audio.play_3d("shade_telegraph", get_aim_point(), -5.0, 0.1, 40.0)


func _tick_channel(_delta: float, _p: Node3D) -> void:
	if _channel_candle == null or not is_instance_valid(_channel_candle) or not bool(_channel_candle.call("is_lit")):
		_channel_candle = null
		_enter_glide()
		return
	var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
	if _stream != null:
		_stream.call("show_link", _channel_candle.call("flame_position"), get_aim_point(), k, true)
	if _ring_mark != null:
		_ring_mark.call("set_progress", 0.5 + 0.5 * k, true)
	if state_time >= _state_len:
		var c := _channel_candle
		_channel_candle = null
		if bool(c.call("darken", self)):
			candles_darkened += 1
			candle_darkened.emit(c)
		_channel_cd = float(CHANNEL_CD[_i()])
		_enter("channel_rest", _tt(T_CH_REST))
		if _ring_mark != null:
			_ring_mark.call("hide_mark")


## Light (a relit candle) or a blow on his exposed, channelling form staggers him: a generous window.
func _light_stagger(how: String) -> void:
	if _gone or _defeat_started or not fight_started or phase != 3:
		return
	if state in ["stagger", "transition", "dormant", "intro"]:
		return
	_channel_candle = null
	light_staggers += 1
	c_staggers += 1
	_update_floor()
	_channel_cd = float(CHANNEL_CD[_i()])
	_enter("stagger", _tt(T_STAGGER))
	_window_damage = 0.0
	_window_mult = STAGGER_MULT
	if visual != null:
		visual.call("set_revealed", how == "light")
	if _ring_mark != null:
		_ring_mark.call("hide_mark")
	Audio.play_3d("brazier_light", get_aim_point(), -3.0, 0.05, 40.0)
	Audio.play_3d("gloomling_flinch", get_aim_point(), -4.0, 0.1, 40.0)
	Events.caption.emit("[light flares - the Count reels]")
	Events.camera_shake.emit(0.12, 0.25)
	_say_once("stagger", LINE_STAGGER, 3.0)
	_refresh_armour()


func _on_candle_lit(_c: Node3D) -> void:
	if not fight_started or phase != 3:
		return
	_light_stagger("light")


# --- Phases, damage, defeat ------------------------------------------------------------------------------------

## The health floor: the next phase threshold (phases A / B), then the borrowed-mask floor until light has
## staggered him once in phase C.
func _update_floor() -> void:
	if health == null:
		return
	match phase:
		1:
			health.floor_hp = health.max_hp * float(PHASE_AT[1])
		2:
			health.floor_hp = health.max_hp * float(PHASE_AT[2])
		_:
			# No ward candle to play the rule with (a misconfigured arena / trial): never hold a floor that nothing
			# could ever lift - that would be an unwinnable fight.
			health.floor_hp = 0.0 if c_staggers >= 1 or not _has_candles() else health.max_hp * MASK_FLOOR


func _has_candles() -> bool:
	for c in candles:
		if is_instance_valid(c):
			return true
	return false


func _begin_transition(np: int) -> void:
	_phase_pending = 0
	if np <= phase:
		_enter_glide()
		return
	_clear_attacks()
	phase = np
	if np >= 3:
		_dismiss_helper()
		_channel_cd = 1.5
	_update_floor()
	_enter("transition", T_TRANSITION)
	Events.boss_phase_changed.emit(boss_id, np)
	phase_changed.emit(np)
	Audio.play_3d("stinger_soft", get_aim_point(), -6.0, 0.0, 60.0)
	Events.caption.emit("[a dramatic swirl of velvet]" if np == 2 else "[the borrowed mask slips; he reaches for the candles]")
	if np == 2:
		_say_once("bats", LINE_BATS, 3.5)
	else:
		_say_once("candles", LINE_CANDLES, 3.5)
		Events.hint.emit("velour_phase3", "He will try to snuff the ward candles. Keep them burning: light staggers him.")


func _on_damaged(amount: float, _source: Node, _dir: Vector3) -> void:
	HitFx.flash(self)
	HitFx.number(get_aim_point() + Vector3.UP * 0.6, amount)
	Audio.play_3d("enemy_hurt", get_aim_point(), -3.0, 0.1)
	if health.dead or health.hp <= 0.0:
		return
	_window_damage += amount
	var np := phase_for(health.hp, health.max_hp)
	if np > phase:
		_phase_pending = np
		_begin_transition(np)
		return
	match state:
		"drain_tele", "drain":
			_break_drain("hit")
			return
		"channel":
			_light_stagger("hit")
			return
	if state in VULNERABLE and _window_damage >= health.max_hp * WINDOW_CAP:
		Audio.play_3d("shade_drift", get_aim_point(), -4.0, 0.1, 40.0)
		Events.caption.emit("[he whirls up out of reach]")
		_enter_glide()


func _on_health_changed(_hp: float, _max_hp: float) -> void:
	if fight_started:
		_emit_health()


func _emit_health() -> void:
	Events.boss_health_changed.emit(boss_id, health.hp, health.max_hp)


func _on_died() -> void:
	_begin_defeat()


## Victory: COMMIT first (bar hidden, encounter over, boss_defeated -> the arena sets ch2_velour_defeated), then the
## enchantment disperses (presentation), then - without an owning arena - the line.
func _begin_defeat() -> void:
	if _defeat_started or _gone:
		return
	_defeat_started = true
	health.invulnerable = true
	_clear_attacks()
	_dismiss_helper()
	fight_started = false
	remove_from_group("enemy")           # no longer a target (auto-aim, companions) during the presentation
	state = "defeat"
	Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
	Events.boss_encounter_changed.emit(boss_id, false)
	_director_hold(false)
	if is_story():
		defeat_events += 1
		Events.boss_defeated.emit(boss_id)
	defeated.emit()
	state_changed.emit("defeat")
	# Presentation (after the commit): the enchantment scatters, the borrowed mask falls - no gore.
	if visual != null:
		visual.visible = false
	if _fx != null:
		_fx.call("hide_all")
	Fx.disperse(get_parent(), get_aim_point())
	Audio.play_3d("ward_restore", get_aim_point(), -3.0, 0.0, 60.0)
	Events.caption.emit("[the enchantment scatters like startled bats; a borrowed mask falls and fades]")
	Events.camera_shake.emit(0.15, 0.5)
	if is_inside_tree() and not fast_defeat:
		# A timer connection (not an await): if the area unloads meanwhile, nothing resumes on a freed node.
		get_tree().create_timer(DEFEAT_PRESENT).timeout.connect(_finish_defeat, CONNECT_ONE_SHOT)
	else:
		_finish_defeat()


func _finish_defeat() -> void:
	if _gone:
		return
	_gone = true
	state = "gone"
	visible = false
	remove_from_group("enemy")
	if visual != null:
		visual.set_process(false)          # hidden for good: no more per-frame cape animation
	if not is_story():
		_restore_candles()
	if say_after_line:
		Events.say.emit(ManorLayout.VELOUR_NAME, ManorLayout.VELOUR_AFTER, 6.0)
	state_changed.emit("gone")


func _on_player_died() -> void:
	reset_fight()


## Clean reset (Krystal fell / the area paused the encounter): see RESET POLICY in the header.
func reset_fight() -> void:
	if _gone or _defeat_started or not _initialized:
		return
	_clear_attacks()
	_dismiss_helper()
	_restore_candles()
	_phase_pending = 0
	_feint_pending = false
	_window_damage = 0.0
	_window_mult = 1.0
	_drain_cd = 0.0
	_channel_cd = 1.5
	_b_step = 0
	_away_t = 0.0
	_glide_wait = 0.0
	global_position = _spawn_pos
	hover_y = HOVER_Y
	remove_from_group("enemy")
	if fight_started:
		fight_started = false
		_retry = true
		resets += 1
		Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
		Events.boss_encounter_changed.emit(boss_id, false)
		_director_hold(false)
	_enter("dormant")
	_update_floor()
	_sync_view(0.0)


## Aliases the manor's encounter hook also recognises.
func stop_fight() -> void:
	reset_fight()


## Everything in flight goes away at once: bats, tether, stream, marks, shadows, the channel.
func _clear_attacks() -> void:
	if _swarm != null:
		_swarm.call("stop")
	if _tether != null:
		_tether.call("hide_link")
	if _stream != null:
		_stream.call("hide_link")
	if _lane_mark != null:
		_lane_mark.call("hide_mark")
	if _ring_mark != null:
		_ring_mark.call("hide_mark")
	if _fx != null:
		_fx.call("hide_lane")
	_channel_candle = null
	if visual != null:
		visual.call("set_revealed", false)


func _record_candles() -> void:
	_start_candles.clear()
	for c in candles:
		if is_instance_valid(c):
			_start_candles[(c as Node).get_instance_id()] = bool(c.call("is_lit"))


## Every arena candle back to the state it had when the fight started (silently: restore() emits nothing).
func _restore_candles() -> void:
	for c in candles:
		if not is_instance_valid(c):
			continue
		var id := (c as Node).get_instance_id()
		if _start_candles.has(id):
			c.call("restore", bool(_start_candles[id]))


func _end_window() -> void:
	_window_mult = 1.0
	if visual != null:
		visual.call("set_revealed", false)
	_enter_glide()


# --- Helpers ------------------------------------------------------------------------------------------------------

func _attack(id: String) -> Dictionary:
	var list: Variant = data.get("attacks", [])
	if list is Array:
		for a in list:
			if a is Dictionary and String((a as Dictionary).get("id", "")) == id:
				return a
	return {}


## Damage of an attack: data x horror intensity (Gentle 0.6 / Standard 1 / Intense 1.15, like the Matron).
func _damage(id: String, fallback: float) -> float:
	return float(_attack(id).get("damage", fallback)) * Combat.intensity_damage_mult(_i())


## One hit on Krystal through her health path (i-frames -> armour -> shield -> hp), knockback, impact, hitstop.
## Only Krystal (or the test stand-in) can be hurt: never companions, pets, decor or crops.
func _deal(t: Node3D, dmg: float, dir: Vector3, knock: float) -> float:
	if not _is_victim(t) or dmg <= 0.0:
		return 0.0
	var h := Combat.find_health(t)
	if h == null:
		return 0.0
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var dealt := float(h.apply_damage(dmg, self, d))
	if dealt <= 0.0:
		if t.has_method("on_hit_blocked"):
			t.call("on_hit_blocked", self, d)
		return 0.0
	if knock > 0.0 and t.has_method("knockback"):
		t.call("knockback", d, knock)
	var col: Variant = t.get("hit_color")
	HitFx.impact(Combat.aim_point(t) - d * 0.25, dealt, col if col is Color else HitFx.DEFAULT_IMPACT)
	Events.hitstop.emit(Combat.HITSTOP_HEAVY if dealt >= 15.0 else Combat.HITSTOP_LIGHT)
	return dealt


func _is_victim(t: Node) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t == target_override:
		return true
	return t.is_in_group("player") and not t.is_in_group("companion") and not t.is_in_group("enemy")


static func _is_krystal(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player") and not n.is_in_group("companion")


func _los(from: Vector3, to: Vector3, t: Node) -> bool:
	if not is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, from, to, [t], Combat.LOS_MASK)


func _player() -> Node3D:
	if target_override != null:
		return target_override if is_instance_valid(target_override) else null
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _hunt_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "loading" or Game.mode == "cutscene":
		return false
	var h := Combat.find_health(p)
	return not (h != null and bool(h.get("dead")))


func _stand_down_due(p: Node3D, dt: float) -> bool:
	if p == null or _flat(p.global_position, arena_center) > arena_radius + LEAVE_MARGIN:
		_away_t += dt
		return _away_t >= LEAVE_TIME
	_away_t = 0.0
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clamp_in_arena(p: Vector3, margin: float) -> Vector3:
	var rel := Vector3(p.x - arena_center.x, 0.0, p.z - arena_center.z)
	var r := maxf(arena_radius - margin, 1.0)
	if rel.length() > r:
		rel = rel.normalized() * r
	return Vector3(arena_center.x + rel.x, _floor_y, arena_center.z + rel.z)


func _avoid_cover(p: Vector3) -> Vector3:
	var out := p
	for c in cover:
		var cp: Vector3 = c
		var d := Vector3(out.x - cp.x, 0.0, out.z - cp.z)
		if d.length() < COVER_CLEAR:
			if d.length_squared() < 0.0001:
				d = Vector3(arena_center.x - cp.x, 0.0, arena_center.z - cp.z)
			out = Vector3(cp.x, out.y, cp.z) + d.normalized() * COVER_CLEAR
	return out


func _face_toward(p: Node3D, delta: float) -> void:
	if p == null:
		return
	_face_dir(p.global_position - global_position, clampf(delta * 5.0, 0.0, 1.0))


func _face_dir(d: Vector3, k: float) -> void:
	if Vector2(d.x, d.z).length_squared() < 0.0001:
		return
	_face_yaw = lerp_angle(_face_yaw, atan2(d.x, d.z), clampf(k, 0.0, 1.0))


## Mirrors height / facing / shadow onto the view nodes (logic never reads them back).
func _sync_view(delta: float) -> void:
	if state in ["bow", "flourish", "final_tell", "dash"]:
		_face_dir(_lane_dir, clampf(delta * 12.0, 0.0, 1.0))      # he bows / dashes along the lane
	if visual != null:
		visual.position = Vector3(0.0, hover_y, 0.0)
		visual.rotation = Vector3(0.0, _face_yaw, 0.0)
	if _fx != null:
		var show := visual != null and visual.visible and not _gone
		_fx.call("set_drop", Vector3(global_position.x, _floor_y, global_position.z), hover_y, show)


func _say_once(key: String, text: String, seconds: float) -> void:
	if _said.has(key):
		return
	_said[key] = true
	Events.say.emit(ManorLayout.VELOUR_NAME, text, seconds)


func _notice_companions() -> void:
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("notice_threat"):
			(c as Node).call("notice_threat", get_aim_point())


## Horror director: hold it quiet for the whole encounter (released on reset / defeat / leaving the tree).
func _director_hold(on: bool) -> void:
	if on == _director_held:
		return
	_director_held = on
	var d: Variant = Game.get("director")
	if d == null or not (d is Node) or not is_instance_valid(d):
		return
	if on:
		if (d as Node).has_method("hold"):
			(d as Node).call("hold", HOLD_ID)
		elif (d as Node).has_method("suppress"):
			(d as Node).call("suppress", 9999.0)
	else:
		if (d as Node).has_method("release"):
			(d as Node).call("release", HOLD_ID)
		elif (d as Node).has_method("suppress"):
			(d as Node).call("suppress", 10.0, true)


func _disconnect_candle(n: Variant) -> void:
	if n is Node and is_instance_valid(n) and (n as Node).has_signal("lit") and (n as Node).is_connected("lit", _on_candle_lit):
		(n as Node).disconnect("lit", _on_candle_lit)
