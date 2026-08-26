# TMXY 版本控制、评审与大型资产规范

> 状态：Mandatory  
> 版本：V1.0  
> 日期：2026-08-26  
> 适用范围：`E:\QQXYCodeDev\Rebuild` Git 仓库及其后续托管副本

## 1. 仓库边界

- 唯一仓库根目录是 `E:\QQXYCodeDev\Rebuild`。禁止在 `E:\QQXYCodeDev` 或其五个只读证据目录初始化仓库。
- `ClientCode`、`ServerCode`、`ToolCode`、`DevDoc`、`天命西游` 只作为证据源，禁止复制到 Git 或 Git LFS。
- 仓库只保存新源码、契约、Migration、部署清单、治理文档、可移植报告和经批准的小型黄金样本。
- GitHub 私有仓库 `FaithandUnity/TMXY` 和远端 `origin` 已获项目负责人授权并完成绑定；其他 remote、镜像仓库、权限或公开性变化仍需另行授权。

## 2. 分支模型与 `main` 保护

`main` 始终代表可构建、可测试、可回滚的集成基线。除首次仓库引导外，所有变更从最新 `main` 创建短生命周期分支，并通过 PR 合并。

分支命名使用小写 ASCII、数字和连字符：

| 类型 | 格式 | 用途 |
|---|---|---|
| 功能 | `feature/<任务ID>-<简述>` | 新功能或纵向切片 |
| 修复 | `fix/<任务ID>-<简述>` | 缺陷修复 |
| 文档 | `docs/<任务ID>-<简述>` | 仅文档变更 |
| 构建 | `build/<任务ID>-<简述>` | 工具链、CI、部署和依赖 |
| 维护 | `chore/<任务ID>-<简述>` | 无产品行为变化的维护 |
| 紧急修复 | `hotfix/<事件ID>-<简述>` | 从当前发布标签或 `main` 创建的紧急修复 |

管理员必须为 `main` 配置以下保护，不得以口头约定替代。2026-08-27 的只读 API 证据确认当前私有仓库尚未保护，且 GitHub 要求升级到 Pro 或改为 public 才开放保护/ruleset；在项目负责人决定前不得静默改公开性或订阅：

1. 禁止直接 push、force push 和删除分支，只允许 PR 合并。
2. 合并前要求分支与 `main` 同步，全部必需 CI 检查成功。
3. 至少一名非作者批准；协议、安全、经济写入、数据库 Migration 和发布配置至少两名评审者批准。
4. 作者不得自批；新提交使旧批准失效，所有评审意见必须解决。
5. 管理员同样受保护规则约束；紧急绕过必须关联事件记录，并在下一个工作日补 PR、测试与复盘。
6. 默认使用 squash merge 保持一个 PR 对应一个可回滚提交；发布或审计确需保留提交时可使用非快进合并，并在 PR 说明原因。

最低必需检查固定为 `policy/repository`、`security/secrets`、`backend/clang21`、`backend/static-analysis`、`backend/postgres-migration`、`client/ue58-build-automation`、`supply-chain/policy` 和 `release/provenance`。GitHub Actions 源码和 CODEOWNERS 已建立，但只有保护规则、真实 Runner、供应链策略和签名证据全部生效后才能宣称发布权威。

## 3. Commit 规则

- Commit 必须使用开发者真实的本地 `user.name` 和 `user.email`；未配置时停止提交，不伪造、不共用身份。
- 标题格式为 `<type>(<scope>): <摘要>`，例如 `build(repo): establish p0-11 version control policy`。
- `type` 使用 `feat`、`fix`、`docs`、`build`、`test`、`refactor`、`perf`、`chore`、`revert`。
- 一个 Commit 只表达一个可审查目的，不混入无关格式化、生成噪声或个人环境文件。
- 行为变化在正文说明原因、兼容性、测试和回滚；关联永久任务 ID、Issue 或 ADR。
- 禁止提交失败构建、注释掉的大段旧代码、无负责人/到期日的临时豁免，以及手工修改的生成文件。

## 4. PR 与强制评审

PR 必须保持小而完整，并填写：

- 目标、范围和关联任务；
- 架构层/数据所有权影响；
- 协议、Schema、Migration、配置或大型资产变化；
- 安全与 Secret 影响；
- 实际运行的命令和结果；
- 发布、回滚、数据恢复与已知风险。

评审者必须核对 `ENGINEERING-STANDARD.md` 的评审清单。作者处理完意见后由评审者确认，不以“已回复”代替“已解决”。Draft PR、失败检查、未解决意见、缺少所需批准或来源不明的资产均不得合并。

## 5. 大型资产边界

### 5.1 普通 Git

普通 Git 保存文本源码、Schema、Migration、文档和小型可移植测试向量。单个新增二进制黄金样本原则上不超过 10 MiB，并同时具备授权、来源路径、SHA-256、客户端版本、用途和删除/替代策略。

### 5.2 Git LFS

默认 LFS allowlist 仅包含 `.uasset`、`.umap`、`.ubulk`、`.uexp`、`.uptnl`。它们必须是项目合法使用、进入产品或受控黄金测试所必需的 UE 源资产，并位于明确的 UE `Content` 边界。

- 单文件超过 100 MiB，或单个 PR 的 LFS 增量超过 1 GiB，必须先经过资产负责人和仓库管理员评审。
- LFS 对象必须有可追溯来源和内容版本；不得把 LFS 当作通用网盘。
- `.gitattributes` 中不得为原始 QRender/客户端格式、原始 Package、数据库转储、归档包、视频或批量导出目录添加通配 LFS 规则。
- LFS 指针与对象必须在 CI 做完整性检查；缺失对象阻断合并和发布。

### 5.3 只读证据目录或对象存储

下列内容禁止进入普通 Git 和 Git LFS：

- 原客户端安装包、原始 Package、原始资源全集和老源码副本；
- `Data/Extracted`、`Data/Exports`、`Data/Generated` 等批量解包、转换和导出产物；
- UE DDC、`Binaries`、`Intermediate`、`Saved`、Cooked、Staged、`.pak`、`.ucas`、`.utoc`；
- 数据库转储、容器卷、构建缓存、本地备份、镜像归档和大型运行日志。

这些内容保留在只读证据目录或受控对象存储。Git 只记录不可逆哈希、大小、来源版本、对象键、授权范围、生成工具版本和可重建步骤；对象键不得包含访问凭据。

## 6. Secret 禁令

- 密码、Token、私钥、证书私钥、完整连接串、Cookie、真实账号和解密材料不得进入 Commit、PR 描述、Issue、Git LFS、日志或测试快照。
- 配置文件只提交键名和无效占位符；真实值通过 Secret Store、部署平台或本机受控环境注入。
- `.gitignore` 不是安全控制。提交前和 CI 必须扫描工作树、暂存区和可达历史。
- 发现泄漏时立即停止合并和推送，先撤销/轮换 Secret，再按安全负责人批准的流程清理历史并记录事件；只在最新 Commit 删除文件不算处置完成。

## 7. 生成代码和生成资产

- `Contracts/generated` 仅保存由已提交 Schema 和锁定生成器确定性生成、且构建或分发确实需要的代码。必须与源 Schema 同 PR，禁止手工编辑。
- 可随时从源码生成的本机构建目录、CMake 缓存、解决方案、报告临时文件和依赖缓存不提交。
- UE 生成资产只有在授权明确、路径稳定、来源 Manifest/工具版本可追踪且产品或 Golden Test 必需时才进入 LFS。
- DDC、Cooked/Stage 包和批量转换资产始终可重建，使用对象存储或流水线制品，不进入 LFS。
- 重新生成造成大范围差异时，PR 必须说明生成器版本、命令、输入摘要和预期差异；评审不得只检查生成结果而忽略源定义。

## 8. 回滚与版本标签

- `main` 已合并历史不改写。普通回滚使用独立 `revert` PR 和 `git revert`，保留原变更与撤销原因。
- 数据库不可逆变更优先使用向前修复 Migration；回滚必须先验证数据兼容、备份和恢复路径，禁止用 Git 回滚代替数据库恢复。
- 大型资产回滚同时还原 LFS 指针、内容 Manifest、引用关系和产品内容版本。
- 发布标签只能从通过全部发布门禁的 `main` Commit 创建，使用 annotated tag，禁止移动、覆盖或复用。
- 程序标签使用 `client-vMAJOR.MINOR.PATCH`、`backend-vMAJOR.MINOR.PATCH`；候选版追加 `-rc.N`；内容使用 `content-vYYYY.MM.DD.N`。
- 发布记录必须关联 Git Commit、OCI digest、协议版本、Schema/Migration 版本、内容版本和回滚目标。标签错误时创建递增的新标签，不删除或重指旧标签。

## 9. 本地验证

在仓库根目录运行：

```powershell
git status --short --branch
git lfs track
& '.\Tests\Contract\Test-RepositoryLayout.ps1'
```

任何规则例外必须形成带负责人、风险、范围和到期日的 waiver，并由与对应代码相同数量的评审者批准。
