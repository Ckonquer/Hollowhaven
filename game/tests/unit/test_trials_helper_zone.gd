extends "res://tests/unit/test_trials_harness.gd"
## COV-003 (QA bot, trials_expeditions #1): entering any Echo Trial was recorded as a map landmark discovery
## ("echo_trial/trial"): the save gained discovered.echo_trial = ["trial"], the Wayfinding landmark record (+15 xp)
## and the following companion's new-zone bond (+3, zones + "trial"), all from inside the isolated echo.
## Fix: the arena's one "trial" zone is a HELPER zone (echo_trial.gd _add_trial_zone -> annexes.gd mark_helper_zone,
## the CH2-010 mechanism of the surface waygate's safe circle), so Game.is_landmark_zone() says no for it: Game's real
## zone poll still reports the zone, but records no discovery, pays no Wayfinding xp and the companion no bond.

const Mastery := preload("res://src/core/mastery.gd")
const CompanionScript := preload("res://src/companions/companion.gd")
const Annexes := preload("res://src/world/surface/annexes.gd")

## The arena's zone id (echo_trial.gd TRIAL_ZONE; spelled out so this suite also runs against older code).
const TRIAL_ZONE := "trial"

var _game_saved: Dictionary = {}


func before_each() -> void:
	super.before_each()
	Mastery.init()
	_game_saved = {"mode": Game.mode, "zone_id": Game.zone_id, "in_safe_zone": Game.in_safe_zone}


func after_each() -> void:
	Game.mode = String(_game_saved["mode"])
	Game.zone_id = String(_game_saved["zone_id"])
	Game.in_safe_zone = bool(_game_saved["in_safe_zone"])
	await super.after_each()


func test_entering_any_echo_trial_is_no_discovery_xp_or_companion_bond() -> void:
	completed_save()
	for id in ["matron", "velour", "choir"]:
		var a := await trial_area(id)
		assert_eq(String(a.get("trial_id")), id, "precondition: the echo hosts %s" % id)
		assert_false(bool(Game.is_landmark_zone(a, TRIAL_ZONE)), "%s: the trial zone is a helper zone" % id)
		var entry: Dictionary = {}
		for z in a.get("zones"):
			if String((z as Dictionary).get("id", "")) == TRIAL_ZONE:
				entry = z
		assert_false(entry.is_empty(), "%s: the arena still registers its trial zone" % id)
		assert_eq(entry.get(Annexes.HELPER_ZONE_KEY, true), false, "%s: marked landmark = false" % id)
		# Krystal (a stand-in) on the safe pad, Lumi following her: Game's real 0.4 s zone poll.
		var spawn: Transform3D = a.spawns["trial_start"]
		var k := dummy(a, spawn.origin)
		GameState.companion("lumi")["befriended"] = true
		GameState.set_companion_assignment("lumi", "follow")
		var lumi: Node3D = CompanionScript.new()
		lumi.setup({"id": "lumi", "mode": "follow", "home": spawn.origin + Vector3(0, 0, 3), "wild": spawn.origin + Vector3(1, 0, 1)})
		a.add_child(lumi)
		lumi.global_position = spawn.origin + Vector3(1, 0.05, 1)
		nodes.append(lumi)
		Game.companion_nodes["lumi"] = lumi
		Game.area = a
		Game.player = k
		Game.area_id = "echo_trial"
		Game.mode = "playing"
		Game.zone_id = ""
		var xp0 := Mastery.xp("wayfinding")
		var bond0 := int(GameState.companion("lumi")["bond_xp"])
		Game._process(0.5)
		assert_eq(Game.zone_id, TRIAL_ZONE, "%s: the poll still reports the trial zone" % id)
		assert_false(GameState.is_discovered("echo_trial", TRIAL_ZONE), "%s: no map discovery" % id)
		assert_eq(GameState.discovered_in("echo_trial"), [], "%s: nothing recorded for the echo" % id)
		assert_eq(Mastery.xp("wayfinding"), xp0, "%s: no Wayfinding landmark xp" % id)
		assert_false(Mastery.has_seen("wayfinding", "landmark:echo_trial/" + TRIAL_ZONE), "%s: no landmark record" % id)
		assert_eq(int(GameState.companion("lumi")["bond_xp"]), bond0, "%s: no companion new-zone bond" % id)
		var zv: Variant = GameState.companion("lumi").get("zones")
		assert_false(zv is Array and (zv as Array).has(TRIAL_ZONE), "%s: nor is the echo remembered as explored" % id)
		Game.area = null
		Game.player = null
		Game.companion_nodes = {}
		Game._bosses.clear()
		a.queue_free()
		lumi.queue_free()
		await wait_frames(2)
