# 交易执行数据与题库路线图

更新：2026-11-13。任务勾选以各变更单tasks.md为准；自动计数见[任务进度](../deliverables/任务进度.md)。OpenSpec工件就绪表示计划可实施，不表示代码、数据或实证已完成。

## 最终目标

当前阶段只交付“节点 → 题目 → 最小字段与缺口 → 对应输入文件 → 输入验证”的链路。用户已确认“答案”是笔误；不生成答案、不调用教师、不做蒸馏或学生评测。批量输入为200合成标的5日，并配小案例；真实市场结论须另有真实证据。

## 当前边界

- 已有：25表schema、115节点/1150题、12类缺口登记、共享合成生成器、200标的5日基础数据、订单/账本/辅助/专用资产输入及逐题读取器；1150份专用题目案例、575个前五题实验和575份节点场景均有独立校验证据。
- 尚无：真实ClickHouse抽取、真实自身订单/账户、真实专用资产、官方适用规则核验或硬件测量。合成故障覆盖不代替真实验收；未生产题目答案。
- 本次治理变更完成后归档；未来实现任务保持未勾选，不因为本次规划而自动启动实盘或付费模型调用。

|阶段/优先级|变更单|依赖/负责角色|主要产物|放行条件|
|---|---|---|---|---|
|M0，本次|govern-data-gaps-and-question-bank|执行研究/研发|缺口登记、节点契约、题库v2、规范、进度与校验|115节点各10题，字段与任务合法，负例拒绝，确定性及OpenSpec严格验证通过|
|M1，P0|build-execution-fixture-mvp（任务状态见进度）|M0；执行研发|D01—D05目标、回报、账本和测试协议输入；200合成标的5日manifest|输入因果/账本一致，至少10类故障族；不包含生产执行引擎|
|M2，P1|[connect-market-replay-and-calibration](changes/connect-market-replay-and-calibration/tasks.md)|审计可先行；回放依赖M1；数据/合规/执行研究/低延迟研发|真实覆盖、冻结universe、分片重放、D07/D10/D06证据报告|真实来源/语义核验，质量门控，完成率+全目标IS，独立自有样本与硬件按需验证|
|M3，P2|add-special-asset-fixtures（任务状态见进度）|M1；专用输入研发|D08/D09/D11/D12独立资产和协议测试输入|字段/单位/时段/场景一致，不实现各专用交易引擎或真实校准|
|M5，当前交付|deliver-question-input-packs|M0/M1/M3|1150题实际输入引用、115小案例、读取器、完整合成数据包|无答案字段；文件/字段/时间/哈希可验，基础支持范围明确|
|M6，本次完成后归档|refine-node-specific-inputs（任务状态见进度）|M5；逐管线输入研发|1150份题目专用案例、115节点各5类场景、逐题/节点覆盖表|题干哈希和专用投影匹配；正常/故障关系可区分，恢复只追加证据，中性语义不变，重复生成一致|

延期且不计当前任务：[run-teacher-distillation](changes/run-teacher-distillation/tasks.md)的8项任务保留历史规划，scope_status=deferred。当前题目与基础输入的实现状态及真实源/精确场景剩余任务见自动进度报告，不使用旧的28项总数描述当前完成度。

角色是建议责任范围，尚未指派具体人员。任务编号、产物、前置和验收详见各tasks。没有真实源/权限时，应先做不依赖它的契约与夹具，不能虚构连接结果。

## 数据缺口决策

1. D01—D03优先：优化器/柜台真实导出最好；暂无时按机制向前造synthetic，不从因子反演。
2. D04—D05先写test_only规则和假柜台以练工程，再补真实来源与版本；两者不是合规或生产能力证明。
3. D07/D08/D09/D11/D12补专用源或独立契约夹具；股票、指数权重、日级日期不能冒充专有字段。
4. D06只能靠硬件实测支持微秒性能；虚拟延迟仅测流程。D10部分问题本质不可识别，应给条件/区间而非等待“万能字段”。

## 就绪与完成规则

`design_ready`表示题面契约齐全；`synthetic_input_ready`表示基础合成输入可用；专用配方和独立校验通过时，`generator_implemented`的scope为shared_and_question_specific_synthetic_inputs，`exact_node_fault_implemented=true`表示声明的合成节点故障已覆盖。证据见precise-input-validation.json、逐题适配覆盖.csv及逐节点场景覆盖.csv。`dataset_ready`保留为真实/完整节点数据门槛，不能由synthetic自动升档；真实校准仍false。

执行后更新tasks和证据路径，再运行进度与验证。全部任务有证据才归档；归档将已实现的delta同步主specs。未来能力在changes/specs中提出，不能提前复制到主specs冒充现状。

## 使用命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 status --change connect-market-replay-and-calibration
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 validate --all --strict
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-progress.ps1
```

本项目使用OpenSpec官方v2.0.0本地CLI，未生成特定编辑器技能；可直接通过上述命令管理。流程定义参考[官方仓库](https://github.com/Fission-AI/OpenSpec)。
