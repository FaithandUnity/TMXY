# TMXY Contracts

这里保存客户端、后端、工具和数据流水线共同消费的唯一契约源。

- `proto/`：版本化 Protobuf 源文件；
- `data-schema/`：内容中间格式 Schema，首次实际 Schema 出现时再创建；
- `generated/`：只允许协议生成器写入，首次生成时再创建。

已经发布的 Protobuf 字段号不得复用。生成代码不能手工修改，也不能在依赖未锁定前提交由不同
protoc 版本产生的临时结果。
