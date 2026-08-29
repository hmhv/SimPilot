# SimPilot

翻訳: [English](README.md) | **日本語** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot は、Claude Code や Codex から自然言語で使える、iOS Simulator 向けのテスト・検証用エージェントスキル集です。

トップレベルの README のみ翻訳しています。skill docs とコードは英語のままです。

## できること

- **`/sipi-test`**: iOS Simulator 上での UI テストと異常系テストの自動化。skill が自然言語の意図を明示的な v2 JSON 仕様に変換し、`sipi run-test` / `sipi run-suite` が決定論的な harness で実行します。保存したテストでは、権限、deep link、push 通知、位置情報、外観、Dynamic Type、Increase Contrast、Face ID / Touch ID、より広いアクセシビリティ表示設定、起動環境、明示的に設定した network-condition provider を制御できます。
- **`/sipi-verify`**: 実装後の検証。機能追加や修正後に、その変更が正しく動作し見た目も問題ないかを確認します。

結果は `.simpilot/` に保存され、HTML レポートをブラウザで確認できます。

## 前提条件

- macOS 15 以降
- Xcode 26 以降: Simulator を操作するために**実行時**に必要です（SimPilot は Xcode の private Simulator frameworks を読み込みます）。インストール時には不要です。Xcode 27 以降ではさらに Face ID / Touch ID、アクセシビリティ表示設定が使えます。これらは `xcrun devicectl` を経由します。また、キーボード入力のフォールバックとしても使えます（[キー入力を受け付けなくなった simulator への入力](#キー入力を受け付けなくなった-simulator-への入力)を参照）。
- [Claude Code](https://claude.com/claude-code) または Codex

## インストール

SimPilot は skills を埋め込んだ単一の `sipi` バイナリとして配布されます。次の 1 コマンドでインストールできます。

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

インストーラーはビルド済みの `sipi` バイナリをダウンロードし、`sipi` が埋め込みの `sipi-common` / `sipi-test` / `sipi-verify` skills を次の場所に登録します。

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

simulator の capability は `sipi doctor` で確認してください。

更新と削除:

```bash
sipi update      # GitHub Releases から最新の sipi をダウンロードし、skills を更新
sipi uninstall   # skills、インストール metadata、sipi バイナリを削除
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
/sipi-test 明るさスライダーを80%に設定して通知をトグルするテストを作成して
/sipi-test 今の画面からテストを作成して
```

保存したテストは、タップやスワイプだけでなく、タップ・ダブルタップ・トグル・スライダー・ジェスチャー・ドラッグ・長押し・ピンチや生のマルチタッチ・キー操作・回転まで決定論的なステップとして実行します。

さらに、権限の拒否、deep link、push 配信、座標のシミュレート、Face ID / Touch ID の一致と不一致、アクセシビリティ表示設定の全体（視差効果を減らす、透明度を下げる、カラーフィルタ、Liquid Glass の不透明度）、provider を使ったオフライン／遅延プロファイルなど、Simulator が制御する実際のエラー前提条件も作成できます。SimPilot は独自のネットワークコンディショナーを同梱も模倣もしていません。network profile を使う前に `sipi network-condition status` を確認してください。

検証はテキストの一致にとどまりません。`contains` / `absent` や正規表現に加えて、ステップは要素そのものについてもアサートできます。コントロールが無効になっていること、リストがちょうど 5 行であること、値がパターンに一致すること、タップ領域が 44pt を満たしていることなどです。

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
/sipi-test 視差効果を減らすとカラーフィルタを有効にしてこの画面を監査して
```

`sipi a11y-audit` は、その機械的にチェックできる部分を、起動済みの任意の simulator に対してコマンドラインから実行します。小さすぎるタップ領域、ラベルのないコントロール、紛らわしい重複ラベル、意味のないラベル、切り詰められたテキストを検出し、error 深刻度の指摘があれば非ゼロで終了するため、CI のゲートに使えます。Xcode 自身のアクセシビリティ監査は UI テストターゲットの中からしか実行できません。

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

`.simpilot/` 全体、または少なくとも `runs/` と `verify/` はプロジェクトの `.gitignore` に追加することを勧めます。

## 参照

- **[JSON-REFERENCE.md](.claude/skills/sipi-test/references/json-reference.md)**: tests、suites、devices、results、metadata の完全な JSON 仕様

## 既知の制限

- テキスト入力は既定でフィールドのアクセシビリティ値を書き込む方式（`set-text`）を使います。キーボードが不要で、どの文字体系でも入力できます。キー入力レベルの入力（`type`）は既定で clipboard（paste）を経由し、直接の HID キー入力は US キーボード配列のみ対応です。ゲスト側で別の配列が有効な場合は誤った文字が入力されます
- **長く使った simulator はキーボード HID を受け付けなくなることがあります**（Xcode 27.0 beta 6 で計測）。paste、キー単位の入力、select-all+delete はいずれも無視され、タッチ入力は動作します。これは iOS のバージョンではなくデバイスの使用期間に依存し、`simctl erase` でも再起動でも回復しません。`type` はこの状態を検出し、成功と報告せずに失敗します。`set-text` は影響を受けません。Xcode 27 のサービスを有効にしてあれば `type` はそちら経由で再試行して成功します（後述）
- アクセシビリティツリー上は存在するのに実際には触れない要素へのタップは、成功と報告されます。`describe-point` もその要素を返すため、この違いはどの層でも判別できません。Xcode 自身のツールも同じ挙動です
- Face ID / Touch ID、light/dark を超えるアクセシビリティ表示設定には Xcode 27 が必要です。これらは `xcrun devicectl` を経由し、devicectl はそのリリース以降の simulator しか対象にできません
- コントラスト比と文字切れは `sipi a11y-audit` の対象外です。どちらも描画されたフレームのピクセル解析が必要です
- simulator のみ対応で、実機はサポートしていません

## キー入力を受け付けなくなった simulator への入力

simulator は、SimPilot が送るキーボードイベントを無視する状態になることがあります。タッチは動き続け、paste・キー単位の入力・select-all+delete だけが効かなくなります。SimPilot は正常なデバイスと同一のイベントを送っているため、SimPilot 側に直せる箇所はありません。一方 Xcode 27 のデバイス操作サービスは別経路で入力するため、この状態のデバイスでも通ります。さらにこの経路はゲスト側のキーボード配列にも依存しません。

`sipi type` はこれをフォールバックとして使います。自前のキー入力が届かなかったことを検出すると、ステップを失敗させる代わりに Xcode のサービス経由で再試行します。`--xcode-mcp` を付けると最初からその経路を使います。これ以外の SimPilot の機能はすべてこの設定なしで動作し、`set-text` はそもそもキーボードを必要としません。

利用には次の3つが必要です。

```bash
xcode-select -p                    # Xcode 27 以降
sudo xcrun mcp-server enable       # headless モードを有効化
sipi xcode-mcp --approve <.xcodeproj または .xcworkspace のパス>
```

プロジェクトは Xcode の承認ダイアログを出すためだけに開き、すぐ閉じます。設定後、フォールバックが発動した際にサービスが停止していれば sipi が起動します。Xcode は承認をバイナリ単位で紐付けるため、`sipi update` や再ビルドのたびに承認手順が必要です。現在の状態は `sipi xcode-mcp` で、フォールバックが使えるかどうかは `sipi doctor` で確認できます。

`--clear` はこの経路では使えません。select-all と delete もキー入力であり、このサービスは入力はできてもフィールドを空にはできないためです。値を置き換えたい場合は `sipi set-text` を使ってください。

## Note

このリポジトリは主に AI によって管理されています。Issue やフィードバックは歓迎しますが、pull request は受け付けていません。必要なら fork して自分用に調整してください。

## 免責事項

SimPilot は開発用ツールです。Apple の**ドキュメント化されていないプライベートフレームワーク**を通じて iOS シミュレーターを操作しており、これらは Xcode や macOS のアップデートで Apple によって変更・削除される可能性があり、予告なく SimPilot が動作しなくなることがあります。本ツールは Apple と提携・承認された関係になく、App Store や本番環境での利用を意図したものではありません。本ツールは**現状有姿（as-is）で無保証にて提供されます。利用は自己責任でお願いします。**

## License

MIT © 2026 hmhv. 詳細は [LICENSE](LICENSE) を参照してください。
