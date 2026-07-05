# 開発用コード署名のセットアップ

Debug ビルドごとに Accessibility 権限が失効する問題 (issue #11) への対策として、
開発者ごとに安定した署名 identity を設定する。

## 背景

ad-hoc 署名 (identity 未設定) では designated requirement が `cdhash` ベースになり、
バイナリが変わるたびに macOS TCC が別アプリと判定して Accessibility 権限を失効させる。
Apple Development 証明書で署名すると designated requirement が証明書ベースになり、
リビルドしても権限が維持される。

## セットアップ手順

1. Xcode → **Settings → Accounts → 「+」→ Apple ID** でサインインする (無料アカウントで可)
2. アカウントを選択し **Manage Certificates… → 「+」→ Apple Development** で証明書を作成する
3. `security find-identity -v -p codesigning` で identity が **valid** と表示されることを確認する
   - `0 valid identities found` だが `-v` なしだと表示される場合は、中間証明書
     **Apple WWDR CA G3** の欠落が原因。以下で解消する:

     ```bash
     curl -fsSL -o /tmp/wwdrg3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
     security add-certificates -k ~/Library/Keychains/login.keychain-db /tmp/wwdrg3.cer
     ```

4. Team ID を確認する (証明書 subject の **OU** フィールド。CN 括弧内の ID ではない):

   ```bash
   security find-certificate -c "Apple Development" -p ~/Library/Keychains/login.keychain-db \
     | openssl x509 -noout -subject
   ```

5. `SupportingFiles/Local.xcconfig` を作成する (gitignore 対象):

   ```text
   DEVELOPMENT_TEAM = <Team ID>
   CODE_SIGN_STYLE = Automatic
   CODE_SIGN_IDENTITY = Apple Development
   ```

6. プロジェクトを再生成してからビルドし、署名を確認する
   (`Yank.xcodeproj` は生成物のため、fresh clone や `project.yml` 変更後は
   `xcodegen generate` を先に実行しないと署名設定が反映されない):

   ```bash
   xcodegen generate
   xcodebuild -project Yank.xcodeproj -scheme Yank -configuration Debug build
   codesign -d -r- <DerivedData>/Build/Products/Debug/Yank.app
   # designated => ... certificate leaf[subject.CN] = "Apple Development: ..." なら OK
   ```

7. 署名切り替え後の初回起動時のみ、Accessibility 権限の再付与が必要
   (システム設定 → プライバシーとセキュリティ → アクセシビリティで Yank を削除して再追加)

## 仕組み

- `project.yml` の `configFiles` が `SupportingFiles/Base.xcconfig` を **Debug 構成のみ**・全ターゲットに適用する (個人証明書を Release/archive に波及させないため)
- `Base.xcconfig` は `#include? "Local.xcconfig"` で個人設定を optional include する
- `Local.xcconfig` が無い環境 (CI 等) では従来どおり ad-hoc 署名にフォールバックする

設計判断の背景と却下した代替案は ADR 0007 を参照。

## 注意

- **`Local.xcconfig` と Team ID はコミットしない** (個人設定のため gitignore 済み)
- 実署名では hardened runtime が実効化されるが、Debug ビルドには Xcode が
  `com.apple.security.get-task-allow` を自動注入するためデバッガは使用可能
- 証明書は約 1 年で失効する。更新後は一度だけ Accessibility 権限の再付与が必要
