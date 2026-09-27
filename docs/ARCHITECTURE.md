# Hollowhaven architecture contract

Godot 4.7.2, GDScript, Forward+ renderer, Jolt physics. Project root: `game/`.
Read `GAME_SPEC.md` for design. This file defines how code fits together. **Follow it exactly** —
several people build modules in parallel and integration depends on these contracts.

## Golden rules
1. **Scripts build their own children in code.** Entities are plain scripts; create with
   `load("res://...gd").new()` or `preload(...).new()`, then `add_child`. No hand-written `.tscn`
   except the few in `scenes/`. Optional `setup(params: Dictionary)` before `add_child`.
2. **No `class_name`.** Reference other scripts with `const X := preload("res://path.gd")` (or `load()`
   at runtime to avoid cyclic preloads). Autoload singletons are global: `Events`, `Settings`, `ItemDB`,
   `GameState`, `SaveSystem`, `Audio`, `Game`, `Debug`.
3. **Typed GDScript, tabs for indentation.** Avoid `:=` when the right side is Variant (Array/Dictionary
   element access, `floor()`, `min()`, `max()`, `clamp()`, ternaries mixing types) — declare the type
   explicitly (`var x: float = ...`) or use `floorf/minf/maxf/clampf/mini/maxi/clampi`. Warnings-as-errors
   are not enabled, but parse errors break everything.
4. **Data-driven:** items `data/items.gd`, recipes `data/recipes.gd`, structures & crops
   `data/structures.gd`, creatures & lines `data/creatures.gd`, enemies `data/enemies.gd`, quests
   `data/quests.gd`, horror events `data/horror_events.gd`, layout `data/world_layout.gd`.
   Look up through `ItemDB`. Never hardcode an item's stats elsewhere.
5. **State lives in `GameState`** (serialisable). Nodes are views/behaviour over that state. Anything
   that must survive save/load goes through `GameState` methods (flags, counters, structures, depleted
   nodes, dropped items, companions, quests, lore, clock).
6. **Talk through `Events`** (autoload/events.gd) for cross-module notifications. Do not add signals to
   Events yourself — if you truly need one, define a local signal and mention it in your report.
7. **Shared foundation files are read-only for module owners**: everything in `autoload/`, `data/`,
   `src/core/`, `src/art/`, `shaders/toon.gdshader`, `shaders/outline.gdshader`, `src/world/area_base.gd`,
   `tests/test_case.gd`, `tests/runner.gd`, `tests/preview/`, `project.godot`. If you find a bug or need a
   change there, describe the exact change in your final report (the integrator applies it). You MAY
   add new files in your own directories and new data files named after your module.
8. **Art cohesion:** use `src/art/palette.gd` colours, `src/art/mat.gd` materials (toon + outlines on
   characters/creatures/key props) and `src/art/mesh_kit.gd` primitives/blobs. Soft, rounded, chunky,
   readable silhouettes. No external assets, no image files (generate textures in code if needed).
   Only the Audio module adds files under `assets/` (audio). Fonts: `assets/fonts/Fredoka-Variable.ttf`
   (headings, rounded) and `assets/fonts/Nunito-Variable.ttf` (body) — both OFL.
9. **Arachnophobia**: anything spider-like must check `Settings.get_value("arachnophobia")` and use the
   alternative (non-arachnid "Hollow Mother/Shade" visuals, pale roots instead of webs, alt sounds and names
   via `ItemDB.display_name` / `ItemDB.enemy_display_name`). Listen to `Events.settings_changed` if the
   visual can be on screen while the setting changes (or rebuild on area load — acceptable).
10. **Comfort**: camera shake / flashes go through `Events.camera_shake` / `Events.screen_flash`; the
    camera/UI consumer scales them by `reduce_shake` / `reduce_flashing`. Never hard-flash the screen.
11. **Physics layers** (bit values): world=1, player=2, companion=4, enemy=8, interact=16, structure=32,
    pickup=64, trigger=128, hitbox=256. Player collides with world|structure (1|32). Enemies/companions
    collide with world|structure. Interaction ray/shape queries use layer 16 (interact) — every
    interactable/harvestable owns an `Area3D` or `StaticBody3D` on layer 16 whose parent chain contains
    the script implementing the interaction methods (see below).
12. **Groups**: "player", "companion", "enemy", "interactable", "harvestable", "light_source",
    "crafting_station", "director_anchor", "stalker", "flicker_light", "checkpoint".
13. **Performance**: target 60 FPS at 1080p on high settings. Share meshes/materials (Mat/Kit caches),
    use MultiMeshInstance3D for grass/flowers/pebbles, keep dynamic shadowed lights few (≤ 8 visible),
    no per-frame allocations in hot loops, no `get_nodes_in_group` every frame (cache or throttle).
14. **Never** block the main thread for more than ~1 s total during area load; heavy generation must be
    reasonably fast (area load is hidden behind a fade).
15. **Debug-only features** must check `Debug.is_cheat_allowed()`.

## Game flow (autoload/game.gd — read it)
`scenes/boot.tscn` → `Game.boot()` → title (`scenes/title.tscn`, script `src/ui/title_screen.gd`).
Title calls `Game.new_game()` (after the comfort screen) or `Game.continue_game()`.
`Game.load_area(area_id, spawn_id, use_saved_position)` changes scene to `scenes/surface.tscn` /
`scenes/below.tscn`, then: creates UI root once (`src/ui/ui_root.gd`, child of Game), creates the player
(`src/player/player.gd`) under the area root, calls `player.read_from_state()` and
`player.teleport(area.get_spawn(spawn_id))`, spawns companions via
`src/companions/companion_spawner.gd: static spawn_for_area(area, area_id, player) -> Dictionary`,
respawns persistent dropped items via `src/world/common/world_item.gd: static spawn_from_state(area, uid)`,
calls `area.on_player_spawned(player)`, emits `Events.area_loaded`.
Other key calls: `Game.change_area(area, spawn)` (autosaves), `Game.set_respawn(area, spawn)`,
`Game.on_player_died()`, `Game.open_panel(name, args)`, `Game.push_ui(name)/pop_ui(name)`,
`Game.gameplay_input_allowed()`, `Game.set_paused(bool)`, `Game.set_cutscene(bool)`,
`Game.complete_chapter()`, `Game.can_manual_save()`. `Game.player`, `Game.area`, `Game.area_id`,
`Game.companion_nodes` (id → node), `Game.ui`, `Game.mode`.

## Module contracts

### Area roots (`src/world/area_base.gd`)
Area scripts `extends "res://src/world/area_base.gd"`; build content in `_ready()`; call
`register_spawn(id, Transform3D)` for every spawn id; `add_zone(id, center, radius, safe)`.
Optional overrides: `get_zone_at(pos)`, `is_safe_zone(pos)`, `validate_position(pos)`,
`on_player_spawned(player)`. Surface also implements `play_restoration()` (awaitable, ~8–12 s,
the ending bloom) and applies the restored look on load when `GameState.get_flag("ward_restored")`.
Surface must also provide `height_at(x: float, z: float) -> float` for other systems.
Area roots should have a WorldEnvironment + lights appropriate to the area.

### Player (`src/player/`) — node: `CharacterBody3D` in group "player"
Required API: `teleport(xform: Transform3D)`, `read_from_state()` (hp/stamina/lantern from
GameState.player), `write_to_state()` (pos only if grounded & safe, yaw, hp, stamina, lantern_on),
`set_input_enabled(on)`, `get_camera() -> Camera3D`, `health` (child Node from `src/combat/health.gd`),
`stamina: float`, `lantern_on: bool`, `set_lantern(on)`, `is_sprinting()`, `is_dodging()`,
`is_moving()`, `get_prompt() -> Dictionary` ({"text": "Pick up Wood", "action": "interact"} or {}),
`get_focus_target() -> Node` (current interactable), `get_facing() -> Vector3`,
`play_emote(name: String)` ("wave", "cheer", "flinch", "sleep"), `build_mode_active: bool`,
`knockback(dir: Vector3, force: float)`. Keeps `GameState.player["hp"]` in sync.
Gameplay input only when `Game.gameplay_input_allowed()` and input enabled. Input actions are defined
in Settings (move_forward, move_back, move_left, move_right, jump, sprint, dodge, attack, use_item,
interact, lantern, companion_command, hotbar_1..8, zoom_in, zoom_out). UI actions (inventory, craft,
build, journal, map, pause, help) are handled by the UI root / build mode, NOT the player.

### Interaction contract (duck typed; used by the player probe)
An interactable node (in group "interactable", reachable from a layer-16 collider via parent chain):
`get_interaction(player) -> Dictionary` → `{"text": "Open chest", "enabled": true}` (enabled=false
shows the text greyed with the reason), and `interact(player) -> void`.
A harvestable (group "harvestable"): `get_harvest_info() -> Dictionary` →
`{"tool": "axe"|"pickaxe"|"hand", "name": "Oak Tree"}` and `harvest_hit(player, tool_item_id: String) -> void`.
When the player presses **attack** facing a harvestable within ~2.4 m whose tool it owns, it swings that
tool and calls `harvest_hit`. When it lacks the tool, show a hint ("You need an axe"). Hand harvestables
(sticks, stones, grass, berry bushes) are also interactables (E). Harvestables grant items via
`GameState.give_item(id, n, drop_pos)`, emit `Events.harvested(...)`, and persist depletion with
`GameState.deplete(node_id, respawn_minutes)` using a STABLE `node_id` (e.g. "tree_12"). On load they
check `GameState.is_depleted(node_id)`.

### Combat (`src/combat/`)
`health.gd` (Node): `max_hp`, `hp`, `dead`, `invulnerable`, signals `damaged(amount, source, dir)`,
`healed(amount)`, `died`, `changed(hp, max_hp)`; `apply_damage(amount, source=null, dir=Vector3.ZERO) -> float`,
`heal(amount)`, `reset()`. `combat.gd` (static): `melee(attacker: Node3D, origin: Vector3, forward: Vector3,
reach: float, arc_deg: float, damage: float, target_groups: Array, knockback: float) -> Array`
(hits nodes that own a `health` property/child), `find_health(node) -> Node`, `light_at(pos) -> float`
(0..1 from nodes in group "light_source": each exposes `light_radius: float` and `is_light_active() -> bool`).
Hit feedback helpers: `hit_fx.gd` (flash, particles, numbers optional). Player melee target groups:
["enemy"]; enemies target ["player"] (companions are never damaged permanently — see companions).

### Enemies (`src/enemies/`)
`enemy_factory.gd` static `spawn(enemy_id: String, parent: Node, xform: Transform3D, params := {}) -> Node`.
Enemy nodes: `CharacterBody3D`, group "enemy", `health`, `is_threatening() -> bool`, signal `defeated`.
Drops via `GameState.give_item` at the enemy position (pickups spawn by overflow rules) or as world items.
On death: `Events.enemy_killed.emit(id, pos)`, `GameState.stats["enemies_defeated"] += 1`.
`enemy_spawner.gd` (Node3D): `setup({"enemy": id, "count": n, "radius": r, "respawn_minutes": m,
"spawner_id": "ruin_bramblings", "quest_flag_on_clear": "ruin_cleared"})` — spawns when the player is
within ~45 m, despawns when far, sets the flag when all its enemies are defeated once.
Stalker (`stalker.gd`, group "stalker"): `setup({"route": PackedVector3Array/Array of Vector3 ceiling
points, "ambush_points": [...], "zone": "silk"})`, `pass_overhead()` (director hook), obeys light.
Boss (`weaver_boss.gd`): `setup({"arena_center": Vector3, "anchors": [Vector3...], "braziers": [Node...]})`,
emits `Events.boss_health_changed`, on defeat: `Events.boss_defeated.emit("weaver_matron")`,
spawns the Heartseed pickup (or calls `GameState.give_item("heartseed", 1)`), sets flag
"weaver_defeated". Brazier node (`boss_brazier.gd`): interactable ("Light the brazier" – needs lantern,
hold 1.5 s), signal `lit`, `is_lit()`, in group "light_source" once lit.

### Companions (`src/companions/`)
`companion_spawner.gd` static `spawn_for_area(area, area_id, player) -> Dictionary(id → node)`.
Uses spawn ids `companion_wild_<id>`, `companion_home_<id>`, `mine_threshold` from the surface area;
in "below" only the follower (if `enters_below`) spawns next to the player; Mochi refuses (see spec).
Companion node: `CharacterBody3D`, group "companion", layer 4, mask 1|32, never pushes the player
(does not collide with the player layer). API: `companion_id`, `command(cmd: String)` with cmd in
"pet", "follow", "wait", "home", "feed"; `get_interaction/interact` (wild → befriend attempt;
befriended → `Game.open_panel("companion", {"id": id})`), `react(reaction)` ("happy", "scared",
"notice", "celebrate", "dizzy"), `notice_threat(pos: Vector3)` (Lumi looks, dims, warns; others hide),
`on_player_respawned()`, `teleport_near(pos)`. Stuck recovery: if >20 m away or no progress 4 s →
teleport safely behind the player (never into geometry, never in view if avoidable).

### Building / crafting / farming (`src/building/`, `src/crafting/`, `src/farming/`)
`crafting.gd` static: `stations_near(pos: Vector3) -> Array` (always includes "hand"; group
"crafting_station" nodes expose `station_id: String` and are within 4 m),
`known_recipes() -> Array`, `check(recipe_id, stations) -> Dictionary`
(`{"ok", "reason", "missing": {item: n}}`), `craft(recipe_id, stations) -> bool` (transactional against
`GameState.inventory`; emits `Events.crafted`; increments stats).
`build_mode.gd` (Node added by the surface area or Game; listens for "build" action): ghost preview,
grid snap, validation (inside BUILD_AREA, not in blocked circles, no overlap in the same layer, not
overlapping the player/companions, slope ok), place (consumes item, `GameState.add_structure`,
spawns node), rotate (R), dismantle (X on a looked-at structure: refund via give_item; chests only when
empty or contents fit), emits `Events.build_mode_changed / build_selection_changed /
build_placement_state`. Exposes `static spawn_structure(area, uid) -> Node3D` used when loading.
**Entry point:** `src/building/building_system.gd` with `static func attach(area: Node) -> void` — Game
calls it right after the surface area loads (before companions spawn). `attach` spawns every saved
structure of that area (GameState.structures) and adds the BuildMode node (group "build_mode", method
`begin(item_id)` used by the player when a placeable hotbar item is used). The surface area itself does
NOT need to call anything.
Structure nodes implement the interaction contract (chest → `Game.open_panel("storage", {"uid": uid})`,
bed → sleep: fade, `GameState.skip_to_morning()`, heal, `area.register_spawn("bed", xform)` +
`Game.set_respawn("surface", "bed")`, save; workbench → `Game.open_panel("crafting", {"station": "workbench"})`;
crop plot → plant/harvest). Crop growth = in-game minutes; tended by Mochi when home
(`GameState.crops[uid]["tended_minutes"]`), after "ward_restored" growth ×1.5.

### UI (`src/ui/`)
`ui_root.gd` (CanvasLayer, layer 50, process ALWAYS): owns HUD + panels + overlays. API used by Game &
others: `fade_out(t)` / `fade_in(t)` (awaitable), `open(panel, args)`, `close(panel)`, `is_open(panel)`,
`show_death()` (awaitable ~2.5 s), `show_ending()` (awaitable, chapter complete + credits, skippable),
`show_chapter_card(title, subtitle)`, `show_comfort(first_time: bool)` (awaitable).
Panels: inventory (+ hotbar drag/drop, tooltips, sort), crafting (station filter), storage (chest ↔ bag),
journal (objectives, lore, companions & bonds), map (landmarks from world_layout, player marker,
objective target), companion (menu for a befriended companion), pause (resume, save, settings,
controls, return home/last lantern [unstuck], quit to title, quit game), settings (gameplay, controls
rebinding, video, audio, comfort), controls (F1 overlay). HUD: health & stamina, hotbar, objective
tracker, interaction prompt (from `Game.player.get_prompt()` with the key label), toasts (`Events.notify`),
dialog/speech line (`Events.say`), captions (`Events.caption`, respects Settings), hints (`Events.hint`,
once per id; replaces `{interact}`-style tokens with `Settings.action_label`), boss bar
(`Events.boss_health_changed`), build bar (build-mode events), day/time indicator, companion portrait,
FPS (if enabled). Theme: `theme_factory.gd` (parchment panels, Fredoka headings, Nunito body).
Icons: `icon_factory.gd` renders item icons procedurally (2D storybook sticker style) from the item's
`icon` id and `color`; cached ImageTextures. Title screen `title_screen.gd`: 3D diorama backdrop,
"Hollowhaven" logo text, "For Krystal" dedication, Continue / New Game (overwrite warning) / Settings /
Credits / Quit; New Game → comfort screen → `Game.new_game()`.
Mouse: panels call `Game.push_ui(name)` when opened and `Game.pop_ui(name)` when closed; full-screen
menus (inventory/crafting/storage/journal/map/pause/settings) also `Game.set_paused(true/false)`.

### Horror (`src/horror/`)
`director.gd` (Node; **Game creates it** for the "below" area: `setup({"area": area, "seed": int})`
is called before `add_child` under the area root; `Game.director` references it. The Below area only
places anchors and emits authored events): `setup(...)`, `suppress(seconds)`,
`get_state()`, `debug_log: Array[String]`, pure-logic core testable without a scene (see
`data/horror_events.gd`). Uses anchors: `Marker3D` nodes in group "director_anchor" with metadata
`zone` (mine/ruins/silk), `kind` (sound/doorway/ceiling/floor/spawn), optional `room`.
Executes events through `event_runner.gd` (sounds via Audio.play_3d, captions via Events.caption,
glimpse silhouettes via `silhouette.gd`, flicker via group "flicker_light" nodes' `flicker(seconds)`,
Lumi notice via companion `notice_threat`, spawns via EnemyFactory, stalker passes via group "stalker").
Listens to `Events.horror_event` ("authored:<id>" → recovery), `Events.player_died`,
`Events.safe_zone_changed`, `Events.paused_changed`, `Events.area_exiting` (cancel).

### Audio (`tools/audio/`, `assets/audio/`, `autoload/audio.gd`)
Generated originals. Sound NAMES (consumers call these; variants `_1.._n` allowed):
UI: ui_click, ui_hover, ui_open, ui_close, ui_error, ui_craft, ui_quest, ui_notify, ui_befriend, ui_bond, ui_save.
Player: step_grass, step_stone, step_wood, step_water, jump, land, dodge, swing, hurt, eat, lantern_on, lantern_off, death.
Gathering: chop, tree_fall, mine_hit, rock_break, pickup, grass_pull, berry_pick, splash.
Building/farming: build_place, build_remove, build_invalid, dig, harvest_crop, chest_open, chest_close, sleep.
Combat: hit_soft, hit_hard, enemy_hurt, enemy_defeat, brambling_chatter, brambling_telegraph,
gloomling_hiss, gloomling_telegraph, gloomling_alert, gloomling_flinch, weaver_rattle, weaver_skitter,
weaver_shriek, weaver_drop, shade_whisper, shade_telegraph, shade_drift, shade_shriek, brazier_light, heartseed_pulse.
Companions: mochi_chirp, mochi_happy, mochi_scared, pebble_clack, pebble_happy, pebble_grunt,
lumi_chime, lumi_happy, lumi_warn, fake_lumi_chime.
World: ward_hum, ward_restore, door_creak, gate_unlock, lift_move, checkpoint_light, water_drip, mine_cart.
Director: dir_distant_pickaxe, dir_creak, dir_footsteps, dir_pebbles, dir_whisper, dir_wrong_squeak,
dir_flicker, dir_scratch, dir_scratch_soft, dir_web_rustle, dir_root_creak, stinger_soft, stinger_major.
Ambience loops: amb_forest_day, amb_forest_night, amb_stream, amb_mine, amb_ruins, amb_silk, amb_boss.
Music: music_title, music_haven, music_night, music_boss, music_ending.

## Testing
Unit tests: `game/tests/unit/test_<module>_*.gd` extending `res://tests/test_case.gd`.
Run: `tools/test.sh <filter>` (headless). Tests must not write outside `user://test_saves/`.
Visual preview: `tools/godot.sh --path game --windowed --resolution 1280x720 -- --preview=res://src/.../x.gd --shot-dir=<abs dir> [options]`
(see tests/preview/preview_stage.gd). Area screenshots (debug build):
`tools/godot.sh --path game --windowed --resolution 1600x900 -- --area=surface --cams="x,y,z,yawdeg,pitchdeg;..." --shot-dir=<abs dir> [--hour=18]`.
Then look at the PNGs (Read tool) and iterate on what you actually see.
Parse/compile check (headless): `tools/parse_check.sh res://src/<your_module>` (or no arg = everything).
Stable debug test arena (flat ground, slopes, stairs with ramp collision, doorway, corner, ledge,
companion spawn ids): `tools/godot.sh --path game --windowed --resolution 1600x900 -- --area=arena`
(file tests/preview/arena.gd). Use it when the real areas are still being built by someone else.
Game falls back to tests/preview/fallback_player.gd / fallback_ui.gd if the real player/UI scripts fail
to load, and skips missing modules (building system, director, companion spawner) - so a broken module
never blocks everyone else. That also means: check the Godot output for "script failed to load".
Do NOT run `--import` (only the integrator / audio module do) and do not start the editor GUI.
Always use `timeout` and `--max-seconds` / `--quit-at` so no process is left running.

## Conventions added during integration (all additive)
* **Prompts**: `player.get_prompt()` returns `{text, action, enabled, reason?}`. Axe/pickaxe harvestables always
  prompt the `attack` action ("Chop Oak Tree"); pressing E on them also swings the owned tool. Hand gathering
  calls `harvest_hit(player, "")`. Interactables may implement `set_focused(on: bool)` (probe calls it).
* **Player**: `stamina` is writable (bed refill), `play_emote("stop")` ends looping emotes, `eat(id) -> bool`,
  render layer 12 (bit 1<<11) is Krystal's (custom cull masks must include it).
* **Shared world scripts**: `src/world/common/resource_node.gd` (`setup({node_id, kind, tool, hits, drops,
  respawn_minutes, visual, name, tint, scale, glow_light})`, signals `harvested_out`, `respawned`) and
  `world_item.gd` (`static spawn(item_id, count, pos, persistent := true, parent := null)`, `collect()`).
  Surface area also exposes `surface_at(pos)`, `water_level_at(x, z)`; terrain collider `get_surface_at(pos)`.
* **Enemies**: optional boss setup keys `arena_radius`, `crack`; boss signal `anchor_burned(pos)`;
  `stalker.pass_overhead() -> bool`; brazier setup keys `lit`, `persist_flag`; combat target conventions
  `on_hit_blocked(attacker, dir)`, `get_aim_point()`, `hit_radius`, `hit_color`. The stalker emits
  `Events.horror_event("authored:stalker_ambush")`.
* **Director**: `suppress(seconds, replace := false)`; suppressions >= 600 s are holds replaced by the next call.
* **Settings** (core QA): `Settings.RANGES`, `coerce_value(key, v)`, `sanitize_bindings(d)`, `actions_using(ev)`,
  optional `load_settings(path)` / `save(path)`. **SaveSystem**: recovers a complete `.tmp`, moves corrupt
  saves aside (`slot1.corrupt-<unix>.json`). **GameState**: `max_bond_xp()`; quests are also polled once/second.
* **QuestLog**: `step_string(step, field)` returns `alt_<field>` text in arachnophobia mode — UI uses it.
* **Windowed runs**: Godot does not report engine flags in `OS.get_cmdline_args()`, so to keep a debug/QA run
  windowed also pass the user arg: `... --resolution 1600x900 -- --windowed ...`.
* **QA telemetry** (`src/qa/qa_telemetry.gd`, `--qa-telemetry=<file>`): read-only JSON lines used by the
  external real-input bot (`tools/qa/`).
