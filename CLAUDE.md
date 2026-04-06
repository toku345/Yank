# CLAUDE.md

## Project Overview

Yank は macOS 14+ 向けのクリップボードマネージャ。Clipy の後継として、SwiftUI + SwiftData + Carbon API で外部依存ゼロで構築する。

## 要件

- **Cmd+Shift+V** でクリップボード履歴 + スニペットビューアを開く
- ビューア上で **Emacs keybinding** によるカーソル移動（C-n/C-p/C-f/C-b 等）
- （将来）センシティブな値の管理

## 技術スタック

- **UI**: SwiftUI（macOS 14+）
- **データ永続化**: SwiftData
- **グローバルホットキー**: Carbon API (RegisterEventHotKey)
- **ペースト実行**: CGEvent (Cmd+V シミュレート)
- **クリップボード監視**: main RunLoop Timer + NSPasteboard.changeCount（250ms間隔ポーリング）
- **パッケージ管理**: SPM（外部依存ゼロが目標）
- **プロジェクト生成**: xcodegen (project.yml → .xcodeproj)
- **デプロイメントターゲット**: macOS 14 Sonoma

## 実装方針

- PLAN.md に全体計画あり。Phase 1（MVP）から着手。
- `.xcodeproj` は xcodegen で生成。`project.yml` をソース管理し、`.xcodeproj` は .gitignore に入れる。
- 外部依存はゼロを維持。Carbon API が使いにくい場合のみ HotKey (SPM) を検討。
- ソースコード内のコメントは英語で記述する。
- `nonisolated(unsafe)` を使わず、スレッド間共有には `OSAllocatedUnfairLock` を使う。
- main RunLoop Timer から `@MainActor` メソッドを呼ぶ場合は `MainActor.assumeIsolated` を使う。
- Carbon API callback に `self` を渡す場合は `Unmanaged.passRetained` を使い、全失敗パスで `release` をバランスさせる。`applicationWillTerminate` で deterministic cleanup を保証する。
- `os.log` でクリップボード由来の文字列を出力する場合は `privacy: .private` を使う。`privacy: .public` はタイプ名やステータス等の非機密情報に限定する。
- コミット前に `swiftlint lint --strict` を実行し、violation がゼロであることを確認する。

## ビルド・テスト

```bash
# プロジェクト生成
xcodegen generate

# ビルド
xcodebuild -project Yank.xcodeproj -scheme Yank -configuration Debug build

# テスト
xcodebuild -project Yank.xcodeproj -scheme Yank test

# Lint
swiftlint lint --strict
```

### CI

- GitHub Actions（`macos-15` ランナー）で PR・main push 時にビルド・テストを実行。ワークフロー: `.github/workflows/ci.yml`
- GitHub Actions のアクション参照は `pinact run` でコミットハッシュにピン留めする。
- SwiftLint（Homebrew）で lint を実行。設定: `.swiftlint.yml`、ビルドフェーズ: `project.yml` の `postCompileScripts`。

### 注意事項

- テストターゲット（`YankTests`）には `project.yml` で `GENERATE_INFOPLIST_FILE: YES` が必要。未設定だと `xcodebuild test` が `Cannot code sign because the target does not have an Info.plist file` で失敗する。
- `xcodebuild` は Xcode.app（フル版）が必要。`xcode-select -p` が CommandLineTools を向いている場合は `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` で切り替える（パスは環境に合わせて調整）。
- `SupportingFiles/Info.plist` は xcodegen が自動生成する。`.gitignore` に含まれており手動作成不要。`Resources/` 内に置くと Copy Bundle Resources に重複コピーされるため `SupportingFiles/` に配置している。
- `SupportingFiles/Yank.entitlements` も同様に xcodegen が `project.yml` の `entitlements.properties` から自動生成する。`.gitignore` に含まれており、entitlements の変更は `project.yml` で行う。
- XcodeGen でリソースを含めるには `sources` 内で `buildPhase: resources` を指定する。ターゲット直下の `resources` キーは公式スキーマに存在しない。
- SwiftData モデルに Optional プロパティを追加する場合は lightweight migration で対応可能だが、既存ストアがある環境ではビルド→起動の手動確認を行う。

### 手動テスト

```bash
# ビルド成果物のパスはプロジェクトディレクトリに紐づく（同じディレクトリなら不変）
killall Yank 2>/dev/null
open ~/Library/Developer/Xcode/DerivedData/Yank-cyrjxgwalxvjrtclicspdfexvkrl/Build/Products/Debug/Yank.app

# ログ確認
log stream --predicate 'subsystem == "com.toku345.Yank"' --level debug
```

### macOS 26 (Tahoe) 固有の注意

- **Accessibility 権限のリセット**: ビルドのたびにバイナリが変わると権限が無効化され、CGEvent.post が黙って失敗する。ペーストが効かない場合、システム設定 → アクセシビリティから Yank を削除→再追加する。
- **CGEvent Cmd+V シミュレーション**: `.hidSystemState` + `.cghidEventTap` では動作しない。`CGEventSource(.combinedSessionState)` + `setLocalEventsFilterDuringSuppressionState` + NX_NONCOALESCED フラグ (0x000008) + `.cgSessionEventTap` の組み合わせが必要（Maccy 方式）。

## 前身プロジェクト (Clipy) からの参考実装

本プロジェクトは [Clipy](https://github.com/Clipy/Clipy)（MIT License）の設計・実装を参考にしている。
コードを直接コピーする場合は Clipy の著作権表示を含めること。

参考箇所（[Clipy リポジトリ](https://github.com/Clipy/Clipy)）：
- クリップボード監視: `Clipy/Sources/Services/ClipService.swift:30-51`
- ペースト実行: `Clipy/Sources/Services/PasteService.swift:142-165`
- ホットキー登録: `Clipy/Sources/Services/HotKeyService.swift:112-120`
- スニペットXML: `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift:154-254`
- データモデル: `Clipy/Sources/Models/CPYClipData.swift`（型別データ保持の設計根拠）

## 参考プロジェクト (Maccy)

[Maccy](https://github.com/p0deje/Maccy)（MIT License）のペースト実装を参考にしている。
CGEvent による Cmd+V シミュレーションの手法（`CGEventSource(.combinedSessionState)`, `setLocalEventsFilterDuringSuppressionState`, NX_NONCOALESCED フラグ, `.cgSessionEventTap`）を採用。
