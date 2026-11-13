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
$caseDirectory=Join-Path $DataDirectory 'cases'
New-Item -ItemType Directory -Force -Path $caseDirectory | Out-Null
foreach($n in $nodes){
    $fault=$n.failure_scenario
    $kind=switch -Regex ($fault){
        '双主|同时出单|所有权|两个.*控制器' {'fenced_sender';break}
        '重复' {'duplicate_delivery';break}
        '先.*ACK|先回调|乱序' {'out_of_order';break}
        '未知受理|超时|重试' {'unknown_acceptance';break}
        '撤单|撤改|释放|冻结' {'partial_then_cancel';break}
        '断|重连|恢复|切换' {'disconnect_recovery';break}
        '陈旧|旧盘口' {'stale_quote';break}
        '限频|流控|配额|速率|高峰' {'shared_rate_limit';break}
        '资金|余额|透支' {'insufficient_funds';break}
        default {'normal'}
    }
    $pi=[int]$n.node_key.Substring(1,2)
    $mini=switch($pi){
        1 {[ordered]@{case_id='isolated-small-planning-input';target_qty=1000;filled_qty=300;active_qty=200;cancel_requested_within_active_qty=100;qty_unit='shares';lot_size=100;budget_minor=5000000}}
        2 {[ordered]@{case_id='isolated-small-optimization-input';Q=1000;steps=5;eta=0.001;gamma=0.00001;sigma=0.02;lambda=$(if($n.node_key -eq 'P02-S04'){$null}else{0.01});calibration_evidence='not_provided';parameter_role='assumptions_for_controls_not_market_truth'}}
        3 {[ordered]@{case_id='isolated-small-tca-input';target_qty=1000;side='buy';decision_price_ticks=2000;arrival_price_ticks=2001;fills=@(@{qty=200;price_ticks=2002;fee_minor=50},@{qty=400;price_ticks=2003;fee_minor=50});terminal_price_ticks=2005;price_divisor=100}}
        4 {[ordered]@{case_id='isolated-small-gateway-input';logical_order_id='ORDER-SMALL-1';qty=500;request_timeout_ms=100;query_visible_after_ms=500;duplicate_request_id='REQ-SMALL-1';test_only_api=$true}}
        5 {[ordered]@{case_id='isolated-small-system-input';queue_capacity=1024;burst_messages=2048;cpu_target='x86-64-baseline';price_width=32;qty_width=32;clock_domains=@('simulated_monotonic','simulated_ptp');hardware_measurements_available=$false}}
        6 {[ordered]@{case_id='isolated-small-risk-input';cash_available_minor=1000000;cash_frozen_minor=200000;qty_total=1000;qty_sellable=600;qty_frozen=100;qty_today_buy=300;quote_age_ms=1500;max_quote_age_ms=1000;kill_requested=$true}}
        7 {[ordered]@{case_id='isolated-small-book-input';bid_ticks=1999;bid_depth=1000;ask_ticks=2001;ask_depth=1000;own_qty=100;assumed_queue_ahead=500;events=@(@{type='cancel_ahead';qty=100},@{type='trade_at_own_price';qty=200});queue_position_observed=$false}}
        8 {[ordered]@{case_id='isolated-small-preopen-input';test_only=$true;request_at='2026-11-02T09:19:59.900+08:00';network_delay_ms=200;stage_boundary='2026-11-02T09:20:00.000+08:00';required_checks=@('account','market_status','session','rules_version')}}
        9 {[ordered]@{case_id='isolated-small-feature-input';decision_at='2026-11-02T09:45:00.000+08:00';feature_window_start='2026-11-02T09:30:00.000+08:00';feature_window_end='2026-11-02T10:00:00.000+08:00';feature_available_at='2026-11-02T10:00:00.002+08:00';observed_features=@{bid_depth=1000;ask_depth=2000;spread_ticks=2};future_labels_supplied=$false}}
        10 {[ordered]@{case_id='isolated-small-derivative-input';legs=@(@{contract='FUT_A';qty=2;multiplier=300;side='buy'},@{contract='FUT_B';qty=1;multiplier=300;side='sell'});currency='CNY';test_only_margin_rate=0.12}}
        11 {[ordered]@{case_id='isolated-small-compliance-input';test_only_rule=$true;request_ms=@(950,980,1010,1030);window_ms=1000;warning_count=3;hard_count=4;legal_threshold_evidence_available=$false}}
        12 {[ordered]@{case_id='isolated-small-cross-venue-input';legs=@(@{venue='SYN_X';side='long';contracts=100;multiplier=0.001},@{venue='SYN_Y';side='short';contracts=50;multiplier=0.001});mark_price=50000;currency='USDT';fx_rate=7.1;transfer_status='pending_review'}}
        13 {[ordered]@{case_id='isolated-small-etf-block-input';fund='SYN_ETF_200';creation_unit=500000;basket_stocks=200;pcf_version='pcf-test-1';estimated_cash_minor=100000;share_origin=$null;holder_identity=$null;review_status='test_only'}}
    }
    $case=[ordered]@{schema_version='1.0';node_key=$n.node_key;node_name=$n.node_name;source_class='synthetic_test_only';small_case=$mini;large_case=[ordered]@{universe='manifest.symbols';dates='manifest.dates';n_symbols=$manifest.actual_n_symbols;n_days=$manifest.actual_n_days};fault_family_context=$kind;target_node_fault=$fault;fault_coverage='family_context_only_not_exact_node_fault_implementation';no_answers=$true;real_evidence_pending=@($n.required_gap_ids);instructions='Small case and shared large dataset are separate examples; do not merge their quantities. Use per-row availability gates; do not assume file line order is arrival order.'}
    [System.IO.File]::WriteAllText((Join-Path $caseDirectory ($n.node_key+'.json')),($case | ConvertTo-Json -Depth 12),$utf8)
}
$bindings=New-Object System.Collections.Generic.List[string]
$csv=New-Object System.Collections.Generic.List[object]
foreach($q in $questions){
    $key=$q.split_group_id;$n=$nodeIndex[$key]
    $paths=New-Object System.Collections.Generic.List[string]
    foreach($table in $q.related_tables){$paths.Add('synthetic/market/'+$table+'.jsonl')}
    foreach($gap in $q.missing_data_ids){foreach($path in $gapFiles[$gap]){$paths.Add($path)}}
    if($key -in @('P01-S03','P01-S05','P01-S06','P03-S08','P09-S02')){$paths.Add('synthetic/models/volume-profile.jsonl')}
    if($key -in @('P01-S06','P02-S03','P02-S06')){$paths.Add('synthetic/models/execution-parameters.jsonl')}
    if($paths.Count -eq 0){$paths.Add('synthetic/business/parents.jsonl')}
    $refs=foreach($path in ($paths | Select-Object -Unique)){
        if(-not $files.ContainsKey($path)){throw "Missing actual input file: $path"}
        $f=$files[$path]
        if($f.table_schema){foreach($field in $q.minimum_real_fields.($f.table_schema)){if($field -notin $f.columns){throw "Input lacks field: $($f.table_schema).$field"}}}
        $exclude=@()
        if($key -in @('P02-S02','P02-S04') -and $path -eq 'synthetic/models/execution-parameters.jsonl'){$exclude=@('impact_Y','temporary_eta','permanent_gamma','risk_lambda')}
        [ordered]@{path=$path;sha256=$f.sha256;rows=$f.rows;namespace='synthetic';fidelity=$f.fidelity;availability=$f.availability;exclude_fields=$exclude}
    }
    $casePath='cases/'+$key+'.json'
    $questionNumber=[int]$q.question_id.Substring($q.question_id.Length-2)
    $specialVariants=switch($questionNumber){2{@('partial_failure')}3{@('recovery')}4{@('missing_evidence')}6{@('missing_evidence')}8{@('partial_failure')}9{@('normal','partial_failure')}10{@('missing_evidence')}default{@('normal')}}
    $record=[ordered]@{schema_version='1.0';question_id=$q.question_id;node_key=$key;node_name=$q.node_name;question_type=$q.question_type;question=$q.question;source_class='synthetic_test_only';case_file=$casePath;case_sha256=(Get-FileHash -LiteralPath (Join-Path $DataDirectory $casePath) -Algorithm SHA256).Hash.ToLowerInvariant();input_files=@($refs);filters=[ordered]@{symbols='all_manifest_symbols';dates='all_manifest_dates';special_variants=@($specialVariants)};visibility_policy='At each decision use rows whose declared available_at <= decision time; full-window loading is for offline iteration only';synthetic_input_ready=$true;input_support_scope='synthetic_baseline_and_small_case';exact_node_fault_implemented=$false;real_dataset_ready=$false;real_calibration_ready=$false;task_refs=$q.task_refs;minimum_real_fields=$q.minimum_real_fields;missing_real_data_ids=$q.missing_data_ids;read_command=('powershell -NoProfile -ExecutionPolicy Bypass -File scripts/read-question-input.ps1 -QuestionId '+$q.question_id+' -MetadataOnly')}
    $bindings.Add(($record | ConvertTo-Json -Depth 14 -Compress))
    $csv.Add([pscustomobject]@{question_id=$q.question_id;node_key=$key;node_name=$q.node_name;input_file_count=@($refs).Count;case_file=$casePath;source_class='synthetic_test_only';synthetic_input_ready=$true;exact_node_fault_implemented=$false;real_dataset_ready=$false;input_paths=(@($refs.path) -join ';')})
}
if($bindings.Count -ne 1150){throw 'Question input coverage mismatch'}
[System.IO.File]::WriteAllLines((Join-Path $OutputDirectory '题目与数据输入.jsonl'),$bindings,$utf8)
[System.IO.File]::WriteAllLines((Join-Path $DataDirectory 'question-inputs.jsonl'),$bindings,$utf8)
$csv | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputDirectory '题目输入索引.csv')
$summary=[ordered]@{questions=$bindings.Count;nodes=$nodes.Count;synthetic_baseline_ready=1150;exact_node_fault_ready=0;actual_n_symbols=$manifest.actual_n_symbols;actual_n_days=$manifest.actual_n_days;public_data_files=$manifest.files.Count;input_validation_result='passed';answers_generated=0;real_dataset_ready=$false;real_calibration_ready=$false;manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $DataDirectory 'manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();scope='questions_and_inputs_only';limitations='Every question has concrete shared baseline and a small-case input; exact reproduction of every node-specific fault and real-source validation remain separate tasks.'}
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'input-coverage.json'),($summary | ConvertTo-Json -Depth 8),$utf8)
$summary | ConvertTo-Json
