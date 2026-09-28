# Integration pass 2 (after Wave D) — decision record

After the Chapter Two enemies (C5), the three Chapter Two bosses (C6a Count Velour, C6b the Crossing Matron, C6c the Borrowed Choir)
and Wave D (D1 echo trials, D2 expeditions, D3 music box, D4 docs & onboarding hints) were built and reviewed, the lead collected every
integrator request from those build / review reports, the eleven items pass 1 had deferred (`D01`-`D11`, see
`INTEGRATION_WAVE_BC.md` §6) and the four follow-ups pass 1 found (`F01`-`F04`, its §7) into one plan of **76 requests**:
10 lead decisions (`L01`-`L10`), 10 pass-1 deferred items (`D05` became `L06`), 4 follow-ups and 52 new requests (`P01`-`P58`; unused
numbers were merged into others). By status: 32 to apply as specified, 37 carrying a lead decision (including the deliberate
"keep as is" ones), 6 already done, 1 obsolete. Ten fixer groups (G1-G10, `docs/ch2/WAVES.md` "Integration pass 2") applied it in
parallel, each owning disjoint files.

This file records **every request of that plan with its decision and reason**, including the ones that deliberately change nothing,
so a later session does not reopen them by accident. The groups' own notes, outcomes and test evidence are in
`docs/ch2/INTEGRATION_PASS2.md` (one section per group). The conventions the pass produced are summarised in `docs/ARCHITECTURE.md`
("Chapter Two conventions") and mapped in `docs/ch2/maps/*.md` (combat_enemies §12, world_areas §8, state_save_data §14, ui §12);
what is still open is in `KNOWN_ISSUES.md`.

Ground rules (unchanged): the spec (`docs/CHAPTER_TWO_SPEC.md`) wins over the master prompt (MP) where they disagree; legacy ids,
coordinates and saves never change; rewards are granted once through the ledger; comfort and arachnophobia rules apply everywhere.
`tools/qa/*` was being edited by the QA-bot agent during the pass and was off-limits; the `.uid` import (D09) runs last, alone.

## 1. Lead decisions (binding)
| id | problem | decision | why | group |
|---|---|---|---|---|
| L01 | The Velvet Wing's drain broke on EVERY light source except Krystal: a lit Lumi within ~3.7 m broke every drain, Krystal's own raised lantern never did. | Only ward-light breaks it - lit ward candles, lamps / lantern posts / placed light structures, braziers, Krystal's raised lantern while she stands inside the drain mark - plus a line-of-sight break, range or a hit. Lumi's passive glow does NOT; her Glimmerstep pulse DOES. | The counter must be a readable player choice: a pet's glow would defeat the mechanic without anyone doing anything, a Glimmerstep is a deliberate skill, and "raise your lantern inside the mark" is the taught rule. | G1 |
| L02 | The Warden arena set the spawner's cleared flag before the spawner cleared itself, so `TEXT["warden_clear"]` never showed on a real defeat. | The arena emits `TEXT["warden_clear"]` itself on the FIRST clear; the spawner-flag logic stays untouched. | The player should hear that the quarry is safe; changing the flag order would risk the saved-flag logic. | G2 |
| L03 | Do elites get the boss timing assist? | Yes: the Knotted Elder and the Quarry Warden stretch wind-ups and recoveries ×1.5 under Settings `timing_assist` (already implemented; verify only). | The setting promises roomier timing for boss mechanics; elites are arena fights. | G1 |
| L04 | Brood Skitter telegraph 0.7 s. | 1.0 s in data (already applied in pass 1; verify only). | MP rule: committed attacks warn 1.0-1.4 s. | G1 |
| L05 | Should the Hollow Drudge scale with horror intensity at the outdoor Candleyard? | Only underground (below, tobin_annex, hushed_works; `threat_damage_mult()` follows the area; verify only, do not regress). | Horror intensity is an underground setting; surface areas never scale. | G1 |
| L06 (was D05) | `test_enemies_ch2_mimic.test_dormant_is_decor_that_twitches_in_pairs` was timing-flaky. | Optional mimic setup key `seed` (seeds its RNG; default stays random) and a fixed seed + a window that ends between pairs in the test. No gameplay change. | A flaky test hides real regressions. | G1 |
| L07 | Pass-1 D08 and the `data/quests_ch2.gd` header said the Velour / Choir trials open on `ch2_trials_open` + the boss flag; the code (D1) checks only the boss flag. | **No extra `ch2_trials_open` gate.** Each trial opens right after its boss is defeated: Matron after `weaver_defeated`, Velour after `ch2_velour_defeated`, Choir after `ch2_choir_defeated` (`data/trials.gd` `requires_flag`). `ch2_trials_open` stays a harmless story flag (its "Old echoes stir..." step message is flavour). Docs updated (G9); the data header line is P56 (G8). | The stone already stands where the fight was won and the manor test expects it right after the defeat; a second, invisible gate would hide content the player has earned for no story reason. | G9 (docs), G8 (P56) |
| L08 | Repeat-clear rewards were given inside `echo_trial`: with a full backpack they dropped at her feet there, and since every trial shares that area id they reappeared inside another arena later (possibly inside a pillar). | Repeat-clear items are paid on arrival back at the origin, never dropped inside the trial: `record_clear()` stores them in `GameState.trials[id]["pending"]` (+ `pending_clears`), toasts "The echo's gift waits for you back at <origin>."; `echo_trial.init()` connects `Events.area_loaded` -> `pay_pending(area_id)` (any non-transient area = the origin: leaving, falling and Continue all land there), ledger first, then `give_item` (overflow drops at the safe origin checkpoint), one toast. Same path for all three trials; the first-clear ledger grant is unchanged. | Rewards must never be lost or land somewhere unreachable; the origin checkpoint is safe and is where every exit lands. | G3 (+ G7 wiring) |
| L09 | The Velour / Choir first clears paid nothing: no catalogue entries, no unlock flags, no patterns. | Apply D1's requests 1-3 together: `rw_trial_velour_first` / `rw_trial_choir_first` in `data/sources.gd` REWARDS (exact mirrors of `data/trials.gd` `FIRST_REWARDS`); `ch2_trial_velour` / `ch2_trial_choir` in `data/unlocks.gd`; patterns `pat_echo_masquerade` "Moonlit Masquerade" (masquerade mask worn in the hair - never over the face - + opera cloak) and `pat_echo_chime` "Chime Chorister" (chime ribbons + chorister capelet) in `data/appearance.gd` with `accessory_builder.gd` visuals, and the two Loom recipes. Saves that already cleared a trial get the pattern through the flag already set (no migration). | MP §15: every trial's first clear gives a unique cosmetic pattern. | G4 |
| L10 | The Bell Throat stone stands at (153.6, -28, 27.6), not in the west-wall bay D08 had reserved (z 23.4-26.1). | Keep it for now; screenshot it in the visible run; only if the wall rocks touch it move it to about (153.4, -28, 24.75) (one data line). | It works and is 2.7 m from the checkpoint; nobody has seen either spot on screen. | G3 (verify), pending check |

## 2. The pass-1 deferred list (D01-D11)
| id | item (pass 1) | pass-2 outcome | group |
|---|---|---|---|
| D01 | QA bot: confirm Meet Krystal, answer the wardrobe card | Done by the QA-bot agent (`playthrough.py` clicks "Confirm"; `ch2/s1_continuation.py` opens "Open the wardrobe", or the pause-menu Wardrobe headless). No integrator change. | QA agent |
| D02 | Optional wardrobe hotkey | **Decision:** key **O** (free: no binding, debug key or build fallback uses it; not Q/E, which switch wardrobe categories; not Z/P/N), rebindable; same rules as the pause-menu Wardrobe (full-screen, pauses, only in ordinary play). Settings action `wardrobe` in `DEFAULT_BINDINGS` / `REBINDABLE`, `ui_root.HOTKEYS`, the controls overlay, HUD token `{wardrobe}`; a settings file without it gets the default. | G6 |
| D03 | Build keys as Settings actions | `build_undo` Z, `build_recolor` P, `build_variant` N in `DEFAULT_BINDINGS` + `REBINDABLE` ("Build: Undo last piece", "Build: Recolour", "Build: Pumpkin face"), controls overlay Building rows, tokens `{undo}` `{recolor}` `{variant}`; `build_mode.gd` unchanged (it prefers the InputMap action; `FALLBACK_KEYS` stay). The docs' "Z, P and N can't be changed" lines went (P49). | G6, G9 |
| D04 | `expose(seconds)` for light-fearing enemies (Glimmerstep calls it) | **Decision:** only the ordinary light-fearing enemies: Velvet Wing (breaks an active drain, reason "light", consistent with L01) and Borrowed Wisp (a forced reveal for `seconds`, like a lantern reveal, subject to the P08 dazzle cooldown). NOT `count_velour`, `crossing_matron`, `borrowed_choir`. | The bosses' light rule is their arena mechanic (braziers, ward candles, lantern anchors); MP 13: pets and equipment never bypass the learned interaction (companion_combat already skips boss hazards). | G1 |
| D05 | Deterministic mimic test | Became L06. | G1 |
| D06 | Quarry Warden charge off the L2 edge | The charge lane is clipped so its end stays within `arena_radius` - 1 m of the centre (the red lane shows the clipped length), and "no floor within ~1 m below the next step" is a wall bonk (stun while any pillar is intact, exposed when none: never unwinnable). | G1 |
| D07 | Boss contracts to verify | Done: Velour emits `boss_defeated("count_velour")` once in story mode, one node, `start_fight` / `reset_fight`, the manor's setup keys, the first bow said once; the Crossing Matron takes `crossing_arena.boss_params()` and cut threads never regrow; the Choir takes `choir_arena.boss_params()` (anchors, anchor_nodes, resonators, symbols). | verified |
| D08 | Echo Trials for Velour and the Choir | Done by Wave D1 (Gallery copy with real ward candles, vault copy with real anchors / resonators, echo stones in the manor ballroom and the Bell Throat). **Its `ch2_trials_open` gate is superseded by L07** (no such gate); the rest is L08, L09, L10, P28-P32. | D1 |
| D09 | `.uid` files | Run `tools/godot.sh --headless --path game --import` ONCE after every other group has landed and the full suite is green, with no other Godot process; then `parse_all` + the full suite again; commit only new `*.gd.uid` (375 of 681 scripts had none). | G10 (last) |
| D10 | New enemy voices | **Decision: not in this pass.** Every enemy / boss uses existing, test-verified sound names (safe; arachnophobia swaps work). All new-voice requests are merged into ONE open item: the Wave B/C enemies (Brambleback, Lantern Moth, Hollow Drudge, Brood Skitter / Pale Sprout, Knotted Elder), C5 (mimic stem rustle / snap / roll, Patchwalker straw / rake / splat, Velvet Wing squeak / cape / drain, Bellcap swell / toll, wisp false chime / gutter, Warden grind / triple toll / crack), Velour (`velour_bow`, `velour_laugh`, `bat_flock`, `velour_reform`, `candle_snuff`, `velour_dazzled`, `crown_glint`, `enchantment_break`), the Crossing (`matron_final_click` / `mother_final_sigh`, `matron_thread_whip` / `mother_roots_lash`, `matron_retreat` / `mother_withdraw`), the Choir (`choir_bell_toll`, `choir_ring_hum`, `choir_welcome_chord`, `choir_release_chimes`, `choir_mask_fall`, `choir_form_burst`, `choir_flame_settle`). One dedicated audio pass later: `tools/audio` sfx generators + Audio index / aliases, then point each script's / data's voice at its names (arachnophobia variants for the Crossing), then a human listening check. | Audio generation touches `assets/` and needs an import and a listener; doing it piecemeal inside an integration pass would risk the working, verified names. Listed in `KNOWN_ISSUES.md`. | later |
| D11 | QA bot reads the new telemetry | Done by the QA-bot agent (`tools/qa/ch2/s*.py` read chapter2 / tracker / optional / equipment / appearance / companions). | QA agent |

## 3. Pass-1 follow-ups (F01-F04)
| id | item | outcome | group |
|---|---|---|---|
| F01 | The wardrobe test expected "Return to safety" in `echo_trial` | Done in pass 1's test run (expects "Leave the trial", R17). | - |
| F02 | Blink flake in `test_player_avatar` | Done in pass 1 (the test pushes the next blink out of its window). | - |
| F03 | R38 never landed: `ch2_quarry` showed only "Light the quarry lamp" | ChapterLog display-only objectives: `"display": true` rows are listed with their done state but ignored by `step_done()`; `ch2_quarry` lists "Calm the Quarry Warden" (`hr_warden_defeated`) and "Mend the mineral winch" (`ch2_winch_repaired`) before the lamp; completion still reads the lamp alone (a save with the lamp lit and no Warden flag never stalls). | G8 |
| F04 | The runner's isolation repairs leaks on every full run (stray projectiles / particles, `Game._bosses`, zone flags, Reach world items) | **Decision:** no per-suite cleanup in this pass (another agent owned the test run); the runner's ISOLATION guard stays the safety net. Recorded as a test-hygiene item in `KNOWN_ISSUES.md`. | G9 (record) |

## 4. Design calls on new requests (decision status)
| id | question | decision | why |
|---|---|---|---|
| P03 | Let `enemy_base._on_player_died()` return custom non-committed states (stuck, waking, exposed) to idle? | Keep the per-script overrides (mimic, velvet wing, warden already call super and are tested); no new base hook. | Working, tested code; a base change would touch every legacy enemy. |
| P06 | Boss music for the Quarry Warden? | Keep: an elite, not one of the four bosses; the director ignores it as a boss and the Reach's combat music (m22) follows the threat. | Boss music is reserved for the story bosses. |
| P08 | Toggling the lantern re-dazzled the Borrowed Wisp on every reveal (stun-lock). | Dazzle cooldown 6 s: a reveal inside it still reveals (reachable, vulnerable) but neither dazzles nor cancels the wind-up. Tested. | Keeps the lantern rule readable and fair without making the wisp trivial. |
| P09 | A veiled wisp can sweep while its tell says "raise your lantern". | Keep: the sweep is marked on the ground with a 0.8 s delay; the tell teaches the counter. | MP: a marked, delayed sweep is fair. |
| P10 | The veiled wisp floats at 2.9 m, above melee reach, so a swing gives no feedback. | Show the existing one-time hint `hint_borrowed_wisp_blocked` the first time Krystal is within ~4 m (horizontal) of a veiled, visible wisp while threatened; no attack detection, no damage change. | Feedback without new rules. |
| P11 | Only the Velvet Wing feints on Intense; the clod / Warden pulses / charge wind up 1.6 s (above 1.0-1.4). | Keep both; document only. | Intense for ordinary enemies = less rest (feints are a boss / taught tell); longer tells are fairer, never shorter. |
| P12 | Dormant mode is unused by the districts; a spawner placing a dormant mimic on a disallowed spot would respawn it every tick. | Keep; `combat_enemies.md` §12 says spawners must not pass `dormant` (`spot_allowed()` rejects crop / safe spots). | The orchard pocket already teaches "twitch twice -> inspect" with its own props. |
| P13 | On Gentle the first Borrowed Wisp could appear inside the final boss fight. | Add ONE fixed encounter: `data/works_layout.gd` SPAWNERS `hw_sp_eyes_wisp` (borrowed_wisp ×1, respawn 1440 min, no flag, no message) in the Hall of Closed Eyes on a validated spot away from the lantern hook, lore and exits, not in a safe zone. | Teaches the lantern reveal before the Choir; data zones already name `hw_eyes`. |
| P16 | Velour: companion blows during the channel lift the 8 % mask floor; a light-stagger lands ~13 m away; a never-dodging player takes > 100 HP on Standard; bot pacing 65-90 s. | Keep all; real-input checks listed. | Pets attack exposed phases normally (MP 13); the rest is tuning for real play. |
| P21 | Crossing: two Brood Skitters may leap 0.85 s apart; no body collision; rules assume the bridge centre line at z = 0; long far-anchor pounces may read as a teleport; knockback can fizzle a kindle. | Keep all: she never pounces while minions live (release instead of pounce); z = 0 matches the layout and is documented (P07); the rest is visual / real-input tuning. | No unfairness in the rules; the look needs a screen. |
| P22 | `data/enemies.gd` borrowed_choir said arena_radius 15 (vault 12.4) and telegraphs 1.8/1.5/1.6 (rules 1.1-1.4); strike zones reused the rings row. | Make the data honest (descriptive only; `choir_rules.gd` stays the source of truth): arena_radius 12.4, each telegraph = the rules' Standard value, a `strikes` zone row (damage 16, radius 1.7). | Data that lies misleads the journal / catalogue and later tuning. |
| P24 | Let a raised lantern anchor accept a re-raise that refreshes its burn? | Keep: the Choir's lower-the-hook workaround is tested; the practice anchor's 8 s lockout shows a disabled "Your lantern burns on the anchor" prompt. | Readable, no softlock; not worth a mechanic change now. |
| P25 | A `--sandbox=choir` scenario? | No. | `choir_preview.gd` and `--area=hushed_works --choir-phase=2|3` already cover visual / QA checks. |
| P27 | Choir: winnable without attacking; the sweep follows 60 % of the warning; no Lantern = no progress; harness resonators at 10.6 m vs 9.3 m; `rings.overlapping()` allocates while rings fly. | Keep all; sweep fairness and the 4-6 min pace go to real-input checks. | MP 13.3 allows "three exposures or an equivalent damage threshold"; the Lantern is a Chapter One key item (she can always leave); the allocation is small and bounded. |
| P38 | `Game.AREA_WARMUP` had nothing for the Reach, the echo trial or the new bosses. | Apply: `hallowmere_reach` (district + expedition enemies), the bosses in their areas, `echo_trial` (both trial bosses + both arena builders + the Matron). | R05's rule (compile behind the fade, ≤ ~1 s) applies to them now that they exist; prefetch is idempotent and never blocks. |
| P39 | Mastery Wayfinding XP on a route's first completion? | Apply: `complete()` calls `Mastery.award("wayfinding", "expedition:" + template, xp)` on the FIRST completion only, safe-loaded. | MP 5.3: masteries grow with ordinary play; dedupe by kind keeps it once per route; no other side effect. |
| P40 | Expedition-only decor recipe unlocks (new `exp_*` flags)? | No: keepsakes stay ready-made decorations and dyes; no new flags or recipes. | MP 15: no required rare drops; fewer moving parts. |
| P42 | The dye keepsake unlocks the Loom palette directly while the texts said "the ... dye recipe". | Keep the direct unlock (a keepsake is a gift; post-Choir only) and make the texts honest ("Sometimes: a new dye colour (Pumpkin or Rose) for clothes and furniture, or a festival decoration"). | Cozy, and the words now match what happens. |
| P43 | Setting a run aside mid-fight makes the living group vanish (only from the Commons outpost board); stale "until Game wires init()" comments. | Keep the vanish (harmless, player-chosen); update the comments once P34 lands. | Nothing is lost; the home board is far from every stop. |
| P46 | Move the selector's `PREVIEW_DEF` ("musicbox", priority 40) into `data/music.gd` CONTEXTS? | Apply; the selector keeps its fallback for older data. | Golden rule: data-driven, one table for every music context. |
| P47 | Music Box open behaviours: nothing discovered while muted (a started preview stays "Now playing"), no resume after a fight, previewing the current piece continues it, favourites may add e.g. m11 to the Haven rotation (≤ 2 per round). | Keep all; document the muted behaviour (ARCHITECTURE, What's New). | Safe, bounded and cozy. |
| P50 | Onboarding pacing untuned (a Chapter One save can see ~5 tips in its first minutes); the fight check relies on the music director. | Keep the timings (2.5 s calm, 25 s gap, 30 s after horror) until a real play session; listed in the pending checks. | Tuning needs a player, not a guess. |
| P58 | The Velour memory starts with all three candles lit (no teaching candle); his line and the fade line follow 2.4 s apart. | Keep. | A trial replays a fight she has already won (the candle was taught in the story); lit candles keep phases B / C fair. |

## 5. Applied requests (by group)
The code is the source of truth; the last column is what G9 found when it re-checked the files while writing this record (the
groups worked in parallel; their own sections in `INTEGRATION_PASS2.md` have the test evidence).
| group | requests | summary | seen in code |
|---|---|---|---|
| G1 enemies | L01, L03-L06, D04, D06, P01, P02, P04, P20, P23, P57 (+ decisions P03, P08-P12, P21, P22, P25, P27) | Velvet Wing ward-light rule + `lantern_in_mark`; seeded mimic; `expose()` on Velvet Wing / Borrowed Wisp; Warden lane clip + ledge bonk; opt-in intensity helpers in `enemy_base` (the six C5 copies removed); `fire_projectile` `dir` / `on_hit` / `kind` (Patchwalker uses it); `telegraph_fx.move_ring` (Velvet Wing's drain mark); static attack-token API used by the Choir; honest Crossing / Choir data rows; wisp dazzle cooldown + proximity hint; Choir trial retry hint | yes |
| G2 boss arenas & world hooks | L02, P14, P15, P17, P18, P19 (+ decisions P13, P16, P24) | Warden clear toast; the manor's freed resident appears after Velour's 1.4 s dispersal (instant on load); Velour trial retry hint; the Crossing gate drops after the Matron's retreat, the arena ignores a downed Krystal, `boss_params()` passes `rail`; the Hall of Closed Eyes wisp | yes |
| G3 echo trial flow | L08, P28, P30, P31, P32 (+ decisions L10, P58) | Repeat gifts paid on arrival at the origin (`pending`, `pay_pending`, `init`); the Below's stone uses `menu_text("matron")`; the stone's refusal names a fight only when a boss is active; the Velour trial test reads `LEAVE_MARGIN`; the trials data header / test assert the patterns | yes |
| G4 trial patterns & reward catalogue | L09 (+ decision P40) | Trial bundles, unlock flags, the two patterns with four avatar parts, the two Loom recipes | yes |
| G5 expeditions surfaced | P35, P36, P41 (+ decisions P39, P42, P43) | Reach map expedition pins + current-stop ring + `exp_*` ids + legend; the tracker's `expedition` card (only in place of signpost / done / hidden); first-completion Wayfinding XP; honest reward texts; comments; test rename | yes |
| G6 UI shell & input bindings | P33, D03 (+ decision D02) | `"expedition"` (fullscreen) and `"music_box"` (not fullscreen) panels registered; wardrobe key O; rebindable build keys; controls overlay Building column; HUD tokens | yes |
| G7 session wiring & music data | P34 (+ decisions P06, P38, P46, P47) | `Game.wire_session_systems()` also inits Expeditions, the Music Box and the Echo Trial gift payer and attaches the onboarding hints; `AREA_WARMUP` for the Reach, the bosses and the trials; the "musicbox" context in `data/music.gd`; music box behaviour notes | yes |
| G8 story & progression data | F03, P05, P56 | ChapterLog display rows + the two quarry rows; Mastery `ENCOUNTER_FLAGS` gain `hr_warden_defeated` and `ch2_velour_defeated` (flag route and boss route = one encounter); the `ch2_trials_open` header line reworded | yes |
| G9 docs, hints & packaging | L07, D10, F04, P07, P29, P37, P48, P49, P50, P51 | see §7 | this pass |
| G10 `.uid` files | D09 | one `--import` after everything else is green | runs last (not yet when this was written) |

## 6. Obsolete
* P26 (regional lanterns regain their true signal on `ch2_choir_defeated`): already delivered by the story module C9
  (`reach_dressing.gd` stage 2 floats festival lanterns over every road and turns the Commons pole into the Lanternwake lantern; the
  `ch2_choir` step message says "The outer ward shines again").

## 7. G9: docs, onboarding hints and release packaging
* **L07** - no `ch2_trials_open` gate: `INTEGRATION_WAVE_BC.md` §6 D08 (superseded note), spec §1 (the echo-trial line names
  `data/trials.gd`, `src/world/trial/*`, the three stones and the opening rule; the Matron's origin is `cp_arena`, not "arena_gate"),
  `docs/ch2/maps/world_areas.md` §8, `GAME_SPEC.md` "Replay & optional", `KNOWN_ISSUES.md`.
* **D10 / F04** - recorded as open items in `KNOWN_ISSUES.md` (Chapter Two, "Open work") and here.
* **P07** - `docs/ch2/maps/combat_enemies.md` §12 (C5 setup keys incl. `dormant` / `seed` and the Warden's `arena`, `arena_center`,
  `arena_radius`, `pillars`; the Warden leash, timing assist and charge edge clip; the pass-2 `enemy_base` helpers, `fire_projectile`
  `dir` / `on_hit`, the attack-token API, `move_ring`, `expose()`; Count Velour, the Crossing Matron incl. `rail`, the HP floor,
  `retreat_seconds()` and the z = 0 assumption; the Borrowed Choir) and a summary bullet in ARCHITECTURE.
* **P29** - spec §3 `trials` keys (`last_seconds`, `repeat_paid`, `paid`, `pending`, `pending_clears`) and the extra keys; spec §1;
  ARCHITECTURE "Echo Trials"; `WAVES.md` Wave D module table (D1-D4) + the pass-2 group table; `GAME_SPEC.md` and `KNOWN_ISSUES.md`
  no longer call the Velour / Choir trials or the expeditions "in progress".
* **P37** - saved state documented in `SAVE_MIGRATION.md` §2 (trials keys; `extra["expeditions"]`, `extra["music_box"]`),
  `state_save_data.md` §14 and ARCHITECTURE (Expeditions API, Music Box API + priority 40 + the house rule + the non-fullscreen panel
  that closes when she is hurt + the muted behaviour, onboarding hints `attach` + suppression reasons, the new input actions).
* **P48** - `tools/build_release.ps1` also copies `docs\player\Chapter Two - What's New.txt` next to `How to Play.txt` (parse-checked;
  no build was run).
* **P49** - player docs: What's New "GOOD TO KNOW" (the three echo stones, the Expedition Board's three routes by name, the Music
  Box with favourites), the wardrobe key O, the build keys are rebindable (the "can't be changed" line is gone); How to Play lists
  O, "Leave the trial" and points to the note; `GAME_SPEC.md` controls / expression / replay / music paragraphs; README status.
  `onboarding_hints.gd`: one generic `ob_echo_trial` tip ("where" keyword `echo_origin` = an area whose trial's `requires_flag` is
  set; armed on arrival there and live when Velour or the Choir falls - not when the Matron falls, so Chapter One's return home is
  never interrupted; dropped once ANY trial has a clear), `ob_expedition_board` names the Lanternwake Expeditions, `ob_wardrobe`
  names the `{wardrobe}` key (G6's suggestion). Tests: `test_onboarding_hints` (+3: every stone, live arming / waiting for a stone,
  dropped after any clear) and `test_onboarding_text` (the wardrobe key O and the build keys Z / P / N are real, rebindable
  Settings actions and the docs say so; the note names every trial's stone, the three routes, the Expedition Board and the Music
  Box, both Workbench recipes).
* **P50** - timings kept (2.5 s / 25 s / 30 s); listed in `KNOWN_ISSUES.md` and the pending checks.
* **P51** - this record; `INTEGRATION_WAVE_BC.md` §6 (a "resolved in pass 2" column), §3 k and §7 / §8 pointers;
  `WAVE_A_REPORT.md` content-bundle list (+ the pass-1 bundles and `rw_trial_velour_first` / `rw_trial_choir_first`);
  `KNOWN_ISSUES.md` Chapter Two section rewritten; `PROJECT_STATE.md`; `AGENTS.md` visual-QA commands (`--ui-open=expedition`,
  `--ui-open=music_box`, the trial arenas, `--save-dir` for runs that can save); `docs/ch2/maps/ui.md` §12 (new panels, hotkeys,
  tracker / map, echo stones, hints). Cross-group doc follow-ups from the other groups' notes were applied too (the ChapterLog
  `"display"` key in ARCHITECTURE / state_save_data, the tracker's `expedition` kind and the map's `exp_*` ids).

## 8. Still open after pass 2
`KNOWN_ISSUES.md` (Chapter Two section) is the list: the D10 voices pass, test hygiene (F04), the `.uid` import if G10 has not run
yet (D09), onboarding pacing (P50), the Bell Throat stone position (L10), and the visual / listening / real-input / performance
checks (the plan's 27 pending checks, merged into that file's lists).
