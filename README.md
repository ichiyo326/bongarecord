# ボンガレコード

ボンバーガールの対戦結果を記録・集計・振り返るためのiOSアプリです。SwiftUI / SwiftDataを中心に、戦績分析、CloudKit同期、Live Activities、CSV入出力、配信用オーバーレイ連携、Apple Intelligenceを利用した戦績分析機能を実装しています。

## 主な機能

- 対戦結果の登録・編集・検索
- キャラクター、ロール、ステージ、ランクなどの条件別集計
- SwiftDataによる永続化とCloudKit同期
- Live Activities / Dynamic Islandによる対戦状況表示
- CSVインポート・エクスポート
- OBS等で利用する配信用オーバーレイ連携
- Foundation Models / Tool Callingを利用した戦績AI分析
- 集計処理の性能検証・テスト

## 技術スタック

- Swift / SwiftUI
- SwiftData / CloudKit
- Swift Concurrency (`async/await`, `Actor`, `@ModelActor`)
- ActivityKit / Live Activities
- UserNotifications
- Foundation Models
- XCTest / Swift Testing

## 構成

```text
BongaRecord/
├── AI/             # Apple Intelligence / Foundation Models関連
├── Analytics/      # 検索条件・集計・分析サービス
├── DeveloperTools/ # 性能検証用ツール
├── Models/         # SwiftDataモデル・マスターデータ
├── Storage/        # CSV、集計、通知、Live Activity、配信連携
├── Theme/          # テーマ・配色
└── Views/          # SwiftUI画面

BongaRecordTests/   # 単体・性能・分析機能テスト
Assets.xcassets/    # アプリアセット
```

## 設計上のポイント

### 分析処理の分離

画面側に閉じていた戦績集計処理とは別に、`AnalyticsRepository` と `BattleAnalyticsService` を設け、UIから独立して検索・集計できる構成にしています。

### AIに計算を任せない

AI分析では、LLMはユーザー意図の解釈とTool選択、結果の説明を担当し、勝率や件数などの確定計算はSwift側で実行します。生成モデルに数値計算を直接任せず、アプリ内データをTool経由で取得する構成です。

### 大量データを意識した集計

`SingleFetchAggregator` などでDBアクセス回数とメモリ使用量のトレードオフを検証しています。現在の実装にも改善余地があり、Predicate、fetchLimit、集計方法などの最適化を継続しています。

### バックグラウンド処理

CSV取り込みや集計処理ではActorを利用し、UIスレッドを長時間占有しないようにしています。

## テスト

`BongaRecordTests/` に以下を含みます。

- 戦績分析サービスのテスト
- Foundation Models Toolのテスト
- 単一fetch集計のテスト
- 並列処理・性能検証

## 注意事項

このリポジトリにはXcodeのユーザー固有設定、ローカルAIツール設定、ビルド生成物、秘密情報は含めていません。CloudKit等を実機で利用する場合は、各自のApple Developer Team / Signing & Capabilities設定が必要です。
