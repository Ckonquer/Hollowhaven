extends RefCounted
## Material + node helpers for structure models. Most props are built as a Batch (batch.gd) of
## primitive parts baked into ONE vertex-coloured ArrayMesh (one draw call, shared by every copy of that
## structure), rendered with the project toon shader (Mat.toon with vertex_color).

const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")
const Batch := preload("res://src/building/batch.gd")

static var _cache: Dictionary = {}


# --- Materials -----------------------------------------------------------------------------------

## Vertex-coloured toon material (shared).
static func vc_mat(opts: Dictionary = {}) -> Material:
	var o := {"vertex_color": true}
	o.merge(opts, true)
	return Mat.toon(Color.WHITE, o)


## Vertex-coloured toon + storybook outline (key props).
static func vc_outlined(thickness: float = 0.014, opts: Dictionary = {}) -> Material:
	return Mat.outlined(vc_mat(opts), thickness)


## Translucent ghost material for build previews.
static func ghost_mat(valid: bool) -> Material:
	var key := "ghost|%s" % valid
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Valid = cool mint (reads against the yellow-green Haven grass), invalid = soft coral red.
	m.albedo_color = Color(0.62, 1.0, 0.86, 0.5) if valid else Color(1.0, 0.45, 0.42, 0.5)
	m.emission_enabled = true
	m.emission = Color(0.42, 1.0, 0.78) if valid else Color(1.0, 0.32, 0.3)
	m.emission_energy_multiplier = 0.6 if valid else 0.45
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.shadow_to_opacity = false
	_cache[key] = m
	return m


## Overlay used to highlight the structure that X would dismantle.
static func highlight_mat() -> Material:
	if _cache.has("highlight"):
		return _cache["highlight"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.42, 0.36, 0.38)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_cache["highlight"] = m
	return m


## Self-lit sparkle for billboard particles (particles fade in/out through their scale curve).
static func sparkle_mat(color: Color) -> Material:
	var key := "sparkle|%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Transparent glass (window panes).
static func glass_mat() -> Material:
	if _cache.has("glass"):
		return _cache["glass"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Palette.WATER.r, Palette.WATER.g, Palette.WATER.b, 0.38)
	m.roughness = 0.15
	m.metallic_specular = 0.8
	m.emission_enabled = true
	m.emission = Palette.LANTERN_GLOW
	m.emission_energy_multiplier = 0.12
	_cache["glass"] = m
	return m


# --- MeshInstance helpers ------------------------------------------------------------------------

static func instance(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi


static func pivot(parent: Node3D, pos: Vector3, name: String = "") -> Node3D:
	var n := Node3D.new()
	if name != "":
		n.name = name
	parent.add_child(n)
	n.position = pos
	return n


## Cached baked mesh: builder(batch) fills a Batch the first time `key` is requested.
static func baked(key: String, builder: Callable) -> ArrayMesh:
	var k := "baked|" + key
	if _cache.has(k):
		return _cache[k]
	var b := Batch.new()
	builder.call(b)
	var m := b.bake()
	_cache[k] = m
	return m
