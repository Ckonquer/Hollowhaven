extends RefCounted
## District: Thimblebrook Pools (landmark hr_pools, docs/CHAPTER_TWO_SPEC.md §10 district interface).
## The region (reach_world) calls footprints() before planting generic vegetation / grass, then build(area)
## once the base region (terrain, colliders, arches) exists. Content: src/world/reach/west/pools_controller.gd,
## data: data/reach_west.gd. Everything follows area.height_at (works on flat ground too); shape_terrain()
## only levels a few sites and paints soil / lanes when the region terrain offers its shaping API.

const Data := preload("res://data/reach_west.gd")
const Controller := preload("res://src/world/reach/west/pools_controller.gd")

const NODE_NAME := "District_Pools"


## [[Vector2 centre, float radius], ...] kept clear of generic vegetation and grass.
static func footprints() -> Array:
	return Data.POOLS_FOOTPRINTS.duplicate(true)


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


## Region terrain shaping inside hr_pools: level each pool so its water lies flat, soft sandy banks.
static func shape_terrain(terrain: RefCounted) -> void:
	if not _can_shape(terrain):
		return
	# Gentle partial levelling (the brook really does run downhill between the pools; the last pool sits beside
	# the region's own Thimblebrook carving, so it is only softened).
	var soft := [1.0, 1.0, 0.35]
	var reach := [3.2, 3.2, 1.4]
	for i in Data.POOL_DISCS.size():
		var pd: Array = Data.POOL_DISCS[i]
		var c: Vector2 = pd[0]
		var r := float(pd[1])
		terrain.call("blend_to", c, r, r + float(reach[i]), _mean(terrain, c, r), float(soft[i]))
		terrain.call("tint_disc", c, r, r + 2.2, Color("cdb88a"), 0.35)
	terrain.call("flatten", Data.POUCH, 1.4, 3.6, _mean(terrain, Data.POUCH, 1.4))
	# Mark the ankle-deep water in the terrain's water map (footsteps splash, no grass under the pools, the
	# region's depth check sees a 5 cm wade). The region draws only its own brook / ponds, never these samples.
	if terrain.has_method("set_water_disc"):
		for pd2 in Data.POOL_DISCS:
			var c2: Vector2 = pd2[0]
			terrain.call("set_water_disc", c2, float(pd2[1]) - 0.2, _h(terrain, c2) + Data.WATER_LIFT + 0.01)
	if terrain.has_method("each_in") and terrain.has_method("set_water"):
		var lift := Data.WATER_LIFT + 0.01
		var pts: Array = Data.BROOK
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
			for k in n + 1:
				var q := a.lerp(b, float(k) / float(n))
				terrain.call("each_in", q, Data.BROOK_WIDTH * 0.5 - 0.1, func(_idx: int, x: float, z: float, _d: float) -> void:
					terrain.call("set_water", x, z, float(terrain.call("get_height", x, z)) + lift))


static func _h(terrain: RefCounted, p: Vector2) -> float:
	return float(terrain.call("get_height", p.x, p.y))


static func _can_shape(terrain: RefCounted) -> bool:
	if terrain == null:
		return false
	for m in ["flatten", "blend_to", "get_height", "tint_disc", "mark_path"]:
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
