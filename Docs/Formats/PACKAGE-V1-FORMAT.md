# Package V1 格式基线

> 任务：P1-02  
> 状态：已实现并由锁定工具链及冻结实样验证  
> 运行时边界：`TMXY.Package` 只依赖 `TMXY.FormatCore`，不链接老客户端代码

## 证据边界

Package V1 的结构结论来自两类只读证据：

- L1 源码证据：老客户端 `QPackage`、`QArchive`、`QDict` 和 `QMetaclass` 的头文件与实现；
- L2 实样证据：冻结客户端中唯一观察到的 Package 1.0 文件 `Packages/Texture/tempfile.tmp`。

合同测试在每次运行时重新核对六份源码证据的大小与 SHA-256，并核对实样大小与 SHA-256。老源码和实样不会复制进 `Rebuild`，也不会成为新产品运行时依赖。

## 字节布局

所有整数均为 little-endian。字符串不是 Unicode 语义字段，而是保持原始字节的 `uint16 length + length bytes`。

| 顺序 | 字段 | 编码 | 约束 |
|---:|---|---|---|
| 1 | version | legacy string | 必须逐字节等于 `QRENDER PACKAGE VER 1.0` |
| 2 | object_count | int32 | 必须非负、未超过配置上限，且剩余字节足以容纳最小记录 |
| 3 | object records | 重复 `object_count` 次 | `name`, `class_name`, `offset`, `size` |
| 3.1 | name | legacy string | 作为不透明对象键；同一 Package 内不得重复 |
| 3.2 | class_name | legacy string | 作为不透明类名字节保留 |
| 3.3 | offset | int32 | 必须非负 |
| 3.4 | size | int32 | 必须非负 |
| 4 | object bodies | 原始字节区间 | 按 offset 排序后必须从头结束位置连续覆盖到文件末尾 |

解析器只读取和验证头，不解释对象 body。后续对象反序列化必须由拥有明确格式合同的模块完成。

## 冻结实样结果

| 属性 | 冻结值 |
|---|---:|
| 实样 SHA-256 | `11804bcbd1c28a4243670f519cee12d6b8fe7f46ebfaf8033e43b0509f9bc0e6` |
| 文件大小 | 319,813 bytes |
| 记录数 | 3,004 |
| 头大小 / 首对象偏移 | 145,581 bytes |
| 不同类名数 | 1 |
| 连续对象区间数 | 3,004 |
| 元数据 FNV-1a 64 | `1691fafacd3ab5bd` |

元数据指纹覆盖版本、记录顺序、名称字节、类名字节、偏移和大小，用于检测解析语义漂移；它不是安全签名，也不替代输入 SHA-256。

## 稳定错误模型

`PackageV1Error` schema 版本为 1，提供稳定错误码、绝对偏移、可选记录序号、字段上下文和底层 bounded-reader 错误码。当前拒绝：截断读取、版本不符、负数或不可能的记录数、超过配置上限、负 offset/size、重复名称、非连续区间和越过文件末尾的区间。

与老加载器相比，新读取器有意增加长度、计数、分配前、重复键和区间完整性检查。这是输入安全边界强化，不改变已验证正常实样的格式语义。不得为了兼容损坏输入而放宽这些检查。

## 复验

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-PackageV1Baseline.ps1
```

证据写入 `Data/BuildBaseline/p1-02-package-v1.json`；运行过程使用锁定的非 root Clang 21 镜像、禁网、只读根文件系统、只读源码挂载、只读单实样挂载及临时构建盘。
