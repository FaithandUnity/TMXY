# TMXY Deploy

部署清单只引用已经锁定的 OCI digest。开发、CI、预发布和生产使用相同服务制品，环境差异通过
配置与 Secret 注入，不重新编译程序。

当前提供 PostgreSQL 18.6 开发编排，以及 `Deploy/toolchain` 中已按不可变摘要资格验证的
Linux Clang 21 后端构建器。构建器只生产后端制品，不冒充尚未设计的 Production 运行时镜像；
正式运行时 Dockerfile 必须随首个可部署服务一起建立，并复用已锁定工具链与供应链门禁。
