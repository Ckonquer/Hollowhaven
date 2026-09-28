# QA report — Hollowhaven v0.9.0 (Chapter One) and v2.0.0 - v2.0.3 (Chapter Two)

Sections 1-8: Chapter One (v0.9.0 / v0.9.1). **Section 9: the Chapter Two release 2.0.0** (executed-test matrix, save integrity,
bot runs, visual inspection, bugs, music, performance, the natural chain, and the NOT YET DONE list). Section 10: Chapter Two
development records. **Section 11: the bug-fix release 2.0.1** (what changed, full suite, Run A / Run B on the packaged 2.0.1 exe,
focus protection, the updated NOT YET DONE list); it supersedes §9 where they differ. **Section 12: release 2.0.2** (the
boss-fight tip fix, suite, the Mochi / Lumi investigation, verification runs on the packaged 2.0.2 exe). **Section 13: release
2.0.3, the gift build** (installer, first-time player - Krystal has never played, so the returning-player instructions and the
personal-save caveat of §9-§12 are obsolete; the QA primary-monitor incident; the current NOT YET DONE list).

Every entry says what KIND of check it was:
**[code]** source review · **[auto]** automated tests (headless engine) · **[visual]** launched and inspected
real rendered frames · **[interactive]** played through real OS-level keyboard/mouse input (Win32 SendInput)
sent to the game window · **[subjective]** human judgement — marked *not verified* where it wasn't done.
Chapter Two adds **[bot]** (headless engine driven through the game's QA input port: virtual input, not OS input, nothing rendered),
**[stills]** (rendered still frames looked at by an agent, not play) and **[perf]** (profiling harness); see §9.

Environment (all checks unless stated): the owner's PC, not a sandbox — Windows 11 Pro 10.0.26200 x64 ·
AMD Ryzen 9 9950X (16C/32T) · 125.6 GB RAM · NVIDIA GeForce RTX 4090 (driver 32.0.15.9571) + AMD Radeon iGPU ·
two 1920×1080 displays · Godot 4.7.2-stable official (Forward+, Vulkan, Jolt physics).

## 1. Toolchain gate (Milestone A) — 2026-09-27 15:31
| # | Check | Kind | Steps | Expected | Observed | Result | Evidence |
|---|---|---|---|---|---|---|---|
| A1 | Create/open project | auto | `godot --headless --path game --import` | imports | imported | PASS | console |
| A2 | Compile a minimal playable scene | auto | gate scene `tests/gate/gate.gd` | runs | ran | PASS | qa/evidence/gate/gate_log.txt |
| A3 | Standalone build | auto | `--export-release "Windows Desktop"` | exe produced | 109 MB exe, PCK embedded | PASS | — |
| A4 | Launch in a graphical environment | visual | ran the exported exe on the desktop | window opens on the GPU | `READY renderer=forward_plus adapter=NVIDIA GeForce RTX 4090` | PASS | gate_log.txt |
| A5 | Capture a real rendered frame | visual | GDI screen capture of the client area + in-engine capture | real frame | captured (first OS capture caught the boot splash) | PASS | qa/evidence/gate/*.png |
| A6 | Real input changes state | interactive | `winctl.ps1 -Action key -Key D -Ms 1500` (SendInput scancodes) | cube moves ≈ +6 m | `POS 0.67 → 6.07` while `keyD=true` | PASS | gate_log.txt, os_after_D.png |

## 2. Automated tests — [auto]
`tools/test.sh` runs every `game/tests/unit/test_*.gd` headless; the runner **fails a test on any runtime
SCRIPT ERROR** (added after core QA showed errors could otherwise pass silently; verified with a probe test).
Result recorded 2026-09-27 20:06 (just before commit 0dde10e): **653 tests, 0 failed, 300 s** (`qa/evidence/test_results_v0.9.0.json`). Commit 0dde10e added one more regression test (654); the latest full-suite result is recorded in section 8.

| Area | Tests | Covers (examples) |
|---|---|---|
| core | 172 | inventory stacking/overflow/moves/sort, give/take incl. key pouch, quest chain walked end-to-end with rewards granted once, save round trip of every field, atomic write, corrupt main → backup restore, .tmp recovery, garbage/future-version rejection, settings coercion/rebinding, clock/day math, data reachability (no circular recipe requirements) |
| horror | 71 | director eligibility per zone/state/intensity, per-event/global/major cooldowns, no stacked majors, recovery after encounter/death/authored moments, safe zone & pause cancel, threat budget, spawn-anchor validation, repetition avoidance, "often does nothing" statistics, seed determinism |
| companions | 66 | one-follower rule, pet/feed once per day, bond XP, Mochi refusing the mine, spawner decisions per area, stuck recovery, reward-once after reload |
| enemies + combat | 68 | health/damage/i-frames, melee arc & line of sight, light exposure, telegraph→attack→recover timings, spawner clear flag persistence, boss rules (damage only when stunned, brazier scorch, heartseed exactly once after reload), intensity scaling |
| building + crafting + farming | 68 | transactional crafting (incl. rapid repeats, output that fits only after ingredients are consumed), placement validation, refunds, chest rules, enclosure prevention, roofs, crop growth/tending/harvest |
| ui | 56 | icons for every item, hint tokens, toasts, settings bindings, confirm dialogs, New Game overwrite flow, quest banner layering, lore lookups |
| player | 54 | stamina/jump/dodge maths, one hit per swing, prompt building, safe-position recovery, camera clamps/comfort, **follower-focus regression**, **item-behind-desk-edge regression** |
| audio | 34 | every sound name the code uses resolves (with/without arachnophobia), loops marked looping, bus volumes, missing sounds never crash, mix-balance rules |
| world (surface) | 31 | height_at equals collision, spawn points on ground, deterministic node ids, resource deplete/respawn, world-item persistence, stream crossings walkable by a physics walker |
| below (dungeon) | 33 | every spawn on solid ground with headroom, critical path & side paths walked by Krystal's capsule, key never duplicated, gate/lift/checkpoint persistence, arachnophobia leaves no web meshes |
| parse_all | 1 | every script in the project compiles |

## 3. Interactive playthroughs with real input — [interactive] + [visual]
Driver: `tools/qa/playthrough.py`. It sends real keyboard/mouse events to the game window with Win32
SendInput and sees the game through a read-only telemetry stream (`--qa-telemetry`: position, on-screen
prompt, objectives, button rectangles, nearby objects) plus window screenshots. It never grants items,
teleports or sets flags. Honest caveat: the bot "sees" via telemetry rather than by reading pixels, and it
knows the route, so it is much faster than a first-time human.

### 3.1 FIRST CLEAN PLAYTHROUGH — packaged release, fresh save — **PASS**
* Build: v0.9.0 (`dist/Hollowhaven-0.9.0-Windows.zip`, commit 0dde10e), **extracted to a folder whose path
  contains spaces** (`qa\tmp\Release Test Folder\Hollowhaven\Hollowhaven.exe`), launched windowed 1600×900,
  dedicated test save folder (`--save-dir`), started through the real title menu (New Game → comfort screen →
  "Begin the journey").
* All 18 scenario steps passed in one uninterrupted run (12.6 min game time): read the Ward Stone → gather →
  craft axe (crafting UI) → fell trees → craft + place workbench (build mode) → pick berries & befriend Mochi →
  craft pickaxe, break the boulder, befriend Pebble, mine copper → craft bed + crop plot, place both, plant
  seeds → craft sword/lantern/snacks at the workbench, fight the ruin Bramblings, befriend Lumi → Ward Stone
  warning → mine the rubble, enter the mine (comfort reminder) → light lanterns, fight Gloomlings, mine the
  gallery rubble, take the Foreman's Key → unlock the gate, stair, Hall of Faces, Drowned Shrine, Silk Hollows
  → light 3 braziers, fight and defeat the Weaver Matron, take the Heartseed → lift up, climb out, walk home →
  return the Heartseed → restoration cutscene, "Chapter One Complete", credits → free play (the attempted pause-menu save failed, see below).
* Observed in the run (from the game's own events): the authored moments fired in order — THE THRESHOLD
  ("timbers creak…" + Lumi noticing), THE DISTANT CROSSING ("something skitters past the far doorway"),
  THE IMITATION ("a familiar chime… played backwards", "[Lumi whimpers]"), SILK HOLLOWS INTRO ("it slips away
  into the dark above" / "It shrinks from your light"), boss braziers, the Weaver's retreat, the lift, the
  Ward Stone restoration. 0 deaths, lowest health 36/100. 6 automatic saves (area changes, lantern checkpoints, chapter end). **Correction (found by an independent verification pass):** the scenario's last step, a manual Save from the pause menu, did *not* happen - the bot could not find the button and the step wrongly reported success (bot bug). The final save on disk is the automatic chapter-completion save.
* Evidence: `qa/evidence/e2e_release_v0.9.0/` (31 screenshots, bot log, per-step results, observed_events.txt).

### 3.2 Earlier runs (the bugs they found are in section 5)
| Run | Build | Outcome |
|---|---|---|
| dev1–dev5 (editor binary, same code) | pre-0.9.0 | surface half passed after bot fixes; revealed the companion-focus bug, gallery Gloomlings (bot didn't fight), the key/note focus bug, office overexposure, Lumi line spam |
| checkpointed dungeon runs (Continue from lantern saves) | pre-0.9.0 | old mine → ruins → silk → boss → return → ending all passed; boss needed better dodging by the bot |
| release1 | 0.9.0 (first build) | failed at the Foreman's Key → real bug (focus), fixed |
| release2 | rebuild | bot ran out of berries for snacks (bot planning) → bot now gathers more |
| release3 | rebuild | failed at the Foreman's Key again → root cause found in the interaction line-of-sight, fixed + regression test |
| release4 | 0.9.0 final | **PASS**, section 3.1 |

### 3.3 PERSISTENCE PLAYTHROUGH — **partially verified**
* Automated [auto]: full GameState save/load round trips, corrupt-save recovery, reward-once after reload,
  structure/crop/companion persistence (section 2).
* Interactive: during development the dungeon was repeatedly resumed through the real title **Continue** from
  lantern autosaves (dev3–dev5 checkpoints) and continued to the ending — Continue restored area, quest step,
  lantern checkpoint position, Lumi following, inventory and key items [interactive, dev binary].
* NOT RUN: the scripted persistence scenario on the release build (save → quit via menu → relaunch → verify
  → hard-kill underground → relaunch → finish; `tools/qa/persistence.py`) was started but stopped at the
  owner's request (they needed the PC). Re-run it with:
  `.tools/pyenv/Scripts/python.exe tools/qa/persistence.py --exe builds/Hollowhaven/Hollowhaven.exe`

## 4. Visual & audio checks
* [visual] Title, comfort screen, HUD, Haven by day/dusk/night, every landmark, the mine, ruins, silk hollows,
  boss arena, restoration, credits — inspected in screenshots during development (agents' `qa/tmp/*` shots and
  the playthrough screenshots). Issues found and fixed: overexposed foreman office; rug design; Ward Stone glow
  invisible; sign text overflow; floating arena webs; lift cage filled with rocks.
* [visual] Arachnophobia mode was inspected by the dungeon/enemy/UI modules (Hollow Shade, pale roots, thread
  spool icon, boss bar name). *Not re-inspected on the final build.*
* [subjective] **Audio: not verified by listening.** All 154 sounds/music are original and generated by
  `tools/audio`; checked by numbers (peak/RMS/weighted loudness, loop seams, clipping), spectrograms and an
  in-engine mix capture. A human listening pass is still needed.

## 5. Bugs found by playing, and their regression status
| Bug | Found by | Fix | Regression |
|---|---|---|---|
| A following companion stole the interaction prompt from grass/stones ("Talk to Pebble") | real-input run dev1 | befriended companions deprioritised in the interaction probe (also for camera-ray hits) | unit test `test_follower_does_not_steal_focus_from_gatherables` + passes in release4 |
| Foreman's Key could not be focused (note won; LOS aimed at the floor behind the desk) | release1, release3 | key/note spaced apart; key volume reaches the floor; LOS aims at the collider shape | unit test `test_item_behind_a_desk_edge_is_still_targetable` (fails without the fix) + release4 |
| Foreman's office washed out with the lantern + Lumi | dev3 screenshot | lamp energy 1.1 → 0.6 | visual in later runs |
| Lumi's "notices something" line every ~30 s near enemies | dev2 event log | spoken line cooldown 75 s (glance/dim unchanged) | code |
| Surface idle lines underground ("watches the leaves") | dev3 event log | `idle_below` lines | code |
| Bed respawn lost after returning from the mine | module review | `Game.change_area` keeps the bed spawn | code |
| Confirm dialogs & New Game overwrite threw script errors | UI review (tests) | fixed | unit tests |
| Damage vignette/flash invisible, quest banner off-screen | UI review (screenshot) | anchors/offsets fixed | unit test |
| Stalker tunnelling through rock; scorched boss landing on a brazier | combat review | fixed | 11 regression tests (each fails when reverted) |

## 6. Performance — [visual] measured, but not the formal target run
Windowed debug-binary runs (1280×720–1600×900, high quality, often with other processes rendering at the same
time) logged via `--perf-log`: surface steady 330–436 FPS (~2,100 draw calls by day), dungeon 270–600 FPS
(290–1,580 draw calls); dips to 107–116 FPS only in the first seconds after an area load (shader compilation).
Static memory 125–190 MB, video memory 370–410 MB, no growth observed across the runs. **Not done:** a
dedicated fullscreen 1080p profile of a fixed route on the release build (the owner needed the PC). These
numbers come from one very powerful GPU and say nothing about minimum requirements.

## 7. Not verified (honest list, Chapter One)
Human listening; human subjective fun/pacing; weaker GPUs; the scripted release persistence run (3.3);
arachnophobia visuals on the final build; 1080p fullscreen perf profile; gamepad (not supported).
(Chapter Two: §9.10.)

## 8. Later changes (after the release playthrough)
The credits text changed to "For Krystal / from Ali" (commit 9512a0d) and a headless code audit produced further fixes. These later builds were verified by the automated test suite (headless) only, not by a new real-input playthrough (the owner needed the PC). Details and the final suite result: `docs/Hollowhaven_Technical_Handoff.md` section 9 and the git log.

## 9. Chapter Two — v2.0.0 release QA (2026-09-28)
_As written for 2.0.0. Later runs and the 2.0.1 fixes (CHAIN-001 / 002 and more) are in §11, which supersedes the open-bug table
in §9.6 and the list in §9.10 where they differ._

**Build under test.** `dist/Hollowhaven-2.0.0-Windows.zip` (111.1 MB, SHA-256 `9F3FD0D2E3216B861E470158B881A10ED2CEBBC30FC3C07D3BC61D93652856CC`,
`dist/SHA256SUMS.txt`), exe `builds/Hollowhaven/Hollowhaven.exe` (184.7 MB, 10:20), git `36e2e8a` = `9e8765f` + version bump
(`project.godot` / `export_presets.cfg`) + 401 one-line `.uid` files. Export log `qa/tmp/build_v200.log` (EXIT=0). Same PC as above.

**Evidence kinds used for Chapter Two** (in addition to the legend at the top):
**[bot]** the QA bot (`tools/qa/ch2/`) drives a **headless** engine through the game's QA input port: injected keyboard / mouse
events and read-only telemetry, nothing rendered, dummy audio, no OS input layer (no Windows focus / raw input / cursor capture) -
not **[interactive]** in the section-1 sense. It knows the route; its times are not human times.
**[stills]** frames rendered on the second monitor (1920×1080 at 1920,0; muted, no focus, bounded runs, scratch saves) and looked at
by the agent that reviewed or fixed them - still images, not play. **[perf]** the profiling harness `tools/qa/perf_profile.py`.
**No human has played or listened to Chapter Two. No [interactive] (OS-level real-input) run of Chapter Two exists.**

**Which code each kind of evidence ran on** (important: most runtime evidence predates the final commit):

| Evidence | Code under test |
|---|---|
| Final full suite (§9.2) | the tree committed as `9e8765f` (run ~10:05-10:19); `36e2e8a` only adds the version bump and `.uid` files - the suite was not re-run after it |
| Bot segments S0-S4, re-runs after bug-fix round 1 (§9.4) | S0 `vfix_fast` / `vfix_thorough`: the live tree at 08:2x; all others: snapshot `scratchpad/snap` = `5cd7774` + the bug-fix round 1 files (08:31) |
| Natural end-to-end chain (§9.9) | the same snapshot; it differs from 2.0.0 in 166 files (the visual fixes, integration pass 3, the Weaver's finishing-blow rule); `quarry_warden.gd` is identical |
| Still frames (§9.5) | debug runs of the source tree while the fixes were made |
| Performance runs (§9.8) | `headless_check1`: source, headless; `packaged_smoke*`, `packaged_v200` (finished 10:57): the packaged 2.0.0 exe |
| `save_integrity.py` re-check (§9.3) | v2 files written by the final suite run (10:16) |

### 9.1 Executed-test matrix (MP §20.3 areas × kind of evidence)
"[auto]" counts are the final full run's tests grouped by suite-name prefix (approximate grouping; 2639 in total). A dash means
**not done**.

| MP 20.3 area | Source review | [auto] unit / integration | [stills] graphical | [bot] virtual input, headless | [interactive] OS real input | [perf] | Listening |
|---|---|---|---|---|---|---|---|
| Customization | module builds + independent reviews (B1 avatar, B2 appearance UI), pass-3 G6 palettes (`docs/ch2/INTEGRATION_PASS3.md`) | ≈92 (`avatar_look_*`, `ui_appearance_*`, `data_ch2_appearance`, `flow_ch2_newgame`): cancel writes nothing, legacy look default, ownership, presets, armor / outfit separation, fit numbers | avatar review 20 findings; before / after sheets `qa/tmp/visual/avatar/`, `fix_avatar/sheets/`, `pass3_g6/`, `g1_pass3/` | S0 (natural): "Meet Krystal" look chosen and kept; S1 (natural): wardrobe restyle, preset "Autumn Picnic" saved, notice retired | - | n/a | n/a |
| Inventory / crafting / building | B5 stations, B6 building reviews; pass 1-3 records | ≈263 (`building_*` incl. storeys, stairs walk, undo / tint, visual fit; `crafting_*`, `station_*`, `core_inventory`, `core_economy`, `farming_*`): reachable recipes, no circular gates, multi-chest transactions, queue completes once, capacity grows without truncation, recolour keeps uid / data | building review 15 findings; the real Haven cottage built through BuildMode (59 of 61 pieces) `qa/tmp/visual/fix_building/` | chain T23 / T34 (natural): harvest, berries, cooking; S1 extras: hand-crafted Crop Plot, gathering for the waygate; S2: wood, iron, Reach trees felled | - | n/a | n/a |
| Equipment | B3 equipment / stats review | ≈83 (`equipment_*`, `stats_*`, `wand_*`): slot swaps, no duplication, stat recompute, caps, shield / health | armor fit (AV-02/03/04) | **not exercised**: no run equipped armor (the real save has no Loom; the chain keeps the copper sword) | - | n/a | n/a |
| Companions | B4 companion combat review | ≈153 (`companions_*`: combat, skills, courage, nav, home, areas) | companion visuals in the review sheets; menu layout (`fix_ui`) | S0 (natural): Comfort Ribbon tied, Mochi follows below; Lumi follows through the chain. **Measured pet damage / heal / shield in play (MP Run C): not done** | - | n/a | n/a |
| Combat | C5, C6a-c, B8, B9 reviews; pass-3 G5 | ≈513 (`combat_core`, `enemies_*`, `boss_*`, `c1x_arena`): one hit per swing, i-frames, telegraphs, budgets, boss phases / resets / rewards, pacing caps | creatures review 15 findings (tells, faces, arachnophobia looks) `fix_creatures/`, `pass3_g4/` | every boss won by the bot: 0 deaths in the segment re-runs (§9.4); in the natural chain 1 death (run3, the Choir's phase-3 hush) followed by a successful retry (§9.9); new open Warden bugs CHAIN-001 / 002 (§9.6) | - | n/a | n/a |
| Quests / world | C1-C4, C7-C9, B7, B10 reviews | ≈775 (chapter log, optional log, `story_ch2_*`, `flow_ch2_*`, `reach_*`, `manor_*`, `works_*`, `world_*`, `annex_*`, `c1x_*`, progression audits, mastery, `expeditions_*`, `trials_*`, `below_*`): lamps in any order, legacy indices, no replay of Chapter One, return paths | Reach 20 and interiors 17 findings, camera arrivals `fix_cameras/`, `fix_reach/`, `fix_interiors/` | chain (natural): Chapter-One-complete save -> 20/20 Chapter Two steps -> free play -> relaunch; S0 (natural): fresh game through Chapter One and the Ward Stone. Only ONE lamp order (orchard, quarry, manor) was played. **Echo Trials and Expeditions: never run by the bot** | - | n/a | n/a |
| Audio | A4 music director review; manifests with independent numeric reviews | ≈112 (`audio_*`, `music_box_*`): every cue exists / imports, anti-repeat, no per-frame restarts, boundary hysteresis, boss / ending priority, combat exit, silence, limiter, missing-file fallback, RNG independence | n/a | director cue changes in 89 telemetry files: 24 of 27 cues selected in play; m09, m12, m19 never (`docs/ch2/MUSIC_MANIFEST.md`); headless = dummy audio, nothing heard | - | - | **NOT DONE** (offline loudness / peak / seam analysis only) |
| Comfort (arachnophobia, flashing, cues) | reviews per module | ≈42 in dedicated suites (`audit_arachno_*`, `below_arachno`, `onboarding_*`) + arachnophobia / high-visibility / timing-assist cases inside enemy, boss and building suites | arachnophobia looks rendered (Hollow Mother, pale roots, posts: `pass3_g4/`, `fix_interiors/deep_v2_arach`) | all bot runs used default comfort settings (arachnophobia off, Standard) | - | n/a | - |
| Save / persistence | A1 core-save review | ≈107 (`save_v2_*` matrix / migration / state / title, `core_save`, `audit_persistence_*`) | - | S1 migration of a real v0.9.0 save, save diffs, relaunch + Continue (§9.3) | - | n/a | n/a |
| UI / HUD (extra) | B2, B11 reviews | ≈169 (`ui_*`, `audit_ui_*`, incl. `test_ui_visual_qa` 18) | UI review 23 findings; `fix_ui/` sheets at 1080p and 720p | panels driven by the bot (wardrobe, Lantern Road lists, pause menu, Save & Quit) | - | n/a | n/a |
| Performance | - | `enemies_perf` (2), build-time budgets in world tests | - | - | - | packaged exe, 9 states × 3 presets + round trips on an RTX 4090 (§9.8); no weaker GPU | n/a |

### 9.2 Automated test runs — [auto]
`tools/test.sh` (headless; the runner fails a test on any runtime SCRIPT ERROR).

| When | Tree | Result | Log |
|---|---|---|---|
| 04:21-04:35 | after integration pass 1 | 2407 tests, 0 failed, 820 s | `qa/tmp/full_integration_bc_final.log` |
| 07:2x | after integration pass 2 (commit `5cd7774`) | 2477 tests, 0 failed, 830.8 s | `qa/tmp/full_integration_pass2_final.log` |
| 08:48 | snapshot `5cd7774` + bug-fix round 1 | 2534 tests, 0 failed, 842 s | `qa/tmp/full_bugfix1.log` |
| **~10:05-10:19** | **final tree (`9e8765f`)** | **2639 tests, 0 failed, 847.0 s**; `parse_all` passes; 21 `ISOLATION` repairs; ends with "7 ObjectDB instances were leaked at exit" (§9.6 CHAIN-003) | **`qa/tmp/full_final1.log`** |
| 2026-09-28 (docs pass) | 2.0.0 + the player-doc corrections | `test_onboarding_text` 8 tests, 0 failed (it checks the player docs against the real bindings) | console |

The known red test of pass 3 (`test_enemies_review.test_boss_killing_blow_skips_the_window_cap_climb`) passes in the final run: the
Weaver's rule now lets a blow that would finish her in her last phase through (`weaver_boss.gd` `_on_damaged`).

### 9.3 Save integrity — [auto] + [bot]
Full report: `docs/ch2/SAVE_INTEGRITY_REPORT.md`. Summary:
* **Fixture matrix (MP §20.2):** all 12 scenarios + extras + the two real v0.9.0 files: `test_save_v2_matrix` 22/22 PASS in the final
  run. Re-checked for this report with `tools/qa/save_integrity.py` (self-test 12/12) on the 14 v1 fixtures vs the v2 files the
  final run wrote: all exit 0, 0 preserved-field mismatches, 0 missing sections (reports `qa/tmp/save_integrity_2.0.0/`).
* **Real QA-bot save migrations:** the upgrade backup of the real Chapter-One-complete save is byte-identical to the original in
  `s1/vfix1`, `s1/diag_bak` (main + backup) and all five natural chain runs (`chain/dev3`, `run1`-`run4`). S1 after-migration diff: 5 strict differences, all from 2.6 s of game
  clock (time, play seconds, float settle, one stone's respawn timer expiring); home structures, crop, inventory, key pouch,
  companions, flags and quest index identical. S1 final diff: 29 differences, all explained by play, 0 unexplained.
* **Relaunch / Continue:** S1, S4 and the chain END check resume the same save with the same items and no double rewards.
* **PERSONAL-SAVE VERIFICATION BLOCKED** (Krystal's save is not on this PC). Not done either: a process kill during a real write,
  before / after screenshots of a home, chests in a real (non-synthetic) save.

### 9.4 QA-bot route segments — [bot]
Scripts `tools/qa/ch2/s0_fresh_c1.py`, `s1_continuation.py`, `s2_orchard_quarry.py`, `s3_manor.py`, `s4_route.py` (fixtures `s2/s3/s4_fixture.py`); merged bug list `qa/tmp/bot/BUGS_MERGED.md`. Every final run: 0 deaths, 0 SCRIPT
ERRORs, no problems filed.

| Segment | Content | Start (natural or fixture) | Best run(s) | Duration (bot time) |
|---|---|---|---|---|
| S0 | fresh New Game -> Meet Krystal -> enriched Chapter One (Tailor's Cache, Brave Little Steps) -> 3-phase Matron -> restoration -> Ward Stone accepted | **natural** (empty save folder) | `s0/run11` (live tree 04:17, before bug-fix round 1) | 706.5 s; Matron 49 s, no damage |
| S0 re-runs | the Weaver Matron after CH2-003 | **diagnostic fixture** (debug `--area` / `--give` at the arena lantern) | `s0/vfix_fast`, `vfix_thorough` (live tree), `vfix_snap_fast`, `vfix_snap_thorough` (snapshot) | 55.7-73.9 s; phases 1-2-3 every time |
| S1 | Continue (v1 -> v2) -> wardrobe -> Ward Stone -> waygate -> Reach -> Commons -> Lantern Road home and back -> Save & Quit -> relaunch -> Continue | **natural** (copy of the real v0.9.0 Chapter-One-complete save, fixture 16) | `s1/vfix1`, `s1/vfix_verbose` | 73.9 s / 76.5 s wall |
| S2 | orchard (irrigation, seed, mimics, garden lamp) + quarry (winch, Quarry Warden, lamp) -> Save & Quit -> Continue | **diagnostic fixture** (`s2_fixture.py`: save 16 + S1 flags) | `s2/vfix1` | 232.7 s; Warden 40.2 s |
| S3 | Moonveil Manor, Looking-Glass Hall, ballroom, Count Velour | **diagnostic fixture** (`s3_fixture.py`) / the ballroom save | `s3/vfix_run`, `s3/vfix_boss` | 196.5 s / 140.7 s; Velour 78.0-78.7 s |
| S4 | link the lanterns -> Hushed Works (3 lines) -> Weaver's Crossing -> Borrowed Choir -> home -> Lanternwake -> free play -> relaunch | **diagnostic fixture** (`s4_fixture.py`: three lamps lit) | `s4/vfix_full` | 747.8 s; Crossing 70.0 s, Choir 301.3 s; relaunch 20/20 steps, same items |

Fight durations before / after bug-fix round 1 (bot time): Weaver Matron fast 19.8-22.8 s -> 44.6-47 s, thorough 65.9 -> 64.3-71.3 s;
Quarry Warden 24.9 s -> 40.2 s; Count Velour 70.2 / 106.3 s -> 78.0 / 78.7 s; Crossing Matron 21.7-22.5 s -> ~65 s; Borrowed Choir
229.8 s -> 301.3 s. The design targets (2-4 min per Chapter Two boss) are about a first human attempt, which is untested.

### 9.5 Visual inspection — [stills]
Six still-frame reviews (avatar, building, creatures, interiors, Reach, UI) produced **110 unique findings** (0 blockers, 21 major,
47 minor, 42 polish; `qa/tmp/visual/VISUAL_BUGS_MERGED.md`). Fixers changed the code, added numeric regression tests and re-rendered
their fixes as stills. Status at 2.0.0:

| Area | Findings | Fixed and re-rendered | Partly fixed | Addressed in code + tests, closure not recorded | Evidence |
|---|---|---|---|---|---|
| Avatar | 20 | 16 | 4: AV-04 (cardigan cloud hem / ruffle collar still show under armor), AV-11 (skirt slits, knees), AV-12 (hair vs lantern pack), AV-19 (roll hover) | - | `fix_avatar/sheets/`, `pass3_g6/`, `g1_pass3/`; `test_avatar_look_fit` |
| Building | 15 | 15 | - | - | `fix_building/`; `test_building_visual_fit` |
| Creatures | 15 (CR-12 merged into IN-07) | 15 (CR-03 / 05 / 14 in pass 3 G4) | - | - | `fix_creatures/`, `pass3_g4/`; `test_creatures_visual_fixes` |
| Interiors | 17 | 15 | 1: IN-13 (balcony backdrop fixed; the HUD day dial inside the manor is not, R3-43) | 1: IN-09 (HUD hush, `test_ui_visual_qa`) | `fix_cameras/`, `fix_interiors/`, `pass3_g3/`; `test_camera_spawn_clearance`, `test_works_interior_visuals` |
| Reach | 20 | 20 (RE-00 in pass 3 G2) | - | - | `fix_reach/`, `fix_cameras/`; `test_reach_visual_fixes` |
| UI | 23 | - | - | 23: the UI fixes landed in `9e8765f` (21 UI files); `test_ui_visual_qa` (18 tests) covers 20 of them, UI-13 has its own code fix, UI-19 was the same issue as CH2-012 (fixed), UI-11 changed the echo-stone material; stills in `fix_ui/` (1080p and 720p sheets) but **no per-finding closure record** was written | `fix_ui/` |
| **Total** | **110** | **81** | **5** | **24** | |

Nothing here was judged in motion, in a play session or by a human (list in `KNOWN_ISSUES.md` §7).

### 9.6 Bugs found and fixed
* **Bot route segments (S0-S4): 17 bugs** (0 blockers, 2 major, 5 minor, 10 polish; `qa/tmp/bot/BUGS_MERGED.md`). Bug-fix round 1
  fixed 16 and partly fixed CH2-011 (an engine-internal leak warning in developer logs, accepted). Every fixer's new tests fail on the
  old code; the bot re-ran each segment afterwards (details and per-bug table: §10.2).
* **Visual reviews: 110 findings** (§9.5).
* **Natural chain (after the release code freeze), open in 2.0.0** (`qa/tmp/bot/chain/bugs.json`):

| Id | Sev | What | Status |
|---|---|---|---|
| CHAIN-001 | minor | Quarry Warden stands frozen in "chase" at the arena edge when Krystal is on the terrace 1.4 m below the bench (no attack, no reset); walking back up the ramp restarts the fight (`chain/run1`, `diag_warden_climb`) | open (not a softlock) |
| CHAIN-002 | minor | Quarry Warden can be beaten with 0 pillar exposures by staying close and punishing slams (`chain/dev3` 68.5 s, `diag_warden_climb` 41 s) | open, design call |
| CHAIN-003 | polish | "ObjectDB instances were leaked at exit" on both quit paths = CH2-011 | accepted (developer logs only) |

### 9.7 Music — analysis only, NOT LISTENED
`docs/ch2/MUSIC_MANIFEST.md`: 27 cues (5 retained + 22 new compositions) + 4 layers, each with generator, duration, loop, tempo /
meter, playlist, peak / loudness from the manifests (new pieces -19.4 to -16.8 LUFS integrated) and in-game selection evidence (unit
tests + bot telemetry). No human listening, no in-game recording of the new music, layer sync reasoned but not measured in the engine.

### 9.8 Performance — [perf] (`qa/tmp/perf/packaged_v200/summary.md`)
The packaged-build profile finished at 10:57 (run 10:29-10:57), after the rest of this report was written. Setup (from its summary):
the **packaged 2.0.0 exe** (release build, not debug), Vulkan Forward+, 1920×1080 borderless window on the second monitor (60 Hz),
**V-Sync off and no frame cap** (to show headroom; the shipped default is V-Sync on), muted, virtual input, no editor running.
Hardware: Ryzen 9 9950X, 125.6 GB RAM, **RTX 4090** (driver 595.71). Each state: 2.5 s settle, 20 s 360° pan, 12 s walking, 4 s
idle. States start from the real save 16 (Haven) or from S2 / S4 **diagnostic fixtures** (not a natural route). Shader caches were
already warm from earlier runs.

| Preset | Avg FPS range over the 9 states | 1 % low range | Worst frame in the samples | Frames > 33 ms in the samples | In-game loads | Private / video memory |
|---|---|---|---|---|---|---|
| High @1920×1080 | 398 (Haven) - 709 (ballroom) | 217 - 334 | 16.9 ms | 0 | 0.95 s (annex) - 2.7 s (Reach arrival) | 1.43-1.87 GB / 452-507 MB |
| Low @1920×1080 | 468 - 682 | 241 - 330 | 17.2 ms | 0 | 0.85 - 2.9 s | 1.44-1.69 GB / 453-476 MB |
| High @1280×720 | 397 - 690 | 215 - 330 | 17.8 ms | 0 | 0.86 - 2.6 s | 1.44-1.66 GB / 304-338 MB |

* Loading hitches: the worst frames are inside loads (a single 0.85-2.4 s frame while an area is built) and the first seconds after
  (post-load worst 30-44 ms); no sample frame over 50 ms outside loads ("Stalls / outliers: none").
* Lantern Road round trips (Reach <-> Haven ×3, each preset): node, object, orphan, audio-player and video-memory counts flat;
  harness verdict **stable**. Process private memory still rises about 9-15 MB per cycle (e.g. 1.61 -> 1.73 GB over three cycles at
  High 1080p); the harness counts that as stable, but a long session was not measured.
* Enemy AI: no enemy processing farther than 60 m in any sample.
* QA-harness note (not a player issue): the packaged window took the OS foreground ~0.6 s after launch despite the no-focus override;
  the harness held `LockSetForegroundWindow` and handed focus back (the game was foreground in 3043 of 3136 checks).
* Earlier in the same folder: `headless_check1` (harness validation, headless, nothing rendered - its FPS figures are meaningless) and
  `packaged_smoke*` (single-state smoke samples of the same exe, consistent with the table).

**Not measured:** any weaker or integrated GPU, the shipped V-Sync-on default, a timed natural route with fights, a long session.
These numbers come from one very powerful PC and say nothing about minimum requirements.

### 9.9 The natural end-to-end chain — [bot]
`tools/qa/ch2/chain.py` runs S1 -> S2 -> T23 -> S3 -> T34 -> S4 -> END as ONE journey from a copy of the real Chapter-One-complete
save: no fixtures, no debug cheats, no teleports or grants; T23 / T34 earn by play what the segment fixtures handed out (home rest,
harvest, cooking). Headless, virtual input, on the pre-release snapshot (see the table at the top of §9) - **not the 2.0.0 exe, not
OS input, not a human**.

| Run | Result | Total | S1 / S2 / T23 / S3 / T34 / S4 / END (s) | Notes |
|---|---|---|---|---|
| `chain/dev3` | **completes**, Chapter Two 20/20, relaunch same items | 1564.1 s | 73.2 / 255.8 / 81.2 / 228.1 / 46.1 / 864.7 / 11.1 | 0 deaths, 0 SCRIPT ERRORs, lowest HP 8 (S4); Warden 0 exposures (CHAIN-002); 62 music cue changes |
| `chain/run2` (seed 11) | **completes**, 20/20, relaunch same items | 1306.4 s | 72.4 / 242.7 / 87.4 / 195.3 / 45.2 / 648.7 / 11.3 | 0 deaths, 0 SCRIPT ERRORs, lowest HP 28 (S4); Warden 2 exposures |
| `chain/run1` | **stopped in S2**: Warden not defeated in time | - | 71.7 / 608.9 (stopped) | found CHAIN-001 |
| `chain/run3` | **completes**, 20/20, relaunch same items | 1433.9 s | 69.5 / 218.6 / 87.5 / 204.2 / 46.0 / 792.2 / 12.6 | **1 death** in S4: the Borrowed Choir's phase-3 hush (the bot's lantern on a false anchor at 7 HP); respawn at the vault checkpoint, "The Choir picks up its song where you left it", fight won after the retry; 0 SCRIPT ERRORs; Warden 1 exposure |
| `chain/run4` (seed 5) | **completes**, 20/20, relaunch same items | 1323.0 s | 69.7 / 236.9 / 87.9 / 203.0 / 49.8 / 660.0 / 12.2 | 0 deaths, 0 SCRIPT ERRORs, lowest HP 25 (S4); Warden 1 exposure |
| `chain/exe_smoke` | harness error (QA input port not reachable) | - | - | 09:34, against the exe that existed before 2.0.0 was built; not a 2.0.0 result |

Summary: **4 of 5 natural chain runs completed Chapter Two** (dev3, run2, run3, run4; 1306-1564 s each), one stopped at the Quarry
Warden (run1, CHAIN-001). Every completed run ended with Save & Quit from the pause menu, a relaunch and Continue into the same save
(same items, 20/20 steps, chapter complete). Every run logged 2 "ObjectDB instances were leaked" warnings (CHAIN-003) and 0 SCRIPT
ERRORs. Boss times across the four: Quarry Warden 35.9-68.5 s (0-2 exposures), Count Velour 78-108 s (route step), Crossing Matron
65-92 s, Borrowed Choir 188-317 s.

Human-time equivalent: unknown. A route-aware bot finished Chapter Two in about 22-26 minutes of real time; a first-time player
will take far longer, and nobody has measured it.

### 9.10 NOT YET DONE (honest list)
* **Human listening** of any music or sound (Chapter One or Two), the Music Box, transitions, boss layers.
* **An OS-level real-input run** (SendInput, `tools/winctl.ps1` / `playthrough.py` default transport) of Chapter Two, on the
  packaged build.
* **A human first-time playthrough** of Chapter Two (or of the enriched Chapter One): playtime, difficulty, fun, readability of hints
  and tells.
* **PERSONAL-SAVE VERIFICATION BLOCKED**: Krystal's own save has not been copied, migrated or diffed (procedure:
  `docs/ch2/SAVE_INTEGRITY_REPORT.md` §7).
* **Performance on anything but the development PC** (RTX 4090): no weaker / integrated GPU, no V-Sync-on default, no timed
  natural route with fights, no long session (the packaged per-state profile is done, §9.8).
* **The natural end-to-end chain on the 2.0.0 exe** (so far only on the pre-release source snapshot, headless: §9.9); a visible
  second-monitor chain run.
* MP §20.4 runs: A with her save (blocked), B fresh integrated game on the packaged build with real input, C measured companion /
  gear effects in controlled encounters, D comfort + music with arachnophobia on and listening, E persistence with a real process
  kill during a write. Only headless bot equivalents of parts of A and B exist.
* Echo Trials and Lanternwake Expeditions in play (unit-tested only); lamp orders other than orchard -> quarry -> manor in play;
  equipment in play.
* In-motion visual checks and screenshots / recordings from the packaged 2.0.0 build.

## 10. Chapter Two — development records (superseded by §9 where they differ)

### 10.1 Integration pass 1 (after Waves B/C) — [auto] only
Twelve parallel fixer groups; the runs were snapshots of files that were changing while they ran. Before the pass: 2164 tests, 11
failed (8 order-dependent, fixed by the runner's isolation R09, plus R08 / R42). During it: 2279 / 20 failed and 2334 / 4 failed (files
mid-edit). After it: `parse_all` OK, full suite 2407 tests, 3 failed (Wave D expedition files rewritten mid-run; an outdated R17
expectation, fixed) and then **2407 tests, 0 failed, 820 s** (04:21-04:35), with the 33 timing suites run three times (393 tests, 0
failed ×3). Logs: `qa/tmp/full_integration_bc.log`, `qa/tmp/full_integration_bc_final.log`, `qa/tmp/timing_suites_3x.log`. Test
changes of that pass: the Echo Trial label follows R17 ("Leave the trial"), a deterministic blink test, two progression audits restore
`Game.zone_id` / `Game.in_safe_zone`.

### 10.2 Bug-fix round 1 (CH2-001..017) — fixes, regression tests, [bot] confirmation
Every fixer confirmed its new tests fail on the old code (old files swapped back in, then restored byte-identical). The [bot] column
is the verifier's re-run on the snapshot (S0 also on the live tree). Details: the fixer reports summarised in `docs/ch2/INTEGRATION_PASS3.md`.

| Bug | Sev | Fix (files) | Regression tests | [bot] confirmation | Status |
|---|---|---|---|---|---|
| CH2-001 | major | the lamp search joins step group "lamps"; `hint_when`; `ChapterLog.from_dict()` narrowing (`quests_ch2.gd`, `chapter_log.gd`) | `test_save_v2_chapter_log` ×3 (+1 updated), `test_ui_journal_tracker` ×1 (+2 updated) | S2: Garden and Quarry Seals + "Goal complete" the moment each lamp is lit; S3: Manor Seal right after its lamp | fixed |
| CH2-002 | major | `resource_node.gd` `_visual_id()`, `_settle_depleted()` safety net; `reach_vegetation.node_params()` | `test_world_nodes` ×3, `test_world_reach_area` ×1 | S2: two Reach trees felled, 0 SCRIPT ERRORs (was 10) | fixed (respawn after 1440 in-game min: unit test only) |
| CH2-003 | minor | Weaver: 15 % late window cap, threshold stop, banked scorch; a finishing blow in her last phase lands (`weaver_boss.gd`) | `test_enemies_boss_pacing` (10), `test_enemies_review` | S0 ×4: fan, drop, release and channel all play before the win | fixed; the later overshoot / finishing-blow changes were not re-run by the bot |
| CH2-004 | minor | Warden: `EXPOSE_CAP` 35 %, owed pulses, `PULSE_FLOOR_RATIO` (`quarry_warden.gd`) | `test_enemies_ch2_warden` ×5 | S2: the three pulses before defeat; the one exposure took 80.4 HP (cap 105) | fixed; but see CHAIN-001 / 002 |
| CH2-005 | minor | Velour channels beside the candle and eases round the stand (`count_velour.gd`) | `test_boss_velour_qa_fixes` ×2 | S3 ×2: both phase-3 channels broken by a straight-on blow 0.8-1.7 s in | fixed |
| CH2-006 | minor | lost-sight give-up for ordinary enemies (`enemy_base.gd`) | `test_enemies_lost_sight` (4) | - (the bot killed the hall's Velvet Wing) | fixed, unit-tested only (real-play check open) |
| CH2-007 | minor | Crossing: engagement rule, floors 60/35/20 %, clamped scorch, 3 s retreat run (`crossing_matron.gd`, `crossing_rules.gd`) | `test_boss_crossing_pacing` ×2, `_fight` ×3, `_rules` ×1 + 4 updated | S4: one exposure per phase; pounce, delayed pounce and release all faced | fixed |
| CH2-008 | polish | no combat state under a boss context; the boss's engagement grace cleared (`music_selector.gd`, `music_director.gd`) | `test_audio_music_selector` ×2, `test_audio_music_director` ×1 | S0, S3, S4: boss cue -> silence / area music, never m10 / m22 | fixed |
| CH2-009 | polish | opening the wardrobe retires the notice (`wardrobe_panel.gd`) | `test_ui_appearance_wardrobe` ×1 | S1: `notice_shown` true | fixed |
| CH2-010 | polish | helper zones; legacy landmarks marked seen (`game.gd`, `annexes.gd`, `mastery.gd`, `data/mastery.gd`) | `test_mastery_landmark_discovery` (5) | S1: `discovered.surface` = haven, ruin; Wayfinding 105 XP | fixed |
| CH2-011 | polish | `Game.release_prefetches()` on quit / window close (`game.gd`) | `test_flow_quit_prefetch` (3) | S1: still "8 ObjectDB instances were leaked"; 3 in the `--verbose` probe (bare RefCounted, refcount 0) | **partly fixed**: our leak source is gone (15 -> 7-9); the rest is engine-internal, developer logs only - accepted (R3-16) |
| CH2-012 | polish | the search step renamed "Find the Three Lamps" (`quests_ch2.gd`) | `test_save_v2_chapter_log` ×1 | S2: only the group title is announced | fixed (same issue as visual UI-19) |
| CH2-013 | polish | Velour's cap applied before the blow (`velour_health.window_room`) | `test_boss_velour_qa_fixes` ×4 | S3: no window over the 60.8 HP cap | fixed |
| CH2-014 | polish | Choir anchors switched off for phase B (`borrowed_choir.gd`) | `test_boss_choir_anchors` (3) | S4: 0 anchor prompts in phase B (was 38 and 152 samples) | fixed |
| CH2-015 | polish | crossing hint wording (`quests_ch2.gd`) | `test_save_v2_chapter_log` ×1 | S4 | fixed |
| CH2-016 | polish | post-Choir hint names the vault's bell-lift (`quests_ch2.gd`) | `test_save_v2_chapter_log` ×1 | S4 | fixed |
| CH2-017 | polish | vault exit caption follows the clock (`choir_arena.gd`) | `test_works_deep_vault_exit` ×1 | S4: "[the bell-lift climbs toward the daylight]" at 11:40 | fixed |

Runs of that round (`qa/tmp/full_bugfix1_run1.log`, `full_bugfix1.log`, `full_bugfix1_worktree.log`): the snapshot went 2534 / 2 failed
(a packaging test reading a local `override.cfg`; a prefetch test's assumption) -> **2534 / 0** after the test fix; the live tree
mid-edit had 33 failures (a file not compiling at that moment), none in a bug-fix file. `game/override.cfg` is gone from the tree now
and the packaging test reads the shipped `project.godot` (R3-22).

### 10.3 Integration pass 3 (51 requests) — groups
Decision record: `docs/ch2/INTEGRATION_PASS3.md`. Each group re-checked the code, added regression tests that fail on the old code,
ran its related suites and rendered its visible changes as stills.

| Group | Requests | Outcome | [auto] | [stills] |
|---|---|---|---|---|
| G2 surface arrival spawns | R3-32, R3-33 | Woods waygate spawn 5.8 m out; Tobin's `annex_door` spawn moved to (6.8, 7.8) | 22 + 81 + 69 tests, 0 failed | both arrivals rendered |
| G3 Works deep interiors | R3-19, 35, 41, 42 | resonator prompts, crossing-gate sign (cause: a winch-hall rock), lift signs, trial board crescent | 237 tests, 0 failed | `qa/tmp/visual/pass3_g3/` |
| G4 boss creature props | R3-36..38 (R3-39 skipped: would override the comfort setting) | trip posts, Crossing scar and mantle, Choir paper lanterns | 144 tests, 0 failed | `qa/tmp/visual/pass3_g4/` (both arachnophobia looks) |
| G5 combat feedback, text, tests | R3-06, 08, 09, 22 | Crossing text "three times", one glance spark for a blocked swing, robust `win_velour`, packaging test reads `project.godot` | combat_core, catalogue, trials, velour, boss suites 0 failed | a preview scene |
| G6 appearance palettes | R3-26..28, 30 (R3-29 skipped) | Ghostlight Party, Pumpkin Patch, mushroom beret, chorister capelet | avatar / appearance suites 0 failed | `qa/tmp/visual/pass3_g6/` |
| G1 docs, layer name | R3-04, 05, 10, 12, 16, 17, 18, 31, 34, 48, 51 | records, `project.godot` layer 10 "camera" | `test_project_layer_names` (2); 97 related tests, 0 failed | `qa/tmp/visual/g1_pass3/` |

Items pass 3 left open and their state at 2.0.0: the clean full-suite run (R3-50) - **done** (§9.2); the `.uid` import (R3-47) - **done**
in `36e2e8a` (705 of 705 scripts have one); `game/override.cfg` (R3-23) - **gone**; the UI group's findings - **addressed** (§9.5);
the tracker's lamp rows (R3-03) and the day dial in the manor (R3-43) - **open** (`KNOWN_ISSUES.md` §3); real-play checks (R3-49) and
the S4 bot's dodge near braziers (R3-07) - **open**.

## 11. Release 2.0.1 — bug fixes, packaged-exe bot runs A and B (2026-09-28)

**Build under test.** `dist/Hollowhaven-2.0.1-Windows.zip` (111.1 MB, SHA-256 `8017AF7123204BA303EE9E08D8B61A47DBB01CAD87EBAB6E5F311465175857FE`,
`dist/SHA256SUMS.txt`), exe `builds/Hollowhaven/Hollowhaven.exe` (184.8 MB, 13:33; byte-identical to the exe in the zip - checked),
git `da94714` = `c709db8` + version bump (`project.godot` / `export_presets.cfg` 2.0.1) + 2 `.uid` files. Export log
`qa/tmp/build_v201.log` (EXIT=0). The build script moved the 2.0.0 zip to `builds/superseded/`. Same PC as above. Committed evidence
copies: `qa/evidence/ch2_v2.0.1/` (its `README.md` lists each file).

**Zip contents (checked with Python `zipfile` against the repo at `da94714`).** 7 files: `Hollowhaven.exe`, `How to Play.txt`,
`Chapter Two - What's New.txt`, `Licenses/` (`Godot_Engine_Licenses.txt`, `OFL-Fredoka.txt`, `OFL-Nunito.txt`,
`THIRD_PARTY_NOTICES.txt`). `How to Play.txt` and `Chapter Two - What's New.txt` are byte-identical to `docs/player/`, and
`Licenses/THIRD_PARTY_NOTICES.txt` is byte-identical to `THIRD_PARTY_NOTICES.md` (with the build-time audio-encoder note). The 2.0.0
zip's three files differ (older text: "The first time this version saves", "change them any time", no Audio-tab line, no encoder
note). So 2.0.1 is the first zip with the corrected player docs and licence notice.

### 11.1 What changed since 2.0.0 (`git log 36e2e8a..da94714`)
| Commit | What | Tests |
|---|---|---|
| `ec00374` | **Quarry Warden** (`quarry_warden.gd`): CHAIN-001 - it fights only on its arena floor (within 1.2 m of the arena height), never starts an attack at Krystal off it, never walks off its level, and gives up + resets cleanly after 5 s of chase with her off the floor; CHAIN-002 - until its shell has been cracked once in the attempt (while an intact pillar stands) blows stop at 50 % health and it charges to show the pillars | new `test_enemies_ch2_warden_chain.gd`; `test_enemies_ch2_warden`, `test_reach_east_encounter` updated |
| `8c50a61`, `a3f31e1` | QA harness only: focus protection `tools/qa/fglock.py` (§11.5) in `session.py`, `perf_profile.py` and the chain's visible launcher; perf harness | - |
| `75008fc` | evidence only: `qa/evidence/ch2_v2.0.0/` (visible packaged 2.0.0 chain, perf summaries, `full_final1.log`; §11.4) | - |
| `1fcae5a` | QA bot: telemetry-driven Warden fight in `s2_orchard_quarry.py`, five coverage scripts `tools/qa/ch2/cov_*.py`; game side only a read-only `elite` entry in the QA telemetry (`game/src/qa/qa_telemetry.gd`) | - |
| `c709db8` | **COV-001** a lit checkpoint reached through its own entrance (Works refuge hatch, Bellhouse stair) becomes the return point, and Return to safety prefers the safe point of the room Krystal stands in (e.g. the manor cloakroom) - `game.gd`, `pause_panel.gd`; **COV-002** a companion's hit never cancels an ordinary enemy's tell (`enemy_base.gd holds_tell_against`); **COV-003** the Echo Trial is not a landmark (`echo_trial.gd`); **COV-004** arachnophobia wording of the Weaver's banked-scorch and trip-line hints (`weaver_boss.gd`, `hazard_field.gd`); **COV-005** the upstairs goal needs the walk (`build_ops.gd`, `building_system.gd`, `optional_goals.gd`); **COV-006** plurals ("Collect 3 Copper Bars", `item_db.gd display_count`, `crafting.gd`); **COV-007** the wand refunds stamina and cooldown when a hit cancels the wind-up (`player.gd`); **R3-03** the HUD tracker drops the done lamp-search rows (`tracker.gd hud_rows`); **loading card** (`loading_card.gd`, new) shown before an area builds, and the title prefetches Continue's area (`Game.continue_target()` / `prefetch_continue()`) | +33 tests (2639 -> 2672), incl. new `test_flow_loading_card.gd`, `test_trials_helper_zone.gd`; new tests in `test_enemies_ch1x_drudge`, `test_enemies_boss_pacing`, `test_enemies_boss_hazards`, `test_building_storeys`, `test_building_stairs_walk`, `test_station_furnace`, `test_crafting_rules`, `test_wand_player`, `test_works_deep_vault_exit`, `test_flow_ch2_rules`, `test_ui_journal_tracker`, `test_ui_appearance_wardrobe` |
| `da94714` | version 2.0.1; release built | - |

Not changed in 2.0.1: `save_system.gd` (save schema v2, the v1 -> v2 migration and the upgrade backup - the only file with that
code - are as in 2.0.0, so `docs/ch2/SAVE_INTEGRITY_REPORT.md` still applies); `crossing_matron.gd`. **No finishing-blow rule changed in 2.0.1**: "a blow that
would finish the Weaver in her last phase (or Count Velour) always lands" is from `9e8765f` (2.0.0, §9.2, `KNOWN_ISSUES.md` §5); in
2.0.1 `weaver_boss.gd` only changed its two hint texts (COV-004, `test_enemies_boss_pacing.test_banked_and_tripline_hints_follow_arachnophobia_live`).
COV-008 (exit-time leak lines) was not changed (accepted with CH2-011).

Where the COV bugs came from: five bot coverage runs (`tools/qa/ch2/cov_*.py`; **source tree, headless**, virtual input, before
`c709db8`) - equipment / companions, Echo Trials / Expeditions, lamp orders + Chapter One optionals, arachnophobia / comfort,
persistence / failure: 8 unique bugs, 0 blockers, 0 majors (`qa/tmp/bot/COVERAGE_BUGS.md`, with a per-system coverage table). They
were the first bot runs of the Echo Trials (Velour, Choir, Matron entry / leave / lose), Expeditions (Orchard Patrol, Quarry
Circuit), the manor-first and orchard-first lamp orders, and armour / wand / companion skills (diagnostic starts with injected gear);
that is still bot evidence on the source tree, not on the packaged exe and not play.

### 11.2 Automated tests — [auto]
| When | Tree | Result | Log |
|---|---|---|---|
| ~13:18-13:32 | the working tree committed right after as `c709db8`; `da94714` adds only the version bump and 2 `.uid` files (not re-run after it) | **2672 tests, 0 failed, 888.5 s**; `parse_all` passes; 21 `ISOLATION` repairs; ends with "8 ObjectDB instances were leaked at exit" (CH2-011) | `qa/tmp/full_final2.log` (copy: `qa/evidence/ch2_v2.0.1/full_final2.log`) |

### 11.3 Run B — fresh New Game on the packaged 2.0.1 exe, visible — [bot]
`python tools/qa/playthrough.py --second-monitor --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/final_201_fresh`
(13:34:11-13:45:09; console `qa/tmp/e2e/final_201_fresh.console.txt`). The packaged 2.0.1 exe (hard-linked copy with the no-focus
override) in a 1920×1080 window on the second monitor, **sound on** (not muted; nobody listened), virtual input through the QA port,
empty scratch save folder and settings file (`%APPDATA%\Hollowhaven\saves` untouched). Not OS input, not a human.

| Step | s | Step | s | Step | s |
|---|---|---|---|---|---|
| title_new_game (Meet Krystal + New Game) | 17.2 | tailor_cache | 14.5 | descend | 28.7 |
| read_ward | 6.3 | mochi | 25.5 | old_mine | 35.8 |
| gather_basics | 42.0 | pebble | 44.7 | deeper | 37.6 |
| craft_axe | 3.4 | home | 72.9 | silk_and_boss | 75.8 |
| chop | 30.1 | lumi | 47.1 | return_home | 26.1 |
| workbench | 13.9 | prepare | 20.9 | ending | 57.6 |
| | | brave_steps | 51.3 | accept_ch2 + free_play_save | 4.3 + 2.1 |

* **Result: 21 of 21 steps ok, 0 failed, 658.3 s** (bot time); `game_log_errors: []` (no SCRIPT ERROR); 41 screenshots; exit 0.
* The look chosen on "Meet Krystal" (Strawberry Picnic, braided crown) was kept; Tailor's Cache done; the three-phase Weaver Matron
  won in 64.0 s (phases 1-2-3, 0 deaths, lowest HP 91, braziers 0 and 2); Chapter One ending -> Ward Stone -> Chapter Two accepted
  (current step "The Hallowmere Way", `ch2_waygate`) -> free-play save. 20 music-director changes in `play_events.txt` (15 cue
  starts, 5 silences).
* Focus: the watchdog made 2523 checks; the game owned the OS foreground window in **0** of them (0 hand-backs). (The telemetry's
  `frames_focused` 6410/6410 is Godot's own window flag, not the OS foreground.)
* **Findings (not fixed in 2.0.1):** (1) `play_038_ending.png`: the Weaver's fight tip "It is smothering a brazier!..." is still on
  the HUD in the Haven after the Chapter One ending (stale boss-fight tip; fixed in 2.0.2, §12.1). (2) The bot filed one minor problem: the optional Brave Little Steps stopped at `tie_ribbon` - the bot
  pressed E at a "Talk to Mochi" prompt, but the Friends panel that opened was Lumi's (its buttons: "Feed Sweetroot", "Use
  Glimmerstep (T)"), which offers no ribbon; the Comfort Ribbon stayed in the backpack. Investigated after 2.0.1: a bot race, not a game bug
  (§12.3). The step is still reported ok: the harness files a failed optional goal as a problem, not a failure.
* Harness labels: `results.jsonl` tags each step `"kind": "interactive"` / "real-input scenario step" but also `"input": "virtual
  (qa_input, second monitor)"` - the input was virtual; these runs are [bot], not [interactive] in the §1 sense.
* Not covered by Run B: anything in Chapter Two past accepting it, a relaunch / Continue, OS input.

### 11.4 Run A — natural Chapter Two chain on the packaged 2.0.1 exe, headless — [bot]
`python tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/final_201` (13:34:06 -
13:59:40; console `qa/tmp/bot/chain/final_201.console.txt`, log `qa/tmp/bot/chain/final_201/chain.log`). Start: a copy of the real
v0.9.0 Chapter-One-complete save (fixture 16); S1 -> S2 -> T23 -> S3 -> T34 -> S4 -> END (relaunch + Continue), no fixtures, no
cheats, virtual input, headless (nothing rendered, so no screenshots and nothing seen).

| Segment | Result | Seconds | Deaths | Lowest HP | SCRIPT ERRORs | Music cue changes |
|---|---|---|---|---|---|---|
| S1 Continue (v1 -> v2 migration), wardrobe, Ward Stone, waygate, Commons, relaunch | completes | 65.8 | 0 | 66 | 0 | 9 |
| S2 orchard + quarry, Quarry Warden | completes | 234.7 | 0 | 55 | 0 | 11 |
| T23 home to rest and cook, road to the manor | completes | 87.1 | 0 | 91 | 0 | 3 |
| S3 Moonveil Manor, Count Velour | completes | 198.4 | 0 | 86 | 0 | 8 |
| T34 home to rest and cook | completes | 50.4 | 0 | 86 | 0 | 3 |
| S4 lanterns linked, Hushed Works, Crossing Matron, Borrowed Choir, homecoming, Lanternwake, free play | completes | 887.1 | 0 | 26 | 0 | 26 |
| END Save & Quit -> relaunch -> Continue | completes | 8.8 | 0 | 66 | 0 | 3 |
| **Total** | **completes** (console `EXIT=0`) | **1534.8** | **0** | 26 | **0** | **63** |

* Chapter Two complete, 20 of 20 steps; free play reached. END: Save & Quit from the pause menu, the process exited by itself,
  relaunch, Continue loaded the same save in 2.8 s with the same items (`same_items: true`), tracker on the optional signpost.
* Quarry Warden (with the 2.0.1 rules): 32.5 s, 3 pillar exposures [105, 105, 76.8], 3 pulses, 0 hits taken, 0 climbs; Count Velour:
  phases 1-2-3, lowest HP 86, 1 snack, 0 deaths; S4 route steps: Weaver's Crossing 75.7 s, Borrowed Choir 390.1 s (the bot ate snacks at 36 HP
  and 40 HP during it).
* 0 bugs filed (`bugs.json` `[]`), 0 warnings; two quits logged "6" / "7 ObjectDB instances were leaked at exit" (CH2-011).
* Screenshot requests 0 of 123 (headless: nothing is rendered - expected, not a failure of the game).
* This is the first natural chain on the **packaged 2.0.1** exe; it is headless, so it shows that the bot's route, saves and relaunch
  work in the release binary, not what anything looks or sounds like.

Earlier chain runs for comparison (all [bot], virtual input):

| Run | Code | Mode | Result | Total | S1 / S2 / T23 / S3 / T34 / S4 / END (s) | Notes |
|---|---|---|---|---|---|---|
| `chain/visible2` (`qa/evidence/ch2_v2.0.0/visible_run/`) | packaged **2.0.0** exe | visible, second monitor, sound on | **completes** | 1488.4 s | 100.1 / 232.1 / 92.3 / 212.0 / 53.9 / 782.5 / 10.4 | 0 deaths, 0 SCRIPT ERRORs, 62 music cue changes, lowest HP 26 (S4), 122 of 123 screenshots; watchdog 357 + 5287 + 30 checks, game in the foreground 0 times; Warden 1 exposure (before the CHAIN-002 fix) |
| `chain/run6` | source after `ec00374` (before `c709db8`) | headless | **completes** | 1555.9 s | 69.8 / 237.0 / 87.5 / 214.4 / 38.6 / 893.9 / 11.3 | 0 deaths, 0 SCRIPT ERRORs, 64 music cue changes; Warden 32.0 s, 3 exposures [105, 105, 76.8], 0 hits taken (CHAIN-002 retest) |

### 11.5 Focus protection for second-monitor runs — [QA harness]
`tools/qa/fglock.py` (`8c50a61`, `a3f31e1`): a fresh helper process holds `LockSetForegroundWindow` while a QA game runs
(ForegroundLock), and a watchdog checks every 0.25 s whether the game owns the foreground window and hands it straight back if so
(FocusWatchdog). Reason: the packaged build's first window became the OS foreground window ~0.6 s after launch despite the
`no_focus` override. Results: probes 0 of 81 (session launcher) and 0 of 184 (chain launcher) foreground samples; perf runs on 2.0.0
0 of 3152 and 0 of 635 checks; the visible 2.0.0 chain 0 of 5674 checks; **Run B (2.0.1) 0 of 2523 checks, 0 hand-backs**. Run A
is headless (no window). This protects the owner's desktop during QA; it is not a game feature and says nothing about how the game
behaves with real focus / input.

### 11.6 NOT YET DONE after 2.0.1 (honest list; replaces §9.10 where they differ)
Done since §9.10 (all [bot], virtual input): the natural chain on the packaged exe (2.0.0 visible, 2.0.1 headless - Run A), a
visible second-monitor chain (2.0.0), a fresh game through Chapter One on the packaged build (2.0.1 Run B), bot runs of the Echo
Trials, Expeditions, other lamp orders and equipment (source tree, headless; §11.1). Still not done:
* **PERSONAL-SAVE VERIFICATION BLOCKED**: Krystal's own save is not on this PC (gate: `docs/ch2/SAVE_INTEGRITY_REPORT.md` §7; the
  save code is unchanged in 2.0.1, so the gate is the same with the 2.0.1 exe).
* **Human listening**: none. The visible runs played with sound; nobody listened to the music, the Music Box or the mix.
* **OS-level real-input run**: none for Chapter Two (every run above used the QA input port).
* **Human play**: no first-time session; human playtime is unmeasured (bot: ~11 min for Chapter One in Run B, ~22-26 min for Chapter
  Two in the chains - route-aware bot times, not human times).
* **Performance**: only the 2.0.0 exe on the RTX 4090 (398-709 average FPS, §9.8); memory still creeps ~8.5 MB per Lantern Road
  round trip over 10 cycles (`qa/evidence/ch2_v2.0.0/perf/leak10_summary.md`; 9.9-15.7 MB in the 3-cycle runs); 2.0.1 not
  re-profiled; no weaker / integrated GPU, no V-Sync-on default, no long session.
* **Chapter Two on screen in 2.0.1**: Run A is headless, so no Chapter Two area of the 2.0.1 build was rendered; the last rendered
  Chapter Two run is the visible 2.0.0 chain. Nothing was judged in motion.
* The Warden's 5 s give-up + reset (CHAIN-001) is unit-tested only; the bot never stayed off its floor long enough.
* Echo Trials, Expeditions, other lamp orders and equipment: bot coverage runs on the source tree only (§11.1), not on the packaged exe.
* Not implemented: the optional friend Pipkin; new creature voices (D10).
* Accepted: CH2-011 / CHAIN-003 ObjectDB leak warning at exit (developer logs only); the "resources still in use" ERROR lines of
  COV-008 are not yet explained (`KNOWN_ISSUES.md` §6).

## 12. Release 2.0.2 — boss-fight tips (2026-09-28)

**Build under test.** `dist/Hollowhaven-2.0.2-Windows.zip` (111.1 MB, SHA-256 `2F77F52F219F5452E4140FD95DA25895C94E7C59E7A20231143ED564E4907FA8`,
`dist/SHA256SUMS.txt`), exe `builds/Hollowhaven/Hollowhaven.exe` (184.8 MB, 14:12; byte-identical to the exe in the zip - checked),
git `991014c` = `a31e717` + version bump (`project.godot` / `export_presets.cfg` 2.0.2) + a QA-bot change in `tools/qa/playthrough.py`
(not shipped). Build log `qa/tmp/build_v202.log`, built with `tools/build_release.ps1 -SkipTests` (no test output in the log; it ends with the
"Built ... SHA256" line; EXIT=0 was captured in the lead's shell, not in the log). The 2.0.1 zip moved to `builds/superseded/`. The zip has the same 7 files as 2.0.1; its player
docs and `Licenses/THIRD_PARTY_NOTICES.txt` are still byte-identical to `docs/player/` and `THIRD_PARTY_NOTICES.md` (checked).
Evidence copies: `qa/evidence/ch2_v2.0.2/`.

### 12.1 The fix (`a31e717`, `game/src/ui/hud/hint_card.gd`; the only game change since 2.0.1)
* **Fight tips** = hint ids starting with `boss_`, `velour_`, `choir_` or `hint_quarry_warden_` (`FIGHT_TIP_PREFIXES`).
* A newer fight tip replaces an older one still waiting in the queue; the dropped tip gets its once-per-save flag back, so a later
  attempt still teaches it.
* The fight tip on screen makes room after 4 s (`FIGHT_TIP_MIN_SECONDS`) when a newer fight tip waits; ordinary tips keep their
  full time.
* The end of the encounter - `boss_encounter_changed` false (won, reset or left), `boss_defeated`, `area_exiting` - drops every
  fight tip at once, also while the card is held (a held fight tip never comes back).

**Why.** (1) Run B on 2.0.1 (§11.3): `play_038_ending.png` shows the Weaver's "It is smothering a brazier!" tip on the HUD in the
Haven after the Chapter One ending. (2) Run A on 2.0.1 (`qa/tmp/bot/chain/final_201.console.txt`): during the 75.7 s Crossing Matron
step the fight emitted 17 `boss_crossing_*` hints of 9 different ids in 67 s (13:49:42-13:50:49; `run6` logged 19); each tip stays
on the card for several seconds and they were shown one after another, so the queue outlasted the fight. The telemetry has no
hint-card state, so that overrun is inferred from the emission times and card durations, not observed on screen (the commit
message counts "ten Crossing Matron tips in 75 s"). Note: a comment in `hint_card.gd` says the Crossing tips spilled "over the Chapter
One ending"; the tip seen over the Chapter One ending was the Weaver's (comment wording only).

**Tests.** New `game/tests/unit/test_hint_card_fight_tips.gd` (7): `which_tips_are_fight_tips`,
`a_newer_fight_tip_replaces_an_older_queued_one`, `the_fight_tip_on_screen_makes_room_for_a_newer_one`,
`ordinary_tips_keep_their_full_time`, `the_end_of_the_encounter_drops_the_fight_tips`,
`a_held_fight_tip_never_comes_back_after_the_fight`, `defeat_and_area_change_are_wired`. All pass in the full run.

### 12.2 Automated tests — [auto]
| When | Tree | Result | Log |
|---|---|---|---|
| ~13:52-14:07 | the working tree committed right after as `a31e717` (the version bump `991014c` changes only version strings in `game/`) | **2679 tests, 0 failed, 890.7 s** (2672 + the 7 new); `parse_all` passes; 21 `ISOLATION` repairs; "8 ObjectDB instances were leaked at exit" (CH2-011) | `qa/tmp/full_final3.log` (copy in `qa/evidence/ch2_v2.0.2/`) |
| 14:07 / 14:11 | after the version strings were edited (`project.godot` / `export_presets.cfg` edited, save + audit run, then `991014c` committed at 14:11:57) | save filter **128 / 0**; audit filter **83 / 0** | `qa/tmp/test_results_save.json`, `test_results_audit.json` (copies in `qa/evidence/ch2_v2.0.2/`) |

### 12.3 Run B's "wrong panel" (Mochi / Lumi) — investigated: a bot race, not a game bug
In Run B (§11.3) the bot pressed E at "Talk to Mochi" and Lumi's Friends panel opened. Cause: the bot read "Talk to Mochi" from a
telemetry frame 100-200 ms old; when E landed, the game's own prompt already said "Talk to Lumi" (Mochi was running away at ~4.5 m/s,
Lumi 1.4 m away). The prompt, the HUD and E share `probe.prompt` / `probe.focus` (`player.gd` 328-331 and 1235-1267,
`interaction_probe.gd` 173-185): E re-scores the target immediately, while the HUD label refreshes every 0.08 s, so when two targets
cross the label can trail the real target by up to ~160 ms. Minor UX edge, not changed (`KNOWN_ISSUES.md` §3). The bot was fixed in
`991014c` (`playthrough.py` checks whose panel opened and retries).

### 12.4 Verification runs on the packaged 2.0.2 exe — [bot]
| Run | Command | Result |
|---|---|---|
| V1 fresh New Game, visible on the second monitor, sound on | `python tools/qa/playthrough.py --second-monitor --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/final_202_fresh` (console `qa/tmp/e2e/final_202_fresh.console.txt`), 14:12:28-14:24:06 | **21 of 21 steps ok, 0 failed, 697.2 s**, EXIT=0; no bot-filed problems - Brave Little Steps finished this time (ribbon tied, Mochi follows: `ribbon_tied: true`, no retry needed, `play_030_mochi_ribbon.png`); 0 SCRIPT ERRORs (`game_log_errors: []`); 42 screenshots; Weaver Matron 63.6 s (phases 1-2-3, 0 deaths, lowest HP 88); Chapter Two accepted (`ch2_waygate`); 23 music-director changes (18 cue starts, 5 silences); watchdog 2669 checks, game in the OS foreground 0 times, 0 hand-backs (the lead's separate foreground monitor also reported nothing). **`play_039_ending.png`**: after the Chapter One ending the HUD shows only the "When you're ready - The Ward Stone has something new to say" card, the "Read the Ward Stone" prompt and "Journey saved" - no stale Weaver tip (2.0.1's `play_038_ending.png` showed "It is smothering a brazier!") |
| V2 Chapter Two finale, headless, from Run A's `T34_end` checkpoint save (a save the 2.0.1 game wrote in Run A) | `python tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --from S4 --start-save qa/tmp/bot/chain/final_201/checkpoints/T34_end --out qa/tmp/bot/chain/final_202_s4` (console `qa/tmp/bot/chain/final_202_s4.console.txt`): link the lanterns, Hushed Works, Crossing Matron, Borrowed Choir, Lanternwake ending, free play, relaunch + Continue; 14:12:28-14:27:28 | **completes**, 900.7 s (S4 883.4, END 8.8), EXIT=0; 0 deaths (lowest HP 24), 0 SCRIPT ERRORs, 0 warnings, `bugs.json` `[]`, 32 music cue changes; route steps Weaver's Crossing 74.0 s, Borrowed Choir 412.7 s; END: saved before quit, Save & Quit, relaunch, Continue in 2.9 s, same items, `chapter_two_complete: true`, 20 of 20 Chapter Two steps; one quit logged "7 ObjectDB instances were leaked at exit" (CH2-011). Headless: nothing rendered (0 of 36 screenshots), so the Crossing / Choir tips were not seen on screen |

V2 is a resumed start (`--start-save`), not a natural chain from the Chapter One save; S1-T34 on the 2.0.2 exe were not re-run
(the 2.0.2 change is HUD-only; the natural chain on 2.0.1 is §11.4).

### 12.5 NOT YET DONE after 2.0.2
Unchanged from §11.6: PERSONAL-SAVE VERIFICATION BLOCKED; no human listening; no OS-level real-input run; human playtime
unmeasured; performance only on the 2.0.0 exe and an RTX 4090 (2.0.1 / 2.0.2 not re-profiled; memory creep ~8.5 MB per Lantern
Road round trip); nothing judged in motion; Pipkin not implemented; CH2-011 accepted. The stale boss-fight tip is fixed (§12.1):
checked by unit tests and, for the Weaver after the Chapter One ending, on screen in V1 (`play_039_ending.png`); the Crossing
Matron / Choir / Velour / Warden cases were not rendered on 2.0.2 (V2 is headless), so for them the fix rests on the unit tests.
Only V1 re-ran Chapter One and only V2 re-ran the Chapter Two finale on 2.0.2; S1-T34 of Chapter Two were not re-run on 2.0.2.

## 13. Release 2.0.3 — the gift build: installer, first-time player (2026-09-28)

**Context change (from the owner, 2026-09-28).** Krystal has **never played** Hollowhaven and never received any version. She will
play for the first time, on her own PC (specs unknown), starting with **New Game** (comfort options -> "Meet Krystal" -> Chapter One
-> Chapter Two at the Ward Stone), from an **installer**. So the returning-player framing of §9-§12 is obsolete: there is no
Chapter One save to Continue, the "Chapter Two - What's New" note is retired, and **PERSONAL-SAVE VERIFICATION BLOCKED no longer
applies** (there is no personal save). The v1 -> v2 migration evidence (§9.3, `docs/ch2/SAVE_INTEGRITY_REPORT.md`) only matters for a
pre-2.0 save, which she does not have. Her path - a save written by New Game in a 2.x build - is what the native-save runs (§13.4)
and F1 / F2 (§13.7) cover.

**Build under test.** Installer `dist/Hollowhaven-Setup-2.0.3.exe` (100.8 MB, 105,736,221 bytes, SHA-256
`9A8660DDF85E344C2333100B1E47FC90A791B9F49162B59ED8CE3822A26D18E2`) and zip `dist/Hollowhaven-2.0.3-Windows.zip` (111.1 MB, SHA-256
`1788D65B101CCF4581011C3ABE60963CF18511A96A59DAA58FA5FBD2FA60A670`), both in `dist/SHA256SUMS.txt` (checked); git `8f5cbc0` (committed
18:15:02). `tools/build_release.ps1 -SkipTests` finished 18:15:29 (`qa/tmp/build_v203.log`, EXIT=0, no test output);
`tools/build_installer.ps1` 18:16 (`qa/tmp/build_installer_v203.log`, EXIT=0: exe file version 2.0.3.0, `builds/Hollowhaven` matches the
zip file for file by SHA-256, Setup-2.0.2 moved to `builds/superseded/`). The zip now holds 6 files - `Hollowhaven.exe` (184.8 MB),
`How to Play.txt`, `Licenses/` (4 files); "Chapter Two - What's New.txt" is no longer shipped. `How to Play.txt` and
`Licenses/THIRD_PARTY_NOTICES.txt` are byte-identical to `docs/player/How to Play.txt` and `THIRD_PARTY_NOTICES.md`; the zip's exe is
byte-identical to `builds/Hollowhaven/Hollowhaven.exe` and to the silent test install (§13.3). Evidence copies:
`qa/evidence/ch2_v2.0.3/` (its `README.md` lists each file).

### 13.1 What changed since 2.0.2 (`git log 02aec8f..8f5cbc0`)
| Commit | What | Tests / checks |
|---|---|---|
| `88218b6` | **Installer** (Inno Setup 6.7, `tools/installer/hollowhaven.iss`, `tools/build_installer.ps1`, `docs/INSTALLER.md`): per-user, no admin / UAC prompt, `%LOCALAPPDATA%\Programs\Hollowhaven`, Start Menu "Hollowhaven" + "How to Play", Desktop shortcut ticked by default, a welcome message for Krystal, constant AppId (a later installer updates in place), uninstall never touches `%APPDATA%\Hollowhaven` (saves, settings) | silent tests only (§13.3) |
| `eab619d` | **First-time player text**: `How to Play.txt` rewritten for someone who has never played (New Game, both chapters; reviewer fixed 4 small factual errors), the returning-player "What's New" note retired, in-game "update" wording removed (controls tip, wardrobe reset -> "Classic look", companion / kitchen / onboarding texts, the Heartbloom goal text); release build ships `How to Play.txt` only | new `test_first_time_player_text` (6); `test_onboarding_text`, `test_audit_release_packaging` updated |
| `bb79708` | QA only: the primary-monitor guard (§13.6); `chain.py` / `s1_continuation.py` accept a native version-2 start save (no migration checks) | dummy-window tests of the guard |
| `37d93ef` | **Different-PC readiness** report `docs/ch2/DIFFERENT_PC_READINESS.md` (renderer fallback chain Vulkan -> Direct3D 12 -> OpenGL, a clean first run, small windows, integrated-GPU presets, minimum / recommended PC); no game code change | new `test_pc_readiness_settings` (6) pins the fallback settings |
| `caab0a4` | **Fight-tip priorities** (`hint_card.gd`): openings ("strike now") > boss instructions > elite attack tells (`tell_quarry_warden_*`, `tell_knotted_elder_*`, now fight tips too) > ordinary tips; nothing outlives the fight (also a hidden boss bar ends the Knotted Elder's tips); the Warden's bench give-up tip is no longer dropped in the same tick | `test_hint_card_fight_tips` 7 -> 16 tests; replays (§13.5) |
| `36934ae` | **Companions never drawn inside the camera**: hidden below 0.85 m from the follow camera, shown again above 1.0 m (visual only; AI, collision, saving, portraits unchanged). Found in `native_202_visible` (Mochi filled the frame on the Sunken Bellhouse service stair, `s4/005`) | new `test_companions_camera_clearance` (6); a short visible source check `qa/tmp/cam_companion/visible1` |
| `ac5c69c` | **HUD**: toasts never cover the goal card (the toast column starts below the day dial / goal card / a wide banner; waiting toasts keep their time); the quest banner measures a wrapped line at its real width (the festival-map card was 247-2410 px tall); a neutral journal tag for goals open from the start | new `test_ui_toast_layout` (5), `test_ui_journal_tabs` updated; probes `qa/tmp/ui_overlap_review/` |
| `8f5cbc0` | version 2.0.3 | - |

### 13.2 Automated tests — [auto]
| When | Tree | Result | Log |
|---|---|---|---|
| 18:15-18:31 | `8f5cbc0` (clean working tree, after the version bump: the code the build was exported from) | **2712 tests, 0 failed, 949.9 s**, EXIT=0; `parse_all` passes; 21 `ISOLATION` repairs; "8 ObjectDB instances were leaked at exit" (CH2-011) | `qa/tmp/full_final4.log` (copy in `qa/evidence/ch2_v2.0.3/`) |

### 13.3 Installer — silent tests only
* **2.0.2-era installer** (15:11-15:41, `Hollowhaven-Setup-2.0.2.exe` and a 2.0.0 test build; `qa/tmp/installer/`, independent review
  `qa/tmp/installer/review/`): byte-identical files, the Settings > Apps entry under HKCU only (nothing in HKLM), a headless boot of the
  installed game, same-version reinstall, 2.0.0 -> 2.0.2 update in place without `/DIR` (one entry), Start Menu + Desktop shortcuts
  resolving to the right targets (also in a folder path with spaces, an accent, ♥ and a Chinese character), silent uninstall removing
  everything it installed, and `%APPDATA%\Hollowhaven` unchanged by all of it. An update while a *headless* game ran from the install
  folder was refused safely (Setup aborted before changing a file); the normal case - a game window Setup can close - was not run.
* **2.0.3 installer**: `build_installer.ps1` checked `builds/Hollowhaven` against the zip file for file; a silent install
  (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS /MERGETASKS=!desktopicon`) into `qa/tmp/final203/install` succeeded; its 6 game
  files have the same SHA-256 list as `builds/Hollowhaven` (`installed.sha` = `builds.sha`), no Start Menu or Desktop shortcut was
  created. F2 (§13.7) ran that installed exe. Afterwards a silent uninstall (`unins000.exe /VERYSILENT`, exit 0,
  `qa/tmp/final203/logs/uninstall.log`: "Removed all? Yes") removed the folder and the HKCU uninstall entry (AppId
  `6FD89CDE...`); `%APPDATA%\Hollowhaven\saves` stayed empty and `settings.cfg` untouched (mtime 2026-09-27 20:27).
* **Never seen on screen**: no installer or uninstaller window was ever opened, so the wizard pages (welcome text, picture, the
  "Play Hollowhaven now" box) have not been looked at. Not tested either: SmartScreen / Smart App Control on another PC, an update
  while a visible game window runs, a OneDrive-redirected Desktop.

### 13.4 Chapter Two from a New-Game save (packaged 2.0.2 exe) — [bot]
Start save `qa/tmp/bot/chain/native_start_202/slot1.json` = the save the 2.0.2 V1 fresh New Game wrote (same SHA-256 as
`qa/tmp/e2e/final_202_fresh/saves/slot1.json`): the first chains from a save made by New Game (no v1 migration) - Krystal's path.
These ran on the **2.0.2** exe, before the 2.0.3 fixes.

| Run | Mode | Result | Total | Segments (s) | Notes |
|---|---|---|---|---|---|
| `native_202_visible` (15:04-15:28) | visible 1920×1080, sound on, virtual input | **completes** | 1393.0 s | S1 121.9 / S2 235.5 / T23 81.9 / S3 198.8 / T34 55.9 / S4 681.4 / END 12.4 | 0 deaths, 0 SCRIPT ERRORs, 63 music cue changes, 121 of 122 screenshots, Continue after relaunch 4.3 s with the same items; Warden 31.9 s, 3 exposures; watchdog 0 focus takes - **but the window sat on the owner's primary monitor (§13.6)**. Found: Mochi inside the camera on the Bellhouse stair (-> `36934ae`), the Warden's late tells (-> `caab0a4`) |
| `native_202_headless` | headless | **stopped in T23** (`lantern_road_commons`: "no Ward Stone near the Haven" - the bot got lost; fixed in the bot) | 436.8 s | S1 97.9 / S2 239.8 / T23 96.6 (stop) | 0 SCRIPT ERRORs |
| `native_202_headless_resumeT23` | headless, resumed from that run's `S2_end` checkpoint | **completes** | 1076.6 s | T23 76.6 / S3 206.0 / T34 51.0 / S4 723.4 / END 9.5 | 0 deaths, 0 SCRIPT ERRORs, same items after relaunch |
| `native_202_headless_full` (15:28-15:51) | headless, from the native start save | **completes** | 1426.1 s | S1 102.1 / S2 233.2 / T23 89.6 / S3 223.7 / T34 55.6 / S4 709.8 / END 9.4 | 0 SCRIPT ERRORs, 64 music cue changes, Continue after relaunch 3.5 s with the same items |

### 13.5 Fight-tip priorities — [replay]
Checked by replaying the tip emissions recorded in earlier bot runs through the real `hint_card.gd` (old 2.0.2 vs new; headless, no
fight watched on screen): 19 builder and 59 reviewer fight windows plus 600 fuzz runs (commit `caab0a4`; `qa/tmp/fighttips/report.txt`,
`qa/tmp/fighttips_review/`). Example, the Warden in `native_202_visible`: 2.0.2 showed its tells 16-26 s late, dropped "the shell is
open" unshown, and left two tells on screen 6.9 s and 15.3 s past its defeat; new: tells 0.35-4.8 s late, the opening 0.35 s after
it was emitted, nothing after the end. Over all replays: no fight tip on screen after an encounter end and no ordinary tip lost - but
an ordinary tip emitted during a fight now waits (e.g. `tell_brood_skitter_leap` shown 26.9 s after emission in one Weaver replay).

### 13.6 QA incident: test windows on the owner's primary monitor (QA process, not the game)
On 2026-09-28, about 15:00-15:56, the 1920×1080 QA windows that were asked for at 1920,0 (the second monitor) sat at **0,0 on the
owner's primary monitor**: the visible native Chapter Two chain (`native_202_visible`, 15:04-15:28, about 23 minutes, **with sound**)
and the full-size PC-readiness probes (`qa/tmp/pcready/runs/`: a_default, b_d3d12, c_compat, c2_angle, e1-e7, f1, f2, g1, g2; muted).
Telemetry `window_pos` was [0, 0] for all 18 of those processes; every smaller window (1366×768, 1280×720, 1728×1080, 1620×1080,
1920×822) landed correctly at 1920,0. The windows never took keyboard focus, so the focus watchdog (0 focus takes in every run) did not
notice. Fixed in `bb79708`: launchers take a rect 8 px inside the live second monitor and refuse any rect not fully on a non-primary
monitor, and the watchdog moves a window that overlaps the primary monitor back and kills the game if it is still there ~0.5 s later
(tested with dummy windows). Later visible runs (`qa/tmp/hud_clutter/visible`, `qa/tmp/cam_companion/visible1`, 16:48-16:49) opened
at [1928, 8] with `on_primary_checks` 0. This also answers `docs/ch2/DIFFERENT_PC_READINESS.md` §7's open question about where the
probe windows were: the 1920×1080 probes were on the primary monitor. Evidence: `qa/evidence/ch2_v2.0.3/incident_primary_monitor/`.

### 13.7 Verification on the 2.0.3 build — [bot]
| Run | Command / what ran | Result |
|---|---|---|
| F1, first attempt: fresh New Game -> Chapter One -> accept Chapter Two, headless | a headless `tools/qa/playthrough.py` run into `qa/tmp/final203/fresh` (console `qa/tmp/final203/fresh.console.txt`, 18:16:49-18:21:06). Its console (line 1) shows the Godot 4.7.2 console binary running the **source project** `game/` (at `8f5cbc0`), not the installed exe: `playthrough.py --headless` only uses a given `--exe` when it is a console binary | **stopped** at step `home` after 9 passed steps: "StepFailed: no ['Grass', 'Fiber'] nearby" after two `walk_to stuck` events - a bot navigation problem (no world or gathering code changed in 2.0.3; the same steps passed in the 2.0.2 V1 run and in the re-run below); `game_log_errors: []`, no problems filed |
| F1 re-run: the same route with the headless route bot | `tools/qa/ch2/s0_fresh_c1.py --attempt 31 --out qa/tmp/final203/s0` (console `qa/tmp/final203/s0.console.txt`, 18:21:52-18:34; result `s0/s0_result.json`); `headless_session` always runs the **source project** (`8f5cbc0` = the build's code) | **completes**, 721.5 s, 21 of 21 steps, `problems: []`, `game_log_errors: []`; the look chosen on "Meet Krystal" kept (Strawberry Picnic, braided crown); Tailor's Cache, Brave Little Steps (ribbon tied, Mochi follows) and the courage lantern done; Weaver Matron 69.0 s, phases 1-2-3, 0 deaths, lowest HP 79; ending; Chapter Two accepted (`ch2_waygate`); save; Continue check ok (9.8 s to play, no mismatches) |
| F2 Chapter Two S1 -> END from the native New-Game save, headless | `tools/qa/ch2/chain.py` headless into `qa/tmp/final203/chain_native` (console `qa/tmp/final203/chain_native.console.txt`, started 18:16:49): its first lines show `exe=qa/tmp/final203/install/Hollowhaven.exe` - the **installed** 2.0.3 exe - and `start_save=qa/tmp/final203/native_start/slot1.json` (native_v2, from S1; a copy of `qa/tmp/bot/chain/native_start_202`, the 2.0.2 V1 New-Game save, same SHA-256) | **completes**, `start_kind: native_v2`, `natural: true`, 1509.3 s (S1 102.8 / S2 226.9 / T23 79.5 / S3 212.1 / T34 45.7 / S4 829.0 / END 10.4), 0 deaths (lowest HP 28.2 in S4), 0 SCRIPT ERRORs, 0 warnings, `bugs.json` `[]`, 64 music cue changes; Quarry Warden 32.1 s, 3 pillar exposures, 0 hits taken; Count Velour phases 1-2-3, lowest HP 62; END: saved before quit, Save & Quit, relaunch, Continue in 3.8 s with the same items, `chapter_two_complete: true`, 20 of 20 steps. All three game processes were the installed exe with `--headless` (nothing rendered, 0 of 122 screenshots) |

**So, on 2.0.3:** Chapter One (fresh New Game -> accepting Chapter Two) completed only **headless on the 2.0.3 sources** (the re-run;
the first attempt stopped on a bot navigation problem) - it was **not** run on the installed exe; Chapter Two from a New-Game save
completed on the **installed exe**, headless. No 2.0.3 run rendered anything on screen.

### 13.8 NOT YET DONE for the gift (honest list; replaces §11.6 / §12.5)
* **No human has played** any 2.x build; Krystal will be the first. Human playtime is unmeasured (bot: ~11-12 min for Chapter One,
  ~22-26 min for Chapter Two, route-aware - not human times).
* **No OS-level real-input run**, **no human listening** (music, Music Box, mix), **nothing judged in motion** (stills and bot runs only).
* **Her PC is unknown.** Nothing ran on a second physical PC. The weaker-GPU numbers in `docs/ch2/DIFFERENT_PC_READINESS.md` are
  estimates scaled from one measured weak built-in chip (15 FPS at the automatic settings, 22-25 FPS at Low); the renderer fallbacks
  were simulated per process; the default fullscreen first start was never run. The owner chose to ship 2.0.3 **without** the
  readiness report's recommended first-start quality changes (§6 items 3 and 4: Low / lower render scale on integrated GPUs, not
  High on the OpenGL fallback); they stay open. On a slow PC the fix is by hand: `How to Play.txt` "IF THE GAME RUNS SLOWLY"
  (Settings > Video > Graphics quality Medium or Low, a lower Render scale).
* **Chapter One on the installed 2.0.3 exe** was not run (only headless on the identical sources, §13.7).
* **Installer**: the wizard pages were never seen on screen; SmartScreen / Smart App Control on her Windows and an update over a running
  game window are untested (`docs/INSTALLER.md`).
* **Performance** of 2.0.1-2.0.3 not re-profiled (the RTX 4090 profile is of the 2.0.0 exe, §9.8).
* Known small issues kept for 2.0.3 (`KNOWN_ISSUES.md` §3): the Bellhouse service-stair camera sits ~0.25 m above a tread; a companion
  near the camera vanishes / reappears instantly (no fade); toasts on screen can vanish and come back later when a longer dialogue
  line shrinks the room; ordinary tips emitted during a fight wait behind fight tips; enemy tell tips are emitted once per session;
  Pipkin not implemented; CH2-011 leak warning (developer logs only).
* No longer applicable: PERSONAL-SAVE VERIFICATION (no personal save exists).
