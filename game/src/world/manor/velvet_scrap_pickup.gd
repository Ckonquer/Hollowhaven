extends Node3D
## One of the Count's three velvet scraps (MP §15 "The Count's Wardrobe"; data/sources.gd velvet_scrap
## "pickup"). Guaranteed, fixed, persistent: picking it up sets its flag FIRST (ch2_velvet_scrap_<n>, read by
## the optional goal opt_counts_wardrobe) and then gives one velvet_scrap (a key item: the pouch never drops
## it). With the flag already set the pickup is never built again. A soft sparkle marks it; with
## high_visibility_cues a bold beacon ring does too.
##   setup({"id": "mm_scrap_1", "flag": "ch2_velvet_scrap_1", "item": "velvet_scrap"})

signal collected(scrap_id: String)

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const VELVET := Color("9b3b5a")
const VELVET_DARK := Color("6e2440")
const GOLD := Color("e2bd5e")

var scrap_id: String = ""
var flag: String = ""
var item_id: String = "velvet_scrap"
var taken := false
var _t := 0.0
var _swatch: Node3D
var _sparkle: MeshInstance3D
var _beacon: MeshInstance3D


func setup(params: Dictionary) -> void:
	scrap_id = String(params.get("id", scrap_id))
	flag = String(params.get("flag", flag))
	item_id = String(params.get("item", item_id))


func _ready() -> void:
	name = "VelvetScrap_" + scrap_id
	add_to_group("interactable")
	add_to_group("mm_velvet_scrap")
	if flag != "" and bool(GameState.get_flag(flag)):
		taken = true
		queue_free()
		return
	_build()
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func get_interaction(_player: Node = null) -> Dictionary:
	if taken:
		return {}
	return {"text": "Pick up the velvet scrap", "enabled": true}


func interact(_player: Node = null) -> void:
	collect()


## Takes the scrap (once ever). Returns true if this call took it.
func collect() -> bool:
	if taken or (flag != "" and bool(GameState.get_flag(flag))):
		taken = true
		queue_free()
		return false
	taken = true
	if flag != "":
		GameState.set_flag(flag, true)          # committed first: a crash after this never duplicates it
	GameState.give_item(item_id, 1)
	Audio.play_3d("pickup", global_position, -4.0)
	var found := 0
	for f in ["ch2_velvet_scrap_1", "ch2_velvet_scrap_2", "ch2_velvet_scrap_3"]:
		if bool(GameState.get_flag(f)):
			found += 1
	Events.notify.emit("Velvet scrap found (%d of 3)" % found, "item")
	GameState.request_quest_eval()
	collected.emit(scrap_id)
	queue_free()
	return true


func _build() -> void:
	_swatch = Node3D.new()
	_swatch.name = "Swatch"
	add_child(_swatch)
	var velvet := Mat.outlined(Mat.toon(VELVET, {"rim": 0.6, "noise": 0.12}), 0.012)
	var dark := Mat.toon(VELVET_DARK, {"rim": 0.4})
	var gold := Mat.toon(GOLD, {"rim": 0.6, "specular": 0.4})
	Kit.add(_swatch, Kit.box(Vector3(0.34, 0.05, 0.26), velvet), Vector3(0, 0.03, 0), Vector3(0, 12, 3))
	Kit.add(_swatch, Kit.box(Vector3(0.3, 0.04, 0.22), dark), Vector3(0.02, 0.07, -0.01), Vector3(0, -8, -4))
	Kit.add(_swatch, Kit.sphere(0.1, velvet, 8, 10), Vector3(-0.1, 0.1, 0.05), Vector3.ZERO, Vector3(1.2, 0.5, 0.9))
	Kit.add(_swatch, Kit.box(Vector3(0.04, 0.03, 0.3), gold), Vector3(0.05, 0.1, 0), Vector3(0, 30, 0))
	Kit.add(_swatch, Kit.torus(0.04, 0.07, gold), Vector3(0.1, 0.12, 0.06), Vector3(70, 0, 0))
	_sparkle = Kit.sphere(0.05, Mat.glow(Color("fff0f6"), 3.0), 6, 8)
	Kit.add(self, _sparkle, Vector3(0.1, 0.3, 0))
	_sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon = Kit.torus(0.42, 0.5, Mat.glow(Color("fff4d0"), 1.8))
	Kit.add(self, _beacon, Vector3(0, 0.02, 0))
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = bool(Settings.get_value("high_visibility_cues"))
	var l := OmniLight3D.new()
	l.name = "Glint"
	l.light_color = Color("ff9ab8")
	l.light_energy = 0.5
	l.omni_range = 1.6
	l.shadow_enabled = false
	l.position = Vector3(0, 0.35, 0)
	add_child(l)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.55
	cs.shape = sph
	cs.position = Vector3(0, 0.15, 0)
	ib.add_child(cs)
	add_child(ib)


func _process(delta: float) -> void:
	_t += delta
	if _sparkle != null:
		var s := 0.6 + 0.4 * absf(sin(_t * 2.2))
		_sparkle.scale = Vector3(s, s, s)
		_sparkle.position = Vector3(0.1 + sin(_t * 1.3) * 0.08, 0.3 + sin(_t * 1.7) * 0.05, cos(_t * 1.3) * 0.08)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _beacon != null:
		_beacon.visible = bool(Settings.get_value("high_visibility_cues"))
