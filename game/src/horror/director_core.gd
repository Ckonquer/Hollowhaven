extends RefCounted
## Local horror director - pure pacing logic. No nodes, no physics, no network, no LLM:
## a small, deterministic state machine plus a weighted random picker. Fully unit-testable.
##
## States: calm -> unease -> anticipation -> encounter -> recovery -> calm
##   calm/unease/anticipation are driven by "tension": seconds spent in a dungeon zone, sped up
##   while the player lingers (stands still) and slowed while they retreat. anticipation relaxes
##   back to unease if nothing major happened for a while (builds and releases, like breathing).
##   encounter: something is actually threatening the player (or the director just spawned it).
##   recovery: a quiet period after encounters, major scares, deaths and authored moments.
##
## Usage (director.gd does this every second):
##   var core = preload("res://src/horror/director_core.gd").new()
##   core.setup({"seed": 42})
##   var d: Dictionary = core.tick(1.0, ctx)
##   # d = {event_id ("" most of the time), reason, rejected: [{id, reason}], state, cancel,
##   #      anchor ({} or the chosen ctx anchor), event (data), kind, count, major, eligible_count, time}
##
## ctx = {zone, in_safe_zone, paused, player_hp_ratio, sprinting, retreating, lingering_seconds,
##        threats_nearby, active_director_threats, companion ("" or id), intensity (0/1/2),
##        anchors: [{name?, kind, zone, pos, dist, visible}], time?,
##        enemies_nearby? (idle dungeon enemies close by: no ambush piles onto a room's own encounter)}
## Missing ctx keys fall back to harmless defaults.
##
## Determinism: all randomness comes from this object's own RandomNumberGenerator seeded in setup().
## Same seed + same tick inputs => identical decisions.

signal state_changed(new_state: String, reason: String)

const HorrorData := preload("res://data/horror_events.gd")

const TENSION_STATES: Array[String] = ["calm", "unease", "anticipation"]

## Extra pacing knobs owned by this module. data/horror_events.gd DIRECTOR values are merged on top,
## then setup({"tuning": {...}}) overrides (tests use that to isolate single rules).
const EXTRA_TUNING := {
	"decision_interval": 12.0,         # seconds between "should I do something?" rolls (after the global cooldown)
	"decision_jitter": 0.4,            # +-40% on each interval
	"start_grace": 8.0,                # quiet seconds after the director starts / enters a zone
	"nothing_mult": {"calm": 2.5, "unease": 1.5, "anticipation": 1.0},   # do-nothing weight per state
	"linger_tension_mult": 1.75,       # standing still builds tension faster
	"retreat_tension_mult": 0.25,      # backing away from a threat barely builds tension
	"tension_scales_with_intensity": true,   # tension rate x sqrt(event_rate): Gentle builds slower, Intense faster
	"anticipation_max": 100.0,         # anticipation without a major relaxes back to unease
	"encounter_clear_seconds": 4.0,    # no threat for this long ends an encounter
	"encounter_min_seconds": 8.0,
	"death_recovery_mult": 1.6,        # recovery after death is longer
	"authored_counts_as_major": true,  # authored moments also start the major cooldown
	"low_hp_ratio": 0.35,              # below this: no spawns, no majors
	"repeat_penalties": [0.0, 0.35, 0.6, 0.8],   # weight factor by recency (0 = the last event)
	"repeat_only_option_factor": 0.35, # last event may repeat only if it is the only option
	"fatigue_window": 300.0,           # an event used several times in this window loses weight...
	"fatigue_per_use": 0.4,            # ...weight / (1 + 0.4 * uses), uses capped at 4
	"major_ramp": 3.0,                 # in anticipation, major weights grow up to x(1+ramp) so the build-up pays off
	"gentle_cooldown_scale": true,     # global cooldown / event_rate when event_rate < 1
	"glimpse_min_distance": 12.0,      # a glimpse never appears closer than this
	"glimpse_max_distance": 40.0,
	"sound_anchor_max_distance": 30.0,
	"notice_max_distance": 28.0,
	"scratch_max_distance": 9.0,
	"stalker_max_distance": 30.0,
	"default_anchor_max_distance": 35.0,
	"suppress_hold_seconds": 600.0,    # a suppress() this long is a "hold": the next suppress() call replaces it
	"log_limit": 400,
}

const EVENT_DEFAULTS := {"kind": "sound", "zones": [], "states": [], "weight": 1.0, "cooldown": 0.0,
	"major": false, "min_intensity": 0, "anchor": "", "sound": "", "caption": ""}

var tuning: Dictionary = {}
var events: Dictionary = {}
var intensity_table: Dictionary = {}
var event_ids: Array[String] = []
var director_zones: Dictionary = {}     # zone id -> true for every zone that has at least one event

var rng := RandomNumberGenerator.new()
var seed_value: int = 0

var state: String = "calm"
var now: float = 0.0                    # director clock (seconds, advances only while not paused)
var time_in_state: float = 0.0
var tension: float = 0.0
var zone: String = ""
var time_in_zone: float = 0.0
var recovery_left: float = 0.0
var suppressed_left: float = 0.0
var last_event_time: float = -1.0e9
var last_major_time: float = -1.0e9
var last_fired: Dictionary = {}         # event id -> director time
var fired_once: Dictionary = {}         # event id -> true
var recent: Array[String] = []          # most recent first
var history: Array = []                 # [[time, id], ...] fired within the fatigue window
var next_decision_at: float = 0.0
var encounter_clear_time: float = 0.0
var blocked_reason: String = ""         # "paused" / "safe zone" while blocked
var debug_log: Array[String] = []
var stats: Dictionary = {}

var _cancel_requested: bool = false
var _log_file: FileAccess = null
var _undo: Dictionary = {}              # pacing state before the last fired event (see on_event_failed)


func _init() -> void:
	setup({})


## (Re)initialises the director. params: seed, events (override table), tuning (overrides), intensity.
func setup(params: Dictionary = {}) -> void:
	seed_value = int(params.get("seed", 0))
	rng.seed = seed_value
	tuning = EXTRA_TUNING.duplicate(true)
	tuning.merge(HorrorData.DIRECTOR, true)
	var tover: Dictionary = params.get("tuning", {})
	tuning.merge(tover, true)
	var src: Dictionary = params.get("events", HorrorData.EVENTS)
	events = {}
	for id in src:
		var ev: Dictionary = EVENT_DEFAULTS.duplicate(true)
		var raw: Dictionary = src[id]
		ev.merge(raw.duplicate(true), true)
		events[String(id)] = ev
	var itab: Dictionary = params.get("intensity", HorrorData.INTENSITY)
	intensity_table = itab.duplicate(true)
	event_ids.clear()
	director_zones.clear()
	for id in events:
		event_ids.append(String(id))
		var zs: Array = events[id]["zones"]
		for z in zs:
			director_zones[String(z)] = true
	event_ids.sort()
	state = "calm"
	now = 0.0
	time_in_state = 0.0
	tension = 0.0
	zone = ""
	time_in_zone = 0.0
	recovery_left = 0.0
	suppressed_left = 0.0
	last_event_time = -1.0e9
	last_major_time = -1.0e9
	last_fired = {}
	fired_once = {}
	recent.clear()
	history = []
	next_decision_at = float(tuning["start_grace"])
	encounter_clear_time = 0.0
	blocked_reason = ""
	_cancel_requested = false
	_undo = {}
	debug_log.clear()
	stats = {"ticks": 0, "decisions": 0, "fired": 0, "nothing": 0, "majors": 0, "failed": 0,
		"by_event": {}, "by_state": {}, "transitions": 0}


# --- Public hooks ------------------------------------------------------------------------

func get_state() -> String:
	return state


## The player died: long recovery, tension reset, pending events cancelled.
func on_player_died() -> void:
	tension = 0.0
	last_event_time = now
	_cancel_requested = true
	_undo = {}
	_enter_recovery(float(tuning["recovery_seconds"]) * float(tuning["death_recovery_mult"]), "player died")


## An authored moment (Distant Crossing, Imitation...) played: recovery + global cooldown.
func on_authored_event(authored_id: String) -> void:
	tension = 0.0
	last_event_time = now
	if bool(tuning["authored_counts_as_major"]):
		last_major_time = now
	_cancel_requested = true
	_undo = {}
	_enter_recovery(float(tuning["recovery_seconds"]), "authored moment '%s'" % authored_id)


## Hands-off period (authored scenes, cutscenes). Tension keeps its value; nothing fires.
## Overlapping calls keep the longest remaining time, except that a very long suppression (a "hold",
## e.g. suppress(9999) for the boss fight) is replaced by the next call, so suppress(20) afterwards
## releases it 20 s later. replace=true always replaces.
func suppress(seconds: float, replace: bool = false) -> void:
	var hold := suppressed_left >= float(tuning.get("suppress_hold_seconds", 600.0))
	if replace or hold:
		suppressed_left = maxf(seconds, 0.0)
	else:
		suppressed_left = maxf(suppressed_left, seconds)
	_cancel_requested = true
	_undo = {}
	_log("suppressed for %.0fs%s" % [suppressed_left, " (replaces a hold)" if hold and not replace else ""])


## The node could not carry out the event this core just chose (anchor blocked by a prop, no light
## to flicker, stalker busy, sound missing...). Nothing happened in the world, so the pacing side
## effects are rolled back: global and major cooldowns, repetition memory, "once" use and the
## encounter/recovery the event started. Its own per-event cooldown stays, so the same broken setup
## is not retried at every decision.
func on_event_failed(event_id: String, reason: String = "") -> void:
	if _undo.is_empty() or String(_undo.get("id", "")) != event_id:
		_log("%s failed (%s); nothing to roll back" % [event_id, reason])
		return
	var u := _undo
	_undo = {}
	last_event_time = float(u["last_event_time"])
	last_major_time = float(u["last_major_time"])
	if not bool(u["was_once"]):
		fired_once.erase(event_id)
	if not recent.is_empty() and recent[0] == event_id:
		recent.pop_front()
	for i in range(history.size() - 1, -1, -1):
		if String(history[i][1]) == event_id:
			history.remove_at(i)
			break
	stats["fired"] = maxi(int(stats["fired"]) - 1, 0)
	stats["failed"] = int(stats.get("failed", 0)) + 1
	var be: Dictionary = stats["by_event"]
	be[event_id] = maxi(int(be.get(event_id, 0)) - 1, 0)
	var bs: Dictionary = stats["by_state"]
	var prev_state := String(u["state"])
	bs[prev_state] = maxi(int(bs.get(prev_state, 0)) - 1, 0)
	if bool(u["major"]):
		stats["majors"] = maxi(int(stats["majors"]) - 1, 0)
	# Undo the encounter / recovery the event started (only if nothing else changed the state since).
	if state != prev_state and state == String(u.get("after_state", "")) and TENSION_STATES.has(prev_state):
		recovery_left = 0.0
		encounter_clear_time = 0.0
		_set_state(prev_state, "'%s' could not happen" % event_id)
		time_in_state = float(u["time_in_state"]) + (now - float(u["time"]))
	_log("%s could not happen (%s): pacing rolled back" % [event_id, reason])


## Effective global cooldown for an intensity (Gentle waits longer between cues).
func global_cooldown_for(intensity: int) -> float:
	var gc := float(tuning["global_cooldown"])
	if bool(tuning["gentle_cooldown_scale"]):
		var rate := _event_rate(intensity)
		if rate > 0.0 and rate < 1.0:
			gc /= rate
	return gc


## Effective major cooldown (Intense stalks more boldly: cooldown / event_rate when event_rate > 1).
func major_cooldown_for(intensity: int) -> float:
	return float(tuning["major_cooldown"]) / maxf(_event_rate(intensity), 1.0)


## Adds a line to the debug log (the node reports execution results through this).
func log_line(text: String) -> void:
	_log(text)


## Optional file log (director.gd opens it for --director-log=<path>).
func set_log_file(path: String) -> bool:
	if path == "":
		_log_file = null
		return false
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	if _log_file == null:
		push_warning("HorrorDirector: cannot open log file %s" % path)
		return false
	_log_file.store_line("# Hollowhaven horror director log (seed %d)" % seed_value)
	return true


func summary() -> String:
	return "ticks %d, decisions %d, fired %d (majors %d), could not happen %d, chose nothing %d, by event %s" % [
		int(stats["ticks"]), int(stats["decisions"]), int(stats["fired"]), int(stats["majors"]),
		int(stats.get("failed", 0)), int(stats["nothing"]), str(stats["by_event"])]


# --- Tick ----------------------------------------------------------------------------------

func tick(dt: float, ctx: Dictionary) -> Dictionary:
	var d := _new_decision()
	if bool(ctx.get("paused", false)):
		d["reason"] = "paused"
		if blocked_reason != "paused":
			blocked_reason = "paused"
			d["cancel"] = true
			_cancel_requested = false
			_log("paused: holding still, pending events cancelled")
		return d
	dt = maxf(dt, 0.0)
	now += dt
	time_in_state += dt
	stats["ticks"] = int(stats["ticks"]) + 1
	d["time"] = now
	if _cancel_requested:
		_cancel_requested = false
		d["cancel"] = true
	if suppressed_left > 0.0:
		suppressed_left = maxf(0.0, suppressed_left - dt)
	var z := String(ctx.get("zone", ""))
	if z != zone:
		_on_zone_changed(z)
	time_in_zone += dt
	if state == "recovery":
		recovery_left -= dt
		if recovery_left <= 0.0:
			recovery_left = 0.0
			tension = 0.0
			_set_state("calm", "recovery finished")
	# Safe zones: nothing happens, tension drains, pending work is cancelled once.
	if bool(ctx.get("in_safe_zone", false)):
		if blocked_reason != "safe zone":
			blocked_reason = "safe zone"
			d["cancel"] = true
			_log("safe zone: nothing will happen here, pending events cancelled")
		if state == "unease" or state == "anticipation":
			_set_state("calm", "reached a safe zone")
		elif state == "encounter":
			_enter_recovery(float(tuning["recovery_seconds"]), "reached a safe zone during an encounter")
		tension = 0.0
		d["state"] = state
		d["reason"] = "safe zone"
		return d
	if blocked_reason != "":
		_log("%s ended" % blocked_reason)
		blocked_reason = ""
	# Encounters: any real threat nearby takes over.
	var threats := int(ctx.get("threats_nearby", 0))
	if threats > 0 and TENSION_STATES.has(state):
		encounter_clear_time = 0.0
		_set_state("encounter", "%d threat(s) nearby" % threats)
	if state == "encounter":
		if threats > 0:
			encounter_clear_time = 0.0
		else:
			encounter_clear_time += dt
		if encounter_clear_time >= float(tuning["encounter_clear_seconds"]) and time_in_state >= float(tuning["encounter_min_seconds"]):
			_enter_recovery(float(tuning["recovery_seconds"]), "encounter over")
	# Tension grows with time in a dungeon zone; lingering speeds it up, retreating slows it.
	var active_zone := director_zones.has(zone)
	if active_zone and TENSION_STATES.has(state):
		var rate: float = sqrt(maxf(_event_rate(clampi(int(ctx.get("intensity", 1)), 0, 2)), 0.0)) if bool(tuning["tension_scales_with_intensity"]) else 1.0
		if float(ctx.get("lingering_seconds", 0.0)) >= float(tuning["linger_seconds"]):
			rate *= float(tuning["linger_tension_mult"])
		if bool(ctx.get("retreating", false)):
			rate *= float(tuning["retreat_tension_mult"])
		tension += dt * rate
		_update_tension_state()
	d["state"] = state
	# Gates that make the director do nothing without even considering events.
	if not active_zone:
		d["reason"] = "zone '%s' is quiet" % zone
		return d
	if state == "encounter":
		d["reason"] = "encounter in progress"
		return d
	if state == "recovery":
		d["reason"] = "recovery (%.0fs left)" % recovery_left
		return d
	if suppressed_left > 0.0:
		d["reason"] = "suppressed (%.0fs left)" % suppressed_left
		return d
	var intensity := clampi(int(ctx.get("intensity", 1)), 0, 2)
	var gc := global_cooldown_for(intensity)
	var since := now - last_event_time
	if since < gc:
		d["reason"] = "global cooldown (%.0fs left)" % (gc - since)
		return d
	if now < next_decision_at:
		d["reason"] = "waiting (next decision in %.0fs)" % (next_decision_at - now)
		return d
	# Irregular rhythm: the next "should I?" moment is jittered so cues never feel metronomic.
	var jitter := float(tuning["decision_jitter"])
	next_decision_at = now + float(tuning["decision_interval"]) * rng.randf_range(1.0 - jitter, 1.0 + jitter)
	return _decide(d, ctx, intensity)


## Debug/QA: picks `event_id` right now, ignoring pacing rules but still requiring a usable anchor
## (falls back to the nearest anchor of the right kind). Returns a decision like tick().
func force(event_id: String, ctx: Dictionary) -> Dictionary:
	var d := _new_decision()
	if not events.has(event_id):
		d["reason"] = "unknown event '%s'" % event_id
		return d
	var ev: Dictionary = events[event_id]
	var anchor := {}
	var need := String(ev["anchor"])
	if need != "":
		var check := _validate_anchors(ev, ctx)
		var valid: Array = check["valid"]
		if valid.is_empty():
			var best_d := INF
			var anchors: Array = ctx.get("anchors", [])
			for a in anchors:
				if a is Dictionary and String(a.get("kind", "")) == need and float(a.get("dist", 0.0)) < best_d:
					best_d = float(a.get("dist", 0.0))
					anchor = a
			if anchor.is_empty():
				d["reason"] = "forced %s: %s" % [event_id, String(check["reason"])]
				_log(d["reason"])
				return d
		else:
			anchor = valid[0]
	d["event_id"] = event_id
	d["event"] = ev
	d["kind"] = String(ev["kind"])
	d["anchor"] = anchor
	d["major"] = bool(ev["major"])
	d["count"] = _spawn_count(ev, int(ctx.get("active_director_threats", 0)), false)
	d["reason"] = "forced (debug)"
	_mark_fired(event_id, ev)
	_log("FORCED %s%s" % [event_id, _anchor_suffix(anchor)])
	return d


# --- Decision --------------------------------------------------------------------------------

func _decide(d: Dictionary, ctx: Dictionary, intensity: int) -> Dictionary:
	stats["decisions"] = int(stats["decisions"]) + 1
	var rejected: Array = []
	var eligible: Array = []            # [{id, anchors: Array}]
	for id in event_ids:
		var ev: Dictionary = events[id]
		var why := _ineligible_reason(id, ev, ctx, intensity)
		var valid_anchors: Array = []
		if why == "" and String(ev["anchor"]) != "":
			var check := _validate_anchors(ev, ctx)
			valid_anchors = check["valid"]
			why = String(check["reason"])
		if why == "":
			eligible.append({"id": id, "anchors": valid_anchors})
		else:
			rejected.append({"id": id, "reason": why})
	d["rejected"] = rejected
	d["eligible_count"] = eligible.size()
	var rate := _event_rate(intensity)
	var total := 0.0
	var weights: Array[float] = []
	for e in eligible:
		var eid := String(e["id"])
		var w := float(events[eid]["weight"]) * rate * _repeat_factor(eid, eligible.size()) * _fatigue_factor(eid) * _major_ramp(events[eid])
		weights.append(w)
		total += w
	var nm: Dictionary = tuning["nothing_mult"]
	var nothing_w := float(tuning["do_nothing_weight"]) * float(nm.get(state, 1.0))
	if eligible.is_empty() or total <= 0.0:
		stats["nothing"] = int(stats["nothing"]) + 1
		d["reason"] = "nothing eligible"
		_log("nothing eligible | %s" % _rejections_text(rejected))
		return d
	# Stage 1: act or do nothing. The do-nothing option competes with one *typical* eligible event
	# (the mean weight), so the chance to act does not balloon when many events are eligible.
	# event_rate (intensity) and recency penalties are already folded into the weights.
	var act_w := total / float(eligible.size())
	var roll := rng.randf() * (act_w + nothing_w)
	if roll < nothing_w:
		stats["nothing"] = int(stats["nothing"]) + 1
		d["reason"] = "chose to do nothing (p=%.2f)" % (nothing_w / (act_w + nothing_w))
		_log("%s | options: %s | %s" % [d["reason"], _options_text(eligible, weights), _rejections_text(rejected)])
		return d
	# Stage 2: which event, by weight.
	roll = rng.randf() * total
	var pick := eligible.size() - 1
	for i in eligible.size():
		if roll < weights[i]:
			pick = i
			break
		roll -= weights[i]
	var chosen: Dictionary = eligible[pick]
	var id := String(chosen["id"])
	var ev: Dictionary = events[id]
	var anchor := _pick_anchor(ev, chosen["anchors"])
	d["event_id"] = id
	d["event"] = ev
	d["kind"] = String(ev["kind"])
	d["anchor"] = anchor
	d["major"] = bool(ev["major"])
	d["count"] = _spawn_count(ev, int(ctx.get("active_director_threats", 0)), true)
	d["reason"] = "chose %s (weight %.2f of %.2f, nothing %.2f)" % [id, weights[pick], total, nothing_w]
	_log("FIRE %s%s | %s | options: %s | %s" % [id, _anchor_suffix(anchor), d["reason"],
		_options_text(eligible, weights), _rejections_text(rejected)])
	_mark_fired(id, ev)
	if String(ev["kind"]) == "spawn":
		encounter_clear_time = 0.0
		_set_state("encounter", "ambush '%s'" % id)
	elif bool(ev["major"]):
		_enter_recovery(float(tuning["recovery_seconds"]), "major scare '%s'" % id)
	if not _undo.is_empty():
		_undo["after_state"] = state
	d["state"] = state
	return d


## Returns "" if the event may fire (ignoring anchors), otherwise a short human-readable reason.
func _ineligible_reason(id: String, ev: Dictionary, ctx: Dictionary, intensity: int) -> String:
	var zs: Array = ev["zones"]
	if not zs.has(zone):
		return "zone %s not in %s" % [zone, str(zs)]
	var sts: Array = ev["states"]
	if not sts.has(state):
		return "state %s not in %s" % [state, str(sts)]
	if int(ev["min_intensity"]) > intensity:
		return "intensity %s below %s" % [_intensity_name(intensity), _intensity_name(int(ev["min_intensity"]))]
	var major := bool(ev["major"])
	var itab: Dictionary = intensity_table.get(intensity, {})
	if major and not bool(itab.get("allow_major", true)):
		return "major scares are off at %s intensity" % _intensity_name(intensity)
	if bool(ev.get("once", false)) and fired_once.has(id):
		return "once-only, already happened"
	var needs := String(ev.get("needs_companion", ""))
	if needs != "" and String(ctx.get("companion", "")) != needs:
		return "needs companion %s present" % needs
	# An imitation of a companion (wrong_mochi) only works while the real one is NOT following Krystal.
	var absent := String(ev.get("absent_companion", ""))
	if absent != "" and String(ctx.get("companion", "")) == absent:
		return "companion %s is following (the imitation would fool nobody)" % absent
	if last_fired.has(id):
		var left := float(ev["cooldown"]) - (now - float(last_fired[id]))
		if left > 0.0:
			return "cooldown (%.0fs left)" % left
	var kind := String(ev["kind"])
	var spawn := kind == "spawn"
	if major:
		var mleft := major_cooldown_for(intensity) - (now - last_major_time)
		if mleft > 0.0:
			return "major cooldown (%.0fs left)" % mleft
		if int(ctx.get("active_director_threats", 0)) > 0:
			return "another major is still active (no stacking)"
	if (spawn or major) and float(ctx.get("player_hp_ratio", 1.0)) < float(tuning["low_hp_ratio"]):
		return "player health low (%.0f%%)" % (float(ctx.get("player_hp_ratio", 1.0)) * 100.0)
	if (spawn or major) and bool(ctx.get("retreating", false)):
		return "player is retreating"
	if spawn and int(ctx.get("threats_nearby", 0)) > 0:
		return "player already threatened"
	if spawn and int(ctx.get("enemies_nearby", 0)) > 0:
		return "the room's own enemies are close (no pile-on)"
	if kind == "glimpse" and bool(ctx.get("sprinting", false)):
		return "player sprinting (would miss it)"
	if spawn:
		var cnt: Array = ev.get("count", [1, 1])
		var cmin: int = int(cnt[0]) if cnt.size() > 0 else 1
		var active := int(ctx.get("active_director_threats", 0))
		var budget := int(tuning["max_active_threats"])
		if active + cmin > budget:
			return "threat budget full (%d/%d)" % [active, budget]
	return ""


## Checks every anchor of the required kind in the current zone. Returns {valid: Array, reason: String}.
func _validate_anchors(ev: Dictionary, ctx: Dictionary) -> Dictionary:
	var need := String(ev["anchor"])
	var kind := String(ev["kind"])
	var anchors: Array = ctx.get("anchors", [])
	var valid: Array = []
	var notes := PackedStringArray()
	var found := 0
	for i in anchors.size():
		if not anchors[i] is Dictionary:
			continue
		var a: Dictionary = anchors[i]
		if String(a.get("kind", "")) != need:
			continue
		var az := String(a.get("zone", ""))
		if az != "" and az != zone:
			continue
		found += 1
		var why := _anchor_problem(kind, a)
		if why == "":
			valid.append(a)
		else:
			notes.append("%s %s" % [_anchor_name(a, i), why])
	if found == 0:
		return {"valid": [], "reason": "no %s anchor in %s" % [need, zone]}
	if valid.is_empty():
		return {"valid": [], "reason": "no usable %s anchor (%s)" % [need, "; ".join(notes)]}
	return {"valid": valid, "reason": ""}


func _anchor_problem(kind: String, a: Dictionary) -> String:
	var dist := float(a.get("dist", 0.0))
	var vis := bool(a.get("visible", false))
	match kind:
		"spawn":
			if dist < float(tuning["min_spawn_distance"]):
				return "too close (%.1fm < %.0fm)" % [dist, float(tuning["min_spawn_distance"])]
			if dist > float(tuning["max_spawn_distance"]):
				return "too far (%.1fm > %.0fm)" % [dist, float(tuning["max_spawn_distance"])]
			if vis:
				return "visible to the player"
		"glimpse":
			if dist < float(tuning["glimpse_min_distance"]):
				return "too close (%.1fm < %.0fm)" % [dist, float(tuning["glimpse_min_distance"])]
			if dist > float(tuning["glimpse_max_distance"]):
				return "too far (%.1fm > %.0fm)" % [dist, float(tuning["glimpse_max_distance"])]
			if not vis:
				return "not in view"
		"notice":
			if dist > float(tuning["notice_max_distance"]):
				return "too far (%.1fm)" % dist
		"scratch":
			if dist > float(tuning["scratch_max_distance"]):
				return "too far (%.1fm)" % dist
		"stalker_pass":
			if dist > float(tuning["stalker_max_distance"]):
				return "too far (%.1fm)" % dist
		"sound", "wrong_sound":
			if dist > float(tuning["sound_anchor_max_distance"]):
				return "too far (%.1fm)" % dist
		_:
			if dist > float(tuning["default_anchor_max_distance"]):
				return "too far (%.1fm)" % dist
	return ""


func _pick_anchor(ev: Dictionary, valid: Array) -> Dictionary:
	if valid.is_empty():
		return {}
	var pool: Array = valid
	var kind := String(ev["kind"])
	if kind == "sound" or kind == "wrong_sound":
		# Sounds are scarier from where the player is not looking.
		var hidden: Array = []
		for a in valid:
			if not bool(a.get("visible", false)):
				hidden.append(a)
		if not hidden.is_empty():
			pool = hidden
	if pool.size() == 1:
		return pool[0]
	return pool[rng.randi_range(0, pool.size() - 1)]


func _spawn_count(ev: Dictionary, active: int, use_rng: bool) -> int:
	if String(ev["kind"]) != "spawn":
		return 0
	var cnt: Array = ev.get("count", [1, 1])
	var cmin: int = int(cnt[0]) if cnt.size() > 0 else 1
	var cmax: int = int(cnt[1]) if cnt.size() > 1 else cmin
	var room := int(tuning["max_active_threats"]) - active
	cmax = mini(cmax, room)
	if cmax <= cmin:
		return maxi(mini(cmin, room), 0)
	if not use_rng:
		return cmin
	return rng.randi_range(cmin, cmax)


func _repeat_factor(id: String, eligible_count: int) -> float:
	var idx := recent.find(id)
	if idx < 0:
		return 1.0
	var pens: Array = tuning["repeat_penalties"]
	var f: float = float(pens[idx]) if idx < pens.size() else 1.0
	if idx == 0 and eligible_count <= 1:
		f = maxf(f, float(tuning["repeat_only_option_factor"]))
	return f


## Time-based memory on top of the recency list: an event heard several times in the last few
## minutes becomes less likely, so no single cue (pebbles, creaks) dominates a whole zone.
func _fatigue_factor(id: String) -> float:
	var uses := 0
	var window := float(tuning["fatigue_window"])
	for h in history:
		if String(h[1]) == id and now - float(h[0]) <= window:
			uses += 1
	return 1.0 / (1.0 + float(tuning["fatigue_per_use"]) * float(mini(uses, 4)))


## Majors become more likely the longer anticipation lasts, so a long build-up tends to pay off
## before it relaxes (anticipation_max).
func _major_ramp(ev: Dictionary) -> float:
	if not bool(ev["major"]) or state != "anticipation":
		return 1.0
	var t := clampf(time_in_state / maxf(float(tuning["anticipation_max"]), 1.0), 0.0, 1.0)
	return 1.0 + float(tuning["major_ramp"]) * t


func _mark_fired(id: String, ev: Dictionary) -> void:
	_undo = {"id": id, "last_event_time": last_event_time, "last_major_time": last_major_time,
		"was_once": fired_once.has(id), "state": state, "after_state": state, "time_in_state": time_in_state,
		"time": now, "major": bool(ev["major"])}
	last_event_time = now
	last_fired[id] = now
	history.append([now, id])
	var window := float(tuning["fatigue_window"])
	while not history.is_empty() and (now - float(history[0][0]) > window or history.size() > 64):
		history.pop_front()
	if bool(ev.get("once", false)):
		fired_once[id] = true
	if bool(ev["major"]):
		last_major_time = now
		stats["majors"] = int(stats["majors"]) + 1
	recent.push_front(id)
	var pens: Array = tuning["repeat_penalties"]
	while recent.size() > maxi(pens.size(), 1):
		recent.pop_back()
	stats["fired"] = int(stats["fired"]) + 1
	var be: Dictionary = stats["by_event"]
	be[id] = int(be.get(id, 0)) + 1
	var bs: Dictionary = stats["by_state"]
	bs[state] = int(bs.get(state, 0)) + 1
	next_decision_at = maxf(next_decision_at, now + float(tuning["decision_interval"]))


# --- State machine -----------------------------------------------------------------------------

func _update_tension_state() -> void:
	var ua := float(tuning["unease_after"])
	var aa := float(tuning["anticipation_after"])
	if state == "calm" and tension >= ua:
		_set_state("unease", "tension %.0fs" % tension)
	if state == "unease" and tension >= aa:
		_set_state("anticipation", "tension %.0fs" % tension)
	if state == "anticipation" and time_in_state >= float(tuning["anticipation_max"]):
		tension = ua
		_set_state("unease", "nothing came of it; tension eases")


func _enter_recovery(seconds: float, reason: String) -> void:
	recovery_left = maxf(recovery_left if state == "recovery" else 0.0, seconds)
	encounter_clear_time = 0.0
	if state != "recovery":
		_set_state("recovery", "%s (%.0fs)" % [reason, recovery_left])
	else:
		_log("recovery extended to %.0fs: %s" % [recovery_left, reason])


func _set_state(new_state: String, reason: String) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	time_in_state = 0.0
	stats["transitions"] = int(stats["transitions"]) + 1
	_log("state %s -> %s: %s" % [old, new_state, reason])
	state_changed.emit(new_state, reason)


func _on_zone_changed(z: String) -> void:
	var was_active := director_zones.has(zone)
	var is_active := director_zones.has(z)
	_log("zone %s -> %s" % [zone if zone != "" else "-", z if z != "" else "-"])
	zone = z
	time_in_zone = 0.0
	if is_active and was_active:
		# A new space is a small breather: keep some unease but restart the build-up.
		var ua := float(tuning["unease_after"])
		if tension > ua:
			tension = ua
			if state == "anticipation":
				_set_state("unease", "new zone")
	elif is_active:
		next_decision_at = maxf(next_decision_at, now + float(tuning["start_grace"]))


# --- Helpers ----------------------------------------------------------------------------------------

func _new_decision() -> Dictionary:
	return {"event_id": "", "reason": "", "rejected": [], "state": state, "cancel": false,
		"anchor": {}, "event": {}, "kind": "", "count": 0, "major": false, "eligible_count": 0, "time": now}


func _event_rate(intensity: int) -> float:
	var itab: Dictionary = intensity_table.get(intensity, {})
	return float(itab.get("event_rate", 1.0))


func _intensity_name(i: int) -> String:
	var itab: Dictionary = intensity_table.get(i, {})
	return String(itab.get("name", str(i)))


func _anchor_name(a: Dictionary, i: int) -> String:
	var n := String(a.get("name", ""))
	return n if n != "" else "%s#%d" % [String(a.get("kind", "?")), i]


func _anchor_suffix(a: Dictionary) -> String:
	if a.is_empty():
		return ""
	return " @%s (%.1fm%s)" % [String(a.get("name", a.get("kind", "?"))), float(a.get("dist", 0.0)),
		", visible" if bool(a.get("visible", false)) else ""]


func _options_text(eligible: Array, weights: Array[float]) -> String:
	var parts := PackedStringArray()
	for i in eligible.size():
		parts.append("%s=%.2f" % [String(eligible[i]["id"]), weights[i]])
	return ", ".join(parts)


func _rejections_text(rejected: Array) -> String:
	if rejected.is_empty():
		return "no rejections"
	var parts := PackedStringArray()
	for r in rejected:
		parts.append("%s: %s" % [String(r["id"]), String(r["reason"])])
	return "rejected " + "; ".join(parts)


func _log(text: String) -> void:
	var line := "[%7.1fs %s %s] %s" % [now, state, zone if zone != "" else "-", text]
	debug_log.append(line)
	var limit := int(tuning.get("log_limit", 400))
	while debug_log.size() > limit:
		debug_log.pop_front()
	if _log_file != null:
		_log_file.store_line(line)
		_log_file.flush()
