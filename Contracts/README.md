# TMXY Contracts

这里保存客户端、后端、工具和数据流水线共同消费的唯一契约源。

- `proto/`：版本化 Protobuf 源文件；
- `data-schema/`：内容、证据和规划报告的封闭 Schema 与策略；
- `generated/`：只允许协议生成器写入，首次生成时再创建。

已经发布的 Protobuf 字段号不得复用。生成代码不能手工修改，也不能在依赖未锁定前提交由不同
protoc 版本产生的临时结果。

P2-19 的 `resource-budget-policy-v1.json` 与
`resource-budget-report-v1.schema.json` 冻结资源预算系数、五类 basis、输出结构和权限边界。
它们允许在缺测显式保留时形成条件规划基线，但不授予价格、工期承诺、G2、可玩性或发布权威。

P2-20 的 `g2-review-policy-v1.json` 与 `g2-review-v1.schema.json` 把 9 条 G2 出口要求
全部固定为 `SATISFIED`，并把当前观测状态分离记录。评审过程通过不能把 `BLOCKED`
决策、未完成任务或 P3 禁止状态解释为批准。
