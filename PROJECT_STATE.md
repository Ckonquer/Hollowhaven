# Project state — Hollowhaven (Chapter One: The Dimming Ward · Chapter Two: The Lanterns of Hallowmere)

_Last updated: 2026-09-28 (Chapter One released as v0.9.0 / v0.9.1; Chapter Two fully built, integration pass 2 applied;
not yet packaged as a new release)._

## Where things are
* Playable build: `builds/Hollowhaven/Hollowhaven.exe` (+ `How to Play.txt`, `Chapter Two - What's New.txt` from the next
  build on, `Licenses/`) · ZIP: `dist/Hollowhaven-<version>-Windows.zip`
* Source: `game/` (Godot 4.7.2 project) · tools: `tools/` · docs: `GAME_SPEC.md`, `docs/ARCHITECTURE.md`, `AGENTS.md`
* Evidence: `QA_REPORT.md`, `qa/evidence/` · issues: `KNOWN_ISSUES.md` · provenance: `THIRD_PARTY_NOTICES.md`
* Chapter Two: contract `docs/CHAPTER_TWO_SPEC.md` · save schema v2 `docs/SAVE_MIGRATION.md` · module ownership
  `docs/ch2/WAVES.md` · code maps `docs/ch2/maps/*.md` · decisions `docs/ch2/INTEGRATION_WAVE_BC.md` (pass 1) and
  `docs/ch2/INTEGRATION_WAVE_D.md` (pass 2) · player note `docs/player/Chapter Two - What's New.txt`

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

## Automated tests
`tools/test.sh` — 653 tests, 0 failures at v0.9.0 (headless, ~5 min). With Chapter Two: 2407 tests, 0 failed after integration
pass 1 (headless, 15-25 min; `QA_REPORT.md` §9.1). The full-suite result after pass 2 is recorded by the lead in `QA_REPORT.md`
(each fixer group's own suite runs: `docs/ch2/INTEGRATION_PASS2.md`). Chapter Two has NOT been played with real input or looked
at on screen yet (`KNOWN_ISSUES.md`, Chapter Two section).

## Next steps
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
