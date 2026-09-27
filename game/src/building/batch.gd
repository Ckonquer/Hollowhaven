extends RefCounted
## Collects [mesh, transform, colour] parts and bakes them into ONE vertex-coloured ArrayMesh
## (one draw call). Used by every structure model; render with ModelUtil.vc_mat()/vc_outlined().
##   var b := Batch.new(); b.rbox(Vector3(1, 0.1, 1), Vector3(0, 0.5, 0), Palette.WOOD); var mesh := b.bake()

const Shapes := preload("res://src/building/shapes.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var parts: Array = []

func add(mesh: Mesh, xform: Transform3D, color: Color) -> void:
	parts.append([mesh, xform, color])

## Local transform: scale first (in the part's own axes), then rotate (degrees), then move.
static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var r := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(r * Basis.from_scale(scl), pos)

## Rounded box centred at pos.
func rbox(size: Vector3, pos: Vector3, color: Color, radius: float = 0.03, rot_deg: Vector3 = Vector3.ZERO, smooth: bool = true) -> void:
	add(Shapes.rounded_box(size, radius, smooth), xf(pos, rot_deg), color)

func cyl(top: float, bottom: float, height: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, segments: int = 14) -> void:
	# thin rods don't need many sides
	var r := maxf(top, bottom)
	var seg := segments if r >= 0.05 else mini(segments, 8 if r >= 0.02 else 6)
	add(Shapes.prim_cylinder(top, bottom, height, seg), xf(pos, rot_deg), color)

## Sphere with tessellation scaled to its on-screen size (largest axis after scaling).
func sphere(radius: float, pos: Vector3, color: Color, scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var size := radius * maxf(scl.x, maxf(scl.y, scl.z))
	var mesh: Mesh
	if size < 0.04:
		mesh = Shapes.prim_sphere(radius, 4, 6)
	elif size < 0.065:
		mesh = Shapes.prim_sphere(radius, 5, 8)
	elif size < 0.1:
		mesh = Shapes.prim_sphere(radius, 6, 10)
	elif size < 0.2:
		mesh = Shapes.prim_sphere(radius, 8, 12)
	else:
		mesh = Shapes.prim_sphere(radius, 10, 16)
	add(mesh, xf(pos, rot_deg, scl), color)

func torus(inner: float, outer: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var rings := 24 if outer >= 0.15 else 14
	add(Shapes.prim_torus(inner, outer, rings, 8 if outer >= 0.15 else 6), xf(pos, rot_deg, scl), color)

func prism(size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, left_to_right: float = 0.5) -> void:
	add(Shapes.prim_prism(size, left_to_right), xf(pos, rot_deg), color)

func blob(radius: float, pos: Vector3, color: Color, seed_value: int = 0, lumpiness: float = 0.2, squash: float = 1.0, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	add(Kit.blob_mesh(radius, seed_value, lumpiness, squash, 2), xf(pos, rot_deg, scl), color)

## Heart (square rotated 45 deg + two lobes) facing +Z. size ~ total width.
func heart(size: float, pos: Vector3, color: Color, depth: float = 0.0, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var s := size / 1.707
	var d: float = depth if depth > 0.0 else s * 0.55
	var base := xf(pos, rot_deg)
	add(Shapes.rounded_box(Vector3(s, s, d), minf(s, d) * 0.3), base * xf(Vector3(0, -s * 0.12, 0), Vector3(0, 0, 45)), color)
	var lobe := Shapes.prim_cylinder(s * 0.5, s * 0.5, d, 16)
	var off := s / (2.0 * sqrt(2.0))
	add(lobe, base * xf(Vector3(-off, off - s * 0.12, 0), Vector3(90, 0, 0)), color)
	add(lobe, base * xf(Vector3(off, off - s * 0.12, 0), Vector3(90, 0, 0)), color)

## Puffy 3D heart (for glowing bulbs).
func heart_round(size: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var s := size / 1.707
	var base := xf(pos, rot_deg)
	add(Shapes.rounded_box(Vector3(s, s, s * 0.8), s * 0.3), base * xf(Vector3(0, -s * 0.12, 0), Vector3(0, 0, 45)), color)
	var off := s / (2.0 * sqrt(2.0))
	add(Shapes.prim_sphere(s * 0.52), base * xf(Vector3(-off, off - s * 0.12, 0), Vector3.ZERO, Vector3(1, 1, 0.8)), color)
	add(Shapes.prim_sphere(s * 0.52), base * xf(Vector3(off, off - s * 0.12, 0), Vector3.ZERO, Vector3(1, 1, 0.8)), color)

func bake() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var mesh: Mesh = p[0]
		var t: Transform3D = p[1]
		# Vertex colours reach the toon shader unconverted: bake palette (sRGB) colours as linear.
		var col: Color = (p[2] as Color).srgb_to_linear()
		var nb := t.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base := verts.size()
			var flip := t.basis.determinant() < 0.0
			for i in v.size():
				verts.append(t * v[i])
				norms.append((nb * n[i]).normalized() if i < n.size() else Vector3.UP)
				cols.append(col)
			if ix.is_empty():
				for i in v.size():
					idx.append(base + i)
			else:
				for i in range(0, ix.size(), 3):
					if flip:
						idx.append_array([base + ix[i], base + ix[i + 2], base + ix[i + 1]])
					else:
						idx.append_array([base + ix[i], base + ix[i + 1], base + ix[i + 2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if not verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
