param(
    [string]$DataDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data\generated\execution-inputs-v1'),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'deliverables')
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$utf8=New-Object System.Text.UTF8Encoding($false)
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory 'manifest.json') | ConvertFrom-Json
$validationPath=Join-Path $DataDirectory 'validation.json'
if(-not(Test-Path -LiteralPath $validationPath)){throw 'Validate the generated dataset before binding questions'}
$validation=Get-Content -Raw -Encoding UTF8 $validationPath | ConvertFrom-Json
if($validation.result -ne 'passed'){throw 'Input validation has not passed'}
if($manifest.actual_n_symbols -lt 200 -or $manifest.actual_n_days -ne 5){throw 'Production question bindings require at least 200 symbols and exactly five test dates'}
$files=@{};foreach($f in $manifest.files){$files[$f.path]=$f}
$gapFiles=@{
    D01=@('synthetic/business/target_holdings.jsonl','synthetic/business/parents.jsonl','synthetic/business/client_requests.jsonl')
    D02=@('synthetic/business/client_requests.jsonl','synthetic/business/observations.jsonl','synthetic/business/broker_queries.jsonl','synthetic/business/decision_quotes.jsonl')
    D03=@('synthetic/business/initial_balances.jsonl','synthetic/business/initial_positions.jsonl','synthetic/business/ledger-flows.jsonl','synthetic/business/settlement_flows.jsonl')
    D04=@('synthetic/rules/rule-pack.jsonl','synthetic/rules/sessions.jsonl')
    D05=@('synthetic/protocol/capabilities.jsonl','synthetic/protocol/error-codes.jsonl','synthetic/protocol/fix-messages.jsonl','synthetic/protocol/datagrams.jsonl')
    D06=@('synthetic/system/telemetry.jsonl','synthetic/system/build-profile.jsonl','synthetic/system/fpga-vectors.jsonl')
    D07=@('synthetic/events/auction.jsonl','synthetic/events/announcements.jsonl')
    D08=@('synthetic/special/derivatives.jsonl','synthetic/special/derivative-sessions.jsonl')
    D09=@('synthetic/special/overseas-crypto.jsonl')
    D10=@('synthetic/models/evidence-status.jsonl','synthetic/market/wind_book_quality_local.jsonl')
    D11=@('synthetic/special/pcf.jsonl','synthetic/special/etf-events.jsonl')
    D12=@('synthetic/special/block-trades.jsonl')
}
$nodes=Get-Content -Raw -Encoding UTF8 (Join-Path $OutputDirectory '节点数据契约.json') | ConvertFrom-Json
$questions=@(Get-Content -Encoding UTF8 (Join-Path $OutputDirectory '交易执行_教师输入.jsonl') | ForEach-Object {$_ | ConvertFrom-Json})
$nodeIndex=@{};foreach($n in $nodes){$nodeIndex[$n.node_key]=$n}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/generate-precise-cases.ps1') -DataDirectory $DataDirectory -OutputDirectory $OutputDirectory | Out-Null
if($LASTEXITCODE -ne 0){throw 'Precise case generation failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/validate-precise-inputs.ps1') -DataDirectory $DataDirectory -OutputDirectory $OutputDirectory -SelfTest | Out-Null
if($LASTEXITCODE -ne 0){throw 'Independent precise case validation failed'}
$caseManifest=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory 'case-manifest.json') | ConvertFrom-Json
$caseIndex=@{};foreach($file in $caseManifest.files){$caseIndex[$file.path]=$file}
$precise=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory 'precise-validation.json') | ConvertFrom-Json
$semanticIndex=@{};foreach($row in $precise.nodes_detail){$semanticIndex[$row.node_key]=$row}
$scenarioIndex=@{};foreach($line in Get-Content -Encoding UTF8 (Join-Path $root 'config/question-scenario-selection.jsonl')){$selection=$line | ConvertFrom-Json;if($scenarioIndex.ContainsKey($selection.question_id)){throw 'Duplicate question scenario selection'};$scenarioIndex[$selection.question_id]=$selection}
if($scenarioIndex.Count -ne $questions.Count){throw 'Explicit scenario selection coverage mismatch'}
$bindings=New-Object System.Collections.Generic.List[string]
$csv=New-Object System.Collections.Generic.List[object]
foreach($q in $questions){
    $key=$q.split_group_id;$n=$nodeIndex[$key]
    if(-not $scenarioIndex.ContainsKey($q.question_id)){throw 'Missing explicit question scenario selection'}
    $selection=$scenarioIndex[$q.question_id];$specialVariants=@($selection.special_variants)
    foreach($variant in $specialVariants){if($variant -notin @('normal','partial_failure','recovery','missing_evidence')){throw 'Unknown explicit scenario variant'}}
    $paths=New-Object System.Collections.Generic.List[string]
    foreach($table in $q.related_tables){$paths.Add('synthetic/market/'+$table+'.jsonl')}
    foreach($gap in $q.missing_data_ids){foreach($path in $gapFiles[$gap]){$paths.Add($path)}}
    if($key -in @('P01-S03','P01-S05','P01-S06','P03-S08','P09-S02')){$paths.Add('synthetic/models/volume-profile.jsonl')}
    if($key -in @('P01-S06','P02-S03','P02-S06')){$paths.Add('synthetic/models/execution-parameters.jsonl')}
    if($paths.Count -eq 0){$paths.Add('synthetic/business/parents.jsonl')}
    $refs=foreach($path in ($paths | Select-Object -Unique)){
        if(-not $files.ContainsKey($path)){throw "Missing actual input file: $path"}
        $f=$files[$path]
        if('variant' -in $f.columns -and $specialVariants.Count -eq 0){continue}
        if($f.table_schema){foreach($field in $q.minimum_real_fields.($f.table_schema)){if($field -notin $f.columns){throw "Input lacks field: $($f.table_schema).$field"}}}
        $exclude=@()
        if($key -in @('P02-S02','P02-S04') -and $path -eq 'synthetic/models/execution-parameters.jsonl'){$exclude=@('impact_Y','temporary_eta','permanent_gamma','risk_lambda')}
        [ordered]@{path=$path;sha256=$f.sha256;rows=$f.rows;namespace='synthetic';fidelity=$f.fidelity;availability=$f.availability;exclude_fields=$exclude}
    }
    $casePath='cases/questions/'+$q.question_id+'.json'
    $questionNumber=[int]$q.question_id.Substring($q.question_id.Length-2)
    $record=[ordered]@{schema_version='2.0';question_id=$q.question_id;node_key=$key;node_name=$q.node_name;question_type=$q.question_type;question=$q.question;source_class='synthetic_test_only';case_file=$casePath;case_sha256=(Get-FileHash -LiteralPath (Join-Path $DataDirectory $casePath) -Algorithm SHA256).Hash.ToLowerInvariant();input_files=@($refs);filters=[ordered]@{symbols='all_manifest_symbols';dates='all_manifest_dates';special_variants=@($specialVariants)};visibility_policy='At each decision use rows whose declared available_at <= decision time; full-window loading is for offline iteration only';synthetic_input_ready=$true;input_support_scope='question_specific_synthetic_inputs_semantic_status_per_node';semantic_status=$semanticIndex[$key].semantic_status;exact_node_fault_implemented=$semanticIndex[$key].exact_node_fault_implemented;real_dataset_ready=$false;real_calibration_ready=$false;task_refs=$q.task_refs;minimum_real_fields=$q.minimum_real_fields;missing_real_data_ids=$q.missing_data_ids;read_command=('powershell -NoProfile -ExecutionPolicy Bypass -File scripts/read-question-input.ps1 -QuestionId '+$q.question_id+' -MetadataOnly')}
    $bindings.Add(($record | ConvertTo-Json -Depth 14 -Compress))
    $csv.Add([pscustomobject]@{question_id=$q.question_id;node_key=$key;node_name=$q.node_name;input_file_count=@($refs).Count;case_file=$casePath;source_class='synthetic_test_only';synthetic_input_ready=$true;semantic_status=$semanticIndex[$key].semantic_status;exact_node_fault_implemented=$semanticIndex[$key].exact_node_fault_implemented;real_dataset_ready=$false;input_paths=(@($refs.path) -join ';')})
}
if($bindings.Count -ne 1150){throw 'Question input coverage mismatch'}
[System.IO.File]::WriteAllLines((Join-Path $OutputDirectory '题目与数据输入.jsonl'),$bindings,$utf8)
[System.IO.File]::WriteAllLines((Join-Path $DataDirectory 'question-inputs.jsonl'),$bindings,$utf8)
$csv | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputDirectory '题目输入索引.csv')
$summary=[ordered]@{questions=$bindings.Count;nodes=$nodes.Count;synthetic_baseline_ready=1150;exact_node_fault_ready=10*@($precise.nodes_detail | Where-Object exact_node_fault_implemented).Count;exact_node_fault_ready_nodes=@($precise.nodes_detail | Where-Object exact_node_fault_implemented).Count;semantic_pending_nodes=$precise.semantic_pending_nodes;validation_schema_version=3;precise_question_cases=1150;precise_node_variants=575;precise_validation_result='passed';actual_n_symbols=$manifest.actual_n_symbols;actual_n_days=$manifest.actual_n_days;public_data_files=$manifest.files.Count;input_validation_result='passed';answers_generated=0;real_dataset_ready=$false;real_calibration_ready=$false;manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $DataDirectory 'manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();scope='questions_and_inputs_only';case_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $DataDirectory 'case-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();precise_validation_sha256=(Get-FileHash -LiteralPath (Join-Path $DataDirectory 'precise-validation.json') -Algorithm SHA256).Hash.ToLowerInvariant();limitations='All question projections and declared relations checked; raw-event semantic oracles verified only for nodes explicitly marked ready. Other node semantics remain pending review; real evidence unavailable.'}
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'input-coverage.json'),($summary | ConvertTo-Json -Depth 8),$utf8)
$summary | ConvertTo-Json
