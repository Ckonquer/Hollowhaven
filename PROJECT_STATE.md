# Project state — Hollowhaven (Chapter One: The Dimming Ward)

_Last updated: 2026-09-27 (v0.9.0)._

## Where things are
* Playable build: `builds/Hollowhaven/Hollowhaven.exe` (+ `How to Play.txt`, `Licenses/`) · ZIP: `dist/Hollowhaven-<version>-Windows.zip`
* Source: `game/` (Godot 4.7.2 project) · tools: `tools/` · docs: `GAME_SPEC.md`, `docs/ARCHITECTURE.md`, `AGENTS.md`
* Evidence: `QA_REPORT.md`, `qa/evidence/` · issues: `KNOWN_ISSUES.md` · provenance: `THIRD_PARTY_NOTICES.md`

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

## Automated tests
`tools/test.sh` — 653 tests, 0 failures at v0.9.0 (headless, ~5 min).

## Next steps (future chapters / polish)
1. Human listening pass on the audio; adjust levels/melodies by ear.
2. Test on a weaker GPU; tune Settings "Quality" presets (tree MultiMesh LODs if needed).
3. Keyboard/gamepad navigation for inventory slots.
4. Chapter Two hooks already in place: the Weaver retreated into the deep crack; the Heartbloom
   recipes and echo shards hint at deeper places. Add a new area by following docs/ARCHITECTURE.md
   (new `scenes/<area>.tscn` + area script, register in `Game.AREAS`, add quest steps in data/quests.gd).

## How to continue development
Read AGENTS.md (verified commands), then docs/ARCHITECTURE.md. Run `tools/test.sh` before and after
changes. Rebuild with `tools/build_release.ps1`. The real-input QA bot lives in `tools/qa/`
(`playthrough.py --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/run`).
