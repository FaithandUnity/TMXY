# Package 1.0 / 老 TBL 参考格式 V0.1

> 文档版本：0.1  
> 对应任务：P1-04  
> 冻结日期：2026-08-26  
> 适用范围：Package 1.0 与老 `QDataTable` TBL；不适用于 Package 2.0/3.0 或当前客户端新 TBL

## 证据等级

| 等级 | 含义 | 本文使用 |
|---|---|---|
| L1 | 可定位的老源码直接证明 | 字段写入/读取顺序、整数宽度、AES 调用顺序、padding、CRLF/分隔行为 |
| L2 | 冻结二进制或明文实样重复观察 | Package 1.0 目录边界；老 TBL 加密/明文逐 byte 配对 |
| L3 | 独立构造的固定向量或新实现测试 | 损坏输入、上限、重复键、padding、行宽和稳定错误码 |
| L4 | 尚未证实的语义候选 | 本文未知项；不得升级为实现事实 |

逐文件 size/SHA-256 和锁定工具链执行结果分别位于 `p1-02-package-v1.json` 与 `p1-03-legacy-table.json`。原始证据保持只读且未复制到 `Rebuild`。

## Package 1.0

### 文件头与目录

起始偏移以文件首 byte 为 0。所有整数为 little-endian；`legacy_string` 为 `uint16 byte_length` 后接等长不透明 bytes。

| 字段 | 相对偏移 | 类型/宽度 | 重复 | 证据 | 已验证约束 |
|---|---:|---|---:|---|---|
| `version.length` | 0 | uint16 | 1 | L1+L2 | 值为 24 |
| `version.bytes` | 2 | 24 bytes | 1 | L1+L2 | 精确等于 `QRENDER PACKAGE VER 1.0` |
| `object_count` | 26 | int32 | 1 | L1+L2 | 非负；冻结实样为 3,004 |
| `object.name` | 动态 | legacy_string | object_count | L1+L2 | 作为不透明对象键；新读取器拒绝精确 byte 重复 |
| `object.class_name` | 动态 | legacy_string | object_count | L1+L2 | 作为不透明类名字节保留 |
| `object.offset` | 动态 | int32 | object_count | L1+L2 | 非负；绝对文件偏移 |
| `object.size` | 动态 | int32 | object_count | L1+L2 | 非负；对象 body byte 数 |
| `object bodies` | `header_size` | opaque bytes | object_count | L1+L2 | 按 offset 排序后连续覆盖至 EOF |

冻结实样头结束及首对象偏移均为 145,581，文件大小 319,813；3,004 个对象区间连续且无越界，元数据 FNV-1a 64 为 `1691fafacd3ab5bd`。

### Package 1.0 未知项

| ID | 状态 | 未知内容 | 隔离策略 | 后续任务 |
|---|---|---|---|---|
| PKG1-U01 | L4 | name/class bytes 的原始字符集未由格式声明 | 保持 bytes，不在 Package 层转 Unicode | 类专属格式任务 |
| PKG1-U02 | L4 | 各 `class_name` 对应 body 的字段 Schema | body 保持 opaque，不做猜测式反序列化 | P1-13～P1-18 |
| PKG1-U03 | L4 | 未观察 writer 是否允许空 name/class | 新读取器只执行当前已冻结的结构与区间边界；语义层另行验证 | P1-27 |
| PKG1-U04 | L4 | 损坏/手工编辑文件是否存在合法 gap/overlap 变体 | 正常输入强制连续；异常样本独立隔离 | P1-27 |

## 老 TBL

### 密文容器

| 字段/阶段 | 偏移 | 类型/宽度 | 证据 | 已验证约束 |
|---|---:|---|---|---|
| ciphertext blocks | 0 | N × 16 bytes | L1+L2 | 文件非空且必须为 16-byte 倍数 |
| key | 外部输入 | 16 bytes | L1+L3 | 新模块无默认值；必须显式注入，禁止日志/报告输出 |
| transform | 每个 block | AES-128 decrypt × 2 | L1+L2+L3 | 同一 key schedule 对每块连续执行两次 |
| `padding_count` | 解密偏移 0 | uint8 | L1+L2 | 0～15；冻结实样为 1 |
| payload | 解密偏移 1 | opaque text bytes | L1+L2 | 长度 = plaintext size - 1 - padding_count |
| tail padding | payload 后 | zero bytes | L1+L3 | 数量等于 padding_count；新读取器逐 byte 验零 |

该 legacy cipher 不认证密文。真实样本必须先由冻结 SHA-256 或更高层可信清单绑定，不能把“成功解码”当成真实性证明。

### 分隔表 payload

| 规则 | 类型 | 证据 | 已验证行为 |
|---|---|---|---|
| 行结束 | exact CRLF | L1+L2 | 空行跳过；新读取器拒绝 lone CR/LF |
| 默认分隔符 | `,` single byte | L1+L2 | 无引号或 escape 语法 |
| header | 首个非空行 | L1+L2 | 字段名按分隔符切分；新读取器拒绝空名与重复名 |
| record | 后续非空行 | L1+L2+L3 | 每行字段数必须与 header 一致；保留空字段 |
| field | opaque bytes | L1 | 数值、bool、对象引用转换属于调用方语义层 |

冻结配对样本为 4,688-byte TBL、4,686-byte payload/CSV、10 列、57 行；payload 与配对 CSV SHA-256 均为 `4d43925eb834bea6d9710fa0112d599b8c96fbe29314612b461b5cdf44a169f2`，元数据 FNV-1a 64 为 `c60c5d8848a6a32a`。

### 老 TBL 未知项

| ID | 状态 | 未知内容 | 隔离策略 | 后续任务 |
|---|---|---|---|---|
| LTBL-U01 | L4 | payload 字段的字符集未由格式声明 | 保持 bytes；展示/转码由表 Schema 显式决定 | P1-11 |
| LTBL-U02 | L4 | 除逗号外 separator 的实际生产使用范围 | API 保留显式 separator；黄金基线仅冻结逗号 | P1-27 |
| LTBL-U03 | L4 | 空 header、重复列、超长行在历史工具中的预期容错 | 新读取器安全拒绝，不复刻断言或静默截断 | P1-27 |
| LTBL-U04 | L4 | 当前客户端新 TBL 的 key 派生、处理顺序及 Schema | 与老模块严格隔离；不得回退使用老 key | P1-09～P1-11 |

## 实现边界

- `TMXY.FormatCore` 提供通用有界字节读取；
- `TMXY.Package` 只解析 Package 1.0 目录与区间，不解释 body；
- `TMXY.Table` 只实现老 TBL 离线兼容路径，key 由调用方显式 span 注入；
- 三个模块均为纯 C++20，不依赖 Win32、D3D9、Qt、老运行时或当前客户端二进制；
- 当前文档不授权批量导出、UE 资产导入、Package 2.0/3.0 推断或新 TBL Secret 获取。

## 机器复验

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-ReferenceFormatDocs.ps1
```

更详细的实现、安全差异和复验命令见 `PACKAGE-V1-FORMAT.md` 与 `LEGACY-TBL-BASELINE.md`。
