# 交易执行知识树衍生题库

面向量化交易执行知识蒸馏的题库与实验设计：13 个管线、115 个技术节点，每节点 10 题，共 1,150 题。

## 主要文件

- [设计建议与数据缺口](deliverables/设计建议与数据缺口.md)：问题设计、200 股 × 5 日方案、12 类缺失数据、模拟方法与开源参考。
- [完整题库](deliverables/交易执行_1150题.md)：可阅读版本。
- [CSV 题库](deliverables/交易执行_1150题.csv)：用于筛选与标注。
- [教师输入 JSONL](deliverables/交易执行_教师输入.jsonl)：每行一个问题，包含提示词、相关字段和缺失数据说明；答案待生成。
- [数据覆盖审计 SQL](deliverables/数据覆盖审计.sql)：尚未在数据库执行的只读查询模板。
- [覆盖统计](deliverables/coverage.json)及[验证结果](deliverables/验证结果.txt)。

`execution-source.json` 保存交易执行分支的原始节点；`question-seeds.txt` 保存逐节点具体问题；`build-deliverables.ps1` 用于生成题库。

## 生成方法

生成脚本读取本机原始字段文件 `columns.csv` 和 `observed-schema.json`，当前路径位于 `C:\Users\EDY\Desktop\quantdocs`。在其他机器运行前需调整脚本中的这两处输入路径，并准备对应文件。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-deliverables.ps1
```

## 使用边界

本项目尚未连接 ClickHouse、生成教师答案或执行实盘操作。200 股 × 5 日是建议的工程演练配置，实际数据覆盖待核验。工程仿真通过不等于真实成交概率、冲击和收益效果已经得到验证。

Q01—Q05 为逐节点具体技术题；Q06—Q10 为绑定节点上下文的数据、验收、故障、反事实与证据边界题。
