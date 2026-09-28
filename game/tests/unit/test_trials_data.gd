extends "res://tests/test_case.gd"
## The Echo Trial table (data/trials.gd, module D1): every trial is complete and consistent with the catalogue - a
## real boss id, the won story fight that offers it, an origin checkpoint the origin area really registers, a
## first-clear content bundle that sets only its own pattern-unlock flag (never a story flag, never an item that is a
## key / quest item), bounded modest renewable repeat rewards, a unique pattern per trial (no other reward or recipe
## pays it), arachnophobia-safe wording. The Matron entry is unchanged, and the area reads this table.

const TrialsData := preload("res://data/trials.gd")
const EchoTrial := preload("res://src/world/areas_ch2/echo_trial.gd")
const SourcesData := preload("res://data/sources.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")

## The origin spawns of spec §1 (each origin area registers them in _ready()).
const ORIGIN_SPAWNS := {"below": ["cp_arena"], "moonveil_manor": ["manor_ballroom"], "hushed_works": ["bell_throat"]}


func before_each() -> void:
	fresh_state()


func test_every_trial_is_complete() -> void:
	assert_eq(TrialsData.ids(), ["matron", "velour", "choir"], "three remembered challenges (MP §15)")
	assert_eq(EchoTrial.TRIALS, TrialsData.TRIALS, "the area reads the data table")
	for id in TrialsData.ids():
		var t := TrialsData.trial(id)
		for k in ["title", "alt_title", "subtitle", "boss", "requires_flag", "first_reward", "first_message", "pattern",
				"pattern_name", "repeat", "bonus_every", "bonus", "origin", "origin_name", "builder", "memory", "intro", "fade",
				"exit_text", "ambience"]:
			assert_true(t.has(k), "%s has %s" % [id, k])
		assert_true(String(t.get("origin_name", "")).begins_with("the "), "%s: the origin in words for the gift toast" % id)
		assert_eq(EchoTrial.origin_name(id), String(t.get("origin_name", "")))
		assert_true(Factory.can_spawn(String(t["boss"])), "%s: the real boss %s can be spawned" % [id, t["boss"]])
		assert_false(ItemDB.enemy(String(t["boss"])).is_empty(), "%s: boss in data/enemies.gd" % id)
		var origin: Dictionary = t["origin"]
		assert_true(Game.AREAS.has(String(origin["area"])), "%s origin area %s is a real area" % [id, origin["area"]])
		assert_false(Game.TRANSIENT_AREAS.has(String(origin["area"])), "%s never returns into a trial" % id)
		assert_true((ORIGIN_SPAWNS.get(String(origin["area"]), []) as Array).has(String(origin["spawn"])), "%s origin spawn %s (spec §1)" % [id, origin["spawn"]])
		var b := String(t["builder"])
		if id == "matron":
			assert_eq(b, "", "the Matron keeps her own room inside echo_trial.gd")
		else:
			assert_true(ResourceLoader.exists(b), "%s builder %s exists" % [id, b])
			assert_true((load(b) as Script).can_instantiate(), "%s builder compiles" % id)
		assert_true(String(t["memory"]).contains("memory, not undone history"), "%s: the menu explains it is a memory" % id)
		assert_eq(String(t["subtitle"]), "a remembered challenge")
		var amb := String(t["ambience"])
		assert_true(amb == "" or Audio.has_sound(amb), "%s ambience %s is an existing loop" % [id, amb])


func test_the_matron_entry_is_exactly_as_before() -> void:
	var m := TrialsData.trial("matron")
	assert_eq(String(m["title"]), "Echo Trial: The Thread Above")
	assert_eq(String(m["alt_title"]), "Echo Trial: The Hollow Above")
	assert_eq(String(m["first_reward"]), "rw_trial_matron_first")
	assert_eq(m["repeat"], {"silk": 3, "glowcap": 2})
	assert_eq(int(m["bonus_every"]), 3)
	assert_eq(m["bonus"], {"echo_shard": 1})
	assert_eq(m["origin"], {"area": "below", "spawn": "cp_arena"})
	assert_eq(String(m["requires_flag"]), "weaver_defeated")


func test_first_clear_bundles_are_content_bundles_with_only_their_pattern_flag() -> void:
	var seen_flags := {}
	for id in TrialsData.ids():
		var t := TrialsData.trial(id)
		var rid := String(t["first_reward"])
		assert_true(rid.begins_with("rw_trial_"), rid + " is a trial reward id")
		assert_true(TrialsData.FIRST_REWARDS.has(rid), rid + " is defined in data/trials.gd")
		var own: Dictionary = TrialsData.FIRST_REWARDS[rid]
		assert_eq(String(own["by"]), "content", rid + " is granted by this module")
		assert_true(String(own["who"]) != "", rid + " says who grants it")
		assert_eq((own["items"] as Dictionary).size(), 0, rid + ": a pattern, not loot")
		assert_eq((own["flags"] as Array).size(), 1, rid + ": exactly one flag")
		var f := String((own["flags"] as Array)[0])
		assert_eq(f, "ch2_trial_" + id, rid + " sets only its own pattern-unlock flag")
		assert_false(TrialsData.TRIALS.values().any(func(x: Dictionary) -> bool: return String(x["requires_flag"]) == f), "never a story flag")
		assert_false(seen_flags.has(f), "one flag per trial")
		seen_flags[f] = true
		# data/sources.gd REWARDS mirrors every bundle exactly (the catalogue copy is what the area reads).
		assert_true(SourcesData.REWARDS.has(rid), rid + " is catalogued in data/sources.gd")
		if SourcesData.REWARDS.has(rid):
			var m: Dictionary = SourcesData.REWARDS[rid]
			assert_eq(m["items"], own["items"], rid + " mirror items")
			assert_eq(m["flags"], own["flags"], rid + " mirror flags")
			assert_eq(String(m["by"]), "content", rid + " mirror is a content bundle")
		assert_eq(EchoTrial.first_bundle(id)["flags"], own["flags"], id + ": the area pays this bundle")


func test_each_first_clear_pattern_is_unique_to_its_trial() -> void:
	var pats := {}
	for id in TrialsData.ids():
		var t := TrialsData.trial(id)
		var pid := String(t["pattern"])
		assert_true(pid.begins_with("pat_"), id + " names a pattern id")
		assert_false(pats.has(pid), "one unique pattern per trial")
		pats[pid] = true
		assert_true(String(t["first_message"]).contains(String(t["pattern_name"])), id + ": the message names the pattern")
		var p: Dictionary = ItemDB.pattern(pid)
		assert_false(p.is_empty(), "%s: pattern %s is in data/appearance.gd" % [id, pid])
		if p.is_empty():
			continue
		assert_eq(String(p.get("name", "")), String(t["pattern_name"]), pid + ": the table names it as the catalogue does")
		assert_eq(String(p.get("flag", "")), "ch2_trial_" + id, pid + " is unlocked by this trial's flag only")
		# the only pattern that flag unlocks, and no other pattern shares its parts
		for other in TrialsData.ids():
			if other == id:
				continue
			var op: Dictionary = ItemDB.pattern(String(TrialsData.trial(other)["pattern"]))
			assert_ne(String(op.get("flag", "")), "ch2_trial_" + id, "%s's flag unlocks only %s" % [id, pid])
			for part in p.get("parts", []):
				assert_false((op.get("parts", []) as Array).has(part), "%s part %s is unique to it" % [pid, part])
		# its Loom recipe is gated by the same flag
		var rec_id := String(p.get("recipe", ""))
		assert_true(rec_id != "" and ItemDB.every_recipe_id().has(rec_id), pid + " has a Loom recipe")
		if rec_id != "" and ItemDB.every_recipe_id().has(rec_id):
			assert_eq(String(ItemDB.recipe(rec_id).get("unlock", "")), "ch2_trial_" + id, rec_id + " is unlocked by the trial")
		# no other reward bundle grants it directly
		for rid in ItemDB.all_reward_ids():
			if String(rid) == String(t["first_reward"]):
				continue
			assert_false((ItemDB.reward_bundle(String(rid)).get("patterns", []) as Array).has(pid), "%s never granted by %s" % [pid, rid])
	assert_eq(String(ItemDB.pattern("pat_moon_moth").get("flag", "")), "ch2_trial_matron", "the Matron's Moon Moth Shawl")


func test_repeat_rewards_are_modest_renewable_and_bounded() -> void:
	for id in TrialsData.ids():
		var t := TrialsData.trial(id)
		assert_true(int(t["bonus_every"]) >= 2, id + ": a bonus is occasional")
		for set_name in ["repeat", "bonus"]:
			for item in t[set_name]:
				assert_true(ItemDB.has_item(String(item)), "%s %s item %s exists" % [id, set_name, item])
				assert_false(ItemDB.is_quest_item(String(item)), "%s: %s is never a key item" % [id, item])
				assert_ne(String(item), "heartseed", "never a Heartseed")
				var renewable := false
				for s in ItemDB.sources(String(item)):
					renewable = renewable or bool((s as Dictionary).get("renewable", false)) or String((s as Dictionary).get("kind", "")) == "recipe"
				assert_true(renewable, "%s: %s has a renewable source (modest renewable resources)" % [id, item])
		for clears in range(1, 25):
			var give := TrialsData.repeat_items(id, clears)
			var n := 0
			for k in give:
				n += int(give[k])
			assert_true(n > 0 and n <= TrialsData.MAX_REPEAT_PER_CLEAR, "%s clear %d pays %d items (bounded)" % [id, clears, n])
		assert_eq(TrialsData.repeat_items(id, 3).size(), (t["repeat"] as Dictionary).size() + (t["bonus"] as Dictionary).size(), id + ": the third clear adds the bonus")
		assert_eq(TrialsData.repeat_items(id, 4), t["repeat"], id + ": the fourth is plain again")


func test_titles_and_menu_wording_follow_arachnophobia() -> void:
	completed_save()
	for mode in [false, true]:
		Settings.set_value("arachnophobia", mode)
		for id in TrialsData.ids():
			var m := EchoTrial.menu_text(id)
			assert_true(String(m["title"]).begins_with("Echo Trial: "), id + " title")
			assert_true(String(m["title"]).ends_with("(a remembered challenge)"), id + " subtitle")
			if mode:
				for part in [String(m["title"]), String(m["body"])]:
					for w in ["spider", "web", "silk", "skitter", "arachn", "weaver"]:
						assert_false(part.to_lower().contains(w), "%s: no '%s' in arachnophobia mode: %s" % [id, w, part])
	Settings.set_value("arachnophobia", false)
	assert_eq(EchoTrial.entry_text("matron"), "Echo Trial: The Thread Above (a remembered challenge)")
	Settings.set_value("arachnophobia", true)
	assert_eq(EchoTrial.entry_text("matron"), "Echo Trial: The Hollow Above (a remembered challenge)")
	assert_eq(EchoTrial.entry_text("velour"), "Echo Trial: The Last Waltz (a remembered challenge)")
	assert_eq(EchoTrial.entry_text("choir"), "Echo Trial: The Borrowed Song (a remembered challenge)")
	Settings.set_value("arachnophobia", false)


func test_format_time() -> void:
	assert_eq(TrialsData.format_time(0.0), "--:--")
	assert_eq(TrialsData.format_time(5.4), "0:05")
	assert_eq(TrialsData.format_time(125.0), "2:05")
	assert_eq(TrialsData.format_time(3600.0), "60:00")


## The trial-scoped record and ledger (clears, best time, repeat_paid, paid) and the first-clear ledger entry go
## through a real save file and back (JSON numbers come back as floats); a clear after the load adds to the loaded
## ledger and never pays the first-clear bundle again.
func test_the_trial_ledger_survives_save_and_load() -> void:
	assert_true(SaveSystem.save_dir.begins_with("user://test_saves/"), "tests only touch user://test_saves")
	SaveSystem.delete_test_saves()
	completed_save()
	assert_true(bool(EchoTrial.record_clear("choir", 250.0)["first"]), "first clear: the content bundle")
	EchoTrial.record_clear("choir", 200.0)
	EchoTrial.record_clear("choir", 230.0)          # the third clear adds the bonus
	EchoTrial.pay_pending("hushed_works")           # the trip home pays both waiting gifts
	var rec: Dictionary = EchoTrial.record("choir").duplicate(true)
	assert_eq(int(rec["repeat_paid"]), 2)
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_eq(int(EchoTrial.record("choir")["clears"]), 0, "a fresh state has no record")
	assert_true(SaveSystem.load_game(), "loaded")
	var back := EchoTrial.record("choir")
	assert_eq(int(back["clears"]), 3, "clears survive")
	assert_almost(float(back["best_seconds"]), 200.0, 0.001, "best time survives")
	assert_almost(float(back["last_seconds"]), 230.0, 0.001)
	assert_eq(int(back["repeat_paid"]), 2, "repeat_paid survives")
	var paid: Dictionary = back["paid"]
	for k in rec["paid"]:
		assert_eq(int(paid.get(k, 0)), int(rec["paid"][k]), "paid %s survives" % k)
	assert_true(EchoTrial.first_clear_paid("choir"), "the first-clear ledger entry survives")
	assert_true(bool(GameState.get_flag("ch2_trial_choir")), "and its pattern-unlock flag")
	assert_eq(EchoTrial.record_line("choir"), "Cleared 3 times - best time 3:20")
	var ledger_n := GameState.ledger.size()
	var out := EchoTrial.record_clear("choir", 180.0)
	assert_false(bool(out["first"]), "never the first-clear bundle again after a load")
	assert_eq(GameState.ledger.size(), ledger_n)
	EchoTrial.pay_pending("hushed_works")
	var after := EchoTrial.record("choir")
	assert_eq(int(after["repeat_paid"]), 3)
	assert_eq(int((after["paid"] as Dictionary)["echo_shard"]), int(paid.get("echo_shard", 0)) + 2, "adds to the loaded ledger")
	assert_eq(EchoTrial.record_line("choir"), "Cleared 4 times - best time 3:00")
	SaveSystem.delete_test_saves()


## Lead decision L08: a repeat clear's gift waits in the trial's record ("pending", saved) until the arrival at the
## origin. A save + reload between the win and the arrival keeps it, and the arrival then pays it exactly once; the
## menu / record texts are what they were; arriving inside a trial pays nothing.
func test_a_waiting_gift_survives_save_and_load_and_is_paid_once() -> void:
	assert_true(SaveSystem.save_dir.begins_with("user://test_saves/"), "tests only touch user://test_saves")
	SaveSystem.delete_test_saves()
	completed_save()
	EchoTrial.record_clear("velour", 200.0)          # first clear: the pattern flag
	var wax := GameState.count_item("lantern_wax")
	var cloth := GameState.count_item("woven_cloth")
	var notes: Array = []
	var on_note := func(t: String, _k: String) -> void: notes.append(t)
	Events.notify.connect(on_note)
	var out := EchoTrial.record_clear("velour", 150.0)
	EchoTrial.record_clear("velour", 170.0)          # the third clear adds the bonus; the gifts merge
	assert_true(bool(out["pending"]), "a repeat clear's gift waits")
	assert_eq(out["items"], {"lantern_wax": 2, "moonpetal": 2}, "what the clear earned")
	assert_eq(GameState.count_item("lantern_wax"), wax, "nothing given yet")
	assert_eq(notes.filter(func(t: Variant) -> bool: return String(t) == "The echo's gift waits for you back at the ballroom candles.").size(), 2, "she is told where it waits")
	assert_true(EchoTrial.is_listening(), "a win wires the payer")
	var menu_before := EchoTrial.menu_text("velour")
	assert_eq(EchoTrial.record_line("velour"), "Cleared 3 times - best time 2:30", "the record text is unchanged")
	assert_true(SaveSystem.save_game(true), "saved between the win and the arrival")
	fresh_state()
	assert_eq(EchoTrial.pending_gifts(), {}, "a fresh state has nothing waiting")
	assert_true(SaveSystem.load_game(), "loaded")
	var back := EchoTrial.record("velour")
	var pend: Dictionary = back.get("pending", {})
	assert_eq(int(pend.get("lantern_wax", 0)), 4, "the waiting gift survives the save")
	assert_eq(int(pend.get("moonpetal", 0)), 4)
	assert_eq(int(pend.get("woven_cloth", 0)), 1)
	assert_eq(int(back.get("pending_clears", 0)), 2)
	assert_eq(EchoTrial.menu_text("velour"), menu_before, "the menu text is unchanged")
	notes.clear()
	assert_eq(EchoTrial.pay_pending("echo_trial"), {}, "never paid inside a trial")
	assert_eq(EchoTrial.pay_pending("moonveil_manor"), {"lantern_wax": 4, "moonpetal": 4, "woven_cloth": 1}, "paid on arrival")
	assert_eq(EchoTrial.pay_pending("moonveil_manor"), {}, "exactly once")
	assert_eq(GameState.count_item("lantern_wax"), wax + 4)
	assert_eq(GameState.count_item("woven_cloth"), cloth + 1)
	assert_eq(notes.filter(func(t: Variant) -> bool: return String(t).begins_with("The echo's gift: ")).size(), 1, "one toast")
	var rec := EchoTrial.record("velour")
	assert_false(rec.has("pending") or rec.has("pending_clears"), "nothing waits any more")
	assert_eq(int(rec["repeat_paid"]), 2)
	assert_eq(int((rec["paid"] as Dictionary)["lantern_wax"]), 4)
	assert_eq(int(rec["clears"]), 3)
	Events.notify.disconnect(on_note)
	SaveSystem.delete_test_saves()


## init() is idempotent (Game.wire_session_systems and every repeat win call it): one Events.area_loaded connection.
func test_the_gift_payer_is_wired_once() -> void:
	EchoTrial.init()
	EchoTrial.init()
	var n := 0
	for c in Events.area_loaded.get_connections():
		if (c["callable"] as Callable).get_method() == "pay_pending":
			n += 1
	assert_eq(n, 1, "one listener")
	assert_true(EchoTrial.is_listening())
	EchoTrial.shutdown()
	assert_false(EchoTrial.is_listening())
	EchoTrial.init()
	assert_true(EchoTrial.is_listening(), "wired again (as the session wiring leaves it)")


func completed_save() -> void:
	for f in ["chapter_one_complete", "weaver_defeated", "ch2_velour_defeated", "ch2_choir_defeated"]:
		GameState.set_flag(f, true)
