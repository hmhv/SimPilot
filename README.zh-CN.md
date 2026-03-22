# SimPilot

翻译: [English](README.md) | [日本語](README.ja.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot 是一组面向 iOS Simulator 测试与验证的 agent skills，可在 Claude Code 或 Codex 中通过自然语言请求驱动。

目前仅翻译顶层 README。skill docs 和代码仍保持英文。

## 功能

- **`/sipi-test`**: 在 iOS Simulator 上自动化 UI 测试。可以用自然语言定义测试，并自动执行交互和验证。支持回归测试、多设备运行，以及质量审查（无障碍、本地化、外观检查）。
- **`/sipi-verify`**: 实现后的验证。用于在功能开发或缺陷修复后，确认行为和界面都符合预期。

结果会保存在 `.simpilot/` 中，并生成可在浏览器查看的 HTML 报告。

## 前置条件

- macOS 15 或更高版本
- Xcode 26 或更高版本
- [AXe](https://github.com/cameroncooke/AXe) CLI
  - `brew install cameroncooke/axe/axe`
  - `axe init`
- [Claude Code](https://claude.com/claude-code) 或 Codex

SimPilot 的 simulator automation 默认要求 agent 环境中已经安装 `axe` skill。

## 安装

```bash
git clone https://github.com/hmhv/SimPilot.git
cd SimPilot
make install
```

`make install` 会执行以下操作:

- 将 SimPilot skills 注册到 Claude Code (`~/.claude/skills/`)
- 将 SimPilot skills 注册到 Codex (`~/.agents/skills/`)

更新和卸载:

```bash
make update
make uninstall
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
/sipi-test 从当前界面创建测试
```

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
```

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
      report.html              # HTML report (open in browser)
      <test-id>/
        result.json            # Test result
        step-NNN.png           # Step screenshots
        recording.mp4          # (if enabled)
  verify/                      # Verification results (sipi-verify)
    <timestamp>_<description>/
      report.html
```

建议将 `.simpilot/` 整体，或至少将 `runs/` 和 `verify/` 加入项目的 `.gitignore`。

## 参考

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests、suites、devices、results 和 metadata 的完整 JSON 规范

## 已知限制

- 文本输入使用剪贴板，密码场景不能使用 `axe type`
- `axe type` 默认假设为美式键盘布局
- 无法复现 drag and drop、pinch、rotation 手势
- PhotosPicker 这类 system UI 无法通过 `describe-ui` 访问

## Note

这个仓库主要由 AI 维护。欢迎提交 issue 和反馈，但不接受 pull request。如果你想按自己的流程调整，请 fork 后使用。

## License

请参阅 [LICENSE](LICENSE)。
