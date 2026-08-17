import SwiftUI

// MARK: - 紙工作風プロフィール（履歴書）用パーツ
//
// ユーザーが参考として共有した「紙の履歴書」テンプレートの雰囲気
// （クリーム紙・黒ペン枠・マスキングテープ）を、SwiftUIの図形描画のみで
// オリジナルに再現したもの。実在のロゴやキャラクターイラストは一切使用しない。
// ProfileView（プロフィール画面）専用。アプリの他画面はこれまで通り
// ThemeManager 由来のダーク基調デザインのまま。

/// マスキングテープ風の装飾（角に斜めに貼ったような帯）
struct WashiTape: View {
    var color: Color = .bongaPurpleLight
    var width: CGFloat = 60
    var rotation: Double = -10

    var body: some View {
        Rectangle()
            .fill(color.opacity(0.8))
            .frame(width: width, height: 20)
            .overlay(
                Rectangle().stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
    }
}

// MARK: - Paper card modifier

extension View {
    /// クリーム紙に黒枠・薄影をつけた「履歴書の枠」風の見た目にする。
    func paperCard(tint: Color = PaperPalette.paper, corner: CGFloat = 10, lineWidth: CGFloat = 1.4) -> some View {
        self
            .background(tint)
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(Color.black.opacity(0.78), lineWidth: lineWidth)
            )
            .cornerRadius(corner)
            .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 2)
    }
}

/// このプロフィール画面専用の固定配色（ダーク/ライト設定に関わらず「紙」の質感を保つ）
enum PaperPalette {
    static let paper       = Color(red: 1.00, green: 0.98, blue: 0.90)
    static let paperShade  = Color(red: 0.99, green: 0.95, blue: 0.80)
    static let yellow      = Color(red: 1.00, green: 0.84, blue: 0.30)
    static let ink         = Color.black.opacity(0.85)
}

/// 手帳の項目タグ風ラベル（黒帯に白文字＋ドット飾り）
struct PaperFieldLabel: View {
    let text: String
    /// true の場合、ドット飾りを省いてさらに小さく（密集レイアウト用）
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: compact ? 8 : 10, weight: .bold))
                .foregroundColor(.white)
            if !compact {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(0.55)).frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, compact ? 1.5 : 2)
        .background(PaperPalette.ink)
        .cornerRadius(4)
    }
}

/// プロフィール項目1枠（ラベル＋内容）。「履歴書」のマス目を模したパーツ。
struct PaperField: View {
    let label: String
    let value: String
    var placeholder: String = "未設定"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            PaperFieldLabel(text: label, compact: true)
            Text(value.isEmpty ? placeholder : value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(value.isEmpty ? .secondary : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .paperCard()
    }
}

/// ランクバッジ（丸ワッペン風）
struct RankBadgeChip: View {
    let rank: String
    var size: CGFloat = 14

    var body: some View {
        Text(rank)
            .font(.system(size: size * 0.58, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.6))
    }

    private var color: Color {
        switch rank {
        case "S": return Color(red: 1.00, green: 0.62, blue: 0.05)
        case "A": return Color(red: 0.93, green: 0.32, blue: 0.42)
        case "B": return Color(red: 0.22, green: 0.56, blue: 0.92)
        case "C": return Color(red: 0.35, green: 0.70, blue: 0.42)
        default:  return Color.gray
        }
    }
}
