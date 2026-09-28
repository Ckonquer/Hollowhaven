extends Node3D
## The Ballroom's candle-routing puzzle (MP §9 "short candle-routing puzzle", spec §7.3): light the hearth
## candle with the Lantern, then turn the candelabra so the ward-light runs along the gilt runners to the
## crescent lock of the Gallery doors. No timing, no audio-only cue: lit runners glow gold, dark ones stay
## plum, every brass hand + floor chevron shows where its flame goes, captions name the sounds. A brass
## lever resets the candelabra. Solving sets flag mm_ballroom_solved (persistent: the doors stay open).
## Logic lives in candle_route.gd (pure); this node owns the state and the visuals.
##   var p = Puzzle.new(); p.setup({"layout": Layout.PUZZLE}); area.add_child(p)
##   p.solved_now.connect(...)      # emitted once, when the flame first reaches the lock
## API: light_source(src) -> bool, turn(id) -> bool, reset() -> bool, is_solved(), state() -> Dictionary,
##      arms (id -> index), source_lit, candelabra (id -> node), source_candle, reset_lever.

signal changed
signal solved_now

const Layout := preload("res://data/manor_layout.gd")
const Route := preload("res://src/world/manor/candle_route.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const Candelabrum := preload("res://src/world/manor/route_candelabrum.gd")
const Interactable := preload("res://src/world/manor/manor_interactable.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const LoreDB := preload("res://src/core/lore_db.gd")

const RUNNER_W := 0.24
const DIM := Color("6e3f63")
const LIT := Color("ffcf6a")
const LORE_CARD := "lore_ch2_manor_dance_card"

var puzzle: Dictionary = Layout.PUZZLE
var arms: Dictionary = {}
var source_lit: bool = false
var solved: bool = false
var turns: int = 0
var resets: int = 0
var candelabra: Dictionary = {}       # id -> route_candelabrum node
var source_candle: Node3D = null
var reset_lever: Node3D = null
var dance_card: Node3D = null
var runner_nodes: Dictionary = {}     # "a|b" -> MeshInstance3D
var _lock_glow: MeshInstance3D = null
var _lock_dim: MeshInstance3D = null
var _dim_mat: Material
var _lit_mat: Material


func setup(params: Dictionary) -> void:
	var p: Variant = params.get("layout", null)
	if p is Dictionary:
		puzzle = p


func _ready() -> void:
	name = "CandleRoutePuzzle"
	add_to_group("mm_puzzle")
	arms = Route.initial_arms(puzzle)
	_dim_mat = Mat.toon(DIM, {"rim": 0.2})
	_lit_mat = Mat.glow(LIT, 1.5)
	_build()
	if bool(GameState.get_flag(Layout.FLAG_BALLROOM_SOLVED)):
		# Already solved in this save: show the finished dance (no signals, no captions).
		source_lit = true
		solved = true
		var sol := Route.solution(puzzle)
		if not sol.is_empty():
			arms = sol
		if source_candle != null:
			source_candle.call("restore", true)
	_sync(false)


# --- State -------------------------------------------------------------------------------------------------

func is_solved() -> bool:
	return solved


func trace() -> Dictionary:
	return Route.trace(puzzle, arms, source_lit)


func lit_nodes() -> Array:
	return trace()["lit"]


func state() -> Dictionary:
	var t := trace()
	return {"source_lit": source_lit, "arms": arms.duplicate(), "lit": t["lit"], "runners": t["runners"], "solved": solved,
		"turns": turns, "resets": resets}


## Lights the hearth candle (normally through the candle's own interaction, which calls back here).
func light_source(src: Variant = null) -> bool:
	if source_lit:
		return false
	if source_candle != null and not bool(source_candle.call("is_lit")):
		return bool(source_candle.call("light", src))   # -> _on_source_lit
	source_lit = true
	_after_change()
	return true


func turn(id: String) -> bool:
	if solved or not arms.has(id):
		return false
	arms = Route.turned(puzzle, arms, id)
	turns += 1
	Audio.play_3d("door_creak", _node_pos(id) + Vector3.UP, -14.0, 0.2, 18.0)
	Events.caption.emit("[a brass candelabrum turns with a small click]")
	_after_change()
	return true


func reset() -> bool:
	if solved:
		return false
	arms = Route.initial_arms(puzzle)
	resets += 1
	Audio.play_3d("gate_unlock", _node_pos("S") + Vector3.UP, -10.0, 0.05, 20.0)
	Events.caption.emit("[the lever clunks; every candelabrum turns back to its place]")
	_after_change()
	return true


func _on_source_lit(_c: Node3D) -> void:
	if source_lit:
		return
	source_lit = true
	_after_change()


func _after_change() -> void:
	var t := trace()
	if bool(t["solved"]) and not solved:
		solved = true
		GameState.set_flag(Layout.FLAG_BALLROOM_SOLVED, true)
		Audio.play_3d("gate_unlock", _node_pos("T") + Vector3.UP * 2.0, -2.0, 0.05, 30.0)
		Events.caption.emit("[the crescent lock chimes and the Gallery doors unlatch]")
		Events.notify.emit("The ward-light reached the crescent lock. The Gallery is open.", "success")
		_sync(true)
		changed.emit()
		solved_now.emit()
		return
	_sync(true)
	changed.emit()


# --- Visuals ------------------------------------------------------------------------------------------------

func _node_pos(id: String) -> Vector3:
	match id:
		"S":
			return puzzle["source"]["pos"]
		"T":
			return puzzle["target"]["pos"]
	var n: Dictionary = puzzle["nodes"].get(id, {})
	return n.get("pos", Vector3.ZERO)


func _build() -> void:
	# Hearth candle (the flame's source).
	source_candle = WardCandle.new()
	source_candle.setup({"id": "hearth", "kind": "hearth", "lit": false, "pool_radius": 1.6, "height": 1.2,
		"prompt": "Light the hearth candle"})
	source_candle.name = "HearthCandle"
	add_child(source_candle)
	source_candle.position = _node_pos("S")
	source_candle.lit.connect(_on_source_lit)
	# Candelabra.
	for id in Route.node_ids(puzzle):
		var c: Node3D = Candelabrum.new()
		c.setup({"id": String(id), "puzzle": self})
		add_child(c)
		c.position = _node_pos(String(id))
		candelabra[String(id)] = c
	# Gilt runners (visual only: nothing to trip on).
	for r in Route.runners(puzzle):
		var a := _node_pos(String(r[0]))
		var b := _node_pos(String(r[1]))
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var mi := MeshInstance3D.new()
		mi.name = "Runner_%s_%s" % [r[0], r[1]]
		var bm := BoxMesh.new()
		bm.size = Vector3(RUNNER_W, 0.02, maxf(d.length() - 0.9, 0.2))
		mi.mesh = bm
		mi.material_override = _dim_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (a + b) * 0.5 + Vector3.UP * 0.03)
		runner_nodes[_rkey(String(r[0]), String(r[1]))] = mi
	# Crescent lock on the Gallery doors (T): dim crescent, glowing once the flame arrives.
	var t := _node_pos("T")
	var lock_pos := Vector3(t.x, float(puzzle["target"].get("lock_y", 4.3)), -50.94)
	_lock_dim = Kit.cylinder(0.34, 0.34, 0.04, Mat.toon(Color("8a6a9a"), {"rim": 0.4}), 20)
	Kit.add(self, _lock_dim, lock_pos, Vector3(90, 0, 0))
	_lock_glow = Kit.cylinder(0.34, 0.34, 0.05, Mat.glow(LIT, 2.2), 20)
	Kit.add(self, _lock_glow, lock_pos + Vector3(0, 0, 0.01), Vector3(90, 0, 0))
	var bite := Kit.cylinder(0.29, 0.29, 0.06, Mat.toon(Color("4a2a44")), 20)
	Kit.add(self, bite, lock_pos + Vector3(0.14, 0.05, 0.03), Vector3(90, 0, 0))
	# Reset lever.
	reset_lever = Interactable.new()
	reset_lever.setup({"id": "ballroom_reset", "radius": 0.8, "offset": Vector3(0, 1.0, 0),
		"text_func": Callable(self, "_reset_prompt"), "handler": Callable(self, "reset")})
	reset_lever.name = "ResetLever"
	add_child(reset_lever)
	reset_lever.position = puzzle["reset"]["pos"]
	var gold := Mat.outlined(Mat.toon(Color("d6ad55"), {"rim": 0.5}), 0.012)
	Kit.add(reset_lever, Kit.cylinder(0.22, 0.28, 0.9, Mat.toon(Color("5a3a52")), 12), Vector3(0, 0.45, 0))
	Kit.add(reset_lever, Kit.box(Vector3(0.06, 0.6, 0.06), gold), Vector3(0, 1.15, 0.08), Vector3(-25, 0, 0))
	Kit.add(reset_lever, Kit.sphere(0.08, gold, 8, 10), Vector3(0, 1.43, 0.2))
	Kit.static_collider(reset_lever, _cyl_shape(0.28, 0.9), Vector3(0, 0.45, 0), 1).name = "SolidBody"
	# The dance card (the rule, in writing).
	dance_card = Interactable.new()
	dance_card.setup({"id": "dance_card", "text": "Read the dance card", "radius": 0.7, "offset": Vector3(0, 1.0, 0),
		"handler": Callable(self, "_read_card")})
	dance_card.name = "DanceCard"
	add_child(dance_card)
	dance_card.position = puzzle["card"]["pos"]
	Kit.add(dance_card, Kit.cylinder(0.05, 0.08, 1.0, gold, 8), Vector3(0, 0.5, 0))
	Kit.add(dance_card, Kit.box(Vector3(0.42, 0.3, 0.03), Mat.toon(Color("f7ecd6"))), Vector3(0, 1.1, 0), Vector3(-30, 0, 0))
	Kit.static_collider(dance_card, _cyl_shape(0.1, 1.0), Vector3(0, 0.5, 0), 1).name = "SolidBody"


static func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


func _rkey(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _reset_prompt() -> Dictionary:
	if solved:
		return {"text": "The dance is finished", "enabled": false}
	return {"text": "Pull the lever (candelabra back to their places)", "enabled": true}


func _read_card() -> void:
	var l := LoreDB.get_lore(LORE_CARD)
	GameState.discover_lore(LORE_CARD)
	Events.say.emit(String(l.get("title", "A Dance Card")), String(l.get("text", "")), 12.0)


func _sync(animate: bool) -> void:
	var t := trace()
	var lit: Array = t["lit"]
	var lit_runners := {}
	for r in t["runners"]:
		lit_runners[_rkey(String(r[0]), String(r[1]))] = true
	for key in runner_nodes:
		(runner_nodes[key] as MeshInstance3D).material_override = _lit_mat if lit_runners.has(key) else _dim_mat
	for id in candelabra:
		var c: Node3D = candelabra[id]
		c.call("set_lit", lit.has(id))
		c.call("point_at", _node_pos(Route.arm_target(puzzle, arms, String(id))), animate)
	if _lock_glow != null:
		_lock_glow.visible = solved
		_lock_dim.visible = not solved
