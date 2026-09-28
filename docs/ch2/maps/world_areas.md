# Map: world_areas (areas, surface world, the Below)

Paths are relative to `game/`. `Lnn` = line number when this map was written. This map adds to
`docs/ARCHITECTURE.md` and does not repeat it.

## 1. Area lifecycle (autoload/game.gd)

- `AREAS := {"surface": "res://scenes/surface.tscn", "below": "res://scenes/below.tscn"}` (L6). `TEST_AREAS`
  holds `arena`, which only loads when cheats are allowed. Each `scenes/*.tscn` is one root `Node3D` with the
  area script attached (surface → `surface_world.gd`, below → `below_world.gd`). The script builds everything
  inside `_ready()`, synchronously, while `change_scene_to_file` instantiates the scene.
- `load_area(target_area, spawn_id, use_saved_position=false)` (L204), beyond what ARCHITECTURE says:
  - Fades 0.45 s out and 0.6 s in.
  - An unknown id silently becomes `surface`.
  - It waits two `process_frame`s after `change_scene_to_file`.
  - `use_saved` is honoured only for `"surface"` (L240), through `area.validate_position`.
  - On the surface it waits one more frame and re-teleports if the spawn (e.g. `bed`) only now exists.
  - The director is created only for `"below"` (L259).
- `change_area(area, spawn)` (L324) calls `player.write_to_state()`, then `load_area(..., false)`, then
  resets the respawn point. On the surface that is `_bed_spawn_or("haven_respawn")` (L365). In the Below it is
  `_below_return_point(spawn)` (L344): `player.below_respawn` if that spawn exists, otherwise the deepest lit
  `area.checkpoints[*].spawn_id`. **Any other area gets the arrival spawn.** Last comes a *non-quiet*
  `SaveSystem.save_game()`.
- `continue_game()` (L186) falls back to `surface` when `player.area` is not in `AREAS`. It loads at
  `player.spawn` with `use_saved=true`, which only works on the surface.
- `respawn_player()` (L417): if the respawn area differs from the current one it calls `load_area`;
  otherwise it teleports in place to `get_spawn(respawn_spawn)`.
- Zone polling in `_process` (L52), every 0.4 s while playing: it emits `Events.zone_entered(area.get_zone_at(pos))`
  on change (including `""`) and `Events.safe_zone_changed(area.is_safe_zone(pos))`.
  - Consumers of `zone_entered`: `below_world._on_zone_entered` (mood and ambience) and
    `companion._on_zone_entered`, which gives bond XP once per **zone-id string** (`zone_bond` stores the ids
    in `companions[id].zones`).
  - Consumers of safe zones: the director, `enemy_base` (never targets a player in a safe zone, L442) and
    `enemy_spawner` (no spawning if the player **or the spawner** is in a safe zone, L133).
- Saving: `can_manual_save()` (L508), `_tick_autosave` (L129) and `save_before_close()` all work only when
  `area_id == "surface"`. For every other area the refusal reads "Underground...". Below saves happen only at
  lanterns.
- `complete_chapter()` (L523) awaits `area.play_restoration()`, then `ui.show_ending()`, then saves.

**Hard-coded area-id branches** (every new area must be checked against these):

| Place | Behaviour today |
|---|---|
| `game.gd` L240, L259, L130, L511 | saved-position restore, director, autosave, manual save: surface/below only |
| `companion_logic.gd` L7 `SURFACE_AREAS := ["surface","arena"]` | any other area is "dungeon-like": only the follower spawns, and only if `enters_below`. Mochi is sent to *wait at the mine threshold on the surface* |
| `player_logic.gd` L271 / `player.gd` L1085, L1105 | "outside" recovery (uses `WORLD_HALF_EXTENT`) and below-terrain recovery: surface only. `KILL_Y=-40` applies everywhere (also in `companion.gd` L1008) |
| `player_logic.gd` L373 `lantern_scale` | lantern dimmed in daylight: surface only |
| `player.gd` L1069 | footsteps: in `"below"` the collider meta (default stone); elsewhere `area.surface_at()` |
| `combat.gd` L237 | horror damage multiplier: `"below"` only |
| `map_panel.gd` L14-19, L62 | title/landmarks come from `data/world_layout.gd` for every non-below area |
| `pause_panel.gd` L101 `unstuck_spawn` | the "below" rule; everything else is sent to `haven_respawn` (the `get_spawn` fallback) |
| `day_dial`, `hud`, `ui_root` L389, `tracker` | cosmetic surface/below checks |

## 2. area_base.gd

- `spawns` maps id → `Transform3D`. `zones` is `[{id, center, radius, safe}]`, tested on XZ only.
- `get_spawn` (L19) never fails. It falls back to `haven_respawn`, then `haven_start`, then `mine_entry`, then
  the first registered spawn, then `(0,2,0)`.
- `get_zone_at` (L36): the **smallest** containing radius wins.
- `validate_position` (L58): ray from +3 m to −8 m on mask 1|32, then a 0.2 to 1.8 m headroom ray. Returns
  `hit + 0.1` or `null`.
- A new area script must set `area_id` itself. `world_item.spawn` reads `area.area_id` to tag drops (L86).

## 3. Surface: Hollowhaven Woods

### 3.1 Construction (`src/world/surface/surface_world.gd` `_ready` L56)

Build order, with each timing stored in `build_times[label]` by `_mark`:

1. `Terrain.new().generate()`
2. `SkyScript` (child "Sky")
3. `ShaderMaterial(surface_terrain.gdshader)` with `splat_tex = terrain.splat_image()`
4. `build_meshes(ground, mat)`
5. `build_collision(ground, TerrainBody)` with `body.area = self`
6. `WaterScript` (`terrain` set before `add_child`)
7. `plan = VegetationScript.plan(terrain)`
8. `clear_grass_for(terrain, plan)`. This must run **before** Grass, which reads the grass image in its `_ready`.
9. Vegetation, then Grass, then Landmarks, then AmbientLife
10. Bloom flowers via `vegetation.build_restore_flowers`
11. `_register_spawns`, `_add_zones`, `_build_boundary`
12. `_apply_restored_state(flag ward_restored)`, `_update_daylight()`, `_setup_structure_mask()`

Other entry points:

- `_process` is throttled to 0.25 s. It drives `landmarks.set_daylight` and `ambient.set_daylight` (from
  `sky.daylight`) and the audio cycle (`MUSIC_PLAY_SECONDS=175`, `MUSIC_REST_SECONDS=70`).
- `on_player_spawned` (L197) starts `amb_forest_day/night` and the music.
- Public queries: `height_at` (L242), `water_level_at` (L246), `surface_at` (L250),
  `is_inside_bounds(pos, margin)` (L254, rounded square `SL.BOUNDARY=104` and circle `104/0.86`).
- `validate_position` (L263) adds bounds, water depth > 0.6 m is rejected, and a crossing deck counts as dry.

### 3.2 Layout constants

- `data/world_layout.gd` (shared, read-only):
  - `WORLD_HALF_EXTENT=110`, `KILL_Y=-40`
  - `HAVEN_RADIUS=20`
  - `BUILD_AREA` (radius 16, blocked circles)
  - `LANDMARKS{id:{name,pos:Vector2,radius}}`. The ids are haven, glade, quarry, ruin (-12,-66) r20,
    mine_mouth, pond, meadow, old_oak, thicket. They are also the zone ids, and only `haven` is safe.
  - `STREAM_POINTS`, `STREAM_WIDTH`, `STREAM_CROSSINGS[3]`
  - `SPAWN_HINTS{id:Vector2}` (10 ids)
  - `CLOCK`
- `surface_layout.gd`:
  - `PATHS{id:[Vector2]}` (Catmull-Rom), `PATH_WIDTHS`, `PATH_FADE_IN`, `DIRT_PATCHES`, `CROSSING_STYLE`
  - `STREAM_END`, `POND_RADIUS=11.5`
  - `MINE_MOUTH=(54,-74)`, `MINE_FACING=(-6,10)`
  - `WARD_STONE=(0,-6)`, `CAMPFIRE=(4,3)`, `SIGN`
  - `QUARRY_TERRACE_DIR`, `BOUNDARY=104`
- Coordinates: x east, z south, 1 unit = 1 m. Surface spawn yaw uses `yaw_towards(from,to) = atan2(-dx,-dz)`
  (L282, forward is −Z). Spawns are registered from `SPAWN_HINTS` plus a local `facing` dict (L294) and
  mirrored as `Marker3D "Spawn_<id>"`.

### 3.3 Terrain (`terrain.gd`, RefCounted)

- Grid: `N=257`, `HALF=128`, 1 m spacing covering [-128,128]². The playable area is about ±104 and hills rise
  beyond an edge metric `e=max(|x|,|z|,0.86·r) > 86`.
- Data lives in Packed arrays indexed `j*N+i` (heights, path weight, water level, rock, splat, grass mask).
- `generate()` (L96) runs six passes: base noise, landmarks, paths, water, normals, colour.
  - Noise is sampled in bulk with `FastNoiseLite.get_image` (seeds 1234, 777, 4321).
  - `_landmark_pass` (L158) shapes each landmark **by hard-coded key**, so a new `LANDMARKS` entry gets no
    terrain shaping.
  - `_color_pass` (L399) writes into members instead of locals because **lambdas capture locals by value**.
- `height_at` (L494) uses the same triangulation as the render mesh and collider. Other queries:
  `water_level_at`, `is_water`, `path_at`, `stream_distance`, `rock_at`, `pond_distance`, `surface_at`,
  `clear_grass(x, z, r)`.
- `build_meshes` (L586): 8×8 chunks of 32 quads that share one index array, vertex colours in linear space,
  shadows on.
- `build_collision` (L643): a single `HeightMapShape3D` (257×257, centred on the body) on layer 1, meta
  "surface".
- `terrain_body.gd` refreshes that meta to the surface under the player every 0.12 s, because one collider
  covers everything. `get_surface_at(pos)` gives an exact per-point answer.
- The shaders `surface_terrain`, `surface_grass` and `surface_flower` hard-code the uniforms
  `terrain_origin=(-128,-128)` and `terrain_samples=257.0` (a scalar, which assumes a square grid). No script
  sets them.

### 3.4 Vegetation and stable ids (`vegetation.gd`)

`static plan(t) -> Dictionary` (L147) is **pure and deterministic**. Its keys:

- `trees`, `rocks`, `ores`, `bushes`, `sticks`, `stones`, `tufts`: `[{id, pos:Vector3, seed, yaw(deg),
  scale?, species?}]`
- `decor_trees`: `[sp, variant, Transform3D, collide]`
- `decor_bushes`, `mushrooms`, `logs`, `decor_rocks`, `brambles`: positional arrays
- `flowers` / `restore_flowers`: `[pos, yaw, scale, Color, bloom_dist, kind]`

How the ids are assigned:

- Id formats: `tree_%d`, `rock_%d`, `rock_q%d`, `ore_0..6`, `bush_%d`, `stick_%d`, `stone_%d`, `tuft_%d`
  (resource kind `grass`).
- Ids are sequential counters over **accepted** candidates, so any change in acceptance renumbers every later
  id.
- Each category uses a fixed RNG seed (trees 424242 on a jittered 6.5 m grid; rocks 515151; others in
  `plan()`).
- Acceptance goes through `_clear_of` (L89): path and stream distance, pond, rock, the `big_exclusions()` list
  (L69), and an `Occ` 4 m spatial hash.
- `big_exclusions()` **includes every `Layout.SPAWN_HINTS` point (3.5 m) and every stream crossing**. The small
  items use the same list (L241-245).

Instantiation (`_ready` L453):

- Resource nodes go into groups Trees/Rocks/BerryBushes/Forage. `vegetation.resource_nodes` maps id → node.
- Decoration (forest belt, bushes, rocks, flowers) is all MultiMesh with visibility ranges of 60–130 m.
  The forest belt is split into 8 angular sectors so it can be culled.

### 3.5 Landmarks (`landmarks.gd`)

- Everything is hand-placed from the layout constants. Steps (L43): haven, glade, quarry, ruin, old_oak,
  pond, mine, spawners.
- One shared `StaticBody3D "LandmarkCollision"` (layer 1, "stone"). `_box_col(xf, size, surface)` creates a
  separate body for non-stone surfaces.
- Haven: the Ward Stone at `SL.WARD_STONE`, the campfire, the sign, and fences at r 19.2 with gaps at the
  path exits. The restoration lanterns stay hidden until the Ward is restored.
- Ruin (L321): columns at r 6.8 and two `_arch(parent, p, yaw, tint, broken)` calls: the south entrance at
  rc+(0,6.8) and a broken west arch at rc+(−6.9,−1).
- `_build_mine` places `mine_entrance.gd` at `MINE_MOUTH + f*0.4`, y = `terrain.mine_floor`.
- `_build_spawners` (L624) places `ruin_bramblings` (-10,-61.5) with `quest_flag_on_clear:"ruin_cleared"`,
  `thicket_bramblings` (-62,-46) and `quarry_bramblings` (77,3). If the enemy module is missing it sets
  `ruin_cleared` directly (anti-softlock).

### 3.6 Water, sky, ambience, grass

- `water.gd`: the water surfaces have no collider; the player walks on the terrain bed. The only colliders
  are the crossings (bridges and stepping stones), built from `Layout.STREAM_CROSSINGS`. One stream sound
  follows the camera.
- `sky.gd` (Node, child "Sky"):
  - Builds the `WorldEnvironment` (custom sky shader, radiance 32 in INCREMENTAL mode), a shadowed `Sun` and
    an unshadowed `Moon`.
  - `KEYS` holds 11 hourly keyframes of colours, energies, fog and exposure. `update_sky()` interpolates them
    every frame from `GameState.hour()` (or `hour_override`). `warmth` (0..1) adds the restored tint.
  - Outputs `daylight = clamp(sun_e/1.2)` and `is_night = sun_e < 0.2`. Sun shadow distance is
    `[55,85,120][quality]`.
- The clock runs in every area (`Game._process` → `GameState.advance_clock`).
- `grass.gd`: a camera-following MultiMesh snapped to an 8 m period, with a raw instance buffer and a
  `custom_aabb`. `QUALITY` sets the radius per quality level: 26, 32 or 38 m.
- `props.gd`: `instance(...)` and `multimesh(mesh, mat, xforms, name, vis_range, shadows)` use
  `VISIBILITY_RANGE_FADE_DISABLED`, because outline passes can't dither. `flora.gd` provides `build_fields(...)`.
- `campfire.gd` is the only shadowed omni light on the surface.

### 3.7 Mine entrance (`mine_entrance.gd`)

- The rubble is a `resource_node` (`node_id "mine_rubble"`, flag `mine_opened`). `_sync_state` (L37) keeps the
  flag and the depletion in agreement. Once cleared, the doorway body gets layer 16.
- Entering: the comfort screen on the first visit (flag `mine_comfort_seen`), then `entered_below`, then
  `Game.change_area("below","mine_entry")`.

### 3.8 Restoration and the structure mask

- `play_restoration()` (L380) is a scripted ~10 s bloom; `_apply_restored_state(on)` applies the same end
  state instantly.
- `_setup_structure_mask` (L126) creates an R8 image of 257² that hides grass and flowers under built
  structures. It is rebuilt deferred on `Events.structure_placed/removed`.

## 4. Common world scripts (`src/world/common/`)

- `resource_node.gd`: `KIND_DEFAULTS` (L50) lists the kinds. `_complete` (L360) calls
  `GameState.deplete(node_id, respawn)`. **`GameState.depleted` is one global dictionary**, so node ids must be
  unique across all areas.
- `world_item.gd`: `static spawn_from_state(area, uid)` (L48) and
  `static spawn(item, count, pos, persistent=true, parent=null)` (L73). The drop's area comes from
  `area.area_id`. `_settle_initial` uses `area.height_at` when present, otherwise a ray.
- `node_visuals.gd` has `build(visual_id, seed, opts)`, `tree_parts(species, variant)` and the `Merger`
  mesh combiner. `fx.gd` has `burst(parent, pos, kind, ...)`.

## 5. The Below (`src/world/below/`)

### 5.1 Construction (`below_world.gd` `_ready` L78)

1. `viewport.use_occlusion_culling = true`. It is restored in `_exit_tree`.
2. `_build_environment`: `BG_COLOR #07060b`, ambient colour, volumetric fog when q ≥ 1, SSR at q2.
   `_apply_darkness` scales ambient, fog and exposure with `HorrorData.INTENSITY[horror_intensity].darkness`.
3. `builder = Builder.new(self)` (rng seed 7331) and `SpiderDecor`.
4. `RoomsMine.build(b, self)`, `RoomsRuins.build(b, self, decor)`, `RoomsSilk.build(b, self, decor)`, then
   `builder.finish()` and `decor.build()`.
5. Spawns, zones, checkpoints, progression nodes, lore, resources, enemies, boss, anchors, then moments.

The fog and ambient mood (`MOODS`) changes per zone.

### 5.2 Layout data (`below_layout.gd`, pure)

- `ROOMS{id:{space, zone, x0, x1, z0, z1, y, h, open:{n|s|w|e: "all" | [[from, to, height],...]}, custom?,
  ylo?, yhi?}}`.
  - n/s openings run along x; w/e openings run along z. Coordinates are absolute.
  - `custom` rooms (stair, descent_*, arena, lift_recess) are built by hand, not through `shell()`.
  - `ylo`/`yhi` give sloped rooms their vertical detection range.
- `SPAWNS{id:{pos, yaw_deg}}` (7 ids), `CHECKPOINTS{id:{pos, spawn, zone}}` (4), `SAFE_RADIUS=4`.
- `RESOURCES[{id:"below_*", kind, pos}]`, `ANCHORS`, `CRITICAL_PATH`, `SPACES`.
- Static helpers: `spawn_xform(id)`, `room_at(pos)` and `zone_of_room`.
- The Below spans roughly x −11..119, z +9..−149, y 0..−13.

### 5.3 Builder API (`below_builder.gd`)

- `begin(id)` starts a room node. Collision goes into one StaticBody per room and surface type.
- Visuals (`vbox`, `vcyl`, `vblob`, …) are only collected. They share one white toon material tinted per
  instance.
- Composites: `solid()` (visual, collision and occluder), `floor_rect`, `ceiling_rect`,
  `wall_side(r, side, color)`, `shell(id, floor, wall, ceil, opts)`, `ramp`, `stairs` (visual steps over a
  ramp collider), `dress_room_rock`.
- `finish()` (L197) turns the collected visuals into one MultiMesh per mesh/material per room (visibility
  85 m) and adds box occluders for walls, floors and ceilings. Call it **once**, after every room.
- `shell()` (L341) and `dress_room_rock()` (L449) read `Layout.ROOMS` from **below_layout directly**. That
  constant is the only thing that ties the builder to the Below.
- `rng` is consumed sequentially: the build order determines the random dressing.

### 5.4 Rooms, lights, props

- The `rooms_mine/ruins/silk.gd` statics follow one pattern: `b.begin`, `b.shell`, `b.dress_room_rock`,
  `Props.*` clutter, then lights.
- `below_props.gd` `lamp(parent, pos, {style, energy, range, shadow, color, idle, hang, flame, yaw})` creates
  a `below_lamp.gd` (group `flicker_light`, distance fade 34+10 m, shadow fade 22 m). The file also has
  mine/ruin prop factories (`timber_frame`, `crate`, `pillar`, `glowcaps`, …).
- Checkpoint lanterns are also shadowed lights.
- All web and silk dressing must go through `spider_decor.gd`, which swaps it for pale roots when the
  arachnophobia setting is on.

### 5.5 Zones, checkpoints, respawn

- `_register_zones` adds one circle per room (for id registration). It then **overrides**:
  - `get_zone_at` → `room_at`, or `nearest_room`, then the zone.
  - `is_safe_zone` → `safe_areas`: XZ radius **and |dy| < 3**.
  - The landing's safe area is (0,0,0.5) r 6.5.
- `checkpoint_lantern.gd`: `setup({id, spawn, zone})`, flag `cp_lit_<id>`. A lit lantern adds a safe area of
  r 4. `interact` (L158) calls `Game.set_respawn("below", spawn_id)` (the area is hard-coded), then saves.

### 5.6 Progression nodes

- `rubble.gd`: `setup({size, flag, node_id, hits})`. Already reusable.
- `lower_gate.gd`: the flag `lower_gate_open` and key `foreman_key` are constants (L11-12). The key is not
  consumed.
- `below_lift.gd`: `setup({role, target, area})`. It only works once `weaver_defeated` is set, and
  `interact` calls `area.ride_lift(target_spawn)` (below_world L646: fade, teleport, companions follow).
- `below_interactable.gd`: a generic interactable, `setup({text, size, offset, handler, text_func,
  accent})`. The ClimbOut at (0,0,7.7) uses it to call `Game.change_area("surface","mine_exit")`.
- `below_moments.gd` tracks the player's room and calls `area.on_room_changed(old, new)`, which starts the
  boss fight.

### 5.7 Performance budgets and evidence

- Tests: `test_world_surface.test_build_time_budget` requires under 4000 ms (target under 1 s).
  `test_below_layout.test_build_is_fast_enough` requires under 2500 ms and more than 2000 batched instances.
- QA (`QA_REPORT.md` L115): about 2,100 draw calls on the surface by day, 290–1,580 in the dungeon.
- Shadowed lights: the sun and campfire on the surface; opt-in lamps in the Below. The target is at most 8
  visible.

## 6. Extension recipes

*Status: recipes (a)-(e) are built (Waves A-C); §8 at the end maps the current Chapter Two areas.*

### (a) New outdoor area `hallowmere_reach` (~280×220 m) with a two-way waygate

1. **Data:** create `data/reach_layout.gd`. It holds `LANDMARKS`, `SPAWN_HINTS`, `PATHS`, `HX=140`,
   `HZ=110`, `BOUNDARY`. **Zone ids must be new strings** (e.g. `reach_mere`), because bond XP is keyed per
   zone string.
2. **Terrain:** create `src/world/reach/reach_terrain.gd` by copying the `terrain.gd` structure.
   - Grid: `NX=321` (x ±160) and `NZ=257` (z ±128), 1 m spacing, `k=j*NX+i`.
   - Chunks: `CHUNK=32` gives 10×8 chunks. That is about 82k samples, 1.25× the surface.
   - Collision: `HeightMapShape3D.map_width=NX`, `map_depth=NZ`.
   - Hills: use the edge metric `max(|x|/HX, |z|/HZ)`.
   - Keep the same query names (`height_at` with the same triangle split, `surface_at`, `water_level_at`,
     `is_water`, `path_at`, `rock_at`, `stream_distance`, `pond_distance`, `clear_grass`, `*_image`). Then
     `Grass`, `Props`, `ResourceNode`, `terrain_body.gd` and `world_item` work unchanged.
   - Use new fixed noise and RNG seeds.
3. **Shaders:**
   - In `surface_terrain`, `surface_grass` and `surface_flower`, change `uniform float terrain_samples` to
     `uniform vec2 terrain_samples = vec2(257.0)`. The expression `/ terrain_samples` stays valid, and the
     surface is unchanged because nothing sets the uniform.
   - For the reach, set `terrain_origin=(-160,-128)` and `terrain_samples=(321,257)` on its materials. Set
     them on `grass.grass_material` after `add_child`.
4. **Area script:** create `src/world/reach/reach_world.gd`, extending `area_base.gd`.
   - Set `area_id="hallowmere_reach"` and mirror the order of `surface_world._ready`.
   - The vegetation plan should be a pure `plan()` with **prefixed ids** (`reach_tree_%d`, …) and its own
     exclusions. Reuse `ResourceNode`, `Props.multimesh`, `Flora.build_fields` and `NodeVisuals`.
   - Implement `height_at`, `surface_at`, `water_level_at`, `is_inside_bounds`, `validate_position`
     (bounds, then `super`) and `on_player_spawned` (ambience and music, using existing sound names only).
   - Build a rounded-rectangle boundary following the `_build_boundary` pattern.
5. **Sky tint:** in `sky.gd`, add `var tint := Color(1,1,1,0)` and blend the sky, ambient and fog colours by
   `tint.a` inside `update_sky()` after the warmth block. The default is a no-op. The reach sets the tint
   right after `SkyScript.new()`.
6. **Scene and registration:** create `scenes/hallowmere_reach.tscn` (copy `surface.tscn` and swap the
   script). The **integrator** adds it to `Game.AREAS`. Game edits needed:
   - `use_saved` should work for outdoor areas (L240).
   - `can_manual_save` and `_tick_autosave` should allow outdoor areas (L130/L511). Today the reach gets the
     "Underground" refusal.
   - Also needed: the companion logic's outdoor case (today Mochi would walk off to the mine threshold),
     `lantern_scale`, map panel data per area, and the pause unstuck spawn.
7. **Waygate (both sides):** create `src/world/reach/waygate.gd`.
   - A Node3D in group `interactable`, with a layer-16 StaticBody, `setup({target_area, target_spawn,
     unlock_flag?})`, and `interact` → `Game.change_area(target_area, target_spawn)`.
   - On the surface, add a `_build_annexes()` call in `surface_world._ready` right after `_build_boundary()`.
     It places the gate, does `register_spawn("woods_waygate", xf)` (**not** via `SPAWN_HINTS`), and
     `add_zone("woods_waygate", c, ≤5, true)`.
   - Suggested site: the outer ruin route north of the ruin, around (−12,−84). It is inside
     `BOUNDARY=104`, and its small zone overrides "ruin" locally.
   - Keep the safe radius clear of the ruin centre (−12,−66), which a test requires to be unsafe, and of the
     `ruin_bramblings` spawner (−10,−61.5); a safe spawner never spawns, so `ruin_cleared` would softlock.
   - Check that no `vegetation.plan_data` entry lies within the footprint + 2 m. If one does, move the gate
     or `queue_free` that node via `vegetation.resource_nodes[id]`. Never add exclusions to `plan()`.
   - In the reach, a mirror gate sends the player to `change_area("surface","woods_waygate")`. The surface
     respawn resets to bed/haven automatically.
8. **Tests:** add `tests/unit/test_world_reach.gd`, cloning `test_world_surface.gd`: height vs collision,
   spawns on the ground and clear, zones, boundary, determinism, build time.

### (b) Interior manor (5 rooms) and a new 14-room dungeon on the Below builder

1. **Make the builder layout-agnostic** (backward compatible):
   `var rooms: Dictionary = Layout.ROOMS`, `_init(p_root, seed_value := 7331, p_rooms := {})`, and
   `if not p_rooms.is_empty(): rooms = p_rooms`. Replace `Layout.ROOMS[id]` at L341 and L449.
2. **Layout:** create `src/world/<name>/<name>_layout.gd` in the same shape as `below_layout.gd`, and copy
   the static helpers (they bind to their own script's `ROOMS` const).
   - Keep openings at least 1.6 m wide and 2.4 m tall, and rooms at least 2.4 m high.
   - Keep every floor above `KILL_Y=-40` (use y ≥ −35) or the player and companions "fall".
3. **Area script:** create `<name>_world.gd`, modelled on `below_world.gd`.
   - Environment: `_build_environment`/`MOODS`.
   - Build with `Builder.new(self, seed, Layout.ROOMS)`, the room builders (`b.begin`/`shell`/
     `dress_room_rock`/`Props.lamp`), one `finish()`, then `decor.build()`.
   - Register spawns and zones (`add_zone` per room, then override `get_zone_at` with `room_at`), and
     `add_safe_area`.
   - Toggle occlusion on in `_ready` and off in `_exit_tree`, as `below_world` does at L82/L127.
4. **Reusable nodes and the parameters they need:**
   - `checkpoint_lantern.gd`: add a setup key `area` (default `"below"`) for L164. Ids must be globally
     unique (`cp_lit_<id>`).
   - `lower_gate.gd`: add setup keys `flag`, `key` and `locked_text` in place of the L11-12 constants.
   - `below_lift.gd`: add `requires_flag`. The area implements `ride_lift(spawn)`, copied from L646.
   - Ready as they are: `rubble.gd` and `below_interactable.gd`.
   - All resource ids need prefixes.
5. **Manor:**
   - Five `ROOMS`, all `zone:"manor_*"`, and `is_safe_zone` returns true.
   - Warm `WorldEnvironment` with no volumetric fog, and at most 3 shadowed `below_lamp`s.
   - Door: a surface or reach annex interactable plus a registered spawn, going through
     `change_area("manor","manor_hall")` and back.
   - Saving there needs Game support (the integrator).
6. **Dungeon:** Game only creates the director for `"below"` (L259), and `_below_return_point` and unstuck are
   below-only. Either generalise these to a `DUNGEON_AREAS` set (integrator change) or have no horror. New
   anchor zones need `data/horror_events.gd` support.
7. **Tests:** clone `test_below_layout.gd` / `test_below_path.gd` (spawn headroom, openings, no-escape rays,
   build under 2500 ms).

### (c) Annexes to existing areas without changing legacy ids or positions

- **Surface, never edit:**
  - `SPAWN_HINTS` (these are exclusion circles, so editing renumbers `tree_*` and `stick_*`)
  - `LANDMARKS` pos/radius
  - `STREAM_*`
  - `SL.PATHS`, `DIRT_PATCHES`, `PATH_WIDTHS`
  - noise and RNG seeds, and the loop order in `plan()`
  - the landmark step order
- **Surface, do instead:** add an `_build_annexes()` step after `_build_boundary()`.
  - Explicit nodes, with their own StaticBody.
  - `register_spawn`, and `add_zone` with a small radius that never contains a `LANDMARKS` centre (the tests
    assert `get_zone_at(landmark) == id`).
  - Annex resource ids with a prefix (`annex_*`).
  - Grass: call `terrain.clear_grass` before Grass is added (before L95), or re-upload
    `structure_mask_tex`.
  - Keep out of radius ≤ 18 of the Haven (`BUILD_AREA` r16 + footprints): existing saves may have
    structures there.
  - Add a golden test that hashes `Vegetation.plan(t)` id→pos.
  - Heightfield edits must happen before `build_meshes` and must not change `rock_at` or `path_at` near
    planned candidates.
- **Below:**
  - Add new room builders **after** `RoomsSilk.build` (L91), so the builder rng keeps the legacy rooms
    identical.
  - New rooms go in new XZ boxes, or at a distinct y (detection uses the y range).
  - Use new checkpoint, resource and flag ids.
  - Update `test_below_layout` (checkpoints `== 4`, `REQUIRED_SPAWNS`, anchors ≥ 3 per `SPACES` entry) and
    the `test_below_path` room list.

### (d) Fast travel between safe arches

1. Create `data/arches.gd`: `ARCHES{id:{area, spawn:"arch_<id>", name, pos:Vector3, flag:"arch_found_<id>"}}`.
2. Create `src/world/common/safe_arch.gd`: group `interactable`, a layer-16 body and `setup({id})`.
   - The first use sets the flag and emits a notify.
   - Later uses gate on `Game.mode == "playing"`, no threatening enemy within 20 m (same test as `game.gd`
     L514) and `area.fight_active != true`.
   - They then run `var c: String = await Game.ui.confirm(title, text, [[id, name, "AccentButton"], ...,
     ["cancel", "Stay", ""]])` (`ui_root.gd` L270).
3. **Same area:** `Game.set_cutscene(true)`, `await Game.ui.fade_out(0.35)`,
   `Game.player.teleport(Game.area.get_spawn(spawn))`, then `teleport_near` on the companions (it only moves
   followers), fade in, and `set_cutscene(false)`. Don't reuse `ui_root.teleport_player` (L415): it shows the
   unstuck toast.
4. **Other area:** `Game.change_area(area, spawn)` (autosaves and applies the respawn rules).
5. Each area's annex step builds its arches from `ARCHES` (filtered by area), plus a `register_spawn` in
   front of each and `add_zone("arch_<id>", pos, 4, true)`. Don't place any in the Below before
   `weaver_defeated`.

### (e) Ward Stone inscriptions and choices (`src/world/surface/ward_stone.gd`)

- Prompt: `get_interaction` (L232). It returns `{}` while `_busy`, "Return the Heartseed" when not restored
  and holding the seed, and "Read the Ward Stone" otherwise.
- The priority chain is in `interact` (L240):
  1. `ward_restored` → "Light kept. Home kept. Thank you, %s."
  2. heartseed → `await Game.complete_chapter()`
  3. intro → `read_ward_intro`
  4. Lumi befriended or `prepare` → `read_ward_warning` (arachnophobia wording)
  5. repeat lines
- Output helpers: `_say(lines)` (`Events.say(SPEAKER, line, LINE_SECONDS=5.5)`, lines chained by a tween),
  `_pulse_once()`, `play_glow_burst()`, `set_restored(t)`.
- **To add an inscription**, insert a branch gated by a new Chapter Two flag (e.g. `ch2_started`) inside the
  `ward_restored` block, *before* the existing thank-you line.
  - Set a `read_*` flag and give lines with `alt` wording for arachnophobia.
  - For a choice: `_busy = true`, then `var c: String = await Game.ui.confirm("Ward Stone", text,
    [["a","…","AccentButton"],["b","…",""]])` (guard `Game.ui == null` in tests → default), branch,
    `_busy = false`.
  - Update `get_interaction` text for the new state.
  - Optional: a data file `data/ward_inscriptions.gd` (`[{requires_flag, sets_flag, lines, alt_lines}]`)
    iterated there.

## 7. Risks (saves and tests)

- **Vegetation determinism.** Anything that changes plan acceptance (terrain heights/normals near candidates,
  paths, `SPAWN_HINTS`, crossings, exclusions, seeds, loop order) renumbers `tree_/rock_/stick_…`. Saved
  `depleted` then marks the wrong trees as felled, and `test_placement_is_deterministic_and_complete` still
  passes, so the bug is silent.
- **Terrain height changes** move ground under saved positions (these fall back to the spawn via
  `validate_position`), under structures (absolute `pos` in the save: floating or buried) and under dropped
  items.
- **Persisted ids:**
  - Spawn ids: `player.spawn`, `respawn_spawn`, `below_respawn`.
  - Area ids: `player.area`, `dropped[].area`, `structures[].area`, companion `wait_area`.
  - Flags: `mine_opened`, `gallery_cleared`, `lower_gate_open`, `foreman_key_taken`, `cp_lit_*`,
    `weaver_defeated`, `ward_restored`, `read_ward_*`, `moment_*`, `mine_comfort_seen`, `entered_below`.
  - Node ids: `mine_rubble`, `below_*`.
  - Zone ids in companion `zones`.
  - Renaming any of these breaks old saves: they fall back to the surface or `haven_respawn`, or progression
    re-locks.
- **Tests with hard-coded expectations:**
  - `test_world_surface`: the spawn loop over `SPAWN_HINTS` (ground, clear capsule, `is_inside_bounds(p,3)`,
    dry), zone-per-landmark, the ruin not safe, the 4 s build budget.
  - `test_below_layout`: 4 checkpoints, 7 required spawns, ≥ 15 flicker lights, openings, anchors per space,
    the 2.5 s budget.
  - `test_below_path`: the no-escape room list.
  - `test_world_nodes.test_ward_stone_inscriptions`: exactly one restored line.
  - `test_audit_progression_order`: "Return the Heartseed" is available on any step.
  - `test_audit_persistence_*`: surface and below continue flows.
- **Shared foundations:** `autoload/game.gd`, `data/world_layout.gd` and `area_base.gd` are read-only for
  module owners. The AREAS, save, director and respawn changes go through the integrator.
- **Occlusion flag:** new dungeon areas must restore `use_occlusion_culling` on exit. Otherwise the surface
  inherits it (harmless, but it costs CPU).
- **Shader uniform type change** (float → vec2): any script that later calls
  `set_shader_parameter("terrain_samples", 257.0)` with a float would silently fail. Always pass a Vector2.
- **Load time:** area generation runs inside one frame behind the fade (rule: at most about 1 s). A larger
  terrain scales linearly with sample count. Keep an eye on `build_times` (`print`ed in debug builds).

## 8. Chapter Two areas (Waves A-C + integration) — as built

Sections 1-7 map the Chapter One areas; recipes 6(a)-(e) are built. Areas, spawn ids, travel and zone ids: spec §1 / §7 (they are
the contract); Game flow constants (`AREAS`, `SAFE_SAVE_AREAS`, `OUTDOOR_AREAS`, `TRANSIENT_AREAS`, `DIRECTOR_AREAS`,
`AREA_DEFAULT_RESPAWN`, `return_point`, `set_respawn`, Lantern Road): `docs/ch2/WAVE_A_REPORT.md`. Source of truth: the headers of
the area scripts below and of `autoload/game.gd`.

**Area scripts** (every scene keeps its Wave A spawn ids, zone ids and exit targets):
| area | script | built from |
|---|---|---|
| `hallowmere_reach` | `src/world/areas_ch2/hallowmere_reach_world.gd` → `src/world/reach/reach_world.gd` (C1) | `data/hallowmere_layout.gd`; base region (terrain, brook, forest edge, roads, Commons, Conservatory, Bellhouse, arches) + districts through `reach_districts.gd` (`footprints()` → `shape_terrain()` strictly inside the district's landmark circle → `build(area)`); district scripts `src/world/reach/districts/{orchard,pools,candleyard}.gd` (C2, `west/*`, `data/reach_west.gd`), `quarry.gd` (C3, `east/*`, `data/reach_east.gd`), `manor_grounds.gd` (C4); story festival dressing (C9 `reach_dressing.gd`) is built during the load |
| `moonveil_manor` | `moonveil_manor_world.gd` (C4) | its own room builder `src/world/manor/manor_builder.gd` + `data/manor_layout.gd` (not below_builder) |
| `hushed_works` | `hushed_works_world.gd` (C7) | `data/works_layout.gd` (rooms 1-8) merged with `data/works_layout_deep.gd` (rooms 9-14) into one table for `below_builder.gd`, then `src/world/works/rooms_deep.gd` `build(area, builder)` (C8); Works horror director (`Game.DIRECTOR_AREAS` has "hushed_works") |
| `tobin_annex` | `tobin_annex_world.gd` (B10; the scene's script, not `tobin_annex.gd`) | `src/world/annex/*` on the Below builder |
| `echo_trial` | `echo_trial.gd` (B9) behind the 3-line `echo_trial_world.gd` shim that `scenes/echo_trial.tscn` loads | kept: no .tscn churn (R136 j); trial table `TRIALS` in `echo_trial.gd` holds the repeat rewards (trial-owned content data, R136 k) |
Surface additions are annexes (`src/world/surface/annexes.gd` `ANNEX_SCRIPTS`, safe-loaded, `static build(area)` + optional
`grass_clearings()`): the c1x content (B7), `courage_lantern.gd` (B4), `tobin_door.gd` (B10) and C9's `story_ch2/haven_dressing.gd`
(the lasting Haven keepsake after `chapter_two_complete`; R50). The legacy vegetation golden hash stays green.

**Cold-load warm-up (integration R05/R58/R110).** `Game.prefetch_area(area_id, extra := []) -> int` starts compiling an area on
loader threads — its scene (with every script the scene preloads), the `AREA_WARMUP` scripts it builds or spawns early (surface:
brambleback / knotted_elder / lantern_moth; tobin_annex: hollow_drudge; hushed_works: rooms_deep + hollow_drudge + bellcap_sentry;
moonveil_manor: velvet_wing) and any `extra` paths. Idempotent, never blocks; `EnemyFactory` is loaded on the MAIN thread first (no
worker may compile a script that preloads it: the quarry's deadlock-avoidance rule). `load_area()` calls it before its fade-out and
takes the scene with `load_threaded_get()` (plain `change_scene_to_file()` fallback); `goto_title()` prefetches the Woods;
`is_prefetching(path)` for tests. Early callers (behind `has_method` guards, once per node): the repaired waygate within ~25 m
(`prefetch_area("hallowmere_reach")`), the open Bellhouse stair within ~20 m (`prefetch_area("hushed_works")`). The Reach districts warm
themselves: `reach_districts.warm_up()` / `load_all()` request every district script with `ResourceLoader.load_threaded_request`
and collect them in order (plain `load()` fallback).

**Loading details (integration).** `Game.load_area` restores a position saved on an upper storey after the structures exist
(`UPPER_STOREY_RESTORE` 1 m, R04). `Game.wire_session_systems()` (from `_ready`, idempotent; the test runner calls it between suites)
starts the mastery listeners and the Chapter Two activity tracker node (R02/R03). `surface_world.get_zone_at()` reports "haven" in the
whole expanded Haven (build regions + `HAVEN_SAFE_BUFFER`), any legacy zone that claims the point still wins (R51).
Reusable Below nodes gained setup keys (spec §10); `lower_gate.gd` records `lower_gate_tried` only for the legacy gate, every other gate
`<its flag>_tried` (R74); `BelowProps.tint()` / `torus_mesh()` are public for the annex (R75); the Foreman's desk offers a lost key again
while the Bellhouse service gate still needs it (`ch2_lamps_linked` and not `ch2_service_gate_open`; never duplicates it, R73).

**Kept as built (lead decisions R136, no change):** Celebrate at home before revisiting the Reach is allowed (step 18 skipped,
`ch2_trials_open` still paid) (n); Hask's Rail completes on reaching the junction and the Works repairs `ch2_service_gate_open` on
arrival (no softlock possible) (p); after the Choir the Works respawn is `vault_exit` and the porch fragment still asks for "haven" (q);
entering a trial may set the Below respawn to `cp_arena` even if unlit (the echo stone stands at that lantern) (l); minor keeps (s):
the annex echo plays on the stair, the lantern niche is safe unlit, the no-enemy fallbacks (annex Drudge, quarry Warden) stay as
completability guards, the moth pocket sits just outside the pond music zone, Bramblewatch circles overlap the thicket rim, manor
`height_at` in doorways, the brook corridor is held by the invisible wall, chime-trail progress is per session. After the Choir the
vault ambience calms to `amb_stream` (R120); the quarry gangway collider switches on when the lowering animation ends (R112).
