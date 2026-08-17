# ボンガレコード

ボンバーガールのプレイ戦績を記録・集計するためのiOSアプリです。

日々の対戦結果を記録し、カレンダーやプロフィール画面から勝率、使用キャラクター、ステージごとの戦績などを確認できます。

<p align="left">
  <a href="https://apps.apple.com/jp/app/id6777901156">
    <img src="https://img.shields.io/badge/App%20Store-ボンガレコード-0D96F6?logo=appstore&logoColor=white" alt="Download on the App Store">
  </a>
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift / SwiftUI">
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-lightgrey" alt="iOS / iPadOS">
</p>

## App Store

[ボンガレコードをApp Storeで表示](https://apps.apple.com/jp/app/id6777901156)

## 主な機能

### 戦績記録

対戦ごとに、勝敗や使用キャラクター、ロール、ステージなどを記録できます。

### 戦績集計

記録したデータをもとに、勝率やプレイ状況を集計します。

* 全体の勝率
* キャラクター別の戦績
* ロール別の戦績
* ステージ別の戦績
* 期間ごとの戦績

### カレンダー表示

プレイした日と戦績をカレンダー形式で確認できます。

### プロフィール

プレイヤー情報や、お気に入りのキャラクター・ステージ、これまでの戦績をまとめて表示します。

### キャラクター・マップ管理

集計や入力画面に表示するキャラクター、ステージを管理できます。

使用しない項目を非表示にすることで、戦績入力を簡略化できます。

### ライブアクティビティ

ロック画面とDynamic Islandに、その日の勝敗数をリアルタイム表示します。

アプリを開かずに当日の戦績を確認できます。

### 時報通知

指定した末尾時刻に合わせてローカル通知を設定できます。

ボンバーガールの時報参加を補助するための機能です。

### 実績通知

通算勝利数や連勝数が節目に到達したとき、ローカル通知でお知らせします。

### 戦績シェア

集計結果をカード画像として書き出し、SNSなどへ共有できます。

### 配信オーバーレイ連携（任意）

配信中の戦績（勝敗数・勝率・連勝連敗）を、OBSのブラウザソースに表示できます。

アプリから専用のHTMLファイルを書き出し、AirDropなどでOBSを動かすパソコンへ送って「ローカルファイル」として指定するだけで利用できます。Webサイトの用意は不要です。

この機能は既定でオフです。詳細は「プライバシー」を参照してください。

### 表示カスタマイズ

* アプリ内の配色変更
* 背景画像の設定
* 戦績表示項目の変更
* キャラクター練度基準の変更

### データの入出力

CSV形式による戦績データのインポート・エクスポートに対応しています。

Android向け戦績管理アプリ「ボンガクロニクル」のデータと互換性があります。

## スクリーンショット

スクリーンショットはApp Storeで確認できます。

[App Storeの掲載ページを開く](https://apps.apple.com/jp/app/id6777901156)

リポジトリ内に画像を配置する場合は、次のように追加できます。

```text
docs/
└── images/
    ├── record.png
    ├── statistics.png
    ├── calendar.png
    └── profile.png
```

```markdown
<p align="center">
  <img src="docs/images/record.png" width="220" alt="戦績入力画面">
  <img src="docs/images/statistics.png" width="220" alt="戦績集計画面">
  <img src="docs/images/calendar.png" width="220" alt="カレンダー画面">
</p>
```

## 使用技術

* Swift
* SwiftUI
* SwiftData
* CloudKit
* ActivityKit / WidgetKit
* UserNotifications
* PhotosUI
* CSVインポート・エクスポート
* iCloud同期

## アーキテクチャ

プロジェクトは、役割ごとにコードを分離しています。

```text
BongaRecord/
├── BongaRecordApp.swift
├── Models/
├── Views/
│   └── Components/
├── Storage/
├── Theme/
└── DeveloperTools/
```

| ディレクトリ           | 役割                             |
| ---------------- | ------------------------------ |
| `Models`         | 戦績、キャラクター、ステージなどのデータモデル        |
| `Views`          | SwiftUIによる画面・UI                |
| `Storage`        | 集計、CSV、通知、CloudKit連携などの処理       |
| `Theme`          | 配色、書体、背景画像などの外観設定              |
| `DeveloperTools` | 開発時のみ使用するベンチマーク・検証用コード         |

`BongaRecordApp.swift` がアプリのエントリーポイントで、SwiftDataの`ModelContainer`の初期設定もここで行っています。

実際のディレクトリ構成は、開発状況によって変更される場合があります。

## 開発環境

* macOS
* Xcode
* Swift
* iOS SDK

動作に必要なOSバージョンは、Xcodeプロジェクト内のDeployment Targetを確認してください。

## セットアップ

リポジトリをcloneします。

```bash
git clone https://github.com/ichiyo326/bongarecord.git
cd bongarecord
```

Xcodeプロジェクトを開きます。

```bash
open BongaRecord_Project.xcodeproj
```

Xcode上で以下を確認します。

1. 使用するSchemeを選択する
2. 実行先のSimulatorまたは実機を選択する
3. Signing & Capabilitiesを自分の開発チームに設定する
4. `Command + R` でビルド・実行する

ライブアクティビティを動作させるには、Widget Extensionターゲットの追加が必要です。リポジトリ内のセットアップ手順を参照してください。

## iCloud・CloudKitについて

戦績データはSwiftDataで管理し、`cloudKitDatabase: .automatic` によりiCloudのプライベートデータベースへ同期されます。

iCloud同期を利用する場合は、自分のApple Developerアカウントに合わせて以下の設定を変更する必要があります。

* Development Team
* Bundle Identifier
* iCloud Container
* CloudKit Container
* Signing & Capabilities

公開リポジトリに、秘密鍵や個人用の認証情報を含めないでください。

## プライバシー

戦績データは端末内、または利用者自身のiCloud環境（プライベートデータベース）で管理されます。開発者がこれらのデータを閲覧することはできません。

例外として、「配信オーバーレイ連携」を有効にしている間のみ、集計値（勝敗数、勝率、連勝連敗数）が開発者の用意した中継サーバー（Firebase Realtime Database）を経由してOBSへ送信されます。

* この機能は既定でオフで、利用者が明示的に有効化したときだけ動作します
* 送信されるのは上記の数値のみで、氏名やアカウント情報などの個人情報、個々の対戦記録は含まれません
* 送信先のパスには、端末内で生成されるランダムな秘密トークンが使われます
* サーバーは中継目的でのみ使用し、開発者による分析や第三者提供は行いません

詳細は以下を参照してください。

[プライバシーポリシー](PRIVACY.md)

## コントリビューション

不具合報告や改善提案は、GitHub Issuesから受け付けています。

変更を提案する場合は、以下の流れでPull Requestを作成してください。

1. このリポジトリをForkする
2. 作業用ブランチを作成する
3. 変更をコミットする
4. Fork先へpushする
5. Pull Requestを作成する

```bash
git switch -c feature/example
git add .
git commit -m "Add example feature"
git push origin feature/example
```

## 注意事項

本アプリは、ボンバーガールのプレイヤーが個人で開発している非公式アプリです。

本アプリおよび本リポジトリは、ボンバーガールの運営会社、開発会社、その他の権利者とは関係ありません。

ゲーム名、キャラクター名、画像、その他の商標・著作物に関する権利は、それぞれの権利者に帰属します。

## ライセンス

本リポジトリのソースコードを利用・複製・改変・再配布できる条件は、リポジトリ内のライセンスファイルを確認してください。

ライセンスファイルが存在しない場合、著作権法上、第三者にソースコードの利用・改変・再配布を許可したことにはなりません。

Copyright © 2026 ICHI
