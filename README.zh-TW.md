# SimPilot

翻譯: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot 是一組用於 iOS Simulator 測試與驗證的 agent skills，可在 Claude Code 或 Codex 中透過自然語言請求驅動。

目前只翻譯最上層 README。skill docs 與程式碼仍維持英文。

## 功能

- **`/sipi-test`**: 在 iOS Simulator 上自動化 UI 測試與異常狀態測試。skill 會把自然語言意圖轉換成明確的 v2 JSON 規格，再由 `sipi run-test` / `sipi run-suite` 透過確定性 harness 執行。儲存的測試可以控制權限、deep links、推播通知、定位、外觀、Dynamic Type、Increase Contrast、Face ID / Touch ID、VoiceOver、更廣泛的無障礙外觀設定、啟動環境，以及明確設定的 network-condition provider。
- **`/sipi-verify`**: 實作後驗證。用於在功能新增或錯誤修正後，確認行為與畫面都符合預期。

結果會儲存在 `.simpilot/` 中，並產生可在瀏覽器開啟的 HTML 報告。

## 前置需求

- macOS 15 或以上
- Xcode 26 或以上：在**執行時**需要，用於驅動 Simulator（SimPilot 會載入 Xcode 的 private Simulator frameworks）。安裝時不需要。Xcode 27 或以上還會額外啟用 Face ID / Touch ID、VoiceOver 與無障礙外觀設定，它們透過 `xcrun devicectl` 實作。
- [Claude Code](https://claude.com/claude-code) 或 Codex

## 安裝

SimPilot 以單一內嵌 skills 的 `sipi` 二進位檔發佈。一行指令即可安裝:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

安裝程式會下載預先建置的 `sipi` 二進位檔，接著 `sipi` 會將內嵌的 `sipi-common` / `sipi-test` / `sipi-verify` skills 註冊到:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

執行 `sipi doctor` 驗證模擬器能力。

更新與解除安裝:

```bash
sipi update      # 從 GitHub Releases 下載最新的 sipi 並更新 skills
sipi uninstall   # 移除 skills、安裝 metadata 與 sipi 二進位檔
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
/sipi-test 建立一個把亮度滑桿設為 80% 並切換通知開關的測試
/sipi-test 從目前畫面建立測試
```

儲存的測試以確定性步驟驅動完整的互動面——點按、點兩下、開關切換、滑桿、手勢、拖曳、長按、捏合與原始多點觸控、組合鍵與旋轉——而不只是點按與滑動。

它們也能建立由 Simulator 實際控制的錯誤前置條件，例如拒絕權限、deep links、推播投遞、模擬座標、Face ID / Touch ID 的相符與不相符、VoiceOver、完整的無障礙外觀設定（減少動態效果、降低透明度、色彩濾鏡、Liquid Glass 不透明度），以及由 provider 支援的離線／延遲設定檔。SimPilot 不內附也不模仿任何專有的網路狀態模擬工具：使用網路設定檔前請先檢查 `sipi network-condition status`。

驗證不只是文字比對：除了 `contains` / `absent` 與正規表示式，單一步驟還可以對元素本身做斷言——某個控制項處於停用狀態、某個列表剛好有五列、某個值符合指定樣式，或者某個點按目標達到 44pt。

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
/sipi-test 在開啟減少動態效果與色彩濾鏡的情況下稽核這個畫面
```

`sipi a11y-audit` 可以在命令列中針對任何已啟動的 simulator 執行其中機械可檢查的部分——過小的點按目標、缺少標籤的控制項、有歧義的重複標籤、無意義的標籤、被截斷的文字——並在出現 error 嚴重度的問題時以非零碼結束，因此可以用來把關 CI。Xcode 自身的無障礙稽核只能在 UI 測試 target 內部執行。

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

建議將整個 `.simpilot/`，或至少 `runs/` 與 `verify/`，加入專案的 `.gitignore`。

## 參考

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests、suites、devices、results 與 metadata 的完整 JSON 規格

## 已知限制

- 文字輸入預設寫入欄位的無障礙值（`set-text`），不需要鍵盤，任何文字系統都適用。按鍵層級的輸入（`type`）預設透過剪貼簿貼上；逐鍵直接 HID 輸入僅支援美式鍵盤配置
- **長期使用的 simulator 可能不再傳遞鍵盤 HID**（在 Xcode 27.0 beta 4 上實測）：貼上、逐鍵輸入與全選+刪除都會被忽略，而觸控輸入正常。這取決於裝置的使用時間而非 iOS 版本，`simctl erase` 與重新啟動都無法恢復，需要重新建立裝置。`type` 會偵測到這一點並直接失敗，而不是回報成功；`set-text` 不受影響
- Face ID / Touch ID、VoiceOver，以及 light/dark 之外的無障礙外觀項目需要 Xcode 27——它們透過 `xcrun devicectl` 實作，而 devicectl 只能作用於該版本以後的 simulator
- 對比度與文字裁切不在 `sipi a11y-audit` 的範圍內；兩者都需要對算繪後的影格做像素分析
- 僅支援 simulator，不支援實機

## Note

這個儲存庫主要由 AI 維護。歡迎提交 issue 與回饋，但不接受 pull request。如果你想依自己的流程調整，請 fork 後使用。

## 免責聲明

SimPilot 是一個開發工具。它透過 Apple 的**未公開私有框架**驅動 iOS 模擬器，而這些框架可能被 Apple 在任何 Xcode 或 macOS 更新中變更或移除，從而可能在沒有任何預告的情況下導致 SimPilot 無法運作。本工具與 Apple 並無關聯，也未獲得 Apple 認可，並非用於 App Store 或正式環境。本工具**以「現狀」提供，不附帶任何保證——使用風險由你自行承擔。**

## License

MIT © 2026 hmhv。請參閱 [LICENSE](LICENSE)。
