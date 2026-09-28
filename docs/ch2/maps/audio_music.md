# Map: audio_music (Audio autoload, music selection, ambience, synthesis toolchain)

Scope: `game/autoload/audio.gd` (939 lines), every runtime caller of music/ambience, `tools/audio/*`,
`game/assets/audio/*`, `game/tests/unit/test_audio_*.gd`. It adds to docs/ARCHITECTURE.md (sound-name list,
Audio API names). Line numbers are for the tree as of 2026-09-27.

## 1. How it is built at runtime

- Autoload order (`game/project.godot` [autoload]): Events, Settings, ItemDB, GameState, SaveSystem, **Audio**, Game, Debug.
  Audio starts before Game, so it looks `Game` up lazily (`_read_game_mode()` :866 → `get_node_or_null("/root/Game")`).
- `_ready()` :243: `process_mode = ALWAYS`, `_setup_buses()` :266, `_build_index()` :286, reads `arachnophobia`, then
  creates **65 pooled players**: 20 `Sfx%d` (SFX_VOICES), 10 `Ui%d` (UI_VOICES), 28 `Pos%d` 3D under child `World3D`
  (VOICES_3D), a music `Deck` of 3 players (MUSIC_DECKS) and 2 ambience layers × 2 players (AMB_LAYERS, AMB_DECKS).
  It connects `Events.settings_changed` → `_on_setting_changed` :376 and `Events.area_exiting` → `_on_area_exiting` :893.
- **Buses are created in code** (there is no `default_bus_layout.tres`): Music, Ambience, SFX, UI, each sending to Master.
  An `AudioEffectHardLimiter` (ceiling -1.0 dB) is added to Master once. Volume: `_set_bus` :354 =
  `linear_to_db(max(l,1e-4)) + duck_db`, muted when linear <= 0.001. Keys (`VOLUME_KEYS` :41): master_volume,
  music_volume, ambience_volume, sfx_volume, ui_volume. Defaults (`autoload/settings.gd:16-20`): 0.85 / 0.6 / 0.8 / 0.85 / 0.7.
- Everything is a child of the autoload, so **everything inherits PROCESS_MODE_ALWAYS**: music and ambience keep
  playing while the tree is paused. World voices are paused by hand (see §4).

## 2. Public API (audio.gd)

| Line | Signature | Notes |
|---|---|---|
| 452 | `has_sound(name: String, exact := false) -> bool` | exact = real file/variants only |
| 459 | `get_stream(name) -> AudioStream` | random variant or null |
| 464 | `resolve(name) -> String` | after arachno swap/aliases, "" if missing |
| 469 | `sound_names() -> Array` | every index key, sorted |
| 476 | `preload_sounds(names: Array)` | **no caller today** |
| 386 | `duck(bus, db, seconds, attack := 0.4, release := 1.5)` | deepest overlapping duck wins |
| 394 | `duck_ambience(db, seconds)` | = `duck("Ambience", db, max(seconds-3, .5), 1.5, 1.5)` |
| 442 | `get_duck_db(bus) -> float` | includes pause dip for Ambience |
| 679 | `active_voices(name) -> int` | tests/debug |
| 694 | `play_sfx(name, volume_db := 0.0, pitch_var := 0.06)` | while paused → UI pool (never paused) |
| 709 | `play_ui(name, volume_db := 0.0)` | UI bus, pitch 1.0 |
| 723 | `play_3d(name, pos, volume_db := 0.0, pitch_var := 0.06, max_distance := 30.0) -> Node` | pooled AudioStreamPlayer3D or null |
| 744 | `stop_world_sounds(fade := 0.3, include_non_positional := false)` | tween to -60 dB then stop |
| 772 | `stop_all()` | every voice + music + ambience, instantly (Game.quit_game :550, close :122, tests) |
| 796 | `play_music(name, fade := 2.0)` / 809 `stop_music(fade := 2.0)` / 813 `current_music() -> String` | |
| 817 | `play_ambience(name, fade := 3.0, layer := 0)` / 833 `stop_ambience(fade := 3.0, layer := -1)` / 839 `current_ambience(layer := 0)` | |
| 125 | `var min_retrigger_ms := 35` | tests set 0 |

Audio emits **no signals** and never emits captions.

## 3. Name resolution and caches

- `_build_index()` scans `res://assets/audio/{sfx,ui,ambience,music}` for `.wav/.ogg` (also `.import`/`.remap` for exports).
  Each file is indexed under its stem **and**, if the stem ends in `_<int>`, under the base name (`music_x_2` becomes a
  variant of `music_x`). `.wav` and `.ogg` with the same stem both land under that key and are then treated as variants.
- `_resolve(name)` :528: arachno swap (`ARACHNO_ALT` :90, only when the alt exists) → exact files → `_alias` :512
  (`ALIASES` :96, `PREFIX_FALLBACK` :106 per prefix with `"*"` default) → "" (warned once). Results go into `_resolved`,
  which is cleared on an arachnophobia change.
- `_streams()` :554 `load()`s every variant **synchronously on first use** and keeps it in `_cache` **forever (no eviction)**.
  `_pick()` :569 uses the **global `randi()`** and never repeats the last variant.
- Voice dict (`_new_voice` :337): `{"p", "name", "start", "end", "paused", "tw", "pos3d"}`. `end` = now +
  length/pitch (+60 ms), or `FAR_FUTURE_MS` for looping streams. No `finished` signals are used.
- `_acquire()` :596: if the name is at its `VOICE_LIMIT` (:55, default 4), reuse the oldest voice of that name; otherwise a
  free voice; otherwise the oldest voice overall. A player freed by a consumer is recreated.
- Levels: `GAIN_DB` :74 (tree_fall/rock_break -1), `VARY_DB` :75 random ±dB for steps/chop/etc. `_too_soon` :652 merges identical
  requests within 35 ms.
- `play_3d`: `ATTENUATION_INVERSE_DISTANCE`, `max_distance = max(md,1)`, `unit_size = clamp(md/5, 2, 10)`, bus SFX. The caller may
  move the returned player but must not free or reparent it.

## 4. Music/ambience decks, ducking, pause

**`class Deck`** :155-236 (RefCounted). Arrays per player: `players, gains (0..1), targets, speeds, names, trims`, plus `active`.
- `play(name, stream, fade, trim)` :184: **does nothing if `current()==name`**. If a player with the same name and the *same stream
  object* still has gain > 0 (it is fading out), it is revived **from its current position**. Otherwise the quietest player is
  `stop()`ped, given the stream and **started from 0**. All targets are set to 0 except the chosen one, with speed = 1/fade.
- `update(delta)` :221, called every frame from `_process` :847: gain moves linearly and volume = `linear_to_db(sin(g·π/2)) + trim`
  (equal power). A player that is fully silent is stopped, and its `stream = null` and name are cleared.
- `current()` returns "" while a track is fading out. It returns the **requested** name, not the resolved one.
- `play_music(name)` :796: `""` means stop. **A missing track stops the current music** (`_music.stop(fade)`), and so does a missing ambience.
- `play_ambience` stores `_amb_mode[layer] = Game.mode` so that `_back_to_title()` :901 fades out only gameplay beds (over 1.5 s).
- Game code only uses ambience layer 0. **Layer 1 is free** (only the tests use it).

**Ducking:** `_ducks` entries are `{bus, db, t0, attack, hold, release}`. `_update_ducks` :398 has an idle early-out
(no allocation) and re-applies the volumes only when something changed. `AUTO_DUCK` :79 fires on play:
stinger_major (Music -6, Amb -6, 4 s), stinger_soft (Amb -3, 3 s), weaver/shade_shriek (Music -3, 1.5 s), ward_restore
(Music -9, Amb -6, 7.5 s), death (Music -8, 3 s), ui_befriend (Music -4, 1.6 s). The director's "silence" event
(`src/horror/event_runner.gd:311`) calls `duck_ambience(-18, 12)`.

**Pause:** `_process` polls `get_tree().paused`. It does not listen to `Events.paused_changed`. On pause, busy SFX/3D voices get
`stream_paused` (re-asserted every frame by `_hold_paused` :911, because a 3D player registers only on the next physics tick).
On resume, their `end` times shift by the time spent paused. Ambience dips `PAUSE_AMBIENCE_DUCK_DB` = -5 dB at 12 dB/s.
**Music is not paused or ducked by menus.** `area_exiting` → drop held voices + `stop_world_sounds(0.3)`.
Game mode changing to "title" → `_back_to_title()` (music is left for the title's crossfade).

## 5. How music is selected today (no director; each owner calls Audio directly)

| Situation | Call site | Effect |
|---|---|---|
| Title screen shown | `src/ui/title_screen.gd:52` | `play_music("music_title", 3.0)`. The title has no ambience. |
| Continue/New Game fade | `title_screen.gd:336` (`_fade_to_black`) | `stop_music(t)` (0.9 s continue, 1.1 s new game) |
| Continue load failed | `title_screen.gd:288` | `play_music("music_title", 1.5)` |
| Surface arrival | `src/world/surface/surface_world.gd:197-207` `on_player_spawned` | ambience `amb_forest_day/night` (4 s) + `_start_music()` → `music_haven` (day) / `music_night`, 4 s |
| Surface day↔night flip | `surface_world.gd:212-231` `_update_audio(dt)` (ticked every 0.25 s from `_process` :177) | ambience crossfade 4 s. If music is on, crossfade to the other track **starting at 0** (the "keep the phase" comment means the play/rest timer) |
| Surface play/rest cycle | same, `MUSIC_PLAY_SECONDS = 175.0`, `MUSIC_REST_SECONDS = 70.0` (:31-32) | After 175 s, `stop_music(8.0)`, but only if the current track is haven or night. If another track is playing, the cycle leaves it alone and stays "on". After a 70 s rest, it restarts. The fade-out is not phrase-aligned: 175 s ≈ 2.0 passes of haven but 2.19 of night. |
| Night definition | `src/world/surface/sky.gd:185` `is_night = sun_e < 0.2` | with smoothstep keys (:12-23) this is about 20:00 → 05:16 |
| Surface audio frozen | `_update_audio` returns if `restoring` or `Game.mode == "cutscene"`. The area `_process` is pausable, so the timers stop while paused. | |
| Enter the Below | `src/world/below/below_world.gd:688-695` | `stop_music(2.0)`. Ambience per zone. **The Below has no music except the boss fight.** Horror is carried by ambience plus stinger one-shots (`event_runner.gd:777` `_stinger` → `play_sfx` on SFX). |
| Below zone change | `below_world.gd:253` `_on_zone_entered` (Events.zone_entered, Game polls every 0.4 s at `game.gd:58-64`) | `AMBIENCE = {mine: amb_mine, ruins: amb_ruins, silk: amb_silk, boss: amb_boss}` (:48), 3 s. No change during a fight. "boss" becomes "silk" once `weaver_defeated`. Nursery: `below_moments.gd:358` `stop_ambience(2.5)` until `leave_nursery` → `resume_ambience`. |
| Boss fight start | `below_world.gd:540-558` `on_room_changed`: room "arena"/"lift_recess" while the boss is alive | `play_music("music_boss", 1.5)` + `amb_boss` 2 s + `director.suppress(9999)`. `weaver_boss.gd:368` `start_fight` calls `play_music("music_boss", 2.0)` again, which is a no-op. |
| Boss fight end | leaving the arena (not to "arena_way") `below_world.gd:561` stop 3 s. Defeat: `weaver_boss.gd:662` stop 4 s and `below_world.gd:583` stop 5 s (the last call sets the speed) + `amb_silk` 4 s. Death: `below_world.gd:596` stop 1.5 s, `weaver_boss.gd:684` stop 3 s. | |
| Ending | `Game.complete_chapter()` (`game.gd:523`) → `surface_world.play_restoration()` :388 `play_music("music_ending", 1.5)` → `ui_root.show_ending()` → `ending_screen.gd:100` plays `music_ending` again (no restart, which is relied on) → `ui_root.gd:389-390` `play_music("music_haven", 3.0)` if on the surface. **Quirk:** this is haven even at night, until the cycle's next stop and restart. |
| Quit to title | `game.gd:159` | Music keeps playing until the title crossfades to music_title (3 s). |

Other behaviour:
- Opening a menu: no music change (only the -5 dB ambience dip and `ui_open`).
- Crossing a surface zone: no music change.
- Respawning in the same area: no change (the death sound ducks Music by -8 dB).
- Surface→Below→Surface: the surface track starts again from 0. It is revived only if it is still fading out.
- Area loads never stop the music (`area_exiting` only stops positional sounds).

**Ambience outside the decks:**
- `src/world/surface/water.gd:483-537`: `amb_stream` on its own looping `AudioStreamPlayer3D` (bus Ambience, -4 dB,
  unit 5, max 32 m). It moves to the nearest stream point every 0.25 s.
- `src/world/surface/audio_util.gd:16` `make_loop(name, bus := "Ambience", volume_db := -6.0, max_distance := 18.0)`
  duplicates the stream and forces the loop. It is used for `ward_hum` (`ward_stone.gd:170`, SFX, -14 dB, 12 m).
- These are area children, so they pause with the tree.

**Captions:** `Events.caption(text)` → `src/ui/hud/captions.gd`. Shown only if Settings `captions` (default true).
3 lines max, `LIFE` 3.8 s + 0.5 s fade, identical text refreshes its timer. 22 emit sites, style `"[lowercase bracketed]"`.
Music is never captioned.

## 6. Assets (measured from the WAV headers)

All files are 44.1 kHz 16-bit PCM WAV. Loops are stereo with a `smpl` loop chunk and one extra wrap frame. Imports: `edit/loop_mode=2`
(Forward, which overrides the smpl chunk), `loop_begin=0`, `loop_end=-1`, `compress/mode=2` (QOA) for loops and one-shots over 2.5 s.
QOA imports come to about 35.6 KB/s stereo (2.14 MB/min) and are **fully resident** (AudioStreamWAV, no streaming).

| Track | Key/meter | BPM × bars | Length | WAV | QOA .sample | RMS/peak dBFS |
|---|---|---|---|---|---|---|
| music_title | F, 3/4 | 76 × 32 (A A' B A'') | 75.789 s | 13.37 MB | 2.70 MB | -20.0 / -5.0 |
| music_haven | G, 4/4, swing .08 | 88 × 32 | 87.273 s | 15.40 MB | 3.11 MB | -20.0 / -5.9 |
| music_night | D, 4/4 | 60 × 20 (8+8+4) | 80.000 s | 14.11 MB | 2.85 MB | -20.0 / -3.2 |
| music_boss | Dm, 4/4 | 120 × 30 (2+8+8+8+4) | 60.000 s | 10.58 MB | 2.14 MB | -20.0 / -6.2 |
| music_ending | G, 3/4 | 80 × 40 (4+32+4) | 90.000 s | 15.88 MB | 3.21 MB | -19.5 / -4.3 |

Ambience lengths: forest_day 72 s (-27 RMS), forest_night 70 s (-28), stream 48 s (-27), mine 60 s (-26), ruins 60 s (-26), silk 60 s (-28.5), boss 45 s (-28).
Totals: 154 WAVs (262 files in sfx/ including .import, 22 in ui/), `game/assets/audio` 153 MB, `game/.godot/imported` 38 MB (gitignored,
so a fresh checkout needs `--import`). The export excludes only `tests/*`; the source WAVs are not shipped.

## 7. Python toolchain (`tools/audio/`, run with `.tools/pyenv/Scripts/python.exe`: Py 3.12.10, numpy 2.5.3, scipy 1.18.1; soundfile 0.14.0 with OGG support is installed but unused; ffmpeg 8.1.1 is on PATH but not in the project toolchain)

- `catalog.py`: `REQUIRED` (by category, the ARCHITECTURE names) and `REGISTRY: dict[str, Spec]`.
  `Spec(name, fn, cat, variants=1, peak=-5.0, rms=-24.0, loop=False, seconds=0.0, fin=.002, fout=.03, trim=True, extra={})`.
  - `@sound(name, cat="sfx", variants=1, peak=-5.0, ...)` registers `fn(rng, variant) -> mono`.
  - `@loop(name, cat, seconds, rms=-24.0)` registers `fn(rng, seconds) -> (n,2)` with **exactly `ns(seconds)` frames** (asserted).
  - `extra` exists but `loop()` cannot set it.
- `generate_all.py`:
  - `MODULES` (:31) is the list of imported generator modules. **A new module must be added here.**
  - `render_job` :47: `rng = rng_for("name:v")` (crc32).
  - Loop pipeline: mean removal → `normalize_rms(spec.rms)` → circular look-ahead limiter (ceiling -1.5 dB music, -3.0 ambience) →
    `write_wav(loop=True)`.
  - `write_import` :87 creates or patches `<file>.wav.import` (uid and dest kept).
  - CLI: `--only a,b`, `--cat music`, `--jobs N` (default cpu-2, max 16), `--keep-stale`, `--out DIR`
    (with a folder outside the project, no .import files are written).
  - **A full run (no --only/--cat) deletes every WAV in `game/assets/audio/*` that is not registered.**
  - Builds are bit-reproducible. Verified: re-rendering music_haven and music_boss into the scratchpad was byte-identical,
    taking 7.1 s and 10.1 s single-threaded.
- `hhsynth/wavio.py`: `write_wav(path, x, loop=False)` writes 16-bit with TPDF dither (seeded by filename). For loops it
  appends a copy of frame 0 and writes `smpl` (0, n). `read_wav(path) -> (x, sr, loop)`.
- `hhsynth/music.py` `Song(bpm, beats_per_bar, bars, rng, tail=8.0, swing=0.0)`:
  - `.note(bus, inst, note, bar, beat, beats, vel=.8, pan=0, human=.006, gain=1, **inst_kw)`: `note` is a name ("F#5"), a midi int,
    or a float taken as Hz (percussion). Notes before 0 wrap to the end.
  - `.mix(levels={bus: (gain_db, reverb_send)}, ir, rms_db=-20, ceiling_db=-1.5, hp=35, master_lp=14000)`: every bus plus the
    convolution reverb is folded into an exactly periodic loop (`core.fold_loop`), then HP/LP/normalise/limit circularly.
  - Notes may ring at most `tail` seconds past the end. `Song.last_report` holds the per-bus RMS.
- Instruments (`hhsynth/music.py`, signature `(f, dur, vel, rng, **kw)`):
  - Tuned: `music_box`, `celesta`, `harp(ring=1.6)`, `pad(attack=.9, release=1.4, cutoff=1300, detune=7)` (stereo),
    `strings` (stereo), `flute`, `clarinet`, `ocarina` (all `fm.woodwind`), `soft_bass`, `pluck_bass`, `ostinato_pluck`.
  - Percussion and effects: `tom`, `heartbeat`, `shaker`, `woodblock`, `swell`, plus `horn` in `music_tracks.py:369`.
  - Building blocks: `fm.bell/glass/fm`, `physical.ks_pluck/modal`, `space.hall(rng, t60, brightness)/room/cave/reverb` (oaconvolve).
  - `CHORD_SHAPES`: "", m, 7, maj7, m7, sus2, sus4, add9, madd9, 6, m6, dim, maj9, m9, 7sus4, 5, m(b6).
- `music_tracks.py` helpers:
  - `chord_info("C/E")`, `play_line(song, bus, inst, bars, start_bar, vel, pan, transpose, legato)`
    where bars = `[[("C5",1),("r",1)],...]`.
  - `pad_line` (voice-led), `bass_notes(pattern=[(beat, beats, "b"|"5"|"8")])`, `harp_arp(pattern=[(beat, degree, velmul)])`, `_strum`.
  - Patterns `WALTZ_EIGHTHS`, `WALTZ_QUARTERS`, `STRUM_4`, `OSTINATO`.
  - The "For Krystal" motif is scale degrees 5-1-7-6-5 (`THEME_*`).
- QA: `analyze.py [--spectrograms all|loops|none] [--sheets]` writes `qa/tmp/audio/report.txt` and exits 1 on failure. Rules:
  - music peak <= -1.0 and RMS -23..-17.5; ambience peak <= -3 and RMS -29..-21.5
  - loop points (0, len-1), wrap frame == frame 0, seam jump/level checks
  
  `mix_report.py [names]` prints the per-bus balance (it imports `music_tracks` only).

## 8. Tests (`tools/test.sh audio` runs all three; the filter is a filename substring)

- `test_audio_assets.gd`:
  - Required names exist and load; minimum `VARIANTS`; `sound_names().size() >= 103`.
  - The 5 MUSIC and 7 AMBIENCE (hard-coded consts :23-24) are AudioStreamWAV, Forward, begin 0, stereo, 44.1 kHz, and QOA.
  - Length ranges (:99): title 68-92, haven 80-95, night 50-100, boss 55-65, ending 74-101, ambience 44-91 s.
  - One-shots are mono, non-looping, under 12 s.
  - **:137 scans every `"music_*"`/`"amb_*"` string literal in `src/` and `data/`** (except `*_volume`) and asserts each one resolves.
- `test_audio_manager.gd` (21 tests): buses and limiter, volumes, ducks, arachno, aliases, voice limits, pooling, crossfade
  semantics (:220), stop fade (:252), independent layers (:264), pause, area exit, back-to-title (:358).
  It **reads internals**: `Audio._music.gains/.active/.players/.names`, `Audio._amb[0]`.
- `test_audio_mix.gd`: an `AudioEffectCapture` on each bus.
  - Music RMS must be in (-34, -14) with peak < -1; ambience RMS in (-36, -20) with peak < -3.
  - At the default sliders the beds must sit at least 3 dB under their music: haven over forest_day/night/stream, night over
    forest_night, boss over amb_boss.
- `test_world_surface.gd:334` `test_music_rests_between_plays`: uses `SurfaceWorld.MUSIC_DAY/MUSIC_NIGHT/MUSIC_PLAY_SECONDS/MUSIC_REST_SECONDS`,
  `w.on_player_spawned(null)`, `w._update_audio(dt)`, `w._audio_started`.

## 9. Performance notes and pitfalls

- Main-thread cost: every first play `load()`s synchronously. A 180 s QOA track is about 6.4 MB, which can hitch.
  Nothing calls `preload_sounds`, and `_cache` never evicts.
- A 4th music change within one fade time hard-stops the quietest deck (MUSIC_DECKS = 3).
- **Do not name tracks `music_ch2_1`** (a `_<digits>` stem becomes a variant). `finished` never fires for looping WAV imports,
  so playlists cannot advance on it.

## 10. Extension recipes

### (a) Data-driven MusicDirector

1. **Data** `game/data/music.gd` (new, module-owned):
   - `TRACKS = {"music_x": {"bpm": 96.0, "bpb": 4, "bars": 64, "phrase_bars": 8, "tags": ["surface","day"], "energy": 1, "min_play": 30.0}}`
   - `CONTEXTS = [{"id": "boss", "priority": 90, "playlist": [...], "mode": "loop"|"shuffle"|"sequence", "rest": [min, max], "enter_s": 0.0, "exit_s": 4.0, "fade": 2.0, "cut": "now"|"bar"|"phrase"}, ...]`
   - Existing metadata: title 76/3/32/8, haven 88/4/32/8, night 60/4/20/(8), boss 120/4/30/(8), ending 80/3/40/(4).
   - Every literal `"music_*"` here is checked by `test_every_name_the_game_uses_resolves`, so **generate the WAVs first**.
2. **Pure core** `game/src/audio/music_selector.gd` (RefCounted, no scene access, like the horror director core):
   - `setup(data: Dictionary, seed: int)`
   - `update(ctx: Dictionary, dt: float) -> Dictionary` returning `{"action": "play"|"stop"|"none", "track", "fade", "wait_s"}`
   - `ctx` keys: `mode, area, zone, night, paused, threat (bool), boss (bool), horror_state, cutscene, ending, pos_s, track_len_s`.
   - Hysteresis:
     - combat is entered after threat >= 1.0 s continuous and left after 6-8 s with no threat
     - a zone must hold for 3 s before the base playlist changes
     - honour `min_play` unless the new context has a higher priority
     - the rest window comes from its own RNG.
   - Priorities: ending/cutscene 100 > boss 90 > combat 70 > horror-encounter 60 (prefer silence/duck over music) > area/zone base 10.
   - Shuffle bag: its own `RandomNumberGenerator` (seeded; never the global `randi`). Refill when empty, and never repeat the last
     track across a refill.
3. **Node** `game/src/audio/music_director.gd` (Node, `PROCESS_MODE_ALWAYS`, ticks every 0.2 s):
   - It must outlive scene changes, so the integrator creates it under `Game` (next to the UI root) or adds an autoload (project.godot is read-only for modules).
   - Inputs:
     - `Game.mode/area_id/zone_id`
     - `Game.area.sky.is_night` (surface)
     - `Events.boss_health_changed` (hp < 0 = bar hidden = fight over), `boss_defeated`
     - `horror_state_changed`, `cutscene_changed`, `chapter_completed`
     - `player_died/player_respawned`, `area_exiting/area_loaded`, `paused_changed`
     - threat: a cached, throttled (0.5 s) scan of group "enemy" `is_threatening()` within about 20 m of `Game.player`.
       Never call `get_nodes_in_group` every frame.
4. **Phrase-boundary crossfade:**
   - `pos = player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()`.
   - `phrase = 60/bpm * bpb * phrase_bars`, `wait = fposmod(-pos, phrase)`. Fire `Audio.play_music(next, fade)` when `wait < tick`.
   - Use "bar" for combat entry and "now" for boss/ending.
   - Needs an integrator addition to audio.gd, e.g. `func music_position() -> float` (active deck `get_playback_position()`, -1 if
     none), instead of reaching into `Audio._music`.
5. **Migrate the owners**, or the old call sites will fight the director:
   - Gate the music half of `surface_world._update_audio` and `_start_music` (keep the constants for the test).
   - Route `below_world.gd:554/563/583/596/692`, `weaver_boss.gd:368/662/684`, `title_screen.gd:52/288/336`,
     `ending_screen.gd:100` and `ui_root.gd:390` through `director.request(context_id)` / `release(context_id)`.
   - Interim option: the director treats a track it did not start (`Audio.current_music()` not in its plan) as an external override
     and backs off, as the surface cycle already does.

### (b) Adding ~22 compositions (90-180 s)

1. New module `tools/audio/music_ch2.py`: `from catalog import loop`, `from hhsynth import music as M, space as S`,
   `from hhsynth.music import Song`, `from music_tracks import play_line, pad_line, bass_notes, harp_arp, chord_info, arp_tones, split_bar, horn`.
   Re-importing `music_tracks` only re-registers the same specs. Split into several modules if needed.
2. Per track:
   ```python
   @loop("music_glade_a", "music", 64 * 4 * 60.0 / 96.0, rms=-20.0)   # 160 s; seconds MUST equal bars*bpb*60/bpm
   def music_glade_a(rng, seconds):
       s = Song(96, 4, 64, rng)
       ...
       return s.mix({...}, S.hall(rng, 2.4), rms_db=-20.0)
   ```
   Build in 8-bar phrases (the director's `phrase_bars`). Keep `rms` in the decorator equal to `rms_db`. Use a reverb t60 < `tail` (8 s).
   Names are lowercase `music_<id>` with **no trailing `_<int>`**.
3. Add the module to `MODULES` in `generate_all.py:31`. Otherwise a later full run deletes the WAVs as stale. Also add it to the
   imports in `mix_report.py:16`. Optionally add the names to `catalog.REQUIRED["music"]`.
4. Run:
   ```
   .tools/pyenv/Scripts/python.exe tools/audio/generate_all.py --only music_glade_a,... --jobs 3
   ```
   **Memory:** a 180 s Song holds `(n + 8 s)×2` float64 per bus, about 133 MB per bus. With about 8 buses plus the dry, send, wet and full
   buffers that is about 1.5 GB per worker, so keep `--jobs` low. Expect about 10-25 s of render per track per worker. Then:
   ```
   .tools/pyenv/Scripts/python.exe tools/audio/analyze.py --spectrograms loops
   .tools/pyenv/Scripts/python.exe tools/audio/mix_report.py music_glade_a
   timeout 600 tools/godot.sh --headless --path game --import
   tools/test.sh audio
   ```
5. Source size: 22 × about 135 s ≈ 520 MB of WAV (the audio folder is 153 MB today) and about 106 MB imported QOA.

### (c) Streaming and compression for long tracks

- Today: the WAV is imported as QOA and fully resident (about 2.1 MB/min), is cheap to decode, and has a sample-exact Forward loop.
  Fine for 5 tracks. For 22 long ones the issues are:
  - add music eviction to `_cache` (integrator: drop cache entries for music names not on any deck)
  - preload the next track with `ResourceLoader.load_threaded_request` during area fades or ahead of phrase switches.
- Ogg Vorbis is about 1 MB/min and is also memory-resident compressed data. It needs an encoder:
  - `soundfile` (installed, format "OGG", subtype "VORBIS") or ffmpeg (not in the project toolchain; log in INSTALL_LOG).
  - Import params (importer "oggvorbisstr"): `loop=true`, `loop_offset=0.0`, `bpm`, `beat_count`, `bar_beats`.
  - `generate_all.write_import` is WAV-only and needs an ogg branch.
  - Keep WAV masters **outside `game/`**, because a `.wav` and an `.ogg` with the same stem become two variants of one name.
  - `analyze.py` reads only WAV.
  - Check the Vorbis loop seam by ear or with analysis.
- Do not convert the existing 5 tracks: `test_audio_assets` requires `AudioStreamWAV`, QOA and Forward for them.
  `Audio._is_looping` already handles the Ogg `loop` property.

### (d) Tests for the selector

New `game/tests/unit/test_audio_music_director.gd` (picked up by `tools/test.sh audio`), extending `res://tests/test_case.gd`:

1. Pure selector, fed fake ctx dicts plus `update(ctx, dt)`:
   - the base track per area/zone/night
   - combat is not entered for a 0.5 s threat blip and is entered after 1 s; it lingers for exit_s
   - boss outranks combat, ending outranks all
   - zone flapping within 3 s does not switch
   - `min_play` is respected
   - rest windows
   - the shuffle bag has no duplicates within a bag, no repeat across a refill, and is deterministic per seed
   - the RNG is separate: `seed(1); var a = randi()` then re-seed, run the selector, `randi()` is unchanged
2. Phrase math: given bpm/bpb/phrase_bars/pos, the expected `wait_s`, including 3/4 tracks.
3. Data integrity:
   - every `TRACKS` key has `Audio.has_sound(k, true)`
   - `abs(stream.get_length() - bars*bpb*60/bpm) < 2/44100` (the wrap frame adds 1)
   - loops are Forward
4. Integration: drive the node with a short tick and fades of 0.01 s, then assert `Audio.current_music()`.
   `after_each`: `Audio.stop_all(); await wait_seconds(0.05)`.
5. Keep, or deliberately update, `test_world_surface.gd:334` when the surface cycle moves.

## 11. Risks

- **Saves:** audio state is not saved, and GameState/SaveSystem hold no audio fields.
  - If the director persists anything (bag state, last track), make it additive with defaults for old saves.
  - New volume keys need `Settings.DEFAULTS/RANGES` (autoload, integrator) plus `settings_schema.gd`. Old settings files fall back to defaults.
- **New bus:** extend `BUSES`, `VOLUME_KEYS`, `_duck_db` and `_duck_want` together. `duck()` silently ignores unknown buses, and
  `test_audio_manager`/`test_audio_mix` enumerate the buses.
- **Deck semantics are depended on:**
  - The no-op for the same name is relied on by the ending double call, the boss double call and the surface re-entry.
  - Reviving a fading track and "missing track = stop" are also existing behaviour.
  - Renaming `_music`, `_amb`, `gains`, `active`, `players` or `names` breaks the tests.
- **Surface constants and methods** used by `test_world_surface` must stay (or the test must be updated).
- **Toolchain:**
  - Editing shared `hhsynth` instruments or `music_tracks` helpers changes the existing tracks, ambience and SFX on the next render.
    That can shift the levels checked by `test_audio_mix`/`analyze.py` and needs a re-import.
  - A full `generate_all` run deletes the WAVs of unregistered modules.
  - Data referencing ungenerated tracks fails the literal scan test.
  - The `.godot/imported` cache is gitignored, so every checkout must run `--import` (about +100 MB for 22 tracks).
- **AUTO_DUCK** on the Music bus also hits new combat music (death -8 dB, stingers -6 dB).
- **Arachnophobia:** new spider-themed stingers need entries in `ARACHNO_ALT`.
