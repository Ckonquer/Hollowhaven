extends CharacterBody3D
## A companion creature (Mochi, Pebble or Lumi): behaviour, befriending, commands and abilities.
## Built entirely in code (collision, interaction area, visual). Persistent state lives in
## GameState.companions[id]; this node is the living view of it and is recreated on area load.
##
## Contract (docs/ARCHITECTURE.md "Companions"):
##   companion_id, command(cmd) with cmd in pet/follow/wait/home/feed, get_interaction/interact,
##   react(reaction) happy/scared/notice/celebrate/dizzy, notice_threat(pos), on_player_respawned(),
##   teleport_near(pos). Group "companion", layer 4 (companion), mask world|structure; never collides
##   with the player. Lumi is also a "light_source" (light_radius, is_light_active()).
##
## States: a base `mode` driven by the GameState assignment (wild | follow | wait | home) plus a
## temporary `override` (working | afraid | refuse | celebrate | notice | befriending | reunite |
## charge | dizzy | leaving | attack | brave). get_state() returns the override if one is active.
##
## Chapter Two (MP §6, spec §9): `combat` (companion_combat.gd: basic attacks, the signature skill with one
## shared cooldown, Bloomguard / Stoneheart / Glimmerstep), `nav` (companion_nav.gd: obstacle-aware approach),
## `home_life` (companion_home.gd: bounded home behaviours). Commands gain "skill", "assist", "close", "ribbon".
## The Companion Skill action (companion_skill, default T) is read here by the follower (_unhandled_input,
## only when Game.gameplay_input_allowed()). Mochi's courage: flag c1x_mochi_courage (Brave Little Steps).

signal state_changed(state: String)
signal skill_changed(remaining: float, cooldown: float)

const Logic := preload("res://src/companions/companion_logic.gd")
const Support := preload("res://src/companions/companion_support.gd")
const CombatCtl := preload("res://src/companions/companion_combat.gd")
const Nav := preload("res://src/companions/companion_nav.gd")
const HomeLife := preload("res://src/companions/companion_home.gd")
const Fx := preload("res://src/companions/companion_fx.gd")
const VisualBase := preload("res://src/companions/companion_visual.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const CreaturesData := preload("res://data/creatures.gd")
const Layout := preload("res://data/world_layout.gd")
const VISUALS := {
	"mochi": "res://src/companions/mochi_visual.gd",
	"pebble": "res://src/companions/pebble_visual.gd",
	"lumi": "res://src/companions/lumi_visual.gd",
}
const FARMING_SCRIPT := "res://src/farming/farming.gd"
const COMBAT_SCRIPT := "res://src/combat/combat.gd"

const GRAVITY := 18.0
const JUMP_SPEED := 5.4
const ACCEL := 16.0
const MASK_WORLD := 1 | 32
const TEND_MINUTES := 30.0
const LUMI_NOTICE_RANGE := 14.0
const MOCHI_FEAR_RANGE := 8.0
const PEBBLE_CHARGE_RANGE := 7.0
const CHARGE_MAX_RISE := 1.6       # Pebble only charges enemies roughly on its own level
const HIDE_SECONDS := 4.0
const BRAVE_HIDE_SECONDS := 1.5    # Mochi with courage still trembles on horror cues, but only briefly
const CLOSE_FOLLOW_MULT := 0.6     # "Stay close": follow this much nearer
const ATTACK_OVERRIDE_SECONDS := 6.0
const ATTACK_STALL_SECONDS := 2.5  # no progress toward a melee target this long -> give up on it
const VISUAL_SCALE := 1.15         # a touch bigger in the world so they read well in tall grass
## Each creature has three voices (docs/ARCHITECTURE.md Audio names); generic cues map onto them.
const VOICE_MAP := {
	"mochi": {"chirp": "chirp", "happy": "happy", "scared": "scared", "warn": "scared", "grunt": "scared", "clack": "chirp", "chime": "chirp"},
	"pebble": {"chirp": "clack", "happy": "happy", "scared": "grunt", "warn": "grunt", "grunt": "grunt", "clack": "clack", "chime": "clack"},
	"lumi": {"chirp": "chime", "happy": "happy", "scared": "warn", "warn": "warn", "grunt": "warn", "clack": "chime", "chime": "chime"},
}

var companion_id: String = "mochi"
var def: Dictionary = {}
var visual: Node3D
var mode: String = "wild"
var override: String = ""
var pinned: bool = false
var boulder: Node3D = null

var home_pos := Vector3.ZERO
var wild_pos := Vector3.ZERO
var wait_pos := Vector3.ZERO
var threshold_pos: Variant = null
var light_radius: float = 5.0          # light_source contract (Lumi only is in the group)

var move_speed: float = 4.5
var follow_distance: float = 2.6
var side: float = 1.0

var _spawn_mode: String = ""
var _override_t: float = 0.0
var _player: Node3D = null
var _player_t: float = 0.0
var _trail: Array = []
var _stuck: Dictionary = {}
var _goal: Variant = null
var _goal_speed: float = 0.0
var _look: Variant = null
var _yaw: float = 0.0
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _los_t: float = 0.0
var _has_los: bool = true
var _scan_t: float = 0.0
var _wander_t: float = 2.0
var _wander_goal: Variant = null
var _ability_t: float = 30.0
var _gift_timer: float = 0.0
var _say_cd: float = 0.0
var _voice_cd: Dictionary = {}        # voice kind -> msec when it may play again
var _chirp_t: float = 6.0
var _emote_t: float = 3.0
var _idle_line_t: float = 120.0
var _refused_this_approach: bool = false
var _threat_pos: Variant = null
var _guard_t: float = 0.0
var _noticed: Dictionary = {}
var _notice_line_cd: float = 0.0
var _fear_line_cd: float = 0.0
var _charge_cd: float = 4.0
var _charge_target: Node3D = null
var _mine_cd: float = 0.0
var _work: Dictionary = {}
var _last_command_ms: int = -100000
var _sleeping: bool = false
var _greet_ready: bool = false
var _near_seen: bool = false
var _jump_cd: float = 0.0
var _ledge_t: float = 0.0
var _wait_idle_t: float = 0.0
var _home_far_t: float = 0.0
var _interact_area: Area3D
var _collision: CollisionShape3D
var _glow_target: float = 1.0
var _hidden_hint_done: bool = false
var _timeline: Tween
var _pvel := Vector3.ZERO
var _settled: bool = false
var _goal_choice: int = 0
var _peek_t: float = 2.0
var _progress: Dictionary = {}
var _los_track: Dictionary = {}
var _plast := Vector3.INF
var _blocked_t: float = 0.0
var _bag_full_noted: bool = false

# --- Chapter Two ---
var combat: RefCounted = null         # companion_combat.gd
var nav: RefCounted = null            # companion_nav.gd
var home_life: RefCounted = null      # companion_home.gd
var recoveries: int = 0               # safe-teleport recoveries (tests / telemetry)
var refuse_line: String = "refuse_below"
var threshold_flag: String = ""       # refusal at this threshold only once the flag is set ("" = always)
var _attack_best: float = INF
var _attack_stall: float = 0.0
var _skill_note_ms: int = -100000
var _safe_floor := Vector3.INF        # last spot it stood on while following (a fall mid boss fight returns here)
var _safe_floor_t: float = 0.0
var _ribbon_node: Node3D = null
var _default_home := Vector3.ZERO     # companion_home_<id> (used again when its nook is taken away)

static var _last_any_say_ms: int = -100000
static var _enemy_cache: Array = []
static var _enemy_cache_ms: int = -100000


## params: {"id", "mode" (wild|pinned|home|wait|follow|reunite|reunite_home), "home": Vector3,
##          "wild": Vector3, "wait": Vector3, "threshold": Vector3|null,
##          "refuse_line": creature line context said when refusing there (default "refuse_below"),
##          "threshold_flag": refuse there only once this flag is set (default: always)}
func setup(params: Dictionary) -> void:
	companion_id = String(params.get("id", companion_id))
	_spawn_mode = String(params.get("mode", ""))
	refuse_line = String(params.get("refuse_line", refuse_line))
	threshold_flag = String(params.get("threshold_flag", threshold_flag))
	if params.get("home") is Vector3:
		home_pos = params["home"]
		_default_home = home_pos
	if params.get("home_default") is Vector3:
		_default_home = params["home_default"]
	if params.get("wild") is Vector3:
		wild_pos = params["wild"]
	if params.get("wait") is Vector3:
		wait_pos = params["wait"]
	if params.get("threshold") is Vector3:
		threshold_pos = params["threshold"]


func _ready() -> void:
	_rng.randomize()
	name = "Companion_%s" % companion_id
	def = ItemDB.creature(companion_id)
	move_speed = float(def.get("move_speed", 4.5))
	follow_distance = float(def.get("follow_distance", 2.6))
	side = [1.0, -1.0, 1.0][maxi(Logic.ORDER.find(companion_id), 0) % 3]
	add_to_group("companion")
	add_to_group("interactable")
	if String(def.get("ability", "")) == "lightbearer":
		add_to_group("light_source")
	collision_layer = 4
	collision_mask = MASK_WORLD
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	_collision = CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.24
	_collision.shape = sh
	_collision.position = Vector3(0, 0.25, 0)
	add_child(_collision)
	_interact_area = Area3D.new()
	_interact_area.name = "Interact"
	_interact_area.collision_layer = 16
	_interact_area.collision_mask = 0
	_interact_area.monitoring = false
	var ics := CollisionShape3D.new()
	var isph := SphereShape3D.new()
	isph.radius = 0.55
	ics.shape = isph
	ics.position = Vector3(0, 0.35, 0)
	_interact_area.add_child(ics)
	add_child(_interact_area)
	var vpath: String = VISUALS.get(companion_id, VISUALS["mochi"])
	visual = load(vpath).new()
	visual.name = "Visual"
	add_child(visual)
	visual.scale = Vector3.ONE * VISUAL_SCALE
	if visual.has_signal("action_event"):
		visual.action_event.connect(_on_visual_action)
	_stuck = Logic.new_stuck_tracker()
	_ability_t = _rng.randf_range(20.0, 32.0)
	_chirp_t = _rng.randf_range(4.0, 9.0)
	_idle_line_t = _rng.randf_range(90.0, 160.0)
	_yaw = _rng.randf_range(-PI, PI)
	visual.rotation.y = _yaw
	Events.companion_assignment_changed.connect(_on_assignment_changed)
	Events.harvested.connect(_on_harvested)
	Events.zone_entered.connect(_on_zone_entered)
	Events.flag_set.connect(_on_flag_set)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.companion_bond_changed.connect(_on_bond_changed)
	Events.structure_placed.connect(_on_structure_placed)
	Events.structure_removed.connect(_on_structure_removed)
	Events.horror_event.connect(_on_horror_event)
	combat = CombatCtl.new(self, companion_id)
	nav = Nav.new(self)
	home_life = HomeLife.new(self, companion_id)
	_init_mode()
	_init_threshold_guard()
	refresh_ribbon()
	if is_befriended() and Logic.is_surface_area(Game.area_id):
		home_life.call_deferred("build_cairn")


func _init_mode() -> void:
	var rec := GameState.companion(companion_id)
	match _spawn_mode:
		"pinned":
			pinned = true
			mode = "wild"
		"wild":
			mode = "wild"
		"reunite":
			mode = "follow"
			_set_override("reunite", 8.0)
		"reunite_home":
			mode = "home"
			_set_override("reunite", 8.0)
		"":
			mode = String(rec.get("assignment", "wild")) if bool(rec.get("befriended", false)) else "wild"
		_:
			mode = _spawn_mode
	if mode == "wait":
		var wp: Variant = Logic.vec_from(rec.get("wait_pos"))
		if wp is Vector3 and wait_pos == Vector3.ZERO:
			wait_pos = wp
		if wait_pos == Vector3.ZERO:
			wait_pos = global_position if is_inside_tree() else wild_pos
	_set_pinned(pinned)
	if companion_id == "lumi" and not GameState.is_befriended("lumi"):
		_glow_target = 1.0 if bool(GameState.get_flag(_rescue_flag())) else 0.28
		visual.set_glow(_glow_target)


## Created near the mine (Krystal just came back out, or a save loaded there): she's leaving, not
## going in, so this approach doesn't count for Mochi's refusal until she walks away and returns.
func _init_threshold_guard() -> void:
	_refresh_player(true)
	if threshold_pos is Vector3 and _player != null:
		var tp: Vector3 = threshold_pos
		if not Logic.approach_reset(_flat(_player.global_position - tp).length()):
			_refused_this_approach = true


# --- Public API -------------------------------------------------------------------------------------

func get_state() -> String:
	return override if override != "" else mode


func get_display_name() -> String:
	return String(def.get("name", companion_id.capitalize()))


func is_light_active() -> bool:
	return is_in_group("light_source") and _glow_target > 0.5


func is_befriended() -> bool:
	return GameState.is_befriended(companion_id)


## Signature skill (manual: the Companion Skill action / Friends panel; else the autocast). One cooldown for
## both, on the play_seconds timeline. Returns {"ok", "reason", "skill"}.
func use_skill(manual: bool = true) -> Dictionary:
	var r: Dictionary = combat.use_skill(manual)
	skill_changed.emit(Support.remaining(companion_id), Support.cooldown(companion_id))
	return r


## {"ready", "remaining", "cooldown", "ok", "reason", "name", "range"} for the UI.
func skill_status() -> Dictionary:
	return combat.skill_status()


## Telemetry (src/qa/qa_telemetry.gd companion_skill_info): skill_status() plus what the combat layer is doing.
func get_skill_state() -> Dictionary:
	var s := skill_status()
	s["state"] = get_state()
	s["target"] = String(combat.target.name) if combat.has_target() else ""
	s["attacks"] = int(combat.attacks_fired)
	s["healing"] = not (combat.hot as Dictionary).is_empty()
	s["nav"] = String(nav.last_result) if nav != null else ""
	return s


## The Companion Skill action (rebindable, default T): only the follower answers, only while gameplay input
## is allowed (menus, pause, cutscenes and UI focus never leak it).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventJoypadMotion:
		return
	if not InputMap.has_action("companion_skill") or not event.is_action_pressed("companion_skill") or event.is_echo():
		return
	if mode != "follow" or GameState.active_companion != companion_id or not is_befriended():
		return
	if not Game.gameplay_input_allowed():
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	var r := use_skill(true)
	if not bool(r.get("ok", false)) and String(r.get("reason", "")) != "":
		var now := Time.get_ticks_msec()
		if now - _skill_note_ms > 900:
			_skill_note_ms = now
			Events.notify.emit(String(r["reason"]), "warn")


## Commands from the companion panel / hotkey: pet, follow, wait, home, feed, and (Chapter Two) skill,
## assist, close (behaviour modes) and ribbon (tie the Comfort Ribbon).
## Returns {"ok": bool, "text": String, "bond": int}.
func command(cmd: String) -> Dictionary:
	if not is_befriended():
		return {"ok": false, "text": "", "bond": 0}
	var now := Time.get_ticks_msec()
	var rec := GameState.companion(companion_id)
	var day := GameState.day()
	match cmd:
		"pet":
			var xp := Logic.pet_bond(rec, day)
			var perks: Array = Support.table(companion_id).get("perks_active", [])
			var affection := perks.has(5) and _affection_action() != ""
			if xp > 0:
				GameState.add_bond(companion_id, xp)
				_say("affection" if affection else "pet", 3.0, true)
			_face_player_now()
			if affection and not visual.is_busy():
				# 5-heart perk: a special affectionate animation (data/companion_skills.gd "affection").
				visual.play_action(_affection_action())
				visual.show_emote("heart", 2.0)
				Fx.hearts(get_parent(), global_position + Vector3.UP * 0.8, 3)
			else:
				_reaction_visual("happy")
			_voice("happy")
			Events.companion_reaction.emit(companion_id, "happy")
			return {"ok": true, "text": "", "bond": xp}
		"feed":
			var food := String(def.get("favorite_food", ""))
			var check := Logic.feed_check(rec, day, food != "" and GameState.has_item(food))
			if check == "no_food":
				var fname := ItemDB.display_name(food) if food != "" else "food"
				Events.notify.emit("You don't have any %s." % fname, "warn")
				visual.show_emote("question", 1.6)
				return {"ok": false, "text": "no_food", "bond": 0}
			if check == "full":
				_say_text("%s pats its tummy. Still full from earlier!" % get_display_name(), 2.5, true)
				visual.show_emote("dots", 1.6)
				return {"ok": false, "text": "full", "bond": 0}
			if not GameState.take_item(food, 1):
				return {"ok": false, "text": "no_food", "bond": 0}
			var fx := Logic.feed_bond(rec, day)
			GameState.add_bond(companion_id, fx)
			_face_player_now()
			visual.play_action("eat")
			visual.show_emote("heart", 2.0)
			_voice("happy")
			_say_text("%s munches the %s happily." % [get_display_name(), ItemDB.display_name(food)], 3.0, true)
			Events.companion_reaction.emit(companion_id, "happy")
			return {"ok": true, "text": "fed", "bond": fx}
		"follow", "wait", "home":
			if now - _last_command_ms < 300:
				return {"ok": false, "text": "debounced", "bond": 0}
			_last_command_ms = now
			if cmd == "follow":
				GameState.set_companion_assignment(companion_id, "follow")
				_say("follow", 2.5, true)
				_voice("chirp" if companion_id == "mochi" else ("clack" if companion_id == "pebble" else "chime"))
				visual.show_emote("exclaim", 1.2)
			elif cmd == "wait":
				GameState.set_companion_assignment(companion_id, "wait", Game.area_id, global_position)
				_say("wait", 2.5, true)
				visual.show_emote("dots", 1.4)
			else:
				GameState.set_companion_assignment(companion_id, "home")
				_say("home", 2.5, true)
				visual.show_emote("heart", 1.4)
			return {"ok": true, "text": cmd, "bond": 0}
		"skill":
			var r := use_skill(true)
			return {"ok": bool(r.get("ok", false)), "text": String(r.get("reason", "")), "bond": 0}
		"assist", "close":
			if Support.mode(companion_id) == cmd:
				return {"ok": true, "text": cmd, "bond": 0}
			Support.set_mode(companion_id, cmd)
			if cmd == "close" and override == "attack":
				_clear_override()
			_settled = false
			_say(cmd, 2.5, true)
			visual.show_emote("exclaim" if cmd == "assist" else "heart", 1.2)
			return {"ok": true, "text": cmd, "bond": 0}
		"ribbon":
			if not Support.give_ribbon(companion_id):
				return {"ok": false, "text": String(Support.ribbon_check(companion_id).get("reason", "")), "bond": 0}
			refresh_ribbon()
			_face_player_now()
			visual.play_action("happy")
			visual.show_emote("heart", 2.0)
			_voice("happy")
			_say("ribbon", 4.0, true)
			return {"ok": true, "text": "ribbon", "bond": 0}
	return {"ok": false, "text": "unknown", "bond": 0}


## Interaction contract (player probe).
func get_interaction(_player_node: Node = null) -> Dictionary:
	if pinned or override == "befriending" or override == "leaving":
		return {}
	if not is_befriended():
		return Logic.wild_prompt(companion_id, def, _wild_context())
	return {"text": "Talk to %s" % get_display_name(), "enabled": true}


func interact(_player_node: Node = null) -> void:
	if pinned or override == "befriending" or override == "leaving":
		return
	if not is_befriended():
		var p := get_interaction()
		if bool(p.get("enabled", false)):
			_befriend()
		else:
			visual.show_emote("drop" if _is_scared_now() else "question", 1.4)
		return
	_face_player_now()
	Game.open_panel("companion", {"id": companion_id})
	var ui_open := false
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("is_open"):
		ui_open = bool(Game.ui.is_open("companion"))
	if not ui_open:
		# No companion panel available: a friendly pet + follow/wait toggle.
		command("pet")
		_last_command_ms = -100000
		command("wait" if mode == "follow" else "follow")


## Reactions requested by other systems (director, ending, UI).
func react(reaction: String) -> void:
	if _uninterruptible():
		return
	match reaction:
		"happy":
			_reaction_visual("happy")
			_voice("happy")
		"scared":
			_hide_from(_threat_pos if _threat_pos is Vector3 else null, 3.5)
		"notice":
			var p: Vector3 = global_position + visual.global_basis.z * 5.0
			if _player != null:
				p = _player.global_position + _player_forward() * 6.0
			_notice(p, false)
		"celebrate":
			_set_override("celebrate", 2.6)
			visual.play_action("celebrate")
			visual.show_emote("sparkle", 2.2)
			_voice("happy")
			_say("celebrate", 3.0, false)
		"dizzy":
			_set_override("dizzy", 2.0)
			visual.play_action("dizzy")
	Events.companion_reaction.emit(companion_id, reaction)


## Horror director / authored moments: something is out there at `pos`.
func notice_threat(pos: Vector3) -> void:
	if pinned or not is_befriended() or _uninterruptible():
		return
	if companion_id == "mochi":
		if Support.has_courage(companion_id) and mode == "follow":
			# Brave Mochi still trembles and shelters behind Krystal, but only briefly: it keeps following
			# and healing (the combat layer works while "afraid").
			var was := override
			_hide_from(pos, BRAVE_HIDE_SECONDS)
			if was != "afraid" and _fear_line_cd <= 0.0:
				_fear_line_cd = 40.0
				_say("tremble", 3.0, false)
		else:
			_hide_from(pos, HIDE_SECONDS)
	else:
		_notice(pos, true)


## Horror cues (Events.horror_event: director events and authored moments). Mochi, following Krystal,
## shelters behind her: briefly once she found her courage (MP 6.4: a personality reaction that never stops
## the following or the healing), the old longer hide otherwise. Others keep their own authored reactions.
func _on_horror_event(_event_id: String, data: Dictionary) -> void:
	if companion_id != "mochi" or mode != "follow" or not is_befriended() or _player == null:
		return
	if override in ["afraid", "refuse", "brave", "befriending", "leaving"]:
		return
	var p: Variant = data.get("pos")
	if not (p is Vector3) or (p as Vector3) == Vector3.ZERO:
		p = _player.global_position + _player_forward() * 6.0     # somewhere ahead in the dark
	notice_threat(p)


func on_player_respawned() -> void:
	_clear_override()
	_threat_pos = null
	_guard_t = 0.0
	if combat != null:
		combat.reset()
	if mode == "follow":
		_refresh_player(true)
		if _player != null:
			teleport_near(_player.global_position)


## Places the companion safely near `pos` (behind Krystal / out of view if possible) with a poof.
## Only the follower is carried along (lift rides, "unstuck", stuck recovery): a companion told to
## wait, at home or still wild stays where Krystal left it, whoever asks.
func teleport_near(pos: Vector3) -> void:
	if not is_inside_tree():
		position = pos + Vector3(0.8, 0.05, 0.8)
		return
	if mode != "follow":
		return
	_refresh_player(true)
	var from := global_position
	var spot := find_safe_spot(pos)
	var parent := get_parent()
	if is_inside_tree() and from.distance_to(spot) > 1.0 and _visible_to_camera(from):
		Fx.poof(parent, from)
	global_position = spot
	velocity = Vector3.ZERO
	_trail.clear()
	Logic.reset_stuck(_stuck)
	_progress = {}
	_los_track = {}
	_settled = false
	if nav != null:
		nav.reset()
	Fx.poof(parent, spot, Color(1.0, 0.97, 0.92), 10, 0.8)


## Called by the spawner for the follower so it appears beside Krystal on area load.
func place_near_player() -> void:
	_refresh_player(true)
	if _player == null:
		return
	var ppos := _player.global_position
	var spot: Variant = _validate_spot(Logic.follow_goal(ppos, _player_forward(), side, follow_distance), ppos)
	global_position = spot if spot is Vector3 else find_safe_spot(ppos, false)
	_yaw = atan2(_player_forward().x, _player_forward().z)
	visual.rotation.y = _yaw
	_settled = true


func find_safe_spot(center: Vector3, prefer_hidden_first: bool = true) -> Vector3:
	if not is_inside_tree():
		return center + Vector3(0.8, 0.0, 0.8)
	var cam := _camera()
	var cam_pos: Variant = cam.global_position if cam != null else null
	var cands := Logic.placement_candidates(center, _player_forward(), cam_pos, side)
	for prefer_hidden in ([true, false] if prefer_hidden_first else [false]):
		for c in cands:
			var v: Variant = _validate_spot(c, center)
			if v == null:
				continue
			var p: Vector3 = v
			if prefer_hidden and cam != null and Logic.in_view(cam.global_position, -cam.global_basis.z, p + Vector3.UP * 0.3, 52.0):
				continue
			return p
	var fb: Variant = _validate_spot(center + Vector3(0.6, 0.0, 0.6), center)
	return fb if fb is Vector3 else center + Vector3(0, 0.1, 0)


# --- Pebble & the boulder --------------------------------------------------------------------------

func link_boulder(b: Node3D) -> void:
	boulder = b


## Called by pebble_boulder.gd when the last hit breaks it.
func release_from_boulder() -> void:
	if not pinned:
		return
	_set_pinned(false)
	boulder = null
	_befriend()


func on_boulder_wobble() -> void:
	if pinned:
		visual.play_action("stomp")
		if _rng.randf() < 0.5:
			visual.show_emote("exclaim", 1.0)


func _set_pinned(on: bool) -> void:
	pinned = on
	if _collision != null:
		_collision.disabled = on
	if _interact_area != null:
		_interact_area.collision_layer = 0 if on else 16
	if visual != null:
		visual.set_mood("pinned" if on else "idle")


# --- Main loop ----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	_tick_timers(delta)
	_refresh_player(false)
	_track_player(delta)
	if pinned:
		_goal = null
		_look = _player.global_position + Vector3.UP * 1.2 if _player != null and _dist_player() < 10.0 else null
		_update_visual()
		return
	_goal = null
	_goal_speed = 0.0
	_look = null
	var st := get_state()
	match st:
		"wild":
			_state_wild(delta)
		"follow":
			_state_follow(delta)
		"wait":
			_state_wait(delta)
		"home":
			_state_home(delta)
		"working":
			_state_working(delta)
		"afraid":
			_state_afraid(delta)
		"refuse":
			_state_refuse(delta)
		"notice", "celebrate", "dizzy", "befriending", "brave":
			_state_hold(delta)
		"reunite":
			_state_reunite(delta)
		"charge":
			_state_charge(delta)
		"leaving":
			_state_leaving(delta)
		"attack":
			_state_attack(delta)
	if mode == "follow" and override != "befriending" and override != "leaving":
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 0.45
			_scan_threats()
	if combat != null and is_befriended():
		combat.tick(delta)
	# Safety net: the stuck detectors only run in plain follow. A follower busy with an override
	# (Mochi hiding while a Brambling keeps chasing Krystal can stay "afraid" for a long time,
	# working, cheering...) must never be left behind either.
	if mode == "follow" and override != "" and not (override in ["befriending", "leaving", "refuse", "brave"]):
		if _player != null and _dist_player() > Logic.STUCK_FAR + 4.0:
			_recover("far")
	_move(delta)
	_update_visual()
	_check_fall()
	_safe_floor_t -= delta
	if _safe_floor_t <= 0.0 and mode == "follow" and is_on_floor():
		_safe_floor_t = 0.5
		_safe_floor = global_position


func _tick_timers(delta: float) -> void:
	_say_cd = maxf(_say_cd - delta, 0.0)
	_notice_line_cd = maxf(_notice_line_cd - delta, 0.0)
	_fear_line_cd = maxf(_fear_line_cd - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_mine_cd = maxf(_mine_cd - delta, 0.0)
	_jump_cd = maxf(_jump_cd - delta, 0.0)
	_blocked_t = maxf(_blocked_t - delta, 0.0)
	_guard_t = maxf(_guard_t - delta, 0.0)
	if override != "" and _override_t > 0.0:
		_override_t -= delta
		if _override_t <= 0.0:
			_on_override_timeout()


func _refresh_player(force: bool) -> void:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return
	_player = null
	_player_t -= get_physics_process_delta_time()
	if not force and _player_t > 0.0:
		return
	_player_t = 1.0
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		_player = Game.player
	elif is_inside_tree():
		var p := get_tree().get_first_node_in_group("player")
		if p is Node3D:
			_player = p


# --- States -------------------------------------------------------------------------------------------

func _state_wild(delta: float) -> void:
	var d := _dist_player()
	match companion_id:
		"mochi":
			if _player != null and d < 7.0 and _player_sprinting():
				_hide_from(_player.global_position, HIDE_SECONDS)
				if not _hidden_hint_done:
					_hidden_hint_done = true
					Events.hint.emit("mochi_shy", "The little creature is shy. Walk slowly (don't sprint) when you're close.")
				return
			_wander(delta, wild_pos, 3.0, 1.1)
			if d < 9.0:
				_look = _player_head()
				if d < 4.0:
					_goal = null
			_wild_attention(delta, d)
			_chirp(delta, d, "chirp")
			# Pop up out of the tall glade grass now and then so Krystal can spot the little cap.
			_peek_t -= delta
			if _peek_t <= 0.0:
				_peek_t = _rng.randf_range(3.0, 5.5)
				if d < 28.0 and d > 3.0 and not visual.is_busy():
					visual.play_action("peek")
		"lumi":
			if not bool(GameState.get_flag(_rescue_flag())):
				_glow_target = 0.28
				visual.set_mood("scared")
				if global_position.distance_to(wild_pos) > 0.8:
					_goal = wild_pos
					_goal_speed = 1.5
				if d < 9.0:
					_look = _player_head()
					_emote_t -= delta
					if _emote_t <= 0.0:
						_emote_t = _rng.randf_range(5.0, 8.0)
						visual.show_emote("drop", 1.6)
			else:
				_glow_target = 1.0
				visual.set_mood("idle")
				if _player != null and d < 12.0:
					if not _near_seen:
						_near_seen = true
						visual.show_emote("exclaim", 1.4)
						_voice("chime")
					var away := global_position - _player.global_position
					away.y = 0.0
					if away.length() < 0.1:
						away = Vector3.BACK
					if d > 2.2:
						_goal = _player.global_position + away.normalized() * 1.7
						_goal_speed = 2.2
					_look = _player_head()
					_emote_t -= delta
					if _emote_t <= 0.0 and d < 4.0:
						_emote_t = _rng.randf_range(4.0, 6.0)
						visual.show_emote("heart" if _rng.randf() < 0.5 else "sparkle", 1.6)
				else:
					_near_seen = false
					_wander(delta, wild_pos, 1.5, 1.2)
			visual.set_glow(_glow_target)
			_chirp(delta, d, "chime")
		_:
			# Pebble freed but not befriended yet (rare): stand proudly and wait for Krystal.
			if d < 8.0:
				_look = _player_head()
			_wild_attention(delta, d)


func _wild_attention(delta: float, d: float) -> void:
	if _player == null:
		return
	if d < 6.0:
		if not _near_seen:
			_near_seen = true
			visual.show_emote("question", 1.6)
			_emote_t = 3.0
		_emote_t -= delta
		if _emote_t <= 0.0:
			_emote_t = _rng.randf_range(5.0, 8.0)
			var how: Dictionary = def.get("befriend", {})
			if String(how.get("type", "")) == "offer_item":
				var have := GameState.count_item(String(how.get("item", "")))
				visual.show_emote("berry", 1.8)
				if have >= int(how.get("count", 1)):
					visual.play_action("happy")
	elif d > 10.0:
		_near_seen = false


func _state_follow(delta: float) -> void:
	if _player == null:
		_idle_look(delta)
		return
	var ppos := _player.global_position
	var d := _dist_player()
	if _player_on_floor():
		Logic.trail_push(_trail, ppos)
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.25
		_has_los = _line_clear(global_position + Vector3.UP * 0.4, ppos + Vector3.UP * 0.6)
	var cam := _camera()
	var goal: Vector3
	if _guard_t > 0.0 and _threat_pos is Vector3:
		# Stay close behind Krystal, on the side away from the threat.
		var tp: Vector3 = _threat_pos
		var away := ppos - tp
		away.y = 0.0
		if away.length() < 0.1:
			away = -_player_forward()
		goal = ppos + away.normalized() * 1.05 + away.normalized().cross(Vector3.UP) * side * 0.35
		_look = tp + Vector3.UP * 0.5
	else:
		var cands := Logic.goal_candidates(ppos, _player_move_dir(), side, _follow_dist())
		if _los_t >= 0.24 or _goal_choice >= cands.size():
			_goal_choice = _pick_goal_choice(cands, ppos, cam)
		goal = cands[_goal_choice]
		_look = _player_head() if d < 6.0 else null
	if cam != null:
		goal = Logic.camera_safe(goal, ppos, cam.global_position, side)
	var player_speed := _player_speed()
	var vertical_gap := absf(ppos.y - global_position.y)
	if (not _has_los or vertical_gap > 1.0) and not _trail.is_empty() and d > 1.5:
		var crumb: Variant = Logic.trail_next(_trail, global_position)
		if crumb is Vector3:
			goal = crumb
	if d < 0.75:
		# Never stand inside Krystal: step aside.
		var aside := _flat(global_position - ppos)
		if aside.length() < 0.05:
			aside = -_player_forward()
		goal = ppos + aside.normalized() * 1.3
	var dg := _flat(goal - global_position).length()
	# Settle hysteresis: walk all the way to the spot first, then stay put (no fidgeting while
	# Krystal turns on the spot) as long as she's still, close, visible and we're not in the way.
	var can_settle := player_speed < 0.4 and _has_los and _guard_t <= 0.0 and vertical_gap < 1.0
	if can_settle and cam != null and Logic.in_camera_corridor(global_position, ppos, cam.global_position):
		can_settle = false
	if _settled:
		_settled = can_settle and d > 0.9 and d < _follow_dist() * 1.6
	else:
		_settled = can_settle and dg < 0.45
	if _settled:
		_goal = null
		_idle_line(delta, d)
	else:
		_goal = goal
		_goal_speed = Logic.follow_speed(dg, move_speed, player_speed)
	# Walking a found path around an obstacle: that IS progress (the detour may first lead away from her).
	if nav != null and nav.progressing():
		Logic.reset_stuck(_stuck)
		_progress = {}
		_los_track = {}
	# Recovery: too far, not closing the distance, not actually getting anywhere, or cut off.
	var status := Logic.stuck_update(_stuck, d, delta, _follow_dist())
	if status == "" and Logic.progress_update(_progress, global_position, _goal is Vector3 and dg > 1.0, delta):
		status = "no_progress"
	if status == "" and Logic.los_update(_los_track, _has_los, d, delta):
		status = "no_los"
	if status != "":
		_recover(status)
		return
	_follow_abilities(delta, d)
	_check_threshold()


## Follow distance for the current behaviour mode ("Stay close" follows nearer).
func _follow_dist() -> float:
	if is_befriended() and Support.mode(companion_id) == "close":
		return follow_distance * CLOSE_FOLLOW_MULT
	return follow_distance


## First follow spot Krystal can see (no wall between her and it), camera-safe.
func _pick_goal_choice(cands: Array, ppos: Vector3, cam: Camera3D) -> int:
	for i in cands.size():
		var c: Vector3 = cands[i]
		if cam != null:
			c = Logic.camera_safe(c, ppos, cam.global_position, side)
		if _line_clear(ppos + Vector3.UP * 0.5, c + Vector3.UP * 0.5):
			return i
	return 0


func _state_wait(delta: float) -> void:
	var dw := global_position.distance_to(wait_pos)
	if dw > 1.2:
		# Far from the spot (knocked off it, or stuck walking back): slip back
		# there once nobody is watching, like going home. There's no navmesh for long walks.
		_home_far_t = _home_far_t + delta if dw > 14.0 else 0.0
		if _home_far_t > 1.0 and (_player == null or (_dist_player() > 10.0 and not _visible_to_camera(global_position))):
			_home_far_t = 0.0
			global_position = _snap_to_ground(wait_pos)
			velocity = Vector3.ZERO
			return
		_goal = wait_pos
		_goal_speed = move_speed * 0.6
		_wait_idle_t = 0.0
		visual.set_mood("idle")
		return
	_home_far_t = 0.0
	_wait_idle_t += delta
	var d := _dist_player()
	if d < 7.0:
		_look = _player_head()
	visual.set_mood("rest" if _wait_idle_t > 6.0 and d > 3.0 else "idle")
	_idle_line(delta, d)


func _state_home(delta: float) -> void:
	var d := _dist_player()
	var dh := _flat(home_pos - global_position).length()
	# Far away (e.g. sent home from the other side of the woods): slip home unseen.
	if dh > 14.0:
		_home_far_t += delta
		if _home_far_t > 1.0 and (_player == null or (d > 24.0 and not _visible_to_camera(global_position))):
			_home_far_t = 0.0
			global_position = _snap_to_ground(home_pos + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)))
			velocity = Vector3.ZERO
			return
	else:
		_home_far_t = 0.0
	if not Logic.is_surface_area(Game.area_id) and Game.area_id != "":
		return
	if GameState.is_night():
		if home_life != null:
			if float(home_life.nap_left) > 0.0:
				home_life.interrupt()
			# Lumi pulses with the Haven's lamps once before bed (MP 6.5).
			if not _sleeping and home_life.tick_night(delta):
				return
		if dh > 0.6:
			_goal = home_pos
			_goal_speed = move_speed * 0.6
			_set_sleeping(false)
		else:
			_set_sleeping(true)
		return
	if home_life != null and float(home_life.nap_left) > 0.0:
		home_life.tick_day(delta, d)      # a little nap near home: stay asleep until it ends
		return
	_set_sleeping(false)
	if dh > 3.5:
		_goal = home_pos
		_goal_speed = move_speed * (1.0 if dh > 8.0 else 0.6)
		return
	# Greet Krystal when she comes home.
	if d > 18.0:
		_greet_ready = true
	elif d < 6.0 and _greet_ready:
		_greet_ready = false
		_reaction_visual("happy")
		_voice("happy")
	if d < 6.0:
		_look = _player_head()
	_wander(delta, home_pos, 3.0, 1.0)
	if home_life != null and home_life.tick_day(delta, d):
		return
	_home_abilities(delta, d)
	_idle_line(delta, d)


func _state_working(delta: float) -> void:
	var kind := String(_work.get("kind", ""))
	var phase := String(_work.get("phase", "go"))
	var target: Vector3 = _work.get("pos", global_position)
	if kind == "present" and _player != null:
		target = _player.global_position
	if phase == "go":
		var reach := float(_work.get("reach", 0.8))
		var dist := _flat(target - global_position).length()
		# Solid targets (rocks, bushes): bumping into them close by counts as arrived.
		var arrived := dist <= reach or (_blocked_t > 0.0 and dist < 2.6)
		if not arrived:
			_goal = target
			_goal_speed = move_speed * float(_work.get("speed", 0.9))
			_look = target + Vector3.UP * 0.3
			_work["go_t"] = float(_work.get("go_t", 0.0)) + delta
			if float(_work["go_t"]) > 7.0:
				_finish_work()
			return
		_work["phase"] = "act"
		_face_towards(target)
		var anim := String(_work.get("anim", "gather"))
		var alen: float = visual.play_action(anim)
		_work["act_t"] = alen + 0.25
		return
	_look = target + Vector3.UP * 0.3
	_work["act_t"] = float(_work.get("act_t", 0.0)) - delta
	if float(_work["act_t"]) <= 0.0:
		_finish_work()


func _state_afraid(_delta: float) -> void:
	visual.set_mood("scared")
	var hide: Variant = _hide_spot()
	if hide is Vector3:
		_goal = hide
		_goal_speed = move_speed * 1.3
	if _threat_pos is Vector3:
		_look = _threat_pos
	elif _player != null:
		_look = _player_head()


func _state_refuse(_delta: float) -> void:
	if not (threshold_pos is Vector3):
		_finish_refuse()
		return
	var tp: Vector3 = threshold_pos
	if _flat(tp - global_position).length() > 0.8 and _override_t > 2.2:
		_goal = tp
		_goal_speed = move_speed
	_look = _player_head()
	if _override_t <= 2.2 and visual.get_action() != "refuse" and not bool(_work.get("refused", false)):
		_work["refused"] = true
		visual.play_action("refuse")
		visual.set_mood("scared")


func _state_hold(_delta: float) -> void:
	if _threat_pos is Vector3 and override == "notice":
		_look = _threat_pos
	elif _player != null and _dist_player() < 8.0:
		_look = _player_head()


func _state_reunite(_delta: float) -> void:
	if _player == null:
		return
	var d := _dist_player()
	_look = _player_head()
	if d > 1.6:
		_goal = _player.global_position
		_goal_speed = move_speed * 1.25
		return
	_reaction_visual("happy")
	visual.show_emote("heart", 2.0)
	_voice("happy")
	_say("reunite", 3.5, true)
	if mode == "home":
		_say_text("%s is so relieved you're back. It hops off home." % get_display_name(), 3.0, true)
	_clear_override()


func _state_charge(_delta: float) -> void:
	if _charge_target == null or not is_instance_valid(_charge_target) or not _charge_target.is_inside_tree():
		_clear_override()
		return
	var tp := _charge_target.global_position
	if absf(tp.y - global_position.y) > CHARGE_MAX_RISE + 0.4:
		_charge_target = null      # it climbed out of reach: give up (no bonk on thin air)
		_clear_override()
		return
	_look = tp + Vector3.UP * 0.4
	var dist := _flat(tp - global_position).length()
	if dist > 0.95:
		_goal = tp
		_goal_speed = 7.0
		return
	# Bonk! Bounce off comically, maybe a tiny bit of damage, then dizzy.
	var dir := _flat(tp - global_position)
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	velocity = -dir * 4.0 + Vector3.UP * 4.2
	_voice("clack")
	Fx.chips(get_parent(), global_position + dir * 0.4 + Vector3.UP * 0.3, Color("9a948a"), 6)
	_damage_enemy(_charge_target, 2.0, dir)
	_charge_target = null
	_set_override("dizzy", 2.0)
	visual.play_action("dizzy")
	Events.camera_shake.emit(0.08, 0.12)


## Melee pets (Pebble) walk to the enemy Krystal is fighting (obstacle-aware, leashed to her) and headbutt it
## on the cadence of companion_combat.gd; gives up when it can't get closer (never chases into geometry).
func begin_attack_approach() -> void:
	if override != "" or mode != "follow" or combat == null or not combat.has_target():
		return
	_attack_best = INF
	_attack_stall = 0.0
	_set_override("attack", ATTACK_OVERRIDE_SECONDS)


func _state_attack(delta: float) -> void:
	if combat == null or not combat.approach_ok():
		# Leash reached (or the target stopped counting): leave that enemy alone for a moment.
		if combat != null and combat.has_target():
			combat.give_up_target()
		_clear_override()
		return
	var t: Node3D = combat.target
	_look = t.global_position + Vector3.UP * 0.4
	if combat.within_reach(t):
		_goal = null
		_attack_best = INF
		_attack_stall = 0.0
		return
	_goal = combat.melee_spot()
	_goal_speed = move_speed * 1.35
	var dist := _flat(t.global_position - global_position).length()
	if dist < _attack_best - 0.3 or (nav != null and nav.progressing()):
		_attack_best = minf(dist, _attack_best)
		_attack_stall = 0.0
	else:
		_attack_stall += delta
		if _attack_stall > ATTACK_STALL_SECONDS:
			combat.give_up_target()


func _state_leaving(_delta: float) -> void:
	if _player != null:
		var away := _flat(global_position - _player.global_position)
		if away.length() < 0.1:
			away = Vector3.BACK
		_goal = global_position + away.normalized() * 2.0
		_goal_speed = move_speed * 0.7


func _idle_look(_delta: float) -> void:
	_look = null


# --- Movement ----------------------------------------------------------------------------------------

func _move(delta: float) -> void:
	var want := Vector3.ZERO
	if _goal is Vector3:
		var g: Vector3 = _goal
		var seek := g
		if nav != null and _nav_wanted():
			seek = nav.route(g, delta)      # around walls when the straight line is blocked (companion_nav.gd)
		var to := _flat(seek - global_position)
		var dist := to.length()
		var dist_goal := _flat(g - global_position).length()
		if dist > 0.12 and dist_goal > 0.12:
			var spd := _goal_speed
			if dist_goal < 0.6:
				spd *= clampf(dist_goal / 0.6, 0.25, 1.0)
			want = to / dist * spd
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var accel := ACCEL if is_on_floor() else ACCEL * 0.35
	hv = hv.move_toward(want, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -0.5)
		_try_hop(want)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Facing: toward travel, else toward what we're looking at.
	var face_dir := Vector3.ZERO
	if hv.length() > 0.35:
		face_dir = hv
	elif _look is Vector3:
		face_dir = _flat(_look - global_position)
	if face_dir.length() > 0.05:
		var target_yaw := atan2(face_dir.x, face_dir.z)
		var rate := 10.0 if hv.length() > 0.35 else 4.0
		_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-rate * delta))
	visual.rotation.y = _yaw


## Obstacle-aware routing is for travelling; work targets (rocks, bushes) are solid on purpose and a charge
## runs straight.
func _nav_wanted() -> bool:
	return not (override in ["working", "charge", "leaving", "befriending"]) and not pinned


## Small hops over low obstacles and gaps while travelling.
func _try_hop(want: Vector3) -> void:
	if _jump_cd > 0.0 or want.length() < 1.0:
		return
	var dir := want.normalized()
	var blocked := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y < 0.5 and n.dot(dir) < -0.4:
			blocked = true
			_blocked_t = 0.35
			break
	if blocked and override == "working":
		return       # bumping into the rock/bush we're walking to: no hop, we've arrived
	var gap := false
	_ledge_t -= get_physics_process_delta_time()
	if not blocked and _ledge_t <= 0.0:
		_ledge_t = 0.2
		var ahead := global_position + dir * 0.65
		var ground: Variant = _ray_ground(ahead + Vector3.UP * 0.5, 1.6)
		if ground == null and _goal is Vector3:
			var g: Vector3 = _goal
			gap = g.y > global_position.y - 1.0 and _flat(g - global_position).length() > 1.2
	if blocked or gap:
		velocity.y = JUMP_SPEED
		velocity.x = dir.x * maxf(want.length(), 3.2)
		velocity.z = dir.z * maxf(want.length(), 3.2)
		_jump_cd = 0.7


func _check_fall() -> void:
	var fell := global_position.y < Layout.KILL_Y
	if not fell and _player != null and mode == "follow":
		fell = global_position.y < _player.global_position.y - 12.0
	if not fell:
		return
	if mode == "follow" and _player != null:
		_recover("fell")
	else:
		var back := home_pos if mode == "home" else (wait_pos if mode == "wait" else wild_pos)
		global_position = _snap_to_ground(back)
		velocity = Vector3.ZERO


func _recover(reason: String) -> void:
	if _player == null:
		return
	if Game.boss_active() and _dist_player() > 12.0:
		# Never pop a fighting pet into a closed boss room: it keeps walking (breadcrumbs / nav) instead.
		# A pet that actually fell (off a ledge, out of the world) goes back to the last floor it stood on.
		if reason == "fell" and _safe_floor != Vector3.INF and global_position.y < _safe_floor.y - 4.0:
			global_position = _safe_floor
			velocity = Vector3.ZERO
			_trail.clear()
			if nav != null:
				nav.reset()
		Logic.reset_stuck(_stuck)
		_progress = {}
		_los_track = {}
		if override == "attack":
			_clear_override()
		return
	if override in ["working", "charge", "reunite", "attack"]:
		_clear_override()
	recoveries += 1
	teleport_near(_player.global_position)


func _wander(delta: float, center: Vector3, radius: float, speed: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = _rng.randf_range(3.0, 7.0)
		if _rng.randf() < 0.6:
			var a := _rng.randf_range(0.0, TAU)
			var r := sqrt(_rng.randf()) * radius
			_wander_goal = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		else:
			_wander_goal = null
			if _rng.randf() < 0.35:
				visual.play_action("sniff")
	if _flat(center - global_position).length() > radius + 1.5:
		_wander_goal = center
	if _wander_goal is Vector3:
		var wg: Vector3 = _wander_goal
		if _flat(wg - global_position).length() < 0.4:
			_wander_goal = null
		else:
			_goal = wg
			_goal_speed = speed


# --- Abilities -------------------------------------------------------------------------------------------

func _follow_abilities(delta: float, d: float) -> void:
	if override != "":
		return
	match String(def.get("ability", "")):
		"forager":
			_ability_t -= delta
			if _ability_t <= 0.0:
				_ability_t = _rng.randf_range(25.0, 40.0)
				if not _start_forage():
					_ability_t = 8.0
		"miner":
			_tick_gift(delta, d)


func _home_abilities(delta: float, d: float) -> void:
	if override != "":
		return
	match String(def.get("ability", "")):
		"forager":
			_ability_t -= delta
			if _ability_t <= 0.0:
				_ability_t = _rng.randf_range(22.0, 35.0)
				_start_tend()
		"miner":
			_tick_gift(delta, d)
			_ability_t -= delta
			if _ability_t <= 0.0:
				_ability_t = _rng.randf_range(14.0, 24.0)
				if _goal == null:
					visual.play_action("polish")
		"lightbearer":
			_ability_t -= delta
			if _ability_t <= 0.0:
				_ability_t = _rng.randf_range(10.0, 18.0)
				_wander_t = 0.0
				visual.play_action("glow_pulse")


func _start_forage() -> bool:
	if not is_inside_tree():
		return false
	var best: Node3D = null
	var best_d := 6.0
	for n in get_tree().get_nodes_in_group("harvestable"):
		if not (n is Node3D) or not n.has_method("get_harvest_info"):
			continue
		var n3: Node3D = n
		var dd := n3.global_position.distance_to(global_position)
		if dd >= best_d or not n3.is_visible_in_tree():
			continue
		var info: Variant = n3.get_harvest_info()
		if not (info is Dictionary) or String(info.get("tool", "")) != "hand" or bool(info.get("depleted", false)):
			continue
		# Mochi forages berries and grass only (not sticks, stones, glowcaps...).
		var k := String(info.get("kind", ""))
		if k != "" and k != "bush" and k != "grass":
			continue
		if n3.has_method("is_available") and not bool(n3.is_available()):
			continue
		if "depleted" in n3 and bool(n3.get("depleted")):
			continue
		best_d = dd
		best = n3
	if best == null:
		return false
	# A stuffed backpack: no foraging (it would only spill a new pickup + "Backpack full!" every time).
	if GameState.inventory.space_for("berries") <= 0 and GameState.inventory.space_for("fiber") <= 0:
		_note_bag_full()
		return false
	_bag_full_noted = false
	var info2: Dictionary = best.get_harvest_info()
	var label := (String(info2.get("kind", "")) + " " + String(info2.get("item", "")) + " " + String(info2.get("name", ""))).to_lower()
	var item := "fiber"
	if label.contains("berr") or label.contains("bush"):
		item = "berries"
	elif not (label.contains("grass") or label.contains("fiber")):
		item = "berries" if _rng.randf() < 0.5 else "fiber"
	if GameState.inventory.space_for(item) <= 0:
		item = "fiber" if item == "berries" else "berries"      # bring whatever still fits
	_start_work({"kind": "gather", "anim": "gather", "pos": best.global_position, "item": item, "reach": 0.9, "speed": 0.95})
	visual.show_emote("exclaim", 1.0)
	_voice("chirp")
	return true


func _start_tend() -> void:
	var plots: Array = []
	var fs: Script = _farming()
	var area_key := "surface" if Game.area_id == "" else Game.area_id
	if fs != null and fs.has_method("plots_needing_care"):
		var uids: Variant = fs.call("plots_needing_care", area_key)
		if uids is Array:
			for uid in uids:
				var pv: Variant = fs.call("plot_position", String(uid)) if fs.has_method("plot_position") else Logic.vec_from(GameState.structures.get(uid, {}).get("pos"))
				if pv is Vector3 and _flat(pv - home_pos).length() < 30.0:
					plots.append([String(uid), pv])
	else:
		for uid in GameState.crops:
			var c: Dictionary = GameState.crops[uid]
			if String(c.get("crop", "")) == "":
				continue
			var s: Dictionary = GameState.structures.get(uid, {})
			if String(s.get("area", "surface")) != area_key:
				continue
			var pv2: Variant = Logic.vec_from(s.get("pos"))
			if pv2 is Vector3 and _flat(pv2 - home_pos).length() < 30.0:
				plots.append([String(uid), pv2])
	if plots.is_empty():
		visual.play_action("sniff")
		return
	var pick: Array = plots[_rng.randi() % plots.size()]
	_start_work({"kind": "tend", "anim": "pat", "pos": pick[1], "uid": pick[0], "reach": 1.1, "speed": 0.6})


## Something to forage but no room in the backpack: tell Krystal once (until there's room again).
func _note_bag_full(with_emote: bool = true) -> void:
	if _bag_full_noted:
		return
	_bag_full_noted = true
	if with_emote:
		visual.show_emote("question", 1.4)
	_say_text("%s wants to forage, but your backpack is full." % get_display_name(), 3.0, false)


static func _farming() -> Script:
	if not ResourceLoader.exists(FARMING_SCRIPT):
		return null
	var fs: Script = load(FARMING_SCRIPT)
	if fs == null or not fs.can_instantiate():
		return null
	return fs


func _tick_gift(delta: float, d: float) -> void:
	if d < 7.0:
		_gift_timer += delta
	if _gift_timer < 40.0 or not Logic.gift_due(GameState.companion(companion_id), GameState.day()):
		return
	if _player == null or d > 9.0:
		return
	_gift_timer = 0.0
	_start_work({"kind": "present", "anim": "present", "pos": _player.global_position, "reach": 1.2, "speed": 1.0})
	visual.show_emote("sparkle", 1.4)


func _start_work(w: Dictionary) -> void:
	_work = w
	_work["phase"] = "go"
	_set_override("working", 12.0)


func _finish_work() -> void:
	_work = {}
	if override == "working":
		_clear_override()


func _on_visual_action(action_name: String) -> void:
	# Combat first: an attack's impact frame resolves its hit (whatever the override is).
	if combat != null and combat.on_action(action_name):
		return
	if override != "working":
		return
	if home_life != null and home_life.on_work_action(_work, action_name):
		return
	var kind := String(_work.get("kind", ""))
	var pos: Vector3 = _work.get("pos", global_position)
	var rec := GameState.companion(companion_id)
	match kind:
		"gather":
			if action_name != "gather":
				return
			var item := String(_work.get("item", "berries"))
			# The backpack may have filled up on the way: only hand over what fits (never a spill).
			if GameState.inventory.space_for(item) <= 0:
				item = "fiber" if item == "berries" else "berries"
			var n: int = mini(_rng.randi_range(1, 2), GameState.inventory.space_for(item))
			if n <= 0:
				visual.show_emote("dots", 1.2)
				_note_bag_full(false)
				return
			GameState.give_item(item, n, pos)
			_add_work_bond(rec)
			Fx.sparkles(get_parent(), pos + Vector3.UP * 0.4, 0.25, 6)
			_voice("happy")
			_say_text(_gather_line(item), 3.0, false)
			visual.show_emote("heart", 1.2)
		"tend":
			if action_name != "pat":
				return
			var uid := String(_work.get("uid", ""))
			_tend(uid, TEND_MINUTES)
			Fx.sparkles(get_parent(), pos + Vector3.UP * 0.2, 0.35, 6, Color(0.7, 1.0, 0.6))
			if _dist_player() < 12.0:
				_say("tend", 3.0, false)
		"headbutt":
			if action_name != "headbutt":
				return
			var it := String(_work.get("item", "stone"))
			if ItemDB.has_item(it):
				GameState.give_item(it, 1, pos)
			_voice("clack")
			Fx.chips(get_parent(), pos + Vector3.UP * 0.3, Color("9a948a"), 7)
			_add_work_bond(rec)
			_say("mine", 2.5, false)
		"present":
			if action_name != "present":
				return
			if Logic.gift_due(rec, GameState.day()):
				rec["last_gift_day"] = GameState.day()
				GameState.give_item("shiny_pebble", 1, global_position)
				_voice("happy")
				_say("gift", 3.5, true)
				visual.show_emote("heart", 1.8)


func _add_work_bond(rec: Dictionary) -> void:
	var xp := Logic.work_bond(rec, GameState.day())
	if xp > 0:
		GameState.add_bond(companion_id, xp)


func _gather_line(item: String) -> String:
	var lines: Array = CreaturesData.LINES.get(companion_id, {}).get("gather", [])
	var key := "berr" if item == "berries" else "fiber"
	for l in lines:
		if String(l).to_lower().contains(key):
			return String(l).replace("{name}", GameState.player_name)
	return ItemDB.creature_line(companion_id, "gather")


func _tend(uid: String, minutes: float) -> void:
	if uid == "" or not GameState.crops.has(uid):
		return
	var fs: Script = _farming()
	if fs != null and fs.has_method("tend"):
		fs.call("tend", uid, minutes)
		return
	var c: Dictionary = GameState.crops[uid]
	c["tended_minutes"] = float(c.get("tended_minutes", 0.0)) + minutes


func _on_harvested(node_kind: String, item_id: String, _count: int, pos: Vector3) -> void:
	if String(def.get("ability", "")) != "miner" or mode != "follow" or override != "" or pinned:
		return
	if not (node_kind == "rock" or node_kind == "ore") or _mine_cd > 0.0:
		return
	var near_me := pos.distance_to(global_position) <= 8.0
	var near_player := _player != null and pos.distance_to(_player.global_position) <= 8.0
	if not (near_me or near_player):
		return
	_mine_cd = 6.0
	_start_work({"kind": "headbutt", "anim": "headbutt", "pos": pos, "item": item_id, "reach": 0.95, "speed": 1.3})
	visual.show_emote("exclaim", 1.0)


func _on_zone_entered(zone_id: String) -> void:
	if mode != "follow" or not is_befriended() or zone_id == "":
		return
	if _player != null and _dist_player() > 25.0:
		return
	var xp := Logic.zone_bond(GameState.companion(companion_id), zone_id)
	if xp > 0:
		GameState.add_bond(companion_id, xp)


func _on_flag_set(flag: String, value: Variant) -> void:
	var cf := String(def.get("courage_flag", ""))
	if cf != "" and flag == cf and _truthy(value):
		# Courage found: no more refusing at the mine (an active refusal ends where it is).
		_refused_this_approach = false
		if override == "refuse":
			_clear_override()
		return
	if companion_id == "lumi" and flag == _rescue_flag() and bool(value) and not is_befriended():
		_glow_target = 1.0
		visual.set_glow(1.0)
		visual.set_mood("idle")
		visual.play_action("glow_pulse")
		visual.show_emote("sparkle", 1.8)
		_voice("chime")


func _on_enemy_killed(_enemy_id: String, pos: Vector3) -> void:
	if mode != "follow" or override != "" or _player == null:
		return
	if pos.distance_to(global_position) < 14.0:
		_threat_pos = null
		_guard_t = 0.0
		visual.play_action("happy" if companion_id != "pebble" else "stomp")


# --- Threats -------------------------------------------------------------------------------------------------

## Enemies the companions react to (shared, refreshed at most every 0.4 s). Boss hazards (meta "boss_hazard":
## the Matron's trip-lines and egg sacs are in group "enemy" so Krystal can cut / pop them) are left out, so no
## companion ever notices (Lumi), hides from (Mochi), charges (Pebble) or targets one.
func _enemies() -> Array:
	var now := Time.get_ticks_msec()
	if now - _enemy_cache_ms > 400 and is_inside_tree():
		_enemy_cache_ms = now
		_enemy_cache = CombatCtl.without_hazards(get_tree().get_nodes_in_group("enemy"))
	return _enemy_cache


## Untyped on purpose: the shared cache may hold an enemy freed since the last refresh, and a
## typed `Node` parameter would raise a script error on the call before we could check it.
static func _enemy_alive(e: Variant) -> bool:
	if e == null or not is_instance_valid(e) or not (e is Node3D) or not (e as Node3D).is_inside_tree():
		return false
	if e.has_method("is_dead") and bool(e.is_dead()):
		return false
	var h: Variant = e.get("health")
	if h is Object and is_instance_valid(h) and "dead" in h and bool(h.get("dead")):
		return false
	return true


func _scan_threats() -> void:
	if _player == null:
		return
	var ppos := _player.global_position
	var nearest: Node3D = null
	var nearest_d := INF
	var threatening: Node3D = null
	var threat_d := INF
	for e in _enemies():
		if not _enemy_alive(e):
			continue
		var e3: Node3D = e
		var dd := e3.global_position.distance_to(global_position)
		if dd < nearest_d:
			nearest_d = dd
			nearest = e3
		var dp := e3.global_position.distance_to(ppos)
		var active := bool(e3.is_threatening()) if e3.has_method("is_threatening") else dp < 6.0
		if active and dp < threat_d:
			threat_d = dp
			threatening = e3
	match companion_id:
		"lumi":
			if nearest != null and nearest_d <= LUMI_NOTICE_RANGE:
				var key := nearest.get_instance_id()
				var last := int(_noticed.get(key, -100000))
				if Time.get_ticks_msec() - last > 25000:
					if _noticed.size() > 48:
						_noticed.clear()       # respawning enemies over a long session: keep it small
					_noticed[key] = Time.get_ticks_msec()
					_notice(nearest.global_position, true)
				elif nearest.global_position.distance_to(ppos) < 10.0:
					_threat_pos = nearest.global_position
					_guard_t = 2.0
		"mochi":
			if threatening != null and (threat_d < MOCHI_FEAR_RANGE or threatening.global_position.distance_to(global_position) < MOCHI_FEAR_RANGE):
				if override != "afraid":
					_hide_from(threatening.global_position, 2.5)
				else:
					_threat_pos = threatening.global_position
					_override_t = maxf(_override_t, 2.0)
		"pebble":
			if threatening != null and threat_d < PEBBLE_CHARGE_RANGE and _charge_cd <= 0.0 and override == "":
				# Only things on the ground: never "charge" the Weaver on the ceiling or a stalker overhead.
				# Chapter Two: the brave opener obeys the combat rules too (auto attack on, Assist, a hittable
				# target in sight: never an armoured boss or through a wall).
				var reachable := absf(threatening.global_position.y - global_position.y) < CHARGE_MAX_RISE
				if reachable and combat != null and not combat.may_charge(threatening):
					reachable = false
				if reachable and threatening.global_position.distance_to(global_position) < 11.0:
					_charge_cd = 14.0
					_charge_target = threatening
					_set_override("charge", 4.0)
					visual.show_emote("exclaim", 1.0)
					_voice("grunt")
					_say("brave", 3.0, false)
	# Basic-attack target (companion_combat.gd): enemies Krystal is fighting, in sight, never peaceful ones.
	if combat != null:
		combat.scan(_enemies())


func _notice(pos: Vector3, warn: bool) -> void:
	_threat_pos = pos
	_set_override("notice", 1.4)
	visual.set_mood("alert")
	visual.play_action("notice")
	visual.show_emote("exclaim", 1.4)
	if companion_id == "lumi":
		_glow_target = 0.35
		visual.set_glow(_glow_target)
		_voice("warn")
		if warn and _notice_line_cd <= 0.0:
			_notice_line_cd = 75.0   # the glance + dim still happen every time; the spoken line stays rare
			_say("notice", 3.0, true)
	else:
		_voice("grunt" if companion_id == "pebble" else "scared")
	_guard_t = 6.0


func _hide_from(pos: Variant, seconds: float) -> void:
	_threat_pos = pos
	var was := override
	_set_override("afraid", seconds)
	visual.set_mood("scared")
	if was != "afraid":
		visual.show_emote("drop", 1.6)
		_voice("scared")
		if _fear_line_cd <= 0.0 and is_befriended() and _player != null:
			_fear_line_cd = 40.0
			_say("scared", 3.0, false)


func _hide_spot() -> Variant:
	if is_befriended() and _player != null and mode == "follow":
		var ppos := _player.global_position
		var away: Vector3
		if _threat_pos is Vector3:
			away = _flat(ppos - _threat_pos)
		else:
			away = -_player_forward()
		if away.length() < 0.1:
			away = -_player_forward()
		return ppos + away.normalized() * 1.0
	# Wild / at home / waiting: scurry away from whatever scared it, staying near its own spot.
	var base := wild_pos
	if mode == "home":
		base = home_pos
	elif mode == "wait":
		base = wait_pos
	var from: Vector3 = _threat_pos if _threat_pos is Vector3 else (_player.global_position if _player != null else global_position)
	var dir := _flat(base - from)
	if dir.length() < 0.1:
		dir = Vector3.BACK
	return base + dir.normalized() * 3.5


# --- Mochi & the mine --------------------------------------------------------------------------------------------

func _check_threshold() -> void:
	if not (threshold_pos is Vector3) or _player == null or override != "":
		return
	if threshold_flag != "" and not _truthy(GameState.get_flag(threshold_flag)):
		return
	var tp: Vector3 = threshold_pos
	var dt := _flat(_player.global_position - tp).length()
	if Logic.approach_reset(dt):
		_refused_this_approach = false
	var dares := bool(def.get("enters_below", true)) or Support.has_courage(companion_id)
	if Logic.should_refuse(dares, mode, dt, _refused_this_approach):
		_refused_this_approach = true
		_work = {}
		_set_override("refuse", 5.5)
		visual.show_emote("drop", 2.0)
		_voice("scared")
		_say(refuse_line, 4.5, true)


## Brave Little Steps (MP 6.4): wearing its Comfort Ribbon, beside the lit lantern at the OUTSIDE mine
## threshold (src/world/surface/c1x/courage_lantern.gd), Mochi finds its courage: the line, a brave little
## step, flag c1x_mochi_courage (+ the optional goal reads it). Mochi follows Krystal again afterwards.
func brave_step(at: Vector3) -> bool:
	var cf := String(def.get("courage_flag", ""))
	if cf == "" or not is_befriended() or _uninterruptible():
		return false
	_clear_override()
	_refused_this_approach = false
	if mode != "follow":
		GameState.set_companion_assignment(companion_id, "follow")
	GameState.set_flag(cf, true)
	GameState.request_quest_eval()
	_face_towards(at)
	_set_override("brave", 2.4)
	visual.play_action("brave_step")
	visual.show_emote("sparkle", 2.2)
	Fx.sparkles(get_parent(), global_position + Vector3.UP * 0.4, 0.45, 12, Color(1.0, 0.85, 0.9))
	_voice("happy")
	_say("courage", 5.0, true)
	return true


func _finish_refuse() -> void:
	var tp: Vector3 = threshold_pos if threshold_pos is Vector3 else global_position
	# Wait right at the threshold (so she's there to greet Krystal on the way out).
	var spot: Vector3 = tp if _flat(tp - global_position).length() < Logic.THRESHOLD_MATCH + 2.0 else global_position
	_clear_override()
	GameState.set_companion_assignment(companion_id, "wait", Game.area_id, spot)
	wait_pos = spot


# --- Befriending -------------------------------------------------------------------------------------------------

func _befriend() -> void:
	if is_befriended() or override == "befriending":
		return
	var how: Dictionary = def.get("befriend", {})
	if String(how.get("type", "")) == "offer_item":
		var item := String(how.get("item", ""))
		var need := int(how.get("count", 1))
		if not GameState.take_item(item, need):
			visual.show_emote("berry", 1.6)
			return
	_set_override("befriending", 0.0)
	_face_player_now()
	# Commit the friendship right away (state is safe even if the game is saved/quit mid-animation);
	# the override keeps the creature in place while the little ceremony plays.
	GameState.befriend(companion_id)
	if companion_id == "pebble":
		GameState.deplete(Logic.PINNED_BOULDER_ID, -1.0)
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	_timeline = create_tween()
	match companion_id:
		"mochi":
			visual.show_emote("berry", 1.2)
			visual.play_action("eat")
			_voice("chirp")
			_timeline.tween_interval(1.5)
		"pebble":
			visual.play_action("tumble")
			Fx.poof(get_parent(), global_position, Color("cfc8bd"), 16, 1.2)
			velocity = visual.global_basis.z * 2.5 + Vector3.UP * 3.0
			_timeline.tween_interval(1.1)
			_timeline.tween_callback(func() -> void: visual.play_action("salute"))
			_timeline.tween_interval(0.5)
		"lumi":
			_glow_target = 1.0
			visual.set_glow(1.0)
			visual.play_action("glow_pulse")
			_voice("chime")
			_timeline.tween_interval(1.3)
		_:
			_timeline.tween_interval(0.5)
	_timeline.tween_callback(_befriend_commit)
	_timeline.tween_interval(1.8)
	_timeline.tween_callback(_befriend_done)


func _befriend_commit() -> void:
	if not GameState.is_befriended(companion_id):
		return
	Audio.play_ui("ui_befriend")
	_voice("happy")
	if companion_id != "pebble":
		visual.play_action("happy")
	visual.show_emote("heart", 2.2)
	Fx.hearts(get_parent(), global_position + Vector3.UP * 0.8, 4)
	Fx.sparkles(get_parent(), global_position + Vector3.UP * 0.4, 0.5, 14)
	_say("befriend", 5.5, true)
	Events.companion_reaction.emit(companion_id, "happy")


func _befriend_done() -> void:
	if override == "befriending":
		_clear_override()
	_trail.clear()
	Logic.reset_stuck(_stuck)


func _wild_context() -> Dictionary:
	var how: Dictionary = def.get("befriend", {})
	var item := String(how.get("item", ""))
	return {
		"have": GameState.count_item(item) if item != "" else 0,
		"item_name": ItemDB.display_name(item) if item != "" else "",
		"scared": override == "afraid",
		"ruin_cleared": bool(GameState.get_flag(_rescue_flag())),
		"pinned": pinned,
	}


func _rescue_flag() -> String:
	return String(def.get("befriend", {}).get("flag", "ruin_cleared"))


# --- Assignment changes -------------------------------------------------------------------------------------------

func _on_assignment_changed(id: String, assignment: String) -> void:
	if id != companion_id:
		return
	_set_sleeping(false)
	if not pinned and visual != null:
		visual.set_mood("idle")
	if home_life != null:
		home_life.interrupt()
	if nav != null:
		nav.reset()
	if combat != null and assignment != "follow":
		combat.reset()
		if override == "attack":
			_clear_override()
	match assignment:
		"follow":
			mode = "follow"
			_trail.clear()
			Logic.reset_stuck(_stuck)
			_ability_t = _rng.randf_range(18.0, 30.0)
			if override in ["refuse", "leaving"]:
				_clear_override()
		"wait":
			mode = "wait"
			var wp: Variant = Logic.vec_from(GameState.companion(companion_id).get("wait_pos"))
			wait_pos = wp if wp is Vector3 else global_position
			_wait_idle_t = 0.0
		"home":
			mode = "home"
			_greet_ready = false
			if Game.area_id != "" and not Logic.is_surface_area(Game.area_id):
				_set_override("leaving", 2.2)
		"wild":
			mode = "wild"
	state_changed.emit(get_state())


# --- Overrides -----------------------------------------------------------------------------------------------------

func _set_override(o: String, seconds: float) -> void:
	# The befriend ceremony and leaving the Below are never interrupted: a "notice" replacing
	# "leaving" would strand a home-bound companion down there (home does nothing below).
	# Assignment changes end them explicitly through _clear_override().
	if _uninterruptible() and o != override:
		return
	override = o
	_override_t = seconds
	state_changed.emit(get_state())


func _uninterruptible() -> bool:
	return override == "befriending" or override == "leaving"


func _clear_override() -> void:
	var was := override
	override = ""
	_override_t = 0.0
	if was == "working":
		_work = {}
	if was == "attack":
		_attack_best = INF
		_attack_stall = 0.0
	if was in ["afraid", "notice", "refuse", "dizzy", "brave"]:
		visual.set_mood("idle")
	if companion_id == "lumi" and is_befriended():
		_glow_target = 1.0
		visual.set_glow(1.0)
	state_changed.emit(get_state())


func _on_override_timeout() -> void:
	match override:
		"refuse":
			_finish_refuse()
		"notice":
			_clear_override()
			if companion_id == "lumi":
				_glow_target = 0.7
				visual.set_glow(0.7)
				visual.show_emote("dots", 1.4)
		"leaving":
			Fx.poof(get_parent(), global_position)
			if Game.companion_nodes.get(companion_id) == self:
				Game.companion_nodes.erase(companion_id)
			queue_free()
		"afraid":
			_threat_pos = null
			_clear_override()
			if not is_befriended():
				visual.show_emote("question", 1.4)
		_:
			_clear_override()


# --- Helpers -----------------------------------------------------------------------------------------------------------

func _update_visual() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z).length()
	visual.set_motion(hv, is_on_floor())
	visual.set_look_target(_look)
	if companion_id == "lumi" and is_befriended() and override == "" and _guard_t <= 0.0 and not _sleeping:
		_glow_target = move_toward(_glow_target, 1.0, get_physics_process_delta_time() * 0.5)
		visual.set_glow(_glow_target)


func _reaction_visual(r: String) -> void:
	if r == "happy":
		visual.play_action("happy")
		visual.show_emote("heart", 1.8)


func _set_sleeping(on: bool) -> void:
	if on == _sleeping:
		return
	_sleeping = on
	if companion_id == "lumi" and is_befriended():
		_glow_target = 0.55 if on else 1.0      # a soft night-light while asleep
		visual.set_glow(_glow_target)
	if on:
		visual.set_mood("sleep")
	else:
		visual.set_mood("idle")
		visual.play_action("stretch")


func _chirp(delta: float, d: float, kind: String) -> void:
	if d > 22.0:
		return
	_chirp_t -= delta
	if _chirp_t <= 0.0:
		_chirp_t = _rng.randf_range(9.0, 16.0)
		_voice(kind, -3.0)


func _idle_line(delta: float, d: float) -> void:
	if d > 6.0:
		return
	_idle_line_t -= delta
	if _idle_line_t <= 0.0:
		_idle_line_t = _rng.randf_range(120.0, 220.0)
		var below := Game.area_id != "" and Logic.is_underground_area(Game.area_id)
		_say("idle_below" if below else "idle", 3.0, false)


func _say(context: String, duration: float = 3.0, priority: bool = false) -> void:
	_say_text(ItemDB.creature_line(companion_id, context), duration, priority)


func _say_text(line: String, duration: float, priority: bool) -> void:
	if line == "":
		return
	var now := Time.get_ticks_msec()
	if not priority and (_say_cd > 0.0 or now - _last_any_say_ms < 7000):
		return
	_say_cd = 4.0 if priority else 16.0
	_last_any_say_ms = now
	Events.say.emit(get_display_name(), line, duration)


func _voice(kind: String, volume_db: float = 0.0) -> void:
	kind = String(VOICE_MAP.get(companion_id, {}).get(kind, kind))
	var now := Time.get_ticks_msec()
	if now < int(_voice_cd.get(kind, 0)):
		return
	_voice_cd[kind] = now + 350      # msec timestamps: nothing to tick every frame
	var prefix := String(def.get("voice", companion_id))
	if is_inside_tree():
		Audio.play_3d("%s_%s" % [prefix, kind], global_position + Vector3.UP * 0.3, volume_db)


func _damage_enemy(e: Node3D, amount: float, dir: Vector3) -> void:
	var h: Variant = e.get("health")
	if not (h is Object and is_instance_valid(h) and h.has_method("apply_damage")):
		if ResourceLoader.exists(COMBAT_SCRIPT):
			var cs: Script = load(COMBAT_SCRIPT)
			if cs != null and cs.can_instantiate() and cs.has_method("find_health"):
				h = cs.call("find_health", e)
	if h is Object and is_instance_valid(h) and h.has_method("apply_damage"):
		h.apply_damage(amount, self, dir)


func _dist_player() -> float:
	return global_position.distance_to(_player.global_position) if _player != null else INF


func _player_head() -> Vector3:
	return _player.global_position + Vector3.UP * 1.3 if _player != null else global_position + Vector3.UP


func _player_forward() -> Vector3:
	if _player == null:
		return Vector3.FORWARD
	if _player.has_method("get_facing"):
		var f: Variant = _player.get_facing()
		if f is Vector3 and (f as Vector3).length() > 0.01:
			return f
	return -_player.global_basis.z


## Krystal's velocity estimated from her actual movement (robust to any player implementation,
## knockback and scripted moves); teleports are ignored.
func _track_player(delta: float) -> void:
	if _player == null:
		_plast = Vector3.INF
		_pvel = Vector3.ZERO
		return
	var p := _player.global_position
	if _plast != Vector3.INF and delta > 0.0:
		var v := (p - _plast) / delta
		v.y = 0.0
		if v.length() > 20.0:
			v = Vector3.ZERO
		_pvel = _pvel.lerp(v, 1.0 - exp(-12.0 * delta))
	_plast = p


func _player_move_dir() -> Vector3:
	if _pvel.length() > 0.5:
		return _pvel.normalized()
	return _player_forward()


func _player_speed() -> float:
	return _pvel.length()


func _player_on_floor() -> bool:
	if _player is CharacterBody3D:
		return (_player as CharacterBody3D).is_on_floor()
	return true


func _player_sprinting() -> bool:
	if _player != null and _player.has_method("is_sprinting"):
		return bool(_player.is_sprinting())
	return _player_speed() > 6.0


func _is_scared_now() -> bool:
	return override == "afraid" or (companion_id == "lumi" and not bool(GameState.get_flag(_rescue_flag())))


func _camera() -> Camera3D:
	if _player != null and _player.has_method("get_camera"):
		var c: Variant = _player.get_camera()
		if c is Camera3D and is_instance_valid(c):
			return c
	if is_inside_tree():
		return get_viewport().get_camera_3d()
	return null


func _visible_to_camera(p: Vector3) -> bool:
	var cam := _camera()
	if cam == null:
		return false
	if cam.global_position.distance_to(p) > 60.0:
		return false
	return Logic.in_view(cam.global_position, -cam.global_basis.z, p + Vector3.UP * 0.3, 55.0)


func _face_player_now() -> void:
	if _player != null:
		_face_towards(_player.global_position)


func _face_towards(p: Vector3) -> void:
	var d := _flat(p - global_position)
	if d.length() > 0.05:
		_yaw = atan2(d.x, d.z)
		if visual != null:
			visual.rotation.y = _yaw


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	return get_world_3d().direct_space_state


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var space := _space()
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, MASK_WORLD)
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


func _ray_ground(from: Vector3, depth: float) -> Variant:
	var space := _space()
	if space == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * depth, MASK_WORLD)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit["position"]


func _snap_to_ground(p: Vector3) -> Vector3:
	var g: Variant = _ray_ground(p + Vector3.UP * 1.5, 6.0)
	if g == null:
		g = _ray_ground(p + Vector3.UP * 40.0, 100.0)
	return (g as Vector3) + Vector3.UP * 0.05 if g is Vector3 else p


## A candidate spot is valid when there's ground under it near Krystal's height, room to stand,
## and nothing solid between Krystal and it (so it never ends up behind a wall).
func _validate_spot(c: Vector3, center: Vector3) -> Variant:
	var space := _space()
	if space == null:
		return c
	var q := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 2.5, c + Vector3.DOWN * 4.0, MASK_WORLD)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	if n.y < 0.6 or absf(p.y - center.y) > 2.5:
		return null
	var sq := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.26
	sq.shape = s
	sq.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.34)
	sq.collision_mask = MASK_WORLD
	sq.exclude = [get_rid()]
	if not space.intersect_shape(sq, 1).is_empty():
		return null
	if not _line_clear(center + Vector3.UP * 0.5, p + Vector3.UP * 0.5):
		return null
	return p + Vector3.UP * 0.05


# --- Chapter Two helpers ------------------------------------------------------------------------------------------------

static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return false


## The 5-heart affectionate animation id (data/companion_skills.gd perks[5].affection), "" if none.
func _affection_action() -> String:
	var perks: Dictionary = ItemDB.companion_skill(companion_id).get("perks", {})
	var p: Dictionary = perks.get(5, {})
	var a := String(p.get("affection", ""))
	return a if VisualBase.ACTIONS.has(a) else ""


## Shows the ribbon the companion wears (the Comfort Ribbon, or the 5-heart bond ribbon). Shared meshes.
const RIBBON_ANCHORS := {"mochi": Vector3(0.15, 0.5, 0.06), "pebble": Vector3(0.13, 0.46, 0.1), "lumi": Vector3(0.0, 0.36, -0.14)}
const RIBBON_COLORS := {"comfort_ribbon": Color("f4a0ab"), "bond_ribbon": Color("f2c14e")}


func refresh_ribbon() -> void:
	if visual == null:
		return
	var r := Support.ribbon(companion_id) if is_befriended() else ""
	if r == "":
		if _ribbon_node != null and is_instance_valid(_ribbon_node):
			_ribbon_node.visible = false
		return
	var col: Color = RIBBON_COLORS.get(r, Color("f4a0ab"))
	if _ribbon_node == null or not is_instance_valid(_ribbon_node):
		var parent: Variant = visual.get("body")
		var host: Node3D = parent if parent is Node3D else visual
		_ribbon_node = Node3D.new()
		_ribbon_node.name = "Ribbon"
		host.add_child(_ribbon_node)
		_ribbon_node.position = RIBBON_ANCHORS.get(companion_id, Vector3(0.12, 0.45, 0.05))
	for ch in _ribbon_node.get_children():
		ch.queue_free()
	var m := Mat.outlined(Mat.toon(col, {"rim": 0.3}), 0.008, Color(0.2, 0.13, 0.15))
	for s in [-1.0, 1.0]:
		var loop := Kit.sphere(0.05, m, 8, 12)
		Kit.add(_ribbon_node, loop, Vector3(0.045 * s, 0.0, 0.0), Vector3(0, 0, 20.0 * s), Vector3(1.0, 0.62, 0.42))
	var knot := Kit.sphere(0.022, m, 6, 10)
	Kit.add(_ribbon_node, knot, Vector3.ZERO)
	_ribbon_node.visible = true


func _on_bond_changed(id: String, _level: int) -> void:
	if id == companion_id:
		refresh_ribbon()


## A home spot from a companion nook (bed / perch), or null to go back to the Haven default.
func set_home_spot(pos: Variant) -> void:
	if pos is Vector3:
		home_pos = pos
	elif _default_home != Vector3.ZERO:
		home_pos = _default_home
	_wander_goal = null
	_home_far_t = 0.0
	if home_life != null:
		home_life.build_cairn()


func _on_structure_placed(uid: String, structure_id: String) -> void:
	if home_life != null and mode == "home" and is_befriended() and Logic.is_surface_area(Game.area_id):
		home_life.on_structure_placed(uid, structure_id)


func _on_structure_removed(uid: String, _structure_id: String) -> void:
	var rec := GameState.companion(companion_id)
	if uid != "" and String(rec.get("home_nook", "")) == uid:
		rec["home_nook"] = ""
		rec["home_spot"] = null
		set_home_spot(null)
