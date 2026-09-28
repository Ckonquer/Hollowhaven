extends RefCounted
## Large, simple symbol glyphs of the Hushed Works (Kit meshes, facing +Z, about `size` metres tall). Every
## symbol is a distinct silhouette, so they read without colour and without sound. Used by the Bellmaker's
## Floor (leaf / moon / key / flame) and free for the deep module (the Choir's resonators reuse the order).
##   var g: Node3D = Glyphs.build("moon", Mat.glow(Color.WHITE), 0.8)

const Kit := preload("res://src/art/mesh_kit.gd")

const SYMBOLS := ["leaf", "moon", "key", "flame", "water", "bell", "light"]


static func build(symbol: String, m: Material, size: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Glyph_" + symbol
	var s := size
	match symbol:
		"leaf":
			Kit.add(n, Kit.sphere(0.28 * s, m, 8, 12), Vector3(0, 0.08 * s, 0), Vector3(0, 0, 18), Vector3(0.62, 1.2, 0.18))
			Kit.add(n, Kit.box(Vector3(0.04, 0.5, 0.05) * s, m), Vector3(0.02 * s, -0.12 * s, 0.03 * s), Vector3(0, 0, 18))
			for k in 3:
				Kit.add(n, Kit.box(Vector3(0.16, 0.025, 0.05) * s, m), Vector3((0.07 + 0.01 * float(k)) * s, (-0.04 + 0.12 * float(k)) * s, 0.04 * s), Vector3(0, 0, 45))
		"moon":   # a crescent: a disc with a second disc bitten out (drawn as a thick C of beads)
			for k in 11:
				var a := lerpf(-2.3, 2.3, float(k) / 10.0)
				var r := 0.3 * s
				var thick := (0.11 - absf(a) * 0.025) * s
				Kit.add(n, Kit.sphere(maxf(thick, 0.03 * s), m, 6, 8), Vector3(cos(a + PI) * r, sin(a + PI) * r, 0), Vector3.ZERO, Vector3(1, 1, 0.45))
		"key":
			Kit.add(n, Kit.torus(0.08 * s, 0.16 * s, m), Vector3(0, 0.24 * s, 0), Vector3(90, 0, 0))
			Kit.add(n, Kit.box(Vector3(0.07, 0.5, 0.06) * s, m), Vector3(0, -0.12 * s, 0))
			Kit.add(n, Kit.box(Vector3(0.16, 0.06, 0.06) * s, m), Vector3(0.08 * s, -0.3 * s, 0))
			Kit.add(n, Kit.box(Vector3(0.12, 0.06, 0.06) * s, m), Vector3(0.06 * s, -0.18 * s, 0))
		"flame":
			Kit.add(n, Kit.sphere(0.17 * s, m, 8, 10), Vector3(0, -0.1 * s, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
			Kit.add(n, Kit.cone(0.15 * s, 0.42 * s, m, 10), Vector3(0, 0.16 * s, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
			Kit.add(n, Kit.cone(0.07 * s, 0.22 * s, m, 8), Vector3(0.1 * s, 0.08 * s, 0), Vector3(0, 0, -25), Vector3(1, 1, 0.4))
		"water":
			Kit.add(n, Kit.sphere(0.16 * s, m, 8, 10), Vector3(0, -0.07 * s, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
			Kit.add(n, Kit.cone(0.13 * s, 0.26 * s, m, 8), Vector3(0, 0.15 * s, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
		"bell":
			Kit.add(n, Kit.cone(0.2 * s, 0.36 * s, m, 10), Vector3(0, 0.02 * s, 0), Vector3.ZERO, Vector3(1, 1, 0.45))
			Kit.add(n, Kit.sphere(0.06 * s, m, 6, 8), Vector3(0, -0.2 * s, 0))
		_:
			Kit.add(n, Kit.sphere(0.14 * s, m, 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.4))
			for k in 8:
				var a := TAU * float(k) / 8.0
				Kit.add(n, Kit.box(Vector3(0.05, 0.12, 0.04) * s, m), Vector3(sin(a) * 0.24 * s, cos(a) * 0.24 * s, 0), Vector3(0, 0, -rad_to_deg(a)))
	return n
