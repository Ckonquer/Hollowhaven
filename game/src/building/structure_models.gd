extends RefCounted
## Dispatcher for structure visuals and collision shapes (every id in data/structures.gd).
##   var parts := StructureModels.build("storage_chest", model_root)   # -> {"lid": Node3D}
##   StructureModels.build("pumpkin_lantern", root, {"face": "cat"})   # Chapter Two model options
## Build previews (ghosts) reuse build() and then swap every material for a translucent one.
## Chapter Two pieces: models_storey.gd (stairs, upper floors, railings, walls, roofs, trim), models_cozy.gd
## (furniture and stations), models_seasonal.gd (lights, keepsakes and Halloween decor).

const Palette := preload("res://src/art/palette.gd")
const U := preload("res://src/building/model_util.gd")
const Batch := preload("res://src/building/batch.gd")
const Furniture := preload("res://src/building/models_furniture.gd")
const Parts := preload("res://src/building/models_building.gd")
const Decor := preload("res://src/building/models_decor.gd")
const Storey := preload("res://src/building/models_storey.gd")
const Cozy := preload("res://src/building/models_cozy.gd")
const Seasonal := preload("res://src/building/models_seasonal.gd")
const CropModels := preload("res://src/farming/crop_models.gd")
const Placement := preload("res://src/building/placement.gd")

static var _shape_cache: Dictionary = {}


static func build(structure_id: String, root: Node3D, opts: Dictionary = {}) -> Dictionary:
	match structure_id:
		"workbench": return Furniture.workbench(root)
		"storage_chest": return Furniture.storage_chest(root)
		"bed": return Furniture.bed(root)
		"table": return Furniture.table(root)
		"stool": return Furniture.stool(root)
		"rug": return Furniture.rug(root)
		"crop_plot": return CropModels.plot(root)
		"wood_floor": return Parts.wood_floor(root)
		"wood_wall": return Parts.wood_wall(root)
		"wood_window": return Parts.wood_window(root)
		"wood_doorway": return Parts.wood_doorway(root)
		"wood_roof": return Parts.wood_roof(root)
		"fence": return Parts.fence(root)
		"lantern_post": return Decor.lantern_post(root)
		"flower_pot": return Decor.flower_pot(root)
		"pebble_cairn": return Decor.pebble_cairn(root)
		"echo_chime": return Decor.echo_chime(root)
		"heartbloom_lamp": return Decor.heartbloom_lamp(root)
		"haven_banner": return Decor.haven_banner(root)
		# --- Chapter Two ---
		"wood_stairs": return Storey.wood_stairs(root)
		"upper_floor": return Storey.upper_floor(root)
		"wood_railing": return Storey.wood_railing(root)
		"half_wall": return Storey.half_wall(root)
		"porch_post": return Storey.porch_post(root)
		"arched_window": return Storey.arched_window(root)
		"crescent_window": return Storey.crescent_window(root)
		"gable_roof": return Storey.gable_roof(root)
		"roof_corner": return Storey.roof_corner(root)
		"gothic_trim": return Storey.gothic_trim(root)
		"flower_box": return Cozy.flower_box(root)
		"curtain": return Cozy.curtain(root)
		"bookshelf": return Cozy.bookshelf(root)
		"wardrobe": return Cozy.wardrobe(root)
		"vanity_mirror": return Cozy.vanity_mirror(root)
		"kitchen_counter": return Cozy.kitchen_counter(root)
		"furnace": return Cozy.furnace(root)
		"loom": return Cozy.loom(root)
		"companion_bed": return Cozy.companion_bed(root)
		"companion_perch": return Cozy.companion_perch(root)
		"sturdy_planter": return CropModels.planter(root)
		"cottage_bench": return Cozy.cottage_bench(root)
		"music_box": return Cozy.music_box(root)
		"expedition_board": return Cozy.expedition_board(root)
		"lanternwake_table": return Cozy.lanternwake_table(root)
		"wardlight": return Seasonal.wardlight(root)
		"miner_lamp": return Seasonal.miner_lamp(root)
		"thread_veil": return Seasonal.thread_veil(root, bool(Settings.get_value("arachnophobia")))
		"pumpkin_lantern": return Seasonal.pumpkin_lantern(root, String(opts.get("face", "")))
		"pumpkin_lights": return Seasonal.pumpkin_lights(root)
		"bat_bunting": return Seasonal.bat_bunting(root)
		"ghost_lantern": return Seasonal.ghost_lantern(root)
		"candy_bowl": return Seasonal.candy_bowl(root)
		"scarecrow": return Seasonal.scarecrow(root)
	return _fallback(structure_id, root)


## Unknown ids (e.g. a structure added to the data later) still get a tidy crate in the item colour.
static func _fallback(structure_id: String, root: Node3D) -> Dictionary:
	var def := ItemDB.structure(structure_id)
	var s: Vector2i = def.get("size", Vector2i.ONE)
	var h := clampf(float(def.get("height", 0.8)), 0.1, 3.0)
	var col: Color = ItemDB.item(String(def.get("item", structure_id))).get("color", Palette.WOOD)
	var mesh := U.baked("fallback|%s" % structure_id, func(b: Batch) -> void:
		b.rbox(Vector3(float(s.x) * 0.9, h, float(s.y) * 0.9), Vector3(0, h * 0.5, 0), col, 0.06)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


## Footstep surface for colliders ("wood" / "stone").
static func surface_kind(structure_id: String) -> String:
	if structure_id in ["pebble_cairn", "flower_pot", "furnace", "wardlight"]:
		return "stone"
	return "wood"


## Solid collision: Array of [Shape3D, Transform3D] in the structure's local space.
static func collision_shapes(structure_id: String) -> Array:
	if _shape_cache.has(structure_id):
		return _shape_cache[structure_id]
	var def := ItemDB.structure(structure_id)
	var s: Vector2i = def.get("size", Vector2i.ONE)
	var h := float(def.get("height", 1.0))
	var out: Array = []
	match structure_id:
		"wood_floor":
			var cp := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(Vector3(c.x * 1.0, Placement.FLOOR_TOP, c.y * 1.0))
				pts.append(Vector3(c.x * 1.28, 0.0, c.y * 1.28))
			cp.points = pts
			out.append([cp, Transform3D.IDENTITY])
		"wood_wall", "wood_window", "arched_window", "crescent_window":
			out.append([_box(Vector3(2.1, 3.0, Placement.WALL_THICKNESS)), Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0))])
		"wood_doorway":
			var side_w := 1.12 - Parts.DOOR_HALF
			for sx in [-1.0, 1.0]:
				out.append([_box(Vector3(side_w, 3.0, Placement.WALL_THICKNESS)), Transform3D(Basis.IDENTITY, Vector3((Parts.DOOR_HALF + side_w * 0.5) * sx, 1.5, 0))])
			var top_y := Parts.DOOR_SPRING + Parts.DOOR_HALF
			out.append([_box(Vector3(Parts.DOOR_HALF * 2.0, 3.0 - top_y, Placement.WALL_THICKNESS)), Transform3D(Basis.IDENTITY, Vector3(0, (top_y + 3.0) * 0.5, 0))])
		"wood_roof":
			var rp := ConvexPolygonShape3D.new()
			rp.points = Parts.roof_collision_points()
			out.append([rp, Transform3D.IDENTITY])
		"fence":
			out.append([_box(Vector3(1.0, 0.9, 0.16)), Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0))])
		"lantern_post":
			out.append([_box(Vector3(0.34, 2.2, 0.34)), Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0))])
		"haven_banner":
			out.append([_box(Vector3(0.36, 2.6, 0.36)), Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0))])
		"table":
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.46
			cyl.height = 0.8
			out.append([cyl, Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0))])
		# --- Chapter Two ---
		"wood_stairs":
			# One ramp under the treads: 37.95 deg (< the 46 deg the player can walk, 52 for companions),
			# ending flush with the landing's walkable top.
			var sp := ConvexPolygonShape3D.new()
			sp.points = Storey.stair_collision_points()
			out.append([sp, Transform3D.IDENTITY])
		"upper_floor":
			var slab := Storey.UPPER_SLAB
			out.append([_box(Vector3(2.0, slab.y, 2.0)), Transform3D(Basis.IDENTITY, Vector3(0, Placement.UPPER_TOP - slab.y * 0.5, 0))])
		"wood_railing":
			out.append([_box(Vector3(2.04, 1.0, 0.14)), Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))])
		"half_wall":
			out.append([_box(Vector3(2.1, 1.2, Placement.WALL_THICKNESS)), Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))])
		"porch_post":
			out.append([_box(Vector3(0.3, 3.0, 0.3)), Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0))])
		"gable_roof":
			var gp := ConvexPolygonShape3D.new()
			gp.points = Storey.gable_collision_points()
			out.append([gp, Transform3D.IDENTITY])
		"roof_corner":
			var cp2 := ConvexPolygonShape3D.new()
			cp2.points = Storey.corner_collision_points()
			out.append([cp2, Transform3D.IDENTITY])
		"wardlight":
			out.append([_box(Vector3(0.4, 2.4, 0.4)), Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))])
		"scarecrow":
			out.append([_box(Vector3(0.3, 2.0, 0.3)), Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))])
		_:
			var margin := 0.08
			out.append([_box(Vector3(float(s.x) - margin, h, float(s.y) - margin)), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0))])
	_shape_cache[structure_id] = out
	return out


## Interaction collider (layer "interact") covering the whole piece: [Shape3D, Transform3D].
static func interact_shape(structure_id: String) -> Array:
	var key := "interact|" + structure_id
	if _shape_cache.has(key):
		return _shape_cache[key]
	var def := ItemDB.structure(structure_id)
	var s: Vector2i = def.get("size", Vector2i.ONE)
	var h := maxf(float(def.get("height", 1.0)), 0.6)
	var out: Array = [_box(Vector3(float(s.x), h, float(s.y))), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0))]
	_shape_cache[key] = out
	return out


static func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b
