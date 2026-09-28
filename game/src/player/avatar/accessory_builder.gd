extends RefCounted
## Krystal's hats, hair accessories and visible back accessories (data/appearance.gd PARTS slots hat /
## hair_acc / back). Hats are non-obstructive: small or tilted-back brims, nothing below the brows, so the
## camera always sees her face; the avatar adds their silhouette to the roll head hull.
##   build_hat(ctx)      -> {"hull": "all", "roll_squash": Node3D (a tall hat folded down while rolling) | absent}
##   build_hair_acc(ctx) -> {"hull": "all" | ""}
##   build_back(ctx)     -> {"chains": [...], "belt": Node3D (the belt lantern holder), "cape": bool}
## The Chapter One flower clip and satchel (+ belt lantern) are reproduced part for part.
## Hair accessories and the flower crown sit ON the hair of the current hairstyle (ctx["hair_prims"], the hair surface
## probe of hair_builder.gd): every anchor is pushed out along its direction from the hair centre until the piece rests
## on the hair instead of inside it (the Chapter One clip on the Chapter One braid keeps its exact spot). With a hat on,
## anchors drop below the brim line first. Capes move out over body armor (ctx["armor_body"]).

const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const LookColors := preload("res://src/player/avatar/look_colors.gd")
const HairBuilder := preload("res://src/player/avatar/hair_builder.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")

const LEATHER := Color("6e4a33")
const WOOD := Color("8a6242")
## With a hat on, hair accessories stay below this height (HeadCenter space) so no brim or crown swallows them.
const HAT_LINE := 0.1
## Chorister capelet fallback when both of its channels match the top it is worn over.
const CHOIR_CREAM := Color("f3ead6")


# =====================================================================================================
# Hats
# =====================================================================================================

static func build_hat(ctx: Dictionary) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var hc: Node3D = ctx["box"].call("head_c")
	match id:
		"sun_hat":
			var straw_c := LookColors.fixed(id, "straw", Color("e6cf8a"))
			var straw := AKit.m(straw_c)
			var hat := AKit.node(hc, Vector3(0, 0.2, -0.02), "SunHat")
			hat.rotation_degrees = Vector3(-12, 0, 0)
			AKit.part(hat, Kit.cylinder(0.205, 0.235, 0.14, straw, 24), Vector3(0, 0.07, 0))
			AKit.part(hat, Kit.sphere(0.205, straw, 12, 24), Vector3(0, 0.14, 0), Vector3.ZERO, Vector3(1.0, 0.32, 1.0))
			AKit.part(hat, Kit.cylinder(0.34, 0.34, 0.018, straw, 28), Vector3.ZERO)
			AKit.part(hat, Kit.torus(0.33, 0.35, AKit.m(AKit.shade(straw_c, 0.12))), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.7, 1))
			var band_c := LookColors.channel(id, "band", col)
			AKit.part(hat, Kit.torus(0.228, 0.244, AKit.m(band_c, true, 0.006)), Vector3(0, 0.022, 0), Vector3.ZERO, Vector3(1, 2.4, 1))
			_flower(hat, Vector3(0.2, 0.04, 0.1), Color("fff4e0"), Palette.FLOWER_YELLOW, 0.8)
		"mushroom_beret":
			# a toadstool cap: a rounder dome, a few big cream spots, pale gills showing under the rim and a stalk nub
			var beret_c := LookColors.channel(id, "beret", col)
			var spots_c := LookColors.fixed(id, "spots", Color("fff4e0"))
			var hat := AKit.node(hc, Vector3(0.02, 0.22, -0.04), "Beret")
			hat.rotation_degrees = Vector3(-8, 0, 10)
			AKit.part(hat, Kit.sphere(0.27, AKit.m(beret_c), 16, 28), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.05, 0.62, 1.0))
			AKit.part(hat, Kit.torus(0.2, 0.25, AKit.m(AKit.shade(spots_c, 0.12))), Vector3(0, -0.012, 0), Vector3.ZERO, Vector3(1.04, 0.5, 1.0))
			var spots := AKit.m(spots_c, false)
			var spot_at := [[0.0, 0.0], [0.4, 0.62], [2.3, 0.6], [4.1, 0.62], [5.4, 0.55]]
			for sp in spot_at:
				var a: float = sp[0]
				var f: float = sp[1]
				var y := 0.02 + 0.27 * 0.62 * sqrt(maxf(0.0, 1.0 - f * f))
				var n := Vector3(cos(a) * f * 1.05, sqrt(maxf(0.0, 1.0 - f * f)) * 0.62, sin(a) * f).normalized()
				var tilt := Basis(Quaternion(Vector3.UP, n)).get_euler() * (180.0 / PI)
				AKit.part(hat, Kit.sphere(0.058 if f > 0.1 else 0.064, spots, 8, 12), Vector3(cos(a) * 0.27 * 1.05 * f, y, sin(a) * 0.27 * f), tilt, Vector3(1.0, 0.3, 1.0), false)
			AKit.part(hat, Kit.capsule(0.02, 0.05, AKit.m(beret_c)), Vector3(0, 0.185, 0), Vector3(0, 0, 18))
		"witch_hat":
			var hat_c := LookColors.channel(id, "hat", col)
			var mat := AKit.m(hat_c)
			var hat := AKit.node(hc, Vector3(0, 0.21, -0.03), "WitchHat")
			hat.rotation_degrees = Vector3(-10, 0, 0)
			AKit.part(hat, Kit.cylinder(0.33, 0.33, 0.016, mat, 28), Vector3.ZERO)
			AKit.part(hat, Kit.torus(0.32, 0.34, AKit.m(AKit.shade(hat_c, 0.15))), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.6, 1))
			AKit.part(hat, Kit.cylinder(0.14, 0.215, 0.16, mat, 20), Vector3(0, 0.08, 0))
			# the bent tip: two more segments folded back (static, so they bake with the crown)
			var t1 := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18.0)), Vector3(0, 0.16, 0))
			var t2 := t1 * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-32.0)), Vector3(0, 0.14, 0))
			AKit.part_xf(hat, Kit.cylinder(0.085, 0.14, 0.14, mat, 18), t1 * Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0)))
			AKit.part_xf(hat, Kit.cone(0.085, 0.16, mat, 16), t2 * Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)))
			var ribbon_c := LookColors.channel(id, "ribbon", col)
			var ribbon := AKit.m(ribbon_c, true, 0.006)
			AKit.part(hat, Kit.torus(0.2, 0.218, ribbon), Vector3(0, 0.025, 0), Vector3.ZERO, Vector3(1, 2.4, 1))
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(hat, Kit.sphere(0.04, ribbon, 8, 12), Vector3(0.19 + 0.02 * s, 0.035, 0.1 + 0.035 * s), Vector3(0, 60, -20 * s), Vector3(1.4, 0.8, 0.5))
				AKit.part(hat, Kit.box(Vector3(0.025, 0.09, 0.008), ribbon), Vector3(0.21, -0.02, 0.1 + 0.02 * s), Vector3(0, 60, 12 * s))
			# the tall bent tip folds down while she rolls (krystal_avatar.gd ROLL_HAT_SQUASH), so it never props up the ball
			return {"hull": "all", "roll_squash": hat}
		"flower_crown":
			_flower_crown(ctx, hc, col)
		_:
			return {"hull": ""}
	return {"hull": "all"}


## The Lantern Flower Crown fitted to the hairstyle: a leafy ring resting on top of the hair (an ellipse sized from the
## hair surface probe at the lowest height where it stays compact, so it rides above a braided crown and below space
## buns) with big flowers and leaf sprigs all the way round, so it also reads from behind.
static func _flower_crown(ctx: Dictionary, hc: Node3D, col: Dictionary) -> void:
	var id := "flower_crown"
	var prims: Array = ctx.get("hair_prims", [])
	const TILT := -8.0
	const TUBE := 0.022
	var basis := Basis(Vector3.RIGHT, deg_to_rad(TILT))
	var best: Array = []
	for yi in 6:
		var y := 0.24 - 0.02 * float(yi)
		var fit := _crown_fit(prims, Vector3(0, y, -0.05), basis)
		if best.is_empty() or float(fit[0]) < float(best[0]) - 0.001:
			best = fit
			best.append(y)
		if float(fit[0]) <= 0.3:
			break
	var rx: float = best[1]
	var rf: float = best[2]
	var rb: float = best[3]
	var yc: float = best[4]
	var rz := (rf + rb) * 0.5
	var crown := AKit.node(hc, Vector3(0, yc, -0.05) + basis * Vector3(0, 0, (rf - rb) * 0.5), "FlowerCrown")
	crown.rotation_degrees = Vector3(TILT, 0, 0)
	var leaves_c := LookColors.channel(id, "leaves", col)
	var leaves := AKit.m(leaves_c)
	const R0 := 0.255
	AKit.part(crown, Kit.torus(R0 - TUBE * 0.5, R0 + TUBE * 0.5, leaves), Vector3.ZERO, Vector3.ZERO, Vector3(rx / R0, 1.5, rz / R0))
	var flower_c := LookColors.fixed(id, "flowers", Palette.FLOWER_YELLOW)
	var leaf_dark := AKit.m(AKit.shade(leaves_c, 0.15))
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := Vector3(sin(a) * (rx + 0.006), 0.012, cos(a) * (rz + 0.006))
		if i % 2 == 0:
			_flower(crown, p, flower_c if i % 4 == 0 else Color("fff4e0"), Palette.FLOWER_YELLOW if i % 4 != 0 else Color("fff4e0"), 1.4)
		else:
			AKit.part(crown, Kit.sphere(0.034, leaf_dark, 8, 10), p, Vector3(0, rad_to_deg(a), 30), Vector3(1.7, 0.6, 0.45))


## Fit of a crown ring at `c` (HeadCenter space, ring plane = `b` * XZ): [max radius, x radius, front radius, back radius].
static func _crown_fit(prims: Array, c: Vector3, b: Basis) -> Array:
	var rx := 0.2
	var rf := 0.2
	var rb := 0.2
	var worst := 0.0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var d := b * Vector3(sin(a), 0, cos(a))
		var r := maxf(HairBuilder.reach_from(prims, c, d, 0.02), 0.2) + 0.03
		worst = maxf(worst, r)
		var sa := absf(sin(a))
		var ca := cos(a)
		if sa > 0.7:
			rx = maxf(rx, r * sa)
		if ca > 0.7:
			rf = maxf(rf, r * ca)
		elif ca < -0.7:
			rb = maxf(rb, r * -ca)
	# an ellipse through those radii must still clear every sample (grow it when a diagonal pokes out)
	for i in 16:
		var a := TAU * float(i) / 16.0
		var d := b * Vector3(sin(a), 0, cos(a))
		var r := maxf(HairBuilder.reach_from(prims, c, d, 0.02), 0.2) + 0.03
		var rz := rf if cos(a) >= 0.0 else rb
		var e := Vector2(sin(a) / rx, cos(a) / rz).length()
		var have := 1.0 / maxf(e, 0.0001)
		if have < r:
			var k := r / have
			rx *= k
			rf *= k
			rb *= k
	return [maxf(rx, maxf(rf, rb)), rx, rf, rb]


## Five-petal flower facing outward from `pos` (in `parent` space).
static func _flower(parent: Node3D, pos: Vector3, petal: Color, centre: Color, scale: float) -> void:
	var f := AKit.node(parent, pos, "Flower")
	f.rotation = Vector3(0, atan2(pos.x, pos.z), 0)
	f.scale = Vector3.ONE * scale
	for i in 5:
		var a := TAU * float(i) / 5.0
		AKit.part(f, Kit.sphere(0.024, AKit.m(petal, true, 0.005), 8, 10), Vector3(cos(a) * 0.026, sin(a) * 0.026, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.45), false)
	AKit.part(f, Kit.sphere(0.016, AKit.m(centre, false), 8, 10), Vector3(0, 0, 0.01), Vector3.ZERO, Vector3.ONE, false)


# =====================================================================================================
# Hair accessories
# =====================================================================================================

## A hair accessory anchor on the OUTSIDE of the current hair: `p` (HeadCenter space; with a hat on, first lowered
## below HAT_LINE) pushed out along its direction from the hair centre until it sits `lift` beyond the hair surface
## under a footprint of radius `foot`. Never pulled in.
static func _on_hair(ctx: Dictionary, p: Vector3, foot: float, lift: float) -> Vector3:
	var q := p
	if String(ctx.get("hat", "")) != "":
		q.y = minf(q.y, HAT_LINE)
	var prims: Array = ctx.get("hair_prims", [])
	if prims.is_empty():
		return q
	var c := HairBuilder.CENTRE
	var d := (q - c).normalized()
	return c + d * maxf((q - c).length(), HairBuilder.reach(prims, d, foot) + lift)


static func build_hair_acc(ctx: Dictionary) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var hc: Node3D = ctx["box"].call("head_c")
	var hair := String(ctx["look"].get("hair", ""))
	var hat_on := String(ctx.get("hat", "")) != ""
	match id:
		"flower_clip":
			# Chapter One: flower clip on the left side of the head (five petals + honey centre); on the Chapter One
			# braid it keeps its exact spot, on bulkier hairstyles it moves out onto the hair
			var at := Vector3(0.2, 0.13, 0.1)
			if hair != "side_braid" or hat_on:
				at = _on_hair(ctx, at, 0.03, 0.012)
			var clip := AKit.node(hc, at, "FlowerClip")
			clip.rotation_degrees = Vector3(-10, 55, 10)
			var petals := LookColors.fixed(id, "petals", Palette.FLOWER_WHITE)
			for i in 5:
				var a := TAU * float(i) / 5.0
				AKit.part(clip, Kit.sphere(0.024, AKit.m(petals, true, 0.005), 8, 10), Vector3(cos(a) * 0.026, sin(a) * 0.026, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.45), false)
			AKit.part(clip, Kit.sphere(0.016, AKit.m(LookColors.fixed(id, "centre", Palette.FLOWER_YELLOW), false), 8, 10), Vector3(0, 0, 0.01), Vector3.ZERO, Vector3.ONE, false)
			return {"hull": ""}
		"strawberry_clip":
			var berry := AKit.m(LookColors.fixed(id, "berry", Color("e4665c")), true, 0.005)
			var leaf := AKit.m(LookColors.fixed(id, "leaf", Color("7fa35a")), false)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				var n := AKit.node(hc, _on_hair(ctx, Vector3(0.205 * s, 0.12, 0.08), 0.03, 0.028), "Strawberry%d" % side)
				n.rotation_degrees = Vector3(0, 55 * s, 15 * s)
				n.scale = Vector3.ONE * 1.45
				AKit.part(n, Kit.sphere(0.028, berry, 8, 12), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.2, 0.9), false)
				for k in 3:
					var a := TAU * float(k) / 3.0
					AKit.part(n, Kit.sphere(0.012, leaf, 6, 8), Vector3(cos(a) * 0.012, 0.03, sin(a) * 0.012), Vector3.ZERO, Vector3(1.4, 0.5, 1.0), false)
		"big_bow", "ribbon_bow":
			var bow_c := LookColors.channel(id, "bow" if id == "big_bow" else "ribbon", col)
			var pos := Vector3(0, 0.14, -0.27)
			var rot := Vector3(-20, 0, 0)
			var sc := 1.0
			if id == "ribbon_bow":
				# turned toward the back so the usual camera (behind her) sees the loops, not the edge
				pos = Vector3(-0.19, 0.15, -0.12)
				rot = Vector3(0, -125, 10)
				sc = 0.8
			elif hair == "high_ponytail" and not hat_on:
				pos = Vector3(0, 0.26, -0.2)
				rot = Vector3(-45, 0, 0)
				sc = 0.75
			_bow(hc, "Bow", _on_hair(ctx, pos, 0.05 * sc, 0.035 * sc), rot, sc, AKit.m(bow_c, true, 0.006))
		"star_pins":
			var star := AKit.m(LookColors.fixed(id, "stars", Color("f7e08a")), false)
			for p in [Vector3(0.19, 0.16, 0.1), Vector3(0.22, 0.09, 0.06), Vector3(0.16, 0.21, 0.04)]:
				var n := AKit.node(hc, _on_hair(ctx, p, 0.02, 0.016), "Star")
				n.rotation = Vector3(0, atan2(p.x, p.z), 0)
				n.scale = Vector3.ONE * 1.5
				AKit.part(n, Kit.sphere(0.012, star, 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.6), false)
				for k in 5:
					var a := TAU * float(k) / 5.0
					AKit.part(n, Kit.capsule(0.007, 0.03, star), Vector3(sin(a) * 0.013, cos(a) * 0.013, 0), Vector3(0, 0, -rad_to_deg(a)), Vector3(1, 1, 0.6), false)
		"leaf_clip":
			var leaf_c := LookColors.fixed(id, "leaf", Color("e9a15b"))
			var n := AKit.node(hc, _on_hair(ctx, Vector3(0.2, 0.13, 0.06), 0.035, 0.02), "Leaf")
			n.rotation_degrees = Vector3(-10, 75, 30)
			n.scale = Vector3.ONE * 1.35
			AKit.part(n, Kit.sphere(0.045, AKit.m(leaf_c, true, 0.005), 10, 12), Vector3.ZERO, Vector3.ZERO, Vector3(1.85, 0.8, 0.3), false)
			AKit.part(n, Kit.capsule(0.004, 0.08, AKit.flat(AKit.shade(leaf_c, 0.3))), Vector3(0, 0, 0.012), Vector3(0, 0, 90), Vector3.ONE, false)
			AKit.part(n, Kit.capsule(0.005, 0.03, AKit.flat(AKit.shade(leaf_c, 0.4))), Vector3(-0.08, 0, 0.004), Vector3(0, 0, 70), Vector3.ONE, false)
		"ribbon_ties":
			var rib := AKit.m(LookColors.channel(id, "ribbons", col), true, 0.006)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				# turned out and back so the ties read from behind (the usual camera)
				_bow(hc, "Tie%d" % side, _on_hair(ctx, Vector3(0.2 * s, -0.03, -0.1), 0.04, 0.025), Vector3(0, 110 * s, 0), 0.62, rib)
		"bat_bow":
			var bat_c := LookColors.channel(id, "bow", col)
			var mat := AKit.m(bat_c, true, 0.006)
			var n := AKit.node(hc, _on_hair(ctx, Vector3(0.16, 0.2, -0.02), 0.06, 0.024), "BatBow")
			n.rotation_degrees = Vector3(0, 80, -20)
			n.scale = Vector3.ONE * 1.25
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(n, Kit.sphere(0.05, mat, 10, 12), Vector3(0.055 * s, 0.01, 0), Vector3(0, 0, 12 * s), Vector3(1.5, 0.75, 0.3))
				for k in 3:
					AKit.part(n, Kit.sphere(0.018, mat, 6, 8), Vector3(s * (0.03 + 0.03 * float(k)), -0.028, 0), Vector3.ZERO, Vector3(1, 1, 0.4), false)
			AKit.part(n, Kit.sphere(0.02, AKit.m(AKit.shade(bat_c, 0.2), false), 8, 10), Vector3(0, 0.01, 0.005), Vector3.ZERO, Vector3.ONE, false)
		"glow_pins":
			var glow := Mat.glow(LookColors.fixed(id, "glow", Color("d8e8ff")), 1.0)
			var pin := AKit.flat(Color("c8ccd8"))
			for p in [Vector3(0.18, 0.17, 0.06), Vector3(0.21, 0.1, 0.02), Vector3(-0.19, 0.16, 0.04)]:
				var n := AKit.node(hc, _on_hair(ctx, p, 0.02, 0.014), "GlowPin")
				n.rotation = Vector3(0, atan2(p.x, p.z), 0)
				n.scale = Vector3.ONE * 1.6
				AKit.part(n, Kit.capsule(0.004, 0.05, pin), Vector3(0, -0.015, -0.01), Vector3(30, 0, 0), Vector3.ONE, false)
				AKit.part(n, Kit.sphere(0.016, glow, 8, 10), Vector3(0, 0.01, 0.005), Vector3.ZERO, Vector3.ONE, false)
		"moth_antennae_band":
			var band := AKit.m(LookColors.channel(id, "band", col), true, 0.006)
			var arch := MeshInstance3D.new()
			arch.mesh = AKit.arc_mesh(0.27, 0.011, PI)
			arch.material_override = band
			var y_top := 0.35 if not hat_on else 0.3
			var band_sc := Vector3(1.04, 1.0, 1.0)
			if not hat_on:
				# the band arches over the hair (buns, crowns) instead of through it: taller where the top needs it,
				# wider only where the sides do (its ends stay at her temples)
				var prims: Array = ctx.get("hair_prims", [])
				var top := 0.27
				var wide := 0.27
				for k in 9:
					var b := lerpf(-1.35, 1.35, float(k) / 8.0)
					var r := HairBuilder.reach_from(prims, Vector3(0, 0.08, 0.03), Vector3(sin(b), cos(b), 0.0), 0.0) + 0.012
					top = maxf(top, r * cos(b))
					if absf(b) > 0.9:
						wide = maxf(wide, r * absf(sin(b)))
				band_sc = Vector3(1.04 * wide / 0.27, top / 0.27, 1.0)
				y_top = 0.08 + top
			AKit.part(hc, arch, Vector3(0, y_top, 0.03), Vector3(0, 0, 180), band_sc)
			var tips := AKit.m(LookColors.fixed(id, "tips", Color("d9dcf5")), true, 0.005)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				var a := AKit.node(hc, Vector3(0.06 * s, y_top - 0.01, 0.05), "Antenna%d" % side)
				a.rotation_degrees = Vector3(-25, 0, -20 * s)
				AKit.part(a, Kit.capsule(0.006, 0.12, band), Vector3(0, 0.055, 0))
				var t := AKit.node(a, Vector3(0, 0.11, 0), "AntennaTip")
				t.rotation_degrees = Vector3(-35, 0, -25 * s)
				AKit.part(t, Kit.capsule(0.006, 0.07, band), Vector3(0, 0.03, 0))
				AKit.part(t, Kit.sphere(0.026, tips, 8, 12), Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(0.6, 1.5, 1.2))
		"lantern_ribbon":
			# a ribbon bow on her left side with a little glowing paper lantern hanging from it, clear of the hair
			var rib_c := LookColors.channel(id, "ribbon", col)
			var bow_at := _on_hair(ctx, Vector3(0.19, 0.13, -0.1), 0.02, 0.025)
			_bow(hc, "LanternBow", bow_at, Vector3(0, 85, 10), 0.72, AKit.m(rib_c, true, 0.006))
			var out := (bow_at - HairBuilder.CENTRE).normalized()
			var hang := AKit.node(hc, bow_at + Vector3(out.x, 0.0, out.z).normalized() * 0.035 + Vector3(0, -0.03, 0), "PaperLantern")
			AKit.part(hang, Kit.capsule(0.004, 0.06, AKit.flat(AKit.shade(rib_c, 0.3))), Vector3(0, -0.025, 0), Vector3.ZERO, Vector3.ONE, false)
			AKit.part(hang, Kit.sphere(0.034, Mat.glow(LookColors.fixed(id, "lantern", Color("ffc978")), 1.2), 8, 10), Vector3(0, -0.075, 0), Vector3.ZERO, Vector3(1, 1.2, 1), false)
			AKit.part(hang, Kit.cylinder(0.018, 0.022, 0.012, AKit.m(AKit.shade(rib_c, 0.3), false), 8), Vector3(0, -0.035, 0), Vector3.ZERO, Vector3.ONE, false)
		"masquerade_mask":
			# A little domino mask pushed up into the hair on her left side, facing outward, its back tip raised
			# (worn like a hair ornament, never over the face; tests check it stays beside / above the ear).
			var mask_c := LookColors.channel(id, "mask", col)
			var mask := AKit.m(mask_c, true, 0.006)
			var n := AKit.node(hc, _on_hair(ctx, Vector3(0.28, 0.11, -0.03) if hat_on else Vector3(0.266, 0.16, -0.024), 0.04, 0.012), "MasqueradeMask")
			n.rotation_degrees = Vector3(-15, 75, 20)
			n.scale = Vector3.ONE * 0.75
			var hole := AKit.flat(AKit.shade(mask_c, 0.6))
			var trim := AKit.m(LookColors.fixed(id, "trim", AKit.BRASS), false)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(n, Kit.sphere(0.045, mask, 8, 12), Vector3(0.043 * s, 0, 0), Vector3(0, 0, 14 * s), Vector3(1.3, 0.85, 0.4))
				AKit.part(n, Kit.sphere(0.018, hole, 6, 8), Vector3(0.045 * s, 0.002, 0.016), Vector3(0, 0, 14 * s), Vector3(1.35, 0.7, 0.3), false)
				AKit.part(n, Kit.sphere(0.012, trim, 6, 8), Vector3(0.1 * s, 0.022, 0.006), Vector3.ZERO, Vector3.ONE, false)
			AKit.part(n, Kit.sphere(0.03, trim, 6, 8), Vector3(0, 0.012, 0.008), Vector3.ZERO, Vector3(0.6, 0.5, 0.3), false)
			# a soft plume tucked into the hair behind the raised back tip
			var plume := AKit.m(LookColors.channel(id, "plume", col), true, 0.005)
			AKit.part(n, Kit.sphere(0.03, plume, 8, 10), Vector3(0.11, 0.05, -0.012), Vector3(0, 0, -28), Vector3(0.5, 1.9, 0.3))
		"chime_ribbons":
			# A ribbon bow on her right side with three short streamers (tilted out, clear of the hair), each ending
			# in a tiny chime bell.
			var rib_c := LookColors.channel(id, "ribbons", col)
			var rib := AKit.m(rib_c, true, 0.006)
			var bow := _bow(hc, "ChimeBow", _on_hair(ctx, Vector3(-0.27, 0.12, -0.12) if hat_on else Vector3(-0.26, 0.17, -0.12), 0.04, 0.02), Vector3(-30, -62, 0), 0.6, rib)
			var bell := AKit.metal(LookColors.fixed(id, "chimes", Color("e8c66a")), 0.005)
			for k in 3:
				var x := (float(k) - 1.0) * 0.045
				var ln := 0.13 + 0.035 * float(1 - absi(k - 1))
				AKit.part(bow, Kit.box(Vector3(0.028, ln, 0.01), rib), Vector3(x, -0.05 - ln * 0.5, -0.004), Vector3(0, 0, -6.0 * (float(k) - 1.0)))
				var b := AKit.node(bow, Vector3(x * 1.15, -0.06 - ln, -0.004), "Chime%d" % k)
				AKit.part(b, Kit.sphere(0.03, bell, 6, 10), Vector3(0, 0.004, 0), Vector3.ZERO, Vector3(1.0, 1.15, 1.0), false)
				AKit.part(b, Kit.cylinder(0.02, 0.034, 0.024, bell, 10), Vector3(0, -0.018, 0), Vector3.ZERO, Vector3.ONE, false)
		_:
			return {"hull": ""}
	return {"hull": "all"}


## A two-loop ribbon bow with a knot and two tails.
static func _bow(parent: Node3D, nm: String, pos: Vector3, rot_deg: Vector3, sc: float, mat: Material) -> Node3D:
	var n := AKit.node(parent, pos, nm)
	n.rotation_degrees = rot_deg
	n.scale = Vector3.ONE * sc
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(n, Kit.sphere(0.07, mat, 10, 14), Vector3(0.075 * s, 0, 0), Vector3(0, 0, -15 * s), Vector3(1.5, 1.0, 0.55))
		AKit.part(n, Kit.box(Vector3(0.035, 0.1, 0.012), mat), Vector3(0.03 * s, -0.07, 0), Vector3(0, 0, 15 * s))
	AKit.part(n, Kit.sphere(0.032, mat, 8, 12), Vector3(0, 0, 0.01))
	return n


# =====================================================================================================
# Back accessories
# =====================================================================================================

static func build_back(ctx: Dictionary) -> Dictionary:
	var id := String(ctx["id"])
	var col: Dictionary = ctx["col"]
	var box: Callable = ctx["box"]
	var spine: Node3D = box.call("spine")
	var res := {"chains": [], "belt": null, "cape": bool(ItemDB.appearance_part(id).get("cape", false))}
	match id:
		"":
			res["belt"] = _belt_clip(spine)
		"picnic_basket":
			var wicker_c := LookColors.fixed(id, "wicker", Color("c9a26e"))
			var wicker := AKit.m(wicker_c)
			var b := AKit.node(spine, Vector3(0, 0.2, -0.205), "Basket")
			AKit.part(b, Kit.cylinder(0.12, 0.11, 0.15, wicker, 18), Vector3.ZERO, Vector3.ZERO, Vector3(1.25, 1.0, 0.7))
			AKit.part(b, Kit.torus(0.11, 0.13, AKit.m(AKit.shade(wicker_c, 0.15))), Vector3(0, 0.075, 0), Vector3.ZERO, Vector3(1.25, 1.0, 0.7))
			AKit.part(b, Kit.sphere(0.12, AKit.m(LookColors.channel(id, "cloth", col)), 12, 18), Vector3(0, 0.085, 0), Vector3.ZERO, Vector3(1.2, 0.35, 0.75))
			AKit.part(b, Kit.torus(0.085, 0.1, AKit.m(AKit.shade(wicker_c, 0.1))), Vector3(0, 0.08, 0), Vector3(90, 0, 0), Vector3(1.2, 1.0, 1.0))
			_front_straps(spine, AKit.m(AKit.shade(wicker_c, 0.25)))
			res["belt"] = _belt_clip(spine)
		"bedroll_pack":
			var strap_c := LookColors.fixed(id, "straps", Color("6b4428"))
			var straps := AKit.m(strap_c)
			var p := AKit.node(spine, Vector3(0, 0.2, -0.19), "Pack")
			AKit.part(p, Kit.sphere(0.12, straps, 12, 18), Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 1.25, 0.6))
			AKit.part(p, Kit.sphere(0.1, AKit.m(AKit.shade(strap_c, 0.15)), 10, 14), Vector3(0, 0.09, -0.01), Vector3.ZERO, Vector3(1.1, 0.5, 0.6))
			var roll := AKit.m(LookColors.channel(id, "roll", col))
			AKit.part(p, Kit.cylinder(0.055, 0.055, 0.34, roll, 16), Vector3(0, 0.17, 0), Vector3(0, 0, 90))
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(p, Kit.torus(0.05, 0.063, AKit.m(LEATHER, true, 0.006)), Vector3(0.09 * s, 0.17, 0), Vector3(0, 0, 90))
			_front_straps(spine, straps)
			res["belt"] = _belt_clip(spine)
		"tote_bag":
			var tote_c := LookColors.channel(id, "tote", col)
			var tote := AKit.m(tote_c)
			AKit.part(spine, Kit.torus(0.17, 0.2, tote), Vector3(0.03, 0.2, 0), Vector3(0, 0, -57), Vector3(1.42, 0.9, 0.78))
			var bag := AKit.node(spine, Vector3(0.2, 0.0, -0.07), "Tote")
			bag.rotation_degrees = Vector3(0, 115, -5)
			AKit.part(bag, Kit.box(Vector3(0.2, 0.19, 0.05), tote), Vector3(0, -0.02, 0))
			AKit.part(bag, Kit.sphere(0.035, AKit.m(AKit.lighten(tote_c, 0.35), false), 8, 12), Vector3(0.03, 0.0, 0.028), Vector3.ZERO, Vector3(1.4, 0.9, 0.3), false)
			var belt := AKit.node(bag, Vector3(0.07, 0.04, 0.05), "BeltLantern")
			res["belt"] = belt
		"acorn_pack":
			var cap_c := LookColors.fixed(id, "cap", Color("7a5236"))
			var cap := AKit.m(cap_c)
			var p := AKit.node(spine, Vector3(0, 0.17, -0.2), "Acorn")
			AKit.part(p, Kit.sphere(0.13, AKit.m(LookColors.fixed(id, "nut", Color("c98a55"))), 14, 20), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.15, 0.8))
			AKit.part(p, Kit.sphere(0.136, cap, 14, 20), Vector3(0, 0.11, 0), Vector3.ZERO, Vector3(1.08, 0.55, 0.86))
			AKit.part(p, Kit.capsule(0.013, 0.06, cap), Vector3(0, 0.19, 0), Vector3(0, 0, 15))
			var dots := AKit.flat(AKit.shade(cap_c, 0.25))
			for k in 6:
				var a := TAU * float(k) / 6.0
				AKit.part(p, Kit.sphere(0.014, dots, 6, 8), Vector3(cos(a) * 0.1, 0.13, sin(a) * 0.08), Vector3.ZERO, Vector3(1, 0.5, 1), false)
			_front_straps(spine, cap)
			res["belt"] = _belt_clip(spine)
		"leaf_cape", "little_cape", "moth_shawl", "opera_cloak", "chorister_capelet":
			res["chains"].append(_cape(ctx, id))
			res["belt"] = _belt_clip(spine)
		"ghostlight_wings":
			# bigger, faintly sky-tinted wings with a soft glow by day too and a deeper-blue vein panel, so they still
			# separate from a pale dress and pale hair in sunlight
			var wing_c := LookColors.fixed(id, "wings", Color("e8f0ff"))
			var wing := AKit.softglow(wing_c.lerp(Color("a9d0f5"), 0.3), 0.5)
			var vein := AKit.softglow(wing_c.lerp(Color("7fa8e0"), 0.55), 0.45)
			var chest: Node3D = box.call("chest")
			var segs: Array = []
			var rest: Array = []
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				var w := AKit.node(chest, Vector3(0.05 * s, -0.02, -0.15), "Wing%d" % side)
				var r := Vector3(0.1, 0.55 * s, 0.25 * s)
				w.rotation = r
				AKit.part(w, Kit.sphere(0.17, wing, 12, 16), Vector3(0.17 * s, 0.08, -0.02), Vector3(0, 0, -25 * s), Vector3(1.5, 1.0, 0.1))
				AKit.part(w, Kit.sphere(0.12, wing, 10, 14), Vector3(0.13 * s, -0.13, -0.02), Vector3(0, 0, 30 * s), Vector3(1.3, 1.0, 0.1))
				AKit.part(w, Kit.sphere(0.1, vein, 10, 14), Vector3(0.17 * s, 0.08, -0.03), Vector3(0, 0, -25 * s), Vector3(1.4, 0.8, 0.08), false)
				AKit.part(w, Kit.sphere(0.065, vein, 8, 12), Vector3(0.13 * s, -0.13, -0.03), Vector3(0, 0, 30 * s), Vector3(1.2, 0.8, 0.08), false)
				segs.append(w)
				rest.append(r)
			var ch := AKit.chain("wing", segs, rest, 30.0, 4.0)
			res["chains"].append(ch)
			res["belt"] = _belt_clip(spine)
		"lantern_backpack":
			var wood := AKit.m(WOOD)
			var p := AKit.node(spine, Vector3(0, 0.2, -0.18), "LanternPack")
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				AKit.part(p, Kit.capsule(0.012, 0.32, wood), Vector3(0.085 * s, 0.0, 0))
			var paper_c := LookColors.channel(id, "paper", col)
			AKit.part(p, Kit.sphere(0.12, AKit.m(paper_c), 14, 20), Vector3(0, 0.02, -0.08), Vector3.ZERO, Vector3(1.0, 1.25, 0.95))
			for k in 3:
				AKit.part(p, Kit.torus(0.1 - 0.02 * absf(float(k) - 1.0), 0.118 - 0.02 * absf(float(k) - 1.0), AKit.m(AKit.shade(paper_c, 0.25), false)), Vector3(0, 0.02 + (float(k) - 1.0) * 0.08, -0.08), Vector3.ZERO, Vector3(1.0, 1.0, 0.95), false)
			AKit.part(p, Kit.cylinder(0.05, 0.06, 0.03, wood, 12), Vector3(0, 0.17, -0.08))
			AKit.part(p, Kit.cylinder(0.06, 0.05, 0.03, wood, 12), Vector3(0, -0.13, -0.08))
			AKit.part(p, Kit.sphere(0.04, Mat.glow(LookColors.fixed(id, "glow", Color("ffc978")), 1.1), 8, 12), Vector3(0, -0.15, -0.08), Vector3.ZERO, Vector3(1, 0.6, 1), false)
			_front_straps(spine, wood)
			res["belt"] = _belt_clip(spine)
		_:
			res["belt"] = _satchel(spine, id)
	return res


## Chapter One satchel: strap across the chest and the bag on the left hip, with the belt-lantern holder.
static func _satchel(spine: Node3D, id: String) -> Node3D:
	var bag_c := LookColors.fixed(id, "bag", Palette.K_BAG)
	AKit.part(spine, Kit.torus(0.17, 0.2, AKit.m(bag_c)), Vector3(0.03, 0.2, 0), Vector3(0, 0, -57), Vector3(1.42, 0.9, 0.78))
	var bag := AKit.node(spine, Vector3(0.2, 0.0, -0.07), "Satchel")
	bag.rotation_degrees = Vector3(0, 115, -5)
	AKit.part(bag, Kit.capsule(0.07, 0.21, AKit.m(bag_c)), Vector3.ZERO, Vector3(0, 0, 90), Vector3(1.05, 1.0, 0.62))
	AKit.part(bag, Kit.sphere(0.1, AKit.m(LEATHER)), Vector3(0, 0.03, 0.02), Vector3.ZERO, Vector3(1.05, 0.55, 0.52))
	AKit.part(bag, Kit.sphere(0.017, AKit.flat(AKit.BRASS), 8, 12), Vector3(0, 0.0, 0.07), Vector3.ZERO, Vector3.ONE, false)
	return AKit.node(bag, Vector3(0.07, 0.04, 0.07), "BeltLantern")


## Without a bag the lantern clips to a little belt loop on the left hip.
static func _belt_clip(spine: Node3D) -> Node3D:
	var clip := AKit.node(spine, Vector3(0.215, 0.0, 0.03), "BeltClip")
	clip.rotation_degrees = Vector3(0, 90, 0)
	AKit.part(clip, Kit.torus(0.014, 0.024, AKit.m(LEATHER, true, 0.006)), Vector3(0, 0.02, 0), Vector3(90, 0, 0), Vector3.ONE, false)
	return AKit.node(clip, Vector3(0, 0.0, 0.0), "BeltLantern")


static func _front_straps(spine: Node3D, mat: Material) -> void:
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(spine, Kit.capsule(0.017, 0.2, mat), Vector3(0.09 * s, 0.3, 0.13), Vector3(-22, 0, 0))


## Main cloth colour of an upper garment (its first palette channel) - capes check they stand out against it.
static func _upper_color(ctx: Dictionary) -> Color:
	var up := String(ctx.get("upper", ""))
	var chans: Dictionary = ItemDB.appearance_part(up).get("channels", {})
	for k in chans:
		return LookColors.channel(up, String(k), ctx["col"])
	return Color(-1, -1, -1)


static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.18


## Capes and shawls: a flat yoke over the shoulders (static) and a two-segment cloth chain down the back. Over body
## armor the cape hangs a little further out so the armor never cuts through it.
static func _cape(ctx: Dictionary, id: String) -> Dictionary:
	var col: Dictionary = ctx["col"]
	var chest: Node3D = ctx["box"].call("chest")
	var armored := bool(ctx.get("armor_body", false))
	var outer_c: Color
	var lining_c: Color
	var w0 := 0.32
	var w1 := 0.4
	var seg_len := 0.2
	var curve := Vector3(0.2, 0.22, 0.25)   # panel curvature radii: top, middle, hem
	var trim_c := Color(-1, -1, -1)
	match id:
		"little_cape":
			# a short flared vampire cape: narrow at the collar, wide at the hem with bat-wing points
			outer_c = LookColors.channel(id, "cape", col)
			lining_c = LookColors.channel(id, "lining", col)
			w0 = 0.3
			w1 = 0.58
			seg_len = 0.155
			curve = Vector3(0.18, 0.22, 0.3)
		"moth_shawl":
			# spread wider than any hair curtain so its wing shape shows from behind
			outer_c = LookColors.channel(id, "shawl", col)
			lining_c = AKit.shade(outer_c, 0.12)
			w0 = 0.46
			w1 = 0.7
			seg_len = 0.21
			curve = Vector3(0.22, 0.28, 0.36)
		"opera_cloak":
			# long and wide, a pale lining (lining channel) and a stand collar behind the neck
			outer_c = LookColors.channel(id, "cloak", col)
			lining_c = LookColors.channel(id, "lining", col)
			w0 = 0.36
			w1 = 0.56
			seg_len = 0.25
		"chorister_capelet":
			# a short round capelet with a choir collar; it never takes the colour of the top it is worn over (the
			# collar colour swaps in, or choir cream when that matches too)
			outer_c = LookColors.channel(id, "capelet", col)
			trim_c = LookColors.channel(id, "collar", col)
			var top_c := _upper_color(ctx)
			if _close(outer_c, top_c):
				var sw := outer_c
				outer_c = trim_c if not _close(trim_c, top_c) else CHOIR_CREAM
				trim_c = sw
			lining_c = AKit.shade(outer_c, 0.12)
			w0 = 0.36
			w1 = 0.5
			seg_len = 0.12
		_:
			outer_c = LookColors.channel(id, "cape", col)
			lining_c = AKit.shade(outer_c, 0.15)
	# no cape disappears into the top it is worn over: a cape in the top's colour takes its lining colour (or a
	# lighter tint of itself when the lining matches too)
	var top := _upper_color(ctx)
	if id != "chorister_capelet" and _close(outer_c, top):
		if id in ["little_cape", "opera_cloak"] and not _close(lining_c, top):
			var t := outer_c
			outer_c = lining_c
			lining_c = t
		else:
			outer_c = AKit.lighten(outer_c, 0.45)
			lining_c = AKit.shade(outer_c, 0.12)
	var outer := AKit.m(outer_c)
	var lining := AKit.m(lining_c, false)
	var push := 0.035 if armored else 0.0
	# a flat yoke over the shoulders and round the back, open at the front (a full round torus read as a neck pillow)
	const YOKE_R := 0.185
	var yoke := MeshInstance3D.new()
	yoke.mesh = AKit.arc_mesh(YOKE_R, 0.03, 4.2)
	yoke.material_override = outer
	AKit.part(chest, yoke, Vector3(0, -0.012, -0.005 - YOKE_R * (0.97 + push * 1.5) - push * 0.4), Vector3(90, 0, 0), Vector3(1.06 + push, 0.97 + push * 1.5, 0.5))
	if id == "little_cape":
		# a stand-up vampire collar behind the neck (lining colour inside) with two points
		AKit.part(chest, Kit.box(Vector3(0.24, 0.11, 0.018), outer), Vector3(0, 0.085, -0.13 - push), Vector3(-20, 0, 0))
		AKit.part(chest, Kit.box(Vector3(0.22, 0.095, 0.01), lining), Vector3(0, 0.085, -0.117 - push), Vector3(-20, 0, 0), Vector3.ONE, false)
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(chest, Kit.prism(Vector3(0.06, 0.07, 0.018), outer), Vector3(0.1 * s, 0.155, -0.155 - push), Vector3(-20, 0, -18 * s))
		AKit.part(chest, Kit.sphere(0.018, AKit.flat(AKit.BRASS), 8, 10), Vector3(0, 0.0, 0.14), Vector3.ZERO, Vector3.ONE, false)
	elif id == "opera_cloak":
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(chest, Kit.sphere(0.07, outer, 8, 12), Vector3(0.065 * s, 0.08, -0.14), Vector3(-18, -22 * s, -12 * s), Vector3(1.15, 1.1, 0.25))
			AKit.part(chest, Kit.sphere(0.062, lining, 8, 12), Vector3(0.063 * s, 0.08, -0.13), Vector3(-18, -22 * s, -12 * s), Vector3(1.1, 1.0, 0.2), false)
		AKit.part(chest, Kit.sphere(0.022, AKit.metal(LookColors.fixed(id, "clasp", AKit.BRASS), 0.006), 8, 10), Vector3(0, 0.0, 0.145), Vector3.ZERO, Vector3(1.0, 1.0, 0.6), false)
	elif id == "chorister_capelet":
		var collar := AKit.m(trim_c)
		AKit.part(chest, Kit.torus(0.13, 0.2, collar), Vector3(0, 0.03, 0.0), Vector3.ZERO, Vector3(1.08, 0.42, 1.0))
		var bell := AKit.metal(LookColors.fixed(id, "chime", Color("e8c66a")), 0.006)
		AKit.part(chest, Kit.sphere(0.024, bell, 6, 10), Vector3(0, -0.03, 0.16), Vector3.ZERO, Vector3(1.0, 1.15, 1.0), false)
		AKit.part(chest, Kit.cylinder(0.016, 0.028, 0.02, bell, 10), Vector3(0, -0.052, 0.16), Vector3.ZERO, Vector3.ONE, false)
	elif id == "leaf_cape":
		var leaf := AKit.m(LookColors.fixed(id, "leaves", Color("7fa35a")), true, 0.006)
		for k in 6:
			var a := lerpf(-1.2, 1.2, float(k) / 5.0) + PI
			AKit.part(chest, Kit.sphere(0.035, leaf, 8, 10), Vector3(sin(a) * 0.19, 0.03, cos(a) * 0.17), Vector3(0, rad_to_deg(a), 25), Vector3(1.6, 0.5, 0.9))
	else:
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(chest, Kit.sphere(0.03, AKit.m(AKit.lighten(outer_c, 0.3)), 8, 10), Vector3(0.04 * s, -0.01, 0.14), Vector3.ZERO, Vector3.ONE, false)
	var root := AKit.node(chest, Vector3(0, 0.02, -0.14 - push), "Cape")
	var rest: Array = [Vector3(-0.12 - push * 1.5, PI, 0.0), Vector3(-0.05, 0.0, 0.0)]
	root.rotation = rest[0]
	var m0 := AKit.panel_mesh(w0, lerpf(w0, w1, 0.5), seg_len, curve.x, curve.y, 0.012)
	var m1 := AKit.panel_mesh(lerpf(w0, w1, 0.5), w1, seg_len, curve.y, curve.z, 0.012)
	AKit.mesh_part(root, m0, outer, Vector3.ZERO)
	AKit.mesh_part(root, m0, lining, Vector3(0, -0.005, -0.006), Vector3.ZERO, Vector3(0.97, 0.98, 1.0), false)
	var seg := AKit.node(root, Vector3(0, -seg_len + 0.01, 0), "CapeHem")
	seg.rotation = rest[1]
	AKit.mesh_part(seg, m1, outer, Vector3.ZERO)
	AKit.mesh_part(seg, m1, lining, Vector3(0, -0.005, -0.006), Vector3.ZERO, Vector3(0.97, 0.98, 1.0), false)
	if id == "moth_shawl":
		var spot := AKit.m(LookColors.channel(id, "spots", col), false)
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(seg, Kit.sphere(0.03, spot, 8, 10), Vector3(0.12 * s, -0.08, 0.006), Vector3.ZERO, Vector3(1.0, 1.0, 0.3), false)
			AKit.part(root, Kit.sphere(0.022, spot, 8, 10), Vector3(0.1 * s, -0.1, 0.006), Vector3.ZERO, Vector3(1.0, 1.0, 0.3), false)
		for k in 5:
			var x := lerpf(-w1 * 0.4, w1 * 0.4, float(k) / 4.0)
			AKit.part(seg, Kit.sphere(0.035, outer, 8, 10), Vector3(x, -seg_len, -x * x * 1.2), Vector3.ZERO, Vector3(1.2, 0.7, 0.5))
	elif id == "leaf_cape":
		var leaf2 := AKit.m(LookColors.fixed(id, "leaves", Color("7fa35a")), true, 0.006)
		for k in 5:
			var x := lerpf(-w1 * 0.4, w1 * 0.4, float(k) / 4.0)
			AKit.part(seg, Kit.sphere(0.035, leaf2, 8, 10), Vector3(x, -seg_len - 0.01, -x * x * 1.2), Vector3(0, 0, 90), Vector3(1.6, 0.5, 0.9))
	elif id == "little_cape":
		# bat-wing points along the hem
		for k in 5:
			var x := lerpf(-w1 * 0.42, w1 * 0.42, float(k) / 4.0)
			var zc := -x * x / (2.0 * curve.z)
			AKit.part(seg, Kit.prism(Vector3(w1 * 0.19, 0.06, 0.012), outer), Vector3(x, -seg_len - 0.026, zc - 0.006), Vector3(0, rad_to_deg(x / curve.z), 180))
	elif id == "chorister_capelet":
		# a scalloped choir hem in the collar colour
		var hem := AKit.m(trim_c, false)
		for k in 4:
			var x := lerpf(-w1 * 0.36, w1 * 0.36, float(k) / 3.0)
			AKit.part(seg, Kit.sphere(0.032, hem, 8, 10), Vector3(x, -seg_len, -x * x * 1.2), Vector3.ZERO, Vector3(1.3, 0.6, 0.45))
	return AKit.chain("cape", [root, seg], rest, 45.0, 6.0)
