import SwiftUI

extension Color {
    /// メインの紫（アクセント）。優先順位：ユーザー設定 ＞ 背景画像から自動提案 ＞ 既定色。
    /// アプリ全体のボタン・ナビバー・アクセントがこのトークンを参照している。
    static var bongaPurple: Color { ThemeManager.shared.effectiveAccent }

    /// 薄紫（ハイライト・タップ時など）※固定
    static let bongaPurpleLight = Color(red: 200/255, green: 180/255, blue: 255/255)

    /// アクセントの水色（ラジオボタン選択など）※固定
    static let bongaCyan = Color(red: 56/255, green: 207/255, blue: 196/255)

    /// テーブルヘッダ背景の薄水色（ユーザー設定可）
    static var bongaCyanLight: Color { ThemeManager.shared.tableHeader ?? ThemeManager.Defaults.tableHeader }

    /// アクセント上に乗せる文字色（ボタン・メニューの文字）。既定は白。
    static var bongaOnAccent: Color { ThemeManager.shared.onAccent ?? ThemeManager.Defaults.onAccent }

    /// アイコン色。既定はアクセント色に追従（背景画像からの自動提案も含む）。
    static var bongaIcon: Color { ThemeManager.shared.effectiveIcon }

    /// 画面の地の背景色。既定は systemBackground（ライト/ダーク追従）。
    static var bongaBackground: Color { ThemeManager.shared.background ?? Color(uiColor: .systemBackground) }

    /// この色を背景に敷いたとき、読みやすい文字色（黒 or 白）を返す。
    ///
    /// 背景の相対輝度を計算し、明るい背景には黒、暗い背景には白を返す。
    /// 固定色でも、ユーザーが任意のRGBを設定した場合でも、
    /// 文字が背景に埋もれないことを保証する。
    var readableForeground: Color {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1
        #endif

        // 相対輝度 (0=暗い 〜 1=明るい)。明るい背景は黒文字、暗い背景は白文字
        let luminance = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return luminance > 0.6 ? Color.black : Color.white
    }
}

// MARK: - 太字の置き換え（「文字の太さ」設定を確実に反映するため）

extension Font {
    /// 見出しなどを太字にしたい箇所で、`.bold()`の代わりに使う。
    ///
    /// `Text(...).font(.headline.bold())`のように`.bold()`をFontに直接チェーンすると、
    /// そのFontに「明示的な太さ」が焼き込まれてしまい、SwiftUIの環境修飾子である
    /// `.fontWeight()`では後から上書きできなくなる（＝ユーザーが「文字の太さ」設定を
    /// 変えても、こう書かれた文字だけ反映されない）。これがアプリ内のほぼ全ての強調
    /// テキストで起きていた「太さを変えても効かない」不具合の原因だった。
    /// 常にこちらを使い、太さは`ThemeManager.shared.fontWeight`（未設定なら見出しとして
    /// 十分な`.semibold`）を明示的に指定することで、設定を確実に反映する。
    static func bongaEmphasis(_ style: Font.TextStyle) -> Font {
        .system(style, design: ThemeManager.shared.fontDesign)
            .weight(ThemeManager.shared.fontWeight ?? .semibold)
    }
}

extension View {
    /// View修飾子としての`.bold()`の置き換え版（理由は`Font.bongaEmphasis`と同じ）。
    func bongaBold() -> some View {
        self.fontWeight(ThemeManager.shared.fontWeight ?? .semibold)
    }
}
