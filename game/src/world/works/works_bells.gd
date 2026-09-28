extends Node3D
## Bellmaker's Floor (room 5): the BELL line. Four great bells hang over four striker posts, each marked
## with a large symbol (Leaf, Moon, Key, Flame). The bellmaker's plaque on the north wall shows the order
## with the same symbols; a lamp under each plate lights as the order advances. Every strike is told by a
## caption naming the symbol and the step ("[the Leaf bell rings - 1 of 4]") and by the bell swinging, so
## nothing depends on hearing a pitch. A wrong strike only makes the bells fall quiet (lamps go out, start
## again; no damage, no lock-out, no timer). The whole order sets ch2_line_bell (persistent).
## Bellcap Sentries (spawner hw_sp_bells) may be about; the mechanism never waits on them.
## Logic: src/world/works/works_puzzles.gd bell_step (pure). Place at the world origin.

signal solved_changed(is_solved: bool)

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://data/works_layout.gd")
const Puzzles := preload("res://src/world/works/works_puzzles.gd")
const Glyphs := preload("res://src/world/works/works_glyphs.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const FLAG := "ch2_line_bell"
const BELL_TOP_Y := -8.2              # the beam the bells hang from
const PITCH := {"leaf": 1.15, "moon": 0.85, "key": 1.0, "flame": 1.3}   # decoration only (never required)

var progress: int = 0
var solved: bool = false
var strikes: Array = []               # symbols struck this visit (tests / QA)

var _bells: Dictionary = {}           # symbol -> swinging Node3D
var _board_on: Array = []             # plate lamps (in BELL_ORDER)
var _board_off: Array = []
var _next_rings: Array = []           # high-visibility ring around the next plate
var _markers: Array = []


func _ready() -> void:
	name = "Bells"
	solved = bool(GameState.get_flag(FLAG))
	progress = Layout.BELL_ORDER.size() if solved else 0
	for sym in Layout.BELLS:
		_build_bell(String(sym), Layout.BELLS[sym])
	_build_board()
	_refresh()
	Events.settings_changed.connect(_on_settings_changed)


## Strikes one bell. Returns the step result ("advance" | "reset" | "solved" | "ignored").
func strike(symbol: String) -> String:
	if not _bells.has(symbol):
		return "ignored"
	_swing(symbol)
	if solved:
		Events.caption.emit("[the %s bell rings; the bell line already hums]" % String(Layout.BELL_NAMES[symbol]))
		return "ignored"
	strikes.append(symbol)
	var r: Dictionary = Puzzles.bell_step(progress, symbol)
	progress = int(r["progress"])
	var result := String(r["result"])
	var total: int = Layout.BELL_ORDER.size()
	match result:
		"advance":
			Events.caption.emit("[the %s bell rings - %d of %d]" % [String(Layout.BELL_NAMES[symbol]), progress, total])
		"reset":
			if progress == 1:
				Events.caption.emit("[the %s bell rings - the order starts again: 1 of %d]" % [String(Layout.BELL_NAMES[symbol]), total])
			else:
				Events.caption.emit("[the %s bell clanks dully and the bells fall quiet - begin again with the first symbol]" % String(Layout.BELL_NAMES[symbol]))
				Audio.play_3d("mine_hit", (Layout.BELLS[symbol] as Vector3) + Vector3.UP * 5.0, -10.0, 0.0)
		"solved":
			_solve()
	_refresh()
	return result


func _solve() -> void:
	solved = true
	GameState.set_flag(FLAG, true)
	Events.caption.emit("[all four bells ring together, and the note runs away into the walls]")
	Events.notify.emit("The bell line is restored.", "success")
	Audio.play_3d("ward_hum", Layout.BELL_BOARD + Vector3.UP * 3.0, -4.0)
	solved_changed.emit(true)


func _strike_text(symbol: String) -> Dictionary:
	return {"text": "Strike the %s bell" % String(Layout.BELL_NAMES[symbol]), "enabled": true}


func _swing(symbol: String) -> void:
	var pivot: Node3D = _bells[symbol]
	if pivot.is_inside_tree():
		var tw := create_tween()
		tw.tween_property(pivot, "rotation:x", 0.22, 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "rotation:x", -0.14, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
		Audio.play_3d("mine_hit", pivot.global_position + Vector3.DOWN * 1.5, -2.0, 0.0, 40.0)


# --- Visuals ------------------------------------------------------------------------------------------------------

func _build_bell(symbol: String, pos: Vector3) -> void:
	var bronze := Mat.outlined(Mat.toon(Color("a8743e"), {"rim": 0.5, "specular": 0.45}), 0.02)
	var iron := Mat.outlined(Mat.toon(Color("333a46"), {"rim": 0.35}), 0.014)
	var ink := Mat.outlined(Mat.toon(Color("f3e6c8"), {"emission": Color("f3e6c8"), "emission_energy": 0.4}), 0.02)
	var plate := Mat.outlined(Mat.toon(Color("46505e")), 0.016)
	# the bell (swings on its pivot under the beam)
	var pivot := Node3D.new()
	pivot.name = "Bell_" + symbol
	add_child(pivot)
	pivot.position = Vector3(pos.x, BELL_TOP_Y, pos.z)
	Kit.add(pivot, Kit.cylinder(0.02, 0.02, 1.4, iron, 5), Vector3(0, -0.7, 0))
	Kit.add(pivot, Kit.cylinder(0.5, 1.05, 1.5, bronze, 18), Vector3(0, -2.15, 0))
	Kit.add(pivot, Kit.sphere(0.5, bronze, 10, 14), Vector3(0, -1.4, 0), Vector3.ZERO, Vector3(1.0, 0.5, 1.0))
	Kit.add(pivot, Kit.torus(0.98, 1.14, bronze), Vector3(0, -2.88, 0))
	Kit.add(pivot, Kit.sphere(0.18, iron, 8, 10), Vector3(0, -2.95, 0))
	var bell_glyph := Glyphs.build(symbol, ink, 0.9)
	pivot.add_child(bell_glyph)
	bell_glyph.position = Vector3(0, -2.2, 0.9)
	bell_glyph.rotation.x = -0.35
	_bells[symbol] = pivot
	# the striker post facing the middle of the room, with the same symbol, big, on a round plate
	var root := Node3D.new()
	root.name = "Striker_" + symbol
	add_child(root)
	root.position = pos
	var centre := Vector3(12.0, pos.y, 33.5)
	var to := centre - pos
	root.rotation.y = atan2(to.x, to.z)          # local +Z faces the room centre
	Kit.add(root, Kit.box(Vector3(0.3, 1.3, 0.3), iron), Vector3(0, 0.65, 0))
	Kit.add(root, Kit.cylinder(0.62, 0.62, 0.08, plate, 20), Vector3(0, 1.75, 0.18), Vector3(90, 0, 0))
	var g := Glyphs.build(symbol, ink, 1.0)
	root.add_child(g)
	g.position = Vector3(0, 1.75, 0.26)
	# lever
	Kit.add(root, Kit.box(Vector3(0.08, 0.7, 0.08), iron), Vector3(0.28, 1.05, 0.12), Vector3(0, 0, -20))
	Kit.add(root, Kit.sphere(0.08, Mat.toon(Color("c9a25a")), 6, 8), Vector3(0.4, 1.38, 0.12))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.5, 2.3, 0.5)
	cs.shape = sh
	cs.position = Vector3(0, 1.15, 0)
	body.add_child(cs)
	root.add_child(body)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.4, 2.0, 1.4), "offset": Vector3(0, 1.0, 0.4),
		"text_func": _strike_text.bind(symbol), "handler": func(_p: Node) -> void: strike(symbol)})
	it.name = "Strike"
	root.add_child(it)
	var ring := Kit.add(root, Kit.torus(0.85, 1.02, Mat.glow(Color("fff1c4"), 1.6)), Vector3(0, 0.04, 0))
	ring.scale = Vector3(1.0, 0.2, 1.0)
	_markers.append(ring)


func _build_board() -> void:
	var plate := Mat.outlined(Mat.toon(Color("46505e")), 0.016)
	var ink := Mat.outlined(Mat.toon(Color("f3e6c8"), {"emission": Color("f3e6c8"), "emission_energy": 0.35}), 0.016)
	var brass := Mat.outlined(Mat.toon(Color("c9a25a"), {"rim": 0.4}), 0.014)
	var z := Layout.BELL_BOARD.z + 0.08
	var y := Layout.BELL_BOARD.y + 3.1
	Kit.add(self, Kit.box(Vector3(6.2, 2.1, 0.12), brass), Vector3(Layout.BELL_BOARD.x, y, z))
	var n: int = Layout.BELL_ORDER.size()
	for i in n:
		var x := Layout.BELL_BOARD.x + (float(i) - float(n - 1) * 0.5) * 1.45
		Kit.add(self, Kit.cylinder(0.56, 0.56, 0.06, plate, 20), Vector3(x, y + 0.2, z + 0.08), Vector3(90, 0, 0))
		var g := Glyphs.build(String(Layout.BELL_ORDER[i]), ink, 0.85)
		add_child(g)
		g.position = Vector3(x, y + 0.2, z + 0.14)
		var off := Kit.add(self, Kit.sphere(0.1, Mat.toon(Color("3a3530")), 6, 8), Vector3(x, y - 0.62, z + 0.12))
		var on := Kit.add(self, Kit.sphere(0.11, Mat.glow(Color("ffd08a"), 2.6), 6, 8), Vector3(x, y - 0.62, z + 0.12))
		_board_off.append(off)
		_board_on.append(on)
		var ring := Kit.add(self, Kit.torus(0.6, 0.72, Mat.glow(Color("fff1c4"), 2.0)), Vector3(x, y + 0.2, z + 0.1), Vector3(90, 0, 0))
		_next_rings.append(ring)
	# one warm light on the board so it is always readable
	var l := OmniLight3D.new()
	l.light_color = Color("ffd6a0")
	l.light_energy = 0.9
	l.omni_range = 5.0
	l.shadow_enabled = false
	add_child(l)
	l.position = Vector3(Layout.BELL_BOARD.x, y, z + 1.6)


func _refresh() -> void:
	for i in _board_on.size():
		var lit := i < progress
		(_board_on[i] as Node3D).visible = lit
		(_board_off[i] as Node3D).visible = not lit
	var hv := bool(Settings.get_value("high_visibility_cues"))
	for i in _next_rings.size():
		(_next_rings[i] as Node3D).visible = hv and not solved and i == progress
	for m in _markers:
		(m as Node3D).visible = hv and not solved


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_refresh()
