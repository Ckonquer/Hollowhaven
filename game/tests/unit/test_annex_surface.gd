extends "res://tests/test_case.gd"
## Tobin's side door and the hatch top on the surface (src/world/surface/c1x/tobin_door.gd, spec §7.1):
## built through the Annexes hook, beside the legacy mine mouth without touching it: the mine entrance,
## its rubble, mine_exit / mine_threshold, the zones and the vegetation plan stay exactly as they were. The
## door stands between the legacy cliff-foot boulders with a clear approach; the hatch sits on flat, dry,
## clear apron ground; both spawns stand on clear ground (not the Annexes fallback transforms).

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")
const TobinDoor := preload("res://src/world/surface/c1x/tobin_door.gd")
const MASK := 1 | 32

var _surface: Node3D = null


func _world() -> Node3D:
	if _surface == null or not is_instance_valid(_surface):
		fresh_state()
		_surface = SurfaceWorld.new()
		add_child(_surface)
		await wait_physics(3)
	return _surface


func _by_script(w: Node, path: String) -> Array:
	var out: Array = []
	for n in w.find_children("*", "Node3D", true, false):
		var s: Variant = n.get_script()
		if s is Script and (s as Script).resource_path == path:
			out.append(n)
	return out


func _shape_hits(w: Node3D, shape: Shape3D, xf: Transform3D, mask: int = MASK) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = mask
	var hits := w.get_world_3d().direct_space_state.intersect_shape(q, 8)
	return hits.map(func(h: Dictionary) -> String: return String((h["collider"] as Node).get_path()))


func test_sites_follow_the_mine_frame() -> void:
	var o := TobinDoor.mine_origin()
	var f := SL.MINE_FACING.normalized()
	assert_almost(o.distance_to(SL.MINE_MOUTH + f * 0.4), 0.0, 0.0001, "the mine entrance frame origin (landmarks.gd)")
	var d := TobinDoor.door_site()
	var h := TobinDoor.hatch_site()
	assert_true(d.distance_to(o) >= 6.0 and d.distance_to(o) <= 9.0, "the side door is a few metres beside the mouth (%.1f m)" % d.distance_to(o))
	assert_true(h.distance_to(o) >= 6.0 and h.distance_to(o) <= 10.0, "the hatch is near the mouth (%.1f m)" % h.distance_to(o))
	assert_true((d - o).dot(f) > 0.0 and (h - o).dot(f) > 0.0, "both on the apron side of the cliff")
	var c: Array = TobinDoor.grass_clearings()
	assert_eq(c.size(), 2, "two grass clearings")
	assert_true(c[0][0] is Vector2 and float(c[0][1]) > 0.0, "[centre, radius] pairs")
	assert_true(_annexes_has_slot(), "annexes.gd runs this script")


func _annexes_has_slot() -> bool:
	return (load("res://src/world/surface/annexes.gd") as Script).get_script_constant_map()["ANNEX_SCRIPTS"].has("res://src/world/surface/c1x/tobin_door.gd")


func test_surface_pieces_are_cheap_to_build() -> void:
	var host: Node3D = load("res://src/world/area_base.gd").new()
	add_child(host)
	var t0 := Time.get_ticks_usec()
	TobinDoor.build(host)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("    tobin_door.build: %.1f ms" % ms)
	assert_true(ms < 150.0, "door + hatch build quickly (%.1f ms)" % ms)
	assert_true((host.spawns as Dictionary).has("annex_door") and (host.spawns as Dictionary).has("annex_hatch"), "both spawns registered")
	var lights := host.find_children("*", "Light3D", true, false)
	assert_eq(lights.size(), 1, "one small unshadowed lamp by the door")
	for l in lights:
		assert_false((l as Light3D).shadow_enabled, "no extra shadowed light on the surface")
	host.queue_free()
	await wait_frames(2)


func test_door_hatch_and_spawns_on_the_surface() -> void:
	var w: Node3D = await _world()
	var doors := _by_script(w, "res://src/world/annex/annex_door.gd")
	var hatches := _by_script(w, "res://src/world/annex/annex_hatch.gd")
	assert_eq(doors.size(), 1, "one side door")
	assert_eq(hatches.size(), 1, "one hatch top")
	if doors.is_empty() or hatches.is_empty():
		return
	var door: Node3D = doors[0]
	var hatch: Node3D = hatches[0]
	var ds := TobinDoor.door_site()
	var hs := TobinDoor.hatch_site()
	assert_almost(Vector2(door.global_position.x, door.global_position.z).distance_to(ds), 0.0, 0.01, "door at its site")
	assert_almost(Vector2(hatch.global_position.x, hatch.global_position.z).distance_to(hs), 0.0, 0.01, "hatch at its site")
	assert_almost(door.global_position.y, float(w.height_at(ds.x, ds.y)), 0.1, "door on the ground")
	assert_almost(hatch.global_position.y, float(w.height_at(hs.x, hs.y)), 0.05, "hatch flush with the ground")
	assert_eq(String(door.get("target_area")), "tobin_annex")
	assert_eq(String(door.get("target_spawn")), "annex_entry")
	assert_eq(String(door.get("requires_flag")), "mine_opened")
	assert_eq(String(hatch.get("target_area")), "tobin_annex")
	assert_eq(String(hatch.get("target_spawn")), "annex_hatch_below")
	assert_false(bool(door.get_interaction(null)["enabled"]), "jammed on a new game (mine not opened)")
	assert_false(bool(hatch.get_interaction(null)["enabled"]), "bolted on a new game")
	# The spawns are ours (not the Annexes fallback = the legacy mine-mouth spawns) and stand on clear ground.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	for id in ["annex_door", "annex_hatch"]:
		assert_true((w.spawns as Dictionary).has(id), "%s registered" % id)
		var xf: Transform3D = w.spawns[id]
		assert_ne(xf, w.spawns["mine_exit"], "%s is not the fallback" % id)
		assert_ne(xf, w.spawns["mine_threshold"], "%s is not the fallback" % id)
		var p := xf.origin
		assert_almost(p.y, float(w.height_at(p.x, p.z)) + 0.08, 0.05, "%s on the ground" % id)
		assert_eq(_shape_hits(w, cap, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0))), [], "%s is clear" % id)
		assert_true(w.validate_position(p) is Vector3, "%s is a valid saved position" % id)
		assert_true(w.is_inside_bounds(p, 3.0), "%s inside the world" % id)
		assert_false(w.terrain.is_water(p.x, p.z), "%s is dry" % id)
		assert_eq(w.get_zone_at(p), "mine_mouth", "%s adds no zone (the mine mouth's music and bond xp)" % id)
		var fwd := -xf.basis.z
		assert_true(fwd.dot(Vector3(SL.MINE_FACING.normalized().x, 0, SL.MINE_FACING.normalized().y)) > 0.95, "%s faces out onto the apron" % id)
	# Clear approach: capsules from the door's spawn up to the door front, and around the hatch.
	var sp: Vector3 = (w.spawns["annex_door"] as Transform3D).origin
	for k in 5:
		var t := float(k) / 4.0
		var p := sp.lerp(door.global_position + (sp - door.global_position).normalized() * 0.6, t)
		p.y = float(w.height_at(p.x, p.z))
		assert_eq(_shape_hits(w, cap, Transform3D(Basis.IDENTITY, p + Vector3(0, 1.05, 0))), [], "the way to the door is clear (%d)" % k)
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.5, 1.9)
	var hp := hatch.global_position
	assert_eq(_shape_hits(w, box, Transform3D(Basis(Vector3.UP, hatch.rotation.y), hp + Vector3(0, 0.45, 0))), [], "nothing legacy stands on the hatch")
	var slope := 0.0
	for a in 8:
		var q := Vector2(hp.x, hp.z) + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * 1.0
		slope = maxf(slope, absf(float(w.height_at(q.x, q.y)) - hp.y))
	assert_true(slope < 0.15, "the hatch lies on flat ground (%.2f m)" % slope)


## Arriving at either spawn, the way back is right there: the player's own interaction probe (reach, facing,
## line of sight) focuses the side door from annex_door and the hatch from annex_hatch.
func test_door_and_hatch_are_usable_from_their_spawns() -> void:
	var w: Node3D = await _world()
	var doors := _by_script(w, "res://src/world/annex/annex_door.gd")
	var hatches := _by_script(w, "res://src/world/annex/annex_hatch.gd")
	if doors.is_empty() or hatches.is_empty():
		fail("door / hatch missing")
		return
	# (Flags untouched: this world is shared by the suite; a locked door / bolted hatch still takes the focus
	# and explains itself, see test_annex_flow for the unlocked prompts.)
	var stand := Node3D.new()
	w.add_child(stand)
	var probe: Node = (load("res://src/player/interaction_probe.gd") as Script).new()
	probe.set("player", stand)
	w.add_child(probe)
	await wait_physics(1)
	for c in [["annex_door", doors[0]], ["annex_hatch", hatches[0]]]:
		var target: Node3D = c[1]
		var p: Vector3 = (w.spawns[c[0]] as Transform3D).origin
		var to := target.global_position - p
		stand.global_transform = Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), p)
		probe.call("refresh")
		var focus: Variant = probe.get("focus")
		assert_true(focus == target, "%s: the way back is focused (got %s)" % [c[0], str(focus.name) if focus is Node else "nothing"])
		var info: Dictionary = probe.get("focus_interaction")
		assert_true(String(info.get("text", "")) != "", "%s: a prompt is shown" % c[0])
	probe.queue_free()
	stand.queue_free()


func test_legacy_mine_mouth_untouched() -> void:
	var w: Node3D = await _world()
	var me: Node3D = w.landmarks.mine_entrance
	var f := SL.MINE_FACING.normalized()
	var p := SL.MINE_MOUTH + f * 0.4
	assert_almost(Vector2(me.global_position.x, me.global_position.z).distance_to(p), 0.0, 0.001, "mine entrance in place")
	assert_almost(me.rotation.y, atan2(f.x, f.y), 0.0001, "mine entrance facing")
	assert_eq(String(me.rubble.get("node_id")), "mine_rubble", "the legacy rubble node")
	for id in ["mine_exit", "mine_threshold"]:
		var h: Vector2 = Layout.SPAWN_HINTS[id]
		var o: Vector3 = (w.spawns[id] as Transform3D).origin
		assert_almost(Vector2(o.x, o.z).distance_to(h), 0.0, 0.001, "%s unmoved" % id)
	var mp: Vector2 = Layout.LANDMARKS["mine_mouth"]["pos"]
	assert_eq(w.get_zone_at(Vector3(mp.x, 0, mp.y)), "mine_mouth", "mine mouth zone unchanged")
	# The side door and hatch keep clear of the mine entrance frame, its cart and its lantern posts.
	var ds := TobinDoor.door_site()
	var hs := TobinDoor.hatch_site()
	assert_true(Vector2(me.global_position.x, me.global_position.z).distance_to(ds) > 5.5, "door clear of the mine frame")
	assert_true(Vector2(me.global_position.x, me.global_position.z).distance_to(hs) > 5.5, "hatch clear of the mine frame")
	# The walk from mine_exit into the mine mouth stays clear.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	var a: Vector3 = (w.spawns["mine_exit"] as Transform3D).origin
	var b := me.global_position + me.global_transform.basis.z * 3.2      # just short of the (legacy) rubble seal
	for k in 9:
		var q := a.lerp(b, float(k) / 8.0)
		q.y = float(w.height_at(q.x, q.z))
		assert_eq(_shape_hits(w, cap, Transform3D(Basis.IDENTITY, q + Vector3(0, 1.0, 0))), [], "the path to the mine mouth is clear (%d)" % k)


func test_no_legacy_vegetation_under_the_new_pieces() -> void:
	var w: Node3D = await _world()
	var plan: Dictionary = w.vegetation.plan_data
	var ds := TobinDoor.door_site()
	var hs := TobinDoor.hatch_site()
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		for e in plan[k]:
			var p: Vector3 = e["pos"]
			assert_true(Vector2(p.x, p.z).distance_to(ds) > 3.0, "%s %s is clear of the side door" % [k, e["id"]])
			assert_true(Vector2(p.x, p.z).distance_to(hs) > 2.5, "%s %s is clear of the hatch" % [k, e["id"]])
	for k in ["decor_trees", "decor_bushes", "mushrooms", "logs", "brambles"]:
		for e in plan[k]:
			for v in e:
				if v is Transform3D:
					var o: Vector3 = (v as Transform3D).origin
					assert_true(Vector2(o.x, o.z).distance_to(ds) > 2.5 and Vector2(o.x, o.z).distance_to(hs) > 2.0, "%s at %s is clear" % [k, str(o)])
	# The big cliff-foot boulders are part of the look: they may flank the adit, never block its front.
	for e in plan["decor_rocks"]:
		var xf: Transform3D = e[1]
		var r := 1.35 * xf.basis.get_scale().x
		var o := Vector2(xf.origin.x, xf.origin.z)
		assert_true(o.distance_to(hs) > r + 0.9, "decor rock at %s is clear of the hatch" % str(o))
