extends "res://tests/test_case.gd"
## AUDIT VERIFY (horror): the director's stalker_pass with a lit Krystal, measured on the REAL Silk
## Hollows route (below_world.gd). Headless, manual ticks, seeded rhythm, no saves written.
## Regression for "stalker_pass recoils at once when Krystal's lantern is up": a far pass must crawl
## whatever light Krystal carries (lantern, or Lumi following), a retreat never heads toward her, and
## her lantern raised under a rattle still drives it off.
## The real-stalker tests need the stalker.gd change requested by the horror fixer (Krystal's light
## counts only in "rattle"; _away_step never picks a neighbour closer to her). FixedStalker mirrors
## exactly that change, so the requested patch is verified here as well; drop it once stalker.gd has it.

const Stalker := preload("res://src/enemies/stalker.gd")
const Combat := preload("res://src/combat/combat.gd")
const WORLD := "res://src/world/below/below_world.gd"
const DT := 0.05
const SPOTS := [Vector3(90.0, -10.0, -86.0), Vector3(105.0, -10.0, -100.0), Vector3(105.0, -10.0, -86.0), Vector3(96.0, -10.0, -85.5)]
const AMBUSH_SPOT := Vector3(103.2, -10.0, -99.0)      # below_layout STALKER_AMBUSH[0]
const SEEDS := [11, 29, 47]
const BACK_OFF_SLACK := 0.5

var _nodes: Array = []
var area: Node3D = null
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_companions: Dictionary = {}


class LitDummy extends CharacterBody3D:
	var health: Node
	var light_radius: float = 6.0          # same as player.gd
	var lantern_on: bool = true

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func is_light_active() -> bool:
		return lantern_on

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


## A plain light (Lumi's glow, a lit crystal...): group "light_source" contract.
class GlowDummy extends Node3D:
	var light_radius: float = 5.0

	func is_light_active() -> bool:
		return true


## The requested stalker.gd change, simulated: Krystal's light only counts in "rattle" (directly above
## her), and a retreat never steps to a route neighbour that is closer to her.
class FixedStalker extends "res://src/enemies/stalker.gd":
	func _repelled_by_light() -> bool:
		if _light(global_position) >= LIGHT_REPEL:
			return true
		var p := _player()
		if p != null and state == "rattle" and _light(p.global_position + Vector3.UP) >= LIGHT_REPEL:
			return true
		return false

	func _away_step(i: int, ref: Vector3) -> int:
		var best := 0
		var best_d: float = route[i].distance_to(ref)
		for s in [-1, 1]:
			var j: int = i + int(s)
			if j >= 0 and j < route.size() and segment_ok(mini(i, j)):
				var d: float = route[j].distance_to(ref)
				if d > best_d:
					best = int(s)
					best_d = d
		return best


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_companions = Game.companion_nodes
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	Game.area = _saved_area
	Game.player = _saved_player
	Game.companion_nodes = _saved_companions
	Combat.invalidate_light_cache()
	await wait_frames(2)


# --- Setup helpers -------------------------------------------------------------------------------------

func _load_world() -> void:
	area = load(WORLD).new()
	add_child(area)
	await wait_physics(3)


func _prepare(s: Node) -> void:
	s.set_process(false)
	s.intensity_override = 1
	s.los_override = 1


func _real_stalker() -> Node:
	await _load_world()
	var s: Node = area.get("stalker")
	assert_not_null(s, "stalker spawned")
	if s != null:
		_prepare(s)
	return s


func _fixed_stalker() -> Node:
	await _load_world()
	var real: Node = area.get("stalker")
	assert_not_null(real, "stalker spawned")
	if real == null:
		return null
	real.set_process(false)
	var route: Array = real.get("route")
	var amb: Array = real.get("ambush_points")
	var s := FixedStalker.new()
	s.setup({"route": route.duplicate(), "ambush_points": amb.duplicate(), "zone": "silk"})
	area.add_child(s)
	_nodes.append(s)
	_prepare(s)
	return s


func _krystal(pos: Vector3, lit: bool) -> LitDummy:
	var d := LitDummy.new()
	add_child(d)
	d.global_position = pos
	d.lantern_on = lit
	d.add_to_group("light_source")
	_nodes.append(d)
	Combat.invalidate_light_cache()
	return d


func _glow(pos: Vector3, radius: float) -> GlowDummy:
	var g := GlowDummy.new()
	g.light_radius = radius
	add_child(g)
	g.global_position = pos
	g.add_to_group("light_source")
	_nodes.append(g)
	Combat.invalidate_light_cache()
	return g


func _drop(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
	_nodes.erase(n)
	await wait_frames(1)
	Combat.invalidate_light_cache()


func _seed(s: Node, v: int) -> void:
	var r: Variant = s.get("_rng")
	if r is RandomNumberGenerator:
		(r as RandomNumberGenerator).seed = v


# --- Trace ---------------------------------------------------------------------------------------------

## Ticks the stalker until it is hidden again (or `stop_at` is entered) and returns what Krystal saw.
## back_d: distance when it first backs off (recoil / retreat); back_min_d: closest it came afterwards;
## paths: for every retreat, the distance of each point of its route to Krystal.
func _trace(s: Node, d: Node3D, stop_at: String = "") -> Dictionary:
	var seen: Array = []
	var paths: Array = []
	var cb := func(st: String) -> void:
		seen.append(st)
		if st == "retreat":
			var ds: Array = []
			for step in (s.get("_path") as Array):
				ds.append(((step as Dictionary)["pos"] as Vector3).distance_to(d.global_position))
			paths.append(ds)
	s.state_changed.connect(cb)
	var recoil_d := -1.0
	var back_d := -1.0
	var back_min_d := INF
	var min_d := INF
	var full_time := 0.0
	var t := 0.0
	var prev := String(s.state)
	while String(s.state) != "hidden" and t < 20.0:
		s.tick(DT)
		t += DT
		var st := String(s.state)
		var dist := (s as Node3D).global_position.distance_to(d.global_position)
		if st == "recoil" and prev != "recoil":
			recoil_d = dist
		if back_d < 0.0 and (st == "recoil" or st == "retreat"):
			back_d = dist
		if back_d >= 0.0 and st != "hidden":
			back_min_d = minf(back_min_d, dist)
		if st != "hidden":
			min_d = minf(min_d, dist)
			if float(s.get("_appear_scale")) >= 0.8:
				full_time += DT
		prev = st
		if stop_at != "" and st == stop_at:
			break
	s.state_changed.disconnect(cb)
	return {"seen": seen, "paths": paths, "recoil_d": recoil_d, "back_d": back_d, "back_min_d": back_min_d,
		"min_d": min_d, "full_time": full_time, "t": t}


## A retreat never heads toward Krystal: every retreat route leads away from her, and after a recoil
## it never comes closer than where it flinched. Returns the problems found ([] = fine).
func _back_off_problems(r: Dictionary) -> Array:
	var out: Array = []
	for p in (r["paths"] as Array):
		var ds := p as Array
		for k in range(1, ds.size()):
			if float(ds[k]) < float(ds[k - 1]) - 0.01:
				out.append("retreat route heads toward her %s" % str(ds))
				break
	var rd: float = float(r["recoil_d"])
	if rd >= 0.0 and float(r["back_min_d"]) < rd - BACK_OFF_SLACK:
		out.append("recoiled at %.1f m, then came to %.1f m" % [rd, float(r["back_min_d"])])
	return out


## One failure per scenario (not one per case), naming a few of the bad cases.
func _report(bad: Array, total: int, what: String) -> void:
	assert_true(bad.is_empty(), "%s: %d/%d cases wrong, e.g. %s" % [what, bad.size(), total, str(bad.slice(0, 3))])


# --- Scenarios (shared by the real stalker and the simulated fix) ----------------------------------------

## Director passes with Krystal dark (control), lantern raised, or lantern down with Lumi following.
## Every pass must crawl (not recoil from light 20+ m away), stay on screen at full size for a while
## (not a 1.9 s glimpse), back off away from her and slip back into the dark.
func _check_passes(s: Node, tag: String) -> void:
	var bad: Array = []
	var total := 0
	for spot in SPOTS:
		for mode in ["dark", "lantern", "lumi"]:
			for sd in SEEDS:
				var d := _krystal(spot as Vector3, mode == "lantern")
				var lumi: GlowDummy = null
				if mode == "lumi":
					lumi = _glow((spot as Vector3) + Vector3(-1.8, 1.0, 1.8), 5.0)     # ~2.6 m, like a follower
				s.target_override = d
				s.set("_cooldown", 0.0)
				_seed(s, int(sd))
				total += 1
				var label: String = "%s %s seed %d" % [str(spot), String(mode), int(sd)]
				if not bool(s.pass_overhead()):
					bad.append("%s: pass refused" % label)
				else:
					var r := _trace(s, d)
					var seen := r["seen"] as Array
					var problems: Array = []
					if not seen.has("pass") or seen.has("recoil"):
						problems.append("no crawl %s" % str(seen))
					if float(r["full_time"]) < 2.0:
						problems.append("full size only %.2f s" % float(r["full_time"]))
					problems.append_array(_back_off_problems(r))
					if String(s.state) != "hidden":
						problems.append("still %s" % String(s.state))
					if not problems.is_empty():
						bad.append("%s: %s" % [label, ", ".join(PackedStringArray(problems))])
				await _drop(lumi)
				await _drop(d)
	print("[verify] %s passes: %d/%d fine" % [tag, total - bad.size(), total])
	_report(bad, total, "%s: director passes play out whatever light Krystal carries" % tag)


## It emerges at a chain end that happens to be lit (a glowing crystal, a placed light): it recoils
## from its OWN light, and the retreat must not run along the chain toward Krystal.
func _check_chain_end_recoil(s: Node, tag: String) -> void:
	var bad: Array = []
	for spot in SPOTS:
		var d := _krystal(spot as Vector3, false)
		s.target_override = d
		s.set("_cooldown", 0.0)
		_seed(s, 5)
		var label: String = str(spot)
		if not bool(s.pass_overhead()):
			bad.append("%s: pass refused" % label)
		else:
			var g := _glow((s as Node3D).global_position, 3.0)
			var r := _trace(s, d)
			print("[verify] %s chain-end %s -> seen %s paths %s" % [tag, label, str(r["seen"]), str(r["paths"])])
			var problems: Array = []
			if not (r["seen"] as Array).has("recoil"):
				problems.append("no recoil %s" % str(r["seen"]))
			problems.append_array(_back_off_problems(r))
			if String(s.state) != "hidden":
				problems.append("still %s" % String(s.state))
			if not problems.is_empty():
				bad.append("%s: %s" % [label, ", ".join(PackedStringArray(problems))])
			await _drop(g)
		await _drop(d)
	_report(bad, SPOTS.size(), "%s: a recoil at a lit chain end never flees toward Krystal" % tag)


## Krystal lingering under the ambush point: a raised lantern still drives off the rattle (the
## counterplay), and in the dark the rattle turns into a lunge.
func _check_rattle(s: Node, tag: String) -> void:
	var d := _krystal(AMBUSH_SPOT, true)
	s.target_override = d
	_seed(s, 3)
	assert_true(bool(s.start_ambush()), "%s: ambush starts above Krystal" % tag)
	var r := _trace(s, d)
	var seen := r["seen"] as Array
	assert_true(seen.has("recoil"), "%s: her raised lantern makes the rattling stalker recoil (%s)" % [tag, str(seen)])
	assert_false(seen.has("lunge"), "%s: lit, it never lunges (%s)" % [tag, str(seen)])
	var problems := _back_off_problems(r)
	assert_true(problems.is_empty(), "%s: after the rattle it backs off away from her: %s" % [tag, str(problems)])
	assert_eq(String(s.state), "hidden", "%s: it slips back into the dark" % tag)
	d.lantern_on = false
	Combat.invalidate_light_cache()
	assert_true(bool(s.start_ambush()), "%s: second ambush starts" % tag)
	var r2 := _trace(s, d, "lunge")
	var seen2 := r2["seen"] as Array
	assert_true(seen2.has("lunge") and not seen2.has("recoil"), "%s: lantern down, the rattle turns into a lunge (%s)" % [tag, str(seen2)])


# --- Tests ------------------------------------------------------------------------------------------------

func test_real_route_pass_with_lantern() -> void:
	var s: Node = await _real_stalker()
	if s == null:
		return
	await _check_passes(s, "real")


func test_real_route_recoil_at_a_chain_end_never_retreats_toward_krystal() -> void:
	var s: Node = await _real_stalker()
	if s == null:
		return
	await _check_chain_end_recoil(s, "real")


func test_real_route_rattle_still_recoils_from_a_raised_lantern() -> void:
	var s: Node = await _real_stalker()
	if s == null:
		return
	await _check_rattle(s, "real")


func test_fixed_variant_crawls_with_lantern() -> void:
	var s: Node = await _fixed_stalker()
	if s == null:
		return
	await _check_passes(s, "fixed")
	await _check_chain_end_recoil(s, "fixed")
	await _check_rattle(s, "fixed")
