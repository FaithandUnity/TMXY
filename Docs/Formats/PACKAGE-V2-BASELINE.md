# Package 2.0 读取基线

## 范围与边界

P1-05 提供只读、离线、C++20 的 Package 2.0 头读取器。它只解析容器目录和对象字节区间，不解释对象 body，不链接老客户端，不向只读证据目录写入任何内容。原始 Package 不复制到仓库，也不进入 Git LFS；基线只保存路径、大小、SHA-256 和聚合统计。

证据来自冻结清单 `Data/RawManifests/client-3.0.0.413.files.jsonl`，其 SHA-256 为 `b80cde6fbb736c9a6b85fd5e4528554f4e6e9bf950b1ac12a036b4c54d5d60c3`。当前客户端中所有带 Package 2.0 头的 22 个文件都纳入验证，不挑选单一“好样本”。

## 外层结构

所有整数均为 little-endian。

| 顺序 | 字段 | 类型 | 约束 |
|---|---|---|---|
| 1 | version_length | uint16 | 必须为 23 |
| 2 | version | 23 bytes | 必须逐字节等于 `QRENDER PACKAGE VER 2.0` |
| 3 | directory_size | int32 | 必须非负、未超过配置上限、目录落在文件内且至少 18 bytes |
| 4 | encoded_directory | `directory_size` bytes | 按下述确定性变换解码 |
| 5 | object bodies | 原始字节区间 | 按 offset 排序后必须从头结束位置连续覆盖到 EOF |

外层固定长度为 29 bytes，因此目录从文件偏移 29 开始，对象区从 `29 + directory_size` 开始。

## 目录变换和结构

目录变换按每个完整 4-byte 组执行：

```text
decoded[0] = ~encoded[2]
decoded[1] = ~encoded[3]
decoded[2] = ~encoded[0]
decoded[3] = ~encoded[1]
```

不足 4 bytes 的尾部逐字节按位取反。该变换是自身的逆变换。错误位置会从解码目录偏移映射回原始文件中的编码字节位置，便于对证据文件定位，而不是报告临时缓冲区位置。

解码后的目录结构如下：

| 解码偏移 / 顺序 | 字段 | 类型 | 约束 |
|---|---|---|---|
| 0 | directory_prefix | 14 bytes | 必须为 `030076657264000000010000003f` |
| 14 | object_count | int32 | 必须非负、未超过配置上限，且不超过剩余空间可容纳的最小记录数 |
| 18 / 重复 | name | uint16 长度 + bytes | 不透明对象键；同一 Package 内不得重复 |
| 后续 | class_name | uint16 长度 + bytes | 不透明类名字节 |
| 后续 | offset | int32 | 必须非负 |
| 后续 | size | int32 | 必须非负 |

声明记录全部读取后不得残留目录字节。对象区间不得重叠、留洞、越界或在文件末尾留下未声明尾部。

## 冻结实样结果

| 属性 | 冻结值 |
|---|---:|
| 实样文件数 | 22 |
| 实样集合 SHA-256 | `2371a43ac6a46403e68e0d31e884bb6b27b54ac5babc3db6b3c448695c3179e6` |
| 文件总大小 | 5,783,942 bytes |
| 目录总大小 | 1,220,531 bytes |
| 记录总数 | 27,637 |
| 聚合元数据 FNV-1a 64 | `2d2d359bc9f5da7f` |

实样集合 SHA-256 覆盖按路径排序的 `path|size|sha256` 行。聚合元数据指纹覆盖相对路径以及每个文件解析后的版本、记录顺序、名称、类名、偏移和大小；它用于检测解析语义漂移，不是安全签名，也不替代逐文件 SHA-256。

## 稳定错误模型

`PackageV2Error` schema 版本为 1，包含稳定错误码、原文件绝对偏移、可选记录序号、字段上下文和可选 bounded-reader 错误码。当前拒绝截断读取、版本不符、负数/过大/越界/过短目录、目录前缀不符、负数/过大/不可能的记录数、负 offset/size、重复对象名、目录尾随字节、非连续对象区间以及越过文件末尾的对象区间。

这些检查是新产品的输入安全边界。不得为了兼容损坏输入而默认放宽；如发现合法变体，必须先补充只读证据、版本化合同和回归样本。

## 复验

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-PackageV2Baseline.ps1
```

证据写入 `Data/BuildBaseline/p1-05-package-v2.json`。验证使用锁定的非 root Clang 21 镜像、禁网、只读根文件系统、只读源码挂载、只读 Packages 目录挂载、无 Linux capabilities、禁止提权和临时构建盘。
