extends RefCounted
## Music Box helper (MP 18.3: "a restrained optional Music Box furnishing that previews/unlocks discovered
## safe-area tracks and favorites. It is a home feature, not a global override that breaks boss/horror cues").
## Static and autoload-free, like src/core/mastery.gd. Used by the Music Box structure
## (src/building/structures/music_box.gd), its panel (src/ui/panels/music_box_panel.gd) and the music director
## (favourites for the Haven rotation).
##
## Saved state - GameState.extra[STATE_KEY] ("music_box"). GameState writes every top-level key it does not own
## back verbatim (extra), so the section survives save / load / migration untouched and is reset by New Game:
##   {"discovered": {cue_id: {"area": String, "zone": String, "at": total_minutes}},   first heard (in play)
##    "favourites": [cue_id, ...]}                                                     the Favourite toggles
## Cue ids are the plain strings of data/music.gd. An id the catalogue no longer knows (a renamed cue) is KEPT in
## the save but never listed, previewed or weighted, so a save never fails because of it and it comes back if
## the id does. A malformed section reads as empty (never a script error) and is repaired on the next write.
##
## Discovery: a cue is discovered once it starts playing in play (Events.music_cue_changed while a journey is
## loaded and Game.mode is not the title), for the kinds in ELIGIBLE_KINDS (safe / explore / ending: the Haven,
## the regions, the restoration and celebration reprises) - never boss, combat or horror cues. STARTER_CUES
## ("A Little Light", the music box's own tune) are always known, so a new box has something to play.
##
## Preview: through the music director's low-priority "musicbox" context (src/audio/music_selector.gd): one
## pass of the chosen cue; boss / horror / combat / authored music (and death, leaving the area) end it in the
## director. The box that started it stops it when Krystal leaves the house (should_stop()). Stop fades it
## out and the Haven rotation returns after a short rest. Without an active director (legacy fallback) the
## track is played through Audio.request_music's fallback and stopped with release_music.
## Sound muted: nothing breaks; the panel shows the title and a caption names the song (captions setting).
##
## API
##   init() / shutdown() / is_listening()        Events wiring (idempotent). Game.wire_session_systems() should
##                                                call init() (integrator); the structure also calls it.
##   is_eligible(cue), eligible_cues() -> Array, title(cue) -> String, home_of(cue) -> {context, area, zone, night}
##   note_heard(cue, area := "", zone := "") -> bool   (true = newly discovered), is_discovered(cue),
##   discovered() -> Array (catalogue order), heard_at(cue) -> {area, zone, at} ({} for starters / unknown)
##   favourites() -> Array (known, discovered), favourites_view() -> Array (the saved list itself, read-only),
##   is_favourite(cue), set_favourite(cue, on) -> bool (changed), toggle_favourite(cue) -> bool (new state)
##   preview(cue, source: Node = null) -> bool, stop_preview(fade := PREVIEW_FADE), preview_cue() -> String,
##   is_previewing(), preview_source() -> Node,
##   should_stop(area, zone, player_pos, box_pos, box_area := HOUSE_AREA) -> bool,
##   music_muted() -> bool, owns_music_box() -> bool
## Tests: `director_override` replaces Audio.music_director() (a director node set up by the test).

const MusicData := preload("res://data/music.gd")

const STATE_KEY := "music_box"
const ELIGIBLE_KINDS := ["safe", "explore", "ending"]
const STARTER_CUES := ["m01"]
const PREVIEW_CONTEXT := "musicbox"      # music_selector.gd PREVIEW_CONTEXT
const PREVIEW_FADE := 1.5
## The house area: the Haven zone of the surface (the whole buildable home) or this close to the box.
const HOUSE_AREA := "surface"
const HOUSE_ZONE := "haven"
const HOUSE_RADIUS := 12.0
const STRUCTURE_ID := "music_box"
## Where a piece belongs when its context has no place of its own.
const CONTEXT_PLACES := {"title": "The music box's own tune", "restoration": "When the Ward bloomed again",
	"celebration": "Homecoming celebrations"}
const CAPTION_PLAY := "[the music box plays \"%s\"]"
const CAPTION_STOP := "[the music box winds down]"
const CAPTION_LEFT := "[the music box winds down behind you]"
const NEW_SONG_TEXT := "New song for your music box: %s"
const NO_FAVOURITES := []

static var director_override: Node = null
static var _wired := false
static var _source: WeakRef = null
static var _legacy_cue := ""


# --- Wiring ----------------------------------------------------------------------------------------

## Connects the discovery listener (idempotent).
static func init() -> void:
	_wired = true
	if not Events.music_cue_changed.is_connected(_on_cue_changed):
		Events.music_cue_changed.connect(_on_cue_changed)


static func shutdown() -> void:
	_wired = false
	if Events.music_cue_changed.is_connected(_on_cue_changed):
		Events.music_cue_changed.disconnect(_on_cue_changed)


static func is_listening() -> bool:
	return _wired and Events.music_cue_changed.is_connected(_on_cue_changed)


static func _on_cue_changed(cue: String) -> void:
	if cue == "" or not _in_play():
		return
	# a quiet toast once a box stands at home - never over a cutscene (the restoration / celebration reprises)
	if note_heard(cue, String(Game.area_id), String(Game.zone_id)) and String(Game.mode) == "playing" \
			and owns_music_box():
		Events.notify.emit(NEW_SONG_TEXT % title(cue), "info")


## A journey is loaded and it is not the title screen (the title theme is heard there before every journey).
static func _in_play() -> bool:
	var m := String(Game.mode)
	return GameState.active and m != "title" and m != "boot" and m != ""


# --- Catalogue -------------------------------------------------------------------------------------

static func is_eligible(cue: String) -> bool:
	var c: Variant = MusicData.CUES.get(cue)
	return c is Dictionary and ELIGIBLE_KINDS.has(String((c as Dictionary).get("kind", "")))


## Every cue the music box can ever hold, in catalogue order.
static func eligible_cues() -> Array:
	var out: Array = []
	for id in MusicData.cue_ids():
		if is_eligible(String(id)):
			out.append(String(id))
	return out


static func title(cue: String) -> String:
	var c: Variant = MusicData.CUES.get(cue)
	return String((c as Dictionary).get("title", cue)) if c is Dictionary else cue


static func track_of(cue: String) -> String:
	var c: Variant = MusicData.CUES.get(cue)
	return String((c as Dictionary).get("track", "")) if c is Dictionary else ""


## Where a piece belongs, from the catalogue itself: the context whose playlist (or signature) holds it with
## the fewest other pieces (first in data order on a tie), and the area / zone that context plays in.
## {"context", "area", "zone" ("" = the whole area), "night" (only its night playlist holds it)}.
static func home_of(cue: String) -> Dictionary:
	var out := {"context": "", "area": "", "zone": "", "night": false}
	var best_n := 1 << 30
	for cid in MusicData.CONTEXTS:
		var c: Dictionary = MusicData.CONTEXTS[cid]
		for key in ["signature", "playlist", "late_playlist", "night_playlist"]:
			var pl := String(c.get(key, ""))
			if pl == "":
				continue
			var cs: Array = (MusicData.PLAYLISTS.get(pl, {}) as Dictionary).get("cues", [])
			if cs.has(cue) and cs.size() < best_n:
				best_n = cs.size()
				out["context"] = String(cid)
				out["night"] = key == "night_playlist"
	var ctx := String(out["context"])
	if ctx == "":
		return out
	for a in MusicData.AREAS:
		var ad: Dictionary = MusicData.AREAS[a]
		var zones: Dictionary = ad.get("zones", {})
		for z in zones:
			if String(zones[z]) == ctx:
				out["area"] = String(a)
				out["zone"] = String(z)
				return out
		if String(ad.get("default", "")) == ctx:
			out["area"] = String(a)
			return out
	return out


# --- Saved state -----------------------------------------------------------------------------------

## The saved section (read only; {} when missing or malformed).
static func _view() -> Dictionary:
	var v: Variant = GameState.extra.get(STATE_KEY)
	return v if v is Dictionary else {}


static func _discovered_view() -> Dictionary:
	var d: Variant = _view().get("discovered")
	return d if d is Dictionary else {}


## The saved section for writing (created / repaired in place; unknown keys and ids are kept).
static func _state_rw() -> Dictionary:
	var v: Variant = GameState.extra.get(STATE_KEY)
	if not (v is Dictionary):
		v = {}
		GameState.extra[STATE_KEY] = v
	var st: Dictionary = v
	var disc: Variant = st.get("discovered")
	if not (disc is Dictionary):
		var fixed := {}
		if disc is Array:                     # a list of ids (hand-edited / damaged): keep them
			for id in (disc as Array):
				if id is String:
					fixed[id] = {}
		st["discovered"] = fixed
	var fav: Variant = st.get("favourites")
	if not (fav is Array):
		st["favourites"] = []
	return st


## Records a cue as heard. True when it was newly discovered (eligible kinds only).
static func note_heard(cue: String, area: String = "", zone: String = "") -> bool:
	if not is_eligible(cue) or is_discovered(cue):
		return false
	var disc: Dictionary = _state_rw()["discovered"]
	disc[cue] = {"area": area, "zone": zone, "at": float(GameState.total_minutes)}
	return true


static func is_discovered(cue: String) -> bool:
	if not is_eligible(cue):
		return false
	return STARTER_CUES.has(cue) or _discovered_view().has(cue)


## Discovered cues in catalogue order (starters included; unknown / ineligible saved ids left out).
static func discovered() -> Array:
	var out: Array = []
	for id in MusicData.cue_ids():
		if is_discovered(String(id)):
			out.append(String(id))
	return out


## {"area", "zone", "at"} of the first time a cue was heard ({} for starters and unknown cues).
static func heard_at(cue: String) -> Dictionary:
	var r: Variant = _discovered_view().get(cue)
	return (r as Dictionary).duplicate() if r is Dictionary else {}


## The saved favourites list itself (read only; the director hands it to the selector every tick without
## copying - the selector ignores ids it doesn't know).
static func favourites_view() -> Array:
	var f: Variant = _view().get("favourites")
	return f if f is Array else NO_FAVOURITES


## Favourites that can play: known, discovered cues (stored order).
static func favourites() -> Array:
	var out: Array = []
	for f in favourites_view():
		if f is String and is_discovered(f) and not out.has(f):
			out.append(f)
	return out


static func is_favourite(cue: String) -> bool:
	return favourites_view().has(cue) and is_discovered(cue)


## Marks / unmarks a favourite. Only discovered cues can become favourites; removing always works (also for
## an id the catalogue lost). True when something changed.
static func set_favourite(cue: String, on: bool) -> bool:
	var st := _state_rw()
	var fav: Array = st["favourites"]
	if on:
		if not is_discovered(cue) or fav.has(cue):
			return false
		fav.append(cue)
		return true
	if not fav.has(cue):
		return false
	while fav.has(cue):
		fav.erase(cue)
	return true


static func toggle_favourite(cue: String) -> bool:
	set_favourite(cue, not is_favourite(cue))
	return is_favourite(cue)


## True when a Music Box stands anywhere in the Haven (GameState.structures).
static func owns_music_box() -> bool:
	for uid in GameState.structures:
		var r: Variant = GameState.structures[uid]
		if r is Dictionary and String((r as Dictionary).get("id", "")) == STRUCTURE_ID:
			return true
	return false


# --- Preview ---------------------------------------------------------------------------------------

static func _director() -> Node:
	if director_override != null and is_instance_valid(director_override):
		return director_override
	if Audio.has_method("music_director_active") and bool(Audio.music_director_active()):
		var d: Variant = Audio.music_director()
		if d is Node and (d as Node).has_method("preview"):
			return d
	return null


## Plays a discovered cue on the music box (one pass). `source` (the box) is told through
## on_preview_started(cue) and checks that Krystal stays at home. False when nothing can play: undiscovered or
## unplayable, or higher-priority music (boss / combat / horror silence / authored) is on right now.
static func preview(cue: String, source: Node = null) -> bool:
	if not is_discovered(cue):
		return false
	var ok := false
	var d := _director()
	if d != null:
		# the director evaluates at once: a boss / combat / horror silence / authored music that is already
		# on ends the request in the same tick, so only a preview that is still standing counts as playing
		ok = bool(d.call("preview", cue, PREVIEW_FADE)) and String(d.call("preview_cue")) == cue
		_legacy_cue = ""
	else:
		var track := track_of(cue)
		if track != "" and Audio.has_sound(track, true):
			Audio.request_music(PREVIEW_CONTEXT, track, PREVIEW_FADE)   # no director: plays the track itself
			_legacy_cue = cue
			ok = true
	if not ok:
		return false
	_source = weakref(source) if source != null else null
	Events.caption.emit(CAPTION_PLAY % title(cue))
	if source != null and is_instance_valid(source) and source.has_method("on_preview_started"):
		source.call("on_preview_started", cue)
	return true


## Stop pressed / Krystal left the house: the preview fades out (the Haven music returns after a rest).
static func stop_preview(fade: float = PREVIEW_FADE) -> void:
	var d := _director()
	if d != null:
		d.call("stop_preview", fade)
	if _legacy_cue != "":
		if Audio.current_music() == track_of(_legacy_cue) and d == null:
			Audio.release_music(PREVIEW_CONTEXT, fade)            # no director: stops the music
		_legacy_cue = ""
	_source = null


## The cue being previewed ("" = none: never started, stopped, finished or ended by other music).
static func preview_cue() -> String:
	var d := _director()
	if d != null:
		return String(d.call("preview_cue"))
	if _legacy_cue != "" and Audio.current_music() == track_of(_legacy_cue):
		return _legacy_cue
	return ""


static func is_previewing() -> bool:
	return preview_cue() != ""


## The box that started the current preview (null when none or gone).
static func preview_source() -> Node:
	if _source == null or preview_cue() == "":
		return null
	var n: Variant = _source.get_ref()
	return n if n is Node and is_instance_valid(n) else null


## True when Krystal has left the house: another area than the box's, or (in the box's area) farther than
## HOUSE_RADIUS from the box - except anywhere in the Haven zone for a box at home on the surface (a box placed
## where a landmark circle overlaps the home still works). `box_area` is where the box stands: the surface
## Haven, or the small Reach outpost at the Commons (build_ops.gd), where the radius alone is the house.
static func should_stop(area_id: String, zone_id: String, player_pos: Vector3, box_pos: Vector3,
		box_area: String = HOUSE_AREA) -> bool:
	if area_id != box_area:
		return true
	if box_area == HOUSE_AREA and zone_id == HOUSE_ZONE:
		return false
	return player_pos.distance_to(box_pos) > HOUSE_RADIUS


## True when the music cannot be heard (Master or Music bus muted: volume at 0). Previews still "play"
## (title, caption, the dancer turns) so the box works without sound.
static func music_muted() -> bool:
	var mb := AudioServer.get_bus_index("Music")
	return AudioServer.is_bus_mute(0) or (mb >= 0 and AudioServer.is_bus_mute(mb))
