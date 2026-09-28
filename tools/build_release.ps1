<#
  build_release.ps1 - builds the playable Windows release and the ZIP.
    1. imports assets   2. runs the automated tests (skip with -SkipTests)
    3. exports builds/Hollowhaven/Hollowhaven.exe (release template, PCK embedded)
    4. adds player docs + licences   5. zips to dist/Hollowhaven-<version>-Windows.zip
  Usage:  powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 [-SkipTests]
#>
param([switch]$SkipTests)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $Root ".tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$Game = Join-Path $Root "game"
if (-not (Test-Path $Godot)) { throw "Godot not found. Run tools\setup_toolchain.ps1 first." }
$Version = (Select-String -Path (Join-Path $Game "project.godot") -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
$Out = Join-Path $Root "builds\Hollowhaven"
$Dist = Join-Path $Root "dist"

Write-Host "== Hollowhaven $Version release build =="
& $Godot --headless --path $Game --import | Out-Null

if (-not $SkipTests) {
    Write-Host "== Running tests =="
    $res = Join-Path $Root "qa\tmp\test_results_release.json"
    & $Godot --headless --path $Game "res://tests/runner.tscn" -- "--results=$res" "--max-seconds=2400" | Select-String -Pattern "FAIL|====" | ForEach-Object { $_.Line }
    if ($LASTEXITCODE -ne 0) { throw "Tests failed (exit $LASTEXITCODE). See $res" }
}

Write-Host "== Exporting =="
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null
$Exe = Join-Path $Out "Hollowhaven.exe"
& $Godot --headless --path $Game --export-release "Windows Desktop" $Exe
if ($LASTEXITCODE -ne 0) { throw "Export failed (Godot exit $LASTEXITCODE)" }
if (-not (Test-Path $Exe)) { throw "Export failed (no $Exe)" }
# The game data is embedded in the exe (embed_pck): a failed pack step can leave a bare template that
# still "exists". The real export is the template plus ~40 MB of game data.
$Template = Join-Path $Root ".tools\godot\editor_data\export_templates\4.7.2.stable\windows_release_x86_64.exe"
if (Test-Path $Template) {
    $minBytes = (Get-Item $Template).Length + 5MB
    if ((Get-Item $Exe).Length -lt $minBytes) { throw "Export looks incomplete: $Exe is not larger than the bare export template" }
}

Write-Host "== Player docs & licences =="
Copy-Item (Join-Path $Root "docs\player\How to Play.txt") $Out
$lic = Join-Path $Out "Licenses"
New-Item -ItemType Directory -Force $lic | Out-Null
Copy-Item (Join-Path $Root "THIRD_PARTY_NOTICES.md") (Join-Path $lic "THIRD_PARTY_NOTICES.txt")
Copy-Item (Join-Path $Game "assets\fonts\OFL-Fredoka.txt") $lic
Copy-Item (Join-Path $Game "assets\fonts\OFL-Nunito.txt") $lic
$licFile = Join-Path $lic 'Godot_Engine_Licenses.txt'
& $Godot --headless --path $Game -s "res://tests/tools/dump_licenses.gd" -- "--out=$licFile" | Out-Null
if (-not (Test-Path $licFile)) { throw "Could not write the Godot licence file ($licFile)" }

Write-Host "== Zipping =="
New-Item -ItemType Directory -Force $Dist | Out-Null
$zip = Join-Path $Dist "Hollowhaven-$Version-Windows.zip"
if (Test-Path $zip) { Remove-Item $zip }
# dist/ must only ever hold the current build: move zips of older versions aside (not deleted) so
# nobody extracts a superseded build by mistake.
$Superseded = Join-Path $Root "builds\superseded"
$old = @(Get-ChildItem -Path $Dist -Filter 'Hollowhaven-*-Windows.zip' | Where-Object { $_.Name -ne (Split-Path -Leaf $zip) })
if ($old.Count -gt 0) {
    New-Item -ItemType Directory -Force $Superseded | Out-Null
    foreach ($o in $old) {
        Move-Item -Force $o.FullName (Join-Path $Superseded $o.Name)
        Write-Host "Moved superseded $($o.Name) to builds\superseded\"
    }
}
Compress-Archive -Path $Out -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Built $zip ($size MB) SHA256 $hash"
"$hash  $(Split-Path -Leaf $zip)" | Set-Content -Encoding ascii (Join-Path $Dist "SHA256SUMS.txt")
