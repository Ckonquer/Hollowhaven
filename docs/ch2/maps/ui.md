# UI subsystem map (for Chapter Two)

Scope: `game/src/ui/**` plus the tests `tests/unit/test_ui_*.gd` and `test_audit_ui_*.gd`. All paths below
are relative to `game/`. This supplements `docs/ARCHITECTURE.md` § UI and does not repeat it.

## 1. Runtime construction

- **Gameplay UI root.** `Game.load_area()` (`autoload/game.gd:234-236`) creates it once:
  `_safe_new(UI_ROOT_SCRIPT, FALLBACK_UI)`, a child of the `Game` autoload. It survives area changes and is
  freed only by `Game.goto_title()` (`game.gd:168`). The fallback (`tests/preview/fallback_ui.gd`) implements only
  `fade_out/fade_in/open/close/show_death/show_ending`. Anything else called on `Game.ui` needs a
  `has_method()` guard.
- **`ui_root._ready()`** (`src/ui/ui_root.gd:61`) sets layer 50, `PROCESS_MODE_ALWAYS` (every panel/HUD child
  inherits it and keeps processing while the tree is paused), and builds `Root` (full rect, `theme =
  ThemeFactory.get_theme()`, mouse IGNORE). Its children are added in this z-order (bottom to top):
  `HUD` (`hud/hud.gd`) → `Overlays` (chapter card, death, ending) → `Top` (toasts in a
  `Kit.margin([34,34,34,150])`, quest banner) → `Panels` → `Fade` ColorRect. The fade starts black when `Game.mode == "loading"`.
- `ui_root` connects `Events.area_loaded` (close_all, re-emit current quest hint, queue icon warm-up, debug boot),
  `area_exiting` (close_all) and `settings_changed` (on "arachnophobia" it calls `refresh()` on every open panel).
- **Title screen** (`src/ui/title_screen.gd`, a Node, not ui_root). It has its own `CanvasLayer` (layer 10),
  `Diorama` 3D backdrop (`title/title_diorama.gd`, owns the current Camera3D) and its own single-panel
  system (`_panel`, `_open_panel` :220, `_close_panel` :232, `_confirm` :253). Panels opened here have
  `ui_root == null`. Game.push_ui/pop_ui are **not** called and nothing pauses.
- **HUD** (`hud/hud.gd`): 5 margin regions (MARGIN=34). TL: vitals, companion badge, hint card. TR: day
  dial, tracker. TC: boss bar. BC: captions, dialog box, then `gp` vbox (prompt, build bar, hotbar). BL: FPS.
  `gameplay_regions` (TL, TR, gp) fade out in `set_cinematic(true)` (`hud.gd:130`). It is driven by
  `Events.cutscene_changed`, `player_died/respawned` and `area_loaded`. The HUD is tinted `Color(0.84,0.82,0.88)`
  only when `area == "below"` (`hud.gd:100-105`; Chapter Two: every underground area, §11).

## 2. Panel registry & lifecycle

*(Chapter One code as mapped before Wave B; the Chapter Two changes are in §11.)*

`ui_root.gd:23-40`:
```gdscript
const PANELS := {"inventory":…, "crafting":…, "storage":…, "journal":…, "map":…, "companion":…,
  "pause":…, "settings":…, "controls":…, "comfort": screens/comfort_screen.gd, "confirm": screens/confirm_dialog.gd}
const FULLSCREEN := [inventory, crafting, storage, journal, map, pause, settings, controls, comfort, confirm]  # pause world
const GAMEPLAY_PANELS := [inventory, crafting, storage, journal, map, companion, controls]  # hotkeys may switch away
const HOTKEYS := {"inventory":"inventory", "craft":"crafting", "journal":"journal", "map":"map", "help":"controls"}
```
*Current (after integration pass 2):* `PANELS` also has `"wardrobe"` (B2), `"expedition"` (D2) and `"music_box"` (D3);
`FULLSCREEN` adds `wardrobe`, `expedition` (NOT `music_box`); `GAMEPLAY_PANELS` adds `wardrobe`, `expedition`, `music_box`; `HOTKEYS`
adds `"wardrobe": "wardrobe"` (Settings action `wardrobe`, default O, rebindable; D02). Details in §11 / §12.
The UI root is the only registry: `Game.open_panel(name, args)` (`game.gd:449`) calls `ui.open(name, args)`.

**`open(panel_name, args={})`** (:154):
1. `"comfort"` not yet open → `show_comfort(args.first_time)`.
2. Already open → move to front and to the end of `order`, then call `reopen(args)` if defined, else `refresh()`.
3. Otherwise `_instantiate` (:180): `load(path).new()`, `name = panel_name.capitalize()`, sets `panel_id` and
   `ui_root`, calls `setup(args)` **before** add_child, and connects `close_requested` → `close.bind(name)`.
4. Adds it to `panel_layer`, then `Game.push_ui(name)` → `_update_pause()` (pauses via `Game.set_paused(true)` if any open
   panel is in FULLSCREEN; `_paused_by_ui` remembers who paused) → `_refresh_focus_layers()` → `ui_open` sound.

**`close(panel_name)`** (:200): erase → `on_close()` → `animate_out_and_free()` (0.14 s fade) → `Game.pop_ui` →
unpause if nothing fullscreen remains → focus layers → `ui_close` sound. Closing "settings" also saves Settings.
Afterwards it calls `_focus_default` (deferred) on the new top panel.
Other API: `close_all()`, `is_open()`, `top_panel()`, `toggle()`, `confirm()` (see §5), `teleport_player(spawn_id)`
(unstuck, :415).

**`panel_base.gd`** (`panels/panel_base.gd`), fields: `panel_id, ui_root, args, title, dim_background=true,
window_min=Vector2(1100,700), show_close=true, window (Parchment), body (VBox sep 14), close_btn`.
The `_ready()` order is fixed (:35): dim ColorRect (ThemeFactory.DIM) → `_frame` → `window = Parchment.new()` with a
ribbon if `title != ""` → `body` → close button (FOCUS_NONE, placed on `sort_children`) → **`_build()` →
`refresh()`** → `_layout_window()` (centres the window, clamps to the viewport minus 24 px, min y 30) → `_animate_in()` →
`_focus_default` (deferred).
Overrides: `setup(p_args)` (call `super.setup`, set `title` and `window_min` here, **before** `_ready`),
`_build()`, `refresh()`, `on_close()`, `handle_key(event)->bool`, `is_capturing_input()->bool`,
`default_focus()->Control`, optional `reopen(args)`. Close yourself with `request_close()` (it emits
`close_requested`; the owner does the rest). The helper `section_title(text)` (:165) gives a leaf glyph plus a Subheading.
`dim_background=false` (companion panel) → the root is mouse-IGNORE and only the window blocks clicks.

## 3. Input, focus, pause

- `ui_root._input` (:289) uses `_input`, not `_unhandled_input`. It sees only pressed, non-echo key and mouse-button
  events. It returns early while `_ending` or `_death` exist. If any open panel `is_capturing_input()`, it returns
  (the settings rebind). Then the **top panel's `handle_key(event)`** runs first (true → handled). Then the
  `"pause"` action (Esc; it is **not** in `Settings.REBINDABLE`) closes the top panel, or opens "pause" when
  `Game.mode=="playing"` and `!_fade_busy()` after trying to exit build mode (`_exit_build_mode` calls
  `end/exit/cancel/stop` on the group "build_mode"). Last come the HOTKEYS through `_hotkey` (:323): same key toggles
  closed; needs `mode=="playing"` and no fade; switches only away from GAMEPLAY_PANELS; "controls" may stack over
  pause/settings.
- **`ui_cancel` is not used anywhere.** Esc is the `pause` action. Enter/arrows are Godot's built-in `ui_accept` /
  `ui_up…` on the focused Control.
- Focus: `_refresh_focus_layers` (:259) sets `focus_behavior_recursive` to 0 (inherited) on the top panel and 1
  (disabled) on covered panels and on the HUD while any panel is open. The title does the same to its `menu` while a panel is open.
  Panels give keyboard focus through `default_focus()`. The crafting panel shows the patterns: the selection follows
  `focus_entered`, a `ScrollContainer.follow_focus = true`, and Enter handled in `handle_key` (crafting_panel.gd:301).
- `_fade_busy()` (:140): `fade_rect.color.a > 0.01` or the fade is blocking the mouse. Pause and hotkeys refuse to act during it,
  but **`open()` itself does not check it**, so a panel opened under a fade is hidden.
- Journal `handle_key`: Q/PageUp and E/PageDown cycle the tabs (journal_panel.gd:66).
- Inventory `handle_key`: Esc while carrying a stack cancels the carry. `hotbar_1..8` selects a slot.
- `Game.gameplay_input_allowed()` is false while `_ui_stack` is non-empty (the companion panel holds Krystal still but
  does not pause). `Game._update_mouse()` shows the cursor whenever `_ui_stack` is non-empty.
- `dialog_box` (Events.say) pauses its line timer while `Game.is_ui_open()`. `quest_banner` holds its queue while a
  menu is open (`quest_banner.gd:48,79`). `dialog_box.advance()` exists but **nothing calls it** (no click-to-advance).

## 4. Quest tracker, journal, map

*(Chapter One code as mapped before Wave B; the Chapter Two changes are in §11.)*

**Tracker** (`hud/tracker.gd`): a HudCard 440 wide. `refresh()` (:52) reads `GameState.quests.current_step()` and
`objective_status()` → `[{label, done, progress, target}]` (`src/core/quest_log.gd:83`). It rebuilds only when the signature
`"%s|%s|%s|%s" % [step id, str(status), Game.area_id, here]` changes. Triggers: `objectives_changed`, `quest_step_started`
(glow tween), `area_loaded`, `settings_changed` ("bindings"/"arachnophobia") and a 1 s poll (`_check_t`). The header
is `"OPTIONAL GOALS"` if `step.optional`, else `"CURRENT GOAL"`. Title via `step_string(step,"title")`. Rows are pooled
(`_rows`, `{box, icon, label, progress}`). "Head to X · M Map" shows only when `Game.area_id=="surface"`, `step.target` is a
key of `Layout.LANDMARKS`, and Krystal is outside its radius (`_player_at`). It hides when there is no step or `!GameState.active`.

**Journal** (`panels/journal_panel.gd`), title "Journal", window_min 1520 wide. A `TabContainer` 1440×700 whose tab
titles are the **child node names** "Goals", "Lore", "Friends". `args.tab` is matched against the lowercased tab
title (:53). `_build()` connects `Events.objectives_changed` → `_build_goals` (a bound method, auto-dropped on free).
`refresh()` rebuilds all three tabs by `queue_free`-ing their children.
- Goals (:82): a left Card (820) holds the current step: header, title, `step_string(…,"text")`, objectives, "Head to <landmark>",
  and a Tip formatted by `hint_card.format_hint`. A right column (520) holds **hard-coded "Chapter One" / "The Dimming Ward"** (:140),
  a ProgressBar counting non-`optional` STEPS completed, and a scrolling "Completed" list over `QuestsData.STEPS`.
- Lore (:180): TabLike toggle buttons (ButtonGroup) per `GameState.lore` id and a page via `UiUtil.lore_entry(id)` (reads
  `src/world/below/lore.gd get_lore`).
- Friends (:222): one Card of 440×600 per `ItemDB.creature_ids()` in an HBox (portrait, name/"???", species, hearts, blurb,
  favourite food, `CompanionPanel.status_text(id)`, or `unmet_hint(id)` (:269)).

**Map** (`panels/map_panel.gd`): the branch is **only** `Game.area_id == "below"` → `_build_below()` (lantern icon plus
"The map can't help you down here"). **Every other area id draws the surface map.** The surface map: `MapView` 800×800 plus a
460-wide side column ("Where to?" card from `step.target`, a legend, and a "Places" 2-column grid over `Layout.LANDMARKS` with
`MapView.ICONS.get(id,"unknown")`).
`widgets/map_view.gd`: `_draw()` every frame while visible (`_process` → `queue_redraw`). Constants: `H := 118.0` (world half
extent shown = `Layout.WORLD_HALF_EXTENT + 8`), `REGIONS` {landmark: [Color, radius mult]}, `ICONS` {landmark: icon id},
`PATHS` (landmark ids, or `"@n"` = `Layout.STREAM_CROSSINGS[n]`). Draw order: regions, mine cliffs (hard-coded
`LANDMARKS["mine_mouth"]`), dashed paths, stream spline (`STREAM_POINTS`), pond (hard-coded `"pond"`), crossings, 150 seeded
trees (seed 20240517, computed once in `_ready`), forest frame, objective pulse (`target_id`), companion portraits from
`Game.companion_nodes`, landmark stickers and names, player arrow (camera yaw via `UiUtil.map_heading`), compass.
Projection: `UiUtil.world_to_map(world_xz, rect, half_extent)` / `map_to_world` (ui_util.gd:461), north = −Z = up.
Surface landmarks (`data/world_layout.gd:18`): haven (0,0) r20, glade (−55,12) r22, quarry (66,−12) r22, ruin (−12,−66)
r20, mine_mouth (54,−74) r14, pond (46,52) r16, meadow (−8,60) r22, old_oak (−34,−20) r10, thicket (−62,−46) r16.

## 5. Dialogs & prompts

- **Choice dialog = `confirm_dialog.gd`**, a panel_base subclass with any number of buttons:
  `setup({"title", "text", "buttons": [[id, label, variation], …]})` (default `[["ok","OK","AccentButton"],["cancel","Cancel",""]]`),
  `window_min = Vector2(760,0)`, signal `chosen(choice: String)`. `_choose(id)` emits and then calls request_close. `on_close()` emits
  `"cancel"` if nothing was chosen (Esc, X, close_all, area change). The first button gets focus.
- **Awaitable wrapper `ui_root.confirm(title, text, buttons=[]) -> String`** (:270): it closes an existing confirm (which
  answers "cancel"), opens "confirm" (FULLSCREEN → pauses and pushes UI), and awaits `chosen`, handling the one-argument
  await quirk. Used by pause (unstuck, quit), settings reset. On the title: `title._confirm(...)` (same shape).
- Speech: `Events.say(speaker, text, duration)` → `dialog_box.say()` queues ≤5 lines. Duration ≤0 →
  `clamp(2.6+len*0.05, 3, 9)`. An empty speaker, or a speaker name containing "stone"/"inscription", is rendered centred and italic.
- Interaction prompt: `hud._update_prompt()` polls `Game.player.get_prompt()` every 0.08 s (only when playing, no UI, not
  cinematic, not building) → `prompt.set_prompt({text, action="interact", enabled=true, reason})`.
- Hints: `Events.hint(id, text)` → `hint_card.on_hint` shows each id once (persisted as GameState flag `"hint_<id>"`), obeys
  `show_hints`, and replaces tokens from `UiUtil.TOKEN_ACTIONS` (ui_util.gd:10; `{move}` special).
- Toasts: `Events.notify(text, kind)`, kinds `info/success/warn/item/quest/bond/save` (`toasts.gd:12`). The "quest" kind
  goes to the quest banner, which splits `"Prefix: text"` into a small caps header plus a heading. Item pickups merge within 2.5 s
  (`UiUtil.ToastModel`).

## 6. Title → New Game flow

*(Chapter One code as mapped before Wave B; the Chapter Two changes are in §11.)*

`title_screen._on_new_game()` (:294): `_busy` guard → if `SaveSystem.has_save()`: `await _confirm("Start a new
journey?", …, [["new","Start fresh","AccentButton"],["cancel","Keep my save",""]])`, return unless "new" →
`ComfortScreen.new(); setup({"first_time": true}); _open_panel(c); await c.confirmed` → `if not c.accepted: return` →
`_busy = true; await _fade_to_black(1.1)` (it also stops the music) → `Game.new_game.call_deferred()`.
`Game.new_game()` (game.gd:175): `GameState.new_game()` (reset, which **does not reset `player_name`**) → `load_area("surface",
"haven_start")` → quiet save → `Events.hint("intro_move", …)` → `ui.show_chapter_card("Chapter One", "The Dimming Ward")`.
Comfort (`screens/comfort_screen.gd`): signal `confirmed` is emitted from `on_close()` on **every** close path. `accepted`
is true only through the "Begin the journey"/"Done" button (node name "Confirm"). `on_close` also sets Settings
`comfort_confirmed` and saves. The in-game mine entry uses the same pattern through `Game.ui.show_comfort(false)`, then reads
`panels["comfort"].accepted` (`src/world/surface/mine_entrance.gd:267`).
The debug path `--title-show=newgame` sets `_panel.accepted = true` and closes (title_screen.gd:359).

## 7. Icons (`src/ui/icon_factory.gd`)

This is a CPU SDF rasteriser (`class Raster`, :1001) on a 96-unit design grid. It produces sticker style (ink outline 3,
cream backing border 4, drop shadow) for items and flat output for glyphs/portraits. Cache key `"%s|%s|%d" % [icon_id,
color.to_html(), size]`, `ImageTexture`, mipmaps when size ≥32, size clamped 8..512.
API: `item_icon(item_id, size=96)` (uses ItemDB `icon` and `color`; silk→"spool" under arachnophobia),
`item_icon_id`, `item_color`, `icon(icon_id, color=WHITE, size=96)`, `portrait(creature_id, size=128)` →
`"portrait_<id>"`, `glyph(kind, w, h, color=WHITE)` (design height 48), `has_drawing(id)`, `render()` (uncached),
`clear_cache()`.
- `ITEM_ICONS` (:21): log, stone, fiber, berries, ore, seeds, root, pebble, mushroom, silk, crystal, axe, pickaxe, sword,
  lantern, snack, stew, skewer, workbench, chest, bed, plot, floor, wall, window, doorway, roof, fence, lamppost, flowerpot,
  rug, table, stool, cairn, chime, heartbloom, banner, key, heartseed.
- `EXTRA_ICONS` (:26): spool, unknown, ui_heart, ui_heart_empty, ui_stamina, ui_check, ui_star, ui_info, ui_warn, ui_bag, ui_sun,
  ui_moon, ui_lock, ui_close, ui_hint, ui_quest, ui_save, ui_speaker, map_house, map_ruin, map_mine, map_pond, map_flower,
  map_oak, map_thorn, map_quarry, map_glade. `PORTRAITS` = mochi, pebble, lumi.
- Glyph kinds (`_draw_glyph` :950): box_off/on, radio_off/on, switch_off/on, knob, knob_hot, arrow_down, arrow_right, close,
  dot, diamond, leaf (anything else draws a dot).
- Dispatch is the `match` in `_compose` (:190). Shape helpers: `C` circle, `E` ellipse, `B` rounded box, `L` tapered polyline,
  `P` polygon, `R` ring, `CUT(part)`. Fill options: `o` outline, `back`, `alpha`, `shade`, `soft`, `ink`. `NO_LINE`/`DETAIL` presets.
- Warm-up: after every `area_loaded`, ui_root renders one item icon per frame from `ItemDB.all_item_ids()` (:449, :455).

## 8. Theme (`src/ui/theme_factory.gd`)

The theme is built once (`static var _theme`) and set on `ui_root.root` and `title.root`. It is authored for a **1920×1080
canvas** (project: `canvas_items` stretch, `expand` aspect). Fonts: `font(kind)` returns a cached `FontVariation`;
Fredoka for `heading*`/`display`, Nunito otherwise. Weights (:51): body 600, body_bold 800, body_light 500, heading 600,
heading_bold 700, heading_light 450, display 700.
Sizes: FS_TINY 18, SMALL 21, BODY 24, LARGE 28, H3 30, H2 40, H1 56, DISPLAY 96; Button 26 (heading).
Colours: INK 3b2f35, INK_SOFT 6e5d63, PAPER f7ecd6, PAPER_DARK e8d6b0, PAPER_LIGHT fffaf0, PAPER_MID f1e2c3, CREAM fff4e0,
BORDER c9a47e, BORDER_DARK 8e6a4f, ACCENT e4665c, GOOD 6fae4f, WARN e9a15b, BAD d9446a, GOLD f2c14e, TEAL 3fa7a0,
DIM (0.12,0.09,0.13,0.58), HUD_DARK.
Variations. Labels: Heading, Title, Display, Subheading, Small, Tiny, Muted, GoodText, BadText, WarnText, HudText, HudTitle,
HudSmall, RibbonTitle, KeyCapLabel, CardTitle. Buttons: AccentButton, GhostButton, RoundButton, TabLike, TitleMenuButton.
PanelContainers: Card, Inset, HudCard, HudDark, Pill, Ribbon, KeyCap, SlotPanel, Tooltip.
Helpers: `box(bg, radius, border_w, border_col, margins, shadow…)`, `focus_ring()`, `parchment_style()`,
`paper_material()` (a shared canvas shader for paper grain, applied to the node's own drawing only).
`ui_kit.gd` builders (all static): label :11, wrap_label :22, rich :29, button(text, cb, variation, icon) :42 (hooks
click/hover sounds), close_button :57, icon_rect :76, vbox/hbox :87/:93, margin :99, panel :109, spacer/expander :116/:123,
hearts(level, max=5, size) :136, key_cap / action_caps :146/:156, full_rect :178, **retween(node, holder, key)** :188 (kills
the previous tween), **listen(owner, signal, cb)** :199 (auto-disconnects on tree_exiting; needed for lambdas made in static funcs).

## 9. Settings schema (`src/ui/settings_schema.gd`)

`TABS` = [[gameplay,"Gameplay"],[controls,"Controls"],[video,"Video"],[audio,"Audio"],[comfort,"Comfort"]].
Each `ROWS` entry is `{key, tab, type: toggle|slider|option|intensity, label, desc, min?, max?, step?, fmt?: pct|deg|m|mult,
options?: [[value,label],…], test_ui?/test_sfx?}`. `key` must exist in `Settings.DEFAULTS` (tested). Helpers:
`rows_for(tab)`, `row(key)`, `snap`, `coerce` (by the DEFAULTS type), `apply(key, v)` → `Settings.set_value`, `format_value`,
`option_index`, `intensity_info`. Widgets: `widgets/setting_rows.gd` `build(key, width, compact)` / `control(key)` /
`intensity_picker`. They are live-bound through `Kit.listen(Events.settings_changed)`. The settings panel renders
gameplay/video/audio rows generically. The controls tab lists `Settings.REBINDABLE`. The comfort tab is hand-picked keys.
`RESET_KEEPS` (settings_panel.gd:13) lists the keys that Reset leaves untouched.

## 10. Performance tricks already in place

Tracker: signature compare plus a 1 s poll. Polls: prompt 0.08 s, FPS 0.5 s. The badge rebuilds hearts only on a level
change. Map trees are seeded once. Icons are cached and warmed one per frame. Theme, fonts and paper shader are shared.
`Kit.retween` prevents stacked tweens. Queues are capped (toasts 5, banner 4, dialog 5). `ui_root._wait_tween` polls
`process_frame` so killed fade tweens never hang awaiting callers.

## 11. Chapter Two (Waves B/C + integration) — as built

Sections 1-10 describe the Chapter One code; this section maps what Waves B/C changed. The code headers are the source of truth
(`ui_root.gd`, `title_screen.gd`, `screens/creation_screen.gd`, `panels/wardrobe_panel.gd`, `widgets/avatar_preview.gd`,
`panels/journal_panel.gd`, `hud/tracker.gd`, `widgets/map_view.gd`, `panels/map_panel.gd`, `src/qa/qa_telemetry.gd`).

**New Game flow ("Meet Krystal", B2).** `title_screen._on_new_game()`: overwrite confirm (only with a save) → comfort screen →
**Meet Krystal** (`screens/creation_screen.gd`: `signal finished`, `var look`, `accepted`, `result` "confirm" | "back";
`setup({"look"})`, `choose(key, value) -> bool`; only starter pieces can be chosen, earnable ones show how to earn them) →
fade → `Game.new_game(look)` (tests replace the hand-over with `title_screen.launch_override`). Back / Esc / X on Meet Krystal
returns to the comfort screen with the draft look kept; Esc there returns to the title. **Nothing is written before Confirm**
(tested: the old save stays byte-identical, no files are created). `Game.new_game(look)`: `GameState.new_game()` →
`_apply_new_game_look(look)` → for a non-empty look sets flag `c1x_look_chosen` and `GameState.wardrobe["notice_shown"] = true`
(integration R01; `CreationScreen.arm_new_journey_marks()` sets the same two marks through `Events.appearance_changed`, a
harmless second path). The title footer and the Continue line follow the save's chapter (`static footer_text(save_data)`).

**Panel registry additions (B2).** `"wardrobe"` is in `PANELS`, `FULLSCREEN` and `GAMEPLAY_PANELS` (hotkey O since pass 2, see
§12; it was deferred D02 in pass 1). `ui_root.has_panel(name) -> bool` says whether a panel is registered (the Ward Stone asks for
"wardrobe" before offering it). Openers: pause menu "Wardrobe", Ward Stone option, the wardrobe / vanity mirror furniture
(`src/building/structures/wardrobe.gd`, owned by B2: `Game.open_panel("wardrobe", {"source": structure_id})`).
`wardrobe_panel.gd`: args `{"category", "source"}`; inner classes `Looks` (pure look / ownership / preset logic:
`can_choose`, `how_to_earn`, `with_choice`, `with_outfit`, `merge_edit`, `wear`, `reset_to_legacy`, `save_preset/rename_preset/
apply_preset` (3 slots, names ≤ `PRESET_NAME_MAX` 40), `missing_names`) and `LookEditor` (category tabs + option grid; Q/E or
PageUp/PageDown switch category, `<` `>` or a mouse drag turn the preview). Changes are worn at once and free; "Undo changes"
returns to the look at open; only the keys the player changed are written, so ids from a newer version survive (named under the
editor). Wearing a changed look or resetting sets `c1x_look_chosen`. `widgets/avatar_preview.gd`: own `World3D`, transparent,
redraws only while visible, drives the real avatar in "live" mode (`apply_look` / `set_show_armor`), freed on close.

**Wardrobe notice (existing saves).** `wardrobe_notice_pending()`: a loaded journey whose `GameState.wardrobe.notice_shown` is
false. `tick_wardrobe_notice(delta)` polls at 4 Hz (`WARDROBE_NOTICE_POLL` 0.25 s) and opens the card after
`WARDROBE_NOTICE_SAFE_SECONDS` (3 s) of **continuous** safe play: `wardrobe_notice_safe_now()` = gameplay input allowed, no fade,
no death / ending screen, **nothing in `overlay_layer`** (chapter cards, the Chapter Two card other modules add there), no boss,
and `Game.can_manual_save().ok` or standing in a safe zone. `show_wardrobe_notice()` marks it shown at once (it never returns,
whatever the answer; "Open the wardrobe" opens it). Switched off (`wardrobe_notice_enabled = false`) in headless runs and when any
of `NOTICE_OFF_ARGS` (`cams, shot-dir, shots, area, preview, player-demo, no-wardrobe-notice`) is on the command line;
`--ui-show=wardrobe_notice` shows it on demand.

**Focus after close.** `close()` defers `_focus_top()`, which focuses whatever panel is on top when it runs (a hotkey may have
opened another panel in the same frame, e.g. switching away from the wardrobe opened over the pause menu). Known quirk kept: a
gameplay hotkey from the wardrobe over the pause menu opens that panel with pause still underneath (like the controls overlay).

**Endings.** `show_ending()` (Chapter One, unchanged) and `show_chapter_two_ending()` (integration R14) share `_play_ending(params)`:
closes menus, cinematic HUD, `EndingScreen` (variant `"chapter_two"` for Chapter Two, owned by C9) on `overlay_layer`, and keeps
`_ending` set the whole time, so `_input`, hotkeys and the wardrobe notice are blocked exactly like the Chapter One ending. The
Chapter Two ending makes no music call (the director plays the celebration on `Events.chapter2_completed`). A second call while it
shows waits for the same ending. `Game._show_chapter_two_ending()` prefers it (fallbacks: `show_ending(variant)`, a bare
EndingScreen on `overlay_layer`, else the chapter card + ending line). Debug: `--ui-show=ending2`.

**Pause menu (B2 + R17).** The unstuck entry is per area: `static unstuck_label(area_id)` ("Return to the Haven" legacy,
"Return to safety" in Chapter Two areas, "Leave the trial" in `echo_trial`), `unstuck_tooltip`, `unstuck_spawn(area_id, player_state,
defaults)` (legacy results unchanged), `unstuck_target()` (uses `Game.return_point()` and only returns spawns the area registers).
In the Echo Trial the option leaves the trial back to its origin checkpoint (progress intact). The subtitle uses
`GameState.current_objective()`.

**Tracker (`hud/tracker.gd`, B11).** `static objective_view() -> {kind, header, title, text, hint, rows, parts, step_id, group,
optional, targets}` with `kind` = `legacy` (Chapter One chain until `chapter_one_complete`) | `pointer` ("The Ward Stone has something
new to say", or "The lantern road will keep" once `read_ward_ch2`) | `chapter2` (the current step; the three lamps shown together,
done ones ticked, any order) | `signpost` (after Chapter Two: one pending optional goal under **"SOMETHING TO DO"**, Chapter Two
goals first — lead decision R136 i) | `done` | `hidden`. The legacy "OPTIONAL GOALS" header never appears once Chapter One is
complete. `pending_targets(view)`, `is_at(t, area, pos, zone)`, `where_text(view, area, pos, zone)` (per-area "where to" line, also
for goals in another area). Quest banner: a line already queued or on screen is not repeated.

**Journal (B11).** Five tabs (child node names): **Story, Optional, Friends, Lore, Mastery**; `args.tab` / `select_tab(name)`
(aliases `TAB_ALIASES`: "goals" → story, "optional goals" → optional, "masteries" → mastery), `tab_names()`, `reopen(args)` switches
the tab when already open. Story: current objective + both chapters' progress (current chapter first). Optional: visible goals only,
grouped by chapter, pending before done, legacy free_play goals included. Lore: `LoreDB` (arachnophobia-aware), grouped by
`lore_chapter(id)` = `LoreDB.chapter_of(id)` (by source file: Tobin's annex notes are Chapter One although their ids start with
`lore_ch2_`; integration R24). Mastery: rank, XP to next, every rank reward, names from `ItemDB.mastery_track_info(track)` (R21).
Pages rebuild only when their content signature changes. The Expedition Board opens the `"expedition"` panel (§12); only when that
panel is not registered does it fall back to the journal with `{"tab": "optional"}` (`expedition_board.panel_args()`).

**Map (B11 + integration).** `MapView.map_kind(area_id)` → `"surface"` (the Woods drawing, unchanged and pinned by a test; a waygate
pin once `ch2_accepted`, lit after `ch2_waygate_repaired`) | `"reach"` (Hallowmere Reach: only DISCOVERED landmarks, arches — lit
ones glow, unlit ones once their district is known — and the waygate home) | `"rooms"` (manor, Works, annex: a list of rooms found,
from `MapView.ROOMS`) | `"none"` (the Below, trials: a message). **Room display names live only in `MapView.ROOMS`** (lead decision
R136 h; the annex names "Side-Door Landing", "Shift Lockers", "The Old Sump" and the alt name "Rooted Winch" are official).
**Festival roads**: once `ch2_read_festival_map` is set the Reach map draws the revealed roads from the layout's `MAP_ROUTES` (read
defensively), undiscovered branch districts get a nameless "?" pin, trees along known roads are cleared, and a road replaces the
dashed footpath it covers (`REACH_PATH_ROADS` links the first five footpaths to arrival/main/west/east/north roads; C1 keeps those ids
stable). Road lines are projected only when the map size changes. After "The Long Way Home" (`ch2_map_pins_upgraded`) objective pins
get a gold ring + star badge (steady glint, no flashing). `map_panel.gd`: args `{"area"}`, `show_area(id)`, `reopen(args)`, an
outdoor toggle (Woods ↔ Reach) once the Reach was visited, `goal_marks(map_area)`, `way_to(target_area, map_area)` (a goal in another
area is marked at the way there: waygate, manor door, Bellhouse stair). Map glyphs `map_lantern / map_glasshouse / map_pumpkin /
map_candle / map_manor / map_bell` are in `icon_factory.gd` (R20). Mastery map rewards (Wayfinding 2 resource pins, Wayfinding 4 cache
hints) read `Mastery.known_spots(area)` / `Mastery.cache_hints(area)` (R22); a Bramblewatch label appears on the Woods map once
`c1x_bramblewatch` is discovered (R23).

**HUD (integration).** Health bar shows Pebble's transient shield from `Events.player_shield_changed` (pale segment, no flashing;
bar max = `Stats.effective_max_hp()` when larger; R11). The build bar shows a scrolling window over every placeable with key caps and
undo / face / storey state (R12). Underground look (tint + lantern day dial) for every underground area through
`UiUtil.is_underground_area(area)` = `companion_logic.UNDERGROUND_AREAS` (below, tobin_annex, hushed_works; R13). Companion badge:
skill cooldown ring + ready flash (B4, `reduce_flashing` respected). Settings rows (R10): gameplay tab `companion_auto_attack`,
`companion_autocast`, `seasonal_decor`; comfort tab `high_visibility_cues`, `timing_assist` (kept by a settings reset).

**QA telemetry (B11, read-only).** `progress_snapshot()` (refreshed every `PROGRESS_INTERVAL`, merged into each line) adds keys
`area_info` {area, zone, safe, map, discovered}, `chapter2` {available, active, finished, chapter, current, title, done}, `tracker`
{kind, title, step, targets}, `optional` {done, pending, done_count}, `equipment`, `companion_skills` (per befriended companion:
skill, cooldown, ready_at, left, ready, active, mode[, node]) and `music` {cue, director}; message kinds `quest` (Chapter Two step
started/completed, optional goal completed), `discover`, `music`, `skill`, `equip`. The QA bot's Chapter Two scenarios read them
(`tools/qa/ch2/`, pass 2 D11).

## 12. Wave D + integration pass 2 — as built

Code headers are the source of truth (`ui_root.gd`, `autoload/settings.gd`, `panels/controls_panel.gd`, `ui_util.gd`,
`panels/expedition_panel.gd`, `panels/music_box_panel.gd`, `hud/tracker.gd`, `widgets/map_view.gd`, `panels/map_panel.gd`,
`src/world/trial/trial_entry.gd`, `src/world/story_ch2/onboarding_hints.gd`). Decisions: `docs/ch2/INTEGRATION_WAVE_D.md`.

**New panels (P33).**
| panel | script | FULLSCREEN (pauses) | GAMEPLAY_PANELS | opened by | args |
|---|---|---|---|---|---|
| `"expedition"` | `panels/expedition_panel.gd` (D2) | yes | yes | the Expedition Board (`expedition_board.gd`: `target_panel()`, `expedition_args()`) | `{"template": id (preselect), "source": structure id}` |
| `"music_box"` | `panels/music_box_panel.gd` (D3) | **no** - a paused tree silences the preview; the world keeps running (like the Friends menu) and the panel closes itself when Krystal is hurt (`Events.player_damaged`) or its box is dismantled | yes | the Music Box furnishing (`src/building/structures/music_box.gd`) | `{"uid", "source": the box node}` (also opens without args, e.g. the every-panel test: no house check then) |
The expedition panel: left the three routes (difficulty in words AND lantern pips, never colour alone; locked ones greyed with the
reason), right the chosen route before starting (blurb, difficulty, rough length, stops in order, who may be met - arachnophobia-aware
names -, the reward TYPES, completions); bottom "Set out" (`Expeditions.start`), while a run is going its progress line, "Lantern
Road to <arch>" when that arch is lit (`travel()`), "Set it aside" (two presses; in the cache phase the confirm says the cache stays
closed) and "Optional journal". No countdowns or streaks. Rebuilt on `Events.objectives_changed`. The music box panel lists the
discovered songs by title with where each belongs, Play / Stop, a Favourite toggle per song, "Now playing", a note when the sound is
muted and a found / favourites count; "That song can't play right now." when higher music has the director. Text only: works with
the sound off.

**Hotkeys and bindings (D02 / D03).** `ui_root.HOTKEYS` gains `"wardrobe": "wardrobe"`: Settings action `wardrobe`, default **O**
(free: not Q/E, which switch wardrobe categories, not the build keys), rebindable; it follows the pause-menu Wardrobe's rules
(full-screen, pauses, only in ordinary play). The build-mode keys are Settings actions too: `build_undo` Z, `build_recolor` P,
`build_variant` N (REBINDABLE rows "Build: Undo last piece", "Build: Recolour", "Build: Pumpkin face"; `build_mode.gd` prefers the
InputMap action, `FALLBACK_KEYS` stay as the safety net). HUD tokens in `UiUtil.TOKEN_ACTIONS`: `{wardrobe}`, `{undo}`, `{recolor}`,
`{variant}` (the onboarding hints switch to them automatically). The F1 controls overlay (`controls_panel.gd`) groups Moving / Doing
/ Menus (with Wardrobe) / Building (build, rotate, dismantle, undo, recolour, pumpkin face) in three columns. A settings file saved
before these actions existed gets their default keys (nothing is written back until the player saves settings).

**Tracker and map (P35 / P36).** `tracker.objective_view()` gains kind `"expedition"` (`Expeditions.tracker_view()`), used ONLY
where the view would otherwise be `signpost` / `done` / `hidden` - never over a chapter, legacy or pointer step; `where_text()` uses the
view's `"where"`. The Reach map draws a running expedition's route (`MapView.expedition_pins(area)`: numbered paper pins, a candy pin
for the cache, done stops faded and ticked, a steady ring on the current one - no flashing), `exp_*` ids resolve through
`MapView.expedition_disc(id)` / `Expeditions.place_disc(id)`, and `map_panel` always marks the current stop / cache (one extra
"Expedition:" line when another objective owns the card) with a legend row "Expedition stop". Nothing is drawn without a run.

**Echo stones (D1 + pass 2).** `trial_entry.gd` (manor ballroom, Bell Throat) and the Below's stone (`below_world.gd`, P28) open the
same confirm: `echo_trial.menu_text(id)` = title, memory text, record ("Cleared n times - best time m:ss" / "Not cleared yet.") and
what a clear leaves (the first-clear pattern, else "Each clear leaves a little: ..."), buttons "Enter the echo" / "Not now". A won
repeat clear toasts "The echo's gift waits for you back at <origin_name>." and the arrival there "The echo's gift: ..." (L08;
`data/trials.gd` `origin_name`). A refusal says "The echo stays quiet while a fight is on." only while a boss is active, else "The echo stays quiet
for now." (P30). Pause "Leave the trial" inside a trial (R17).

**Onboarding hints (D4 + pass 2 P49).** `onboarding_hints.gd` emits once-per-save tips through `Events.hint` (the HUD hint card shows
them one at a time). Pass 2: one generic `ob_echo_trial` tip for every echo stone (armed on arrival where a won fight's stone stands,
live when Velour or the Choir falls; dropped once any trial has a clear) and `ob_expedition_board` names the Lanternwake Expeditions.
Pacing unchanged until a real play session (P50).

## Extension recipes

*Status after Waves B/C:* (a) is built as `screens/creation_screen.gd`, (b) as `panels/wardrobe_panel.gd` + the equipment
column of the inventory panel (B3), (c) as the companion panel skill row / badge ring (B4, `get_skill_state()`), (d) as the
five journal tabs + `tracker.objective_view()`, (e) in `ward_stone.gd` (A3), (f) as the furnace queue inside the crafting panel
(`Game.open_panel("crafting", {"station": "furnace", "uid": uid})`, not a separate panel), (g) as `MapView.map_kind()` + the
per-area map. The recipes stay for history; §11 describes the current code.

**(a) "Meet Krystal" creation screen (title-side, cancel-safe).**
1. New `src/ui/screens/character_screen.gd` extending panel_base: `signal finished`, `var accepted := false`,
   `var profile := {}`. Emit `finished` from `on_close()` (the comfort pattern), because the title's Esc path calls
   `_close_panel()` → `on_close()` directly without `request_close`. Set `window_min` ≤ 1920×1080 minus margins.
2. Preview: a `SubViewportContainer` (stretch=true, ~560×720) → `SubViewport` with `own_world_3d = true` (otherwise it renders
   the diorama's world), `transparent_bg = true`, `render_target_update_mode = UPDATE_WHEN_VISIBLE`, `msaa_3d` 2x. Inside it,
   put a Camera3D (the default cull mask includes Krystal's render layer 1<<11), a DirectionalLight3D, a WorldEnvironment, and
   `preload("res://src/player/krystal_avatar.gd").new()` → `play_anim("idle")`, rotated in `_process` (the panel inherits
   ALWAYS processing). Drag or arrow keys to rotate, handled in `handle_key`.
3. `title_screen._on_new_game()`: after `if not c.accepted: return`, open the creation screen with `_open_panel(cs)`,
   `await cs.finished`, and `if not cs.accepted: return` (or loop back to comfort). Only then `_busy = true`, fade, and start.
4. Persisting: `GameState.new_game()` runs inside `Game.new_game()` after the title is gone, so pass the profile in. That needs
   integrator changes: `Game.new_game(profile := {})` applying `GameState.player_name` plus new appearance fields
   (GameState/save format are foundation). *(Resolved in Wave B: the avatar's `_bake_cache` is keyed by content incl. colour,
   see player_avatar.md §7, so a preview and the player never share recoloured meshes.)*
5. Update `_debug_show("newgame")` and add a title test for Esc on the creation screen (no game started, `_busy` false).
   If it should be reachable in-game too, register it in `PANELS` + `FULLSCREEN`.

**(b) Wardrobe / equipment / stats panel.** Add `panels/wardrobe_panel.gd` (panel_base). Register `"wardrobe"` in `PANELS`,
`FULLSCREEN`, `GAMEPLAY_PANELS`. For a hotkey, the integrator adds an action to `Settings.DEFAULT_BINDINGS` and
`REBINDABLE`. Then add it to `ui_root.HOTKEYS`, the "Menus" group in `controls_panel.GROUPS`, and `UiUtil.TOKEN_ACTIONS` if hints mention it.
Equipment slots can reuse `widgets/item_slot.gd` and `slot_controller.gd`: any RefCounted with the Inventory API
(`get_slot/set_slot/remove_from_slot/size`) works, and `UiUtil.move_stack` is the transaction. Add slot type
filtering in a panel callback. Reuse the (a) preview widget. Add an "Equip" label in `inventory_panel.use_action()` (:200, it is tested) and stat lines in
`UiUtil.item_stat_lines()` (it special-cases `lantern`). Equipment state itself belongs in GameState (integrator).

**(c) Companion skill cooldowns.** Agree on a duck-typed companion node API, e.g. `get_skill_state() -> {id, name,
cooldown_left, cooldown_total, ready}` (read from GameState/game time, never ticked by the UI).
Companion menu (`panels/companion_panel.gd`, not fullscreen, so the world runs): add a skill row in `_build()` (:24) and update it
in `_process` at a throttle of about 0.1 s. Don't rebuild the rows. It already closes on `Events.player_damaged`.
HUD badge (`hud/companion_badge.gd`): draw a radial sweep in `_draw_portrait()` (:208) from a cached fraction and call `portrait.queue_redraw()` only
when the fraction changes by ≥1 % (add a `_process` with a timer). The badge follows `GameState.active_companion`.
The journal Friends tab (:229) can show the skill blurb statically. If a 4th companion is added, see Risks (width).

**(d) Optional-goals tab and Chapter Two tracker.** Journal: in `_build()` add a child container **named** "Optional"
(the tab title and `args.tab` key come from the node name). Build it in `refresh()` and on `objectives_changed`. Replace the hard-coded
"Chapter One/The Dimming Ward" (:140) and the progress count over `QuestsData.STEPS` with a per-chapter filter (e.g. a
`chapter` key on steps). `handle_key` cycling adapts automatically. Tracker: keep the single `refresh()` path and signature.
For a second "optional" card, add another pooled row set under a separate header. Include its data in `sig` or it won't update.
The header already switches on `step.optional`. Keep `step_string()` for all text (arachnophobia alt text).
New hint tokens must be in `TOKEN_ACTIONS` (`test_every_quest_hint_token_is_known`).

**(e) Ward Stone 2-option choice.** In `ward_stone.gd interact()` (the world module), set `_busy = true` and then:
```gdscript
var pick := "stay"
if Game.ui != null and Game.ui.has_method("confirm"):
	pick = await Game.ui.confirm("The Lantern Road", "…", [["follow", "Follow the lantern road", "AccentButton"], ["stay", "Stay a little longer", ""]])
if pick == "follow": …   # "cancel" (Esc/X/area change) = stay
_busy = false
```
It pauses the world and pushes UI. Don't call it during a fade or cutscene transition (hidden under `Fade`). Check
`is_instance_valid(self)` after the await. For per-option sub-text, extend `confirm_dialog._build` with an optional 4th element
(tooltip or sub-label) guarded by `b.size() > 3`; that stays backward compatible.

**(f) Furnace/loom station panel with a queue.** Add `panels/station_panel.gd` with args `{"uid", "station"}` and a `reopen(args)` that
closes or refreshes when the uid differs (companion pattern). Register it in `PANELS`. Decide FULLSCREEN deliberately: fullscreen
pauses the tree, so a game-time queue will not advance while it is open. Queue state must live in GameState (integrator),
keyed by the structure uid. Show progress from state in a throttled `_process`. Use `UiUtil.craft_check/craft` for
ingredient checks, and reuse `crafting_panel._ingredient_summary` (static). The structure's `interact` calls
`Game.open_panel("station", {...})`. If furnace recipes should also appear in the Crafting panel, add the station to `StationOrder`
(crafting_panel.gd:7) and the tab list (:43). Otherwise they are **invisible even under "All"**, because `_recipes()`
iterates StationOrder only. Give `ItemDB.station_name` a name in `data/recipes.gd STATIONS`. New item icons need drawings
(§7 and Risks).

**(g) Map support for new areas.** `map_panel.setup/_build` branch on `Game.area_id`; add a branch per new area (or a
dict `area_id → builder`). Keep `"below"`. Make `MapView` data-driven: move `H`, `REGIONS`, `ICONS`, `PATHS`, the stream and
pond and mine-cliff drawing behind a `layout` object (landmarks with `{name, pos, radius}`, `half_extent`) and pass
`half_extent` to `UiUtil.world_to_map`. Guard the hard-coded `LANDMARKS["mine_mouth"]` and `["pond"]` lookups.
New landmark stickers go in `EXTRA_ICONS` plus the `_compose` match. Unknown ids fall back to "unknown". The tracker's
"Head to" and `_player_at`, plus the journal and map `landmark_name()`, read `Layout.LANDMARKS` and are gated on `area_id == "surface"`.
Generalise them to look up the current area's landmarks. Also fix `pause_panel.unstuck_spawn()` (:100): any non-"below" area
returns Haven spawns and the label says "Return to the Haven". Update `hud.gd`'s below tint if needed.

## Risks

- **Tests that enumerate registries:** `test_every_panel_builds_and_closes` opens **every** `PANELS` entry (except comfort)
  with `args.get(name, {})` and requires a laid-out window that fits the screen, so new panels must build with empty args.
  `test_all_panels_fit_the_virtual_canvas` requires combined min size ≤1920×1080 and the ribbon on-screen. A 4th Friends
  card (4×440 + gaps + margins ≈ 1920) or more map "Places" rows can fail it. `test_every_item_icon_id_has_a_drawing`
  requires every `ITEM_ICONS` id to be used by an item and every item icon to have a drawing. `test_portraits_and_glyphs`
  requires `portrait_<id>` for every creature (add it to `PORTRAITS` + `_compose`). `test_pure_panel_helpers` pins
  `unstuck_spawn`, `use_action`, `continue_text`, and `unmet_hint` length >10. `test_ui_settings` checks that schema keys
  exist in DEFAULTS and that REBINDABLE actions are defined. `test_default_bindings_have_no_conflicts` covers new hotkeys.
  The title tests drive `_on_new_game` and `_panel` directly.
- **Saves:** the UI persists nothing itself except GameState flags `"hint_<id>"` (renaming hint ids re-shows hints) and
  Settings `comfort_confirmed`. Title `continue_text` reads save `meta` keys `day, step, step_title, play_seconds`; renaming
  step ids breaks the resolved title, which falls back to `step_title`.
- `order`, `panels` and the `_paused_by_ui` bookkeeping assume each panel pushes and pops exactly once. Don't call
  `Game.push_ui/set_paused` from panels.
- Hard-coded Chapter One text: `Game.new_game` chapter card and the ui_root debug card (the title footer, journal and ending
  screen now follow the chapter, §11). New Chapter Two panels must also pass `test_every_panel_builds_and_closes` with empty
  args (the wardrobe does) and the layout tests (Meet Krystal min 1660×877, wardrobe 1816×899, journal 1520×≤835, Reach map 1663×944).
- Hotkey panels and `open()` ignore the mode for direct calls. `_hotkey` requires `Game.mode=="playing"`, so new modes
  (e.g. a "creation" mode) disable hotkeys.
- Lambdas connected to `Events` inside **static** builders leak unless they go through `Kit.listen`.
