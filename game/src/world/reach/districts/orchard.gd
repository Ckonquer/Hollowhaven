extends RefCounted
## District: Pumpkintide Orchard (landmark hr_orchard, docs/CHAPTER_TWO_SPEC.md §10 district interface).
## The region (reach_world) calls footprints() before planting generic vegetation / grass, then build(area)
## once the base region (terrain, colliders, arches) exists. Content: src/world/reach/west/orchard_controller.gd,
## data: data/reach_west.gd. Everything follows area.height_at (works on flat ground too); shape_terrain()
## only levels a few sites and paints soil / lanes when the region terrain offers its shaping API.

const Data := preload("res://data/reach_west.gd")
const Controller := preload("res://src/world/reach/west/orchard_controller.gd")

const NODE_NAME := "District_Orchard"


## [[Vector2 centre, float radius], ...] kept clear of generic vegetation and grass.
static func footprints() -> Array:
	return Data.ORCHARD_FOOTPRINTS.duplicate(true)


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


## Region terrain shaping (reach_terrain.gd API, run by reach_districts.gd inside hr_orchard's circle):
## level the festival garden, the irrigation junction/cistern, the mimic pocket and the roadside bale; warm
## amber soil; lanes from the arch to the Candleyard and Pools roads. Deterministic, heights only nudged.
static func shape_terrain(terrain: RefCounted) -> void:
	if not _can_shape(terrain):
		return
	var sites := [[Data.GARDEN["bed"], 5.5, 9.0], [Data.IRRIGATION["junction"], 3.0, 6.0], [Data.IRRIGATION["cistern"], 2.5, 5.0],
		[Data.MIMIC_POCKET["center"], 6.5, 8.0], [Data.MOMENT["pos"], 1.8, 4.0], [Data.IRRIGATION["drain_pond"], 3.2, 5.5]]
	for s in sites:
		var c: Vector2 = s[0]
		terrain.call("flatten", c, float(s[1]), float(s[2]), _mean(terrain, c, float(s[1])))
	terrain.call("tint_disc", Data.center_of(Data.ORCHARD), 10.0, 27.0, Color("c78f45"), 0.22)
	terrain.call("tint_disc", Data.MIMIC_POCKET["center"], 3.0, 7.0, Color("8a5a36"), 0.3)
	for lane in Data.ORCHARD_LANES:
		terrain.call("mark_path", lane, 0.9, 0.75)


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
