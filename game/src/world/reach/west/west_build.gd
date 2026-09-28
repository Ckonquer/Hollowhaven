extends RefCounted
## Shared placement helpers for the Reach west districts: ground heights from the region, colliders,
## MultiMesh decor, terrain-draped water meshes, renewable harvest nodes and guarded enemy spawners.
## Everything is deterministic (fixed data, RNGs seeded by name) so node ids and layouts never change.

const Data := preload("res://data/reach_west.gd")
const Art := preload("res://src/world/reach/west/west_art.gd")
const Props := preload("res://src/world/surface/props.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const ResourceNodeScript := preload("res://src/world/common/resource_node.gd")
const SpawnerScript := preload("res://src/enemies/enemy_spawner.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")

const LAYER_WORLD := 1
const DECOR_RANGE := 90.0
const SMALL_RANGE := 55.0

## Tests only: {enemy_id: bool} overrides enemy_available() (pretend a later-wave enemy exists / is missing).
static var availability_override: Dictionary = {}


# --- Ground ----------------------------------------------------------------------------------------------

static func height(area: Node, p: Vector2) -> float:
	if area != null and is_instance_valid(area) and area.has_method("height_at"):
		return float(area.height_at(p.x, p.y))
	return 0.0


static func ground(area: Node, p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height(area, p) + lift, p.y)


## Yaw (radians) that makes -Z face `to` from `from` (same convention as hallowmere_layout.yaw_towards).
static func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length() < 0.001:
		return 0.0
	return atan2(-d.x, -d.y)


## A deterministic RNG for a name (layout jitter never depends on build order).
static func rng_for(key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("hr_west|" + key)
	return r


# --- Colliders -----------------------------------------------------------------------------------------------

## One StaticBody3D (layer 1) per district/surface; shapes are added with box()/cylinder(). All district
## content is built in WORLD coordinates under a district root that sits at the world origin (identity).
static func solid_body(parent: Node3D, body_name: String, surface: String = "stone") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", surface)
	parent.add_child(body)
	return body


## Box collider: `center` = world centre of the box, rotated by `basis`.
static func box(body: StaticBody3D, center: Vector3, size: Vector3, basis: Basis = Basis()) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	cs.transform = Transform3D(basis, center)     # district roots and their bodies sit at the world origin
	return cs


## Upright cylinder collider standing on `base` (world).
static func cylinder(body: StaticBody3D, base: Vector3, radius: float, h: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = h
	cs.shape = sh
	body.add_child(cs)
	cs.transform = Transform3D(Basis(), base + Vector3(0, h * 0.5, 0))
	return cs


# --- Visual placement ----------------------------------------------------------------------------------

static func mesh_at(parent: Node3D, mesh: Mesh, mat: Material, xform: Transform3D, node_name: String = "", vis_range: float = DECOR_RANGE, shadows: bool = true) -> MeshInstance3D:
	var mi := Props.instance(mesh, mat, vis_range, shadows)
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	mi.transform = xform
	return mi


## MultiMesh from world transforms (the instance node sits at the origin of `parent`'s space, which for the
## district roots is the world origin).
static func multi(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array, node_name: String, vis_range: float = DECOR_RANGE, shadows: bool = true) -> MultiMeshInstance3D:
	var mmi := Props.multimesh(mesh, mat, xforms, node_name, vis_range, shadows)
	parent.add_child(mmi)
	return mmi


static func xform_on_ground(area: Node, p: Vector2, yaw: float = 0.0, scl: float = 1.0, lift: float = 0.0, tilt_deg: Vector2 = Vector2.ZERO) -> Transform3D:
	var b := Basis(Vector3.UP, yaw)
	if tilt_deg != Vector2.ZERO:
		b = b * Basis.from_euler(Vector3(deg_to_rad(tilt_deg.x), 0.0, deg_to_rad(tilt_deg.y)))
	return Transform3D(b.scaled(Vector3.ONE * scl), ground(area, p, lift))


## A disc lying on the terrain (vertices follow height_at + lift), local to its centre. UV.x = r / radius.
static func draped_disc(area: Node, center: Vector2, radius: float, lift: float, rings: int = 3, segs: int = 20) -> ArrayMesh:
	var h0 := height(area, center)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(0, lift, 0))
	uvs.append(Vector2(0, 0))
	normals.append(Vector3.UP)
	for r in range(1, rings + 1):
		var rr := radius * float(r) / float(rings)
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var wob := 1.0 + 0.06 * sin(a * 3.0 + radius) if r == rings else 1.0
			var p := Vector2(cos(a), sin(a)) * rr * wob
			var y := height(area, center + p) - h0 + lift
			verts.append(Vector3(p.x, y, p.y))
			uvs.append(Vector2(float(r) / float(rings), float(s) / float(segs)))
			normals.append(Vector3.UP)
	for s in segs:
		var a := 1 + s
		var b := 1 + (s + 1) % segs
		idx.append_array(PackedInt32Array([0, b, a]))
	for r in range(1, rings):
		var base0 := 1 + (r - 1) * segs
		var base1 := 1 + r * segs
		for s in segs:
			var a0 := base0 + s
			var a1 := base0 + (s + 1) % segs
			var b0 := base1 + s
			var b1 := base1 + (s + 1) % segs
			idx.append_array(PackedInt32Array([a0, a1, b0, a1, b1, b0]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A strip of `width` along a polyline, draped on the terrain (+lift), in WORLD coordinates (place the mesh
## instance at the origin). UV.x = across (0..1), UV.y = metres along the line (flow stripes read downstream).
static func draped_strip(area: Node, pts: Array, width: float, lift: float, step: float = 0.8) -> ArrayMesh:
	var samples: Array = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		for k in n:
			samples.append(a.lerp(b, float(k) / float(n)))
	samples.append(pts[pts.size() - 1])
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var dist := 0.0
	for i in samples.size():
		var p: Vector2 = samples[i]
		var prev: Vector2 = samples[maxi(i - 1, 0)]
		var nxt: Vector2 = samples[mini(i + 1, samples.size() - 1)]
		var dir := (nxt - prev).normalized()
		if dir.length() < 0.001:
			dir = Vector2(0, 1)
		var side := Vector2(-dir.y, dir.x) * width * 0.5
		if i > 0:
			dist += p.distance_to(prev)
		for s in [-1.0, 1.0]:
			var q: Vector2 = p + side * float(s)
			verts.append(Vector3(q.x, height(area, q) + lift, q.y))
			uvs.append(Vector2(0.0 if s < 0.0 else 1.0, dist))
			normals.append(Vector3.UP)
	for i in range(samples.size() - 1):
		var a0 := i * 2
		idx.append_array(PackedInt32Array([a0, a0 + 1, a0 + 2, a0 + 1, a0 + 3, a0 + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# --- Harvest nodes -----------------------------------------------------------------------------------------

## A custom visual per data kind (resource_node hides the child "Berries" when a bush-like kind is picked).
static func harvest_visual(kind: String, variant: int) -> Node3D:
	var root := Node3D.new()
	var prop := Art.prop_material()
	match kind:
		"pumpkin_vine":
			root.add_child(_mi(Art.vine_patch(variant % 3), Art.sway_material(0.03, 0.4), "Leaves"))
			var fruit := Node3D.new()
			fruit.name = "Berries"
			root.add_child(fruit)
			var body := _mi(Art.pumpkin_body(variant % 3, Art.PUMPKIN_DEEP, Art.PUMPKIN_PALE if variant % 2 == 0 else Art.PUMPKIN), prop, "Pumpkin")
			body.scale = Vector3.ONE * 0.34
			fruit.add_child(body)
			var stem := _mi(Art.pumpkin_stem(false), prop, "Stem")
			stem.position = Vector3(0, 0.34 * Art.pumpkin_top(variant % 3), 0)
			stem.scale = Vector3.ONE * 0.34
			fruit.add_child(stem)
			root.set_meta("interact_radius", 0.95)
			root.set_meta("interact_y", 0.4)
			root.set_meta("fx_height", 0.5)
		"roseberry_bush":
			root.add_child(_mi(Art.hedge(variant % 3), Art.sway_material(0.025, 1.4), "Leaves"))
			root.add_child(_mi(Art.berry_clusters(variant % 3, Art.ROSEBERRY), Art.berry_material(), "Berries"))
			root.set_meta("interact_radius", 1.1)
			root.set_meta("interact_y", 0.6)
			root.set_meta("fx_height", 0.9)
		"moonpetal_patch":
			root.add_child(_mi(Art.moonflower_leaves(variant % 3), Art.soft_material(), "Leaves"))
			var petals := _mi(Art.moonflower_petals(variant % 3), Art.tinted(Art.MOONPETAL, 0.45, 0.5), "Berries")
			root.add_child(petals)
			root.set_meta("interact_radius", 0.7)
			root.set_meta("interact_y", 0.35)
			root.set_meta("fx_height", 0.45)
		"sugarcap_patch":
			var mound := _mi(Art.moss_mound(variant % 3), Art.soft_material(), "Moss")
			root.add_child(mound)
			var caps := _mi(Art.sugarcap_caps(variant % 3), Art.prop_material(), "Berries")
			root.add_child(caps)
			root.set_meta("interact_radius", 0.75)
			root.set_meta("interact_y", 0.3)
			root.set_meta("fx_height", 0.35)
		"sap_stump":
			# Only the resin (bark beads + the full pail) is the node's visual: it hides while the sap gathers
			# again. The stump, spout, pail and its collider are decor (sap_stump_decor), so the stump stays.
			root.add_child(_mi(Art.sap_resin(variant % 3), Art.resin_material(), "Resin"))
			root.set_meta("interact_radius", 0.95)
			root.set_meta("interact_y", 0.45)
			root.set_meta("fx_height", 0.7)
		"sunflax_patch":
			root.add_child(_mi(Art.sunflax_stems(variant % 3), Art.sunflax_material(), "Stems"))
			root.add_child(_mi(Art.sunflax_heads(variant % 3), Art.sunflax_material(), "Heads"))
			root.set_meta("interact_radius", 0.7)
			root.set_meta("interact_y", 0.45)
			root.set_meta("fx_height", 0.7)
	root.set_meta("solid", "none")
	NV.set_visibility_range(root, 80.0)
	return root


static func _mi(mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = node_name
	return mi


## Places one renewable harvest node from a Data.NODES entry (data kinds of data/sources.gd; the shared
## resource_node owns drops, depletion and respawn). Returns the node.
static func harvest_node(parent: Node3D, area: Node, entry: Dictionary) -> Node3D:
	var id := String(entry["id"])
	var kind := String(entry["kind"])
	var pos: Vector2 = entry["pos"]
	var variant := node_variant(id)
	var params := {"node_id": id, "kind": kind, "visual": harvest_visual(kind, variant), "seed": variant,
		"yaw": node_yaw_deg(id)}
	if kind == "sap_stump":
		params["fx"] = "copper"          # amber droplets, not leaves, when the pail is emptied
	# The real region registers district nodes itself (reach_world.add_resource -> resource_ids(), map, QA).
	if area != null and is_instance_valid(area) and area.has_method("add_resource"):
		var rn: Variant = area.add_resource(params, ground(area, pos))
		if rn is Node3D:
			(rn as Node3D).set_meta("west_kind", kind)
			return rn
	var n: Node3D = ResourceNodeScript.new()
	n.setup(params)
	n.name = id
	n.set_meta("west_kind", kind)
	n.position = ground(area, pos)
	parent.add_child(n)
	return n


## Stable per-id look variant and yaw (degrees) of a harvest node (the stump decor reuses them to line up).
static func node_variant(id: String) -> int:
	return posmod(hash(id), 7)


static func node_yaw_deg(id: String) -> float:
	return float(posmod(hash(id + "|yaw"), 360))


## The permanent part of a district's sap stumps (Data.NODES kind "sap_stump"): one MultiMesh per look variant
## (stump + ribbon mark + spout + pail) and a solid cylinder each, lined up with the harvest node's own yaw.
static func sap_stump_decor(parent: Node3D, solids: StaticBody3D, area: Node, district: String) -> void:
	var by_variant: Dictionary = {}
	for e in Data.nodes_in(district):
		if String(e["kind"]) != "sap_stump":
			continue
		var id := String(e["id"])
		var v := node_variant(id) % 3
		if not by_variant.has(v):
			by_variant[v] = []
		var g := ground(area, e["pos"])
		(by_variant[v] as Array).append(Transform3D(Basis(Vector3.UP, deg_to_rad(node_yaw_deg(id))), g + Vector3(0, -0.04, 0)))
		if solids != null:
			cylinder(solids, g - Vector3(0, 0.05, 0), Art.STUMP_R, 0.7)
	for v2 in by_variant:
		multi(parent, Art.sap_stump(int(v2)), Art.prop_material(), by_variant[v2], "SapStumps_%d" % int(v2), DECOR_RANGE)


# --- Enemies -------------------------------------------------------------------------------------------------

## True when EnemyFactory can build this enemy id now (the Chapter Two enemy scripts arrive in a later wave).
static func enemy_available(enemy_id: String) -> bool:
	if availability_override.has(enemy_id):
		return bool(availability_override[enemy_id])
	# Registered AND its script exists and compiles (a broken script would otherwise warn on every spawn tick).
	return Factory.can_spawn(enemy_id)


## Creates the EnemySpawner of Data.SPAWNERS[spawner_id] (null - and nothing spawned or warned every tick -
## when the enemy script is missing). `enemy_override` lets tests run the real flow with an existing enemy.
static func spawner(parent: Node3D, area: Node, spawner_id: String, enemy_override: String = "") -> Node3D:
	var d: Dictionary = Data.SPAWNERS[spawner_id]
	var enemy := enemy_override if enemy_override != "" else String(d["enemy"])
	if not enemy_available(enemy):
		return null
	var sp: Node3D = SpawnerScript.new()
	var params := {"enemy": enemy, "count": int(d["count"]), "radius": float(d["radius"]),
		"respawn_minutes": float(d["respawn_minutes"]), "spawner_id": spawner_id}
	for k in ["quest_flag_on_clear", "clear_message", "min_player_distance", "wander_radius"]:
		if d.has(k):
			params[k] = d[k]
	sp.setup(params)
	sp.name = spawner_id
	sp.position = ground(area, d["pos"], 0.05)
	parent.add_child(sp)
	return sp
