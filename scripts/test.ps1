# Runs the offline rule/parser tests under LuaJIT (Lua 5.1, same as the game).
$root = Split-Path $PSScriptRoot -Parent
$luajit = (Get-Command luajit -ErrorAction SilentlyContinue).Source
if (-not $luajit) { $luajit = "$env:LOCALAPPDATA\Programs\LuaJIT\bin\luajit.exe" }
Push-Location $root
try { & $luajit tests/run.lua; $code = $LASTEXITCODE }
finally { Pop-Location }
exit $code
