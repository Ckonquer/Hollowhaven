# AGENTS.md — development rules for Hollowhaven

Read first: `GAME_SPEC.md` (design) and `docs/ARCHITECTURE.md` (code contracts). Current status:
`PROJECT_STATE.md`. Test evidence: `QA_REPORT.md`.

## Toolchain (project-local, nothing installed system-wide)
* Godot 4.7.2 stable (official build, SHA-512 verified) in `.tools/godot/` (self-contained mode via `_sc_`;
  export templates in `.tools/godot/editor_data/export_templates/4.7.2.stable/`).
  Reinstall: `powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1`.
* Python 3.12 venv with numpy/scipy/pillow in `.tools/pyenv/` (audio generation only).
* Why Godot, not Unity: Unity 6 Personal can only be activated by signing in to Unity Hub
  (docs.unity3d.com/6000.4/Documentation/Manual/ManualActivationGuide.html); that needs the owner's
  account, and the build had to proceed unattended. Godot is MIT-licensed and needs no account.

## Verified commands (run from the repo root in Git Bash)
* Unit tests (headless):            `tools/test.sh` or `tools/test.sh <filter>`
* Parse-check every script:         `tools/test.sh parse_all`
* Re-import assets (after adding audio/fonts): `tools/godot.sh --headless --path game --import`
* Run the game (debug, windowed):   `tools/godot.sh --path game --resolution 1600x900 -- --windowed`
* Jump into an area (debug only):   `... -- --area=surface --spawn=haven_start`
* Area screenshots (debug only):    `... -- --area=surface --cams="x,y,z,yaw,pitch;..." --shot-dir=<abs dir>`
* Preview one visual script:        `... -- --preview=res://src/companions/mochi.gd --shot-dir=<abs dir>`
* Release build + zip:              `powershell -ExecutionPolicy Bypass -File tools/build_release.ps1`
* Chapter Two visual-QA commands (debug builds only; `...` = `tools/godot.sh --path game --resolution 1600x900`; always
  bound them with `--quit-at` / `--max-seconds` or `timeout`; look at the PNGs afterwards). Suggested by the Wave B-D
  modules and the integration passes, not yet run on screen (the pending checks are listed in `KNOWN_ISSUES.md`). Any run
  that can save (a checkpoint, an area change, an Echo Trial round trip, "Set out" on an expedition) must also pass
  `--save-dir=<abs scratch dir>` so the real saves in `%APPDATA%\Hollowhaven\saves` are never touched:
  * Avatar looks (preview stage, non-driven avatar): `... -- --windowed --preview=res://src/player/krystal_avatar.gd
    --avatar-outfit=<outfit id> [--avatar-hair=<id> --avatar-hair-color=<id> --avatar-skin=<id> --avatar-eyes=<id>
    --avatar-hat=<id> --avatar-armor=<armor set id>] --preview-anim=walk --shot-dir=<abs dir>` (ids: `data/appearance.gd`,
    armor sets: `data/equipment.gd`; other `--preview-anim` names: idle, run, jump, roll, wave, cheer, sleep, wand ...).
  * "Meet Krystal" creation screen: `... -- --windowed --title-show=creation --shots=<abs dir> --shot-times=3 --quit-at=6`
    (other `--title-show=` values: comfort, settings, credits, continue, newgame, confirm).
  * Wardrobe panel: `... -- --windowed --area=surface --ui-open=wardrobe --shots=<abs dir> --shot-times=4 --quit-at=6`.
  * One-time wardrobe notice: `... -- --windowed --area=surface --ui-show=wardrobe_notice --shots=<abs dir> --shot-times=4 --quit-at=6`
    (debug boots switch the automatic notice off, `ui_root.NOTICE_OFF_ARGS`; `--ui-show` shows it on demand; the QA bot passes
    `-- --no-wardrobe-notice` when continuing a v1 save). Chapter Two ending screen: `--ui-show=ending2`.
  * Journal / map: `... -- --windowed --area=hallowmere_reach --ui-open=map` or `--ui-open=journal --ui-args={"tab":"mastery"}`
    (tabs: story, optional, friends, lore, mastery).
  * Hushed Works deep rooms: `... -- --windowed --area=hushed_works --spawn=crossing_gate
    --flags=ch2_line_water,ch2_line_bell,ch2_line_light --give=lantern` (other spawns: `bell_throat`, `vault_exit`, see spec §1).
  * Expedition panel (Wave D2; the routes open after the Choir and their district's restored flag, else they show locked with the
    reason): `... -- --windowed --area=surface --flags=ch2_choir_defeated,ch2_orchard_restored,ch2_quarry_restored,ch2_manor_restored
    --ui-open=expedition --ui-args={"template":"orchard_patrol"} --shots=<abs dir> --shot-times=4 --quit-at=6` (template ids:
    `orchard_patrol`, `quarry_circuit`, `manor_afterglow`, `data/expeditions.gd`). The ribbon lantern, the end cache, the Reach map
    pins (`--ui-open=map`) and the tracker card need a started run: press "Set out" in that panel (with `--save-dir`), then boot
    the saved run with `--load-save --save-dir=<same dir>`.
  * Music Box panel (Wave D3; not full-screen, the world keeps running behind it): `... -- --windowed --area=surface
    --ui-open=music_box --shots=<abs dir> --shot-times=4 --quit-at=6` (opened without a box: no house check; only discovered songs
    are listed - m01 always, more after `--hour=` / walking around in the same run).
  * Echo Trial arenas (Wave D1): the Matron's trial is what the area hosts by default: `... -- --windowed --area=echo_trial
    --flags=weaver_defeated --save-dir=<abs dir> --shots=<abs dir> --shot-times=3,8 --quit-at=10`. Count Velour's and the
    Choir's arenas are only entered through their echo stones (no direct switch): boot at the stone - `--area=moonveil_manor
    --spawn=manor_ballroom --flags=ch2_velour_defeated` or `--area=hushed_works --spawn=bell_throat
    --flags=ch2_choir_defeated,ch2_line_water,ch2_line_bell,ch2_line_light --give=lantern` (both with `--save-dir`) - screenshot
    the stone (Bell Throat position check: lead decision L10), then press E and "Enter the echo" with `tools/winctl.ps1` or the
    QA bot.
* Drive a running build with real OS input: `tools/winctl.ps1 -ProcId <pid> -Action seq -Seq "W:800,E:80"`
* Second-monitor QA playthrough (the owner keeps full use of monitor 1; virtual input, no SendInput, no focus):
  `python tools/qa/playthrough.py --second-monitor --mute --out qa/tmp/e2e/sm1` (packaged build; same flags for
  `tools/qa/persistence.py`). Current sources without a rebuild: add `--dev --exe .tools/godot/Godot_v4.7.2-stable_win64.exe`.
  It launches the game with `-- --qa-input-port=<free port> --qa-no-focus --qa-window=1920,0,1920,1080
  --settings-file=<out>/qa_settings.cfg --save-dir=<out>/saves --qa-telemetry=<file> [--qa-mute]`, from a
  hard-linked copy of the exe in `<out>/qa_exe/` with an `override.cfg` (windowed, borderless,
  `display/window/size/no_focus`) so the window never activates; `--dev` runs cannot use that override and may
  take focus once while the boot window leaves fullscreen. Game side: `game/src/qa/qa_input.gd` (127.0.0.1 only,
  JSON lines: `k`, `mb`, `mm`, `move`, `click`, `shot`, `release_all`), `Debug` (flags), `Settings`
  (`--settings-file`, `--qa-window` / `--qa-screen`). The flags work in release builds too and grant no cheats.
  Honest scope: injected input bypasses the OS input layer (no Windows focus / raw input / cursor capture); from
  `Input.parse_input_event` on it takes the same InputMap / `_input` / GUI / `_unhandled_input` path as a real
  keyboard and mouse, and the camera turns through `CameraRig.rotate_by()` with the same delta its `_input()`
  would get. OS-level input problems are only caught by the default SendInput transport. Don't click on the QA
  monitor while it runs (mouse clicks there still reach the game). Verified headless (unit tests
  `tools/test.sh qa_input` + a Python client against headless Godot); a visible second-monitor run is still to do.

## Rules
* Follow the Golden Rules in docs/ARCHITECTURE.md (no class_name, scripts build their own children,
  typed GDScript with tabs, data-driven, state in GameState, Events bus, arachnophobia & comfort rules).
* Keep the release build free of cheats: debug features check `Debug.is_cheat_allowed()`.
* Tests only write inside `user://test_saves/`. Never delete the player's real saves.
* Always bound processes: `timeout`, `--quit-at`, `--max-seconds`. Kill only processes you started.
* Don't weaken or delete tests to make them pass. Record real evidence in QA_REPORT.md.
