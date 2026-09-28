# Evidence — Hollowhaven 2.0.1 (2026-09-28)

Small committed copies of the 2.0.1 release evidence. The full run folders stay in `qa/tmp/` (gitignored). Build under test:
`dist/Hollowhaven-2.0.1-Windows.zip` (SHA-256 `8017AF7123204BA303EE9E08D8B61A47DBB01CAD87EBAB6E5F311465175857FE`), git `da94714`.
Every bot run used **virtual input through the game's QA port** (not OS input, not a human). Report: `QA_REPORT.md` §11.

| File | Copied from | What it shows |
|---|---|---|
| `full_final2.log` | `qa/tmp/full_final2.log` (whole log) | Full automated suite on the tree committed as `c709db8`: `==== 2672 tests, 0 failed, 888.5s ====`, `parse_all` passes, then the known "8 ObjectDB instances were leaked at exit" (CH2-011), EXIT=0 |
| `build_v201_tail.log` | last 12 lines of `qa/tmp/build_v201.log` (colour codes stripped) | The export finished, the 2.0.0 zip was moved to `builds/superseded/`, the 2.0.1 zip was built (111.1 MB) with the SHA-256 above, EXIT=0 |
| `run_b_fresh/console.txt` | `qa/tmp/e2e/final_201_fresh.console.txt` | **Run B** (`tools/qa/playthrough.py --second-monitor --exe builds/Hollowhaven/Hollowhaven.exe`): the packaged 2.0.1 exe launched on the second monitor (1920x1080 at 1920,0, not muted), scratch save dir; every step with its duration; 21 of 21 steps ok in 658.3 s; the Weaver Matron summary (64 s, phases 1-2-3, 0 deaths); the foreground watchdog line; EXIT=0 |
| `run_b_fresh/play_summary.json` | same run | Per-step results, the one bot-filed problem (Brave Little Steps stopped at `tie_ribbon`: the panel that opened was Lumi's), notes (look kept, boss, Chapter Two accepted at `ch2_waygate`), final state, `game_log_errors: []` |
| `run_b_fresh/results.jsonl` | same run | One line per step (PASS). Its `"kind": "interactive"` label is the harness default; the same lines say `"input": "virtual (qa_input, second monitor)"` |
| `run_b_fresh/play_events.txt` | same run | In-game events from telemetry (quests, hints, notifications, 20 music-director changes) with game time |
| `run_b_fresh/play_focus_watchdog.json` | same run | `{"checks": 2523, "game_had_focus": 0, "handed_back": 0}`: the game never owned the OS foreground window |
| `run_b_fresh/contact_sheet.jpg` | made from all 41 `play_*.png` of the run | Every Run B screenshot as a thumbnail, in order |
| `run_b_fresh/play_002_meet_krystal_chosen.jpg` | JPEG (q88, full 1920x1080) of the run's PNG | "Meet Krystal" with the chosen look |
| `run_b_fresh/play_020_home.jpg` | " | The Haven with bed and crop plot placed |
| `run_b_fresh/play_034_silk_and_boss.jpg` | " | The Weaver Matron fight (Chapter One boss) |
| `run_b_fresh/play_036_restoration.jpg` | " | "Chapter One Complete" |
| `run_b_fresh/play_037_ending_credits.jpg` | " | The ending card ("Continue exploring your Haven") |
| `run_b_fresh/play_038_ending.jpg` | " | Back in the Haven after the ending - **shows a stale Weaver tip** ("It is smothering a brazier!") on the HUD: a 2.0.1 finding, not fixed in 2.0.1 |
| `run_b_fresh/play_039_ward_stone_choice.jpg` | " | The Ward Stone offering Chapter Two |
| `run_b_fresh/play_040_accept_ch2.jpg` | " | Chapter Two accepted ("Chapter Two" title card) |
| `run_a_chain/chain.log` | `qa/tmp/bot/chain/final_201/chain.log` | **Run A** (`tools/qa/ch2/chain.py --headless --exe builds/Hollowhaven/Hollowhaven.exe`): the natural Chapter Two chain on the packaged 2.0.1 exe, headless, from the real Chapter-One-complete save; per-segment result lines |
| `run_a_chain/chain_result.json` | `qa/tmp/bot/chain/final_201/chain_result.json` | `"status": "completes"`, `natural: true`, 1534.8 s; per segment (S1 65.8, S2 234.7, T23 87.1, S3 198.4, T34 50.4, S4 887.1, END 8.8 s): 0 deaths, 0 script errors; 63 music cue changes; `end_check`: Save & Quit, relaunch, Continue in 2.8 s, `same_items: true`, Chapter Two complete (20 steps); the launched processes (the packaged exe with `--headless`); 0 of 123 screenshots (headless, nothing rendered) |
| `run_a_chain/console.txt` | `qa/tmp/bot/chain/final_201.console.txt` | The bot's full console for Run A (fights, steps, eats, telemetry messages), the segment summary table and `EXIT=0` |
| `run_a_chain/bugs.json` | `qa/tmp/bot/chain/final_201/bugs.json` | `[]`: the chain filed no bugs in this run |

What this folder does **not** prove: anything about real OS input, human play or playtime, how the music sounds (nobody
listened), how things look in motion, performance of 2.0.1 (not re-profiled), or Krystal's own save (PERSONAL-SAVE VERIFICATION
BLOCKED). Run A is headless: nothing was rendered, so it has no screenshots. The 2.0.0 evidence (visible packaged chain run, perf
summaries) is in `qa/evidence/ch2_v2.0.0/`.
