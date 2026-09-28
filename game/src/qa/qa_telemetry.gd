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

const Tracker := preload("res://src/ui/hud/tracker.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const PROGRESS_INTERVAL := 0.5

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


func setup(path: String, interval: float) -> void:
	_file = FileAccess.open(path, FileAccess.WRITE)
	_interval = maxf(interval, 0.03)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_t += delta
	_nearby_t += delta
	_buttons_t += delta
	if _nearby_t >= 0.4:
		_nearby_t = 0.0
		_nearby = _collect_nearby()
	if _buttons_t >= 0.2:
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
	return d


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
	if get_tree().current_scene != null:
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
