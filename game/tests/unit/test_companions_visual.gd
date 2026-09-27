extends "res://tests/test_case.gd"
## Companion visuals: things that are easy to break without noticing in a screenshot.

const LumiVisual := preload("res://src/companions/lumi_visual.gd")
const MochiVisual := preload("res://src/companions/mochi_visual.gd")
const PebbleVisual := preload("res://src/companions/pebble_visual.gd")
const BaseVisual := preload("res://src/companions/companion_visual.gd")

var nodes: Array = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	await wait_frames(2)


func _fur_energy(v: Node) -> float:
	var skull: MeshInstance3D = (v.get("head") as Node3D).get_child(0)
	var m := skull.material_override as ShaderMaterial
	return float(m.get_shader_parameter("emission_energy"))


func test_lumi_dimming_reaches_the_fur_the_player_sees() -> void:
	var v: Node3D = LumiVisual.new()
	add_child(v)
	nodes.append(v)
	await wait_seconds(0.8)
	var skull: MeshInstance3D = (v.get("head") as Node3D).get_child(0)
	assert_true(skull.material_override is ShaderMaterial, "fur is a toon material")
	assert_not_null(skull.material_override.next_pass, "fur keeps its outline")
	var bright := _fur_energy(v)
	var light: OmniLight3D = v.get("light")
	var bright_light := light.light_energy
	v.set_glow(0.2)
	await wait_seconds(1.5)
	var dim := _fur_energy(v)
	assert_true(dim < bright - 0.12, "the visible fur dims too, not just the light (%.3f -> %.3f)" % [bright, dim])
	assert_true(light.light_energy < bright_light * 0.5, "the light dims")
	v.set_glow(1.0)
	await wait_seconds(1.5)
	assert_true(_fur_energy(v) > dim + 0.12, "and brightens again")


func test_two_lumis_glow_independently() -> void:
	# The lineup / title diorama can show a Lumi while the real one is in the world.
	var a: Node3D = LumiVisual.new()
	var b: Node3D = LumiVisual.new()
	add_child(a)
	add_child(b)
	nodes.append_array([a, b])
	await wait_frames(2)
	a.set_glow(0.1)
	await wait_seconds(1.5)
	assert_true(_fur_energy(a) < _fur_energy(b) - 0.12, "dimming one leaves the other glowing")


func test_every_action_and_mood_plays_on_every_creature() -> void:
	for script in [MochiVisual, PebbleVisual, LumiVisual]:
		var v: Node3D = script.new()
		add_child(v)
		nodes.append(v)
		await wait_frames(1)
		var fired: Array = []
		v.action_event.connect(func(a: String) -> void: fired.append(a))
		for a in BaseVisual.ACTIONS:
			var length: float = v.play_action(a)
			assert_true(length > 0.0, "%s has a length" % a)
			await wait_frames(2)
		v.stop_action()
		for m in BaseVisual.MOODS:
			v.set_mood(m)
			await wait_frames(1)
		v.set_mood("idle")
		assert_eq(v.play_action("not_an_action"), 0.0, "unknown actions are ignored")
		v.play_action("happy")
		await wait_seconds(1.3)
		assert_true(fired.has("happy"), "the impact moment fires (drives rewards in companion.gd)")
		assert_false(v.is_busy(), "and the action ends")
