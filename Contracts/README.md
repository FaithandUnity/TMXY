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

`g2-core-resource-closure-policy-v1.json`、`g2-core-resource-closure-v1.schema.json` 与
G2-07 的 V1 基线及 V2 policy/registry/authority/review-packet Schema 分别冻结核心资源
闭包和迁移决定全集。前者必须显式记录闭包内未解析、歧义、结构未决和条件必需缺值，
并只在忽略区保存脱敏成员工作集；资产绑定“显式状态”与歧义/未决的独立零阈值不可互相
替代，等价候选集合保留全部成员且禁止首候选选择。V2 只接受独立权威台账，把 39 个匿名审阅包、机器建议、
正式决定、审批和决定后验证严格分开。证据覆盖完整不等于风险清零或获得批准。
