extends Node3D
## A Moonveil rest point: a velvet-draped side table with a five-branch candelabrum (spec §1: the manor
## saves "at its candles"). Resting makes it the manor's return point (Game.set_respawn -> the per-area
## respawn memory), makes Continue resume here, and saves. The first rest lights all five candles
## (flag mm_cp_<spawn>). Interaction contract: group "interactable" + a layer-16 sphere; group "checkpoint".
##   setup({"area": "moonveil_manor", "spawn": "manor_ballroom"})

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const VELVET := Color("7a2f52")
const GOLD := Color("d9b25a")
const WAX := Color("f7ecd8")
const FLAME := Color("ffc562")

var area_name: String = "moonveil_manor"
var spawn_id: String = ""
var save_enabled := true           # tests switch saving off
var rests: int = 0
var _flames: Array = []
var _light: OmniLight3D


func setup(params: Dictionary) -> void:
	area_name = String(params.get("area", area_name))
	spawn_id = String(params.get("spawn", spawn_id))


func _ready() -> void:
	name = "RestPoint_" + spawn_id
	add_to_group("interactable")
	add_to_group("checkpoint")
	_build()
	_apply(is_lit())


func flag_name() -> String:
	return "mm_cp_" + spawn_id


func is_lit() -> bool:
	return bool(GameState.get_flag(flag_name()))


func get_interaction(_player: Node = null) -> Dictionary:
	return {"text": "Rest by the candles (save)", "enabled": true}


func interact(_player: Node = null) -> void:
	if area_name == "" or spawn_id == "":
		return
	var first := not is_lit()
	if first:
		GameState.set_flag(flag_name(), true)
		_apply(true)
		Audio.play_3d("checkpoint_light", global_position + Vector3(0, 1.3, 0), -2.0)
		Events.caption.emit("[five little candles catch, one after another]")
	rests += 1
	Game.set_respawn(area_name, spawn_id)
	GameState.player["spawn"] = spawn_id      # Continue resumes here
	var ok := true
	if save_enabled:
		ok = SaveSystem.save_game()
	if first:
		Events.notify.emit("Candles lit - progress saved" if ok else "Candles lit (saving failed)", "success" if ok else "warn")
	else:
		Events.notify.emit("Rested - progress saved" if ok else "Rested (saving failed)", "success" if ok else "warn")


func _apply(on: bool) -> void:
	for i in _flames.size():
		(_flames[i] as Node3D).visible = on or i == 2
	if _light != null:
		_light.light_energy = 1.1 if on else 0.45


func _build() -> void:
	var velvet := Mat.outlined(Mat.toon(VELVET, {"rim": 0.35}), 0.014)
	var gold := Mat.toon(GOLD, {"rim": 0.5, "specular": 0.3})
	var wood := Mat.toon(Color("5a3a2e"))
	Kit.add(self, Kit.cylinder(0.42, 0.46, 0.08, wood, 16), Vector3(0, 0.78, 0))
	Kit.add(self, Kit.cylinder(0.44, 0.52, 0.72, velvet, 16), Vector3(0, 0.38, 0))
	for k in 8:
		var a := TAU * float(k) / 8.0
		Kit.add(self, Kit.sphere(0.05, gold, 6, 8), Vector3(cos(a) * 0.5, 0.08, sin(a) * 0.5))
	Kit.add(self, Kit.cylinder(0.12, 0.16, 0.06, gold, 12), Vector3(0, 0.85, 0))
	Kit.add(self, Kit.cylinder(0.035, 0.045, 0.5, gold, 8), Vector3(0, 1.1, 0))
	Kit.add(self, Kit.box(Vector3(0.7, 0.04, 0.04), gold), Vector3(0, 1.3, 0))
	Kit.add(self, Kit.box(Vector3(0.04, 0.04, 0.7), gold), Vector3(0, 1.3, 0))
	var wax := Mat.toon(WAX, {"rim": 0.25})
	var glow := Mat.glow(FLAME, 3.0)
	var spots := [Vector3(-0.33, 1.32, 0), Vector3(0.33, 1.32, 0), Vector3(0, 1.36, 0), Vector3(0, 1.32, -0.33), Vector3(0, 1.32, 0.33)]
	for p in spots:
		var pp: Vector3 = p
		var tall := 0.3 if pp == Vector3(0, 1.36, 0) else 0.2
		Kit.add(self, Kit.cylinder(0.035, 0.04, tall, wax, 8), pp + Vector3.UP * tall * 0.5)
		var f := Kit.sphere(0.04, glow, 6, 8)
		Kit.add(self, f, pp + Vector3.UP * (tall + 0.05), Vector3.ZERO, Vector3(1.0, 1.9, 1.0))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.append(f)
	_light = OmniLight3D.new()
	_light.name = "RestLight"
	_light.light_color = FLAME
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 26.0
	_light.distance_fade_length = 8.0
	_light.position = Vector3(0, 1.7, 0)
	add_child(_light)
	var body := StaticBody3D.new()
	body.name = "TableBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 0.85
	cs.shape = cyl
	cs.position = Vector3(0, 0.425, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	ics.shape = sph
	ics.position = Vector3(0, 1.0, 0)
	ib.add_child(ics)
	add_child(ib)
