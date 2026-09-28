# Hollowhaven performance profile (MP 20.5)

Run 2026-09-28T11:37:40 -> 2026-09-28T11:43:08. Mode: **packaged build, second monitor, virtual input**.

## Setup

* Build: `C:\Users\Ali\Desktop\Hollowhaven\builds\Hollowhaven\Hollowhaven.exe` (mtime 2026-09-28T10:20:07, 184.7 MB); engine -, debug build: -; renderer - / - (API -).
* Hardware: AMD Ryzen 9 9950X 16-Core Processor (32 threads), 125.6 GB RAM, NVIDIA GeForce RTX 4090 (driver 595.71, 24564 MiB); Windows-10-10.0.26200-SP0.
* Display: game window borderless on DISPLAY2 (x=1920), monitor refresh - Hz; vsync OFF and max_fps 0 (uncapped, so the numbers show headroom; the shipped default is vsync on = capped at the refresh rate); audio muted (--qa-mute); window never focused.
* Focus: the OS foreground window (GetForegroundWindow, every 0.5 s) belonged to the game in 0 of 635 checks. A fresh helper process holds LockSetForegroundWindow for the life of each game process (ForegroundLock): without it the packaged build's first window became the OS foreground window ~0.6 s after launch despite override.cfg no_focus. Lock taken in 1 of 1 game sessions. (The telemetry's window_focused is Godot's own flag and stayed true even while the game was not in front.)
* Shader caches in %APPDATA%\Hollowhaven before the run: {'files': 150, 'mb': 7.0, 'newest': '2026-09-28T08:44:16'} / vulkan {'files': 1, 'mb': 24.3, 'newest': '2026-09-28T09:50:58'}.
* Sample per state: settle 2.5 s after the load, 360-degree pan 20.0 s, walk W/A/S/D 12.0 s, idle 4.0 s. Frame time = interval between consecutive frames (telemetry node _process, Time.get_ticks_usec). 1% low = 1000 / mean of the slowest 1% frame times.
* Presets: `high1080` = High @1920x1080 (quality 2, render scale 1.0)

## Area x preset

| Area | Preset | Avg FPS | 1% low | 0.1% low | p99 ms | Worst ms | >16.7 ms | >33 ms | >50 ms | GPU ms avg | Load ms (in-game) | Click->play s | Post-load worst ms | Private MB | Video MB | Draw calls | Tele % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

## Loading

In-game load ms = first frame seen in Game.mode 'loading' -> 'playing' (a Lantern Road trip includes its 0.45 s fade-out; from the title there is no fade and the frame that parses the save and swaps the scene is counted as the 'worst frame during load'). Click->play s is the bot's wall clock (+ up to one 0.2 s telemetry line). The 0.6 s fade-in after 'playing' is inside the 'first 3 s after' window.

| Area | Preset | In-game load ms (mode loading->playing, incl. 0.45 s fade-out) | Worst frame during load ms | Frames >50 ms in load | Worst frame first 3 s after ms | >50 ms after |
|---|---|---|---|---|---|---|

## Lantern Road round trips (leak check)

### High @1920x1080 - 10 cycles - OK

| Checkpoint | Load ms | Post-load worst ms | Nodes | Objects | Resources | Orphans | Static MB | Video MB | Private MB | Audio players (playing) | Enemies (active far) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| reach_0 | 2895 | 33.7 | 6647 | 14163 | 279 | 0 | 0.0 | 475.1 | 1623.6 | 68 (4) | 0 (0) |
| haven_1 | 1340 | 18.4 | 5101 | 12887 | 303 | 0 | 0.0 | 479.1 | 1705.4 | 69 (4) | 0 (0) |
| reach_1 | 832 | 15.1 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1711.2 | 68 (3) | 0 (0) |
| haven_2 | 768 | 12.5 | 5101 | 12892 | 308 | 0 | 0.0 | 479.1 | 1712.2 | 69 (4) | 0 (0) |
| reach_2 | 856 | 13.2 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1726.5 | 68 (3) | 0 (0) |
| haven_3 | 808 | 14.7 | 5101 | 12893 | 308 | 0 | 0.0 | 479.1 | 1732.2 | 69 (4) | 0 (0) |
| reach_3 | 870 | 13.5 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1739.2 | 68 (3) | 0 (0) |
| haven_4 | 767 | 13.9 | 5101 | 12892 | 308 | 0 | 0.0 | 479.1 | 1741.0 | 69 (4) | 0 (0) |
| reach_4 | 814 | 14.2 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1743.3 | 68 (3) | 0 (0) |
| haven_5 | 766 | 12.9 | 5101 | 12891 | 308 | 0 | 0.0 | 479.1 | 1752.0 | 69 (4) | 0 (0) |
| reach_5 | 866 | 15.5 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1755.0 | 68 (3) | 0 (0) |
| haven_6 | 795 | 14.2 | 5101 | 12889 | 307 | 0 | 0.0 | 479.1 | 1758.4 | 69 (4) | 0 (0) |
| reach_6 | 817 | 14.9 | 6649 | 15070 | 308 | 0 | 0.0 | 483.2 | 1759.5 | 68 (4) | 0 (0) |
| haven_7 | 768 | 12.7 | 5101 | 12891 | 308 | 0 | 0.0 | 479.1 | 1767.9 | 69 (4) | 0 (0) |
| reach_7 | 870 | 14.1 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1770.5 | 68 (3) | 0 (0) |
| haven_8 | 760 | 14.7 | 5101 | 12889 | 307 | 0 | 0.0 | 479.1 | 1775.4 | 69 (4) | 0 (0) |
| reach_8 | 813 | 12.7 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1775.0 | 68 (3) | 0 (0) |
| haven_9 | 771 | 12.2 | 5101 | 12891 | 308 | 0 | 0.0 | 479.1 | 1774.7 | 69 (4) | 0 (0) |
| reach_9 | 809 | 14.9 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1784.1 | 68 (3) | 0 (0) |
| haven_10 | 773 | 12.4 | 5101 | 12892 | 308 | 0 | 0.0 | 479.1 | 1784.0 | 69 (4) | 0 (0) |
| reach_10 | 815 | 12.8 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1787.5 | 68 (3) | 0 (0) |

Verdict: **slow growth (see per-metric)**. reach: nodes +0.0/cycle (stable), objects +0.0/cycle (stable), resources +0.0/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +8.5/cycle (slow growth), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable); haven: nodes +0.0/cycle (stable), objects +0.6/cycle (stable), resources +0.6/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +8.7/cycle (slow growth), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable)

Whole round-trip run: 116099 frames, worst 777.5 ms, >50 ms: 21, >100 ms: 20 (loads included).

## Stalls / outliers (sample frames > 50 ms, worst 3 per run)

* none in the samples (see the Loading table for load-time and first-seconds hitches)

## Enemy AI / audio during the samples

| Area | Preset | Enemies (max) | Alive | Processing | Processing > 60 m | Processing off-screen | Farthest processing m | Audio players | Playing |
|---|---|---|---|---|---|---|---|---|---|

## Files

results.json (everything), summary.csv, roundtrip.csv, frames/<preset>__<state>.csv (per frame), <preset>/<state>/ (telemetry jsonl, perf_log.jsonl, bot log, saves, settings).
