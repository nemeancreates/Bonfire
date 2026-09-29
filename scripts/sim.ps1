# Plays thousands of Odd Man Out games and prints how they go (tests\sim.lua).
$root = Split-Path $PSScriptRoot -Parent
$luajit = (Get-Command luajit -ErrorAction SilentlyContinue).Source
if (-not $luajit) { $luajit = "$env:LOCALAPPDATA\Programs\LuaJIT\bin\luajit.exe" }
Push-Location $root
try { & $luajit tests/sim.lua; $code = $LASTEXITCODE }
finally { Pop-Location }
exit $code
