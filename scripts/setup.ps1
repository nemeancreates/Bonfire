# One-shot dev setup, safe to re-run: fetches libraries into Libs\, luacheck into
# .tools\bin, and links the addon into the WoW: Forever beta AddOns folder.
param(
  [string]$WowDir = "C:\Program Files (x86)\World of Warcraft\_classic_beta_",
  [switch]$Update  # pull the latest library sources first
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root '.tools\src'
$bin = Join-Path $root '.tools\bin'
$libs = Join-Path $root 'Libs'

$repos = [ordered]@{
  Ace3          = 'https://github.com/WoWUIDev/Ace3.git'
  HereBeDragons = 'https://github.com/Nevcairiel/HereBeDragons.git'
}
# Libs\<folder> <- .tools\src\<path>; keep in sync with embeds.xml and .pkgmeta.
$wanted = [ordered]@{
  'LibStub'             = 'Ace3\LibStub'
  'CallbackHandler-1.0' = 'Ace3\CallbackHandler-1.0'
  'AceAddon-3.0'        = 'Ace3\AceAddon-3.0'
  'AceEvent-3.0'        = 'Ace3\AceEvent-3.0'
  'AceTimer-3.0'        = 'Ace3\AceTimer-3.0'
  'AceConsole-3.0'      = 'Ace3\AceConsole-3.0'
  'AceDB-3.0'           = 'Ace3\AceDB-3.0'
  'AceSerializer-3.0'   = 'Ace3\AceSerializer-3.0'
  'AceComm-3.0'         = 'Ace3\AceComm-3.0'
  'HereBeDragons'       = 'HereBeDragons'
}

New-Item -ItemType Directory -Force $src, $bin | Out-Null
foreach ($name in $repos.Keys) {
  $dir = Join-Path $src $name
  if (-not (Test-Path $dir)) { git clone --depth 1 -q $repos[$name] $dir }
  elseif ($Update) { git -C $dir pull --ff-only -q }
  if ($LASTEXITCODE) { throw "git failed for $name" }
}

if (Test-Path $libs) { Remove-Item $libs -Recurse -Force }
foreach ($name in $wanted.Keys) {
  $to = Join-Path $libs $name
  New-Item -ItemType Directory -Force $to | Out-Null
  Get-ChildItem (Join-Path $src $wanted[$name]) -File |
    Where-Object { $_.Extension -in '.lua', '.xml' } |
    Copy-Item -Destination $to
}
Write-Host "Libs ready."

$luacheck = Join-Path $bin 'luacheck.exe'
if (-not (Test-Path $luacheck)) {
  Invoke-WebRequest 'https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe' -OutFile $luacheck
}
Write-Host "luacheck ready."

if (-not (Get-Command luajit -ErrorAction SilentlyContinue) -and
    -not (Test-Path "$env:LOCALAPPDATA\Programs\LuaJIT\bin\luajit.exe")) {
  Write-Warning "LuaJIT not found (needed for tests): winget install DEVCOM.LuaJIT"
}

$addons = Join-Path $WowDir 'Interface\AddOns'
$link = Join-Path $addons 'Bonfire'
if (-not (Test-Path $addons)) {
  Write-Warning "AddOns folder not found: $addons (pass -WowDir)"
} elseif ($item = Get-Item $link -ErrorAction SilentlyContinue) {
  if ($item.LinkType -eq 'Junction') { Write-Host "AddOns link ready." }
  else { Write-Warning "$link exists and isn't a junction; left it alone." }
} else {
  New-Item -ItemType Junction -Path $link -Target $root | Out-Null
  Write-Host "Linked $link -> $root"
}
