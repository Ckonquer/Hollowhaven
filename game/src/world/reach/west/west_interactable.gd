extends Node3D
## Generic interactable for the Reach west districts (docs/ARCHITECTURE.md interaction contract): group
## "interactable" + an Area3D on layer 16 whose parent chain reaches this script.
##   var it: Node3D = WestInteractable.new()
##   it.setup({"id": "lever_junction", "text_func": Callable(self, "_lever_text"), "handler": Callable(self, "_pull"),
##             "size": Vector3(1.2, 1.6, 1.2), "marker": true, "marker_radius": 0.7})
## handler(player) runs on interact (only while the prompt is enabled). text_func() -> Dictionary overrides the
## static text ({} hides the prompt). marker = a bold glowing ring on the ground, shown only while the setting
## high_visibility_cues is on (never colour alone: it is a thick ring + gentle bob, readable in greyscale).

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const LAYER_INTERACT := 16
const MARKER_COLOR := Color("fff1b8")

var interact_id: String = ""
var text: String = "Inspect"
var enabled: bool = true
var size: Vector3 = Vector3(1.2, 1.6, 1.2)
var offset: Vector3 = Vector3(0.0, 0.8, 0.0)
var handler: Callable
var text_func: Callable
var marker: bool = false
var marker_radius: float = 0.7
var active: bool = true

var _area: Area3D
var _ring: MeshInstance3D
var _t: float = 0.0


func setup(p: Dictionary) -> void:
	interact_id = String(p.get("id", interact_id))
	text = String(p.get("text", text))
	enabled = bool(p.get("enabled", enabled))
	size = p.get("size", size)
	offset = p.get("offset", Vector3(0.0, size.y * 0.5, 0.0))
	if p.has("handler"):
		handler = p["handler"]
	if p.has("text_func"):
		text_func = p["text_func"]
	marker = bool(p.get("marker", marker))
	marker_radius = float(p.get("marker_radius", marker_radius))


func _ready() -> void:
	if interact_id != "":
		name = "Interact_" + interact_id
	_area = Area3D.new()
	_area.name = "InteractArea"
	_area.collision_layer = LAYER_INTERACT
	_area.collision_mask = 0
	_area.monitoring = false
	_area.monitorable = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = offset
	_area.add_child(cs)
	add_child(_area)
	if marker:
		var tm := TorusMesh.new()
		tm.inner_radius = marker_radius
		tm.outer_radius = marker_radius + 0.12
		tm.rings = 24
		tm.ring_segments = 6
		_ring = MeshInstance3D.new()
		_ring.name = "CueRing"
		_ring.mesh = tm
		_ring.material_override = Mat.glow(MARKER_COLOR, 1.6)
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.position = Vector3(0, 0.06, 0)
		_ring.scale = Vector3(1.0, 0.35, 1.0)
		add_child(_ring)
		if not Events.settings_changed.is_connected(_on_settings_changed):
			Events.settings_changed.connect(_on_settings_changed)
	else:
		set_process(false)          # no cue ring: nothing to animate
	set_active(active)


func _process(delta: float) -> void:
	_t += delta
	if _ring != null and _ring.visible:
		var s := 1.0 + 0.06 * sin(_t * 2.2)
		_ring.scale = Vector3(s, 0.35, s)


func get_interaction(_player: Node = null) -> Dictionary:
	if not active:
		return {}
	if text_func.is_valid():
		var d: Variant = text_func.call()
		if d is Dictionary:
			return d
	if text == "":
		return {}
	return {"text": text, "enabled": enabled}


func interact(player: Node = null) -> void:
	var d := get_interaction(player)
	if d.is_empty() or not bool(d.get("enabled", true)):
		return
	if handler.is_valid():
		handler.call(player)


## Turns the prompt (group + layer-16 collider) and its cue ring on or off.
func set_active(on: bool) -> void:
	active = on
	if on:
		add_to_group("interactable")
	elif is_in_group("interactable"):
		remove_from_group("interactable")
	if _area != null:
		_area.collision_layer = LAYER_INTERACT if on else 0
	_refresh_ring()


func is_cue_visible() -> bool:
	return _ring != null and _ring.visible


func _refresh_ring() -> void:
	if _ring == null:
		return
	_ring.visible = active and bool(Settings.get_value("high_visibility_cues"))
	set_process(_ring.visible)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" or key == "":
		_refresh_ring()
