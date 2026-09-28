# The Hollowhaven installer

`dist\Hollowhaven-Setup-<version>.exe` is the one file to give Krystal. She double-clicks it, clicks through a
short wizard (no administrator password, no UAC prompt), and ends up with Hollowhaven in her Start menu and,
by default, on her Desktop. It is built with Inno Setup 6 from the release build in `builds\Hollowhaven`.

Files:

| Path | What it is |
|---|---|
| `tools\installer\hollowhaven.iss` | the installer script (the personal welcome words are at the very top) |
| `tools\build_installer.ps1` | checks the release build, compiles the script, writes the checksum line |
| `tools\installer\art\make_art.py` | makes the wizard pictures (Pillow, from existing images only) |
| `tools\installer\art\wizard_*.bmp` | the wizard pictures (24-bit BMP, one per screen-scaling size) |
| `tools\installer\art\source_scene.png` | the crop of the game screenshot the big picture is made from |

## Building it

Run the release build first, then the installer:

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1
powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1
```

The order matters: `build_release.ps1` deletes and re-exports `builds\Hollowhaven` and rewrites
`dist\SHA256SUMS.txt` with the zip's line only. `build_installer.ps1` then adds the installer's line (and keeps
the zip's).

`build_installer.ps1`:

1. finds the Inno Setup 6 command-line compiler: `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` (where it is
   installed on this PC), else the Program Files locations, else `-Iscc <path to ISCC.exe>`;
2. reads the version from `game\project.godot` (`config/version`, must be plain numbers like `2.0.3`);
3. checks `builds\Hollowhaven\Hollowhaven.exe` exists and its file version is that version (`2.0.3` = `2.0.3.0`),
   that `builds\Hollowhaven\How to Play.txt` exists (the Start Menu shortcut opens it), and that
   `builds\Hollowhaven` still holds exactly the files of `dist\Hollowhaven-<version>-Windows.zip` (same names, same
   SHA-256). QA runs start the game from that folder and hard-link to its exe, so a file added or changed there after
   the release build - above all an `override.cfg`, which Godot reads from the exe's folder - stops the build instead
   of ending up on her PC;
4. moves an older `dist\Hollowhaven-Setup-*.exe` to `builds\superseded\` (never deletes it), like
   `build_release.ps1` does with older zips;
5. compiles `tools\installer\hollowhaven.iss` quietly with `/DAppVersion=<version>` (about a minute:
   lzma2/ultra64 solid compression; the installer is about 101 MB for the 185 MB build);
6. checks the installer's own version resource, prints its path, size and SHA-256, and adds or replaces its line
   in `dist\SHA256SUMS.txt`.

It stops with a red `build_installer.ps1 FAILED: ...` line and exit code 1 on any problem (compiler missing,
version mismatch, missing build or zip, build folder not matching the zip, compile error).

Run it again after **every** `build_release.ps1`, even for the same version number: the installer is not rebuilt
by `build_release.ps1`, so an installer left in `dist\` from before would still hold the older build under the same
file name. The sign of that: `dist\SHA256SUMS.txt` has only the zip's line (`build_release.ps1` rewrites it).

Don't expect a rebuild to be byte-identical (two builds of the same files from different folders had different
SHA-256s); the line in `SHA256SUMS.txt` always matches the installer next to it.

The installer installs **everything** in `builds\Hollowhaven`, sub-folders included, under the same names
(`Hollowhaven.exe`, `How to Play.txt`, `Licenses\...`). Nothing needs changing here when the release build ships
different documents.

## What Krystal sees

1. **Welcome** - the big picture on the left (the Ward Stone, Krystal, Mochi, "Hollowhaven - For Krystal"), the
   heading "Welcome to Hollowhaven" and the personal line "A little haven in the woods, made for you.", then
   "This will install Hollowhaven on this computer. It only takes a minute."
2. **Select Destination Location** - suggests `%LOCALAPPDATA%\Programs\Hollowhaven`
   (for example `C:\Users\Krystal\AppData\Local\Programs\Hollowhaven`). Just click Next. This page is skipped when
   Hollowhaven is already installed (an update goes to the same folder).
3. **Select Additional Tasks** - "Create a desktop shortcut", ticked.
4. **Ready to Install** - click Install. Installing takes a few seconds.
5. **Finished** - "Hollowhaven is ready", with **Play Hollowhaven now** ticked. Click Finish and the game starts.

Requirements: 64-bit Windows 10 or 11 (the installer refuses to run elsewhere). No internet, no account.

## Where things go

| What | Where | Removed by uninstall? |
|---|---|---|
| The game (`Hollowhaven.exe`, `How to Play.txt`, `Licenses\`) | `%LOCALAPPDATA%\Programs\Hollowhaven\` | yes |
| The uninstaller (`unins000.exe`, `unins000.dat`) | same folder | yes |
| Start Menu folder "Hollowhaven" with "Hollowhaven" and "How to Play" | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Hollowhaven\` | yes |
| Desktop shortcut "Hollowhaven" (if ticked) | her Desktop (also when the Desktop is in OneDrive) | yes |
| The entry in Settings > Apps | `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6FD89CDE-658C-4364-8ACE-AC51476C639C}_is1` | yes |
| **Her saved journey and settings** (and the game's logs / shader cache) | `%APPDATA%\Hollowhaven\` - written by the game, not by the installer | **never** |

Everything is per-user: nothing goes to Program Files, nothing is written to `HKEY_LOCAL_MACHINE`, and no
administrator rights are asked for (`PrivilegesRequired=lowest`).

## Updating later

The script's `AppId` (`{6FD89CDE-658C-4364-8ACE-AC51476C639C}`) must never change. Because of it, a newer
`Hollowhaven-Setup-<version>.exe` recognises the installed game and updates it in place: same folder, the same
single entry in Settings > Apps (with the new version number), her shortcut choice remembered, and her saves
untouched (they are not in the install folder). She just runs the new installer.

If the game is still running during an update, Setup stops on a "Preparing to Install" page and offers to close
it (Windows Restart Manager; `CloseApplications=yes`). It is not restarted automatically
(`RestartApplications=no`); the Finished page offers "Play Hollowhaven now" instead. Not tried with a visible game
window yet (see "How it was tested"), and it is not known whether the game gets the chance to save on Restart
Manager's close request the way it does when its window's X is clicked (`game.gd` saves on the window close request)
- so when you give her an update, tell her to quit the game from its menu first.

Files that an older version shipped and a newer one no longer ships stay in the folder until uninstall (harmless;
the uninstaller removes every file any version installed).

## Uninstalling

Settings > Apps > Installed apps > Hollowhaven > ... > Uninstall (or Control Panel > Programs and Features, or
`unins000.exe` in the game folder). It asks "Remove Hollowhaven from this computer? Your saved game and settings
are kept, so if you install Hollowhaven again later you can carry on where you left off." and afterwards says the
saved game and settings were kept.

It removes only what the installer put down: the game files, the uninstaller, the Start Menu folder, the Desktop
shortcut and the Settings > Apps entry.

**It never deletes or touches `%APPDATA%\Hollowhaven`** (saves, `settings.cfg`, logs, shader cache). The script
has no `[UninstallDelete]`, no `[Registry]`, no `[InstallDelete]` and no `[Code]` section, and nothing in it
refers to `{userappdata}`; the uninstaller only removes what its log (`unins000.dat`) lists. To wipe Hollowhaven
completely, that folder would have to be deleted by hand - which deletes her journey, so don't.

## "Windows protected your PC" (SmartScreen)

Neither the installer nor `Hollowhaven.exe` is code-signed. Signing needs a paid certificate, which is out of scope
for this gift. So when the installer was **downloaded** (from a browser or a cloud-drive link), Windows
Defender SmartScreen shows a blue "Windows protected your PC" box the first time it is run:

> click **More info**, then **Run anyway**.

How to hand it over: a **USB stick** is the easiest - it usually avoids that box too (SmartScreen checks files
Windows marked as coming from the internet). A cloud-drive link (OneDrive, Google Drive, Dropbox ...) works but
brings the box, and the browser may first warn that the file "isn't commonly downloaded" (choose Keep; in Edge
it is under "..." > Keep > Show more > Keep anyway). **E-mail does not work**: the installer is about 100 MB, far
over attachment limits, and Gmail and Outlook block `.exe` attachments anyway.

The installed game itself is not marked, so it normally starts without the box. Not verified
on another PC: if her Windows 11 has **Smart App Control** turned on (Windows Security > App & browser control),
unsigned programs can be blocked outright, without a "Run anyway" button; only code signing avoids that.

## Changing the welcome message (Ali)

Open `tools\installer\hollowhaven.iss` in any text editor. At the very top:

```
#define WelcomeTitle    "Welcome to Hollowhaven"
#define WelcomeMessage  "A little haven in the woods, made for you."
#define FinishedTitle   "Hollowhaven is ready"
#define FinishedMessage "Everything is set up. You can start Hollowhaven any time from the Start menu."
```

- `WelcomeTitle` is the big heading of the first page, `WelcomeMessage` the first paragraph under it (the page
  then adds "This will install Hollowhaven on this computer. It only takes a minute."). The `Finished` pair is the
  last page.
- Write between the quotes, keep each on one line. `%n` starts a new line; `%n%n` leaves an empty line, e.g.
  `"A little haven in the woods, made for you.%n%nLove, Ali"`.
- A double quote inside the text must be typed twice (`""`), or use `'` instead. Apostrophes, accented letters
  and a heart are fine: Inno Setup 6.7 reads the script as UTF-8 with or without a BOM (what Notepad saves) and
  falls back to the Windows ANSI code page for an older editor's ANSI file. Checked in the built Setup (not only the
  compiler): a test script's `"A little haven in the woods — made for you, café ♥ “quoted”, it's 100% yours.%n%nLove, Ali"`
  came out character for character (with the two line breaks) from UTF-8 with a BOM, UTF-8 without one, and an
  ANSI file (there without the ♥, which ANSI cannot hold). A plain `%` is fine. How such text looks on the wizard
  page was not seen - look once after building (emoji were not tried at all; they may not show in colour, or at all,
in the wizard's plain Windows font, so ♥ is the safer heart).

Then rebuild: `powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1`.

The words in the picture ("Hollowhaven", "For Krystal" with a heart - the same dedication as the title screen)
are part of the image. To change the picture, edit and run
`.tools\pyenv\Scripts\python.exe tools\installer\art\make_art.py` (it uses the game's own fonts and colours and
always builds from `tools\installer\art\source_scene.png`, a crop of the packaged-build screenshot
`qa\tmp\e2e\final_202_fresh\play_039_ending.png`, so a re-run gives the same pictures; `--screenshot <1920x1080 png>`
re-crops another screenshot and replaces `source_scene.png`), then rebuild the installer.

## How it was tested

Only ever silently - no installer or uninstaller window was opened on this PC - so the look of the wizard pages
has not been seen on screen. Before handing it over, run it once yourself (it is safe on this PC: install, look,
uninstall from Settings > Apps; untick "Play Hollowhaven now" on the last page unless you want the game to open
with your own saves).

Silent commands used (Git Bash mangles `/SWITCHES` into paths: run them from PowerShell or set
`MSYS2_ARG_CONV_EXCL='*'`):

```
Hollowhaven-Setup-<v>.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS /MERGETASKS="!desktopicon" /DIR="<scratch dir>" /LOG="<log>"
<scratch dir>\unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="<log>"
```

- Always pass `/NORESTART` to a very silent uninstall: without it, an uninstall that needs a restart reboots the
  PC without asking.
- `/NOICONS` (no Start Menu folder) and `/MERGETASKS="!desktopicon"` (no Desktop shortcut) keep test installs off
  the Start menu and Desktop.
- All installs of this AppId share the one Settings > Apps entry: a second test install in another folder takes
  the entry over. Test one install at a time and uninstall it before the next.
- A test build with another version number, compiled next to the real one without touching `dist\`:
  `ISCC.exe /Q /DAppVersion=2.0.0 /O<scratch dir> /FHollowhaven-Setup-2.0.0-TEST tools\installer\hollowhaven.iss`.

Covered: byte-identical files (SHA-256 of every file against `builds\Hollowhaven`), the Settings > Apps entry
values, no `HKEY_LOCAL_MACHINE` entry, a headless boot of the installed game, same-version reinstall, 2.0.0 -> 2.0.2
update in place without `/DIR` (found the old folder, one entry), Start Menu + Desktop shortcuts resolving to the
right targets, silent uninstall removing everything it installed, the uninstall data listing no path under
`%APPDATA%\Hollowhaven`, and `%APPDATA%\Hollowhaven` unchanged by all of it. An update while a *headless* (windowless)
game ran from the install folder was refused safely (Restart Manager cannot close a process without a window;
Setup aborted before changing any file, exit code 5); the normal case - a game window Setup can close - was not run.

Independent review re-run (same silent rules): `build_installer.ps1` run in a scratch copy of the repo layout
(success, plus refusals for an added `override.cfg`, a changed and a missing file, and a missing zip); a silent
install, headless boot and silent uninstall; and an install **with** shortcuts into a folder whose path has spaces,
an accent, ♥ and a Chinese character (like a Windows user name with such letters), followed by an in-place
reinstall without `/DIR`, a headless boot with `APPDATA` also pointed at a non-ASCII folder, and the uninstall.
All files matched, the shortcuts pointed exactly at the non-ASCII targets, one Settings > Apps entry throughout,
and nothing was left behind. Note for such checks: PowerShell's `WScript.Shell` shortcut reader shows `?` for
letters outside the ANSI code page even when the shortcut is right; read `.lnk` files through `IShellLinkW` instead.
The Desktop here is not OneDrive-redirected, so that case is covered only by Inno Setup's `{autodesktop}` using the
shell's real Desktop folder, not by a test.
