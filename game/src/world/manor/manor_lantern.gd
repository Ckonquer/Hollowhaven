extends Node3D
## The Moonveil lantern on the Conservatory Balcony (MP §11 step 7, spec §7.3). A tall ornate cage lantern
## with a crescent finial. Cold (grey-violet glass) until the Count's enchantment is broken
## (ch2_velour_defeated); then a small ember waits for Krystal; waking it sets ch2_manor_lamp_lit and
## NOTHING else - the Chapter Two quest layer then pays rw_ch2_manor (Manor Seal + tailoring patterns)
## exactly once through the reward ledger. The lit state is rebuilt from the flag on every load.
## Interaction contract: group "interactable" + a layer-16 sphere.
##   setup({"lit_flag": "ch2_manor_lamp_lit", "ready_flag": "ch2_velour_defeated"})

signal woken

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const IRON := Color("35283a")
const GOLD := Color("d9b25a")
const STONE := Color("b3a6b6")
const COLD := Color("8f86a8")
const WARM := Color("ffc463")

var lit_flag: String = "ch2_manor_lamp_lit"
var ready_flag: String = "ch2_velour_defeated"
var wakes: int = 0
var light_radius: float = 6.0          # light_source contract (only while lit)
var _glass_cold: MeshInstance3D
var _glass_warm: MeshInstance3D
var _ember: MeshInstance3D
var _light: OmniLight3D
var _halo: MeshInstance3D
var _beckon: MeshInstance3D
var _t := 0.0


func setup(params: Dictionary) -> void:
	lit_flag = String(params.get("lit_flag", lit_flag))
	ready_flag = String(params.get("ready_flag", ready_flag))


func _ready() -> void:
	name = "ManorLantern"
	add_to_group("interactable")
	add_to_group("mm_manor_lantern")
	add_to_group("light_source")
	_build()
	refresh()
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func is_light_active() -> bool:
	return is_lit()


func is_lit() -> bool:
	return bool(GameState.get_flag(lit_flag))


func is_ready_to_wake() -> bool:
	return bool(GameState.get_flag(ready_flag))


## Re-reads the flags (after the enchantment breaks while Krystal is in the manor).
func refresh() -> void:
	var lit := is_lit()
	var ready := is_ready_to_wake()
	_glass_cold.visible = not lit
	_glass_warm.visible = lit
	_ember.visible = ready and not lit
	_light.visible = lit or ready
	_light.light_energy = 2.4 if lit else 0.35
	_light.omni_range = 9.0 if lit else 2.2
	_halo.visible = lit
	if _beckon != null:
		_beckon.visible = ready and not lit and bool(Settings.get_value("high_visibility_cues"))
	set_process(lit or ready)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		refresh()


## high_visibility_cues: a bold ring round the pedestal while the lantern waits to be woken.
func beckon_visible() -> bool:
	return _beckon != null and _beckon.visible


func get_interaction(_player: Node = null) -> Dictionary:
	if is_lit():
		return {"text": "The Moonveil lantern burns warm and gold", "enabled": false}
	if not is_ready_to_wake():
		return {"text": "Wake the Moonveil lantern", "enabled": false,
			"reason": "Its wick is cold. Something in the Gallery is still holding the house's light."}
	return {"text": "Wake the Moonveil lantern", "enabled": true}


func interact(_player: Node = null) -> void:
	wake()


## Lights the lantern once. Returns true if this call lit it.
func wake() -> bool:
	if is_lit() or not is_ready_to_wake():
		return false
	GameState.set_flag(lit_flag, true)          # the only thing the manor sets; the quest layer pays the seal
	wakes += 1
	refresh()
	Audio.play_3d("ward_restore", global_position + Vector3.UP * 2.0, -4.0, 0.03, 40.0)
	Events.caption.emit("[the Moonveil lantern catches, warm and gold]")
	Events.say.emit("", "The lantern wakes. Far off, over the treetops, the orchard and the quarry can see the manor keeping its promise.", 6.0)
	Events.screen_flash.emit(Color(1.0, 0.85, 0.55, 0.18), 0.6)
	GameState.request_quest_eval()
	woken.emit()
	return true


func _build() -> void:
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.35}), 0.014)
	var gold := Mat.toon(GOLD, {"rim": 0.55, "specular": 0.35})
	var stone := Mat.outlined(Mat.toon(STONE, {"noise": 0.12}), 0.014)
	# Pedestal.
	Kit.add(self, Kit.cylinder(0.7, 0.85, 0.3, stone, 16), Vector3(0, 0.15, 0))
	Kit.add(self, Kit.cylinder(0.42, 0.55, 0.9, stone, 12), Vector3(0, 0.75, 0))
	Kit.add(self, Kit.cylinder(0.62, 0.5, 0.18, stone, 16), Vector3(0, 1.29, 0))
	# Cage.
	var cy := 2.05
	Kit.add(self, Kit.cylinder(0.5, 0.42, 0.14, gold, 16), Vector3(0, 1.45, 0))
	for k in 6:
		var a := TAU * float(k) / 6.0
		Kit.add(self, Kit.cylinder(0.035, 0.035, 1.25, iron, 6), Vector3(cos(a) * 0.44, cy, sin(a) * 0.44))
	_glass_cold = Kit.cylinder(0.4, 0.4, 1.1, Mat.transparent(Color(COLD, 0.55), false), 12)
	Kit.add(self, _glass_cold, Vector3(0, cy, 0))
	_glass_warm = Kit.cylinder(0.4, 0.4, 1.1, Mat.glow(WARM, 1.6), 12)
	Kit.add(self, _glass_warm, Vector3(0, cy, 0))
	_glass_warm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ember = Kit.sphere(0.09, Mat.glow(Color("ff9a4a"), 2.4), 8, 10)
	Kit.add(self, _ember, Vector3(0, cy - 0.3, 0))
	_ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, Kit.cone(0.62, 0.55, iron, 12), Vector3(0, cy + 0.9, 0))
	Kit.add(self, Kit.cylinder(0.5, 0.5, 0.1, gold, 16), Vector3(0, cy + 0.64, 0))
	Kit.add(self, Kit.sphere(0.1, gold, 8, 10), Vector3(0, cy + 1.24, 0))
	# Crescent finial.
	Kit.add(self, Kit.cylinder(0.26, 0.26, 0.05, gold, 20), Vector3(0, cy + 1.55, 0), Vector3(90, 0, 0))
	Kit.add(self, Kit.cylinder(0.22, 0.22, 0.06, iron, 20), Vector3(0.1, cy + 1.6, 0.0), Vector3(90, 0, 0))
	_halo = Kit.sphere(0.9, Mat.transparent(Color(1.0, 0.8, 0.45, 0.12), true), 10, 14)
	Kit.add(self, _halo, Vector3(0, cy, 0))
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.name = "LanternLight"
	_light.light_color = WARM
	_light.shadow_enabled = false
	_light.position = Vector3(0, cy, 0)
	add_child(_light)
	_beckon = Kit.torus(1.0, 1.2, Mat.glow(Color("fff1c4"), 1.8))
	Kit.add(self, _beckon, Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1.0, 0.3, 1.0))
	_beckon.name = "BoldBeckon"
	_beckon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.name = "PedestalBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 3.2
	cs.shape = cyl
	cs.position = Vector3(0, 1.6, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.2
	ics.shape = sph
	ics.position = Vector3(0, 1.3, 0)
	ib.add_child(ics)
	add_child(ib)


func _process(delta: float) -> void:
	_t += delta
	if is_lit():
		_light.light_energy = 2.4 + sin(_t * 3.1) * 0.08
	elif _ember.visible:
		var s := 0.8 + 0.25 * absf(sin(_t * 1.8))
		_ember.scale = Vector3(s, s, s)
