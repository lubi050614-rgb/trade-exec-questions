# 教师答案生产与蒸馏验收

范围状态：deferred（2026-11-13用户纠正）。用户已确认“答案”是笔误，当前仅做题目＋对应输入。本单只保留历史规划，不启动教师调用、知识卡、蒸馏或学生评测。

## Why

1150道题不等于1150条可训练答案。需有输入证据、教师版本、独立核验和防泄漏切分，避免批量固化错误。

## What Changes

- 先按13管线抽26题试跑，再按通过的模板扩量。
- 分离design_only、synthetic_tested、replay_tested和external_validated证据；各等级不能互相冒充。
- 记录模型/提示/数据版本，按场景族和节点进行分组切分。
- 将核验通过答案压缩为知识卡，保留上游条件、动作、失败与证据边界。

## Capabilities

### New Capabilities

- `teacher-distillation`：可核验教师语料与知识卡生产。

### Modified Capabilities

无。

## Impact

依赖题库治理；设计题试跑可先做，执行题须对应数据夹具。模型接口和预算未配置，不能视为教师已调用。
