extends RefCounted
## Procedural storybook "sticker" icons, rasterised on the CPU into Images and cached as ImageTextures.
## Every `icon` id used in data/items.gd has a hand-composed drawing here (soft shapes, warm ink
## outline, gentle top-lit shading, a cream sticker border and a soft drop shadow). Unknown ids get a
## tidy fallback. Drawings are authored on a 96x96 design grid and scaled to the requested size.
##   const IconFactory := preload("res://src/ui/icon_factory.gd")
##   rect.texture = IconFactory.item_icon("wood")              # respects the arachnophobia option
##   rect.texture = IconFactory.icon("ui_heart", Palette.UI_HEALTH, 48)
##   rect.texture = IconFactory.portrait("mochi")
## Shapes are signed distance fields evaluated per pixel inside each shape's bounding box, so the
## result is anti-aliased at any size. Rendering one icon takes a few milliseconds; results are cached.

const Palette := preload("res://src/art/palette.gd")

const SIZE := 96
const DESIGN := 96.0
const INK := Color("3b2f35")
const BACKING := Color("fffaf0")

## Every icon id referenced by data/items.gd (kept in sync by tests/unit/test_ui_icons.gd).
const ITEM_ICONS := ["log", "stone", "fiber", "berries", "ore", "seeds", "root", "pebble", "mushroom",
	"silk", "crystal", "axe", "pickaxe", "sword", "lantern", "snack", "stew", "skewer", "workbench",
	"chest", "bed", "plot", "floor", "wall", "window", "doorway", "roof", "fence", "lamppost",
	"flowerpot", "rug", "table", "stool", "cairn", "chime", "heartbloom", "banner", "key", "heartseed"]
## Additional drawings: the arachnophobia silk variant, the fallback and UI / map glyphs.
const EXTRA_ICONS := ["spool", "unknown", "ui_heart", "ui_heart_empty", "ui_stamina", "ui_check", "ui_star",
	"ui_info", "ui_warn", "ui_bag", "ui_sun", "ui_moon", "ui_lock", "ui_close", "ui_hint", "ui_quest",
	"ui_save", "ui_speaker", "map_house", "map_ruin", "map_mine", "map_pond", "map_flower", "map_oak",
	"map_thorn", "map_quarry", "map_glade"]
const PORTRAITS := ["mochi", "pebble", "lumi"]

static var _cache: Dictionary = {}


# --- Public API ----------------------------------------------------------------------------------

## Icon texture for an item id (uses the item's `icon` and `color`). Silk becomes a thread spool
## when arachnophobia mode is on. Unknown items get the fallback icon.
static func item_icon(item_id: String, size: int = SIZE) -> Texture2D:
	return icon(item_icon_id(item_id), item_color(item_id), size)


## The icon drawing id used for an item (after the arachnophobia swap).
static func item_icon_id(item_id: String) -> String:
	var icon_id := "unknown"
	if ItemDB.has_item(item_id):
		icon_id = String(ItemDB.item(item_id).get("icon", "unknown"))
	if icon_id == "silk" and _arachno():
		icon_id = "spool"
	return icon_id


static func item_color(item_id: String) -> Color:
	if ItemDB.has_item(item_id):
		var c: Variant = ItemDB.item(item_id).get("color", Color.WHITE)
		if c is Color:
			return c
	return Color("d8c7a8")


## Cached texture for a drawing id. `color` is the item colour (ignored by fixed-colour glyphs).
static func icon(icon_id: String, color: Color = Color.WHITE, size: int = SIZE) -> Texture2D:
	var key := "%s|%s|%d" % [icon_id, color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := render(icon_id, color, size)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Round companion portrait (no sticker border; the UI frames it).
static func portrait(creature_id: String, size: int = 128) -> Texture2D:
	return icon("portrait_" + creature_id, Color.WHITE, size)


## Small flat glyph (no sticker border) of any size, e.g. theme checkboxes. `kind` is a glyph id.
static func glyph(kind: String, w: int, h: int, color: Color = Color.WHITE) -> Texture2D:
	var key := "glyph|%s|%d|%d|%s" % [kind, w, h, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var r := Raster.new(w, h, float(h) / 48.0, false)
	_draw_glyph(r, kind, color)
	var tex := ImageTexture.create_from_image(r.to_image(false))
	_cache[key] = tex
	return tex


## True if `icon_id` has its own drawing (otherwise the fallback is used).
static func has_drawing(icon_id: String) -> bool:
	return ITEM_ICONS.has(icon_id) or EXTRA_ICONS.has(icon_id) or (icon_id.begins_with("portrait_") and PORTRAITS.has(icon_id.substr(9)))


## Renders an icon into a new Image (not cached). Always returns a valid size x size RGBA8 image.
static func render(icon_id: String, color: Color = Color.WHITE, size: int = SIZE) -> Image:
	size = clampi(size, 8, 512)
	var sticker := not icon_id.begins_with("portrait_")
	var r := Raster.new(size, size, float(size) / DESIGN, sticker)
	_compose(r, icon_id, color)
	var img := r.to_image(sticker)
	if size >= 32:
		img.generate_mipmaps()
	return img


static func clear_cache() -> void:
	_cache.clear()


static func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


# --- Shape constructors (design units, 96 grid; angles in degrees) -------------------------------

static func C(x: float, y: float, rad: float) -> Dictionary:
	return {"k": 0, "x": x, "y": y, "r": rad}


static func E(x: float, y: float, rx: float, ry: float, rot: float = 0.0) -> Dictionary:
	return {"k": 1, "x": x, "y": y, "rx": maxf(rx, 0.1), "ry": maxf(ry, 0.1), "rot": deg_to_rad(rot)}


static func B(x: float, y: float, hw: float, hh: float, rad: float = 0.0, rot: float = 0.0) -> Dictionary:
	return {"k": 2, "x": x, "y": y, "hw": hw, "hh": hh, "rad": minf(rad, minf(hw, hh)), "rot": deg_to_rad(rot)}


## Polyline stroke with round caps. `radii` is a float or an Array with one radius per point (tapers).
static func L(points: Array, radii: Variant) -> Dictionary:
	var pts := PackedVector2Array(points)
	var rr := PackedFloat32Array()
	for i in pts.size():
		if radii is Array:
			var arr: Array = radii
			rr.append(float(arr[mini(i, arr.size() - 1)]))
		else:
			rr.append(float(radii))
	return {"k": 3, "p": pts, "r": rr}


static func P(points: Array, rnd: float = 0.0) -> Dictionary:
	return {"k": 4, "p": PackedVector2Array(points), "rnd": rnd}


static func R(x: float, y: float, rad: float, thick: float) -> Dictionary:
	return {"k": 5, "x": x, "y": y, "r": rad, "t": thick}


## Marks a part as a cut-out (subtracted from the union of the other parts of the same fill).
static func CUT(part: Dictionary) -> Dictionary:
	var p := part.duplicate()
	p["cut"] = true
	return p


static func _star(cx: float, cy: float, outer: float, inner: float, points: int = 4, rot: float = 0.0) -> Dictionary:
	var pts: Array = []
	for i in points * 2:
		var a := deg_to_rad(rot) - PI * 0.5 + PI * float(i) / float(points)
		var rad := outer if i % 2 == 0 else inner
		pts.append(Vector2(cx + cos(a) * rad, cy + sin(a) * rad))
	return P(pts, 0.6)


static func _heart(cx: float, cy: float, s: float) -> Array:
	# Two lobes and a rounded point; s = lobe radius.
	return [C(cx - s * 0.78, cy, s), C(cx + s * 0.78, cy, s),
		P([Vector2(cx - s * 1.62, cy + s * 0.42), Vector2(cx + s * 1.62, cy + s * 0.42), Vector2(cx, cy + s * 2.05)], s * 0.12)]


# --- Composition ---------------------------------------------------------------------------------

const NO_LINE := {"o": 0.0, "back": false, "shade": 0.0}
const DETAIL := {"o": 0.0, "back": false, "shade": 0.05}


static func _gloss(r: Raster, part: Dictionary, alpha: float = 0.45) -> void:
	r.fill([part], Color(1, 1, 1, alpha), NO_LINE)


## Soft glow that fades to nothing exactly at `rad` (keep it inside the canvas).
static func _halo(r: Raster, x: float, y: float, rad: float, c: Color, alpha: float = 0.4) -> void:
	r.fill([C(x, y, rad * 0.5)], Color(c.r, c.g, c.b, alpha), {"o": 0.0, "back": false, "shade": 0.0, "soft": rad})


static func _sparkle(r: Raster, x: float, y: float, s: float) -> void:
	r.fill([_star(x, y, s, s * 0.34)], Color("fffbe8"), {"o": 2.0, "shade": 0.0})


static func _compose(r: Raster, id: String, c: Color) -> void:
	match id:
		"log": _log(r, c)
		"stone": _stone(r, c)
		"fiber": _fiber(r, c)
		"berries": _berries(r, c)
		"ore": _ore(r, c)
		"seeds": _seeds(r, c)
		"root": _root(r, c)
		"pebble": _pebble(r, c)
		"mushroom": _mushroom(r, c)
		"silk": _silk(r, c)
		"spool": _spool(r, c)
		"crystal": _crystal(r, c)
		"axe": _axe(r, c)
		"pickaxe": _pickaxe(r, c)
		"sword": _sword(r, c)
		"lantern": _lantern(r, c)
		"snack": _snack(r, c)
		"stew": _stew(r, c)
		"skewer": _skewer(r, c)
		"workbench": _workbench(r, c)
		"chest": _chest(r, c)
		"bed": _bed(r, c)
		"plot": _plot(r, c)
		"floor": _floor(r, c)
		"wall": _wall(r, c)
		"window": _window(r, c)
		"doorway": _doorway(r, c)
		"roof": _roof(r, c)
		"fence": _fence(r, c)
		"lamppost": _lamppost(r, c)
		"flowerpot": _flowerpot(r, c)
		"rug": _rug(r, c)
		"table": _table(r, c)
		"stool": _stool(r, c)
		"cairn": _cairn(r, c)
		"chime": _chime(r, c)
		"heartbloom": _heartbloom(r, c)
		"banner": _banner(r, c)
		"key": _key(r, c)
		"heartseed": _heartseed(r, c)
		"ui_heart": _ui_heart(r, Palette.UI_HEALTH if c == Color.WHITE else c)
		"ui_heart_empty": _ui_heart_empty(r)
		"ui_stamina": _ui_stamina(r)
		"ui_check": _ui_check(r)
		"ui_star": _ui_star(r)
		"ui_info": _ui_info(r)
		"ui_warn": _ui_warn(r)
		"ui_bag": _ui_bag(r)
		"ui_sun": _ui_sun(r)
		"ui_moon": _ui_moon(r)
		"ui_lock": _ui_lock(r)
		"ui_close": _ui_close(r)
		"ui_hint": _ui_hint(r)
		"ui_quest": _ui_quest(r)
		"ui_save": _ui_save(r)
		"ui_speaker": _ui_speaker(r)
		"map_house": _map_house(r)
		"map_ruin": _map_ruin(r)
		"map_mine": _map_mine(r)
		"map_pond": _map_pond(r)
		"map_flower": _map_flower(r)
		"map_oak": _map_oak(r)
		"map_thorn": _map_thorn(r)
		"map_quarry": _stone(r, Palette.STONE)
		"map_glade": _berries(r, Palette.FLOWER_RED)
		"portrait_mochi": _portrait_mochi(r)
		"portrait_pebble": _portrait_pebble(r)
		"portrait_lumi": _portrait_lumi(r)
		_: _unknown(r)


# --- Item drawings ----------------------------------------------------------------------------

static func _log(r: Raster, c: Color) -> void:
	r.fill([L([Vector2(26, 66), Vector2(66, 38)], 17.0)], c.darkened(0.05))
	var groove := c.darkened(0.38)
	r.fill([L([Vector2(24, 56), Vector2(44, 42)], 1.7)], groove, DETAIL)
	r.fill([L([Vector2(33, 70), Vector2(54, 56)], 1.7)], groove, DETAIL)
	r.fill([L([Vector2(22, 67), Vector2(28, 63)], 1.5)], groove, DETAIL)
	r.fill([C(66, 38, 15.0)], Palette.WOOD_LIGHT)
	r.fill([R(66, 38, 8.5, 2.2)], Palette.WOOD.darkened(0.08), DETAIL)
	r.fill([C(66, 38, 3.0)], Palette.WOOD.darkened(0.08), DETAIL)
	_gloss(r, E(60, 31, 4, 2.5, -30), 0.5)
	# a tiny sprout on top of the log
	r.fill([L([Vector2(30, 46), Vector2(28, 36)], 1.8)], Palette.FOLIAGE_DARK)
	r.fill([E(21, 33, 7, 4, -25)], Palette.FOLIAGE_LIGHT)
	r.fill([E(34, 30, 6.5, 3.6, 30)], Palette.FOLIAGE)


static func _stone(r: Raster, c: Color) -> void:
	r.fill([P([Vector2(56, 50), Vector2(72, 46), Vector2(80, 60), Vector2(72, 72), Vector2(57, 69)], 5.0)], c.darkened(0.14))
	r.fill([P([Vector2(20, 58), Vector2(33, 36), Vector2(54, 32), Vector2(67, 48), Vector2(62, 72), Vector2(34, 76)], 6.0)], c)
	_gloss(r, E(38, 45, 9, 5, -25), 0.5)
	r.fill([C(50, 62, 2.2)], c.darkened(0.25), DETAIL)
	r.fill([C(42, 66, 1.6)], c.darkened(0.25), DETAIL)
	r.fill([L([Vector2(54, 44), Vector2(58, 52), Vector2(55, 58)], 1.2)], c.darkened(0.3), DETAIL)


static func _fiber(r: Raster, c: Color) -> void:
	var tip := [4.5, 3.6, 1.4]
	r.fill([L([Vector2(44, 80), Vector2(34, 48), Vector2(20, 22)], tip)], c.darkened(0.18))
	r.fill([L([Vector2(52, 80), Vector2(66, 50), Vector2(80, 30)], tip)], c.darkened(0.12))
	r.fill([L([Vector2(46, 80), Vector2(42, 44), Vector2(36, 12)], tip)], c)
	r.fill([L([Vector2(50, 80), Vector2(58, 42), Vector2(64, 14)], tip)], c.lightened(0.1))
	r.fill([L([Vector2(48, 80), Vector2(49, 44), Vector2(50, 18)], tip)], c.lightened(0.2))
	r.fill([B(48, 64, 14, 5.5, 3.0, -4)], Palette.DIRT)
	r.fill([L([Vector2(38, 63), Vector2(58, 62)], 1.1)], Palette.DIRT_DARK, DETAIL)
	r.fill([C(60, 66, 3.5)], Palette.DIRT_DARK)


static func _berries(r: Raster, c: Color) -> void:
	r.fill([E(62, 24, 14, 6.5, -28)], Palette.FOLIAGE)
	r.fill([L([Vector2(54, 26), Vector2(66, 21)], 1.0)], Palette.FOLIAGE_DARK, DETAIL)
	r.fill([L([Vector2(48, 44), Vector2(52, 30), Vector2(56, 26)], 2.2)], Palette.BARK)
	r.fill([C(35, 52, 15.0)], c.darkened(0.06))
	r.fill([C(61, 51, 14.0)], c)
	r.fill([C(48, 70, 14.5)], c.lightened(0.04))
	for p in [Vector2(29, 46), Vector2(55, 45), Vector2(42, 64)]:
		_gloss(r, C(p.x, p.y, 3.6), 0.75)
	r.fill([C(48, 44, 2.2)], c.darkened(0.4), DETAIL)


static func _ore(r: Raster, c: Color) -> void:
	r.fill([P([Vector2(18, 58), Vector2(30, 34), Vector2(52, 26), Vector2(74, 38), Vector2(78, 62), Vector2(58, 78), Vector2(30, 76)], 5.0)], Palette.STONE_DARK)
	_gloss(r, E(36, 40, 8, 4, -30), 0.3)
	var nug := c.lightened(0.05)
	r.fill([P([Vector2(33, 44), Vector2(46, 40), Vector2(49, 53), Vector2(37, 57)], 3.0)], nug)
	r.fill([P([Vector2(55, 50), Vector2(68, 47), Vector2(67, 62), Vector2(56, 63)], 3.0)], nug.darkened(0.06))
	r.fill([C(41, 67, 5.0)], nug)
	r.fill([C(60, 34, 3.6)], nug)
	for p in [Vector2(38, 45), Vector2(58, 52), Vector2(39, 65)]:
		_gloss(r, C(p.x, p.y, 2.0), 0.8)


static func _seeds(r: Raster, c: Color) -> void:
	r.fill([E(32, 64, 9, 13, 30)], c.darkened(0.08))
	r.fill([E(62, 66, 9, 13, -22)], c)
	r.fill([E(47, 50, 9.5, 13.5, 4)], c.lightened(0.08))
	for p in [Vector2(30, 60), Vector2(60, 62), Vector2(45, 46)]:
		_gloss(r, E(p.x, p.y, 2.5, 4.5, 15), 0.5)
	r.fill([L([Vector2(47, 38), Vector2(48, 26)], 2.0)], Palette.FOLIAGE_DARK)
	r.fill([E(40, 23, 8, 4, 28)], Palette.FOLIAGE_LIGHT)
	r.fill([E(56, 21, 8, 4, -28)], Palette.FOLIAGE)


static func _root(r: Raster, c: Color) -> void:
	r.fill([E(40, 24, 5.5, 14, -28)], Palette.FOLIAGE)
	r.fill([E(58, 25, 5.5, 13, 32)], Palette.FOLIAGE_DARK)
	r.fill([E(49, 20, 5.5, 15, 4)], Palette.FOLIAGE_LIGHT)
	r.fill([L([Vector2(48, 40), Vector2(48, 60), Vector2(46, 84)], [18.0, 12.0, 3.0])], c)
	var ln := c.darkened(0.25)
	r.fill([L([Vector2(36, 50), Vector2(43, 52)], 1.4)], ln, DETAIL)
	r.fill([L([Vector2(53, 60), Vector2(59, 58)], 1.4)], ln, DETAIL)
	r.fill([L([Vector2(40, 68), Vector2(45, 70)], 1.3)], ln, DETAIL)
	_gloss(r, E(40, 45, 3.5, 7, 10), 0.45)


static func _pebble(r: Raster, c: Color) -> void:
	r.fill([E(46, 56, 27, 21)], c)
	r.fill([E(46, 66, 20, 8)], c.darkened(0.08), NO_LINE)
	_gloss(r, E(36, 47, 10, 5.5, -18), 0.75)
	_gloss(r, C(56, 44, 2.5), 0.8)
	_sparkle(r, 72, 26, 11)
	_sparkle(r, 24, 28, 6)


static func _mushroom(r: Raster, c: Color) -> void:
	_halo(r, 46, 48, 44, c, 0.5)
	var cream := Color("fff4e0")
	r.fill([L([Vector2(70, 80), Vector2(70, 64)], [4.5, 3.8])], cream)
	r.fill([E(70, 62, 11, 7)], c.darkened(0.05))
	r.fill([L([Vector2(44, 80), Vector2(44, 54)], [9.5, 7.5])], cream)
	r.fill([E(44, 46, 29, 17), CUT(B(44, 70, 40, 12))], c)
	r.fill([E(44, 56, 25, 4)], c.darkened(0.2), NO_LINE)
	for p in [[33, 40, 4.2], [52, 36, 3.4], [46, 47, 2.8], [60, 45, 2.4]]:
		r.fill([C(float(p[0]), float(p[1]), float(p[2]))], Color(1, 1, 1, 0.85), NO_LINE)
	_gloss(r, E(32, 36, 6, 3, -20), 0.5)


static func _silk(r: Raster, c: Color) -> void:
	# a twisted skein of pale silk: two soft lobes wrapped by a band, with a loose curly end
	var ln := c.darkened(0.16)
	r.fill([L([Vector2(74, 58), Vector2(80, 68), Vector2(74, 76), Vector2(80, 84)], 1.8)], c)
	r.fill([E(29, 52, 19, 15, 25)], c)
	r.fill([E(67, 44, 19, 15, 25)], c.lightened(0.04))
	r.fill([R(29, 52, 9.5, 1.6)], ln, DETAIL)
	r.fill([R(67, 44, 9.5, 1.6)], ln, DETAIL)
	r.fill([C(29, 52, 4.2)], ln, DETAIL)
	r.fill([C(67, 44, 4.2)], ln, DETAIL)
	r.fill([B(48, 48, 8, 17, 3, 25)], c.darkened(0.08))
	r.fill([L([Vector2(43, 38), Vector2(53, 42)], 1.2), L([Vector2(41, 46), Vector2(51, 50)], 1.2), L([Vector2(39, 54), Vector2(49, 58)], 1.2)], ln, DETAIL)
	_gloss(r, E(24, 44, 6, 3, -20), 0.6)
	_gloss(r, E(62, 36, 6, 3, -20), 0.6)
	_sparkle(r, 80, 20, 7)


static func _spool(r: Raster, c: Color) -> void:
	r.fill([B(48, 48, 16, 22, 3)], c)
	var ln := c.darkened(0.14)
	for y in [34.0, 42.0, 50.0, 58.0]:
		r.fill([L([Vector2(34, y), Vector2(62, y + 2.0)], 1.2)], ln, DETAIL)
	_gloss(r, B(40, 46, 3, 16, 3), 0.5)
	r.fill([L([Vector2(63, 54), Vector2(74, 62), Vector2(78, 78)], 2.0)], c)
	r.fill([B(48, 22, 25, 6, 4)], Palette.WOOD)
	r.fill([B(48, 74, 25, 6, 4)], Palette.WOOD)
	_gloss(r, B(40, 20, 12, 1.5, 1.5), 0.45)


static func _crystal(r: Raster, c: Color) -> void:
	r.fill([P([Vector2(58, 32), Vector2(70, 40), Vector2(74, 72), Vector2(61, 80), Vector2(54, 48)], 1.5)], c.darkened(0.16))
	r.fill([P([Vector2(22, 48), Vector2(32, 52), Vector2(34, 78), Vector2(24, 82), Vector2(16, 70)], 1.5)], c.lightened(0.1))
	r.fill([P([Vector2(42, 12), Vector2(55, 28), Vector2(56, 74), Vector2(44, 84), Vector2(32, 74), Vector2(30, 28)], 1.5)], c)
	r.fill([P([Vector2(42, 14), Vector2(45, 28), Vector2(43, 72), Vector2(37, 74), Vector2(34, 30)], 0.5)], Color(1, 1, 1, 0.35), NO_LINE)
	_sparkle(r, 72, 22, 8)


static func _axe(r: Raster, c: Color) -> void:
	r.fill([L([Vector2(34, 86), Vector2(58, 18)], 5.5)], Palette.WOOD)
	_gloss(r, L([Vector2(37, 78), Vector2(55, 28)], 1.4), 0.4)
	r.fill([P([Vector2(52, 20), Vector2(68, 22), Vector2(82, 12), Vector2(86, 30), Vector2(80, 48), Vector2(66, 38), Vector2(54, 36)], 3.0)], c)
	_gloss(r, L([Vector2(81, 18), Vector2(81, 40)], 1.8), 0.6)
	r.fill([B(56, 30, 7, 4.5, 2, -70)], Palette.MEADOW_GOLD)


static func _pickaxe(r: Raster, c: Color) -> void:
	r.fill([L([Vector2(32, 88), Vector2(55, 26)], 5.5)], Palette.WOOD)
	_gloss(r, L([Vector2(35, 80), Vector2(52, 34)], 1.4), 0.4)
	r.fill([L([Vector2(12, 40), Vector2(28, 24), Vector2(55, 17), Vector2(80, 22), Vector2(92, 36)], [1.8, 6.0, 8.0, 6.0, 1.8])], c)
	_gloss(r, L([Vector2(30, 22), Vector2(54, 15), Vector2(72, 17)], 1.5), 0.55)
	r.fill([B(54, 27, 7, 5, 2, -20)], Palette.MEADOW_GOLD)


static func _sword(r: Raster, c: Color) -> void:
	var blade := c.lightened(0.18)
	r.fill([P([Vector2(35, 51), Vector2(66, 20), Vector2(82, 14), Vector2(76, 30), Vector2(45, 61)], 1.5)], blade)
	r.fill([L([Vector2(44, 52), Vector2(70, 26)], 1.6)], c.darkened(0.12), DETAIL)
	_gloss(r, L([Vector2(38, 50), Vector2(66, 22)], 1.4), 0.55)
	r.fill([L([Vector2(38, 60), Vector2(20, 78)], 4.8)], Palette.WOOD_DARK)
	r.fill([L([Vector2(27, 45), Vector2(51, 69)], 5.2)], c.darkened(0.22))
	r.fill([C(18, 80, 6.5)], c.darkened(0.12))
	_gloss(r, C(16, 78, 1.8), 0.7)


static func _lantern(r: Raster, c: Color) -> void:
	_halo(r, 48, 52, 44, c, 0.55)
	var metal := Color("5b4a57")
	r.fill([R(48, 15, 7.5, 3.5)], metal)
	r.fill([B(48, 76, 20, 5, 3)], metal)
	r.fill([B(48, 52, 17, 20, 6)], c.lightened(0.45))
	r.fill([L([Vector2(48, 64), Vector2(48, 44)], [7.0, 1.0])], Palette.MINE_LIGHT, NO_LINE)
	r.fill([C(48, 60, 3.5)], Color("fff4c8"), NO_LINE)
	r.fill([L([Vector2(34, 34), Vector2(34, 71)], 2.4)], metal)
	r.fill([L([Vector2(62, 34), Vector2(62, 71)], 2.4)], metal)
	r.fill([P([Vector2(30, 33), Vector2(66, 33), Vector2(58, 21), Vector2(38, 21)], 3.0)], metal)
	_gloss(r, B(40, 48, 2, 10, 2), 0.6)


static func _snack(r: Raster, c: Color) -> void:
	r.fill([B(48, 50, 30, 15, 9, -12)], c)
	for p in [[33, 50, 4.0, -0.25], [45, 42, 3.4, 0.2], [60, 50, 3.8, -0.3], [66, 40, 3.0, 0.15], [40, 60, 3.0, 0.1]]:
		var col: Color = c.darkened(float(p[3])) if float(p[3]) > 0.0 else c.lightened(-float(p[3]))
		r.fill([C(float(p[0]), float(p[1]), float(p[2]))], col, NO_LINE)
	r.fill([B(49, 50, 8, 18, 2, -12)], Palette.CLOTH_CREAM)
	r.fill([L([Vector2(45, 38), Vector2(49, 60)], 1.0)], Palette.WOOD_LIGHT, DETAIL)
	_gloss(r, L([Vector2(26, 42), Vector2(38, 38)], 1.6), 0.5)


static func _stew(r: Raster, c: Color) -> void:
	var steam := Color(1, 1, 1, 0.92)
	r.fill([L([Vector2(38, 34), Vector2(34, 25), Vector2(40, 16)], 3.0)], steam, {"o": 2.0, "shade": 0.0})
	r.fill([L([Vector2(56, 32), Vector2(60, 22), Vector2(55, 13)], 3.0)], steam, {"o": 2.0, "shade": 0.0})
	r.fill([E(48, 56, 34, 10), E(48, 58, 31, 26), CUT(B(48, 34, 40, 22))], Palette.WOOD)
	r.fill([E(48, 55, 28, 7)], c)
	r.fill([C(37, 54, 4.0)], Palette.FLOWER_RED, NO_LINE)
	r.fill([C(56, 56, 4.5)], Color("f29a4a"), NO_LINE)
	r.fill([C(47, 52, 3.0)], Palette.FOLIAGE, NO_LINE)
	r.fill([C(63, 53, 2.5)], Palette.FOLIAGE_LIGHT, NO_LINE)
	_gloss(r, L([Vector2(22, 66), Vector2(30, 74)], 1.8), 0.35)


static func _skewer(r: Raster, c: Color) -> void:
	r.fill([L([Vector2(16, 84), Vector2(82, 18)], 3.0)], Palette.WOOD_LIGHT)
	for t in [0.3, 0.52, 0.74]:
		var p := Vector2(16, 84).lerp(Vector2(82, 18), t)
		r.fill([E(p.x, p.y, 12, 8, -45)], c)
		r.fill([E(p.x + 3, p.y + 3, 6, 3, -45)], Color(Palette.BARK.r, Palette.BARK.g, Palette.BARK.b, 0.35), NO_LINE)
		_gloss(r, E(p.x - 4, p.y - 4, 4, 2, -45), 0.6)


static func _workbench(r: Raster, c: Color) -> void:
	var dk := c.darkened(0.2)
	r.fill([B(26, 66, 5.5, 17, 2)], dk)
	r.fill([B(70, 66, 5.5, 17, 2)], dk)
	r.fill([B(48, 70, 20, 3.5, 1.5)], dk)
	r.fill([B(48, 46, 38, 9, 4)], c)
	r.fill([L([Vector2(14, 49), Vector2(82, 49)], 1.0)], c.darkened(0.25), DETAIL)
	_gloss(r, L([Vector2(16, 41), Vector2(56, 41)], 1.4), 0.4)
	r.fill([L([Vector2(38, 36), Vector2(58, 28)], 2.6)], Palette.WOOD_LIGHT)
	r.fill([B(62, 26, 5, 8.5, 2, -22)], Palette.STONE_DARK)
	r.fill([C(26, 34, 3.5)], Palette.STONE)


static func _chest(r: Raster, c: Color) -> void:
	var gold := Color("e2b95a")
	r.fill([B(48, 62, 33, 20, 5)], c)
	r.fill([B(48, 40, 34, 13, 11)], c.lightened(0.1))
	r.fill([L([Vector2(16, 51), Vector2(80, 51)], 1.4)], c.darkened(0.35), DETAIL)
	r.fill([B(29, 55, 4, 27, 1.5)], gold, {"o": 2.0})
	r.fill([B(67, 55, 4, 27, 1.5)], gold, {"o": 2.0})
	r.fill([B(48, 52, 7, 9, 2.5)], gold)
	r.fill([C(48, 52, 2.2)], INK, NO_LINE)
	_gloss(r, B(40, 34, 14, 2, 2), 0.45)


static func _bed(r: Raster, c: Color) -> void:
	r.fill([B(18, 50, 7, 26, 5)], Palette.WOOD)
	r.fill([B(80, 60, 6, 15, 4)], Palette.WOOD)
	r.fill([B(50, 70, 33, 6, 3)], Palette.WOOD_DARK)
	r.fill([B(52, 58, 29, 10, 6)], Color("fff4e0"))
	r.fill([B(58, 56, 23, 12, 6)], c)
	r.fill([L([Vector2(38, 50), Vector2(80, 50)], 1.2)], c.darkened(0.2), DETAIL)
	r.fill([E(32, 48, 10, 6.5)], Palette.CLOTH_CREAM)
	_gloss(r, E(54, 50, 12, 2.2), 0.4)


static func _plot(r: Raster, c: Color) -> void:
	r.fill([B(48, 62, 37, 17, 8)], c)
	r.fill([L([Vector2(18, 58), Vector2(78, 58)], 2.0)], c.darkened(0.3), DETAIL)
	r.fill([L([Vector2(18, 69), Vector2(78, 69)], 2.0)], c.darkened(0.3), DETAIL)
	for x in [30.0, 48.0, 66.0]:
		r.fill([L([Vector2(x, 56), Vector2(x, 44)], 1.8)], Palette.FOLIAGE_DARK)
		r.fill([E(x - 6, 41, 6, 3.3, 30)], Palette.FOLIAGE_LIGHT)
		r.fill([E(x + 6, 41, 6, 3.3, -30)], Palette.FOLIAGE)


static func _floor(r: Raster, c: Color) -> void:
	r.fill([P([Vector2(14, 56), Vector2(48, 75), Vector2(48, 83), Vector2(14, 64)], 0.5)], c.darkened(0.28))
	r.fill([P([Vector2(48, 75), Vector2(82, 56), Vector2(82, 64), Vector2(48, 83)], 0.5)], c.darkened(0.14))
	r.fill([P([Vector2(14, 56), Vector2(48, 37), Vector2(82, 56), Vector2(48, 75)], 1.0)], c)
	var ln := c.darkened(0.25)
	for k in [1.0, 2.0, 3.0]:
		var a := Vector2(14, 56).lerp(Vector2(48, 75), k / 4.0)
		var b := Vector2(48, 37).lerp(Vector2(82, 56), k / 4.0)
		r.fill([L([a, b], 1.2)], ln, DETAIL)
	_gloss(r, L([Vector2(26, 52), Vector2(44, 42)], 1.4), 0.4)


static func _wall(r: Raster, c: Color) -> void:
	r.fill([B(48, 50, 29, 33, 4)], c)
	var ln := c.darkened(0.28)
	for x in [34.0, 48.0, 62.0]:
		r.fill([L([Vector2(x, 20), Vector2(x, 80)], 1.3)], ln, DETAIL)
	r.fill([B(48, 34, 31, 4, 2)], c.darkened(0.18))
	r.fill([B(48, 66, 31, 4, 2)], c.darkened(0.18))
	for p in [Vector2(27, 34), Vector2(69, 34), Vector2(27, 66), Vector2(69, 66)]:
		r.fill([C(p.x, p.y, 1.6)], INK, NO_LINE)
	_gloss(r, B(28, 50, 2, 26, 2), 0.3)


static func _window(r: Raster, c: Color) -> void:
	r.fill([B(48, 50, 29, 33, 4)], c)
	var ln := c.darkened(0.28)
	for x in [30.0, 66.0]:
		r.fill([L([Vector2(x, 20), Vector2(x, 80)], 1.3)], ln, DETAIL)
	r.fill([C(48, 44, 16)], Palette.WATER.lightened(0.25))
	r.fill([L([Vector2(48, 29), Vector2(48, 59)], 2.0)], c.darkened(0.15), {"o": 1.5, "back": false})
	r.fill([L([Vector2(33, 44), Vector2(63, 44)], 2.0)], c.darkened(0.15), {"o": 1.5, "back": false})
	_gloss(r, E(41, 37, 4, 2.5, -30), 0.75)
	r.fill([B(48, 65, 15, 3, 1.5)], c.darkened(0.18))


static func _doorway(r: Raster, c: Color) -> void:
	r.fill([B(48, 50, 29, 33, 4)], c)
	var ln := c.darkened(0.28)
	for x in [27.0, 69.0]:
		r.fill([L([Vector2(x, 20), Vector2(x, 80)], 1.3)], ln, DETAIL)
	r.fill([B(48, 66, 13, 17, 1.5), C(48, 48, 13)], Palette.BARK_DARK)
	r.fill([B(48, 80, 16, 3, 1.5)], Palette.STONE)
	r.fill([E(48, 72, 9, 3)], Color(Palette.LANTERN_GLOW.r, Palette.LANTERN_GLOW.g, Palette.LANTERN_GLOW.b, 0.35), NO_LINE)


static func _roof(r: Raster, c: Color) -> void:
	r.fill([B(66, 36, 5, 10, 1.5)], Palette.STONE)
	r.fill([P([Vector2(12, 66), Vector2(48, 22), Vector2(84, 66)], 4.0)], c)
	var ln := c.darkened(0.22)
	for x in [30.0, 48.0, 66.0]:
		r.fill([L([Vector2(48, 30), Vector2(x, 64)], 1.3)], ln, DETAIL)
	r.fill([B(48, 70, 40, 5, 3)], c.darkened(0.2))
	_gloss(r, L([Vector2(26, 56), Vector2(44, 32)], 1.5), 0.45)


static func _fence(r: Raster, c: Color) -> void:
	r.fill([B(48, 44, 38, 4, 2)], c.darkened(0.14))
	r.fill([B(48, 66, 38, 4, 2)], c.darkened(0.14))
	for x in [24.0, 48.0, 72.0]:
		r.fill([P([Vector2(x - 6, 82), Vector2(x - 6, 32), Vector2(x, 23), Vector2(x + 6, 32), Vector2(x + 6, 82)], 2.0)], c)
		_gloss(r, B(x - 2.5, 50, 1.2, 14, 1.2), 0.5)


static func _lamppost(r: Raster, c: Color) -> void:
	_halo(r, 62, 42, 26, c, 0.5)
	r.fill([B(30, 83, 12, 4, 2)], Palette.STONE)
	r.fill([L([Vector2(30, 82), Vector2(30, 18)], 4.5)], Palette.WOOD_DARK)
	r.fill([L([Vector2(30, 20), Vector2(62, 20)], 3.0)], Palette.WOOD_DARK)
	var metal := Color("5b4a57")
	r.fill([L([Vector2(62, 22), Vector2(62, 28)], 1.5)], metal)
	r.fill([B(62, 42, 9, 11, 3)], c.lightened(0.45))
	r.fill([L([Vector2(62, 48), Vector2(62, 37)], [4.0, 0.8])], Palette.MINE_LIGHT, NO_LINE)
	r.fill([P([Vector2(51, 33), Vector2(73, 33), Vector2(68, 27), Vector2(56, 27)], 2.0)], metal)
	r.fill([B(62, 55, 10, 2.5, 1.5)], metal)


static func _flowerpot(r: Raster, c: Color) -> void:
	r.fill([E(32, 44, 11, 5, 30)], Palette.FOLIAGE)
	r.fill([E(64, 44, 11, 5, -30)], Palette.FOLIAGE_DARK)
	r.fill([L([Vector2(40, 54), Vector2(36, 30)], 1.8)], Palette.FOLIAGE_DARK, {"o": 1.5})
	r.fill([L([Vector2(56, 54), Vector2(60, 28)], 1.8)], Palette.FOLIAGE_DARK, {"o": 1.5})
	r.fill([L([Vector2(48, 54), Vector2(48, 40)], 1.8)], Palette.FOLIAGE_DARK, {"o": 1.5})
	_flower(r, 35, 28, 8.0, c)
	_flower(r, 61, 26, 8.0, Palette.FLOWER_WHITE)
	_flower(r, 48, 40, 7.0, Palette.BLOSSOM.lightened(0.1))
	var pot := Color("c9a58a")
	r.fill([P([Vector2(27, 56), Vector2(69, 56), Vector2(63, 84), Vector2(33, 84)], 3.0)], pot)
	r.fill([B(48, 57, 25, 5, 3)], pot.lightened(0.1))
	_gloss(r, B(36, 70, 2, 8, 2), 0.35)


static func _flower(r: Raster, x: float, y: float, s: float, c: Color) -> void:
	var parts: Array = []
	for i in 5:
		var a := TAU * float(i) / 5.0 - PI * 0.5
		parts.append(C(x + cos(a) * s * 0.62, y + sin(a) * s * 0.62, s * 0.52))
	r.fill(parts, c)
	r.fill([C(x, y, s * 0.36)], Palette.FLOWER_YELLOW, {"o": 1.5, "back": false})


static func _rug(r: Raster, c: Color) -> void:
	var cream := Palette.CLOTH_CREAM
	for y in [34.0, 42.0, 50.0, 58.0, 66.0]:
		r.fill([L([Vector2(14, y), Vector2(8, y)], 1.6)], cream, {"o": 1.6})
		r.fill([L([Vector2(82, y), Vector2(88, y)], 1.6)], cream, {"o": 1.6})
	r.fill([B(48, 50, 35, 25, 9)], c)
	r.fill([B(48, 50, 27, 17, 6)], cream, NO_LINE)
	r.fill([B(48, 50, 23, 13, 5)], c.darkened(0.06), NO_LINE)
	r.fill([P([Vector2(48, 40), Vector2(58, 50), Vector2(48, 60), Vector2(38, 50)], 1.0)], Palette.FLOWER_YELLOW, {"o": 2.0, "back": false})
	r.fill([C(48, 50, 3.0)], Palette.TEAL, NO_LINE)
	for p in [Vector2(30, 50), Vector2(66, 50)]:
		r.fill([C(p.x, p.y, 2.6)], cream, NO_LINE)


static func _table(r: Raster, c: Color) -> void:
	var dk := c.darkened(0.22)
	r.fill([E(48, 80, 17, 4.5)], dk)
	r.fill([B(48, 64, 6, 16, 2)], dk)
	r.fill([E(48, 48, 36, 11)], dk)
	r.fill([E(48, 43, 36, 11)], c)
	_gloss(r, E(38, 40, 14, 3.5), 0.4)


static func _stool(r: Raster, c: Color) -> void:
	var dk := c.darkened(0.22)
	r.fill([L([Vector2(37, 52), Vector2(29, 84)], 3.8)], dk)
	r.fill([L([Vector2(59, 52), Vector2(67, 84)], 3.8)], dk)
	r.fill([L([Vector2(48, 56), Vector2(48, 86)], 3.8)], dk.darkened(0.1))
	r.fill([L([Vector2(33, 71), Vector2(63, 71)], 2.2)], dk)
	r.fill([E(48, 52, 25, 8.5)], dk)
	r.fill([E(48, 47, 25, 8.5)], c)
	_gloss(r, E(40, 45, 9, 2.5), 0.45)


static func _cairn(r: Raster, c: Color) -> void:
	r.fill([E(48, 72, 29, 11)], Palette.STONE)
	r.fill([E(46, 55, 22, 9)], c.darkened(0.12))
	r.fill([E(50, 40, 15, 7.5)], c)
	r.fill([E(47, 28, 9, 6)], c.lightened(0.15))
	_gloss(r, E(42, 25, 3, 1.8), 0.8)
	_gloss(r, E(44, 37, 5, 2), 0.6)
	_gloss(r, E(36, 68, 7, 2.5), 0.4)
	_sparkle(r, 70, 22, 8)


static func _chime(r: Raster, c: Color) -> void:
	r.fill([L([Vector2(48, 6), Vector2(48, 16)], 1.2)], Palette.UI_INK_SOFT, NO_LINE)
	r.fill([L([Vector2(22, 19), Vector2(74, 19)], 4.0)], Palette.WOOD)
	for x in [30.0, 48.0, 66.0]:
		r.fill([L([Vector2(x, 23), Vector2(x, 42 if x != 48.0 else 50)], 1.1)], Palette.UI_INK_SOFT, NO_LINE)
	r.fill([P([Vector2(30, 42), Vector2(35, 50), Vector2(33, 68), Vector2(27, 68), Vector2(25, 50)], 1.0)], c.darkened(0.08))
	r.fill([P([Vector2(48, 50), Vector2(54, 60), Vector2(51, 82), Vector2(45, 82), Vector2(42, 60)], 1.0)], c.lightened(0.1))
	r.fill([P([Vector2(66, 42), Vector2(71, 50), Vector2(69, 64), Vector2(63, 64), Vector2(61, 50)], 1.0)], c)
	_gloss(r, L([Vector2(46, 58), Vector2(46, 74)], 1.2), 0.55)
	_sparkle(r, 80, 40, 6)


static func _heartbloom(r: Raster, c: Color) -> void:
	_halo(r, 48, 44, 42, c, 0.55)
	r.fill([L([Vector2(48, 86), Vector2(48, 56)], 3.0)], Palette.FOLIAGE_DARK)
	r.fill([E(37, 72, 10, 4.5, 30)], Palette.FOLIAGE)
	r.fill([E(59, 68, 10, 4.5, -30)], Palette.FOLIAGE_LIGHT)
	r.fill(_heart(48, 34, 14.0), c)
	r.fill(_heart(48, 36, 7.0), c.lightened(0.35), NO_LINE)
	_gloss(r, E(38, 29, 4, 2.5, -30), 0.7)


static func _banner(r: Raster, c: Color) -> void:
	r.fill([L([Vector2(24, 88), Vector2(24, 14)], 3.5)], Palette.WOOD_DARK)
	r.fill([L([Vector2(24, 18), Vector2(74, 18)], 3.0)], Palette.WOOD_DARK)
	r.fill([P([Vector2(30, 20), Vector2(70, 20), Vector2(70, 78), Vector2(50, 66), Vector2(30, 78)], 2.0)], c)
	r.fill([L([Vector2(34, 28), Vector2(66, 28)], 1.0)], c.lightened(0.3), DETAIL)
	r.fill(_heart(50, 40, 6.5), Palette.FLOWER_YELLOW, {"o": 2.0, "back": false})
	r.fill([C(24, 11, 5.0)], Color("e2b95a"))
	_gloss(r, B(35, 44, 1.5, 18, 1.5), 0.35)


static func _key(r: Raster, c: Color) -> void:
	r.fill([B(60, 44, 25, 5.5, 2.5)], c)
	r.fill([B(74, 56, 4.5, 8, 1.5)], c)
	r.fill([B(84, 54, 3.5, 6, 1.5)], c)
	r.fill([C(28, 44, 17)], c)
	r.fill([C(28, 44, 7)], BACKING)
	_gloss(r, E(21, 36, 5, 3, -35), 0.6)
	_gloss(r, B(62, 41, 18, 1.2, 1.2), 0.45)


static func _heartseed(r: Raster, c: Color) -> void:
	_halo(r, 48, 50, 44, c, 0.6)
	r.fill([L([Vector2(48, 36), Vector2(51, 20)], 2.2)], Palette.FOLIAGE_DARK)
	r.fill([E(59, 18, 8, 4, -20)], Palette.FOLIAGE_LIGHT)
	r.fill(_heart(48, 46, 16.0), c)
	r.fill(_heart(48, 48, 9.0), c.lightened(0.4), NO_LINE)
	r.fill(_heart(48, 50, 4.0), Color("fff2f5"), NO_LINE)
	_gloss(r, E(36, 40, 5, 3, -30), 0.7)
	_sparkle(r, 78, 28, 7)
	_sparkle(r, 18, 70, 6)


static func _unknown(r: Raster) -> void:
	r.fill([C(48, 48, 32)], Palette.UI_PAPER_DARK)
	r.fill([L([Vector2(37, 38), Vector2(40, 29), Vector2(48, 25), Vector2(57, 29), Vector2(59, 37), Vector2(53, 44), Vector2(48, 49), Vector2(48, 56)], 4.8)], Palette.UI_INK_SOFT, NO_LINE)
	r.fill([C(48, 68, 5.2)], Palette.UI_INK_SOFT, NO_LINE)


# --- UI glyphs (sticker style) ------------------------------------------------------------------

static func _ui_heart(r: Raster, c: Color) -> void:
	r.fill(_heart(48, 38, 18.0), c)
	_gloss(r, E(35, 32, 6, 3.5, -30), 0.65)


static func _ui_heart_empty(r: Raster) -> void:
	r.fill(_heart(48, 38, 18.0), Color("d9c7b8"))
	r.fill(_heart(48, 40, 11.0), Color("c9b5a6"), NO_LINE)


static func _ui_stamina(r: Raster) -> void:
	r.fill([P([Vector2(56, 8), Vector2(24, 54), Vector2(44, 54), Vector2(36, 88), Vector2(72, 38), Vector2(51, 38), Vector2(62, 8)], 2.0)], Palette.UI_STAMINA)
	_gloss(r, L([Vector2(53, 16), Vector2(36, 46)], 1.8), 0.55)


static func _ui_check(r: Raster) -> void:
	r.fill([C(48, 48, 34)], Palette.UI_GOOD)
	r.fill([L([Vector2(30, 50), Vector2(43, 63), Vector2(67, 35)], 6.0)], Color.WHITE, {"o": 0.0, "back": false, "shade": 0.0})


static func _ui_star(r: Raster) -> void:
	r.fill([_star(48, 50, 36, 16, 5)], Palette.FLOWER_YELLOW)
	_gloss(r, E(40, 38, 5, 3, -30), 0.6)


static func _ui_info(r: Raster) -> void:
	r.fill([C(48, 48, 34)], Palette.FLOWER_BLUE)
	r.fill([C(48, 30, 5.5)], Color.WHITE, NO_LINE)
	r.fill([L([Vector2(48, 44), Vector2(48, 68)], 5.2)], Color.WHITE, NO_LINE)


static func _ui_warn(r: Raster) -> void:
	r.fill([P([Vector2(48, 14), Vector2(84, 78), Vector2(12, 78)], 7.0)], Palette.UI_WARN)
	r.fill([L([Vector2(48, 36), Vector2(48, 56)], 5.0)], INK, NO_LINE)
	r.fill([C(48, 68, 4.5)], INK, NO_LINE)


static func _ui_bag(r: Raster) -> void:
	r.fill([R(48, 30, 13, 5)], Palette.WOOD_DARK)
	r.fill([B(48, 58, 28, 24, 10)], Palette.K_BAG)
	r.fill([B(48, 46, 28, 10, 8)], Palette.K_BAG.darkened(0.12))
	r.fill([B(48, 54, 5, 6, 2)], Color("e2b95a"))
	_gloss(r, B(32, 62, 2.5, 12, 2.5), 0.35)


static func _ui_sun(r: Raster) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		r.fill([L([Vector2(48 + cos(a) * 30, 48 + sin(a) * 30), Vector2(48 + cos(a) * 40, 48 + sin(a) * 40)], 3.5)], Palette.FLOWER_YELLOW)
	r.fill([C(48, 48, 22)], Palette.FLOWER_YELLOW)
	_gloss(r, E(40, 40, 6, 4, -30), 0.6)


static func _ui_moon(r: Raster) -> void:
	r.fill([C(48, 48, 30), CUT(C(62, 38, 24))], Palette.MOON.lightened(0.25))
	r.fill([C(34, 56, 3.5)], Palette.MOON, NO_LINE)
	r.fill([C(40, 68, 2.5)], Palette.MOON, NO_LINE)


static func _ui_lock(r: Raster) -> void:
	r.fill([R(48, 38, 14, 6)], Palette.STONE_DARK)
	r.fill([B(48, 60, 24, 20, 6)], Color("e2b95a"))
	r.fill([C(48, 56, 4.5), B(48, 64, 2.5, 6, 1)], INK, NO_LINE)


static func _ui_close(r: Raster) -> void:
	r.fill([L([Vector2(30, 30), Vector2(66, 66)], 7.0), L([Vector2(66, 30), Vector2(30, 66)], 7.0)], Palette.UI_ACCENT)


static func _ui_hint(r: Raster) -> void:
	_halo(r, 48, 42, 40, Palette.LANTERN_GLOW, 0.45)
	r.fill([B(48, 72, 11, 8, 3)], Palette.STONE_DARK)
	r.fill([C(48, 42, 22)], Palette.LANTERN_GLOW.lightened(0.2))
	r.fill([L([Vector2(42, 46), Vector2(48, 38), Vector2(54, 46)], 2.2)], Palette.MINE_LIGHT, NO_LINE)
	_gloss(r, E(40, 34, 6, 4, -30), 0.7)


static func _ui_quest(r: Raster) -> void:
	r.fill([B(48, 50, 24, 30, 4)], Palette.UI_PAPER)
	r.fill([E(48, 20, 28, 7)], Palette.UI_PAPER_DARK)
	r.fill([E(48, 80, 28, 7)], Palette.UI_PAPER_DARK)
	for y in [38.0, 48.0, 58.0]:
		r.fill([L([Vector2(34, y), Vector2(62, y)], 1.6)], Palette.UI_INK_SOFT, NO_LINE)
	r.fill([C(62, 66, 7)], Palette.UI_ACCENT)


static func _ui_save(r: Raster) -> void:
	r.fill([B(48, 50, 30, 32, 6)], Palette.TEAL)
	r.fill([B(48, 30, 18, 10, 2)], Palette.UI_PAPER)
	r.fill([B(48, 64, 20, 12, 3)], Palette.UI_PAPER_DARK)
	r.fill([B(56, 30, 4, 7, 1)], Palette.TEAL.darkened(0.2), NO_LINE)


static func _ui_speaker(r: Raster) -> void:
	r.fill([P([Vector2(18, 38), Vector2(34, 38), Vector2(52, 20), Vector2(52, 76), Vector2(34, 58), Vector2(18, 58)], 3.0)], Palette.UI_INK_SOFT)
	r.fill([L([Vector2(64, 36), Vector2(70, 48), Vector2(64, 60)], 3.0)], Palette.UI_INK_SOFT, NO_LINE)
	r.fill([L([Vector2(74, 28), Vector2(82, 48), Vector2(74, 68)], 3.0)], Palette.UI_INK_SOFT, NO_LINE)


# --- Map landmarks --------------------------------------------------------------------------------

static func _map_house(r: Raster) -> void:
	r.fill([B(64, 30, 5, 10, 1.5)], Palette.STONE)
	r.fill([B(48, 62, 26, 20, 4)], Palette.CLOTH_CREAM)
	r.fill([P([Vector2(14, 48), Vector2(48, 18), Vector2(82, 48)], 4.0)], Palette.THATCH)
	r.fill([B(48, 70, 7, 12, 2)], Palette.WOOD_DARK)
	r.fill([C(33, 60, 5)], Palette.LANTERN_GLOW)


static func _map_ruin(r: Raster) -> void:
	r.fill([B(28, 56, 8, 26, 2)], Palette.RUIN_STONE.lightened(0.2))
	r.fill([B(68, 62, 8, 20, 2)], Palette.RUIN_STONE.lightened(0.2))
	r.fill([P([Vector2(20, 32), Vector2(48, 20), Vector2(62, 26), Vector2(56, 34), Vector2(36, 36)], 3.0)], Palette.RUIN_STONE.lightened(0.3))
	r.fill([E(30, 34, 8, 4)], Palette.RUIN_MOSS, NO_LINE)
	r.fill([C(48, 70, 5)], Palette.LANTERN_GLOW, {"o": 2.0})


static func _map_mine(r: Raster) -> void:
	r.fill([P([Vector2(10, 82), Vector2(24, 34), Vector2(48, 16), Vector2(74, 30), Vector2(88, 82)], 5.0)], Palette.MINE_ROCK.lightened(0.15))
	r.fill([B(48, 66, 15, 17, 1), C(48, 50, 15)], Palette.MINE_ROCK_DARK.darkened(0.3))
	r.fill([L([Vector2(30, 84), Vector2(30, 44), Vector2(66, 44), Vector2(66, 84)], 3.5)], Palette.MINE_TIMBER)


static func _map_pond(r: Raster) -> void:
	r.fill([E(48, 54, 36, 24)], Palette.WATER)
	r.fill([E(48, 56, 26, 16)], Palette.WATER.lightened(0.15), NO_LINE)
	r.fill([E(62, 50, 9, 5), CUT(P([Vector2(62, 50), Vector2(74, 44), Vector2(74, 56)]))], Palette.FOLIAGE_LIGHT)
	r.fill([C(34, 58, 4)], Palette.BLOSSOM)


static func _map_flower(r: Raster) -> void:
	r.fill([L([Vector2(48, 86), Vector2(48, 50)], 2.5)], Palette.FOLIAGE_DARK)
	r.fill([E(38, 72, 9, 4, 30)], Palette.FOLIAGE)
	_flower(r, 48, 38, 20.0, Palette.FLOWER_YELLOW.lightened(0.1))
	r.fill([C(48, 38, 6)], Palette.FLOWER_RED, {"o": 1.5, "back": false})


static func _map_oak(r: Raster) -> void:
	r.fill([L([Vector2(48, 88), Vector2(48, 56)], [9.0, 6.0])], Palette.BARK)
	r.fill([C(30, 46, 17), C(66, 46, 17), C(48, 30, 22), C(48, 50, 18)], Palette.FOLIAGE_DARK)
	r.fill([C(42, 26, 7)], Palette.FOLIAGE, NO_LINE)
	r.fill([C(60, 40, 5)], Palette.FOLIAGE, NO_LINE)


static func _map_thorn(r: Raster) -> void:
	r.fill([C(48, 54, 28)], Palette.FOLIAGE_DARK.darkened(0.15))
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		r.fill([L([Vector2(48 + cos(a) * 22, 54 + sin(a) * 22), Vector2(48 + cos(a) * 36, 54 + sin(a) * 36)], [3.5, 0.8])], Palette.BARK_DARK)
	r.fill([C(40, 46, 4.5)], Palette.FLOWER_RED, NO_LINE)
	r.fill([C(58, 60, 3.5)], Palette.FLOWER_RED, NO_LINE)


# --- Companion portraits (circle backdrop; framed by the UI) ------------------------------------

static func _portrait_mochi(r: Raster) -> void:
	r.fill([C(48, 48, 46)], Palette.FOLIAGE_LIGHT.lightened(0.35), {"o": 0.0, "back": false, "shade": 0.1})
	r.fill([E(48, 94, 40, 14)], Palette.GRASS.lightened(0.2), {"o": 0.0, "back": false, "shade": 0.0})
	var body := Color("f6e7cf")
	var cap := Color("e4665c")
	r.fill([E(48, 70, 22, 20)], body)
	r.fill([E(48, 44, 36, 26), CUT(B(48, 76, 50, 14))], cap)
	for p in [[34, 38, 5.5], [56, 32, 4.5], [66, 48, 3.8], [44, 54, 3.2], [24, 52, 3.0]]:
		r.fill([C(float(p[0]), float(p[1]), float(p[2]))], Color("fff4e0"), NO_LINE)
	r.fill([E(40, 72, 3.2, 4.6)], INK, NO_LINE)
	r.fill([E(56, 72, 3.2, 4.6)], INK, NO_LINE)
	r.fill([C(41, 70.5, 1.2)], Color.WHITE, NO_LINE)
	r.fill([C(57, 70.5, 1.2)], Color.WHITE, NO_LINE)
	r.fill([E(33, 78, 4, 2.4)], Color(Palette.BLOSSOM.r, Palette.BLOSSOM.g, Palette.BLOSSOM.b, 0.7), NO_LINE)
	r.fill([E(63, 78, 4, 2.4)], Color(Palette.BLOSSOM.r, Palette.BLOSSOM.g, Palette.BLOSSOM.b, 0.7), NO_LINE)
	r.fill([L([Vector2(45, 79), Vector2(48, 81), Vector2(51, 79)], 1.1)], INK, NO_LINE)
	_gloss(r, E(32, 30, 8, 4, -30), 0.5)


static func _portrait_pebble(r: Raster) -> void:
	r.fill([C(48, 48, 46)], Palette.FLOWER_BLUE.lightened(0.45), {"o": 0.0, "back": false, "shade": 0.1})
	r.fill([E(48, 94, 40, 14)], Palette.DIRT.lightened(0.2), {"o": 0.0, "back": false, "shade": 0.0})
	var body := Color("9a948a")
	r.fill([P([Vector2(20, 62), Vector2(26, 36), Vector2(46, 24), Vector2(68, 28), Vector2(78, 50), Vector2(74, 78), Vector2(48, 86), Vector2(24, 80)], 6.0)], body)
	r.fill([E(46, 26, 20, 8), E(34, 30, 9, 6)], Color("7dbb5b"))
	r.fill([C(58, 22, 3)], Palette.FLOWER_YELLOW, {"o": 1.5, "back": false})
	r.fill([L([Vector2(32, 50), Vector2(43, 53)], 2.2)], INK, NO_LINE)
	r.fill([L([Vector2(64, 49), Vector2(53, 53)], 2.2)], INK, NO_LINE)
	r.fill([E(39, 60, 3.4, 4.2)], INK, NO_LINE)
	r.fill([E(58, 60, 3.4, 4.2)], INK, NO_LINE)
	r.fill([C(40, 58.5, 1.2)], Color.WHITE, NO_LINE)
	r.fill([C(59, 58.5, 1.2)], Color.WHITE, NO_LINE)
	r.fill([L([Vector2(43, 72), Vector2(49, 70), Vector2(54, 72)], 1.3)], INK, NO_LINE)
	r.fill([L([Vector2(68, 64), Vector2(72, 70)], 1.2)], body.darkened(0.3), NO_LINE)
	_gloss(r, E(34, 40, 6, 3, -30), 0.45)


static func _portrait_lumi(r: Raster) -> void:
	r.fill([C(48, 48, 46)], Color("3b3f6e").lightened(0.15), {"o": 0.0, "back": false, "shade": 0.15})
	_halo(r, 48, 56, 40, Color("ffd98a"), 0.55)
	var body := Color("fff1c9")
	var ear := Color("f7c35c")
	r.fill([E(28, 32, 7, 17, -28)], ear)
	r.fill([E(68, 32, 7, 17, 28)], ear)
	r.fill([E(28, 34, 3, 10, -28)], Palette.BLOSSOM, NO_LINE)
	r.fill([E(68, 34, 3, 10, 28)], Palette.BLOSSOM, NO_LINE)
	r.fill([E(48, 62, 27, 24)], body)
	r.fill([E(39, 60, 5, 6.5)], INK, NO_LINE)
	r.fill([E(57, 60, 5, 6.5)], INK, NO_LINE)
	r.fill([C(40.5, 57.5, 2.0)], Color.WHITE, NO_LINE)
	r.fill([C(58.5, 57.5, 2.0)], Color.WHITE, NO_LINE)
	r.fill([C(48, 69, 1.8)], ear.darkened(0.3), NO_LINE)
	r.fill([E(32, 70, 4, 2.4)], Color(Palette.BLOSSOM.r, Palette.BLOSSOM.g, Palette.BLOSSOM.b, 0.6), NO_LINE)
	r.fill([E(64, 70, 4, 2.4)], Color(Palette.BLOSSOM.r, Palette.BLOSSOM.g, Palette.BLOSSOM.b, 0.6), NO_LINE)
	for p in [[16, 58, 2.0], [80, 64, 2.4], [74, 20, 1.8], [22, 16, 1.6]]:
		r.fill([C(float(p[0]), float(p[1]), float(p[2]))], Color("fff4c8"), NO_LINE)


# --- Flat glyphs for the theme (design height 48) -------------------------------------------------

static func _draw_glyph(r: Raster, kind: String, color: Color) -> void:
	var ink := INK
	var paper := Palette.UI_PAPER
	var accent := Palette.UI_ACCENT if color == Color.WHITE else color
	var line := {"o": 2.4, "back": false, "shade": 0.06}
	var aw := float(r.w) / r.s     # design width
	var cx := aw * 0.5
	match kind:
		"box_off":
			r.fill([B(cx, 24, 17, 17, 6)], paper.darkened(0.03), line)
		"box_on":
			r.fill([B(cx, 24, 17, 17, 6)], accent, line)
			r.fill([L([Vector2(cx - 8, 24), Vector2(cx - 2, 30), Vector2(cx + 9, 17)], 3.2)], Color.WHITE, NO_LINE)
		"radio_off":
			r.fill([C(cx, 24, 16)], paper.darkened(0.03), line)
		"radio_on":
			r.fill([C(cx, 24, 16)], paper.darkened(0.03), line)
			r.fill([C(cx, 24, 8)], accent, NO_LINE)
		"switch_off":
			r.fill([B(cx, 24, aw * 0.5 - 4, 16, 16)], Palette.UI_PAPER_DARK.darkened(0.08), line)
			r.fill([C(cx - aw * 0.5 + 20, 24, 12)], paper.lightened(0.3), line)
		"switch_on":
			r.fill([B(cx, 24, aw * 0.5 - 4, 16, 16)], Palette.UI_GOOD, line)
			r.fill([C(cx + aw * 0.5 - 20, 24, 12)], paper.lightened(0.3), line)
		"knob":
			r.fill([C(cx, 24, 17)], paper.lightened(0.3), line)
			r.fill([C(cx, 24, 7)], accent, NO_LINE)
		"knob_hot":
			r.fill([C(cx, 24, 19)], paper.lightened(0.4), {"o": 3.0, "back": false, "shade": 0.06, "ink": accent.darkened(0.2)})
			r.fill([C(cx, 24, 8)], accent, NO_LINE)
		"arrow_down":
			r.fill([L([Vector2(cx - 9, 19), Vector2(cx, 29), Vector2(cx + 9, 19)], 3.4)], color if color != Color.WHITE else ink, NO_LINE)
		"arrow_right":
			r.fill([L([Vector2(cx - 5, 14), Vector2(cx + 5, 24), Vector2(cx - 5, 34)], 3.4)], color if color != Color.WHITE else ink, NO_LINE)
		"close":
			r.fill([L([Vector2(cx - 9, 15), Vector2(cx + 9, 33)], 3.6), L([Vector2(cx + 9, 15), Vector2(cx - 9, 33)], 3.6)], color if color != Color.WHITE else ink, NO_LINE)
		"dot":
			r.fill([C(cx, 24, 10)], accent, line)
		"diamond":
			r.fill([P([Vector2(cx, 12), Vector2(cx + 12, 24), Vector2(cx, 36), Vector2(cx - 12, 24)], 1.5)], accent, NO_LINE)
		"leaf":
			r.fill([E(cx, 24, aw * 0.42, 9, -18)], accent, {"o": 0.0, "back": false, "shade": 0.1})
			r.fill([L([Vector2(cx - aw * 0.36, 28), Vector2(cx + aw * 0.36, 20)], 1.2)], accent.darkened(0.3), NO_LINE)
		_:
			r.fill([C(cx, 24, 12)], accent, line)


# --- Rasteriser ----------------------------------------------------------------------------------

## Tiny CPU rasteriser: shapes are signed distance fields; each fill composites over the canvas with
## an ink outline, top-lit shading and (for stickers) contributes to a cream backing + drop shadow.
class Raster extends RefCounted:
	const RINK := Color("3b2f35")
	const RBACK := Color("fffaf0")
	const OUTLINE_W := 3.0
	const BORDER_W := 4.0

	var w: int
	var h: int
	var s: float
	var sticker: bool
	var col := PackedFloat32Array()
	var back := PackedFloat32Array()

	func _init(p_w: int, p_h: int, p_scale: float, p_sticker: bool) -> void:
		w = p_w
		h = p_h
		s = p_scale
		sticker = p_sticker
		col.resize(w * h * 4)
		col.fill(0.0)
		back.resize(w * h)
		back.fill(0.0)

	## Fills the union of `parts` (minus parts marked cut). Options:
	##   o: outline width (design units, default 3; 0 = none)   back: contributes to the sticker backing
	##   alpha: opacity   shade: top-lit gradient amount   soft: soft edge width (glows)   ink: outline colour
	func fill(parts: Array, color: Color, o: Dictionary = {}) -> void:
		var ow_d: float = float(o.get("o", OUTLINE_W))
		var use_back: bool = sticker and bool(o.get("back", true))
		var alpha: float = float(o.get("alpha", 1.0)) * color.a
		var shade: float = float(o.get("shade", 0.12))
		var soft: float = float(o.get("soft", 0.0)) * s
		var ink: Color = o.get("ink", RINK.lerp(color.darkened(0.6), 0.3))
		var bb := Rect2()
		var first := true
		for p in parts:
			if p.get("cut", false):
				continue
			var rb := _bounds(p)
			bb = rb if first else bb.merge(rb)
			first = false
		if first:
			return
		var ext := ow_d + (BORDER_W if use_back else 0.0) + 2.0 + float(o.get("soft", 0.0))
		var gb := bb.grow(ext)
		var x0 := clampi(int(floor(gb.position.x * s)), 0, w)
		var y0 := clampi(int(floor(gb.position.y * s)), 0, h)
		var x1 := clampi(int(ceil(gb.end.x * s)), 0, w)
		var y1 := clampi(int(ceil(gb.end.y * s)), 0, h)
		var bw := x1 - x0
		var bh := y1 - y0
		if bw <= 0 or bh <= 0:
			return
		var f := PackedFloat32Array()
		f.resize(bw * bh)
		var have := false
		var g := PackedFloat32Array()
		g.resize(bw * bh)
		# union first, then cuts
		for pass_cut in [false, true]:
			for p in parts:
				if bool(p.get("cut", false)) != pass_cut:
					continue
				if not have:
					_dist(p, f, x0, y0, bw, bh)
					have = true
					continue
				_dist(p, g, x0, y0, bw, bh)
				if pass_cut:
					for i in f.size():
						f[i] = maxf(f[i], -g[i])
				else:
					for i in f.size():
						f[i] = minf(f[i], g[i])
		var ow := ow_d * s
		var bwid := (ow_d + BORDER_W) * s
		var cr0 := color.r
		var cg0 := color.g
		var cb0 := color.b
		var ir := ink.r
		var ig := ink.g
		var ib := ink.b
		var ytop := bb.position.y * s
		var yh := maxf(bb.size.y * s, 1.0)
		var i := 0
		for yy in bh:
			var y := y0 + yy
			var t := clampf((float(y) + 0.5 - ytop) / yh, 0.0, 1.0)
			var m := 1.0 + shade * (1.0 - 2.0 * t)
			var cr := clampf(cr0 * m, 0.0, 1.0)
			var cg := clampf(cg0 * m, 0.0, 1.0)
			var cb := clampf(cb0 * m, 0.0, 1.0)
			var row := y * w + x0
			for xx in bw:
				var d: float = f[i]
				i += 1
				var pix := row + xx
				if use_back:
					var bc := clampf(0.5 - (d - bwid), 0.0, 1.0)
					if bc > back[pix]:
						back[pix] = bc
				var a: float
				if soft > 0.0:
					a = clampf(0.5 - d / soft, 0.0, 1.0)
					a = a * a * (3.0 - 2.0 * a)
				else:
					a = clampf(0.5 - (d - ow), 0.0, 1.0)
				if a <= 0.0:
					continue
				var r := cr
				var gg := cg
				var b := cb
				if ow > 0.0:
					var mf := clampf(0.5 - d, 0.0, 1.0)
					r = ir + (cr - ir) * mf
					gg = ig + (cg - ig) * mf
					b = ib + (cb - ib) * mf
				a *= alpha
				var k := pix * 4
				var inv := 1.0 - a
				col[k] = r * a + col[k] * inv
				col[k + 1] = gg * a + col[k + 1] * inv
				col[k + 2] = b * a + col[k + 2] * inv
				col[k + 3] = a + col[k + 3] * inv

	func _bounds(p: Dictionary) -> Rect2:
		match int(p["k"]):
			0:
				var rr: float = p["r"]
				return Rect2(float(p["x"]) - rr, float(p["y"]) - rr, rr * 2.0, rr * 2.0)
			1:
				var rx: float = p["rx"]
				var ry: float = p["ry"]
				if absf(float(p["rot"])) > 0.001:
					var m := maxf(rx, ry)
					rx = m
					ry = m
				return Rect2(float(p["x"]) - rx, float(p["y"]) - ry, rx * 2.0, ry * 2.0)
			2:
				var hw: float = p["hw"]
				var hh: float = p["hh"]
				if absf(float(p["rot"])) > 0.001:
					var m := sqrt(hw * hw + hh * hh)
					hw = m
					hh = m
				return Rect2(float(p["x"]) - hw, float(p["y"]) - hh, hw * 2.0, hh * 2.0)
			3:
				var pts: PackedVector2Array = p["p"]
				var rads: PackedFloat32Array = p["r"]
				var mr := 0.0
				for v in rads:
					mr = maxf(mr, v)
				var rb := Rect2(pts[0], Vector2.ZERO)
				for v in pts:
					rb = rb.expand(v)
				return rb.grow(mr)
			4:
				var pts2: PackedVector2Array = p["p"]
				var rb2 := Rect2(pts2[0], Vector2.ZERO)
				for v in pts2:
					rb2 = rb2.expand(v)
				return rb2.grow(float(p["rnd"]))
			5:
				var e: float = float(p["r"]) + float(p["t"]) * 0.5
				return Rect2(float(p["x"]) - e, float(p["y"]) - e, e * 2.0, e * 2.0)
		return Rect2()

	## Writes signed distances (in pixels) of part `p` for the pixel block into `g`.
	func _dist(p: Dictionary, g: PackedFloat32Array, x0: int, y0: int, bw: int, bh: int) -> void:
		var inv := 1.0 / s
		var i := 0
		match int(p["k"]):
			0:
				var cx: float = p["x"]
				var cy: float = p["y"]
				var rr: float = p["r"]
				for yy in bh:
					var dy := (float(y0 + yy) + 0.5) * inv - cy
					var dy2 := dy * dy
					for xx in bw:
						var dx := (float(x0 + xx) + 0.5) * inv - cx
						g[i] = (sqrt(dx * dx + dy2) - rr) * s
						i += 1
			1:
				var cx: float = p["x"]
				var cy: float = p["y"]
				var rx: float = p["rx"]
				var ry: float = p["ry"]
				var ca := cos(-float(p["rot"]))
				var sa := sin(-float(p["rot"]))
				var mn := minf(rx, ry)
				for yy in bh:
					var dy := (float(y0 + yy) + 0.5) * inv - cy
					for xx in bw:
						var dx := (float(x0 + xx) + 0.5) * inv - cx
						var lx := dx * ca - dy * sa
						var ly := dx * sa + dy * ca
						var nx := lx / rx
						var ny := ly / ry
						var kk := sqrt(nx * nx + ny * ny)
						var gx := nx / rx
						var gy := ny / ry
						var gl := sqrt(gx * gx + gy * gy)
						var d := -mn
						if gl > 0.00001:
							d = kk * (kk - 1.0) / gl
							if d < -mn:
								d = -mn
						g[i] = d * s
						i += 1
			2:
				var cx: float = p["x"]
				var cy: float = p["y"]
				var hw: float = p["hw"]
				var hh: float = p["hh"]
				var rad: float = p["rad"]
				var ca := cos(-float(p["rot"]))
				var sa := sin(-float(p["rot"]))
				for yy in bh:
					var dy := (float(y0 + yy) + 0.5) * inv - cy
					for xx in bw:
						var dx := (float(x0 + xx) + 0.5) * inv - cx
						var qx := absf(dx * ca - dy * sa) - hw + rad
						var qy := absf(dx * sa + dy * ca) - hh + rad
						var ox := maxf(qx, 0.0)
						var oy := maxf(qy, 0.0)
						g[i] = (sqrt(ox * ox + oy * oy) + minf(maxf(qx, qy), 0.0) - rad) * s
						i += 1
			3:
				var pts: PackedVector2Array = p["p"]
				var rads: PackedFloat32Array = p["r"]
				var n := pts.size()
				if n == 1:
					pts.append(pts[0])
					rads.append(rads[0])
					n = 2
				var ax := PackedFloat32Array()
				var ay := PackedFloat32Array()
				var ex := PackedFloat32Array()
				var ey := PackedFloat32Array()
				var l2 := PackedFloat32Array()
				var ra := PackedFloat32Array()
				var dr := PackedFloat32Array()
				for j in n - 1:
					ax.append(pts[j].x)
					ay.append(pts[j].y)
					ex.append(pts[j + 1].x - pts[j].x)
					ey.append(pts[j + 1].y - pts[j].y)
					l2.append(maxf(ex[j] * ex[j] + ey[j] * ey[j], 0.0001))
					ra.append(rads[j])
					dr.append(rads[j + 1] - rads[j])
				var segs := n - 1
				for yy in bh:
					var py := (float(y0 + yy) + 0.5) * inv
					for xx in bw:
						var px := (float(x0 + xx) + 0.5) * inv
						var best := 1e9
						for j in segs:
							var wx := px - ax[j]
							var wy := py - ay[j]
							var t := clampf((wx * ex[j] + wy * ey[j]) / l2[j], 0.0, 1.0)
							var qx := wx - ex[j] * t
							var qy := wy - ey[j] * t
							var d := sqrt(qx * qx + qy * qy) - (ra[j] + dr[j] * t)
							if d < best:
								best = d
						g[i] = best * s
						i += 1
			4:
				var pts: PackedVector2Array = p["p"]
				var rnd: float = p["rnd"]
				var n := pts.size()
				for yy in bh:
					var py := (float(y0 + yy) + 0.5) * inv
					for xx in bw:
						var px := (float(x0 + xx) + 0.5) * inv
						var dx0 := px - pts[0].x
						var dy0 := py - pts[0].y
						var d := dx0 * dx0 + dy0 * dy0
						var sgn := 1.0
						var j := n - 1
						for k in n:
							var vi: Vector2 = pts[k]
							var vj: Vector2 = pts[j]
							var ex := vj.x - vi.x
							var ey := vj.y - vi.y
							var wx := px - vi.x
							var wy := py - vi.y
							var t := clampf((wx * ex + wy * ey) / maxf(ex * ex + ey * ey, 0.0001), 0.0, 1.0)
							var bx := wx - ex * t
							var by := wy - ey * t
							d = minf(d, bx * bx + by * by)
							var c1 := py >= vi.y
							var c2 := py < vj.y
							var c3 := ex * wy > ey * wx
							if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
								sgn = -sgn
							j = k
						g[i] = (sgn * sqrt(d) - rnd) * s
						i += 1
			5:
				var cx: float = p["x"]
				var cy: float = p["y"]
				var rr: float = p["r"]
				var ht: float = float(p["t"]) * 0.5
				for yy in bh:
					var dy := (float(y0 + yy) + 0.5) * inv - cy
					for xx in bw:
						var dx := (float(x0 + xx) + 0.5) * inv - cx
						g[i] = (absf(sqrt(dx * dx + dy * dy) - rr) - ht) * s
						i += 1

	## Final composite: drop shadow + cream backing (stickers) under the drawn shapes.
	func to_image(with_backing: bool) -> Image:
		var bytes := PackedByteArray()
		bytes.resize(w * h * 4)
		var off := maxi(1, int(round(3.0 * s)))
		var sr := RINK.r
		var sg := RINK.g
		var sb := RINK.b
		var br := RBACK.r
		var bg := RBACK.g
		var bb := RBACK.b
		for y in h:
			for x in w:
				var pix := y * w + x
				var k := pix * 4
				var r := 0.0
				var g := 0.0
				var b := 0.0
				var a := 0.0
				if with_backing:
					var sy := y - off
					var sh := 0.0
					if sy >= 1 and sy < h - 1:
						sh = (back[(sy - 1) * w + x] + back[sy * w + x] * 2.0 + back[(sy + 1) * w + x]) * 0.25
					a = sh * 0.24
					r = sr * a
					g = sg * a
					b = sb * a
					var bc: float = back[pix]
					if bc > 0.0:
						var ib := 1.0 - bc
						r = br * bc + r * ib
						g = bg * bc + g * ib
						b = bb * bc + b * ib
						a = bc + a * ib
				var ma: float = col[k + 3]
				if ma > 0.0:
					var im := 1.0 - ma
					r = col[k] + r * im
					g = col[k + 1] + g * im
					b = col[k + 2] + b * im
					a = ma + a * im
				if a > 0.0001:
					r /= a
					g /= a
					b /= a
				bytes[k] = int(clampf(r, 0.0, 1.0) * 255.0 + 0.5)
				bytes[k + 1] = int(clampf(g, 0.0, 1.0) * 255.0 + 0.5)
				bytes[k + 2] = int(clampf(b, 0.0, 1.0) * 255.0 + 0.5)
				bytes[k + 3] = int(clampf(a, 0.0, 1.0) * 255.0 + 0.5)
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
