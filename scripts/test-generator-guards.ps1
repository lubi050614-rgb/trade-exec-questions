$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$base=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config\input-generation.json') | ConvertFrom-Json
$work=Join-Path $root ('reports\local\guard-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8=New-Object System.Text.UTF8Encoding($false)
$rejected=0
foreach($kind in @('answer_export','real_claim','wrong_units','unknown_field','unmarked_overwrite','too_small_universe','id_namespace_overflow')){
    $c=$base | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    switch($kind){
        'answer_export' {$c.export_answers=$true}
        'real_claim' {$c.allow_real_market_claims=$true}
        'wrong_units' {$c.volume_unit='hands_without_conversion'}
        'unknown_field' {$c | Add-Member -NotePropertyName unsupported_setting -NotePropertyValue 1}
        'too_small_universe' {$c.symbol_count=1}
        'id_namespace_overflow' {$c.symbol_count=1001}
    }
    $path=Join-Path $work ($kind+'.json')
    [System.IO.File]::WriteAllText($path,($c | ConvertTo-Json -Depth 8),$utf8)
    $target=Join-Path $work ($kind+'-output')
    $extra=@()
    if($kind -eq 'unmarked_overwrite'){New-Item -ItemType Directory -Force -Path $target | Out-Null;$extra=@('-Overwrite')}
    $savedPreference=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\generate-input-data.ps1') -ConfigPath $path -OutputDirectory $target @extra *> (Join-Path $work ($kind+'.txt'))
        $exitCode=$LASTEXITCODE
    }finally{$ErrorActionPreference=$savedPreference}
    if($exitCode -eq 0){throw "Generator accepted forbidden configuration: $kind"}
    if(Test-Path -LiteralPath (Join-Path $target 'manifest.json')){throw 'Invalid configuration wrote a dataset manifest'}
    $rejected++
}
$result=[ordered]@{result='passed';negative_configurations_rejected=$rejected;cases=@('answer_export','real_market_claim','ambiguous_units','unknown_field','overwrite_without_generator_marker','missing_scenario_universe','order_id_namespace_overflow');answers_generated=0}
[System.IO.File]::WriteAllText((Join-Path $root 'deliverables\input-generator-guards.json'),($result | ConvertTo-Json -Depth 6),$utf8)
$result | ConvertTo-Json
