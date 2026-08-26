# Gateway app

职责：公网协议入口的 Composition Root、配置、生命周期和适配器组装。

当前仅输出结构化启动事件，用于验证最终工程边界。这里不能放账号、角色、物品或其他业务规则。
Asio/TLS、Protobuf 和 OpenTelemetry 会在相应 Adapter 及依赖 lockfile 就绪后注入。
