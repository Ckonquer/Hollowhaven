extends Node3D
## Moonveil doors and stairs that take Krystal somewhere else. Same contract as
## src/world/areas_ch2/area_exit.gd (group "area_exit", target_area / target_spawn / use_respawn,
## destination(), is_unlocked()), with manor visuals:
##   "grand"   the manor's front double door seen from the grounds (Reach) - plum leaves, gold studs,
##             crescent fanlight
##   "inner"   the same door from inside the Cloakroom
##   "stair"   the balcony's garden stair (iron arch, steps going down)
##   "servants" a small servants' door (in-house shortcut: target_area == this area -> fade + teleport)
## Local +Z is the front (where Krystal stands); the leaves sit 0.27 m behind the node origin.
##   setup({"text": "Step back outside", "target_area": "hallowmere_reach", "target_spawn": "manor_door",
##          "requires_flag": "", "locked_text": "", "style": "inner"})
## Travel to another area goes through Game.change_area (autosave + respawn rules). A same-area target
## (the servants' stair) fades, teleports Krystal and her follower, and fades back.

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const PLUM := Color("5b2a4e")
const PLUM_DARK := Color("3e1d38")
const GOLD := Color("d9b25a")
const STONE := Color("b9aab8")
const MOON := Color("bcd0ff")
const WARM := Color("ffc978")
const IRON := Color("3a2c3e")

var text: String = "Leave"
var target_area: String = ""
var target_spawn: String = ""
var requires_flag: String = ""
var locked_text: String = "It won't open."
var use_respawn: bool = false
var style: String = "inner"
var travels: int = 0             # completed uses (tests)
var _busy := false


func setup(params: Dictionary) -> void:
	text = String(params.get("text", text))
	target_area = String(params.get("target_area", target_area))
	target_spawn = String(params.get("target_spawn", target_spawn))
	requires_flag = String(params.get("requires_flag", requires_flag))
	locked_text = String(params.get("locked_text", locked_text))
	style = String(params.get("style", style))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("area_exit")
	_build()


func is_unlocked() -> bool:
	return requires_flag == "" or bool(GameState.get_flag(requires_flag))


func destination() -> Dictionary:
	return {"area": target_area, "spawn": target_spawn}


func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if not is_unlocked():
		return {"text": text, "enabled": false, "reason": locked_text}
	return {"text": text, "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if not is_unlocked():
		Events.notify.emit(locked_text, "info")
		return
	if target_area == "" or Game.mode != "playing":
		return
	_busy = true
	Audio.play_3d("door_creak", global_position + Vector3.UP, -6.0)
	travels += 1
	if target_area == Game.area_id:
		await _teleport_here(target_spawn)
	else:
		await Game.change_area(target_area, target_spawn)
	if is_instance_valid(self):
		_busy = false


## In-house shortcut: fade, move Krystal (and her follower), fade back.
func _teleport_here(spawn: String) -> void:
	var area: Node = Game.area
	if area == null or not is_instance_valid(area) or not area.has_method("get_spawn"):
		return
	Game.set_cutscene(true)
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("fade_out"):
		await Game.ui.fade_out(0.35)
	var xf: Transform3D = area.get_spawn(spawn)
	if Game.player != null and is_instance_valid(Game.player):
		Game.player.teleport(xf)
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c is Node and is_instance_valid(c) and (c as Node).has_method("teleport_near"):
			(c as Node).teleport_near(xf.origin)
	if is_inside_tree():
		await get_tree().create_timer(0.15).timeout
	if Game.ui != null and is_instance_valid(Game.ui) and Game.ui.has_method("fade_in"):
		await Game.ui.fade_in(0.5)
	Game.set_cutscene(false)


# --- Visuals ----------------------------------------------------------------------------------------------

func _build() -> void:
	match style:
		"grand":
			_build_double(2.6, 3.4, true)
		"inner":
			_build_double(2.2, 3.0, false)
		"stair":
			_build_stair()
		_:
			_build_servants()
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	ics.shape = sph
	ics.position = Vector3(0, 1.1, 0.25)
	ib.add_child(ics)
	add_child(ib)


func _block(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "DoorBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	body.add_child(cs)
	add_child(body)


func _build_double(w: float, h: float, exterior: bool) -> void:
	var leaf := Mat.outlined(Mat.toon(PLUM, {"rim": 0.3, "noise": 0.12}), 0.016)
	var dark := Mat.toon(PLUM_DARK)
	var gold := Mat.toon(GOLD, {"rim": 0.55, "specular": 0.35})
	var frame := Mat.outlined(Mat.toon(STONE if exterior else Color("6b4a3a"), {"noise": 0.1}), 0.014)
	var rect_h := h - w * 0.5
	var z := -0.27
	for sx in [-1.0, 1.0]:
		var cx := float(sx) * w * 0.25
		Kit.add(self, Kit.box(Vector3(w * 0.5 - 0.04, rect_h, 0.12), leaf), Vector3(cx, rect_h * 0.5, z))
		Kit.add(self, Kit.box(Vector3(w * 0.5 - 0.3, rect_h * 0.36, 0.04), dark), Vector3(cx, rect_h * 0.72, z + 0.07))
		Kit.add(self, Kit.box(Vector3(w * 0.5 - 0.3, rect_h * 0.36, 0.04), dark), Vector3(cx, rect_h * 0.28, z + 0.07))
		Kit.add(self, Kit.torus(0.07, 0.11, gold), Vector3(float(sx) * 0.2, rect_h * 0.5, z + 0.1), Vector3(90, 0, 0))
		for k in 4:
			Kit.add(self, Kit.sphere(0.035, gold, 6, 8), Vector3(cx + float(k % 2) * 0.3 - 0.15, 0.4 + floorf(float(k) * 0.5) * (rect_h - 0.8), z + 0.08))
	# Arched top: the fanlight (warm from outside, moonlit from inside) with a crescent bitten out.
	var fan := Kit.cylinder(w * 0.5, w * 0.5, 0.06, Mat.glow(WARM if exterior else MOON, 1.1), 24)
	Kit.add(self, fan, Vector3(0, rect_h, z - 0.02), Vector3(90, 0, 0))
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, Kit.cylinder(w * 0.36, w * 0.36, 0.07, dark, 24), Vector3(w * 0.14, rect_h + w * 0.06, z + 0.01), Vector3(90, 0, 0))
	Kit.add(self, Kit.box(Vector3(w + 0.1, 0.14, 0.16), gold), Vector3(0, rect_h, z + 0.02))
	# Frame: jambs + an arch ring.
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.3, rect_h + 0.1, 0.34), frame), Vector3(float(sx) * (w * 0.5 + 0.15), rect_h * 0.5, z))
	_arch(w * 0.5 + 0.15, rect_h, z, Vector3(0.3, 0.34, 0.34), frame)
	if exterior:
		# Door knocker bat + two lanterns flanking the door.
		Kit.add(self, Kit.sphere(0.12, gold, 8, 10), Vector3(0, rect_h * 0.62, z + 0.14))
		for sx in [-1.0, 1.0]:
			Kit.add(self, Kit.sphere(0.14, gold, 8, 10), Vector3(float(sx) * 0.16, rect_h * 0.66, z + 0.14), Vector3.ZERO, Vector3(1.6, 0.6, 0.4))
			var lp := Vector3(float(sx) * (w * 0.5 + 0.55), 2.3, z + 0.25)
			Kit.add(self, Kit.box(Vector3(0.05, 0.05, 0.3), Mat.toon(IRON)), lp + Vector3(0, 0.2, -0.12))
			Kit.add(self, Kit.cylinder(0.14, 0.16, 0.34, Mat.toon(IRON), 8), lp + Vector3(0, -0.02, 0))
			var g := Kit.cylinder(0.1, 0.1, 0.24, Mat.glow(WARM, 1.8), 8)
			Kit.add(self, g, lp)
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Kit.add(self, Kit.cone(0.18, 0.2, Mat.toon(IRON), 8), lp + Vector3(0, 0.26, 0))
	_block(Vector3(w + 0.2, h, 0.3), Vector3(0, h * 0.5, z - 0.1))


## Semicircular arch of little boxes (voussoirs) centred at (0, base_y) in the door plane z.
## size = (thickness across the ring, depth, unused).
func _arch(radius: float, base_y: float, z: float, size: Vector3, mat: Material) -> void:
	var n := 9
	var seg := PI * radius / float(n) * 1.15
	for i in n:
		var a := PI * (float(i) + 0.5) / float(n)
		var p := Vector3(cos(a) * radius, base_y + sin(a) * radius, z)
		Kit.add(self, Kit.box(Vector3(seg, size.x, size.y), mat), p, Vector3(0, 0, rad_to_deg(a) + 90.0))


func _build_servants() -> void:
	var wood := Mat.outlined(Mat.toon(Color("7a5236"), {"noise": 0.12}), 0.014)
	var dark := Mat.toon(Color("4e3322"))
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	var z := -0.27
	Kit.add(self, Kit.box(Vector3(1.2, 2.2, 0.1), wood), Vector3(0, 1.1, z))
	for k in 3:
		Kit.add(self, Kit.box(Vector3(1.0, 0.08, 0.04), dark), Vector3(0, 0.45 + float(k) * 0.65, z + 0.06))
	Kit.add(self, Kit.sphere(0.06, gold, 6, 8), Vector3(0.42, 1.05, z + 0.09))
	Kit.add(self, Kit.box(Vector3(1.45, 0.14, 0.2), dark), Vector3(0, 2.26, z))
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.12, 2.3, 0.2), dark), Vector3(float(sx) * 0.66, 1.15, z))
	# A little bell over the door (it rings for the servants' stair).
	Kit.add(self, Kit.cone(0.1, 0.14, gold, 10), Vector3(0.0, 2.52, z + 0.06))
	_block(Vector3(1.4, 2.3, 0.2), Vector3(0, 1.15, z - 0.08))


func _build_stair() -> void:
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.3}), 0.012)
	var stone := Mat.toon(STONE, {"noise": 0.12})
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	var z := -0.3
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.cylinder(0.07, 0.08, 2.6, iron, 8), Vector3(float(sx) * 0.85, 1.3, z))
		Kit.add(self, Kit.sphere(0.1, gold, 6, 8), Vector3(float(sx) * 0.85, 2.65, z))
	_arch(0.85, 2.6, z, Vector3(0.12, 0.12, 0.12), iron)
	Kit.add(self, Kit.cylinder(0.2, 0.2, 0.05, Mat.glow(WARM, 1.2), 12), Vector3(0, 3.35, z), Vector3(90, 0, 0))
	# Steps going down beyond the arch (visual only).
	for i in 6:
		var d := 0.55 + float(i) * 0.42
		Kit.add(self, Kit.box(Vector3(1.5, 0.3, 0.44), stone), Vector3(0, -0.18 - float(i) * 0.3, z - d))
	# The gap stays shut to the body; the stair is taken through the interaction.
	_block(Vector3(1.8, 3.0, 0.5), Vector3(0, 1.5, z - 0.25))
