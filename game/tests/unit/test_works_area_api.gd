extends "res://tests/test_case.gd"
## The Hushed Works area API that the deep module (rooms 9-14) builds against (documented at the top of
## src/world/areas_ch2/hushed_works_world.gd), exercised through a stand-in deep builder: spawns, checkpoints
## (respawn area hushed_works), safe rooms / nooks, director anchors, lore notes, exits, doors, moods, boss fights
## (Game.boss_active + director holds), the loop-B lift back to the refuge. Plus the module's data contracts:
## Works lore ids never shadow another module's lore, resource nodes match data/sources.gd, and the shadowed
## light budget of rooms 1-8.

const Layout := preload("res://data/works_layout.gd")
const LoreWorks := preload("res://data/lore_ch2_works.gd")
const LegacyLore := preload("res://src/world/below/lore.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Sources := preload("res://data/sources.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"


## Records what the area asks of a director.
class FakeDirector extends Node:
	var holds: Dictionary = {}
	var suppressed: Array = []

	func hold(id: String) -> void:
		holds[id] = true

	func release(id: String) -> void:
		holds.erase(id)

	func suppress(seconds: float, _replace: bool = false) -> void:
		suppressed.append(seconds)


## A player stand-in for the lift (Game.player.teleport).
class StandIn extends Node3D:
	var teleports: int = 0

	func teleport(xf: Transform3D) -> void:
		teleports += 1
		global_transform = xf


var area: Node3D = null
var _nodes: Array = []
var _built: Dictionary = {}


func before_each() -> void:
	fresh_state()
	_built = {}


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes = []
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _deep_rooms() -> Dictionary:
	return {
		"api_crossing": {"space": 10, "zone": "hw_crossing", "x0": 40.0, "x1": 56.0, "z0": -5.0, "z1": 5.0, "y": -18.0, "h": 5.0,
			"open": {"w": [[-1.5, 1.5, 3.4]]}},
		"api_throat": {"space": 13, "zone": "hw_throat", "x0": 56.0, "x1": 66.0, "z0": -4.0, "z1": 4.0, "y": -18.0, "h": 4.5,
			"open": {"w": [[-1.5, 1.5, 3.2]]}},
	}


## Everything a deep module does during rooms_deep.build(area, builder), through the documented API only.
func _deep_build(a: Node3D, b: Object) -> void:
	for id in ["api_crossing", "api_throat"]:
		b.begin(id)
		b.shell(id, Color("404040"), Color("505050"), Color("303030"))
	a.place_spawn("crossing_gate", Vector3(44.0, -18.0, 0.0), -90.0)
	a.place_spawn("bell_throat", Vector3(61.0, -18.0, 0.0), -90.0)
	a.place_spawn("vault_exit", Vector3(64.0, -18.0, 2.0), -90.0)
	_built["cp"] = a.add_checkpoint("hw_crossing", Vector3(43.0, -18.0, -3.0), "crossing_gate", "hw_crossing")
	_built["cp_throat"] = a.add_checkpoint("hw_throat", Vector3(59.0, -18.0, -2.5), "bell_throat", "hw_throat")
	a.add_safe_room("api_throat")
	_built["anchor"] = a.add_anchor("api_crossing", "hw_crossing", "sound", Vector3(50.0, -15.5, 3.0))
	_built["note"] = a.add_lore_note("lore_ch2_bell_throat_note", Vector3(62.0, -18.0, -3.0), {"flag": "hw_api_note_read", "page": true})
	_built["exit"] = a.add_exit("vault", {"text": "Ride the bell-lift up", "target_area": "hallowmere_reach",
		"target_spawn": "bellhouse_stair", "requires_flag": "ch2_choir_defeated", "locked_text": "Not yet."}, Vector3(65.0, -18.0, 2.0), -90.0)
	_built["door"] = a.add_door("api_gate", {"size": Vector3(3.0, 3.2, 0.3), "flags": ["hw_api_gate"], "style": "grate",
		"name": "A gate", "closed_text": "Shut."}, Vector3(56.0, -18.0, 0.0), -90.0)
	a.register_mood("hw_crossing", {"fog": Color(0.3, 0.2, 0.5), "density": 0.02}, "amb_silk")
	_built["lamp"] = a.lamp(Vector3(52.0, -15.5, -4.6), {"style": "wall", "energy": 0.8, "range": 5.0})
	_built["rooms_seen"] = (a.rooms as Dictionary).has("api_crossing") and (a.rooms as Dictionary).has("refuge")
	_built["builder_shared"] = a.builder == b


func _make_area(director: Node = null) -> Node3D:
	var a: Node3D = load(WORLD).new()
	a.use_deep = false
	a.deep_rooms_override = _deep_rooms()
	a.deep_builder_override = Callable(self, "_deep_build")
	if director != null:
		a.director_override = director
	add_child(a)
	await wait_physics(2)
	return a


# --- The deep module's API -----------------------------------------------------------------------------------------------

func test_deep_api_spawns_checkpoints_safety_and_nodes() -> void:
	area = await _make_area()
	assert_true(bool(_built.get("rooms_seen", false)), "the deep builder sees the merged table")
	assert_true(bool(_built.get("builder_shared", false)), "and the one shared builder")
	for sp in Layout.REQUIRED_SPAWNS:
		assert_true((area.spawns as Dictionary).has(sp), "spawn %s" % sp)
	assert_true((area.deep_spawn_fallbacks as Array).is_empty(), "no hub fallbacks when the deep module registered them")
	assert_almost((area.get_spawn("bell_throat") as Transform3D).origin.x, 61.0, 0.01, "bell_throat where the deep module put it")
	assert_not_null(area.get_node_or_null("SpawnPoints/Spawn_vault_exit"), "a marker per spawn")
	# Checkpoints: lantern named after its spawn, respawn area hushed_works, a safe nook around it.
	var cp: Node = _built["cp"]
	assert_eq(String(cp.name), "RestPoint_crossing_gate")
	assert_true((area.checkpoints as Dictionary).has("hw_crossing"))
	cp.save_enabled = false
	cp.interact(null)
	assert_true(bool(GameState.get_flag("cp_lit_hw_crossing")), "cp_lit_hw_crossing")
	assert_eq([String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))], ["hushed_works", "crossing_gate"])
	assert_true(area.is_safe_zone(Vector3(43.0, -18.0, -3.0)), "the checkpoint nook is safe")
	assert_false(area.is_safe_zone(Vector3(52.0, -18.0, 3.0)), "the rest of the crossing is not")
	assert_true(area.is_safe_zone(Vector3(64.0, -18.0, 3.0)), "a safe room (the Bell Throat) is safe everywhere")
	assert_eq(area.get_zone_at(Vector3(50.0, -17.5, 0.0)), "hw_crossing")
	assert_eq(area.get_zone_at(Vector3(60.0, -17.5, 0.0)), "hw_throat")
	var zone_ids: Array = (area.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
	assert_eq(zone_ids.count("hw_crossing"), 1, "a deep zone is registered once (from the merged table)")
	# Anchor, note, exit, door, lamp.
	var an: Node3D = _built["anchor"]
	assert_true(an.is_in_group("director_anchor"))
	assert_eq([String(an.get_meta("zone")), String(an.get_meta("kind")), String(an.get_meta("room"))], ["hw_crossing", "sound", "api_crossing"])
	var note: Node = _built["note"]
	note.interact(null)
	assert_true(GameState.lore.has("lore_ch2_bell_throat_note"), "the deep module's note is discovered by id")
	assert_true(bool(GameState.get_flag("hw_api_note_read")), "and sets its flag")
	var ex: Node = _built["exit"]
	assert_true(ex.is_in_group("area_exit"))
	assert_false(bool(ex.is_unlocked()), "locked until its flag")
	GameState.set_flag("ch2_choir_defeated", true)
	assert_true(bool(ex.is_unlocked()))
	assert_eq(ex.destination(), {"area": "hallowmere_reach", "spawn": "bellhouse_stair"})
	var door: Node = _built["door"]
	assert_false(bool(door.is_open))
	GameState.set_flag("hw_api_gate", true)
	assert_true(bool(door.is_open), "a works door opens with its flag")
	assert_true(_built["lamp"] is Node3D and (_built["lamp"] as Node3D).is_inside_tree(), "lamp()")


func test_register_mood_and_ambience() -> void:
	area = await _make_area()
	area._set_mood("hw_crossing", true)
	assert_eq(String(area.mood_zone), "hw_crossing")
	var fog: Color = area.env.volumetric_fog_albedo
	assert_almost(fog.r, 0.3, 0.001, "the deep module's fog colour wins")
	assert_almost(fog.b, 0.5, 0.001)
	assert_almost(float(area.env.volumetric_fog_density), 0.02 * float(area.darkness()), 0.0001, "and its density")
	assert_eq(String(area._ambience["hw_crossing"]), "amb_silk")
	# Every Works zone has a mood (cold blue-grey rooms, warm safe rooms).
	for z in Layout.ZONES:
		assert_true((area._moods as Dictionary).has(z), "mood for %s" % z)
	var warm: Color = area._moods["hw_refuge"]["ambient"]
	var cold: Color = area._moods["hw_rails"]["ambient"]
	assert_true(warm.r > warm.b and cold.b > cold.r, "refuge warm, rails cold")


func test_fights_hold_the_director_and_count_as_a_boss() -> void:
	var fake := FakeDirector.new()
	_nodes.append(fake)
	area = await _make_area(fake)
	var saved_area: Variant = Game.area
	Game.area = area
	assert_false(Game.boss_active())
	area.set_fight("crossing_matron", true)
	assert_true(bool(area.fight_active))
	assert_true(Game.boss_active(), "Game.boss_active() reads the area's fight")
	assert_true(fake.holds.has("boss:crossing_matron"), "the director is held while the fight is on")
	area.set_fight("borrowed_choir", true)
	area.set_fight("crossing_matron", false)
	assert_true(bool(area.fight_active), "another fight still running")
	assert_false(fake.holds.has("boss:crossing_matron"))
	assert_true(fake.holds.has("boss:borrowed_choir"))
	area.set_fight("borrowed_choir", false)
	assert_false(bool(area.fight_active))
	assert_false(Game.boss_active())
	assert_true(fake.holds.is_empty(), "every hold released")
	assert_true(fake.suppressed.has(20.0), "a short quiet after a fight")
	# Holds requested before a director exists are applied to it when it appears.
	area.director_override = null
	area.director_hold("scene:test")
	var late := FakeDirector.new()
	_nodes.append(late)
	area.director_override = late
	area._sync_director_holds(0.5)
	assert_true(late.holds.has("scene:test"), "late director picks up the pending hold")
	area.director_release("scene:test")
	assert_false(late.holds.has("scene:test"))
	Game.area = saved_area


func test_loop_b_lift_rides_back_to_the_refuge() -> void:
	area = await _make_area()
	var saved_player: Variant = Game.player
	var saved_comps: Dictionary = Game.companion_nodes
	var p := StandIn.new()
	add_child(p)
	_nodes.append(p)
	p.global_position = Vector3(50.0, -18.0, 0.0)
	Game.player = p
	Game.companion_nodes = {}
	area.ride_lift("nowhere")
	assert_eq(p.teleports, 0, "an unknown spawn is ignored")
	area.ride_lift("refuge")
	area.ride_lift("refuge")      # a second press while riding does nothing
	await wait_seconds(2.8)
	assert_eq(p.teleports, 1, "one ride")
	var xf: Transform3D = area.get_spawn("refuge")
	assert_true(p.global_position.distance_to(xf.origin) < 0.05, "at the refuge spawn")
	assert_eq(area.room_at(p.global_position + Vector3.UP * 0.2), "refuge")
	assert_true(area.is_safe_zone(p.global_position), "the refuge is safe")
	assert_eq(String(area.mood_zone), "hw_refuge", "the refuge mood right away")
	Game.player = saved_player
	Game.companion_nodes = saved_comps


func test_debug_clear_hook_marks_encounters_cleared() -> void:
	area = await _make_area()
	assert_true(bool(area.debug_clear_encounter("hw_sp_lockers")), "debug builds / tests only")
	assert_true(bool(GameState.get_flag("spawner_cleared_hw_sp_lockers")))
	assert_true(bool(GameState.get_flag(Layout.FLAG_LOCKERS_CLEARED)))
	assert_true(bool(area.debug_clear_encounter("hw_sp_bells")))
	assert_true(bool(GameState.get_flag("spawner_cleared_hw_sp_bells")))


# --- Data contracts ------------------------------------------------------------------------------------------------------

func test_works_lore_ids_are_its_own() -> void:
	LoreDB.reload()
	var others: Dictionary = {}
	for id in LegacyLore.LORE:
		others[String(id)] = "legacy"
	for path in ["res://data/lore_ch2_annex.gd", "res://data/lore_ch2_reach.gd", "res://data/lore_ch2_manor.gd", "res://data/lore_ch2_story.gd"]:
		if not ResourceLoader.exists(path):
			continue
		var s: Script = load(path)
		var lore: Variant = s.get_script_constant_map().get("LORE", {})
		if lore is Dictionary:
			for id in lore:
				others[String(id)] = path
	for id in LoreWorks.LORE:
		assert_true(String(id).begins_with("lore_ch2_"), "%s uses the lore_ch2_ namespace" % id)
		assert_false(others.has(String(id)), "%s is not already another module's note (%s)" % [id, String(others.get(String(id), ""))])
	assert_eq(LoreWorks.ORDER.size(), LoreWorks.LORE.size(), "ORDER lists every Works note once")
	for id in LoreWorks.ORDER:
		assert_true(LoreWorks.LORE.has(id), "%s in LORE" % id)
	# Tobin's MP §17 note is the annex's (verbatim there); the Works only gives it context at the sluice.
	assert_eq(String(LoreDB.get_lore("lore_ch2_tobin_note")["text"]),
		"I dropped the lantern when the passage answered me. Hask found me at the sluice. Tell whoever comes after us: the garden below is real.")
	assert_false(Layout.LORE_SPOTS.has("lore_ch2_tobin_note"), "the Works never places the annex's note")
	assert_true(Layout.LORE_SPOTS.has("lore_ch2_sluice_chalk"))
	for id in ["lore_ch2_bell_throat_note", "lore_ch2_before_choir"]:
		assert_true(LoreDB.has_lore(id), "%s for the deep module" % id)


func test_resource_nodes_follow_the_sources_table() -> void:
	area = await _make_area()
	var counts: Dictionary = {}
	for r in Layout.RESOURCES:
		var id := String(r["id"])
		var kind := String(r["kind"])
		assert_true(id.begins_with("hw_%s_" % kind), "%s is an hw_<kind>_<n> id" % id)
		assert_true((area.resource_nodes as Dictionary).has(id), "%s placed" % id)
		var node: Dictionary = Sources.NODES.get(kind, {})
		assert_false(node.is_empty(), "%s is a known node kind" % kind)
		var zones: Array = (node.get("where", {}) as Dictionary).get("hushed_works", [])
		var p: Vector3 = r["pos"]
		var zone: String = area.get_zone_at(p + Vector3.UP * 0.2)
		assert_true(zones.has(zone), "%s stands in an allowed zone (%s)" % [id, zone])
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 1.0)
		q.collision_mask = 1 | 32
		var hit := area.get_world_3d().direct_space_state.intersect_ray(q)
		assert_false(hit.is_empty(), "%s has ground" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.1, "%s on the floor" % id)
		counts[kind] = int(counts.get(kind, 0)) + 1
	for kind in ["glowcap", "crystal"]:
		var need := int(((Sources.NODES[kind] as Dictionary).get("min_count", {}) as Dictionary).get("hushed_works", 0))
		assert_true(int(counts.get(kind, 0)) >= need, "%s: %d >= %d" % [kind, int(counts.get(kind, 0)), need])


func test_shadowed_light_budget_in_rooms_1_to_8() -> void:
	var a: Node3D = load(WORLD).new()
	a.use_deep = false
	add_child(a)
	area = a
	await wait_physics(2)
	var shadowed: Array = []
	for l in a.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled:
			shadowed.append(l)
	assert_true(shadowed.size() <= 10, "few shadowed lights in rooms 1-8 (%d)" % shadowed.size())
	# From any room centre, at most 8 shadowed lights within 40 m (what can be on screen at once).
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var c := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, float(r["y"]) + 1.5, (float(r["z0"]) + float(r["z1"])) * 0.5)
		var near := 0
		for l in shadowed:
			if (l as Node3D).global_position.distance_to(c) < 40.0:
				near += 1
		assert_true(near <= 8, "at most 8 shadowed lights around %s (%d)" % [id, near])
