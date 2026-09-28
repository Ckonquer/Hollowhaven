extends RefCounted
## Fixture for tests/unit/test_flow_quit_prefetch.gd (CH2-011): a script nothing else loads, so a test can request
## it through Game.prefetch_area() and check that Game.release_prefetches() takes the threaded request back.

const MARK := "prefetch_probe"
