# Project state — Hollowhaven (Chapter One: The Dimming Ward · Chapter Two: The Lanterns of Hallowmere)

_Last updated: 2026-09-28. Chapter Two released as **v2.0.0** (packaged, automated suite green, driven by the headless QA bot and
inspected as still frames). NOT yet: played by a human, played with OS-level input, listened to, profiled on anything but the development PC,
or verified on Krystal's own save._

## Where things are
| What | Where |
|---|---|
| Game to hand over | `dist/Hollowhaven-2.0.0-Windows.zip` (111.1 MB; SHA-256 in `dist/SHA256SUMS.txt`: `9F3FD0D2E3216B861E470158B881A10ED2CEBBC30FC3C07D3BC61D93652856CC`) |
| Unzipped build | `builds/Hollowhaven/Hollowhaven.exe` + `How to Play.txt`, `Chapter Two - What's New.txt`, `Licenses/` |
| Older builds | `builds/superseded/` (0.1.0, 0.9.0, 0.9.1 zips) |
| Source | `game/` (Godot 4.7.2 project); the 2.0.0 build is git `36e2e8a` "v2.0.0 (Chapter Two)". Later: `e4b10b2` (QA tooling only: `tools/qa/ch2/chain.py`, `tools/qa/perf_profile.py`). At 11:00 on 2026-09-28 `game/src/enemies/quarry_warden.gd` had uncommitted edits by another session (presumably CHAIN-001 / 002 work) - NOT in the 2.0.0 build, not reviewed here. Tools `tools/`; toolchain `.tools/` (gitignored, `tools/setup_toolchain.ps1`) |
| Immutable pre-Chapter-Two backup | `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\` (`build\Hollowhaven-0.9.1-Windows.zip`, `source\` git bundle + zip at `b760f79`, `MANIFEST.txt`; hashes in `..\pre_chapter2_SHA256.txt`) |
| Short handoff | `docs/ch2/HANDOFF_2.0.0.md` |
| Evidence | `QA_REPORT.md` (§9 = Chapter Two), `docs/ch2/SAVE_INTEGRITY_REPORT.md`, `docs/ch2/MUSIC_MANIFEST.md`, `qa/tmp/` (gitignored: test logs, bot runs `qa/tmp/bot/`, stills `qa/tmp/visual/`, perf `qa/tmp/perf/`), `qa/evidence/` (Chapter One) |
| Issues | `KNOWN_ISSUES.md` |
| Design / contracts | `GAME_SPEC.md`, `Hollowhaven_Part2_Master_Prompt.md`, `docs/CHAPTER_TWO_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/SAVE_MIGRATION.md`, `docs/ch2/WAVES.md`, code maps `docs/ch2/maps/*.md` |
| Decision records | `docs/ch2/WAVE_A_REPORT.md`, `INTEGRATION_WAVE_BC.md` (pass 1), `INTEGRATION_WAVE_D.md` + `INTEGRATION_PASS2.md` (pass 2), `INTEGRATION_PASS3.md` (pass 3) |
| Player docs (source) | `docs/player/How to Play.txt`, `docs/player/Chapter Two - What's New.txt` (corrected after the 2.0.0 zip was built; see Pending) |
| Provenance | `THIRD_PARTY_NOTICES.md` |

## Done
* **Chapter One** (v0.9.0 / v0.9.1): see `QA_REPORT.md` §1-8.
* **Chapter Two** (each module built, then independently reviewed; `docs/ch2/WAVES.md`):
  * Wave A: save schema v2 + migration + one-time upgrade backup, the Chapter Two quest layer, optional goals, reward ledger, data
    catalogue, new areas and travel (waygate, Lantern Road), the MusicDirector and 22 new compositions (26 OGG files).
  * Wave B: avatar looks, "Meet Krystal" and the wardrobe; equipment / stats / Sparkseed Wand; companion combat, skills and Mochi's
    courage; Furnace, Loom & Dye Bench, Kitchen Counter, masteries; two-storey building and Halloween decor; Chapter One extras
    (Tailor's Cache, Bramblewatch, meadow, moths, Tobin's annex); new Chapter One enemies; the three-phase Weaver Matron and her Echo
    Trial; journal / map / tracker.
  * Wave C: Hallowmere Reach (Commons, Conservatory, Orchard, Pools, Candleyard, Quarry, Manor grounds, Bellhouse), Moonveil Manor,
    the Hushed Works (14 rooms), five Chapter Two enemies + the Quarry Warden, bosses Count Velour, the Crossing Matron and the
    Borrowed Choir, the Chapter Two story and ending.
  * Wave D: Echo Trials for Velour and the Choir, Lanternwake Expeditions, the Music Box, onboarding tips, the player update note.
  * Integration passes 1-3; QA-bot route segments S0-S4 (17 bugs: 16 fixed, CH2-011 partly - engine log noise); six still-frame
    visual reviews (110 findings: 81 fixed and re-rendered, 5 partly, 24 addressed in code without a closure record); the natural
    end-to-end chain (headless, pre-release snapshot: 4 of 5 runs completed Chapter Two + relaunch, 1 stopped at the Warden -> CHAIN-001 / 002, open).
  * Release: version 2.0.0, `.uid` files for all 705 scripts, full suite **2639 tests, 0 failed** (`qa/tmp/full_final1.log`),
    `tools/build_release.ps1` -> zip + SHA-256.
* Not implemented (stretch): the optional fourth friend Pipkin; new creature voices (D10: creatures reuse existing sounds).

## Pending (in priority order)
1. **Krystal's-own-save gate** (PERSONAL-SAVE VERIFICATION BLOCKED): copy, hash, migrate the copy with `--save-dir`, run
   `tools/qa/save_integrity.py`, inspect the home (`docs/ch2/SAVE_INTEGRITY_REPORT.md` §7). Needs her save file.
2. **Performance**: the packaged per-area profile on the RTX 4090 is done (`qa/tmp/perf/packaged_v200/summary.md`, `QA_REPORT.md`
   §9.8); still to do: a weaker / integrated GPU, the V-Sync-on default, a timed natural route and a long session (memory rises
   ~9-15 MB per Lantern Road round trip).
3. **Real play**: a human first-time session and an OS-level real-input run on the packaged exe (MP §20.4 runs A-E); the list of
   checks is `KNOWN_ISSUES.md` §7. Also the natural chain on the packaged exe, visible on the second monitor.
4. **Listening**: a human pass over the music (`docs/ch2/MUSIC_MANIFEST.md`), the Music Box and the mix; then the D10 voice pass.
5. **Open bugs**: CHAIN-001 (Warden frozen below the bench edge), CHAIN-002 (Warden beatable without exposures - design call);
   R3-03 tracker lamp rows; R3-43 day dial in the manor; onboarding pacing (P50); Bell Throat stone position check (L10).
6. **Next rebuild** ships the corrected player docs and the updated `THIRD_PARTY_NOTICES.md` (the 2.0.0 zip has the earlier text).
7. Keyboard / gamepad navigation for inventory slots; test hygiene (per-suite cleanup instead of the runner's ISOLATION guard, F04).

## How to continue development
Read `AGENTS.md` (verified commands, rules), then `docs/ARCHITECTURE.md` and `docs/CHAPTER_TWO_SPEC.md`. From the repo root in Git Bash:
```bash
powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1      # Godot 4.7.2 + templates + Python venv (once)
tools/test.sh                                                           # full headless suite (~15 min, 2639 tests)
tools/test.sh save_v2                                                   # one area (filter = file-name substring)
tools/godot.sh --path game --resolution 1600x900 -- --windowed          # run from source
powershell -ExecutionPolicy Bypass -File tools/build_release.ps1        # export + zip + SHA256SUMS
.tools/pyenv/Scripts/python.exe tools/qa/save_integrity.py <v1 slot1.json> <v2 slot1.json> --out report.json
python tools/qa/ch2/chain.py --headless --out qa/tmp/bot/chain/<run>   # natural Chapter Two chain (headless bot)
python tools/qa/ch2/chain.py --visible --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/<run>   # packaged, 2nd monitor
.tools/pyenv/Scripts/python.exe tools/audio/music2/group_home_woods.py  # regenerate a music group (also group_ch1_tension / group_hallowmere / group_manor_works)
```
After adding scripts or audio: `tools/godot.sh --headless --path game --import` (alone, then the full suite). Tests only write in
`user://test_saves/`; every QA run that can save must pass `--save-dir=<scratch>` so `%APPDATA%\Hollowhaven\saves` is never touched.
Bound every process (`--quit-at`, `--max-seconds`, `timeout`) and kill only processes you started.
