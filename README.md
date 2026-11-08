# リフトログ

筋トレの種目・重量・回数を記録する Web アプリ（PWA）。iPhone / Android のホーム画面に追加して使う。

- 記録はブラウザの localStorage に保存（端末の外には送らない）
- 履歴タブの「バックアップ」から JSON で書き出し・読み込み
- 「体」タブの写真は IndexedDB に保存（長辺1080pxの JPEG に縮める）。容量が大きいのでバックアップには含めない
- `sw.js` がアプリ本体をキャッシュするのでオフラインでも開ける。ファイルを変えたら `sw.js` の `VERSION` を上げる
- アイコンは `icons/` の PNG

## iOS 版（SwiftUI）

`ios/` にある。Web 版と同じ操作・同じ文言で、全タブを移植済み。仕様は `docs/spec.md`、App Store への出し方は `docs/app-store.md`。

- プロジェクトは `ios/project.yml` から XcodeGen で作る：`cd ios && xcodegen generate`
- テスト：`xcodebuild test -project ios/LiftLog.xcodeproj -scheme LiftLog -destination 'platform=iOS Simulator,name=iPhone 17'`
- 保存は SwiftData（記録・ルーティン・体重・写真）と UserDefaults（下書き・設定。キーは Web 版と同じ）。Web 版のバックアップ（JSON）を履歴タブから読み書きできる
- 種目・筋肉・ガイドの図は `ios/LiftLog/Resources/guide.json`。`index.html` の種目やガイドを変えたら `node ios/scripts/export-guide.mjs` で作り直す
- アプリアイコンは `swift ios/scripts/make-icon.swift ios/LiftLog/Assets.xcassets/AppIcon.appiconset/icon-1024.png` で描き直せる
- `privacy.html` は App Store に載せるプライバシーポリシー（GitHub Pages で公開する）
