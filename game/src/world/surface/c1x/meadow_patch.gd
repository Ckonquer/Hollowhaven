extends RefCounted
## A Gardener's Afternoon (MP 7; spec 7.1; optional goal opt_gardeners_afternoon): a wild Sunflax patch and a
## Roseberry bush cluster in the Sunny Meadow (data/c1x_layout.gd SUNFLAX / ROSEBERRY). Renewable harvestable
## nodes (ids c1x_sunflax_<n> / c1x_roseberry_<n>) built from data/sources.gd NODES "sunflax_patch" /
## "roseberry_bush" (hand; drops include the seeds). The FIRST harvest there sets c1x_found_new_crops (objective
## flag) and grants the content bundle rw_c1x_gardener (a starter seed packet) once through the ledger. The goal's
## own reward and "c1x_grew_new_crop" belong to the optional log / farming module.
##   MeadowPatch.build(area)
## Patch node (group "c1x_meadow_patch"): mark_found() -> bool (true the first time), nodes: Array.

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")


static func build(area: Node3D) -> void:
	if area == null:
		return
	var parent := Common.sub_root(area, "MeadowPatch")
	var patch := Patch.new()
	patch.name = "Patch"
	parent.add_child(patch)
	for i in L.SUNFLAX.size():
		var d: Dictionary = L.SUNFLAX[i]
		var node := Common.harvest_node(L.SUNFLAX_KIND, String(d["id"]), Common.sunflax_visual(i % 3),
			{"hit_sound": "grass_pull", "fx": "grass", "verb": "Gather"}, "Wild Sunflax (regrowing)")
		patch.add_node(node, area, d["pos"], float(d.get("yaw_deg", 0.0)))
	for i in L.ROSEBERRY.size():
		var d: Dictionary = L.ROSEBERRY[i]
		var node := Common.harvest_node(L.ROSEBERRY_KIND, String(d["id"]), Common.roseberry_visual(i),
			{"hit_sound": "berry_pick", "fx": "berries", "verb": "Pick"}, "Roseberry Bush (regrowing)")
		patch.add_node(node, area, d["pos"], float(d.get("yaw_deg", 0.0)))


class Patch extends Node3D:
	const L := preload("res://data/c1x_layout.gd")
	const Common := preload("res://src/world/surface/c1x/common.gd")
	const MESSAGE := "Wild sunflax and roseberries! A little seed packet was tucked among them. They would grow at home, too."

	var nodes: Array = []

	func _ready() -> void:
		add_to_group("c1x_meadow_patch")

	func add_node(node: Node3D, area: Node, p: Vector2, yaw_deg: float) -> void:
		Common.place(self, node, area, p, yaw_deg, -0.03)
		nodes.append(node)
		if node.has_signal("harvested_out"):
			node.connect("harvested_out", _on_harvested_out)

	func _on_harvested_out(_node: Node3D) -> void:
		mark_found()

	## First harvest at the patch: objective flag + the starter packet (once). True only the first time.
	func mark_found() -> bool:
		if not bool(GameState.get_flag(L.FLAG_FOUND_NEW_CROPS)):
			GameState.set_flag(L.FLAG_FOUND_NEW_CROPS, true)
		var first := Common.grant_content(L.REWARD_GARDENER, MESSAGE)
		if first:
			Events.hint.emit("c1x_new_crops", "Sunflax and roseberry seeds grow in a crop plot, just like sweetroot.")
		return first
