# Golden test content root

P0-10A 创建时此目录没有 `.uasset` 或 `.umap`。P1-20 起仅加入固定的最小测试 Map：
`/Game/TMXY/Golden/Maps/TMXYGoldenTestMap`。它只承载 Headless Automation，不含旧客户端资源。

后续黄金资产只能由受测试的 Editor-only Importer 逐项生成，并写入 `/Game/TMXY/Golden`；批量导出、
原始 Package、Cooked 输出和 Derived Data Cache 不进入此目录。
