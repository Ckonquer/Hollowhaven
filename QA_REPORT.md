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
Result at v0.9.0: **653 tests, 0 failed, 300 s** (`qa/evidence/test_results_v0.9.0.json`).

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
  return the Heartseed → restoration cutscene, "Chapter One Complete", credits → free play → save from the
  pause menu.
* Observed in the run (from the game's own events): the authored moments fired in order — THE THRESHOLD
  ("timbers creak…" + Lumi noticing), THE DISTANT CROSSING ("something skitters past the far doorway"),
  THE IMITATION ("a familiar chime… played backwards", "[Lumi whimpers]"), SILK HOLLOWS INTRO ("it slips away
  into the dark above" / "It shrinks from your light"), boss braziers, the Weaver's retreat, the lift, the
  Ward Stone restoration. 0 deaths, lowest health 36/100. 6 autosaves/lantern saves + 1 manual save.
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
