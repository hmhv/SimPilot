# SimPilot

翻译: [English](README.md) | [日本語](README.ja.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot 是一组面向 iOS Simulator 测试与验证的 agent skills，可在 Claude Code 或 Codex 中通过自然语言请求驱动。

目前仅翻译顶层 README。skill docs 和代码仍保持英文。

## 功能

- **`/sipi-test`**: 在 iOS Simulator 上自动化 UI 测试与异常状态测试。skill 会把自然语言意图转换成明确的 v2 JSON 规范，再由 `sipi run-test` / `sipi run-suite` 通过确定性 harness 执行。保存的测试可以控制权限、deep links、推送通知、定位、外观、Dynamic Type、Increase Contrast、Face ID / Touch ID、更广泛的无障碍外观设置、启动环境，以及显式配置的 network-condition provider。
- **`/sipi-verify`**: 实现后的验证。用于在功能开发或缺陷修复后，确认行为和界面都符合预期。

结果会保存在 `.simpilot/` 中，并生成可在浏览器查看的 HTML 报告。

## 前置条件

- macOS 15 或更高版本
- Xcode 26 或更高版本：在**运行时**需要，用于驱动 Simulator（SimPilot 会加载 Xcode 的 private Simulator frameworks）。安装时不需要。Xcode 27 或更高版本还会额外启用 Face ID / Touch ID 和无障碍外观设置，它们通过 `xcrun devicectl` 实现，并且可以作为键盘输入的回退路径（见[向不再接受按键输入的 simulator 输入文本](#向不再接受按键输入的-simulator-输入文本)）。
- [Claude Code](https://claude.com/claude-code) 或 Codex

## 安装

SimPilot 以单个内置 skills 的 `sipi` 二进制文件分发。一条命令即可安装:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

安装脚本会下载预构建的 `sipi` 二进制文件，随后 `sipi` 会将内置的 `sipi-common` / `sipi-test` / `sipi-verify` skills 注册到:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

运行 `sipi doctor` 验证模拟器能力。

更新和卸载:

```bash
sipi update      # 从 GitHub Releases 下载最新的 sipi 并刷新 skills
sipi uninstall   # 移除 skills、安装 metadata 和 sipi 二进制文件
```

## 快速开始

在你的 iOS 应用项目中:

- Claude Code: 使用 `/sipi-test` 这类 slash command
- Codex: 自然地提到 skill，例如 `Use the sipi-test skill to ...`

**测试:**
```text
/sipi-test 创建一个在首页和设置页签之间切换的测试
Use the sipi-test skill to create a test for switching between the home and settings tabs
```

首次使用时，SimPilot 会检测你的项目，创建 `.simpilot/config.json`，并准备 simulator 会话。

**验证:**
```text
/sipi-verify 检查新的登录流程是否能在 simulator 上正常工作
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## 常见任务

**创建测试:**
```text
/sipi-test 创建一个首页标签切换测试
/sipi-test 创建一个登录后打开设置的测试
/sipi-test 创建一个把亮度滑块设为 80% 并切换通知开关的测试
/sipi-test 从当前界面创建测试
```

保存的测试以确定性步骤驱动完整的交互面——点按、双击、开关切换、滑块、手势、拖拽、长按、捏合与原始多点触控、组合键和旋转——而不仅是点按和滑动。

它们还能创建由 Simulator 真实控制的错误前置条件，比如拒绝权限、deep links、推送投递、模拟坐标、Face ID / Touch ID 的匹配与不匹配、完整的无障碍外观设置（减弱动态效果、降低透明度、颜色滤镜、Liquid Glass 不透明度），以及由 provider 支撑的离线/延迟配置。SimPilot 不捆绑也不模仿任何专有的网络条件模拟工具：使用网络配置前请先检查 `sipi network-condition status`。

验证不止于文本匹配：除了 `contains` / `absent` 和正则表达式，单个步骤还可以对元素本身做断言——某个控件处于禁用状态、某个列表恰好有五行、某个值匹配指定模式，或者某个点按目标达到 44pt。

**运行测试:**
```text
/sipi-test 运行 settings-navigation 测试
/sipi-test 运行 regression 套件
/sipi-test 运行带 smoke 标签的测试
/sipi-test 在 iPhone 16 Pro 上运行 regression 套件
/sipi-test 在 iPhone 16 和 iPhone 15 上运行测试
/sipi-test 使用 regression-profile 设备集运行测试
```

指定多个设备时，测试会并行运行。如果 `.simpilot/config.json` 包含 `build` 配置，则会在运行前先构建应用。

**查看结果:**
```text
/sipi-test 显示最新结果
/sipi-test 显示 settings-toggle 测试的失败细节
/sipi-test 显示所有失败测试的细节
/sipi-test 打开 HTML 报告
```

每次运行都会在 run 目录中生成 `report.html`。结果保存在 `.simpilot/runs/` 下。

**管理套件:**
```text
/sipi-test 显示所有测试
/sipi-test 显示带 smoke 标签的测试
/sipi-test 使用 app-launch、settings-toggle 和 tab-navigation 创建 regression 套件
```

**质量审查:**
```text
/sipi-test 对 onboarding 和 settings 页面做无障碍审查
/sipi-test 检查缺失的 accessibility labels 和 identifiers
/sipi-test 检查 onboarding 在 English、日语和德语下的翻译完整性
/sipi-test 检查未翻译文本和文字截断
/sipi-test 比较 profile 页面在 Light 和 Dark 模式下的表现
/sipi-test 检查 settings 流程在大号 Dynamic Type 下的显示
/sipi-test 在开启减弱动态效果和颜色滤镜的情况下审查这个界面
```

`sipi a11y-audit` 可以在命令行中针对任意已启动的 simulator 运行其中机械可查的部分——过小的点按目标、缺少标签的控件、有歧义的重复标签、无意义的标签、被截断的文本——并在出现 error 级别的问题时以非零码退出，因此可以用来把关 CI。Xcode 自带的无障碍审查只能在 UI 测试 target 内部运行。

## 工作区结构

SimPilot 在 `.simpilot/` 下使用如下目录结构:

```text
.simpilot/
  config.json                  # Project configuration (app bundle ID, build settings)
  tests/                       # Test definitions
    <test-id>.json
  suites/                      # Test suites
    <suite-name>.json
  devices/                     # Device/simulator profiles
    <profile-name>.json
  runs/                        # Test run results (sipi-test)
    <run-id>/
      run.json                 # Run summary
      summary.json             # Compact agent/CI summary
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        trace.jsonl            # Per-test event trace
        step-NNN.png           # Step screenshots
        step-NNN.describe-before.json
        step-NNN.describe-after.json
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      checks.json
      findings.json
      report.html
```

建议将 `.simpilot/` 整体，或至少将 `runs/` 和 `verify/` 加入项目的 `.gitignore`。

## 参考

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests、suites、devices、results 和 metadata 的完整 JSON 规范

## 已知限制

- 文本输入默认写入字段的无障碍值（`set-text`），无需键盘，任何文字系统都适用。按键级别的输入（`type`）默认通过剪贴板粘贴；逐键直接 HID 输入仅支持美式键盘布局，若客户机当前启用的是其他布局则会输入错误的字符
- **长期使用的 simulator 可能不再接受键盘 HID**（在 Xcode 27.0 beta 6 上实测）：粘贴、逐键输入和全选+删除都会被忽略，而触摸输入正常。这取决于设备的使用时长而非 iOS 版本，`simctl erase` 和重启都无法恢复。`type` 会检测到这一点并直接失败，而不是报告成功；`set-text` 不受影响。若已启用 Xcode 27 的服务，`type` 会经由它重试并成功（见下文）
- 无障碍树声称存在、但实际无法触摸的元素，点击后仍会报告成功。`describe-point` 同样会返回该元素，因此任何一层都无法区分；Xcode 自身的工具也是同样的行为
- Face ID / Touch ID，以及 light/dark 之外的无障碍外观项需要 Xcode 27——它们通过 `xcrun devicectl` 实现，而 devicectl 只能作用于该版本及之后的 simulator
- 对比度和文字截断不在 `sipi a11y-audit` 的范围内；两者都需要对渲染帧做像素分析
- 仅支持 simulator，不支持真机

## 向不再接受按键输入的 simulator 输入文本

simulator 可能进入忽略 SimPilot 注入的键盘事件的状态：触摸依然可用，而粘贴、逐键输入和全选+删除都失效。SimPilot 在正常设备和该状态的设备上发送的是完全相同的事件，因此 SimPilot 这一侧没有可修复之处。而 Xcode 27 自带的设备交互服务走的是另一条路径，该状态的设备仍会接受，并且这条路径也不依赖客户机的键盘布局。

`sipi type` 会把它作为回退：当检测到自身的按键没有送达时，不让步骤失败，而是经由 Xcode 的服务重试。加上 `--xcode-mcp` 则从一开始就使用该路径。SimPilot 的其他功能都无需这项配置，`set-text` 本来就不需要键盘。

需要满足三个条件：

```bash
xcode-select -p                    # Xcode 27 或更高版本
sudo xcrun mcp-server enable       # 开启 headless 模式
sipi xcode-mcp --approve <.xcodeproj 或 .xcworkspace 的路径>
```

打开该项目只是为了弹出 Xcode 的授权对话框，随后会立即关闭。配置完成后，若回退被触发而服务尚未运行，sipi 会将其启动。Xcode 将授权绑定到具体的二进制文件，因此每次 `sipi update` 或重新构建后都需要再次执行授权步骤。当前状态可用 `sipi xcode-mcp` 查看，回退是否可用可用 `sipi doctor` 确认。

`--clear` 无法使用该路径：全选和删除同样是按键输入，而该服务只能输入文本、无法清空字段。需要整体替换值时请使用 `sipi set-text`。


## Note

这个仓库主要由 AI 维护。欢迎提交 issue 和反馈，但不接受 pull request。如果你想按自己的流程调整，请 fork 后使用。

## 免责声明

SimPilot 是一个开发工具。它通过 Apple 的**未公开私有框架**驱动 iOS 模拟器，而这些框架可能被 Apple 在任意 Xcode 或 macOS 更新中更改或移除，从而可能在没有任何预告的情况下导致 SimPilot 无法工作。本工具与 Apple 没有关联，也未获得 Apple 认可，并非用于 App Store 或生产环境。本工具**按“现状”提供，不附带任何保证——使用风险由你自行承担。**

## License

MIT © 2026 hmhv。请参阅 [LICENSE](LICENSE)。
