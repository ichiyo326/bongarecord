import Foundation
import Combine

// MARK: - OBS配信連携(Firebase Realtime Database中継)

/// アプリ内の戦績を「配信セッション中の勝敗数・勝率・連勝連敗」に集計し、
/// Firebase Realtime Database（RTDB）へリアルタイムで送信するサービス。
///
/// **設計方針(なぜFirebase RTDB経由か)**:
/// OBSを動かすPCは配信のたびに変わりうる（自宅PC・持参ノートPC・店舗PCなど）ため、
/// iPhoneとOBS PCが同じローカルネットワークにあることを前提にできない。
/// そのため「iPhone → インターネット上の中継地点 → OBS（Browser Source）」という
/// 経路にし、OBS側は決まったファイルをブラウザソースに登録するだけで動くようにしている。
///
/// **v3での変更（アプリだけで完結・外部ホスティング不要）**:
/// v1はユーザーごとにFirebaseプロジェクトを作らせていた。v2は共有Firebaseにしたが、
/// overlay.htmlを開発者がどこかのWebサイトにホスティングする作業が必要だった。
/// v3では、overlay.htmlの中身をアプリ内にテンプレート文字列として同梱し、
/// ユーザーの秘密トークンを埋め込んだ「その人専用のHTMLファイル」をアプリが
/// その場で生成する。ユーザーはそれをAirDropや「ファイル」に保存してOBSを動かす
/// パソコンへ送り、OBSの「ローカルファイル」で指定するだけでよい。
/// これにより、Webサイトの用意（Netlify/Firebase Hosting等）が一切不要になる。
///
/// RTDBは「経路の中継地点」としてのみ使用し、認証はランダムな`secretToken`を
/// パスの一部に含めることで代替する簡易的なものである（本格的な機密データを
/// 扱うものではないため、この程度の秘匿性で許容している）。
@MainActor
final class StreamOverlaySync: ObservableObject {
    static let shared = StreamOverlaySync()

    // MARK: - 永続設定

    /// 誰にも推測されないランダムな秘密トークン（生成するHTMLに埋め込む）
    @Published var secretToken: String {
        didSet { UserDefaults.standard.set(secretToken, forKey: Key.secretToken) }
    }

    /// 配信中かどうか（ONの間だけ戦績変化を都度送信する）
    @Published private(set) var isStreaming: Bool {
        didSet { UserDefaults.standard.set(isStreaming, forKey: Key.isStreaming) }
    }

    /// 直近の送信結果（UI表示用）
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    /// 配信セッションの起点（この時刻以降の記録だけを集計する）
    private var sessionStartTimestamp: Int64 {
        didSet { UserDefaults.standard.set(sessionStartTimestamp, forKey: Key.sessionStart) }
    }

    private enum Key {
        static let secretToken  = "streamSync.secretToken"
        static let isStreaming  = "streamSync.isStreaming"
        static let sessionStart = "streamSync.sessionStart"
    }

    private init() {
        let d = UserDefaults.standard
        secretToken = d.string(forKey: Key.secretToken) ?? StreamOverlaySync.makeToken()
        isStreaming = d.bool(forKey: Key.isStreaming)
        sessionStartTimestamp = d.object(forKey: Key.sessionStart) != nil
            ? Int64(d.integer(forKey: Key.sessionStart))
            : Int64(Date().timeIntervalSince1970)
        UserDefaults.standard.set(secretToken, forKey: Key.secretToken)
    }

    // MARK: - トークン生成

    static func makeToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// ファイルが漏れた・第三者に渡ってしまった場合などに、ユーザー自身で
    /// トークンを作り直せるようにする。再生成後は「OBS用ファイルを書き出す」で
    /// 新しいファイルを作り直し、OBS側にも設定し直してもらう必要がある。
    func regenerateToken() {
        secretToken = StreamOverlaySync.makeToken()
    }

    // MARK: - セッション制御

    /// 配信を開始する。以降に記録した試合のみが集計対象になる（それ以前の戦績は含めない）。
    func startStreaming() {
        sessionStartTimestamp = Int64(Date().timeIntervalSince1970)
        isStreaming = true
    }

    func stopStreaming() {
        isStreaming = false
    }

    /// 現在の集計対象期間の開始日時（設定画面での表示用）
    var sessionStartDate: Date {
        Date(timeIntervalSince1970: TimeInterval(sessionStartTimestamp))
    }

    // MARK: - 送信先URL（アプリ→中継地点。内部処理用でユーザーには見せない）

    /// OBS用HTMLファイルが読みに行くデータURL（中継地点そのもの）。
    /// 共有のFirebaseプロジェクトを使うため、ユーザーが入力する必要はない。
    var endpointURL: URL? {
        guard !secretToken.isEmpty else { return nil }
        return URL(string: "\(StreamBackendConfig.firebaseRTDBBaseURL)/bongaRecordStreams/\(secretToken).json")
    }

    // MARK: - OBS用HTMLファイルの生成（アプリだけで完結）

    /// アプリに同梱のテンプレートへ、このユーザー専用の`endpointURL`を埋め込んだ
    /// HTML文字列を返す。外部サイトへのホスティングは不要で、このファイルを
    /// そのままOBSの「ローカルファイル」として使う。
    func generateOverlayHTML() -> String? {
        guard let url = endpointURL else { return nil }
        return OverlayHTMLTemplate.source.replacingOccurrences(
            of: OverlayHTMLTemplate.placeholder,
            with: url.absoluteString
        )
    }

    /// 生成したHTMLを一時ファイルに書き出し、共有シート（AirDrop/ファイルに保存 等）で
    /// 渡せるURLを返す。呼ぶたびに同じファイル名を上書きする。
    func writeOverlayHTMLFile() -> URL? {
        guard let html = generateOverlayHTML() else { return nil }
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("ボンガレコード配信オーバーレイ.html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            lastError = "ファイルの書き出しに失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 集計＆送信

    /// `records`は全戦績（新しい順・古い順どちらでも可）。配信中のときだけ送信する。
    func recomputeAndPush(records: [BattleRecord]) {
        guard isStreaming, let url = endpointURL else { return }

        let snapshot = BattleStatsSnapshot.compute(from: records, since: sessionStartTimestamp)

        let payload: [String: Any] = [
            "wins": snapshot.wins,
            "losses": snapshot.losses,
            "draws": snapshot.draws,
            "winRate": snapshot.winRate,
            "streakCount": snapshot.streakCount,
            "streakType": snapshot.streakType.rawValue,
            "sessionStart": sessionStartTimestamp,
            "updatedAt": Int64(Date().timeIntervalSince1970)
        ]

        send(payload: payload, to: url)
    }

    /// `URLSession`の completionHandler 版は、そのクロージャ自体が `@Sendable`
    /// （メインアクターから切り離された文脈で実行される）であるため、`[weak self]`で
    /// MainActor隔離クラスである`self`を直接キャプチャすると
    /// 「Reference to captured var 'self' in concurrently-executing code」という
    /// Swift 6のエラーになる。`URLSession.data(for:)`のasync/await版を使い、
    /// このメソッド自身（MainActor隔離）の中で`await`するようにすれば、`self`への
    /// アクセスは常にMainActor上で行われるため、この問題が起きない。
    private func send(payload: [String: Any], to url: URL) {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.lastError = "送信に失敗しました（しばらくしてから配信を開始し直してください）"
                    return
                }
                self.lastError = nil
                self.lastSyncedAt = Date()
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - 共有バックエンド設定（開発者がアプリリリース前に1回だけ設定する）

/// ユーザーには一切見せない、アプリ全体で共有する設定値。
///
/// `firebaseRTDBBaseURL`: 開発者が用意したFirebase Realtime DatabaseのベースURL。
/// 全ユーザーが `/bongaRecordStreams/{その人のsecretToken}` という別々のパスに
/// 書き込むため、1つのFirebaseプロジェクトを全ユーザーで共有してよい。
/// Firebaseコンソール → Realtime Database →「ルール」タブに、以下を設定しておくこと
/// （最初の1回だけでよく、ユーザーが増えても変更不要）。
/// ```json
/// {
///   "rules": {
///     "bongaRecordStreams": {
///       "$token": { ".read": true, ".write": true }
///     }
///   }
/// }
/// ```
enum StreamBackendConfig {
    static let firebaseRTDBBaseURL = "https://arcade-81ba0-default-rtdb.firebaseio.com"
}

// MARK: - OBS用HTMLテンプレート（アプリに同梱・ユーザーは編集不要）

/// 元は `overlay.html` として同梱していたファイルと同じ内容。
/// `placeholder` の部分だけをユーザーごとの `endpointURL` に置き換えて書き出す。
/// Web上へのホスティングは不要で、OBSの「ローカルファイル」オプションで直接使える。
enum OverlayHTMLTemplate {
    static let placeholder = "__BONGA_RECORD_ENDPOINT_URL__"

    static let source = """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
    <meta charset="UTF-8">
    <title>ボンガレコード 配信オーバーレイ</title>
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: transparent; /* OBS Browser Sourceで透過表示するため */
        font-family: "Hiragino Sans", "Yu Gothic", sans-serif;
        -webkit-font-smoothing: antialiased;
      }

      #card {
        display: inline-flex;
        flex-direction: column;
        gap: 6px;
        padding: 14px 20px;
        border-radius: 14px;
        background: rgba(20, 10, 40, 0.72);
        border: 2px solid #5500FF;
        box-shadow: 0 4px 18px rgba(0,0,0,0.35);
        color: #ffffff;
        min-width: 260px;
      }

      #title {
        font-size: 13px;
        letter-spacing: 2px;
        color: #c9b3ff;
        text-transform: uppercase;
      }

      #mainLine {
        font-size: 30px;
        font-weight: 800;
        display: flex;
        align-items: baseline;
        gap: 10px;
      }

      #winRate {
        font-size: 18px;
        font-weight: 600;
        color: #38CFC4;
      }

      #streakLine {
        font-size: 16px;
        font-weight: 700;
      }

      .streak-win  { color: #38CFC4; }
      .streak-lose { color: #ff6b81; }
      .streak-none { color: #999999; }

      #status {
        font-size: 10px;
        color: #7a7a7a;
        margin-top: 2px;
      }
    </style>
    </head>
    <body>
      <div id="card">
        <div id="title">BONGA RECORD LIVE</div>
        <div id="mainLine">
          <span id="score">- 勝 - 敗 - 分</span>
          <span id="winRate"></span>
        </div>
        <div id="streakLine"></div>
        <div id="status">接続中...</div>
      </div>

    <script>
    // このファイルはボンガレコードのアプリが自動生成したものです。
    // 編集は不要です。OBSの「ソース」→「＋」→「ブラウザ」→「ローカルファイル」に
    // チェックを入れて、このファイルを指定するだけで動きます。

    const DATA_URL = "__BONGA_RECORD_ENDPOINT_URL__";
    const POLL_INTERVAL_MS = 1500;

    const scoreEl    = document.getElementById("score");
    const winRateEl  = document.getElementById("winRate");
    const streakEl   = document.getElementById("streakLine");
    const statusEl   = document.getElementById("status");

    function renderStreak(count, type) {
      if (!count || type === "none") {
        streakEl.textContent = "";
        streakEl.className = "";
        return;
      }
      if (type === "win") {
        streakEl.textContent = `${count}連勝中 🔥`;
        streakEl.className = "streak-win";
      } else {
        streakEl.textContent = `${count}連敗中...`;
        streakEl.className = "streak-lose";
      }
    }

    async function poll() {
      try {
        const res = await fetch(DATA_URL, { cache: "no-store" });
        if (!res.ok) throw new Error("HTTP " + res.status);
        const data = await res.json();
        if (!data) {
          statusEl.textContent = "データ待機中（アプリ側で「配信を開始」してください）";
          return;
        }
        const wins   = data.wins   ?? 0;
        const losses = data.losses ?? 0;
        const draws  = data.draws  ?? 0;
        const winRate = data.winRate ?? 0;

        scoreEl.textContent = `${wins}勝 ${losses}敗 ${draws}分`;
        winRateEl.textContent = (wins + losses) > 0 ? `勝率 ${winRate}%` : "";
        renderStreak(data.streakCount, data.streakType);

        const updatedAt = data.updatedAt ? new Date(data.updatedAt * 1000) : null;
        statusEl.textContent = updatedAt
          ? `最終更新 ${updatedAt.toLocaleTimeString("ja-JP")}`
          : "接続済み";
      } catch (e) {
        statusEl.textContent = "取得エラー: " + e.message;
      }
    }

    poll();
    setInterval(poll, POLL_INTERVAL_MS);
    </script>
    </body>
    </html>
    """
}
