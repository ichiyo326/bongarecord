import SwiftUI
import UIKit
import Combine
import CoreImage

/// ユーザーがカスタマイズした配色・書体・背景画像を保持する。
///
/// 各値は「未設定 = nil」で、その場合は `Defaults` の既定値（＝従来のアプリ配色）に
/// フォールバックする。これにより、ユーザーが触っていない項目は従来通り（背景の
/// systemBackground のようにライト/ダークへ追従する動的色）を維持できる。
///
/// 値は UserDefaults（端末内のみ・iCloud非同期）に永続化。背景画像も同様に
/// アプリのApplication Supportディレクトリへファイルとして保存するのみで、
/// SwiftData/CloudKitの同期対象には含めない（画像は他端末には反映されない）。
/// `@Published` なので、監視しているビュー（ホーム・配色設定画面）は
/// 変更するとライブで再描画される。
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var accent: Color?      { didSet { save(accent,      Key.accent) } }
    @Published var onAccent: Color?    { didSet { save(onAccent,    Key.onAccent) } }
    @Published var background: Color?  { didSet { save(background,   Key.background) } }
    @Published var icon: Color?        { didSet { save(icon,        Key.icon) } }
    @Published var tableHeader: Color? { didSet { save(tableHeader, Key.tableHeader) } }

    /// 文字のデザイン（標準／丸め／明朝風／等幅）。nil = 標準。
    @Published var fontDesign: Font.Design? { didSet { saveFontDesign() } }

    /// 文字の太さ（標準／細め／少し太め／太め／極太）。nil = 標準。
    /// `fontDesign`だけだと4種類しかなく、特に日本語では書体によって見た目の違いが
    /// 小さいことがあるため、太さの軸を組み合わせてバリエーションを増やしている。
    @Published var fontWeight: Font.Weight? { didSet { saveFontWeight() } }

    /// ユーザーが設定した背景画像（クロップ済み・メモリキャッシュ）。nil ならパズル柄背景を使う。
    @Published private(set) var backgroundImage: UIImage?

    /// クロップ前の元画像（メモリキャッシュ）。「範囲を調整」で編集画面を再度開くときに使う。
    /// これが無いと、既にクロップ・圧縮済みの`backgroundImage`を再度クロップすることになり、
    /// 調整するたびに選べる範囲が狭まり画質も落ちていく問題があった。
    @Published private(set) var backgroundSourceImage: UIImage?

    /// 実際に画面へ表示する背景画像。`backgroundBlurEnabled`がtrueなら`backgroundImage`を
    /// あらかじめぼかしたもの、falseなら`backgroundImage`そのもの。
    ///
    /// ぼかしをSwiftUIの`.blur(radius:)`修飾子でライブに適用すると、
    /// `CMPhotoCompressionSession`がメインスレッドでデッドロックする既知の不具合があるため
    /// （カレンダー画面の背景実装で判明した問題）、ここでは一度だけオフスクリーンで
    /// ぼかし処理をした画像をキャッシュし、表示側は普通の`Image`として扱う。
    @Published private(set) var displayBackgroundImage: UIImage?

    /// 背景画像の平均輝度から判定した「暗い画像か」。ユーザーが背景色を明示的に
    /// 指定していないとき、画面全体の配色（ライト/ダーク）をこれに合わせて自動調整する。
    @Published private(set) var backgroundImageIsDark: Bool?

    /// 背景画像の色相から提案する、視認性を確保した目安のアクセント色。
    /// ユーザーがアクセント色を明示的に指定していないときのフォールバックとして使う
    /// （明示的に指定すればいつでもそちらが優先される）。
    @Published private(set) var backgroundImageAccent: Color?

    /// 背景画像を暗く/明るく落として文字を読みやすくするか（既定では有効）
    @Published var backgroundDimEnabled: Bool = true { didSet { store.set(backgroundDimEnabled, forKey: Key.backgroundDimEnabled) } }

    /// ↑の濃さ（0=無し 〜 1=画像がほぼ見えなくなる）
    @Published var backgroundDimOpacity: Double = 0.7 { didSet { store.set(backgroundDimOpacity, forKey: Key.backgroundDimOpacity) } }

    /// 背景画像にぼかしを入れるか（既定では無効。写真をくっきり見せたい人もいるため）
    @Published var backgroundBlurEnabled: Bool = false {
        didSet {
            store.set(backgroundBlurEnabled, forKey: Key.backgroundBlurEnabled)
            refreshBackgroundDerivedState()
        }
    }

    /// ぼかしの強さ
    @Published var backgroundBlurRadius: Double = 14 {
        didSet {
            store.set(backgroundBlurRadius, forKey: Key.backgroundBlurRadius)
            if backgroundBlurEnabled { refreshBackgroundDerivedState() }
        }
    }

    /// 背景画像のファイル名（UserDefaultsに保存するのはファイル名のみ。実体はディスク）
    private var backgroundImageFileName: String? {
        didSet { save(backgroundImageFileName, Key.backgroundImageFileName) }
    }

    /// 元画像のファイル名
    private var backgroundSourceImageFileName: String? {
        didSet { save(backgroundSourceImageFileName, Key.backgroundSourceImageFileName) }
    }

    /// 既定色（従来のアプリ配色）
    enum Defaults {
        static let accent      = Color(red: 85/255,  green: 0/255,   blue: 255/255)
        static let onAccent    = Color.white
        static let background   = Color(uiColor: .systemBackground)
        static let icon        = Color(red: 85/255,  green: 0/255,   blue: 255/255)
        static let tableHeader = Color(red: 200/255, green: 240/255, blue: 240/255)
    }

    /// プリセット（配色＋書体の完成品セット）。背景画像は上書きしない
    /// （ユーザーが選んだ画像を尊重するため）。
    /// 色の系統名で10種類用意し、明るい配色7種・暗い配色3種のバランスにしてある。
    enum Preset: String, CaseIterable, Identifiable {
        case pastelPink
        case mint
        case lavender
        case coral
        case iceBlue
        case monotone
        case sunset
        case navyNight
        case forest
        case cyberMagenta

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pastelPink:   return "パステルピンク"
            case .mint:         return "ミント"
            case .lavender:     return "ラベンダー"
            case .coral:        return "コーラル"
            case .iceBlue:      return "アイスブルー"
            case .monotone:     return "モノトーン"
            case .sunset:       return "サンセット"
            case .navyNight:    return "ネイビーナイト"
            case .forest:       return "フォレスト"
            case .cyberMagenta: return "サイバーマゼンタ"
            }
        }

        var accent: Color {
            switch self {
            case .pastelPink:   return Color(red: 1.00, green: 0.52, blue: 0.63)
            case .mint:         return Color(red: 0.15, green: 0.71, blue: 0.57)
            case .lavender:     return Color(red: 0.55, green: 0.43, blue: 1.00)
            case .coral:        return Color(red: 1.00, green: 0.44, blue: 0.38)
            case .iceBlue:      return Color(red: 0.23, green: 0.59, blue: 0.88)
            case .monotone:     return Color(red: 0.20, green: 0.20, blue: 0.22)
            case .sunset:       return Color(red: 1.00, green: 0.58, blue: 0.24)
            case .navyNight:    return Color(red: 0.25, green: 0.78, blue: 1.00)
            case .forest:       return Color(red: 0.35, green: 0.78, blue: 0.51)
            case .cyberMagenta: return Color(red: 1.00, green: 0.16, blue: 0.65)
            }
        }
        var onAccent: Color { .white }
        var icon: Color { accent }
        var background: Color {
            switch self {
            case .pastelPink:   return Color(red: 1.00, green: 0.96, blue: 0.97)
            case .mint:         return Color(red: 0.94, green: 0.98, blue: 0.97)
            case .lavender:     return Color(red: 0.97, green: 0.96, blue: 1.00)
            case .coral:        return Color(red: 1.00, green: 0.97, blue: 0.96)
            case .iceBlue:      return Color(red: 0.94, green: 0.97, blue: 1.00)
            case .monotone:     return Color(red: 0.96, green: 0.96, blue: 0.97)
            case .sunset:       return Color(red: 1.00, green: 0.95, blue: 0.90)
            case .navyNight:    return Color(red: 0.04, green: 0.06, blue: 0.10)
            case .forest:       return Color(red: 0.03, green: 0.08, blue: 0.06)
            case .cyberMagenta: return Color(red: 0.06, green: 0.03, blue: 0.08)
            }
        }
        var tableHeader: Color {
            switch self {
            case .pastelPink:   return Color(red: 1.00, green: 0.85, blue: 0.90)
            case .mint:         return Color(red: 0.78, green: 0.93, blue: 0.89)
            case .lavender:     return Color(red: 0.88, green: 0.85, blue: 0.98)
            case .coral:        return Color(red: 1.00, green: 0.84, blue: 0.80)
            case .iceBlue:      return Color(red: 0.80, green: 0.91, blue: 0.98)
            case .monotone:     return Color(red: 0.88, green: 0.88, blue: 0.90)
            case .sunset:       return Color(red: 1.00, green: 0.84, blue: 0.71)
            case .navyNight:    return Color(red: 0.08, green: 0.16, blue: 0.26)
            case .forest:       return Color(red: 0.08, green: 0.20, blue: 0.14)
            case .cyberMagenta: return Color(red: 0.20, green: 0.08, blue: 0.18)
            }
        }
        /// nil = 標準（`ThemeManager.fontDesign`同様、「未設定=標準」の表記に揃えている。
        /// こうしないと配色設定画面の「文字のデザイン」欄で「標準」にチェックが
        /// 付かなくなってしまう）。
        var fontDesign: Font.Design? {
            switch self {
            case .pastelPink, .coral, .sunset: return .rounded
            case .mint, .lavender, .iceBlue, .monotone: return nil
            case .navyNight, .cyberMagenta: return .monospaced
            case .forest: return .serif
            }
        }
    }

    private enum Key {
        static let accent      = "theme.accent"
        static let onAccent    = "theme.onAccent"
        static let background   = "theme.background"
        static let icon        = "theme.icon"
        static let tableHeader = "theme.tableHeader"
        static let fontDesign  = "theme.fontDesign"
        static let fontWeight  = "theme.fontWeight"
        static let backgroundImageFileName = "theme.backgroundImageFileName"
        static let backgroundSourceImageFileName = "theme.backgroundSourceImageFileName"
        static let backgroundDimEnabled = "theme.backgroundDimEnabled"
        static let backgroundDimOpacity = "theme.backgroundDimOpacity"
        static let backgroundBlurEnabled = "theme.backgroundBlurEnabled"
        static let backgroundBlurRadius = "theme.backgroundBlurRadius"
        static let backgroundImageIsDark = "theme.backgroundImageIsDark"
        static let backgroundImageAccent = "theme.backgroundImageAccent"
    }

    private let store = UserDefaults.standard

    private init() {
        accent      = ThemeManager.load(Key.accent,      from: store)
        onAccent    = ThemeManager.load(Key.onAccent,    from: store)
        background   = ThemeManager.load(Key.background,   from: store)
        icon        = ThemeManager.load(Key.icon,        from: store)
        tableHeader = ThemeManager.load(Key.tableHeader, from: store)
        fontDesign  = ThemeManager.loadFontDesign(from: store)

        let fileName = store.string(forKey: Key.backgroundImageFileName)
        backgroundImageFileName = fileName
        if let fileName {
            let url = ThemeManager.backgroundImagesDirectory.appendingPathComponent(fileName)
            backgroundImage = UIImage(contentsOfFile: url.path)
        }

        let sourceFileName = store.string(forKey: Key.backgroundSourceImageFileName)
        backgroundSourceImageFileName = sourceFileName
        if let sourceFileName {
            let url = ThemeManager.backgroundImagesDirectory.appendingPathComponent(sourceFileName)
            backgroundSourceImage = UIImage(contentsOfFile: url.path)
        }

        fontWeight = ThemeManager.loadFontWeight(from: store)

        if store.object(forKey: Key.backgroundDimEnabled) != nil {
            backgroundDimEnabled = store.bool(forKey: Key.backgroundDimEnabled)
        }
        if store.object(forKey: Key.backgroundDimOpacity) != nil {
            backgroundDimOpacity = store.double(forKey: Key.backgroundDimOpacity)
        }
        if store.object(forKey: Key.backgroundBlurEnabled) != nil {
            backgroundBlurEnabled = store.bool(forKey: Key.backgroundBlurEnabled)
        }
        if store.object(forKey: Key.backgroundBlurRadius) != nil {
            backgroundBlurRadius = store.double(forKey: Key.backgroundBlurRadius)
        }

        // 背景画像の明暗判定・提案アクセント色を起動時に即座に読み込む。
        // これが無いと、アプリ起動直後は解析が終わるまで判定不能（nil）のままになり、
        // 「最初はライト配色で表示 → 少し経ってから画像の暗さに合わせてダーク配色に
        // 切り替わる」という、アプリ全体（ライト/ダーク配色に追従するあらゆる画面）が
        // 一瞬別の見た目になってから戻る、という目に見えるちらつきが発生していた。
        if store.object(forKey: Key.backgroundImageIsDark) != nil {
            backgroundImageIsDark = store.bool(forKey: Key.backgroundImageIsDark)
        }
        backgroundImageAccent = ThemeManager.load(Key.backgroundImageAccent, from: store)

        refreshBackgroundDerivedState()
    }

    /// すべて既定に戻す（配色・書体・背景画像すべて）
    func resetToDefaults() {
        accent = nil
        onAccent = nil
        background = nil
        icon = nil
        tableHeader = nil
        fontDesign = nil
        fontWeight = nil
        backgroundDimEnabled = true
        backgroundDimOpacity = 0.7
        backgroundBlurEnabled = false
        backgroundBlurRadius = 14
        clearBackgroundImage()
    }

    /// プリセットを適用する（配色＋書体のみ。背景画像・背景の見え方設定は変更しない）
    func apply(preset: Preset) {
        accent = preset.accent
        onAccent = preset.onAccent
        icon = preset.icon
        background = preset.background
        tableHeader = preset.tableHeader
        fontDesign = preset.fontDesign
        // 太さ（fontWeight）はプリセットの対象外。プリセット適用後も
        // 「文字の太さ」セクションからいつでも独立して変更できる。
    }

    /// 何か1つでもカスタムされているか
    var isCustomized: Bool {
        accent != nil || onAccent != nil || background != nil || icon != nil
            || tableHeader != nil || fontDesign != nil || fontWeight != nil
            || backgroundImageFileName != nil
            || !backgroundDimEnabled || backgroundDimOpacity != 0.7
            || backgroundBlurEnabled || backgroundBlurRadius != 14
    }

    /// アクセント色の実効値（優先順位：ユーザー指定 ＞ 背景画像から自動抽出 ＞ 既定色）。
    /// ユーザーが一度でも手動で色を選べば`accent`が非nilになり、それが常に優先される。
    var effectiveAccent: Color { accent ?? backgroundImageAccent ?? Defaults.accent }

    /// アイコン色の実効値。優先順位はアクセント色と同様。
    var effectiveIcon: Color { icon ?? backgroundImageAccent ?? accent ?? Defaults.icon }

    /// 背景色から導く、アプリ全体のカラースキーム。
    /// 背景が暗ければ `.dark`、明るければ `.light` を返し、意味色（カード地・薄字・
    /// セグメント等）を背景に合わせて反転させる。背景色を明示指定していない場合、
    /// 背景「画像」が設定されていればその明暗（`backgroundImageIsDark`）を使う。
    /// どちらも未設定なら nil（端末/プレイヤー設定に従う）。
    var backgroundColorScheme: ColorScheme? {
        if let background {
            return background.overlayColorScheme
        }
        if let backgroundImageIsDark {
            return backgroundImageIsDark ? .dark : .light
        }
        return nil
    }

    // MARK: - 背景画像

    /// 背景画像の保存先ディレクトリ（Application Support配下。CloudKit同期対象外）
    static var backgroundImagesDirectory: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 背景画像として保存するときの上限解像度（長辺のピクセル数）。
    /// 現行の主要iPhoneの実解像度（長辺3000px前後）を下回らない値にしてあるため、
    /// 編集画面（`BackgroundImageEditorView`）で選んだ範囲は基本的にそのままの
    /// 画質で保存される。極端に大きい元画像（一眼レフ写真の全体表示など）だけ
    /// この上限で縮小し、端末容量の圧迫を防ぐ。
    static let maxBackgroundDimension: CGFloat = 3000

    /// クロップ前の元画像を保存するときの上限解像度（長辺のピクセル数）。
    /// 「範囲を調整」で編集画面を開き直したときにズームインし直せる余地を残すため、
    /// 表示用の`maxBackgroundDimension`より大きめに取ってある。
    static let maxSourceDimension: CGFloat = 4500

    /// 編集画面で選んだ「表示範囲」（`croppedImage`）と、そのクロップ前の元画像
    /// （`source`）の両方を端末内に保存する。表示範囲はその解像度のまま
    /// （`maxBackgroundDimension`を超える場合だけ縮小）、元画像は「範囲を調整」で
    /// 再クロップできるよう`maxSourceDimension`まで解像度を保って別ファイルに保存する。
    /// これにより、「範囲を調整」を繰り返しても毎回クロップ前の元画像から選び直せるため、
    /// 選べる範囲が狭まったり画質が落ちていったりしない。
    ///
    /// `@MainActor`を明示しているのが重要：内部の`Task.detached`でバックグラウンドに
    /// 処理を逃がした後、`await`から戻ってきた時点でこの関数は必ずメインアクターに
    /// 復帰する。これが無いと、この後に続く`@Published`プロパティへの代入が
    /// メインスレッド以外で起きる可能性があり、Combineの制約（@Publishedの更新は
    /// メインスレッドのみ）に反して未定義動作（画面の一部が描画されない等）を
    /// 引き起こしていた。これが今回の本当の原因だったと思われる。
    @MainActor
    func setBackgroundImage(source: UIImage, croppedImage: UIImage) async {
        let processed: (crop: UIImage, cropJPEG: Data, source: UIImage, sourceJPEG: Data,
                         isDark: Bool?, accent: Color?)?
        processed = await Task.detached(priority: .userInitiated) {
            let cappedCrop = ThemeManager.downscaled(croppedImage, maxDimension: ThemeManager.maxBackgroundDimension)
            let cappedSource = ThemeManager.downscaled(source, maxDimension: ThemeManager.maxSourceDimension)
            guard let cropJPEG = cappedCrop.jpegData(compressionQuality: 0.92),
                  let sourceJPEG = cappedSource.jpegData(compressionQuality: 0.9) else { return nil }
            // 配色の自動調整に使う、クロップ後の画像（＝実際に表示される範囲）の平均輝度・色相
            let luminance = cappedCrop.averageLuminance
            let isDark = luminance.map { $0 < 0.55 }
            let accent = cappedCrop.averageColor?.asSuggestedAccent
            return (cappedCrop, cropJPEG, cappedSource, sourceJPEG, isDark, accent)
        }.value

        guard let processed else { return }

        let newCropName = "bg_\(UUID().uuidString).jpg"
        let newSourceName = "bgsrc_\(UUID().uuidString).jpg"
        let cropURL = ThemeManager.backgroundImagesDirectory.appendingPathComponent(newCropName)
        let sourceURL = ThemeManager.backgroundImagesDirectory.appendingPathComponent(newSourceName)
        do {
            try processed.cropJPEG.write(to: cropURL, options: .atomic)
            try processed.sourceJPEG.write(to: sourceURL, options: .atomic)
        } catch {
            return
        }

        // ここは@MainActorなので、この代入は確実にメインスレッドで実行される
        let oldCropName = backgroundImageFileName
        let oldSourceName = backgroundSourceImageFileName
        backgroundImageFileName = newCropName
        backgroundSourceImageFileName = newSourceName
        backgroundImage = processed.crop
        backgroundSourceImage = processed.source
        backgroundImageIsDark = processed.isDark
        backgroundImageAccent = processed.accent
        // 次回起動時に即読み込めるよう永続化する（起動直後のライト/ダーク切り替わりの
        // ちらつきを防ぐため。詳しくは`init()`のコメントを参照）
        if let isDark = processed.isDark {
            store.set(isDark, forKey: Key.backgroundImageIsDark)
        } else {
            store.removeObject(forKey: Key.backgroundImageIsDark)
        }
        save(processed.accent, Key.backgroundImageAccent)
        if let oldCropName {
            try? FileManager.default.removeItem(
                at: ThemeManager.backgroundImagesDirectory.appendingPathComponent(oldCropName))
        }
        if let oldSourceName {
            try? FileManager.default.removeItem(
                at: ThemeManager.backgroundImagesDirectory.appendingPathComponent(oldSourceName))
        }
        refreshBackgroundDerivedState()
    }

    /// 背景画像を削除し、既定のパズル柄背景に戻す
    func clearBackgroundImage() {
        if let oldName = backgroundImageFileName {
            try? FileManager.default.removeItem(
                at: ThemeManager.backgroundImagesDirectory.appendingPathComponent(oldName))
        }
        if let oldSourceName = backgroundSourceImageFileName {
            try? FileManager.default.removeItem(
                at: ThemeManager.backgroundImagesDirectory.appendingPathComponent(oldSourceName))
        }
        backgroundImageFileName = nil
        backgroundSourceImageFileName = nil
        backgroundImage = nil
        backgroundSourceImage = nil
        backgroundImageIsDark = nil
        backgroundImageAccent = nil
        displayBackgroundImage = nil
        store.removeObject(forKey: Key.backgroundImageIsDark)
        store.removeObject(forKey: Key.backgroundImageAccent)
    }

    /// `displayBackgroundImage`（実際に画面へ出す背景画像）を最新の状態に作り直す。
    ///
    /// 重要：ぼかしが有効なときも、まず`backgroundImage`（シャープな画像）を
    /// 即座に暫定表示してから、非同期でぼかし済み画像に差し替える。以前はぼかし
    /// 処理が終わるまで`displayBackgroundImage`がnilのままだったため、その一瞬だけ
    /// 背景がパズル柄プレースホルダーに戻ってしまい（＝画面全体が一瞬「消える」ように
    /// 見える不具合）、ナビゲーションバーのアイコン周りなどが一瞬チラつく原因になっていた。
    private func refreshBackgroundDerivedState() {
        guard let backgroundImage else {
            displayBackgroundImage = nil
            return
        }
        // 即座にシャープな画像を暫定表示（ちらつき防止）。ぼかし無効ならこれで確定。
        displayBackgroundImage = backgroundImage
        guard backgroundBlurEnabled else { return }

        let radius = backgroundBlurRadius
        Task.detached(priority: .userInitiated) { [weak self] in
            let blurred = backgroundImage.blurred(radius: radius) ?? backgroundImage
            await MainActor.run {
                // 処理中に画像やぼかし設定が変わっていたら、古い結果を反映しない
                guard let self, self.backgroundImage === backgroundImage, self.backgroundBlurEnabled else { return }
                self.displayBackgroundImage = blurred
            }
        }
    }

    // `nonisolated`が重要：プロジェクトのデフォルトアクター分離設定により、
    // 明示しないとこの関数は暗黙的に@MainActor扱いになる。`Task.detached`は
    // メインアクターから切り離された非同期タスクなので、その中からMainActor隔離の
    // メンバーには直接アクセスできず、コンパイルエラーになる
    // （"Main actor-isolated property ... cannot be accessed from outside of the actor"）。
    // 単なる画像処理でUIやMainActor状態に触れないため、nonisolatedにするのが正しい。
    private static nonisolated func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    // MARK: - 永続化

    private func save(_ color: Color?, _ key: String) {
        if let color {
            store.set(color.hexString, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    private func save(_ value: String?, _ key: String) {
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    private func saveFontDesign() {
        switch fontDesign {
        case .rounded:    store.set("rounded",    forKey: Key.fontDesign)
        case .serif:      store.set("serif",      forKey: Key.fontDesign)
        case .monospaced: store.set("monospaced", forKey: Key.fontDesign)
        default:          store.removeObject(forKey: Key.fontDesign)
        }
    }

    private static func loadFontDesign(from store: UserDefaults) -> Font.Design? {
        switch store.string(forKey: Key.fontDesign) {
        case "rounded":    return .rounded
        case "serif":      return .serif
        case "monospaced": return .monospaced
        default:           return nil
        }
    }

    private func saveFontWeight() {
        switch fontWeight {
        case .some(.light):     store.set("light",     forKey: Key.fontWeight)
        case .some(.medium):    store.set("medium",    forKey: Key.fontWeight)
        case .some(.semibold):  store.set("semibold",  forKey: Key.fontWeight)
        case .some(.bold):      store.set("bold",      forKey: Key.fontWeight)
        case .some(.heavy):     store.set("heavy",     forKey: Key.fontWeight)
        default:                store.removeObject(forKey: Key.fontWeight)
        }
    }

    private static func loadFontWeight(from store: UserDefaults) -> Font.Weight? {
        switch store.string(forKey: Key.fontWeight) {
        case "light":    return .light
        case "medium":   return .medium
        case "semibold": return .semibold
        case "bold":     return .bold
        case "heavy":    return .heavy
        default:         return nil
        }
    }

    private static func load(_ key: String, from store: UserDefaults) -> Color? {
        guard let hex = store.string(forKey: key) else { return nil }
        return Color(hex: hex)
    }
}

// MARK: - UIImage 向き正規化・色解析・ぼかし

extension UIImage {
    /// EXIFの向き情報（`imageOrientation`）をピクセルデータ自体に焼き込んで正立させる。
    /// `BackgroundImageEditorView`のクロップ処理は`cgImage`のピクセル座標を直接
    /// 扱うため、これをしないと横向き・回転して撮った写真でクロップ範囲がずれる。
    nonisolated func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// 画像全体の平均色（CIAreaAverageフィルタで計算）。呼び出しはやや重いため、
    /// 背景画像を保存するタイミングで一度だけ計算してキャッシュする用途を想定している。
    ///
    /// `nonisolated`が重要：これらの画像処理系プロパティ／関数は`Task.detached`
    /// （メインアクターから切り離された非同期タスク）から呼ぶ前提のため、明示的に
    /// nonisolatedにしないとプロジェクトのデフォルトアクター分離設定により暗黙的に
    /// @MainActor扱いとなり、`Task.detached`内からアクセスできずコンパイルエラーになる。
    nonisolated var averageColor: Color? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y,
                                     z: extent.size.width, w: extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]),
              let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8, colorSpace: nil)
        return Color(red: Double(bitmap[0]) / 255, green: Double(bitmap[1]) / 255, blue: Double(bitmap[2]) / 255)
    }

    /// 画像全体の平均輝度（0=暗い 〜 1=明るい）
    nonisolated var averageLuminance: Double? {
        guard let avg = averageColor else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(avg).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
    }

    /// CIGaussianBlurで画像全体をぼかした新しい画像を返す（失敗時は自分自身を返す）。
    ///
    /// これをSwiftUIの`.blur(radius:)`修飾子でライブに（＝毎フレームの描画パスの中で）
    /// 行うと`CMPhotoCompressionSession`がメインスレッドでデッドロックする既知の不具合が
    /// あったため（カレンダー画面の背景実装時に判明）、必ずこの関数でオフスクリーン・
    /// 非同期に一度だけレンダリングした画像をキャッシュし、表示側は通常の`Image`として扱うこと。
    nonisolated func blurred(radius: CGFloat) -> UIImage? {
        guard radius > 0, let ciImage = CIImage(image: self) else { return self }
        let clamped = ciImage.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return self }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: ciImage.extent) else { return self }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: ciImage.extent) else { return self }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: .up)
    }
}

// MARK: - Color <-> HEX

extension Color {
    /// "#RRGGBB" / "RRGGBB" から生成。失敗時は nil。
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard s.count == 6, let int = UInt64(s, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// "#RRGGBB" 文字列へ変換
    var hexString: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
        #else
        return "#5500FF"
        #endif
    }

    /// この色を背景にしたとき、上に重ねるツールバー等の文字を白/黒どちらにすべきか。
    var overlayColorScheme: ColorScheme {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return luminance > 0.6 ? .light : .dark
        #else
        return .dark
        #endif
    }

    /// この色（背景画像の平均色を想定）の色相だけを取り出し、彩度・明度を
    /// 視認性の高い値に補正して返す。写真の平均色はくすんだ色になりがちで、
    /// そのままボタンのアクセント色に使うと地味で読みにくくなるための調整。
    ///
    /// `nonisolated`が重要：`Task.detached`（メインアクターから切り離された非同期タスク）
    /// から呼ぶ前提のため。無いとデフォルトアクター分離設定により暗黙的に@MainActor扱いとなり、
    /// `Task.detached`内からアクセスできずコンパイルエラーになる。
    nonisolated var asSuggestedAccent: Color {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: 0.6, brightness: 0.8)
        #else
        return self
        #endif
    }
}
