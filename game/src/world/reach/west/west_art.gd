extends RefCounted
## Storybook art for the Reach west districts (Pumpkintide Orchard, Thimblebrook Pools, The Candleyard).
## Every mesh is merged (NodeVisuals.Merger), vertex-coloured and cached by its parameters, so repeated props
## share geometry (use them in MultiMeshes); materials come from Mat / NodeVisuals caches or are cached here.
## Soft, rounded, chunky silhouettes; palette: amber / pumpkin / plum for the orchard, silver-teal for the
## pools, lilac stone + violet candle light for the Candleyard. No external assets.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")

const PUMPKIN := Color("f08a2e")
const PUMPKIN_DEEP := Color("c9571f")
const PUMPKIN_PALE := Color("f7b65c")
const MIMIC := Color("d9682c")
const MIMIC_DEEP := Color("7e3319")
const STEM := Color("6e7a3a")
const VINE := Color("5f8f45")
const VINE_DARK := Color("3f6a36")
const STRAW := Color("e2b560")
const STRAW_DARK := Color("b58a3e")
const FENCE := Color("8a6246")
const FENCE_DARK := Color("5e4030")
const AMBER := Color("e8a23e")
const PLUM := Color("5a3f5c")
const RIBBON_RED := Color("e0604e")
const RIBBON_PLUM := Color("a466c0")
const RIBBON_CREAM := Color("f6e9cc")
const RIBBON_GOLD := Color("f2c14e")
const LILAC_STONE := Color("aa9dbd")
const VIOLET := Color("9b7fe0")
const VIOLET_FLAME := Color("c7a9ff")
const MOONFLOWER := Color("f3eeff")
const MOONPETAL := Color("a9b8f2")
const SUGARCAP := Color("f5b8d0")
const ROSEBERRY := Color("e0607e")
const REED := Color("7f9f55")
const REED_TIP := Color("8a5a3c")
const LILY := Color("6fae6a")
const SOIL := Color("6e4a30")
const SOIL_DRY := Color("b89468")
const SHED_PLANK := Color("7a5a78")
const HAT_PURPLE := Color("5b3b78")
const IRON := Color("3d3440")
const WARM_GLOW := Color("ffc070")

static var _cache: Dictionary = {}


# --- Materials -------------------------------------------------------------------------------------------

## Vertex-coloured toon + outline: every chunky prop.
static func prop_material() -> Material:
	return NV.rock_material(0.02)


## Vertex-coloured toon without an outline: small, numerous decor (leaves, candles, reeds' friends).
static func soft_material() -> Material:
	return NV.rock_material(0.0)


## Swaying vertex-coloured foliage (reeds, vine leaves, hedges).
static func sway_material(wind: float = 0.05, height: float = 1.2) -> Material:
	return NV.foliage_material(wind, height, 0.018, 0.2)


## A fluttering ribbon: vertices sway more the higher they are above the knot (toon wind).
static func ribbon_material(color: Color) -> Material:
	return Mat.toon(color, {"wind": 0.16, "wind_height": 0.55, "wind_speed": 2.4, "rim": 0.35})


## Glossy berries (roseberries) with a thin outline.
static func berry_material() -> Material:
	return Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.55, "specular": 0.6}), 0.012)


static func glow(color: Color, energy: float = 2.0) -> Material:
	return Mat.glow(color, energy)


static func tinted(color: Color, emission: float = 0.0, rim: float = 0.3) -> Material:
	if emission > 0.0:
		return Mat.toon(color, {"emission": color, "emission_energy": emission, "rim": rim})
	return Mat.toon(color, {"rim": rim})


## Glossy amber puddle (rain on autumn soil).
static func puddle_material() -> Material:
	return Mat.toon(AMBER.lerp(Color("c97a2a"), 0.3), {"specular": 0.95, "emission": AMBER, "emission_energy": 0.12, "rim": 0.6, "noise": 0.02})


## Flowing water: stripes drift downstream (UV.y = metres along the flow), so the direction reads with the
## sound muted. Transparent, unshadowed, a little emissive so it stays readable at dusk.
static func flow_material() -> ShaderMaterial:
	if _cache.has("mat_flow"):
		return _cache["mat_flow"]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.46, 0.79, 0.87, 0.82);
uniform vec4 foam_color : source_color = vec4(0.93, 0.98, 1.0, 1.0);
uniform float flow_speed = 0.9;
uniform float stripes = 1.6;
void fragment() {
	float s = fract(UV.y * stripes - TIME * flow_speed);
	float band = smoothstep(0.0, 0.1, s) * (1.0 - smoothstep(0.1, 0.34, s));
	float edge = smoothstep(0.32, 0.5, abs(UV.x - 0.5));
	vec3 c = mix(base_color.rgb, foam_color.rgb, clamp(band * 0.55 + edge * 0.35, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = base_color.a;
	EMISSION = c * 0.22;
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache["mat_flow"] = m
	return m


## Still, sparkling shallow pool water (slow shimmer rings, never a strobe).
static func pool_material() -> ShaderMaterial:
	if _cache.has("mat_pool"):
		return _cache["mat_pool"]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform vec4 shallow : source_color = vec4(0.55, 0.84, 0.88, 0.66);
uniform vec4 deep : source_color = vec4(0.30, 0.60, 0.74, 0.8);
uniform vec4 glint : source_color = vec4(1.0, 0.98, 0.9, 1.0);
void fragment() {
	float r = UV.x;
	vec3 c = mix(deep.rgb, shallow.rgb, smoothstep(0.35, 1.0, r));
	float ripple = sin(r * 26.0 - TIME * 1.1) * 0.5 + 0.5;
	float sparkle = pow(ripple, 18.0) * (1.0 - r * 0.6);
	c = mix(c, glint.rgb, sparkle * 0.45);
	ALBEDO = c;
	ALPHA = mix(deep.a, shallow.a, r);
	EMISSION = c * 0.14 + glint.rgb * sparkle * 0.25;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache["mat_pool"] = m
	return m


## Tiny twinkling glints (MultiMesh): each instance breathes at its own phase; soft, no hard flashing.
static func glint_material() -> ShaderMaterial:
	if _cache.has("mat_glint"):
		return _cache["mat_glint"]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
varying float phase;
void vertex() {
	phase = float(INSTANCE_ID) * 1.618;
}
void fragment() {
	float a = 0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * 1.7 + phase));
	ALBEDO = color.rgb * a;
	ALPHA = a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache["mat_glint"] = m
	return m


# --- Helpers -----------------------------------------------------------------------------------------

static func _commit(key: String, m: NV.Merger) -> ArrayMesh:
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh


static func _grad(lo: Color, hi: Color, h: float) -> Callable:
	return func(p: Vector3, _n: Vector3) -> Color:
		return lo.lerp(hi, clampf(p.y / maxf(h, 0.01), 0.0, 1.0))


static func _prism(size: Vector3) -> PrismMesh:
	var key := "prism|%s" % size
	if not _cache.has(key):
		var p := PrismMesh.new()
		p.size = size
		_cache[key] = p
	return _cache[key]


static func _torus(inner: float, outer: float) -> TorusMesh:
	var key := "torus|%.3f|%.3f" % [inner, outer]
	if not _cache.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 14
		t.ring_segments = 8
		_cache[key] = t
	return _cache[key]


## Rotation about Y then a LOCAL scale (Basis.scaled() would scale in the parent's axes).
static func rs(yaw: float, scl: Vector3) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis.from_scale(scl)


## Local TRS transform: position, Euler rotation in degrees (YXZ), local scale.
static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b * Basis.from_scale(scl), pos)


# --- Pumpkins ----------------------------------------------------------------------------------------------

## A ribbed pumpkin of radius 1 (base at y = 0) without its stem. lo/hi = bottom/top colours.
static func pumpkin_body(variant: int, lo: Color = PUMPKIN_DEEP, hi: Color = PUMPKIN) -> ArrayMesh:
	var key := "pbody|%d|%s|%s" % [variant, lo.to_html(), hi.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var squash := 0.78 + 0.06 * float(posmod(variant, 3))
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var t := clampf(p.y / (1.5 * squash), 0.0, 1.0)
		var c := lo.lerp(hi, t)
		return c.lerp(hi.lightened(0.18), clampf(n.y, 0.0, 1.0) * 0.25)
	var lobes := 8
	for i in lobes:
		var a := TAU * float(i) / float(lobes) + 0.2 * float(variant)
		var lp := Vector3(cos(a) * 0.42, 0.72 * squash, sin(a) * 0.42)
		var b := rs(-a, Vector3(0.62, 0.72 * squash, 0.5))
		m.add(NV._sph(1.0, 8, 12), Transform3D(b, lp), fn)
	m.add(NV._sph(0.82, 8, 12), Transform3D(Basis().scaled(Vector3(1.0, squash, 1.0)), Vector3(0, 0.72 * squash, 0)), fn)
	return _commit(key, m)


## Height of the top of pumpkin_body(variant) (radius 1): where its stem sits.
static func pumpkin_top(variant: int) -> float:
	return 1.44 * (0.78 + 0.06 * float(posmod(variant, 3))) - 0.04


## A curly stem (pivot at its base) for pumpkins of radius 1: separate so it can twitch.
static func pumpkin_stem(crooked: bool = false) -> ArrayMesh:
	var key := "pstem|%s" % crooked
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var bend := 24.0 if crooked else 10.0
	m.add(NV._cyl(0.09, 0.14, 0.3, 7), xf(Vector3(0, 0.12, 0), Vector3(0, 0, bend)), STEM)
	m.add(NV._cyl(0.06, 0.09, 0.2, 7), xf(Vector3(-0.07 if crooked else -0.03, 0.32, 0), Vector3(0, 0, bend * 2.2)), STEM.darkened(0.15))
	m.add(NV._sph(0.1, 4, 6), Transform3D(Basis().scaled(Vector3(1.6, 0.35, 1.0)), Vector3(0.14, 0.05, 0.06)), VINE)
	return _commit(key, m)


## Carved friendly face (eyes + grin) on the +Z side of a radius-1 pumpkin; use a glow material.
static func carved_face() -> ArrayMesh:
	if _cache.has("face"):
		return _cache["face"]
	var m := NV.Merger.new()
	for sx in [-1.0, 1.0]:
		var p := Vector3(float(sx) * 0.3, 0.86, 0.78)
		m.add(_prism(Vector3(0.22, 0.2, 0.08)), xf(p, Vector3(-8, float(sx) * 18.0, 0)), Color.WHITE)
	for i in 5:
		var t := float(i) / 4.0
		var x := lerpf(-0.36, 0.36, t)
		var y := 0.5 - sin(t * PI) * 0.1
		var z := 0.82 - absf(x) * 0.28
		m.add(NV._box(Vector3(0.15, 0.1 if i % 2 == 0 else 0.07, 0.08)), xf(Vector3(x, y, z), Vector3(-6, x * 40.0, 0)), Color.WHITE)
	return _commit("face", m)


## The mimic's tells: a jagged closed seam of a mouth, sleepy closed eyes and stubby vine feet (radius 1).
static func mimic_details() -> ArrayMesh:
	if _cache.has("mimic_det"):
		return _cache["mimic_det"]
	var m := NV.Merger.new()
	for i in 7:
		var t := float(i) / 6.0
		var x := lerpf(-0.42, 0.42, t)
		var y := 0.5 + (0.05 if i % 2 == 0 else -0.04)
		m.add(NV._box(Vector3(0.14, 0.05, 0.06)), xf(Vector3(x, y, 0.84 - absf(x) * 0.3), Vector3(0, x * 40.0, 35.0 if i % 2 == 0 else -35.0)), MIMIC_DEEP)
	for sx in [-1.0, 1.0]:
		m.add(NV._box(Vector3(0.2, 0.04, 0.05)), xf(Vector3(float(sx) * 0.3, 0.88, 0.76), Vector3(0, float(sx) * 20.0, float(sx) * -12.0)), MIMIC_DEEP)
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		m.add(NV._cyl(0.07, 0.1, 0.28, 6), xf(Vector3(cos(a) * 0.72, 0.06, sin(a) * 0.72), Vector3(0, 0, 70.0)).rotated_local(Vector3.UP, -a), VINE_DARK)
	return _commit("mimic_det", m)


# --- Orchard props -------------------------------------------------------------------------------------------

## Pumpkin vine patch (leaves + curls), base at y = 0, ~1.4 m across. The pumpkin itself is separate.
static func vine_patch(variant: int) -> ArrayMesh:
	var key := "vine|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5100 + variant
	var m := NV.Merger.new()
	for i in 6:
		var a := TAU * float(i) / 6.0 + rng.randf() * 0.5
		var r := rng.randf_range(0.35, 0.6)
		var leaf := Transform3D(rs(-a, Vector3(0.34, 0.08, 0.26)), Vector3(cos(a) * r, 0.1, sin(a) * r))
		m.add(NV.ublob(i + variant, 0.3, 0.6, 1), leaf, VINE.lerp(VINE_DARK, rng.randf() * 0.6))
	for i in 3:
		var a := rng.randf() * TAU
		m.add(NV._cyl(0.025, 0.025, 0.7, 5), xf(Vector3(cos(a) * 0.3, 0.06, sin(a) * 0.3), Vector3(90, rad_to_deg(-a), 0)), VINE_DARK)
	return _commit(key, m)


static func hedge(variant: int) -> ArrayMesh:
	var key := "hedge|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var fn := _grad(Color("355f33"), Color("6d9b4c"), 1.3)
	m.add(NV.ublob(variant, 0.25, 0.8, 2), NV.sxf(0.62, Vector3(-0.5, 0.55, 0)), fn)
	m.add(NV.ublob(variant + 1, 0.25, 0.8, 2), NV.sxf(0.72, Vector3(0.1, 0.62, 0.05)), fn)
	m.add(NV.ublob(variant + 2, 0.25, 0.8, 2), NV.sxf(0.58, Vector3(0.68, 0.5, -0.05)), fn)
	return _commit(key, m)


static func berry_clusters(variant: int, color: Color, count: int = 16, spread: Vector3 = Vector3(0.95, 0.55, 0.55)) -> ArrayMesh:
	var key := "berr|%d|%s|%d" % [variant, color.to_html(), count]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + variant
	var m := NV.Merger.new()
	for i in count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := Vector3(d.x * spread.x, 0.5 + d.y * spread.y, d.z * spread.z)
		m.add(NV._sph(0.075, 4, 7), Transform3D(Basis(), p), color.lerp(Color.WHITE, rng.randf() * 0.2))
	return _commit(key, m)


## Crooked rustic fence, 2 m along X, base at y = 0.
static func fence(variant: int) -> ArrayMesh:
	var key := "fence|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5500 + variant
	var m := NV.Merger.new()
	for sx in [-1.0, 1.0]:
		m.add(NV._cyl(0.06, 0.08, 1.05, 6), xf(Vector3(float(sx) * 0.95, 0.5, 0), Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-7, 7))), FENCE_DARK)
	for y in [0.35, 0.72]:
		m.add(NV._box(Vector3(2.05, 0.09, 0.07)), xf(Vector3(0, float(y) + rng.randf_range(-0.05, 0.05), 0.05), Vector3(0, 0, rng.randf_range(-4, 4))), FENCE)
	return _commit(key, m)


static func puddle_disc() -> Mesh:
	return NV._cyl(1.0, 1.0, 0.02, 18)


static func hay_bale() -> ArrayMesh:
	if _cache.has("bale"):
		return _cache["bale"]
	var m := NV.Merger.new()
	m.add(Kit.blob_mesh(0.5, 5601, 0.08, 1.0, 2), Transform3D(Basis().scaled(Vector3(1.3, 0.62, 0.85)), Vector3(0, 0.3, 0)), _grad(STRAW_DARK, STRAW, 0.6))
	for x in [-0.3, 0.3]:
		m.add(NV._box(Vector3(0.05, 0.64, 0.9)), Transform3D(Basis(), Vector3(float(x), 0.31, 0)), FENCE_DARK)
	return _commit("bale", m)


static func leaf_pile(variant: int) -> ArrayMesh:
	var key := "leafp|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var cols := [Color("e9a15b"), Color("d9682c"), Color("c9571f"), Color("f2c14e")]
	m.add(Kit.blob_mesh(0.6, 5700 + variant, 0.35, 0.35, 2), Transform3D(Basis(), Vector3(0, 0.05, 0)), cols[variant % cols.size()])
	for i in 4:
		var a := TAU * float(i) / 4.0 + float(variant)
		m.add(NV._box(Vector3(0.16, 0.02, 0.1)), xf(Vector3(cos(a) * 0.65, 0.02, sin(a) * 0.65), Vector3(0, float(i) * 50.0, 0)), cols[(i + variant) % cols.size()])
	return _commit(key, m)


## Little harmless scarecrow (1.55 m): sack head with a stitched smile, patched coat, straw cuffs, small hat.
static func scarecrow() -> ArrayMesh:
	if _cache.has("scare"):
		return _cache["scare"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.05, 0.06, 1.55, 6), Transform3D(Basis(), Vector3(0, 0.77, 0)), FENCE_DARK)
	m.add(NV._cyl(0.04, 0.04, 1.3, 6), xf(Vector3(0, 1.1, 0), Vector3(0, 0, 90)), FENCE_DARK)
	m.add(NV._cyl(0.22, 0.3, 0.62, 8), Transform3D(Basis(), Vector3(0, 0.95, 0)), Color("7a8a4a"))
	m.add(NV._box(Vector3(0.16, 0.16, 0.04)), xf(Vector3(0.1, 1.0, 0.27), Vector3(0, 0, 12)), RIBBON_RED)
	for sx in [-1.0, 1.0]:
		m.add(NV._cyl(0.08, 0.1, 0.4, 6), xf(Vector3(float(sx) * 0.38, 1.1, 0), Vector3(0, 0, 90)), Color("7a8a4a"))
		m.add(NV._cyl(0.02, 0.1, 0.16, 6), xf(Vector3(float(sx) * 0.62, 1.1, 0), Vector3(0, 0, float(sx) * -90.0)), STRAW)
	m.add(NV._cyl(0.06, 0.2, 0.16, 7), Transform3D(Basis(), Vector3(0, 0.6, 0)), STRAW)
	m.add(NV._sph(0.21, 6, 9), Transform3D(Basis().scaled(Vector3(1.0, 1.05, 0.95)), Vector3(0, 1.43, 0)), Color("e8d2a6"))
	for sx in [-1.0, 1.0]:
		m.add(NV._sph(0.03, 3, 5), Transform3D(Basis(), Vector3(float(sx) * 0.07, 1.47, 0.19)), PLUM)
	for i in 5:
		var x := lerpf(-0.08, 0.08, float(i) / 4.0)
		m.add(NV._box(Vector3(0.03, 0.012, 0.02)), Transform3D(Basis(), Vector3(x, 1.36 - sin(float(i) / 4.0 * PI) * 0.025, 0.2)), PLUM)
	m.add(NV._cyl(0.3, 0.3, 0.03, 12), Transform3D(Basis(), Vector3(0, 1.6, 0)), STRAW_DARK)
	m.add(NV._cyl(0.02, 0.16, 0.3, 10), xf(Vector3(0.02, 1.76, 0), Vector3(0, 0, -8)), STRAW_DARK)
	return _commit("scare", m)


## Stone cistern (the irrigation source): round rim, dark inner water, a wooden spout toward +Z.
static func cistern() -> ArrayMesh:
	if _cache.has("cistern"):
		return _cache["cistern"]
	var m := NV.Merger.new()
	var fn := _grad(Color("8f897f"), Color("c9c2b5"), 0.9)
	m.add(NV._cyl(1.3, 1.4, 0.9, 16), Transform3D(Basis(), Vector3(0, 0.45, 0)), fn)
	m.add(NV._cyl(1.05, 1.05, 0.04, 16), Transform3D(Basis(), Vector3(0, 0.86, 0)), Color("3f8fb0"))
	m.add(NV._box(Vector3(0.36, 0.14, 1.1)), Transform3D(Basis(), Vector3(0, 0.62, 1.4)), FENCE)
	m.add(Kit.blob_mesh(0.3, 5801, 0.25, 0.6, 1), Transform3D(Basis(), Vector3(-0.9, 0.9, -0.6)), Palette.MOSS)
	return _commit("cistern", m)


## One wooden flume piece: a U-shaped trough 1 m long along -Z (sides + bottom), top at y = 0.16.
static func flume_piece() -> ArrayMesh:
	if _cache.has("flume"):
		return _cache["flume"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.7, 0.05, 1.02)), Transform3D(Basis(), Vector3(0, 0.02, -0.5)), FENCE_DARK)
	for sx in [-1.0, 1.0]:
		m.add(NV._box(Vector3(0.06, 0.18, 1.02)), Transform3D(Basis(), Vector3(float(sx) * 0.34, 0.08, -0.5)), FENCE)
	return _commit("flume", m)


static func lever_post() -> ArrayMesh:
	if _cache.has("lpost"):
		return _cache["lpost"]
	var m := NV.Merger.new()
	m.add(Kit.blob_mesh(0.3, 5901, 0.2, 0.5, 1), Transform3D(Basis(), Vector3(0, 0.08, 0)), Palette.STONE)
	m.add(NV._box(Vector3(0.22, 1.0, 0.22)), Transform3D(Basis(), Vector3(0, 0.55, 0)), FENCE_DARK)
	m.add(NV._cyl(0.1, 0.1, 0.3, 10), xf(Vector3(0, 0.95, 0), Vector3(0, 0, 90)), IRON)
	return _commit("lpost", m)


## Lever handle (pivot at the hub; points up along +Y), bright paint so it reads from afar.
static func lever_arm() -> ArrayMesh:
	if _cache.has("larm"):
		return _cache["larm"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.045, 0.045, 0.75, 6), Transform3D(Basis(), Vector3(0, 0.37, 0)), IRON)
	m.add(NV._sph(0.1, 5, 8), Transform3D(Basis(), Vector3(0, 0.78, 0)), RIBBON_GOLD)
	return _commit("larm", m)


## Big painted arrow board (arrow points along -Z), on its own so it can swing to the active branch.
static func arrow_board() -> ArrayMesh:
	if _cache.has("arrow"):
		return _cache["arrow"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.5, 0.06, 1.1)), Transform3D(Basis(), Vector3(0, 0, -0.2)), FENCE_DARK)
	m.add(NV._box(Vector3(0.18, 0.08, 0.6)), Transform3D(Basis(), Vector3(0, 0.02, -0.05)), RIBBON_GOLD)
	m.add(_prism(Vector3(0.44, 0.34, 0.08)), xf(Vector3(0, 0.02, -0.52), Vector3(-90, 0, 0)), RIBBON_GOLD)
	return _commit("arrow", m)


## Sluice gate paddle (slides up/down in its frame): a plank 0.8 wide, 0.5 tall.
static func gate_paddle() -> ArrayMesh:
	if _cache.has("paddle"):
		return _cache["paddle"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.8, 0.5, 0.08)), Transform3D(Basis(), Vector3(0, 0.25, 0)), FENCE)
	m.add(NV._box(Vector3(0.84, 0.08, 0.1)), Transform3D(Basis(), Vector3(0, 0.46, 0)), RIBBON_GOLD)
	m.add(NV._cyl(0.03, 0.03, 0.5, 6), Transform3D(Basis(), Vector3(0, 0.7, 0)), IRON)
	return _commit("paddle", m)


static func gate_frame() -> ArrayMesh:
	if _cache.has("gframe"):
		return _cache["gframe"]
	var m := NV.Merger.new()
	for sx in [-1.0, 1.0]:
		m.add(NV._box(Vector3(0.14, 1.3, 0.16)), Transform3D(Basis(), Vector3(float(sx) * 0.5, 0.65, 0)), FENCE_DARK)
	m.add(NV._box(Vector3(1.14, 0.14, 0.18)), Transform3D(Basis(), Vector3(0, 1.3, 0)), FENCE_DARK)
	return _commit("gframe", m)


## Raised festival bed frame (size.x by size.y), 0.35 m tall, ribbon posts at the corners.
static func bed_frame(size: Vector2) -> ArrayMesh:
	var key := "bed|%s" % size
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	for sz in [-1.0, 1.0]:
		m.add(NV._box(Vector3(size.x + 0.12, 0.35, 0.12)), Transform3D(Basis(), Vector3(0, 0.175, float(sz) * size.y * 0.5)), FENCE)
	for sx in [-1.0, 1.0]:
		m.add(NV._box(Vector3(0.12, 0.35, size.y)), Transform3D(Basis(), Vector3(float(sx) * size.x * 0.5, 0.175, 0)), FENCE)
		for sz in [-1.0, 1.0]:
			var c := Vector3(float(sx) * size.x * 0.5, 0, float(sz) * size.y * 0.5)
			m.add(NV._cyl(0.05, 0.06, 0.8, 6), Transform3D(Basis(), c + Vector3(0, 0.4, 0)), FENCE_DARK)
			m.add(NV._sph(0.09, 4, 6), Transform3D(Basis(), c + Vector3(0, 0.84, 0)), RIBBON_RED if sz > 0.0 else RIBBON_PLUM)
	return _commit(key, m)


static func seed_box() -> ArrayMesh:
	if _cache.has("seedbox"):
		return _cache["seedbox"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.6, 0.4, 0.45)), Transform3D(Basis(), Vector3(0, 0.2, 0)), FENCE)
	m.add(NV._box(Vector3(0.64, 0.05, 0.49)), xf(Vector3(0, 0.44, -0.12), Vector3(-28, 0, 0)), FENCE_DARK)
	m.add(NV._sph(0.1, 5, 8), Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), Vector3(0.0, 0.22, 0.24)), PUMPKIN)
	for i in 3:
		m.add(NV._box(Vector3(0.12, 0.16, 0.02)), xf(Vector3(-0.16 + float(i) * 0.16, 0.46, 0.05), Vector3(-10, 0, float(i - 1) * 8.0)), [RIBBON_CREAM, RIBBON_GOLD, ROSEBERRY][i])
	# the garden note, folded and tucked under the lid's front edge (lore_ch2_garden_note: "A Note in the Seed Box")
	m.add(NV._box(Vector3(0.2, 0.02, 0.14)), xf(Vector3(0.12, 0.415, 0.2), Vector3(-6, 14, 0)), Color("fbf3dc"))
	return _commit("seedbox", m)


## The festival garden's painted sign: a post with a board showing a pumpkin and a sprout (decor, no text to read).
static func garden_sign() -> ArrayMesh:
	if _cache.has("gardensign"):
		return _cache["gardensign"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.05, 0.06, 1.1, 6), Transform3D(Basis(), Vector3(0, 0.55, 0)), FENCE_DARK)
	m.add(NV._box(Vector3(0.5, 0.34, 0.05)), xf(Vector3(0, 1.05, 0.05), Vector3(-10, 0, 0)), FENCE)
	m.add(NV._sph(0.09, 5, 8), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10.0)) * Basis.from_scale(Vector3(1.2, 0.95, 0.3)), Vector3(-0.08, 1.02, 0.085)), PUMPKIN)
	m.add(NV._box(Vector3(0.03, 0.14, 0.02)), xf(Vector3(0.12, 1.02, 0.085), Vector3(-10, 0, 0)), VINE)
	m.add(NV._sph(0.05, 4, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.6, 0.4)), Vector3(0.16, 1.1, 0.085)), VINE)
	m.add(NV._sph(0.05, 4, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.6, 0.4)), Vector3(0.08, 1.07, 0.085)), VINE)
	return _commit("gardensign", m)


static func note_post() -> ArrayMesh:
	if _cache.has("notepost"):
		return _cache["notepost"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.05, 0.06, 1.1, 6), Transform3D(Basis(), Vector3(0, 0.55, 0)), FENCE_DARK)
	m.add(NV._box(Vector3(0.46, 0.34, 0.05)), xf(Vector3(0, 1.05, 0.05), Vector3(-10, 0, 0)), FENCE)
	m.add(NV._box(Vector3(0.3, 0.22, 0.02)), xf(Vector3(0.02, 1.05, 0.085), Vector3(-10, 0, 4)), RIBBON_CREAM)
	return _commit("notepost", m)


## Tall festival lamp post with a curled iron hook; the pumpkin-shaped glass is lamp_glass().
static func lamp_post() -> ArrayMesh:
	if _cache.has("lamppost"):
		return _cache["lamppost"]
	var m := NV.Merger.new()
	m.add(Kit.blob_mesh(0.45, 6001, 0.2, 0.45, 1), Transform3D(Basis(), Vector3(0, 0.1, 0)), Palette.STONE)
	m.add(NV._cyl(0.1, 0.14, 3.2, 8), Transform3D(Basis(), Vector3(0, 1.6, 0)), FENCE_DARK)
	m.add(NV._box(Vector3(0.9, 0.08, 0.08)), Transform3D(Basis(), Vector3(0.38, 3.1, 0)), IRON)
	m.add(_torus(0.08, 0.14), xf(Vector3(0.85, 3.02, 0), Vector3(90, 0, 0)), IRON)
	m.add(NV._cyl(0.012, 0.012, 0.3, 4), Transform3D(Basis(), Vector3(0.78, 2.93, 0)), IRON)
	for i in 3:
		m.add(NV._box(Vector3(0.1, 0.3, 0.02)), xf(Vector3(-0.02 + float(i) * 0.05, 2.6 - float(i) * 0.04, 0.12), Vector3(0, 0, -12.0 + float(i) * 12.0)), [RIBBON_RED, RIBBON_GOLD, RIBBON_PLUM][i])
	return _commit("lamppost", m)


static func lamp_glass() -> ArrayMesh:
	if _cache.has("lampglass"):
		return _cache["lampglass"]
	var m := NV.Merger.new()
	for i in 6:
		var a := TAU * float(i) / 6.0
		m.add(NV._sph(0.2, 6, 8), Transform3D(rs(-a, Vector3(0.55, 1.0, 0.5)), Vector3(cos(a) * 0.1, 0, sin(a) * 0.1)), Color.WHITE)
	m.add(NV._cyl(0.05, 0.08, 0.1, 6), Transform3D(Basis(), Vector3(0, 0.22, 0)), Color.WHITE)
	return _commit("lampglass", m)


## Warning sign: a board with a painted twitching pumpkin (two stem ticks) - no words needed.
static func warning_sign() -> ArrayMesh:
	if _cache.has("warn"):
		return _cache["warn"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.06, 0.07, 1.4, 6), Transform3D(Basis(), Vector3(0, 0.7, 0)), FENCE_DARK)
	m.add(NV._box(Vector3(0.9, 0.62, 0.06)), xf(Vector3(0, 1.35, 0.05), Vector3(0, 0, -4)), RIBBON_CREAM)
	m.add(NV._sph(0.17, 5, 8), Transform3D(Basis().scaled(Vector3(1.2, 0.9, 0.3)), Vector3(-0.08, 1.3, 0.1)), PUMPKIN)
	m.add(NV._box(Vector3(0.04, 0.12, 0.03)), xf(Vector3(-0.08, 1.5, 0.1), Vector3(0, 0, 15)), STEM)
	for i in 2:
		m.add(NV._box(Vector3(0.1, 0.03, 0.03)), xf(Vector3(0.1 + float(i) * 0.04, 1.54 + float(i) * 0.06, 0.1), Vector3(0, 0, 30)), RIBBON_RED)
	m.add(NV._box(Vector3(0.06, 0.24, 0.03)), Transform3D(Basis(), Vector3(0.26, 1.36, 0.1)), RIBBON_RED)
	m.add(NV._box(Vector3(0.06, 0.06, 0.03)), Transform3D(Basis(), Vector3(0.26, 1.18, 0.1)), RIBBON_RED)
	return _commit("warn", m)


static func stake() -> ArrayMesh:
	if _cache.has("stake"):
		return _cache["stake"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.035, 0.05, 1.1, 5), Transform3D(Basis(), Vector3(0, 0.55, 0)), FENCE_DARK)
	m.add(NV._sph(0.06, 4, 6), Transform3D(Basis(), Vector3(0, 1.12, 0)), RIBBON_RED)
	return _commit("stake", m)


## A ribbon streamer: rises from its knot at the origin (so the toon wind sways its tail).
static func ribbon_strip(length: float = 0.7) -> ArrayMesh:
	var key := "ribbon|%.2f" % length
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.07, length, 0.012)), xf(Vector3(0.05, length * 0.5, 0), Vector3(0, 0, -18)), Color.WHITE)
	m.add(NV._box(Vector3(0.07, length * 0.8, 0.012)), xf(Vector3(-0.05, length * 0.4, 0), Vector3(0, 0, 14)), Color.WHITE)
	m.add(NV._sph(0.05, 4, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.6)), Vector3.ZERO), Color.WHITE)
	return _commit(key, m)


## Torn coat on a post + a crossed rake: the Patchwalker field marker.
static func coat_post() -> ArrayMesh:
	if _cache.has("coatpost"):
		return _cache["coatpost"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.06, 0.08, 1.8, 6), xf(Vector3(0, 0.9, 0), Vector3(0, 0, 6)), FENCE_DARK)
	m.add(NV._box(Vector3(0.7, 0.9, 0.16)), xf(Vector3(0.05, 1.2, 0), Vector3(0, 0, 4)), Color("5f5a4a"))
	m.add(NV._box(Vector3(0.2, 0.3, 0.17)), xf(Vector3(-0.18, 0.86, 0.01), Vector3(0, 0, -20)), Color("7a6a3a"))
	m.add(NV._box(Vector3(0.16, 0.16, 0.18)), xf(Vector3(0.22, 1.35, 0.01), Vector3(0, 0, 25)), RIBBON_PLUM.darkened(0.3))
	m.add(NV._cyl(0.025, 0.025, 1.7, 5), xf(Vector3(0.45, 0.8, 0.2), Vector3(0, 0, -24)), FENCE)
	m.add(NV._box(Vector3(0.5, 0.05, 0.06)), xf(Vector3(0.8, 1.56, 0.2), Vector3(0, 0, -24)), IRON)
	for i in 5:
		m.add(NV._box(Vector3(0.02, 0.14, 0.02)), xf(Vector3(0.62 + float(i) * 0.09, 1.56 - float(i) * 0.04, 0.2), Vector3(0, 0, -24)), IRON)
	return _commit("coatpost", m)


static func straw_tuft() -> ArrayMesh:
	if _cache.has("strawtuft"):
		return _cache["strawtuft"]
	var m := NV.Merger.new()
	for i in 5:
		var a := TAU * float(i) / 5.0
		m.add(NV._box(Vector3(0.03, 0.02, 0.4)), xf(Vector3(cos(a) * 0.1, 0.02, sin(a) * 0.1), Vector3(0, float(i) * 37.0, 0)), STRAW if i % 2 == 0 else STRAW_DARK)
	return _commit("strawtuft", m)


## The festival sprout -> vine -> pumpkin growth pieces (vine curls grow up from the soil).
static func festival_vine() -> ArrayMesh:
	if _cache.has("fvine"):
		return _cache["fvine"]
	var m := NV.Merger.new()
	for i in 5:
		var a := TAU * float(i) / 5.0
		m.add(NV.ublob(i + 3, 0.3, 0.6, 1), Transform3D(rs(-a, Vector3(0.3, 0.08, 0.24)), Vector3(cos(a) * 0.55, 0.12, sin(a) * 0.4)), VINE.lerp(VINE_DARK, float(i % 2) * 0.5))
	for i in 3:
		m.add(_torus(0.02, 0.05), xf(Vector3(-0.5 + float(i) * 0.5, 0.25, 0.3), Vector3(90, float(i) * 40.0, 0)), VINE_DARK)
	return _commit("fvine", m)


# --- Pools props ------------------------------------------------------------------------------------------

static func reed_clump(variant: int) -> ArrayMesh:
	var key := "reed|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6100 + variant
	var m := NV.Merger.new()
	var n := 5 + variant % 3
	for i in n:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.18)
		var h := rng.randf_range(0.9, 1.5)
		var p := Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		m.add(NV._cyl(0.012, 0.022, h, 4), xf(p, Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))), REED)
		if i % 2 == 0:
			m.add(NV._cyl(0.04, 0.04, 0.2, 6), Transform3D(Basis(), p + Vector3(0, h * 0.5 - 0.08, 0)), REED_TIP)
	for i in 3:
		var a := rng.randf() * TAU
		m.add(NV._box(Vector3(0.05, 0.9, 0.012)), xf(Vector3(cos(a) * 0.12, 0.4, sin(a) * 0.12), Vector3(rng.randf_range(-20, 20), rad_to_deg(a), 0)), REED.darkened(0.15))
	return _commit(key, m)


static func lily_pad(variant: int) -> ArrayMesh:
	var key := "lily|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.34, 0.34, 0.02, 12), Transform3D(Basis(), Vector3.ZERO), LILY.lerp(Color("9ccf62"), float(variant % 3) * 0.2))
	if variant % 3 == 0:
		m.add(NV._sph(0.08, 4, 7), Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), Vector3(0.08, 0.05, 0.04)), Color("f7d9e6"))
	return _commit(key, m)


static func stepping_stone(variant: int) -> ArrayMesh:
	var key := "step|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var c := Color("9a948a").lerp(Color("c9c2b5"), clampf(p.y * 3.0, 0.0, 1.0))
		return c.lerp(Palette.MOSS, 0.35) if n.y > 0.8 and p.x < -0.1 else c
	m.add(Kit.blob_mesh(0.55, 6200 + variant, 0.15, 0.42, 2), Transform3D(Basis(), Vector3(0, 0.0, 0)), fn)
	return _commit(key, m)


## Mossy mound under the sugarcaps.
static func moss_mound(variant: int) -> ArrayMesh:
	var key := "moss|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	m.add(Kit.blob_mesh(0.45, 7200 + variant, 0.25, 0.3, 2), Transform3D(Basis(), Vector3(0, 0.04, 0)), _grad(Color("4f7a3e"), Palette.MOSS, 0.2))
	return _commit(key, m)


## Pastel sugarcap mushrooms (the pickable part of a sugarcap patch).
static func sugarcap_caps(variant: int) -> ArrayMesh:
	var key := "sugarcaps|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7100 + variant
	var m := NV.Merger.new()
	for i in 5:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.05, 0.35)
		var h := rng.randf_range(0.12, 0.26)
		var cr := rng.randf_range(0.08, 0.13)
		var p := Vector3(cos(a) * r, 0.08, sin(a) * r)
		m.add(NV._cyl(cr * 0.35, cr * 0.45, h, 6), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)), Color("fff2e0"))
		m.add(NV._hemi(cr, cr * 0.9, 10), Transform3D(Basis(), p + Vector3(0, h - 0.01, 0)), SUGARCAP.lerp(Color("ffd6e6"), rng.randf() * 0.5))
	return _commit(key, m)


static func cyl_mesh(radius: float, h: float) -> Mesh:
	return NV._cyl(radius, radius, h, 10)


static func box_mesh(size: Vector3) -> Mesh:
	return NV._box(size)


## A tall thin festival pole with a ribbon knot (holds the bunting).
static func bunting_post() -> ArrayMesh:
	if _cache.has("bpost"):
		return _cache["bpost"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.06, 0.08, 2.7, 7), Transform3D(Basis(), Vector3(0, 1.35, 0)), FENCE_DARK)
	m.add(NV._sph(0.1, 5, 8), Transform3D(Basis(), Vector3(0, 2.72, 0)), RIBBON_GOLD)
	m.add(NV._sph(0.07, 4, 6), Transform3D(Basis().scaled(Vector3(1.6, 0.7, 0.7)), Vector3(0.0, 2.45, 0.06)), RIBBON_PLUM)
	return _commit("bpost", m)


static func glint() -> Mesh:
	return NV._sph(0.05, 2, 4)


## A reed-stem wind chime: tall pole, three little bells and a knot of ribbon. The glint above is separate.
static func chime_post() -> ArrayMesh:
	if _cache.has("chime"):
		return _cache["chime"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.035, 0.05, 1.7, 6), xf(Vector3(0, 0.85, 0), Vector3(0, 0, 4)), Color("c2a878"))
	m.add(NV._cyl(0.015, 0.015, 0.5, 4), xf(Vector3(0.2, 1.65, 0), Vector3(0, 0, 90)), Color("c2a878"))
	for i in 3:
		var x := 0.1 + float(i) * 0.12
		m.add(NV._cyl(0.004, 0.004, 0.18 + float(i) * 0.06, 3), Transform3D(Basis(), Vector3(x, 1.55 - float(i) * 0.03, 0)), IRON)
		m.add(NV._cyl(0.012, 0.045, 0.08, 8), Transform3D(Basis(), Vector3(x, 1.43 - float(i) * 0.06, 0)), Color("e8d48a"))
	return _commit("chime", m)


## A weeping willow (trunk + drooping curtain), 4.5 m tall.
static func willow() -> ArrayMesh:
	if _cache.has("willow"):
		return _cache["willow"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.28, 0.42, 2.6, 9), xf(Vector3(0, 1.3, 0), Vector3(0, 0, 5)), Palette.BARK)
	var fn := _grad(Color("5b8a4a"), Color("a8c96a"), 4.5)
	m.add(NV.ublob(2, 0.3, 0.7, 2), NV.sxf(1.5, Vector3(0.1, 3.4, 0)), fn)
	for i in 7:
		var a := TAU * float(i) / 7.0
		m.add(NV.ublob(i, 0.2, 1.8, 1), Transform3D(Basis().scaled(Vector3(0.55, 1.0, 0.55)), Vector3(cos(a) * 1.35, 2.5, sin(a) * 1.35)), fn)
	return _commit("willow", m)


static func pouch() -> ArrayMesh:
	if _cache.has("pouch"):
		return _cache["pouch"]
	var m := NV.Merger.new()
	m.add(NV._sph(0.2, 6, 9), Transform3D(Basis().scaled(Vector3(1.0, 0.8, 0.9)), Vector3(0, 0.16, 0)), Color("c9876a"))
	m.add(NV._cyl(0.06, 0.1, 0.1, 8), Transform3D(Basis(), Vector3(0, 0.33, 0)), Color("c9876a"))
	m.add(_torus(0.07, 0.1), Transform3D(Basis(), Vector3(0, 0.3, 0)), RIBBON_GOLD)
	m.add(NV._sph(0.05, 4, 6), Transform3D(Basis(), Vector3(0.12, 0.3, 0.06)), RIBBON_PLUM)
	return _commit("pouch", m)


static func spring_stone() -> ArrayMesh:
	return NV.boulder_mesh(3, Color("a8a295"), 0.9)


static func mossy_log() -> ArrayMesh:
	return Props.fallen_log(2)


# --- Candleyard props ---------------------------------------------------------------------------------------

## Whimsical leaning memory stone (0.8 x 1.25 x 0.26): rounded top, a carved crescent and star that glow faintly.
static func leaning_stone(variant: int) -> ArrayMesh:
	var key := "lstone|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var tint := LILAC_STONE.lerp(Color("c7bfd6"), float(variant % 3) * 0.25)
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var c := tint.darkened(0.22).lerp(tint, clampf(p.y / 1.2, 0.0, 1.0))
		return c.lerp(Palette.MOSS, 0.5) if n.y > 0.7 else c
	m.add(NV._box(Vector3(0.8, 0.9, 0.26)), Transform3D(Basis(), Vector3(0, 0.45, 0)), fn)
	m.add(NV._cyl(0.4, 0.4, 0.26, 14), xf(Vector3(0, 0.9, 0), Vector3(90, 0, 0)), fn)
	m.add(Kit.blob_mesh(0.3, 6300 + variant, 0.2, 0.5, 1), Transform3D(Basis().scaled(Vector3(1.6, 0.6, 0.9)), Vector3(0, 0.05, 0)), Color("8f8a9a"))
	return _commit(key, m)


## The carved crescent + star on a leaning stone's face (+Z side); glow material.
static func stone_carving(variant: int) -> ArrayMesh:
	var key := "carve|%d" % (variant % 2)
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	if variant % 2 == 0:
		m.add(_torus(0.1, 0.16), xf(Vector3(0, 0.85, 0.135), Vector3(90, 0, 0), Vector3(1, 0.3, 1)), Color.WHITE)
	else:
		for i in 4:
			m.add(NV._box(Vector3(0.05, 0.3, 0.02)), xf(Vector3(0, 0.82, 0.135), Vector3(0, 0, float(i) * 45.0)), Color.WHITE)
	return _commit(key, m)


static func candle(variant: int) -> ArrayMesh:
	var key := "candle|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var h := 0.14 + 0.06 * float(variant % 3)
	m.add(NV._cyl(0.035, 0.04, h, 7), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), Color("f4ead2"))
	m.add(NV._sph(0.03, 3, 5), Transform3D(Basis().scaled(Vector3(1.3, 0.5, 1.3)), Vector3(0.03, h - 0.02, 0)), Color("f4ead2"))
	return _commit(key, m)


## Candle flame (unit, at the candle top): used with a violet glow material in a MultiMesh.
static func flame() -> Mesh:
	return NV._sph(0.03, 3, 5)


## Moonflower clump: stems and leaves (vertex colour); the petals are moonflower_petals() (soft glow).
static func moonflower_leaves(variant: int) -> ArrayMesh:
	var key := "mfl|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6400 + variant
	var m := NV.Merger.new()
	for i in 4:
		var a := rng.randf() * TAU
		m.add(NV._cyl(0.012, 0.016, 0.42, 4), xf(Vector3(cos(a) * 0.1, 0.2, sin(a) * 0.1), Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10))), VINE_DARK)
		m.add(NV._sph(0.08, 3, 6), Transform3D(rs(-a, Vector3(1.4, 0.25, 0.6)), Vector3(cos(a) * 0.16, 0.06, sin(a) * 0.16)), VINE)
	return _commit(key, m)


static func moonflower_petals(variant: int) -> ArrayMesh:
	var key := "mfp|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6400 + variant
	var m := NV.Merger.new()
	for i in 4:
		var a := rng.randf() * TAU
		var top := Vector3(cos(a) * 0.1, 0.42, sin(a) * 0.1)
		for k in 5:
			var pa := TAU * float(k) / 5.0
			m.add(NV._sph(0.05, 3, 5), Transform3D(rs(-pa, Vector3(1.6, 0.35, 0.8)), top + Vector3(cos(pa) * 0.05, 0, sin(pa) * 0.05)), Color.WHITE)
	return _commit(key, m)


## The Candle Tree: a gnarled, friendly old trunk with low curling branches (one points toward +X+Z at hat
## height) and a sparse dusk-violet crown.
static func candle_tree() -> ArrayMesh:
	if _cache.has("ctree"):
		return _cache["ctree"]
	var m := NV.Merger.new()
	var bark := _grad(Color("4f3f4a"), Color("7a6470"), 4.0)
	m.add(NV._cyl(0.5, 0.78, 2.4, 10), xf(Vector3(0, 1.2, 0), Vector3(0, 0, -6)), bark)
	m.add(NV._cyl(0.34, 0.5, 1.8, 9), xf(Vector3(-0.2, 3.1, 0.1), Vector3(12, 0, 10)), bark)
	var branches := [[Vector3(0.9, 1.7, 0.7), Vector3(0, -38, 62), 1.9], [Vector3(-0.9, 2.6, -0.3), Vector3(0, 160, 58), 1.8],
		[Vector3(0.3, 3.3, -0.9), Vector3(0, 95, 55), 1.6], [Vector3(-0.5, 3.6, 0.8), Vector3(0, -110, 50), 1.5]]
	for b in branches:
		m.add(NV._cyl(0.08, 0.16, float(b[2]), 7), xf(b[0], b[1]), bark)
	var crown := _grad(Color("5b4a78"), Color("9a7fbf"), 5.5)
	for c in [[Vector3(0, 4.4, 0), 1.3], [Vector3(1.3, 3.9, 0.6), 0.9], [Vector3(-1.2, 4.1, -0.4), 1.0], [Vector3(0.2, 4.0, -1.2), 0.85]]:
		m.add(NV.ublob(int(c[1] * 10.0), 0.3, 0.75, 2), NV.sxf(float(c[1]), c[0]), crown)
	return _commit("ctree", m)


## A small hanging lantern (cage) - the glass is a violet glow sphere placed by the caller at y = -0.18.
static func hanging_lantern() -> ArrayMesh:
	if _cache.has("hlant"):
		return _cache["hlant"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.006, 0.006, 0.3, 3), Transform3D(Basis(), Vector3(0, 0.0, 0)), IRON)
	m.add(NV._cyl(0.02, 0.1, 0.07, 6), Transform3D(Basis(), Vector3(0, -0.08, 0)), IRON)
	m.add(NV._cyl(0.08, 0.08, 0.03, 6), Transform3D(Basis(), Vector3(0, -0.3, 0)), IRON)
	return _commit("hlant", m)


## Groundskeeper's shed: plum-painted planks, dark roof, a door on its -X face, a warm little window.
static func shed(size: Vector2) -> ArrayMesh:
	var key := "shed|%s" % size
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var h := 2.1
	m.add(NV._box(Vector3(size.x, h, size.y)), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), SHED_PLANK)
	for i in 6:
		var z := lerpf(-size.y * 0.5 + 0.2, size.y * 0.5 - 0.2, float(i) / 5.0)
		m.add(NV._box(Vector3(size.x + 0.03, h - 0.1, 0.03)), Transform3D(Basis(), Vector3(0, h * 0.5, z)), SHED_PLANK.darkened(0.15))
	m.add(_prism(Vector3(size.y + 0.5, 1.0, size.x + 0.5)), xf(Vector3(0, h + 0.5, 0), Vector3(0, 90, 0)), Color("3e3346"))
	m.add(NV._box(Vector3(0.06, 1.6, 0.9)), Transform3D(Basis(), Vector3(-size.x * 0.5 - 0.03, 0.8, 0.2)), FENCE_DARK)
	m.add(NV._sph(0.04, 3, 5), Transform3D(Basis(), Vector3(-size.x * 0.5 - 0.07, 0.8, 0.52)), RIBBON_GOLD)
	m.add(NV._box(Vector3(0.05, 0.4, 0.4)), Transform3D(Basis(), Vector3(-size.x * 0.5 - 0.02, 1.35, -0.6)), Color("ffd79a"))
	return _commit(key, m)


## Rake, spade and watering can leaning together (the groundskeepers' tools), ~1.6 m.
static func garden_tools() -> ArrayMesh:
	if _cache.has("tools"):
		return _cache["tools"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.025, 0.025, 1.6, 5), xf(Vector3(0, 0.78, 0), Vector3(0, 0, 14)), FENCE)
	m.add(NV._box(Vector3(0.45, 0.05, 0.05)), xf(Vector3(-0.19, 1.55, 0), Vector3(0, 0, 14)), IRON)
	for i in 5:
		m.add(NV._box(Vector3(0.02, 0.12, 0.02)), xf(Vector3(-0.36 + float(i) * 0.09, 1.49 + float(i) * 0.02, 0), Vector3(0, 0, 14)), IRON)
	m.add(NV._cyl(0.025, 0.025, 1.3, 5), xf(Vector3(0.35, 0.65, 0.1), Vector3(0, 0, -10)), FENCE)
	m.add(NV._box(Vector3(0.22, 0.3, 0.04)), xf(Vector3(0.44, 0.12, 0.1), Vector3(0, 0, -10)), Color("8f8a96"))
	m.add(NV._cyl(0.14, 0.16, 0.26, 10), Transform3D(Basis(), Vector3(0.6, 0.13, -0.3)), Color("6f8a9a"))
	m.add(NV._cyl(0.02, 0.03, 0.3, 5), xf(Vector3(0.8, 0.26, -0.3), Vector3(0, 0, -55)), Color("6f8a9a"))
	return _commit("tools", m)


static func wheelbarrow() -> ArrayMesh:
	if _cache.has("barrow"):
		return _cache["barrow"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.7, 0.3, 0.55)), xf(Vector3(0, 0.45, 0), Vector3(0, 0, -6)), Color("6f8a9a"))
	m.add(NV._cyl(0.2, 0.2, 0.08, 12), xf(Vector3(0.45, 0.2, 0), Vector3(90, 0, 0)), FENCE_DARK)
	for sz in [-1.0, 1.0]:
		m.add(NV._cyl(0.025, 0.025, 1.1, 5), xf(Vector3(-0.3, 0.5, float(sz) * 0.22), Vector3(0, 0, -78)), FENCE)
		m.add(NV._cyl(0.02, 0.02, 0.35, 4), Transform3D(Basis(), Vector3(-0.2, 0.18, float(sz) * 0.22)), FENCE_DARK)
	m.add(Kit.blob_mesh(0.28, 6501, 0.3, 0.5, 1), Transform3D(Basis(), Vector3(0, 0.62, 0)), Color("e9a15b"))
	return _commit("barrow", m)


## A storybook bench with curled arms (seat 1.5 m along X, facing +Z).
static func bench() -> ArrayMesh:
	if _cache.has("bench"):
		return _cache["bench"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(1.5, 0.08, 0.46)), Transform3D(Basis(), Vector3(0, 0.46, 0)), FENCE)
	for i in 3:
		m.add(NV._box(Vector3(1.5, 0.12, 0.04)), xf(Vector3(0, 0.66 + float(i) * 0.16, -0.24), Vector3(-10, 0, 0)), FENCE)
	for sx in [-1.0, 1.0]:
		m.add(NV._box(Vector3(0.08, 0.46, 0.4)), Transform3D(Basis(), Vector3(float(sx) * 0.68, 0.23, 0)), IRON)
		m.add(_torus(0.06, 0.12), xf(Vector3(float(sx) * 0.72, 0.62, 0.12), Vector3(0, 0, 90)), IRON)
	return _commit("bench", m)


## Stone plinth with a shallow empty candle dish on top (the groundskeeper's marker).
static func marker_plinth() -> ArrayMesh:
	if _cache.has("plinth"):
		return _cache["plinth"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.26, 0.34, 0.8, 10), Transform3D(Basis(), Vector3(0, 0.4, 0)), LILAC_STONE)
	m.add(NV._cyl(0.36, 0.36, 0.08, 12), Transform3D(Basis(), Vector3(0, 0.84, 0)), LILAC_STONE.lightened(0.1))
	m.add(NV._cyl(0.18, 0.12, 0.06, 12), Transform3D(Basis(), Vector3(0, 0.91, 0)), Color("8f8a9a"))
	return _commit("plinth", m)


static func seat_stone() -> ArrayMesh:
	if _cache.has("seat"):
		return _cache["seat"]
	var m := NV.Merger.new()
	m.add(Kit.blob_mesh(0.5, 6601, 0.12, 0.5, 2), Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.9)), Vector3(0, 0.22, 0)), LILAC_STONE)
	return _commit("seat", m)


## A big purple witch hat with a floppy tip, a rose ribbon band and a gold buckle (~0.8 m tall).
static func witch_hat() -> ArrayMesh:
	if _cache.has("witchhat"):
		return _cache["witchhat"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.52, 0.52, 0.04, 18), Transform3D(Basis(), Vector3.ZERO), HAT_PURPLE)
	m.add(NV._cyl(0.2, 0.3, 0.34, 14), Transform3D(Basis(), Vector3(0, 0.19, 0)), HAT_PURPLE)
	m.add(NV._cyl(0.08, 0.2, 0.28, 12), xf(Vector3(0.03, 0.48, 0), Vector3(0, 0, -14)), HAT_PURPLE.lightened(0.05))
	m.add(NV._cyl(0.0, 0.08, 0.24, 10), xf(Vector3(0.14, 0.66, 0), Vector3(0, 0, -48)), HAT_PURPLE.lightened(0.1))
	m.add(NV._cyl(0.305, 0.305, 0.08, 16), Transform3D(Basis(), Vector3(0, 0.07, 0)), ROSEBERRY)
	m.add(NV._box(Vector3(0.12, 0.1, 0.03)), Transform3D(Basis(), Vector3(0, 0.07, 0.3)), RIBBON_GOLD)
	return _commit("witchhat", m)


static func iron_lantern_post() -> ArrayMesh:
	if _cache.has("ilpost"):
		return _cache["ilpost"]
	var m := NV.Merger.new()
	m.add(NV._cyl(0.05, 0.07, 1.8, 6), Transform3D(Basis(), Vector3(0, 0.9, 0)), IRON)
	m.add(NV._cyl(0.02, 0.14, 0.12, 6), Transform3D(Basis(), Vector3(0, 2.12, 0)), IRON)
	m.add(NV._cyl(0.12, 0.12, 0.03, 6), Transform3D(Basis(), Vector3(0, 1.82, 0)), IRON)
	return _commit("ilpost", m)


# --- Renewable resin and wild sunflax ------------------------------------------------------------------------

const RESIN := Color("e3a13b")
const RESIN_DARK := Color("b8701f")
const SUNFLAX_STEM := Color("8fa45a")
const SUNFLAX_GOLD := Color("f2cf62")
const TIN := Color("8fa3ad")
const STUMP_R := 0.42


## An old orchard stump with a carved spout, a little tin pail hanging under it on the +Z side and a red festival
## ribbon tied round it (the "marked" tappable stump). Base at y = 0, top at 0.62; the resin is separate.
static func sap_stump(variant: int) -> ArrayMesh:
	var key := "sapstump|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var r0 := STUMP_R + 0.03 * float(posmod(variant, 3) - 1)
	m.add_lumpy(NV._cyl(r0 * 0.9, r0 * 1.06, 0.62, 12, 2), Transform3D(Basis(), Vector3(0, 0.31, 0)), Palette.BARK, 0.05, Vector3.ZERO, 8100 + variant)
	m.add(NV._cyl(r0 * 0.86, r0 * 0.86, 0.04, 12), Transform3D(Basis(), Vector3(0, 0.63, 0)), Palette.WOOD_LIGHT)
	m.add(NV._cyl(r0 * 0.5, r0 * 0.5, 0.02, 12), Transform3D(Basis(), Vector3(0, 0.655, 0)), Palette.WOOD)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4 * float(variant)
		m.add(NV.ublob(i + variant, 0.25, 0.5, 1), NV.sxf(r0 * 0.55, Vector3(cos(a) * r0 * 0.85, 0.08, sin(a) * r0 * 0.85)), Palette.BARK_DARK)
	# the festival mark: a red ribbon band with a little bow on the spout side
	m.add(NV._cyl(r0 * 1.0, r0 * 1.02, 0.07, 14), Transform3D(Basis(), Vector3(0, 0.5, 0)), RIBBON_RED)
	for sx in [-1.0, 1.0]:
		m.add(NV._sph(0.06, 4, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.6)), Vector3(float(sx) * 0.08, 0.53, r0 + 0.02)), RIBBON_RED.lightened(0.1))
	# the spout and the tin pail under it
	m.add(NV._cyl(0.03, 0.035, 0.2, 6), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(80.0)), Vector3(0, 0.42, r0 + 0.07)), Palette.WOOD_LIGHT)
	m.add(NV._cyl(0.1, 0.08, 0.16, 10), Transform3D(Basis(), Vector3(0, 0.19, r0 + 0.2)), TIN)
	m.add(NV._cyl(0.105, 0.105, 0.02, 10), Transform3D(Basis(), Vector3(0, 0.27, r0 + 0.2)), TIN.darkened(0.3))
	m.add(NV._cyl(0.084, 0.084, 0.02, 10), Transform3D(Basis(), Vector3(0, 0.12, r0 + 0.2)), TIN.darkened(0.3))
	return _commit(key, m)


## The renewable part of a sap stump: resin beads on the bark and the pail filled to the brim (hidden while the
## sap gathers again).
static func sap_resin(variant: int) -> ArrayMesh:
	var key := "sapresin|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8200 + variant
	var r0 := STUMP_R + 0.03 * float(posmod(variant, 3) - 1)
	var m := NV.Merger.new()
	for i in 3:
		var a := PI * 0.5 + rng.randf_range(-0.9, 0.9)
		var p := Vector3(cos(a) * r0 * 0.98, rng.randf_range(0.28, 0.46), sin(a) * r0 * 0.98)
		m.add(NV._sph(0.045, 5, 8), Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.7, 2.2, 1.0)), p), RESIN)
	m.add(NV._sph(0.035, 5, 8), Transform3D(Basis().scaled(Vector3(1, 1.4, 1)), Vector3(0, 0.36, r0 + 0.16)), RESIN)
	m.add(NV._cyl(0.088, 0.088, 0.03, 10), Transform3D(Basis(), Vector3(0, 0.255, r0 + 0.2)), RESIN)
	m.add(NV._sph(0.05, 5, 8), Transform3D(Basis().scaled(Vector3(1.2, 0.6, 1.2)), Vector3(0.03, 0.275, r0 + 0.19)), RESIN.lightened(0.2))
	return _commit(key, m)


## Glossy amber resin (a little self-lit so the full pail reads at dusk).
static func resin_material() -> Material:
	if _cache.has("mat_resin"):
		return _cache["mat_resin"]
	var mat := Mat.outlined(Mat.toon(RESIN, {"rim": 0.6, "specular": 0.8, "emission": RESIN_DARK, "emission_energy": 0.25}), 0.008)
	_cache["mat_resin"] = mat
	return mat


## Wild sunflax: a clump of slender stems (stays) ...
static func sunflax_stems(variant: int) -> ArrayMesh:
	var key := "sflxstem|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8300 + variant
	var m := NV.Merger.new()
	for i in 14:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.0, 0.3)
		var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, rng.randf_range(0.04, 0.22))
		var h := rng.randf_range(0.6, 0.95)
		m.add(NV._cyl(0.01, 0.016, h, 4), Transform3D(tilt, Vector3(cos(a) * rr, 0.0, sin(a) * rr) + tilt * Vector3(0, h * 0.5, 0)), SUNFLAX_STEM.lerp(STRAW, rng.randf() * 0.35))
	return _commit(key, m)


## ... and its golden seed heads (the pickable part; same RNG stream as the stems so each head tops a stem).
static func sunflax_heads(variant: int) -> ArrayMesh:
	var key := "sflxhead|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8300 + variant
	var m := NV.Merger.new()
	for i in 14:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.0, 0.3)
		var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, rng.randf_range(0.04, 0.22))
		var h := rng.randf_range(0.6, 0.95)
		rng.randf()
		var tip := Vector3(cos(a) * rr, 0.0, sin(a) * rr) + tilt * Vector3(0, h, 0)
		m.add(NV._sph(0.045, 4, 6), Transform3D(Basis().scaled(Vector3(1.3, 0.7, 1.3)), tip), SUNFLAX_GOLD)
		if i % 3 == 0:
			m.add(NV._sph(0.028, 3, 5), Transform3D(Basis(), tip + Vector3(0, 0.035, 0)), Color("fff1b0"))
	return _commit(key, m)


## Stems and heads of wild sunflax share this swaying, outline-free vertex-coloured toon (same wind, so the golden
## heads stay on their stems; an outline would make 1.5 cm stems look like black wire).
static func sunflax_material() -> Material:
	return Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.3, "wind": 0.05, "wind_height": 1.0})
