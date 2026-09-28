extends "res://tests/unit/test_core_base.gd"
## Story module C9 world pieces, tested numerically (no screenshots):
##   * Reach dressing: nothing before its time; stage-by-stage road lanterns that stay on open road (outside
##     every landmark circle, off the spawns, above head height, inside the region), deterministic, idempotent,
##     fast; the Commons festival lantern appears after the Choir, stands on the floor, dodges a blocker, leaves
##     room around itself for Krystal's capsule and is reachable from open ground
##   * Haven keepsake: only after the ending, inside the Ward Stone's blocked circle, no colliders
##   * Celebration: every festival light outside every build circle (incl. extra regions) and the outpost; no
##     colliders, nothing inside the build area; the camera viewpoint is validated against player-built
##     geometry (blocked -> the next one, walled in / roofed -> the player's own camera); play / skip / finish

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const ReachDressing := preload("res://src/world/story_ch2/reach_dressing.gd")
const HavenDressing := preload("res://src/world/story_ch2/haven_dressing.gd")
const Celebration := preload("res://src/world/story_ch2/celebration.gd")
const Pole := preload("res://src/world/story_ch2/lanternwake_pole.gd")
const FestivalLights := preload("res://src/world/story_ch2/festival_lights.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Layout := preload("res://data/world_layout.gd")

const FAR := Vector3(6000, 0, 6000)      # test worlds are staged far from anything else in the physics world
const CAPSULE_R := 0.35
const CAPSULE_H := 1.8


class FlatArea extends Node3D:
	var ground_y := 0.0

	func height_at(_x: float, _z: float) -> float:
		return ground_y


var area: FlatArea = null


func setup() -> void:
	fresh_state()
	GameState.active = true
	area = FlatArea.new()
	add_child(area)


func teardown() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(1)


func _flat(_x: float, _z: float) -> float:
	return 0.0


## A solid box (layer `layer`) in the test area.
func _box(center: Vector3, size: Vector3, layer: int = 32) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	area.add_child(b)
	b.global_position = center
	return b


func _colliders(n: Node) -> int:
	var c := 1 if n is CollisionObject3D else 0
	for ch in n.get_children():
		c += _colliders(ch)
	return c


## Instance count of every MultiMesh named `mm_name` under `root` (road lanterns are split into cells; headless
## rendering keeps no instance transforms, so positions are checked through the builders' pure point lists).
func _lantern_count(root: Node, mm_name: String) -> int:
	var n := 0
	for mmi in root.find_children(mm_name, "MultiMeshInstance3D", true, false):
		n += (mmi as MultiMeshInstance3D).multimesh.instance_count
	return n


# --- Reach dressing ------------------------------------------------------------------------------------------

func test_reach_dressing_stages() -> void:
	for f in ["", Story.SAFE_ROUTES_FLAG]:
		if f != "":
			GameState.set_flag(f)
		var r0: Node3D = ReachDressing.build(area)
		assert_not_null(r0)
		assert_eq(r0.get_child_count(), 0, "nothing before the Choir (%s; the region's own road lights cover the linked lamps)" % f)
		area.remove_child(r0)
		r0.free()
	var counts: Array = []
	for f in [Story.CHOIR_FLAG, Story.COMPLETE_FLAG]:
		GameState.set_flag(f)
		var root := ReachDressing.build(area)
		var pts := ReachDressing.route_points(ReachDressing.stage(), _flat)
		counts.append(pts.size())
		assert_eq(_lantern_count(root.get_node("RouteLanterns"), "Bodies"), pts.size(), "%s: one lantern per road point" % f)
		var pole: Node3D = root.get_node_or_null(ReachDressing.POLE_NAME)
		assert_not_null(pole, "the Commons festival lantern after the Choir")
		if pole != null:
			assert_eq(pole.is_in_group("light_source"), f == Story.COMPLETE_FLAG, "a lasting safe light only after the Lanternwake")
		area.remove_child(root)
		root.free()
	assert_true(int(counts[0]) >= 20, "festival lanterns on every road (%d)" % int(counts[0]))
	assert_eq(counts[1], counts[0], "the same roads after the Lanternwake")


func test_road_lanterns_stay_on_open_road() -> void:
	var pts := ReachDressing.route_points(2, _flat)
	assert_true(pts.size() >= 20, "enough lanterns (%d)" % pts.size())
	var roads := ReachDressing.roads()
	var clear := ReachDressing.keep_clear()
	for p in pts:
		var pos: Vector3 = p["pos"]
		var p2 := Vector2(pos.x, pos.z)
		assert_true(Reach.is_inside(p2, 5.0), "inside the region %s" % p2)
		assert_true(pos.y >= 4.3, "floating above head height, arches and road posts (never blocks a path) %s" % pos)
		var best := INF
		for road in roads:
			for i in range((road as Array).size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(p2, road[i], road[i + 1])
				best = minf(best, q.distance_to(p2))
		assert_true(best < 0.05, "over a road centreline %s (%.2f m)" % [p2, best])
		for c in clear:
			assert_true(p2.distance_to(c[0]) >= float(c[1]) - 0.01, "%s clear of %s" % [p2, c[0]])
		for id in Reach.LANDMARKS:
			var l: Dictionary = Reach.LANDMARKS[id]
			assert_true(p2.distance_to(l["pos"]) >= float(l["radius"]), "%s outside %s" % [p2, id])
		for sid in Reach.SPAWNS:
			assert_true(p2.distance_to(Reach.SPAWNS[sid]["pos"]) >= ReachDressing.SPAWN_CLEARANCE - 0.01, "%s clear of spawn %s" % [p2, sid])
		assert_true(p2.distance_to(Reach.OUTPOST_BUILD_AREA["center"]) > float(Reach.OUTPOST_BUILD_AREA["radius"]), "never over the outpost build area")
	# Deterministic: same flags, same lanterns.
	assert_eq(ReachDressing.route_points(2, _flat), pts)
	assert_eq(ReachDressing.route_points(3, _flat), pts, "stage 3 keeps the same roads")


func test_reach_dressing_is_idempotent_fast_and_collider_light() -> void:
	GameState.set_flag(Story.CHOIR_FLAG)
	var t0 := Time.get_ticks_usec()
	var root: Node3D = ReachDressing.build(area)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	assert_true(ms < 150.0, "builds behind the load fade in %.1f ms (budget: well under 1.5 s)" % ms)
	assert_eq(ReachDressing.build(area), root, "idempotent")
	assert_eq(String(root.name), ReachDressing.NODE_NAME)
	var route: Node3D = root.get_node_or_null("RouteLanterns")
	assert_not_null(route, "stable node path")
	# One MultiMesh pair per cell, each with its own visibility range: the range is measured to each MultiMesh's
	# own bounds, so a single region-wide MultiMesh would hide every road lantern at once far from the middle.
	var pts := ReachDressing.route_points(2, _flat)
	var cells := route.get_children()
	assert_true(cells.size() >= 4, "road lanterns are split into cells (%d)" % cells.size())
	assert_eq(_lantern_count(route, "Bodies"), pts.size(), "every lantern in exactly one cell")
	assert_eq(_lantern_count(route, "Caps"), pts.size())
	var names: Array = []
	for c in cells:
		names.append(String(c.name))
		for mm_name in ["Bodies", "Caps"]:
			var mmi := (c as Node).get_node_or_null(mm_name) as MultiMeshInstance3D
			assert_not_null(mmi, "%s/%s" % [c.name, mm_name])
			if mmi == null:
				continue
			assert_almost(mmi.visibility_range_end, ReachDressing.VIS_RANGE, 0.001, "%s/%s culls by distance" % [c.name, mm_name])
	# Each cell holds exactly the lanterns inside its own CELL x CELL square (so its bounds stay local).
	var per_cell := {}
	for p in pts:
		var pos: Vector3 = p["pos"]
		var key := "Cell_%d_%d" % [floori(pos.x / ReachDressing.CELL), floori(pos.z / ReachDressing.CELL)]
		per_cell[key] = int(per_cell.get(key, 0)) + 1
	assert_eq(per_cell.size(), cells.size(), "one node per occupied cell")
	for c in cells:
		assert_eq(_lantern_count(c, "Bodies"), int(per_cell.get(String(c.name), -1)), "%s holds only its own square" % c.name)
	var root2 := Node3D.new()
	add_child(root2)
	var again: Node3D = FestivalLights.lanterns_chunked(pts, "RouteLanterns", ReachDressing.VIS_RANGE, ReachDressing.CELL)
	root2.add_child(again)
	assert_eq(again.get_children().map(func(n: Node) -> String: return String(n.name)), names, "deterministic cells")
	root2.queue_free()
	# Only the festival lantern has colliders: its thin pole + the interaction sphere (no region pole here).
	assert_eq(_colliders(root), 2)
	var shadowed := 0
	for l in root.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled:
			shadowed += 1
	assert_eq(shadowed, 0, "no shadowed lights")
	assert_eq(Story.ensure_dressing(area, "hallowmere_reach"), root, "the tracker never builds it twice")


func test_pole_candidates_are_sensible() -> void:
	var commons: Dictionary = Reach.LANDMARKS["hr_commons"]
	var arches: Array = []
	for id in Reach.ARCHES:
		arches.append(Reach.ARCHES[id]["pos"])
	for c in ReachDressing.pole_candidates():
		var p: Vector2 = c
		assert_true(p.distance_to(commons["pos"]) < float(commons["radius"]) - 1.0, "%s in the Commons" % p)
		assert_true(absf(p.x) >= 5.0, "%s off the main north-south road" % p)
		assert_true(p.distance_to(Reach.OUTPOST_BUILD_AREA["center"]) >= float(Reach.OUTPOST_BUILD_AREA["radius"]) + 3.0, "%s clear of the outpost" % p)
		for sid in Reach.SPAWNS:
			assert_true(p.distance_to(Reach.SPAWNS[sid]["pos"]) >= 4.0, "%s clear of spawn %s" % [p, sid])
		for a in arches:
			assert_true(p.distance_to(a) >= 4.0, "%s clear of an arch" % p)


func test_pole_stands_on_the_floor_dodges_blockers_and_is_reachable() -> void:
	area.position = FAR
	var floor_body := _box(FAR + Vector3(0, -0.5, 60), Vector3(80, 1.0, 80), 1)
	assert_not_null(floor_body)
	var cands: Array = [Vector2(FAR.x + 9, FAR.z + 54), Vector2(FAR.x - 7, FAR.z + 44)]
	_box(Vector3(cands[0].x, 1.2, cands[0].y), Vector3(2.5, 2.4, 2.5), 32)      # a stall where the first spot is
	var pole: Node3D = Pole.new()
	pole.setup({"candidates": cands, "stage": 2})
	area.add_child(pole)
	pole.global_position = Vector3(cands[0].x, 0.0, cands[0].y)
	for i in 6:
		await wait_physics(1)
		if bool(pole.get("placed")):
			break
	assert_true(bool(pole.get("placed")), "placement ran")
	var gp := pole.global_position
	assert_almost(gp.x, float(cands[1].x), 0.01, "moved off the blocked spot")
	assert_almost(gp.y, 0.0, 0.05, "stands on the floor")
	# Krystal can stand beside it (capsule clear) and reach the interaction sphere from there.
	var space := pole.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_R
	cap.height = CAPSULE_H
	var free_sides := 0
	for d: Vector3 in [Vector3(1.3, 0, 0), Vector3(-1.3, 0, 0), Vector3(0, 0, 1.3), Vector3(0, 0, -1.3)]:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, gp + d + Vector3(0, CAPSULE_H * 0.5 + 0.05, 0))
		q.collision_mask = 1 | 32
		if space.intersect_shape(q, 1).is_empty():
			free_sides += 1
			var eye := gp + d + Vector3(0, 1.5, 0)
			var target := gp + Vector3(0, 1.2, 0)
			assert_true(eye.distance_to(target) < 2.4, "the interaction sphere is within reach")
			var ray := PhysicsRayQueryParameters3D.create(eye, target, 16)
			ray.hit_from_inside = true      # like the interaction probe: standing right at the sphere's edge counts
			var hit := space.intersect_ray(ray)
			assert_false(hit.is_empty(), "the interaction collider answers the probe")
	assert_eq(free_sides, 4, "room on every side")
	# Floors collide: a ray down beside it meets the ground, not the void.
	var down := PhysicsRayQueryParameters3D.create(gp + Vector3(2, 5, 0), gp + Vector3(2, -5, 0), 1)
	assert_false(space.intersect_ray(down).is_empty(), "no fall-through")


func test_pole_attaches_to_the_commons_pole() -> void:
	GameState.set_flag(Story.CHOIR_FLAG)
	var cp := ReachDressing.commons_pole()
	# Without a region pole (the placeholder region): a stand-alone festival pole, first at the layout's spot.
	var root: Node3D = ReachDressing.build(area)
	var pole: Node3D = root.get_node_or_null(ReachDressing.POLE_NAME)
	assert_not_null(pole)
	assert_false(bool(pole.get("attach")), "stand-alone without a region pole")
	assert_not_null(pole.get("body"), "its own thin solid pole")
	if cp != Vector2.INF:
		assert_eq((pole.get("candidates") as Array)[0], cp, "the layout's pole spot first")
	area.remove_child(root)
	root.free()
	if cp == Vector2.INF:
		return
	# With the region's own pole (src/world/reach/commons.gd builds "LanternPole"): attach, never a second pole.
	var region := Node3D.new()
	region.name = "LanternPole"
	area.add_child(region)
	region.global_position = Vector3(cp.x, 0.0, cp.y)
	root = ReachDressing.build(area)
	pole = root.get_node_or_null(ReachDressing.POLE_NAME)
	assert_true(bool(pole.get("attach")), "attached to the region pole")
	assert_almost(pole.global_position.x, cp.x, 0.001)
	assert_almost(pole.global_position.z, cp.y, 0.001)
	assert_null(pole.get("body"), "no extra collider: the region pole is already solid")
	assert_null(pole.find_child("Crown", true, false), "no second crown")
	var ib: StaticBody3D = pole.get("interact_body")
	assert_eq(ib.collision_layer, 16)
	var sph: SphereShape3D = (ib.get_child(0) as CollisionShape3D).shape
	assert_true(sph.radius >= 1.4, "reachable from beside the pole (the region pole collider is 0.26 m)")
	assert_true(bool(pole.get("placed")))


func test_pole_states_and_light() -> void:
	var pole: Node3D = Pole.new()
	pole.setup({"candidates": [], "stage": 3})
	area.add_child(pole)
	assert_true(pole.is_in_group("light_source"), "a lasting safe light after the Lanternwake")
	assert_true(pole.is_light_active() and float(pole.get("light_radius")) >= 8.0)
	assert_true(pole.is_in_group("interactable"))
	Settings.set_value("high_visibility_cues", true)
	GameState.set_flag(Story.HOMECOMING_FLAG)
	pole.call("_update_marker")
	assert_true((pole.get("marker") as Node3D).visible, "bold marker while celebrating is possible")
	GameState.set_flag(Story.COMPLETE_FLAG)
	pole.call("_update_marker")
	assert_false((pole.get("marker") as Node3D).visible)
	Settings.set_value("high_visibility_cues", false)


# --- Haven keepsake ---------------------------------------------------------------------------------------------

func test_haven_keepsake_only_after_the_ending_and_inside_the_stone_circle() -> void:
	assert_null(HavenDressing.build(area), "nothing before Chapter Two is complete")
	GameState.set_flag(Story.COMPLETE_FLAG)
	var node: Node3D = HavenDressing.build(area)
	assert_not_null(node)
	assert_eq(HavenDressing.build(area), node, "idempotent")
	assert_eq(_colliders(node), 0, "nothing solid")
	var c := HavenDressing.stone_center_2d()
	var r := HavenDressing.stone_blocked_radius()
	assert_eq(_lantern_count(node, "Bodies"), HavenDressing.COUNT)
	var pts: Array = node.world_points()
	assert_eq(pts.size(), HavenDressing.COUNT)
	await wait_frames(3)     # it drifts; still inside
	pts = node.world_points()
	pts.append_array(HavenDressing.lantern_points().map(func(p: Dictionary) -> Vector3:
		return node.global_transform * (p["pos"] as Vector3) + Vector3(0, -HavenDressing.BOB, 0)))
	for p in pts:
		var pos: Vector3 = p
		assert_true(Vector2(pos.x, pos.z).distance_to(c) <= r - 0.5, "inside the Ward Stone's blocked circle (never buildable)")
		assert_true(Vector2(pos.x, pos.z).distance_to(c) >= 1.2, "clear of the monolith")
		assert_true(pos.y >= 2.5, "above the ring stones")
	# The blocked circle really is excluded from building.
	var found := false
	for b in Layout.BUILD_AREA["blocked"]:
		if String((b as Dictionary).get("name", "")) == "Ward Stone":
			found = true
	assert_true(found)


func test_dressings_fit_the_area_hook_contracts() -> void:
	# The surface annex loader (src/world/surface/annexes.gd) checks has_method("build") on the script and calls it
	# statically; the Reach region's requested call line does the same with reach_dressing.gd.
	for path in [Story.HAVEN_DRESSING, Story.REACH_DRESSING]:
		var sc: Script = load(path)
		assert_true(sc != null and sc.can_instantiate(), path)
		assert_true(sc.has_method("build"), path + " exposes build()")
	GameState.set_flag(Story.COMPLETE_FLAG)
	var node: Variant = (load(Story.HAVEN_DRESSING) as Script).call("build", area)
	assert_true(node is Node3D and (node as Node3D).get_parent() == area, "static build through the Script")
	var t0 := Time.get_ticks_usec()
	for i in 20:
		HavenDressing.lantern_points()
	assert_true(Time.get_ticks_usec() - t0 < 20000, "cheap")


# --- Celebration ---------------------------------------------------------------------------------------------------

func test_festival_lights_stay_outside_every_build_circle() -> void:
	var ring := Celebration.haven_ring(_flat)
	assert_true(ring.size() >= Celebration.RING_COUNT - 3, "a (nearly) full ring around the Haven and its extra lawns (%d)" % ring.size())
	var circles := Celebration.build_circles()
	for p in ring:
		var pos: Vector3 = p["pos"]
		assert_true(Celebration.outside_build(Vector2(pos.x, pos.z), Celebration.OUTSIDE_MARGIN - 0.01, circles), "outside the build area %s" % pos)
		assert_true(pos.y > 2.5, "floating")
	# With the Haven expansion's extra regions the ring steps around them.
	var extra := circles.duplicate()
	extra.append([Vector2(19, 0), 6.0])
	extra.append([Vector2(-12, 16), 5.0])
	var ring2 := Celebration.haven_ring(_flat, extra)
	assert_true(ring2.size() >= Celebration.RING_COUNT - 6, "still most of a ring (%d)" % ring2.size())
	for p in ring2:
		var pos2: Vector3 = p["pos"]
		assert_true(Celebration.outside_build(Vector2(pos2.x, pos2.z), Celebration.OUTSIDE_MARGIN - 0.01, extra), "outside the extra regions %s" % pos2)
	var cring := Celebration.commons_ring(Vector2(-9, 54), _flat)
	for p in cring:
		var pos3: Vector3 = p["pos"]
		assert_true(Vector2(pos3.x, pos3.z).distance_to(Reach.OUTPOST_BUILD_AREA["center"]) >= float(Reach.OUTPOST_BUILD_AREA["radius"]) + 1.49, "never over the outpost")
	assert_true(cring.size() < Celebration.COMMONS_RING_COUNT, "points over the outpost were dropped")


func test_camera_viewpoints_are_validated_against_her_buildings() -> void:
	area.position = FAR
	var focus := FAR + Vector3(0, 0, -6)
	var cands := Celebration.candidate_shots("haven", focus, Vector3.BACK)
	assert_true(cands.size() >= 5)
	for c in cands:
		assert_true(((c as Dictionary)["pos"] as Vector3).y >= focus.y + 3.5, "above head height")
	await wait_physics(2)
	var space := area.get_world_3d().direct_space_state
	var ground := func(_x: float, _z: float) -> float: return FAR.y
	var first: Dictionary = Celebration.pick_shot(space, cands, ground)
	assert_eq(first["pos"], cands[0]["pos"], "open world: the first viewpoint")
	# Her house wall right in front of the first viewpoint -> the next clear one.
	var p0: Vector3 = cands[0]["pos"]
	var look: Vector3 = cands[0]["look"]
	_box(p0.lerp(look, 0.4), Vector3(3, 3, 3), 32)
	await wait_physics(2)
	var second: Dictionary = Celebration.pick_shot(space, cands, ground)
	assert_false(second.is_empty())
	assert_ne(second["pos"], p0, "a viewpoint behind a wall is refused")
	assert_true(Celebration.shot_is_clear(space, second["pos"], second["look"], FAR.y))
	# A roof over a viewpoint (a lens inside a room) is refused even with a clear line of sight.
	var p1: Vector3 = cands[1]["pos"]
	_box(p1 + Vector3(0, 3.0, 0), Vector3(3, 0.3, 3), 32)
	await wait_physics(2)
	assert_false(Celebration.shot_is_clear(space, p1, cands[1]["look"], FAR.y), "under one of her roofs")
	assert_false(Celebration.shot_is_clear(space, Vector3(p1.x, FAR.y + 0.5, p1.z), cands[1]["look"], FAR.y), "too close to the ground")
	# Everything walled in -> no shot: the caller keeps the player's own camera (the simple safe shot).
	_box(focus + Vector3(0, 8, 0), Vector3(60, 20, 60), 32)
	await wait_physics(2)
	assert_eq(Celebration.pick_shot(space, cands, ground), {}, "fallback")


func test_celebration_plays_skips_and_cleans_up() -> void:
	area.position = FAR
	var cam := Camera3D.new()
	area.add_child(cam)
	cam.make_current()
	var cel: Node3D = Celebration.new()
	cel.setup({"area": area, "area_id": "surface", "duration": 30.0})
	area.add_child(cel)
	assert_eq(String(cel.get("venue")), "haven")
	assert_eq(_colliders(cel), 0, "no tables, no guests, nothing solid")
	var lights := cel.find_children("*", "Light3D", true, false)
	assert_true(lights.size() <= 2)
	for l in lights:
		assert_false((l as Light3D).shadow_enabled)
	# Skip after a moment.
	var state := {"done": false}
	var runner := func() -> void:
		await cel.play()
		state["done"] = true
	runner.call()
	await wait_frames(2)
	assert_false(bool(state["done"]), "playing")
	cel.call("skip")
	await wait_frames(1)
	assert_true(bool(state["done"]), "skippable")
	assert_true(bool(cel.get("skipped")))
	cel.call("finish")
	await wait_frames(2)
	assert_false(is_instance_valid(cel), "removed")
	assert_eq(area.get_viewport().get_camera_3d(), cam, "camera restored")
	# A short run ends by itself; a celebration freed mid-play never leaves its caller waiting.
	var cel2: Node3D = Celebration.new()
	cel2.setup({"area": area, "area_id": "hallowmere_reach", "duration": 0.15})
	area.add_child(cel2)
	assert_eq(String(cel2.get("venue")), "commons")
	var st2 := {"done": false}
	var r2 := func() -> void:
		await cel2.play()
		st2["done"] = true
	r2.call()
	await wait_seconds(0.4)
	assert_true(bool(st2["done"]), "ends by itself")
	var cel3: Node3D = Celebration.new()
	cel3.setup({"area": area, "area_id": "surface", "duration": 60.0})
	area.add_child(cel3)
	var st3 := {"done": false}
	var r3 := func() -> void:
		await cel3.play()
		st3["done"] = true
	r3.call()
	cel2.call("finish")
	cel3.queue_free()
	await wait_frames(2)
	assert_true(bool(st3["done"]), "freed with its area: the ending continues")
