# Hollowhaven architecture contract

Godot 4.7.2, GDScript, Forward+ renderer, Jolt physics. Project root: `game/`.
Read `GAME_SPEC.md` for design (Chapter Two: `docs/CHAPTER_TWO_SPEC.md`; its conventions are summarised in the last
section, "Chapter Two conventions"). This file defines how code fits together. **Follow it exactly** —
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
    pickup=64, trigger=128, hitbox=256, camera=512 (layer 10: camera-only blockers, `src/camera/camera_block.gd`;
    only `CameraRig.COLLISION_MASK` = 1|32|512 includes it, so every other body and query ignores them - any new
    ray / shape query must set an explicit mask). Player collides with world|structure (1|32). Enemies/companions
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
Title calls `Game.new_game(look)` (after the comfort screen and "Meet Krystal") or `Game.continue_game()`.
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
in "below" only the follower (if `enters_below`) spawns next to the player; Mochi refuses (see spec) unless she has courage
(Chapter Two area classes and doorsteps: last section).
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
Credits / Quit; New Game → comfort screen → "Meet Krystal" → `Game.new_game(look)`.
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
* **Quest skips**: a step in `data/quests.gd` may carry `"skip_if_flag"`; once that flag is set
  `QuestLog.is_skipped(step)` is true, `step_done()` returns true and the step passes silently (no toasts or
  hint). The dungeon steps (wake, prepare, descend, old_mine, deeper, silk) skip on `ward_restored`, so a
  Heartseed returned before the tracker reached them never stalls the chain (the poll repairs old saves).
* **Respawn points**: `Game.change_area()` sets the surface return point to the slept-in bed or
  `haven_respawn` (never the arrival spawn `mine_exit`), and the Below one to the last lantern used, kept in
  `GameState.player["below_respawn"]` by `Game.set_respawn("below", ...)` (old saves: deepest lit lantern).
* **Saving**: `SaveSystem.save_game(quiet := false)`: quiet saves skip `Events.game_saved` on success (no
  toast). `Game.new_game()` saves once the Haven has loaded; the surface autosaves quietly every
  `Game.AUTOSAVE_SECONDS` of unpaused play when `can_manual_save()` allows it (no menu open, not building).
  `auto_accept_quit` is off: a window close request runs `Game.save_before_close()` (same rules as a manual
  save), saves the settings and always quits. `SaveSystem.BACKUP_NOTICE` is re-announced by
  `continue_game()` once the gameplay UI exists.
* **Focus loss**: remembered in `Game._focus_lost`; if the pause menu couldn't open (loading, death screen,
  lift ride, ending) it opens when play resumes (after `area_loaded`, a respawn or `set_cutscene(false)`).
* **Window**: the engine window starts fullscreen (`display/window/size/mode=3`, matching the default
  setting). `Settings.apply_video()` leaves fullscreen for a centred 1600x900 window when the setting is off
  or a debug/QA run passes `-- --windowed`.

## Conventions added by the post-release audit
* **Flicker lights**: any `flicker_light` implementing `flicker(seconds)` must honour Settings
  `reduce_flashing` itself (one slow dip, no strobe) - the director's runner does not pass the setting.
* **Companions**: `teleport_near(pos)` only moves a companion in follow mode (waiting/home/wild ones stay put).
* **Bed spawn**: the respawn bed re-registers the `bed` spawn one physics frame after every
  `Events.structure_placed/structure_removed`; if its wake spot is walled in, the target falls back to
  `haven_respawn` (else `haven_start`) with a toast.
* **Saving**: `SaveSystem.save_game(quiet := false)`; quiet saves (New Game, the 5-minute surface autosave,
  window close on the surface) don't emit `Events.game_saved` on success. Closing the window runs
  `Game.save_before_close()` (surface only). `GameState.player["below_respawn"]` remembers the last lit lantern.
* **Quests**: steps may carry `"skip_if_flag": "<flag>"` - a skipped step counts as done (used so returning
  the Heartseed early never stalls the chain). `QuestLog.is_skipped(step)`.
* **Stalker**: Krystal's own light only repels it during the rattle directly above her; director passes
  recoil only from light at the stalker's own position. Retreats never step toward Krystal.

## Chapter Two conventions (Waves B-D + integration passes 1-3)
The binding contract for Chapter Two is `docs/CHAPTER_TWO_SPEC.md`; what the foundation delivered is `docs/ch2/WAVE_A_REPORT.md`
(schema v2, ChapterLog / OptionalLog, the rewards & flags rule, data catalogue, Game flow, music director). This section lists the
conventions Waves B-D and the integration passes added; each points to the code map with the details (`docs/ch2/maps/*.md`,
the "Chapter Two ... as built" sections). Module ownership: `docs/ch2/WAVES.md`; decisions: `docs/ch2/INTEGRATION_WAVE_BC.md`
(pass 1, after Waves B/C), `docs/ch2/INTEGRATION_WAVE_D.md` (pass 2, after Wave D) and `docs/ch2/INTEGRATION_PASS3.md` (pass 3,
after bug-fix round 1 CH2-001..017 and the visual fixes; its evidence is `QA_REPORT.md` §10).
* **New Game / look** (ui.md §11): title → overwrite confirm → comfort → "Meet Krystal" (`src/ui/screens/creation_screen.gd`) →
  `Game.new_game(look)`. Nothing is written before Confirm. A non-empty look sets `c1x_look_chosen` and `wardrobe.notice_shown`.
  The avatar (player_avatar.md §7) follows `GameState.appearance` / `wardrobe.show_armor` / `equipment` through
  `Events.appearance_changed` / `equipment_changed` / `game_loaded`; UI code writes GameState and emits the event, never pokes the avatar.
  Appearance is cosmetic only (no collision, speed or reach).
* **UI root** (ui.md §11-12): panel `"wardrobe"` (fullscreen, gameplay panel, hotkey **O** = Settings action `wardrobe`, rebindable;
  pass 2 D02); panels `"expedition"` (fullscreen, gameplay panel; opened by the Expedition Board) and `"music_box"` (gameplay panel,
  **not** fullscreen: a paused tree would silence the preview; opened by the Music Box); `ui_root.has_panel(name) -> bool`; the
  one-time wardrobe notice for older saves waits for 3 s of continuous safe play with nothing in `overlay_layer`, never in headless
  runs or with `NOTICE_OFF_ARGS`; `close()` defers `_focus_top()`; endings go through `show_ending()` (Chapter One) and
  `show_chapter_two_ending()` (awaitable, tracked in `_ending` like the Chapter One ending; `Game._show_chapter_two_ending()` prefers
  it). Pause "Return to safety" is per area ("Leave the trial" in the Echo Trial). Underground HUD look for every underground area.
* **Journal / tracker / map / telemetry** (ui.md §11-12): journal tabs Story, Optional, Friends, Lore, Mastery (`args.tab`, alias
  "goals" → story, `reopen(args)`); `tracker.objective_view()` kinds legacy | pointer | chapter2 | signpost | expedition | done |
  hidden (`expedition` = a running Lanternwake Expedition, only in place of signpost / done / hidden, pass 2 P36);
  `MapView.map_kind(area)` surface | reach | rooms | none (room names only in `MapView.ROOMS`); the Reach map draws a running
  expedition's route and resolves `exp_*` ids through `Expeditions.place_disc()` (P35); festival roads after
  `ch2_read_festival_map`; read-only telemetry keys `area_info, chapter2, tracker, optional, equipment, companion_skills, music`.
* **Chapter Two quest rows** (state_save_data.md §14): a `data/quests_ch2.gd` objective may carry `"display": true` - a signpost row
  listed with its real done state (`ChapterLog.check_objective` / `objective_status`, the row carries `"display": true`) that never
  counts for completion (`step_done()` ignores it; a step needs at least one non-display objective). `ch2_quarry` shows "Calm the
  Quarry Warden" and "Mend the mineral winch" this way before its lamp (pass 2 F03, the old R38). Pass 3: the lamp search
  `ch2_outer_lamps` is in step group `"lamps"` with the three lamp roads (each lit lamp pays its road at once, CH2-001); a step key
  `"hint_when"` (an objective) holds the step's hint until it holds; `ChapterLog.from_dict()` adds silent baselines only when no current
  step has one (state_save_data.md §14).
* **Stats and damage** (combat_enemies.md §11): `src/core/stats.gd` is static and recomputed from saved state (never cached across a
  load). Player damage order, once per hit: i-frames → `Stats.damage_reduction()` (cap 45%) → transient shield
  (`Game.player.add_shield(amount, seconds, source)`, read with `Stats.player_shield()`; never `GameState`) → Health. A hit fully
  absorbed by the shield returns 0 and does not emit `Events.player_damaged`. `health.heal()` applies `Stats.heal_mult()` itself.
  Slows only through `player.apply_slow` (bounded, immunity) or `EnemyBase.apply_slow`. Shared projectile
  `src/combat/projectile.gd` `fire(params)` (pooled, LOS every tick, `only_target` / `filter`) for the wand, companions and enemies.
  `Combat.INTENSITY_SCALED_AREAS` = below, tobin_annex, hushed_works; `enemy_base.threat_damage_mult()` follows where the enemy fights.
* **Companions** (companions.md §15): `companion_combat.gd` / `companion_support.gd` / `companion_nav.gd` / `companion_home.gd`; area
  classes `companion_logic.area_class(area)` haven | outdoor | interior | underground (single list, also used by the HUD); doorsteps
  (`DOORSTEPS`, incl. `entries` for the Works refuge hatch); record keys `combat_mode, skill_ready_at, home_spot, ribbon, home_task,
  home_nook, home_log, cairn`; ONE signature cooldown on the `stats.play_seconds` timeline; the skill key `companion_skill` is read by
  the follower only. Boss hazards (meta `boss_hazard`) are never companion or director threats.
* **Crafting, stations, mastery** (building_crafting_farming.md §11): recipe kinds item | timed | apply | pattern | dye; crafting from
  same-area chests within `Crafting.CHEST_RADIUS` = 18 m (opt-in, one transaction); furnace queue in `structures[uid].data`
  (`queue`, `output`, `held_jobs`) on the play-seconds timeline, refunded once on dismantle; chest record keys `slots`,
  `upgrade_refunded`; `GameState.stations` keys `use_chests`, `table_decor`; `src/core/mastery.gd` static, wired once by
  `Game.wire_session_systems()`; Stats applies mastery effects (mastery only exposes values).
* **Building** (building_crafting_farming.md §11): storeys (`data.level`), undo (exact refund, one area visit), recolour
  (`data.tint`, free once a dye is owned), pumpkin faces (`data.face`; festival faces after `ch2_feast`), expanded Haven safe zone +
  "haven" zone, the Reach outpost. `structure_factory.LAZY_SCRIPTS` maps scripts owned by other modules (`wardrobe.gd` belongs to
  the appearance UI module).
* **Enemies** (combat_enemies.md §11): additive `enemy_base` hooks (`committed_states`, `attack_def/telegraph/recover/damage_for`,
  `can_be_hit_by`, `can_stagger`, charge / leap / lane / pulse / projectile helpers, `mark()` → `telegraph_fx.gd`, `defeat_flag`);
  ground marks match the attack footprint and honour `reduce_flashing` / `high_visibility_cues`; spawner params `enemy_params`
  (merged into every enemy's spawn params) and `out_of_view` (never pop in within view); `EnemyFactory.can_spawn(id)` guards every
  spawn; elites use Settings `timing_assist` like bosses; `boss_defeated(id)` listeners must check the id.
* **Chapter Two enemies and bosses** (combat_enemies.md §12, pass 2 P07): opt-in intensity helpers `intensity_cooldown_mult()` /
  `intensity_telegraph_bonus()` / `overlap_blocked()` (the C5 enemies; legacy enemies unchanged); `fire_projectile` params `dir` /
  `on_hit` / `kind`; the shared attack-token table for non-enemy_base attackers `claim_attack_token(id)` / `release_attack_token(id)`
  (the Choir); `telegraph_fx.move_ring(at)`; `expose(seconds)` only on the light-fearing Velvet Wing (breaks a drain) and Borrowed
  Wisp (forced reveal) - never on bosses. Setup keys: `pumpkin_mimic` `dormant` (never passed by spawners) / `seed`; `quarry_warden`
  `arena`, `arena_center`, `arena_radius`, `pillars` (leash = arena radius + 6 m within a 3 m height band; timing assist ×1.5; the
  charge lane is clipped 1 m inside the arena and a ledge bonks; one exposure takes at most `EXPOSE_CAP` 35 % and phase 2 owes its
  three pulses, `PULSE_FLOOR_RATIO` 30 % floor until they played - pass 3; after 2.0.0, CHAIN-001 / 002: a `SHELL_FLOOR_RATIO`
  50 % floor until its first exposure of the attempt while an intact pillar stands, and it fights only on its arena floor -
  `ARENA_FLOOR_DY` 1.2 m band, no attacks across levels, gives up after 5 s with her off it). Bosses take `"mode": "story" | "trial"` (trial: no
  flags, no `boss_defeated`): `count_velour` (in group "enemy" only while fighting; one clean reset rule; one window ≤ `WINDOW_CAP`
  16 % through `velour_health.window_room`, checked before the blow lands, a finishing blow never trimmed), `crossing_matron` (arena
  `boss_params()` incl. `rail`; with a Lantern the HP floor `Rules.HP_FLOOR` is 60 / 35 / 20 % before exposures 1 / 2 / 3 and the
  flare's scorch stops at the floor of its own exposure, so a win takes three exposures, one per phase; a flare under her anchor
  exposes her only once she has committed this round - before that it primes the anchor and her next pounce landing exposes her
  (`is_engaged()` / `is_primed()`); `retreat_seconds()`, ceiling run ≤ `RETREAT_RUN_MAX` 3 s; `crossing_rules.gd` assumes the bridge
  centre line at z = 0), `borrowed_choir` (three exposures per phase; holds an attack token while committed). The Chapter One
  Weaver Matron: one stun window ≤ `WINDOW_CAP` 40 % in phase 1 / `LATE_WINDOW_CAP` 15 % in phases 2-3, a blow crossing 144 / 72 HP
  stops on it (`next_phase_hp()`), a phase 2-3 scorch before that phase's first action is banked (`scorch_banked()`). Weaver and
  Warden trim even a would-be lethal blow; Velour never trims a finishing blow (accepted difference, pass 3 R3-10).
* **Lost sight (pass 3, CH2-006)**: an ordinary `enemy_base` enemy that has not seen Krystal for `lose_sight_seconds()` (5 s; data
  `"lose_sight"`; sight or her hit resets `unseen_time()`) drops the chase and goes home, so it stops blocking saves and travel;
  elites and bosses (data `elite` / `boss`) never give up this way.
* **Areas and loading** (world_areas.md §8): `Game.prefetch_area(area_id, extra := []) -> int` compiles an area's scene and its
  `AREA_WARMUP` scripts on loader threads (idempotent, never blocks, EnemyFactory first on the main thread); `load_area` uses it, and
  the waygate / Bellhouse stair call it early behind `has_method` guards; since pass 2 (P38) the Reach, the Chapter Two bosses and
  the Echo Trial arenas are warmed too. `Game.wire_session_systems()` (idempotent; the test runner re-wires between suites): mastery
  listeners, the Chapter Two activity tracker, and since pass 2 (P34) `init()` of Expeditions, the Music Box and the Echo Trial's gift
  payer plus `attach(self)` of the onboarding hints - each safe-loaded and optional. A position saved on an upper storey is restored
  after the structures exist. Pass 3: `quit_game()` and the window close request call `Game.release_prefetches()` (claims every
  outstanding threaded load, CH2-011); `Game.is_landmark_zone(area, zone)` is false for a helper zone (its `zones` entry carries
  `"landmark": false`, set by `annexes.gd` `mark_helper_zone()`: the Woods waygate circle), which is never a discovery or Lumi bond XP;
  camera-only blockers (`CameraBlock.add_box()`, layer 512) sit on the waygate lintel, Lantern Road arch tops, Works lift roofs and the
  Echo Trial pale door, and arrival spawns keep ~5 m clear behind them (`test_camera_spawn_clearance.gd`).
* **Loading card** (after 2.0.0, perf finding "Continue freezes the screen"): an area still builds its children in ONE blocking
  main-thread frame, so `load_area()` shows `Game.loading_card` (`src/ui/screens/loading_card.gd`, CanvasLayer 60 under the Game
  autoload: fade-colour backdrop, parchment card with `MapView.area_name`, a lantern glow that pulses - steady with `reduce_flashing`)
  after the UI root's fade-out and awaits `show_loading_card()`, which returns only once `PRESENT_FRAMES` (2) more frames with the
  full card were drawn; only then `area_exiting`, the scene change and the build. After `area_loaded` it dissolves (0.4 s) inside
  the UI root's 0.6 s fade-in. The UI root's hush is `"loading"` while it is up and `Game.mode == "loading"`. `Game.continue_target(player)`
  is Continue's destination rule; the title calls `Game.prefetch_continue(SaveSystem.peek())` while it offers Continue, and the
  Lantern Road menu prefetches its other-area destinations. Order guard: `tests/unit/test_flow_loading_card.gd`.
* **Echo Trials** (world_areas.md §8; spec §1): one area `echo_trial`, the table `data/trials.gd` (`matron`, `velour`, `choir`),
  arena builders `src/world/trial/{velour,choir}_trial.gd` (`static build(area) -> Dictionary`, the real bosses in mode "trial"),
  echo stones `src/world/trial/trial_entry.gd` at each origin checkpoint (Below `cp_arena`, manor `manor_ballroom`, Works
  `bell_throat`). **A trial opens right after its boss is defeated** (its `requires_flag`; lead decision L07 - `ch2_trials_open`
  gates nothing). `echo_trial.begin(id, origin_area, origin_spawn)`; leaving, falling and Continue all return to the origin; a trial
  never reads or writes a story flag or emits `boss_defeated`. First clear = its content bundle through the ledger (pattern-unlock
  flag `ch2_trial_<id>`); repeat clears are renewable and wait in `GameState.trials[id].pending` until `echo_trial.pay_pending()`
  pays them on arrival at the origin (L08; `echo_trial.init()` wires it).
* **Lanternwake Expeditions** (`src/expeditions/expeditions.gd`, static; data `data/expeditions.gd`; spec §3 extra key): `init()` /
  `shutdown()` / `is_listening()` (Events.area_loaded gives the Reach its runner `expedition_runner.gd`, node `RUNNER_NODE`
  "Expeditions", ONLY while a run is active), `template_ids()`, `template(id)`, `is_unlocked(id)`, `lock_reason(id)`, `preview(id)`,
  `plan(id, seed)`, `state()`, `active()`, `is_active()`, `start(id, seed := -1)`, `abandon()`, `record_defeat(...)`, `complete()`
  (records the completion BEFORE paying: once), `current_target()`, `tracker_view()` (kind "expedition", shown by the tracker only
  when there is no chapter / legacy / pointer step), `map_marks(area)`, `place_disc("exp_*")`, `summary_line()`. Expeditions never
  write a flag, the ledger or a quest layer; rewards are renewable materials, candy and sometimes a keepsake (a dye palette or a
  festival decoration); no timers, no daily limits. Board `src/building/structures/expedition_board.gd` -> panel "expedition".
* **Music Box** (`src/audio/music_box.gd`, static, autoload-free): `init()` / `shutdown()` / `is_listening()` (the discovery listener on
  `Events.music_cue_changed`: cues of kind safe / explore / ending heard in play; `STARTER_CUES` m01 always known), `is_eligible`,
  `eligible_cues`, `title`, `home_of`, `note_heard`, `is_discovered`, `discovered`, `heard_at`, `favourites`, `is_favourite`,
  `set_favourite`, `toggle_favourite`, `preview(cue, source := null) -> bool` (false when higher music already plays),
  `stop_preview(fade)`, `preview_cue()`, `is_previewing()`, `should_stop(area, zone, player_pos, box_pos, box_area)`,
  `music_muted()`, `owns_music_box()`. The preview is the music director's `"musicbox"` context (**priority 40**, one pass; data in
  `data/music.gd` CONTEXTS since pass 2 P46): above the Haven (30) and exploration (20), ended for good by any higher music (combat,
  horror, boss, authored, title), by death and by leaving the area; boss / combat / horror cues are refused as previews. **House
  rule**: the box stops its preview when Krystal leaves its house - she must stay in the box's own area and, on the surface, in the
  Haven zone or within 12 m of the box (elsewhere, e.g. the Reach outpost, within 12 m). Favourites add at most 2 extra entries per
  Haven round. The panel `music_box_panel.gd` is NOT fullscreen, never pauses, and closes when she is hurt
  (`Events.player_damaged`). With the Music bus muted the director decides nothing: nothing is discovered and a started preview
  stays "Now playing" until Stop / leaving (kept, P47).
* **Onboarding hints** (`src/world/story_ch2/onboarding_hints.gd`): one node under Game (`static attach(parent) -> Node`, idempotent;
  never steps by itself in headless runs - tests call `tick(dt)`); `arm(id, delay)`, `suppression_reason()` ("" or one of
  `inactive, hints_off, cutscene, not_playing, no_ui, busy, boss, trial, combat, horror, unsafe, notice, card`), `is_shown(id)`,
  `armed_ids()`, `hint_text(id)`. Emits through `Events.hint`; once per save via the HUD card's `hint_<id>` flag; writes nothing
  else. Pacing `CALM_SECONDS` 2.5, `MIN_GAP` 25, `HORROR_QUIET` 30 (untuned until a real play session, P50). `"where"` is "", an area
  id, `"outdoor"` or `"echo_origin"` (an area whose echo stone stands).
* **Input (pass 2, D02 / D03)**: Settings actions `wardrobe` (O), `build_undo` (Z), `build_recolor` (P), `build_variant` (N) are in
  `DEFAULT_BINDINGS` and `REBINDABLE`, with HUD tokens `{wardrobe}`, `{undo}`, `{recolor}`, `{variant}`; a settings file without them
  gets the defaults. `build_mode.gd` prefers the InputMap action and keeps its `FALLBACK_KEYS`.
* **Saved state of Wave D** (SAVE_MIGRATION.md §2, state_save_data.md §14): `GameState.trials[id]` keys `clears`, `best_seconds`,
  `last_seconds`, `repeat_paid`, `paid`, `pending`, `pending_clears`; `GameState.extra["expeditions"]` and
  `GameState.extra["music_box"]` (top-level keys GameState keeps verbatim; no migration; reset by New Game).
* **Lore** (state_save_data.md §14): `src/core/lore_db.gd` `get_lore(id)`, `has_lore(id)`, `ids()`, `chapter_of(id)` (by source file;
  Tobin's annex notes are Chapter One); `UiUtil.lore_entry` delegates to it.
* **Tests** (state_save_data.md §14): the runner isolates test files (restores Game flow state, frees strays, re-wires the session
  listeners, prints `ISOLATION <suite>: ...`) and accepts comma-separated `--filter` fragments; the leaks it repairs are a known
  test-hygiene item (F04). Visual-QA commands for the new screens are in AGENTS.md; the still-pending visual, listening and
  real-input checks are in KNOWN_ISSUES.md.
