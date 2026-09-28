extends Node3D
## Sluice Gallery (room 4): the WATER line. Two big valve wheels decide where the inlet's water goes:
##   valve A (upper, by the header basin): the drain channel | the middle channel
##   valve B (lower, end of the middle channel): the overflow drain | the ward basin
## Water planes in the shallow channels show the current flow at a glance (sound is only decoration); each
## wheel carries a large arrow toward the channel it feeds. Water reaching the ward basin sets
## ch2_line_water (persistent), lights the basin and the conduit toward the hub. Valves turn freely, nothing
## drowns, nothing locks; once the line flows the valves stay put (no way to undo the flag).
## Logic: src/world/works/works_puzzles.gd (pure). Place this node at the world origin (children use world
## coordinates from data/works_layout.gd SLUICE).

signal solved_changed(is_solved: bool)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://data/works_layout.gd")
const Puzzles := preload("res://src/world/works/works_puzzles.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const FLAG := "ch2_line_water"
const FLOOR_Y := -20.0
const WATER_Y := -19.86
const DRY_Y := -20.25
## Channel beds (x, z, size x, size z) per channel (the header basin is always full).
const CHANNELS := {
	"header": [Rect2(21.0, -40.4, 6.0, 3.4)],
	"drain": [Rect2(14.6, -36.4, 9.4, 1.8)],
	"middle": [Rect2(24.8, -37.0, 1.6, 6.0), Rect2(24.8, -31.0, 12.4, 1.8)],
	"ward": [Rect2(35.4, -29.2, 1.8, 3.8), Rect2(30.0, -25.4, 7.2, 1.8)],
}
## Valve arrows: world direction per valve position.
const ARROW_A := [Vector3(-1, 0, 0), Vector3(1, 0, 0)]
const ARROW_B := [Vector3(0, 0, -1), Vector3(0, 0, 1)]

var a: int = 0
var b: int = 0
var solved: bool = false
var turns: int = 0                     # valve turns this visit (tests / QA)

var _water: Dictionary = {}            # channel -> [MeshInstance3D]
var _wheels: Array = []                # [Node3D, Node3D]
var _arrows: Array = []                # [Node3D, Node3D]
var _basin_light: OmniLight3D
var _line_on: Array = []               # glowing conduit studs (visible once solved)
var _markers: Array = []
var _water_mat: Material


func _ready() -> void:
	name = "Sluice"
	_water_mat = Mat.transparent(Color(0.42, 0.74, 0.78, 0.62), false)
	solved = bool(GameState.get_flag(FLAG))
	if solved:
		a = 1
		b = 1
	else:
		a = int(Puzzles.SLUICE_START[0])
		b = int(Puzzles.SLUICE_START[1])
	_build_water()
	_build_valve(0, Layout.SLUICE["valve_a"])
	_build_valve(1, Layout.SLUICE["valve_b"])
	_build_basin()
	_apply(false)
	Events.settings_changed.connect(_on_settings_changed)
	_update_markers()


func flow() -> Dictionary:
	return Puzzles.sluice_flow(a, b)


## Turns valve 0 (A) or 1 (B). Returns false when the line already flows (valves stay put).
func turn(valve: int) -> bool:
	if solved:
		Events.notify.emit("The water line is already flowing.", "info")
		return false
	if valve == 0:
		a = Puzzles.valve_next(a)
	else:
		b = Puzzles.valve_next(b)
	turns += 1
	var wheel: Node3D = _wheels[valve]
	if wheel.is_inside_tree():
		create_tween().tween_property(wheel, "rotation:z", wheel.rotation.z + PI, 0.8).set_trans(Tween.TRANS_SINE)
		Audio.play_3d("door_creak", wheel.global_position, -8.0)
	var names: Array = Puzzles.SLUICE_A_NAMES if valve == 0 else Puzzles.SLUICE_B_NAMES
	var pos: int = a if valve == 0 else b
	Events.caption.emit("[the valve groans round; water rushes toward %s]" % String(names[pos]))
	_apply(true)
	if Puzzles.sluice_solved(a, b):
		_solve()
	return true


func _solve() -> void:
	solved = true
	GameState.set_flag(FLAG, true)
	Audio.play_3d("ward_hum", Layout.SLUICE["basin"] + Vector3.UP, -4.0)
	Events.caption.emit("[the ward basin fills, and the pipes in the walls begin to hum]")
	Events.notify.emit("The water line is restored.", "success")
	_apply(true)
	_update_markers()
	solved_changed.emit(true)


func _valve_text(valve: int) -> Dictionary:
	if solved:
		return {"text": "The water line is flowing", "enabled": false, "reason": "The water reaches the ward basin."}
	if valve == 0:
		return {"text": "Turn the upper valve (sends water to %s)" % String(Puzzles.SLUICE_A_NAMES[a]), "enabled": true}
	return {"text": "Turn the lower valve (sends water to %s)" % String(Puzzles.SLUICE_B_NAMES[b]), "enabled": true}


# --- Visuals ------------------------------------------------------------------------------------------------------

func _build_water() -> void:
	var bed := Mat.toon(Color("2f3a40"), {"noise": 0.15})
	for ch in CHANNELS:
		var list: Array = []
		for r in CHANNELS[ch]:
			var rect: Rect2 = r
			var c := rect.get_center()
			# a dark bed a hair above the floor (the water sits over it when the channel flows)
			var bmi := MeshInstance3D.new()
			var bm := PlaneMesh.new()
			bm.size = rect.size
			bmi.mesh = bm
			bmi.material_override = bed
			bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(bmi)
			bmi.position = Vector3(c.x, FLOOR_Y + 0.015, c.y)
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = rect.size - Vector2(0.05, 0.05)
			mi.mesh = pm
			mi.material_override = _water_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.position = Vector3(c.x, WATER_Y, c.y)
			list.append(mi)
		_water[ch] = list
	# the inlet: a pipe mouth in the north wall pouring into the header basin
	var iron := Mat.outlined(Mat.toon(Color("4b5563"), {"rim": 0.35}), 0.014)
	Kit.add(self, Kit.cylinder(0.35, 0.35, 1.2, iron, 12), Vector3(24.0, -17.6, -40.5), Vector3(90, 0, 0))
	var fall := Kit.add(self, Kit.box(Vector3(0.5, 2.3, 0.18), _water_mat), Vector3(24.0, -18.95, -40.0))
	fall.name = "Inflow"


func _build_valve(i: int, pos: Vector3) -> void:
	var iron := Mat.outlined(Mat.toon(Color("4b5563"), {"rim": 0.35}), 0.014)
	var brass := Mat.outlined(Mat.toon(Color("c9a25a"), {"rim": 0.45, "specular": 0.4}), 0.014)
	var root := Node3D.new()
	root.name = "Valve%s" % ["A", "B"][i]
	add_child(root)
	root.position = pos
	# pipe stand + a big wheel facing the approach side
	Kit.add(root, Kit.cylinder(0.16, 0.2, 1.2, iron, 10), Vector3(0, 0.6, 0))
	Kit.add(root, Kit.cylinder(0.3, 0.34, 0.14, iron, 12), Vector3(0, 0.07, 0))
	var wheel := Node3D.new()
	root.add_child(wheel)
	wheel.position = Vector3(0, 1.25, 0.28 if i == 0 else -0.28)
	Kit.add(wheel, Kit.torus(0.36, 0.46, brass), Vector3.ZERO, Vector3(90, 0, 0))
	for k in 4:
		Kit.add(wheel, Kit.box(Vector3(0.84, 0.06, 0.06), brass), Vector3.ZERO, Vector3(0, 0, 45.0 * float(k)))
	Kit.add(wheel, Kit.sphere(0.09, brass, 8, 10), Vector3.ZERO)
	_wheels.append(wheel)
	# big arrow on a dial plate above the wheel, pointing at the channel it feeds
	Kit.add(root, Kit.cylinder(0.5, 0.5, 0.06, Mat.toon(Color("46505e")), 16), Vector3(0, 1.9, 0))
	var arrow := Node3D.new()
	root.add_child(arrow)
	arrow.position = Vector3(0, 1.95, 0)
	var ink := Mat.outlined(Mat.toon(Color("efe6cf"), {"emission": Color("efe6cf"), "emission_energy": 0.35}), 0.012)
	Kit.add(arrow, Kit.box(Vector3(0.12, 0.05, 0.6), ink), Vector3(0, 0, -0.05))
	Kit.add(arrow, Kit.cone(0.2, 0.3, ink, 3), Vector3(0, 0, -0.42), Vector3(-90, 0, 0))
	_arrows.append(arrow)
	# solid core so nobody walks through it
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.36
	sh.height = 2.0
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	body.add_child(cs)
	root.add_child(body)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.4, 2.0, 1.4), "offset": Vector3(0, 1.0, 0),
		"text_func": _valve_text.bind(i), "handler": func(_p: Node) -> void: turn(i)})
	it.name = "Turn"
	root.add_child(it)
	var ring := Kit.add(root, Kit.torus(0.9, 1.08, Mat.glow(Color("fff1c4"), 1.8)), Vector3(0, 0.04, 0))
	ring.scale = Vector3(1.0, 0.2, 1.0)
	_markers.append(ring)


func _build_basin() -> void:
	var pos: Vector3 = Layout.SLUICE["basin"]
	var stone := Mat.outlined(Mat.toon(Color("6f7480"), {"noise": 0.12}), 0.016)
	# the ward basin: a low round rim around the end of the ward channel, with the line glyph behind it
	var rim := Kit.add(self, Kit.torus(0.9, 1.2, stone), pos + Vector3(0, 0.08, 0))
	rim.scale = Vector3(1.0, 0.45, 1.0)
	_basin_light = OmniLight3D.new()
	_basin_light.light_color = Color("8fd8f0")
	_basin_light.light_energy = 1.2
	_basin_light.omni_range = 5.5
	_basin_light.shadow_enabled = false
	add_child(_basin_light)
	_basin_light.position = pos + Vector3(0, 1.2, 0)
	# conduit studs along the south wall toward the hub (x 37 -> 30.5 at z -21.6, the doorway side)
	var off := Mat.toon(Color("46505e"))
	var on := Mat.glow(Color("8fd8f0"), 2.0)
	for k in 7:
		var p := Vector3(37.2 - float(k) * 1.0, -18.2, -21.35)
		Kit.add(self, Kit.box(Vector3(0.36, 0.14, 0.08), off), p)
		var g := Kit.add(self, Kit.box(Vector3(0.3, 0.1, 0.1), on), p + Vector3(0, 0, 0.02))
		_line_on.append(g)


func _apply(animate: bool) -> void:
	var f := flow()
	for ch in _water:
		var full: bool = ch == "header" or bool(f.get(ch, false))
		for mi in _water[ch]:
			var node := mi as MeshInstance3D
			var y := WATER_Y if full else DRY_Y
			if animate and node.is_inside_tree():
				create_tween().tween_property(node, "position:y", y, 1.2).set_trans(Tween.TRANS_SINE)
			else:
				node.position.y = y
	for i in _arrows.size():
		var dir: Vector3 = (ARROW_A if i == 0 else ARROW_B)[a if i == 0 else b]
		var yaw := atan2(-dir.x, -dir.z)
		var arr: Node3D = _arrows[i]
		if animate and arr.is_inside_tree():
			create_tween().tween_property(arr, "rotation:y", yaw, 0.5).set_trans(Tween.TRANS_BACK)
		else:
			arr.rotation.y = yaw
	_basin_light.visible = solved
	for g in _line_on:
		(g as Node3D).visible = solved


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_update_markers()


func _update_markers() -> void:
	var on := bool(Settings.get_value("high_visibility_cues")) and not solved
	for m in _markers:
		(m as Node3D).visible = on
