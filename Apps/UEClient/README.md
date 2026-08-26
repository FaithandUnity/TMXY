# TMXY UE Client

这是 UE 5.8.2/Windows x64 新客户端。它不包含老 D3D9 客户端代码、旧协议兼容层或从已安装客户端
直接复制的 Cooked 资源。

当前真实模块：

- `TMXYCore`：构建身份和后续无 UI/玩法含义的基础类型；
- `TMXYClient`：Primary Game Module 和 Composition Root，不承载玩法规则；
- `TMXYGoldenTests`：仅 Editor 加载，固定黄金样本路径并提供 Headless Automation 宿主。

当前真实 Editor 插件：

- `TMXYImporter`：验证 `tmxy.asset.interchange` Manifest，提供批量 validate-only、报告输出、格式处理器注册
  和重导入派发边界；P1-21 不创建资产，首个真实 qtx 处理器由 P1-22 加入。

后续 `TMXYData`、`TMXYNet`、`TMXYAssets`、`TMXYGameplay`、`TMXYUI` 和 `TMXYEditor` 等模块只在出现
首个真实功能时创建，并遵守 `实施计划.md` 的依赖边界。

P1-20 唯一允许的 Content 资产是
`/Game/TMXY/Golden/Maps/TMXYGoldenTestMap`。它是空的非 World Partition 测试 Map，不能放入旧客户端
资源。`Scripts/CreateGoldenHostMap.py` 只用于使用已锁定的 UE 版本重建该 Map，不是运行时依赖。

## 构建

```powershell
& 'C:\Program Files\Epic Games\UE_5.8\Engine\Build\BatchFiles\Build.bat' `
  TMXYEditor Win64 Development `
  -Project='E:\QQXYCodeDev\Rebuild\Apps\UEClient\TMXY.uproject' `
  -WaitMutex -NoHotReloadFromIDE
```

生成的 `Binaries`、`Intermediate`、`Saved`、`.vs` 和解决方案文件不是源码，不提交版本库。
空工程启动时 UE 还会自动展开 `Config/DefaultInput.ini`；在 TMXYUI 建立真实输入映射前该文件保持忽略。
