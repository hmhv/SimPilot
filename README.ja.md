# SimPilot

翻訳: [English](README.md) | **日本語** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot は、Claude Code や Codex から自然言語で使える、iOS Simulator 向けのテスト・検証用エージェントスキル集です。

トップレベルの README のみ翻訳しています。skill docs とコードは英語のままです。

## できること

- **`/sipi-test`**: iOS Simulator 上での UI テスト自動化。自然言語からテストを定義し、操作と検証を自動化します。回帰テスト、複数デバイス実行、品質監査（アクセシビリティ、ローカライズ、表示確認）に対応します。
- **`/sipi-verify`**: 実装後の検証。機能追加や修正後に、その変更が正しく動作し見た目も問題ないかを確認します。

結果は `.simpilot/` に保存され、HTML レポートをブラウザで確認できます。

## 前提条件

- macOS 15 以降
- Xcode 26 以降
- [AXe](https://github.com/cameroncooke/AXe) CLI
  - `brew install cameroncooke/axe/axe`
  - `axe init`
- [Claude Code](https://claude.com/claude-code) または Codex

SimPilot の simulator automation は、エージェント環境に `axe` skill がある前提です。

## インストール

```bash
git clone https://github.com/hmhv/SimPilot.git
cd SimPilot
make install
```

`make install` では次を行います。

- SimPilot skills を Claude Code に登録 (`~/.claude/skills/`)
- SimPilot skills を Codex に登録 (`~/.agents/skills/`)

更新と削除:

```bash
make update
make uninstall
```

## クイックスタート

iOS アプリのプロジェクト内で使います。

- Claude Code: `/sipi-test` のようなスラッシュコマンドで使う
- Codex: `Use the sipi-test skill to ...` のように自然に skill を指定する

**テスト:**
```text
/sipi-test ホームと設定タブを切り替えるテストを作成して
Use the sipi-test skill to create a test for switching between the home and settings tabs
```

初回利用時には、SimPilot がプロジェクトを検出し、`.simpilot/config.json` を作成して simulator の準備を行います。

**検証:**
```text
/sipi-verify 新しいログインフローが simulator 上で正しく動くか確認して
Use the sipi-verify skill to verify the dark mode fix looks correct
```

## よく使う操作

**テスト作成:**
```text
/sipi-test ホーム画面のタブ切り替えテストを作成して
/sipi-test ログインして設定を開くテストを作成して
/sipi-test 今の画面からテストを作成して
```

**テスト実行:**
```text
/sipi-test settings-navigation テストを実行して
/sipi-test regression スイートを実行して
/sipi-test smoke タグのテストを実行して
/sipi-test iPhone 16 Pro で regression スイートを実行して
/sipi-test iPhone 16 と iPhone 15 でテストを実行して
/sipi-test regression-profile デバイスセットでテストを実行して
```

複数デバイスを指定した場合、テストは並列実行されます。`.simpilot/config.json` に `build` エントリがある場合は、実行前にアプリをビルドします。

**結果確認:**
```text
/sipi-test 最新の結果を表示して
/sipi-test settings-toggle テストの失敗詳細を表示して
/sipi-test 失敗した全テストの詳細を表示して
/sipi-test HTML レポートを開いて
```

各 run では run ディレクトリ内に `report.html` が生成されます。結果は `.simpilot/runs/` に保存されます。

**スイート管理:**
```text
/sipi-test すべてのテストを表示して
/sipi-test smoke タグのテストを表示して
/sipi-test app-launch、settings-toggle、tab-navigation で regression スイートを作成して
```

**品質監査:**
```text
/sipi-test onboarding と settings 画面をアクセシビリティ監査して
/sipi-test アクセシビリティラベルや identifier の不足を確認して
/sipi-test English、日本語、Deutsch で onboarding の翻訳抜けを確認して
/sipi-test 未翻訳テキストや文字切れを確認して
/sipi-test profile 画面を Light と Dark で比較して
/sipi-test 大きな Dynamic Type サイズで settings フローを確認して
```

## ワークスペース構成

SimPilot は `.simpilot/` 配下に次の構成を使います。

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

`.simpilot/` 全体、または少なくとも `runs/` と `verify/` はプロジェクトの `.gitignore` に追加することを勧めます。

## 参照

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests、suites、devices、results、metadata の完全な JSON 仕様

## 既知の制限

- パスワード入力では `axe type` は使えず、テキスト入力は clipboard を使います
- `axe type` は US キーボード配列前提です
- drag and drop、pinch、rotation は再現できません
- PhotosPicker のような system UI は `describe-ui` からは見えません

## Note

このリポジトリは主に AI によって管理されています。Issue やフィードバックは歓迎しますが、pull request は受け付けていません。必要なら fork して自分用に調整してください。

## License

[LICENSE](LICENSE) を参照してください。
