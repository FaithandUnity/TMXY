# LegacyToUETransform 规范

状态：Frozen（P1-12）  
版本：1  
实现：`Tools/TMXY.Transform`

## 1. 适用边界

本规范只处理已经由旧工具写入 `.sm/.skem/.anim/Package` 等运行时格式的空间值。3ds Max、FBX 或 glTF 原生值不是遗留运行时值，必须先完成各自来源格式的标准化。第一层解析必须保留原值；只有生成 UE-facing 数据时才能调用本转换。

## 2. 冻结换算

| 项目 | 遗留约定 | UE 5.8.2 目标 | 换算 |
|---|---|---|---|
| 坐标系 | 左手，X 前、Y 右、Z 上 | 左手，X 前、Y 右、Z 上 | 轴恒等 |
| 位置单位 | 米 | 厘米 | `(x,y,z) * 100` |
| 方向 | 无单位 | 无单位 | 分量恒等 |
| 法线 | 遗留轴，长度不可信 | UE 轴，单位长度 | 分量恒等后归一化；零向量失败 |
| 角度 | `int32`，65,536/圈 | 度 | 先按低 16 bit 规范到 `[-180,180)`，再 `(-Pitch, Yaw, -Roll)` |
| 矩阵 | `m[row][column]`，行向量，平移在 `m[3][0..2]` | 同为行向量仿射矩阵 | 复制 3×3；平移乘 100；禁止投影项 |
| UV | 左上原点语义，允许越过 0～1 | UE UV | `(u,v)` 恒等，不 clamp，不二次翻 V |
| 三角形 | 导出时已左手化 | UE 左手空间 | 索引顺序恒等 |

`Matrix4` 的合法仿射尾列为 `(0,0,0,1)`。非均匀缩放和负缩放的 3×3 基底原样保留。如果矩阵被单独保留为 UE Transform，索引不改变；如果矩阵被烘焙进顶点，3×3 行列式小于零时反转一次绕序，等于零时阻断。非均匀缩放烘焙后的法线/切线必须由下游使用逆转置或重建，不能按位置缩放。

## 3. 证据链

| 证据 | 观察 | SHA-256 |
|---|---|---|
| `ClientCode/Base/Hdr/QMath.h` | `reduceAngle` 使用 16-bit mask | `62b5f6f18aa1885b70587ca79cd2bad08e7cce62d572808b66288611708d13ac` |
| `ClientCode/QRender/Hdr/QRotator.h` | 默认方向为 X；Pitch/Yaw/Roll 分别绕 Y/Z/X；65,536/圈 | `661c662041667513d2deaa4c6d4bd6a1244a8fa7b09e533b4ed8a4df1ed51a3f` |
| `ClientCode/QRender/Hdr/QMatrix.h` | 行向量乘法、平移行和旧欧拉矩阵公式 | `99defaa9fa607285bb2c553d257d948fbc1028d58e53cdaf6d38dfb25a4ecc58` |
| `ClientCode/QRender/Src/QPawnPhy.cpp` | Z 轴重力且基准为 9.8 | `d82ab57cd8dafc7f1f5a7d811e0c94bc49c3246e2438deded597d3552641028b` |
| `ToolCode/XwMaxExp/XwMaxExp.h` | 导出器显式选择左手目标 | `674549952ee6b3eacb0068efb4aa1d50c41ddbb40a819e2cc809715f45071c1d` |
| `ToolCode/XwMaxExp/XwMaxMesh.cpp` | Max 边界镜像 X、按变换奇偶调整绕序、写出前执行 `V=1-V` | `8133ea9e6326da55e1d542bfcfb44731a4a48cabf5984bedcbba7dfb97bdcaea` |
| `DevDoc/游戏资料/CLSVShare/unit_disp_ids.csv` | 角色高度/半径和 4～5 的移动速度是米尺度 | `05a6a64e66654784eada747f5ff35310c2b48fea881f6a8ff12c356053b54fc0` |
| UE 5.8.2 `RotationTranslationMatrix.h` | UE 行向量矩阵公式；与旧公式比较得到 Pitch/Roll 反号、Yaw 同号 | `8dd14f716b4c8a26b5a1aa270a7da73aa76e09d2d83b6ddba55a289e2e1124c4` |

旧目录和 UE 安装目录只读。新实现未 include 或链接任何旧源码、D3D、Max SDK 或 UE 头；证据只以路径、行为断言和哈希进入规范与机器报告。

## 4. 错误契约

错误 Schema 版本为 1：

- `non_finite_input`：任一输入分量为 NaN 或 Infinity；
- `zero_length_normal`：法线长度不足以稳定归一化；
- `non_affine_matrix`：矩阵尾列不是 `(0,0,0,1)`；
- `degenerate_basis`：请求烘焙绕序判定时 3×3 行列式为零或接近零。

错误不得以默认零值继续导入。

## 5. 黄金与边界测试

`transform.legacy_to_ue` 固定验证：米到厘米、三轴方向、法线归一化、UV 越界保持、四分之一圈与环绕角、负缩放矩阵、平移行、索引顺序、负行列式烘焙、NaN/Infinity、零法线、投影矩阵和退化基底。P1-12 契约在锁定的非 root Clang 21 容器中执行 clang-format、CMake/Ninja、clang-tidy 与 CTest，源目录只读且网络禁用。
