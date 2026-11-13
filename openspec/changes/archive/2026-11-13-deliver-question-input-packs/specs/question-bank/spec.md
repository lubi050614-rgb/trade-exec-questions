## ADDED Requirements

### Requirement: 合成输入与真实就绪分开
题库 SHALL 单独报告synthetic_input_ready并关联已验证输入manifest，不因生成合成数据就把真实dataset_ready或real_calibration_ready设为true。

#### Scenario: 合成输入已交付
- **GIVEN** 某题关联文件通过输入校验但真实数据库未连接
- **WHEN** 输出题库状态
- **THEN** 合成输入可用，真实数据/校准仍待证据，题库不输出该题答案
