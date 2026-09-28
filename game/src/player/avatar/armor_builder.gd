extends RefCounted
## "Show equipped armor" (GameState.wardrobe.show_armor): simple tier-coloured armor pieces drawn over or
## instead of the garment of their slot. Purely visual - the stats come from src/core/stats.gd; nothing here
## changes collision, speed or reach. Colours come from the armor item (data/items.gd `color`), the shape from
## its icon / tier: head = hood (cloth tiers) or helm (metal tiers), body = quilted vest or scale mail with
## pauldrons, boots = armored boots (replace the shoes).
##   build_head(ctx)  -> {"hull": "all"}      (instead of the hat; hides the crown hair like a hat)
##   build_body(ctx)  -> {}                   (over the upper garment)
##   build_boots(ctx) -> {}                   (instead of the shoes)
## ctx["id"] = the armor item id.

const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")


## Armor look of an item: {color, metal (bool), tier, icon}.
static func style(item_id: String) -> Dictionary:
	var it := ItemDB.item(item_id)
	var tier := ItemDB.item_tier(item_id)
	var c: Variant = it.get("color", Color("d9c49a"))
	var icon := String(it.get("icon", ""))
	var metal := tier >= 3 or icon == "helm" or icon == "mail"
	return {"color": c if c is Color else Color("d9c49a"), "metal": metal, "tier": tier, "icon": icon}


static func _mat(st: Dictionary, c: Color) -> Material:
	return AKit.metal(c) if bool(st["metal"]) else AKit.m(c)


static func build_head(ctx: Dictionary) -> Dictionary:
	var st := style(String(ctx["id"]))
	var c: Color = st["color"]
	var hc: Node3D = ctx["box"].call("head_c")
	var n := AKit.node(hc, Vector3.ZERO, "ArmorHead")
	if bool(st["metal"]):
		# rounded helm sitting above the brows, band with rivets, a crest on moonsteel
		AKit.part(n, Kit.sphere(0.285, _mat(st, c), 18, 26), Vector3(0, 0.14, -0.06), Vector3.ZERO, Vector3(1.06, 0.75, 1.02))
		AKit.part(n, Kit.torus(0.262, 0.29, _mat(st, AKit.shade(c, 0.18))), Vector3(0, 0.1, -0.05), Vector3(-6, 0, 0), Vector3(1.03, 1.3, 0.98))
		for k in 4:
			var a := lerpf(-0.9, 0.9, float(k) / 3.0)
			AKit.part(n, Kit.sphere(0.012, AKit.flat(AKit.lighten(c, 0.35)), 6, 8), Vector3(sin(a) * 0.285, 0.105 + 0.02 * cos(a), cos(a) * 0.27 - 0.05), Vector3.ZERO, Vector3.ONE, false)
		if int(st["tier"]) >= 4:
			var crest := MeshInstance3D.new()
			crest.mesh = AKit.arc_mesh(0.07, 0.014, 3.4)
			crest.material_override = AKit.m(AKit.lighten(c, 0.45), true, 0.006)
			AKit.part(n, crest, Vector3(0, 0.34, -0.02), Vector3(0, 90, 180))
	else:
		# quilted hood framing the face (open front), a little peak at the back
		var cloth := _mat(st, c)
		AKit.part(n, Kit.sphere(0.29, cloth, 18, 26), Vector3(0, 0.07, -0.1), Vector3.ZERO, Vector3(1.06, 1.0, 0.98))
		var rim := MeshInstance3D.new()
		rim.mesh = AKit.arc_mesh(0.215, 0.022, 3.8)
		rim.material_override = AKit.m(AKit.shade(c, 0.15), true, 0.008)
		AKit.part(n, rim, Vector3(0, 0.215, 0.17), Vector3(-8, 0, 180))
		AKit.part(n, Kit.sphere(0.08, cloth, 10, 14), Vector3(0, 0.3, -0.25), Vector3(-30, 0, 0), Vector3(0.8, 0.6, 1.3))
		if int(st["tier"]) >= 2:
			for k in 3:
				var a := lerpf(-0.8, 0.8, float(k) / 2.0)
				AKit.part(n, Kit.sphere(0.013, AKit.metal(Palette.COPPER, 0.005), 6, 8), Vector3(sin(a) * 0.2, 0.2 * cos(a) + 0.005, 0.2), Vector3.ZERO, Vector3.ONE, false)
	return {"hull": "all"}


static func build_body(ctx: Dictionary) -> Dictionary:
	var st := style(String(ctx["id"]))
	var c: Color = st["color"]
	var box: Callable = ctx["box"]
	var spine: Node3D = box.call("spine")
	if bool(st["metal"]):
		var metal := _mat(st, c)
		AKit.part(spine, Kit.capsule(0.19, 0.42, metal), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
		var rows := AKit.metal(AKit.lighten(c, 0.18))
		for k in 3:
			AKit.part(spine, Kit.torus(0.18, 0.198, rows), Vector3(0, 0.05 + 0.08 * float(k), 0), Vector3.ZERO, Vector3(1.02, 1.3, 0.9))
		for side in 2:
			var sh: Node3D = box.call("sh%d" % side)
			AKit.part(sh, Kit.sphere(0.088, metal, 12, 16), Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1.15, 0.72, 1.15))
			AKit.part(sh, Kit.torus(0.078, 0.096, rows), Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(1.1, 1.0, 1.1))
		if int(st["tier"]) >= 4:
			var moon := MeshInstance3D.new()
			moon.mesh = AKit.arc_mesh(0.035, 0.009, 3.6)
			moon.material_override = AKit.flat(AKit.lighten(c, 0.5))
			AKit.part(spine, moon, Vector3(0, 0.25, 0.172), Vector3(0, 0, 200), Vector3.ONE, false)
	else:
		var cloth := _mat(st, c)
		AKit.part(spine, Kit.capsule(0.186, 0.4, cloth), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
		AKit.part(spine, Kit.cylinder(0.182, 0.205, 0.08, cloth), Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
		var quilt := AKit.m(AKit.shade(c, 0.14), false)
		for k in 2:
			AKit.part(spine, Kit.torus(0.18, 0.192, quilt), Vector3(0, 0.1 + 0.1 * float(k), 0), Vector3.ZERO, Vector3(1.01, 1.2, 0.89), false)
		if int(st["tier"]) >= 2:
			var plate := AKit.metal(Palette.COPPER, 0.006)
			for k in 4:
				var x := -0.06 if k % 2 == 0 else 0.06
				AKit.part(spine, Kit.box(Vector3(0.06, 0.05, 0.012), plate), Vector3(x, 0.12 if k < 2 else 0.22, 0.162), Vector3(-6, 0, 0))
	return {}


static func build_boots(ctx: Dictionary) -> Dictionary:
	var st := style(String(ctx["id"]))
	var c: Color = st["color"]
	var box: Callable = ctx["box"]
	var shaft := _mat(st, c)
	var cap := AKit.metal(AKit.shade(c, 0.1) if bool(st["metal"]) else Palette.COPPER)
	for side in 2:
		var knee: Node3D = box.call("knee%d" % side)
		AKit.part(knee, Kit.cylinder(0.082, 0.088, 0.21, shaft), Vector3(0, -0.215, 0))
		AKit.part(knee, Kit.torus(0.074, 0.098, AKit.m(AKit.shade(c, 0.16))), Vector3(0, -0.11, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
		if int(st["tier"]) >= 2:
			AKit.part(knee, Kit.sphere(0.092, cap), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(1.0, 0.64, 1.42))
		else:
			AKit.part(knee, Kit.sphere(0.09, shaft), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(1.0, 0.64, 1.42))
		if bool(st["metal"]):
			AKit.part(knee, Kit.sphere(0.05, cap, 10, 12), Vector3(0, 0.0, 0.06), Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
		AKit.part(knee, Kit.cylinder(0.084, 0.084, 0.024, AKit.m(Color("6e4a33"), true, 0.006), 16), Vector3(0, -0.338, 0.042), Vector3.ZERO, Vector3(1.0, 1.0, 1.42), false)
	return {}
