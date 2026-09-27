extends Node
## QA telemetry for automated/interactive playtesting (read-only observation, no cheats).
## Enabled only with the command-line user arg --qa-telemetry=<file> [--qa-interval=0.1].
## Writes one JSON object per line describing what a player could perceive: player/camera pose,
## on-screen prompt, objectives, open UI, visible buttons (window pixel rects), nearby objects,
## recent messages. An external bot (tools/qa/hhbot.py) reads it and drives the game with real
## OS-level keyboard/mouse input (SendInput). Nothing here changes game state.

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


func setup(path: String, interval: float) -> void:
	_file = FileAccess.open(path, FileAccess.WRITE)
	_interval = maxf(interval, 0.03)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.notify.connect(func(text: String, kind: String): _push_msg("notify", kind + ": " + text))
	Events.say.connect(func(speaker: String, text: String, _d: float): _push_msg("say", speaker + ": " + text))
	Events.hint.connect(func(id: String, text: String): _push_msg("hint", id + ": " + text))
	Events.caption.connect(func(text: String): _push_msg("caption", text))
	Events.build_mode_changed.connect(func(active: bool): _build["active"] = active)
	Events.build_selection_changed.connect(func(item_id: String): _build["item"] = item_id)
	Events.build_placement_state.connect(func(valid: bool, reason: String):
		_build["valid"] = valid
		_build["reason"] = reason)


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
	d["hotbar_index"] = GameState.hotbar_index
	d["hotbar"] = []
	for i in GameState.HOTBAR_SIZE:
		var s = GameState.inventory.get_slot(i)
		d["hotbar"].append(null if s == null else s["id"])
	d["flags"] = GameState.flags.keys()
	d["messages"] = _messages.duplicate()
	d["build"] = _build.duplicate()
	d["nearby"] = _nearby
	d["buttons"] = _buttons
	var win := DisplayServer.window_get_size()
	d["window"] = [win.x, win.y]
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
	return d


## Nearby objects of gameplay interest within 80 m, closest first (max 60 entries).
func _collect_nearby() -> Array:
	var out := []
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return out
	var origin: Vector3 = p.global_position
	var seen := {}
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
			out.append(e)
	out.sort_custom(func(a, b): return a["dist"] < b["dist"])
	if out.size() > 60:
		out.resize(60)
	return out


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
	if out.size() > 120:
		return
	if n is BaseButton:
		var b: BaseButton = n
		if b.is_visible_in_tree():
			var r := b.get_global_rect()
			var tl: Vector2 = xf * r.position
			var br: Vector2 = xf * (r.position + r.size)
			var text := ""
			if b is Button:
				text = (b as Button).text
			if text == "" and b.tooltip_text != "":
				text = b.tooltip_text
			if text == "":
				text = String(b.name)
			out.append({"text": text, "rect": [int(tl.x), int(tl.y), int(br.x - tl.x), int(br.y - tl.y)], "disabled": b.disabled})
	for c in n.get_children():
		_collect_buttons_rec(c, xf, out)
