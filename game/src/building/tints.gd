extends RefCounted
## Recolouring placed pieces (Chapter Two, MP §3): a tintable piece can be dyed with any dye palette Krystal
## has made at the Loom (GameState.wardrobe.palettes; ids of data/appearance.gd DYE_PALETTES), or turned back
## to its natural wood. The choice is saved as structures[uid].data.tint (a palette id; absent = natural), the
## uid, position and chest contents never change, and nothing is ever recoloured automatically.
## Tinting is a vertex-colour remap of the piece's baked meshes (hue and saturation move toward the dye,
## brightness keeps the plank and shading variation; greys, whites and glass stay as they are). Tinted meshes
## are cached per (mesh, palette), so every copy of a dyed piece shares one mesh.
## Only the piece's own colour family is dyed (dye_family): the wood/thatch family when enough of its coloured
## surface is wood, else its main colour (curtain cloth, bunting bats, trim paint). Accents in other hues (books,
## quilt patches, flowers, the kettle) keep their colours, and colours flagged keep() (brass and gold fittings,
## book spines: vertex alpha KEEP_ALPHA, which the toon shader never reads) are never dyed.

const AppearanceData := preload("res://data/appearance.gd")

## Legacy pieces that may be recoloured too (their data entries stay untouched; new pieces say `tintable`).
const LEGACY_TINTABLE := ["wood_floor", "wood_wall", "wood_window", "wood_doorway", "wood_roof", "fence", "table",
	"stool", "rug", "bed", "storage_chest", "workbench", "lantern_post", "haven_banner"]
const NATURAL := ""
const UNTINTED_META := "untinted_mesh"
const KEEP_ALPHA := 0.9               # vertex alpha of "keep natural" colours (see keep())
const WOOD_HUE := 29.0                # wood / thatch family centre (degrees): bark 21, planks 26-32, thatch 38
const WOOD_SHARE := 0.25              # at least this share of the coloured surface in the wood band = a wood piece
const WOOD_BAND := Vector2(10.0, 16.0)   # dyed fully within 10 deg of the family hue, fading out by 16 deg
const MAIN_BAND := Vector2(14.0, 26.0)   # same for pieces dyed by their own main colour

static var _mesh_cache: Dictionary = {}
static var _family_cache: Dictionary = {}


## A colour that is never dyed (metal fittings, book spines, patchwork): bake it with this.
static func keep(c: Color) -> Color:
	return Color(c.r, c.g, c.b, KEEP_ALPHA)


static func is_kept(c: Color) -> bool:
	return c.a < 0.99


static func is_tintable(structure_id: String) -> bool:
	return bool(ItemDB.structure(structure_id).get("tintable", false)) or LEGACY_TINTABLE.has(structure_id)


## Every dye palette id, in the catalogue's order.
static func palette_ids() -> Array:
	return AppearanceData.DYE_PALETTES.keys()


static func is_palette(tint_id: String) -> bool:
	return AppearanceData.DYE_PALETTES.has(tint_id)


## Palettes Krystal owns (made at the Loom), in catalogue order.
static func owned_palettes() -> Array:
	var have: Variant = GameState.wardrobe.get("palettes", [])
	var out: Array = []
	if have is Array:
		for id in palette_ids():
			if (have as Array).has(id):
				out.append(id)
	return out


## Choices for a piece: natural first, then every owned palette ([] if the piece can't be recoloured).
static func options_for(structure_id: String) -> Array:
	if not is_tintable(structure_id):
		return []
	var out: Array = [NATURAL]
	out.append_array(owned_palettes())
	return out


static func color_of(tint_id: String) -> Color:
	return ItemDB.dye_palette(tint_id).get("tint", Color.WHITE)


static func display_name(tint_id: String) -> String:
	if tint_id == NATURAL:
		return "Natural"
	return String(ItemDB.dye_palette(tint_id).get("name", tint_id)).trim_suffix(" Dye")


## Saved tint of a record ("" = natural; unknown ids count as natural and are left in the save untouched).
static func tint_of(rec: Dictionary) -> String:
	var data: Variant = rec.get("data", {})
	if data is Dictionary:
		var t := String((data as Dictionary).get("tint", NATURAL))
		return t if is_palette(t) else NATURAL
	return NATURAL


## Applies `tint_id` to every vertex-coloured mesh under `root` (NATURAL restores the originals). `family`:
## "" picks the colour family from the mesh (dye_family), "main" always dyes the piece's main colour (data
## `tint_family`, e.g. a companion bed whose cushion is what you see).
static func apply(root: Node, tint_id: String, family: String = "") -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var original: Variant = mi.get_meta(UNTINTED_META) if mi.has_meta(UNTINTED_META) else mi.mesh
		if original is ArrayMesh and _has_colors(original as ArrayMesh):
			if tint_id == NATURAL or not is_palette(tint_id):
				mi.mesh = original
			else:
				if not mi.has_meta(UNTINTED_META):
					mi.set_meta(UNTINTED_META, original)
				mi.mesh = tinted_mesh(original as ArrayMesh, tint_id, family)
	for c in root.get_children():
		apply(c, tint_id, family)


static func _has_colors(m: ArrayMesh) -> bool:
	return m.get_surface_count() > 0 and (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0


## Cached copy of a baked mesh with its vertex colours dyed toward the palette.
static func tinted_mesh(mesh: ArrayMesh, tint_id: String, family: String = "") -> ArrayMesh:
	var key := "%d|%s|%s" % [mesh.get_instance_id(), tint_id, family]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out := ArrayMesh.new()
	var t := color_of(tint_id)
	var fam := dye_family(mesh, family == "main")
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var cols: Variant = arr[Mesh.ARRAY_COLOR]
		if cols is PackedColorArray:
			var pc: PackedColorArray = (cols as PackedColorArray).duplicate()
			for i in pc.size():
				var s0 := pc[i].linear_to_srgb()
				var d := dye(s0, t, fam)
				if d != s0:
					pc[i] = d.srgb_to_linear()       # colours the dye leaves alone stay bit-identical
			arr[Mesh.ARRAY_COLOR] = pc
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arr)
	_mesh_cache[key] = out
	return out


## The colour family a mesh is dyed by: {"hue": degrees, "band": Vector2(full, fade) degrees}. Coloured surface
## area per 10 deg hue bin (triangle area x saturation weight, kept colours skipped); the wood family when at least
## WOOD_SHARE of it is within 16 deg of WOOD_HUE, else the busiest bin (with its neighbours). Cached per mesh.
static func dye_family(mesh: ArrayMesh, main_only: bool = false) -> Dictionary:
	var key := "%d|%s" % [mesh.get_instance_id(), main_only]
	if _family_cache.has(key):
		return _family_cache[key]
	var bins := PackedFloat32Array()
	bins.resize(36)
	var total := 0.0
	var wood := 0.0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var cols: Variant = arr[Mesh.ARRAY_COLOR]
		if not (cols is PackedColorArray):
			continue
		var pc: PackedColorArray = cols
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := ix.size() if not ix.is_empty() else v.size()
		for t in range(0, n - 2, 3):
			var a := ix[t] if not ix.is_empty() else t
			var c := pc[a]
			if is_kept(c):
				continue
			var cs := c.linear_to_srgb()
			var wt := smoothstep(0.08, 0.28, cs.s)
			if wt <= 0.0:
				continue
			var b := ix[t + 1] if not ix.is_empty() else t + 1
			var d := ix[t + 2] if not ix.is_empty() else t + 2
			var area := (v[b] - v[a]).cross(v[d] - v[a]).length() * 0.5 * wt
			var hue := cs.h * 360.0
			bins[int(hue / 10.0) % 36] += area
			total += area
			if _hue_dist(hue, WOOD_HUE) <= WOOD_BAND.y:
				wood += area
	var fam := {"hue": WOOD_HUE, "band": WOOD_BAND}
	if total > 0.0 and (main_only or wood < total * WOOD_SHARE):
		var best := 0
		var best_w := -1.0
		for i in 36:
			var w3 := bins[i] + 0.5 * (bins[(i + 35) % 36] + bins[(i + 1) % 36])
			if w3 > best_w:
				best_w = w3
				best = i
		fam = {"hue": float(best) * 10.0 + 5.0, "band": MAIN_BAND}
	_family_cache[key] = fam
	return fam


static func _hue_dist(a: float, b: float) -> float:
	var d := absf(fposmod(a - b, 360.0))
	return minf(d, 360.0 - d)


## One colour (sRGB) dyed toward `t` (sRGB): hue follows the dye, saturation blends, brightness keeps the
## original variation scaled toward the dye's value. Near-grey colours (stone, glass, white trim) barely move,
## kept colours never do, and with a `family` (dye_family) only hues near the piece's own colour family move.
static func dye(c: Color, t: Color, family: Dictionary = {}) -> Color:
	if is_kept(c):
		return c
	var w := 0.85 * smoothstep(0.08, 0.28, c.s)
	if not family.is_empty():
		var band: Vector2 = family["band"]
		w *= 1.0 - smoothstep(band.x, band.y, _hue_dist(c.h * 360.0, float(family["hue"])))
	if w <= 0.001:
		return c
	var sat := clampf(c.s * 0.35 + t.s * 0.65, 0.0, 1.0)
	var val := clampf(c.v * lerpf(1.0, t.v / 0.85, 0.6), 0.0, 1.0)
	var target := Color.from_hsv(t.h, sat, val, c.a)
	return c.lerp(target, w)
