extends RefCounted
## Recolouring placed pieces (Chapter Two, MP §3): a tintable piece can be dyed with any dye palette Krystal
## has made at the Loom (GameState.wardrobe.palettes; ids of data/appearance.gd DYE_PALETTES), or turned back
## to its natural wood. The choice is saved as structures[uid].data.tint (a palette id; absent = natural), the
## uid, position and chest contents never change, and nothing is ever recoloured automatically.
## Tinting is a vertex-colour remap of the piece's baked meshes (hue and saturation move toward the dye,
## brightness keeps the plank and shading variation; greys, whites and glass stay as they are). Tinted meshes
## are cached per (mesh, palette), so every copy of a dyed piece shares one mesh.

const AppearanceData := preload("res://data/appearance.gd")

## Legacy pieces that may be recoloured too (their data entries stay untouched; new pieces say `tintable`).
const LEGACY_TINTABLE := ["wood_floor", "wood_wall", "wood_window", "wood_doorway", "wood_roof", "fence", "table",
	"stool", "rug", "bed", "storage_chest", "workbench", "lantern_post", "haven_banner"]
const NATURAL := ""
const UNTINTED_META := "untinted_mesh"

static var _mesh_cache: Dictionary = {}


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


## Applies `tint_id` to every vertex-coloured mesh under `root` (NATURAL restores the originals).
static func apply(root: Node, tint_id: String) -> void:
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
				mi.mesh = tinted_mesh(original as ArrayMesh, tint_id)
	for c in root.get_children():
		apply(c, tint_id)


static func _has_colors(m: ArrayMesh) -> bool:
	return m.get_surface_count() > 0 and (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0


## Cached copy of a baked mesh with its vertex colours dyed toward the palette.
static func tinted_mesh(mesh: ArrayMesh, tint_id: String) -> ArrayMesh:
	var key := "%d|%s" % [mesh.get_instance_id(), tint_id]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out := ArrayMesh.new()
	var t := color_of(tint_id)
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var cols: Variant = arr[Mesh.ARRAY_COLOR]
		if cols is PackedColorArray:
			var pc: PackedColorArray = (cols as PackedColorArray).duplicate()
			for i in pc.size():
				pc[i] = dye(pc[i].linear_to_srgb(), t).srgb_to_linear()
			arr[Mesh.ARRAY_COLOR] = pc
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arr)
	_mesh_cache[key] = out
	return out


## One colour (sRGB) dyed toward `t` (sRGB): hue follows the dye, saturation blends, brightness keeps the
## original variation scaled toward the dye's value. Near-grey colours (stone, glass, white trim) barely move.
static func dye(c: Color, t: Color) -> Color:
	var w := 0.85 * smoothstep(0.08, 0.28, c.s)
	if w <= 0.001:
		return c
	var sat := clampf(c.s * 0.35 + t.s * 0.65, 0.0, 1.0)
	var val := clampf(c.v * lerpf(1.0, t.v / 0.85, 0.6), 0.0, 1.0)
	var target := Color.from_hsv(t.h, sat, val, c.a)
	return c.lerp(target, w)
