$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$staging=Join-Path $root ('reports\local\package-v2-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
foreach($name in @('deliverables','openspec','config','data\schema','scripts','src')) {
    $target=Join-Path $staging (Split-Path $name -Parent)
    if(-not(Test-Path -LiteralPath $target)){New-Item -ItemType Directory -Force -Path $target | Out-Null}
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $target -Recurse -Force
}
foreach($name in @('README.md','AGENTS.md','build-deliverables.ps1','execution-source.json','question-seeds.txt','.gitignore')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $staging -Force
}
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath (Join-Path $root '交易执行_题库与数据方案.zip') -Force
Write-Output 'Packaged deliverables, OpenSpec, contracts, schema and build/validation scripts; no CLI binary, private or generated data.'
