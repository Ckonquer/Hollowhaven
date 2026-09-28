extends "res://tests/test_case.gd"
## Moonveil Manor grounds district (src/world/reach/districts/manor_grounds.gd, spec §10): valid footprints,
## terrain shaping through the Reach terrain API (edits kept inside hr_manor_grounds), and build(area) on a
## stand-in Reach: the facade and the front door exit (-> moonveil_manor / manor_entry, registered in
## area.exits), the manor_door spawn stays clear and outside, the approach from the arch to the door is
## walkable, ch2_found_manor_lamp on the first approach, the invitation (MP §17 verbatim), the Velvet Wing
## pocket only when the enemy exists, no safe zone added, deterministic and cheap to build.

const Layout := preload("res://data/manor_layout.gd")
const Grounds := preload("res://src/world/reach/districts/manor_grounds.gd")
const Districts := preload("res://src/world/reach/reach_districts.gd")
const TerrainScript := preload("res://src/world/reach/reach_terrain.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const LoreDB := preload("res://src/core/lore_db.gd")

var _area: Node3D = null
var _said: Array = []


## A flat stand-in for the Reach (the district only needs height_at, spawns, exits, add_child).
class FlatReach extends "res://src/world/area_base.gd":
	var exits: Dictionary = {}

	func _ready() -> void:
		area_id = "hallowmere_reach"
		var body := StaticBody3D.new()
		body.name = "FlatGround"
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(160.0, 2.0, 160.0)
		cs.shape = box
		cs.position = Vector3(18.0, -1.0, -70.0)
		body.add_child(cs)
		add_child(body)
		add_zone("hr_manor_grounds", Vector3(18, 0, -74), 26.0, false)
		register_spawn("manor_door", Transform3D(Basis.IDENTITY, Vector3(18.0, 0.08, -82.0)))

	func height_at(_x: float, _z: float) -> float:
		return 0.0


## Records the shaping calls (same method names as reach_terrain.gd).
class FakeTerrain extends RefCounted:
	var calls: Array = []
	func plaza_height(id: String) -> float:
		calls.append(["plaza_height", id])
		return 2.5
	func flatten(center: Vector2, flat_r: float, blend_r: float, height: float) -> void:
		calls.append(["flatten", center, flat_r, blend_r, height])
	func mark_path(points: Array, half_width: float, strength: float = 1.0) -> void:
		calls.append(["mark_path", points.size(), half_width, strength])
	func add_stone_disc(center: Vector2, radius: float) -> void:
		calls.append(["stone", center, radius])
	func tint_disc(center: Vector2, r0: float, r1: float, color: Color, amount: float) -> void:
		calls.append(["tint", center, r1])


func before_each() -> void:
	fresh_state()
	_said.clear()
	if not Events.say.is_connected(_on_say):
		Events.say.connect(_on_say)


func after_each() -> void:
	if Events.say.is_connected(_on_say):
		Events.say.disconnect(_on_say)
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	await wait_frames(2)


func _on_say(speaker: String, text: String, _d: float) -> void:
	_said.append([speaker, text])


func _build() -> Node3D:
	_area = FlatReach.new()
	add_child(_area)
	var t0 := Time.get_ticks_usec()
	Grounds.build(_area)
	_area.set_meta("build_ms", float(Time.get_ticks_usec() - t0) / 1000.0)
	await wait_physics(2)
	return _area


func _space() -> PhysicsDirectSpaceState3D:
	return _area.get_world_3d().direct_space_state


func _clear(p: Vector3, r: float = 0.32) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = 1.6
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0))
	sq.collision_mask = 1 | 32
	return _space().intersect_shape(sq, 4).map(func(o: Dictionary) -> String: return str((o["collider"] as Node).get_path()))


func _floor(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -60.0, z))
	q.collision_mask = 1 | 32
	var hit := _space().intersect_ray(q)
	return NAN if hit.is_empty() else float((hit["position"] as Vector3).y)


# --- Interface ----------------------------------------------------------------------------------------------

func test_district_interface_and_footprints() -> void:
	var names := {}
	for m in (Grounds as Script).get_script_method_list():
		names[String(m["name"])] = true
	for want in ["footprints", "shape_terrain", "build"]:
		assert_true(names.has(want), "static %s()" % want)
	var loaded := Districts.load_all([{"id": "manor_grounds", "path": "res://src/world/reach/districts/manor_grounds.gd", "landmark": "hr_manor_grounds"}])
	assert_eq(loaded.size(), 1, "the Reach loader accepts the script")
	var fps := Districts.footprints(loaded)
	assert_eq(fps.size(), (Layout.GROUNDS["footprints"] as Array).size(), "every footprint validates")
	var lm: Vector2 = Layout.GROUNDS["landmark"]
	var door: Vector2 = Layout.GROUNDS["door"]
	var covers_door := false
	for f in fps:
		var c: Vector2 = f[0]
		assert_true(c.distance_to(lm) <= float(Layout.GROUNDS["landmark_r"]), "footprint %s is centred inside the grounds" % str(c))
		covers_door = covers_door or c.distance_to(door) <= float(f[1])
	assert_true(covers_door, "the house footprint covers the door")
	var fp_arch := false
	for f in fps:
		fp_arch = fp_arch or (f[0] as Vector2).distance_to(Vector2(10, -50)) < float(f[1])
	assert_false(fp_arch, "the region's arch plaza is left alone")


func test_shape_terrain_uses_the_reach_api() -> void:
	var t := FakeTerrain.new()
	Grounds.shape_terrain(t)
	var kinds: Array = t.calls.map(func(c: Array) -> String: return String(c[0]))
	assert_true(kinds.has("plaza_height"), "reads the manor_door plaza level")
	var fl: Array = t.calls.filter(func(c: Array) -> bool: return String(c[0]) == "flatten")
	assert_eq(fl.size(), 1, "one flatten")
	if not fl.is_empty():
		assert_almost(float(fl[0][4]), 2.5, 0.001, "flattened to the plaza level")
	assert_true(kinds.has("mark_path"), "paints the approach path")
	Grounds.shape_terrain(null)      # never crashes
	Grounds.shape_terrain(RefCounted.new())


func test_shape_terrain_on_the_real_reach_terrain_stays_inside_the_grounds() -> void:
	var t: RefCounted = TerrainScript.new()
	t.call("generate_base")
	var before: PackedFloat32Array = (t.get("h") as PackedFloat32Array).duplicate()
	var circle := Districts.landmark_circle("hr_manor_grounds")
	var t0 := Time.get_ticks_msec()
	Districts.shape_one(t, Grounds, circle)
	var ms := Time.get_ticks_msec() - t0
	assert_true(ms < 300, "shaping is cheap (%d ms)" % ms)
	var after: PackedFloat32Array = t.get("h")
	var nx: int = TerrainScript.NX
	var outside_changed := 0
	var inside_changed := 0
	for k in after.size():
		if absf(after[k] - before[k]) < 0.0001:
			continue
		var x := float(k % nx) - TerrainScript.HALF_X
		var z := float(k / nx) - TerrainScript.HALF_Z
		if Vector2(x - circle.x, z - circle.y).length() > circle.z:
			outside_changed += 1
		else:
			inside_changed += 1
	assert_eq(outside_changed, 0, "no edit outside hr_manor_grounds")
	assert_true(inside_changed > 50, "the house footprint was levelled (%d samples)" % inside_changed)
	var plaza := float(t.call("plaza_height", "manor_door"))
	assert_almost(float(t.call("get_height", 18.0, -90.0)), plaza, 0.05, "house footprint at the door plaza level")
	assert_almost(float(t.call("get_height", 18.0, -86.0)), plaza, 0.05, "door at the plaza level")


# --- Build --------------------------------------------------------------------------------------------------

func test_build_places_the_door_exit_and_keeps_the_spawn_clear() -> void:
	# The first build of a session also compiles the scripts it loads (the manor pieces, the Velvet Wing via
	# EnemyFactory.can_spawn): bounded generously, since that cost swings with machine load. The budget that
	# matters for every Reach load is the warm rebuild.
	await _build()
	var cold: float = float(_area.get_meta("build_ms"))
	assert_true(cold < 1000.0, "first grounds build (incl. script loads) in %.0f ms" % cold)
	_area.queue_free()
	_area = null
	await wait_frames(2)
	await _build()
	var ms: float = float(_area.get_meta("build_ms"))
	assert_true(ms < 250.0, "grounds build in %.0f ms" % ms)
	print("    manor grounds build: first %.0f ms, warm %.0f ms" % [cold, ms])
	var d: Node = (_area.get("exits") as Dictionary).get("manor_door")
	assert_not_null(d, "area.exits[manor_door] registered")
	if d == null:
		return
	assert_true(d.is_in_group("area_exit") and d.is_in_group("interactable"))
	assert_eq(String(d.get("target_area")), "moonveil_manor")
	assert_eq(String(d.get("target_spawn")), "manor_entry")
	assert_eq(String(d.get_interaction(null)["text"]), "Enter Moonveil Manor")
	var dp: Vector3 = (d as Node3D).global_position
	assert_almost(Vector2(dp.x, dp.z).distance_to(Layout.GROUNDS["door"]), 0.0, 0.4, "the door stands at the layout point (18, -86)")
	var sp: Vector3 = (_area.spawns["manor_door"] as Transform3D).origin
	assert_eq(_clear(sp, 0.35), [], "spawn manor_door keeps a clear capsule")
	assert_almost(_floor(sp.x, sp.z), 0.0, 0.1, "the spawn stays on the open ground outside")
	assert_true(sp.z > dp.z + 3.0, "the spawn is outside, in front of the door")
	assert_false(_area.is_safe_zone(Vector3(18, 0, -74)), "the grounds stay unsafe")
	assert_eq(_area.get_zone_at(Vector3(18, 0, -74)), "hr_manor_grounds", "no zone added over the landmark")
	assert_eq((_area.zones as Array).size(), 1, "the district adds no zones")


func test_approach_is_walkable_and_the_door_is_in_reach() -> void:
	await _build()
	var pts: Array = Layout.GROUNDS["path"]
	var route: Array = []
	for p in pts:
		route.append(p)
	for i in route.size() - 1:
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var n := maxi(int(a.distance_to(b) / 0.4), 1)
		for k in n + 1:
			var q := a.lerp(b, float(k) / float(n))
			var fy := _floor(q.x, q.y)
			assert_false(is_nan(fy), "ground at %s" % str(q))
			if is_nan(fy):
				continue
			if q.y < -84.8:
				continue      # the last metre is the steps
			var hits := _clear(Vector3(q.x, fy, q.y), 0.3)
			assert_eq(hits, [], "path clear at %s" % str(q))
	# Up the steps: floor rises smoothly to the threshold.
	var prev := _floor(18.0, -84.0)
	for k in 8:
		var z := -84.0 - float(k) * 0.28
		var y := _floor(18.0, z)
		assert_false(is_nan(y), "step floor at z %.2f" % z)
		assert_true(absf(y - prev) < 0.3, "no big step at z %.2f (%.2f -> %.2f)" % [z, prev, y])
		prev = y
	# The door's interaction sphere is within the player's reach from a clear standing point.
	var d: Node3D = (_area.get("exits") as Dictionary)["manor_door"]
	var ib: Node3D = d.get_node("InteractBody")
	var stand := Vector3(18.0, _floor(18.0, -84.9), -84.9)
	assert_eq(_clear(stand, 0.3), [], "standing point in front of the door is clear")
	var sphere_c: Vector3 = (ib.get_child(0) as Node3D).global_position
	assert_true(stand.distance_to(sphere_c) < 2.6 + 1.1, "door within reach (%.2f m)" % stand.distance_to(sphere_c))


func test_found_flag_on_first_approach_and_the_invitation() -> void:
	await _build()
	var c: Node = _area.find_children("ManorGroundsController", "", true, false)[0]
	var far := Node3D.new()
	add_child(far)
	far.global_position = Vector3(10, 0, -40)
	c.set("player_override", far)
	assert_false(bool(c.call("check")), "not from the far side of the arch")
	assert_false(bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)))
	far.global_position = Vector3(18, 0, -82)
	assert_true(bool(c.call("check")), "found on approach")
	assert_true(bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)), "ch2_found_manor_lamp")
	assert_false(bool(c.call("check")), "only once")
	far.queue_free()
	# The invitation: MP §17 verbatim, discovered as lore when the Reach lore file has it.
	var inv: Node = c.get("invitation")
	assert_eq(String(inv.get_interaction(null)["text"]), "Read the invitation")
	inv.interact(null)
	assert_true(_said.any(func(s: Array) -> bool: return String(s[1]) == "To the bearer of a proper light: you are expected. The house has practiced being welcoming."), "MP §17 invitation verbatim")
	assert_eq(GameState.lore.has(Layout.LORE_INVITATION), LoreDB.has_lore(Layout.LORE_INVITATION), "discovered iff the note exists")


func test_tower_lamp_and_wing_pocket_follow_state() -> void:
	await _build()
	var c: Node = _area.find_children("ManorGroundsController", "", true, false)[0]
	assert_false(bool(c.call("lamp_is_lit")), "cold lamp before the manor is restored")
	var has_spawner := _area.find_children("Spawner_hr_sp_manor_wings", "", true, false).size() == 1
	assert_eq(has_spawner, Factory.can_spawn("velvet_wing"), "Velvet Wing pocket exists exactly when the enemy can spawn")
	# The bat sign's board faces the approach path (read face-on from the road).
	var sign_node: Node3D = _area.find_children("BatSign", "", true, false)[0]
	var sp: Vector2 = Layout.GROUNDS["bat_sign"]
	var to_path: Vector2 = Grounds.nearest_path_point(sp) - sp
	var n3: Vector3 = sign_node.global_transform.basis.z
	assert_true(absf(Vector2(n3.x, n3.z).normalized().dot(to_path.normalized())) > 0.95, "the sign faces the path")
	_area.queue_free()
	await wait_frames(2)
	GameState.set_flag(Layout.FLAG_LAMP_LIT, true)
	await _build()
	var c2: Node = _area.find_children("ManorGroundsController", "", true, false)[0]
	assert_true(bool(c2.call("lamp_is_lit")), "the tower lamp shines once ch2_manor_lamp_lit")


## Integration with the real Reach (world module C1): the region's loader builds this district on real
## terrain. Skipped while the Reach scene is still the wave A stand-in.
func test_in_the_real_reach_the_door_spawn_and_steps_line_up() -> void:
	var ps: PackedScene = load("res://scenes/hallowmere_reach.tscn")
	var reach: Node3D = ps.instantiate()
	if reach.get("districts_built") == null:
		reach.free()
		return
	add_child(reach)
	_area = reach
	await wait_physics(3)
	var built: Array = reach.get("districts_built")
	assert_true(built.has("manor_grounds"), "the Reach loader built the manor grounds (%s)" % str(built))
	var d: Node = (reach.get("exits") as Dictionary).get("manor_door")
	assert_not_null(d, "manor_door exit")
	if d == null:
		return
	assert_eq(String(d.name), "ManorFrontDoor", "the district's door, not the region's fallback")
	var sp: Vector3 = (reach.spawns["manor_door"] as Transform3D).origin
	assert_eq(_clear(sp, 0.35), [], "spawn manor_door clear on the real terrain")
	var fy := _floor(sp.x, sp.z)
	assert_true(absf(fy - sp.y) < 0.35, "spawn on the ground (%.2f vs %.2f)" % [fy, sp.y])
	# Steps rise smoothly from the plaza to the threshold, and the door stands on them.
	var prev := _floor(18.0, -83.8)
	for k in 9:
		var z := -83.8 - float(k) * 0.28
		var y := _floor(18.0, z)
		assert_false(is_nan(y), "floor at z %.2f" % z)
		if not is_nan(y) and not is_nan(prev):
			assert_true(absf(y - prev) < 0.32, "walkable rise at z %.2f (%.2f -> %.2f)" % [z, prev, y])
		prev = y
	var door_y := (d as Node3D).global_position.y
	assert_true(absf(door_y - prev) < 0.3, "the door sits on the top step (%.2f vs %.2f)" % [door_y, prev])
	var stand := Vector3(18.0, _floor(18.0, -84.9), -84.9)
	assert_eq(_clear(stand, 0.3), [], "a clear place to stand at the door")
	# The approach from the arch plaza to the spawn is open ground.
	var pts: Array = Layout.GROUNDS["path"]
	for i in pts.size() - 2:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for k in 6:
			var q := a.lerp(b, float(k) / 6.0)
			var y2 := _floor(q.x, q.y)
			assert_false(is_nan(y2), "ground on the approach at %s" % str(q))
			if not is_nan(y2):
				assert_eq(_clear(Vector3(q.x, y2, q.y), 0.3), [], "approach clear at %s" % str(q))
	var bt: Dictionary = reach.get("build_times")
	print("    reach build %.0f ms, all districts %.0f ms" % [float(bt.get("total", 0.0)), float(bt.get("districts_build", 0.0))])


func test_build_is_deterministic_and_reuses_the_manor_door_spawn() -> void:
	await _build()
	var names: Array = _area.find_children("*", "", true, false).filter(func(n: Node) -> bool: return not (n is MultiMeshInstance3D or n is CollisionShape3D or n is MeshInstance3D)).map(func(n: Node) -> String: return str(_area.get_path_to(n)))
	names.sort()
	var sp_before: Transform3D = _area.spawns["manor_door"]
	_area.queue_free()
	await wait_frames(2)
	await _build()
	var names2: Array = _area.find_children("*", "", true, false).filter(func(n: Node) -> bool: return not (n is MultiMeshInstance3D or n is CollisionShape3D or n is MeshInstance3D)).map(func(n: Node) -> String: return str(_area.get_path_to(n)))
	names2.sort()
	assert_eq(names2, names, "same nodes on every build")
	assert_eq(_area.spawns["manor_door"], sp_before, "the Reach's manor_door spawn is never moved by the district")
	assert_false(names.any(func(s: String) -> bool: return s.contains("@")), "no auto-named nodes")
