# 输入基线摘要

> 基线日期：2026-08-26  
> Manifest Schema：1  
> 客户端版本：`TMXY 3.0.0 build413` / `3.0.0.413`

## 已冻结目录

| 名称 | 只读输入 | 文件数 | 总字节数 | Manifest SHA-256 |
|---|---|---:|---:|---|
| 当前客户端 | `E:\QQXYCodeDev\天命西游` | 45,532 | 13,095,879,333 | `b80cde6fbb736c9a6b85fd5e4528554f4e6e9bf950b1ac12a036b4c54d5d60c3` |
| 老客户端源码 | `E:\QQXYCodeDev\ClientCode` | 1,750 | 241,365,978 | `61d75487bb5eeed169a5850e2483f98be92c0fb8a94f3508b228415cd2310d3d` |
| 老服务端源码 | `E:\QQXYCodeDev\ServerCode` | 2,734 | 101,429,174 | `7e592040a1914de56db8436c53bb1f2881bad2dfa9d863a2339b20742dd79bd7` |
| 老工具源码 | `E:\QQXYCodeDev\ToolCode` | 7,320 | 585,475,355 | `1fbfd7ef065876c5c83efc577bd8a9992d42fbc9585ce2408193a0b378dd25f4` |
| 历史文档 | `E:\QQXYCodeDev\DevDoc` | 1,121 | 66,666,387 | `f0b74fb6e2ae5e1b2d0992b1224bde108c38644388515b06a548381e652f02f4` |

四套老源码、工具和文档合计 12,925 个文件、994,936,894 字节。

完整安装客户端约 12.20 GiB；此前约 8.19 GB 的统计只对应主要运行时美术资源子集，不包含客户端全部程序、表、Package、配置及其他文件。

## 源码归档文件

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `E:\QQXYCodeDev\QQXYCodeDev狮王源代码.rar` | 204,867,966 | `447e43253bb1ddefe78ff7a4c44123800c8c4c7b3eaecd5ed7bc99b2a35e7b6a` |

`QQXYClient`、`QQXYServer` 和 `QQXYTools` 当前仅各包含一个 0 字节说明文件，不作为额外运行时证据集。

## 验证结果

- 五份 `.files.jsonl` 的行数均与摘要文件数一致；
- 五份 `.files.jsonl` 的实际 SHA-256 均与摘要一致；
- 已重新读取全部 58,457 个原文件并逐一复算 SHA-256，全部匹配；
- 未发现被跳过的文件型 Reparse Point；
- Manifest 工具自测连续运行两次，输出清单 SHA-256 一致；
- 清单按规范化相对路径使用固定 OrdinalIgnoreCase 顺序，避免受系统区域设置影响；
- 原始输入没有被修改，生成结果全部位于 `E:\QQXYCodeDev\Rebuild`。

## 复验

结构复验：

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tools\TMXY.Manifest\Test-Manifest.ps1 `
  -SummaryPath E:\QQXYCodeDev\Rebuild\Data\RawManifests\client-3.0.0.413.summary.json
```

重新读取并校验全部原文件：

```powershell
pwsh -NoProfile -File E:\QQXYCodeDev\Rebuild\Tools\TMXY.Manifest\Test-Manifest.ps1 `
  -SummaryPath E:\QQXYCodeDev\Rebuild\Data\RawManifests\client-3.0.0.413.summary.json `
  -VerifySourceFiles
```
