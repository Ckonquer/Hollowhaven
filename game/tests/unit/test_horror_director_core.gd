extends "res://tests/test_case.gd"
## Unit tests for the local horror director core (src/horror/director_core.gd).
## Pure logic: no scene, deterministic seeds, simulated seconds.

const Core := preload("res://src/horror/director_core.gd")
const HorrorData := preload("res://data/horror_events.gd")

## Tuning that removes pacing noise so single rules can be tested in isolation.
const EAGER := {"start_grace": 0.0, "global_cooldown": 0.0, "decision_interval": 1.0, "decision_jitter": 0.0, "do_nothing_weight": 0.0,
	"unease_after": 0.0, "anticipation_after": 0.0, "anticipation_max": 1.0e9}


# --- helpers -------------------------------------------------------------------------------------

func _core(seed_value: int = 1, extra: Dictionary = {}) -> Core:
	var c: Core = Core.new()
	var p := {"seed": seed_value}
	p.merge(extra, true)
	c.setup(p)
	return c


func _ctx(over: Dictionary = {}) -> Dictionary:
	var c := {"zone": "mine", "in_safe_zone": false, "paused": false, "player_hp_ratio": 1.0, "sprinting": false,
		"retreating": false, "lingering_seconds": 0.0, "threats_nearby": 0, "active_director_threats": 0,
		"companion": "", "intensity": 1, "anchors": [], "time": 0.0}
	c.merge(over, true)
	return c


func _anchor(anchor_name: String, kind: String, zone: String, dist: float, visible: bool) -> Dictionary:
	return {"name": anchor_name, "kind": kind, "zone": zone, "pos": Vector3(dist, 0.0, 0.0), "dist": dist, "visible": visible}


## One event (copy of real data or custom) so a rule can be observed alone.
func _only(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = HorrorData.EVENTS[id]
	return out


func _simple_event(over: Dictionary = {}) -> Dictionary:
	var e := {"kind": "sound", "zones": ["mine"], "states": ["calm", "unease", "anticipation"], "weight": 1.0,
		"cooldown": 0.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "dir_creak", "caption": ""}
	e.merge(over, true)
	return e


## Ticks `seconds` times (1 s each) with a fixed ctx. Returns all decisions.
func _run(core: Core, seconds: int, ctx: Dictionary) -> Array:
	var out: Array = []
	for i in seconds:
		out.append(core.tick(1.0, ctx))
	return out


func _fired(decisions: Array) -> Array:
	var out: Array = []
	for d in decisions:
		if String(d["event_id"]) != "":
			out.append(d)
	return out


func _reason_for(d: Dictionary, id: String) -> String:
	for r in d["rejected"]:
		if String(r["id"]) == id:
			return String(r["reason"])
	return ""


func _all_anchors() -> Array:
	var out: Array = []
	for z in ["mine", "ruins", "silk"]:
		out.append(_anchor(z + "_sound", "sound", z, 18.0, false))
		out.append(_anchor(z + "_door", "doorway", z, 20.0, true))
		out.append(_anchor(z + "_ceiling", "ceiling", z, 5.0, false))
		out.append(_anchor(z + "_spawn", "spawn", z, 15.0, false))
	return out


## A deterministic 30-minute "playthrough" of the Below: mine -> ruins -> silk, checkpoint safe zones,
## dungeon-placed enemies now and then, moving anchors, lingering, Lumi joining after 5 minutes.
func _simulate(seed_value: int, intensity: int, seconds: int = 1800) -> Dictionary:
	var core := _core(seed_value)
	var fired: Array = []
	var decisions := 0
	var sim := {"threat_start": -1.0, "threat_until": -1.0, "dthreats": 0, "dthreats_until": -1.0}
	for i in seconds:
		var t := float(i)
		var ctx := _sim_ctx(t, sim, intensity)
		var d: Dictionary = core.tick(1.0, ctx)
		if String(d["event_id"]) != "":
			fired.append({"t": t, "id": String(d["event_id"]), "major": bool(d["major"]), "zone": String(ctx["zone"]),
				"anchor": String(d["anchor"].get("name", "")), "count": int(d["count"]), "eligible": int(d["eligible_count"])})
			if String(d["kind"]) == "spawn":
				sim["threat_start"] = t + 3.0
				sim["threat_until"] = t + 18.0
				sim["dthreats"] = int(d["count"])
				sim["dthreats_until"] = t + 40.0
		if String(d["reason"]).begins_with("cho") or String(d["reason"]) == "nothing eligible":
			decisions += 1
	return {"core": core, "fired": fired, "decisions": decisions}


func _sim_ctx(t: float, sim: Dictionary, intensity: int) -> Dictionary:
	var zone := "mine"
	if t >= 1200.0:
		zone = "silk"
	elif t >= 600.0:
		zone = "ruins"
	var seg := fmod(t, 600.0)
	var safe := seg < 30.0 or (seg > 290.0 and seg < 305.0)
	var lingering := 0.0
	var lm := fmod(t, 170.0)
	if lm > 120.0 and lm < 150.0:
		lingering = lm - 120.0
	var threats := 0
	if t >= float(sim["threat_start"]) and t < float(sim["threat_until"]):
		threats += 1
	if zone != "silk" and fmod(t + 40.0, 240.0) < 14.0:
		threats += 1
	var dthreats: int = int(sim["dthreats"]) if t < float(sim["dthreats_until"]) else 0
	var anchors: Array = []
	var specs := [["sound", 16.0], ["sound", 24.0], ["doorway", 14.0], ["doorway", 22.0], ["doorway", 30.0],
		["ceiling", 5.0], ["ceiling", 12.0], ["spawn", 8.0], ["spawn", 14.0], ["spawn", 19.0], ["floor", 6.0]]
	for i in specs.size():
		var ph := float(i) * 1.7
		var dist := maxf(1.0, float(specs[i][1]) + 5.0 * sin(t * 0.031 + ph))
		var vis := sin(t * 0.07 + ph * 2.3) > 0.2
		anchors.append(_anchor("%s_%s_%d" % [zone, specs[i][0], i], String(specs[i][0]), zone, dist, vis))
	return {"zone": zone, "in_safe_zone": safe, "paused": false, "player_hp_ratio": 1.0,
		"sprinting": fmod(t, 97.0) < 6.0, "retreating": false, "lingering_seconds": lingering,
		"threats_nearby": threats, "active_director_threats": dthreats,
		"companion": "lumi" if t > 300.0 else "", "intensity": intensity, "anchors": anchors, "time": t}


# --- state machine ------------------------------------------------------------------------------

func test_tension_builds_calm_unease_anticipation() -> void:
	# One event that can never fire at Standard: observe the state machine alone.
	var c := _core(3, {"events": {"x": _simple_event({"min_intensity": 2})}})
	var ctx := _ctx()
	assert_eq(c.get_state(), "calm")
	_run(c, 19, ctx)
	assert_eq(c.get_state(), "calm", "still calm after 19 s")
	_run(c, 1, ctx)
	assert_eq(c.get_state(), "unease", "unease after 20 s (DIRECTOR.unease_after)")
	_run(c, 24, ctx)
	assert_eq(c.get_state(), "unease", "unease at 44 s")
	_run(c, 1, ctx)
	assert_eq(c.get_state(), "anticipation", "anticipation after 45 s")


func test_lingering_builds_tension_faster_and_retreat_slower() -> void:
	var ev := {"x": _simple_event({"min_intensity": 2})}
	var c := _core(3, {"events": ev})
	var linger := _ctx({"lingering_seconds": 30.0})
	_run(c, 11, linger)
	assert_eq(c.get_state(), "calm", "11 s lingering = 19.25 tension")
	_run(c, 1, linger)
	assert_eq(c.get_state(), "unease", "12 s lingering = 21 tension")
	var r := _core(3, {"events": ev})
	_run(r, 60, _ctx({"retreating": true}))
	assert_eq(r.get_state(), "calm", "retreating for 60 s barely builds tension")
	assert_almost(float(r.tension), 15.0, 0.01, "retreat rate x0.25")


func test_tension_speed_follows_intensity() -> void:
	var ev := {"x": _simple_event({"min_intensity": 3})}
	var reach := {}
	for intensity in [0, 1, 2]:
		var c := _core(3, {"events": ev})
		var t := 0
		while c.get_state() == "calm" and t < 200:
			c.tick(1.0, _ctx({"intensity": intensity}))
			t += 1
		reach[intensity] = t
	assert_eq(int(reach[1]), 20, "Standard: unease after 20 s")
	assert_eq(int(reach[0]), int(ceil(20.0 / sqrt(0.45))), "Gentle builds slower")
	assert_eq(int(reach[2]), int(ceil(20.0 / sqrt(1.5))), "Intense builds faster")


func test_anticipation_relaxes_back_to_unease() -> void:
	var c := _core(3, {"events": {"x": _simple_event({"min_intensity": 2})}})
	_run(c, 45, _ctx())
	assert_eq(c.get_state(), "anticipation")
	_run(c, 99, _ctx())
	assert_eq(c.get_state(), "anticipation", "holds for anticipation_max")
	_run(c, 1, _ctx())
	assert_eq(c.get_state(), "unease", "nothing major happened: tension eases")
	assert_almost(float(c.tension), float(HorrorData.DIRECTOR["unease_after"]), 0.01)


func test_zone_change_restarts_build_up() -> void:
	var c := _core(3, {"events": {"x": _simple_event({"zones": ["mine", "ruins"], "min_intensity": 2})}})
	_run(c, 50, _ctx())
	assert_eq(c.get_state(), "anticipation")
	c.tick(1.0, _ctx({"zone": "ruins"}))
	assert_eq(c.get_state(), "unease", "a new space steps back to unease")
	assert_true(float(c.tension) <= float(HorrorData.DIRECTOR["unease_after"]) + 1.01, "tension capped")


func test_quiet_zones_do_nothing() -> void:
	var c := _core(3, {"tuning": EAGER})
	for z in ["", "boss", "mine_landing"]:
		var ds := _run(c, 30, _ctx({"zone": z, "anchors": _all_anchors()}))
		assert_eq(_fired(ds).size(), 0, "no events in zone '%s'" % z)
		assert_true(String(ds[29]["reason"]).contains("quiet"), "reason explains the quiet zone")
	assert_eq(c.get_state(), "calm", "tension does not build outside director zones")


# --- eligibility ---------------------------------------------------------------------------------

func test_zone_eligibility() -> void:
	var c := _core(5, {"tuning": EAGER})
	var ds := _run(c, 400, _ctx({"zone": "silk", "anchors": _all_anchors(), "companion": "lumi"}))
	var fired := _fired(ds)
	assert_true(fired.size() > 20, "events fire in silk (%d)" % fired.size())
	for d in fired:
		var zs: Array = d["event"]["zones"]
		assert_true(zs.has("silk"), "%s is allowed in silk" % d["event_id"])
	var decision: Dictionary = ds[0]
	assert_true(_reason_for(decision, "distant_pickaxe").contains("zone"), "mine-only event rejected by zone: " + _reason_for(decision, "distant_pickaxe"))
	assert_true(_reason_for(decision, "gloomling_ambush").contains("zone"), "no gloomling ambush in silk")


func test_state_eligibility() -> void:
	var t := EAGER.duplicate()
	t["unease_after"] = 1.0e9
	t["anticipation_after"] = 1.0e9
	var c := _core(5, {"tuning": t})
	var ds := _run(c, 300, _ctx({"anchors": _all_anchors(), "companion": "lumi"}))
	assert_eq(c.get_state(), "calm")
	var fired := _fired(ds)
	assert_true(fired.size() > 10, "calm-state events fire")
	for d in fired:
		var sts: Array = d["event"]["states"]
		assert_true(sts.has("calm"), "%s allowed in calm" % d["event_id"])
	assert_true(_reason_for(ds[0], "far_glimpse").contains("state"), "glimpse rejected in calm: " + _reason_for(ds[0], "far_glimpse"))
	assert_true(_reason_for(ds[0], "gloomling_ambush").contains("state"), "ambush rejected in calm")


func test_min_intensity_gentle_excludes_majors() -> void:
	for z in ["mine", "ruins", "silk"]:
		var c := _core(11, {"tuning": EAGER})
		var ds := _run(c, 600, _ctx({"zone": z, "intensity": 0, "anchors": _all_anchors(), "companion": "lumi"}))
		for d in _fired(ds):
			assert_false(bool(d["major"]), "no majors at Gentle (%s)" % d["event_id"])
			assert_true(int(d["event"]["min_intensity"]) == 0, "%s allowed at Gentle" % d["event_id"])
		assert_true(_fired(ds).size() > 5, "Gentle still has quiet cues in %s" % z)
	var g := _core(11, {"tuning": EAGER})
	var d0: Dictionary = g.tick(1.0, _ctx({"zone": "ruins", "intensity": 0, "anchors": _all_anchors()}))
	assert_true(_reason_for(d0, "gloomling_ambush").contains("intensity"), "ambush needs Standard: " + _reason_for(d0, "gloomling_ambush"))
	assert_true(_reason_for(d0, "footsteps_behind").contains("intensity"), "footsteps need Standard")
	var s := _core(11, {"tuning": EAGER})
	var d1: Dictionary = s.tick(1.0, _ctx({"zone": "silk", "intensity": 0, "anchors": _all_anchors()}))
	assert_true(_reason_for(d1, "stalker_pass").contains("major scares are off"), "stalker pass is a major: " + _reason_for(d1, "stalker_pass"))
	# Standard allows them
	var st := _core(11, {"tuning": EAGER, "events": _only(["stalker_pass"])})
	var fired := _fired(_run(st, 5, _ctx({"zone": "silk", "intensity": 1, "anchors": _all_anchors()})))
	assert_eq(fired.size(), 1, "stalker pass fires at Standard")


func test_per_event_cooldown() -> void:
	var c := _core(2, {"tuning": EAGER, "events": {"a": _simple_event({"cooldown": 30.0})}})
	var ds := _run(c, 100, _ctx())
	var times: Array = []
	for d in _fired(ds):
		times.append(float(d["time"]))
	assert_eq(times, [1.0, 31.0, 61.0, 91.0], "fires exactly when its cooldown expires")
	assert_true(_reason_for(ds[1], "a").contains("cooldown (29s left)"), "cooldown explained: " + _reason_for(ds[1], "a"))


func test_global_cooldown() -> void:
	var t := EAGER.duplicate()
	t["global_cooldown"] = 14.0
	var events := {"a": _simple_event(), "b": _simple_event(), "c": _simple_event()}
	var c := _core(2, {"tuning": t, "events": events})
	var ds := _run(c, 200, _ctx())
	var fired := _fired(ds)
	assert_true(fired.size() >= 13, "fires every 14 s when forced (%d)" % fired.size())
	for i in range(1, fired.size()):
		assert_true(float(fired[i]["time"]) - float(fired[i - 1]["time"]) >= 14.0, "global cooldown respected")
	assert_true(String(ds[1]["reason"]).begins_with("global cooldown"), "reason: " + String(ds[1]["reason"]))
	# Gentle waits longer (global cooldown / event_rate).
	var g := _core(2, {"tuning": t, "events": events})
	var gf := _fired(_run(g, 200, _ctx({"intensity": 0})))
	for i in range(1, gf.size()):
		assert_true(float(gf[i]["time"]) - float(gf[i - 1]["time"]) >= 14.0 / 0.45 - 0.01, "Gentle cooldown")
	assert_true(gf.size() < fired.size(), "Gentle fires fewer events")


func test_major_cooldown_and_no_stacking() -> void:
	var t := EAGER.duplicate()
	t["recovery_seconds"] = 10.0
	var events := {"m1": _simple_event({"major": true}), "m2": _simple_event({"major": true}),
		"minor": _simple_event({"weight": 0.001})}
	var c := _core(4, {"tuning": t, "events": events})
	var ds := _run(c, 300, _ctx())
	var majors: Array = []
	for d in _fired(ds):
		if bool(d["major"]):
			majors.append(float(d["time"]))
	assert_true(majors.size() >= 3, "majors fire (%d)" % majors.size())
	for i in range(1, majors.size()):
		assert_true(majors[i] - majors[i - 1] >= 90.0, "major cooldown respected (%.0f -> %.0f)" % [majors[i - 1], majors[i]])
	# A major scare starts a recovery with no events at all.
	var m := _core(4, {"tuning": t, "events": events})
	var first: Dictionary = m.tick(1.0, _ctx())
	assert_true(bool(first["major"]), "first pick is a major")
	assert_eq(m.get_state(), "recovery", "major scare -> recovery")
	var during := _run(m, 9, _ctx())
	assert_eq(_fired(during).size(), 0, "nothing during recovery")
	assert_true(String(during[3]["reason"]).begins_with("recovery"), "reason: " + String(during[3]["reason"]))
	var after := _run(m, 3, _ctx())
	var fa := _fired(after)
	assert_true(fa.size() > 0 and not bool(fa[0]["major"]), "only the minor event is eligible after recovery")
	assert_true(_reason_for(after[2], "m2").contains("major cooldown"), "major cooldown explained: " + _reason_for(after[2], "m2"))
	# No stacking: while director threats are still alive no other major may start.
	var s := _core(4, {"tuning": t, "events": events})
	var d: Dictionary = s.tick(1.0, _ctx({"active_director_threats": 1}))
	assert_eq(String(d["event_id"]), "minor")
	assert_true(_reason_for(d, "m1").contains("no stacking"), "no stacking: " + _reason_for(d, "m1"))


func test_spawn_starts_encounter_and_blocks_other_majors() -> void:
	var t := EAGER.duplicate()
	var events := _only(["gloomling_ambush"])
	events["m"] = _simple_event({"major": true, "states": ["anticipation", "encounter"], "weight": 0.0001})
	var c := _core(9, {"tuning": t, "events": events})
	var ctx := _ctx({"anchors": [_anchor("sp", "spawn", "mine", 14.0, false)]})
	var d: Dictionary = c.tick(1.0, ctx)
	assert_eq(String(d["event_id"]), "gloomling_ambush")
	assert_eq(c.get_state(), "encounter", "ambush -> encounter")
	var ds := _run(c, 6, _ctx({"threats_nearby": 1, "active_director_threats": int(d["count"])}))
	assert_eq(_fired(ds).size(), 0, "nothing stacks on an encounter")
	assert_eq(String(ds[5]["reason"]), "encounter in progress")


func test_once_only_events() -> void:
	var t := EAGER.duplicate()
	t["anticipation_after"] = 1.0e9      # stay in unease
	var c := _core(8, {"tuning": t})
	var ds := _run(c, 3000, _ctx({"zone": "ruins", "anchors": _all_anchors()}))
	var n := 0
	var fired_at := -1
	for i in ds.size():
		if String(ds[i]["event_id"]) == "wrong_mochi":
			n += 1
			fired_at = i
	assert_eq(n, 1, "wrong_mochi happens exactly once in 50 minutes")
	assert_true(fired_at >= 0 and _reason_for(ds[mini(fired_at + 450, ds.size() - 1)], "wrong_mochi").contains("once"), "once explained")


func test_needs_companion() -> void:
	var events := _only(["lumi_notices"])
	var ctx := _ctx({"anchors": [_anchor("door", "doorway", "mine", 15.0, false)]})
	for comp in ["", "pebble", "mochi"]:
		var c := _core(1, {"tuning": EAGER, "events": events})
		var ds := _run(c, 10, _ctx({"companion": comp, "anchors": ctx["anchors"]}))
		assert_eq(_fired(ds).size(), 0, "no notice without Lumi (companion '%s')" % comp)
		assert_true(_reason_for(ds[0], "lumi_notices").contains("needs companion lumi"), _reason_for(ds[0], "lumi_notices"))
	var l := _core(1, {"tuning": EAGER, "events": events})
	var lf := _fired(_run(l, 3, _ctx({"companion": "lumi", "anchors": ctx["anchors"]})))
	assert_eq(lf.size(), 1, "Lumi present -> she notices")
	assert_eq(String(lf[0]["anchor"]["name"]), "door")


func test_threat_budget_blocks_spawns() -> void:
	var budget := int(HorrorData.DIRECTOR["max_active_threats"])
	var spawn := _simple_event({"kind": "spawn", "anchor": "spawn", "enemy": "gloomling", "count": [1, 2]})
	var anchors := [_anchor("sp", "spawn", "mine", 15.0, false)]
	var full := _core(1, {"tuning": EAGER, "events": {"s": spawn}})
	var d: Dictionary = full.tick(1.0, _ctx({"anchors": anchors, "active_director_threats": budget}))
	assert_eq(String(d["event_id"]), "", "budget full -> no spawn")
	assert_true(_reason_for(d, "s").contains("threat budget full (%d/%d)" % [budget, budget]), _reason_for(d, "s"))
	var one := _core(1, {"tuning": EAGER, "events": {"s": spawn}})
	var d1: Dictionary = one.tick(1.0, _ctx({"anchors": anchors, "active_director_threats": budget - 1}))
	assert_eq(String(d1["event_id"]), "s", "room for one")
	assert_eq(int(d1["count"]), 1, "count clamped to the remaining budget")
	for sd in 30:
		var f := _core(sd, {"tuning": EAGER, "events": {"s": spawn}})
		var d2: Dictionary = f.tick(1.0, _ctx({"anchors": anchors}))
		assert_true(int(d2["count"]) >= 1 and int(d2["count"]) <= 2, "count within [1,2]")
	# The real ambush (a major) is blocked while any director threat lives.
	var r := _core(1, {"tuning": EAGER, "events": _only(["gloomling_ambush"])})
	var d3: Dictionary = r.tick(1.0, _ctx({"anchors": anchors, "active_director_threats": 1}))
	assert_eq(String(d3["event_id"]), "")


func test_spawn_anchor_validation() -> void:
	var events := _only(["gloomling_ambush"])
	var bad := [_anchor("close", "spawn", "mine", 5.0, false), _anchor("far", "spawn", "mine", 30.0, false),
		_anchor("seen", "spawn", "mine", 15.0, true), _anchor("other_zone", "spawn", "ruins", 15.0, false)]
	var c := _core(1, {"tuning": EAGER, "events": events})
	var ds := _run(c, 5, _ctx({"anchors": bad}))
	assert_eq(_fired(ds).size(), 0, "no valid anchor -> no ambush")
	var why := _reason_for(ds[0], "gloomling_ambush")
	assert_true(why.contains("close too close"), why)
	assert_true(why.contains("far too far"), why)
	assert_true(why.contains("seen visible"), why)
	assert_false(why.contains("other_zone"), "anchors from other zones are ignored")
	var good := bad.duplicate()
	good.append(_anchor("ok", "spawn", "mine", 15.0, false))
	for sd in 10:
		var g := _core(sd, {"tuning": EAGER, "events": events})
		var d: Dictionary = g.tick(1.0, _ctx({"anchors": good}))
		assert_eq(String(d["event_id"]), "gloomling_ambush")
		assert_eq(String(d["anchor"]["name"]), "ok", "only the hidden anchor in the distance band is used")
	# Boundaries are inclusive.
	var edge := [_anchor("min", "spawn", "mine", float(HorrorData.DIRECTOR["min_spawn_distance"]), false)]
	var e := _core(1, {"tuning": EAGER, "events": events})
	assert_eq(String(e.tick(1.0, _ctx({"anchors": edge}))["event_id"]), "gloomling_ambush", "exactly min distance is fine")


func test_glimpse_needs_a_far_visible_doorway() -> void:
	var events := _only(["far_glimpse"])
	var bad := [_anchor("near", "doorway", "mine", 8.0, true), _anchor("hidden", "doorway", "mine", 20.0, false),
		_anchor("distant", "doorway", "mine", 55.0, true)]
	var c := _core(1, {"tuning": EAGER, "events": events})
	var d: Dictionary = c.tick(1.0, _ctx({"anchors": bad}))
	assert_eq(String(d["event_id"]), "")
	var why := _reason_for(d, "far_glimpse")
	assert_true(why.contains("near too close"), why)
	assert_true(why.contains("hidden not in view"), why)
	assert_true(why.contains("distant too far"), why)
	var ok := bad.duplicate()
	ok.append(_anchor("door", "doorway", "mine", 18.0, true))
	var g := _core(1, {"tuning": EAGER, "events": events})
	var dg: Dictionary = g.tick(1.0, _ctx({"anchors": ok}))
	assert_eq(String(dg["event_id"]), "far_glimpse")
	assert_eq(String(dg["anchor"]["name"]), "door")
	assert_true(float(dg["anchor"]["dist"]) >= 12.0, "never closer than 12 m")


func test_missing_anchor_kind_is_explained() -> void:
	var c := _core(1, {"tuning": EAGER, "events": _only(["scratching_above"])})
	var d: Dictionary = c.tick(1.0, _ctx({"zone": "silk", "anchors": [_anchor("s", "sound", "silk", 5.0, false)]}))
	assert_eq(String(d["event_id"]), "")
	assert_true(_reason_for(d, "scratching_above").contains("no ceiling anchor"), _reason_for(d, "scratching_above"))
	var far := _core(1, {"tuning": EAGER, "events": _only(["scratching_above"])})
	var d2: Dictionary = far.tick(1.0, _ctx({"zone": "silk", "anchors": [_anchor("c", "ceiling", "silk", 15.0, false)]}))
	assert_true(_reason_for(d2, "scratching_above").contains("too far"), "scratch needs a ceiling right above the player")


func test_low_health_retreat_and_sprint_rules() -> void:
	var events := _only(["gloomling_ambush", "far_glimpse"])
	var anchors := [_anchor("sp", "spawn", "mine", 15.0, false), _anchor("door", "doorway", "mine", 20.0, true)]
	var low := _core(1, {"tuning": EAGER, "events": events})
	var dl: Dictionary = low.tick(1.0, _ctx({"anchors": anchors, "player_hp_ratio": 0.2}))
	assert_true(_reason_for(dl, "gloomling_ambush").contains("health low"), _reason_for(dl, "gloomling_ambush"))
	assert_eq(String(dl["event_id"]), "far_glimpse", "subtle cues still allowed at low health")
	var ret := _core(1, {"tuning": EAGER, "events": events})
	var dr: Dictionary = ret.tick(1.0, _ctx({"anchors": anchors, "retreating": true}))
	assert_true(_reason_for(dr, "gloomling_ambush").contains("retreating"), "never ambush a retreating player")
	var spr := _core(1, {"tuning": EAGER, "events": events})
	var ds: Dictionary = spr.tick(1.0, _ctx({"anchors": anchors, "sprinting": true}))
	assert_true(_reason_for(ds, "far_glimpse").contains("sprinting"), "glimpses wait until the player can see them")
	# A room's own (still idle) enemies close by: no ambush on top of that encounter.
	var room := _core(1, {"tuning": EAGER, "events": events})
	var de: Dictionary = room.tick(1.0, _ctx({"anchors": anchors, "enemies_nearby": 2}))
	assert_true(_reason_for(de, "gloomling_ambush").contains("no pile-on"), _reason_for(de, "gloomling_ambush"))
	assert_eq(String(de["event_id"]), "far_glimpse", "quiet cues still allowed")


# --- recovery, safety, pause -------------------------------------------------------------------------

func test_recovery_after_encounter() -> void:
	var c := _core(1, {"tuning": {"start_grace": 0.0, "global_cooldown": 0.0, "decision_interval": 1.0, "decision_jitter": 0.0, "do_nothing_weight": 0.0},
		"events": {"a": _simple_event()}})
	_run(c, 10, _ctx({"threats_nearby": 0}))
	_run(c, 5, _ctx({"threats_nearby": 2}))
	assert_eq(c.get_state(), "encounter", "real threats -> encounter")
	var ds := _run(c, 3, _ctx())
	assert_eq(c.get_state(), "encounter", "encounter holds for a few quiet seconds")
	ds.append_array(_run(c, 1, _ctx()))
	assert_eq(c.get_state(), "recovery", "4 quiet seconds -> recovery")
	var rec := _run(c, 24, _ctx())
	assert_eq(_fired(ds).size() + _fired(rec).size(), 0, "no events during encounter/recovery")
	assert_eq(c.get_state(), "recovery")
	_run(c, 1, _ctx())
	assert_eq(c.get_state(), "calm", "recovery_seconds later: calm again")
	assert_almost(float(c.tension), 0.0, 1.01, "tension reset")
	assert_true(_fired(_run(c, 3, _ctx())).size() > 0, "events resume after recovery")


func test_recovery_after_death() -> void:
	var c := _core(1, {"tuning": EAGER, "events": {"a": _simple_event()}})
	_run(c, 5, _ctx())
	c.on_player_died()
	assert_eq(c.get_state(), "recovery")
	var first: Dictionary = c.tick(1.0, _ctx())
	assert_true(bool(first["cancel"]), "death cancels pending events")
	var expected := float(HorrorData.DIRECTOR["recovery_seconds"]) * 1.6
	var ds := _run(c, int(expected) - 2, _ctx())
	assert_eq(_fired(ds).size(), 0, "long quiet period after death")
	var after := _run(c, 4, _ctx())
	assert_true(_fired(after).size() > 0, "director resumes after the death recovery")


func test_recovery_after_authored_moment() -> void:
	var t := EAGER.duplicate()
	t["global_cooldown"] = 40.0
	var events := {"minor": _simple_event(), "big": _simple_event({"major": true})}
	var c := _core(1, {"tuning": t, "events": events})
	c.on_authored_event("distant_crossing")
	assert_eq(c.get_state(), "recovery")
	var ds := _run(c, 39, _ctx())
	assert_eq(_fired(ds).size(), 0, "recovery then global cooldown")
	assert_true(String(ds[30]["reason"]).begins_with("global cooldown"), "after recovery the global cooldown still holds: " + String(ds[30]["reason"]))
	var d: Dictionary = c.tick(1.0, _ctx())
	assert_eq(String(d["event_id"]), "minor", "only minor cues after an authored scare")
	assert_true(_reason_for(d, "big").contains("major cooldown"), "authored moments start the major cooldown")
	assert_true(c.debug_log.size() > 0 and "\n".join(PackedStringArray(c.debug_log)).contains("authored moment 'distant_crossing'"), "authored logged")


func test_safe_zone_and_pause_do_nothing_and_cancel() -> void:
	var c := _core(1, {"tuning": EAGER, "events": {"a": _simple_event()}})
	_run(c, 3, _ctx())
	var t_before := float(c.now)
	var p1: Dictionary = c.tick(1.0, _ctx({"paused": true}))
	var p2: Dictionary = c.tick(1.0, _ctx({"paused": true}))
	assert_eq(String(p1["event_id"]), "")
	assert_true(bool(p1["cancel"]), "pausing cancels pending events")
	assert_false(bool(p2["cancel"]), "cancel is sent once")
	assert_eq(String(p2["event_id"]), "")
	assert_almost(float(c.now), t_before, 0.0001, "director clock frozen while paused")
	assert_true(_fired(_run(c, 2, _ctx())).size() > 0, "resumes after unpause")
	# Safe zone
	var s := _core(1, {"events": {"a": _simple_event({"states": ["anticipation"]})}, "tuning": {"start_grace": 0.0, "global_cooldown": 0.0, "decision_interval": 1.0, "decision_jitter": 0.0, "do_nothing_weight": 0.0}})
	_run(s, 46, _ctx({"anchors": _all_anchors()}))
	assert_eq(s.get_state(), "anticipation")
	var sd: Dictionary = s.tick(1.0, _ctx({"in_safe_zone": true}))
	assert_true(bool(sd["cancel"]), "entering a safe zone cancels pending events")
	assert_eq(s.get_state(), "calm", "safe zone calms the director")
	var ds := _run(s, 120, _ctx({"in_safe_zone": true}))
	assert_eq(_fired(ds).size(), 0, "nothing ever happens in a safe zone")
	assert_eq(String(ds[50]["reason"]), "safe zone")
	assert_false(bool(ds[50]["cancel"]))
	assert_almost(float(s.tension), 0.0, 0.001, "no tension while safe")
	# Recovery does not tick while paused.
	var r := _core(1, {"tuning": EAGER, "events": {"a": _simple_event()}})
	r.on_player_died()
	var left := float(r.recovery_left)
	_run(r, 100, _ctx({"paused": true}))
	assert_almost(float(r.recovery_left), left, 0.0001, "recovery frozen while paused")


func test_suppress_blocks_events() -> void:
	var c := _core(1, {"tuning": EAGER, "events": {"a": _simple_event()}})
	c.suppress(20.0)
	var ds := _run(c, 19, _ctx())
	assert_true(bool(ds[0]["cancel"]), "suppress cancels pending work")
	assert_eq(_fired(ds).size(), 0, "suppressed")
	assert_true(String(ds[5]["reason"]).begins_with("suppressed"))
	assert_true(_fired(_run(c, 3, _ctx())).size() > 0, "resumes after suppression")


func test_suppress_keeps_longest_but_a_hold_is_released_by_the_next_call() -> void:
	var c := _core(1, {"tuning": EAGER, "events": {"a": _simple_event()}})
	c.suppress(30.0)
	c.suppress(10.0)
	assert_almost(float(c.suppressed_left), 30.0, 0.001, "overlapping authored moments keep the longest quiet")
	# Boss fight: below_world suppresses 9999 s on entry and suppress(20) when Krystal leaves the arena.
	var b := _core(1, {"tuning": EAGER, "events": {"a": _simple_event()}})
	b.suppress(9999.0)
	_run(b, 50, _ctx())
	b.suppress(20.0)
	assert_almost(float(b.suppressed_left), 20.0, 0.001, "a hold is replaced by the next call")
	var ds := _run(b, 19, _ctx())
	assert_eq(_fired(ds).size(), 0, "still quiet for those 20 s")
	assert_true(_fired(_run(b, 3, _ctx())).size() > 0, "then the director resumes (it used to stay silent for 9999 s)")
	var r := _core(1)
	r.suppress(60.0)
	r.suppress(5.0, true)
	assert_almost(float(r.suppressed_left), 5.0, 0.001, "replace=true always replaces")


func test_failed_event_rolls_back_pacing() -> void:
	# An ambush the node could not carry out (anchor blocked) must not leave the director in a phantom
	# encounter + recovery, nor spend the global / major cooldowns.
	var t := EAGER.duplicate()
	t["global_cooldown"] = 14.0
	var events := _only(["gloomling_ambush"])
	events["cue"] = _simple_event({"states": ["anticipation"]})
	var c := _core(9, {"tuning": t, "events": events})
	var ctx := _ctx({"anchors": [_anchor("sp", "spawn", "mine", 14.0, false)]})
	var d: Dictionary = {}
	for i in 20:
		d = c.tick(1.0, ctx)
		if String(d["event_id"]) == "gloomling_ambush":
			break
	assert_eq(String(d["event_id"]), "gloomling_ambush", "the ambush was chosen")
	assert_eq(c.get_state(), "encounter")
	var fired_before := int(c.stats["fired"])
	c.on_event_failed("gloomling_ambush", "anchor inside geometry")
	assert_eq(c.get_state(), "anticipation", "back to the build-up, no phantom encounter")
	assert_true(float(c.last_major_time) < -1.0e8, "major cooldown rolled back")
	assert_eq(int(c.stats["fired"]), fired_before - 1)
	assert_eq(int(c.stats["failed"]), 1)
	assert_eq(int(c.stats["majors"]), 0)
	assert_true(c.last_fired.has("gloomling_ambush"), "per-event cooldown kept: the broken anchor is not retried at once")
	var why := ""
	var next_fire := ""
	for i in 30:
		var n: Dictionary = c.tick(1.0, ctx)
		if why == "":
			why = _reason_for(n, "gloomling_ambush")
		if String(n["event_id"]) != "":
			next_fire = String(n["event_id"])
			break
	assert_true(why.contains("cooldown"), "ambush on its own cooldown: " + why)
	assert_eq(next_fire, "cue", "the director moves on to something that can happen")
	# A failure report for anything but the last fired event changes nothing.
	var s := _core(2, {"tuning": EAGER, "events": {"a": _simple_event({"once": true})}})
	s.tick(1.0, _ctx())
	var le := float(s.last_event_time)
	s.on_event_failed("zzz", "unrelated")
	assert_almost(float(s.last_event_time), le, 0.0001, "unknown id ignored")
	# A once-only cue that could not play may still happen later.
	s.on_event_failed("a", "sound missing")
	assert_false(s.fired_once.has("a"), "once-only use given back")
	# After a death the rollback is off (the recovery was not caused by the event).
	var k := _core(3, {"tuning": EAGER, "events": {"m": _simple_event({"major": true})}})
	k.tick(1.0, _ctx())
	assert_eq(k.get_state(), "recovery")
	k.on_player_died()
	k.on_event_failed("m", "late")
	assert_eq(k.get_state(), "recovery", "death recovery untouched")


# --- selection ----------------------------------------------------------------------------------

func test_repetition_avoidance_no_back_to_back() -> void:
	var events := {"a": _simple_event(), "b": _simple_event({"weight": 0.2})}
	var c := _core(6, {"tuning": EAGER, "events": events})
	var fired := _fired(_run(c, 600, _ctx()))
	assert_eq(fired.size(), 600)
	for i in range(1, fired.size()):
		assert_ne(String(fired[i]["event_id"]), String(fired[i - 1]["event_id"]), "no back-to-back repeat at %d" % i)
	# ...unless it is the only option.
	var solo := _core(6, {"tuning": EAGER, "events": {"a": _simple_event()}})
	assert_eq(_fired(_run(solo, 10, _ctx())).size(), 10, "the only option may repeat")


func test_recency_penalties() -> void:
	var events := {"a": _simple_event(), "b": _simple_event(), "c": _simple_event(), "d": _simple_event()}
	var c := _core(6, {"tuning": EAGER, "events": events})
	var fired := _fired(_run(c, 3, _ctx()))
	var last := String(fired[2]["event_id"])
	var second := String(fired[1]["event_id"])
	var third := String(fired[0]["event_id"])
	assert_almost(c._repeat_factor(last, 4), 0.0, 0.0001, "most recent excluded")
	assert_almost(c._repeat_factor(second, 4), 0.35, 0.0001, "second most recent penalised")
	assert_almost(c._repeat_factor(third, 4), 0.6, 0.0001, "third most recent lightly penalised")
	assert_almost(c._repeat_factor(last, 1), 0.35, 0.0001, "only option keeps a reduced weight")
	# Statistically: an a-b-a pattern is rarer than a-b-c.
	var big := _core(21, {"tuning": EAGER, "events": {"a": _simple_event(), "b": _simple_event(), "c": _simple_event()}})
	var seq := _fired(_run(big, 3000, _ctx()))
	var aba := 0
	for i in range(2, seq.size()):
		if String(seq[i]["event_id"]) == String(seq[i - 2]["event_id"]):
			aba += 1
	var ratio := float(aba) / float(seq.size() - 2)
	print("  recency: x-y-x ratio %.3f (uniform 0.5; recency weights 0.35 vs 0.6 -> ~0.37)" % ratio)
	assert_true(ratio > 0.25 and ratio < 0.45, "second-most-recent penalty works (%.3f)" % ratio)


func test_fatigue_penalises_events_used_often_recently() -> void:
	var c := _core(6, {"tuning": EAGER, "events": {"a": _simple_event(), "b": _simple_event()}})
	assert_almost(c._fatigue_factor("a"), 1.0, 0.0001, "unused event: full weight")
	_run(c, 6, _ctx())                   # a, b alternate: 3 uses each
	assert_almost(c._fatigue_factor("a"), 1.0 / (1.0 + 0.4 * 3.0), 0.0001, "3 recent uses")
	_run(c, 20, _ctx())
	assert_almost(c._fatigue_factor("a"), 1.0 / (1.0 + 0.4 * 4.0), 0.0001, "uses capped at 4")
	# Outside the window the memory fades.
	var q := _core(6, {"tuning": EAGER, "events": {"a": _simple_event()}})
	_run(q, 1, _ctx())
	_run(q, 400, _ctx({"in_safe_zone": true}))
	assert_almost(q._fatigue_factor("a"), 1.0, 0.0001, "forgotten after the fatigue window")


func test_major_weight_ramps_during_anticipation() -> void:
	var c := _core(6, {"events": {"m": _simple_event({"major": true, "min_intensity": 2})}})
	var ev: Dictionary = c.events["m"]
	_run(c, 45, _ctx())
	assert_eq(c.get_state(), "anticipation")
	assert_almost(c._major_ramp(ev), 1.0, 0.05, "no ramp at the start of anticipation")
	_run(c, 50, _ctx())
	assert_almost(c._major_ramp(ev), 1.0 + 3.0 * 0.5, 0.05, "halfway through: x2.5")
	var minor: Dictionary = _simple_event()
	assert_almost(c._major_ramp(minor), 1.0, 0.0001, "minor events never ramp")


func test_intensity_scales_cooldowns() -> void:
	var c := _core(1)
	assert_almost(c.global_cooldown_for(1), 14.0, 0.001, "Standard global cooldown from data")
	assert_almost(c.global_cooldown_for(0), 14.0 / 0.45, 0.001, "Gentle waits longer")
	assert_almost(c.global_cooldown_for(2), 14.0, 0.001, "Intense keeps the data minimum")
	assert_almost(c.major_cooldown_for(1), 90.0, 0.001)
	assert_almost(c.major_cooldown_for(2), 60.0, 0.001, "Intense: bolder stalking")


func test_long_run_real_data_no_back_to_back_unless_only_option() -> void:
	var fired: Array = []
	for sd in [1, 2, 3]:
		var run: Array = _simulate(sd, 2, 3600)["fired"]
		fired.append_array(run)
		for i in range(1, run.size()):
			if String(run[i]["id"]) == String(run[i - 1]["id"]):
				assert_eq(int(run[i]["eligible"]), 1, "%s repeated back-to-back with %d options" % [run[i]["id"], run[i]["eligible"]])
	assert_true(fired.size() > 60, "long simulated runs fire plenty of events (%d)" % fired.size())


func test_do_nothing_frequency_30_minutes() -> void:
	var counts: Array = []
	var major_counts: Array = []
	for intensity in [0, 1, 2]:
		var total := 0
		var majors := 0
		var decisions := 0
		for sd in [11, 22, 33, 44]:
			var r := _simulate(sd, intensity)
			var fired: Array = r["fired"]
			total += fired.size()
			decisions += int(r["decisions"])
			for f in fired:
				if bool(f["major"]):
					majors += 1
			if sd == 11:
				var core: Core = r["core"]
				print("  [%s] seed %d: %s" % [HorrorData.INTENSITY[intensity]["name"], sd, core.summary()])
		var avg := float(total) / 4.0
		var avg_major := float(majors) / 4.0
		var nothing_ratio := 1.0 - float(total) / maxf(float(decisions), 1.0)
		print("  [%s] 30 min average: %.1f events (%.1f per minute), %.1f majors, did nothing in %.0f%% of decisions" % [
			HorrorData.INTENSITY[intensity]["name"], avg, avg / 30.0, avg_major, nothing_ratio * 100.0])
		counts.append(avg)
		major_counts.append(avg_major)
		assert_true(nothing_ratio > 0.55, "the director often chooses to do nothing (%.2f)" % nothing_ratio)
		assert_true(avg_major <= 30.0 * 60.0 / 60.0, "majors limited by the major cooldown")
		if intensity == 0:
			assert_eq(avg_major, 0.0, "no majors at Gentle")
			assert_true(avg >= 6.0 and avg <= 22.0, "Gentle: a handful of quiet cues (%.1f)" % avg)
		elif intensity == 1:
			assert_true(avg >= 18.0 and avg <= 40.0, "Standard: about one cue a minute or less (%.1f)" % avg)
			assert_true(avg_major >= 1.5 and avg_major <= 8.0, "Standard: a few real scares, not a barrage (%.1f)" % avg_major)
		else:
			assert_true(avg >= 25.0 and avg <= 55.0, "Intense: busier but not constant (%.1f)" % avg)
	assert_true(counts[0] < counts[1] and counts[1] < counts[2], "event rate scales with intensity %s" % str(counts))
	assert_true(major_counts[2] >= major_counts[1], "Intense stalks at least as boldly as Standard %s" % str(major_counts))


func test_determinism() -> void:
	var a := _sequence(_simulate(1234, 1, 900)["fired"])
	var b := _sequence(_simulate(1234, 1, 900)["fired"])
	var c := _sequence(_simulate(4321, 1, 900)["fired"])
	assert_true(a.size() > 5, "enough events to compare (%d)" % a.size())
	assert_eq(a, b, "same seed + same inputs -> identical decisions")
	assert_ne(a, c, "different seed -> different decisions")


func _sequence(fired: Array) -> Array:
	var out: Array = []
	for f in fired:
		out.append("%.0f:%s:%s:%d" % [float(f["t"]), f["id"], f["anchor"], int(f["count"])])
	return out


func test_same_seed_after_setup_resets() -> void:
	var c := _core(77, {"tuning": EAGER})
	var first := _fired(_run(c, 50, _ctx({"anchors": _all_anchors()})))
	c.setup({"seed": 77, "tuning": EAGER})
	var second := _fired(_run(c, 50, _ctx({"anchors": _all_anchors()})))
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(String(first[i]["event_id"]), String(second[i]["event_id"]), "setup() resets everything")


# --- debug log --------------------------------------------------------------------------------

func test_debug_log_explains_decisions() -> void:
	var c := _core(1, {"tuning": EAGER, "events": _only(["gloomling_ambush", "creaking_timbers"])})
	c.tick(1.0, _ctx({"anchors": [_anchor("seen", "spawn", "mine", 15.0, true)]}))
	var log_text := "\n".join(PackedStringArray(c.debug_log))
	assert_true(log_text.contains("FIRE creaking_timbers"), "selection logged")
	assert_true(log_text.contains("gloomling_ambush: no usable spawn anchor (seen visible to the player)"), "rejection explained:\n" + log_text)
	var n := _core(1)
	_run(n, 200, _ctx({"anchors": _all_anchors()}))
	var nt := "\n".join(PackedStringArray(n.debug_log))
	assert_true(nt.contains("state calm -> unease"), "transitions logged")
	assert_true(nt.contains("chose to do nothing"), "do-nothing decisions logged")
	assert_true(nt.contains("options:"), "weights of the options logged")
	# The log is bounded.
	var big := _core(1, {"tuning": EAGER})
	_run(big, 2000, _ctx({"anchors": _all_anchors()}))
	assert_true(big.debug_log.size() <= 400, "debug log capped")


func test_file_log() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	var path := "user://test_saves/director_log_test.txt"
	var c := _core(1, {"tuning": EAGER})
	assert_true(c.set_log_file(path))
	_run(c, 5, _ctx())
	c.set_log_file("")
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "log file written")
	if f != null:
		var text := f.get_as_text()
		f.close()
		assert_true(text.contains("FIRE "), "file log contains decisions")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_force_event_for_qa() -> void:
	var c := _core(1)
	var d: Dictionary = c.force("far_glimpse", _ctx({"anchors": [_anchor("h", "doorway", "mine", 16.0, false)]}))
	assert_eq(String(d["event_id"]), "far_glimpse", "force falls back to the nearest anchor")
	assert_eq(String(d["anchor"]["name"]), "h")
	var u: Dictionary = c.force("nope", _ctx())
	assert_eq(String(u["event_id"]), "")
	assert_true(String(u["reason"]).contains("unknown"))
	var none: Dictionary = c.force("scratching_above", _ctx())
	assert_eq(String(none["event_id"]), "", "forced events still need an anchor")
