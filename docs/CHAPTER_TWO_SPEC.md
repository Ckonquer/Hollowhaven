# Chapter Two — implementation contract ("The Lanterns of Hallowmere")

Source of the design: `Hollowhaven_Part2_Master_Prompt.md` (repo root; referred to as **MP §n**). This file
turns that design into the *actual* decisions for this repository: stable ids, the save schema v2,
who owns which file, and the APIs modules use to talk to each other. **Everything here is a contract:
build against it exactly.** When the contract and the master prompt disagree, the contract wins (the
disagreement is a deliberate implementation decision); when the contract is silent, follow the master
prompt, then `docs/ARCHITECTURE.md`.

Maps of the existing code (read the ones for your area before writing code): `docs/ch2/maps/*.md`.

## 0. Non-negotiables (summary of MP §2, applies to every module)
* Never rename/remove/reorder legacy ids: items, recipes, structures, creatures, enemies, flags,
  counters, lore, quest steps (`data/quests.gd` indices 0..15 stay exactly as they are), spawns, areas.
* Never change legacy world coordinates, terrain heights inside the Haven build area, resource node ids
  or their generation order in `surface` / `below`. New world content uses NEW namespaced ids
  (`ch2_*`, `c1x_*`, `hr_*`, `hw_*`, `mm_*`, `ta_*` prefixes, see §2) and is appended, never interleaved
  into existing deterministic generation loops (append after them, or use a separate RNG seeded by name).
* A completed Chapter One save must load with: same structures (uid/pos/rot/data), chests, crops,
  inventory order, key pouch, companions, flags, quest index, lore, clock. Migration only ADDS.
* Rewards are granted exactly once (reward ledger, §3.5). Loading twice changes nothing.
* No cheat reachable in release: debug hooks check `Debug.is_cheat_allowed()`.
* Arachnophobia: every spider-like new thing has a non-arachnid alternative (MP §8, §12, §13.2).
* Comfort: shakes/flashes via Events (scaled by settings), no audio-only required cues, `reduce_flashing`.
* Golden rules of docs/ARCHITECTURE.md (no class_name, code-built nodes, typed GDScript with tabs, state in
  GameState, talk through Events, data-driven).

## 1. Areas, spawns and travel

| area id | scene | what | safe zones | manual save | respawn |
|---|---|---|---|---|---|
| `surface` (legacy) | scenes/surface.tscn | Hollowhaven Woods + Chapter-One additions | Haven (expanded, §6.3) | yes (legacy rule) | bed / haven_respawn |
| `below` (legacy) | scenes/below.tscn | Old mine / ruins / silk hollows | landing, checkpoints | no (lanterns) | last lantern |
| `tobin_annex` | scenes/tobin_annex.tscn | Tobin's Lost Shift: 3 compact spaces off the mine mouth | `ta_entry` room | at its lantern | `annex_entry` / its lantern |
| `hallowmere_reach` | scenes/hallowmere_reach.tscn | New autumn surface region (~280 x 220 m) | Commons, Conservatory, arches | yes (like surface) | last lit arch (default `commons_arch`) |
| `moonveil_manor` | scenes/moonveil_manor.tscn | Manor interior, 5 spaces | Cloakroom, Balcony | at its candles (checkpoints) | `manor_entry` / last checkpoint |
| `hushed_works` | scenes/hushed_works.tscn | Chapter Two dungeon, 14 rooms | Landing, Refuge, Bell Throat | at checkpoints | last checkpoint |
| `echo_trial` | scenes/echo_trial.tscn | Optional replay arenas (Matron / Velour / Choir) | entry pad | no | trial origin (leaves the trial) |

Spawn ids (each area registers ALL of these in `_ready()` even while its content is unfinished):
* `surface` NEW: `waygate` (beside the Lanternwake waygate, arriving from the Reach), `annex_door`
  (beside Tobin's side door at the mine mouth), `annex_hatch` (surface end of the annex shortcut).
* `tobin_annex`: `annex_entry`, `annex_lantern` (checkpoint), `annex_hatch_below` (far end, by the hatch).
* `hallowmere_reach`: `waygate_arrival`, `reach_respawn`, `commons_arch`, `orchard_arch`, `quarry_arch`,
  `manor_arch`, `conservatory`, `manor_door` (outside the manor door), `bellhouse_stair` (outside the
  Bellhouse stair), `refuge_exit` (where the Works refuge shortcut comes out).
* `moonveil_manor`: `manor_entry`, `manor_ballroom` (checkpoint), `manor_balcony` (checkpoint/shortcut).
* `hushed_works`: `service_landing`, `works_lockers` (checkpoint), `refuge`, `crossing_gate`, `bell_throat`,
  `vault_exit`.
* `echo_trial`: `trial_start`.

Travel (all through `Game.change_area(area, spawn)`, which autosaves on arrival):
* surface `waygate` structure (after `ch2_waygate_repaired`) <-> reach `waygate_arrival`.
* surface annex side door <-> annex `annex_entry`; annex hatch (after `ta_hatch_open`) -> surface `annex_hatch`.
* reach manor door <-> manor `manor_entry`; manor balcony stair -> reach `manor_door`.
* reach Bellhouse stair (after `ch2_lamps_linked`, uses the Foreman's Key once: `ch2_service_gate_open`)
  <-> works `service_landing`; works refuge shortcut (after `ch2_refuge_shortcut`) <-> reach `refuge_exit`.
* **Lantern Road** (fast travel, MP §9): lit arches (flags `ch2_arch_<id>`, §8) + the ORIGINAL Haven Ward Stone.
  Interacting with a lit arch (or the Ward Stone "Lantern road" option once any Reach arch is lit)
  opens the travel list. Not while `Game.can_fast_travel()` is false (enemy threatening within 20 m,
  boss active, cutscene). Haven destination = surface `haven_respawn`.
* echo trial: entered from its origin checkpoint (below `arena_gate` checkpoint for Matron; manor
  ballroom for Velour; works bell throat for Choir) and always returns there.

`Game.AREAS` gains the new ids. `Game.SAFE_SAVE_AREAS := ["surface", "hallowmere_reach"]` replaces the
hard-coded surface checks: manual save + 5-minute quiet autosave + save-on-close are allowed there (same
"nothing chasing" rule), and in any area while `in_safe_zone` is true and no boss is active.

## 2. Id namespaces and naming
* Chapter-Two story flags/quests/encounters: `ch2_*`. Chapter-One optional additions: `c1x_*`.
* World node ids (harvestables, spawners, props that persist): surface additions `c1x_<kind>_<n>`,
  reach `hr_<kind>_<n>`, works `hw_<kind>_<n>`, manor `mm_<kind>_<n>`, annex `ta_<kind>_<n>`.
* Optional goals: `opt_*`. Reward ledger ids: `rw_*`. Music cues: `m01`..`m27`. Lore: `lore_ch2_*`.
* Enemy spawner ids: `<area prefix>_sp_<name>` (e.g. `hr_sp_orchard_mimics`), never a legacy spawner id.

## 3. Save schema v2 (owner: core-save module)
`SaveSystem.SAVE_VERSION = 2`. File name, folder, format string, atomic write, backup rotation unchanged.
New top-level keys in `state` (all optional on read; defaults below are what `migrate()` and
`GameState.reset()` produce):

```
"schema": 2,
"appearance": {look}                         # §4.1, legacy default = LEGACY_LOOK in data/appearance.gd
"wardrobe": {"owned": [part/pattern ids], "palettes": [palette ids], "presets": [{"name", "look"}],
             "notice_shown": false, "show_armor": false}
"equipment": {"head": "", "body": "", "boots": "", "charm": ""}   # item ids moved OUT of the backpack
"capacity": {"backpack": 32}                 # 32 | 40 | 48 ; inventory array length == capacity
"optional": {goal_id: {"done": bool, "done_at": float(total_minutes)}}
"chapter2": {"accepted": false, "done": [step ids], "baselines": {step_id: {counter: v}}}
"ledger": {reward_id: float(total_minutes)}  # reward-once ledger
"mastery": {"gathering": 0, "hearthcraft": 0, "wayfinding": 0,
            "seen": {"gathering": [], "hearthcraft": [], "wayfinding": []}, "legacy_credit": false}
"discovered": {area_id: [landmark ids]}      # map landmarks discovered
# (arches lit are flags ch2_arch_<id>, see §8)
"trials": {trial_id: {"clears": 0, "best_seconds": 0.0}}
"orphans": [{"where": "inventory"|"storage:<uid>"|"equipment", "slot": int, "stack": {...}}]
"stations": {}                               # reserved; station queues live in structures[uid].data
```
Companion records gain (defaults added by migrate/_load_companion, extra keys already survive):
`"combat_mode": "assist"` ("assist" | "close"), `"skill_ready_at": 0.0` (value of
`GameState.stats.play_seconds` when the signature skill is ready), `"home_spot": null` ([x,y,z] or
null), `"ribbon": ""`, `"home_task": ""`. Mochi's courage is the flag `c1x_mochi_courage`.
Structure `data` may carry: `"slots": 40` (upgraded chest), `"tint": "<palette id>"` (recolor),
`"face": "<face id>"` (pumpkin lantern), `"level": 1` (upper storey), `"queue"`/`"output"` (stations).
`player` dict: unchanged keys; `max_hp` stays the BASE 100 (effective max comes from Stats, §5).

### 3.1 Migration rules (SaveSystem.migrate, v1 -> v2)
Deterministic, idempotent, additive. Adds every missing section with defaults; appearance = LEGACY_LOOK;
`capacity.backpack = max(32, len(inventory))`; optional goals whose state is already satisfied are NOT
pre-marked (the optional log evaluates state on load and latches them normally; legacy free_play
progress is state-based so it carries over); `mastery.legacy_credit` is applied once by the mastery
module on first load (conservative credit from existing counters/stats, recorded). Never touches
legacy keys. Unknown top-level keys are kept (round-tripped) so a later patch never loses data.
### 3.2 Upgrade backup
Before the first write of a v2 save over a v1 file, `SaveSystem` copies the untouched v1 files
(`slot1.json`, `slot1.bak.json` if present) into `<save_dir>/pre_v2_backup/` as
`slot1.v1-<unix>.json` / `slot1.bak.v1-<unix>.json` (only if that folder has no `slot1.v1-*` yet).
Never deleted or rewritten by the game. Rollback instructions in docs/SAVE_MIGRATION.md.
### 3.3 Future versions
A main save whose `version` > SAVE_VERSION is NOT corrupt: `load_game()` refuses it with
`last_error = "This save was made by a newer version of Hollowhaven."`, does not move it aside, does
not fall back to the backup, does not write anything. Title shows Continue disabled with that reason.
### 3.4 Capacity & orphans
`Inventory.resize(n)` grows only (never truncates occupied slots). Loading uses the saved capacity
BEFORE `from_array`. Stacks with unknown item ids are kept in `GameState.orphans` (and written back on
save) instead of being dropped. Upgraded chests use `data.slots` when building their Inventory.
### 3.5 Reward ledger
`GameState.grant_once(reward_id: String, items: Dictionary, flags := [], message := "") -> bool`:
returns false (and does nothing) if `ledger` has `reward_id`; otherwise records it FIRST, then sets
flags, then gives items (overflow drops persistently), then notifies. Every story/boss/optional reward
goes through it. Quest `on_complete` of the chapter-two layer and optional goals use it too.

## 4. Data catalogue (owner: data module; everyone else reads through ItemDB)

### 4.1 Appearance (`data/appearance.gd`)
Look dictionary: `{"hair", "hair_color", "skin", "eyes", "upper", "lower", "shoes", "hat", "hair_acc",
"back", "palette": {"primary", "secondary", "accent"}, "outfit"}` (outfit = the preset it came from,
informational). Every value is an id from these tables:
* `HAIRSTYLES`: `side_braid` (legacy), `bob`, `long_waves`, `high_ponytail`, `twin_braids`, `space_buns`,
  `braided_crown`, `half_up_ribbon`.
* `HAIR_COLORS` (>= 12): `auburn` (legacy), `chestnut`, `espresso`, `raven`, `honey`, `platinum`,
  `strawberry`, `copper`, `rose`, `lavender`, `mint`, `sky`, `silver`.
* `SKIN_TONES` (6): `skin_1` .. `skin_6` (legacy value = the current avatar's skin colour).
* `EYE_COLORS` (8): `eye_1` .. `eye_8` (legacy = current).
* `PARTS` by slot `upper`/`lower`/`shoes`/`hat`/`hair_acc`/`back`, each with `name`, `slot`, `mesh`
  (builder id), `starter` bool, `pattern` (ownership id if earnable), `skirt` bool (sway), `hides_hair`.
* `OUTFITS` (complete looks): starter `cozy_explorer` (legacy), `strawberry_picnic`,
  `ribboned_adventurer`, `cloud_cardigan`, `moonflower_dress`, `mushroom_dungarees`; earnable
  `pumpkin_patch`, `ribbon_witch`, `velvet_vampire`, `ghostlight_party`, `moon_moth_shawl`,
  `lanternwake_dress` (each with its unlock source).
* `SWATCHES` (palette colours incl. rose, lavender, cream, mint, sky, plum, warm neutrals...) and
  `DYE_PALETTES` (rose, pumpkin, lavender, cream, ember, midnight) unlocked at the Loom.
* `LEGACY_LOOK`: exactly the Chapter-One avatar (auburn side braid explorer).
* `PRESET_SLOTS := 3`.

### 4.2 Items (`data/items.gd`, additive). New categories: `armor`, `charm`, `wand` (weapon with
`ranged: true`), `station` not needed (placeables). New fields: `tier` (tools/weapons/armor: stone 1,
copper 2, ironwood 3, moonsteel 4), `slot` (armor: head/body/boots), `reduction` (armor fraction),
`effects` (charms: {"gather": 0.1} etc.), `ranged`, `range`, `stamina`, `projectile`.
Ids: resources `sunflax`, `roseberries` (food), `resin`, `iron_ore`, `woven_cloth`, `copper_bar`,
`iron_bar`, `moon_crystal`, `moonsteel_bar`, `pumpkin` (food), `sugarcap`, `moonpetal`, `lantern_wax`,
`candy` (food); seeds `sunflax_seeds`, `roseberry_seeds`, `pumpkin_seeds`; tools `copper_axe`,
`copper_pickaxe`, `ironwood_axe`, `ironwood_pickaxe`, `moonsteel_axe`, `moonsteel_pickaxe`; weapons
`ironwood_sword` (25), `moonsteel_sword` (34), `sparkseed_wand`; armor `padded_hood/vest/boots`,
`copperwood_hood/vest/boots`, `ironwood_helm/mail/boots`, `moonsteel_helm/mail/boots`; charms
`gatherers_charm`, `swiftstep_charm`, `kindling_charm`; foods `pumpkin_soup`, `pumpkin_biscuit`,
`roseberry_tart`, `moonpetal_tea`, `lanternwake_platter`; companion gear `comfort_ribbon`;
key items `garden_seal`, `quarry_seal`, `manor_seal`, `velvet_scrap` (x3, Count's Wardrobe);
placeables: one item per new structure (§4.4).

### 4.3 Recipes (`data/recipes.gd`). New stations: `furnace`, `loom`, `kitchen` (+ legacy hand /
workbench / campfire). New recipe fields: `time` (seconds, furnace only: queued), `apply` (special
effect instead of an item: `backpack_40`, `backpack_48`; chest upgrade is done from the storage panel,
recipe id `chest_upgrade_40` with `apply: "chest_40"`), `unlock` (flag, as before), `pattern`
(wardrobe ownership granted instead of an item), `mastery` (optional hearthcraft rank gate - never on a
story-critical recipe). Quantities from MP §16 unless noted in the data file.

### 4.4 Structures (`data/structures.gd`, additive). New fields: `level_ok` (can be placed on an upper
floor), `stairs` (true), `support` (true: counts as support for upper floors), `station` for
`furnace`/`loom`/`kitchen`, `interact` new values `wardrobe` (mirror & wardrobe), `nook` (companion
bed/perch), `board` (expedition board), `music` (music box), `face` (pumpkin lantern face picker),
`tintable` (bool). Ids: `wood_stairs`, `upper_floor`, `wood_railing`, `half_wall`, `porch_post`,
`arched_window`, `gable_roof`, `roof_corner`, `flower_box`, `curtain`, `bookshelf`, `wardrobe`,
`vanity_mirror`, `kitchen_counter`, `furnace`, `loom`, `companion_bed`, `companion_perch`,
`sturdy_planter` (farm), `cottage_bench`, `pumpkin_lantern`, `pumpkin_lights`, `bat_bunting`,
`ghost_lantern`, `crescent_window`, `candy_bowl`, `scarecrow`, `gothic_trim`, `music_box`,
`expedition_board`, `wardlight` (Chapter Two home reward), `miner_lamp` (Tobin reward), `thread_veil`
(Crossing reward; alt name "Pale Veil Drape"), `lanternwake_table`.
Crops: `sunflax` (420 min), `roseberry` (480), `pumpkin` (600) with seed returns.

### 4.5 Enemies (`data/enemies.gd`, additive). `brambleback`, `lantern_moth`, `hollow_drudge`,
`brood_skitter` (alt_name "Pale Sprout"), `knotted_elder` (elite), `pumpkin_mimic`, `patchwalker`,
`velvet_wing`, `bellcap_sentry`, `borrowed_wisp`, `quarry_warden` (elite), `count_velour` (boss),
`crossing_matron` (boss; alt "The Hollow Mother"), `borrowed_choir` (boss). Stats: MP §12/§13 ranges.

### 4.6 Companion combat (`data/companion_skills.gd`) - ONE table with every number of MP §6.2/§6.3:
passive, basic attack (damage, interval, range, kind melee/projectile), signature (id, name, cooldown,
values), perks by bond level 2/3/5, `MOVE_BUFF_CAP := 0.30`, `REDUCTION_CAP := 0.45`.

### 4.7 Mastery (`data/mastery.gd`): tracks `gathering`, `hearthcraft`, `wayfinding`; `RANK_XP`
(5 ranks), xp per first-time kind / repeat action with caps, rewards per rank, legacy credit formula.

### 4.8 Music (`data/music.gd`): cue table `m01`..`m27` (`file`, `title`, `bpm`, `bars_per_phrase`,
`kind` explore/safe/combat/boss/ending/horror, `loop`), playlists (`haven_day` m02/m03/m04,
`haven_night` m05/m06, `woods` m07/m08 (+m09 at the pond), `mine` m11, `ruins` m12, `combat1` m10,
`boss_matron` m13, `restoration` m14, `reach` m15/m16, `orchard` m17, `quarry` m18, `candleyard` m19,
`manor` m20, `velour` m21, `combat2` m22, `works` m23, `refuge` m24, `crossing` m25, `choir` m26,
`celebration` m27, `title` m01). Retained legacy files: m01 = music_title, m02 = music_haven, m05 =
music_night, m13 = music_boss, m14 = music_ending.

## 5. Stats (owner: equipment module) — `src/core/stats.gd` (static, pure; tests call it directly)
`Stats.damage_reduction() -> float` = 1 - (1 - armor_sum) * (1 - pebble_passive) * (1 - charm) * ...
capped at `REDUCTION_CAP`; `Stats.move_mult() -> float` (1 + lumi passive + glimmerstep + charm,
cap +0.30); `Stats.heal_mult()` (Mochi passive, perks); `Stats.stamina_cost_mult()`;
`Stats.gather_bonus()`; `Stats.melee_damage(weapon_id) -> float`; `Stats.effective_max_hp()` (= base
100 unless a later design adds max HP). The player damage path: invulnerable? -> reduction ->
shield absorb (`GameState.player_shield()` transient, not saved) -> Health. Companion passives count only
for `GameState.active_companion` when that companion node is in the same area within 25 m of Krystal
(`Game.companion_present(id)`).

## 6. Module ownership (who edits what)
(Filled in per wave in docs/ch2/WAVES.md. Shared foundation files are edited only by the module the
wave assigns them to; everyone else reports needed changes.)

## 7. World layout decisions

### 7.1 Hollowhaven Woods (surface) additions — all OUTSIDE the legacy Haven build circle
* **Lanternwake waygate**: north of the Moonlit Ruin toward the world's north edge, on the outer route,
  away from the Haven (exact validated walkable spot chosen by the flow module and written to
  `data/world_layout.gd` as `CH2_POINTS["waygate"]`; target around (-14, -94)). Spawn `waygate` 3 m
  south of it. Dormant (vines + dim stones) until `chapter_one_complete`; repair prompt after
  `ch2_accepted`; lit and usable after `ch2_waygate_repaired`.
* **Tobin's side door**: on the mine cliff a few metres beside the legacy mine mouth (legacy entrance,
  rubble and `mine_exit` untouched). Spawn `annex_door`. The annex shortcut hatch comes out on the
  cliff top/side near the mine mouth: spawn `annex_hatch`.
* **Tailor's Cache**: near the Old Oak roots (outside its 10 m landmark radius edge is fine), a small
  chest-like cache with an environmental clue (ribbons on low branches).
* **Bramblewatch**: a NEW pocket on the Thornthicket outskirts (west/north-west of the legacy thicket
  spawner), Brambleback group + the Knotted Elder arena (open, several exits, cuttable roots).
* **Gardener's patch**: Sunny Meadow wild Sunflax patch + a Roseberry bush cluster (renewable).
* **Sap stumps**: 4-6 tappable Resin stumps spread over the woods (never inside the build area).
* **Mochi's courage lantern**: at the OUTSIDE mine threshold (legacy `mine_threshold` spot area).
* **Lantern Moth dusk pocket**: near Mirror Pond edges at dusk/night only (not in the Haven).
* **Seasonal decor** (setting `seasonal_decor`): a few pumpkins/ribbons along paths only.
* **Haven expansion** (MP §3): extra buildable regions appended to BUILD_AREA (`"extra": [...]`),
  never overlapping the stream, the Old Oak radius, the Ward Stone/campfire blocked circles, or the
  legacy start path; the Haven safe zone grows with the buildable boundary plus a 4 m buffer.

### 7.2 Hallowmere Reach (`data/hallowmere_layout.gd`, x east, z south, metres, origin = Commons centre)
Playable extent x in [-140, 140], z in [-110, 110]; soft boundary (hills, cliffs, dense autumn trees).
| id | name | centre | radius | safe | notes |
|---|---|---|---|---|---|
| `commons` | Lanternwake Commons | (0, 60) | 24 | yes | arrival arch `commons_arch` (0, 78), festival map board, stalls, festival mirror (wardrobe), cottage foundation (optional outpost build area r=8 at (-16, 54)) |
| `conservatory` | Ward-Keeper's Conservatory | (0, 6) | 14 | yes | lamp-linking pedestal, recipes, preparation notes + practice seam |
| `orchard` | Pumpkintide Orchard | (-82, 36) | 30 | no | `orchard_arch` (-60, 50), irrigation sluice, garden lamp, mimic pockets, pumpkin/roseberry beds |
| `pools` | Thimblebrook Pools | (-44, -8) | 18 | no | brook, stepping stones, moonpetals, sugarcap patch, chime trail |
| `candleyard` | The Candleyard | (-86, -60) | 22 | no | leaning stones, moonflowers, groundskeeper notes, dress pattern, bench |
| `quarry` | Ashbell Quarry | (86, 18) | 30 | no | `quarry_arch` (62, 38), lower iron terraces, winch (100, 0), upper Moon Crystal shelf (110, -26), Warden arena (90, 10) |
| `manor_grounds` | Moonveil Manor | (18, -74) | 26 | no | `manor_arch` (10, -50), manor door (18, -86) -> `moonveil_manor` |
| `bellhouse` | Sunken Bellhouse | (72, -74) | 16 | no | stair down -> `hushed_works` (revealed by `ch2_lamps_linked`) |
The waygate arrival (`waygate_arrival`) is at (0, 98) facing north. Main paths: arrival -> Commons ->
Conservatory, then three visible branches west (orchard), east (quarry), north (manor); the Candleyard
loops off the orchard/pools, the Bellhouse sits between quarry and manor.

### 7.3 Moonveil Manor (`moonveil_manor`), five spaces in a row with a return loop
Entrance Cloakroom (safe, exit) -> Looking-Glass Hall (reflection/light teaching) -> Ballroom (candle
routing puzzle; checkpoint `manor_ballroom`) -> Count's Gallery (Count Velour arena: three ward candles,
curtains, central light) -> Conservatory Balcony (Manor lantern, reward, stair shortcut to the
Cloakroom/outside, checkpoint `manor_balcony`, Pipkin rescue spot). Optional side rooms hold the three
`velvet_scrap` (Count's Wardrobe).

### 7.4 Hushed Works (`hushed_works`) room graph
1 Service Landing (safe, exit) -> 2 Tool Lockers -> 3 Humming Rails -> 7 Pocket Conservatory (hub,
safe, refuge shortcut to the Reach). Loop A: 3 -> 6 Hall of Closed Eyes -> 5 Bellmaker's Floor -> 7.
From the hub: 4 Sluice Gallery (water line), 5 Bellmaker's Floor (bell line), 8 Light Well (light line)
in any order. When all three lines are restored: 7 -> 9 Threaded Winch -> 10 Weaver's Crossing
(checkpoint `crossing_gate` before) -> 11 The Wrong Landing -> 12 The Borrowed Porch -> 13 Bell Throat
(safe, checkpoint, return choice) -> 14 Choir Vault (exit `vault_exit` after victory). Loop B: 11's real
lift returns to 7. Flags: `ch2_line_water`, `ch2_line_bell`, `ch2_line_light`, `ch2_crossing_cleared`,
`ch2_false_home_revealed`, `ch2_choir_defeated`, `ch2_refuge_shortcut`.

## 8. Fixed cross-module values (decided by the lead; use verbatim)
* `LEGACY_LOOK` (data/appearance.gd) = `{"hair": "side_braid", "hair_color": "auburn", "skin": "skin_2",
  "eyes": "eye_1", "upper": "explorer_jacket", "lower": "explorer_trousers", "shoes": "explorer_boots",
  "hat": "", "hair_acc": "flower_clip", "back": "satchel", "palette": {"primary": "teal", "secondary":
  "sunflower", "accent": "plum"}, "outfit": "cozy_explorer"}` — reproduces the Chapter-One avatar exactly
  (skin_2 = Palette.K_SKIN f0c6a0, eye_1 = the current iris colour, auburn = K_HAIR 7a3b2e, teal =
  K_JACKET 3fa7a0, sunflower = K_SCARF f2c14e, plum = K_PANTS 5a4a6e).
* Chapter Two acceptance = flag `ch2_accepted`; availability = flag `chapter_one_complete`. The layer is
  active when both are true. Lantern Road arches lit = flags `ch2_arch_<arch id>` (arch ids:
  `commons`, `orchard`, `quarry`, `manor`, `conservatory`), the Haven is always a destination once any
  arch is lit. Landmark discovery: `GameState.discover(area_id, landmark_id) -> bool` (new -> true).
* Equipment slots: `head`, `body`, `boots`, `charm`. Items with `cat == "armor"` carry `slot`; items with
  `cat == "charm"` go to `charm`. `GameState.equip(item_id) -> bool` / `GameState.unequip(slot) -> bool`
  are transactional (backpack full -> unequip refused with a reason, never lost).
* Companion present (support/passives): `Game.companion_present(id) -> bool` (follower, same area, <= 25 m).
* Rewards: `GameState.grant_once(reward_id, items := {}, flags := [], message := "") -> bool`.
* Combined tracker accessor: `GameState.current_objective() -> Dictionary` `{"source": "chapter2" |
  "legacy", "steps": [step dicts to display], "title", "status": [objective rows]}`.
