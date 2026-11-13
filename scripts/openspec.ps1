$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools\openspec\openspec.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Run scripts/setup-openspec.ps1 first.' }
$env:OPENSPEC_TELEMETRY = '0'
Push-Location $root
try { & $exe @args; $code=$LASTEXITCODE } finally { Pop-Location }
exit $code
