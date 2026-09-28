extends Node3D
## The Lanternwake cache at the end of an expedition route (module D2): a small ribboned festival crate with
## a warm glow under its lid. Interactable through the shared Reach interactable (group "interactable",
## layer-16 area, high-visibility marker when that setting is on): "Open the harvest crate". The handler
## (the runner's open_cache -> Expeditions.complete) pays the run once; play_open() lifts the lid and folds
## the crate away. No collision (it never blocks a path). Not an enemy, not a container that keeps items.
##   var c = Cache.new(); c.setup({"name": "the harvest crate", "handler": Callable(runner, "open_cache")})

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")
const Interactable := preload("res://src/world/reach/reach_interactable.gd")
const Data := preload("res://data/expeditions.gd")

var cache_name: String = "the cache"
var handler: Callable
var interactable: Node3D
var lid: Node3D
var opened := false


func setup(p: Dictionary) -> void:
	cache_name = String(p.get("name", cache_name))
	if p.has("handler"):
		handler = p["handler"]


func _ready() -> void:
	var wood := Mat.outlined(Mat.toon(Palette.WOOD), 0.02)
	var dark := Mat.toon(Palette.WOOD_DARK)
	Kit.add(self, Kit.box(Vector3(0.9, 0.5, 0.6), wood), Vector3(0, 0.25, 0))
	Kit.add(self, Kit.box(Vector3(0.94, 0.08, 0.64), dark), Vector3(0, 0.08, 0))
	Kit.add(self, Kit.box(Vector3(0.1, 0.52, 0.64), Mat.toon(Palette.CLOTH_RED)), Vector3(0, 0.26, 0))
	Kit.add(self, Kit.sphere(0.12, Mat.glow(Palette.LANTERN_GLOW, 1.8), 8, 12), Vector3(0, 0.5, 0))
	lid = Node3D.new()
	lid.name = "Lid"
	add_child(lid)
	lid.position = Vector3(0, 0.5, -0.3)
	Kit.add(lid, Kit.box(Vector3(0.94, 0.1, 0.64), wood), Vector3(0, 0.05, 0.3))
	Kit.add(lid, Kit.box(Vector3(0.1, 0.11, 0.66), Mat.toon(Palette.CLOTH_RED)), Vector3(0, 0.06, 0.3))
	Kit.add(lid, Kit.sphere(0.07, Mat.toon(Palette.FLOWER_YELLOW)), Vector3(0, 0.14, 0.3))
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	interactable = Interactable.new()
	interactable.name = "Interact"
	interactable.setup({"text": String(Data.TEXT["cache_prompt"]).format({"cache": cache_name}),
		"size": Vector3(1.2, 1.0, 1.0), "offset": Vector3(0, 0.5, 0), "handler": Callable(self, "_on_open"), "marker_y": 1.4})
	add_child(interactable)


func get_interaction(player: Node = null) -> Dictionary:
	return interactable.get_interaction(player) if interactable != null and not opened else {}


func interact(player: Node = null) -> void:
	if interactable != null and not opened:
		interactable.interact(player)


func _on_open(player: Node) -> void:
	if opened or not handler.is_valid():
		return
	handler.call(player)


## Lifts the lid, then folds the crate away (called by the runner once the rewards are paid).
func play_open() -> void:
	if opened:
		return
	opened = true
	if interactable != null and interactable.has_method("set_active"):
		interactable.call("set_active", false)
	Audio.play_3d("chest_open", global_position if is_inside_tree() else position, -4.0)
	if not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", deg_to_rad(-100.0), 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.2)
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
