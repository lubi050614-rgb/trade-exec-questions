param([string]$Version = 'v2.0.0')
$ErrorActionPreference='Stop'
if ($Version -notmatch '^v\d+\.\d+\.\d+$') { throw 'Version must be a release tag such as v2.0.0' }
$root=Split-Path $PSScriptRoot -Parent
$destination=Join-Path $root '.tools\openspec'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$asset='openspec-windows-x64.zip'
$base="https://github.com/Fission-AI/OpenSpec/releases/download/$Version/"
$archive=Join-Path $destination 'download.zip'
$checksums=Join-Path $destination 'SHA256SUMS'
Invoke-WebRequest -UseBasicParsing -Uri ($base+$asset) -OutFile $archive
Invoke-WebRequest -UseBasicParsing -Uri ($base+'SHA256SUMS') -OutFile $checksums
$entries=@(Get-Content $checksums | Where-Object { $_ -match ('\s+\*?'+[regex]::Escape($asset)+'$') })
if ($entries.Count -ne 1) { throw 'Expected one checksum entry' }
$expected=($entries[0] -split '\s+')[0].ToLowerInvariant()
$actual=(Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'OpenSpec SHA256 mismatch' }
Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force
& (Join-Path $destination 'openspec.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'OpenSpec executable check failed' }
Write-Output "Installed $Version in $destination; user PATH was not changed."
