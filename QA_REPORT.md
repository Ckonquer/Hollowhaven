# QA report — Hollowhaven v0.9.0

Every entry says what KIND of check it was:
**[code]** source review · **[auto]** automated tests (headless engine) · **[visual]** launched and inspected
real rendered frames · **[interactive]** played through real OS-level keyboard/mouse input (Win32 SendInput)
sent to the game window · **[subjective]** human judgement — marked *not verified* where it wasn't done.

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

## 7. Not verified (honest list)
Human listening; human subjective fun/pacing; weaker GPUs; the scripted release persistence run (3.3);
arachnophobia visuals on the final build; 1080p fullscreen perf profile; gamepad (not supported).

## 8. Later changes (after the release playthrough)
The credits text changed to "For Krystal / from Ali" (commit 9512a0d) and a headless code audit produced further fixes. These later builds were verified by the automated test suite (headless) only, not by a new real-input playthrough (the owner needed the PC). Details and the final suite result: `docs/Hollowhaven_Technical_Handoff.md` section 9 and the git log.

## 9. Chapter Two — integration pass after Waves B/C (2026-09-28) — [auto] only
Chapter Two is still in development. Everything in this section is **[auto]** (headless unit tests on the owner's PC, same
environment as above). **No Chapter Two content has been checked [visual] or [interactive] yet**: the pending visual and real-input
checks are listed in `KNOWN_ISSUES.md` ("Chapter Two (in development)"), the debug/visual-QA commands to run them are in `AGENTS.md`,
and the decisions of the pass are in `docs/ch2/INTEGRATION_WAVE_BC.md`.

The pass ran as twelve parallel fixer groups; the Wave D modules and the three Chapter Two boss modules were also still being
written, so each full run below is a snapshot of files that were changing while it ran. Command for every row:
`tools/godot.sh --headless --path game res://tests/runner.tscn -- --filter=<f> --results=<json> --max-seconds=2400` (what
`tools/test.sh` runs), results kept outside the repo.

| When | Run | Result | Observed failures |
|---|---|---|---|
| before the pass (lead) | full suite | 2164 tests, 11 failed, 738 s | 8 order-dependent (pass alone): two companion stuck-recovery tests, one companion nav test, five world-item tests in `test_world_nodes`; per the integration plan the other three came from the audio-name scanner's false positives (R42) and the stale Wave A flow assertions (R08); all three causes were addressed in the pass (R08, R09 runner isolation, R42) |
| 03:08-03:22 | full suite | 2279 tests, 20 failed, 834 s | taken while other groups were mid-edit: 11 map/UI tests hit map_panel / map_view halfway through the map-reward change (`data_area`, `resource_pins` not yet in the loaded scripts); the new festival pumpkin faces over the triangle budget (being modelled); 5 `test_world_nodes` world-item tests (order-dependent; `tests/runner.gd` with the new isolation was still being changed at 03:14, after this run had started); the Echo Trial unstuck label (see below); one flaky blink test; one scratch probe file that failed to load |
| 03:24 | the 19 failed tests' suites together (`test_world_nodes, test_ui_map_areas, test_ui_root, test_audit_ui_input_layout, test_player_avatar, parse_all`) | 67 tests, 0 failed, 39 s | — (the edits above had settled) |
| 03:23-03:37 | full suite | **2334 tests, 4 failed, 810 s** | `test_enemies_ch2_mimic.test_dormant_is_decor_that_twitches_in_pairs` (known timing flake, deferred D05); `test_music_box_selector.test_unknown_and_unplayable_favourites_are_ignored` and a load failure of `test_expeditions_zz_probe.gd` (Wave D modules still being written, not part of the pass); `test_ui_appearance_wardrobe.test_unstuck_labels_and_targets_per_area` still expects "Return to safety" in the Echo Trial, where the lead decision R17 now says "Leave the trial" (the test needs that one expectation updated) |
| both full runs | `test_zz_parse_all.test_all_scripts_compile` | PASS | every script compiles |

Isolation evidence (second full run, runner R09): 22 `ISOLATION <suite>: ...` repairs were printed — stray projectiles / particles
left by enemy, wand and companion suites, `Game._bosses` left set by the boss suites, a leftover zone / safe-zone flag in two
progression audits, world items left by `test_reach_west_orchard` — and none of the formerly order-dependent tests failed. Those
suites should eventually clean up after themselves.

### 9.1 Integration test run after the pass (2026-09-28 03:44-04:35) — [auto] only
Same command as above (`tools/test.sh`, full suite; `tools/test.sh parse_all`). Boss, Chapter Two enemy and QA-input modules and
the Wave D modules (expeditions, trials, music box, onboarding hints) were still being edited by other agents during these runs.
Logs: `qa/tmp/full_integration_bc.log` (first run), `qa/tmp/full_integration_bc_final.log` (final run), `qa/tmp/timing_suites_3x.log`.

| When | Run | Result | Observed failures / notes |
|---|---|---|---|
| 03:43 | `parse_all` | 1 tests, 0 failed | — |
| 03:44-03:58 | full suite | 2407 tests, 3 failed, 823 s | `test_expeditions_templates.test_the_reach_gets_a_runner_and_groups_stand_on_its_ground`, `test_expeditions_ui.test_setting_aside_at_the_cache_says_the_cache_stays_closed`: the Wave D expedition files (`src/expeditions/*`, `data/expeditions.gd`, the panel and these tests) were rewritten 03:51-03:53, while the run reached them; 39/39 pass at 04:01 and 3/3 re-runs pass. `test_ui_appearance_wardrobe.test_unstuck_labels_and_targets_per_area`: outdated expectation (R17) — fixed in the test |
| 04:02-04:18 | the 33 suites that measure time (`get_ticks_msec/usec`), three times in a row | 393 tests, 0 failed ×3 (315 s, 309 s, 312 s) | no flaky timing test found |
| 04:18 | `test_enemies_ch2_mimic` + `test_expeditions` ×3 | 49 tests, 0 failed ×3 | the D05 mimic flake did not reproduce (still deferred: busy file) |
| 04:21-04:35 | full suite (final) | **2407 tests, 0 failed, 820 s** | 20 `ISOLATION` repairs (was 22: the two progression audits now restore Game's zone / safe-zone state themselves) |
| 04:36 | `parse_all` | 1 tests, 0 failed | — |

Test changes of this pass: `test_ui_appearance_wardrobe` (Echo Trial label follows lead decision R17: "Leave the trial"; the
product requirement changed on purpose), `test_player_avatar.test_idle_head_height_and_blink` (deterministic: after the forced
blink the test pushes the next blink out of its window, so the random 18% double blink can no longer land inside it; product code
unchanged), `test_audit_progression_comfort` / `test_audit_progression_reentry` (restore `Game.zone_id` / `Game.in_safe_zone` in
`after_each`).

## 10. Chapter Two — bug-fix round 1 (CH2-001..017) and the visual fixes (2026-09-28)
Kinds used in this section (in addition to the legend at the top):
**[bot]** the QA bot (`tools/qa/ch2`, route segments S0-S4) drives a **headless** engine through the game's QA input port: injected
keyboard / mouse events and telemetry reads, nothing rendered, no OS-level input - so these runs are not **[interactive]** in the
section-1 sense. **[visual]** still frames rendered on the second monitor (1920×1080 at 1920,0; muted, no focus, bounded runs, scratch
saves) and looked at by the agent that made the change. **No human has played or listened to Chapter Two yet.**

### 10.1 What was found
* Five [bot] route segments (S0 fresh Chapter One → S4 Works finale; `qa/tmp/bot/BUGS_MERGED.md`): 17 bugs - 0 blockers, 2 major
  (CH2-001 lamp seals held back, CH2-002 Reach trees raising SCRIPT ERRORs), 5 minor (boss / elite pacing CH2-003/004/007, Count Velour's
  channel behind the candle stand CH2-005, an enemy threatening through a wall CH2-006), 10 polish.
* Six still-frame reviews (avatar, building, creatures, interiors, Reach, UI; `qa/tmp/visual/VISUAL_BUGS_MERGED.md`): 110 findings -
  0 blockers, 21 major, 47 minor, 42 polish.

### 10.2 Automated tests — [auto]
Same command as section 9 (`tools/test.sh`, headless). The bug fixes landed while other agents were still editing ~75 files for the
visual fixes, so the verifier ran the full suite on a **snapshot**: git HEAD 5cd7774 plus the 44 bug-fix files, byte-identical to the
working tree (`C:\Users\Ali\AppData\Local\Temp\claude\...\scratchpad\snap`).

| When | Tree | Run | Result | Notes |
|---|---|---|---|---|
| 08:31 | snapshot | full suite | 2534 tests, 2 failed, 847 s (`qa/tmp/full_bugfix1_run1.log`) | `test_audit_release_packaging` read the local, gitignored `game/override.cfg` (window mode 0) left by a QA run; `test_flow_quit_prefetch` assumed no earlier suite left a prefetch → the test now releases them in `before_each()` (still fails on the old game.gd) |
| 08:48 | snapshot + that test fix | full suite | **2534 tests, 0 failed, 842 s** (`qa/tmp/full_bugfix1.log`) | the run ends with "7 ObjectDB instances were leaked at exit" (CH2-011, 10.3) |
| 08:48 | live tree, visual fixes mid-edit | full suite | 2587 tests, 33 failed (`qa/tmp/full_bugfix1_worktree.log`) | 25 from `tobin_annex_world.gd` not compiling at that moment; `camera_spawn_clearance` ×3, `reach_visual_fixes` ×2, `avatar_look_fit` ×1, `reach_west_build` ×1 (16 lights > 8), the override.cfg test; none in a bug-fix file |
| ~09:20 | live tree, visual fixers done | the suites that had failed + `parse_all` | 91 tests, 1 failed | only the override.cfg packaging test; pass 3 G5 made it read the shipped `res://project.godot` (R3-22) |
| 09:40 | live tree (pass 3 G1) | the suites behind the rules pass 3 documented: `parse_all`, `project_layer_names` (new), `camera_spawn_clearance`, `audit_release_packaging`, `enemies_lost_sight`, `mastery_landmark_discovery`, `flow_quit_prefetch`, `enemies_boss_pacing`, `boss_crossing_pacing`, `enemies_ch2_warden`, `boss_velour_qa_fixes`, `save_v2_chapter_log` | **97 tests, 0 failed, 15 s** | one ISOLATION note (`Game._bosses` from the Velour suite) |

Known red test at the end of pass 3: `test_enemies_review.test_boss_killing_blow_skips_the_window_cap_climb` ("expected gone got
climb", reproduced by G1, G4 and G5). The Weaver's in-progress fix for the late-window overshoot (below) now trims even a would-be
lethal blow to the window's room, as the pass-3 decision R3-10 records; that older test still expects a phase-1 killing blow larger
than the room to kill. The Weaver owner has to reconcile the test with the rule before the final full run. **A clean full-suite run
on the live tree is still to do** (R3-50) - the snapshot result is the latest full green run.

### 10.3 The 17 bugs: fix, regression tests, [bot] confirmation
Every fixer confirmed its new tests fail on the old code (old files swapped back in, then restored byte-identical). The [bot] column is
the verifier's re-run on the snapshot (S0 also on the live tree). Details: the fixer reports summarised in `docs/ch2/INTEGRATION_PASS3.md`.

| Bug | Sev | Fix (files) | Regression tests | [bot] confirmation | Status |
|---|---|---|---|---|---|
| CH2-001 | major | the lamp search joins step group "lamps"; `hint_when`; `ChapterLog.from_dict()` narrowing (`quests_ch2.gd`, `chapter_log.gd`) | `test_save_v2_chapter_log` ×3 (+1 updated), `test_ui_journal_tracker` ×1 (+2 updated) | S2: Garden and Quarry Seals + "Goal complete" the moment each lamp is lit; S3: Manor Seal right after its lamp | fixed |
| CH2-002 | major | `resource_node.gd` `_visual_id()`, `_settle_depleted()` safety net; `reach_vegetation.node_params()` | `test_world_nodes` ×3, `test_world_reach_area` ×1 | S2: two Reach trees felled, 0 SCRIPT ERRORs (was 10) | fixed (respawn after 1440 in-game min: unit test only) |
| CH2-003 | minor | Weaver: 15 % late window cap, threshold stop, banked scorch (`weaver_boss.gd`) | `test_enemies_boss_pacing` (10) | S0 ×4: fan, drop, release and channel all play before the win | fixed; the late-window overshoot the verifier saw (54 HP in a 36 HP window) was fixed afterwards in code with its own test - not re-run by the bot |
| CH2-004 | minor | Warden: `EXPOSE_CAP` 35 %, owed pulses, `PULSE_FLOOR_RATIO` (`quarry_warden.gd`) | `test_enemies_ch2_warden` ×5 | S2: the three pulses before defeat; the one exposure took 80.4 HP (cap 105) | fixed |
| CH2-005 | minor | Velour channels beside the candle and eases round the stand (`count_velour.gd`) | `test_boss_velour_qa_fixes` ×2 | S3 ×2: both phase-3 channels broken by a straight-on blow 0.8-1.7 s in | fixed |
| CH2-006 | minor | lost-sight give-up for ordinary enemies (`enemy_base.gd`) | `test_enemies_lost_sight` (4) | - (the bot killed the hall's Velvet Wing) | fixed, unit-tested only (real-play check open) |
| CH2-007 | minor | Crossing: engagement rule, floors 60/35/20 %, clamped scorch, 3 s retreat run (`crossing_matron.gd`, `crossing_rules.gd`) | `test_boss_crossing_pacing` ×2, `_fight` ×3, `_rules` ×1 + 4 updated | S4: one exposure per phase; pounce, delayed pounce and release all faced | fixed |
| CH2-008 | polish | no combat state under a boss context; the boss's engagement grace cleared (`music_selector.gd`, `music_director.gd`) | `test_audio_music_selector` ×2, `test_audio_music_director` ×1 | S0, S3, S4: boss cue → silence / area music, never m10 / m22 | fixed |
| CH2-009 | polish | opening the wardrobe retires the notice (`wardrobe_panel.gd`) | `test_ui_appearance_wardrobe` ×1 | S1: `notice_shown` true | fixed |
| CH2-010 | polish | helper zones; legacy landmarks marked seen (`game.gd`, `annexes.gd`, `mastery.gd`, `data/mastery.gd`) | `test_mastery_landmark_discovery` (5) | S1: `discovered.surface` = haven, ruin; Wayfinding 105 XP (rank 2 = 110) | fixed |
| CH2-011 | polish | `Game.release_prefetches()` on quit / window close (`game.gd`) | `test_flow_quit_prefetch` (3) | S1: still "8 ObjectDB instances were leaked" (`s1/vfix1`), 3 in the `--verbose` probe (`s1/vfix_verbose`: bare RefCounted, refcount 0) | **partly fixed**: our leak source is gone (old quit 15, fixed quit 7-8); the rest is engine-internal, developer logs only - accepted (R3-16, KNOWN_ISSUES) |
| CH2-012 | polish | the search step renamed "Find the Three Lamps" (`quests_ch2.gd`) | `test_save_v2_chapter_log` ×1 | S2: only the group title is announced | fixed |
| CH2-013 | polish | Velour's cap applied before the blow (`velour_health.window_room`) | `test_boss_velour_qa_fixes` ×4 | S3: no window over the 60.8 HP cap (largest exactly 60.8) | fixed |
| CH2-014 | polish | Choir anchors switched off for phase B (`borrowed_choir.gd`) | `test_boss_choir_anchors` (3) | S4: 0 anchor prompts in phase B (38 and 152 samples in the old runs) | fixed |
| CH2-015 | polish | crossing hint wording (`quests_ch2.gd`) | `test_save_v2_chapter_log` ×1 | S4: "A checkpoint lantern waits just before the bridge." | fixed |
| CH2-016 | polish | post-Choir hint names the vault's bell-lift (`quests_ch2.gd`) | `test_save_v2_chapter_log` ×1 | S4 | fixed |
| CH2-017 | polish | vault exit caption follows the clock (`choir_arena.gd`) | `test_works_deep_vault_exit` ×1 | S4: "[the bell-lift climbs toward the daylight]" at 11:40 | fixed |

**[bot] runs after the fixes** (`qa/tmp/bot/`; every run 0 deaths, 0 SCRIPT ERRORs, no problems filed):

| Segment | Start | Run folder(s) | Result |
|---|---|---|---|
| S0 (Weaver Matron) | diagnostic fixture at the arena lantern | `s0/vfix_fast`, `s0/vfix_thorough` (live tree), `s0/vfix_snap_fast`, `s0/vfix_snap_thorough` (snapshot) | won ×4, phases 1-2-3 seen every time, lowest HP 93-100 |
| S1 (continuation) | natural: a copy of the real v1 Chapter-One-complete save | `s1/vfix1`, `s1/vfix_verbose` | completes (74-76 s), save diff fully explained by play, CH2-011 warning as above |
| S2 (orchard, quarry) | diagnostic fixture | `s2/vfix1` | completes, 232.7 s, both seals, Warden with pulses |
| S3 (manor, Velour) | diagnostic fixture / the ballroom save | `s3/vfix_run`, `s3/vfix_boss` | completes, 196.5 s / 140.7 s |
| S4 (Works, finale) | diagnostic fixture | `s4/vfix_full` | completes, 747.8 s (was 647.3 s), relaunch shows 20/20 steps, no double rewards (`s4/vfix1` is invalid: player.gd did not compile mid-edit, the run was killed) |

**Fight durations** ([bot] time; all phases now play):

| Fight | Before | After |
|---|---|---|
| Weaver Matron, fast style (intro → defeat) | 19.8-22.8 s, braziers only | 44.6-47 s (53.6-56 s bot time) |
| Weaver Matron, thorough style | 65.9 s | 64.3-71.3 s |
| Quarry Warden | 24.9 s, pulses skipped | 40.2 s |
| Count Velour | 70.2 s / 106.3 s | 78.0 s / 78.7 s |
| Crossing Matron | 21.7-22.5 s, no attack faced | ~65 s (70.0 s route step) |
| Borrowed Choir (not retuned) | 229.8 s | 301.3 s (the bot guessing in phase A) |

These are bot times with perfect route knowledge; the design targets (2-4 min for the Chapter Two bosses, "a few minutes" for the
Matron) are about a first human attempt, which is untested. The fixers' headless simulations are in their reports (Crossing rusher 43 s,
reactive 57 s at Standard; Weaver rush 40 s, thorough 53-55 s; Velour 62-96 s by gear and intensity).

### 10.4 Visual fixes — [visual] stills
Each group re-rendered its fixes on the second monitor and looked at the frames; each added a numeric regression suite. **Everything
in this table was only rendered as still frames** (plus unit tests): nothing was judged in motion, in a real play session, or by a
human. The in-motion checks are listed in KNOWN_ISSUES (R3-49).

| Group | Findings | Fixed | Partly / left for other files | Before | After (pairs) | Tests |
|---|---|---|---|---|---|---|
| Avatar | 20 (AV-00..19) | 14 | 6 partly: AV-11 skirts (sprint slits, knees when sitting), AV-12 (paper lantern pack), AV-13 / 14 / 15 (need palette data → done in pass 3 G6, rendered `qa/tmp/visual/pass3_g6/`), AV-19 late-roll hover | `qa/tmp/visual/avatar/sheets/` | `qa/tmp/visual/fix_avatar/sheets/` (`BA_*` side-by-side) | `test_avatar_look_fit` (10) |
| Building | 15 (BU-00..14) | 15 | - (the real Haven cottage built through BuildMode: 59 of 61 pieces; the 2 refusals are the plan's own conflict and the new wall rule) | `qa/tmp/visual/building/shots/` | `qa/tmp/visual/fix_building/` | `test_building_visual_fit` (11) |
| Cameras (theme T1) | 8 (RE-00, RE-01, IN-00, IN-01, IN-03..06) + RE-07 | 7 + RE-07 | RE-00 Woods side → done in pass 3 G2 (R3-32), plus a new find, Tobin's `annex_door` arrival (R3-33); both rendered by G2 | `qa/tmp/visual/reach/`, `qa/tmp/visual/interiors/` | `qa/tmp/visual/fix_cameras/compare/`, `fix_cameras/after_*/` | `test_camera_spawn_clearance` (7): view covered within 2 m of the lens, before → after: arches 10-12 % → 0, Reach arrival 78 % → 0, annex lantern 16 % → 0, lift landing 58 % → 0, `vault_exit` 32 % → 0, trials 75-100 % → 0 |
| Creatures | 16 (CR-00..15) | 12 | CR-03 partly; CR-05, CR-14 in files outside the group → all three done in pass 3 G4 (rendered `qa/tmp/visual/pass3_g4/`); CR-12 covered by IN-07 | `qa/tmp/visual/creatures/`, `fix_creatures/before_*` | `qa/tmp/visual/fix_creatures/after_*`, `w_*` | `test_creatures_visual_fixes` (12, 15 after G4) |
| Interiors | 12 own (IN-02, IN-06..16) | 11 | IN-09 and the HUD half of IN-13 are UI work (IN-09: the UI agent's HUD hush, unconfirmed; IN-13 dial deferred, R3-43); the follow-ups were done in pass 3 G3 - each lift fits its own sign, a winch-hall rock no longer cuts the crossing-gate sign's top line from the arrival camera, resonator plates show no prompt while disabled, the Choir trial board's Moon is a crescent (rendered `qa/tmp/visual/pass3_g3/`) | `qa/tmp/visual/interiors/` | `qa/tmp/visual/fix_interiors/compare/` | `test_works_interior_visuals` (7), `test_manor_layout` (+1) |
| Reach | 18 (RE-02..19) | 18 (RE-07 by the cameras group) | - | `qa/tmp/visual/reach/` | `qa/tmp/visual/fix_reach/_cmp_misc.png`, `_cmp_c1x.png`, `shots/fix3/_cmp_basin.png`, `shots/final/` | `test_reach_visual_fixes` (17) |
| UI | 23 (UI-00..22) | ? | still being fixed when pass 3 closed; no report yet | `qa/tmp/visual/ui/` | - | - |

Pass-3 re-check by G1 (the docs group), [visual]: `qa/tmp/visual/g1_pass3/crown_helm_recheck.png` - no hair shows through any helm
or hood (AV-02 confirmed, its KNOWN_ISSUES note removed); `armor_hem_recheck.png` - jacket / cardigan buttons and plain hems are covered
under body armor (AV-04), but the Cloud Cardigan's fluffy cloud hem and the Velvet Ruffle Bodice's white collar still show round every
body armor set (kept in KNOWN_ISSUES).

### 10.5 Integration pass 3
The fixers' requests for files outside their groups, the design decisions (CH2-010 legacy landmarks, CH2-006 lost sight, CH2-011
engine leak, Velour's finishing blow) and every group's outcome are in `docs/ch2/INTEGRATION_PASS3.md` (51 requests). Each group
re-checked the code, added regression tests that fail on the old code, ran its related suites and rendered its visible changes:

| Group | Requests | Outcome | [auto] | [visual] |
|---|---|---|---|---|
| G2 surface arrival spawns | R3-32, R3-33 | Woods waygate spawn 5.8 m out; Tobin's `annex_door` spawn moved to (6.8, 7.8) (7.4 still left 8 % of the view on the lintel) | 22 + 81 + 69 tests, 0 failed; `parse_all` 0 failed | both arrivals rendered: clean third-person frames |
| G3 Works deep interiors | R3-19, R3-35, R3-41, R3-42 | resonator prompts, crossing-gate sign (cause: a winch-hall rock, dressing RNG kept), lift signs, trial board crescent | 237 tests, 0 failed | `qa/tmp/visual/pass3_g3/` (before / after of the gate sign) |
| G4 boss creature props | R3-36..38 (R3-39 skipped: would override the comfort setting) | trip posts, Crossing scar and mantle, Choir paper lanterns | 144 tests 0 failed; 203 tests 1 failed (the red test below) | `qa/tmp/visual/pass3_g4/` (both arachnophobia looks) |
| G5 combat feedback, text, tests | R3-06, R3-08, R3-09, R3-22 | Crossing desc "three times", one glance spark for a player swing blocked by scenery, `win_velour` robust, packaging test reads `project.godot` | combat_core 16, data_ch2_catalogue 19, trials 31, velour 68, boss_ 230: 0 failed; `enemies_` 317, 1 failed (the red test below) | a preview scene: one spark cluster on the wall's near face |
| G6 appearance palettes | R3-26..28, R3-30 (R3-29 skipped) | Ghostlight Party, Pumpkin Patch, mushroom beret, chorister capelet channels | avatar / appearance suites 0 failed (one UI wardrobe-preview failure from the in-progress UI fix; it passes again at 09:48) | `qa/tmp/visual/pass3_g6/` |
| G1 docs, layer name | R3-04, 05, 10, 12, 16, 17, 18, 31, 34, 48, 51 | this section, KNOWN_ISSUES, PROJECT_STATE, the code maps, ARCHITECTURE, `project.godot` layer 10 "camera" | new `test_project_layer_names` (2); related suites 97, 0 failed | `qa/tmp/visual/g1_pass3/` (10.4) |

Still open after it: the
clean full-suite run on the live tree (R3-50), the real-play checks (R3-49), the UI group's visual fixes and its deferred tracker /
day-dial items (R3-03, R3-43), the `.uid` import (R3-47), removing `game/override.cfg` after the QA runs (R3-23) and the S4 bot's dodge
near braziers (R3-07) - also listed in `PROJECT_STATE.md`.
