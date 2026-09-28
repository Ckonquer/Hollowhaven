extends Node3D
## Generic interactable for Hallowmere Reach set pieces (boards, notes, mirror, signs, plaques).
## Duck-typed interaction contract: group "interactable" + an Area3D on layer 16 in this subtree.
##   var it = ReachInteractable.new()
##   it.setup({"text": "Read the board", "size": Vector3(1.6, 2.0, 0.8), "offset": Vector3(0, 1, 0),
##             "handler": Callable(self, "_on_read"), "text_func": Callable(self, "_prompt"), "marker_y": 2.4})
## handler(player) runs on interact; text_func() -> Dictionary overrides the prompt ({} hides it).
## High-visibility cues (Settings "high_visibility_cues"): a bold, outlined, gently bobbing diamond marker
## floats above it (shape + outline, never colour alone); it follows the setting live.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")

var text: String = "Inspect"
var enabled: bool = true
var size: Vector3 = Vector3(1.0, 1.2, 1.0)
var offset: Vector3 = Vector3(0.0, 0.6, 0.0)
var handler: Callable
var text_func: Callable
var marker_y: float = 2.2
var interact_id: String = ""

var _area: Area3D
var _marker: Node3D
var _t := 0.0

static var _marker_mesh: Mesh = null


func setup(p: Dictionary) -> void:
	text = String(p.get("text", text))
	enabled = bool(p.get("enabled", enabled))
	size = p.get("size", size)
	offset = p.get("offset", Vector3(0.0, size.y * 0.5, 0.0))
	if p.has("handler"):
		handler = p["handler"]
	if p.has("text_func"):
		text_func = p["text_func"]
	marker_y = float(p.get("marker_y", offset.y + size.y * 0.5 + 0.6))
	interact_id = String(p.get("id", interact_id))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("reach_interactable")
	_area = Area3D.new()
	_area.name = "InteractArea"
	_area.collision_layer = 16
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
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	_apply_marker()


func set_active(on: bool) -> void:
	if _area != null:
		_area.collision_layer = 16 if on else 0
	if on and not is_in_group("interactable"):
		add_to_group("interactable")
	elif not on and is_in_group("interactable"):
		remove_from_group("interactable")
	_apply_marker()


func is_active() -> bool:
	return _area != null and _area.collision_layer == 16


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply_marker()


static func marker_mesh() -> Mesh:
	if _marker_mesh == null:
		var p := PrismMesh.new()
		p.size = Vector3(0.34, 0.3, 0.12)
		_marker_mesh = p
	return _marker_mesh


## A bold high-visibility marker (two stacked prisms = a diamond), shared by other Reach nodes.
static func make_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "HiVisMarker"
	var mat := Mat.outlined(Mat.glow(Color("fff1c8"), 1.6), 0.03, Color(0.12, 0.08, 0.1))
	var up := MeshInstance3D.new()
	up.mesh = marker_mesh()
	up.material_override = mat
	up.position = Vector3(0, 0.15, 0)
	up.rotation = Vector3(0, 0, PI)
	up.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(up)
	var dn := MeshInstance3D.new()
	dn.mesh = marker_mesh()
	dn.material_override = mat
	dn.position = Vector3(0, 0.45, 0)
	dn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dn)
	return root


static func hi_vis_on() -> bool:
	return bool(Settings.get_value("high_visibility_cues"))


func _apply_marker() -> void:
	var want := hi_vis_on() and is_active()
	if want and _marker == null:
		_marker = make_marker()
		add_child(_marker)
		_marker.position = Vector3(offset.x, marker_y, offset.z)
	if _marker != null:
		_marker.visible = want
	set_process(want)


func _process(delta: float) -> void:
	_t += delta
	if _marker != null:
		_marker.position.y = marker_y + sin(_t * 2.0) * 0.08
		_marker.rotation.y = _t * 0.9


func get_interaction(_player: Node = null) -> Dictionary:
	if text_func.is_valid():
		var d: Variant = text_func.call()
		if d is Dictionary:
			return d
	if text == "":
		return {}
	return {"text": text, "enabled": enabled}


func interact(player: Node = null) -> void:
	var d := get_interaction(player)
	if d.is_empty():
		return
	if not bool(d.get("enabled", true)):
		var reason := String(d.get("reason", ""))
		if reason != "":
			Events.notify.emit(reason, "info")
		return
	if handler.is_valid():
		handler.call(player)
