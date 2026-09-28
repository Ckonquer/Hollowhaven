extends RefCounted
## Music catalogue for BOTH chapters (docs/CHAPTER_TWO_SPEC.md 4.8, master prompt 18): the 27 cues
## m01..m27, the playlists the MusicDirector rotates, the contexts it chooses between (with their
## priorities) and the area/zone/boss mappings. Read by src/audio/music_selector.gd (pure core) and
## src/audio/music_director.gd (the node that applies it). Nothing here is saved.
##
## Cue fields:
##   track       Audio sound name (file stem in res://assets/audio/music/). Retained Chapter One pieces
##               keep their WAV names; new compositions are OGG Vorbis files named after the cue.
##   file        resource path of the source file (manifest / QA only; playback goes through `track`)
##   title, kind explore | safe | combat | boss | ending | horror
##   loop        the file loops by itself (import loop flag). Non-looping pieces play to their end.
##   bpm, bpb    tempo and beats per bar (0 = unknown: the director then reads the stream's own
##               bpm/bar_beats import metadata, and without either waits for the piece's end)
##   bars        bars in one pass (0 = unknown), bars_per_phrase, phrases = bar offsets of irregular
##               phrase starts (e.g. 8+8+4)
##   len_s       length of one pass in seconds when known (the director measures it otherwise)
##   passes      a LOOPING piece in a rotation plays this many passes, then fades out at its end
##   layers      synchronised stems faded in by boss phase (phase 2 -> first, phase 3 -> both)
##   retained    a Chapter One file that already exists (always available)
##
## Missing files never break anything: a cue whose file is absent (or not imported yet) is skipped
## ("next in playlist"); a playlist without any playable cue uses its `fallback` list: a retained cue,
## "keep" (leave the current music alone: the context is transparent) or "" (silence).

const DIR := "res://assets/audio/music/"

const CUES := {
	# --- retained Chapter One pieces (WAV, QOA, forward loops; measured in docs/ch2/maps/audio_music.md 6) ---
	"m01": {"title": "A Little Light", "kind": "safe", "track": "music_title", "file": DIR + "music_title.wav",
		"loop": true, "bpm": 76.0, "bpb": 3, "bars": 32, "bars_per_phrase": 8, "phrases": [0, 8, 16, 24],
		"len_s": 75.789, "retained": true},
	"m02": {"title": "Home in the Clearing", "kind": "safe", "track": "music_haven", "file": DIR + "music_haven.wav",
		"loop": true, "bpm": 88.0, "bpb": 4, "bars": 32, "bars_per_phrase": 8, "phrases": [0, 8, 16, 24],
		"len_s": 87.273, "passes": 2, "retained": true},
	"m05": {"title": "Lanterns After Dark", "kind": "safe", "track": "music_night", "file": DIR + "music_night.wav",
		"loop": true, "bpm": 60.0, "bpb": 4, "bars": 20, "bars_per_phrase": 8, "phrases": [0, 8, 16],
		"len_s": 80.0, "passes": 2, "retained": true},
	"m13": {"title": "The Thread Above", "kind": "boss", "track": "music_boss", "file": DIR + "music_boss.wav",
		"loop": true, "bpm": 120.0, "bpb": 4, "bars": 30, "bars_per_phrase": 8, "phrases": [0, 2, 10, 18, 26],
		"len_s": 60.0, "retained": true,
		"layers": ["m13_layer2", "m13_layer3"],
		"layer_files": [DIR + "m13_layer2.ogg", DIR + "m13_layer3.ogg"]},
	"m14": {"title": "The Heart Comes Home", "kind": "ending", "track": "music_ending", "file": DIR + "music_ending.wav",
		"loop": true, "bpm": 80.0, "bpb": 3, "bars": 40, "bars_per_phrase": 8, "phrases": [0, 4, 12, 20, 28, 36],
		"len_s": 90.0, "retained": true},

	# --- new compositions (OGG Vorbis, tools/audio/music2/*) ---
	"m03": {"title": "Wood, Wool & Windows", "kind": "safe", "track": "m03_wood_wool_windows",
		"file": DIR + "m03_wood_wool_windows.ogg", "loop": false, "bpm": 96.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m04": {"title": "Berry Tea Afternoon", "kind": "safe", "track": "m04_berry_tea_afternoon",
		"file": DIR + "m04_berry_tea_afternoon.ogg", "loop": false, "bpm": 50.0, "bpb": 2, "bars": 0, "bars_per_phrase": 8},
	"m06": {"title": "Firefly Wishes", "kind": "safe", "track": "m06_firefly_wishes",
		"file": DIR + "m06_firefly_wishes.ogg", "loop": false, "bpm": 63.0, "bpb": 3, "bars": 0, "bars_per_phrase": 8},
	"m07": {"title": "Footpaths & Ferns", "kind": "explore", "track": "m07_footpaths_and_ferns",
		"file": DIR + "m07_footpaths_and_ferns.ogg", "loop": false, "bpm": 104.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m08": {"title": "The Long Way Home", "kind": "explore", "track": "m08_the_long_way_home",
		"file": DIR + "m08_the_long_way_home.ogg", "loop": false, "bpm": 74.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m09": {"title": "Ripples at Mirror Pond", "kind": "explore", "track": "m09_ripples_at_mirror_pond",
		"file": DIR + "m09_ripples_at_mirror_pond.ogg", "loop": false, "bpm": 56.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m10": {"title": "Thorns in the Path", "kind": "combat", "track": "m10_thorns_in_the_path",
		"file": DIR + "m10_thorns_in_the_path.ogg", "loop": true, "bpm": 100.0, "bpb": 2, "bars": 56, "bars_per_phrase": 8},
	"m11": {"title": "The Last Shift", "kind": "explore", "track": "m11_the_last_shift",
		"file": DIR + "m11_the_last_shift.ogg", "loop": true, "bpm": 60.0, "bpb": 4, "bars": 36, "bars_per_phrase": 8,
		"passes": 1},
	"m12": {"title": "Eyes That Stay Shut", "kind": "horror", "track": "m12_eyes_that_stay_shut",
		"file": DIR + "m12_eyes_that_stay_shut.ogg", "loop": true, "bpm": 48.0, "bpb": 3, "bars": 36, "bars_per_phrase": 8,
		"passes": 1},
	"m15": {"title": "Welcome to Lanternwake", "kind": "safe", "track": "m15_welcome_to_lanternwake",
		"file": DIR + "m15_welcome_to_lanternwake.ogg", "loop": false, "bpm": 104.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m16": {"title": "Copper Leaves at Dusk", "kind": "explore", "track": "m16_copper_leaves_at_dusk",
		"file": DIR + "m16_copper_leaves_at_dusk.ogg", "loop": false, "bpm": 56.0, "bpb": 2, "bars": 0, "bars_per_phrase": 8},
	"m17": {"title": "Pumpkin Patch Parade", "kind": "explore", "track": "m17_pumpkin_patch_parade",
		"file": DIR + "m17_pumpkin_patch_parade.ogg", "loop": false, "bpm": 96.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m18": {"title": "Stone Bells, Quiet Hills", "kind": "explore", "track": "m18_stone_bells_quiet_hills",
		"file": DIR + "m18_stone_bells_quiet_hills.ogg", "loop": false, "bpm": 84.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m19": {"title": "Candles for the Moon", "kind": "explore", "track": "m19_candles_for_the_moon",
		"file": DIR + "m19_candles_for_the_moon.ogg", "loop": false, "bpm": 66.0, "bpb": 3, "bars": 0, "bars_per_phrase": 8},
	"m20": {"title": "The Empty Waltz", "kind": "explore", "track": "m20_the_empty_waltz",
		"file": DIR + "m20_the_empty_waltz.ogg", "loop": false, "bpm": 96.0, "bpb": 3, "bars": 0, "bars_per_phrase": 8},
	"m21": {"title": "A Midnight Invitation", "kind": "boss", "track": "m21_a_midnight_invitation",
		"file": DIR + "m21_a_midnight_invitation.ogg", "loop": true, "bpm": 144.0, "bpb": 3, "bars": 80, "bars_per_phrase": 8},
	"m22": {"title": "Harvest Trouble", "kind": "combat", "track": "m22_harvest_trouble",
		"file": DIR + "m22_harvest_trouble.ogg", "loop": true, "bpm": 160.0, "bpb": 4, "bars": 50, "bars_per_phrase": 8},
	"m23": {"title": "Under the Bellhouse", "kind": "horror", "track": "m23_under_the_bellhouse",
		"file": DIR + "m23_under_the_bellhouse.ogg", "loop": true, "bpm": 50.0, "bpb": 4, "bars": 32, "bars_per_phrase": 8,
		"passes": 1},
	"m24": {"title": "A Pocket of Day", "kind": "safe", "track": "m24_a_pocket_of_day",
		"file": DIR + "m24_a_pocket_of_day.ogg", "loop": false, "bpm": 76.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m25": {"title": "No Thread Left Unseen", "kind": "boss", "track": "m25_no_thread_left_unseen",
		"file": DIR + "m25_no_thread_left_unseen.ogg", "loop": true, "bpm": 0.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
	"m26": {"title": "The Borrowed Welcome", "kind": "boss", "track": "m26_borrowed_welcome_l1",
		"file": DIR + "m26_borrowed_welcome_l1.ogg", "loop": true, "bpm": 108.0, "bpb": 4, "bars": 48, "bars_per_phrase": 8,
		"layers": ["m26_borrowed_welcome_l2", "m26_borrowed_welcome_l3"],
		"layer_files": [DIR + "m26_borrowed_welcome_l2.ogg", DIR + "m26_borrowed_welcome_l3.ogg"]},
	"m27": {"title": "Every Road Leads Home", "kind": "ending", "track": "m27_every_road_leads_home",
		"file": DIR + "m27_every_road_leads_home.ogg", "loop": false, "bpm": 112.0, "bpb": 4, "bars": 0, "bars_per_phrase": 8},
}

## Playlists (shuffle bags: every cue once per round, never the same piece twice in a row).
const PLAYLISTS := {
	"title": {"cues": ["m01"], "fallback": [""]},
	"haven_day": {"cues": ["m02", "m03", "m04"], "fallback": ["m02"]},
	"haven_day_late": {"cues": ["m02", "m03", "m04", "m27"], "fallback": ["m02"]},   # after Chapter Two
	"haven_night": {"cues": ["m05", "m06"], "fallback": ["m05"]},
	"woods": {"cues": ["m07", "m08"], "fallback": ["m02"]},
	"pond": {"cues": ["m09"], "fallback": []},                   # signature only (then "woods")
	"combat1": {"cues": ["m10"], "fallback": ["keep"]},
	"mine": {"cues": ["m11"], "fallback": [""]},
	"ruins": {"cues": ["m12"], "fallback": [""]},
	"boss_matron": {"cues": ["m13"], "fallback": [""]},
	"restoration": {"cues": ["m14"], "fallback": [""]},
	"reach": {"cues": ["m15", "m16"], "fallback": ["m02"]},
	"orchard": {"cues": ["m17"], "fallback": []},                # signature
	"orchard_rotation": {"cues": ["m17", "m16", "m15"], "fallback": ["m02"]},
	"quarry": {"cues": ["m18"], "fallback": []},                 # signature
	"quarry_rotation": {"cues": ["m18", "m16", "m15"], "fallback": ["m02"]},
	"candleyard": {"cues": ["m19"], "fallback": []},             # signature
	"candleyard_rotation": {"cues": ["m19", "m16"], "fallback": ["m05"]},
	"manor_grounds": {"cues": ["m20", "m16"], "fallback": ["m05"]},
	"manor": {"cues": ["m20"], "fallback": [""]},
	"velour": {"cues": ["m21"], "fallback": ["m13"]},
	"combat2": {"cues": ["m22"], "fallback": ["m10", "keep"]},
	"works": {"cues": ["m23"], "fallback": [""]},
	"refuge": {"cues": ["m24"], "fallback": ["m02"]},
	"crossing": {"cues": ["m25"], "fallback": ["m13"]},
	"choir": {"cues": ["m26"], "fallback": ["m13"]},
	"celebration": {"cues": ["m27"], "fallback": ["m14"]},
}

## Contexts. priority: higher wins (muted/paused policy comes before all of them). kind: ending |
## menu | boss | horror | combat | safe | explore | ambience. mode: rotate (bag + rests between
## pieces), loop (one piece until the context ends), once (one piece, then the request ends).
## playlist / night_playlist / late_playlist ("" = no music: ambience only). signature: playlist
## played first on arrival (at most once per signature_cooldown_s), then `playlist` rotates.
## fade: crossfade into the context; exit_fade: out of it; cut: now | beat | bar | phrase (when the
## change may happen; exploration waits for the current piece's phrase); rest: [min, max] seconds of
## quiet between pieces; enter_s: seconds a zone must hold before this base context takes over.
const CONTEXTS := {
	# authored scenes and the title
	"restoration": {"kind": "ending", "priority": 100, "playlist": "restoration", "mode": "loop", "fade": 1.5, "exit_fade": 3.0},
	"celebration": {"kind": "ending", "priority": 100, "playlist": "celebration", "mode": "once", "fade": 2.0, "exit_fade": 4.0},
	"title": {"kind": "menu", "priority": 95, "playlist": "title", "mode": "loop", "fade": 3.0, "exit_fade": 1.0},
	# bosses (stems follow boss_phase_changed)
	"boss_matron": {"kind": "boss", "priority": 90, "playlist": "boss_matron", "mode": "loop", "fade": 1.5, "exit_fade": 3.0, "layer_fade": 2.0},
	"velour": {"kind": "boss", "priority": 90, "playlist": "velour", "mode": "loop", "fade": 1.5, "exit_fade": 3.0, "layer_fade": 2.0},
	"crossing": {"kind": "boss", "priority": 90, "playlist": "crossing", "mode": "loop", "fade": 1.5, "exit_fade": 3.0, "layer_fade": 2.0},
	"choir": {"kind": "boss", "priority": 90, "playlist": "choir", "mode": "loop", "fade": 1.5, "exit_fade": 4.0, "layer_fade": 3.0},
	# authored horror suppression: the music fades OUT so the room, footsteps and silence carry it
	"silence": {"kind": "horror", "priority": 80, "playlist": "", "fade": 4.0},
	# ordinary combat
	"combat1": {"kind": "combat", "priority": 70, "playlist": "combat1", "mode": "loop", "fade": 1.2, "exit_fade": 3.0, "cut": "beat"},
	"combat2": {"kind": "combat", "priority": 70, "playlist": "combat2", "mode": "loop", "fade": 1.2, "exit_fade": 3.0, "cut": "beat"},
	# safe refuges
	"haven": {"kind": "safe", "priority": 30, "playlist": "haven_day", "night_playlist": "haven_night",
		"late_playlist": "haven_day_late", "mode": "rotate", "rest": [15.0, 40.0], "fade": 4.0, "cut": "phrase"},
	"refuge": {"kind": "safe", "priority": 30, "playlist": "refuge", "mode": "rotate", "rest": [20.0, 45.0], "fade": 5.0, "cut": "phrase"},
	# regional exploration
	"woods": {"kind": "explore", "priority": 20, "playlist": "woods", "night_playlist": "haven_night", "mode": "rotate",
		"rest": [25.0, 60.0], "fade": 5.0, "cut": "phrase"},
	"pond": {"kind": "explore", "priority": 20, "signature": "pond", "playlist": "woods", "night_playlist": "haven_night",
		"mode": "rotate", "rest": [25.0, 60.0], "fade": 5.0, "cut": "phrase"},
	"mine": {"kind": "explore", "priority": 20, "playlist": "mine", "mode": "rotate", "rest": [30.0, 75.0], "fade": 6.0, "cut": "phrase"},
	"ruins": {"kind": "explore", "priority": 20, "playlist": "ruins", "mode": "rotate", "rest": [40.0, 90.0], "fade": 6.0, "cut": "phrase"},
	"annex": {"kind": "explore", "priority": 20, "playlist": "mine", "mode": "rotate", "rest": [30.0, 75.0], "fade": 6.0, "cut": "phrase"},
	"reach": {"kind": "explore", "priority": 20, "playlist": "reach", "mode": "rotate", "rest": [20.0, 45.0], "fade": 5.0, "cut": "phrase"},
	"orchard": {"kind": "explore", "priority": 20, "signature": "orchard", "playlist": "orchard_rotation", "mode": "rotate",
		"rest": [20.0, 45.0], "fade": 5.0, "cut": "phrase"},
	"quarry": {"kind": "explore", "priority": 20, "signature": "quarry", "playlist": "quarry_rotation", "mode": "rotate",
		"rest": [20.0, 45.0], "fade": 5.0, "cut": "phrase"},
	"candleyard": {"kind": "explore", "priority": 20, "signature": "candleyard", "playlist": "candleyard_rotation",
		"mode": "rotate", "rest": [25.0, 55.0], "fade": 5.0, "cut": "phrase"},
	"manor_grounds": {"kind": "explore", "priority": 20, "playlist": "manor_grounds", "mode": "rotate", "rest": [20.0, 45.0], "fade": 5.0, "cut": "phrase"},
	"manor": {"kind": "explore", "priority": 20, "playlist": "manor", "mode": "rotate", "rest": [20.0, 50.0], "fade": 5.0, "cut": "phrase"},
	"works": {"kind": "explore", "priority": 20, "playlist": "works", "mode": "rotate", "rest": [30.0, 75.0], "fade": 6.0, "cut": "phrase"},
	# ambience only (no music)
	"silk": {"kind": "ambience", "priority": 10, "playlist": "", "fade": 3.0},
	"trial": {"kind": "ambience", "priority": 10, "playlist": "", "fade": 3.0},
}

## Area -> base context: zone ids first (spec 7: surface legacy zones, reach hr_*, manor mm_*, works
## hw_*, annex ta_*), then the area default. Unknown areas have no base context (the music is held).
const AREAS := {
	"surface": {"default": "woods", "zones": {"haven": "haven", "pond": "pond"}},
	"below": {"default": "mine", "zones": {"mine": "mine", "ruins": "ruins", "silk": "silk", "boss": "silk"}},
	"tobin_annex": {"default": "annex", "zones": {}},
	"hallowmere_reach": {"default": "reach", "zones": {"hr_orchard": "orchard", "hr_quarry": "quarry",
		"hr_candleyard": "candleyard", "hr_manor_grounds": "manor_grounds"}},
	"moonveil_manor": {"default": "manor", "zones": {}},
	"hushed_works": {"default": "works", "zones": {"hw_refuge": "refuge"}},
	"echo_trial": {"default": "trial", "zones": {}},
}

## Ordinary combat music per area ("*" = every other area: the Chapter Two ones). Tobin's annex is
## Chapter One content (MP 7), so it keeps the Chapter One combat piece.
const AREA_COMBAT := {"surface": "combat1", "below": "combat1", "tobin_annex": "combat1", "*": "combat2"}

## Boss id (Events.boss_* signals) -> boss context. Echo trials replay the same ids.
const BOSSES := {"weaver_matron": "boss_matron", "count_velour": "velour", "crossing_matron": "crossing",
	"borrowed_choir": "choir"}

## Seconds of music silence after a horror event (Events.horror_event). "authored:<id>" moments not
## listed use AUTHORED_SILENCE_DEFAULT; other director events rely on the horror state instead.
## Short Chapter Two moments get a shorter hush: Tobin's annex echo (a single cozy-eerie beat, 12 s) and the
## manor's Empty Waltz (the waltz fades, one pair bows, then the room's music returns: 15 s). The Works' hw_*
## moments keep the default.
const AUTHORED_SILENCE := {"authored:boss": 0.0, "authored:return": 0.0, "silence": 12.0,
	"authored:ta_echo": 12.0, "authored:empty_waltz": 15.0}
const AUTHORED_SILENCE_DEFAULT := 25.0

const TUNING := {
	"tick_s": 0.2,                    # director decision rate
	"combat_enter_s": 1.0,            # sustained threat before combat music
	"combat_release_s": [4.0, 8.0],   # quiet after the threat genuinely cleared (rolled per fight)
	"region_enter_s": 10.0,           # stable seconds before a region override (8-12 s)
	"min_dwell_s": 20.0,              # minimum time between two base-context switches
	"signature_cooldown_s": 600.0,    # a region's signature piece plays at most this often
	"resume_rest_s": [5.0, 10.0],     # quiet before the music returns after silence / a boss
	"default_rest_s": [20.0, 45.0],
	"rest_scale": 1.0,                # tests shrink rests
	"loop_passes": 2,                 # looping pieces in a rotation (legacy surface: ~175 s)
	"loop_play_s": 170.0,             # ... when the pass length is unknown
	"end_fade_s": 8.0,                # a looping piece ending its turn fades out over this
	"arrival_fade_s": 4.0,            # music arriving with Krystal in a new area
	"arrival_stop_s": 2.0,            # an area without music fades the old one out over this
	"external_max_s": 180.0,          # how long a track started outside the director is left alone
	"default_phrase_bars": 8,
	"horror_silence_states": ["anticipation", "encounter"],
	"threat_radius": 20.0,            # threat monitor (director): metres around Krystal
	"engaged_s": 5.0,                 # damage dealt/taken this recently counts without line of sight
}


## Everything the selector needs, in one dictionary.
static func catalogue() -> Dictionary:
	return {"cues": CUES, "playlists": PLAYLISTS, "contexts": CONTEXTS, "areas": AREAS,
		"area_combat": AREA_COMBAT, "bosses": BOSSES, "tuning": TUNING}


## Cue ids m01..m27 in order.
static func cue_ids() -> Array:
	var out: Array = CUES.keys()
	out.sort()
	return out


## Seconds of music silence a horror event asks for (0 = none).
static func authored_silence_seconds(event_id: String) -> float:
	if AUTHORED_SILENCE.has(event_id):
		return float(AUTHORED_SILENCE[event_id])
	if event_id.begins_with("authored:"):
		return AUTHORED_SILENCE_DEFAULT
	return 0.0
