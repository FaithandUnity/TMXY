# 《天命西游／QQ西游》老工程构建依赖与可编译性矩阵

> 文档编号：P0-06
> 版本：V1.1（最终架构决策同步版）
> 日期：2026-08-26
> 工作区：`E:\QQXYCodeDev`
> 调查方式：只读静态扫描、工程 XML 解析、本机构建环境探测、代表性静态库头检查
> 原始输入：`ClientCode`、`ServerCode`、`ToolCode` 只读
> 机器可读清单：[build-inventory.json](../../Data/BuildInventory/build-inventory.json)
> 本机环境锁定快照：[toolchain-environment.json](../../Data/BuildInventory/toolchain-environment.json)
> 产品架构决策：[TARGET-ARCHITECTURE.md](../Architecture/TARGET-ARCHITECTURE.md)
> 强制工程规范：[ENGINEERING-STANDARD.md](../Standards/ENGINEERING-STANDARD.md)

---

## 1. 结论先行

P0-06 已完成全部老工程、主解决方案、构建配置、链接库、第三方源码、随附二进制、数据库接口和本机构建环境的基线盘点。核心结论如下：

1. 老代码不是“完全无法编译”，但不能把原始 `.vcproj` 直接当成 UE 5.8.2 或现代 x64 工程使用。
2. 从纯遗留研究角度，`Release|Win32` 是最可能成功的老服务端配置；但根据 ADR-008，它不再是产品实施首条路径，只在无法从源码静态确定关键行为时作为可选隔离实验。
3. 不能从 `FastDebug|Win32` 起步。`WorldServer` 和 `InstServer` 的 FastDebug 配置引用了不存在的 `FJGameServer.lib`；Release/Debug 配置改用可由工程生成的 `GameServer.lib`。
4. 主客户端同样是 Win32、Direct3D 9、自研渲染/UI/音频结构。它应作为协议、玩法、格式和视觉行为参考；UE 5.8.2 将替换渲染、UI、输入、音频、资源管理和发布壳层。
5. 现有专有/平台静态库抽样均为 x86 COFF，并混用旧 CRT 指令。x64 重构必须先建立适配边界，然后替换或重新获得源码构建，不能仅把平台选项从 Win32 改成 x64。
6. 老服务端研究环境若启动仍需要 SQL Server；新产品后端从首个切片直接使用 PostgreSQL 18。SQL Server 只读快照经离线迁移工具进入 Canonical 数据，不被新服务运行时连接。
7. 工程树含 216 个 3ds Max SDK 示例项目。它们不是新客户端/服务端的构建前置条件，不应把其 FBX、OpenGL 或示例库缺失误判成主工程阻塞。
8. 本机已安装 UE 5.8.2、Visual Studio Community 2026、MSVC 14.51.36231 和 Windows SDK 10.0.26100.0；但 P0-08 仍需把安装组件、调用入口和干净机步骤固化为正式工具链锁定文件。

### 1.1 当前可编译性总表

| 构建目标 | 当前判定 | 是否建议现在执行 | 主要原因 | 进入下一状态的条件 |
|---|---|---:|---|---|
| 老服务端 Release/Win32 行为研究 | 🟡 条件可行 | 仅证据不足时可选 | 主工程、第三方源码和多数二进制均存在；但不是产品运行时 | 单独研究任务批准后在隔离目录转换；产物禁止进入 Production |
| 老服务端 Debug/Win32 | 🟡 条件可行 | 否 | Debug 库命名和旧 CRT 组合需逐项核实 | 默认不投入；只有调试遗留行为时启用 |
| 老服务端 FastDebug/Win32 | 🔴 不可直接构建 | 否 | `FJGameServer.lib` 缺失，仅 FastDebug 引用 | 删除过期配置依赖或恢复其真实生产工程；不得盲造空库 |
| 老服务端原样 x64 | 🔴 不可行 | 否 | 主工程只有 Win32；平台/商业库为 x86；ADO 与结构位宽风险 | 协议和持久化边界固定；全部二进制依赖有 x64 替代；完成位宽审计 |
| 老客户端原样 Release/Win32 | 🟡 仅供参考复现 | 视需要 | D3D9/D3DX、Miles、AH 接口、旧 DX SDK 与旧工具链耦合 | 仅在需要对照行为或格式时建立隔离构建机 |
| 老客户端直接升级为 UE 5.8.2 | 🔴 不存在直接升级路径 | 否 | 引擎、资源对象、UI、音频和渲染体系不同 | 以协议/数据/行为为规范重写 UE 前端；资产经可验证转换导入 |
| UE 5.8.2 新客户端 x64 | 🟡 环境具备、工程未建 | P1 创建 | UE 已安装；资源/协议中间层尚未完成 | P0-08 完成；P1-19 中间格式、P1-20 空工程、P1-21 导入插件 |
| Linux x64/PostgreSQL 18 新后端 | 🟡 架构已冻结、工程未建 | 是，正式产品首条路径 | ADR-008/ADR-011 已接受；质量和目录规范已固定 | 建立 C++20/CMake/Ninja 骨架及 Gateway→Account/Character→PostgreSQL 纵向切片 |
| 老 3ds Max 导出工具原样构建 | 🟡 仅隔离环境可行 | 非主路径 | 依赖 Max 8/9/2010 SDK、MFC，部分样例依赖旧 FBX SDK | 只选择第一方导出器；不要编译 216 个 SDK 示例；必要时用历史工具机 |
| 新资产转换工具 x64 | 🟡 待创建 | 是 | 应独立于 Max、D3D、MFC 和 UE Runtime | C++20/CMake 解析库 + CLI + 测试；UE 仅消费规范化中间产物 |
| LoginWeb 原样部署 | 🔴 不建议 | 否 | ASP.NET Web Application、.NET Framework 3.5 | 仅提取行为和接口；使用新管理/API 服务重写 |

---

## 2. 盘点范围、方法和判定规则

### 2.1 已扫描对象

- `ClientCode`：老客户端、启动器、渲染、UI、音频适配、第三方源码和 DX9 SDK。
- `ServerCode`：登录、网关、世界、实例、数据库、日志、商城、奖励等服务及第三方源码/库。
- `ToolCode`：第一方美术/数据工具，以及随附的 3ds Max SDK 示例树。
- 本机环境：Visual Studio、MSVC、MSBuild、Windows SDK、UE、PowerShell、.NET 和 PATH 可见工具。
- 数据库证据：SQL 文件、ADO 导入方式、Provider 和存储过程使用方式。

未执行任何原始工程转换或写入；生成物全部位于 `Rebuild`。

### 2.2 自动依赖状态

| 状态 | 含义 | 注意事项 |
|---|---|---|
| `BundledBinary` | 工作区存在同名 `.lib`/`.dll`/`.tlb` | 只证明文件存在，不证明架构、CRT、许可证或 ABI 可用 |
| `ProducedByProject` | 同名库由某个老工程声明生成 | 必须先构建生产工程；配置名和输出路径仍需验证 |
| `SystemSdk` | Windows、DirectX 或系统 SDK 链接库 | 部分旧 DirectX 辅助库不在现代 Windows SDK 中 |
| `LegacyCompilerRuntime` | 旧 Visual C++ 工具链运行库 | 不能视为现代 MSVC 的稳定接口 |
| `MissingOrExternal` | 未找到同名产物或生产工程 | 可能是真缺失、过期配置、SDK 样例依赖或拼写错误，需结合消费者判断 |

### 2.3 自动扫描的边界

自动扫描解析工程 XML 中显式链接项。源码里的 `#pragma comment(lib, ...)`、运行时 `LoadLibrary`、COM 注册、外部进程、配置文件和数据库运行依赖还需要源码级审计。因此本报告已经人工补入 `AHClientInterface.lib` 等源码依赖；若批准可选遗留研究构建，仍须用编译/链接日志做闭包。

---

## 3. 工程与解决方案全量统计

### 3.1 工程数量

| 根目录 | `.vcproj` | 第一方 | 第三方源码 | SDK 示例 | 主要年代 |
|---|---:|---:|---:|---:|---|
| ClientCode | 18 | 13 | 5 | 0 | VS2003/2005/2008 |
| ServerCode | 26 | 19 | 7 | 0 | VS2003/2005/2008 |
| ToolCode | 241 | 25 | 0 | 216 | VS2003/2008 |
| 合计 | **285** | **57** | **12** | **216** | 以 VS2008 为主 |

另有：

- 1 个 `.csproj`：`ServerCode/LoginWeb/LoginWeb.csproj`。
- 33 个 `.sln`。
- 8 个 `.dsp`、4 个 `.dsw`，属于更早的 Visual C++ 6 风格工程遗留。
- 未发现可作为老源码正式入口的 `.vcxproj` 或 `CMakeLists.txt`。
- 285 个 `.vcproj` 全部成功解析，解析错误为 0。

### 3.2 `.vcproj` 工具链年代

| 根目录 | VS2003 `7.10` | VS2005 `8.00` | VS2008 `9.00`/`9,00` | 合计 |
|---|---:|---:|---:|---:|
| ClientCode | 1 | 2 | 15 | 18 |
| ServerCode | 7 | 2 | 17 | 26 |
| ToolCode | 4 | 0 | 237 | 241 |
| 合计 | **12** | **4** | **269** | **285** |

ServerCode 中两个 `9,00` 使用逗号的项目属于旧 FreeType/移动平台工程元数据异常，转换工具必须归一化处理，不能据此判断为未知编译器。

### 3.3 平台分布

| 范围 | 平台事实 | 结论 |
|---|---|---|
| ClientCode | 18/18 工程声明 Win32 | 老客户端没有可继承的 x64 基线 |
| ServerCode | 26/26 工程含 Win32 | 可选遗留研究构建只能从 Win32 起步；新产品直接 Linux x64 |
| ServerCode FreeType 移动工程 | 2 个工程还声明 Pocket PC/Smartphone/Windows Mobile ARM | 历史旁支，不进入重构主线 |
| ToolCode | 241 个含 Win32；216 个 SDK 示例还含 x64 | SDK 示例的 x64 配置不代表第一方工具已支持 x64 |

### 3.4 解决方案格式

| 根目录 | VS2003 格式 8.00 | VS2005 格式 9.00 | VS2008 格式 10.00 | 合计 |
|---|---:|---:|---:|---:|
| ClientCode | 1 | 0 | 3 | 4 |
| ServerCode | 4 | 1 | 6 | 11 |
| ToolCode | 2 | 0 | 16 | 18 |
| 合计 | **7** | **1** | **25** | **33** |

---

## 4. 主客户端工程矩阵

`ClientCode/QRender.sln` 是 VS2008 格式，包含 14 个工程：

| 层次 | 工程 | 作用判断 | 重构处理 |
|---|---|---|---|
| 基础 | Base、Utility | 通用工具、平台辅助 | 只提取仍有价值的纯逻辑；重写平台层 |
| 引擎 | QRender、D3D9RDev | 自研渲染与 D3D9 设备层 | 不移植到 UE；用于资源语义和视觉对照 |
| 客户端 | Game、WinClient、WinConsole | 游戏逻辑和两个宿主入口 | 提取协议、状态机、计算与玩法行为；UE 重写表现层 |
| 启动/更新 | WinLauncher、UpdateGen | 启动、更新和生成工具 | 使用新启动器/补丁与发布管线重写 |
| UI | QUI | 自研 UI | 映射为 UMG/CommonUI；不复制控件实现 |
| 音频 | MSSDev | Miles Sound 适配 | UE Audio/MetaSounds 替换；保留音频事件语义 |
| 第三方 | lua-5.1.4、tinyxml、Freetype-2.3.9 | 脚本、XML、字体 | 解析/行为参考；新工程按模块重新选择版本与边界 |

### 4.1 客户端主要构建依赖

| 依赖 | 当前证据 | 当前可用性 | UE 5.8.2 处理 |
|---|---|---|---|
| Direct3D 9 / D3DX9 | 工程链接 `d3d9.lib`、`d3dx9.lib`；随附 `DX9SDK` | 仅老 Win32 参考构建 | UE RHI 替换；不可把 D3D9 资源对象带入 UE |
| DirectInput 8 / DXGuid / DXErr | 启动器/控制台工程显式链接 | 旧 SDK 依赖 | Enhanced Input、平台 API 替换 |
| Miles Sound System | `Mss32.lib` 随附并由客户端链接 | x86 商业二进制；需单独核权利/版本 | UE Audio 替换；音频文件和事件映射单独迁移 |
| AHClientInterface | `QNetHandler.cpp` 通过 pragma 链接；库文件存在 | x86、旧 CRT、平台耦合 | 新客户端核心不依赖；用可替换平台/安全适配层 |
| Lua 5.1.4 | 源码和工程存在 | 可作为行为参考构建 | 是否保留 Lua 由脚本资产审计决定；接口隔离 |
| TinyXML | 源码和工程存在 | 可构建，版本较老 | 新工具优先现代 XML 库；兼容解析器可封装旧行为 |
| FreeType 2.3.9 | 源码和工程存在 | 可构建，版本较老 | UE 字体系统替换；只保留旧资源解释逻辑 |
| ODBC 库 | 启动器/控制台工程出现 | 需确认是否仍有运行用途 | 新客户端禁止直接访问数据库 |

### 4.2 客户端可复用边界

建议复用的是“规则和证据”，不是旧引擎对象：

- 可提取：协议编号、包结构、序列化、状态机、输入语义、角色/技能/任务逻辑、资源格式字段、坐标换算证据。
- 需要重写：窗口、渲染、材质、Shader、UI、音频、输入、文件系统、补丁、崩溃收集、反作弊/平台接入。
- 必须验证：所有客户端数据都不能自动视为服务端权威数据；战斗、经济、掉落、任务条件应由新服务端拥有最终判定。

---

## 5. 主服务端工程与服务矩阵

`ServerCode/RouteManager.sln` 是 VS2008 格式，包含 15 个工程：

| 构建层 | 工程 | 产物/作用 | 遗留研究用途 |
|---|---|---|---|
| 第三方基础 | ACE、lua、tinyxml | 网络/并发、脚本、XML | 仅为解释老行为时从源码构建 |
| 共享基础 | ServerCommon | 数据库、协议、公共设施 | 研究 ADO、协议和公共规则，不进入新后端 |
| 游戏核心 | GameServer | 世界/实例共用游戏逻辑库 | 第三层构建，产出 `GameServer.lib` |
| 网关共享 | GatewayManager | 网关管理共享库 | 第三层构建 |
| 入口服务 | loginServer、Gateway | 登录与接入 | 建立最小登录链路 |
| 数据服务 | DBCenter | 数据读写与持久化协调 | 解释 SQL Server 读写和事务语义 |
| 世界服务 | WorldServer、InstServer | 世界与副本 | 仅从 Release/Debug 起步 |
| 辅助服务 | LogServer、RewardServer、MallServer | 日志、奖励、商城 | 核心登录/进世界之后恢复 |
| 工具 | DBBinaryTool | 数据库/二进制辅助工具 | 按数据管线需要恢复 |

不在主 `RouteManager.sln` 但必须纳入后续服务清单的目录/工程包括 `ProxyServer`、`ValidateServer`、`LoginWeb` 等。是否属于目标版本运行拓扑，须在 P4 根据配置、端口、进程调用和协议引用再次确认。

### 5.1 可选遗留研究构建顺序

```text
1. ACE + Lua + TinyXML
2. ServerCommon
3. GameServer + GatewayManager
4. loginServer + Gateway
5. DBCenter
6. WorldServer + InstServer
7. RewardServer + MallServer + LogServer
8. ProxyServer / ValidateServer / 其他外围服务（按运行拓扑验证）
```

只有当关键行为无法通过源码、SQL 和客户端证据确定时才执行此顺序，并固定 `Release|Win32`。它不阻塞 Linux 新后端，也不向新工程提供可链接产物。

### 5.2 服务端依赖与现代化方向

| 依赖/机制 | 已确认版本或方式 | 遗留证据处理 | 新产品处理 |
|---|---|---|---|
| ACE | 5.4.2 | 从随附源码构建 Win32；保留网络行为 | 通过网络适配接口迁移到现代异步 I/O 层；核心代码不再直接暴露 ACE 类型 |
| Lua | 5.1.4 | 保留脚本行为，冻结测试向量 | 根据脚本资产兼容性决定升级或沙箱化；不让 Lua C API 穿透业务边界 |
| TinyXML | 版本尚未在本次基线中精确锁定 | 先用随附源码读取旧配置 | 新配置格式/schema 与现代 XML/JSON 解析层替换 |
| Protobuf | 宏版本 `2000003`，即 2.0.3 | 只处理现有生成代码与旧数据兼容 | 从统一 Schema 重新生成；升级运行库；做字段兼容测试 |
| FreeType | 2.3.9 | 仅保留需要文字栅格/动态图的旧工具路径 | 服务核心剥离；UE/新工具使用受维护版本 |
| zlib | 随附旧二进制 | 先验证具体调用与数据兼容 | 使用受维护版本并保留压缩测试向量 |
| gtest | ProxyServer 随附旧库 | 不作为生产依赖 | 新测试工程使用当前受控版本 |
| Tencent/平台库 | `libpal`、`libtdr`、`libtlog`、`libtloghelp`、`libtmng`、`logapilib`、`tqqsig`、`qq_descrypt` 等 | 仅分析接口和可观察行为 | 不链接旧库；使用自有认证、日志、运维和加解密实现 |
| Win32/COM | ADO、Windows 类型、旧运行库 | 只读分析或隔离实验 | 完全禁止；业务域使用定宽类型、RAII 和平台无关接口 |

新后端不会机械替换 ACE/ADO/平台库，而是从契约测试重新实现消息帧、超时、断线、重连、事务和错误语义。

---

## 6. 数据库和 Web 管理依赖

### 6.1 SQL Server 基线

已发现 5 份 SQL 文件：

- `sql/生成insert脚本的存储过程.sql`
- `sql/账户二级密保.sql`
- `sql/log.sql`
- `sql/login.sql`
- `sql/world.sql`

代码通过 ADO/OLE DB 使用 SQL Server：

- `ServerCommon/QDBHandler.h` 硬编码导入 `msado15.dll` 的历史安装路径。
- 默认 Provider 为 `SQLOLEDB`。
- 数据层大量依赖存储过程，不能只复制表结构就认为数据库已还原。

### 6.2 数据库最终方案

| 范围 | 数据库方案 | 目的 |
|---|---|---|
| 新产品运行时 | PostgreSQL 18 + libpq Adapter + 版本化 Migration | 从第一天形成最终事务、索引、备份和性能基线 |
| 老系统证据 | SQL Server 只读快照和 SQL 脚本 | 解释字段、存储过程、事务和数据语义 |
| 离线迁移 | SQL Server → Canonical JSONL/Parquet → PostgreSQL staging → owned schemas | 可重跑、可核对地迁移旧数据，不形成双数据库产品依赖 |
| 测试 | 同一行为向量比较老证据与 PostgreSQL 新实现 | 验证功能等价、总量守恒和错误语义 |

### 6.3 Secret 与安全问题

源码/测试材料中存在历史连接信息和内部环境痕迹。报告和扫描 JSON没有复制具体值。P0-14 必须完成以下动作：

- 把数据库、平台、日志和服务间凭据移入 Secret Store/本机安全配置。
- 在新仓库启用 Secret 扫描和提交前检查。
- 对仍可能有效的历史凭据执行轮换；不得因为源码年代久远而默认安全。
- 配置文件只保留变量名、示例和非敏感默认值。

### 6.4 LoginWeb

`LoginWeb.csproj` 使用 `ToolsVersion="3.5"`、目标 `.NET Framework v3.5`，属于经典 ASP.NET Web Application。它不进入现代生产架构：

1. 先盘点页面、接口、权限、运营操作和数据库副作用。
2. 为每个操作建立审计、授权和契约测试。
3. 用现代受支持的管理/API 服务重写，不把旧 Web 进程作为新系统依赖。

---

## 7. 美术工具与 SDK 依赖

### 7.1 3ds Max 工程树

ToolCode 的 241 个 `.vcproj` 中：

- 第一方工具约 25 个。
- 216 个属于随附的 3ds Max 8/9/2010 SDK 示例工程。

因此不能提出“把 ToolCode 全部编译通过”作为资产恢复的前置条件。正确做法是：

1. 识别真正生成游戏格式的第一方导出器/转换器。
2. 从源码读出 qtx/sm/skem/anim/ter 等格式的写入规则。
3. 建立不依赖 3ds Max 的独立解析/转换测试库。
4. 只有必须复核 DCC 导出行为时，才在隔离历史环境中构建特定插件。

### 7.2 工具依赖矩阵

| 依赖 | 影响范围 | 当前状态 | 主线决策 |
|---|---|---|---|
| 3ds Max 8/9/2010 SDK | 老导出器和 216 个示例 | 随树可见，但要求历史 DCC/编译环境 | 仅作为格式证据；不成为新工具运行依赖 |
| FBX SDK 2008 库 | Max pointcache 示例 | 4 个架构/调试变体未找到 | 仅影响 SDK 示例，不阻塞游戏主工程；不补旧 FBX SDK |
| MFC | 多个 Windows 工具 | 当前 VS 可提供现代 MFC，但 ABI/工程转换仍有风险 | CLI/库核心不使用 MFC；必要 UI 工具再单独重写 |
| DirectX 9 SDK | 老预览/客户端工具 | 随附旧 SDK | 新预览使用 UE 或现代渲染；解析库无图形 API 依赖 |
| `assetmanagement.libassetmanagement.lib` | 一个 Max SDK 示例 | 原工程依赖字符串本身拼接错误 | 记录为样例元数据错误，不修原文件、不阻塞主线 |
| `gcreptdb.lib` | 两个 Max SDK 示例 | 未随附 | 非第一方主线依赖 |

---

## 8. 随附二进制与 ABI 风险

### 8.1 文件统计

| 根目录 | `.lib` | `.dll` | `.tlb` | 总字节 |
|---|---:|---:|---:|---:|
| ClientCode | 60 | 0 | 2 | 66,424,004 |
| ServerCode | 40 | 5 | 0 | 51,999,016 |
| ToolCode | 221 | 19 | 1 | 47,983,772 |
| 合计 | **321** | **24** | **3** | **166,406,792** |

### 8.2 代表性架构检查

使用本机 MSVC `dumpbin` 对以下库抽样：

| 库 | 机器类型 | 默认库痕迹 | 风险 |
|---|---|---|---|
| `ServerCode/libs/qq_descrypt.lib` | x86 (`14C`) | `MSVCRT`、`MSCOREE` 等 | 旧 CRT/托管边界，不能直接用于 x64 |
| `ServerCode/libs/libprotobuf.lib` | x86 | `msvcprt`、`MSVCRT` | 旧 Protobuf 与编译器 ABI 风险 |
| `ServerCode/libs/lib_rel/libpal.lib` | x86 | `MSVCRT` | 平台库源码/替代方案不明确 |
| `ClientCode/Game/AHClientInterface.lib` | x86 | `LIBCMT`、`libcpmt` | 与 DLL CRT 组合可能冲突；平台接口应移除 |
| `ClientCode/lib/Mss32.lib` | x86 | — | 商业音频库、x64 与许可/版本风险 |

抽样不是全库架构证明。若执行遗留研究构建，应检查所有实际链接 `.lib`/`.dll` 的 Machine、导入项和默认 CRT；新产品构建由 CI 直接禁止这些路径。

### 8.3 ABI 迁移原则

- 可选遗留研究进程保持 Win32，避免跨架构链接，并与产品部署隔离。
- 新服务从第一天使用 x64，但不能链接任何未审计的旧静态库。
- 新旧进程通过明确版本的网络/IPC 契约交互，不跨模块传 C++ STL 对象、异常、内存所有权或 CRT 分配对象。
- ID、长度、时间、货币和数量使用固定宽度类型，并对旧协议的截断/溢出建立测试。

---

## 9. 自动链接依赖结果

工程 XML 共提取 112 个唯一 `.lib` 名称：

| 状态 | 数量 | 解释 |
|---|---:|---|
| BundledBinary | 53 | 存在同名随附库 |
| ProducedByProject | 20 | 由老工程声明生成 |
| SystemSdk | 30 | Windows/DirectX/系统 SDK |
| LegacyCompilerRuntime | 2 | 旧 Visual C++ 运行库 |
| MissingOrExternal | 7 | 需人工复核 |

7 个 `MissingOrExternal` 中，唯一影响第一方服务端主路径的是：

| 名称 | 消费者 | 配置 | 判定 |
|---|---|---|---|
| `FJGameServer.lib` | WorldServer、InstServer | `FastDebug|Win32` | 过期/缺失配置依赖；Release/Debug 使用 `GameServer.lib`，首轮绕开 FastDebug |

其余 6 个全部位于 3ds Max SDK 示例：4 个 FBX SDK 2008 变体、`gcreptdb.lib`，以及一个由样例字符串拼接错误产生的 `assetmanagement.libassetmanagement.lib`。这些项目不属于重构主构建闭包。

机器可读清单保留每个库的消费者、配置和分类，后续可从 `link_dependencies` 直接生成 CI 规则。

---

## 10. 当前本机构建环境

| 组件 | 已探测值 | P0-06 判定 |
|---|---|---|
| Unreal Engine | 5.8.2，Changelist 56702186，Compatible 55116800，`++UE5+Release-5.8` | 已安装，可进入 P0-08 锁定 |
| Visual Studio | Community 2026，安装版本 18.9.12112.369 | 已安装 |
| MSVC | 14.51.36231 | 已安装 x86/x64 工具目录 |
| MSBuild | VS 安装目录下存在 | 未加入当前 PowerShell PATH，脚本必须使用锁定路径或开发环境入口 |
| Windows SDK | 10.0.26100.0 | 已安装 |
| PowerShell | 7.6.4 | 已安装 |
| .NET SDK | 10.0.400 | 已安装；不等于已具备 .NET Framework 3.5 Web 构建环境 |
| CMake/Ninja | 当前 shell PATH 未发现 | P0-08 安装并锁定，或使用 UE/VS 随附的受控路径 |

当前环境适合创建新工程，但不能直接证明 VS2026 可以无损打开 VS2003/2005/2008 `.vcproj`。转换必须发生在 `Rebuild` 的副本中，并保留原工程哈希作为证据。

---

## 11. 最终架构与遗留证据边界

```text
只读老源码/客户端/SQL Server 快照
        │
        ├── Evidence Only
        │     ├─ 源码/SQL/协议/行为分析
        │     ├─ 可选 Release|Win32 隔离实验
        │     └─ Canonical 数据与测试向量
        │
        └── Product Rebuild（从第一天即最终架构）
              ├─ Linux x64 + C++20 + CMake/Ninja
              ├─ PostgreSQL 18 + libpq Adapter
              ├─ TLS/Asio/Protobuf
              ├─ UE 5.8.2 客户端
              ├─ OCI + OpenTelemetry
              └─ 强制工程与代码质量门禁
```

遗留证据与新产品通过测试向量、字段映射、Canonical 数据和行为结果连接，不通过运行时兼容层连接。不得让新工程包含 D3D/MFC/ADO/ACE 头文件，也不得让 Linux 服务链接任何老 x86 静态库。

---

## 12. 可选遗留研究构建步骤

### 12.1 准备阶段

> 本节只在关键行为证据不足且研究任务获批时执行，不是新后端实施前置。

1. 以 Manifest 和本报告作为输入基线。
2. 在 `Rebuild/LegacyCompat` 中建立源码工作副本或生成式补丁层；原目录继续只读。
3. 固定源文件编码策略。老源码很可能混有 ANSI/GBK；转换前保存字节哈希，转换后做中文字符串抽检。
4. 固定 `Release|Win32`，生成工程转换日志和每处人工修订记录。
5. 为第三方/平台二进制建立 `THIRD_PARTY.yml`：文件哈希、架构、来源、许可、消费者和替换负责人。

### 12.2 编译阶段

1. 先编译 ACE、Lua、TinyXML；记录编译器诊断，不全局关闭警告。
2. 编译 ServerCommon，并把 ADO `#import` 路径改为受控构建参数/生成步骤，修改仅存在于 Rebuild 副本。
3. 编译 GameServer 和 GatewayManager，确认输出名与链接配置一致。
4. 编译 loginServer/Gateway，建立无数据库或测试数据库的进程启动冒烟。
5. 配置临时 SQL Server 实例，按受控顺序恢复 login/world/log 等 schema 和存储过程。
6. 编译 DBCenter，然后接通登录、角色列表最小路径。
7. 编译 WorldServer/InstServer；只用 Release，确认没有 `FJGameServer.lib`。
8. 最后恢复奖励、商城、日志和外围服务。

### 12.3 运行验证

每个服务至少记录：

- 可执行文件/库 SHA-256、编译器、配置和源码基线 ID。
- 进程启动参数、配置模板和 Secret 变量名。
- 监听地址、依赖服务、数据库和启动顺序。
- 正常启动、缺依赖、数据库失败、断线、重复登录、正常退出日志。
- 资源占用、线程数、端口、异常退出码和最小健康检查。

---

## 13. 阻塞项与处置矩阵

| ID | 严重度 | 阻塞/风险 | 影响 | 处置 | 验收证据 |
|---|---|---|---|---|---|
| BLD-01 | 高 | `.vcproj` 7.10/8.00/9.00 不作为现代长期构建格式 | 全部老工程 | 在 Rebuild 转换副本；新代码用 CMake/UBT | 转换日志 + 干净构建 |
| BLD-02 | 高 | 关键商业/平台库为 x86、旧 CRT | 遗留研究 | 与产品完全隔离；新实现不链接旧库 | Linux/UE 产品产物无旧库链接 |
| BLD-03 | 高 | ADO `msado15.dll` 路径与 `SQLOLEDB` | 老数据库语义提取 | 新后端不引入 ADO；将行为重写到 Domain/PostgreSQL | PostgreSQL 契约与迁移测试 |
| BLD-04 | 高 | FastDebug 缺 `FJGameServer.lib` | World/Inst | 首轮 Release；调查历史意图 | Release 链接通过；FastDebug 有明确去留 |
| BLD-05 | 高 | 历史凭据/地址痕迹 | 安全与发布 | P0-14 Secret Store、扫描、轮换 | 扫描报告无明文 Secret |
| BLD-06 | 中 | LoginWeb 为 .NET Framework 3.5 | Web 管理 | 提取行为后重写 | 新 API/管理端契约通过 |
| BLD-07 | 中 | D3D9/D3DX/Miles/AH 绑定 | 老客户端 | 参考构建隔离；UE 替换 | UE 垂直切片不链接旧引擎库 |
| BLD-08 | 中 | Max 8/9/2010、FBX 2008、MFC | 美术工具 | 只构建第一方必要工具；新 CLI 去 DCC 依赖 | 五类黄金资产可重复转换 |
| BLD-09 | 中 | 老库许可、版本和漏洞状态未完整登记 | 发布 | 建第三方物料清单/SBOM 与替换期限 | 发布依赖审核通过 |
| BLD-10 | 中 | 源码编码/中文字符串可能在转换中损坏 | 全工程 | 字节基线、编码检测、抽样和测试 | 无静默乱码；差异可审计 |
| BLD-11 | 中 | `ServerCode/bin` 缺少完整运行产物/拓扑 | 服务复现 | 从配置、脚本、端口和进程引用恢复拓扑 | 一键启动/停止与健康报告 |
| BLD-12 | 中 | 老协议/结构中固定数组和位宽 | 新旧互通 | 定宽 Schema、边界测试、版本协商 | 最大 ID/长度测试通过 |

---

## 14. P0-06 完成标准核对

| 验收项 | 状态 | 证据 |
|---|---|---|
| 全部 Solution/Project 已盘点 | ✅ | 33 `.sln`、285 `.vcproj`、1 `.csproj`、8 `.dsp`、4 `.dsw` |
| 工具链年代与目标平台已盘点 | ✅ | VS2003/2005/2008、Win32/历史移动/x64 SDK 示例矩阵 |
| 第三方源码和 SDK 已盘点 | ✅ | ACE、Lua、TinyXML、Protobuf、FreeType、zlib、gtest、DX9、Max、FBX、MFC 等矩阵 |
| 服务与数据库依赖已盘点 | ✅ | 主 15 工程、外围服务、ADO/OLE DB、SQL Server 和 5 份 SQL 文件 |
| 随附/生成/系统/缺失链接库已分类 | ✅ | 112 个唯一库；机器可读消费者/配置记录 |
| 可编译性和研究构建顺序已给出 | ✅ | 可选 `Release|Win32` 遗留研究路线与 8 层顺序；产品路线见 ADR-008 |
| x64/UE 现代化边界已明确 | ✅ | 双轨架构、ABI 隔离和替换矩阵 |
| 扫描可重复执行且原目录只读 | ✅ | `Export-BuildInventory.ps1` + `Test-BuildInventory.ps1` |

P0-06 可以关闭。它没有宣称老系统已经成功编译，也不再把老系统可编译作为 P4 前置。P4 直接建设 Linux/PostgreSQL 新后端；遗留编译只在行为证据不足时单独立项。

---

## 15. 下一步建议

1. **P0-08**：生成正式 `toolchain.lock.json`、VS 组件清单、CMake/Ninja/Windows SDK/UE 调用脚本和干净机安装说明。
2. **P0-10**：建立 `Rebuild/LegacyCompat`、`Rebuild/Server`、`Rebuild/UEClient`、`Rebuild/Shared`、`Rebuild/Tests` 的最小有内容骨架。
3. **P0-14**：先做 Secret 扫描/脱敏，避免证据提取和迁移映射把历史凭据带入新仓库。
4. **后端首个切片**：建立 Linux/C++20/CMake/Ninja 工程，直接完成 Gateway → Account/Character → PostgreSQL 18 的最终架构闭环。
5. **P1 并行准备**：资产解析库不依赖老客户端工程是否编译成功；按 Package/TBL/五类黄金样本推进。

---

## 16. 复现命令

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.BuildInventory\Export-BuildInventory.ps1'
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.BuildInventory\Test-BuildInventory.ps1'
```

第一次命令重新生成 JSON；第二次验证 285 个 `.vcproj` 的存在性和 SHA-256、基线数量、解析结果以及 VS/UE 环境。环境 JSON 包含采集时间，因此重跑后的文件哈希变化是预期行为；工程内容哈希变化则会被验证器识别。
