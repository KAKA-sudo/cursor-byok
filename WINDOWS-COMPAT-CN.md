# Windows x64 兼容修复版

[下载单文件安装包（约 30 MB）](https://github.com/KAKA-sudo/cursor-byok/raw/refs/heads/main/releases/windows/Cursor.BYOK_1.0.1-compat.20261111_x64-setup.exe)

安装包：`releases/windows/Cursor.BYOK_1.0.1-compat.20261111_x64-setup.exe`

SHA256：`CB33AC8AED3EE3B0EF1042EC9A147E04A0AC5037CAE7EA94F95A9BFD21277F65`

## 修复内容

- 接受 Cursor 的二进制 BidiAppend 消息，同时支持十六进制消息。
- 本地接管时关闭不支持的 `agent_host_local_loop / RunInference`，使用后端 AgentService 协议。
- 安装时恢复 HTTP/1.1 流式连接，并更新同一项本地缓存开关；修改前备份原值。

安装前保存工作并退出 Cursor、BYOK。选择原安装目录可覆盖程序，模型配置和 API Key 保留。
本包不含任何用户 API Key、模型配置、CA 私钥或本机数据备份，也不会自动安装、信任 CA。

安装后 `source/` 内有完整源码 ZIP、最终补丁和打包脚本；`compatibility/` 内有兼容配置脚本及使用说明。

## 源码版本与构建

安装包的准确源码基线是上游 **v1.0.1**（`2068ab20513288e6a0289d33febe872a30608610`）。
对应本仓库标签：[`v1.0.1-windows-compat.20261111`](https://github.com/KAKA-sudo/cursor-byok/tree/v1.0.1-windows-compat.20261111)。

`main` 分支保留其后续上游内容，并同步相同修复；如需复现此安装包，应使用上述标签或安装包内的源码。
不同上游版本的数据库格式可能不同，迁移前应备份现有数据。

构建说明见 [compatibility-build/BUILD-CN.md](compatibility-build/BUILD-CN.md)。
打包脚本使用官方 Tauri CLI 2.11.4 / NSIS；目标机器无需 Python 或 Node.js。

## 验证范围

- v1.0.1 发布源码：10 项 Connect/protobuf 测试、1 项兼容开关测试通过。
- 安装脚本：三种开关名称格式、新用户、备份、重复执行、SQLite 完整性通过隔离测试。
- Windows x64 / Cursor 3.29.15：真实聊天完成。
- 安装包内程序与已验证程序逐字节一致，源码 ZIP 的 CRC 和源码文件内容已校验。

这是本仓库提供的兼容修复包，非上游官方发布；界面版本号仍显示 1.0.1。
