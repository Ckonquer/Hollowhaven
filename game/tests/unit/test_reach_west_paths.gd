extends "res://tests/unit/test_reach_west_fixture.gd"
## Reach west districts (module C2): walkable connectivity (physics flood fills from the entries), openings at
## least 1.6 m wide x 2.4 m tall, floors that collide (no fall-through), every interactable and harvest node
## reachable, capsule clearance where she stands.


func _bounds(district: String, margin: float = 3.0) -> Rect2:
	var c := Data.center_of(district)
	var r := Data.radius_of(district) + margin
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


## Wide probe: a 1.6 m wide, 2.4 m tall body (capsule radius 0.8) must fit along the required routes.
func _wide_clear(h: Node3D, p: Vector2) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.8
	cap.height = 2.4
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, height(h, p) + 0.22 + 1.2, p.y))
	sq.collision_mask = MASK
	return h.get_world_3d().direct_space_state.intersect_shape(sq, 1).is_empty()


func _wide_cells(h: Node3D, bounds: Rect2, start: Vector2, cell: float = 0.8) -> Dictionary:
	var free := {}
	var seen := {}
	var origin := bounds.position
	var nx := int(ceil(bounds.size.x / cell))
	var nz := int(ceil(bounds.size.y / cell))
	var s := Vector2i(int((start.x - origin.x) / cell), int((start.y - origin.y) / cell))
	var queue: Array = [s]
	seen[s] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var p := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell
		if not _wide_clear(h, p):
			continue
		free[c] = true
		for dxy in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dxy
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return {"free": free, "origin": origin, "cell": cell}


func _check_reach(grid: Dictionary, root: Node3D, label: String) -> void:
	for it in interactables_under(root):
		var gp: Vector3 = (it as Node3D).global_position
		assert_true(reachable(grid, Vector2(gp.x, gp.z), 2.1), "%s: %s can be reached on foot" % [label, it.name])
	for id in root.nodes:
		var n: Node3D = root.nodes[id]
		assert_true(reachable(grid, Vector2(n.global_position.x, n.global_position.z), 1.9), "%s: %s can be reached on foot" % [label, id])


func test_orchard_is_connected_and_its_required_route_is_wide() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var o: Node3D = d["orchard"]
	var grid := walkable_cells(h, _bounds(Data.ORCHARD), Data.ORCHARD_ENTRY)
	assert_true((grid["free"] as Dictionary).size() > 3000, "a large walkable orchard (%d cells)" % (grid["free"] as Dictionary).size())
	# The probe really sees the solid props (sanity check of the flood fill itself).
	for solid in [Data.IRRIGATION["cistern"], Data.GARDEN["bed"], Data.ORCHARD_DECOR["giant_pumpkins"][0][0], Data.GARDEN["lamp"]]:
		assert_false(capsule_clear(h, solid), "%s is solid" % str(solid))
	_check_reach(grid, o, "orchard")
	# The ways on: the Candleyard road start (-76, 8) and the pools road start (-58, 16) (region roads).
	for exit_p in [Vector2(-76.0, 8.0), Vector2(-58.0, 16.0)]:
		assert_true(reachable(grid, exit_p, 1.2), "the orchard connects to the road at %s" % str(exit_p))
	# Required content (levers, seed box, lamp, the mimic pocket) is reachable by a 1.6 m wide, 2.4 m tall body.
	var wide := _wide_cells(h, _bounds(Data.ORCHARD), Data.ORCHARD_ENTRY)
	for key in ["lever_junction", "lever_gate", "festival_seed", "garden_lamp"]:
		var it: Node3D = o.interactables[key]
		assert_true(reachable(wide, Vector2(it.global_position.x, it.global_position.z), 2.4), "%s is on a wide route" % key)
	for dm in o.mimic_pocket.dormant:
		var rp: Vector3 = (dm["root"] as Node3D).global_position
		assert_true(reachable(wide, Vector2(rp.x, rp.z), 2.6), "the dormant mimics are on a wide route")
	# The crooked fence gaps are real openings (>= 1.6 m wide, 2.4 m tall).
	var runs: Array = Data.ORCHARD_DECOR["fences"]
	for i in range(0, runs.size(), 2):
		var a: Vector2 = runs[i][1]
		var b: Vector2 = runs[i + 1][0]
		assert_true(a.distance_to(b) >= 1.6 + 0.4, "fence gap %d is wide (%.1f m)" % [i / 2, a.distance_to(b)])
		assert_true(_opening_clear(h, (a + b) * 0.5, b - a, a.distance_to(b) - 0.4), "fence gap %d is open" % [i / 2])


func test_pools_are_connected_and_the_stepping_stones_hold() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var p: Node3D = d["pools"]
	var grid := walkable_cells(h, _bounds(Data.POOLS), Data.POOLS_ENTRIES[0])
	_check_reach(grid, p, "pools")
	assert_true(reachable(grid, Data.POOLS_ENTRIES[1], 1.0), "both pools entries connect")
	for c in Data.CHIMES:
		assert_true(reachable(grid, c, Data.CHIME_REACH - 0.3), "chime %s can be walked up to" % str(c))
	# No fall-through: every stepping stone is solid at its top, the pools have ground under the water.
	for s in Data.STEPPING_STONES:
		var g: Variant = ground_hit(h, s)
		assert_not_null(g, "stone %s solid" % str(s))
		if g != null:
			assert_almost((g as Vector3).y, height(h, s) + Data.STONE_TOP, 0.05, "stone %s top at %.2f m" % [str(s), Data.STONE_TOP])
	for pd in Data.POOL_DISCS:
		var g2: Variant = ground_hit(h, pd[0])
		assert_not_null(g2, "ground under pool %s (ankle-deep water, no swimming)" % str(pd[0]))
		if g2 != null:
			assert_almost((g2 as Vector3).y, height(h, pd[0]), 0.05, "the pool floor is the ground")


func test_candleyard_gates_are_wide_and_everything_connects() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var c: Node3D = d["candleyard"]
	var grid := walkable_cells(h, _bounds(Data.CANDLEYARD), Data.CANDLEYARD_ENTRIES[0])
	_check_reach(grid, c, "candleyard")
	assert_true(reachable(grid, Data.CANDLEYARD_ENTRIES[1], 1.0), "the south-east entry connects")
	assert_true(reachable(grid, Data.HAT["stand"], 0.8), "the hat can be reached from the ground (no jumping)")
	var wall_blocks := 0
	for a in range(0, 360, 5):
		if Data.in_wall_gate(wrapf(float(a), -180.0, 180.0)):
			continue
		if not capsule_clear(h, Data.gate_point(float(a))):
			wall_blocks += 1
	assert_true(wall_blocks > 40, "the low wall is solid between the gates (%d samples blocked)" % wall_blocks)
	assert_false(capsule_clear(h, Data.SHED["pos"]), "the shed is solid")
	for g in c.gate_openings:
		var gp: Vector2 = g[0]
		var tangent := (gp - Data.CANDLEYARD_CENTER).orthogonal()
		assert_true(float(g[1]) >= 1.6, "gate width %.1f m" % float(g[1]))
		assert_true(_opening_clear(h, gp, tangent, 1.6), "gate at %s is open 1.6 m x 2.4 m" % str(gp))
	# The ribbon route to the hat is itself one wide walk (1.6 m) from the south-east gate.
	var wide := _wide_cells(h, _bounds(Data.CANDLEYARD), Data.CANDLEYARD_ENTRIES[1])
	for rp in Data.HAT_RIBBONS:
		assert_true(reachable(wide, rp, 1.2), "ribbon waypoint %s on a wide route" % str(rp))
	assert_true(reachable(wide, Data.HAT["stand"], 1.4), "the hat stand is on a wide route")


func test_stand_spots_have_capsule_clearance_and_floors() -> void:
	var h: Node3D = await flat_host()
	var _d := await build_all(h)
	var spots: Array = [Data.ORCHARD_ENTRY, Data.HAT["stand"], Data.POOLS_ENTRIES[0], Data.POOLS_ENTRIES[1]]
	spots.append_array(Data.CANDLEYARD_ENTRIES)
	for s in spots:
		assert_true(capsule_clear(h, s), "a player capsule fits at %s" % str(s))
		assert_not_null(ground_hit(h, s), "floor under %s" % str(s))
	# The raised festival bed is solid (she can't sink into it) and its top is at bed height.
	var g: Variant = ground_hit(h, Data.GARDEN["bed"])
	assert_not_null(g)
	if g != null:
		assert_almost((g as Vector3).y, height(h, Data.GARDEN["bed"]) + 0.4, 0.05, "bed collider top")


## A 2.4 m tall box, `width` wide along `along`, 0.4 m deep, standing at p: nothing solid inside.
func _opening_clear(h: Node3D, p: Vector2, along: Vector2, width: float) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2.4, 0.4)
	var yaw := -atan2(along.y, along.x)
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = box
	sq.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, height(h, p) + 0.15 + 1.2, p.y))
	sq.collision_mask = MASK
	return h.get_world_3d().direct_space_state.intersect_shape(sq, 1).is_empty()
