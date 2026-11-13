param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'deliverables'),
    [switch]$SelfTest,
    [string]$InputCoveragePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'deliverables\input-coverage.json')
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Assert-Check($condition,[string]$message) { if (-not $condition) { throw $message } }
$source=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'execution-source.json') | ConvertFrom-Json
$registry=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'config\data-gaps.json') | ConvertFrom-Json
$columns=Import-Csv -Encoding UTF8 (Join-Path $root 'data\schema\columns.csv')
$schema=@{}
foreach($group in ($columns | Group-Object table_name)) { $schema[$group.Name]=@($group.Group.column_name) }
$taskIndex=@{}
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $root 'openspec\changes') -Filter tasks.md -Recurse)) {
    $name=$file.Directory.Name -replace '^\d{4}-\d{2}-\d{2}-',''
    $text=Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach($match in [regex]::Matches($text,'(?m)^- \[[ xX]\] (\d+\.\d+)\s')) {
        $key=$name+'/'+$match.Groups[1].Value
        Assert-Check (-not $taskIndex.ContainsKey($key)) "Duplicate task: $key"
        $taskIndex[$key]=$true
    }
}
$gapIndex=@{}
foreach($g in $registry.gaps) {
    Assert-Check (-not $gapIndex.ContainsKey($g.id)) "Duplicate gap: $($g.id)"
    $gapIndex[$g.id]=$g
    foreach($field in @('name','priority','status','owner_role','fields','real_solution','synthetic_solution','acceptance','forbidden_claims','task_refs')) { Assert-Check ($null -ne $g.$field -and @($g.$field).Count -gt 0) "Gap missing $field : $($g.id)" }
    foreach($ref in $g.task_refs) { Assert-Check ($taskIndex.ContainsKey($ref)) "Unknown gap task: $ref" }
}
Assert-Check ($gapIndex.Count -eq 12) 'Expected 12 gap IDs'

function Test-QuestionRecord($r) {
    foreach($field in @('question_id','node_id','question','teacher_prompt','acceptance_invariant','failure_scenario','independent_oracle','family_id','split_group_id','task_refs')) {
        Assert-Check ($null -ne $r.$field -and @($r.$field).Count -gt 0 -and [string]$r.$field -ne '') "Missing record field $field : $($r.question_id)"
    }
    Assert-Check ($r.schema_version -eq '2.0') 'Unexpected question schema version'
    Assert-Check ($r.question_id -match '^P\d{2}-S\d{2}-Q\d{2}$') 'Invalid question ID'
    Assert-Check ($r.default_status -eq 'design_only' -and $null -eq $r.answer) 'Unverified answer/status'
    Assert-Check ($r.readiness.design_ready -eq $true) 'Design readiness missing'
    foreach($field in @('dataset_ready','real_calibration_ready','exact_node_fault_implemented')) { Assert-Check ($r.readiness.$field -eq $false) "False readiness claim: $field" }
    if($r.readiness.generator_implemented -eq $true){
        $evidencePath=$InputCoveragePath
        Assert-Check (Test-Path -LiteralPath $evidencePath) 'Missing input generator evidence'
        $evidence=Get-Content -Raw -Encoding UTF8 -LiteralPath $evidencePath | ConvertFrom-Json
        Assert-Check ($evidence.input_validation_result -eq 'passed' -and $r.readiness.generator_scope -eq 'shared_synthetic_inputs_only') 'Unverified generator scope'
    }
    Assert-Check ($r.universe_target -eq 200 -and $r.evaluation_trading_days -eq 5) 'Experiment target mismatch'
    Assert-Check ($r.family_id -eq $r.split_group_id -and $r.split -eq 'unassigned') 'Unsafe split assignment'
    Assert-Check ($r.question -notmatch '从前五题选择|从前五题选择一个|从前五题选择一个最') 'Cross-question dependency'
    Assert-Check ($r.teacher_prompt.Contains($r.question) -and $r.teacher_prompt.Contains($r.acceptance_invariant)) 'Incomplete standalone prompt'
    Assert-Check ($r.teacher_prompt.Contains('design_only') -and $r.teacher_prompt.Contains('available_at')) 'Missing evidence/time contract'
    foreach($g in $r.missing_data_ids) { Assert-Check ($gapIndex.ContainsKey($g)) "Unknown gap ID: $g" }
    foreach($ref in $r.task_refs) { Assert-Check ($taskIndex.ContainsKey($ref)) "Unknown record task: $ref" }
    foreach($table in $r.related_tables) { Assert-Check ($schema.ContainsKey($table)) "Unknown real table: $table" }
    foreach($property in $r.minimum_real_fields.PSObject.Properties) {
        Assert-Check ($property.Name -in $r.related_tables) "Field table not in related tables: $($property.Name)"
        foreach($field in $property.Value) { Assert-Check ($field -in $schema[$property.Name]) "Unknown real field: $($property.Name).$field" }
    }
    Assert-Check (@($r.required_answer_artifacts).Count -eq 4) 'Missing answer artifacts'
}

$records=@(Get-Content -Encoding UTF8 (Join-Path $OutputDirectory '交易执行_教师输入.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
$csv=@(Import-Csv -Encoding UTF8 (Join-Path $OutputDirectory '交易执行_1150题.csv'))
$contracts=Get-Content -Raw -Encoding UTF8 (Join-Path $OutputDirectory '节点数据契约.json') | ConvertFrom-Json
Assert-Check ($records.Count -eq 1150 -and $csv.Count -eq 1150 -and $contracts.Count -eq 115) 'Coverage mismatch'
Assert-Check (@($records.question_id | Select-Object -Unique).Count -eq 1150) 'Duplicate question ID'
$expected=@{}
$pi=0
foreach($pipeline in $source.pipelines) {
    $pi++;$si=0
    foreach($node in $pipeline.scripts) {
        $si++;$key='P{0:D2}-S{1:D2}' -f $pi,$si
        Assert-Check (-not $expected.ContainsKey($node._id)) 'Duplicate source node ID'
        $expected[$node._id]=$key
        $group=@($records | Where-Object node_id -eq $node._id)
        Assert-Check ($group.Count -eq 10) "Node coverage mismatch: $key"
        for($i=1;$i -le 10;$i++) { Assert-Check (($key+'-Q'+('{0:D2}' -f $i)) -in $group.question_id) "Missing stable ID: $key/$i" }
    }
}
for($i=0;$i -lt $records.Count;$i++) {
    $r=$records[$i]
    Test-QuestionRecord $r
    Assert-Check ($expected.ContainsKey($r.node_id) -and $r.family_id -eq $expected[$r.node_id]) 'Source node/family mismatch'
    Assert-Check ($csv[$i].question_id -eq $r.question_id -and $csv[$i].question -eq $r.question) 'CSV/JSONL mismatch'
    Assert-Check ($csv[$i].missing_data_ids -eq ($r.missing_data_ids -join ';')) 'CSV gap mismatch'
}
Assert-Check (@($contracts.node_key | Select-Object -Unique).Count -eq 115) 'Duplicate node contract'
foreach($nc in $contracts) {
    $r=$records | Where-Object node_id -eq $nc.node_id | Select-Object -First 1
    Assert-Check ($r.acceptance_invariant -eq $nc.acceptance_invariant -and $r.independent_oracle -eq $nc.independent_oracle) 'Node contract drift'
}
$negativeCount=0
if($SelfTest) {
    foreach($case in @('unknown_field','unknown_task','false_readiness','dependent_prompt')) {
        $clone=$records[0] | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json
        switch($case) {
            'unknown_field' { $clone.minimum_real_fields.rq_instrument_versions_local += 'invented_private_balance' }
            'unknown_task' { $clone.task_refs=@('not-a-real-change/9.9') }
            'false_readiness' { $clone.readiness.dataset_ready=$true }
            'dependent_prompt' { $clone.question='从前五题选择一个'; $clone.teacher_prompt += $clone.question }
        }
        $rejected=$false
        try { Test-QuestionRecord $clone } catch { $rejected=$true }
        Assert-Check $rejected "Validator accepted negative case: $case"
        $negativeCount++
    }
}
$result=[ordered]@{schema_version='2.0';validated_at='2026-11-13';questions=$records.Count;nodes=$contracts.Count;gaps=$gapIndex.Count;task_references='resolved';real_fields='schema_checked';csv_jsonl='matched';negative_cases_rejected=$negativeCount;database_connected=$false;shared_input_generator_implemented=($records[0].readiness.generator_implemented -eq $true);exact_node_fault_implemented=$false;teacher_answers_generated=0;result='passed'}
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'validation.json'),($result | ConvertTo-Json -Depth 5),$utf8)
$lines=@('验证日期：2026-11-13','通过：13管线115节点，各10题，共1150个稳定唯一ID。','通过：CSV/JSONL题面一致，115节点契约匹配。','通过：真实表/最低字段与仓库schema一致，12类缺口和任务编号全部可追溯。','通过：题面与输入/故障/证据边界可追踪；共享合成输入状态单独检查。',"负例拒绝数量：$negativeCount。",'限制：未连接ClickHouse、未运行真实重放/硬件测试；输入生成不等于每个节点精确故障实现；未生成题目答案。')
[System.IO.File]::WriteAllLines((Join-Path $OutputDirectory '验证结果.txt'),$lines,$utf8)
$result | ConvertTo-Json
