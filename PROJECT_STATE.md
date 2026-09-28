# Project state — Hollowhaven (Chapter One: The Dimming Ward · Chapter Two: The Lanterns of Hallowmere)

_Last updated: 2026-09-28 (Chapter One released as v0.9.0 / v0.9.1; Chapter Two fully built, integration passes 1-2 applied,
bug-fix round 1 (CH2-001..017) and the visual fixes done, integration pass 3 applied; not yet packaged as a new release)._

## Where things are
* Playable build: `builds/Hollowhaven/Hollowhaven.exe` (+ `How to Play.txt`, `Chapter Two - What's New.txt` from the next
  build on, `Licenses/`) · ZIP: `dist/Hollowhaven-<version>-Windows.zip`
* Source: `game/` (Godot 4.7.2 project) · tools: `tools/` · docs: `GAME_SPEC.md`, `docs/ARCHITECTURE.md`, `AGENTS.md`
* Evidence: `QA_REPORT.md`, `qa/evidence/` · issues: `KNOWN_ISSUES.md` · provenance: `THIRD_PARTY_NOTICES.md`
* Chapter Two: contract `docs/CHAPTER_TWO_SPEC.md` · save schema v2 `docs/SAVE_MIGRATION.md` · module ownership
  `docs/ch2/WAVES.md` · code maps `docs/ch2/maps/*.md` · decisions `docs/ch2/INTEGRATION_WAVE_BC.md` (pass 1),
  `docs/ch2/INTEGRATION_WAVE_D.md` (pass 2) and `docs/ch2/INTEGRATION_PASS3.md` (pass 3) · bot bug list
  `qa/tmp/bot/BUGS_MERGED.md` · visual findings `qa/tmp/visual/VISUAL_BUGS_MERGED.md` · player note
  `docs/player/Chapter Two - What's New.txt`

## Completed
* Toolchain: project-local Godot 4.7.2 (+ Windows export templates), Python venv for audio; reproducible
  via `tools/setup_toolchain.ps1`. Unity not used (Personal licence activation requires the owner's Hub sign-in).
* Foundation: autoloads (Events, Settings, ItemDB, GameState, SaveSystem, Audio, Game, Debug), data files,
  art kit (toon shader, outlines, palette, procedural meshes), test runner (fails on runtime script errors),
  debug/QA harness, QA telemetry for the external real-input bot.
* Modules (each built, then independently reviewed): player & camera, crafting/building/farming,
  UI (title, HUD, all panels, comfort, ending), companions (Mochi, Pebble, Lumi), combat & enemies
  (Brambling, Gloomling, Weaver stalker, Weaver Matron boss, braziers, arachnophobia "Hollow Shade"),
  surface world (terrain, water, day/night, landmarks, resources, restoration), The Below (11 spaces,
  authored moments, checkpoints, lore), horror director, audio (154 original synthesised sounds + music),
  core QA.
* Integration + playtest fixes (see git log): bed respawn after the mine, companion focus priority,
  office lighting, desk key spacing, companion line pacing, etc.
* **Chapter Two** (each module built, then independently reviewed; see `docs/ch2/WAVES.md`):
  * Wave A: save schema v2 + migration + upgrade backup, the Chapter Two quest layer, optional goals, reward ledger, data
    catalogue, new areas and travel (waygate, Lantern Road), the music director and 22 new compositions.
  * Wave B: avatar looks and the wardrobe, equipment / stats / wand, companion combat, crafting stations and masteries, two-storey
    building and Halloween decor, Chapter One extras, new Chapter One enemies, the three-phase Matron and the first Echo Trial,
    Tobin's annex, journal / map / tracker.
  * Wave C: Hallowmere Reach (Commons, Conservatory, Orchard, Pools, Candleyard, Quarry, Manor grounds, Bellhouse), Moonveil Manor,
    the Hushed Works (14 rooms), the Chapter Two ordinary enemies and the Quarry Warden, the bosses Count Velour, the Crossing
    Matron and the Borrowed Choir, the Chapter Two story and ending.
  * Wave D: Echo Trials for Count Velour and the Borrowed Choir, Lanternwake Expeditions, the Music Box, onboarding tips and the
    player update note.
  * Integration pass 1 (after Waves B/C, 110 requests) and pass 2 (after Wave D, 76 requests: every lead decision, the pass-1
    deferred list, the new panels and hotkeys, session wiring, trial patterns and gifts, boss arena fixes, docs).
  * QA-bot route segments S0-S4 (headless, virtual input) found 17 bugs; bug-fix round 1 fixed 16 and partly fixed CH2-011 (an
    engine-internal leak warning in developer logs, accepted). Six still-frame visual reviews found 110 findings; the avatar,
    building, camera, creature, interior and Reach fixers fixed most of them (the UI group was still at work when pass 3 closed).
    Integration pass 3 (51 requests) applied their cross-group requests and decisions. Evidence: `QA_REPORT.md` §10.

## Automated tests
`tools/test.sh` — 653 tests, 0 failures at v0.9.0 (headless, ~5 min). With Chapter Two: 2407 tests, 0 failed after integration
pass 1 (headless, 15-25 min; `QA_REPORT.md` §9.1); after bug-fix round 1, 2534 tests, 0 failed on a snapshot (git HEAD + the bug-fix
files; `QA_REPORT.md` §10.2). A clean full run on the live tree after the visual fixes and pass 3 is still to do, and one known red
test must be reconciled first (`test_enemies_review.test_boss_killing_blow_skips_the_window_cap_climb`, see Next steps). Chapter Two
has been driven by the headless QA bot and looked at as rendered still frames, but NOT played by a human, with OS-level input, in
motion on screen, or listened to (`KNOWN_ISSUES.md`, Chapter Two section).

## Next steps
0. Finish pass 3 (deferred items, `docs/ch2/INTEGRATION_PASS3.md`):
   * Reconcile `test_enemies_review.test_boss_killing_blow_skips_the_window_cap_climb` with the Weaver's new rule (a would-be lethal
     blow is trimmed to the window's room, decision R3-10) - the owner of `weaver_boss.gd`; then one clean full-suite run on the live
     tree with `parse_all` and the packaging test with `game/override.cfg` present (R3-50).
   * UI owner: the UI visual findings (UI-00..UI-22, in progress), the lamp-stage tracker card showing up to 8 rows (drop the lamp
     search rows once that step is done, R3-03), the day dial's moon face inside Moonveil Manor (R3-43), and confirm the HUD hush
     that covers IN-09 (R3-44).
   * QA chain developer: remove `game/override.cfg` when the QA runs end and keep source-tree QA runs from leaving it in `game/`
     (R3-23); optional S4 bot polish - dodge a pounce while standing near a Crossing brazier (R3-07).
   * Release step: one editor `--import` for the missing `.uid` files (398 of 704 scripts, incl. every pass-3 addition; R3-47), alone,
     after the last code change and a green full suite.
   * Real play (human or a long bot session): an ordinary enemy losing Krystal behind a wall and saving right after (CH2-006), first
     attempts at the Crossing Matron (~2-4 min target) and the Weaver Matron, a Reach tree respawning after 1440 in-game minutes, the
     new telegraph contrast bands on grass / stone / the ballroom floor, the Chapter One Hollow Mother's edge light, the avatar limits in
     motion (R3-49).
1. Chapter Two release QA (Wave E): the visual, listening, real-input and performance checks listed in `KNOWN_ISSUES.md`
   (commands in `AGENTS.md`), a second-monitor QA-bot playthrough, then a release build (`tools/build_release.ps1`, which now
   ships `Chapter Two - What's New.txt` next to `How to Play.txt`).
2. The Krystal's-own-save gate before release (`docs/SAVE_MIGRATION.md` §9: copy, hash, migrate the copy, integrity report).
3. One dedicated audio pass for the new enemy and boss voices (D10), then a human listening pass on all audio.
4. Test on a weaker GPU; tune Settings "Quality" presets (tree MultiMesh LODs if needed).
5. Keyboard/gamepad navigation for inventory slots.

## How to continue development
Read AGENTS.md (verified commands), then docs/ARCHITECTURE.md. Run `tools/test.sh` before and after
changes. Rebuild with `tools/build_release.ps1`. The real-input QA bot lives in `tools/qa/`
(`playthrough.py --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/run`).
