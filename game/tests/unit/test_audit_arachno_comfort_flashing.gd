extends "res://tests/test_case.gd"
## AUDIT (arachnophobia & comfort): "Reduce flashing" must calm every flash / pulse source.
## The director's "lantern_flicker" event (min_intensity 0, so it also fires on Gentle) prefers
## flicker_light nodes (below_lamp.gd) over its own gentle dip. Fixed: below_lamp applies the setting
## itself - with reduce_flashing on, flicker() is one slow dip to ~55 % (no strobe, no jumps, even if
## re-triggered or switched on mid-flicker); with it off the lamp still stutters as before.

const Runner := preload("res://src/horror/event_runner.gd")
const Lamp := preload("res://src/world/below/below_lamp.gd")
const HorrorData := preload("res://data/horror_events.gd")
const WORLD := "res://src/world/below/below_world.gd"
const Layout := preload("res://src/world/below/below_layout.gd")

const BASE := 2.0

var root: Node3D = null
var _saved_flash: bool = false


func before_each() -> void:
	fresh_state()
	_saved_flash = bool(Settings.get_value("reduce_flashing"))
	root = Node3D.new()
	root.name = "AuditFlashRoot"
	add_child(root)


func after_each() -> void:
	Settings.set_value("reduce_flashing", _saved_flash)
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	await wait_frames(2)


func _decision() -> Dictionary:
	var ev: Dictionary = HorrorData.EVENTS["lantern_flicker"].duplicate(true)
	return {"event_id": "lantern_flicker", "event": ev, "kind": String(ev["kind"]), "anchor": {}, "count": 1, "major": false}


## Steps the lamp by hand for `seconds` at 60 Hz. Returns {min, dips} where dips counts separate
## drops below half the base energy.
func _sample(lamp: Node3D, seconds: float) -> Dictionary:
	var light: OmniLight3D = lamp.get("light")
	var steps := int(seconds * 60.0)
	var lo := INF
	var dips := 0
	var below := false
	for i in steps:
		lamp.call("_process", 1.0 / 60.0)
		var e := light.light_energy
		lo = minf(lo, e)
		var now_below := e < BASE * 0.5
		if now_below and not below:
			dips += 1
		below = now_below
	return {"min": lo, "dips": dips}


func test_lamp_flicker_is_calm_with_reduce_flashing() -> void:
	Settings.set_value("reduce_flashing", true)
	var lamp: Node3D = Lamp.new()
	lamp.setup({"style": "none", "energy": BASE, "range": 7.0, "idle": 0.0})
	root.add_child(lamp)
	lamp.set_process(false)
	var player := Node3D.new()
	root.add_child(player)
	player.position = Vector3(2.0, 0.0, 0.0)
	var r: Node = Runner.new()
	root.add_child(r)
	r.setup({"seed": 5})
	var env := {"player": player, "area": root, "companion_node": null, "intensity": 0,
		"arachnophobia": false, "reduce_flashing": true}
	var res: Dictionary = r.execute(_decision(), env)
	assert_true(bool(res["ok"]), String(res["note"]))
	assert_true(String(res["note"]).begins_with("flicker_light"), "the lamp's own stutter is used: " + String(res["note"]))
	var s := _sample(lamp, 2.0)
	# A gentle dip (what the runner itself does for plain lights) never goes below ~55 % and dips once.
	assert_true(float(s["min"]) >= BASE * 0.4, "reduce_flashing: lamp light drops to %.0f%% of its energy" % (float(s["min"]) / BASE * 100.0))
	assert_true(int(s["dips"]) <= 1, "reduce_flashing: lamp strobes %d times in 2 s (expected at most one slow dip)" % int(s["dips"]))


## The real Below: in the Old Mine and the Ruins the flicker event always finds below_lamp nodes in
## range, so the runner's gentle (reduce_flashing) dip is never used there. Measures the lamps
## themselves (implementation-neutral): with reduce_flashing ON no nearby lamp may drop below 40 %
## of its lit energy or dip more than once.
func test_real_below_flicker_respects_reduce_flashing() -> void:
	Settings.set_value("reduce_flashing", true)
	var area: Node3D = load(WORLD).new()
	root.add_child(area)
	await wait_physics(2)
	var player := Node3D.new()
	area.add_child(player)
	var r: Node = Runner.new()
	area.add_child(r)
	r.setup({"seed": 9})
	for sp in ["cp_office", "cp_shrine"]:
		player.global_position = Layout.spawn_xform(sp).origin
		var env := {"player": player, "area": area, "companion_node": null, "intensity": 0,
			"arachnophobia": false, "reduce_flashing": true}
		var res: Dictionary = r.execute(_decision(), env)
		assert_true(bool(res["ok"]), sp + ": " + String(res["note"]))
		var checked := 0
		for n in area.get_tree().get_nodes_in_group("flicker_light"):
			if not (n is Node3D) or (n as Node3D).global_position.distance_to(player.global_position) > 16.0:
				continue
			var light: OmniLight3D = n.get("light")
			var lit: float = float(n.get("energy")) * float(n.get("dim_mult"))
			if light == null or lit < 0.05:
				continue
			(n as Node).set_process(false)
			var lo := INF
			var dips := 0
			var below := false
			for i in 132:
				n.call("_process", 1.0 / 60.0)
				lo = minf(lo, light.light_energy / lit)
				var now_below := light.light_energy < lit * 0.5
				if now_below and not below:
					dips += 1
				below = now_below
			(n as Node).set_process(true)
			checked += 1
			assert_true(lo >= 0.4 and dips <= 1,
				"%s reduce_flashing ON: lamp '%s' drops to %.0f%% and dips %d times (%s)" % [sp, (n as Node).name, lo * 100.0, dips, String(res["note"])])
		assert_true(checked > 0, sp + ": no lit lamp near the checkpoint")
		r.cancel_all("next")


func _lamp() -> Node3D:
	var lamp: Node3D = Lamp.new()
	lamp.setup({"style": "none", "energy": BASE, "range": 7.0, "idle": 0.0})
	root.add_child(lamp)
	lamp.set_process(false)
	return lamp


## With the option off the horror stutter is unchanged, and the lamp recovers fully afterwards.
func test_lamp_still_stutters_without_reduce_flashing() -> void:
	Settings.set_value("reduce_flashing", false)
	var lamp := _lamp()
	lamp.call("flicker", 1.5)
	var s := _sample(lamp, 1.5)
	assert_true(float(s["min"]) < BASE * 0.2, "stutter still dims hard (min %.2f)" % float(s["min"]))
	assert_true(int(s["dips"]) >= 3, "stutter still flickers (%d dips)" % int(s["dips"]))
	_sample(lamp, 0.2)
	assert_false(bool(lamp.call("is_flickering")), "flicker over")
	assert_almost((lamp.get("light") as OmniLight3D).light_energy, BASE, 0.0001, "light fully restored")


## The gentle dip never jumps: re-triggering during the recovery, or turning the option on
## mid-stutter, leads to one smooth dip that ends at full brightness.
func test_gentle_dip_is_smooth_when_retriggered_or_switched_on() -> void:
	Settings.set_value("reduce_flashing", true)
	var lamp := _lamp()
	var light: OmniLight3D = lamp.get("light")
	lamp.call("flicker", 1.5)
	_sample(lamp, 1.0)                     # 0.5 s left: easing back up
	lamp.call("flicker", 2.0)              # the director fires again
	var prev := light.light_energy
	var jump := 0.0
	var lo := INF
	for i in 150:
		lamp.call("_process", 1.0 / 60.0)
		jump = maxf(jump, absf(light.light_energy - prev))
		prev = light.light_energy
		lo = minf(lo, light.light_energy)
	assert_true(jump <= BASE * 0.05, "re-triggered gentle dip jumps by %.0f%% in one frame" % (jump / BASE * 100.0))
	assert_true(lo >= BASE * 0.54, "gentle dip stays at 55%% or brighter (%.0f%%)" % (lo / BASE * 100.0))
	assert_almost(light.light_energy, BASE, 0.0001, "restored after the re-triggered dip")
	# Option switched on while the lamp is already stuttering: no more strobing from then on.
	Settings.set_value("reduce_flashing", false)
	lamp.call("flicker", 2.0)
	_sample(lamp, 0.4)
	Settings.set_value("reduce_flashing", true)
	lamp.call("_process", 1.0 / 60.0)
	var s := _sample(lamp, 2.0)
	assert_true(float(s["min"]) >= BASE * 0.54 and int(s["dips"]) == 0,
		"switched on mid-flicker: min %.0f%%, %d dips" % [float(s["min"]) / BASE * 100.0, int(s["dips"])])
	assert_almost(light.light_energy, BASE, 0.0001, "restored")
