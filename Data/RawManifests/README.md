# Raw Manifests

这里保存由 `Tools/TMXY.Manifest/Scan-Manifest.ps1` 生成的基线清单。

每个输入包含：

- `<name>.files.jsonl`：按相对路径排序的逐文件 SHA-256 清单；
- `<name>.summary.json`：输入根目录、版本、文件数、总字节数和清单自身 SHA-256。

逐文件清单是确定性产物：输入路径、文件大小、修改时间和内容不变时，其 SHA-256 应保持不变。摘要中的生成时间允许变化。

Manifest 可能包含本机路径，默认不提交到公开仓库。

