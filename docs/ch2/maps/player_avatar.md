# Map: player_avatar (player controller, Krystal avatar, camera)

Scope: `game/src/player/{player.gd, player_logic.gd, krystal_avatar.gd, interaction_probe.gd, player_demo.gd, qa_dummy.gd}`,
`game/src/player/avatar/*` (Chapter Two appearance builders), `game/src/camera/camera_rig.gd`, tests
`game/tests/unit/test_player_{node,logic,avatar}.gd` and `test_avatar_look_{legacy,build,motion}.gd`.
This file adds to docs/ARCHITECTURE.md ("Player", "Interaction contract"); it does not repeat it. Line numbers are for the Chapter 1 release
(sections 7, 11 and 12(a) were rewritten after Wave B and name functions instead of lines).
All paths below are relative to `game/`.

## 1. Runtime construction

`Game.load_area()` (autoload/game.gd:238-245) does `player = PlayerScript.new()` → `area.add_child(player)` (so `_ready` runs
**before** state is read) → `player.read_from_state()` → `player.teleport(xform)`. Respawn (game.gd:417-431) sets
`GameState.player.hp/stamina` to max, then calls `read_from_state()` + `teleport()` on the **same** node.

`player.gd _init` (91): `name="Player"`, `health` = health.gd child "Health" (max_hp 100). `_ready` (99-149): groups "player",
"light_source"; layer 2, mask 1|32; floor angle 46°, snap 0.35, `max_slides` 6; capsule r 0.32 h 1.6 at y 0.8; then, in order:
- `avatar` = krystal_avatar.gd (`driven = true`, `add_child`, **then** `top_level = true`), `avatar.footstep → _on_footstep`.
- `rig` = camera_rig.gd (`setup(self)`; top_level itself); `probe` = interaction_probe.gd (`probe.player = self`).
- health `damaged/healed/died/changed` → `_on_*` handlers; `Events.build_mode_changed → _on_build_mode_changed`.
- `_place_avatar(1.0)`, `rig.snap(_facing_yaw)`, `_refresh_owned()`; debug-only `player_demo.gd` when `--player-demo`.

Engine physics interpolation is **off**; the player keeps `_prev/_cur` pos+yaw (`_store_visual_state` 427) and each `_process` places
the top-level avatar at `lerp(prev, cur, Engine.get_physics_interpolation_fraction()) + _visual_offset` with `Basis(UP, yaw + PI)` (444)
— the model faces +Z, the player forward is −Z. `get_visual_position()` (308) feeds the camera; `_visual_offset` smooths step-ups (`_try_step_up` 516).

## 2. player.gd per-frame order

`_physics_process` (331-424): death retry (`DEATH_RETRY` 2.5 s calls `Game.on_player_died()` again if mode is "playing") →
`_recovering` early-out → timers (`_dodge_cd`, `_eat_lock`, `_jump_lock`, `_stagger`) → `_jump.tick` → raw input
(`Input.get_vector` only when `_can_act()` = `input_enabled and not _dead and not _recovering and Game.gameplay_input_allowed()`)
→ `_wish = Logic.camera_relative(raw, rig.yaw)` → moving cancels looping emotes (sleep/wave/cheer/tired, 357-360) →
sprint decision (363) → `_stamina.tick(dt, _sprinting and hspeed > 1.0, GameState.buff_mult("stamina_regen"))` →
horizontal velocity → gravity/jump cut/jump → `move_and_slide()` → step-up → landing/air time/floor collider →
`_update_facing` → safe-ground tracker + `_check_recovery` → swing events → `GameState.player["stamina"]` sync → `_store_visual_state`.

**Speed** (374-385) — the single place to add a movement multiplier:
```gdscript
var top := Logic.SPRINT_SPEED if _sprinting else Logic.WALK_SPEED
if _swing.active: top *= 0.35
if _eat_lock > 0.0: top *= 0.55
```
Stagger (0.3 s after knockback) uses `hv.move_toward(_wish*top, AIR_DECEL*dt)`, otherwise `Logic.approach()`.
Sprint requires: can act, `sprint` held, `|wish| > 0.2`, `_stamina.can_sprint()`, not dodging, not swinging, no eat lock.
Jump: `_jump.try_consume()` (coyote/buffer 0.12) blocked while dodging/swinging/eating; `_do_jump` (556) sets `velocity.y = 6.0`;
early release ×`JUMP_CUT` 0.8. `_on_land` (566): avatar "land" (strength `fall_speed*0.3`), shake if fall speed > 12.

**Dodge** `_try_dodge` (610): needs no active dodge, `_dodge_cd` 0, not dead, no eat lock, grounded or coyote; a swing is cancelled
only before its strike (`Swing.can_cancel()`); `_stamina.try_spend(DODGE_COST 20)` else avatar "tired". Direction = wish or facing.
I-frames via `_grant_iframes(DODGE_IFRAMES 0.3)` (640; keeps the later of `_iframes_until_ms`, calls `health.grant_iframes`).
Speed `Logic.dodge_speed(k) = lerp(8.6, 3.2, k²)` over `DODGE_TIME` 0.45 s, then `DODGE_COOLDOWN` 0.12. `knockback()` is ignored while rolling.

**Hotbar/use_item**: `_unhandled_input` (580) → `GameState.select_hotbar(i)` (emits `Events.hotbar_selected`). The selected slot only
matters for `use_item` (`_use_item` 852, by `ItemDB.category`): food → `eat(id)`; placeable → group "build_mode" `.begin(id)`;
seed → hint toast; equipment "lantern" → toggle; tool/weapon → toast "used automatically". **Tools/weapons are never chosen by hotbar.**

**eat(id) -> bool** (884): refused while dead or eat-locked (except when the tree is paused = menu eat), refused at full HP unless the
food has a `buff`; `GameState.take_item`; `_eat_lock = EAT_TIME 1.0` (gameplay only); `health.heal(d.heal)`; every key of
`d.buff` except "seconds" → `GameState.add_buff(key, mult, seconds)` (so new buff keys need no player change to be *stored*; only
"stamina_regen" is *consumed*, at 364); sfx, `Events.item_consumed`, avatar `set_food_color` + "eat", success toast.

**Lantern**: `set_lantern(on, silent)` (232) syncs `lantern_on`, GameState and `avatar.lantern_on`. `_refresh_owned` (476, every 0.5 s)
sets `avatar.lantern_owned`, `avatar.lantern_energy_scale = Logic.lantern_scale(area, hour)` and turns the lantern off if the item is gone.

**State sync**: `read_from_state` (185): `health.max_hp = max(p.max_hp,1)`; hp ≤ 0 → max; `health.set_hp(hp)`;
`_stamina.reset(p.stamina, p.max_stamina)`; clears `_dead/_recovering`; `avatar.cancel_action(true)`;
`set_lantern(p.lantern_on and has_item("lantern"), true)`. `write_to_state` (202): `pos` only when on floor and not
`_in_danger()` (dead/recovering/damaged < 5 s/airborne) else last safe point; `yaw`, `hp`, `max_hp`, `stamina`, `max_stamina`, `lantern_on`.
`_on_health_changed` writes `GameState.player.hp/max_hp` on every Health `changed`. The `stamina` property setter (29-36) clamps to
`_stamina.max_value`, clears exhaustion at ≥ 25 and writes GameState (the bed relies on this).
`GameState.player` keys (game_state.gd:81): hp, max_hp, stamina, max_stamina (floats), area, pos ([x,y,z]|null), yaw, spawn,
respawn_area, respawn_spawn, lantern_on, below_respawn. `_load_player` (game_state.gd:618) coerces keys by the default's type and
**keeps unknown keys** (deep copy) — new keys survive saves without a GameState change. Saves are JSON: Colors become strings, ints come back as floats.

## 3. Attack flow

`_on_attack_pressed` (649) → blocked in build mode, rolling, eating → `_swing.request()` (buffers one click after 20 % of a swing)
→ `_start_swing` (657):
1. `probe.refresh()`; target = `probe.focused_harvestable()`.
2. `_soft_lock_dir()` (787): nearest living "enemy" within 3.2 m horizontal, |dy| ≤ 1.8, in front (dot > -0.2) or < 1.5 m. If found,
   harvesting is suppressed (fight first).
3. Harvest: tool = `focus_harvest.tool`; owned = "hand" or `GameState.best_tool(tool)` (highest `power`); kind = "gather" (hand) or the
   tool name; missing → `_need_tool_notice` (toast + `Events.hint("need_tool")`).
4. Otherwise weapon: `_swing_tool = GameState.best_weapon()` (highest `damage` among cat weapon|tool — **auto-selection**),
   kind = `Logic.weapon_kind(id, cat, tool)` ("sword" for any cat "weapon", axe/pickaxe for tools, else "hands"); face = soft-lock dir or wish.
5. `_stamina.spend_soft(SWING_COST 6)`; if not fully paid, time ×`TIRED_SWING_MULT` 1.25. `_swing.start(kind, 0.5*m, 0.22*m)`;
   `avatar.cancel_action()`, `avatar.show_tool(kind, duration + 0.35)`.
`Swing.tick` emits STRIKE once → `_on_strike` (709): swing sfx; harvest → `target.harvest_hit(self, _swing_tool)` if still ≤ 4.5 m;
else `_melee_hit` (727): `dmg = max(item.damage, HAND_DAMAGE 5)`, `reach = item.reach` (ItemDB default 2.0; hands 1.8), origin
`+0.9 up`, forward `get_facing()`, `Combat.melee(self, origin, fwd, reach, MELEE_ARC 110, dmg, ["enemy"], 4.0)` (fallback
`_fallback_melee` if combat.gd fails to load); hits → `camera_shake(0.1, 0.12)`. FINISHED → `_on_swing_finished` restarts a buffered click.
While swinging the facing turns to `_swing_face` at rate 24; `avatar.swing_t` is fed with sub-tick interpolation (460-464).

## 4. Damage intake

Every source calls `player.health.apply_damage(amount, source, dir)`: enemies through `Combat.melee` with
`data.damage × Combat.damage_mult_for_area() × damage_scale` (enemy_base.gd:216), stalker lunge (stalker.gd:369) and boss slam
(weaver_boss.gd:443), which additionally call `player.knockback(dir, 6|7)`. health.gd returns 0 when dead, `invulnerable`,
amount ≤ 0 or inside i-frames; else `dealt = min(amount × damage_taken_mult, hp)` → `damaged`, `changed`, maybe `died`.
The player never uses `damage_taken_mult` (stays 1.0) — it is the free hook for armor.
`_on_damaged` (998): `_last_damage_ms`; `_grant_iframes(HURT_IFRAMES 0.6)`; sfx "hurt"; `Events.player_damaged(amount, source)`;
`camera_shake(clamp(0.15 + amount*0.012, 0.15, 0.45), 0.28)`; `knockback(dir or away-from-source, HURT_KNOCKBACK 4.5)`
(knockback 292: force clamped ≤ 12, replaces horizontal velocity, hop `min(2.5, f*0.3)` if grounded, `_stagger` 0.3); cancels a wind-up;
avatar "hurt". `_on_died` (1026): death pose, sfx, `Game.on_player_died()`.

## 5. player_logic.gd (pure, unit-tested)

Movement: WALK 4.2, SPRINT 7.0, GROUND_ACCEL 30 / DECEL 36, AIR_ACCEL 9 / DECEL 3.5, TURN_RATE 14, GRAVITY 18 (×1.2 falling),
TERMINAL_FALL 32. Stamina: MAX 100, SPRINT_DRAIN 18/s, REGEN 22/s after REGEN_DELAY 0.6, SPRINT_RESUME 25. Swing: SWING_TIME 0.5,
SWING_STRIKE 0.22, SWING_COST 6, TIRED_SWING_MULT 1.25, HAND_DAMAGE 5, HAND_REACH 1.8, MELEE_ARC 110. INTERACT_RANGE 2.6.
Classes: `Stamina` (`reset(v,mx)`, `tick(dt, draining, regen_mult)`, `can_sprint()`, `try_spend(cost)` all-or-nothing, `spend_soft(cost) -> bool`),
`Swing` (`start(kind, dur, strike)`, `request()`, `tick(dt) -> int` STRIKE=1|FINISHED=2, `take_buffer()`, `can_cancel()`, `cancel()`),
`JumpAssist`, `SafeTracker`. Statics: `build_prompt`, `weapon_kind`, `score_candidate`, `lantern_scale(area, hour)` (surface 8–17 h → 0.45),
`dodge_speed`, `approach`, `yaw_for_dir(dir) = atan2(-x,-z)`, `dir_for_yaw`, `camera_relative(raw, yaw)`, `recovery_reason`.

## 6. interaction_probe.gd

`refresh()` at 12.5 Hz (`INTERVAL` 0.08) and on demand: sphere r 1.3 at `pos + facing*1.05 + up*0.8` (mask 16) plus the camera-centre
ray (mask 16|1|32, only if `cam.current`); owners via `resolve_owner()` (≤ 6 parents); `Logic.score_candidate` (ray −0.55, befriended
companion +1.2); LOS ray mask 1|32; `{"depleted": true}` harvests ignored. Public: `focus`, `focus_interaction`, `focus_harvest`, `prompt`,
`focused_harvestable()`, `clear()`, `enabled`, `max_dist`; calls optional `set_focused(bool)`.

## 7. krystal_avatar.gd — how Krystal is built (Chapter Two: slot units, module B1)

`extends Node3D`, `signal footstep(foot: int)` (0 left, 1 right). `_ready`: `_pose.resize(13)`; a driven avatar that follows
GameState (`driven and follow_game_state`) reads `GameState.appearance`, `wardrobe.show_armor` and `equipment` (`_read_state`);
any other avatar starts from `ItemDB.legacy_look()` unless a look was set before `add_child`; debug-only `_apply_debug_look()`
(below); `_build()`; blink timer; followers connect `Events.appearance_changed` / `equipment_changed` / `game_loaded` →
`refresh_from_state()`. **The source of truth is the header of krystal_avatar.gd and the builders' headers**; this section maps them.

**Rig** (`_build`): the avatar itself only builds the joints and the always-present pieces: Body > RollPivot > Rig > Hips
(J_HIPS) > Leg0/1 > Knee0/1, Spine > Chest > Shoulder0/1 > Elbow > Hand (arms `_build_arm`), Head > HeadCenter (`_head_c`;
face `_build_face`: eyes, brows, mouth shapes), the tools on the right hand's ToolAnchor, the raised lantern on the left hand and
LanternLight (child of the avatar root, not Body; same light settings as Chapter One). Every joint clothing can sit on is a
**host** in `_hosts` (keys `hips, leg0, leg1, knee0, knee1, spine, chest, sh0, sh1, el0, el1, hand0, hand1, head_c, eye0, eye1,
brow0, brow1`; 0 = +X = her left, 1 = −X = right / tool hand). Then `_rebuild_units(true)` builds the look.

**Slot units** (`UNITS`, rebuilt independently, in this order): `skin, eyes, hair, hat, hair_acc, upper, lower, shoes, back, armor`.
Each unit builds into its own **slot container** Node3D per host (`_box(host_key, unit)`: named after `UNIT_BOX`, meta
`avatar_slot`, identity transform, so a part's position is in the host joint's space). The builders are static files in
`src/player/avatar/`; each receives a context `{box: Callable(host_key) -> container, col, look, id, hides_hair, hat}` and
returns a result Dictionary:

| file | builds | returns |
|---|---|---|
| `avatar_kit.gd` | shared toon / flat / metal / softglow materials (`Mat` caches, never mutated), `node/part/part_xf/mesh_part`, lantern mesh, `arc_mesh`, closed outward-facing cloth `panel_mesh`, `chain(kind, segs, rest, k, d, amp, side)` spring records | — |
| `look_colors.gd` | `resolve(look)`: every colour of a look (hair, skin, eyes, palette channels, leg channel) through ItemDB | colour dict incl. `palette_key` |
| `hair_builder.gd` | the 8 hairstyles + brows (`side_braid` = the Chapter One hair exactly) | `{chains, hull: "" / "direct", hull_nodes}` |
| `garment_builder.gd` | upper / lower (skirts and dresses on panel pivots) / shoes; the explorer pieces part for part | upper `{chains: scarf ends, patch}`; lower `{skirt: {pivots, theta, radius, y0, length, base, max}}` |
| `accessory_builder.gd` | hats, hair accessories, back items (satchel, capes / shawls, wings) | hat / hair_acc `{hull}`; back `{chains, belt, cape: bool}` |
| `armor_builder.gd` | hood / helm (replaces the hat, hides crown hair), vest / mail + shoulder pieces, boots; tier-coloured | head `{hull: "all"}` |
| `skirt_rig.gd` | skirt sway maths (pure, packed arrays, no per-frame allocation) | — |
| `wand_builder.gd` | the Sparkseed wand in the right hand, built lazily the first time a wand is held or cast (integration R100) | — |

A unit is rebuilt only when its **signature** changes (`_signatures(col)`: its ids + palette key + the inputs it depends on, e.g.
hair depends on `hides_hair`, shoes on boots armor and the leg colour). `apply_look()` returns the rebuilt unit names (`[]` for the
same look). Unknown ids show the slot's safe default (`ItemDB.sanitize_look`), are listed by `missing_ids()` and warned once; the
saved look is never modified. Armor: `_armor_id(slot)` is non-empty only while "show armor" is on and that slot holds armor of that
slot; head armor replaces the hat and hides crown hair, body armor is its own unit, boots armor replaces the shoes.

**Baking** (draw calls): parts that never move relative to their joint are merged per host and material class (outline thickness,
rim, noise, specular, shadow casting; glowing cloth, the mouth shapes, food and eye nodes stay separate). `_rebake_host(host)`
merges the parts of **every unit container on that host** into one vertex-coloured mesh per class ("Baked", material
`Mat.toon(WHITE, {vertex_color, emission FILL_TINT, ...})`); the source parts are detached and kept per container (`_detached`,
freed with the container) so the host can be re-merged when a single unit changes. Nodes inside a container (satchel, patch,
spring segments, hats) are baked on their own (`_bake_subtree`). Merged meshes are cached in `static var _bake_cache` keyed by
**content** (`_merged_instance`: material class + md5 of every part's mesh id, transform and albedo), so the **merge cache includes
colour**: two avatars with different looks never share a mesh, identical looks do. The cache is cleared when it reaches
`BAKE_CACHE_MAX` (600 entries). `_set_layers` puts every visual on `AVATAR_LAYER` (1 << 11). LEGACY_LOOK reproduces the Chapter
One avatar exactly (60 mesh instances, 82 draw calls; pinned vertex by vertex and frame by frame against the Chapter One code in
`test_avatar_look_legacy.gd`); full outfits measure 79–88 draw calls, the worst mix ~108.

**After every rebuild** (`_after_rebuild`): `_chains` = the spring records of all units; `_scarf_ends` / `_braid` are derived from
them (kind "scarf" / the first "braid"; either may be empty); a new lower unit sets up `_skirt` (`SkirtRig`) and `_skirt_pivots`;
the roll hull is recomputed (below); `_patch` comes from the upper unit, `_lantern_belt` from the back unit. **A cape or shawl**
(back result `cape: true`) hides the jacket's back patch **and** the explorer scarf ends (their first segment); the scarf wraps at
the neck stay, and both come back when the cape is taken off.

**Per-look head hull** (roll clearance): `_head_hull = _HEAD_HULL` (the 14 Chapter One points) **+ the hull points of the hair,
hat and hair_acc units**. `_hull_points(unit)`: for results with `hull` "all" (hats, helms, buns: every part) or "direct" (hair: its
direct parts, never the spring chains), the support points of the unit's meshes under `_head_c` in 26 directions, kept only when
farther than `HULL_MIN_DIST` 0.28 m from `HULL_CENTRE`; plus the rest positions of listed `hull_nodes`, pushed out by their radius.
Tall hats therefore lift the roll (witch hat +18 cm, moth antennae +13 cm; every hairstyle except the side braid +6 cm).

**Public API** (the Chapter One methods are unchanged) — `apply_look(look) -> Array` (callable before `add_child`; a partial look
takes the legacy value for each missing key), `var appearance` (same as `apply_look`; set it before `add_child` to build once),
`apply_armor(on, equipment := {}) -> Array`, `set_show_armor(on) -> Array` / `var show_armor` (GameState.equipment when none was
given), `refresh_from_state() -> Array` (followers only), `current_look() -> Dictionary` (sanitized copy), `missing_ids() -> Array`,
`draw_call_estimate() -> int`, `var follow_game_state := true`, `set_held_tool(kind)` / `held_tool()` (wand, R100). A preview
avatar (not driven) ignores GameState; `src/ui/widgets/avatar_preview.gd` drives the real avatar in "live" mode.
Debug-only look args for non-driven avatars (preview stage): `--avatar-outfit= --avatar-hair= --avatar-hair-color= --avatar-skin=
--avatar-eyes= --avatar-hat= --avatar-armor=<armor set id>` (full command in AGENTS.md).

## 8. krystal_avatar.gd — animation (fully procedural node transforms, no Skeleton3D)

Controller inputs (set by player `_feed_avatar` 452 each frame): `driven, speed, grounded, vertical_speed, turn_rate, sprinting,
swing_kind, swing_t (0..1 or <0), roll_t, lantern_on, lantern_owned, lantern_energy_scale, look_target, has_look_target`.
`_process` (735): `dt=min(delta,0.05)`; if `!driven` `_run_demo`; `_update_weights` → `_reset_pose` → `_pose_locomotion` → `_pose_air` →
`_pose_lantern` → `_pose_swing` → `_pose_action` → `_pose_roll` → `_apply_pose` → `_keep_roll_above_ground` → `_update_face` →
`_update_secondary` → `_update_props`. The pose is a `PackedVector3Array` of 13 Euler rotations **assigned** to `joint.rotation` each
frame (anything else writing joint rotations is overwritten); `_body_off` offsets Rig; squash spring (k 170, damping 12, ±0.28) scales Body.
- Weights: `_move_w = clamp(speed/4.2)`, `_run_w = clamp((speed-4.6)/2.2)`, air, lantern, swing (decays 8/s).
- Walk/run: phase advances `speed / lerp(1.35, 2.05, run_w)`; footsteps at phase 0.25/0.75 (speed > 0.6, not swinging); leg, knee, arm
  amplitudes lerp walk→run; idle breathing, sway, random look-around every 5–10 s; head tracks `look_target` (yaw ±0.7, pitch −0.45..0.3).
- Swing: `SWING_KEYS` (54) kinds axe/pickaxe/sword/hands/gather; each has `"t"` (5 times) and 11 channels `sh_x sh_y sh_z el_x sp_x sp_y
  lsh_x lel_x knee body_y head_x` (5 values each), sampled with smoothstep (`_sample` 883). Strike pose at t≈0.44. Unknown kinds → "hands".
  Left-arm channels are skipped while the lantern is raised. `show_tool(kind, seconds)` shows `_tools[kind]` and auto-hides.
- Actions (`ACTION_TIME` 88): hurt .42, flinch .9, wave 1.8, cheer 1.6, eat 1.1, interact .45, tired .8, sleep/death loop (−1). Unknown names
  are ignored; "jump"/"land" only kick the squash spring. Face: blink timer, `_eyes_closed`, `_mouth_amt`, `_brow_worry`.
- Roll: tuck pose, `_roll.rotation.x = smoothstep(.05,.92,t)*TAU`, y-scale `1-.46 sin(πt)`, pivot lowered; `_keep_roll_above_ground`
  lifts the pivot so every point of the **per-look** `_head_hull` (§7: the 14 `_HEAD_HULL` points + hair/hat/hair_acc points) stays
  ≥ `ROLL_CLEARANCE` .02 m.
- Secondary (`_update_secondary`): local velocity from global position deltas (driven) or `(0,0,speed)` (not driven), jumps > 14 m/s
  rejected, accel ≤ 40; kept in `_lv` / `_acc` for the skirt. **One general spring-chain loop** over `_chains` (records from
  `AvatarKit.chain`), dispatched by kind: `scarf` (`_chain_scarf`, Chapter One formula, k 70 d 7.5), `braid` (`_chain_braid`: the
  Chapter One braid formula around each segment's rest rotation — braids, ponytails, hair curtains, ribbon tails; per-style k/d/amp),
  `cape` (`_chain_cape`: capes/shawls lift away from the back with speed, falls and running flutter, clamped so they never fold into
  her back; k 45 d 6), `wing` (`_chain_wing`: a flap whose phase `_wing_phase` is integrated per frame, so a speed change never makes
  the wings jump). Lantern pendulum (k 55, d 4) kept upright via `global_basis`.
- Skirts (`_update_skirt`, after the chains): `SkirtRig.update(dt, lv, acc, legs, knees, t, run_w, turn_rate)` → per panel pivot
  `rotation = (-flare, theta, side)`: base flare + bell + trail + running flutter, pushed out by the thigh/shin points of the
  current pose (legs never poke through while walking, running, jumping, on stairs), clamped to [min, max] flare (garment max 1.3 rad).
  **No roll sway**: the motion drive (`lv`, `acc`, `run_w`, `turn_rate`) is multiplied by `1 - _roll_blend`, so while she rolls the
  panels keep only their base flare and the leg push (a trailing hem would swing into the ground as the body tumbles).
- Props: raised lantern visible when `lantern_on` and not rolling; light follows `lantern_world_position()`; flicker × smoothed `lantern_energy_scale`.
Public API: `play_action(name, strength=1)`, `play_emote(name)`, `cancel_action(include_death=false)`, `current_action()`,
`set_food_color(c)`, `show_tool(kind, seconds=0.9)`, `set_body_visible(v)`, `reset_motion()`, `lantern_world_position()`,
`get_lantern_light()`, `play_anim(name)` (preview: idle walk run jump roll axe pickaxe sword hands gather lantern lantern_walk wave cheer flinch sleep eat hurt death tired).

## 9. camera_rig.gd

CameraRig (top_level) > Yaw > Pitch > {SpringArm (mask 1|32, sphere .2, margin .12), Camera (near .05, far 600)}. Constants: PITCH
−1.1345..0.6109 (default −0.3), ZOOM 2.5..8 step .55, TARGET_HEIGHT 1.38, SHOULDER .36, BASE_SENS .0045, MAX_SHAKE .6, HIDE/SHOW_DIST
1.0/1.15. Follows `target.get_visual_position()+1.38` (max lag 2.5 m); arm pulls in fast, eases out; shoulder offset is a real lateral arm
shift probed by sphere casts; after `snap()` a direct `cast_motion` places the arm; FOV +4 while `is_sprinting()`; shake only from
`Events.camera_shake` (zero with `reduce_shake`); hides the avatar via `target.set_avatar_visible()`. API: `setup`, `snap(yaw, reset_pitch=true)`,
`rotate_by(rel)`, `zoom_by`, `forward()`, `arm_length()`, `add_shake`, `shake_amount`, `get_camera`; fields `yaw`, `pitch`, `zoom_target`, `input_enabled`.

## 10. Performance tricks already in place
Bake + static caches (content-keyed `_bake_cache`, AvatarKit mesh/material caches, Mat/Kit); only changed units are rebuilt and
only the hosts they touch are re-merged (look change 1.5–19 ms, legacy build 6–16 ms); skirt maths on packed arrays; per frame 22–41 µs
(legacy vs heaviest look); probe at 12.5 Hz with preallocated queries; owned-item and terrain-height checks every 0.5 s; group scans only
on button press; manual render interpolation; lantern light skips Krystal as a shadow caster.

## 11. Pitfalls
- Avatar is top_level: children added to the **player** do not follow the avatar's rotation; attach visuals to avatar joints.
- Baking detaches the source parts of a host (kept in `_detached`, re-merged when one unit changes) and `_bake_subtree` frees merged
  parts: never keep references to part MeshInstances across a rebuild; keep the unit's container or the result's named nodes
  (chain segments, skirt pivots, patch, belt) — `_after_rebuild` refreshes those references.
- The merge cache (`_bake_cache`) is keyed by content **including colour** (fixed in Wave B): the player and a UI preview with different
  looks never share a mesh. Keep new parts' albedo in the toon material (the key reads it); a part that changes colour at runtime must
  stay unbaked (e.g. glowing cloth, which `_group_parts` skips).
- Never `set_shader_parameter` on a `Mat.toon()` result (shared across the whole game); use `Mat.toon_unique` or new cached colours.
- Secondary motion is one loop over `_chains` (any number of scarf ends / braids / capes / wings, including none); `_scarf_ends` and
  `_braid` are derived views and may be empty. A cape hides the patch and the scarf ends' first segment; a new back item that
  overlaps them should return `cape: true`.
- Skirt panels are rigid strips at their angle limit while rolling / sitting (sleep, death): expect ~3–4 cm leg overlap there, and long
  skirts can dip ~6–7 cm into the ground mid-roll (review B1). Belt lantern / satchel can clip flared skirts (visual check pending).
- Toon `wind` sways only vertices with model-space `VERTEX.y > 0` and uses world position: useless for skirts/capes hanging below a pivot
  (that is why skirts and capes use SkirtRig / cape chains).
- Height-coupled constants: camera TARGET_HEIGHT 1.38, look `head_h` 1.25, probe LOS +1.0, melee origin +0.9, `_HEAD_HULL` (+ the
  per-look hull points), tests. A new hat/hairstyle must report `hull` so the roll keeps it out of the ground.
- Appearance is cosmetic only: never add CollisionObjects, speed or reach effects to the avatar (spring arm, LOS and probe masks would
  hit them); `test_avatar_look_build.gd` asserts no look adds collision.
- Visual meshes are on layer 12 only; custom cameras / `light_cull_mask` must include `1 << 11`.
- `health.max_hp` changes do not emit `changed`; call `health.set_hp()` to sync GameState/HUD.
- HUD vitals read `max_stamina` from `GameState.player`, not from `_stamina.max_value`.
- `Logic.weapon_kind` returns "sword" for every cat "weapon"; `best_weapon()` picks any weapon/tool by `damage`.

## 12. Extension recipes

### (a) Runtime hairstyles / outfits / colours / hats / capes (no collision change) — DONE in Wave B (module B1)
As built (details in §7; the original plan's data file `data/avatar_styles.gd` and `GameState.player["appearance"]` were replaced by
the spec's `data/appearance.gd` catalogue and the top-level `GameState.appearance` section, spec §3/§4.1):
1. Data: ids from `data/appearance.gd` through ItemDB (`appearance_part`, `outfit`, `sanitize_look`, `legacy_look` ...); the look is
   `GameState.appearance`, show-armor is `GameState.wardrobe.show_armor`, armor pieces come from `GameState.equipment`.
2. Slot builders in `src/player/avatar/` build into **slot containers** per rig host (`_box(host_key, unit)`); joints, `_joints`,
   `_head_c`, `_eyes`, `_brows` are untouched by looks.
3. `var appearance` / `apply_look(look)` (set before `add_child` to build once) rebuild only the units whose signature changed, then
   re-merge only the hosts those containers sit on (`_rebake_host`). The merge cache is keyed by content (mesh, transform, **colour**),
   not by node path, so containers need no signature in their names.
4. Secondary motion: one **general spring-chain loop** over `_chains` (scarf / braid / cape / wing records from `AvatarKit.chain`);
   `_lv` / `_acc` are members; styles without a braid or scarf simply contribute no chain.
5. Skirt/dress sway: **skirt rig** `src/player/avatar/skirt_rig.gd` (panel pivots on a ring under the hips, spring toward trail +
   bell, legs push panels out as a hard constraint, clamped flare); `_update_skirt` runs after the chains and fades the motion drive out
   while rolling (**no roll sway**).
6. Hats/helms/buns report `hull` points → the **per-look head hull** (§7). **Cape rig**: a 2-segment `cape` chain from the chest;
   while a cape/shawl is worn the back **patch and the scarf ends are hidden** (the neck wraps stay).
7. Player: the player's avatar is `driven` and `follow_game_state`: it reads GameState in `_ready` and re-reads on
   `Events.appearance_changed` / `equipment_changed` / `game_loaded`; the wardrobe UI writes GameState and emits
   `appearance_changed` (it never calls the avatar directly). Still no CollisionObjects on the avatar.
**Adding a new part:** add it to `data/appearance.gd` (data module), then a branch in the matching builder that places parts through
`AvatarKit` materials/helpers into `ctx.box.call(host_key)`; return `chains` for anything that swings, `hull` for anything on the head,
`cape: true` for a back item that covers the patch/scarf, `skirt` for panels. Tests: `tools/test.sh avatar` (the legacy snapshot and
motion tests must stay exact), plus a visual check with the preview command in AGENTS.md.

### (b) Equipment stat layer
1. Pure `src/player/equipment_stats.gd` (RefCounted, testable like player_logic): `static func compute(equipped: Dictionary) -> Dictionary`
   → `{"armor": 0.0, "speed_mult": 1.0, "heal_mult": 1.0, "shield_max": 0.0, "max_hp_bonus": 0.0, "max_stamina_bonus": 0.0}` with caps
   (e.g. ARMOR_CAP 0.6, SPEED_CAP 1.3, SPEED_MIN 0.7). Item fields (integrator edits data/items.gd): `"equip": {"slot": "body", "armor": .1, ...}`.
   State: `GameState.player["equipment"] = {slot: item_id}`; keep equipped items in the inventory (`has_item`, lantern checks count only
   inventory + key items) and drop missing ones on `Events.inventory_changed`.
2. Player: cache `_eq := EquipStats.compute(...)` in `refresh_equipment()` (called in `read_from_state`, on `inventory_changed`, on equip) — never per frame.
3. Armor: `health.damage_taken_mult = 1.0 - _eq.armor` (health.gd already multiplies; `damaged` then reports the reduced amount).
4. Speed: at player.gd:375 `top *= _move_mult()` with `clampf(_eq.speed_mult * GameState.buff_mult("move_speed"), SPEED_MIN, SPEED_CAP)`.
   Dodge/knockback stay unscaled. Optionally add `avatar.speed_scale` so `_move_w/_run_w` thresholds scale (else fast walking blends into the run pose).
5. Heal multiplier: player.gd:899 `health.heal(heal * _eq.heal_mult)` (bed and respawn full-heal stay unscaled).
6. Shield absorb: new `src/player/player_health.gd` `extends "res://src/combat/health.gd"` with `shield`, `shield_max`, `signal shield_hit(absorbed)`;
   override `apply_damage`: same early returns (dead, invulnerable, ≤ 0, `_iframe_until_ms`), `a = amount * damage_taken_mult`, absorb from
   `shield`; if nothing remains emit `shield_hit`, `grant_iframes(0.3)` and return 0 (Combat then calls `on_hit_blocked` if the player defines it —
   use it for FX); else apply the rest exactly as the base does. Use it in `player._init` instead of HealthScript. Regenerate the shield in
   `_physics_process` when `seconds_since_damage() > N`.
7. Max HP / stamina: keep `GameState.player["max_hp"]` = **effective** max (bed, respawn, inventory and HUD read it) and store
   `"base_max_hp"`; on refresh set `health.max_hp = base + bonus`, then `health.set_hp(minf(hp, max))`. Stamina: `_stamina.max_value` **and**
   `GameState.player["max_stamina"]` together.

### (c) Ranged wand attack
1. Data: new category (e.g. `"wand"`, add to `CATEGORY_ORDER` and `ui_util.gd:19`) with `"ranged": {"damage": 12, "speed": 18, "range": 16,
   "cost": 10, "cooldown": 0.6}` and **no `damage` field** so `best_weapon()` and the sword test are unaffected.
2. Trigger: `_use_item` (852) new `"wand"` branch → `_cast_wand(id)`; or in `_start_swing` prefer the selected wand when no harvest target.
   Gate like attack (not dodging/eating/build mode); stamina via `_stamina.spend_soft/try_spend`.
3. Timing: reuse `_swing.start("wand", 0.5, 0.22)`; add a `_swing_ranged` flag; in `_on_strike` branch to `_fire_bolt()` before `_melee_hit()`.
   Clear the flag wherever `_swing_target` is reset (teleport, dodge, hurt, death).
4. Aim: `_soft_lock_dir()` has a 3.2 m radius; write `_ranged_target(range)` (one scan of group "enemy" on cast, LOS via
   `Combat.has_line_of_sight`, aim at `Combat.aim_point(t)`), else `rig.forward()`/camera ray. Face it via `_swing_face`.
5. Projectile: new `src/player/wand_bolt.gd` (Node3D, `setup({dir, speed, damage, range, owner})`, `Mat.glow` sphere, optional small
   unshadowed OmniLight): each physics tick one `intersect_ray` (or sphere `cast_motion` + `get_rest_info`) from the previous to the new
   position, mask 8|1|32, excluding the player RID; enemy hit → `Combat.find_health(t).apply_damage(dmg, owner, dir)`, `t.knockback(dir, f)`
   if present, `HitFx.impact(pos, dealt)`; world hit → `HitFx.spark`. Parent under `Game.area`; free on hit/range; no group scans per frame.
6. Avatar: add `"wand"` to `SWING_KEYS` (same `t` array, 11 channels × 5 values; a forward thrust e.g. `sh_x [0,-1.9,-1.55,-1.45,0]`), build a wand
   node in `_build_tools` and register it in `_tools`; `Logic.weapon_kind` stays untouched unless the wand also melee-swings.

### (d) Rotating avatar preview in a UI SubViewport
```gdscript
var box := SubViewportContainer.new(); box.stretch = true
var vp := SubViewport.new(); vp.own_world_3d = true; vp.transparent_bg = true
vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE; box.add_child(vp)
var pivot := Node3D.new(); vp.add_child(pivot)
var av: Node3D = load("res://src/player/krystal_avatar.gd").new()
av.set("appearance", app)            # recipe (a); set before add_child
pivot.add_child(av)                  # driven=false: idle breathing/blinks; play_anim("wave") for showcase
av.set("lantern_owned", GameState.has_item("lantern"))
var cam := Camera3D.new(); cam.position = Vector3(0, 0.85, 2.6); cam.fov = 30; vp.add_child(cam); cam.current = true
# + DirectionalLight3D (shadows off) + WorldEnvironment with ambient light; rotate `pivot.rotation.y += delta * 0.6` in _process
```
Notes: `own_world_3d` is mandatory (else the preview lives in the live area, lighting it and casting shadows). The default cull mask includes
layer 12. UI root is PROCESS_MODE_ALWAYS, so the preview animates while menus pause the tree. Rotating the pivot does not disturb the springs
(non-driven avatars use `(0,0,speed)` as velocity). Toon noise is world-space (pattern shifts slightly while turning). Recipe (a)'s
colour-aware bake key is **required** before the preview can differ from the live player. Free the viewport on close (~70 draw calls).

## 13. Risks (saves / tests)
- Save format: `GameState.player` keys and float types (§2) are read by `_load_player`, `Game._spawn_transform`, bed, respawn, HUD;
  renaming or retyping breaks old saves. New keys are safe; store strings/numbers only (JSON).
- `max_hp` semantics: if equipment writes a boosted max into `"max_hp"` without a base key, unequipping after a load cannot restore the base.
- tests/unit/test_player_node.gd pins: layer 2, mask 33, floor angle 46°, `health.max_hp` 100, `light_radius` 6.0, the contract method
  list, `apply_damage(15)` → hp 85 exactly (armor default must be 0), hurt i-frames (second hit 0), knockback exact values (5.0, no stacking,
  ignored while `_dodge_t` ≥ 0), eat heal = item heal exactly (heal mult 1), menu eats unlocked, walk speed, one harvest hit per swing,
  enemy priority (`best_weapon` damage vs. qa_dummy 30 hp), camera clamps/comfort/shoulder tests, emote names.
  It pokes privates: `_dodge_t`, `_eat_lock`, `_stamina`, `_on_attack_pressed`, `_interact`, `_command_ok`, `rig`, `avatar`, `probe`.
- test_player_avatar.gd uses `_head_c`, `_eyes`, `_blink_timer`, `roll_t`, `_process`: head centre y must stay 1.1–1.45 at idle and a 0.3 m
  hull around the head must stay above −0.06 m during a roll (hats/hair report their own hull points, §7).
- test_avatar_look_legacy.gd pins LEGACY_LOOK to the Chapter One meshes and motion (git 8de11a1 record, 1e-5): any change to the
  shared rig, springs or bake that alters the legacy look fails it. test_avatar_look_motion.gd pins skirt limits (hem above −0.08 m in a
  roll), cape/scarf hiding and the wing flap continuity; test_avatar_look_build.gd pins coverage, rebuild minimality and no collision.
- test_player_logic.gd pins the tuning constants and `weapon_kind` mapping; test_core_game_state `best_weapon` expects copper_sword
  preferred; test_core_inventory / test_core_item_db require every item category in `CATEGORY_ORDER`.
- test_audit_combat_ai_findings.gd:108 and test_enemies_boss_arena.gd:97 replicate `_melee_hit` numbers (sword 18 dmg, reach 2.5): change them
  together if the melee formula changes. player_demo.gd (debug QA) asserts walk/sprint speed, jump heights, dodge cost and sword damage.
- Player tests build the full avatar headless (heavy geometry slows the suite); a parse error silently swaps in
  `tests/preview/fallback_player.gd` (check the output for "script failed to load").
