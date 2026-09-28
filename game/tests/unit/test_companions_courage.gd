extends "res://tests/unit/test_companions_fixture.gd"
## Mochi's courage (MP 6.4, optional goal Brave Little Steps): the Comfort Ribbon is tied once from the Friends
## menu; the lit, safe lantern beside the OUTSIDE mine threshold turns courage on with Mochi beside Krystal
## (following, or waiting there after refusing); the original refusal is untouched until then; afterwards Mochi
## follows underground and only trembles briefly on horror cues, still following and healing.

const CourageLantern := preload("res://src/world/surface/c1x/courage_lantern.gd")
const Layout := preload("res://data/world_layout.gd")
const COURAGE_LINE := "Mochi checks its ribbon. Then it takes one very brave little step."


func _lantern(pos: Vector3) -> Node3D:
	var n: Node3D = CourageLantern.Lantern.new()
	add_child(n)
	n.global_position = pos
	nodes.append(n)
	return n


func test_comfort_ribbon_is_tied_once_from_the_friends_menu() -> void:
	var m := _follower("mochi")
	var r: Dictionary = m.command("ribbon")
	assert_false(bool(r["ok"]), "no ribbon in the bag yet")
	assert_true(String(r["text"]).contains("Loom"), String(r["text"]))
	GameState.give_item("comfort_ribbon", 2)
	r = m.command("ribbon")
	assert_true(bool(r["ok"]))
	assert_eq(GameState.count_item("comfort_ribbon"), 1, "one ribbon used")
	assert_eq(String(GameState.companion("mochi")["ribbon"]), "comfort_ribbon")
	assert_true(bool(GameState.get_flag("c1x_ribbon_given")), "optional goal objective 1")
	assert_true(_said_contains("ribbon"), "a little line")
	var rib: Variant = m.get("_ribbon_node")
	assert_true(rib is Node3D and (rib as Node3D).visible, "Mochi wears it")
	r = m.command("ribbon")
	assert_false(bool(r["ok"]), "only once")
	assert_eq(GameState.count_item("comfort_ribbon"), 1, "nothing more consumed")
	var p := _make("pebble", "home", Vector3(-3, 0.05, 6))
	_befriend("pebble")
	assert_false(bool(p.command("ribbon")["ok"]), "the Comfort Ribbon is Mochi's")


func test_courage_lantern_needs_the_ribbon_mochi_beside_krystal_and_safety() -> void:
	var lan := _lantern(player.global_position + Vector3(1.5, 0, -1.0))
	assert_false(bool(lan.get_interaction(player)["enabled"]), "nothing to do before Mochi is a friend")
	var m := _follower("mochi")
	await wait_physics(2)
	var p: Dictionary = lan.get_interaction(player)
	assert_false(bool(p["enabled"]))
	assert_true(String(p["reason"]).contains("Comfort Ribbon"), String(p["reason"]))
	GameState.give_item("comfort_ribbon", 1)
	assert_true(bool(m.command("ribbon")["ok"]))
	m.global_position = player.global_position + Vector3(0, 0, 14)
	m.set_physics_process(false)
	p = lan.get_interaction(player)
	assert_true(String(p["reason"]).contains("together"), "Mochi has to be here: %s" % String(p["reason"]))
	m.set_physics_process(true)
	m.global_position = player.global_position + Vector3(1.0, 0, 0.8)
	var e := _enemy(player.global_position + Vector3(0, 0, -6))
	p = lan.get_interaction(player)
	assert_false(bool(p["enabled"]), "not while something hunts Krystal nearby")
	assert_true(String(p["reason"]).contains("safe"), String(p["reason"]))
	e.threatening = false
	p = lan.get_interaction(player)
	assert_true(bool(p["enabled"]), "ready: %s" % str(p))
	lan.interact(player)
	assert_true(bool(GameState.get_flag("c1x_mochi_courage")), "courage")
	assert_true(_said_contains(COURAGE_LINE), "the line: %s" % str(said))
	assert_eq(m.get_state(), "brave", "one very brave little step")
	await wait_seconds(2.6)
	assert_eq(m.get_state(), "follow", "and on it goes beside Krystal")
	assert_false(bool(lan.get_interaction(player)["enabled"]), "done once")
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_brave_little_steps"), "Brave Little Steps completes (reward paid by the optional log)")


func test_mochi_waiting_at_the_threshold_can_take_the_step() -> void:
	var th := Vector3(0, 0.05, -12)
	var m := _make("mochi", "follow", Vector3(1, 0.05, 2), {"threshold": th})
	_befriend("mochi", "follow")
	GameState.give_item("comfort_ribbon", 1)
	assert_true(bool(m.command("ribbon")["ok"]))
	var lan := _lantern(th + Vector3(2.3, 0, 1.2))
	player.global_position = Vector3(0, 0.05, -5)
	await wait_physics(3)
	assert_eq(m.get_state(), "refuse", "with the ribbon but no courage yet the refusal is unchanged")
	await wait_seconds(5.8)
	assert_eq(String(GameState.companion("mochi")["assignment"]), "wait", "waiting at the mine's mouth")
	player.global_position = lan.global_position + Vector3(-0.8, 0, 1.5)
	await wait_physics(2)
	assert_true(bool(lan.get_interaction(player)["enabled"]), "the waiting Mochi counts as beside her")
	lan.interact(player)
	assert_true(bool(GameState.get_flag("c1x_mochi_courage")))
	assert_eq(GameState.active_companion, "mochi", "Mochi follows Krystal again")
	# Walking down to the mine now: no refusal.
	await wait_seconds(2.6)
	player.global_position = Vector3(0, 0.05, 10)
	await wait_physics(4)
	player.global_position = Vector3(0, 0.05, -7)
	await wait_physics(6)
	assert_ne(m.get_state(), "refuse", "brave enough for the mine")


func test_courage_mid_refusal_ends_it() -> void:
	var th := Vector3(0, 0.05, -12)
	var m := _make("mochi", "follow", Vector3(1, 0.05, 2), {"threshold": th})
	_befriend("mochi", "follow")
	player.global_position = Vector3(0, 0.05, -5)
	await wait_physics(3)
	assert_eq(m.get_state(), "refuse")
	GameState.set_flag("c1x_mochi_courage", true)
	assert_ne(m.get_state(), "refuse", "the refusal stops where it is")
	await wait_seconds(0.5)
	assert_eq(String(GameState.companion("mochi")["assignment"]), "follow")


func test_courage_lets_mochi_follow_underground() -> void:
	assert_false(bool(Spawner.courage_def("mochi")["enters_below"]))
	GameState.set_flag("c1x_mochi_courage", true)
	assert_true(bool(Spawner.courage_def("mochi")["enters_below"]), "the spawn plan sees a brave Mochi")
	assert_false(bool(ItemDB.creature("mochi")["enters_below"]), "the data file stays untouched")
	_befriend("mochi", "follow")
	var area: Node3D = AreaBase.new()
	add_child(area)
	nodes.append(area)
	for id in ["mochi", "pebble", "lumi"]:
		area.register_spawn("companion_home_" + id, Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 10)))
	player.global_position = Vector3(0, 0.05, 0)
	for a in ["below", "tobin_annex", "hushed_works"]:
		var out: Dictionary = Spawner.spawn_for_area(area, a, player)
		for id in out:
			nodes.append(out[id])
		assert_true(out.has("mochi"), "Mochi comes into %s" % a)
		assert_eq(GameState.active_companion, "mochi")
		for id in out:
			(out[id] as Node).queue_free()
		await wait_frames(1)


func test_brave_mochi_trembles_briefly_but_keeps_following_and_healing() -> void:
	GameState.set_flag("c1x_mochi_courage", true)
	var m := _follower("mochi")
	await wait_physics(2)
	player.health.hp = 40.0
	assert_true(bool(m.use_skill(true)["ok"]))
	m.notice_threat(player.global_position + Vector3(0, 0, -8))
	assert_eq(m.get_state(), "afraid", "a brief tremble on a horror cue")
	assert_eq(String(m.get("mode")), "follow", "still following")
	await wait_seconds(1.9)
	assert_eq(m.get_state(), "follow", "only briefly (1.5 s)")
	assert_true(float(player.health.hp) > 44.0, "Bloomguard kept healing meanwhile (%.1f)" % float(player.health.hp))
	# Without courage the original 4 s hide stays.
	GameState.set_flag("c1x_mochi_courage", false)
	m.notice_threat(player.global_position + Vector3(0, 0, -8))
	await wait_seconds(2.0)
	assert_eq(m.get_state(), "afraid", "the timid Mochi hides longer")


## Horror cues (Events.horror_event, director events and authored moments) reach the following Mochi herself:
## brave Mochi shelters for a moment and carries on; the timid one keeps the old longer hide; the others and a
## Mochi at home are untouched by this hook.
func test_horror_cue_makes_mochi_shelter_briefly_once_brave() -> void:
	GameState.set_flag("c1x_mochi_courage", true)
	var m := _follower("mochi")
	_befriend("pebble")
	var p := _make("pebble", "home", Vector3(-3, 0.05, 10))
	await wait_physics(2)
	Events.horror_event.emit("authored:hw_knock", {})
	assert_eq(m.get_state(), "afraid", "shelters behind Krystal")
	assert_eq(String(m.get("mode")), "follow", "still following")
	assert_eq(p.get_state(), "home", "Pebble at home is not part of it")
	await wait_seconds(1.9)
	assert_eq(m.get_state(), "follow", "only a moment")
	# A director event with a position; without courage the old 4 s hide stays.
	GameState.set_flag("c1x_mochi_courage", false)
	Events.horror_event.emit("wrong_sound", {"pos": player.global_position + Vector3(0, 0, -9)})
	assert_eq(m.get_state(), "afraid")
	await wait_seconds(2.0)
	assert_eq(m.get_state(), "afraid", "the timid Mochi hides longer")


func test_lantern_site_is_beside_the_outside_threshold() -> void:
	var s := CourageLantern.site()
	var th: Vector2 = Layout.SPAWN_HINTS["mine_threshold"]
	var ex: Vector2 = Layout.SPAWN_HINTS["mine_exit"]
	assert_true(s.distance_to(th) <= 2.5, "right beside the threshold (%.2f m)" % s.distance_to(th))
	assert_true(s.distance_to(ex) >= 3.5, "clear of the mine_exit spawn (%.2f m)" % s.distance_to(ex))
	assert_true(s.distance_to(Vector2(54, -74)) > 8.0, "outside, well before the tunnel (%.2f m)" % s.distance_to(Vector2(54, -74)))
	assert_eq(CourageLantern.grass_clearings().size(), 1)
	var area: Node3D = AreaBase.new()
	add_child(area)
	nodes.append(area)
	var n: Node3D = CourageLantern.build(area)
	assert_not_null(n, "built into the surface area")
	assert_true(Vector2(n.global_position.x, n.global_position.z).distance_to(s) < 0.01)
	assert_null(CourageLantern.build(area), "only once per area")
	assert_true(n.is_in_group("interactable") and n.is_in_group("light_source"), "an interactable, lit lantern")


## Geometry check (no screenshots in this wave): the lantern stands on open, flat ground at the mine apron,
## clear of every legacy vegetation node, of Tobin's side door / hatch and of the other Chapter One additions.
func test_lantern_site_is_clear_of_everything_on_the_surface() -> void:
	var t: RefCounted = load("res://src/world/surface/terrain.gd").new()
	t.generate()
	var plan: Dictionary = load("res://src/world/surface/vegetation.gd").plan(t)
	var s := CourageLantern.site()
	var clear := 1.6
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		for e in plan[k]:
			var p: Vector3 = e["pos"]
			assert_true(Vector2(p.x, p.z).distance_to(s) > clear, "%s %s is clear of the lantern" % [k, e["id"]])
	for k in ["decor_trees", "decor_bushes", "mushrooms", "logs", "decor_rocks", "brambles"]:
		if not plan.has(k):
			continue
		for e in plan[k]:
			for v in e:
				if v is Transform3D:
					var o: Vector3 = (v as Transform3D).origin
					assert_true(Vector2(o.x, o.z).distance_to(s) > 1.2, "%s at %s is clear of the lantern" % [k, str(o)])
	var h0 := float(t.height_at(s.x, s.y))
	for a in 8:
		var q := s + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * 0.6
		assert_true(absf(float(t.height_at(q.x, q.y)) - h0) < 0.35, "flat enough for the post")
	var tobin := "res://src/world/surface/c1x/tobin_door.gd"
	if ResourceLoader.exists(tobin):
		var ts: Script = load(tobin)
		if ts != null and ts.can_instantiate():
			assert_true(s.distance_to(ts.call("door_site")) > 4.0, "clear of Tobin's side door (%.1f m)" % s.distance_to(ts.call("door_site")))
			assert_true(s.distance_to(ts.call("hatch_site")) > 4.0, "clear of the annex hatch")
	var c1x := "res://data/c1x_layout.gd"
	if ResourceLoader.exists(c1x):
		var cs: Script = load(c1x)
		if cs != null and cs.can_instantiate():
			for f in cs.call("footprints"):
				assert_true(s.distance_to(f["pos"]) > float(f["radius"]) + 1.0, "clear of %s" % String(f["id"]))
