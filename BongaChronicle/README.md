# ボンガクロニクル iOS版（SwiftData + CloudKit）

Android版ボンガクロニクルのSwiftUI移植実装。
**iCloud自動同期対応**、**100万行データ対応**、**完全ローカルファースト**設計。

---

## 設計の特徴

| 項目 | 採用技術 / 仕様 |
|---|---|
| 永続化 | **SwiftData**（裏側はSQLite） |
| クラウド同期 | **CloudKit**（`cloudKitDatabase: .automatic`） |
| データモデル | マップ・キャラを**IDで参照**して行サイズを圧縮 |
| 1行のサイズ | 約30〜40バイト（メタデータ込み） |
| 100万行想定時の容量 | 約30〜40MB |
| 検索 | `FetchDescriptor` + `#Predicate` でSQL層フィルタ |
| 集計 | `fetchCount` でCOUNT(*)、メモリにロードしない |
| オフライン動作 | 完全対応（CloudKitは接続時のみ同期） |
| 信頼性・可用性 | 端末ローカルが正本、iCloudは透過バックアップ |

---

## 環境要件

- **Xcode**: 15.0 以降（iOS 17 SDKのため）
- **iOS デプロイメントターゲット**: **iOS 17.0 以上**（SwiftData要件、17.4+推奨）
- **Apple Developer Program**: CloudKit利用に必要（無料アカウントでも個人開発は可）
- **iCloudアカウント**: 実機テスト時、端末にiCloudサインインが必要

---

## セットアップ手順

### 1. Xcodeプロジェクト作成

1. Xcode → "Create New Project..." → **iOS → App**
2. 設定:
    - Product Name: `BongaChronicle`
    - Interface: **SwiftUI**
    - Language: **Swift**
    - Storage: **None**（SwiftDataを後から手動設定）
    - Include Tests: 任意
3. Bundle Identifier を一意な値に（例: `com.yourname.BongaChronicle`）

### 2. デプロイメントターゲット設定

- TARGETS → General → **Minimum Deployments** → `iOS 17.0`

### 3. iCloud / CloudKit Capability 追加（重要）

1. TARGETS → **Signing & Capabilities** タブを開く
2. 左上 **「+ Capability」** をクリック
3. **iCloud** を追加
4. iCloud のセクションで:
    - ✅ **CloudKit** にチェック
    - **Containers** で `+` を押し、自動生成された `iCloud.com.yourname.BongaChronicle` をそのまま使う（または独自名で作成）
5. **+ Capability** を再度クリック → **Background Modes** を追加
    - ✅ **Remote notifications** にチェック（CloudKitの変更通知用）
6. Signing で Team を選択（無料Apple IDでも可）

> **トラブルシュート**: "Failed to register Bundle ID" が出る場合は Bundle Identifier を変更（既存と衝突）

### 4. ソースコードの配置

このフォルダのSwiftファイルすべてをXcodeの `BongaChronicle` グループにドラッグ＆ドロップ。

```
BongaChronicle/
├── BongaChronicleApp.swift       ← Xcode自動生成と差し替え
├── Models/
│   ├── BattleRecord.swift
│   ├── PlayerInfo.swift
│   └── MasterData.swift
├── Storage/
│   └── CSVManager.swift
├── Theme/
│   └── Colors.swift
└── Views/
    ├── ContentView.swift          ← Xcode自動生成と差し替え
    ├── BattleRegistrationView.swift
    ├── BattleEditView.swift
    ├── BattleStatsView.swift
    ├── ProfileView.swift
    ├── PlayerInfoEditView.swift
    ├── DataTransferView.swift
    └── Components/
        ├── PuzzleBackground.swift
        ├── CommonComponents.swift
        └── RadarChartView.swift
```

> **重要**: ドラッグ追加時に "Copy items if needed" にチェック、"Create groups" を選択。

### 5. ビルド & 実行

- シミュレータでも動作するが、**CloudKit同期は実機推奨**
- 実機の **設定 → Apple ID → iCloud → このAppを使用** をON
- 同じiCloudアカウントの別端末（iPad等）で開けば自動同期される

---

## データ設計の根拠

### 1行あたりの想定サイズ

| フィールド | 型 | バイト |
|---|---|---|
| dateTimestamp | Int64 | 8 |
| mapId | Int | 8 |
| characterId | Int | 8 |
| resultRaw | Int | 8 |
| SwiftDataメタデータ | - | 約10〜20 |
| **小計** | | **約40〜50バイト** |

100万行で **約40〜50MB** → iCloud標準5GBの1%以下に収まる。

> もし更にサイズを絞りたい場合、`Int` を `Int16` に変更可能（マップ48・キャラ33ともInt16範囲）。ただしSwiftData/CloudKit互換性のため `Int` のままを推奨。

### なぜマップ名・キャラ名を直接保存しないか

例: 文字列「パニックアイランド 岩礁」は16バイト、IDなら8バイト（差は8バイト/行）。
- 100万行で **8MB節約**
- マップ名の表記変更にもマスター側だけ更新すればよく、戦績データは触らなくて済む
- 検索が **文字列比較ではなく整数比較**になり高速

---

## CloudKit同期の挙動

### 同期される
- 戦績データ（`BattleRecord`）
- プレイヤー情報（`PlayerInfo`）

### 同期されない
- マスターデータ（マップ・キャラ一覧）→ コード内に定義、アプリ更新で配布
- アプリ設定（端末固有のUI状態など）

### 競合解決

CloudKit は **last-writer-wins** で自動解決する。`PlayerInfo` は複数端末で同時編集すると単純上書きになるが、`lastModified` フィールドを持たせているので必要に応じてアプリ側で詳細な競合解決を実装可能。

### 同期タイミング

- アプリのフォアグラウンド復帰時
- ネットワーク接続時
- バックグラウンドプッシュ（Background Modes に Remote notifications を入れたため）

---

## パフォーマンス上の工夫

| 場面 | 工夫 |
|---|---|
| 戦績修正の検索 | `FetchDescriptor` で `fetchLimit = 200` を指定し、全件メモリロードを回避 |
| 戦績表示の集計 | `#Predicate` で日付/マップ/キャラで絞り込んだ後に集計 |
| プロフィールの練度算出 | `fetchCount` を33キャラ × 2クエリで実行（SQLのCOUNT(*)に翻訳される） |
| CSV取込 | バッチinsert、`context.delete(model:)`で既存全削除を一発実行 |

100万行データでも:
- 戦績登録: 即時（O(1) insert）
- 戦績検索: 数十〜数百ms（インデックスは未設定、必要に応じて `@Attribute(.spotlight)` 検討）
- 戦績表示: 数百ms〜数秒（絞り込み次第）
- プロフィール: 1〜2秒程度（66クエリの並列化で改善余地あり）

---

## 既知の暫定実装ポイント

要件ドキュメント未確定事項の暫定処理:

1. **キャラ練度算出**: 試合数×勝率で S/A/B/C/D を判定（`ProfileView.rank()`）
2. **お気に入りマップの用途**: データのみ保持（プロフィールに非表示）
3. **削除確認ダイアログ**: iOS HIGに従って追加（Android版になくても）

---

## カスタマイズポイント

- **メインカラー**: `Theme/Colors.swift` の `bongaPurple`
- **練度算出ロジック**: `Views/ProfileView.swift` の `rank(games:wins:)`
- **マスターデータ**: `Models/MasterData.swift` の `characterDefs` / `mapDefs`
- **CSV形式**: `Storage/CSVManager.swift`（Android版の実フォーマットが判明したら調整）
- **検索結果の上限**: `Views/BattleEditView.swift` の `fetchLimit`
