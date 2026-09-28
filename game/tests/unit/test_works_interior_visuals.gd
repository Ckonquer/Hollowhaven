extends "res://tests/test_case.gd"
## Hushed Works interior readability (qa/tmp/visual VISUAL_BUGS IN-06, IN-07, IN-08, IN-10, IN-11, IN-12):
## lift signs fit their 2 m boards and can be seen from the rooms they face (the wrong landing's recess
## lintel hid both, with the false lift's backwards-sign cue); authored signs are single-sided (no mirrored
## letters from behind) except the deliberately mirrored false-lift sign; the crossing gate's bridge sign hangs
## over the doorway ahead of the arrival, clear of the camera; web veils are silk (web-shader quads + threads),
## never a flat sheet; resonator names sit above their plates; the bellmakers' order board stands clear of
## the rock dressing; the bell strikers carry their symbol on both faces.
## Integration pass 3: the bridge sign's top line is in clear view of the crossing_gate arrival camera (no winch rock
## hangs into the gate doorway, dressing RNG unchanged: R3-35); a lift fits its own sign, keeps the false one
## double-sided and hangs it at "sign_pos" (R3-41); the Choir echo trial's order board shows a crescent Moon (R3-42).

const Host := preload("res://src/world/works/deep/deep_preview_host.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const UpperLayout := preload("res://data/works_layout.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const ThreadScript := preload("res://src/world/works/deep/deep_thread.gd")
const Resonator := preload("res://src/world/works/deep/resonator.gd")
const Throat := preload("res://src/world/works/deep/throat.gd")
const Bells := preload("res://src/world/works/works_bells.gd")
const Lift := preload("res://src/world/works/deep/deep_lift.gd")
const Rig := preload("res://src/camera/camera_rig.gd")
const Logic := preload("res://src/player/player_logic.gd")
const ChoirTrial := preload("res://src/world/trial/choir_trial.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const RoomsDeep := preload("res://src/world/works/rooms_deep.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const MASK := 1 | 32
const BOARD_W := Lift.SIGN_BOARD_W

var host: Node3D = null
var extra: Node = null
var _extras: Array = []
var _batch_data: Array = []
var _saved := {}


func before_each() -> void:
	fresh_state()
	for k in ["arachnophobia", "high_visibility_cues"]:
		_saved[k] = Settings.get_value(k)
	Settings.set_value("arachnophobia", false)


func after_each() -> void:
	for n in [host, extra] + _extras:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	host = null
	extra = null
	_extras.clear()
	_batch_data.clear()
	for k in _saved:
		Settings.set_value(k, _saved[k])
	await wait_frames(2)


func _make() -> Node3D:
	var h: Node3D = Host.new()
	h.set("with_environment", false)
	add_child(h)
	await wait_physics(3)
	host = h
	return h


func _ctl() -> Node:
	return host.get("deep")


func _label(n: Node) -> Label3D:
	var ls := n.find_children("*", "Label3D", false, false)
	return ls[0] as Label3D if not ls.is_empty() else null


func _labels_with(text_part: String) -> Array:
	return host.find_children("*", "Label3D", true, false).filter(func(l: Node) -> bool: return (l as Label3D).text.contains(text_part))


func _blocked(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return host.get_world_3d().direct_space_state.intersect_ray(q)


func test_lift_signs_fit_their_boards_and_are_seen_from_the_landing() -> void:
	await _make()
	for id in ["hw_winch_cage", "hw_lift_real", "hw_lift_false"]:
		var lift: Node3D = _ctl().call("lift", id)
		assert_not_null(lift, "lift %s" % id)
		var l := _label(lift)
		assert_not_null(l, "%s carries a sign" % id)
		if l == null:
			continue
		var w := Art.label_width(l)
		assert_true(w <= BOARD_W - 0.1, "%s sign text fits its %.1f m board (%.2f m)" % [id, BOARD_W, w])
		print("    %s sign: %d px, %.2f m wide" % [id, l.font_size, w])
	var landing_floor := float(Layout.ROOMS["hw_wrong_landing"]["y"])
	for id in Layout.LIFTS:
		var lift: Node3D = _ctl().call("lift", id)
		var l := _label(lift)
		if l == null:
			continue
		var at := l.global_position
		var eye := Vector3(at.x, landing_floor + 1.7, float(Layout.ROOMS["hw_wrong_landing"]["z0"]) + 5.0)
		# stop 2 cm short of the text (the board behind it is visual only)
		var hit := _blocked(eye, at + (eye - at).normalized() * 0.02)
		assert_true(hit.is_empty(), "the %s sign is in plain view from the landing (hit: %s)" % [id, str(hit.get("collider", ""))])
	var fake := _label(_ctl().call("lift", "hw_lift_false"))
	var real := _label(_ctl().call("lift", "hw_lift_real"))
	assert_true(fake.scale.x < 0.0 and fake.double_sided, "the false lift's backwards sign stays drawn (mirrored + double-sided)")
	assert_false(real.double_sided, "the true lift's sign is single-sided")


func test_authored_signs_read_from_the_front_only() -> void:
	await _make()
	for part in ["WINCH No. 3", "WINCH CAGE", "SERVICE BRIDGE", "MIND WHICH LAMP", "LANDING", "IT HAS LEARNED", "BELLMAKERS"]:
		var found := _labels_with(part)
		assert_false(found.is_empty(), "sign '%s' exists" % part)
		for l in found:
			var lb := l as Label3D
			assert_eq(lb.billboard, BaseMaterial3D.BILLBOARD_DISABLED, "'%s' is a wall sign" % part)
			assert_false(lb.double_sided, "'%s' shows no mirrored letters from behind" % part)


func test_crossing_gate_sign_hangs_over_the_doorway_ahead() -> void:
	await _make()
	var found := _labels_with("SERVICE BRIDGE")
	assert_eq(found.size(), 1, "one bridge sign")
	if found.is_empty():
		return
	var l := found[0] as Label3D
	var s: Dictionary = Layout.SPAWNS["crossing_gate"]
	var sp: Vector3 = s["pos"]
	var yaw := deg_to_rad(float(s["yaw"]))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rel := l.global_position - sp
	assert_true(rel.y >= 3.0, "above camera height in the low gate room (%.2f m over the floor)" % rel.y)
	assert_true(Vector3(rel.x, 0, rel.z).dot(fwd) > 2.0, "ahead of the arrival, not behind or beside it")
	assert_true(l.visibility_range_begin > 1.0, "the text hides when the camera passes right under it")
	# it faces the arrival: its front (+Z of the label) points back toward the spawn
	var facing := l.global_transform.basis.z
	assert_true(facing.dot(-fwd) > 0.9, "readable from the arrival side")
	assert_true(Art.label_width(l) <= 2.3, "fits its board")


## Points along a label's top line, in world space: the top of its text box and the middle of its first line, each at
## the left end, a quarter, the centre, three quarters and the right end of the text.
func _label_top_points(l: Label3D) -> Array:
	var f: Font = l.font if l.font != null else ThemeDB.fallback_font
	var lines := l.text.split("
").size()
	var h := (f.get_height(l.font_size) * float(lines) + l.line_spacing * float(lines - 1)) * l.pixel_size
	var line_h := h / float(lines)
	var half_w := Art.label_width(l) * 0.5
	var out: Array = []
	for y in [h * 0.5, h * 0.5 - line_h * 0.5]:
		for x in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			out.append(l.global_transform * Vector3(float(x) * half_w, float(y), 0.0))
	return out


## Builds rooms 9-14 on a bare area exactly like deep_preview_host.gd (Builder -> RoomsDeep.build -> finish), keeping
## the builder's batch list: headless, a MultiMesh reports no instance transforms, so the batched visuals (walls, rock
## blobs, props) are checked from that list. -> the area (also `host`); _batch_data = [{mesh, xf: [Transform3D], room}].
func _make_keeping_batches() -> Node3D:
	var a := Node3D.new()
	a.set_script(AreaBase)
	add_child(a)
	host = a
	var rooms: Dictionary = Host.STUB_HUB.duplicate(true)
	rooms.merge(Layout.ROOMS)
	var b: Builder = Builder.new(a, 4242, rooms)
	RoomsDeep.build(a, b)
	_batch_data.clear()
	var pending: Dictionary = b.get("_batches")
	for key in pending:
		_batch_data.append(pending[key])
	b.finish()
	await wait_physics(3)
	return a


## The first visible triangle on the segment from -> to - batched room visuals (rock blobs have no collider, so a
## physics ray never sees them) and mesh nodes: {} when clear, else {"what", "origin", "at"}.
func _visual_block(from: Vector3, to: Vector3) -> Dictionary:
	var sets: Array = []
	for bd in _batch_data:
		sets.append({"mesh": bd["mesh"], "xf": bd["xf"], "what": "%s batch %s" % [bd["room"], str(bd["mesh"])]})
	for n in host.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			sets.append({"mesh": mi.mesh, "xf": [mi.global_transform], "what": str(host.get_path_to(mi))})
	for s in sets:
		var mesh: Mesh = s["mesh"]
		var aabb := mesh.get_aabb()
		var faces := PackedVector3Array()
		for xf in s["xf"]:
			var t := xf as Transform3D
			if t.basis.determinant() == 0.0 or (t * aabb).grow(0.01).intersects_segment(from, to) == null:
				continue
			if faces.is_empty():
				faces = mesh.get_faces()
			var inv := t.affine_inverse()
			var lf := inv * from
			var lt := inv * to
			for k in range(0, faces.size() - 2, 3):
				var p: Variant = Geometry3D.segment_intersects_triangle(lf, lt, faces[k], faces[k + 1], faces[k + 2])
				if p != null:
					return {"what": s["what"], "origin": t.origin, "at": t * (p as Vector3)}
	return {}


## Integration pass 3 R3-35: from the crossing_gate arrival camera (the real follow rig, default zoom and pitch,
## snapped behind a stand-in at the spawn) the sign's top line was cut by a rock lump: the winch hall's east-wall
## dressing above the 3.4 m gate opening sat inside the low gate room and hung into the doorway
## (fix_cameras/after_crossing/crop_sign.png). Nothing visible or solid may lie on the camera -> top-line rays.
func test_crossing_gate_sign_top_is_in_clear_view_of_the_arrival_camera() -> void:
	GameState.set_flag("hw_thread_winch_exit_burned", true)     # she came through the winch exit veil to get here
	await _make_keeping_batches()
	var found := _labels_with("SERVICE BRIDGE")
	assert_eq(found.size(), 1, "one bridge sign")
	if found.is_empty():
		return
	var l := found[0] as Label3D
	var xf := Layout.spawn_xform("crossing_gate")
	var stand := Node3D.new()
	host.add_child(stand)
	stand.global_position = xf.origin
	var rig: Node3D = Rig.new()
	host.add_child(rig)
	rig.call("setup", stand)
	rig.set("zoom_target", 5.0)
	rig.set("_zoom", 5.0)
	var f := -xf.basis.z
	rig.call("snap", Logic.yaw_for_dir(Vector3(f.x, 0.0, f.z).normalized()))
	await wait_physics(2)
	await wait_frames(2)
	var cam := (rig.call("get_camera") as Camera3D).global_position
	print("    crossing_gate arrival camera %s (arm %.2f m), sign at %s, %d px" % [str(cam), float(rig.call("arm_length")), str(l.global_position), l.font_size])
	assert_true(float(rig.call("arm_length")) > 3.0, "a proper third-person arm at the arrival")
	# the visual check is not blind: the gate room's floor is in the way of a ray aimed below it
	assert_false(_visual_block(cam, Vector3(64.0, -18.5, 0.5)).is_empty(), "the visual ray check sees the batched room geometry")
	for top in _label_top_points(l):
		var p := top as Vector3
		var end := p + (cam - p).normalized() * 0.02
		var solid := _blocked(cam, end)
		assert_true(solid.is_empty(), "nothing solid between the camera and the sign's top line at %s (hit %s)" % [str(p), str(solid.get("collider", ""))])
		var seen := _visual_block(cam, end)
		assert_true(seen.is_empty(), "nothing visible between the camera and the sign's top line at %s (%s centred at %s, hit at %s)" % [str(p), str(seen.get("what", "")), str(seen.get("origin", "")), str(seen.get("at", ""))])
	rig.queue_free()
	stand.queue_free()


## Rock blobs (batched) centred above `above_y` with a vertex inside `box` (they hang into it): [origin, ...].
## Without `above_y` (-INF) every blob whose box reaches into `box` counts.
func _blobs_in(b: Builder, box: AABB, above_y: float = -INF) -> Array:
	var out: Array = []
	var pending: Dictionary = b.get("_batches")
	for key in pending:
		var bd: Dictionary = pending[key]
		var mesh: Mesh = bd["mesh"]
		if not (mesh is ArrayMesh):          # blobs; walls / props are boxes and cylinders
			continue
		var faces := PackedVector3Array()
		for xf in bd["xf"]:
			var t := xf as Transform3D
			if not (t * mesh.get_aabb()).intersects(box):
				continue
			if above_y == -INF:
				out.append(t.origin)
				continue
			if t.origin.y <= above_y:
				continue
			if faces.is_empty():
				faces = mesh.get_faces()
			for v in faces:
				if box.has_point(t * v):
					out.append(t.origin)
					break
	return out


## R3-35 fix: the winch hall's east wall is dressed with its gate opening kept clear up to the gate room's height -
## no rock of it reaches into the doorway any more - and the dressing RNG ends exactly where the unchanged dressing
## left it, so every room dressed after the winch keeps its rocks (no reshuffle of the deep rooms' dressing).
func test_winch_keep_clear_over_the_gate_keeps_the_dressing_rng() -> void:
	var rooms: Dictionary = Layout.ROOMS
	var gate: Dictionary = rooms["hw_crossing_gate"]
	var winch: Dictionary = rooms["hw_winch"]
	# the doorway of the gate room seen from the hall: its west end, up to the hall's 3.4 m opening
	var y0 := float(gate["y"])
	var doorway := AABB(Vector3(float(winch["x1"]), y0, -1.6), Vector3(2.0, 3.4, 3.2))
	var plain: Builder = Builder.new(null, 5, rooms)
	var fixed: Builder = Builder.new(null, 5, rooms)
	plain.rng.seed = Layout.DRESS_SEED
	fixed.rng.seed = Layout.DRESS_SEED
	plain.dress_room_rock("hw_winch", RoomsDeep.WINCH_ROCK, RoomsDeep.WINCH_DRESS)
	RoomsDeep._dress_rock_as(fixed, "hw_winch", {"e": [[-1.6, 1.6, float(gate["h"])]]}, RoomsDeep.WINCH_ROCK, RoomsDeep.WINCH_DRESS)
	var top := y0 + 3.4
	var before := _blobs_in(plain, doorway, top)
	var after := _blobs_in(fixed, doorway, top)
	print("    winch rocks hanging into the gate doorway: %d before %s, %d after" % [before.size(), str(before), after.size()])
	assert_true(before.size() >= 1, "the unchanged dressing hung a lump into the doorway (the case this guards)")
	assert_eq(after.size(), 0, "no winch rock hangs into the gate doorway")
	assert_eq(fixed.rng.state, plain.rng.state, "the dressing RNG continues where the unchanged dressing left it")
	# the rest of the hall keeps its dressing (only the rocks over the gate are skipped)
	var hall := AABB(Vector3(float(winch["x0"]) - 2.0, y0 - 1.0, float(winch["z0"]) - 2.0), Vector3(float(winch["x1"]) - float(winch["x0"]) + 4.0, 14.0, float(winch["z1"]) - float(winch["z0"]) + 4.0))
	var all_before := _blobs_in(plain, hall).size()
	var all_after := _blobs_in(fixed, hall).size()
	assert_true(all_after >= all_before - 8 and all_after < all_before, "only a few rocks over the gate go (%d -> %d)" % [all_before, all_after])


## R3-41: a lift fits its own sign (no caller has to), the false lift's mirrored sign stays drawn, and "sign_pos"
## hangs the board + label elsewhere (default: over the cage mouth).
func test_a_lift_built_on_its_own_fits_its_sign_and_keeps_the_false_one_drawn() -> void:
	var long_text := "LIFT - REFUGE LEVEL - MIND THE GATE"
	for kind in ["true", "false", "bell"]:
		var lift: Node3D = Lift.new()
		lift.setup({"id": "t_lift_" + kind, "kind": kind, "sign": long_text})
		add_child(lift)
		_extras.append(lift)
		var l := _label(lift)
		assert_not_null(l, "%s lift carries its sign" % kind)
		if l == null:
			continue
		var w := Art.label_width(l)
		assert_true(w <= Lift.SIGN_TEXT_WIDTH + 0.001, "%s lift: the sign fits its board on its own (%.2f m, %d px)" % [kind, w, l.font_size])
		assert_almost(l.position.y, Lift.SIGN_POS.y, 0.001, "%s lift: default sign height" % kind)
		assert_almost(l.position.z, Lift.SIGN_POS.z - 0.05, 0.001, "%s lift: label 5 cm in front of the board" % kind)
		if kind == "false":
			assert_true(l.scale.x < 0.0, "the false sign reads backwards")
			assert_true(l.double_sided, "the false sign is double-sided (a mirrored single-sided label is culled from the front)")
		else:
			assert_false(l.double_sided, "%s lift: an ordinary single-sided sign" % kind)
	# a short sign keeps its size (fitting never grows or shrinks what already fits)
	var short: Node3D = Lift.new()
	short.setup({"id": "t_lift_short", "kind": "bell", "sign": "REFUGE"})
	add_child(short)
	_extras.append(short)
	assert_eq(_label(short).font_size, 34, "a short sign is left at its size")
	# sign_pos moves the board and the label together
	var moved: Node3D = Lift.new()
	var at := Vector3(0.0, 3.74, -2.34)
	moved.setup({"id": "t_lift_moved", "kind": "false", "sign": "LIFT - REFUGE LEVEL", "sign_pos": at})
	add_child(moved)
	_extras.append(moved)
	var ml := _label(moved)
	assert_true(ml.position.distance_to(at + Vector3(0, 0, -0.05)) < 0.001, "the label hangs at sign_pos (%s)" % str(ml.position))
	var board := moved.get_node_or_null("SignBoard") as Node3D
	assert_not_null(board, "the sign board")
	if board != null:
		assert_true(board.position.distance_to(at) < 0.001, "the board hangs at sign_pos (%s)" % str(board.position))


## R3-42: the Choir echo trial's copy of the bellmakers' order board paints its Moon's "bite" in the sheet colour,
## so it reads as a crescent (like the real board in the Bell Throat), not as a black hole.
func test_trial_order_board_moon_is_a_crescent() -> void:
	var holder := Node3D.new()
	add_child(holder)
	_extras.append(holder)
	var board: Node3D = ChoirTrial._order_board(holder, Layout.bell_symbols())
	var moon: Node = board.get_node_or_null("Symbol_moon")
	assert_not_null(moon, "the trial board shows the Moon")
	if moon == null:
		return
	var meshes := moon.find_children("*", "MeshInstance3D", false, false)
	assert_true(meshes.size() >= 2, "disc + bite")
	if meshes.size() < 2:
		return
	var bite := (meshes[1] as MeshInstance3D).material_override as ShaderMaterial
	assert_not_null(bite, "the bite has a toon material")
	if bite != null:
		var c: Color = bite.get_shader_parameter("albedo")
		assert_true(c.get_luminance() > 0.5, "the bite is painted in the board's sheet colour (%s)" % str(c))


func test_web_veils_are_silk_not_sheets() -> void:
	await _make()
	var threads: Dictionary = _ctl().get("threads")
	assert_false(threads.is_empty(), "the deep rooms have thread veils")
	for id in threads:
		var t: Node = threads[id]
		var veil: Node = t.get_node_or_null("Veil")
		assert_not_null(veil, "%s has a veil" % id)
		if veil == null:
			continue
		assert_true(veil.is_in_group("hw_thread_web"), "%s: web variant" % id)
		var webs := 0
		for c in veil.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				assert_false(mi.mesh is BoxMesh, "%s: no flat backing sheet / card (%s)" % [id, mi.name])
				var m := mi.material_override
				if m is ShaderMaterial and (m as ShaderMaterial).shader == ThreadScript.WEB_SHADER:
					webs += 1
		assert_true(webs >= 1, "%s: drawn as real web (%d web quads)" % [id, webs])
	# the arena's fight threads are the same silk
	var arena: Node = _ctl().get("crossing")
	var ft: Node = arena.call("spawn_thread", Vector3(80.0, -18.0, -4.0), Vector3(80.0, -18.0, 4.0), 5.0, 0)
	var fv: Node = ft.get_node_or_null("Veil")
	assert_true(fv != null and fv.find_children("Web*", "MeshInstance3D", false, false).size() >= 2, "an 8 m fight thread is tiled with webs")


func test_resonator_names_sit_above_their_plates() -> void:
	await _make()
	var choir: Node = _ctl().get("choir")
	assert_not_null(choir, "choir arena")
	if choir == null:
		return
	for r in choir.call("resonator_nodes"):
		for holder in (r as Node).find_children("Plate_*", "Node3D", false, false):
			var names := (holder as Node).find_children("Name", "Label3D", true, false)
			assert_eq(names.size(), 1, "%s names its symbol" % holder.name)
			if names.is_empty():
				continue
			var l := names[0] as Label3D
			var half_h := float(l.font_size) * l.pixel_size * 0.5
			var lowest := l.global_position.y - half_h - (holder as Node3D).global_position.y
			assert_true(lowest > Resonator.PLATE_RADIUS, "%s: the name clears the plate's rim (%.2f > %.2f)" % [holder.name, lowest, Resonator.PLATE_RADIUS])


func test_order_board_stands_clear_of_the_rock_and_its_moon_is_a_crescent() -> void:
	await _make()
	var throat: Node = _ctl().get("throat")
	assert_not_null(throat, "bell throat")
	if throat == null:
		return
	var board: Node3D = throat.get_node_or_null("OrderBoard")
	assert_not_null(board, "order board")
	var wall: Vector3 = Layout.THROAT["order_board"]
	assert_true(wall.x - board.global_position.x >= Throat.ORDER_BOARD_OUT - 0.01, "stands %.2f m out of the rocky east wall" % Throat.ORDER_BOARD_OUT)
	var moon: Node = board.get_node_or_null("Symbol_moon")
	assert_not_null(moon, "the moon glyph")
	if moon != null:
		var meshes := moon.find_children("*", "MeshInstance3D", false, false)
		assert_true(meshes.size() >= 2, "disc + bite")
		var bite := (meshes[1] as MeshInstance3D).material_override as ShaderMaterial
		var c: Color = bite.get_shader_parameter("albedo")
		assert_true(c.get_luminance() > 0.5, "the bite is painted in the board's colour, not a black hole (%s)" % str(c))


func test_bell_strikers_show_their_symbol_on_both_faces() -> void:
	var b: Node3D = Bells.new()
	extra = b
	add_child(b)
	await wait_frames(1)
	for sym in UpperLayout.BELLS:
		var s: Node = b.get_node_or_null("Striker_" + String(sym))
		assert_not_null(s, "striker %s" % sym)
		if s == null:
			continue
		var glyphs := s.find_children("Glyph*", "Node3D", false, false)
		assert_eq(glyphs.size(), 2, "%s: symbol on the front and on the back" % sym)
		if glyphs.size() == 2:
			var f := (glyphs[0] as Node3D).global_transform.basis.z
			var k := (glyphs[1] as Node3D).global_transform.basis.z
			assert_true(f.dot(k) < -0.9, "%s: the two glyphs face opposite ways" % sym)
