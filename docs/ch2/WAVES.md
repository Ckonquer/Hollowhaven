# Chapter Two build waves (module ownership)

Each wave's modules edit ONLY the files listed as theirs. Anything else they need is reported to the
integrator (lead) in their final report, who applies it between waves. New files inside a module's own
directories are always allowed. Tests: `game/tests/unit/test_<module>_*.gd`.

## Wave A — foundation (M0/M1) + music composition (independent)
| module | owns (edit) | delivers |
|---|---|---|
| A1 core-save | autoload/game_state.gd, autoload/save_system.gd, src/core/inventory.gd, src/core/chapter_log.gd (new), src/core/optional_log.gd (new), data/quests_ch2.gd (new), data/optional_goals.gd (new), tests/fixtures/saves/* (new), tests/unit/test_save_v2_*.gd, docs/SAVE_MIGRATION.md | schema v2, migration, upgrade backup, future-version refusal, capacity/orphans, ledger, chapter-two quest layer, optional tracker, 12-fixture migration matrix + integrity diff tool |
| A2 data | data/items.gd, data/recipes.gd, data/structures.gd, data/enemies.gd, data/appearance.gd (new), data/equipment.gd (new), data/companion_skills.gd (new), data/mastery.gd (new), autoload/item_db.gd, src/ui/icon_factory.gd (new icon shapes only), tests/unit/test_data_ch2_*.gd | full catalogue of MP §16 with icons + obtainability / dependency validation |
| A3 flow & areas | autoload/game.gd, scenes/*.tscn (new), src/world/areas_ch2/* (new skeleton area scripts), data/hallowmere_layout.gd (new), src/world/surface/ward_stone.gd, src/world/surface/waygate.gd (new), src/ui/screens/choice_dialog.gd (new), tests/unit/test_flow_ch2_*.gd | AREAS, spawns, safe-save areas, travel, Lantern Road, Ward Stone inscription + choice, waygate repair, round-trip test |
| A4 music-director | autoload/audio.gd (music part), src/audio/music_director.gd (new), data/music.gd (new), tests/unit/test_music_*.gd | data-driven selector, shuffle bags, hysteresis, priorities, crossfades |
| A5-A8 composers | tools/audio/music2/* (new), game/assets/audio/music/*.ogg (new) | 22 new compositions (OGG Vorbis via soundfile), manifest rows |

## Wave B — expression, companions, progression, Chapter One upgrade (M2-M4)
Each module was built, then independently reviewed (the reviewer fixed inside the module's files). Paths under `game/`.
| module | owns (edit) | delivers |
|---|---|---|
| B1 avatar-look | src/player/krystal_avatar.gd, src/player/avatar/* (new builders: hair, garments + skirt rig, accessories + capes/wings, armor, look colours, kit), tests/unit/test_player_avatar.gd (only intentional changes), tests/unit/test_avatar_look_*.gd | avatar built from `GameState.appearance` in slot units; LEGACY_LOOK = the Chapter One Krystal exactly; content-keyed (colour-aware) bake cache; general spring chains, skirt/cape rigs, per-look roll hull; armor display |
| B2 appearance-ui | src/ui/ui_root.gd (Wave B owner of the UI root), src/ui/title_screen.gd, src/ui/panels/pause_panel.gd, src/ui/screens/creation_screen.gd (new "Meet Krystal"), src/ui/panels/wardrobe_panel.gd (new), src/ui/widgets/avatar_preview.gd (new), **src/building/structures/wardrobe.gd** (new; see ownership decisions), tests/unit/test_ui_appearance_*.gd | New Game flow with Meet Krystal, wardrobe panel + presets, one-time wardrobe notice, per-area "Return to safety" |
| B3 equipment-stats | src/core/stats.gd (new), src/player/player.gd, src/player/player_logic.gd, src/player/player_health.gd (new), src/combat/health.gd, src/combat/combat.gd, src/combat/projectile.gd (new, shared), src/world/common/resource_node.gd, src/ui/panels/inventory_panel.gd, src/ui/widgets/item_slot.gd, tests/unit/test_stats_*/test_equipment_*/test_wand_*.gd | Stats layer, damage order (i-frames → reduction → shield → Health), shield, slows, wand + pooled projectile, tool tiers, equipment slots in the inventory, area-aware player checks |
| B4 companion-combat | src/companions/* (all), data/creatures.gd (additive only), src/ui/panels/companion_panel.gd, src/ui/hud/companion_badge.gd, src/ui/panels/controls_panel.gd, src/ui/ui_util.gd (only the "skill" hint token), src/building/structures/companion_nook.gd (new), src/world/surface/c1x/courage_lantern.gd (new), tests/unit/test_companions_*.gd | basic attacks, signature skills with one saved cooldown, perks, modes, obstacle-aware navigation, area classes + doorsteps, Mochi's courage, home life |
| B5 crafting-stations-mastery | src/crafting/*, src/farming/*, src/core/mastery.gd (new), src/building/structures/{workbench,storage_chest,furnace}.gd, src/ui/panels/crafting_panel.gd, src/ui/panels/storage_panel.gd, tests/unit/test_crafting_*/test_farming_*/test_mastery_*/test_station_*.gd | special recipes (backpack 40/48, patterns, dyes), chest crafting within `CHEST_RADIUS` 18 m, furnace queue, kitchen, chest 20→40 upgrade, new crops, mastery tracks + legacy credit |
| B6 building | src/building/* EXCEPT structures/{workbench,storage_chest,furnace,companion_nook,wardrobe}.gd, data/structures.gd (additive field tweaks), src/world/surface/surface_world.gd (ONLY is_safe_zone / Haven safe radius), data/world_layout.gd (ONLY BUILD_AREA "extra"), autoload/game.gd (ONLY the building attach condition), tests/unit/test_building_*.gd | two storeys + stairs, the new pieces, recolour, undo, pumpkin faces, the bigger Haven, the Reach outpost |
| B7 c1x-surface | src/world/surface/c1x/{tailor_cache,bramblewatch,meadow_patch,sap_stumps,moth_pocket,seasonal_decor,common}.gd (new), data/c1x_layout.gd (new), tests/unit/test_c1x_*.gd | Chapter One optional surface content (Tailor's Cache, Bramblewatch + Elder arena, meadow, sap stumps, moth pocket, seasonal decor) |
| B8 ch1-enemies | src/enemies/enemy_base.gd (ADDITIVE hooks only), src/enemies/enemy_factory.gd (registering), src/enemies/{brambleback,lantern_moth,hollow_drudge,brood_skitter,knotted_elder}.gd + *_visual.gd, src/enemies/telegraph_fx.gd (new), tests/unit/test_enemies_ch1x_*.gd | new Chapter One enemies + the shared mechanics (charge, leap, projectile, pulse, ground marks, can_be_hit_by, stagger, slows) |
| B9 matron-trial | src/enemies/weaver_boss.gd, weaver_visual.gd, boss_brazier.gd, src/enemies/boss_hazards/* (new), src/world/areas_ch2/echo_trial.gd, src/world/below/below_world.gd (ONLY the trial entry + arena hooks), tests/unit/test_enemies_boss_*.gd | three-phase Weaver Matron (+ arachnophobia alternates), the Echo Trial instance |
| B10 tobin-annex | src/world/areas_ch2/tobin_annex_world.gd (the scene's script; the brief said tobin_annex.gd), src/world/annex/* (new), src/world/surface/c1x/tobin_door.gd (new), data/lore_ch2_annex.gd (new), tests/unit/test_annex_*.gd | Tobin's Lost Shift: 3 rooms, side door, shortcut hatch, notes |
| B11 journal-map-ui | src/ui/panels/journal_panel.gd, src/ui/hud/tracker.gd, src/ui/hud/quest_banner.gd, src/ui/panels/map_panel.gd, src/ui/widgets/map_view.gd, src/qa/qa_telemetry.gd (read-only additions), tests/unit/test_ui_journal_*/test_ui_map_*.gd | combined tracker, five journal tabs, per-area maps + festival roads, telemetry keys |

## Wave C — Hallowmere Reach, Moonveil Manor, Hushed Works (M5-M6)
| module | owns (edit) | delivers |
|---|---|---|
| C1 reach-world | src/world/areas_ch2/hallowmere_reach_world.gd, src/world/reach/* EXCEPT districts/* and the west/east/manor subfolders, data/hallowmere_layout.gd (additive), data/lore_ch2_reach.gd, src/world/surface/sky.gd (ONLY a backward-compatible tint), shaders surface_{terrain,grass,flower}.gdshader (ONLY the terrain_samples vec2 change), tests/unit/test_world_reach_*.gd | the Reach base region: terrain, forest edge, brook, Commons, Conservatory, Bellhouse, arches, roads, region loader |
| C2 reach-west | src/world/reach/districts/{orchard,pools,candleyard}.gd, src/world/reach/west/*, data/reach_west.gd, tests/unit/test_reach_west_*.gd | Pumpkintide Orchard, Thimblebrook Pools, the Candleyard, the turning pumpkin |
| C3 reach-east | src/world/reach/districts/quarry.gd, src/world/reach/east/*, data/reach_east.gd, tests/unit/test_reach_east_*.gd | Ashbell Quarry: terraces, winch, crystal shelf, Warden arena |
| C4 manor | src/world/reach/districts/manor_grounds.gd, src/world/manor/*, src/world/areas_ch2/moonveil_manor_world.gd, data/manor_layout.gd, data/lore_ch2_manor.gd, tests/unit/test_manor_*.gd | Moonveil Manor grounds + 5-space interior, candle puzzle, velvet scraps, the Empty Waltz, Velour arena |
| C5 ch2-enemies | src/enemies/{pumpkin_mimic,patchwalker,velvet_wing,bellcap_sentry,borrowed_wisp,quarry_warden}.gd + *_visual.gd, src/enemies/enemy_factory.gd (ONLY registering these), tests/unit/test_enemies_ch2_*.gd | Chapter Two ordinary enemies + the Quarry Warden elite |
| C6a count-velour / C6b crossing-matron / C6c borrowed-choir | src/enemies/count_velour.gd + velour_visual.gd + velour/*; crossing_matron.gd + crossing/*; borrowed_choir.gd + choir/*; enemy_factory.gd (ONLY registering their id); tests/unit/test_boss_{velour,crossing,choir}_*.gd | the three Chapter Two bosses (built and reviewed after the Wave B/C integration pass, which could not touch their files; integrated in pass 2) |
| C7 works-upper | src/world/areas_ch2/hushed_works_world.gd, src/world/works/* EXCEPT rooms_deep.gd and deep/*, data/works_layout.gd, data/lore_ch2_works.gd, data/horror_events.gd (additive), src/horror/* (additive), autoload/game.gd (ONLY DIRECTOR_AREAS + director setup), tests/unit/test_works_*.gd (not works_deep) | the Hushed Works area, rooms 1-8, the three lines, the Works horror director |
| C8 works-deep | src/world/works/rooms_deep.gd, src/world/works/deep/*, data/works_layout_deep.gd, tests/unit/test_works_deep_*.gd | rooms 9-14: winch (+ cage), Crossing arena, Wrong Landing, Borrowed Porch, Bell Throat, Choir Vault |
| C9 story-ending | src/ui/screens/ending_screen.gd (Chapter Two variant), src/ui/screens/chapter_card.gd, src/world/story_ch2/*, data/lore_ch2_story.gd, data/quests_ch2.gd, data/optional_goals.gd (only the cross-area goals), data/sources.gd (only the matching chapter_log / optional_log REWARDS entries), autoload/game.gd (ONLY chapter_two_rewards() and the presentation part of complete_chapter_two), src/world/surface/ward_stone.gd (ONLY the Chapter Two homecoming lines and Celebrate), tests/unit/test_story_ch2_*.gd | story glue, homecoming, celebration, Chapter Two ending, cross-area activities |

### Ownership decisions (lead)
* **`src/building/structures/wardrobe.gd` belongs to the appearance UI module (B2)**, which wrote it (integration R133). Spec §9
  once listed it under the building module; the building module only maps `wardrobe` / `vanity_mirror` to it in
  `structure_factory.gd` `LAZY_SCRIPTS` and must not overwrite it. (Spec §9 text updated.)
* `companion_nook.gd` (B4), `furnace.gd` / `workbench.gd` / `storage_chest.gd` (B5) likewise live in `src/building/structures/` but
  belong to those modules; `pumpkin_lantern.gd`, `music_box.gd`, `expedition_board.gd`, `thread_veil.gd` belong to building (B6)
  unless a later wave assigns them (Wave D: D2 owns `expedition_board.gd`, D3 owns `music_box.gd`).
* Shared foundation files (`autoload/`, `data/`, `src/core/`) stay integrator-owned; the narrow exceptions are the ones in the
  tables ("ONLY ...").

### Integration pass after Waves B/C
The lead collected every integrator request of the B/C reports into one plan (requests R01-R136, deferred D01-D11, done/obsolete
X01-X19) and applied it with twelve parallel fixer groups G1-G12, each owning disjoint files. Decisions and the deferred list:
`docs/ch2/INTEGRATION_WAVE_BC.md`; the conventions it produced are in `docs/ARCHITECTURE.md` ("Chapter Two conventions") and the maps.

## Wave D — variety & replay (M7)
Built, then independently reviewed, like the earlier waves. Paths under `game/`.
| module | owns (edit) | delivers |
|---|---|---|
| D1 echo-trials | data/trials.gd (new: `TRIALS`, `FIRST_REWARDS`, `repeat_items`, `format_time`), src/world/trial/* (new: velour_trial.gd, choir_trial.gd, trial_entry.gd, trial_fx.gd), src/world/areas_ch2/echo_trial.gd, src/world/areas_ch2/moonveil_manor_world.gd (ONLY `_place_echo_trial`), src/world/areas_ch2/hushed_works_world.gd (ONLY `echo_entry` / `_place_echo_trial`), tests/unit/test_trials_*.gd | Echo Trials for Count Velour (Gallery copy with real ward candles) and the Borrowed Choir (rotated vault copy with real anchors / resonators), echo stones in the manor ballroom and the Bell Throat, the trial menu (record, best time, reward), the trial-scoped ledger |
| D2 expeditions | data/expeditions.gd (new), src/expeditions/* (new: expeditions.gd, expedition_runner.gd, expedition_beacon.gd, expedition_cache.gd), src/ui/panels/expedition_panel.gd (new), src/building/structures/expedition_board.gd, tests/unit/test_expeditions_*.gd | three hand-authored Lanternwake Expeditions through the Reach (Orchard Patrol, Quarry Circuit, Manor Afterglow), saved runs in `GameState.extra["expeditions"]`, ribbon lantern, end cache |
| D3 music-box | src/audio/music_box.gd (new), src/ui/panels/music_box_panel.gd (new), src/building/structures/music_box.gd, src/audio/music_selector.gd (ONLY the "musicbox" preview context + favourites weighting), src/audio/music_director.gd (ONLY preview wrappers + favourites), tests/unit/test_music_box_*.gd | the Music Box: discovered safe-area songs, one-pass previews at priority 40, favourites (bounded extra weight in the Haven rotation), `GameState.extra["music_box"]` |
| D4 docs-hints | src/world/story_ch2/onboarding_hints.gd (new), tests/unit/test_onboarding_{hints,text}.gd, docs/player/How to Play.txt, docs/player/Chapter Two - What's New.txt (new), README.md, GAME_SPEC.md (Chapter Two section) | once-per-save onboarding tips for the new systems, the player update note |

### Integration pass 2 (after Wave D)
The lead collected every integrator request of the C5 / C6a-c / D1-D4 build and review reports (plus the pass-1 deferred list
D01-D11 and the follow-ups F01-F04) into one plan of 76 requests (`L` = lead decisions, `D` = pass-1 deferred, `F` = pass-1
follow-ups, `P` = new requests) and applied it with ten parallel fixer groups, each owning disjoint files:
| group | owns (edit) |
|---|---|
| G1 enemies | src/enemies/{enemy_base, telegraph_fx, pumpkin_mimic, patchwalker, velvet_wing, bellcap_sentry, borrowed_wisp, quarry_warden, knotted_elder, borrowed_choir, crossing_matron}.gd, enemies/choir/choir_rings.gd, enemies/crossing/crossing_rules.gd, enemies/debug/combat_sandbox.gd, data/enemies.gd + their tests |
| G2 boss arenas & world hooks | moonveil_manor_world.gd, count_velour.gd, works/deep/{crossing_arena, lantern_anchor}.gd, reach/east/warden_arena.gd, data/works_layout.gd + their tests |
| G3 echo trial flow | echo_trial.gd, src/world/trial/{trial_entry, velour_trial}.gd, data/trials.gd, below_world.gd + the trial tests |
| G4 trial patterns & reward catalogue | data/{appearance, recipes, sources, unlocks}.gd, src/player/avatar/accessory_builder.gd + their tests |
| G5 expeditions surfaced | src/expeditions/*, data/expeditions.gd, expedition_panel.gd, expedition_board.gd, map_view.gd, map_panel.gd, hud/tracker.gd + their tests |
| G6 UI shell & input bindings | ui_root.gd, autoload/settings.gd, controls_panel.gd, ui_util.gd + their tests |
| G7 session wiring & music data | autoload/game.gd, data/music.gd, music_selector.gd, music_box.gd + their tests |
| G8 story & progression data | src/core/chapter_log.gd, data/quests_ch2.gd, src/core/mastery.gd + their tests |
| G9 docs, hints & packaging | the docs, onboarding_hints.gd + its tests, tools/build_release.ps1 |
| G10 `.uid` files | new `*.gd.uid` only, run last (one `--import`) |
Decisions and outcomes: `docs/ch2/INTEGRATION_WAVE_D.md` (the record) and `docs/ch2/INTEGRATION_PASS2.md` (each group's own notes).

## Wave E — release QA (M8)
(Details are written when the wave starts; see git history of this file.)
