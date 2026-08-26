# TMXY.BuildInventory

只读扫描 `ClientCode`、`ServerCode` 和 `ToolCode` 的老工程及本机构建环境，输出 P0-06 构建依赖盘点数据。

## 运行

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.BuildInventory\Export-BuildInventory.ps1'
```

可以覆盖默认路径：

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.BuildInventory\Export-BuildInventory.ps1' `
  -WorkspaceRoot 'E:\QQXYCodeDev' `
  -OutputDirectory 'E:\QQXYCodeDev\Rebuild\Data\BuildInventory'
```

## 输出

- `build-inventory.json`：工程、解决方案、配置、平台、链接库、已有二进制和缺失/外部依赖。
- `toolchain-environment.json`：本机 VS、MSVC、Windows SDK、UE、PowerShell、.NET 与 PATH 可见工具。

## 判定边界

- `BundledBinary`：工作区中存在同名 `.lib`/`.dll`/`.tlb`，不代表它能与当前 MSVC 或 x64 ABI 兼容。
- `ProducedByProject`：同名库由某个老工程声明生成；需要先按依赖顺序构建。
- `SystemSdk`：Windows/DirectX 等系统 SDK 链接库。
- `MissingOrExternal`：静态扫描没有找到同名产物或生产工程；可能是已废弃配置、未提交 SDK 或需要替换的商业组件，必须人工复核。

扫描器不会修改原始目录，也不会读取、输出数据库连接字符串或其他 Secret。

## 验证

```powershell
& 'E:\QQXYCodeDev\Rebuild\Tools\TMXY.BuildInventory\Test-BuildInventory.ps1'
```

验证器会检查基线数量、全部 `.vcproj` 的 SHA-256、解析错误、本机 Visual Studio 和 UE 5.8.2 记录。若原工程发生变化，验证会明确失败，不会静默接受漂移。
