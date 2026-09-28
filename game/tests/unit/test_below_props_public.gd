extends "res://tests/test_case.gd"
## R75 (integration): below_props.gd offers public tint() / torus_mesh() wrappers for other prop modules
## (annex_props.gd) instead of them calling its private helpers. Same objects, no behaviour change.

const BelowProps := preload("res://src/world/below/below_props.gd")


func test_public_wrappers_return_the_shared_resources() -> void:
	var t: Mesh = BelowProps.torus_mesh()
	assert_not_null(t, "torus mesh")
	assert_true(t is TorusMesh, "a torus")
	assert_true(t == BelowProps._torus_mesh(), "the same cached torus the Below uses")
	assert_true(t == BelowProps.torus_mesh(), "cached: one shared mesh")
	var m: Material = BelowProps.tint()
	assert_not_null(m, "tint material")
	assert_true(m is ShaderMaterial or m is BaseMaterial3D, "a real material (%s)" % m.get_class())


func test_annex_props_no_longer_reaches_into_private_helpers() -> void:
	var f := FileAccess.open("res://src/world/annex/annex_props.gd", FileAccess.READ)
	assert_not_null(f, "annex_props.gd readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_false(src.contains("BelowProps._"), "annex_props uses BelowProps' public API only")
	assert_true(src.contains("BelowProps.tint()") and src.contains("BelowProps.torus_mesh()"), "uses the wrappers")
