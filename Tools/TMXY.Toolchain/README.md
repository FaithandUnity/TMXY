# TMXY.Toolchain

本工具用于 P0-08 的主机环境采集、工具链锁定验证和 PostgreSQL 18.6 运行时冒烟测试。

## 运行顺序

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Test-HostEnvironment.ps1'

& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Test-ToolchainLock.ps1' `
  -RunPostgresSmoke

& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.Toolchain\Test-RegistryConnectivity.ps1'
```

第一条命令会覆盖生成：

- `E:\QQXYCodeDev\Rebuild\Data\Toolchain\host-environment.json`

第二条命令会覆盖生成：

- `E:\QQXYCodeDev\Rebuild\Data\Toolchain\validation.json`

第三条命令会对 Docker Hub 的 DNS、IPv4、IPv6 和基础镜像 manifest 做只读检查，并覆盖生成：

- `E:\QQXYCodeDev\Rebuild\Data\Toolchain\registry-diagnostics.json`

第二条命令不会修改老源码或客户端。启用 `-RunPostgresSmoke` 时，只会建立一个名称带随机后缀、禁用容器网络、数据目录位于 tmpfs 的临时 PostgreSQL 容器，执行版本和本地 Unix socket 可连接性检查，然后在 `finally` 中删除该容器及其临时数据。

## 结果解释

- `PASS`：主机、客户端、数据库和后端构建镜像的不可变摘要均已冻结。
- `PASS_WITH_PENDING_FREEZE_ITEMS`：当前开发环境可用，但后端构建器仍有未冻结摘要；P0-08 不能关闭。
- `FAIL`：必要环境与锁定清单不一致，不能继续创建正式构建基线。

权威版本与干净机步骤见 `E:\QQXYCodeDev\Rebuild\Docs\Build\TOOLCHAIN-SETUP.md`。
