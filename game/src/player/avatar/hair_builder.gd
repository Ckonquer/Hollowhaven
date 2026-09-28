extends RefCounted
## Krystal's eight hairstyles (data/appearance.gd HAIRSTYLES) and her brows. Every style shares the
## Chapter One skull cap so the head proportions never change; the silhouettes differ in the back volume,
## fringe, side locks and the spring chains (braids, ponytail, hair curtains, ribbon tails):
##   side_braid      the Chapter One hair, exactly (swept fringe, side puffs, nape locks, one braid behind the right shoulder)
##   bob             rounded chin-length bob with a blunt fringe and curled-under ends (no springs)
##   long_waves      parted fringe, long face-framing locks, a wavy three-segment curtain down the back
##   high_ponytail   sleek sides, a fountain ponytail from the crown (springy); low ponytail under a hat
##   twin_braids     parted fringe, a braid behind each shoulder
##   space_buns      two buns on top (lowered to the sides under a hat)
##   braided_crown   a braid ring around the head and a little nape bun
##   half_up_ribbon  half-up knot with a ribbon bow (tails sway) over a straight curtain
## A hat or helm that covers the crown (`hides_hair`) drops the springy top curl and moves top-mounted hair.
## build(ctx) -> {"chains": [...], "hull": "" | "direct", "hull_nodes": [[Node3D, radius], ...]}

const AKit := preload("res://src/player/avatar/avatar_kit.gd")
const Kit := preload("res://src/art/mesh_kit.gd")


static func build(ctx: Dictionary) -> Dictionary:
	var box: Callable = ctx["box"]
	var col: Dictionary = ctx["col"]
	var style := String(ctx["look"].get("hair", "side_braid"))
	var hides := bool(ctx.get("hides_hair", false))
	var hc: Node3D = box.call("head_c")
	var hair := AKit.m(col["hair"], true, 0.012)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var brow: Node3D = box.call("brow%d" % side)
		AKit.part(brow, Kit.capsule(0.0105, 0.068, AKit.flat(col["hair_dark"])), Vector3.ZERO, Vector3(0, 0, 90 - 8 * s), Vector3.ONE, false)
	var res := {"chains": [], "hull": "direct", "hull_nodes": []}
	match style:
		"bob":
			_bob(hc, hair)
		"long_waves":
			_long_waves(hc, hair, res)
		"high_ponytail":
			_high_ponytail(hc, hair, col, hides, res)
		"twin_braids":
			_cap(hc, hair)
			_fringe_parted(hc, hair)
			_side_locks(hc, hair, true)
			_nape(hc, hair)
			res["chains"].append(_braid(hc, "BraidR", Vector3(-0.17, -0.1, -0.13), Vector3(0.35, 0.0, -0.18), hair, col["secondary"], 38.0, true))
			res["chains"].append(_braid(hc, "BraidL", Vector3(0.17, -0.1, -0.13), Vector3(0.35, 0.0, 0.18), hair, col["secondary"], 36.0, true))
		"space_buns":
			_space_buns(hc, hair, col, hides)
		"braided_crown":
			_braided_crown(hc, hair, col)
		"half_up_ribbon":
			_half_up(hc, hair, col, res)
		_:
			# side_braid: the Chapter One hair, part for part
			res["hull"] = ""
			_cap(hc, hair)
			_fringe_swept(hc, hair)
			_side_locks(hc, hair, true)
			_nape(hc, hair)
			res["chains"].append(_braid(hc, "Braid", Vector3(-0.17, -0.1, -0.13), Vector3(0.35, 0.0, -0.18), hair, col["secondary"], 38.0))
	if not hides:
		_curl(hc, col["hair"])
	return res


# --- shared pieces (the Chapter One head) --------------------------------------------------------------------

static func _cap(hc: Node3D, hair: Material, back: bool = true) -> void:
	AKit.part(hc, Kit.sphere(0.268, hair, 20, 28), Vector3(0, 0.052, -0.057), Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
	if back:
		AKit.part(hc, Kit.sphere(0.21, hair, 16, 22), Vector3(0, -0.085, -0.12), Vector3.ZERO, Vector3(1.12, 1.0, 0.92))


static func _fringe_swept(hc: Node3D, hair: Material) -> void:
	var fringe := [
		[Vector3(-0.125, 0.1, 0.188), Vector3(-12, -32, -18), Vector3(0.62, 1.35, 0.5), 0.07],
		[Vector3(-0.055, 0.118, 0.212), Vector3(-14, -12, -30), Vector3(0.7, 1.4, 0.48), 0.072],
		[Vector3(0.02, 0.13, 0.22), Vector3(-14, 6, -42), Vector3(0.72, 1.45, 0.46), 0.072],
		[Vector3(0.1, 0.13, 0.2), Vector3(-12, 28, -52), Vector3(0.7, 1.35, 0.48), 0.068],
		[Vector3(0.17, 0.09, 0.15), Vector3(-6, 48, -24), Vector3(0.62, 1.3, 0.55), 0.066],
	]
	for f in fringe:
		AKit.part(hc, Kit.sphere(float(f[3]), hair, 12, 16), f[0], f[1], f[2])


## Centre parting: two locks sweep outward on each side of the forehead.
static func _fringe_parted(hc: Node3D, hair: Material) -> void:
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(hc, Kit.sphere(0.07, hair, 12, 16), Vector3(0.05 * s, 0.135, 0.215), Vector3(-14, 10 * s, 38 * s), Vector3(0.7, 1.4, 0.46))
		AKit.part(hc, Kit.sphere(0.068, hair, 12, 16), Vector3(0.125 * s, 0.105, 0.19), Vector3(-12, 30 * s, 30 * s), Vector3(0.66, 1.35, 0.5))
		AKit.part(hc, Kit.sphere(0.064, hair, 12, 16), Vector3(0.18 * s, 0.07, 0.14), Vector3(-6, 50 * s, 16 * s), Vector3(0.6, 1.3, 0.55))


static func _side_locks(hc: Node3D, hair: Material, puffs: bool, length: float = 0.25) -> void:
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(hc, Kit.capsule(0.056, length, hair), Vector3(0.212 * s, -0.08 - (length - 0.25) * 0.5, 0.075), Vector3(10, 0, 7 * s), Vector3(0.72, 1.0, 0.95))
		if puffs:
			AKit.part(hc, Kit.sphere(0.1, hair, 12, 16), Vector3(0.19 * s, -0.04, -0.03), Vector3.ZERO, Vector3(0.62, 1.15, 1.1))


## Soft layered locks along the nape so the back of the head (the usual camera view) has shape.
static func _nape(hc: Node3D, hair: Material) -> void:
	for i in 5:
		var x := -0.13 + 0.065 * float(i)
		AKit.part(hc, Kit.sphere(0.056, hair, 10, 14), Vector3(x, -0.255 + absf(x) * 0.3, -0.212 + absf(x) * 0.22), Vector3(-22, x * 110.0, x * 80.0), Vector3(0.95, 1.55, 0.72))


## A single springy strand on top of the head.
static func _curl(hc: Node3D, c: Color) -> void:
	var curl := MeshInstance3D.new()
	curl.mesh = AKit.arc_mesh(0.045, 0.011, 3.6)
	curl.material_override = AKit.m(c, true, 0.006)
	AKit.part(hc, curl, Vector3(0.025, 0.338, -0.03), Vector3(0, 60, 90), Vector3(1, 1.15, 1))


## Braid of six alternating lobes with a tie (palette secondary) and a tuft; returns its spring chain.
## `pair` groups two lobes per animated segment (twin braids: half the segments, the same braid).
static func _braid(hc: Node3D, nm: String, pos: Vector3, rot: Vector3, hair: Material, tie_col: Color, k: float, pair: bool = false) -> Dictionary:
	var segs: Array = []
	var rest: Array = []
	var parent: Node3D = AKit.node(hc, pos, nm)
	parent.rotation = rot
	var radii := [0.058, 0.054, 0.05, 0.046, 0.042, 0.038]
	var step := 2 if pair else 1
	for i in range(0, radii.size(), step):
		var seg := AKit.node(parent, Vector3(0, -0.065 * step if i > 0 else 0.0, 0), "B%d" % segs.size())
		for j in step:
			var li := i + j
			var r: float = radii[li]
			var off := 0.012 if li % 2 == 0 else -0.012
			AKit.part(seg, Kit.sphere(r, hair, 10, 14), Vector3(off, -0.03 - 0.065 * j, 0), Vector3(0, 0, 25.0 if li % 2 == 0 else -25.0), Vector3(0.9, 1.15, 0.9))
		segs.append(seg)
		rest.append(Vector3.ZERO)
		parent = seg
	var tie := AKit.node(parent, Vector3(0, -0.075 - 0.065 * float(step - 1), 0), "Tie")
	AKit.part(tie, Kit.torus(0.018, 0.034, AKit.m(tie_col, true, 0.006)), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.6, 1))
	AKit.part(tie, Kit.sphere(0.042, hair, 10, 14), Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1.0, 1.3, 0.85))
	AKit.part(tie, Kit.sphere(0.03, hair, 8, 12), Vector3(0.012, -0.095, 0), Vector3(0, 0, 20), Vector3(0.8, 1.3, 0.75))
	return AKit.chain("braid", segs, rest, k, 5.0)


## A hair curtain down the back: `count` segments of three wavy lobes.
static func _curtain(hc: Node3D, hair: Material, count: int, wave: float, k: float) -> Dictionary:
	var root := AKit.node(hc, Vector3(0, -0.1, -0.2), "Curtain")
	root.rotation = Vector3(0.3, 0, 0)
	var segs: Array = []
	var rest: Array = []
	var parent: Node3D = root
	for i in count:
		var seg := AKit.node(parent, Vector3(0, -0.12 if i > 0 else 0.0, 0), "W%d" % i)
		var taper := 1.0 - 0.1 * float(i)
		for j in 3:
			var x := (float(j) - 1.0) * 0.105 * taper
			var zig := wave * (1.0 if (i + j) % 2 == 0 else -1.0)
			AKit.part(seg, Kit.sphere(0.08 * taper, hair, 10, 14), Vector3(x + zig, -0.06, 0.012 * absf(float(j) - 1.0)),
				Vector3(0, 0, zig * 300.0), Vector3(1.05, 1.45, 0.55))
		segs.append(seg)
		rest.append(Vector3(0.0 if i == 0 else 0.08, 0, 0))
		parent = seg
	var tip := AKit.node(parent, Vector3(0, -0.13, 0), "WTip")
	for j in 2:
		AKit.part(tip, Kit.sphere(0.05, hair, 8, 12), Vector3((float(j) - 0.5) * 0.1, 0.0, 0.0), Vector3(0, 0, (float(j) - 0.5) * -40.0), Vector3(1.0, 1.4, 0.6))
	return AKit.chain("braid", segs, rest, k, 5.0, 0.8)


# --- styles --------------------------------------------------------------------------------------------------

static func _bob(hc: Node3D, hair: Material) -> void:
	_cap(hc, hair, false)
	# rounded mushroom volume down to the jaw, blunt and wide
	AKit.part(hc, Kit.sphere(0.235, hair, 18, 24), Vector3(0, -0.075, -0.1), Vector3.ZERO, Vector3(1.18, 0.92, 1.0))
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(hc, Kit.capsule(0.072, 0.27, hair), Vector3(0.212 * s, -0.085, 0.07), Vector3(6, 0, 5 * s), Vector3(0.78, 1.0, 1.05))
		AKit.part(hc, Kit.sphere(0.078, hair, 10, 14), Vector3(0.2 * s, -0.2, 0.06), Vector3.ZERO, Vector3(0.95, 0.62, 1.25))
	# blunt straight fringe across the forehead
	for i in 7:
		var x := -0.15 + 0.05 * float(i)
		AKit.part(hc, Kit.sphere(0.07, hair, 10, 14), Vector3(x, 0.14, 0.205 - absf(x) * 0.28), Vector3(-12, x * 120.0, 0), Vector3(0.78, 1.1, 0.5))
	# curled-under ends around the back
	for i in 7:
		var a := lerpf(-1.1, 1.1, float(i) / 6.0)
		AKit.part(hc, Kit.sphere(0.07, hair, 10, 14), Vector3(sin(a) * 0.2, -0.25, -cos(a) * 0.19 - 0.03), Vector3(0, rad_to_deg(a), 0), Vector3(1.0, 0.8, 0.9))


static func _long_waves(hc: Node3D, hair: Material, res: Dictionary) -> void:
	_cap(hc, hair)
	_fringe_parted(hc, hair)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		# face-framing waves resting in front of the shoulders
		AKit.part(hc, Kit.sphere(0.066, hair, 10, 14), Vector3(0.212 * s, -0.1, 0.085), Vector3(8, 0, 10 * s), Vector3(0.72, 1.4, 0.95))
		AKit.part(hc, Kit.sphere(0.06, hair, 10, 14), Vector3(0.232 * s, -0.215, 0.11), Vector3(8, 0, -12 * s), Vector3(0.75, 1.35, 0.9))
		AKit.part(hc, Kit.sphere(0.05, hair, 10, 14), Vector3(0.222 * s, -0.305, 0.125), Vector3(8, 0, 14 * s), Vector3(0.75, 1.3, 0.85))
		AKit.part(hc, Kit.sphere(0.1, hair, 12, 16), Vector3(0.19 * s, -0.04, -0.03), Vector3.ZERO, Vector3(0.66, 1.2, 1.12))
	_nape(hc, hair)
	res["chains"].append(_curtain(hc, hair, 3, 0.014, 30.0))


static func _high_ponytail(hc: Node3D, hair: Material, col: Dictionary, hides: bool, res: Dictionary) -> void:
	_cap(hc, hair, false)
	AKit.part(hc, Kit.sphere(0.2, hair, 16, 22), Vector3(0, -0.07, -0.1), Vector3.ZERO, Vector3(1.1, 0.95, 0.95))
	_fringe_swept(hc, hair)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(hc, Kit.capsule(0.045, 0.2, hair), Vector3(0.205 * s, -0.07, 0.085), Vector3(10, 0, 7 * s), Vector3(0.7, 1.0, 0.9))
	# sleek nape
	for i in 3:
		var x := -0.07 + 0.07 * float(i)
		AKit.part(hc, Kit.sphere(0.05, hair, 10, 14), Vector3(x, -0.24, -0.2 + absf(x) * 0.3), Vector3(-22, x * 110.0, 0), Vector3(0.95, 1.3, 0.72))
	var root_pos := Vector3(0, 0.21, -0.215)
	var rest: Array = [Vector3(2.1, 0, 0), Vector3(-0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(-0.45, 0, 0), Vector3(-0.35, 0, 0)]
	var tie_rot := Vector3(-45, 0, 0)
	if hides:
		# under a hat: a low ponytail at the nape
		root_pos = Vector3(0, -0.03, -0.235)
		rest = [Vector3(0.35, 0, 0), Vector3(0.05, 0, 0), Vector3(0.05, 0, 0), Vector3(0.05, 0, 0), Vector3(0.05, 0, 0)]
		tie_rot = Vector3(60, 0, 0)
	var holder := AKit.node(hc, root_pos, "Ponytail")
	AKit.part(holder, Kit.torus(0.034, 0.058, AKit.m(col["secondary"], true, 0.006)), Vector3.ZERO, tie_rot, Vector3(1, 1.5, 1))
	var segs: Array = []
	var parent: Node3D = holder
	var radii := [0.068, 0.066, 0.061, 0.054, 0.045]
	for i in radii.size():
		var seg := AKit.node(parent, Vector3(0, -0.07 if i > 0 else 0.0, 0), "P%d" % i)
		seg.rotation = rest[i]
		AKit.part(seg, Kit.sphere(float(radii[i]), hair, 10, 14), Vector3(0.008 * (1.0 if i % 2 == 0 else -1.0), -0.035, 0),
			Vector3(0, 0, 18.0 if i % 2 == 0 else -18.0), Vector3(1.0, 1.3, 0.9))
		segs.append(seg)
		parent = seg
	var tip := AKit.node(parent, Vector3(0, -0.075, 0), "PTip")
	AKit.part(tip, Kit.sphere(0.035, hair, 8, 12), Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(0.9, 1.4, 0.8))
	res["chains"].append(AKit.chain("braid", segs, rest, 52.0, 5.5, 1.2))
	for i in range(1, segs.size()):
		res["hull_nodes"].append([segs[i], float(radii[i]) * 1.3])


static func _space_buns(hc: Node3D, hair: Material, col: Dictionary, hides: bool) -> void:
	_cap(hc, hair)
	_fringe_swept(hc, hair)
	_side_locks(hc, hair, true)
	_nape(hc, hair)
	var band := AKit.m(col["secondary"], true, 0.006)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var c := Vector3(0.15 * s, 0.25, -0.07)
		var r := 0.1
		var band_pos := Vector3(0.12 * s, 0.2, -0.065)
		var band_rot := Vector3(-10, 0, -34 * s)
		if hides:
			c = Vector3(0.21 * s, 0.05, -0.15)
			r = 0.09
			band_pos = Vector3(0.17 * s, 0.04, -0.12)
			band_rot = Vector3(0, -30 * s, -80 * s)
		AKit.part(hc, Kit.sphere(r, hair, 14, 18), c, Vector3.ZERO, Vector3(1.0, 0.94, 1.0))
		# a swirl on the bun and a band wrapped round its base
		AKit.part(hc, Kit.sphere(r * 0.62, hair, 10, 14), c + (c - Vector3(0, 0.03, -0.03)).normalized() * r * 0.55, Vector3(0, 0, 30 * s), Vector3(1.0, 0.7, 1.0))
		AKit.part(hc, Kit.torus(r * 0.62, r * 0.82, band), band_pos, band_rot, Vector3(1, 1.4, 1))


static func _braided_crown(hc: Node3D, hair: Material, col: Dictionary) -> void:
	_cap(hc, hair, false)
	AKit.part(hc, Kit.sphere(0.2, hair, 16, 22), Vector3(0, -0.075, -0.1), Vector3.ZERO, Vector3(1.1, 0.95, 0.95))
	_fringe_swept(hc, hair)
	_side_locks(hc, hair, false)
	var lobe := AKit.m(col["hair_light"].lerp(col["hair"], 0.55), true, 0.012)
	for i in 18:
		var a := TAU * float(i) / 18.0
		var pos := Vector3(sin(a) * 0.262, 0.15 + 0.045 * cos(a), cos(a) * 0.25 - 0.05)
		AKit.part(hc, Kit.sphere(0.05, lobe if i % 2 == 0 else hair, 10, 14), pos, Vector3(0, rad_to_deg(a), 28.0 if i % 2 == 0 else -28.0), Vector3(0.85, 1.2, 0.85))
	# little nape bun with two soft locks beside it
	AKit.part(hc, Kit.sphere(0.085, hair, 12, 16), Vector3(0, -0.16, -0.23), Vector3.ZERO, Vector3(1.1, 0.9, 0.9))
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(hc, Kit.sphere(0.05, hair, 10, 14), Vector3(0.1 * s, -0.22, -0.18), Vector3(-20, 20 * s, 0), Vector3(0.9, 1.4, 0.75))


static func _half_up(hc: Node3D, hair: Material, col: Dictionary, res: Dictionary) -> void:
	_cap(hc, hair)
	_fringe_parted(hc, hair)
	_side_locks(hc, hair, true, 0.31)
	# half-up knot at the back of the crown
	AKit.part(hc, Kit.sphere(0.07, hair, 12, 16), Vector3(0, 0.12, -0.255), Vector3.ZERO, Vector3(1.1, 0.95, 0.85))
	var ribbon := AKit.m(col["accent"], true, 0.006)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		AKit.part(hc, Kit.sphere(0.055, ribbon, 10, 14), Vector3(0.062 * s, 0.13, -0.3), Vector3(0, 0, -20 * s), Vector3(1.5, 0.9, 0.5))
	AKit.part(hc, Kit.sphere(0.026, ribbon, 8, 12), Vector3(0, 0.125, -0.315))
	res["chains"].append(_curtain(hc, hair, 3, 0.004, 32.0))
	# ribbon tails fluttering below the bow
	var tails := AKit.node(hc, Vector3(0, 0.105, -0.31), "RibbonTails")
	var segs: Array = []
	var rest: Array = []
	var parent: Node3D = tails
	for i in 2:
		var seg := AKit.node(parent, Vector3(0, -0.07 if i > 0 else 0.0, 0), "R%d" % i)
		for side in 2:
			var s := 1.0 if side == 0 else -1.0
			AKit.part(seg, Kit.box(Vector3(0.03, 0.075, 0.008), ribbon), Vector3(0.022 * s + 0.01 * s * float(i), -0.035, -0.004), Vector3(0, 0, 10 * s), Vector3.ONE, false)
		segs.append(seg)
		rest.append(Vector3(0.15 if i == 0 else 0.05, 0, 0))
		parent = seg
	res["chains"].append(AKit.chain("braid", segs, rest, 60.0, 4.0, 1.4))
