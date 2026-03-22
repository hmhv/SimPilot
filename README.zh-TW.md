# SimPilot

翻譯: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot 是一組用於 iOS Simulator 測試與驗證的 agent skills，可在 Claude Code 或 Codex 中透過自然語言請求驅動。

目前只翻譯最上層 README。skill docs 與程式碼仍維持英文。

## 功能

- **`/sipi-test`**: 在 iOS Simulator 上自動化 UI 測試。你可以用自然語言定義測試，skill 會自動完成互動與驗證。支援回歸測試、多裝置執行，以及品質稽核（無障礙、在地化、外觀檢查）。
- **`/sipi-verify`**: 實作後驗證。用於在功能新增或錯誤修正後，確認行為與畫面都符合預期。

結果會儲存在 `.simpilot/` 中，並產生可在瀏覽器開啟的 HTML 報告。

## 前置需求

- macOS 15 或以上
- Xcode 26 或以上
- [AXe](https://github.com/cameroncooke/AXe) CLI
  - `brew install cameroncooke/axe/axe`
  - `axe init`
- [Claude Code](https://claude.com/claude-code) 或 Codex

SimPilot 的 simulator automation 預設要求 agent 環境中已具備 `axe` skill。

## 安裝

```bash
git clone https://github.com/hmhv/SimPilot.git
cd SimPilot
make install
```

`make install` 會執行以下動作:

- 將 SimPilot skills 註冊到 Claude Code (`~/.claude/skills/`)
- 將 SimPilot skills 註冊到 Codex (`~/.agents/skills/`)

更新與解除安裝:

```bash
make update
make uninstall
```

## 快速開始

在你的 iOS app 專案中使用:

- Claude Code: 使用像 `/sipi-test` 這樣的 slash commands
- Codex: 自然地提到 skill，例如 `Use the sipi-test skill to ...`

**測試:**
```text
/sipi-test 建立一個在首頁與設定分頁間切換的測試
Use the sipi-test skill to create a test for switching between the home and settings tabs
```

第一次使用時，SimPilot 會偵測你的專案、建立 `.simpilot/config.json`，並準備 simulator session。

**驗證:**
```text
/sipi-verify 檢查新的登入流程是否能在 simulator 上正常運作
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## 常見工作

**建立測試:**
```text
/sipi-test 建立首頁分頁切換測試
/sipi-test 建立登入後開啟設定的測試
/sipi-test 從目前畫面建立測試
```

**執行測試:**
```text
/sipi-test 執行 settings-navigation 測試
/sipi-test 執行 regression suite
/sipi-test 執行帶有 smoke 標籤的測試
/sipi-test 在 iPhone 16 Pro 上執行 regression suite
/sipi-test 在 iPhone 16 和 iPhone 15 上執行測試
/sipi-test 使用 regression-profile 裝置集執行測試
```

指定多個裝置時，測試會平行執行。如果 `.simpilot/config.json` 內有 `build` 項目，則會在執行前先建置 app。

**查看結果:**
```text
/sipi-test 顯示最新結果
/sipi-test 顯示 settings-toggle 測試的失敗細節
/sipi-test 顯示所有失敗測試的細節
/sipi-test 開啟 HTML 報告
```

每次 run 都會在 run 目錄中產生 `report.html`。結果會儲存在 `.simpilot/runs/`。

**管理 suites:**
```text
/sipi-test 顯示所有測試
/sipi-test 顯示帶有 smoke 標籤的測試
/sipi-test 用 app-launch、settings-toggle、tab-navigation 建立 regression suite
```

**品質稽核:**
```text
/sipi-test 稽核 onboarding 與 settings 畫面的無障礙
/sipi-test 檢查缺少的 accessibility labels 與 identifiers
/sipi-test 檢查 onboarding 在 English、日文與德文下的翻譯完整性
/sipi-test 檢查未翻譯文字與文字裁切
/sipi-test 比較 profile 畫面在 Light 與 Dark 模式下的表現
/sipi-test 檢查 settings 流程在大型 Dynamic Type 下的顯示
```

## Workspace 結構

SimPilot 在 `.simpilot/` 下使用以下標準結構:

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

建議將整個 `.simpilot/`，或至少 `runs/` 與 `verify/`，加入專案的 `.gitignore`。

## 參考

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests、suites、devices、results 與 metadata 的完整 JSON 規格

## 已知限制

- 文字輸入使用剪貼簿，密碼情境無法使用 `axe type`
- `axe type` 預設假設為美式鍵盤配置
- 無法重現 drag and drop、pinch、rotation 手勢
- PhotosPicker 這類 system UI 無法透過 `describe-ui` 存取

## Note

這個儲存庫主要由 AI 維護。歡迎提交 issue 與回饋，但不接受 pull request。如果你想依自己的流程調整，請 fork 後使用。

## License

請參閱 [LICENSE](LICENSE)。
