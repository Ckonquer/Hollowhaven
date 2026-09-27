extends Node3D
## Spider-themed set dressing with an arachnophobia-safe twin. Rooms register SPECS (webs, strands,
## egg sacs, cocoons, web sheets); build() creates exactly one variant:
##   normal:        cobwebs (below_web shader), silk strands, egg sacs, silk cocoons
##   arachnophobia: hanging pale roots, fungal strands with glowing bulbs, root knots, root pods
## Web-variant nodes are in group "below_web", root-variant nodes in "below_root". Switching the
## setting at runtime (Events.settings_changed "arachnophobia") frees one variant and builds the other.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const WEB_SHADER := preload("res://shaders/below_web.gdshader")

const PALE_ROOT := Color("cdbfa3")
const ROOT_DARK := Color("8a7560")
const FUNGAL := Color("e9e3d2")
const BULB := Color("d9f2c4")
const SAC := Color("ddd6e6")

var specs: Array = []
var arachno: bool = false
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {}

static var _cache: Dictionary = {}


func _ready() -> void:
	name = "SpiderDecor" if name == "" else name
	Events.settings_changed.connect(_on_settings_changed)


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia":
		build()


# --- Spec registration ---------------------------------------------------------------------------

## Cobweb quad centred at pos, facing `normal`, `size` metres across. density 0..1 (thin -> thick).
func add_web(pos: Vector3, normal: Vector3, size: float, density: float = 1.0, hub: Vector2 = Vector2(0.5, 0.5)) -> void:
	specs.append({"type": "web", "pos": pos, "normal": normal.normalized(), "size": size, "density": density, "hub": hub})


## Thread from a ceiling point down to a lower point.
func add_strand(top: Vector3, bottom: Vector3) -> void:
	specs.append({"type": "strand", "top": top, "bottom": bottom})


func add_egg_sac(pos: Vector3, size: float = 0.5) -> void:
	specs.append({"type": "egg_sac", "pos": pos, "size": size})


## Hanging cocoon: top = attachment point on the ceiling, length = drop.
func add_cocoon(top: Vector3, length: float, size: float = 0.45) -> void:
	specs.append({"type": "cocoon", "top": top, "length": length, "size": size})


## Web sheet stretched under a ceiling area (big, thin, shallow sag).
func add_sheet(center: Vector3, extent: Vector2, density: float = 1.0) -> void:
	specs.append({"type": "sheet", "pos": center, "extent": extent, "density": density})


# --- Build -----------------------------------------------------------------------------------------------

func build() -> void:
	arachno = bool(Settings.get_value("arachnophobia"))
	for c in get_children():
		c.queue_free()
		remove_child(c)
	_batches.clear()
	_rng.seed = 90210
	for s in specs:
		var t := String(s["type"])
		if arachno:
			match t:
				"web": _root_curtain(s)
				"strand": _root_tendril(s)
				"egg_sac": _root_knot(s)
				"cocoon": _root_pod(s)
				"sheet": _root_mat(s)
		else:
			match t:
				"web": _web(s)
				"strand": _strand(s)
				"egg_sac": _egg_sac(s)
				"cocoon": _cocoon(s)
				"sheet": _sheet(s)
	_flush()


func variant_group() -> String:
	return "below_root" if arachno else "below_web"


# --- Web variant ----------------------------------------------------------------------------------------------

static func web_material() -> ShaderMaterial:
	if not _cache.has("web_mat"):
		var m := ShaderMaterial.new()
		m.shader = WEB_SHADER
		m.set_shader_parameter("web_color", Palette.SILK_WEB)
		_cache["web_mat"] = m
	return _cache["web_mat"]


static func _quad() -> QuadMesh:
	if not _cache.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_cache["quad"] = q
	return _cache["quad"]


func _web(s: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad()
	mi.material_override = web_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var n: Vector3 = s["normal"]
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-n, up).rotated(n, _rng.randf_range(-0.5, 0.5))
	var sz: float = float(s["size"])
	mi.transform = Transform3D(basis.scaled_local(Vector3(sz, sz, 1.0)), s["pos"])
	mi.set_instance_shader_parameter("seed", _rng.randf_range(0.0, 100.0))
	mi.set_instance_shader_parameter("hub", s["hub"])
	mi.set_instance_shader_parameter("density", float(s["density"]))
	mi.add_to_group("below_web")
	add_child(mi)


func _sheet(s: Dictionary) -> void:
	var ext: Vector2 = s["extent"]
	var mi := MeshInstance3D.new()
	mi.mesh = _quad()
	mi.material_override = web_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var basis := Basis(Vector3(1, 0, 0), -PI * 0.5).rotated(Vector3.UP, _rng.randf() * TAU)
	var sz := maxf(ext.x, ext.y)
	mi.transform = Transform3D(basis.scaled_local(Vector3(sz, sz, 1.0)), s["pos"])
	mi.set_instance_shader_parameter("seed", _rng.randf_range(0.0, 100.0))
	mi.set_instance_shader_parameter("hub", Vector2(0.5, 0.5))
	mi.set_instance_shader_parameter("density", float(s["density"]))
	mi.add_to_group("below_web")
	add_child(mi)
	# a few sagging drips of silk under the sheet
	for i in 4:
		var p: Vector3 = s["pos"] + Vector3(_rng.randf_range(-ext.x, ext.x) * 0.35, 0.0, _rng.randf_range(-ext.y, ext.y) * 0.35)
		_line(p, p + Vector3(0, -_rng.randf_range(0.4, 1.2), 0), 0.006, _silk_mat(), "below_web")


func _strand(s: Dictionary) -> void:
	_line(s["top"], s["bottom"], 0.008, _silk_mat(), "below_web")


func _egg_sac(s: Dictionary) -> void:
	var p: Vector3 = s["pos"]
	var sz: float = float(s["size"])
	var mat := _sac_mat()
	for i in 5:
		var a := float(i) / 5.0 * TAU + _rng.randf() * 0.5
		var r := 0.0 if i == 0 else sz * 0.55
		var rr := sz * (0.55 if i == 0 else _rng.randf_range(0.3, 0.42))
		_batch(Kit.blob_mesh(1.0, 60 + i, 0.18, 1.0, 2), mat, Transform3D(Basis.IDENTITY.scaled_local(Vector3(rr, rr * 1.15, rr)), p + Vector3(cos(a) * r, rr * 0.9, sin(a) * r)), "below_web")
	for i in 5:
		var a := _rng.randf() * TAU
		_line(p + Vector3(0, sz * 0.9, 0), p + Vector3(cos(a) * sz * 1.4, 0.02, sin(a) * sz * 1.4), 0.006, _silk_mat(), "below_web")
	_batch(Kit.blob_mesh(1.0, 3, 0.2, 1.0, 1), Mat.glow(Palette.SILK_GLOW, 0.9), Transform3D(Basis.IDENTITY.scaled_local(Vector3.ONE * sz * 0.14), p + Vector3(sz * 0.2, sz * 1.25, sz * 0.1)), "below_web")


func _cocoon(s: Dictionary) -> void:
	var top: Vector3 = s["top"]
	var length: float = float(s["length"])
	var sz: float = float(s["size"])
	var body := top + Vector3(0, -length, 0)
	_line(top, body + Vector3(0, sz * 1.6, 0), 0.01, _silk_mat(), "below_web")
	var basis := Basis(Vector3(1, 0, 0), _rng.randf_range(-0.12, 0.12)).rotated(Vector3.UP, _rng.randf() * TAU)
	_batch(Kit.blob_mesh(1.0, 44, 0.16, 1.0, 2), _sac_mat(), Transform3D(basis.scaled_local(Vector3(sz, sz * 2.0, sz * 0.9)), body), "below_web")
	for k in 4:
		var y := (float(k) - 1.5) * sz * 0.8
		var ring := basis * Vector3(0, y, 0)
		var rw := sz * (1.0 - absf(float(k) - 1.5) * 0.25)
		_batch(_ring_mesh(), _silk_mat(), Transform3D(basis.rotated(basis.y, _rng.randf() * TAU).scaled_local(Vector3(rw, 1.0, rw * 0.95)) * Basis(Vector3(1, 0, 0), _rng.randf_range(-0.3, 0.3)), body + ring), "below_web")


# --- Arachnophobia variant ---------------------------------------------------------------------------------------

func _root_curtain(s: Dictionary) -> void:
	# Hang roots from the upper part of where the web would have been.
	var n: Vector3 = s["normal"]
	var p: Vector3 = s["pos"]
	var sz: float = float(s["size"])
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-n, up)
	var side := basis.x
	var count := 3 + int(float(s["density"]) * 3.0)
	for i in count:
		var off := side * _rng.randf_range(-0.4, 0.4) * sz
		var top := p + off + Vector3(0, sz * _rng.randf_range(0.15, 0.4), 0) - n * 0.1
		var length := sz * _rng.randf_range(0.45, 1.0)
		_hanging_root(top, length, _rng.randf() < 0.3)
	if float(s["density"]) > 0.5:
		_fungal_strand(p + Vector3(0, sz * 0.35, 0), sz * 0.8)


func _root_tendril(s: Dictionary) -> void:
	var top: Vector3 = s["top"]
	var bottom: Vector3 = s["bottom"]
	var length := minf(top.y - bottom.y, 3.2) * _rng.randf_range(0.55, 0.85)
	_hanging_root(top, length, true)


func _root_knot(s: Dictionary) -> void:
	var p: Vector3 = s["pos"]
	var sz: float = float(s["size"])
	var mat := _root_mat_mat()
	for i in 4:
		var a := float(i) / 4.0 * TAU + _rng.randf() * 0.6
		var r := 0.0 if i == 0 else sz * 0.45
		var rr := sz * (0.5 if i == 0 else _rng.randf_range(0.25, 0.38))
		_batch(Kit.blob_mesh(1.0, 80 + i, 0.4, 1.0, 2), mat, Transform3D(Basis(Vector3.UP, a).scaled_local(Vector3(rr * 1.1, rr * 0.85, rr)), p + Vector3(cos(a) * r, rr * 0.7, sin(a) * r)), "below_root")
	# Upward sprouts (never radiating sideways like legs) and a few roots sinking into the floor
	for i in 4:
		var a := _rng.randf() * TAU
		var dir := Vector3(cos(a) * 0.3, 1.0, sin(a) * 0.3).normalized()
		var start := p + Vector3(cos(a) * sz * 0.25, sz * 0.7, sin(a) * sz * 0.25)
		_line(start, start + dir * sz * _rng.randf_range(0.7, 1.3), 0.03, _pale_root_mat(), "below_root")
	for i in 3:
		var a := _rng.randf() * TAU
		_batch(Kit.blob_mesh(1.0, 95 + i, 0.3, 1.0, 1), mat, Transform3D(Basis(Vector3.UP, a).scaled_local(Vector3(sz * 0.5, sz * 0.12, sz * 0.2)), p + Vector3(cos(a) * sz * 0.7, 0.03, sin(a) * sz * 0.7)), "below_root")
	for i in 3:
		var a := _rng.randf() * TAU
		_batch(_bulb_mesh(), Mat.glow(BULB, 1.1), Transform3D(Basis.IDENTITY.scaled_local(Vector3.ONE * sz * 0.1), p + Vector3(cos(a) * sz * 0.5, sz * 0.9, sin(a) * sz * 0.5)), "below_root")


func _root_pod(s: Dictionary) -> void:
	var top: Vector3 = s["top"]
	var length: float = float(s["length"])
	var sz: float = float(s["size"])
	var body := top + Vector3(0, -length, 0)
	_line(top, body + Vector3(0, sz * 1.3, 0), 0.04, _root_mat_mat(), "below_root")
	var basis := Basis(Vector3.UP, _rng.randf() * TAU)
	_batch(Kit.blob_mesh(1.0, 91, 0.45, 1.0, 2), _root_mat_mat(), Transform3D(basis.scaled_local(Vector3(sz * 0.8, sz * 1.5, sz * 0.8)), body), "below_root")
	for i in 3:
		_hanging_root(body + Vector3(_rng.randf_range(-0.15, 0.15), -sz * 0.9, _rng.randf_range(-0.15, 0.15)), _rng.randf_range(0.3, 0.7), false)


func _root_mat(s: Dictionary) -> void:
	var p: Vector3 = s["pos"]
	var ext: Vector2 = s["extent"]
	var count := int(6.0 + 8.0 * float(s["density"]))
	for i in count:
		var top := p + Vector3(_rng.randf_range(-ext.x, ext.x) * 0.5, 0.25, _rng.randf_range(-ext.y, ext.y) * 0.5)
		_hanging_root(top, _rng.randf_range(0.6, 2.0), _rng.randf() < 0.4)
	_fungal_strand(p + Vector3(0, 0.2, 0), 1.4)


func _hanging_root(top: Vector3, length: float, thick: bool) -> void:
	var v := _rng.randi_range(0, 3)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU)
	var mat := _root_mat_mat() if thick else _pale_root_mat()
	_batch(_root_mesh(v, thick), mat, Transform3D(basis.scaled_local(Vector3.ONE * length), top), "below_root")


func _fungal_strand(top: Vector3, length: float) -> void:
	var bottom := top + Vector3(_rng.randf_range(-0.2, 0.2), -length, _rng.randf_range(-0.2, 0.2))
	_line(top, bottom, 0.012, _fungal_mat(), "below_root")
	for i in 3:
		var t := _rng.randf_range(0.3, 1.0)
		_batch(_bulb_mesh(), Mat.glow(BULB, 1.2), Transform3D(Basis.IDENTITY.scaled_local(Vector3.ONE * 0.05), top.lerp(bottom, t)), "below_root")


# --- Mesh / material helpers -------------------------------------------------------------------------------------------

func _line(a: Vector3, b: Vector3, radius: float, mat: Material, group: String) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var up := d / length
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := up.cross(ref).normalized()
	var z := x.cross(up).normalized()
	var basis := Basis(x, up, z)
	_batch(_cyl_mesh(), mat, Transform3D(basis.scaled_local(Vector3(radius * 2.0, length, radius * 2.0)), (a + b) * 0.5), group)


func _batch(mesh: Mesh, mat: Material, xf: Transform3D, group: String) -> void:
	var key := "%d|%d|%s" % [mesh.get_instance_id(), mat.get_instance_id(), group]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "mat": mat, "group": group, "xf": []}
	_batches[key]["xf"].append(xf)


func _flush() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var xfs: Array = b["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = b["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group(String(b["group"]))
		add_child(mmi)
	_batches.clear()


static func _cyl_mesh() -> Mesh:
	if not _cache.has("cyl"):
		var m := CylinderMesh.new()
		m.top_radius = 0.5
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = 5
		m.rings = 1
		m.cap_top = false
		m.cap_bottom = false
		_cache["cyl"] = m
	return _cache["cyl"]


static func _ring_mesh() -> Mesh:
	if not _cache.has("ring"):
		var t := TorusMesh.new()
		t.inner_radius = 0.96
		t.outer_radius = 1.0
		t.rings = 16
		t.ring_segments = 4
		_cache["ring"] = t
	return _cache["ring"]


static func _bulb_mesh() -> Mesh:
	if not _cache.has("bulb"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.rings = 4
		m.radial_segments = 6
		_cache["bulb"] = m
	return _cache["bulb"]


static func _silk_mat() -> Material:
	return Mat.toon(Palette.SILK_WEB, {"rim": 0.6, "emission": Palette.SILK_WEB, "emission_energy": 0.25})


static func _sac_mat() -> Material:
	return Mat.toon(SAC, {"rim": 0.7, "emission": Palette.SILK_GLOW, "emission_energy": 0.12, "noise": 0.12})


static func _root_mat_mat() -> Material:
	return Mat.toon(ROOT_DARK, {"rim": 0.35, "noise": 0.15})


static func _pale_root_mat() -> Material:
	return Mat.toon(PALE_ROOT, {"rim": 0.45, "noise": 0.12, "emission": PALE_ROOT, "emission_energy": 0.06})


static func _fungal_mat() -> Material:
	return Mat.toon(FUNGAL, {"rim": 0.5, "emission": FUNGAL, "emission_energy": 0.15})


## Unit-length hanging root: a tapered, gently wiggling tube from (0,0,0) down to y = -1.
static func _root_mesh(v: int, thick: bool) -> ArrayMesh:
	var key := "root|%d|%s" % [v, thick]
	if _cache.has(key):
		return _cache[key]
	var rings := 9
	var sides := 6
	var base_r := 0.05 if thick else 0.028
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var phase := float(v) * 1.7
	for i in rings + 1:
		var t := float(i) / float(rings)
		var c := Vector3(sin(t * 3.4 + phase) * 0.07 * t, -t, cos(t * 2.6 + phase * 1.3) * 0.06 * t)
		var r := base_r * lerpf(1.0, 0.12, t)
		for j in sides:
			var a := float(j) / float(sides) * TAU
			var nn := Vector3(cos(a), 0.0, sin(a))
			verts.append(c + nn * r)
			normals.append(nn)
	for i in rings:
		for j in sides:
			var a0 := i * sides + j
			var a1 := i * sides + (j + 1) % sides
			var b0 := (i + 1) * sides + j
			var b1 := (i + 1) * sides + (j + 1) % sides
			idx.append(a0); idx.append(b0); idx.append(a1)
			idx.append(a1); idx.append(b0); idx.append(b1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = mesh
	return mesh
