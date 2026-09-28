extends "res://tests/unit/test_boss_choir_harness.gd"
## QA: during the Borrowed Choir's Phase B plate sequence a "Talk to Lumi" prompt showed among the plate prompts and
## could steal the interaction focus from the plates (Lumi trots at Krystal's heels, often closer than a plate).
## While a boss fight is on (Game.boss_active()) a FOLLOWING companion offers no talk / menu interaction
## (companion.gd talk_hushed_in_fight), so the probe (interaction_probe.gd) never focuses it; outside a fight the
## same Lumi offers her talk prompt as before. The REAL vault (choir_arena.gd layout), the REAL companion.

const HP := 5000.0
const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const Probe := preload("res://src/player/interaction_probe.gd")
const CompanionScript := preload("res://src/companions/companion.gd")

## In front of the east resonator's Leaf plate (the CH2-014 QA spot).
const SPOT := Vector3(165.0, -32.0, 62.5)

var _saved_player: Node = null
var _saved_companions: Dictionary = {}


func before_each() -> void:
	super.before_each()
	_saved_player = Game.player
	_saved_companions = Game.companion_nodes
	Game.companion_nodes = {}
	Game._bosses.clear()


func after_each() -> void:
	Game._bosses.clear()
	Game.player = _saved_player if is_instance_valid(_saved_player) else null
	Game.companion_nodes = _saved_companions
	await super.after_each()


func _face(d: Node3D, at: Vector3) -> void:
	var to := at - d.global_position
	d.look_at(d.global_position + Vector3(to.x, 0.0, to.z).normalized(), Vector3.UP)


## The facings (degrees, every 15) at which the probe focuses `who`.
func _focus_sweep(probe: Node, d: Node3D, who: Node) -> Array:
	var hits: Array = []
	for k in 24:
		var ang := TAU * float(k) / 24.0
		d.look_at(d.global_position + Vector3(cos(ang), 0.0, sin(ang)), Vector3.UP)
		probe.call("refresh")
		if probe.get("focus") == who:
			hits.append(k * 15)
	return hits


func test_following_lumi_never_takes_the_plates_focus_during_the_fight() -> void:
	var arena: Node3D = ChoirArena.new()
	arena.set("save_on_clear", false)
	add_child(arena)
	var rs: Array = arena.call("resonator_nodes")
	var leaf: Node3D = (rs[1] as Node).get_node("Plate_leaf/Strike_leaf")
	var d := dummy(SPOT, false, HP)
	Game.player = d
	# Befriended Lumi following Krystal, a step behind her (processing off: she stays put for the probe).
	GameState.companion("lumi")["befriended"] = true
	GameState.set_companion_assignment("lumi", "follow")
	var to_leaf := leaf.global_position - SPOT
	var back := -Vector3(to_leaf.x, 0.0, to_leaf.z).normalized()
	var lumi: Node3D = CompanionScript.new()
	lumi.setup({"id": "lumi", "mode": "follow", "home": SPOT, "wild": SPOT + back})
	add_child(lumi)
	lumi.global_position = SPOT + back * 0.9
	lumi.set_physics_process(false)
	lumi.set_process(false)
	Game.companion_nodes["lumi"] = lumi
	var probe: Node = Probe.new()
	probe.set("player", d)
	add_child(probe)
	probe.set_physics_process(false)
	await wait_physics(3)
	assert_eq(String(lumi.get("mode")), "follow", "precondition: Lumi follows Krystal")
	# Before the fight: her talk prompt as always (normal companion interaction).
	var talk := {"text": "Talk to %s" % lumi.call("get_display_name"), "enabled": true}
	assert_false(bool(Game.boss_active()))
	assert_eq(lumi.call("get_interaction", d), talk, "outside a fight: Lumi offers her talk prompt")
	# The fight, Phase B: the plate sequence.
	Base.reset_attack_tokens()
	var b: Node = Factory.create(BOSS_ID, arena.call("boss_params"), arena.call("arena_center"))
	add_child(b)
	b.set_process(false)
	b.target_override = d
	b.intensity_override = 1
	b.fast_defeat = true
	start_in_phase(b, 2)
	assert_true(until(b, "b_gather") >= 0.0, "phase B")
	for w in b.wisp_nodes():
		(w as Node).set_physics_process(false)
	assert_true(bool(Game.boss_active()), "precondition: the fight is on")
	assert_eq(lumi.call("get_interaction", d), {}, "no talk prompt from the follower during the fight")
	_face(d, leaf.global_position)
	probe.call("refresh")
	assert_eq(probe.get("focus"), leaf, "facing the Leaf plate focuses it")
	assert_eq(String((probe.get("focus_interaction") as Dictionary).get("text", "")), "Strike the Leaf plate")
	assert_eq(_focus_sweep(probe, d, lumi), [], "phase B: no facing at this spot focuses Lumi")
	# The fight over (a quiet dismissal): her talk prompt is back.
	GameState.set_flag("ch2_choir_defeated", true)
	assert_true(bool(b.is_gone()), "dismissed")
	Events.boss_encounter_changed.emit(BOSS_ID, false)
	assert_false(bool(Game.boss_active()))
	assert_eq(lumi.call("get_interaction", d), talk, "after the fight: her talk prompt is back")
	probe.queue_free()
	b.queue_free()
	lumi.queue_free()
	arena.queue_free()
	await wait_frames(2)
