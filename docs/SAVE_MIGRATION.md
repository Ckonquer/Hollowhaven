# Save migration: schema v2 (Chapter Two)

Owner: core-save module (A1). Contract: `docs/CHAPTER_TWO_SPEC.md` §3 and §8. Design: master prompt §2, §20.1-20.2.
Code: `game/autoload/save_system.gd`, `game/autoload/game_state.gd`, `game/src/core/inventory.gd`,
`game/src/core/chapter_log.gd`, `game/src/core/optional_log.gd`.

## 1. Files

The save folder is `%APPDATA%\Hollowhaven\saves` (`user://saves`), or whatever `--save-dir=<dir>` names.

| file | meaning |
|---|---|
| `slot1.json` | current save (`"format": "hollowhaven-save"`, `"version": 2`) |
| `slot1.bak.json` | the previous good save (rotated on every successful save) |
| `slot1.tmp` | a write in progress; a complete one is recovered after a crash |
| `slot1.corrupt-<unix>[-n].json` | a damaged main save, moved aside for inspection (never deleted) |
| `slot1.future-<ver>-<unix>[-bak\|-tmp][-n].json` | a save written by a NEWER game version, set aside only after the player confirmed New Game (never deleted) |
| `pre_v2_backup/slot1.v1-<unix>.json` | untouched copy of the Chapter-One (version 1) main save, made once before the first v2 write |
| `pre_v2_backup/slot1.bak.v1-<unix>.json` | untouched copy of the version-1 backup, same moment |

The write procedure is unchanged: serialise -> write `slot1.tmp` -> re-read and validate -> rotate the current file to
`.bak` (only if it is valid) -> rename the temp file into place. `settings.cfg` is not part of the save.

## 2. What schema v2 adds

`SaveSystem.SAVE_VERSION = 2`. Every new key is optional on read; `GameState.reset()` and `SaveSystem.migrate()` use
the same defaults (`GameState.v2_section_defaults()`).

| state key | default | notes |
|---|---|---|
| `schema` | `2` | informational |
| `appearance` | `GameState.LEGACY_LOOK_IDS` | the Chapter-One avatar (spec §8); `data/appearance.gd` holds the same `LEGACY_LOOK` |
| `wardrobe` | `{"owned": [], "palettes": [], "presets": [], "notice_shown": false, "show_armor": false}` | |
| `equipment` | `{"head": "", "body": "", "boots": "", "charm": ""}` | worn items are OUT of the backpack |
| `capacity` | `{"backpack": 32}` | the backpack array length always equals `capacity.backpack` (32/40/48) |
| `optional` | `{}` | `{goal_id: {"done": bool, "done_at": total_minutes}}` |
| `chapter2` | `{"accepted": false, "done": [], "baselines": {}}` | done steps by stable id; `accepted` mirrors flag `ch2_accepted` |
| `ledger` | `{}` | `{reward_id: total_minutes}` - rewards granted exactly once |
| `mastery` | three tracks at 0, `seen` lists, `legacy_credit: false` | owned by the mastery module; a recorded credit is never reset |
| `discovered` | `{}` | `{area_id: [landmark ids]}` |
| `trials` | `{}` | `{trial_id: {"clears", "best_seconds"}}` |
| `orphans` | `[]` | player-owned stacks with an item id this build does not know (see §4) |
| `stations` | `{}` | reserved (station queues live in `structures[uid].data`) |

Companion records gain `combat_mode` ("assist"), `skill_ready_at` (0.0), `home_spot` (null), `ribbon` (""),
`home_task` (""). Structure `data` may carry `slots` (upgraded chest), `tint`, `face`, `level`, `queue`/`output`.
`meta` in the file gains `chapter` (1 or 2); `meta.step`/`meta.step_title` come from `GameState.current_objective()`
(the Chapter Two step while that layer is active, else the legacy step; "Chapter complete" / "Chapter Two complete"
past the end).

Any top-level state key this build does not know is kept in `GameState.extra` and written back unchanged, so a
later patch never loses data by being loaded in this one. Unknown keys inside companion records, structures,
appearance, wardrobe, mastery, trials and capacity are kept the same way.

## 3. Migration rules (`SaveSystem.migrate`, v1 -> v2)

`migrate()` runs on every read of `slot1.json`, `slot1.tmp` and `slot1.bak.json` (Continue, the title's peek, the
temp-file validation of every save), so it is pure (returns a new dictionary, the argument is untouched),
deterministic, idempotent and cheap. It tolerates a dictionary without `state`. For `version < 2` it only ADDS:

* every missing schema-v2 section with its default (existing keys are never replaced);
* `capacity.backpack = max(32, length of the saved inventory)`;
* the five new companion keys with their defaults (existing values win; malformed records are left to the loader);
* the two legacy goals `opt_legacy_bond` / `opt_legacy_heartbloom` as done when the legacy log already completed
  `free_play` (`completed` has it, or `index >= 16`). This carry-over is silent: no reward, no toast.

It never touches legacy keys: structures (uid/type/area/pos/rot/data), chests and their order, crops, inventory
order, key pouch, hotbar, companions, flags, quest index/completed/baselines, lore, clock, counters, dropped items.
Optional goals whose state happens to be satisfied are NOT pre-marked: the optional log evaluates state after loading
and latches them normally. `GameState.from_dict()` still accepts version-1 state directly (every section optional,
type-checked, JSON floats normalised to ints where the runtime uses ints) and grants nothing.

## 4. Capacity and orphans

* `Inventory.resize(n)` only grows; `Inventory.reset_to(n)` (new game / before a load) empties and resizes.
* Loading sets the backpack size from `capacity.backpack` (and the saved array length) BEFORE the slots are read, so
  an upgraded backpack is never truncated. Chests use `max(definition slots, data.slots, saved length)`.
  `GameState.set_backpack_capacity(n)` and `GameState.set_storage_capacity(uid, n)` perform upgrades (grow only).
* A stack whose item id this build does not know is never dropped. It goes to `GameState.orphans` as
  `{"where": "inventory" | "storage:<uid>" | "equipment" | "key_items" | "dropped", "slot": int, "stack": {"id", "count"}}`
  (`dropped` entries also keep the full `record`), and is written back on save. When a later build knows the id again,
  the orphan returns to its slot (or anywhere in the same inventory; worn items to their slot). Chest contents saved
  under a structure this build does not treat as storage (unknown id, or a later build made it one), or under a uid
  whose structure record is missing, are kept verbatim and written back (their uids stay reserved).
  (`key_items` and `dropped` are additions to the three `where` values of spec §3.)

## 5. Rewards, Chapter Two layer and optional goals

* `GameState.grant_once(reward_id, items := {}, flags := [], message := "") -> bool` records the reward id FIRST,
  then sets flags, then gives items (a full backpack drops the rest as persistent pickups; an unknown item id is kept
  as an orphan), then notifies. It returns false and does nothing when the id is already in the ledger.
* The Chapter Two layer (`GameState.chapter2`, data `data/quests_ch2.gd`) stores completed steps by id and grants
  `rw_<step id>` through the ledger; the optional log (`GameState.optional_goals`, data `data/optional_goals.gd`)
  grants `rw_<goal id>`. Loading twice, re-evaluating, or a save that lost its done list can therefore never grant
  anything twice. The legacy quest chain (`data/quests.gd`, indices 0..15) is unchanged and keeps its own
  reward-once rule (`completed`).

## 6. The pre-v2 upgrade backup (spec §3.2)

Before the first version-2 write over version-1 files, SaveSystem copies the untouched v1 files byte for byte into
`<save_dir>/pre_v2_backup/`: `slot1.json` -> `slot1.v1-<unix>.json`, `slot1.bak.json` -> `slot1.bak.v1-<unix>.json`
(a recovered complete `slot1.tmp` is copied as `slot1.v1-<unix>.json`). It happens

* in `load_game()` as soon as the data to load came from a version-1 file (before anything is moved or written), and
* again as a guard in every save: if the current main or backup on disk is still version 1 and no upgrade backup
  exists (e.g. New Game over an old save without loading it), the copy is made first; if the copy fails the save is
  refused (`last_error` says so) and the v1 file stays untouched.

It is made only once per save folder: nothing is copied once the folder holds a `slot1.v1-*`, and a version-1
backup file is not copied again when a `slot1.bak.v1-*` exists (a torn main recovered from its backup leaves only
that copy; a version-1 main that shows up later is still copied). The game never deletes or rewrites these files.
`delete_test_saves()` removes them only for test folders.

## 7. Saves from a newer version (spec §3.3)

A well-formed save whose `version` is greater than 2 is not corrupt. `load_game()` refuses it IN PLACE:
`last_error = "This save was made by a newer version of Hollowhaven."`, `SaveSystem.blocked_by_future = true`,
nothing is moved, the older backup is NOT loaded instead, and nothing is written. The same holds when the main file is
missing or damaged and the temp or backup file is the newer one. The title keeps Continue visible but disabled with
that reason. Saving is refused while such a file would be replaced. Only when the player confirms New Game (the
confirmation names the newer save and says it is kept) does the title set `SaveSystem.replace_future_allowed`; the
next save then moves the newer file aside as `slot1.future-<ver>-<unix>.json` (never deleted) and the permission is
consumed. A newer-version backup or temp file next to a valid current main is simply set aside by the next save.

## 8. Rollback (return to the v0.9.1 build)

The archived pre-Chapter-Two build and source are in `Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\`
(`build\Hollowhaven-0.9.1-Windows.zip`, `source\`, hashes in `Desktop\Hollowhaven_Backups\pre_chapter2_SHA256.txt`).

1. Close the game completely.
2. Open the save folder (`%APPDATA%\Hollowhaven\saves`, or the `--save-dir` folder).
3. Move the current `slot1.json` and `slot1.bak.json` into a new folder such as `v2_kept\` (do not delete them:
   they hold any Chapter Two progress).
4. Copy `pre_v2_backup\slot1.v1-<unix>.json` to `slot1.json`. If there is a `pre_v2_backup\slot1.bak.v1-<unix>.json`,
   copy it to `slot1.bak.json`. Leave the `pre_v2_backup` folder itself as it is.
5. Unzip `Hollowhaven-0.9.1-Windows.zip` somewhere new and start it; Continue loads the Chapter One save.

Why the copies matter: v0.9.1 treats any version-2 file as corrupt, moves it aside as `slot1.corrupt-<unix>.json`
and falls back to the backup; after two v2 saves there is no v1 file left except the copies in `pre_v2_backup`.
To go forward again later, start the new build: it loads the v1 files, keeps the existing upgrade backup, and
migrates again (or put the files from `v2_kept\` back to continue the Chapter Two progress instead).

## 9. Verification

Tests (headless, bounded, only in `user://test_saves/`), from the repo root in Git Bash:

* `tools/test.sh save_v2` - all schema-v2 suites: `test_save_v2_migration` (migrate, statuses, newer versions,
  permission, upgrade backup, test hygiene), `test_save_v2_state` (sections, capacity, orphans, equip/unequip, ledger,
  discovery, tolerant loading, combined objective), `test_save_v2_chapter_log`, `test_save_v2_optional_log`,
  `test_save_v2_title`, `test_save_v2_matrix`.
* `tools/test.sh save`, `tools/test.sh core`, `tools/test.sh quests`, `tools/test.sh persistence`, `tools/test.sh parse_all`.

Migration matrix (MP §20.2): committed synthetic fixtures in `game/tests/fixtures/saves/` (`<name>.json` = slot1.json,
`<name>.bak.json` = slot1.bak.json; list in its `README.txt`), built from real GameState calls by
`game/tests/unit/ch2_save_fixtures.gd`:

| # | fixture | covers |
|---|---|---|
| 1 | `01_fresh_new_game` (+ no save at all) | fresh profile |
| 2 | `02_early_before_pets` | early Chapter One, since_start baseline |
| 3 | `03_mid_home_full_bag` | buildings, chests, crop, FULL backpack, waiting companion |
| 4 | `04_before_matron` | in the Below, lower-tier gear, key in pouch, below_respawn |
| 5 | `05_weaver_defeated` | Heartseed held, not returned |
| 6 | `06_interrupted_restoration` | ward_restored without chapter_one_complete: reconciled once |
| 7 | `07_c1_complete_free_play` | complete, free_play goals not done |
| 8 | `08_c1_complete_goals_done` | free_play done: legacy goals marked silently |
| 9 | `09_dense_home_overflow` | ~100 structures incl. a raised storey, 4 chests, crops, dropped overflow |
| 10 | `10_custom_save_dir` | custom `--save-dir` (backup lands next to it) |
| 11 | `11_current_schema_twice` | v2 save with Chapter Two progress loaded/evaluated repeatedly |
| 12 | `12a_malformed_main_good_bak`, `12b_future_main` | torn main + valid backup; newer main refused in place |
| + | `13_state_empty`, `14_stuck_dungeon_ward_restored`, `15_v2_unknown_ids` | defaults; legacy skip repair; orphans and unknown keys |
| real | `16_real_handoff_c1_complete` (+ torn-main variant), `17_real_release_below_silk` | files the SHIPPED v0.9.0 build wrote (QA bot playthroughs, byte-for-byte copies with their SHA-256 in `README.txt`; NOT Krystal's save): Chapter One complete at free_play (backup at `return` with the Heartseed), and a release run in the Below on `silk` with a dropped item |

For every scenario `test_save_v2_matrix` compares the canonical pre/post state (all fields above, allowing only the
documented additive changes), checks the upgrade backup bytes, the written v2 file, save->load stability, and that
evaluating, saving, loading and evaluating again grants nothing twice. `test_fixture_files_match_the_builders`
keeps the committed files in sync; regenerate them after an intentional change with
`cd game && ../tools/godot.sh --headless --path . res://tests/runner.tscn -- --filter=save_v2_matrix --write-fixtures`.

Integrity report (Python 3 standard library only):

```
.tools/pyenv/Scripts/python.exe tools/qa/save_integrity.py <v1 slot1.json> <v2 slot1.json> [--out report.json]
.tools/pyenv/Scripts/python.exe tools/qa/save_integrity.py --self-test
```

It prints a JSON report (`ok`, `preserved_mismatches`, `missing_v2_sections`, `allowed_changes`, file hashes and a
summary of each side) and exits 0 (preserved), 1 (a preserved field changed: failure) or 2 (unusable input). The matrix
test leaves each scenario's first v2 write in `%APPDATA%\Hollowhaven\test_saves\test_save_v2_matrix\migrated\<name>.v2.json`,
so the fixtures can be checked with e.g.
`save_integrity.py game/tests/fixtures/saves/09_dense_home_overflow.json "%APPDATA%/Hollowhaven/test_saves/test_save_v2_matrix/migrated/09_dense_home_overflow.v2.json"`.
For a real save: copy `slot1.json` to a scratch folder BEFORE starting the new build, run the new build (or the test
runner) with `--save-dir=<that scratch folder>`, load once, save once, then compare the copy with the new `slot1.json`.

**Personal-save verification: NOT RUN (blocked).** Development never touches `%APPDATA%\Hollowhaven\saves`; the archived
profile snapshot contains only `settings.cfg`. Verified so far: the synthetic fixtures and two real-build QA-bot saves
(the handoff's `save_chapter1_complete` sample and a release-build Below checkpoint, rows "real" above; both also pass
`save_integrity.py` against their migrated v2 output). Neither is Krystal's save. Do not call the migration verified
safe for Krystal's own save until the MP §20.1 gate (copy, hash, migrate the copy, integrity report) is done.
