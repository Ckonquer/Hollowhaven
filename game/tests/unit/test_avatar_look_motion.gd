extends "res://tests/test_case.gd"
## Krystal's appearance in motion: skirt / dress panels stay bounded and outside the legs while running,
## rolling, jumping, taking stairs and sitting; hats / helms / tall hair respect the roll head hull; hair and
## cape springs swing and settle (capes never into the back); a preview avatar stays independent of GameState.

const AvatarScript := preload("res://src/player/krystal_avatar.gd")
const SkirtRig := preload("res://src/player/avatar/skirt_rig.gd")
const DT := 1.0 / 60.0

var _nodes: Array = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			(n as Node).free()
	_nodes.clear()


## A driven avatar that does not follow GameState (so the test controls the look and the motion).
func _avatar(look: Dictionary) -> Node3D:
	var av: Node3D = AvatarScript.new()
	av.driven = true
	av.follow_game_state = false
	av.call("apply_look", look)
	add_child(av)
	_nodes.append(av)
	return av


func _with(slot: String, id: String) -> Dictionary:
	var look := ItemDB.legacy_look()
	look[slot] = id
	return look


func _step(av: Node3D, n: int, move: Vector3 = Vector3.ZERO) -> void:
	for i in n:
		av.global_position += move * DT
		av.call("_process", DT)


## Every panel within its bounds, pivots posed from the rig, and no leg sample point outside the skirt unless
## the rig is at its clamp (only allowed where `allow_clamp`). Returns the number of clamped panels.
func _check_skirt(av: Node3D, what: String, allow_clamp: bool) -> int:
	var rig: SkirtRig = av.get("_skirt")
	var pivots: Array = av.get("_skirt_pivots")
	var clamped := 0
	for i in rig.count:
		var f: float = rig.flare[i]
		assert_true(f >= rig.min_flare - 0.0001 and f <= rig.max_flare + 0.0001, "%s: panel %d flare %.3f in bounds" % [what, i, f])
		assert_true(absf(rig.side[i]) <= rig.max_side + 0.0001, "%s: panel %d side %.3f in bounds" % [what, i, rig.side[i]])
		assert_false(is_nan(f), what + " no NaN")
		var need := rig.required_flare(i)
		if need > f + 0.0001:
			clamped += 1
			if not allow_clamp:
				fail("%s: a leg pokes through panel %d (needs %.2f, has %.2f)" % [what, i, need, f])
		var pv := pivots[i] as Node3D
		assert_almost(pv.rotation.x, -f, 0.0001, "%s: panel %d posed" % [what, i])
	if not allow_clamp:
		_check_legs_inside(av, what)
	return clamped


## Real geometry: the knee and mid-thigh (joint node positions) of each leg are on the inner side of the
## nearest panel (panel space z < -margin) or below its hem.
func _check_legs_inside(av: Node3D, what: String) -> void:
	var rig: SkirtRig = av.get("_skirt")
	var pivots: Array = av.get("_skirt_pivots")
	var joints: Array = av.get("_joints")
	var hips := joints[AvatarScript.J_HIPS] as Node3D
	for side in 2:
		var leg := joints[AvatarScript.J_LEG_L + side] as Node3D
		var knee := joints[AvatarScript.J_KNEE_L + side] as Node3D
		for p in [leg.global_position.lerp(knee.global_position, 0.5), knee.global_position]:
			var hp: Vector3 = hips.global_transform.affine_inverse() * (p as Vector3)
			var ang := atan2(hp.x, hp.z)
			var best := 0
			var best_d := INF
			for i in rig.count:
				var d := absf(angle_difference(ang, rig.theta[i]))
				if d < best_d:
					best_d = d
					best = i
			var local: Vector3 = (pivots[best] as Node3D).global_transform.affine_inverse() * (p as Vector3)
			var inside := local.z < -0.05 or local.y < -rig.length
			assert_true(inside, "%s: leg %d point pierces panel %d (local %s)" % [what, side, best, local])


func test_skirt_panels_stay_bounded_and_outside_the_legs() -> void:
	for lower in ["pleated_skirt_leggings", "pinafore_skirt", "moonflower_dress", "moth_long_skirt", "tulle_party_dress", "witch_dress", "velvet_dress"]:
		var av := _avatar(_with("lower", lower))
		var rig: SkirtRig = av.get("_skirt")
		assert_not_null(rig, lower + " has a skirt rig")
		if rig == null:
			continue
		# idle
		_step(av, 30)
		_check_skirt(av, lower + " idle", false)
		# walk then sprint forward (the model faces +Z)
		av.set("speed", 4.2)
		for i in 60:
			_step(av, 1, Vector3(0, 0, 4.2))
			_check_skirt(av, lower + " walk", false)
		av.set("speed", 7.0)
		av.set("sprinting", true)
		var back_max := 0.0
		for i in 90:
			_step(av, 1, Vector3(0, 0, 7.0))
			_check_skirt(av, lower + " run", false)
			back_max = maxf(back_max, rig.flare[rig.count / 2])
		assert_true(back_max > rig.base_flare + 0.05, "%s: the back panel trails while running (%.2f)" % [lower, back_max])
		# roll (dodge): tucked legs may exceed the clamp, but never the bounds; the hem stays (nearly) out of the
		# ground - the travel drive fades while tumbling (before the review fix the witch dress dipped 0.11 m).
		var roll_low := INF
		for i in 28:
			av.set("roll_t", float(i) / 27.0)
			_step(av, 1, Vector3(0, 0, 6.0))
			_check_skirt(av, lower + " roll", true)
			roll_low = minf(roll_low, _unit_low(av, "lower"))
		assert_true(roll_low > -0.08, "%s: the hem dips %.3f m into the ground during a roll" % [lower, roll_low])
		av.set("roll_t", -1.0)
		# jump: up, then falling (the skirt billows, still bounded, legs inside)
		av.set("grounded", false)
		for i in 50:
			var vy := 6.0 - 18.0 * float(i) * DT
			av.set("vertical_speed", vy)
			_step(av, 1, Vector3(0, vy, 7.0))
			_check_skirt(av, lower + " jump", false)
		av.set("grounded", true)
		av.set("vertical_speed", 0.0)
		# stairs: 0.25 m steps every 12 frames while walking
		av.set("speed", 4.2)
		av.set("sprinting", false)
		for i in 72:
			if i % 12 == 0:
				av.global_position.y += 0.25
			_step(av, 1, Vector3(0, 0, 4.2))
			_check_skirt(av, lower + " stairs", false)
		# sitting (sleep): legs forward, panels open up to the clamp and stay there
		av.set("speed", 0.0)
		av.call("play_action", "sleep")
		_step(av, 60)
		_check_skirt(av, lower + " sit", true)
		var front := rig.flare[0]
		assert_true(front > 1.0, "%s: sitting opens the front panel (%.2f)" % [lower, front])
		av.call("cancel_action")
		_step(av, 60)
		_check_skirt(av, lower + " stand again", false)
		av.free()


func test_skirt_rig_is_bounded_for_any_input() -> void:
	var rig := SkirtRig.new()
	var th: Array = []
	for i in 8:
		th.append(TAU * float(i) / 8.0)
	rig.setup({"theta": th, "radius": 0.18, "y0": 0.05, "length": 0.34, "base": 0.24, "max": 1.3})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var lv := Vector3(rng.randf_range(-30, 30), rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		var acc := Vector3(rng.randf_range(-40, 40), rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		var leg_l := Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var leg_r := Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var knee := Vector3(rng.randf_range(0, 2.5), 0, 0)
		rig.update(rng.randf_range(0.0, 0.05), lv, acc, leg_l, leg_r, knee, knee, float(i) * 0.1, rng.randf(), rng.randf_range(-20, 20))
		for k in rig.count:
			assert_true(rig.flare[k] >= rig.min_flare - 0.0001 and rig.flare[k] <= rig.max_flare + 0.0001, "flare bounded")
			assert_true(absf(rig.side[k]) <= rig.max_side + 0.0001, "side bounded")
			assert_false(is_nan(rig.flare[k]) or is_nan(rig.side[k]), "finite")
	# standing still with straight legs: every panel rests at its base flare
	rig.reset()
	for i in 120:
		rig.update(DT, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3(0.05, 0, 0), Vector3(0.05, 0, 0), 0.0, 0.0, 0.0)
	for k in rig.count:
		assert_almost(rig.flare[k], rig.base_flare, 0.02, "rest flare")
		assert_true(rig.required_flare(k) < rig.flare[k], "straight legs fit inside the skirt")


## Lowest world-space y of every vertex of a unit (in-tree meshes and parts kept aside by the joint bake).
func _unit_low(av: Node3D, unit: String) -> float:
	var low := INF
	var detached: Dictionary = av.get("_detached")
	for b in av.get("_unit_boxes").get(unit, []):
		var box := b as Node3D
		var list: Array = []
		var stack: Array = [box]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D:
				list.append(n)
		list.append_array(detached.get(box.get_instance_id(), []))
		for m in list:
			var mi := m as MeshInstance3D
			var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else box.global_transform * mi.transform
			for s in mi.mesh.get_surface_count():
				var v: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for k in range(0, v.size(), 2):
					low = minf(low, (xf * v[k]).y)
	return low


func test_hats_helms_and_tall_hair_respect_the_roll_head_hull() -> void:
	var cases: Array = []
	for hat in ["sun_hat", "mushroom_beret", "witch_hat", "flower_crown"]:
		cases.append([_with("hat", hat), "hat", hat])
	for hair in ["space_buns", "high_ponytail", "braided_crown", "bob"]:
		cases.append([_with("hair", hair), "hair", hair])
	for helm in ["padded_hood", "copperwood_hood", "ironwood_helm", "moonsteel_helm"]:
		cases.append([ItemDB.legacy_look(), "hat", helm])
	for c in cases:
		var av := _avatar(c[0])
		if String(c[2]).ends_with("_hood") or String(c[2]).ends_with("_helm"):
			av.call("apply_armor", true, {"head": c[2]})
		var hull: Array = av.get("_head_hull")
		if String(c[2]) != "bob":
			assert_true(hull.size() > 14, "%s adds silhouette points to the roll hull" % c[2])
		var worst := INF
		var worst_t := 0.0
		for i in 21:
			var t := float(i) / 20.0
			av.set("roll_t", t)
			_step(av, 2)
			var low := _unit_low(av, String(c[1]))
			if low < worst:
				worst = low
				worst_t = t
		# same tolerance as test_player_avatar's head hull test
		assert_true(worst > -0.06, "%s dips %.2f m into the ground at roll t=%.2f" % [c[2], worst, worst_t])
		av.set("roll_t", -1.0)
		_step(av, 3)
		var hc: Node3D = av.get("_head_c")
		assert_true(hc.global_position.y > 1.1 and hc.global_position.y < 1.45, "%s: head height unchanged %.2f" % [c[2], hc.global_position.y])
		av.free()


func test_hats_never_cover_the_face() -> void:
	# every hat / helm vertex stays above the brows or behind the face (the camera always sees her eyes)
	for hat in ["sun_hat", "mushroom_beret", "witch_hat", "flower_crown", "ironwood_helm", "padded_hood"]:
		var av: Node3D
		if hat.ends_with("_helm") or hat.ends_with("_hood"):
			av = _avatar(ItemDB.legacy_look())
			av.call("apply_armor", true, {"head": hat})
		else:
			av = _avatar(_with("hat", hat))
		var hc: Node3D = av.get("_head_c")
		var detached: Dictionary = av.get("_detached")
		var blocked := 0
		for b in av.get("_unit_boxes")["hat"]:
			var box := b as Node3D
			var list: Array = []
			var stack: Array = [box]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				stack.append_array(n.get_children())
				if n is MeshInstance3D:
					list.append(n)
			list.append_array(detached.get(box.get_instance_id(), []))
			for m in list:
				var mi := m as MeshInstance3D
				var xf: Transform3D = hc.global_transform.affine_inverse() * (mi.global_transform if mi.is_inside_tree() else box.global_transform * mi.transform)
				for s in mi.mesh.get_surface_count():
					for p in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
						var q: Vector3 = xf * (p as Vector3)
						# the eye / brow window of the face (|x| < 0.14, -0.08 < y < 0.075), in front of the skull surface
						var e := Vector3(q.x / 0.25, q.y / 0.235, q.z / 0.2375)
						if absf(q.x) < 0.14 and q.y > -0.08 and q.y < 0.075 and q.z > 0.12 and e.length() > 1.0:
							blocked += 1
		assert_eq(blocked, 0, hat + " keeps the eyes and brows visible")
		av.free()


func test_hair_springs_swing_and_settle() -> void:
	for hair in ["high_ponytail", "twin_braids", "long_waves", "half_up_ribbon", "side_braid"]:
		var av := _avatar(_with("hair", hair))
		var chains: Array = av.get("_chains")
		var hair_chains: Array = chains.filter(func(ch: Variant) -> bool: return String(ch["kind"]) == "braid")
		assert_false(hair_chains.is_empty(), hair + " has spring chains")
		_step(av, 20)
		av.set("speed", 7.0)
		var moved := 0.0
		for i in 60:
			_step(av, 1, Vector3(0, 0, 7.0))
			for ch in hair_chains:
				moved = maxf(moved, (ch["ang"] as Vector2).length())
		assert_true(moved > 0.1, "%s swings while running (%.2f)" % [hair, moved])
		av.set("speed", 0.0)
		_step(av, 240)
		for ch in hair_chains:
			assert_true((ch["ang"] as Vector2).length() < 0.12, "%s settles when she stops" % hair)
			var segs: Array = ch["segs"]
			for s in segs:
				assert_true((s as Node3D).rotation.length() < 4.0, "finite rotations")
		av.free()


func test_capes_never_swing_into_the_back() -> void:
	for back in ["leaf_cape", "little_cape", "moth_shawl"]:
		var av := _avatar(_with("back", back))
		var cape: Dictionary = {}
		for ch in av.get("_chains"):
			if String(ch["kind"]) == "cape":
				cape = ch
		assert_false(cape.is_empty(), back + " has a cape chain")
		assert_false((av.get("_patch") as Node3D).visible, back + " hides the explorer patch")
		var scarf_ends: Array = av.get("_scarf_ends")
		assert_eq(scarf_ends.size(), 2, "explorer jacket under the cape")
		for ends in scarf_ends:
			assert_false(((ends as Array)[0] as Node3D).is_visible_in_tree(), back + " covers the scarf ends (no tails cutting through the cape)")
		var root := (cape["segs"] as Array)[0] as Node3D
		var rest: Vector3 = (cape["rest"] as Array)[0]
		var lifted := 0.0
		var moves := [Vector3(0, 0, 7), Vector3(0, 0, -5), Vector3(4, 0, 0), Vector3.ZERO, Vector3(0, -9, 3)]
		for mv in moves:
			av.set("speed", (mv as Vector3).length())
			for i in 50:
				_step(av, 1, mv)
				assert_true(root.rotation.x <= rest.x + 0.021, "%s never folds into her back (%.3f)" % [back, root.rotation.x])
				lifted = maxf(lifted, rest.x - root.rotation.x)
		assert_true(lifted > 0.2, "%s lifts behind her when she runs (%.2f)" % [back, lifted])
		av.free()
	# the satchel keeps the belt lantern; other backs clip it to the belt
	var sat := _avatar(ItemDB.legacy_look())
	assert_eq(String((sat.get("_lantern_belt") as Node3D).get_parent().name), "Satchel")
	for ends in sat.get("_scarf_ends"):
		assert_true(((ends as Array)[0] as Node3D).is_visible_in_tree(), "no cape: the scarf ends flutter")
	# cape off again (only the back unit is rebuilt): patch and scarf ends come back
	var re := _avatar(_with("back", "little_cape"))
	assert_eq(re.call("apply_look", ItemDB.legacy_look()), ["back"])
	assert_true((re.get("_patch") as Node3D).visible)
	for ends2 in re.get("_scarf_ends"):
		assert_true(((ends2 as Array)[0] as Node3D).is_visible_in_tree(), "scarf ends shown again")
	var cape_av := _avatar(_with("back", "moth_shawl"))
	assert_eq(String((cape_av.get("_lantern_belt") as Node3D).get_parent().name), "BeltClip")
	cape_av.set("lantern_owned", true)
	_step(cape_av, 2)
	assert_true((cape_av.get("_lantern_belt") as Node3D).visible, "owned lantern hangs at the belt")


## Recipe (d) of docs/ch2/maps/player_avatar.md: a non-driven avatar in its own SubViewport world, built once
## from `appearance` set before add_child, animating on its own and ignoring GameState.
func test_preview_mode_in_a_subviewport_is_independent_of_game_state() -> void:
	fresh_state()
	var look := ItemDB.legacy_look()
	look["hair"] = "bob"
	look["lower"] = "moonflower_dress"
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.85, 2.6)
	vp.add_child(cam)
	var av: Node3D = AvatarScript.new()
	av.set("appearance", look)
	assert_eq(av.call("apply_look", look), [], "before add_child: stored, built once in _ready")
	pivot.add_child(av)
	add_child(vp)
	_nodes.append(vp)
	av.call("play_anim", "idle")
	await wait_frames(2)
	assert_true(cam.cull_mask & AvatarScript.AVATAR_LAYER != 0, "a default camera sees Krystal's layer")
	assert_true(av.get_viewport() == vp, "lives in the preview world")
	assert_false(bool(av.get("driven")), "non-driven preview")
	assert_eq(String(av.call("current_look")["hair"]), "bob")
	assert_eq(String(av.get("appearance")["hair"]), "bob")
	assert_not_null(av.get("_skirt"), "the dress sways in the preview")
	GameState.appearance["hair"] = "space_buns"
	Events.appearance_changed.emit()
	assert_eq(String(av.call("current_look")["hair"]), "bob", "GameState edits do not touch the preview")
	pivot.rotation.y += 1.2
	await wait_frames(2)
	var r: Array = av.call("apply_look", ItemDB.legacy_look())
	assert_true(r.has("hair") and r.has("lower"))
	av.set("show_armor", true)
	assert_true((av.get("_unit_boxes")["armor"] as Array).is_empty(), "nothing equipped: no armor")
	av.call("apply_armor", true, {"body": "moonsteel_mail"})
	assert_false((av.get("_unit_boxes")["armor"] as Array).is_empty(), "armor preview")
	av.call("play_anim", "wave")
	await wait_frames(3)
	assert_eq(av.call("current_action"), "wave")
	fresh_state()


## The procedural cloth panels (skirts, capes, aprons) are closed shells whose front faces agree with their
## normals under Godot's clockwise winding (checked against a BoxMesh), so both sides render and light right.
func test_cloth_panels_face_outward() -> void:
	const AKit := preload("res://src/player/avatar/avatar_kit.gd")
	var box := BoxMesh.new()
	var barr := box.surface_get_arrays(0)
	var bv: PackedVector3Array = barr[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = barr[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = barr[Mesh.ARRAY_INDEX]
	var ref := signf(((bv[bi[1]] - bv[bi[0]]).cross(bv[bi[2]] - bv[bi[0]])).dot(bn[bi[0]]))
	for params in [[0.16, 0.2, 0.3, 0.18, 0.25, 0.01, 0, 0.0], [0.32, 0.36, 0.2, 0.2, 0.22, 0.012, 0, 0.0], [0.13, 0.16, 0.2, 0.18, 0.23, 0.01, 2, 0.008]]:
		var mesh: ArrayMesh = AKit.panel_mesh(params[0], params[1], params[2], params[3], params[4], params[5], params[6], params[7])
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bad := 0
		var outward := 0
		for t in range(0, v.size(), 3):
			var g := (v[t + 1] - v[t]).cross(v[t + 2] - v[t])
			if g.length_squared() < 1e-12:
				continue
			if signf(g.dot(n[t])) != ref:
				bad += 1
			if n[t].z > 0.5:
				outward += 1
		assert_eq(bad, 0, "panel %s: winding matches the normals" % str(params))
		assert_true(outward > 10, "panel %s has an outer (+Z) surface" % str(params))
		var aabb := mesh.get_aabb()
		assert_almost(aabb.size.y, float(params[2]), 0.001, "panel length")
		assert_true(aabb.size.x >= float(params[1]) - 0.001, "hem width")


## The ghost-light wings flap faster with speed; the flap phase is integrated, so speeding up or stopping late in a
## session (large time) never makes them jump between frames.
func test_wings_flap_smoothly_when_the_speed_changes() -> void:
	var av := _avatar(_with("back", "ghostlight_wings"))
	var wing: Node3D = null
	for ch in av.get("_chains"):
		if String(ch["kind"]) == "wing":
			wing = (ch["segs"] as Array)[0]
	assert_not_null(wing, "wings animate")
	if wing == null:
		return
	av.set("_t", 3000.0)   # ~50 minutes of play
	_step(av, 30)
	var worst := 0.0
	var swing := 0.0
	for spd in [7.0, 0.0, 4.2, 0.0]:
		av.set("speed", spd)
		var prev := wing.rotation.y
		for i in 45:
			_step(av, 1, Vector3(0, 0, spd))
			worst = maxf(worst, absf(wing.rotation.y - prev))
			swing = maxf(swing, absf(wing.rotation.y - 0.55))
			prev = wing.rotation.y
	assert_true(worst < 0.05, "no flap jumps between frames (%.3f rad)" % worst)
	assert_true(swing > 0.1, "the wings do flap (%.2f rad)" % swing)
