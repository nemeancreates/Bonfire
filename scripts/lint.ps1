# Lints the addon's own Lua files (Libs\ and .tools\ are excluded in .luacheckrc).
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try { & (Join-Path $root '.tools\bin\luacheck.exe') . @args; $code = $LASTEXITCODE }
finally { Pop-Location }
exit $code
