# 交易执行数据与题库路线图

更新：2026-11-13。任务勾选以各变更单tasks.md为准；自动计数见[任务进度](../deliverables/任务进度.md)。OpenSpec工件就绪表示计划可实施，不表示代码、数据或实证已完成。

## 最终目标

形成从“节点 → 问题 → 最小字段与缺口 → 数据/故障样本 → 独立验收 → 教师答案 → 知识卡”的可追踪链路。工程题以200标的5日作为批量验收目标，短小手算例验证核心机制；市场质量结论只在相应真实证据到位后放行。

## 当前边界

- 已有：25表schema、115节点/1150题、12类缺口方案、逐节点契约、构建器和校验器。
- 尚无：真实ClickHouse抽取结果、业务数据生成器、实际200股5日样本、真实自身订单/账户、专用资产数据、教师答案。
- 本次治理变更完成后归档；未来实现任务保持未勾选，不因为本次规划而自动启动实盘或付费模型调用。

|阶段/优先级|变更单|依赖/负责角色|主要产物|放行条件|
|---|---|---|---|---|
|M0，本次|govern-data-gaps-and-question-bank|执行研究/研发|缺口登记、节点契约、题库v2、规范、进度与校验|115节点各10题，字段与任务合法，负例拒绝，确定性及OpenSpec严格验证通过|
|M1，P0，下一步|[build-execution-fixture-mvp](changes/build-execution-fixture-mvp/tasks.md)|M0；执行/通道研发，运营供账本口径|D01—D05的目标、事件、账户、假柜台与10类故障；200合成标的5日manifest|因果有效、真值隔离、独立账本守恒、重复/超量/过早解冻负例拒绝，同seed复现|
|M2，P1|[connect-market-replay-and-calibration](changes/connect-market-replay-and-calibration/tasks.md)|审计可先行；回放依赖M1；数据/合规/执行研究/低延迟研发|真实覆盖、冻结universe、分片重放、D07/D10/D06证据报告|真实来源/语义核验，质量门控，完成率+全目标IS，独立自有样本与硬件按需验证|
|M3，P2|[add-special-asset-fixtures](changes/add-special-asset-fixtures/tasks.md)|M1；各资产与通道研发/运营/合规|D08/D09/D11/D12独立资产和协议夹具|乘数币种时段、双腿/权益/PCF/股份批次正确，专用结论不由股票代理支撑|
|M4，分批|[run-teacher-distillation](changes/run-teacher-distillation/tasks.md)|设计试跑依赖M0；执行题依赖相应M1/M2/M3；模型工程/执行研究|26题试跑→1150题核验答案→知识卡→学生未见集评测|字段/时间/状态/证据硬失败先清除，同族隔离，教师版本与输入哈希留痕|

角色是建议责任范围，尚未指派具体人员。任务编号、产物、前置和验收详见各tasks。没有真实源/权限时，应先做不依赖它的契约与夹具，不能虚构连接结果。

## 数据缺口决策

1. D01—D03优先：优化器/柜台真实导出最好；暂无时按机制向前造synthetic，不从因子反演。
2. D04—D05先写test_only规则和假柜台以练工程，再补真实来源与版本；两者不是合规或生产能力证明。
3. D07/D08/D09/D11/D12补专用源或独立契约夹具；股票、指数权重、日级日期不能冒充专有字段。
4. D06只能靠硬件实测支持微秒性能；虚拟延迟仅测流程。D10部分问题本质不可识别，应给条件/区间而非等待“万能字段”。

## 就绪与完成规则

`design_ready`是题面可独立作答；`dataset_ready`需要相应输入通过契约与质量校验；`generator_implemented`需要可运行代码和测试；`real_calibration_ready`需要外部独立证据。当前后三项均false。

执行后更新tasks和证据路径，再运行进度与验证。全部任务有证据才归档；归档将已实现的delta同步主specs。未来能力在changes/specs中提出，不能提前复制到主specs冒充现状。

## 使用命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 status --change build-execution-fixture-mvp
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 validate --all --strict
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-progress.ps1
```

本项目使用OpenSpec官方v2.0.0本地CLI，未生成特定编辑器技能；可直接通过上述命令管理。流程定义参考[官方仓库](https://github.com/Fission-AI/OpenSpec)。
