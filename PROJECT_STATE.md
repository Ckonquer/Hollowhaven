# Project state — Hollowhaven (Chapter One: The Dimming Ward · Chapter Two: The Lanterns of Hallowmere)

_Last updated: 2026-09-28. Chapter Two released as **v2.0.0**, then the bug-fix releases **v2.0.1** and **v2.0.2** (packaged,
automated suite green, driven by the QA bot with virtual input - headless and visible on the second monitor, incl. the packaged 2.0.1
and 2.0.2 exes - and inspected as still frames). NOT yet: played by a human, played with OS-level input, listened to, profiled on anything but the development PC,
or verified on Krystal's own save._

## Where things are
| What | Where |
|---|---|
| Game to hand over | `dist/Hollowhaven-2.0.2-Windows.zip` (111.1 MB; SHA-256 in `dist/SHA256SUMS.txt`: `2F77F52F219F5452E4140FD95DA25895C94E7C59E7A20231143ED564E4907FA8`) |
| Unzipped build | `builds/Hollowhaven/Hollowhaven.exe` (2.0.2) + `How to Play.txt`, `Chapter Two - What's New.txt`, `Licenses/` |
| Older builds | `builds/superseded/` (0.1.0, 0.9.0, 0.9.1, 2.0.0, 2.0.1 zips) |
| Source | `game/` (Godot 4.7.2 project); the 2.0.2 build is git `991014c` "v2.0.2: version bump" (= `a31e717` "HUD tips: boss-fight tips never lag behind the fight or outlive it" + version bump + a QA-bot change in `tools/qa/playthrough.py`); 2.0.1 was `da94714`, 2.0.0 `36e2e8a`. Changes: `QA_REPORT.md` §11.1 (2.0.0 -> 2.0.1), §12.1 (-> 2.0.2). Tools `tools/`; toolchain `.tools/` (gitignored, `tools/setup_toolchain.ps1`) |
| Immutable pre-Chapter-Two backup | `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\` (`build\Hollowhaven-0.9.1-Windows.zip`, `source\` git bundle + zip at `b760f79`, `MANIFEST.txt`; hashes in `..\pre_chapter2_SHA256.txt`) |
| Short handoff | `docs/ch2/HANDOFF_2.0.2.md` (older: `HANDOFF_2.0.1.md`, `HANDOFF_2.0.0.md`) |
| Evidence | `QA_REPORT.md` (§9 = Chapter Two 2.0.0, §11 = 2.0.1, §12 = 2.0.2), `docs/ch2/SAVE_INTEGRITY_REPORT.md`, `docs/ch2/MUSIC_MANIFEST.md`, `qa/evidence/ch2_v2.0.0/`, `ch2_v2.0.1/`, `ch2_v2.0.2/` (committed copies: suite logs, bot runs on the packaged exe, screenshots, perf summaries), `qa/tmp/` (gitignored: test logs, bot runs `qa/tmp/bot/`, `qa/tmp/e2e/`, stills `qa/tmp/visual/`, perf `qa/tmp/perf/`), `qa/evidence/` (Chapter One) |
| Issues | `KNOWN_ISSUES.md` |
| Design / contracts | `GAME_SPEC.md`, `Hollowhaven_Part2_Master_Prompt.md`, `docs/CHAPTER_TWO_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/SAVE_MIGRATION.md`, `docs/ch2/WAVES.md`, code maps `docs/ch2/maps/*.md` |
| Decision records | `docs/ch2/WAVE_A_REPORT.md`, `INTEGRATION_WAVE_BC.md` (pass 1), `INTEGRATION_WAVE_D.md` + `INTEGRATION_PASS2.md` (pass 2), `INTEGRATION_PASS3.md` (pass 3) |
| Player docs (source) | `docs/player/How to Play.txt`, `docs/player/Chapter Two - What's New.txt` (the 2.0.1 and 2.0.2 zips carry these exact files) |
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
    end-to-end chain (headless, pre-release snapshot: 4 of 5 runs completed Chapter Two + relaunch, 1 stopped at the Warden -> CHAIN-001 / 002).
  * Release: version 2.0.0, `.uid` files for all 705 scripts, full suite **2639 tests, 0 failed** (`qa/tmp/full_final1.log`),
    `tools/build_release.ps1` -> zip + SHA-256.
  * After 2.0.0: a visible natural chain on the packaged 2.0.0 exe (1488 s, completes; `qa/evidence/ch2_v2.0.0/`); QA focus
    protection (`tools/qa/fglock.py`); five bot coverage runs (equipment / companions, trials / expeditions, lamp orders + Chapter One
    optionals, arachnophobia / comfort, persistence / failure; 8 bugs, `qa/tmp/bot/COVERAGE_BUGS.md`).
  * **Release 2.0.1** (`da94714`): CHAIN-001 / 002, COV-001..007, R3-03 and the loading card fixed (`KNOWN_ISSUES.md` "Fixed in 2.0.1");
    full suite **2672 tests, 0 failed** (`qa/tmp/full_final2.log`); zip ships the corrected player docs and licence notice (checked);
    Run B (fresh New Game -> Chapter One -> accept Chapter Two, packaged, visible) 21/21 steps; Run A (natural Chapter Two chain,
    packaged, headless) completes: 20/20 steps + relaunch, 1534.8 s, 0 deaths, 0 script errors (`QA_REPORT.md` §11).
  * **Release 2.0.2** (`991014c`): boss-fight tips never lag behind the fight or outlive it (`a31e717`, 7 new tests); full suite
    **2679 tests, 0 failed** (`qa/tmp/full_final3.log`), save 128 / 0 and audit 83 / 0 after the bump; the Run B Mochi / Lumi panel
    case investigated (a bot race, not a game bug). Packaged 2.0.2: V1 (fresh New Game, visible) 21/21 steps, 0 script errors, no stale
    tip after the ending; V2 (Chapter Two finale from Run A's `T34_end` save, headless) completes, 900.7 s, relaunch + Continue same
    items (`QA_REPORT.md` §12).
* Not implemented (stretch): the optional fourth friend Pipkin; new creature voices (D10: creatures reuse existing sounds).

## Pending (in priority order)
1. **Krystal's-own-save gate** (PERSONAL-SAVE VERIFICATION BLOCKED): copy, hash, migrate the copy with `--save-dir`, run
   `tools/qa/save_integrity.py`, inspect the home (`docs/ch2/SAVE_INTEGRITY_REPORT.md` §7). Needs her save file.
2. **Performance**: the packaged per-area profile on the RTX 4090 is done for 2.0.0 (`qa/tmp/perf/packaged_v200/summary.md`,
   `qa/tmp/perf/packaged_v200_nofocus/`, `QA_REPORT.md` §9.8); still to do: 2.0.1 (loading card) / 2.0.2 not re-profiled, a weaker / integrated GPU, the
   V-Sync-on default, a timed natural route and a long session (memory rises ~8.5 MB per Lantern Road round trip over 10 cycles,
   9.9-15.7 MB in 3-cycle runs).
3. **Real play**: a human first-time session and an OS-level real-input run on the packaged exe (MP §20.4 runs A-E); the list of
   checks is `KNOWN_ISSUES.md` §7. (The packaged-exe bot runs - 2.0.0 visible chain, 2.0.1 Run A / Run B, 2.0.2 V1 / V2 - are virtual input only.)
4. **Listening**: a human pass over the music (`docs/ch2/MUSIC_MANIFEST.md`), the Music Box and the mix; then the D10 voice pass.
5. **Open bugs**: R3-43 day dial in the manor; onboarding pacing (P50); Bell Throat stone position check (L10); the exit-time
   "resources still in use" ERROR lines (COV-008); the prompt label trailing the real target by up to ~160 ms when two targets
   cross (minor, not changed). Fixed in 2.0.2: the lingering boss-fight tips; the Run B Mochi / Lumi case was a bot race.
6. **Done in 2.0.1:** the rebuild with the corrected player docs and the updated `THIRD_PARTY_NOTICES.md` (the zip's
   `How to Play.txt`, `Chapter Two - What's New.txt` and `Licenses/THIRD_PARTY_NOTICES.txt` are byte-identical to `docs/player/` and
   `THIRD_PARTY_NOTICES.md` at `da94714`).
7. Keyboard / gamepad navigation for inventory slots; test hygiene (per-suite cleanup instead of the runner's ISOLATION guard, F04).

## How to continue development
Read `AGENTS.md` (verified commands, rules), then `docs/ARCHITECTURE.md` and `docs/CHAPTER_TWO_SPEC.md`. From the repo root in Git Bash:
```bash
powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1      # Godot 4.7.2 + templates + Python venv (once)
tools/test.sh                                                           # full headless suite (~15 min, 2679 tests)
tools/test.sh save_v2                                                   # one area (filter = file-name substring)
tools/godot.sh --path game --resolution 1600x900 -- --windowed          # run from source
powershell -ExecutionPolicy Bypass -File tools/build_release.ps1        # export + zip + SHA256SUMS
.tools/pyenv/Scripts/python.exe tools/qa/save_integrity.py <v1 slot1.json> <v2 slot1.json> --out report.json
python tools/qa/ch2/chain.py --headless --out qa/tmp/bot/chain/<run>   # natural Chapter Two chain (headless bot)
python tools/qa/ch2/chain.py --visible --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/<run>   # packaged, 2nd monitor
python tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/<run>  # packaged, headless (2.0.1 Run A)
python tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --from S4 --start-save <run>/checkpoints/T34_end --out qa/tmp/bot/chain/<run2>  # resume at S4 (2.0.2 V2)
python tools/qa/playthrough.py --second-monitor --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/<run>  # fresh New Game -> Chapter One -> Chapter Two accepted (2.0.1 Run B)
.tools/pyenv/Scripts/python.exe tools/audio/music2/group_home_woods.py  # regenerate a music group (also group_ch1_tension / group_hallowmere / group_manor_works)
```
After adding scripts or audio: `tools/godot.sh --headless --path game --import` (alone, then the full suite). Tests only write in
`user://test_saves/`; every QA run that can save must pass `--save-dir=<scratch>` so `%APPDATA%\Hollowhaven\saves` is never touched.
Bound every process (`--quit-at`, `--max-seconds`, `timeout`) and kill only processes you started.
