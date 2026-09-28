extends "res://tests/test_case.gd"
## CH2-011 (QA bot S1): every pause-menu "Quit Game" logged "WARNING: N ObjectDB instances were leaked at exit".
## A headless --verbose probe (lit waygate prefetch of the Reach, then Quit Game) showed one bare RefCounted leaked
## per threaded load request still outstanding at quit: Game.prefetch_area() requests (an area scene + its warm-up
## scripts) stay requested until load_area() takes them, and quitting without travelling never collected them with
## ResourceLoader.load_threaded_get(). Fix: Game.release_prefetches() takes every outstanding request back; quit_game()
## and closing the window call it before quitting. (Other, random leaks seen in the same probe are engine-internal:
## ResourceLoader bookkeeping of collected threaded script compiles, and AudioServer playbacks in headless runs.)

const PROBE := "res://tests/fixtures/prefetch/prefetch_probe.gd"
const PROBE_B := "res://tests/fixtures/prefetch/prefetch_probe_b.gd"   # a second one (a loaded script stays cached)


## Game is an autoload: an earlier suite that built a lit waygate / the Bellhouse stair leaves its own area prefetch
## outstanding (the runner's isolation does not collect them), so every test starts from an empty prefetch set.
func before_each() -> void:
	Game.release_prefetches()
	await wait_frames(1)


func after_each() -> void:
	Game.release_prefetches()
	await wait_frames(1)


func test_release_takes_back_every_outstanding_prefetch() -> void:
	assert_false(ResourceLoader.has_cached(PROBE), "the fixture is not loaded yet")
	assert_eq(Game.prefetch_area("no_such_area", [PROBE]), 1, "one threaded request started")
	assert_true(Game.is_prefetching(PROBE))
	assert_ne(ResourceLoader.load_threaded_get_status(PROBE), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"the loader holds the request (and its bookkeeping) until someone collects it")
	assert_eq(Game.release_prefetches(), 1, "release collects it (waits for the loader thread if needed)")
	assert_false(Game.is_prefetching(PROBE), "nothing outstanding any more")
	assert_eq(ResourceLoader.load_threaded_get_status(PROBE), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"the loader forgot the request: nothing is left behind at exit")
	assert_eq(Game.release_prefetches(), 0, "idempotent")


func test_release_drops_kept_warm_up_scripts() -> void:
	assert_eq(Game.prefetch_area("no_such_area", [PROBE_B]), 1, "requested (cached: %s)" % ResourceLoader.has_cached(PROBE_B))
	var t := 0
	while ResourceLoader.load_threaded_get_status(PROBE_B) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and t < 300:
		await wait_frames(1)
		t += 1
	assert_eq(ResourceLoader.load_threaded_get_status(PROBE_B), ResourceLoader.THREAD_LOAD_LOADED, "loaded")
	Game._collect_warmups()                   # a finished warm-up is kept (compiled) until an enemy uses it
	assert_false(Game.is_prefetching(PROBE_B))
	assert_true(Game._warm_refs.has(PROBE_B), "kept while playing")
	Game.release_prefetches()
	assert_false(Game._warm_refs.has(PROBE_B), "dropped on quit")


## Both ways out of the game take the requests back before quitting (the Quit Game button and the window's close).
func test_quit_paths_release_prefetches_before_quitting() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/game.gd")
	assert_true(src != "", "game.gd source readable")
	for fn in ["func quit_game()", "func _on_close_requested()"]:
		var at := src.find(fn)
		assert_true(at >= 0, fn + " exists")
		var end := src.find("\nfunc ", at + fn.length())
		var body := src.substr(at, (end - at) if end > at else -1)
		var rel := body.find("release_prefetches()")
		var quit := body.find("get_tree().quit()")
		assert_true(rel >= 0, fn + " releases the outstanding prefetches")
		assert_true(quit > rel, fn + " releases them BEFORE quitting")
