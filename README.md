# TMXY Rebuild

本目录用于《天命西游／QQ西游》重构工程的新代码、工具、数据描述和测试产物。

## 原始输入规则

以下目录是重构证据源，按只读输入处理：

- `E:\QQXYCodeDev\ClientCode`
- `E:\QQXYCodeDev\ServerCode`
- `E:\QQXYCodeDev\ToolCode`
- `E:\QQXYCodeDev\DevDoc`
- `E:\QQXYCodeDev\天命西游`

不得在这些目录内执行格式转换、批量改名或修复。所有派生结果写入 `Rebuild`。

## 当前目录

```text
Rebuild/
├─ .github/                     CODEOWNERS、8 个稳定检查与受保护 provenance 工作流
├─ Apps/UEClient/                UE 5.8.2 C++ 客户端工程
├─ Backend/                      Linux/C++20 后端模块和应用
│  └─ adapters/persistence_postgres/ PostgreSQL Migration 与后续 libpq 唯一边界
├─ Contracts/                    Protobuf、数据 Schema、资产交换注册表与规范示例唯一来源
├─ Deploy/                       Compose、容器和生产部署清单
├─ Tests/                        跨模块契约、集成、Golden 与性能测试
├─ Tools/TMXY.Manifest/          输入清单工具
├─ Tools/TMXY.BuildInventory/    老工程与构建环境盘点工具
├─ Tools/TMXY.Toolchain/         最终工具链环境检测与锁定验证
├─ Tools/TMXY.GoldenSamples/     黄金样本引用基线生成与源文件校验
├─ Tools/TMXY.Security/          Secret 工作树/历史扫描与泄漏门禁
├─ Tools/TMXY.SupplyChain/       本地镜像 SBOM 与供应链证据校验
├─ Tools/TMXY.GitHub/            GitHub 托管 CI 状态只读采集与脱敏证据
├─ Tools/TMXY.FormatCore/        P1 有界二进制读取与稳定错误契约
├─ Tools/TMXY.Package/           Package 头解析、边界验证与格式指纹
├─ Tools/TMXY.Table/             TBL 解码/盘点及 XML、ClassCfg 非表配置清单
├─ Tools/TMXY.Transform/         遗留坐标、单位、矩阵、UV 与绕序的 UE 单一转换边界
├─ Tools/TMXY.Texture/           Package 元数据与 qtx mip 解析、Alpha 分析和纹理中间输出
├─ Tools/TMXY.StaticMesh/        Package 材质绑定、sm 有界解析及静态网格审查中间输出
├─ Tools/TMXY.SkeletalMesh/      Package 骨架绑定、skem 权重/部件解析及骨骼网格审查输出
├─ Tools/TMXY.Animation/         Package 动画元数据绑定、anim 轨道/Key 与 Root Motion 审查输出
├─ Tools/TMXY.Terrain/           ter 地形 Tile 的高程、层 Alpha、水体和完整边缘导出
├─ Data/RawManifests/            Manifest 与摘要
├─ Data/GoldenSamples/           只存元数据的黄金样本引用集
├─ Data/BuildInventory/          工程、链接依赖和环境 JSON
├─ Data/BuildBaseline/           新工程可重复构建验证结果
├─ Data/Toolchain/               工具链锁定清单与主机环境快照
├─ Data/Security/                脱敏后的安全门禁报告
├─ Data/Performance/             平台、容量和性能预算基线
├─ Data/Inventory/               脱敏后的格式、表和依赖全量证据
├─ Data/Exports/                 Git 忽略的可重建批量明文/转换产物
├─ Docs/Governance/              权利与治理基线
├─ Docs/Build/                   构建依赖与可编译性报告
├─ Docs/Architecture/            已冻结的最终技术架构
├─ Docs/Standards/               强制工程与代码规范
├─ Docs/Formats/                 格式证据、样本边界与重构记录
├─ Docs/Security/                Secret 注入、脱敏、轮换与事件规则
├─ Docs/Waivers/                 有时限、可审计且默认不生效的风险例外请求
├─ Docs/Performance/             客户端/后端容量、延迟和恢复目标
├─ Docs/Database/                PostgreSQL Migration、所有权和验证规则
└─ Docs/ADR/                     已接受和待评审的架构决策
```

辅助资源不建立空模块：ZIF、声音、UI、Shader 和字体的已验证分类、优先级及后续处理路线见
`Docs/Formats/AUXILIARY-ASSET-INVESTIGATION.md`，机器证据由
`Tests/Contract/Test-AuxiliaryAssetInvestigation.ps1` 重扫只读客户端后生成。

P1 资产交换统一使用 `manifest.json` + 独立哈希载荷；Schema、格式注册表、示例、版本与
未知字段保留规则见 `Docs/Formats/ASSET-INTERCHANGE-V1.md`。OBJ/PNG/TGA/CSV 只作审查，
不得被导入器当作权威输入。

P2 表数据统一由 `Tools/TMXY.Table/New-ThreeLayerTableData.ps1` 生成三层产物：忠实
`raw.csv`、UTF-8 `normalized.jsonl` 与逐表 `schema.yaml`。批量内容只保留在
`Data/Exports/P2-06`；Git 仅跟踪生成器、Schema 合同、格式说明和无字段值的哈希证据。
P2-06 的类型和主键仍是结构候选，P2-07/P2-08 才负责权威语义与所有权决策。

P2-07 由 `Tools/TMXY.Table/New-CoreTableSchema.ps1` 将其中 12 张首个可玩切片核心表
升级为冻结构建的权威导入合同。`Data/Schemas/core-table-registry-v1.json` 为 355 列
记录类型、null 和闭区间/UTF-8 长度规则，并验证 12 个主键与 14 条零悬空严格引用；
完整口径、重复行折叠与版本升级规则见 `Docs/Formats/CORE-TABLE-SCHEMA.md`。所有权和
热加载仍由 P2-08 决定。

P2-08 由 `Tools/TMXY.Table/New-TableOwnershipRegistry.ps1` 将“观察到的消费者”、
Schema 所有者和运行时权威拆开记录。225 张活动表全部分类为 117 张客户端展示目录与
108 张共享/服务端权威目录；12 张核心表的 355 列进一步分为客户端展示/本地化、服务端
规则和共享标识符。客户端持有数据副本不授予战斗、经济或进度决定权，详见
`Docs/Formats/TABLE-OWNERSHIP.md`。

P2-12 由 `Tools/TMXY.AssetInventory/New-FullAssetInventory.ps1` 在锁定 Clang 21 容器中
复用五个生产解析器，全量分类冻结客户端的 40,090 个 QTX/SM/SKEM/ANIM/TER/ZIF/WAV/
MP3 文件。逐文件目录位于 Git 忽略的 `Data/Exports/P2-12`，Git 仅跟踪扫描器、合同、
格式说明和不含 payload/解码资产的汇总证据；缺失的 headerless 描述、Package 副本歧义
和可独立确认的结构失败分别保留，详见 `Docs/Formats/FULL-ASSET-INVENTORY.md`。

P2-13 由 `Tools/TMXY.ReferenceClosure/New-ReferenceClosure.ps1` 把核心表、Package 对象图
和完整资产目录连接成可复现的跨域引用闭包。忽略目录中的 683,355 行图可从角色、场景和
技能根查询；Git 仅跟踪脱敏合同和汇总证据。14 条权威核心外键的 55,361 个活动物理引用
保持零悬空；可空旧版展示指针、同名歧义和未解析候选均保留为显式工作队列，不能被误报为
权威外键或静默选择，详见 `Docs/Formats/REFERENCE-CLOSURE.md`。

P2-14 由 `Tools/TMXY.AssetHealth/New-AssetHealthReport.ps1` 对 40,090 个资产做完整源哈希
重复分析和角色/场景/技能根可达性分类。相同解析指标但不同哈希的资源只列为结构审查候选，
不宣称语义等价；根不可达、无 Package 匹配或尚无身份规则也都不等于可删除。逐资产报告
位于 Git 忽略的 `Data/Exports/P2-14`，详见 `Docs/Formats/ASSET-HEALTH.md`。

P2-15 由 `Tools/TMXY.ConversionRouting/New-ConversionRouting.ps1` 为全部 40,090 个资产冻结
五条转换路线、三档执行层级、四档交付优先级和显式规划系数。完整哈希相同且格式可独立解析的
资源可保留路径别名并复用转换结果；依赖外部描述的 QTX/ANIM 不据 payload 相同而错误复用。
逐资产路线位于 Git 忽略的 `Data/Exports/P2-15`，详见 `Docs/Formats/CONVERSION-ROUTING.md`。

P2-16 由 `Tools/TMXY.ConversionCache/New-ConversionCachePlan.ps1` 为 33,801 个就绪转换作业
生成内容寻址键，并让 5,489 个路径别名共享明确代表键。键绑定源载荷、解释记录、描述符范围、
转换器、中间格式、路由策略和目标配置；时间戳不参与。800 个人工项在缺少人工决策摘要时
禁止缓存命中，任何输出还必须逐项验长度和 SHA-256，详见 `Docs/Formats/CONVERSION-CACHE.md`。

P2-09 由 `Tools/TMXY.TableDiff/New-LegacyCurrentDiff.ps1` 将只读 DevDoc 中 52 张已解密
旧 CSV 与当前 P2-06 数据逐表比较。旧快照没有可证明 build，因此仅以完整哈希清单标识；
表头、列类型/分布候选、行多重集、10 个核心主键域和 12 条可比较外键均形成可查询差异，
不复制旧行或把观察众数伪称默认值，详见 `Docs/Formats/LEGACY-CURRENT-TABLE-DIFF.md`。

P2-10 由 `Tools/TMXY.CanonicalId/New-CanonicalIdMap.ps1` 为 12 个 P2-07 核心域冻结类型化、
按表命名空间隔离的 Canonical ID。共享和当前新增 ID 不重编号，旧版独有 ID 永久保留为
Tombstone；旧版类型例外不强制转换，冲突必须显式评审。完整键映射只留在 Git 忽略的
`Data/Exports/P2-10`，详见 `Docs/Formats/CANONICAL-ID-MAP.md`。

P2-11 由 `Tools/TMXY.IdLimitAudit/New-IdLimitAudit.ps1` 审计全部 Canonical ID 分量的位宽、
稀疏率、u8/u16、等级上限、字符串与 Tombstone 风险，并只读扫描三个旧源码根中的等级、
槽位和固定容量信号。精确极值和旧路径只留在 Git 忽略的 `Data/Exports/P2-11`，详见
`Docs/Formats/ID-LIMIT-AUDIT.md`。

PostgreSQL/gosu 的 WVR-0002 当前仅是待所有者决策的草案。机器判定器会绑定精确镜像、
二进制、22 项发现与全部上游证据；只有最长 30 天的有效区间、GitHub 当前 HEAD 上两个
非作者审批和只读认证 API 复核同时成立时，才允许组件级临时例外。负责人若是 PR 作者，
必须在精确请求中显式授权；否则其当前 HEAD 审批必须属于两项审批之一。
离线夹具永远不能激活例外，且该例外本身不授予合并、G0/G1 或发布权。

最终目录和依赖边界见 `Docs/Architecture/TARGET-ARCHITECTURE.md`。后续目录按首个真实文件逐步建立，不提前生成无内容的工程。

## 版本控制

Git 仓库根目录固定为本目录，父目录和五个只读输入目录不得初始化或纳入仓库。分支保护、Commit/PR、强制评审、Secret、生成物和 Git LFS/对象存储边界见 `Docs/Governance/VERSION-CONTROL-POLICY.md`。
