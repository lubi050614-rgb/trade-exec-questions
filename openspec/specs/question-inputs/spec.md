# question-inputs Specification

## Purpose
为每道交易执行题提供可复现、来源清楚、可读取的数据输入，区分合成工程输入和未取得的真实市场证据，不生成题目答案。

## Requirements

### Requirement: 冻结的合成输入数据
输入生成器 SHALL 生成200个显式合成标的和5个测试日期，记录单位、规则范围、seed、文件哈希和真实源缺口。

#### Scenario: 未提供真实行情行
- **GIVEN** 仓库只有字段文档
- **WHEN** 运行默认输入生成器
- **THEN** 生成SYN标识和synthetic来源，不宣称这些是ClickHouse真实200股数据

### Requirement: 逐题可读取且无答案
系统 MUST 为1150个稳定题目ID提供存在且可验证的输入文件、过滤条件和可见时间策略，不导出答案或内部真值作为问题输入。

#### Scenario: 单独读取某题
- **GIVEN** 一个question_id和已生成的数据目录
- **WHEN** 读取该题输入
- **THEN** 返回题目、输入引用及数据行，路径不含内部真值，结果不含标准答案字段

### Requirement: 输入一致性与确定性
系统 SHALL 验证行情量额、事件因果、库存和现金的机制一致性，并保证相同配置和seed的输出哈希一致。

#### Scenario: 重复交付成交
- **GIVEN** 一个物理成交被重复交付
- **WHEN** 独立校验器聚合可见事件
- **THEN** 该成交只记账一次，破坏性重复分录不得通过校验
