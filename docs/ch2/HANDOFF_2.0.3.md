# Handoff — Hollowhaven 2.0.3, the gift build

Krystal has never played Hollowhaven. She installs it on her own PC and starts with **New Game**: Chapter One, then Chapter Two
from the Ward Stone, in one save. (The older handoffs, `HANDOFF_2.0.0.md`-`HANDOFF_2.0.2.md`, were written for a returning player
with a Chapter One save; they do not apply to her.)

## What to give her
* **One file:** `C:\Users\Ali\Desktop\Hollowhaven\dist\Hollowhaven-Setup-2.0.3.exe` (100.8 MB, SHA-256
  `9A8660DDF85E344C2333100B1E47FC90A791B9F49162B59ED8CE3822A26D18E2`, also in `dist\SHA256SUMS.txt`).
* The same game without an installer, if ever needed: `dist\Hollowhaven-2.0.3-Windows.zip` (111.1 MB, SHA-256
  `1788D65B101CCF4581011C3ABE60963CF18511A96A59DAA58FA5FBD2FA60A670`; extract, run `Hollowhaven\Hollowhaven.exe`).
* **How to hand it over:** a **USB stick** is best (it usually avoids the SmartScreen box too). A cloud-drive link (OneDrive, Google
  Drive, Dropbox ...) works, but the browser may warn that the file "isn't commonly downloaded" (choose Keep) and SmartScreen will
  ask. **E-mail cannot carry it**: 100 MB is far over attachment limits, and Gmail / Outlook block `.exe` files anyway.
* Before you give it: check her PC against `docs/ch2/DIFFERENT_PC_READINESS.md` §2 (Start -> `dxdiag`: 64-bit Windows 10/11, the
  graphics chip), update her graphics driver, and give her a **mouse** (the camera turns with the mouse). Run the installer once on
  your own PC and look at the pages - nobody has seen them on screen yet (untick "Play Hollowhaven now" on the last page unless you
  want the game to open with your own saves).

## What she does
1. Double-click `Hollowhaven-Setup-2.0.3.exe`. If Windows says **"Windows protected your PC"**: click **More info**, then
   **Run anyway** (the game is homemade and not code-signed). No administrator password is asked for.
2. Click through the short wizard (Welcome - folder - "Create a desktop shortcut" - Install - Finished). The game goes to
   `%LOCALAPPDATA%\Programs\Hollowhaven`; the Start menu gets **Hollowhaven** and **How to Play**.
3. Start Hollowhaven and choose **New Game**: "Before You Begin" (comfort options, e.g. arachnophobia mode), then "Meet Krystal"
   (her look), then Chapter One. From then on **Continue** on the title screen carries on where she left off. Chapter Two begins at
   the Ward Stone in the Haven after the Chapter One ending ("Follow the lantern road"), in the same save.
4. Controls and tips: Start menu > **How to Play**, or **F1** in the game. If it does not start or runs slowly:
   `docs/ch2/DIFFERENT_PC_READINESS.md` §4 (driver update, Graphics quality: Low, the `--rendering-driver d3d12` shortcut, the log to
   send you).

## Updating later / uninstalling
* **Update:** give her a newer `Hollowhaven-Setup-<version>.exe`; she runs it and it updates the installed game in place (same
  folder, one entry in Settings > Apps, her saves untouched). Ask her to **quit the game from its menu first** - an update over a
  running game window has not been tested.
* **Uninstall:** Settings > Apps > Hollowhaven > Uninstall. It removes the game, shortcuts and the Settings entry and **keeps her
  saved journey and settings** (`%APPDATA%\Hollowhaven`), so a later install carries on where she left off. Never delete that folder.
* Details: `docs/INSTALLER.md`.

## What is verified - and what is not
* **Verified (automated / bot / silent):** the installer's files are byte-identical to the release build (a silent test install of
  2.0.3); silent install, reinstall, update in place, shortcuts and uninstall keeping `%APPDATA%\Hollowhaven` (2.0.2-era installer
  tests); a fresh New Game through Chapter One to accepting Chapter Two (2.0.1 and 2.0.2 packaged, visible, 21/21 steps; 2.0.3 headless
  on the identical sources: completes, 721.5 s - not on the installed exe); Chapter Two from a save made by New Game (2.0.2 packaged: completes, visible and headless; 2.0.3 **installed** exe,
  headless: completes, 1509.3 s, 0 script errors, Continue after a relaunch with the same items; the test install was then
  silently uninstalled, saves folder untouched); full automated suite on 2.0.3: **2712 tests, 0 failed**. Evidence: `QA_REPORT.md` §13, `qa/evidence/ch2_v2.0.3/`.
* **Not verified:** no human has played it (she is the first; playtime unmeasured); no OS-level keyboard / mouse run; nobody has
  listened to the music; nothing judged in motion; **never run on a PC other than the development PC** - the weaker-GPU numbers
  and the minimum PC are estimates; the installer wizard pages, SmartScreen / Smart App Control on her Windows, and the default
  fullscreen first start were never seen. On a weak laptop the game's own first choice of graphics settings can be slow (about
  15 FPS measured on the weakest chip): if so, `How to Play.txt` "IF THE GAME RUNS SLOWLY" (Graphics quality Low). The optional friend Pipkin is not in the game. Known small issues: `KNOWN_ISSUES.md`.
