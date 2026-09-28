# Handoff — Hollowhaven 2.0.0 (Chapter Two: The Lanterns of Hallowmere)

## Launch
* Give Krystal: `C:\Users\Ali\Desktop\Hollowhaven\dist\Hollowhaven-2.0.0-Windows.zip`
  (SHA-256 `9F3FD0D2E3216B861E470158B881A10ED2CEBBC30FC3C07D3BC61D93652856CC`, `dist\SHA256SUMS.txt`).
* She extracts it and runs **`Hollowhaven\Hollowhaven.exe`**, then presses **Continue, not New Game**.
  Update note: `Chapter Two - What's New.txt` next to the exe.
* Same build unzipped here: `C:\Users\Ali\Desktop\Hollowhaven\builds\Hollowhaven\Hollowhaven.exe`.
* Source: `C:\Users\Ali\Desktop\Hollowhaven\` (Godot 4.7.2 project in `game\`), git `36e2e8a`. Build: `tools/build_release.ps1`;
  tests: `tools/test.sh`; commands: `AGENTS.md`, `PROJECT_STATE.md`.

## Implemented (in the build)
Save schema v2 with additive migration and a one-time untouched copy of the Chapter One save; Chapter Two chosen at the Ward Stone;
waygate + Hallowmere Reach (Commons, Conservatory, Orchard, Pools, Candleyard, Quarry, Manor grounds, Bellhouse), Moonveil Manor,
the Hushed Works; Lantern Road travel home; "Meet Krystal", wardrobe (O, pause menu, mirror furniture, Ward Stone, Commons mirror),
cosmetic outfits separate from armor; equipment slots, tool / weapon / armor tiers, Sparkseed Wand; companions that fight, with
skills on T (Bloomguard, Stoneheart, Glimmerstep) and Mochi's courage; Furnace, Loom & Dye Bench, Kitchen Counter, masteries,
bigger backpack / chests; two-storey building, Halloween decor, recolour / undo / pumpkin face (Z / P / N); Chapter One extras and a
three-phase Weaver Matron; 5 new Chapter One and 6 Chapter Two enemy types; bosses Count Velour, the Crossing Matron, the Borrowed
Choir; Echo Trials for all three trial bosses; Lanternwake Expeditions; the Music Box; 27 music cues (22 new compositions) chosen by a
MusicDirector. Not implemented: the optional friend Pipkin; new creature voices (existing sounds are reused).

## Tests actually run
* Automated: full suite **2639 tests, 0 failed** (`qa/tmp/full_final1.log`, tree `9e8765f`; not re-run after the version-bump /
  `.uid` commit).
* Save: 12-scenario fixture matrix + 2 real v0.9.0 bot saves (all pass); `save_integrity.py` re-check of 14 migrations (0
  mismatches); real bot-save migration with byte-identical upgrade backup (`docs/ch2/SAVE_INTEGRITY_REPORT.md`).
* QA bot, headless, virtual input: segments S0-S4 (S0 / S1 natural, S2-S4 from diagnostic fixtures) and a natural end-to-end chain
  from the Chapter-One-complete save to Chapter Two complete + relaunch (4 of 5 runs complete, 1 stopped at the Quarry Warden) - on a
  pre-release source snapshot, not the exe.
* Still frames: 110 visual findings; 81 fixed and re-rendered, 5 partly, 24 addressed in code without a closure record.
* Performance: the packaged exe profiled per area at High / Low 1080p and High 720p on the RTX 4090, uncapped: 398-709 average
  FPS, 1 % lows 215-334, loads 0.9-2.9 s, round trips stable (`qa/tmp/perf/packaged_v200/summary.md`). No weaker GPU tested.
Details: `QA_REPORT.md` §9.

## Blockers / unverified
* **PERSONAL-SAVE VERIFICATION BLOCKED** - her save is not on this PC. Run the gate on a copy first
  (`docs/ch2/SAVE_INTEGRITY_REPORT.md` §7).
* No human play, no OS-level real-input run, no human listening, nothing judged in motion; performance only on an RTX 4090.
* Open: Quarry Warden can freeze below its bench edge (CHAIN-001, walk back up to restart) and can be won without pillar exposures
  (CHAIN-002); small UI items and avatar clipping limits (`KNOWN_ISSUES.md`).
* The zip's player docs / licence notice predate small corrections now in `docs/player/` and `THIRD_PARTY_NOTICES.md` (next rebuild).

## Safe rollback
1. Close the game. 2. In `%APPDATA%\Hollowhaven\saves` move `slot1.json` / `slot1.bak.json` into a new `v2_kept\` folder (keep them).
3. Copy `pre_v2_backup\slot1.v1-<time>.json` to `slot1.json` (and `slot1.bak.v1-<time>.json` to `slot1.bak.json` if present).
4. Unzip `C:\Users\Ali\Desktop\Hollowhaven_Backups\pre_chapter2_v0.9.1_2026-09-27\build\Hollowhaven-0.9.1-Windows.zip` somewhere
   new and play it. **Never open a 2.0.0 save with the old exe** (it would set the v2 file aside as corrupt).
