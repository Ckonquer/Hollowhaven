; Hollowhaven - Windows installer script (Inno Setup 6.7, command-line compiler ISCC.exe).
; Build it with:  powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1
; That script checks the release build, passes /DAppVersion=<game/project.godot config/version> and writes
; dist\Hollowhaven-Setup-<version>.exe. Everything is explained in docs\INSTALLER.md.

; ==================================================================================================================
;  The personal words - Ali, put your own here.
;  Keep each one on a single line. %n starts a new line (%n%n = an empty line between two paragraphs).
;  Inside the quotes, a double quote must be typed twice ("") - or just use ' instead.
;  WelcomeTitle is the big heading on the first page; WelcomeMessage is the first paragraph under it (the page then
;  adds one plain line saying what will be installed). The Finished pair is the last page, after installing.
; ==================================================================================================================
#define WelcomeTitle    "Welcome to Hollowhaven"
#define WelcomeMessage  "A little haven in the woods, made for you."
#define FinishedTitle   "Hollowhaven is ready"
#define FinishedMessage "Everything is set up. You can start Hollowhaven any time from the Start menu."
; ==================================================================================================================

#ifndef AppVersion
  #error AppVersion is not defined - build with tools\build_installer.ps1 (it passes /DAppVersion=x.y.z)
#endif
; Numeric x.y.z[.w] for the Windows version resource (build_installer.ps1 passes it; defaults to AppVersion).
#ifndef AppVersionNumeric
  #define AppVersionNumeric AppVersion
#endif
; What gets installed: everything the release build ships (tools\build_release.ps1 -> builds\Hollowhaven).
#ifndef BuildDir
  #define BuildDir AddBackslash(SourcePath) + "..\..\builds\Hollowhaven"
#endif
#define RepoDir AddBackslash(SourcePath) + "..\.."
#define ArtDir AddBackslash(SourcePath) + "art"

#if !FileExists(BuildDir + "\Hollowhaven.exe")
  #error builds\Hollowhaven\Hollowhaven.exe not found - run tools\build_release.ps1 first
#endif
#if !Is64BitPEImage(BuildDir + "\Hollowhaven.exe")
  #error builds\Hollowhaven\Hollowhaven.exe is not a 64-bit Windows program
#endif

[Setup]
; The AppId identifies Hollowhaven to Windows. NEVER change it: a later installer with the same AppId upgrades the
; installed game in place (same folder, one entry in Settings > Apps) instead of installing a second copy.
AppId={{6FD89CDE-658C-4364-8ACE-AC51476C639C}
AppName=Hollowhaven
AppVersion={#AppVersion}
AppVerName=Hollowhaven {#AppVersion}
AppPublisher=Ali
AppCopyright=Copyright (C) 2026 Ali. Made for Krystal.
UninstallDisplayName=Hollowhaven
UninstallDisplayIcon={app}\Hollowhaven.exe
VersionInfoVersion={#AppVersionNumeric}
VersionInfoProductVersion={#AppVersionNumeric}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoProductName=Hollowhaven
VersionInfoCompany=Ali
VersionInfoDescription=Hollowhaven Setup
VersionInfoCopyright=Copyright (C) 2026 Ali

; Per-user install: no administrator rights, no UAC prompt. {autopf} is %LOCALAPPDATA%\Programs for a per-user
; install, so the game goes to %LOCALAPPDATA%\Programs\Hollowhaven. Shortcuts and the uninstall entry are per-user.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Hollowhaven
DefaultGroupName=Hollowhaven
DisableProgramGroupPage=yes
; The Start Menu page is never shown; AllowNoIcons only makes the /NOICONS command-line switch work (silent test
; installs without Start Menu shortcuts). No visible change in the wizard.
AllowNoIcons=yes
DisableWelcomePage=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Only one Hollowhaven Setup at a time.
SetupMutex=HollowhavenSetup_6FD89CDE

; An upgrade can replace a game that is still running: Setup offers to close it (Windows Restart Manager).
; It is not started again by itself afterwards (the Finished page offers "Play Hollowhaven now").
CloseApplications=yes
RestartApplications=no

WizardStyle=modern
WizardImageFile={#ArtDir}\wizard_164x314.bmp,{#ArtDir}\wizard_202x386.bmp,{#ArtDir}\wizard_269x515.bmp,{#ArtDir}\wizard_328x628.bmp,{#ArtDir}\wizard_403x772.bmp,{#ArtDir}\wizard_534x1022.bmp
WizardSmallImageFile={#ArtDir}\wizard_small_55.bmp,{#ArtDir}\wizard_small_58.bmp,{#ArtDir}\wizard_small_77.bmp,{#ArtDir}\wizard_small_97.bmp,{#ArtDir}\wizard_small_110.bmp,{#ArtDir}\wizard_small_124.bmp,{#ArtDir}\wizard_small_143.bmp,{#ArtDir}\wizard_small_159.bmp
SetupIconFile={#RepoDir}\game\icon.ico

Compression=lzma2/ultra64
SolidCompression=yes
OutputDir={#RepoDir}\dist
OutputBaseFilename=Hollowhaven-Setup-{#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1={#WelcomeTitle}
WelcomeLabel2={#WelcomeMessage}%n%nThis will install Hollowhaven on this computer. It only takes a minute.
FinishedHeadingLabel={#FinishedTitle}
FinishedLabel={#FinishedMessage}
FinishedLabelNoIcons={#FinishedMessage}
; Uninstalling never touches the saved game or the settings (they live in %APPDATA%\Hollowhaven, see [Files] note).
ConfirmUninstall=Remove %1 from this computer?%n%nYour saved game and settings are kept, so if you install Hollowhaven again later you can carry on where you left off.
UninstalledAll=%1 was removed from this computer.%n%nYour saved game and settings were kept.

[Tasks]
; Checked by default (no "unchecked" flag).
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Everything in the release build folder, sub-folders included; "How to Play.txt" keeps its name.
; The game keeps its saves and settings in %APPDATA%\Hollowhaven (Godot user://), never in the install folder, so the
; uninstaller - which removes only what this installer put down - can never reach them. There is deliberately no
; [UninstallDelete] section and no [Code] section.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Hollowhaven"; Filename: "{app}\Hollowhaven.exe"; WorkingDir: "{app}"; Comment: "Play Hollowhaven"
Name: "{group}\How to Play"; Filename: "{app}\How to Play.txt"; WorkingDir: "{app}"; Comment: "How to play Hollowhaven"
Name: "{autodesktop}\Hollowhaven"; Filename: "{app}\Hollowhaven.exe"; WorkingDir: "{app}"; Comment: "Play Hollowhaven"; Tasks: desktopicon

[Run]
Filename: "{app}\Hollowhaven.exe"; WorkingDir: "{app}"; Description: "Play Hollowhaven now"; Flags: postinstall nowait skipifsilent
