# Cross-cutting tests

这里保存跨模块的契约、集成、Golden 和性能测试。模块内部单元测试继续与模块放在一起。

当前第一项是 `Contract/Test-RepositoryLayout.ps1`，用于阻止旧源码依赖、平台/第三方类型泄漏和
未锁定的部署镜像进入新工程。

`Contract/Test-BackendBaseline.ps1` 会进一步验证 Compose，并在禁用网络、只读挂载源码的缓存
Linux 镜像中执行 configure/build/test。当前 GCC 结果仅是诊断证据，Clang 21 仍是发布权威。

`Contract/Test-UEProjectBaseline.ps1 -RunAutomation` 使用锁定的 UE 5.8.2 生成解决方案、编译
`TMXYEditor Win64 Development`、执行 format，并在 NullRHI 下运行 BuildInfo、黄金 Map 和 Importer Automation。

`Contract/Test-UEGoldenHost.ps1` 锁定唯一黄金 Map、导入前后报告 Schema 和 Headless 宿主；
`Contract/Test-UEImporterPlugin.ps1` 验证 Win64 Editor-only 插件、Manifest 批量验证、报告输出、格式处理器注册与
重导入边界；`Contract/Test-UETextureImport.ps1` 验证首个 `microsoft.dds` 生产 Handler、真实/合成 Golden
Fixture、写入前完整性拒绝、BC1/BC3 解码、sRGB/Alpha/mip 观察、固定纹理资产和受限重导入证据。
`Contract/Test-UEStaticMeshImport.ps1` 验证 `khronos.gltf-json` 生产 Handler、真实 SM 派生 Golden
Fixture、glTF/BIN 边界、坐标/法线/绕序、源与渲染顶点、UV/材质段/光照图通道、固定静态网格资产及字节不变重导入。

`Contract/Test-SecretPolicy.ps1` 验证 Secret 文件挂载契约、工作树/可达历史扫描、扫描器阻断自测和不回显规则。`Contract/Test-GoldenSampleBaseline.ps1 -VerifySourceFiles` 则复核只引用黄金样本与只读客户端 SHA-256。

`Contract/Test-FormatCoreBaseline.ps1` 在锁定的 Clang 21 构建器中对 P1 格式基础库执行 format、clang-tidy、编译和 CTest；源码只读挂载、网络禁用，构建输出只进入临时文件系统。

`Contract/Test-PackageV1Baseline.ps1`、`Contract/Test-PackageV2Baseline.ps1` 与 `Contract/Test-PackageV3Baseline.ps1` 分别复核 1.0 单实样、2.0 全部 22 个实样和 3.0 全部 140 个实样的 SHA-256、字段边界、错误定位及解析指纹；原 Package 始终只读且不复制到仓库。

`Contract/Test-PackagePipelineBaseline.ps1` 强制 2.0/3.0 共享目录 codec 的固定向量、四种尾部、偏移映射和 162 个真实目录逐 byte 解码/重编码往返，并确认目录算法不接受 Secret。

`Contract/Test-PackageNormalizedTree.ps1` 验证 Package 1.0/2.0/3.0 的统一 JSON Schema、显式 `unparsed`/`source-span` 边界及三种冻结实样的确定性输出摘要。

`Contract/Test-CurrentTableInvestigation.ps1` 冻结 338 张 TBL 的独立块统计、当前
`QY.exe` double-AES-128 读取链、授权运行时指纹及安全捕获工具契约。它验证 225 张
活动表、三张 GBK 大型代表表和 113 张具有更新替代物的历史影子分类；报告只含指纹
与结构计数，P1-09 由此完成，产品读取器继续由 P1-10 实现。

`Contract/Test-CurrentTableCsvRelation.ps1` 不读取 Secret，而是验证 P1-10 的脱敏机器
证据和生成器安全合同。它冻结当前/残留 item 表相同的 95 列 Schema、27,288 个共有
主键、26,272 个逐 byte 相同行、1,016 个变化行以及 1,935/1 个单侧主键，并强制
`residual_can_replace_current_table=false`。

`Contract/Test-CurrentTableRepresentatives.ps1` 验证 P1-11 脱敏报告和生成器安全合同，
固定 10 张简单/10 张复杂表、20/20 解码、20/20 固定列数、11 张 ASCII/9 张 GBK、
15 张唯一首字段候选和 5 张复合键分类；测试本身不需要读取运行时 Secret。

`Contract/Test-G1FormatReview.ps1` 重新生成并语义比对 P1-28/G1 机器评审，强制
P1-01～P1-27 为 27/27、G1 标准为 8/8、10 个未知项全部有负责人和隔离策略，并
验证项目负责人授权没有越权批准 G0、P0 或发布权威。

`Contract/Test-FullPackageInventory.ps1` 验证 P2-01 的 167 文件全量 Package 清单、
1/22/140 版本分布、163/163 有界解析、121,715 条记录、Manifest/源码绑定，以及
空文件/未知元数据的稳定分类；报告不包含对象/类名，也不复制对象 body。

`Contract/Test-PackageBoundaryCompleteness.ps1` 验证 P2-02 的 163/163 完整边界、
12/12 预选黄金核心包、42,437,084 bytes 零缺口覆盖，以及逐包截断/追加尾字节共
326 次变异全部失败关闭；变异只存在于隔离容器 tmpfs。

`Contract/Test-PackageDependencyGraph.ps1` 验证 P2-03 的 121,715 节点、147,349
条证据驱动引用、19 类覆盖、唯一/歧义/未解析/逻辑名四态，以及 UTF-8 名称、
opaque hex、节点 ID 三种脱敏查询模式；任意字符串不会被猜成依赖边。

`Contract/Test-FullCurrentTableInventory.ps1` 不读取 Secret，验证 P2-04 的 338 张
逐表清单、225/113 活动与历史生命周期、165 ASCII/59 GBK/1 UTF-8、181 固定列/
44 可变列、214,885 个活动数据行，以及每个历史影子的更新替代链接。合同同时强制
报告只含哈希和结构指标，不含 key、表头或字段值。

`Contract/Test-CoreTableSchema.ps1` 验证 P2-07 的 12 张核心表、87,844 个物理行、
87,044 个 Canonical 行、355 列、12 个主键和 14 条严格引用，强制类型/范围/键/外键
违规为 0，并确认职业成长的 800 个重复物理行只按逐行相同策略折叠。加
`-RequireLocalExports` 会从 Git 忽略的 P2-06 明文层完整重建并要求注册表和证据逐 byte
一致；托管 CI 只复核跟踪合同及其哈希链。

`Contract/Test-TableOwnershipRegistry.ps1` 验证 P2-08 的 225 张活动表和 355 个核心列
全部分类，强制 108 张共享表及 307 个服务端/共享核心列保持服务端运行时权威，并确认
48 个客户端列只属于展示或本地化。`-VerifyLegacySources` 会重扫只读客户端/服务端源码
与冻结 ECF，要求注册表和证据逐 byte 一致；默认托管模式只验证跟踪哈希链和安全不变量。

`Contract/Test-FullAssetInventory.ps1` 验证 P2-12 的 40,090 个目标资源和八类逐项汇总，
强制 39,290 个结构通过、786 个 headerless 待解析、14 个独立结构失败、0 个未分类格式，
并复核 Package 等价/分歧候选没有被静默选择。加 `-VerifyLegacySources` 会在锁定 Clang 21
容器中重建扫描器、运行全套 CTest、重新读取约 8.88 GB 目标资源并要求忽略目录和跟踪
证据逐 byte 一致；默认托管模式只验证已提交合同和哈希链。

`Contract/Test-ReferenceClosure.ps1` 验证 P2-13 的 683,355 行跨域闭包、24,465 个角色/
场景/技能查询根、54,561 条去重后的核心外键、147,349 条 Package 引用及 61,511 条
Package 到资产引用；14 条权威核心外键必须零悬空，歧义和未解析候选必须显式保留。
加 `-VerifyDerivedSources` 会从 P2-03、P2-07、P2-12 的本地产物完整重建图并要求逐 byte
一致；默认托管模式只验证已提交合同、策略和哈希链。

`Contract/Test-AssetHealth.ps1` 验证 P2-14 对 40,090 个资产的四态引用分类、1,743 组
完整源哈希重复和 523 组结构审查候选，强制语义等价未经证明为 0、删除建议为 0。
加 `-VerifyDerivedSources` 会从 P2-12 目录和 P2-13 闭包完整重建 42,356 行报告并要求逐
byte 一致；默认托管模式只验证已提交策略、汇总证据和哈希链。

`Contract/Test-ConversionRouting.ps1` 验证 P2-15 对 40,090 个资产的五条路线、三档执行
层级、四档交付优先级、34,601 个转换作业和 5,489 个安全复用别名；QTX/ANIM 的描述符
边界、规划系数口径、零删除和零未分类均为硬断言。加 `-VerifyDerivedSources` 会从 P2-14
完整重建 40,090 行路线报告并要求逐 byte 一致；默认模式验证策略、汇总证据和哈希链。

`Contract/Test-ConversionCache.ps1` 验证 P2-16 的 33,801 个不同就绪键、5,489 个代表键
别名和 800 个人工阻断项，固定单源/单工具/描述符图/路由策略/目标配置的失效范围；夹具同时
证明命中必须验证输出 SHA-256，哈希不符会失败关闭。加 `-VerifyDerivedSources` 会完整重建
40,090 行计划并要求逐 byte 一致。

`Contract/Test-LegacyCurrentDiff.ps1` 验证 P2-09 的 52/52 旧/当前表配对、列/类型/观察
众数哈希、行多重集、10 张核心主键表和 12 条外键规则差异；旧 build 必须保持未知且报告
不得泄露表头、行值或主键。加 `-VerifyDerivedSources` 会只读重扫 DevDoc 快照并逐 byte 复核。

`Contract/Test-CanonicalIdMap.ps1` 验证 P2-10 的 12 个类型化主键域、87,044 个活动 ID、
284 个永久 Tombstone 和 0 个自动重编号/未解决冲突；完整映射与查询输出边界不允许主键
进入 Git。加 `-VerifyDerivedSources` 会只读重建 87,328 条映射并逐 byte 复核。

`Contract/Test-IdLimitAudit.ps1` 验证 P2-11 的 16 个 Canonical ID 分量位宽/稀疏率和
u8/u16/等级/Tombstone 风险，并冻结 8,090 个旧源码文件中的四类固定容量信号统计。
加 `-VerifyDerivedSources` 会通过三个只读挂载重建完整审计并逐 byte 复核。

`Contract/Test-ProtocolCodegen.ps1` 验证 P2-17 的单一核心数据模型、12 个领域强类型 ID、
355 个字段、16 个 ID 分量和 backend/UE 两套输出哈希；检查 64 位数值 ID、显式可空值、
禁止缩窄及两条真实编译锚点。加 `-VerifyGenerated` 会在锁定、断网、只读容器中逐 byte 重建。

`Contract/Test-ContentHealth.ps1` 验证 P2-18 对 P2-01～P2-17 共 17 份完成证据的精确哈希
绑定，以及解析、损坏、不透明/未知、引用、转换、工作量、容量和 13 项风险清单。加
`-VerifyDerivedSources` 会在锁定、断网、只读容器中逐 byte 重建 JSON 与 Markdown 报告。

`Contract/Test-ResourceBudget.ps1` 验证 P2-19 对 P2-15、P2-18 和五类匿名转换试验的精确
哈希绑定，并把实测事实、规划系数、假设、风险储备和缺失实测严格分开。专项合同拒绝
极值选样、alias 重复计费、basis 错分和冻结证据篡改；加 `-VerifyDerivedSources` 会在锁定、
断网、只读容器中逐 byte 重建预算 JSON 与 Markdown，并比较完整机器证据。

`Contract/Test-G2Review.ps1` 验证 P2-20 对 P2-01～P2-19 和完整质量门禁的精确哈希
绑定，并消费两个独立补救证据。`Contract/Test-G2CoreResourceClosure.ps1` 从 P2-13 的
冻结根集合重建五类边的闭包，验证范围、条件必需字段、引用队列和资产结构缺口均没有被
省略；条件必需的 29 个匿名成员工作集和覆盖 21,494 个可达资产的显式绑定工作集只保存在
Git 忽略区，跟踪证据仅保存 count/SHA。资产绑定显式为 true 仍必须分别满足歧义、未决
和未知为零，合同拒绝首候选、明细遗漏/重复、矛盾状态及伪造归零。
`Contract/Test-G2MigrationDecisions.ps1` 则枚举
Schema、引用规则、Canonical ID 域、ID 分量和固定容量信号的完整决定集合，强制机器建议
和 39 个匿名审阅包不得冒充负责人选择或审批；V2 决定、审批、验证与 supersession 都须
绑定决定摘要和外部权威台账。合同成功表示评审正确失败关闭，不表示 G2 通过；当前 7/9
满足、G2-06/G2-07 阻塞，任务完成、G2/P3/可玩性/发布权威均为 false。三份合同的
`-VerifyDerivedSources` 会隔离重建并逐 byte 复核；负例防止删减范围、归零真实缺口、
伪造迁移决定或把审计冒充授权。

`Contract/Test-LegacyToUETransform.ps1` 复核只读旧源码与 UE 5.8.2 矩阵证据哈希，并在锁定的非 root Clang 21 容器中验证米到厘米、欧拉角符号、行向量矩阵、UV、法线、负缩放绕序和非法数值边界。
