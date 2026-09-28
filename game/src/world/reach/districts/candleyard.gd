extends RefCounted
## District: The Candleyard (landmark hr_candleyard, docs/CHAPTER_TWO_SPEC.md §10 district interface).
## The region (reach_world) calls footprints() before planting generic vegetation / grass, then build(area)
## once the base region (terrain, colliders, arches) exists. Content: src/world/reach/west/candleyard_controller.gd,
## data: data/reach_west.gd. Everything follows area.height_at (works on flat ground too); shape_terrain()
## only levels a few sites and paints soil / lanes when the region terrain offers its shaping API.

const Data := preload("res://data/reach_west.gd")
const Controller := preload("res://src/world/reach/west/candleyard_controller.gd")

const NODE_NAME := "District_Candleyard"


## [[Vector2 centre, float radius], ...] kept clear of generic vegetation and grass.
static func footprints() -> Array:
	return Data.CANDLEYARD_FOOTPRINTS.duplicate(true)


static func build(area: Node3D) -> void:
	build_district(area)


## Same as build(), returning the district root (tests / QA). Builds once per area.
static func build_district(area: Node3D) -> Node3D:
	if area == null:
		return null
	var existing := area.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var c: Node3D = Controller.new()
	c.name = NODE_NAME
	c.setup(area)
	area.add_child(c)
	c.build()
	return c


## Region terrain shaping inside hr_candleyard: the yard keeps its natural gentle hill (the wall, stones and
## gates follow height_at block by block, so the gates never become steps); only small level pads under the
## shed, the Candle Tree, the marker + nook and the bench, and a cool lilac-grey ground tint.
static func shape_terrain(terrain: RefCounted) -> void:
	if not _can_shape(terrain):
		return
	var c := Data.center_of(Data.CANDLEYARD)
	for site in [[Data.SHED["pos"], 1.9, 5.4], [Data.CANDLE_TREE, 1.4, 4.0], [Data.MARKER, 1.0, 3.2], [Data.NOOK, 1.2, 3.4],
			[Data.BENCH["pos"], 1.1, 3.6]]:
		var p: Vector2 = site[0]
		terrain.call("flatten", p, float(site[1]), float(site[2]), _mean(terrain, p, float(site[1])))
	terrain.call("tint_disc", c, 8.0, Data.WALL_RADIUS + 2.0, Color("8d849e"), 0.3)


static func _h(terrain: RefCounted, p: Vector2) -> float:
	return float(terrain.call("get_height", p.x, p.y))


static func _can_shape(terrain: RefCounted) -> bool:
	if terrain == null:
		return false
	for m in ["flatten", "get_height", "tint_disc", "mark_path"]:
		if not terrain.has_method(m):
			return false
	return true


## Mean terrain height over a disc (a level pad at the mean moves the ground least).
static func _mean(terrain: RefCounted, c: Vector2, r: float) -> float:
	var sum := 0.0
	var n := 0
	var k := int(ceil(r))
	for dz in range(-k, k + 1):
		for dx in range(-k, k + 1):
			var p := c + Vector2(dx, dz)
			if p.distance_to(c) <= r:
				sum += _h(terrain, p)
				n += 1
	return sum / float(maxi(n, 1))
