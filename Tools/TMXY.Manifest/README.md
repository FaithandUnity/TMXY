# TMXY.Manifest

对只读输入目录生成确定性的 SHA-256 文件基线。

示例：

```powershell
pwsh -NoProfile -File .\Scan-Manifest.ps1 `
  -Root 'E:\QQXYCodeDev\天命西游' `
  -OutputDirectory 'E:\QQXYCodeDev\Rebuild\Data\RawManifests' `
  -Name 'client-3.0.0.413' `
  -ProductVersion 'TMXY 3.0.0 build413'
```

脚本只读取 `Root`，只在 `OutputDirectory` 中写入生成文件。

验证已生成清单：

```powershell
pwsh -NoProfile -File .\Test-Manifest.ps1 `
  -SummaryPath 'E:\QQXYCodeDev\Rebuild\Data\RawManifests\client-3.0.0.413.summary.json'
```

需要重新读取并核对每个原文件内容时增加 `-VerifySourceFiles`。这会再次计算全部 SHA-256，耗时取决于输入体积。

