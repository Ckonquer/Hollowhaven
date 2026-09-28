# Hollowhaven — Technical handoff for Part 2 (Chapter Two)

Companion to `Hollowhaven_Chapter1_Bible.md` (story/design content). This file covers engine, code, IDs,
save format and extension constraints. It describes the source in the accompanying source ZIP (the git
commit is named in the ZIP file name and in §9). Verification kinds: **[run]** executed, **[test]** covered
by automated tests, **[code]** read in source only. Every claim in an earlier draft was independently
re-checked against the code by two verifier agents; their corrections are included.

**Build provenance (important):** the full real-input playthrough (QA_REPORT §3.1) was done on the release
built from commit **0dde10e** (v0.9.0). Later commits changed the credits text ("For Krystal / from Ali"),
added documentation, and applied fixes from a headless code audit; those later builds were verified by the
automated test suite only, not by another real-input playthrough.

---

## 1. Engine, project structure, build / run / test

* **Engine**: Godot **4.7.2-stable** (official build, SHA-512 verified), **GDScript** only (no C#),
  renderer **Forward+** (Vulkan), physics **Jolt**. Target: Windows x86_64. [run]
* **Toolchain is project-local** (git-ignored `.tools/`): Godot editor + Windows export templates in
  `.tools/godot/` (self-contained mode), Python 3.12 venv in `.tools/pyenv/` (numpy/scipy/pillow; used to
  regenerate audio and the icon; the QA bot scripts in `tools/qa/` use only the standard library).
* **Warning — shared user folder:** running from source *without* `-- --save-dir=<folder>` uses the same
  `%APPDATA%\Hollowhaven\saves` as the release build Krystal plays (even with the self-contained editor), and
  the test runner writes to `%APPDATA%\Hollowhaven	est_saves`. Always pass `--save-dir` for dev runs so her
  save is never touched. Reinstall: `powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1`.
* **Why not Unity**: Unity 6 Personal can only be activated by signing in to Unity Hub; the build was done
  unattended, so Godot (MIT, no account) was used.

```
Hollowhaven/
  game/                      Godot project (project.godot)
    autoload/                global singletons: events, settings, item_db, game_state, save_system, audio, game, debug
    data/                    data-driven definitions: items, recipes, structures(+crops), creatures(+lines),
                             enemies, quests, horror_events, world_layout
    scenes/                  boot.tscn, title.tscn, surface.tscn, below.tscn (+ boot.gd)
    src/art/                 palette, material factory (toon + outlines), procedural mesh kit
    src/core/                inventory.gd, quest_log.gd
    src/player/ camera/      player controller, avatar, interaction probe, camera rig
    src/building/ crafting/ farming/   build mode, placement rules, structures, crafting, crops
    src/companions/          Mochi/Pebble/Lumi visuals + AI + spawner
    src/combat/ enemies/     health, melee, hit fx, Brambling, Gloomling, Weaver stalker, boss, braziers, spawners
    src/world/surface/       Hollowhaven Woods (terrain, water, sky, vegetation, landmarks, Ward Stone, mine entrance)
    src/world/below/         The Below (layout data, rooms, props, checkpoints, gate/key/lift, authored moments, lore)
    src/world/common/        shared resource_node.gd, world_item.gd, fx
    src/horror/              horror director (core logic + node + event runner + silhouettes)
    src/ui/                  UI root, HUD, panels, screens, title screen, theme, icon factory
    src/qa/                  read-only QA telemetry (only active with --qa-telemetry)
    shaders/                 toon/outline + surface_* + below_* shaders
    assets/audio/            154 generated WAVs (+ .import settings); assets/fonts/ (OFL fonts)
    tests/                   test runner, test base, unit tests (tests/unit/test_*.gd), preview/arena tools
  game/tests/gate/           the first toolchain-gate scene; game/tests/tools/dump_licenses.gd (used by the build)
  tools/                     build_release.ps1, setup_toolchain.ps1, godot.sh, test.sh, parse_check.sh,
                             winctl.ps1 (OS input helper), audio/ (sound & music synthesis), art/ (icon),
                             qa/ (real-input playthrough bot: hhbot.py, session.py, playthrough.py, persistence.py)
  qa/evidence/               committed test evidence (toolchain gate, release playthrough screenshots/logs)
  docs/                      ARCHITECTURE.md (code contracts), INSTALL_LOG.md, player/How to Play.txt,
                             Hollowhaven_Chapter1_Bible.md, this file
  GAME_SPEC.md PROJECT_STATE.md QA_REPORT.md KNOWN_ISSUES.md THIRD_PARTY_NOTICES.md AGENTS.md README.md
```

**Commands** (repo root, Git Bash) [run]:
| Task | Command |
|---|---|
| Install toolchain | `powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1` |
| Import assets (fresh checkout; needed once) | `tools/godot.sh --headless --path game --import` |
| All tests (headless, ~5 min) | `tools/test.sh` · one area: `tools/test.sh <filter>` · compile check: `tools/parse_check.sh res://src/<dir>` |
| Run from source (windowed) | `tools/godot.sh --path game --resolution 1600x900 -- --windowed` |
| Debug jump into an area (always starts a NEW game) | `... -- --windowed --area=surface\|below [--spawn=<id>] [--give=item:n] [--flags=a,b] [--befriend=mochi,lumi:follow]` (debug builds only) |
| Open an existing save directly | debug builds: `... -- --windowed --load-save --save-dir=<folder>`; release: `Hollowhaven.exe -- --save-dir=<folder>` then Continue |
| Open in the Godot editor (not exercised during development — everything was done from code/CLI) | run `.tools/godot/Godot_v4.7.2-stable_win64.exe`, open `game/project.godot` |
| Release build + ZIP | `powershell -ExecutionPolicy Bypass -File tools/build_release.ps1` (add `-SkipTests` to skip tests) → `builds/Hollowhaven/Hollowhaven.exe` (PCK embedded) + `dist/Hollowhaven-<ver>-Windows.zip` |
| Real-input playthrough (needs the desktop) | `.tools/pyenv/Scripts/python.exe tools/qa/playthrough.py --exe builds/Hollowhaven/Hollowhaven.exe --out qa/tmp/e2e/run` |
| Regenerate audio | `.tools/pyenv/Scripts/python.exe tools/audio/generate_all.py` then re-import |

Coding rules (enforced by review, see `docs/ARCHITECTURE.md`): no `class_name` (scripts reference each
other via `preload`/`load` paths), scripts build their own child nodes in code (no hand-authored scenes except
the four in `scenes/`), typed GDScript with tabs, all persistent state goes through `GameState`, cross-module
messages via the `Events` signal bus, data in `data/*.gd`, debug features gated by `Debug.is_cheat_allowed()`.

---

## 2. What is implemented and playable (vs. only planned)

**Implemented and played end-to-end with real input on the packaged release (commit 0dde10e)** [run]: see
`QA_REPORT.md` §3.1. The full content list (world, locations, systems, companions, enemies, items, recipes,
progression) is in `Hollowhaven_Chapter1_Bible.md` §3–§8; all of it exists in code and data. Automated
tests: see §9 for the suite result of the exact commit in the ZIP.

**Planned but NOT done / not verified**:
* No human has **listened** to the audio (all generated; numbers checked only).
* Scripted **persistence playthrough on the release build** was started but stopped (owner needed the PC);
  save/load is covered by automated tests and by Continue-from-save during development runs.
* No formal 1080p fullscreen performance profile (windowed runs: 270–600 FPS on an RTX 4090).
* Arachnophobia visuals were inspected during module development, not re-inspected on the final build.
* Not built: gamepad support (PROJECT_STATE lists keyboard/gamepad inventory navigation as a possible next
  step), multiple save slots, localisation, Chapter Two (only story hooks and this handoff exist).
* The manual pause-menu **Save** was not exercised in the release playthrough (the bot's final step failed
  to find the button but reported success — a bot bug); manual save is covered by UI code/tests only.

---

## 3. The complete Chapter 1 objective sequence

`game/data/quests.gd` → `STEPS` (linear; one current step). Ids in order:

| idx | id | title | objectives (type: target) | on_complete |
|---|---|---|---|---|
| 0 | `wake` | A Dim Haven | flag `read_ward_intro` | |
| 1 | `gather_basics` | Gather Supplies | item wood 3, stone 2, fiber 2 | |
| 2 | `craft_axe` | A Proper Tool | item `stone_axe` 1 | |
| 3 | `chop` | Timber! | counter `trees_felled` +2 since start; item wood 10 | |
| 4 | `workbench` | A Place to Work | placed `workbench` 1 | |
| 5 | `mochi` | A Timid Friend | befriended `mochi` | give `sweetroot_seeds` ×3 |
| 6 | `pebble` | Something Stuck | item `stone_pickaxe` 1; befriended `pebble` | give `copper_ore` ×2 |
| 7 | `home` | Make It Home | placed `bed` 1; placed `crop_plot` 1; counter `crops_planted` ≥1 | |
| 8 | `lumi` | Lights in the Ruin | flag `ruin_cleared`; befriended `lumi` | |
| 9 | `prepare` | The Ward Remembers | flag `read_ward_warning`; item `lantern` 1; item_any [`berry_snack`,`hearty_stew`,`glowcap_skewer`] 2 | |
| 10 | `descend` | The Hollow Mine | flag `mine_opened`; flag `entered_below` | |
| 11 | `old_mine` | The Old Mine | item `foreman_key` 1 | |
| 12 | `deeper` | Deeper Still | flag `reached_silk_hollows` | |
| 13 | `silk` | The Silk Hollows (alt: The Pale Hollows) | item `heartseed` 1 | |
| 14 | `return` | Bring Back the Light | flag `ward_restored` | give `haven_banner` ×1; flag `chapter_one_complete` |
| 15 | `free_play` | Krystal's Haven | counter `max_bond` ≥5; placed `heartbloom_lamp` 1 | step has data key `"optional": true` (tracker/journal show "OPTIONAL GOALS"); QuestLog still requires both to complete it |

Note: the Bible's quest table numbers steps 1–16; the code index here is 0–15 (Bible step 16 = index 15).

**Spider encounter → heart → light stone → ending** (code path) [run][code]:
1. **Silk Hollows stalker** (`src/enemies/stalker.gd`, spawned by `below_world.gd` on authored ceiling routes;
   not spawned once `weaver_defeated`): the authored intro `moment_silk_intro` shows it recoil from the lantern;
   it may ambush if Krystal lingers in darkness (rattle warning; lantern/dodge/break line of sight). It cannot be
   killed there.
2. **Boss**: entering the Heartseed Chamber starts the fight (`below_world.gd` room change → `weaver_boss.gd`
   `start_fight()`, also a proximity check). Braziers (`src/enemies/boss_brazier.gd`, need the `lantern` item)
   scorch it off its ceiling anchors. At 0 HP: shriek, ~1.4 s pause, then it rises into the ceiling crack
   (~2.7 s tween); only then (`_finish_defeat`) flag `weaver_defeated` is set, `Events.boss_defeated
   ("weaver_matron")` fires and the Heartseed pickup is created ("Take the Heartseed" →
   `GameState.give_item("heartseed", 1)`, key pouch). If `weaver_defeated` is set, the seed isn't owned and
   `ward_restored` is false, the pickup is re-created on load. The lift cages (`below_lift.gd`) work once
   `weaver_defeated` is set. **Nothing is saved between the defeat and the next lantern/area change.**
3. **Return**: surface `src/world/surface/ward_stone.gd` shows "Return the Heartseed" whenever the seed is held
   and `ward_restored` is false → `Game.complete_chapter()` (`game/autoload/game.gd`): takes the Heartseed,
   cutscene on, sets `ward_restored`. **One frame later** the deferred quest evaluation completes step `return`
   (Haven Banner, flag `chapter_one_complete`, index → 15, `heartbloom_lamp` recipe becomes known, "Goal
   complete" toasts) — i.e. at the *start* of the cutscene. Then `area.play_restoration()` (~10 s),
   companions `react("celebrate")`, `Events.chapter_completed` (no listeners), `ui.show_ending()` (fixed Chapter
   One card + scrolling credits "For Krystal / from Ali" + "Continue exploring your Haven"), cutscene off,
   a re-check of quests (no-op), 0.5 s, `SaveSystem.save_game()`. **Quitting during the ~10 s restoration or the
   credits leaves the previous save (Heartseed still held, `ward_restored` false), so the ending replays.**
4. **Afterwards the game stays playable** in free play at the Haven — observed in the release playthrough
   (mode "playing", quest `free_play`, surface) [run]. Code-verified [code][test]: the restored look is applied
   on every surface load when `ward_restored`; the `heartbloom_lamp` recipe is gated by `unlock:
   "ward_restored"`; crop growth ×1.5 after `ward_restored`; the mine stays enterable (no quest gating), with no
   boss/stalker once `weaver_defeated`.

---

## 4. IDs and flags

**Scenes / areas**: `res://scenes/boot.tscn` (main scene → `Game.boot()`), `title.tscn`, `surface.tscn`
(area id `surface`), `below.tscn` (area id `below`). `Game.AREAS` maps area ids to scenes; a debug-only
`arena` test area exists. Travel: `Game.change_area(area_id, spawn_id)` (autosaves on arrival).
The Below's rooms/zones are data in `src/world/below/below_layout.gd` `ROOMS` (zones `mine`, `ruins`, `silk`,
`boss`; e.g. `arena`, `arena_way`, `lift_recess` → boss; `antechamber`, `webbed`, `nursery` → silk; `shrine` →
ruins). Lift roles: the chamber cage rides up to `lift_bottom` (Mine Landing); the landing cage rides down to
`lift_chamber`.

**Spawn ids** — surface: `haven_start`, `haven_respawn`, `mine_exit`, `companion_wild_mochi|pebble|lumi`,
`companion_home_mochi|pebble|lumi`, `mine_threshold`, `bed` (registered by a slept-in bed at runtime).
Below: `mine_entry`, `cp_landing`, `cp_office`, `cp_shrine`, `cp_arena`, `lift_bottom`, `lift_chamber`.

**Item ids** (stable, used in saves): wood, stone, fiber, berries, copper_ore, sweetroot_seeds, sweetroot,
shiny_pebble, glowcap, silk, echo_shard, stone_axe, stone_pickaxe, copper_sword, lantern, berry_snack,
hearty_stew, glowcap_skewer, workbench, storage_chest, bed, crop_plot, wood_floor, wood_wall, wood_window,
wood_doorway, wood_roof, fence, lantern_post, flower_pot, rug, table, stool, pebble_cairn, echo_chime,
heartbloom_lamp, haven_banner; key items (`quest: true`): **foreman_key**, **heartseed**. Structure ids = the
placeable item ids; crop id `sweetroot`. Creature ids: mochi, pebble, lumi. Enemy ids: brambling, gloomling,
weaver, weaver_matron.

**Flags present in the copied Chapter-1-complete save** (§8): progress `read_ward_intro, read_ward_warning,
ruin_cleared, mine_opened, mine_comfort_seen, entered_below, gallery_cleared, foreman_key_taken,
lower_gate_open, reached_silk_hollows, weaver_defeated, ward_restored, chapter_one_complete`; checkpoints
`cp_lit_landing|office|shrine|arena`; spawners `spawner_cleared_ruin_bramblings|gallery_gloom|hall_gloom`;
moments `moment_threshold, moment_crossing, moment_silk_intro, moment_return, imitation_seen`; once-per-save
hints `hint_<id>`. Other flags that exist in code and may appear in other saves: `moment_nursery,
imitation_folded, crossing_clue_seen, lower_gate_tried, heartseed_spawned_checked, horror_once_<event_id>`.
Counters in that save: `trees_felled, crops_planted, max_bond, structures_built` (also `crops_harvested` in code).

**"Chapter 1 is finished" markers**: `QuestLog.is_chapter_complete()` (= `completed` contains `return`), flag
`chapter_one_complete` (set on completion, **not read anywhere yet**), flag `ward_restored`. The quest `index`
is **15** (free play) or **16** (past the end, if both optional free-play goals were completed). See the
sequence-break case in §6 where `ward_restored` can be true while the others are not.

---

## 5. Saves

* **Location**: `%APPDATA%\Hollowhaven\saves\` (Godot `user://saves`; `project.godot` uses a custom user dir
  "Hollowhaven"). `slot1.json` (current), `slot1.bak.json` (previous good save), transient `slot1.tmp`. If the
  **main** file is unreadable it is moved aside to `slot1.corrupt-<unix>[-n].json` (a bad `.tmp`/`.bak` is not);
  a stale `.tmp` is deleted when the main file loads. **One save slot.** Settings are separate and per machine:
  `%APPDATA%\Hollowhaven\settings.cfg` (arachnophobia, comfort, intensity, volumes, key bindings are NOT part of
  the save). `-- --save-dir=<folder>` redirects saves (works in release builds; not settings). [code][test]
* **Format** (JSON, `game/autoload/save_system.gd`): `{"format": "hollowhaven-save", "version": 1,
  "game_version": "0.9.0", "saved_unix": …, "meta": {day, step, step_title, play_seconds, area}, "state":
  GameState.to_dict()}`. `state` keys (20): `player_name, inventory` (32 slots of `{id,count}`/null; 0–7 =
  hotbar), `key_items {id:count}, hotbar_index, player {hp, max_hp, stamina, max_stamina, area, pos, yaw,
  spawn, respawn_area, respawn_spawn, lantern_on}, flags, counters, quests {index, completed[], baselines{}},
  companions {id: {befriended, bond_xp, assignment, wait_area, wait_pos, last_pet_day, last_gift_day,
  last_fed_day} + optional extras written by companion logic (zones[], work_day, work_xp; unknown extra keys
  are kept)}, active_companion, structures {uid: {id, area, pos, rot, data}}, storages {uid: slots[]}, crops
  {uid: {crop, planted_at, tended_minutes}}, depleted {node_id: respawn_at_minutes | -1}, dropped [{uid, item,
  count, area, pos}], lore[], total_minutes, stats{}, buffs{}, next_uid`. [code][test]
* **Writing**: serialise → write `slot1.tmp` → re-read & validate → rotate a valid `slot1.json` to `.bak` →
  rename tmp. **Loading**: main if valid, else the newer valid of `.tmp`/`.bak`; `migrate(d)` exists but is a
  no-op (version 1). **A save with a version newer than the build's `SAVE_VERSION` is rejected** (an old build
  cannot load a newer save and would move it aside on its next save). `GameState.from_dict()` coerces types and
  repairs inconsistencies (one follower, missing crop records, uid collisions, non-finite numbers). [test]
* **When saves happen** (all `SaveSystem.save_game()` callers): arriving in an area via `Game.change_area`
  (entering/leaving the mine); sleeping in a bed; lighting a dungeon lantern, and every "Rest by the lantern
  (save)"; chapter completion (after the credits); pause menu **Save** (surface only, not with a threatening
  enemy within 20 m) and **Save & Quit** from the pause menu's quit dialogs.
* **Persisted**: everything in `state` — inventory/equipment/key items, quest progress, flags, counters,
  companions (identity, bond, assignment, wait spot), placed structures + chest contents + crops, depleted
  resource nodes and their respawn times, spawner clear flags and spawner respawn cooldowns
  (`depleted["spawner_<id>"]`), dropped overflow items, lore, clock, stats, buffs, player position on the
  surface (underground Krystal resumes at her last spawn/lantern).
* **Not persisted**: boss fight state (on death the fight resets but keeps its wounds, lit braziers and burned
  anchors **only while the Below stays loaded**; leaving the mine or Quit+Continue rebuilds the boss fresh),
  partial damage on rubble/boulders, enemies killed in an unfinished wave, director cooldowns (only
  `horror_once_*` flags), companion positions except wait spots, settings.

**Limitations that matter for adding content to an existing save** [code][test]:
1. **Quests are one linear list addressed by index** with a single active step. New Chapter Two steps must be
   **appended after `free_play`** (never inserted/reordered). A starter is needed because a finished save sits
   at index **15** (free play, optional goals possibly never done) or **16** (past the end — appended steps would
   then begin silently on load without the "new goal" toast/hint). Parallel side quests need a QuestLog
   extension (e.g. a second optional list).
2. **Ids must stay stable.** Unknown item ids are dropped on load from the inventory, key pouch, chest contents
   and dropped items (renaming/deleting an item id loses those items). Unknown structure ids stay in the save but
   are silently not spawned. Unknown companion ids, flags and completed quest ids are kept.
3. **Save `version` is 1.** Bump `SAVE_VERSION` + add a `migrate()` step for structural changes; note old builds
   then refuse the new save (downgrades impossible).
4. **Resource node ids are generated deterministically from the surface layout** (`vegetation.gd` indices with
   fixed seeds); changing placement data or generation order re-maps ids (depleted states may apply to different
   nodes — harmless, they respawn). Use new id prefixes for new nodes.
5. **Area ids are hard-coded in many places**, not just `Game.AREAS`: `Game.load_area` (building/saved position
   only on `surface`, horror director only on `below`), manual save (surface only), bed respawn, `build_ops.gd`
   (build area), companion rules (`companion_logic.gd` `SURFACE_AREAS = ["surface", "arena"]`; any other area
   behaves like the Below: only a follower with `enters_below` comes along, Mochi waits at the mine threshold),
   the pause-menu unstuck option, player/player_logic, combat, HUD/tracker/day dial/map/inventory panels.
   A new area needs a pass over all of these.
6. **Build area is the Haven only** (`data/world_layout.gd BUILD_AREA`, `build_ops.gd`).
7. **Single save slot**; New Game replaces the save on the next save (a confirmation is shown).
8. **Inventory is fixed at 32 slots** (entries beyond the size are dropped on load).

---

## 6. Extension points, known bugs, constraints

**Extension points** (see `docs/ARCHITECTURE.md` for exact signatures):
* Content data: `data/items.gd` (`alt_name/alt_desc` for arachnophobia), `data/recipes.gd` (`unlock` = flag
  gate), `data/structures.gd` (+ `CROPS`), `data/creatures.gd` (creatures, lines, bond thresholds),
  `data/enemies.gd`, `data/quests.gd` (objective types: flag, item, item_any, placed, befriended, counter;
  `alt_title/alt_text/alt_hint`), `data/horror_events.gd` (director events & intensity — new events are pure
  data only if they reuse the existing kinds in `src/horror/event_runner.gd`; the director is only created for
  area `below`), `data/world_layout.gd` (surface landmarks, spawns, clock).
* New area: `extends "res://src/world/area_base.gd"` (register spawns, zones, `get_zone_at`, `is_safe_zone`,
  `validate_position`, `on_player_spawned`), add to `Game.AREAS`, travel with `Game.change_area` — plus the
  hard-coded area checks listed in §5 limitation 5.
* Reusable building blocks: `resource_node.gd` (any harvestable), `world_item.gd` (persistent pickups),
  `enemy_spawner.gd` / `enemy_factory.gd`, `boss_brazier.gd`, `below/checkpoint_lantern.gd`, the interaction
  contract (`get_interaction`/`interact`, `get_harvest_info`/`harvest_hit`), lore notes (`below/lore.gd`),
  authored-moment pattern (`below/below_moments.gd`: trigger → effect → `Events.horror_event("authored:<id>")`
  + `Game.director.suppress()`).
* Flow & UI: `ui_root.show_chapter_card(title, subtitle)`, `show_comfort()`, `Events.say/notify/caption/hint`.
  **Chapter-One-specific (need parameterising or a Chapter Two variant)**: `Game.complete_chapter()`,
  `ui_root.show_ending()` / `ending_screen.gd` (fixed "Chapter One Complete / The Dimming Ward" text and
  credits line), the "Chapter One" card in `Game.new_game()`.
* Unused hooks: `Events.chapter_completed` (emitted, no listeners), `Events.recipe_unlocked` (declared, never
  emitted), flag `chapter_one_complete` (set, never read).

**Known bugs / limitations**:
* `KNOWN_ISSUES.md` (all minor: no navmesh for companions/enemies, boss state not saved mid-fight, camera pulls in
  when swung into walls, inventory needs a mouse, audio not listened to, …).
* **Sequence-break stall (found by the handoff verification)**: the mine, boss and Ward Stone are not gated by
  the quest step, so a player can return the Heartseed while the chain is still before `silk`; `silk` then waits
  for a Heartseed that was already consumed and `chapter_one_complete`/Haven Banner never arrive (and if the Ward
  warning was never read, the chain stays at `prepare`). The status of the fix is recorded in §9.
* Arachnophobia gap: the Ward Stone warning line "What took it still weaves in the dark." has no alternative
  text (status in §9).
* Results of the post-release headless audit: §9.

**Architectural constraints**: single-player, keyboard+mouse, offline; all art is procedural code geometry;
all audio is generated; text-only dialogue; the Haven must stay safe; every spider-like element needs an
arachnophobia alternative (`Settings.get_value("arachnophobia")`); comfort settings (shake/flash/intensity/
captions) must be honoured by any new effect.

---

## 7. Documents included
`GAME_SPEC.md` (design), `PROJECT_STATE.md` (state/next steps), `docs/ARCHITECTURE.md` (code contracts),
`AGENTS.md` (rules + verified commands), `QA_REPORT.md` (what was tested and how), `KNOWN_ISSUES.md`,
`THIRD_PARTY_NOTICES.md`, `README.md`, `docs/INSTALL_LOG.md`, `docs/Hollowhaven_Chapter1_Bible.md`, this file.

## 8. The Chapter-1-complete save copy
Folder `save_chapter1_complete/` in the handoff package: `slot1.json` + `slot1.bak.json`, **byte-identical
copies** (SHA-256 checked) of the save written by the automated real-input playthrough of the v0.9.0 release
(commit 0dde10e). It is **not Krystal's own save** — the owner's real save folder was empty; nothing there was
touched. The originals remain unchanged in the repo's `qa/tmp/e2e/release4/saves/` (git-ignored).
* `slot1.json` = the automatic save written by `Game.complete_chapter()` after the credits: quest index 15
  (`free_play`), flags `ward_restored` + `chapter_one_complete`, Lumi following, Mochi and Pebble at home, a
  workbench, a bed (never slept in) and a crop plot whose Sweetroot is **already ripe** when loaded, the
  Foreman's Key in the key pouch, the Haven Banner in the backpack. `respawn_spawn` is `mine_exit` (the bed was
  never used), so a defeat on the surface wakes Krystal at the mine exit.
* `slot1.bak.json` = the previous save (arriving back on the surface: quest `return`, index 14, Heartseed held,
  `ward_restored` false). The game only falls back to it if `slot1.json` is unreadable.
* **Verified** [test]: a headless test loaded this copy with `SaveSystem` pointed at a copied folder:
  index 15 / `free_play`, both flags, key item, 3 structures, companions; `Game.load_area("surface",
  "mine_exit", true)` built the Haven with the structures, the three companions and the restored Ward Stone;
  no SCRIPT ERRORs; a to_dict round trip was byte-identical.

**To load it** (only `slot1.json` is required; `settings.cfg` is optional — defaults are used without it):
* safest: **duplicate the folder first** (any save you make — area change, bed, lantern, chapter event, Save —
  rewrites `slot1.json` and rotates `.bak`), then run `Hollowhaven.exe -- --save-dir="C:\path\to\copy"` and choose
  **Continue**. The real `%APPDATA%\Hollowhaven\settings.cfg` is still read and written.
* or copy `slot1.json` into `%APPDATA%\Hollowhaven\saves\` (this makes it the real Continue save — back up any
  existing save there first).

## 9. Package state at handoff
(filled in when the package is created: source commit, test-suite result for that commit, audit fixes included.)
