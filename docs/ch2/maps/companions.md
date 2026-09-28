# Map: companions (Mochi, Pebble, Lumi)

Scope: `game/src/companions/*.gd`, `game/data/creatures.gd`, `game/src/ui/panels/companion_panel.gd`, and the
companion-related parts of `autoload/game_state.gd`, `autoload/game.gd`, and the tests. This map does not repeat
`docs/ARCHITECTURE.md` §Companions; it covers what that section leaves out. Paths are relative to `game/`, and `L123`
means line 123.

## 1. Files at a glance
| File | Lines | Role |
|---|---|---|
| `src/companions/companion.gd` | 1907 | `CharacterBody3D`. The whole runtime: state machine, steering, abilities, threats, befriending, speech and voice |
| `src/companions/companion_logic.gd` | 425 | `RefCounted`, pure static logic with no scene access (spawn planning, bond math, stuck detectors, follow geometry, prompts). Unit tested |
| `src/companions/companion_spawner.gd` | 135 | `static spawn_for_area(area, area_id, player) -> Dictionary`. Applies `Logic.plan_spawns` |
| `src/companions/companion_visual.gd` | 633 | Base procedural rig and pose solver (gait + mood + action + look + blink), emote bubble |
| `mochi_visual.gd` / `pebble_visual.gd` / `lumi_visual.gd` | 147/206/260 | Subclasses (`extends "res://src/companions/companion_visual.gd"`). Lumi owns an `OmniLight3D` (range 6.5, no shadows) |
| `companion_fx.gd` | 234 | Static one-shot FX: `poof`, `hearts`, `sparkles`, `chips`, `note`. Cached meshes and materials, self-freeing |
| `emote_icons.gd` | 318 | SDF-rendered 96 px textures. `bubble(kind)`, `icon(kind)`, `prewarm()`. Cached in `static var _cache` |
| `pebble_boulder.gd` | 205 | The quarry boulder (harvestable + interactable, `HITS_NEEDED := 4.0`). Calls `pebble.release_from_boulder()` |
| `companion_lineup.gd` | 45 | Preview helper that shows all three visuals side by side |
| `companion_debug.gd` | 293 | Debug-only (`--companion-walk/-log/-scenario`). Added under the area as `CompanionDebug` |
| `data/creatures.gd` | 96 | `BOND_XP_PER_LEVEL`, `CREATURES`, `LINES` |
| `src/ui/panels/companion_panel.gd` | 118 | Pet / Follow or Wait / Go home / Feed menu. Calls `Game.companion_nodes[id].command(cmd)` |
| Tests | | `tests/unit/test_companions_logic.gd` (460), `test_companions_node.gd` (724), `test_companions_visual.gd` (81), `test_audit_companions_verify.gd` (116). Run with `tools/test.sh companions` |

## 2. Data shapes

**Creature def** (`data/creatures.gd` `CREATURES[id]`, read through `ItemDB.creature(id)`, a **const, read-only** dictionary):
`name, species, blurb, favorite_food, befriend {type: offer_item|free_from_boulder|rescue, item?, count?, flag?},
ability: forager|miner|lightbearer, move_speed, follow_distance, enters_below: bool, brave: float (0.1/1.0/0.4 — **unused by code**),
voice (sound prefix), colors {..}, light {color, energy, range} (Lumi only)`.
- Mochi: speed 4.6, follow 2.6, `enters_below=false`, befriend = 3 berries, food berries.
- Pebble: 4.2 / 2.8, true, free_from_boulder, food `shiny_pebble`.
- Lumi: 4.8 / 2.4, true, rescue with flag `ruin_cleared`, food `sweetroot`.

**`LINES[id][context]`**: arrays of strings with `{name}` substitution. They are read by `ItemDB.creature_line(id, ctx)` (random pick).
Contexts the code uses: befriend, pet, follow, wait, home, gather, scared, refuse_below, reunite, tend, celebrate, idle,
idle_below, mine, gift, brave, notice. Contexts that are authored but never used: pebble `dizzy`, lumi `warn` and `calm`.

**GameState record** `GameState.companions[id]` (`game_state.gd` L104 `_new_companion_record`):
`{befriended: bool, bond_xp: int, assignment: "wild"|"home"|"follow"|"wait", wait_area: String, wait_pos: [x,y,z]|null,
last_pet_day: int, last_gift_day: int, last_fed_day: int}`. Companion code also adds these keys lazily: `work_day: int`,
`work_xp: int`, `zones: Array[String]`. `_load_companion` (L640) **keeps unknown extra keys** (`_copy`). It coerces the
known keys and **repairs any assignment not in `COMPANION_ASSIGNMENTS := ["wild","home","follow","wait"]` (L10)** to
home or wild. `_repair_followers` (L660) enforces one follower. `GameState.active_companion: String` holds the follower id.

**Work dict** (`companion.gd` `_work`): `{kind: "gather"|"tend"|"headbutt"|"present", anim: <visual action>, pos: Vector3,
item?: String, uid?: String (crop plot), reach: float, speed: float (× move_speed), phase: "go"|"act", go_t, act_t}`.
`_state_refuse` also reuses it as `{"refused": true}`.

**Spawn plan** (`Logic.plan_spawns` L45): `{"spawns": [{id, mode, pos?}], "changes": [{id, assignment, wait_area?, wait_pos?}], "boulder": bool}`.
The spawn modes are `wild|pinned|home|wait|follow|reunite|reunite_home`.

## 3. Construction at runtime
`Game.load_area` (`autoload/game.gd` ~L268) runs after the player and the Below director exist:
`companion_nodes = spawner.spawn_for_area(area, target_area, player)`.
`spawn_for_area` (spawner L20) proceeds in this order:
1. `_apply_debug_overrides()` (debug `--companion-follow=<id>`).
2. `Icons.prewarm()`.
3. It builds `defs` from `ItemDB.creature_ids()`.
4. Threshold: on the surface it is the area spawn `mine_threshold`. In any other area it is `Layout.SPAWN_HINTS["mine_threshold"]` with **y = 0**, in surface coordinates.
5. It calls `Logic.plan_spawns(area_id, GameState.companions, GameState.active_companion, GameState.player["spawn"], defs, GameState.is_depleted("pebble_boulder"), threshold)`.
6. It applies `changes` through `GameState.set_companion_assignment`. These emit `Events.companion_assignment_changed` **before any node exists**.
7. `_spawn_one` (L53) for each spawn:
   - It computes `home` from `companion_home_<id>` and `wild` from `companion_wild_<id>` with `_spawn_pos(..., required=true)`. Fallback order: area `spawns` dict, then `Layout.SPAWN_HINTS` snapped by `_ground()`, then `area.get_spawn()`. **In the Below and in any new area, home and wild therefore resolve to surface coordinates.**
   - `params = {id, mode, home, wild, wait?, threshold? (surface only)}`.
   - `CompanionScript.new()`, `setup(params)`, `area.add_child(c)`. `_ready` runs here, before the position is set. Then it sets `c.global_position = pos`.
   - Mode `follow` calls `c.place_near_player()`. Mode `pinned` sets `c.set("_yaw", ...)` and spawns `pebble_boulder.gd` at `wild`.
8. It adds the debug node if `--companion-walk` or `--companion-log` is passed.

`companion._ready` (L143) does the following:
- Reads `def`, then `move_speed` and `follow_distance` from it. `side` is `[1,-1,1][ORDER.find(id)]` (lateral follow side).
- Groups: `companion`, `interactable`, plus `light_source` if the ability is `lightbearer`.
- Body: layer 4, mask 1|32, `floor_snap_length 0.35`, `floor_max_angle 52°`, collision `SphereShape3D r=0.24` at y 0.25.
- `Area3D "Interact"`: layer 16, mask 0, `monitoring=false`, sphere r 0.55 at y 0.35.
- Visual: `load(VISUALS[id]).new()`, scale ×1.15 (`VISUAL_SCALE`). Connects `visual.action_event` to `_on_visual_action`.
- Connects `Events.companion_assignment_changed`, `harvested`, `zone_entered`, `flag_set`, `enemy_killed`. These are bound methods, so they drop automatically on free.
- Calls `_init_mode()` and `_init_threshold_guard()`.

Teardown: nodes die with the area. `Game._free_gameplay_nodes` clears `companion_nodes`. A companion that finishes the `leaving` override erases itself from `Game.companion_nodes` and calls `queue_free()` (L1650).

Other runtime callers:
- **Commands**: the G hotkey (`player.gd` L929) sends `command("wait")` to the follower. With no follower, the nearest waiting companion within 35 m gets `command("follow")`.
- **Reactions and respawn**: same-area respawn calls `on_player_respawned()` (`game.gd` ~L430). `Game.complete_chapter` calls `react("celebrate")`.
- **Teleports**: the unstuck path (`ui_root.teleport_player`) and the lift (`below_world.gd` L665) call `teleport_near`.
- **Threat notices**: `notice_threat` comes from `event_runner._run_notice` (event `lumi_notices`), `stalker` L661, `weaver_boss` L771 and `below_moments` L206.
- **Readers**: `map_view` L149, `qa_telemetry` L111, and the HUD `companion_badge` (reads GameState only).
- **Side effects of layer 4 and the group**: `build_mode` L455 blocks placements overlapping layer 2|4. `resource_node` L544 skips a regrow within 1.6 m of a companion. `interaction_probe` L119 deprioritises befriended companions.

## 4. State machine
`mode` is the base state and mirrors the GameState assignment: `wild|follow|wait|home`.
`override` is a temporary state layered on top. `get_state()` (L241) returns the override if one is set, otherwise the mode.
`_physics_process` (L489) dispatches on `get_state()` (L503-525). Each state handler only writes `_goal`, `_goal_speed` and `_look`.
After that the frame runs:
- `_scan_threats` every 0.45 s (`_scan_t`, only when `mode=="follow"`).
- A safety-net recover if the companion is more than 24 m away while an override is active (L534).
- `_move`, `_update_visual`, `_check_fall`.

A pinned Pebble short-circuits at L494: it only looks at the player.

| Override | Set by | Timeout (`_override_t`) | End |
|---|---|---|---|
| working | `_start_work` L1199 | 12 s hard cap; also gives up after 7 s in phase "go" | `_finish_work` |
| afraid | `_hide_from` L1429 | seconds passed (2.5 scan / 3.5 react / 4.0 `HIDE_SECONDS`) | clears `_threat_pos` |
| refuse | `_check_threshold` L1468 | 5.5 | `_finish_refuse` sets assignment to wait at the threshold |
| notice | `_notice` L1411 | 1.4 | Lumi glow goes to 0.7 plus a "dots" emote |
| celebrate / dizzy | `react`, charge | 2.6 / 2.0 | clear |
| befriending | `_befriend` L1505 | **0 = never times out** | tween callback `_befriend_done` |
| reunite | spawn mode reunite* | 8.0 | clears on reaching the player (<1.6 m) |
| charge | Pebble scan L1405 | 4.0 | bonk sets dizzy |
| leaving | assignment "home" while not on the surface | 2.2 | poof, erase from `Game.companion_nodes`, `queue_free` |

- `_set_override` (L1611) refuses to replace `befriending` or `leaving` (`_uninterruptible()`).
- Mode changes **always go through GameState**. `command()` calls `GameState.set_companion_assignment(...)`, which emits the signal handled by `_on_assignment_changed` (L1580), and that updates `mode`. The companion also emits its local `signal state_changed(state)` from there.
- A new follower demotes the previous one to "home" through the same signal.

## 5. Movement, following, recovery
- **Steering `_move` (L942)**: flat seek to `_goal` at `_goal_speed`. It slows down linearly inside 0.6 m (min ×0.25) and stops inside 0.12 m. `ACCEL 16` (×0.35 when airborne), `GRAVITY 18`, then `move_and_slide()`. The visual yaw lerps toward the velocity (rate 10) or toward `_look` (rate 4). Only `visual.rotation.y` rotates; the body never does.
- **Hop `_try_hop` (L977)**: triggers on a slide collision with a wall (`n.y<0.5`, `n·dir<-0.4`) or on a ledge gap (ray 0.65 m ahead, checked every 0.2 s). It sets `velocity.y = JUMP_SPEED 5.4` with forward ≥3.2 and a 0.7 s cooldown. There is no hop while working (bumping into the target counts as arrived).
- **Follow `_state_follow` (L664)**:
  - It pushes a breadcrumb for the player when she is on the floor (`Logic.trail_push`: min step 0.4 m, max 48).
  - The LOS ray companion→player runs every 0.25 s (`_line_clear`, mask 1|32).
  - Goal: `Logic.goal_candidates` gives 6 spots behind or beside the player based on the *movement* direction (`_pvel`, estimated from position deltas). `_pick_goal_choice` takes the first spot the player can see, then `Logic.camera_safe` keeps it out of the camera→player corridor (clearance 1.1 m).
  - Guard override: while `_guard_t>0` and a `_threat_pos` exists, the goal is 1.05 m behind the player, on the side away from the threat.
  - Breadcrumbs replace the goal when there is no LOS or the vertical gap is >1 m (and d>1.5): `Logic.trail_next`.
  - If closer than 0.75 m it steps aside to 1.3 m.
  - Settle hysteresis (`_settled`) stops fidgeting.
  - Speed: `Logic.follow_speed(dist_to_goal, move_speed, player_speed)`, up to ×1.9 when catching up and never slower than the player while she moves.
- **Stuck detection (follow only)**: `Logic.stuck_update` (>`STUCK_FAR 20` returns "far"; no 0.5 m improvement for `STUCK_SECONDS 4` returns "stuck"), `Logic.progress_update` (net move <1 m over 4 s while the goal is >1 m away), and `Logic.los_update` (no LOS for `NO_LOS_SECONDS 7` within 20 m). Any hit calls `_recover(reason)` (L1021). That clears the working/charge/reunite override and calls `teleport_near(player_pos)`.
- **`teleport_near` (L401)**: a **no-op unless `mode=="follow"`** (audit fix). `find_safe_spot` checks `Logic.placement_candidates` in order: 1.3 m behind the camera, then behind or beside the player. It prefers spots outside the camera view first (`in_view`, 52° half-angle). Each candidate goes through `_validate_spot` (L1883): a ray from +2.5 to −4, floor normal ≥0.6, |dy|≤2.5, a sphere r 0.26 overlap test, and LOS from the player. It spawns a poof at the old spot if visible and at the new one. It then clears the trail and the stuck, progress and LOS trackers.
- **Fall `_check_fall` (L1007)**: y < `Layout.KILL_Y (-40)`, or 12 m below the player while following, triggers recover. Other modes snap back to the home, wait or wild spot.
- **Wait (L747)**: walks back at 0.6× speed if more than 1.2 m off the spot. If more than 14 m off for over 1 s, the player is more than 10 m away and the spot is not visible, it snaps back. After 6 s idle it switches to the "rest" mood.
- **Home (L772)**: more than 14 m from home for over 1 s, with the player more than 24 m away and out of view, snaps it home. **It returns early when `!Logic.is_surface_area(Game.area_id)`.** At night (`GameState.is_night()`) it walks home and sleeps (mood "sleep", Lumi glow 0.55). By day it wanders within 3 m of home, greets the player (she was >18 m away and is now <6 m) and runs `_home_abilities`.
- **Per area**: `SURFACE_AREAS := ["surface","arena"]` (logic L7). On those, wild, home, wait and threshold all work. Any other area id (the Below **and every new Chapter-Two area**) takes the dungeon branch of `plan_spawns`: only the follower spawns, and only if `enters_below`. The follower appears beside the player. Companions waiting in that same area also spawn if `enters_below`. "home" there becomes the `leaving` override and a poof. A companion waiting in another area goes home on the surface.

## 6. Mochi's mine refusal (three gates)
1. **Walking up (surface)**: `_check_threshold` (L1468) runs at the end of `_state_follow` when `override==""`. `Logic.should_refuse(def.enters_below (default **true**), mode, flatdist(player, threshold), _refused_this_approach)` checks for ≤ `REFUSE_RADIUS 8`. When it fires:
   - Override "refuse" for 5.5 s: walk to the threshold, then the "refuse" action and scared mood at ≤2.2 s left, the `refuse_below` line and a "drop" emote.
   - `_finish_refuse` (L1484) then sets assignment wait with `wait_area=Game.area_id` at the threshold (if within `THRESHOLD_MATCH 6 + 2` m).
   - `_refused_this_approach` resets once the player is more than `REFUSE_RESET_RADIUS 14` away. `_init_threshold_guard` (L231) pre-sets it when the companion spawns with the player within 14 m, because she is coming out of the mine.
2. **Area load in the Below**: in `plan_spawns` L101-109, an active follower without `enters_below` (default **false** there) is not spawned. The change `{assignment: wait, wait_area: "surface", wait_pos: threshold}` is applied instead, so `active_companion` becomes "".
3. **Coming back** (arrival spawn `mine_exit`): a companion waiting within 6 m of the threshold gets mode `reunite` (it becomes the follower if nobody follows) or `reunite_home`.

## 7. Bond, daily interactions, gifts
- Levels come from `BOND_XP_PER_LEVEL := [0, 10, 25, 45, 70, 100]` (cumulative, levels 0..5). `GameState.bond_level(id)` uses `ItemDB.bond_level_for_xp`. `add_bond` (L390) clamps to `max_bond_xp()=100`. On a level-up it emits `Events.companion_bond_changed(id, lvl)`, sends a notify toast of kind "bond", and sets counter `max_bond` (the post-game `free_play` quest has an optional "max bond 5" objective, `data/quests.gd` L121).
- **Bond level has no gameplay effect today.** It is shown in the panel, journal and HUD badge only.
- XP sources (logic L9-13): `PET_BOND 5` (once per in-game day, `last_pet_day`), `FEED_BOND 8` (once per day, needs `favorite_food` in the bag, `last_fed_day`; `feed_check` returns ok/full/no_food), `WORK_BOND 1` per assist up to `WORK_BOND_DAILY_MAX 5` per day (`work_day`/`work_xp`: forage gather or Pebble headbutt; crop tending gives **no** XP), and `ZONE_BOND 3` the first time a zone is entered together. The zone bonus comes from `Events.zone_entered` (polled by Game every 0.4 s) while following within 25 m (`zones`).
- "Day" is `GameState.day()`, the in-game day.
- `command(cmd) -> {"ok", "text", "bond"}` (L259). pet/feed are never debounced. follow/wait/home have a 300 ms debounce (`_last_command_ms`). Unbefriended companions return ok=false.
- **Pebble gift**: `_tick_gift` (L1187) accumulates `_gift_timer` while the player is within 7 m. At 40 s, if `Logic.gift_due` (once per day, `last_gift_day`) and the player is within 9 m, it starts a "present" work. On the "present" action event it gives `shiny_pebble` ×1.

## 8. Abilities (the `def.ability` switch)
- **Follow** `_follow_abilities` (L1054), only when there is no override:
  - forager (Mochi) runs `_start_forage` every 25-40 s (8 s retry). It picks the nearest hand harvestable within 6 m of kind bush or grass (`get_nodes_in_group("harvestable")`, rare). It skips when the bag has no room for berries or fiber and says a one-time "bag full" line. On the "gather" action event it gives 1-2 berries or fiber through `GameState.give_item` (never more than fits), plus work bond.
  - miner (Pebble) runs `_tick_gift`. `_on_harvested` (L1291) reacts to rock/ore harvested within 8 m of Pebble or the player (6 s cooldown) with a "headbutt" work. On the event it gives +1 of that item plus work bond.
- **Home** `_home_abilities` (L1068):
  - forager runs `_start_tend` every 22-35 s. It uses `farming.gd` `plots_needing_care(area)` and `plot_position(uid)` for plots within 30 m of home, with a fallback over `GameState.crops`. It performs the "pat" action, and the event calls `farming.tend(uid, TEND_MINUTES=30)` (fallback: `crops[uid].tended_minutes += 30`).
  - miner: gift, plus "polish" every 14-24 s.
  - lightbearer: "glow_pulse" every 10-18 s.
- **Lumi's light is a gameplay passive**: `light_source` group, `light_radius = 5.0` (companion L60, *not* the 6.5 m visual range), `is_light_active()` returns `_glow_target > 0.5`. It feeds `Combat.light_at`, which exposes Gloomlings (×2 damage taken) and matters for stalker light rules. The light is inactive while dimmed (notice 0.35, unrescued 0.28).

## 9. Threats and enemies
- Enemies **never target companions** (`enemy_base.gd` L6). Companions have **no health**. Their mask (1|32) ignores the enemy layer 8, so they pass through enemies.
- `_enemies()` (L1336) reads a **static shared cache** of group "enemy", refreshed every 400 ms. Freed entries can linger, so always filter with the untyped `static _enemy_alive(e: Variant)` (L1346).
- `_scan_threats` (L1357), follow mode only, every 0.45 s. It finds the nearest enemy to the companion, and the "threatening" enemy nearest the player (`is_threatening()`, or within 6 m).
  - **Lumi**: an enemy within `LUMI_NOTICE_RANGE 14` gets a notice (once per enemy instance per 25 s, `_noticed` capped at 48). Notice is the override for 1.4 s, the "alert" mood, glow 0.35, the warn voice, a line with a 75 s cooldown, and `_guard_t = 6`, which puts the follow goal behind the player. Otherwise an enemy within 10 m of the player sets guard 2 s.
  - **Mochi**: a threatening enemy within `MOCHI_FEAR_RANGE 8` of the player or Mochi makes her `_hide_from`. That is afraid for 2.5 s, extended while the threat persists. The hide goal is 1 m behind the player, away from the threat, at ×1.3 speed. When wild, home or waiting she runs 3.5 m past her own spot instead.
  - **Pebble**: a threatening enemy within `PEBBLE_CHARGE_RANGE 7` of the player, within 11 m of Pebble, with `|dy| < CHARGE_MAX_RISE 1.6`, when `_charge_cd<=0` and there is no override, starts a charge. Charge is 4 s at 7 m/s. At 0.95 m it bonks: bounce velocity, `_damage_enemy(target, 2.0, dir)` (L1739, `health.apply_damage(2, self, dir)`), chips, `camera_shake(0.08, 0.12)`, then dizzy for 2 s. `_charge_cd = 14`.
- Because the damage source is the companion and not in group "player", `enemy_base._on_damaged` does **not** retarget. The enemy still flinches, or goes from idle to chase *toward the player*.
- `_on_enemy_killed` within 14 m clears threat and guard and plays happy (Pebble: stomp).
- `notice_threat(pos)` (L379) is ignored when pinned, unbefriended or uninterruptible. Mochi hides for 4 s; the others run `_notice(pos, true)`.
- `react()` (L352) accepts happy, scared, notice, celebrate and dizzy, and always emits `Events.companion_reaction`.

## 10. Speech, voice, emotes, animation
- `_say(ctx)` calls `_say_text`. Non-priority lines are blocked if this companion's `_say_cd>0` **or any companion spoke in the last 7 s** (`static var _last_any_say_ms`). Cooldown is 4 s after a priority line and 16 s after a normal one. The output is `Events.say.emit(name, line, dur)`. Idle lines (`idle`/`idle_below`, only when area_id == "below") come every 120-220 s while within 6 m.
- `_voice(kind, db)` maps a generic cue through `VOICE_MAP[id]` onto that creature's 3 real sounds (`<voice>_chirp|happy|scared`, `pebble_clack|happy|grunt`, `lumi_chime|happy|warn`). There is a 350 ms per-kind cooldown stored as msec timestamps, and playback uses `Audio.play_3d`. Wild companions chirp every 9-16 s within 22 m.
- Emote bubbles are `exclaim, question, heart, dots, zz, sparkle, drop, note, berry`. Unknown kinds fall back to "dots".
- Visual API: `set_motion`, `set_look_target`, `set_mood(idle|sleep|scared|alert|pinned|rest)`, `play_action(name) -> float`, `show_emote(kind, s)`, `set_glow`, `get_action`, `is_busy`, `stop_action`, `head_world_position`.
  - `ACTIONS` (visual L32) holds `[length_s, fire_at_normalised]`. The **gameplay effects of work happen on `action_event`** (the impact frame), not on a timer.
  - Pose pipeline in `_process`: `_reset_pose`, `_gait`, `_breathe`, `_mood_pose`, `_update_action`, `_update_look`, `_update_blink`, `_apply_pose`, `_update_emote`. Subclass hooks are `_build`, `_gait`, `_mood_pose`, `_action_pose`, `_apply_pose`, `_on_action_started`, `_on_action_fire`, `_on_mood_changed`. There are no AnimationPlayers and no skeletons.

## 11. Performance tricks
- **Throttled queries**: the static enemy cache refreshes every 400 ms. The threat scan runs every 0.45 s, the LOS ray every 0.25 s, and the ledge ray every 0.2 s. The goal-candidate raycasts (up to 6) run only on the LOS refresh frame. A missing player is re-looked-up at most once per second.
- **No per-frame ticking**: voice cooldowns are timestamps. Harvestable and crop scans run only on the 22-40 s ability timers.
- **Caches**: emote textures are prewarmed at spawn (the test budget is <1.5 s), and FX meshes and materials are shared. Lumi's per-instance materials and shadowless light are the only unique ones.

## 12. Pitfalls
- `def` is a **const** Dictionary. Mutating it (`def["enters_below"]=true`) raises an error, so duplicate it first. The `enters_below` default also differs: `true` in the node, `false` in `plan_spawns`.
- New area ids are "dungeons" unless they are added to `SURFACE_AREAS`. There, Mochi is converted to *wait at the surface mine threshold*.
- `_on_visual_action` returns early unless `override=="working"`. New effects need a branch before that guard.
- `_recover` clears only working, charge and reunite. Add new overrides there, and decide whether they belong in the L534 exclusion list.
- `_override_t == 0` means the override never expires. `_ready` runs before the spawner sets `global_position`.

## 13. Extension recipes

### (a) Basic attack (melee or projectile) against group "enemy" with LOS
1. **Data.** `data/` is shared read-only, so either ask the integrator to add `"attack": {kind: "melee"|"projectile", damage, range, cooldown, arc_deg, knockback, speed?}` to `CREATURES`, or add a new module data file `data/companion_combat.gd` keyed by id. Use `brave` for the willingness to engage (Mochi 0.1 should stay non-combat or ranged-from-behind).
2. **Pure selection** in `companion_logic.gd`: `static func pick_attack_target(me: Vector3, player: Vector3, enemies: Array[{pos, threatening, id}], range, max_dy) -> int`. Unit test it in `test_companions_logic.gd`.
3. **State.** Add an `"attack"` branch in the `_physics_process` match (L503) and a `_state_attack(delta)` that chases to `range*0.8`, faces the target and plays the action. Acquire targets inside `_scan_threats` (L1357, already on 0.45 s cadence) and reuse `_enemies()` and `_enemy_alive()`. Tick `_attack_cd` in `_tick_timers` (L542). Add "attack" to `_recover` (L1024).
4. **LOS.** Use `Combat.has_line_of_sight(space, global_position+UP*0.4, Combat.aim_point(e), [self, e])` (combat.gd L108; mask 1|32). Throttle it to the scan cadence.
5. **Melee hit.** Add a new visual action to `ACTIONS` (a generic pose in the base `_action_pose` is enough; `test_every_action_and_mood_plays_on_every_creature` plays every action on every creature). Resolve the hit in `_on_visual_action` *before* the working guard with `Combat.melee(self, origin, fwd, reach, arc, dmg, ["enemy"], kb)`. It does LOS, `find_health`, knockback, `on_hit_blocked`, HitFx and **`Events.hitstop`**; consider direct `_damage_enemy` (L1739) plus `HitFx` to avoid a hitstop for every companion hit.
6. **Projectile.** New `src/companions/companion_projectile.gd` (Node3D, no body). Each physics frame it ray-casts the travelled segment with mask `1|32|8` (enemies are `CharacterBody3D` on layer 8) and applies `Combat.find_health(collider).apply_damage(d, companion, dir)`. It frees on a world hit or after a lifetime. Test `FakeEnemy`s are plain `Node3D` without colliders, so tests need a fake with a layer-8 body.
7. **Voice.** Map new cue names in `VOICE_MAP` onto existing sounds (the test enforces real names).
8. **Aggro.** Enemies ignore companion sources for retargeting. Changing that is an enemy-module change, and it breaks the "enemies attack only the player" contract.

### (b) Passive support effects the player stat layer can query
- Today's stat hook is `GameState.buff_mult(name)` (game_state L457, used for `stamina_regen` at player L364). Buffs are **saved** and time out, so don't inject companion passives there.
- Add `src/companions/companion_support.gd` (static) with `static func mult(stat: String) -> float` and `static func add(stat) -> float`. It reads `GameState.active_companion`, `GameState.bond_level(id)`, a data table `passives[id][stat] = [lvl0..lvl5]`, and presence (`Game.companion_nodes[id]` is valid and inside the tree, and within about 15 m of `Game.player`). Cache the result per `Engine.get_physics_frames()`.
- The player module multiplies it in, for example `buff_mult("stamina_regen") * Support.mult("stamina_regen")`, or in the damage calculation at player L728-733.
- Lumi's radius could scale with bond by setting `light_radius` in `_on_assignment_changed` and on `Events.companion_bond_changed`.

### (c) Signature skill: cooldown + autocast + manual
1. Add `var _skill_cd`, tick it in `_tick_timers`, and add a local `signal skill_changed(cd, max_cd)`. Events is read-only.
2. Add a public `use_skill(manual := true) -> Dictionary` that returns `{"ok", "reason"}`. Check befriended, `mode=="follow"`, `override==""` or interruptible, and cooldown. Run the effect as an override (for example `"skill"`) with an action-event impact.
3. **Autocast**: in `_follow_abilities` (L1054) or `_scan_threats`, when the conditions hold (such as an enemy threatening the player within X).
4. **Manual**: add `"skill"` to the `command()` match (L259) so the panel and player can call `command("skill")`. The player's `_command_ok` already honours `ok`. Add a panel button in `companion_panel._build` grid (L54-68). A hotkey needs a new input action in `Settings` (autoload, integrator) and a handler next to `player.gd` L595.
5. Cooldowns don't need saving. If they must be saved, store `skill_ready_at` (clock minutes) as an extra record key.

### (d) Obstacle-aware navigation for follow and attack
- Nothing exists yet: no Navigation* nodes, no AStar. Movement is seek + hop + breadcrumbs + teleport.
- **Waypoint graph (the Below)**: build an `AStar3D` once per area from `src/world/below/below_layout.gd` (`ROOMS` openings, `CRITICAL_PATH`, `SIDE_PATHS`, `STAIR`). Cache it in a static keyed by area_id.
- **NavigationServer3D**: bake async at area load from collision layers 1|32 (keep the main thread under 1 s). Rebake throttled on `Events.structure_placed/removed`. Use agent radius about 0.26 and a conservative climb. The surface is large, so bake around the Haven and paths only.
- Hook: in `_state_follow` at L697 (where breadcrumbs replace `goal`), and in the attack state. When there is no LOS, feed `path[i]` as `_goal`. Put `path_next(path, pos, reach)` in logic (like `trail_next`). Re-path at most every 0.5 s or when the target moves more than 1.5 m. Keep the three stuck detectors and the teleport as the last resort.

### (e) Courage flag: Mochi enters the Below
- Define `static func dares_below(def: Dictionary, courage: bool) -> bool` in logic.
- In the **spawner** (L27-29) give `plan_spawns` a duplicated def with `enters_below=true` when `GameState.get_flag("mochi_courage")`. This keeps the `plan_spawns` signature and its tests.
- In the node, replace `def.get("enters_below", true)` in `_check_threshold` (L1475) with that helper.
- In `_on_flag_set` (L1315), cancel an active "refuse" when the flag turns on.
- Mochi still hides from threats in the Below (scan L1391, `notice_threat`). That is fine, but tune it.
- The horror director has `wrong_mochi` ("a familiar squeak… from somewhere deep below", `horror_events.gd` L43), which assumes Mochi is absent. Gate it (horror module) when the companion is Mochi.
- Existing saves with Mochi waiting at the threshold still reunite normally.

### (f) Behaviour modes Assist / Stay close / Wait
- Keep assignment `follow`, because adding new assignment strings breaks `_load_companion`'s repair list (L648). Store a stance in an extra record key `rec["stance"] = "assist"|"close"` (it is preserved on load; default "assist").
- "Wait" is the existing assignment.
- `command()` gets `"assist"` and `"close"`. In `_state_follow`, "close" scales the `follow_distance` passed to `goal_candidates` and `stuck_update` (for example ×0.6), keeps `_guard_t` behaviour, and disables charge and attack. "assist" enables them.
- Update `companion_panel` (buttons and `status_text` L87) and the G hotkey if desired (`player.gd` L929).

## 14. Risks (saves and tests)
- **Saves**: record keys and types (`test_core_save.gd` L110-172, 428-486, 535) and the assignment whitelist in the autoload. `wait_pos` must stay `[x,y,z]` or null. New keys must be read with `.get(k, default)`. Changing `BOND_XP_PER_LEVEL` re-levels existing saves, and `bond_xp` is clamped to the new max on load. Renaming the depletion id `pebble_boulder` re-pins a freed Pebble.
- **Tests poke private members by name**: `_last_command_ms`, `_override_t`, `_charge_cd`, `_ability_t`, `_gift_timer`, `_scan_threats`, and `_yaw` (the spawner uses `set("_yaw")`). Constants `VOICE_MAP`, `ACTIONS`, `MOODS`, `Logic.*`. Signatures of `Logic.plan_spawns`, bond functions and stuck functions.
- **Behaviour assertions**:
  - Pebble charge does exactly 2 damage and ends "dizzy". No charge at +5 m dy.
  - Lumi `notice` for 1.4 s and not light-active during it.
  - Mochi `notice_threat` sets "afraid".
  - "leaving" cannot be interrupted, and `Game.companion_nodes` is erased.
  - `teleport_near` moves only the follower (audit lift tests).
  - Forage never overfills the bag.
  - Plus the spawn plan tables in `test_companions_logic.gd` L37-160.
- **Contracts others depend on**: `notice_threat`, `teleport_near`, `on_player_respawned`, `react`, `command` return shape, the `companion_id` property, layer 4 (build mode's 2|4 overlap query), and `Game.companion_nodes` entries being valid Node3Ds. Lumi's `light_source` membership changes Gloomling exposure and stalker behaviour globally.
- **Comfort and perf**: new hits must use `Events.camera_shake` and `hitstop` sparingly. Avoid per-frame `get_nodes_in_group` and extra per-frame rays (three companions can exist at once on the surface).
