extends Node
## Music director (Chapter Two, MP 18.2). A child of the Audio autoload (created in Audio._ready), so
## it outlives scene changes, and PROCESS_MODE_ALWAYS (menus never restart the music). While
## `enabled` it is the single owner of the music: game code asks through Audio.request_music /
## Audio.release_music (authored scenes: title, restoration, bosses) or emits Events; nothing else
## calls Audio.play_music/stop_music.
##
## Every tick_s (0.2 s) it gathers the context (Game.mode/area_id/zone_id, GameState.is_night(), the
## boss/horror/combat state it learned from Events, what Audio is playing and where) and asks the pure
## core (src/audio/music_selector.gd, data/music.gd) what to do; it applies the answer through Audio
## (phrase-boundary starts are scheduled to the frame) and emits Events.music_cue_changed(cue).
## A throttled threat monitor (scan_s = 0.5 s) looks for enemies in group "enemy" whose
## is_threatening() is true within ~20 m of Krystal AND that can see her (line of sight) or that were
## engaged in the last few seconds (damage dealt/taken), so a stuck enemy behind a wall never pins the
## combat music; it emits Events.combat_state_changed when that changes.
##
## API: request(context_id, fade := -1.0), release(context_id, fade := -1.0), tick_now(),
##   get_debug_log() -> Array (last 50 decisions/notes; read-only copy for QA telemetry),
##   state() -> Dictionary, current_cue() -> String, reset(seed := -1), reseed(seed),
##   refresh_availability(), scan_threat(player) -> bool, gather_context() -> Dictionary.
## Tests/QA: setup({"seed", "tuning", "fade_scale", "tick_s", "ctx", "available"}) before add_child;
##   `ctx_override` entries replace gathered context keys; `enabled` switches the director off.
## Music Box (src/audio/music_box.gd, MP 18.3): preview(cue, fade := 1.5) -> bool, stop_preview(fade := 1.5),
##   preview_cue() -> String (a low-priority "musicbox" context: see music_selector.gd); the context carries
##   the saved favourites (ctx "favourites", read from GameState through the helper) for the Haven rotation.

const MusicData := preload("res://data/music.gd")
const Selector := preload("res://src/audio/music_selector.gd")
const MusicBox := preload("res://src/audio/music_box.gd")
## Chapter Two finished (Game.CH2_COMPLETE_FLAG, set by Game.complete_chapter_two): the Haven's day
## rotation then also includes Every Road Leads Home (m27).
const CH2_COMPLETE_FLAG := "chapter_two_complete"

var enabled: bool = true
var tick_s: float = 0.2
var scan_s: float = 0.5
var fade_scale: float = 1.0
var ctx_override: Dictionary = {}
var selector: RefCounted = null
var threat: bool = false               # threat monitor result (raw, before the selector's hysteresis)
var external_combat: bool = false      # combat_state_changed(true) emitted by someone else (e.g. an arena)
var last_context: Dictionary = {}

var _params: Dictionary = {}
var _t := 0.0
var _scan_t := 0.0
var _emitting := false
var _engaged_ms := -1000000
var _bosses: Dictionary = {}           # boss id -> {"active": bool, "phase": int, "seq": int}
var _boss_seq := 0
var _horror_state := ""
var _silence_until_ms := 0
var _silence_hold := false
var _hint := ""
var _late := false
var _scheduled: Dictionary = {}
var _avail_done := false
var _game: Node = null


func setup(params: Dictionary) -> void:
	_params = params.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	selector = Selector.new()
	var seed_v: int = int(_params.get("seed", _clock_seed()))
	selector.setup(MusicData.catalogue(), seed_v, _params.get("tuning", {}))
	fade_scale = float(_params.get("fade_scale", fade_scale))
	tick_s = float(_params.get("tick_s", float(selector.tuning.get("tick_s", tick_s))))
	if _params.get("ctx") is Dictionary:
		ctx_override = (_params["ctx"] as Dictionary).duplicate()
	Events.boss_health_changed.connect(_on_boss_health)
	Events.boss_encounter_changed.connect(_on_boss_encounter)
	Events.boss_phase_changed.connect(_on_boss_phase)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.horror_state_changed.connect(_on_horror_state)
	Events.horror_event.connect(_on_horror_event)
	Events.cutscene_changed.connect(_on_cutscene_changed)
	Events.chapter_completed.connect(_on_chapter_completed)
	Events.chapter2_completed.connect(_on_chapter2_completed)
	Events.combat_state_changed.connect(_on_combat_state)
	Events.music_context_changed.connect(_on_music_context)
	Events.player_died.connect(_on_player_died)
	Events.player_respawned.connect(_on_player_respawned)
	Events.player_damaged.connect(_on_engaged.unbind(2))
	Events.enemy_killed.connect(_on_engaged.unbind(2))
	Events.companion_attacked.connect(_on_engaged.unbind(2))
	Events.hitstop.connect(_on_engaged.unbind(1))
	Events.area_exiting.connect(_on_area_exiting)
	Events.area_loaded.connect(_on_area_loaded)


## Music randomness never uses the global RNG: its own seed comes from the clock (reseed() for QA).
func _clock_seed() -> int:
	return int(Time.get_ticks_usec() ^ (int(Time.get_unix_time_from_system() * 1000.0) << 8))


func _process(delta: float) -> void:
	if not _scheduled.is_empty() and Time.get_ticks_msec() >= int(_scheduled.get("at", 0)):
		var d := _scheduled
		_scheduled = {}
		if enabled:
			_do_play(d)
	if not enabled or selector == null:
		return
	_scan_t += delta
	if _scan_t >= scan_s:
		_scan_t = 0.0
		_update_threat()
	_t += delta
	if _t >= tick_s:
		tick_now()


## Evaluates immediately (also used after requests, so authored music starts in the same frame).
func tick_now() -> void:
	if not enabled or selector == null:
		return
	var dt := _t
	_t = 0.0
	if not _avail_done:
		refresh_availability()
	var ctx := gather_context()
	last_context = ctx
	var d: Dictionary = selector.update(ctx, dt)
	_apply(d)


## Which cues and stems exist as playable (imported) files right now.
func refresh_availability() -> void:
	var av: Dictionary = {}
	var audio := _audio()
	for id in MusicData.CUES:
		var c: Dictionary = MusicData.CUES[id]
		av[id] = audio != null and bool(audio.has_sound(String(c.get("track", "")), true))
		for l in (c.get("layers", []) as Array):
			av[String(l)] = audio != null and bool(audio.has_sound(String(l), true))
	if _params.get("available") is Dictionary:
		av.merge(_params["available"], true)
	selector.set_available(av)
	_avail_done = true


func _audio() -> Node:
	var a := get_node_or_null("/root/Audio")
	return a if a != null and a.has_method("try_play_music") else null


# ---------------------------------------------------------------------------------------------
# Public requests
# ---------------------------------------------------------------------------------------------

func request(context_id: String, fade: float = -1.0) -> void:
	if selector == null:
		return
	selector.request(context_id, fade, _area_id())
	tick_now()


func release(context_id: String, fade: float = -1.0) -> void:
	if selector == null or context_id == "":
		return
	# a released boss context also ends the fight seen through Events (e.g. Krystal left the arena)
	for bid in _bosses:
		if String(MusicData.BOSSES.get(bid, "")) == context_id:
			(_bosses[bid] as Dictionary)["active"] = false
	selector.release(context_id, fade)
	tick_now()


func current_cue() -> String:
	return String(selector.current_cue()) if selector != null else ""


## Music Box preview of one cue (one pass; boss / horror / combat / authored music end it). False when the
## cue is unknown or unplayable (nothing changes then).
func preview(cue: String, fade: float = 1.5) -> bool:
	if selector == null or not enabled:
		return false
	if not _avail_done:
		refresh_availability()
	var ok := bool(selector.request_preview(cue, fade, _area_id()))
	if ok:
		tick_now()
	return ok


func stop_preview(fade: float = 1.5) -> void:
	if selector == null or selector.preview_cue() == "":
		return
	selector.stop_preview(fade)
	tick_now()


## The cue being previewed ("" = none).
func preview_cue() -> String:
	return String(selector.preview_cue()) if selector != null else ""


func state() -> Dictionary:
	var s: Dictionary = selector.state() if selector != null else {}
	s["enabled"] = enabled
	s["threat"] = threat
	s["bosses"] = _bosses.duplicate(true)
	s["horror_state"] = _horror_state
	s["hint"] = _hint
	return s


## Last 50 decisions and notes, oldest first (a copy: QA telemetry reads it, nobody writes it).
func get_debug_log() -> Array:
	return selector.get_debug_log() if selector != null else []


## Fresh start (keeps data and availability). seed < 0 keeps the current seed.
func reset(seed_value: int = -1) -> void:
	if selector == null:
		return
	if seed_value >= 0:
		selector.reseed(seed_value)
	selector.reset()
	_scheduled = {}
	_bosses.clear()
	_horror_state = ""
	_silence_until_ms = 0
	_silence_hold = false
	_hint = ""
	_late = false
	threat = false
	external_combat = false
	_t = 0.0


func reseed(seed_value: int) -> void:
	if selector != null:
		selector.reseed(seed_value)


# ---------------------------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------------------------

func gather_context() -> Dictionary:
	var ctx: Dictionary = {"mode": "", "area": "", "zone": ""}
	var g := _game_node()
	if g != null:
		ctx["mode"] = _as_string(g.get("mode"))
		ctx["area"] = _as_string(g.get("area_id"))
		ctx["zone"] = _zone(g)
	ctx["hint"] = _hint
	ctx["night"] = _is_night(g)
	ctx["late"] = _late or _flag(CH2_COMPLETE_FLAG)
	ctx["paused"] = is_inside_tree() and get_tree().paused
	ctx["muted"] = _music_muted()
	ctx["threat"] = threat or external_combat
	var b := _active_boss()
	ctx["boss"] = b
	ctx["boss_phase"] = int((_bosses[b] as Dictionary).get("phase", 1)) if b != "" else 1
	ctx["horror_state"] = _horror_state
	ctx["silence"] = _silence_hold or Time.get_ticks_msec() < _silence_until_ms
	ctx["favourites"] = MusicBox.favourites_view()     # the saved list itself (no copy per tick)
	var audio := _audio()
	if audio != null:
		# while a phrase-aligned start is scheduled, report the track as already ours
		ctx["audio_track"] = String(selector.current_track()) if not _scheduled.is_empty() else String(audio.current_music())
		ctx["pos_s"] = float(audio.music_position())
		ctx["track_len_s"] = float(audio.music_length())
		var st: Variant = audio.music_stream()
		if st is AudioStream:
			var bpm: Variant = (st as AudioStream).get("bpm")
			if bpm is float or bpm is int:
				ctx["track_bpm"] = float(bpm)
			var bb: Variant = (st as AudioStream).get("bar_beats")
			if bb is int:
				ctx["track_bar_beats"] = int(bb)
	for k in ctx_override:
		ctx[k] = ctx_override[k]
	return ctx


func _game_node() -> Node:
	if not is_instance_valid(_game):
		_game = get_node_or_null("/root/Game")
	return _game


func _area_id() -> String:
	if ctx_override.has("area"):
		return String(ctx_override["area"])
	var g := _game_node()
	return _as_string(g.get("area_id")) if g != null else ""


## Game.zone_id, or the area's own answer right after a load (Game polls zones every 0.4 s).
func _zone(g: Node) -> String:
	var z := _as_string(g.get("zone_id"))
	if z != "":
		return z
	var area: Variant = g.get("area")
	var p: Variant = g.get("player")
	if is_instance_valid(area) and is_instance_valid(p) and area is Node and p is Node3D \
			and (area as Node).has_method("get_zone_at") and (p as Node3D).is_inside_tree():
		return _as_string((area as Node).call("get_zone_at", (p as Node3D).global_position))
	return ""


## The area's own sky decides day/night when it has one (the surface turns its ambience on
## sky.is_night, so the music turns at the same moment); otherwise the game clock.
func _is_night(g: Node) -> bool:
	if g != null:
		var area: Variant = g.get("area")
		if is_instance_valid(area) and area is Node:
			var sky: Variant = (area as Node).get("sky")
			if is_instance_valid(sky) and sky is Object:
				var n: Variant = (sky as Object).get("is_night")
				if n is bool:
					return n
	return GameState.has_method("is_night") and bool(GameState.call("is_night"))


func _music_muted() -> bool:
	var mb := AudioServer.get_bus_index("Music")
	return AudioServer.is_bus_mute(0) or (mb >= 0 and AudioServer.is_bus_mute(mb))


func _flag(name: String) -> bool:
	if not GameState.has_method("get_flag"):
		return false
	var v: Variant = GameState.call("get_flag", name)
	return v is bool and v


## The most recently engaged boss that has music of its own (elites such as the Knotted Elder also
## report encounters; they are scored as ordinary combat and never hide a real boss).
func _active_boss() -> String:
	var best := ""
	var best_seq := -1
	for id in _bosses:
		var b: Dictionary = _bosses[id]
		if not MusicData.BOSSES.has(id):
			continue
		if bool(b.get("active", false)) and int(b.get("seq", 0)) > best_seq:
			best = String(id)
			best_seq = int(b.get("seq", 0))
	return best


static func _as_string(v: Variant) -> String:
	return String(v) if v is String or v is StringName else ""


# ---------------------------------------------------------------------------------------------
# Applying decisions
# ---------------------------------------------------------------------------------------------

func _apply(d: Dictionary) -> void:
	var action := String(d.get("action", "none"))
	var audio := _audio()
	if audio == null:
		return
	if d.has("prefetch") and String(d["prefetch"]) != "":
		audio.prefetch_music(String(d["prefetch"]))
	if action == "none":
		return
	var fade := float(d.get("fade", 2.0)) * fade_scale
	match action:
		"play":
			_scheduled = {}
			var w := float(d.get("wait_s", 0.0))
			if w > 0.02:
				_scheduled = d.duplicate()
				_scheduled["at"] = Time.get_ticks_msec() + int(w * 1000.0)
			else:
				_do_play(d)
		"stop":
			_scheduled = {}
			audio.stop_music(fade)
			Events.music_cue_changed.emit("")
		"layers":
			audio.set_music_layers(d.get("layers", []), fade)


func _do_play(d: Dictionary) -> void:
	var audio := _audio()
	if audio == null:
		return
	var fade := float(d.get("fade", 2.0)) * fade_scale
	var cue := String(d.get("cue", ""))
	if not bool(audio.try_play_music(String(d.get("track", "")), fade)):
		selector.play_failed(cue)
		return
	audio.set_music_layers(d.get("layers", []), fade)
	Events.music_cue_changed.emit(cue)


# ---------------------------------------------------------------------------------------------
# Threat monitor (0.5 s)
# ---------------------------------------------------------------------------------------------

func _update_threat() -> void:
	if get_tree().paused:
		return          # a menu is open: keep the last answer (no false/true flicker around menus)
	var raw := false
	var g := _game_node()
	if g != null and _as_string(g.get("mode")) == "playing":
		var p: Variant = g.get("player")
		if is_instance_valid(p) and p is Node3D:
			raw = scan_threat(p as Node3D)
	if raw != threat:
		threat = raw
		_emitting = true
		Events.combat_state_changed.emit(raw)
		_emitting = false


## True when an enemy near Krystal is threatening her AND can see her or was engaged recently.
func scan_threat(p: Node3D) -> bool:
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return false
	var radius := float(selector.tuning.get("threat_radius", 20.0)) if selector != null else 20.0
	var engaged_ms := int(float(selector.tuning.get("engaged_s", 5.0)) * 1000.0) if selector != null else 5000
	var engaged := Time.get_ticks_msec() - _engaged_ms < engaged_ms
	var ppos := p.global_position
	var space: PhysicsDirectSpaceState3D = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var n := e as Node3D
		if not n.is_inside_tree() or n.is_in_group("stalker") or not n.has_method("is_threatening"):
			continue
		if not bool(n.call("is_threatening")):
			continue
		if n.global_position.distance_to(ppos) > radius:
			continue
		if engaged:
			return true
		if space == null:
			var w := p.get_world_3d()
			if w == null:
				return false
			space = w.direct_space_state
		if _has_line_of_sight(space, n, p):
			return true
	return false


func _has_line_of_sight(space: PhysicsDirectSpaceState3D, e: Node3D, p: Node3D) -> bool:
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3.UP * 1.0,
		p.global_position + Vector3.UP * 1.2, 1 | 32)          # world | structure
	var ex: Array[RID] = []
	if e is CollisionObject3D:
		ex.append((e as CollisionObject3D).get_rid())
	if p is CollisionObject3D:
		ex.append((p as CollisionObject3D).get_rid())
	q.exclude = ex
	return space.intersect_ray(q).is_empty()


## Damage dealt or taken (or a companion attacking) counts as engagement for a few seconds.
func note_engaged() -> void:
	_engaged_ms = Time.get_ticks_msec()


func _on_engaged() -> void:
	note_engaged()


# ---------------------------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------------------------

func _set_boss(id: String, active: bool, phase: int = -1) -> void:
	if id == "":
		return
	var b: Dictionary = _bosses.get(id, {"active": false, "phase": 1, "seq": 0})
	var was := bool(b.get("active", false))
	if active and not was:
		_boss_seq += 1
		b["seq"] = _boss_seq
	if phase > 0:
		b["phase"] = phase
	elif not active:
		b["phase"] = 1
	b["active"] = active
	_bosses[id] = b
	if active != was or phase > 0:
		tick_now()


func _on_boss_health(boss_id: String, hp: float, _max_hp: float) -> void:
	# legacy Weaver: a shown health bar (hp >= 0) is an active fight, hp < 0 hides it (over)
	var active := hp >= 0.0
	if active == bool((_bosses.get(boss_id, {}) as Dictionary).get("active", false)):
		return
	_set_boss(boss_id, active)


func _on_boss_encounter(boss_id: String, active: bool) -> void:
	_set_boss(boss_id, active)


func _on_boss_phase(boss_id: String, phase: int) -> void:
	_set_boss(boss_id, true, maxi(phase, 1))


func _on_boss_defeated(boss_id: String) -> void:
	_set_boss(boss_id, false)


func _on_horror_state(s: String) -> void:
	_horror_state = s


func _on_horror_event(event_id: String, _data: Dictionary) -> void:
	var secs := MusicData.authored_silence_seconds(event_id)
	if secs > 0.0:
		_silence_until_ms = maxi(_silence_until_ms, Time.get_ticks_msec() + int(secs * 1000.0))


func _on_cutscene_changed(_active: bool) -> void:
	tick_now()


func _on_chapter_completed() -> void:
	request("restoration")        # no-op when the restoration scene already asked for it


func _on_chapter2_completed() -> void:
	_late = true
	request("celebration")


func _on_combat_state(in_combat: bool) -> void:
	if _emitting:
		return
	external_combat = in_combat


## Area hints: a base context id (e.g. "pond"), "silence" (hold the music out) or "" (clear both).
func _on_music_context(context: String) -> void:
	if context == "silence":
		_silence_hold = true
	elif context == "":
		_silence_hold = false
		_hint = ""
	else:
		_hint = context


func _on_player_died() -> void:
	for id in _bosses:
		(_bosses[id] as Dictionary)["active"] = false
	threat = false
	external_combat = false
	if selector != null:
		selector.clear_combat()


func _on_player_respawned() -> void:
	if selector != null:
		selector.snap_base()


func _on_area_exiting(_area: String) -> void:
	_bosses.clear()
	_late = false          # from now on the save's chapter_two_complete flag decides (a New Game resets it)
	_hint = ""
	_silence_hold = false
	_silence_until_ms = 0
	_horror_state = ""
	threat = false
	external_combat = false
	_scheduled = {}
	if selector != null:
		selector.reset_area()


func _on_area_loaded(_area: String) -> void:
	tick_now()
