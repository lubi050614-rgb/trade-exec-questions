# question-bank Specification

## Purpose
提供稳定覆盖115个交易执行技术节点的独立作答题库，使每题的数据依赖、验收不变量、故障、独立参考和就绪状态可追溯，并能从仓库快照确定性重建。

## Requirements

### Requirement: 稳定覆盖与独立作答
系统 SHALL 保留13管线115节点的1150个问题ID，每节点10题，每题含独立契约、缺口和不依赖其他题答案的题面。

#### Scenario: 单独抽取故障题
- **GIVEN** 教师只收到Q08这一条JSONL
- **WHEN** 读取题面
- **THEN** 可获得故障、不变量、参考验收和数据边界，无需其他题答案

### Requirement: 节点验收与状态
系统 MUST 提供节点不变量、故障、独立参考、任务关联、分组标识及设计/数据/生成器/校准状态。

#### Scenario: 设计完成而生成器未实现
- **GIVEN** 仅有缺口方案和题库
- **WHEN** 构建题库
- **THEN** design_ready为true，其余就绪为false，default_status为design_only

### Requirement: 可移植确定性构建
系统 SHALL 从仓库schema重建并验证字段和ID覆盖。

#### Scenario: 跨目录重复构建
- **GIVEN** 相同源和schema
- **WHEN** 指定不同输出目录构建两次
- **THEN** 输出哈希相同且无桌面路径依赖
