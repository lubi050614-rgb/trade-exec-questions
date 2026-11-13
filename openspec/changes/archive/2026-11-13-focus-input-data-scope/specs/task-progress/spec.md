## ADDED Requirements

### Requirement: 当前范围与延期任务分离
任务进度 SHALL 区分active与deferred范围，延期任务保持原勾选状态但不计入当前待办。

#### Scenario: 用户排除教师阶段
- **GIVEN** 教师生产变更包含8项未完成任务
- **WHEN** 用户明确当前不考虑教师工作且变更标为deferred
- **THEN** 8项继续未勾选，报告显示延期且不计当前待办，数据输入任务保持active
