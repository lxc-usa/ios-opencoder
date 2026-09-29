# openCoder（开放码农）

轻量级 iOS 文本 / 代码编辑器，对标 Textastic，并内置 SFTP / SSH 远程能力。
中英双语界面（跟随系统语言）。

<!-- ipa-release:start -->
## 📦 固定取包地址（永久有效）

**下载（链接永久不变）：** [openCoder-latest.ipa](https://raw.githubusercontent.com/lxc-usa/ios-opencoder/main/dist/openCoder-latest.ipa)

| 项目 | 内容 |
|---|---|
| 当前版本 | v17（标签切换高亮修复） |
| 文件大小 | 10,006,170 字节（约 9.5 MB） |
| MD5 | `87d171a2b8a0774930d479f84771faf6` |
| SHA256 | `a4ede3914943f2d041f5598065bfb15bbca09320adb8869f84f7ad5b93101fcb` |
| Bundle ID | `one.lxc.opencoder` |
| 系统要求 | iOS 17.0+ |

每次有新包，更新的都是上面这一个地址，不再发临时链接。

### 安装步骤（未签名 IPA）
1. 点上面的固定地址下载 IPA；
2. 用爱思助手 / Sideloadly / AltStore 等工具自行签名后安装到 iPhone/iPad；
3. 安装前可核对文件大小与校验值，确认下载完整。

> 若本节暂时没有可下载的包，会明确写"暂无可下载版本"，不会留空。
<!-- ipa-release:end -->

## 功能（v16）

- **本地文件浏览**：新建文件 / 文件夹、重命名、导入；「移出列表」只移记录不删文件（文件搬进 `Documents/.opencoder_trash/` 隐藏目录，可从系统"文件"App 找回）
- **代码编辑器**（Runestone 内核）：行号、Tree-sitter 语法高亮（30+ 语言）、自动换行开关
- **多标签页编辑**，未保存内容显示圆点标记；活跃标签自动滚动保持可见
- **编辑器内查找 / 替换**（工具栏按钮，或外接键盘 Cmd+F）
- **字体与排版**：4 款经典等宽字体（SF Mono / Menlo / Courier New / Courier）、字号 10–20pt、行距 0–12pt，终端与编辑器共用
- **外观**：跟随系统 / 浅色 / 深色；深色下编辑器为纯黑背景
- **SFTP**：服务器配置（密码认证，密码存 Keychain）、远程目录浏览、远程文件打开 / 保存回写、SFTP 通道复用；浏览页右上角一键进入终端
- **SSH 交互式终端**（SwiftTerm xterm 仿真）：持久化 login shell，支持 top / vi 全屏、Tab 补全、Ctrl-C/D，Esc/Ctrl/方向键快捷栏；可选手「终端会话保持」，离开再回继续上次会话
- **SSH 兼容性**：RSA-SHA2 主机密钥（RFC 8332，兼容 OpenSSH 10）、aes256-ctr / aes192-ctr 加密；握手失败自动抓取服务器 KEXINIT 并给出双方算法对照诊断
- **主机密钥 TOFU**：按 `host:port` 首次连接记住服务器主机密钥（跨启动持久化），之后变更则拒绝连接并报错；不断线复用已断开的 client
- **设置**：字体与排版、外观、终端会话保持、断开所有服务器连接
- **轻量设计语言**（借鉴 ChunUI 思路、自实现、无第三方依赖）：语义化颜色 token、设置行、统一空态、顶部 toast 成功反馈

## 暂不支持

- 跳转到指定行
- 私钥认证（当前仅密码认证）
- 远程新建文件 / 上传 / 删除 / 重命名

## 版本历史

- **v16**：修复中文界面显示英文——补 `zh-Hans.lproj` 中文语言包（此前只有英文包，iOS 会 fallback 到开发语言英文）；`SettingRow` / `DSGroupCard` 的标题改用 `LocalizedStringKey`，中英文设备均正确查表
- **v15**：英中双语本地化（143 条字符串，中文为 key，源码保持中文）
- **v14**：「移出列表」改走物理隔离——文件搬进 `Documents/.opencoder_trash/`（点开头目录，系统导入选择器自动隐藏），导入同名文件即全新文件，不再"复活"；启动时自动迁移旧版隐藏记录
- **v13–v13.2**：文件列表删除改为只删记录不删文件（UserDefaults 隐藏集合方案，真机有状态问题，后被 v14 取代）；左滑文案统一为「移出列表」；导入时跳过曾移出列表的文件名
- **v12**：终端会话保持选项（`TerminalSessionCache` 按服务器 ID 内存保留会话，离开仅 detach，后台继续跑，重进补上输出）；generation 守卫根治 stop/start 竞态
- **v11**：交互式 PTY 终端——Citadel `withPTY` 开持久化 login shell + SwiftTerm 1.20.0 做 xterm 仿真（ANSI/备用屏幕/光标定位/尺寸变化），替代逐条命令执行；Swift 6 并发隔离重构（`SSHManager.runPTY`，UI 只交换 Sendable）
- **v10**：修复深色下编辑器白字白底（Runestone 把文本区背景写死白色，改为动态黑/白）；SFTP 浏览页右上角加终端入口按钮；活跃标签自动滚动
- **v9**：字体设置同步到代码编辑器（`MonoTheme` 包装 DefaultTheme 只覆盖字体）、行距配置（换算 `lineHeightMultiplier`）、深浅配色方案（跟随系统/浅色/深色）；SFTP 通道复用修复泄漏
- **v8**：终端 UI 优化——4 款经典等宽字体、字号设置、紧凑布局（行距/边距缩小）、清屏按钮、info 弹窗替代常驻提示条
- **v7**：修复 `EXC_BREAKPOINT` 闪退——`derInteger` 里 Data 原地修改触发 iOS 26 Foundation `InlineSlice` precondition，改用 `[UInt8]` 数组组装 DER；修正 RSA-SHA256 签名配对
- **v6**：修复后台线程改 `@State` 崩溃——全部 19 个 View 加 `@MainActor`
- **v5**：RSA-SHA2 主机密钥支持（RFC 8332，本地 vendoring `swift-nio-ssh` 最小补丁，兼容 OpenSSH 10.0p2）；真机验证握手通过
- **v4**：SSH 握手失败根因修复——补 `aes256-ctr` / `aes192-ctr`（CommonCrypto 实现）+ 握手失败时自动抓取服务器 KEXINIT 探针
- **v3**：App Icon（1024 精确绘制：深蓝黑编辑器渐变底 + 青蓝渐变 `</>` + 绿色终端光标）
- **v2**：修复真机三问题——XcodeGen 洗掉 `UILaunchScreen`（project.yml 声明全部必需键）、编辑器"加载中"卡死（独立 `DocumentContentView` 观察单个文档）、SSH 错误中文映射 + TOFU 按 `host:port` + 不复用断线 client
- **v1**：初始版本

## 技术栈

- SwiftUI App 外壳，iOS 17+
- [Runestone](https://github.com/simonbs/Runestone) 0.5.2（编辑器内核，MIT）
- [TreeSitterLanguages](https://github.com/simonbs/TreeSitterLanguages) 0.1.10（语法高亮，MIT）
- [Citadel](https://github.com/Orlandos-nl/Citadel) 0.12.1（SSH/SFTP，MIT）
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.20.0（终端仿真，MIT）
- `Vendor/swift-nio-ssh`：本地 vendoring 的 NIOSSH（上游 Wellz26/swift-nio-ssh 0.3.4），含 RSA-SHA2 最小补丁，说明见 `Vendor/swift-nio-ssh/PATCHES.md`
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
- 主机密钥采用 TOFU：按 `host:port` 首次连接时记录，之后若服务器主机密钥变化，连接会被拒绝。
- 未签名 IPA 仅用于自签名安装，请勿分发给他人。
