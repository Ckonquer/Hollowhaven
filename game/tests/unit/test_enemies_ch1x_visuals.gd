extends "res://tests/test_case.gd"
## Procedural visuals of the Chapter One additions, checked numerically (no screenshots): distinct silhouettes
## (bounds and proportions), feet on the ground, bounded mesh counts, shared meshes / materials, readable
## wind-up poses (moth flare + orb, skitter legs drawing in, sprout roots curling, brambleback head lowering
## and glowing flanks in the punish window) and telegraph tints that stay steady with reduce_flashing.

const BramblebackVisual := preload("res://src/enemies/brambleback_visual.gd")
const MothVisual := preload("res://src/enemies/lantern_moth_visual.gd")
const DrudgeVisual := preload("res://src/enemies/hollow_drudge_visual.gd")
const SkitterVisual := preload("res://src/enemies/brood_skitter_visual.gd")
const ElderVisual := preload("res://src/enemies/knotted_elder_visual.gd")

const DT := 1.0 / 60.0
const MAX_MESHES := 110

var _nodes: Array = []


func before_each() -> void:
	Settings.set_value("reduce_flashing", false)
	Settings.set_value("arachnophobia", false)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Settings.set_value("reduce_flashing", false)
	Settings.set_value("high_visibility_cues", false)
	await wait_frames(1)


func _make(script: Script, pos: Vector3, params: Dictionary = {}) -> Node3D:
	var v: Node3D = script.new()
	if not params.is_empty():
		v.call("setup", params)
	add_child(v)
	v.global_position = pos
	_nodes.append(v)
	return v


static func _meshes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out


static func _aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi in _meshes(root):
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var ab: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out


func _run(v: Node3D, seconds: float) -> void:
	for i in int(seconds / DT):
		v._process(DT)


func test_silhouettes_are_distinct_and_grounded() -> void:
	var bb := _make(BramblebackVisual, Vector3(0, 0, 0))
	var moth := _make(MothVisual, Vector3(10, 0, 0))
	var dr := _make(DrudgeVisual, Vector3(20, 0, 0))
	var sk := _make(SkitterVisual, Vector3(30, 0, 0), {"sprout": false})
	var sp := _make(SkitterVisual, Vector3(40, 0, 0), {"sprout": true})
	var el := _make(ElderVisual, Vector3(50, 0, 0))
	for v in [bb, moth, dr, sk, sp, el]:
		_run(v, 0.5)                                    # settle into the idle pose
	var a_bb := _aabb(bb)
	var a_moth := _aabb(moth)
	var a_dr := _aabb(dr)
	var a_sk := _aabb(sk)
	var a_sp := _aabb(sp)
	var a_el := _aabb(el)
	print("SIZES bb %s moth %s drudge %s skitter %s sprout %s elder %s" % [a_bb.size, a_moth.size, a_dr.size, a_sk.size, a_sp.size, a_el.size])
	# Brambleback: long, low, wide mound
	assert_true(a_bb.size.y > 0.85 and a_bb.size.y < 1.3, "brambleback height %.2f" % a_bb.size.y)
	assert_true(a_bb.size.z > 1.4 and a_bb.size.z < 2.1, "brambleback length %.2f" % a_bb.size.z)
	assert_true(a_bb.size.x > 1.0 and a_bb.size.x < 1.5, "brambleback width %.2f" % a_bb.size.x)
	assert_true(a_bb.size.z > a_bb.size.y * 1.3, "longer than tall")
	# Moth: wide flat wings
	assert_true(a_moth.size.x > 1.0 and a_moth.size.x < 1.7, "moth wingspan %.2f" % a_moth.size.x)
	assert_true(a_moth.size.x > a_moth.size.y * 1.8, "wide and flat (%s)" % str(a_moth.size))
	# Drudge: tall narrow hunched figure
	assert_true(a_dr.size.y > 1.6 and a_dr.size.y < 2.2, "drudge height %.2f" % a_dr.size.y)
	assert_true(a_dr.size.y > a_dr.size.x * 1.6, "taller than wide (%s)" % str(a_dr.size))
	# Skitter vs Pale Sprout
	assert_true(a_sk.size.y < 0.5 and a_sk.size.x > 0.5, "skitter low and wide (%s)" % str(a_sk.size))
	assert_true(a_sp.size.y > 0.8 and a_sp.size.x < 0.5, "sprout tall and narrow (%s)" % str(a_sp.size))
	# Elder: the giant
	assert_true(a_el.size.y > 2.6 and a_el.size.y < 3.3, "elder height (crown included) %.2f" % a_el.size.y)
	assert_true(a_el.size.y > a_dr.size.y + 0.4, "clearly bigger than a drudge")
	# Grounded walkers
	for pair in [["brambleback", a_bb], ["drudge", a_dr], ["skitter", a_sk], ["elder", a_el]]:
		var low: float = (pair[1] as AABB).position.y
		assert_true(absf(low) < 0.12, "%s stands on the ground (lowest %.3f m)" % [pair[0], low])
	assert_true(a_sp.position.y > 0.1, "the sprout floats (%.2f m)" % a_sp.position.y)


func test_mesh_counts_are_bounded_and_resources_shared() -> void:
	var a := _make(BramblebackVisual, Vector3(0, 0, 0))
	var b := _make(BramblebackVisual, Vector3(5, 0, 0))
	for v in [a, b, _make(MothVisual, Vector3(10, 0, 0)), _make(DrudgeVisual, Vector3(15, 0, 0)),
			_make(SkitterVisual, Vector3(20, 0, 0), {"sprout": false}), _make(SkitterVisual, Vector3(25, 0, 0), {"sprout": true}),
			_make(ElderVisual, Vector3(30, 0, 0))]:
		var n := _meshes(v).size()
		assert_true(n > 5 and n <= MAX_MESHES, "%s: %d meshes" % [v.get_script().resource_path.get_file(), n])
	var ma := _meshes(a)
	var mb := _meshes(b)
	var shared_mesh := 0
	var shared_mat := 0
	for i in mini(ma.size(), mb.size()):
		if (ma[i] as MeshInstance3D).mesh == (mb[i] as MeshInstance3D).mesh:
			shared_mesh += 1
		if (ma[i] as MeshInstance3D).material_override == (mb[i] as MeshInstance3D).material_override:
			shared_mat += 1
	assert_eq(shared_mesh, ma.size(), "every mesh resource is shared between two instances")
	assert_true(shared_mat >= ma.size() - 2, "materials are shared (%d / %d)" % [shared_mat, ma.size()])


func test_brambleback_windup_and_flank_window() -> void:
	var v := _make(BramblebackVisual, Vector3.ZERO)
	_run(v, 0.3)
	var head: Node3D = v.get("_head")
	var head_idle := head.rotation.x
	v.set_state("telegraph", 1.0)
	_run(v, 0.4)
	assert_true(head.rotation.x > head_idle + 0.25, "head lowered behind the brow")
	assert_true(bool(v.get("_tint_on")), "wind-up tint on")
	assert_false(bool(v.flanks_glowing()))
	v.set_state("recover", 1.5)
	_run(v, 0.2)
	assert_true(bool(v.flanks_glowing()), "soft flanks glow during the punish window")
	v.set_state("chase")
	_run(v, 0.1)
	assert_false(bool(v.flanks_glowing()))


func test_moth_flare_and_rest() -> void:
	var v := _make(MothVisual, Vector3.ZERO)
	_run(v, 0.2)
	assert_false(bool(v.is_flaring()))
	v.set_state("telegraph", 1.1)
	_run(v, 0.3)
	var s1: float = v.orb_scale()
	assert_true(bool(v.is_flaring()), "the wings flare")
	_run(v, 0.6)
	assert_true(float(v.orb_scale()) > s1, "the orb swells toward the release")
	v.set_state("recover", 1.8)
	_run(v, 0.5)
	assert_false(bool(v.is_flaring()))
	assert_almost(float(v.orb_scale()), 0.0, 0.001, "the orb is gone once released")


func test_skitter_legs_draw_in_and_sprout_roots_curl() -> void:
	var sk := _make(SkitterVisual, Vector3.ZERO, {"sprout": false})
	_run(sk, 0.5)
	var wide := _aabb(sk).size.x
	sk.set_state("telegraph", 1.0)
	_run(sk, 0.5)
	var tight := _aabb(sk).size.x
	assert_true(tight < wide - 0.05, "legs draw in (%.2f -> %.2f m)" % [wide, tight])
	var sp := _make(SkitterVisual, Vector3(5, 0, 0), {"sprout": true})
	_run(sp, 0.5)
	var tendrils: Array = sp.get("_tendrils")
	sp.set_state("telegraph", 1.0)
	_run(sp, 0.5)
	for t in tendrils:
		assert_true((t as Node3D).scale.y < 0.6, "roots curl up (%.2f)" % (t as Node3D).scale.y)


func test_reduce_flashing_keeps_tints_steady() -> void:
	Settings.set_value("reduce_flashing", true)
	for script in [BramblebackVisual, DrudgeVisual, SkitterVisual, ElderVisual]:
		var v := _make(script, Vector3(float(_nodes.size()) * 6.0, 0, 0))
		v.set_state("telegraph", 1.3)
		_run(v, 0.45)                                   # past the ramp-in
		var mat: StandardMaterial3D = v.get("_tint_mat")
		var alphas := {}
		for i in 20:
			v._process(0.023)
			alphas[snappedf(mat.albedo_color.a, 0.001)] = true
		assert_eq(alphas.size(), 1, "%s: steady tint (%s)" % [script.resource_path.get_file(), str(alphas.keys())])
		assert_true(bool(v.get("_tint_on")), "but still clearly tinted")
	Settings.set_value("reduce_flashing", false)
	var p := _make(BramblebackVisual, Vector3(-10, 0, 0))
	p.set_state("telegraph", 1.0)
	_run(p, 0.3)
	var pm: StandardMaterial3D = p.get("_tint_mat")
	var seen := {}
	for i in 20:
		p._process(0.023)
		seen[snappedf(pm.albedo_color.a, 0.001)] = true
	assert_true(seen.size() > 3, "pulses without the comfort option")


## R87: Settings high_visibility_cues adds a bold cream outline round every shared ground telegraph (ring, disc,
## lane, wedge, spots), live on settings_changed, steady, with ONE shared material and cached meshes.
func test_high_visibility_cues_outline_the_ground_marks_live() -> void:
	const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
	Settings.set_value("high_visibility_cues", false)
	var m1: Node3D = TelegraphFx.new()
	var m2: Node3D = TelegraphFx.new()
	add_child(m1)
	add_child(m2)
	_nodes.append(m1)
	_nodes.append(m2)
	m1.show_ring(Vector3.ZERO, 2.0)
	assert_false(bool(m1.bold_visible()), "off by default: no outline")
	Settings.set_value("high_visibility_cues", true)
	assert_true(bool(m1.bold_visible()), "switched on live: the showing mark gains its outline")
	var b1: MeshInstance3D = m1.get("_bold")
	assert_true(b1.scale.is_equal_approx(Vector3(2.0, 1.0, 2.0)), "the outline hugs the marked radius")
	m2.show_lane(Vector3(4, 0, 0), Vector3(4, 0, -6), 1.6, TelegraphFx.DANGER)
	assert_true(bool(m2.bold_visible()), "a new mark is outlined while the option is on")
	var b2: MeshInstance3D = m2.get("_bold")
	assert_eq(b1.material_override, b2.material_override, "one shared outline material")
	var bm: StandardMaterial3D = b1.material_override
	assert_true(bm.albedo_color.r > 0.95 and bm.albedo_color.g > 0.9 and bm.albedo_color.b > 0.75, "cream")
	m2.move_lane(Vector3(4, 0, 0), Vector3(10, 0, 0))
	assert_almost(b2.scale.z, 6.0, 0.001, "the outline follows a tracked lane")
	m2.show_arc(Vector3.ZERO, Vector3.FORWARD, 3.0, 150.0, TelegraphFx.WARN)
	assert_true(bool(m2.bold_visible()), "wedge outlined")
	var arc_mesh: Mesh = b2.mesh
	m1.show_arc(Vector3(8, 0, 0), Vector3.BACK, 2.0, 150.0, TelegraphFx.WARN)
	assert_eq((m1.get("_bold") as MeshInstance3D).mesh, arc_mesh, "outline meshes are cached per shape")
	m1.show_spots([Vector3(1, 0, 1), Vector3(-1, 0, 1)], 0.75)
	assert_true(bool(m1.bold_visible()), "each spot gets a ring")
	var spots_on := 0
	for s in m1.get("_bold_spots"):
		if (s as MeshInstance3D).visible:
			spots_on += 1
	assert_eq(spots_on, 2, "one outline per marked spot")
	assert_false((m1.get("_bold") as MeshInstance3D).visible, "no stray wedge outline under the spots")
	# Steady: the outline is visibility only, the pulse never touches it.
	var lvl_mat: Material = bm
	for i in 20:
		m2._process(0.037)
	assert_eq(b2.material_override, lvl_mat, "the outline never pulses")
	Settings.set_value("high_visibility_cues", false)
	assert_false(bool(m1.bold_visible()) or bool(m2.bold_visible()), "switched off live")
	m2.hide_mark()
	Settings.set_value("high_visibility_cues", true)
	assert_false(bool(m2.bold_visible()), "a hidden mark shows no outline")
	Settings.set_value("high_visibility_cues", false)
