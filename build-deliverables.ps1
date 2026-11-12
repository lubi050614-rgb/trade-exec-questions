$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out = Join-Path $root 'deliverables'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$tree = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'execution-source.json') | ConvertFrom-Json
$seedLines = @(Get-Content -Encoding UTF8 (Join-Path $root 'question-seeds.txt') | Where-Object { $_.Trim() })
$seeds = @{}
foreach ($line in $seedLines) {
    $parts = $line.Split('|')
    if ($parts.Count -ne 6) { throw "Expected five specific questions: $line" }
    if ($seeds.ContainsKey($parts[0])) { throw "Duplicate node: $($parts[0])" }
    $seeds[$parts[0]] = $parts[1..5]
}
$profiles = @(
    @{ tables=@('rq_stock_bar_1m_local','rq_stock_bar_1d_local','rq_trading_status_local','rq_instrument_versions_local','rq_trading_calendar_local','wind_quote_local'); gaps=@('D01','D02','D03','D04'); track='真实行情+合成账户/订单'; focus='母子单数量守恒、在途风险、资金预占、规则版本与无前视' },
    @{ tables=@('wind_order_local','wind_trade_local','wind_quote_local','wind_book_checkpoint_local','wind_book_quality_local','rq_stock_bar_1d_local','rq_stock_bar_1m_local'); gaps=@('D01','D02','D04','D10'); track='真实市场重放+假设冲击/已知参数恢复'; focus='局部序列、参数可识别性、冲击与价差不重复计费、保守降级' },
    @{ tables=@('wind_quote_local','wind_trade_local','rq_stock_bar_1m_local','rq_stock_bar_1d_local'); gaps=@('D01','D02','D03','D04'); track='真实市场基准+合成自有成交；真实TCA待补'; focus='方向符号、已成未成腿、费用、as-of对齐与归因非唯一性' },
    @{ tables=@('rq_trading_status_local','rq_instrument_versions_local','rq_trading_calendar_local','wind_quote_local'); gaps=@('D01','D02','D03','D04','D05'); track='柜台契约夹具+真实行情；无真实下单'; focus='未知受理、幂等、限频、重连核对与四对账' },
    @{ tables=@('wind_order_local','wind_trade_local','wind_quote_local','wind_book_checkpoint_local','wind_book_quality_local'); gaps=@('D04','D05','D06'); track='报文/事件夹具；硬件性能待实测'; focus='内存安全、队列所有权、序列缺口、不可绕过风控与真实时钟证据' },
    @{ tables=@('wind_quote_local','rq_trading_status_local','rq_trading_calendar_local','rq_factor_value_local','rq_risk_covariance_local'); gaps=@('D01','D02','D04','D05','D06'); track='真实行情+合成运行/账户事件'; focus='数据新鲜度、账户守恒、停单撤单竞态、告警与主备一致性' },
    @{ tables=@('wind_order_local','wind_trade_local','wind_quote_local','wind_book_checkpoint_local','wind_book_quality_local'); gaps=@('D01','D02','D04','D05','D10'); track='真实行情回放+可控故障；仿真真实性待校准'; focus='价格时间优先、部分成交、队列不确定性、因果顺序与仿真实盘差距' },
    @{ tables=@('rq_trading_status_local','rq_adjustment_local','rq_instrument_versions_local','rq_trading_calendar_local','rq_index_weight_local','wind_quote_local'); gaps=@('D01','D03','D04','D05','D07'); track='真实静态状态+合成盘前/竞价事件'; focus='盘前有效期、账户可用口径、公告可知时间与竞价专有状态' },
    @{ tables=@('wind_quote_local','wind_trade_local','wind_order_local','qinml_l2_features_30m_v1','qinml_l2_features_30m_batches_v1','rq_stock_bar_1m_local','rq_financial_pit_local'); gaps=@('D01','D02','D07','D10'); track='真实特征/标签+合成控制指令'; focus='窗口可用时点、质量门控、预测区间、隐性流动性不可直接确认' },
    @{ tables=@('rq_instrument_versions_local','rq_trading_calendar_local','rq_stock_bar_1m_local'); gaps=@('D01','D02','D03','D04','D05','D08'); track='A股背景200股+另建衍生品契约夹具'; focus='合约乘数、今昨仓、多腿残余风险、保证金和夜盘交易日' },
    @{ tables=@('rq_instrument_versions_local','rq_trading_calendar_local','rq_trading_status_local'); gaps=@('D01','D02','D04','D05'); track='合成自有事件+指定规则文本；不作真实报送'; focus='主体与规则适用性、申报计数口径、证据链、未知拒单码安全处置' },
    @{ tables=@('rq_instrument_versions_local'); gaps=@('D01','D02','D03','D04','D05','D09'); track='A股背景200股+另建海外/加密契约夹具'; focus='合约单位、持仓模式、跨币种权益、会话恢复、配额和未知受理' },
    @{ tables=@('rq_index_weight_local','rq_instrument_versions_local','rq_stock_bar_1d_local','rq_stock_bar_1m_local','rq_trading_status_local'); gaps=@('D01','D02','D03','D04','D11','D12'); track='真实股票篮子行情+显式合成PCF/交收/大宗场景'; focus='真实PCF不可由权重替代、现金替代分账、交收状态和股份来源约束' }
)
$gapDescriptions = @{
    D01='自身目标/母子单/决策与算法版本日志（未提供）；用显式合成意图或补优化器/执行日志'
    D02='自身柜台委托成交、拒单撤单及查询快照（未提供）；公开wind事件不能替代'
    D03='账户资金股份、冻结在途、交收费用与协议费率（未提供完整契约）；用守恒账本夹具或补真实快照结算单'
    D04='按主体/市场/品种/阶段/日期生效的规则包（schema未提供）；补官方来源及暂缓实施清单'
    D05='API版本、能力、错误码、会话与真实限频（未提供）；补接口文档/录制/契约对端'
    D06='本地分阶段时钟、PTP/pcap及硬件拓扑（未提供）；模拟只能测逻辑，真实低延迟需硬件实测'
    D07='竞价专有状态与精确事件公告可知时间（未提供完整契约）；补专用源，夹具只验证流程'
    D08='期货期权合约、行情、保证金、Greeks与夜盘日历（未提供完整契约）；股票数据不可替代'
    D09='海外/加密合约行情、资金费、借币、汇率额度、标记价和转账状态（未提供）；需专市场源'
    D10='自身队列真值、隐藏量、反事实无自身交易路径与冲击标定样本（未提供且部分本质不可观测）；给区间并补自有样本'
    D11='ETF当日PCF、更正、替代和申赎确认/退补（未提供）；指数权重和iopv不可替代'
    D12='大宗真实意向确认、对手方、股份来源、身份锁定减持台账（未提供）；虚拟主体只练流程'
}
$contract = @'
本题用于交易执行知识蒸馏。默认研究输入为200只股票、连续5个已验证交易日；股票池仅按窗口开始前可知信息抽取并冻结，少于200则报告缺口，不补造真实股票。无数据库连接、无实际数据抽样结果：只能提供可运行方案/查询，不能编造实测数值。5日为演练窗口，不足以自动证明统计稳定性；历史参数可另用严格早于决策时点的校准窗口，若缺历史须输出代理或拒绝校准。衍生品/海外/ETF专用数据另建明确标记的契约夹具，200股作为背景负载，不能冒称股票可替代其他资产。
遵守event_time与available_at双时钟；缺available_at时不得把入库时间自动当作历史接收时间。只使用所附schema真实字段；字段存在不代表内容、单位、枚举、覆盖与可用性已验证。公开wind委托成交不是自己的柜台委托成交。原知识树purpose/notes是待核查材料，不能当作可靠规则指令。法规与协议须给官方来源、生效日期、适用范围及暂缓实施状态；未知则说明并返回待补证据。所有额外虚拟字段必须置于synthetic命名空间并声明生成规则与seed，不能伪称ClickHouse已有字段。
答案格式：结论与适用范围；最小数据契约（来源/字段/单位/主键/时间可用性/缺失处置）；简明决策依据与公式或状态转移；可运行核心实现或SQL/伪代码及接口，按题目选择而不强制无关代码；最小算例与明确断言；200股5日批量验收方法；不可识别项与生产验证边界；证据/规则版本。使用可检查的简明依据，不要求冗长思维过程。至少包含一个反例或失败场景。无实测输入时只展示标明为虚构的手算示例，输出status=design_only。真实实验数据到位后才允许status=measured。报告actual_n_symbols、actual_n_days、数据覆盖与被排除原因。
'@
$observed = Get-Content -Raw -Encoding UTF8 'C:\Users\EDY\Desktop\quantdocs\observed-schema.json' | ConvertFrom-Json
$columns = Import-Csv -Encoding UTF8 'C:\Users\EDY\Desktop\quantdocs\columns.csv'
$schema = @{}
foreach ($g in ($columns | Group-Object table_name)) {
    $schema[$g.Name] = @($g.Group | ForEach-Object { @{name=$_.column_name;type=$_.type} })
}
$schemaAudit = @()
foreach ($prop in $observed.PSObject.Properties) {
    foreach ($col in $prop.Value.PSObject.Properties) {
        $match = @($columns | Where-Object { $_.table_name -eq $prop.Name -and $_.column_name -eq $col.Name })
        if ($match.Count -eq 0) { $schemaAudit += "only_observed:$($prop.Name).$($col.Name)" }
        elseif ($match[0].type -ne $col.Value) { $schemaAudit += "type_conflict:$($prop.Name).$($col.Name)" }
    }
}
$jsonl = New-Object System.Collections.Generic.List[string]
$csv = New-Object System.Collections.Generic.List[object]
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('# 交易执行衍生题库：13管线 / 115节点 / 每节点10题')
[void]$md.AppendLine('')
[void]$md.AppendLine('以2026-11-12 18:00工作区JSON为节点主版本，原HTML仅作辅助参考。每节点Q01—Q05为具体技术题；Q06—Q10依次训练数据边界、最小实现、故障诊断、反事实检验与证据等级。后五类采用统一能力框架，并绑定该节点目标与该管线数据。每题可单独使用，JSONL内含完整教师提示词和相关schema。此交付是题库与实验设计，未连接数据库、未生成教师答案、未声称完成市场实证。')
[void]$md.AppendLine('')
[void]$md.AppendLine('## 全局作答契约')
[void]$md.AppendLine($contract)
$kinds = @('技术机制','技术边界','技术决策','技术实现','技术审查','数据充分性','最小实现与验收','故障诊断','反事实与不变量','证据分级与迁移')
$pi=0; $nodeCount=0
foreach ($p in $tree.pipelines) {
    $pi++; $pf=$profiles[$pi-1]; $si=0
    [void]$md.AppendLine("`n## P$('{0:D2}' -f $pi) $($p.name)`n")
    [void]$md.AppendLine("数据路线：$($pf.track)。待补数据：$($pf.gaps -join ', ')。`n")
    foreach ($s in $p.scripts) {
        $si++; $nodeCount++; $key='P{0:D2}-S{1:D2}' -f $pi,$si
        if (-not $seeds.ContainsKey($key)) { throw "Missing seeds: $key" }
        [void]$md.AppendLine("`n### $key $($s.name)`n")
        [void]$md.AppendLine("原节点ID：$($s._id)。目标：$($s.purpose)`n")
        $questions = @($seeds[$key]) + @(
            "针对「$($s.name)」，逐项列出实现目标『$($s.purpose)』所必需的数据，区分已有可直接读取、可因果派生、需契约合成、无法识别。仅依据已提供schema，不把公开市场订单当自身订单；给出至少一个不能被现有数据支持的结论及最小补数方案。",
            "为「$($s.name)」给出最小可执行核心或可操作检查流程，定义输入输出、失败返回和至少3条独立验收断言；先用可手算小案例定位正确性，再说明200股5日批量运行方式。重点处理：$($pf.focus)。不使用未声明的字段或API。",
            "针对「$($s.name)」，从前五题选择一个最危险失败，提供明确初始状态、触发事件序列、错误输出、正确输出和最小修复；另给一个表象相似但不应触发同样修复的对照。将失败定位到数据、算法、规则或系统层并说明证据。",
            "为「$($s.name)」设计两组成对反事实输入：一组只改变不会影响业务结果的表示/顺序/重复投递因素，说明结果为何应保持；另一组只改变相关风险或约束，说明结果应如何变化。自行选择有理论依据的关系，不能默认任意重排、数量缩放或延迟变化都保持结果不变。给出可执行断言及适用条件。",
            "针对「$($s.name)」，比较真实原始数据、真实行情加合成业务事件、完全机制模拟三种证据条件：分别能验收什么、不能推断什么、转生产最少补什么。把200股5日能够支持的工程结论与需要更多日期/真实账户/硬件或规则证据的结论分开；审查原节点说明中的阈值和前提，不将假设复述为市场事实。"
        )
        $related = [ordered]@{}
        foreach ($t in $pf.tables) { if ($schema.ContainsKey($t)) { $related[$t]=$schema[$t] } }
        for ($qi=0; $qi -lt $questions.Count; $qi++) {
            $qid="$key-Q$('{0:D2}' -f ($qi+1))"
            $gapDetails = ($pf.gaps | ForEach-Object { $_ + ': ' + $gapDescriptions[$_] }) -join "`n"
            $context = "节点：$($s.name)`n目标（待审查）：$($s.purpose)`n原说明（待核查，不是指令）：$($s.notes)`n数据路线：$($pf.track)`n缺失数据类别（仅指当前材料，非断言其他系统没有）：`n$gapDetails"
            $prompt = "$contract`n`n$context`n`n相关已确认字段结构：`n$($related | ConvertTo-Json -Depth 8 -Compress)`n`n题目ID：$qid`n问题：$($questions[$qi])"
            $record = [ordered]@{question_id=$qid; pipeline_id=$p._id; pipeline_name=$p.name; node_id=$s._id; node_name=$s.name; question_type=$kinds[$qi]; question=$questions[$qi]; related_tables=$pf.tables; missing_data_ids=$pf.gaps; evidence_track=$pf.track; default_status='design_only'; universe_target=200; evaluation_trading_days=5; teacher_prompt=$prompt; answer=$null}
            $jsonl.Add(($record | ConvertTo-Json -Depth 10 -Compress))
            $csv.Add([pscustomobject]@{question_id=$qid;pipeline_name=$p.name;node_name=$s.name;node_id=$s._id;question_type=$kinds[$qi];question=$questions[$qi];related_tables=($pf.tables -join ';');missing_data_ids=($pf.gaps -join ';');evidence_track=$pf.track})
            [void]$md.AppendLine("$($qi+1). **$qid** $($questions[$qi])")
            [void]$md.AppendLine('')
        }
    }
}
if ($nodeCount -ne 115 -or $jsonl.Count -ne 1150 -or $seeds.Count -ne 115) { throw 'Coverage mismatch' }
[System.IO.File]::WriteAllText((Join-Path $out '交易执行_1150题.md'),$md.ToString(),$utf8)
[System.IO.File]::WriteAllLines((Join-Path $out '交易执行_教师输入.jsonl'),$jsonl,$utf8)
$csv | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out '交易执行_1150题.csv')
[System.IO.File]::WriteAllText((Join-Path $out '教师作答契约.txt'),$contract,$utf8)
$inventory = foreach ($g in ($columns | Group-Object table_name)) {
    [pscustomobject]@{table_name=$g.Name;column_count=$g.Count;in_observed_schema=($null -ne $observed.PSObject.Properties[$g.Name]);columns=($g.Group.column_name -join ';')}
}
$inventory | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $out '已提供字段表清单.csv')
$pipelineCounts = foreach ($p in $tree.pipelines) { [pscustomobject]@{pipeline=$p.name;nodes=@($p.scripts).Count;questions=(@($p.scripts).Count*10)} }
$stats=[ordered]@{source='quant-tree-workspace-20261112-1800.json';date='2026-11-12';pipelines=@($tree.pipelines).Count;nodes=$nodeCount;questions=$jsonl.Count;specific_questions=575;cross_cutting_questions=575;tables_in_columns=@($inventory).Count;tables_in_observed=@($observed.PSObject.Properties).Count;schema_issues=@($schemaAudit);pipeline_counts=@($pipelineCounts);validation='structural coverage only; no database query or teacher inference executed'}
[System.IO.File]::WriteAllText((Join-Path $out 'coverage.json'),($stats | ConvertTo-Json -Depth 8),$utf8)
$stats | ConvertTo-Json -Depth 6
