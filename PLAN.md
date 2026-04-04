# ClipBoard Manager 新規開発プラン

## Context

ClipyはmacOS用クリップボードマネージャとして優秀だが、2020年以降メンテナンスが停止。15個のCocoaPods依存、非推奨API多数、RxSwift 5→6の破壊的変更等により、改修より新規開発の方が合理的と判断。

ユーザーの要件：
- **Cmd+Shift+V** でクリップボード履歴 + スニペットビューアを開く
- ビューア上で **Emacs keybinding** によるカーソル移動（C-n/C-p/C-f/C-b 等）
- （将来）センシティブな値の管理（ペースト後に履歴から削除、明示的削除）

## 技術スタック

| 要素 | 選定 | 理由 |
|------|------|------|
| UI | **SwiftUI** | macOS 13+なら十分実用的。宣言的UIでメンテしやすい |
| データ永続化 | **SwiftData** | macOS 14+ 標準。Realmのような外部依存不要 |
| パッケージ管理 | **SPM** | CocoaPods不要。Xcode標準統合 |
| グローバルホットキー | **Carbon API (RegisterEventHotKey)** or **MASShortcut (SPM)** | 要調査。Carbon APIなら外部依存ゼロ |
| ペースト実行 | **CGEvent** | Clipyと同方式。Accessibility権限でCmd+Vをシミュレート |
| クリップボード監視 | **Timer + NSPasteboard.changeCount** | RxSwift不要。Combine or async/awaitで十分 |
| デプロイメントターゲット | **macOS 14 Sonoma** | SwiftData利用のため。2024年以降のmacOSをカバー |

## アーキテクチャ概要

```
App (SwiftUI App lifecycle, @main)
├── ClipboardMonitor     — NSPasteboard.changeCount ポーリング
├── DataStore            — SwiftData (ClipItem, Snippet, SnippetFolder)
├── HotKeyManager        — グローバルホットキー登録 (Cmd+Shift+V)
├── PasteEngine          — CGEvent で Cmd+V シミュレート
├── ViewerPanel          — NSPanel (フローティングウィンドウ)
│   ├── HistoryListView  — クリップボード履歴リスト
│   ├── SnippetListView  — スニペット一覧
│   └── EmacsKeyHandler  — Emacs keybinding 処理
└── SettingsView         — 設定画面
```

## フェーズ分け

### Phase 1: 最小動作版（MVP）
**ゴール**: Cmd+Shift+V で履歴一覧を表示し、選択してペーストできる

1. **プロジェクトセットアップ**
   - Xcode で新規 SwiftUI App (macOS 14+)
   - SPM プロジェクト構成
   - LSUIElement = true（メニューバーアプリ）
   - Info.plist に NSAccessibilityUsageDescription 追加

2. **ClipboardMonitor**
   - DispatchSourceTimer で **1ms間隔** で NSPasteboard.general.changeCount をポーリング
     - Clipyは750μsでポーリング。NSPasteboardは「現在値しか取れない」ため、遅いと取りこぼす
     - Timer.publishではなくDispatchSourceTimerを使い、専用のシリアルキューで実行
   - 変更検知時に NSPasteboard から全型のデータを即座にキャプチャ
   - SwiftData の ClipItem に保存
   - 自分自身のペーストによるchangeCount変化を無視する仕組み（incrementChangeCount相当）
   - Clipy参考: `ClipService.swift:30-51`（RxSwift版ポーリング）

3. **データモデル (SwiftData)**
   ```swift
   @Model class ClipItem {
       var title: String              // 表示用テキスト（先頭N文字）
       var primaryType: String        // 主要UTType識別子
       var availableTypes: [String]   // 全UTType識別子リスト
       // 型別データ（クリップボードは複数型を同時に持つため個別保持）
       var stringValue: String?       // プレーンテキスト
       var rtfData: Data?             // RTF
       var rtfdData: Data?            // RTFD
       var pdfData: Data?             // PDF
       var tiffData: Data?            // 画像 (TIFF)
       var fileURLs: [String]?        // ファイルURL
       var urlStrings: [String]?      // URL
       var createdAt: Date
       var isPinned: Bool
       var isSensitive: Bool          // 将来用: センシティブフラグ
   }
   
   @Model class SnippetFolder {
       var title: String
       var index: Int
       var snippets: [Snippet]
   }
   
   @Model class Snippet {
       var title: String
       var content: String
       var index: Int
       var folder: SnippetFolder?
   }
   ```
   
   **設計根拠**: Clipyの`CPYClipData`はNSKeyedArchiverで型別にシリアライズしている。
   新アプリではSwiftDataのプロパティとして直接保持し、ペースト時に元の全型を
   NSPasteboardに復元する。これにより、RTFをコピーした場合にリッチテキストとして
   貼り付けられる。

4. **HotKeyManager**
   - Carbon API `RegisterEventHotKey` でグローバルホットキー登録
   - Cmd+Shift+V → ViewerPanel 表示/非表示トグル
   - 依存ライブラリ不要（Carbon APIはmacOS標準）
   - Clipy参考: `HotKeyService.swift:112-120`

5. **ViewerPanel（NSPanel）**
   - NSPanel をフローティングウィンドウとして表示（キー入力を受け取れる）
   - SwiftUI の NSHostingView を埋め込み
   - 履歴リスト: ClipItem を時系列で表示
   - 選択 → PasteEngine → ペースト → パネル閉じる

6. **PasteEngine**
   - 選択されたClipItemの内容をNSPasteboardに書き込み
   - CGEvent で Cmd+V をシミュレート
   - Clipy参考: `PasteService.swift:142-165`

7. **Emacs Keybinding**
   - NSPanel の keyDown イベントをオーバーライド
   - C-n (↓), C-p (↑): リスト項目移動
   - C-f (→), C-b (←): タブ切り替え（履歴 ↔ スニペット）
   - C-a: 先頭へ、C-e: 末尾へ
   - Return: 選択してペースト
   - C-g / Escape: キャンセル（パネルを閉じる）

### Phase 2: スニペット機能
**ゴール**: スニペットの作成・編集・フォルダ管理・ペースト

1. **スニペット管理UI**
   - SwiftUI で SnippetEditor ウィンドウ
   - フォルダ → スニペットの2階層管理
   - ドラッグ&ドロップで並べ替え

2. **ViewerPanel にスニペットタブ追加**
   - C-f/C-b でタブ切り替え
   - スニペットもEmacs keybindingで操作可能

3. **Clipyスニペットのインポート**
   - Clipyが使用するXMLフォーマットを読み込み可能にする
   - Clipy参考: `CPYSnippetsEditorWindowController.swift:154-212`
   - XMLタグ: `<folders><folder><title/><snippets><snippet><title/><content/></snippet></snippets></folder></folders>`

### Phase 3: 品質向上・追加機能
**ゴール**: 実用レベルに引き上げる

1. **ステータスバーアイコン**
   - MenuBarExtra (SwiftUI) でステータスバー常駐
   - 設定へのアクセス

2. **センシティブ値対応**
   - ClipItem.isSensitive フラグ
   - ペースト後に自動削除オプション
   - 手動で「センシティブとしてマーク → 即削除」
   - メニューから明示的に削除

3. **ログイン時起動**
   - SMAppService.mainApp で登録（macOS 13+標準API）

4. **履歴管理**
   - 最大保存件数の設定
   - 古い履歴の自動削除
   - 全履歴クリア

5. **検索**
   - ViewerPanel で文字列検索（C-s でインクリメンタル検索）

## Clipyとの機能比較

| 機能 | Clipy | 新アプリ (MVP) | 新アプリ (将来) |
|------|-------|--------------|--------------|
| クリップボード履歴 | ○ | ○ | ○ |
| スニペット | ○ | Phase 2 | ○ |
| グローバルホットキー | ○ | ○ | ○ |
| Emacs keybinding | × | ○ | ○ |
| Dark Mode | × | ○（SwiftUI自動対応） | ○ |
| センシティブ値 | × | × | ○ |
| 画像履歴 | ○ | △（データモデルに含む） | ○ |
| ログイン時起動 | ○（旧API） | Phase 3 | ○（SMAppService） |
| 自動アップデート | ○（Sparkle） | × | 検討 |
| スニペットXMLインポート | ○ | Phase 2 | ○ |

## 外部依存

**Phase 1 時点: ゼロ**
- グローバルホットキー: Carbon API（macOS標準）
- ペースト: CGEvent（macOS標準）
- データ永続化: SwiftData（macOS標準）
- UI: SwiftUI（macOS標準）

Carbon API が使いにくい場合のみ、HotKey (SPM対応) パッケージを検討。

## 検証方法

### Phase 1 完了条件
- [ ] アプリ起動でステータスバーにアイコン表示（またはDockなし常駐）
- [ ] テキストをコピーすると履歴に追加される
- [ ] Cmd+Shift+V でビューアパネルが表示される
- [ ] C-n/C-p で項目を移動できる
- [ ] Return で選択項目がペーストされる
- [ ] C-g/Escape でパネルが閉じる
- [ ] Dark Mode で正常に表示される

### Phase 2 完了条件
- [ ] スニペットの作成・編集・削除ができる
- [ ] フォルダでスニペットを整理できる
- [ ] ビューアでスニペットを選択してペーストできる
- [ ] ClipyのXMLスニペットをインポートできる

※ 必須ゲート（動作検証・既存機能・差分確認・シークレット）は常に適用

## Done 判定基準
- [ ] Phase 1 完了条件を全て満たす
- [ ] macOS 14+ でビルド・実行できる
- [ ] 外部依存ゼロ（または最小限）
- [ ] Cmd+Shift+V → Emacs keybinding → ペーストのフローが動作する
※ 必須ゲート（動作検証・既存機能・差分確認・シークレット）は常に適用
