## 1. 审查修复

- [x] 1.1 重建跨通道排序故障，保留局部顺序并独立复算盘口轨迹。
- [x] 1.2 逐题显式配置共享场景，验证申购失败题读取失败数据。
- [x] 1.3 为两个200股题补齐五日专用请求、账户、限额和并发输入。
- [x] 1.4 窗口计数从事件重算，并纠正全量语义就绪声明。
- [x] 1.5 声明实验价格单位并验证整数/小数表示一致。
- [x] 1.6 重建交付物，运行负例、复现、打包及OpenSpec检查。

## 验收证据

- precise-input-validation.json：1725份案例、14项负例、两个原始事件复算节点、两个200股批量题、575份单位契约。
- input-binding-validation.json：1150题绑定与申购失败场景回归通过。
- reproducibility.json / input-reproducibility.json：13个题库输出和1780个输入文件哈希一致。
- input-archive-validation.json：解压读取及确定性重打包通过。
- OpenSpec严格校验通过；113节点语义待审由audit-question-input-semantics单独管理。
