# SimPilot

翻译: [English](README.md) | [日本語](README.ja.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot 让 Claude Code 或 Codex 通过自然语言驱动 iOS Simulator——读取屏幕、点按、输入、折叠、截取、把文件放进 App 并读回它保存的内容——同时让背后的 Xcode 和 simulator 工具链保持已安装且干净。如何检查结果交给 agent 决定：它会读取屏幕、截取画面，并以适合任务的方式读取 App 的数据。

目前仅翻译顶层 README。skill docs 和代码仍保持英文。

## 功能

- **驱动 simulator**：`sipi` 以原生、headless 的方式读取无障碍树并据此操作：按标签或 id 点按、以任何文字系统输入文本、手势、硬件按钮、旋转、折叠 iPhone Duo、截图和录像、Face ID / Touch ID、无障碍外观设置，以及内存警告。
- **处理 App 数据**：把文件放进 App 的数据容器、App Group 或 Files.app；以文本、JSON、plist 或 SQLite 形式查看 App 保存的内容；为容器创建快照并比较差异；收集 App 的崩溃报告。
- **管理 Xcode 和 simulator runtime**：`sipi xcode list / install / uninstall` 用于查看、安装和删除 Xcode，`sipi runtime list` 显示 Apple 提供的 simulator runtime；runtime 和设备的安装与删除按 skill 中的说明通过 `xcodebuild` 和 `simctl` 完成。
- **清理**：找出并移除 Xcode 和 simulator 留下的内容：DerivedData、device support 文件、预览和测试用设备、无法使用的 runtime、旧版 Xcode。未经批准不会移除任何内容，文件会被移到废纸篓。

## 前置条件

- Xcode 27.2 或更高版本
- macOS 26.6 或更高版本
- [Claude Code](https://claude.com/claude-code) 或 Codex

## 安装

SimPilot 以单个内置 skill 的 `sipi` 二进制文件分发。一条命令即可安装:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

安装脚本会下载预构建的 `sipi` 二进制文件，随后 `sipi` 会将内置的 `sipi-common` skill 安装到:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

运行 `sipi doctor` 验证模拟器能力。

更新和卸载:

```bash
sipi update      # 从 GitHub Releases 下载最新的 sipi 并刷新 skill
sipi uninstall   # 删除 skill、安装元数据和 sipi 二进制文件
```

从 2.x 更新时会移除 `sipi-test` 和 `sipi-verify` skills。App 仓库中的 `.simpilot/tests/`、`suites/`、`devices/`、`runs/`、`verify/`，以及 `config.json` 中 `app`、`build` 以外的键都不再使用，不需要时请删除。

## 快速开始

在你的 iOS 应用项目中:

- Claude Code: 使用 `/sipi-common` 后接请求内容，或直接提出请求
- Codex: 提到该 skill，例如 `Use the sipi-common skill to ...`

```text
/sipi-common 构建 App，并在 simulator 上检查新的登录流程是否正常
/sipi-common 打开设置并开启通知
/sipi-common 把 sample.pdf 放进 App 的 Inbox，并检查导入界面
/sipi-common 显示登录后 App 保存的内容
/sipi-common 安装 Xcode 27.2 和 iOS 27.2 runtime
/sipi-common 清理 Xcode 占用的磁盘空间
```

首次使用时，SimPilot 会检测你的项目，创建 `.simpilot/config.json`，并准备 simulator。

## 直接驱动 simulator

`sipi` 是一个可由 agent 逐步调用的普通 CLI。`describe-ui --format compact` 以每个元素一行（类型、标签、id、值、frame、点击坐标）输出无障碍树，体积只有 JSON 的几分之一；`wait-for` 会轮询直到某个标签、id、值或文本出现（或消失），替代 sleep；`screenshot --max-pixel 600` 返回足够小、便于查看的截图；`memory-warning` 发送 Simulator.app Debug 菜单曾提供的内存警告（Xcode 27 及以上）；`fold-state` 报告 iPhone Duo 的两块屏幕中哪一块是点亮的，`fold --closed|--open|--angle` 可以折叠它（simctl 和 devicectl 都做不到），`--display inner|cover` 可以截取熄灭的那一块。完整命令见 `sipi --help`。

`sipi a11y-audit` 可针对任意已启动的 simulator 检查当前界面——过小的点按目标、缺少标签的控件、有歧义的重复标签、无意义的标签、被截断的文本。Xcode 自带的无障碍审查只能在 UI 测试 target 内部运行。

App 数据相关命令见 [App data and evidence commands](docs/data-artifacts.md)。

## Xcode 和 simulator runtime

```bash
sipi xcode install 27B48
```

传入 `sipi xcode list`（来自 [xcodereleases.com](https://xcodereleases.com)）列出的 build 号。随后会打开一个 developer.apple.com 的窗口；在其中登录后它会自动关闭。会话只在本次运行期间保存在内存中，不会存储任何内容。App 会安装为 `/Applications/Xcode-<version>.app`（例如 `Xcode-27.2.0-release.candidate.app`）。选择该 Xcode 需要 root 权限，因此 `sipi` 会打印 `sudo xcode-select -s …` 和 `sudo xcodebuild -runFirstLaunch` 命令，由你自行执行。

`sipi runtime list` 列出 Apple 提供的 simulator runtime，并标出已安装的（`xcodebuild` 和 `simctl` 都无法列出）。安装用 `xcodebuild -downloadPlatform iOS -buildVersion <版本> -architectureVariant arm64`，删除用 `xcrun simctl runtime delete`，创建设备用 `xcrun simctl create`。skill 了解这些命令并会替你执行。

## 项目文件

SimPilot 会在你的项目中保留两个文件:

```text
.simpilot/
  config.json   # bundle ID 以及 App 的构建方式
  notes.md      # skill 记录的 App 特有操作技巧
```

两者都值得提交：队友或其他 agent 都能从中受益。

## 已知限制

- 文本输入默认写入字段的无障碍值（`set-text`），无需键盘，任何文字系统都适用。按键级别的输入（`type`）默认通过剪贴板粘贴；逐键直接 HID 输入仅支持美式键盘布局，若客户机当前启用的是其他布局则会输入错误的字符
- **长期使用的 simulator 可能不再接受键盘 HID**（在 Xcode 27.0 beta 6 上实测）：粘贴、逐键输入和全选+删除都会被忽略，而触摸输入正常。这取决于设备的使用时长而非 iOS 版本，`simctl erase` 和重启都无法恢复。`type` 会检测到这一点并直接失败，而不是报告成功；`set-text` 不受影响。`type --xcode-mcp` 会改为经由 Xcode 27 自带的服务输入，在实测的设备上由此成功，但有代价（见下文）
- 无障碍树声称存在、但实际无法触摸的元素，点击后仍会报告成功。`describe-point` 同样会返回该元素，因此任何一层都无法区分；Xcode 自身的工具也是同样的行为
- 对比度和被容器裁切（不带省略号）的文字不在 `sipi a11y-audit` 的范围内；两者都需要对渲染帧做像素分析
- **iPhone Duo**（在 Xcode 27.2 上实测）：点击、滑动、文字输入和硬件按钮都能到达两块屏幕。内屏对无障碍 hit-test 不返回任何结果，因此按选择器的点击会不经确认地发送到元素的位置，`set-text` / `describe-point` 只能在外屏使用。Device Hub 打开期间会接管设备的输入：内屏的点击被丢弃，模拟器的剪贴板被 Mac 的剪贴板覆盖，因此 `type` 会拒绝粘贴。`sipi doctor` 会报告这种状态，`sipi repair-input` 可恢复输入。无法通过脚本旋转 Duo simulator，请使用 Device Hub 的旋转按钮
- 仅支持 simulator，不支持真机

## 向不再接受按键输入的 simulator 输入文本

simulator 可能进入忽略 SimPilot 注入的键盘事件的状态：触摸依然可用，而粘贴、逐键输入和全选+删除都失效。SimPilot 在正常设备和该状态的设备上发送的是完全相同的事件，因此 SimPilot 这一侧没有可修复之处。而 Xcode 27 自带的设备交互服务走的是另一条路径，实测时该状态的设备仍会接受（磨损更严重的设备连这条路径也会忽略），并且这条路径也不依赖客户机的键盘布局。

`sipi type --xcode-mcp` 选择该路径。SimPilot 绝不会自行使用它：在 iOS 27 上，一次这样的会话会让该设备之后启动的所有 App 的无障碍树为空，直到设备重启（`simctl shutdown` + `boot`）。请把它放在最后使用，或在下一次启动前重启设备。SimPilot 的其他功能都无需这项配置，`set-text` 本来就不需要键盘。

需要满足三个条件：

```bash
xcode-select -p                    # Xcode 27.2 或更高版本
sudo xcrun mcp-server enable       # 开启 headless 模式
sipi xcode-mcp --approve <.xcodeproj 或 .xcworkspace 的路径>
```

打开该项目只是为了弹出 Xcode 的授权对话框，随后会立即关闭。配置完成后，若服务尚未运行，sipi 会将其启动。Xcode 将授权绑定到具体的二进制文件，因此每次 `sipi update` 或重新构建后都需要再次执行授权步骤。当前状态（包括同一路径上旧构建的授权）可用 `sipi xcode-mcp` 查看，该路径是否可用可用 `sipi doctor` 确认。

`--clear` 无法使用该路径：全选和删除同样是按键输入，而该服务只能输入文本、无法清空字段。需要整体替换值时请使用 `sipi set-text`。

代价来自会话本身而非输入：在 Xcode 27.2 上仅用一次点击的会话重新测量，之后启动的 App 的无障碍树在设备重启前都是空的。


## Note

这个仓库主要由 AI 维护。欢迎提交 issue 和反馈，但不接受 pull request。如果你想按自己的流程调整，请 fork 后使用。

## 免责声明

SimPilot 是一个开发工具。它通过 Apple 的**未公开私有框架**驱动 iOS 模拟器，而这些框架可能被 Apple 在任意 Xcode 或 macOS 更新中更改或移除，从而可能在没有任何预告的情况下导致 SimPilot 无法工作。本工具与 Apple 没有关联，也未获得 Apple 认可，并非用于 App Store 或生产环境。本工具**按“现状”提供，不附带任何保证——使用风险由你自行承担。**

## License

MIT © 2026 hmhv。请参阅 [LICENSE](LICENSE)。
