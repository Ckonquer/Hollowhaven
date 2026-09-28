extends Node3D
## Small generic interactable for Moonveil Manor (notes, plaques, levers). Interaction contract: group
## "interactable" + a layer-16 sphere; the prompt and the action come from callables so the owner keeps
## all state (nothing is saved here).
##   var n = ManorInteractable.new()
##   n.setup({"id": "hall_card", "text": "Read the card", "radius": 0.9, "offset": Vector3(0, 1.0, 0),
##            "handler": Callable(self, "_read_card"), "text_func": Callable()})
## text_func (optional) returns the whole interaction Dictionary ({} hides the prompt);
## handler is called with no arguments. Optional "say": [speaker, text, seconds] shows a line on use.

signal used(interact_id: String)

var interact_id: String = ""
var text: String = "Look"
var radius: float = 0.9
var offset := Vector3(0.0, 1.0, 0.0)
var handler: Callable = Callable()
var text_func: Callable = Callable()
var enabled: bool = true
var uses: int = 0
var say_line: Array = []


func setup(params: Dictionary) -> void:
	var sl: Variant = params.get("say", null)
	if sl is Array and (sl as Array).size() >= 2:
		say_line = sl
	interact_id = String(params.get("id", interact_id))
	text = String(params.get("text", text))
	radius = float(params.get("radius", radius))
	offset = params.get("offset", offset)
	var h: Variant = params.get("handler", null)
	if h is Callable:
		handler = h
	var tf: Variant = params.get("text_func", null)
	if tf is Callable:
		text_func = tf


func _ready() -> void:
	if interact_id != "" and name.begins_with("@"):
		name = "Interact_" + interact_id
	add_to_group("interactable")
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	cs.position = offset
	ib.add_child(cs)
	add_child(ib)


func get_interaction(_player: Node = null) -> Dictionary:
	if text_func.is_valid():
		var r: Variant = text_func.call()
		return r if r is Dictionary else {}
	return {"text": text, "enabled": enabled}


func interact(_player: Node = null) -> void:
	var info := get_interaction(_player)
	if info.is_empty() or not bool(info.get("enabled", true)):
		return
	uses += 1
	if handler.is_valid():
		handler.call()
	if not say_line.is_empty():
		Events.say.emit(String(say_line[0]), String(say_line[1]), float(say_line[2]) if say_line.size() > 2 else 6.0)
	used.emit(interact_id)
