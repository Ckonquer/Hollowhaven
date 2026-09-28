# Hollowhaven on Krystal's PC: readiness report (for the 2.0.3 gift build)

Written 2026-09-28. Krystal has never played Hollowhaven. She will install it on her own Windows PC (specs unknown),
start with **New Game**, and play without anyone next to her. This report answers four questions: will the game
start on a PC we have never seen, will it run well enough, does it look right, and what can she do if something
goes wrong.

**What was tested:** the packaged **2.0.2** build (`builds/Hollowhaven/Hollowhaven.exe`, Godot 4.7.2, the same engine
and project settings as 2.0.3). The 2.0.3 changes in the working tree at the time of writing (texts, docs, some UI and
data scripts) do not touch renderer settings or shaders. Still, re-run the short checks in "How to reproduce" on the
final 2.0.3 exe before you give it to her.

**The test PC** is the only one available: Ryzen 9 9950X, 128 GB RAM, RTX 4090, Windows 11, two 1080p monitors.
Its CPU also has a very weak **built-in Radeon graphics chip (2 compute units)**. That chip stood in for a weak
laptop GPU (`--gpu-index 1`), so the low-end numbers below are real measurements, not guesses. Nothing was run on a
second physical PC.

Every visible run except the two Below runs (g1/g2, which continue a prepared save) started from an empty save
folder, and every run except those two and the forced-preset runs (e2-e7) had no settings file, like a brand-new PC.
All were muted, launched onto the second monitor
(`--position 1920,0` / `--qa-window=1920,0,...`; the window's real position was not logged, see §7) and never
focused: the focus watchdog saw the game take focus **0 times** in every run.

---

## 1. Short version (for Ali)

* **It will start on almost any Windows 10/11 PC with working graphics drivers.** The game uses Vulkan first. If
  Vulkan is missing it switches to Direct3D 12 by itself, and if that is missing too it switches to OpenGL (the
  "Compatibility" renderer). I checked both switches on the packaged exe by making the drivers unavailable. No
  error box appeared and the game played.
* **The main risk is speed on a weak laptop, not crashes.** On the weakest graphics chip I could test (a basic
  built-in chip), the settings the game picks by itself give about **15 FPS**. Setting Graphics quality to **Low**
  gives about **22-25 FPS**. Laptops with **Intel Iris Xe** or **AMD Ryzen 5000-or-newer** graphics (common from
  about 2021) should be clearly faster (my estimate, not measured). Budget laptops with basic "Intel UHD Graphics"
  are about as slow as the chip I measured. A gaming PC or laptop with a real graphics card will be smooth.
* **If her PC falls back to OpenGL** (only very old or badly-driven PCs), the game still works, but it looks worse:
  streams and ponds turn white, meadow flowers turn black, and the greens are harsher. Screenshots are in §3.2.
* **Small screens are fine.** Every menu fits and is readable at 1280x720 and 1366x768. It also works on 16:10,
  3:2 and ultrawide screens. One cosmetic flaw on every shape except 16:9: the title logo peeks out behind the
  "Meet Krystal" panel (§3.5).
* **Before you give it to her:** look up her graphics chip (see §2), make sure the graphics driver is up to date, and
  give her a **mouse**. The camera is turned with the mouse, which is hard on a touchpad. If it is a laptop, keep
  the charger plugged in.

## 2. Minimum and recommended PC (check this against her PC)

How to look it up on her PC: **Start → type `dxdiag` → Enter**. The *System* tab shows Windows, 64-bit, Processor
and Memory.
The *Display* tab shows the graphics chip ("Name"). If there are two Display tabs, the laptop has two graphics chips.
Alternatively use Task Manager → Performance → GPU.

| | Minimum (plays at Low / Medium, roughly 30 FPS or more; estimate) | Recommended (smooth, about 60 FPS at High 1080p; estimate) |
|---|---|---|
| Windows | Windows 10 or 11, **64-bit** (the installer refuses anything older) | same |
| Memory | 8 GB (the game uses 1.4-2.4 GB) | 8 GB or more |
| Graphics | Built-in graphics at least as strong as **Intel Iris Xe** (Intel 11th-gen laptops, 2020+) or **AMD Radeon Vega 7/8** (Ryzen 4000/5000 laptops), or any gaming card from about 2016+ (GTX 1050 / RX 560) | A gaming card such as **GTX 1650 / RTX 2050 / RX 6500 or newer**, or recent built-in graphics (**Radeon 680M/780M**, **Intel Arc**) |
| Processor | not measured on a slow CPU (see below); any 4-core 64-bit processor from about 2017 on is expected to be enough | same |
| Driver | an up-to-date graphics driver (Windows Update → Advanced options → Optional updates, or the Intel / AMD / NVIDIA app) | same |
| Disk | about 1 GB free (the installed game is 185 MiB, the installer file 106 MB; shader caches and logs in `%APPDATA%\Hollowhaven` reached about 100 MB on the test PC after many runs on two GPUs and four graphics drivers, less is expected on hers) | same |
| Other | a **mouse**; speakers or headphones are optional (it runs silently without them) | a mouse; laptop on its charger |
| Not supported | 32-bit Windows, Windows 7/8, Mac. Windows on ARM (Snapdragon laptops) is untested (the installer allows it; the game would run under x64 emulation) | |

Both graphics rows are **estimates**, scaled from what I measured on the weak built-in Radeon chip (§3.4) by roughly
how much faster each chip is. **Below the minimum:** basic built-in graphics such as the "Intel UHD Graphics" of
budget laptops, Intel HD / UHD 620-class chips (laptops from about 2016-2020), AMD Radeon Vega 3, or the small
"AMD Radeon Graphics" (2 compute units) of Ryzen 7000/9000 desktop processors are about as fast as, or slower than, the chip I
measured. The game starts and plays there, but only at Low and at about 20-25 FPS at best (measured: 22-25 FPS on
the 2-CU chip), which feels sluggish in fights. Graphics from before about 2015 (Intel HD 4000/4400/5500, Radeon HD
series) may only start through the OpenGL fallback (§3.1, §3.2) and should be treated as not playable.

**Processor:** every run used a Ryzen 9 9950X, so the processor line is an estimate. On that CPU the rendering work
took about 1.2-1.8 ms per frame on Vulkan / Direct3D 12 (telemetry `cpu_render_avg_ms`), which leaves a lot of room
for a laptop CPU that is 2-4 times slower. The OpenGL fallback is heavier (3.8 ms), and ANGLE much heavier
(16.6 ms, already the limit on this CPU).

Nothing extra needs installing. The exe only uses DLLs that ship with Windows (import table checked: no Visual C++
runtime, no .NET, no DirectX redistributable). ANGLE is built into the exe, and Direct3D 12 works without the
Agility SDK (verified).

## 3. Findings

### 3.1 Renderer, driver and the automatic fallback chain

The engine's own settings, printed by a headless script (`qa/tmp/pcready/print_render_settings.gd` →
`qa/tmp/pcready/render_settings.txt`). project.godot sets none of these except `rendering_method` (to its default
value), so every value is Godot 4.7.2's default:

| Setting | Value | Meaning |
|---|---|---|
| `rendering/renderer/rendering_method` | `forward_plus` | the normal renderer |
| `rendering/rendering_device/driver.windows` | `vulkan` | Windows starts on Vulkan |
| `rendering/rendering_device/fallback_to_d3d12` | `true` | no Vulkan → Direct3D 12 |
| `rendering/rendering_device/fallback_to_vulkan` | `true` | no Direct3D 12 → Vulkan |
| `rendering/rendering_device/fallback_to_opengl3` | `true` | neither → OpenGL 3.3 (Compatibility renderer) |
| `rendering/gl_compatibility/driver.windows` | `opengl3` | native OpenGL first |
| `rendering/gl_compatibility/fallback_to_angle` / `fallback_to_native` | `true` / `true` | no usable OpenGL → ANGLE (OpenGL ES on Direct3D 11) and back |
| `rendering/gl_compatibility/force_angle_on_devices` | engine list (old Radeon HD / R-series, old Intel HD / Iris) | GPUs with known-bad OpenGL drivers go straight to ANGLE |
| `debug/file_logging/enable_file_logging.pc` | `true` | release builds write `%APPDATA%\Hollowhaven\logs\godot.log` (5 kept) |

What the packaged exe actually did (all on the RTX 4090):

* **Vulkan made unavailable.** For the game process only, `VK_DRIVER_FILES` / `VK_ICD_FILENAMES` pointed at a
  driver list that does not exist. The log says `Your video card drivers seem not to support Vulkan, switching to
  Direct3D 12.`, followed by `D3D12 12_0 - Forward+`. New Game, Meet Krystal and the Haven sample then ran
  normally at 243 FPS (`qa/tmp/pcready/runs/f1_no_vulkan/godot.log`).
* **Vulkan and Direct3D 12 made unavailable.** Same as above, plus a `d3d12.dll` without `D3D12CreateDevice` (a
  renamed copy of `System32\version.dll`) placed next to the exe copy. The log says `switching to OpenGL 3.`,
  followed by `OpenGL API 3.3.0 ... Compatibility`. New Game, Meet Krystal and the Haven sample ran normally
  (`runs/f2_no_vulkan_no_d3d12/godot.log`). In this run the Direct3D 12 library loaded, but the device could not be
  created: the log shows `Failed to initialize driver for device` (rendering_device.cpp) just before the switch. So
  the fallback also covers a driver that is present but cannot create a device, not only a missing driver. For
  Vulkan only the "no Vulkan driver at all" case was exercised.
  No error box appeared and the game did not crash in either case. The probe also suppresses Windows' own
  crash / bad-DLL boxes, as a precaution (Godot's own message boxes are not affected by that).
* **Direct3D 12 on purpose** (`--rendering-driver d3d12`): same picture and same FPS as Vulkan (233 vs 233). The
  first start took 5.2 s instead of 2.7 s because its shader cache was still empty (`runs/b_d3d12`).
* **ANGLE on purpose** (`--rendering-driver opengl3_angle`): ANGLE is built into the exe and works (`ANGLE (NVIDIA
  ... Direct3D11)`). It is slow, though: 49 FPS on the RTX 4090, bound by the CPU side of rendering (16.6 ms), and
  the very first load took 23 s, including one frame of 19 s while shaders compiled (`runs/c2_angle`). Only very old
  GPUs from the force-ANGLE list, or PCs whose native OpenGL also fails, end up here.
* **When everything fails**, Godot shows a message box titled "Unable to initialize video driver": "Your video card
  drivers seem not to support the required ... version", with the advice to update the graphics driver or reboot
  (and, in the variant for a Vulkan / Direct3D 12 failure, the `--rendering-driver opengl3` command). Both texts are
  in the exe (string search); which one appears depends on the drivers that were tried. I did not trigger this on
  purpose.
* **Hybrid laptops (two GPUs).** The exe exports `NvOptimusEnablement` and `AmdPowerXpressRequestHighPerformance`
  (PE export table, `qa/tmp/pcready/pe_exports.py`). NVIDIA Optimus and AMD switchable-graphics drivers therefore
  run the game on the dedicated GPU. Godot's own Vulkan device pick also prefers the dedicated GPU. The verbose log
  lists `#0 NVIDIA ... Discrete`, `#1 AMD Radeon(TM) Graphics ... Integrated` and then `Using Device #0`
  (`runs/devices/godot.log`). Windows' per-app setting (Settings → System → Display → Graphics) can still override
  this.

### 3.2 The Compatibility (OpenGL) renderer: works, but looks worse

This only matters if her PC falls back that far (§3.1). The whole first-minutes route works: New Game, comfort
screen, Meet Krystal, Ward Stone, gathering (`runs/c_compat`, both steps ok). On the RTX 4090 it runs at 191-223 FPS
average, with more hitches (1% low 41 vs 89). The first load of the Haven had one 8 s frame while shaders compiled.
On a weak PC that frame will be much longer, and Windows may mark the window "Not responding" for a while.

Visual defects, found by comparing screenshots side by side (`qa/tmp/pcready/runs/haven_fplus_left_vs_compat_right.png`,
`runs/c_compat/zoom_stream.png` vs `runs/a_default/zoom_stream.png`, `runs/c_compat/zoom_distance.png`):

1. **Water is white.** The stream and Mirror Pond are pale white instead of blue. `shaders/surface_water.gdshader`
   rebuilds depth as `vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0)`. That formula is only right for Forward+/Mobile.
   The Compatibility renderer needs `depth_raw * 2.0 - 1.0` for z, so the computed depth comes out wrong and the
   whole surface becomes foam. This cause comes from reading the shader; the fix has not been tried.
2. **Meadow flowers are black.** The flower heads (MultiMesh with `surface_flower.gdshader`: vertex COLOR ×
   INSTANCE_CUSTOM) render as black silhouettes. Root cause not confirmed; the suspect is how the GL renderer
   passes MultiMesh colour / custom data when `use_colors` is off (`src/world/surface/flora.gd`).
3. **The whole image looks different.** Greens are neon-bright and grass tips pale. On the title screen the glow
   around the Ward Stone and campfire is blown out. In the Below (Continue from a real fixture save,
   `runs/below_fplus_vs_compat.png`), the image is darker and harder, with no volumetric fog. Compatibility has no
   volumetric fog, SSAO or SSR, and `below_world.gd` then keeps the thin 0.004 fog because `volumetric_fog_enabled`
   is still true. It stays readable.
4. The log gets one harmless line: `WARNING: Screen-space AA is only available when using the Forward+ or Mobile
   renderer.`

**Auto quality does not help on this path.** By engine source reading (not measured), Godot's GL renderer reports
the adapter type as "other". `Settings.auto_quality()` therefore keeps **High** on exactly the PCs that fell back
because they are old. The probe's fresh settings did show High on OpenGL, but on the RTX 4090 High is the right pick
anyway, so the run cannot tell the two causes apart.

### 3.3 Results of every probe run

All runs used the packaged exe, a fresh save dir and settings file (except the preset / Below runs), muted, on the
second monitor, and were never focused. Evidence for each run is in `qa/tmp/pcready/runs/<run>/`: `result.json`,
`probe_*.png`, `godot.log`, `probe_telemetry.jsonl`, `probe_bot.log`. "Pan+walk" is a 16 s camera turn plus an 8 s
walk in the Haven right after New Game. "First minutes" is reading the Ward Stone plus gathering the first basics
(playthrough.py's own steps; both passed in every full run).

| Run | Renderer / driver | GPU | Quality / render scale | Window | Title s | Confirm→play s | Pan+walk avg FPS | 1% low | p99 ms | GPU ms | First-minutes FPS | Private MB max | Video MB | Log err/warn |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| a_default | forward_plus / vulkan | RTX 4090 | High / 1.0 | 1920x1080 | 2.7 | 4.3 | 233.5 | 88.5 | 6.35 | 3.14 | 248.8 | 2010 | 471 | 0/0 |
| b_d3d12 | forward_plus / d3d12 | RTX 4090 | High / 1.0 | 1920x1080 | 5.2 (cold cache) | 6.3 | 233.0 | 89.9 | 6.06 | 3.35 | 243.0 | 2078 | 797 | 0/0 |
| c_compat | gl_compatibility / opengl3 | RTX 4090 | High / 1.0 | 1920x1080 | 6.0 | 10.8 | 190.9 | 40.8 | 9.05 | 3.86 | 223.0 | 887 | 177 | 0/1 |
| c2_angle | gl_compatibility / opengl3_angle | RTX 4090 via ANGLE | High / 1.0 | 1920x1080 | 2.4 | 23.1 | 49.3 | 9.3 | 34.87 | - | (short run) | 1049 | 163 | 0/1 |
| f1_no_vulkan | forward_plus / d3d12 (automatic) | RTX 4090 | High / 1.0 | 1920x1080 | 2.7 | 5.3 | 243.0 | 90.5 | 6.07 | 3.30 | (short run) | 1751 | 796 | 2/1 (the expected Vulkan failure) |
| f2_no_vulkan_no_d3d12 | gl_compatibility / opengl3 (automatic) | RTX 4090 | High / 1.0 | 1920x1080 | 2.6 | 4.5 | 184.0 | 53.1 | 8.33 | 4.42 | (short run) | 737 | 179 | 5/2 (the expected failures) |
| d1_1366 | forward_plus / vulkan | RTX 4090 | High / 1.0 | 1366x768 | 3.1 | 5.2 | 219.7 | 102.7 | 6.35 | 3.30 | 239.9 | 1679 | 325 | 0/0 |
| d2_1280_noaudio | forward_plus / vulkan, `--audio-driver Dummy` | RTX 4090 | High / 1.0 | 1280x720 | 3.1 | 5.7 | 207.3 | 89.9 | 7.28 | 3.31 | 305.0 | 1693 | 315 | 0/0 |
| d3_1610 | forward_plus / vulkan | RTX 4090 | High / 1.0 | 1728x1080 (16:10) | 2.6 | 4.4 | 433.0 | 153.0 | 3.97 | 1.69 | 414.0 | 1676 | 463 | 0/0 |
| d4_32 | forward_plus / vulkan | RTX 4090 | High / 1.0 | 1620x1080 (3:2) | 2.6 | 4.4 | 395.1 | 143.3 | 4.27 | 1.86 | 440.7 | 1697 | 448 | 0/0 |
| d5_219 | forward_plus / vulkan | RTX 4090 | High / 1.0 | 1920x822 (21:9) | 2.6 | 4.6 | 409.5 | 146.1 | 4.24 | 1.62 | 439.7 | 1670 | 416 | 0/0 |
| e3_igpu_high | forward_plus / vulkan | Radeon 2-CU iGPU | High / 1.0 (forced) | 1920x1080 | 2.6 | 6.9 | **10.8** | 5.3 | 102.7 | 90.5 | 11.7 | 1864 | 452 | 0/0 |
| e1_igpu_auto | forward_plus / vulkan | Radeon 2-CU iGPU | **Medium / 0.85 (auto)** | 1920x1080 | 4.8 | 6.5 | **15.0** | 7.7 | 74.7 | 64.9 | 16.3 | 2353 | 402 | 0/0 |
| e2_igpu_low | forward_plus / vulkan | Radeon 2-CU iGPU | Low / 0.7 (forced) | 1920x1080 | 2.9 | 6.6 | **21.8** | 10.7 | 55.4 | 44.3 | 24.8 | 1978 | 335 | 0/0 |
| e4_igpu_low_lean | + MSAA off, soft shadows low, 2048 shadow atlas (override.cfg) | Radeon 2-CU iGPU | Low / 0.7 | 1920x1080 | 3.3 | 6.2 | 25.8 | 10.2 | 47.2 | 37.2 | (short run) | 1769 | 242 | 0/0 |
| e5_igpu_low_lean_50 | same as e4 | Radeon 2-CU iGPU | Low / 0.5 | 1920x1080 | 3.5 | 6.1 | 30.2 | 11.8 | 42.5 | 31.8 | (short run) | 2265 | 214 | 0/0 |
| e7_igpu_medium | forward_plus / vulkan | Radeon 2-CU iGPU | Medium / 0.85 (forced) | 1920x1080 | 2.8 | 6.8 | 14.9 | 7.6 | 75.8 | 65.5 | (short run) | 2302 | 402 | 0/0 |
| e6_igpu_medium_fsr | + FSR 1.0 upscaling (override.cfg) | Radeon 2-CU iGPU | Medium / 0.85 | 1920x1080 | 2.8 | 7.2 | 14.2 | 5.8 | 78.5 | 68.7 | (short run) | 2317 | 418 | 0/0 |
| g1_below_fplus | forward_plus / vulkan | RTX 4090 | High / 1.0 | 1920x1080 | 2.8 | 2.2 (Continue) | 388.2 | 82.1 | 4.03 | 1.67 | - | 1834 | 498 | 0/0 |
| g2_below_compat | gl_compatibility / opengl3 | RTX 4090 | High / 1.0 | 1920x1080 | 2.7 | 3.9 (Continue) | 262.1 | 42.7 | 6.43 | 1.20 | - | 802 | 149 | 0/1 |

Caveats:

* **RTX 4090 FPS numbers are noisy.** Other agents' visible game sessions shared the GPU during some runs (two
  other `Hollowhaven.exe` processes were running at the start). That is why d3/d5 show about 430 FPS and
  a/d1/d2 about 220 FPS for the same scene. The iGPU runs used a different GPU and are more stable
  (e1 vs e7, same settings: 15.0 vs 14.9).
* **V-Sync stayed on but did not limit FPS here.** Every run reports `vsync_mode 1`, yet FPS ran far above the
  monitor's refresh rate. The cause is not established. It could be a driver-level override on this PC, or the
  borderless QA window. On her PC, V-Sync is expected to cap fullscreen at the monitor's refresh rate.
* **Shader caches were cold only for some runs.** On a brand-new PC the first start compiles shaders. D3D12, ANGLE,
  OpenGL and the iGPU's pipeline cache were cold in their first run. The Vulkan SPIR-V cache on this PC was already
  warm, and I did not clear it because it is shared with other agents' runs.

### 3.4 Weak graphics: auto quality, presets and what helps

* **First-run auto quality works as coded** (`Settings.auto_quality()`, on the first start only, when there is no
  settings file yet): RTX 4090 → High / 100%, integrated Radeon → **Medium / 85%**. The choice is saved when the
  comfort screen closes (`runs/e1_igpu_auto/settings_after_comfort.cfg`: `quality=1`, `render_scale=0.85`) and shown
  on Settings → Video (`runs/e1_igpu_auto/probe_*_ui_settings_video.png`).
* **Medium is too heavy for the weakest built-in chips.** The iGPU gets 15 FPS at Medium, 11 at High and 22-25 at
  Low. The GPU is the limit (97% of the frame time). All three presets still look pretty
  (`runs/igpu_high_medium_low.png`; Low has sparser grass and a slightly softer image).
* **The quality presets leave the biggest fixed costs untouched:** MSAA 2x, the soft-shadow filter at quality 3 and
  the 4096 directional shadow atlas are set in project.godot for everyone. Lowering those three as well (e4 vs e2,
  same preset) gave **+18%** (21.8 → 25.8 FPS, GPU 44 → 37 ms). Dropping the render scale further to 50% gave
  30 FPS.
* **Geometry is heavy even at Low:** about 5.1 M primitives per frame at Low and about 8.4 M at High, mostly grass
  and foliage. That is why the render scale helps less than expected (e4 vs e5: 70% → 50% only gains 5.5 ms).
* **FSR 1.0 upscaling** (`rendering/scaling_3d/mode=1`) gives a visibly sharper image at 85% scale
  (`runs/igpu_medium_bilinear_vs_fsr.png`) and costs about 3 ms (5%) on the weakest chip (e6 vs e7).
* Rough estimate for other chips, scaled by raw GPU throughput from the measured 2-CU chip (not measured):
  Intel Iris Xe / Radeon Vega 7-8 about 3x → 35-50 FPS at auto Medium. Radeon 680M/780M or a GTX 1650 about 6x →
  60 FPS at High 1080p. **4K screens:** the game renders 3D at the screen's full resolution. auto_quality ignores
  resolution, so a 4K laptop with mid-range graphics starts at High/100% and will struggle until the render scale is
  lowered.
* **Is the Haven representative?** The weak chip only ran the Haven. In the separate performance pass on an earlier
  packaged build of the same day (`qa/tmp/perf/packaged_v200_nofocus/summary.md`, RTX 4090, High 1080p) the Haven's
  GPU time was 1.77 ms; the Chapter Two outdoor areas were within about +10% (Reach arrival 1.85, Commons at dusk
  1.93, orchard 1.78, quarry 1.81 ms) and the indoor areas lighter (0.6-1.1 ms). So the weak-chip numbers above
  should roughly hold for the rest of the game, with the busiest outdoor areas about 10% slower (a ratio estimate,
  not measured on the weak chip).

### 3.5 Small windows and other screen shapes

Full UI tour (pause, Settings → Gameplay and Video, backpack, crafting, journal, map, wardrobe) at 1280x720
(`runs/d2_1280_noaudio`), 1366x768 (`runs/d1_1366`), 16:10 (`runs/d3_1610`, `contact_sheet.png`), 3:2
(`runs/d4_32`, `contact_sheet.png`) and 21:9 (`runs/d5_219`, `contact_sheet.png`). The comfort and Meet Krystal
screens were checked at every size.

* **Nothing is cut off or overlapping.** Every panel fits, and the telemetry's "clipped" buttons are only rows of
  scroll lists (the same rows are "clipped" at 1080p). Text stays readable. At 1280x720 the smallest lines (hint
  lines under the backpack, the stats table) are about 12 px high: small but legible on a laptop screen.
* **Cosmetic bug on every screen shape except 16:9 (16:10 and 3:2 are common on laptops):** the title logo and
  menu fade back in *behind* the "Meet Krystal" panel. On 16:10 the tops of the "Hollowhaven" letters peek over
  the panel's top edge (`runs/d3_1610/zoom_meet_topleft.png`). On 3:2 the upper half of the logo shows above the
  panel (`runs/d4_32/probe_003_meet_krystal.png`). On 21:9 the logo and New Game / Settings / Credits / Quit show at
  the left (`runs/d5_219/probe_003_meet_krystal.png`). On 16:9 the panel covers them (`runs/a_default/zoom_meet_topleft.png`).
  Cause, from reading the code: `title_screen.gd` `_close_panel()` calls `p.on_close()`. The comfort screen emits
  `confirmed` from there, which resumes `_on_new_game()` and opens the creation panel (`_fade_menu(false)`).
  `_close_panel()` then continues and calls `_fade_menu(true)` unconditionally. Fix: only fade the menu back in when
  `_panel == null` at that point.

### 3.6 A clean first run on a new PC

Empty save dir, and no settings file except in the forced-preset runs e2-e7:

* **The title shows New Game, Settings, Credits and Quit. There is no Continue** (every run with an empty save dir,
  `result.json` `title_buttons`; the two Below runs, which had a save, show Continue first as expected).
* **New Game → "Before You Begin" (comfort) → "Meet Krystal" → the Haven.** The chosen outfit and hair are applied
  (`appearance` in `runs/a_default/result.json`).
* **Defaults written on the first comfort close:** fullscreen on, V-Sync on, frame-rate limit unlimited, render
  scale 100% and High on a dedicated GPU (85% and Medium on an integrated one), master volume 85%, music 60%,
  ambience 80%, effects 85%, interface 70%, horror Standard, captions on (`runs/a_default/settings_after_comfort.cfg`).
  These are sane.
* **Log:** 0 errors and 0 warnings in every Vulkan / D3D12 / small-window / iGPU run. OpenGL adds the one harmless
  SSAA warning. The only other lines, in `--verbose` only, are Vulkan loader notes about this PC's own OBS and Epic
  overlay layers (`runs/devices/godot.log`).
* **Start time with warm caches:** 2.4-3.6 s to the title, 4.3-7.2 s from Confirm to playing (the slower end is
  the weak chip). With cold caches: D3D12 5.2 s and 6.3 s, the weak chip's first run 4.8 s to the title.
* **Not verified on screen:** the real fullscreen start. QA windows are always borderless-windowed on the second
  monitor, so the default fullscreen mode (`display/window/size/mode=3` + `Settings.apply_video()`) is covered by code
  and earlier QA only.

### 3.7 Other risks

* **No audio device.** `--audio-driver Dummy` is where Godot lands when WASAPI cannot start. With it, the full
  first-minutes route ran with 0 errors (`runs/d2_1280_noaudio`). With no output device at all, WASAPI either falls
  back to that driver or keeps running silently and picks up a device when one is plugged in. That second part is
  from engine knowledge, not tested. The game never opens the microphone (`audio/driver/enable_input=false`) and uses
  no audio-device APIs of its own.
* **High-DPI.** `allow_hidpi=true`, so the game is DPI-aware. Fullscreen uses the native resolution, and the UI
  (1920x1080 base, `canvas_items` + `expand`) scales with the window, so text stays sharp at 125-200% Windows
  scaling. In windowed mode the 1600x900 window is measured in physical pixels, so it looks small on a 4K screen
  (shrunk to 90% of smaller screens). Not tested on a real high-DPI screen.
* **Antivirus / SmartScreen / Smart App Control.** Neither the exe nor the installer is signed
  (`Get-AuthenticodeSignature`: NotSigned). What she will see, and how to hand it over (a USB stick avoids the
  SmartScreen box), is in `docs/INSTALLER.md` → "Windows protected your PC". If Windows 11 **Smart App Control** is
  **On** on her PC, unsigned programs can be blocked with no "Run anyway" button. Only code signing, or her turning
  Smart App Control off, gets past that. Check it (Windows Security → App & browser control → Smart App Control)
  before the day. Not tested: this PC's settings were not changed.
* **Input.** A keyboard and mouse are required: the game has no gamepad bindings, and the camera follows the mouse.
  Keys are bound by physical position, and labels come from `DisplayServer.keyboard_get_keycode_from_physical`, so
  AZERTY and QWERTZ keyboards get WASD in the same place with the right letters shown. That is from reading the
  code, not tested.
* **Memory.** Private bytes peak at 1.7-2.4 GB on Vulkan / D3D12 (the higher numbers are on the iGPU, which uses
  system RAM as video memory) and 0.7-1.0 GB on OpenGL. Godot reports 150-800 MB of video memory at 1080p:
  Vulkan about 470 MB, D3D12 about 800 MB, OpenGL about 180 MB. The performance pass (§3.4) saw 1.4-1.9 GB private
  and 450-510 MB video memory in the Chapter Two areas at High 1080p, so the Haven is typical. An 8 GB PC is fine.
  On 4 GB, Windows plus the game would swap.
* **Overlays.** Third-party Vulkan layers (OBS, Discord, MSI Afterburner / RivaTuner, Epic) hook into every Vulkan
  game. If the game crashes at start on her PC, the D3D12 option in §4 avoids them.

## 4. If the game doesn't start or runs badly (for Krystal / Ali)

1. **A blue "Windows protected your PC" box** → *More info* → *Run anyway* (see `docs/INSTALLER.md`).
2. **A message about video card drivers, or nothing happens / black screen / it closes right away:** update the
   graphics driver (Windows Update → Advanced options → Optional updates → Driver updates, or the Intel Driver &
   Support Assistant, AMD Adrenalin or NVIDIA app), restart the PC, and try again.
3. **Still not starting: use the other graphics path.** Right-click the Hollowhaven desktop shortcut → *Properties*
   (for the Start-menu one: right-click it → *Open file location* first). At the very end of *Target* (after
   `Hollowhaven.exe`, or after its closing quote if there is one), add a space and `--rendering-driver d3d12`, then
   click OK and start it from that shortcut. If that also fails, use `--rendering-driver opengl3` instead. It is
   less pretty (§3.2) but works almost anywhere. Both were verified on the packaged exe (`runs/b_d3d12`,
   `runs/h2_cli_opengl3_only`).
   To make the choice permanent without the shortcut: put a text file named `override.cfg` next to `Hollowhaven.exe`
   (the install folder, `%LOCALAPPDATA%\Programs\Hollowhaven`) containing these two lines:
   ```
   [rendering]
   rendering_device/driver.windows="d3d12"
   ```
   Verified on the packaged exe: the log says `d3d12` (`runs/h1_override_d3d12`). Remove the file to undo it.
4. **It opens on the wrong screen or stays black in fullscreen:** add `--windowed` to the shortcut's Target the same
   way. The game then always starts in a window (`Settings.apply_video()` checks `--windowed`; every QA launch
   passes it). **While `--windowed` is on the shortcut, the Fullscreen switch in Settings → Video does nothing**: it
   can show "On" while the game stays in a window (the probes show exactly this, e.g.
   `runs/d2_1280_noaudio/probe_012_ui_settings_video.png`; code: `want_fs = fullscreen and not cli_windowed`). To
   keep a window without the shortcut change, switch Fullscreen **off** in Settings → Video and remove `--windowed`
   again: the game then leaves fullscreen by itself right after every start. There is no Alt+Enter toggle.
5. **The first start seems frozen for a while:** on a slow PC, or on the OpenGL path, the first start prepares
   shaders for up to a minute (one 19 s frame was measured on ANGLE). Windows may show "Not responding". Wait; later
   starts are quicker.
6. **It runs slowly:** press Esc → Settings → Video → *Graphics quality: Low* and *Render scale: 70%* (50% if still
   slow). *Show FPS counter* on the same page shows the speed. Plug in the laptop charger. On a laptop with two
   graphics chips, open Windows Settings → System → Display → Graphics → Hollowhaven → *High performance* (if it is
   not listed, add it with *Browse*: `%LOCALAPPDATA%\Programs\Hollowhaven\Hollowhaven.exe`). Close other big
   programs.
7. **Send Ali the log:** paste `%APPDATA%\Hollowhaven\logs` into File Explorer's address bar and send `godot.log`
   (the latest run). The four older `godot<date>.log` files are the runs before it. Her saved journey is in
   `%APPDATA%\Hollowhaven\saves`. Never delete that folder.

## 5. Changes made in this pass

* **New test `game/tests/unit/test_pc_readiness_settings.gd`** (plus `.uid`). It pins the effective values the
  probes relied on:
  * Forward+ on a verified Windows driver (Vulkan or D3D12);
  * all three rendering-device fallbacks on;
  * the Compatibility fallbacks (native OpenGL first, ANGLE fallback both ways, the force-ANGLE device list kept);
  * the PC file log in `user://logs` with at least 2 files kept, and user:// = `%APPDATA%\Hollowhaven`;
  * UI stretch `canvas_items` + `expand` on a 1920x1080 base, DPI-aware, resizable window;
  * no microphone, keep-screen-on.

  It reads the effective ProjectSettings, so a project.godot edit or a future engine default that turns one off
  fails the suite. Result: 6/6 PASS.
* **No change to `game/project.godot`.** Every fallback that exists is already on (they are engine defaults), so
  there was nothing clearly safe to enable. The candidates I measured all change the look for every player, which is
  not this pass's call: lower MSAA / soft shadows / shadow atlas (+18% on a weak chip), FSR upscaling (sharper when
  the render scale is below 100%), or Direct3D 12 as the default driver. They are listed as recommendations below.
* **Adversarial review (same day).** Every claim was re-checked against the run files (`result.json`, `godot.log`),
  the settings dump, `settings.gd`, `title_screen.gd`, the shaders, the installer script and a string search of the
  exe. Corrected: §4 step 4 (with `--windowed` on the shortcut the Fullscreen switch does nothing), the minimum-PC
  wording (column header vs. the listed chips, budget and pre-2015 laptops, a processor line), the "everything
  fails" message, the cache size, the start times, and which runs were fresh. Added: the D3D12 device-creation
  fallback evidence, the Chapter Two areas' GPU cost and memory from the performance pass, and the unlogged window
  position (§7). `game/project.godot` is unchanged (confirmed with `git status`). Re-run:
  `tools/test.sh test_pc_readiness_settings` 6/6 PASS, `tools/test.sh parse_all` 1/1 PASS.

## 6. Recommended fixes, in priority order

| # | Priority | What | Where (owner) | Why / evidence |
|---|---|---|---|---|
| 1 | P1, no code | Before the hand-over: look up her GPU (dxdiag), update the graphics driver, check Smart App Control, give her a mouse, hand the installer over on USB | Ali | §2, §3.7 |
| 2 | P1, no code | Re-run the short probes on the **final 2.0.3 exe**: `a_default`, `e1_igpu_auto`, `f2_no_vulkan_no_d3d12` (about 6 min). Before any further visible run, settle where the probe windows land (§7: screen index 1 vs 0), e.g. by logging the window rectangle | lead / QA | this report measured 2.0.2 |
| 3 | P1 | `auto_quality()`: when `RenderingServer.get_current_rendering_method() == "gl_compatibility"` (the fallback path), pick **low** / 70% instead of keeping High | `game/autoload/settings.gd` | §3.2: adapter type is "other" on GL, so the oldest PCs get High |
| 4 | P1 | `auto_quality()`: integrated GPU → **low** with render scale about 0.75-0.8 (instead of medium / 0.85), or a one-time step-down if the first ~20 s of play average under ~25 FPS (with a small note pointing to Settings → Video). The step-down is the better of the two: a blanket Low would also lower strong built-in chips (Radeon 780M, Intel Arc) that manage Medium or High | `game/autoload/settings.gd` (+ a HUD note) | §3.4: auto Medium = 15 FPS on the weakest chip; Low still looks good |
| 5 | P2 | Let the **Low** preset also lower MSAA (2x → off), the soft-shadow filter (3 → 1) and the directional shadow atlas (4096 → 2048) at runtime (`Viewport.msaa_3d`, `RenderingServer.directional_soft_shadow_filter_set_quality`, `RenderingServer.directional_shadow_atlas_set_size`), and thin out the grass more | `settings.gd` / `sky.gd` / `grass.gd` | e4 vs e2: +18%; 5.1 M primitives per frame at Low |
| 6 | P2 | Compatibility renderer: water depth for GL (`#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` → `ndc.z = depth_raw * 2.0 - 1.0`); find why the MultiMesh flowers render black (try `use_colors = true` with white instance colours) | `shaders/surface_water.gdshader`, `shaders/surface_flower.gdshader`, `src/world/surface/flora.gd` | §3.2 screenshots; only matters on the fallback path |
| 7 | P2 | Title: `_close_panel()` must not `_fade_menu(true)` when a new panel was opened from `on_close()` (only when `_panel == null`) | `game/src/ui/title_screen.gd` | §3.5: logo / menu behind Meet Krystal on 16:10, 3:2 and 21:9 |
| 8 | P2 | Installer: optional second Start-menu shortcut "Hollowhaven (safe graphics)" with `--rendering-driver d3d12`, so §4 step 3 needs no editing of shortcut properties | `tools/installer/hollowhaven.iss` | §3.1 / §4 (D3D12 verified identical look and speed) |
| 9 | P3 | First run on a 4K / 1440p+ screen: start with render scale about 0.67-0.75 (take the screen size into account in `auto_quality`) | `settings.gd` | §3.4, §3.7 |
| 10 | P3 | FSR 1.0 upscaling when render scale < 100% (`rendering/scaling_3d/mode=1`, or `Viewport.scaling_3d_mode`) | `project.godot` / `settings.gd` | e6 vs e7: sharper, about 5% cost |
| 11 | P3 | Alt+Enter (or F11) fullscreen toggle | input handling | §4 step 4 |
| 12 | P3 | Copy the curated evidence into git (see below): `qa/tmp` is git-ignored | `qa/evidence/` (lead) | |
| 13 | P3 | Code signing (paid certificate): the only fix for Smart App Control | owner's decision | §3.7, `docs/INSTALLER.md` |

Suggested evidence to keep (copy to `qa/evidence/pcready_2.0.2/`): `qa/tmp/pcready/render_settings.txt`, every
`qa/tmp/pcready/runs/*/result.json`, `runs/f1_no_vulkan/godot.log`, `runs/f2_no_vulkan_no_d3d12/godot.log`,
`runs/c2_angle/godot.log`, `runs/devices/godot.log`, `runs/haven_fplus_left_vs_compat_right.png`,
`runs/below_fplus_vs_compat.png`, `runs/c_compat/zoom_stream.png`, `runs/a_default/zoom_stream.png`,
`runs/c_compat/zoom_distance.png`, `runs/igpu_high_medium_low.png`, `runs/igpu_medium_bilinear_vs_fsr.png`,
`runs/d3_1610/contact_sheet.png`, `runs/d3_1610/zoom_meet_topleft.png`, `runs/d4_32/contact_sheet.png`,
`runs/d5_219/contact_sheet.png`, `runs/d5_219/probe_003_meet_krystal.png`,
`runs/d1_1366/probe_0{02,03,14,15,16,17}_*.png`, and `runs/d2_1280_noaudio/probe_0{09,12,13}_*.png`.

## 7. What was not verified

* No second physical PC, no real laptop, no Intel GPU, no Windows 10 install, no real high-DPI or 4K screen, no slow
  CPU. The graphics tiers and the processor line in §2 are estimates, scaled from one measured weak chip and one
  very fast CPU.
* Where the probe windows really were. Every probe was launched with `--position 1920,0` and
  `--qa-window=1920,0,<w>,<h>` (DISPLAY2), but the window rectangle was never logged. The telemetry's screen index
  (`DisplayServer.window_get_current_screen()`) is **1** for all 1920x1080 probes and **0** for all smaller windows,
  and on this PC Windows enumerates DISPLAY2 before DISPLAY1. So the index alone does not show that every window was
  on DISPLAY2; the cause is not established. Only "never focused" (the watchdog) is measured.
  **Correction (later on 2026-09-28):** the telemetry *did* log the window position (`window_pos`). Every 1920x1080 probe here
  (a_default, b_d3d12, c_compat, c2_angle, e1-e7, f1, f2, g1, g2) sat at [0, 0] - on the owner's **primary** monitor - and every
  smaller window at [1920, 0] as asked. The same happened to the visible native Chapter Two chain run (15:04-15:28, with sound).
  None of them took keyboard focus, which is why the watchdog saw nothing. Why Windows placed them there is not established; the fix (`bb79708`: rect 8 px inside the live
  second monitor, refuse any rect not fully on a non-primary monitor, the watchdog moves / kills a window on the primary monitor):
  `QA_REPORT.md` §13.6; per-run positions: `qa/evidence/ch2_v2.0.3/incident_primary_monitor/window_positions.txt`.
* The real default **fullscreen** first start. QA always runs windowed on the second monitor.
* A PC that **truly** lacks Vulkan / D3D12. Both were simulated per process: the Vulkan loader was pointed at no
  driver, and a stub `d3d12.dll` was used. Real old drivers can also fail differently, for example by crashing
  instead of refusing to start. For that case the only help is §4.
* Where the adapter type comes from on the OpenGL path (§3.2), WASAPI with no output device at all (§3.7), and
  AZERTY labels: all from reading the code or the engine, not run.
* Two bot hiccups, not game bugs: the first `c2_angle` attempt clicked the comfort screen while it was still sliding
  in. It changed the master volume and music sliders in that run's scratch settings and never left the comfort
  screen. The first `d1_1366` attempt's New Game click did not register. Both reruns, with a click only after the
  button's position had been stable for 1.2 s, passed. The cause of the second one was not investigated.
* The rest of the game (Chapter One after the first gathering, Chapter Two areas) was not replayed on the weak chip
  or on OpenGL. Only the Haven, and one Below view on OpenGL, were checked.

## 8. How to reproduce

The probe (`qa/tmp/pcready/probe.py`) imports `tools/qa/session.py`, `playthrough.py` and `perf_profile.py`. It
launches exactly the way `perf_profile.py` does:

* `prepare_qa_exe()` makes a hard-linked exe copy with the no-focus `override.cfg`;
* `Session(..., virtual_input=True, qa_window=<DISPLAY2 rect>, mute=True, exe_copy=False, pre_args=<engine args>)`
  runs Session's own `_start_virtual`: SW_SHOWNOACTIVATE, `fglock.ForegroundLock` + `FocusWatchdog`, `--qa-no-focus`,
  and scratch `--settings-file` / `--save-dir`.

The probe adds engine arguments before `--` (`--log-file`, the renderer / GPU / audio options) and, for the
experiments, extra lines in the copy's `override.cfg`. It also calls `SetErrorMode` so that no Windows error box can
open. It needs the second monitor at x=1920 and takes 1-3 minutes per run.

```
# Git Bash, repo root. One visible run at a time.
R="$(pwd -W)"   # C:/... form for Godot
.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game -s "$R/qa/tmp/pcready/print_render_settings.gd" -- --settings-file="$R/qa/tmp/pcready/hl/settings.cfg" --save-dir="$R/qa/tmp/pcready/hl/saves"
python qa/tmp/pcready/pe_exports.py builds/Hollowhaven/Hollowhaven.exe      # NvOptimusEnablement / AmdPowerXpress...
python qa/tmp/pcready/pe_imports.py builds/Hollowhaven/Hollowhaven.exe      # only Windows system DLLs
python qa/tmp/pcready/probe.py a_default --video-tab 641,143
python qa/tmp/pcready/probe.py e1_igpu_auto --gpu-index 1 --video-tab 641,143   # index from: probe.py devices (--verbose log)
python qa/tmp/pcready/probe.py f2_no_vulkan_no_d3d12
# all variants: devices a_default b_d3d12 c_compat c2_angle d1_1366 d2_1280_noaudio d3_1610 d4_32 d5_219 e1..e7
#               f1_no_vulkan f2_no_vulkan_no_d3d12 g1_below_fplus g2_below_compat h1_override_d3d12 h2_cli_opengl3_only
tools/test.sh test_pc_readiness_settings
```

