# Integration pass 2 - decision record

Each fixer group appends its own section (append only; never rewrite another group's section).

## G8 Story & progression data (quest display rows, mastery encounter flags)

Files: `game/src/core/chapter_log.gd`, `game/data/quests_ch2.gd`, `game/src/core/mastery.gd`, tests
`test_save_v2_chapter_log.gd`, `test_story_ch2_data.gd`, `test_mastery_core.gd`, new `test_save_v2_chapter_log_display.gd`.

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| F03 (R38) | done | ChapterLog supports display-only objectives: an objective with `"display": true` is listed by `check_objective()` / `objective_status()` with its real done state (the row dict carries `"display": true`; rows without it keep their exact old shape), while `step_done()` (and so `has_pending_completion()` and `evaluate()`) ignores it. A step needs at least one non-display objective to complete; a step of display rows only never completes. New static `ChapterLog.is_display_objective(o)`. `ch2_quarry` now lists "Calm the Quarry Warden" (`hr_warden_defeated`, display) and "Mend the mineral winch" (`ch2_winch_repaired`, display) before "Light the quarry lamp"; completion still reads `ch2_quarry_lamp_lit` alone, so a save with the lamp lit and no Warden / winch flag never stalls (tested through a real save round trip). The data header documents the key and moves the two quarry flags out of "flags no step reads". Honoured by ChapterLog only: `optional_log.gd` does not read `display` (no optional goal uses it). |
| P05 | done | `Mastery.ENCOUNTER_FLAGS` gains `hr_warden_defeated -> quarry_warden` and `ch2_velour_defeated -> count_velour`, the bosses' own `Events.boss_defeated` ids (`quarry_warden.gd BAR_ID`, `count_velour.gd BOSS_ID`), so the flag route and the signal route are ONE encounter (`award()` dedupes on `encounter:<id>`). The test reads the ids and flag names from the owner scripts (no drift) and checks both orders plus repeats. Note: the Warden stand-in / Velour fallback (only when the boss script is missing) now also pays the one encounter xp, like any other flag route. |
| P56 | done | `data/quests_ch2.gd` header: `ch2_trials_open (step ch2_routes_restored): a story marker; nothing gates on it - each echo trial opens when its boss is defeated (lead decision, pass 2).` No data / logic change (`story_ch2.STEP_FLAG_REPAIRS` keeps repairing it). |

Tests (headless, 2026-09-28): `parse_all` 1/1 pass; `chapter_log` (both chapter-log files) 19/19; `story_ch2_data` 7/7;
`mastery_core` 17/17 (new `test_ch2_boss_flag_and_signal_are_one_encounter`). Wider run (mastery, warden, velour, manor, reach_east,
story_ch2, trials, journal_tabs, optional_log, core_quests, reach_west_layout, ch2_rewards, annex_flow): 345 tests, 4 failed, all in
`test_boss_velour_manor` / `test_manor_progress` ("the resident appears"): caused by another group's in-flight RESIDENT_DELAY change in
`moonveil_manor_world.gd`, not by this group.

Cross-group follow-ups (files this group does not own):
* `game/tests/unit/test_ui_journal_tracker.gd` expects three lamp rows; with R38 the quarry step shows three rows, so the view has five.
  `test_three_lamps_shown_together_in_any_order`: the label lists (lines ~146 and ~155) become `["Light the garden lamp", "Calm the Quarry
  Warden", "Mend the mineral winch", "Light the quarry lamp", "Light the manor lamp"]` and the done check (line ~156) becomes
  `[false, false, false, false, true]` (manor lit). `test_tracker_node_follows_every_stage`: `rows.size()` is 5 (line ~259) and the
  done check (line ~260, quarry lit) is `[false, true, true, true, false]` (a done step's rows all read done, tracker.gd rule).
* `game/tests/unit/test_save_v2_state.gd` `test_current_objective_combines_both_layers` (line ~468): the per-row step ids become
  `["ch2_orchard", "ch2_quarry", "ch2_quarry", "ch2_quarry", "ch2_manor"]`.
* QA bot (`tools/qa/*`) / telemetry readers of `current_objective().status`: rows may now carry `"display": true`; a bot that
  treats every unticked row as a required action should skip display rows (they tick on their own as the Warden / winch are done).
* Docs (lead): `docs/ARCHITECTURE.md` "Chapter Two conventions" could mention the `display` objective key; `INTEGRATION_WAVE_BC.md` §7/§8
  R38 notes are now resolved.

Re-check (2026-09-28, later run): `parse_all` 1/1, `chapter_log` 19/19, `story_ch2_data` 7/7, `mastery_core` 17/17 all pass. The two
tracker / state test follow-ups above landed with their owners (they filter display rows): `ui_journal_tracker` 13/13, `save_v2_state`
24/24. The manor failures noted above are gone: `manor_progress` 16/16, `velour` 62/62, `warden` 24/24.

## G6 UI shell & input bindings (panel registration, wardrobe hotkey, rebindable build keys)
Files: `game/src/ui/ui_root.gd`, `game/autoload/settings.gd`, `game/src/ui/panels/controls_panel.gd`, `game/src/ui/ui_util.gd` and
their tests (`test_ui_root`, `test_ui_settings`, `test_ui_util`, `test_core_settings`, `test_ui_appearance_wardrobe`).

| id | outcome | what changed / why |
|---|---|---|
| P33 | done | `ui_root.PANELS` registers `expedition` (`expedition_panel.gd`) and `music_box` (`music_box_panel.gd`). `expedition` is in `FULLSCREEN` + `GAMEPLAY_PANELS` (pauses, hotkeys switch away). `music_box` is in `GAMEPLAY_PANELS` only: a paused tree would silence its song preview, so it keeps the world running like the companion menu (it closes itself when Krystal is hurt). The board (`expedition_board.target_panel()`) and the Music Box (`panel_available()`) find them through `has_panel()`, so the board now opens the Expeditions panel instead of the journal and the box opens its song list instead of only chiming. The every-panel test opens both without args and now also checks that a panel pauses exactly when it is in `FULLSCREEN` and that the music box window is 780 wide. |
| D02 | done (lead decision: O) | Action `wardrobe` = O in `Settings.DEFAULT_BINDINGS`, rebindable ("Wardrobe", after Map); `ui_root.HOTKEYS["wardrobe"] = "wardrobe"`; F1 overlay "Menus" row; `UiUtil.TOKEN_ACTIONS["wardrobe"]`. O is used by no binding, debug key, build fallback or wardrobe key (Q / E switch wardrobe categories). Rules = the pause-menu Wardrobe through the shared `_hotkey`: full-screen, pauses, only in ordinary play (mode "playing", no fade, no ending/death overlay, opens over nothing or a gameplay panel - not over the pause menu, which has its own button); the same key closes it; typing O while naming a preset is captured by the wardrobe and never closes it. |
| D03 | done | `DEFAULT_BINDINGS` `build_undo` Z, `build_recolor` P, `build_variant` N (exactly `build_mode.FALLBACK_KEYS`, so docs / muscle memory stay right), `REBINDABLE` rows "Build: Undo last piece", "Build: Recolour", "Build: Pumpkin face" (after Build Mode); `TOKEN_ACTIONS` `undo` / `recolor` / `variant`. `build_mode.gd` unchanged: `_pressed()` / `key_label()` prefer the InputMap action now that it exists (a rebind reaches build mode and the build bar; tested). `onboarding_hints.build_key()` now returns the live `{undo}` / `{recolor}` tokens (tested). |
| (both) | verified | A settings file from before these actions (custom keys saved, none for the new actions) loads with the new actions on their default keys and nothing written into the saved bindings; a saved binding for a new action is honoured (`test_core_settings.test_older_settings_file_gets_the_new_actions_by_default`). This is the existing `setup_input_map()` fallback, now documented on the function. |

Layout decision (F1 controls overlay): the build keys moved out of "Menus" into a new "Building" group (Build mode, Rotate, Dismantle,
Undo last piece, Recolour, Pumpkin face); `controls_panel.COLUMNS = [[0, 3], [1], [2]]` stacks Building under Moving so the three
columns stay balanced (window 1560 x 779 on the 1080p canvas). `GROUPS` keeps its `[name, items]` shape (test_companions_ui reads it).

Not changed on purpose: `build_rotate` / `build_dismantle` are still not in `REBINDABLE` (not requested; they were not rebindable before
either - a one-line follow-up if wanted). A player whose old settings file moved another action onto O / Z / P / N now has both actions
on that key until they rebind one (Settings shows "Also used by"); defaults are never taken away from an action silently.

Cross-group follow-ups:
* `game/tests/unit/test_building_undo_tint.gd` `test_build_keys_never_shadow_other_actions` fails by design after D03: it asserts every
  fallback key is free in `DEFAULT_BINDINGS`, and each is now bound to its own build action. The intent (never shadow ANOTHER action)
  holds; the assert should skip the action's own binding, e.g.
  `assert_false(used.has(code) and String(used[code]) != String(action), ...)` (building test owner).
* Docs still say the wardrobe has no hotkey / the build keys are fallback-only: `docs/ARCHITECTURE.md` (UI root bullet, "no hotkey
  yet"), `docs/ch2/maps/ui.md` (`GAMEPLAY_PANELS` / `HOTKEYS` lines, "Panel registry additions (B2)", D02 note), and `KNOWN_ISSUES.md` /
  `INTEGRATION_WAVE_BC.md` §6 D02 / D03 rows if they are tracked as open (docs owner). The player docs already name O.
* Optional: onboarding hint `ob_wardrobe` could name the new key ("press {wardrobe}, or {pause} > Wardrobe"); the token exists now.

Tests (2026-09-28): `tools/test.sh parse_all` 1 test, 0 failed. `tools/test.sh test_ui_root,test_ui_settings,test_ui_util,test_core_settings`
89 tests, 0 failed. `tools/test.sh test_building,test_ui_,test_onboarding,test_qa,test_title,test_player_input,test_companions_ui` 352 tests,
1 failed (the `test_building_undo_tint` assert above). Neighbour suites `test_expeditions_ui`, `test_music_box_nodes`, `test_onboarding_text`,
`test_ui_hud_ch2`, `test_core_quests`, `test_save_v2_chapter_log`, `test_story_ch2_data`, `test_ui_appearance_flow` pass.
Re-run after the session resumed (same day): `parse_all` 1 test, 0 failed; the five owned suites (incl. `test_ui_appearance_wardrobe`)
109 tests, 0 failed; `test_building,test_onboarding,test_expeditions_ui,test_music_box,test_companions_ui,test_player_input,test_ui_appearance`
229 tests, 1 failed (still only `test_building_undo_tint.test_build_keys_never_shadow_other_actions`, see follow-up above).

## G3 Echo trial flow (pay on arrival, stones, menu texts)

Files: `game/src/world/areas_ch2/echo_trial.gd`, `game/src/world/trial/trial_entry.gd`, `game/src/world/trial/velour_trial.gd`,
`game/data/trials.gd`, `game/src/world/below/below_world.gd`, tests `test_trials_data.gd`, `test_trials_flow.gd`,
`test_trials_entry.gd`, `test_trials_velour.gd`, `test_trials_choir.gd`, `test_enemies_boss_trial.gd` (`test_trials_harness.gd` unchanged).

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| L08 (lead, binding) | done | Repeat-clear rewards are never given inside `echo_trial` any more (a full backpack dropped them at her feet under area `echo_trial`, and every trial shares that area id, so they reappeared inside another arena). `record_clear()` keeps the first-clear ledger grant exactly as before; a repeat clear now stores what it earned in `GameState.trials[id]["pending"]` ({item: n}, merged with any gift still waiting) plus `"pending_clears"` (how many clears it holds), toasts "The echo's gift waits for you back at <origin>." and calls `init()`. Its return value keeps `"items"` (what the clear earned) and gains `"pending": bool`. New static `init()` (idempotent; `Game.wire_session_systems` already calls it through G7's `SESSION_INIT_SCRIPTS`), `shutdown()`, `is_listening()`, `pending_gifts()`, `origin_name(id)` and `pay_pending(area_id)`, connected to `Events.area_loaded`: on arrival in any area not in `Game.TRANSIENT_AREAS` (leaving, falling and Continue all land at the origin) it writes the trial ledger first (`paid` += items, `repeat_paid` += pending_clears, `pending` / `pending_clears` erased, so a re-entrant call cannot pay twice), then gives each item via `GameState.give_item`; overflow drops at the respawn spawn of the area just loaded (the origin checkpoint the trial set), else at her feet; one toast "The echo's gift: ...". Same path for all three trials. A repeat clear with nothing valid to give is settled at once (`repeat_paid` + 1). New data key `origin_name` per trial ("the chamber door", "the ballroom candles", "the Bell Throat"). Record line, reward line and menu text are unchanged (tested before / after a save round trip). The saved keys match `docs/CHAPTER_TWO_SPEC.md` §3 (already documented there). |
| L10 (lead, binding) | kept | `TRIALS.choir.entry.pos` stays (153.6, -28, 27.6). No code change; a header comment in `data/trials.gd` records the decision and the fallback (about (153.4, -28, 24.75), one data line) if the visible run shows the west wall rocks touching the stone. The on-screen check is still pending (lead's visible run). |
| P28 | done | The Below's Matron stone keeps its Interactable, prompt and "Enter the echo" / "Not now" buttons, but the confirm now shows `echo_trial.menu_text("matron")` (title + body = the memory text as before, the trial's record, the reward line). New test `test_the_below_stone_opens_the_trial_menu_with_record_and_reward`; the existing Below test is unchanged and passes. |
| P30 | done | `trial_entry.gd` `refusal_text()`: "The echo stays quiet while a fight is on." only when `Game.boss_active()`; otherwise (cutscene / menu / load) "The echo stays quiet for now." Test covers cutscene, boss fight in play, and both at once. |
| P31 | done | `test_trials_velour.gd` reads `count_velour.gd LEAVE_MARGIN` (6.0 today) instead of a hard-coded 6.0. |
| P32 | done | L09 has landed (`pat_echo_masquerade` / `pat_echo_chime` in `data/appearance.gd`, Loom recipes, `rw_trial_velour_first` / `rw_trial_choir_first` in `data/sources.gd`). `data/trials.gd` header: PENDING note dropped; says `data/sources.gd` REWARDS mirrors FIRST_REWARDS (tests check they agree); `pattern_name` described as the fallback name; the pending-gift keys documented. `test_trials_data` now ASSERTS every trial pattern exists, carries the table's name and its trial's flag, shares no parts or flag with another trial pattern, has a Loom recipe gated by that flag, and every bundle is catalogued in sources.gd (the NOTE branch is gone). `test_trials_entry` asserts the Velour / Choir menus name their patterns (the "echo will remember you" branch is gone from the test; the code keeps it as a guard). |
| P58 (lead: keep) | kept | No behaviour change: the Velour memory starts with all three candles lit (no teaching candle), the Count's line and the fade line stay 2.4 s apart. A header comment in `velour_trial.gd` records the decision and why (a replay of a won fight; lit candles keep phases B / C fair). |

Tests (headless, 2026-09-28): `parse_all` 1/1 pass. `test_trials_,test_enemies_boss_trial` 39/39 pass (new:
`test_a_full_backpack_win_drops_nothing_in_the_echo_and_the_gift_waits_for_the_origin`, `test_the_below_stone_opens_the_trial_menu_with_record_and_reward`,
`test_a_waiting_gift_survives_save_and_load_and_is_paid_once`, `test_the_gift_payer_is_wired_once`, and the real-flow
`test_a_repeat_gift_is_paid_on_arrival_at_the_origin`: full backpack, win in the Velour echo, nothing dropped in the echo, the pale
door brings her to the ballroom candles where the gift drops at the checkpoint once, the arrival save carries it paid; a second win,
a save written inside the echo, Continue: paid exactly once). Related suites (`data_ch2_rewards`, `flow_ch2_roundtrip`,
`manor_progress`, `below_flow`, `below_progress`, `works_deep_integration`, `onboarding_hints`, `core_save`, `flow_ch2_rules`,
`flow_ch2_areas`, `ui_appearance_wardrobe`): 157/157 pass (one pre-existing `ISOLATION test_works_deep_integration: Game._bosses`).

Cross-group notes:
* G7 already lists `echo_trial.gd` in `Game.SESSION_INIT_SCRIPTS`, so `init()` runs at session start (and after every test file via
  the runner's `wire_session_systems`); `record_clear()` also calls it. Nothing else is needed for saves carrying a pending gift.
* QA bot / telemetry (`tools/qa/*`, not touched): the "The echo leaves something behind: ..." toast is gone; a repeat win now says
  "The echo's gift waits for you back at <origin>." and the arrival says "The echo's gift: ...". Trial records may carry `pending` /
  `pending_clears` between a win and the arrival.
* Only the trial's own reward path changed. Any OTHER persistent drop created inside `echo_trial` (e.g. a `give_item` overflow from
  another system) would still be recorded under area `echo_trial` and respawn in whichever trial is entered next; none is known today
  (trial minions spawn with `no_drops`).

Re-verification (resumed run, 2026-09-28, after other groups' edits to `game.gd`, `count_velour.gd`, `borrowed_choir.gd` ...):
the code changes above are all in place. One run of `test_trials_,test_enemies_boss_trial` failed once,
`test_trials_flow.test_velour_echo_returns_to_the_ballroom_candles`: "entering a trial doesn't save expected moonveil_manor got ''".
Not reproduced in 6 further runs (alone, with entry/data, and the full group). "" means the save file just written could not be
read back (`SaveSystem._read_status` open / parse miss), not a save for another area; most likely the fresh file was briefly held on a
loaded Windows machine. The test's two read-backs now go through `_saved_area_settled()` (re-reads for up to 30 frames only while
the result is ""; a save written for another area still fails at once), no assertion weakened. After that: `parse_all` 1/1,
`test_trials_,test_enemies_boss_trial` 39/39, the related suites above 157/157 (same pre-existing `ISOLATION
test_works_deep_integration: Game._bosses was ["crossing_matron"]`, not G3's).

## G4 Trial patterns & reward catalogue (appearance parts, avatar builders, loom recipes, sources, unlocks)
| Id | Decision / request | Outcome |
|---|---|---|
| L09 | BINDING (lead): apply D1 requests 1-3 (Echo Trial first-clear patterns, MP 15 "unique cosmetic patterns"). | **Done.** `data/sources.gd` REWARDS: `rw_trial_velour_first` / `rw_trial_choir_first` copied exactly from `data/trials.gd` FIRST_REWARDS (content bundles, no items, one flag each) and added to the header list of content bundles. `data/unlocks.gd`: `ch2_trial_velour` (Moonlit Masquerade) and `ch2_trial_choir` (Chime Chorister). `data/appearance.gd`: parts `masquerade_mask` (hair_acc, `acc_masquerade_mask`), `opera_cloak` (back, `back_opera_cloak`, cape), `chime_ribbons` (hair_acc, `acc_chime_ribbons`), `chorister_capelet` (back, `back_chorister_capelet`, cape), all pattern-owned and palette-coloured; patterns `pat_echo_masquerade` / `pat_echo_chime` (names, recipes, flags and source lines as decided). `data/recipes.gd` SPECIAL_RECIPES next to `pattern_moon_moth`: `pattern_echo_masquerade` (woven_cloth 3, lantern_wax 2, loom, `ch2_trial_velour`) and `pattern_echo_chime` (woven_cloth 3, echo_shard 2, loom, `ch2_trial_choir`). `accessory_builder.gd`: the mask is a small domino mask pushed up into the hair on her left side, facing outward, back tip raised, a plume tucked into the hair (steps down under a hat); the chime ribbons are a bow on her right side with three short streamers ending in tiny bells, tilted outward so the bells hang clear of the hair cap; both capes reuse `_cape()` (opera cloak: long/wide, pale lining channel, stand collar, brass clasp; capelet: short, choir collar torus, scalloped hem, a small bell pendant). No new colours outside the catalogue, no legs/webs (nothing spider-like), low triangle counts like the existing accessories. Saves that already cleared a trial see the recipe through the existing flag (no migration; tested). |
| P40 | Optional expedition-only decor recipe unlocks (new exp_* flags). DECISION: No. | **Done (no change).** Verified `data/unlocks.gd` / `data/recipes.gd` have no `exp_*` flags or expedition-only recipes; keepsakes stay ready-made decorations and dyes. |

Tests added / changed (all in G4 files): `test_data_ch2_appearance.test_echo_trial_patterns` (exact catalogue entries, recipes, flags, slots, capes); `test_data_ch2_rewards.test_echo_trial_first_clears_unlock_unique_patterns` (strict: every trial's bundle mirrors FIRST_REWARDS, its pattern exists, is named as the trial promises, and nothing else sets the flag, grants the pattern or sews it - this is the asserting replacement for the old "NOTE: not in data/appearance.gd yet" branch) and `test_a_cleared_trial_flag_is_enough_to_sew_its_pattern` (old save with only the flag, and a real first Choir clear, both sew their pattern once); `test_data_ch2_sources.test_reward_bundles_set_every_story_unlock_once` (each `ch2_trial_*` flag is set only by its own `rw_trial_*_first`); `test_avatar_look_build.test_echo_trial_accessories_sit_in_the_hair_and_capes_drape` (mask entirely at her side and never in front of the face for 4 hats x 4 hairstyles, three bells outside the hair cap, capes are one cloth chain, palette channels, jacket patch and scarf ends hidden); `test_ui_appearance_looks.test_echo_trial_pieces_say_how_to_earn_and_are_worn_once_owned`. The generic "every part builds with its own geometry" test covers the four new parts automatically.
Runs: parse_all 1/1; test_data_ch2 62/62; test_avatar 26/26; test_ui_appearance 38/38; test_trials 31/31 (no NOTE line any more); test_crafting 38/38; test_enemies_boss_trial 8/8; test_core_item_db 19/19; test_expeditions_templates 9/9; test_reach_east_layout 8/8.
Cross-group follow-ups (files not owned by G4): `data/trials.gd` header still says "PENDING: pat_echo_masquerade / pat_echo_chime are not in data/appearance.gd yet" and "(a data/sources.gd mirror, when present, wins)" - now stale; `tests/unit/test_trials_data.gd` `test_each_first_clear_pattern_is_unique_to_its_trial` can drop its `if p.is_empty(): print NOTE; continue` branch for a plain `assert_false(p.is_empty())`; `tests/unit/test_trials_entry.gd` can drop its "pattern not yet catalogued" branch; `tests/unit/test_avatar_look_motion.gd` `test_capes_never_swing_into_the_back` lists only the three older capes (the new ones share the same `_cape()` chain, so behaviour is identical); `docs/ch2/WAVE_A_REPORT.md` rewards rule lists the content bundles without the two new trial bundles; `echo_trial.gd` comments that mention the pending pattern.
Re-verified after the session resumed (06:2x): parse_all 1/1; test_data_ch2 63/63; test_avatar 26/26 (the printed stack traces are the expected push_warnings of `test_unknown_ids_fall_back_without_touching_the_saved_look`); test_ui_appearance 38/38; test_trials 31/31; test_crafting 38/38. Other groups have since closed most follow-ups (data/trials.gd header, the test_trials NOTE / "not yet catalogued" branches, the WAVE_A_REPORT rewards list). Still open: `test_avatar_look_motion.test_capes_never_swing_into_the_back` covers only leaf_cape / little_cape / moth_shawl (optional; the new capes use the same `_cape()` chain).

## G2 Boss arenas & world hooks (Velour manor, Crossing arena, Warden arena, Works wisp encounter)

Files: `game/src/world/reach/east/warden_arena.gd`, `game/data/works_layout.gd`, `game/src/world/areas_ch2/moonveil_manor_world.gd`,
`game/src/enemies/count_velour.gd`, `game/src/world/works/deep/crossing_arena.gd`; tests `test_reach_east_encounter.gd`,
`test_works_layout.gd`, `test_manor_resident_greet.gd`, `test_manor_progress.gd`, `test_boss_velour_manor.gd`, `test_boss_velour_fight.gd`,
`test_boss_crossing_arena.gd`. Not changed: `lantern_anchor.gd` (P24).

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| L02 | done | `warden_arena._clear_encounter()`: in the existing `first` branch the arena also emits `Events.notify(TEXT["warden_clear"], "success")` (the channel `enemy_spawner._on_wave_cleared` uses for `clear_message`). The spawner flag logic is unchanged. On a real defeat the Warden's `boss_defeated` reaches the arena before its spawner, so the arena shows the message. On a spawner-first clear the spawner shows it and the arena's `first` is false. Either way it shows once. A reload (flags in the save) shows nothing. |
| P13 | done | `works_layout.SPAWNERS["hw_sp_eyes_wisp"]` = {borrowed_wisp, count 1, radius 1.0, respawn 1440, quest flag "", wander 3.0, clear_message ""} at **(-16, -13, 36)**, the quiet south end of the Hall of Closed Eyes. It is 9.2 m from the eyes_route lantern hook and at least 6 m from the nearest point of every opening (bells way 7.2 m, carvers' rest door 8.1 m). The carvings are 12+ m away. It is out of every safe zone. Its z is 20.5 m past `WRONG_DOOR_TRIGGER_Z`, more than its 11 m aggro radius, so it never interrupts the Wrong Door moment. That moment teaches "real light lights the floor", and the wisp is the test of it. Placed by `hushed_works_world._place_enemies` (data-driven). No `data/enemies.gd` change. |
| P14 | done | `_apply_after_velour(live)`: flags, candles, doors, the lantern refresh and the echo stone stay immediate. On a live win the resident is created after `RESIDENT_DELAY` (1.4 s = `count_velour.DEFEAT_PRESENT`; a mirrored constant because a won save never loads the boss script; tests keep them equal). The delay uses one pause-aware `create_timer(..., false)` connection (`_resident_pending` blocks a second schedule). It is dropped when the area is freed, not in the tree, `Game.mode == "loading"` or another area is current. On a load he still appears at once and stays quiet. This applies to every live path (boss, candle fallback, debug, foreign flag): one rule, and the fallback gets the same short beat. |
| P15 | done | `start_fight()` retry hint: story keeps `velour_retry` (manor wording). Trial mode (`not is_story()`) uses `velour_retry_trial`: "The echo keeps his wounds while you stay in the memory. Leave through the pale door and it starts afresh." |
| P16 | decision: keep | No behaviour change. A comment at `MASK_FLOOR` records that a companion's blow during the channel also lifts the 8% floor (pets hit exposed phases normally, MP §13). The light-stagger landing distance, the damage taken by a player who never dodges and the bot pacing are tuning. Sim baseline this run (tireless bot, copper 18): Gentle 80 s / took 48, Standard 82 s / 148, Intense 80 s / 166; Standard moonsteel 64 s. |
| P17 | done | `crossing_arena._apply_cleared(animate)`: flags, reward, save and `Art.set_collision(_route_body, true)` stay immediate. When the win is animated and a real retreat plays, the bars' drop, `gate_unlock`, the shake, the gate caption and the "retreats behind the old service gate" line wait `max(boss.retreat_seconds() - 0.8, 0)` s. A real retreat means a valid boss with `retreat_seconds()`, not `is_gone()` and not `fast_defeat`, so a quiet debug withdrawal or no boss gets no wait. The wait is a one-shot timer to `_on_gate_delay` guarded by `_gate_pending`, the tree and area exit. If she left meanwhile, the bars just snap to the end state. `route_gate_shut()` is true at once (cleared). |
| P18 | done | `check(p)` returns early through the new `player_down(p)`: her `health.dead`, or `p == Game.player` while `Game.mode != "playing"`. The mode gate applies to the real player only, so test stand-ins driven through `player_override` keep working. While she lies on the bridge there is no fight flag and no `authored:hw_crossing`. |
| P19 | done | `boss_params()` passes `"rail": float(Layout.CROSSING["rail"])` (4.8). The Matron now uses the layout value instead of recomputing it from the bridge rect. |
| P24 | decision: keep | `lantern_anchor.gd` untouched. The Choir's lower-the-hook workaround is tested, and the practice anchor's 8 s lockout shows the disabled "Your lantern burns on the anchor" prompt. |

Tests (headless, 2026-09-28): `parse_all` 1/1. `test_reach_east_encounter` 13/13 (new `test_clear_message_once_on_any_path_and_never_after_a_reload`; the real Warden and `boss_defeated` tests count the toast). `test_works_layout` 14/14 (new `test_eyes_wisp_spawner_is_valid_and_out_of_safe_zones`: data, registration, distances, floor / capsule / headroom, not safe, and a real wisp spawns inside the hall). `test_boss_crossing_arena` 11/11 (rail; the fall test now also asserts the arena and the horror event stay down; new `test_the_arena_waits_while_the_real_player_is_not_playing`, `test_the_service_gate_waits_for_her_retreat`). Crossing fight / rules and `works_deep_arenas`: 47/47. Manor and Velour (`test_manor_resident_greet` +2 area tests, `test_manor_progress` and `test_boss_velour_manor` wait for the resident, `test_boss_velour_fight` + retry hint test): 76/76. Wider run (works, flow_ch2, story_ch2, trials, manor, reach_east, enemies_ch2, onboarding, enemies_boss): 523/523. Plus choir_rhythm, data_ch2, core_item_db, horror_director_core, companions_logic, velour_phases, enemies_ch2_warden, mastery_core: 221/221. G8's note about 4 resident failures came from this group's in-flight change. The tests now wait for the resident, and those suites pass.

Real-input checks (pending): Velour companion blows during the channel lifting the mask floor; where a light-stagger lands (~13 m); the damage a player who never dodges takes on Standard; engaged time of the real fight. The Crossing gate: the bars reach the lintel about when the Matron slips into the crack (both arachnophobia looks). The Hall of Closed Eyes wisp: first contact with the lantern reveal near the bells-way exit on Gentle.

Cross-group follow-ups (files this group does not own):
* `autoload/game.gd` `AREA_WARMUP["hushed_works"]`: consider adding `res://src/enemies/borrowed_wisp.gd`. The new eyes spawner makes the wisp script load lazily on the main thread the first time she nears the hall (about 35 m, from the rail hall).
* QA bot (`tools/qa/ch2/s4_*`): a route through loop A (`s4_nav.py` "loop_a") now meets one Borrowed Wisp in the Hall of Closed Eyes near the bells-way exit (spawner `hw_sp_eyes_wisp`). The Crossing gate caption / Matron line now arrive about 2.6-3 s after `boss_defeated`, and the Velour resident about 1.4 s after it (his greeting about 2.6 s after it).

## G5 Expeditions surfaced (map pins, tracker card, texts, mastery xp)

Files: `game/src/expeditions/expeditions.gd`, `game/src/expeditions/expedition_runner.gd` (comment), `game/data/expeditions.gd`,
`game/src/ui/panels/expedition_panel.gd`, `game/src/building/structures/expedition_board.gd` (comments), `game/src/ui/widgets/map_view.gd`,
`game/src/ui/panels/map_panel.gd`, `game/src/ui/hud/tracker.gd`; tests `test_expeditions_core`, `test_expeditions_ui`, `test_ui_map_areas`,
`test_ui_journal_tracker`, `test_building_ch2_models`.

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| P35 | done | `map_view`: `area_of("exp_*")` is the Reach (while the expeditions script loads); `place_disc(id)` resolves `exp_*` ids through `Expeditions.place_disc()` on the Reach map only (`{}` on the woods map / without a run); `place_name` names them. All expedition access is safe-loaded (`EXPEDITIONS_PATH`, `_expeditions()`, public statics `expedition_disc`, `expedition_pins`, `expedition_target`, `draw_expedition_pin`). `prepare()` reads `expedition_marks = Expeditions.map_marks(REACH)` (never per frame); `_draw_reach()` draws them over the stickers, under Krystal's arrow: numbered paper pins in the ribbon colour for the stops, a candy pin for the cache, done stops faded with a tick, a steady gold ring on the current one. `map_panel.goal_marks(REACH)` always adds `Expeditions.current_target().id` to the Reach map's marks (so it also pulses while a chapter step owns the card, with one extra line "Expedition: head to X"); the Reach legend gets an "Expedition stop" row while a run is going. Nothing is drawn, marked or listed without a run. `Expeditions.map_marks()` now builds from the plan (adds `"n"`, the stop number). Reach window with a run: 1550 x 944 (fits). |
| P36 | done | `Tracker.objective_view()` returns `Expeditions.tracker_view()` (kind `"expedition"`, safe-loaded via `Tracker.expedition_view()`) ONLY where the view would be `signpost` / `done` / `hidden` (`_or_expedition`); chapter, legacy and pointer steps always win (tested at every stage with a run present). `where_text()` for `"expedition"` = `view["where"]` (+ the map key suffix in the Reach; `""` while she stands within 8 m of the current stop / cache). To fit the objective-view contract, `tracker_view()` now lists ONLY the current stop / cache in `"targets"` (one pulse, one "Head to" line in map / journal consumers; the map pins show the whole route), `"group"` is `""` (the journal lists its rows; a non-empty group made the journal iterate an empty `parts`), and `"parts"` has one entry. |
| P39 | done (lead decision) | `complete()` on a route's FIRST completion (after the completion is recorded, after the rewards) calls `Mastery.award("wayfinding", "expedition:" + template, Data.FIRST_ROUTE_WAYFINDING_XP)` through a safe-load guard (`MASTERY_SCRIPT`, `has_method("award")`). `FIRST_ROUTE_WAYFINDING_XP = 20` in `data/expeditions.gd` (the size of the shortcut / arch first-time rules). Mastery dedupes on the kind, so it is once per route, also across a reload; an abandoned run gives nothing; no flag, ledger, quest or optional-goal change (the "never write flags / ledger untouched" test still passes). No other side effect (20 xp from 0 is below rank 1, so no rank toast on a fresh save). |
| P41 | done | `test_building_ch2_models`: the test is renamed `test_expedition_board_journal_fallback_is_the_optional_tab`; the docstring says the board opens the Expeditions panel (registered by G6 P33) and `panel_args()` stays the journal fallback / second option; the assertion message says the same. Still passes. |
| P42 | done (lead decision) | The direct palette unlock stays (a keepsake is a gift; post-Choir only). Texts made honest: the three `reward_types` now read "Sometimes: a new dye colour (Pumpkin or Rose / Ember or Cream / Lavender or Midnight) for clothes and furniture, or a festival decoration"; new `Data.TEXT["dye_keepsake"]` = "a new dye colour ({colour})" and `Expeditions.keepsake_text(keepsake)` (dye -> "a new dye colour (Pumpkin)", decor -> "Pumpkin Lights x2"), used by the completion toast AND the panel's "Last outing" line (they had said "the Pumpkin Dye recipe"). Header comments of both expedition files updated. Tests: no reward text / toast / panel line says "recipe", each route names its own dye colours. |
| P43 | done (lead decision, comments only) | The vanish on setting a run aside mid-fight is kept. P34 has landed (`Game.SESSION_INIT_SCRIPTS` includes the expeditions script), so the stale "until Game wires Expeditions.init()" comments in `expedition_board.gd` `interact()`, `expeditions.gd` `init()` and `expedition_panel.gd` `_build()` now say Game wires it at start-up and those calls are an idempotent safety net; the P43 decision is noted at the board, the header of `expeditions.gd` and the runner's `clear_all()`. Board / panel headers no longer say the panel is unregistered (G6 P33). |
| (extra) | done | The views the HUD / map poll every second (`is_active`, `current_plan`, `current_target`, `tracker_view`, `map_marks`, `place_disc`) no longer CREATE `GameState.extra["expeditions"]` on a save that never used the board (`_has_saved_run()`, read-only); a saved run is still normalised / repaired by the first read. Needed because P36 makes the tracker poll the expedition view from New Game on. |

Tests (headless, 2026-09-28): `tools/test.sh parse_all` 1/1 pass. `tools/test.sh "test_expeditions_,test_building_ch2_models,test_ui_journal_tracker,
test_ui_map_areas,test_ui_journal_tabs,test_ui_map_telemetry,test_mastery_core,test_ui_hud_ch2,test_ui_root"` 157 tests, 0 failed (new:
`test_views_are_read_only_without_a_run`, `test_first_completion_of_a_route_gives_wayfinding_xp_once`, `test_dye_keepsake_reads_as_a_new_dye_colour`,
`test_expedition_card_replaces_the_signpost_and_done_views`, `test_expedition_never_replaces_chapter_legacy_or_pointer_steps`,
`test_tracker_node_shows_the_expedition_card`, `test_expedition_route_on_the_reach_map`; extended `test_tracker_map_and_summary_views` and the
panel reward-type / last-outing tests). Wider run `test_ui_,test_save_,test_data_ch2,test_building_,test_flow_ch2,test_core_save,test_onboarding,
test_mastery,test_crafting_ch2,test_c1x_rewards`: 599 tests, 2 failed, neither this group's: `test_building_undo_tint.test_build_keys_never_shadow_other_actions`
(G6 D03, documented above) and `test_save_v2_migration.test_upgrade_backup_copies_v1_bytes_once_before_the_first_v2_write` ("could not rotate
backup") which passes when run alone (17/17): a clash of parallel test runs sharing `user://test_saves`, not a code fault.

G8 follow-up handled here: `test_ui_journal_tracker` (this group's file) no longer hard-codes three lamp rows. The lamp tests compare the rows a
step needs (`_counted()` drops `"display": true` rows), check every display row is labelled, compare the tracker node's shown rows with the view's
rows, and check every row of the lit quarry step reads done. They pass with G8's display rows and would pass without them.

Cross-group follow-ups (files this group does not own):
* `game/src/ui/panels/journal_panel.gd` (UI owner, optional): while a run is going after Chapter Two, the Story tab shows the EXPEDITION card
  (header, route name, "Follow the ribbon lantern to X.", one row per stop + the cache) instead of "The Lanternwake is complete!", because kind
  `"expedition"` is not in its hidden / done / signpost branch. Acceptable as is; if the congratulation should stay, show it above the card.
  `journal_where()` returns `""` for kind `"expedition"`; it could return `vw["where"]` like the tracker.
* `game/data/mastery.gd` (data owner, optional): the Wayfinding description ("Discover landmarks, open shortcuts, read lore and face varied
  encounters.") could add "and walk new expedition routes"; an `"expedition": {"xp": 20, "once_per": "route", ...}` XP rule would document it
  (the code passes the xp explicitly, so it works without the rule).
* `docs/ARCHITECTURE.md` "Journal / tracker / map / telemetry" (docs owner): `tracker.objective_view()` kinds gain `expedition` (only in place of
  signpost / done / hidden); MapView resolves `exp_*` ids and draws the running route on the Reach map; `docs/ch2/maps/ui.md` likewise.
* QA bot / telemetry (`tools/qa/*` owners): read-only telemetry `tracker.kind` can now be `"expedition"` after Chapter Two with `targets` =
  the current `exp_*` stop in `hallowmere_reach`; it is optional (never a story step), so a bot should not treat it as the next story goal.

Re-verified after the usage-limit pause (2026-09-28 06:22, with the other fixers' later edits in the tree): `tools/test.sh parse_all` 1 tests, 0 failed;
the group run above again 157 tests, 0 failed. No code change since the table above.

## G9 Docs, onboarding hints & release packaging (pass-2 record)

Files: `docs/ARCHITECTURE.md`, `docs/CHAPTER_TWO_SPEC.md`, `docs/SAVE_MIGRATION.md`, `docs/ch2/WAVES.md`, `docs/ch2/INTEGRATION_WAVE_BC.md`,
new `docs/ch2/INTEGRATION_WAVE_D.md` (the pass-2 decision record: every request of the plan with its decision and reason),
`docs/ch2/WAVE_A_REPORT.md`, `docs/ch2/maps/{combat_enemies,world_areas,state_save_data,ui}.md`, `GAME_SPEC.md`, `KNOWN_ISSUES.md`,
`README.md`, `PROJECT_STATE.md`, `AGENTS.md`, `docs/player/How to Play.txt`, `docs/player/Chapter Two - What's New.txt`,
`tools/build_release.ps1`, `game/src/world/story_ch2/onboarding_hints.gd`, `game/tests/unit/test_onboarding_{hints,text}.gd`.

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| L07 (lead, binding) | done | Code already matched (`data/trials.gd` `requires_flag`: matron `weaver_defeated`, velour `ch2_velour_defeated`, choir `ch2_choir_defeated`; nothing gates on `ch2_trials_open` - `story_ch2.gd` only repairs the flag for a done `ch2_routes_restored` step). Docs: `INTEGRATION_WAVE_BC.md` §6 D08 row ("superseded by the pass-2 lead decision: no `ch2_trials_open` gate"), spec §1 opening rule, `world_areas.md` §8 (+ the §3 n note), ARCHITECTURE "Echo Trials", `GAME_SPEC.md` "Replay & optional", `KNOWN_ISSUES.md` (kept limitations). The `data/quests_ch2.gd` header line is P56 (G8, done). |
| D10 (lead) | recorded | Not in this pass. ONE open item in `KNOWN_ISSUES.md` (Chapter Two "Open work") listing every requested voice (Wave B/C enemies, C5, Velour, the Crossing incl. its arachnophobia pairs, the Choir) and the plan (tools/audio generators + Audio index / aliases, then point each voice, then a human listening check); `INTEGRATION_WAVE_D.md` §2 D10. |
| F04 (lead) | recorded | Test-hygiene item in `KNOWN_ISSUES.md` (the runner's `ISOLATION` guard stays the safety net; no test fails because of it; not a player issue); `INTEGRATION_WAVE_D.md` §3. |
| P07 | done | `combat_enemies.md` §12 (new): C5 setup keys (`pumpkin_mimic` `dormant` - spawners must not pass it - and `seed`; `quarry_warden` `arena`, `arena_center`, `arena_radius`, `pillars`), the Warden leash (arena radius + 6 m, 3 m height band), timing assist x1.5, the charge lane clip + ledge bonk (D06); the `enemy_base` intensity helpers (P01), `fire_projectile` `dir` / `on_hit` / `kind` (P02), the static attack-token API (P23), `telegraph_fx.move_ring` (P04), `expose()` (D04, Velvet Wing / Borrowed Wisp only); `count_velour` (setup keys, group "enemy" only while fighting, reset policy, trial mode), `crossing_matron` (`boss_params()` incl. `rail`, HP floor 60 % / 25 %, `retreat_seconds()`, the z = 0 bridge-centre assumption of `crossing_rules.gd`), `borrowed_choir` (`boss_params()`, trial mode, attack tokens, three exposures). ARCHITECTURE "Chapter Two conventions" gains the same in one bullet. |
| P29 | done | Spec §3 `trials` keys (`last_seconds`, `repeat_paid`, `paid`, `pending`, `pending_clears`); spec §1 names `data/trials.gd`, `src/world/trial/*`, the three stones (Below `cp_arena` - not "arena_gate" -, manor ballroom, Bell Throat) and the L07 rule; ARCHITECTURE the same; `WAVES.md` Wave D module rows D1-D4 + the pass-2 group table; `GAME_SPEC.md` / `KNOWN_ISSUES.md` no longer call the Velour / Choir trials or the expeditions "in progress"; `SAVE_MIGRATION.md` §2 trials row. |
| P37 | done | `SAVE_MIGRATION.md` §2 rows `extra["expeditions"]` ({v, active{template, seed, stop, defeated, down, started_at, run}, runs, completed, abandoned, last}; runner node only while a run is active) and `extra["music_box"]` ({discovered {cue: {area, zone, at}}, favourites}; unknown cues kept, never played) + the trials keys; `state_save_data.md` §14; ARCHITECTURE: Expeditions API, Music Box API, preview priority 40 (ended by any higher music, death, leaving the area), the house rule (box's own area; Haven zone on the surface or 12 m around the box), the panel is not fullscreen and closes when she is hurt, the muted behaviour (P47); onboarding hints (`attach`, the suppression reasons); the pass-2 input actions. |
| P48 | done | `tools/build_release.ps1` also copies `docs\player\Chapter Two - What's New.txt` (`-LiteralPath`; the apostrophe is safe) next to `How to Play.txt`; header comment updated. Parsed with the PowerShell parser (0 errors); no build was run (the lead packages). |
| P49 | done | What's New "GOOD TO KNOW": echo stones by the lantern / candles before each won great fight (Heartseed Chamber, manor ballroom, Bell Throat), the Expedition Board's three routes by name, the Music Box with favourites; the wardrobe key O (What's New, How to Play, `GAME_SPEC.md` controls); the "Z, P and N can't be changed" line is gone (rebindable, D03); `GAME_SPEC.md` "Replay & optional"; README status line. `onboarding_hints.gd`: ONE generic `ob_echo_trial` (where keyword `echo_origin` = an area whose trial's `requires_flag` is set, read from `data/trials.gd`: below / moonveil_manor / hushed_works after weaver_defeated / ch2_velour_defeated / ch2_choir_defeated), armed on arrival there and live when Velour or the Choir falls (not when the Weaver falls: Chapter One's return home is never interrupted, it waits for the next Below visit), obsolete once any trial has a clear; `ob_expedition_board` names the Lanternwake Expeditions and the three routes; `ob_wardrobe` names `{wardrobe}` (G6's suggestion). Tests: `test_onboarding_hints` +3 (every stone; live arming / waiting for a stone; dropped after any clear); `test_onboarding_text` (O and Z / P / N are real rebindable Settings actions and the docs say so; the note names every trial's stone, the three routes, the Expedition Board and the Music Box as Workbench recipes). |
| P50 (lead) | kept | Timings unchanged (2.5 s calm, 25 s gap, 30 s after horror); listed in `KNOWN_ISSUES.md` and the pending checks. |
| P51 | done | `docs/ch2/INTEGRATION_WAVE_D.md` written (lead decisions, D01-D11, F01-F04, design calls, applied requests per group with a "seen in code" column, obsolete P26, G9 details, still open); `INTEGRATION_WAVE_BC.md` §6 "resolved in pass 2 -> see INTEGRATION_WAVE_D.md" column + §3 / §7 / §8 pointers; `WAVE_A_REPORT.md` content-bundle list gains `rw_trial_velour_first` / `rw_trial_choir_first`; `KNOWN_ISSUES.md` Chapter Two section rewritten (bosses, trials, expeditions, music box built; open: D10 voices, F04 hygiene, D09 `.uid`, P50 pacing, L10 stone, visual / listening / real-input / performance lists); `PROJECT_STATE.md` status; `AGENTS.md` visual-QA commands (`--ui-open=expedition`, `--ui-open=music_box`, the trial arenas and stones, `--save-dir` for any run that can save); `ui.md` §12 (new panels, hotkeys, tracker / map, stones, hints) and a "current after pass 2" note under the §2 Chapter One registry snapshot. |

Cross-group doc follow-ups applied from the other sections: G8 (ChapterLog `"display"` rows in ARCHITECTURE / state_save_data; the
BC §7 / §8 R38 notes point to pass 2), G6 (the ARCHITECTURE UI-root bullet and `ui.md` name the O hotkey and the rebindable build keys;
no doc says "no hotkey" / "can't be changed" any more), G4 (WAVE_A_REPORT bundles), G5 (tracker kind `expedition`, `exp_*` map ids in
ARCHITECTURE and `ui.md`).

Tests (headless, 2026-09-28, re-run after the usage-limit pause with the other fixers' edits in the tree):
`tools/test.sh onboarding` -> `==== 35 tests, 0 failed, 1.9s ====` (no ISOLATION / SCRIPT ERROR lines);
`tools/test.sh parse_all` -> `==== 1 tests, 0 failed, 12.3s ====`; `tools/test.sh test_ui_util` -> `==== 26 tests, 0 failed ====`;
`tools/test.sh flow_ch2_rules` (the session wiring attaches the hints) -> `==== 19 tests, 0 failed ====`.

Cross-group notes: none new. (G2's `AREA_WARMUP["hushed_works"]` += `borrowed_wisp.gd` suggestion belongs to the `game.gd` owner.)
`INTEGRATION_WAVE_D.md` §5 records G1 / G7 as "seen in code" (their sections were not yet in this file when it was written) and G10
(the D09 import) as still to run.

## G1 Enemies: base hooks, Chapter Two enemies, Choir tokens, enemy data

Files: `game/src/enemies/enemy_base.gd`, `telegraph_fx.gd`, `pumpkin_mimic.gd`, `patchwalker.gd`, `velvet_wing.gd`,
`bellcap_sentry.gd`, `borrowed_wisp.gd`, `quarry_warden.gd`, `borrowed_choir.gd`, `game/data/enemies.gd` and their tests
(`test_enemies_ch2_*`, `test_boss_choir_rhythm` / `_flow`, `test_data_ch2_catalogue`), new `test_enemies_ch2_glimmer.gd`
(a real Lumi + a real Glimmerstep cast from the companions fixture). Unchanged on purpose: `knotted_elder.gd`, `choir_rings.gd`,
`crossing_matron.gd`, `crossing_rules.gd`, `combat_sandbox.gd`.

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| L01 | done | `velvet_wing.ward_light_at()` skips group "companion" as well as "player": Lumi's passive glow never breaks a drain. Still counted: lamps / lantern posts / placed light structures (`structure.gd` light_source), lit ward candles, braziers and the Glimmerstep pulse (`companion_combat` PulseLight "GlimmerPulse", not in group companion). New `lantern_in_mark(t)` / `drain_mark_center(t)`: Krystal's raised lantern (`lantern_on`) breaks the drain only while she stands within `DRAIN_MARK_RADIUS` (0.7 m, flat) of the mark centre. The mark follows her through the wind-up and stays put for the channel. The header, the `light` break caption, the drain hint ("raise your lantern ({lantern}) inside the mark, step into candle or lamp light, out of its sight, or strike it") and the data drain tell all state the rule. Tests: Lumi's glow beside her never breaks it (fake companion and real Lumi); the pulse does (a PulseLight node and a real cast); a raised lantern inside the mark does; outside the mark it does not. |
| L03 | verified | `knotted_elder.gd` and `quarry_warden.gd` `assist_mult()` x1.5 on wind-ups and recoveries under `timing_assist`. Data has only these two `"elite": true` rows. No change; their tests are green. |
| L04 | verified | `brood_skitter` telegraph 1.0 and leap telegraph 1.0 (catalogue test R83). No change. |
| L05 | verified | `threat_damage_mult()` follows `Game.area_id` through `Combat.damage_mult_for_area` (INTENSITY_SCALED_AREAS below / tobin_annex / hushed_works). `hollow_drudge.gd` uses `attack_damage_for()`. Not touched by the P01 refactor. |
| L06 | done | `pumpkin_mimic` optional setup key `"seed"` (int >= 0; default stays randomized). `_ready()` re-seeds `_rng` after the base randomizes it and re-draws the first chatter / idle wait, so the whole twitch schedule is fixed. The test uses seed 1234. It runs until three pairs plus a 1 s tail, which always ends between pairs (the rest gap is at least 3.5 s), and checks that a second mimic with the same seed twitches at the same moments. It passed three runs in a row. No gameplay change. |
| D04 | done | `velvet_wing.expose(seconds)`: breaks a drain in progress (wind-up or channel) with reason "light", otherwise nothing. `borrowed_wisp.expose(seconds)`: a forced reveal held for at least `seconds` (`_expose_t`), exactly like a lantern reveal (drops to REVEAL_HEIGHT, vulnerable). It dazzles subject to P08's cooldown, then the usual REVEAL_HOLD veil rule applies. No `expose()` on `crossing_matron` / `count_velour` / `borrowed_choir` (the lead decision). Tests: direct calls in the velvet / wisp tests, and a real Glimmerstep cast in `test_enemies_ch2_glimmer`. |
| D06 | done | `quarry_warden.charge_reach(from, dir)` = min(data distance, `arena_lane_limit()`): the lane ends within `arena_radius - ARENA_EDGE_MARGIN` (1 m) of `arena_center`. The red lane mark and the charge use the same clipped length. In the charge step, `floor_ahead()` casts one short ray (LOS_MASK, `LEDGE_PROBE_DEPTH` 1 m below a point `LEDGE_PROBE_LEAD` ahead of the next step). With no floor, the charge stops there (`ledge_stops`) and goes through `_charge_stopped_at_wall()`: a stun while any pillar is intact, exposed when none is. Tests: lane geometry; a lane ends inside the arena; the mark shows the clipped length; a charge baited off an L2 -> L1 ledge bonks at the edge and stays on L2; with no intact pillar the ledge exposes it. The pillar and wall tests are unchanged and green. |
| P01 | done | `enemy_base` opt-in `intensity_cooldown_mult()` (Gentle x1.35 / Standard 1 / Intense x0.8), `intensity_telegraph_bonus()` (Gentle +0.2 s, added on top of the 1.0 s committed floor of `attack_telegraph()`) and `overlap_blocked()` (Gentle only: another live instance holds an attack token). The six C5 scripts call them and their private copies are gone; a test greps for that. Legacy / Chapter One extra enemies never call them (the test checks the Brambling keeps 0.7 s at every level). The numbers are unchanged: enemies_ch2, enemies, reach_east / reach_west and companions_combat are green. |
| P02 | done | `fire_projectile(from, t, params)` passes `params.dir` (then no `target`: projectile.gd prefers target), `on_hit` and `color` through to the shared projectile. Without them it behaves as before (the Lantern Moth path is unchanged). `patchwalker._throw_clod()` uses it. Test `test_fire_projectile_passes_dir_and_on_hit`. |
| P03 | kept | Per-script `_on_player_died()` overrides stay; no new base hook. |
| P04 | done | `telegraph_fx.move_ring(at)` moves the current ring / disc node (fill, rim and the high-visibility outline are children) with the same meshes. With no ring showing, it shows one. `velvet_wing._update_mark()` uses it (no more writing `global_position` / `center` by hand). Test: same meshes, the outline stays visible, a lane turns into a ring. `count_velour.gd` (other group) may switch later. |
| P08 | done | `borrowed_wisp` `DAZZLE_COOLDOWN` 6 s: a reveal inside the cooldown still reveals (reachable, vulnerable) but neither dazzles nor cancels the wind-up (`dazzles` counter). Test `test_lantern_toggling_cannot_stun_lock_it`. |
| P09 | kept | A veiled wisp may still sweep (marked, 0.8 s delayed); documented in the header. |
| P10 | done | The one-time hint `hint_borrowed_wisp_blocked` also shows the first time Krystal is within `BLOCKED_HINT_DIST` 4 m (flat) of a veiled, visible, threatening wisp. It is checked at perception (5 Hz); there is no attack detection and no damage change. Test `test_a_veiled_wisp_close_by_teaches_the_lantern_once`. |
| P11 | kept | Documented in the velvet_wing / patchwalker / quarry_warden headers: the feint is Intense-only on the Velvet Wing, and the 1.6 s wind-ups are longer on purpose. |
| P12 | kept | Header note in `pumpkin_mimic.gd` (spawners must not pass `dormant`). `combat_enemies.md` §12 already says it (G9). |
| P20 | done | `crossing_matron` `delayed_pounce` telegraph 1.9 (= `crossing_rules.T_DELAYED_TELE[1]`). The tell names the rattle + strand; the alt tell names the whisper + pale root (no silk / spider / thread words). desc / alt_desc add "Blows alone can't drive her off until the light has burned her twice." Descriptive only. |
| P21 | kept | No change (open points go to pending real-input checks). |
| P22 | done | `borrowed_choir`: `arena_radius` 12.4 (= `works_layout_deep.VAULT.radius`). Each attack telegraph is the choir_rules Standard value (1.3: T_SWEEP_TELE / T_RING_TELE / T_STRIKE_DELAY / T_HUSH_TELE [1]). New row `{id "strikes", kind "zone", telegraph 1.3, damage 16.0, recover 1.8, radius 1.7, tell "Short delayed strike zones are marked on the floor; step out before they chime."}`. A comment says the rules file is the source of truth. Test `test_boss_rows_describe_their_rules` reads the values from the rules / layout files. |
| P23 | done | `enemy_base` static `claim_attack_token(id)` (refused at MAX_ATTACKERS or inside another attacker's stagger; a new claim starts the stagger clock) and `release_attack_token(id)`. `attack_token_available_for(id)` drops the tokens of freed instances. `borrowed_choir` no longer touches `_attackers`: `_may_commit()` claims, committed `_enter()` (re)claims, and a non-committed state releases. Test `test_the_choir_claims_the_shared_token_table_through_enemy_base`: never a third holder, and the Choir waits for a free slot. |
| P25 | kept | No `--sandbox=choir`; `combat_sandbox.gd` is untouched. |
| P27 | kept | No change. |
| P57 | done | In trial mode the retry hint uses id `choir_retry_trial`: "The Choir picks up its song where you left it. Leave through the pale door and the echo starts afresh." Story mode keeps `choir_retry`. Test `test_retry_hint_names_the_way_out_per_mode`. |

Tests (headless, 2026-09-28, resumed run): `parse_all` -> `==== 1 tests, 0 failed ====`; `enemies_ch2` (base, bellcap, glimmer,
mimic, patchwalker, velvet, visuals, warden, wisp) -> `==== 96 tests, 0 failed ====`;
`enemies,boss_choir,data_ch2_catalogue,companions_combat,trials_choir,boss_crossing,boss_velour` -> `==== 481 tests, 0 failed ====`;
`reach_east,reach_west,world_reach,works_,manor_,trials_,horror_director` -> `==== 414 tests, 0 failed ====`; `enemies_ch2_mimic`
x3 -> `==== 10 tests, 0 failed ====` each.

Cross-group notes:
* `count_velour.gd` (~l. 885) still moves its ring mark by hand; it may switch to `telegraph_fx.move_ring(at)` (optional).
* `test_enemies_ch2_glimmer.gd` is new and has no `.uid` yet; the lead's final `--import` creates it.


## G7 Session wiring, area warm-up & music data

Files: `game/autoload/game.gd`, `game/data/music.gd`, `game/src/audio/music_selector.gd`, `game/src/audio/music_box.gd`, tests
`test_flow_ch2_rules.gd`, `test_flow_ch2_roundtrip.gd`, `test_save_v2_state.gd`, `test_music_box_selector.gd`,
`test_audio_music_selector.gd` (`test_story_ch2_ending.gd`, `test_story_ch2_goals.gd`, `test_save_v2_matrix.gd`,
`test_music_box_state.gd`, `test_music_box_nodes.gd` needed no change).

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| P34 | done | `Game.wire_session_systems()` now wires, each through `_safe_load` + a `has_method` guard (a missing module or method is skipped, never a crash): `SESSION_INIT_SCRIPTS` = mastery, `src/expeditions/expeditions.gd`, `src/audio/music_box.gd`, `src/world/areas_ch2/echo_trial.gd` (`init()` each, all idempotent), the story tracker node as before, and `src/world/story_ch2/onboarding_hints.gd` `attach(self)` (one `OnboardingHints` node under Game; `auto_tick` is off headless, so it never steps in tests). New path constants `EXPEDITIONS_SCRIPT`, `MUSIC_BOX_SCRIPT`, `ONBOARDING_SCRIPT`, `ECHO_TRIAL_SCRIPT`. Effects: a mid-run expedition save resumes in the Reach (no runner node without an active run - checked through a real `Events.area_loaded`); songs are discovered from the first eligible cue in play (before any box exists), which writes `GameState.extra["music_box"]`; the echo gift payer (G3's L08) is live from boot. Full-suite fallout in this group: `test_flow_ch2_roundtrip` compared every saved section strictly and saw `music_box` appear - it is now a GROWING section (songs known before stay known with the same first-heard record, favourites unchanged). `test_save_v2_state` / `test_save_v2_matrix` needed nothing for `music_box` (none of their cases plays music). |
| P38 | done (+2 paths) | `Game.AREA_WARMUP` gains `hallowmere_reach` (pumpkin_mimic, patchwalker, hollow_drudge, velvet_wing, bellcap_sentry, quarry_warden, lantern_moth) and `echo_trial` (count_velour, borrowed_choir, `src/world/trial/velour_trial.gd`, `choir_trial.gd`); `moonveil_manor` + count_velour; `hushed_works` + borrowed_wisp, crossing_matron, borrowed_choir. Two additions in the decision's own spirit: `brambling.gd` / `brambleback.gd` in the Reach (the lead's intent was "expedition + district enemies": data/expeditions.gd sends both, and the new table test checks every expedition enemy id through `EnemyFactory.script_path`), and `weaver_boss.gd` in `echo_trial` (the Matron's echo; normally already compiled in the Below and then skipped). No cyclic preloads among the warm-up scripts (checked: the boss sub-scripts only preload leaves - art, combat, rules); every boss / trial builder that preloads EnemyFactory is covered by the existing main-thread factory load. Timing only; prefetch stays idempotent and never blocks. Tests: the manor prefetch test now waits on a 20 s time budget instead of 900 frames (Count Velour compiles too); new `test_area_warmup_covers_the_chapter_two_enemies_and_bosses` (every entry exists, is a script of a registered area, is listed once, is never the factory; bosses per area; every expedition enemy in the Reach) and `test_prefetch_of_the_echo_trial_never_blocks` (< 1 s to start, idempotent, collected, stays compiled). |
| P06 | kept (no data change) | The Quarry Warden is an elite, not one of the four bosses: `data/music.gd BOSSES` does not map it, the selector treats its id as unknown and the Reach's ordinary combat music (m22) follows the threat. New `test_the_quarry_warden_fight_uses_ordinary_combat_music` pins it (its window is 2.4 s: the quarry's own piece m18 hands over to combat on a beat boundary, observed at 1.4 s, so the first 1.2 s window failed in the full suite; behaviour was right, the test was too tight). |
| P46 | done | The Music Box preview context moved into `data/music.gd CONTEXTS["musicbox"]` (kind `musicbox`, priority 40, playlist `~musicbox`, mode `once`, fade / exit_fade 1.5 - identical to the selector's old `PREVIEW_DEF`), with a declared placeholder playlist `PLAYLISTS["~musicbox"]` (`cues: []`, fallback `keep`) so "every context's playlist exists" holds. The selector keeps `PREVIEW_DEF` as the fallback for an older catalogue without the context, and now fills the playlist the context names (`preview_playlist()`, `PREVIEW_PLAYLIST` when none) in its OWN copy of the playlists (the shared catalogue is never written). No behaviour change. Tests: the priority test now asserts the context is in the data, equals the fallback and names a declared playlist (it used to assert the opposite: "the shared catalogue is untouched"); new `test_older_catalogue_without_the_context_still_previews`; the catalogue ordering test adds combat > musicbox > haven and "musicbox is never an area / zone base". `MusicBox.home_of()` is unaffected (the placeholder playlist has no cues). |
| P47 | kept | All four behaviours stay (safe, bounded, cozy): nothing is discovered while the Master / Music bus is muted (the selector makes no decisions while muted, so no cue starts) and a preview started while muted stays "Now playing"; a preview ended by a fight is not resumed; previewing the current piece continues it; favourites may add m11 "The Last Shift" to the Haven rotation (<= 2 favourite entries per round). Documented in the `music_box.gd` header (with the session wiring). The ARCHITECTURE / What's New wording is outside this group's files: see the follow-ups. |

Tests (headless, 2026-09-28): `parse_all` 1/1 pass. `test_flow_ch2_rules,test_music_box,test_audio_music_selector` 75 tests -> after fixes
all pass (`test_flow_ch2_rules` 19/19). Group + wired modules (`flow_ch2_roundtrip`, `story_ch2_ending`, `story_ch2_goals`, `save_v2_state`,
`save_v2_matrix`, `onboarding`, `expeditions`, `trials_flow`, `enemies_boss_trial`): 159 tests, 3 failed before the fixes below, then
`trials_flow,save_v2_state,flow_ch2_roundtrip` 30/30. 
After the P06 test fix (resumed run, 06:2x): `test_audio_music_selector` 26/26; `parse_all` 1/1; group + wired modules
(`test_flow_ch2,test_story_ch2,test_save_v2,test_music_box,test_audio_music,test_onboarding,test_expeditions,test_trials,test_enemies_boss_trial`)
378 tests, 2 failed (`test_save_v2_migration.test_future_backup_behind_a_valid_main_is_set_aside_by_the_next_save`,
`test_trials_flow.test_velour_echo_returns_to_the_ballroom_candles` - both save-file reads; rerun alone: 20/20 pass). FULL suite
(run while other fixers' suites ran in parallel): `==== 2477 tests, 3 failed, 843.9s ====`, 0 SCRIPT ERRORs; the 3 failures are
not this group's: `test_building_undo_tint.test_build_keys_never_shadow_other_actions` (fails alone too: G6's rebindable build
keys are now in `Settings.DEFAULT_BINDINGS`, so the test finds each fallback key "bound to" its own action - G6's test), and
`test_audit_persistence_flow.test_continue_with_only_a_complete_temp_file` / `test_audit_persistence_surface.test_structures_chest_crop_bed_come_back_with_their_data`
(save-file races: `test_audit_persistence` alone 13/13 pass). The earlier full run (04:50, 2475 tests) had one G7 failure - the
first P06 test window - fixed above.

Cross-group follow-ups (files this group does not own):
* Docs (lead / docs group): `docs/ARCHITECTURE.md` "Areas and loading" should list the new `wire_session_systems()` hooks (expeditions,
  music box discovery, onboarding hints node, echo trial payer) and the extended `AREA_WARMUP`; the Music Box muted behaviour (P47) belongs
  in ARCHITECTURE ("Music Box: nothing is discovered while the Music / Master bus is muted; a preview started muted still shows Now
  playing") and in `docs/player/Chapter Two - What's New.txt` (player wording, e.g. "Songs are only learned while the music is on.").
* `game/tests/runner.gd` (runner owner): add `"OnboardingHints"` to `KEEP_GAME_NODES` next to `StoryCh2Tracker`. Today the node exists
  before the runner records its baseline, so nothing is freed; if a suite ever frees and re-attaches it, the runner would free the new one
  as a stray each time (and `wire_session_systems()` re-attach it) with an ISOLATION note.
* Every suite now runs with the music box discovery listener live: a test that plays safe / explore music in play (GameState.active,
  Game.mode "playing") gets `GameState.extra["music_box"]`; tests that compare whole saves must tolerate that key (done here for
  `test_flow_ch2_roundtrip`). The full suite shows no other `music_box` fallout.
* `test_save_v2_state.test_current_objective_combines_both_layers` was adapted to G8's display rows (one status row per objective; the
  three lamp steps in order, each with at least one real objective).
* Test isolation (runner / lead): every headless run uses the same `user://test_saves/`, so fixers running suites in parallel
  race on save files (the migration, trials-flow and persistence-audit failures above pass alone). The lead's final full run
  should be the only Godot test process.
* G6: `test_building_undo_tint.test_build_keys_never_shadow_other_actions` needs updating for the rebindable build keys (skip
  an action's own binding, or check the fallback keys against the OTHER actions only).


## Integration tester (pass 2): full-suite results and fixes

Files: `game/tests/runner.gd`, `game/tests/unit/test_building_undo_tint.gd`.

| Id | Outcome | What changed / why |
|----|---------|--------------------|
| T1 | fixed (runner) | Root cause of the "parallel save races" (G7's `test_audit_persistence_*`, `test_save_v2_migration`, `test_trials_flow` failures): `_remove_stale_runs()` deleted every `user://test_saves/run_<pid>` whose pid `OS.is_process_running()` called dead, but that call only knows processes the calling process started (probed on Windows: own pid true, explorer.exe false), so every runner that STARTED wiped the live save folders of all runners already in progress. Liveness is now a heartbeat: the runner writes `run_<pid>/.heartbeat` (unix time) at start and before every suite; another run's folder is removed only when its heartbeat (or, without one, the folder's modified time) is older than `STALE_RUN_SECONDS` (3 h). Checked: a 58-test save-heavy run with five runners started 12 s apart beside it - folder kept, 0 failures; a fake folder with an old heartbeat is removed, a fresh one without a heartbeat is kept. |
| T2 | fixed (outdated test) | `test_building_undo_tint.test_build_keys_never_shadow_other_actions`: the product requirement changed on purpose (G6 D03: `build_undo` Z / `build_recolor` P / `build_variant` N are `Settings.DEFAULT_BINDINGS` now). The test now asserts that no OTHER action shares a build key and that each build action's default binding is its fallback key. |
| T3 | done (runner) | G7 follow-up: `KEEP_GAME_NODES` gains `"OnboardingHints"` (re-created by `wire_session_systems()`, never a stray). |

Tests (headless, 2026-09-28, no other Godot test process): `parse_all` 1/1. Full suite `==== 2477 tests, 0 failed, 830.6s ====`, final re-run with T1-T3 `==== 2477 tests, 0 failed, 830.8s ====` (`qa/tmp/full_integration_pass2_final.log`)
(`qa/tmp/full_integration_pass2.log`, with T2 applied), 0 SCRIPT ERRORs; ISOLATION notes unchanged from pass 1 (boss registries,
projectiles / particles, orchard drops). Timing and save suites 3x (`test_audio_music_selector, test_flow_ch2_rules, _areas,
_roundtrip, test_enemies_ch2_mimic, test_player_avatar, test_audit_persistence, test_audit_lifecycle, test_save_v2_migration,
test_trials_flow, test_enemies_perf, test_manor_, test_reach_east_cold, test_story_ch2_world, test_works_flow, test_ui_root,
test_building_undo_tint, test_music_box`): `==== 255 tests, 0 failed ====` each run (`qa/tmp/timing_suites_pass2_3x.log`).
