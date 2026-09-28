extends "res://tests/unit/test_reach_west_fixture.gd"
## Numeric regressions for the Reach visual-QA fixes (qa/tmp/visual/VISUAL_BUGS_MERGED.md, RE-02..RE-19):
## details sit ON their parent's surface (carved faces, mimic tells, roseberries), sign lettering faces outward and
## fits its board, the Bellhouse pond is one seamless mesh, the Candleyard has warm light pools with no shadowed
## lights, the festival board's Manor pin keeps off the title, leaves are leaf-shaped and fade near the camera, the
## brook's exit gorge bends out of sight and the Chapter One moonbells glow at night.

const Art := preload("res://src/world/reach/west/west_art.gd")
const RP := preload("res://src/world/reach/reach_props.gd")
const CommonsScript := preload("res://src/world/reach/commons.gd")
const WaterScript := preload("res://src/world/reach/reach_water.gd")
const TerrainScript := preload("res://src/world/reach/reach_terrain.gd")
const ReachWorld := preload("res://src/world/reach/reach_world.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const MothPocket := preload("res://src/world/surface/c1x/moth_pocket.gd")

static var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = ReachWorld.new()
		add_child(_w)
		await wait_physics(3)
	return _w


# --- RE-04: carved faces and mimic tells ON the pumpkin rind ------------------------------------------------------

## Front centre of a detail piece (local +Z = out of the rind) in radius-1 space.
static func _front(part: Array, depth: float) -> Vector3:
	return (part[1] as Transform3D) * Vector3(0, 0, depth * 0.5)


func test_carved_face_sits_on_the_rind() -> void:
	for v in [0, 1, 2]:
		var parts: Array = Art.carved_face_parts(v)
		assert_true(parts.size() >= 8, "eyes, nose and a grin (%d pieces)" % parts.size())
		for part in parts:
			var front := _front(part, Art.FACE_DEPTH)
			assert_false(Art.pumpkin_inside(v, front), "variant %d: face piece front %s is outside the body" % [v, front])
			var centre: Vector3 = (part[1] as Transform3D).origin
			assert_true(Art.pumpkin_inside(v, centre - (part[1] as Transform3D).basis.z * 0.03), "variant %d: piece %s is anchored in the rind, not floating" % [v, centre])
			assert_true(centre.z > 0.55, "on the +Z (face) side: z %.2f" % centre.z)
	# the old bug: the face at z 0.78-0.82 was inside lobes that reach ~1.04
	assert_true(Art.pumpkin_inside(1, Vector3(0.3, 0.86, 0.78)), "the old eye position really was buried")


func test_mimic_tells_sit_on_the_rind() -> void:
	var parts: Array = Art.mimic_tell_parts(2)
	assert_true(parts.size() >= 10, "a seam mouth and two lids (%d strokes)" % parts.size())
	for part in parts:
		var front := _front(part, 0.06)
		assert_false(Art.pumpkin_inside(2, front), "tell stroke front %s is outside the body" % front)
	# the mimic pocket scales the tells exactly like its body (squashed, tilted) so they stay on it
	var h: Node3D = await flat_host()
	var MimicPocket: Script = load("res://src/world/reach/west/mimic_pocket.gd")
	var mp: Node3D = MimicPocket.new()
	mp.setup(h)
	h.add_child(mp)
	await wait_frames(1)
	for d in mp.dormant:
		var root: Node3D = d["root"]
		var body: MeshInstance3D = null
		var det: MeshInstance3D = null
		for c in root.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh == Art.pumpkin_body(2, Art.MIMIC_DEEP.lightened(0.15), Art.MIMIC):
				body = c
			elif c is MeshInstance3D and (c as MeshInstance3D).mesh == Art.mimic_details(2):
				det = c
		assert_not_null(body, "dormant mimic body")
		assert_not_null(det, "dormant mimic tells")
		if body != null and det != null:
			assert_true(det.transform.is_equal_approx(body.transform), "the tells share the body's transform")


func test_carved_faces_are_dark_by_day_and_glow_at_night() -> void:
	var m: StandardMaterial3D = Art.carved_material()
	assert_eq(m.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "a cut reads as a hole by day")
	Art.set_daylight(1.0)
	assert_almost(m.emission_energy_multiplier, 0.0, 0.001, "no glow by day")
	assert_true(m.albedo_color.get_luminance() < 0.12, "a dark cut interior by day (%.2f)" % m.albedo_color.get_luminance())
	Art.set_daylight(0.0)
	assert_true(m.emission_energy_multiplier > 1.2, "blooms at night (%.2f)" % m.emission_energy_multiplier)
	assert_true(m.albedo_color.get_luminance() > 0.5, "warm and bright at night")
	Art.set_daylight(1.0)


# --- RE-05: roseberries ON the hedge ------------------------------------------------------------------------------

func test_roseberries_sit_on_the_hedge() -> void:
	for v in [0, 1, 2]:
		var pts: Array = Art.berry_points(v)
		assert_true(pts.size() >= 14, "variant %d: plenty of berries (%d)" % [v, pts.size()])
		var high := 0
		for p in pts:
			var cl := Art.hedge_clearance(v, p)
			assert_true(cl >= Art.BERRY_R * 0.3, "variant %d: berry %s pokes out of the leaves (clearance %.3f)" % [v, p, cl])
			assert_true(cl <= Art.BERRY_R * 1.2, "variant %d: berry %s is not floating (clearance %.3f)" % [v, p, cl])
			if (p as Vector3).y > 0.6:
				high += 1
		assert_true(high >= pts.size() / 3, "variant %d: berries show on top, not only at the sides" % v)
	# the old bug: berries within ~1 m of (0, 0.5, 0) were inside the blobs
	assert_true(Art.hedge_clearance(0, Vector3(0.1, 0.8, 0.2)) < 0.0, "the old berry spots really were buried")


# --- RE-02 / T3: sign lettering -------------------------------------------------------------------------------------

func test_sign_text_faces_outward_and_fits_its_board() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var board := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1.5, -2))
	var labels: Array = RP.sign_text(parent, "Ashbell Quarry", board, Vector2(1.8, 0.6), 0.08, {"font_size": 64, "px": 0.0075, "margin": 0.12})
	assert_eq(labels.size(), 2, "front and back")
	var normal := board.basis.z
	var sides := [1.0, -1.0]
	for i in labels.size():
		var l: Label3D = labels[i]
		assert_false(l.double_sided, "single-sided (never mirrored)")
		var off := l.position - board.origin
		assert_almost(l.basis.z.dot(normal), float(sides[i]), 0.001, "label %d faces its own side" % i)
		assert_true(off.dot(l.basis.z) > 0.04, "label %d sits in front of its face (outward), not inside the board" % i)
		var ext := RP.sign_text_extent(l.text, l.font_size, l.outline_size) * l.pixel_size
		assert_true(ext.x <= 1.8 * 0.9 and ext.y <= 0.6 * 0.9, "label %d fits the 1.8 x 0.6 board (%s)" % [i, ext])
	assert_true((labels[0] as Label3D).pixel_size < 0.0075, "shrunk to fit (the old 0.0075 overflowed)")
	parent.queue_free()


func test_quarry_sign_and_stall_names_in_the_region() -> void:
	var w: Node3D = await _world()
	var quarry: Node = w.find_child("AshbellQuarry", true, false)
	assert_not_null(quarry, "the quarry district is built")
	if quarry == null:
		return
	var front: Label3D = quarry.get_node_or_null("SignText")
	var back: Label3D = quarry.get_node_or_null("SignTextBack")
	assert_not_null(front)
	assert_not_null(back)
	if front != null and back != null:
		var mid := (front.global_position + back.global_position) * 0.5
		for l in [front, back]:
			assert_true(((l as Label3D).global_position - mid).dot((l as Label3D).global_basis.z) > 0.0, "%s faces away from the board" % (l as Label3D).name)
		assert_almost(front.global_basis.z.dot(back.global_basis.z), -1.0, 0.01, "the two faces look opposite ways")
		var ext := RP.sign_text_extent(front.text, front.font_size, front.outline_size) * front.pixel_size
		assert_true(ext.x < 1.8, "the lettering is narrower than the 1.8 m board (%.2f m)" % ext.x)
	var commons: Node = w.get("commons")
	var names := 0
	for c in commons.get_children():
		if c is Label3D and ["Costumes", "Pumpkins", "Lanterns", "Sweets", "Candles", "Ribbons", "Roseberries"].has((c as Label3D).text):
			names += 1
			var l2: Label3D = c
			var h := l2.font_size * l2.pixel_size
			assert_true(h >= 0.2, "%s: letters about 20 cm tall or more (%.2f m)" % [l2.text, h])
			var ext2 := RP.sign_text_extent(l2.text, l2.font_size, l2.outline_size) * l2.pixel_size
			assert_true(ext2.x <= RP.STALL_BOARD.x, "%s fits its name board" % l2.text)
	assert_eq(names, 7, "every stall is named")


# --- RE-09: festival board -----------------------------------------------------------------------------------------

func test_festival_board_manor_pin_keeps_off_the_title() -> void:
	var pin_top: float = CommonsScript.BOARD_MAP_ORIGIN.y + CommonsScript.MANOR_PIN.y + CommonsScript.BOARD_PIN_RADIUS
	var title_bottom: float = CommonsScript.BOARD_TITLE_Y - float(CommonsScript.BOARD_TITLE_PX) * CommonsScript.BOARD_TITLE_PIXEL * 0.5
	assert_true(pin_top < title_bottom - 0.03, "the Manor lamp (top %.2f) stays below the title (bottom %.2f)" % [pin_top, title_bottom])


# --- RE-08: falling leaves -------------------------------------------------------------------------------------------

func test_commons_leaves_are_leaf_shaped_and_fade_near_the_camera() -> void:
	var mesh: ArrayMesh = CommonsScript.leaf_mesh()
	var bb := mesh.get_aabb()
	assert_true(bb.size.x < 0.16 and bb.size.y < 0.16, "a small leaf (%s)" % bb.size)
	assert_true(mesh.surface_get_array_len(0) >= 36, "a lobed outline, not a 4-vertex card")
	var mat: StandardMaterial3D = CommonsScript.leaf_material()
	assert_ne(mat.distance_fade_mode, BaseMaterial3D.DISTANCE_FADE_DISABLED, "fades near the camera")
	assert_true(mat.distance_fade_min_distance >= 1.0 and mat.distance_fade_max_distance > mat.distance_fade_min_distance, "gone within ~1 m, full by ~2.6 m")


# --- RE-03 / RE-11: the Bellhouse pond and basin --------------------------------------------------------------------

static func _mesh_area(mesh: ArrayMesh) -> float:
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var a := 0.0
	for t in range(0, idx.size(), 3):
		a += (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]]).length() * 0.5
	return a


func test_pond_is_one_seamless_disc() -> void:
	var c := Vector2(10, -4)
	var r := 6.0
	var mesh: ArrayMesh = WaterScript.pond_mesh(c, r, 1.5, [])
	assert_not_null(mesh)
	var rr := r + WaterScript.POND_OVERHANG
	var expect := 0.5 * float(WaterScript.POND_SEGMENTS) * sin(TAU / float(WaterScript.POND_SEGMENTS)) * rr * rr
	var area := _mesh_area(mesh)
	assert_almost(area, expect, expect * 0.001, "no surface is drawn twice (area %.2f vs %.2f)" % [area, expect])
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rings := int(ceil(rr / WaterScript.POND_RING_STEP))
	assert_eq(v.size(), 1 + rings * WaterScript.POND_SEGMENTS, "every vertex is shared (one indexed grid)")
	for t in range(0, idx.size(), 3):
		var n := (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]])
		assert_true(n.y < 0.0, "triangle %d faces up (clockwise from above)" % (t / 3))
		if n.y >= 0.0:
			break
	for p in v:
		assert_almost(p.y, 1.5, 0.0001, "flat at the water level")
		if absf(p.y - 1.5) > 0.0001:
			break


func test_bellhouse_pond_covers_its_water_and_skips_the_tower() -> void:
	var w: Node3D = await _world()
	var t: RefCounted = w.get("terrain")
	var water: Node = w.get("water")
	var ponds: Array = t.get("ponds")
	var still: Array = []
	for c in water.get_children():
		if String(c.name).begins_with("StillWater"):
			still.append(c)
	assert_eq(still.size(), ponds.size(), "one still-water mesh per pond")
	var B: Dictionary = Reach.BELLHOUSE
	var pc: Vector2 = B["pond"]
	var pr: float = B["pond_radius"]
	var covered := 0
	for j in range(int(pc.y - pr), int(pc.y + pr) + 1):
		for i in range(int(pc.x - pr), int(pc.x + pr) + 1):
			if float(t.water_level_at(float(i), float(j))) > -999.0 and Vector2(i, j).distance_to(pc) <= pr + 1.0:
				assert_true(Vector2(i, j).distance_to(pc) <= pr + WaterScript.POND_OVERHANG, "water sample (%d, %d) is under the disc" % [i, j])
				covered += 1
	assert_true(covered > 150, "the pond really has water samples (%d)" % covered)
	var cut: Array = WaterScript.pond_cutouts(pc)
	assert_eq(cut.size(), 2, "the tower base and the stairwell stay dry")
	var mesh: ArrayMesh = (still[0] as MeshInstance3D).mesh
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k in range(0, idx.size(), 3):
		var ctr := (v[idx[k]] + v[idx[k + 1]] + v[idx[k + 2]]) / 3.0
		var tower: Rect2 = (B["tower"] as Rect2).grow(-0.4)
		assert_false(tower.has_point(Vector2(ctr.x, ctr.z)), "no water inside the tower")
		if tower.has_point(Vector2(ctr.x, ctr.z)):
			break
	# RE-11: the carved basin banks keep their grass colours (no bare, noisy rock patch around the tower)
	var bank := 0
	var rocky := 0
	for a in 24:
		var ang := TAU * float(a) / 24.0
		for d in [pr + 1.5, pr + 3.0]:
			var q := pc + Vector2(cos(ang), sin(ang)) * float(d)
			if absf(q.x - float(B["stair_x"])) < float(B["wall_outer"]) + 1.0 and q.y > pc.y:
				continue
			bank += 1
			if float(t.rock_at(q.x, q.y)) > 0.3:
				rocky += 1
	assert_true(bank > 20, "basin bank samples (%d)" % bank)
	print("basin banks: %d of %d samples rocky" % [rocky, bank])
	assert_true(rocky <= bank / 10, "the basin banks are not painted as rock (%d of %d)" % [rocky, bank])


# --- RE-06: the Candleyard's candle light -----------------------------------------------------------------------------

func test_candleyard_has_warm_light_pools_and_no_shadowed_lights() -> void:
	var h: Node3D = await flat_host()
	var c: Node3D = Candleyard.build_district(h)
	await wait_physics(1)
	var lights := 0
	for n in c.find_children("*", "Light3D", true, false):
		assert_false((n as Light3D).shadow_enabled, "%s casts no shadows (the scene's shadowed-light budget stays free)" % n.name)
		lights += 1
	assert_true(lights <= 7, "the Candleyard's share of the west districts' 8-light budget (%d)" % lights)
	var warm: Array = c.get("candle_lights")
	var pools: Array = c.get("candle_pools")
	assert_true(warm.size() >= 1 and warm.size() <= 3, "a warm light over the Candle Tree ring and the lit gates (%d)" % warm.size())
	assert_true(pools.size() >= 6, "warm glow pools under the candle clusters (%d)" % pools.size())
	for w in warm:
		var o: OmniLight3D = w[0]
		assert_true(o.omni_range <= 7.0, "a pool, not a floodlight (%.1f m)" % o.omni_range)
		assert_true(o.light_color.r > o.light_color.b, "warm")
	for pl in pools:
		var d: Decal = pl[0]
		assert_not_null(d.texture_emission, "an emission-only glow (no Light3D)")
		assert_true(d.modulate.r > d.modulate.b, "warm glow")
	GameState.total_minutes = 60.0 * 23.0
	Art.set_daylight(0.0)
	c.update_lights()
	for w2 in warm:
		assert_true((w2[0] as OmniLight3D).visible and (w2[0] as OmniLight3D).light_energy > 0.8, "lit at night")
	for p2 in pools:
		assert_true((p2[0] as Decal).visible and (p2[0] as Decal).emission_energy > 0.3, "glowing at night")
	var mpool: Decal = c.get("_marker_pool")
	assert_false(mpool.visible, "the empty candle dish does not glow before her candle is lit")
	GameState.set_flag(Data.FLAG_LIGHT_PLACED, true)
	c._apply_state()
	c.update_lights()
	assert_true(mpool.visible, "her lit candle warms the ground at night")
	GameState.total_minutes = 60.0 * 12.0
	Art.set_daylight(1.0)
	c.update_lights()
	for w3 in warm:
		assert_false((w3[0] as OmniLight3D).visible, "off by day")
	for p3 in pools:
		assert_false((p3[0] as Decal).visible, "no glow by day")
	var fb := Art.flame().get_aabb()
	assert_true(fb.size.y >= 0.06, "flames are ~7 cm teardrops, not 6 cm dots (%.3f)" % fb.size.y)
	var flames: MultiMeshInstance3D = c.get_node("CandleFlames")
	var halos: MultiMeshInstance3D = c.get_node("CandleHalos")
	assert_eq(halos.multimesh.instance_count, flames.multimesh.instance_count, "a soft halo around every flame")
	assert_eq(halos.material_override, Art.halo_material(), "one shared halo material")
	assert_eq(halos.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


# --- RE-18: carved jack-o'-lanterns in the Commons ---------------------------------------------------------------------

func test_commons_has_carved_jack_o_lanterns() -> void:
	var w: Node3D = await _world()
	var commons: Node = w.get("commons")
	var faces: MultiMeshInstance3D = commons.get_node_or_null("JackOLanternFaces")
	assert_not_null(faces)
	if faces != null:
		assert_true(faces.multimesh.instance_count >= 4, "a few jack-o'-lanterns at the arch and the arrival (%d)" % faces.multimesh.instance_count)
		assert_eq(faces.material_override, Art.carved_material(), "faces follow the day / night glow")


# --- RE-15: the brook's exit gorge ------------------------------------------------------------------------------------

func test_brook_exit_gorge_bends_out_of_sight() -> void:
	var w: Node3D = await _world()
	var t: RefCounted = w.get("terrain")
	var pts: PackedVector3Array = t.get("stream_pts")
	var last: Vector3 = pts[pts.size() - 1]
	var raw: Vector2 = Reach.BROOK_POINTS[Reach.BROOK_POINTS.size() - 1]
	assert_true(last.x < raw.x - TerrainScript.GORGE_BEND * 0.8, "beyond the south wall the gorge swings west (x %.1f)" % last.x)
	for p in pts:
		if p.z <= Reach.WALL_HALF_Z:
			assert_true(p.x > -40.0, "inside the walls the brook keeps its course (%.1f, %.1f)" % [p.x, p.z])


# --- RE-12: the Ashbell's bell profile --------------------------------------------------------------------------------

func test_ashbell_has_a_flared_bell_profile() -> void:
	var lip := QV.ashbell_radius(-0.62)
	var waist := QV.ashbell_radius(0.85)
	assert_true(lip > waist * 1.6, "a flared lip (%.2f) over a narrow waist (%.2f)" % [lip, waist])
	var prev := INF
	for y in [-0.6, -0.3, 0.0, 0.4, 0.8, 1.2]:
		var r := QV.ashbell_radius(float(y))
		assert_true(r <= prev + 0.001, "the profile narrows toward the shoulder")
		prev = r


# --- RE-19: Chapter One moonbells glow at night ------------------------------------------------------------------------

func test_moonbells_glow_and_light_the_shore_only_at_night() -> void:
	var pocket: Node3D = MothPocket.Pocket.new()
	add_child(pocket)
	pocket.build_blooms([Transform3D(Basis(), Vector3(0, 0, 0)), Transform3D(Basis(), Vector3(1, 0, 0))])
	pocket.hour_override = 12.0
	pocket.update()
	assert_false((pocket.get("glow_caps") as Node3D).visible, "no glow by day")
	assert_false((pocket.get("glow_light") as Node3D).visible)
	pocket.hour_override = 21.0
	pocket.update()
	assert_true((pocket.get("glow_caps") as Node3D).visible, "the bell caps glow at night")
	assert_true((pocket.get("halos") as Node3D).visible)
	var light: OmniLight3D = pocket.get("glow_light")
	assert_true(light.visible and not light.shadow_enabled, "a small unshadowed moonlight lamp")
	pocket.queue_free()


func test_meadow_sunflax_stands_clear_of_the_grass() -> void:
	var MeadowPatch: Script = load("res://src/world/surface/c1x/meadow_patch.gd")
	var C1xLayout: Script = load("res://data/c1x_layout.gd")
	var Common: Script = load("res://src/world/surface/c1x/common.gd")
	var cl: Array = MeadowPatch.call("grass_clearings")
	var sunflax: Array = C1xLayout.get("SUNFLAX")
	assert_eq(cl.size(), sunflax.size(), "the grass is trimmed round every sunflax clump")
	for c in cl:
		assert_true(float(c[1]) >= 1.0, "a clearing wider than the clump")
	var v: Node3D = Common.call("sunflax_visual", 0)
	add_child(v)
	var heads: MeshInstance3D = v.get_node("Berries")
	assert_true(heads.mesh.get_aabb().end.y >= 0.95, "golden heads rise above the meadow grass (%.2f m)" % heads.mesh.get_aabb().end.y)
	v.queue_free()


# --- RE-10: the quarry's cut faces are its own copper rock (no pale grey teeth between the cliff boulders) ------------

func test_quarry_cut_faces_are_copper_not_grey() -> void:
	var w: Node3D = await _world()
	var t: RefCounted = w.get("terrain")
	var Q: Script = load("res://data/reach_east.gd")
	var centre: Vector2 = Q.get("CENTER")
	var rock: PackedFloat32Array = t.get("rock")
	var splat: PackedByteArray = t.get("splat")
	var col: PackedColorArray = t.get("col")
	var steep := 0
	for j in range(int(centre.y - 26.0), int(centre.y + 26.0)):
		for i in range(int(centre.x - 26.0), int(centre.x + 26.0)):
			if Vector2(i, j).distance_to(centre) > 26.0:
				continue
			var k: int = t.index_of(float(i), float(j))
			if rock[k] < 0.6:
				continue
			steep += 1
			assert_true(float(splat[k * 4 + 2]) / 255.0 < 0.34, "(%d, %d): no grey rock splat on the quarry's cut faces" % [i, j])
			var c: Color = col[k]
			assert_true(c.r > c.b + 0.12, "(%d, %d): copper, not grey (%s)" % [i, j, c])
			if float(splat[k * 4 + 2]) / 255.0 >= 0.34:
				break
	assert_true(steep > 20, "the terraces really have steep faces (%d samples)" % steep)
