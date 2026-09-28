extends RefCounted
## Shared helpers for Krystal's avatar part builders (src/player/avatar/*.gd): her toon materials, node and
## part placement, the lantern mesh and the procedural cloth meshes (skirt panels, capes, brims).
## Everything is static and cached; materials come from Mat (shared by colour, never mutated - never call
## set_shader_parameter on them), meshes from Kit or the local cache below.
## Builders receive a context Dictionary from krystal_avatar.gd:
##   ctx["box"]: Callable(host_key: String) -> Node3D   the builder's slot container on that rig host
##   ctx["col"]: resolved colours (look_colors.gd resolve()), ctx["look"]: the sanitized look,
##   ctx["id"]: the part id being built, plus a few flags: hides_hair, hat (hat or head armor id), head_armor ("helm" /
##   "hood" / ""), hair_acc, back_pack (a bulky pack the hair drapes over), armor_body (body armor shown), upper (the top
##   a cape is worn over) and hair_prims (the static hair parts for hair_builder.gd reach(): pieces sit ON the hair).
## Host keys: hips, leg0, leg1, knee0, knee1, spine, chest, sh0, sh1, el0, el1, hand0, hand1, head_c, eye0, eye1,
## brow0, brow1 (0 = +X = Krystal's left, 1 = -X = right / tool hand). Containers sit at the host origin with an
## identity transform, so a part's position is in the host joint's space (the model faces +Z).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const OUTLINE := 0.011
const FILL := 0.07
const BRASS := Color("e0b85a")
## Chapter One shade pairs (exact): the legacy jacket cuffs / pocket flaps and scarf tips.
const LEGACY_SHADES := {"3fa7a0": Color("2e8781"), "f2c14e": Color("d9a53a")}

static var _cache: Dictionary = {}


## Krystal's toon material (same parameters as the Chapter One avatar): faint self-fill, optional outline.
static func m(c: Color, outline: bool = true, thick: float = OUTLINE) -> Material:
	var base := Mat.toon(c, {"rim": 0.42, "noise": 0.04, "emission": c, "emission_energy": FILL})
	return Mat.outlined(base, thick) if outline else base


## Flat face/detail material (no rim, no noise, no outline).
static func flat(c: Color) -> Material:
	return Mat.toon(c, {"rim": 0.0, "noise": 0.0, "emission": c, "emission_energy": FILL})


## Polished metal (armor plates, buckles on armor): stronger rim + a little specular.
static func metal(c: Color, thick: float = OUTLINE) -> Material:
	return Mat.outlined(Mat.toon(c, {"rim": 0.7, "noise": 0.02, "specular": 0.45, "emission": c, "emission_energy": FILL}), thick)


## Soft self-lit cloth (ghost-light wings / tulle sparkle): brighter fill, thin outline.
static func softglow(c: Color, energy: float = 0.3) -> Material:
	return Mat.outlined(Mat.toon(c, {"rim": 0.6, "noise": 0.0, "emission": c, "emission_energy": energy}), 0.006)


## Darker shade of a cloth colour (cuffs, flaps, hem shadows). The Chapter One colours map to their exact
## original shades so the legacy look is reproduced bit for bit.
static func shade(c: Color, amount: float = 0.22) -> Color:
	var key := c.to_html(false)
	if LEGACY_SHADES.has(key):
		return LEGACY_SHADES[key]
	return Color.from_hsv(c.h, minf(1.0, c.s * 1.08 + 0.03), c.v * (1.0 - amount), c.a)


static func lighten(c: Color, amount: float = 0.25) -> Color:
	return c.lerp(Color.WHITE, amount)


static func node(parent: Node3D, pos: Vector3, nm: String = "") -> Node3D:
	var n := Node3D.new()
	if nm != "":
		n.name = nm
	parent.add_child(n)
	n.position = pos
	return n


static func part(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	Kit.add(parent, mi, pos, rot_deg, scl)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A spring chain record animated by the avatar's secondary motion (krystal_avatar.gd _update_secondary):
##   kind "braid" - the Chapter One braid spring (hair: braids, ponytails, curtains, ribbon tails)
##   kind "scarf" - the explorer scarf ends (segs = [root, tip], `i` = end index)
##   kind "cape"  - capes / shawls hanging from the chest (flare backwards, never into the back)
##   kind "wing"  - gentle flapping wings (rotation about Y)
## segs: the animated nodes (parent first), rest: their rest rotations, k / d: spring stiffness / damping,
## amp: angle multiplier, side: lateral sign.
static func chain(kind: String, segs: Array, rest: Array, k: float, d: float, amp: float = 1.0, side: float = 1.0) -> Dictionary:
	return {"kind": kind, "segs": segs, "rest": rest, "k": k, "d": d, "amp": amp, "side": side,
		"ang": Vector2.ZERO, "vel": Vector2.ZERO, "i": 0}


## A part placed with a full transform (static nested pieces composed into one node so they bake together).
static func part_xf(parent: Node3D, mi: MeshInstance3D, xf: Transform3D, shadow: bool = true) -> MeshInstance3D:
	parent.add_child(mi)
	mi.transform = xf
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A MeshInstance3D with a cached custom mesh.
static func mesh_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return part(parent, mi, pos, rot_deg, scl, shadow)


## The explorer's lantern (hangs below its origin: handle ring, roof, glass, base). Shadows off.
static func lantern_mesh(root: Node3D, lit: bool) -> void:
	var frame := m(Palette.MINE_TIMBER, true, 0.008)
	var brass := m(BRASS, true, 0.008)
	var glass: Material = Mat.glow(Palette.LANTERN_GLOW, 2.2) if lit else m(Color("e8d9b0"), true, 0.008)
	var parts: Array[MeshInstance3D] = []
	parts.append(part(root, Kit.torus(0.022, 0.034, brass), Vector3(0, 0.0, 0), Vector3(90, 0, 0)))
	parts.append(part(root, Kit.cone(0.07, 0.06, frame, 12), Vector3(0, -0.055, 0)))
	parts.append(part(root, Kit.cylinder(0.05, 0.055, 0.1, glass, 12), Vector3(0, -0.13, 0)))
	parts.append(part(root, Kit.cylinder(0.066, 0.066, 0.025, frame, 12), Vector3(0, -0.19, 0)))
	parts.append(part(root, Kit.sphere(0.018, brass, 8, 10), Vector3(0, -0.02, 0)))
	for p in parts:
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Small smile / curl: a tube bent into a U (cached ArrayMesh; identical to the Chapter One mesh).
static func arc_mesh(radius: float, tube: float, angle: float) -> ArrayMesh:
	var key := "arc|%.4f|%.4f|%.3f" % [radius, tube, angle]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var segs := 8
	var pts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in rings + 1:
		var a := -angle * 0.5 + angle * float(i) / float(rings)
		var c := Vector3(sin(a) * radius, radius - cos(a) * radius, 0.0)
		var n_in := Vector3(-sin(a), cos(a), 0.0)
		for j in segs:
			var b := TAU * float(j) / float(segs)
			var n := n_in * cos(b) + Vector3(0, 0, 1) * sin(b)
			pts.append(c + n * tube)
			norms.append(n)
	for i in rings:
		for j in segs:
			var a0 := i * segs + j
			var a1 := i * segs + (j + 1) % segs
			var b0 := (i + 1) * segs + j
			var b1 := (i + 1) * segs + (j + 1) % segs
			for idx in [a0, b0, a1, a1, b0, b1]:
				st.set_normal(norms[idx])
				st.add_vertex(pts[idx])
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A thin cloth panel (closed shell, so it reads from both sides) hanging from its origin along -Y, facing +Z:
## width w_top at the top -> w_bot at the hem, `length` long, curved around a vertical axis behind it with radius
## r_top -> r_bot (panels on a skirt ring / a cape around the back), `thick` thick (inward), with `pleats` soft
## folds of depth `pleat_amp`. Front faces are clockwise (Godot's convention). Cached by parameters.
static func panel_mesh(w_top: float, w_bot: float, length: float, r_top: float, r_bot: float, thick: float = 0.01,
		pleats: int = 0, pleat_amp: float = 0.0) -> ArrayMesh:
	var key := "panel|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%d|%.3f" % [w_top, w_bot, length, r_top, r_bot, thick, pleats, pleat_amp]
	if _cache.has(key):
		return _cache[key]
	var nu := 6 if pleats == 0 else maxi(6, pleats * 4)
	var nv := 4
	var outer := PackedVector3Array()
	for j in nv + 1:
		var v := float(j) / float(nv)
		var half := lerpf(w_top, w_bot, v) * 0.5
		var r := maxf(lerpf(r_top, r_bot, v), 0.05)
		for i in nu + 1:
			var u := float(i) / float(nu)
			var x := (u * 2.0 - 1.0) * half
			var z := -x * x / (2.0 * r)
			if pleats > 0:
				z += pleat_amp * cos(u * float(pleats) * TAU) * sqrt(v)
			outer.append(Vector3(x, -v * length, z))
	# per-vertex normals of the outer surface from the grid tangents
	var nrm := PackedVector3Array()
	nrm.resize(outer.size())
	for j in nv + 1:
		for i in nu + 1:
			var k := j * (nu + 1) + i
			var du := outer[j * (nu + 1) + mini(i + 1, nu)] - outer[j * (nu + 1) + maxi(i - 1, 0)]
			var dv := outer[mini(j + 1, nv) * (nu + 1) + i] - outer[maxi(j - 1, 0) * (nu + 1) + i]
			var n := dv.cross(du).normalized()   # +Z-ish for a panel hanging down (-Y) and spanning +X
			if n.z < 0.0:
				n = -n
			nrm[k] = n
	var inner := PackedVector3Array()
	inner.resize(outer.size())
	for k in outer.size():
		inner[k] = outer[k] - nrm[k] * thick
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + (nu + 1)
			var d := c + 1
			_tri(st, outer, nrm, a, b, c, false)
			_tri(st, outer, nrm, b, d, c, false)
			_tri(st, inner, nrm, a, b, c, true)
			_tri(st, inner, nrm, b, d, c, true)
	# rims: left, right, top, bottom edges joining the two surfaces
	for j in nv:
		_edge(st, outer, inner, j * (nu + 1), (j + 1) * (nu + 1), Vector3(-1, 0, 0))
		_edge(st, outer, inner, (j + 1) * (nu + 1) + nu, j * (nu + 1) + nu, Vector3(1, 0, 0))
	for i in nu:
		_edge(st, outer, inner, i + 1, i, Vector3(0, 1, 0))
		_edge(st, outer, inner, nv * (nu + 1) + i, nv * (nu + 1) + i + 1, Vector3(0, -1, 0))
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## One surface triangle with the given vertex normals; `back` flips it (inner surface faces -normal).
static func _tri(st: SurfaceTool, pts: PackedVector3Array, nrm: PackedVector3Array, a: int, b: int, c: int, back: bool) -> void:
	var order := [a, c, b] if back else [a, b, c]
	var want := -1.0 if back else 1.0
	# clockwise front faces: (p1 - p0) x (p2 - p0) must point AWAY from the facing normal
	var p0: Vector3 = pts[order[0]]
	var g := (pts[order[1]] - p0).cross(pts[order[2]] - p0)
	if g.dot(nrm[a] * want) > 0.0:
		order = [order[0], order[2], order[1]]
	for idx in order:
		st.set_normal(nrm[idx] * want)
		st.add_vertex(pts[idx])


## A quad between two outer vertices (o0 -> o1) and their inner twins, facing `out`.
static func _edge(st: SurfaceTool, outer: PackedVector3Array, inner: PackedVector3Array, o0: int, o1: int, out: Vector3) -> void:
	var quad := [outer[o0], outer[o1], inner[o1], inner[o0]]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var p0: Vector3 = quad[tri[0]]
		var p1: Vector3 = quad[tri[1]]
		var p2: Vector3 = quad[tri[2]]
		var g := (p1 - p0).cross(p2 - p0)
		var face := out
		if g.length_squared() > 0.0000001:
			face = -g.normalized()
			if face.dot(out) < 0.0:
				var t := p1
				p1 = p2
				p2 = t
				face = -face
		for p in [p0, p1, p2]:
			st.set_normal(face)
			st.add_vertex(p)
