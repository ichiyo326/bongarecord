import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var players: [PlayerInfo]
    @ObservedObject private var theme = ThemeManager.shared

    /// OBS配信連携用。全戦績を監視し、変化するたびに`StreamOverlaySync`へ
    /// 集計・送信を依頼する（配信ONの間のみ実際に送信される）。
    /// ContentViewはアプリ起動中ずっと生存するNavigationStackのルートなので、
    /// どの画面で戦績を登録・修正しても確実に検知できる箇所としてここに置く。
    @Query(sort: \BattleRecord.dateTimestamp, order: .reverse) private var allBattleRecords: [BattleRecord]
    @ObservedObject private var streamSync = StreamOverlaySync.shared
    /// ロック画面／Dynamic Islandの「今日の戦績」表示用（ONの間だけ実際に更新される）。
    @ObservedObject private var liveActivity = LiveActivityManager.shared
    /// 通算勝利数・連勝数の節目通知用（ONの間だけ実際に通知される）。
    @ObservedObject private var achievementNotifier = AchievementNotifier.shared

    /// 「修正／編集タブに切り替わらない」バグの根本原因だった箇所。
    /// 以前は `NavigationLink(destination: RecordHubView())` のように遷移先を値として
    /// 渡していたため、ThemeManagerの@Publishedが更新されるたびにContentView.bodyが
    /// 再評価され、既にプッシュ済みの画面まで新しい値として再構築されて@State
    /// （SegmentedHubの表示中タブ等）がリセットされていた。
    /// その後トレイリングクロージャ形式の`NavigationLink{}label:{}`は
    /// ToolbarContentBuilderと衝突し、`NavigationLink(value:)`+switch式の
    /// `.navigationDestination(for:)`はViewBuilderの型推論で「Ambiguous use of
    /// 'init()'」という紛らわしいエラーになった。どちらもSwiftの型推論とSwiftUIの
    /// ビルダーが複雑に絡むケースで、原因の特定・再現が難しい。
    /// そのため、画面ごとに個別の`Bool`と`.navigationDestination(isPresented:)`を
    /// 素朴に並べる最も単純な形にした。……はずが、同じ形の`.navigationDestination`を
    /// 7個そのまま1つの式としてチェーンすると、今度は式全体が複雑すぎてSwiftの型推論が
    /// 音を上げ、無関係な行を指して「Ambiguous use of 'init()'」を吐くようになった
    /// （どの行が名指しされるかがビルドのたびに変わるのはこれが理由）。
    /// 対策として、7個をまとめて1つの式にせず、各ボタン1つ1つに
    /// `.navigationDestination`を直接くっつける形に分割した。これで一度に
    /// 型推論する式が2〜3段程度に収まり、迷う余地がなくなる。
    @State private var showRecord = false
    @State private var showStats = false
    @State private var showProfile = false
    @State private var showMatsubi = false
    @State private var showStreamSettings = false
    @State private var showSettings = false
    @State private var showThemeSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                PuzzleBackground()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            menuButton("戦績登録／修正")         { showRecord = true }
                                .navigationDestination(isPresented: $showRecord) { RecordHubView() }

                            menuButton("戦績表示")                { showStats = true }
                                .navigationDestination(isPresented: $showStats) { BattleStatsView() }

                            menuButton("プロフィール")            { showProfile = true }
                                .navigationDestination(isPresented: $showProfile) { ProfileHubView() }

                            menuButton("末尾通知")              { showMatsubi = true }
                                .navigationDestination(isPresented: $showMatsubi) { MatsubiNotificationView() }

                            menuButton("配信連携（OBS）")        { showStreamSettings = true }
                                .navigationDestination(isPresented: $showStreamSettings) { StreamSettingsView() }

                            // 「マップ／キャラ管理」「引継ぎデータ作成／取込」「ライブアクティビティ」
                            // 「実績通知」をここに集約。中身（各画面）は変更していない。
                            menuButton("設定")                  { showSettings = true }
                                .navigationDestination(isPresented: $showSettings) { SettingsHubView() }
                        }
                        .padding()
                    }
                }
            }
            .bongaNavigationBar(title: "ボンガレコード")
            .toolbar { themeToolbarContent }
            // navigationDestinationはツールバー項目ではなく、NavigationStackの
            // コンテンツ階層側（ZStack）に付ける方が確実に動く。
            .navigationDestination(isPresented: $showThemeSettings) { ThemeSettingsView() }
        }
        .preferredColorScheme(effectiveColorScheme)
        .fontDesign(theme.fontDesign)
        // 戦績が変化するたび（登録・修正・削除）に、各連携機能へ最新状態を反映し直す。
        .onChange(of: allBattleRecords) { _, newRecords in
            streamSync.recomputeAndPush(records: newRecords)
            liveActivity.update(records: newRecords)
            achievementNotifier.checkAndNotify(records: newRecords)
        }
        .task {
            // アプリ起動直後、各機能がONのままだった場合に最新状態へ追いつかせる。
            streamSync.recomputeAndPush(records: allBattleRecords)
            liveActivity.update(records: allBattleRecords)
        }
    }

    /// ツールバーの中身を別のcomputed propertyに切り出し、戻り値の型を
    /// `some ToolbarContent`と明示しておく。`.toolbar { ... }`の場でクロージャの
    /// 中身をその場で型推論させると、SwiftUIの`toolbar(content:)`には
    /// `ToolbarContent`版と`View`版の2つの似たオーバーロードがあるため、
    /// 中身が少し複雑になっただけで「Ambiguous use of 'toolbar(content:)'」に
    /// なることがあった。戻り値の型を先に確定させることで曖昧さを無くす。
    @ToolbarContentBuilder
    private var themeToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showThemeSettings = true
            } label: {
                Image(systemName: "paintpalette")
            }
            .accessibilityLabel("テーマ設定")
        }
    }

    /// 適用するカラースキーム。
    /// カスタム背景色があればその明暗を優先、なければプレイヤー設定（既定ライト）に従う。
    private var effectiveColorScheme: ColorScheme? {
        if let scheme = theme.backgroundColorScheme { return scheme }
        if let pi = players.first { return pi.theme == .dark ? .dark : .light }
        return nil
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.bongaOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.bongaPurple)
                .cornerRadius(6)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [BattleRecord.self, PlayerInfo.self, MapPreference.self, CharacterPreference.self], inMemory: true)
}
