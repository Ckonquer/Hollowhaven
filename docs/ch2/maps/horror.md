# Map: horror (director + authored moments)

Scope: `game/src/horror/*` (director, pure core, runner, silhouette, testbed), `game/data/horror_events.gd`,
`game/src/world/below/below_moments.gd`, `fake_lumi.gd`, `pale_shape.gd`, stalker hooks, tests
`tests/unit/test_horror_director_core.gd` (pure), `test_horror_director_node.gd` (scene),
`test_audit_horror_verify_stalker_pass.gd`, plus moment coverage in `test_below_progress.gd`,
`test_below_flow.gd`, `test_below_arachno.gd`. ARCHITECTURE.md "Horror" is assumed; this adds what it omits.
Paths below are relative to `game/`.

## 1. Construction and lifecycle

- `autoload/game.gd:258-266`: `director = null`; **only** `if target_area == "below"`:
  `ds.new()`, `name = "HorrorDirector"`, `setup({"area": area, "seed": Debug --seed or randi()})`,
  `area.add_child(director)`. Created after the player, before companions (so `Game.companion_nodes` is
  empty during `_ready`; it is read lazily each tick). `_free_gameplay_nodes()` (381) nulls it. No director on
  the surface or the debug arena. `DIRECTOR_SCRIPT` const at game.gd:13; a load failure is skipped silently.
- `director.gd:69 setup(params)`: stores `area`, `seed`, `tick_seconds = DIRECTOR.tick_seconds` (1.0, min 0.1),
  creates `Core` and calls `core.setup({"seed": seed})` **only** — `events`/`tuning`/`intensity` params are NOT
  forwarded (see recipe a).
- `director.gd:79 _ready`: creates child `EventRunner` (`runner.setup({"seed": seed + 7919, "log": core.log_line,
  "visibility": is_point_visible})`), connects `runner.event_failed`, `core.state_changed`, restores "once"
  flags, connects Events `paused_changed, safe_zone_changed, area_exiting, player_died, horror_event,
  cutscene_changed`; reads debug args; emits `Events.horror_state_changed(core.state)`.
- `_process` (108): accumulates delta, calls `tick_now(dt)` once per `tick_seconds` (1 Hz). `enabled=false` stops it
  (set by `area_exiting`; the testbed sets it to drive `debug_force` only).
- Director state (tension, cooldowns, recent) is **runtime-only**: rebuilt on every area load. The only
  persisted director data are `GameState` flags `horror_once_<event_id>` (director.gd:34, 407-415).

## 2. Data (`data/horror_events.gd`, shared foundation, read-only for modules)

- `INTENSITY[0|1|2]` keys: `name, desc, event_rate (0.45/1.0/1.5), damage_mult (0.6/1.0/1.15), allow_major
  (false/true/true), stinger_db (-12/-6/-4), darkness (0.75/1.0/1.15)`. Consumed by core, runner `_stinger`,
  `below_moments.intensity()`, `below_world.darkness()`, `Combat.intensity_damage_mult`, UI
  (`settings_schema.gd:109`, comfort screen, setting_rows cards).
- `DIRECTOR`: `tick_seconds 1.0, global_cooldown 14, major_cooldown 90, recovery_seconds 25, do_nothing_weight 3,
  max_active_threats 3, min_spawn_distance 9, max_spawn_distance 22, linger_seconds 12, unease_after 20,
  anticipation_after 45`.
- `EVENTS` (14 ids): distant_pickaxe, creaking_timbers, footsteps_behind, pebbles_fall, whisper, wrong_mochi
  (`once`), lantern_flicker, far_glimpse, lumi_notices (`needs_companion: "lumi"`), scratching_above (spider),
  web_rustle (spider), silence, gloomling_ambush (spawn, major, `enemy`, `count [1,2]`), stalker_pass (major,
  spider). Zones used: `mine, ruins, silk` only.
- Event keys: `kind, zones, states, weight, cooldown, major, min_intensity, anchor, sound, caption` (defaults in
  `director_core.gd:67 EVENT_DEFAULTS`) + optional `once, needs_companion, enemy, count:[min,max], alt_sound,
  alt_caption, spider`. `alt_*` are used **only if `spider: true`** and arachnophobia is on
  (`event_runner.gd:752-761`).

## 3. Core (`src/horror/director_core.gd`, RefCounted, pure)

`EXTRA_TUNING` (36-65) merged with `DIRECTOR`, then `setup({"tuning":{}})` overrides: decision_interval 12,
decision_jitter 0.4, start_grace 8, nothing_mult {calm 2.5, unease 1.5, anticipation 1.0}, linger_tension_mult
1.75, retreat_tension_mult 0.25, tension_scales_with_intensity true, anticipation_max 100,
encounter_clear_seconds 4, encounter_min_seconds 8, death_recovery_mult 1.6, authored_counts_as_major true,
low_hp_ratio 0.35, repeat_penalties [0,0.35,0.6,0.8], repeat_only_option_factor 0.35, fatigue_window 300,
fatigue_per_use 0.4, major_ramp 3, gentle_cooldown_scale true, glimpse 12-40 m, sound_anchor_max 30,
notice_max 28, scratch_max 9, stalker_max 30, default_anchor_max 35, suppress_hold_seconds 600, log_limit 400.

`setup(params)` (109): keys `seed, events, tuning, intensity`; resets everything (same seed ⇒ same run).
`director_zones` = every zone named by any event: tension only builds there; other zones are "quiet".

**State machine** (`tick`, 278-373, one call per second):
1. `ctx.paused` → returns immediately, clock frozen; first paused tick sets `cancel`.
2. `now += dt`; pending `_cancel_requested` → `cancel`; `suppressed_left -= dt`.
3. Zone change (`_on_zone_changed`, 734): active→active caps tension at `unease_after` (anticipation→unease);
   inactive→active delays next decision by `start_grace`.
4. `recovery`: counts down; at 0 → `calm`, tension 0.
5. `in_safe_zone` → unease/anticipation→calm, encounter→recovery(25), tension 0, return ("safe zone").
6. `threats_nearby>0` in calm/unease/anticipation → `encounter`. Encounter ends into recovery(25) when no
   threat for 4 s **and** ≥8 s in state.
7. Tension (active zone, tension states): `+dt * sqrt(event_rate)` (Gentle 0.67, Intense 1.22) ×1.75 if
   `lingering_seconds ≥ 12`, ×0.25 if `retreating`. `_update_tension_state` (702): calm→unease at 20, →anticipation
   at 45; anticipation lasting 100 s → tension=20, back to unease.
8. Gates (reason strings): quiet zone, encounter, recovery, suppressed, global cooldown, `now < next_decision_at`.
9. `next_decision_at = now + 12 * rand(0.6..1.4)`, then `_decide`.

Other transitions: spawn event → `encounter`; any other major → `recovery(25)`; `on_player_died` → recovery 40
(25×1.6), tension 0; `on_authored_event(id)` → recovery 25, tension 0, `last_event_time`/`last_major_time = now`.
`_enter_recovery` extends (max) if already recovering. `state_changed(new_state, reason)` signal.

**Eligibility** (`_ineligible_reason`, 493-540, in order): zone ∈ `zones`; state ∈ `states`;
`min_intensity ≤ intensity`; major needs `allow_major`; `once` not yet fired; `needs_companion == ctx.companion`;
per-event cooldown; major: major cooldown (`90 / max(rate,1)` → Intense 60) and `active_director_threats == 0`
(no stacking); spawn/major: `player_hp_ratio ≥ 0.35`, not `retreating`; spawn: `threats_nearby == 0`,
`enemies_nearby == 0` (idle room enemies ≤20 m: no pile-on); glimpse: not `sprinting`; spawn budget
`active + count_min ≤ max_active_threats (3)`. Then anchors (`_validate_anchors`, 544): anchors of the required
kind whose `zone` is `""` (wildcard) or the current zone; per-kind distance rules in `_anchor_problem` (573):
spawn 9-22 m and **not visible**; glimpse 12-40 m and **visible**; notice ≤28; scratch ≤9; stalker_pass ≤30;
sound/wrong_sound ≤30; other ≤35.

**Weights** (`_decide`, 416): `w = weight × event_rate × repeat_factor × fatigue × major_ramp`.
Stage 1: act vs nothing: `nothing_w = 3 × nothing_mult[state]` (7.5/4.5/3.0) against the **mean** eligible weight.
Stage 2: weighted pick. `_pick_anchor` prefers non-visible anchors for sound kinds, else uniform random.
Repeat factor by recency index (last event ×0, unless the only option: ×0.35); fatigue `1/(1+0.4·min(uses,4))`
within 300 s; majors in anticipation ×(1 + 3·t/100).
Cooldowns: global `14 / rate` only when rate < 1 (Gentle 31.1 s); per-event `cooldown`; firing also pushes
`next_decision_at ≥ now + 12`.

**Decision dict** (`_new_decision`, 753): `{event_id, reason, rejected:[{id,reason}], state, cancel, anchor,
event, kind, count, major, eligible_count, time}`.
**ctx dict**: `{zone, in_safe_zone, paused, player_hp_ratio, sprinting, retreating, lingering_seconds,
threats_nearby, enemies_nearby, active_director_threats, companion, intensity, anchors:[{name, kind, zone, room,
pos, dist, visible}], time}` — missing keys default harmlessly.

**Rollback** `on_event_failed(id, reason)` (203): if `_undo.id == id`, restores global/major cooldown times,
`once`, recency, history, stats, and the encounter/recovery the event started. The per-event cooldown stays.
`suppress`, death, authored events clear `_undo`.

`force(event_id, ctx)` (378): ignores pacing, still needs an anchor (falls back to the nearest anchor of that
kind regardless of distance rules). Marks fired.

## 4. Director node (`src/horror/director.gd`)

Constants (25-34): THREAT_RADIUS 20, ANCHOR_RANGE 48, ANCHOR_REFRESH 4, LINGER_RADIUS 2, RETREAT_MEMORY 12,
DESPAWN_DISTANCE 30, WORLD_MASK 1|32, VIEW_MARGIN 0.06, BLOCKING_MODES ["dead","loading","cutscene"].

`build_context(dt)` (195): no player → `paused`. `paused = tree.paused or (Game.area == area and (mode in
BLOCKING_MODES or Game.is_ui_open()))` — any open panel holds the director. Zone/safety come from
`Game.zone_id`/`Game.in_safe_zone` (polled by Game every 0.4 s from `area.get_zone_at/is_safe_zone`,
game.gd:56-68) when `Game.area == area`, else directly from the area (tests). `_scan_threats` (316): group
"enemy" with `is_threatening()` within 20 m; non-threatening, non-dead, non-`director_spawned` ones count as
`enemies_nearby`. Retreat = distance to last threat grew >0.8 m within 12 s. Companion = `GameState.active_companion`
if its node is in `Game.companion_nodes`.

`is_point_visible(pos)` (232): camera frustum test on `unproject_position` with rect grown by 6 % (points just off
screen count as visible → conservative for spawns) + one ray (mask 1|32) from camera; hit within 0.4 m counts as
visible. Anchors get `visible = is_point_visible(pos + UP*0.6)`.

`_execute` (389): env `{player, area, companion_node, intensity, arachnophobia, reduce_flashing}` → runner; on
`ok=false` → `core.on_event_failed`; on success stores once-flag and emits
`Events.horror_event(id, {kind, zone, state, major, pos})`. `tick_now` in `calm` also calls
`runner.despawn_far(player_pos, 30)`.

Signals consumed: `horror_event("authored:<id>")` → `core.on_authored_event` + `runner.cancel_all`;
`player_died` → core + cancel; `paused_changed(true)`, `safe_zone_changed(true)`, `cutscene_changed(true)` →
cancel; `area_exiting` → `enabled=false`, cancel, log summary. Emits `horror_state_changed(state)` (no in-repo
consumer yet — a Chapter Two MusicDirector can listen) and `horror_event` for executed events.

Public API: `setup, suppress(seconds, replace=false), get_state(), tick_now(dt) -> Dictionary,
debug_force(id) -> Dictionary (cheats), debug_probe_anchors() -> [{name, ok, reason, nudged}] (cheats),
build_context(dt), is_point_visible(pos)`, vars `core, runner, enabled, last_decision, last_context, debug_log`.

## 5. Runner (`src/horror/event_runner.gd`, child Node)

`execute(decision, env) -> {ok, note, pos, id, kind}` (90); unknown kind → fail (rolled back). Signal
`event_failed(event_id, reason)` for delayed failures. Constants: FLICKER_RADIUS 16, SPAWN_TELEGRAPH 0.9,
SPAWN_SPACING 1.3, SPAWN_NUDGE_RINGS [0.9,1.8,2.7]×8 dirs, SPAWN_MAX_STEP 0.6, STALKER_REAL_RANGE 28,
STALKER_HEAR_RANGE 12, LIGHT_CACHE_SECONDS 8, THREAT_GROUP "director_threat".

| kind | executor | behaviour / failure |
|---|---|---|
| sound, wrong_sound | `_run_sound` 210 | `Audio.play_3d` at anchor or 7 m behind/beside at +1.4 (`_event_position` 818); wrong: −3 dB, companion `react("scared")` after 0.8 s. Fails if `Audio.has_sound` false. |
| flicker | `_run_flicker` 227 | group `flicker_light` within 16 m → `flicker(1.2-2.0 s)`; else tween-dims Omni/Spot lights under area (gentle: one dip to 55 %). Fails with no lights. |
| glimpse | `_run_glimpse` 250 | `silhouette.gd` "glimpse" on floor below doorway anchor (ray), `stinger_soft`. |
| notice | `_run_notice` 276 | `companion.notice_threat(pos)`; checks `companion_id == needs_companion`. |
| scratch | `_run_scratch` 292 | sound at ceiling anchor + CPUParticles dust (26) + 3 pebbles (`_spawn_dust` 640). |
| silence | `_run_silence` 308 | `Audio.duck_ambience(-18, 12)`. |
| spawn | `_run_spawn` 316 | validate/nudge spot, hiss+caption now, `_do_spawn` after 0.9 s via `enemy_factory.spawn(id, area, xform, {"alert": true})`; meta `director_spawned`, group `director_threat`. |
| stalker_pass | `_run_stalker_pass` 346 | real stalker if its route is ≤28 m and perceivable (≤12 m or on screen) → `pass_overhead()`; else silhouette "cross" at ceiling anchor if perceivable and ≥3 m clear (`_crossing_path` 589). `stinger_major`, `camera_shake(0.12,0.5)`. |

Spawn point rules (`_validate_spawn_point` 508): 9 ≤ d ≤ 24 m; ground ray +1.5/−3; ground > anchor+0.6 = prop;
0.4 m sphere at ground+0.9 clear; probes at +0.4 and +1.3 **not visible**. Nudge (`_find_spawn_point` 462) only
for "inside geometry"/"no ground", stays in the anchor's room via `area.get_room_at()` else `get_zone_at()`
(`_same_space` 494). `_do_spawn` revalidates each spot at spawn time; zero spawned → `event_failed`.
`cancel_all(reason)` (131): drops pending (incl. telegraphed ambush), `cancel()`s silhouettes, frees dust,
restores dimmed lights; **spawned enemies stay**. Volume: `_trim_db` −3 at Gentle; stingers
`stinger_db + extra` via `Audio.play_sfx`.

## 6. Silhouette (`src/horror/silhouette.gd`)

`setup({variant: "spider"|"shade"|"" (=from setting), mode: "static"|"glimpse"|"cross", duration, target,
face, slip_dir, slip_distance, to, ceiling})`; add, then set `global_position` (cross starts deferred).
Glimpse: fade 0.3, hold, slip 1.4 m in 0.6 s, free. `cancel()` fades in 0.2 s; `finished` signal. Per-instance
duplicated alpha material (`TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`), shadows off, violet-black `BODY_COLOR`. It
does NOT swap on `settings_changed` (lives ≤2.2 s).

## 7. Authored moments (`src/world/below/below_moments.gd`)

Created by `below_world.gd:103` (`Moments.new(); setup(self); add_child`). Ticks every 0.1 s (skips in
`cutscene`/`loading`), `check(p, dt)` public; `player_override`, `hold` (QA), `fired` for tests. Room from
`Layout.room_at(pos)`; `_on_room_changed` forwards to `area.on_room_changed(old,new)` (drives the boss fight).
`_authored(id, secs)` (83) = `Events.horror_event.emit("authored:"+id, {})` + `Game.director.suppress(secs)`
(null-guarded). Every moment is once per save through flags:

| moment | trigger | flags | director |
|---|---|---|---|
| threshold | tunnel/side_passage, z∈(−24.5,−15.5) | `moment_threshold` | authored 35 s |
| crossing | hall, looking at doorway (dot>0.85) or 4 s; <11 m sets flag silently | `moment_crossing`, `crossing_clue_seen` | authored 45 s |
| imitation | shrine, z<−77.3 | `imitation_seen`, `imitation_folded` | authored 60 s |
| silk hollows | descent_low x>76 or webbed | `reached_silk_hollows` (quest objective, quests.gd:102) | emits authored only |
| silk intro | webbed x>81 | `moment_silk_intro` | suppress 40 at start, authored 40 on recoil |
| nursery | nursery/nursery_way | `moment_nursery` | suppress 12, rolling suppress(10) every 4 s, authored 30 once |
| return | lift up (`below_world.gd:674`) | `moment_return` | authored only |

Stalker `start_ambush` also emits `authored:stalker_ambush` (stalker.gd:202) → recovery.
Boss: `_start_fight` (below_world 548) emits `authored:boss` + `suppress(9999)`; `_director_suppress(20/240/30)`
on leaving/victory/death replaces the hold. Arena zone `boss` has no events → quiet anyway.

**Fake Lumi** (`fake_lumi.gd`): clones `res://src/companions/lumi_visual.gd` (fallback mesh if missing),
`process_mode = DISABLED` (no blink/gait/motes), removes every `Light3D`/particles, hides billboard halo, recolours
cold (`_cold_color`, `COLD_GLOW #cfe6ff`), hides eye highlights. Tells: cold glow, **no light cast**, snapping
jerks every 0.35-0.95 s (18 % a 55-80° head tilt), reversed `fake_lumi_chime` every 4.5-7 s (caption once
"[a familiar chime... played backwards]"). RNG seed 6660. Moments: `stare_at(player)` each tick; <4 m (XZ) →
`fold(stinger_db+2, !reduce_flashing)` (hiss, stinger_soft, caption, 0.12 s flash α0.12, tween, `folded`); leaving
shrine/wrong_way → `vanish()`. Real Lumi `react("scared")` + "[Lumi whimpers]" after 1.4 s.
**PaleShape** (`pale_shape.gd`): pale, emissive 0.18, no light; `setup({variant})`, awaitable `cross(from,to,s,linear)`,
`cling(pos, facing)`, awaitable `recoil(to, s)`; swaps rig live on `settings_changed("arachnophobia")`.

## 8. Stalker hooks (`src/enemies/stalker.gd`)

Group "stalker" only (NOT "enemy": the director never counts it as a threat). `pass_overhead() -> bool` (147):
false if not hidden, route <2, isolated point, or Gentle and emerge point <10 m; crawls 2-4 points of the connected
stretch nearest Krystal. Intensity tables: `LINGER_TIME [∞,5,3.5]`, `AMBUSH_COOLDOWN [∞,30,20]` (Gentle never
lunges). Runner reads its `route` property. `_hunt_allowed` respects safe zones and dead/cutscene/loading.

## 9. Captions

`Events.caption(text)` → `src/ui/hud/captions.gd`: shown only if Settings `captions`, max 3 lines, life 3.8 s,
identical text refreshes instead of stacking. Director captions come from event data (`alt_caption` for spider
events); moments hardcode text with `arachno()` ternaries. Empty caption = none.

## 10. Debug/QA

CLI (autoload/debug.gd): `--seed=<int>`, `--director-log=<path>` (file log), `--director-force=a,b` (cheats; first
after 3 s, then every 4 s), `--director-probe` (cheats; 2 s), `--below-moment=crossing|imitation|silk|return`
(below_world 704, sets `moments.hold`). Testbed `src/horror/debug/horror_testbed.gd` via `--preview=...
--preview-args='{"scenario":"glimpse|cross|scratch|flicker|ambush|idle","arachnophobia":false}'`; builds a mine
corridor at x=120 with a StandIn player (`get_camera/get_facing/is_sprinting`), anchors zone "mine".

## 11. Performance tricks

1 Hz director tick; anchor list cached 4 s (re-fetched only if a cached node was freed); anchors >48 m skipped
before the visibility raycast (≤1 ray/anchor/s); light cache 8 s; shared dust `SphereMesh`; one-shot particles free
themselves; silhouettes shadowless; moments at 10 Hz with pure box lookups; stalker checks every 0.15 s; logs capped
(400 lines, history 64/300 s).

## 12. Pitfalls

- Zones are the event filter. Reusing `mine/ruins/silk` in a new area imports Chapter One cues (pickaxe, gloomlings).
- Anchor meta `room` is informational (the Below stores the *space* id); nudging uses `area.get_room_at`.
- `floor` anchors are placed but no event requires them.
- Any `suppress()` after a hold (≥600 s) **replaces** it, including a moment's `suppress(40)` mid-boss.
- Quiet zones freeze tension but do not reset state; recovery still counts down.
- `ctx.paused` freezes the core clock, so cooldowns do not tick while a panel is open.
- `Combat.damage_mult_for_area` (combat.gd:235) scales damage only for area id `"below"`.
- `Game.in_safe_zone` is not reset on area load (updated within 0.4 s).
- Director-spawned enemies survive `cancel_all`/suppress; `despawn_far` runs only in `calm`.
- Sounds missing from `Audio` make sound events fail (rolled back); scratch still drops dust.
- `wrong_mochi`'s once-flag persists across saves (`horror_once_wrong_mochi`).

## 13. Extension recipes

### (a) Director in `hushed_works`
1. Integrator (foundation files): in `game.gd:259` replace `target_area == "below"` with a set, e.g.
   `const DIRECTOR_AREAS := ["below", "hushed_works"]`; add the scene to `AREAS` (game.gd:6); extend
   `Combat.damage_mult_for_area` to the same set.
2. Optional but recommended (horror module, additive): forward params in `director.gd:69`:
   `core.setup({"seed": seed_value, "events": params.get("events", HorrorData.EVENTS), "tuning": params.get("tuning", {})})`
   and let Game pass per-area data (`area.get("director_events")`). Otherwise append new events to
   `HorrorData.EVENTS` (integrator) with **new zone ids only**, e.g. `works_rails, works_sluice, works_bells,
   works_eyes, works_winch` — Chapter One RNG/decisions stay identical because ineligible events consume no RNG.
3. Area script (`extends area_base.gd`): `add_zone` or override `get_zone_at(pos)` (room boxes like
   `below_world.gd:287`), `get_room_at(pos)` (spawn nudge containment), `is_safe_zone(pos)` with safe areas at
   Service Landing, Pocket Conservatory, Bell Throat and every lit checkpoint (`add_safe_area` pattern, 278/349).
   Give Tool Lockers and Weaver's Crossing zones that no event lists (quiet), or omit `spawn` anchors there.
4. Anchors: `Marker3D`, group `director_anchor`, meta `zone` (must match event zones or be ""), `kind`
   (sound ~1.5-3 m up; doorway 0.2 m above floor with 12-40 m sightlines; ceiling 0.3 m under ceiling with ≥3 m
   clear sideways; spawn on floor, clear 0.4 m sphere, off critical sightlines), `room`. 3-6 per space. Run
   `--director-probe` and `debug_probe_anchors()` in a test.
5. Lights that should flicker: group `flicker_light`, `flicker(seconds)` honouring `reduce_flashing`
   (copy `below_lamp.gd:169`).
6. New kinds: add a `match` branch in `event_runner.execute` (101), a distance rule in `_anchor_problem` (573) +
   `EXTRA_TUNING` key; keep "fail gracefully → `_fail(note)`".
7. Moments controller for the area mirroring `below_moments.gd` (see b).
8. Tests: core test with `"events": {...}` override and zone `works_*`; node test with a minimal area
   (`test_horror_director_node.gd:47` pattern); run `tools/test.sh horror`.

### (b) Authored moments (new `src/world/hushed_works/works_moments.gd` + a small surface/manor controller)
Common skeleton: Node, `setup(area)`, 0.1 s tick skipping `cutscene/loading`, public `check(p, dt)`,
`player_override`/`hold`, flag `moment_<id>` set **first**, then `_authored(id, secs)`; pick all variants from
`Settings` at trigger time; captions for every meaningful sound; never damage.
- **Rails answer (Hask's Last Knock)**: in `works_rails`, arm when Krystal walked ≥N m then stands still
  (`player.is_moving()` false ≥1.5 s; Intense waits longer). Play knocks with `Audio.play_3d` at an actual rail
  point. Source rule: a *true* signal's position has a real lamp (Light3D + group `light_source`) within ~2 m and a
  visible reaction (lamp sway/dust); a *false* one comes from a dark sealed corridor with no Light3D nearby. Gentle:
  explicit source caption. Never make the choice audio-only. Test: assert Light3D presence/absence near each source.
- **False porch (Borrowed Porch)**: generic facade (never read `GameState.structures`); "warm lamp" = `Mat.glow`
  mesh, **no Light3D, not in `light_source`** (copy fake_lumi's stripping); true path gets an anchored flame
  (`below_lamp.gd`, real light). Interactable text (Gentle explicit). Intense: short fragment via `Audio.play_sfx`
  then `Audio.duck_ambience`. Rolling suppress while inside. Test like `test_below_progress.gd:274`.
- **Fake companion at wrong door**: reuse `FakeLumi.new()` at a door the real follower cannot occupy (behind a
  grate). Add optional additive params (e.g. `start_still_seconds` for Intense) rather than editing tells. Own flags
  (`moment_wrong_door`, `_folded`), not `imitation_*`. Keep: no Light3D, fold <4 m, real companion only `react`.
- **Scratching above the winch**: dust (copy `_spawn_dust`, it is private) + visible overhead thread route, then a
  stalker (`stalker.gd`, route over the winch) `pass_overhead()`; Gentle fewer passes (stalker already never
  lunges). Suppress on note read (`Interactable` handler). Optional director event
  `{"kind":"scratch","zones":["works_winch"],"anchor":"ceiling","spider":true,"alt_sound":"shade_drift","alt_caption":"[dust drifts down from above]"}`.
- **Turning pumpkin (surface, new region)**: no director exists there (`Game.director == null`; guard calls). Region
  controller: flag `ch2_moment_pumpkin_seen` when on screen (`cam.is_position_in_frustum`), rotate only while off
  screen after the player left and returned, set `ch2_moment_pumpkin_turned` (stem lesson: `ch2_moment_pumpkin_twitched`);
  on load build it already rotated from the flag. Must not be a crop/structure and must be outside the home safe area.
  Gentle wobble + caption; Intense: a distant face turns once while watched, no volume spike.
  **As built** (C2, `src/world/reach/west/pumpkin_moment.gd`, constants in `data/reach_west.gd` `FLAG_MOMENT_*` /
  `MOMENT_*`): the flags carry the `ch2_` prefix (not `moment_pumpkin_*`); the Intense on-screen turn happens only while
  she watches from **>= 16 m** (`MOMENT_INTENSE_MIN := 16.0`), not the > 25 m suggested here. **Lead decision (integration
  R135/R136 o): 16 m is kept** — it is still clearly distant (the pumpkin is ~0.8 m across, a small figure at 16 m) and the
  turn is silent and slow (2.4 s tween, then perfectly still), so it stays unsettling without a jump scare or volume spike.
  It emits `Events.horror_event("authored:pumpkin_turned", {pos})` so Mochi shelters from the real pumpkin.
- **Empty waltz cloaks (manor)**: on waltz stop (music end), after a delay (Gentle: longer preview while music
  plays; Intense: later), tween one cloak pair; near candle/lantern light (`Combat.light_at > 0.4`) reveal support
  wires. Non-damaging; flag `ch2_moment_empty_waltz` (as built by C4: `data/manor_layout.gd` `FLAG_WALTZ`, set FIRST,
  once per save; `src/world/manor/waltz_moment.gd`; authored silence event `authored:empty_waltz`).

### (c) Suppressing during bosses/puzzles
- Boss: on start emit `authored:<boss>` + `Game.director.suppress(9999)`; on leave/victory/death call
  `suppress(20..240)` (replaces the hold) — copy `below_world.gd:548-597`.
- Puzzles/notes: rolling `suppress(10)` every ~4 s while in the room (nursery pattern) is robust against other
  callers releasing a hold; or a zone with no events. Cutscenes: `Game.set_cutscene(true)` already pauses.
- If a stacking-safe API is needed, add additively `hold(id)`/`release(id)` (a set checked before
  `suppressed_left`) without changing `suppress` semantics (tested).

### (d) Arachnophobia-safe variants
Director events: `spider: true` + `alt_sound` + `alt_caption`. Visuals: runner hardcodes silhouette
`"shade" if arachno else "spider"` (event_runner.gd:265, 390) — add an event key (e.g. `silhouette`, `alt_silhouette`)
if Chapter Two needs veil/bell figures, plus a `_build_<variant>` in silhouette.gd. Long-lived shapes must swap
live on `Events.settings_changed("arachnophobia")` (pale_shape.gd:50, stalker.gd:692); set dressing via
`SpiderDecor` specs. Existing alt sounds: dir_scratch_soft, dir_root_creak, shade_drift, shade_telegraph,
shade_whisper, shade_shriek. Cover with a test like `test_below_arachno.gd:82` and
`test_runner_arachnophobia_swaps_visuals_sounds_and_captions`.

## 14. Risks (saves/tests)

- Save flags: `horror_once_*`, `moment_threshold/crossing/silk_intro/nursery/return`, `crossing_clue_seen`,
  `imitation_seen/folded`, `reached_silk_hollows` (quest), `weaver_defeated`. Renaming replays moments in old saves
  and breaks `test_below_progress`, `test_audit_persistence_below`, `test_below_flow`.
- Chapter Two moment flags (saved, once per save): `ch2_moment_pumpkin_seen/turned/twitched` (Reach west),
  `ch2_moment_empty_waltz` (manor), `ta_moment_echo` (Tobin's annex), `moment_hw_knock`, `moment_hw_wrong_door`,
  `moment_hw_winch`, `moment_hw_porch` (Hushed Works). The prefixes are inconsistent on purpose: the lead kept the local
  names (integration R136 r) because renaming saved flags later is riskier than the inconsistency.
- Editing existing `EVENTS`/`DIRECTOR`/`INTENSITY` values or adding events in `mine/ruins/silk` shifts RNG and
  pacing: breaks `test_do_nothing_frequency_30_minutes` ranges, `test_intensity_scales_cooldowns` (14/90/60),
  `test_zone_eligibility`, `test_state_eligibility`, `test_min_intensity_gentle_excludes_majors`,
  `test_debug_log_explains_decisions`, node tests that build decisions from real ids. Zone names `""`, `boss`,
  `mine_landing` must stay event-free (`test_quiet_zones_do_nothing`).
- `suppress` hold threshold/replace semantics are tested and relied on by the boss fight.
- `director.setup` must still work with `{"area","seed"}` only and with no setup at all (node test 171).
- Runner result keys `ok/note/pos` and `event_failed` drive rollback.
- Any Light3D added to FakeLumi/porch lamps breaks the "casts no light" tell and its test.
- Changing `Game` creation must keep "below"; `test_below_flow` swaps `Game.director` for a fake with `suppress`.
- INTENSITY `name/desc` feed the settings UI; `horror_intensity` 0-2 is a saved setting.
