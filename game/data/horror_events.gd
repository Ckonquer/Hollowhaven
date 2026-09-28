extends RefCounted
## Data for the local horror director (src/horror/). Pure gameplay pacing: no network, no LLM.
## Director states: calm -> unease -> anticipation -> encounter -> recovery -> calm
##
## Event fields:
##   kind        sound | wrong_sound | glimpse | flicker | notice | scratch | silence | spawn | stalker_pass
##   zones       dungeon zones where it may fire: mine | ruins | silk
##   states      director states in which it is eligible
##   weight      base selection weight
##   cooldown    per-event cooldown (seconds)
##   major       true = counts as a major scare (never stacked; long recovery afterwards)
##   min_intensity  0 = Gentle, 1 = Standard, 2 = Intense
##   anchor      required anchor kind near the player: "" | sound | doorway | ceiling | floor | spawn
##   sound       sound name played (Audio); alt_sound when arachnophobia is ON
##   caption     caption text shown when captions are enabled
##   spider      true = spider-themed (uses alt visuals/sounds when arachnophobia is ON)

const INTENSITY := {
	0: {"name": "Gentle", "desc": "Fewer scares, no ambushes, softer sounds. Enemies deal less damage.", "event_rate": 0.45, "damage_mult": 0.6, "allow_major": false, "stinger_db": -12.0, "darkness": 0.75},
	1: {"name": "Standard", "desc": "The intended experience: tense and unsettling, with a few real scares.", "event_rate": 1.0, "damage_mult": 1.0, "allow_major": true, "stinger_db": -6.0, "darkness": 1.0},
	2: {"name": "Intense", "desc": "More frequent cues, darker shadows and bolder stalking. For horror fans.", "event_rate": 1.5, "damage_mult": 1.15, "allow_major": true, "stinger_db": -4.0, "darkness": 1.15},
}

const DIRECTOR := {
	"tick_seconds": 1.0,
	"global_cooldown": 14.0,           # min seconds between any two director events
	"major_cooldown": 90.0,            # min seconds between major events
	"recovery_seconds": 25.0,          # after encounter / death / major scare
	"do_nothing_weight": 3.0,          # the director often chooses to do nothing
	"max_active_threats": 3,           # director-spawned enemies alive at once
	"min_spawn_distance": 9.0,         # never spawn closer than this to the player
	"max_spawn_distance": 22.0,
	"linger_seconds": 12.0,            # standing still this long nudges tension upward
	"unease_after": 20.0, "anticipation_after": 45.0,
}

const EVENTS := {
	"distant_pickaxe": {"kind": "sound", "zones": ["mine"], "states": ["calm", "unease"], "weight": 3.0, "cooldown": 60.0, "major": false, "min_intensity": 0, "anchor": "sound", "sound": "dir_distant_pickaxe", "caption": "[distant pickaxe strikes]"},
	"creaking_timbers": {"kind": "sound", "zones": ["mine"], "states": ["calm", "unease", "anticipation"], "weight": 2.0, "cooldown": 40.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "dir_creak", "caption": "[timbers creak]"},
	"footsteps_behind": {"kind": "sound", "zones": ["mine", "ruins"], "states": ["unease", "anticipation"], "weight": 2.0, "cooldown": 80.0, "major": false, "min_intensity": 1, "anchor": "", "sound": "dir_footsteps", "caption": "[footsteps behind you]"},
	"pebbles_fall": {"kind": "sound", "zones": ["mine", "ruins", "silk"], "states": ["calm", "unease", "anticipation"], "weight": 2.5, "cooldown": 35.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "dir_pebbles", "caption": "[pebbles trickle down]"},
	"whisper": {"kind": "sound", "zones": ["ruins", "silk"], "states": ["unease", "anticipation"], "weight": 1.5, "cooldown": 90.0, "major": false, "min_intensity": 1, "anchor": "sound", "sound": "dir_whisper", "caption": "[a faint whisper]"},
	"wrong_mochi": {"kind": "wrong_sound", "zones": ["ruins", "silk"], "states": ["unease", "anticipation"], "weight": 1.0, "cooldown": 400.0, "major": false, "min_intensity": 1, "anchor": "sound", "sound": "dir_wrong_squeak", "caption": "[a familiar squeak... from somewhere deep below]", "once": true},
	"lantern_flicker": {"kind": "flicker", "zones": ["mine", "ruins", "silk"], "states": ["unease", "anticipation"], "weight": 2.0, "cooldown": 45.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "dir_flicker", "caption": ""},
	"far_glimpse": {"kind": "glimpse", "zones": ["mine", "ruins"], "states": ["anticipation"], "weight": 1.5, "cooldown": 120.0, "major": false, "min_intensity": 1, "anchor": "doorway", "sound": "", "caption": ""},
	"lumi_notices": {"kind": "notice", "zones": ["mine", "ruins", "silk"], "states": ["unease", "anticipation"], "weight": 2.0, "cooldown": 70.0, "major": false, "min_intensity": 0, "anchor": "doorway", "sound": "lumi_warn", "caption": "[Lumi chimes softly]", "needs_companion": "lumi"},
	"scratching_above": {"kind": "scratch", "zones": ["silk", "ruins"], "states": ["anticipation"], "weight": 2.0, "cooldown": 75.0, "major": false, "min_intensity": 0, "anchor": "ceiling", "sound": "dir_scratch", "alt_sound": "dir_scratch_soft", "caption": "[scratching above you]", "spider": true},
	"web_rustle": {"kind": "sound", "zones": ["silk"], "states": ["unease", "anticipation"], "weight": 2.0, "cooldown": 40.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "dir_web_rustle", "alt_sound": "dir_root_creak", "caption": "[something shifts in the silk]", "alt_caption": "[roots creak]", "spider": true},
	"silence": {"kind": "silence", "zones": ["mine", "ruins", "silk"], "states": ["anticipation"], "weight": 1.5, "cooldown": 120.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "", "caption": "[the ambience goes quiet]"},
	"gloomling_ambush": {"kind": "spawn", "zones": ["mine", "ruins"], "states": ["anticipation"], "weight": 1.2, "cooldown": 150.0, "major": true, "min_intensity": 1, "anchor": "spawn", "enemy": "gloomling", "count": [1, 2], "sound": "gloomling_alert", "caption": "[hissing nearby]"},
	"stalker_pass": {"kind": "stalker_pass", "zones": ["silk"], "states": ["anticipation"], "weight": 1.5, "cooldown": 110.0, "major": true, "min_intensity": 0, "anchor": "ceiling", "sound": "weaver_skitter", "alt_sound": "shade_drift", "caption": "[skittering overhead]", "alt_caption": "[something drifts overhead]", "spider": true},
}

# --- Chapter Two: the Hushed Works (works module C7, ADDITIVE) --------------------------------------------------
## The Works director does NOT use EVENTS above (Chapter One pacing and RNG stay untouched): the Works area
## hands WORKS_EVENTS to its director through area.director_config() (src/horror/director.gd setup). Only the
## hw_* zones of docs/CHAPTER_TWO_SPEC.md §7.2 appear here. Quiet on purpose (no event lists them): the safe
## rooms, the Tool Lockers (its taught Hollow Drudge fight gets no ambush on top), the Hall of Closed Eyes
## (quiet after combat; it holds an authored moment instead) and the boss / authored rooms of the deep module.
## Puzzle rooms (WORKS_PUZZLE_HOLDS) are held quiet by the area until their line is restored.
## Rooms 9-14 (deep module) get events only where it places matching anchors: hw_winch scratch needs
## "ceiling" anchors, hw_wisp_drift needs "spawn" anchors in hw_wrong_landing; ambient sounds need none.
const WORKS_ZONES := ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge",
	"hw_lightwell", "hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]
const WORKS_QUIET_ZONES := ["hw_landing", "hw_lockers", "hw_eyes", "hw_refuge", "hw_crossing", "hw_porch", "hw_throat", "hw_vault"]
## Zone -> the line flag that releases its puzzle hold (while unset the director keeps quiet there).
const WORKS_PUZZLE_HOLDS := {"hw_sluice": "ch2_line_water", "hw_bells": "ch2_line_bell", "hw_lightwell": "ch2_line_light"}

const WORKS_EVENTS := {
	"hw_rail_hum": {"kind": "sound", "zones": ["hw_rails", "hw_wrong_landing"], "states": ["calm", "unease"], "weight": 2.5, "cooldown": 70.0, "major": false, "min_intensity": 0, "anchor": "sound", "sound": "mine_cart", "caption": "[the rails hum somewhere down the line]"},
	"hw_far_clank": {"kind": "sound", "zones": ["hw_rails", "hw_sluice", "hw_bells", "hw_lightwell", "hw_winch"], "states": ["calm", "unease", "anticipation"], "weight": 2.0, "cooldown": 50.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "mine_hit", "caption": "[a far-off clank of metal]"},
	"hw_drip_echo": {"kind": "sound", "zones": ["hw_rails", "hw_sluice", "hw_lightwell"], "states": ["calm", "unease"], "weight": 2.0, "cooldown": 45.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "water_drip", "caption": "[water drips, and the echo drips twice]"},
	"hw_footsteps": {"kind": "sound", "zones": ["hw_rails", "hw_wrong_landing"], "states": ["unease", "anticipation"], "weight": 1.5, "cooldown": 90.0, "major": false, "min_intensity": 1, "anchor": "", "sound": "dir_footsteps", "caption": "[footsteps, keeping a little behind you]"},
	"hw_borrowed_hum": {"kind": "sound", "zones": ["hw_rails", "hw_bells", "hw_wrong_landing"], "states": ["unease", "anticipation"], "weight": 1.2, "cooldown": 110.0, "major": false, "min_intensity": 1, "anchor": "sound", "sound": "dir_whisper", "caption": "[a hum, like a choir learning a tune]"},
	"hw_lamp_flicker": {"kind": "flicker", "zones": ["hw_rails", "hw_sluice", "hw_bells", "hw_lightwell", "hw_winch", "hw_wrong_landing"], "states": ["unease", "anticipation"], "weight": 2.0, "cooldown": 60.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "dir_flicker", "caption": ""},
	"hw_lumi_notices": {"kind": "notice", "zones": ["hw_rails", "hw_sluice", "hw_bells", "hw_lightwell", "hw_winch", "hw_wrong_landing"], "states": ["unease", "anticipation"], "weight": 2.0, "cooldown": 80.0, "major": false, "min_intensity": 0, "anchor": "doorway", "sound": "lumi_warn", "caption": "[Lumi chimes softly]", "needs_companion": "lumi"},
	"hw_silence": {"kind": "silence", "zones": ["hw_rails", "hw_wrong_landing"], "states": ["anticipation"], "weight": 1.2, "cooldown": 150.0, "major": false, "min_intensity": 0, "anchor": "", "sound": "", "caption": "[the hum of the works falls silent]"},
	"hw_winch_dust": {"kind": "scratch", "zones": ["hw_winch"], "states": ["anticipation"], "weight": 2.0, "cooldown": 80.0, "major": false, "min_intensity": 0, "anchor": "ceiling", "sound": "dir_scratch", "alt_sound": "shade_drift", "caption": "[scratching above you]", "alt_caption": "[dust drifts down from above]", "spider": true},
	"hw_wisp_drift": {"kind": "spawn", "zones": ["hw_wrong_landing"], "states": ["anticipation"], "weight": 1.0, "cooldown": 180.0, "major": true, "min_intensity": 1, "anchor": "spawn", "enemy": "borrowed_wisp", "count": [1, 1], "sound": "shade_whisper", "caption": "[a warm light that lights nothing drifts closer]"},
}
