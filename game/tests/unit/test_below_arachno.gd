extends "res://tests/test_case.gd"
## The Below with arachnophobia mode: no web meshes, no web shader anywhere, pale roots instead;
## switching the setting at runtime swaps the variants; authored shapes use the "shade" variant.

const WORLD := "res://src/world/below/below_world.gd"
const WEB_SHADER := "res://shaders/below_web.gdshader"

var area: Node3D = null
var _saved: bool = false


func before_each() -> void:
	fresh_state()
	_saved = bool(Settings.get_value("arachnophobia"))


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	Settings.set_value("arachnophobia", _saved)
	await wait_frames(2)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(2)
	return a


func _count(group: String) -> int:
	var n := 0
	for node in area.get_tree().get_nodes_in_group(group):
		if area.is_ancestor_of(node) and not node.is_queued_for_deletion():
			n += 1
	return n


func _web_shader_users() -> int:
	var n := 0
	for gi in area.find_children("*", "GeometryInstance3D", true, false):
		if (gi as Node).is_queued_for_deletion():
			continue
		var m: Material = (gi as GeometryInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path == WEB_SHADER:
			n += 1
	return n


func test_normal_mode_has_webs() -> void:
	Settings.set_value("arachnophobia", false)
	area = await _make_area()
	assert_true(_count("below_web") > 40, "webs present (%d)" % _count("below_web"))
	assert_eq(_count("below_root"), 0, "no root variant")
	assert_true(_web_shader_users() > 20, "web shader used")


func test_arachnophobia_builds_no_web_meshes() -> void:
	Settings.set_value("arachnophobia", true)
	area = await _make_area()
	assert_eq(_count("below_web"), 0, "no web-variant nodes")
	assert_eq(_web_shader_users(), 0, "no web shader anywhere")
	assert_true(_count("below_root") > 20, "pale roots instead (%d)" % _count("below_root"))


func test_runtime_swap() -> void:
	Settings.set_value("arachnophobia", false)
	area = await _make_area()
	assert_true(_count("below_web") > 0, "webs first")
	Settings.set_value("arachnophobia", true)
	await wait_frames(3)
	assert_eq(_count("below_web"), 0, "webs gone after switching on")
	assert_eq(_web_shader_users(), 0, "no web shader after switching on")
	assert_true(_count("below_root") > 0, "roots after switching on")
	Settings.set_value("arachnophobia", false)
	await wait_frames(3)
	assert_true(_count("below_web") > 0, "webs back after switching off")
	assert_eq(_count("below_root"), 0, "roots gone after switching off")


func test_authored_shapes_respect_arachnophobia() -> void:
	Settings.set_value("arachnophobia", true)
	area = await _make_area()
	area.moments.fire_crossing()
	var shape: Node = area.find_child("CrossingShape", true, false)
	assert_not_null(shape, "shape spawned")
	assert_eq(String(shape.variant), "shade", "non-arachnid shade")
	area.moments.start_silk_intro()
	assert_eq(String(area.moments.silk_shape.variant), "shade", "silk intro uses the shade too")
	assert_eq(String(area.lift_chamber.get_interaction(null)["text"]), "The winch is choked with pale roots", "lift wording")
