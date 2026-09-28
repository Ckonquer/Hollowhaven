extends "res://tests/test_case.gd"
## Visual QA fixes of the creature cast (qa/tmp/visual CR-00 .. CR-15), checked NUMERICALLY so they cannot drift
## back: the Pumpkin Mimic's carved face sits ON its shell (never inside the ribs), the Velvet Wing hangs FROM its
## twig, telegraph tints keep the shading (capped wash + rim), the roots colour and every ground mark contrast
## with the meadow, the Skitter's crouch keeps bent knees, the Warden's face is clear of its bell, the Patchwalker's
## rake tell stands above and beside its hat, the Hollow Mother's boss robe carries an edge light, Count Velour's
## reveal halo is no waist hoop, the Wisp's false light has volume, the Gallery bats are bigger, the trip-line
## posts are pale objects (also in a real hazard field, both looks), the Crossing Matron's ember scar sits on her
## abdomen under a fuller mantle, and the Choir's false cozy lights are paper lanterns, not eyeballs.

const MimicVisual := preload("res://src/enemies/pumpkin_mimic_visual.gd")
const WingVisual := preload("res://src/enemies/velvet_wing_visual.gd")
const DrudgeVisual := preload("res://src/enemies/hollow_drudge_visual.gd")
const ElderVisual := preload("res://src/enemies/knotted_elder_visual.gd")
const WalkerVisual := preload("res://src/enemies/patchwalker_visual.gd")
const WardenVisual := preload("res://src/enemies/quarry_warden_visual.gd")
const WispVisual := preload("res://src/enemies/borrowed_wisp_visual.gd")
const SkitterVisual := preload("res://src/enemies/brood_skitter_visual.gd")
const ShadeVisual := preload("res://src/enemies/shade_visual.gd")
const VelourVisual := preload("res://src/enemies/velour_visual.gd")
const VelourFx := preload("res://src/enemies/velour/velour_fx.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const HazardArt := preload("res://src/enemies/boss_hazards/hazard_art.gd")
const HazardField := preload("res://src/enemies/boss_hazards/hazard_field.gd")
const MatronLook := preload("res://src/enemies/crossing/matron_look.gd")
const ChoirLights := preload("res://src/enemies/choir/choir_lights.gd")
const CreatureFx := preload("res://src/enemies/creature_fx.gd")
const Palette := preload("res://src/art/palette.gd")

const DT := 1.0 / 60.0

var _nodes: Array = []


func before_each() -> void:
	Settings.set_value("reduce_flashing", false)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("high_visibility_cues", false)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Settings.set_value("reduce_flashing", false)
	Settings.set_value("high_visibility_cues", false)
	Settings.set_value("arachnophobia", false)
	await wait_frames(1)


func _make(script: Script, pos: Vector3, params: Dictionary = {}) -> Node3D:
	var v: Node3D = script.new()
	if not params.is_empty():
		v.call("setup", params)
	add_child(v)
	v.global_position = pos
	_nodes.append(v)
	return v


func _run(v: Node3D, seconds: float) -> void:
	for i in int(seconds / DT):
		v._process(DT)


static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# --- CR-00: the Mimic's face is ON the shell -------------------------------------------------------------------------

func test_mimic_carved_face_sits_in_front_of_the_shell() -> void:
	# the analytic shell front matches the rib numbers (front ribs reach ~0.45 m at the eyes)
	var zc: float = MimicVisual.shell_front_z(0.0, 0.0)
	var ze: float = MimicVisual.shell_front_z(0.14, 0.09)
	assert_true(zc < -0.34 and zc > -0.52, "shell front at the centre %.3f" % zc)
	assert_true(ze < -0.38, "the ribs bulge to %.3f at the eyes (where the old face was buried at -0.31)" % ze)
	var v := _make(MimicVisual, Vector3.ZERO)
	for st in ["dormant", "chase", "bite_tele", "stuck"]:
		if st == "bite_tele":
			v.set_attack("bite")
			v.set_state("telegraph", 1.2)
		else:
			v.set_state(st, 1.2)
		_run(v, 0.6)
		var c: float = v.face_clearance()
		assert_true(c > 0.002 and c < 0.06, "%s: every visible face piece sits on the shell, none buried (clearance %.4f m)" % [st, c])
	v.set_state("dormant")
	_run(v, 0.4)
	assert_false(bool(v.eyes_open()), "dormant: only the sleepy slits")
	assert_false(bool(v.mouth_glowing()), "dormant: a closed seam, no candle glow")
	v.set_attack("bite")
	v.set_state("telegraph", 1.2)
	_run(v, 0.5)
	assert_true(bool(v.eyes_open()) and bool(v.mouth_glowing()), "bite tell: glowing eyes and a gaping glowing mouth")
	var shell: Node3D = v.get("_shell")
	assert_true(shell.rotation.x > 0.2, "the top tips BACK so the gaping mouth turns up toward Krystal (%.2f)" % shell.rotation.x)


# --- CR-01: the Velvet Wing hangs from its twig ----------------------------------------------------------------------

func test_velvet_wing_hangs_from_the_twig_by_its_feet() -> void:
	var v := _make(WingVisual, Vector3.ZERO)
	v.set_state("idle")
	_run(v, 1.5)
	assert_true(bool(v.hanging))
	var h: float = v.twig_height()
	assert_true(h > 0.2, "the twig is ABOVE the upside-down bat (%.2f m), not at its head" % h)
	assert_true(float(v.foot_to_twig()) < 0.05, "its feet grip the twig (%.3f m)" % float(v.foot_to_twig()))
	v.set_state("chase")
	_run(v, 0.5)
	var twig: Node3D = v.get("_twig")
	assert_false(twig.visible, "no twig once it flies")


# --- CR-09: tells keep the shading ---------------------------------------------------------------------------------

func test_telegraph_tints_are_a_capped_wash_plus_rim() -> void:
	var cap := CreatureFx.WASH_CAP * CreatureFx.WASH_K + 0.001
	var specs := [[DrudgeVisual, "pick_swing"], [ElderVisual, "roots"], [WalkerVisual, "rake"], [WardenVisual, "slam"],
		[MimicVisual, "bite"], [WingVisual, "dash"], [SkitterVisual, ""], [WispVisual, ""]]
	var x := 0.0
	for s in specs:
		var v := _make(s[0], Vector3(x, 0, 0))
		x += 6.0
		if String(s[1]) != "":
			v.set_attack(String(s[1]))
		v.set_state("telegraph", 1.4)
		var worst_wash := 0.0
		var best_rim := 0.0
		for i in 40:
			v._process(DT)
			var m: StandardMaterial3D = v.get("_tint_mat")
			worst_wash = maxf(worst_wash, m.albedo_color.a)
			best_rim = maxf(best_rim, CreatureFx.rim_alpha(m))
		var name := (s[0] as Script).resource_path.get_file()
		assert_true(bool(v.get("_tint_on")), "%s: tinted" % name)
		assert_true(worst_wash <= cap, "%s: the flat wash stays capped (%.3f <= %.3f) so the shading shows" % [name, worst_wash, cap])
		assert_true(best_rim > 0.35, "%s: the tell colour rides on the rim (%.2f)" % [name, best_rim])
		v.hit_flash(0.2)
		v._process(DT)
		var fm: StandardMaterial3D = v.get("_tint_mat")
		assert_almost(CreatureFx.rim_alpha(fm), 0.0, 0.001, "%s: a hit flash is flat, no rim" % name)
		assert_true(fm.albedo_color.a > 0.3, "%s: and still a clear flash" % name)


# --- CR-02 / CR-04: ground marks read on grass and on the carpet ----------------------------------------------------

func test_roots_colour_and_contrast_bands() -> void:
	var grass_l := _lum(Palette.GRASS)
	assert_true(absf(_lum(TelegraphFx.ROOT) - grass_l) > 0.15, "roots mark stands off the meadow in brightness (the old green: 0.10)")
	assert_true(grass_l - _lum(TelegraphFx.SHADE) > 0.45, "and its dark band stands off it the other way")
	assert_true(TelegraphFx.ROOT.g - TelegraphFx.ROOT.r < 0.05, "no longer green on green")
	assert_true(ElderVisual.ROOTS_TINT.is_equal_approx(TelegraphFx.ROOT), "the Elder's body tell matches its ground mark")
	var m1: Node3D = TelegraphFx.new()
	var m2: Node3D = TelegraphFx.new()
	add_child(m1)
	add_child(m2)
	_nodes.append(m1)
	_nodes.append(m2)
	m1.show_spots([Vector3(1, 0, 1), Vector3(-1, 0, 1)], 0.6, TelegraphFx.ROOT)
	assert_true(bool(m1.shade_visible()), "every spot has its dark contrast band")
	var spots_on := 0
	for s in m1.get("_shade_spots"):
		if (s as MeshInstance3D).visible:
			spots_on += 1
	assert_eq(spots_on, 2, "one band per spot")
	for k in ["ring", "lane", "arc", "disc"]:
		match k:
			"ring":
				m2.show_ring(Vector3.ZERO, 2.0)
			"lane":
				m2.show_lane(Vector3.ZERO, Vector3(0, 0, -6), 1.6, TelegraphFx.DANGER)
			"arc":
				m2.show_arc(Vector3.ZERO, Vector3.FORWARD, 3.0, 120.0)
			_:
				m2.show_disc(Vector3.ZERO, 1.0)
		assert_true(bool(m2.shade_visible()), "%s: dark contrast band on" % k)
	var sm: StandardMaterial3D = (m2.get("_shade") as MeshInstance3D).material_override
	assert_eq(sm, (m1.get("_shade_spots")[0] as MeshInstance3D).material_override, "one shared band material")
	assert_true(_lum(sm.albedo_color) < 0.2 and sm.albedo_color.a > 0.3, "an ink band")
	# edges a step paler than the fill (two-tone), so a red lane reads on a red carpet
	m2.show_lane(Vector3.ZERO, Vector3(0, 0, -6), 1.6, TelegraphFx.DANGER)
	m2.set_progress(1.0, true)
	for i in 5:
		m2._process(0.05)
	var edge: StandardMaterial3D = (m2.get("_edge") as MeshInstance3D).material_override
	var fill: StandardMaterial3D = (m2.get("_fill") as MeshInstance3D).material_override
	assert_true(_lum(edge.albedo_color) > _lum(fill.albedo_color) + 0.05, "paler edge line than fill")
	m2.hide_mark()
	assert_false(bool(m2.shade_visible()), "a hidden mark shows no band")


func test_gallery_bats_are_bigger_and_lighter() -> void:
	var b: Node3D = VelourFx.bat_node(1.0, false)
	add_child(b)
	_nodes.append(b)
	var look: Node3D = b.get_node("Look")
	assert_almost(look.scale.x, VelourFx.BAT_SIZE, 0.001, "built 1.5x")
	assert_almost(b.scale.x, 1.0, 0.001, "the swarm still drives the root scale")
	assert_true(_lum(VelourFx.BAT_FUR) > _lum(Color("3a2244")) + 0.03, "a lighter plum than the old near-black")


# --- CR-10: the Skitter crouch keeps bent knees ------------------------------------------------------------------------

func test_skitter_telegraph_keeps_bent_knees_and_grounded_feet() -> void:
	var v := _make(SkitterVisual, Vector3.ZERO, {"sprout": false})
	v.set_state("telegraph", 1.0)
	_run(v, 0.6)
	var legs: Array = v.get("_legs")
	var grounded := 0
	for l in legs:
		var femur := l["femur"] as Node3D
		var knee := l["knee"] as Node3D
		var side: float = l["side"]
		var hip_p := femur.global_position
		var knee_p := knee.global_position
		var foot_p := knee.global_transform * Vector3(side * SkitterVisual.L2, 0.0, 0.0)
		var ang := rad_to_deg((hip_p - knee_p).angle_to(foot_p - knee_p))
		if int(l["index"]) != 0:
			assert_true(ang > 30.0, "leg %d: a real knee bend (%.0f deg), not a vertical plank" % [int(l["index"]), ang])
			if absf(foot_p.y) < 0.04:
				grounded += 1
	assert_eq(grounded, 6, "the six back legs stand on the ground")


# --- CR-13: the Warden's face is clear of the bell ----------------------------------------------------------------

func test_warden_eyes_are_not_hidden_by_the_bell() -> void:
	var v := _make(WardenVisual, Vector3.ZERO)
	v.set_state("chase")
	_run(v, 0.5)
	var bell: Node3D = v.get("_bell")
	var head: Node3D = v.get("_head")
	var body: MeshInstance3D = bell.get_child(0) as MeshInstance3D
	var to_local := v.global_transform.affine_inverse()
	var ab := body.get_aabb()
	var bell_low := INF
	var bell_front := INF
	for i in 8:
		var corner := to_local * (body.global_transform * ab.get_endpoint(i))
		bell_low = minf(bell_low, corner.y)
		bell_front = minf(bell_front, corner.z)
	var eye := to_local * (head.global_transform * Vector3(0.12, 0.03, -0.27))
	# CR-13: the bell used to hang to the eyes' height just behind them, so from the follow camera it sat ON the face.
	assert_true(bell_low > eye.y + 0.1, "the whole bell rides above the eyes (bell low %.2f, eyes %.2f)" % [bell_low, eye.y])
	assert_true(bell_front > eye.z + 0.25, "and well behind the face (bell front z %.2f, eyes z %.2f)" % [bell_front, eye.z])
	# no ray from an eye toward the front camera (10-35 degrees up) crosses the bell
	var inv := body.global_transform.affine_inverse()
	for elev in [10.0, 20.0, 35.0]:
		var dir := v.global_transform.basis * Vector3(0.0, sin(deg_to_rad(elev)), -cos(deg_to_rad(elev)))
		var e := head.global_transform * Vector3(0.12, 0.03, -0.27)
		var hit := false
		for i in 60:
			if ab.has_point(inv * (e + dir * (0.05 + 0.1 * float(i)))):
				hit = true
		assert_false(hit, "the eye is in plain view at %d deg" % int(elev))
	var eye_mesh: Array = head.find_children("*", "MeshInstance3D", false, false)
	assert_true(eye_mesh.size() >= 6, "head, brow, two sockets and two eyes")


# --- CR-15: the rake tell stands above and beside the hat -----------------------------------------------------------

func test_patchwalker_rake_tell_clears_the_hat() -> void:
	var v := _make(WalkerVisual, Vector3.ZERO)
	v.set_attack("rake")
	v.set_state("telegraph", 1.1)
	_run(v, 0.8)
	var head: Vector3 = v.rake_head_local()
	var hat: Vector3 = v.hat_top_local()
	assert_true(head.y > hat.y + 0.5, "rake head high above the hat (%.2f vs %.2f)" % [head.y, hat.y])
	assert_true(absf(head.x - hat.x) > 0.45, "and out to the side of the brim (%.2f)" % absf(head.x - hat.x))
	v.set_state("chase")
	_run(v, 1.0)
	assert_true(float(v.rake_raise) < 0.2)
	assert_true(v.rake_head_local().y < hat.y, "the rake comes back down")


# --- CR-06: the Hollow Mother's edge light ---------------------------------------------------------------------------

func test_hollow_mother_boss_robe_has_an_edge_light() -> void:
	var plain: Material = ShadeVisual.robe_material()
	var boss: Material = ShadeVisual.boss_robe_material()
	assert_not_null(plain.next_pass, "the ordinary Shade keeps its outline")
	assert_null(plain.next_pass.next_pass, "and no edge light (Chapter One Shades unchanged)")
	assert_not_null(boss.next_pass, "boss: outline")
	assert_not_null(boss.next_pass.next_pass, "boss: + lavender edge light")
	var v := _make(ShadeVisual, Vector3.ZERO, {"scale": 2.4, "boss": true})
	var robe: MeshInstance3D = v.get("_robe")
	assert_eq(robe.material_override, boss, "the boss wears it")
	var s := _make(ShadeVisual, Vector3(5, 0, 0))
	assert_eq((s.get("_robe") as MeshInstance3D).material_override, plain)


# --- CR-11: Velour's reveal halo --------------------------------------------------------------------------------------

func test_velour_reveal_halo_is_above_the_crown_and_behind_him() -> void:
	var v := _make(VelourVisual, Vector3.ZERO)
	v.call("set_state", "reform", 1.2)
	v.call("set_revealed", true)
	_run(v, 0.5)
	var halo: Node3D = v.get("_halo")
	assert_true(halo.visible)
	var head: Node3D = v.get("_head")
	var ring_ok := false
	var aura_ok := false
	for c in halo.get_children():
		var mi := c as MeshInstance3D
		if mi.mesh is TorusMesh:
			ring_ok = mi.global_position.y > head.global_position.y + 0.3
		elif mi.material_override is ShaderMaterial:
			aura_ok = true
	assert_true(ring_ok, "the gold ring floats above the crown, not round the waist")
	assert_true(aura_ok, "a soft glow behind him")


# --- CR-07: the Wisp's false light --------------------------------------------------------------------------------------

func test_wisp_orb_has_volume_and_the_sweep_ribbons_stretch() -> void:
	var v := _make(WispVisual, Vector3.ZERO)
	v.preview = true
	_run(v, 0.3)
	var orb: MeshInstance3D = v.get("_orb")
	assert_true(orb.material_override is ShaderMaterial, "a shaded core-to-limb orb, not a flat unshaded disc")
	var ribbons: Array = v.get("_ribbons")
	v.set_state("telegraph", 1.4)
	_run(v, 0.6)
	for r in ribbons:
		assert_true((r as Node3D).scale.y > 1.3, "sweep tell: the ribbons lengthen (%.2f)" % (r as Node3D).scale.y)
	var fl: Node3D = v.get("_float")
	assert_true(absf(fl.rotation.z) > 0.25, "and the wisp tips to the swing side")


# --- CR-03: trip-line posts -------------------------------------------------------------------------------------------

func test_trip_posts_are_pale_objects() -> void:
	for alt in [false, true]:
		var holder := Node3D.new()
		add_child(holder)
		_nodes.append(holder)
		HazardArt.build_post(holder, alt)
		var meshes := holder.find_children("*", "MeshInstance3D", true, false)
		assert_true(meshes.size() >= 4 and meshes.size() <= 7, "a peg with a cap and a band (%d meshes)" % meshes.size())
		var ab := AABB()
		for m in meshes:
			var mi := m as MeshInstance3D
			ab = ab.merge(mi.transform * mi.get_aabb()) if ab.size != Vector3.ZERO else mi.transform * mi.get_aabb()
		assert_true(ab.size.y > ab.size.x * 1.2, "taller than wide: a stake, not a round blob (%s)" % str(ab.size))
	for alt in [false, true]:
		var pm: ShaderMaterial = HazardArt.post_mat(alt)
		var c: Color = pm.get_shader_parameter("albedo")
		assert_true(_lum(c) > 0.45, "pale post (%.2f), never a dark shadow blob" % _lum(c))


## AABB (in `space`'s local frame) of every mesh under `holder`.
static func _aabb_in(holder: Node3D, space: Node3D) -> AABB:
	var inv := space.global_transform.affine_inverse()
	var ab := AABB()
	var first := true
	for m in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var bb: AABB = inv * mi.global_transform * mi.get_aabb()
		ab = bb if first else ab.merge(bb)
		first = false
	return ab


func _trip_posts(f: Node) -> Array:
	var out: Array = []
	for c in f.get_children():
		if String(c.name).begins_with("TripPost"):
			out.append(c)
	return out


# --- CR-03 in the real field: hazard_field builds its posts with hazard_art.build_post ----------------------------

func test_hazard_field_posts_are_stakes_in_both_looks() -> void:
	var f: Node3D = HazardField.new()
	f.setup({"center": Vector3.ZERO, "radius": 11.5, "floor_y": 0.0, "intensity": 1, "entrance": Vector3(0, 0, 11.0),
		"obstacles": [[Vector3.ZERO, HazardField.CENTRE_OBSTACLE]]})
	add_child(f)
	_nodes.append(f)
	var n_posts: int = (f.get("posts") as Array).size()
	assert_eq(n_posts, HazardField.POST_COUNT)
	for alt in [false, true]:
		if alt:
			Settings.set_value("arachnophobia", true)   # the live swap: settings_changed -> set_alt -> rebuild
		assert_eq(bool(f.get("alt")), alt, "the field follows the setting")
		var tp := _trip_posts(f)
		assert_eq(tp.size(), n_posts, "alt=%s: one post per anchor, the old set already gone (no duplicates)" % alt)
		var cones := 0
		for h in tp:
			var holder := h as Node3D
			var meshes := holder.find_children("*", "MeshInstance3D", true, false)
			assert_true(meshes.size() >= 4 and meshes.size() <= 7, "alt=%s: a peg with a cap and a band (%d meshes)" % [alt, meshes.size()])
			var ab := _aabb_in(holder, holder)
			assert_true(ab.size.y > ab.size.x * 1.2, "alt=%s: taller than wide - a stake, not the old round blob (%s)" % [alt, str(ab.size)])
			assert_true(ab.position.y > -0.15 and ab.position.y < 0.1, "alt=%s: it stands on its floor point (%.2f)" % [alt, ab.position.y])
			for m in meshes:
				var mi := m as MeshInstance3D
				assert_false(mi.mesh is ArrayMesh, "alt=%s: no noise blob (the old dark knob) left in a post" % alt)
				if mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).top_radius < 0.001:
					cones += 1
				if mi.mesh is TorusMesh:
					var band_y := mi.position.y
					assert_true(band_y > ab.end.y * 0.6, "alt=%s: the strand is wound tight near the top (%.2f of %.2f)" % [alt, band_y, ab.end.y])
		if alt:
			assert_eq(cones, n_posts * 3, "arachnophobia: pale root stakes with little root feet")
		else:
			assert_eq(cones, 0, "silk look: stone pegs")
	Settings.set_value("arachnophobia", false)
	assert_false(bool(f.get("alt")))
	assert_eq(_trip_posts(f).size(), n_posts, "and back, still one set")


# --- CR-05: the Crossing Matron's ember scar and mantle ---------------------------------------------------------------

func test_crossing_scar_sits_on_the_abdomen_under_a_fuller_mantle() -> void:
	var look: Node3D = MatronLook.new()
	look.call("setup", {"alt": false})
	add_child(look)
	_nodes.append(look)
	var scar: MeshInstance3D = look.call("scar_node")
	assert_not_null(scar, "silk look: an ember scar")
	var inner: Node3D = look.get("inner")
	var abd: Node3D = inner.call("abdomen_node")
	assert_not_null(abd)
	assert_true(abd.is_ancestor_of(scar), "the scar is fitted onto the abdomen (it rides its bob), never a free hoop")
	assert_eq(look.find_children("EmberScar", "", true, false).size(), 1, "exactly one scar")
	var d := scar.global_position.distance_to(abd.global_position)
	assert_true(d < 0.1 * MatronLook.WEAVER_SCALE, "centred on the abdomen (%.2f m off)" % d)
	# the band hugs the abdomen blob: its ring is the blob's girth, not a hoop around it
	var blob := abd.get_child(0) as MeshInstance3D
	var inv := abd.global_transform.affine_inverse()
	var blob_box: AABB = inv * blob.global_transform * blob.get_aabb()
	var scar_box: AABB = inv * scar.global_transform * scar.get_aabb()
	assert_true(scar_box.size.x <= blob_box.size.x * 1.12, "no wider than the abdomen (%.2f vs %.2f)" % [scar_box.size.x, blob_box.size.x])
	assert_true(scar_box.size.y <= blob_box.size.y * 1.12, "no taller than the abdomen (%.2f vs %.2f)" % [scar_box.size.y, blob_box.size.y])
	assert_true(scar_box.size.z < scar_box.size.x * 0.4, "a flat band round the long axis")
	var sm: ShaderMaterial = scar.get_active_material(0)
	assert_almost(float(sm.get_shader_parameter("emission_energy")), MatronLook.SCAR_GLOW_ENERGY, 0.001, "a warmer ember glow")
	assert_almost(MatronLook.SCAR_GLOW_ENERGY, 0.6, 0.001)
	assert_eq(int(look.call("streamer_count")), 6, "a fuller torn mantle")
	var strips := look.find_children("Streamer*", "MeshInstance3D", true, false)
	assert_eq(strips.size(), 6, "six streamers")
	var silk: StandardMaterial3D = (strips[0] as MeshInstance3D).get_active_material(0)
	assert_true(silk.albedo_color.a >= 0.9 - 0.001, "more opaque silk (%.2f)" % silk.albedo_color.a)
	# the live arachnophobia swap: the scar leaves with the old body (no orphan), none on the Hollow Mother ...
	look.call("set_alt", true)
	assert_null(look.call("scar_node"), "no scar on the Hollow Mother")
	assert_eq(look.find_children("EmberScar", "", true, false).size(), 0, "none left in the tree")
	assert_eq(look.find_children("Streamer*", "", true, false).size(), 0, "no silk streamers either")
	await wait_frames(1)
	assert_false(is_instance_valid(scar), "the old scar was freed with the old body (no orphan)")
	# ... and exactly one fresh one back on the new Matron's abdomen
	look.call("set_alt", false)
	var scar2: MeshInstance3D = look.call("scar_node")
	assert_not_null(scar2)
	var abd2: Node3D = (look.get("inner") as Node).call("abdomen_node")
	assert_true(abd2 != null and abd2.is_ancestor_of(scar2), "back on the new abdomen")
	assert_eq(look.find_children("EmberScar", "", true, false).size(), 1, "no duplicate after the round trip")
	assert_eq(look.find_children("Streamer*", "MeshInstance3D", true, false).size(), 6)


# --- CR-14: the Choir's false cozy lights are paper lanterns --------------------------------------------------------

func test_choir_false_lights_are_paper_lanterns_not_eyeballs() -> void:
	var lt: Node3D = ChoirLights.new()
	add_child(lt)
	_nodes.append(lt)
	var fl: Array = lt.call("false_lights_nodes")
	assert_eq(fl.size(), ChoirLights.MAX_FALSE)
	assert_eq(ChoirLights.LANTERN_RIBS, 4)
	for i in fl.size():
		var f := fl[i] as Node3D
		assert_eq(String(f.name), "FalseLight_%d" % i, "names kept (the boss relies on them)")
		var ribs := 0
		for c in f.get_children():
			if String(c.name).begins_with("Rib") and c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
				ribs += 1
		assert_eq(ribs, 4, "lantern %d: a cage of four ribs round the paper" % i)
		for part in ["Paper", "Cap", "Base", "Hanger", "Ribbon"]:
			assert_not_null(f.get_node_or_null(part), "lantern %d: %s" % [i, part])
		assert_almost((f.get_node("Ribbon") as Node3D).position.y, -0.34, 0.001, "the ribbon hangs below the base")
		assert_eq(f.find_children("*", "Light3D", true, false).size(), 0, "emissive only, no Light3D")
		for m in f.find_children("*", "MeshInstance3D", true, false):
			var mat: Material = (m as MeshInstance3D).get_active_material(0)
			var col := Color.WHITE
			if mat is ShaderMaterial:
				col = (mat as ShaderMaterial).get_shader_parameter("albedo")
			elif mat is StandardMaterial3D:
				col = (mat as StandardMaterial3D).albedo_color
			assert_true(_lum(col) > 0.3, "lantern %d %s: no near-black cap or dot (the eyeball look; lum %.2f)" % [i, m.name, _lum(col)])
