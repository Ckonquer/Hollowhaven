extends Node3D
## Weaver's Crossing rematch (MP 13.2; spec sections 9-10): the ESCAPED Weaver Matron (arachnophobia: the
## Hollow Mother) on the Hushed Works service bridge. A NEW encounter with its own id "crossing_matron" and
## its own state: it never reads or writes "weaver_defeated", the Heartseed or anything of Chapter One.
## Spawned by the arena (src/world/works/deep/crossing_arena.gd) through EnemyFactory with its boss_params():
##   setup({"arena": node, "arena_center", "arena_radius", "anchors": [5 ceiling Vector3 - lines 0..2 first],
##          "braziers": [3 line-braziers, index = line], "crack": Vector3, "bridge": Rect2 (x, z),
##          "deck_y": float, "landing_points": [Vector3...], "alert": true (start at once),
##          optional "rail" (default: bridge half depth - 0.2), "mode": "story"|"trial", "minion_id"})
##
## THE RULE (taught by the intro hint): she holds ONE line anchor at a time. When the line-brazier UNDER THE
## ANCHOR SHE HOLDS flares - lit with the lantern (1.5 s kindle) or, once lit, stoked again after its readable
## cooldown (boss_brazier set_reusable) - the anchor is EXPOSED: she is burned off it, falls to the deck and is
## vulnerable for a long window. Lighting a brazier under an empty anchor is a wasted flare (a caption says so).
## Her kit, one readable action at a time (crossing/crossing_rules.gd has every number):
##   THREADS  (hazard set)  a floor mark shows where they will land (1.2 s), then cuttable threads (arachno-
##            phobia: pale veils/roots, deep_thread.gd) fall ACROSS HER lane either side of the guarded brazier.
##            The other lane always stays open. Cut them (interact), burn them (lantern raised) or burn them
##            with their line-brazier; a new cast replaces what is left of the old one; they expire by themselves.
##   POUNCE   (committed)   a ring marks her landing on the lane Krystal is using (1.3 s Standard) - a VALID
##            landing only (on the deck, inside the rails, clear of braziers and threads, clear line of sight
##            from her anchor: never through the deck, a ceiling or a wall). Hit: one hit through Krystal's
##            health, knocked ALONG the bridge only (never toward a rail or the pit), no opening. Missed: she is
##            STRANDED ~2.5 s (an opening).
##   DELAYED POUNCE (from phase 2) the ring pulses at half speed, then an audible AND visible FINAL PREPARATION
##            (sound + caption, the ring snaps solid, a strand drops from her to it, she coils with a halo)
##            0.6 s before she drops. Intense adds a harmless feint shiver at the ordinary pounce time, over
##            at least Rules.FEINT_GAP before the real final tell (two separate cues, never one blurred one).
##   RELEASE  (phase 3, once, INSTEAD of a delayed pounce) capped minions: shaking sacs (pale pods) in front of
##            Krystal, never underfoot -> Brood Skitters (Pale Sprouts): Gentle one slower, else two. No pounce
##            of any kind while a sac is pending or a minion lives (never together with the pounce).
## At most ONE hazard set (one cast of threads) + ONE committed attack. Every action has a recovery beat.
## Phases follow exposures: 1 (north lane) -> exposure -> 2 (she CHANGES SIDES: south, delayed pounce) ->
## exposure -> 3 (north again, the release) -> ... Two or three exposures plus tuned damage end it: each flare
## also scorches her (10% of max hp; 25% after the third, so she can never become a health sponge); an
## exposure window can take at most 40% of her health, a stranded window 20%. A strong weapon can't skip the
## rule: blows alone never take her below 60% before the first exposure or 25% before the second
## (Rules.HP_FLOOR; at the floor a missed pounce leaves no opening and a hint points at the brazier).
## DEFEAT = RETREAT: at 0 hp the victory is COMMITTED FIRST - bar hidden, boss_encounter_changed(false) and
## Events.boss_defeated("crossing_matron") exactly once (the arena's listener grants rw_ch2_crossing -> flag
## ch2_crossing_cleared, opens the way on, shuts the old service gate and saves) - and only then does she flee
## across the ceiling, down the wall and through the mouth of her deeper route into the crack behind the old
## service gate (retreat_path(), retreat_seconds()). No death, no gore.
## Companions: can_be_hit_by(source) is true only in the exposed / stranded windows, and only for Krystal or
## helpers standing inside the arena. Hits outside a window glance off (spark; the hint is Krystal's).
##
## RESET POLICY (one rule, the same as the Chapter One Matron): Krystal falls, or leaves the crossing (the
## arena stands the encounter down): the ACTIVE encounter resets cleanly - back up on a line anchor of her
## current side, dormant, bar hidden, encounter event off; every thread, mark, sac and minion removed. Her
## wounds, the exposures made (phase, side) and lit braziers are kept (lit braziers stay stokable: never a dead
## end). Reloading / leaving the Works: nothing unfinished is saved - a fresh encounter. Won progression is
## never touched: once ch2_crossing_cleared is set she never comes back. The fight never (re)starts while
## Krystal is down; a blow that knocks her out ends that pounce at once (the reset already ran inside it).
## Comfort: Settings timing_assist stretches warnings, openings and recovery beats x1.5; high_visibility_cues
## adds bold outlines (pounce mark, thread landing marks; landed threads via deep_thread); reduce_flashing keeps
## marks steady; camera shakes go through Events.camera_shake. Gentle: softer (x0.6), longer warnings/openings, one thread per cast,
## one slower minion. Intense: less idle, the delayed-pounce feint - never shorter warnings than 1.1 s, never
## invisible, never louder. Every important sound has a caption; arachnophobia swaps names (data alt_name),
## body (crossing/matron_look.gd), anchors (stone seals: crossing/anchor_marks.gd), threads, marks, sacs,
## minions, sounds and captions - live, timers untouched.
## QA (cheats only): --crossing-exposures=1|2 starts the fight as if that many exposures were made.

signal defeated
signal retreated
signal state_changed(new_state: String)
signal exposed(line: int, count: int)
signal phase_changed(phase: int)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Health := preload("res://src/combat/health.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const Rules := preload("res://src/enemies/crossing/crossing_rules.gd")
const MatronLook := preload("res://src/enemies/crossing/matron_look.gd")
const PounceMark := preload("res://src/enemies/crossing/pounce_mark.gd")
const AnchorMarks := preload("res://src/enemies/crossing/anchor_marks.gd")
const BroodRelease := preload("res://src/enemies/crossing/brood_release.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const THREAD_SCRIPT := "res://src/world/works/deep/deep_thread.gd"
const HIGH_VIS_COLOR := Color("fff1c9")      # Settings high_visibility_cues: bold cream outlines (shape, not colour)
const CAST_MARK_WIDTH := 0.6

const BOSS_ID := "crossing_matron"
const REWARD_ID := "rw_ch2_crossing"
const CLEAR_FLAG := "ch2_crossing_cleared"
const ENGAGE_MARGIN := 2.0        # (no arena) starts this far outside the arena edge
const LEAVE_MARGIN := 9.0         # (no arena) stands down after Krystal has been this far out ...
const LEAVE_TIME := 4.0           # ... for this long
const THREAD_HEIGHT := 2.6
const THREAD_DONE_FREE := 1.0     # a burned / expired / dissolved thread node is freed after this
const RETREAT_SHRIEK := 0.9
const RETREAT_UP := 0.9
const RETREAT_SPEED := 9.0
const RETREAT_IN := 0.6
const RETREAT_WALL_GAP := 2.8   # she runs along the ceiling to this far in front of the crack, then slips in
const RETREAT_SHRINK := 0.22    # she has withdrawn to this size by the route's mouth (the 4.5 m Hollow Mother
                                # then fits the 3 m opening from the crack's height: ~1 m tall)
const VULNERABLE_STATES := ["stranded", "exposed"]
const GROUND_STATES := ["rebound", "stranded", "exposed"]
const CEILING_STATES := ["dormant", "intro", "cling", "cast", "recover", "pounce_tele", "release"]
const MOVING_STATES := ["climb", "drop", "scorch_fall"]

var enemy_id: String = BOSS_ID
var boss_id: String = BOSS_ID
var mode: String = "story"
var data: Dictionary = {}
var health: Node
var look: Node3D = null
var visual: Node3D = null            # = look (HitFx.flash and previews look for `visual`)
var hit_radius: float = 1.8
var hit_color := Color(0.86, 0.8, 0.92)
var arena: Node = null
var arena_center := Vector3.ZERO
var arena_radius: float = 14.5
var bridge := Rect2(-16.0, -5.0, 32.0, 10.0)
var deck_y: float = 0.0
var rail: float = 4.8
var crack_point := Vector3.ZERO
var anchors: Array = []              # every ceiling anchor (lines first)
var line_anchors: Array = []         # anchors[0 .. lines-1]
var braziers: Array = []             # line-brazier nodes, index = line
var landing_points: Array = []       # the arena's validated landing grid (fallback)
var minion_id: String = "brood_skitter"
var state: String = "dormant"
var state_time: float = 0.0
var fight_started := false
var phase: int = 1
var exposures: int = 0
var side: int = Rules.START_SIDE
var held_line: int = -1
var target_override: Node3D = null   # tests: the node treated as Krystal
var intensity_override: int = -1     # tests
var fast_defeat := false             # tests: skip the retreat presentation
var require_floor := true            # pounce landings need a floor under them (tests without geometry: false)
var auto_start := false              # setup "alert": start the fight as soon as she is in the tree
## Counters for tests / QA telemetry.
var stats := {"casts": 0, "threads": 0, "pounces": 0, "delayed": 0, "hits": 0, "final_tells": 0, "feints": 0,
	"releases": 0, "exposures": 0, "wasted_flares": 0, "resets": 0, "defeat_events": 0}

var _state_len: float = 0.0
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _mid := Transform3D.IDENTITY     # side change: the corner under the ceiling above where she lay
var _mid_k: float = 0.0              # share of the climb spent on the first leg (0 = one straight leg)
var _landing := Vector3.ZERO
var _pounce_delayed := false
var _delayed: Dictionary = {}
var _final_done := false
var _feint_done := false
var _pending_exposure := false
var _window_damage: float = 0.0
var _window_cap: float = 0.0
var _scorching := false
var _check_t: float = 0.0
var _away_t: float = 0.0
var _step: int = 0
var _release_done := false
var _threads: Array = []             # [{"node", "a", "b", "line", "cut_t", "done_t"}]
var _cast_segs: Array = []
var _cast_marks: Array = []          # TelegraphFx nodes (one per thread of a cast)
var _cast_bold: Array = []           # their high-visibility outlines (two bold rails each)
var _mark: Node3D = null             # crossing/pounce_mark.gd
var _marks: Node3D = null            # crossing/anchor_marks.gd
var _release: Node3D = null          # crossing/brood_release.gd
var _line_exposures: Dictionary = {}
var _last_exposed_line: int = -1
var _alt := false
var _rng := RandomNumberGenerator.new()
var _defeat_started := false
var _gone := false
var _initialized := false
var _retry := false
var _debug_jumped := false


func setup(p: Dictionary) -> void:
	var a: Variant = p.get("arena")
	if a is Node:
		arena = a
	var c: Variant = p.get("arena_center")
	if c is Vector3:
		arena_center = c
	arena_radius = maxf(float(p.get("arena_radius", arena_radius)), 3.0)
	deck_y = float(p.get("deck_y", arena_center.y))
	var br: Variant = p.get("bridge")
	if br is Rect2:
		bridge = br
	else:
		bridge = Rect2(arena_center.x - arena_radius, arena_center.z - 5.0, arena_radius * 2.0, 10.0)
	rail = float(p.get("rail", maxf(bridge.size.y * 0.5 - 0.2, 1.0)))
	var ck: Variant = p.get("crack")
	crack_point = ck if ck is Vector3 else Vector3(bridge.end.x, deck_y + 2.0, arena_center.z - rail - 6.0)
	mode = "trial" if String(p.get("mode", mode)) == "trial" else "story"
	minion_id = String(p.get("minion_id", minion_id))
	auto_start = Combat.truthy(p.get("alert", auto_start))
	anchors.clear()
	var an: Variant = p.get("anchors", [])
	if an is Array or an is PackedVector3Array:
		for v in an:
			if v is Vector3:
				anchors.append(v)
	landing_points.clear()
	var lp: Variant = p.get("landing_points", [])
	if lp is Array or lp is PackedVector3Array:
		for v in lp:
			if v is Vector3:
				landing_points.append(v)
	for b in braziers:
		_disconnect_brazier(b)
	braziers.clear()
	var bz: Variant = p.get("braziers", [])
	if bz is Array:
		for b in bz:
			if b is Node and is_instance_valid(b):
				braziers.append(b)
	var lines := mini(braziers.size(), anchors.size()) if not braziers.is_empty() else mini(3, anchors.size())
	line_anchors = anchors.slice(0, lines)
	for i in braziers.size():
		var b: Node = braziers[i]
		var line := int(b.get_meta("anchor_index", i)) if b.has_meta("anchor_index") else i
		if b.has_signal("lit"):
			b.connect("lit", _on_line_fired.bind(line, "lit"))
		if b.has_signal("flared"):
			b.connect("flared", _on_line_fired.bind(line, "flared"))
	if is_inside_tree() and data.size() > 0:
		_initialized = false
		_initialize()


func _ready() -> void:
	data = ItemDB.enemy(BOSS_ID)
	_rng.randomize()
	health = Health.new()
	health.name = "Health"
	health.max_hp = float(data.get("hp", 320.0))
	health.invulnerable = true
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	if not Events.flag_set.is_connected(_on_flag):
		Events.flag_set.connect(_on_flag)
	HitFx.ensure_hitstop()
	_initialize()


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if anchors.is_empty():
		anchors = [arena_center + Vector3(0.0, 10.0, -rail * 0.8), arena_center + Vector3(0.0, 10.0, rail * 0.8)]
		line_anchors = anchors.duplicate()
	if is_story() and bool(GameState.get_flag(CLEAR_FLAG)):
		# Won progression is never touched: a cleared crossing never brings her back.
		_gone = true
		state = "gone"
		visible = false
		set_process(false)
		return
	add_to_group("enemy")
	_alt = _arachno()
	_build_parts()
	side = Rules.side_for(exposures)
	held_line = _pick_line(side, -1)
	global_transform = _ceiling_pose(_anchor_of(held_line), _player_pos())
	_marks.call("set_held", held_line, _body_point())
	_enter("dormant")
	if auto_start:
		start_fight()


func _build_parts() -> void:
	if look == null or not is_instance_valid(look):
		look = MatronLook.new()
		look.call("setup", {"alt": _alt})
		look.name = "Look"
		add_child(look)
		visual = look
	if _mark == null or not is_instance_valid(_mark):
		_mark = PounceMark.new()
		_mark.name = "PounceMark"
		add_child(_mark)
	if _marks == null or not is_instance_valid(_marks):
		_marks = AnchorMarks.new()
		_marks.call("setup", {"anchors": anchors, "lines": line_anchors.size(), "alt": _alt})
		_marks.name = "AnchorMarks"
		add_child(_marks)
	if _release == null or not is_instance_valid(_release):
		_release = BroodRelease.new()
		_release.call("setup", {"minion_parent": get_parent(), "home": Vector3(arena_center.x, deck_y, arena_center.z),
			"radius": maxf(bridge.size.x * 0.5, 6.0), "alt": _alt, "minion_id": minion_id})
		_release.name = "BroodRelease"
		add_child(_release)
	while _cast_marks.size() < int(Rules.THREADS_PER_CAST.max()):
		var m: Node3D = TelegraphFx.new()
		m.name = "ThreadMark%d" % _cast_marks.size()
		add_child(m)
		_cast_marks.append(m)
		var bold := Node3D.new()
		bold.name = "CastBold%d" % _cast_bold.size()
		bold.top_level = true
		add_child(bold)
		var bm := Mat.glow(HIGH_VIS_COLOR, 1.3)
		for sx in [-1.0, 1.0]:
			var rail_mi := Kit.box(Vector3(0.07, 0.03, 1.0), bm)
			rail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Kit.add(bold, rail_mi, Vector3(float(sx) * (CAST_MARK_WIDTH * 0.5 + 0.05), 0.07, -0.5))
		bold.visible = false
		_cast_bold.append(bold)


# --- Public API ----------------------------------------------------------------------------------------------

func is_story() -> bool:
	return mode != "trial"


func is_threatening() -> bool:
	return fight_started and not _gone and not _defeat_started


func is_vulnerable() -> bool:
	return state in VULNERABLE_STATES


func is_overhead() -> bool:
	return state in CEILING_STATES or state == "climb"


func is_gone() -> bool:
	return _gone


func is_defeated() -> bool:
	return _defeat_started or _gone


func intensity() -> int:
	return intensity_override if intensity_override >= 0 else Combat.current_intensity()


func held_anchor() -> Vector3:
	return _anchor_of(held_line)


func current_landing() -> Vector3:
	return _landing


func live_threads() -> int:
	var n := 0
	for t in _threads:
		var node: Variant = t["node"]
		if node != null and is_instance_valid(node) and bool((node as Node).call("is_blocking")):
			n += 1
	return n


func thread_nodes() -> Array:
	var out: Array = []
	for t in _threads:
		var node: Variant = t["node"]
		if node != null and is_instance_valid(node):
			out.append(node)
	return out


func minions_alive() -> int:
	return int(_release.call("alive_minions")) if _release != null else 0


func sacs_pending() -> bool:
	return _release != null and bool(_release.call("sacs_pending"))


func release_node() -> Node:
	return _release


func pounce_mark() -> Node:
	return _mark


func anchor_marks() -> Node:
	return _marks


func uses_shade() -> bool:
	return _alt


## Seconds of the retreat presentation after the victory was committed (the arena may time its gate by it).
func retreat_seconds() -> float:
	var path := retreat_path()
	return RETREAT_SHRIEK + RETREAT_UP + _leg_time(path[0], path[1], 0.6) + _leg_time(path[1], path[2], 0.4) + RETREAT_IN


## The retreat's waypoints (her origin): [up under the ceiling where she is, over the old service gate under
## the ceiling, down the wall to the mouth of her deeper route (in front of it, at the crack's height), the
## crack]. Only the last leg crosses the wall line, level, through the route's opening (she shrinks to
## RETREAT_SHRINK on the way down the wall); while she travels the ceiling the Hollow Mother (upright, tall)
## hangs her full height lower so she never pokes through it.
func retreat_path() -> Array:
	var dz := signf(arena_center.z - crack_point.z)
	if dz == 0.0:
		dz = 1.0
	var high := _ceiling_y() - _retreat_hang()
	var front := crack_point.z + dz * RETREAT_WALL_GAP
	return [Vector3(global_position.x, high, global_position.z), Vector3(crack_point.x, high, front),
		Vector3(crack_point.x, crack_point.y, front), crack_point]


## How far below the ceiling line her origin travels (the ceiling pose's hang; see _ceiling_pose).
func _retreat_hang() -> float:
	if _alt:
		return (float(look.call("body_height")) if look != null else 4.5) + 0.35
	return 0.4


static func _leg_time(a: Vector3, b: Vector3, min_t: float) -> float:
	return maxf(a.distance_to(b) / RETREAT_SPEED, min_t)


## Spec section 9: companion attacks and projectiles respect this. True only in an exposed / stranded window,
## and only for Krystal or a helper standing inside the crossing (never from outside, never from the ceiling).
func can_be_hit_by(source: Node) -> bool:
	if _gone or _defeat_started or not is_vulnerable():
		return false
	if source == null or not is_instance_valid(source) or not (source is Node3D):
		return true
	if source == target_override or _is_krystal(source):
		return true
	if source.is_in_group("enemy"):
		return false
	return _in_arena((source as Node3D).global_position)


func get_aim_point() -> Vector3:
	if state in GROUND_STATES or state == "defeat":
		return global_position + Vector3.UP * (1.4 if _alt else 0.9)
	return global_position + global_transform.basis.y * 1.2


func hit_flash(duration: float = 0.11) -> void:
	if look != null:
		look.call("hit_flash", duration)


func knockback(_dir: Vector3, _force: float) -> void:
	pass


## Damage of one pounce (data "pounce" / "delayed_pounce" x the underground intensity multiplier).
func pounce_damage(delayed: bool) -> float:
	var def := _attack_def("delayed_pounce" if delayed else "pounce")
	return float(def.get("damage", data.get("damage", 20.0))) * Combat.intensity_damage_mult(intensity())


func on_hit_blocked(attacker: Node, _dir: Vector3) -> void:
	if _gone or _defeat_started:
		return
	HitFx.spark(get_aim_point())
	Audio.play_3d("hit_soft", get_aim_point(), -2.0, 0.2)
	if (attacker == null or not is_instance_valid(attacker) or _is_krystal(attacker)) and state in GROUND_STATES:
		# braced on the deck (a pounce that landed, or she can't be wounded further by blows alone)
		Events.hint.emit("boss_crossing_braced", "She's braced and shrugs that off. She's only open when a pounce misses or the light under HER anchor burns her down." if not _alt
			else "She's braced and shrugs that off. She's only open when her drop misses or the light under HER seal breaks her hold.")
	elif attacker == null or not is_instance_valid(attacker) or _is_krystal(attacker):
		Events.hint.emit("boss_crossing_glance", "Her hide is too tough while she hangs from her anchor. Light the line-brazier under HER anchor with {interact}, or dodge a pounce so she's stranded!" if not _alt
			else "She is out of reach while she floats beneath her seal. Light the line-brazier under HER seal with {interact}, or dodge her drop so she's stranded!")


func start_fight() -> void:
	if fight_started or _gone or _defeat_started or not _initialized:
		return
	var p := _player()
	if p != null and not _hunt_allowed(p):
		# Krystal is down (death screen) or the game is loading: no encounter events, bar or captions now.
		# The dormant tick starts the fight once she is back on the crossing (_may_self_start).
		return
	fight_started = true
	_debug_exposure_jump()
	for i in braziers.size():
		var b: Node = braziers[i]
		if is_instance_valid(b) and b.has_method("set_reusable"):
			b.call("set_reusable", true, float(Rules.REUSE_COOLDOWN[_i()]))
	_emit_health()
	Events.boss_encounter_changed.emit(boss_id, true)
	Events.boss_phase_changed.emit(boss_id, phase)
	_director_hold(true)
	_snd("shriek", global_position, -4.0)
	Events.caption.emit(_caption("intro"))
	Events.hint.emit("boss_crossing_intro", "She holds one ceiling anchor at a time. Light the line-brazier UNDER HER ANCHOR with {interact} to burn her off it." if not _alt
		else "She floats beneath one stone seal at a time. Light the line-brazier UNDER HER SEAL with {interact} to break her hold.")
	if _retry and is_story():
		Events.hint.emit("boss_crossing_retry", "She keeps her wounds, and lit braziers stay lit, while you stay in the Works. Leaving the Works lets her recover fully.")
	_notice_companions()
	if state == "dormant":
		_enter("intro", Rules.T_INTRO)


## Clean stand-down (Krystal fell, or left the crossing). See RESET POLICY in the header.
func reset_fight() -> void:
	if _gone or _defeat_started or not _initialized:
		return
	_pending_exposure = false
	_step = 0
	_away_t = 0.0
	_release_done = false
	_clear_hazards(false)
	if _release != null:
		_release.set("released_count", 0)
	side = Rules.side_for(exposures)
	if held_line < 0 or Rules.side_of(_anchor_of(held_line), arena_center.z) != side:
		held_line = _pick_line(side, _last_exposed_line)
	global_transform = _ceiling_pose(_anchor_of(held_line), _player_pos())
	if _marks != null:
		_marks.call("set_held", held_line, _body_point())     # the held anchor's mark + tether follow her
	if fight_started:
		fight_started = false
		_retry = true
		stats["resets"] = int(stats["resets"]) + 1
		Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
		Events.boss_encounter_changed.emit(boss_id, false)
		_director_hold(false)
	_enter("dormant")


# --- State machine ---------------------------------------------------------------------------------------------

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
	_tick_threads(delta)
	if _release != null:
		var t: Node3D = p if p != null and fight_started and _hunt_allowed(p) else null
		_release.call("tick", delta, t, _release_allowed())
	if fight_started and _check_stand_down(p, delta):
		return
	match state:
		"dormant":
			if check and p != null and _hunt_allowed(p) and _may_self_start(p):
				start_fight()
		"intro":
			_face_on_ceiling(delta)
			if state_time >= _state_len:
				_enter_cling(1.0)
		"cling":
			_face_on_ceiling(delta)
			if state_time >= _state_len and p != null and _hunt_allowed(p):
				_choose_action()
		"cast":
			_face_on_ceiling(delta)
			var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
			for m in _cast_marks:
				if (m as Node3D).call("is_showing"):
					(m as Node3D).call("set_progress", k, k > 0.6)
			if state_time >= _state_len:
				_land_threads()
				_enter_recover()
		"recover", "release":
			_face_on_ceiling(delta)
			if state_time >= _state_len:
				if state == "release":
					_enter_recover()
				else:
					_enter_cling(-1.0)
		"pounce_tele":
			_tick_pounce_tele(delta)
			if state_time >= _state_len:
				_begin_drop()
		"drop":
			var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
			global_transform = _lerp_xform(_from, _to, k * k)
			if k >= 1.0:
				_land_pounce()
		"rebound", "stranded":
			if state_time >= _state_len:
				_begin_climb()
		"scorch_fall":
			var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
			global_transform = _lerp_xform(_from, _to, k * k)
			if k >= 1.0:
				_land_exposed()
		"exposed":
			if state_time >= _state_len:
				_change_sides()
		"climb":
			var k := clampf(state_time / maxf(_state_len, 0.01), 0.0, 1.0)
			global_transform = climb_xform(k)
			if _marks != null:
				_marks.call("update_body", _body_point())
			if k >= 1.0:
				_enter_cling(-1.0)


## A dormant boss starts by herself: without an arena when Krystal comes near; with one only while the arena
## says the encounter is on AND Krystal is on the crossing (the arena came on while she was down, and
## start_fight() refused then) - never while she stands back at the checkpoint gate.
func _may_self_start(p: Node3D) -> bool:
	if arena != null and is_instance_valid(arena):
		return arena.has_method("is_active") and bool(arena.call("is_active")) and _in_arena(p.global_position)
	return _flat(p.global_position, arena_center) <= arena_radius + ENGAGE_MARGIN


## The arena owns "the encounter is on": when it stands down (Krystal back at the checkpoint gate) she resets.
## Without an arena: Krystal away from the crossing for LEAVE_TIME. True when it reset.
func _check_stand_down(p: Node3D, delta: float) -> bool:
	if arena != null and is_instance_valid(arena):
		if arena.has_method("is_active") and not bool(arena.call("is_active")):
			reset_fight()
			return true
		return false
	if state in GROUND_STATES or state in MOVING_STATES:
		return false
	if p == null or _flat(p.global_position, arena_center) > arena_radius + LEAVE_MARGIN:
		_away_t += delta
		if _away_t >= LEAVE_TIME:
			reset_fight()
			return true
	else:
		_away_t = 0.0
	return false


func _enter(s: String, length: float = 0.0) -> void:
	state = s
	state_time = 0.0
	_state_len = length
	health.invulnerable = not (s in VULNERABLE_STATES)
	health.damage_taken_mult = Rules.EXPOSED_MULT if s == "exposed" else 1.0
	if s in VULNERABLE_STATES:
		_window_damage = 0.0
		_window_cap = health.max_hp * (Rules.WINDOW_CAP_EXPOSED if s == "exposed" else Rules.WINDOW_CAP_STRANDED)
	if s != "pounce_tele" and s != "drop" and _mark != null:
		_mark.call("hide_mark")
	if s != "pounce_tele" and look != null:
		look.call("set_final_tell", false)
	if s != "cast":
		_hide_cast_marks()
	_apply_look_state(s, length)
	state_changed.emit(s)


func _apply_look_state(s: String, length: float) -> void:
	if look == null:
		return
	var vs := "idle"
	match s:
		"climb":
			vs = "move"
		"pounce_tele":
			vs = "telegraph"
		"cast":
			vs = "spit"
		"drop":
			vs = "lunge"
		"stranded", "exposed", "scorch_fall":
			vs = "stunned"
		"intro", "release", "defeat":
			vs = "shriek"
		"rebound":
			vs = "recoil"
	look.call("set_state", vs, length)
	look.call("set_clinging", s in CEILING_STATES)


func _i() -> int:
	return Rules.ti(intensity())


## A warning / opening / recovery length after Settings timing_assist.
func _t(base: float) -> float:
	return base * Rules.TIMING_ASSIST_MULT if bool(Settings.get_value("timing_assist")) else base


func _enter_cling(length: float) -> void:
	var r: Array = Rules.T_CLING[_i()]
	var l := length if length >= 0.0 else _rng.randf_range(float(r[0]), float(r[1]))
	_enter("cling", l)
	if _marks != null:
		_marks.call("set_held", held_line, _body_point())


func _enter_recover() -> void:
	_enter("recover", _t(float(Rules.T_RECOVER[_i()])))


## What she does when a cling ends: the phase's rotation, skipping what is not allowed right now.
func _choose_action() -> void:
	var rot := Rules.rotation(phase)
	for n in rot.size():
		var act: String = rot[_step % rot.size()]
		_step += 1
		match act:
			"threads":
				if live_threads() == 0 and _begin_cast():
					return
			"release":
				if phase >= 3 and not _release_done and _begin_release():
					return
				if _begin_pounce(true):
					return
			"pounce":
				if _begin_pounce(false):
					return
			"delayed":
				if _begin_pounce(true):
					return
	_enter_cling(-1.0)           # nothing fair to do right now: she watches


# --- Threads (the hazard set) ---------------------------------------------------------------------------------------

func _begin_cast() -> bool:
	var p := _player()
	if p == null:
		return false
	var kp := p.global_position
	var bpos := _brazier_pos(held_line)
	var lane := Rules.side_of(_anchor_of(held_line), arena_center.z)
	var segs := Rules.thread_segments(bpos, lane, kp, int(Rules.THREADS_PER_CAST[_i()]), bridge, rail, deck_y)
	var ok_segs: Array = []
	var body := _body_point()
	for sg in segs:
		var mid: Vector3 = ((sg[0] as Vector3) + (sg[1] as Vector3)) * 0.5
		if _clear_ray(body, mid + Vector3.UP * 1.3):
			ok_segs.append(sg)
	var circles := Rules.brazier_circles(_brazier_positions())
	var targets := Rules.route_targets(_brazier_positions(), bridge)
	while not ok_segs.is_empty() and not Rules.route_ok(kp, targets, bridge, rail, ok_segs, circles):
		ok_segs.pop_back()
	if ok_segs.is_empty():
		return false
	_dissolve_threads()          # ONE hazard set: a new cast replaces what is left of the old one
	_cast_segs = ok_segs
	for i in _cast_segs.size():
		var m: Node3D = _cast_marks[i]
		var sg: Array = _cast_segs[i]
		m.call("show_lane", sg[0], sg[1], CAST_MARK_WIDTH, TelegraphFx.ROOT if _alt else TelegraphFx.COOL)
		_show_cast_bold(i, sg[0], sg[1])
	_enter("cast", _t(float(Rules.T_THREAD_TELE[_i()])))
	stats["casts"] = int(stats["casts"]) + 1
	_snd("threads", body, -3.0)
	Events.caption.emit(_caption("threads"))
	Events.hint.emit("boss_crossing_threads", "Threads fall across her lane to guard the brazier. Cut them with {interact}, raise your lantern to burn them, or go round by the other lane." if not _alt
		else "Pale roots fall across her lane to guard the brazier. Part them with {interact}, raise your lantern to burn them, or go round by the other lane.")
	return true


func _land_threads() -> void:
	var p := _player()
	var life := float(Rules.THREAD_LIFE[_i()])
	for sg in _cast_segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		# Krystal stepped under it meanwhile: this one falls short (never lands on her).
		if p != null and Rules.seg_dist(a, b, p.global_position) < Rules.KEEP_CLEAR * 0.75 and absf(p.global_position.y - deck_y) < 3.0:
			continue
		var node := _spawn_thread(a, b, life, held_line)
		if node == null:
			continue
		if node.has_signal("cleared"):
			node.connect("cleared", _on_thread_cleared.bind(node))
		_threads.append({"node": node, "a": a, "b": b, "line": held_line, "cut_t": -1.0, "done_t": -1.0})
		stats["threads"] = int(stats["threads"]) + 1
	_cast_segs = []
	_hide_cast_marks()


func _spawn_thread(a: Vector3, b: Vector3, life: float, line: int) -> Node3D:
	if arena != null and is_instance_valid(arena) and arena.has_method("spawn_thread"):
		var t: Variant = arena.call("spawn_thread", a, b, life, line)
		return t as Node3D if t is Node3D else null
	if not ResourceLoader.exists(THREAD_SCRIPT):
		return null
	var script: Script = load(THREAD_SCRIPT)
	if script == null or not script.can_instantiate():
		return null
	var parent: Node = get_parent() if get_parent() != null else self
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var t: Node3D = script.new()
	t.call("setup", {"id": "crossing_matron_thread_%d" % (int(stats["threads"]) + 1), "width": maxf(d.length(), 0.6),
		"height": THREAD_HEIGHT, "thick": false, "lifetime": life, "line": line})
	parent.add_child(t)
	t.global_position = Vector3((a.x + b.x) * 0.5, deck_y, (a.z + b.z) * 0.5)
	t.rotation.y = atan2(-d.z, d.x)
	return t


func _on_thread_cleared(_id: String, how: String, node: Node) -> void:
	for t in _threads:
		if t["node"] == node:
			if how == "cut":
				t["cut_t"] = 0.0
			else:
				t["done_t"] = 0.0


## Cut threads never regrow here (a thrown thread is not a doorway veil): their stubs linger, then they go.
## Spent nodes are freed so a long fight never piles them up.
func _tick_threads(delta: float) -> void:
	var i := _threads.size() - 1
	while i >= 0:
		var t: Dictionary = _threads[i]
		var node: Variant = t["node"]
		if node == null or not is_instance_valid(node) or (node as Node).is_queued_for_deletion():
			_threads.remove_at(i)
			i -= 1
			continue
		if float(t["cut_t"]) >= 0.0:
			t["cut_t"] = float(t["cut_t"]) + delta
			if float(t["cut_t"]) >= Rules.THREAD_CUT_LINGER:
				t["cut_t"] = -1.0
				(node as Node).call("dissolve")
		elif float(t["done_t"]) >= 0.0:
			t["done_t"] = float(t["done_t"]) + delta
			if float(t["done_t"]) >= THREAD_DONE_FREE:
				(node as Node).queue_free()
				_threads.remove_at(i)
		i -= 1


## [[a, b], ...] of the threads still standing (landings and routes avoid them).
func _thread_segs() -> Array:
	var out: Array = []
	for t in _threads:
		var node: Variant = t["node"]
		if node != null and is_instance_valid(node) and bool((node as Node).call("is_blocking")):
			out.append([t["a"], t["b"]])
	return out


func _dissolve_threads() -> void:
	for t in _threads:
		var node: Variant = t["node"]
		if node != null and is_instance_valid(node) and bool((node as Node).call("is_blocking")):
			(node as Node).call("dissolve")


func _burn_threads(line: int = -1) -> void:
	for t in _threads:
		var node: Variant = t["node"]
		if node == null or not is_instance_valid(node):
			continue
		if line >= 0 and int(t["line"]) != line:
			continue
		if String((node as Node).get("state")) in ["whole", "cut"]:
			(node as Node).call("burn", true)


func _hide_cast_marks() -> void:
	for m in _cast_marks:
		if m != null and is_instance_valid(m):
			(m as Node3D).call("hide_mark")
	for bold in _cast_bold:
		if bold != null and is_instance_valid(bold):
			(bold as Node3D).visible = false


## Settings high_visibility_cues: two bold cream rails along a thread's landing mark (local -Z runs a -> b).
func _show_cast_bold(i: int, a: Vector3, b: Vector3) -> void:
	if i < 0 or i >= _cast_bold.size():
		return
	var bold: Node3D = _cast_bold[i]
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var l := d.length()
	if l < 0.05:
		bold.visible = false
		return
	var yaw := atan2(-d.x, -d.z)
	bold.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 1.0, l)), a)
	bold.visible = bool(Settings.get_value("high_visibility_cues"))


func cast_bold_visible() -> bool:
	for bold in _cast_bold:
		if bold != null and is_instance_valid(bold) and (bold as Node3D).visible:
			return true
	return false


# --- Pounces (the committed attack) ------------------------------------------------------------------------------

## No pounce of any kind while a sac is pending or a minion lives (never together with the release).
func _pounce_allowed() -> bool:
	return not sacs_pending() and minions_alive() == 0


func _release_allowed() -> bool:
	return not (state in ["pounce_tele", "drop"])


func _begin_pounce(delayed: bool) -> bool:
	if not _pounce_allowed():
		return false
	var p := _player()
	if p == null or not _hunt_allowed(p) or not _valid_victim(p):
		return false
	var pos := _find_landing(p.global_position)
	if not pos.is_finite():
		return false
	_landing = pos
	_pounce_delayed = delayed
	_final_done = false
	_feint_done = false
	var length: float
	if delayed:
		_delayed = Rules.delayed_times(_i(), bool(Settings.get_value("timing_assist")))
		length = float(_delayed["total"])
		stats["delayed"] = int(stats["delayed"]) + 1
	else:
		_delayed = {}
		length = _t(float(Rules.T_POUNCE_TELE[_i()]))
		stats["pounces"] = int(stats["pounces"]) + 1
	_enter("pounce_tele", length)
	_mark.call("show_mark", pos, Rules.POUNCE_RADIUS, delayed, _alt)
	_snd("rattle", _body_point(), 0.0)
	Events.caption.emit(_caption("delayed" if delayed else "pounce"))
	if delayed:
		Events.hint.emit("boss_crossing_delayed", "A slow-pulsing ring: she waits for a FINAL rattle and flare before she drops. Step out of the ring - rolling too early won't help." if not _alt
			else "A slow-pulsing ring: she waits for a FINAL whisper and flare before she sinks. Step out of the ring - rolling too early won't help.")
	else:
		Events.hint.emit("boss_crossing_pounce", "A ring marks where she will pounce. Step out of it - if she misses, she is stranded for a moment." if not _alt
			else "A ring marks where she will sink down. Step out of it - if she misses, she is stranded for a moment.")
	return true


## A valid landing for Krystal at `kp`, or Vector3.INF: the pure rule first, then the arena's validated grid;
## both must have a floor under them and a clear line from her body (never through the deck or a ceiling).
func _find_landing(kp: Vector3) -> Vector3:
	var bps := _brazier_positions()
	var segs := _thread_segs()
	var res := Rules.pounce_landing(kp, bridge, rail, deck_y, bps, segs)
	if bool(res["ok"]) and _landing_reachable(res["pos"]):
		return res["pos"]
	if String(res["reason"]) == "off_deck":
		return Vector3.INF
	var best := Vector3.INF
	var best_d := Rules.POUNCE_MAX_OFFSET
	for lp in landing_points:
		var v: Vector3 = lp
		var d := _flat(v, kp)
		if d <= best_d and Rules.landing_valid(v, bridge, rail, deck_y, bps, segs) and _landing_reachable(v):
			best = v
			best_d = d
	return best


func _landing_reachable(pos: Vector3) -> bool:
	if require_floor and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.2, pos + Vector3.DOWN * 1.5, 1)
		var hit := _ray_skip_threads(q)
		if hit.is_empty() or absf(float((hit["position"] as Vector3).y) - deck_y) > 0.6:
			return false
	return _clear_ray(_body_point(), pos + Vector3.UP * 0.6)


func _tick_pounce_tele(delta: float) -> void:
	_face_toward(_landing, delta)
	_mark.call("set_progress", state_time / maxf(_state_len, 0.01))
	if not _pounce_delayed:
		return
	var feint_at := float(_delayed.get("feint_at", -1.0))
	if not _feint_done and feint_at >= 0.0 and state_time >= feint_at:
		_feint_done = true
		stats["feints"] = int(stats["feints"]) + 1
		_mark.call("feint")
		_snd("feint", _body_point(), -10.0)
		Events.caption.emit(_caption("feint"))
	if not _final_done and state_time >= float(_delayed.get("final_at", _state_len)):
		_final_tell()
	if _final_done:
		_mark.call("set_strand_top", _body_point())


## The delayed pounce's final preparation: audible (sound + caption) AND visible (mark + strand + halo + pose).
func _final_tell() -> void:
	_final_done = true
	stats["final_tells"] = int(stats["final_tells"]) + 1
	_mark.call("final_tell", _body_point())
	look.call("set_final_tell", true)
	look.call("set_state", "shriek", 0.6)
	_snd("final", _body_point(), -3.0)
	Events.caption.emit(_caption("final"))


func final_tell_shown() -> bool:
	return _final_done


func _begin_drop() -> void:
	_from = global_transform
	_to = _ground_pose(_landing, _player_pos())
	_mark.call("set_progress", 1.0)
	_enter("drop", float(Rules.T_DROP[_i()]))


func _land_pounce() -> void:
	global_transform = _to
	_mark.call("hide_mark")
	_snd("drop", _landing, 0.0)
	Events.camera_shake.emit(0.6, 0.35)
	HitFx.burst(_landing + Vector3.UP * 0.2, Color(0.72, 0.68, 0.76), 18, 4.0, 1.4, -9.0, 0.6, 85.0)
	var hit := false
	var p := _player()
	if p != null and _hunt_allowed(p) and _valid_victim(p) and Rules.pounce_hits(_landing, p.global_position) \
			and _clear_ray(_landing + Vector3.UP * 0.8, Combat.aim_point(p), 1 | 32, [p]):
		var h := Combat.find_health(p)
		if h != null:
			var dir := Rules.push_dir(_landing, p.global_position, bridge)
			var dealt: float = float(h.apply_damage(pounce_damage(_pounce_delayed), self, dir))
			if state != "drop":
				# That blow knocked Krystal out: Events.player_died already reset the fight from inside the
				# hit (dormant, back on her anchor). Nothing of this landing may run on after the reset.
				return
			if dealt > 0.0:
				hit = true
				stats["hits"] = int(stats["hits"]) + 1
				if p.has_method("knockback"):
					p.call("knockback", dir, float(data.get("knockback", 7.0)))
				Events.hitstop.emit(Combat.HITSTOP_HEAVY)
	_pounce_delayed = false
	if _pending_exposure:
		_pending_exposure = false
		_land_exposed()
	elif hit:
		_enter("rebound", Rules.T_REBOUND)
	elif at_floor():
		# Blows alone can't drive her off any more (Rules.HP_FLOOR): no false opening - only the light can.
		_enter("rebound", Rules.T_REBOUND)
		_floor_hint()
	else:
		_enter("stranded", _t(float(Rules.T_STRANDED[_i()])))
		Events.hint.emit("boss_crossing_stranded", "She missed and is stranded! Strike now with {attack}!")


## Her pose `k` (0..1) of the way through the current climb: one eased leg, or (side change) two - straight
## up to the ceiling, then along it to the far anchor, matching "[she scrambles across the ceiling]".
func climb_xform(k: float) -> Transform3D:
	if _mid_k <= 0.0 or _mid_k >= 1.0:
		return _lerp_xform(_from, _to, _smooth(k))
	if k < _mid_k:
		return _lerp_xform(_from, _mid, _smooth(k / _mid_k))
	return _lerp_xform(_mid, _to, _smooth((k - _mid_k) / (1.0 - _mid_k)))


static func _smooth(k: float) -> float:
	var t := clampf(k, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The side change's corner: under the ceiling (at the target's hanging height) straight above her.
func _side_change_corner() -> void:
	var corner := Vector3(_from.origin.x, _to.origin.y, _from.origin.z)
	_mid = Transform3D(_to.basis, corner)
	var d1 := _from.origin.distance_to(corner)
	var d2 := corner.distance_to(_to.origin)
	_mid_k = d1 / (d1 + d2) if d1 > 0.3 and d2 > 0.3 else 0.0


func _begin_climb() -> void:
	var target := _anchor_of(held_line)
	_from = global_transform
	_to = _ceiling_pose(target, _player_pos())
	_mid_k = 0.0
	_enter("climb", float(Rules.T_CLIMB[_i()]))
	_snd("skitter", global_position, -2.0)


# --- The release -----------------------------------------------------------------------------------------------------

func _begin_release() -> bool:
	var p := _player()
	if p == null or _release == null:
		return false
	var n := int(Rules.MINIONS[_i()])
	var spots := Rules.sac_spots(p.global_position, _body_point(), n, bridge, rail, deck_y, _brazier_positions(), _thread_segs())
	if spots.is_empty():
		return false
	_release_done = true
	var params := {"damage_scale": float(Rules.MINION_DAMAGE[_i()]), "speed_scale": float(Rules.MINION_SPEED[_i()])}
	_release.call("begin", spots, _t(float(Rules.SAC_WARN[_i()])), n, params)
	_release.set("released_count", 0)
	stats["releases"] = int(stats["releases"]) + 1
	_enter("release", Rules.T_RELEASE)
	_snd("shriek", global_position, -8.0)
	Events.caption.emit(_caption("release"))
	Events.hint.emit("boss_crossing_release", "Sacs are shaking on the bridge ahead. Pop them with {attack}, or get ready." if not _alt
		else "Pale pods are trembling on the bridge ahead. Pop them with {attack}, or get ready.")
	return true


# --- Exposure ---------------------------------------------------------------------------------------------------------

## A line-brazier flared (lit, or stoked again). Under the anchor she holds: EXPOSED. Anywhere else: wasted.
func _on_line_fired(line: int, how: String) -> void:
	if _gone or _defeat_started or not fight_started:
		return
	if how == "flared":
		_burn_threads(line)          # (a lit brazier's own threads are burned by the arena)
	if line != held_line:
		stats["wasted_flares"] = int(stats["wasted_flares"]) + 1
		Events.caption.emit(_caption("wrong"))
		Events.hint.emit("boss_crossing_wrong_line", "That brazier is not under her anchor. Watch which anchor she holds - its brazier is the one that burns her." if not _alt
			else "That brazier is not under her seal. Watch which seal she floats beneath - its brazier is the one that breaks her hold.")
		return
	match state:
		"exposed", "scorch_fall":
			return
		"drop":
			_pending_exposure = true
			_count_exposure()
		"stranded", "rebound":
			_count_exposure()
			_land_exposed()
		_:
			_count_exposure()
			_from = global_transform
			var land := Rules.scorch_landing(global_position, bridge, rail, deck_y, _brazier_positions())
			_to = _ground_pose(_ground_at(land), _player_pos())
			_enter("scorch_fall", Rules.T_SCORCH_FALL)


func _count_exposure() -> void:
	exposures += 1
	stats["exposures"] = exposures
	_line_exposures[held_line] = int(_line_exposures.get(held_line, 0)) + 1
	_last_exposed_line = held_line
	if _marks != null:
		_marks.call("set_exposed", held_line)
	_clear_hazards(true)
	_snd("shriek", global_position, -3.0)
	Events.caption.emit(_caption("exposed"))
	Events.camera_shake.emit(0.45, 0.3)
	exposed.emit(held_line, exposures)
	var np := Rules.phase_for(exposures)
	if np != phase:
		phase = np
		Events.boss_phase_changed.emit(boss_id, phase)
		phase_changed.emit(phase)


func _land_exposed() -> void:
	global_transform = _ground_pose(_ground_at(Vector3(global_position.x, deck_y, global_position.z)), _player_pos())
	HitFx.burst(global_position + Vector3.UP * 0.3, Color(0.72, 0.68, 0.76), 14, 3.4, 1.3, -9.0, 0.6)
	_snd("drop", global_position, -1.0)
	_enter("exposed", _t(float(Rules.T_EXPOSED[_i()])))
	Events.hint.emit("boss_crossing_exposed", "The light burned her off the anchor! Strike now with {attack}!" if not _alt
		else "The light broke her hold! Strike now with {attack}!")
	# The flare scorches her too (never a health sponge). Not Krystal's blow: no window accounting.
	var scorch: float = float(health.max_hp) * Rules.scorch_fraction(exposures)
	_scorching = true
	health.damage_taken_mult = 1.0
	health.apply_damage(scorch, null, Vector3.ZERO)
	_scorching = false
	if state == "exposed":
		health.damage_taken_mult = Rules.EXPOSED_MULT


## After an exposure window she changes sides (north <-> south) and takes a line there.
func _change_sides() -> void:
	side = Rules.side_for(exposures)
	held_line = _pick_line(side, _last_exposed_line)
	_step = 0
	var target := _anchor_of(held_line)
	_from = global_transform
	_to = _ceiling_pose(target, _player_pos())
	_side_change_corner()
	var dist := global_position.distance_to(target)          # (the time of the straight line: pacing unchanged)
	_enter("climb", maxf(float(Rules.T_CLIMB[_i()]), dist / float(Rules.SHIFT_SPEED[_i()])))
	_snd("skitter", global_position, -1.0)
	Events.caption.emit(_caption("side"))
	if phase == 2:
		Events.hint.emit("boss_crossing_phase2", "She fled to the other side of the bridge. Her next pounce waits for a final rattle and flare." if not _alt
			else "She drifted to the other side of the bridge. Her next drop waits for a final whisper and flare.")
	elif phase >= 3:
		Events.hint.emit("boss_crossing_phase3", "She's back on the first side, and she may call her brood instead of pouncing. One more burn!" if not _alt
			else "She's back on the first side, and she may call pale sprouts instead of sinking down. One more burn!")


# --- Damage & defeat -------------------------------------------------------------------------------------------------

func _on_damaged(amount: float, _source: Node, _dir: Vector3) -> void:
	var shown := amount
	var floored := false
	if not _scorching:
		# Rules.HP_FLOOR: a blow that would take her past the floor for her exposure count stops at it (set
		# here, inside apply_damage, before it tests for death - so it never kills through the floor).
		var fl := hp_floor()
		if fl > 0.0 and health.hp < fl and health.hp + amount >= fl - 0.01:
			shown = maxf(amount - (fl - health.hp), 0.0)
			health.hp = fl
			floored = true
	HitFx.flash(self)
	if shown > 0.0:
		HitFx.number(get_aim_point() + Vector3.UP * 0.8, shown)
	Audio.play_3d("enemy_hurt", get_aim_point(), -2.0, 0.1)
	if health.dead or health.hp <= 0.0 or _scorching:
		return
	_window_damage += shown
	if state in VULNERABLE_STATES and (floored or _window_damage >= _window_cap - 0.001):
		_snd("shriek", global_position, -6.0)
		if floored:
			_floor_hint()
		if state == "exposed":
			_change_sides()
		else:
			_begin_climb()


## Weapon damage never takes her below this now (Rules.HP_FLOOR by exposures made; 0 = none). Only while the
## brazier rule is playable at all: without a Lantern the line-braziers can't be lit (boss_brazier needs it),
## so blows alone must still be able to finish her - the floor never turns into a softlock.
func hp_floor() -> float:
	if health == null or not GameState.has_item("lantern"):
		return 0.0
	return Rules.hp_floor(float(health.max_hp), exposures)


## True while blows alone can't wound her further (only an exposure moves the fight on).
func at_floor() -> bool:
	var fl := hp_floor()
	return fl > 0.0 and health != null and float(health.hp) <= fl + 0.01


func _floor_hint() -> void:
	Events.hint.emit("boss_crossing_floor", "She clings on too hard for blows alone now. Light the line-brazier under HER anchor to burn her off it!" if not _alt
		else "She holds on too hard for blows alone now. Light the line-brazier under HER seal to break her hold!")


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
	_clear_hazards(false)             # quietly: the arena's victory clears the bridge with its own captions
	for b in braziers:
		if is_instance_valid(b) and b.has_method("set_reusable"):
			b.call("set_reusable", false)
	_commit_victory()
	# --- presentation (after the commit) ---
	_apply_look_state("defeat", 1.5)
	if _marks != null:
		_marks.call("set_held", -1, global_position)      # she lets go of her anchor: no tether left hanging
	_snd("shriek", global_position, -3.0)
	Events.caption.emit(_caption("defeat"))
	Events.camera_shake.emit(0.5, 0.8)
	if is_inside_tree() and not fast_defeat:
		var path := retreat_path()
		var tw := create_tween()
		tw.tween_interval(RETREAT_SHRIEK)
		tw.tween_callback(_retreat_lift.bind(path[0]))
		tw.tween_property(self, "global_position", path[0], RETREAT_UP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "global_position", path[1], _leg_time(path[0], path[1], 0.6)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(_retreat_wall)
		var down := _leg_time(path[1], path[2], 0.4)
		tw.tween_property(self, "global_position", path[2], down).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if look != null:
			tw.parallel().tween_property(look, "scale", Vector3.ONE * RETREAT_SHRINK, down)
		tw.tween_callback(_retreat_mouth)
		tw.tween_property(self, "global_position", path[3], RETREAT_IN).set_ease(Tween.EASE_IN)
		await tw.finished
	_finish_retreat()


## Retreat step: she flips up to the ceiling (the Hollow Mother stays upright) and scrambles for the crack.
func _retreat_lift(up: Vector3) -> void:
	global_transform = Transform3D(_ceiling_pose(up, crack_point).basis, global_position)
	if look != null:
		look.call("set_state", "move", 0.0)


## Retreat step: over the gate she goes head-first down the wall (the Hollow Mother just sinks, upright).
func _retreat_wall() -> void:
	if _alt:
		return
	var dz := signf(arena_center.z - crack_point.z)
	global_transform = Transform3D(_basis_up(Vector3(0.0, 0.0, dz if dz != 0.0 else 1.0), Vector3.DOWN), global_position)


## Retreat step: at the route's mouth she turns into it and slips into the crack.
func _retreat_mouth() -> void:
	global_transform = Transform3D(_ground_pose(global_position, crack_point).basis, global_position)


## THE COMMIT (before any presentation): bar hidden, encounter over, Events.boss_defeated exactly once (the
## arena's listener grants rw_ch2_crossing -> ch2_crossing_cleared, opens the way and saves).
func _commit_victory() -> void:
	var was := fight_started
	fight_started = false
	Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
	if was:
		Events.boss_encounter_changed.emit(boss_id, false)
	_director_hold(false)
	if is_story() and int(stats["defeat_events"]) == 0:
		stats["defeat_events"] = 1
		Events.boss_defeated.emit(boss_id)
		if arena == null or not is_instance_valid(arena):
			# No arena listener (never in the shipped Works): commit the content bundle ourselves, once.
			var bundle: Dictionary = ItemDB.reward_bundle(REWARD_ID)
			var items: Dictionary = bundle.get("items", {}) if bundle.get("items", {}) is Dictionary else {}
			var flags: Array = (bundle.get("flags", []) as Array).duplicate() if bundle.get("flags", []) is Array else []
			if not flags.has(CLEAR_FLAG):
				flags.append(CLEAR_FLAG)
			GameState.grant_once(REWARD_ID, items, flags)
	defeated.emit()


func _finish_retreat() -> void:
	_gone = true
	state = "gone"
	visible = false
	remove_from_group("enemy")
	_clear_hazards(false)
	set_process(false)
	retreated.emit()
	state_changed.emit("gone")


## The crossing was cleared some other way while she lived (debug hook, a flag from elsewhere): she withdraws
## quietly - no second boss_defeated, no reward of her own.
func _leave_quietly() -> void:
	if _gone or _defeat_started:
		return
	_defeat_started = true
	_clear_hazards(false)
	for b in braziers:
		if is_instance_valid(b) and b.has_method("set_reusable"):
			b.call("set_reusable", false)
	if fight_started:
		fight_started = false
		Events.boss_health_changed.emit(boss_id, -1.0, health.max_hp)
		Events.boss_encounter_changed.emit(boss_id, false)
		_director_hold(false)
	_finish_retreat()


func _on_flag(flag: String, v: Variant) -> void:
	if flag == CLEAR_FLAG and is_story() and v is bool and v:
		_leave_quietly()


func _on_player_died() -> void:
	reset_fight()


## Threads (burned with a caption when `fx`, else dissolved), marks, sacs and minions: gone at once.
func _clear_hazards(fx: bool) -> void:
	if fx:
		_burn_threads(-1)
	else:
		_dissolve_threads()
	_cast_segs = []
	_hide_cast_marks()
	if _mark != null:
		_mark.call("hide_mark")
	if look != null:
		look.call("set_final_tell", false)
	if _release != null:
		_release.call("clear", fx)
		_release.call("dismiss")


# --- Poses & geometry --------------------------------------------------------------------------------------------------

func _anchor_of(line: int) -> Vector3:
	if line >= 0 and line < anchors.size():
		return anchors[line]
	if not anchors.is_empty():
		return anchors[0]
	return arena_center + Vector3.UP * 10.0


func _brazier_pos(line: int) -> Vector3:
	if line >= 0 and line < braziers.size() and braziers[line] is Node3D and is_instance_valid(braziers[line]) and (braziers[line] as Node3D).is_inside_tree():
		return (braziers[line] as Node3D).global_position
	var a := _anchor_of(line)
	return Vector3(a.x, deck_y, clampf(a.z, -rail + 0.8, rail - 0.8))


func _brazier_positions() -> Array:
	var out: Array = []
	for i in braziers.size():
		if braziers[i] is Node3D and is_instance_valid(braziers[i]) and (braziers[i] as Node3D).is_inside_tree():
			out.append((braziers[i] as Node3D).global_position)
	return out


func _pick_line(s: int, exclude: int) -> int:
	return Rules.pick_line(line_anchors, s, _player_pos(), exclude, _line_exposures, arena_center.z)


func _ceiling_y() -> float:
	if anchors.is_empty():
		return deck_y + 10.0
	var y := 0.0
	for a in anchors:
		y += (a as Vector3).y
	return y / float(anchors.size())


## Her body's centre (strand tops, line-of-sight origins).
func _body_point() -> Vector3:
	var h := float(look.call("body_height")) if look != null else 1.2
	if state in GROUND_STATES:
		return global_position + Vector3.UP * minf(h * 0.5, 1.5)
	if _alt:
		return global_position + Vector3.UP * h * 0.5
	return global_position + global_transform.basis.y * 0.6


## Transform hanging from a ceiling point, facing toward `look_at` horizontally (the Hollow Mother floats
## upright beneath her seal; the Matron clings upside down).
func _ceiling_pose(anchor: Vector3, look_at: Vector3) -> Transform3D:
	var fwd := Vector3(look_at.x - anchor.x, 0.0, look_at.z - anchor.z)
	if fwd.length_squared() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	if _alt:
		var h := float(look.call("body_height")) if look != null else 4.5
		return Transform3D(_basis_up(Vector3.UP, fwd), anchor + Vector3.DOWN * (h + 0.35))
	return Transform3D(_basis_up(Vector3.DOWN, fwd), anchor + Vector3.DOWN * 0.3)


func _ground_pose(pos: Vector3, look_at: Vector3) -> Transform3D:
	var fwd := Vector3(look_at.x - pos.x, 0.0, look_at.z - pos.z)
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


func _face_on_ceiling(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	var target := _ceiling_pose(_anchor_of(held_line), p.global_position)
	global_transform = _lerp_xform(global_transform, target, clampf(delta * 1.5, 0.0, 1.0))


func _face_toward(pos: Vector3, delta: float) -> void:
	var target := _ceiling_pose(_anchor_of(held_line), pos)
	global_transform = _lerp_xform(global_transform, target, clampf(delta * 2.0, 0.0, 1.0))


func _ground_at(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, 1)
	var hit := _ray_skip_threads(q)
	return p if hit.is_empty() else (hit["position"] as Vector3)


## A ray query that looks through the thrown threads (they are thin veils, not walls to her).
func _ray_skip_threads(q: PhysicsRayQueryParameters3D) -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = q.exclude
	for k in 6:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return hit
		var col: Variant = hit.get("collider")
		if col is Node and _is_thread_part(col):
			ex.append(hit["rid"])
			continue
		return hit
	return {}


## Line of sight (world | `mask`) from `a` to `b`, ignoring thrown threads and `exclude` bodies.
func _clear_ray(a: Vector3, b: Vector3, mask: int = 1, exclude: Array = []) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	var ex: Array[RID] = []
	for e in exclude:
		if e is CollisionObject3D and is_instance_valid(e):
			ex.append((e as CollisionObject3D).get_rid())
	q.exclude = ex
	q.collide_with_areas = false
	return _ray_skip_threads(q).is_empty()


static func _is_thread_part(n: Node) -> bool:
	var c: Node = n
	for k in 3:
		if c == null:
			return false
		if c.is_in_group("hw_thread"):
			return true
		c = c.get_parent()
	return false


func _in_arena(pos: Vector3) -> bool:
	if arena != null and is_instance_valid(arena):
		return pos.x >= bridge.position.x - 4.5 and pos.x <= bridge.end.x + 4.5 and absf(pos.z - arena_center.z) <= 12.0 \
			and absf(pos.y - deck_y) < 3.0
	return _flat(pos, arena_center) <= arena_radius + 1.0


# --- Helpers ---------------------------------------------------------------------------------------------------------

## Krystal (or the stand-in a test / the arena controller provides).
func _player() -> Node3D:
	if target_override != null:
		return target_override if is_instance_valid(target_override) else null
	if arena != null and is_instance_valid(arena):
		# (called several times a frame: no temporary arrays here)
		var po := _override_of(arena)
		if po != null:
			return po
		var ctl: Variant = arena.get("controller")
		if ctl is Object and is_instance_valid(ctl):
			po = _override_of(ctl)
			if po != null:
				return po
	var gp: Variant = Game.player
	if gp is Node3D and is_instance_valid(gp) and (gp as Node3D).is_inside_tree():
		return gp
	return null


static func _override_of(holder: Object) -> Node3D:
	var po: Variant = holder.get("player_override")
	if po is Node3D and is_instance_valid(po) and (po as Node3D).is_inside_tree():
		return po
	return null


func _player_pos() -> Vector3:
	var p := _player()
	return p.global_position if p != null else arena_center


func _hunt_allowed(p: Node3D) -> bool:
	if Game.mode == "dead" or Game.mode == "loading" or Game.mode == "cutscene":
		return false
	var h := Combat.find_health(p)
	return not (h != null and h.get("dead") == true)


## Faction filter: only Krystal (or the scripted stand-in) is ever a victim - never companions or enemies.
func _valid_victim(p: Node) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	if p.is_in_group("companion") or p.is_in_group("enemy"):
		return false
	return true


static func _is_krystal(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player") and not n.is_in_group("companion")


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _attack_def(id: String) -> Dictionary:
	var list: Variant = data.get("attacks")
	if list is Array:
		for a in list:
			if a is Dictionary and String((a as Dictionary).get("id", "")) == id:
				return a
	return {}


func _notice_companions() -> void:
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("notice_threat"):
			(c as Node).call("notice_threat", global_position)


## The arena holds the director for the fight (Works area set_fight); without an arena she does it herself.
func _director_hold(on: bool) -> void:
	if arena != null and is_instance_valid(arena):
		return
	var d: Variant = Game.director
	if d is Node and is_instance_valid(d) and (d as Node).has_method("suppress"):
		(d as Node).call("suppress", 9999.0 if on else 30.0)


func _disconnect_brazier(b: Variant) -> void:
	if not (b is Node) or not is_instance_valid(b):
		return
	for sig in ["lit", "flared"]:
		if (b as Node).has_signal(sig):
			for con in (b as Node).get_signal_connection_list(sig):
				var cb: Callable = con["callable"]
				if cb.get_object() == self:
					(b as Node).disconnect(sig, cb)


## QA only (cheats): --crossing-exposures=1|2 starts the fight as if that many exposures were made.
func _debug_exposure_jump() -> void:
	if _debug_jumped or exposures > 0 or not Debug.is_cheat_allowed() or not Debug.has_arg("crossing-exposures"):
		return
	_debug_jumped = true
	var n := clampi(int(Debug.arg("crossing-exposures", "0")), 0, 2)
	if n <= 0:
		return
	exposures = n
	phase = Rules.phase_for(n)
	side = Rules.side_for(n)
	held_line = _pick_line(side, -1)
	global_transform = _ceiling_pose(_anchor_of(held_line), _player_pos())
	if _marks != null:
		_marks.call("set_held", held_line, _body_point())


# --- Arachnophobia / looks ---------------------------------------------------------------------------------------------

func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


func _on_settings_changed(key: String) -> void:
	if _gone:
		return
	if key == "high_visibility_cues":
		# live, like the pounce ring: the thread landing marks on the deck right now get / lose their rails
		for i in _cast_segs.size():
			_show_cast_bold(i, _cast_segs[i][0], _cast_segs[i][1])
		return
	if key != "arachnophobia":
		return
	var on := _arachno()
	if on == _alt:
		return
	_alt = on
	if look != null:
		look.call("set_alt", on)
	if _marks != null:
		_marks.call("set_alt", on)
	if _release != null:
		_release.call("set_alt", on)
	if _mark != null and bool(_mark.call("is_showing")):
		_mark.call("set_alt", on)
	# Re-seat with the new body's hanging offset; timers are left untouched.
	if state in CEILING_STATES:
		global_transform = _ceiling_pose(_anchor_of(held_line), _player_pos())
	elif state == "climb":
		_to = _ceiling_pose(_anchor_of(held_line), _player_pos())
		if _mid_k > 0.0:
			_side_change_corner()          # the new body's hanging height (the timer is untouched)
	_apply_look_state(state, _state_len)
	if _marks != null and not _defeat_started:          # (retreating: she has let go - no tether)
		_marks.call("set_held", held_line, _body_point())


func _snd(kind: String, pos: Vector3, db: float) -> void:
	Audio.play_3d(sound_name(kind), pos, db, 0.05, 55.0)


## The existing sound played for `kind` in the current look (the two sets never share a creature sound).
func sound_name(kind: String) -> String:
	var s := _alt
	var n := kind
	match kind:
		"rattle":
			n = "shade_telegraph" if s else "weaver_rattle"
		"skitter":
			n = "shade_drift" if s else "weaver_skitter"
		"drop":
			n = "hit_hard" if s else "weaver_drop"
		"shriek":
			n = "shade_shriek" if s else "weaver_shriek"
		"threads":
			n = "dir_root_creak" if s else "dir_web_rustle"
		"final":
			n = "shade_whisper" if s else "dir_scratch"
		"feint":
			n = "shade_drift" if s else "weaver_skitter"
	return n


## The caption shown for `kind` in the current look (arachnophobia: veils, roots and seals - never silk).
func caption_text(kind: String) -> String:
	return _caption(kind)


func _caption(kind: String) -> String:
	var s := _alt
	match kind:
		"intro":
			return "[a hollow wail rolls over the service bridge]" if s else "[a shriek echoes over the service bridge]"
		"threads":
			return "[pale roots lash across the bridge]" if s else "[threads whip across the bridge]"
		"pounce":
			return "[a whisper gathers overhead]" if s else "[a dry rattle overhead]"
		"delayed":
			return "[a slow, gathering whisper overhead]" if s else "[a slow, deliberate rattle overhead]"
		"feint":
			return "[the whisper wavers...]" if s else "[she shifts her grip...]"
		"final":
			return "[the whisper catches - she sinks!]" if s else "[a sharp final rattle - she lets go!]"
		"exposed":
			return "[she wails as the light breaks her seal]" if s else "[she shrieks as the light burns her off the anchor]"
		"side":
			return "[she drifts across to the far seals]" if s else "[she scrambles across the ceiling to the far side]"
		"release":
			return "[pale pods on the bridge begin to tremble]" if s else "[egg sacs on the bridge begin to shake]"
		"wrong":
			return "[the light flares under an empty seal]" if s else "[the light flares under an empty anchor]"
		"defeat":
			return "[the Hollow Mother wails and withdraws past the old service gate]" if s else "[the Matron shrieks and flees for the old service gate]"
	return ""
