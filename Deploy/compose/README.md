# Development Compose

当前编排只启动 digest 锁定的 PostgreSQL 18.6。数据库密码必须由仓库外受控文件、CI Secret
Store 或编排平台挂载；本目录不提供带默认密码的 `.env` 文件。

启动前令 `TMXY_POSTGRES_PASSWORD_FILE` 指向 `E:\QQXYCodeDev` 之外、仅当前身份可读的密码文件，
然后执行：

```powershell
docker compose `
  -f 'E:\QQXYCodeDev\Rebuild\Deploy\compose\compose.yaml' `
  up -d --wait
```

停止服务但保留开发数据：

```powershell
docker compose `
  -f 'E:\QQXYCodeDev\Rebuild\Deploy\compose\compose.yaml' `
  down
```

不要随意执行 `down --volumes`，因为它会删除本地 PostgreSQL volume。正式 Migration 角色、应用
角色和最小权限将在 P4 数据库骨架中分别创建。

密码内容不会进入进程环境；Compose 将文件只读挂载为
`/run/secrets/tmxy_postgres_password`，PostgreSQL 通过 `POSTGRES_PASSWORD_FILE` 读取。
