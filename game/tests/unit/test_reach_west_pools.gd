extends "res://tests/unit/test_reach_west_fixture.gd"
## Thimblebrook Pools (module C2): the visual chime trail (in order, untimed, captioned, reward once through the
## ledger, state across reloads), high-visibility cues, shallow water visuals, and no reed-creature encounter.

var _captions: Array = []


func before_each() -> void:
	_captions = []
	Events.caption.connect(_on_caption)


func after_each() -> void:
	Events.caption.disconnect(_on_caption)
	await super.after_each()


func _on_caption(t: String) -> void:
	_captions.append(t)


func _pools() -> Node3D:
	var h: Node3D = await flat_host()
	var p: Node3D = Pools.build_district(h)
	await wait_physics(1)
	return p


func _at(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func _glinting(p: Node3D) -> Array:
	var out: Array = []
	for i in p.chimes.size():
		if (p.chimes[i]["glint"] as Node3D).visible:
			out.append(i)
	return out


func test_chime_trail_rings_in_order_and_pays_once() -> void:
	var p: Node3D = await _pools()
	assert_eq(p.trail_state, "active")
	assert_true(p.is_processing(), "the chime proximity check runs while the trail is active")
	assert_eq(_glinting(p), [0], "exactly one chime glints: the first")
	assert_false(p.pouch.visible, "the pouch is hidden until the trail is followed")
	assert_eq(p.check_chimes(_at(Data.CHIMES[2])), -1, "a later chime does nothing out of order")
	assert_eq(p.check_chimes(_at(Data.CHIMES[0] + Vector2(Data.CHIME_REACH + 0.5, 0))), -1, "not close enough yet")
	assert_eq(p.check_chimes(_at(Data.CHIMES[0] + Vector2(1.5, 0))), 0, "rings when she walks up")
	assert_eq(_glinting(p), [1], "the glint moves on")
	assert_true(_captions.size() == 1 and String(_captions[0]).contains("chime"), "every ring is captioned (sound muted still works)")
	await wait_seconds(1.5)
	assert_eq(_glinting(p), [1], "no timing: the glint waits for her")
	for i in range(1, Data.CHIMES.size()):
		assert_eq(p.check_chimes(_at(Data.CHIMES[i])), i)
	assert_eq(p.trail_state, "found")
	assert_false(p.is_processing(), "no per-frame work once the last chime has rung")
	assert_true(flag(Data.FLAG_CHIMES_FOUND))
	assert_eq(_glinting(p), [], "all quiet")
	assert_true(p.pouch.visible, "the lost pouch shows under the willow")
	var it: Node3D = p.interactables["chime_pouch"]
	assert_eq(String(it.get_interaction(null)["text"]), "Open the lost festival pouch")
	var bundle: Dictionary = ItemDB.reward_bundle(Data.REWARD_CHIMES)
	if bundle.is_empty():
		bundle = Data.CHIME_REWARD_FALLBACK
	var before := {}
	for id in bundle["items"]:
		before[id] = GameState.count_item(String(id))
	it.interact(null)
	assert_true(GameState.has_reward(Data.REWARD_CHIMES), "paid through the reward ledger")
	for id2 in bundle["items"]:
		assert_eq(GameState.count_item(String(id2)), int(before[id2]) + int(bundle["items"][id2]), "%s given" % id2)
	assert_true(flag(Data.FLAG_CHIMES_DONE))
	assert_false(p.pouch.visible)
	assert_false(p.take_pouch(), "never twice")
	for id3 in bundle["items"]:
		assert_eq(GameState.count_item(String(id3)), int(before[id3]) + int(bundle["items"][id3]), "%s not given twice" % id3)
	assert_eq(p.check_chimes(_at(Data.CHIMES[0])), -1, "the trail is done")


func test_trail_state_survives_reloads() -> void:
	var p: Node3D = await _pools()
	for i in Data.CHIMES.size():
		p.check_chimes(_at(Data.CHIMES[i]))
	var dict: Dictionary = GameState.to_dict()
	var h2: Node3D = HostScript.new()
	h2.area_id = Data.AREA_ID
	h2.add_ground(Rect2(-140, -110, 280, 220), 0.0, Color.BROWN, "grass")
	add_child(h2)
	_hosts.append(h2)
	GameState.from_dict(dict)
	var p2: Node3D = Pools.build_district(h2)
	assert_eq(p2.trail_state, "found", "the revealed pouch waits after a reload")
	assert_true(p2.pouch.visible)
	assert_true(p2.take_pouch())
	var h3: Node3D = HostScript.new()
	h3.area_id = Data.AREA_ID
	h3.add_ground(Rect2(-140, -110, 280, 220), 0.0, Color.BROWN, "grass")
	add_child(h3)
	_hosts.append(h3)
	var p3: Node3D = Pools.build_district(h3)
	assert_eq(p3.trail_state, "done")
	assert_false(p3.pouch.visible)
	assert_eq(_glinting(p3), [])


func test_high_visibility_cue_marks_the_active_chime() -> void:
	var p: Node3D = await _pools()
	assert_false((p.chimes[0]["ring"] as Node3D).visible, "no ring by default")
	Settings.set_value("high_visibility_cues", true)
	assert_true((p.chimes[0]["ring"] as Node3D).visible, "bold ring on the active chime")
	assert_false((p.chimes[1]["ring"] as Node3D).visible, "only the active one")
	p.check_chimes(_at(Data.CHIMES[0]))
	assert_true((p.chimes[1]["ring"] as Node3D).visible, "the ring follows the glint")
	Settings.set_value("high_visibility_cues", false)
	assert_false((p.chimes[1]["ring"] as Node3D).visible)


func test_quiet_pools_have_no_fight_and_real_water_visuals() -> void:
	var p: Node3D = await _pools()
	assert_eq(Data.spawners_in(Data.POOLS), [], "the optional reed-creature encounter is not built (documented)")
	for n in p.find_children("*", "", true, false):
		assert_false((n as Node).is_in_group("enemy"), "no enemies in the pools")
		assert_false(n.get_class() == "Node3D" and String(n.name).begins_with("hr_sp_"), "no spawner")
	var brook: MeshInstance3D = p.get_node("Brook")
	assert_not_null(brook)
	assert_true(brook.material_override is ShaderMaterial, "flowing water material")
	assert_true(p.get_node("Pool_1") is MeshInstance3D, "pools are drawn")
	# The water surfaces carry no collider: she wades (ankle-deep) on the ground below - no swimming.
	for n2 in p.find_children("Pool_*", "MeshInstance3D", true, false):
		assert_eq((n2 as Node).get_child_count(), 0, "%s has no body" % n2.name)
	# The brook ends where the region's Thimblebrook starts (its first BROOK_POINTS point).
	var reach_script: Script = load("res://data/hallowmere_layout.gd")
	var bp: Variant = reach_script.get_script_constant_map().get("BROOK_POINTS")
	if bp is Array and not (bp as Array).is_empty():
		assert_true((Data.BROOK.back() as Vector2).distance_to((bp as Array)[0]) < 2.0, "our brook flows into the region's Thimblebrook")
