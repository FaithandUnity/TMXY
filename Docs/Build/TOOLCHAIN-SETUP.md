# TMXY 最终工具链锁定与干净机安装说明

> 文档状态：V0.2（P0-08 已完成）
> 最近更新：2026-08-26
> 权威机器可读清单：`E:\QQXYCodeDev\Rebuild\Data\Toolchain\toolchain.lock.json`
> 当前状态：官方 Debian 基础摘要、Clang 精确 revision、最终构建器摘要、SBOM 和 clean-builder 复建证据均已冻结；系统 Registry DNS 异常仍保留为网络诊断项，但不再阻塞锁定镜像的本地构建。

## 1. 目标和边界

这套工具链从第一天就服务最终架构，不建立“先在 Windows 跑老后端、以后再迁 Linux”的临时路线。

| 工作 | 权威环境 | 说明 |
|---|---|---|
| UE 客户端、Editor、导入插件 | Windows 11 x64 + UE 5.8.2 + VS 2026 | 与 Epic Windows 工具链一致 |
| 后端开发检查 | Windows IDE 可编辑；实际编译使用容器 | 本机无需单独安装 Clang/CMake/Ninja/Conan |
| 后端 CI/Release | Linux amd64 不可变构建镜像 | 唯一发布权威，C++20 |
| PostgreSQL 开发和 CI | 锁定 digest 的 Linux 容器 | 当前锁定 PostgreSQL 18.6 |
| 生产数据库 | PostgreSQL 18 当前受支持小版本 | 不使用 SQL Server 作为过渡库 |

独立 Ubuntu/Debian WSL 发行版不是必要依赖。Docker Desktop 自己的 WSL2 Linux 引擎已经提供容器运行层；再安装一套用户发行版会形成第二套容易漂移的编译环境。需要命令行 Linux 调试时可以额外安装，但不能把它的系统包当成发布依赖。

## 2. 冻结版本

### 2.1 已锁定并在当前机器验证

| 组件 | 版本/摘要 | 用途 |
|---|---|---|
| Unreal Engine | 5.8.2，CL 56702186，Compatible CL 55116800 | 客户端、Editor 和内容管线 |
| Visual Studio | Community 2026，18.9.12112.369 | UE Windows 编译 |
| MSVC | 已安装 14.51.36231（编译器报告 14.51.36256） | UE Editor 编译和 Automation 已通过，但 UE 5.8 提示高于推荐的 14.50.35717 |
| Windows SDK | 10.0.26100.0 | UE Windows 平台 SDK |
| PowerShell | 7.6.4 | Windows 自动化入口 |
| .NET SDK | 10.0.400 | UE/工具辅助构建 |
| Docker Desktop | 4.87.0 | WSL2 Linux 容器宿主 |
| Docker Engine | 29.7.2，linux/amd64 | 开发容器运行时 |
| Docker Compose | 5.4.0 | 本地服务编排 |
| Docker Buildx | 0.36.1-desktop.1 | 多阶段和可复现镜像构建 |
| PostgreSQL | 18.6 Alpine，`postgres@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2` | 开发/CI 数据库 |
| Debian builder base | `bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171` | 官方多平台 index；linux/amd64 manifest 为 `sha256:5ae3c39e...b867` |
| Backend builder | `tmxy-backend-builder@sha256:d3bcb5acf5e7eda4a2138bb6da58ce93d928423a7ee50071d5df71feec8d975d` | 本地 OCI manifest；发布时只能原样推送，禁止重建 |

### 2.2 后端构建器锁定内容

| 组件 | 目标版本 | 冻结状态 |
|---|---:|---|
| Debian 基础镜像 | `bookworm-slim` | index 与 linux/amd64 manifest 均已冻结并逐 blob 验证 |
| Clang/clang-tidy/clang-format/lld | 21.1.8 | apt revision `1:21.1.8~++20251221032947+2078da43e25a-1~exp1~20251221153113.67` |
| CMake | 4.4.2 | 官方 x86_64 归档 SHA-256 `3ada9a3f...1956c` |
| Ninja | 1.11.1，Debian revision `1.11.1-2~deb12u1` | 已定 |
| Conan | 2.31.2 | 主 wheel 及全部传递 wheel 都由 `conan-requirements.txt` 的 SHA-256 锁定 |
| Protobuf/protoc | 35.1 | 版本及官方归档 SHA-256 已定；Conan package revision 待 P4 |
| Asio | 1.38.2 | 版本已定；Conan package revision 待 P4 |
| libpq | PostgreSQL 18 ABI | major 已定；Conan package revision 待 P4 |

版本选择依据：CMake 4.4.2、LLVM 官方 Bookworm 21 分支和 PostgreSQL 18.6 已由实际制品摘要冻结。P4 引入真实第三方 C++ 依赖配方时，仍必须提交 Conan host/build profile 与 application lockfile；该后续职责不重新打开 P0-08 的构建工具链锁。

## 3. 干净 Windows 开发机安装

### 3.1 硬件和 Windows

1. 在 BIOS/UEFI 中启用 CPU 虚拟化。
2. 使用 Windows 11 x64；系统盘和工作盘预留足够的 Docker/UE 空间。
3. 以管理员身份执行：

```powershell
wsl.exe --install --no-distribution
wsl.exe --update
wsl.exe --set-default-version 2
```

4. 重启，随后检查：

```powershell
wsl.exe --version
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
```

这里使用 `--no-distribution`，因为正式编译发生在 Linux 容器，不要求额外 Ubuntu 用户发行版。

### 3.2 Docker Desktop

1. 安装 Docker Desktop for Windows。
2. 选择 WSL 2 backend 和 Linux containers。
3. 不启用不受控的 insecure registry；公司镜像代理必须由基础设施配置 TLS 和审计。
4. 检查引擎：

```powershell
docker version
docker info
docker compose version
docker buildx version
```

验收要求是 Server 的 OS 为 `linux`、Architecture 为 `amd64`。Docker Desktop 或 Engine 的补丁版本可以升级，但升级后必须重新运行本文件第 5 节的验证；CI 构建器摘要不会因此自动变化。

### 3.3 UE 与 Windows 编译器

1. 安装项目锁定的 Unreal Engine 5.8.2。
2. 安装 Visual Studio 2026 的 C++、Windows SDK、.NET 与 Unreal Engine 开发工作负载。
3. 当前已验证基线是 MSVC 14.51.36231（编译器 14.51.36256）和 Windows SDK 10.0.26100.0；UE 5.8 的 UBT 明确提示 14.51 高于推荐的 14.50.35717。Editor、Development、Shipping、Pak/IoStore 和启动回归已通过，14.51 由截至 2026-10-25 的源码指纹绑定 waiver 临时覆盖，不能静默续期。
4. UE 补丁、Changelist、MSVC minor 或 Windows SDK 发生变化时，不静默接受；先建立升级分支并跑客户端空工程、导入插件和打包回归。
5. Waiver 及资格测试见 `Docs/Build/MSVC-14.51-WAIVER.md` 与 `Tests/Integration/Test-UEPackagingQualification.ps1`。安装并验证 MSVC 14.50.35717 会立即取代 waiver；UE、MSVC、SDK 或绑定源码变化时必须重新资格验证。

### 3.4 仓库位置

工作区保持在 Windows 本地 NTFS 路径 `E:\QQXYCodeDev`。以下目录只读：

- `ClientCode`
- `ServerCode`
- `ToolCode`
- `DevDoc`
- `天命西游`

构建缓存、生成代码、导出资产和数据库卷只能进入 `Rebuild`、Docker volume 或明确的临时目录。

## 4. 后端构建器的不可变冻结流程

系统 DNS 连接 Docker Hub Registry 时仍会返回异常地址，但 P0-08 已使用受控的官方获取路径完成，不改变技术架构，也没有修改系统 DNS/hosts。

2026-08-26 的诊断进一步确认：系统 DNS 对 `registry-1.docker.io` 的 A/AAAA 查询异常；即使显式指定多个公共 DNS 地址也得到相同结果，IPv4 与 IPv6 HTTPS 均超时，说明故障位于当前网络的 DNS/代理出口而不是 Docker Engine。诊断证据保存在 `Rebuild\Data\Toolchain\registry-diagnostics.json`。不要硬编码 CDN IP，因为 registry 地址会变化。

已按以下顺序完成，后续升级也不能跳步：

1. 解析 `debian:bookworm-slim` 的官方多平台 manifest，并选择其中 `linux/amd64` 摘要。
2. 将基础镜像写成 `debian:bookworm-slim@sha256:<manifest-digest>`；Dockerfile 不允许裸 tag。
3. 在镜像内安装 Clang 21、CMake 4.4.2、Ninja 1.11.1 和 Conan 2.31.2。
4. 输出 `clang --version`、`cmake --version`、`ninja --version`、`conan --version`，记录 apt 包完整 revision。
5. 构建 `linux/amd64` 工具链镜像，执行最小 C++20 configure/build/test。
6. 记录最终镜像 digest 和 SBOM；使用一个全新 Docker-container builder 再构建一次并比较结果。
7. 更新 `toolchain.lock.json`，锁校验的 pending 数量归零。

官方基础镜像由 `Import-OfficialDebianBase.ps1` 获取：Google DoH 只用于动态选择 Registry 地址，请求仍以 `registry-1.docker.io` 作为 SNI/证书主机名并使用系统信任链；每个 manifest、config 与 layer 均校验官方 descriptor 的 size/SHA-256。Bearer token 仅存在于临时容器内，未进入参数、环境、文件或报告。独立 clean builder 从该已验证 OCI layout 读取同一官方摘要，因此不依赖污染的系统 DNS。

最终资格报告 `Data/Toolchain/backend-toolchain-qualification.json` 为 `PASS`：两个独立镜像均为 linux/amd64、非 root 用户，218 个 Debian 包清单、Conan 环境、工具版本、官方基础层和 4 个后端构建产物 SHA-256 全部一致；两个镜像均在 `--network none`、Backend 只读挂载下完成 CMake configure/build 和 2/2 CTest。CycloneDX 1.5 SBOM 位于 `Data/Security/tmxy-backend-builder.sbom.cdx.json`，包含 343 个组件；Conan 环境显式锁定 `setuptools==83.0.0` 与 `pip==26.2`，消除旧版本的全部已知 Trivy 漏洞。

检查基础镜像信息的命令：

```powershell
docker buildx imagetools inspect debian:bookworm-slim
```

如果仍失败，先检查 Docker Desktop 的代理、DNS 和 IPv6 出站链路。不得通过关闭 TLS 校验或引用未知第三方镜像解决。允许的离线路径是：由受控联网构建机导出 OCI archive、SBOM 与 SHA-256，在本机校验后导入；锁定清单仍记录原始仓库摘要和内部制品摘要。

可以重复运行只读诊断：

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Test-RegistryConnectivity.ps1'
```

## 5. 当前机器验证

### 5.1 重新采集主机环境

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Test-HostEnvironment.ps1'
```

输出写入 `E:\QQXYCodeDev\Rebuild\Data\Toolchain\host-environment.json`。检测器只读取主机、Docker、UE/VS 盘点结果和本地 PostgreSQL 镜像，不扫描密码、Token 或证书。

重建并资格验证后端构建器：

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Build-BackendToolchain.ps1'
```

只复核已存在的最终/clean 镜像并重新生成 SBOM 与证据时使用 `-Mode QualifyExisting`。

### 5.2 校验锁并运行数据库冒烟

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Test-ToolchainLock.ps1' `
  -RunPostgresSmoke
```

数据库测试创建随机命名的临时容器，禁用容器网络，使用 PostgreSQL 18 镜像声明的 `/var/lib/postgresql` tmpfs 数据目录，不映射宿主端口，仅通过容器内 Unix socket 检查，测试完成或异常时都删除容器。当前预期结果是 `PASS` 且 `pending_freeze_count=0`；其他结果说明必要环境或证据已经漂移。

## 6. 版本升级规则

1. 不使用 `latest` tag，不使用 Conan 无上界范围，不允许开发机临时 apt/pip 包成为隐含依赖。
2. UE、Clang major、CMake minor、Protobuf major、PostgreSQL major 的升级必须写 ADR 并建立迁移/回滚计划。
3. 安全补丁通过独立分支更新摘要和 lockfile；完成单测、集成测试、数据库迁移演练、资源导入回归后合并。
4. PostgreSQL 服务端始终运行所选 major 的当前受支持 minor；升级前先验证备份恢复和扩展兼容性。
5. 开发、CI、预发布、生产引用同一制品 digest；不同环境只注入配置和 Secret，不重新编译。

## 7. P0-08 完成标准

- [x] Windows/UE/VS 实际版本已盘点。
- [x] WSL2、Docker Linux engine、Compose、Buildx 已验证。
- [x] PostgreSQL 18.6 开发镜像 digest 已冻结。
- [x] 后端语言、编译器 major、构建系统和依赖管理器版本已选定。
- [x] 主机检测器与数据库冒烟测试已建立。
- [x] 干净机安装和升级规则已形成文档。
- [x] UE 5.8.2 空工程、模块装载和 Automation Test 已通过当前 MSVC 14.51。
- [x] MSVC 14.51 已完成 Editor/Development/Shipping 打包与启动回归，并由截至 2026-10-25 的源码指纹绑定 waiver 覆盖。
- [x] Debian 基础镜像 manifest digest 已冻结。
- [x] 后端工具链镜像已构建，精确包 revision、镜像 digest、SBOM 已记录。
- [x] 干净 builder 的 C++20 configure/build/test 已通过。

`Tools/TMXY.Toolchain/Test-RegistryPreflight.ps1` 使用系统 DNS、IPv4/IPv6 和默认 TLS 校验探测官方 Docker Registry。2026-08-26 的复测结果仍为 `BLOCKED_NETWORK`：双栈 HTTPS 均超时，因此没有关闭 TLS、修改 hosts、使用未知镜像或伪造 digest。证据写入 `Data/Toolchain/registry-preflight.json`。

P0-08 的完成条件已经全部关闭。Registry preflight 的系统 DNS 结果继续作为网络运维诊断保留，不得据此回退到关闭 TLS、固定 CDN IP 或未知镜像。

## 8. 官方参考

- [Microsoft：Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- [Microsoft：Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [Docker：Install Docker Desktop on Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
- [LLVM Debian/Ubuntu packages](https://apt.llvm.org/)
- [CMake 4.4.2 downloads](https://cmake.org/download/)
- [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/)
- [PostgreSQL 18 libpq](https://www.postgresql.org/docs/18/libpq.html)
- [Protocol Buffers version support](https://protobuf.dev/support/version-support/)
- [Conan 2.31.2](https://pypi.org/project/conan/2.31.2/)
- [Asio releases](https://github.com/chriskohlhoff/asio/releases)
