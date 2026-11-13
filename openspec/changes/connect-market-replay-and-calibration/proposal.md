# 接入真实行情重放与外部校准

## Why

机制夹具能验证工程，但不能证明实际覆盖、排队、冲击与硬件性能。需要将已有ClickHouse行情通过质量审计接入，并把不可识别边界保留下来。

## What Changes

- 只读覆盖/语义审计，冻结200股5日manifest，输出缺口和不可用原因。
- 分片抽取与局部有序回放，checkpoint/quality门控。
- 队列三档、延迟/冲击范围、竞价事件适配与外部样本校准。
- 无真实自有成交或硬件时明确calibration_pending/hardware_pending。

## Capabilities

### New Capabilities

- `market-replay`：质量门控的市场数据重放与证据分级。

### Modified Capabilities

无。

## Impact

依赖业务MVP的状态和manifest；真实覆盖审计可先行。需要数据工程提供只读连接或脱敏文件，不在仓库保存凭据，不执行真实订单。
