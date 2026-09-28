extends "res://tests/test_case.gd"
## Shared helpers for the Reach west district suites (module C2). Has no tests of its own.
## Hosts: a flat placeholder-style Reach floor (the region's terrain is built by another module and may be
## in progress) and a gently sloped host with a matching HeightMapShape3D, so every build is also checked to
## follow area.height_at.

const Data := preload("res://data/reach_west.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const HostScript := preload("res://src/world/areas_ch2/placeholder_area.gd")
const Orchard := preload("res://src/world/reach/districts/orchard.gd")
const Pools := preload("res://src/world/reach/districts/pools.gd")
const Candleyard := preload("res://src/world/reach/districts/candleyard.gd")
const B := preload("res://src/world/reach/west/west_build.gd")
const Irrigation := preload("res://src/world/reach/west/irrigation.gd")

const MASK := 1 | 32
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.6


## A sloped test host: height_at is a smooth function; a HeightMapShape3D (1 m) over the west districts matches it.
class SlopeHost extends "res://src/world/areas_ch2/placeholder_area.gd":
	const X0 := -122.0
	const X1 := -18.0
	const Z0 := -92.0
	const Z1 := 72.0

	func height_at(x: float, z: float) -> float:
		return 0.03 * (x + 80.0) + 0.5 * sin(z * 0.08) + 0.3 * cos(x * 0.06)

	func build_ground() -> void:
		var w := int(X1 - X0) + 1
		var d := int(Z1 - Z0) + 1
		var data := PackedFloat32Array()
		data.resize(w * d)
		for j in d:
			for i in w:
				data[j * w + i] = height_at(X0 + float(i), Z0 + float(j))
		var shape := HeightMapShape3D.new()
		shape.map_width = w
		shape.map_depth = d
		shape.map_data = data
		var body := StaticBody3D.new()
		body.name = "SlopeGround"
		body.collision_layer = 1
		body.set_meta("surface", "grass")
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.position = Vector3((X0 + X1) * 0.5, 0.0, (Z0 + Z1) * 0.5)
		add_child(body)


var _hosts: Array = []


func after_each() -> void:
	for h in _hosts:
		if is_instance_valid(h):
			h.queue_free()
	_hosts.clear()
	B.availability_override = {}
	Settings.set_value("high_visibility_cues", false)
	Settings.set_value("timing_assist", false)
	Settings.set_value("horror_intensity", 1)
	await wait_frames(2)


## A flat Reach floor at y = 0 (collides on layer 1), in the tree.
func flat_host() -> Node3D:
	fresh_state()
	var h: Node3D = HostScript.new()
	h.area_id = Data.AREA_ID
	h.add_ground(Rect2(-140, -110, 280, 220), 0.0, Color("a8703f"), "grass")
	add_child(h)
	_hosts.append(h)
	await wait_physics(1)
	return h


func slope_host() -> Node3D:
	fresh_state()
	var h: Node3D = SlopeHost.new()
	h.area_id = Data.AREA_ID
	h.build_ground()
	add_child(h)
	_hosts.append(h)
	await wait_physics(1)
	return h


func build_all(h: Node3D) -> Dictionary:
	var o: Node3D = Orchard.build_district(h)
	var p: Node3D = Pools.build_district(h)
	var c: Node3D = Candleyard.build_district(h)
	await wait_physics(2)
	return {"orchard": o, "pools": p, "candleyard": c}


func height(h: Node3D, p: Vector2) -> float:
	return float(h.height_at(p.x, p.y))


## Ground point below p (ray from +3 m to -6 m around the host height); null when nothing is hit.
## exclude = collider RIDs the ray ignores.
func ground_hit(h: Node3D, p: Vector2, exclude: Array = []) -> Variant:
	var y := height(h, p)
	var space := h.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 3.0, p.y), Vector3(p.x, y - 6.0, p.y), MASK)
	if not exclude.is_empty():
		var ex: Array[RID] = []
		for r in exclude:
			ex.append(r)
		q.exclude = ex
	var hit := space.intersect_ray(q)
	return null if hit.is_empty() else hit["position"]


## True when a player-sized capsule standing on the ground at p overlaps nothing solid.
func capsule_clear(h: Node3D, p: Vector2, ground_y: Variant = null) -> bool:
	var y: float = height(h, p) if ground_y == null else float(ground_y)
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, y + 0.18 + CAPSULE_HEIGHT * 0.5, p.y))
	sq.collision_mask = MASK
	return h.get_world_3d().direct_space_state.intersect_shape(sq, 1).is_empty()


## Grid flood fill (cell metres) over the square bounds from `start`; returns {Vector2i: true} of walkable cells.
func walkable_cells(h: Node3D, bounds: Rect2, start: Vector2, cell: float = 0.8) -> Dictionary:
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
		if not capsule_clear(h, p):
			continue
		free[c] = true
		for dxy in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dxy
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return {"free": free, "origin": origin, "cell": cell}


## True when some walkable cell lies within `reach` metres of target (XZ).
func reachable(grid: Dictionary, target: Vector2, reach: float) -> bool:
	var origin: Vector2 = grid["origin"]
	var cell: float = grid["cell"]
	var r := int(ceil(reach / cell)) + 1
	var c := Vector2i(int((target.x - origin.x) / cell), int((target.y - origin.y) / cell))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dz)
			if not (grid["free"] as Dictionary).has(n):
				continue
			var p := origin + (Vector2(n) + Vector2(0.5, 0.5)) * cell
			if p.distance_to(target) <= reach:
				return true
	return false


## Every west_interactable under a district root.
func interactables_under(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_method("get_interaction") and n.has_method("set_active") and n.get("interact_id") != null:
			out.append(n)
	return out


func flag(f: String) -> bool:
	var v: Variant = GameState.get_flag(f)
	return v is bool and v
