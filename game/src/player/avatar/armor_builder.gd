extends RefCounted
## "Show equipped armor" (GameState.wardrobe.show_armor): simple tier-coloured armor pieces drawn over or
## instead of the garment of their slot. Purely visual - the stats come from src/core/stats.gd; nothing here
## changes collision, speed or reach. Colours come from the armor item (data/items.gd `color`), the shape from
## its icon / tier: head = hood (cloth tiers) or helm (metal tiers), body = quilted vest or scale mail with
## pauldrons, boots = armored boots (replace the shoes). The two metal tiers read apart at a glance: ironwood is
## iron over warm leather (a leather helm band with cheek straps, a leather belt and pauldron straps, strapped
## boots), moonsteel is moon-bright with pale-blue trim, glowing moon studs, a crescent crest and rounder pauldrons.
## The hair under a helm / hood is compressed by hair_builder.gd (ctx["head_armor"]), the jacket's front details are
## left out under body armor (garment_builder.gd) and a tasset covers the garment hem below the vest / mail.
##   build_head(ctx)  -> {"hull": "all"}      (instead of the hat; hides the crown hair like a hat)
##   build_body(ctx)  -> {}                   (over the upper garment)
##   build_boots(ctx) -> {}                   (instead of the shoes)
## ctx["id"] = the armor item id.

const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")

const IRON_LEATHER := Color("7a4e32")
const MOON_TRIM := Color("a9c8f2")
const MOON_GLOW := Color("8fc4ff")

## Hood (cloth tiers): ellipsoid dome (centre, radii) and its face opening - the curve where the dome meets the face,
## a tilted plane section of the dome (centre, forward normal, half widths across / up the plane).
const HOOD_C := Vector3(0, 0.07, -0.1)
const HOOD_R := Vector3(0.316, 0.299, 0.2925)
const RIM_C := Vector3(0, -0.026, 0.05)
const RIM_N := Vector3(0, -0.522, 0.853)
const RIM_W := 0.2518
const RIM_H := 0.2365


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


## Point of the hood's face-opening rim at angle `a` (0 = top, +-PI/2 = the sides), HeadCenter space.
static func rim_point(a: float) -> Vector3:
	var up := Vector3(0, RIM_N.z, -RIM_N.y)   # in the rim plane, pointing up and back
	return RIM_C + Vector3(sin(a) * RIM_W, 0, 0) + up * cos(a) * RIM_H


static func build_head(ctx: Dictionary) -> Dictionary:
	var st := style(String(ctx["id"]))
	var c: Color = st["color"]
	var tier := int(st["tier"])
	var hc: Node3D = ctx["box"].call("head_c")
	var n := AKit.node(hc, Vector3.ZERO, "ArmorHead")
	if bool(st["metal"]):
		# rounded helm sitting above the brows, band with rivets
		AKit.part(n, Kit.sphere(0.285, _mat(st, c), 18, 26), Vector3(0, 0.14, -0.06), Vector3.ZERO, Vector3(1.06, 0.75, 1.02))
		if tier >= 4:
			# moonsteel: pale-blue trim band with glowing moon studs and a big crescent crest
			AKit.part(n, Kit.torus(0.262, 0.294, AKit.metal(MOON_TRIM)), Vector3(0, 0.1, -0.05), Vector3(-6, 0, 0), Vector3(1.03, 1.3, 0.98))
			var glow := Mat.glow(MOON_GLOW, 1.3)
			for k in 5:
				var a := lerpf(-1.1, 1.1, float(k) / 4.0)
				AKit.part(n, Kit.sphere(0.02, glow, 8, 10), Vector3(sin(a) * 0.304, 0.106 + 0.02 * cos(a), cos(a) * 0.29 - 0.05), Vector3.ZERO, Vector3.ONE, false)
			# the crest arches front to back above the dome (its legs sink into it), a moon stud on top
			var crest := MeshInstance3D.new()
			crest.mesh = AKit.arc_mesh(0.11, 0.022, 3.2)
			crest.material_override = AKit.metal(AKit.lighten(MOON_TRIM, 0.35), 0.008)
			AKit.part(n, crest, Vector3(0, 0.41, -0.06), Vector3(0, 90, 180))
			AKit.part(n, Kit.sphere(0.024, glow, 8, 10), Vector3(0, 0.43, -0.06), Vector3.ZERO, Vector3.ONE, false)
		else:
			# ironwood: iron over warm leather - a leather band with brass rivets and leather cheek straps
			var leather := AKit.m(IRON_LEATHER)
			AKit.part(n, Kit.torus(0.262, 0.292, leather), Vector3(0, 0.1, -0.05), Vector3(-6, 0, 0), Vector3(1.03, 1.3, 0.98))
			for k in 4:
				var a := lerpf(-0.9, 0.9, float(k) / 3.0)
				AKit.part(n, Kit.sphere(0.013, AKit.flat(AKit.BRASS), 6, 8), Vector3(sin(a) * 0.294, 0.105 + 0.02 * cos(a), cos(a) * 0.278 - 0.05), Vector3.ZERO, Vector3.ONE, false)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(n, Kit.box(Vector3(0.035, 0.12, 0.014), leather), Vector3(0.262 * s, 0.03, 0.0), Vector3(0, 90 * s, 4 * s))
				AKit.part(n, Kit.sphere(0.014, AKit.flat(AKit.BRASS), 6, 8), Vector3(0.272 * s, 0.078, 0.0), Vector3.ZERO, Vector3.ONE, false)
	else:
		# quilted hood: a dome with a rolled rim along the face opening (on the dome, never in front of it), a seam
		# over the top to the little back peak and soft ear flaps
		var cloth := _mat(st, c)
		var rim_c := AKit.shade(c, 0.2)
		AKit.part(n, Kit.sphere(0.29, cloth, 18, 26), HOOD_C, Vector3.ZERO, HOOD_R / 0.29)
		var tilt := rad_to_deg(Vector3.UP.signed_angle_to(RIM_N, Vector3.RIGHT))
		AKit.part(n, Kit.torus(0.222, 0.278, AKit.m(rim_c, true, 0.009)), RIM_C + RIM_N * 0.01, Vector3(tilt, 0, 0), Vector3(RIM_W / 0.25, 0.85, RIM_H / 0.25))
		var seam := MeshInstance3D.new()
		seam.mesh = AKit.arc_mesh(0.29, 0.007, 2.5)
		seam.material_override = AKit.flat(AKit.shade(c, 0.22))
		AKit.part(n, seam, HOOD_C + Vector3(0, 0.292, 0), Vector3(0, 90, 180), Vector3.ONE, false)
		AKit.part(n, Kit.sphere(0.08, cloth, 10, 14), Vector3(0, 0.3, -0.25), Vector3(-30, 0, 0), Vector3(0.8, 0.6, 1.3))
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(n, Kit.sphere(0.085, cloth, 10, 14), Vector3(0.262 * s, -0.08, -0.03), Vector3(0, 0, -8 * s), Vector3(0.42, 1.15, 0.95))
		if tier >= 2:
			for k in 5:
				var a := lerpf(-1.0, 1.0, float(k) / 4.0)
				AKit.part(n, Kit.sphere(0.014, AKit.metal(Palette.COPPER, 0.005), 6, 8), rim_point(a) + RIM_N * 0.034, Vector3.ZERO, Vector3.ONE, false)
	return {"hull": "all"}


static func build_body(ctx: Dictionary) -> Dictionary:
	var st := style(String(ctx["id"]))
	var c: Color = st["color"]
	var tier := int(st["tier"])
	var box: Callable = ctx["box"]
	var spine: Node3D = box.call("spine")
	if bool(st["metal"]):
		var metal := _mat(st, c)
		var moon := tier >= 4
		AKit.part(spine, Kit.capsule(0.19, 0.42, metal), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
		# tasset: covers the garment's hem below the scales (a jacket / cardigan hem showed through between the bands)
		AKit.part(spine, Kit.cylinder(0.19, 0.225, 0.13, metal, 20), Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
		var rows := AKit.metal(MOON_TRIM if moon else AKit.lighten(c, 0.18))
		for k in 3:
			AKit.part(spine, Kit.torus(0.18, 0.2, rows), Vector3(0, 0.05 + 0.08 * float(k), 0), Vector3.ZERO, Vector3(1.03, 1.3, 0.91))
		AKit.part(spine, Kit.torus(0.205, 0.232, rows), Vector3(0, -0.08, 0), Vector3.ZERO, Vector3(1.0, 1.2, 0.9))
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			var sh: Node3D = box.call("sh%d" % side)
			if moon:
				# rounder, bigger pauldrons with a pale-blue rim and a glowing stud
				AKit.part(sh, Kit.sphere(0.1, metal, 14, 18), Vector3(0, 0.012, 0), Vector3.ZERO, Vector3(1.2, 0.85, 1.2))
				AKit.part(sh, Kit.torus(0.09, 0.112, rows), Vector3(0, -0.012, 0), Vector3.ZERO, Vector3(1.12, 1.0, 1.12))
				AKit.part(sh, Kit.sphere(0.016, Mat.glow(MOON_GLOW, 1.3), 8, 10), Vector3(0.05 * s, 0.07, 0.0), Vector3.ZERO, Vector3.ONE, false)
			else:
				AKit.part(sh, Kit.sphere(0.088, metal, 12, 16), Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1.15, 0.72, 1.15))
				AKit.part(sh, Kit.torus(0.078, 0.096, rows), Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(1.1, 1.0, 1.1))
				# ironwood: a leather strap over each pauldron
				AKit.part(sh, Kit.torus(0.085, 0.1, AKit.m(IRON_LEATHER)), Vector3(0, 0.02, 0), Vector3(0, 0, 90), Vector3(1.0, 1.4, 1.05))
		if moon:
			var crescent := MeshInstance3D.new()
			crescent.mesh = AKit.arc_mesh(0.045, 0.011, 3.6)
			crescent.material_override = AKit.flat(AKit.lighten(MOON_TRIM, 0.5))
			AKit.part(spine, crescent, Vector3(0, 0.25, 0.175), Vector3(0, 0, 200), Vector3.ONE, false)
			AKit.part(spine, Kit.sphere(0.016, Mat.glow(MOON_GLOW, 1.3), 8, 10), Vector3(0.03, 0.29, 0.172), Vector3.ZERO, Vector3.ONE, false)
		else:
			# ironwood: a leather belt with a brass buckle and a strap across the chest
			var leather := AKit.m(IRON_LEATHER)
			AKit.part(spine, Kit.torus(0.192, 0.214, leather), Vector3(0, 0.005, 0), Vector3.ZERO, Vector3(1.03, 1.25, 0.92))
			AKit.part(spine, Kit.box(Vector3(0.05, 0.04, 0.014), AKit.metal(AKit.BRASS, 0.006)), Vector3(0, 0.005, 0.2), Vector3.ZERO, Vector3.ONE, false)
			AKit.part(spine, Kit.torus(0.185, 0.205, leather), Vector3(0.0, 0.2, 0), Vector3(0, 0, -50), Vector3(1.25, 1.3, 0.94))
	else:
		var cloth := _mat(st, c)
		AKit.part(spine, Kit.capsule(0.186, 0.4, cloth), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
		AKit.part(spine, Kit.cylinder(0.186, 0.225, 0.13, cloth), Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
		var quilt := AKit.m(AKit.shade(c, 0.14), false)
		for k in 2:
			AKit.part(spine, Kit.torus(0.18, 0.192, quilt), Vector3(0, 0.1 + 0.1 * float(k), 0), Vector3.ZERO, Vector3(1.01, 1.2, 0.89), false)
		AKit.part(spine, Kit.torus(0.2, 0.214, quilt), Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1.03, 1.2, 0.91), false)
		if tier >= 2:
			var plate := AKit.metal(Palette.COPPER, 0.006)
			for k in 4:
				var x := -0.06 if k % 2 == 0 else 0.06
				AKit.part(spine, Kit.box(Vector3(0.06, 0.05, 0.012), plate), Vector3(x, 0.12 if k < 2 else 0.22, 0.162), Vector3(-6, 0, 0))
	return {}


static func build_boots(ctx: Dictionary) -> Dictionary:
	var st := style(String(ctx["id"]))
	var c: Color = st["color"]
	var tier := int(st["tier"])
	var box: Callable = ctx["box"]
	var shaft := _mat(st, c)
	var cap := AKit.metal(AKit.shade(c, 0.1) if bool(st["metal"]) else Palette.COPPER)
	for side in 2:
		var knee: Node3D = box.call("knee%d" % side)
		AKit.part(knee, Kit.cylinder(0.082, 0.088, 0.21, shaft), Vector3(0, -0.215, 0))
		var cuff_c := MOON_TRIM if tier >= 4 else AKit.shade(c, 0.16)
		AKit.part(knee, Kit.torus(0.074, 0.098, AKit.metal(cuff_c) if tier >= 4 else AKit.m(cuff_c)), Vector3(0, -0.11, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
		if tier >= 2:
			AKit.part(knee, Kit.sphere(0.092, cap), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(1.0, 0.64, 1.42))
		else:
			AKit.part(knee, Kit.sphere(0.09, shaft), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(1.0, 0.64, 1.42))
		if bool(st["metal"]):
			AKit.part(knee, Kit.sphere(0.05, cap, 10, 12), Vector3(0, 0.0, 0.06), Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
			if tier >= 4:
				AKit.part(knee, Kit.sphere(0.014, Mat.glow(MOON_GLOW, 1.3), 8, 10), Vector3(0, 0.0, 0.088), Vector3.ZERO, Vector3.ONE, false)
			else:
				AKit.part(knee, Kit.torus(0.086, 0.1, AKit.m(IRON_LEATHER)), Vector3(0, -0.2, 0), Vector3.ZERO, Vector3(1, 1.5, 1))
		AKit.part(knee, Kit.cylinder(0.084, 0.084, 0.024, AKit.m(Color("6e4a33"), true, 0.006), 16), Vector3(0, -0.338, 0.042), Vector3.ZERO, Vector3(1.0, 1.0, 1.42), false)
	return {}
