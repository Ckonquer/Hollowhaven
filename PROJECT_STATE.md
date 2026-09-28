# Project state — Hollowhaven (Chapter One: The Dimming Ward · Chapter Two: The Lanterns of Hallowmere)

_Last updated: 2026-09-28. **v2.0.3 is the gift build**: an installer plus the same game as a zip. Krystal has never played; she
starts with New Game on her own PC (so there is no personal save to verify). Chapter Two was released as v2.0.0, then bug-fix
releases 2.0.1-2.0.3 (packaged, automated suite green, driven by the QA bot with virtual input - headless and visible on the second
monitor - and inspected as still frames). NOT yet: played by a human, played with OS-level input, listened to, run on a second PC,
profiled on anything but the development PC; the installer wizard was never seen on screen._

## Where things are
| What | Where |
|---|---|
| Game to hand over | **`dist/Hollowhaven-Setup-2.0.3.exe`** (the installer, 100.8 MB, SHA-256 `9A8660DDF85E344C2333100B1E47FC90A791B9F49162B59ED8CE3822A26D18E2`); the same game without installer: `dist/Hollowhaven-2.0.3-Windows.zip` (111.1 MB, SHA-256 `1788D65B101CCF4581011C3ABE60963CF18511A96A59DAA58FA5FBD2FA60A670`); both in `dist/SHA256SUMS.txt`. Installer guide: `docs/INSTALLER.md` |
| Unzipped build | `builds/Hollowhaven/Hollowhaven.exe` (2.0.3) + `How to Play.txt`, `Licenses/` |
| Older builds | `builds/superseded/` (0.1.0, 0.9.0, 0.9.1, 2.0.0, 2.0.1, 2.0.2 zips; `Hollowhaven-Setup-2.0.2.exe`) |
| Source | `game/` (Godot 4.7.2 project); the 2.0.3 build is git `8f5cbc0` "v2.0.3: version bump (the gift build ...)"; 2.0.2 was `991014c`, 2.0.1 `da94714`, 2.0.0 `36e2e8a`. Changes: `QA_REPORT.md` §11.1 (-> 2.0.1), §12.1 (-> 2.0.2), §13.1 (-> 2.0.3). Installer script `tools/installer/hollowhaven.iss`, build `tools/build_installer.ps1`. Tools `tools/`; toolchain `.tools/` (gitignored, `tools/setup_toolchain.ps1`) |
| Immutable pre-Chapter-Two backup | `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\` (`build\Hollowhaven-0.9.1-Windows.zip`, `source\` git bundle + zip at `b760f79`, `MANIFEST.txt`; hashes in `..\pre_chapter2_SHA256.txt`) |
| Short handoff | `docs/ch2/HANDOFF_2.0.3.md` (older ones, written for a returning player: `HANDOFF_2.0.2.md`, `HANDOFF_2.0.1.md`, `HANDOFF_2.0.0.md`) |
| Her PC | `docs/ch2/DIFFERENT_PC_READINESS.md` (minimum / recommended PC - estimates, renderer fallbacks, what to do if it does not start) |
| Evidence | `QA_REPORT.md` (§9 = Chapter Two 2.0.0, §11 = 2.0.1, §12 = 2.0.2, §13 = 2.0.3), `docs/ch2/SAVE_INTEGRITY_REPORT.md`, `docs/ch2/MUSIC_MANIFEST.md`, `qa/evidence/ch2_v2.0.0/`, `ch2_v2.0.1/`, `ch2_v2.0.2/`, `ch2_v2.0.3/` (committed copies: suite logs, bot runs on the packaged exe, screenshots, perf summaries), `qa/tmp/` (gitignored: test logs, bot runs `qa/tmp/bot/`, `qa/tmp/e2e/`, stills `qa/tmp/visual/`, perf `qa/tmp/perf/`), `qa/evidence/` (Chapter One) |
| Issues | `KNOWN_ISSUES.md` |
| Design / contracts | `GAME_SPEC.md`, `Hollowhaven_Part2_Master_Prompt.md`, `docs/CHAPTER_TWO_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/SAVE_MIGRATION.md`, `docs/ch2/WAVES.md`, code maps `docs/ch2/maps/*.md` |
| Decision records | `docs/ch2/WAVE_A_REPORT.md`, `INTEGRATION_WAVE_BC.md` (pass 1), `INTEGRATION_WAVE_D.md` + `INTEGRATION_PASS2.md` (pass 2), `INTEGRATION_PASS3.md` (pass 3) |
| Player docs (source) | `docs/player/How to Play.txt` (for a first-time player; the 2.0.3 zip and installer carry this exact file). The returning-player "Chapter Two - What's New.txt" was retired in 2.0.3 |
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
  * **Release 2.0.3, the gift build** (`8f5cbc0`): Inno Setup installer (`88218b6`, `docs/INSTALLER.md`); first-time player texts,
    `How to Play.txt` rewritten, "What's New" retired (`eab619d`); different-PC readiness report (`37d93ef`); fight-tip priorities
    (`caab0a4`); companions never inside the camera (`36934ae`); toasts / quest banner / journal tag (`ac5c69c`); QA primary-monitor
    guard after the 15:00-15:56 incident (`bb79708`). Chapter Two from a New-Game save on the packaged 2.0.2 exe: completes
    (visible, headless, resumed). Full suite on 2.0.3: **2712 tests, 0 failed** (`qa/tmp/full_final4.log`); Chapter One (fresh New
    Game -> Chapter Two accepted): completes headless on the 2.0.3 sources (route-bot re-run, 721.5 s; the first attempt stopped on a
    bot navigation problem; not run on the installed exe); Chapter Two from the New-Game save on the **installed** exe, headless:
    completes (1509.3 s, 0 script errors, relaunch + Continue same items); the test install was silently uninstalled afterwards
    (`QA_REPORT.md` §13).
* Not implemented (stretch): the optional fourth friend Pipkin; new creature voices (D10: creatures reuse existing sounds).

## Pending (in priority order)
1. **Before handing it over** (`docs/ch2/HANDOFF_2.0.3.md`): run the installer once on this PC and look at the wizard pages (never
   seen on screen), check her PC against `docs/ch2/DIFFERENT_PC_READINESS.md` §2 (graphics chip, driver), give her a mouse.
   (The former personal-save gate is obsolete: she has no save.)
2. **Performance**: the packaged per-area profile on the RTX 4090 is done for 2.0.0 (`qa/tmp/perf/packaged_v200/summary.md`,
   `qa/tmp/perf/packaged_v200_nofocus/`, `QA_REPORT.md` §9.8); still to do: 2.0.1-2.0.3 not re-profiled, a real weaker / integrated GPU (the readiness numbers are one measured weak chip + estimates), the
   V-Sync-on default, a timed natural route and a long session (memory rises ~8.5 MB per Lantern Road round trip over 10 cycles,
   9.9-15.7 MB in 3-cycle runs).
3. **Real play**: a human first-time session and an OS-level real-input run on the packaged exe (MP §20.4 runs A-E); the list of
   checks is `KNOWN_ISSUES.md` §7. (The packaged-exe bot runs - 2.0.0 visible chain, 2.0.1 Run A / Run B, 2.0.2 V1 / V2, the 2.0.2 native
   New-Game-save chains, 2.0.3 F2 - are virtual input only.) Krystal's own first session will be the first human play.
4. **Listening**: a human pass over the music (`docs/ch2/MUSIC_MANIFEST.md`), the Music Box and the mix; then the D10 voice pass.
5. **Open bugs** (`KNOWN_ISSUES.md` §2-§3): the Bellhouse service-stair camera ~0.25 m above a tread; companions near the camera
   vanish / reappear without a fade; toasts can vanish and come back when a long dialogue line shrinks the room; ordinary tips wait
   behind fight tips; enemy tell tips once per session; R3-43 day dial in the manor; onboarding pacing (P50); Bell Throat stone (L10);
   the exit-time "resources still in use" ERROR lines (COV-008); the prompt label trailing the real target by up to ~160 ms.
6. Readiness follow-ups in `docs/ch2/DIFFERENT_PC_READINESS.md` §6 - the owner shipped 2.0.3 without them; open: #3 / #4 first-start
   quality (integrated GPU -> Low, no High on the OpenGL fallback), #6 OpenGL water / flowers, #7-#13. Until then: `How to Play.txt`
   "IF THE GAME RUNS SLOWLY". Also: mention Inno Setup (a build-time tool, not shipped) in `THIRD_PARTY_NOTICES.md` at the next
   release build (that file ships byte for byte, so it was left unchanged in 2.0.3).
7. Keyboard / gamepad navigation for inventory slots; test hygiene (per-suite cleanup instead of the runner's ISOLATION guard, F04).

## How to continue development
Read `AGENTS.md` (verified commands, rules), then `docs/ARCHITECTURE.md` and `docs/CHAPTER_TWO_SPEC.md`. From the repo root in Git Bash:
```bash
powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1      # Godot 4.7.2 + templates + Python venv (once)
tools/test.sh                                                           # full headless suite (~16 min, 2712 tests)
tools/test.sh save_v2                                                   # one area (filter = file-name substring)
tools/godot.sh --path game --resolution 1600x900 -- --windowed          # run from source
powershell -ExecutionPolicy Bypass -File tools/build_release.ps1        # export + zip + SHA256SUMS
powershell -ExecutionPolicy Bypass -File tools/build_installer.ps1      # installer (after build_release; docs/INSTALLER.md)
.tools/pyenv/Scripts/python.exe tools/qa/save_integrity.py <v1 slot1.json> <v2 slot1.json> --out report.json
python tools/qa/ch2/chain.py --headless --out qa/tmp/bot/chain/<run>   # natural Chapter Two chain (headless bot)
python tools/qa/ch2/chain.py --visible --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/<run>   # packaged, 2nd monitor
python tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/bot/chain/<run>  # packaged, headless (2.0.1 Run A)
python tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --from S4 --start-save <run>/checkpoints/T34_end --out qa/tmp/bot/chain/<run2>  # resume at S4 (2.0.2 V2)
python tools/qa/playthrough.py --second-monitor --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/<run>  # fresh New Game -> Chapter One -> Chapter Two accepted (2.0.1 Run B)
#   note: playthrough.py --headless runs the SOURCE project with the console binary (it ignores a non-console --exe)
.tools/pyenv/Scripts/python.exe tools/audio/music2/group_home_woods.py  # regenerate a music group (also group_ch1_tension / group_hallowmere / group_manor_works)
```
After adding scripts or audio: `tools/godot.sh --headless --path game --import` (alone, then the full suite). Tests only write in
`user://test_saves/`; every QA run that can save must pass `--save-dir=<scratch>` so `%APPDATA%\Hollowhaven\saves` is never touched.
Bound every process (`--quit-at`, `--max-seconds`, `timeout`) and kill only processes you started.
