# Save-integrity report — Hollowhaven 2.0.x (save schema v2)

Written 2026-09-28 for the 2.0.0 release (`dist/Hollowhaven-2.0.0-Windows.zip`, git `36e2e8a`). **Still current for 2.0.1 -
2.0.3:** `game/autoload/save_system.gd` - the file with the schema, the v1 -> v2 migration, the upgrade backup and the
save-side future-version check - is unchanged since 2.0.0 (`git diff 36e2e8a 8f5cbc0 -- game/autoload/save_system.gd` is empty). The
measurements below were made on 2.0.0 or earlier code; "2.0.x" below means any of these builds, today 2.0.3. Design: master prompt §2 and
§20.1-20.2. Implementation and rules: `docs/SAVE_MIGRATION.md` (the reference; this file is the evidence summary).

> **2.0.3 note:** Krystal has never played Hollowhaven and has no save; she starts with New Game, which writes a version-2 save
> directly (no migration). The block below and the gate in §7 only matter if a pre-2.0 (v0.9.x) Chapter One save ever turns up.
>
> **PERSONAL-SAVE VERIFICATION BLOCKED.** Krystal's own save is not on this PC: `%APPDATA%\Hollowhaven\saves` on the development
> PC is empty, and the immutable pre-Chapter-Two snapshot records the same (`Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\MANIFEST.txt`:
> "profile_snapshot/saves/ ... EMPTY. Krystal's personal save is not on this PC"). Everything below was measured on synthetic
> fixtures and on files written by the QA bot through the real v0.9.0 game. **The migration is a candidate, not verified safe for
> her particular save**, until the gate in §7 is run on a copy of her save.

## 1. What the migration guarantees (by design and by test)

Code: `game/autoload/save_system.gd` (`SAVE_VERSION = 2`, `migrate()`, `load_game()`, `_atomic_write()`), `game/autoload/game_state.gd`.

* **Additive only.** `migrate()` is pure, deterministic and idempotent; for a version-1 file it only adds the schema-v2 sections
  with their defaults, `capacity.backpack = max(32, saved length)`, five new companion keys, and marks the two legacy free-play goals
  done when the legacy log already finished `free_play` (silently, no reward). It never rewrites legacy keys: structures
  (uid / type / area / pos / rot / data), chests and their order, crops, inventory order, key pouch, hotbar, companions, flags, quest
  index / completed / baselines, lore, clock, counters, dropped items.
* **Nothing is lost.** Unknown top-level keys and unknown keys inside records are kept and written back; stacks with an unknown item
  id become `orphans` (same slot) and return when a later build knows them; backpacks and chests only grow.
* **Rewards once.** Chapter Two steps and optional goals pay through the reward ledger (`GameState.grant_once`, id recorded first);
  loading twice or re-evaluating can never pay twice.
* **Untouched copy first.** The first time a version-1 save is loaded (Continue) - or, as a guard, before the first version-2 write
  over version-1 files (e.g. New Game over an old save) - the untouched v1 files are copied byte for byte to
  `<save folder>\pre_v2_backup\slot1.v1-<unix>.json` (+ `slot1.bak.v1-<unix>.json`). Made once per folder, never deleted or
  rewritten by the game. If the copy fails, the v2 save is refused and the v1 file stays untouched.
* **Atomic writes** (unchanged from Chapter One): temp file -> re-read and validate -> rotate the good file to `.bak` -> rename.

## 2. Fixture matrix (MP §20.2) — automated, headless

Fixtures: `game/tests/fixtures/saves/` (list and hashes in its `README.txt`), built from real GameState calls by
`game/tests/unit/ch2_save_fixtures.gd`. Suite `test_save_v2_matrix` compares canonical pre/post state for every scenario (in memory,
no clock advance), checks the upgrade-backup bytes, the written v2 file, save -> load stability and that evaluate / save / load /
evaluate grants nothing twice. Result in the final full run `qa/tmp/full_final1.log` (2639 tests, 0 failed, 847 s): **all 22
matrix tests PASS**, plus `test_save_v2_migration` 17/17, `test_save_v2_state` 24/24, `test_save_v2_title` 3/3,
`test_save_v2_chapter_log` 23/23, `test_save_v2_optional_log` 11/11, `test_core_save` 25/25.

Independent re-check for this report: `tools/qa/save_integrity.py` (stdlib-only diff tool; `--self-test` = 12/12 cases ok) run
on 2026-09-28 against each fixture and the v2 file the final suite run wrote for it
(`%APPDATA%\Hollowhaven\test_saves\test_save_v2_matrix\migrated\<name>.v2.json`, 10:16). Reports: `qa/tmp/save_integrity_2.0.0/<name>.json`.

| # | MP 20.2 scenario | Fixture / test | Matrix test | save_integrity (v1 -> migrated v2) |
|---|---|---|---|---|
| 1 | Fresh profile / New Game cancelled | `01_fresh_new_game`, `01b` no save at all | PASS ×2 | ok, 0 mismatches (0 structures) |
| 2 | Early Chapter One, no pet | `02_early_before_pets` | PASS | ok, 0 (1 structure, 4 stacks) |
| 3 | Mid Chapter One, buildings, full bag, waiting companion | `03_mid_home_full_bag` | PASS | ok, 0 (16 structures, 2 chests / 5 stacks, 1 crop, 32 stacks) |
| 4 | Just before the Matron, lower-tier gear | `04_before_matron` | PASS | ok, 0 |
| 5 | Weaver defeated, Heartseed not returned | `05_weaver_defeated` | PASS | ok, 0 |
| 6 | Interrupted restoration | `06_interrupted_restoration` | PASS (reconciled once) | ok, 0 |
| 7 | Chapter One complete, optional goals not done | `07_c1_complete_free_play` | PASS | ok, 0 |
| 8 | Chapter One complete, optional goals done | `08_c1_complete_goals_done` | PASS (marked silently) | ok, 0 |
| 9 | Dense two-storey home, filled chests, crops, overflow | `09_dense_home_overflow` | PASS | ok, 0 (96 structures, 6 storage records / 36 stacks, 5 crops, 4 dropped) |
| 10 | Custom `--save-dir` | `10_custom_save_dir` | PASS | ok, 0 |
| 11 | Current schema loaded twice | `11_current_schema_twice` (v2) | PASS (nothing duplicated) | n/a (already v2) |
| 12 | Malformed main + valid backup; future-version main | `12a_malformed_main_good_bak`, `12b_future_main` | PASS ×2 (12b refused in place, backup NOT loaded instead) | n/a |
| + | Empty state; stuck dungeon step; unknown ids | `13_state_empty`, `14_stuck_dungeon_ward_restored`, `15_v2_unknown_ids` | PASS ×3 | 13, 14: ok, 0 |
| real | Files the shipped v0.9.0 game wrote (QA bot; NOT Krystal's) | `16_real_handoff_c1_complete` (+ torn-main variant `16b`), `17_real_release_below_silk` | PASS ×4 (incl. "real samples are untouched copies") | 16: ok, 0 (3 structures, 1 crop, 13 stacks, 47 flags, quest index 15); 17: ok, 0 |

"ok, 0" = exit 0, no preserved-field mismatch, no missing v2 section; the only differences are the documented additions (the v2
sections and the five companion keys).

## 3. Real QA-bot save migrations (a real save, the real game loop)

The start file for every natural bot run is a copy of fixture 16, the Chapter-One-complete save the v0.9.0 game wrote during the
handoff playthrough (sha256 `a72362e5…8c7b`). The bot drove the game headless through its QA input port (virtual keyboard / mouse,
no OS input layer, nothing rendered), on the source tree of the time (S1 `vfix1`: snapshot = HEAD `5cd7774` + the bug-fix round 1
files; the version string then was still 0.9.1). Not the packaged 2.0.0 exe.

| Evidence | What it shows |
|---|---|
| Upgrade backup (`qa/tmp/bot/s1/vfix1/saves/pre_v2_backup/`, `s1/diag_bak/...`, `chain/{dev3,run1,run2,run3,run4}/saves/pre_v2_backup/`) | `slot1.v1-<unix>.json` sha256 `a72362e5…8c7b` = the original, byte for byte; with a v1 backup present (`diag_bak`) `slot1.bak.v1-*` = `db6e09cb…2878`, also identical |
| S1 save right after Continue (`s1/vfix1/integrity_after_migration.json`) | 0 missing sections, 28 allowed changes; 5 strict differences, all from the 2.6 s of game clock between Continue and the save: `total_minutes` +2.64, `stats/play_seconds` +2.64, player y +0.0002 m and yaw +7e-9 rad (float settle), and `depleted/stone_4` expiring (its respawn time 1139.55 passed at 1141.22). Structures 3 = 3 (every uid / position), crop, 13 stacks, key pouch, companions (Lumi following, Mochi / Pebble at home), 47 flags, quest index 15: identical |
| S1 final save after play (`s1/vfix1/integrity_final.json` + `s1_result.json`) | 29 differences, **all 29 classified "explained by play", 0 unexplained** (new Chapter Two flags, gathered stones, inventory from gathering, area / position, Lumi bond XP and zones); structures, crop and companion records unchanged; the home's three structures found in place (`moved_m` 0.0) |
| Relaunch + Continue (S1, chain `END`) | Continue resumes the same save; the four completed natural chain runs (`chain/dev3`, `run2`, `run3`, `run4`): `same_items: true`, chapter complete, 20/20 Chapter Two steps, after "Save & Quit" from the pause menu |
| Reward-once after relaunch (S4 `vfix_full`, chain) | relaunch shows 20/20 steps and the same items; no double rewards (`qa/tmp/bot/BUGS_MERGED.md`, `s4/vfix_full/s4_result.json` `relaunch.same_items_as_before_quit`) |

Not covered by the real saves: chests (the real Chapter-One-complete save has none - chest migration is covered by fixtures 3 and 9
only), dense two-storey homes (fixture 9 only), and before / after screenshots of a home (the bot runs were headless).

## 4. Save / quit / resume in the new places

| Case | Evidence | Kind |
|---|---|---|
| Save & Quit -> Continue in the Reach (quarry) | S2 (`s2/vfix1`), chain S2 | bot (S2 from a diagnostic fixture; chain natural) |
| Pause-menu Save & Quit after the finale -> relaunch | S4 `vfix_full`, chain `END` | bot |
| Home rests (bed save) between districts | chain T23 / T34 (`sleep_msgs: journey saved`) | bot, natural |
| Echo Trials never save; a pending repeat gift paid once across a reload | `test_trials_*` (31 tests) | auto |
| Expedition resumes through the real SaveSystem | `test_expeditions_*` | auto |
| Round trips old + new areas in one save | `test_flow_ch2_roundtrip` (3) | auto |
| Choir death / reset | S4 `diag_reset` (diagnostic fixture) | bot |
| Interruption during a write | atomic-write / `.tmp` recovery / corrupt-main tests (`test_core_save`), failed upgrade backup refuses the write (`test_save_v2_migration`) | auto only - **no real process kill during a write was done** |
| Manor / Works checkpoint Continue with a real window, OS input | — | **not done** |

## 5. Upgrade backup on the player's PC

When Krystal first presses Continue in a 2.0.x build, the game copies her untouched Chapter One files to
`%APPDATA%\Hollowhaven\saves\pre_v2_backup\slot1.v1-<unix time>.json` (and `slot1.bak.v1-<unix time>.json` if a backup existed).
The game never deletes or rewrites them. Tell her not to delete that folder.

## 6. Future-version rule

A well-formed save with `version > 2` is not corrupt: 2.0.x refuses it in place (Continue shown but disabled, "This save was made by
a newer version of Hollowhaven."), moves nothing, does NOT fall back to an older backup, writes nothing. Only an explicit New Game
confirmation (which names the newer save and says it is kept) sets it aside as `slot1.future-<ver>-<unix>.json` - never deleted.
Tests: `test_save_v2_migration.test_future_*`, `test_save_v2_title.*`, matrix `12b`.

## 7. The personal-save gate (still to do, on a COPY)

1. Close the game. Copy `%APPDATA%\Hollowhaven\saves\slot1.json` (and `slot1.bak.json`) from her PC to a scratch folder, e.g.
   `D:\hh_gate\saves\`; record `certutil -hashfile slot1.json SHA256` (never work in her real folder).
2. Run the current 2.0.x build (2.0.3) on the copy only: `Hollowhaven.exe -- --save-dir=D:\hh_gate\saves`, press Continue, stand still, Pause > Save Game,
   quit.
3. Compare: `.tools/pyenv/Scripts/python.exe tools/qa/save_integrity.py <original copy of slot1.json> D:\hh_gate\saves\slot1.json --out gate_report.json`
   (exit 0 = preserved; with a few seconds of play expect only clock / float / respawn-timer differences as in §3).
4. Check that `D:\hh_gate\saves\pre_v2_backup\slot1.v1-*.json` has the same SHA-256 as the original.
5. Look at her home in the copy (structures, chests, crops, pets). Only then call it verified for her save.

## 8. Rollback (return to v0.9.1)

Never open a v2 save with the old exe: v0.9.1 treats a version-2 file as corrupt, moves it aside as `slot1.corrupt-<unix>.json` and
falls back to the backup - after two v2 saves only `pre_v2_backup` still holds a v1 file.

1. Close the game completely.
2. Open `%APPDATA%\Hollowhaven\saves` (or the `--save-dir` folder).
3. Move the current `slot1.json` and `slot1.bak.json` into a new folder such as `v2_kept\` (keep them: they hold the Chapter Two
   progress).
4. Copy `pre_v2_backup\slot1.v1-<unix>.json` to `slot1.json`; if there is a `pre_v2_backup\slot1.bak.v1-<unix>.json`, copy it to
   `slot1.bak.json`. Leave `pre_v2_backup\` itself as it is.
5. Unzip the archived build `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\build\Hollowhaven-0.9.1-Windows.zip`
   (sha256 `b4cab2cc…0e95`, listed in `Desktop\Hollowhaven_Backups\pre_chapter2_SHA256.txt`) to a new folder and start it; Continue
   loads the Chapter One save. (Source of that build: `...\source\hollowhaven_b760f79.bundle` / `hollowhaven_source_b760f79.zip`.)

To go forward again: start the 2.0.x build; it migrates the v1 files again (the existing upgrade backup is kept), or put the files from
`v2_kept\` back to continue the Chapter Two progress.
