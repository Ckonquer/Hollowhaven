extends "res://tests/test_case.gd"
## Chapter Two flow & areas (wave A3, kept current for the wave C areas): every new area id is registered in
## Game.AREAS, its scene loads headless (loose cold bound, 1.5 s warm budget), registers EVERY spawn of
## docs/CHAPTER_TWO_SPEC.md §1 on flat, collidable, clear ground, registers its zones, has an environment + light
## somewhere in its tree and a way back. The Reach stand-in follows
## data/hallowmere_layout.gd (= spec §7.2 table). On the surface the Lanternwake waygate stands at a
## validated site (Layout.CH2_POINTS["waygate"]) that keeps the ruin unsafe, stays clear of legacy
## vegetation and never touches the legacy spawns, zones or vegetation plan.

const Layout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")
const Vegetation := preload("res://src/world/surface/vegetation.gd")
const Terrain := preload("res://src/world/surface/terrain.gd")
const Annexes := preload("res://src/world/surface/annexes.gd")
const WaygateScript := preload("res://src/world/surface/waygate.gd")
const AreaBase := preload("res://src/world/area_base.gd")

const NEW_AREAS := ["tobin_annex", "hallowmere_reach", "moonveil_manor", "hushed_works", "echo_trial"]
## Spec §1, verbatim.
const SPEC_SPAWNS := {
	"surface": ["waygate", "annex_door", "annex_hatch"],
	"tobin_annex": ["annex_entry", "annex_lantern", "annex_hatch_below"],
	"hallowmere_reach": ["waygate_arrival", "reach_respawn", "commons_arch", "orchard_arch", "quarry_arch",
		"manor_arch", "conservatory", "manor_door", "bellhouse_stair", "refuge_exit"],
	"moonveil_manor": ["manor_entry", "manor_ballroom", "manor_balcony"],
	"hushed_works": ["service_landing", "works_lockers", "refuge", "crossing_gate", "bell_throat", "vault_exit"],
	"echo_trial": ["trial_start"],
}
## Spec §7.2 zone lists.
const SPEC_ZONES := {
	"tobin_annex": ["ta_entry", "ta_lockers", "ta_sump"],
	"hallowmere_reach": ["hr_commons", "hr_conservatory", "hr_orchard", "hr_pools", "hr_candleyard", "hr_quarry",
		"hr_manor_grounds", "hr_bellhouse"],
	"moonveil_manor": ["mm_cloakroom", "mm_hall", "mm_ballroom", "mm_gallery", "mm_balcony"],
	"hushed_works": ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge",
		"hw_lightwell", "hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"],
	"echo_trial": ["trial"],
}
## Spawns that must stand in a safe zone (arrival points, checkpoints, safe rooms; spec §1 "safe zones").
const SAFE_SPAWNS := {
	"tobin_annex": ["annex_entry", "annex_lantern"],
	"hallowmere_reach": ["waygate_arrival", "reach_respawn", "commons_arch", "orchard_arch", "quarry_arch", "manor_arch", "conservatory"],
	"moonveil_manor": ["manor_entry", "manor_ballroom", "manor_balcony"],
	"hushed_works": ["service_landing", "works_lockers", "refuge", "crossing_gate", "bell_throat"],
	"echo_trial": ["trial_start"],
}
## Points that must NOT be safe (hostile places stay hostile).
const UNSAFE_POINTS := {
	"tobin_annex": [Vector3(0, 0, -25)],
	"hallowmere_reach": [Vector3(-82, 0, 36), Vector3(86, 0, 18), Vector3(18, 0, -74), Vector3(-86, 0, -60), Vector3(72, 0, -74)],
	"moonveil_manor": [Vector3(0, 0, -47), Vector3(0, 0, -18)],
	"hushed_works": [Vector3(-14, 0, -7), Vector3(14, 0, -21)],
	"echo_trial": [Vector3(0, 0, -20)],
}

var _surface: Node3D = null


func _surface_world() -> Node3D:
	if _surface == null or not is_instance_valid(_surface):
		fresh_state()
		_surface = SurfaceWorld.new()
		add_child(_surface)
		await wait_physics(3)
	return _surface


func _load_area(id: String) -> Node3D:
	var ps: Variant = load(String(Game.AREAS[id]))
	if not (ps is PackedScene):
		fail("%s: scene is not a PackedScene" % id)
		return null
	var a: Node3D = (ps as PackedScene).instantiate()
	add_child(a)
	await wait_physics(2)
	return a


## Load-time budget (wave C areas are real now, not stand-ins): a loose bound on the COLD load (scripts compiled
## for the first time, measured by the caller) and the 1.5 s budget on a WARM load - the area's own
## build_times.base_total when it reports one (the Reach: its base world without the district scripts, which
## have their own budgets), else a second instantiation of the same (still loaded) scene.
const COLD_LOAD_MS := 4000
const WARM_LOAD_MS := 1500


## Frees `first` (the cold instance) either way; the PackedScene held here keeps its scripts compiled meanwhile.
func _warm_load_ms(id: String, first: Node3D) -> float:
	var bt: Variant = first.get("build_times")
	var ps: Variant = load(String(Game.AREAS[id]))
	first.queue_free()
	await wait_frames(2)
	if bt is Dictionary and (bt as Dictionary).has("base_total"):
		return float((bt as Dictionary)["base_total"])
	if not (ps is PackedScene):
		return INF
	var t0 := Time.get_ticks_msec()
	var b: Node3D = (ps as PackedScene).instantiate()
	add_child(b)
	await wait_physics(2)
	var ms := float(Time.get_ticks_msec() - t0)
	b.queue_free()
	await wait_frames(2)
	return ms


func _extends_placeholder(s: Variant) -> bool:
	var sc: Script = s as Script
	while sc != null:
		if sc.resource_path == "res://src/world/areas_ch2/placeholder_area.gd":
			return true
		sc = sc.get_base_script()
	return false


## Ground under the spawn (<= 0.35 m) and nothing solid in a player-sized capsule standing there.
func _check_spawn(area: Node3D, area_name: String, spawn_id: String) -> void:
	var space := area.get_world_3d().direct_space_state
	var xf: Transform3D = area.spawns[spawn_id]
	var p := xf.origin
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0)
	q.collision_mask = 1 | 32
	var hit := space.intersect_ray(q)
	assert_false(hit.is_empty(), "%s: ground under spawn %s" % [area_name, spawn_id])
	if not hit.is_empty():
		assert_almost(float(hit["position"].y), p.y, 0.35, "%s: spawn %s sits on the ground" % [area_name, spawn_id])
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0))
	sq.collision_mask = 1 | 32
	var overlaps := space.intersect_shape(sq, 4)
	assert_eq(overlaps.size(), 0, "%s: spawn %s is clear %s" % [area_name, spawn_id, str(overlaps.map(func(o: Dictionary) -> String: return String(o["collider"].name)))])
	assert_true(area.validate_position(p) is Vector3, "%s: spawn %s is a valid saved position" % [area_name, spawn_id])


# --- Registration --------------------------------------------------------------------------------------

func test_new_areas_are_registered_with_scenes() -> void:
	for id in NEW_AREAS:
		assert_true(Game.AREAS.has(id), "Game.AREAS has %s" % id)
		var path := String(Game.AREAS.get(id, ""))
		assert_true(ResourceLoader.exists(path), "%s scene exists (%s)" % [id, path])
	# Legacy ids untouched.
	assert_eq(String(Game.AREAS["surface"]), "res://scenes/surface.tscn")
	assert_eq(String(Game.AREAS["below"]), "res://scenes/below.tscn")
	assert_eq(Game.SAFE_SAVE_AREAS, ["surface", "hallowmere_reach"])
	assert_true(Game.DIRECTOR_AREAS.has("below"), "the Below keeps its horror director")
	assert_true(Game.OUTDOOR_AREAS.has("surface") and Game.OUTDOOR_AREAS.has("hallowmere_reach"), "outdoor areas resume at the saved position")


func test_every_new_area_loads_and_registers_its_spawns_on_clear_ground() -> void:
	for id in NEW_AREAS:
		var t0 := Time.get_ticks_msec()
		var a: Node3D = await _load_area(String(id))
		if a == null:
			continue
		var ms := Time.get_ticks_msec() - t0
		assert_eq(String(a.get("area_id")), String(id), "%s sets its area_id" % id)
		# Wave C replaced the stand-ins: an area that still DECLARES placeholder == true must really be the
		# wave-A stand-in (placeholder_area.gd or a script extending it). Real areas declare false or nothing.
		var ph: Variant = a.get("placeholder")
		if ph is bool and ph:
			assert_true(_extends_placeholder(a.get_script()), "%s declares placeholder = true, so it is the stand-in" % id)
			print("    %s is still a placeholder" % id)
		assert_true(ms < COLD_LOAD_MS, "%s cold load within the loose bound (%d ms incl. 2 physics frames)" % [id, ms])
		for sp in SPEC_SPAWNS[id]:
			assert_true((a.spawns as Dictionary).has(sp), "%s registers spawn %s" % [id, sp])
			if (a.spawns as Dictionary).has(sp):
				_check_spawn(a, String(id), String(sp))
		var zone_ids: Array = (a.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
		for z in SPEC_ZONES[id]:
			assert_true(zone_ids.has(z), "%s registers zone %s" % [id, z])
		for sp in SAFE_SPAWNS[id]:
			var p: Vector3 = (a.spawns[sp] as Transform3D).origin
			assert_true(a.is_safe_zone(p), "%s: spawn %s is in a safe zone" % [id, sp])
		for p in UNSAFE_POINTS[id]:
			assert_false(a.is_safe_zone(p), "%s: %s is not safe" % [id, str(p)])
		# Real areas build their environment and lights inside sub-nodes (districts, rooms): search the whole tree.
		assert_false(a.find_children("*", "WorldEnvironment", true, false).is_empty(), "%s has a WorldEnvironment" % id)
		assert_false(a.find_children("*", "Light3D", true, false).is_empty(), "%s has a light" % id)
		# Every way out leads to a registered area and a spawn that area registers (or to the origin).
		var outs := 0
		for n in a.find_children("*", "Node3D", true, false):
			if n.is_in_group("area_exit") or n.is_in_group("waygate"):
				outs += 1
				if n.get("use_respawn") == true:
					continue
				var ta := String(n.get("target_area"))
				var ts := String(n.get("target_spawn"))
				assert_true(Game.AREAS.has(ta), "%s: exit %s leads to a registered area (%s)" % [id, n.name, ta])
				var legal: Array = SPEC_SPAWNS.get(ta, [])
				assert_true(legal.has(ts), "%s: exit %s arrives at a spec spawn (%s/%s)" % [id, n.name, ta, ts])
		assert_true(outs >= 1, "%s has a way back" % id)
		# Warm load (the scene and its scripts are compiled now).
		var warm: float = await _warm_load_ms(String(id), a)     # frees `a`
		assert_true(warm < WARM_LOAD_MS, "%s loads quickly when warm (%.0f ms; cold %d ms)" % [id, warm, ms])


func test_reach_follows_hallowmere_layout() -> void:
	var a: Node3D = await _load_area("hallowmere_reach")
	if a == null:
		return
	for id in Reach.SPAWNS:
		var want: Vector2 = Reach.SPAWNS[id]["pos"]
		var got: Vector3 = (a.spawns[id] as Transform3D).origin
		assert_almost(Vector2(got.x, got.z).distance_to(want), 0.0, 0.01, "spawn %s at its layout point" % id)
	var arrival: Transform3D = a.spawns["waygate_arrival"]
	assert_true((-arrival.basis.z).dot(Vector3.FORWARD) > 0.99, "waygate_arrival faces north")
	for id in Reach.LANDMARKS:
		var l: Dictionary = Reach.LANDMARKS[id]
		var p: Vector2 = l["pos"]
		assert_eq(a.get_zone_at(Vector3(p.x, 0, p.y)), String(id), "zone at landmark %s" % id)
		assert_eq(a.is_safe_zone(Vector3(p.x, 0, p.y)), bool(l["safe"]), "landmark %s safety" % id)
	var arches: Dictionary = a.get("arches")
	for id in Reach.ARCH_ORDER:
		assert_true(arches.has(id), "arch %s built" % id)
		if arches.has(id):
			var ap: Vector2 = Reach.ARCHES[id]["pos"]
			var n: Node3D = arches[id]
			assert_almost(Vector2(n.global_position.x, n.global_position.z).distance_to(ap), 0.0, 0.01, "arch %s at its layout point" % id)
			assert_eq(String(n.get("spawn_id")), String(Reach.ARCHES[id]["spawn"]), "arch %s travel spawn" % id)
	var gate: Node3D = a.get("waygate")
	assert_not_null(gate, "the mirror waygate exists")
	if gate != null:
		assert_eq(String(gate.get("side")), "reach")
		assert_eq(String(gate.get("target_area")), "surface")
		assert_eq(String(gate.get("target_spawn")), "waygate")
		assert_eq(String(gate.get_interaction(null).get("text", "")), "Return to Hollowhaven Woods", "the way home is always open")
	assert_null(a.validate_position(Vector3(200, 1, 0)), "outside the Reach is rejected")
	a.queue_free()
	await wait_frames(2)


## data/hallowmere_layout.gd reproduces the spec §7.2 table exactly.
func test_hallowmere_layout_matches_spec_table() -> void:
	var table := {
		"hr_commons": [Vector2(0, 60), 24.0, true], "hr_conservatory": [Vector2(0, 6), 14.0, true],
		"hr_orchard": [Vector2(-82, 36), 30.0, false], "hr_pools": [Vector2(-44, -8), 18.0, false],
		"hr_candleyard": [Vector2(-86, -60), 22.0, false], "hr_quarry": [Vector2(86, 18), 30.0, false],
		"hr_manor_grounds": [Vector2(18, -74), 26.0, false], "hr_bellhouse": [Vector2(72, -74), 16.0, false],
	}
	assert_eq(Reach.LANDMARKS.size(), table.size(), "eight landmarks")
	for id in table:
		var l: Dictionary = Reach.LANDMARKS.get(id, {})
		assert_eq(l.get("pos"), table[id][0], "%s centre" % id)
		assert_eq(float(l.get("radius", 0.0)), float(table[id][1]), "%s radius" % id)
		assert_eq(bool(l.get("safe", false)), bool(table[id][2]), "%s safe" % id)
	assert_eq(Reach.POINTS["waygate_arrival"], Vector2(0, 98))
	assert_eq(Reach.POINTS["commons_arch"], Vector2(0, 78))
	assert_eq(Reach.POINTS["orchard_arch"], Vector2(-60, 50))
	assert_eq(Reach.POINTS["quarry_arch"], Vector2(62, 38))
	assert_eq(Reach.POINTS["manor_arch"], Vector2(10, -50))
	assert_eq(Reach.POINTS["manor_door"], Vector2(18, -86))
	assert_eq(Reach.POINTS["winch"], Vector2(100, 0))
	assert_eq(Reach.POINTS["moon_crystal_shelf"], Vector2(110, -26))
	assert_eq(Reach.POINTS["warden_arena"], Vector2(90, 10))
	assert_eq(Reach.OUTPOST_BUILD_AREA, {"center": Vector2(-16, 54), "radius": 8.0})
	assert_eq(Reach.ARCH_ORDER, ["commons", "orchard", "quarry", "manor", "conservatory"])
	for id in Reach.ARCHES:
		assert_true(Reach.SPAWNS.has(String(Reach.ARCHES[id]["spawn"])), "arch %s has a spawn" % id)
		assert_eq(Reach.arch_for_spawn(String(Reach.ARCHES[id]["spawn"])), String(id))
	for id in Reach.SPAWNS:
		assert_true(Reach.is_inside(Reach.SPAWNS[id]["pos"], 3.0), "spawn %s inside the Reach" % id)


# --- Surface: the Lanternwake waygate -----------------------------------------------------------------

func test_surface_registers_the_new_spawns_on_clear_ground() -> void:
	var w: Node3D = await _surface_world()
	for sp in SPEC_SPAWNS["surface"]:
		assert_true((w.spawns as Dictionary).has(sp), "surface registers %s" % sp)
		if (w.spawns as Dictionary).has(sp):
			_check_spawn(w, "surface", String(sp))
			var p: Vector3 = (w.spawns[sp] as Transform3D).origin
			assert_true(w.is_inside_bounds(p, 3.0), "%s inside the boundary" % sp)
			assert_false(w.terrain.is_water(p.x, p.z), "%s is dry" % sp)
	for id in Layout.SPAWN_HINTS:
		assert_true((w.spawns as Dictionary).has(id), "legacy spawn %s still registered" % id)
		var h: Vector2 = Layout.SPAWN_HINTS[id]
		var o: Vector3 = (w.spawns[id] as Transform3D).origin
		assert_almost(Vector2(o.x, o.z).distance_to(h), 0.0, 0.001, "legacy spawn %s unmoved" % id)


func test_waygate_site_is_validated() -> void:
	var w: Node3D = await _surface_world()
	var site: Vector2 = Layout.CH2_POINTS["waygate"]
	var gate: Node3D = w.get_node_or_null("Waygate")
	assert_not_null(gate, "the waygate is built on the surface")
	if gate == null:
		return
	assert_almost(Vector2(gate.global_position.x, gate.global_position.z).distance_to(site), 0.0, 0.001, "gate at CH2_POINTS.waygate")
	assert_eq(String(gate.get("target_area")), "hallowmere_reach")
	assert_eq(String(gate.get("target_spawn")), "waygate_arrival")
	# Spawn: 3 m south, facing south (toward the ruin and home).
	var xf: Transform3D = w.spawns["waygate"]
	assert_almost(xf.origin.x, site.x, 0.01, "spawn x")
	assert_almost(xf.origin.z, site.y + 3.0, 0.01, "spawn 3 m south of the gate")
	assert_true((-xf.basis.z).dot(Vector3.BACK) > 0.99, "arrival faces south, toward home")
	# Never near the Haven (existing saves may have structures there).
	assert_true(site.length() >= Layout.HAVEN_RADIUS + 18.0, "far from the Haven (%.1f m)" % site.length())
	# The ruin stays exactly as it was: its centre is unsafe, its spawner can still spawn.
	var rc: Vector2 = Layout.LANDMARKS["ruin"]["pos"]
	assert_eq(w.get_zone_at(Vector3(rc.x, 2, rc.y)), "ruin")
	assert_false(w.is_safe_zone(Vector3(rc.x, 2, rc.y)), "ruin centre is not safe")
	assert_false(w.is_safe_zone(Vector3(-10, 0, -61.5)), "the ruin_bramblings spawner is not in a safe zone")
	# The small safe zone covers the gate and its spawn and contains no landmark centre.
	assert_true(w.is_safe_zone(Vector3(site.x, 0, site.y)), "the gate stands in a safe zone")
	assert_true(w.is_safe_zone(xf.origin), "the waygate spawn is safe")
	assert_eq(w.get_zone_at(xf.origin), Annexes.WAYGATE_ZONE)
	for z in w.zones:
		if String(z["id"]) != Annexes.WAYGATE_ZONE:
			continue
		assert_true(float(z["radius"]) <= 5.0, "small zone")
		for id in Layout.LANDMARKS:
			var p: Vector2 = Layout.LANDMARKS[id]["pos"]
			var c: Vector3 = z["center"]
			assert_true(Vector2(c.x, c.z).distance_to(p) > float(z["radius"]), "the waygate zone never contains landmark %s" % id)
	for id in Layout.LANDMARKS:
		var p: Vector2 = Layout.LANDMARKS[id]["pos"]
		assert_eq(w.get_zone_at(Vector3(p.x, 0, p.y)), String(id), "zone at landmark %s unchanged" % id)
	# No legacy vegetation within the footprint + 2 m.
	var clear := WaygateScript.FOOTPRINT_RADIUS + 2.0
	var plan: Dictionary = w.vegetation.plan_data
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		for e in plan[k]:
			var p: Vector3 = e["pos"]
			assert_true(Vector2(p.x, p.z).distance_to(site) > clear, "%s %s is clear of the waygate" % [k, e["id"]])
	for k in ["decor_trees", "decor_bushes", "mushrooms", "logs", "decor_rocks", "brambles"]:
		for e in plan[k]:
			for v in e:
				if v is Transform3D:
					var o: Vector3 = (v as Transform3D).origin
					assert_true(Vector2(o.x, o.z).distance_to(site) > clear, "%s at %s is clear of the waygate" % [k, str(o)])
	# Flat enough for the stones.
	var h0: float = w.height_at(site.x, site.y)
	for a in 8:
		var q := site + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * WaygateScript.FOOTPRINT_RADIUS
		assert_true(absf(float(w.height_at(q.x, q.y)) - h0) < 0.5, "flat footprint")


## Golden guard: no Chapter Two addition may change the legacy vegetation plan (saved `depleted` ids).
func test_legacy_vegetation_plan_is_unchanged() -> void:
	var t: RefCounted = Terrain.new()
	t.generate()
	var plan: Dictionary = Vegetation.plan(t)
	var counts := {}
	var parts: PackedStringArray = []
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		counts[k] = (plan[k] as Array).size()
		for e in plan[k]:
			var p: Vector3 = e["pos"]
			parts.append("%s:%.1f,%.1f" % [e["id"], p.x, p.z])
	var digest := "|".join(parts).md5_text()
	print("    vegetation plan: %s md5=%s" % [str(counts), digest])
	assert_eq(counts, GOLDEN_COUNTS, "legacy resource node counts")
	assert_eq(digest, GOLDEN_DIGEST, "legacy resource node ids and positions")


## Recorded from the legacy build (wave A3, before any Chapter Two surface content existed).
const GOLDEN_COUNTS := {"trees": 218, "rocks": 26, "ores": 7, "bushes": 20, "tufts": 40, "sticks": 46, "stones": 46}
const GOLDEN_DIGEST := "bd86320366013834cd23feefa16c4703"


# --- Surface annex hooks ------------------------------------------------------------------------------

func test_optional_annex_scripts_are_safe_loaded() -> void:
	var dir := SaveSystem.save_dir.path_join("annex_fixture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join("fixture_annex.gd")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends RefCounted\n\nstatic func build(area: Node3D) -> void:\n\tarea.set_meta(\"fixture_annex_built\", true)\n\tarea.register_spawn(\"annex_door\", Transform3D(Basis(), Vector3(1, 2, 3)))\n")
	f.close()
	var area: Node3D = AreaBase.new()
	add_child(area)
	area.register_spawn("mine_exit", Transform3D(Basis(), Vector3(48, 1, -64)))
	area.register_spawn("mine_threshold", Transform3D(Basis(), Vector3(50, 1, -66)))
	Annexes._run_annex(area, "res://src/world/surface/c1x/does_not_exist.gd")   # missing: silently skipped
	Annexes._run_annex(area, path)
	assert_true(bool(area.get_meta("fixture_annex_built", false)), "an existing annex script's static build(area) runs")
	Annexes._ensure_fallback_spawns(area)
	assert_eq((area.spawns["annex_door"] as Transform3D).origin, Vector3(1, 2, 3), "a spawn the annex registered is kept")
	assert_eq((area.spawns["annex_hatch"] as Transform3D).origin, Vector3(50, 1, -66), "a missing annex spawn falls back to the mine mouth")
	assert_eq(Annexes.ANNEX_SCRIPTS.size(), 8, "the eight optional annex slots")
	area.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_zz_cleanup() -> void:
	if _surface != null and is_instance_valid(_surface):
		_surface.queue_free()
		_surface = null
	await wait_frames(8)
