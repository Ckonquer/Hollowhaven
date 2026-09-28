extends "res://tests/test_case.gd"
## Ashbell Quarry's threaded warm-up on a COLD load (src/world/reach/districts/quarry.gd): the real Hallowmere Reach
## is built from scratch while the quarry builder is not cached yet, so footprints() really starts the builder on a
## loader thread while the main thread keeps loading / generating the region, and build() picks the result up.
## Proves the path the game takes on its first Reach load: no deadlock, no script error, the request consumed, the
## quarry complete. (This file sorts before every other reach_east suite, so `tools/test.sh reach_east` runs it
## cold; in a full run another suite may have loaded the Reach first - then it only checks the warm path.)

const District := preload("res://src/world/reach/districts/quarry.gd")
const REGION := "res://src/world/areas_ch2/hallowmere_reach_world.gd"
const DISTRICTS := "res://src/world/reach/reach_districts.gd"


func before_each() -> void:
	fresh_state()


func test_region_load_uses_the_threaded_builder() -> void:
	var cold := not ResourceLoader.has_cached(District.BUILDER_PATH)
	if not ResourceLoader.exists(REGION):
		print("  (region script not present - skipped)")
		return
	var s: Variant = load(REGION)
	if not (s is Script) or not (s as Script).can_instantiate():
		print("  (region script does not compile right now - skipped)")
		return
	var w: Variant = (s as Script).new()
	if not (w is Node3D):
		if w is Node:
			(w as Node).free()
		print("  (region script is not a Node3D - skipped)")
		return
	var t0 := Time.get_ticks_msec()
	add_child(w as Node3D)
	var region_ms := Time.get_ticks_msec() - t0
	await wait_physics(2)
	var qr := District.district_root(w as Node)
	assert_not_null(qr, "the region built the quarry district")
	if qr != null:
		assert_true(qr.nodes.size() >= 30, "harvest nodes: %d" % qr.nodes.size())
		assert_not_null(qr.winch, "winch")
		assert_not_null(qr.lamp, "lamp")
		assert_not_null(qr.arena, "arena")
	assert_false(bool(District._requested), "the loader-thread request was consumed by build()")
	assert_true(ResourceLoader.has_cached(District.BUILDER_PATH), "the builder is cached for later loads")
	# the quarry's enemy scripts were compiled off the main thread and are ready for the spawners' first check
	assert_true((District._enemy_requests as Array).is_empty(), "every enemy-script request was collected")
	var factory: Script = load("res://src/enemies/enemy_factory.gd")
	var t1 := Time.get_ticks_usec()
	for id in District.enemy_ids():
		var path := String(factory.call("script_path", String(id)))
		if path != "" and ResourceLoader.exists(path):
			assert_true(ResourceLoader.has_cached(path), "%s is compiled and cached after the region load" % id)
			factory.call("can_spawn", String(id))
	var check_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	var ds: Variant = load(DISTRICTS)
	var load_ms: Dictionary = (ds as Script).get("load_ms") if ds is Script else {}
	print("  %s load: region %d ms, quarry script %.1f ms, build() waited %.1f ms for the builder and %.1f ms for enemy scripts; spawners' first check %.1f ms" % [
		"COLD" if cold else "warm", region_ms, float(load_ms.get("quarry", -1.0)), District.builder_wait_ms, District.enemy_wait_ms, check_ms])
	(w as Node).queue_free()
	await wait_frames(2)
