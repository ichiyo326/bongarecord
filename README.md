# ボンガレコード

**ボンバーガールの対戦結果を記録・分析し、プレイの振り返りから配信まで支援するiOSアプリです。**

個人で企画・設計・実装し、App Storeへの公開後も機能追加・UI改善・不具合修正を継続しています。

<p align="center">
  <a href="https://apps.apple.com/jp/app/id6777901156"><strong>App Storeで見る</strong></a>
  ·
  <a href="https://github.com/ichiyo326/bongarecord"><strong>GitHub</strong></a>
</p>

## Screenshots

> 画面イメージは [App Store](https://apps.apple.com/jp/app/id6777901156) で確認できます。  
> GitHub上にも表示する場合は `docs/images/` に `record.png`、`statistics.png`、`calendar.png`、`profile.png` を追加してください。

---

## 概要

ボンガレコードは、アーケードゲーム「ボンバーガール」の対戦結果をiPhoneで記録し、勝率・キャラクター・ロール・ステージ・期間などの条件から振り返るための戦績管理アプリです。

単に対戦結果を保存するだけではなく、次のような用途まで一つのアプリで完結させることを目指して開発しています。

- 日々の戦績を素早く記録する
- キャラクター・マップ・期間などの条件別に戦績を分析する
- カレンダーやプロフィールからプレイ傾向を振り返る
- Live Activities / Dynamic Islandで当日の戦績を確認する
- 配信中の戦績をOBSへリアルタイム表示する
- 他の戦績管理アプリからCSVでデータを移行する

## 開発背景

自分自身がボンバーガールをプレイする中で、対戦結果を継続的に残し、後から「どのキャラクター・マップで成績が良いか」「最近の戦績がどう変化しているか」を確認したいと考えたことが開発のきっかけです。

そこで、戦績の入力・保存・集計・可視化をiPhone上で完結でき、端末を変更してもデータを引き継げるアプリとして開発しました。

開発を進める中では、記録・集計だけでなく、実際の利用場面から得た課題をもとに、入力項目のカスタマイズ、通知、Live Activities、CSV互換、OBS配信連携などへ機能を拡張しています。

## 主な機能

### 戦績記録・集計

対戦ごとに勝敗、使用キャラクター、ロール、ステージなどを記録できます。保存したデータから、全体・キャラクター別・ロール別・ステージ別・期間別の戦績を集計します。

### カレンダー・プロフィール

プレイ日ごとの戦績をカレンダーで確認できます。プロフィール画面では、プレイヤー情報やキャラクターごとの利用状況・戦績などをまとめて表示します。

### キャラクター・マップ管理

使用しないキャラクターやステージを非表示にでき、入力時に必要な項目だけを表示することで操作量を減らしています。

### Live Activities / Dynamic Island

ActivityKit / WidgetKitを利用し、その日の勝敗数をロック画面とDynamic Islandへ表示します。アプリを開かなくても当日の戦績を確認できます。

### 通知・戦績シェア

時報参加を補助するローカル通知や、通算勝利数・連勝数などの節目を知らせる実績通知を実装しています。また、集計結果をカード画像として書き出して共有できます。

### OBS配信オーバーレイ

配信セッション中の勝敗数・勝率・連勝連敗をOBS Browser Sourceへ表示できます。

アプリ側で利用者専用のHTMLファイルを生成し、AirDropなどでPCへ渡してOBSのローカルファイルとして指定できる構成にしています。利用者自身がWebサイトを用意する必要はありません。

### CSVインポート・エクスポート

CSVによるバックアップに加え、Android向け戦績管理アプリ「ボンガクロニクル」の引継ぎデータを取り込めるようにしています。

外部アプリと本アプリではID体系が異なるため、外部IDをそのまま保存せず、**外部ID → 名称 → 本アプリ内部ID**へ変換する層を設けています。不正値や本アプリに存在しないIDを含む行はスキップし、取り込み結果として扱える設計です。

---

## 技術スタック

| 技術 | 用途 |
|---|---|
| Swift | アプリケーション実装 |
| SwiftUI | UI構築 |
| SwiftData | 対戦記録・プレイヤー情報などの永続化 |
| CloudKit | SwiftDataと連携したiCloud同期 |
| Swift Concurrency | 非同期処理・集計処理 |
| ModelActor | MainActor外でSwiftDataを扱う集計処理 |
| ActivityKit / WidgetKit | Live Activities・Dynamic Island |
| UserNotifications | 時報通知・実績通知 |
| PhotosUI | 背景画像カスタマイズ |
| URLSession | OBS連携用データ送信 |
| Firebase Realtime Database | iPhoneとOBS間のリアルタイム中継 |
| XCTest | 集計結果の一致確認・パフォーマンス検証 |

## 技術的に工夫した点

### 1. SwiftData + CloudKitによるローカルファーストなデータ管理

対戦記録はSwiftDataで端末内に保存し、CloudKitと組み合わせてiCloudへ同期しています。

データモデルではキャラクター名やマップ名そのものを戦績ごとに重複保存するのではなくIDで参照し、マスターデータと分離しています。これにより、表記変更をマスター側で吸収しやすくし、戦績データのサイズ増加も抑えています。

### 2. SwiftDataの集計方法を複数方式で設計・検証

プロフィールでは、キャラクターごとの試合数・勝利数をSwiftDataから集計します。

当初の直列な集計だけでなく、SwiftDataの `ModelContext` がスレッドセーフではないことを踏まえ、`@ModelActor` ごとに独立したModelContextを持たせ、`withThrowingTaskGroup` から複数のactorへ処理を分配する方式を実装しました。

```text
MainActor
   |
   v
TaskGroup
   |
   +---- ModelActor + ModelContext
   +---- ModelActor + ModelContext
   +---- ModelActor + ModelContext
   +---- ModelActor + ModelContext
```

一方で「並列化すれば必ず速くなる」とは限らないため、以下の3方式を比較するテストコードも作成しています。

1. キャラクターごとに `fetchCount` を直列実行する方式
2. 複数ModelActorで `fetchCount` を分担する方式
3. 全戦績を1回だけfetchし、Swift側で辞書集計する方式

`BongaRecordTests/SingleFetchAggregatorTests.swift` では、1,000件・50,000件・500,000件・2,000,000件のデータを使う比較テストに加え、ディスク上のストアを使った条件も用意しています。

速度だけを主張するのではなく、SQL側でCOUNTを行う方式と、モデルオブジェクトを大量に実体化する方式のトレードオフを実測できるようにしています。

### 3. OBS連携を「利用者が導入できる形」まで改善

OBSとの連携では、iPhoneと配信PCが同一LANにあるとは限らないため、Firebase Realtime Databaseを中継地点として利用しています。

```text
iPhone
  |
  | 集計値を送信
  v
Firebase Realtime Database
  |
  | JSONを取得
  v
OBS Browser Source
```

初期案では利用者側でFirebaseの準備やWebホスティングが必要でしたが、その導入負荷をなくすため、現在はアプリ内にHTMLテンプレートを持ち、ランダムな利用者用トークンを埋め込んだHTMLをアプリ自身が生成する方式にしています。

利用者は生成したHTMLをPCへ送ってOBSの「ローカルファイル」に指定するだけで利用できます。

### 4. 外部アプリとのCSV互換

既存のAndroid向け戦績管理アプリから移行できるよう、異なるID体系を吸収する変換処理を実装しています。

```text
外部CSVのキャラクター / マップNo
        |
        v
TransferTable
        |
        v
名称へ変換
        |
        v
MasterDataから本アプリ内部IDを解決
        |
        v
BattleRecordとして保存
```

単純にCSVの数値を内部IDとして扱わないことで、別アプリのデータ形式とアプリ内部のモデルを疎結合にしています。

### 5. iOS固有機能まで含めた体験設計

SwiftUIによる画面実装だけでなく、ActivityKit / WidgetKit、UserNotifications、PhotosUIなどを利用し、Live Activities、通知、背景カスタマイズなどiOSの機能をアプリ体験に組み込んでいます。

---

## テスト・パフォーマンス検証

集計ロジックについては、速度比較だけでなく、最適化前後で同じ結果が得られることをXCTestで検証しています。

主な検証内容:

- 旧方式とModelActor方式の集計結果一致
- 直列fetchCount / ModelActorプール / 単一fetch方式の結果一致
- 1,000件 / 50,000件 / 500,000件での比較
- 2,000,000件のストレステスト
- pool sizeを1 / 2 / 4 / 8 / 16へ変えた際の傾向確認
- ディスクバックストアを利用した条件での比較

関連コード:

- `BongaRecordTests/ProficiencyPerformanceTests.swift`
- `BongaRecordTests/SingleFetchAggregatorTests.swift`
- `BongaRecordTests/ParallelismDiagnosticsTests.swift`

## プロジェクト構成

```text
BongaRecord/
├── Models/           # 戦績・プレイヤー情報・マスターデータ
├── Views/            # SwiftUIによる画面
│   └── Components/   # 再利用UI
├── Storage/          # 集計・CSV・通知・Live Activity・OBS連携
├── Theme/            # 配色・背景などの外観管理
├── DeveloperTools/   # ベンチマーク・検証用機能
└── BongaRecordApp.swift

BongaRecordTests/
├── ProficiencyPerformanceTests.swift
├── SingleFetchAggregatorTests.swift
├── ParallelismDiagnosticsTests.swift
└── ...
```

UI、データモデル、永続化・集計処理、テーマ、開発用検証コードを役割ごとに分離しています。

## App Store公開後の改善

2026年6月9日にApp Storeで初回公開しました。

公開後も、実際に利用する中で見つかった課題をもとに、次のような改善を継続しています。

- 戦績表示UI・文字配色・レイアウトの改善
- お気に入りキャラクター / ステージ表示
- キャラクター・マップの表示 / 非表示設定
- 時報通知
- アプリ内テーマ・背景画像カスタマイズ
- 集計方式の改善
- Live Activities
- OBS配信連携
- 不具合修正・動作安定性の改善

[App Storeでバージョン履歴を見る](https://apps.apple.com/jp/app/id6777901156)

## プライバシー設計

通常の戦績データは端末内、または利用者自身のiCloudプライベートデータベースで管理されます。

OBS配信連携を利用者が明示的に有効化した場合のみ、配信画面に必要な集計値をFirebase Realtime Database経由で送信します。個々の対戦記録や氏名・アカウント情報をOBS連携用データとして送る設計にはしていません。

詳細は [PRIVACY.md](PRIVACY.md) を参照してください。

## セットアップ

```bash
git clone https://github.com/ichiyo326/bongarecord.git
cd bongarecord
open BongaRecord_Project.xcodeproj
```

CloudKitやLive Activitiesなど、Apple Developerアカウントに紐づく設定は利用する環境に合わせて変更する必要があります。詳しくはリポジトリ内のセットアップ資料を参照してください。

## 今後改善したいこと

- 実データでのパフォーマンス計測結果をREADMEへ継続的に反映する
- 集計処理のボトルネックをInstrumentsで計測し、データ件数に応じた最適な方式を検討する
- UIテスト・アクセシビリティ対応を拡充する
- 利用者からのフィードバックをもとに入力・分析体験を改善する

## Links

- [App Store](https://apps.apple.com/jp/app/id6777901156)
- [GitHub Repository](https://github.com/ichiyo326/bongarecord)
- [OBS配信連携セットアップ](OBS配信連携_セットアップ手順.md)
- [プライバシーポリシー](PRIVACY.md)

---

本アプリは個人が開発している非公式アプリであり、ボンバーガールの運営会社・開発会社・その他の権利者とは関係ありません。ゲーム名・キャラクター名・画像・その他の商標・著作物に関する権利は、それぞれの権利者に帰属します。

Copyright © 2026 ICHI
