# ADR-011：PostgreSQL 18 作为唯一产品数据库

- 状态：Accepted
- 日期：2026-08-26

## 决策

新后端唯一产品关系数据库为 PostgreSQL 18.x。C++ 使用官方 libpq，并由 `PersistencePostgres` 适配器封装。SQL Server 只作为旧数据离线提取来源，不被新产品服务连接。

## 原因

- 最终部署目标为 Linux x64。
- 避免先实现 ADO/SQL Server 再重写 PostgreSQL 的双重成本。
- 从第一天建立 PostgreSQL Schema、Migration、事务、索引、备份和性能基线。
- 通过 Port/Adapter 隔离数据库 API，使领域逻辑不依赖 libpq 或 SQL。

## 后果

- 旧 T-SQL、存储过程、类型和事务语义必须先解释，再以 C++ 领域逻辑、PostgreSQL SQL 或约束重写。
- 必须建设 SQL Server → Canonical → PostgreSQL 的离线迁移和核对工具。
- PostgreSQL 大版本固定为 18；跟随当前 18.x 修订，跨大版本另立 ADR。

## 禁止事项

- 新服务中的 SQL Server 驱动、ADO、OLE DB 或双数据库 Repository。
- 在 Domain/Application 中暴露 `PGconn`、`PGresult` 或 SQL 字符串。
- 使用缓存替代 PostgreSQL 权威数据。
