extends "res://tests/unit/test_trials_harness.gd"
## The echo stones (src/world/trial/trial_entry.gd, module D1) and where the origin areas place them (spec §1):
## Moonveil Manor by the ballroom rest candles after ch2_velour_defeated, the Hushed Works' Bell Throat after
## ch2_choir_defeated (also live, the moment the flag is set). The TRIAL MENU (echo_trial.gd menu_text) explains the
## memory and shows the trial's own record - clears and best time - and what the next clear leaves.

const Entry := preload("res://src/world/trial/trial_entry.gd")
const ManorLayout := preload("res://data/manor_layout.gd")
const VaultLayout := preload("res://data/works_layout_deep.gd")
const MANOR_SCENE := "res://scenes/moonveil_manor.tscn"
const WORKS := "res://src/world/areas_ch2/hushed_works_world.gd"

var _saved_mode: String = ""


## Stands in for ui_root.confirm(): records what the stone asked and answers after a couple of frames.
class FakeUi extends Node:
	var answer: String = "cancel"
	var asked: Array = []

	func confirm(title: String, text: String, buttons: Array = []) -> String:
		asked.append([title, text, buttons])
		await get_tree().process_frame
		await get_tree().process_frame
		return answer


func before_each() -> void:
	super.before_each()
	_saved_mode = Game.mode


func after_each() -> void:
	Game.mode = _saved_mode
	await super.after_each()


func _entry(id: String, area: String, spawn: String) -> Node3D:
	var e: Node3D = Entry.new()
	e.setup({"trial": id, "origin_area": area, "origin_spawn": spawn})
	add_child(e)
	nodes.append(e)
	return e


func test_the_stone_offers_its_trial_only_after_the_story_fight() -> void:
	var e := _entry("velour", "moonveil_manor", "manor_ballroom")
	assert_true(e.is_in_group("interactable"))
	var area3d: Array = e.find_children("*", "Area3D", true, false)
	assert_true(area3d.size() == 1 and ((area3d[0] as Area3D).collision_layer & 16) != 0, "the probe finds it (layer 16)")
	assert_eq(e.get_interaction(null), {}, "nothing to offer before the Count is freed")
	GameState.set_flag("ch2_velour_defeated", true)
	var it: Dictionary = e.get_interaction(null)
	assert_eq(String(it.get("text", "")), "Echo Trial: The Last Waltz (a remembered challenge)")
	assert_true(bool(it.get("enabled", false)))
	assert_eq(e.find_children("*", "StaticBody3D", true, false).size(), 0, "not solid unless asked: it blocks nobody")
	# Not while a fight is on / outside ordinary play: no travel. Only a boss fight says "a fight is on".
	var respawn_before := [String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))]
	Game.mode = "cutscene"
	var notes: Array = []
	var on_note := func(t: String, _k: String) -> void: notes.append(t)
	Events.notify.connect(on_note)
	e.interact(null)
	await wait_frames(1)
	assert_eq(EchoTrial.pending_trial, "", "no trip starts")
	assert_eq(notes, ["The echo stays quiet for now."], "a cutscene / menu: the plain line (no fight is on)")
	# A boss fight on (even in ordinary play): the fight line.
	notes.clear()
	Game.mode = "playing"
	Game._bosses["test_boss"] = true
	e.interact(null)
	await wait_frames(1)
	Game._bosses.erase("test_boss")
	assert_eq(EchoTrial.pending_trial, "", "no trip starts during a boss fight")
	assert_eq(notes, ["The echo stays quiet while a fight is on."], "says a fight is on")
	# Both at once: the fight is the reason.
	notes.clear()
	Game.mode = "cutscene"
	Game._bosses["test_boss"] = true
	e.interact(null)
	await wait_frames(1)
	Game._bosses.erase("test_boss")
	assert_eq(notes, ["The echo stays quiet while a fight is on."])
	Events.notify.disconnect(on_note)
	assert_eq([String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))], respawn_before, "the respawn is untouched")


## Interacting opens ONE trial menu (the confirm dialog carries menu_text: memory, record, reward); no second prompt
## or menu while it is open; "Not now" starts no trip and leaves the respawn point alone; the stone is offered again.
func test_the_stone_opens_the_trial_menu_and_not_now_changes_nothing() -> void:
	completed_save()
	EchoTrial.record_clear("velour", 151.2)
	var e := _entry("velour", "moonveil_manor", "manor_ballroom")
	var ui := FakeUi.new()
	add_child(ui)
	nodes.append(ui)
	var saved_ui: Node = Game.ui
	Game.ui = ui
	Game.mode = "playing"
	var respawn_before := [String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))]
	var went: Array = []
	e.entered.connect(func(id: String) -> void: went.append(id))
	e.interact(null)
	var open_now := bool(e.get("menu_open"))
	var prompt_while_open: Dictionary = e.get_interaction(null)
	e.interact(null)                 # a second press while the menu is up
	await wait_frames(4)
	Game.ui = saved_ui
	assert_true(open_now, "the menu opened")
	assert_eq(prompt_while_open, {}, "no prompt while the menu is open")
	assert_eq(ui.asked.size(), 1, "one menu")
	if ui.asked.size() == 1:
		var m := EchoTrial.menu_text("velour")
		assert_eq(String(ui.asked[0][0]), String(m["title"]), "titled with the trial")
		assert_eq(String(ui.asked[0][1]), String(m["body"]), "the memory, the record and the reward")
		assert_true(String(ui.asked[0][1]).contains("Cleared 1 time - best time 2:31"), "clears and best time on the menu")
		var ids: Array = []
		for b in ui.asked[0][2]:
			ids.append(String((b as Array)[0]))
		assert_eq(ids, ["enter", "cancel"], "Enter the echo / Not now")
	assert_false(bool(e.get("menu_open")), "closed again")
	assert_eq(went, [], "Not now: no trip")
	assert_eq(EchoTrial.pending_trial, "", "nothing pending")
	assert_eq([String(GameState.player.get("respawn_area", "")), String(GameState.player.get("respawn_spawn", ""))], respawn_before, "the respawn is untouched")
	assert_false(e.get_interaction(null).is_empty(), "offered again")


func test_the_trial_menu_shows_the_record_and_what_a_clear_leaves() -> void:
	completed_save()
	var m := EchoTrial.menu_text("velour")
	assert_eq(String(m["title"]), "Echo Trial: The Last Waltz (a remembered challenge)")
	assert_true(String(m["body"]).contains("memory, not undone history"), "a memory, not undone history")
	assert_true(String(m["body"]).contains(ItemDB.enemy_display_name("count_velour")), "names the Count")
	assert_eq(String(m["record"]), "Not cleared yet.")
	# The catalogue has every trial pattern (data/appearance.gd), so the menu names it.
	assert_eq(String(m["reward"]), "First clear: the Moonlit Masquerade pattern, to sew at the Loom.")
	assert_eq(String(EchoTrial.menu_text("choir")["reward"]), "First clear: the Chime Chorister pattern, to sew at the Loom.")
	assert_true(String(m["body"]).contains("Not cleared yet.") and String(m["body"]).contains(String(m["reward"])))
	assert_eq(String(EchoTrial.menu_text("matron")["reward"]), "First clear: the Moon Moth Shawl pattern, to sew at the Loom.", "a catalogued pattern is named")
	EchoTrial.record_clear("velour", 151.2)
	m = EchoTrial.menu_text("velour")
	assert_eq(String(m["record"]), "Cleared 1 time - best time 2:31", "clears and best time")
	assert_true(String(m["reward"]).begins_with("Each clear leaves a little: "), "repeat rewards after the first")
	assert_true(String(m["reward"]).contains(ItemDB.display_name("lantern_wax")))
	assert_true(String(m["reward"]).contains("Every third clear adds " + ItemDB.display_name("woven_cloth")))
	EchoTrial.record_clear("velour", 98.0)
	EchoTrial.record_clear("velour", 120.0)
	assert_eq(EchoTrial.record_line("velour"), "Cleared 3 times - best time 1:38")
	assert_true(String(EchoTrial.menu_text("velour")["body"]).contains("best time 1:38"), "the menu body carries it")
	assert_eq(EchoTrial.record_line("choir"), "Not cleared yet.", "each trial keeps its own record")
	assert_eq(EchoTrial.menu_text("nope"), {})
	# The Matron's menu uses the same record (the Below's stone shows it too: test_enemies_boss_trial).
	assert_true(String(EchoTrial.menu_text("matron")["body"]).contains("Not cleared yet."))


func test_the_record_label_in_the_trial_follows_a_clear() -> void:
	completed_save()
	EchoTrial.record_clear("velour", 200.0)
	var a := await trial_area("velour")
	var rl: Label3D = a.get("record_label")
	assert_not_null(rl)
	assert_eq(rl.text, "Cleared 1 time - best time 3:20")


func test_the_manor_places_the_stone_by_the_ballroom_candles_after_the_count() -> void:
	var m: Node3D = (load(MANOR_SCENE) as PackedScene).instantiate()
	add_child(m)
	nodes.append(m)
	await wait_physics(2)
	assert_null(m.get("echo_entry"), "no stone before the Count is freed")
	m.call("debug_mark_velour_defeated")
	var e: Node3D = m.get("echo_entry")
	assert_not_null(e, "the stone appears the moment he is freed")
	if e == null:
		return
	assert_true(String(e.get_script().resource_path).ends_with("src/world/trial/trial_entry.gd"), "the module's stone")
	assert_eq(String(e.get("trial_id")), "velour")
	assert_eq([String(e.get("origin_area")), String(e.get("origin_spawn"))], ["moonveil_manor", "manor_ballroom"], "returns to the ballroom candles")
	assert_true(e.global_position.distance_to(ManorLayout.ECHO_ENTRY) < 0.01)
	assert_true(bool(m.call("is_safe_zone", e.global_position)), "beside the rest candles (safe)")
	var sp: Vector3 = (m.get_spawn("manor_ballroom") as Transform3D).origin
	assert_true(Vector2(sp.x - e.global_position.x, sp.z - e.global_position.z).length() < 5.0, "near the ballroom checkpoint")
	assert_eq(String(e.get_interaction(null)["text"]), "Echo Trial: The Last Waltz (a remembered challenge)")


func test_the_works_places_the_stone_at_the_bell_throat_after_the_choir() -> void:
	var w: Node3D = load(WORKS).new()
	add_child(w)
	nodes.append(w)
	await wait_physics(3)
	if w.get_node_or_null("WorksDeep") == null:
		print("  SKIP: the Works area does not build rooms 9-14 here")
		return
	assert_null(w.get("echo_entry"), "no stone before the Choir is beaten")
	GameState.set_flag("ch2_choir_defeated", true)
	var e: Node3D = w.get("echo_entry")
	assert_not_null(e, "the stone appears the moment the Choir is beaten (live)")
	if e == null:
		return
	assert_eq(String(e.get("trial_id")), "choir")
	assert_eq([String(e.get("origin_area")), String(e.get("origin_spawn"))], ["hushed_works", "bell_throat"], "returns to the Bell Throat")
	var p := e.global_position
	var want: Vector3 = TrialsData.trial("choir")["entry"]["pos"]
	assert_true(p.distance_to(want) < 0.01, "at the table's position")
	assert_eq(String(w.call("room_at", p + Vector3.UP * 0.5)), "hw_throat", "inside the Bell Throat")
	assert_true(bool(w.call("is_safe_zone", p)), "the Bell Throat is safe")
	var cp: Vector3 = VaultLayout.CHECKPOINTS["hw_bell_throat"]["pos"]
	assert_true(p.distance_to(cp) <= 4.0, "beside the Bell Throat checkpoint (%.1f m)" % p.distance_to(cp))
	var space := w.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 1.0, 1))
	assert_false(hit.is_empty(), "stands on the floor")
	if not hit.is_empty():
		assert_almost(float(hit["position"].y), p.y, 0.05)
	assert_eq(e.find_children("*", "StaticBody3D", true, false).size(), 0, "it blocks nobody")
	# Clear of the other stations (the probe never has to choose) and of the walking line stair -> vault stair.
	var near_checked := 0
	for n in w.find_children("*", "", true, false):
		if n == e or not (n is Node3D) or not n.is_in_group("interactable") or e.is_ancestor_of(n):
			continue
		var d := Vector2((n as Node3D).global_position.x - p.x, (n as Node3D).global_position.z - p.z).length()
		if absf((n as Node3D).global_position.y - p.y) < 3.0:
			assert_true(d >= 1.5, "%s is %.2f m away" % [n.name, d])
			if d < 8.0:
				near_checked += 1
	assert_true(near_checked >= 2, "the Bell Throat stations nearby were checked (%d)" % near_checked)
	var a2 := Vector2(152.0, 33.5)
	var b2 := Vector2(157.0, 44.0)
	var q := Vector2(p.x, p.z)
	var tt := clampf((q - a2).dot(b2 - a2) / (b2 - a2).length_squared(), 0.0, 1.0)
	assert_true(q.distance_to(a2 + (b2 - a2) * tt) >= 1.5, "off the walking line to the vault stair")
	assert_eq(String(e.get_interaction(null)["text"]), "Echo Trial: The Borrowed Song (a remembered challenge)")
	# A second build of the won save places it on load.
	var w2: Node3D = load(WORKS).new()
	add_child(w2)
	nodes.append(w2)
	await wait_physics(2)
	assert_not_null(w2.get("echo_entry"), "placed on load")
