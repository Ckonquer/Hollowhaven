extends Node3D
## Art QA helper for the preview stage (debug only):
##   tools/godot.sh --path game -- --preview=res://src/building/preview_all.gd --shot-dir=<dir>
##       --preview-args='{"mode":"all"}'          every structure in a grid (default)
##       --preview-args='{"mode":"house"}'        a little cottage with furniture, farm and decor
##       --preview-args='{"mode":"crops"}'        crop plot: empty + the four growth stages
##       --preview-args='{"ids":["bed","storage_chest"]}'   just these, in a row
## Also used by the house screenshot harness (build_harness.gd).

const Factory := preload("res://src/building/structure_factory.gd")

var mode: String = "all"
var ids: Array = []
var open_chest: bool = false


func setup(p: Dictionary) -> void:
	mode = String(p.get("mode", mode))
	ids = p.get("ids", [])
	open_chest = bool(p.get("open_chest", false))


func _ready() -> void:
	if not ids.is_empty():
		_row(ids, 2.6)
		return
	match mode:
		"house":
			house(self)
		"crops":
			for i in 5:
				_put("crop_plot", Vector3(-5.0 + i * 2.5, 0, 0), 0, {"stage": i - 1})
		_:
			_grid(ItemDB.all_structure_ids())


func _row(list: Array, spacing: float) -> void:
	var n := list.size()
	for i in n:
		# "crop_plot:3" = crop plot at growth stage 3
		var parts := String(list[i]).split(":")
		var params := {"stage": int(parts[1])} if parts.size() > 1 else {}
		_put(parts[0], Vector3((float(i) - float(n - 1) * 0.5) * spacing, 0, 0), 0, params)


func _grid(list: Array) -> void:
	var cols := int(ceilf(sqrt(float(list.size()))))
	var sp := 3.0
	for i in list.size():
		var cx := i % cols
		var cz := i / cols
		var pos := Vector3((float(cx) - float(cols - 1) * 0.5) * sp, 0, (float(cz) - float((list.size() - 1) / cols) * 0.5) * sp)
		_put(String(list[i]), pos, 0)


func _put(id: String, pos: Vector3, rot: int, params: Dictionary = {}) -> Node3D:
	var n := Factory.create(id, "", params)
	add_child(n)
	n.position = pos
	n.rotation.y = deg_to_rad(float(rot))
	if open_chest and id == "storage_chest" and n.has_method("set_open"):
		n.call_deferred("set_open", true)
	return n


## A cosy cottage on a 4 x 4 m floor (origin = floor centre) with its garden. Static so the harness
## can reuse the layout for GameState-backed placement.
static func house_layout() -> Array:
	return [
		["wood_floor", Vector3(-1, 0, -1), 0], ["wood_floor", Vector3(1, 0, -1), 0],
		["wood_floor", Vector3(-1, 0, 1), 0], ["wood_floor", Vector3(1, 0, 1), 0],
		["wood_wall", Vector3(-1, 0, -2), 180], ["wood_window", Vector3(1, 0, -2), 180],
		["wood_window", Vector3(-1, 0, 2), 0], ["wood_doorway", Vector3(1, 0, 2), 0],
		["wood_wall", Vector3(-2, 0, -1), 270], ["wood_window", Vector3(-2, 0, 1), 270],
		["wood_window", Vector3(2, 0, -1), 90], ["wood_wall", Vector3(2, 0, 1), 90],
		["wood_roof", Vector3(-1, 3, -1), 180], ["wood_roof", Vector3(1, 3, -1), 180],
		["wood_roof", Vector3(-1, 3, 1), 0], ["wood_roof", Vector3(1, 3, 1), 0],
		["bed", Vector3(-1.5, 0.12, -1.0), 0], ["storage_chest", Vector3(1.5, 0.12, -1.5), 0],
		["table", Vector3(0.5, 0.12, -1.5), 0], ["stool", Vector3(0.5, 0.12, -0.5), 0],
		["rug", Vector3(0, 0.12, 1), 0],
		["lantern_post", Vector3(2.5, 0, 2.5), 0], ["haven_banner", Vector3(-2.5, 0, 2.5), 0],
		["flower_pot", Vector3(-1.5, 0, 2.5), 0], ["heartbloom_lamp", Vector3(0.5, 0, 3.5), 0],
		["crop_plot", Vector3(4, 0, -1), 0], ["crop_plot", Vector3(4, 0, 1), 0],
		["fence", Vector3(5.5, 0, -1.5), 90], ["fence", Vector3(5.5, 0, -0.5), 90],
		["fence", Vector3(5.5, 0, 0.5), 90], ["fence", Vector3(5.5, 0, 1.5), 90],
		["workbench", Vector3(4, 0, 3.5), 0], ["pebble_cairn", Vector3(-3.5, 0, 0.5), 0],
		["echo_chime", Vector3(-3.5, 0, -1.5), 0],
	]


func house(parent: Node3D) -> void:
	var plot_stage := 1
	for e in house_layout():
		var params := {}
		if e[0] == "crop_plot":
			params = {"stage": plot_stage}
			plot_stage += 2
		var n := Factory.create(String(e[0]), "", params)
		parent.add_child(n)
		n.position = e[1]
		n.rotation.y = deg_to_rad(float(e[2]))
