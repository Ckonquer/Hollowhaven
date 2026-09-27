extends "res://tests/test_case.gd"
## The Below: persistent progression (rubble, key, gate, checkpoints, lift, boss state, resources),
## authored moments firing once, lore texts. State survives a GameState save/load round trip.

const Layout := preload("res://src/world/below/below_layout.gd")
const Lore := preload("res://src/world/below/lore.gd")
const Desk := preload("res://src/world/below/foreman_desk.gd")
const WORLD := "res://src/world/below/below_world.gd"
const MASK := 1 | 32

var area: Node3D = null
var events: Array = []


func before_each() -> void:
	fresh_state()
	events = []
	if not Events.horror_event.is_connected(_on_horror):
		Events.horror_event.connect(_on_horror)


func after_each() -> void:
	if Events.horror_event.is_connected(_on_horror):
		Events.horror_event.disconnect(_on_horror)
	await _free_area()


func _on_horror(id: String, _data: Dictionary) -> void:
	events.append(id)


func _free_area() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(3)
	return a


func _rebuild() -> void:
	await _free_area()
	area = await _make_area()


func _blocked(a: Vector3, b: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, a + Vector3.UP * 1.05)
	q.motion = b - a
	q.collision_mask = MASK
	var r := area.get_world_3d().direct_space_state.cast_motion(q)
	return r[0] < 1.0


## Saves, wipes and reloads GameState through SaveSystem (test save dir).
func _round_trip() -> void:
	assert_true(SaveSystem.save_game(), "save ok")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "load ok")


func test_gate_locked_until_key_then_stays_open() -> void:
	area = await _make_area()
	var gate: Node = area.gate
	assert_eq(String(gate.get_interaction(null).get("text", "")), "Try the gate", "locked prompt")
	gate.interact(null)
	assert_false(bool(GameState.get_flag("lower_gate_open")), "locked without the key")
	assert_true(_blocked(Vector3(0, 0, -53.5), Vector3(0, 0, -56.8)), "closed gate blocks the passage")
	GameState.give_item("foreman_key", 1)
	assert_eq(String(gate.get_interaction(null).get("text", "")), "Unlock the gate", "unlock prompt")
	gate.interact(null)
	assert_true(bool(GameState.get_flag("lower_gate_open")), "flag set at once")
	assert_true(gate.get_interaction(null).is_empty(), "no prompt once opening")
	_round_trip()
	assert_true(bool(GameState.get_flag("lower_gate_open")), "flag survives save/load")
	await _rebuild()
	assert_true(area.gate.is_open, "gate is open after reload")
	assert_false(area.gate.is_in_group("interactable"), "open gate isn't interactable")
	await wait_physics(2)
	assert_false(_blocked(Vector3(0, 0, -53.5), Vector3(0, 0, -56.8)), "open gate lets Krystal through")


func test_rubble_clears_with_a_pickaxe_and_persists() -> void:
	area = await _make_area()
	var rubble: Node = area.rubble
	assert_eq(String(rubble.get_harvest_info().get("tool", "")), "pickaxe", "needs a pickaxe")
	assert_true(rubble.is_in_group("harvestable"), "harvestable")
	assert_true(_blocked(Vector3(7.0, 0, -43.75), Vector3(12.8, 0, -43.75)), "rubble blocks the office passage")
	for i in 3:
		rubble.harvest_hit(null, "stone_pickaxe")
	assert_false(bool(GameState.get_flag("gallery_cleared")), "not cleared after 3 hits")
	rubble.harvest_hit(null, "stone_pickaxe")
	assert_true(bool(GameState.get_flag("gallery_cleared")), "cleared after 4 hits")
	assert_true(GameState.is_depleted("below_gallery_rubble"), "depleted permanently")
	assert_true(rubble.get_harvest_info().is_empty(), "no more harvesting")
	await wait_physics(3)
	assert_false(_blocked(Vector3(7.0, 0, -43.75), Vector3(12.8, 0, -43.75)), "passage opens")
	_round_trip()
	await _rebuild()
	assert_true(area.rubble.cleared, "still cleared after reload")
	assert_false(_blocked(Vector3(7.0, 0, -43.75), Vector3(12.8, 0, -43.75)), "passage still open after reload")


func test_foreman_key_is_guaranteed_and_never_duplicated() -> void:
	area = await _make_area()
	var desk: Node = area.desk
	assert_true(Desk.key_available(), "key on the hook")
	desk._take_key(null)
	assert_eq(GameState.count_item("foreman_key"), 1, "key taken")
	desk._take_key(null)
	assert_eq(GameState.count_item("foreman_key"), 1, "no duplicate on a second take")
	assert_false(Desk.key_available(), "hook empty while held")
	assert_true(desk._key_text().is_empty(), "no prompt while held")
	_round_trip()
	assert_eq(GameState.count_item("foreman_key"), 1, "key survives save/load")
	assert_true(bool(GameState.get_flag("foreman_key_taken")), "flag survives save/load")
	await _rebuild()
	assert_false(Desk.key_available(), "no second key after reload")
	# If it were somehow lost before the gate opened, it is available again (never a soft-lock) ...
	GameState.take_item("foreman_key", 1)
	assert_true(Desk.key_available(), "lost key comes back")
	area.desk._take_key(null)
	assert_eq(GameState.count_item("foreman_key"), 1, "exactly one again")
	# ... and once the gate is open it is not needed any more.
	GameState.take_item("foreman_key", 1)
	GameState.set_flag("lower_gate_open", true)
	assert_false(Desk.key_available(), "not offered once the gate is open")
	# Reading the note records the lore
	area.desk._read_note(null)
	assert_true(GameState.lore.has("foreman_order"), "note discovered")


func test_checkpoint_lighting_saves_and_persists() -> void:
	area = await _make_area()
	var cp: Node = area.checkpoints["office"]
	assert_false(cp.lit, "unlit at start")
	assert_eq(String(cp.get_interaction(null)["text"]), "Light the lantern")
	cp.interact(null)
	assert_true(cp.lit, "lit")
	assert_true(bool(GameState.get_flag("cp_lit_office")), "flag set")
	assert_eq(String(GameState.player.get("respawn_area", "")), "below", "respawn area")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "cp_office", "respawn spawn")
	assert_eq(String(GameState.player.get("spawn", "")), "cp_office", "continue resumes at the lantern")
	assert_true(SaveSystem.has_save(), "the lantern saved the game")
	assert_true(cp.is_in_group("light_source") and cp.is_light_active(), "light source")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "load the lantern's save")
	assert_true(bool(GameState.get_flag("cp_lit_office")), "lit flag in the save")
	await _rebuild()
	var cp2: Node = area.checkpoints["office"]
	assert_true(cp2.lit, "re-lit on load")
	assert_false(area.checkpoints["shrine"].lit, "other lanterns stay unlit")
	assert_true(area.is_safe_zone(Layout.CHECKPOINTS["office"]["pos"]), "safe zone restored on load")


func test_lift_only_after_the_weaver_is_defeated() -> void:
	area = await _make_area()
	var lift: Node = area.lift_chamber
	var d: Dictionary = lift.get_interaction(null)
	assert_false(bool(d["enabled"]), "stuck before the boss")
	lift.interact(null)
	assert_false(area._riding, "no ride before the boss")
	assert_false(bool(area.lift_landing.get_interaction(null)["enabled"]), "landing lift stuck too")
	GameState.set_flag("weaver_defeated", true)
	assert_true(bool(lift.get_interaction(null)["enabled"]), "works after the boss")
	assert_eq(String(lift.get_interaction(null)["text"]), "Ride the lift up")
	assert_eq(String(lift.target_spawn), "lift_bottom", "rides to the landing")
	assert_eq(String(area.lift_landing.target_spawn), "lift_chamber", "landing lift goes down")


func test_boss_state_on_load() -> void:
	GameState.set_flag("weaver_defeated", true)
	GameState.set_flag("heartseed_spawned_checked", true)
	area = await _make_area()
	assert_null(area.boss, "no boss when already defeated")
	assert_true(area.cocoon.opened, "cocoon open")
	var pickups := 0
	for n in area.get_tree().get_nodes_in_group("heartseed_pickup"):
		if area.is_ancestor_of(n):
			pickups += 1
	if ResourceLoader.exists("res://src/enemies/weaver_boss.gd"):
		# The boss module re-creates exactly one Heartseed pickup; the cocoon offers nothing extra.
		assert_eq(pickups, 1, "exactly one Heartseed pickup re-created")
		assert_true(area.cocoon._interaction().is_empty(), "cocoon never offers a second seed")
		await _rebuild()
		var again := 0
		for n in area.get_tree().get_nodes_in_group("heartseed_pickup"):
			if area.is_ancestor_of(n) and not n.is_queued_for_deletion():
				again += 1
		assert_eq(again, 1, "still exactly one after another reload")
	else:
		assert_eq(String(area.cocoon._interaction().get("text", "")), "Take the Heartseed", "fallback seed offered")
		area.cocoon._on_interact(null)
		assert_eq(GameState.count_item("heartseed"), 1, "seed given")
		assert_true(area.cocoon._interaction().is_empty(), "no second seed")
	# Once Krystal holds the seed, nothing offers another.
	if GameState.count_item("heartseed") == 0:
		GameState.give_item("heartseed", 1)
	assert_true(area.cocoon._interaction().is_empty(), "nothing while holding the seed")
	GameState.set_flag("ward_restored", true)
	GameState.take_item("heartseed", 1)
	assert_true(area.cocoon._interaction().is_empty(), "never after the ward is restored")


func test_resources_harvest_and_stay_depleted() -> void:
	area = await _make_area()
	var glow: Node = area.find_child("below_glowcap_2", true, false)
	var crystal: Node = area.find_child("below_crystal_1", true, false)
	var silk: Node = area.find_child("below_silk_1", true, false)
	assert_not_null(glow, "glowcap node")
	assert_not_null(crystal, "crystal node")
	assert_not_null(silk, "silk node")
	assert_eq(String(glow.get_harvest_info()["tool"]), "hand")
	assert_true(glow.is_in_group("harvestable") and glow.is_in_group("interactable"), "hand harvestable")
	assert_eq(String(crystal.get_harvest_info()["tool"]), "pickaxe")
	glow.interact(null)
	var g := GameState.count_item("glowcap")
	assert_true(g >= 1 and g <= 2, "1-2 glowcaps (%d)" % g)
	silk.interact(null)
	var s := GameState.count_item("silk")
	assert_true(s >= 1 and s <= 2, "1-2 silk (%d)" % s)
	for i in 3:
		crystal.harvest_hit(null, "stone_pickaxe")
	var e := GameState.count_item("echo_shard")
	assert_true(e >= 1 and e <= 2, "1-2 echo shards (%d)" % e)
	assert_true(bool(glow.depleted) and bool(crystal.depleted), "depleted")
	assert_true(GameState.is_depleted("below_glowcap_2") and GameState.is_depleted("below_crystal_1"), "depletion persisted")
	glow.interact(null)
	assert_eq(GameState.count_item("glowcap"), g, "no double harvest")
	await _rebuild()
	assert_true(bool(area.find_child("below_glowcap_2", true, false).depleted), "still depleted after reload")
	# Enough materials exist below for a Heartbloom Lamp (2 glowcap + 2 silk) and an Echo Chime (3 shards)
	var counts := {}
	for r in Layout.RESOURCES:
		counts[r["kind"]] = int(counts.get(r["kind"], 0)) + 1
	assert_true(int(counts.get("glowcap", 0)) >= 4 and int(counts.get("silk", 0)) >= 3 and int(counts.get("crystal", 0)) >= 3, "enough resource nodes")


func test_authored_moments_fire_once() -> void:
	area = await _make_area()
	var m: Node = area.moments
	var probe := Node3D.new()
	area.add_child(probe)
	m.player_override = probe
	# THE THRESHOLD
	probe.global_position = Vector3(0.0, 0.0, -20.0)
	m.check(probe, 0.1)
	assert_true(bool(GameState.get_flag("moment_threshold")), "threshold fired")
	assert_true(events.has("authored:threshold"), "threshold event")
	m.check(probe, 0.1)
	assert_eq(events.count("authored:threshold"), 1, "only once")
	# THE DISTANT CROSSING: looking down the hall toward the far doorway
	probe.global_position = Vector3(14.0, -6.0, -59.3)
	probe.rotation.y = -PI * 0.5
	m.check(probe, 0.1)
	assert_true(bool(GameState.get_flag("moment_crossing")), "crossing fired")
	assert_true(area.find_child("CrossingShape", true, false) != null, "the pale shape crosses")
	# THE IMITATION: appears, then folds when approached
	probe.global_position = Vector3(44.2, -6.0, -78.5)
	m.check(probe, 0.1)
	assert_true(bool(GameState.get_flag("imitation_seen")), "imitation seen")
	assert_not_null(m.fake, "fake Lumi present")
	var fake: Node3D = m.fake
	var casts_light := false
	for c in fake.find_children("*", "Light3D", true, false):
		casts_light = true
	assert_false(casts_light, "the imitation casts no light")
	probe.global_position = Layout.FAKE_LUMI_POS + Vector3(0.5, 0, 3.0)
	m.check(probe, 0.1)
	assert_true(bool(GameState.get_flag("imitation_folded")), "folds when approached")
	# Into the Silk Hollows + the intro shape
	probe.global_position = Vector3(84.0, -10.0, -85.75)
	m.check(probe, 0.1)
	assert_true(bool(GameState.get_flag("reached_silk_hollows")), "reached silk hollows")
	assert_true(bool(GameState.get_flag("moment_silk_intro")), "silk intro started")
	assert_eq(String(m.silk_state), "watching", "shape watching")
	probe.global_position = Vector3(89.0, -10.0, -85.75)
	m.check(probe, 0.1)
	assert_eq(String(m.silk_state), "rattle", "rattles at a lantern-less Krystal")
	m.check(probe, 3.0)
	assert_eq(String(m.silk_state), "done", "retreats anyway - it never attacks here")
	assert_true(events.has("authored:silk_intro"), "silk intro event")
	# THE NURSERY: silence while inside, back to normal outside
	probe.global_position = Vector3(104.75, -10.0, -70.0)
	m.check(probe, 0.1)
	assert_true(m.in_silence, "silence in the nursery")
	assert_true(bool(GameState.get_flag("moment_nursery")), "nursery flagged")
	probe.global_position = Vector3(105.0, -10.0, -86.0)
	m.check(probe, 0.1)
	assert_false(m.in_silence, "silence ends outside")
	# Nothing repeats after a reload
	_round_trip()
	await _rebuild()
	events.clear()
	var probe2 := Node3D.new()
	area.add_child(probe2)
	area.moments.player_override = probe2
	for p in [Vector3(0, 0, -20), Vector3(14, -6, -59.3), Vector3(44.2, -6, -78.5), Vector3(84, -10, -85.75)]:
		probe2.global_position = p
		area.moments.check(probe2, 0.1)
	for id in ["authored:threshold", "authored:crossing", "authored:imitation", "authored:silk_intro"]:
		assert_false(events.has(id), id + " does not repeat after reload")


func test_lore_texts() -> void:
	assert_true(Lore.all_ids().size() >= 4 and Lore.all_ids().size() <= 6, "4-6 lore notes")
	for id in Lore.all_ids():
		var l: Dictionary = Lore.get_lore(id)
		assert_true(String(l["title"]).length() > 3, "%s has a title" % id)
		assert_true(String(l["text"]).length() > 40, "%s has text" % id)
		assert_true(Layout.LORE_SPOTS.has(id), "%s is placed in the world" % id)
	assert_eq(String(Lore.get_lore("nope")["text"]), "", "unknown id is empty")
	var before := String(Lore.get_lore("hollows_page")["text"])
	Settings.set_value("arachnophobia", true)
	var after := String(Lore.get_lore("hollows_page")["text"])
	Settings.set_value("arachnophobia", false)
	assert_ne(before, after, "arachnophobia wording")
	assert_false(after.to_lower().contains("silk") or after.to_lower().contains("web"), "no silk/web in the alt text")


func test_entering_sets_flag() -> void:
	area = await _make_area()
	var p := Node3D.new()
	area.add_child(p)
	p.global_position = area.get_spawn("mine_entry").origin
	area.on_player_spawned(p)
	assert_true(bool(GameState.get_flag("entered_below")), "entered_below")
