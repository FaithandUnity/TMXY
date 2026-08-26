# Package 规范化记录树 v1

## 目的

P1-08 定义 Package 1.0/2.0/3.0 共用的确定性 JSON 输出，用作后续对象格式研究和迁移流水线的稳定边界。Schema 唯一来源为 `Contracts/data-schema/package-tree-v1.schema.json`，标识 `tmxy.package.tree`、版本 1。

规范化不等于猜测。当前容器层已经证明的版本、目录、名称/类名字节及 body offset/size 正常输出；尚未证明的引用、Transform 和材质明确输出 `state: unparsed`。对象 body 作为 `unknown_fields` 中的 `source-span` 保存来源区间，不复制资产字节，也不伪造字段值。

## 字段边界

| JSON 区域 | 状态 | 说明 |
|---|---|---|
| `source.label` | 已知 | 调用者提供的可移植相对标签；导出器不输出本机输入绝对路径 |
| `source.file_size` | 已知 | 已验证 Package 文件大小 |
| `package.format_version` | 已知 | 原始 1.0/2.0/3.0 完整版本字符串 |
| `package.header_size` | 已知 | 对象区起点 |
| `package.directory` | 已知 | V1 为 offset 0/完整头大小；V2/V3 为编码目录原文件 offset/size |
| `objects[].index` | 已知 | 原目录顺序，0-based |
| `name` / `class_name` | 已知原字节 | `opaque-bytes` + 小写 hex，不猜测字符编码 |
| `body` | 已知 | 原文件 offset/size |
| `references` | 未解析 | 空数组不表示“没有引用”，必须同时读取 `state: unparsed` |
| `transform` | 未解析 | `matrix: null`，不得解释为单位矩阵 |
| `materials` | 未解析 | 空 slots 不表示“没有材质” |
| `unknown_fields` | 保留 | `object-body` 的 source-span，后续 codec 可按范围继续解析 |

## 确定性与升级

JSON 使用固定字段顺序、十进制无符号整数、小写 hex、紧凑单行和 LF 结尾。相同解析树和 source label 必须产生相同字节。Schema v1 已发布字段不得改变含义；增加已解析引用、Transform、材质或对象字段时，应保持 `unparsed` 与真实已解析状态可区分，并按兼容性决定扩展 v1 或发布 v2。

## 导出器

锁定 Linux 构建中的命令行入口：

```text
tmxy_package_tree_export <package-file> <source-label>
```

第一个参数仅用于本地读取，不写入 JSON；第二个参数进入 `source.label`。解析失败只输出稳定错误类别，不回显文件内容或绝对路径。

三种冻结实样输出：

| 版本 | source label | JSON bytes | SHA-256 |
|---|---|---:|---|
| 1.0 | `Packages/Texture/tempfile.tmp` | 1,350,653 | `4ab058aafd9ffd44065e442994591b33415dc5c1ff37307a8ceb6a02bd89c13c` |
| 2.0 | `Packages/Level/bydfb` | 5,223 | `9a738c3ab36adb33da85866d252c71e6f48eef92f4000ce5bcc2cdf8a8d370a8` |
| 3.0 | `Packages/Texture/texeditor` | 676 | `f75e249ce19f82be23c6b6d3b039a64cf58771cbb033460e3d43fc7869b4bec3` |

大 JSON 只是验证过程的临时输出，不提交仓库；仓库只保存 Schema、代码、摘要和报告。

## 复验

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tests\Contract\Test-PackageNormalizedTree.ps1
```

证据写入 `Data/BuildBaseline/p1-08-package-normalized-tree.json`。验证使用锁定的非 root Clang 21 镜像、禁网、只读源码与 Packages 挂载、只读根文件系统、无 capabilities、禁止提权和临时构建盘。
