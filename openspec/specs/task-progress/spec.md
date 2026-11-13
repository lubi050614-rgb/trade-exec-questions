# task-progress Specification

## Purpose
用OpenSpec区分规划工件、实现任务与外部验证的真实进度，记录后续目标依赖和放行证据，保证尚未实现的数据生成或校准不被标为完成。

## Requirements

### Requirement: 记录真实任务进度
项目 SHALL 用proposal、design、specs和tasks记录变更，仅以存在的产物和验收证据勾选任务。

#### Scenario: 只完成生成器规划
- **GIVEN** 生成器proposal和契约已存在
- **WHEN** 更新进度
- **THEN** 计划工件就绪但生成器实现任务未勾选

### Requirement: 目标有依赖与放行条件
路线图 MUST 指定后续目标、依赖、角色、产物和放行条件，外部数据未到位不报告实证完成。

#### Scenario: 尚未连接真实行情
- **GIVEN** 200股5日仅是配置目标
- **WHEN** 生成状态报告
- **THEN** 报告设计可用、数据待核验，真实重放校准保持待实施

### Requirement: 当前范围与延期任务分离
任务进度 SHALL 区分active与deferred范围，延期任务保持原勾选状态但不计入当前待办。

#### Scenario: 用户排除教师阶段
- **GIVEN** 教师生产变更包含8项未完成任务
- **WHEN** 用户明确当前不考虑教师工作且变更标为deferred
- **THEN** 8项继续未勾选，报告显示延期且不计当前待办，数据输入任务保持active
