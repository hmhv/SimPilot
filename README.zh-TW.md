# SimPilot

翻譯: [English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot 讓 Claude Code 或 Codex 透過自然語言驅動 iOS Simulator——讀取畫面、點按、輸入文字、摺疊、擷取畫面、把檔案放進 app 並讀回 app 儲存的內容——同時讓背後的 Xcode 與 simulator 工具鏈保持安裝妥當且乾淨。如何確認結果則交給 agent 決定：它會讀取畫面、擷取畫面，並以最適合該任務的方式讀取 app 的資料。

目前只翻譯最上層 README。skill docs 與程式碼仍維持英文。

## 功能

- **驅動 simulator**：`sipi` 以原生、headless 的方式讀取無障礙樹並據以操作：依標籤或 id 點按、任何文字系統的文字輸入、手勢、硬體按鈕、旋轉、摺疊 iPhone Duo、截圖與錄影、Face ID / Touch ID、無障礙外觀設定，以及記憶體警告。
- **處理 app 資料**：把檔案放進 app 的資料容器、App Group 或 Files.app；以文字、JSON、plist 或 SQLite 檢視 app 儲存的內容；為容器建立快照並比較差異；收集 app 的當機報告。
- **管理 Xcode 與 simulator runtimes**：`sipi xcode list / install / uninstall` 用來查看、安裝與移除 Xcode，`sipi runtime list` 顯示 Apple 提供的 simulator runtimes；runtimes 與裝置的安裝與移除依 skill 的說明透過 `xcodebuild` 與 `simctl` 進行。
- **清理**：找出並移除 Xcode 與 simulator 留下的東西：DerivedData、device support 檔案、preview 與測試用裝置、無法使用的 runtimes、舊版 Xcode。未經同意不會移除任何東西，檔案會移到垃圾桶。

## 前置需求

- Xcode 27.2 或以上
- macOS 26.6 或以上
- [Claude Code](https://claude.com/claude-code) 或 Codex

## 安裝

SimPilot 以內嵌 skill 的單一 `sipi` 二進位檔發佈。一行指令即可安裝:

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

安裝程式會下載預先建置的 `sipi` 二進位檔，接著 `sipi` 會將內嵌的 `sipi-common` skill 安裝到:

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

執行 `sipi doctor` 驗證模擬器能力。

更新與解除安裝:

```bash
sipi update      # 從 GitHub Releases 下載最新的 sipi 並更新 skill
sipi uninstall   # 移除 skill、安裝中繼資料與 sipi 二進位檔
```

從 2.x 更新時會移除 `sipi-test` 與 `sipi-verify` skills。App 儲存庫中的 `.simpilot/tests/`、`suites/`、`devices/`、`runs/`、`verify/`，以及 `config.json` 中 `app`、`build` 以外的鍵都不再使用，不需要時請刪除。

## 快速開始

在你的 iOS app 專案中使用:

- Claude Code: 輸入 `/sipi-common` 再接上請求，或直接提出請求
- Codex: 提到 skill，例如 `Use the sipi-common skill to ...`

```text
/sipi-common 建置 App，並在 simulator 上檢查新的登入流程是否正常
/sipi-common 打開設定並開啟通知
/sipi-common 把 sample.pdf 放進 App 的 Inbox，並檢查匯入畫面
/sipi-common 顯示登入後 App 儲存的內容
/sipi-common 安裝 Xcode 27.2 與 iOS 27.2 runtime
/sipi-common 清理 Xcode 佔用的磁碟空間
```

第一次使用時，SimPilot 會偵測你的專案、建立 `.simpilot/config.json`，並準備 simulator。

## 直接驅動 simulator

`sipi` 是一個可由 agent 逐步呼叫的一般 CLI。`describe-ui --format compact` 以每個元素一行（類型、標籤、id、值、frame、點擊座標）輸出無障礙樹，大小只有 JSON 的幾分之一；`wait-for` 會輪詢直到某個標籤、id、值或文字出現（或消失），取代 sleep；`screenshot --max-pixel 600` 回傳足夠小、便於查看的截圖；`memory-warning` 送出 Simulator.app Debug 選單曾提供的記憶體警告（Xcode 27 以上）；`fold-state` 回報 iPhone Duo 的兩塊螢幕中哪一塊是亮著的，`fold --closed|--open|--angle` 可以真正摺疊／展開它（simctl 與 devicectl 都做不到），`--display inner|cover` 可擷取熄滅的那一塊。完整命令見 `sipi --help`。

`sipi a11y-audit` 會針對任何已啟動的 simulator 檢查目前畫面——過小的點按目標、缺少標籤的控制項、有歧義的重複標籤、無意義的標籤、被截斷的文字。Xcode 自身的無障礙稽核只能在 UI 測試 target 內部執行。

app 資料相關命令的說明見 [App data and evidence commands](docs/data-artifacts.md)。

## Xcode 與 simulator runtimes

```bash
sipi xcode install 27B48
```

傳入 `sipi xcode list`（來自 [xcodereleases.com](https://xcodereleases.com)）列出的 build 編號。會開啟一個 developer.apple.com 的視窗；在那裡登入後，視窗會自動關閉。登入工作階段只在該次執行期間存在於記憶體中，不會儲存任何東西。app 會安裝為 `/Applications/Xcode-<version>.app`（例如 `Xcode-27.2.0-release.candidate.app`）。選用它需要 root 權限，因此 `sipi` 會印出 `sudo xcode-select -s …` 與 `sudo xcodebuild -runFirstLaunch` 命令，請自行執行。

`sipi runtime list` 列出 Apple 提供的 simulator runtimes，並標出已安裝的（`xcodebuild` 與 `simctl` 都無法列出）。安裝用 `xcodebuild -downloadPlatform iOS -buildVersion <版本> -architectureVariant arm64`，移除用 `xcrun simctl runtime delete`，建立裝置用 `xcrun simctl create`。skill 了解這些命令並會代你執行。

## 專案檔案

SimPilot 會在你的專案中保留兩個檔案:

```text
.simpilot/
  config.json   # bundle ID 與 App 的建置方式
  notes.md      # skill 記錄的 App 專屬操作技巧
```

兩者都值得提交到版本控制：隊友或其他 agent 都能從中受益。

## 已知限制

- 文字輸入預設寫入欄位的無障礙值（`set-text`），不需要鍵盤，任何文字系統都適用。按鍵層級的輸入（`type`）預設透過剪貼簿貼上；逐鍵直接 HID 輸入僅支援美式鍵盤配置，若客體端啟用的是其他配置則會輸入錯誤的字元
- **長期使用的 simulator 可能不再接受鍵盤 HID**（在 Xcode 27.0 beta 6 上實測）：貼上、逐鍵輸入與全選+刪除都會被忽略，而觸控輸入正常。這取決於裝置的使用時間而非 iOS 版本，`simctl erase` 與重新啟動都無法恢復。`type` 會偵測到這一點並直接失敗，而不是回報成功；`set-text` 不受影響。`type --xcode-mcp` 會改由 Xcode 27 內建的服務輸入，在實測的裝置上由此成功，但有代價（見下文）
- 無障礙樹宣稱存在、但實際無法觸控的元素，點擊後仍會回報成功。`describe-point` 也會回傳該元素，因此任何一層都無法分辨；Xcode 自身的工具也是相同行為
- 對比度與文字裁切不在 `sipi a11y-audit` 的範圍內；兩者都需要對算繪後的影格做像素分析
- **iPhone Duo**（在 Xcode 27.2 上實測）：點擊、滑動、文字輸入和硬體按鈕都能到達兩塊螢幕。內螢幕對無障礙 hit-test 不回傳任何結果，因此依選擇器的點擊會不經確認地送到元素的位置，`set-text` / `describe-point` 只能在外螢幕使用。Device Hub 開啟期間會接管裝置的輸入：內螢幕的點擊被丟棄，模擬器的剪貼板被 Mac 的剪貼簿覆蓋，因此 `type` 會拒絕貼上。`sipi doctor` 會回報這種狀態，`sipi repair-input` 可恢復輸入。無法透過腳本旋轉 Duo simulator，請使用 Device Hub 的旋轉按鈕
- 僅支援 simulator，不支援實機

## 對不再接受按鍵輸入的 simulator 輸入文字

simulator 可能進入忽略 SimPilot 注入之鍵盤事件的狀態：觸控仍可運作，而貼上、逐鍵輸入與全選+刪除都失效。SimPilot 在正常裝置與該狀態的裝置上送出的是完全相同的事件，因此 SimPilot 這一側沒有可修正之處。而 Xcode 27 內建的裝置互動服務走的是另一條路徑，實測時該狀態的裝置仍會接受（磨損更嚴重的裝置連這條路徑也會忽略），且這條路徑也不依賴客體端的鍵盤配置。

`sipi type --xcode-mcp` 選擇該路徑。SimPilot 絕不會自行使用它：在 iOS 27 上，一次這樣的工作階段會讓該裝置之後啟動的所有 App 的無障礙樹為空，直到裝置重新啟動（`simctl shutdown` + `boot`）。請把它放在最後使用，或在下一次啟動前重新啟動裝置。SimPilot 的其他功能都不需要這項設定，`set-text` 本來就不需要鍵盤。

需要滿足三個條件：

```bash
xcode-select -p                    # Xcode 27.2 或更新版本
sudo xcrun mcp-server enable       # 開啟 headless 模式
sipi xcode-mcp --approve <.xcodeproj 或 .xcworkspace 的路徑>
```

開啟該專案只是為了叫出 Xcode 的授權對話框，之後會立即關閉。設定完成後，若服務尚未執行，sipi 會將其啟動。Xcode 將授權綁定到特定的二進位檔，因此每次 `sipi update` 或重新建置後都需要再次執行授權步驟。目前狀態（包括同一路徑上舊建置的授權）可用 `sipi xcode-mcp` 查看，該路徑是否可用可用 `sipi doctor` 確認。

`--clear` 無法使用該路徑：全選與刪除同樣是按鍵輸入，而該服務只能輸入文字、無法清空欄位。需要整體取代值時請使用 `sipi set-text`。

代價來自工作階段本身而非輸入：在 Xcode 27.2 上僅用一次點擊的工作階段重新測量，之後啟動的 App 的無障礙樹在裝置重新啟動前都是空的。


## Note

這個儲存庫主要由 AI 維護。歡迎提交 issue 與回饋，但不接受 pull request。如果你想依自己的流程調整，請 fork 後使用。

## 免責聲明

SimPilot 是一個開發工具。它透過 Apple 的**未公開私有框架**驅動 iOS 模擬器，而這些框架可能被 Apple 在任何 Xcode 或 macOS 更新中變更或移除，從而可能在沒有任何預告的情況下導致 SimPilot 無法運作。本工具與 Apple 並無關聯，也未獲得 Apple 認可，並非用於 App Store 或正式環境。本工具**以「現狀」提供，不附帶任何保證——使用風險由你自行承擔。**

## License

MIT © 2026 hmhv。請參閱 [LICENSE](LICENSE)。
