extends Node3D
## The old mine lift: a cage between the Heartseed Chamber and the Mine Landing. It only works after
## the Weaver is defeated (flag "weaver_defeated"): its winch is choked with silk / pale roots until then.
## Riding calls area.ride_lift(target_spawn) (fade, lift_move sound, teleport; see below_world.gd).
## role "chamber": "Ride the lift up" -> lift_bottom.  role "landing": "Ride the lift down" -> lift_chamber.
## The node's local -Z faces out of the cage (toward the room).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var role: String = "chamber"
var target_spawn: String = "lift_bottom"
var area: Node = null

var _wrap: Node3D
var _lever: Node3D
var _lamp_mat_on: Material
var _signal_light: OmniLight3D
var _signal_bulb: MeshInstance3D


## Flag that frees the winch (the Below: "weaver_defeated"). Other lifts pass their own.
var requires_flag: String = "weaver_defeated"


func setup(p: Dictionary) -> void:
	requires_flag = String(p.get("requires_flag", requires_flag))
	role = String(p.get("role", role))
	target_spawn = String(p.get("target", "lift_bottom" if role == "chamber" else "lift_chamber"))
	area = p.get("area", null)


func usable() -> bool:
	return requires_flag == "" or bool(GameState.get_flag(requires_flag))


func _ready() -> void:
	add_to_group("interactable")
	_build()
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 2.4, 1.2)
	cs.shape = sh
	cs.position = Vector3(0, 1.2, -1.0)
	a.add_child(cs)
	add_child(a)
	Events.flag_set.connect(_on_flag)
	Events.settings_changed.connect(_on_settings_changed)
	_refresh()


func _on_flag(flag: String, _v: Variant) -> void:
	if flag == requires_flag:
		_refresh()


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia":
		_build_wrap()
		_refresh()


func _build() -> void:
	var iron := Mat.outlined(Mat.toon(Color("4a4048"), {"rim": 0.45}), 0.018)
	var wood := Mat.outlined(Mat.toon(Color("7a5236")), 0.02)
	var plank := Mat.toon(Color("8e6340"))
	# Cage: floor, four corner posts, bars on three sides, roof with a pulley wheel
	Kit.add(self, Kit.box(Vector3(2.2, 0.12, 2.2), plank), Vector3(0, 0.06, 0.4))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Kit.add(self, Kit.box(Vector3(0.12, 2.6, 0.12), wood), Vector3(sx * 1.05, 1.3, 0.4 + sz * 1.05))
	for i in 7:
		var x := -0.9 + float(i) * 0.3
		Kit.add(self, Kit.cylinder(0.025, 0.025, 2.4, iron, 6), Vector3(x, 1.25, 1.45))
	for side in [-1.0, 1.0]:
		for i in 6:
			var z := -0.45 + float(i) * 0.3
			Kit.add(self, Kit.cylinder(0.025, 0.025, 2.4, iron, 6), Vector3(side * 1.05, 1.25, 0.4 + z))
	Kit.add(self, Kit.box(Vector3(2.3, 0.14, 2.3), wood), Vector3(0, 2.62, 0.4))
	Kit.add(self, Kit.torus(0.28, 0.4, iron), Vector3(0, 3.1, 0.4), Vector3(0, 0, 90))
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.cylinder(0.03, 0.03, 6.0, iron, 6), Vector3(sx * 0.18, 5.9, 0.4))
	# Lever post outside the cage
	var post := Node3D.new()
	add_child(post)
	post.position = Vector3(1.35, 0, -0.55)
	Kit.add(post, Kit.box(Vector3(0.3, 1.0, 0.3), wood), Vector3(0, 0.5, 0))
	_lever = Node3D.new()
	post.add_child(_lever)
	_lever.position = Vector3(0, 1.0, 0)
	_lever.rotation.x = -0.6
	Kit.add(_lever, Kit.cylinder(0.03, 0.03, 0.6, iron, 6), Vector3(0, 0.3, 0))
	Kit.add(_lever, Kit.sphere(0.07, Mat.outlined(Mat.toon(Color("c84b3c")), 0.01), 6, 8), Vector3(0, 0.62, 0))
	# Signal lamp: dark while stuck, warm when the lift works
	_signal_bulb = Kit.sphere(0.08, Mat.toon(Color("3a302c")), 8, 10)
	post.add_child(_signal_bulb)
	_signal_bulb.position = Vector3(0, 1.15, 0.12)
	_lamp_mat_on = Mat.glow(Palette.LANTERN_GLOW, 2.5)
	_signal_light = OmniLight3D.new()
	_signal_light.light_color = Palette.LANTERN_GLOW
	_signal_light.light_energy = 0.9
	_signal_light.omni_range = 3.5
	_signal_light.distance_fade_enabled = true
	_signal_light.distance_fade_begin = 30.0
	_signal_light.distance_fade_length = 6.0
	post.add_child(_signal_light)
	_signal_light.position = Vector3(0, 1.2, -0.2)
	# Solid cage walls (back and sides) so nobody walks through the bars
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	for spec in [[Vector3(0, 1.3, 1.5), Vector3(2.3, 2.6, 0.12)], [Vector3(-1.1, 1.3, 0.4), Vector3(0.12, 2.6, 2.3)], [Vector3(1.1, 1.3, 0.4), Vector3(0.12, 2.6, 2.3)]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = spec[1]
		cs.shape = sh
		cs.position = spec[0]
		body.add_child(cs)
	var pcs := CollisionShape3D.new()
	var psh := BoxShape3D.new()
	psh.size = Vector3(0.3, 1.0, 0.3)
	pcs.shape = psh
	pcs.position = Vector3(1.35, 0.5, -0.55)
	body.add_child(pcs)
	add_child(body)
	_build_wrap()


## Silk (or pale roots) choking the winch until the Weaver is gone.
func _build_wrap() -> void:
	if _wrap != null:
		_wrap.queue_free()
	_wrap = Node3D.new()
	_wrap.name = "Wrap"
	add_child(_wrap)
	if role != "chamber":
		return
	var arachno := bool(Settings.get_value("arachnophobia"))
	var group := "below_root" if arachno else "below_web"
	var mat: Material
	if arachno:
		mat = Mat.outlined(Mat.toon(Color("8a7560"), {"rim": 0.4}), 0.015)
	else:
		mat = Mat.toon(Palette.SILK_WEB, {"rim": 0.7, "emission": Palette.SILK_WEB, "emission_energy": 0.2})
	for i in 6:
		var y := 2.3 + float(i) * 0.3
		var t := Kit.torus(0.5 - float(i) * 0.03, 0.56 - float(i) * 0.03, mat)
		_wrap.add_child(t)
		t.position = Vector3(0, y, 0.4)
		t.rotation = Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
		t.add_to_group(group)
	var lump := Kit.blob(0.45, mat, 77 if arachno else 78, 0.3, 0.8)
	_wrap.add_child(lump)
	lump.position = Vector3(0, 3.05, 0.4)
	lump.add_to_group(group)
	for i in 5:
		var s := Kit.cylinder(0.02 if not arachno else 0.05, 0.02 if not arachno else 0.07, 2.6, mat, 5)
		_wrap.add_child(s)
		s.position = Vector3(randf_range(-0.9, 0.9), 1.5, 0.4 + randf_range(-0.9, 0.9))
		s.rotation = Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		s.add_to_group(group)


func _refresh() -> void:
	var ok := usable()
	if _wrap != null:
		_wrap.visible = not ok
	_signal_light.visible = ok
	_signal_bulb.material_override = _lamp_mat_on if ok else Mat.toon(Color("3a302c"))
	_lever.rotation.x = 0.6 if ok else -0.6


func get_interaction(_player: Node = null) -> Dictionary:
	if usable():
		return {"text": "Ride the lift up" if role == "chamber" else "Ride the lift down", "enabled": true}
	if role == "chamber":
		var arachno := bool(Settings.get_value("arachnophobia"))
		return {"text": "The winch is choked with pale roots" if arachno else "The winch is choked with silk", "enabled": false}
	return {"text": "The lift cage is stuck far below", "enabled": false}


func interact(_player: Node = null) -> void:
	if not usable():
		return
	var a := area if area != null else get_tree().current_scene
	if a != null and a.has_method("ride_lift"):
		a.ride_lift(target_spawn)
