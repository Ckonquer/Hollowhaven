# Map: combat_enemies (Chapter Two prep)

Scope: `game/src/combat/{combat,health,hit_fx}.gd`, `game/src/enemies/*.gd`, `game/src/enemies/debug/combat_sandbox.gd`,
`game/data/enemies.gd`, tests `tests/unit/test_enemies_*.gd`, `test_combat_core.gd`, `test_audit_combat_*.gd`.
Paths below are relative to `game/`. This map adds to docs/ARCHITECTURE.md ("Combat", "Enemies"); it does not repeat it.

## 1. Who builds what at runtime

| Node | Built by | Params |
|---|---|---|
| Brambling spawners x3 | `src/world/surface/landmarks.gd:_build_spawners` L624-648 | ids `ruin_bramblings` (count 3, respawn -1, quest flag `ruin_cleared`), `thicket_bramblings` (3, 720 min), `quarry_bramblings` (2, 720) |
| Gloomling spawners x2 | `src/world/below/below_world.gd:_place_enemies` L471-478 | `gallery_gloom` (2, r 3.0, respawn -1), `hall_gloom` (2, r 1.2, 720) |
| Stalker | same, L479-489 | not spawned once `weaver_defeated`; route/ambush from `below_layout.gd` STALKER_ROUTE/STALKER_AMBUSH |
| Boss + 3 braziers + cocoon | `below_world.gd:_place_boss` L492-525 | `{"arena_center": Layout.ARENA_CENTER, "anchors": ARENA_ANCHORS(5), "braziers": [...]}`. **No `arena_radius`/`crack` passed** -> boss default radius 11.5 (layout ARENA_RADIUS is 11.0). Braziers get `{"id", "anchor", "anchor_index"}` - **no `persist_flag`**, so they relight fresh on every area load. |
| Director ambushes | `src/horror/event_runner.gd:_do_spawn` L404-440 | `factory.spawn(id, parent, xform, {"alert": true})`, meta `director_spawned`, own budget `max_threats` = `HorrorData.DIRECTOR.max_active_threats` (3) |
| Debug | `enemy_factory.gd:debug_spawn_from_args` L66 (`--spawn-enemy=brambling:2`), sandbox `--sandbox=field|boss|stalker|spawner|area_boss|area_stalker|hits` |

All scripts are created with `.new()` + `setup(dict)` before `add_child`. `EnemyFactory.create` (L41) duplicates params, forces `p["enemy"]=id`, defaults `p["home"]=xform.origin`; `spawn` (L23) sets the local transform *before* `add_child` so `_ready` can override it (boss/stalker do). `SCRIPTS` (L10) maps `brambling, gloomling, weaver (stalker.gd), weaver_matron (weaver_boss.gd)`.

## 2. Combat core

### combat.gd (static, `extends RefCounted`)
Constants L21-28: `LOS_MASK=1|32`, `DEFAULT_TARGET_RADIUS=0.45`, `DEFAULT_AIM_HEIGHT=0.8`, `MAX_VERTICAL_REACH=1.7`, `LIGHT_CORE=0.45`, `PLAYER_LANTERN_RADIUS=6.5`, `HITSTOP_LIGHT=0.045`, `HITSTOP_HEAVY=0.06`.
- `melee(attacker, origin, forward, reach, arc_deg, damage, target_groups, knockback) -> Array` L38. Per call: `get_nodes_in_group` for each group (fine per swing, never per frame); for each target: `aim_point(t)` -> `in_arc(origin, fwd, aim, reach + target_radius(t), arc, 1.7)` -> ray LOS world|structure excluding attacker+target RIDs -> `find_health` -> `dealt = h.apply_damage(damage, attacker, dir)` where `dir` = flat origin->aim. `dealt <= 0` => `t.on_hit_blocked(attacker, dir)` if present, no knockback. Else `t.knockback(dir, knockback)`, `HitFx.impact(aim - dir*0.25, dealt, t.hit_color)`. After loop: one `Events.hitstop` (0.06 if any dealt >= 15 else 0.045).
- `in_arc` L91: `arc_deg >= 359` = full circle; targets closer than 0.6 m always count.
- `aim_point` L122 (`get_aim_point()` or pos+0.8 up), `target_radius` L130 (`hit_radius`), `find_health` L138 (`health` prop, else child "Health").
- `light_at(pos) -> float` L155: product of darkness over group `light_source` nodes (`is_light_active()`, `light_radius`, optional `light_strength`) with `light_falloff` L178 (1 inside 45% core, linear to 0 at radius), plus the player's lantern if the player is NOT in the group (it is: `player.gd` L101, `light_radius=6.0`). **Cache**: `_sources()` L192 re-reads the group once per process frame (`Engine.get_process_frames()`); `invalidate_light_cache()` L188 for tests/same-frame additions.
- Damage scaling: `current_intensity()` L223 (Settings `horror_intensity` 0..2), `intensity_damage_mult(level)` L227 (data/horror_events.gd INTENSITY: 0.6 / 1.0 / 1.15), `damage_mult_for_area(area)` L235 -> scales only when `area == "below"` (literal string).

### health.gd (Node)
Fields L12-17: `max_hp=100`, `hp=-1` (set to max in `_ready`), `dead`, `invulnerable`, `damage_taken_mult=1.0`, `_iframe_until_ms`.
`apply_damage(amount, source=null, dir=ZERO) -> float` L26: returns 0 if dead/invulnerable/amount<=0/inside i-frames; `dealt = min(amount*damage_taken_mult, hp)`; emits **`damaged` then `changed` then (if 0) `died`** - `dead` is set only just before `died`. `grant_iframes(s)` L43 (player dodge 0.3 s, hurt 0.6 s), `heal` L47, `set_hp` L59 (no signals but `changed`), `reset` L65, `ratio` L72.

### hit_fx.gd (static)
`flash(node, dur=0.11)` L79 delegates to `node.hit_flash()` or `node.visual.hit_flash()`, else additive overlay on all meshes. `impact(pos, dmg, color)` L190: burst + `hit_hard` (>=15) / `hit_soft`. `spark` L197 (glance), `wisps` L203, `chips` L176, `burst` L145, `new_tint()` L56 (alpha overlay for telegraph tints), `additive(color)` L34 (cached), `flash_strength()` L71 (x0.45 with `reduce_flashing`).
**Damage numbers**: `number(pos, amount, color)` L212: Label3D billboard, Fredoka, rises 0.7 m, fades by 0.75 s; global toggle `static var show_numbers := true` L28 (no Setting). Called only by `enemy_base._on_damaged` L567 and `weaver_boss._on_damaged` L601 (never for the player).
**Hitstop**: `ensure_hitstop()` L259 installs one `HitstopListener` under root (called from every enemy `_ready`); `_on_hitstop` sets `Engine.time_scale=0.05` for min(duration, 0.08) s **real time**, ignored while paused, restored in `_process`/`_exit_tree`. All particle/label/hitstop helpers are no-ops in headless (`DisplayServer.get_name()=="headless"`).
**Shake**: `Events.camera_shake(strength, dur)` -> `src/camera/camera_rig.gd:add_shake` L312 (clamped to `MAX_SHAKE=0.6`, zero with `reduce_shake`). Emitters: player hit 0.1/0.12 (`player.gd` L743), player hurt `0.15+amount*0.012` clamped 0.45 / 0.28 (L1003), boss slam 0.7/0.4, scorch landing 0.5/0.3, defeat 0.5/0.8, stalker hit 0.4/0.25, Pebble bonk 0.08/0.12.

## 3. Exact damage call chains

**Player -> enemy**: `player.gd:_on_strike` L709 (at `SWING_STRIKE=0.22` s of a 0.5 s swing) -> `_melee_hit()` L727: `dmg = max(item.damage, HAND_DAMAGE 5)`, `reach = item.reach` (hand 1.8, axe/pickaxe 9 dmg 2.2 m, copper_sword 18 dmg 2.5 m), origin = pos+0.9, `Combat.melee(self, origin, get_facing(), reach, MELEE_ARC 110, dmg, ["enemy"], 4.0)` -> enemy `health.apply_damage(dmg, player, dir)` -> `enemy_base._on_damaged` (flash, number, `_on_hurt`, flinch/retarget) -> back in melee: `enemy.knockback(dir, 4.0)`, impact FX, hitstop; player adds shake. Fallback `_fallback_melee` L758 only if combat.gd fails to load.

**Enemy -> player**: `enemy_base._physics_process` -> `tick` -> `_st_attack` L360: at `ATTACK_HIT_AT=0.18` s, `Combat.melee(self, pos + UP*body_h*0.5, _attack_dir, attack_range+0.2, ATTACK_ARC 80, attack_damage(), ["player"], data.knockback)`. `attack_damage()` L215 = `data.damage * damage_mult_for_area(data.area) * damage_scale`. Player `health.apply_damage` (dodge/hurt i-frames => 0, player has no `on_hit_blocked`) -> `player._on_damaged` L998: `grant_iframes(0.6)`, `Events.player_damaged`, shake, `knockback(d, HURT_KNOCKBACK 4.5)`, cancels swing -> then melee calls `player.knockback(dir, data.knockback)` which **replaces** (player knockback never stacks, ignored while rolling, L292). Death: `player._on_died` L1026 -> `Game.on_player_died` (mode "dead", `Events.player_died`, death screen, `respawn_player` resets hp from GameState).

**Boss slam** (`weaver_boss._slam` L427) and **stalker lunge** (`stalker._land` L353) bypass `Combat.melee`: flat distance test (boss `SLAM_RADIUS 2.4`, |dy|<2.2; stalker `HIT_RADIUS 1.35`, |dy|<1.6), then `find_health(p).apply_damage(dmg, self, dir)`; if dealt>0: `p.knockback`, `Events.hitstop(0.06)`. No LOS, no `on_hit_blocked`.

**Companion -> enemy** (exists): Pebble charge `companion.gd` L1398-1408 (`PEBBLE_CHARGE_RANGE 7`, cd 14 s, only targets within `CHARGE_MAX_RISE`) -> `_state_charge` L897 -> `_damage_enemy(target, 2.0, dir)` L1739 = raw `apply_damage(2.0, companion, dir)`: no knockback, no LOS, no FX/hitstop, no glance spark.

## 4. enemy_base.gd state machine (`CharacterBody3D`, layer 8, mask 1|32)
Constants L18-29: `GRAVITY 22`, `PERCEPTION_INTERVAL 0.2`, `FLINCH_TIME 0.32`, `FLINCH_IMMUNITY 1.6`, `ATTACK_TIME 0.42`, `ATTACK_HIT_AT 0.18`, `ATTACK_ARC 80`, `TELEGRAPH_TRACK 0.6`, `TURN_RATE 7`, `LEASH_HEAL_PER_SEC 0.35`, `LEASH_HEAL_DELAY 2.5`, `THREAT_STATES = chase, telegraph, attack, recover, flinch, backoff`. Pack fairness statics L71-80: `MAX_ATTACKERS 2`, `ATTACK_STAGGER_MS 850`, `_attackers` dict (instance id), `clock_override_ms` (tests), `reset_attack_tokens()`.

setup keys L106: `enemy, home, wander_radius|radius, spawner, no_drops, alert (+12 m aggro decaying 1/s), damage_scale`. `_ready` L123 builds capsule (`_body_radius/_body_height`), `Health` (max from `data.hp`), visual, connects `Events.player_died`.

Everything is decided in `tick(delta)` L221 (tests call it directly with physics off); `_apply_movement` L512 runs after it in `_physics_process`.

| state | logic |
|---|---|
| idle L300 | `_should_aggro()` -> chase; timer -> wander |
| wander L307 | random point in `wander_radius` around home at speed*0.55; 7 s cap |
| chase L319 | invalid -> return. In reach & `_cooldown<=0` & `_can_start_attack()`: token free -> telegraph (`telegraph_duration()` = data.telegraph); token busy -> circle at reach edge (tangent by instance-id parity) |
| telegraph L346 | tracks player for first 60%, then locked; end -> `_attack_dir=_forward()`, attack(`ATTACK_TIME`) |
| attack L360 | lunge `clamp(dist-0.75, 0, _lunge_distance())` over 60% of 0.42 s; hit at 0.18 s; -> recover(`recover_duration()`) |
| recover L373 | `_cooldown = data.cooldown` set on entry; end -> `_resume_after_interrupt` L394 |
| flinch / stunned | 0.32 s / `stun(s)` length, then resume |
| return L378 | walk home, heal 35%/s after 2.5 s unhurt, teleport home after 20 s |
| dead | `_on_died` L586 |
| other | `_st_custom(name, delta)` hook (Gloomling "backoff") |

`_enter(state, len)` L265: telegraph grabs the attack token; any state except telegraph/attack releases it; calls `_on_telegraph_start/_on_attack_start/_on_alert`, `visual.set_state(state, len)`, emits `state_changed`.
Perception `_perceive` L405 every 0.2 s: target = `target_override` > `Game.player` > group "player"; `hunt_allowed` L431 (Game.mode not dead/cutscene/loading/title, target health alive, not `is_respawning`, not `Game.area.is_safe_zone`); visible = dist <= aggro*2.2 and LOS on mask **1 only** (structures don't block sight, they do block melee). Aggro L452 also needs `home.distance_to(player) <= leash_radius`; `_chase_valid` L462 adds self within leash+4 of home.
Hit reaction `_on_damaged` L565: flash + number + `_on_hurt`; killing blow returns early; player source => retarget + `_alert_boost>=6`; attack/recover/stunned are uninterruptible; else flinch (then 1.6 s immunity) or idle->chase.
Knockback L178: `_knock = dir*force*_knockback_scale()`, added to velocity, decays `exp(-7t)`. Separation L546 (<1.3 m, cache of group "enemy" refreshed every 20 physics frames), stuck sidestep (0.8 s window, <0.35 m progress -> 0.7 s side step), void recovery (y < home.y-25).
Death L586: state dead, `collision_layer=0`, leave group "enemy", `_drop_loot` (`roll_drops` L605 static pure `[{item,min,max,chance}] -> [{item,count}]`, `give_drop` L625 -> persistent `world_item.spawn` else `GameState.give_item`), `stats.enemies_defeated += 1`, `Events.enemy_killed(id,pos)`, `defeated` signal, `await _play_defeat()`, `queue_free`. `Events.player_died` -> chase/telegraph/flinch/backoff go to return.
Hooks (override in subclass) L647-721: `_default_id, _build_visual, _body_radius, _body_height, _lunge_distance, _speed_scale, _knockback_scale, _can_start_attack, _perceive_extra, _tick_extra, _st_custom, _on_alert, _on_telegraph_start, _on_attack_start, _on_attack_resolved(hits), _on_hurt, _idle_sound, _play_defeat (coroutine)`. GDScript lets a subclass override any method (e.g. `_st_attack`, `_on_damaged` - signal Callables dispatch virtually).

### Subclasses and telegraph visuals
- `brambling.gd`: radius 0.42, height 1.0, lunge 1.3, leaf chips on hurt, spin+puff defeat. Visual `brambling_visual.gd` `set_state` L152, `hit_flash` L166, `_process` L170: telegraph = crouch, wiggle, thorns bristle, **red tint overlay** (`TELEGRAPH_TINT`, pulse `0.26+0.24*sin(22t)`, steady `0.3` with reduce_flashing), recover/stunned = orbiting stars; `_apply_tint` L260 toggles `material_overlay` only on change. Static merged thorn mesh.
- `gloomling.gd`: `EXPOSE_ON 0.4 / EXPOSE_OFF 0.3` (L11-12), `EXPOSED_DAMAGE_MULT 2`, `BACKOFF_TIME 1.3`, `BRAVE_TIME 3.5`; `_perceive_extra` L61 samples `Combat.light_at(pos+0.6)` (or `light_override`) and **overwrites `health.damage_taken_mult` every 0.2 s**; newly exposed during telegraph cancels the swipe (backoff); after backoff it is brave 3.5 s. Visual: telegraph = eyes swap to `EYE_FLARE` material + claw wind-up; `set_exposed(on)` squints; `fade` property tweened on defeat.
- Visual contract (duck typed): `set_state(name, len)`, `hit_flash(dur)`, reads parent `move_speed_now`, optional `set_exposed`, `set_clinging`, `body_height()`, `play_anim` (preview).

## 5. Spawner lifecycle and persistence (`enemy_spawner.gd`, Node3D)
Constants L23-27: `SPAWN_DISTANCE 45`, `DESPAWN_DISTANCE 70`, `TICK 0.5`, `MAX_SPAWN_STEP 1.6`. setup L47 keys: `enemy, count, radius, respawn_minutes, spawner_id, quest_flag_on_clear, clear_message, wander_radius, min_player_distance (7)`. Signals `cleared(id)`, `enemy_spawned(e)`.
`update_spawner` L109 (every 0.5 s): prune; >70 m => `despawn_all` (queue_free living); <=45 m and `wave_available()` and `_spawning_allowed` (mode, safe zone at player OR spawner) => spawn `count - defeated_in_wave - alive.size()` at once. `spawn_one` L139 parents enemies to the spawner's **parent**, passes `{"home", "wander_radius", "spawner": self}`, connects `defeated` one-shot, `pop_in()`. `_pick_position` L205: 8 tries, ground ray, rejects |dy|>1.6, prefers >= min_player_distance.
Persistence: `cleared_flag()` = `"spawner_cleared_<id>"` (flag), `cooldown_id()` = `"spawner_<id>"` in `GameState.depleted` (`deplete(id, minutes)`, -1 = never). `_on_wave_cleared` L170 sets both + quest flag + toast on first clear. `wave_available` L101: cleared & respawn<0 => never; else not depleted. `defeated_in_wave` is memory only (survives despawn, lost on area reload). Id-less spawners derive `"<enemy>_<x>_<z>"` lazily from position (L68).

## 6. Stalker (brief; `stalker.gd`, Node3D, group "stalker")
States `hidden, emerge, pass, rattle, lunge, landed, retreat, recoil`; in group "enemy" only while visible (`_enter` L283). Always invulnerable; `on_hit_blocked` L207 => spark + retreat. Ambush after lingering in darkness (<0.25) near an ambush point (`LINGER_TIME [inf,5,3.5]`) -> `start_ambush` L180 (1.0 s rattle) -> lunge -> `_land` (18 x intensity). Light >= 0.4 => recoil. `tick` runs in `_process`.

## 7. Boss: `weaver_boss.gd` (Node3D, **no collision body**)
setup L106: `arena_center, arena_radius (11.5, min 3), crack, anchors, braziers` (re-callable after `_ready`: re-initializes). `_ready` L134: `data = ItemDB.enemy("weaver_matron")` (hp **240**, damage 20, knockback 7), health invulnerable, connects `settings_changed`, `player_died`. `_initialize` L153: if flag `weaver_defeated` -> state "gone", invisible, `ensure_heartseed` if needed, return; else group "enemy", build visual + drop shadow, burn anchors under already-lit braziers, hang from `anchors[0]`, "dormant". `hit_radius 1.8`; `get_aim_point` L202 differs on ground vs ceiling.
Loop (`tick` L259 in `_process`, checks every 0.2 s): `dormant` -(player within arena_radius+3)-> `start_fight` L363 (bar, music, caption, hint, companions notice) -> `intro` 2.2 s -> `cling` (T_CLING range) -> 45% `reposition` to anchor nearest Krystal (not twice in a row) else `telegraph` L407 (drop target = Krystal clamped to radius-1.5, floor-probed; red-ring shadow disc shown) -> `drop` -> `_slam` L427: hit => `rebound` 0.8 s; miss => `stuck` + hint; pending scorch => `scorch_fall`/`scorched`. `stuck`/`scorched`/`rebound` end -> `climb` to nearest anchor -> `cling`. Standing down: >arena_radius+9 for 4 s in cling => `reset_fight`.
Timings by intensity [Gentle, Standard, Intense] L51-60: `T_CLING [[3.4,4.6],[2.3,3.3],[2.0,2.9]]`, `T_TELEGRAPH [1.6,1.2,1.1]`, `T_DROP [0.6,0.45,0.42]`, `T_STUCK [3.5,2.5,2.3]`, `T_SCORCHED [7,5,4.6]`, `T_CLIMB [1.6,1.3,1.2]`, `REPOSITION_SPEED [3.2,4.6,5.2]`; data telegraph/recover/cooldown are NOT used. Slam damage `data.damage * intensity_damage_mult(intensity())` (any area).
Armour: `_enter` L329 sets `health.invulnerable = state not in ["stuck","scorched"]` and `damage_taken_mult = 1.5` only in scorched. Blocked hits -> `on_hit_blocked` L217 (spark + hint). `_on_damaged` L599: `_window_damage` accumulates; >= 40% max (`WINDOW_CAP`) => shriek + climb. No phases beyond this.
Braziers: `_on_brazier_lit` L489 burns the anchor nearest the brazier (`_burn_anchor_near` L570, emits `anchor_burned`, ember FX), starts the fight if needed (not if Krystal is down/loading), then scorch: from stuck/scorched/rebound -> scorched; during drop -> `_pending_scorch`; else `scorch_fall` to `scorch_landing()` L529 (>= 2.6 m from braziers, >= 3.0 m from centre cocoon, inside radius-1.5). With all anchors burned it clings to the crack point above centre.
Defeat `_begin_defeat` L626: invulnerable, shriek, caption, shake, 1.4 s wait, tween up into `crack_point` (skipped by `fast_defeat` in tests) -> `_finish_defeat` L653: `gone`, leave group, bar hidden (`boss_health_changed(id, -1, max)`), **flag `weaver_defeated`**, `Events.boss_defeated("weaver_matron")`, `defeated`, stop music, `ensure_heartseed(parent, arena_center)`.
Heartseed: `should_spawn_heartseed()` L227 (static: defeated, not held, not `ward_restored`), `ensure_heartseed` L232 (static, dedups via group `heartseed_pickup`, parent children and static `_pending_seed`, adds deferred). `heartseed_pickup.gd`: interact -> `GameState.give_item("heartseed")`, `screen_flash`, is a `light_source` (radius 3, strength 0.5).
Reset: `Events.player_died` -> `reset_fight` L673 (dormant on nearest anchor, bar hidden, music stop); **keeps HP, burned anchors, lit braziers**. Nothing is saved: area reload/quit => full 240 HP, unlit braziers.
Events: `boss_health_changed` emitted on every `health.changed` only while `fight_started` (`_emit_health` L618); UI `src/ui/hud/boss_bar.gd:on_boss_health` L47 names it with `ItemDB.enemy_display_name(boss_id)`.
Arachnophobia: `_build_visual` L791 picks `ShadeVisual` (scale 2.3, upright, hangs `body_height()+0.1` under the anchor) or `WeaverVisual` (2.6, inverted on ceiling); `_on_settings_changed` L806 rebuilds live without touching timers; `_snd` L892 / `_caption` L906 swap names. Stalker does the same (L679/L692). Names via `alt_name`.
`boss_brazier.gd`: `KINDLE_TIME 1.5`, `KINDLE_MAX_DIST 4`, `light_radius 7`; `interact` needs item `lantern`; fizzles if kindler walks away or dies (`_on_player_died` L67); `light()` L112 (instant, persists `persist_flag` if set) -> group `light_source`, `lit` signal. No unlight API.
`below_world.gd` also drives the fight: `on_room_changed` L540 -> `_start_fight` L548 (calls `boss.start_fight`, `Game.director.suppress(9999)`), `_on_boss_defeated` L576 and `heartseed_cocoon.gd:_on_boss_defeated` L190 **ignore boss_id**.

## 8. data/enemies.gd shape
`ENEMIES[id] = {name, alt_name, hp, damage, speed, chase_speed, aggro_radius, leash_radius, attack_range, telegraph, recover, cooldown, knockback, drops:[{item,min,max,chance}], area:"surface"|"below", desc}` plus descriptive-only keys `light_fear, stalker, boss, sound, alt_sound` (not read by code). `ItemDB.enemy(id)` returns `{}` for unknown ids (silent defaults). The file is foundation (integrator edits).

## 9. Performance tricks already in place
Perception 0.2 s; separation cache every 20 physics frames; `light_at` group cache per frame; spawner tick 0.5 s; boss check 0.2 s, stalker 0.15 s; companions cache group "enemy" every 400 ms; shared static meshes/materials (thorns, particle sphere, fire); tint overlays swapped only on change; one hitstop node; FX skipped headless. Pinned by `test_enemies_perf.gd`: 20 enemies tick+move < 4 ms/frame; `light_at` with 12 sources < 40 us.

## 10. Pitfalls
- `damage_taken_mult` and `invulnerable` are owned by Gloomling perception / boss `_enter` - anything else writing them on those enemies is clobbered.
- `Health` signals fire before `dead` is set; handlers must check `hp <= 0` (enemy_base L571, boss L605).
- `apply_damage` returning 0 is the "blocked" signal everywhere (knockback, hitstop, on_hit_blocked).
- Enemy perception LOS uses mask 1; melee LOS uses 1|32.
- `damage_mult_for_area` scales only the literal area `"below"`; a new underground area id gets no intensity scaling.
- Static `_attackers` token table is shared by every enemy_base instance (elites/minions count toward MAX_ATTACKERS 2).
- Custom states release the attack token (`_enter` L274) and are not in `THREAT_STATES`, so `is_threatening()` (save gating `Game.can_manual_save` L508, director `_scan_threats` L316, companions) returns false unless overridden.
- `_on_player_died` ignores custom states. Projectiles/FX must not parent to the enemy (freed on death).
- Boss/stalker have no physics body: Krystal walks through them; melee LOS ignores them.
- `give_drop` introspects `world_item.spawn` arity (>= 3 args).

## 11. Chapter Two (Waves B/C + integration) — as built

Sections 1-10 map the Chapter One code; the recipes below (d) companion attacks and (e) armor/shields are built. Source of truth:
the headers of `src/core/stats.gd`, `src/player/player_health.gd`, `src/combat/projectile.gd`, `src/combat/combat.gd`,
`src/enemies/enemy_base.gd`, `telegraph_fx.gd`, `enemy_spawner.gd`, `enemy_factory.gd`.

**Stats (`src/core/stats.gd`, static, pure over saved state; B3).** Recomputed from GameState on every call (loading twice can't
stack a bonus). `damage_reduction()` (armor pieces add, then armor × Pebble passive × charms multiply, cap `REDUCTION_CAP` 45%;
20% armor + Pebble = 28%), `combine(a, b, c, d)`, `mitigate(raw)`, `armor_reduction()`, `player_shield()` (the shield on
`Game.player.health`; there is no GameState shield), `base_max_hp()` (= saved base 100) / `effective_max_hp()` / `max_hp_bonus()`,
`move_bonus()` / `slow_mult()` (never below `SLOW_FLOOR` 0.5) / `move_mult()` (+30% cap, × slow), `heal_mult()`,
`stamina_cost_mult(action)` ("sprint" | "dodge" | "swing" | "wand"), `gather_bonus()`, `bonus_yield_chance()`,
`harvest_power(tool)`, `best_tool(kind, min_tier)`, `best_melee_weapon()` (never a wand), `best_wand()`, `melee_damage/reach/dps`,
`wand_stats/damage/dps`, `best_weapon_tier()`, `companion_damage_mult()`, `apply_food_buff(item)` (same family: stronger replaces,
weaker only refreshes, never stacks), `meal_buff_mult()`, `lantern_radius_mult()`, `present_companion()` / `companion_value` /
`companion_passive` (only `GameState.active_companion` when `Game.companion_present(id)`: same area, ≤ 25 m), `equipped_effect`,
`mastery_value`, `buff_value`, `stat_rows()` / `companion_lines()` (inventory stats card). Legacy numbers unchanged (Copper Sword 18,
stone tools 9, walk 4.2 / sprint 7.0, dodge 0.3 s i-frames / cost 20, a 15-damage hit leaves 85 HP).

**Player damage order (`src/player/player_health.gd` extends health.gd; spec §9).** Processed exactly once per `apply_damage()`:
1. dead / invulnerable / amount ≤ 0 / inside i-frames → 0, nothing else (i-frames BEFORE damage);
2. reduction `Stats.damage_reduction()`;
3. shield (transient, `add_shield(amount, seconds, source) -> float`: never stacks, the larger wins, cap `MAX_SHIELD` 60; timer runs
   only while the tree runs; not saved) absorbs what is left AFTER mitigation;
4. Health (the rest; `damaged` reports the HP actually lost, `Events.player_damaged` follows it).
A hit the shield swallows completely returns 0 (the "blocked" convention: no knockback, no hurt), grants `SHIELD_BLOCK_IFRAMES` 0.3 s
and emits `shield_hit` / `Events.player_shield_changed` — **not** `Events.player_damaged` (lead decision R136 d: that is a
damage-taken event). `heal(amount)` applies `Stats.heal_mult()` itself (callers never scale; bed / respawn full heals unscaled).
`last_hit` = {raw, reduction, mitigated, absorbed, dealt} for tests. Special damage never silently bypasses armor.

**Player (B3).** `add_shield(...)`, `shield_amount()`, `apply_slow(mult, seconds, source) -> bool` (bounded: ≥ 0.5, ≤ 3 s, then
`SLOW_IMMUNITY` 2 s), `clear_slow()` / `cleanse_slow()`, `is_slowed()`, `resist_knockback(count, seconds)` (alias
`add_knockback_resist`), `move_mult()`, `refresh_stats()`, `selected_wand()`, `wand_cooldown_left()`, `last_bolt`. Area-aware checks in
`player_logic.gd`: `is_outdoor(area)` (surface, hallowmere_reach), `is_interior(area)`, `world_half_extents`, `in_world_bounds`,
`kill_y_for(area)` (hushed_works −60), `recovery_reason_bounds`, `lantern_tint(area)` (warm in interiors). Jumps: while airborne the top
speed uses at most +10% of the movement bonus, slows apply fully (R102). Enemies slow Krystal through `EnemyBase.apply_slow(t, ...)`,
which routes to the player's own `apply_slow` (limits + immunity).

**Wand (B3 + R100/R101).** With a wand selected on the hotbar, attack (or the use key) casts: stamina × `stamina_cost_mult("wand")`,
data cooldown, the target is picked by ONE scan of group "enemy" at cast time (`_ranged_target`: alive, in range, LOS, in the aim cone;
boss hazards score ×3 worse so a stunned boss beats a nearby trip-line), a spark leaves at `Logic.CAST_RELEASE` through the shared
projectile; never while eating, dodging or building; the wand is never picked for melee or mining. The avatar holds the wand and plays
a "wand" cast pose (`krystal_avatar.set_held_tool("wand")`, `wand_builder.gd`).

**Shared projectile (`src/combat/projectile.gd`, static `fire(params) -> Node3D`, null when refused).** Pooled (`MAX_LIVE` 32,
`POOL_MAX` 24, ≤ `MAX_LIGHTS` 4 with lights), straight flight, one ray per physics tick over the travelled segment (world \| structure
stops it), hits the first node of its target groups the segment touches, respects `health` / `can_be_hit_by` / `on_hit_blocked` /
`knockback` / `hit_radius` / `get_aim_point`. Params: shooter, from, dir \| target \| target_pos, damage, speed (16), range (14), radius,
lifetime, groups (["enemy"]), **`only_target`** (only that node can be hit; other bodies are passed through; a freed value hits nothing),
**`filter`** (Callable(candidate) -> bool), knockback, los_mask, color, light, max_per_shooter, parent, on_hit, hitstop, impact_fx, kind
(R60). Also `live_count(shooter)`, `pool_size()`, `stop_all()`, `invalidate_targets()`, `segment_distance(...)`.

**Combat (`combat.gd`).** `can_hit(target, attacker)` (melee respects `can_be_hit_by`), `INTENSITY_SCALED_AREAS := ["below",
"tobin_annex", "hushed_works"]`, `damage_mult_for_area(area)`, `intensity_damage_mult(level)`, `current_intensity()`.

**enemy_base.gd hooks (B8; additive — with the defaults every legacy enemy behaves exactly as before).** Properties
`committed_states` (custom attack states that keep the attack token, count as threatening, are never flinched), `needs_clear_shot`,
`defeat_flag` (setup key: flag set once on defeat), `damage_scale`, `target_override`. Hooks: `attack_reach()`, `_choose_attack()`,
`_telegraph_finished()`, `attack_def(id)` / `attack_telegraph(def)` / `attack_recover(def)` / `attack_damage_for(def)` (data
`attacks`), `can_be_hit_by(source)`, `can_stagger(amount, source)`, `_is_uninterruptible()`, `_stagger(...)`, `_on_alert()`,
`_on_telegraph_start()`, `_on_attack_start()`, `_on_attack_resolved(hits)`, `_on_hurt()`, `_tick_extra()`, `_st_custom()`,
`_perceive_extra()`, `_can_start_attack()`, `_speed_scale()`, `_knockback_scale()`, `_body_radius/_height()`. Helpers: `mark()` /
`hide_mark()` (this enemy's telegraph_fx), `charge_begin/charge_step/charge_lane_end`, `leap_begin/leap_target/leap_step/leap_land_hit`,
`lane_clip`, `lane_hits`, `pulse_hits`, `deal_damage_to`, `fire_projectile` / `projectile_in_flight`, static `apply_slow(t, mult,
seconds, immunity, source)` (bounded by `SLOW_MIN_MULT` 0.5 / `SLOW_MAX_SECONDS` 3), `announce_tell(def, caption)` (captions for
tells). `threat_damage_mult()` follows WHERE the enemy fights (R80): in a real, non-transient area `Combat.damage_mult_for_area(
Game.area_id)` (underground areas scale by horror intensity; surface, Reach and interiors never); in the Echo Trial and without an area
(tests) the data rule (`underground` / area "below"). Legacy enemies still use `attack_damage()` (data area), numbers unchanged.
Lead decisions: elites count as boss mechanics for Settings `timing_assist` (×1.5 wind-ups and recoveries: Matron, Quarry Warden,
Knotted Elder, R86); `brood_skitter` telegraph 1.0 s in data (R83).

**Ground telegraphs (`telegraph_fx.gd`, B8).** One lazily created top-level node per enemy (`enemy.mark()`), reused for every wind-up:
`show_ring(at, r, col)`, `show_disc`, `show_lane(a, b, w, col)` + `move_lane`, `show_arc(at, dir, r, arc, col)` + `move_arc`,
`show_spots(points, r, col)` (≤ `MAX_SPOTS` 8), `set_progress(k, lock)`, `hide_mark()`, `is_showing()`, `footprint()` (the SAME numbers the
attack resolves with; tests compare them), statics `closest_on_segment`, `segment_distance`, `segment_hit`, `in_sector`. Colours
`DANGER` / `WARN` / `COOL` / `ROOT` / `PALE`. Shared unit meshes + `LEVELS` cached alpha materials: nothing allocated per frame.
Comfort: `reduce_flashing` = no pulse (steady firming); `high_visibility_cues` = a bold cream outline (`BOLD`) around rings / discs /
lanes / arcs, switched live on `Events.settings_changed` (R87).

**Spawner params (`enemy_spawner.gd`).** Besides the legacy keys: `"enemy_params"` (Dictionary merged into every enemy's
`Factory.spawn` params; the spawner's own home / wander_radius / spawner keys win; e.g. Bramblewatch passes the Knotted Elder
`{"arena_center", "arena_radius": 10.0}`, R81) and `"out_of_view"` (default false: candidate points inside the current camera
frustum with a clear line of sight are rejected when a point is chosen — never per frame; if every candidate is in plain view the
wave waits for the next update; used by the moth pocket and the Bramblebacks, R82). `EnemyFactory.can_spawn(id)` (script exists AND
compiles) guards every area's spawn; a missing enemy never crashes (areas keep completability fallbacks, e.g. the annex Drudge, the
quarry Warden: kept, R136 s). All Chapter Two ids are registered in `EnemyFactory.SCRIPTS`.

**Bosses and hazards.** Bosses emit `Events.boss_encounter_changed(id, active)` / `boss_phase_changed(id, phase)` /
`boss_health_changed` and `boss_defeated(id)` (listeners must check the id: `heartseed_cocoon` only reacts to `weaver_matron`, R72).
`weaver_boss._exit_tree` releases a live encounter (hides the bar, `boss_encounter_changed(id, false)`) when the node is freed
mid-fight (R91). Matron floor hazards (`src/enemies/boss_hazards/*`: web fan / trip lines / egg sacs / threads, arachnophobia
alternates drifting root / veil / pale pods) carry **meta `boss_hazard`** (R89): strikeable by Krystal but skipped by companions'
threat scans (R61), the director's threat scan (R71) and ranked low by wand auto-aim (R101). The hazard field's zone slow is tagged
`"source": "matron_field"`, erases only its own slow, starts its break-free window after a cleanse, and the fan sheet never slows her
mid-jump (R88). Gentle: the Matron's drop gate ignores a minion out > `MINION_DROP_GATE` 20 s or unreachable (R90); Gentle minions keep
both damage reductions (intensity ×0.6 × minion ×0.8 ≈ 3.4 damage; intended, R136 c). The Chapter Two ordinary enemies, the
Quarry Warden and the three Chapter Two bosses are mapped in §12.

## 12. Chapter Two enemies and bosses (C5, C6a-c + integration pass 2) — as built

Source of truth: the headers of the scripts named below (each lists its setup keys, tells, reset policy and sounds) and
`data/enemies.gd`. Decisions: `docs/ch2/INTEGRATION_WAVE_D.md` (ids in brackets).

**Shared helpers added in pass 2 (`enemy_base.gd`, `telegraph_fx.gd`; additive, legacy enemies unchanged).**
* Horror intensity, OPT-IN (P01): `intensity_cooldown_mult()` (Gentle ×1.35, Standard 1, Intense ×0.8 on the rest after an
  attack), `intensity_telegraph_bonus()` (Gentle +0.2 s on a wind-up; Intense never shortens a tell), `overlap_blocked()` (Gentle
  only: true while another enemy holds an attack token, so no overlapping wind-ups). The six C5 scripts use them (their private
  copies are gone); Chapter One and Chapter One-extra enemies never call them. Committed wind-ups stay ≥ `MIN_COMMITTED_TELEGRAPH`
  1.0 s.
* `fire_projectile(from, t, params)` passes `dir` (a non-zero Vector3: fly straight along it, e.g. a throw along a locked lane; `t`
  then only gates the shot), `on_hit` (Callable(target, dealt), dealt 0 = blocked) and `kind` through to `src/combat/projectile.gd`
  (P02; the Patchwalker's clod uses it instead of calling the projectile directly).
* Attack-token table (P23): statics `attack_token_available_for(id)`, `claim_attack_token(id) -> bool` (same `MAX_ATTACKERS` 2 cap
  and `ATTACK_STAGGER_MS` 850 stagger as an enemy's wind-up; a new claim starts the stagger clock), `release_attack_token(id)`,
  `reset_attack_tokens()`; for attackers that are not enemy_base nodes (the Borrowed Choir holds a slot while it is committed).
* `telegraph_fx.move_ring(at)` (P04): moves a shown ring / disc with its fill, rim and high-visibility outline, no new meshes or
  materials (the Velvet Wing's drain mark follows Krystal with it). Tracking wind-ups use `move_lane` / `move_arc` / `move_ring`.
* `expose(seconds)` (D04): Lumi's Glimmerstep calls it on enemies inside its light pulse. Only the ordinary light-fearing enemies
  implement it - Velvet Wing (breaks a drain in progress, reason "light") and Borrowed Wisp (a forced reveal held for at least
  `seconds`, dazzled unless inside its dazzle cooldown). The bosses deliberately do not: their light rule is the arena mechanic
  (braziers, ward candles, lantern anchors), which pets and gear never bypass (MP 13).

**Ordinary enemies (C5; `src/enemies/<id>.gd` + `<id>_visual.gd`; sounds: existing names only - new voices are the open D10 item).**
| id | setup keys (besides the spawner's) | rules worth knowing |
|---|---|---|
| `pumpkin_mimic` | `dormant` (bool), `seed` (int, deterministic RNG for tests; L06) | Dormant = decor that twitches its stem twice: NOT in group "enemy" (companions, travel / save gates and swings ignore it), an interactable ("Inspect twitching pumpkin"), wakes on inspect or when Krystal lingers `WAKE_NEAR` 2 m for 0.5 s; `spot_allowed()` retires a dormant spawn in a safe zone or beside a crop plot / planter. **Spawners must not pass `dormant`** (P12): the orchard pocket twitches its own props and spawns awake mimics. Bite (wedge), roll (lane, unlocked after the first bite / below 70 %). |
| `patchwalker` | - | Rake sweep (wedge, staggerable wind-up) and a mud clod thrown STRAIGHT along its locked lane (`fire_projectile` `dir`), one per Patchwalker; a hit slows through `apply_slow` (bounded, never chained). Tells 1.1 / 1.6 s (longer tells kept, P11). |
| `velvet_wing` | - | Height is the reach tell (hangs / flies out of reach, dashes down, rests at 1.4 m). Drain tether: broken by ward-light only - lit ward candles, lamps / lantern posts / placed light structures, braziers, the Glimmerstep pulse, Krystal's raised lantern while she stands inside the drain mark (`DRAIN_MARK_RADIUS` 0.7) - or a line-of-sight break, range or a hit; **never by Lumi's passive glow** (lead decision L01; `ward_light_at()` skips groups "player" and "companion"). Intense: the only ordinary enemy with a feint (P11). |
| `bellcap_sentry` | - | One pulse ring (radius 4 m) with arrows, line of sight from the bell; the heavy wind-up is never staggered. |
| `borrowed_wisp` | - | Veiled (a false light: emissive only, not a `light_source`, every hit passes through) until real light reveals it (lantern within ~4.5 m, lamps, braziers, wards) - then reachable and hurtable; the first reveal dazzles it, later reveals within `DAZZLE_COOLDOWN` 6 s reveal without dazzling or cancelling a wind-up (P08). A one-time hint when Krystal is within ~4 m of a veiled, visible wisp while threatened (P10). The marked, delayed sweep (0.8 s) is kept (P09). One fixed wisp in the Hall of Closed Eyes (`data/works_layout.gd` `hw_sp_eyes_wisp`, P13), besides the director's `hw_wisp_drift` and the Choir's helpers. |
| `quarry_warden` (elite) | `arena` (node), `arena_center` (Vector3), `arena_radius` (float, ≥ 4; data default), `pillars` ([quarry_pillar nodes]; else group "quarry_pillar" within `arena_radius` + 3) | Spawned by the arena's guarded spawner `hr_sp_quarry_warden`. Slam (wedge, punish window), three spaced pulses (phase 2), a charge into a pillar = cracked pillar + EXPOSED window. **Leash**: the base leash AND within `arena_radius` + `ARENA_LEASH_MARGIN` 6 m of the centre AND within `ARENA_LEASH_DY` 3 m of its height (never engaged below the crystal shelf); leaving it or falling = a clean reset (pillars re-knit, full health). **Timing assist**: every wind-up, recovery and the pulse spacing ×`TIMING_ASSIST_MULT` 1.5 (elites count as boss mechanics, L03), exposure `EXPOSE_TIME_ASSIST` 7.5 s instead of 6. **Charge edge clip (D06)**: the lane end stays within `arena_radius` - `ARENA_EDGE_MARGIN` 1 m of the centre (the red lane shows the clipped length), and no floor within `LEDGE_PROBE_DEPTH` 1 m below its next step is a ledge = a wall bonk (stun while a pillar stands, exposed when none: never unwinnable), so a charge baited at the L2 edge never carries it down to L1. Encounter events `boss_encounter_changed("quarry_warden")` / bar / `boss_defeated("quarry_warden")` -> the arena sets `hr_warden_defeated` and toasts `TEXT["warden_clear"]` on the first clear (L02); counted once as a mastery encounter (P05). Not in `data/music.gd` BOSSES: ordinary combat music (P06). |

**Bosses (C6a-c).** Each is spawned by its arena through `EnemyFactory`; each emits `boss_encounter_changed` / `boss_phase_changed` /
`boss_health_changed` and, in story mode only, `boss_defeated(id)` exactly once, COMMITTED before any presentation. Setup key
`"mode": "story" | "trial"` - trial = no flags, no `boss_defeated`, no drops; the Echo Trial listens to `defeated`. Settings
`timing_assist` stretches warnings, openings and recoveries ×1.5; `reduce_flashing` / `high_visibility_cues` are honoured.
* **`count_velour`** (`count_velour.gd`, `velour_visual.gd`, `velour/*`; the manor's `moonveil_manor_world.gd` `_place_boss`). Setup
  `arena_center`, `arena_radius` (12), `candles` [ward_candle], `teach_candle`, `curtains` [Marker3D], `fixture`, `cover` [Vector3],
  `helper_points` [Vector3], `entry`, `area`, `no_drops`; optional `mode`, `auto_start` (default: true only without an `area`),
  `say_after_line`, `seed`. **In group "enemy" only while the encounter runs** (dormant he is Gallery scenery; removed again on
  defeat and on reset). API `start_fight()`, `reset_fight()`, `is_vulnerable()`, `is_reachable()`, static `phase_for(hp, max)`;
  signals `phase_changed`, `drain_resolved`, `candle_darkened`. Height is the reach tell; phase C's borrowed mask holds him above
  `MASK_FLOOR` until light has staggered him once. **Reset policy**: Krystal falls or leaves the Gallery = a clean reset (bats,
  tether, marks, channel and helper removed, every candle back to the fight's start state); wounds and phase are kept while the
  manor stays loaded; quitting / reloading = a fresh encounter; a won encounter is never reset. Trial mode: the retry hint has its
  own id `velour_retry_trial` with trial wording (P15). The manor shows the freed resident after the 1.4 s dispersal
  (`DEFEAT_PRESENT`, P14; instant on load). Counted once as a mastery encounter via `ch2_velour_defeated` (P05).
* **`crossing_matron`** (`crossing_matron.gd`, `crossing/*`; arena `src/world/works/deep/crossing_arena.gd` `boss_params()`). Setup
  `arena`, `arena_center`, `arena_radius`, `anchors` [5 ceiling Vector3, lines 0..2 first], `braziers` [3 line-braziers, index =
  line], `crack`, `bridge` (Rect2 in x, z), `deck_y`, `landing_points`, `alert`, **`rail`** (the guardrails' inner |z|; the arena
  passes `Layout.CROSSING["rail"]` since pass 2 (P19); the default is the bridge half depth - 0.2), `mode`, `minion_id`. Own id and
  state: never reads or writes `weaver_defeated`. **HP floor** `Rules.HP_FLOOR` [0.6, 0.25]: blows alone never take her below 60 %
  before the first exposure or 25 % before the second (the flare's scorch still can), so every win needs at least two exposures.
  `retreat_path()` / **`retreat_seconds()`**: the arena commits flags, reward and save at once but delays the gate's bars, sound,
  shake and line by max(`retreat_seconds()` - 0.8, 0) (P17), and ignores the bridge while Krystal is down (P18). **Geometry
  assumption (P21)**: `crossing_rules.gd` expects the bridge to run along X with its centre line at **z = 0** (lanes north z < 0,
  south z > 0, deck |z| ≤ rail); `data/works_layout_deep.gd` `CROSSING` matches - moving the bridge off z = 0 needs an offset in the
  rules. She never pounces while a minion lives (the release replaces the pounce). Arachnophobia: the Hollow Mother (look, anchors,
  threads, marks, sacs, minions, sounds and captions swap live).
* **`borrowed_choir`** (`borrowed_choir.gd`, `choir/*`; arena `choir_arena.gd` `boss_params()`). Setup `arena_center`,
  `arena_radius` 12.4, `perimeter_radius` 10.4, `anchor_nodes` [lantern_anchor ×3], `anchors` [Vector3 ×3], `resonators`
  [resonator ×2], `symbols` [{id, name, caption}], `arena`, `alert`, `mode`, `seed`. Hurt only while exposed: three correct reveals
  end phase A (false welcome), one or two resonator cycles phase B (stolen rhythm), **three kept-flame exposures** phase C - each
  exposure capped and floored (`choir_health.gd`), never a sponge. While committed it holds a slot of the shared **attack-token
  table** (`claim_attack_token` / `release_attack_token`, P23), so it never overlaps the wisps' wind-ups beyond `MAX_ATTACKERS`. The
  warm perimeter walk is safe from every Choir attack. Trial mode: retry hint `choir_retry_trial` (P57). The `data/enemies.gd` rows
  are descriptive and honest (P22: `arena_radius` 12.4, telegraphs = the `choir_rules.gd` Standard values, a `strikes` zone row);
  `choir_rules.gd` stays the source of truth.

## Extension recipes

*Status:* (a) and (b) are built as the Chapter One extras and the C5 enemies / C6 bosses (§11, §12); (c) is built as the Echo
Trial (`echo_trial.gd` + `data/trials.gd`, the bosses' `"mode": "trial"`; world_areas.md §8); (d) and (e) as §11 describes. The
recipes below are the original pre-build notes.

### (a) New ordinary enemy with distinct telegraphs
1. Integrator: add `ENEMIES["<id>"]` in `data/enemies.gd` (all keys of section 8; `area` decides intensity scaling).
2. Create `src/enemies/<id>.gd` `extends "res://src/enemies/enemy_base.gd"`; override `_default_id`, `_build_visual`, `_body_radius/_body_height`, sounds (`_on_alert`, `_on_telegraph_start`, `_idle_sound`, `_on_hurt`), `_play_defeat`. Visual `src/enemies/<id>_visual.gd` implementing the visual contract; telegraph tints via `HitFx.new_tint()` with the reduce_flashing steady branch (copy brambling_visual L192-205).
3. Register in `enemy_factory.gd` SCRIPTS L10.
4. Attack kinds: keep the base telegraph, then branch. Pick the kind in `_on_telegraph_start` (store `_kind`), override `_st_telegraph` so that at `state_time >= _state_len` it enters a custom state (`"charge"`, `"leap"`, ...) instead of `"attack"`, implement it in `_st_custom`, and finish with `_enter("recover", recover_duration())`. Override `is_threatening()` to include custom states, `_on_damaged` if they must not be flinch-interrupted, and consider holding the token by overriding `_enter` (re-add `_attackers[get_instance_id()]`).
   - Charge: `_desired_vel = _attack_dir * speed`; one-shot `Combat.melee(self, ..., reach 1.0, arc 90, ...)` when the player is close; `is_on_wall()` -> `stun(1.5)` as the punish window. Telegraph: tint + head-down pose + ground arrow.
   - Projectile: new `src/combat/projectile.gd` (Node3D, own `_physics_process`, parented to `Game.area`), hit test by distance to `Game.player` aim point + ray LOS (`Combat.has_line_of_sight`), damage through `Combat.find_health(p).apply_damage(dmg, shooter, dir)` so dodge i-frames work; `knockback`, `HitFx.impact`, `Events.hitstop`. Spawn at the release moment of the custom state; telegraph = glow build-up on the visual + aim line.
   - Radial pulse: `Combat.melee(self, pos, fwd, radius, 360.0, ...)` (full circle); telegraph = floor ring, reuse boss `_build_shadow`/`_update_shadow` L818-858 (disc + additive torus, top_level, steady with reduce_flashing).
   - Dash line: snapshot segment start/end at telegraph end, show a thin floor box; resolve with a new static helper (e.g. `segment_hit(a, b, width, target)` in combat.gd or `src/combat/shapes.gd`) then `apply_damage`.
   - Leap: copy stalker `_begin_lunge/_land` (arc lerp + landing circle); override `_apply_movement` to skip gravity/`move_and_slide` while in `"leap"` and set `global_position` directly; landing damage by flat distance like `_slam`.
5. Place via spawner `setup({"enemy": "<id>", ...})` or director event `"enemy": "<id>"`.
6. Test like `test_enemies_state.gd`: `Factory.create`, `set_physics_process(false)`, `target_override = dummy`, `Base.clock_override_ms`, `Base.reset_attack_tokens()`, step `tick(DT)`.

### (b) Elite / boss with phases and minion budget
- Elite (ground): subclass enemy_base; bigger data hp; phases from `health.changed` -> `health.ratio()` thresholds changing `damage_scale`, telegraph durations (override `telegraph_duration()`), attack kind pool. Remember the shared 2-attacker cap.
- Boss: follow weaver_boss: Node3D/CharacterBody3D, group "enemy", `health` child, `hit_radius`, `get_aim_point`, `is_threatening`, `on_hit_blocked`, own `tick` + `_enter` that owns `invulnerable/damage_taken_mult`, `Events.boss_health_changed(id, hp, max)` only after the fight starts and `-1` to hide, `Events.boss_defeated(id)` once, `defeated` signal, a `WINDOW_CAP`-style per-opening damage cap. Phases: `var phase` recomputed in the `health.changed` handler; table in data (`"phases": [{"at": 0.66, ...}]`); transition via an invulnerable "shriek" state.
- Minions: `Factory.spawn(id, get_parent(), xform, {"home": arena_center, "wander_radius": arena_radius, "alert": true, "no_drops": true})`; keep `_minions` array, prune with `is_instance_valid`, cap alive (e.g. 3) + cooldown; connect `defeated`; free all on `reset_fight`, player death and defeat. Set data `leash_radius` >= arena size (leash is measured from `home`). The director budget is separate - suppress the director during the fight (`Game.director.suppress(9999.0)`, then a short suppress to release, as below_world L548-573).

### (c) Instance-separate boss encounter (trial) with its own flags
1. First fix the listeners: `below_world.gd:_on_boss_defeated` L576 and `heartseed_cocoon.gd:_on_boss_defeated` L190 must check `boss_id == "weaver_matron"` (integrator), else any `boss_defeated` in "below" sets `weaver_defeated` and opens the cocoon.
2. Parametrize weaver_boss (defaults preserve Chapter One): setup keys `boss_id` (replace const `BOSS_ID` uses at L135, L619, L658, L660, L683), `defeat_flag` (default `"weaver_defeated"`, used L167, L228, L659), `reward` (`"heartseed"` or none: skip `ensure_heartseed` at L172/L663; `_pending_seed` is static and shared). Or subclass `src/enemies/<trial>.gd` overriding `_initialize`/`_finish_defeat` - but `should_spawn_heartseed` is static and called by below_world, so keep it untouched.
3. Data entry `ENEMIES["<trial_id>"]` (hp, damage, name/alt_name for the boss bar) + factory SCRIPTS entry.
4. Flags namespaced `trial_<id>_cleared` (+ counters for best time). Never reuse `weaver_defeated` (lift, stalker, cocoon, quests key on it).
5. Braziers: pass `persist_flag = "trial_<id>_brazier_<i>"` only if lit state must survive reloads; for replayable trials add `extinguish()` to boss_brazier.gd (leave `light_source`, hide flame/light, clear flag) and call it plus `health.reset()`, `_initialized = false; _initialize()` in a full reset.
6. Arena: own `arena_center`, `arena_radius`, `crack`, anchors; start via room change or the built-in dormant proximity (radius+3).

### (d) Companion attacks hitting enemies
- Replace `companion.gd:_damage_enemy` L1739 with `Combat.melee(self, origin, fwd, reach, arc, dmg, ["enemy"], knock)` to gain LOS, knockback, impact FX and boss-armour sparks; to avoid hitstop/FX spam, add an options variant (e.g. `melee_ex(..., {"hitstop": false})`) to combat.gd.
- Enemy side: `enemy_base._on_damaged` L573 retargets only on `"player"` sources; companion hits still flinch. Enemies attack only `["player"]` (L366-367) - keep that (contract: companions are never damaged).
- Boss: companion damage lands only in stuck/scorched and counts toward `_window_damage`; stalker: `on_hit_blocked` makes it flee.
- Kills by companions still emit `enemy_killed`, count stats, drop loot and advance spawner clears.

### (e) Player armor and shields
- Single choke point: `health.gd:apply_damage` L26 on the player's `Health` (all three enemy paths call it). Order today: raw `data.damage * intensity * damage_scale` -> `* damage_taken_mult` -> clamp to hp.
- Percentage armor: player-owned `health.damage_taken_mult` (nothing else writes the player's) recomputed from equipped items (new `data/items.gd` key e.g. `"armor": 0.15`) on `read_from_state` and `Events.inventory_changed`. Flat armor/absorb shield: add `armor: float` and `shield_hp: float` + local signal `shield_changed` to health.gd with defaults 0 (behaviour unchanged), subtract before the hp clamp, return only hp damage (or total, but decide: callers treat `0` as "blocked").
- Directional block: in `apply_damage` ask the owner `get_parent().filter_damage(amount, source, dir) -> float` if present; player compares `get_facing().dot(-dir)`. Return 0 on a full block => `Combat.melee` calls `player.on_hit_blocked(attacker, dir)` (implement for spark/stamina/push-back); boss slam and stalker lunge do not - add the same call there.
- Keep `Events.player_damaged` only for dealt > 0; derive stats from items rather than new save fields (GameState is foundation).

## Risks (saves/tests)
- Tests pin data values: brambling hp 30, damage 10, telegraph 0.7, recover 1.1, cooldown 1.6; boss hp 240, damage 20, x1.5 scorched, 40% cap, `T_*` tables, Gentle 0.6; stalker damage 18; gloomling exposure thresholds; `ATTACK_TIME`, `ATTACK_STAGGER_MS`, `MAX_ATTACKERS`, flinch rules (`test_enemies_state`, `test_enemies_boss`, `test_enemies_review`, `test_enemies_stalker`, `test_combat_core`).
- Health signal order / return semantics and `find_health` conventions are relied on by player, companions, tests.
- Flag and depletion ids are save data: `weaver_defeated`, `ruin_cleared`, `spawner_cleared_<id>`, `depleted["spawner_<id>"]` for the five spawner ids; renaming ids or moving id-less spawners resets progress or respawns cleared waves.
- Emitting `Events.boss_defeated` for any new boss in "below" before fixing the two listeners corrupts Chapter One state.
- `is_threatening()` and group "enemy" membership gate surface saving and the director.
- `test_enemies_perf` budgets break with per-tick raycasts or group scans.
- `test_enemies_review` reads `brambling_visual._tint_mat`; arachnophobia swap tests expect fight state untouched by visual rebuilds.
- Boss/brazier state is intentionally unsaved; adding persistence needs GameState fields and migration (foundation).
