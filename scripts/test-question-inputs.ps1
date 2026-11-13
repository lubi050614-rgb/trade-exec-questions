param([string]$DataDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'data\generated\execution-inputs-v1'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Need($condition,[string]$message){if(-not $condition){throw $message}}
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory 'manifest.json') | ConvertFrom-Json
$fileIndex=@{};foreach($f in $manifest.files){$fileIndex[$f.path]=$f}
$records=@(Get-Content -Encoding UTF8 (Join-Path $DataDirectory 'question-inputs.jsonl') | ForEach-Object {$_ | ConvertFrom-Json})
Need ($records.Count -eq 1150 -and @($records.question_id | Select-Object -Unique).Count -eq 1150) 'Question binding coverage mismatch'
Need (@($records.node_key | Select-Object -Unique).Count -eq 115) 'Node input coverage mismatch'
function Test-Binding($r){
    Need ($r.source_class -eq 'synthetic_test_only' -and $r.synthetic_input_ready -eq $true -and $r.real_dataset_ready -eq $false -and $r.real_calibration_ready -eq $false) 'False fidelity claim'
    foreach($field in @('answer','expected_output','solution')){Need ($null -eq $r.PSObject.Properties[$field]) 'Answer field in question input index'}
    Need ($r.input_files.Count -gt 0 -and $r.case_file -match '^cases/P\d{2}-S\d{2}\.json$') 'Missing input case'
    $casePath=Join-Path $DataDirectory $r.case_file
    Need ((Test-Path -LiteralPath $casePath) -and (Get-FileHash -LiteralPath $casePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $r.case_sha256) 'Case checksum mismatch'
    foreach($f in $r.input_files){
        Need ($f.path -notmatch '_internal|\.\.' -and $fileIndex.ContainsKey($f.path)) 'Private or unknown input path'
        Need ($f.sha256 -eq $fileIndex[$f.path].sha256) 'Input manifest mismatch'
    }
    if($r.node_key -in @('P02-S02','P02-S04')){Need ('synthetic/models/execution-parameters.jsonl' -notin $r.input_files.path) 'Inference target parameter leaked into its input'}
}
foreach($r in $records){Test-Binding $r}
$negative=0
foreach($kind in @('answer','private','false_real_ready')){
    $copy=$records[0] | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json
    switch($kind){
        'answer' {$copy | Add-Member -NotePropertyName answer -NotePropertyValue 'not allowed'}
        'private' {$copy.input_files[0].path='_internal/state-digest.jsonl'}
        'false_real_ready' {$copy.real_dataset_ready=$true}
    }
    $rejected=$false;try{Test-Binding $copy}catch{$rejected=$true};Need $rejected "Accepted negative binding: $kind";$negative++
}
$reader=Join-Path $root 'scripts\read-question-input.ps1'
$sampleText=& powershell -NoProfile -ExecutionPolicy Bypass -File $reader -QuestionId P09-S01-Q01 -DataDirectory $DataDirectory -MaxRowsPerFile 2 -AsOf '2026-11-02T09:45:00+08:00'
Need ($LASTEXITCODE -eq 0) 'As-of reader failed'
$sample=($sampleText -join "`n") | ConvertFrom-Json
$feature=@($sample.data | Where-Object path -eq 'synthetic/market/qinml_l2_features_30m_v1.jsonl')
Need ($feature.Count -eq 1 -and $feature[0].rows.Count -eq 0) 'Future 30-minute feature leaked before 10:00'
$dailyText=& powershell -NoProfile -ExecutionPolicy Bypass -File $reader -QuestionId P03-S03-Q01 -DataDirectory $DataDirectory -MaxRowsPerFile 1 -AsOf '2026-11-02T09:45:00+08:00'
Need ($LASTEXITCODE -eq 0) 'Daily visibility reader failed'
$daily=($dailyText -join "`n") | ConvertFrom-Json
$dailyRows=@($daily.data | Where-Object path -eq 'synthetic/market/rq_stock_bar_1d_local.jsonl')
Need ($dailyRows.Count -eq 1 -and $dailyRows[0].rows.Count -eq 0) 'Future daily close leaked at 09:45'
$specialText=& powershell -NoProfile -ExecutionPolicy Bypass -File $reader -QuestionId P13-S01-Q04 -DataDirectory $DataDirectory -MaxRowsPerFile 2
Need ($LASTEXITCODE -eq 0) 'Special-case reader failed'
$special=($specialText -join "`n") | ConvertFrom-Json
$pcf=@($special.data | Where-Object path -eq 'synthetic/special/pcf.jsonl')
Need ($pcf.Count -eq 1 -and $pcf[0].rows.Count -gt 0 -and @($pcf[0].rows | Where-Object variant -ne 'missing_evidence').Count -eq 0) 'Scenario variants were mixed'
$result=[ordered]@{result='passed';questions=1150;nodes=115;input_paths='public_and_resolved';case_hashes='matched';no_answer_fields=$true;inference_parameter_leakage='blocked_by_file_selection';future_feature_gate='passed';future_daily_gate='passed';negative_bindings_rejected=$negative;real_dataset_ready=$false;exact_node_fault_ready=0}
[System.IO.File]::WriteAllText((Join-Path $root 'deliverables\input-binding-validation.json'),($result | ConvertTo-Json -Depth 8),(New-Object System.Text.UTF8Encoding($false)))
$result | ConvertTo-Json
