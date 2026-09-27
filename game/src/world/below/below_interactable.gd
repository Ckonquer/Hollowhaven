extends Node3D
## Generic interactable for The Below (duck-typed interaction contract).
## Owns an Area3D on layer 16 so the player's probe can find it.
##   var it = Interactable.new()
##   it.setup({"text": "Read the note", "size": Vector3(1, 1, 1), "handler": Callable(self, "_on_note"),
##             "text_func": Callable(self, "_note_text"), "accent": true})
## handler(player) runs on interact. text_func() -> Dictionary overrides get_interaction when valid
## (return {} to hide the prompt). accent adds a small emissive marker so it stays readable in the dark.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var text: String = "Inspect"
var enabled: bool = true
var size: Vector3 = Vector3(1.0, 1.2, 1.0)
var offset: Vector3 = Vector3(0.0, 0.6, 0.0)
var handler: Callable
var text_func: Callable
var accent: bool = false
var accent_color: Color = Palette.LANTERN_GLOW
var interact_id: String = ""

var _area: Area3D
var _accent_node: Node3D
var _t: float = 0.0


func setup(p: Dictionary) -> void:
	text = String(p.get("text", text))
	enabled = bool(p.get("enabled", enabled))
	size = p.get("size", size)
	offset = p.get("offset", Vector3(0.0, size.y * 0.5, 0.0))
	if p.has("handler"):
		handler = p["handler"]
	if p.has("text_func"):
		text_func = p["text_func"]
	accent = bool(p.get("accent", accent))
	accent_color = p.get("accent_color", accent_color)
	interact_id = String(p.get("id", interact_id))


func _ready() -> void:
	add_to_group("interactable")
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
	if accent:
		_accent_node = Kit.add(self, Kit.sphere(0.045, Mat.glow(accent_color, 2.5), 6, 8), offset + Vector3(0, size.y * 0.5 * 0.2, 0))
	set_process(accent)


func _process(delta: float) -> void:
	_t += delta
	if _accent_node != null:
		_accent_node.scale = Vector3.ONE * (0.8 + 0.25 * sin(_t * 2.6))


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
	if d.is_empty() or not bool(d.get("enabled", true)):
		return
	if handler.is_valid():
		handler.call(player)


## Removes the prompt and the probe collider (e.g. after a one-time use).
func disable_interaction() -> void:
	remove_from_group("interactable")
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
		_area = null
	if _accent_node != null:
		_accent_node.visible = false
	set_process(false)


func set_accent_visible(v: bool) -> void:
	if _accent_node != null:
		_accent_node.visible = v
