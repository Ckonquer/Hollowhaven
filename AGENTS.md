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
* Run the game (debug, windowed):   `tools/godot.sh --path game --windowed --resolution 1600x900`
* Jump into an area (debug only):   `... -- --area=surface --spawn=haven_start`
* Area screenshots (debug only):    `... -- --area=surface --cams="x,y,z,yaw,pitch;..." --shot-dir=<abs dir>`
* Preview one visual script:        `... -- --preview=res://src/companions/mochi.gd --shot-dir=<abs dir>`
* Release build + zip:              `powershell -ExecutionPolicy Bypass -File tools/build_release.ps1`
* Drive a running build with real OS input: `tools/winctl.ps1 -ProcId <pid> -Action seq -Seq "W:800,E:80"`

## Rules
* Follow the Golden Rules in docs/ARCHITECTURE.md (no class_name, scripts build their own children,
  typed GDScript with tabs, data-driven, state in GameState, Events bus, arachnophobia & comfort rules).
* Keep the release build free of cheats: debug features check `Debug.is_cheat_allowed()`.
* Tests only write inside `user://test_saves/`. Never delete the player's real saves.
* Always bound processes: `timeout`, `--quit-at`, `--max-seconds`. Kill only processes you started.
* Don't weaken or delete tests to make them pass. Record real evidence in QA_REPORT.md.
