# special-asset-fixtures Specification

## Purpose
以独立合约和业务契约支持衍生品、海外加密、ETF及大宗的工程验证，保留专用语义并阻断由股票代理产生的错误实证结论。

## Requirements

### Requirement: 专用资产契约隔离
系统 SHALL 为期货期权、海外加密、ETF和大宗提供独立业务契约及资产universe，200股只作为背景。

#### Scenario: 期权题缺曲面数据
- **GIVEN** 仅有股票行情与已知Greeks的合成夹具
- **WHEN** 验收组合执行逻辑
- **THEN** 可核对合成敞口，不宣称真实期权执行收益已验证

### Requirement: 保留专用业务语义
系统 MUST 保留合约单位、账户模式、PCF版本、股份来源与确认差异，并阻断证据不足的真实结论。

#### Scenario: ETF只提供指数权重
- **GIVEN** 无基金当日PCF与退补记录
- **WHEN** 构建申赎演练
- **THEN** 使用显式synthetic基金，不把权重或iopv当真实PCF
