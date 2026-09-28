extends RefCounted
## Krystal's clothing: upper garments, lower garments / dresses (with procedural skirt panels) and footwear
## (data/appearance.gd PARTS, slots upper / lower / shoes). Palette channels colour the cloth per the part's
## `channels`; `fixed` colours are details. The Chapter One explorer pieces are reproduced part for part.
##   build_upper(ctx) -> {"chains": [scarf ends], "patch": Node3D | null}
##   build_lower(ctx) -> {"skirt": {pivots, theta, radius, y0, length, base, max} | {}}
##   build_shoes(ctx) -> {}
## Cosmetic only: nothing here touches collision, speed or reach.

const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const LookColors := preload("res://src/player/avatar/look_colors.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")

const SKIRT_RADIUS := 0.18       # panel ring radius at the waist (hips space)
const SKIRT_Y := 0.05            # ring height (hips space)
const SKIRT_MAX_FLARE := 1.3     # rad; the rig never opens a panel further (roll / sitting)
const SOLE := Color("6e4a33")

## Lower garments: legs = "trousers" (cloth legs) | "legacy" (the Chapter One trouser legs) | "bare" | "culottes";
## skirt = [panel count, length, base flare, pleats] or [] for none.
const LOWER := {
	"explorer_trousers": {"cloth": "trousers", "legs": "legacy", "skirt": []},
	"pinafore_skirt": {"cloth": "pinafore", "legs": "bare", "skirt": [8, 0.23, 0.26, 0], "bib": true},
	"pleated_skirt_leggings": {"cloth": "skirt", "legs": "leggings", "skirt": [10, 0.2, 0.24, 2]},
	"cloud_culottes": {"cloth": "culottes", "legs": "culottes", "skirt": []},
	"moonflower_dress": {"cloth": "dress", "legs": "bare", "skirt": [8, 0.34, 0.24, 0], "hem": "hem", "dots": "flowers"},
	"dungarees": {"cloth": "dungarees", "legs": "trousers", "skirt": [], "bib": true},
	"harvest_skirt": {"cloth": "skirt", "legs": "bare", "skirt": [8, 0.27, 0.3, 1]},
	"witch_dress": {"cloth": "dress", "legs": "bare", "skirt": [8, 0.36, 0.28, 0], "points": true, "bows": "ribbons"},
	"velvet_dress": {"cloth": "dress", "legs": "bare", "skirt": [8, 0.32, 0.3, 1], "hem": "ruffles"},
	"tulle_party_dress": {"cloth": "tulle", "legs": "bare", "skirt": [10, 0.26, 0.45, 2], "under": "underskirt", "dots": "sparkles"},
	"moth_long_skirt": {"cloth": "skirt", "legs": "bare", "skirt": [8, 0.42, 0.16, 0]},
	"lanternwake_dress": {"cloth": "dress", "legs": "bare", "skirt": [8, 0.34, 0.28, 0], "hem": "hem", "apron": "apron"},
}


# =====================================================================================================
# Upper garments
# =====================================================================================================

static func build_upper(ctx: Dictionary) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var box: Callable = ctx["box"]
	var spine: Node3D = box.call("spine")
	var chest: Node3D = box.call("chest")
	var skin := AKit.m(col["skin"])
	var res := {"chains": [], "patch": null}
	match id:
		"puff_blouse":
			var blouse := AKit.m(LookColors.channel(id, "blouse", col))
			var collar_c := LookColors.channel(id, "collar", col)
			_torso(spine, blouse, "blouse")
			_collar(chest, AKit.m(collar_c), 0.07, 0.13, 1.3)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(chest, Kit.sphere(0.042, AKit.m(collar_c, false), 10, 14), Vector3(0.045 * s, 0.015, 0.11), Vector3(20, 25 * s, 0), Vector3(1.3, 0.6, 0.35), false)
			for i in 3:
				AKit.part(spine, Kit.sphere(0.012, AKit.flat(collar_c), 8, 10), Vector3(0, 0.3 - 0.08 * float(i), 0.143), Vector3.ZERO, Vector3.ONE, false)
			_sleeves(box, "puff", blouse, AKit.m(collar_c), skin)
		"ribbon_blouse":
			var blouse := AKit.m(LookColors.channel(id, "blouse", col))
			var collar_c := LookColors.channel(id, "collar", col)
			var ribbon := AKit.m(LookColors.channel(id, "ribbon", col), true, 0.006)
			_torso(spine, blouse, "blouse")
			# sailor collar: square flap on the back with a pale trim stripe, points at the front
			AKit.part(spine, Kit.box(Vector3(0.25, 0.17, 0.018), AKit.m(collar_c)), Vector3(0, 0.36, -0.142), Vector3(-18, 0, 0))
			AKit.part(spine, Kit.box(Vector3(0.23, 0.012, 0.02), AKit.flat(AKit.lighten(collar_c, 0.6))), Vector3(0, 0.3, -0.155), Vector3(-18, 0, 0), Vector3.ONE, false)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(spine, Kit.prism(Vector3(0.1, 0.12, 0.02), AKit.m(collar_c, false)), Vector3(0.05 * s, 0.33, 0.13), Vector3(-14, 0, 180 + 25 * s), Vector3.ONE, false)
				AKit.part(spine, Kit.sphere(0.035, ribbon, 8, 12), Vector3(0.036 * s, 0.28, 0.152), Vector3(0, 0, -15 * s), Vector3(1.4, 0.8, 0.5), false)
				AKit.part(spine, Kit.box(Vector3(0.022, 0.08, 0.008), ribbon), Vector3(0.016 * s, 0.23, 0.154), Vector3(0, 0, 12 * s), Vector3.ONE, false)
			AKit.part(spine, Kit.sphere(0.018, ribbon, 8, 10), Vector3(0, 0.28, 0.158), Vector3.ZERO, Vector3.ONE, false)
			_sleeves(box, "long", blouse, AKit.m(collar_c), skin)
		"cloud_cardigan", "pumpkin_cardigan":
			var cardi_c := LookColors.channel(id, "cardigan", col)
			var cardi := AKit.m(cardi_c)
			var buttons := LookColors.fixed(id, "buttons", Color("fbf8f2"))
			_torso(spine, cardi, "cardigan")
			AKit.part(spine, Kit.prism(Vector3(0.13, 0.2, 0.03), AKit.m(LookColors.channel(id, "top", col), false)), Vector3(0, 0.31, 0.132), Vector3(-14, 0, 180), Vector3.ONE, false)
			for i in 3:
				AKit.part(spine, Kit.sphere(0.015, AKit.flat(buttons), 8, 10), Vector3(0.055, 0.26 - 0.075 * float(i), 0.15), Vector3.ZERO, Vector3.ONE, false)
			if id == "cloud_cardigan":
				# fluffy cloud hem
				for i in 10:
					var a := TAU * float(i) / 10.0
					AKit.part(spine, Kit.sphere(0.05, cardi, 10, 14), Vector3(sin(a) * 0.205, -0.07, cos(a) * 0.19), Vector3(0, rad_to_deg(a), 0), Vector3(1.2, 0.8, 1.0))
				_sleeves(box, "chunky", cardi, AKit.m(AKit.lighten(cardi_c, 0.2)), skin)
			else:
				AKit.part(spine, Kit.torus(0.185, 0.222, AKit.m(AKit.shade(cardi_c, 0.15))), Vector3(0, -0.075, 0), Vector3.ZERO, Vector3(1, 1.4, 0.9))
				# a little pumpkin pocket with a leaf-green stem
				AKit.part(spine, Kit.sphere(0.042, AKit.m(AKit.shade(cardi_c, 0.1), false), 10, 14), Vector3(-0.1, 0.05, 0.165), Vector3(0, -20, 0), Vector3(1.25, 1.0, 0.45), false)
				AKit.part(spine, Kit.capsule(0.008, 0.03, AKit.flat(buttons)), Vector3(-0.1, 0.095, 0.17), Vector3(0, 0, 15), Vector3.ONE, false)
				_sleeves(box, "chunky", cardi, AKit.m(AKit.shade(cardi_c, 0.15)), skin)
		"moonflower_bodice":
			var bodice_c := LookColors.channel(id, "bodice", col)
			var bodice := AKit.m(bodice_c)
			var sash := AKit.m(LookColors.channel(id, "sash", col))
			_torso(spine, bodice, "fitted")
			AKit.part(spine, Kit.torus(0.148, 0.185, sash), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 1.15, 0.9))
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(spine, Kit.sphere(0.045, sash, 10, 14), Vector3(0.05 * s, 0.06, -0.165), Vector3(0, 0, -20 * s), Vector3(1.4, 0.85, 0.5))
				AKit.part(spine, Kit.box(Vector3(0.028, 0.1, 0.01), sash), Vector3(0.025 * s, -0.01, -0.168), Vector3(0, 0, 10 * s), Vector3.ONE, false)
			var scallop := AKit.m(AKit.lighten(bodice_c, 0.35), false)
			for i in 9:
				var a := lerpf(-1.3, 1.3, float(i) / 8.0)
				AKit.part(chest, Kit.sphere(0.022, scallop, 8, 10), Vector3(sin(a) * 0.135, 0.012, cos(a) * 0.12), Vector3.ZERO, Vector3(1.2, 0.7, 0.8), false)
			_sleeves(box, "cap", bodice, bodice, skin)
		"striped_tee":
			var tee := AKit.m(LookColors.channel(id, "tee", col))
			var stripes := AKit.m(LookColors.channel(id, "stripes", col), false)
			_torso(spine, tee, "blouse")
			for i in 3:
				AKit.part(spine, Kit.torus(0.158, 0.172, stripes), Vector3(0, 0.1 + 0.1 * float(i), 0), Vector3.ZERO, Vector3(1.01, 1.5, 0.87), false)
			_collar(chest, AKit.m(LookColors.channel(id, "stripes", col)), 0.075, 0.115, 1.0)
			_sleeves(box, "short", tee, stripes, skin)
		"witch_blouse":
			var blouse_c := LookColors.channel(id, "blouse", col)
			var blouse := AKit.m(blouse_c)
			var laces := AKit.flat(LookColors.channel(id, "laces", col))
			_torso(spine, blouse, "blouse")
			_lacing(spine, laces, 0.145)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(chest, Kit.prism(Vector3(0.08, 0.09, 0.016), AKit.m(AKit.lighten(blouse_c, 0.3), false)), Vector3(0.05 * s, 0.0, 0.12), Vector3(-30, 0, 180 + 30 * s), Vector3.ONE, false)
			_sleeves(box, "bishop", blouse, AKit.m(LookColors.channel(id, "laces", col)), skin)
		"ruffle_bodice":
			var bodice := AKit.m(LookColors.channel(id, "bodice", col))
			var ruff := AKit.m(LookColors.channel(id, "ruffles", col))
			var collar := AKit.m(LookColors.channel(id, "collar", col))
			_torso(spine, bodice, "fitted")
			AKit.part(chest, Kit.torus(0.08, 0.14, ruff), Vector3(0, 0.03, 0), Vector3(4, 0, 0), Vector3(1, 1.6, 0.95))
			AKit.part(chest, Kit.torus(0.1, 0.16, ruff), Vector3(0, -0.005, 0), Vector3(4, 0, 0), Vector3(1, 1.3, 0.95))
			for i in 3:
				AKit.part(spine, Kit.sphere(0.04, ruff, 10, 12), Vector3(0, 0.3 - 0.05 * float(i), 0.142), Vector3.ZERO, Vector3(1.3, 0.7, 0.5))
			# stand collar behind the neck, pointed at both ends
			AKit.part(chest, Kit.box(Vector3(0.2, 0.1, 0.02), collar), Vector3(0, 0.085, -0.12), Vector3(-15, 0, 0))
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(chest, Kit.prism(Vector3(0.05, 0.08, 0.02), collar), Vector3(0.105 * s, 0.14, -0.11), Vector3(-15, 0, -20 * s), Vector3.ONE, false)
			_sleeves(box, "bishop", bodice, ruff, skin)
		"ghost_bodice":
			var bodice := AKit.m(LookColors.channel(id, "bodice", col))
			var trim := AKit.m(LookColors.channel(id, "trim", col))
			_torso(spine, bodice, "fitted")
			AKit.part(spine, Kit.torus(0.15, 0.175, trim), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 1.3, 0.9))
			_collar(chest, trim, 0.075, 0.115, 1.0)
			var glow := Mat.glow(LookColors.fixed(id, "glow", Color("d8e8ff")), 0.9)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(spine, Kit.sphere(0.014, glow, 8, 10), Vector3(0.05 * s, 0.3, 0.142), Vector3.ZERO, Vector3.ONE, false)
			_sleeves(box, "puff", bodice, trim, skin)
		"moth_blouse":
			var blouse_c := LookColors.channel(id, "blouse", col)
			var blouse := AKit.m(blouse_c)
			_torso(spine, blouse, "blouse")
			var fuzz := AKit.m(AKit.lighten(blouse_c, 0.3))
			for i in 10:
				var a := TAU * float(i) / 10.0
				AKit.part(chest, Kit.sphere(0.036, fuzz, 8, 12), Vector3(sin(a) * 0.13, 0.025, cos(a) * 0.12), Vector3.ZERO, Vector3(1.1, 0.8, 1.0))
			_sleeves(box, "bishop", blouse, AKit.m(LookColors.channel(id, "cuffs", col)), skin)
		"festival_bodice":
			var bodice := AKit.m(LookColors.channel(id, "bodice", col))
			var lacing := AKit.flat(LookColors.channel(id, "lacing", col))
			var emb := LookColors.fixed(id, "embroidery", Color("f2c14e"))
			_torso(spine, bodice, "fitted")
			_lacing(spine, lacing, 0.141)
			for i in 5:
				var a := lerpf(-0.9, 0.9, float(i) / 4.0)
				AKit.part(spine, Kit.sphere(0.013, AKit.flat(emb), 8, 10), Vector3(sin(a) * 0.14, 0.34, cos(a) * 0.128), Vector3.ZERO, Vector3.ONE, false)
			_sleeves(box, "puff", bodice, AKit.m(emb), skin)
		_:
			res = _explorer_jacket(ctx, spine, chest, skin)
	return res


## The Chapter One explorer jacket, part for part: jacket body + A-line hem, shirt V, brass buttons, pocket
## flaps, the embroidered back patch, the scarf (with its two fluttering ends) and full sleeves with cuffs.
static func _explorer_jacket(ctx: Dictionary, spine: Node3D, chest: Node3D, skin: Material) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var jacket_c := LookColors.channel(id, "jacket", col)
	var scarf_c := LookColors.channel(id, "scarf", col)
	var shirt_c := LookColors.fixed(id, "shirt", Palette.K_SHIRT)
	var brass := LookColors.fixed(id, "buttons", AKit.BRASS)
	var jacket := AKit.m(jacket_c)
	var jacket_dark := AKit.shade(jacket_c)
	_torso(spine, jacket, "jacket")
	AKit.part(spine, Kit.prism(Vector3(0.13, 0.15, 0.03), AKit.m(shirt_c, false)), Vector3(0, 0.335, 0.122), Vector3(-14, 0, 180), Vector3.ONE, false)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(spine, Kit.sphere(0.013, AKit.flat(brass), 8, 12), Vector3(0.062 * s, 0.24, 0.139), Vector3.ZERO, Vector3.ONE, false)
		AKit.part(spine, Kit.sphere(0.013, AKit.flat(brass), 8, 12), Vector3(0.062 * s, 0.15, 0.144), Vector3.ZERO, Vector3.ONE, false)
		AKit.part(spine, Kit.sphere(0.045, AKit.m(jacket_dark, false)), Vector3(0.1 * s, 0.05, 0.158), Vector3(0, 22 * s, 0), Vector3(1.0, 0.42, 0.28), false)
	# Back: an embroidered explorer patch (cream disc with a little green sprout) - seen from the camera
	var patch := AKit.node(spine, Vector3(0, 0.25, -0.142), "Patch")
	patch.rotation_degrees = Vector3(-8, 180, 0)
	AKit.part(patch, Kit.cylinder(0.052, 0.052, 0.012, AKit.m(shirt_c, true, 0.005), 20), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
	AKit.part(patch, Kit.capsule(0.006, 0.05, AKit.flat(Palette.FOLIAGE_DARK)), Vector3(0, -0.008, 0.009), Vector3.ZERO, Vector3.ONE, false)
	AKit.part(patch, Kit.sphere(0.017, AKit.flat(Palette.FOLIAGE), 8, 10), Vector3(-0.014, 0.014, 0.01), Vector3(0, 0, 35), Vector3(1.4, 0.7, 0.4), false)
	AKit.part(patch, Kit.sphere(0.015, AKit.flat(Palette.FOLIAGE_LIGHT), 8, 10), Vector3(0.013, 0.02, 0.01), Vector3(0, 0, -35), Vector3(1.4, 0.7, 0.4), false)
	# Scarf: two wraps, a knot at the back-left and two ends that flutter
	var scarf := AKit.m(scarf_c)
	AKit.part(chest, Kit.torus(0.085, 0.16, scarf), Vector3(0, 0.02, 0), Vector3(4, 0, 0), Vector3(1.0, 1.55, 0.94))
	AKit.part(chest, Kit.torus(0.08, 0.14, scarf), Vector3(0, 0.075, -0.01), Vector3(-6, 0, 0), Vector3(0.96, 1.3, 0.9))
	AKit.part(chest, Kit.sphere(0.05, scarf), Vector3(0.075, 0.03, -0.128), Vector3.ZERO, Vector3(1.1, 0.85, 0.8))
	var chains: Array = []
	for i in 2:
		var root := AKit.node(chest, Vector3(0.06 + 0.035 * i, 0.02, -0.15), "ScarfEnd%d" % i)
		root.rotation = Vector3(0.25, 0, 0.22 - 0.4 * i)
		AKit.part(root, Kit.capsule(0.03, 0.16, scarf), Vector3(0, -0.07, 0), Vector3.ZERO, Vector3(1.2, 1.0, 0.55))
		var seg := AKit.node(root, Vector3(0, -0.13, 0), "Tip")
		AKit.part(seg, Kit.capsule(0.03, 0.15 - 0.035 * i, scarf), Vector3(0, -0.055, 0), Vector3(0, 0, 6 - 12 * i), Vector3(1.3, 1.0, 0.5))
		AKit.part(seg, Kit.box(Vector3(0.074, 0.016, 0.034), AKit.m(AKit.shade(scarf_c), false)), Vector3(0, -0.09 + 0.02 * i, 0), Vector3(0, 0, 6 - 12 * i), Vector3.ONE, false)
		var ch := AKit.chain("scarf", [root, seg], [Vector3(0.25, 0, 0.22 - 0.4 * i), Vector3.ZERO], 70.0, 7.5)
		ch["i"] = i
		chains.append(ch)
	_sleeves(ctx["box"], "long", jacket, AKit.m(jacket_dark), skin)
	return {"chains": chains, "patch": patch}


## Torso shapes (Spine space): jacket (Chapter One: body + A-line hem), blouse, fitted bodice, cardigan.
static func _torso(spine: Node3D, mat: Material, style: String) -> void:
	match style:
		"blouse":
			AKit.part(spine, Kit.capsule(0.165, 0.49, mat), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
			AKit.part(spine, Kit.cylinder(0.16, 0.19, 0.1, mat), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
		"fitted":
			AKit.part(spine, Kit.capsule(0.158, 0.47, mat), Vector3(0, 0.21, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.84))
			AKit.part(spine, Kit.cylinder(0.152, 0.172, 0.08, mat), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
		"cardigan":
			AKit.part(spine, Kit.capsule(0.176, 0.5, mat), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.86))
			AKit.part(spine, Kit.cylinder(0.172, 0.215, 0.17, mat), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
		_:
			AKit.part(spine, Kit.capsule(0.168, 0.5, mat), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.84))
			AKit.part(spine, Kit.cylinder(0.165, 0.205, 0.15, mat), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))


static func _collar(chest: Node3D, mat: Material, inner: float, outer: float, sy: float) -> void:
	AKit.part(chest, Kit.torus(inner, outer, mat), Vector3(0, 0.035, 0), Vector3(4, 0, 0), Vector3(1.0, sy, 0.94))


## Criss-cross lacing down the front of a bodice.
static func _lacing(spine: Node3D, mat: Material, z: float) -> void:
	for k in 3:
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(spine, Kit.capsule(0.006, 0.075, mat), Vector3(0, 0.14 + 0.06 * float(k), z), Vector3(0, 0, 50 * s), Vector3.ONE, false)


## Sleeves on both arms. long (Chapter One), puff (short puff + bare arm), cap, short (tee), bishop (flared), chunky.
static func _sleeves(box: Callable, style: String, cloth: Material, cuff: Material, skin: Material) -> void:
	for side in 2:
		var sh: Node3D = box.call("sh%d" % side)
		var el: Node3D = box.call("el%d" % side)
		match style:
			"puff":
				AKit.part(sh, Kit.sphere(0.092, cloth), Vector3(0, -0.025, 0), Vector3.ZERO, Vector3(1.05, 0.95, 1.05))
				AKit.part(sh, Kit.torus(0.058, 0.074, cuff), Vector3(0, -0.085, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
				AKit.part(sh, Kit.capsule(0.05, 0.2, skin), Vector3(0, -0.11, 0))
				AKit.part(el, Kit.capsule(0.047, 0.19, skin), Vector3(0, -0.075, 0))
			"cap":
				AKit.part(sh, Kit.sphere(0.078, cloth), Vector3(0, -0.012, 0), Vector3.ZERO, Vector3(1.05, 0.9, 1.05))
				AKit.part(sh, Kit.capsule(0.05, 0.21, skin), Vector3(0, -0.105, 0))
				AKit.part(el, Kit.capsule(0.047, 0.19, skin), Vector3(0, -0.075, 0))
			"short":
				AKit.part(sh, Kit.sphere(0.072, cloth), Vector3(0, -0.01, 0))
				AKit.part(sh, Kit.cylinder(0.066, 0.072, 0.12, cloth), Vector3(0, -0.07, 0))
				AKit.part(sh, Kit.torus(0.064, 0.076, cuff), Vector3(0, -0.11, 0), Vector3.ZERO, Vector3(1, 1.3, 1), false)
				AKit.part(sh, Kit.capsule(0.05, 0.2, skin), Vector3(0, -0.12, 0))
				AKit.part(el, Kit.capsule(0.047, 0.19, skin), Vector3(0, -0.075, 0))
			"bishop":
				AKit.part(sh, Kit.sphere(0.072, cloth), Vector3(0, -0.01, 0))
				AKit.part(sh, Kit.capsule(0.058, 0.23, cloth), Vector3(0, -0.1, 0))
				AKit.part(el, Kit.cylinder(0.05, 0.078, 0.2, cloth), Vector3(0, -0.08, 0))
				AKit.part(el, Kit.torus(0.062, 0.084, cuff), Vector3(0, -0.176, 0), Vector3.ZERO, Vector3(1, 1.2, 1))
			"chunky":
				AKit.part(sh, Kit.sphere(0.08, cloth), Vector3(0, -0.01, 0))
				AKit.part(sh, Kit.capsule(0.066, 0.23, cloth), Vector3(0, -0.1, 0))
				AKit.part(el, Kit.capsule(0.06, 0.2, cloth), Vector3(0, -0.075, 0))
				AKit.part(el, Kit.torus(0.05, 0.082, cuff), Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
			_:
				AKit.part(sh, Kit.sphere(0.072, cloth), Vector3(0, -0.01, 0))
				AKit.part(sh, Kit.capsule(0.06, 0.23, cloth), Vector3(0, -0.1, 0))
				AKit.part(el, Kit.capsule(0.054, 0.2, cloth), Vector3(0, -0.075, 0))
				AKit.part(el, Kit.torus(0.042, 0.066, cuff), Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1, 1.4, 1))


# =====================================================================================================
# Lower garments and dresses
# =====================================================================================================

static func build_lower(ctx: Dictionary) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var box: Callable = ctx["box"]
	var spec: Dictionary = LOWER.get(id, LOWER["explorer_trousers"])
	if not LOWER.has(id):
		id = "explorer_trousers"
	var cloth_c := LookColors.channel(id, String(spec["cloth"]), col)
	var cloth := AKit.m(cloth_c)
	var skin := AKit.m(col["skin"])
	var hips: Node3D = box.call("hips")
	var legs := String(spec["legs"])
	# pelvis: trousers / bloomers in the garment colour (leggings colour under a pleated skirt)
	var pelvis_mat := cloth
	if legs == "leggings":
		pelvis_mat = AKit.m(LookColors.channel(id, "leggings", col))
	AKit.part(hips, Kit.sphere(0.155, pelvis_mat), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.08, 0.72, 0.92))
	for side in 2:
		var leg: Node3D = box.call("leg%d" % side)
		var knee: Node3D = box.call("knee%d" % side)
		match legs:
			"legacy":
				AKit.part(leg, Kit.capsule(0.078, 0.3, cloth), Vector3(0, -0.12, 0))
				AKit.part(knee, Kit.capsule(0.066, 0.24, cloth), Vector3(0, -0.08, 0))
			"trousers":
				AKit.part(leg, Kit.capsule(0.084, 0.3, cloth), Vector3(0, -0.12, 0))
				AKit.part(knee, Kit.capsule(0.072, 0.3, cloth), Vector3(0, -0.11, 0))
				AKit.part(knee, Kit.torus(0.066, 0.086, AKit.m(AKit.shade(cloth_c, 0.12))), Vector3(0, -0.225, 0), Vector3.ZERO, Vector3(1, 1.5, 1))
				if side == 0 and id == "dungarees":
					AKit.part(knee, Kit.sphere(0.042, AKit.m(LookColors.channel(id, "patch", col), false), 10, 12), Vector3(0, -0.02, 0.062), Vector3.ZERO, Vector3(1.0, 1.0, 0.35), false)
			"leggings":
				var leggings := AKit.m(LookColors.channel(id, "leggings", col))
				AKit.part(leg, Kit.capsule(0.076, 0.3, leggings), Vector3(0, -0.12, 0))
				AKit.part(knee, Kit.capsule(0.062, 0.34, leggings), Vector3(0, -0.13, 0))
			"culottes":
				AKit.part(leg, Kit.cylinder(0.085, 0.12, 0.27, cloth), Vector3(0, -0.13, 0))
				AKit.part(leg, Kit.torus(0.1, 0.124, AKit.m(AKit.shade(cloth_c, 0.12))), Vector3(0, -0.262, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
				AKit.part(knee, Kit.capsule(0.06, 0.34, skin), Vector3(0, -0.13, 0))
			_:
				AKit.part(leg, Kit.capsule(0.074, 0.3, skin), Vector3(0, -0.12, 0))
				AKit.part(knee, Kit.capsule(0.06, 0.34, skin), Vector3(0, -0.13, 0))
	if bool(spec.get("bib", false)):
		_bib(ctx, id, cloth, cloth_c)
	var res := {"skirt": {}}
	var sk: Array = spec["skirt"]
	if sk.is_empty():
		return res
	res["skirt"] = _skirt(ctx, id, spec, cloth, cloth_c, int(sk[0]), float(sk[1]), float(sk[2]), int(sk[3]))
	return res


## Pinafore / dungaree bib on the chest with straps over the shoulders.
static func _bib(ctx: Dictionary, id: String, cloth: Material, cloth_c: Color) -> void:
	var col: Dictionary = ctx["col"]
	var spine: Node3D = ctx["box"].call("spine")
	var dungarees := id == "dungarees"
	AKit.part(spine, Kit.box(Vector3(0.19 if dungarees else 0.17, 0.16, 0.026), cloth), Vector3(0, 0.19, 0.148), Vector3(-6, 0, 0))
	var pocket_c := LookColors.channel(id, "patch" if dungarees else "pocket", col)
	AKit.part(spine, Kit.box(Vector3(0.08, 0.06, 0.01), AKit.m(pocket_c, false)), Vector3(0, 0.19, 0.163), Vector3(-6, 0, 0), Vector3.ONE, false)
	if not dungarees:
		AKit.part(spine, Kit.sphere(0.02, AKit.m(LookColors.fixed(id, "strawberry", Color("e4665c")), false), 8, 10), Vector3(0.02, 0.19, 0.17), Vector3.ZERO, Vector3(1.0, 1.15, 0.6), false)
		AKit.part(spine, Kit.sphere(0.01, AKit.flat(Palette.FOLIAGE), 6, 8), Vector3(0.02, 0.212, 0.17), Vector3.ZERO, Vector3(1.6, 0.6, 0.6), false)
	var buckle := AKit.flat(LookColors.fixed(id, "buckles", AKit.BRASS)) if dungarees else AKit.flat(AKit.lighten(cloth_c, 0.4))
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(spine, Kit.capsule(0.016, 0.17, cloth), Vector3(0.075 * s, 0.33, 0.128), Vector3(-28, 0, 0))
		AKit.part(spine, Kit.capsule(0.016, 0.2, cloth), Vector3(0.075 * s, 0.31, -0.128), Vector3(24, 0, -8 * s))
		AKit.part(spine, Kit.sphere(0.013, buckle, 8, 10), Vector3(0.075 * s, 0.265, 0.155), Vector3.ZERO, Vector3.ONE, false)


## Skirt / dress: a waistband plus `n` spring panels on a ring under the hips (animated by skirt_rig.gd).
static func _skirt(ctx: Dictionary, id: String, spec: Dictionary, cloth: Material, cloth_c: Color, n: int, length: float,
		base: float, pleats: int) -> Dictionary:
	var col: Dictionary = ctx["col"]
	var hips: Node3D = ctx["box"].call("hips")
	var r0 := SKIRT_RADIUS
	AKit.part(hips, Kit.torus(0.16, 0.2, cloth), Vector3(0, SKIRT_Y + 0.005, 0), Vector3.ZERO, Vector3(1.0, 1.2, 0.92))
	if spec.has("under"):
		var under := AKit.m(LookColors.channel(id, String(spec["under"]), col))
		AKit.part(hips, Kit.cylinder(0.17, 0.26, 0.2, under), Vector3(0, -0.06, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.95))
	var w_top := TAU * r0 / float(n) * 1.16
	var w_bot := TAU * (r0 + length * sin(base + 0.22)) / float(n) * 1.2
	var mesh := AKit.panel_mesh(w_top, w_bot, length, r0, r0 + length * sin(base), 0.01, pleats, 0.008 if pleats > 0 else 0.0)
	var hem_mesh: Mesh = null
	var hem_mat: Material = null
	if spec.has("hem"):
		hem_mat = AKit.m(LookColors.channel(id, String(spec["hem"]), col))
		hem_mesh = AKit.panel_mesh(w_bot * 0.97, w_bot * 1.01, 0.05, r0 + length * sin(base) * 0.85, r0 + length * sin(base), 0.012)
	var dot_mat: Material = null
	if spec.has("dots"):
		dot_mat = AKit.flat(LookColors.fixed(id, String(spec["dots"]), Color("fff4e0")))
	var bow_mat: Material = null
	if spec.has("bows"):
		bow_mat = AKit.m(LookColors.channel(id, String(spec["bows"]), col))
	var ring := AKit.node(hips, Vector3.ZERO, "Skirt")
	var pivots: Array = []
	var theta: Array = []
	for i in n:
		var th := TAU * float(i) / float(n)
		var pv := AKit.node(ring, Vector3(sin(th) * r0, SKIRT_Y, cos(th) * r0), "Panel%d" % i)
		pv.rotation = Vector3(-base, th, 0.0)
		AKit.mesh_part(pv, mesh, cloth, Vector3.ZERO)
		if hem_mesh != null:
			AKit.mesh_part(pv, hem_mesh, hem_mat, Vector3(0, -length + 0.05, 0.004))
		if bool(spec.get("points", false)):
			AKit.part(pv, Kit.prism(Vector3(w_bot * 0.55, 0.05, 0.01), cloth), Vector3(0, -length - 0.02, -0.004), Vector3(0, 0, 180))
		if dot_mat != null and i % 4 == 0:
			AKit.part(pv, Kit.sphere(0.016, dot_mat, 8, 10), Vector3(-w_bot * 0.15, -length * 0.55, 0.008), Vector3.ZERO, Vector3(1.0, 1.0, 0.5), false)
			AKit.part(pv, Kit.sphere(0.012, dot_mat, 8, 10), Vector3(w_bot * 0.18, -length * 0.78, 0.008), Vector3.ZERO, Vector3(1.0, 1.0, 0.5), false)
		if bow_mat != null and i % 2 == 1:
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(pv, Kit.sphere(0.02, bow_mat, 8, 10), Vector3(0.02 * s, -length + 0.06, 0.01), Vector3(0, 0, -20 * s), Vector3(1.4, 0.8, 0.5))
		if spec.has("apron") and i == 0:
			var apron_mesh := AKit.panel_mesh(w_top * 0.9, w_bot * 0.85, length * 0.78, r0 + 0.01, r0 + length * sin(base), 0.008)
			AKit.mesh_part(pv, apron_mesh, AKit.m(LookColors.channel(id, String(spec["apron"]), col)), Vector3(0, -0.01, 0.008))
		pivots.append(pv)
		theta.append(th)
	return {"pivots": pivots, "theta": theta, "radius": r0, "y0": SKIRT_Y, "length": length, "base": base, "max": SKIRT_MAX_FLARE}


# =====================================================================================================
# Footwear
# =====================================================================================================

static func build_shoes(ctx: Dictionary) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var box: Callable = ctx["box"]
	var leg_skin := AKit.m(col.get("leg", col["skin"]))
	for side in 2:
		var knee: Node3D = box.call("knee%d" % side)
		match id:
			"mary_janes":
				var shoe_c := LookColors.channel(id, "shoes", col)
				var socks := AKit.m(LookColors.fixed(id, "socks", Color("fbf8f2")))
				AKit.part(knee, Kit.capsule(0.064, 0.16, socks), Vector3(0, -0.23, 0))
				AKit.part(knee, Kit.torus(0.058, 0.076, socks), Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
				AKit.part(knee, Kit.sphere(0.086, AKit.m(shoe_c)), Vector3(0, -0.298, 0.035), Vector3.ZERO, Vector3(1.0, 0.56, 1.42))
				AKit.part(knee, Kit.torus(0.05, 0.062, AKit.m(shoe_c, true, 0.006)), Vector3(0, -0.285, 0.05), Vector3(90, 0, 0), Vector3(1.25, 1.0, 1.0))
				_sole(knee, AKit.shade(shoe_c, 0.3), 0.08)
			"lace_up_boots":
				var boot_c := LookColors.channel(id, "boots", col)
				var boot := AKit.m(boot_c)
				AKit.part(knee, Kit.cylinder(0.075, 0.083, 0.2, boot), Vector3(0, -0.21, 0))
				AKit.part(knee, Kit.torus(0.068, 0.088, AKit.m(AKit.shade(boot_c, 0.15))), Vector3(0, -0.115, 0), Vector3.ZERO, Vector3(1, 1.2, 1))
				AKit.part(knee, Kit.sphere(0.086, boot), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(0.98, 0.62, 1.42))
				var laces := AKit.flat(LookColors.fixed(id, "laces", Color("fbf8f2")))
				for k in 3:
					for s2 in 2:
						AKit.part(knee, Kit.box(Vector3(0.05, 0.008, 0.008), laces), Vector3(0, -0.15 - 0.04 * float(k), 0.08), Vector3(0, 0, 30.0 if s2 == 0 else -30.0), Vector3.ONE, false)
				_sole(knee, SOLE, 0.082)
			"ballet_flats":
				var flat_c := LookColors.channel(id, "flats", col)
				AKit.part(knee, Kit.capsule(0.056, 0.14, leg_skin), Vector3(0, -0.245, 0))
				AKit.part(knee, Kit.sphere(0.084, AKit.m(flat_c)), Vector3(0, -0.31, 0.035), Vector3.ZERO, Vector3(1.0, 0.46, 1.45))
				for s3 in 2:
					var s := 1.0 if s3 == 0 else -1.0
					AKit.part(knee, Kit.sphere(0.014, AKit.m(AKit.shade(flat_c, 0.2), false), 8, 10), Vector3(0.014 * s, -0.285, 0.1), Vector3(0, 0, 20 * s), Vector3(1.4, 0.8, 0.6), false)
				_sole(knee, AKit.shade(flat_c, 0.35), 0.078)
			"wellies":
				var well_c := LookColors.channel(id, "boots", col)
				var well := AKit.m(well_c)
				AKit.part(knee, Kit.cylinder(0.09, 0.09, 0.24, well), Vector3(0, -0.215, 0))
				AKit.part(knee, Kit.torus(0.08, 0.1, AKit.m(AKit.shade(well_c, 0.12))), Vector3(0, -0.1, 0), Vector3.ZERO, Vector3(1, 1.1, 1))
				AKit.part(knee, Kit.sphere(0.094, well), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(1.0, 0.66, 1.4))
				_sole(knee, AKit.shade(well_c, 0.4), 0.09)
			"buckle_boots":
				var bb_c := LookColors.channel(id, "boots", col)
				var bb := AKit.m(bb_c)
				AKit.part(knee, Kit.cylinder(0.076, 0.082, 0.18, bb), Vector3(0, -0.205, 0))
				AKit.part(knee, Kit.cylinder(0.088, 0.082, 0.05, AKit.m(AKit.shade(bb_c, 0.15))), Vector3(0, -0.12, 0))
				AKit.part(knee, Kit.box(Vector3(0.032, 0.024, 0.01), AKit.flat(LookColors.fixed(id, "buckles", AKit.BRASS))), Vector3(0, -0.19, 0.083), Vector3.ZERO, Vector3.ONE, false)
				AKit.part(knee, Kit.sphere(0.084, bb), Vector3(0, -0.292, 0.055), Vector3.ZERO, Vector3(0.9, 0.6, 1.6))
				_sole(knee, SOLE, 0.08)
			"velvet_slippers":
				var sl_c := LookColors.channel(id, "slippers", col)
				AKit.part(knee, Kit.capsule(0.056, 0.14, leg_skin), Vector3(0, -0.245, 0))
				AKit.part(knee, Kit.sphere(0.084, AKit.m(sl_c)), Vector3(0, -0.305, 0.035), Vector3.ZERO, Vector3(1.0, 0.5, 1.42))
				var bows := AKit.m(LookColors.fixed(id, "bows", Color("2f3158")), false)
				for s4 in 2:
					var s := 1.0 if s4 == 0 else -1.0
					AKit.part(knee, Kit.sphere(0.016, bows, 8, 10), Vector3(0.016 * s, -0.28, 0.1), Vector3(0, 0, 20 * s), Vector3(1.4, 0.8, 0.6), false)
				_sole(knee, AKit.shade(sl_c, 0.35), 0.078)
			_:
				_explorer_boots(knee, id)
	return {}


## Chapter One boots: shaft, cuff, rounded toe and a little sole (exact).
static func _explorer_boots(knee: Node3D, id: String) -> void:
	var boots := LookColors.fixed(id, "boots", Palette.K_BOOTS)
	AKit.part(knee, Kit.cylinder(0.078, 0.084, 0.16, AKit.m(boots)), Vector3(0, -0.2, 0.0))
	AKit.part(knee, Kit.torus(0.07, 0.094, AKit.m(LookColors.fixed(id, "cuff", Color("8a5a36")))), Vector3(0, -0.125, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
	AKit.part(knee, Kit.sphere(0.088, AKit.m(boots)), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(0.98, 0.64, 1.42))
	AKit.part(knee, Kit.cylinder(0.082, 0.082, 0.024, AKit.m(LookColors.fixed(id, "sole", SOLE), true, 0.006), 16), Vector3(0, -0.338, 0.042), Vector3.ZERO, Vector3(1.0, 1.0, 1.42), false)


static func _sole(knee: Node3D, c: Color, r: float) -> void:
	AKit.part(knee, Kit.cylinder(r, r, 0.022, AKit.m(c, true, 0.006), 16), Vector3(0, -0.338, 0.04), Vector3.ZERO, Vector3(1.0, 1.0, 1.42), false)
