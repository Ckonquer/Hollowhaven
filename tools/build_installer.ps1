<#
  build_installer.ps1 - builds the Windows installer dist\Hollowhaven-Setup-<version>.exe from the release build.
    1. checks builds\Hollowhaven\Hollowhaven.exe exists and its file version matches game\project.godot config/version,
       and that builds\Hollowhaven still holds exactly the files of dist\Hollowhaven-<version>-Windows.zip (SHA-256)
    2. moves an older dist\Hollowhaven-Setup-*.exe to builds\superseded\ (not deleted), like build_release.ps1 does with zips
    3. compiles tools\installer\hollowhaven.iss with the Inno Setup 6 command-line compiler (ISCC.exe, quiet)
    4. prints the installer's path, size and SHA-256 and adds/replaces its line in dist\SHA256SUMS.txt (the zip's line is kept)
  Run it AFTER tools\build_release.ps1 (that script rebuilds builds\Hollowhaven and rewrites SHA256SUMS.txt with the zip only).
  Usage:  powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1 [-Iscc <path to ISCC.exe>]
  Exits non-zero on any failure. See docs\INSTALLER.md.
#>
param([string]$Iscc = "")
$ErrorActionPreference = "Stop"

function Normalize-Version([string]$v) {
    $parts = @($v.Split('.') | ForEach-Object { [int]$_ })
    while ($parts.Count -lt 4) { $parts += 0 }
    return ($parts[0..3] -join '.')
}

try {
    $Root = Split-Path -Parent $PSScriptRoot
    $Script = Join-Path $Root "tools\installer\hollowhaven.iss"
    $Build = Join-Path $Root "builds\Hollowhaven"
    $Exe = Join-Path $Build "Hollowhaven.exe"
    $Dist = Join-Path $Root "dist"
    $Superseded = Join-Path $Root "builds\superseded"

    # --- Inno Setup compiler ---
    if (-not $Iscc) {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
            (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
        )
        $Iscc = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    if (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc)) { throw "Inno Setup 6 command-line compiler (ISCC.exe) not found. Pass -Iscc <path>." }

    # --- Version ---
    $Version = (Select-String -Path (Join-Path $Root "game\project.godot") -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
    if ($Version -notmatch '^\d+(\.\d+){0,3}$') { throw "config/version '$Version' is not a plain x.y.z version (the Windows version resource needs numbers only)" }
    Write-Host "== Hollowhaven $Version installer =="

    # --- The release build must exist and be this version ---
    if (-not (Test-Path -LiteralPath $Exe)) { throw "$Exe not found - run tools\build_release.ps1 first" }
    $fv = (Get-Item -LiteralPath $Exe).VersionInfo
    $exeVersion = "{0}.{1}.{2}.{3}" -f $fv.FileMajorPart, $fv.FileMinorPart, $fv.FileBuildPart, $fv.FilePrivatePart
    if ($exeVersion -ne (Normalize-Version $Version)) {
        throw "builds\Hollowhaven\Hollowhaven.exe has file version $exeVersion but game\project.godot says $Version - rebuild with tools\build_release.ps1"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Build "How to Play.txt"))) { throw "builds\Hollowhaven\How to Play.txt is missing (the Start Menu shortcut points to it)" }
    $files = @(Get-ChildItem -LiteralPath $Build -Recurse -File)
    Write-Host ("Source: builds\Hollowhaven ({0} files, {1:N1} MB), exe file version {2}" -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB), $exeVersion)

    # --- builds\Hollowhaven must still be exactly what the release zip of this version ships ---
    # The folder is used after the release build (QA runs start the exe from it, QA copies hard-link to it), so anything
    # added or changed there since - an override.cfg (Godot reads it from the exe's folder and it would change how her
    # game window behaves), a log, a patched exe - must not end up in the installer. Same names, same SHA-256.
    $Zip = Join-Path $Dist "Hollowhaven-$Version-Windows.zip"
    if (-not (Test-Path -LiteralPath $Zip)) { throw "$Zip not found - run tools\build_release.ps1 first (the installer must ship what the release zip ships)" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $za = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $zipHash = @{}
        foreach ($e in $za.Entries) {
            $rel = $e.FullName.Replace('/', '\')
            if ($rel.EndsWith('\')) { continue }   # folder entry
            if ($rel.StartsWith('Hollowhaven\', [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring(12) }
            $s = $e.Open()
            try { $zipHash[$rel] = [BitConverter]::ToString($sha.ComputeHash($s)).Replace('-', '') } finally { $s.Dispose() }
        }
    } finally { $za.Dispose() }
    $problems = @()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Build.Length).TrimStart('\')
        if (-not $zipHash.ContainsKey($rel)) { $problems += "not in the zip: $rel"; continue }
        if ((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ne $zipHash[$rel]) { $problems += "differs from the zip: $rel" }
        $zipHash.Remove($rel)
    }
    foreach ($k in $zipHash.Keys) { $problems += "missing from builds\Hollowhaven: $k" }
    if ($problems.Count -gt 0) {
        throw ("builds\Hollowhaven is not what $(Split-Path -Leaf $Zip) ships (" + ($problems -join '; ') + ") - rebuild with tools\build_release.ps1")
    }
    Write-Host "builds\Hollowhaven matches $(Split-Path -Leaf $Zip) file for file (SHA-256)"

    # --- dist\ holds only the current installer: move older ones aside (not deleted) ---
    New-Item -ItemType Directory -Force $Dist | Out-Null
    $Name = "Hollowhaven-Setup-$Version.exe"
    $Setup = Join-Path $Dist $Name
    $old = @(Get-ChildItem -LiteralPath $Dist -Filter 'Hollowhaven-Setup-*.exe' | Where-Object { $_.Name -ne $Name })
    foreach ($o in $old) {
        New-Item -ItemType Directory -Force $Superseded | Out-Null
        Move-Item -Force -LiteralPath $o.FullName -Destination (Join-Path $Superseded $o.Name)
        Write-Host "Moved superseded $($o.Name) to builds\superseded\"
    }

    # --- Compile ---
    Write-Host "== Compiling (ISCC, lzma2/ultra64 solid - about a minute) =="
    $started = Get-Date
    & $Iscc /Q "/DAppVersion=$Version" "/DAppVersionNumeric=$Version" $Script
    if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $Setup)) { throw "ISCC reported success but $Setup does not exist" }
    $item = Get-Item -LiteralPath $Setup
    if ($item.LastWriteTime -lt $started.AddSeconds(-5)) { throw "$Setup was not rewritten by this build" }
    $sv = $item.VersionInfo
    $setupVersion = "{0}.{1}.{2}.{3}" -f $sv.FileMajorPart, $sv.FileMinorPart, $sv.FileBuildPart, $sv.FilePrivatePart
    if ($setupVersion -ne (Normalize-Version $Version)) { throw "Installer file version is $setupVersion, expected $(Normalize-Version $Version)" }

    # --- Report + checksum list ---
    $hash = (Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash
    $size = [math]::Round($item.Length / 1MB, 1)
    $sums = Join-Path $Dist "SHA256SUMS.txt"
    $keep = @()
    if (Test-Path -LiteralPath $sums) {
        # keep every other line (the zip's), drop any installer line - older installers are no longer in dist\
        # ("<hash>  name" as written here and by build_release.ps1, or sha256sum's binary-mode "<hash> *name")
        $keep = @(Get-Content -LiteralPath $sums | Where-Object { $_.Trim() -ne "" -and $_ -notmatch '\s\*?Hollowhaven-Setup-[^\s]*\.exe\s*$' })
    }
    ($keep + "$hash  $Name") | Set-Content -Encoding ascii -LiteralPath $sums
    $secs = [int]((Get-Date) - $started).TotalSeconds
    Write-Host "Built $Setup ($size MB, $($item.Length) bytes, ${secs}s) SHA256 $hash"
    Write-Host "Updated dist\SHA256SUMS.txt:"
    Get-Content -LiteralPath $sums | ForEach-Object { Write-Host "  $_" }
    exit 0
}
catch {
    Write-Host "build_installer.ps1 FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
