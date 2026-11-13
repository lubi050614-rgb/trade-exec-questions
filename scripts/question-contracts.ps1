# Dot-sourced by build-deliverables.ps1. All registry data is repository-local.
$gapRegistry = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config\data-gaps.json') | ConvertFrom-Json
$gapIndex = @{}
foreach ($gap in $gapRegistry.gaps) { $gapIndex[$gap.id] = $gap }
$aliases = @{
    daily='rq_stock_bar_1d_local'; minute='rq_stock_bar_1m_local'; inst='rq_instrument_versions_local'; status='rq_trading_status_local'; calendar='rq_trading_calendar_local'
    quote='wind_quote_local'; order='wind_order_local'; trade='wind_trade_local'; quality='wind_book_quality_local'; checkpoint='wind_book_checkpoint_local'
    feature='qinml_l2_features_30m_v1'; batches='qinml_l2_features_30m_batches_v1'; adjust='rq_adjustment_local'; financial='rq_financial_pit_local'; weight='rq_index_weight_local'; factor='rq_factor_value_local'; cov='rq_risk_covariance_local'
}
$minimalFields = @{
    daily=@('market','security_code','trade_date','close','volume','total_turnover'); minute=@('market','security_code','bar_end','trade_date','close','volume','total_turnover')
    inst=@('market','security_code','asset_type','listed_date','delisted_date','round_lot','board_type'); status=@('market','security_code','trade_date','suspended','st_flag','limit_up','limit_down'); calendar=@('trade_date')
    quote=@('market','security_code','ts','trade_date','channel_id','exchange_seq','bid_price_1','bid_volume_1','ask_price_1','ask_volume_1')
    order=@('market','security_code','ts','trade_date','channel_id','exchange_seq','order_no','exchange_order_id','order_type','order_code','price','volume')
    trade=@('market','security_code','ts','trade_date','channel_id','exchange_seq','trade_id','bid_order_id','ask_order_id','price','volume')
    quality=@('market','security_code','trade_date','gap_count','unresolved_refs','ambiguous_groups','reconstruction_policy','confidence')
    checkpoint=@('market','security_code','ts','trade_date','bid_prices','bid_volumes','ask_prices','ask_volumes','reconstruction_policy')
    feature=@('symbol','trade_date','window_end','quote_coverage_ratio','quote_age_ms','semantics_confirmed','price_divisor_known','volume_multiplier_known','quality_status')
    batches=@('batch_id','status','checks_passed','formula_version','config_hashes'); adjust=@('market','security_code','effective_date','adjustment_type','value')
    financial=@('market','security_code','info_date','metric','value'); weight=@('market','security_code','trade_date','index_code','weight')
    factor=@('market','security_code','trade_date','factor_name','value'); cov=@('trade_date','model','factor_i','factor_j','value','units')
}
$nodeDefinitions = @{}
foreach ($line in (Get-Content -Encoding UTF8 (Join-Path $root 'config\node-contracts.txt'))) {
    if (-not $line.Trim() -or $line.StartsWith('#')) { continue }
    $parts = $line.Split('|')
    if ($parts.Count -ne 6 -or $nodeDefinitions.ContainsKey($parts[0])) { throw "Invalid or duplicate node contract: $line" }
    $nodeDefinitions[$parts[0]] = @{ gaps=@($parts[1].Split(',') | Where-Object { $_.Trim() }); aliases=@($parts[2].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }); invariant=$parts[3]; failure=$parts[4]; oracle=$parts[5] }
}
$nodeContracts = New-Object System.Collections.Generic.List[object]
$inputEvidencePath=$InputCoveragePath
$syntheticInputReady=$false
if(Test-Path -LiteralPath $inputEvidencePath){
    $inputEvidence=Get-Content -Raw -Encoding UTF8 -LiteralPath $inputEvidencePath | ConvertFrom-Json
    $syntheticInputReady=$inputEvidence.scope -eq 'questions_and_inputs_only' -and $inputEvidence.input_validation_result -eq 'passed' -and $inputEvidence.synthetic_baseline_ready -eq 1150
}

function Get-ExecutionNodeContract($key, $scriptNode, $pipeline, $pipelineNumber, $schema) {
    if (-not $nodeDefinitions.ContainsKey($key)) { throw "Missing node contract: $key" }
    $def = $nodeDefinitions[$key]
    $tables = @()
    $fields = [ordered]@{}
    foreach ($alias in $def.aliases) {
        if (-not $aliases.ContainsKey($alias)) { throw "Unknown table alias: $alias" }
        $table=$aliases[$alias]
        if (-not $schema.ContainsKey($table)) { throw "Unknown real table: $table" }
        foreach ($field in $minimalFields[$alias]) {
            if ($field -notin $schema[$table].name) { throw "Unknown real field: $table.$field" }
        }
        $tables += $table
        $fields[$table]=@($minimalFields[$alias])
    }
    $taskRefs=@('connect-market-replay-and-calibration/1.1')
    foreach ($gapId in $def.gaps) {
        if (-not $gapIndex.ContainsKey($gapId)) { throw "Unknown gap: $gapId" }
        $taskRefs += @($gapIndex[$gapId].task_refs)
    }
    $priority = if ($pipelineNumber -in @(1,3,6,7)) { 'P0' } elseif ($pipelineNumber -in @(2,4,8,9,11)) { 'P1' } else { 'P2' }
    return [ordered]@{
        node_key=$key;node_id=$scriptNode._id;pipeline_name=$pipeline.name;node_name=$scriptNode.name
        training_priority=$priority;real_tables=@($tables);minimum_real_fields=$fields;required_gap_ids=@($def.gaps)
        acceptance_invariant=$def.invariant;failure_scenario=$def.failure;independent_oracle=$def.oracle
        task_refs=@($taskRefs | Select-Object -Unique)
        readiness=[ordered]@{design_ready=$true;synthetic_input_ready=$syntheticInputReady;dataset_ready=$false;generator_implemented=$syntheticInputReady;generator_scope='shared_synthetic_inputs_only';exact_node_fault_implemented=$false;real_calibration_ready=$false}
        availability_policy='event_time与available_at分开；未知接收时间不得由createtime替代'
        split_group_id=$key
    }
}

function Get-ExecutionQuestions($nodeContract, $originalQuestions) {
    $n=$nodeContract
    return @($originalQuestions[0..4]) + @(
        "为「$($n.node_name)」建立最小数据契约，使用本题附带的minimum_real_fields及缺口定义区分真实、派生、synthetic和不可识别项。必须支撑不变量『$($n.acceptance_invariant)』；说明字段单位、主键、event_time/available_at、缺失策略以及缺口解决路径。没有额外结构缺口时也不得把schema存在当成数据已就绪。",
        "实现或设计「$($n.node_name)」的最小核心，使『$($n.acceptance_invariant)』可检查。用『$($n.independent_oracle)』作独立验收，不准仅复述同一实现。提交输入输出契约、核心代码或操作步骤、至少3条可判失败的断言、一个小算例和200股5日批量步骤；缺专用资产、规则或硬件时写清替代夹具范围。",
        "诊断「$($n.node_name)」的故障：『$($n.failure_scenario)』。给出明确初始状态、最短触发序列、错误与正确结果、可观察证据、最小修复及不会误伤的正常对照；按『$($n.independent_oracle)』核验，并证明恢复后仍满足『$($n.acceptance_invariant)』。本题不依赖其他题目的答案。",
        "围绕「$($n.node_name)」的不变量『$($n.acceptance_invariant)』，构造两组成对反事实：一个仅改变无业务意义的表示，另一个只改变与故障『$($n.failure_scenario)』相关的风险或约束。给出输入差异、预期变化和失败断言；以『$($n.independent_oracle)』检查。不得默认任意乱序、数量缩放或延迟变化保持结果不变。",
        "审查「$($n.node_name)」的证据等级：现有字段与缺口清单能否验证『$($n.acceptance_invariant)』，能否支持真实市场、账户或性能结论？分别列出设计、合成夹具、真实行情重放、外部实测四种条件下的允许与禁止结论，明确未决项、task_refs对应的最小补数任务和放行证据；原节点阈值或规则若缺有效依据必须标记待核验。"
    )
}

function Export-ExecutionContracts {
    if ($nodeDefinitions.Count -ne 115 -or $nodeContracts.Count -ne 115) { throw 'Node contract coverage mismatch' }
    [System.IO.File]::WriteAllText((Join-Path $out '节点数据契约.json'),(ConvertTo-Json -InputObject @($nodeContracts.ToArray()) -Depth 12),$utf8)
    $nodeContracts | ForEach-Object { [pscustomobject]@{node_key=$_.node_key;node_name=$_.node_name;training_priority=$_.training_priority;required_gap_ids=($_.required_gap_ids -join ';');real_tables=($_.real_tables -join ';');acceptance_invariant=$_.acceptance_invariant;failure_scenario=$_.failure_scenario;independent_oracle=$_.independent_oracle;task_refs=($_.task_refs -join ';');design_ready=$true;synthetic_input_ready=$syntheticInputReady;dataset_ready=$false;generator_implemented=$syntheticInputReady;generator_scope='shared_synthetic_inputs_only';exact_node_fault_implemented=$false} } | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out '节点数据契约.csv')
    $gapRegistry.gaps | ForEach-Object { [pscustomobject]@{id=$_.id;name=$_.name;priority=$_.priority;status=$_.status;real_status=$_.real_status;synthetic_status=$_.synthetic_status;synthetic_artifacts=($_.synthetic_artifacts -join ';');owner_role=$_.owner_role;fields=($_.fields -join ';');real_solution=$_.real_solution;synthetic_solution=$_.synthetic_solution;acceptance=($_.acceptance -join ';');forbidden_claims=($_.forbidden_claims -join ';');task_refs=($_.task_refs -join ';')} } | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out '数据缺口登记表.csv')
    $report=New-Object System.Text.StringBuilder
    [void]$report.AppendLine('# 数据缺口登记与解决方案')
    [void]$report.AppendLine('')
    [void]$report.AppendLine($gapRegistry.scope)
    foreach($g in $gapRegistry.gaps) {
        [void]$report.AppendLine("`n## $($g.id) $($g.name)`n")
        [void]$report.AppendLine("优先级：$($g.priority)；状态：$($g.status)；建议角色：$($g.owner_role)。`n")
        [void]$report.AppendLine("真实来源状态：$($g.real_status)；合成输入状态：$($g.synthetic_status)。已生成的基础输入：$($g.synthetic_artifacts -join '；')。路径相对于解压后的数据目录；不是ClickHouse真实表。`n")
        [void]$report.AppendLine("最小synthetic/外部契约（不是已有ClickHouse列）：$($g.fields -join '；')。`n")
        [void]$report.AppendLine("真实解决：$($g.real_solution)`n`n替代方案：$($g.synthetic_solution)`n")
        [void]$report.AppendLine("验收：$($g.acceptance -join '；')。`n`n禁止结论：$($g.forbidden_claims -join '；')。`n")
        $affected=@($nodeContracts | Where-Object { $g.id -in $_.required_gap_ids })
        [void]$report.AppendLine("关联节点数：$($affected.Count)；任务：$($g.task_refs -join '；')。")
    }
    [System.IO.File]::WriteAllText((Join-Path $out '数据缺口登记表.md'),$report.ToString(),$utf8)
    $readiness=@'
# 题库与数据就绪度

当前只交付题目和对应输入，不生产答案。115节点、1150题的设计契约已完成；真实数据库未连接，真实校准为0。

合成输入状态以input-coverage.json和input-binding-validation.json为准。已有输入生成器、共享200标的5日数据和逐节点小案例；每题均有具体文件引用。它们支持synthetic_baseline，不表示115个节点的全部精确故障均已复现。

- design_ready：独立题面、数据依赖、不变量、故障、oracle齐全。
- dataset_ready：保留旧字段，表示真实/完整节点任务级数据门槛，不等于共享synthetic基础包；本版保持false。
- synthetic_input_ready：对应已验证的合成基础输入包；不等于真实数据。
- generator_implemented：已有共享合成输入生成器，generator_scope=shared_synthetic_inputs_only；不表示执行算法、生产柜台或每个节点故障引擎已实现。
- exact_node_fault_implemented：本版保持false；故障族数据与精确节点故障覆盖分开。
- real_calibration_ready：需独立自有订单/专用数据/硬件/有效规则等外部证据，按节点决定。

具体输入入口为题目与数据输入.jsonl、题目输入索引.csv和scripts/read-question-input.ps1。精确节点故障、真实源接入和外部证据的剩余工作见任务进度.md；不包含教师模型调用、蒸馏或学生评测。

family_id/split_group_id暂按技术节点设置，split=unassigned；当前不开展训练集划分或模型生产。跨节点近重复分组不是本阶段输入交付的完成条件。
'@
    [System.IO.File]::WriteAllText((Join-Path $out '题库就绪度.md'),$readiness,$utf8)
}
