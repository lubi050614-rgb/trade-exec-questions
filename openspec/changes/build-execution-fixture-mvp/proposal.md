# 业务数据夹具MVP

## Why

题库缺少可执行的自身目标、回报和账户样本。先覆盖D01—D05的机制验证，才能开展工程题的批量验收。

## What Changes

- 构建确定性synthetic目标、账户、订单生命周期及故障交付数据。
- 200股、5个显式测试交易日；真实模式的日期必须来自已验证日历。
- 同一seed复现，物理真值与策略可见事件分开；金额用整数最小单位，价格用tick。
- 提供独立参考账本、状态断言、场景manifest和反例回归。
- 不接真实交易，不声称实盘成交概率、费用、规则或收益已校准。

## Capabilities

### New Capabilities

- `execution-fixtures`：自有业务机制夹具、因果故障与可验证账本。

### Modified Capabilities

无。

## Impact

计划新增src/fixtures、测试、命令行和data/generated运行输出。依赖当前治理基线；数据源角色提供真实快照时另经脱敏接入。当前只是计划。
