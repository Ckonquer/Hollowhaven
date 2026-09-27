extends RefCounted
## Procedural mesh helpers for building stylised props and creatures from code.
##   const Kit := preload("res://src/art/mesh_kit.gd")
##   var head := Kit.sphere(0.3, Palette.K_SKIN)                 # MeshInstance3D
##   Kit.add(parent, head, Vector3(0, 1.6, 0))                    # parent it with a local transform
##   var rock := Kit.blob(0.8, Palette.STONE, 7, 0.25)            # lumpy organic mesh (seeded, cached)
## Mesh resources are cached by parameters so repeated props share geometry.

const Mat := preload("res://src/art/mat.gd")

static var _mesh_cache: Dictionary = {}


static func _mi(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material:
		mi.material_override = material
	return mi


static func _mat(color_or_mat) -> Material:
	if color_or_mat is Material:
		return color_or_mat
	return Mat.toon(color_or_mat)


static func sphere(radius: float, color_or_mat, rings: int = 16, segments: int = 24) -> MeshInstance3D:
	var key := "sph|%.3f|%d|%d" % [radius, rings, segments]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.rings = rings
		m.radial_segments = segments
		_mesh_cache[key] = m
	return _mi(_mesh_cache[key], _mat(color_or_mat))


static func capsule(radius: float, height: float, color_or_mat) -> MeshInstance3D:
	var key := "cap|%.3f|%.3f" % [radius, height]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = max(height, radius * 2.0)
		m.radial_segments = 20
		m.rings = 8
		_mesh_cache[key] = m
	return _mi(_mesh_cache[key], _mat(color_or_mat))


static func cylinder(top_radius: float, bottom_radius: float, height: float, color_or_mat, segments: int = 16) -> MeshInstance3D:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top_radius, bottom_radius, height, segments]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top_radius
		m.bottom_radius = bottom_radius
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_mesh_cache[key] = m
	return _mi(_mesh_cache[key], _mat(color_or_mat))


static func box(size: Vector3, color_or_mat) -> MeshInstance3D:
	var key := "box|%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mi(_mesh_cache[key], _mat(color_or_mat))


static func cone(radius: float, height: float, color_or_mat, segments: int = 16) -> MeshInstance3D:
	return cylinder(0.0, radius, height, color_or_mat, segments)


static func torus(inner: float, outer: float, color_or_mat) -> MeshInstance3D:
	var key := "tor|%.3f|%.3f" % [inner, outer]
	if not _mesh_cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 12
		_mesh_cache[key] = m
	return _mi(_mesh_cache[key], _mat(color_or_mat))


static func prism(size: Vector3, color_or_mat) -> MeshInstance3D:
	var key := "pri|%s" % size
	if not _mesh_cache.has(key):
		var m := PrismMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mi(_mesh_cache[key], _mat(color_or_mat))


## Adds `child` under `parent` with a local position / rotation (degrees) / scale. Returns child.
static func add(parent: Node3D, child: Node3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Node3D:
	parent.add_child(child)
	child.position = pos
	child.rotation_degrees = rot_deg
	child.scale = scl
	return child


## Lumpy organic blob: an icosphere displaced by seeded noise. Great for rocks, bushes, clouds,
## foliage clumps and creature bodies. squash scales Y. Returns MeshInstance3D.
static func blob(radius: float, color_or_mat, seed_value: int = 0, lumpiness: float = 0.2, squash: float = 1.0, subdivisions: int = 3) -> MeshInstance3D:
	return _mi(blob_mesh(radius, seed_value, lumpiness, squash, subdivisions), _mat(color_or_mat))


static func blob_mesh(radius: float, seed_value: int = 0, lumpiness: float = 0.2, squash: float = 1.0, subdivisions: int = 3) -> ArrayMesh:
	var key := "blob|%.3f|%d|%.3f|%.3f|%d" % [radius, seed_value, lumpiness, squash, subdivisions]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.3 / max(radius, 0.05)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var ico := _icosphere(subdivisions)
	var verts: PackedVector3Array = ico[0]
	var tris: PackedInt32Array = ico[1]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var d: Vector3 = verts[i]
		var n := noise.get_noise_3dv(d * radius)
		var r := radius * (1.0 + n * lumpiness)
		out[i] = Vector3(d.x * r, d.y * r * squash, d.z * r)
	var normals := PackedVector3Array()
	normals.resize(out.size())
	for t in range(0, tris.size(), 3):
		var a := out[tris[t]]
		var b := out[tris[t + 1]]
		var c := out[tris[t + 2]]
		var fn := (b - a).cross(c - a)
		normals[tris[t]] += fn
		normals[tris[t + 1]] += fn
		normals[tris[t + 2]] += fn
	for i in normals.size():
		var nn := normals[i].normalized()
		if nn.dot(out[i]) < 0.0:   # blobs are star-shaped around the origin: normals point outward
			nn = -nn
		normals[i] = nn
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


## Returns [unit vertices, indices] of an icosphere (counter-clockwise front faces for Godot).
static func _icosphere(subdiv: int) -> Array:
	var key := "ico|%d" % subdiv
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdiv:
		var mid := {}
		var nf := []
		for tri in f:
			var m := []
			for e in 3:
				var a: int = tri[e]
				var b: int = tri[(e + 1) % 3]
				var k := "%d_%d" % [min(a, b), max(a, b)]
				if not mid.has(k):
					v.append(((v[a] + v[b]) * 0.5).normalized())
					mid[k] = v.size() - 1
				m.append(mid[k])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	var verts := PackedVector3Array(v)
	var idx := PackedInt32Array()
	for tri in f:
		# Godot uses clockwise winding for front faces.
		idx.append(tri[0]); idx.append(tri[2]); idx.append(tri[1])
	var res := [verts, idx]
	_mesh_cache[key] = res
	return res


## Adds a simple static collision body with a box/capsule/sphere/cylinder shape to `parent`.
## layer: physics layer bit value (1 = world, 32 = structure ...). Returns the StaticBody3D.
static func static_collider(parent: Node3D, shape: Shape3D, pos: Vector3 = Vector3.ZERO, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.position = pos
	return body
