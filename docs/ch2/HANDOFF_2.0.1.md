# Handoff — Hollowhaven 2.0.1 (Chapter Two: The Lanterns of Hallowmere, bug-fix release)

## Launch
* Give Krystal: `C:\Users\Ali\Desktop\Hollowhaven\dist\Hollowhaven-2.0.1-Windows.zip`
  (111.1 MB, SHA-256 `8017AF7123204BA303EE9E08D8B61A47DBB01CAD87EBAB6E5F311465175857FE`, `dist\SHA256SUMS.txt`).
* She extracts it and runs **`Hollowhaven\Hollowhaven.exe`**, then presses **Continue - NOT New Game** - to keep her Chapter One
  world (house, chests, crops, friends). Update note: `Chapter Two - What's New.txt` next to the exe.
* The first Continue in a 2.0.x build keeps an untouched copy of her Chapter One save in
  `%APPDATA%\Hollowhaven\saves\pre_v2_backup\` (don't delete it). 2.0.1 uses the same save format and upgrade as 2.0.0
  (`save_system.gd` unchanged).
* Same build unzipped here: `C:\Users\Ali\Desktop\Hollowhaven\builds\Hollowhaven\Hollowhaven.exe`. The 2.0.0 zip is in
  `builds\superseded\`; 2.0.1 replaces it.
* Source: `C:\Users\Ali\Desktop\Hollowhaven\` (Godot 4.7.2 project in `game\`), git `da94714`. Build: `tools/build_release.ps1`;
  tests: `tools/test.sh`; commands: `AGENTS.md`, `PROJECT_STATE.md`.

## Changed since 2.0.0
Quarry Warden: resets cleanly when Krystal leaves its arena level (CHAIN-001) and needs at least one pillar exposure (CHAIN-002);
Return to safety / respawn near lit checkpoints (COV-001); companions no longer cancel ordinary enemies' tells (COV-002); the Echo
Trial is no longer a landmark (COV-003); arachnophobia wording of two Weaver hints (COV-004); the upstairs goal needs the walk
(COV-005); plurals (COV-006); wand refund when a hit cancels the cast (COV-007); the tracker drops finished lamp-search rows (R3-03);
a loading card before an area builds. The zip now carries the corrected player docs and licence notice (checked byte for byte).
Details: `QA_REPORT.md` §11, `KNOWN_ISSUES.md` "Fixed in 2.0.1".

## Tests actually run on 2.0.1
* Automated: full suite **2672 tests, 0 failed**, 888.5 s (`qa/tmp/full_final2.log`, tree `c709db8`; not re-run after the
  version-bump commit). Usual developer-log leak warning at exit (CH2-011).
* **Run B** (packaged 2.0.1, visible on the second monitor, sound on, virtual input): fresh New Game -> Meet Krystal -> Chapter One ->
  Weaver Matron -> ending -> Chapter Two accepted -> free-play save: **21 of 21 steps, 658 s, 0 script errors**; the game never
  had the OS foreground (0 of 2523 checks). Found: a stale boss-fight tip over the ending (`play_038_ending.png`, fix in progress for
  the next build) and the optional Comfort Ribbon step not finished (bot opened Lumi's panel; not investigated).
* **Run A** (packaged 2.0.1, headless, virtual input): natural Chapter Two chain from the real Chapter-One-complete save -> S1..S4 ->
  relaunch + Continue: **completes** - Chapter Two 20 of 20 steps, Save & Quit, relaunch, Continue with the same items; 1534.8 s,
  0 deaths, 0 script errors, 63 music cue changes (headless: nothing rendered, nothing heard). Warden 32.5 s with 3 pillar exposures.
* Earlier: visible natural Chapter Two chain on the packaged 2.0.0 exe (1488 s, completes, 0 script errors); perf on the 2.0.0 exe
  (RTX 4090, 398-709 average FPS). Evidence copies: `qa/evidence/ch2_v2.0.0/`, `qa/evidence/ch2_v2.0.1/`.

## Blockers / unverified
* **PERSONAL-SAVE VERIFICATION BLOCKED** - her save is not on this PC. Run the gate on a copy first, with the 2.0.1 exe
  (`docs/ch2/SAVE_INTEGRITY_REPORT.md` §7).
* No human play (playtime unmeasured), no OS-level real-input run (every run used the QA input port), no human listening to the
  music, nothing judged in motion; performance only on an RTX 4090 (2.0.1 not re-profiled; memory creeps ~8.5 MB per Lantern Road
  round trip). Pipkin is not implemented. Remaining issues: `KNOWN_ISSUES.md`.

## Safe rollback (same as `docs/ch2/SAVE_INTEGRITY_REPORT.md` §8)
1. Close the game. 2. In `%APPDATA%\Hollowhaven\saves` move `slot1.json` / `slot1.bak.json` into a new `v2_kept\` folder (keep them).
3. Copy `pre_v2_backup\slot1.v1-<time>.json` to `slot1.json` (and `slot1.bak.v1-<time>.json` to `slot1.bak.json` if present).
4. Unzip `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\build\Hollowhaven-0.9.1-Windows.zip` (or the
   identical `builds\superseded\Hollowhaven-0.9.1-Windows.zip`, same SHA-256 `b4cab2cc…0e95`) somewhere new and play it.
   **Never open a 2.0.x save with the old exe** (it would set the v2 file aside as corrupt).
