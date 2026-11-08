# App Store への公開手順

SwiftUI 版（`ios/`）を App Store に出すまでの手順と、App Store Connect に入れる内容の下書き。

## 1. 事前に用意するもの

- Apple Developer Program（年会費制）への登録
- プライバシーポリシーの URL：`https://mikihisa-ogata.github.io/liftlog/privacy.html`（リポジトリ直下の `privacy.html`。GitHub Pages を有効にしておく）
- サポート URL：`https://github.com/mikihisa-ogata/liftlog/issues`

## 2. ビルドと提出

1. `ios/project.yml` の `DEVELOPMENT_TEAM` にチーム ID（Developer サイトの Membership に出る10桁）を入れ、`cd ios && xcodegen generate`
2. バンドル ID `io.github.mikihisa-ogata.liftlog` を App Store Connect の「マイ App」で新規登録（名前「リフトログ」、主言語 日本語、SKU は `liftlog` など）
3. Xcode で `ios/LiftLog.xcodeproj` を開き、実行先を「Any iOS Device」にして Product › Archive
4. Organizer で Distribute App › App Store Connect › Upload
5. App Store Connect でビルドを選び、下の内容を入れて審査に出す
6. 2回目以降は `project.yml` の `CURRENT_PROJECT_VERSION`（ビルド番号）を上げてからアーカイブする。表示する版を変えるときは `MARKETING_VERSION`

## 3. App Store Connect に入れる内容（下書き）

| 項目 | 内容 |
| --- | --- |
| 名前 | リフトログ |
| サブタイトル | 筋トレの重量・回数を手早く記録 |
| カテゴリ | ヘルスケア／フィットネス |
| 年齢制限 | 4+（該当する項目なし） |
| 価格 | 無料 |
| 著作権 | 2026 Ogata Mikihisa |

**説明文**

```
リフトログは、筋トレの種目・重量・回数をすばやく記録するアプリです。

・前回の重量と回数が自動で入るので、変えたところだけ直せば記録できます
・よくやる種目の組み合わせをルーティンとして保存して、まとめて呼び出せます
・セットに「済」を付けると休憩タイマーが始まり、終わると音と通知で知らせます
・カレンダー、週ごとの目標の連続記録、鍛えた部位の人体図で、続けた成果が見えます
・種目ごとの推定1RMと最大重量の推移をグラフで確認できます
・体重と体脂肪率を記録し、7日移動平均で傾向をつかめます
・体の写真を撮って、ビフォー・アフターを並べて比べられます
・50種目のやり方を、姿勢の図と効く部位つきで確認できます
・アイアン／プレート／ジムクロックの3つのテーマから選べます

記録はすべて端末の中だけに保存され、外部には送信しません。アカウント登録も不要です。
JSON ファイルへの書き出し・読み込みで、機種変更のときも記録を引き継げます。
```

**キーワード**（100文字以内）：`筋トレ,記録,ワークアウト,ジム,ベンチプレス,スクワット,デッドリフト,1RM,休憩タイマー,ルーティン,体重,トレーニング`

**App のプライバシー**：「データを収集していません」を選ぶ（`ios/LiftLog/PrivacyInfo.xcprivacy` と一致）

**輸出コンプライアンス**：暗号化を使っていない（Info.plist の `ITSAppUsesNonExemptEncryption = NO` で質問は省かれる）

**審査へのメモ**

```
ログインは不要です。初回起動時に見本の記録（「サンプル」の印つき）とルーティンが入っているので、
履歴・推移タブの機能をすぐに確認できます。見本は履歴タブの「サンプルを削除」で消せます。
休憩タイマーは記録タブ下部の「開始」で動き、終了時にローカル通知で知らせます（通知の許可は初回のタイマー開始時に求めます）。
```

## 4. スクリーンショット

6.9 インチ（1320×2868 か 1290×2796）が必須。シミュレーターの iPhone 17 Pro Max で撮る：

```sh
xcrun simctl boot "iPhone 17 Pro Max"
# アプリを入れて開き、見せたい画面にしてから
xcrun simctl io "iPhone 17 Pro Max" screenshot ~/Desktop/liftlog-1.png
```

記録・履歴・推移・ガイド・テーマ違いの 4〜6 枚を用意する。見本の記録が入った状態で撮ると中身のある画面になる。
