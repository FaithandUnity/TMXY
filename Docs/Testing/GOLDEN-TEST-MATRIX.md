# P1 黄金测试总矩阵

## 目的

P1-27 把格式读取器、资产中间格式和 UE Editor 导入器的测试收敛到一个机器可读总矩阵。矩阵不是测试结果的替代品；它把每类风险绑定到实际测试源码、可执行门禁和机器报告，防止只有文档描述而没有进入本地 CI 聚合入口。

权威矩阵为 `Data/GoldenSamples/p1-golden-test-matrix-v1.json`，结构由 `Contracts/data-schema/golden-test-matrix-v1.schema.json` 约束，验证入口为 `Tests/Contract/Test-GoldenTestMatrix.ps1`。

## 四类强制覆盖

每个受控领域必须各有至少一个以下分类，且 Case ID 全局唯一：

- `normal`：已知合法的合成或真实黄金样本成功读取、导出或导入；
- `boundary`：空集合、最小/最大结构、分配上限、规范路径或幂等重导入等边界有明确结果；
- `corrupt`：截断、非法数值、结构不一致或哈希不一致必须稳定拒绝且不得产生部分资产；
- `unknown`：未知版本、属性、尾部或格式必须按既定策略保留或失败关闭，不得静默猜测。

`unknown` 不表示所有输入都必须接受。可无损往返的 Package 属性或未知 body 应保留；没有可证明边界的版本、尾部、格式和扩展应稳定拒绝。

## 进入门禁的领域

矩阵覆盖 Package 容器、老 TBL、QTX、SM、SKEM、ANIM、TER、资产中间格式以及 UE Editor Importer。每个 Suite 同时声明：

- 含真实断言文本的测试源码；
- 在本地质量聚合中实际调用的 PowerShell 门禁；
- 由门禁生成的 `Data/BuildBaseline` 报告；
- 是否要求完成标志和 Headless UE Automation 证据。

总矩阵门禁会验证 Schema、领域/分类完整性、源码断言标记、脚本的聚合入口绑定、报告结果、完成标志和 Automation 状态，并把所有输入 SHA-256 写入 `Data/BuildBaseline/p1-27-golden-test-matrix.json`。

## 维护规则

新增格式或 UE 资产 Handler 时，必须在同一变更中加入四类覆盖、对应可执行门禁和机器报告绑定。修改测试断言、门禁脚本或报告后必须重新运行总矩阵；只修改矩阵描述但没有可执行源码标记与 PASS 报告不能通过。

P1-09 的新版 TBL 最终运行时参数仍未获得授权证据，因此不伪装为已完成 Suite；当前矩阵只纳入已完成的老 TBL 参考读取链。托管 CI 的发布权威仍由 P0-12/P0-16 管理，本矩阵只证明本地、可重复的质量门禁已接线。
