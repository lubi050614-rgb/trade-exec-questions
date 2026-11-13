# 交易执行知识树衍生题库

面向量化交易执行知识蒸馏的题库与实验设计：13 个管线、115 个技术节点，每节点 10 题，共 1,150 题。

当前只交付**题目＋对应输入数据，不生成答案**。1150题各有独立案例，前五题共575个专用实验；115节点各有正常、故障、恢复证据、缺证、中性表达5类场景。共享背景为200个SYN标的5日。原始事件语义复算目前覆盖P02-S01、P11-S05，其余113节点保持待审；文件完整性和声明关系检查不代表全量语义验收。真实行情、真实柜台与硬件证据仍待提供。

## 主要文件

- [设计建议与数据缺口](deliverables/设计建议与数据缺口.md)：问题设计、200 股 × 5 日方案、12 类缺失数据、模拟方法与开源参考。
- [完整题库](deliverables/交易执行_1150题.md)：可阅读版本。
- [CSV 题库](deliverables/交易执行_1150题.csv)：用于筛选与标注。
- [题目与数据输入 JSONL](deliverables/题目与数据输入.jsonl)和[输入索引 CSV](deliverables/题目输入索引.csv)：每题绑定实际存在的文件、小案例、可见时间和支持范围，不包含答案。
- [数据包使用说明](deliverables/输入数据使用说明.md)及[完整合成输入 ZIP](deliverables/执行输入数据_200标的5日.zip)。
- [历史兼容 JSONL](deliverables/交易执行_教师输入.jsonl)：旧格式问题与作答要求，未生成答案；当前入口为上方题目与数据输入索引。
- [数据覆盖审计 SQL](deliverables/数据覆盖审计.sql)：尚未在数据库执行的只读查询模板。
- [覆盖统计](deliverables/coverage.json)及[验证结果](deliverables/验证结果.txt)。
- [数据缺口登记](deliverables/数据缺口登记表.md)及[CSV](deliverables/数据缺口登记表.csv)：12类缺口的字段、真实/合成方案、角色、验收和任务。
- [节点数据契约](deliverables/节点数据契约.csv)：115节点的精确依赖、不变量、故障和独立oracle。
- [语义待审节点](deliverables/语义待审节点.csv)：113节点的后续审查清单。
- [逐题精准适配说明](deliverables/逐题精准适配说明.md)、[逐题覆盖](deliverables/逐题适配覆盖.csv)、[节点场景覆盖](deliverables/逐节点场景覆盖.csv)：专用输入来源、五题样本及逐项校验证据。
- [目标与路线图](openspec/ROADMAP.md)、[任务进度](deliverables/任务进度.md)和[就绪状态](deliverables/题库就绪度.md)。

`execution-source.json` 保存交易执行分支的原始节点；`question-seeds.txt` 保存逐节点具体问题；`build-deliverables.ps1` 用于生成题库。

## 生成方法

默认读取仓库`data/schema`中的字段快照；`config/data-gaps.json`与`config/node-contracts.txt`是缺口和节点契约来源。无需原作者桌面路径。可用`-SchemaDirectory`和`-OutputDirectory`指定其他目录。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-deliverables.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-question-bank.ps1 -SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/update-progress.ps1
```

生成题目及配套输入的一键入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-question-inputs.ps1 -Overwrite
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/read-question-input.ps1 -QuestionId P01-S01-Q01 -MetadataOnly
```

默认输出`data/generated/execution-inputs-v1`，目录不入Git；可下载上方ZIP解压到该目录。全部为synthetic/test_only，分钟数据24万条，原始逐笔和盘口为采样重置块；不宣称完整真实L3。

## 使用边界

本项目未连接真实ClickHouse或执行实盘操作，当前不生产答案。200个合成标的×5个测试日期已实际生成并验证；真实市场覆盖仍待核验。输入质量通过不等于真实成交概率、冲击、生产执行或收益已验证。

Q01—Q05 为逐节点具体技术题；Q06—Q10 为绑定节点上下文的数据、验收、故障、反事实与证据边界题。

## OpenSpec任务管理

使用项目内官方CLI v2.0.0，不提交二进制、不修改系统PATH。首次在新机器运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-openspec.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 list
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 list --specs
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/openspec.ps1 validate --all --strict
```

`status`中的planning/artifact完成不代表实现任务完成；实际勾选见tasks.md和任务进度。当前数据实施顺序为业务夹具→真实重放/质量审计→专用资产输入；教师试跑及蒸馏为deferred，不计当前待办。
