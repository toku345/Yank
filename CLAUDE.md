# Repository Instructions

このファイルは Claude/Codex などのエージェントが共有するリポジトリ作業指示です。

## Communication

- 日本語で簡潔かつ実務的に返答する。
- 編集前に関連ファイルを確認し、ユーザーや他ツールの未コミット変更を巻き戻さない。
- 検索は `rg` / `rg --files` を優先する。
- 変更後は最小限の関連検証を実行し、結果を報告する。
- OpenAI/Codex など外部サービスの最新仕様が必要な場合は公式ドキュメントを確認する。

## Project Overview

Yank は macOS 14+ 向けのクリップボードマネージャです。
Clipy の後継を意識し、SwiftUI + SwiftData + Carbon API を中心に、外部ランタイム依存なしで構築します。

プロダクトの各 Phase と完了条件は `PLAN.md` に記録します。公開向けの短い
現在状況は `README.md` の Project Status、実作業の状態は GitHub Issues と
Milestones を参照してください。

## Planning Sources of Truth

計画情報は、用途ごとに次の場所を正本とします。

- **GitHub Issues と Milestones**: 実作業の scope、acceptance criteria、依存関係、
  status、assignment、実装順序。
- **`README.md` / Project Status**: source 上の app version、active milestone、
  owner が選んだ current focus、public release status だけを示す短い公開 snapshot。
- **`PLAN.md`**: 長期的なプロダクト方針、各 Phase の outcome、完了条件。これらの
  目標が変わる場合だけ更新する。
- **`docs/loop/state.md`**: owner が承認した loop 運用上の判断。Automation は提案のみ
  行い、直接更新しない。通常の Issue 進行や close では更新しない。
- **`docs/adr/`**: 長期的に残すアーキテクチャ・設計判断。

計画上の status を変更する前に live GitHub state と照合し、複数のファイルへ
backlog、完了状況、実装順序を重複して記録しないでください。

## Requirements

- Cmd+Shift+V でクリップボード履歴ビューアを開く。
- ビューア上で Emacs keybinding を使う。
  - 実装済み: `C-n` / `C-p` / `C-a` / `C-e` / `C-g`
  - Phase 2: `C-f` / `C-b` によるタブ切り替え
- Phase 2 でスニペット管理を追加する。
- Phase 3 でセンシティブな値の扱い、ステータスバー機能の拡充、ログイン起動、検索を検討する。

## Tech Stack

- UI: SwiftUI
- Data: SwiftData
- Global hotkey: Carbon API (`RegisterEventHotKey`)
- Paste execution: CGEvent による Cmd+V シミュレーション
- Clipboard monitoring: `Timer` + `NSPasteboard.changeCount` の 250ms ポーリング
- Project generation: XcodeGen (`project.yml` -> `.xcodeproj`)
- Deployment target: macOS 14 Sonoma
- Package policy: 外部依存ゼロを基本方針とする

Carbon API での実装が現実的でない場合のみ HotKey などの SPM 依存を検討します。

## Repository Workflow

- `AGENTS.md` は `CLAUDE.md` への symlink として管理します。
- `.xcodeproj` は生成物です。`project.yml` を編集し、必要に応じて `xcodegen generate` を実行します。
- `project.yml` 変更時、XcodeGen 管理下の source/resource ファイルの新規追加・削除時は `xcodegen generate` を実行します。
- 既存 Swift ファイルの編集だけなら、通常は `xcodebuild` を直接実行すれば十分です。
- `SupportingFiles/Info.plist` と `SupportingFiles/Yank.entitlements` は XcodeGen が生成します。手動作成しないでください。
- Codex がコミット内容の作成に実際に関与した場合のみ、commit message の末尾に次の trailer を一度だけ含めます。関与していないコミットには含めません。

```text
Co-authored-by: Codex <noreply@openai.com>
```

## Build, Test, Lint

```bash
# Generate project
xcodegen generate

# Build
xcodebuild -project Yank.xcodeproj -scheme Yank -configuration Debug build

# Test
xcodebuild -project Yank.xcodeproj -scheme Yank test

# Lint
swiftlint lint --strict

# Runtime logs for manual testing
log stream --predicate 'subsystem == "com.toku345.Yank"' --level debug
```

CI は GitHub Actions の `macos-15` ランナーで、Markdown のみの変更を除く PR と `main` push 時にビルド・テストを実行します。
ワークフローは `.github/workflows/ci.yml` です。

CI 関連の注意:

- GitHub Actions の action 参照は `pinact run` でコミットハッシュに pin する。
- SwiftLint は Homebrew 版を使う。設定は `.swiftlint.yml`、ビルドフェーズは `project.yml` の `postCompileScripts`。
- CodeRabbit の指摘は対象 Issue の acceptance criteria、適用される ADR、`PLAN.md` に照らして判断する。プロジェクト仕様と矛盾する誤検知があり得ます。

## Implementation Notes

- `YankTests` には `project.yml` で `GENERATE_INFOPLIST_FILE: YES` が必要です。未設定だと `xcodebuild test` が code signing エラーで失敗します。
- `xcodebuild` はフル版 Xcode が必要です。`xcode-select -p` が CommandLineTools を向いている場合は Xcode.app へ切り替えてください。
- XcodeGen で resource を含める場合は `sources` 内で `buildPhase: resources` を指定します。ターゲット直下の `resources` キーは使いません。
- SwiftLint の `function_body_length` はデフォルト上限 50 行です。ロジック追加時は必要に応じてヘルパーへ抽出します。
- Apple API の詳細確認は Xcode SDK ヘッダーが有用です。`developer.apple.com` は JavaScript 前提のページが多く、CLI から取得しにくいことがあります。

## macOS / AppKit Pitfalls

- Accessibility 権限は ad-hoc 署名だと debug build ごとに無効化されます (designated requirement が cdhash ベースになるため)。`SupportingFiles/Local.xcconfig` に開発用署名を設定すると権限が維持されます。セットアップは `docs/dev-signing.md` を参照。それでもペーストが効かない場合は「システム設定 -> アクセシビリティ」から Yank を削除して再追加します。
- SwiftData の `ModelConfiguration("Yank")` は `~/Library/Application Support/Yank.store` を作ります。スキーマ変更時は `rm -f ~/Library/Application\ Support/Yank.store*` で削除します。
- worktree ごとに DerivedData パスが異なります。手動起動時は `open` に full path を指定します。
- `NSPasteboard` は classic API (`declareTypes` / `setString` / `setData`) と modern API (`writeObjects`) を混用しないでください。`NSPasteboardItem` + `writeObjects` に寄せます。
- `NSPanel` 内の SwiftUI `List` は内部の `NSTableView` が first responder を奪い、`keyDown` に届かないことがあります。`sendEvent` を override して window level で扱います。
- `@Observable` はイベントチャネルに使えません。同じ値の連続代入では `onChange` が発火しないため、イベント通知は直接メソッド呼び出しなどにします。
- SwiftUI `List` の selection binding 変更だけではスクロールしません。`ScrollViewReader` + `scrollTo` + `.id()` が必要です。
- `XCTestCase.setUp()` は non-throwing です。throwing setup は `setUpWithError() throws` を使います。
- `LSUIElement = true` のメニューバーアプリでも `NSAlert.runModal()` は前面に出ます。ユーザー向けエラー通知に使えます。
- `NSEvent.modifierFlags` は直前のホットキーや Ctrl 入力の flag を引きずることがあります。信頼できる判定が必要なら `flagsChanged` で自前追跡します。デバイス依存ビットは `.intersection(.deviceIndependentFlagsMask)` で除外します。
- `CGEventSource.flagsState` は物理キーボード状態を返すため XCTest で偽装できません。修飾キー判定はイベント経由に寄せる方がテストしやすいです。
- `NSPasteboard.clearContents()` はバリデーション後に呼びます。先に clear すると、途中失敗時にユーザーの既存クリップボードを破壊します。
- Swift の暗黙 return switch で case 内に `let` 文を挟むと contextual type inference が崩れることがあります。明示的な `return` か switch 外での導出を使います。

## ADR

設計判断は `docs/adr/NNNN-<slug>.md` に記録します。既存 ADR は `docs/adr/` を参照してください。

## References And License Notes

本プロジェクトは Clipy と Maccy の設計を参考にしています。
コードを直接コピーする場合は、各プロジェクトの著作権表示とライセンス条件を確認して含めてください。

Clipy:

- Repository: https://github.com/Clipy/Clipy
- License: MIT
- Reference areas: clipboard monitoring, paste execution, hotkey registration, snippet XML, data model design

Maccy:

- Repository: https://github.com/p0deje/Maccy
- License: MIT, Copyright 2025 Alex Rodionov
- Reference areas: custom `NSPasteboard.PasteboardType` marker for self-paste suppression, CGEvent configuration
