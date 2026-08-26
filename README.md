# TMXY Rebuild

本目录用于《天命西游／QQ西游》重构工程的新代码、工具、数据描述和测试产物。

## 原始输入规则

以下目录是重构证据源，按只读输入处理：

- `E:\QQXYCodeDev\ClientCode`
- `E:\QQXYCodeDev\ServerCode`
- `E:\QQXYCodeDev\ToolCode`
- `E:\QQXYCodeDev\DevDoc`
- `E:\QQXYCodeDev\天命西游`

不得在这些目录内执行格式转换、批量改名或修复。所有派生结果写入 `Rebuild`。

## 当前目录

```text
Rebuild/
├─ Apps/UEClient/                UE 5.8.2 C++ 客户端工程
├─ Backend/                      Linux/C++20 后端模块和应用
│  └─ adapters/persistence_postgres/ PostgreSQL Migration 与后续 libpq 唯一边界
├─ Contracts/                    Protobuf、数据 Schema、资产交换注册表与规范示例唯一来源
├─ Deploy/                       Compose、容器和生产部署清单
├─ Tests/                        跨模块契约、集成、Golden 与性能测试
├─ Tools/TMXY.Manifest/          输入清单工具
├─ Tools/TMXY.BuildInventory/    老工程与构建环境盘点工具
├─ Tools/TMXY.Toolchain/         最终工具链环境检测与锁定验证
├─ Tools/TMXY.GoldenSamples/     黄金样本引用基线生成与源文件校验
├─ Tools/TMXY.Security/          Secret 工作树/历史扫描与泄漏门禁
├─ Tools/TMXY.SupplyChain/       本地镜像 SBOM 与供应链证据校验
├─ Tools/TMXY.FormatCore/        P1 有界二进制读取与稳定错误契约
├─ Tools/TMXY.Package/           Package 头解析、边界验证与格式指纹
├─ Tools/TMXY.Table/             老 TBL 显式密钥解码、分隔表验证及当前 TBL 读取链诊断
├─ Tools/TMXY.Transform/         遗留坐标、单位、矩阵、UV 与绕序的 UE 单一转换边界
├─ Tools/TMXY.Texture/           Package 元数据与 qtx mip 解析、Alpha 分析和纹理中间输出
├─ Tools/TMXY.StaticMesh/        Package 材质绑定、sm 有界解析及静态网格审查中间输出
├─ Tools/TMXY.SkeletalMesh/      Package 骨架绑定、skem 权重/部件解析及骨骼网格审查输出
├─ Tools/TMXY.Animation/         Package 动画元数据绑定、anim 轨道/Key 与 Root Motion 审查输出
├─ Tools/TMXY.Terrain/           ter 地形 Tile 的高程、层 Alpha、水体和完整边缘导出
├─ Data/RawManifests/            Manifest 与摘要
├─ Data/GoldenSamples/           只存元数据的黄金样本引用集
├─ Data/BuildInventory/          工程、链接依赖和环境 JSON
├─ Data/BuildBaseline/           新工程可重复构建验证结果
├─ Data/Toolchain/               工具链锁定清单与主机环境快照
├─ Data/Security/                脱敏后的安全门禁报告
├─ Data/Performance/             平台、容量和性能预算基线
├─ Docs/Governance/              权利与治理基线
├─ Docs/Build/                   构建依赖与可编译性报告
├─ Docs/Architecture/            已冻结的最终技术架构
├─ Docs/Standards/               强制工程与代码规范
├─ Docs/Formats/                 格式证据、样本边界与重构记录
├─ Docs/Security/                Secret 注入、脱敏、轮换与事件规则
├─ Docs/Performance/             客户端/后端容量、延迟和恢复目标
├─ Docs/Database/                PostgreSQL Migration、所有权和验证规则
└─ Docs/ADR/                     已接受和待评审的架构决策
```

辅助资源不建立空模块：ZIF、声音、UI、Shader 和字体的已验证分类、优先级及后续处理路线见
`Docs/Formats/AUXILIARY-ASSET-INVESTIGATION.md`，机器证据由
`Tests/Contract/Test-AuxiliaryAssetInvestigation.ps1` 重扫只读客户端后生成。

P1 资产交换统一使用 `manifest.json` + 独立哈希载荷；Schema、格式注册表、示例、版本与
未知字段保留规则见 `Docs/Formats/ASSET-INTERCHANGE-V1.md`。OBJ/PNG/TGA/CSV 只作审查，
不得被导入器当作权威输入。

最终目录和依赖边界见 `Docs/Architecture/TARGET-ARCHITECTURE.md`。后续目录按首个真实文件逐步建立，不提前生成无内容的工程。

## 版本控制

Git 仓库根目录固定为本目录，父目录和五个只读输入目录不得初始化或纳入仓库。分支保护、Commit/PR、强制评审、Secret、生成物和 Git LFS/对象存储边界见 `Docs/Governance/VERSION-CONTROL-POLICY.md`。
