# Map: building / crafting / farming / inventory

Scope: `game/src/building/**`, `src/crafting/crafting.gd`, `src/farming/*`, `src/core/inventory.gd`,
`data/{structures,recipes,items}.gd`, `data/world_layout.gd` BUILD_AREA, the crafting/storage/inventory
panels and their tests. Paths are relative to `game/`. This map adds to `docs/ARCHITECTURE.md` and does not repeat it.
Read-only owners: `autoload/`, `data/`, `src/core/` are integrator-owned (golden rule 7). Several recipes
below need changes there. Those changes are marked **[integrator]**.

## 1. Runtime construction

1. `autoload/game.gd:249-252`: after `player.teleport(...)` and **in the same frame**, `BuildingSystem.attach(area)`
   runs only for `"surface"` (or `"arena"` when `Debug.is_cheat_allowed()`).
2. `building_system.gd:19 attach(area)` → `Factory.structures_root(area)` (Node3D `"Structures"`) → for each
   `GameState.structures` record whose `area` matches `Ops.area_id_of(area)`: `Factory.spawn_structure` → `Ops.notify_area(area)`
   → adds a `BuildMode` node named `"BuildMode"` (added after the player so its `_input` runs first). Calling it twice is safe: spawn returns the existing `S_<uid>`.
3. `structure_factory.gd:45 spawn_structure(area, uid)`: record → `create(sid, uid)` (script from `SCRIPTS`
   at :9-18, default `structure.gd`) → `setup({"uid","id"})`. The node is named `S_<uid>`, gets `position = pos` and `rotation.y = deg_to_rad(rot)`.
   An unknown sid produces `push_warning` and is skipped. The record itself is kept.
4. `structure.gd:32 _ready()`: `def = ItemDB.structure(id)`, group `"structure"`, meta `structure_uid`,
   child `"Model"` ← `Models.build(sid, model)` (returns `parts` dict), `_build_colliders()` (:66):
   `"Solid"` StaticBody3D layer 32/mask 0 from `Models.collision_shapes(sid)` when `def.solid`; `"Interact"`
   StaticBody3D layer 16/mask 0 from `Models.interact_shape(sid)` (box `size.x × max(h,0.6) × size.y`) when
   `def.interact != ""`. Both bodies carry metas `surface` ("wood"/"stone", `structure_models.gd:56`) and `structure_uid`.
   Then group `"interactable"`, then the virtual `_setup_behaviour()`.
   Subclass scripts: `workbench.gd` (group `crafting_station`, `station_id = def.station`), `storage_chest.gd`
   (lid tween on `parts.lid`, closes on `Events.ui_stack_changed(0)`), `bed.gd`, `lamp.gd` (for `lantern_post` and
   `heartbloom_lamp`: an OmniLight, no shadows, distance fade 38+10 m, group `light_source`), `echo_chime.gd`,
   `banner.gd`, `src/farming/crop_plot.gd`.
   Campfire station = `src/world/surface/campfire.gd` (world-owned, `station_id "campfire"`).
5. Other API: `play_place_anim()`, `play_remove_and_free()` (drops groups and colliders at once, then shrinks and frees),
   `set_highlight(on)`, `set_focused(on)`, `record()`.

## 2. Data shapes

**Structure def** (`data/structures.gd:18`). Keys: `name, item` (refund, must round-trip with item.place),
`layer` ∈ floor|decor|object|edge|roof, `snap` ∈ cell|floor2|edge2|roof2, `size: Vector2i` (1 m cells at rot 0),
`height` (m, collider/preview), `solid: bool`, `interact` ∈ ""|storage|sleep|farm|station, optional `station`,
`slots` (storage), `passable` (doorway), `light {color, energy, range}`.
The enum lists are enforced by `tests/unit/test_core_item_db.gd:13-15` (LAYERS/SNAPS/INTERACTS).
Sizes: workbench 2×1, bed 1×2, crop_plot 2×2 (not solid), rug 2×2 decor, walls edge2 h3.0, roof roof2 h1.2, other objects 1×1.

**Crop def** (`data/structures.gd:42 CROPS`): `{name, seed, grow_minutes, stages, yield: {item: [min,max]}}`.
`stages` is **not read by code**. Stages are always 4 (see §6). The test requires `yield` to include the seed.

**Recipe** (`data/recipes.gd`): `{result, count, station ∈ STATIONS keys, ingredients {id:n}, unlock: flag|""}`.
`STATIONS = {hand, workbench, campfire}`. Tests (`test_core_item_db.gd:97`): the station must exist, unlock flags must be set by the quest chain,
ingredients must fit in `INVENTORY_SIZE` slots, count ≤ stack, no quest-item ingredients, no self-consumption.

**Item** (`data/items.gd`, defaults `autoload/item_db.gd:11 ITEM_DEFAULTS`): `name, desc, cat, stack, icon, color`,
`tool ("axe"|"pickaxe"), power, damage, reach, heal, place, quest`, plus the non-defaulted `buff {stat_mult, seconds}`
(exactly 2 keys per the test), `crop` (seeds), `alt_name/alt_desc`. `cat` must be in `CATEGORY_ORDER`
(`items.gd:66`: tool, weapon, equipment, food, resource, seed, placeable, key). Note that **"decor" is documented but not
in CATEGORY_ORDER**, so using it fails the tests. The player's use-item (`player.gd:~861`) handles `food`→`eat`,
`placeable`→`build_mode.begin(id)` and `seed`. Every `icon` needs a drawing in `src/ui/icon_factory.gd`, and every
`ITEM_ICONS` entry (:21) must be used by some item (`tests/unit/test_ui_icons.gd:34-36`).
`test_items_in_category` hard-codes the tool list `[stone_axe, stone_pickaxe]`.

**GameState** (`autoload/game_state.gd`): `structures[uid] = {id, area, pos:[x,y,z], rot: float deg (raw 0/90/180/270,
walls too), data:{}}`. uids are `"s<N>"` (`new_uid`, and `next_uid` is repaired from the max suffix at :610).
`storages[uid] = Inventory` (created in `add_structure:307` for interact=="storage" with `def.slots`).
`crops[uid] = {crop:"", planted_at: total_minutes, tended_minutes}`. `from_dict` (:536-564) keeps unknown extra
record keys (`for extra in e`) and deep-copies `data`. It **re-creates storages with `def.slots` and then `from_array`,
which truncates** anything beyond the size. It creates a crop record for every farm structure and drops orphan crops.
Storages are saved as `to_array()` (length = size, nulls included). `SAVE_VERSION = 1`, and `SaveSystem.migrate()` is an empty hook (`save_system.gd:151`).

**Inventory** (`src/core/inventory.gd`): `size`, `slots[]` (null | `{id, count}`), signal `changed`.
`add(id,n)->int leftover` (tops up existing stacks first, then empty slots from index 0 = hotbar first; unknown ids refused),
`remove(id,n)->bool` (all-or-nothing, last stacks first), `space_for/can_add`, `free_slots`, `totals()`, `set_slot`,
`move`, `transfer_slot_to(other,i)`, `sort_items(keep_hotbar=true)` (slots 8+), `to_array/from_array` (truncates to
`size`, int-normalises JSON floats), `snapshot()/restore()`. There is **no resize()**. The backpack is
`GameState.inventory = Inventory.new(INVENTORY_SIZE=32)`, `HOTBAR_SIZE=8` (slots 0..7). Quest items live in
`GameState.key_items`, never in an Inventory. `give_item` overflow becomes a persistent world pickup and is never lost.

## 3. Grid, snapping, layers, heights (`src/building/placement.gd`, pure and ctx-driven)

Constants (:24-29): `TILE 2.0, WALL_HEIGHT 3.0, WALL_THICKNESS 0.22, FLOOR_TOP 0.12, MAX_UNEVEN 0.45,
OBSTACLE_SHRINK 0.7`. Messages (:31-35).
- `norm_rot(snap, deg)` (:49): 0/90/180/270. edge2 is reduced `%180` **only for footprints**. The stored rot stays raw, so a
  window can face either way.
- `snap_position(def, point, rot)` (:78): cell → footprint centre `round(p - s/2) + s/2` (1×1 → x.5, 2×1 → integer x);
  floor2/roof2 → `floor(p/2)*2+1`; edge2 → centre of a 2 m grid-line segment. It keeps `point.y`.
- `footprint(def,pos,rot)` (:96) → `{layer, cells:[Vector2i], edges:[Vector3i(k,m,dir)], rect: Rect2(x,z), rot}`.
  Edge key `dir 0` spans x∈[2k,2k+2] at z=2m, and `dir 1` spans z∈[2m,2m+2] at x=2k.
- Occupancy (:144 `build_occupancy`) = `{layer: {cell|edge: uid}}`. Overlap is refused **only within the same layer**
  (floor, decor, object, edge and roof are independent, so rugs (decor) sit under tables and objects sit on floors).
  The cell and edge keys carry **no height or storey dimension**.
- `placement_y(sid,pos,rot,ctx)` (:234), sampled at 5 points (centre + corners inset 0.08): floor2 → max ground;
  edge2 → min ground; roof2 → `max(wall base on its 4 tile edges) + 3.0`, else the neighbouring supported roof's y;
  objects → `max(centre ground, max floor.y + FLOOR_TOP over their cells)`.
- **Vertical placement today**: nothing sits above ground level except objects lifted 0.12 m by floor tiles and roofs at wall
  base + 3 m. Floors cannot stack (one floor per cell). There are no storeys or stairs. The cursor ray's hit y is ignored when
  `height_fn` exists (live game: `area.height_at`), so aiming at a roof still places on the ground below.
  `Ops.reseat_objects(area, cells)` (build_ops.gd:198) re-lifts objects after a floor under them is placed or removed.
- Model collision (`structure_models.gd:63`, cached per sid in `_shape_cache`): floor = convex slab with a sloped skirt
  (top 0.12, 1.28 half-width at y 0) so the player steps on; walls are boxes 2.1×3×0.22; the doorway is two jambs + a lintel
  (`models_building.gd DOOR_HALF 0.55, DOOR_SPRING 1.95`); the roof is convex (`roof_collision_points`, 31° pitch, eave +Z,
  ridge −Z at rot 0); the table is a cylinder; the default is a box `(size − 0.08) × height`.
- Player physics relevant to new geometry: capsule r 0.32 h 1.6 (`player.gd:112`), `floor_max_angle 46°`,
  `floor_snap_length 0.35` (:104), step-up `STEP_HEIGHT 0.3` (`player_logic.gd:24`), jump ≈ 1 m, **no fall damage**.
  Companions use `floor_max_angle 52°` and **no navmesh** (they steer directly, and stuck recovery teleports them).
  The arena stair pattern is `tests/preview/arena.gd:42-47` (visual steps + one rotated BoxShape3D ramp).

## 4. Validation (`Placement.validate(sid,pos,rot,ctx) -> {ok, reason, blocker, y}`, :351)

The order is: def exists → all 4 rect corners inside `build_area` circle → `rect_hits_circle` against each blocked circle
("Too close to the <name>" or `MSG_CLEAR`) → same-layer overlap (returns the `blocker` uid so BuildMode can highlight it and hint X)
→ roof2: `roof_supported` (a wall on one of its 4 edges, or a neighbour roof that has one) / everything else: ground
max−min ≤ 0.45 → enclosure → `ctx.physics_fn`.
ctx keys (:14-22): `structures, area_id, build_area, height_fn, player_pos, physics_fn, occupancy` (cached per ctx).
`Ops.make_ctx(area, player_pos)` (build_ops.gd:66) fills them. `build_area_for("surface")` = `Layout.BUILD_AREA` +
`BLOCKED_NAMES`, cached in `static var _haven_area` (never mutates the const, which is tested).
- **Never trap Krystal** (`would_enclose`, :412): a BFS on the 1 m grid. Blockers are `blocks_movement(def)` pieces (solid, not
  `passable`, layer not floor/roof). Walls block *crossings* (`_add_blockers` :482, crossing keys at :480), blocked circles
  × 0.7 fill cells **inside the obstacle bbox only**, and escaping = leaving the bbox of all obstacles. A piece is refused only
  if it *causes* the enclosure (`would_enclose(with) and not would_enclose(without)`). The check is 2D and ignores y.
- `BuildMode._physics_check` (build_mode.gd:441): solid pieces run a box query on mask 2|4 ("You're standing in the way" /
  "<Companion> is in the way"). Non-roof pieces run a box on mask 1 (world) lifted 0.45 m ("Something is in the way").
- Haven data: `BUILD_AREA = {center (0,0), radius 16, grid 1, blocked: Ward Stone (0,−6) r3.5, campfire (4,3) r2.2,
  start path (0,7) r1.8}`.

## 5. BuildMode (`build_mode.gd`, Node in group `build_mode`, child of the area)

Constants: `MAX_REACH 8` (horizontal), `RAY_LENGTH 45`, `REVALIDATE_SECONDS 0.2`. Local signals: `placed(uid)`,
`dismantled(uid)`. API: `begin(item_id="")` (if it can't start yet it retries for 1.5 s once the UI closes), `end()`, `is_active()`,
`get_state()`, `placeables()`, `cycle(dir)`, `select_number(i)`, `rotate_step()`, `try_place() -> uid`, `try_dismantle() -> bool`,
`debug_cursor: Vector3` (tests). Keys: build/pause/interact exit, attack places, R rotates, X dismantles, wheel and 1-8 select.
It sets `player.build_mode_active` and clears it 0.15 s after exit.
Per frame (`_update` :293): cursor ray (mask 1|32, player excluded) → `snap_position` → validate only when the key
`"sid|rot|x|z"` changes, on `_dirty`, or every 0.2 s. Ghost = `Models.build` + `U.ghost_mat(valid)` override, a footprint plate
and a facing arrow for cell snaps. The grid is an ImmediateMesh rebuilt only when its key changes. `_structure_under_cursor` walks the
collider's parents for meta `structure_uid`, else falls back to `structure_at_point` on a cached `_occ` (dirty on
`structure_placed/removed`).
Emits `Events.build_mode_changed`, `build_selection_changed(item)`, `build_placement_state(valid, reason)` (deduplicated).
The HUD build bar (`src/ui/hud/build_bar.gd:84`) shows **at most 8** placeables.

## 6. Place / dismantle (`build_ops.gd`)

`place_structure(area, item_id, pos, rot) -> uid` (:89): `take_item(item,1)` → `add_structure` → spawn + anim → (floor)
`reseat_objects` → counter `structures_built` → `notify_area` → `Events.structure_placed(uid, sid)`. The caller validates first.
`can_dismantle(uid)` (:112): a storage is refused (`MSG_CHEST_FULL`) unless all contents fit, simulated on a copy of the backpack;
edge/roof are refused if any currently supported roof would lose support. `dismantle(area, uid)` (:151): chest
contents → `give_item`; a ripe plot is harvested, a growing plot refunds 1 seed; `remove_structure`; node
`play_remove_and_free`; refund `def.item` ×1 via `give_item` (overflow drops); floor → reseat; a respawn bed →
`_forget_bed_spawn`; `notify_area`; `Events.structure_removed`. Dismantling twice in a row refunds only once (tested).
The bed re-registers spawn `bed` one physics frame after any placed/removed event (`bed.gd:221`), using `would_enclose`.
The surface hides grass/flowers under structures via its own listener (`surface_world.gd:126-170`, deferred mask rebuild,
radius from `max(size)`).

## 7. Models and batching (performance)

`batch.gd`: collects `[mesh, xform, color]` (`rbox, cyl, sphere, torus, prism, blob, heart, heart_round, add`) and `bake()`s
one vertex-coloured ArrayMesh (colours converted `srgb_to_linear`, winding flipped for negative determinants).
Tessellation scales with size. `model_util.gd`: `baked(key, builder)` caches per key **for the whole process**
(one mesh shared by every copy); `vc_mat()` = `Mat.toon(WHITE, {vertex_color})` (the toon albedo *multiplies* vertex colour),
`vc_outlined(th)`, `ghost_mat`, `highlight_mat`, `glass_mat`, `sparkle_mat`, `instance(parent, mesh, mat, pos, rot)`,
`pivot()`. `shapes.gd` caches primitives. Builders are in `models_furniture.gd`, `models_building.gd`, `models_decor.gd`
and `farming/crop_models.gd`. Returned parts: chest `lid`, lamp `flame/light_pos`, heartbloom `bulb`, chime `shards/shard_mat`
(a `toon_unique` material per chime), banner `cloth`. Unknown sids get `_fallback` (a rounded crate in the item colour).
Budget test (`test_building_structures.gd:136`): **< 9000 tris and ≤ 8 GeometryInstance3D per structure**. Also tested:
every sid spawns with collider mask 0, a `surface` meta, a solid body iff `solid`, an interact body iff `interact`, and the contract
dict. Lamp, chime and banner run `_process` every frame. Crop plots use one MultiMesh (9 plants, 1 draw call).

## 8. Farming (`src/farming/farming.gd`, static)

`progress = clamp((total_minutes − planted_at + tended_minutes) × mult / grow_minutes, 0, 1)` (:49).
`mult = WARD_GROWTH_MULT 1.5` when flag `ward_restored`, applied **retroactively** at read time.
`stage_for_progress` (:65): `p ≥ 1` → 3 ripe, else `floor(p×3)` clamped 0..2 (0 sprout, 1 leaves, 2 bushy).
API: `plant(uid, seed="", sound_pos)` (consumes 1, `Events.crop_planted`, counter `crops_planted`), `harvest(uid, drop,
rng)` (`roll_yield`, resets the record, `give_item`, `Events.crop_harvested(uid, crop, main_count)`), `tend(uid, min)` (only
while growing), `plots_needing_care(area)`, `ripe_plots`, `plot_position`, `minutes_remaining`, `format_minutes`,
`choose_seed()` (the selected hotbar seed, else the first seed in the backpack), `crop_for_seed`.
Mochi (forager, home) calls `Farming.tend(uid, TEND_MINUTES=30)` every 22-35 s on plots < 30 m from its home
(`companion.gd:34, ~1073, 1139`). The clock: `advance_clock` (night ×2.5), `skip_to_morning`, and `time_of_day_changed` about once per game minute.
`crop_plot.gd`: `refresh()` (cheap: compares `_stage`), driven by crop events and time_of_day. `CropModels.stage_mesh(stage)`
is **crop-agnostic** (cache key `crop_stage_%d`, sweetroot orange). `plant_positions()` is a 3×3 grid, `SOIL_TOP 0.18`.
Setup param `stage` forces a preview stage.

## 9. Crafting (`src/crafting/crafting.gd`, static)

`STATION_RADIUS 4.0`. `stations_near(pos)` scans group `crafting_station` (`station_id`), always including "hand".
`check(rid, stations) -> {ok, reason, missing}` checks in this order: unknown → locked → station → missing → result fits.
`craft(rid, stations)` (:87) is transactional: re-check, snapshot the backpack and `key_items`, remove every ingredient
(`inv.remove`), add the result, and restore both on any failure. Only after commit does it emit `item_removed` for each ingredient,
`item_added`, `crafted(rid, result, count)`, `stats.items_crafted += count` and `ui_craft`. It never awaits.
`_result_fits` simulates on a copy (removing ingredients may free a slot). The UI goes through `UiUtil.craft_check/craft/stations_near(pos, extra)`
(`ui_util.gd:387-453`, where `extra` = the station that opened the panel counts as present). The crafting panel tabs are
**hard-coded** at `crafting_panel.gd:43` (all/hand/workbench/campfire). Full-screen panels pause the game, so the clock stops.

## 10. UI panels

`storage_panel.gd` (args `{uid}`): chest grid of **5 columns** × 88 px, a backpack grid of 8 columns from
`GameState.INVENTORY_SIZE` (:76, :130), a `chest.changed` connection, Take all / Store all. `inventory_panel.gd`: 92 px slots,
backpack `range(HOTBAR_SIZE, INVENTORY_SIZE)` (:68). `_build()` runs on open (`panel_base.gd:61`). Registry: `ui_root.gd:23-39`.

## 11. Chapter Two (Wave B: B5 crafting/stations/mastery, B6 building + integration) — as built

Sections 1-10 map the Chapter One code (many recipes below are now built). Source of truth: the headers of
`src/crafting/crafting.gd`, `src/crafting/furnace.gd`, `src/core/mastery.gd`, `src/building/build_mode.gd`, `build_ops.gd`,
`placement.gd`, `structure_factory.gd`.

**Crafting (`crafting.gd`, static; legacy signatures kept).** Recipe kinds (`kind(rid)` = `ItemDB.recipe_kind`): `"item"`
(instant), `"timed"` (furnace queue only), `"apply"` (`backpack_40` / `backpack_48` grow `GameState` capacity; `chest_40` upgrades
ONE chest in place from the storage panel), `"pattern"` (wardrobe ownership via `GameState.unlock_pattern`) and `"dye"` (ids
`"dye:<palette>"`, mixed once at the Loom; `GameState.unlock_palette(id)` when present, R07). API: `stations_near(pos)`,
`nearest_station(pos, station)`, `nearest_station_uid`, `known_recipes()`, `known_special(station)`, `recipes_for_stations`,
`recipe_def`, `kind`, `is_known`, `display_name`, `effect_text`, `check(rid, stations, sources := [], target := "")`,
`craft(rid, stations, sources := [], target := "") -> bool`, `max_craftable`, `plan(rid, sources)` (says where each ingredient
comes from), `count_available`, `transact(ingredients, sources, commit: Callable)`, `upgrade_chest(uid, sources)`,
`chest_upgrade_info`, `refund_chest_upgrade(rec, drop_pos)`, `chest_sources_near(pos, area_id := "", radius := CHEST_RADIUS)`,
`use_chests()` / `set_use_chests(on)`, `owns_palette` / `owns_pattern`, `dye_ids()`, `table_decor()` / `decorate_table(choice)`,
`seasonal_dishes_cooked()`, `static var last_reason`.
* **Crafting from nearby chests** (opt-in toggle in the crafting panel): placed storage chests within **`CHEST_RADIUS` = 18 m** in
  the SAME area, stable uid order; ingredients come from the backpack (+ key pouch) first, then the chests; ONE transaction
  (snapshot/restore) covers backpack, key pouch and every source chest, and nothing is consumed when the result can't be created.
  Lead decision R136 a: 18 m stays (it came from B5's reading of the relayed "use 18 instead of 8", which every other module read as
  the agent count; generous same-area chest crafting is cozy, never crosses areas, and is one constant to revert).
* Kitchen: "The Harvest Table" counter `ch2_seasonal_dishes` (distinct dishes, flags `ch2_cooked_<dish>`, the same five dishes as the
  story tracker; candy doesn't count). `decorate_table(choice)` stores the choice and sets `ch2_table_decorated` (with placing a
  `lanternwake_table`, the only ways to complete "Set a table for the festival"; a plain legacy table no longer counts, R44).
* Mastery XP for crafting comes only through `Events.crafted` (furnace jobs when they finish).

**Furnace (`src/crafting/furnace.gd` static + node `src/building/structures/furnace.gd`).** A finite queue of jobs on the
`GameState.stats.play_seconds` timeline (advances only while unpaused; the crafting panel is fullscreen, so the queue is frozen
while it is open — by design, the panel says so). Capacity = data `queue` (4) + 1 at hearthcraft rank 3 (`Mastery.furnace_queue_bonus()`).
API: `enqueue(uid, rid, sources := []) -> bool` (transactional), `can_enqueue`, `settle(uid) -> int` (moves finished jobs to the output
buffer exactly once, emitting `Events.crafted` per job), `collect(uid) -> int` (what doesn't fit stays in the buffer, saved, never
dropped), `queue(uid)`, `output(uid)`, `progress(uid) -> {jobs, output, capacity, busy, ready}`, `capacity(uid)`, `job_seconds(rid)`,
`is_furnace(uid)`, `refund_all(uid, drop_pos)` / `refund_record(rec, drop_pos, uid)` (dismantle returns queued ingredients and
finished bars once). Node API (spec §9): `queue_add(rid) -> bool`, `queue() -> Array`, `collect() -> int`; the panel opens with
`Game.open_panel("crafting", {"station": "furnace", "uid": uid})`. Steady glow with `reduce_flashing`.

**Record / state keys.** `GameState.structures[uid].data`: `queue` [{recipe, start, end}], `output` {item: n}, `held_jobs` (jobs whose
recipe this build doesn't know — kept for a newer save, not refunded on dismantle), `slots` (40 = upgraded chest), `upgrade_refunded`
(the chest upgrade kit was paid back once), `tint` (recolour palette id), `face` (pumpkin face), `level` (1 = upper storey).
`GameState.stations` (reserved dict, spec §3) holds two B5 keys: `use_chests` (bool, the panel toggle) and `table_decor` (the festival
table choice).

**Chest / backpack upgrades.** `Inventory.resize` grows only; the chest 20 → 40 upgrade keeps uid, contents, slot order and the
Inventory object; dismantling an upgraded chest returns contents, the chest and the upgrade kit (6 wood + 2 iron bars) once
(`storage_chest.gd` refunds itself; an explicit `build_ops` hook is optional and never pays twice). Full-backpack refusal shows both the
panel line and a toast (kept, R136 e).

**Mastery (`src/core/mastery.gd`, static; state `GameState.mastery`).** Wired once by `Game.wire_session_systems()` (called from
`Game._ready`; idempotent; R02). `init()` / `shutdown()` / `is_listening()`, `tracks()`, `xp(track)`, `rank(track)` (0..5),
`progress(track)`, `track_name(track)`, `effect(key, default)`, small effects read by Stats / stations / food: `gather_power()`,
`bonus_yield_chance()`, `furnace_queue_bonus()`, `station_time_mult()`, `meal_buff_bonus()`, `sprint_stamina_save()` (Stats applies
them once — mastery only exposes values), `award(track, kind_id, xp := -1) -> int` (first-time kinds dedupe, repeats capped per
in-game day, no XP for dismantle/rebuild, chest shuffling, loading, equipping, healing), `apply_legacy_credit()` (once, recorded,
only for a mastery record without progress), `legacy_credit_preview()`, `legacy_applied()`. Map / world rewards (R22):
`known_spots(area)` (resource spots from `Events.harvested`, `GameState.mastery.spots`, bounded), `cache_hints(area)`,
`resource_pins_on()`, `cache_hints_on()`, `highlight_radius()` (Gathering 4 sparkle, `src/world/common/gather_sparkle.gd`).

**Farming.** New crops `sunflax` / `roseberry` / `pumpkin` with 4 stage meshes each (`CropModels.stage_mesh(stage, crop)`, plant counts
9/4/1 on a plot, 6/2/1 on the Sturdy Planter `CropModels.planter()`); harvests set `c1x_grew_new_crop` and `ch2_pumpkin_harvested`;
the ×1.5 restored-Haven blessing is still applied on read (never compounds on reload).

**Building (B6).** Two storeys (`level` in data, `placement.gd requested_level`; stairs / upper floors / roofs pick their storey; the
flag `c1x_upstairs_reachable` = stairs actually lead onto an upper floor, `build_ops.update_upstairs_flag`, repaired on load, used by
"opt_upstairs", R36). Undo (Z / action `build_undo`): two-step confirm, exact refund, `structures_built` goes back too, up to
`UNDO_DEPTH` 10, **the undo list lasts one area visit**. Recolour (P / `build_recolor`): cycles natural wood and the owned dye palettes
(`data.tint`), **free once a dye is owned**, never automatic. Variant (N / `build_variant`): pumpkin faces before placing / re-carve;
the Lanternwake festival faces unlock with `ch2_feast` (R52; a locked or unknown saved face falls back to the first face without
rewriting data). Fallback keys (`FALLBACK_KEYS`) avoid every default binding until Settings gets the actions (deferred D03);
`BuildMode.key_label(action)` and `get_state()` (undo, undo_armed, face, level) feed the HUD build bar. The Haven grows by BUILD_AREA
`extra` circles; the Haven safe zone follows them + `HAVEN_SAFE_BUFFER` 4 m, and `surface_world.get_zone_at` reports "haven" there too
(R51). **Reach outpost**: the building system also attaches in `hallowmere_reach`; building only inside
`HallowmereLayout.OUTPOST_BUILD_AREA` (Commons cottage foundation; its circle may reach ~1.1 m past the Commons safe radius — spec
placement, kept, R136 f); bed and companion nooks are refused there (home stays at the Haven). `Game.load_area` restores a position
saved on an upper storey after the structures exist (R04).
**Structure scripts owned elsewhere** (`structure_factory.gd` `LAZY_SCRIPTS`, safe-loaded; a missing script falls back to the base
structure): `furnace` → B5, `companion_bed` / `companion_perch` → `companion_nook.gd` (B4), `wardrobe` / `vanity_mirror` →
`wardrobe.gd` (**owned by the appearance UI module B2**, lead decision R133), `pumpkin_lantern` (B6), `loom` / `kitchen_counter` →
`workbench.gd` with the data's station id. Gothic/cottage furnishing variants are the Midnight/Cream dye finishes (tints recolour
furniture); the Wardlight is the homecoming reward (R136 m).
Tests: `crafting`, `station`, `mastery`, `farming`, `economy`, `building`, `audit_building`, `audit_economy`.

## Extension recipes

*Status after Wave B: two storeys, the new pieces, recolour, undo, pumpkin faces, the bigger Haven (B6), the furnace queue,
Loom/Kitchen, chest/backpack upgrades, crops and mastery (B5) are built; §11 describes the current code, the recipes stay for history.*

**(a) Stairs + upper floors (two storeys).**
1. Data: add `"level"` to the records as `rec.data.level: int` (absent = 0, so all old saves stay level 0 and JSON float → `int()`).
   Add a `wood_stairs` def (`snap "stair2"`, i.e. a 2×4 footprint on the even grid so the stairwell is exactly two floor tiles; `layer "stair"`;
   `height 3.0`; `solid true`; new flag `"walkable": true`), plus an item, a recipe and an icon. Extend `LAYERS/SNAPS` in `test_core_item_db.gd:13-14`.
2. `placement.gd`: `const LEVEL_HEIGHT := WALL_HEIGHT`, `level_of(rec)`, and `footprint(def,pos,rot,level:=0)` returning
   `layer = l if level == 0 else "%s@%d" % [l, level]` (level-0 keys stay unchanged, so existing tests and saves are untouched).
   Pass the level from the record in `build_occupancy`. Make every hard-coded `occ.get("floor"/"edge"/"roof")` level-aware
   (`placement_y` :256-265, `_roof_base`, `_neighbour_roof_y`, `roof_supported`, `structure_at_point`).
   Upper floor tile: y = level-0 wall base + 3.0. It is supported like `roof_supported` (a wall under an edge or a supported neighbour).
   Upper walls sit on the upper floor. A roof at level n rests on level-n walls.
3. Stairs: `snap_position/footprint` cases for `stair2` (rot 0 rises toward −Z, entry at +Z). Collision in
   `structure_models.collision_shapes`: one ConvexPolygonShape3D wedge `(±1,0,+2),(±1,0,−2),(±1,3,−2)` = 36.9° (< 46°).
   The visual is a Batch of 12 treads (0.25 rise) + stringers in a new `models_building.gd` builder. Validation: refuse level-1 floor tiles
   over stair cells (head clearance 1.6 m + capsule), require the bottom landing (2 cells in front) to be free of level-0 blockers,
   and require the top landing cells behind the stair to be a level-1 floor or open. `blocks_movement` must return false for `walkable`.
4. Enclosure: `would_enclose` filters blockers to the player's level (`ctx.player_level` from `player.y − ground > 1.5`).
   On level ≥ 1, any cell without an upper floor tile counts as an escape (she can drop down, since there is no fall damage).
   `bed.gd:_is_shut_in` must pass the level.
5. BuildMode: take the level from the cursor hit (collider meta uid → its level). Require `normal.y > 0.7` so the underside of an
   upper floor never selects level 1. Put `ctx["level"]` in `_make_ctx`. `Ops.place_structure(..., level)` sets
   `structures[uid].data.level` **before** `Factory.spawn_structure`.
6. Dismantle: extend `can_dismantle` to refuse removing a level-0 wall that holds up a level-1 floor, and a level-1 floor that
   carries pieces (mirror the roof rule). Make `reseat_objects` per level, and have the grass mask skip level ≥ 1.
7. Tests: a new `test_building_storeys.gd` (reuse the `_ctx/_rec` helpers from `test_building_placement.gd:13-25`) + a live
   arena walk-up.

**(b) ~25 new decor/furniture pieces.** For each piece: `data/items.gd` (`cat "placeable"`, never "decor"), stack 20, `place`, `icon`
(reuse existing ids or add drawings + `ITEM_ICONS` in `icon_factory.gd:21` and the `_compose` match at :191); `data/structures.gd`
(`snap "cell"`, `layer "object"` or `"decor"` for flat rugs); `data/recipes.gd` (workbench, unlock "" or a quest flag). Add a
`structure_models.gd:18` `build()` case to a new `src/building/models_cozy.gd`: `U.baked("<sid>", func(b: Batch)...)` +
`U.instance(root, mesh, U.vc_outlined(0.012))`. Custom `collision_shapes` only where the box default is wrong; `surface_kind` for
stone pieces. Sway via toon `wind` opts, not `_process`. Stay < 9000 tris and ≤ 8 meshes each. Preview:
`--preview=res://src/building/preview_all.gd` lists every sid. Also fix the build bar's 8-item cap and `placeables()` cycling.

**(c) Recolor a placed piece, keeping its UID.** Store `rec.data.tint = "<variant id>"` (a String: a Color would not survive
JSON). Give `Models.build(sid, root, opts := {})` a default param and use `U.baked("<sid>|<tint>", ...)` with a palette swap,
or share a cached `Mat.toon(tint_color, {"vertex_color": true})` override (this tints the whole mesh). Add
`Ops.recolor(area, uid, tint) -> bool`: validate against a def list `"tints"`, consume a dye via `take_item`, set the data,
then respawn the node **after `root.remove_child(old)`**. `spawn_structure` returns an existing `S_<uid>` still in the tree,
and `queue_free` alone keeps the name for that frame. Then `notify_area`. Do not emit `structure_placed` (it is not a new piece).

**(d) Chest capacity 20 → 40 in place.** **[integrator]** Capacity is not saved today; it comes from `def.slots` at load.
(1) Persist `rec.data.slots = 40`. (2) `GameState.add_structure/get_storage/from_dict:551-554` must use
`maxi(def.slots, data.slots, saved_array.size())` **before** `from_array`. (3) Add `Inventory.resize(n)` (grow only:
append nulls, set `size`, emit `changed`), or replace the object while the storage panel is closed (the panel holds the old
reference and its `changed` connection). Upgrade op in build_ops: a transactional `take_item` for the kit plus data write + resize.
Refund the kit in `dismantle`. UI: at 40 slots the 5-column grid is 8 rows (~780 px), so switch to 8 columns or a ScrollContainer.

**(e) Backpack 32 → 40 → 48.** **[integrator]** Persist `GameState.player["bag_slots"]` (default 32). In `from_dict`, resize the
backpack **before** `inventory.from_array` (:515), or slots ≥ 32 are silently truncated. `reset()` must shrink it back to 32
(keep the same object: `_ready` connected `inventory.changed`). Replace `GameState.INVENTORY_SIZE` loops with
`GameState.inventory.size` in `inventory_panel.gd:68` and `storage_panel.gd:76,130`. Keep `INVENTORY_SIZE` (= base 32) because tests fill
the bag with it (`test_world_nodes.gd:145,177`, `test_audit_economy_world_items.gd:74`, `test_companions_node.gd:405`,
`test_core_item_db.gd:113`). `Crafting._result_fits`, `can_dismantle` and `sort_items` already use `inventory.size`. Never shrink it.

**(f) Furnace station with a saved finite queue.** Data: `STATIONS.furnace`, structure `furnace` (`interact "station"`,
`station "furnace"`, `light`, `queue: 4`), item, and a workbench recipe. Smelting recipes get `station "furnace"` + a new
`"minutes"` field. Add `SCRIPTS["furnace"]` → `structures/furnace.gd` extending `workbench.gd` (station group) + a lamp-style light;
`interact` opens `crafting` with `{"station":"furnace","uid":uid}`. State: `rec.data.queue = [{recipe, start, minutes}]`,
`rec.data.output = {item: n}` (cast JSON floats to int). A new pure `src/crafting/furnace.gd`: `enqueue(uid, rid)` (queue cap;
consumes like `Crafting.craft`'s snapshot/restore; `start = max(now, last end)`), `collect(uid)` (finished → `give_item`,
`Events.crafted` + stats), `progress(uid)`. Timing uses `GameState.total_minutes`, so jobs finish during sleep or away.
`Crafting.check` must refuse `minutes` recipes. Add the tab at `crafting_panel.gd:43`. Dismantle refunds queue and output (or refuses).

**(g) Crafting that pulls from nearby chests, transactionally.** Add an optional `sources: Array = []` to `check/_missing/
max_craftable/craft` (the default keeps tests). `chest_sources_near(pos, r)`: storage uids in the same area within r →
`GameState.get_storage(uid)`. In `craft`, snapshot the backpack, every source and `key_items`. Take from the backpack first, then the
chests, with per-source amounts (`remove` is all-or-nothing per inventory). `_result_fits` must simulate removing only the backpack
share. Restore **all** snapshots on failure. Emit `item_removed` only for the backpack share. Show chest counts in the panel.

**(h) New crops (sunflax, roseberry, pumpkin).** `CROPS` entries (yield must include the seed, `stages: 4`). Seed items
(`cat "seed"`, `crop`, `icon "seeds"` with distinct colours) and produce items (`food` with `heal > 0`, or `resource`). Visuals:
change `CropModels.stage_mesh(stage)` → `stage_mesh(stage, crop := "sweetroot")` with the key `crop_stage_<crop>_<n>` and a per-crop
builder. `crop_plot.refresh()` must track `_crop` as well as `_stage` and set `multimesh.mesh` per crop. If a crop wants a different plant count
(pumpkin 2×2), rebuild the MultiMesh (the count is fixed in `_setup_behaviour`). `choose_seed` picks the selected hotbar seed, else the first
one found, which is a UX issue with several seed kinds. Add recipes (e.g. campfire) and a first seed source outside this subsystem.

**(i) Expand BUILD_AREA and the safe zone.** Edit `data/world_layout.gd:12` radius/blocked **[integrator]**. Constraints:
terrain is exactly flat only for r < 19 and blends to r = 37 (`src/world/surface/terrain.gd:135-139`, hard-coded), after which
`MAX_UNEVEN` starts refusing. The Haven fence ring has world colliders at r = 19.2 (`landmarks.gd:121-143`), so `physics_fn` refuses there.
Vegetation exclusions must move together (`vegetation.gd:19 HAVEN_RING [16,34]`, :71 trees < 19.5, :223 bushes 20-30,
:241 small props 15.5, :394 flowers 16.5-23). Regenerating changes harvestable node ids and depletion keys. Add blocked circles for the
stream (≈ (20,−5), 4 m wide) and the sign (−7.5,−14.5). Companion home spots (`SPAWN_HINTS`) are not blocked today.
Safe zone = `LANDMARKS.haven.radius` 20 (`surface_world.gd:321-325`). `HAVEN_RADIUS` 20 keeps spawners +10 m away
(`landmarks.gd:640`). Keep the build radius inside the safe radius.

## Risks

- **Ids are save keys.** Renaming or removing a structure id keeps the records (invisible, skipped with a warning) but **silently drops chest
  contents** on load, because storages are only rebuilt for defs with `interact "storage"`. The same applies to item ids (unknown items are discarded by `from_array`).
- Changing `size/snap/layer/height` of existing ids re-footprints saved pieces: overlaps (occupancy is last-writer-wins), different
  enclosure results, moved colliders. Lowering `slots` truncates chest contents on the next load.
- Any storey or level scheme must leave level-0 occupancy keys (`"floor"`, `Vector2i`, `Vector3i(k,m,dir)`) byte-identical, or
  placement tests and old saves change meaning.
- Backpack or chest growth without the load-order fix loses items; there is no downgrade path. `SAVE_VERSION` is 1 and `migrate()` is empty, so
  add a version bump if the record shape changes.
- The growth multiplier is retroactive: new speed-ups (fertiliser) should bank progress in the record, not multiply total time.
  Tests pin the stage boundaries at 1/3 and 2/3 and ripe at 1.0.
- `U.baked` and shape caches live for the whole process. Changing a builder under the same key in one test run returns the old mesh.
- Exact-list tests: tool list, LAYERS/SNAPS/INTERACTS, CATEGORY_ORDER, ITEM_ICONS used both ways, recipe unlock flags reachable,
  seed-in-yield, geometry budget, collider masks/metas, interaction contract, crafting atomicity under rapid repeats.
- `Events` signals cannot be added by module owners. Use local signals (`BuildMode.placed/dismantled`) or request them.
- Loading relies on `attach` running synchronously right after `player.teleport` (game.gd:245-252). If spawning is deferred,
  players saved on upper floors or roofs fall. Companions have no navmesh and will need teleport help between storeys.
