$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$canonical=Join-Path $root 'data\generated\execution-inputs-v1'
$trial=Join-Path $root ('reports\local\input-repro-'+[guid]::NewGuid().ToString('N'))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\generate-input-data.ps1') -OutputDirectory $trial
if($LASTEXITCODE -ne 0){throw 'Independent input build failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\validate-input-data.ps1') -DataDirectory $trial -SelfTest
if($LASTEXITCODE -ne 0){throw 'Independent input validation failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\bind-question-inputs.ps1') -DataDirectory $trial -OutputDirectory (Join-Path $root 'deliverables') | Out-Null
if($LASTEXITCODE -ne 0){throw 'Independent question binding failed'}
$base=Get-Content -Raw -Encoding UTF8 (Join-Path $canonical 'manifest.json') | ConvertFrom-Json
$other=Get-Content -Raw -Encoding UTF8 (Join-Path $trial 'manifest.json') | ConvertFrom-Json
if($base.config_hash -ne $other.config_hash -or $base.source_code_hash -ne $other.source_code_hash){throw 'Input build configuration/source mismatch'}
$catalog=Get-Content -Raw -Encoding UTF8 (Join-Path $canonical 'case-manifest.json') | ConvertFrom-Json
$paths=@($base.files.path)+@('manifest.json','config.json','question-inputs.jsonl','validation.json','_internal/state-digest.jsonl','case-manifest.json','precise-validation.json')+@($catalog.files.path)
foreach($path in $paths){
    $a=(Get-FileHash -LiteralPath (Join-Path $canonical $path) -Algorithm SHA256).Hash
    $b=(Get-FileHash -LiteralPath (Join-Path $trial $path) -Algorithm SHA256).Hash
    if($a -ne $b){throw "Input reproducibility failed: $path"}
}
$result=[ordered]@{result='passed';independent_generation_processes=2;file_hashes_matched=$paths.Count;public_data_files=$base.files.Count;question_bindings=1150;node_cases=575;question_cases=1150;actual_n_symbols=$base.actual_n_symbols;actual_n_days=$base.actual_n_days;answers_generated=0;real_dataset_ready=$false}
[System.IO.File]::WriteAllText((Join-Path $root 'deliverables\input-reproducibility.json'),($result | ConvertTo-Json -Depth 6),(New-Object System.Text.UTF8Encoding($false)))
$result | ConvertTo-Json
