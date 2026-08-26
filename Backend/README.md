# TMXY Backend

这里是新 Linux/C++20 后端，不编译或链接任何老 Win32、SQL Server、ACE、ADO 或 x86 产物。

当前首个切片包含：

- `modules/foundation`：无业务含义、无第三方依赖的基础构建身份 API；
- `apps/gateway`：只负责进程组合和生命周期入口的最小可执行文件；
- CTest 单元测试；
- Linux Clang、Windows MSVC 和临时 GCC 诊断 Preset。

正式 Linux 构建使用 P0-08 锁定的 Clang 21/CMake 4.4.2/Ninja 镜像。当前 Docker registry
阻塞期间，`linux-gcc-diagnostic` 只用于验证通用 C++20/CMake 结构，不是发布权威。

## 权威构建命令

```bash
cmake --preset linux-clang-debug
cmake --build --preset linux-clang-debug
ctest --preset linux-clang-debug
```

Release/CI 使用 `linux-clang-release` 与 `ci-linux-clang`。依赖引入后必须同时提交 Conan profile、
recipe 和 lockfile；禁止在 CMake 中使用浮动 `FetchContent`。
