extends Node3D
## The Borrowed Choir - Chapter Two's final boss (MP §13.3, §14, §17 "Before the Choir"). Cracked hanging bells,
## carved wooden masks, harvest ribbons and dim lights around an EMPTY centre: it learned the miners' signals and
## the festival's welcomes, but it cannot make true light. Every phase is a different DECISION, not a bigger bar.
##   setup({"arena_center": Vector3, "arena_radius": 12.4, "perimeter_radius": 10.4,
##          "anchor_nodes": [lantern_anchor.gd x3], "anchors": [Vector3 x3] (fallback positions),
##          "resonators": [resonator.gd x2], "symbols": [{"id", "name", "caption"}] (taught order),
##          "arena": choir_arena node, "alert": true (start at once), "mode": "story" | "trial", "seed": int})
## (choir_arena.gd boss_params() passes exactly these; the arena spawns it through EnemyFactory.)
##
## PHASE A "False welcome" (hp 100% -> 67%): three forms drift out to stations in front of the three FIXED lantern
##   anchors. The genuine one lights the floor plate at its feet (a real light - faint always, bright while a
##   lantern burns on any anchor) and sways like something alive; false ones glow above a DARK plate and tick
##   stiffly in lockstep. Raising the lantern at an anchor resolves it (+ a bold ring round the genuine plate with
##   Settings high_visibility_cues); then point the form out (interact) or strike it. Correct = the Choir drops,
##   exposed (damage window). Wrong = that form bursts into ribbons and a telegraphed sweep follows (1.1-1.4 s mark;
##   a wrong pick's sweep never takes her below 1 hp). Waiting too long brings the same sweep as an ordinary hit.
##   Forms reshuffle every cycle (never the same genuine form twice in a row: no elimination guessing).
## PHASE B "Stolen rhythm" (67% -> 33%): it wraps itself in two protection layers in the centre and alternates
##   (a) expanding resonance rings, each with ONE marked opening shown before launch (the perimeter walk is always
##   outside their reach), and (b) short delayed strike zones marked on the floor. Wake the two fixed resonators by
##   striking their plates in the symbol order taught on the Bellmaker's Floor (choir_resonance.gd: captions, no
##   pitch, timing assist = no window at all): each drops a layer; both = exposed. At most two Borrowed Wisps
##   (enemy id borrowed_wisp, Gentle one) guard the resonators - released once per attempt, never refilled.
## PHASE C "The kept flame" (33% -> 0): false cozy lights (emissive, light nothing) compete with ONE true flame
##   anchored on a lantern-anchor hook that lights its floor sector. The hush strikes every unlit place inside the
##   ring (the lit sector and the perimeter walk are safe); raise the lantern at the true flame's anchor = exposed.
##   Exactly three exposures end the fight (choir_rules.gd: good gear only shortens the windows).
## Health (choir_rules.gd): hurt ONLY while exposed; each exposure is capped and floored, phases never bleed into
##   each other (choir_health.gd floor_hp): three correct reveals in A, one or two resonator cycles in B, three
##   kept-flame exposures in C - never a sponge (tuned for ~4-6 engaged first-encounter minutes, pending real play).
## Every committed attack has a recovery beat after it, every exposure a recovery rise. Only one Choir attack at a
##   time, and (MP §12 caps) it only starts one while the wisps' own wind-ups stay within Rules.MAX_COMMITTED
##   (Gentle: never overlapping); while committed it also holds a slot of enemy_base's shared attack-token table.
##   Rings <= 2, strike zones <= 3, no projectiles. Every hit: player group only (never companions, pets, decor),
##   line of sight from its source (no hits through walls / ceilings), ONE apply_damage through her health path.
##   The warm perimeter walk (radius >= perimeter_radius) is safe from EVERY Choir attack: the sweep and the hush
##   stop at it, the rings fade before it, strike-zone centres stay within strike_reach() (their hit area ends at it).
##   (The Borrowed Wisps are ordinary enemies with their own rules.)
## Companions: can_be_hit_by() is true only while exposed (and only for helpers inside the vault); the forms and
##   the false lights are never valid companion targets.
## Events: boss_encounter_changed(id, true/false), boss_phase_changed(id, 1/2/3) (m26 layers), boss_health_changed
##   (bar; -1 hides), boss_defeated("borrowed_choir") once. The horror director is held for the whole fight.
## VICTORY: the commit comes FIRST - bar hidden, encounter over, Events.boss_defeated -> the arena sets
##   ch2_choir_defeated and saves (if no arena listened, the boss sets the flag itself) - THEN the presentation:
##   the trapped echoes rise as gentle chimes, masks and ribbons fall harmlessly and fade. A story save with the flag
##   never spawns a live Choir again ("gone" at once); no drops (rewards belong to the quest layer / ledger).
## RESET POLICY (one rule): Krystal falls, or leaves the vault (>= LEAVE_TIME outside): the encounter resets CLEANLY
##   to the start of the phase she reached (a checkpoint) - hazards gone, wisps dismissed, anchors lowered,
##   resonators reset + re-enabled, forms / lights / layers cleared, hp back to that phase's start, bar hidden,
##   music released. Quitting / reloading: nothing about an unfinished fight is saved - a fresh Choir (phase A).
##   Mode "trial": no flags, no boss_defeated (the trial module listens to `defeated`).
## Intensity: Gentle = longer tells / windows / recoveries, one ring, one strike zone, one wisp, a wider lit sector,
##   x0.6 damage. Intense = less idle, a second ring whose opening is turned (shown in advance), the flame FEINTS
##   toward another hook before settling (a readable final swing) - never invisible, never louder.
## Sounds (existing names only): fake_lumi_chime, shade_whisper, shade_telegraph, shade_drift, shade_shriek,
##   ward_hum, dir_wrong_squeak, gloomling_flinch, checkpoint_light, brazier_light, mine_hit, hit_soft, enemy_hurt,
##   lumi_chime, ward_restore. Every meaningful one has a caption.
## QA (cheats only): --choir-phase=2|3 starts the fight in that phase.

signal defeated
signal state_changed(new_state: String)
signal phase_changed(phase: int)
signal exposure_changed(on: bool)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Rules := preload("res://src/enemies/choir/choir_rules.gd")
const ChoirHealth := preload("res://src/enemies/choir/choir_health.gd")
const Visual := preload("res://src/enemies/choir/choir_visual.gd")
const Form := preload("res://src/enemies/choir/choir_form.gd")
const Layers := preload("res://src/enemies/choir/choir_layers.gd")
const Rings := preload("res://src/enemies/choir/choir_rings.gd")
const Strikes := preload("res://src/enemies/choir/choir_strikes.gd")
const Lights := preload("res://src/enemies/choir/choir_lights.gd")
const Resonance := preload("res://src/enemies/choir/choir_resonance.gd")
const Art := preload("res://src/enemies/choir/choir_art.gd")

const BOSS_ID := "borrowed_choir"
const CLEAR_FLAG := "ch2_choir_defeated"
const WISP_ID := "borrowed_wisp"
const HOLD_ID := "choir_fight"
const HOVER_HIGH := 3.2            # veiled: its aim point sits out of every reach
const AIM_HEIGHT := 1.3
const FORM_RADIUS := 4.4           # Phase A stations: this far from the centre toward each anchor
const EXPOSE_C_RADIUS := 5.0       # Phase C: drawn down beside the true flame's anchor
const DROP_TIME := 0.6
const LEAVE_MARGIN := 3.0
const LEAVE_TIME := 3.0
const HOOK_UP := 1.15              # the true flame hangs this high on its anchor's hook
const HOOK_IN := 0.5
const LANTERN_FALLBACK_REACH := 2.6
const WISP_INSET := 1.6
const DEFAULT_ANCHOR_RADIUS := 7.0
const VICTORY_CHIME_AT := 1.3
const VICTORY_TIME := 4.0
const VULNERABLE_STATES := ["a_exposed", "b_exposed", "c_exposed"]
const COMMITTED_STATES := ["a_sweep_tele", "a_sweep", "b_ring_tele", "b_rings", "b_strike_tele", "b_strike", "c_hush_tele", "c_hush"]
const REVEAL_STATES := ["a_gather", "a_wait", "a_sweep_tele"]     # Phase A states that follow the anchors' light
const WISP_COMMITTED := ["telegraph", "sweep_wait", "sweep"]

var enemy_id: String = BOSS_ID
var boss_id: String = BOSS_ID
var mode: String = "story"
var data: Dictionary = {}
var health: Node
var visual: Node3D
var hit_radius: float = 1.2
var hit_color: Color = Color(1.0, 0.9, 0.72)
var damage_scale: float = 1.0
var arena: Node = null
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 12.4
var perimeter_radius: float = 10.4
var anchor_nodes: Array = []
var anchor_points: Array = []
var resonator_nodes: Array = []
var symbols: Array = []
var state: String = "dormant"
var state_time: float = 0.0
var phase: int = 1
var fight_started: bool = false
var auto_start: bool = false
var target_override: Node3D = null     # tests / scripted: the node treated as Krystal
var intensity_override: int = -1       # tests
var fast_defeat: bool = false          # tests: skip the victory presentation's waits
# parts
var forms: Array = []
var layers: Node3D
var rings: Node3D
var strikes: Node3D
var lights: Node3D
var resonance: RefCounted
var mark_fx: Node3D                    # sweeps / hush / ring origin (telegraph_fx.gd)
# progress / stats (tests read these)
var genuine: int = 0
var revealed: bool = false
var reveals: int = 0
var wrong_picks: int = 0
var exposures: int = 0                 # Phase C exposures (three end the fight)
var sweeps: int = 0
var hits_landed: int = 0
var wisps_released: int = 0
var flame_anchor: int = -1
var retry: bool = false

var _state_len: float = 0.0
var _window_start_hp: float = 0.0
var _window_damage: float = 0.0
var _sweep_dir: Vector3 = Vector3.FORWARD
var _sweep_wrong: bool = false
var _sweep_done: bool = false
var _strike_done: bool = false
var _hush_done: bool = false
var _hush_dir: Vector3 = Vector3.FORWARD
var _pending_expose: bool = false
var _b_rings_next: bool = true
var _b_volleys: int = 0
var _ring_gaps: Array = []
var _wisps: Array = []
var _wisps_out: bool = false
var _prev_genuine: int = -1
var _check_t: float = 0.0
var _away_t: float = 0.0
var _hold: bool = false
var _gone: bool = false
var _defeat_started: bool = false
var _initialized: bool = false
var _seeded: bool = false
var _told: Dictionary = {}
var _glide_from: Vector3 = Vector3.ZERO
var _glide_to_pos: Vector3 = Vector3.ZERO
var _glide_t: float = 0.0
var _glide_len: float = 0.0
var _rng := RandomNumberGenerator.new()
var _victory_t: float = 0.0
var _victory_step: int = 0


func setup(params: Dictionary) -> void:
	var c: Variant = params.get("arena_center")
	if c is Vector3:
		arena_center = c
	arena_radius = maxf(float(params.get("arena_radius", arena_radius)), 4.0)
	perimeter_radius = clampf(float(params.get("perimeter_radius", arena_radius - 2.0)), 2.5, arena_radius - 0.5)
	var ar: Variant = params.get("arena")
	if ar is Node:
		arena = ar
	anchor_nodes.clear()
	for a in params.get("anchor_nodes", []):
		if is_instance_valid(a) and a is Node3D:
			anchor_nodes.append(a)
	anchor_points.clear()
	for p in params.get("anchors", []):
		if p is Vector3:
			anchor_points.append(p)
	resonator_nodes.clear()
	for r in params.get("resonators", []):
		if is_instance_valid(r) and r is Node:
			resonator_nodes.append(r)
	symbols = (params.get("symbols", []) as Array).duplicate(true) if params.get("symbols") is Array else []
	mode = "trial" if String(params.get("mode", mode)) == "trial" else "story"
	boss_id = String(params.get("boss_id", boss_id))
	auto_start = bool(params.get("alert", auto_start))
	damage_scale = float(params.get("damage_scale", damage_scale))
	if params.has("seed"):
		_rng.seed = int(params["seed"])
		_seeded = true


func _ready() -> void:
	data = ItemDB.enemy(BOSS_ID)
	if not _seeded:
		_rng.randomize()
	health = ChoirHealth.new()
	health.name = "Health"
	health.max_hp = float(data.get("hp", 540.0))
	health.invulnerable = true
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	Events.settings_changed.connect(_on_settings_changed)
	Events.player_died.connect(_on_player_died)
	Events.flag_set.connect(_on_flag_set)
	Events.boss_defeated.connect(_on_any_boss_defeated)
	HitFx.ensure_hitstop()
	_initialize()


func _exit_tree() -> void:
	_release_token()
	_director(false)          # freed mid-fight (trial teardown, debug): never leave the horror director held
	if fight_started and not _defeat_started and resonance != null:
		resonance.call("release")     # and never leave the vault's plates disabled (the arena's default state)


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if is_story() and bool(GameState.get_flag(CLEAR_FLAG)):
		# A won story save: the vault stays quiet (no replayed fight, nothing granted twice).
		_gone = true
		state = "gone"
		visible = false
		return
	add_to_group("enemy")
	_build_parts()
	for a in anchor_nodes:
		if (a as Node).has_signal("raised") and not (a as Node).is_connected("raised", _on_anchor_raised):
			(a as Node).connect("raised", _on_anchor_raised)
	resonance = Resonance.new()
	resonance.call("setup", resonator_nodes, taught_sequence())
	resonance.connect("layer_down", _on_layer_down)
	global_position = _veil_pos(arena_center)
	_enter("dormant")
	if auto_start:
		var p := _player()
		if p != null and _hunt_allowed(p):
			start_fight()


func _build_parts() -> void:
	visual = Visual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.set_state("veiled")
	mark_fx = TelegraphFx.new()
	mark_fx.name = "ChoirMark"
	add_child(mark_fx)
	layers = Layers.new()
	layers.name = "Layers"
	add_child(layers)
	rings = Rings.new()
	rings.name = "Rings"
	add_child(rings)
	rings.set("center", arena_center)
	strikes = Strikes.new()
	strikes.name = "Strikes"
	add_child(strikes)
	lights = Lights.new()
	lights.name = "KeptFlame"
	add_child(lights)
	var holder := Node3D.new()
	holder.name = "Forms"
	holder.top_level = true
	add_child(holder)
	holder.global_transform = Transform3D.IDENTITY
	for i in 3:
		var f: Node3D = Form.new()
		f.name = "Form_%d" % i
		f.setup({"index": i, "picker": Callable(self, "pick_form"), "text_func": Callable(self, "form_prompt")})
		holder.add_child(f)
		f.call("hide_form")
		forms.append(f)
	_apply_hv()


# --- Public queries --------------------------------------------------------------------------------------------

func is_story() -> bool:
	return mode != "trial"


func is_gone() -> bool:
	return _gone


func is_defeated() -> bool:
	return _defeat_started or _gone


func intensity() -> int:
	return intensity_override if intensity_override >= 0 else Combat.current_intensity()


func is_threatening() -> bool:
	return fight_started and not _gone and not _defeat_started


func is_vulnerable() -> bool:
	return state in VULNERABLE_STATES and not _defeat_started and not _gone


func is_committed() -> bool:
	return state in COMMITTED_STATES


## Spec §9: false unless exposed; helpers (companions) only from inside the vault; other enemies never.
func can_be_hit_by(source: Node) -> bool:
	if not is_vulnerable():
		return false
	if source == null or not is_instance_valid(source) or not (source is Node3D):
		return true
	if _is_krystal(source):
		return true
	if source.is_in_group("enemy"):
		return false
	return Rules.flat((source as Node3D).global_position, arena_center) <= arena_radius + 1.0


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * AIM_HEIGHT


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func hit_flash(duration: float = 0.11) -> void:
	if visual != null:
		HitFx.flash(visual, duration)


func floor_y() -> float:
	return arena_center.y


func floor_center() -> Vector3:
	return arena_center


## The taught symbol order (the arena passes data/works_layout_deep.gd bell_symbols(), in teaching order).
func taught_sequence() -> Array:
	var out: Array = []
	for s in symbols:
		if s is Dictionary and (s as Dictionary).has("id"):
			out.append(String(s["id"]))
		elif s is String:
			out.append(String(s))
	if out.is_empty() and not resonator_nodes.is_empty() and (resonator_nodes[0] as Node).has_method("symbol_ids"):
		out = (resonator_nodes[0] as Node).call("symbol_ids")
	return out


func symbol_names() -> String:
	var names: Array = []
	for s in symbols:
		if s is Dictionary:
			names.append(String((s as Dictionary).get("name", String((s as Dictionary).get("id", "")).capitalize())))
	return ", ".join(PackedStringArray(names))


## World positions of the three lantern anchors (the nodes when the arena gave them, else fixed points, else a
## default triangle at DEFAULT_ANCHOR_RADIUS).
func anchor_positions() -> Array:
	var out: Array = []
	for a in anchor_nodes:
		if is_instance_valid(a) and a is Node3D:
			out.append((a as Node3D).global_position if (a as Node3D).is_inside_tree() else (a as Node3D).position)
	if out.is_empty():
		out = anchor_points.duplicate()
	if out.is_empty():
		for deg in [-150.0, -30.0, 90.0]:
			var r := deg_to_rad(deg)
			out.append(arena_center + Vector3(cos(r), 0.0, sin(r)) * DEFAULT_ANCHOR_RADIUS)
	return out


func station(i: int) -> Vector3:
	var pts := anchor_positions()
	var a: Vector3 = pts[clampi(i, 0, pts.size() - 1)]
	var s := arena_center + Rules.bearing(arena_center, a) * FORM_RADIUS
	s.y = floor_y()
	return s


func hook_pos(i: int) -> Vector3:
	var pts := anchor_positions()
	var a: Vector3 = pts[clampi(i, 0, pts.size() - 1)]
	return Vector3(a.x, floor_y(), a.z) + Rules.bearing(a, arena_center) * HOOK_IN + Vector3.UP * HOOK_UP


func lit_arc() -> float:
	return Rules.pick(Rules.LIT_ARC, intensity())


func lit_dir() -> Vector3:
	var pts := anchor_positions()
	if flame_anchor < 0 or flame_anchor >= pts.size():
		return Vector3.FORWARD
	return Rules.bearing(arena_center, pts[flame_anchor])


func sweep_arc() -> float:
	return Rules.pick(Rules.SWEEP_ARC, intensity())


func sweep_dir() -> Vector3:
	return _sweep_dir


func ring_max_radius() -> float:
	return perimeter_radius - Rules.RING_BAND * 0.5 - 0.4


## Farthest centre of a strike zone: its hit area (marked radius + body) ends where the perimeter walk begins, so
## the warm perimeter band stays safe from every Choir attack (sweep, rings, strike zones, hush).
func strike_reach() -> float:
	return maxf(perimeter_radius - Rules.STRIKE_RADIUS - Strikes.BODY, 0.5)


func wisps_alive() -> int:
	_prune_wisps()
	return _wisps.size()


func wisp_nodes() -> Array:
	_prune_wisps()
	return _wisps.duplicate()


func window_left() -> float:
	return maxf(_state_len - state_time, 0.0) if is_vulnerable() else 0.0


## Phase for a health value (choir_rules.gd): 1 above two thirds, 2 above one third, else 3.
static func phase_for(hp: float, max_hp: float) -> int:
	return Rules.phase_for(hp, max_hp)


# --- Encounter --------------------------------------------------------------------------------------------------

func start_fight() -> void:
	if fight_started or _gone or _defeat_started or not _initialized:
		return
	fight_started = true
	_away_t = 0.0
	_debug_phase_jump()
	_emit_health()
	Events.boss_encounter_changed.emit(boss_id, true)
	Events.boss_phase_changed.emit(boss_id, phase)
	_director(true)
	visual.set_state("shriek")
	Art.sfx("fake_lumi_chime", get_aim_point(), -4.0)
	Art.sfx("shade_whisper", get_aim_point(), -8.0)
	Art.caption("[a hundred borrowed welcomes echo round the empty centre - none of them quite right]")
	if retry:
		_hint("choir_retry", "The Choir picks up its song where you left it. Leaving the Hushed Works lets it recover fully.")
	_notice_companions()
	_enter("intro", Rules.T_INTRO_RETRY if retry else Rules.T_INTRO)


## QA only (cheats): --choir-phase=2|3 begins the fight at that phase (real-input runs, screenshots).
func _debug_phase_jump() -> void:
	if phase != 1 or not Debug.is_cheat_allowed() or not Debug.has_arg("choir-phase"):
		return
	var n := clampi(int(Debug.arg("choir-phase", "1")), 1, 3)
	if n > 1:
		phase = n
		health.set_hp(Rules.phase_start_hp(n, health.max_hp))


## Clean reset to the start of the phase reached (see RESET POLICY).
func reset_fight() -> void:
	if _gone or _defeat_started or not _initialized:
		return
	if not fight_started and state == "dormant":
		return            # nothing is under way (e.g. she fell elsewhere before the fight began)
	_clear_hazards()
	_dismiss_wisps()
	if resonance != null:
		resonance.call("release")
	_lower_anchors()
	lights.call("clear")
	layers.call("set_count", 0)
	for f in forms:
		(f as Node).call("hide_form")
	_pending_expose = false
	flame_anchor = -1
	exposures = 0
	revealed = false
	_away_t = 0.0
	_glide_len = 0.0
	_wisps_out = false
	health.set("floor_hp", 0.0)
	health.invulnerable = true
	if fight_started:
		fight_started = false
		retry = true
		Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
		Events.boss_encounter_changed.emit(boss_id, false)
		_director(false)
	health.set_hp(Rules.phase_start_hp(phase, health.max_hp))
	global_position = _veil_pos(arena_center)
	visual.set_state("veiled")
	_enter("dormant")


## Quietly gone without a victory (the flag was set elsewhere, e.g. a debug clear or a load): hides the bar, ends
## the encounter, frees helpers - never emits boss_defeated.
func dismiss() -> void:
	if _gone:
		return
	var was := fight_started
	_defeat_started = true
	_gone = true
	_clear_hazards()
	_dismiss_wisps()
	if resonance != null:
		resonance.call("release")
	if lights != null:
		lights.call("clear")
	if layers != null:
		layers.call("set_count", 0)
	for f in forms:
		(f as Node).call("hide_form")
	fight_started = false
	if was:
		Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
		Events.boss_encounter_changed.emit(boss_id, false)
		_director(false)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	visible = false
	state = "gone"
	state_changed.emit("gone")


# --- State machine ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _gone or not _initialized:
		return
	if _defeat_started:
		_tick_victory(delta)
		return
	state_time += delta
	_glide_step(delta)
	_check_t -= delta
	var check := _check_t <= 0.0
	if check:
		_check_t = 0.2
	var p := _player()
	if fight_started:
		resonance.call("tick", delta)
		if _stand_down(p, delta):
			reset_fight()
			return
	for f in forms:
		(f as Node).call("tick", delta)
	if phase >= 3 and lights != null:
		lights.call("tick", delta)
	if state in REVEAL_STATES:
		_update_reveal(p)
	match state:
		"dormant":
			if check and p != null and _hunt_allowed(p) and _inside(p.global_position, perimeter_radius - 0.2):
				start_fight()
		"intro", "phase_shriek":
			if state_time >= _state_len:
				_begin_phase_loop()
		# --- A
		"a_gather":
			if state_time >= _state_len:
				for f in forms:
					if not bool((f as Node).get("folded")):
						(f as Node).call("set_pickable", true)
				_enter("a_wait", Rules.assisted(Rules.pick(Rules.T_WAIT, intensity()), _assist()))
		"a_wait":
			if state_time >= _state_len:
				_begin_sweep(false)
		"a_sweep_tele":
			_track_sweep(p)
			if state_time >= _state_len:
				_enter("a_sweep", Rules.T_SWEEP)
				_resolve_sweep(p)
		"a_sweep":
			if state_time >= _state_len:
				mark_fx.call("hide_mark")
				_a_recover()
		"a_recover":
			if state_time >= _state_len:
				_a_gather()
		"a_exposed", "b_exposed", "c_exposed":
			if state_time >= _state_len:
				_end_window()
		# --- B
		"b_gather":
			if state_time >= _state_len:
				_enter("b_idle", _b_idle_len())
		"b_idle":
			if _b_ready_to_expose():
				_expose_b()
			elif state_time >= _state_len and _may_commit():
				if _b_rings_next:
					_begin_rings(p)
				else:
					_begin_strikes(p)
				_b_rings_next = not _b_rings_next
		"b_ring_tele":
			if _b_ready_to_expose():
				_expose_b()
				return
			mark_fx.call("set_progress", clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0), true)
			if state_time >= _state_len:
				_launch_rings()
		"b_rings":
			rings.call("tick", delta)
			_ring_hits(p)
			if _b_ready_to_expose():
				_expose_b()
			elif int(rings.call("active_count")) == 0:
				_b_volleys += 1
				_enter("b_idle", _b_idle_len())
		"b_strike_tele":
			if _b_ready_to_expose():
				_expose_b()
				return
			strikes.call("set_progress", clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0), true)
			if state_time >= _state_len:
				_enter("b_strike", Rules.T_STRIKE)
				_resolve_strikes(p)
		"b_strike":
			if state_time >= _state_len:
				strikes.call("clear")
				_b_volleys += 1
				if _b_ready_to_expose():
					_expose_b()
				else:
					_enter("b_idle", _b_idle_len())
		"b_reform":
			if state_time >= _state_len:
				_enter("b_idle", _b_idle_len())
		# --- C
		"c_gather":
			if state_time >= _state_len:
				_c_settle()
		"c_settle":
			if state_time >= _state_len:
				_c_settled()
				_begin_hush()
		"c_hush_tele":
			_lantern_fallback_c(p)
			mark_fx.call("set_progress", clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0), true)
			if state_time >= _state_len:
				_enter("c_hush", Rules.T_HUSH)
				_resolve_hush(p)
		"c_hush":
			if state_time >= _state_len:
				mark_fx.call("hide_mark")
				if _pending_expose:
					_expose_c()
				else:
					_enter("c_open", Rules.assisted(Rules.pick(Rules.T_OPEN, intensity()), _assist()))
		"c_open":
			_lantern_fallback_c(p)
			if state == "c_open" and state_time >= _state_len:
				_c_settle()
		"c_recover":
			if state_time >= _state_len:
				_c_settle()


func _enter(s: String, length: float = 0.0) -> void:
	state = s
	state_time = 0.0
	_state_len = length
	health.invulnerable = not (s in VULNERABLE_STATES)
	if s in COMMITTED_STATES:
		Base._attackers[get_instance_id()] = true
	else:
		_release_token()
	state_changed.emit(s)


func _release_token() -> void:
	if Base._attackers.has(get_instance_id()):
		Base._attackers.erase(get_instance_id())


func _begin_phase_loop() -> void:
	match phase:
		1:
			_a_gather()
		2:
			_b_gather()
		_:
			_c_gather()


func _change_phase(np: int) -> void:
	phase = clampi(np, 1, Rules.PHASES)
	_clear_hazards()
	for f in forms:
		(f as Node).call("fold_away")
	if phase >= 3:
		_dismiss_wisps()
		resonance.call("disable")
		layers.call("set_count", 0)
	Events.boss_phase_changed.emit(boss_id, phase)
	phase_changed.emit(phase)
	visual.set_state("shriek")
	_glide_to(_veil_pos(arena_center), 0.8)
	Art.sfx("shade_shriek", get_aim_point(), -8.0)
	Art.caption("[the borrowed voices tangle and change their song]")
	Events.camera_shake.emit(0.25, 0.4)
	_enter("phase_shriek", Rules.T_SHRIEK)


# --- Phase A: False welcome -----------------------------------------------------------------------------------

func _a_gather() -> void:
	mark_fx.call("hide_mark")
	resonance.call("disable")
	var pts := anchor_positions()
	var n := mini(pts.size(), forms.size())
	var g := _rng.randi_range(0, n - 1)
	if n > 1 and g == _prev_genuine:
		g = (g + 1 + _rng.randi_range(0, n - 2)) % n
	genuine = g
	_prev_genuine = g
	revealed = false
	var from := arena_center + Vector3.UP * 0.2
	var dur := Rules.assisted(Rules.pick(Rules.T_GATHER, intensity()), _assist())
	for i in forms.size():
		var f: Node = forms[i]
		if i >= n:
			f.call("hide_form")
			continue
		var dir := Rules.bearing(arena_center, pts[i])
		f.call("set_genuine", i == genuine)
		f.call("set_revealed", false)
		f.call("drift", from, station(i), dur, dir)
		f.call("set_pickable", false)
	visual.set_state("hidden")
	_glide_to(_veil_pos(arena_center), 0.3)
	if not _told.has("a_gather"):
		_told["a_gather"] = true
		Art.caption("[three welcoming shapes drift out of the empty centre]")
		_hint("choir_forms", "Three forms, one true. Raise your lantern at an anchor ({interact}), then point out the form whose light falls on the floor.")
	Art.sfx("shade_drift", arena_center + Vector3.UP, -8.0)
	_enter("a_gather", dur)


## Phase A reveal: any lantern anchor raised (or, with no anchor nodes, her own lit lantern inside the ring).
func revealed_now() -> bool:
	var any_node := false
	for a in anchor_nodes:
		if is_instance_valid(a) and a is Node:
			any_node = true
			if bool((a as Node).call("is_raised")):
				return true
	if any_node:
		return false
	var p := _player()
	if p == null:
		return false
	var lit: Variant = p.get("lantern_on")
	return lit is bool and lit and Rules.flat(p.global_position, arena_center) <= perimeter_radius


func _update_reveal(_p: Node3D) -> void:
	var now := revealed_now()
	if now == revealed:
		return
	revealed = now
	for f in forms:
		(f as Node).call("set_revealed", now)
	if now and not _told.has("a_reveal"):
		_told["a_reveal"] = true
		Art.caption("[the anchor's light falls across the forms - one of them lights the floor at its feet]")


## Interaction prompt of a form (choir_form.gd text_func).
func form_prompt(_i: int) -> Dictionary:
	if revealed:
		return {"text": "Point out this form", "enabled": true}
	return {"text": "Raise your lantern at an anchor first, then watch the floor", "enabled": false}


## Krystal points out form `i` (interact or strike). Returns "correct", "wrong", "not_revealed" or "idle".
func pick_form(i: int, _source: Node = null) -> String:
	if _gone or _defeat_started or state != "a_wait":
		return "idle"
	if i < 0 or i >= forms.size() or bool((forms[i] as Node).get("folded")):
		return "idle"
	revealed = revealed_now()
	if not revealed:
		_hint("choir_raise", "Raise your lantern at one of the three anchors first - then the true form's floor lights up.")
		return "not_revealed"
	if i == genuine:
		_expose_a()
		return "correct"
	wrong_picks += 1
	(forms[i] as Node).call("burst")
	Art.sfx("dir_wrong_squeak", (forms[i] as Node3D).global_position + Vector3.UP, -4.0)
	Art.caption("[the false form bursts into ribbons - the borrowed bells swing back in answer]")
	_begin_sweep(true)
	return "wrong"


func _expose_a() -> void:
	reveals += 1
	var at := station(genuine)
	for i in forms.size():
		var f: Node = forms[i]
		if i == genuine:
			f.call("hide_form")
		else:
			f.call("fold_away")
	global_position = Vector3(at.x, floor_y() + HOVER_HIGH * 0.6, at.z)
	_glide_to(at, DROP_TIME)
	visual.set_state("exposed")
	Art.sfx("gloomling_flinch", at + Vector3.UP, -3.0)
	Art.sfx("checkpoint_light", at + Vector3.UP, -6.0)
	Art.caption("[the genuine form's mask slips - the Choir sinks, exposed]")
	_begin_window("a_exposed", Rules.assisted(Rules.pick(Rules.T_WINDOW_A, intensity()), _assist()))


func _begin_sweep(wrong: bool) -> void:
	_sweep_wrong = wrong
	_sweep_done = false
	var p := _player()
	_sweep_dir = Rules.bearing(arena_center, p.global_position if p != null else arena_center + Vector3.FORWARD, Vector3.FORWARD)
	for f in forms:
		(f as Node).call("set_pickable", false)
	mark_fx.call("show_arc", arena_center, _sweep_dir, perimeter_radius, sweep_arc(), TelegraphFx.WARN)
	Art.sfx("shade_telegraph", arena_center + Vector3.UP * 2.0, -4.0)
	if not wrong:
		Art.caption("[the borrowed bells swing back - a sweep is coming]")
	_hint("choir_sweep", "A sweep is marked on the floor. Step out of the wedge - the perimeter walk is always outside it.")
	_enter("a_sweep_tele", Rules.tell(Rules.T_SWEEP_TELE, intensity(), _assist()))


func _track_sweep(p: Node3D) -> void:
	var locked := state_time >= _state_len * 0.6
	if not locked and p != null:
		_sweep_dir = Rules.bearing(arena_center, p.global_position, _sweep_dir)
		mark_fx.call("move_arc", arena_center, _sweep_dir)
	mark_fx.call("set_progress", clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0), locked)


## Is `pos` inside the marked sweep (the same numbers the mark shows)?
func in_sweep(pos: Vector3) -> bool:
	if absf(pos.y - floor_y()) > 1.6:
		return false
	return TelegraphFx.in_sector(arena_center, _sweep_dir, perimeter_radius, sweep_arc(), pos)


func _resolve_sweep(p: Node3D) -> void:
	if _sweep_done:
		return
	_sweep_done = true
	sweeps += 1
	Art.sfx("shade_drift", arena_center + _sweep_dir * 4.0 + Vector3.UP, -2.0)
	if is_inside_tree():
		HitFx.burst(arena_center + _sweep_dir * 5.0 + Vector3.UP * 0.6, Color(0.95, 0.8, 0.55), 12, 3.2, 0.9, -2.0, 0.5, 90.0)
	if p == null or not _valid_victim(p) or not _hunt_allowed(p):
		return
	if not in_sweep(p.global_position):
		return
	if not _los(arena_center + Vector3.UP * 0.8, p):
		return
	_hit(p, _attack_damage("false_welcome"), Rules.bearing(arena_center, p.global_position, _sweep_dir), _knock(), not _sweep_wrong)


func _a_recover() -> void:
	for f in forms:
		if not bool((f as Node).get("folded")):
			(f as Node).call("fold_away")
	visual.set_state("hidden")
	_glide_to(_veil_pos(arena_center), 0.6)
	_enter("a_recover", Rules.assisted(Rules.pick(Rules.T_RECOVER_A, intensity()), _assist()))


# --- Phase B: Stolen rhythm ---------------------------------------------------------------------------------------

func _b_gather() -> void:
	for f in forms:
		(f as Node).call("hide_form")
	visual.set_state("veiled")
	_glide_to(_veil_pos(arena_center), 0.8)
	layers.call("set_count", 2)
	resonance.call("begin")
	_b_rings_next = true
	_b_volleys = 0
	_spawn_wisps()
	Art.caption("[the Choir wraps itself in borrowed bells; two resonators wait at the edges of the vault]")
	var order := symbol_names()
	_hint("choir_resonators", "Wake both resonators: strike their plates in the Bellmaker's order%s. Each one drops a ring of bells." % ((" (" + order + ")") if order != "" else ""))
	_enter("b_gather", Rules.T_B_GATHER)


func _b_idle_len() -> float:
	return Rules.assisted(Rules.pick(Rules.T_B_IDLE, intensity()), _assist())


## Both resonators ringing true (or, with no resonators at all in this arena, two survived volleys).
func _b_ready_to_expose() -> bool:
	if phase != 2:
		return false
	if bool(resonance.call("valid")):
		return bool(resonance.call("all_active"))
	return _b_volleys >= 2


func _on_layer_down(_resonator_id: String, count: int) -> void:
	if phase != 2 or not fight_started or state in VULNERABLE_STATES:
		return
	layers.call("drop_one")
	Art.sfx("checkpoint_light", get_aim_point(), -4.0)
	if count < 2:
		Art.caption("[one ring of borrowed bells falls silent - one more resonator to wake]")


func _may_commit() -> bool:
	return Rules.may_commit(intensity(), committed_wisps())


func committed_wisps() -> int:
	var n := 0
	for w in _wisps:
		if is_instance_valid(w) and w is Node:
			var s: Variant = (w as Node).get("state")
			if s is String and String(s) in WISP_COMMITTED:
				n += 1
	return n


func _begin_rings(p: Node3D) -> void:
	var i := intensity()
	var assist := _assist()
	var n := mini(Rules.picki(Rules.RINGS_PER_VOLLEY, i), Rules.MAX_RINGS)
	var toward := Rules.bearing(arena_center, p.global_position if p != null else arena_center + Vector3.FORWARD, Vector3.FORWARD)
	# the opening is placed where she can use it: within reach of her side of the ring
	var gap_dir := toward.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-70.0, 70.0)))
	var deg := Rules.ring_gap(i, assist)
	_ring_gaps.clear()
	for k in n:
		var d := gap_dir
		if i >= 2 and k == 1:
			d = gap_dir.rotated(Vector3.UP, deg_to_rad(Rules.INTENSE_GAP_SHIFT * (1.0 if _rng.randf() < 0.5 else -1.0)))
		_ring_gaps.append({"dir": d, "deg": deg})
	rings.set("center", arena_center)
	rings.call("preview", _ring_gaps, ring_max_radius())
	mark_fx.call("show_ring", arena_center, Rules.RING_START, TelegraphFx.DANGER)
	visual.set_state("tele")
	Art.sfx("ward_hum", get_aim_point(), -4.0)
	Art.caption("[a ring of stolen rhythm gathers - find its lit opening, or keep to the edge]")
	_hint("choir_rings", "Rings roll outward from the Choir. Stand in the lit opening, keep to the perimeter walk, or dodge through.")
	_enter("b_ring_tele", Rules.tell(Rules.T_RING_TELE, i, assist))


func _launch_rings() -> void:
	mark_fx.call("hide_mark")
	var i := intensity()
	var assist := _assist()
	var speed := Rules.ring_speed(i, assist)
	for k in _ring_gaps.size():
		var g: Dictionary = _ring_gaps[k]
		rings.call("launch", arena_center, g["dir"], float(g["deg"]), speed, Rules.RING_START, ring_max_radius(),
			Rules.assisted(Rules.RING_SPACING, assist) * float(k), k)
	visual.set_state("veiled")
	Art.sfx("shade_drift", get_aim_point(), -4.0)
	_enter("b_rings", 0.0)


func _ring_hits(p: Node3D) -> void:
	if p == null or not _valid_victim(p) or not _hunt_allowed(p):
		return
	if absf(p.global_position.y - floor_y()) > 1.5:
		return
	var slots: Array = rings.call("overlapping", p.global_position, perimeter_radius)
	for s in slots:
		rings.call("mark_hit", int(s))
		if _los(arena_center + Vector3.UP * 0.6, p):
			_hit(p, _attack_damage("rings"), Rules.bearing(arena_center, p.global_position), _knock() * 0.7, true)


func _begin_strikes(p: Node3D) -> void:
	var i := intensity()
	var base := p.global_position if p != null else arena_center
	base = _clamp_inside(base, strike_reach())
	var pts: Array = [base]
	var start := _rng.randf_range(0.0, TAU)
	var count := Rules.strike_count(i)
	for k in range(1, count):
		var ang := start + TAU * float(k) / float(maxi(count - 1, 1))
		var q := base + Vector3(cos(ang), 0.0, sin(ang)) * Rules.STRIKE_SPREAD
		pts.append(_clamp_inside(q, strike_reach()))
	strikes.call("place", pts, Rules.STRIKE_RADIUS)
	_strike_done = false
	visual.set_state("tele")
	Art.sfx("shade_telegraph", base + Vector3.UP * 2.0, -4.0)
	Art.caption("[bells toll overhead - the marked spots will be struck]")
	_enter("b_strike_tele", Rules.tell(Rules.T_STRIKE_DELAY, i, _assist()))


func _resolve_strikes(p: Node3D) -> void:
	if _strike_done:
		return
	_strike_done = true
	strikes.call("strike_fx")
	visual.set_state("veiled")
	Art.sfx("mine_hit", arena_center + Vector3.UP, -4.0)
	if p == null or not _valid_victim(p) or not _hunt_allowed(p):
		return
	if Rules.flat(p.global_position, arena_center) >= perimeter_radius:
		return            # the perimeter walk is safe from every Choir attack (the zones never reach it)
	if not bool(strikes.call("hits", p.global_position)):
		return
	var from := _nearest_point(strikes.get("points"), p.global_position) + Vector3.UP * 3.0
	if not _los(from, p):
		return
	_hit(p, _attack_damage("rings"), Rules.bearing(arena_center, p.global_position), _knock(), true)


func _expose_b() -> void:
	_clear_hazards()
	layers.call("set_count", 0)
	visual.set_state("exposed")
	_glide_to(arena_center, DROP_TIME)
	Art.sfx("ward_restore", arena_center + Vector3.UP, -4.0)
	Art.caption("[both resonators ring true - the borrowed bells fall silent and the Choir sinks, exposed]")
	_begin_window("b_exposed", Rules.assisted(Rules.pick(Rules.T_WINDOW_B, intensity()), _assist()))


func _b_reform() -> void:
	resonance.call("begin")
	layers.call("set_count", 2)
	visual.set_state("veiled")
	_glide_to(_veil_pos(arena_center), 0.8)
	_b_volleys = 0
	Art.caption("[the Choir gathers its borrowed bells again - wake the resonators once more]")
	_enter("b_reform", Rules.assisted(Rules.T_B_REFORM, _assist()))


func _spawn_wisps() -> void:
	if _wisps_out:
		return
	_wisps_out = true
	_prune_wisps()
	var cap := Rules.wisp_cap(intensity())
	if cap <= 0 or not Factory.can_spawn(WISP_ID):
		return
	var parent := get_parent()
	if parent == null:
		return
	var spots: Array = []
	for r in resonator_nodes:
		if is_instance_valid(r) and r is Node3D:
			var rp := (r as Node3D).global_position if (r as Node3D).is_inside_tree() else (r as Node3D).position
			spots.append(Vector3(rp.x, floor_y(), rp.z) + Rules.bearing(rp, arena_center) * WISP_INSET)
	if spots.is_empty():
		spots = [arena_center + Vector3(-perimeter_radius + WISP_INSET, 0.0, 0.0), arena_center + Vector3(perimeter_radius - WISP_INSET, 0.0, 0.0)]
	for k in cap:
		if _wisps.size() >= cap:
			break
		var pos: Vector3 = spots[k % spots.size()]
		var w: Node = Factory.spawn(WISP_ID, parent, Transform3D(Basis.IDENTITY, pos),
			{"home": pos, "wander_radius": 2.5, "alert": true, "no_drops": true})
		if w == null:
			continue
		if target_override != null:
			w.set("target_override", target_override)
		_wisps.append(w)
		wisps_released += 1
	if not _wisps.is_empty():
		Art.caption("[small masked lights slip out to guard the resonators]")


func _dismiss_wisps() -> void:
	for w in _wisps:
		if is_instance_valid(w) and w is Node and not (w as Node).is_queued_for_deletion():
			if (w as Node).is_inside_tree() and w is Node3D:
				HitFx.burst((w as Node3D).global_position + Vector3.UP, Color(1.0, 0.78, 0.5), 8, 1.4, 0.8, -0.3, 0.8, 160.0)
			(w as Node).queue_free()
	_wisps.clear()


func _prune_wisps() -> void:
	var keep: Array = []
	for w in _wisps:
		if is_instance_valid(w) and w is Node and not (w as Node).is_queued_for_deletion():
			var h: Variant = (w as Node).get("health")
			if is_instance_valid(h) and h is Node and bool((h as Node).get("dead")):
				continue
			keep.append(w)
	_wisps = keep


# --- Phase C: The kept flame ------------------------------------------------------------------------------------

func _c_gather() -> void:
	_dismiss_wisps()
	resonance.call("disable")
	layers.call("set_count", 0)
	for f in forms:
		(f as Node).call("hide_form")
	lights.call("begin", Rules.picki(Rules.FALSE_LIGHTS, intensity()), arena_center)
	visual.set_state("veiled")
	_glide_to(_veil_pos(arena_center), 0.8)
	flame_anchor = -1
	Art.caption("[warm, cozy lights bloom around the vault - only one flame hangs from a hook]")
	_hint("choir_flame", "Only the true flame lights the floor around its anchor. Stand in its light when the hush comes, then raise your lantern at that anchor.")
	_enter("c_gather", Rules.T_C_GATHER)


func _c_settle() -> void:
	_pending_expose = false
	mark_fx.call("hide_mark")
	lights.call("gutter_false", false)
	var pts := anchor_positions()
	var n := pts.size()
	var k := _rng.randi_range(0, n - 1)
	if n > 1 and k == flame_anchor:
		k = (k + 1 + _rng.randi_range(0, n - 2)) % n
	var via := Vector3.INF
	if intensity() >= 2 and n > 1:
		var j := (k + 1 + _rng.randi_range(0, n - 2)) % n
		via = hook_pos(j)
	var dur := Rules.assisted(Rules.pick(Rules.T_SETTLE, intensity()), _assist())
	lights.call("move_flame", lights.call("flame_position"), hook_pos(k), dur, via)
	flame_anchor = k
	# the false cozy lights hover over the OTHER sectors (inviting, and dark underneath)
	var fl: Array = []
	for idx in n:
		if idx != k:
			fl.append(arena_center + Rules.bearing(arena_center, pts[idx]) * 4.6)
	fl.append(arena_center - Rules.bearing(arena_center, pts[k]) * 3.0)
	lights.call("place_false", fl)
	visual.set_state("veiled")
	_glide_to(_veil_pos(arena_center), 0.6)
	Art.sfx("fake_lumi_chime", arena_center + Vector3.UP * 2.0, -8.0)
	_enter("c_settle", dur)


func _c_settled() -> void:
	var pts := anchor_positions()
	lights.call("settle", pts[flame_anchor], hook_pos(flame_anchor), lit_dir(), lit_arc(), perimeter_radius)
	Art.sfx("brazier_light", hook_pos(flame_anchor), -6.0)
	Art.caption("[one flame settles on an anchor hook - its light pools on the floor]")
	_free_flame_hook()


## A lantern already burning on the hook the flame just settled on, raised BEFORE the flame chose it (a guess
## during an Intense feint, or a leftover from a wrong anchor) does not count - but it must not lock her out
## either: a raised anchor refuses a new raise until it burns out (up to 8-16 s, longer than the open wait).
## It is lowered here, so one press raises it again and exposes the Choir after the hush.
func _free_flame_hook() -> void:
	if _pending_expose or flame_anchor < 0 or flame_anchor >= anchor_nodes.size():
		return
	var a: Variant = anchor_nodes[flame_anchor]
	if not is_instance_valid(a) or not (a is Node) or not (a as Node).has_method("is_raised") or not (a as Node).has_method("lower"):
		return
	if bool((a as Node).call("is_raised")):
		(a as Node).call("lower")
		Art.caption("[the kept flame settles on the hook you lit - raise your lantern there again]")


func _begin_hush() -> void:
	_hush_done = false
	_hush_dir = lit_dir()
	mark_fx.call("show_arc", arena_center, -_hush_dir, perimeter_radius, 360.0 - lit_arc(), TelegraphFx.DANGER)
	visual.set_state("tele")
	Art.sfx("shade_telegraph", arena_center + Vector3.UP * 2.0, -4.0)
	Art.caption("[the false lights hush - every unlit place inside the ring will be struck]")
	_enter("c_hush_tele", Rules.tell(Rules.T_HUSH_TELE, intensity(), _assist()))


## Is `pos` inside the marked hush (everything inside the perimeter walk except the true flame's sector)?
func in_hush(pos: Vector3) -> bool:
	if absf(pos.y - floor_y()) > 1.6:
		return false
	return Rules.in_hush(arena_center, _hush_dir, lit_arc(), perimeter_radius, pos)


func _resolve_hush(p: Node3D) -> void:
	if _hush_done:
		return
	_hush_done = true
	visual.set_state("veiled")
	Art.sfx("shade_drift", arena_center + Vector3.UP, -2.0)
	if is_inside_tree():
		HitFx.burst(arena_center + Vector3.UP * 0.5, Color(0.55, 0.5, 0.7), 16, 5.0, 1.0, -6.0, 0.6, 180.0)
	if p == null or not _valid_victim(p) or not _hunt_allowed(p):
		return
	if not in_hush(p.global_position):
		return
	if not _los(arena_center + Vector3.UP * 1.0, p):
		return
	_hit(p, _attack_damage("kept_flame"), Rules.bearing(arena_center, p.global_position), _knock(), true)


func _expose_c() -> void:
	_pending_expose = false
	mark_fx.call("hide_mark")
	var pts := anchor_positions()
	var spot := arena_center + Rules.bearing(arena_center, pts[clampi(flame_anchor, 0, pts.size() - 1)]) * EXPOSE_C_RADIUS
	spot.y = floor_y()
	visual.set_state("exposed")
	_glide_to(spot, DROP_TIME)
	lights.call("gutter_false", true)
	Art.sfx("checkpoint_light", spot + Vector3.UP, -3.0)
	Art.sfx("gloomling_flinch", spot + Vector3.UP, -4.0)
	Art.caption("[your lantern and the kept flame burn together - the Choir is drawn down, exposed]")
	_begin_window("c_exposed", Rules.assisted(Rules.pick(Rules.T_WINDOW_C, intensity()), _assist()))


func _c_recover() -> void:
	lights.call("gutter_false", false)
	visual.set_state("veiled")
	_glide_to(_veil_pos(arena_center), 0.8)
	_enter("c_recover", Rules.assisted(Rules.pick(Rules.T_RECOVER_C, intensity()), _assist()))


func _on_anchor_raised(anchor_id: String) -> void:
	if not fight_started or _defeat_started or _gone or phase != 3:
		return
	_on_c_raise(_anchor_index(anchor_id))


func _on_c_raise(i: int) -> void:
	if i < 0:
		return
	var settled := bool(lights.get("settled"))
	var feinting := intensity() >= 2 and state == "c_settle" and state_time < _state_len * Rules.INTENSE_FEINT_AT
	if i == flame_anchor and state == "c_settle" and not feinting:
		if not _pending_expose:
			_pending_expose = true          # she read where it was going: exposed once the hush has passed
			Art.caption("[the kept flame swings toward your lantern - hold on until the hush passes]")
		return
	if i == flame_anchor and settled:
		match state:
			"c_open":
				_expose_c()
			"c_hush_tele", "c_hush":
				if not _pending_expose:
					_pending_expose = true
					Art.caption("[the kept flame answers your lantern - hold on until the hush passes]")
	elif state in ["c_open", "c_hush_tele", "c_settle"]:
		Art.caption("[your lantern burns alone on this hook - the true flame hangs elsewhere]")


## No anchor nodes (a bare trial arena): her own lit lantern held beside the true flame counts as the raise.
func _lantern_fallback_c(p: Node3D) -> void:
	if not anchor_nodes.is_empty() or p == null or flame_anchor < 0:
		return
	var lit: Variant = p.get("lantern_on")
	if lit is bool and lit and Rules.flat(p.global_position, hook_pos(flame_anchor)) <= LANTERN_FALLBACK_REACH:
		_on_c_raise(flame_anchor)


func _anchor_index(anchor_id: String) -> int:
	for i in anchor_nodes.size():
		var a: Variant = anchor_nodes[i]
		if is_instance_valid(a) and a is Node and String((a as Node).get("anchor_id")) == anchor_id:
			return i
	return -1


# --- Exposure windows --------------------------------------------------------------------------------------------

func _begin_window(s: String, length: float) -> void:
	_window_start_hp = health.hp
	_window_damage = 0.0
	health.set("floor_hp", Rules.window_min_hp(phase, health.hp, health.max_hp))
	_enter(s, length)
	exposure_changed.emit(true)
	_hint("choir_exposed", "It's exposed! Strike now with {attack}!")
	Events.camera_shake.emit(0.12, 0.25)


## Closes an exposure: the floor rule, then the next beat (recovery, a new phase, or the end).
func _end_window() -> void:
	if not (state in VULNERABLE_STATES):
		return
	var target := Rules.after_window_hp(phase, health.hp, _window_start_hp, health.max_hp)
	health.set("floor_hp", 0.0)
	if health.hp > target + 0.001:
		health.set_hp(target)
		Art.caption("[your light holds - the borrowed shape frays]")
	exposure_changed.emit(false)
	if phase >= 3:
		exposures += 1
		if exposures >= Rules.EXPOSURES_TO_END or health.hp <= 0.001:
			if health.hp > 0.0:
				health.set_hp(0.0)
			_begin_defeat()
			return
	var np := Rules.phase_for(health.hp, health.max_hp)
	if np > phase:
		_change_phase(np)
		return
	match phase:
		1:
			_a_recover()
		2:
			_b_reform()
		_:
			_c_recover()


func _on_damaged(amount: float, _source: Node, _dir: Vector3) -> void:
	HitFx.flash(self)
	HitFx.number(get_aim_point() + Vector3.UP * 0.9, amount)
	Art.sfx("enemy_hurt", get_aim_point(), -2.0)
	if health.hp <= 0.0:
		return            # `died` follows at once
	_window_damage += amount
	if state in VULNERABLE_STATES and health.hp <= float(health.get("floor_hp")) + 0.01:
		_end_window()     # the cap (or the phase boundary): good gear ends the window early


func _on_health_changed(_hp: float, _max_hp: float) -> void:
	if fight_started and not _defeat_started:
		_emit_health()


func _emit_health() -> void:
	Events.boss_health_changed.emit(boss_id, health.hp, health.max_hp)


func _on_died() -> void:
	if _defeat_started or _gone:
		return
	if state == "c_exposed":
		exposures += 1
	_begin_defeat()


func on_hit_blocked(attacker: Node, _dir: Vector3) -> void:
	if _gone or _defeat_started:
		return
	if is_inside_tree():
		HitFx.spark(get_aim_point())
	if attacker != null and is_instance_valid(attacker) and not _is_krystal(attacker):
		return
	match phase:
		1:
			_hint("choir_glance_a", "Your blow passes through a borrowed shape. Raise your lantern at an anchor, then point out the true form.")
		2:
			_hint("choir_glance_b", "Its borrowed bells protect it. Wake both resonators to bring it down.")
		_:
			_hint("choir_glance_c", "Raise your lantern at the anchor holding the true flame to draw it down.")


# --- Victory ----------------------------------------------------------------------------------------------------

func _begin_defeat() -> void:
	if _defeat_started or _gone:
		return
	_defeat_started = true
	state = "defeat"
	_release_token()
	health.invulnerable = true
	health.set("floor_hp", 0.0)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	_clear_hazards()
	_dismiss_wisps()
	resonance.call("release")
	lights.call("clear")
	layers.call("set_count", 0)
	for f in forms:
		(f as Node).call("hide_form")
	# 1) COMMIT FIRST - before any presentation (MP §13.3): bar hidden, encounter over, then the arena's listener
	#    sets ch2_choir_defeated and saves. A host without that listener: the boss sets the flag itself.
	fight_started = false
	Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
	Events.boss_encounter_changed.emit(boss_id, false)
	_director(false)
	if is_story():
		Events.boss_defeated.emit(boss_id)
		if not bool(GameState.get_flag(CLEAR_FLAG)):
			GameState.set_flag(CLEAR_FLAG, true)
	state_changed.emit("defeat")
	defeated.emit()
	# 2) presentation (skippable by crashing: the world is already committed)
	_play_victory()


func _play_victory() -> void:
	_victory_t = 0.0
	_victory_step = 0
	Art.caption("[the trapped echoes rise as gentle chimes; masks and ribbons drift harmlessly down]")
	Events.camera_shake.emit(0.2, 0.6)
	visual.set_state("defeat")
	Art.sfx("lumi_chime", get_aim_point(), -6.0)
	Art.sfx("ward_restore", get_aim_point(), -6.0)
	if fast_defeat or not is_inside_tree():
		_finish_defeat()
		return
	HitFx.burst(get_aim_point(), Color(1.0, 0.92, 0.7), 18, 1.2, 1.1, 1.2, 2.4, 160.0)
	visual.call("fall_apart", floor_y() - global_position.y)


## The victory presentation runs on the boss's own clock (tick), never a coroutine: freeing the vault mid-way
## (area change, quit) simply stops it - the world was committed before it began.
func _tick_victory(delta: float) -> void:
	_victory_t += delta
	if _victory_step == 0 and _victory_t >= VICTORY_CHIME_AT:
		_victory_step = 1
		Art.sfx("lumi_chime", get_aim_point() + Vector3.UP, -8.0)
		if is_inside_tree():
			HitFx.burst(get_aim_point() + Vector3.UP, Color(1.0, 0.95, 0.8), 14, 1.0, 1.0, 1.6, 2.6, 180.0)
	if _victory_t >= VICTORY_TIME:
		_finish_defeat()


func _finish_defeat() -> void:
	_gone = true
	state = "gone"
	visible = false
	state_changed.emit("gone")


func _on_flag_set(flag: String, v: Variant) -> void:
	if flag == CLEAR_FLAG and is_story() and not _defeat_started and not _gone and Combat.truthy(v):
		dismiss()


func _on_any_boss_defeated(id: String) -> void:
	if id == boss_id and is_story() and not _defeat_started and not _gone:
		dismiss()


# --- Reset triggers ---------------------------------------------------------------------------------------------

func _on_player_died() -> void:
	reset_fight()


## Krystal left the vault (or it has no Krystal): stand down after LEAVE_TIME.
func _stand_down(p: Node3D, delta: float) -> bool:
	var away := p == null
	if not away:
		var pos := p.global_position
		away = Rules.flat(pos, arena_center) > arena_radius + LEAVE_MARGIN or absf(pos.y - floor_y()) > 5.0
	if away:
		_away_t += delta
		return _away_t >= LEAVE_TIME
	_away_t = 0.0
	return false


func _lower_anchors() -> void:
	for a in anchor_nodes:
		if is_instance_valid(a) and a is Node and (a as Node).has_method("lower"):
			(a as Node).call("lower")


func _clear_hazards() -> void:
	if mark_fx != null:
		mark_fx.call("hide_mark")
	if rings != null:
		rings.call("clear")
	if strikes != null:
		strikes.call("clear")
	_pending_expose = false
	_release_token()


# --- Helpers ----------------------------------------------------------------------------------------------------

func _assist() -> bool:
	return Art.timing_assist()


func _knock() -> float:
	return float(data.get("knockback", 6.0))


func _attack_damage(attack_id: String) -> float:
	var dmg := float(data.get("damage", 16.0))
	var list: Variant = data.get("attacks")
	if list is Array:
		for a in list:
			if a is Dictionary and String((a as Dictionary).get("id", "")) == attack_id:
				dmg = float((a as Dictionary).get("damage", dmg))
	return dmg * Combat.intensity_damage_mult(intensity()) * damage_scale


## ONE hit on Krystal through her health path (i-frames -> armour -> shield -> hp). `lethal` false = the wrong-pick
## sweep: never takes her below 1 hp (MP: "survivable ... rather than instant death").
func _hit(p: Node3D, dmg: float, dir: Vector3, knock: float, lethal: bool) -> float:
	var h := Combat.find_health(p)
	if h == null or dmg <= 0.0:
		return 0.0
	var amount := dmg
	if not lethal:
		# her health multiplies the raw amount by damage_taken_mult (armour only lowers it): cap before that
		var taken: Variant = h.get("damage_taken_mult")
		var mult := maxf(float(taken), 1.0) if (taken is float or taken is int) else 1.0
		amount = minf(amount, maxf(float(h.get("hp")) - 1.0, 0.0) / mult)
	if amount <= 0.0:
		return 0.0
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var dealt := float(h.apply_damage(amount, self, d))
	if dealt <= 0.0:
		if p.has_method("on_hit_blocked"):
			p.call("on_hit_blocked", self, d)
		return 0.0
	hits_landed += 1
	if knock > 0.0 and p.has_method("knockback"):
		p.call("knockback", d, knock)
	var col: Variant = p.get("hit_color")
	HitFx.impact(Combat.aim_point(p) - d * 0.25, dealt, col if col is Color else HitFx.DEFAULT_IMPACT)
	Events.hitstop.emit(Combat.HITSTOP_HEAVY if dealt >= 15.0 else Combat.HITSTOP_LIGHT)
	return dealt


func _los(from: Vector3, p: Node3D) -> bool:
	if not is_inside_tree() or not p.is_inside_tree():
		return true
	return Combat.has_line_of_sight(get_world_3d().direct_space_state, from, Combat.aim_point(p), [p], Combat.LOS_MASK)


func _player() -> Node3D:
	if target_override != null:
		return target_override if is_instance_valid(target_override) and target_override.is_inside_tree() else null
	var p: Variant = Game.player
	if is_instance_valid(p) and p is Node3D and (p as Node3D).is_inside_tree():
		return p
	return null


func _hunt_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "loading" or Game.mode == "cutscene":
		return false
	var h := Combat.find_health(p)
	return not (h != null and bool(h.get("dead")))


func _valid_victim(t: Node) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t == target_override:
		return true
	return t.is_in_group("player") and not t.is_in_group("companion") and not t.is_in_group("enemy")


static func _is_krystal(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player") and not n.is_in_group("companion")


func _inside(pos: Vector3, r: float) -> bool:
	return Rules.flat(pos, arena_center) <= r and absf(pos.y - floor_y()) < 3.0


func _clamp_inside(pos: Vector3, r: float) -> Vector3:
	var v := Vector3(pos.x - arena_center.x, 0.0, pos.z - arena_center.z)
	if v.length() > r:
		v = v.normalized() * r
	return Vector3(arena_center.x + v.x, floor_y(), arena_center.z + v.z)


static func _nearest_point(points: Variant, pos: Vector3) -> Vector3:
	var best := pos
	var bd := INF
	if points is Array:
		for q in points:
			if q is Vector3:
				var d := Rules.flat(q, pos)
				if d < bd:
					bd = d
					best = q
	return best


func _veil_pos(c: Vector3) -> Vector3:
	return Vector3(c.x, floor_y() + HOVER_HIGH, c.z)


func _glide_to(pos: Vector3, length: float) -> void:
	if length <= 0.0 or not is_inside_tree():
		_glide_len = 0.0
		global_position = pos
		return
	_glide_from = global_position
	_glide_to_pos = pos
	_glide_t = 0.0
	_glide_len = length


func _glide_step(dt: float) -> void:
	if _glide_len <= 0.0:
		return
	_glide_t = minf(_glide_t + dt, _glide_len)
	var k := _glide_t / _glide_len
	global_position = _glide_from.lerp(_glide_to_pos, k * k * (3.0 - 2.0 * k))
	if _glide_t >= _glide_len:
		_glide_len = 0.0


func _hint(id: String, text: String) -> void:
	Events.hint.emit(id, text)


func _notice_companions() -> void:
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if is_instance_valid(c) and c is Node and (c as Node).has_method("notice_threat"):
			(c as Node).call("notice_threat", global_position)


## Holds the horror director for the whole fight (through the Works area's hold API when present).
func _director(on: bool) -> void:
	if on == _hold:
		return
	_hold = on
	var a: Variant = Game.area
	if is_instance_valid(a) and a is Node and (a as Node).has_method("director_hold"):
		if on:
			(a as Node).call("director_hold", HOLD_ID)
		elif (a as Node).has_method("director_release"):
			(a as Node).call("director_release", HOLD_ID)
		return
	var d: Variant = Game.director
	if is_instance_valid(d) and d is Node:
		if on and (d as Node).has_method("hold"):
			(d as Node).call("hold", HOLD_ID)
		elif not on and (d as Node).has_method("release"):
			(d as Node).call("release", HOLD_ID)
		elif (d as Node).has_method("suppress"):
			(d as Node).call("suppress", 9999.0 if on else 20.0)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply_hv()


func _apply_hv() -> void:
	var hv := Art.high_visibility()
	for f in forms:
		(f as Node).call("set_hv", hv)
	if lights != null:
		lights.call("set_hv", hv)
	if rings != null:
		rings.set("hv", hv)
	if strikes != null:
		strikes.set("hv", hv)
