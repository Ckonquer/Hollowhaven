# Hollowhaven

A small 3D cozy survival-adventure with creature companions and a restrained horror dungeon, made as
a gift for Krystal. Chapter One: *The Dimming Ward* (designed for about 45–90 minutes; no player has timed it yet), then free-play in your own
little haven. Chapter Two: *The Lanterns of Hallowmere* follows in the same save, from the Ward Stone: a lantern
road to an autumn festival town, a wardrobe, companions that fight beside you, new gear, two-storey building,
Halloween decorations, echo trials, expeditions, a music box and a lot of new music.
**Version 2.0.3 is the gift build**: one installer for Krystal, who has never played and starts with New Game.
The game has been tested by automated tests, a test bot with virtual input (headless, and on the packaged game on a
second monitor) and screenshots, but not yet played by a person, listened to, or run on a PC other than the
development one - see `KNOWN_ISSUES.md`. Hand-over notes: `docs/ch2/HANDOFF_2.0.3.md`.

## Just want to play?
1. Run the installer **`dist/Hollowhaven-Setup-2.0.3.exe`** (built by `tools/build_installer.ps1` after
   `tools/build_release.ps1`; SHA-256 in `dist/SHA256SUMS.txt`). It adds **Hollowhaven** and **How to Play** to the
   Start menu and, unless you untick the box, a Desktop shortcut.
2. If Windows SmartScreen says "Windows protected your PC", click **More info → Run anyway**
   (the game isn't code-signed; this is normal for a homemade game).
3. Start Hollowhaven and choose **New Game**: the comfort options ("Before You Begin"), then "Meet Krystal" (her look),
   then Chapter One. The journey is saved straight away, and from then on **Continue** on the title screen carries on
   where she left off. Chapter Two begins at the Ward Stone in the Haven after the Chapter One ending
   ("Follow the lantern road"), in the same save.

No accounts, internet or game engine needed. Saves live in `%APPDATA%\Hollowhaven\saves`; uninstalling (Windows
Settings > Apps) keeps them. Controls, saving, companions, building, the wardrobe and the comfort settings (e.g.
arachnophobia mode): **`How to Play.txt`** (Start menu > How to Play, or next to `Hollowhaven.exe`; source copy:
`docs/player/`), or press **F1** in game for every key.

No installer wanted? `dist/Hollowhaven-2.0.3-Windows.zip` is the same game: extract it anywhere and double-click
`Hollowhaven.exe` in the extracted `Hollowhaven` folder (same saves folder; SmartScreen may ask once, as above).
Older zips and installers in `builds/superseded/` are superseded builds. Carrying a pre-2.0 (Chapter One v0.9.x) save
forward, or going back to it, is a developer topic: `docs/ch2/SAVE_INTEGRITY_REPORT.md` §8 (also `docs/SAVE_MIGRATION.md` §8).

## What's in this folder
| Path | What it is |
|---|---|
| `builds/Hollowhaven/` | The playable game (after building) |
| `dist/` | The installer (`Hollowhaven-Setup-2.0.3.exe`), the same game as a ZIP, and `SHA256SUMS.txt` (the build scripts move older zips / installers to `builds/superseded/`) |
| `game/` | Editable Godot 4.7.2 project (source code, shaders, data, audio) |
| `tools/` | Build, installer (`tools/installer/`, `build_installer.ps1`), test, toolchain and asset-generation scripts |
| `docs/` | The installer guide (`INSTALLER.md`), the 2.0.3 handoff (`docs/ch2/HANDOFF_2.0.3.md`; the earlier returning-player handoffs `HANDOFF_2.0.0.md`-`HANDOFF_2.0.2.md`), the PC-readiness report (`docs/ch2/DIFFERENT_PC_READINESS.md`), architecture contract, Chapter Two contract (`CHAPTER_TWO_SPEC.md`), save migration, install log, Chapter Two build records, save-integrity report and music manifest (`docs/ch2/`) |
| `docs/player/` | `How to Play.txt` (the player guide shipped next to the game and opened from the Start Menu) |
| `qa/` | Test evidence (screenshots, logs; release evidence in `qa/evidence/ch2_v2.0.0/` ... `ch2_v2.0.3/`) |
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
powershell -ExecutionPolicy Bypass -File tools/build_installer.ps1   # installer from that build (docs/INSTALLER.md)
```
To edit in the Godot editor: run `.tools/godot/Godot_v4.7.2-stable_win64.exe` and open `game/project.godot`.
Regenerate audio: `.tools/pyenv/Scripts/python.exe tools/audio/generate_all.py` (Chapter One sounds and music) and the
Chapter Two music groups `tools/audio/music2/group_*.py` (see `docs/ch2/MUSIC_MANIFEST.md`), then re-import.
