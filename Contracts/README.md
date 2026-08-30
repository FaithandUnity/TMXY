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
闭包和迁移决定全集。前者还精确绑定 P2-20A.3 的 auxiliary report/policy/schema，必须显式记录闭包内未解析、歧义、结构未决和条件必需缺值，
并只在忽略区保存脱敏成员工作集；资产绑定“显式状态”与歧义/未决的独立零阈值不可互相
替代，等价候选集合保留全部成员且禁止首候选选择。V2 只接受独立权威台账，把 39 个匿名审阅包、机器建议、
正式决定、审批和决定后验证严格分开。证据覆盖完整不等于风险清零或获得批准。

`g2-auxiliary-config-reference-policy-v1.json` 与
`g2-auxiliary-config-reference-v1.schema.json` 冻结 P2-20A.3 的 212 个辅助配置文件实例、
完整标量等值候选和五态适配器边界。候选不是语义引用批准；零匹配不是无引用批准；6 个
malformed XML 不能自动排除；歧义 Package 候选必须全部保留。当前 0 个批准适配器、
0 个批准根，因此成功生成仍是 `BLOCKED`，不能授权 G2、P3 或发布。

`g2-aux-semantic-diagnostics-policy-v1.json` 与
`g2-aux-semantic-diagnostics-v1.schema.json` 冻结 P2-20A.5 的消费者级复算。它把区域字段的
文件、对象和包根语义与 ECF 遗留解析差异分开记录，保留 211 个歧义对象、1 个未解析资源、
3 个换行差异和 6 个 malformed 实例。诊断观察不是语义审批，普通开发授权也不能替代审批。

`g2-aux-ecf-parser-parity-policy-v1.json`、报告 Schema 与匿名明细 Schema 冻结 P2-20A.10
的三层 ECF 复算。A.5 历史证据、冻结 A.3 实际输出、正确明文上的解析器差异分别记录，
不得互相覆盖；两个独立源码派生端口一致不表示执行过旧版运行时或证明二进制等价。
候选投影只能是非改写诊断，不能批准赋值、语义引用、适配器、根、G2 或 P3。

`g2-aux-malformed-xml-diagnostics-policy-v1.json`、报告 Schema 与匿名明细 Schema 冻结
P2-20A.11 的 malformed XML 四层诊断。P2-05/.NET 与独立严格解析器的拒绝结果、TinyXML
2.3.4 源码派生 `LoadFile` 结果和底层 `Parse` 完整性必须分开；API 返回成功不能掩盖部分树，
也不能证明旧二进制、Windows CRT、客户端 C 字符串终止、语义有效性或处置完成。

`g2-asset-binding-recovery-base-plan-v1.tsv` 是 A.8/A.13 共用的 21 行匿名哈希契约。
P2-03/P2-12 的忽略区导出先按各自生成器重建后，A.13 Prepare 可直接读取该契约，而不依赖
忽略区的 A.4/A.7/A.8/Core 链产物；A.8 必须从当前 A.7 重新派生本地计划并证明逐字节相等。
契约不含原始名称或私有路径，且不表示恢复成功、处置批准或 G2/P3 授权。
