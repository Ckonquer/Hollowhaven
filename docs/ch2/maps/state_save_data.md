# Map: state, saves, data & tests (`state_save_data`)

Paths are relative to `game/`, and `L` means line. This map adds to `docs/ARCHITECTURE.md` and does not repeat it.

## 1. Construction
The autoload order is Events, Settings, ItemDB, GameState, SaveSystem, Audio, Game, Debug (`project.godot` L23-30). The project version is `0.9.1`.

- **Settings** loads `user://settings.cfg` and builds the InputMap before GameState exists.
- **GameState._ready** (L44) connects `inventory.changed` plus `item_added`, `structure_placed`, `structure_removed`, `companion_befriended`, `crafted`, `flag_set`, `counter_changed` and `key_item_added` to `request_quest_eval`, then calls `reset()`.
- **Debug** applies `--save-dir` via `SaveSystem.set_save_dir()`; `--qa-telemetry` adds a `QATelemetry` child.

## 2. GameState (`autoload/game_state.gd`)
Constants:
- `HOTBAR_SIZE=8`, `INVENTORY_SIZE=32`, `MINUTES_PER_DAY=1440.0`.
- `COMPANION_ASSIGNMENTS=["wild","home","follow","wait"]`.

Fields and their `reset()` defaults (L77-101):
- `player_name="Krystal"`.
- `active`: not saved.
- `inventory`: an `Inventory(32)`. This object is **never replaced**; reset calls `from_array([])` on it.
- `key_items {id:int}`, `hotbar_index=0`.
- `player {hp:100.0, max_hp:100.0, stamina:100.0, max_stamina:100.0, area:"surface", pos:null, yaw:0.0, spawn:"haven_start", respawn_area:"surface", respawn_spawn:"haven_respawn", lantern_on:false, below_respawn:""}`.
- `flags {}`, `counters {}`.
- `quests`: a `QuestLog`. It is **replaced** on reset and load, so do not cache it.
- `companions`: one record per creature, `{befriended:false, bond_xp:0, assignment:"wild", wait_area:"", wait_pos:null, last_pet_day:-1, last_gift_day:-1, last_fed_day:-1}`. `companion_logic.gd` adds `work_day`, `work_xp` and `zones:[]` to these records.
- `active_companion=""`.
- `structures {uid:{id, area, pos:[x,y,z], rot, data:{}}}`. The bed uses `data.respawn`.
- `storages {uid:Inventory}`: replaced on load.
- `crops {uid:{crop, planted_at, tended_minutes}}`.
- `depleted {node_id: respawn_at | -1.0}`.
- `dropped [{uid, item, count, area, pos}]`.
- `lore [id]`. The ids are `landing_notice`, `foreman_order`, `ward_keeper`, `hollows_page`.
- `total_minutes=480.0`.
- `stats {play_seconds:0.0, deaths:0, enemies_defeated:0, items_crafted:0, started_version:"0.9.1"}`.
- `buffs {name:{mult, remaining}}`.
- `next_uid=1`. Uid prefixes are `s` for structures and `d` for dropped items.

API:
```
give_item(id: String, count: int, drop_pos: Variant = null) -> int   # L120; unknown id -> 0, no warning
take_item(id, count) -> bool (all-or-nothing); count_item(id) -> int; has_item(id, count := 1) -> bool
best_tool(kind) -> String; best_weapon() -> String; selected_slot(); select_hotbar(i)
set_flag(name, value: Variant = true); get_flag(name) -> Variant (default false)
add_counter(name, amount := 1) -> int; set_counter_max(name, value); get_counter(name) -> int
discover_lore(id) -> bool; new_uid(prefix := "u") -> String
is_depleted(node_id) -> bool; deplete(node_id, respawn_minutes)   # <0 never respawns
add_dropped(item, count, area, pos) -> String; get_dropped(uid); remove_dropped(uid); dropped_in_area(area)
add_structure(id, pos, rot_deg, area := "surface") -> String; remove_structure(uid); count_structures(id); get_storage(uid)
companion(id); is_befriended(id); befriend(id); set_companion_assignment(id, a, wait_area := "", wait_pos = null)
bond_level(id); max_bond_xp() (=100); add_bond(id, xp)
day(); hour(); time_of_day(); is_night(); advance_clock(real_s); skip_to_morning(wake_hour := 7.0) -> float
add_buff(name, mult, seconds); buff_mult(name); request_quest_eval(); to_dict(); from_dict(d)
```

Signals:
- `set_flag` emits `flag_set` only when the value actually changes, comparing types first. In Godot 4.7, `String==bool` is a script error.
- `add_counter` always emits `counter_changed`. `set_counter_max` emits only when the value rises.
- `give_item` emits `key_item_added`, `item_added` and `notify`. On overflow it also emits `item_overflow_dropped` plus a warning, and spawns the drop through `Game.spawn_dropped_item`.
- `time_of_day_changed` fires at most once per in-game minute.

Performance:
- Quest evaluation is coalesced: `_eval_pending` plus `call_deferred` means at most one evaluation per frame, and only while `active`.
- A 1 s poll re-evaluates whenever the current step is done.
- `_process` skips `buffs.keys()` when the dictionary is empty.
- `QuestLog.evaluate` stops cascading after 32 steps and has a re-entrancy guard.

## 3. Save file (`autoload/save_system.gd`)
Constants: `SAVE_VERSION=1`, `DEFAULT_DIR="user://saves"`, `SLOT="slot1"`, `BACKUP_NOTICE` (L14).

Files in the save directory: `slot1.json`, `slot1.bak.json`, `slot1.tmp` and `slot1.corrupt-<unix>[-n].json`.

Exact JSON written by `build_save_data` (L43):
```
{"format":"hollowhaven-save","version":1,"game_version":"0.9.1","saved_unix":float,
 "meta":{"day":int,"step":"<current_id or ''>","step_title":"<arachno-aware | 'Chapter complete'>","play_seconds":float,"area":str},
 "state":{"player_name","inventory":[32 x null|{id,count}],"key_items":{id:n},"hotbar_index","player":{12 keys},
  "flags":{name:any},"counters":{name:int},"quests":{"index":int,"completed":[ids],"baselines":{step:{counter:int}}},
  "companions":{id:{..}},"active_companion","structures":{uid:{id,area,pos,rot,data,+extras}},
  "storages":{uid:[20 x null|{id,count}]},"crops":{..},"depleted":{node:float},
  "dropped":[{uid,item,count,area,pos}],"lore":[..],"total_minutes","stats":{..},"buffs":{..},"next_uid":int}}
```

Functions:
- **`save_game(quiet := false) -> bool`** (L71)
  - Calls `Game.player.write_to_state()`, then `_atomic_write`.
  - Emits `game_saved(ok)` unless the save was quiet and succeeded.
- **`_atomic_write`** (L85)
  1. Writes the tmp file.
  2. Validates the tmp file.
  3. If the current file is valid, rotates it to `.bak`. If it is not, calls `_preserve_corrupt_main()`.
  4. Renames the tmp file into place.
- **`_read_and_validate`** (L122) returns `{}` when any of these hold:
  - the file is missing or empty, or the JSON is bad;
  - the root is not a Dictionary;
  - `format` is not the String `"hollowhaven-save"`;
  - `version` is not a number, or is below 1 or above `SAVE_VERSION`;
  - `state` is not a Dictionary.

  Otherwise it returns `migrate(d)`. This runs on main, tmp and bak for every `has_save`, `peek` and `load_game`, and on the tmp file during each save.
- **`migrate`** (L151) currently only sets `d["version"] = max(v, SAVE_VERSION)`.
- **`_best_available`** (L167) picks, in order:
  1. main;
  2. tmp, if its `saved_unix` is at least the backup's;
  3. bak.
- **`load_game`** (L188)
  - If the chosen source is not main but a main file exists, main is renamed to `.corrupt-*`.
  - A chosen tmp is promoted to main.
  - A chosen bak sets `recovered_from_backup` and emits a notify.
  - Then it calls `GameState.from_dict(d["state"])` and emits `game_loaded`.
- **`delete_test_saves`** acts only when `save_dir` contains `"test"`, and removes only `slot1.json`, `slot1.bak.json`, `slot1.tmp` and `slot1.corrupt*`.

**Today a save with a version above 1 is treated as corrupt.** It is moved aside and the loader falls back to the backup.

## 4. Load normalisation and unknown ids (`from_dict` L512)
`from_dict` calls `reset()` first. It then type-checks every section with `_num`, `_dict`, `_arr`, `_str`, `_int`, `_float` and `_vec_arr`; `_num` rejects INF and NaN.

| Section | How bad or unknown data is handled |
|---|---|
| `inventory` and `storages` (`Inventory.from_array` L251) | An unknown id or malformed slot becomes `null`, so the item is lost. Slot indices are kept. |
| `key_items` | Unknown ids are dropped. |
| `structures` | Kept whenever `id` is a non-empty String, even if the id is unknown, together with any extra keys. The factory skips unknown ids with a warning when spawning. |
| `crops` | Rebuilt for every farm structure; orphan entries are pruned. |
| `dropped` | Entries with an unknown item or count ≤0 are **discarded**. Missing or duplicate uids are relabelled. |
| `flags` | Every key and value is copied, with no type filter. |
| `counters` | Numeric values only, stored as int. |
| `companions` | Any id is kept. Assignments are repaired and the one-follower rule is enforced. |
| `stats` | A value is kept if its type matches the default; unknown keys are copied. |
| `player` | Unknown keys are copied. hp ≤0 is reset to max. |
| `next_uid` | Set above the highest uid suffix in use. |
| `quests` | Loaded **last**, after counters, so baselines can read them. |

`from_dict` emits no `flag_set` or `counter_changed`. React to `game_loaded` or `area_loaded` instead.

## 5. Inventory and QuestLog (`src/core/`)
**`inventory.gd`**
- `signal changed`; `slots` holds `null` or `{id, count}`.
- `add(id, n) -> int` returns the leftover. It refuses unknown ids and fills existing stacks first, then empty slots, hotbar first.
- `remove(id, n) -> bool` is all-or-nothing and takes from the last slots first.
- Other methods: `count_of`, `has`, `space_for`, `can_add`, `is_empty`, `free_slots`, `get_slot`, `totals`, `remove_from_slot`, `set_slot`, `clear_slot`, `move`, `transfer_slot_to`, `sort_items(keep_hotbar := true)`, `to_array`/`from_array`, `snapshot`/`restore`.

**`quest_log.gd`**
- Fields: `index`, `completed`, `baselines`.
- Methods:
  - `current_step`, `current_id`, `step_by_id`;
  - `step_string(step, field)`, which uses `alt_<field>` in arachnophobia mode;
  - `is_chapter_complete()`, which returns `completed.has("return")`;
  - `objective_status`, `is_skipped`, `step_done`, `evaluate`.
- `_check` (L92) supports the objective types `flag`, `item`, `item_any`, `placed`, `befriended` and `counter` (optionally `since_start`).
- `_complete` (L162) grants rewards only if the step id is not already in `completed`.
- `from_dict` marks every step before `index` as completed **without granting rewards**.

Steps in `data/quests.gd` (index 0-15). An asterisk means `skip_if_flag:"ward_restored"`.

| # | Step | Objectives | Reward |
|---|---|---|---|
| 0 | `wake`* | `read_ward_intro` | |
| 1 | `gather_basics` | wood 3, stone 2, fiber 2 | |
| 2 | `craft_axe` | stone axe | |
| 3 | `chop` | `trees_felled` 2 since start; wood 10 | |
| 4 | `workbench` | place a workbench | |
| 5 | `mochi` | befriend Mochi | 3 `sweetroot_seeds` |
| 6 | `pebble` | stone pickaxe; befriend Pebble | 2 `copper_ore` |
| 7 | `home` | bed; crop_plot; `crops_planted` 1 | |
| 8 | `lumi` | `ruin_cleared`; befriend Lumi | |
| 9 | `prepare`* | `read_ward_warning`; lantern; 2 meals | |
| 10 | `descend`* | `mine_opened`; `entered_below` | |
| 11 | `old_mine`* | `foreman_key` | |
| 12 | `deeper`* | `reached_silk_hollows` | |
| 13 | `silk`* | heartseed | |
| 14 | `return` | `ward_restored` | `haven_banner`, flag `chapter_one_complete` |
| 15 | `free_play` | `max_bond` ≥5; place `heartbloom_lamp` | none (`optional:true`) |

The `optional` key is read only by `tracker.gd` L66 and `journal_panel.gd` L99/146.

QuestLog is read by the tracker, journal, map, pause and title screens, `ui_root` L444, `ward_stone` L259, the save `meta`, `Debug.state_snapshot` and `qa_telemetry`.

## 6. Flags, counters, stats and chapter completion
**Story flags**
- `read_ward_intro`, `read_ward_warning` (ward_stone).
- `ruin_cleared` (the spawner `ruin_bramblings`; also forced by landmarks L631 as a failsafe).
- `mine_opened`, `mine_comfort_seen`, `entered_below`.
- `foreman_key_taken`, `lower_gate_open`, `lower_gate_tried`, `gallery_cleared`.
- `reached_silk_hollows`, `weaver_defeated`, `heartseed_spawned_checked`.
- `ward_restored`, `chapter_one_complete`.

**Moment flags:** `moment_threshold`, `moment_crossing`, `crossing_clue_seen`, `imitation_seen`, `imitation_folded`, `moment_silk_intro`, `moment_nursery`, `moment_return`.

**Patterned flags**
- `cp_lit_<landing|office|shrine|arena>`.
- `spawner_cleared_<ruin_bramblings|thicket_bramblings|quarry_bramblings|gallery_gloom|hall_gloom>`.
- `horror_once_wrong_mochi`.
- `hint_<id>`, set in `hint_card.gd` L55. `settings_panel._reset_hints` (L231) erases these flags directly. The ids:
  - `quest_<step>`;
  - `intro_move`, `bed_respawn`, `below_lantern`;
  - `boss_braziers`, `boss_glance`, `boss_scorched`, `boss_stuck`;
  - `build_controls`, `demo_hint`, `farming_growth`, `mochi_shy`, `need_tool`;
  - `pebble_boulder_pickaxe`, `silk_light`, `silk_light_raise`, `workbench_crafting`.

**Counters:** `trees_felled` (resource_node), `crops_planted` and `crops_harvested` (farming), `structures_built` (build_ops L102), `max_bond` (`add_bond`).

**Stats:** `play_seconds`, `deaths`, `enemies_defeated` (enemy_base L595), `items_crafted` (crafting L132), `started_version`.

**Signs that Chapter One is complete:**
- the flag `ward_restored`, which also unlocks the Heartbloom recipe and multiplies crop growth by 1.5;
- the flag `chapter_one_complete`;
- `quests.is_chapter_complete()`.

`meta.step_title` reads "Chapter complete" only once `free_play` is also finished (index 16). The QA bot's `tools/qa/persistence.py` L154 checks `chapter_one_complete`.

**`Game.complete_chapter()`** (game.gd L523) is called only from `ward_stone` L250:
1. Returns early if `ward_restored` is already set.
2. Takes the heartseed and calls `set_cutscene(true)`.
3. Sets `ward_restored`. A deferred evaluation then completes the `return` step during the cutscene:
   - gives the banner (overflow is dropped);
   - sets `chapter_one_complete`;
   - shows the toasts "Goal complete…" and "The Haven is safe. New recipe: Heartbloom Lamp.";
   - starts `free_play`.
4. Awaits `area.play_restoration()`.
5. Makes each companion `react("celebrate")`.
6. Emits `Events.chapter_completed` (nothing listens to it).
7. Awaits `ui.show_ending()`.
8. Calls `set_cutscene(false)` and `request_quest_eval`.
9. After 0.5 s, calls `save_game()` (not quiet).

If the window closes during the ending, nothing is saved because the mode is `"cutscene"`, and the whole sequence replays after reload.

**Recipe unlock:** a recipe's `unlock` field names a flag. `ItemDB.recipe_known` returns `unlock == "" or bool(get_flag(unlock))`. The Heartbloom Lamp is the only gated recipe. `Events.recipe_unlocked` is declared but never emitted.

## 7. Data catalogue
`ITEM_DEFAULTS` is `{name:"?", desc:"", cat:"resource", stack:99, icon:"unknown", color:WHITE, heal:0, damage:0, reach:2, tool:"", power:1, place:"", quest:false}`. `ItemDB.item()` returns a placeholder for unknown ids. `is_quest_item` is true when `quest` is set or `cat=="key"`.

`CATEGORY_ORDER` is `[tool, weapon, equipment, food, resource, seed, placeable, key]`.

**Items (39)**

| Group | Items |
|---|---|
| Resources | `wood`, `stone`, `fiber`, `copper_ore` (stack 99); `shiny_pebble`, `glowcap`, `silk` (alt "Pale Thread"), `echo_shard` (stack 50) |
| Food | `berries` (heal 8), `sweetroot` (heal 15) (stack 50); `berry_snack` (heal 30), `hearty_stew` (heal 60, buff `{stamina_regen:1.6, seconds:120}`), `glowcap_skewer` (heal 45) (stack 20) |
| Seed | `sweetroot_seeds` (stack 50, `crop:"sweetroot"`) |
| Tools | `stone_axe`, `stone_pickaxe` (tool axe/pickaxe, damage 9, reach 2.2) |
| Weapon | `copper_sword` (damage 18, reach 2.5) |
| Equipment | `lantern` |
| Placeables, stack 5 | `workbench`, `storage_chest`, `bed`, `haven_banner` |
| Placeables, stack 10 | `crop_plot` |
| Placeables, stack 50 | `wood_floor`, `wood_wall`, `wood_window`, `wood_doorway`, `wood_roof`, `fence` |
| Placeables, stack 20 | `lantern_post`, `flower_pot`, `rug`, `table`, `stool`, `pebble_cairn`, `echo_chime`, `heartbloom_lamp` |
| Key items | `foreman_key`, `heartseed` |

Tools, the weapon, the lantern and the key items all stack to 1. Each placeable's `place` is its own id.

**Recipes (25).** Each recipe's result has the same id, and count is 1 unless noted.

| Station | Recipe | Ingredients |
|---|---|---|
| Hand | `stone_axe` | wood 3, stone 2, fiber 2 |
| Hand | `stone_pickaxe` | wood 3, stone 3, fiber 2 |
| Hand | `workbench` | wood 8, stone 2 |
| Hand | `berry_snack` | berries 4 |
| Hand | `crop_plot` | wood 3, fiber 3 |
| Workbench | `copper_sword` | wood 2, copper 4, fiber 2 |
| Workbench | `lantern` | copper 3, fiber 2, wood 2 |
| Workbench | `storage_chest` | wood 10, copper 1 |
| Workbench | `bed` | wood 8, fiber 6 |
| Workbench | `wood_floor` | wood 2 |
| Workbench | `wood_wall` | wood 3 |
| Workbench | `wood_window` | wood 3, fiber 1 |
| Workbench | `wood_doorway` | wood 3 |
| Workbench | `wood_roof` | wood 2, fiber 2 |
| Workbench | `fence` (count 2) | wood 2 |
| Workbench | `lantern_post` | wood 3, copper 1, fiber 1 |
| Workbench | `flower_pot` | stone 3, fiber 1 |
| Workbench | `rug` | fiber 6, berries 2 |
| Workbench | `table` | wood 5 |
| Workbench | `stool` | wood 2 |
| Workbench | `pebble_cairn` | shiny_pebble 3, stone 2 |
| Workbench | `echo_chime` | echo_shard 3, wood 1, fiber 1 |
| Workbench | `heartbloom_lamp` (unlock `ward_restored`) | glowcap 2, silk 2, wood 2 |
| Campfire | `hearty_stew` | sweetroot 2, berries 3 |
| Campfire | `glowcap_skewer` | glowcap 2, wood 1 |

**Structures (19).** Fields are name, item, layer, snap, size, height, solid, interact, station, slots, light and passable.

| Structure | Layer / snap | Size | Notes |
|---|---|---|---|
| `workbench` | object / cell | 2x1 | interact station |
| `storage_chest` | object / cell | 1x1 | storage, 20 slots |
| `bed` | object / cell | 1x2 | sleep |
| `crop_plot` | object / cell | 2x2 | farm, not solid |
| `wood_floor` | floor / floor2 | 2x2 | |
| `wood_wall`, `wood_window` | edge / edge2 | 2x1 | |
| `wood_doorway` | edge / edge2 | 2x1 | passable |
| `wood_roof` | roof / roof2 | 2x2 | |
| `rug` | decor / cell | 2x2 | |
| `fence`, `table`, `haven_banner` | object / cell | 1x1 | solid |
| `lantern_post` | object / cell | 1x1 | light |
| `heartbloom_lamp` | object / cell | 1x1 | light, not solid |
| `flower_pot`, `stool`, `pebble_cairn`, `echo_chime` | object / cell | 1x1 | not solid |

There is one crop, `sweetroot`: 360 minutes to grow, 4 stages, yields `{sweetroot:[2,3], sweetroot_seeds:[1,2]}`.

**Creatures.** `BOND_XP_PER_LEVEL` is `[0,10,25,45,70,100]`.

| Creature | Befriend | Ability | Favourite | Enters the Below |
|---|---|---|---|---|
| `mochi` | offer 3 berries | forager | berries | no |
| `pebble` | `free_from_boulder` | miner | shiny_pebble | yes |
| `lumi` | rescue after `ruin_cleared` | lightbearer | sweetroot | yes |

**Enemies**

| Enemy | HP | Damage | Area | Notes |
|---|---|---|---|---|
| `brambling` | 30 | 10 | surface | |
| `gloomling` | 40 | 12 | below | fears light |
| `weaver` | 999 | 18 | below | stalker |
| `weaver_matron` | 240 | 20 | below | boss |

**Horror data.** `INTENSITY` 0/1/2 sets event_rate 0.45/1.0/1.5, damage_mult 0.6/1.0/1.15 and allow_major no/yes/yes. There are 14 `EVENTS`; only `wrong_mochi` is `once`, and `gloomling_ambush` and `stalker_pass` are major.

**World layout.** `WORLD_HALF_EXTENT=110`, `KILL_Y=-40`, `HAVEN_RADIUS=20`.
- `BUILD_AREA`: centre (0,0), radius 16, grid 1. Blocked circles: Ward Stone (0,-6) r3.5, campfire (4,3) r2.2, path (0,7) r1.8.
- `LANDMARKS` (position, radius): haven (0,0) 20; glade (-55,12) 22; quarry (66,-12) 22; ruin (-12,-66) 20; mine_mouth (54,-74) 14; pond (46,52) 16; meadow (-8,60) 22; old_oak (-34,-20) 10; thicket (-62,-46) 16.
- Also `STREAM_POINTS`, `STREAM_WIDTH=4`, 3 stream crossings, 10 `SPAWN_HINTS`.
- `CLOCK`: `minutes_per_second` 1.0, `night_speedup` 2.5, `day_start_hour` 6, `night_start_hour` 20, `new_game_hour` 8.

## 8. Settings (`autoload/settings.gd`)
Settings are stored in `user://settings.cfg`, section `"settings"`. Ranges come from `RANGES`.

- Camera: `mouse_sensitivity` 0.5 [0.1-2], `invert_y` false, `fov` 70 [55-95], `camera_distance` 5 [2.5-8], `show_hints` true.
- Audio [0-1]: `master_volume` 0.85, `music_volume` 0.6, `ambience_volume` 0.8, `sfx_volume` 0.85, `ui_volume` 0.7.
- Comfort: `horror_intensity` 1 [0-2], `arachnophobia`, `reduce_shake`, `reduce_flashing` false, `captions` true, `comfort_confirmed` false.
- Video: `fullscreen` true, `vsync` true, `max_fps` 0 [0-1000], `render_scale` 1.0 [0.5-1], `quality` 2 [0-2], `show_fps` false.
- `bindings` `{}` stores overrides only.

**Default bindings (32 actions).** Bindings are stored as `"key:<physical keycode>"` or `"mouse:<button>"`.

| Action | Default |
|---|---|
| `move_forward` | W, Up |
| `move_back` | S, Down |
| `move_left` | A, Left |
| `move_right` | D, Right |
| `jump` | Space |
| `sprint` | Shift |
| `dodge` | Ctrl, V |
| `attack` | Left mouse |
| `use_item` | Right mouse, Q |
| `interact` | E |
| `lantern` | F |
| `inventory` | Tab, I |
| `craft` | C |
| `build` | B |
| `journal` | J |
| `map` | M |
| `companion_command` | G |
| `pause` | Esc |
| `help` | F1 |
| `screenshot` | F12 |
| `build_rotate` | R |
| `build_dismantle` | X |
| `zoom_in` | Wheel up |
| `zoom_out` | Wheel down |
| `hotbar_1`…`hotbar_8` | 1…8 |

`REBINDABLE` lists 17 actions, from `move_forward` through `companion_command`.

Unbound keys: T, Y, U, O, P, H, K, L, Z, N, 9, 0 and F2-F11. Some screens hard-code keys: the journal uses Q, E, PgUp and PgDn; crafting uses Enter; settings capture uses Esc.

API: `get_value`, `set_value` (coerces, then emits `settings_changed` only on change), `coerce_value`, `sanitize_bindings` (drops unknown actions), `load_settings(path)`, `save(path)`, `reset_to_defaults`, `apply_video`, `setup_input_map` (only `DEFAULT_BINDINGS` keys, deadzone 0.2), `rebind` (refuses unknown actions), `actions_using`, `reset_bindings`, `action_label`, `event_label`.

Where actions are consumed:
- `player.gd` L583-600 handles player actions.
- `ui_root.HOTKEYS` (L40) handles panel keys.
- `build_mode.gd` handles the `build_*` actions.

## 9. Debug CLI (`autoload/debug.gd`)
Arguments go after `--`.

**Always available:** `--shots=<dir> --shot-times= --quit-at=`, `--log-state=<f> --log-interval=`, `--perf-log=<f>`, `--save-dir=<d>`, `--seed=`, `--max-seconds=` (exit code 3), `--no-focus-pause`, `--windowed`, `--qa-telemetry=<f> --qa-interval=0.1` (min 0.03).

**Debug builds only:** `--area=surface|below|arena --spawn=`, `--load-save`, `--cams= --shot-dir=`, `--hour=`, `--flags=a,b`, `--give=item:n`, `--befriend=mochi,lumi:follow`, `--settings=k=v`, `--spawn-enemy=id:n`, `--preview=<script>`.

**Module arguments:** `ui-{open,args,demo,lore,show}`, `title-show`, `companion-{walk,log,follow,scenario}`, `director-{log,force,probe}`, `below-moment`, `below-debug-light`, `sandbox*`, `player-{demo,demo-seconds,log,shots}`, `preview-*`, `wallhug-{pos,yaw}`, `icon-dump`, `parse-prefix`, and the runner's `filter` and `results`.

**QA telemetry** writes one JSON line per interval: the `Debug.state_snapshot()` fields (`t, mode, area, zone, step, day, hour, fps, ui_open, paused, pos, hp, inv, keys, companions`) plus `seq`, `ui_stack`, `objectives` (legacy QuestLog only), `hotbar_index`, `hotbar`, `flags` (keys), `messages` (last 12), `build`, `nearby` (80 m, max 60, every 0.4 s), `buttons` (every 0.2 s), `window`, `player{...}` and `companion_nodes`.

## 10. Test infrastructure
**`tests/test_case.gd`**
- Hooks: `before_each`, `after_each`.
- Asserts: `fail`, `assert_true`, `assert_false`, `assert_eq` (type-strict except int vs float), `assert_ne`, `assert_almost(a, e, eps=0.001)`, `assert_not_null`, `assert_null`.
- Helpers: `wait_frames`, `wait_physics`, `wait_seconds`, `fresh_state()` (which calls `GameState.new_game()`).

**`tests/runner.gd`**
- Collects `tests/unit/**/test_*.gd`, sorted; the filter is a case-sensitive substring of the file name.
- Per suite: save dir `user://test_saves/<suite>`, `test_*` methods in file order, `GameState.active=false` before each test, `delete_test_saves()` afterwards.
- A Logger subclass fails any test that raises an ERROR_TYPE_SCRIPT (`push_error` is not counted). Exit code 1 on failure; `--results=<json>`.
- `tools/test.sh <filter>` adds `timeout 600` and `--max-seconds=580` and writes `qa/tmp/test_results_<filter|all>.json`.

**`tests/unit/test_core_base.gd`** (override `setup` and `teardown`)
- Also fails on any `push_error` not allowed by `expect_error(fragment)`.
- Restores Settings, the InputMap, SaveSystem and GameState after each test.
- Helpers:
  - `logged`, `listen`, `record(sig, arity)`;
  - `json_norm`;
  - `assert_deep_eq` and `deep_diff` (strict: int is not equal to float);
  - `fill_backpack`, `write_text`, `read_text`.

**Save fixture (`test_core_save.gd`)**
- `_build_rich_state()` (L82-131) touches all 20 `EXPECTED_STATE_KEYS` (L7).
- `_save_text(saved_unix)` and `_wood_in(path)` are helpers.
- Everything is built in code; there are no fixture files on disk. See also `test_audit_persistence_flow.gd` (Continue with a torn save or tmp only).

## 11. Pitfalls
- `get_flag` returns `false` for missing flags, and flags can hold non-bool values. Wrap reads in `bool()`.
- Legacy quests are indexed by position. Inserting or reordering `STEPS` shifts every saved `index`.
- `migrate()` must be pure, idempotent and cheap, and must tolerate a dict with no `"state"` (`test_migrate_keeps_current_version` passes `{"version":1}`).
- JSON loads every number as a float, and `1e99999` reads back as INF. Always normalise.

## 12. Extension recipes
**(a) v1 → v2 migration with new sections**
1. Set `SAVE_VERSION := 2`.
2. In `migrate`, add:
   ```
   if v < 2 and d.get("state") is Dictionary:
       var st: Dictionary = d["state"]   # derive from Ch1 data; never overwrite existing keys
       d["version"] = 2
   ```
3. In GameState, add the new fields, their `reset()` defaults, their `to_dict` keys and a tolerant `from_dict`. `from_dict` must default missing sections because tests call it directly with v1 dicts.
4. Put derivations from Chapter One data in `migrate`, reading the saved dict. `from_dict` calls `reset()` first, so live state is gone by then.
5. Optionally add `meta.chapter` and `meta.quest2_title`.
6. Update `EXPECTED_STATE_KEYS` and `_build_rich_state`. Each new key must differ from a fresh state.

**(b) Reject future versions without falling back to the backup**
1. Split `_read_and_validate` into `_read_status(path) -> {data, status: ok|missing|corrupt|future}`.
2. When main is `future`, `_best_available` returns source `"future"`.
3. `load_game` then sets `last_error` and returns false, with no `_preserve_corrupt_main` and no backup.
4. `_atomic_write` must not rotate or overwrite a future main. On confirmed New Game, move it to `slot1.future-<ver>-<unix>.json`.
5. Add `SaveSystem.blocked_by_future`. Show a message for it in `title_screen._refresh_continue` (L194) and `_on_continue` (L269).
6. Update the `"future version"` case in `test_bad_files_are_rejected_without_script_errors`.
7. Extend `delete_test_saves` to remove `slot1.future*`.

**(c) Stable-ID Chapter Two quest layer**
1. Create `data/quests_ch2.gd` with `QUESTS := {qid: {title, requires_flag:"chapter_one_complete", steps:[{id, objectives (same schema), on_complete, reward_id}]}}`.
2. Create `src/core/quest_book.gd` with `active {qid:step_id}`, `completed {qid:true}`, `steps_done {"q/s":true}`, `baselines {"q/s":{counter:int}}`, `evaluate()`, `objective_status(qid)`, `to_dict()` and `from_dict()`. An unknown step id falls back to the first step that is not done.
3. Reuse the `_check` semantics by copying them or moving them into a static helper; `quest_log.gd` is shared.
4. Hook into `GameState._do_eval` and the 1 s poll, and save it under state key `quests2`.
5. Do not touch `data/quests.gd`.
6. Give the tracker, journal, map, pause, `meta` and telemetry a combined current-objective accessor.

**(d) Optional-goals tracker that keeps `free_play` progress**
1. Add goals `ch1_max_bond` (counter `max_bond` ≥5) and `ch1_heartbloom` (placed `heartbloom_lamp` ≥1). Both are state-based and need no baselines.
2. Store them as `goals {"done": {id: day}}`.
3. In `migrate`, if `completed.has("free_play")` or `index >= 16`, mark both done silently.
4. Keep the legacy `free_play` step. Hide its "OPTIONAL GOALS" header once Chapter Two is active.

**(e) Reward-once ledger**
1. Add `rewards {reward_id: {"day": int}}` to GameState.
2. Add this method:
   ```
   func grant_once(reward_id: String, give: Dictionary, flags := []) -> bool:
       if rewards.has(reward_id): return false
       rewards[reward_id] = {"day": day()}          # mark before granting
       for f in flags: set_flag(f)
       for id in give: give_item(id, int(give[id])) # overflow -> dropped, never lost
       return true
   ```
3. In `migrate`, backfill `ch1:mochi`, `ch1:pebble` and `ch1:return` from `quests.completed`.
4. Never grant anything from `from_dict`.

**(f) New input action `companion_skill` on T**
1. In `DEFAULT_BINDINGS`, add `"companion_skill": ["key:%d" % KEY_T]`.
2. In `REBINDABLE`, add `["companion_skill", "Companion: Skill"]`.
3. In `player.gd` near L595, handle it with an `elif event.is_action_pressed("companion_skill")` branch.
4. Add it to the Doing group in `controls_panel.gd` L6.
5. If quest hints will use it, add a token to `UiUtil.TOKEN_ACTIONS` (L10), the `HINT_TOKENS` in `test_core_quests.gd` L7, and the comment in `data/quests.gd` L13.

T is currently unbound. The only mention is in `test_core_settings.gd` L265, where a test locally rebinds lantern to logical T. Stored overrides don't include new actions, so existing players get T automatically. If a player already rebound another action to T, both actions fire on T.

**(g) Fixtures for 12 save scenarios**
1. Create `tests/unit/ch2_save_fixtures.gd` without the `test_` prefix, so the runner doesn't collect it. Give it static builders that return full save dicts built from real GameState calls: `{"format", "version", "game_version":"0.9.1", "saved_unix", "meta", "state": json_norm(GameState.to_dict())}`.
2. Put the suites in `test_ch2_save_*.gd` extending `test_core_base.gd`. Each writes `slot1.json` with `write_text`, then calls `load_game()`.
3. Cover these 12 scenarios:
   1. Fresh v1 save.
   2. Mid-chain save with baselines.
   3. In the Below holding the key, with `below_respawn` set.
   4. Heartseed held but not returned.
   5. On `free_play`.
   6. `free_play` done (index 16).
   7. Banner overflowed into `dropped`.
   8. Stuck on a dungeon step while `ward_restored` is set.
   9. `{"state":{}}`.
   10. Corrupt main with a good backup.
   11. v3 save, rejected in place.
   12. v2 save with Chapter Two sections and unknown item ids.
4. In each scenario, assert the post-load state, that save → load is stable, and that no reward is granted twice.

## 13. Risks
- **Downgrade.** The shipped 0.9.1 build treats v2 saves as corrupt, moves them aside and falls back to the backup. After two v2 saves the old build finds nothing it can load. The files are kept, not deleted.
- **Renamed or removed ids.** A renamed or removed item id is silently lost from slots and drops. Structures with unknown ids stay in the save but don't spawn.
- **Pinned tests.** These tests pin current behaviour and will fail if it changes:
  - `EXPECTED_STATE_KEYS`.
  - `free_play` must be the last step and `return` the second to last (test_core_quests L357-359).
  - Every recipe unlock flag must appear among the flags in `data/quests.gd` (test_core_item_db L128). A Chapter Two unlock flag will fail this test unless it scans the Chapter Two data too.
  - Every item needs a source (test_core_economy L281).
  - Bindings must not conflict (test_core_settings L63, test_ui_util L216).
  - The `"future version"` case expects the save to be kept as a corrupt copy.
- **Completion detection.** Renaming the completion flags or changing `is_chapter_complete` breaks `persistence.py` and the title screen's meta.
- **Double grants.** Moving reward grants out of `QuestLog._complete` risks granting twice, because the `from_dict` repair assumes earlier steps were already rewarded.
- **Slow migration.** A heavy `migrate()` runs on every save validation and every title-screen peek.

## 14. Chapter Two state, data and tests (Waves A-C + integration) — as built

Sections 1-13 map the Chapter One code. Schema v2, the new GameState sections, ChapterLog / OptionalLog, the reward ledger and the
data catalogue are in `docs/ch2/WAVE_A_REPORT.md` and spec §3/§4; this section adds what Waves B/C and the integration pass stored
or changed. Source of truth: `autoload/game_state.gd`, the module headers named below, `data/*.gd` headers.

**Saved keys added by Wave B/C modules** (all inside existing v2 sections or records, so migration needed nothing new; extra keys
survive load):
| where | keys | owner |
|---|---|---|
| `GameState.appearance` | the look dict (spec §4.1; unknown ids kept, shown as defaults) | B1/B2 |
| `GameState.wardrobe` | `owned`, `palettes` (`GameState.unlock_palette(id) -> bool`, emits `appearance_changed`; R07), `presets` (3), `notice_shown`, `show_armor` | B2/B5 |
| `GameState.companions[id]` | `combat_mode`, `skill_ready_at`, `home_spot`, `ribbon`, `home_task` (spec §3) + `home_nook`, `home_log` {day, task: n}, `cairn` | B4 |
| `GameState.structures[uid].data` | `queue`, `output`, `held_jobs` (furnace); `slots`, `upgrade_refunded` (chest); `tint`, `face`, `level` (building) | B5/B6 |
| `GameState.stations` | `use_chests` (bool), `table_decor` (festival table choice) | B5 |
| `GameState.mastery` | track xp, `seen`, `daily` {day, xp}, `legacy_credit`, `spots` {area: {kind: [[x, z]...]}} (bounded) | B5 + R22 |
| `GameState.trials[id]` | `clears`, `best_seconds` (spec §3) + the trial-scoped ledger `last_seconds`, `repeat_paid`, `paid` {item: total} (D1) and, between a won repeat clear and the arrival back at the origin, `pending` {item: n} + `pending_clears` (pass 2, L08: paid by `echo_trial.pay_pending`, then erased) | D1 + G3 |
| `GameState.extra["expeditions"]` | `{v: 1, active: {} \| {template, seed 1..9999, stop, defeated, down {enemy: n}, started_at, run}, runs, completed {template: n}, abandoned, last {} \| {template, run, items, keepsake, at}}` (see below) | D2 |
| `GameState.extra["music_box"]` | `{discovered: {cue: {area, zone, at}}, favourites: [cue]}` (see below) | D3 |
| flags | story/objective flags per `data/quests_ch2.gd` header + `data/optional_goals.gd` table (the rewards & flags rule, WAVE_A_REPORT); local flags (`hr_*`, `hw_*`, `mm_*`, `ta_*`, `cp_lit_*`, `spawner_cleared_*`); moment flags `ch2_moment_pumpkin_*`, `ch2_moment_empty_waltz`, `ta_moment_echo`, `moment_hw_*` (names kept, R136 r); `c1x_look_chosen`, `c1x_mochi_courage`, `c1x_upstairs_reachable` (repaired on load, R36), `<gate flag>_tried` (R74) | modules |
`GameState.player["max_hp"]` stays the BASE 100 (effective max = `Stats.effective_max_hp()`); the shield and slows' immunity are
transient (not saved); slows are timed buffs (`add_buff`, saved, ticked while unpaused).

**Wave D state in `GameState.extra` (pass 2, P37).** `extra` holds every top-level state key GameState does not own and writes it back
verbatim, so these two sections survive save / load / migration / an older build untouched, need no migration and are reset by New
Game; neither is in `GameState.STATE_KEYS` (only add a key there together with loading it there).
* `extra["expeditions"]` (`src/expeditions/expeditions.gd`, `Data.STATE_KEY`): `v` 1; `active` = {} or the running route
  (`template` id, `seed` 1..9999 - it only picks which authored group waits at each stop, the spawn-point order and the reward amounts
  -, `stop` index (== the stop count: the cache waits), `defeated` / `down` {enemy id: n} at the current stop, `started_at`
  (`GameState.total_minutes`), `run` number); `runs` started, `completed` {template: completions}, `abandoned`, `last` result. Every
  read normalises JSON floats; a damaged section is repaired, an unknown template or an out-of-range stop drops the run (never a crash).
  Expeditions never write a flag, the ledger or a quest layer; `complete()` records the completion before paying (once). The Reach gets
  the runner node (`Expeditions.RUNNER_NODE` "Expeditions") only while a run is active.
* `extra["music_box"]` (`src/audio/music_box.gd`, `STATE_KEY`): `discovered` {cue id: {area, zone, at (total_minutes)}} for cues of kind
  safe / explore / ending first heard in play (`STARTER_CUES` m01 is always known), `favourites` [cue id]. A cue id the catalogue no
  longer knows is kept but never listed, previewed or weighted; a malformed section reads as empty and is repaired on the next write.

**Display-only quest rows (pass 2, F03).** A `data/quests_ch2.gd` objective with `"display": true` is listed by
`ChapterLog.check_objective()` / `objective_status()` with its real done state (the row carries `"display": true`; other rows keep their
exact shape) but `step_done()` - and so `has_pending_completion()` / `evaluate()` - ignores it; a step needs at least one non-display
objective. `ChapterLog.is_display_objective(o)`. Used by `ch2_quarry` ("Calm the Quarry Warden" `hr_warden_defeated`, "Mend the mineral
winch" `ch2_winch_repaired`, then the lamp that completes it). Telemetry `current_objective().status` rows may carry the key.

**Quest layer since bug-fix round 1 (pass 3; CH2-001 / 012 / 015 / 016).** Step ids and the saved shape are unchanged.
* Step group `"lamps"`: the lamp search `ch2_outer_lamps` ("Find the Three Lamps") now shares the group with `ch2_orchard`, `ch2_quarry`
  and `ch2_manor`, so all four are current together from the moment the Commons is done and each lit lamp completes its own road at
  once (seal, `ch2_*_restored` flag, "Goal complete", message). The group title "Three Roads, Three Lamps" is announced once.
* Step key `"hint_when"` (optional, an objective of the same types): the step's hint waits until it holds while the step is current
  (each lamp road's hint waits for its `ch2_found_*_lamp`), then goes out once per session (`ChapterLog._hinted`, not saved) and never
  when the HUD card's `hint_quest_<id>` flag is already set. Steps without it hint once, when they start.
* `ChapterLog.from_dict()` narrowing: silent baselines are added only when NO current step has one (a save from before its current
  steps started). If one already has a baseline, the others start in the next `evaluate()` like any new step (start event, hint; the
  group is not announced twice), so an old save stuck in the lamp search pays any lamp already lit on its first evaluation.
* Legacy landmarks (CH2-010; decision R3-17, kept as implemented), next to the mastery legacy credit (`GameState.mastery.legacy_credit`,
  `Mastery.apply_legacy_credit()`, once per save, capped by `LEGACY_CAP_XP` below rank 2): when the credit is applied,
  `Mastery.mark_legacy_landmarks()` records every Chapter One landmark the save proves visited (`data/mastery.gd` `LEGACY_LANDMARKS`: any
  listed flag; `chapter_one_complete` proves the whole woods, `read_ward_intro` / `ruin_cleared` / `mine_opened`... prove the Haven, Ruin,
  Mine) as an already-seen wayfinding kind `landmark:<area>/<id>` - no XP, no toast - so a Continued save is not paid again for places the
  credit already stands for. A new journey has none of those flags and earns every first discovery; Chapter Two landmarks always pay; the
  Woods waygate circle is a helper zone (`Game.is_landmark_zone`, world_areas.md §8), never a discovery. Verify's S1 run (the real v1
  Chapter-One-complete save): Wayfinding ends at 105 XP, below rank 2 (110); `discovered.surface` is haven + ruin, no `ch2_waygate`.
  `tests/unit/test_mastery_landmark_discovery.gd`.

**Rewards (unchanged rule, WAVE_A_REPORT).** Content modules grant only their `"by": "content"` bundles with `grant_once`; the
integration pass added the missing bundles to `data/sources.gd` REWARDS: `rw_hr_chime_trail` (Pools pouch, R30),
`rw_hw_throat_supplies` (Bell Throat supplies, R31), `rw_hw_lightwell_alcove` (Light Well keepsake: decor `bat_bunting` ×2 +
`crescent_window`, no pattern — every pattern already has its own unique source, R32), and made `rw_ch2_feast` honest (candy 6 +
pumpkin 4, lantern_wax 4, sugarcap 3, moonpetal 3, identical in the `ch2_feast` step and REWARDS; totals paid unchanged, R33). Game's
Chapter Two grant passes no message, so the ending shows one toast (R06). Pass 2 (L09) catalogued the echo trial first clears
`rw_trial_velour_first` / `rw_trial_choir_first` (content bundles, exact mirrors of `data/trials.gd` `FIRST_REWARDS`; flags
`ch2_trial_velour` / `ch2_trial_choir` in `data/unlocks.gd`, which unlock the Loom patterns `pat_echo_masquerade` "Moonlit Masquerade"
and `pat_echo_chime` "Chime Chorister" in `data/appearance.gd` / `data/recipes.gd`). Trial repeat clears and expedition caches are
NOT ledger rewards: they are renewable and recorded in their own state (trials `paid` / `repeat_paid`, expeditions `completed`).

**Lore.** `src/core/lore_db.gd` (static): `get_lore(id) -> {title, text}` (arachnophobia-aware), `has_lore(id)`, `ids()`,
**`chapter_of(id) -> 1 | 2`** (by source file: legacy `lore.gd` and `data/lore_ch2_annex.gd` = 1 — Tobin's annex is Chapter One
optional content although its ids carry `lore_ch2_`; the other files = 2; an unknown id falls back to its prefix; R24), `reload()`
(tests). Files: `data/lore_ch2_{annex,reach,manor,works,story}.gd` (`ORDER` + `LORE`, optional `alt_title` / `alt_text`); no duplicate
ids (the Works note is `lore_ch2_sluice_chalk`). `UiUtil.lore_entry(id)` delegates to LoreDB (R16).

**ItemDB additions (integration).** `mastery_track_info(track) -> {name, desc}` (R21). Data text fixes: `swiftstep_charm` description
matches the equipment rule (sprint, roll, swing, wand; R40); `data/equipment.gd` names `Stats.player_shield()` (R41).

**Debug CLI additions** (debug builds only unless noted): avatar preview `--avatar-outfit/-hair/-hair-color/-skin/-eyes/-hat/-armor`
(krystal_avatar.gd), `--title-show=creation` (Meet Krystal), `--ui-show=wardrobe_notice|ending2`, `--no-wardrobe-notice` (switches the
automatic notice off; also every arg in `ui_root.NOTICE_OFF_ARGS`). Commands: AGENTS.md.

**Test infrastructure (integration R09).** `tests/runner.gd`: `--filter` takes several comma-separated fragments (a file runs when
ANY matches; for bisecting order-dependent failures). Isolation between test FILES: after each file the runner frees stray nodes it
left, restores Game's flow state (mode, area, player, UI root, director, companions, boss encounters, a Chapter Two ending or trip in
flight), unpauses, restores Settings and re-wires the session listeners (`Game.wire_session_systems()`); each repair is printed as
`ISOLATION <suite>: ...` so the leaking suite can be fixed. The full suite (~2,400 tests) takes 15-25 min (`tools/test.sh`, limit
`HH_TEST_SECONDS`, default 2400 s). Known leaks the runner repairs on every full run (stray projectiles / particles, `Game._bosses`,
zone flags, Reach world items) stay a test-hygiene item (pass 2 decision F04, KNOWN_ISSUES): no per-suite cleanup yet, the runner's
isolation is the safety net. Since pass 2 the session wiring also starts the Music Box discovery listener, so a suite that plays
safe music in play may leave `GameState.extra["music_box"]` behind (reset by `fresh_state()` / New Game).
