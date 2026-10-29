# SimPilot

翻訳: [English](README.md) | **日本語** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [Español](README.es.md) | [한국어](README.ko.md) | [Português do Brasil](README.pt-BR.md)

SimPilot は、Claude Code や Codex から自然言語で iOS Simulator を操作できるようにします。画面を読み、タップし、文字を入力し、折りたたみ、キャプチャし、アプリにファイルを入れ、アプリが保存した内容を読み返します。あわせて、その背後にある Xcode と simulator のツールチェーンのインストールと片付けも担います。結果の確かめ方はエージェントに任せています。エージェントはタスクに合ったやり方で画面を読み、キャプチャし、アプリのデータを読みます。

トップレベルの README のみ翻訳しています。skill docs とコードは英語のままです。

## できること

- **simulator を操作する**: `sipi` はアクセシビリティツリーを読み、ネイティブかつ headless で操作します。ラベルや id によるタップ、どの文字体系でも使えるテキスト入力、ジェスチャー、ハードウェアボタン、回転、iPhone Duo の折りたたみ、スクリーンショットと動画、Face ID / Touch ID、アクセシビリティ表示設定、メモリ警告に対応します。
- **アプリのデータを扱う**: アプリのデータコンテナ、App Group、Files.app にファイルを入れます。アプリが保存した内容を text・JSON・plist・SQLite として確認し、コンテナのスナップショットを取って差分を見て、アプリのクラッシュレポートを集めます。
- **Xcode と simulator ランタイムを管理する**: `sipi xcode list / install / uninstall` で Xcode の一覧・インストール・削除を、`sipi runtime list` で Apple が出している simulator ランタイムの一覧を扱います。ランタイムとデバイスの追加・削除は、skill に書かれているとおり `xcodebuild` と `simctl` で行います。
- **片付ける**: Xcode と simulator が残したもの（DerivedData、device support ファイル、プレビュー用・テスト用のデバイス、使えなくなったランタイム、古い Xcode）を見つけて削除します。承認なしには何も削除せず、ファイルはゴミ箱に移します。

## 前提条件

- Xcode 27.2 以降
- macOS 26.6 以降
- [Claude Code](https://claude.com/claude-code) または Codex

## インストール

SimPilot は skill を埋め込んだ単一の `sipi` バイナリとして配布されます。次の 1 コマンドでインストールできます。

```bash
curl -fsSL https://raw.githubusercontent.com/hmhv/SimPilot/main/install.sh | bash
```

インストーラーはビルド済みの `sipi` バイナリをダウンロードし、`sipi` が埋め込みの `sipi-common` skill を次の場所に登録します。

- Claude Code (`~/.claude/skills/`)
- Codex (`~/.agents/skills/`)

simulator の capability は `sipi doctor` で確認してください。

更新と削除:

```bash
sipi update      # GitHub Releases から最新の sipi をダウンロードし、skill を更新
sipi uninstall   # skill、インストール metadata、sipi バイナリを削除
```

2.x から更新すると、`sipi-test` と `sipi-verify` の skill は削除されます。アプリのリポジトリにある `.simpilot/tests/`・`suites/`・`devices/`・`runs/`・`verify/` と、`config.json` の `app`・`build` 以外のキーはもう使われません。不要になったら削除してください。

## クイックスタート

iOS アプリのプロジェクト内で使います。

- Claude Code: `/sipi-common` に続けて依頼を書くか、そのまま頼む
- Codex: `Use the sipi-common skill to ...` のように skill を指定する

```text
/sipi-common アプリをビルドして、新しいログインフローが simulator で動くか確認して
/sipi-common 設定を開いて通知をオンにして
/sipi-common sample.pdf をアプリの Inbox に入れて、取り込み画面を確認して
/sipi-common サインイン後にアプリが保存した内容を見せて
/sipi-common Xcode 27.2 と iOS 27.2 ランタイムを入れて
/sipi-common Xcode のディスク使用量を片付けて
```

初回利用時には、SimPilot がプロジェクトを検出し、`.simpilot/config.json` を作成して simulator の準備を行います。

## simulator を直接操作する

`sipi` は、エージェントが 1 ステップずつ呼ぶ素の CLI です。`describe-ui --format compact` はアクセシビリティツリーを 1 要素 1 行（種類・ラベル・id・値・frame・タップ座標）で出力し、JSON の数分の一のサイズで済みます。`wait-for` は sleep の代わりに、ラベル・id・値・テキストが現れる（または消える）までポーリングします。`screenshot --max-pixel 600` は目で確認するのに十分な小さいキャプチャを返します。`memory-warning` は Simulator.app の Debug メニューにあったメモリ警告を送ります（Xcode 27 以降）。`fold-state` は iPhone Duo の 2 画面のうちどちらが点いているかを報告し、`fold --closed|--open|--angle` で折りたたみます（simctl にも devicectl にもできません）。`--display inner|cover` で消灯側の画面をキャプチャします。全コマンドは `sipi --help` を参照してください。

`sipi a11y-audit` は、起動済みの任意の simulator で今の画面を検査します。小さすぎるタップ領域、ラベルのないコントロール、紛らわしい重複ラベル、意味のないラベル、切り詰められたテキストを検出します。Xcode 自身のアクセシビリティ監査は UI テストターゲットの中からしか実行できません。

アプリのデータを扱うコマンドは [App data and evidence commands](docs/data-artifacts.md) で説明しています。

## Xcode と simulator ランタイム

```bash
sipi xcode install 27B48
```

`sipi xcode list`（[xcodereleases.com](https://xcodereleases.com) の一覧）に載っているビルド番号を渡します。developer.apple.com のウィンドウが開くので、そこでサインインすると自動で閉じます。セッションはその実行中のメモリ上にだけ置かれ、何も保存されません。アプリは `/Applications/Xcode-<version>.app`（例: `Xcode-27.2.0-release.candidate.app`）としてインストールされます。選択には root 権限が必要なため、`sipi` は自分で実行する `sudo xcode-select -s …` と `sudo xcodebuild -runFirstLaunch` のコマンドを表示します。

`sipi runtime list` は、Apple が出している simulator ランタイムを、入っているものに印を付けて一覧表示します（`xcodebuild` にも `simctl` にもこの一覧はありません）。入れるのは `xcodebuild -downloadPlatform iOS -buildVersion <版> -architectureVariant arm64`、消すのは `xcrun simctl runtime delete`、デバイスを作るのは `xcrun simctl create` です。skill はこれらを把握しており、代わりに実行します。

## プロジェクト内のファイル

SimPilot はプロジェクト内に 2 つのファイルを置きます。

```text
.simpilot/
  config.json   # bundle ID とアプリのビルド方法
  notes.md      # skill が記録するアプリ固有の操作のコツ
```

どちらもコミットしておくことを勧めます。チームメイトや別のエージェントが恩恵を受けます。

## 既知の制限

- テキスト入力は既定でフィールドのアクセシビリティ値を書き込む方式（`set-text`）を使います。キーボードが不要で、どの文字体系でも入力できます。キー入力レベルの入力（`type`）は既定で clipboard（paste）を経由し、直接の HID キー入力は US キーボード配列のみ対応です。ゲスト側で別の配列が有効な場合は誤った文字が入力されます
- **長く使った simulator はキーボード HID を受け付けなくなることがあります**（Xcode 27.0 beta 6 で計測）。paste、キー単位の入力、select-all+delete はいずれも無視され、タッチ入力は動作します。これは iOS のバージョンではなくデバイスの使用期間に依存し、`simctl erase` でも再起動でも回復しません。`type` はこの状態を検出し、成功と報告せずに失敗します。`set-text` は影響を受けません。`type --xcode-mcp` は代わりに Xcode 27 のサービス経由で入力し、計測したデバイスではそれで成功しました。ただし代償があります（後述）
- アクセシビリティツリー上は存在するのに実際には触れない要素へのタップは、成功と報告されます。`describe-point` もその要素を返すため、この違いはどの層でも判別できません。Xcode 自身のツールも同じ挙動です
- コントラスト比と、省略記号なしでコンテナに切られて見えなくなった文字は `sipi a11y-audit` の対象外です。どちらも描画されたフレームのピクセル解析が必要です
- **iPhone Duo**（Xcode 27.2 で計測）: タップ・スワイプ・文字入力・ハードウェアボタンは両方の画面に届きます。内側画面はアクセシビリティの hit-test に何も返さないため、セレクタ指定のタップは要素の位置へ確認なしで送られ、`set-text` / `describe-point` はカバー画面でだけ使えます。Device Hub を開いている間は入力が Device Hub に取られ、内側画面のタップは捨てられ、シミュレーターのペーストボードが Mac のクリップボードで上書きされるため `type` は貼り付けを拒否します。`sipi doctor` がこの状態を報告し、`sipi repair-input` で入力を戻せます。Duo simulator をスクリプトから回転させる手段はなく、Device Hub の回転ボタンを使います
- simulator のみ対応で、実機はサポートしていません

## キー入力を受け付けなくなった simulator への入力

simulator は、SimPilot が送るキーボードイベントを無視する状態になることがあります。タッチは動き続け、paste・キー単位の入力・select-all+delete だけが効かなくなります。SimPilot は正常なデバイスと同一のイベントを送っているため、SimPilot 側に直せる箇所はありません。一方 Xcode 27 のデバイス操作サービスは別経路で入力し、測定したこの状態のデバイスでは通りました（さらに使い込まれたデバイスでは、この経路も無視されました）。さらにこの経路はゲスト側のキーボード配列にも依存しません。

`sipi type --xcode-mcp` でこの経路を選びます。SimPilot が勝手にこの経路を使うことはありません。iOS 27 では、このセッションを1回行うと、そのデバイスで以後起動した App のアクセシビリティツリーがデバイス再起動（`simctl shutdown` + `boot`）まで空になるためです。最後に使うか、次の起動の前に再起動してください。これ以外の SimPilot の機能はすべてこの設定なしで動作し、`set-text` はそもそもキーボードを必要としません。

利用には次の3つが必要です。

```bash
xcode-select -p                    # Xcode 27.2 以降
sudo xcrun mcp-server enable       # headless モードを有効化
sipi xcode-mcp --approve <.xcodeproj または .xcworkspace のパス>
```

プロジェクトは Xcode の承認ダイアログを出すためだけに開き、すぐ閉じます。設定後、サービスが停止していれば sipi が起動します。Xcode は承認をバイナリ単位で紐付けるため、`sipi update` や再ビルドのたびに承認手順が必要です。現在の状態（同じパスにある以前のビルドの承認も含む）は `sipi xcode-mcp` で、この経路が使えるかどうかは `sipi doctor` で確認できます。

`--clear` はこの経路では使えません。select-all と delete もキー入力であり、このサービスは入力はできてもフィールドを空にはできないためです。値を置き換えたい場合は `sipi set-text` を使ってください。

代償の原因は入力ではなくセッションそのものです。Xcode 27.2 でタップ 1 回だけのセッションで再計測しても、以後起動した App のアクセシビリティツリーはデバイス再起動まで空になりました。

## Note

このリポジトリは主に AI によって管理されています。Issue やフィードバックは歓迎しますが、pull request は受け付けていません。必要なら fork して自分用に調整してください。

## 免責事項

SimPilot は開発用ツールです。Apple の**ドキュメント化されていないプライベートフレームワーク**を通じて iOS シミュレーターを操作しており、これらは Xcode や macOS のアップデートで Apple によって変更・削除される可能性があり、予告なく SimPilot が動作しなくなることがあります。本ツールは Apple と提携・承認された関係になく、App Store や本番環境での利用を意図したものではありません。本ツールは**現状有姿（as-is）で無保証にて提供されます。利用は自己責任でお願いします。**

## License

MIT © 2026 hmhv. 詳細は [LICENSE](LICENSE) を参照してください。
