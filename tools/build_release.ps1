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
    & $Godot --headless --path $Game "res://tests/runner.tscn" -- "--results=$res" "--max-seconds=900" | Select-String -Pattern "FAIL|====" | ForEach-Object { $_.Line }
    if ($LASTEXITCODE -ne 0) { throw "Tests failed (exit $LASTEXITCODE). See $res" }
}

Write-Host "== Exporting =="
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null
& $Godot --headless --path $Game --export-release "Windows Desktop" (Join-Path $Out "Hollowhaven.exe")
if (-not (Test-Path (Join-Path $Out "Hollowhaven.exe"))) { throw "Export failed" }

Write-Host "== Player docs & licences =="
Copy-Item (Join-Path $Root "docs\player\How to Play.txt") $Out
$lic = Join-Path $Out "Licenses"
New-Item -ItemType Directory -Force $lic | Out-Null
Copy-Item (Join-Path $Root "THIRD_PARTY_NOTICES.md") (Join-Path $lic "THIRD_PARTY_NOTICES.txt")
Copy-Item (Join-Path $Game "assets\fonts\OFL-Fredoka.txt") $lic
Copy-Item (Join-Path $Game "assets\fonts\OFL-Nunito.txt") $lic
& $Godot --headless --path $Game -s "res://tests/tools/dump_licenses.gd" -- "--out=$(Join-Path $lic 'Godot_Engine_Licenses.txt')" | Out-Null

Write-Host "== Zipping =="
New-Item -ItemType Directory -Force $Dist | Out-Null
$zip = Join-Path $Dist "Hollowhaven-$Version-Windows.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $Out -DestinationPath $zip -CompressionLevel Optimal
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Built $zip ($size MB) SHA256 $hash"
"$hash  $(Split-Path -Leaf $zip)" | Set-Content -Encoding ascii (Join-Path $Dist "SHA256SUMS.txt")
