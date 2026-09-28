# Hollowhaven performance profile (MP 20.5)

Run 2026-09-28T11:09:12 -> 2026-09-28T11:37:39. Mode: **packaged build, second monitor, virtual input**.

## Setup

* Build: `C:\Users\Ali\Desktop\Hollowhaven\builds\Hollowhaven\Hollowhaven.exe` (mtime 2026-09-28T10:20:07, 184.7 MB); engine 4.7.2-stable (official), debug build: False; renderer forward_plus / vulkan (API 1.4.329).
* Hardware: AMD Ryzen 9 9950X 16-Core Processor (32 threads), 125.6 GB RAM, NVIDIA GeForce RTX 4090 (driver 595.71, 24564 MiB); Windows-10-10.0.26200-SP0.
* Display: game window borderless on DISPLAY2 (x=1920), monitor refresh 60.0 Hz; vsync OFF and max_fps 0 (uncapped, so the numbers show headroom; the shipped default is vsync on = capped at the refresh rate); audio muted (--qa-mute); window never focused.
* Focus: the OS foreground window (GetForegroundWindow, every 0.5 s) belonged to the game in 0 of 3152 checks. A fresh helper process holds LockSetForegroundWindow for the life of each game process (ForegroundLock): without it the packaged build's first window became the OS foreground window ~0.6 s after launch despite override.cfg no_focus. Lock taken in 30 of 30 game sessions. (The telemetry's window_focused is Godot's own flag and stayed true even while the game was not in front.)
* Shader caches in %APPDATA%\Hollowhaven before the run: {'files': 150, 'mb': 7.0, 'newest': '2026-09-28T08:44:16'} / vulkan {'files': 1, 'mb': 24.3, 'newest': '2026-09-28T09:50:58'}.
* Sample per state: settle 2.5 s after the load, 360-degree pan 20.0 s, walk W/A/S/D 12.0 s, idle 4.0 s. Frame time = interval between consecutive frames (telemetry node _process, Time.get_ticks_usec). 1% low = 1000 / mean of the slowest 1% frame times.
* Presets: `high1080` = High @1920x1080 (quality 2, render scale 1.0); `low1080` = Low @1920x1080 (quality 0, render scale 1.0); `high720` = High @1280x720 (quality 2, render scale 1.0)

## Area x preset

| Area | Preset | Avg FPS | 1% low | 0.1% low | p99 ms | Worst ms | >16.7 ms | >33 ms | >50 ms | GPU ms avg | Load ms (in-game) | Click->play s | Post-load worst ms | Private MB | Video MB | Draw calls | Tele % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| haven | high1080 | 393.7 | 206.7 | 150.3 | 4.18 | 12.1 | 0 | 0 | 0 | 1.77 | 2120 | 3.09 | 30.9 | 1623 | 467 | 2465 | 1.09 |
| reach_arrival | high1080 | 415.5 | 227.8 | 187.3 | 3.98 | 7.7 | 0 | 0 | 0 | 1.85 | 2992 | 4.31 | 34.7 | 1658 | 475 | 2243 | 1.04 |
| commons_dusk | high1080 | 390.6 | 209.3 | 159.6 | 4.21 | 8.1 | 0 | 0 | 0 | 1.93 | 2702 | 4.00 | 31.4 | 1658 | 475 | 2529 | 1.07 |
| orchard | high1080 | 414.3 | 226.8 | 165.6 | 3.86 | 11.8 | 0 | 0 | 0 | 1.78 | 2857 | 4.21 | 31.7 | 1659 | 475 | 2086 | 1.08 |
| quarry | high1080 | 416.1 | 210.7 | 143.0 | 3.92 | 12.3 | 0 | 0 | 0 | 1.81 | 3374 | 4.77 | 35.5 | 1644 | 475 | 1980 | 1.17 |
| ballroom | high1080 | 661.2 | 305.6 | 150.9 | 2.68 | 19.8 | 2 | 0 | 0 | 0.62 | 978 | 2.23 | 34.5 | 1432 | 452 | 792 | 0.90 |
| works_hub | high1080 | 555.7 | 269.1 | 222.8 | 3.28 | 5.8 | 0 | 0 | 0 | 0.90 | 1502 | 2.94 | 49.1 | 1859 | 506 | 524 | 0.91 |
| choir_approach | high1080 | 479.6 | 265.3 | 223.6 | 3.45 | 4.8 | 0 | 0 | 0 | 1.07 | 1542 | 3.05 | 49.7 | 1857 | 507 | 792 | 0.86 |
| annex | high1080 | 555.2 | 275.6 | 158.6 | 3.07 | 15.8 | 0 | 0 | 0 | 0.92 | 1015 | 2.08 | 36.0 | 1539 | 465 | 976 | 0.84 |
| haven | low1080 | 412.8 | 206.9 | 143.4 | 4.11 | 11.3 | 0 | 0 | 0 | 1.23 | 2044 | 2.99 | 32.9 | 1611 | 466 | 1685 | 1.18 |
| reach_arrival | low1080 | 449.2 | 228.9 | 181.3 | 3.86 | 6.3 | 0 | 0 | 0 | 1.16 | 2893 | 4.31 | 32.1 | 1657 | 474 | 1556 | 1.15 |
| commons_dusk | low1080 | 402.2 | 202.9 | 154.0 | 4.28 | 7.1 | 0 | 0 | 0 | 1.26 | 3112 | 4.46 | 35.7 | 1644 | 474 | 1710 | 1.23 |
| orchard | low1080 | 440.6 | 216.3 | 148.5 | 3.88 | 14.0 | 0 | 0 | 0 | 1.10 | 3074 | 4.41 | 34.9 | 1666 | 476 | 1433 | 1.21 |
| quarry | low1080 | 439.8 | 214.4 | 139.9 | 3.87 | 13.9 | 0 | 0 | 0 | 1.14 | 3234 | 4.71 | 34.9 | 1660 | 474 | 1397 | 1.30 |
| ballroom | low1080 | 624.4 | 284.4 | 141.1 | 2.87 | 18.1 | 2 | 0 | 0 | 0.62 | 1067 | 2.18 | 33.4 | 1433 | 452 | 793 | 0.92 |
| works_hub | low1080 | 578.3 | 284.7 | 228.9 | 3.12 | 5.4 | 0 | 0 | 0 | 0.70 | 1580 | 2.99 | 47.0 | 1626 | 461 | 525 | 0.95 |
| choir_approach | low1080 | 511.0 | 280.9 | 229.2 | 3.25 | 5.3 | 0 | 0 | 0 | 0.86 | 1628 | 3.09 | 51.9 | 1617 | 461 | 791 | 0.87 |
| annex | low1080 | 577.9 | 278.1 | 155.4 | 3.03 | 17.7 | 1 | 0 | 0 | 0.77 | 922 | 2.03 | 35.9 | 1559 | 454 | 986 | 0.85 |
| haven | high720 | 363.3 | 185.9 | 129.6 | 4.68 | 11.8 | 0 | 0 | 0 | 1.46 | 2244 | 3.20 | 34.2 | 1628 | 318 | 2487 | 1.14 |
| reach_arrival | high720 | 409.7 | 205.4 | 162.1 | 4.36 | 7.1 | 0 | 0 | 0 | 1.53 | 3047 | 4.41 | 35.5 | 1649 | 326 | 2227 | 1.09 |
| commons_dusk | high720 | 387.8 | 216.1 | 175.0 | 4.16 | 6.3 | 0 | 0 | 0 | 1.63 | 2716 | 4.01 | 31.4 | 1652 | 326 | 2534 | 1.11 |
| orchard | high720 | 413.5 | 214.8 | 151.7 | 3.95 | 14.0 | 0 | 0 | 0 | 1.47 | 2659 | 3.95 | 30.6 | 1645 | 327 | 2075 | 1.11 |
| quarry | high720 | 430.8 | 218.6 | 145.3 | 3.81 | 13.5 | 0 | 0 | 0 | 1.49 | 2639 | 3.95 | 29.9 | 1650 | 327 | 1967 | 1.20 |
| ballroom | high720 | 680.1 | 325.1 | 169.9 | 2.55 | 17.0 | 1 | 0 | 0 | 0.39 | 942 | 2.08 | 34.0 | 1446 | 304 | 790 | 0.91 |
| works_hub | high720 | 570.7 | 308.4 | 250.2 | 2.93 | 4.9 | 0 | 0 | 0 | 0.62 | 1372 | 2.79 | 41.5 | 1614 | 338 | 535 | 0.90 |
| choir_approach | high720 | 524.6 | 295.8 | 239.6 | 3.05 | 5.3 | 0 | 0 | 0 | 0.72 | 1314 | 2.64 | 41.9 | 1607 | 338 | 785 | 0.83 |
| annex | high720 | 638.1 | 333.2 | 256.1 | 2.69 | 11.6 | 0 | 0 | 0 | 0.62 | 851 | 1.98 | 33.0 | 1519 | 314 | 903 | 0.82 |

## Loading

In-game load ms = first frame seen in Game.mode 'loading' -> 'playing' (a Lantern Road trip includes its 0.45 s fade-out; from the title there is no fade and the frame that parses the save and swaps the scene is counted as the 'worst frame during load'). Click->play s is the bot's wall clock (+ up to one 0.2 s telemetry line). The 0.6 s fade-in after 'playing' is inside the 'first 3 s after' window.

| Area | Preset | In-game load ms (mode loading->playing, incl. 0.45 s fade-out) | Worst frame during load ms | Frames >50 ms in load | Worst frame first 3 s after ms | >50 ms after |
|---|---|---|---|---|---|---|
| haven | high1080 | 2120 | 1728.3 | 2 | 30.9 | 0 |
| reach_arrival | high1080 | 2992 | 2536.6 | 3 | 34.7 | 0 |
| commons_dusk | high1080 | 2702 | 2296.5 | 3 | 31.4 | 0 |
| orchard | high1080 | 2857 | 2400.4 | 3 | 31.7 | 0 |
| quarry | high1080 | 3374 | 2835.2 | 3 | 35.5 | 0 |
| ballroom | high1080 | 978 | 977.9 | 2 | 34.5 | 0 |
| works_hub | high1080 | 1502 | 1502.3 | 2 | 49.1 | 0 |
| choir_approach | high1080 | 1542 | 1542.3 | 2 | 49.7 | 0 |
| annex | high1080 | 1015 | 1015.3 | 2 | 36.0 | 0 |
| haven | low1080 | 2044 | 1645.0 | 2 | 32.9 | 0 |
| reach_arrival | low1080 | 2893 | 2457.9 | 3 | 32.1 | 0 |
| commons_dusk | low1080 | 3112 | 2624.8 | 3 | 35.7 | 0 |
| orchard | low1080 | 3074 | 2579.3 | 3 | 34.9 | 0 |
| quarry | low1080 | 3234 | 2717.5 | 3 | 34.9 | 0 |
| ballroom | low1080 | 1067 | 1067.0 | 2 | 33.4 | 0 |
| works_hub | low1080 | 1580 | 1580.0 | 2 | 47.0 | 0 |
| choir_approach | low1080 | 1628 | 1628.5 | 2 | 51.9 | 1 |
| annex | low1080 | 922 | 921.7 | 2 | 35.9 | 0 |
| haven | high720 | 2244 | 1805.3 | 2 | 34.2 | 0 |
| reach_arrival | high720 | 3047 | 2587.2 | 3 | 35.5 | 0 |
| commons_dusk | high720 | 2716 | 2325.1 | 3 | 31.4 | 0 |
| orchard | high720 | 2659 | 2234.7 | 3 | 30.6 | 0 |
| quarry | high720 | 2639 | 2197.1 | 3 | 29.9 | 0 |
| ballroom | high720 | 942 | 942.5 | 2 | 34.0 | 0 |
| works_hub | high720 | 1372 | 1371.5 | 2 | 41.5 | 0 |
| choir_approach | high720 | 1314 | 1313.8 | 2 | 41.9 | 0 |
| annex | high720 | 851 | 850.9 | 2 | 33.0 | 0 |

## Lantern Road round trips (leak check)

### High @1920x1080 - 3 cycles - OK

| Checkpoint | Load ms | Post-load worst ms | Nodes | Objects | Resources | Orphans | Static MB | Video MB | Private MB | Audio players (playing) | Enemies (active far) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| reach_0 | 3070 | 36.1 | 6647 | 14163 | 279 | 0 | 0.0 | 475.1 | 1630.4 | 68 (4) | 0 (0) |
| haven_1 | 1384 | 17.2 | 5101 | 12885 | 303 | 0 | 0.0 | 479.1 | 1715.8 | 69 (4) | 0 (0) |
| reach_1 | 841 | 12.4 | 6649 | 15066 | 304 | 0 | 0.0 | 483.2 | 1727.0 | 68 (4) | 0 (0) |
| haven_2 | 775 | 13.1 | 5101 | 12888 | 304 | 0 | 0.0 | 479.1 | 1739.8 | 69 (4) | 0 (0) |
| reach_2 | 879 | 15.3 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1747.4 | 68 (3) | 0 (0) |
| haven_3 | 808 | 12.8 | 5101 | 12890 | 308 | 0 | 0.0 | 479.1 | 1747.5 | 69 (4) | 0 (0) |
| reach_3 | 849 | 12.6 | 6649 | 15069 | 308 | 0 | 0.0 | 483.2 | 1753.8 | 68 (3) | 0 (0) |

Verdict: **stable**. reach: nodes +0.0/cycle (stable), objects +1.5/cycle (stable), resources +2.0/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +13.4/cycle (stable), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable); haven: nodes +0.0/cycle (stable), objects +2.5/cycle (stable), resources +2.5/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +15.9/cycle (stable), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable)

Whole round-trip run: 32766 frames, worst 809.2 ms, >50 ms: 7, >100 ms: 6 (loads included).

### Low @1920x1080 - 3 cycles - OK

| Checkpoint | Load ms | Post-load worst ms | Nodes | Objects | Resources | Orphans | Static MB | Video MB | Private MB | Audio players (playing) | Enemies (active far) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| reach_0 | 2795 | 31.5 | 6647 | 14163 | 279 | 0 | 0.0 | 474.0 | 1644.8 | 68 (4) | 0 (0) |
| haven_1 | 1333 | 13.7 | 5101 | 12887 | 304 | 0 | 0.0 | 477.9 | 1710.7 | 69 (4) | 0 (0) |
| reach_1 | 825 | 11.4 | 6649 | 15069 | 308 | 0 | 0.0 | 482.1 | 1721.6 | 68 (3) | 0 (0) |
| haven_2 | 780 | 12.7 | 5101 | 12894 | 308 | 0 | 0.0 | 477.9 | 1736.8 | 69 (4) | 0 (0) |
| reach_2 | 831 | 13.0 | 6649 | 15069 | 308 | 0 | 0.0 | 482.1 | 1744.0 | 68 (3) | 0 (0) |
| haven_3 | 773 | 12.3 | 5101 | 12888 | 307 | 0 | 0.0 | 477.9 | 1751.5 | 69 (4) | 0 (0) |
| reach_3 | 884 | 13.4 | 6649 | 15069 | 308 | 0 | 0.0 | 482.1 | 1753.0 | 68 (3) | 0 (0) |

Verdict: **stable**. reach: nodes +0.0/cycle (stable), objects +0.0/cycle (stable), resources +0.0/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +15.7/cycle (stable), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable); haven: nodes +0.0/cycle (stable), objects +0.5/cycle (stable), resources +1.5/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +20.4/cycle (stable), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable)

Whole round-trip run: 38885 frames, worst 769.0 ms, >50 ms: 7, >100 ms: 6 (loads included).

### High @1280x720 - 3 cycles - OK

| Checkpoint | Load ms | Post-load worst ms | Nodes | Objects | Resources | Orphans | Static MB | Video MB | Private MB | Audio players (playing) | Enemies (active far) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| reach_0 | 2584 | 36.2 | 6647 | 14164 | 279 | 0 | 0.0 | 326.4 | 1636.0 | 68 (4) | 0 (0) |
| haven_1 | 1232 | 13.5 | 5101 | 12886 | 304 | 0 | 0.0 | 329.9 | 1717.7 | 69 (4) | 0 (0) |
| reach_1 | 868 | 13.2 | 6649 | 15070 | 308 | 0 | 0.0 | 334.1 | 1727.2 | 68 (4) | 0 (0) |
| haven_2 | 808 | 12.8 | 5101 | 12891 | 308 | 0 | 0.0 | 329.9 | 1740.0 | 69 (4) | 0 (0) |
| reach_2 | 810 | 11.1 | 6649 | 15069 | 308 | 0 | 0.0 | 334.1 | 1742.8 | 68 (3) | 0 (0) |
| haven_3 | 762 | 12.1 | 5101 | 12890 | 307 | 0 | 0.0 | 329.9 | 1745.8 | 69 (4) | 0 (0) |
| reach_3 | 824 | 11.7 | 6649 | 15069 | 308 | 0 | 0.0 | 334.1 | 1746.9 | 68 (3) | 0 (0) |

Verdict: **stable**. reach: nodes +0.0/cycle (stable), objects -0.5/cycle (stable), resources +0.0/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +9.9/cycle (stable), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable); haven: nodes +0.0/cycle (stable), objects +2.0/cycle (stable), resources +1.5/cycle (stable), orphans +0.0/cycle (stable), static_mb +0.0/cycle (stable), video_mb +0.0/cycle (stable), private_mb +14.0/cycle (stable), audio_players +0.0/cycle (stable), enemies +0.0/cycle (stable)

Whole round-trip run: 35773 frames, worst 667.1 ms, >50 ms: 7, >100 ms: 6 (loads included).

## Stalls / outliers (sample frames > 50 ms, worst 3 per run)

* none in the samples (see the Loading table for load-time and first-seconds hitches)

## Enemy AI / audio during the samples

| Area | Preset | Enemies (max) | Alive | Processing | Processing > 60 m | Processing off-screen | Farthest processing m | Audio players | Playing |
|---|---|---|---|---|---|---|---|---|---|
| haven | high1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 69 | 6 |
| reach_arrival | high1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 68 | 6 |
| commons_dusk | high1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 68 | 6 |
| orchard | high1080 | 2 | 2 | 2 | 0 | 2 | 36.9 | 68 | 5 |
| quarry | high1080 | 2 | 2 | 2 | 0 | 2 | 38.3 | 68 | 5 |
| ballroom | high1080 | 1 | 1 | 1 | 0 | 1 | 18.5 | 67 | 8 |
| works_hub | high1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 67 | 4 |
| choir_approach | high1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 67 | 4 |
| annex | high1080 | 1 | 1 | 1 | 0 | 1 | 15.2 | 67 | 9 |
| haven | low1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 69 | 6 |
| reach_arrival | low1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 68 | 6 |
| commons_dusk | low1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 68 | 6 |
| orchard | low1080 | 2 | 2 | 2 | 0 | 2 | 36.8 | 68 | 6 |
| quarry | low1080 | 2 | 2 | 2 | 0 | 2 | 38.4 | 68 | 6 |
| ballroom | low1080 | 1 | 1 | 1 | 0 | 1 | 18.3 | 67 | 8 |
| works_hub | low1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 67 | 4 |
| choir_approach | low1080 | 0 | 0 | 0 | 0 | 0 | 0.0 | 67 | 4 |
| annex | low1080 | 1 | 1 | 1 | 0 | 1 | 13.9 | 67 | 9 |
| haven | high720 | 0 | 0 | 0 | 0 | 0 | 0.0 | 69 | 6 |
| reach_arrival | high720 | 0 | 0 | 0 | 0 | 0 | 0.0 | 68 | 6 |
| commons_dusk | high720 | 0 | 0 | 0 | 0 | 0 | 0.0 | 68 | 6 |
| orchard | high720 | 2 | 2 | 2 | 0 | 2 | 36.4 | 68 | 5 |
| quarry | high720 | 2 | 2 | 2 | 0 | 2 | 37.6 | 68 | 6 |
| ballroom | high720 | 1 | 1 | 1 | 0 | 1 | 19.3 | 67 | 8 |
| works_hub | high720 | 0 | 0 | 0 | 0 | 0 | 0.0 | 67 | 4 |
| choir_approach | high720 | 0 | 0 | 0 | 0 | 0 | 0.0 | 67 | 4 |
| annex | high720 | 1 | 1 | 1 | 0 | 1 | 17.9 | 67 | 6 |

## Files

results.json (everything), summary.csv, roundtrip.csv, frames/<preset>__<state>.csv (per frame), <preset>/<state>/ (telemetry jsonl, perf_log.jsonl, bot log, saves, settings).
