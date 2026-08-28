# 当前客户端 TBL 读取链与运行时密钥证据

## 1. 状态与范围

P1-09 已完成。2026-08-28 在用户授权的本地会话中，从
`Rebuild/Data/Backups` 下的客户端沙箱副本捕获到当前表运行时密钥状态，并在不输出
密钥或明文的前提下完成全量分类。活动表集合为 225 张：`CLSVShare` 113 张、根
`Table` 111 张和 `Table/local/localitem.tbl` 1 张。其余 113 张均有时间更新、且已用
同一运行时状态验证的新副本，因此归类为历史影子文件，不再虚构第二个活动密钥域。

P1-09 完成不代表当前表读取器已经产品化。显式密钥注入、GBK 转码、各表 Schema
规则和错误定位属于 P1-10；本阶段只关闭算法、密钥来源、padding、压缩边界、代表性
编码和活动输入集合的证据缺口。

## 2. 冻结输入与机器报告

- 当前 `QY.exe`：5,160,960 bytes，SHA-256
  `7087dfa64bedeb8c9a5dfc4518f46261d163136b5bd97f5071f2c5a12cb29a4b`。
- `Table` 与 `CLSVShare` 递归合计 338 张 `.tbl`，40,444,128 bytes。
- 静态诊断报告：
  `Data/BuildBaseline/p1-09-current-table-investigation.json`。
- 授权运行时捕获报告：
  `Data/BuildBaseline/p1-09-runtime-key-capture.json`。
- 可复现工具：
  `Tools/TMXY.Table/Capture-CurrentTableRuntimeKey.ps1`。

两份报告只含文件摘要、代码窗口摘要、计数和不可逆密钥 SHA-256，不含密钥字节、
解密字段内容、登录参数或旧资产载荷。

## 3. 密文与读取算法

338 张 TBL 均非空且长度为 16 的整数倍，共 2,527,758 个块。全局只有 1,353,326
个不同块，重复出现 1,174,432 次；230 张表存在文件内重复块，44,134 种块跨文件
重复。该分布支持确定性独立块模式，不支持随机 IV 的 CBC 类解释。

当前 `QY.exe` 的两条表加载路径均构造 Rijndael 实例，以同一 16-byte 全局缓冲区
调用 `setkey`，读取 `.tbl` 后以 `pi=1`、`pj=1` 调用 `decode`。与逐 byte 验证的旧
实现对照，这对应每个 16-byte 块连续执行两次 AES-128 解密；未观察到 IV、Nonce、
认证标签或跨块链式状态。

磁盘基础密钥指纹为
`c5ab3734151f66dd61ec86290d3b1ac5e180d2f3c4e6d54441ec39e3cfb66524`，不能解开代表
表。网络分发器中的两个处理器会分别重排全部 16 个字节、覆盖四个索引字节；静态
分发槽为 958 和 289。槽号只表示当前二进制索引，不套用旧协议枚举名称。

## 4. 授权运行时捕获

捕获器只允许附加到 `Rebuild/Data/Backups` 下、SHA-256 完全匹配且具有启动器
`dev:` 形态的 QY 沙箱进程。它用只读进程权限读取模块基址加 RVA `0x4dd028`，对每个
不同状态先计算 SHA-256，再在内存中验证代表表；报告不记录命令行。

验证通过的运行时状态指纹为
`cf760550b7af6c220331b258db1df781fe567221eb7c53fbfc65aca522085887`。原值通过标准输入
保存到 Docker Pass 操作系统钥匙链条目
`se://tmxy/development/table/qy-3.0.0.413/runtime-key-base64`，随后经 Windows 凭据
API 只读回验为 16 bytes 且指纹一致。所有显式 byte 缓冲区在使用后覆零；原值没有
进入命令行、环境变量、报告、Git 或备份清单。

## 5. 活动表验证结果

同一运行时状态验证了 225 张活动表，且所有未通过的文件都被后续历史影子分类覆盖。

| 目录域 | 文件数 | 通过当前运行时状态 | 历史影子 |
| --- | ---: | ---: | ---: |
| `CLSVShare` | 113 | 113 | 0 |
| 根 `Table` | 111 | 111 | 0 |
| `Table/local` | 2 | 1 | 1 |
| `Table/help` | 1 | 0 | 1 |
| `Table/Regions` | 111 | 0 | 111 |

225 张表全部满足“首 byte 为 0～15 padding 长度、尾部为对应数量的零、载荷无内嵌
NUL、行结束为 CRLF”。这证明代表表在第二次 AES 解密后直接得到表载荷，没有额外
压缩层。181 张表还满足简单逗号列数一致；其余表需要 P1-10 的专用 Schema/转义规则，
不能用朴素 CSV 分割器强行解释。

代表性结果：

- `item_table.tbl`：7,046,695 payload bytes，95 列、29,223 行，严格 GBK 成功、严格
  UTF-8 失败。
- `skill_table.tbl`：7,253,247 payload bytes，65 列、23,227 行，严格 GBK 成功、
  严格 UTF-8 失败。
- 根 `quest_table.tbl`：4,586,490 payload bytes、5,944 个非空 CRLF 行，严格 GBK
  成功；其字段规则不是朴素固定逗号列数。
- `powergame.tbl`：32 payload bytes，纯 ASCII，因此 UTF-8 与 GBK 均可表示。

224/225 张活动表可被严格 CP936 解码；唯一例外是 173-byte 的
`CLSVShare/ArenaLevel.tbl`，由 P1-10 按表级格式处理，不改变三张大型非 ASCII 代表表
的 GBK 结论。

## 6. 113 张历史影子文件

`Table/Regions` 的 111 张 TBL 与根 `Table` 的 111 张文件逐名一一对应，0 张 byte
相同；历史副本最新时间为 2022-01-04，而已验证替代文件最早时间为 2026-08-20。
`Table/local/quest_table.tbl`（2023-06-13）被根 `Table/quest_table.tbl`（2026-08-20）
替代，`Table/help/localitem.tbl`（2023-11-14）被
`Table/local/localitem.tbl`（2026-08-20）替代。

当前 QY 中唯一 `Table\Regions\` 字面量位于把该路径与 `.xml` 拼接的地图 XML
加载函数中，并非 TBL 路径。冻结窗口为文件偏移 `0x280770`、272 bytes、SHA-256
`93068e861cbd04935d546f0ee435192d9eab949dcb4779e4955827e62b199f42`；相邻字符串窗口
SHA-256 为 `b71999eaf35a49bd99870f592c1b2931962749ba12a75e25374f8da54095a8db`。
因此这 113 张文件被保留为取证输入，但排除出当前活动表读取器输入。

## 7. 残留 CSV 关系

`item_tabletemp.csv` 为 6,551,430 bytes；按旧 padding 规则只需 6,551,440 bytes
密文，而当前 `item_table.tbl` 为 7,046,704 bytes，多 495,264 bytes。ECB 重复块关系
在前 874 个块保持一致、第 875 块首次冲突，证明二者有共同早期结构但不是同一版本。
残留 CSV 只能辅助字段候选，不能覆盖当前解密结果，也不能充当发布资产。

## 8. P1-10 接口边界

- 新工程仍不包含默认 TBL key；读取器必须显式注入 16-byte key。
- 产品代码只接受 Secret Store/调用方提供的 key，不读取报告指纹来“还原”密钥。
- P1-10 只处理已证明的 225 张活动表；113 张历史影子必须显式拒绝或标为 historical。
- 解密失败、编码失败和 Schema 失败均返回结构化错误，日志不得包含密钥或字段内容。
- 不硬编码捕获值，不把残留 CSV 当真值，不绕过服务认证获取其他参数。
