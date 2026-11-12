# 兼容版源码及安装包构建

上游： https://github.com/leookun/cursor-byok

基线：v1.0.1，提交 2068ab20513288e6a0289d33febe872a30608610。
源码包含该版本完整受版本控制的文件及三个文件的修复：

- server/src/api/cursor/bidi.rs
- server/src/cursor/services/analytics.rs
- server/tests/connect_wire.rs

最终补丁另存于 compatibility-build/compatibility.patch。

## 编译程序

需要 Rust stable、Node.js/npm、Visual Studio C++ 工具和 CMake，以及 Windows WebView2。

在源码根目录依次执行：

```powershell
npm --prefix apps/desktop ci
npm --prefix apps/desktop run build
cargo test --locked --release -p cursor-server --test connect_wire
cargo test --locked --release -p cursor-server --lib compatibility_gates_select_backend_loop
cargo build --locked --release -p cursor-byok-desktop --features tauri/custom-protocol
```

程序位于 target/release/cursor-byok-desktop.exe。原型测试 10 项和兼容开关测试 1 项已通过。

## 制作安装包

在源码根目录执行：

```powershell
.\compatibility-build\Build-Package.ps1 -SourceRoot (Get-Location).Path -Executable .\target\release\cursor-byok-desktop.exe
```

脚本使用官方 Tauri CLI 2.11.4 的 bundle 命令生成 NSIS 安装包，不重新编译程序。
需要可以访问 npm 和 Tauri 的打包工具下载源；可通过常规代理环境变量配置网络。
源码 ZIP 内嵌在安装包中。构建目录、依赖缓存、Git 元数据和用户数据均不进入源码包。

兼容配置脚本使用 Windows 自带 PowerShell 和 winsqlite3.dll，无需在目标机器安装 Python 或 Node.js。
安装前要求退出 Cursor，修改设置前备份原值，不包含、不复制 API Key 或 CA 私钥。
