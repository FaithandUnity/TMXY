# 《天命西游／QQ西游》最终目标技术架构

> 状态：Accepted  
> 版本：V1.0  
> 日期：2026-08-26  
> 适用范围：`Rebuild` 中全部新客户端、后端、工具、Schema、数据库和部署工程  
> 核心决策：从第一份新代码开始使用最终架构，不建设准备废弃的 Windows/SQL Server 过渡产品

---

## 1. 不可变技术基线

| 领域 | 最终决策 | 不允许的过渡做法 |
|---|---|---|
| 客户端 | Unreal Engine 5.8.2、Windows x64 | 在老 D3D9 客户端上继续堆新功能 |
| 后端操作系统 | Linux x86_64，OCI 容器交付 | 把新的产品服务建立为 Windows Service |
| 后端语言 | C++20 | 新代码复制 VS2008/Win32/ADO 风格 |
| 构建系统 | CMake Presets + Ninja；依赖使用 manifest/lockfile | 手工配置 IDE include/lib 路径 |
| 数据库 | PostgreSQL 18.x，固定大版本并及时升级当前小版本 | 新后端先接 SQL Server、以后再迁移 |
| 数据库客户端 | 官方 `libpq`，封装在 `PersistencePostgres` 适配器内 | 让 `PGconn`、SQL 字符串或 ORM 类型进入业务域 |
| 缓存/临时状态 | Valkey/Redis 协议兼容服务，仅保存可重建的会话、缓存、限流和短期协调状态 | 把角色、物品、货币真值只存缓存 |
| Schema/协议 | Protobuf + 显式消息信封、版本、长度、错误码；Schema 为唯一来源 | 裸发 C++ struct、依赖内存对齐或枚举顺序 |
| 边缘网络 | Asio 异步 TCP/TLS、明确分帧和背压 | 阻塞式每连接线程、ACE 类型渗透业务层 |
| 内部通信 | Protobuf 契约；同步 RPC 与异步事件分离；权威写入保持单一所有者 | 多个服务直接修改同一领域表 |
| 可观测性 | OpenTelemetry Trace/Metrics、结构化日志、Prometheus 兼容指标 | 只写文本日志、没有 Correlation ID |
| 部署 | 同一 OCI 镜像贯穿 Dev/CI/Staging/Production；配置外置 | 每个环境手工编译不同二进制 |
| Secret | Secret Store/部署平台注入 | 密码、密钥、连接串进入源码或 Git |

PostgreSQL 18 作为项目固定大版本。只升级 18.x 当前安全/修订版本；跨主版本必须走独立 ADR、备份恢复和性能回归。PostgreSQL 官方对每个大版本提供五年支持，并建议运行对应大版本的当前小版本。

精确的编译器、CMake、Ninja、依赖包和容器镜像摘要写入 P0-08 的 Lockfile；允许安全补丁更新，但不得改变本节架构边界。

---

## 2. 老源码和 SQL Server 的位置

老服务端不是新产品运行时的一部分。它仅有三种用途：

1. **行为证据**：解释登录、角色、战斗、任务、经济、协议和异常流程。
2. **数据来源**：读取旧 SQL Server Schema、存储过程语义和历史数据，转换到规范化迁移格式。
3. **回归 Oracle**：对同一输入比较老实现与新实现结果；不能满足时记录独立重建设计。

强制边界：

- 新后端不链接 ACE 5.4.2、ADO、COM、旧 Protobuf、旧 Tencent 平台库或任何 x86 静态库。
- 新后端不连接 SQL Server，不写 SQL Server，不实现双运行时数据库访问。
- SQL Server 读取工具属于 `Tools/TMXY.LegacyMigration`，只在受控离线迁移环境运行。
- 老代码允许被独立编译用于研究，但其产物不得进入 Production 镜像。
- 旧存储过程中的业务规则要么迁入 C++ Domain/Application，要么显式重写为 PostgreSQL 约束/查询；不能逐字翻译后继续隐藏业务。

这意味着项目不存在“先把老服务端改好，再把它演进成最终服务端”的路线。新后端与 UE 客户端从同一套新 Schema 和契约开始开发。

---

## 3. 逻辑架构

```text
UE 5.8.2 Client
        │ TLS + Versioned Protobuf Frames
        ▼
    Edge Gateway
        │ authenticated session / rate limit / routing
        ├───────────────┬────────────────┬─────────────────┐
        ▼               ▼                ▼                 ▼
 Identity         Character/World     Instance         Social
        │               │                │                 │
        └───────────────┴──────┬─────────┴─────────────────┘
                                ▼
                         Economy / Mail / Ops
                                │
                    typed ports + transactions
                                ▼
                         PostgreSQL 18
                                │
                    backup / replica / audit

Ephemeral only: Valkey session/cache/rate-limit
Cross-cutting: Config, Secret, OpenTelemetry, Health, Audit
```

这些名称是稳定的领域边界，不代表第一天就必须部署十几个微服务。工程从一开始按边界分模块，部署单元按隔离、扩缩容和故障域合并：

- `tmxy-gateway`：公网连接、TLS、会话验证、协议限流和路由；不执行业务写入。
- `tmxy-account`：身份、凭据、封禁、会话签发；不保存角色玩法数据。
- `tmxy-world`：角色进入、地图目录、基础世界状态和持久角色命令。
- `tmxy-instance`：副本/战斗实例，可横向扩展；通过命令提交持久化结果。
- `tmxy-social`：聊天、好友、公会等社交领域。
- `tmxy-economy`：物品、货币、交易、商城、邮件附件等强审计领域。
- `tmxy-ops`：健康、配置状态和受审计运营 API；不复用旧 LoginWeb。

初期允许 `world/social/economy` 在同一进程中组合，以减少分布式复杂度；模块依赖、数据库所有权和协议契约保持最终边界不变。拆分部署只改变 Composition Root 和部署清单，不重写领域代码。

---

## 4. 后端分层和依赖方向

每个领域模块统一采用 Ports and Adapters：

```text
Domain
  ▲
Application
  ▲
Ports (interfaces owned by Application/Domain)
  ▲
Adapters: PostgreSQL / Network / Cache / Clock / External Platform
  ▲
App Composition Root
```

允许依赖：

- `Foundation`：定宽 ID、时间、错误、Result、少量无业务含义工具。
- `Domain` → `Foundation`。
- `Application` → `Domain` + 自己拥有的 Ports。
- `Adapters` → 对应 Port + 第三方库。
- `Apps` → 组装模块和适配器，不包含业务规则。

禁止依赖：

- Domain/Application 依赖 Asio、libpq、OpenTelemetry SDK、容器环境或 UE 类型。
- 一个领域直接 include 另一个领域的内部实现。
- Gateway 直接写角色、物品或货币表。
- 数据库 Repository 反向调用网络 Session。
- `Shared/Common/Utils` 成为无边界代码堆放区。

跨领域只使用公开命令、查询、事件和强类型 ID。循环依赖由 CI 的架构测试阻断。

---

## 5. 数据架构：PostgreSQL 从第一天启用

### 5.1 数据所有权

| PostgreSQL Schema | 所有者 | 典型数据 | 其他服务访问方式 |
|---|---|---|---|
| `identity` | account | 账号、凭据摘要、封禁、会话元数据 | API/事件，禁止跨 Schema 写 |
| `character` | world | 角色、位置、外观、成长、任务 | 命令/查询接口 |
| `economy` | economy | 物品、背包、货币、交易、商城、附件 | 强审计命令 |
| `social` | social | 好友、公会、社交关系 | API/事件 |
| `operations` | ops | 运营动作、审批、审计 | 只通过受权 API |
| `content` | content pipeline | 内容版本、表版本、发布摘要 | 只读运行时加载 |

同一 PostgreSQL 集群可以承载多个 Schema，但每张表只有一个写入所有者。不得以“都在一个数据库”为理由跨领域直接更新。

### 5.2 数据访问规则

- C++ 只通过 Repository/Unit of Work Port 访问数据。
- `libpq` 仅出现在 `Adapters/PersistencePostgres`。
- 全部查询参数化；不拼接用户输入。
- 明确事务边界、隔离级别、幂等键、超时和重试条件。
- 重试只针对确认安全的瞬时错误；经济写入必须使用业务幂等键。
- 连接池有上限、排队、超时、熔断和指标。
- 生产 DDL 只通过版本化 Migration 执行；应用启动不自动执行不可逆 DDL。
- 核心经济表使用数据库约束和审计流水，不只靠 C++ `if`。
- 时间统一 UTC，文本统一 UTF-8，金额/数量使用整数最小单位，禁止浮点货币。

### 5.3 Migration 结构

```text
Backend/database/
├─ migrations/
│  ├─ identity/
│  ├─ character/
│  ├─ economy/
│  ├─ social/
│  ├─ operations/
│  └─ content/
├─ seeds/
│  ├─ dev/
│  └─ test/
└─ verification/
```

每个 Migration 只做一个可审查变更，包含版本、目的、前置条件、Up、可行的 Down/恢复方案和校验查询。大型回填与 Schema 变更分离。

### 5.4 SQL Server 到 PostgreSQL 的离线迁移

```text
SQL Server readonly snapshot
        ↓ extract (no product dependency)
Canonical JSONL/Parquet + checksums
        ↓ validate/map IDs/encoding/types
PostgreSQL staging schema
        ↓ integrity and reconciliation
PostgreSQL owned schemas
```

迁移工具必须输出：源主键、目标主键、行数、哈希/总量、拒绝记录、字段映射版本和重跑 ID。物品、货币和邮件附件必须做总量守恒与所有权唯一性检查。

---

## 6. 协议与网络

### 6.1 客户端协议

客户端与 Gateway 使用：

- TCP/TLS 长连接；
- 固定长度网络序消息头；
- Magic、ProtocolMajor、ProtocolMinor、MessageType、PayloadLength、RequestId、Flags；
- Payload 为 Protobuf；
- 严格最大帧长、读写超时、背压、速率限制和非法包计数；
- 登录后使用短期会话 Token；
- 所有修改操作拥有请求 ID/幂等语义。

旧客户端协议只作为分析证据。新 UE 客户端不先实现一套将来删除的旧协议兼容层。

### 6.2 内部通信

- 查询/RPC 与异步领域事件分开定义。
- 权威写入有唯一服务所有者。
- 事件至少包含 `event_id`、`event_type`、`schema_version`、`occurred_at`、`producer`、`correlation_id`。
- 需要可靠发布的数据库事件采用 Transactional Outbox。
- 消费者按 `event_id` 幂等。
- 禁止用消息总线实现需要同一事务保证的物品/货币转移。

---

## 7. 仓库和工程结构

```text
Rebuild/
├─ Apps/
│  └─ UEClient/
├─ Backend/
│  ├─ CMakeLists.txt
│  ├─ CMakePresets.json
│  ├─ cmake/
│  ├─ apps/
│  │  ├─ gateway/
│  │  ├─ account/
│  │  ├─ world/
│  │  ├─ instance/
│  │  ├─ social/
│  │  ├─ economy/
│  │  └─ ops/
│  ├─ modules/
│  │  ├─ foundation/
│  │  ├─ identity/
│  │  ├─ character/
│  │  ├─ world/
│  │  ├─ combat/
│  │  ├─ economy/
│  │  ├─ social/
│  │  └─ content/
│  ├─ adapters/
│  │  ├─ network_asio/
│  │  ├─ persistence_postgres/
│  │  ├─ cache_valkey/
│  │  └─ telemetry_otel/
│  ├─ database/
│  └─ tests/
├─ Contracts/
│  ├─ proto/
│  ├─ data-schema/
│  └─ generated/
├─ Tools/
│  ├─ TMXY.Manifest/
│  ├─ TMXY.BuildInventory/
│  ├─ TMXY.FormatCore/
│  ├─ TMXY.Package/
│  ├─ TMXY.Table/
│  ├─ TMXY.AssetCLI/
│  ├─ TMXY.LegacyMigration/
│  └─ TMXY.ProtocolGen/
├─ Data/
├─ Deploy/
│  ├─ containers/
│  ├─ compose/
│  ├─ kubernetes/
│  └─ observability/
├─ Tests/
│  ├─ Golden/
│  ├─ Contract/
│  ├─ Integration/
│  └─ Performance/
└─ Docs/
   ├─ ADR/
   ├─ Architecture/
   ├─ Standards/
   ├─ Formats/
   └─ Runbooks/
```

目录建立规则：只有在存在首个实际文件和负责人时创建目录；禁止为了“看起来完整”生成大量空目录。

---

## 8. 构建、依赖与交付

- Backend/Tools 使用 CMake Presets，至少提供 `linux-clang-debug`、`linux-clang-release`、`windows-msvc-debug` 和 CI preset。
- Ninja 是标准生成器；IDE 只消费 Preset，不拥有隐藏构建配置。
- 第三方包通过 manifest + lockfile 固定；Production 构建禁止从浮动分支下载依赖。
- Linux Release 是后端发布权威构建；Windows 后端构建仅用于开发便利和跨平台检查。
- 每个 app 生成独立、最小权限、非 root OCI 镜像。
- 镜像使用不可变 tag 和 digest；内含 commit、Schema、协议和内容版本标签。
- Dev 使用同一镜像配合 Compose；Staging/Production 使用 Kubernetes 或等价 OCI 编排。二者不改变服务代码和配置模型。
- CI 必须执行格式、静态分析、单元、架构、契约、PostgreSQL 集成、镜像扫描和 SBOM。

---

## 9. 质量和维护性硬约束

详细规则见 [ENGINEERING-STANDARD.md](../Standards/ENGINEERING-STANDARD.md)。架构层面的不可妥协要求：

- 手写 C/C++ `.h/.hpp` 硬上限 500 行，`.c/.cc/.cpp` 硬上限 1000 行。
- 新增函数目标不超过 60 个逻辑行；超过 100 行 CI 失败。
- 单文件不得承载多个无关职责；禁止 God Object 和万能 `Utils`。
- 第三方类型不能穿越 Adapter 边界。
- 业务逻辑必须在 Domain/Application，不能散落在网络回调、SQL Repository、UE Widget 或 Controller。
- 新模块必须同时提交边界说明、测试和可观测性。
- 所有例外必须有带到期日的 ADR/waiver；生成代码和第三方源码只能放入明确豁免目录。

---

## 10. 从第一天执行的开发切片

首个后端纵向切片直接使用最终组件：

```text
UE/Test Client
  → Linux x64 Gateway (C++20/Asio/TLS/Protobuf)
  → Account + Character Application
  → PostgreSQL 18
  → OpenTelemetry + structured logs + health
  → OCI image + CI
```

首个切片验收：

1. 在 Linux CI 编译、测试和生成镜像。
2. PostgreSQL Migration 从空库创建 Schema。
3. 创建测试账号、创建角色、角色列表、进入世界占位流程全部使用新协议。
4. 数据库失败、重复请求、非法帧、断线和重启有自动测试。
5. 没有任何 SQL Server、ADO、ACE、Win32 或 x86 库依赖。
6. 所有手写文件通过规模、格式、静态分析和架构依赖门禁。

---

## 11. 已决定与尚待参数化的内容

已决定，不再反复选型：

- Linux x64、C++20、CMake/Ninja、PostgreSQL 18、libpq、Asio、Protobuf、OCI、OpenTelemetry。
- 新后端不从 SQL Server/Windows 运行时演进。
- 模块化领域边界、Ports and Adapters、单写入所有者和严格代码规模门禁。

仍需 P0-08/P0-09 参数化，但不会改变架构：

- Clang/CMake/Ninja/依赖库的精确补丁版本和镜像 digest。
- 目标在线人数、分区方式、连接数、延迟、RPO/RTO。
- 单机/集群节点规格、Kubernetes 副本和自动扩缩容阈值。
- PostgreSQL HA 拓扑、备份保留、只读副本数量。
- Valkey 是否在首个切片启用；未启用时不允许用进程内状态形成不可迁移依赖。

---

## 12. 参考依据

- [PostgreSQL Versioning Policy](https://www.postgresql.org/support/versioning/)：大版本五年支持、建议跟随当前小版本。
- [PostgreSQL 18 libpq](https://www.postgresql.org/docs/18/libpq.html)：官方 C 客户端接口及异步、Pipeline、TLS 等能力。
- [CMake Presets](https://cmake.org/cmake/help/latest/guide/user-interaction/index.html#presets)：共享配置、构建和测试入口。
- [OpenTelemetry C++ Instrumentation](https://opentelemetry.io/docs/languages/cpp/instrumentation/)：C++ 服务显式埋点和 SDK 使用边界。
