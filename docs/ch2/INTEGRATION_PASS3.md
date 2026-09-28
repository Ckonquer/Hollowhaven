
## G6 Appearance data palettes (preset palettes and part channels)
Files: `game/data/appearance.gd`, `game/tests/unit/test_avatar_look_build.gd`, `game/tests/unit/test_data_ch2_appearance.gd`.
The code was checked again first: `wardrobe_panel.Looks.with_outfit` copies an outfit's palette into the look when it is applied, and
saves store swatch ids, so a saved look keeps its own colours. The two channel changes (beret, capelet) re-colour those parts in any look
from that look's own palette ids. Nothing is migrated.

| id | outcome | what changed / why |
|---|---|---|
| R3-26 | done | `OUTFITS.ghostlight_party`: `hair_color` platinum -> `lavender`; palette `{primary: sky, secondary: snow, accent: lavender}` (was snow / sky / lavender). This gives a sky bodice and tulle, snow trim and underskirt, lavender Mary Janes and lavender hair. The wings and glow pins keep their fixed colours. Re-render (below): no longer an all-white figure, and it matches proposal_palettes.png column 2. |
| R3-27 | done | `OUTFITS.pumpkin_patch`: `hair_color` strawberry -> `espresso`; accent cocoa -> `moss` (caramel / cream / moss). As expected, the harvest skirt (`skirt: accent`) and the lace-up boots (`boots: accent`) turn moss green. The leaf clip stays orange (fixed `e9a15b`), and so do the cardigan's pumpkin details. The half-up ribbon is now green. This matches proposal_palettes.png column 4. |
| R3-28 | done | `PARTS.mushroom_beret.channels` `{beret: primary}` -> `{beret: accent}`. In the Mushroom Dungarees preset the beret is now berry red with cream spots (a toadstool), not the moss of the dungarees. With the legacy palette it is plum. |
| R3-29 | skipped (decision) | `moonflower_dress` palette primary stays `snow`. AV-16 is already fixed by the appliques, and the starter look stays as reviewed. |
| R3-30 | done | `PARTS.chorister_capelet.channels` `{capelet: primary, collar: secondary}` -> `{capelet: secondary, collar: accent}`. The wardrobe tile shows the first channel (`wardrobe_panel._part_color`), so the tile is now the secondary swatch. Over the 7 primary-coloured tops the render shows exactly that: no swap is needed, and the collar and scalloped hem are accent. The pin in `test_avatar_look_build.gd` (Echo Trial capes test, formerly line 215) is now `[secondary, accent]`. Remaining difference, by design: over the 5 secondary-coloured tops (puff / ribbon / witch / moth blouse, striped tee) the AV-10 contrast guard in `accessory_builder._cape` still swaps the capelet to the collar colour (accent), or to choir cream, so it never disappears into the top. There the tile (secondary) and the render (accent) differ. Before this change the mismatch applied to the 7 primary tops. |

Regression tests (new):
- `test_data_ch2_appearance.test_pass3_preset_palettes_and_channels` pins the R3-26/27/28/30 data. It also checks every outfit preset with two generic rules. First, the suggested hair colour differs from the main (primary) cloth by at least the avatar's own `_close` metric (sum |dRGB| >= 0.18). The old Pumpkin Patch fails this: strawberry on caramel = 0.14. Second, no preset has both near-white hair and near-white main cloth (luminance > 0.8). The old Ghostlight Party fails this: platinum 0.89 on snow 0.97.
- `test_avatar_look_build.test_pass3_preset_palettes_render_as_reviewed` checks the colours on the built avatar:
  - Mushroom Dungarees: the hat unit draws berry and no moss.
  - Pumpkin Patch: espresso hair, caramel upper, a moss skirt with no cocoa, moss boots, and the leaf clip's fixed orange.
  - Ghostlight Party: lavender hair, and both the upper and the lower draw sky and snow.
  - Chorister Capelet over each of the 7 primary-coloured tops (palette rose / mint / sky): mint (the tile colour) and sky are drawn, and no rose.

  The beret and capelet assertions would fail on the old channels (moss beret, and rose on the capelet through the guard swap).

Tests (Git Bash, repo root):
- `tools/test.sh test_data_ch2_appearance`: `==== 10 tests, 0 failed, 0.4s ====`
- `tools/test.sh test_avatar_look_build`: `==== 13 tests, 0 failed, 2.3s ====`
- `tools/test.sh test_avatar_look` (build / fit / legacy / motion): `==== 37 tests, 0 failed, 7.0s ====`
- `tools/test.sh test_player_avatar`: `==== 4 tests, 0 failed, 0.3s ====`
- `tools/test.sh parse_all`: `==== 1 tests, 0 failed, 10.4s ====`
- `tools/test.sh appearance`: `==== 49 tests, 1 failed ====`. The failure is `test_ui_appearance_wardrobe.test_preview_renders_in_its_own_world_and_frames_krystal` ("viewport follows the widget ((368.0, 568.0))"). It is not caused by this group: the in-progress UI visual fix (uncommitted `wardrobe_panel.gd`) narrowed the preview from 440 to `PREVIEW_W := 400.0`, and the test expects a viewport of at least 380 wide. That belongs to the UI fixer.

Visual check (second monitor, muted, no focus; bounded with `timeout 150` and `--max-seconds=140`; the preview-stage lineup helper was copied from `qa/tmp/visual/fix_avatar`). The sheets are in `qa/tmp/visual/pass3_g6/`:
- `after_presets.png` (front and back): Ghostlight Party, Pumpkin Patch, Mushroom Dungarees, legacy + capelet, Velvet Vampire + capelet, Moon Moth + capelet.
- `after_beret.png` (head close-up, three views): the preset beret is berry with cream spots, and on the legacy palette it is plum.
- `after_capelet.png` (back views, bob hair):
  - legacy: a sunflower capelet with a plum hem over the teal jacket
  - Velvet Vampire: snow with plum over berry
  - Moon Moth: the guard swaps it to slate with a cream hem over the cream blouse
  - Mushroom Dungarees: the guard swaps it to berry with a cream hem over the cream tee

All of them read clearly. The Ghostlight and Pumpkin looks match the approved proposal columns.

Follow-up outside this group's files: the comment at `game/tests/unit/test_avatar_look_fit.gd:258` ("legacy palette: teal jacket = primary = capelet channel") is now stale. Its loop still passes: the moon_moth_shawl case exercises the guard. The owner of that test should reword the comment.

## G5 Combat feedback, enemy text & test robustness
Files: `game/src/combat/combat.gd`, `game/tests/unit/test_combat_core.gd`, `game/data/enemies.gd`, `game/tests/unit/test_data_ch2_catalogue.gd`,
`game/tests/unit/test_trials_harness.gd`, `game/tests/unit/test_audit_release_packaging.gd`. I checked the code again before changing it.

| id | outcome | what changed / why |
|---|---|---|
| R3-06 | done | `crossing_matron` `desc` / `alt_desc`: "...until the light has burned her twice." became "...until the light has burned her three times, once in each phase." This matches `crossing_rules.gd` (`EXPOSURES_TARGET = 3`, one exposure per phase; `HP_FLOOR` has 3 bands). `test_data_ch2_catalogue` now asserts the new wording in both strings, that "twice" is gone, and that `EXPOSURES_TARGET == 3` and `HP_FLOOR.size() == 3`, so the text can't drift from the rules unnoticed. |
| R3-08 | done (applied as scoped) | `Combat.melee()`: a swing by an attacker in group `player` that hits nothing, where a living `enemy` target (health, not dead) was dropped only because the line of sight was blocked, shows ONE glance spark at the nearest obstacle point. It is nudged 0.08 m (`GLANCE_NUDGE`) toward the swing so it isn't buried in the wall. It is visual only: the spark reuses `HitFx.spark()`'s burst (same colour and parameters) but NOT its `hit_soft` sound, because that sound is also a real light hit and would read as a landed blow. No damage, hint or hitstop. No spark when any target in the swing was hit or answered through `on_hit_blocked` (never two glances per swing), for enemy swings, or for non-`enemy` groups. New helper `line_of_sight_block(space, from, to, exclude, mask) -> Variant` (the obstacle point, or null when clear) uses the same ray query as `has_line_of_sight`, which keeps its signature and verdict. Both now build the query in `_los_query()`. Melee still casts one ray per candidate. The counters `Combat.los_glances` / `last_los_glance` exist because headless tests draw no particles. |
| R3-09 | done | `test_trials_harness.win_velour()`: `health.set_hp(1.0)` right before the finishing `apply_damage(99999)`. The call comes after the candle stagger, which lifts his mask floor. So the blow is always the defeating one, and `velour_health.window_room` can't trim it, whatever hp the phase jump left him at. |
| R3-22 | done | `test_engine_window_starts_in_the_default_display_mode` reads `display/window/size/mode` from `res://project.godot` with ConfigFile (what ships) and keeps the same assertion. On the live tree, ProjectSettings gives 0 (the local override.cfg) and project.godot gives 3 (checked with a headless one-off script). New `test_export_presets_do_not_ship_override_cfg`: for every `[preset.N]` in export_presets.cfg, no `include_filter` pattern matches `override.cfg`. |

New tests (test_combat_core): `test_line_of_sight_block_returns_the_obstacle_point`,
`test_player_swing_at_enemy_behind_wall_shows_one_glance_spark` (2 enemies behind the wall: 0 hits, hp 100, no knockback, no
on_hit_blocked, exactly 1 spark per swing, spark at z = near face + nudge), `test_enemy_swing_behind_wall_makes_no_spark` (also a player swing at a
non-enemy group), and `test_unblocked_player_swing_is_unchanged` (hp 88, knockback, no spark; with one open and one walled enemy, only the
open one is hit and there is no spark; if the open one is armoured, it gives its own on_hit_blocked and there is no LOS spark).

Evidence (headless, `tools/test.sh <filter>`):
- `combat_core` 16 tests, 0 failed; `data_ch2_catalogue` 19/0; `audit_release_packaging` 3/0; `trials` 31/0; `velour` 68/0
- `audit_combat` 8/0; `boss_` 230/0; `equipment_` 32/0; `player_node` 29/0; `wand_` 25/0; `companions_rules` 10/0; `stats_core` 18/0; `parse_all` 1/0
- `enemies_` 317 tests, 1 failed: `test_enemies_review.test_boss_killing_blow_skips_the_window_cap_climb` ("expected gone got climb"). This is
  not caused by G5. The test drives `weaver_boss` health directly (no Combat.melee). The uncommitted, in-progress `weaver_boss.gd` edit (another
  owner, 09:08) now trims "a would-be lethal blow included" to the window cap, which contradicts that test. That owner should resolve it.

Visual (second monitor, 1920x1080 at 1920,0, muted, scratch settings/saves, a scratch `--preview=` scene: a wall, an enemy capsule behind it,
a "player" node swinging): console `LOS_VIS hits=0 glances=1 at=(0.0, 0.91, 1.23) enemy_hp=100.0`, and 2 glances after a second swing.
Frames looked at: before the swing there is no spark. At 3 frames, about 6 warm sparks burst off the wall's near face at chest height, in
front of the wall and not buried in it. After 1 s they are gone. The close-up of the second swing shows one spark cluster on the wall face.

## G2 Surface arrival spawns (Woods waygate, Tobin's side door)

Files: game/src/world/surface/annexes.gd, game/data/world_layout.gd, game/src/world/surface/c1x/tobin_door.gd,
game/tests/unit/test_flow_ch2_areas.gd, game/tests/unit/test_annex_surface.gd, game/tests/unit/test_camera_spawn_clearance.gd.

- **R3-32 (applied).** `Annexes.WAYGATE_SPAWN_OFFSET` 3.0 -> 5.8. The zone centre stays at offset * 0.5 (2.9 m) and the radius
  stays 4.5 m, so both the gate and the spawn are 2.9 m from the centre (1.6 m inside the edge). New helpers
  `waygate_spawn_site()` / `waygate_zone_centre()` are used by build_waygate. `clear_grass` now also thins grass
  around the zone centre (4.5 m), so the grass is thinned around both the gate and the arrival spot. The legacy
  vegetation plan digest is unchanged (bd86320366013834cd23feefa16c4703). Updated the "3 m south" comments in annexes.gd
  and world_layout.gd. test_flow_ch2_areas: the spawn is asserted at `site.y + Annexes.WAYGATE_SPAWN_OFFSET` (and the offset is pinned
  at 5.8), the zone centre and radius are asserted, and a new capsule-walk check confirms the path from the spawn to the arch is clear.
  Camera test: 'waygate' is now in ARRIVALS['surface'] and the comment is fixed. The test catches the old value: at 3.0 it
  failed with "surface/waygate: the camera arm has room (2.52 m, needs 3.0)".
  Second-monitor render (`--area=surface --spawn=waygate`): Krystal stands centred, facing the ruin. Nothing is at the lens
  and the arch is behind her. A reverse free-cam view shows the arch just behind her on thinned grass.
- **R3-33 (applied, with a deviation from the recommendation).** `DOOR_SPAWN_LOCAL` (6.8, 4.4) -> **(6.8, 7.8)**, not 7.4:
  at 7.4 the new camera assertion still failed ("surface/annex_door: ... 8% within 2 m: TobinDoor/@MeshInstance3D" = the
  lintel / lantern arm). 7.6 measured 0% and 7.8 was chosen for margin. The spawn is 5.6 m out from the door (walk < 6 m),
  still facing the apron (yaw + PI). It is clear, dry, in bounds and in the mine_mouth zone (world (55.61, -63.47), 10.6 m
  from the mine_mouth centre). The header comment is updated. 'annex_door' is added to SURFACE_CH2_SPAWNS and ARRIVALS['surface'].
  test_door_and_hatch_are_usable_from_their_spawns: only the door half changed. The probe now stands 2.0 m in front of the
  door on the spawn->door approach, and a new helper `_door_approach_point` asserts the walk is < 6 m and clear, with capsules
  every 0.5 m. The hatch half is unchanged. Also: the clear-approach check in test_door_hatch_and_spawns_on_the_surface is
  now sampled every 0.5 m, and test_sites_follow_the_mine_frame pins the spawn 4.5-6 m straight out from the door.
  A camera blocker was not needed. Second-monitor render (`--spawn=annex_door`, 5 s / 8 s): a clean third-person frame
  looking out over the apron and the mine path. A reverse free-cam view shows the TOBIN door a few clear steps behind her.
- Tests: `tools/test.sh test_annex_surface,test_flow_ch2_areas,test_camera_spawn_clearance` -> "==== 22 tests, 0 failed";
  camera lines "surface/waygate: arm 5.00 m (need 3.0) ... 0%", "surface/annex_door: arm 5.00 m (need 3.0) ... 0%",
  "surface/annex_hatch: arm 5.00 m (need 1.6) ... 0%". Related suites (annex_flow, flow_ch2_waygate, c1x_world,
  world_surface, companions_areas, mastery_landmark_discovery, flow_ch2_rules, flow_ch2_roundtrip) -> "==== 81 tests, 0 failed";
  (ui_map_areas, ui_map_telemetry, companions_courage, companions_node, story_ch2_flow) -> "==== 69 tests, 0 failed";
  `parse_all` -> "==== 1 tests, 0 failed".

## G4 Boss creature props (trip posts, Crossing scar & mantle, Choir false lights)
Files: `game/src/enemies/boss_hazards/hazard_field.gd`, `game/src/enemies/crossing/matron_look.gd`, `game/src/enemies/choir/choir_lights.gd`,
`game/tests/unit/test_creatures_visual_fixes.gd` (`bat_swarm.gd` untouched). I checked the code again first. `hazard_art.build_post`
(pale stake / root peg) already existed but `hazard_field._build_posts()` still built the old dark blob + thin band. `weaver_visual.abdomen_node()`
already existed (read-only accessor). `borrowed_choir.gd` only uses `lights.gutter_false` / `place_false`, the `_false` array and the
`FalseLight_%d` names, and all of those are kept.

| id | outcome | what changed / why |
|---|---|---|
| R3-36 | done | `_build_posts()` builds each holder with `Art.build_post(holder, alt)`. The unused `post_mat` / `strand_mat` locals and the now-unused `Kit` preload are gone. The rebuild on an arachnophobia swap is kept (`set_alt` -> `_build_posts`). The old posts are now `remove_child`-ed before `queue_free`, so a swap never shows or counts both sets for a frame. Holders are named `TripPost0..5`; before, the duplicate names were auto-renamed to `@Node3D@N`. |
| R3-37 | done | `_build_mantle()`: the `EmberScar` is `Kit.torus(0.29, 0.355)` with emission 0.6, parented to `inner.abdomen_node()` at (0, 0, -0.05), rot (90, 0, 0), scale (1, 1, 0.865), so it rides the abdomen's bob and tip. When there is no abdomen yet (the body is built outside the tree), it falls back to the old `_extras` placement, and `_ready` rebuilds onto the abdomen. Mantle: `MANTLE` alpha 0.75 -> 0.9, and `STREAMERS := 6` strips (0.1 wide, lengths 0.8 / 1.05 / 1.3 x scale, yaw spread 8 deg), as in the report's prototype. Swap: `_build()` clears `_scar`; the scar leaves with the old body (removed from the tree at once, then freed), with none on the Hollow Mother and exactly one again after the round trip. New read-only helpers: `scar_node()`, `streamer_count()`. |
| R3-38 | done | Each false light is now the report's paper lantern (`_build_lantern`): a glowing paper globe (0.3, y x1.08), 4 rib tori `Rib0..3` (0.285 / 0.315, `c0703a`, 45 deg apart), a wooden `Cap` and `Base` (`8a5a3c`), a `Hanger` loop, and the ribbon at y -0.34. The dark `3b3238` caps that read as eyeballs are gone. It is still emissive only (no Light3D). Shadows are off on all parts. `FalseLight_%d`, `_false`, `_false_home` and the API are unchanged. |
| R3-39 | skipped (decision) | No `set_high_vis(true)` forced on the Gallery lane marks. CR-04 is already fixed by the contrast band and the bigger, lighter bats (`test_gallery_bats_are_bigger_and_lighter`, `test_roots_colour_and_contrast_bands`), and forcing the outline would override the player's high-visibility comfort setting. |

Regression tests (new, in `test_creatures_visual_fixes.gd`; with the old sources restored the file does not even parse, because of the new constants):
- `test_hazard_field_posts_are_stakes_in_both_looks`: a real hazard field (6 posts). In both looks, reached through the live `Settings` swap, each post has 4-7 meshes, no noise blob (ArrayMesh), is taller than wide (y > 1.2 x), stands on its floor point, and has its strand in the top 40%. Arachnophobia has 3 root-foot cones per post and silk has none. There is exactly one set of posts after each swap and after swapping back.
- `test_crossing_scar_sits_on_the_abdomen_under_a_fuller_mantle`: the scar is a descendant of `abdomen_node()`, centred on it, no wider or taller than the abdomen blob (x 1.12), a flat band, with emission 0.6. There are 6 `Streamer*` meshes at alpha >= 0.9. `set_alt(true)`: no scar and no streamers in the tree, and the old scar instance is freed one frame later. `set_alt(false)`: exactly one scar, on the new abdomen, and 6 streamers.
- `test_choir_false_lights_are_paper_lanterns_not_eyeballs`: 3 `FalseLight_%d` nodes, each with 4 torus ribs, Paper / Cap / Base / Hanger / Ribbon, the ribbon at y -0.34, no Light3D, and no mesh colour with luminance <= 0.3 (the old caps were ~0.2).

Tests (Git Bash, repo root, headless):
- `tools/test.sh creatures_visual_fixes`: `==== 15 tests, 0 failed, 0.8s ====`
- `tools/test.sh parse_all`: `==== 1 tests, 0 failed, 11.1s ====`
- `tools/test.sh boss_hazard,boss_phases,boss_crossing,boss_choir,trials_choir,weaver,matron`: `==== 144 tests, 0 failed, 22.9s ====`
- `tools/test.sh enemies_boss,trials,works_deep,enemies_review,audit_combat`: `==== 203 tests, 1 failed, 42.4s ====`. The failure is `test_enemies_review.test_boss_killing_blow_skips_the_window_cap_climb` ("expected gone got climb"), and this group did not cause it. It fails the same way with `hazard_field.gd` restored to HEAD (`tools/test.sh test_enemies_review`: `==== 13 tests, 1 failed ====`, both ways). The test runs the Weaver's phase-1 scorched window, where no hazard field is involved, so it traces to the in-progress uncommitted `weaver_boss.gd` (+178 lines, another fixer's file). That fixer should check it.

Visual check (second monitor, `--qa-no-focus --qa-window=1920,0,1920,1080 --qa-mute`, own `--settings-file` / `--save-dir` in a scratch dir, `--max-seconds` + `timeout`, preview-stage helper `qa/tmp/visual/fix_creatures/fx_bossrun.gd` used read-only, 0 SCRIPT ERRORs in every log). Key frames are in `qa/tmp/visual/pass3_g4/`:
- `weaver_p2_posts_wide.png` and `weaver_p2_posts_trip_lines.png` (Echo Trial, `--matron-phase=2`): six pale stone pegs with a glowing band near the top, and the trip-lines strung between them. They read as stakes, not as critters with eyes.
- `weaver_p2_posts_arachno.png` (the same with `--settings=arachnophobia=true`, the Hollow Mother): pale root stakes with little root feet.
- `crossing_scar_stranded.png` and `crossing_scar_cling.png` (Weaver's Crossing, silk look): the ember scar is an orange band on the abdomen surface, both stranded on the deck and clinging above it. It no longer floats off the body as a hoop. Six opaque silk streamers trail behind her.
- `choir_c_lanterns.png` (Choir Vault, `--choir-phase=3`, `c_open`): the false lights are ribbed paper lanterns with a wooden cap and hanger, a base and a ribbon, and no eyeball read. The true flame's lit sector and the dark floors under the lanterns are unchanged.

## G3 Works deep interiors (lift signs, crossing-gate sign, resonator prompts, trial order board)
Files: `game/src/world/works/rooms_deep.gd`, `game/src/world/works/deep/deep_lift.gd`, `game/src/world/works/deep/resonator.gd`,
`game/src/world/trial/choir_trial.gd`, `game/tests/unit/test_works_interior_visuals.gd`, `game/tests/unit/test_works_resonator_prompts.gd` (new).
I re-checked the code first. `choir_resonance.gd` switches the plates with a plain `set("enabled", ...)`, so a prompt that reads `enabled` follows every phase change without any other hook.

| id | outcome | what changed / why |
|---|---|---|
| R3-19 | done | `resonator.gd`: each plate's Interactable now has `text_func = plate_prompt.bind(sid)`. It returns `{}` while `enabled` is false (the Choir's Phases A and C), and otherwise returns `{"text": "Strike the <Name> plate", "enabled": true}`. `below_interactable.interact()` ignores an empty prompt, so a hidden plate cannot be struck. `strike()` is unchanged (it still returns "idle" while disabled). choir_arena / borrowed_choir / interaction_probe were not touched. |
| R3-35 | done (cause differs from the request) | The lump was not part of the gate-room dressing. It was a rock from the **winch hall's east-wall** `dress_room_rock`. That wall backs onto the 4 m gate room, and rocks dressed just above its 3.4 m gate opening sit inside the gate room. One of them, centred at (62.88, -13.72, 1.89), hung into the doorway below 3.4 m. It cut the right end of "SERVICE BRIDGE" from the arrival camera at (59.42, -15.09, 1.26). Lowering the board by 0.15-0.25 m would not have fixed this: the ray to the label's centre line at the right end was already blocked. Fix: the hall is dressed through the new `_dress_rock_as(b, id, open, ...)`, with the east opening kept clear up to the gate room's height (`h` 4.0) for the dressing only. The walls keep their real 3.4 m opening. The dressing RNG is then set to where the unchanged dressing would have left it (a replay on a throw-away builder, which is never finished), so every room dressed after the winch keeps exactly its rocks. Three rocks no longer hang into the doorway. The board, label and rods are unchanged, so `test_crossing_gate_sign_hangs_over_the_doorway_ahead` passes as before. |
| R3-41 | done | `deep_lift.gd` now fits its own sign with `Art.fit_label(l, SIGN_TEXT_WIDTH = 1.8)`. The false lift's mirrored sign is `double_sided = true`. There is a new optional setup key `sign_pos` (local board centre, default `SIGN_POS` (0, 3.55, -1.05), the old board position; the label sits 5 cm in front). Board and label are named `SignBoard` / `Sign`. `rooms_deep.gd`: the wrong-landing lifts pass `sign_pos = (0, SIGN_ON_LINTEL_Y, lintel_z)`, which is the same place `_move_sign()` used. `_move_sign()`, `_fit_sign()` and both of their calls (the winch cage and the landing lifts) are removed. The BELLHOUSE (choir_arena) and REFUGE (throat) lifts keep the defaults; their short signs stay at 34 px. |
| R3-42 | done | `choir_trial.gd _order_board`: `Art.symbol(..., nm, sheet_c)` with `sheet_c = Color("efe0bd")` (the sheet colour, now one variable shared with the sheet material). The Moon's bite is painted in the sheet colour, so the glyph reads as a crescent. |

Regression tests (new):
- `test_works_resonator_prompts.gd`:
  - `test_prompt_shows_while_enabled_hides_while_disabled_and_comes_back`: each plate shows "Strike the <Name> plate". While disabled the prompt is `{}` and interacting does not strike. After re-enabling, the prompt is back and a strike counts again.
  - `test_choir_phases_hide_and_restore_the_prompts`: the real `choir_resonance.gd` `disable()` hides the prompts, `begin()` shows them, and `release()` restores them.
- `test_works_interior_visuals.gd`:
  - `test_crossing_gate_sign_top_is_in_clear_view_of_the_arrival_camera`: the real follow rig is snapped at `crossing_gate` (winch exit veil burned). Ten rays run from the camera to the label's top line (the box top and the middle of the first line, at 5 points along it). They are checked with a physics ray (mask 1|32) and with a triangle test against every visible mesh and every batched room visual. Headless, a MultiMesh reports only identity instance transforms, so the test builds the rooms on a bare `area_base` and keeps the builder's batch list. A sanity ray asserts that the check sees the gate floor. It failed on the old dressing (3 rays blocked by the winch blob at (62.88, -13.72, 1.89)) and passes now.
  - `test_winch_keep_clear_over_the_gate_keeps_the_dressing_rng`: winch rocks hanging into the doorway go from 3 before to 0 after. The RNG state after the dressing is identical, and only a few hall rocks go.
  - `test_a_lift_built_on_its_own_fits_its_sign_and_keeps_the_false_one_drawn` covers:
    - a stand-alone "true", "false" and "bell" lift with a long sign: it fits within 1.8 m;
    - the false sign is mirrored and double-sided; the others are single-sided;
    - a short sign stays at 34 px;
    - `sign_pos` moves the board and the label.
  - `test_trial_order_board_moon_is_a_crescent`: the trial board's Moon bite has the sheet colour (luminance > 0.5). It failed before the change with (0.12, 0.09, 0.12).
  - The existing `test_lift_signs_fit_their_boards_and_are_seen_from_the_landing` still passes (winch cage 20 px, landing lifts 22 px, 1.78 m).

Tests (Git Bash, repo root):
- `tools/test.sh works_resonator_prompts`: `==== 2 tests, 0 failed, 0.2s ====`
- `tools/test.sh works_interior_visuals`: `==== 11 tests, 0 failed, 1.4s ====`
- `tools/test.sh test_works_,resonator,choir,trials_,camera_spawn_clearance,flow_ch2_rules,hushed`: `==== 237 tests, 0 failed, 52.0s ====`. This covers all test_works_* suites, boss_choir_*, trials_*, camera_spawn_clearance and flow_ch2_rules.
- `tools/test.sh parse_all`: `==== 1 tests, 0 failed, 10.3s ====`

Visual check: second monitor, `--qa-no-focus --qa-window=1920,0,1920,1080 --qa-mute`, own `--settings-file` / `--save-dir` in a scratch dir, bounded with `timeout 90` + `--max-seconds`. Some runs used the camera helper `qa/tmp/visual/fix_cameras/cam_director.gd` (read-only). Those runs log only the helper's known `preview_stage.gd:72` SCRIPT ERROR (it reparents itself out of the preview stage; this line is also in the original fix_cameras logs). The plain `--area` run has 0. Key frames are in `qa/tmp/visual/pass3_g3/`:
- `crossing_gate_arrival_before.png` and `crossing_gate_sign_before_crop.png` (`--area=hushed_works --spawn=crossing_gate`, veil burned, before the fix): a brown winch rock cuts "BRIDGE" to "BRID".
- `crossing_gate_arrival_after.png` and `crossing_gate_sign_after_crop.png`: "SERVICE BRIDGE / MIND THE RAILS" is fully readable, with the rods above the board.
- `winch_east_wall_after.png` (from inside the hall): the east wall stays rock-dressed round the gate, and there is no bare patch.
- `choir_trial_order_board.png` (Choir echo trial, Krystal at the corridor board): the Moon is a crescent. The numbers, names and title read correctly from the front (single-sided labels).
- `choir_trial_corridor_arrival.png`: the corridor arrival with the board on the left wall.
- `wrong_landing_lift_signs.png`: both lintel signs are in place. "LIFT - REFUGE LEVEL" reads normally over the lit cage, and the false lift's sign is drawn mirrored (sign_pos gives the same place as the old `_move_sign`).
- `winch_cage_sign.png`: "WINCH CAGE - DOWN" fits its board (fitted by the lift itself now).

## G1 Docs, decision records & project layer name (run last, after G2-G6)
Files: `docs/ARCHITECTURE.md`, `docs/ch2/maps/combat_enemies.md`, `docs/ch2/maps/state_save_data.md`, `docs/ch2/maps/world_areas.md`,
`KNOWN_ISSUES.md`, `QA_REPORT.md`, `PROJECT_STATE.md`, `game/project.godot`, new `game/tests/unit/test_project_layer_names.gd`.
Code re-checked before writing (live tree, 09:30-09:45): `weaver_boss.gd` (`WINDOW_CAP` 0.4 / `LATE_WINDOW_CAP` 0.15, `window_cap()`,
`next_phase_hp()` = 144 / 72, the trim in `_on_damaged` before the window-end and death tests, `_bank_scorch` / `scorch_banked()`, hint
`boss_banked`, `_banked` cleared by `reset_fight`); `crossing_rules.gd` / `crossing_matron.gd` (`HP_FLOOR` [0.6, 0.35, 0.2],
`scorch_damage`, `window_room`, `hp_floor()` 0 without a Lantern, `is_engaged()` / `is_primed()` / `_end_round()`, `_step = 0` in
`reset_fight` and `_change_sides`, `RETREAT_RUN_MAX` 3.0); `quarry_warden.gd` (`EXPOSE_CAP` 0.35 of 300, `PULSE_FLOOR_RATIO` 0.3,
`_end_exposure(capped)` resets poise, pulse reach = 5 m × 0.8, `reset_encounter` clears `_pulses_owed`); `velour_health.gd` /
`count_velour.gd` (`window_room`, `dealt < hp` exception, `WINDOW_CAP` 0.16, drain states in `VULNERABLE`); `enemy_base.gd`
(`LOST_SIGHT_GIVE_UP` 5, `lose_sight_seconds()` INF for elite / boss, `unseen_time()`, reset on sight and on her hit); `game.gd`
(`is_landmark_zone`, `release_prefetches` in `quit_game` and `_on_close_requested`); `annexes.gd` `mark_helper_zone`; `mastery.gd`
`mark_legacy_landmarks` / `data/mastery.gd` `LEGACY_LANDMARKS`; `chapter_log.gd` (`hint_when`, `from_dict` narrowing); `camera_block.gd`
and its four callers; `resource_node.gd` `_settle_depleted` safety net; `reach_vegetation.node_params`. R3-34's mask claim re-checked:
every `PhysicsRayQueryParameters3D.create` / `PhysicsShapeQueryParameters3D` / `SpringArm3D` in `src/` and `autoload/` gets an explicit
mask (six `create()` calls without a mask argument set `collision_mask = 1 | 32` on the next line; `music_director.gd` passes it on
its continuation line).

| id | outcome | what changed / where |
|---|---|---|
| R3-04 | done | `combat_enemies.md` §7: the old "40% cap, no phases beyond this" line is marked as the Chapter One numbers and followed by a "Pacing since CH2-003" paragraph (40 % phase 1 / `LATE_WINDOW_CAP` 15 % = 36 HP in phases 2-3 via `window_cap()`, the overshooting blow trimmed before the death test incl. a lethal one, the 144 / 72 stop via `next_phase_hp()`, the banked scorch with `scorch_banked()` / hint `boss_banked`, dropped on fall / leave); Risks list updated (the pins now live in `test_enemies_boss_pacing`). ARCHITECTURE's Weaver section states no cap, so the one-liner went into the Chapter Two enemies bullet instead. |
| R3-05 | done | ARCHITECTURE Chapter Two enemies bullet and `combat_enemies.md` §12 Crossing paragraph: `HP_FLOOR` [0.6, 0.35, 0.2] before exposures 1 / 2 / 3 (with a Lantern), scorch clamped to the floor of its exposure, a win takes three exposures; the engagement rule (committed = a dropped pounce / delayed pounce or, phase 3, a release whose sacs opened; before that the flare primes the anchor, hints `boss_crossing_primed` / `_primed_brood`, the next pounce landing exposes her), `is_engaged()` / `is_primed()`, each rotation opens with its new attack after the thread cast, a reset clears the primed anchor and commitment, `RETREAT_RUN_MAX` 3 s. `INTEGRATION_PASS2.md` untouched. |
| R3-10 | done (decision: kept as implemented) | `combat_enemies.md` Velour paragraph "Window cap (pass 3, CH2-013)": cap applied before the blow via `velour_health.window_room`, the drain-breaking blow counts, a blow that defeats him outright is never trimmed; the Weaver / Warden difference recorded as accepted. One clause in ARCHITECTURE's bosses list. |
| R3-12 | done | `combat_enemies.md` Warden row: `EXPOSE_CAP` 0.35 (105 HP, capping blow trimmed, exposure ends at once), `_end_exposure` resets poise, owed pulses at 66 % (4 m reach), `PULSE_FLOOR_RATIO` 0.3 + `hint_quarry_warden_pulses`, retry clears it, the API list. KNOWN_ISSUES: 2-3 exposures with early gear (new "Fight pacing rules" bullet) and the real-input estimate replaced by the bot's 40 s. |
| R3-16 | done (decision: accepted as engine-internal) | KNOWN_ISSUES "Developer logs only" bullet with the `qa/tmp/bot/s1/vfix_verbose` evidence; QA_REPORT §10.3 marks CH2-011 partly fixed. |
| R3-17 | done (decision: kept as implemented) | `state_save_data.md` §14 "Legacy landmarks" next to the mastery legacy credit, with verify's S1 result (Wayfinding 105 XP, rank 2 = 110); one KNOWN_ISSUES line. |
| R3-18 | done (decision: kept as implemented) | `combat_enemies.md` §12 "Added in pass 3" (rule, 5 s default, data key, resets, INF for elite / boss, save / travel effect, the test) and an ARCHITECTURE bullet; the wall case is in KNOWN_ISSUES' real-play list (R3-49). |
| R3-31 | done | KNOWN_ISSUES avatar bullet rewritten (AV-19 hover + folding witch hat + the three roll-lift numbers, AV-11 sprint slits and knees, AV-12 paper lantern pack); the braided-crown-through-helm note removed after a re-render (`qa/tmp/visual/g1_pass3/crown_helm_recheck.png`: no hair through any helm or hood); the cardigan-hem note re-checked by a render (`armor_hem_recheck.png`) and KEPT, narrowed: buttons, pockets and plain hems are covered (AV-04), but the Cloud Cardigan's fluffy hem and the Ruffle Bodice's white collar still show round every body armor set. `.uid` bullet corrected: the planned end-of-pass-2 import (D09) never ran - 398 of 704 scripts have no `.uid`, incl. `camera_block.gd`, `creature_fx.gd`, the new tests and `tests/fixtures/prefetch/*`. |
| R3-34 | done | `project.godot` `3d_physics/layer_10="camera"`; ARCHITECTURE rule 11 gains camera=512 (only `CameraRig.COLLISION_MASK` 1\|32\|512 includes it; new queries must set explicit masks). New test `test_project_layer_names.gd` (layer names = rule 11, `CameraBlock.LAYER` = layer 10, rig mask, a blocker is layer-512-only with mask 0). |
| R3-48 | done | QA_REPORT §10 (bots, snapshot suite 2534 / 0, the 17-bug table with regression tests and bot confirmation, CH2-011 partly fixed, bot run folders, fight durations, the visual groups' fixed / partly counts with before / after folders, what was only rendered, G2-G6 outcomes, the open red test); PROJECT_STATE status, tests and "Next steps" item 0 (R3-03, R3-07, R3-23, R3-43, R3-44, R3-47, R3-49, R3-50). |
| R3-51 | done | One or two lines each: `hint_when`, the lamps group and the `from_dict` narrowing (`state_save_data.md` §14 + ARCHITECTURE quest-rows bullet); `Game.is_landmark_zone` / `mark_helper_zone`, `Game.release_prefetches()`, the camera blockers (incl. G2's new surface spawn offsets), `_settle_depleted` and `reach_vegetation.node_params()` (`world_areas.md` §8 + ARCHITECTURE "Areas and loading"); `velour_health.window_room` (`combat_enemies.md` §12). |

Tests (Git Bash, repo root, headless):
- `tools/test.sh test_project_layer_names` -> `==== 2 tests, 0 failed, 0.1s ====`. Negative check: with the `layer_10` line removed from
  `project.godot` -> `==== 2 tests, 1 failed ====` ("layer_names/3d_physics/layer_10 is named as in rule 11 expected camera got "); the
  line was restored byte-identical (`git diff`: 1 insertion).
- The suites behind every rule documented here: `parse_all, test_project_layer_names, test_camera_spawn_clearance,
  test_audit_release_packaging, test_enemies_lost_sight, test_mastery_landmark_discovery, test_flow_quit_prefetch,
  test_enemies_boss_pacing, test_boss_crossing_pacing, test_enemies_ch2_warden, test_boss_velour_qa_fixes, test_save_v2_chapter_log`
  -> `==== 97 tests, 0 failed, 15.2s ====` (one note: `ISOLATION test_boss_velour_qa_fixes: Game._bosses was ["count_velour"]`).
- `tools/test.sh test_enemies_review` -> `==== 13 tests, 1 failed ====`: `test_boss_killing_blow_skips_the_window_cap_climb` ("expected gone
  got climb"), the same failure G4 and G5 reported. Not a G1 file (see cross-group notes).

Visual (second monitor, `--position 1920,0 --resolution 1920x1080 -- --qa-no-focus --qa-window=1920,0,1920,1080 --qa-mute`, own
settings / save dir in `qa/tmp/visual/g1_pass3/`, `timeout 150` + `--max-seconds=140`, the avatar fixer's lineup helper used
read-only, both runs exit 0 with no errors): `crown_helm_recheck.png` (braided crown bare / padded / copperwood / ironwood / moonsteel,
three views) and `armor_hem_recheck.png` (Cloud Cardigan bare + four armor sets, Velvet Vampire + padded / ironwood, front / side / back)
- looked at; findings as in R3-31. The layer name itself changes nothing on screen (no render needed for R3-34).

Cross-group notes (not G1 files):
- `game/tests/unit/test_enemies_review.gd:114` `test_boss_killing_blow_skips_the_window_cap_climb` contradicts the in-progress
  `weaver_boss.gd` rule (a would-be lethal blow is trimmed to the window's room, recorded by decision R3-10): the test sets hp 10 with
  6 HP of room left and expects the 15-damage blow to kill. Owner of `weaver_boss.gd` / lead: either keep the rule and make the test's
  killing blow fit the room (e.g. `set_hp(4.0)`), or exempt lethal blows as Velour does - and update R3-10's note if so. It blocks the
  final full run (R3-50).
- G6's red `test_ui_appearance_wardrobe.test_preview_renders_in_its_own_world_and_frames_krystal` passes again at 09:48
  (`tools/test.sh "test_ui_appearance_wardrobe,test_enemies_review,parse_all"` -> `==== 35 tests, 1 failed ====`, the one failure being
  the `test_enemies_review` case above).
- `QA_REPORT.md` §10.4 counts the UI group as in progress (no `vfix__ui` report existed when this was written).
