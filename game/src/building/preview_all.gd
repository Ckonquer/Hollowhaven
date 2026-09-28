extends Node3D
## Art QA helper for the preview stage (debug only):
##   tools/godot.sh --path game -- --preview=res://src/building/preview_all.gd --shot-dir=<dir>
##       --preview-args='{"mode":"all"}'          every structure in a grid (default)
##       --preview-args='{"mode":"house"}'        a little cottage with furniture, farm and decor
##       --preview-args='{"mode":"crops"}'        crop plot: empty + the four growth stages
##       --preview-args='{"mode":"upstairs"}'     Chapter Two: a two-storey cottage (stairs, upper floor,
##                                                 railings, upstairs roofs, furniture and seasonal decor)
##       --preview-args='{"mode":"pumpkins"}'     the six carved pumpkin faces in a row
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
		"upstairs":
			for e in upstairs_layout():
				_put(String(e[0]), e[1], int(e[2]), e[3] if e.size() > 3 else {})
		"pumpkins":
			var faces: Array = ItemDB.structure("pumpkin_lantern").get("faces", [])
			for i in faces.size():
				_put("pumpkin_lantern", Vector3((float(i) - float(faces.size() - 1) * 0.5) * 0.9, 0, 0), 0, {"face": faces[i]})
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


## Chapter Two two-storey cottage on a 4 x 6 m footprint (x 0..4, z 0..6; heights as placement.gd computes
## them: upper floor 3.0, upstairs walls 3.0, upstairs roofs 6.0). [id, pos, rot, params?]
static func upstairs_layout() -> Array:
	var up := 3.0
	var top := up + 0.12
	return [
		# Ground storey: walls, a doorway at the foot of the stairs, a floor and the stairs.
		["wood_wall", Vector3(1, 0, 0), 180], ["arched_window", Vector3(3, 0, 0), 180],
		["wood_doorway", Vector3(1, 0, 6), 0], ["crescent_window", Vector3(3, 0, 6), 0],
		["wood_wall", Vector3(0, 0, 1), 270], ["wood_wall", Vector3(0, 0, 3), 270], ["wood_window", Vector3(0, 0, 5), 270],
		["wood_wall", Vector3(4, 0, 1), 90], ["wood_window", Vector3(4, 0, 3), 90], ["wood_wall", Vector3(4, 0, 5), 90],
		["wood_floor", Vector3(3, 0, 1), 0], ["wood_floor", Vector3(3, 0, 3), 0], ["wood_floor", Vector3(3, 0, 5), 0],
		["wood_stairs", Vector3(1, 0, 4), 0],
		["kitchen_counter", Vector3(3, 0.12, 0.5), 0], ["bookshelf", Vector3(3.5, 0.12, 3), 270],
		# Upper storey: floor tiles around the stairwell, railings along it, walls, furniture.
		["upper_floor", Vector3(1, up, 1), 0], ["upper_floor", Vector3(3, up, 1), 0],
		["upper_floor", Vector3(3, up, 3), 0], ["upper_floor", Vector3(3, up, 5), 0],
		["wood_railing", Vector3(2, up, 3), 90], ["wood_railing", Vector3(2, up, 5), 90],
		["wood_wall", Vector3(1, up, 0), 180], ["arched_window", Vector3(3, up, 0), 180], ["half_wall", Vector3(3, up, 6), 0],
		["wood_wall", Vector3(4, up, 1), 90], ["crescent_window", Vector3(4, up, 3), 90], ["wood_wall", Vector3(4, up, 5), 90],
		["bed", Vector3(3.5, top, 1.0), 0], ["wardrobe", Vector3(3, top, 4.5), 180], ["companion_bed", Vector3(2.5, top, 2.5), 0],
		["pumpkin_lantern", Vector3(3.5, top, 5.5), 0, {"face": "cat"}],
		# Upstairs roofs on the upstairs walls (the stairwell roofs lean on their neighbours).
		["gable_roof", Vector3(1, up * 2.0, 1), 0], ["gable_roof", Vector3(3, up * 2.0, 1), 0],
		["wood_roof", Vector3(3, up * 2.0, 3), 90], ["wood_roof", Vector3(3, up * 2.0, 5), 90],
		["roof_corner", Vector3(1, up * 2.0, 3), 0], ["wood_roof", Vector3(1, up * 2.0, 5), 270],
		# Porch and seasonal decor outside the door.
		["porch_post", Vector3(-0.5, 0, 7.5), 0], ["cottage_bench", Vector3(3, 0, 7.5), 0],
		["pumpkin_lantern", Vector3(0.5, 0, 7.5), 0, {"face": "friendly"}], ["candy_bowl", Vector3(1.5, 0, 7.5), 0],
		["flower_box", Vector3(3.5, 0, 6.5), 0], ["scarecrow", Vector3(6.5, 0, 6.5), 0], ["ghost_lantern", Vector3(5.5, 0, 4.5), 0],
	]
