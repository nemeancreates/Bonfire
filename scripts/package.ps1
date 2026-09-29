# Builds dist\Bonfire-<version>.zip: the addon folder with libraries included, without
# dev files, ready to unzip into Interface\AddOns. Fetches libraries first if missing.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root 'Libs'))) { & (Join-Path $PSScriptRoot 'setup.ps1') }

$version = (Select-String -Path (Join-Path $root 'Bonfire.toc') -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'Bonfire'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

Copy-Item (Join-Path $root '*.lua'), (Join-Path $root 'Bonfire.toc'), (Join-Path $root 'embeds.xml'), (Join-Path $root 'README.md') $stage
Copy-Item (Join-Path $root 'Games'), (Join-Path $root 'Libs') $stage -Recurse

$zip = Join-Path $dist "Bonfire-$version.zip"
Compress-Archive -Path $stage -DestinationPath $zip
Write-Host "Built $zip"
Get-ChildItem $stage -Recurse -File | Measure-Object | ForEach-Object { Write-Host "$($_.Count) files" }
