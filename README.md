# 交易执行知识树衍生题库

面向量化交易执行知识蒸馏的题库与实验设计：13 个管线、115 个技术节点，每节点 10 题，共 1,150 题。

当前v2已明确逐节点数据契约与任务依赖，**业务数据生成器、真实数据接入和教师答案仍待实施**。下一步是[业务夹具MVP](openspec/changes/build-execution-fixture-mvp/tasks.md)。

## 主要文件

- [设计建议与数据缺口](deliverables/设计建议与数据缺口.md)：问题设计、200 股 × 5 日方案、12 类缺失数据、模拟方法与开源参考。
- [完整题库](deliverables/交易执行_1150题.md)：可阅读版本。
- [CSV 题库](deliverables/交易执行_1150题.csv)：用于筛选与标注。
- [教师输入 JSONL](deliverables/交易执行_教师输入.jsonl)：每行一个问题，包含提示词、相关字段和缺失数据说明；答案待生成。
- [数据覆盖审计 SQL](deliverables/数据覆盖审计.sql)：尚未在数据库执行的只读查询模板。
- [覆盖统计](deliverables/coverage.json)及[验证结果](deliverables/验证结果.txt)。
- [数据缺口登记](deliverables/数据缺口登记表.md)及[CSV](deliverables/数据缺口登记表.csv)：12类缺口的字段、真实/合成方案、角色、验收和任务。
- [节点数据契约](deliverables/节点数据契约.csv)：115节点的精确依赖、不变量、故障和独立oracle。
- [目标与路线图](openspec/ROADMAP.md)、[任务进度](deliverables/任务进度.md)和[就绪状态](deliverables/题库就绪度.md)。

`execution-source.json` 保存交易执行分支的原始节点；`question-seeds.txt` 保存逐节点具体问题；`build-deliverables.ps1` 用于生成题库。

## 生成方法

默认读取仓库`data/schema`中的字段快照；`config/data-gaps.json`与`config/node-contracts.txt`是缺口和节点契约来源。无需原作者桌面路径。可用`-SchemaDirectory`和`-OutputDirectory`指定其他目录。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-deliverables.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-question-bank.ps1 -SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-progress.ps1
```

## 使用边界

本项目尚未连接 ClickHouse、生成教师答案或执行实盘操作。200 股 × 5 日是建议的工程演练配置，实际数据覆盖待核验。工程仿真通过不等于真实成交概率、冲击和收益效果已经得到验证。

Q01—Q05 为逐节点具体技术题；Q06—Q10 为绑定节点上下文的数据、验收、故障、反事实与证据边界题。

## OpenSpec任务管理

使用项目内官方CLI v2.0.0，不提交二进制、不修改系统PATH。首次在新机器运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-openspec.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 instructions apply --change build-execution-fixture-mvp --json
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 validate --all --strict
```

`status`中的planning/artifact完成不代表实现任务完成；实际勾选见tasks.md和任务进度。后续顺序为业务夹具→真实重放/校准→专用资产→教师试跑及蒸馏，独立任务可按路线图前置条件推进。
