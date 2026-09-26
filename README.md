# openCoder（开放码农）

轻量级 iOS 文本 / 代码编辑器，对标 Textastic，并内置 SFTP / SSH 远程能力。

## 功能（v1）

- 本地文件浏览：新建文件 / 文件夹、重命名、删除、导入
- 代码编辑器（Runestone 内核）：行号、Tree-sitter 语法高亮（30+ 语言）、自动换行开关
- 多标签页编辑，未保存内容显示圆点标记
- 编辑器内查找 / 替换（工具栏按钮，或外接键盘 Cmd+F）
- SFTP：服务器配置（密码认证，密码存 Keychain）、远程目录浏览、远程文件打开 / 保存回写
- SSH 命令控制台：执行远程命令并查看输出
- 主机密钥 TOFU：首次连接记住服务器主机密钥（跨启动持久化），之后变更则拒绝连接并报错
- 设置：自动换行、行号显示、断开所有连接
- 轻量设计语言（借鉴 ChunUI 思路、自实现、无第三方依赖）：语义化颜色 token、设置行、统一空态、顶部 toast 成功反馈

## v1 暂不支持（计划 v1.1）

- 跳转到指定行
- 字号 / 主题切换（当前为 Runestone DefaultTheme）
- 私钥认证（当前仅密码认证）
- 远程新建文件 / 上传 / 删除 / 重命名

## 技术栈

- SwiftUI App 外壳，iOS 17+
- [Runestone](https://github.com/simonbs/Runestone) 0.5.2（编辑器内核，MIT）
- [TreeSitterLanguages](https://github.com/simonbs/TreeSitterLanguages) 0.1.10（语法高亮，MIT）
- [Citadel](https://github.com/Orlandos-nl/Citadel) 0.12.1（SSH/SFTP，MIT）
- 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成

## 构建

```bash
xcodegen generate
open openCoder.xcodeproj
```

GitHub Actions（`macos-15`）在每次 push 到 main 时自动构建并上传 **未签名 IPA**
（`openCoder-unsigned.ipa` artifact）。拿到后用 Sideloadly / AltStore 等工具以自己的
Apple ID 自签名安装。

## 安全说明

- 服务器密码只存于 iOS Keychain，不写入 UserDefaults、文件或日志。
- 主机密钥采用 TOFU：首次连接时记录，之后若服务器主机密钥变化，连接会被拒绝。
- 未签名 IPA 仅用于自签名安装，请勿分发给他人。
