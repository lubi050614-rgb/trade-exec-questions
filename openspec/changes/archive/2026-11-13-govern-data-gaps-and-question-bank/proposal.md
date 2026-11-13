# 数据缺口治理与题库升级

## Why

现有缺口按管线粗分，题库缺少节点级可验收契约；规划、生成器和真实数据就绪容易混淆。需把115节点的题目、缺口、解决办法和后续任务关联起来。

## What Changes

- 建立12类缺口登记：最小字段、真实/合成路径、角色、验收及禁止结论。
- 为115节点建立不变量、故障、独立验收和数据/任务依赖。
- 保留1150个问题ID，共性题独立化，增加就绪状态和分组字段。
- 保存仓库schema快照，移除桌面路径依赖。
- 用OpenSpec跟踪本次交付与四个后续变更。
- 本次不实现行情抽取、业务数据生成器或教师推理。

## Capabilities

### New Capabilities

- `data-gap-registry`：缺口、解决路径和证据边界的可追溯契约。
- `question-bank`：稳定ID、独立题面、节点验收和可重建题库。
- `task-progress`：任务状态、依赖与真实完成证据。

### Modified Capabilities

无，首次建立规范基线。

## Impact

修改config、构建器、CSV/JSONL和报告，新增scripts、schema快照与OpenSpec。JSONL增加字段，保留原核心字段。CLI为官方v2.0.0项目内二进制，校验SHA256。
