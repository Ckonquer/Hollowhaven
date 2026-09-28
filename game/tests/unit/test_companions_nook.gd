extends "res://tests/unit/test_companions_fixture.gd"
## Companion Bed / Perch (src/building/structures/companion_nook.gd, spec §9 LAZY_SCRIPTS, MP §6.5): pressing
## interact makes it a befriended friend's home spot (a perch offers Lumi first, a bed Mochi), pressing again
## offers the next friend; the record keeps home_spot + home_nook, the structure data keeps the companion,
## the spawned companion walks there, and the previous owner goes back to its default spot.
## Depends on src/building/structure.gd (building module) compiling.

const NOOK := "res://src/building/structures/companion_nook.gd"


func _nook(sid: String, pos: Vector3) -> Node3D:
	var uid := GameState.add_structure(sid, pos, 0.0)
	var n: Node3D = load(NOOK).new()
	n.setup({"uid": uid, "id": sid})
	add_child(n)
	n.global_position = pos
	nodes.append(n)
	return n


func test_bed_becomes_a_home_spot_and_passes_between_friends() -> void:
	var bed := _nook("companion_bed", Vector3(4, 0.05, 12))
	var p0: Dictionary = bed.get_interaction(player)
	assert_false(bool(p0["enabled"]), "nobody to offer it to yet")
	_befriend("mochi")
	var m := _make("mochi", "home", Vector3(0, 0.05, 10))
	assert_eq(String(bed.get_interaction(player)["text"]), "Make this Mochi's bed")
	bed.interact(player)
	var rec := GameState.companion("mochi")
	assert_eq(String(rec["home_nook"]), bed.uid)
	assert_true(rec["home_spot"] is Array, "home_spot saved as [x, y, z]")
	assert_eq(m.home_pos, bed.global_position, "Mochi's home moves to the bed")
	assert_eq(String(GameState.structures[bed.uid]["data"]["companion"]), "mochi")
	assert_false(bool(bed.get_interaction(player)["enabled"]), "already Mochi's (no one else to offer)")
	_befriend("pebble")
	assert_eq(String(bed.get_interaction(player)["text"]), "Make this Pebble's bed", "the next friend")
	bed.interact(player)
	assert_eq(String(GameState.companion("pebble")["home_nook"]), bed.uid)
	assert_null(GameState.companion("mochi")["home_spot"], "Mochi goes back to its default spot")
	assert_eq(m.home_pos, Vector3(0, 0.05, 10))


func test_perch_offers_lumi_first_and_one_nook_per_friend() -> void:
	_befriend("mochi")
	_befriend("lumi")
	var perch := _nook("companion_perch", Vector3(-4, 0.05, 12))
	assert_eq(String(perch.get_interaction(player)["text"]), "Make this Lumi's perch")
	perch.interact(player)
	var bed := _nook("companion_bed", Vector3(4, 0.05, 12))
	assert_eq(String(bed.get_interaction(player)["text"]), "Make this Mochi's bed")
	bed.call("assign", "lumi")
	assert_eq(String(GameState.companion("lumi")["home_nook"]), bed.uid, "Lumi moved to the bed")
	var pdata: Dictionary = GameState.structures[perch.uid]["data"]
	assert_false(pdata.has("companion"), "the perch is free again")
	var count := 0
	for id in GameState.companions:
		if GameState.companions[id].get("home_spot") is Array:
			count += 1
	assert_eq(count, 1, "the chapter layer counts companions with a home spot")


func test_a_nook_outside_the_haven_never_moves_a_haven_home() -> void:
	# The building module keeps nooks out of the Reach outpost; a record from elsewhere (old save, another build
	# area) must still never turn Reach coordinates into a Haven home spot.
	_befriend("mochi")
	var uid := GameState.add_structure("companion_bed", Vector3(-16, 0.05, 54), 0.0, "hallowmere_reach")
	var n: Node3D = load(NOOK).new()
	n.setup({"uid": uid, "id": "companion_bed"})
	add_child(n)
	nodes.append(n)
	assert_false(bool(n.get_interaction(player)["enabled"]), "not offered outside the Haven")
	assert_false(bool(n.call("assign", "mochi")), "never assigned")
	assert_null(GameState.companion("mochi")["home_spot"])
