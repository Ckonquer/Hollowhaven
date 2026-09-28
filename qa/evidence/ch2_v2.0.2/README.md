# Evidence — Hollowhaven 2.0.2 (2026-09-28)

Small committed copies of the 2.0.2 release evidence; full run folders stay in `qa/tmp/` (gitignored). Build under test:
`dist/Hollowhaven-2.0.2-Windows.zip` (SHA-256 `2F77F52F219F5452E4140FD95DA25895C94E7C59E7A20231143ED564E4907FA8`), git `991014c`.
2.0.2 = 2.0.1 + one game fix (`a31e717`, boss-fight tips in `game/src/ui/hud/hint_card.gd`). Report: `QA_REPORT.md` §12.
Every bot run used **virtual input through the game's QA port** (not OS input, not a human).

| File | Copied from | What it shows |
|---|---|---|
| `full_final3.log` | `qa/tmp/full_final3.log` (whole log) | Full automated suite on the tree committed as `a31e717` (~13:52-14:07): `==== 2679 tests, 0 failed, 890.7s ====`, the 7 new `test_hint_card_fight_tips` tests PASS, `parse_all` passes, then the known "8 ObjectDB instances were leaked at exit" (CH2-011), EXIT=0 |
| `after_bump_save_suite.json` | `qa/tmp/test_results_save.json` (14:07) | Save filter: 128 tests, 0 failed (6.0 s) |
| `after_bump_audit_suite.json` | `qa/tmp/test_results_audit.json` (14:11) | Audit filter: 83 tests, 0 failed (134.5 s). Both filters ran after the version strings were edited and before `991014c` was committed (14:11:57); the full suite was not re-run after the bump |
| `build_v202_tail.log` | last 8 lines of `qa/tmp/build_v202.log` (colour codes stripped) | Export done, the 2.0.1 zip moved to `builds/superseded/`, the 2.0.2 zip built (111.1 MB) with the SHA-256 above. Built with `tools/build_release.ps1 -SkipTests` (the log has no test output); EXIT=0 was captured in the lead's shell, not in this log |
| `v1_fresh/console.txt` | `qa/tmp/e2e/final_202_fresh.console.txt` | **V1** (`tools/qa/playthrough.py --second-monitor --exe builds/Hollowhaven/Hollowhaven.exe`): the packaged 2.0.2 exe on the second monitor (1920x1080 at 1920,0, not muted), scratch save dir; every step with its duration; 21 of 21 PASS in 697.2 s, no PROBLEM lines, Weaver Matron 63.6 s, the foreground-watchdog line; EXIT=0 |
| `v1_fresh/play_summary.json` | same run | `problems: []`, `game_log_errors: []`, notes (`brave_steps: {ribbon_tied: true, mochi_follows: true}`, look kept, boss, Chapter Two accepted at `ch2_waygate`), final state |
| `v1_fresh/results.jsonl` | same run | One PASS line per step (the `"kind": "interactive"` label is the harness default; `"input": "virtual (qa_input, second monitor)"`) |
| `v1_fresh/play_events.txt` | same run | In-game events from telemetry with game time (23 music-director changes) |
| `v1_fresh/play_focus_watchdog.json` | same run | `{"checks": 2669, "game_had_focus": 0, "handed_back": 0}` |
| `v1_fresh/contact_sheet.jpg` | made from all 42 `play_*.png` | Every V1 screenshot as a thumbnail, in order |
| `v1_fresh/play_002_meet_krystal_chosen.jpg` | JPEG (q88, full 1920x1080) of the run's PNG | "Meet Krystal" with the chosen look |
| `v1_fresh/play_030_mochi_ribbon.jpg` | " | Right after the Comfort Ribbon was tied: Mochi is the follower in the HUD portrait (the tie itself is recorded in `play_summary.json`) |
| `v1_fresh/play_035_silk_and_boss.jpg` | " | The Weaver Matron fight |
| `v1_fresh/play_037_restoration.jpg` | " | "Chapter One Complete" |
| `v1_fresh/play_038_ending_credits.jpg` | " | The ending card |
| `v1_fresh/play_039_ending.jpg` | " | **The fix on screen**: back in the Haven after the ending the HUD shows only the "When you're ready - The Ward Stone has something new to say" card, the "Read the Ward Stone" prompt and "Journey saved"; no stale Weaver tip (compare `qa/evidence/ch2_v2.0.1/run_b_fresh/play_038_ending.jpg`) |
| `v1_fresh/play_040_ward_stone_choice.jpg` | " | The Ward Stone offering Chapter Two |
| `v1_fresh/play_041_accept_ch2.jpg` | " | Chapter Two accepted |
| `v2_finale/chain.log` | `qa/tmp/bot/chain/final_202_s4/chain.log` | **V2** (`tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe --from S4 --start-save qa/tmp/bot/chain/final_201/checkpoints/T34_end`): the Chapter Two finale on the packaged 2.0.2 exe, headless, resumed from a save the 2.0.1 game wrote in Run A; S4 OK in 883.4 s, END OK in 8.8 s |
| `v2_finale/chain_result.json` | `qa/tmp/bot/chain/final_202_s4/chain_result.json` | `"status": "completes"`, `resumed_from: "S4"` (not natural from Chapter One), 900.7 s, 0 deaths, 0 script errors, 0 warnings, 32 music cue changes; `end_check`: saved before quit, Continue in 2.9 s, `same_items: true`, `chapter_two_complete: true`, `ch2_done: 20`; processes = the packaged exe with `--headless`; 0 of 36 screenshots (headless) |
| `v2_finale/console.txt` | `qa/tmp/bot/chain/final_202_s4.console.txt` | The bot's full console (Crossing 74.0 s, Choir 412.7 s, telemetry messages), the segment table and `EXIT=0` |
| `v2_finale/bugs.json` | `qa/tmp/bot/chain/final_202_s4/bugs.json` | `[]`: no bugs filed |

What this folder does **not** prove: the Crossing / Choir / Velour / Warden tip behaviour on screen (V2 is headless), real OS input, human play or playtime, how the music sounds, anything judged in motion,
performance of 2.0.1 / 2.0.2 (not re-profiled), or Krystal's own save (PERSONAL-SAVE VERIFICATION BLOCKED). Earlier evidence:
`qa/evidence/ch2_v2.0.1/` (Run A / Run B on 2.0.1) and `qa/evidence/ch2_v2.0.0/`.
