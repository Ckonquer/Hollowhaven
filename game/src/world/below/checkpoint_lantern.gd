extends Node3D
## Checkpoint lantern (group "checkpoint", interactable "Light the lantern").
## Lighting it: Game.set_respawn("below", spawn), saves the game, shows "Lantern lit - progress saved",
## and it becomes a light source + safe zone. The lit state persists via GameState flag "cp_lit_<id>"
## and is restored on load. A lit lantern can be used again to save.
##   var cp = CheckpointLantern.new(); cp.setup({"id": "office", "spawn": "cp_office", "zone": "mine"})

signal lit_changed(checkpoint_id: String, lit: bool)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const IRON := Color("3b3238")
const WOOD := Color("7a5236")

var checkpoint_id: String = "landing"
var spawn_id: String = "cp_landing"
var zone: String = "mine"
var light_radius: float = 6.5          # read by combat.light_at
var light_strength: float = 1.0
var lit: bool = false
var save_enabled: bool = true          # tests can turn saving off

var _light: OmniLight3D
var _flame: Node3D
var _ember: MeshInstance3D
var _glass: MeshInstance3D
var _t: float = 0.0
var _tween: Tween


func setup(p: Dictionary) -> void:
	checkpoint_id = String(p.get("id", checkpoint_id))
	spawn_id = String(p.get("spawn", spawn_id))
	zone = String(p.get("zone", zone))


static func flag_name(id: String) -> String:
	return "cp_lit_" + id


func _ready() -> void:
	add_to_group("checkpoint")
	add_to_group("interactable")
	_build()
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.2, 2.2, 1.2)
	cs.shape = sh
	cs.position = Vector3(0, 1.1, 0)
	area.add_child(cs)
	add_child(area)
	# Solid post
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var bcs := CollisionShape3D.new()
	var bsh := CylinderShape3D.new()
	bsh.radius = 0.22
	bsh.height = 2.0
	bcs.shape = bsh
	bcs.position = Vector3(0, 1.0, 0)
	body.add_child(bcs)
	add_child(body)
	_apply_lit(bool(GameState.get_flag(flag_name(checkpoint_id))), false)


func _build() -> void:
	var wood := Mat.outlined(Mat.toon(WOOD), 0.02)
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.4}), 0.015)
	var stone := Mat.toon(Palette.STONE_DARK.darkened(0.2))
	Kit.add(self, Kit.blob(0.42, stone, 5, 0.2, 0.45), Vector3(0, 0.08, 0))
	Kit.add(self, Kit.cylinder(0.11, 0.14, 2.0, wood, 8), Vector3(0, 1.0, 0))
	Kit.add(self, Kit.box(Vector3(0.12, 0.12, 0.62), wood), Vector3(0, 1.95, 0.24))
	Kit.add(self, Kit.box(Vector3(0.07, 0.4, 0.07), wood), Vector3(0, 1.72, 0.13), Vector3(-40, 0, 0))
	var lantern := Node3D.new()
	add_child(lantern)
	lantern.position = Vector3(0, 1.36, 0.5)
	Kit.add(self, Kit.cylinder(0.012, 0.012, 0.18, iron, 6), Vector3(0, 1.83, 0.5))
	Kit.add(lantern, Kit.cylinder(0.17, 0.2, 0.07, iron, 12), Vector3(0, 0.0, 0))
	Kit.add(lantern, Kit.cone(0.21, 0.16, iron, 12), Vector3(0, 0.45, 0))
	Kit.add(lantern, Kit.torus(0.025, 0.06, iron), Vector3(0, 0.56, 0), Vector3(90, 0, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		Kit.add(lantern, Kit.box(Vector3(0.03, 0.38, 0.03), iron), Vector3(cos(a) * 0.15, 0.21, sin(a) * 0.15))
	_glass = Kit.add(lantern, Kit.cylinder(0.14, 0.14, 0.36, Mat.transparent(Color(1.0, 0.85, 0.6, 0.18), true), 12), Vector3(0, 0.21, 0))
	_ember = Kit.add(lantern, Kit.sphere(0.045, Mat.glow(Color("ff7a3c"), 1.6), 6, 8), Vector3(0, 0.1, 0))
	_flame = Node3D.new()
	lantern.add_child(_flame)
	_flame.position = Vector3(0, 0.17, 0)
	Kit.add(_flame, Kit.sphere(0.07, Mat.glow(Palette.LANTERN_GLOW, 3.2), 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.5, 1.0))
	Kit.add(_flame, Kit.sphere(0.035, Mat.glow(Color("fff4d6"), 4.0), 6, 8), Vector3(0, -0.02, 0))
	_light = OmniLight3D.new()
	_light.light_color = Palette.LANTERN_GLOW
	_light.omni_range = 8.5
	_light.omni_attenuation = 1.0
	_light.shadow_enabled = true
	_light.shadow_bias = 0.08
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 36.0
	_light.distance_fade_length = 10.0
	_light.distance_fade_shadow = 20.0
	_light.light_volumetric_fog_energy = 0.45
	_light.light_specular = 0.3
	lantern.add_child(_light)
	_light.position = Vector3(0, 0.25, 0.05)


func _apply_lit(on: bool, animate: bool) -> void:
	lit = on
	_flame.visible = on
	_ember.visible = not on
	if on:
		add_to_group("light_source")
	elif is_in_group("light_source"):
		remove_from_group("light_source")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and on:
		_light.visible = true
		_light.light_energy = 0.0
		_flame.scale = Vector3.ONE * 0.2
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_light, "light_energy", 1.9, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_flame, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_light.visible = on
		_light.light_energy = 1.9 if on else 0.0
		_flame.scale = Vector3.ONE
	set_process(on)
	lit_changed.emit(checkpoint_id, on)


func _process(delta: float) -> void:
	_t += delta
	if _tween != null and _tween.is_running():
		return
	_light.light_energy = 1.9 * (1.0 + sin(_t * 6.1) * 0.03 + sin(_t * 11.3 + 0.7) * 0.02)


func is_light_active() -> bool:
	return lit


func get_interaction(_player: Node = null) -> Dictionary:
	if not lit:
		return {"text": "Light the lantern", "enabled": true}
	return {"text": "Rest by the lantern (save)", "enabled": true}


func interact(_player: Node = null) -> void:
	var first := not lit
	if first:
		GameState.set_flag(flag_name(checkpoint_id), true)
		_apply_lit(true, true)
		Audio.play_3d("checkpoint_light", global_position + Vector3(0, 1.4, 0), -2.0)
	Game.set_respawn("below", spawn_id)
	GameState.player["spawn"] = spawn_id     # Continue resumes at this lantern
	var ok := true
	if save_enabled:
		ok = SaveSystem.save_game()
	if first:
		Events.notify.emit("Lantern lit - progress saved" if ok else "Lantern lit (saving failed)", "success" if ok else "warn")
	else:
		Events.notify.emit("Progress saved" if ok else "Saving failed", "success" if ok else "warn")
