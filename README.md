# リフトログ

筋トレの種目・重量・回数を記録する Web アプリ（PWA）。iPhone / Android のホーム画面に追加して使う。

- 記録はブラウザの localStorage に保存（端末の外には送らない）
- 履歴タブの「バックアップ」から JSON で書き出し・読み込み
- 「体」タブの写真は IndexedDB に保存（長辺1080pxの JPEG に縮める）。容量が大きいのでバックアップには含めない
- `sw.js` がアプリ本体をキャッシュするのでオフラインでも開ける。ファイルを変えたら `sw.js` の `VERSION` を上げる
- アイコンは `icons/` の PNG

## iOS 版（SwiftUI・移植中）

`ios/` にある。仕様は `docs/spec.md`（Web 版の書き起こし）。

- プロジェクトは `ios/project.yml` から XcodeGen で作る：`cd ios && xcodegen generate`
- テスト：`xcodebuild test -project ios/LiftLog.xcodeproj -scheme LiftLog -destination 'platform=iOS Simulator,name=iPhone 17'`
- 保存は SwiftData。Web 版のバックアップ（JSON）を履歴タブから読み込める
