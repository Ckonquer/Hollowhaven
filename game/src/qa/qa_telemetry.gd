extends Node
## QA telemetry for automated/interactive playtesting (read-only observation, no cheats).
## Enabled only with the command-line user arg --qa-telemetry=<file> [--qa-interval=0.1].
## Writes one JSON object per line describing what a player could perceive: player/camera pose,
## on-screen prompt, objectives, open UI, visible buttons (window pixel rects), nearby objects,
## recent messages. An external bot (tools/qa/hhbot.py) reads it and drives the game with real
## OS-level keyboard/mouse input (SendInput). Nothing here changes game state.
## Chapter Two additions (read-only, refreshed every PROGRESS_INTERVAL s, see progress_snapshot()): "area_info"
## (area, zone, safe, map kind, discovered landmarks), "chapter2" (availability, current step ids, done ids),
## "tracker" (what the HUD tracker shows), "optional" (done / pending goal ids), "equipment", "companion_skills"
## (signature cooldowns from the saved skill_ready_at timeline) and "music" (current cue); plus messages for
## chapter-two steps, optional goals, discoveries, music cues, companion skills and equipment changes.
## Second-monitor QA additions: "window_pos", "window_focused", "mouse_mode" and "qa_input" (the virtual input
## server's status when --qa-input-port is given; the bot then drives the game through src/qa/qa_input.gd
## instead of SendInput).
## Headless QA additions (tools/qa --headless: the root window is 64x64 px, so the 1920x1080 UI is drawn at 1/30
## scale and integer rects lose the sub-pixel position a click needs): every button also carries "rf" (the same
## rect in window pixels as floats), "view" is the UI's size in window pixels, "appearance" is the current look
## (progress snapshot), "buffs" the timed buffs (e.g. a boss slow) and nearby enemies may carry "phase" (bosses),
## "kind" (boss hazards: trip / thread / sac) and "vuln" (is_vulnerable()); "boss" is the nearest visible boss
## (id, name, pos, state, hp, max_hp, phase, vuln, threat, dist) read fresh for every line, and player "facing_yaw"
## is Krystal's body facing (cam_yaw convention). All read-only.
## Performance QA additions (tools/qa/perf_profile.py, MP §20.5; read-only - Performance monitors and clocks only):
## every line carries "perf" (see _perf_block()): tick_ms (Time.get_ticks_msec), area / zone / mode, fps, process_ms /
## physics_ms (Performance TIME_*), static_mb / static_max_mb (0 in release builds: the engine tracks it in debug builds
## only), video_mb / texture_mb / buffer_mb, draw_calls / objects_drawn / primitives, objects / resources / nodes /
## orphans, phys_active / phys_pairs and "load" (the last area load: Game.mode "loading" -> "playing" in ms, its worst
## frame and frames over 50 ms, then the worst frame in the first POST_LOAD_S s of play). The user arg --qa-perf adds
## per-frame data since the previous line: "frames" (frame-to-frame interval, ms), "self_ms" (this node's own cost in
## the frame that started each interval, so a profile can tell telemetry overhead from game stalls), "gpu_ms" /
## "cpu_render_ms" (the main viewport's measured render times), plus "audio" (AudioStreamPlayer* nodes in the tree /
## playing), "enemies" (group "enemy": total / alive / still processing, processing far away or off-screen) and "env"
## (adapter, CPU, window, refresh rate, render scale, quality, vsync). With --qa-perf the button scan skips the 3D world
## while playing (it has no buttons; the UI root is still scanned) and the nearby / button scans run less often, so the
## telemetry itself does not add a periodic stall to the frames it measures.

const Tracker := preload("res://src/ui/hud/tracker.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const PROGRESS_INTERVAL := 0.5
const POST_LOAD_S := 3.0            # "load".post_worst_ms: worst frame this long after a load ends
const LONG_FRAME_MS := 50.0         # "load".long_frames / post_long_frames threshold
const FAR_AI_M := 60.0              # "enemies".active_far: still processing this far from Krystal
const PERF_MAX_FRAMES := 4000       # per-frame lists are capped if no line is written for a long time
const PERF_NEARBY_INTERVAL := 1.0   # --qa-perf cadences (defaults 0.4 / 0.2 s)
const PERF_BUTTONS_INTERVAL := 0.5

var _file: FileAccess
var _interval := 0.1
var _t := 0.0
var _nearby_t := 0.0
var _nearby: Array = []
var _buttons_t := 0.0
var _buttons: Array = []
var _messages: Array = []
var _build := {"active": false, "item": "", "valid": false, "reason": ""}
var _seq := 0
var _progress_t := PROGRESS_INTERVAL
var _progress: Dictionary = {}
var _music_cue := ""
var _boss: WeakRef = null          # nearest boss node (has "boss_id") seen by _collect_nearby; read every snapshot
# Performance QA ("perf", see the header). Measurement only: nothing here changes game state.
var _perf_mode := false            # --qa-perf
var _last_frame_us := 0
var _prev_self_ms := 0.0
var _pf_frames: Array = []
var _pf_self: Array = []
var _pf_gpu: Array = []
var _pf_cpu: Array = []
var _vp_rid := RID()
var _prev_mode := ""
var _load: Dictionary = {}
var _load_n := 0
var _load_from := ""
var _load_start_us := 0
var _load_worst := 0.0
var _load_long := 0
var _load_frames := 0
var _post_until_us := 0
var _audio: Dictionary = {}        # instance id -> true: AudioStreamPlayer / 2D / 3D nodes in the tree (--qa-perf)


func setup(path: String, interval: float) -> void:
	_file = FileAccess.open(path, FileAccess.WRITE)
	_interval = maxf(interval, 0.03)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_perf_mode = Debug.has_arg("qa-perf")
	if _perf_mode:
		_perf_setup()
	Events.notify.connect(func(text: String, kind: String): _push_msg("notify", kind + ": " + text))
	Events.say.connect(func(speaker: String, text: String, _d: float): _push_msg("say", speaker + ": " + text))
	Events.hint.connect(func(id: String, text: String): _push_msg("hint", id + ": " + text))
	Events.caption.connect(func(text: String): _push_msg("caption", text))
	Events.game_saved.connect(func(ok: bool): _push_msg("saved", "journey saved" if ok else "save FAILED"))
	Events.player_died.connect(func(): _push_msg("event", "player died"))
	Events.quest_step_completed.connect(func(id: String): _push_msg("quest", "completed " + id))
	Events.build_mode_changed.connect(func(active: bool): _build["active"] = active)
	Events.build_selection_changed.connect(func(item_id: String): _build["item"] = item_id)
	Events.build_placement_state.connect(func(valid: bool, reason: String):
		_build["valid"] = valid
		_build["reason"] = reason)
	Events.chapter2_step_started.connect(func(id: String): _push_msg("quest", "ch2 started " + id))
	Events.chapter2_step_completed.connect(func(id: String): _push_msg("quest", "ch2 completed " + id))
	Events.optional_goal_completed.connect(func(id: String): _push_msg("quest", "optional completed " + id))
	Events.landmark_discovered.connect(func(area: String, id: String): _push_msg("discover", area + ":" + id))
	Events.music_cue_changed.connect(func(cue: String):
		_music_cue = cue
		_push_msg("music", cue))
	Events.companion_skill_used.connect(func(cid: String, skill: String): _push_msg("skill", cid + ": " + skill))
	Events.equipment_changed.connect(func(slot: String, item: String): _push_msg("equip", slot + "=" + item))


func _push_msg(kind: String, text: String) -> void:
	_messages.append({"k": kind, "text": text, "t": snappedf(Debug._t, 0.01)})
	if _messages.size() > 12:
		_messages.pop_front()


func _process(delta: float) -> void:
	if _file == null:
		return
	var t0 := Time.get_ticks_usec()
	_perf_frame(t0)
	_tick(delta)
	_prev_self_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _tick(delta: float) -> void:
	_t += delta
	_nearby_t += delta
	_buttons_t += delta
	if _nearby_t >= (PERF_NEARBY_INTERVAL if _perf_mode else 0.4):
		_nearby_t = 0.0
		_nearby = _collect_nearby()
	if _buttons_t >= (PERF_BUTTONS_INTERVAL if _perf_mode else 0.2):
		_buttons_t = 0.0
		_buttons = _collect_buttons()
	_progress_t += delta
	if _progress_t >= PROGRESS_INTERVAL:
		_progress_t = 0.0
		_progress = progress_snapshot()
	if _t < _interval:
		return
	_t = 0.0
	_seq += 1
	_file.store_line(JSON.stringify(_snapshot()))
	_file.flush()


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _snapshot() -> Dictionary:
	var d := Debug.state_snapshot()
	d["seq"] = _seq
	d["ui_stack"] = Game._ui_stack.duplicate()
	d["objectives"] = GameState.quests.objective_status() if GameState.active else []
	# Combined tracker objective (legacy chain or the Chapter Two layer, docs/CHAPTER_TWO_SPEC.md §8).
	if GameState.active:
		var obj: Dictionary = GameState.current_objective()
		d["objective"] = {"source": obj["source"], "chapter": obj["chapter"], "id": obj["id"], "title": obj["title"],
			"status": obj["status"]}
	d["hotbar_index"] = GameState.hotbar_index
	d["hotbar"] = []
	for i in GameState.HOTBAR_SIZE:
		var s = GameState.inventory.get_slot(i)
		d["hotbar"].append(null if s == null else s["id"])
	d["flags"] = GameState.flags.keys()
	d["messages"] = _messages.duplicate()
	d["build"] = _build.duplicate()
	d["nearby"] = _nearby
	var be := _boss_entry()
	if not be.is_empty():
		d["boss"] = be
	d["buttons"] = _buttons
	var win := DisplayServer.window_get_size()
	d["window"] = [win.x, win.y]
	var vp := get_viewport()
	var view: Vector2 = vp.get_final_transform().basis_xform(vp.get_visible_rect().size)
	d["view"] = [snappedf(view.x, 0.01), snappedf(view.y, 0.01)]
	# Second-monitor QA mode: where the window is, whether it ever had focus, the OS cursor mode and the virtual
	# input server's state (src/qa/qa_input.gd; the QA bot checks the owner's focus was never taken).
	var wpos := DisplayServer.window_get_position()
	d["window_pos"] = [wpos.x, wpos.y]
	d["window_focused"] = DisplayServer.window_is_focused()
	d["mouse_mode"] = int(Input.mouse_mode)
	if Debug.qa_input != null and is_instance_valid(Debug.qa_input) and Debug.qa_input.has_method("status"):
		d["qa_input"] = Debug.qa_input.call("status")
	var p = Game.player
	if p != null and is_instance_valid(p):
		var pd := {"pos": _v(p.global_position), "vel": _v(p.velocity) if "velocity" in p else [0, 0, 0],
			"on_floor": p.is_on_floor() if p.has_method("is_on_floor") else true,
			"stamina": snappedf(float(p.get("stamina")) if p.get("stamina") != null else 0.0, 0.1),
			"lantern": bool(p.get("lantern_on")) if p.get("lantern_on") != null else false}
		var cam: Camera3D = p.get_camera() if p.has_method("get_camera") else get_viewport().get_camera_3d()
		if cam != null:
			var fwd := -cam.global_transform.basis.z
			pd["cam_pos"] = _v(cam.global_position)
			pd["cam_yaw"] = snappedf(rad_to_deg(atan2(-fwd.x, -fwd.z)), 0.1)
			pd["cam_pitch"] = snappedf(rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))), 0.1)
		if p.has_method("get_prompt"):
			pd["prompt"] = p.get_prompt()
		if p.has_method("get_facing"):
			# Krystal's body facing (same yaw convention as cam_yaw): melee swings go this way unless the soft lock turns her.
			var fdir: Vector3 = p.get_facing()
			pd["facing_yaw"] = snappedf(rad_to_deg(atan2(-fdir.x, -fdir.z)), 0.1)
		if p.has_method("get_focus_target"):
			var f = p.get_focus_target()
			if f != null and is_instance_valid(f) and f is Node3D:
				pd["focus"] = {"name": String(f.name), "pos": _v(f.global_position)}
		if p.get("health") != null:
			pd["hp"] = snappedf(float(p.health.hp), 0.1)
		d["player"] = pd
	var comps := {}
	for id in Game.companion_nodes:
		var c = Game.companion_nodes[id]
		if is_instance_valid(c):
			comps[id] = {"pos": _v(c.global_position), "assignment": GameState.companion(id)["assignment"],
				"befriended": GameState.is_befriended(id), "bond": GameState.bond_level(id)}
	d["companion_nodes"] = comps
	for k in _progress:
		d[k] = _progress[k]
	d["perf"] = _perf_block()
	return d


# --- Performance QA (read-only; see the header) -----------------------------------------------------------------

## --qa-perf only: track audio players entering / leaving the tree and turn on the main viewport's render-time
## measurement (a measurement switch, nothing rendered changes).
func _perf_setup() -> void:
	get_tree().node_added.connect(_on_perf_node_added)
	get_tree().node_removed.connect(_on_perf_node_removed)
	for type in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for n in get_tree().root.find_children("*", type, true, false):
			_audio[n.get_instance_id()] = true
	var vp := get_viewport()
	if vp != null and DisplayServer.get_name() != "headless":
		_vp_rid = vp.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _on_perf_node_added(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
		_audio[n.get_instance_id()] = true


func _on_perf_node_removed(n: Node) -> void:
	_audio.erase(n.get_instance_id())


## Called once per frame before anything else here: the frame-to-frame interval, the area-load timer (Game.mode
## "loading" -> anything else) and, with --qa-perf, the per-frame lists.
func _perf_frame(now_us: int) -> void:
	var dt_ms := 0.0
	if _last_frame_us > 0:
		dt_ms = float(now_us - _last_frame_us) / 1000.0
	_last_frame_us = now_us
	var m := String(Game.mode)
	if m == "loading" and _prev_mode != "loading":
		_load_start_us = now_us
		_load_from = String(Game.area_id)
		_load_worst = dt_ms          # this interval holds the frame that started the load (save parse, prefetch)
		_load_long = 1 if dt_ms > LONG_FRAME_MS else 0
		_load_frames = 1
		_post_until_us = 0
	elif m == "loading":
		_load_frames += 1
		_load_worst = maxf(_load_worst, dt_ms)
		if dt_ms > LONG_FRAME_MS:
			_load_long += 1
	elif _prev_mode == "loading":
		_load_n += 1
		_load = {"n": _load_n, "from": _load_from, "area": String(Game.area_id),
			"ms": snappedf(float(now_us - _load_start_us) / 1000.0, 0.1),
			"worst_frame_ms": snappedf(maxf(_load_worst, dt_ms), 0.01), "long_frames": _load_long + (1 if dt_ms > LONG_FRAME_MS else 0),
			"frames": _load_frames + 1, "post_worst_ms": 0.0, "post_long_frames": 0, "post_done": false}
		_post_until_us = now_us + int(POST_LOAD_S * 1000000.0)
	elif _post_until_us > 0:
		if now_us <= _post_until_us:
			_load["post_worst_ms"] = snappedf(maxf(float(_load["post_worst_ms"]), dt_ms), 0.01)
			if dt_ms > LONG_FRAME_MS:
				_load["post_long_frames"] = int(_load["post_long_frames"]) + 1
		else:
			_load["post_done"] = true
			_post_until_us = 0
	_prev_mode = m
	if not _perf_mode or dt_ms <= 0.0:
		return
	if _pf_frames.size() >= PERF_MAX_FRAMES:
		_pf_frames.clear()
		_pf_self.clear()
		_pf_gpu.clear()
		_pf_cpu.clear()
	_pf_frames.append(snappedf(dt_ms, 0.001))
	_pf_self.append(snappedf(_prev_self_ms, 0.001))
	if _vp_rid.is_valid():
		_pf_gpu.append(snappedf(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid), 0.001))
		_pf_cpu.append(snappedf(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid), 0.001))


static func _mb(bytes: float) -> float:
	return snappedf(bytes / 1048576.0, 0.1)


## The "perf" entry of a line (cheap monitors always; per-frame lists, audio, enemies and env with --qa-perf).
func _perf_block() -> Dictionary:
	var d := {"tick_ms": Time.get_ticks_msec(), "area": String(Game.area_id), "zone": String(Game.zone_id),
		"mode": String(Game.mode), "fps": Engine.get_frames_per_second(),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"static_mb": _mb(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_max_mb": _mb(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"video_mb": _mb(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_mb": _mb(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_mb": _mb(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"phys_active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"phys_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"load": _load.duplicate()}
	if not _perf_mode:
		return d
	d["frames"] = _pf_frames
	d["self_ms"] = _pf_self
	d["gpu_ms"] = _pf_gpu
	d["cpu_render_ms"] = _pf_cpu
	_pf_frames = []
	_pf_self = []
	_pf_gpu = []
	_pf_cpu = []
	d["audio"] = _audio_counts()
	d["enemies"] = _enemy_activity()
	d["env"] = _perf_env()
	return d


func _audio_counts() -> Dictionary:
	var total := 0
	var playing := 0
	var p3d := 0
	var stale: Array = []
	for id in _audio:
		var o: Object = instance_from_id(int(id))
		if o == null or not is_instance_valid(o) or not (o is Node):
			stale.append(id)
			continue
		total += 1
		if o is AudioStreamPlayer3D:
			p3d += 1
		if bool(o.get("playing")):
			playing += 1
	for id in stale:
		_audio.erase(id)
	return {"players": total, "playing": playing, "players_3d": p3d}


## Enemies (group "enemy") and whether they still run their AI: "active" = can_process() and processing,
## "active_far" beyond FAR_AI_M from Krystal, "active_offscreen" outside the current camera's frustum.
func _enemy_activity() -> Dictionary:
	var p = Game.player
	var has_p: bool = p != null and is_instance_valid(p) and p is Node3D
	var cam := get_viewport().get_camera_3d()
	var total := 0
	var alive := 0
	var active := 0
	var far := 0
	var off := 0
	var maxd := 0.0
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		total += 1
		if n.has_method("is_dead") and bool(n.call("is_dead")):
			continue
		alive += 1
		if not (n.can_process() and (n.is_physics_processing() or n.is_processing())):
			continue
		active += 1
		var pos: Vector3 = (n as Node3D).global_position
		var dist: float = pos.distance_to((p as Node3D).global_position) if has_p else 0.0
		maxd = maxf(maxd, dist)
		if dist > FAR_AI_M:
			far += 1
		if cam != null and not cam.is_position_in_frustum(pos):
			off += 1
	return {"total": total, "alive": alive, "active": active, "active_far": far, "active_offscreen": off,
		"active_max_dist": snappedf(maxd, 0.1)}


func _perf_env() -> Dictionary:
	var vp := get_viewport()
	var scr := DisplayServer.window_get_current_screen()
	var e := {"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(), "cpu": OS.get_processor_name(),
		"threads": OS.get_processor_count(), "debug_build": OS.is_debug_build(),
		"engine": String(Engine.get_version_info().get("string", "")),
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "screen": scr,
		"refresh_hz": snappedf(DisplayServer.screen_get_refresh_rate(scr), 0.01),
		"render_scale": snappedf(vp.scaling_3d_scale, 0.01) if vp != null else 1.0,
		"quality": Settings.get_value("quality"), "vsync_mode": int(DisplayServer.window_get_vsync_mode()),
		"max_fps": Engine.max_fps,
		"method": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))}
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		e["driver"] = String(RenderingServer.call("get_current_rendering_driver_name"))
	if RenderingServer.has_method("get_current_rendering_method"):
		e["method"] = String(RenderingServer.call("get_current_rendering_method"))
	return e


## Chapter Two / progression state as the QA bot sees it (read-only; allocates, so _process refreshes it only
## every PROGRESS_INTERVAL seconds). Keys: area_info, chapter2, tracker, optional, equipment,
## companion_skills, music.
func progress_snapshot() -> Dictionary:
	var out := {}
	out["area_info"] = {"area": Game.area_id, "zone": Game.zone_id, "safe": Game.in_safe_zone,
		"map": MapView.map_kind(Game.area_id), "discovered": GameState.discovered_in(Game.area_id)}
	var log: RefCounted = GameState.chapter2
	var cur: Array = []
	for s in log.current_steps():
		cur.append(String(s["id"]))
	out["chapter2"] = {"available": log.is_available(), "active": log.is_active(), "finished": log.is_finished(),
		"chapter": GameState.chapter(), "current": cur, "title": log.display_title() if not cur.is_empty() else "",
		"done": (log.done as Array).duplicate()}
	var vw := Tracker.objective_view()
	var targets: Array = []
	for t in Tracker.pending_targets(vw):
		targets.append({"id": String(t["id"]), "area": String(t["area"])})
	out["tracker"] = {"kind": String(vw["kind"]), "title": String(vw["title"]), "step": String(vw["step_id"]),
		"targets": targets}
	var og: RefCounted = GameState.optional_goals
	var done: Array = []
	var pending: Array = []
	for g in og.visible_goals():
		var gid := String(g["id"])
		if og.is_done(gid):
			done.append(gid)
		else:
			pending.append(gid)
	out["optional"] = {"done": done, "pending": pending, "done_count": og.done_count()}
	out["equipment"] = GameState.equipment.duplicate()
	out["appearance"] = GameState.appearance.duplicate(true)
	var buffs := {}
	for bk in GameState.buffs:
		var bv: Variant = GameState.buffs[bk]
		if bv is Dictionary:
			buffs[String(bk)] = {"mult": snappedf(float((bv as Dictionary).get("mult", 1.0)), 0.01),
				"left": snappedf(float((bv as Dictionary).get("remaining", 0.0)), 0.1)}
	out["buffs"] = buffs
	out["companion_skills"] = companion_skill_info()
	if _music_cue == "":
		var dir: Node = Audio.music_director() if Audio.has_method("music_director") else null
		if dir != null and dir.has_method("current_cue"):
			_music_cue = String(dir.call("current_cue"))
	out["music"] = {"cue": _music_cue, "director": Audio.music_director_active() if Audio.has_method("music_director_active") else false}
	return out


## Signature-skill cooldown of every befriended companion from the saved timeline (skill_ready_at vs
## stats.play_seconds): {id: {skill, cooldown, ready_at, left, ready, active, mode[, node]}}. "node" is the
## companion node's own get_skill_state() when it provides one.
static func companion_skill_info() -> Dictionary:
	var out := {}
	var now_v: Variant = GameState.stats.get("play_seconds", 0.0)
	var now: float = float(now_v) if (now_v is float or now_v is int) else 0.0
	for id in GameState.companions:
		var rec: Variant = GameState.companions[id]
		if not (rec is Dictionary) or not bool((rec as Dictionary).get("befriended", false)):
			continue
		var ra: Variant = (rec as Dictionary).get("skill_ready_at", 0.0)
		var ready_at: float = float(ra) if (ra is float or ra is int) else 0.0
		var sig: Dictionary = ItemDB.companion_skill(String(id)).get("signature", {})
		var e := {"skill": String(sig.get("id", "")), "cooldown": float(sig.get("cooldown", 0.0)),
			"ready_at": snappedf(ready_at, 0.1), "left": snappedf(maxf(ready_at - now, 0.0), 0.1), "ready": ready_at <= now,
			"active": GameState.active_companion == String(id), "mode": String((rec as Dictionary).get("combat_mode", "assist"))}
		var node: Variant = Game.companion_nodes.get(id)
		if node is Node and is_instance_valid(node) and (node as Node).has_method("get_skill_state"):
			var st: Variant = (node as Node).call("get_skill_state")
			if st is Dictionary:
				e["node"] = st
		out[String(id)] = e
	return out


## Nearby objects of gameplay interest within 80 m, closest first (max 60 entries).
func _collect_nearby() -> Array:
	var out := []
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return out
	var origin: Vector3 = p.global_position
	var seen := {}
	var boss_node: Node = null
	var boss_d := INF
	for g in ["harvestable", "interactable", "enemy", "companion", "checkpoint", "crafting_station"]:
		for n in get_tree().get_nodes_in_group(g):
			if not (n is Node3D) or not is_instance_valid(n) or seen.has(n.get_instance_id()):
				continue
			if not n.is_visible_in_tree():
				continue
			var dist: float = n.global_position.distance_to(origin)
			if dist > 80.0:
				continue
			seen[n.get_instance_id()] = true
			var e := {"g": g, "name": String(n.name), "pos": _v(n.global_position), "dist": snappedf(dist, 0.1)}
			if n.has_method("get_harvest_info"):
				var hi: Dictionary = n.get_harvest_info()
				e["tool"] = hi.get("tool", "")
				e["label"] = hi.get("name", "")
			if n.has_method("get_interaction"):
				var ii: Dictionary = n.get_interaction(p)
				e["text"] = ii.get("text", "")
				e["enabled"] = ii.get("enabled", true)
			if n.get("node_id") != null:
				e["id"] = String(n.get("node_id"))
			if g == "enemy" and n.has_method("is_threatening"):
				e["threat"] = n.is_threatening()
			if g == "enemy":
				var st = n.get("state")
				if st != null:
					e["state"] = str(st)
				var h = n.get("health")
				if h != null and is_instance_valid(h):
					e["hp"] = snappedf(float(h.hp), 0.1)
				var ph = n.get("phase")
				if ph is int:
					e["phase"] = ph
				var kd = n.get("kind")
				if kd is String or kd is StringName:
					e["kind"] = String(kd)
				if n.has_method("is_vulnerable"):
					e["vuln"] = bool(n.call("is_vulnerable"))
				if n.get("boss_id") != null and (boss_node == null or dist < boss_d):
					boss_node = n
					boss_d = dist
			out.append(e)
	_boss = weakref(boss_node) if boss_node != null else null
	out.sort_custom(func(a, b): return a["dist"] < b["dist"])
	if out.size() > 60:
		out.resize(60)
	return out


## The nearest visible boss (found by _collect_nearby every 0.4 s) read fresh for every snapshot: bosses act on
## ~1 s telegraphs, so the bot needs their state at the snapshot rate, not the nearby-list rate. {} when none.
func _boss_entry() -> Dictionary:
	var bn: Variant = _boss.get_ref() if _boss != null else null
	if bn == null or not is_instance_valid(bn) or not (bn is Node3D) or not (bn as Node3D).is_inside_tree():
		return {}
	var n := bn as Node3D
	if not n.is_visible_in_tree():
		return {}
	var e := {"id": str(n.get("boss_id")), "name": String(n.name), "pos": _v(n.global_position), "state": str(n.get("state"))}
	var p = Game.player
	if p != null and is_instance_valid(p):
		e["dist"] = snappedf(n.global_position.distance_to(p.global_position), 0.1)
	var h = n.get("health")
	if h != null and is_instance_valid(h):
		e["hp"] = snappedf(float(h.hp), 0.1)
		e["max_hp"] = snappedf(float(h.max_hp), 0.1)
	var ph = n.get("phase")
	if ph is int:
		e["phase"] = ph
	if n.has_method("is_vulnerable"):
		e["vuln"] = bool(n.call("is_vulnerable"))
	if n.has_method("is_threatening"):
		e["threat"] = bool(n.call("is_threatening"))
	return e


## Visible, clickable buttons with rects in WINDOW pixel coordinates.
func _collect_buttons() -> Array:
	var out := []
	var xf := get_viewport().get_final_transform()
	var roots: Array = []
	if Game.ui != null and is_instance_valid(Game.ui):
		roots.append(Game.ui)
	# --qa-perf: the 3D world has no buttons; walking its whole tree every scan would be a periodic stall of our own.
	var skip_world: bool = _perf_mode and (Game.mode == "playing" or Game.mode == "loading")
	if get_tree().current_scene != null and not skip_world:
		roots.append(get_tree().current_scene)
	for r in roots:
		_collect_buttons_rec(r, xf, out)
	return out


func _collect_buttons_rec(n: Node, xf: Transform2D, out: Array) -> void:
	if out.size() > 160:
		return
	if n is Control and n.get("index") != null and n.get("hud_style") != null and "stack" in n:
		# Inventory slot widget (src/ui/widgets/item_slot.gd): expose for drag/double-click tests.
		var sc: Control = n
		if sc.is_visible_in_tree() and not bool(sc.get("hud_style")):
			var r0 := sc.get_global_rect()
			var a: Vector2 = xf * r0.position
			var b2: Vector2 = xf * (r0.position + r0.size)
			var st = sc.get("stack")
			var owner_inv = sc.get("inv")
			out.append({"text": "slot:%s:%d" % ["bag" if owner_inv == GameState.inventory else "other", int(sc.get("index"))],
				"item": String(st["id"]) if st is Dictionary else "", "count": int(st["count"]) if st is Dictionary else 0,
				"rect": [int(a.x), int(a.y), int(b2.x - a.x), int(b2.y - a.y)], "rf": _rf(a, b2), "disabled": false,
				"clipped": _is_clipped(sc, r0)})
	if n is BaseButton:
		var b: BaseButton = n
		if b.is_visible_in_tree():
			var r := b.get_global_rect()
			var tl: Vector2 = xf * r.position
			var br: Vector2 = xf * (r.position + r.size)
			var text := ""
			if b is Button:
				text = (b as Button).text
			if text == "":
				text = _child_label_text(b)
			if text == "" and b.tooltip_text != "":
				text = b.tooltip_text
			if text == "":
				text = String(b.name)
			out.append({"text": text, "rect": [int(tl.x), int(tl.y), int(br.x - tl.x), int(br.y - tl.y)], "rf": _rf(tl, br),
				"disabled": b.disabled, "clipped": _is_clipped(b, r)})
	for c in n.get_children():
		_collect_buttons_rec(c, xf, out)


## A window-pixel rect as floats [x, y, w, h] (headless runs draw the UI at 1/30 scale).
static func _rf(tl: Vector2, br: Vector2) -> Array:
	return [snappedf(tl.x, 0.001), snappedf(tl.y, 0.001), snappedf(br.x - tl.x, 0.001), snappedf(br.y - tl.y, 0.001)]


## Concatenated text of Labels inside a text-less button (e.g. recipe rows).
func _child_label_text(n: Node) -> String:
	var parts: PackedStringArray = []
	for c in n.get_children():
		if c is Label and (c as Label).text.strip_edges() != "":
			parts.append((c as Label).text.strip_edges())
		elif c is RichTextLabel and (c as RichTextLabel).get_parsed_text().strip_edges() != "":
			parts.append((c as RichTextLabel).get_parsed_text().strip_edges())
		elif c.get_child_count() > 0:
			var sub := _child_label_text(c)
			if sub != "":
				parts.append(sub)
		if parts.size() >= 3:
			break
	return " | ".join(parts)


## True if the button is (partly) scrolled out of an ancestor that clips its contents.
func _is_clipped(b: Control, r: Rect2) -> bool:
	var p := b.get_parent()
	while p != null:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			var pr := (p as Control).get_global_rect()
			if not pr.encloses(r.grow(-2.0)):
				return true
		p = p.get_parent()
	return false
