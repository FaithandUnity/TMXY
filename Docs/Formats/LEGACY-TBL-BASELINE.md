# 老 TBL 解码基线

> 任务：P1-03  
> 状态：参考读取器、非敏感固定向量与冻结加密/明文对已验证  
> 范围：只覆盖老 `QDataTable` 格式，不代表当前客户端新 TBL

## 结论

老 TBL 是经过 legacy double-AES-128 处理的 CRLF/逗号分隔表。每个 16-byte block 使用同一显式 16-byte key 连续执行两次 AES-128；解码结果的第一个 byte 是尾部零 padding 数量，随后是表文本，最后是 0～15 个零 byte。

`TMXY.Table` 独立实现这一离线兼容路径，不链接老运行时，也不包含默认密钥。调用方必须显式提供 16-byte key；模块不读取环境变量、配置文件或 Secret Store，不输出 key、字段内容或解密后的行。

## 证据

- L1：冻结的 `QDataTable`、`Rijndael_Imp`、`IEncryption` 和 `QParser` 源码，合同测试逐文件核对 size/SHA-256；
- L2：只读 `Suit_table.tbl` 与配对 `Suit_table.csv`，分别核对 SHA-256 后在锁定容器内完成逐 byte 相等验证；
- L3：以公开的非敏感测试 key 独立生成 double-AES 固定向量，覆盖正常、padding、NUL、换行、重复列和行宽错误。

密钥值不属于新工程证据输出。合同测试只在断网容器的临时 tmpfs 中，从已冻结的只读老源码证据提取两份一致的 16-byte initializer；测试结束时先覆零再 unlink，容器随后 `--rm`。报告只记录输入源码 SHA-256 和 key 形状，不记录 key 值或摘要。

## 解码顺序

1. 拒绝空输入、非 16-byte 倍数和超预算输入；
2. 使用调用方显式提供的 key，对每个 block 连续执行两次 AES-128 decrypt；
3. 检查首 byte 的 padding 数量必须为 0～15；
4. 检查所有尾部 padding byte 均为 0；
5. 移除首 byte 和尾部 padding，保留原始 payload bytes；
6. 拒绝 embedded NUL 和非 CRLF 换行；
7. 跳过空行，以首个非空行为列名，其余行为数据；
8. 拒绝空/重复列名、超列/超行预算和列数不一致的行。

老客户端对部分损坏输入依赖断言或静默截断；新参考读取器有意使用稳定错误 Schema v1 和绝对偏移拒绝这些输入。

## 冻结样本结果

| 属性 | 值 |
|---|---:|
| 加密 TBL bytes | 4,688 |
| 解码 payload / 配对 CSV bytes | 4,686 |
| padding bytes | 1 |
| 列数 | 10 |
| 数据行数 | 57 |
| 元数据 FNV-1a 64 | `c60c5d8848a6a32a` |
| payload SHA-256 | `4d43925eb834bea6d9710fa0112d599b8c96fbe29314612b461b5cdf44a169f2` |

legacy cipher 不提供认证，错误 key 或篡改数据在统计上可能形成看似可解析的明文。因此任何真实输入必须先绑定冻结 SHA-256 或由更高层可信清单认证；元数据 FNV 仅用于检测解析语义漂移，不是安全签名。

## 后续边界

当前客户端 `3.0.0.413` 的 TBL 不能据此假定使用同一 key 或处理顺序。P1-09～P1-11 必须单独确认当前格式、Secret 注入、CSV 关系和代表表语义；不得把老 key 写入新仓库、日志、报告或容器镜像。

## 复验

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-LegacyTableBaseline.ps1
```

证据写入 `Data/BuildBaseline/p1-03-legacy-table.json`。
