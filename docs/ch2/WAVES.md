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
## Wave C — Hallowmere Reach, Moonveil Manor, Hushed Works (M5-M6)
## Wave D — variety & replay (M7), Wave E — release QA (M8)
(Details are written when each wave starts; see git history of this file.)
