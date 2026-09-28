extends RefCounted
## Festival props of Hallowmere Reach (cached, merged, vertex-coloured meshes + shared materials).
## Convention: a prop's FRONT faces local +Z; face_yaw(from, to) turns that front toward a point.
##   stall_mesh(a, b), goods_mesh(kind), table_mesh(), bench_mesh(), hay_mesh(), crate_mesh(),
##   signpost_mesh(n_arms), road_post_mesh(), catenary(a, b, sag, n), wire(merger, pts, r, color),
##   label(parent, text, pos, size_px, color) (painted, shaded Label3D), box_col(body, xf, size)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Flora := preload("res://src/world/reach/reach_flora.gd")

const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"
const BULB := Color("ffd08a")
## Festival cloth colours: pumpkin, cream, plum, rose, mustard, forest, midnight.
const CLOTH := {"pumpkin": Color("e9822f"), "cream": Color("f3e6c8"), "plum": Color("7a4a7e"), "rose": Color("d9637a"),
	"mustard": Color("e2b23e"), "forest": Color("4f7a4a"), "midnight": Color("3f4a78"), "red": Color("b8423a")}
const STALL_AWNINGS := {
	"costumes": ["plum", "cream"], "pumpkins": ["pumpkin", "cream"], "lanterns": ["mustard", "midnight"],
	"sweets": ["rose", "cream"], "candles": ["midnight", "mustard"], "ribbons": ["forest", "cream"], "roseberries": ["red", "cream"],
}

static var _cache: Dictionary = {}
static var _font: Font = null


static func face_yaw(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


static func wood_mat() -> Material:
	return Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.12, "noise_scale": 2.0, "rim": 0.22}), 0.02)


## Flat two-sided cloth / flags: no outline (the inverted hull would cover thin geometry).
static func cloth_mat() -> Material:
	return Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.3, "wind": 0.03, "wind_height": 0.5})


static func bulb_mat() -> Material:
	return Mat.glow(BULB, 2.4)


static func stone_mat() -> Material:
	return NodeVisuals.rock_material(0.024)


static func box_col(body: StaticBody3D, xf: Transform3D, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = xf
	body.add_child(cs)
	return cs


static func cyl_col(body: StaticBody3D, pos: Vector3, radius: float, height: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	cs.shape = c
	cs.position = pos + Vector3(0, height * 0.5, 0)
	body.add_child(cs)
	return cs


static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


## Painted lettering (lit like the board it is painted on, so it never glows at night).
static func label(parent: Node3D, text: String, pos: Vector3, size_px: int = 64, color: Color = Color("4a2e20"), yaw: float = 0.0, px: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	var f := font()
	if f != null:
		l.font = f
	l.font_size = size_px
	l.pixel_size = px
	l.modulate = color
	l.outline_modulate = Color("f7ecd6")
	l.outline_size = 6
	l.double_sided = false
	l.shaded = true
	l.position = pos
	l.rotation.y = yaw
	# lettering is unreadable past a few dozen metres: stop drawing it there (fewer draw calls, no shimmer)
	l.visibility_range_end = clampf(float(size_px) * px * 180.0, 30.0, 90.0)
	parent.add_child(l)
	return l


## Points along a sagging wire from a to b (n segments -> n + 1 points).
static func catenary(a: Vector3, b: Vector3, sag: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		out.append(a.lerp(b, t) - Vector3(0, sin(t * PI) * sag, 0))
	return out


## Appends a thin wire along pts to a merger.
static func wire(m: Variant, pts: PackedVector3Array, radius: float, color: Color) -> void:
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var d := p1 - p0
		var ln := d.length()
		if ln < 0.001:
			continue
		var y := d / ln
		var x := y.cross(Vector3.UP)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized()
		var z := x.cross(y).normalized()
		m.add(NodeVisuals._cyl(radius, radius, ln, 4), Transform3D(Basis(x, y, z), (p0 + p1) * 0.5), color)


# --- Stalls -------------------------------------------------------------------------------------------

## A festival stall 3.2 m wide: counter at the front (+Z), posts, a striped sloping awning, a name board.
static func stall_mesh(kind: String) -> ArrayMesh:
	var key := "stall|" + kind
	if _cache.has(key):
		return _cache[key]
	var cols: Array = STALL_AWNINGS.get(kind, ["pumpkin", "cream"])
	var ca: Color = CLOTH[cols[0]]
	var cb: Color = CLOTH[cols[1]]
	var m := NodeVisuals.Merger.new()
	var w := 3.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var hgt := 2.55 if sz > 0.0 else 2.95
			m.add(NodeVisuals._box(Vector3(0.14, hgt, 0.14)), Transform3D(Basis(), Vector3(float(sx) * (w * 0.5 - 0.1), hgt * 0.5, float(sz) * 0.75)), Palette.WOOD_DARK)
	# counter + skirt + back shelf
	m.add(NodeVisuals._box(Vector3(w, 0.1, 0.62)), Transform3D(Basis(), Vector3(0, 1.0, 0.55)), Palette.WOOD_LIGHT)
	m.add(NodeVisuals._box(Vector3(w - 0.1, 0.9, 0.06)), Transform3D(Basis(), Vector3(0, 0.5, 0.84)), Palette.WOOD)
	for i in 7:
		var x := lerpf(-w * 0.5 + 0.3, w * 0.5 - 0.3, float(i) / 6.0)
		m.add(NodeVisuals._box(Vector3(0.2, 0.86, 0.02)), Transform3D(Basis(), Vector3(x, 0.5, 0.88)), ca if i % 2 == 0 else cb)
	m.add(NodeVisuals._box(Vector3(w - 0.3, 0.06, 0.4)), Transform3D(Basis(), Vector3(0, 1.45, -0.6)), Palette.WOOD)
	# striped awning sloping down to the front, with a scalloped edge
	var stripes := 8
	var slope := Basis(Vector3.RIGHT, deg_to_rad(18.0))
	for i in stripes:
		var x := lerpf(-w * 0.5, w * 0.5, (float(i) + 0.5) / float(stripes))
		m.add(NodeVisuals._box(Vector3(w / float(stripes) + 0.01, 0.05, 2.1)), Transform3D(slope, Vector3(x, 2.78, -0.05)), ca if i % 2 == 0 else cb)
		m.add(NodeVisuals._sph(w / float(stripes) * 0.5, 4, 8), Transform3D(Basis().scaled(Vector3(1.0, 0.55, 0.3)), Vector3(x, 2.42, 1.0)), ca if i % 2 == 0 else cb)
	# a name board on top
	m.add(NodeVisuals._box(Vector3(1.6, 0.42, 0.08)), Transform3D(Basis(), Vector3(0, 3.28, -0.4)), Palette.WOOD_LIGHT)
	m.add(NodeVisuals._box(Vector3(1.7, 0.08, 0.1)), Transform3D(Basis(), Vector3(0, 3.5, -0.4)), Palette.WOOD_DARK)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## What each stall sells, sitting on its counter (y = counter top at 1.05).
static func goods_mesh(kind: String) -> ArrayMesh:
	var key := "goods|" + kind
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var m := NodeVisuals.Merger.new()
	var top := 1.05
	match kind:
		"pumpkins":
			# straw on the counter (the pumpkins themselves are instanced by the caller: pumpkin_spots())
			for i in 3:
				m.add(Kit.blob_mesh(0.3, 7640 + i, 0.2, 0.3, 1), Transform3D(Basis(), Vector3(-1.0 + float(i) * 1.0, top + 0.02, 0.5)), Color("d9b25a"))
		"candles", "lanterns":
			for i in 9:
				var hgt := rng.randf_range(0.12, 0.34)
				var c := [Color("f3e6c8"), Color("e2b23e"), Color("d9637a"), Color("7a4a7e")][i % 4] as Color
				var x := -1.3 + float(i) * 0.33
				if kind == "lanterns":
					m.add(NodeVisuals._box(Vector3(0.2, 0.28, 0.2)), Transform3D(Basis(), Vector3(x, top + 0.14, 0.5)), Palette.WOOD_DARK)
					m.add(NodeVisuals._cyl(0.02, 0.13, 0.08, 6), Transform3D(Basis(), Vector3(x, top + 0.32, 0.5)), Palette.WOOD_DARK)
				else:
					m.add(NodeVisuals._cyl(0.045, 0.05, hgt, 7), Transform3D(Basis(), Vector3(x, top + hgt * 0.5, 0.5)), c)
		"sweets":
			for i in 4:
				var x := -1.1 + float(i) * 0.75
				m.add(NodeVisuals._cyl(0.2, 0.16, 0.14, 10), Transform3D(Basis(), Vector3(x, top + 0.07, 0.5)), Color("f3e6c8"))
				for s in 6:
					var a := float(s) * 1.1
					var c := [Color("e9822f"), Color("d9637a"), Color("f2c14e"), Color("7fbf6a")][s % 4] as Color
					m.add(NodeVisuals._sph(0.05, 3, 6), Transform3D(Basis(), Vector3(x + cos(a) * 0.1, top + 0.17, 0.5 + sin(a) * 0.1)), c)
		"ribbons":
			for i in 7:
				var c := [Color("d9637a"), Color("e2b23e"), Color("4f7a4a"), Color("7a4a7e"), Color("3f4a78"), Color("e9822f"), Color("f3e6c8")][i] as Color
				m.add(NodeVisuals._cyl(0.1, 0.1, 0.12, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-1.2 + float(i) * 0.4, top + 0.1, 0.5)), c)
				m.add(NodeVisuals._box(Vector3(0.06, 0.5, 0.01)), Transform3D(Basis(Vector3.BACK, 0.1 * float(i % 3 - 1)), Vector3(-1.2 + float(i) * 0.4, top - 0.2, 0.86)), c)
		"roseberries":
			for i in 4:
				var x := -1.1 + float(i) * 0.75
				m.add(NodeVisuals._cyl(0.24, 0.18, 0.18, 10), Transform3D(Basis(), Vector3(x, top + 0.09, 0.5)), Palette.WOOD)
				for s in 7:
					var a := float(s) * 0.9
					m.add(NodeVisuals._sph(0.06, 3, 6), Transform3D(Basis(), Vector3(x + cos(a) * 0.12, top + 0.22, 0.5 + sin(a) * 0.12)), Color("c8364a").lerp(Color("ff8fa8"), float(s % 3) * 0.2))
		"costumes":
			# a hat rack and a little rail of capes
			m.add(NodeVisuals._cyl(0.02, 0.02, 1.6, 5), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 2.05, -0.2)), Palette.WOOD_DARK)
			for i in 4:
				var c := [Color("7a4a7e"), Color("b8423a"), Color("3f4a78"), Color("e9822f")][i] as Color
				m.add(NodeVisuals._box(Vector3(0.34, 0.9, 0.06)), Transform3D(Basis(), Vector3(-0.6 + float(i) * 0.4, 1.55, -0.2)), c)
			m.add(NodeVisuals._cyl(0.0, 0.16, 0.38, 8), Transform3D(Basis(Vector3.BACK, 0.2), Vector3(-0.8, top + 0.22, 0.45)), Color("3a2e44"))
			m.add(NodeVisuals._cyl(0.3, 0.3, 0.02, 12), Transform3D(Basis(), Vector3(-0.8, top + 0.03, 0.45)), Color("3a2e44"))
			m.add(NodeVisuals._cyl(0.0, 0.14, 0.34, 8), Transform3D(Basis(Vector3.BACK, -0.25), Vector3(0.7, top + 0.2, 0.5)), Color("7a4a7e"))
			m.add(NodeVisuals._cyl(0.26, 0.26, 0.02, 12), Transform3D(Basis(), Vector3(0.7, top + 0.03, 0.5)), Color("7a4a7e"))
	if m.is_empty():
		m.add(NodeVisuals._box(Vector3(0.3, 0.3, 0.3)), Transform3D(Basis(), Vector3(0, top + 0.15, 0.5)), Palette.WOOD)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## Local pumpkin placements for a stall of `kind` ([variant, Transform3D] in stall space), or [].
static func pumpkin_spots(kind: String) -> Array:
	var out: Array = []
	if kind == "pumpkins":
		for i in 5:
			var s := 0.5 + 0.06 * float(i % 3)
			out.append([i % 4, Transform3D(Basis(Vector3.UP, float(i) * 1.3).scaled(Vector3(s, s, s)), Vector3(-1.2 + float(i) * 0.6, 1.05, 0.5))])
		for i in 3:
			out.append([i, Transform3D(Basis(Vector3.UP, float(i)).scaled(Vector3.ONE * 1.1), Vector3(-0.95 + float(i) * 0.95, 0.0, 1.4))])
	elif kind == "sweets" or kind == "candles":
		out.append([0, Transform3D(Basis().scaled(Vector3.ONE * 0.9), Vector3(1.9, 0.0, 0.9))])
	return out


# --- Furniture ------------------------------------------------------------------------------------------

## A long festival table with a runner, candles and bowls of sweets (a sweet upon every table).
static func table_mesh() -> ArrayMesh:
	if _cache.has("table"):
		return _cache["table"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._box(Vector3(2.4, 0.08, 0.9)), Transform3D(Basis(), Vector3(0, 0.78, 0)), Palette.WOOD_LIGHT)
	m.add(NodeVisuals._box(Vector3(2.46, 0.02, 0.36)), Transform3D(Basis(), Vector3(0, 0.83, 0)), CLOTH["rose"])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.add(NodeVisuals._box(Vector3(0.08, 0.76, 0.08)), Transform3D(Basis(), Vector3(float(sx) * 1.05, 0.38, float(sz) * 0.35)), Palette.WOOD_DARK)
	for i in 3:
		var x := -0.8 + float(i) * 0.8
		m.add(NodeVisuals._cyl(0.14, 0.1, 0.1, 10), Transform3D(Basis(), Vector3(x, 0.89, 0)), Color("f3e6c8"))
		for s in 5:
			var a := float(s) * 1.25
			m.add(NodeVisuals._sph(0.04, 3, 6), Transform3D(Basis(), Vector3(x + cos(a) * 0.07, 0.95, sin(a) * 0.07)), [Color("e9822f"), Color("d9637a"), Color("f2c14e")][s % 3])
	for x in [-1.05, 1.05]:
		m.add(NodeVisuals._cyl(0.04, 0.045, 0.22, 7), Transform3D(Basis(), Vector3(float(x) * 0.85, 0.94, 0.25)), Color("f3e6c8"))
	var mesh := m.commit()
	_cache["table"] = mesh
	return mesh


static func bench_mesh() -> ArrayMesh:
	if _cache.has("bench"):
		return _cache["bench"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._box(Vector3(1.8, 0.08, 0.45)), Transform3D(Basis(), Vector3(0, 0.45, 0)), Palette.WOOD)
	m.add(NodeVisuals._box(Vector3(1.8, 0.4, 0.06)), Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 0.78, -0.22)), Palette.WOOD_LIGHT)
	for sx in [-0.75, 0.75]:
		m.add(NodeVisuals._box(Vector3(0.1, 0.45, 0.4)), Transform3D(Basis(), Vector3(float(sx), 0.22, 0)), Palette.WOOD_DARK)
	var mesh := m.commit()
	_cache["bench"] = mesh
	return mesh


static func hay_mesh() -> ArrayMesh:
	if _cache.has("hay"):
		return _cache["hay"]
	var m := NodeVisuals.Merger.new()
	var fn := func(p: Vector3, n: Vector3) -> Color:
		return Color("c9a24a").lerp(Color("ecd07a"), clampf(n.y * 0.5 + p.y, 0.0, 1.0))
	m.add(Kit.blob_mesh(0.5, 7601, 0.08, 1.0, 2), Transform3D(Basis().scaled(Vector3(1.25, 0.8, 0.85)), Vector3(0, 0.4, 0)), fn)
	for sx in [-0.3, 0.3]:
		m.add(NodeVisuals._box(Vector3(0.04, 0.7, 0.9)), Transform3D(Basis(), Vector3(float(sx), 0.4, 0)), Color("8a6a3a"))
	var mesh := m.commit()
	_cache["hay"] = mesh
	return mesh


static func crate_mesh() -> ArrayMesh:
	if _cache.has("crate"):
		return _cache["crate"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._box(Vector3(0.7, 0.55, 0.55)), Transform3D(Basis(), Vector3(0, 0.275, 0)), Palette.WOOD)
	for y in [0.08, 0.47]:
		m.add(NodeVisuals._box(Vector3(0.74, 0.07, 0.59)), Transform3D(Basis(), Vector3(0, float(y), 0)), Palette.WOOD_DARK)
	var mesh := m.commit()
	_cache["crate"] = mesh
	return mesh


## A tall signpost with `arms` pointing boards (the boards are laid out by the caller's yaw per arm).
static func signpost_mesh() -> ArrayMesh:
	if _cache.has("signpost"):
		return _cache["signpost"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._cyl(0.11, 0.14, 3.6, 8), Transform3D(Basis(), Vector3(0, 1.8, 0)), Palette.WOOD_DARK)
	m.add(Kit.blob_mesh(0.3, 7611, 0.3, 0.5, 1), Transform3D(Basis(), Vector3(0, 0.08, 0)), Palette.STONE_DARK)
	m.add(NodeVisuals._cyl(0.02, 0.2, 0.2, 8), Transform3D(Basis(), Vector3(0, 3.7, 0)), Palette.WOOD_DARK)
	var mesh := m.commit()
	_cache["signpost"] = mesh
	return mesh


## One pointing arm board (points toward local -Z... +X): length 1.5 along +X from the post.
static func sign_arm_mesh(color: Color) -> ArrayMesh:
	var key := "arm|" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._box(Vector3(1.35, 0.32, 0.07)), Transform3D(Basis(), Vector3(0.78, 0, 0)), color)
	m.add(NodeVisuals._box(Vector3(0.24, 0.24, 0.07)), Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(1.45, 0, 0)), color)
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


## A road-light post (post + bracket + hanging lantern cap); the glass is a separate mesh at GLASS_POS.
const GLASS_POS := Vector3(0.42, 2.02, 0.0)
static func road_post_mesh() -> ArrayMesh:
	if _cache.has("rpost"):
		return _cache["rpost"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._cyl(0.07, 0.09, 2.45, 8), Transform3D(Basis(), Vector3(0, 1.22, 0)), Palette.WOOD_DARK)
	m.add(Kit.blob_mesh(0.2, 7621, 0.3, 0.4, 1), Transform3D(Basis(), Vector3(0, 0.05, 0)), Palette.STONE)
	m.add(NodeVisuals._box(Vector3(0.55, 0.07, 0.07)), Transform3D(Basis(), Vector3(0.24, 2.36, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._cyl(0.012, 0.012, 0.14, 4), Transform3D(Basis(), Vector3(0.42, 2.26, 0)), Palette.STONE_DARK)
	m.add(NodeVisuals._cyl(0.02, 0.16, 0.1, 8), Transform3D(Basis(), Vector3(0.42, 2.18, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._cyl(0.13, 0.14, 0.04, 8), Transform3D(Basis(), Vector3(0.42, 1.88, 0)), Palette.WOOD_DARK)
	# a little ribbon bow on the post
	m.add(Kit.blob_mesh(0.07, 7622, 0.1, 0.6, 1), Transform3D(Basis(), Vector3(0.0, 1.9, 0.09)), CLOTH["pumpkin"])
	var mesh := m.commit()
	_cache["rpost"] = mesh
	return mesh


static func lantern_glass_mesh() -> Mesh:
	if not _cache.has("rglass"):
		var c := CylinderMesh.new()
		c.top_radius = 0.1
		c.bottom_radius = 0.12
		c.height = 0.24
		c.radial_segments = 8
		_cache["rglass"] = c
	return _cache["rglass"]


static func bulb_mesh() -> Mesh:
	if not _cache.has("bulb"):
		var s := SphereMesh.new()
		s.radius = 0.06
		s.height = 0.13
		s.radial_segments = 6
		s.rings = 3
		_cache["bulb"] = s
	return _cache["bulb"]
