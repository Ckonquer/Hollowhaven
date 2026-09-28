# Evidence — Hollowhaven 2.0.3, the gift build (2026-09-28)

Small committed copies; the full run folders stay in `qa/tmp/` (gitignored). Build under test: the installer
`dist/Hollowhaven-Setup-2.0.3.exe` (SHA-256 `9A8660DDF85E344C2333100B1E47FC90A791B9F49162B59ED8CE3822A26D18E2`) and the zip
`dist/Hollowhaven-2.0.3-Windows.zip` (SHA-256 `1788D65B101CCF4581011C3ABE60963CF18511A96A59DAA58FA5FBD2FA60A670`), git `8f5cbc0`.
Report: `QA_REPORT.md` §13. Every bot run used **virtual input through the game's QA port** (not OS input, not a human); no
installer window was ever opened.

| File | Copied from | What it shows |
|---|---|---|
| `build/build_v203_tail.log` | last 5 lines of `qa/tmp/build_v203.log` (colour codes stripped) | Release build (`-SkipTests`): 2.0.2 zip moved to `builds/superseded/`, the 2.0.3 zip built (111.1 MB) with the SHA-256 above, EXIT=0 |
| `build/build_installer_v203.log` | `qa/tmp/build_installer_v203.log` | `build_installer.ps1`: exe file version 2.0.3.0, `builds/Hollowhaven` matches the zip file for file (SHA-256), Setup-2.0.2 moved to `builds/superseded/`, the installer built (105,736,221 bytes) with the SHA-256 above, `SHA256SUMS.txt` updated, EXIT=0 |
| `build/SHA256SUMS.txt` | `dist/SHA256SUMS.txt` | The two checksums as shipped |
| `installer/final203_silent_install.log` | `qa/tmp/final203/logs/install.log` | The 2.0.3 installer, silent (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS /MERGETASKS=!desktopicon`) into `qa/tmp/final203/install`: the 6 game files + uninstaller written, "Installation process succeeded" |
| `installer/final203_builds.sha`, `installer/final203_installed.sha` | `qa/tmp/final203/` | SHA-256 of the 6 files in `builds/Hollowhaven` and in the test install: identical lists |
| `installer/t5b_upgrade_200_to_202.log` | `qa/tmp/installer/logs/` | 2.0.2-era test: a 2.0.0 test install updated in place by the 2.0.2 installer without `/DIR` |
| `installer/t5c_upgrade_while_running.log` | `qa/tmp/installer/logs/` | 2.0.2-era test: an update while a headless game ran from the install folder - Restart Manager could not close it, Setup aborted and rolled back before changing a file (the normal case, a visible game window, was not run) |
| `installer/r1_uninstall.log`, `installer/r2_install_unicode.log` | `qa/tmp/installer/review/logs/` | Independent review: a silent uninstall; an install into a folder path with spaces, an accent, ♥ and a Chinese character |
| `native_chain_202/*.chain.log`, `native_202_visible.chain_result.json` | `qa/tmp/bot/chain/native_202_*/` | Chapter Two from the save a 2.0.2 New Game wrote, packaged **2.0.2** exe: `visible` completes (1393 s, 0 script errors, 63 music cue changes; ran on the primary monitor, see the incident), `headless` stops in T23 (the bot got lost), `headless_resumeT23` completes from its S2 checkpoint, `headless_full` completes (1426 s) |
| `native_chain_202/native_202_visible_contact_sheet.jpg` + `.index.txt` | `qa/tmp/bot/chain/` | Every screenshot of the visible native run (incl. `s4/005`, Mochi filling the frame on the Bellhouse service stair - fixed in `36934ae`) |
| `fight_tips/replay_report.txt`, `fight_tips/fight_summary.json` | `qa/tmp/fighttips/` | Replays of the recorded fight-tip emissions through the real `hint_card.gd`, old 2.0.2 vs new: per fight, when each tip was emitted / shown / dropped and whether any fight tip outlived the fight (none with the new code) |
| `incident_primary_monitor/window_positions.txt` | generated from `qa/tmp` telemetry | The QA incident: 18 of 26 visible QA processes (every 1920×1080 one) had `window_pos` [0, 0] - the owner's primary monitor - although asked for at 1920,0; smaller windows landed at 1920,0; after the fix windows open at [1928, 8] |
| `incident_primary_monitor/native_202_visible_g*_focus_watchdog.json` | `qa/tmp/bot/chain/native_202_visible/` | Why nobody noticed: the old watchdog only watched keyboard focus (0 focus takes) |
| `incident_primary_monitor/after_fix_*_focus_watchdog.json` | `qa/tmp/hud_clutter/visible/`, `qa/tmp/cam_companion/visible1/` | After `bb79708`: the new watchdog fields, `on_primary_checks` 0 |
| `pcready_2.0.2/render_settings.txt`, `pcready_2.0.2/runs/*.result.json` | `qa/tmp/pcready/` | The different-PC readiness probes (packaged 2.0.2 exe): renderer fallbacks, small windows, the weak built-in GPU presets (`docs/ch2/DIFFERENT_PC_READINESS.md`) |
| `pcready_2.0.2/*.jpg` | JPEG re-encodes of `qa/tmp/pcready/runs/*.png` | Vulkan vs OpenGL fallback (Haven, Below) and the weak GPU at High / Medium / Low |
| `full_final4.log` | `qa/tmp/full_final4.log` (whole log) | Full automated suite on `8f5cbc0`: `==== 2712 tests, 0 failed, 949.9s ====`, `parse_all` passes, the known "8 ObjectDB instances were leaked at exit" (CH2-011), EXIT=0 |
| `f1_first_attempt/console.txt`, `play_summary.json`, `results.jsonl` | `qa/tmp/final203/fresh.console.txt`, `qa/tmp/final203/fresh/` | F1 first attempt (`playthrough.py --headless`): line 1 shows the **source project** run by the console binary, not the installed exe; 9 steps passed, then `home` failed: "StepFailed: no ['Grass', 'Fiber'] nearby" after two `walk_to stuck` events (bot navigation); no game errors |
| `f1_s0_rerun/console.txt`, `s0_result.json`, `results.jsonl`, `events.txt` | `qa/tmp/final203/s0.console.txt`, `qa/tmp/final203/s0/` | F1 re-run (`tools/qa/ch2/s0_fresh_c1.py --attempt 31`, headless, 2.0.3 sources): `status: completes`, 721.5 s, 21 checkpoints, `problems: []`, look kept, Brave Little Steps ribbon tied, Weaver 69.0 s (phases 1-3, 0 deaths, lowest HP 79), Chapter Two accepted (`ch2_waygate`), `continue_check` ok (9.8 s, no mismatches), `game_log_errors: []` |
| `f2_chain_native/console.txt`, `chain.log`, `chain_result.json`, `bugs.json` | `qa/tmp/final203/chain_native.console.txt`, `qa/tmp/final203/chain_native/` | F2: Chapter Two S1 -> END on the **installed** 2.0.3 exe (`processes`: `qa/tmp/final203/install/Hollowhaven.exe --headless`), from a copy of the 2.0.2 New-Game save: `status: completes`, `start_kind: native_v2`, 1509.3 s, 0 deaths, 0 script errors, 0 warnings, 64 music cue changes, `bugs.json` `[]`; END: Continue after relaunch 3.8 s, `same_items: true`, `chapter_two_complete: true`, `ch2_done: 20` |
| `installer/final203_silent_uninstall.log` | `qa/tmp/final203/logs/uninstall.log` | The 2.0.3 test install removed afterwards: silent uninstall, "Uninstallation process succeeded", "Removed all? Yes" |

What this folder does **not** prove: anything about her PC (nothing ran on a second PC), the installer wizard pages on screen,
SmartScreen / Smart App Control, real OS input, human play or playtime, how the music sounds, anything judged in motion, or the
performance of 2.0.1-2.0.3.
