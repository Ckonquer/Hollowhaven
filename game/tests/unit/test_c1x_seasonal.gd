extends "res://tests/test_case.gd"
## Module B7: seasonal decor appears only while Settings "seasonal_decor" is on (built lazily, toggled live) and
## never inside the Haven build area (legacy circle + any Chapter Two extra region, with a margin).

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")
const Seasonal := preload("res://src/world/surface/c1x/seasonal_decor.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const Layout := preload("res://data/world_layout.gd")

var _area: Node3D = null
var _saved: Variant = false


func before_each() -> void:
	_saved = Settings.get_value("seasonal_decor")
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)


func after_each() -> void:
	Settings.set_value("seasonal_decor", bool(_saved))
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	await wait_frames(2)


func test_off_by_default_and_toggles_live() -> void:
	assert_false(bool(Settings.DEFAULTS["seasonal_decor"]), "the setting is off by default")
	Settings.set_value("seasonal_decor", false)
	Seasonal.build(_area)
	var d: Node3D = get_tree().get_first_node_in_group("c1x_seasonal_decor")
	assert_not_null(d, "decor node exists")
	assert_false(bool(d.get("built")), "nothing is built while the setting is off")
	assert_false(d.visible, "hidden")
	assert_eq(d.get_child_count(), 0, "no pieces")
	Settings.set_value("seasonal_decor", true)
	assert_true(bool(d.get("built")), "built when switched on")
	assert_true(d.visible, "shown")
	var placed: Array = d.piece_positions()
	assert_eq(placed.size(), L.SEASONAL_PUMPKINS.size() + L.SEASONAL_RIBBONS.size(), "every piece placed (no extra build regions yet)")
	var children := d.get_child_count()
	Settings.set_value("seasonal_decor", false)
	assert_false(d.visible, "hidden when switched off")
	Settings.set_value("seasonal_decor", true)
	assert_eq(d.get_child_count(), children, "switching back on never builds a second copy")


func test_never_in_the_build_area() -> void:
	Settings.set_value("seasonal_decor", true)
	Seasonal.build(_area)
	var d: Node3D = get_tree().get_first_node_in_group("c1x_seasonal_decor")
	for p in d.piece_positions():
		var pv: Vector2 = p
		assert_false(Common.in_build_area(pv, L.SEASONAL_BUILD_MARGIN), "%s is outside the build area" % pv)
		assert_true(pv.distance_to(Layout.HAVEN_CENTER) > Layout.HAVEN_RADIUS, "%s is outside the Haven" % pv)
	# The runtime guard: a Chapter Two extra build region over a piece removes that piece.
	assert_true(Common.in_build_area(Vector2(3, 3)), "the Haven lawn is build area")
	assert_false(Common.in_build_area(L.SEASONAL_PUMPKINS[0][0]), "a path pumpkin is not")
	# Pumpkins share one MultiMesh (a few draw calls, no per-piece meshes).
	var mm := d.get_node_or_null("Pumpkins") as MultiMeshInstance3D
	assert_not_null(mm, "pumpkins are one MultiMesh")
	if mm != null:
		var n := 0
		for e in L.SEASONAL_PUMPKINS:
			n += clampi(int(e[2]), 1, 3)
		assert_eq(mm.multimesh.instance_count, n, "every pumpkin instance")
