# ADR 0005: PasteFormat enum によるプレーンテキストペースト

## Status

Accepted

## Context

Yank 経由でブラウザからコピーしたリッチテキストをペーストすると、HTML/RTF フォーマットが保持されたまま貼り付けられる (Issue #5)。クリップボードマネージャ経由のペーストでは、プレーンテキストが期待されるケースが多い。

一方で、オリジナルフォーマットでのペーストも有用な場面がある（リッチテキストエディタへの貼り付け等）。そのため、ユーザーがペースト時にフォーマットを選択できる仕組みが必要。

設計上の選択肢として以下を検討した:

- **A: ViewerAction に `.pastePlainText` case を追加** — 既存の `.paste` に手を入れないが、クロージャーチェーン (`onPaste` / `onPastePlainText`) と処理ロジック (`handlePaste` / `handlePastePlainText`) が重複する。
- **B: `.paste(PasteFormat)` associated value 方式** — クロージャーは1本のまま、`handlePaste` も1メソッドで format による分岐のみ。既存テストの機械的修正が必要。
- **C: Cmd+Shift+V シミュレーション** — ペースト先アプリに「Paste and Match Style」を委譲。ただし Yank 自身が Cmd+Shift+V をグローバルホットキーとして登録しており衝突する。また対応しないアプリではリッチフォーマットのまま。

## Decision

**アプローチ B: `.paste(PasteFormat)` associated value 方式** を採用する。

- `PasteFormat` enum (`original` | `plainText`) を導入し、`ViewerAction.paste` に associated value として持たせる。
- `EmacsKeyHandler` で Return → `.paste(.original)`、Shift+Return → `.paste(.plainText)` を生成。
- `PasteService.writePlainTextToPasteboard(item:)` を新設。ユーザー向けペイロードとして `.string` 型のみを書き出す（self-paste suppression マーカー `.fromYank` は維持。ADR 0002 参照）。テキスト導出の優先順位: (1) `stringValue` → そのまま使用、(2) `fileURLs` → ファイルパス文字列に変換。いずれもない場合（画像のみ等）は `false` を返す。
- `ClipItem` のキャプチャ・保存は変更しない。全型を保存し続け、書き出し時のみフォーマットを制御する。
- マウスタップは `.original` 固定。

## Consequences

- **Positive**: ユーザーが Shift+Return でプレーンテキストペーストを選択でき、Yank 側で確実にフォーマットを制御できる。クロージャーチェーンが1本のままで、ペースト処理パスも統一される。
- **Positive**: `ClipItem` に全型を保存しているため、将来「元のフォーマットでペースト」オプションとの互換性がある。
- **Negative**: `ViewerAction.paste` の全参照箇所（テスト含む約7箇所）を修正する必要がある。ただし機械的な変更。
- **Risk**: テキスト表現を持たない ClipItem で Shift+Return した場合、パネルが開いたまま無反応になる。将来的に `NSSound.beep()` 等のフィードバックを検討する。
