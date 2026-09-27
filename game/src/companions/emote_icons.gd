extends RefCounted
## Procedural emote textures in a storybook "sticker" style (no image files).
## Shapes are drawn with signed distance functions into small RGBA images once, then cached.
##   const Icons := preload("res://src/companions/emote_icons.gd")
##   sprite.texture = Icons.bubble("heart")     # speech bubble with an icon inside
##   sprite.texture = Icons.icon("star")        # outlined icon without a bubble (particles, dizzy stars)
## Bubble kinds: exclaim, question, heart, dots, zz, sparkle, drop, note, berry
## Icon kinds:   heart, star, sparkle, z, note, dot (soft round glow)

const SIZE := 96
const INK := Color("3b2f35")
const PAPER := Color("fff8ea")
const COL_RED := Color("e4665c")
const COL_HEART := Color("ea5a7e")
const COL_BLUE := Color("5b9bd5")
const COL_TEAL := Color("3fa7a0")
const COL_PURPLE := Color("9b7fd0")
const COL_GOLD := Color("f6d25a")
const COL_DROP := Color("8fcaf0")
const COL_LEAF := Color("6fae4f")
const COL_SOFT_INK := Color("6e5d63")

const BUBBLE_KINDS := ["exclaim", "question", "heart", "dots", "zz", "sparkle", "drop", "note", "berry"]
const ICON_KINDS := ["heart", "star", "sparkle", "z", "note", "dot"]

static var _cache: Dictionary = {}


## Speech bubble texture with an icon inside. Unknown kinds fall back to "dots".
static func bubble(kind: String) -> Texture2D:
	if not BUBBLE_KINDS.has(kind):
		kind = "dots"
	var key := "b|" + kind
	if not _cache.has(key):
		_cache[key] = _render(kind, true)
	return _cache[key]


## Outlined icon without a bubble. Unknown kinds fall back to "heart".
static func icon(kind: String) -> Texture2D:
	if not ICON_KINDS.has(kind):
		kind = "heart"
	var key := "i|" + kind
	if not _cache.has(key):
		if kind == "dot":
			_cache[key] = _soft_dot()
		else:
			_cache[key] = _render(kind, false)
	return _cache[key]


## Generates every texture up front (called during area load, hidden behind the fade), so the
## first emote never causes a hitch. Cheap after the first call (static cache).
static func prewarm() -> void:
	for k in BUBBLE_KINDS:
		bubble(k)
	for k in ICON_KINDS:
		icon(k)


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# --- Rendering ------------------------------------------------------------------------------

static func _render(kind: String, with_bubble: bool) -> Texture2D:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var px := 2.0 / float(SIZE)          # one pixel in shape units ([-1, 1] square, y down)
	var aa := px * 1.1
	var bubble_ow := 0.07                # bubble outline width
	var icon_ow := 0.06 if not with_bubble else 0.0
	var fill := _icon_color(kind)
	var icon_outline := INK
	if with_bubble and kind in ["sparkle", "drop"]:
		icon_ow = 0.035                  # pale icons need a thin line inside the bubble
	for y in SIZE:
		for x in SIZE:
			var u := Vector2((float(x) + 0.5) * px - 1.0, (float(y) + 0.5) * px - 1.0)
			var col := Color(INK.r, INK.g, INK.b, 0.0)
			if with_bubble:
				var db := _sd_bubble(u)
				if db > bubble_ow + aa:
					img.set_pixel(x, y, col)      # outside the bubble: fully transparent
					continue
				col = _over(col, INK, _cov(db - bubble_ow, aa))
				col = _over(col, PAPER, _cov(db, aa))
				var ui := (u - Vector2(0.0, -0.12)) / 0.78   # icon space inside the bubble
				var di := _sd_icon(kind, ui) * 0.78
				if kind == "berry":
					col = _draw_berry(col, ui, aa / 0.78, 0.78)
				else:
					if icon_ow > 0.0:
						col = _over(col, icon_outline, _cov(di - icon_ow, aa))
					col = _over(col, fill, _cov(di, aa))
			else:
				var ui2 := u / 0.86
				var di2 := _sd_icon(kind, ui2) * 0.86
				col = _over(col, icon_outline, _cov(di2 - icon_ow, aa))
				col = _over(col, fill, _cov(di2, aa))
				# a little glossy highlight on hearts and notes
				if kind == "heart":
					var dh := (ui2 - Vector2(-0.3, -0.28)).length() - 0.11
					col = _over(col, Color(1, 1, 1, 0.55), _cov(dh, aa) * _cov(di2 + 0.05, aa))
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _icon_color(kind: String) -> Color:
	match kind:
		"exclaim": return COL_RED
		"question": return COL_BLUE
		"heart": return COL_HEART
		"dots": return COL_SOFT_INK
		"zz", "z": return COL_PURPLE
		"sparkle", "star": return COL_GOLD
		"drop": return COL_DROP
		"note": return COL_TEAL
	return COL_RED


## Coverage (0..1) of a shape with signed distance d, anti-aliased over `aa`.
static func _cov(d: float, aa: float) -> float:
	return clampf(0.5 - d / aa, 0.0, 1.0)


## "Over" compositing of a colour with coverage `a` onto `dst`.
static func _over(dst: Color, src: Color, a: float) -> Color:
	var sa := src.a * a
	if sa <= 0.0:
		return dst
	var out_a := sa + dst.a * (1.0 - sa)
	if out_a <= 0.0001:
		return dst
	var r := (src.r * sa + dst.r * dst.a * (1.0 - sa)) / out_a
	var g := (src.g * sa + dst.g * dst.a * (1.0 - sa)) / out_a
	var b := (src.b * sa + dst.b * dst.a * (1.0 - sa)) / out_a
	return Color(r, g, b, out_a)


# --- Signed distance functions (shape units, y down unless noted) -----------------------------

static func _sd_bubble(u: Vector2) -> float:
	var c := (u - Vector2(0.0, -0.12)).length() - 0.74
	var t := _sd_triangle(u, Vector2(-0.2, 0.45), Vector2(0.14, 0.52), Vector2(-0.04, 0.9))
	return _smin(c, t, 0.08)


static func _sd_icon(kind: String, u: Vector2) -> float:
	match kind:
		"exclaim":
			return minf(_sd_capsule(u, Vector2(0, -0.55), Vector2(0, 0.08), 0.14), (u - Vector2(0, 0.42)).length() - 0.14)
		"question":
			var d := 1e9
			var pts := [Vector2(-0.34, -0.3), Vector2(-0.3, -0.5), Vector2(-0.14, -0.63), Vector2(0.06, -0.64),
				Vector2(0.24, -0.55), Vector2(0.32, -0.38), Vector2(0.26, -0.2), Vector2(0.1, -0.07),
				Vector2(0.0, 0.03), Vector2(0.0, 0.14)]
			for i in pts.size() - 1:
				d = minf(d, _sd_capsule(u, pts[i], pts[i + 1], 0.12))
			return minf(d, (u - Vector2(0, 0.44)).length() - 0.13)
		"heart":
			# iq's heart (y up, tip at origin): map so the heart is centred.
			var s := 0.62
			var hp := Vector2(u.x / s, (-u.y) / s + 0.58)
			return _sd_heart(hp) * s
		"dots":
			var dd := (u - Vector2(-0.4, 0.0)).length() - 0.14
			dd = minf(dd, u.length() - 0.14)
			return minf(dd, (u - Vector2(0.4, 0.0)).length() - 0.14)
		"zz":
			var z1 := _sd_z(u - Vector2(-0.2, 0.2), 0.25, 0.085)
			var z2 := _sd_z(u - Vector2(0.3, -0.36), 0.15, 0.065)
			return minf(z1, z2)
		"z":
			return _sd_z(u, 0.42, 0.14)
		"sparkle":
			var s1 := _sd_sparkle(u - Vector2(-0.08, 0.06), 0.62)
			var s2 := _sd_sparkle(u - Vector2(0.45, -0.45), 0.26)
			return minf(s1, s2)
		"star":
			return _sd_star5(Vector2(u.x, -u.y + 0.06), 0.78, 0.46) - 0.08
		"drop":
			# uneven capsule: big round bottom, pointy top (y up)
			return _sd_uneven_capsule(Vector2(u.x, -(u.y - 0.28)), 0.34, 0.03, 0.72)
		"note":
			var head := _sd_ellipse_approx(u - Vector2(-0.18, 0.38), Vector2(0.24, 0.18))
			var stem := _sd_capsule(u, Vector2(0.03, 0.34), Vector2(0.03, -0.6), 0.07)
			var flag := _sd_capsule(u, Vector2(0.03, -0.6), Vector2(0.34, -0.36), 0.07)
			return minf(minf(head, stem), flag)
	return u.length() - 0.5


static func _draw_berry(col: Color, u: Vector2, aa: float, scale: float) -> Color:
	# A little cluster of three berries with a leaf: "I'd love some berries!"
	var berries := [Vector2(-0.24, 0.12), Vector2(0.24, 0.12), Vector2(0.0, -0.2)]
	var leaf := _sd_ellipse_approx(_rot(u - Vector2(0.22, -0.52), -0.6), Vector2(0.24, 0.1))
	col = _over(col, INK, _cov((leaf - 0.05) * scale, aa * scale))
	col = _over(col, COL_LEAF, _cov(leaf * scale, aa * scale))
	for b in berries:
		var bp: Vector2 = b
		var d := (u - bp).length() - 0.27
		col = _over(col, INK, _cov((d - 0.05) * scale, aa * scale))
		col = _over(col, COL_RED, _cov(d * scale, aa * scale))
		var hl := (u - bp - Vector2(-0.09, -0.09)).length() - 0.07
		col = _over(col, Color(1, 1, 1, 0.8), _cov(hl * scale, aa * scale))
	return col


static func _rot(p: Vector2, a: float) -> Vector2:
	var c := cos(a)
	var s := sin(a)
	return Vector2(p.x * c - p.y * s, p.x * s + p.y * c)


static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _sd_capsule(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 1e-6), 0.0, 1.0)
	return (pa - ba * h).length() - r


static func _sd_z(p: Vector2, s: float, r: float) -> float:
	var d := _sd_capsule(p, Vector2(-s, -s), Vector2(s, -s), r)
	d = minf(d, _sd_capsule(p, Vector2(s, -s), Vector2(-s, s), r))
	return minf(d, _sd_capsule(p, Vector2(-s, s), Vector2(s, s), r))


static func _sd_triangle(p: Vector2, p0: Vector2, p1: Vector2, p2: Vector2) -> float:
	var e0 := p1 - p0
	var e1 := p2 - p1
	var e2 := p0 - p2
	var v0 := p - p0
	var v1 := p - p1
	var v2 := p - p2
	var pq0 := v0 - e0 * clampf(v0.dot(e0) / e0.dot(e0), 0.0, 1.0)
	var pq1 := v1 - e1 * clampf(v1.dot(e1) / e1.dot(e1), 0.0, 1.0)
	var pq2 := v2 - e2 * clampf(v2.dot(e2) / e2.dot(e2), 0.0, 1.0)
	var s := signf(e0.x * e2.y - e0.y * e2.x)
	var d0 := Vector2(pq0.dot(pq0), s * (v0.x * e0.y - v0.y * e0.x))
	var d1 := Vector2(pq1.dot(pq1), s * (v1.x * e1.y - v1.y * e1.x))
	var d2 := Vector2(pq2.dot(pq2), s * (v2.x * e2.y - v2.y * e2.x))
	var dmin := Vector2(minf(minf(d0.x, d1.x), d2.x), minf(minf(d0.y, d1.y), d2.y))
	return -sqrt(dmin.x) * signf(dmin.y)


static func _sd_heart(p: Vector2) -> float:
	p.x = absf(p.x)
	if p.y + p.x > 1.0:
		return (p - Vector2(0.25, 0.75)).length() - sqrt(2.0) / 4.0
	var a := (p - Vector2(0.0, 1.0)).length_squared()
	var m := maxf(p.x + p.y, 0.0) * 0.5
	var b := (p - Vector2(m, m)).length_squared()
	return sqrt(minf(a, b)) * signf(p.x - p.y)


static func _sd_rhombus(p: Vector2, b: Vector2) -> float:
	p = Vector2(absf(p.x), absf(p.y))
	var bb := b - 2.0 * p
	var h := clampf((bb.x * b.x - bb.y * b.y) / b.dot(b), -1.0, 1.0)
	var d := (p - 0.5 * b * Vector2(1.0 - h, 1.0 + h)).length()
	return d * signf(p.x * b.y + p.y * b.x - b.x * b.y)


static func _sd_sparkle(p: Vector2, r: float) -> float:
	var a := _sd_rhombus(p, Vector2(r, r * 0.26))
	var b := _sd_rhombus(p, Vector2(r * 0.26, r))
	return _smin(a, b, r * 0.12)


static func _sd_star5(p: Vector2, r: float, rf: float) -> float:
	var k1 := Vector2(0.809016994375, -0.587785252292)
	var k2 := Vector2(-k1.x, k1.y)
	p.x = absf(p.x)
	p -= 2.0 * maxf(k1.dot(p), 0.0) * k1
	p -= 2.0 * maxf(k2.dot(p), 0.0) * k2
	p.x = absf(p.x)
	p.y -= r
	var ba := rf * Vector2(-k1.y, k1.x) - Vector2(0, 1)
	var h := clampf(p.dot(ba) / ba.dot(ba), 0.0, r)
	return (p - ba * h).length() * signf(p.y * ba.x - p.x * ba.y)


static func _sd_uneven_capsule(p: Vector2, r1: float, r2: float, h: float) -> float:
	p.x = absf(p.x)
	var b := (r1 - r2) / h
	var a := sqrt(1.0 - b * b)
	var k := p.dot(Vector2(-b, a))
	if k < 0.0:
		return p.length() - r1
	if k > a * h:
		return (p - Vector2(0.0, h)).length() - r2
	return p.dot(Vector2(a, b)) - r1


## Cheap ellipse distance (good enough for small icons).
static func _sd_ellipse_approx(p: Vector2, r: Vector2) -> float:
	var k0 := (p / r).length()
	var k1 := (p / (r * r)).length()
	if k1 < 1e-6:
		return -minf(r.x, r.y)
	return k0 * (k0 - 1.0) / k1
