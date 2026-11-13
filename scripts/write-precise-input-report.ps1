param([string]$DataDirectory,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $DataDirectory){$DataDirectory=Join-Path $root 'data/generated/execution-inputs-v1'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'deliverables'}
$report=Get-Content -Raw -Encoding UTF8 (Join-Path $OutputDirectory 'precise-input-validation.json') | ConvertFrom-Json
if($report.result -ne 'passed'){throw 'Precise validation must pass before publishing coverage'}
$bindings=@(Get-Content -Encoding UTF8 (Join-Path $OutputDirectory '题目与数据输入.jsonl') | ForEach-Object {$_ | ConvertFrom-Json})
$questionIndex=@{};foreach($record in $bindings){$questionIndex[$record.question_id]=$record}
$report.questions_detail | ForEach-Object {
    $row=$_;$binding=$questionIndex[$row.question_id]
    $case=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory $row.case_file) | ConvertFrom-Json
    [pscustomobject]@{question_id=$row.question_id;node_key=$row.node_key;question=$binding.question;adaptation_role=$row.adaptation_role;primary_experiment=$case.small_case.experiment_id;primary_input_keys=(@($case.small_case.PSObject.Properties.Name) -join ';');case_file=$row.case_file;case_sha256=$row.case_sha256;question_sha256=$row.question_sha256;scenario_files=(@($case.scenario_files.path) -join ';');shared_input_paths=(@($binding.input_files.path) -join ';');source_class='synthetic_test_only';question_specific_input_validated=$true;exact_node_fault_implemented=$true;real_dataset_ready=$false}
} | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputDirectory '逐题适配覆盖.csv')
$report.nodes_detail | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputDirectory '逐节点场景覆盖.csv')
$text=New-Object Text.StringBuilder
[void]$text.AppendLine('# 逐题精准适配说明')
[void]$text.AppendLine('')
[void]$text.AppendLine('当前只交付题目和数据输入。1150题各有独立案例文件；575道具体技术题各有人工编写的专用实验。115节点各有正常基线、故障、恢复证据、缺证、中性表达5类场景，共575份节点场景。默认共享背景仍为200个SYN标的、5日、48个原始数据文件。')
[void]$text.AppendLine('')
[void]$text.AppendLine('## 输入分工与来源')
[void]$text.AppendLine('')
[void]$text.AppendLine('|输入|来源与用途|')
[void]$text.AppendLine('|---|---|')
[void]$text.AppendLine('|Q01—Q05专用实验|config/precise-node-inputs*.jsonl逐题编写；cases/questions/{question_id}.json的small_case.given是该题主输入。不加载其他题的故障观测，避免串题。|')
[void]$text.AppendLine('|Q06/Q10|删去真实存在的必要字段，保留缺失路径；分别用于数据契约、证据与适用边界。|')
[void]$text.AppendLine('|Q07|该节点5个独立实验，用于实现与不变量；独立实验的数量不可合并。|')
[void]$text.AppendLine('|Q08|该节点的故障观测及变异输入；另给原始查询/回报作为恢复证据，不提供求解后的最终状态。|')
[void]$text.AppendLine('|Q09|正常、对象键顺序变化、故障三份输入。只改变对象键序，不打乱有时间因果的事件数组。|')
[void]$text.AppendLine('|节点故障探针|config/node-fault-probes.jsonl逐节点指定；包含观测日志、对账/容量/顺序等输入。独立校验器检查正常满足关系、故障违反关系，恢复场景保留故障初态并追加查询。|')
[void]$text.AppendLine('|共享大背景|FixtureGenerator.cs按seed正向生成；market沿用已确认ClickHouse表字段。不是从ClickHouse提取的真实行，也不与专用小案例的订单号、数量、时钟混用。|')
[void]$text.AppendLine('')
[void]$text.AppendLine('## 五题复核样本')
[void]$text.AppendLine('')
foreach($id in @('P01-S01-Q02','P02-S01-Q01','P05-S08-Q05','P09-S01-Q02','P13-S01-Q03')){
    $binding=$questionIndex[$id];$case=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory $binding.case_file) | ConvertFrom-Json
    [void]$text.AppendLine(('### '+$id))
    [void]$text.AppendLine('')
    [void]$text.AppendLine($binding.question)
    [void]$text.AppendLine('')
    [void]$text.AppendLine('```json')
    [void]$text.AppendLine(($case.small_case | ConvertTo-Json -Depth 20))
    [void]$text.AppendLine('```')
    [void]$text.AppendLine('')
    [void]$text.AppendLine(('接口：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/read-question-input.ps1 -QuestionId '+$id+' -MetadataOnly`。完整文件位于输入ZIP中的`'+$binding.case_file+'`。'))
    [void]$text.AppendLine('')
}
[void]$text.AppendLine('## 校验与边界')
[void]$text.AppendLine('')
[void]$text.AppendLine('独立校验器PreciseInputValidator.cs从序列化文件重新读取，检查1725份案例哈希、1150题ID与题干哈希、575个实验投影、115个具体故障关系、缺字段、恢复证据和中性表达语义。反例覆盖错题、旧题干、题干数值错误、答案泄漏、伪称真实、重复入账、并发超额、未来特征和重复占券。覆盖表为逐题适配覆盖.csv与逐节点场景覆盖.csv；机器证据为precise-input-validation.json。')
[void]$text.AppendLine('')
[void]$text.AppendLine('exact_node_fault_implemented=true仅指本次声明的合成节点故障输入已覆盖，不表示执行引擎、所有故障组合或真实市场效果通过验收。没有真实ClickHouse数据、柜台/PCF/主体证据、官方适用规则或硬件测量时，real_dataset_ready与real_calibration_ready仍为false。相应后续任务继续保留；本次不调用教师模型、不生成答案。')
[void]$text.AppendLine('')
[void]$text.AppendLine('读取器的-AsOf只过滤共享文件行；专用小案例明确为离线时间线，可能包含供推理的后续事件，不是盘中可直接读取的特征快照。最终成交价、后续回报等只能在各自已可知时点使用。manifest和校验报告供审计，不作为模型输入特征。')
[IO.File]::WriteAllText((Join-Path $OutputDirectory '逐题精准适配说明.md'),$text.ToString(),(New-Object Text.UTF8Encoding($false)))
Write-Output 'Published 1150 question rows, 115 node rows and five literal-input examples.'
