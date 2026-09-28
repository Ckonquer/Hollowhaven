extends RefCounted
## Home life at the Haven for ONE companion (owned by companion.gd as `home_life`; MP §6.5). Small, bounded,
## saved: every behaviour counts in a daily ledger in the companion record ("home_log": {"day", <task>: n})
## with a per-day cap, nothing ever creates items, and the current task id is kept in "home_task" (spec §3).
##   napper (Mochi): an occasional nap near its home spot (crop tending stays in companion.gd).
##   cairn  (Pebble): fetches a small stone and adds it to its cairn beside its home spot (a visual stack of
##                   at most CAIRN_MAX stones, record key "cairn"; no inventory items).
##   perch  (Lumi):  settles on its perch now and then; at night it visits the nearest Haven lamp once and
##                   pulses with it before sleeping.
##   Everyone notices a newly placed furnishing near home with a restrained line (a few per day).

const Logic := preload("res://src/companions/companion_logic.gd")
const Fx := preload("res://src/companions/companion_fx.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")

const DAILY := {"nap": 2, "cairn": 3, "perch": 3, "lights": 1, "notice": 3}
const CAIRN_MAX := 7
const NOTICE_RADIUS := 18.0
const LAMP_RADIUS := 14.0
const STONE_COLOR := Color("a79f93")
const NIGHT_CHECK := 4.0

var c: Node3D
var id: String = ""
var kind: String = ""
var nap_left: float = 0.0
var carrying: bool = false
var _place_tries: int = 0
var _t: float = 45.0
var _night_t: float = 0.0
var _notice_queue: Array = []        # structure uids placed near home, noticed one at a time
var _cairn: Node3D = null
var _carry_mesh: Node3D = null
var _rng := RandomNumberGenerator.new()


func _init(companion: Node3D, companion_id: String) -> void:
	c = companion
	id = companion_id
	kind = String(ItemDB.creature(id).get("home_life", ""))
	_rng.randomize()
	_t = _rng.randf_range(35.0, 60.0)


## The record's daily ledger (reset on a new in-game day).
static func ledger(rec: Dictionary, day: int) -> Dictionary:
	var l: Variant = rec.get("home_log")
	if not (l is Dictionary) or int((l as Dictionary).get("day", -1)) != day:
		l = {"day": day}
		rec["home_log"] = l
	return l


## One more of `task` today? (records it when allowed)
static func take(rec: Dictionary, day: int, task: String) -> bool:
	var l := ledger(rec, day)
	if int(l.get(task, 0)) >= int(DAILY.get(task, 0)):
		return false
	l[task] = int(l.get(task, 0)) + 1
	return true


static func can_take(rec: Dictionary, day: int, task: String) -> bool:
	var l: Variant = rec.get("home_log")
	var used := 0
	if l is Dictionary and int((l as Dictionary).get("day", -1)) == day:
		used = int((l as Dictionary).get(task, 0))
	return used < int(DAILY.get(task, 0))


func _rec() -> Dictionary:
	return GameState.companion(id)


func _home() -> Vector3:
	return c.get("home_pos")


func cairn_pos() -> Vector3:
	return _home() + Vector3(1.1, 0.0, -0.7)


## Called from companion._state_home by day when nothing else is going on. Returns true when it took over
## this frame (the companion should not start its other home abilities).
func tick_day(delta: float, d_player: float) -> bool:
	if nap_left > 0.0:
		nap_left -= delta
		if nap_left <= 0.0:
			_end_nap()
		return true
	if carrying:
		_place_tries += 1
		if _place_tries > 2:
			# Couldn't reach the cairn twice: set the stone down here (nothing is lost, nothing is made).
			carrying = false
			_show_carry(false)
			_rec()["home_task"] = ""
			return false
		c.call("_start_work", {"kind": "cairn_place", "anim": "stomp", "pos": cairn_pos(), "reach": 0.7, "speed": 0.7})
		return true
	if not _notice_queue.is_empty():
		var uid := String(_notice_queue.pop_front())
		var s: Variant = GameState.structures.get(uid)
		if s is Dictionary:
			var pv: Variant = Logic.vec_from((s as Dictionary).get("pos"))
			if pv is Vector3 and take(_rec(), GameState.day(), "notice"):
				c.call("_start_work", {"kind": "notice", "anim": "sniff", "pos": pv, "reach": 1.4, "speed": 0.8, "uid": uid})
				return true
	_t -= delta
	if _t > 0.0:
		return false
	_t = _rng.randf_range(40.0, 75.0)
	var day := GameState.day()
	match kind:
		"napper":
			if _rng.randf() < 0.45 and take(_rec(), day, "nap"):
				_start_nap()
				return true
		"cairn":
			if take(_rec(), day, "cairn"):
				var a := _rng.randf_range(0.0, TAU)
				var p := _home() + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(2.5, 4.5)
				c.call("_start_work", {"kind": "cairn_fetch", "anim": "sniff", "pos": p, "reach": 0.6, "speed": 0.8})
				return true
		"perch":
			if take(_rec(), day, "perch"):
				c.call("_start_work", {"kind": "perch", "anim": "glow_pulse", "pos": _home(), "reach": 0.5, "speed": 0.7})
				if d_player < 10.0:
					c.call("_say", "perch", 3.0, false)
				return true
	return false


## At night, before sleeping: Lumi visits the nearest Haven lamp once. Returns true while busy with it.
## Looks for a lamp at most every NIGHT_CHECK seconds (no group scan per frame).
func tick_night(delta: float) -> bool:
	if kind != "perch" or not can_take(_rec(), GameState.day(), "lights"):
		return false
	_night_t -= delta
	if _night_t > 0.0:
		return false
	_night_t = NIGHT_CHECK
	var lamp := _nearest_lamp()
	if lamp == null:
		return false
	take(_rec(), GameState.day(), "lights")
	c.call("_start_work", {"kind": "lights", "anim": "glow_pulse", "pos": lamp.global_position, "reach": 1.3, "speed": 0.7})
	return true


func _nearest_lamp() -> Node3D:
	if not c.is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := LAMP_RADIUS
	for n in c.get_tree().get_nodes_in_group("light_source"):
		if n == c or not (n is Node3D) or not (n as Node).is_in_group("structure"):
			continue
		var d := (n as Node3D).global_position.distance_to(_home())
		if d < best_d:
			best_d = d
			best = n
	return best


func _start_nap() -> void:
	nap_left = _rng.randf_range(20.0, 35.0)
	_rec()["home_task"] = "nap"
	c.call("_set_sleeping", true)
	c.call("_say", "nap", 3.0, false)


func _end_nap() -> void:
	nap_left = 0.0
	if String(_rec().get("home_task", "")) == "nap":
		_rec()["home_task"] = ""
	c.call("_set_sleeping", false)


## Anything that interrupts home life (assignment change, night, a threat).
func interrupt() -> void:
	if nap_left > 0.0:
		_end_nap()
	if carrying:
		carrying = false
		_show_carry(false)
	if String(_rec().get("home_task", "")) != "":
		_rec()["home_task"] = ""


## visual.action_event while working on a home task. Returns true when handled.
func on_work_action(work: Dictionary, action_name: String) -> bool:
	var k := String(work.get("kind", ""))
	match k:
		"cairn_fetch":
			if action_name != "sniff":
				return true
			carrying = true
			_place_tries = 0
			_rec()["home_task"] = "cairn"
			_show_carry(true)
			c.call("_voice", "clack")
			return true
		"cairn_place":
			if action_name != "stomp":
				return true
			carrying = false
			_show_carry(false)
			var rec := _rec()
			rec["cairn"] = mini(int(rec.get("cairn", 0)) + 1, CAIRN_MAX)
			rec["home_task"] = ""
			build_cairn()
			Fx.chips(c.get_parent(), cairn_pos() + Vector3.UP * 0.2, STONE_COLOR, 5)
			if _player_dist() < 12.0:
				c.call("_say", "cairn", 3.0, false)
			return true
		"perch":
			return true
		"lights":
			if action_name == "glow_pulse" and _player_dist() < 14.0:
				c.call("_say", "house_lights", 3.0, false)
			return true
		"notice":
			if action_name != "sniff":
				return true
			var s: Variant = GameState.structures.get(String(work.get("uid", "")))
			var thing := "furnishing"
			if s is Dictionary:
				thing = ItemDB.structure_display_name(String((s as Dictionary).get("id", ""))).to_lower()
			var line := ItemDB.creature_line(id, "notice_home").replace("{thing}", thing)
			c.call("_say_text", line, 3.0, false)
			var v: Variant = c.get("visual")
			if v is Node:
				(v as Node).call("show_emote", "heart", 1.4)
			return true
	return false


func _player_dist() -> float:
	return float(c.call("_dist_player"))


## A new structure near home: remember it (noticed later, by day).
func on_structure_placed(uid: String, structure_id: String) -> void:
	if structure_id in ["companion_bed", "companion_perch"] or _notice_queue.size() >= 3:
		return
	var s: Variant = GameState.structures.get(uid)
	if not (s is Dictionary) or String((s as Dictionary).get("area", "surface")) != "surface":
		return
	var pv: Variant = Logic.vec_from((s as Dictionary).get("pos"))
	if pv is Vector3 and (pv as Vector3).distance_to(_home()) <= NOTICE_RADIUS:
		_notice_queue.append(uid)


# --- The cairn (Pebble) -------------------------------------------------------------------------------------------

## (Re)builds the little stone stack beside the home spot from the saved count. Visual only.
func build_cairn() -> void:
	if kind != "cairn" or not c.is_inside_tree():
		return
	var n := clampi(int(_rec().get("cairn", 0)), 0, CAIRN_MAX)
	if n <= 0:
		if _cairn != null and is_instance_valid(_cairn):
			_cairn.queue_free()
		_cairn = null
		return
	var parent := c.get_parent()
	if parent == null:
		return
	if _cairn == null or not is_instance_valid(_cairn):
		_cairn = Node3D.new()
		_cairn.name = "PebbleCairn"
		parent.add_child(_cairn)
	for ch in _cairn.get_children():
		ch.queue_free()
	var base := cairn_pos()
	var ground: Variant = c.call("_snap_to_ground", base)
	_cairn.global_position = ground if ground is Vector3 else base
	var y := 0.0
	for i in n:
		var r := 0.2 - 0.02 * float(i)
		var st := Kit.blob(maxf(r, 0.08), Mat.toon(STONE_COLOR.darkened(0.06 * float(i % 3))), 11 + i, 0.25, 0.7)
		Kit.add(_cairn, st, Vector3(0.03 * float((i * 7) % 3 - 1), y + r * 0.6, 0.02 * float((i * 5) % 3 - 1)))
		y += r * 1.1


func _show_carry(on: bool) -> void:
	var v: Variant = c.get("visual")
	if not (v is Node3D):
		return
	if on:
		if _carry_mesh == null or not is_instance_valid(_carry_mesh):
			_carry_mesh = Kit.blob(0.09, Mat.toon(STONE_COLOR), 5, 0.25, 0.8)
			(v as Node3D).add_child(_carry_mesh)
			_carry_mesh.position = Vector3(0.0, 0.62, 0.05)
		_carry_mesh.visible = true
	elif _carry_mesh != null and is_instance_valid(_carry_mesh):
		_carry_mesh.visible = false
