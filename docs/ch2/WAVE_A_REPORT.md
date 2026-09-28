# Wave A report — what the foundation actually delivered (read before building on it)

Wave A = four modules, each built then independently reviewed: A1 core-save, A2 data catalogue, A3 flow &
areas, A4 music director; plus 22 new compositions (26 OGG files incl. layers) by four composers. The
lead integrated them (below). Source of truth for signatures is the code; this is the map.

## Rewards & flags — THE RULE (read this first)
* Every flag a content module must set is listed in the header of `data/quests_ch2.gd` (Chapter Two
  steps) and in the table at the top of `data/optional_goals.gd` (optional goals, with the module that
  sets each flag). Recipe unlock flags and who sets them: `data/unlocks.gd`.
* `data/sources.gd` `REWARDS` lists every reward bundle with `"by"`:
  * `"content"` — the content module named in `who` grants it itself: `GameState.grant_once(id,
    bundle.items, bundle.flags)` (or read it with `ItemDB.reward_bundle(id)`). These are:
    `rw_c1x_gardener`, `rw_c1x_tailor_cache`, `rw_c1x_elder`, `rw_c1x_tobin`, `rw_ch2_crossing`,
    `rw_ch2_candleyard_pattern`, `rw_trial_matron_first`; added later: `rw_hr_chime_trail`,
    `rw_hw_lightwell_alcove`, `rw_hw_throat_supplies` (integration pass 1, R30-R32) and the echo trial first
    clears `rw_trial_velour_first`, `rw_trial_choir_first` (Wave D1; catalogued in pass 2, L09 - exact mirrors of
    `data/trials.gd` `FIRST_REWARDS`, each setting only its trial's pattern-unlock flag `ch2_trial_<id>`). The
    authoritative list is the header of `data/sources.gd`.
  * `"chapter_log"` / `"optional_log"` — paid AUTOMATICALLY by the quest layer / optional log when the step or
    goal completes (`"rw_" + step/goal id`). Content modules NEVER grant these (seals, seeds, Wardlight,
    Thread Veil, patterns...). They only set the objective flags.
  * `"legacy"` — documentation only; never grant.
* Lamps: the orchard/quarry/manor content sets `ch2_garden_lamp_lit` / `ch2_quarry_lamp_lit` /
  `ch2_manor_lamp_lit`; the quest layer then grants the seal + unlocks (`ch2_orchard_restored` ...).
* Quarry winch flag: `ch2_winch_repaired`. Crossing: grant `rw_ch2_crossing` (sets
  `ch2_crossing_cleared`). Choir: set `ch2_choir_defeated`. Chapter end: only `Game.complete_chapter_two()`.

## SaveSystem (autoload/save_system.gd) — schema v2
`SAVE_VERSION := 2`, `FUTURE_ERROR`, `UPGRADE_BACKUP_DIR := "pre_v2_backup"`; vars `blocked_by_future`,
`future_version`, `replace_future_allowed`, `upgrade_backup_path`; `migrate(d) -> Dictionary` (pure,
idempotent, additive); `_read_status(path)`; meta gains `chapter`. Future-version saves are refused in
place (never moved, never replaced by the backup). A one-time raw copy of v1 files goes to
`<save_dir>/pre_v2_backup/` before any v2 write. Details: `docs/SAVE_MIGRATION.md`.

## GameState (autoload/game_state.gd)
Sections: `appearance`, `wardrobe` {owned, palettes, presets, notice_shown, show_armor}, `equipment`
{head, body, boots, charm}, `capacity` {backpack}, `chapter2` (ChapterLog), `optional_goals` (OptionalLog),
`ledger`, `mastery`, `discovered`, `trials`, `orphans`, `stations`, `extra`. Constants `EQUIPMENT_SLOTS`,
`ARMOR_SLOTS`, `LEGACY_LOOK_IDS`, `COMPANION_V2_DEFAULTS`, `MAX_BACKPACK`, `MAX_STORAGE`.
* `set_backpack_capacity(slots) -> bool` (grow only), `set_storage_capacity(uid, slots) -> bool`
* `equip_slot_for(item_id) -> String`, `equipped(slot) -> String`, `equipped_count(item_id) -> int`,
  `equip(item_id, from_slot := -1) -> bool`, `unequip(slot) -> bool`, `last_equip_error` (+ `Events.equipment_changed`)
* `grant_once(reward_id, items := {}, flag_list := [], message := "") -> bool`, `has_reward(id)`
* `unlock_pattern(id) -> bool` (wardrobe ownership)
* `discover(area_id, landmark_id) -> bool` (Game calls it on every zone change), `is_discovered`, `discovered_in(area)`
* `chapter() -> int`, `current_objective() -> {source, chapter, id, title, steps, status, optional, group, target, target_area}`
* Companion records gain `combat_mode` ("assist"|"close"), `skill_ready_at` (play_seconds timeline),
  `home_spot`, `ribbon`, `home_task`. Buff records keep extra keys (food `family`).
* Panels must use `GameState.inventory.size` (not `INVENTORY_SIZE`) and chest `inventory.size`.
`Inventory`: `resize(n)` grow-only, `reset_to(n)`, `from_array_collect(arr)`.

## ChapterLog (src/core/chapter_log.gd, `GameState.chapter2`) + data/quests_ch2.gd
`is_available()`, `is_active()` (flags `chapter_one_complete` AND `ch2_accepted`), `current_steps()`,
`display_title()`, `step_string(step, field)`, `objective_status(step)`, `is_done(id)`, `is_finished()`,
`step_by_id(id)`, `evaluate()`. Steps have `target` (landmark/zone id String) + `target_area`, `group`
("lamps" for steps 5-7). Objective types: flag, flags_all, item, item_any, placed, placed_any, befriended,
counter, discovered, equipped, companion_home_spot. Emits `chapter2_step_started/completed`.
`Events.chapter2_completed` is emitted ONLY by `Game.complete_chapter_two()`.
## OptionalLog (src/core/optional_log.gd, `GameState.optional_goals`) + data/optional_goals.gd
`goals()`, `goal(id)`, `is_done(id)`, `is_visible(g)`, `visible_goals()`, `pending_goals()`, `done_count()`,
`step_string(g, field)`, `objective_status(g)`, `evaluate()`. Legacy free_play goals are
`opt_legacy_bond` / `opt_legacy_heartbloom`. Emits `optional_goal_completed`.

## Data catalogue (A2) — read through ItemDB
New data files: `appearance.gd`, `equipment.gd` (+ `EquipmentData.combine_reduction(sources)` reference),
`companion_skills.gd`, `mastery.gd`, `sources.gd` (item sources, node kinds per area, REWARDS), `unlocks.gd`.
ItemDB additions: `special_recipe_ids()`, `every_recipe_id()`, `recipe_kind(id)` ("item"|"timed"|"apply"|
"pattern"), `recipes_for_station(station)`, `station_structure(station)`, `unlock_flags()`,
`unlock_setter(flag)`, `enemy_display_desc(id)`, `structure_display_name(id)`, `item_tier(id)`,
`best_tool_tier(kind)`, `equip_slot(id)`, `equipment(id)`, `equipment_rules()`, `armor_set(id)`, `wand(id)`,
`buff_family(id)`, `buff_families()`, `legacy_look()`, `appearance_table(name)`, `appearance_part(id)`,
`parts_for_slot(slot)`, `outfit(id)`, `pattern(id)`, `dye_palette(id)`, `swatch_color(id)`, `preset_slots()`,
`sanitize_look(look) -> {look, missing}`, `companion_skill(id)`, `companion_skill_at(id, bond_level)`,
`companion_rules()`, `mastery_tracks()`, `mastery_rank_for_xp(xp)`, `mastery_rank(track)`,
`mastery_xp_rules(track)`, `mastery_reward(track, rank)`, `mastery_tables()`, `sources(item_id)`,
`node_kind(kind)`, `all_node_kinds()`, `node_kinds_in(area, zone := "")`, `reward_bundle(id)`,
`all_reward_ids()`, `is_story_required(id)`, `story_required_items()`.
Notes: special recipes (apply/pattern/timed) are NOT in `all_recipe_ids()`; `Crafting.check()` currently
refuses non-"item" recipes ("This is made at its own station.") until the crafting module adds handlers.
Food buff keys follow spec §9 (`slow_resist`, not `slow_mult`); the Kindling Charm's data effects are
`lantern_radius` + `heal_received` (spec §9 `ward_calm` is dropped). Loom recipes are gated by
`c1x_tailor_cache` (the Tailor's Cache must exist in Chapter One content). Base structure script now
returns a greyed "Not ready yet" interaction for interactable structures without their own script.

## Game flow (A3, autoload/game.gd)
Constants `AREAS` (+ tobin_annex, hallowmere_reach, moonveil_manor, hushed_works, echo_trial),
`SAFE_SAVE_AREAS`, `OUTDOOR_AREAS`, `TRANSIENT_AREAS := ["echo_trial"]`, `DIRECTOR_AREAS := ["below"]`,
`AREA_DEFAULT_RESPAWN`, `HAVEN_DESTINATION`, `CH2_REWARD_ID := "rw_ch2_feast"`.
`new_game(look := {})`, `can_manual_save()`, `area_allows_saving(a)`, `player_in_safe_zone()`,
`boss_active()`, `can_fast_travel() -> {ok, reason}`, `lantern_road_destinations()`,
`travel_lantern_road()`, `lantern_road_travel(dest_id) -> bool`, `companion_present(id) -> bool`,
`return_point(area, arrival_spawn)`, `area_respawn_of(area)`, `set_respawn(area, spawn)` (ignored for
trial areas; per-area memory in `GameState.player["area_respawn"]`), `complete_chapter_two(rewards := {})
-> bool`, `chapter_two_rewards()`. Trials: entered via `change_area`, never become the respawn point,
Continue from a trial resumes at the origin.
Placeholder areas (`src/world/areas_ch2/placeholder_area.gd` base; helpers `build_environment`,
`add_ground`, `add_walls`, `add_room`, `place_spawn`, `add_safe_spot`, `add_label`, `add_exit`,
`add_rest_point`, `room_at`, `get_zone_at`, `is_safe_zone`, `height_at`, `validate_position`) +
`area_exit.gd`, `rest_point.gd`. Wave C replaces each area script but keeps every spawn id, zone id and
exit target. `data/hallowmere_layout.gd` holds every Reach coordinate (LANDMARKS, POINTS, SPAWNS,
ARCHES, OUTPOST_BUILD_AREA). Waygate: surface site (-4, -86) (`Layout.CH2_POINTS["waygate"]`), spawn
`waygate`, `src/world/surface/waygate.gd` (`state()`, `repair()`, `travel()`). Lantern arches:
`src/world/common/lantern_arch.gd` (`setup({id, area, spawn, name})`, `is_lit()`, `light_arch()`).
Ward Stone: `chapter_two_available()`, `chapter_two_accepted()`, `apply_chapter_two_choice(pick)`,
`menu_options()`, `choose(option)` (read / wardrobe / lantern road / celebrate).
Surface annexes: `src/world/surface/annexes.gd` safe-loads `ANNEX_SCRIPTS` (c1x/*.gd with
`static func build(area)` and optional `static func grass_clearings() -> Array` [[Vector2, radius]] called
BEFORE grass is built). Legacy vegetation is guarded by a golden hash test.

## Music (A4)
Audio: `request_music(context, fallback := "", fade := 2.0)`, `release_music(context, fade := 2.0)`,
`try_play_music(name, fade) -> bool`, `music_position()`, `music_length()`, `set_music_layers(names, fade)`,
`current_music_layers()`, `prefetch_music(name)`, `music_director()`, `music_director_active()`,
`set_music_director_enabled(on)`. Director: `request/release(context_id)`, `get_debug_log()`, `state()`,
`current_cue()`; emits `Events.music_cue_changed`, `Events.combat_state_changed`. Data: `data/music.gd`
(CUES m01..m27 with bpm/bpb/bars, PLAYLISTS, CONTEXTS, AREAS zone->playlist, BOSSES). Areas NEVER call
`Audio.play_music`/`stop_music`; music follows `Game.area_id`/`zone_id` automatically. Bosses emit
`Events.boss_encounter_changed(id, active)` and `boss_phase_changed(id, phase)`; the Matron's phases 2/3
fade in m13 layers. Special cases: `Events.music_context_changed.emit("silence")` / `("")`.
All 26 new OGG files are imported (12 looping: m10-m12, m13 layers, m21-m23, m25, m26 l1-l3).

## Integrator changes after Wave A (lead)
`below_builder.gd` layout-agnostic (`Builder.new(root, seed, rooms)`); `checkpoint_lantern.gd` setup `area`;
`lower_gate.gd` setup `flag`/`key`/`locked_text`; `below_lift.gd` setup `requires_flag` + instance
`usable()`; `src/core/lore_db.gd` (spec §10); annex grass hook; Game zone poll -> `GameState.discover`;
structure default interaction; `Crafting.check` refuses non-item recipes; UI category names for
wand/armor/charm/companion; single `chapter2_completed` emitter; tempo metadata + loop flags for the new
music; test fixes (asset scan ignores catalogue ids, one-shot test skips music cues, flaky hint assert).
