extends RefCounted
## Tiny chunky 3D models for items lying in the world (pickups), chosen by the item's "icon" id
## and tinted with its "color" (data/items.gd). About 0.3-0.45 m, outlined, readable from afar.
##   const ItemVisual := preload("res://src/world/common/item_visual.gd")
##   var v: Node3D = ItemVisual.build("berries")

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const OUTLINE := 0.012


static func _m(c: Color, opts: Dictionary = {}) -> Material:
	return Mat.outlined(Mat.toon(c, opts), OUTLINE)


static func build(item_id: String) -> Node3D:
	var d: Dictionary = ItemDB.item(item_id)
	var icon := String(d.get("icon", "unknown"))
	var col: Color = d.get("color", Color.WHITE)
	var root := Node3D.new()
	root.name = "ItemVisual"
	match icon:
		"log":
			for i in 2:
				var lg := Kit.cylinder(0.085, 0.095, 0.38, _m(Palette.BARK), 10)
				Kit.add(root, lg, Vector3(0, 0.09 + i * 0.15, (i - 0.5) * 0.06), Vector3(0, i * 35.0, 90))
				var cap := Kit.cylinder(0.075, 0.075, 0.01, Mat.toon(Palette.WOOD_LIGHT), 10)
				Kit.add(lg, cap, Vector3(0, 0.19, 0))
		"stone":
			Kit.add(root, Kit.blob(0.14, _m(col), 61, 0.25, 0.7, 2), Vector3(0, 0.1, 0))
			Kit.add(root, Kit.blob(0.1, _m(col.lightened(0.1)), 62, 0.25, 0.7, 2), Vector3(0.1, 0.2, 0.03))
		"fiber":
			for i in 5:
				var a := float(i) / 5.0 * TAU
				Kit.add(root, Kit.cylinder(0.018, 0.025, 0.42, _m(col.lerp(Palette.MEADOW_GOLD, float(i) * 0.1)), 5), Vector3(cos(a) * 0.04, 0.12, sin(a) * 0.04), Vector3(0, 0, 70 + i * 4))
			Kit.add(root, Kit.torus(0.045, 0.07, _m(Palette.WOOD)), Vector3(0, 0.12, 0), Vector3(0, 0, 70))
		"berries":
			var pts := [Vector3(0, 0.08, 0), Vector3(0.09, 0.07, 0.04), Vector3(-0.08, 0.07, 0.05), Vector3(0.02, 0.07, -0.09), Vector3(0.01, 0.17, 0.01)]
			for p in pts:
				Kit.add(root, Kit.sphere(0.075, _m(col, {"specular": 0.5, "rim": 0.5}), 8, 12), p)
			Kit.add(root, Kit.blob(0.08, _m(Palette.FOLIAGE), 63, 0.2, 0.3, 1), Vector3(0.02, 0.25, 0))
		"ore":
			Kit.add(root, Kit.blob(0.16, _m(Palette.STONE_DARK), 64, 0.3, 0.8, 2), Vector3(0, 0.13, 0))
			for i in 3:
				var a := float(i) * 2.1
				Kit.add(root, Kit.blob(0.06, _m(col, {"emission": col, "emission_energy": 0.4, "specular": 0.6}), 65 + i, 0.3, 0.8, 1), Vector3(cos(a) * 0.13, 0.17 + i * 0.03, sin(a) * 0.13))
		"seeds":
			Kit.add(root, Kit.blob(0.15, _m(Palette.CLOTH_CREAM), 66, 0.12, 0.9, 2), Vector3(0, 0.14, 0))
			Kit.add(root, Kit.cylinder(0.04, 0.07, 0.09, _m(Palette.CLOTH_CREAM), 8), Vector3(0, 0.3, 0))
			Kit.add(root, Kit.torus(0.05, 0.075, _m(Palette.CLOTH_RED)), Vector3(0, 0.27, 0))
			for i in 3:
				Kit.add(root, Kit.sphere(0.03, _m(col), 4, 6), Vector3(0.11 - i * 0.05, 0.05, 0.13))
		"root":
			Kit.add(root, Kit.cylinder(0.11, 0.0, 0.34, _m(col), 10), Vector3(0, 0.14, 0), Vector3(0, 0, 70))
			for i in 3:
				Kit.add(root, Kit.cylinder(0.01, 0.025, 0.2, _m(Palette.FOLIAGE), 5), Vector3(-0.2, 0.1, 0), Vector3((i - 1) * 25.0, 0, 70 + i * 10))
		"pebble":
			Kit.add(root, Kit.sphere(0.13, _m(col, {"specular": 0.9, "rim": 0.8}), 12, 16), Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
		"mushroom":
			Kit.add(root, Kit.cylinder(0.035, 0.05, 0.2, _m(Color("eef3e2")), 8), Vector3(0, 0.1, 0))
			Kit.add(root, Kit.sphere(0.13, _m(col, {"emission": col, "emission_energy": 1.5}), 8, 12), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
		"silk":
			if bool(Settings.get_value("arachnophobia")):
				Kit.add(root, Kit.cylinder(0.1, 0.1, 0.22, _m(Color("d9ccb2")), 12), Vector3(0, 0.13, 0))
				Kit.add(root, Kit.cylinder(0.13, 0.13, 0.03, _m(Palette.WOOD)), Vector3(0, 0.025, 0))
				Kit.add(root, Kit.cylinder(0.13, 0.13, 0.03, _m(Palette.WOOD)), Vector3(0, 0.255, 0))
			else:
				for i in 4:
					var a := float(i) * 1.7
					Kit.add(root, Kit.blob(0.1, Mat.toon(col, {"emission": col, "emission_energy": 0.2, "rim": 0.8}), 67 + i, 0.4, 0.8, 1), Vector3(cos(a) * 0.08, 0.12 + i * 0.03, sin(a) * 0.08))
		"crystal":
			for i in 3:
				var h := 0.3 - i * 0.07
				Kit.add(root, Kit.cylinder(0.0, 0.06, h, _m(col, {"emission": col, "emission_energy": 0.9, "specular": 0.8}), 6), Vector3((i - 1) * 0.07, h * 0.5, 0), Vector3(0, 0, (i - 1) * 20.0))
		"axe", "pickaxe":
			var handle := Kit.cylinder(0.025, 0.03, 0.55, _m(Palette.WOOD), 6)
			Kit.add(root, handle, Vector3(0, 0.05, 0), Vector3(0, 0, 90))
			if icon == "axe":
				Kit.add(root, Kit.box(Vector3(0.12, 0.05, 0.18), _m(col)), Vector3(0.22, 0.05, 0.08))
			else:
				Kit.add(root, Kit.cylinder(0.02, 0.035, 0.36, _m(col), 6), Vector3(0.24, 0.05, 0), Vector3(90, 0, 0))
		"sword":
			Kit.add(root, Kit.box(Vector3(0.44, 0.02, 0.07), _m(col, {"specular": 0.7})), Vector3(0.12, 0.04, 0))
			Kit.add(root, Kit.box(Vector3(0.03, 0.04, 0.2), _m(Palette.WOOD_DARK)), Vector3(-0.1, 0.04, 0))
			Kit.add(root, Kit.cylinder(0.02, 0.02, 0.14, _m(Palette.WOOD), 6), Vector3(-0.18, 0.04, 0), Vector3(0, 0, 90))
		"lantern":
			Kit.add(root, Kit.cylinder(0.08, 0.1, 0.03, _m(Palette.WOOD_DARK), 10), Vector3(0, 0.015, 0))
			Kit.add(root, Kit.cylinder(0.075, 0.075, 0.16, Mat.glow(Palette.LANTERN_GLOW, 2.0), 10), Vector3(0, 0.11, 0))
			Kit.add(root, Kit.cylinder(0.02, 0.1, 0.07, _m(Palette.WOOD_DARK), 10), Vector3(0, 0.22, 0))
			Kit.add(root, Kit.torus(0.03, 0.05, _m(Palette.STONE_DARK)), Vector3(0, 0.28, 0), Vector3(90, 0, 0))
		"snack":
			Kit.add(root, Kit.box(Vector3(0.24, 0.07, 0.12), _m(col)), Vector3(0, 0.05, 0))
			Kit.add(root, Kit.box(Vector3(0.1, 0.075, 0.125), _m(Palette.CLOTH_CREAM)), Vector3(0, 0.05, 0))
		"stew":
			Kit.add(root, Kit.cylinder(0.15, 0.1, 0.1, _m(Palette.WOOD), 12), Vector3(0, 0.05, 0))
			Kit.add(root, Kit.cylinder(0.135, 0.135, 0.01, Mat.toon(col), 12), Vector3(0, 0.098, 0))
		"skewer":
			Kit.add(root, Kit.cylinder(0.01, 0.01, 0.46, _m(Palette.WOOD_LIGHT), 5), Vector3(0, 0.06, 0), Vector3(0, 0, 90))
			for i in 3:
				Kit.add(root, Kit.sphere(0.055, _m(col, {"emission": col, "emission_energy": 0.4}), 6, 8), Vector3(-0.1 + i * 0.1, 0.06, 0))
		"key":
			Kit.add(root, Kit.torus(0.04, 0.075, _m(col, {"specular": 0.7})), Vector3(-0.14, 0.04, 0), Vector3(90, 0, 0))
			Kit.add(root, Kit.box(Vector3(0.26, 0.03, 0.03), _m(col, {"specular": 0.7})), Vector3(0.04, 0.04, 0))
			Kit.add(root, Kit.box(Vector3(0.03, 0.03, 0.07), _m(col)), Vector3(0.14, 0.04, 0.04))
		"heartseed":
			Kit.add(root, Kit.sphere(0.13, Mat.glow(Palette.HEART_GLOW, 2.2), 12, 16), Vector3(0, 0.16, 0), Vector3.ZERO, Vector3(1, 1.2, 1))
			Kit.add(root, Kit.blob(0.07, _m(Palette.FOLIAGE_LIGHT), 68, 0.2, 0.4, 1), Vector3(0, 0.32, 0))
		_:
			# Wrapped parcel for placeables and anything else.
			Kit.add(root, Kit.box(Vector3(0.28, 0.2, 0.28), _m(col)), Vector3(0, 0.1, 0))
			Kit.add(root, Kit.box(Vector3(0.29, 0.205, 0.05), _m(Palette.CLOTH_CREAM)), Vector3(0, 0.1, 0))
			Kit.add(root, Kit.box(Vector3(0.05, 0.205, 0.29), _m(Palette.CLOTH_CREAM)), Vector3(0, 0.1, 0))
			Kit.add(root, Kit.torus(0.02, 0.05, _m(Palette.CLOTH_RED)), Vector3(0, 0.22, 0), Vector3(90, 45, 0))
	return root
