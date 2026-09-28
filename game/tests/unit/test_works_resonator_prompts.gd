extends "res://tests/test_case.gd"
## Resonator plate prompts (src/world/works/deep/resonator.gd; integration pass 3 R3-19): a plate shows
## "Strike the <name> plate" only while its resonator is enabled. The Choir switches the plates off in its Phases A
## and C (choir_resonance.gd disable(): strike() -> "idle"); there the prompt is gone too (it promised a strike that
## did nothing), and it comes back when Phase B (begin) or a reset / stand-down (release) re-enables them.

const Resonator := preload("res://src/world/works/deep/resonator.gd")
const Resonance := preload("res://src/enemies/choir/choir_resonance.gd")
const Layout := preload("res://data/works_layout_deep.gd")

var _nodes: Array = []


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_nodes.clear()
	await wait_frames(2)


func _make(id: String) -> Node3D:
	var r: Node3D = Resonator.new()
	r.setup({"id": id, "symbols": Layout.bell_symbols()})
	add_child(r)
	_nodes.append(r)
	await wait_frames(1)
	return r


func _plate(r: Node, sid: String) -> Node:
	return r.get_node_or_null("Plate_%s/Strike_%s" % [sid, sid])


func _name_of(sid: String) -> String:
	for s in Layout.bell_symbols():
		if String(s["id"]) == sid:
			return String(s.get("name", sid.capitalize()))
	return sid.capitalize()


func test_prompt_shows_while_enabled_hides_while_disabled_and_comes_back() -> void:
	var r := await _make("t_resonator_prompts")
	var ids: Array = r.call("symbol_ids")
	assert_true(ids.size() >= 2, "a plate per taught symbol (%d)" % ids.size())
	for sid in ids:
		var it := _plate(r, String(sid))
		assert_not_null(it, "plate %s has its strike interactable" % sid)
		if it == null:
			continue
		var d: Dictionary = it.call("get_interaction", null)
		assert_eq(String(d.get("text", "")), "Strike the %s plate" % _name_of(String(sid)), "enabled: the usual prompt")
		assert_true(bool(d.get("enabled", false)), "enabled: the prompt can be used")
	r.set("enabled", false)
	for sid in ids:
		var it := _plate(r, String(sid))
		if it == null:
			continue
		assert_true((it.call("get_interaction", null) as Dictionary).is_empty(), "disabled: no prompt on the %s plate" % sid)
	# pressing interact on a hidden prompt does nothing (and strike() itself is unchanged: "idle")
	var first := String(ids[0])
	_plate(r, first).call("interact", null)
	assert_eq(int(r.get("progress")), 0, "a disabled plate is not struck")
	assert_eq(String(r.call("strike", first)), "idle", "strike() still answers idle while disabled")
	r.set("enabled", true)
	for sid in ids:
		var it := _plate(r, String(sid))
		if it == null:
			continue
		var d: Dictionary = it.call("get_interaction", null)
		assert_eq(String(d.get("text", "")), "Strike the %s plate" % _name_of(String(sid)), "re-enabled: the prompt is back")
	# and interacting strikes again (the taught order starts with the first symbol)
	_plate(r, first).call("interact", null)
	assert_eq(int(r.get("progress")), 1, "a re-enabled plate strikes")


func test_choir_phases_hide_and_restore_the_prompts() -> void:
	var a := await _make("t_resonator_a")
	var b := await _make("t_resonator_b")
	var res = Resonance.new()
	var taught: Array = a.call("symbol_ids")
	res.call("setup", [a, b], taught)
	res.call("disable")                    # Phase A / C of a live fight
	for r in [a, b]:
		for sid in (r as Node).call("symbol_ids"):
			var it := _plate(r, String(sid))
			assert_true(it != null and (it.call("get_interaction", null) as Dictionary).is_empty(), "Phase A/C: %s %s shows no prompt" % [(r as Node).name, sid])
	res.call("begin")                      # Phase B
	for r in [a, b]:
		for sid in (r as Node).call("symbol_ids"):
			var it := _plate(r, String(sid))
			assert_true(it != null and String((it.call("get_interaction", null) as Dictionary).get("text", "")).begins_with("Strike the "), "Phase B: %s %s prompts a strike" % [(r as Node).name, sid])
	res.call("disable")
	res.call("release")                    # reset / victory / stand-down: back to the default (enabled)
	for r in [a, b]:
		var sid := String(((r as Node).call("symbol_ids") as Array)[0])
		var it := _plate(r, sid)
		assert_true(it != null and not (it.call("get_interaction", null) as Dictionary).is_empty(), "after a stand-down the %s prompt is back" % (r as Node).name)
