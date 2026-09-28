extends RefCounted
## Chapter Two lights, keepsakes and (optional, always friendly) Halloween decor: Wardlight, Miner's Lamp,
## Thread Veil (arachnophobia: Pale Veil Drape), carved pumpkin lantern with selectable faces, pumpkin string
## lights, bat bunting, ghost lantern, candy bowl and a harmless scarecrow. Glowing parts are returned by name
## ("flame", "light_pos") for lamp.gd. Local frame as in models_furniture.gd (front +Z, ground y = 0);
## `mount: wall` pieces hug the back (-Z) edge of their cell.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Batch := preload("res://src/building/batch.gd")

const PUMPKIN_FACES := ["friendly", "sleepy", "toothy", "cat", "moon", "ghost"]
## Festival carvings (data/structures.gd FESTIVAL_FACES, unlocked by the Lanternwake). The model carves any known
## id; WHICH faces a pumpkin may show is decided by src/building/pumpkin_faces.gd (the structure passes the
## resolved face in its model options).
const FESTIVAL_CARVINGS := ["starry", "lanternwake"]
const PUMPKIN_R := 0.26                # body radius (front surface)
const PUMPKIN_Y := 0.24                 # body centre height
static var BRASS: Color = Palette.K_SCARF.lerp(Palette.COPPER, 0.35).darkened(0.04)
static var PUMPKIN: Color = Color("f08a2e")
static var CARVE_GLOW: Color = Color("ffc060")


# --- Wardlight (1 x 1) -----------------------------------------------------------------------------------------

static func wardlight(root: Node3D) -> Dictionary:
	var mesh := U.baked("wardlight", func(b: Batch) -> void:
		b.blob(0.28, Vector3(0, 0.08, 0), Palette.STONE, 91, 0.18, 0.45)
		b.rbox(Vector3(0.3, 0.3, 0.3), Vector3(0, 0.3, 0), Palette.STONE.lightened(0.05), 0.05)
		b.cyl(0.08, 0.11, 1.5, Vector3(0, 1.2, 0), Palette.STONE, Vector3.ZERO, 12)
		for y in [0.6, 1.9]:
			b.torus(0.08, 0.14, Vector3(0, y, 0), BRASS, Vector3.ZERO, Vector3(1, 0.6, 1))
		# Leaf carvings (runes of the Ward) up the pillar.
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			b.sphere(0.5, Vector3(cos(a) * 0.1, 1.0 + 0.12 * float(k % 2), sin(a) * 0.1), Palette.MOSS, Vector3(0.05, 0.14, 0.03), Vector3(0, -rad_to_deg(a), 0))
		# Cage around the ward crystal.
		b.cyl(0.16, 0.12, 0.05, Vector3(0, 1.98, 0), BRASS, Vector3.ZERO, 12)
		for k in 6:
			var a2 := TAU * float(k) / 6.0
			b.rbox(Vector3(0.02, 0.34, 0.02), Vector3(cos(a2) * 0.13, 2.17, sin(a2) * 0.13), BRASS, 0.006)
		b.cyl(0.03, 0.17, 0.08, Vector3(0, 2.36, 0), BRASS, Vector3.ZERO, 12)
		b.sphere(0.04, Vector3(0, 2.42, 0), Palette.WARD_GLOW)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var crystal := U.baked("wardlight_crystal", func(b: Batch) -> void:
		b.cyl(0.0, 0.07, 0.12, Vector3(0, 0.06, 0), Palette.WARD_GLOW, Vector3.ZERO, 6)
		b.cyl(0.07, 0.0, 0.12, Vector3(0, -0.06, 0), Palette.WARD_GLOW, Vector3.ZERO, 6)
	)
	var pv := U.pivot(root, Vector3(0, 2.17, 0), "Crystal")
	var ci := U.instance(pv, crystal, Mat.glow(Palette.WARD_GLOW, 2.6))
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"flame": pv, "light_pos": Vector3(0, 2.17, 0)}


# --- Miner's lamp (1 x 1) --------------------------------------------------------------------------------------

static func miner_lamp(root: Node3D) -> Dictionary:
	var mesh := U.baked("miner_lamp", func(b: Batch) -> void:
		for k in 3:
			var a := TAU * float(k) / 3.0
			b.cyl(0.025, 0.03, 1.5, Vector3(cos(a) * 0.14, 0.73, sin(a) * 0.14), Palette.MINE_TIMBER, Vector3(sin(a) * -8.0, 0, cos(a) * 8.0), 8)
		b.sphere(0.06, Vector3(0, 1.48, 0), Palette.MINE_TIMBER.darkened(0.2))
		b.rbox(Vector3(0.36, 0.05, 0.05), Vector3(0.13, 1.45, 0), Palette.MINE_TIMBER.darkened(0.1), 0.015)
		b.torus(0.02, 0.035, Vector3(0.28, 1.4, 0), BRASS, Vector3(90, 0, 0))
		# The lamp: brass cap and base, a wire cage around the glass.
		b.cyl(0.03, 0.09, 0.08, Vector3(0.28, 1.32, 0), BRASS, Vector3.ZERO, 12)
		b.cyl(0.1, 0.1, 0.04, Vector3(0.28, 1.06, 0), BRASS, Vector3.ZERO, 12)
		for k in 4:
			var a2 := TAU * float(k) / 4.0 + 0.4
			b.rbox(Vector3(0.012, 0.2, 0.012), Vector3(0.28 + cos(a2) * 0.085, 1.18, sin(a2) * 0.085), Palette.STONE_DARK, 0.004)
		b.cyl(0.07, 0.07, 0.18, Vector3(0.28, 1.18, 0), Palette.WATER.lightened(0.3), Vector3.ZERO, 12)
		# Tobin's old pick leaning on the stand, and a lunch tin.
		b.cyl(0.018, 0.018, 0.9, Vector3(-0.22, 0.43, 0.18), Palette.WOOD_DARK, Vector3(15, 0, -20), 6)
		b.rbox(Vector3(0.36, 0.06, 0.06), Vector3(-0.07, 0.85, 0.3), Palette.STONE_DARK, 0.015, Vector3(15, 0, -20))
		b.rbox(Vector3(0.2, 0.1, 0.13), Vector3(0.18, 0.05, 0.22), Palette.TEAL.darkened(0.2), 0.02)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var flame := MeshInstance3D.new()
	flame.mesh = Shapes.prim_sphere(0.045)
	flame.material_override = Mat.glow(Palette.MINE_LIGHT, 3.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	flame.position = Vector3(0.28, 1.17, 0)
	return {"flame": flame, "light_pos": Vector3(0.28, 1.15, 0)}


# --- Thread Veil / Pale Veil Drape (1 x 1, wall) ------------------------------------------------------------------

## `alt` (arachnophobia): a sheer pale cloth drape with a ribbon; no strands, no woven rosette.
static func thread_veil(root: Node3D, alt: bool) -> Dictionary:
	var key := "thread_veil_alt" if alt else "thread_veil"
	var mesh := U.baked(key, func(b: Batch) -> void:
		var z := -0.42
		b.cyl(0.03, 0.025, 1.0, Vector3(0, 2.3, z), Palette.BARK, Vector3(0, 0, 88), 8)
		for sx in [-1.0, 1.0]:
			b.sphere(0.035, Vector3(0.5 * sx, 2.31, z), Palette.MOSS)
		if alt:
			var cloth := Palette.CLOTH_CREAM.lightened(0.35)
			for f in 7:
				var x := -0.39 + 0.13 * float(f)
				var h := 1.9 - 0.08 * float(absi(f - 3))
				b.cyl(0.055, 0.075, h, Vector3(x, 2.28 - h * 0.5, z + 0.03 * float(f % 2)), cloth.darkened(0.04 * float(f % 3)), Vector3.ZERO, 10)
			b.torus(0.05, 0.08, Vector3(0, 1.35, z + 0.08), Palette.FLOWER_PURPLE.lightened(0.2), Vector3(90, 0, 0), Vector3(2.2, 1, 0.6))
			b.heart(0.1, Vector3(0, 1.35, z + 0.13), Palette.FLOWER_PURPLE.lightened(0.2), 0.02)
		else:
			# Silver strands with dewdrop beads, falling in a soft fan, and a small woven moon ring.
			for k in 9:
				var x2 := -0.4 + 0.1 * float(k)
				var h2 := 1.5 + 0.35 * sin(float(k) * 0.9)
				b.cyl(0.004, 0.004, h2, Vector3(x2, 2.28 - h2 * 0.5, z + 0.02), Palette.SILK_WEB, Vector3.ZERO, 4)
				for d in 3:
					b.sphere(0.018, Vector3(x2, 2.1 - h2 * (0.25 + 0.3 * float(d)), z + 0.02), Palette.WATER.lightened(0.4))
			b.torus(0.17, 0.2, Vector3(0, 1.55, z + 0.04), Palette.SILK_WEB, Vector3(90, 0, 0))
			for k in 4:
				var a := PI * float(k) / 4.0
				b.rbox(Vector3(0.34, 0.006, 0.006), Vector3(0, 1.55, z + 0.04), Palette.SILK_WEB, 0.0, Vector3(0, 0, rad_to_deg(a)))
			b.sphere(0.03, Vector3(0, 1.55, z + 0.05), Palette.RUIN_LIGHT)
	)
	U.instance(root, mesh, U.vc_outlined(0.008, {"emission": Palette.SILK_WEB, "emission_energy": 0.12}))
	return {}


# --- Carved pumpkin lantern (1 x 1) ------------------------------------------------------------------------------

## Pumpkin body + the carved `face` glowing warmly (unknown / "" = the first face). Parts: "flame" (a candle
## glow inside, hidden by the body), "light_pos", "face" (the carving node).
static func pumpkin_lantern(root: Node3D, face: String = "") -> Dictionary:
	var fid := face if (PUMPKIN_FACES.has(face) or FESTIVAL_CARVINGS.has(face)) else String(PUMPKIN_FACES[0])
	var body := U.baked("pumpkin_lantern", func(b: Batch) -> void:
		b.cyl(0.2, 0.22, 0.03, Vector3(0, 0.015, 0), Palette.WOOD_DARK, Vector3.ZERO, 14)
		for k in 8:
			var a := TAU * float(k) / 8.0
			var col: Color = PUMPKIN if k % 2 == 0 else PUMPKIN.darkened(0.08)
			b.sphere(0.16, Vector3(cos(a) * 0.1, PUMPKIN_Y, sin(a) * 0.1), col, Vector3(1.0, 1.35, 1.0) * 1.0, Vector3(0, -rad_to_deg(a), 0))
		b.sphere(PUMPKIN_R - 0.02, Vector3(0, PUMPKIN_Y, 0), PUMPKIN.darkened(0.04), Vector3(1.0, 0.82, 1.0))
		b.cyl(0.025, 0.035, 0.12, Vector3(0.01, PUMPKIN_Y + 0.23, 0), Palette.FOLIAGE_DARK, Vector3(0, 0, -12), 7)
		b.sphere(0.5, Vector3(-0.08, PUMPKIN_Y + 0.21, 0.04), Palette.FOLIAGE, Vector3(0.12, 0.02, 0.07), Vector3(0, 30, -15))
		b.torus(0.02, 0.032, Vector3(0.08, PUMPKIN_Y + 0.22, -0.02), Palette.FOLIAGE_DARK, Vector3(90, 30, 0))
	)
	U.instance(root, body, U.vc_outlined(0.011))
	var carving := U.baked("pumpkin_face|" + fid, func(b: Batch) -> void:
		_carve(b, fid)
	)
	var fnode := U.instance(root, carving, Mat.glow(CARVE_GLOW, 2.2))
	fnode.name = "Face"
	fnode.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var candle := MeshInstance3D.new()
	candle.mesh = Shapes.prim_sphere(0.05)
	candle.material_override = Mat.glow(Palette.LANTERN_GLOW, 2.5)
	candle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(candle)
	candle.position = Vector3(0, PUMPKIN_Y, 0)
	return {"flame": candle, "light_pos": Vector3(0, PUMPKIN_Y + 0.05, 0.3), "face": fnode}


## Point on the pumpkin's front surface for face coordinates (x, y relative to the body centre).
static func _on_face(x: float, y: float) -> Vector3:
	var r := PUMPKIN_R + 0.012
	var zz := sqrt(maxf(r * r - x * x - y * y * 1.35, 0.01))
	return Vector3(x, PUMPKIN_Y + y, zz)


## A flat carved blob placed on the surface, turned to face outward.
static func _cut(b: Batch, x: float, y: float, size: Vector2, roll_deg: float = 0.0) -> void:
	var p := _on_face(x, y)
	var yaw := rad_to_deg(asin(clampf(x / PUMPKIN_R, -0.9, 0.9)))
	var pitch := -rad_to_deg(asin(clampf(y / PUMPKIN_R, -0.9, 0.9)))
	b.sphere(0.5, p, CARVE_GLOW, Vector3(size.x, size.y, 0.03), Vector3(pitch, yaw, roll_deg))


## A carved stroke from a to b (face coords), `w` wide.
static func _stroke(b: Batch, a: Vector2, c: Vector2, w: float) -> void:
	var mid := (a + c) * 0.5
	var d := c - a
	_cut(b, mid.x, mid.y, Vector2(d.length() + w, w), rad_to_deg(atan2(d.y, d.x)))


static func _carve(b: Batch, face: String) -> void:
	match face:
		"sleepy":
			for sx in [-1.0, 1.0]:
				_stroke(b, Vector2(0.06 * sx, 0.06), Vector2(0.09 * sx, 0.045), 0.022)
				_stroke(b, Vector2(0.09 * sx, 0.045), Vector2(0.125 * sx, 0.06), 0.022)
			_cut(b, 0.0, -0.075, Vector2(0.05, 0.05))
			_cut(b, 0.14, 0.12, Vector2(0.03, 0.03))
			_cut(b, 0.17, 0.155, Vector2(0.02, 0.02))
		"toothy":
			for sx in [-1.0, 1.0]:
				_cut(b, 0.09 * sx, 0.055, Vector2(0.075, 0.06))
			var pts := [Vector2(-0.14, -0.04), Vector2(-0.09, -0.1), Vector2(-0.045, -0.06), Vector2(0.0, -0.11), Vector2(0.045, -0.06), Vector2(0.09, -0.1), Vector2(0.14, -0.04)]
			for i in pts.size() - 1:
				_stroke(b, pts[i], pts[i + 1], 0.035)
		"cat":
			for sx in [-1.0, 1.0]:
				_cut(b, 0.085 * sx, 0.06, Vector2(0.08, 0.04), -20.0 * sx)
				for k in 2:
					_stroke(b, Vector2(0.07 * sx, -0.03 - 0.03 * float(k)), Vector2(0.16 * sx, -0.02 - 0.05 * float(k)), 0.012)
			_cut(b, 0.0, 0.0, Vector2(0.035, 0.028))
			_stroke(b, Vector2(-0.05, -0.05), Vector2(0.0, -0.075), 0.018)
			_stroke(b, Vector2(0.0, -0.075), Vector2(0.05, -0.05), 0.018)
		"moon":
			for k in 7:
				var a := lerpf(-1.1, 1.1, float(k) / 6.0)
				_cut(b, -0.02 + cos(a) * 0.09 - 0.03, sin(a) * 0.1, Vector2(0.045 - 0.012 * absf(a), 0.045 - 0.012 * absf(a)))
			for s in [Vector2(0.09, 0.08), Vector2(0.12, -0.04), Vector2(0.05, -0.1)]:
				_cut(b, s.x, s.y, Vector2(0.03, 0.03), 45.0)
				_cut(b, s.x, s.y, Vector2(0.045, 0.012), 0.0)
		"ghost":
			_cut(b, 0.0, 0.03, Vector2(0.16, 0.14))
			_cut(b, 0.0, -0.03, Vector2(0.16, 0.12))
			for k in 3:
				_cut(b, -0.055 + 0.055 * float(k), -0.1, Vector2(0.06, 0.05))
			for sx in [-1.0, 1.0]:
				_cut(b, 0.1 * sx, -0.01, Vector2(0.06, 0.03), 25.0 * sx)
		"starry":
			# Festival face: twinkling star eyes (three short crossed strokes each), a soft smile, a sparkle on each cheek.
			for sx in [-1.0, 1.0]:
				var e := Vector2(0.09 * sx, 0.065)
				for k in 3:
					var a := PI * float(k) / 3.0 + PI * 0.5
					var d := Vector2(cos(a), sin(a)) * 0.03
					_stroke(b, e - d, e + d, 0.016)
				_cut(b, 0.155 * sx, -0.015, Vector2(0.022, 0.022), 45.0)
			for k in 5:
				var t := lerpf(-1.0, 1.0, float(k) / 4.0)
				_cut(b, t * 0.075, -0.07 - 0.028 * (1.0 - t * t), Vector2(0.042, 0.03))
		"lanternwake":
			# Festival face: little flame-shaped eyes and a smile of round festival lanterns.
			for sx in [-1.0, 1.0]:
				_cut(b, 0.085 * sx, 0.05, Vector2(0.05, 0.055))
				_cut(b, 0.085 * sx + 0.006 * sx, 0.092, Vector2(0.024, 0.04), -12.0 * sx)
			for k in 5:
				var t := lerpf(-1.0, 1.0, float(k) / 4.0)
				_cut(b, t * 0.12, -0.05 - 0.05 * (1.0 - t * t), Vector2(0.038, 0.042))
		_:     # friendly
			for sx in [-1.0, 1.0]:
				_cut(b, 0.09 * sx, 0.06, Vector2(0.06, 0.07))
			for k in 7:
				var t := lerpf(-1.0, 1.0, float(k) / 6.0)
				_cut(b, t * 0.12, -0.06 - 0.04 * (1.0 - t * t), Vector2(0.05, 0.035))


# --- Pumpkin string lights (1 x 1, wall) ---------------------------------------------------------------------------

static func pumpkin_lights(root: Node3D) -> Dictionary:
	var z := -0.44
	var mesh := U.baked("pumpkin_lights", func(b: Batch) -> void:
		var prev := Vector3(-0.48, 2.32, z)
		for sx in [-1.0, 1.0]:
			b.cyl(0.012, 0.012, 0.06, Vector3(0.48 * sx, 2.32, z - 0.02), BRASS, Vector3(90, 0, 0), 6)
		for k in 9:
			var t := float(k + 1) / 9.0
			var x := lerpf(-0.48, 0.48, t)
			var p := Vector3(x, 2.32 - 0.18 * sin(t * PI), z)
			var d := p - prev
			b.rbox(Vector3(d.length() + 0.01, 0.01, 0.01), (p + prev) * 0.5, Palette.FOLIAGE_DARK, 0.0, Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))))
			prev = p
	)
	U.instance(root, mesh, U.vc_outlined(0.008))
	var bulbs := U.baked("pumpkin_lights_bulbs", func(b: Batch) -> void:
		for k in 5:
			var t := (float(k) + 0.5) / 5.0
			var x := lerpf(-0.48, 0.48, t)
			var y := 2.32 - 0.18 * sin(t * PI) - 0.07
			for r in 5:
				var a := TAU * float(r) / 5.0
				b.sphere(0.035, Vector3(x + cos(a) * 0.022, y, z + 0.04 + sin(a) * 0.022), PUMPKIN, Vector3(0.9, 1.1, 0.9))
			b.cyl(0.006, 0.008, 0.03, Vector3(x, y + 0.05, z + 0.04), Palette.FOLIAGE_DARK, Vector3.ZERO, 5)
	)
	var bi := U.instance(root, bulbs, Mat.glow(Color("ffb862"), 1.8))
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"light_pos": Vector3(0, 2.15, z + 0.2)}


# --- Bat bunting (1 x 1, wall) ---------------------------------------------------------------------------------------

## A garland of pennants and four little round bats (cream eyes, rosy cheeks): cute, never scary.
static func bat_bunting(root: Node3D) -> Dictionary:
	var mesh := U.baked("bat_bunting", func(b: Batch) -> void:
		var z := -0.44
		var bat := Palette.K_PANTS.darkened(0.2)
		var pts: Array = []
		for k in 11:
			var t := float(k) / 10.0
			pts.append(Vector3(lerpf(-0.48, 0.48, t), 2.5 - 0.16 * sin(t * PI), z))
		for k in 10:
			var a: Vector3 = pts[k]
			var c: Vector3 = pts[k + 1]
			var d := c - a
			b.rbox(Vector3(d.length() + 0.01, 0.012, 0.012), (a + c) * 0.5, Palette.CLOTH_CREAM, 0.0, Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))))
		for k in 9:
			var p: Vector3 = pts[k + 1]
			if k % 2 == 0:
				# a bat: round body, two scalloped wings, ears, eyes
				var y := p.y - 0.09
				b.sphere(0.055, Vector3(p.x, y, z + 0.02), bat)
				for sx in [-1.0, 1.0]:
					b.sphere(0.5, Vector3(p.x + 0.07 * sx, y + 0.01, z + 0.015), bat, Vector3(0.1, 0.06, 0.012), Vector3(0, 0, -20.0 * sx))
					b.sphere(0.02, Vector3(p.x + 0.11 * sx, y - 0.025, z + 0.015), bat)
					b.prism(Vector3(0.025, 0.035, 0.012), Vector3(p.x + 0.025 * sx, y + 0.06, z + 0.02), bat)
					b.sphere(0.012, Vector3(p.x + 0.02 * sx, y + 0.012, z + 0.07), Palette.CLOTH_CREAM)
					b.sphere(0.01, Vector3(p.x + 0.032 * sx, y - 0.012, z + 0.068), Palette.BLOSSOM)
			else:
				b.prism(Vector3(0.1, 0.13, 0.01), Vector3(p.x, p.y - 0.075, z + 0.01), [Palette.FOLIAGE_AUTUMN, Palette.CLOTH_CREAM, Palette.K_SCARF, Palette.BLOSSOM][(k / 2) % 4], Vector3(0, 0, 180))
	)
	U.instance(root, mesh, U.vc_outlined(0.008))
	return {}


# --- Ghost lantern (1 x 1) ----------------------------------------------------------------------------------------------

## A friendly little sheet ghost lantern on a crook post. Glows softly; purely decorative.
static func ghost_lantern(root: Node3D) -> Dictionary:
	var post := U.baked("ghost_lantern_post", func(b: Batch) -> void:
		b.blob(0.2, Vector3(0, 0.06, 0), Palette.STONE, 81, 0.2, 0.5)
		b.cyl(0.035, 0.045, 1.66, Vector3(0, 0.83, 0), Palette.WOOD_DARK, Vector3.ZERO, 8)
		b.torus(0.12, 0.16, Vector3(0.14, 1.66, 0), Palette.WOOD_DARK, Vector3(90, 0, 0))
		b.cyl(0.006, 0.006, 0.14, Vector3(0.28, 1.58, 0), Palette.STONE_DARK, Vector3.ZERO, 4)
	)
	U.instance(root, post, U.vc_outlined(0.012))
	var ghost := U.baked("ghost_lantern_ghost", func(b: Batch) -> void:
		var white := Color("eef2ff")
		b.sphere(0.14, Vector3(0, 0.0, 0), white, Vector3(1.0, 1.05, 1.0))
		b.cyl(0.14, 0.19, 0.2, Vector3(0, -0.1, 0), white, Vector3.ZERO, 16)
		for k in 6:
			var a := TAU * float(k) / 6.0
			b.sphere(0.05, Vector3(cos(a) * 0.16, -0.2, sin(a) * 0.16), white)
		for sx in [-1.0, 1.0]:
			b.sphere(0.045, Vector3(0.15 * sx, -0.04, 0.03), white, Vector3(1.2, 0.8, 0.8))
			b.sphere(0.022, Vector3(0.05 * sx, 0.02, 0.13), Palette.UI_INK, Vector3(1, 1.3, 0.6))
			b.sphere(0.02, Vector3(0.085 * sx, -0.03, 0.12), Palette.BLOSSOM, Vector3(1.3, 0.8, 0.5))
		b.sphere(0.018, Vector3(0, -0.035, 0.135), Palette.UI_INK, Vector3(1.2, 0.7, 0.6))
	)
	var gp := U.pivot(root, Vector3(0.28, 1.28, 0), "Ghost")
	var gm := U.instance(gp, ghost, Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "emission": Color("bcd6ff"), "emission_energy": 0.45, "rim": 0.5}), 0.01))
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"light_pos": Vector3(0.28, 1.25, 0.1)}


# --- Candy bowl (1 x 1) ---------------------------------------------------------------------------------------------------

static func candy_bowl(root: Node3D) -> Dictionary:
	var mesh := U.baked("candy_bowl", func(b: Batch) -> void:
		b.cyl(0.14, 0.18, 0.05, Vector3(0, 0.025, 0), Palette.WOOD_DARK, Vector3.ZERO, 14)
		b.cyl(0.05, 0.06, 0.24, Vector3(0, 0.17, 0), Palette.WOOD, Vector3.ZERO, 10)
		b.cyl(0.26, 0.12, 0.13, Vector3(0, 0.345, 0), PUMPKIN, Vector3.ZERO, 18)
		b.torus(0.24, 0.29, Vector3(0, 0.41, 0), PUMPKIN.darkened(0.1), Vector3.ZERO, Vector3(1, 0.6, 1))
		for sx in [-1.0, 1.0]:
			b.sphere(0.025, Vector3(0.08 * sx, 0.36, 0.2), Palette.UI_INK)
		b.sphere(0.5, Vector3(0, 0.32, 0.215), Palette.UI_INK, Vector3(0.1, 0.03, 0.02))
		var cols := [Palette.CLOTH_RED, Palette.TEAL, Palette.K_SCARF, Palette.BLOSSOM, Palette.FLOWER_PURPLE, Palette.FOLIAGE_LIGHT]
		for k in 10:
			var a := TAU * float(k) / 10.0 + 0.2
			var r := 0.13 if k % 2 == 0 else 0.06
			var p := Vector3(cos(a) * r, 0.43 + 0.02 * float(k % 3), sin(a) * r)
			var col: Color = cols[k % cols.size()]
			b.sphere(0.035, p, col, Vector3(1.3, 0.9, 0.9), Vector3(0, rad_to_deg(a), 0))
			for sx in [-1.0, 1.0]:
				b.prism(Vector3(0.03, 0.035, 0.02), p + Vector3(cos(a) * 0.05 * sx, 0, sin(a) * 0.05 * sx), col.lightened(0.2), Vector3(0, -rad_to_deg(a), 90.0 * sx))
		b.cyl(0.006, 0.006, 0.14, Vector3(0.05, 0.5, -0.05), Palette.CLOTH_CREAM, Vector3(10, 0, 10), 5)
		b.cyl(0.04, 0.04, 0.015, Vector3(0.062, 0.575, -0.05), Palette.BLOSSOM, Vector3(90, 0, 10), 12)
	)
	U.instance(root, mesh, U.vc_outlined(0.01))
	return {}


# --- Scarecrow (1 x 1) ----------------------------------------------------------------------------------------------------

## A smiling, patched scarecrow with a straw hat and a little bird friend. Decoration only: it never moves.
static func scarecrow(root: Node3D) -> Dictionary:
	var mesh := U.baked("scarecrow", func(b: Batch) -> void:
		var burlap := Color("d8c08a")
		b.blob(0.18, Vector3(0, 0.04, 0), Palette.STONE, 101, 0.2, 0.5)
		b.cyl(0.05, 0.06, 1.72, Vector3(0, 0.86, 0), Palette.WOOD_DARK, Vector3.ZERO, 8)
		b.rbox(Vector3(0.92, 0.07, 0.07), Vector3(0, 1.42, 0), Palette.WOOD_DARK, 0.02)
		# Shirt with patches and sleeves, straw at the cuffs and the hem.
		b.rbox(Vector3(0.4, 0.5, 0.22), Vector3(0, 1.3, 0), Palette.CLOTH_RED.darkened(0.1), 0.06)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.3, 0.14, 0.16), Vector3(0.28 * sx, 1.42, 0), Palette.CLOTH_RED.darkened(0.1), 0.05)
			for k in 3:
				b.cyl(0.0, 0.025, 0.12, Vector3(0.45 * sx, 1.42 + 0.03 * float(k - 1), 0.02 * float(k - 1)), Palette.THATCH, Vector3(0, 0, 90.0 * sx + 12.0 * float(k - 1)), 5)
		b.rbox(Vector3(0.12, 0.12, 0.01), Vector3(0.08, 1.22, 0.115), Palette.TEAL, 0.01)
		b.rbox(Vector3(0.1, 0.09, 0.01), Vector3(-0.1, 1.4, 0.115), Palette.K_SCARF, 0.01)
		for k in 5:
			b.cyl(0.0, 0.03, 0.14, Vector3(-0.14 + 0.07 * float(k), 1.02, 0.0), Palette.THATCH, Vector3(180, 0, 8.0 * float(k - 2)), 5)
		# Burlap head with button eyes, a stitched smile and rosy cheeks; straw hat.
		b.sphere(0.17, Vector3(0, 1.74, 0), burlap, Vector3(1, 1.05, 0.95))
		for sx in [-1.0, 1.0]:
			b.sphere(0.028, Vector3(0.06 * sx, 1.78, 0.155), Palette.UI_INK, Vector3(1, 1, 0.5))
			b.sphere(0.025, Vector3(0.1 * sx, 1.71, 0.14), Palette.BLOSSOM, Vector3(1.2, 0.8, 0.4))
		for k in 5:
			var t := lerpf(-1.0, 1.0, float(k) / 4.0)
			b.rbox(Vector3(0.03, 0.008, 0.01), Vector3(t * 0.06, 1.68 - 0.02 * (1.0 - t * t), 0.16), Palette.UI_INK, 0.0, Vector3(0, 0, 60.0 if k % 2 == 0 else -60.0))
		b.cyl(0.25, 0.25, 0.025, Vector3(0, 1.88, 0), Palette.THATCH, Vector3.ZERO, 18)
		b.cyl(0.07, 0.13, 0.2, Vector3(0, 1.99, 0), Palette.THATCH.darkened(0.06), Vector3.ZERO, 12)
		b.cyl(0.132, 0.132, 0.04, Vector3(0, 1.915, 0), Palette.CLOTH_RED, Vector3.ZERO, 12)
		b.sphere(0.04, Vector3(0.12, 1.93, 0.07), Palette.FLOWER_YELLOW)
		# A little bluebird friend on the arm.
		b.sphere(0.045, Vector3(-0.36, 1.49, 0), Palette.FLOWER_BLUE, Vector3(1.2, 0.9, 0.9))
		b.sphere(0.03, Vector3(-0.32, 1.53, 0), Palette.FLOWER_BLUE)
		b.prism(Vector3(0.02, 0.02, 0.02), Vector3(-0.295, 1.53, 0), Palette.K_SCARF, Vector3(0, 0, -90))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}
