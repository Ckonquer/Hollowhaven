# Handoff — Hollowhaven 2.0.2 (Chapter Two: The Lanterns of Hallowmere, bug-fix release)

## Launch
* Give Krystal: `C:\Users\Ali\Desktop\Hollowhaven\dist\Hollowhaven-2.0.2-Windows.zip`
  (111.1 MB, SHA-256 `2F77F52F219F5452E4140FD95DA25895C94E7C59E7A20231143ED564E4907FA8`, `dist\SHA256SUMS.txt`).
* She extracts it and runs **`Hollowhaven\Hollowhaven.exe`**, then presses **Continue - NOT New Game** - to keep her Chapter One
  world (house, chests, crops, friends). Update note: `Chapter Two - What's New.txt` next to the exe.
* The first Continue in a 2.0.x build keeps an untouched copy of her Chapter One save in
  `%APPDATA%\Hollowhaven\saves\pre_v2_backup\` (don't delete it). Same save format and upgrade as 2.0.0 / 2.0.1
  (`save_system.gd` unchanged since 2.0.0).
* Same build unzipped here: `C:\Users\Ali\Desktop\Hollowhaven\builds\Hollowhaven\Hollowhaven.exe`. The 2.0.0 and 2.0.1 zips are in
  `builds\superseded\`; 2.0.2 replaces them.
* Source: `C:\Users\Ali\Desktop\Hollowhaven\` (Godot 4.7.2 project in `game\`), git `991014c`. Build: `tools/build_release.ps1`;
  tests: `tools/test.sh`; commands: `AGENTS.md`, `PROJECT_STATE.md`.

## Changed since 2.0.1
One game fix (`a31e717`, `game/src/ui/hud/hint_card.gd`): boss-fight tips never lag behind the fight or outlive it - a newer fight
tip replaces an older queued one, the tip on screen makes room after 4 s, and the end of the encounter (won, reset, left, area
change) drops all fight tips. Seen in 2.0.1: the Weaver's "It is smothering a brazier!" tip over the Chapter One ending
(`qa/evidence/ch2_v2.0.1/run_b_fresh/play_038_ending.jpg`). Everything from 2.0.1 is included (`docs/ch2/HANDOFF_2.0.1.md`).
The Run B "Talk to Mochi opened Lumi's panel" case was investigated: a bot race, not a game bug (`QA_REPORT.md` §12.3).

## Tests actually run on 2.0.2
* Automated: full suite **2679 tests, 0 failed**, 890.7 s (`qa/tmp/full_final3.log`, tree `a31e717`; the bump `991014c` changes
  only version strings in `game/`), then the save (128 / 0) and audit (83 / 0) filters around the bump. Usual developer-log leak
  warning at exit (CH2-011).
* **V1** (packaged 2.0.2, visible on the second monitor, sound on, virtual input): fresh New Game -> Chapter One -> ending ->
  Chapter Two accepted -> free-play save: **21 of 21 steps, 697 s, 0 script errors**, no bot problems (Brave Little Steps' ribbon
  tied); the game never had the OS foreground (0 of 2669 checks). After the Chapter One ending the HUD shows no stale Weaver tip
  (`play_039_ending.png`) - the fix confirmed on screen for that case.
* **V2** (packaged 2.0.2, headless, virtual input): Chapter Two finale resumed from Run A's `T34_end` save - link the lanterns,
  Hushed Works, Crossing Matron, Borrowed Choir, Lanternwake ending, free play, relaunch + Continue: **completes**, 900.7 s (S4 883.4 s, END 8.8 s), 0 deaths, 0 script errors, 0 bugs, 32 music cue
  changes; Continue after the relaunch in 2.9 s with the same items, Chapter Two complete (20 steps). Headless: the Crossing / Choir
  tips were not seen on screen.
* On 2.0.1 (same code apart from the tip fix): Run A, the natural Chapter Two chain on the packaged exe, completes (1534.8 s, 0
  deaths, 0 script errors); Run B, fresh game visible, 21 / 21 steps. Evidence: `qa/evidence/ch2_v2.0.1/`, `qa/evidence/ch2_v2.0.2/`.

## Blockers / unverified
* **PERSONAL-SAVE VERIFICATION BLOCKED** - her save is not on this PC. Run the gate on a copy first, with the 2.0.2 exe
  (`docs/ch2/SAVE_INTEGRITY_REPORT.md` §7).
* No human play (playtime unmeasured), no OS-level real-input run (every run used the QA input port), no human listening to the
  music, nothing judged in motion; performance only on an RTX 4090 with the 2.0.0 exe (2.0.1 / 2.0.2 not re-profiled; memory creeps
  ~8.5 MB per Lantern Road round trip). Pipkin is not implemented. Remaining issues: `KNOWN_ISSUES.md`.

## Safe rollback (same as `docs/ch2/SAVE_INTEGRITY_REPORT.md` §8)
1. Close the game. 2. In `%APPDATA%\Hollowhaven\saves` move `slot1.json` / `slot1.bak.json` into a new `v2_kept\` folder (keep them).
3. Copy `pre_v2_backup\slot1.v1-<time>.json` to `slot1.json` (and `slot1.bak.v1-<time>.json` to `slot1.bak.json` if present).
4. Unzip `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\build\Hollowhaven-0.9.1-Windows.zip` (or the
   identical `builds\superseded\Hollowhaven-0.9.1-Windows.zip`, same SHA-256 `b4cab2cc…0e95`) somewhere new and play it.
   **Never open a 2.0.x save with the old exe** (it would set the v2 file aside as corrupt).
