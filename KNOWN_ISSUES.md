# Known issues — Hollowhaven 2.0.2 (Chapter One + Chapter Two)

Honest list of what is imperfect or unverified in the 2.0.2 release (`dist/Hollowhaven-2.0.2-Windows.zip`, git `991014c`).
Severity is **minor** unless stated. No crash, save corruption or progression blocker is known to be open - but Chapter Two has
**not been played by a human**, so that statement rests on automated tests, QA-bot runs with virtual input (headless, and visible on
the second monitor) and still frames only (`QA_REPORT.md` §9, §11, §12). Fixed bugs are not listed here, except the short lists
below; the details are in `QA_REPORT.md` §9.6, §11 and §12.

## Fixed in 2.0.2
* **Boss-fight tips lagged behind the fight or outlived it** (seen in 2.0.1: the Weaver's "It is smothering a brazier!" tip over the
  Chapter One ending, Run B `play_038_ending.png`; a burst of Crossing Matron tips queued past her defeat in Run A). A newer fight
  tip now replaces an older queued one, the tip on screen makes room after 4 s, and the end of the encounter drops all fight tips
  (`hint_card.gd`, `a31e717`; 7 new unit tests, full suite 2679 / 0). On screen in the packaged 2.0.2 build (V1,
  `qa/evidence/ch2_v2.0.2/v1_fresh/play_039_ending.jpg`): no stale Weaver tip after the Chapter One ending. The Crossing / Choir
  cases were only run headless (V2), not seen on screen.

## Fixed in 2.0.1 (open or unnoticed in 2.0.0)
Checked by new unit / regression tests in the full suite (2672 tests, 0 failed) and, where noted, by bot runs; none by a human.
* **CHAIN-001** Quarry Warden frozen at its arena edge: it now fights only on its arena floor, never attacks across levels, and gives
  up + resets cleanly 5 s after Krystal leaves that level (not reproduced in the bot runs since; the 5 s give-up itself is unit-tested only).
* **CHAIN-002** Warden beatable without the pillars: until its first pillar exposure (while a pillar stands) blows stop at 50 % health
  (bot fights since: 2-3 exposures every time).
* **COV-001** Arriving on a lit checkpoint through its own entrance (Works refuge hatch, Bellhouse stair) makes it the return point,
  and Return to safety prefers the safe point of the room Krystal stands in (e.g. the manor cloakroom) instead of a rest point far
  away. A defeat after entering by the manor's front door still wakes her at the last rest candle (by design).
* **COV-002** A companion's hit no longer flinches an ordinary enemy out of its tell (Tobin's Hollow Drudge shows both tells).
* **COV-003** Entering an Echo Trial is no longer a map landmark discovery (no Wayfinding XP / bond from inside the echo).
* **COV-004** Arachnophobia: the Weaver's "banked scorch" and trip-line hints now use the comfort wording (also when toggled mid-fight).
* **COV-005** "A House With an Upstairs": the walk-upstairs objective needs the walk, not just the floor tile.
* **COV-006** Plurals in the furnace prompt / toast ("Collect 3 Copper Bars").
* **COV-007** Sparkseed Wand: a cast cancelled by a hit during its wind-up refunds its stamina and cooldown.
* **R3-03** The HUD tracker drops the three "Find the ... lamp" rows once all lamps are found (journal and map keep them).
* Perf finding "Continue freezes the screen": a loading card (area name, lantern glow) and fade now show before an area builds.
* The zip's player docs and `Licenses/THIRD_PARTY_NOTICES.txt` are now the corrected ones (checked byte for byte against
  `docs/player/` and `THIRD_PARTY_NOTICES.md`).

## 1. Not verified yet (read this first)
* **PERSONAL-SAVE VERIFICATION BLOCKED.** Krystal's own save is not on the development PC. Migration was verified on synthetic
  fixtures and on saves the real v0.9.0 game wrote during QA-bot runs (`docs/ch2/SAVE_INTEGRITY_REPORT.md`), never on hers. Run the
  gate in that report (§7) on a copy of her save before calling it safe for her world.
* **No human has played Chapter Two** (nor the enriched Chapter One): fun, difficulty, pacing, first-time playtime and whether the
  hints are enough are unknown. The QA bot knows the route and reads telemetry; its times are not human times.
* **No OS-level real-input run of 2.0.x.** Every Chapter Two bot run injected input through the game's QA port (bypasses Windows
  focus, raw input and cursor capture), headless or in a never-focused window on the second monitor. Keyboard / mouse feel, camera
  responsiveness and focus problems are untested for Chapter Two.
* **Nobody has listened** to the 22 new compositions, their layers, the Music Box, any Chapter Two sound, or any in-game mix. All
  audio was checked by numbers only (`docs/ch2/MUSIC_MANIFEST.md`). The Chapter One audio was not listened to either. (The visible
  bot runs played with sound on; nobody listened.)
* **Nothing has been judged in motion.** The 110 visual findings were found and their fixes checked on rendered STILL frames; the
  visible bot runs also left only screenshots.
* **Performance** was measured only on the development PC (RTX 4090): the packaged exe per area at High / Low 1080p and High
  720p, uncapped (`QA_REPORT.md` §9.8: 398-709 average FPS, loads 0.9-2.9 s). Minimum requirements are unknown; no weaker or
  integrated GPU was tried. Settings > Video > Graphics quality (Low / Medium) and Render scale help weaker GPUs; first launch picks
  Medium + 85 % on an integrated GPU. Lantern Road round trips keep node / object counts flat, but process memory still rises:
  9.9-15.7 MB per Reach <-> Haven cycle in the 3-cycle runs, 8.5 MB per cycle over 10 cycles (harness verdict "slow growth",
  `qa/evidence/ch2_v2.0.0/perf/leak10_summary.md`); a long session was not measured. All of this was the **2.0.0** exe; 2.0.1
  (loading card, Continue prefetch) and 2.0.2 were not re-profiled.
* **Packaged-build runs are bot runs.** The packaged exe has now been driven end to end, always with virtual input: 2.0.0 - a
  visible natural Chapter Two chain on the second monitor (1488 s, completes); 2.0.1 - Run B, a fresh New Game through Chapter One,
  the ending and accepting Chapter Two, visible with sound (21/21 steps, 658 s), and Run A, the natural Chapter Two chain, headless
  (completes: 20/20 steps + relaunch, 1534.8 s, 0 deaths, 0 script errors) (`QA_REPORT.md` §11). On 2.0.1 no Chapter Two area was
  rendered by any run (Run A is headless). 2.0.2 - V1, a fresh New Game, visible with sound (21/21 steps,
  697 s, 0 script errors, ribbon tied), and V2, the Chapter Two finale resumed from Run A's `T34_end` save, headless (completes,
  900.7 s, relaunch + Continue with the same items) (`QA_REPORT.md` §12.4). No 2.0.2 run rendered a Chapter Two area (V1 stops at
  accepting Chapter Two in the Haven).

## 2. Open bugs in 2.0.2
The lingering boss-fight tips (2.0.2), CHAIN-001 / 002 and COV-001..007 (2.0.1) are fixed (lists above). Still open:
* **CHAIN-003 = CH2-011 = COV-008 (developer logs only)**: quitting prints "WARNING: N ObjectDB instances were leaked at exit"
  (N 3-9 in the chain runs, 8-24 in the coverage runs; 8 at the end of the 2.0.1 and 2.0.2 suites); 3 coverage-run exits also logged
  "ERROR: N resources still in use at exit" (N 1, 2, 7; `qa/tmp/bot/COVERAGE_BUGS.md`). See §6.

## 3. Open work and small player-visible gaps
* **Shared creature voices (D10).** Every Chapter Two enemy and boss (and the Chapter One additions) uses existing, test-verified
  sound names: safe, arachnophobia swaps work, but many creatures share voices. Planned as ONE audio pass (new `tools/audio` sfx +
  Audio aliases, arachnophobia variants for the Crossing) followed by a human listening check; the requested voice list is in
  `docs/ch2/INTEGRATION_WAVE_D.md` §2 (D10).
* The interaction prompt can trail the real target by up to ~160 ms when two targets cross (the HUD label refreshes every 0.08 s;
  E always acts on the freshly re-scored target), e.g. "Talk to Mochi" still showing while E opens Lumi's panel. Minor, not
  changed. (The case in 2.0.1 Run B was a bot race - it acted on a telemetry frame 100-200 ms old - not a game bug; `QA_REPORT.md` §12.3.)
* The HUD day dial shows a day sky inside Moonveil Manor, where it is always night (R3-43; the balcony backdrop half of IN-13 was fixed).
* Onboarding tip pacing (2.5 s calm, 25 s between tips, 30 s after a horror moment) is untuned: a Chapter One save can see about
  five tips in its first minutes (P50).
* The Bell Throat echo stone stands at (153.6, -28, 27.6) next to the checkpoint; if the wall rocks touch it on screen it should move
  to about (153.4, -28, 24.75) (L10, not checked on screen).
* The optional fourth friend Pipkin (a stretch goal in the design) is not implemented.
* Developer-only: the test runner's isolation guard still repairs leftovers on every full run (21 `ISOLATION` lines in the 2.0.0,
  2.0.1 and 2.0.2 final runs: stray projectiles / particles, `Game._bosses`, zone flags, Reach world items; F04). No test fails because of it.

## 4. Avatar clipping limits (reviewed and kept)
Checked on still frames only (`qa/tmp/visual/fix_avatar/sheets/`, `qa/tmp/visual/g1_pass3/`):
* Late in the dodge roll the tucked body still hovers briefly (AV-19; the Chapter One roll motion is pinned by the legacy motion
  test). The witch hat folds to 45 % while rolling, but the roll pivot lifts 0.457 m (no hat), 0.545 m (sun hat), 0.481 m (witch
  hat), so a tall hat can make her look as if she floats.
* Skirts open as one piece when running and bunch in a roll (AV-11), but small slits show at full sprint (no underskirt) and the
  knees show through skirts in the sleep / sit pose; whether a long skirt dips into the ground mid-roll was not re-measured.
* Long hair drapes over bulky back items, but still touches the paper lantern pack slightly (AV-12, drape capped at 0.5 rad), and
  long hair can pass through the shoulders when she turns her head (as the Chapter One braid does).
* The belt lantern and satchel can cut into flared skirts.
* Under show-armor body pieces, jacket / cardigan buttons, pockets and plain hems are covered (AV-04), but the Cloud Cardigan's fluffy
  cloud hem and the Velvet Ruffle Bodice's white collar still show round every body armor set (`g1_pass3/armor_hem_recheck.png`).
  Hair no longer shows through helms or hoods (AV-02, `g1_pass3/crown_helm_recheck.png`).

## 5. Kept by design (Chapter Two)
* Fight pacing rules from bug-fix round 1: the Quarry Warden takes at most 35 % per pillar exposure and always plays its three
  pulses first in phase 2 (2.0.1, CHAIN-002: blows stop at 50 % until its first pillar exposure); the Crossing Matron takes three exposures, one per phase, and a brazier lit before she
  has attacked only "primes" her anchor (her next pounce exposes her) - without a Lantern her HP floor is off so blows alone can
  finish her; the Weaver Matron needs at least two openings in each of phases 2 and 3, and a scorch before a phase's first action is
  banked until that action ends. A blow that would finish the Weaver in her last phase or Count Velour now always lands (their window
  caps never trim a finishing blow); the Quarry Warden still trims any blow, a finishing one included, to what is left of its
  exposure cap.
* Ordinary enemies give up a hunt after 5 s without seeing Krystal (sight or a hit resets it) and walk home, so they stop blocking
  saves and travel; elites and bosses never give up this way (R3-18). A Continued Chapter One save gets no discovery XP for Chapter
  One landmarks it already proves visited - the one-time legacy credit stands in for them (R3-17).
* The Quarry Warden is an elite and gets the ordinary combat music; only the Velvet Wing feints among ordinary enemies; some
  ordinary tells are longer than 1.4 s; a veiled wisp can still make its marked, delayed sweep; the Choir can be beaten without
  striking it (exposures end the fight) and without a lantern its fight cannot progress (she can always leave); friends' blows while
  Count Velour channels also lift his mask floor; the Crossing Matron can release two Brood Skitters that leap 0.85 s apart (never
  together with a pounce); a raised lantern anchor cannot be re-raised to refresh it.
* Echo Trials open as soon as their boss is defeated (the flag `ch2_trials_open` gates nothing); Count Velour's memory starts with
  all three candles lit.
* A gameplay hotkey pressed in the wardrobe opened over the pause menu opens that panel with pause still underneath (tested not to
  softlock).
* The furnace queue does not advance while its (full-screen) crafting panel is open; furnace jobs from a newer game version are
  kept but not refunded when the furnace is dismantled.
* A full backpack shows both a panel line and a toast; a velvet scrap shows both "Obtained" and "Velvet scrap found (n of 3)".
* Companions: only Mochi reacts to horror cues; Lumi's night lamp visit only finds lamps that are both light sources and structures;
  the gear-tier damage bonus counts weapons in the backpack, not in chests; a pet that falls during a boss fight and never stood on a
  floor while following is not recovered (very rare); Brave Little Steps needs the Loom (Tailor's Cache) first.
* Map: Krystal's and friends' markers can overlap place names (as on the Chapter One map).
* Legacy sweetroot crops are over the newer per-plot triangle budget (unchanged Chapter One shapes).
* The Intense turning pumpkin turns while watched from 16 m or more (distant, silent and slow).
* Music Box: with the Music volume muted nothing new is discovered and a started song keeps saying "Now playing" until Stop or
  leaving the house; a preview ended by a fight is not resumed; playing the piece already on continues it; favourites can bring any
  heard calm piece (e.g. the mine's "The Last Shift") into the Haven rotation, at most two extra per round.
* Expeditions: setting a run aside mid-fight (only possible from the Commons outpost board) makes the group vanish; a dye keepsake
  unlocks the Loom colour directly, without its crafting cost.

## 6. Developer-log leak note (CH2-011 / CHAIN-003 / COV-008)
Quitting can print "WARNING: N ObjectDB instances were leaked at exit" (N varies, 3-9 in the chain runs, up to 24 in the coverage
runs; also at the end of the full test suite: 8 in the 2.0.1 and 2.0.2 runs). Three coverage-run exits also printed "ERROR: N resources still in
use at exit" (N 1, 2, 7), one of them from the title screen with no gameplay; their owners were not identified (no `--verbose` re-run
yet, `qa/tmp/bot/COVERAGE_BUGS.md` COV-008).
Our own source - background loads never claimed at quit - is fixed (`Game.release_prefetches()`, `test_flow_quit_prefetch.gd`); a
`--verbose` probe (`qa/tmp/bot/s1/vfix_verbose`) shows only bare RefCounted objects with a reference count of 0, from engine
background compiles and headless WAV playback. Accepted as engine-internal (decision R3-16; that probe predates the ERROR lines,
which are not yet explained). No player-visible effect; revisit if a Godot update changes it.

## 7. Still to check with real play (keyboard / mouse, on screen)
Commands for the debug views are in `AGENTS.md`; the list is what no human or OS-level run has exercised yet.
* **Controls and panels:** wardrobe grid (arrows / Enter, drag to turn, typing a preset name, every Esc path), the O key (also over
  the pause menu), rebinding Z / P / N and the hints naming the new key, dragging onto equipment slots, map toggle, Q/E journal tabs,
  scroll wheels, mouse capture after Continue.
* **Companions:** the T key (with UI focused, after rebinding, with no follower); navigation in real Below / Works corridors, on
  stairs, upper floors, the quarry gangway and the brook (the local path search is unit-tested only; changing storey relies on the
  4 s stuck recovery).
* **Building:** walking stairs to an upper floor, Continue while upstairs, a bed upstairs.
* **Fights (human first attempts vs the design targets):** Quarry Warden (incl. the 2.0.1 CHAIN-001 / 002 rules: leaving its
  level, the 50 % shell floor), Count Velour (target 2-4 min; bot
  78 s), Weaver Matron after CH2-003 (bot 45-71 s), Crossing Matron (~2-4 min target; bot ~65 s), Borrowed Choir (4-6 min target;
  bot 229-301 s); Brambleback / Elder charges, moth rest window, Drudge in the narrow hall, mimic pocket, Patchwalker, Bellcaps,
  Velvet Wing drain rule, wisp dazzle; every ground telegraph with the new dark contrast band on grass, stone and the ballroom floor.
* **Bug-fix checks that need real play (R3-49):** an ordinary enemy losing Krystal behind a wall and saving right after (CH2-006,
  unit-tested only); a Reach tree respawning after 1440 in-game minutes (unit-tested only); the Chapter One Hollow Mother's new edge
  light.
* **Echo Trials:** a full Velour and Choir trial each (win, fall, leave by the pale door, Continue from inside), the repeat-clear gift
  paid at the stone with a full backpack, a first-clear pattern sewn at the Loom and worn.
* **Expeditions:** one full route of each, the Lantern Road hop, spawns never in view, a fall mid-route, save / quit mid-run and resume.
* **Places:** Bellhouse stair and the Foreman's Key gate, the annex stair, ladders, winch cage and Bell Throat dialogs, the servants'
  stair, Continue from manor / Works checkpoints, celebration and ending skips.
* **Comfort:** arachnophobia enabled before loading through the Matron, her trial and the Crossing; muted-audio puzzles; caption
  readability; onboarding pacing (tips never during fights, trials or horror moments).
* **In motion (visual):** avatar clothes / hair / hats / armor while moving, skirt and cape sway, the Reach and Candleyard lighting
  by day and night, boss tells (Velour's dash lane on the crimson rug, the Crossing's rings with sound muted, the Choir's genuine vs
  false tells), both ending screens, menus at 1080p and 720p on the packaged build.

## 8. Chapter One (still true in 2.0.2)
### Gameplay / feel
* No navmesh: companions follow breadcrumbs, use a small local path search around walls (added for Chapter Two) and whisker
  steering, with stuck detection that safely teleports a companion back beside Krystal; enemies steer directly. On tricky terrain they
  may briefly bump into things before recovering.
* The Weaver Matron's HP and lit braziers reset if you quit to the title mid-fight (dying keeps the lit braziers within the same session).
* Lighting a brazier is "press E, then a 1.5 s kindle" rather than a held button; walking away cancels it.
* If the camera is swung hard into a wall or corner, it pulls in close and hides Krystal until you turn.
* Pebble's boulder doesn't remember partial hits across a save/load (a few extra swings at most).
* Feeding a companion that has already eaten today keeps the food ("still full") instead of consuming it.
* The wall-placement rule that prevents shutting Krystal in only considers built pieces, not trees or rocks at the edge of the build
  area. Pause → "Return to the Haven" always gets you out.
* Sleeping in a bed works at any hour and skips to the next morning (which also ripens crops).
* Nothing stops Krystal from running the dungeon early. If the Heartseed goes back before the surface goals are done, the dungeon
  goals are skipped and the Haven Banner arrives once the remaining surface goals (e.g. befriending Lumi) are finished.
* Closing the window saves in the woods and the Reach (like Pause > Save). Underground it doesn't: Continue starts at the last
  lantern save. In the manor, the Hushed Works and Tobin's annex it saves only while Krystal stands somewhere safe; Echo Trials are
  never saved.

### Interface
* Moving items in the backpack/chest needs the mouse (menus themselves work with the keyboard). No gamepad support.
* Toasts already on screen keep their old wording if Arachnophobia mode is toggled while they are visible.
* The title-screen Credits card needs a little scrolling at 1080p (the ending credits scroll automatically).
* Emote bubbles above companions are hidden behind walls (deliberate, to avoid see-through bubbles).
* Keeping a debug/QA run windowed requires the user argument `-- --windowed` (engine flags are not visible to the game). Normal
  players are unaffected (Settings → Video → Fullscreen toggles it).

### Visual
* The Ward Stone's moss blobs look a little flat up close; the sign lettering is soft in bright daylight.
* Grass is hidden under built floors with a soft-edged mask, so a few blades can poke 0.3-0.5 m into the edge of a structure.
* The `energy` argument of the shared "glow" material has no visible effect (unshaded materials ignore it); affected glows were
  tuned by eye, so this is cosmetic only.
