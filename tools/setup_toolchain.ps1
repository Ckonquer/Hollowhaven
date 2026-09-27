<#
  setup_toolchain.ps1 - reproducibly installs the project-local toolchain into .tools/
  (Godot 4.7.2 editor + Windows export templates, Python venv for audio generation).
  Nothing is installed system-wide. Safe to re-run.
  Usage:  powershell -ExecutionPolicy Bypass -File tools\setup_toolchain.ps1
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Tools = Join-Path $Root ".tools"
$Dl = Join-Path $Tools "downloads"
$GodotDir = Join-Path $Tools "godot"
$Version = "4.7.2-stable"
$Base = "https://github.com/godotengine/godot/releases/download/$Version"
$EditorZip = "Godot_v${Version}_win64.exe.zip"
$Templates = "Godot_v${Version}_export_templates.tpz"
New-Item -ItemType Directory -Force $Dl, $GodotDir | Out-Null

function Get-Verified($name) {
    $sums = Join-Path $Dl "SHA512-SUMS.txt"
    if (-not (Test-Path $sums)) { Invoke-WebRequest "$Base/SHA512-SUMS.txt" -OutFile $sums }
    $expected = (Select-String -Path $sums -Pattern ([regex]::Escape($name) + '$')).Line.Split(" ")[0]
    $file = Join-Path $Dl $name
    if (-not (Test-Path $file)) { Write-Host "Downloading $name ..."; Invoke-WebRequest "$Base/$name" -OutFile $file }
    $actual = (Get-FileHash $file -Algorithm SHA512).Hash.ToLower()
    if ($actual -ne $expected) { Remove-Item $file; throw "SHA-512 mismatch for $name" }
    Write-Host "Verified $name"
    return $file
}

$ProgressPreference = "SilentlyContinue"
$exe = Join-Path $GodotDir "Godot_v${Version}_win64_console.exe"
if (-not (Test-Path $exe)) {
    $zip = Get-Verified $EditorZip
    Expand-Archive $zip -DestinationPath $GodotDir -Force
}
New-Item -ItemType File -Force (Join-Path $GodotDir "_sc_") | Out-Null   # self-contained mode

$tplDir = Join-Path $GodotDir "editor_data\export_templates\4.7.2.stable"
if (-not (Test-Path (Join-Path $tplDir "windows_release_x86_64.exe"))) {
    $tpz = Get-Verified $Templates
    New-Item -ItemType Directory -Force $tplDir | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($tpz)
    foreach ($e in $z.Entries) {
        if ($e.Name -in @("version.txt", "windows_release_x86_64.exe", "windows_debug_x86_64.exe", "windows_release_x86_64_console.exe", "windows_debug_x86_64_console.exe")) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $tplDir $e.Name), $true)
        }
    }
    $z.Dispose()
}

# Python venv for tools/audio (needs Python 3.10+ available via the py launcher)
$venv = Join-Path $Tools "pyenv"
if (-not (Test-Path (Join-Path $venv "Scripts\python.exe"))) {
    py -3 -m venv $venv
    & (Join-Path $venv "Scripts\python.exe") -m pip install --disable-pip-version-check numpy scipy pillow
}
Write-Host "Toolchain ready: $exe"
& $exe --version
