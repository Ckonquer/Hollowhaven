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

## Vertical squash of pumpkin_body(variant).
static func pumpkin_squash(variant: int) -> float:
	return 0.78 + 0.06 * float(posmod(variant, 3))


## The ellipsoids that make up pumpkin_body(variant) (radius 1): each Transform3D maps the unit sphere onto one
## part (8 ribs + the core). The mesh and the rind queries below share them, so carved faces and mimic tells are
## always placed ON the rind, never inside it.
static func pumpkin_ellipsoids(variant: int) -> Array:
	var key := "pell|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var squash := pumpkin_squash(variant)
	var out: Array = []
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2 * float(variant)
		out.append(Transform3D(rs(-a, Vector3(0.62, 0.72 * squash, 0.5)), Vector3(cos(a) * 0.42, 0.72 * squash, sin(a) * 0.42)))
	out.append(Transform3D(Basis.from_scale(Vector3(0.82, 0.82 * squash, 0.82)), Vector3(0, 0.72 * squash, 0)))
	_cache[key] = out
	return out


## A ribbed pumpkin of radius 1 (base at y = 0) without its stem. lo/hi = bottom/top colours.
static func pumpkin_body(variant: int, lo: Color = PUMPKIN_DEEP, hi: Color = PUMPKIN) -> ArrayMesh:
	var key := "pbody|%d|%s|%s" % [variant, lo.to_html(), hi.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var squash := pumpkin_squash(variant)
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var t := clampf(p.y / (1.5 * squash), 0.0, 1.0)
		var c := lo.lerp(hi, t)
		return c.lerp(hi.lightened(0.18), clampf(n.y, 0.0, 1.0) * 0.25)
	for e in pumpkin_ellipsoids(variant):
		m.add(NV._sph(1.0, 8, 12), e, fn)
	return _commit(key, m)


## Height of the top of pumpkin_body(variant) (radius 1): where its stem sits.
static func pumpkin_top(variant: int) -> float:
	return 1.44 * pumpkin_squash(variant) - 0.04


## True when `p` (radius-1 space) is inside the rind of pumpkin_body(variant) (inside any of its ellipsoids).
static func pumpkin_inside(variant: int, p: Vector3) -> bool:
	for e in pumpkin_ellipsoids(variant):
		if ((e as Transform3D).affine_inverse() * p).length() < 1.0:
			return true
	return false


## Where a ray from `from` (inside the pumpkin) along the unit `dir` leaves the rind: the outermost crossing of
## any of its ellipsoids, {"p": point, "n": outward normal} in radius-1 space ({} if the ray misses).
static func pumpkin_hit(variant: int, from: Vector3, dir: Vector3) -> Dictionary:
	var best := -INF
	var best_e := Transform3D()
	for e in pumpkin_ellipsoids(variant):
		var inv := (e as Transform3D).affine_inverse()
		var u0 := inv * from
		var d := inv.basis * dir
		var qa := d.dot(d)
		var qb := 2.0 * u0.dot(d)
		var qc := u0.dot(u0) - 1.0
		var disc := qb * qb - 4.0 * qa * qc
		if disc < 0.0 or qa < 0.000001:
			continue
		var t := (-qb + sqrt(disc)) / (2.0 * qa)
		if t > best:
			best = t
			best_e = e
	if best == -INF:
		return {}
	var p := from + dir * best
	var u := best_e.affine_inverse() * p
	return {"p": p, "n": (best_e.basis.inverse().transposed() * u).normalized()}


## A detail's transform on the rind: `theta` = azimuth from +Z (radians, + toward +X), `y` = height, lifted
## `lift` along the rind normal; local +Z = the normal (out of the pumpkin), X along the rind, rolled `roll_deg`.
static func on_rind(variant: int, theta: float, y: float, lift: float = 0.0, roll_deg: float = 0.0) -> Transform3D:
	var dir := Vector3(sin(theta), 0.0, cos(theta))
	var h := pumpkin_hit(variant, Vector3(0, y, 0), dir)
	var p: Vector3 = h.get("p", Vector3(0, y, 0) + dir)
	var n: Vector3 = h.get("n", dir)
	var x := Vector3.UP.cross(n).normalized()
	var up := n.cross(x).normalized()
	return Transform3D(Basis(x, up, n) * Basis(Vector3.BACK, deg_to_rad(roll_deg)), p + n * lift)


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


const FACE_DEPTH := 0.1
const FACE_LIFT := 0.012

## Carved face pieces of pumpkin_body(variant) on its +Z side: [[mesh, Transform3D]] (radius 1). Every piece sits
## on the rind: its front is FACE_DEPTH / 2 + FACE_LIFT proud of the ellipsoid surface, its back sunk into it.
static func carved_face_parts(variant: int) -> Array:
	var key := "faceparts|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var sq := pumpkin_squash(variant)
	var yc := 0.72 * sq
	var out: Array = []
	# two big upright triangle eyes, tilted a little toward the nose
	for sx in [-1.0, 1.0]:
		out.append([_prism(Vector3(0.27, 0.25, FACE_DEPTH)), on_rind(variant, float(sx) * 0.36, yc + 0.24 * sq, FACE_LIFT, float(sx) * -12.0)])
	# a small triangle nose
	out.append([_prism(Vector3(0.13, 0.12, FACE_DEPTH)), on_rind(variant, 0.0, yc + 0.03 * sq, FACE_LIFT)])
	# a wide grin; two teeth hang from its top edge (shorter cut segments)
	var n := 7
	for i in n:
		var t := float(i) / float(n - 1)
		var th := lerpf(-0.52, 0.52, t)
		var y := yc - 0.18 * sq - sin(t * PI) * 0.1
		var slope := rad_to_deg(atan2(-0.1 * PI * cos(t * PI), 1.0))
		var hgt := 0.08 if i == 2 or i == 4 else 0.13
		out.append([NV._box(Vector3(0.18, hgt, FACE_DEPTH)), on_rind(variant, th, y - (0.13 - hgt) * 0.5, FACE_LIFT, slope)])
	_cache[key] = out
	return out


## Carved friendly face (eyes, nose, toothy grin) on the +Z side of pumpkin_body(variant); use carved_material()
## (a dark cut by day that glows at night).
static func carved_face(variant: int = 1) -> ArrayMesh:
	var key := "face|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	for part in carved_face_parts(variant):
		m.add(part[0], part[1], Color.WHITE)
	return _commit(key, m)


const MIMIC_SEAM := Color("3a150c")

## The mimic's tells on pumpkin_body(variant) (radius 1), dark and ON the rind: a jagged seam of a mouth pressed
## shut and two sleepy closed eyes with lashes, [[mesh, Transform3D]] (the vine feet are added by mimic_details()).
static func mimic_tell_parts(variant: int) -> Array:
	var key := "mimicparts|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var sq := pumpkin_squash(variant)
	var yc := 0.72 * sq
	var out: Array = []
	# the seam: one continuous zig-zag of thin strokes joining alternate high / low points
	var pts: Array = []
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector2(lerpf(-0.62, 0.62, t), yc - 0.16 * sq + (0.04 if i % 2 == 0 else -0.04)))
	out.append_array(_rind_strokes(variant, pts, 0.045))
	# two sleepy closed eyes: smooth lid arcs, ends a little higher than the middle
	for sx in [-1.0, 1.0]:
		var arc: Array = []
		for k in 5:
			var u := float(k - 2) / 2.0
			arc.append(Vector2(float(sx) * 0.34 + u * 0.13, yc + 0.24 * sq + u * u * 0.05))
		out.append_array(_rind_strokes(variant, arc, 0.04))
	_cache[key] = out
	return out


## Thin dark strokes on the rind joining consecutive (azimuth, height) points: [[mesh, Transform3D]].
static func _rind_strokes(variant: int, pts: Array, width: float) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var mid := (a + b) * 0.5
		var dx := (b.x - a.x) * 0.95          # ~ metres along the rind (radius ~0.95 at the face)
		var dy := b.y - a.y
		var ln := sqrt(dx * dx + dy * dy) + width * 0.9
		out.append([NV._box(Vector3(ln, width, 0.06)), on_rind(variant, mid.x, mid.y, FACE_LIFT, rad_to_deg(atan2(dy, dx)))])
	return out


## The mimic's tells: a jagged closed seam of a mouth, sleepy closed eyes and stubby vine feet, for
## pumpkin_body(variant) (use the body's transform, so they stay on its rind).
static func mimic_details(variant: int = 2) -> ArrayMesh:
	var key := "mimic_det|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	for part in mimic_tell_parts(variant):
		m.add(part[0], part[1], MIMIC_SEAM)
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		m.add(NV._cyl(0.07, 0.1, 0.28, 6), xf(Vector3(cos(a) * 0.72, 0.06, sin(a) * 0.72), Vector3(0, 0, 70.0)).rotated_local(Vector3.UP, -a), VINE_DARK)
	return _commit(key, m)


# --- Carved faces and candle halos by day and night ---------------------------------------------------------------

const FACE_CUT := Color("2b130b")       # the dark cut interior (day)
const FACE_GLOW := Color("ffb347")      # candle-lit (night)
const HALO_WARM := Color("ffb45e")
static var _night: float = 0.0


## 0 (day) .. 1 (night), as last set by set_daylight() (smoothstep of the sky's daylight).
static func night_amount() -> float:
	return _night


## Called by the region a few times a second with the sky's daylight (0 night .. 1 day). Every carved face shares
## one material: a dark cut by day, a warm glow at night; candle halos brighten the same way.
static func set_daylight(daylight: float) -> void:
	var t := clampf((0.62 - daylight) / 0.47, 0.0, 1.0)
	var night := t * t * (3.0 - 2.0 * t)
	if absf(night - _night) < 0.004:
		return
	_night = night
	if _cache.has("mat_carved"):
		_apply_carved(_cache["mat_carved"], night)
	if _cache.has("mat_halo"):
		_apply_halo(_cache["mat_halo"], night)


## Unshaded, so the cut reads as a hole by day (no light on it) and as a warm glow at night (emission > 1.2
## blooms). Shared by the Pumpkin That Turned and the Commons jack-o'-lanterns.
static func carved_material() -> StandardMaterial3D:
	if _cache.has("mat_carved"):
		return _cache["mat_carved"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = FACE_GLOW
	_apply_carved(m, _night)
	_cache["mat_carved"] = m
	return m


static func _apply_carved(m: StandardMaterial3D, night: float) -> void:
	m.albedo_color = FACE_CUT.lerp(FACE_GLOW, night)
	m.emission_energy_multiplier = 1.7 * night


## A soft additive glow card that always faces the camera (candle flames, lantern glass). Unit quad: scale it.
static func halo_mesh() -> Mesh:
	if not _cache.has("halo_mesh"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_cache["halo_mesh"] = q
	return _cache["halo_mesh"]


## Shared warm halo: faint by day, full at night (set_daylight). A generated radial gradient, no image files.
static func halo_material() -> StandardMaterial3D:
	if _cache.has("mat_halo"):
		return _cache["mat_halo"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = tex
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.25
	m.disable_receive_shadows = true
	_apply_halo(m, _night)
	_cache["mat_halo"] = m
	return m


## A soft round warm-light footprint for glow decals (emission: white centre fading to black at the rim).
static func pool_texture() -> Texture2D:
	if _cache.has("pool_tex"):
		return _cache["pool_tex"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(0, 0, 0, 1))
	g.add_point(0.45, Color(0.5, 0.5, 0.5, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_cache["pool_tex"] = tex
	return tex


static func _apply_halo(m: StandardMaterial3D, night: float) -> void:
	var c := HALO_WARM
	c.a = lerpf(0.18, 0.85, night)
	m.albedo_color = c


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


const HEDGE_LUMP := 0.25
const HEDGE_SQUASH := 0.8
const BERRY_R := 0.082

## The three unit blobs of hedge(variant): [ublob seed, scale, centre].
static func hedge_blobs(variant: int) -> Array:
	return [[variant, 0.62, Vector3(-0.5, 0.55, 0)], [variant + 1, 0.72, Vector3(0.1, 0.62, 0.05)], [variant + 2, 0.58, Vector3(0.68, 0.5, -0.05)]]


static func hedge(variant: int) -> ArrayMesh:
	var key := "hedge|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	var fn := _grad(Color("355f33"), Color("6d9b4c"), 1.3)
	for b in hedge_blobs(variant):
		m.add(NV.ublob(int(b[0]), HEDGE_LUMP, HEDGE_SQUASH, 2), NV.sxf(float(b[1]), b[2]), fn)
	return _commit(key, m)


## Surface radius of the unit blob NV.ublob(seed, lump, ...) along the unit direction `d` (Kit.blob_mesh noise;
## the mesh's squash is applied on top of it).
static func blob_radius(seed_value: int, lump: float, d: Vector3) -> float:
	var key := "bnoise|%d" % seed_value
	if not _cache.has(key):
		var nz := FastNoiseLite.new()
		nz.seed = 700 + posmod(seed_value, 8)
		nz.frequency = 1.3
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_cache[key] = nz
	return 1.0 + (_cache[key] as FastNoiseLite).get_noise_3dv(d) * lump


## How far `p` (hedge space) lies outside the leaf blobs of hedge(variant), in metres (negative = inside).
static func hedge_clearance(variant: int, p: Vector3) -> float:
	var best := INF
	for b in hedge_blobs(variant):
		var s := float(b[1])
		var q: Vector3 = (p - (b[2] as Vector3)) / s
		q.y /= HEDGE_SQUASH
		var ln := q.length()
		if ln < 0.0001:
			return -s
		var r := blob_radius(int(b[0]), HEDGE_LUMP, q / ln)
		best = minf(best, (ln - r) * s)
	return best


## Berry centres ON the leaves of hedge(variant): each is projected onto a blob's surface (its own noise radius)
## and pushed out by 60 % of a berry, and never lands inside a neighbouring blob or down in the grass.
static func berry_points(variant: int, count: int = 18) -> Array:
	var key := "berrpts|%d|%d" % [variant, count]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + variant
	var blobs := hedge_blobs(variant)
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var b: Array = blobs[out.size() % blobs.size()]
		var s := float(b[1])
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.15, 1.0), rng.randf_range(-1, 1)).normalized()
		var r := blob_radius(int(b[0]), HEDGE_LUMP, d)
		var surf: Vector3 = (b[2] as Vector3) + Vector3(d.x * r, d.y * r * HEDGE_SQUASH, d.z * r) * s
		var nrm := Vector3(d.x, d.y / HEDGE_SQUASH, d.z).normalized()
		var p := surf + nrm * BERRY_R * 0.6
		if p.y < 0.28 or hedge_clearance(variant, p) < BERRY_R * 0.35:
			continue
		var crowded := false
		for q in out:
			if (q as Vector3).distance_to(p) < BERRY_R * 2.4:
				crowded = true
				break
		if not crowded:
			out.append(p)
	_cache[key] = out
	return out


static func berry_clusters(variant: int, color: Color, count: int = 18) -> ArrayMesh:
	var key := "berr|%d|%s|%d" % [variant, color.to_html(), count]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5350 + variant
	var m := NV.Merger.new()
	var fn := func(_q: Vector3, n: Vector3) -> Color:
		return color.lerp(Color("ffc2d6"), clampf(n.y, 0.0, 1.0) * 0.45)
	for p in berry_points(variant, count):
		m.add(NV._sph(BERRY_R, 5, 8), Transform3D(Basis(), p), fn)
		if rng.randf() < 0.35:
			# a little glossy highlight berry beside it (a cluster of two)
			m.add(NV._sph(BERRY_R * 0.7, 4, 7), Transform3D(Basis(), (p as Vector3) + Vector3(rng.randf_range(-1, 1), 0.4, rng.randf_range(-1, 1)).normalized() * BERRY_R * 1.1), color.lightened(0.15))
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


## A chunky rectangular hay bale (1.25 x 0.6 x 0.82, top at 0.6) with soft rounded edges, two twine bands wrapped
## round it and a few loose straws poking out of the ends.
static func hay_bale() -> ArrayMesh:
	if _cache.has("bale"):
		return _cache["bale"]
	var m := NV.Merger.new()
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var c := STRAW_DARK.lerp(STRAW, clampf(p.y / 0.6, 0.0, 1.0))
		return c.lerp(Color("f3d98a"), clampf(n.y, 0.0, 1.0) * 0.3)
	var s := Vector3(1.25, 0.6, 0.82)
	var r := 0.09
	# a rounded box: three crossed slabs + edge rolls
	m.add(NV._box(Vector3(s.x, s.y - r * 2.0, s.z)), Transform3D(Basis(), Vector3(0, s.y * 0.5, 0)), fn)
	m.add(NV._box(Vector3(s.x - r * 2.0, s.y, s.z - r * 2.0)), Transform3D(Basis(), Vector3(0, s.y * 0.5, 0)), fn)
	for sy in [r, s.y - r]:
		for sz in [-1.0, 1.0]:
			m.add(NV._cyl(r, r, s.x - r * 2.0, 8), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, float(sy), float(sz) * (s.z * 0.5 - r))), fn)
		for sx in [-1.0, 1.0]:
			m.add(NV._cyl(r, r, s.z - r * 2.0, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(float(sx) * (s.x * 0.5 - r), float(sy), 0)), fn)
	# twine bands
	for x in [-0.3, 0.3]:
		m.add(NV._box(Vector3(0.045, s.y + 0.02, s.z + 0.02)), Transform3D(Basis(), Vector3(float(x), s.y * 0.5, 0)), Color("8a6a3a"))
	# loose straws on the ends and the top
	var rng := RandomNumberGenerator.new()
	rng.seed = 5602
	for i in 10:
		var sx2 := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(sx2 * (s.x * 0.5 + 0.02), rng.randf_range(0.12, s.y - 0.1), rng.randf_range(-0.3, 0.3))
		m.add(NV._box(Vector3(0.12, 0.012, 0.012)), xf(p, Vector3(0, rng.randf_range(-30, 30), rng.randf_range(-35, 35))), STRAW.lightened(0.1))
	for i in 5:
		m.add(NV._box(Vector3(0.012, 0.012, 0.16)), xf(Vector3(rng.randf_range(-0.5, 0.5), s.y + 0.005, rng.randf_range(-0.3, 0.3)), Vector3(0, rng.randf_range(0, 180), 0)), STRAW.lightened(0.15))
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
	m.add(NV._sph(0.21, 8, 12), Transform3D(Basis().scaled(Vector3(1.0, 1.05, 0.95)), Vector3(0, 1.43, 0)), Color("e8d2a6"))
	# a friendly sack face that reads at play distance: two plum buttons with cream cross-stitches, rosy cheeks
	# and one soft stitched smile (no stitch ticks: those read as teeth), all just proud of the sack
	for sx in [-1.0, 1.0]:
		m.add(NV._cyl(0.034, 0.034, 0.024, 10), xf(Vector3(float(sx) * 0.085, 1.475, 0.19), Vector3(90 - 12, float(sx) * 24.0, 0)), Color("5a3a66"))
		for cr in [45.0, -45.0]:
			m.add(NV._box(Vector3(0.04, 0.009, 0.01)), xf(Vector3(float(sx) * 0.087, 1.476, 0.204), Vector3(-12, float(sx) * 24.0, cr)), RIBBON_CREAM)
		m.add(NV._cyl(0.034, 0.034, 0.012, 8), xf(Vector3(float(sx) * 0.13, 1.4, 0.168), Vector3(90 - 5, float(sx) * 38.0, 0)), Color("f0a29a"))
	for i in 6:
		var t := (float(i) + 0.5) / 6.0
		var x := lerpf(-0.08, 0.08, t)
		var y := 1.385 - sin(t * PI) * 0.03
		var z := 0.2 - absf(x) * 0.3
		m.add(NV._box(Vector3(0.03, 0.012, 0.018)), xf(Vector3(x, y, z), Vector3(0, x * 250.0, rad_to_deg(atan2(-0.03 * PI * cos(t * PI), 0.16)))), PLUM)
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


## A ribbon streamer: two thin tails run from a knot at the origin along local +Y and curve gently away (three
## bent segments each, a notched tip); the toon wind (stronger further along +Y) flutters the ends. Flip it
## (rotate ~PI about a horizontal axis) for ribbons that hang from a knot and still flutter.
static func ribbon_strip(length: float = 0.7) -> ArrayMesh:
	var key := "ribbon|%.2f" % length
	if _cache.has(key):
		return _cache[key]
	var m := NV.Merger.new()
	for tail in [[1.0, 1.0, 0.0], [-1.0, 0.8, 0.012]]:
		var side := float(tail[0])
		var seg := length * float(tail[1]) / 3.0
		var p := Vector3(side * 0.02, 0.0, float(tail[2]))
		var ang := side * -8.0
		for k in 3:
			var a := deg_to_rad(ang)
			var dir := Vector3(-sin(a), cos(a), 0.0)
			var w := 0.05 - 0.008 * float(k)
			m.add(NV._box(Vector3(w, seg + 0.01, 0.008)), xf(p + dir * seg * 0.5, Vector3(0, float(k) * side * 9.0, ang)), Color.WHITE)
			p += dir * seg
			ang += side * -(9.0 + 6.0 * float(k))
		# the notched tip: two little points
		var a2 := deg_to_rad(ang)
		for s in [-1.0, 1.0]:
			m.add(_prism(Vector3(0.022, 0.05, 0.008)), xf(p + Vector3(-sin(a2), cos(a2), 0) * 0.02 + Vector3(cos(a2), sin(a2), 0) * float(s) * 0.012, Vector3(0, 0, ang)), Color.WHITE)
	m.add(NV._sph(0.035, 4, 6), Transform3D(Basis().scaled(Vector3(1.5, 0.9, 0.8)), Vector3.ZERO), Color.WHITE)
	return _commit(key, m)


## Torn coat on a post + a crossed rake: the Patchwalker field marker.
static func coat_post() -> ArrayMesh:
	if _cache.has("coatpost"):
		return _cache["coatpost"]
	var m := NV.Merger.new()
	var coat := Color("5f5a4a")
	m.add(NV._cyl(0.06, 0.08, 1.8, 6), xf(Vector3(0, 0.9, 0), Vector3(0, 0, 6)), FENCE_DARK)
	# a cross-bar for the shoulders and a torn old coat hung on it: rounded shoulders, a collar, two drooping
	# sleeves, a ragged hem, big stitched patches and buttons - a coat, not a board
	m.add(NV._cyl(0.025, 0.025, 0.9, 5), xf(Vector3(0.05, 1.55, 0), Vector3(0, 0, 90)), FENCE_DARK)
	m.add(NV._cyl(0.2, 0.3, 0.72, 8), Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.5)), Vector3(0.05, 1.16, 0.02)), coat)
	m.add(NV._sph(0.3, 5, 8), Transform3D(Basis().scaled(Vector3(1.25, 0.45, 0.55)), Vector3(0.05, 1.5, 0.02)), coat.lightened(0.05))
	m.add(NV._cyl(0.1, 0.16, 0.12, 8), Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.6)), Vector3(0.05, 1.62, 0.02)), coat.darkened(0.15))
	for sx in [-1.0, 1.0]:
		m.add(NV._cyl(0.07, 0.1, 0.62, 6), xf(Vector3(0.05 + float(sx) * 0.36, 1.23, 0.02), Vector3(0, 0, float(sx) * 12.0)), coat.darkened(0.08))
		m.add(NV._cyl(0.02, 0.08, 0.14, 6), xf(Vector3(0.05 + float(sx) * 0.42, 0.88, 0.02), Vector3(0, 0, float(sx) * 12.0)), STRAW)
	for i in 5:
		var hx := -0.2 + float(i) * 0.1
		m.add(_prism(Vector3(0.1, 0.12, 0.26)), xf(Vector3(0.05 + hx, 0.76, 0.02), Vector3(0, 0, 180)), coat)
	m.add(NV._box(Vector3(0.2, 0.22, 0.03)), xf(Vector3(-0.07, 0.98, 0.16), Vector3(-6, 0, -10)), Color("c98a3a"))
	m.add(NV._box(Vector3(0.16, 0.16, 0.03)), xf(Vector3(0.2, 1.3, 0.16), Vector3(-8, 0, 16)), RIBBON_PLUM)
	for i in 4:
		m.add(NV._box(Vector3(0.012, 0.05, 0.02)), xf(Vector3(-0.15 + float(i) * 0.055, 0.88, 0.175), Vector3(0, 0, 10)), RIBBON_CREAM)
	for i in 3:
		m.add(NV._sph(0.03, 3, 6), Transform3D(Basis().scaled(Vector3(1, 1, 0.5)), Vector3(0.07, 1.38 - float(i) * 0.17, 0.17)), RIBBON_GOLD)
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


## Candle flame: a warm ~7 cm teardrop standing on its base at the origin (put it on the wick); a glow material
## in a MultiMesh, with halo_mesh() cards around it for the night.
static func flame() -> ArrayMesh:
	if _cache.has("flame"):
		return _cache["flame"]
	var m := NV.Merger.new()
	m.add(NV._sph(0.024, 4, 7), Transform3D(Basis().scaled(Vector3(1.0, 1.1, 1.0)), Vector3(0, 0.024, 0)), Color.WHITE)
	m.add(NV._cyl(0.0, 0.023, 0.05, 7), Transform3D(Basis(), Vector3(0, 0.05, 0)), Color.WHITE)
	return _commit("flame", m)


## A candle-lit lantern globe (warm glass, a little faceted), centred on the origin, ~0.24 m tall.
static func lantern_globe() -> ArrayMesh:
	if _cache.has("lglobe"):
		return _cache["lglobe"]
	var m := NV.Merger.new()
	for i in 6:
		var a := TAU * float(i) / 6.0
		m.add(NV._sph(0.1, 5, 7), Transform3D(rs(-a, Vector3(0.6, 1.15, 0.55)), Vector3(cos(a) * 0.05, 0, sin(a) * 0.05)), Color.WHITE)
	return _commit("lglobe", m)


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


## A short, rough stone with a wide, shallow, open candle dish on its flat top (the groundskeeper's marker; the
## dish floor is at MARKER_DISH_Y, where her candle stands once it is lit).
const MARKER_DISH_Y := 0.74


static func marker_plinth() -> ArrayMesh:
	if _cache.has("plinth"):
		return _cache["plinth"]
	var m := NV.Merger.new()
	var fn := _grad(LILAC_STONE.darkened(0.28), LILAC_STONE.lightened(0.04), 0.7)
	# a short, rough stone narrowing to its top, on a mossy foot (like a little bird bath, not a pot)
	m.add(Kit.blob_mesh(0.42, 6702, 0.25, 0.32, 1), Transform3D(Basis(), Vector3(0, 0.04, 0)), Color("8a8398"))
	m.add_lumpy(NV._cyl(0.15, 0.27, 0.62, 8, 3), Transform3D(Basis(), Vector3(0, 0.31, 0)), fn, 0.06, Vector3.ZERO, 6701)
	m.add(Kit.blob_mesh(0.16, 6703, 0.3, 0.4, 1), Transform3D(Basis(), Vector3(0.26, 0.09, 0.14)), Palette.MOSS)
	m.add(NV._cyl(0.2, 0.17, 0.06, 10), Transform3D(Basis(), Vector3(0, 0.64, 0)), LILAC_STONE.lightened(0.06))
	# the dish: wide and shallow, overhanging the stone, a thin rolled rim and a dark empty floor
	m.add(NV._cyl(0.37, 0.2, 0.08, 18), Transform3D(Basis(), Vector3(0, MARKER_DISH_Y - 0.03, 0)), Color("c9b98f"))
	m.add(_torus(0.345, 0.385), Transform3D(Basis().scaled(Vector3(1.0, 0.55, 1.0)), Vector3(0, MARKER_DISH_Y + 0.012, 0)), Color("e3d6ae"))
	m.add(NV._cyl(0.34, 0.34, 0.01, 18), Transform3D(Basis(), Vector3(0, MARKER_DISH_Y + 0.006, 0)), Color("4f3f33"))
	# old wax drips over the rim
	for i in 3:
		var a := 0.6 + float(i) * 1.9
		m.add(NV._sph(0.028, 3, 5), Transform3D(Basis().scaled(Vector3(0.8, 1.7, 0.8)), Vector3(cos(a) * 0.37, MARKER_DISH_Y - 0.03, sin(a) * 0.37)), Color("f4ead2"))
	return _commit("plinth", m)


## The groundskeeper's little tin (note 2): a lidded box with a bright lid and a brass clasp on its +Z side.
static func tin_box() -> ArrayMesh:
	if _cache.has("tinbox"):
		return _cache["tinbox"]
	var m := NV.Merger.new()
	m.add(NV._box(Vector3(0.42, 0.18, 0.3)), Transform3D(Basis(), Vector3(0, 0.09, 0)), Color("8fa3ad"))
	m.add(NV._box(Vector3(0.45, 0.06, 0.33)), Transform3D(Basis(), Vector3(0, 0.2, 0)), Color("d7e4ea"))
	m.add(NV._box(Vector3(0.36, 0.015, 0.25)), Transform3D(Basis(), Vector3(0, 0.235, 0)), Color("b9ccd6"))
	m.add(NV._box(Vector3(0.08, 0.1, 0.03)), Transform3D(Basis(), Vector3(0, 0.15, 0.165)), RIBBON_GOLD)
	m.add(NV._box(Vector3(0.43, 0.02, 0.31)), Transform3D(Basis(), Vector3(0, 0.015, 0)), Color("5f7079"))
	# a corner of the folded note peeking out under the lid
	m.add(NV._box(Vector3(0.12, 0.012, 0.08)), xf(Vector3(0.12, 0.17, 0.17), Vector3(0, 12, 0)), Color("fbf3dc"))
	return _commit("tinbox", m)


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
