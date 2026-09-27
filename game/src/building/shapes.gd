extends RefCounted
## Cached procedural meshes for structure models: primitives, rounded boxes (soft bevelled edges with
## smooth normals), half cylinders (chest lids), arch rings (doorways) and sparkle stars.
## Godot front faces are wound clockwise; _tri_out() orders every triangle from its outward normal.

static var _cache: Dictionary = {}


# --- Primitive meshes (cached) --------------------------------------------------------------------

static func prim_cylinder(top: float, bottom: float, height: float, segments: int = 14) -> Mesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top, bottom, height, segments]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_cache[key] = m
	return _cache[key]


static func prim_sphere(radius: float, rings: int = 10, segments: int = 16) -> Mesh:
	var key := "sph|%.3f|%d|%d" % [radius, rings, segments]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.rings = rings
		m.radial_segments = segments
		_cache[key] = m
	return _cache[key]


static func prim_torus(inner: float, outer: float, rings: int = 24, ring_segments: int = 8) -> Mesh:
	var key := "tor|%.3f|%.3f|%d|%d" % [inner, outer, rings, ring_segments]
	if not _cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = rings
		m.ring_segments = ring_segments
		_cache[key] = m
	return _cache[key]


static func prim_prism(size: Vector3, left_to_right: float = 0.5) -> Mesh:
	var key := "pri|%s|%.2f" % [size, left_to_right]
	if not _cache.has(key):
		var m := PrismMesh.new()
		m.size = size
		m.left_to_right = left_to_right
		_cache[key] = m
	return _cache[key]


# --- Custom soft shapes -------------------------------------------------------------------------------

## Box with rounded (bevelled) edges and smooth normals. Soft storybook look + clean outlines.
static func rounded_box(size: Vector3, radius: float, smooth: bool = true) -> ArrayMesh:
	var key := "rbox|%.3f|%.3f|%.3f|%.3f|%s" % [size.x, size.y, size.z, radius, smooth]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.95)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	var lo := -h + Vector3.ONE * r
	var hi := h - Vector3.ONE * r
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var cu := _bevel_coords(absf(h.dot(u)), r, smooth)
		var cv := _bevel_coords(absf(h.dot(v)), r, smooth)
		var base := verts.size()
		var d: float = absf(h.dot(n))
		for i in cu.size():
			for j in cv.size():
				var p: Vector3 = n * d + u * float(cu[i]) + v * float(cv[j])
				if r > 0.0005:
					var inner := p.clamp(lo, hi)
					var dir := p - inner
					dir = dir.normalized() if dir.length() > 0.00001 else n
					verts.append(inner + dir * r)
					norms.append(dir)
				else:
					verts.append(p)
					norms.append(n)
		var cols := cv.size()
		for i in cu.size() - 1:
			for j in cv.size() - 1:
				var a := base + i * cols + j
				var b := base + (i + 1) * cols + j
				var c := base + (i + 1) * cols + j + 1
				var e := base + i * cols + j + 1
				# u x v = n: (a, b, c) is counter-clockwise from outside -> emit clockwise for Godot.
				idx.append_array([a, c, b, a, e, c])
	var m := _array_mesh(verts, norms, idx)
	_cache[key] = m
	return m


static func _bevel_coords(a: float, r: float, smooth: bool = true) -> Array:
	if r <= 0.0005:
		return [-a, a]
	if r < 0.05 or not smooth:
		# small bevels: one chamfer row each side (smooth normals keep it looking round)
		return [-a, -a + r, a - r, a]
	return [-a, -a + r * 0.45, -a + r, a - r, a - r * 0.45, a]


## Half cylinder along X (length 1, radius 1), flat side down at y = 0, dome up. Scale to size.
static func half_cylinder(segments: int = 12) -> ArrayMesh:
	var key := "halfcyl|%d" % segments
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	# Curved surface
	for i in segments + 1:
		var a := PI * float(i) / float(segments)
		var n := Vector3(0.0, sin(a), cos(a))
		verts.append(Vector3(-0.5, n.y, n.z))
		norms.append(n)
		verts.append(Vector3(0.5, n.y, n.z))
		norms.append(n)
	for i in segments:
		var a := i * 2
		_tri_out(idx, verts, a, a + 1, a + 3, norms[a])
		_tri_out(idx, verts, a, a + 3, a + 2, norms[a])
	# End caps
	for side in [-1.0, 1.0]:
		var c := verts.size()
		verts.append(Vector3(0.5 * side, 0.0, 0.0))
		norms.append(Vector3(side, 0, 0))
		for i in segments + 1:
			var a := PI * float(i) / float(segments)
			verts.append(Vector3(0.5 * side, sin(a), cos(a)))
			norms.append(Vector3(side, 0, 0))
		for i in segments:
			_tri_out(idx, verts, c, c + 1 + i, c + 2 + i, Vector3(side, 0, 0))
	# Bottom
	var b := verts.size()
	for p in [Vector3(-0.5, 0, -1), Vector3(0.5, 0, -1), Vector3(0.5, 0, 1), Vector3(-0.5, 0, 1)]:
		verts.append(p)
		norms.append(Vector3.DOWN)
	_tri_out(idx, verts, b, b + 1, b + 2, Vector3.DOWN)
	_tri_out(idx, verts, b, b + 2, b + 3, Vector3.DOWN)
	var m := _array_mesh(verts, norms, idx)
	_cache[key] = m
	return m


## Semicircular arch ring in the XY plane (centre at origin, opening down), extruded along Z.
static func arch_ring(inner: float, outer: float, depth: float, segments: int = 16) -> ArrayMesh:
	var key := "arch|%.3f|%.3f|%.3f|%d" % [inner, outer, depth, segments]
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var hz := depth * 0.5
	for side in [1.0, -1.0]:
		var base := verts.size()
		for i in segments + 1:
			var a := PI * float(i) / float(segments)
			var d := Vector3(cos(a), sin(a), 0.0)
			verts.append(d * inner + Vector3(0, 0, hz * side))
			norms.append(Vector3(0, 0, side))
			verts.append(d * outer + Vector3(0, 0, hz * side))
			norms.append(Vector3(0, 0, side))
		for i in segments:
			var k := base + i * 2
			_tri_out(idx, verts, k, k + 1, k + 3, Vector3(0, 0, side))
			_tri_out(idx, verts, k, k + 3, k + 2, Vector3(0, 0, side))
	for radial in [[inner, -1.0], [outer, 1.0]]:
		var rr: float = radial[0]
		var sgn: float = radial[1]
		var base2 := verts.size()
		for i in segments + 1:
			var a := PI * float(i) / float(segments)
			var d := Vector3(cos(a), sin(a), 0.0)
			verts.append(d * rr + Vector3(0, 0, hz))
			norms.append(d * sgn)
			verts.append(d * rr + Vector3(0, 0, -hz))
			norms.append(d * sgn)
		for i in segments:
			var k := base2 + i * 2
			var n: Vector3 = norms[k]
			_tri_out(idx, verts, k, k + 1, k + 3, n)
			_tri_out(idx, verts, k, k + 3, k + 2, n)
	var m := _array_mesh(verts, norms, idx)
	_cache[key] = m
	return m


## Flat 4-point sparkle star in the XY plane facing +Z (billboard particles), radius `radius`.
static func star(radius: float = 0.07) -> ArrayMesh:
	var key := "star|%.3f" % radius
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	norms.append(Vector3.BACK)
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI * 0.5
		var r: float = radius if i % 2 == 0 else radius * 0.32
		verts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
		norms.append(Vector3.BACK)
	for i in 8:
		_tri_out(idx, verts, 0, 1 + i, 1 + (i + 1) % 8, Vector3.BACK)
	var m := _array_mesh(verts, norms, idx)
	_cache[key] = m
	return m


## Adds indices for triangle (a, b, c) wound clockwise as seen from the `outward` side (Godot front face).
static func _tri_out(idx: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, outward: Vector3) -> void:
	var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if g.dot(outward) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func _array_mesh(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
