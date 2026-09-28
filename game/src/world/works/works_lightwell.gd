extends Node3D
## Light Well (room 8): the LIGHT line. Daylight falls down the well onto mirror A. Each mirror turns a
## quarter at a time (big arrow on its head = where it sends the light); the beam itself is drawn as a
## glowing shaft, so the whole state is visible at a glance. A -> B -> the ward crystal restores the line
## (ch2_line_light, persistent): the crystal blazes, the well warms, the alcove shutter lifts (works_door
## listens to the flag). The brass lever resets both mirrors to their starting facings at any time.
## No timer, no fail state. Logic: src/world/works/works_puzzles.gd beam_path (pure). Place at the origin.

signal solved_changed(is_solved: bool)

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://data/works_layout.gd")
const Puzzles := preload("res://src/world/works/works_puzzles.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const FLAG := "ch2_line_light"
const BEAM_Y := 1.25                  # beam height above the floor (mirror heads)
const SKY_Y := -3.2                   # the skylight glass (above the ceiling opening at y -4)
const ROOM := Rect2(26.0, 20.0, 13.0, 14.0)
const BEAM_COLOR := Color("fff0c0")

var mirrors: Array = [0, 3]
var solved: bool = false
var resets: int = 0

var _heads: Array = []                # mirror head pivots (rotate yaw)
var _beam_a: MeshInstance3D           # A -> end
var _beam_b: MeshInstance3D           # B -> end
var _crystal_glow: Node3D
var _crystal_light: OmniLight3D
var _warm: OmniLight3D
var _markers: Array = []


func _ready() -> void:
	name = "LightWell"
	solved = bool(GameState.get_flag(FLAG))
	mirrors = [1, 2] if solved else Puzzles.MIRROR_START.duplicate()
	_build_sky()
	_build_mirror(0, Layout.LIGHTWELL["mirror_a"])
	_build_mirror(1, Layout.LIGHTWELL["mirror_b"])
	_build_target()
	_build_reset()
	var beam_mat := Mat.transparent(Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.55), true)
	_beam_a = _beam_mesh(beam_mat)
	_beam_b = _beam_mesh(beam_mat)
	_warm = OmniLight3D.new()
	_warm.light_color = Color("ffe6b0")
	_warm.light_energy = 1.1
	_warm.omni_range = 12.0
	_warm.shadow_enabled = false
	add_child(_warm)
	_warm.position = Vector3(32.5, -13.0, 27.0)
	_apply(false)
	Events.settings_changed.connect(_on_settings_changed)


func beam() -> Dictionary:
	return Puzzles.beam_path(int(mirrors[0]), int(mirrors[1]))


func turn(i: int) -> bool:
	if solved:
		Events.notify.emit("The light line is already awake.", "info")
		return false
	mirrors[i] = Puzzles.mirror_next(int(mirrors[i]))
	Audio.play_3d("chest_close", (_heads[i] as Node3D).global_position, -8.0)
	Events.caption.emit("[the mirror grinds a quarter turn; it now faces %s]" % String(Puzzles.FACING_NAMES[int(mirrors[i])]))
	_apply(true)
	if bool(beam()["solved"]):
		_solve()
	return true


func reset() -> void:
	if solved:
		return
	resets += 1
	mirrors = Puzzles.MIRROR_START.duplicate()
	Audio.play_3d("gate_unlock", Layout.LIGHTWELL["reset"] + Vector3.UP, -8.0)
	Events.caption.emit("[the brass lever clunks; both mirrors swing back to where they began]")
	_apply(true)


func _solve() -> void:
	solved = true
	GameState.set_flag(FLAG, true)
	Audio.play_3d("ward_restore", Layout.LIGHTWELL["target"] + Vector3.UP, -6.0)
	Events.caption.emit("[the ward crystal catches the daylight and rings like glass]")
	Events.notify.emit("The light line is restored.", "success")
	_apply(true)
	solved_changed.emit(true)


func _mirror_text(i: int) -> Dictionary:
	if solved:
		return {"text": "The light line is awake", "enabled": false, "reason": "Daylight reaches the ward crystal."}
	return {"text": "Turn the %s mirror (now facing %s)" % ["first" if i == 0 else "second", String(Puzzles.FACING_NAMES[int(mirrors[i])])], "enabled": true}


func _reset_text() -> Dictionary:
	if solved:
		return {}
	return {"text": "Pull the brass lever (set the mirrors back)", "enabled": true}


# --- Visuals --------------------------------------------------------------------------------------------------------

func _build_sky() -> void:
	var a: Vector3 = Layout.LIGHTWELL["mirror_a"]
	var sky := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.6, 2.6)
	sky.mesh = pm
	sky.material_override = Mat.glow(Color("fff4d8"), 1.8)
	sky.rotation_degrees.x = 180.0
	add_child(sky)
	sky.position = Vector3(a.x, SKY_Y + 0.05, a.z)
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var h := SKY_Y - (a.y + BEAM_Y)
	cm.top_radius = 0.55
	cm.bottom_radius = 0.28
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	shaft.mesh = cm
	shaft.material_override = Mat.transparent(Color(1.0, 0.95, 0.8, 0.18), true)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)
	shaft.position = Vector3(a.x, a.y + BEAM_Y + h * 0.5, a.z)
	var sun := SpotLight3D.new()
	sun.name = "WellLight"
	sun.light_color = Color("fff0cc")
	sun.light_energy = 3.0
	sun.spot_range = 18.0
	sun.spot_angle = 14.0
	sun.spot_attenuation = 0.5
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 1.2
	add_child(sun)
	sun.position = Vector3(a.x, SKY_Y - 0.2, a.z)
	sun.rotation_degrees = Vector3(-90, 0, 0)


func _build_mirror(i: int, pos: Vector3) -> void:
	var stone := Mat.outlined(Mat.toon(Color("b9b2a3"), {"noise": 0.12}), 0.016)
	var brass := Mat.outlined(Mat.toon(Color("c9a25a"), {"rim": 0.5, "specular": 0.5}), 0.014)
	var silver := Mat.toon(Color("dfe6ee"), {"rim": 0.9, "specular": 0.8, "emission": Color("dfe6ee"), "emission_energy": 0.25})
	var root := Node3D.new()
	root.name = "Mirror%s" % ["A", "B"][i]
	add_child(root)
	root.position = pos
	Kit.add(root, Kit.cylinder(0.42, 0.5, 0.95, stone, 14), Vector3(0, 0.475, 0))
	var head := Node3D.new()
	root.add_child(head)
	head.position = Vector3(0, BEAM_Y, 0)
	Kit.add(head, Kit.cylinder(0.36, 0.36, 0.1, brass, 16), Vector3(0, -0.22, 0))
	# the mirror plate stands at 45 degrees; its arrow points where it sends the light (local -Z)
	var plate := Kit.add(head, Kit.box(Vector3(0.7, 0.62, 0.05), silver), Vector3(0, 0.08, 0), Vector3(0, 45, 0))
	plate.name = "Plate"
	Kit.add(head, Kit.box(Vector3(0.78, 0.7, 0.03), brass), Vector3(0, 0.08, 0) + Basis(Vector3.UP, deg_to_rad(45.0)) * Vector3(0, 0, -0.04), Vector3(0, 45, 0))
	var ink := Mat.outlined(Mat.toon(Color("fff1c4"), {"emission": Color("fff1c4"), "emission_energy": 0.8}), 0.012)
	Kit.add(head, Kit.box(Vector3(0.1, 0.05, 0.5), ink), Vector3(0, 0.5, -0.2))
	Kit.add(head, Kit.cone(0.16, 0.26, ink, 3), Vector3(0, 0.5, -0.55), Vector3(-90, 0, 0))
	_heads.append(head)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.5
	sh.height = 1.8
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	root.add_child(body)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.5, 2.0, 1.5), "offset": Vector3(0, 1.0, 0),
		"text_func": _mirror_text.bind(i), "handler": func(_p: Node) -> void: turn(i)})
	it.name = "Turn"
	root.add_child(it)
	var ring := Kit.add(root, Kit.torus(0.85, 1.02, Mat.glow(Color("fff1c4"), 1.6)), Vector3(0, 0.04, 0))
	ring.scale = Vector3(1.0, 0.2, 1.0)
	_markers.append(ring)


func _build_target() -> void:
	var pos: Vector3 = Layout.LIGHTWELL["target"]
	var stone := Mat.outlined(Mat.toon(Color("b9b2a3"), {"noise": 0.12}), 0.016)
	Kit.add(self, Kit.cylinder(0.45, 0.55, 0.9, stone, 14), pos + Vector3(0, 0.45, 0))
	var dim := Mat.outlined(Mat.toon(Color("9fb8c8"), {"rim": 0.8, "emission": Color("9fb8c8"), "emission_energy": 0.25}), 0.014)
	Kit.add(self, Kit.blob(0.32, dim, 57, 0.18, 1.8, 2), pos + Vector3(0, BEAM_Y, 0))
	_crystal_glow = Kit.add(self, Kit.blob(0.36, Mat.glow(Color("fff4d0"), 2.6), 57, 0.18, 1.8, 2), pos + Vector3(0, BEAM_Y, 0))
	_crystal_light = OmniLight3D.new()
	_crystal_light.light_color = Color("fff0c8")
	_crystal_light.light_energy = 1.6
	_crystal_light.omni_range = 7.0
	_crystal_light.shadow_enabled = false
	add_child(_crystal_light)
	_crystal_light.position = pos + Vector3(0, BEAM_Y + 0.4, 0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.55
	sh.height = 1.8
	cs.shape = sh
	cs.position = pos + Vector3(0, 0.9, 0)
	body.add_child(cs)
	add_child(body)


func _build_reset() -> void:
	var pos: Vector3 = Layout.LIGHTWELL["reset"]
	var iron := Mat.outlined(Mat.toon(Color("333a46"), {"rim": 0.35}), 0.014)
	var brass := Mat.outlined(Mat.toon(Color("c9a25a"), {"rim": 0.5, "specular": 0.5}), 0.014)
	var root := Node3D.new()
	root.name = "ResetLever"
	add_child(root)
	root.position = pos
	Kit.add(root, Kit.box(Vector3(0.5, 0.9, 0.3), iron), Vector3(0, 0.45, 0))
	Kit.add(root, Kit.box(Vector3(0.07, 0.7, 0.07), brass), Vector3(0, 1.1, 0.05), Vector3(-25, 0, 0))
	Kit.add(root, Kit.sphere(0.1, brass, 8, 10), Vector3(0, 1.42, -0.1))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.5, 0.9, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	body.add_child(cs)
	root.add_child(body)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.2, 1.8, 1.2), "offset": Vector3(0, 0.9, 0.3),
		"text_func": _reset_text, "handler": func(_p: Node) -> void: reset()})
	it.name = "Pull"
	root.add_child(it)
	var ring := Kit.add(root, Kit.torus(0.7, 0.84, Mat.glow(Color("fff1c4"), 1.6)), Vector3(0, 0.04, 0.2))
	ring.scale = Vector3(1.0, 0.2, 1.0)
	_markers.append(ring)


func _beam_mesh(m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 1.0)
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Where a beam leaving `from` toward facing `d` stops: another mirror / the crystal on its line, else a wall.
func _beam_end(from: Vector3, d: int, targets: Array) -> Vector3:
	var dir: Vector3 = Puzzles.DIRS[d]
	var best := INF
	for t in targets:
		var tp: Vector3 = t
		var rel := tp - from
		rel.y = 0.0
		var along := rel.dot(dir)
		if along > 0.3 and (rel - dir * along).length() < 0.3 and along < best:
			best = along
	if best < INF:
		return from + dir * best
	var wall := 0.0
	match d:
		0: wall = from.z - ROOM.position.y
		1: wall = ROOM.end.x - from.x
		2: wall = ROOM.end.y - from.z
		3: wall = from.x - ROOM.position.x
	return from + dir * maxf(wall - 0.05, 0.1)


func _set_beam(mi: MeshInstance3D, a: Vector3, c: Vector3, on: bool) -> void:
	mi.visible = on and a.distance_to(c) > 0.05
	if not mi.visible:
		return
	var mid := (a + c) * 0.5
	var d := c - a
	mi.transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP).scaled_local(Vector3(1.0, 1.0, d.length())), mid)


func _apply(animate: bool) -> void:
	var up := Vector3.UP * BEAM_Y
	var pa: Vector3 = (Layout.LIGHTWELL["mirror_a"] as Vector3) + up
	var pb: Vector3 = (Layout.LIGHTWELL["mirror_b"] as Vector3) + up
	var pt: Vector3 = (Layout.LIGHTWELL["target"] as Vector3) + up
	for i in _heads.size():
		var dir: Vector3 = Puzzles.DIRS[int(mirrors[i])]
		var yaw := atan2(-dir.x, -dir.z)
		var h: Node3D = _heads[i]
		if animate and h.is_inside_tree():
			var cur := h.rotation.y
			var target := cur + wrapf(yaw - cur, -PI, PI)
			create_tween().tween_property(h, "rotation:y", target, 0.5).set_trans(Tween.TRANS_BACK)
		else:
			h.rotation.y = yaw
	var path := beam()
	var hits: Array = path["hits"]
	var end_a := _beam_end(pa, int(mirrors[0]), [pb])
	_set_beam(_beam_a, pa, end_a, true)
	var end_b := _beam_end(pb, int(mirrors[1]), [pt, pa])
	_set_beam(_beam_b, pb, end_b, hits.has("b"))
	_crystal_glow.visible = solved
	_crystal_light.visible = solved
	_warm.visible = solved
	var hv := bool(Settings.get_value("high_visibility_cues"))
	for m in _markers:
		(m as Node3D).visible = hv and not solved


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply(false)
