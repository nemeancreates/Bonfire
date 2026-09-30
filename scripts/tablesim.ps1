# Plays full games through the real Table.lua against a fake clock (tests\table_sim.lua).
$root = Split-Path $PSScriptRoot -Parent
$luajit = (Get-Command luajit -ErrorAction SilentlyContinue).Source
if (-not $luajit) { $luajit = "$env:LOCALAPPDATA\Programs\LuaJIT\bin\luajit.exe" }
Push-Location $root
try { & $luajit tests/table_sim.lua; $code = $LASTEXITCODE }
finally { Pop-Location }
exit $code
