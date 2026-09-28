# Hollowhaven — For Krystal

A small 3D cozy survival-adventure with creature companions and a restrained horror dungeon, made as
a gift for Krystal. Chapter One: *The Dimming Ward* (about 45–90 minutes), then free-play in your own
little haven. Chapter Two: *The Lanterns of Hallowmere* continues the same save: a lantern road to an
autumn festival town, a wardrobe, companions that fight beside you, new gear, two-storey building,
Halloween decorations and a lot of new music (still being built and checked: see `KNOWN_ISSUES.md`).

## Just want to play?
1. Open `dist/` and extract `Hollowhaven-<version>-Windows.zip` anywhere (e.g. your Desktop).
   If there is more than one zip, use the **newest version** (the one named in `dist/SHA256SUMS.txt`);
   older zips are superseded builds.
2. Open the extracted `Hollowhaven` folder and **double-click `Hollowhaven.exe`**.
3. If Windows SmartScreen says "Windows protected your PC", click **More info → Run anyway**
   (the game isn't code-signed; this is normal for a homemade game).

No installation, accounts, internet or game engine needed. Saves live in `%APPDATA%\Hollowhaven\saves`.
Controls and comfort settings: see `How to Play.txt` next to the game (or press **F1** in game).

**Already played Chapter One?** Press **Continue**, not New Game: the same house, friends and story carry
on. What changed is in `Chapter Two - What's New.txt` (`docs/player/`). The first Chapter Two save keeps an
untouched copy of the Chapter One save in `saves\pre_v2_backup\`; an older build cannot open the new save
(rollback steps: `docs/SAVE_MIGRATION.md`, section 8).

## What's in this folder
| Path | What it is |
|---|---|
| `builds/Hollowhaven/` | The playable game (after building) |
| `dist/` | The ZIP of the playable game + SHA-256 checksum (the build script moves older zips to `builds/superseded/`) |
| `game/` | Editable Godot 4.7.2 project (source code, shaders, data, audio) |
| `tools/` | Build, test, toolchain and asset-generation scripts |
| `docs/` | Architecture contract, Chapter Two contract (`CHAPTER_TWO_SPEC.md`), save migration, install log |
| `docs/player/` | `How to Play.txt` and `Chapter Two - What's New.txt` (the player update note) |
| `qa/` | Test evidence (screenshots, logs) |
| `GAME_SPEC.md` | Game design (concise) |
| `PROJECT_STATE.md` | What's done, what's next (for future development) |
| `QA_REPORT.md` | What was actually tested and how |
| `KNOWN_ISSUES.md` | Honest list of remaining issues |
| `THIRD_PARTY_NOTICES.md` | Engine, fonts and asset provenance |
| `AGENTS.md` | Rules and verified commands for developers (human or AI) |

## For developers
Everything is project-local. From the repo root (Git Bash):
```bash
powershell -ExecutionPolicy Bypass -File tools/setup_toolchain.ps1   # Godot 4.7.2 + templates + Python venv
tools/test.sh                                                        # headless automated tests
tools/godot.sh --path game --windowed --resolution 1600x900          # run from source
powershell -ExecutionPolicy Bypass -File tools/build_release.ps1     # export + zip
```
To edit in the Godot editor: run `.tools/godot/Godot_v4.7.2-stable_win64.exe` and open `game/project.godot`.
Regenerate audio: `.tools/pyenv/Scripts/python.exe tools/audio/generate_all.py` then re-import.
