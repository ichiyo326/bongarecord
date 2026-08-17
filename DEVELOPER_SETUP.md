# 配信連携（OBS）— 開発者が一度だけ行う設定

これは**アプリを使うユーザー全員には不要**な作業です。開発者（あなた）が
リリース前に1回だけ済ませれば、以降ユーザーはアプリ内の「OBS用ファイルを
書き出す」→ OBSのパソコンに送る、だけで使えます。Webサイトのホスティングは
一切不要です（overlay.htmlの中身はアプリ内にテンプレートとして同梱済みで、
ユーザーごとのファイルをその場で生成して共有シートで渡す方式にしてあります）。

やることは1つだけです。

## Firebase Realtime Database のルールを確認する

すでに `arcade-81ba0-default-rtdb.firebaseio.com` を使う前提でコードを書いてあります
（`StreamOverlaySync.swift` の `StreamBackendConfig.firebaseRTDBBaseURL`）。
別のFirebaseプロジェクトを使いたい場合は、この値を書き換えてください。

Firebaseコンソール → 該当プロジェクト → Realtime Database →「ルール」タブに、
以下がすでに設定されているか確認し、なければ貼り付けて「公開」してください
（最初の1回だけでよく、ユーザーが増えても変更不要です）。

```json
{
  "rules": {
    "bongaRecordStreams": {
      "$token": {
        ".read": true,
        ".write": true
      }
    }
  }
}
```

ユーザーごとに `secretToken`（推測されにくいランダム文字列）でパスが分かれるので、
1つのFirebaseプロジェクトを全ユーザーで共有して問題ありません。

以上です。Webホスティングの用意（Netlify / Firebase Hosting / GitHub Pages など）は
不要になりました。

---

## 補足：今までの `overlay.html` との違い

- v1: ユーザーごとにFirebaseプロジェクトを作らせ、`overlay.html`を手編集させていた。
- v2: 共有Firebaseにしたが、`overlay.html`を開発者がどこかのサイトにホスティングする
  作業が必要だった。
- v3（現在）: `overlay.html`の中身をアプリ内にテンプレート文字列として同梱
  （`StreamOverlaySync.swift`内 `OverlayHTMLTemplate`）。ユーザーの秘密トークンを
  埋め込んだ専用HTMLをアプリがその場で生成し、共有シート（AirDrop / ファイルに保存など）
  で渡す。OBS側は「ローカルファイル」オプションでそのまま使える。外部ホスティングは
  一切不要。

プロジェクト直下の `overlay.html` はこれまでの経緯として参考に残していますが、
アプリはもう参照していません（同じ内容が `StreamOverlaySync.swift` 内に
埋め込まれています）。
