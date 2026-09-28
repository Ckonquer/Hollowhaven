# Map: state, saves, data & test infrastructure (`state_save_data`)

Paths are relative to `game/`. `L` = line. This adds to `docs/ARCHITECTURE.md` and does not repeat it.

## 1. Runtime construction
Autoload order (`project.godot` L23-30): Events, Settings, ItemDB, GameState, SaveSystem, Audio, Game, Debug.
- `Settings._ready` loads `user://settings.cfg` and builds the InputMap before GameState exists.
- `ItemDB._ready` merges `ITEM_DEFAULTS` into every `data/items.gd` entry and adds `id`.
- `GameState._ready` (L44) connects `inventory.changed` and 8 Events to `request_quest_eval`, then calls `reset()`.
- `SaveSystem._ready` creates `user://saves`.
- `Debug._ready` parses user args. `--save-dir` calls `SaveSystem.set_save_dir()`. `--qa-telemetry` adds a `QATelemetry` child.

Version is `application/config/version="0.9.1"`.

## 2. GameState (`autoload/game_state.gd`)
**Constants:**
- `HOTBAR_SIZE=8`, `INVENTORY_SIZE=32`, `MINUTES_PER_DAY=1440.0`.
- `COMPANION_ASSIGNMENTS=["wild","home","follow","wait"]`.

**Fields (L16-37) and `reset()` defaults (L77-101):**
- `player_name="Krystal"`.
- `active` is not saved. It is set by `new_game`/`from_dict` and cleared by `Game.goto_title`.
- `inventory`: a single `Inventory(32)` object that is never replaced. `reset` calls `from_array([])`.
- `key_items {id:int}`, `hotbar_index`.
- `player`: `{hp:100.0, max_hp:100.0, stamina:100.0, max_stamina:100.0, area:"surface", pos:null, yaw:0.0, spawn:"haven_start", respawn_area:"surface", respawn_spawn:"haven_respawn", lantern_on:false, below_respawn:""}`.
- `flags {}`, `counters {}`.
- `quests`: `QuestLog.new()`, which **is replaced** on reset/load. Never cache it.
- `companions`: one record per `ItemDB.creature_ids()`: `{befriended:false, bond_xp:0, assignment:"wild", wait_area:"", wait_pos:null, last_pet_day:-1, last_gift_day:-1, last_fed_day:-1}`. `companion_logic.gd` adds `work_day`, `work_xp` and `zones:[zone_id]`.
- `active_companion=""`.
- `structures {uid:{id, area, pos:[x,y,z], rot:deg, data:{}}}`. The bed stores `data.respawn=true` (`bed.gd` L186).
- `storages {uid: Inventory}`, replaced on load.
- `crops {plot_uid:{crop, planted_at, tended_minutes}}`.
- `depleted {node_id: respawn_at_total_minutes | -1.0}`.
- `dropped [{uid, item, count, area, pos}]`.
- `lore [ids]`: `landing_notice`, `foreman_order`, `ward_keeper`, `hollows_page` (`src/world/below/lore.gd`).
- `total_minutes`: `CLOCK.new_game_hour*60` = 480.0.
- `stats {play_seconds:0.0, deaths:0, enemies_defeated:0, items_crafted:0, started_version:"0.9.1"}`.
- `buffs {name:{mult, remaining_real_seconds}}`.
- `next_uid=1`. Uid prefixes: `s` = structure, `d` = dropped.

**API (signatures):**
```
give_item(id: String, count: int, drop_pos: Variant = null) -> int   # L120; unknown id -> 0 silently
take_item(id: String, count: int) -> bool                            # L144; all-or-nothing
count_item(id) -> int; has_item(id, count := 1) -> bool; best_tool(kind) -> String; best_weapon() -> String
selected_slot() -> Variant; select_hotbar(i: int)
set_flag(name: String, value: Variant = true); get_flag(name) -> Variant  # default false
add_counter(name, amount := 1) -> int; set_counter_max(name, value: int); get_counter(name) -> int
discover_lore(id) -> bool; new_uid(prefix := "u") -> String
is_depleted(node_id) -> bool; deplete(node_id, respawn_minutes: float)   # <0 = never
add_dropped(item, count, area, pos: Vector3) -> String; get_dropped(uid) -> Dictionary; remove_dropped(uid); dropped_in_area(area) -> Array
add_structure(structure_id, pos: Vector3, rot_deg: float, area := "surface") -> String; remove_structure(uid); count_structures(id) -> int; get_storage(uid) -> RefCounted
companion(id) -> Dictionary; is_befriended(id); befriend(id); set_companion_assignment(id, assignment, wait_area := "", wait_pos: Variant = null)
bond_level(id) -> int; max_bond_xp() -> int (=100); add_bond(id, xp: int)
day() -> int; hour() -> float; time_of_day() -> float; is_night() -> bool; advance_clock(real_s); skip_to_morning(wake_hour := 7.0) -> float
add_buff(name, mult, seconds); buff_mult(name) -> float
request_quest_eval(); to_dict() -> Dictionary; from_dict(d: Dictionary)
```

**Emitted signals:**
- `give_item` emits `key_item_added`, `item_added`, `notify` ("Obtained: X"). On overflow it also emits `item_overflow_dropped` and a warn notify, then calls `Game.spawn_dropped_item`.
- `take_item` emits `item_removed`. Taking a key item also emits `inventory_changed`.
- `set_flag` emits `flag_set` only when the value changed. It compares types first, because `String==bool` is a script error in Godot 4.7.
- `add_counter` always emits `counter_changed`. `set_counter_max` emits only when the value rises.
- Other emitters: `lore_discovered`, `companion_befriended`, `companion_assignment_changed`, `companion_bond_changed`, `time_of_day_changed` (once per in-game minute via `_minute_accum`), `day_started`, `hotbar_selected`.

**Performance tricks:**
- `request_quest_eval` coalesces calls through `_eval_pending` plus `call_deferred`, so it runs at most once per frame and only when `active`.
- `_process` skips `buffs.keys()` when buffs are empty.
- A 1 s poll (`_quest_poll`) re-evaluates when `step_done(current)` is true.
- `QuestLog.evaluate` has a 32-step cascade guard and an `_evaluating` re-entrancy flag.

## 3. Save file (`autoload/save_system.gd`)
`SAVE_VERSION=1`, `DEFAULT_DIR="user://saves"`, `SLOT="slot1"`, `BACKUP_NOTICE` (L14).

Files in `save_dir`:
- `slot1.json`
- `slot1.bak.json`
- `slot1.tmp`
- `slot1.corrupt-<unix>[-n].json`

Exact JSON (`build_save_data` L43; `JSON.stringify(data,"\t")`):
```
{ "format":"hollowhaven-save", "version":1, "game_version":"0.9.1", "saved_unix":float,
  "meta":{"day":int,"step":"<QuestLog.current_id() or ''>","step_title":"<arachno-aware or 'Chapter complete'>",
          "play_seconds":float,"area":"surface|below"},
  "state":{ "player_name","inventory":[32x null|{id,count}],"key_items":{id:n},"hotbar_index",
    "player":{...12 keys above...},"flags":{name:any},"counters":{name:int},
    "quests":{"index":int,"completed":[ids],"baselines":{step_id:{counter:int}}},
    "companions":{id:{record}},"active_companion","structures":{uid:{id,area,pos,rot,data,+extras}},
    "storages":{uid:[20x null|{id,count}]},"crops":{uid:{crop,planted_at,tended_minutes}},
    "depleted":{node:float},"dropped":[{uid,item,count,area,pos}],"lore":[..],"total_minutes":float,
    "stats":{...},"buffs":{name:{mult,remaining}},"next_uid":int } }
```

Functions:
- **`save_game(quiet := false) -> bool`** (L71): calls `Game.player.write_to_state()`, then `_atomic_write`, then emits `Events.game_saved(ok)` unless `quiet and ok`. On failure it calls `push_error`.
- **`_atomic_write`** (L85):
  1. Writes tmp.
  2. Runs `_read_and_validate(tmp)`.
  3. If the current file is valid, rotates it to bak. Otherwise it calls `_preserve_corrupt_main()`.
  4. Renames tmp to the current file.
- **`_read_and_validate(path)`** (L122): returns `{}` for any of these:
  - missing file, empty file or bad JSON
  - a root that is not a Dictionary
  - `format` that is not the String `"hollowhaven-save"`
  - `version` that is not a number, or is `<1` or `>SAVE_VERSION`
  - `state` that is not a Dictionary

  Otherwise it returns **`migrate(d)`**. This runs for main, tmp and bak on every `peek`/`has_save`/`load_game`, and on the tmp during a save.
- **`migrate(d)`** (L151): currently only `d["version"] = max(v, SAVE_VERSION)`.
- **`_best_available()`** (L167): tries main. A tmp is used only when it is valid and at least as new as bak, compared by `saved_unix`. Then bak.
- **`load_game()`** (L188):
  - If the chosen source is not main but a main file exists, main is moved aside as corrupt.
  - A tmp source is promoted to the main file.
  - A bak source sets `recovered_from_backup` and emits a notify.
  - Then `GameState.from_dict(d["state"])` and `Events.game_loaded`.
- **`delete_test_saves()`** only runs when `save_dir.contains("test")`. It removes only `slot1.json/.bak.json/.tmp` and `slot1.corrupt*`.

**Future-version behaviour today:** a save with version > 1 is treated as **corrupt**. It is renamed to `.corrupt-*`, and the loader falls back to bak.

## 4. Load normalisation and unknown ids (`GameState.from_dict` L512)
`from_dict` runs `reset()` first. It then type-checks every section (`_num` rejects INF/NaN; `_dict`, `_arr`, `_str`, `_int`, `_float`, `_vec_arr`).

| Section | Unknown or bad data |
|---|---|
| inventory / storages (`Inventory.from_array` L251) | Unknown item id or malformed slot: the **slot becomes null** and the item is lost. Slot indices are kept. Extra entries beyond `size` are cut. |
| key_items | Unknown id or count ≤0 is dropped. |
| structures | Kept when `id` is a non-empty String, **even if the structure id is unknown**. Extra record keys are kept. `StructureFactory.spawn_structure` skips unknown ids with a warning. A storage Inventory is only created for `interact=="storage"`. |
| crops | Rebuilt for every farm structure. Orphans are pruned. |
| dropped | Entries with an unknown item, non-String item or count ≤0 are **discarded**. A missing or duplicate uid is re-labelled with `new_uid("d")` after `next_uid` is fixed. |
| flags | Any key or value is copied (no type filter). |
| counters | Numbers only, stored as int. |
| companions | Any id is kept. Extra fields are kept. Assignment is repaired. `_repair_followers` enforces one follower. |
| stats | Kept when the type matches the default. Unknown keys are copied. |
| player | `_load_player`: unknown keys copied. hp ≤0 or >max resets to max. Stamina is clamped. |
| next_uid | `max(saved, 1, _max_uid_suffix()+1)`. |
| quests | `QuestLog.from_dict` is called **last**, after counters, so baselines can read counters. |

`from_dict` does **not** emit `flag_set`/`counter_changed`. Listeners must re-read state on `Events.game_loaded` or `area_loaded`.

## 5. Inventory and QuestLog (`src/core/`)
**`inventory.gd`:**
- `signal changed`. `size`, `slots` hold `null|{id,count}`.
- Queries: `count_of`, `has`, `space_for`, `can_add`, `is_empty`, `free_slots`, `get_slot(i)`, `totals()`.
- `add(id,count)->int` returns the leftover. It refuses unknown ids and fills existing stacks, then empty slots, hotbar first.
- `remove(id,count)->bool` is all-or-nothing and takes from the last slots first.
- Other mutators: `remove_from_slot`, `set_slot`, `clear_slot`, `move`, `transfer_slot_to(other,i)`.
- `sort_items(keep_hotbar := true)` orders by `CATEGORY_ORDER`, then name, then id.
- Persistence: `to_array`, `from_array`, `snapshot`, `restore`.

**`quest_log.gd`:**
- State: `index`, `completed:Array`, `baselines`.
- Methods: `steps()`, `current_step()`, `current_id()`, `step_by_id()`, `step_string(step,field)` (uses `alt_<field>` when arachnophobia is on), `is_completed()`, `is_chapter_complete()` (= `completed.has("return")`), `start()`, `objective_status(step := {})`, `is_skipped()`, `step_done()`, `evaluate()`.
- Objective types (`_check` L92): `flag`, `item`, `item_any`, `placed`, `befriended`, `counter` (with `since_start`, which subtracts the baseline). An unknown type gives a warning.
- `_complete` L162: rewards are applied only if the id is not already in `completed`. It sets `on_complete.flags`, gives `give` items, emits `quest_step_completed` and notifies (suppressed when skipped). After the last step, `index = STEPS.size()`.
- `from_dict` repairs data: every step before `index` is marked completed **without rewards**.

**Steps** (`data/quests.gd`, 16, index 0-15):
- `wake`* (flag `read_ward_intro`)
- `gather_basics` (3 wood, 2 stone, 2 fiber)
- `craft_axe`
- `chop` (counter `trees_felled` 2 since_start, plus 10 wood)
- `workbench` (placed)
- `mochi` (befriended; gives 3 `sweetroot_seeds`)
- `pebble` (`stone_pickaxe` plus befriended; gives 2 `copper_ore`)
- `home` (bed, crop_plot, counter `crops_planted` 1)
- `lumi` (`ruin_cleared` plus befriended)
- `prepare`* (`read_ward_warning`, lantern, 2 of snack/stew/skewer)
- `descend`* (`mine_opened`, `entered_below`)
- `old_mine`* (`foreman_key`)
- `deeper`* (`reached_silk_hollows`)
- `silk`* (heartseed)
- `return` (flag `ward_restored`; gives 1 `haven_banner`, flags `["chapter_one_complete"]`)
- `free_play`: `"optional": true`, counter `max_bond`≥5, placed `heartbloom_lamp`≥1

\* = `skip_if_flag:"ward_restored"`. The `optional` key is read only by `src/ui/hud/tracker.gd:66` and `journal_panel.gd:99,146`.

QuestLog consumers: tracker, journal, map_panel, pause_panel, ui_root L444, title_screen L181, ward_stone L259, `SaveSystem.meta`, `Debug.state_snapshot`, qa_telemetry.

## 6. Flags, counters, stats, and chapter completion
**Story flags:**
- `read_ward_intro`, `read_ward_warning` (ward_stone.gd L254/261)
- `ruin_cleared` (enemy spawner `ruin_bramblings`; landmarks.gd L631 failsafe; Lumi rescue flag)
- `mine_opened`, `mine_comfort_seen`, `entered_below` (mine_entrance.gd; below_world L689)
- `foreman_key_taken`
- `lower_gate_open`, `lower_gate_tried`
- `gallery_cleared` (rubble)
- `reached_silk_hollows`
- `weaver_defeated` (weaver_boss L659, below_world L579/716, heartseed_cocoon L247)
- `heartseed_spawned_checked`
- `ward_restored` (Game.complete_chapter; qa_restoration debug)
- `chapter_one_complete`

**Moment flags:**
- `moment_threshold`, `moment_crossing`, `crossing_clue_seen`, `imitation_seen`, `imitation_folded`, `moment_silk_intro`, `moment_nursery` (below_moments.gd)
- `moment_return` (below_world L675)

**Patterned flags:**
- `cp_lit_<landing|office|shrine|arena>` (checkpoint_lantern.gd L39)
- `spawner_cleared_<ruin_bramblings|thicket_bramblings|quarry_bramblings|gallery_gloom|hall_gloom>` (enemy_spawner L86)
- `horror_once_wrong_mochi` (director.gd L34; only `once` event)
- `hint_<id>`, written by hint_card.gd L57-64. `settings_panel._reset_hints` erases these directly. The ids are:
  - `quest_<step>`
  - `intro_move`, `bed_respawn`, `below_lantern`
  - `boss_braziers`, `boss_glance`, `boss_scorched`, `boss_stuck`
  - `build_controls`, `demo_hint`, `farming_growth`, `mochi_shy`, `need_tool`
  - `pebble_boulder_pickaxe`, `silk_light`, `silk_light_raise`, `workbench_crafting`
- `boss_brazier.persist_flag` is supported but unused.

**Counters:**
- `trees_felled` (resource_node tree kind)
- `crops_planted` (farming.gd L133)
- `crops_harvested` (L171)
- `structures_built` (build_ops.gd L102)
- `max_bond` (`add_bond` → `set_counter_max`)

**Stats:**
- `play_seconds` (advance_clock)
- `deaths` (Game.on_player_died)
- `enemies_defeated` (enemy_base.gd L595)
- `items_crafted` (crafting.gd L132; ui_util L453 fallback)
- `started_version`

**Chapter One complete** can be detected three ways:
- flag `ward_restored` (the ward is lit, the Heartbloom recipe is unlocked, crops grow ×1.5)
- flag `chapter_one_complete`
- `quests.is_chapter_complete()`

`meta.step_title=="Chapter complete"` only after the optional free_play step is also done (`index==16`). The QA bot `tools/qa/persistence.py` L154 checks `chapter_one_complete` in the telemetry flags.

**`Game.complete_chapter()`** (autoload/game.gd L523), called only by `ward_stone.gd` L250:
1. It returns early if `ward_restored` is set.
2. `take_item("heartseed")`.
3. `set_cutscene(true)`.
4. `set_flag("ward_restored")`. This emits `flag_set`, and a deferred quest eval then completes `return` **during the cutscene**: it gives `haven_banner` (overflow is dropped), sets `chapter_one_complete`, posts the toasts "Goal complete…" and "The Haven is safe. New recipe: Heartbloom Lamp.", and begins `free_play`.
5. `await area.play_restoration()`.
6. Companions `react("celebrate")`.
7. `Events.chapter_completed` is emitted (no consumer).
8. `await ui.show_ending()`.
9. `set_cutscene(false)`, then `request_quest_eval`.
10. A 0.5 s timer, then `SaveSystem.save_game()` (not quiet).

If the window closes mid-ending, `save_before_close` refuses because mode is `"cutscene"`. The last save still holds the heartseed, so the sequence replays on the next load.

**Recipe unlock:**
- `recipes.gd` field `unlock` holds a flag. `ItemDB.recipe_known(id)` returns true when `unlock == "" or bool(GameState.get_flag(unlock))`.
- `Crafting.known_recipes()` and `check()` use it. `check` gives "You haven't learned this recipe yet."
- Heartbloom Lamp is the **only** gated recipe (`unlock:"ward_restored"`).
- `Events.recipe_unlocked` is declared but **never emitted**. The "New recipe" toast is just the `return` step message.

## 7. Data catalogue
**ItemDB:** `ITEM_DEFAULTS` = `{name:"?", desc:"", cat:"resource", stack:99, icon:"unknown", color:WHITE, heal:0.0, damage:0.0, reach:2.0, tool:"", power:1.0, place:"", quest:false}`. Functions:
- `item(id)` returns a placeholder plus a warning for unknown ids.
- `has_item`, `all_item_ids`, `display_name`, `display_desc`, `stack_max`, `category`
- `is_quest_item` (true for `quest:true` or `cat=="key"`), `items_in_category`
- `recipe`, `all_recipe_ids`, `station_name`, `recipe_known`
- `structure`, `all_structure_ids`, `crop`, `creature`, `creature_ids`, `creature_line`
- `enemy`, `enemy_display_name`, `bond_level_for_xp`

`CATEGORY_ORDER=["tool","weapon","equipment","food","resource","seed","placeable","key"]` (`decor` is allowed but unused).

**Items (39):**

| Group | Items |
|---|---|
| Resources | `wood` (99), `stone` (99), `fiber` (99), `copper_ore` (99), `shiny_pebble` (50) |
| Food | `berries` (50, heal 8), `sweetroot` (50, heal 15) |
| Seed | `sweetroot_seeds` (50, `crop:"sweetroot"`) |
| Below resources | `glowcap` (50), `silk` (50; alt "Pale Thread"), `echo_shard` (50) |
| Tools | `stone_axe` and `stone_pickaxe` (stack 1, tool axe/pickaxe, power 1.0, damage 9, reach 2.2) |
| Weapon | `copper_sword` (damage 18, reach 2.5) |
| Equipment | `lantern` (stack 1) |
| Cooked food | `berry_snack` (20, heal 30), `hearty_stew` (20, heal 60, `buff:{stamina_regen:1.6, seconds:120}`), `glowcap_skewer` (20, heal 45) |
| Placeables | `place` = own id. Stack 5: `workbench`, `storage_chest`, `bed`, `haven_banner`. Stack 10: `crop_plot`. Stack 50: `wood_floor`, `wood_wall`, `wood_window`, `wood_doorway`, `wood_roof`, `fence`. Stack 20: `lantern_post`, `flower_pot`, `rug`, `table`, `stool`, `pebble_cairn`, `echo_chime`, `heartbloom_lamp` |
| Key (quest, stack 1) | `foreman_key`, `heartseed` |

**Recipes (25, `result==id`, count 1 unless noted):**

| Station | Recipe | Ingredients |
|---|---|---|
| hand | `stone_axe` | wood 3, stone 2, fiber 2 |
| hand | `stone_pickaxe` | wood 3, stone 3, fiber 2 |
| hand | `workbench` | wood 8, stone 2 |
| hand | `berry_snack` | berries 4 |
| hand | `crop_plot` | wood 3, fiber 3 |
| workbench | `copper_sword` | wood 2, copper 4, fiber 2 |
| workbench | `lantern` | copper 3, fiber 2, wood 2 |
| workbench | `storage_chest` | wood 10, copper 1 |
| workbench | `bed` | wood 8, fiber 6 |
| workbench | `wood_floor` | wood 2 |
| workbench | `wood_wall` | wood 3 |
| workbench | `wood_window` | wood 3, fiber 1 |
| workbench | `wood_doorway` | wood 3 |
| workbench | `wood_roof` | wood 2, fiber 2 |
| workbench | `fence` (count 2) | wood 2 |
| workbench | `lantern_post` | wood 3, copper 1, fiber 1 |
| workbench | `flower_pot` | stone 3, fiber 1 |
| workbench | `rug` | fiber 6, berries 2 |
| workbench | `table` | wood 5 |
| workbench | `stool` | wood 2 |
| workbench | `pebble_cairn` | shiny_pebble 3, stone 2 |
| workbench | `echo_chime` | echo_shard 3, wood 1, fiber 1 |
| workbench | `heartbloom_lamp` (unlock `ward_restored`) | glowcap 2, silk 2, wood 2 |
| campfire | `hearty_stew` | sweetroot 2, berries 3 |
| campfire | `glowcap_skewer` | glowcap 2, wood 1 |

`STATIONS={hand:"By Hand", workbench:"Workbench", campfire:"Campfire"}`.

**Structures** (`data/structures.gd`; fields name, item, layer, snap, size:Vector2i, height, solid, interact, station, slots, light, passable):

| Structure | Layer / snap | Size | Other |
|---|---|---|---|
| `workbench` | object / cell | 2x1 | interact station, station workbench |
| `storage_chest` | object / cell | — | interact storage, slots 20 |
| `bed` | object / cell | 1x2 | interact sleep |
| `crop_plot` | object / cell | 2x2 | interact farm, not solid |
| `wood_floor` | floor / floor2 | — | |
| `wood_wall`, `wood_window` | edge / edge2 | — | height 3 |
| `wood_doorway` | edge / edge2 | — | `passable:true` |
| `wood_roof` | roof / roof2 | — | |
| `fence`, `table` | object / cell | — | solid |
| `lantern_post` | object / cell | — | light ffc978 / 1.6 / 7 |
| `flower_pot`, `stool`, `pebble_cairn`, `echo_chime` | object / cell | — | not solid |
| `rug` | decor / cell | 2x2 | |
| `heartbloom_lamp` | object / cell | — | light ffb3c7 / 1.4 / 6 |
| `haven_banner` | object / cell | — | solid |

`CROPS.sweetroot={seed:"sweetroot_seeds", grow_minutes:360, stages:4, yield:{sweetroot:[2,3], sweetroot_seeds:[1,2]}}`.

**Creatures:** `BOND_XP_PER_LEVEL=[0,10,25,45,70,100]`.

| Creature | Befriend | Ability | Favourite food | Enters Below | Brave |
|---|---|---|---|---|---|
| `mochi` | offer 3 berries | forager | berries | false | 0.1 |
| `pebble` | `free_from_boulder` | miner | shiny_pebble | true | 1.0 |
| `lumi` | rescue, flag `ruin_cleared` | lightbearer | sweetroot | true | 0.4 |

`LINES[id][context]` supports `{name}`.

**Enemies:**

| Enemy | HP | Damage | Area | Notes |
|---|---|---|---|---|
| `brambling` | 30 | 10 | surface | drops fiber 1-3, berries 1-2 @0.5 |
| `gloomling` | 40 | 12 | below | light_fear |
| `weaver` | 999 | 18 | below | stalker; alt name "The Hollow Shade" |
| `weaver_matron` | 240 | 20 | below | boss; alt name "The Hollow Mother" |

**Horror (`data/horror_events.gd`):**
- `INTENSITY` 0/1/2:
  - event_rate .45/1/1.5
  - damage_mult .6/1/1.15
  - allow_major false/true/true
- `DIRECTOR` keys: tick 1, global_cd 14, major_cd 90, recovery 25, do_nothing_weight 3, max_threats 3, spawn distance 9-22, linger 12, unease_after 20, anticipation_after 45.
- 14 `EVENTS`: distant_pickaxe, creaking_timbers, footsteps_behind, pebbles_fall, whisper, wrong_mochi (once), lantern_flicker, far_glimpse, lumi_notices, scratching_above, web_rustle, silence, gloomling_ambush (major), stalker_pass (major).

**`data/world_layout.gd`:**
- `WORLD_HALF_EXTENT=110`, `KILL_Y=-40`, `HAVEN_RADIUS=20`.
- `BUILD_AREA={center (0,0), radius 16, grid 1, blocked:[Ward Stone (0,-6) r3.5, campfire (4,3) r2.2, path (0,7) r1.8]}`.
- `LANDMARKS`: haven (0,0) r20, glade (-55,12) r22, quarry (66,-12) r22, ruin (-12,-66) r20, mine_mouth (54,-74) r14, pond (46,52) r16, meadow (-8,60) r22, old_oak (-34,-20) r10, thicket (-62,-46) r16.
- `STREAM_POINTS`, `STREAM_WIDTH=4`, `STREAM_CROSSINGS` (3), `SPAWN_HINTS` (10 ids).
- `CLOCK={minutes_per_second:1.0, night_speedup:2.5, day_start_hour:6, night_start_hour:20, new_game_hour:8}`.

## 8. Settings (`autoload/settings.gd`)
`PATH="user://settings.cfg"`. The ConfigFile section is `"settings"`.

**DEFAULTS:**
- Camera: `mouse_sensitivity` 0.5 [0.1-2], `invert_y` false, `fov` 70 [55-95], `camera_distance` 5 [2.5-8], `show_hints` true.
- Audio: `master_volume` .85, `music_volume` .6, `ambience_volume` .8, `sfx_volume` .85, `ui_volume` .7 (all [0-1]).
- Comfort: `horror_intensity` 1 [0-2], `arachnophobia` false, `reduce_shake` false, `reduce_flashing` false, `captions` true, `comfort_confirmed` false.
- Video: `fullscreen` true, `vsync` true, `max_fps` 0 [0-1000], `render_scale` 1.0 [.5-1], `quality` 2 [0-2], `show_fps` false.
- `bindings` `{}`: only overrides are stored.

**Default bindings** (`DEFAULT_BINDINGS`, 32 actions):

| Action | Default |
|---|---|
| move_forward | W / Up |
| move_back | S / Down |
| move_left | A / Left |
| move_right | D / Right |
| jump | Space |
| sprint | Shift |
| dodge | Ctrl / V |
| attack | LMB |
| use_item | RMB / Q |
| interact | E |
| lantern | F |
| inventory | Tab / I |
| craft | C |
| build | B |
| journal | J |
| map | M |
| companion_command | G |
| pause | Esc |
| help | F1 |
| screenshot | F12 |
| build_rotate | R |
| build_dismantle | X |
| zoom_in | Wheel up |
| zoom_out | Wheel down |
| hotbar_1..8 | 1..8 |

Binding format is `"key:<physical keycode>"` or `"mouse:<button>"`.

`REBINDABLE` (17): the movement actions through `companion_command`. It excludes pause, help, screenshot, build_*, zoom and the hotbar.

**Free keys:** T, Y, U, O, P, H, K, L, Z, N, 9, 0 and F2-F11 are unbound. Hard-coded keys: the journal uses Q/E/PgUp/PgDn for pages (L69-73), crafting uses Enter, settings capture uses Esc.

**API:** `get_value`, `set_value` (via `coerce_value`, emits `settings_changed(key)` only on change), `coerce_value`, `sanitize_bindings`, `load_settings(path)`, `save(path)`, `reset_to_defaults(keep_bindings)`, `apply_video`, `setup_input_map`, `rebind(action, ev)`, `actions_using(ev)`, `reset_bindings`, `action_label`, `event_label`.

**Input actions:**
- InputMap actions exist only for `DEFAULT_BINDINGS` keys, with deadzone 0.2.
- Unknown actions are dropped by `sanitize_bindings` and refused by `rebind`.
- The player handles its actions in `player.gd` L583-600. `ui_root.HOTKEYS` (L40) handles the panel keys. `build_mode.gd` handles the build keys.

## 9. Debug CLI (`autoload/debug.gd`, user args after `--`)
**Always available:**
- `--shots=<dir> --shot-times=a,b --quit-at=s`
- `--log-state=<file> --log-interval=1.0`
- `--perf-log=<file>`
- `--save-dir=<dir>`
- `--seed=<int>`
- `--max-seconds=n` (quits with exit code 3)
- `--no-focus-pause`
- `--windowed`
- `--qa-telemetry=<file> --qa-interval=0.1` (minimum 0.03)

**Cheats** (require `OS.is_debug_build()`):
- `--area=<surface|below|arena> --spawn=<id>`
- `--load-save`
- `--cams="x,y,z,yaw,pitch;..." --shot-dir`
- `--hour`, `--flags=a,b`, `--give=item:n`
- `--befriend=mochi,lumi:follow`
- `--settings=k=v`
- `--spawn-enemy=id:n`
- `--preview=<script>`

**Module args:**
- `ui-open`, `ui-args`, `ui-demo`, `ui-lore`, `ui-show` (ui_root L461)
- `title-show`
- `companion-{walk,log,follow,scenario}`
- `director-{log,force,probe}`
- `below-moment`, `below-debug-light`
- `sandbox*` (sandbox, sandbox-area, sandbox-dark, sandbox-enemies, sandbox-full, sandbox-lantern, sandbox-swap-at, sandbox-time)
- `player-{demo,demo-seconds,log,shots}`
- `preview-{args,anim,dist,height,light,shots,target-y,wait}`
- `wallhug-{pos,yaw}`
- `icon-dump`
- `parse-prefix`
- `filter`, `results` (runner)

`state_snapshot()` (L222) returns `{t, mode, area, zone, step, day, hour, fps, ui_open, paused, pos, hp, inv, keys, companions}`.

**QA telemetry** (`src/qa/qa_telemetry.gd`) writes one JSON line per interval. Each line is the snapshot plus:
- `seq`, `ui_stack`
- `objectives` (legacy QuestLog only)
- `hotbar_index`, `hotbar`
- `flags` (key list)
- `messages` (last 12)
- `build`
- `nearby`: groups within 80 m, max 60, refreshed every 0.4 s
- `buttons`: window rects, refreshed every 0.2 s
- `window`
- `player{pos, vel, on_floor, stamina, lantern, cam_*, prompt, focus, hp}`
- `companion_nodes`

## 10. Test infrastructure
**`tests/test_case.gd`:**
- Hooks: `before_each`, `after_each`, `fail(msg)`.
- Asserts: `assert_true`, `assert_false`, `assert_eq` (type-strict except int vs float), `assert_ne`, `assert_almost(a, e, eps=0.001)`, `assert_not_null`, `assert_null`.
- Helpers: `wait_frames(n)`, `wait_physics(n)`, `wait_seconds(t)`, `fresh_state()` (= `GameState.new_game()`).

**`tests/runner.gd`:**
- Collects `res://tests/unit/**/test_*.gd` recursively and sorts them.
- Filter: `path.get_file().contains(filter)` (case-sensitive substring of the file name).
- Per suite:
  - `SaveSystem.set_save_dir("user://test_saves/<suite>")`.
  - Methods starting with `test_` run in declaration order.
  - Before each: `GameState.active=false`, then `await before_each / method / after_each`.
  - After the suite: `delete_test_saves()`.
- A `ScriptErrorCatcher` (a Logger) turns every **ERROR_TYPE_SCRIPT** logged during a test into a failure. `push_error` does not count here.
- Exit code 1 on failures. `--results=<json>`.
- `tools/test.sh <filter>` wraps this with `timeout 600` and `--max-seconds=580`, writing to `qa/tmp/test_results_<filter|all>.json`.

**`tests/unit/test_core_base.gd`** (base for core suites; override `setup()`/`teardown()`):
- Also fails on unexpected `push_error`. Use `expect_error(fragment)` to allow one; `logged(fragment)` checks the log.
- Restores Settings values, the InputMap, the SaveSystem dir and flags, and GameState after each test.
- Helpers: `listen`, `record(sig, arity)`, `json_norm(v)` (JSON round trip), `assert_deep_eq`/`deep_diff` (strict int≠float), `fill_backpack`, `write_text`, `read_text`.

**Save fixture** (`tests/unit/test_core_save.gd`):
- `_build_rich_state()` (L82-131) sets every one of the 20 state keys (`EXPECTED_STATE_KEYS` L7).
- `_save_text(saved_unix)` returns a full file text from `build_save_data()`.
- `_wood_in(path)` reads the wood count from a file.
- The fixtures are built in code. There are no fixture files on disk.

Other save suites: `test_audit_persistence_flow.gd` (continue with a torn main or a tmp only, via `Game.continue_game`) and `test_core_quests.gd` (reload never re-grants).

## 11. Pitfalls
- Never replace the `GameState.inventory` object, or the `changed` hook is lost. `quests` and `storages` objects are replaced on load.
- `get_flag` returns the Variant `false` for missing flags. Flags may hold non-bool values (the test uses `"note":"hello"`). Always wrap reads in `bool()`.
- Rewards are idempotent only through `QuestLog.completed`. `from_dict`'s repair marks earlier steps completed **without granting**.
- Legacy quests are **index-based**. Inserting or reordering `STEPS` shifts every saved `index`.
- `migrate()` runs on the tmp during each save, and several times per title screen (`has_save` plus `peek`). It must be pure and idempotent. It must also tolerate a dict with no `state`: `test_migrate_keeps_current_version` passes `{"version":1}`.
- JSON turns ints into floats. INF survives as `1e99999`. Always normalise through `_num`/`_int`.

## 12. Extension recipes
**(a) v1→v2 migration with new sections**
1. In `save_system.gd`, set `SAVE_VERSION := 2`.
2. In `migrate()`, add:
   ```
   if v < 2 and d.get("state") is Dictionary:
       var st: Dictionary = d["state"]
       # derive, never overwrite: st["quests2"] = ..., st["goals"] = ..., st["rewards"] = backfill_from(st)
       d["version"] = 2
   ```
   Keep `max(v, SAVE_VERSION)` last.
3. In `GameState`, add fields, `reset()` defaults, `to_dict()` keys and **tolerant** `from_dict()` parsing that defaults missing sections. Tests call `from_dict` directly with v1-shaped dicts and bypass `migrate`.
4. Put anything derived from Chapter One state in `migrate`. Note that `from_dict` runs `reset()` first, so read the saved `d` rather than GameState.
5. Optionally add `meta.chapter` and `meta.quest2_title` in `build_save_data`.
6. Update `test_core_save.gd`: `EXPECTED_STATE_KEYS` and `_build_rich_state`. Every new key must differ from a fresh state.

**(b) Future-version rejection without backup fallback**
1. Split `_read_and_validate` into `_read_status(path) -> {"data", "status": "ok"|"missing"|"corrupt"|"future"}` and keep the old wrapper.
2. In `_best_available`, if main is `"future"`, return `{data:{}, source:"future"}` (and apply the same rule when only tmp or bak is future).
3. `load_game` sets `last_error = "This save was made by a newer version…"` and returns false. It must not call `_preserve_corrupt_main` and must not use bak.
4. `_atomic_write` must refuse to rotate or overwrite a future main, or should move it aside as `slot1.future-<ver>-<unix>.json`, and only after the title screen's New Game confirmation.
5. Expose `SaveSystem.blocked_by_future: bool`. `title_screen._refresh_continue` (L194) and `_on_continue` (L269) should show that message instead of "couldn't find a save".
6. Update the `"future version"` case in `test_bad_files_are_rejected_without_script_errors` (it currently expects a corrupt copy). Extend `delete_test_saves` to remove `slot1.future*`.

**(c) Stable-ID parallel Chapter Two quest layer**
1. Add `data/quests_ch2.gd`: `QUESTS := {quest_id: {"title", "requires_flag":"chapter_one_complete", "steps":[{"id": stable, ...same objective schema, "on_complete":{...}, "reward_id"}]}}`.
2. Add `src/core/quest_book.gd` (RefCounted): `active: {quest_id: step_id}`, `completed: {quest_id: true}`, `steps_done: {"q/step": true}`, `baselines: {"q/step": {counter: int}}`. Use string keys only, never indices. Provide `evaluate()`, `current(quest_id)`, `objective_status(quest_id)`, `to_dict()`/`from_dict()`. An unknown step id should fall back to the first step that is not done.
3. Reuse the `QuestLog._check` semantics. Copy them or factor them into a static helper, because quest_log.gd is shared.
4. Hook it into `GameState._do_eval` and the 1 s poll. Add a state key `quests2`.
5. Leave `data/quests.gd` untouched. Tests require `free_play` to be last and `return` second-last.
6. The tracker, journal, map, pause, title (`meta`) and qa_telemetry currently read only `GameState.quests`. Give them a combined "current objective" accessor.

**(d) Optional-goals tracker preserving free_play**
1. Add goals with stable ids, e.g. `ch1_max_bond` (counter `max_bond` ≥5) and `ch1_heartbloom` (placed `heartbloom_lamp` ≥1). Both are state-based with no baselines.
2. Store `goals: {"done": {goal_id: day}}`.
3. In migrate or first load: if `quests.completed.has("free_play")` or `index>=16`, mark both goals done with no message. Otherwise leave them to live evaluation.
4. Keep QuestLog's `free_play` step active so legacy saves and tests still pass. Once Chapter Two is active, the tracker should hide the legacy "OPTIONAL GOALS" header.

**(e) Reward-once ledger**
1. Add GameState `rewards: {reward_id: {"day": int}}`.
2. Add:
   ```
   func grant_once(reward_id: String, give: Dictionary, flags := []) -> bool:
       if rewards.has(reward_id): return false
       rewards[reward_id] = {"day": day()}   # mark first
       for f in flags: set_flag(f)
       for id in give: give_item(id, int(give[id]))   # overflow -> dropped, never lost
       return true
   ```
3. In migrate, backfill `ch1:mochi`, `ch1:pebble` and `ch1:return` from `quests.completed`.
4. Chapter Two steps call `grant_once("ch2:<quest>/<step>", ...)`. Never grant from `from_dict`.

**(f) New input action `companion_skill` on T**
1. `settings.gd` `DEFAULT_BINDINGS`: add `"companion_skill": ["key:%d" % KEY_T]`.
2. `REBINDABLE`: add `["companion_skill", "Companion: Skill"]`.
3. `player.gd` L595: add an `elif event.is_action_pressed("companion_skill")` branch, gated by `Game.gameplay_input_allowed()`.
4. `controls_panel.gd` L6 "Doing" group: add the entry.
5. `ui_util.gd` `TOKEN_ACTIONS` L10: add `"skill": "companion_skill"`. If quest hints use it, also add it to `HINT_TOKENS` in `test_core_quests.gd` L7 and the token doc in `data/quests.gd` L13.

T is currently unbound. `test_core_settings.gd` L265 only rebinds lantern to logical T inside that test. Existing players' `bindings` hold overrides only, so they get T automatically. If a player already rebound another action to T, both actions fire and nothing resolves it. `actions_using` can warn about the clash.

**(g) Fixtures for 12 save scenarios**
1. Create `tests/unit/ch2_save_fixtures.gd`. It has no `test_` prefix, so the runner will not collect it. Give it static builders that return full save dicts: `{"format":"hollowhaven-save", "version":1, "game_version":"0.9.1", "saved_unix":1000.0, "meta":{...}, "state": json_norm(GameState.to_dict())}`. Build state through real GameState calls, then `json_norm`.
2. Suites go in `test_ch2_save_*.gd`, extend `test_core_base.gd`, write with `write_text(SaveSystem.save_dir.path_join("slot1.json"), JSON.stringify(d))`, then run `SaveSystem.load_game()`.
3. The 12 scenarios:
   1. fresh v1 (`wake`)
   2. mid-chain v1 (`chop` with baselines)
   3. Below with key and `below_respawn` lantern
   4. heartseed held, not returned
   5. chapter one complete, on `free_play`
   6. free_play done (`index` 16)
   7. complete with the banner overflowed into `dropped`
   8. legacy stuck on a dungeon step with `ward_restored`
   9. minimal `{"state":{}}`
   10. corrupt main plus good bak
   11. future version v3 (rejected in place)
   12. v2 with Chapter Two sections plus unknown item ids in inventory/storages/dropped
4. For each scenario assert: `GameState.to_dict()` after load, the deep-equality of a second save, that rewards are not re-granted, and the migrated sections.

## 13. Risks
- **Downgrade:** the shipped 0.9.1 build treats any v2 save as corrupt, moves it to `.corrupt-*` and falls back to bak. After two v2 saves nothing loads in the old build. The files are preserved, not deleted.
- **Unknown ids:** an item id that is removed or renamed is lost silently from slots and drops. Never rename ids in `data/items.gd`. Structures with unknown ids survive in state but do not spawn.
- **Tests that pin data or state:**
  - `EXPECTED_STATE_KEYS` (test_core_save)
  - `free_play` last and `return` second-last (test_core_quests L357-359)
  - every recipe `unlock` flag must appear as a quest flag objective or an `on_complete` flag in `data/quests.gd` (test_core_item_db L128). A Chapter Two unlock flag set elsewhere fails this unless the test also scans the Chapter Two data.
  - every item needs a source (test_core_economy L281)
  - bindings must be conflict-free (test_core_settings L62, test_ui_util L216)
  - `REBINDABLE` actions must be defined
  - hint tokens must be documented
  - the `"future version"` corrupt-preservation expectation
- **Chapter One completion detection:** changing `QuestLog.is_chapter_complete` or the flag names breaks the QA bot's `persistence.py` and the title `meta`.
- **Reward-order change:** moving reward grants out of `QuestLog._complete` risks double grants on load. `from_dict` repair assumes earlier steps are already rewarded.
- **Performance:** a heavy `migrate()` is paid on every save validation and on each title-screen peek.
