extends RefCounted
## Phase B "Stolen rhythm": drives the Choir Vault's two FIXED resonators (src/world/works/deep/resonator.gd,
## built by the arena) with the bell-symbol sequence taught on the Bellmaker's Floor (room 5: the arena passes
## data/works_layout_deep.gd bell_symbols() in taught order). Each resonator woken = one protection layer down;
## both = the Choir is exposed.
##   * the plates are struck by interaction (no pitch, no colour-only cue: each plate is a large carved symbol
##     with its name, every strike is captioned by the resonator) - fully playable with sound muted;
##   * a sequence left half-done longer than the resonator's window_seconds() (12 s) quietly restarts (caption,
##     never damage); Settings timing_assist makes that window INF - no timing at all;
##   * outside Phase B the plates are disabled during the fight (strike -> "idle"); on a reset / victory /
##     stand-down every resonator is reset and re-enabled (the arena's default state - never mismatched props).
##   var r = Resonance.new(); r.setup(resonator_nodes, ["leaf", "moon", "key", "flame"]); r.begin(); r.tick(dt)

signal layer_down(resonator_id: String, active_count: int)

const Art := preload("res://src/enemies/choir/choir_art.gd")

var resonators: Array = []
var sequence: Array = []
var running: bool = false
var window_override: float = -1.0      # tests: >= 0 replaces the resonator's window
var slips: int = 0                     # half-done sequences that timed out (tests)
var _active: Dictionary = {}           # resonator id -> true
var _elapsed: Dictionary = {}          # resonator id -> seconds since the first correct plate of this attempt


func setup(nodes: Array, seq: Array) -> void:
	resonators.clear()
	for n in nodes:
		if is_instance_valid(n) and n is Node:
			resonators.append(n)
			if n.has_signal("struck") and not (n as Node).is_connected("struck", _on_struck):
				(n as Node).connect("struck", _on_struck)
			if n.has_signal("activated") and not (n as Node).is_connected("activated", _on_activated):
				(n as Node).connect("activated", _on_activated)
	sequence = seq.duplicate()


func valid() -> bool:
	return resonators.size() >= 1


## Phase B starts (or a cycle re-forms): every resonator enabled, set to the taught order (which resets it).
func begin() -> void:
	running = true
	_active.clear()
	_elapsed.clear()
	for r in _live():
		(r as Node).set("enabled", true)
		if not sequence.is_empty() and (r as Node).has_method("set_sequence"):
			(r as Node).call("set_sequence", sequence)
		elif (r as Node).has_method("reset"):
			(r as Node).call("reset")


## Phase A / C of a live fight: plates do nothing.
func disable() -> void:
	running = false
	_active.clear()
	_elapsed.clear()
	for r in _live():
		if (r as Node).has_method("reset"):
			(r as Node).call("reset")
		(r as Node).set("enabled", false)


## Reset / victory / stand-down: back to the arena's default (reset, enabled).
func release() -> void:
	running = false
	_active.clear()
	_elapsed.clear()
	for r in _live():
		if (r as Node).has_method("reset"):
			(r as Node).call("reset")
		(r as Node).set("enabled", true)


func active_count() -> int:
	return _active.size()


func all_active() -> bool:
	var live := _live()
	return running and not live.is_empty() and _active.size() >= live.size()


func window() -> float:
	if window_override >= 0.0:
		return window_override
	for r in resonators:
		if is_instance_valid(r) and (r as Node).has_method("window_seconds"):
			return float((r as Node).call("window_seconds"))
	return INF if Art.timing_assist() else 12.0


## Runs every frame of the fight: no per-frame allocations (iterates `resonators` in place).
func tick(dt: float) -> void:
	if not running or _elapsed.is_empty():
		return
	var w := window()
	if w == INF:
		return
	for r in resonators:
		if not is_instance_valid(r):
			continue
		var id := String((r as Node).get("resonator_id"))
		if _active.has(id) or not _elapsed.has(id):
			continue
		_elapsed[id] = float(_elapsed[id]) + dt
		if float(_elapsed[id]) > w and int((r as Node).get("progress")) > 0:
			_elapsed.erase(id)
			slips += 1
			(r as Node).call("reset")
			Art.caption("[the borrowed rhythm drowns the plates out - start the sequence again]")


func _on_struck(resonator_id: String, _symbol_id: String, correct: bool) -> void:
	if not running:
		return
	if correct:
		if not _elapsed.has(resonator_id):
			_elapsed[resonator_id] = 0.0
	else:
		_elapsed.erase(resonator_id)


func _on_activated(resonator_id: String) -> void:
	if not running or _active.has(resonator_id):
		return
	_active[resonator_id] = true
	_elapsed.erase(resonator_id)
	layer_down.emit(resonator_id, _active.size())


func _live() -> Array:
	var out: Array = []
	for r in resonators:
		if is_instance_valid(r) and r is Node:
			out.append(r)
	return out
