extends RefCounted
## ECHO TRIALS (MP §8 "Echo Trial", §15 "Echo Trials"; docs/CHAPTER_TWO_SPEC.md §1, §3 "trials"). Pure data, read by
## src/world/areas_ch2/echo_trial.gd (the area, its record / reward rules and the trial menu text) and the arena
## builders in src/world/trial/*. Echo Trials are REMEMBERED challenges: optional replays of the Weaver Matron,
## Count Velour and the Borrowed Choir in their own instance (area "echo_trial"), offered once the story fight is
## won, entered from that fight's checkpoint ("origin") and always returning there.
##
## Isolation (never undone history): a trial never reads or writes a story flag, never emits Events.boss_defeated,
## never revives a main-world boss, never gives a Heartseed. Its own state lives in GameState.trials[<id>]
## (the trial-scoped record and ledger, see echo_trial.gd record()):
##   {"clears": int, "best_seconds": float, "last_seconds": float, "repeat_paid": int, "paid": {item: total}}
##   (+ "pending": {item: n} and "pending_clears": int while a repeat gift waits for the trip home)
## Rewards:
##   * FIRST clear: the trial's content bundle `first_reward` through GameState.grant_once (the reward ledger:
##     exactly once per save). Its only flag is the trial's pattern-unlock flag (ch2_trial_<id>), which unlocks a
##     UNIQUE cosmetic pattern sewn at the Loom (`pattern`, in data/appearance.gd PATTERNS with its Loom recipe in
##     data/recipes.gd). The three bundles are defined in FIRST_REWARDS below; data/sources.gd REWARDS mirrors them
##     (the catalogue copy is what the area reads through ItemDB; tests check the two agree).
##   * every LATER clear: modest renewable resources, `repeat` plus `bonus` on every `bonus_every`-th clear, earned
##     once per won visit and paid on ARRIVAL back at the origin (never inside the echo: they wait in the trial's
##     record as "pending" until then; echo_trial.gd pay_pending), then recorded in the trial's own ledger. Bounded:
##     never more than MAX_REPEAT_PER_CLEAR items per clear, never a key item, never a flag, no daily limit, no
##     timers (MP §15: no FOMO).
## Keys per trial: title / alt_title (arachnophobia wording) / subtitle, boss (data/enemies.gd id), requires_flag
## (the won story fight that offers it), origin {area, spawn} (the checkpoint it is entered from), origin_name (that
## checkpoint in words, for the "the echo's gift waits for you back at ..." toast), builder (arena
## builder script; "" = the Matron's own room inside echo_trial.gd), memory (the trial menu text; "%s" = the boss's
## display name), intro (said on arrival), fade (said fade_delay s after a win), exit_text, ambience (existing loop names only),
## first_reward, pattern, pattern_name (the pattern's name; the catalogue's name wins, this is the fallback),
## first_message, repeat, bonus_every, bonus. `entry` (optional): where the origin area places the echo stone.
## The Choir stone (lead decision L10): kept at (153.6, -28, 27.6), 2.7 m from the Bell Throat checkpoint, pending
## an on-screen check in the visible run; only if the west wall rocks touch it, move it to about (153.4, -28, 24.75).

const MATRON := "matron"
const VELOUR := "velour"
const CHOIR := "choir"
const ORDER := ["matron", "velour", "choir"]

## A repeat clear never pays more items than this in total (repeat + bonus; tests).
const MAX_REPEAT_PER_CLEAR := 6

const TRIALS := {
	"matron": {
		"title": "Echo Trial: The Thread Above", "alt_title": "Echo Trial: The Hollow Above",
		"subtitle": "a remembered challenge", "boss": "weaver_matron", "requires_flag": "weaver_defeated",
		"first_reward": "rw_trial_matron_first",
		"first_message": "The echo remembers you. The Moon Moth Shawl pattern can now be sewn at the Loom.",
		"pattern": "pat_moon_moth", "pattern_name": "Moon Moth Shawl",
		"repeat": {"silk": 3, "glowcap": 2}, "bonus_every": 3, "bonus": {"echo_shard": 1},
		"origin": {"area": "below", "spawn": "cp_arena"}, "origin_name": "the chamber door",
		"builder": "",
		"memory": "An echo of your battle with %s, remembered by the stone. It is a memory, not undone history: the real chamber stays at peace, and nothing on your journey changes. Leave by the pale door at any time, or fall, and you wake here at the lantern.",
		"intro": "A memory of the Heartseed Chamber. Nothing here can change what really happened - the true chamber stays at peace. Leave through the pale door whenever you like.",
		"fade": "The echo fades. The chamber is only a memory again.", "fade_delay": 0.0,
		"exit_text": "Leave the echo (back to the chamber door)",
		"ambience": "amb_silk",
	},
	"velour": {
		"title": "Echo Trial: The Last Waltz", "alt_title": "Echo Trial: The Last Waltz",
		"subtitle": "a remembered challenge", "boss": "count_velour", "requires_flag": "ch2_velour_defeated",
		"first_reward": "rw_trial_velour_first",
		"first_message": "The echo remembers you. The Moonlit Masquerade pattern can now be sewn at the Loom.",
		"pattern": "pat_echo_masquerade", "pattern_name": "Moonlit Masquerade",
		"repeat": {"lantern_wax": 2, "moonpetal": 2}, "bonus_every": 3, "bonus": {"woven_cloth": 1},
		"origin": {"area": "moonveil_manor", "spawn": "manor_ballroom"}, "origin_name": "the ballroom candles",
		"builder": "res://src/world/trial/velour_trial.gd",
		"memory": "An echo of your evening with %s, remembered by the house. It is a memory, not undone history: the Count stays a (mostly) gracious host, and nothing on your journey changes. Leave by the pale door at any time, or fall, and you wake here by the candles.",
		"intro": "A memory of the Count's Gallery on the night of the invitation. Nothing here can change what really happened - the real Count is still a (mostly) gracious host. Leave through the pale door whenever you like.",
		"fade": "The echo fades. The Gallery is only a memory again.", "fade_delay": 2.4,
		"exit_text": "Leave the echo (back to the ballroom candles)",
		"ambience": "",
	},
	"choir": {
		"title": "Echo Trial: The Borrowed Song", "alt_title": "Echo Trial: The Borrowed Song",
		"subtitle": "a remembered challenge", "boss": "borrowed_choir", "requires_flag": "ch2_choir_defeated",
		"first_reward": "rw_trial_choir_first",
		"first_message": "The echo remembers you. The Chime Chorister pattern can now be sewn at the Loom.",
		"pattern": "pat_echo_chime", "pattern_name": "Chime Chorister",
		"repeat": {"echo_shard": 2, "iron_ore": 2}, "bonus_every": 3, "bonus": {"moon_crystal": 1},
		"origin": {"area": "hushed_works", "spawn": "bell_throat"}, "origin_name": "the Bell Throat",
		"entry": {"area": "hushed_works", "pos": Vector3(153.6, -28.0, 27.6), "yaw_deg": 90.0},
		"builder": "res://src/world/trial/choir_trial.gd",
		"memory": "An echo of the song in the vault, remembered by the bells. It is a memory, not undone history: the lanterns keep their true signal, and nothing on your journey changes. Leave by the pale door at any time, or fall, and you wake here at the lantern.",
		"intro": "A memory of the Choir Vault. Nothing here can change what really happened - the lanterns keep their true signal. Leave through the pale door whenever you like.",
		"fade": "The echo fades. The vault is only a memory again.", "fade_delay": 2.4,
		"exit_text": "Leave the echo (back to the Bell Throat)",
		"ambience": "amb_boss",
	},
}

## First-clear content bundles of the trials (same shape as data/sources.gd REWARDS; "by": "content" = the trial
## grants them itself through GameState.grant_once). data/sources.gd REWARDS mirrors all three exactly (tests check
## that they agree).
const FIRST_REWARDS := {
	"rw_trial_matron_first": {"items": {}, "flags": ["ch2_trial_matron"], "by": "content", "who": "echo trial: first Matron clear (isolated trial reward state)"},
	"rw_trial_velour_first": {"items": {}, "flags": ["ch2_trial_velour"], "by": "content", "who": "echo trial: first Count Velour clear (isolated trial reward state)"},
	"rw_trial_choir_first": {"items": {}, "flags": ["ch2_trial_choir"], "by": "content", "who": "echo trial: first Borrowed Choir clear (isolated trial reward state)"},
}


static func trial(id: String) -> Dictionary:
	return TRIALS.get(id, {})


static func ids() -> Array:
	return ORDER.duplicate()


## What a repeat clear pays when it is the trial's `clears`-th clear in total: `repeat`, plus `bonus` on every
## `bonus_every`-th clear. Pure (the area gives the items and records them).
static func repeat_items(id: String, clears: int) -> Dictionary:
	var t := trial(id)
	var give: Dictionary = (t.get("repeat", {}) as Dictionary).duplicate()
	var every := int(t.get("bonus_every", 0))
	if every > 0 and clears > 0 and clears % every == 0:
		var bonus: Dictionary = t.get("bonus", {})
		for k in bonus:
			give[k] = int(give.get(k, 0)) + int(bonus[k])
	return give


## "2:05" (minutes:seconds) for a clear time; "--:--" when there is none yet.
static func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--"
	var s := int(roundf(seconds))
	return "%d:%02d" % [int(float(s) / 60.0), s % 60]
