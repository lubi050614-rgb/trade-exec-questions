# execution-fixtures Specification

## Purpose
生成可复现、因果有效且真值隔离的交易执行业务夹具，以独立参考验收订单、账户和故障恢复，不冒充真实市场执行效果。

## Requirements

### Requirement: 确定性业务夹具
生成器 SHALL 从版本化配置生成200标的5日目标、订单和账户事件，显式标记synthetic并记录seed和manifest。

#### Scenario: 同配置重复生成
- **GIVEN** 相同配置、规则、版本和seed
- **WHEN** 运行生成器两次
- **THEN** 数据及manifest内容哈希相同，实际数量和日期可核对

### Requirement: 因果有效与观测隔离
生成器 MUST 分离物理事件、可见交付层和真值，重复交付不新增成交。

#### Scenario: 成交先于ACK到达
- **GIVEN** 订单已在物理层受理成交
- **WHEN** 客户端先收到成交再收到ACK及重复成交
- **THEN** 仅记一笔成交，最终库存和无故障参考一致

### Requirement: 未决风险和账本守恒
执行夹具 MUST 保留未知受理与未确认撤单的风险占用，并对资金股份提供独立验收。

#### Scenario: 撤单未确认时重规划
- **GIVEN** 仍有200股可能成交的委托
- **WHEN** 撤单请求已发送但确认未到
- **THEN** 这200股继续计入占用，新增派量不能突破母单预算
