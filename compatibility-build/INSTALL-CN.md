# Cursor BYOK 1.0.1 Windows 兼容版

本安装包基于 https://github.com/leookun/cursor-byok 的 v1.0.1 制作，是本地兼容修复版，非上游官方发布。

修复内容：接受 Cursor 二进制 BidiAppend 消息；在接管连接中关闭不兼容的 local_loop / RunInference 通道，使用后端 AgentService 协议；恢复 HTTP/1.1 流式连接。

## 安装和使用

1. 保存工作并退出 Cursor、Cursor BYOK，然后运行安装包。
2. 打开 Cursor BYOK，按原流程初始化本地 CA、启用 Cursor 接管，并配置自己的模型服务。
3. 完全重启 Cursor，新建对话，选择配置的模型。

已有 API Key、模型配置、CA 仍保存在本机用户数据目录，安装包不包含这些数据。
安装时只对现有 Cursor 缓存中的 `agent_host_local_loop` 开关及已有的 HTTP/1.0 回退设置进行兼容调整。
有改动时，原值备份在 `%LOCALAPPDATA%\Cursor BYOK Repair\installer-backups\`。
不会自动安装或信任 CA 证书。

## 安装后的文件

- `cursor-byok-desktop.exe`：兼容版程序，界面版本号仍为 1.0.1。
- `source/Cursor-BYOK-1.0.1-compat-source.zip`：对应完整源码、补丁、构建说明及安装包制作脚本。
- `compatibility/Apply-Compatibility.ps1`：安装时使用的兼容配置脚本，可在 Cursor 退出后手动运行。
- `compatibility/README-CN.md`：本说明。

已在 Windows x64 / Cursor 3.29.15 上完成真实聊天验证。升级 Cursor 后仍需按实际版本检查兼容性。

项目采用 MIT License，源码包保留上游 LICENSE。
