extends RefCounted
## Music selection core of the MusicDirector (src/audio/music_director.gd). Pure logic: no scene
## access, no Audio calls and no global RNG (its own RandomNumberGenerator, seeded by the caller), so
## music randomness never changes gameplay random outcomes. The director feeds it a context a few
## times per second and applies the decisions it returns.
##
##   setup(data: Dictionary, seed: int, tuning_override := {})   data = res://data/music.gd catalogue()
##   update(ctx: Dictionary, dt: float) -> Dictionary
##     ctx keys (all optional): mode (Game.mode), area, zone, hint (music_context_changed), night, late,
##       paused, muted, threat (raw: an engaged enemy is near), boss (boss id or ""), boss_phase,
##       horror_state, silence (authored silence active), audio_track (what Audio plays; leave it out
##       when nothing reports it), pos_s (playback position, -1 unknown), track_len_s, track_bpm,
##       track_bar_beats
##     returns {"action": "play" | "stop" | "layers" | "none", "cue", "track", "layers", "fade",
##       "wait_s", "context", "reason"} (+ "prefetch": track about to be needed)
##   request(context_id, fade := -1.0, area := "") / release(context_id, fade := -1.0)
##   set_available(dict), play_failed(cue), clear_combat(), reset_area(), snap_base(), state(),
##   draw(playlist_id), base_for(area, zone, hint), static beat_wait(...), get_debug_log()
##
## Priority chain (MP 18.2): muted/paused policy -> authored ending/cutscene requests (and the title)
## -> active boss (phase layers) -> authored horror suppression (fade out) -> ordinary combat
## (enter after ~1 s of sustained threat, release 4-8 s after it cleared; never latched under a playable boss
## context and reset when it ends, so a boss hands straight back to the area) -> safe refuge -> regional
## exploration -> ambience only. Base contexts (refuge/exploration/ambience) change only after the
## zone held for region_enter_s and the previous one lasted min_dwell_s; exploration changes wait for
## the current piece's phrase boundary. Pieces rotate from shuffle bags with rests in between.
##
## Music Box (MP 18.3, src/audio/music_box.gd): a home feature, never a global override.
##   request_preview(cue, fade := -1.0, area := "") -> bool, stop_preview(fade := -1.0), preview_cue(),
##   preview_playlist()
##   The "musicbox" context (data/music.gd CONTEXTS["musicbox"]; PREVIEW_DEF is only the fallback added when an
##   older catalogue lacks it; its one-cue playlist is the context's own "playlist") sits above the regional base
##   (safe 30 / explore 20) and below everything else: ordinary combat, horror suppression, bosses, authored
##   requests and the title. Any of those ENDS the preview (the request is dropped, not resumed), as do death,
##   leaving the area and an unplayable cue. It plays one pass of the chosen cue ("once"), cuts in at once,
##   and on Stop fades out and lets the Haven rotation return after a short rest (like a boss recovery).
##   set_favourites(list) (or ctx key "favourites"): favourite cues get extra, bounded weight in the Haven's
##   own rotation (FAVOURITE_CONTEXTS, only while it is the base context): every piece of the Haven playlist
##   still plays once per round, plus at most FAV_BONUS_PER_ROUND favourite entries (each favourite at most
##   once per round), shuffled with this selector's own RNG (deterministic per seed).

const ACTIVE_MODES := ["playing", "cutscene", "dead", "loading", "title"]
const FROZEN_MODES := ["cutscene", "dead", "loading"]    # base/combat frozen, authored requests still apply
const HOLD_KINDS := ["combat", "boss", "ending", "menu", "musicbox"]  # never held past their reason
const BASE_KINDS := ["safe", "explore", "ambience"]
const PREVIEW_CONTEXT := "musicbox"
const PREVIEW_PLAYLIST := "~musicbox"
## Fallback only (a catalogue without a "musicbox" context): the same values as data/music.gd CONTEXTS["musicbox"].
const PREVIEW_DEF := {"kind": "musicbox", "priority": 40, "playlist": PREVIEW_PLAYLIST, "mode": "once",
	"fade": 1.5, "exit_fade": 1.5}
const FAVOURITE_CONTEXTS := ["haven"]
const FAVOURITE_KINDS := ["safe", "explore", "ending"]   # also the only kinds a preview may play
const FAV_BONUS_PER_ROUND := 2
const FAV_BAG_SUFFIX := "~fav"
const OVERRIDE_PRIORITY := 80     # contexts at/above this override a track started outside the director
const LOG_MAX := 50
const KEEP := "~keep"
const EPS := 0.0005

var cues: Dictionary = {}
var playlists: Dictionary = {}
var contexts: Dictionary = {}
var areas: Dictionary = {}
var area_combat: Dictionary = {}
var bosses: Dictionary = {}
var tuning: Dictionary = {}
var rng := RandomNumberGenerator.new()
var seed_used: int = 0
var available: Dictionary = {}    # cue id / layer track -> bool (a missing key counts as available)
var combat: bool = false          # ordinary combat, after hysteresis
var debug_log: Array = []         # last LOG_MAX decisions and notes (read through get_debug_log())
var favourites: Array = []        # Music Box favourites (cue ids, as given; unknown ids are ignored)

var _has_data := false
var _now := 0.0
var _requests: Dictionary = {}    # context id -> {"fade", "area", "t"}
var _released: Dictionary = {}    # context id -> fade (released since the last update)
# base context hysteresis
var _base := ""
var _base_area := "~"             # "~" = nothing committed yet (next base commits at once)
var _base_since := -1.0e9
var _cand := ""
var _cand_t := 0.0
var _arrival := false             # the base was just committed because Krystal arrived somewhere
# combat hysteresis
var _threat_t := 0.0
var _clear_t := 0.0
var _release_s := 6.0
var _boss_on := false             # a boss context could sound on the last update (see _wanted)
# what is sounding
var _eff := ""                    # context being served ("" = none)
var _cue := ""
var _track := ""
var _layers: Array = []
var _phase := "idle"              # idle | playing | ended | resting | silent | external
var _variant := ""                # playlist the current piece came from
var _piece_t := 0.0
var _piece_len := 0.0
var _piece_loop := false
var _rest_left := 0.0
var _next_cue := ""
var _last_played := ""
var _sig_at: Dictionary = {}      # context id -> time its signature last played
var _bags: Dictionary = {}        # playlist id -> cues left in this round
var _last_drawn: Dictionary = {}  # playlist id -> last cue drawn
var _external := ""
var _external_t := 0.0
var _prev: Dictionary = {}
var _preview_cue := ""            # the Music Box cue of the current / last preview request


func setup(data: Dictionary, seed_value: int, tuning_override: Dictionary = {}) -> void:
	cues = data.get("cues", {})
	# own (writable) copies: the Music Box adds its preview context and one-cue playlist
	var pls: Dictionary = data.get("playlists", {})
	playlists = pls.duplicate()
	var cxs: Dictionary = data.get("contexts", {})
	contexts = cxs.duplicate()
	areas = data.get("areas", {})
	area_combat = data.get("area_combat", {})
	bosses = data.get("bosses", {})
	var t: Dictionary = data.get("tuning", {})
	tuning = t.duplicate(true)
	tuning.merge(tuning_override, true)
	_has_data = not cues.is_empty() and not contexts.is_empty()
	# data/music.gd carries the "musicbox" context; an older catalogue without it gets the built-in definition
	if _has_data and not contexts.has(PREVIEW_CONTEXT):
		contexts[PREVIEW_CONTEXT] = PREVIEW_DEF.duplicate()
	reseed(seed_value)
	reset()


## New seed for the selector's own RNG (bags restart). Never touches the global RNG.
func reseed(seed_value: int) -> void:
	seed_used = seed_value
	rng.seed = seed_value
	_bags.clear()
	_last_drawn.clear()


## Forgets everything that is sounding or pending (data, seed and availability stay).
func reset() -> void:
	_now = 0.0
	_requests.clear()
	_released.clear()
	_base = ""
	_base_area = "~"
	_base_since = -1.0e9
	_cand = ""
	_cand_t = 0.0
	_arrival = false
	clear_combat()
	_boss_on = false
	_eff = ""
	_cue = ""
	_track = ""
	_layers = []
	_phase = "idle"
	_variant = ""
	_piece_t = 0.0
	_piece_len = 0.0
	_piece_loop = false
	_rest_left = 0.0
	_next_cue = ""
	_last_played = ""
	_sig_at.clear()
	_external = ""
	_external_t = 0.0
	_prev = {}
	_preview_cue = ""


func set_available(avail: Dictionary) -> void:
	for k in avail:
		available[k] = bool(avail[k])


func is_available(key: String) -> bool:
	return key != "" and bool(available.get(key, true))


## An authored scene asks for a context (restoration, celebration, title, a boss...). Requesting an
## active one again changes nothing (no restart). The request lives in `area` (dropped elsewhere).
func request(context_id: String, fade: float = -1.0, area: String = "") -> void:
	if not contexts.has(context_id):
		_note("unknown context '%s' requested" % context_id)
		return
	if _requests.has(context_id):
		return
	_requests[context_id] = {"fade": fade, "area": area, "t": _now}
	_note("request %s" % context_id)


func release(context_id: String, fade: float = -1.0) -> void:
	if context_id == "":
		return
	if _requests.has(context_id):
		_requests.erase(context_id)
		_note("release %s" % context_id)
	_released[context_id] = fade


func has_request(context_id: String) -> bool:
	return _requests.has(context_id)


func clear_combat() -> void:
	combat = false
	_threat_t = 0.0
	_clear_t = 0.0


## Krystal left the area: the next base context commits immediately, combat and requests end.
func reset_area() -> void:
	_base_area = "~"
	_cand = ""
	_cand_t = 0.0
	clear_combat()
	for id in _requests.keys():
		if String(id) != "title":
			_requests.erase(id)


## Krystal moved without walking (respawn, teleport): skip the region hysteresis once.
func snap_base() -> void:
	_base_area = "~"


## The director could not start `cue` (file missing or not importable): never try it again this
## session and choose again on the next update. The previous music keeps playing meanwhile.
func play_failed(cue: String) -> void:
	available[cue] = false
	_note("could not play %s: skipped from now on" % cue)
	_cue = String(_prev.get("cue", ""))
	_track = String(_prev.get("track", ""))
	_phase = String(_prev.get("phase", "idle"))
	_layers = []
	_eff = ""
	if cue == _preview_cue:
		_end_preview("its file could not be played")


# ---------------------------------------------------------------------------------------------
# Music Box: preview and favourites
# ---------------------------------------------------------------------------------------------

## Previews one cue from the Music Box (one pass, then the base music returns). False (nothing changes)
## when the cue is unknown, known to be unplayable, or not a safe / explore / ending piece (a boss, combat
## or horror cue never plays at the Music Box's low priority). Asking for another cue while one plays
## switches at once; asking for the same one again changes nothing. The request lives in `area` like any other.
func request_preview(cue: String, fade: float = -1.0, area: String = "") -> bool:
	if not _has_data or not contexts.has(PREVIEW_CONTEXT):
		return false
	if not cues.has(cue) or not is_available(cue) \
			or not FAVOURITE_KINDS.has(String((cues[cue] as Dictionary).get("kind", ""))):
		_note("music box: '%s' cannot be previewed" % cue)
		return false
	_released.erase(PREVIEW_CONTEXT)
	if _requests.has(PREVIEW_CONTEXT) and cue == _preview_cue:
		return true
	_preview_cue = cue
	var pl := preview_playlist()
	playlists[pl] = {"cues": [cue], "fallback": ["keep"]}      # this selector's own copy, never the catalogue
	_bags.erase(pl)
	_last_drawn.erase(pl)
	if _eff == PREVIEW_CONTEXT:
		_eff = ""                 # re-plan now: the new cue replaces the one playing (or the finished one)
	_requests[PREVIEW_CONTEXT] = {"fade": fade, "area": area, "t": _now}
	_note("music box preview %s" % cue)
	return true


## Stop pressed (or Krystal left the house): the preview fades out, the Haven music returns after a rest.
func stop_preview(fade: float = -1.0) -> void:
	release(PREVIEW_CONTEXT, fade)


## The playlist the "musicbox" context draws from (the context's own "playlist"; PREVIEW_PLAYLIST when it names none).
func preview_playlist() -> String:
	var pl := String((contexts.get(PREVIEW_CONTEXT, {}) as Dictionary).get("playlist", ""))
	return pl if pl != "" else PREVIEW_PLAYLIST


## The cue the Music Box is previewing ("" when no preview is requested any more).
func preview_cue() -> String:
	return _preview_cue if _requests.has(PREVIEW_CONTEXT) else ""


func _end_preview(why: String) -> void:
	if _requests.has(PREVIEW_CONTEXT):
		_requests.erase(PREVIEW_CONTEXT)
		_note("music box preview of %s ended: %s" % [_preview_cue, why])


## Favourite cue ids (Music Box). Anything not in the catalogue, of the wrong kind or unplayable is
## ignored when drawing, so a renamed cue never breaks the rotation. Bags restart only on a change.
func set_favourites(list: Array) -> void:
	if list == favourites:
		return
	var out: Array = []
	for f in list:
		if (f is String or f is StringName) and not out.has(String(f)):
			out.append(String(f))
	if out == favourites:
		return
	favourites = out
	for k in _bags.keys():
		if String(k).ends_with(FAV_BAG_SUFFIX):
			_bags.erase(k)
	_note("favourites: %s" % str(favourites))


## Favourites that may join a rotation: known cues of a safe/explore/ending kind that are playable.
func usable_favourites() -> Array:
	var out: Array = []
	for f in favourites:
		var c: Dictionary = cues.get(f, {})
		if not c.is_empty() and FAVOURITE_KINDS.has(String(c.get("kind", ""))) and is_available(String(f)):
			out.append(String(f))
	return out


## True when context `id` rotates with the favourites mixed in: the Haven, while it is the base context
## (an authored request for the same context elsewhere, e.g. a remembered fragment, stays unweighted).
func _favoured(id: String) -> bool:
	return not favourites.is_empty() and FAVOURITE_CONTEXTS.has(id) and id == _base and not _requests.has(id)


func current_track() -> String:
	return _track


func current_cue() -> String:
	return _cue


func state() -> Dictionary:
	return {"effective": _eff, "base": _base, "candidate": _cand, "cue": _cue, "track": _track,
		"layers": _layers.duplicate(), "phase": _phase, "combat": combat, "rest_left": _rest_left,
		"external": _external, "requests": _requests.keys(), "variant": _variant, "seed": seed_used,
		"preview": preview_cue(), "favourites": favourites.duplicate()}


func get_debug_log() -> Array:
	return debug_log.duplicate(true)


# ---------------------------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------------------------

func update(ctx: Dictionary, dt: float) -> Dictionary:
	if not _has_data:
		return _none("no music data")
	_now += dt
	var fv: Variant = ctx.get("favourites")
	if fv is Array:
		set_favourites(fv)
	var mode := String(ctx.get("mode", ""))
	var area := String(ctx.get("area", ""))
	_expire_requests(mode, area)
	if not ACTIVE_MODES.has(mode):
		# not in a running game (boot, tools, tests): leave the music alone
		_released.clear()
		clear_combat()
		return _none("idle")
	_track_audio(ctx, dt)
	if bool(ctx.get("paused", false)) or bool(ctx.get("muted", false)):
		# menus never restart the music and a muted bus loads nothing: keep everything as it is
		return _none("paused")
	var want := _wanted(ctx, dt, mode, area)
	var d := _serve(want, ctx, dt)
	_released.clear()
	if String(d["action"]) != "none":
		_log(d)
	return d


func _expire_requests(mode: String, area: String) -> void:
	for id in _requests.keys():
		var sid := String(id)
		var r: Dictionary = _requests[sid]
		var keep := true
		if not ACTIVE_MODES.has(mode):
			keep = false
		elif sid == "title":
			keep = mode == "title"
		elif mode == "title":
			keep = false
		elif mode != "loading" and String(r.get("area", "")) != area:
			keep = false
		if not keep:
			_requests.erase(sid)


func _wanted(ctx: Dictionary, dt: float, mode: String, area: String) -> String:
	if mode == "title":
		return "title" if _requests.has("title") and _playable("title", ctx) else ""
	var best := ""
	var best_p := -1
	for id in _requests:
		var sid := String(id)
		if sid == "title" or sid == PREVIEW_CONTEXT or not contexts.has(sid):
			continue
		var p := _priority(sid)
		if p > best_p and _playable(sid, ctx):
			best = sid
			best_p = p
	var bc := String(bosses.get(String(ctx.get("boss", "")), ""))
	if bc != "" and contexts.has(bc) and _priority(bc) > best_p and _playable(bc, ctx):
		best = bc
		best_p = _priority(bc)
	# A boss fight owns its threat (the boss itself is an enemy near Krystal): the ordinary combat latch never
	# builds underneath a playable boss context, and when that context ends it starts again from nothing, so a
	# combat cue follows a boss only after the usual sustained threat from an enemy that is still there (CH2-008).
	var boss_on := _boss_music_on(bc, ctx)
	if boss_on or _boss_on:
		if combat or _threat_t > 0.0 or _clear_t > 0.0:
			clear_combat()
		if boss_on != _boss_on:
			_note("boss music %s: the ordinary combat latch starts again from nothing" % ("on" if boss_on else "over"))
	_boss_on = boss_on
	var frozen := FROZEN_MODES.has(mode)
	if not frozen:
		_update_combat(bool(ctx.get("threat", false)), dt)
		_update_base(ctx, dt, area)
	# Music Box preview: only above the regional base; everything else ends it (never resumed)
	var preview := _requests.has(PREVIEW_CONTEXT)
	if preview and not _playable(PREVIEW_CONTEXT, ctx):
		_end_preview("not playable")
		preview = false
	if preview and mode == "dead":
		_end_preview("Krystal fainted")
		preview = false
	if best != "":
		if preview:
			_end_preview("%s took over" % best)
		return best
	if frozen:
		return PREVIEW_CONTEXT if preview else ""
	if _silenced(ctx) and contexts.has("silence"):
		if preview:
			_end_preview("horror suppression")
		return "silence"
	if combat:
		var cc := _combat_context(area)
		if cc != "" and _playable(cc, ctx):
			if preview:
				_end_preview("%s took over" % cc)
			return cc
	if preview and _priority(PREVIEW_CONTEXT) > _priority(_base):
		return PREVIEW_CONTEXT
	return _base


## True while a boss context can sound: the reported boss's own context (bc) or an authored boss-kind request
## (the legacy Weaver asks for "boss_matron" itself). An unplayable boss context does not count, so ordinary
## combat music still stands in for it then.
func _boss_music_on(bc: String, ctx: Dictionary) -> bool:
	if bc != "" and contexts.has(bc) and _playable(bc, ctx):
		return true
	for id in _requests:
		var sid := String(id)
		if contexts.has(sid) and _kind(sid) == "boss" and _playable(sid, ctx):
			return true
	return false


func _update_combat(threat: bool, dt: float) -> void:
	if threat:
		_threat_t += dt
		_clear_t = 0.0
		if not combat and _threat_t >= _tf("combat_enter_s", 1.0) - EPS:
			combat = true
			_release_s = _roll("combat_release_s", [4.0, 8.0], false)
			_note("combat: threat held %.1f s (release %.1f s after it clears)" % [_threat_t, _release_s])
	else:
		_threat_t = 0.0
		if combat:
			_clear_t += dt
			if _clear_t >= _release_s - EPS:
				combat = false
				_note("combat over (%.1f s clear)" % _clear_t)


func _update_base(ctx: Dictionary, dt: float, area: String) -> void:
	var cand := base_for(area, String(ctx.get("zone", "")), String(ctx.get("hint", "")))
	if area != _base_area:
		_base_area = area
		_commit_base(cand, "arrived (%s)" % area)
		_arrival = true
		return
	if cand == _base:
		_cand = ""
		_cand_t = 0.0
		return
	if cand != _cand:
		_cand = cand
		_cand_t = 0.0
	_cand_t += dt
	var need := float((contexts.get(cand, {}) as Dictionary).get("enter_s", _tf("region_enter_s", 10.0)))
	if _cand_t >= need - EPS and _now - _base_since >= _tf("min_dwell_s", 20.0) - EPS:
		_commit_base(cand, "zone held %.1f s" % _cand_t)


func _commit_base(cand: String, why: String) -> void:
	if cand != _base:
		_note("base %s -> %s (%s)" % [_base, cand, why])
	_base = cand
	_base_since = _now
	_cand = ""
	_cand_t = 0.0


## Base context for a place: an area hint naming a base context wins, then the zone, then the area.
func base_for(area: String, zone: String, hint: String = "") -> String:
	if hint != "" and contexts.has(hint) and BASE_KINDS.has(_kind(hint)):
		return hint
	var a: Dictionary = areas.get(area, {})
	if a.is_empty():
		return ""
	var z: Dictionary = a.get("zones", {})
	if z.has(zone):
		return String(z[zone])
	return String(a.get("default", ""))


func _silenced(ctx: Dictionary) -> bool:
	if bool(ctx.get("silence", false)):
		return true
	var states: Array = tuning.get("horror_silence_states", [])
	return states.has(String(ctx.get("horror_state", "")))


func _combat_context(area: String) -> String:
	return String(area_combat.get(area, area_combat.get("*", "")))


## False when a context has nothing to add (its music is missing and its fallback is "keep").
func _playable(id: String, ctx: Dictionary) -> bool:
	if not contexts.has(id):
		return false
	var pl := playlist_for(id, ctx)
	if pl == "":
		return true
	return _resolve_playlist(pl) != KEEP


func playlist_for(id: String, ctx: Dictionary) -> String:
	var c: Dictionary = contexts.get(id, {})
	if bool(ctx.get("night", false)) and c.has("night_playlist"):
		return String(c["night_playlist"])
	if bool(ctx.get("late", false)) and c.has("late_playlist"):
		return String(c["late_playlist"])
	return String(c.get("playlist", ""))


# ---------------------------------------------------------------------------------------------
# Serving the wanted context
# ---------------------------------------------------------------------------------------------

func _serve(want: String, ctx: Dictionary, dt: float) -> Dictionary:
	if _external != "":
		# (a Music Box preview is Krystal's own choice: it replaces a foreign track too)
		if want == "" or (_priority(want) < OVERRIDE_PRIORITY and want != PREVIEW_CONTEXT):
			if want != "" and want != _eff:
				_eff = want                  # what to play once the foreign track has gone
			return _none("foreign track '%s' left alone" % _external)
		_note("foreign track '%s' overridden by %s" % [_external, want])
		# the foreign track is still sounding: treat it as ours so the override replaces it (a boss)
		# or fades it out (horror silence) instead of re-noticing it on every update
		_cue = ""
		_track = _external
		_layers = []
		_phase = "playing"
		_external = ""
		_eff = ""                        # always re-plan (even when `want` was already the context)
	if want == "":
		return _hold()
	if want != _eff:
		return _switch(want, ctx, dt)
	_arrival = false          # arrived where the music already was (e.g. respawn in the same place)
	return _continue(ctx, dt)


## Nothing new is wanted (frozen modes, title without its request, unknown area): keep the music,
## except for contexts that must not outlive their reason (released requests, fights, the title).
func _hold() -> Dictionary:
	if _eff == "":
		return _none("hold")
	if _released.has(_eff) or HOLD_KINDS.has(_kind(_eff)):
		var f := float(_released.get(_eff, -1.0))
		if f < 0.0:
			f = _cf(_eff, "exit_fade", 3.0)
		var why := "%s ended" % _eff
		_eff = ""
		if _phase == "playing":
			return _stop(f, why)
		_phase = "silent"
		return _none(why)
	return _none("hold")


func _switch(to: String, ctx: Dictionary, dt: float) -> Dictionary:
	var from := _eff
	var arrival := _arrival
	_arrival = false
	var cut := "now" if arrival else _cut_for(from, to)
	var wait := 0.0
	if cut != "now" and _phase == "playing":
		var w := boundary_wait(cut, ctx)
		if w > dt + EPS:
			_arrival = arrival
			return _none("waiting %.1f s for a %s boundary (%s -> %s)" % [w, cut, from, to])
		wait = maxf(w, 0.0)
	var fade := _fade_for(from, to)
	var entry_rest := _entry_rest(from, to)
	# after a boss (or a stopped Music Box preview) the music settles first, then the area's own mood returns
	var boss_recovery := from != "" and (_kind(from) == "boss" or from == PREVIEW_CONTEXT) \
			and _ctx_mode(to) == "rotate" and _phase == "playing"
	_eff = to
	var why := "%s -> %s" % [from if from != "" else "-", to]
	var pl := playlist_for(to, ctx)
	if pl == "":
		return _silence(_tf("arrival_stop_s", 2.0) if arrival else fade, why + " (no music here)")
	if boss_recovery:
		# after a boss the music settles first, then the area's own mood returns
		var d := _stop(fade, why + " (recovery)")
		_rest(_roll("resume_rest_s", [5.0, 10.0], true), ctx)
		return d
	if entry_rest > 0.0:
		_rest(entry_rest, ctx)
		return _none(why + " (resting %.1f s first)" % entry_rest)
	var sig := _signature_due(to)
	if sig == "" and _phase == "playing" and _cue != "" and _cue_in(to, _cue, ctx):
		_variant = pl
		if to == PREVIEW_CONTEXT and _piece_loop:
			_piece_t = 0.0        # previewing the looping piece already playing: one full pass from now
		return _none("%s continues into %s" % [_cue, to])
	var cue := sig if sig != "" else _draw_for(to, ctx)
	if cue == "":
		# e.g. the Below while The Last Shift is not there yet: the old music fades like Chapter One's
		return _silence(_tf("arrival_stop_s", 2.0) if arrival else fade, why + " (nothing playable)")
	if cue == _cue and _phase == "playing":
		return _none("%s keeps playing" % cue)
	if arrival and BASE_KINDS.has(_kind(to)):
		fade = _tf("arrival_fade_s", 4.0)
	return _play(cue, fade, wait, why, ctx)


func _continue(ctx: Dictionary, dt: float) -> Dictionary:
	var mode := _ctx_mode(_eff)
	match _phase:
		"playing":
			if _kind(_eff) == "boss":
				var want_layers := _layers_for(_cue, ctx)
				if want_layers != _layers:
					_layers = want_layers
					return {"action": "layers", "cue": _cue, "track": _track, "layers": _layers.duplicate(),
						"fade": _cf(_eff, "layer_fade", 2.0), "wait_s": 0.0, "context": _eff,
						"reason": "boss phase %d" % int(ctx.get("boss_phase", 1))}
			if mode == "once" and _piece_loop:
				# a "once" context served by a looping piece (e.g. the celebration falling back to
				# the ending reprise) plays one pass, fades at its end, and then the request is over
				var ef1 := _tf("end_fade_s", 8.0)
				if _piece_t >= _planned_len(1) - ef1 - EPS:
					_requests.erase(_eff)
					_note("%s played once" % _eff)
					return _stop(ef1, "%s finished its one pass" % _cue)
				return _none("")
			if mode != "rotate":
				return _none("")
			var pl := playlist_for(_eff, ctx)
			if pl != _variant and not _is_signature_piece():
				if _cue_in(_eff, _cue, ctx):
					_variant = pl
				else:
					# day/night (or late) change: switch on the current piece's phrase, else at its end
					var w := boundary_wait("phrase", ctx)
					if w >= 0.0 and w <= dt + EPS:
						var nc := _draw_for(_eff, ctx)
						if nc != "" and nc != _cue:
							return _play(nc, _cf(_eff, "fade", 4.0), maxf(w, 0.0), "%s -> %s on a phrase" % [_variant, pl], ctx)
			if _piece_loop:
				var ef := _tf("end_fade_s", 8.0)
				if _piece_t >= _planned_len() - ef - EPS:
					var d := _stop(ef, "%s finished its turn" % _cue)
					_rest(_roll_rest(_eff) + ef, ctx)
					d["prefetch"] = _prefetch_track()
					return d
			return _none("")
		"ended":
			return _after_piece(ctx)
		"resting":
			_rest_left -= dt
			if _rest_left > EPS:
				return _none("")
			var cue := _next_cue
			_next_cue = ""
			if cue == "" or not is_available(cue) or not (_cue_in(_eff, cue, ctx) or _is_signature_cue(_eff, cue)):
				cue = _draw_for(_eff, ctx)
			if cue == "":
				_phase = "silent"
				return _none("nothing to play in %s" % _eff)
			return _play(cue, _cf(_eff, "fade", 3.0), 0.0, "next piece in %s" % _eff, ctx)
	return _none("")


## A non-looping piece reached its end (or someone stopped ours).
func _after_piece(ctx: Dictionary) -> Dictionary:
	var mode := _ctx_mode(_eff)
	var was := _cue
	_cue = ""
	_track = ""
	_layers = []
	if mode == "once":
		_requests.erase(_eff)
		_note("%s played once" % _eff)
		_phase = "silent"
		return _none("%s done" % was)
	if mode == "loop":
		_rest(1.0, ctx)
		return _none("%s stopped: again shortly" % was)
	_rest(_roll_rest(_eff), ctx)
	var d := _none("%s ended, resting %.0f s" % [was, _rest_left])
	d["prefetch"] = _prefetch_track()
	return d


func _rest(seconds: float, ctx: Dictionary) -> void:
	_phase = "resting"
	_rest_left = seconds
	_next_cue = _draw_for(_eff, ctx) if _eff != "" else ""


func _prefetch_track() -> String:
	return String((cues.get(_next_cue, {}) as Dictionary).get("track", "")) if _next_cue != "" else ""


func _silence(fade: float, why: String) -> Dictionary:
	_next_cue = ""
	if _phase == "playing":
		return _stop(fade, why)
	_phase = "silent"
	_cue = ""
	_track = ""
	return _none(why)


func _cut_for(from: String, to: String) -> String:
	if _phase != "playing" or from == "":
		return "now"
	var kt := _kind(to)
	var kf := _kind(from)
	if kt in ["boss", "ending", "menu", "horror", "musicbox"]:
		return "now"
	if kt == "combat":
		return _cs(to, "cut", "beat")
	if kf in ["combat", "boss", "ending", "menu", "horror", "musicbox"]:
		return "now"
	return _cs(to, "cut", "phrase")


func _fade_for(from: String, to: String) -> float:
	var r: Dictionary = _requests.get(to, {})
	if float(r.get("fade", -1.0)) >= 0.0:
		return float(r["fade"])
	if from != "" and float(_released.get(from, -1.0)) >= 0.0:
		return float(_released[from])
	if from != "" and HOLD_KINDS.has(_kind(from)):
		return _cf(from, "exit_fade", 3.0)
	return _cf(to, "fade", 3.0)


## Quiet before a rotation starts: only when coming back from silence (horror, a stopped piece).
func _entry_rest(from: String, to: String) -> float:
	if from == "" or _ctx_mode(to) != "rotate" or _phase == "playing":
		return 0.0
	return _roll("resume_rest_s", [5.0, 10.0], true)


func _signature_due(id: String) -> String:
	var c: Dictionary = contexts.get(id, {})
	var sig := String(c.get("signature", ""))
	if sig == "":
		return ""
	if _now - float(_sig_at.get(id, -1.0e9)) < _tf("signature_cooldown_s", 600.0) - EPS:
		return ""
	var cue := _draw_available(sig)
	if cue == "":
		return ""
	_sig_at[id] = _now
	_variant = sig
	return cue


func _is_signature_piece() -> bool:
	var sig := String((contexts.get(_eff, {}) as Dictionary).get("signature", ""))
	return sig != "" and _variant == sig


func _is_signature_cue(id: String, cue: String) -> bool:
	var sig := String((contexts.get(id, {}) as Dictionary).get("signature", ""))
	return sig != "" and ((playlists.get(sig, {}) as Dictionary).get("cues", []) as Array).has(cue)


## True when `cue` is what context `id` would play now (a member of its current playlist, or the
## fallback that stands in for a playlist whose files are missing).
func _cue_in(id: String, cue: String, ctx: Dictionary) -> bool:
	if cue == "":
		return false
	var pl := playlist_for(id, ctx)
	if pl == "":
		return false
	var p: Dictionary = playlists.get(pl, {})
	if (p.get("cues", []) as Array).has(cue):
		return true
	if _favoured(id) and usable_favourites().has(cue):
		return true
	return _first_available(p) == "" and _fallback(p) == cue


func _draw_for(id: String, ctx: Dictionary) -> String:
	var pl := playlist_for(id, ctx)
	if pl == "":
		return ""
	var cue := draw_favoured(pl) if _favoured(id) else draw(pl)
	_variant = pl
	return "" if cue == KEEP else cue


# ---------------------------------------------------------------------------------------------
# Playlists and shuffle bags
# ---------------------------------------------------------------------------------------------

## Next cue of a playlist: shuffle bag (every available cue once per round, own RNG, never the same
## piece twice in a row - also across refills and after another playlist played it). Missing cues are
## skipped; a playlist with none available returns its fallback (a retained cue, KEEP or "").
func draw(pl: String) -> String:
	var p: Dictionary = playlists.get(pl, {})
	var avail := _available_cues(p)
	if avail.is_empty():
		return _fallback(p)
	return _draw_from(pl, avail)


## Like draw() but without fallback (signatures).
func _draw_available(pl: String) -> String:
	var avail := _available_cues(playlists.get(pl, {}))
	if avail.is_empty():
		return ""
	return _draw_from(pl, avail)


func _draw_from(pl: String, avail: Array) -> String:
	var bag: Array = []
	for c in (_bags.get(pl, []) as Array):
		if avail.has(c):
			bag.append(c)
	if bag.is_empty():
		bag = _refill(avail, String(_last_drawn.get(pl, "")))
	var cue := String(bag.pop_front())
	if cue == _last_played and avail.size() > 1:
		if bag.is_empty():
			bag = _refill(avail, cue)
		var alt := String(bag[0])
		bag[0] = cue
		cue = alt
	_bags[pl] = bag
	_last_drawn[pl] = cue
	return cue


func _refill(avail: Array, avoid: String) -> Array:
	var bag: Array = avail.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	if bag.size() > 1 and String(bag[0]) == avoid:
		var k := rng.randi_range(1, bag.size() - 1)
		var tmp2: Variant = bag[0]
		bag[0] = bag[k]
		bag[k] = tmp2
	return bag


## draw() with the Music Box favourites mixed in (bounded): a round is every available cue of the playlist
## once, plus one extra entry for at most FAV_BONUS_PER_ROUND favourites (a favourite of the playlist then
## plays twice in that round, a favourite from elsewhere joins as a guest once). The playlist's own pieces
## are always part of every round, so favourites are never the only thing playing. Own RNG only; never the
## same piece twice in a row. Without usable favourites this is exactly draw().
func draw_favoured(pl: String) -> String:
	var p: Dictionary = playlists.get(pl, {})
	var avail := _available_cues(p)
	if avail.is_empty():
		return _fallback(p)
	var favs := usable_favourites()
	if favs.is_empty():
		return _draw_from(pl, avail)
	var key := pl + FAV_BAG_SUFFIX
	var bag: Array = []
	for c in (_bags.get(key, []) as Array):
		if avail.has(c) or favs.has(c):
			bag.append(c)
	if bag.is_empty():
		bag = _refill_favoured(avail, favs, String(_last_drawn.get(key, "")))
	var cue := String(bag.pop_front())
	if cue == _last_played:
		var j := _index_other(bag, cue)
		if j < 0 and (_index_other(avail, cue) >= 0 or _index_other(favs, cue) >= 0):
			bag.append_array(_refill_favoured(avail, favs, cue))   # (only when another piece exists at all)
			j = _index_other(bag, cue)
		if j >= 0:
			var alt := String(bag[j])
			bag[j] = cue
			cue = alt
	_bags[key] = bag
	_last_drawn[key] = cue
	return cue


func _refill_favoured(avail: Array, favs: Array, avoid: String) -> Array:
	var pool: Array = favs.duplicate()
	_shuffle(pool)
	var bag: Array = avail.duplicate()
	for i in mini(FAV_BONUS_PER_ROUND, pool.size()):
		bag.append(pool[i])
	_shuffle(bag)
	if bag.size() > 1 and String(bag[0]) == avoid:
		var k := _index_other(bag, avoid)
		if k > 0:
			var tmp: Variant = bag[0]
			bag[0] = bag[k]
			bag[k] = tmp
	return bag


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


func _index_other(a: Array, cue: String) -> int:
	for i in a.size():
		if String(a[i]) != cue:
			return i
	return -1


func _available_cues(p: Dictionary) -> Array:
	var out: Array = []
	for c in (p.get("cues", []) as Array):
		if is_available(String(c)):
			out.append(String(c))
	return out


func _first_available(p: Dictionary) -> String:
	var a := _available_cues(p)
	return String(a[0]) if not a.is_empty() else ""


func _fallback(p: Dictionary) -> String:
	var fb: Variant = p.get("fallback", [])
	var list: Array = fb if fb is Array else [fb]
	for f in list:
		var s := String(f)
		if s == "keep":
			return KEEP
		if s == "":
			return ""
		if is_available(s):
			return s
	return ""


func _resolve_playlist(pl: String) -> String:
	var p: Dictionary = playlists.get(pl, {})
	var f := _first_available(p)
	return f if f != "" else _fallback(p)


func _layers_for(cue: String, ctx: Dictionary) -> Array:
	var ls: Array = (cues.get(cue, {}) as Dictionary).get("layers", [])
	var n := mini(maxi(int(ctx.get("boss_phase", 1)) - 1, 0), ls.size())
	var out: Array = []
	for i in n:
		var s := String(ls[i])
		if is_available(s):
			out.append(s)
	return out


# ---------------------------------------------------------------------------------------------
# What Audio is actually playing
# ---------------------------------------------------------------------------------------------

func _track_audio(ctx: Dictionary, dt: float) -> void:
	if _phase == "playing":
		_piece_t += dt
	var at_v: Variant = ctx.get("audio_track")
	var reported := at_v is String or at_v is StringName
	var at := String(at_v) if reported else ""
	var tl := float(ctx.get("track_len_s", 0.0))
	if tl > 0.0 and _phase == "playing" and (not reported or at == _track):
		_piece_len = tl
	if _external != "":
		if not reported:
			return
		if at == _external and _now - _external_t < _tf("external_max_s", 180.0):
			return
		_note("foreign track '%s' %s" % [_external, "gone" if at != _external else "timed out"])
		_external = ""
		_cue = ""
		_track = ""
		if at == "":
			_rest(_roll("resume_rest_s", [5.0, 10.0], true), ctx)
		else:
			_rest(0.0, ctx)
		return
	if reported:
		if at != "" and at != _track:
			var adopt := _cue_for_track(at)
			if adopt != "" and _eff != "" and _cue_in(_eff, adopt, ctx):
				_cue = adopt
				_track = at
				_phase = "playing"
				_piece_t = maxf(float(ctx.get("pos_s", 0.0)), 0.0)
				_piece_len = float((cues.get(adopt, {}) as Dictionary).get("len_s", 0.0))
				_piece_loop = bool((cues.get(adopt, {}) as Dictionary).get("loop", false))
				_note("adopted '%s' as %s" % [at, adopt])
			else:
				_external = at
				_external_t = _now
				_phase = "external"
				_cue = ""
				_track = ""
				_layers = []
				_note("foreign track '%s': backing off" % at)
			return
		if _phase == "playing" and at == "" and _piece_t > 0.5:
			_phase = "ended"
			return
	if _phase == "playing" and not _piece_loop and _piece_len > 0.0 and _piece_t >= _piece_len - EPS:
		_phase = "ended"


func _cue_for_track(track: String) -> String:
	for id in cues:
		if String((cues[id] as Dictionary).get("track", "")) == track:
			return String(id)
	return ""


## How long the current looping piece plays in its turn (passes x pass length). passes_override > 0
## replaces the cue's / tuning's pass count.
func _planned_len(passes_override: int = 0) -> float:
	var c: Dictionary = cues.get(_cue, {})
	var passes := int(c.get("passes", int(tuning.get("loop_passes", 2))))
	if passes_override > 0:
		passes = passes_override
	if _piece_len > 0.0:
		return float(maxi(passes, 1)) * _piece_len
	return _tf("loop_play_s", 170.0)


# ---------------------------------------------------------------------------------------------
# Musical time
# ---------------------------------------------------------------------------------------------

## Seconds until the current piece reaches the next `kind` boundary ("beat", "bar", "phrase"),
## -1 when its tempo is unknown.
func boundary_wait(kind: String, ctx: Dictionary) -> float:
	if _cue == "":
		return -1.0
	var pos := float(ctx.get("pos_s", -1.0))
	if pos < 0.0:
		pos = maxf(_piece_t, 0.0)
	return beat_wait(cues.get(_cue, {}), kind, pos, _piece_len, float(ctx.get("track_bpm", 0.0)),
		int(ctx.get("track_bar_beats", 0)), int(tuning.get("default_phrase_bars", 8)))


## Pure phrase math. pos: seconds into the piece; len_s: pass length when the cue has no bar count.
## Phrase boundaries come from cue.phrases (bar offsets, for irregular forms like 8+8+4) or every
## bars_per_phrase bars; the end of the pass is always a boundary.
static func beat_wait(cue: Dictionary, kind: String, pos: float, len_s: float = 0.0, track_bpm: float = 0.0,
		track_bpb: int = 0, default_phrase_bars: int = 8) -> float:
	var bpm := float(cue.get("bpm", 0.0))
	if bpm <= 0.0:
		bpm = track_bpm
	if bpm <= 0.0:
		return -1.0
	var bpb := int(cue.get("bpb", 0))
	if bpb <= 0:
		bpb = track_bpb
	if bpb <= 0:
		bpb = 4
	var beat := 60.0 / bpm
	var bar := beat * float(bpb)
	var bars := int(cue.get("bars", 0))
	var total := float(bars) * bar if bars > 0 else len_s
	var p := fposmod(pos, total) if total > 0.0 else pos
	var step := bar
	var marks: Array = []
	if kind == "beat":
		step = beat
	elif kind == "phrase":
		var ph: Array = cue.get("phrases", [])
		if not ph.is_empty() and total > 0.0:
			for b in ph:
				marks.append(float(b) * bar)
			marks.append(total)
		else:
			var pb := int(cue.get("bars_per_phrase", 0))
			step = bar * float(pb if pb > 0 else default_phrase_bars)
	if marks.is_empty():
		var nxt := ceilf((p - EPS) / step) * step
		if total > 0.0:
			nxt = minf(nxt, total)
		return maxf(nxt - p, 0.0)
	for m in marks:
		if float(m) >= p - EPS:
			return maxf(float(m) - p, 0.0)
	return 0.0


# ---------------------------------------------------------------------------------------------
# Decisions, helpers, log
# ---------------------------------------------------------------------------------------------

func _play(cue: String, fade: float, wait: float, why: String, ctx: Dictionary) -> Dictionary:
	_prev = {"cue": _cue, "track": _track, "phase": _phase}
	var c: Dictionary = cues.get(cue, {})
	_cue = cue
	_track = String(c.get("track", ""))
	_piece_t = -wait
	_piece_len = float(c.get("len_s", 0.0))
	_piece_loop = bool(c.get("loop", false))
	_phase = "playing"
	_rest_left = 0.0
	_next_cue = ""
	_last_played = cue
	_layers = _layers_for(cue, ctx) if _kind(_eff) == "boss" else []
	return {"action": "play", "cue": cue, "track": _track, "layers": _layers.duplicate(), "fade": fade,
		"wait_s": wait, "context": _eff, "reason": why}


func _stop(fade: float, why: String) -> Dictionary:
	_prev = {"cue": _cue, "track": _track, "phase": _phase}
	_cue = ""
	_track = ""
	_layers = []
	_phase = "silent"
	return {"action": "stop", "cue": "", "track": "", "layers": [], "fade": fade, "wait_s": 0.0,
		"context": _eff, "reason": why}


func _none(why: String) -> Dictionary:
	return {"action": "none", "cue": _cue, "track": _track, "layers": [], "fade": 0.0, "wait_s": 0.0,
		"context": _eff, "reason": why}


func _log(d: Dictionary) -> void:
	debug_log.append({"t": snappedf(_now, 0.01), "action": String(d.get("action", "")),
		"context": String(d.get("context", "")), "cue": String(d.get("cue", "")),
		"track": String(d.get("track", "")), "fade": float(d.get("fade", 0.0)),
		"wait_s": float(d.get("wait_s", 0.0)), "reason": String(d.get("reason", ""))})
	while debug_log.size() > LOG_MAX:
		debug_log.pop_front()


func _note(text: String) -> void:
	_log({"action": "note", "context": _eff, "cue": _cue, "track": _track, "reason": text})


func _kind(id: String) -> String:
	return String((contexts.get(id, {}) as Dictionary).get("kind", ""))


func _ctx_mode(id: String) -> String:
	return String((contexts.get(id, {}) as Dictionary).get("mode", "rotate"))


func _priority(id: String) -> int:
	return int((contexts.get(id, {}) as Dictionary).get("priority", 0))


func _cf(id: String, key: String, def: float) -> float:
	return float((contexts.get(id, {}) as Dictionary).get(key, def))


func _cs(id: String, key: String, def: String) -> String:
	return String((contexts.get(id, {}) as Dictionary).get(key, def))


func _tf(key: String, def: float) -> float:
	return float(tuning.get(key, def))


## Random value from a [min, max] tuning pair (own RNG). Rests scale with tuning.rest_scale.
func _roll(key: String, def: Array, is_rest: bool) -> float:
	var r: Variant = tuning.get(key, def)
	var a: Array = r if r is Array and (r as Array).size() >= 2 else def
	var v := rng.randf_range(float(a[0]), float(a[1]))
	return v * _tf("rest_scale", 1.0) if is_rest else v


func _roll_rest(id: String) -> float:
	var r: Variant = (contexts.get(id, {}) as Dictionary).get("rest", tuning.get("default_rest_s", [20.0, 45.0]))
	var a: Array = r if r is Array and (r as Array).size() >= 2 else [20.0, 45.0]
	return rng.randf_range(float(a[0]), float(a[1])) * _tf("rest_scale", 1.0)
