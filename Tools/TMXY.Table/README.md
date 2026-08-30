# TMXY.Table

`TMXY.Table` 是离线格式证明模块，负责旧 TBL 的显式密钥注入、legacy double-AES-128 解码、padding 验证和逗号分隔表结构解析。

模块不包含默认密钥，不读取环境变量，不访问 Secret Store，也不依赖老客户端运行时。调用方必须以 16-byte span 显式提供已获授权的密钥；错误、日志和指纹均不得包含密钥或解密字段内容。

`Capture-CurrentTableRuntimeKey.ps1` 是 P1-09 的 Windows-only 授权取证工具。它只
附加到 `Data/Backups` 中哈希锁定的 QY 沙箱进程，使用只读进程权限，对候选 key 在
内存中完成全表验证，并只输出不可逆指纹和结构计数。通过验证的值可经标准输入写入
Docker Pass 操作系统钥匙链；命令行、报告和 Git 均不包含原值。

P1-09 已证明 225 张当前活动表沿用 double-AES-128、旧 padding 和 CRLF 载荷，其中
代表性非 ASCII 大表是 GBK；113 张未匹配文件均为有更新替代物的历史影子。产品化
当前表读取器、表级 Schema 和编码例外属于 P1-10，不能把旧读取器的朴素逗号规则
直接外推到全部当前表。

`Compare-CurrentItemResidual.ps1` 使用钥匙链中的同一候选，在内存中比较当前
`item_table.tbl` 与残留 CSV。它只报告表头指纹、行数、唯一主键集合以及相同/变化/
新增/删除行计数，不输出字段或主键。该证据完成 P1-10，并明确残留 CSV 只能用于
Schema 与历史差异研究。

`Inspect-CurrentTableRepresentativeSet.ps1` 固定 10 张最小和 10 张最大活动
`CLSVShare` 表，逐表验证解密、padding、CRLF、编码、列数、首字段唯一性和空字段，
只输出计数与分类。20/20 样本通过，P1-11 完成；需要复合键的表会明确分类，不会把
首字段重复误报为解析失败。

`New-FullCurrentTableInventory.ps1` 完成 P2-04。它对冻结沙箱的 338 张 TBL 逐文件
生成哈希、来源版本角色、活动/历史生命周期、解码错误、编码、物理行列、表头质量、
空字段和主键候选；225 张活动表全部解码，113 张历史影子全部关联更新且已验证的替代
表。报告不输出 key、明文表头、字段名或字段值，历史影子也不会猜测旧 key 或伪造
Schema。

`New-AuxiliaryConfigInventory.ps1` 完成 P2-05。它盘点 148 个 Table/CLSVShare XML
和 64 个 ClassCfg ECF，使用禁止 DTD/外部解析的严格 XML 读取器、ECF 自逆变换往返
校验以及完整遗留服务端源码字面引用扫描，输出结构、重复/覆盖和客户端/共享所有权。
报告不输出 XML 文本/属性值或 ECF 解码行、键和值；6 个不合规 XML 保留原始输入并
显式隔离，P2-05 不自动修复或删除任何文件。

`New-ThreeLayerTableData.ps1` 完成 P2-06。它将 225 张活动表确定性导出为逐表
`raw.csv`、UTF-8 `normalized.jsonl` 和 JSON 语法子集的 `schema.yaml`；113 张历史
影子只保留更新替代关系。全量明文位于 Git 忽略的 `Data/Exports/P2-06`，提交报告只含
路径、哈希、大小、计数、分类和稳定列 ID。类型、键、所有权和加载策略均保留证据等级，
分别交给 P2-07/P2-08 做权威决策，不把机械推断升级为产品语义。

`New-CoreTableSchema.ps1` 完成 P2-07。它从 P2-06 本地规范化层生成 12 张核心表的
版本化导入注册表，逐行验证 355 列类型/范围、12 个主键和 14 条严格引用。技能按
`guid + level`、职业成长按 `Profession + level`，后者只折叠已证明逐行相同的 800 个
重复物理行；任意不同内容的同键行均失败关闭。`-Check` 不写文件，要求重新生成的
注册表与证据逐 byte 相同。工具不解密 TBL、不接收或访问 Secret；所有权仍留给 P2-08。

`New-TableOwnershipRegistry.ps1` 完成 P2-08。它只读扫描 1,096 个旧客户端源码文件、
1,972 个旧服务端源码文件和冻结沙箱的 `QGameEngine.ecf`，把消费者证据与目标权威分开。
225/225 活动表和 355/355 核心列均有客户端/服务端/共享决定；战斗、经济和未知玩法语义
默认服务端权威，36 个本地化列与 12 个表现资源列明确归客户端。ECF 解码内容、表行和值
不进入证据，`-Check` 要求全量重扫结果逐 byte 相同。
