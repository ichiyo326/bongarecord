import SwiftUI

/// 4軸のレーダーチャート（ロール使用率を表示）
///
/// 軸配置:
///   ボマー（上）
///   アタッカー（右）
///   シューター（下）
///   ブロッカー（左）
struct RadarChartView: View {
    /// ロールごとの値 (0.0〜1.0)
    let values: [CharacterRole: Double]

    private let axisOrder: [CharacterRole] = [.bomber, .attacker, .shooter, .blocker]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.35

            ZStack {
                // グリッド（4段階のひし形）
                ForEach(1...4, id: \.self) { level in
                    DiamondShape()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        .frame(width: radius * 2 * CGFloat(level) / 4,
                               height: radius * 2 * CGFloat(level) / 4)
                        .position(center)
                }

                // 軸線
                ForEach(0..<4, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: pointFor(axis: i, value: 1.0, center: center, radius: radius))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                }

                // データポリゴン
                Path { p in
                    var first: CGPoint?
                    for (i, role) in axisOrder.enumerated() {
                        let v = values[role] ?? 0
                        let pt = pointFor(axis: i, value: v, center: center, radius: radius)
                        if i == 0 {
                            p.move(to: pt)
                            first = pt
                        } else {
                            p.addLine(to: pt)
                        }
                        if i == axisOrder.count - 1, let f = first {
                            p.addLine(to: f)
                        }
                    }
                }
                .fill(Color.bongaPurple.opacity(0.4))

                Path { p in
                    var first: CGPoint?
                    for (i, role) in axisOrder.enumerated() {
                        let v = values[role] ?? 0
                        let pt = pointFor(axis: i, value: v, center: center, radius: radius)
                        if i == 0 {
                            p.move(to: pt)
                            first = pt
                        } else {
                            p.addLine(to: pt)
                        }
                        if i == axisOrder.count - 1, let f = first {
                            p.addLine(to: f)
                        }
                    }
                }
                .stroke(Color.bongaPurple, lineWidth: 1.5)

                // 軸ラベル
                // 注：ここは `.position(x:y:)` で幾何学的に配置しているため、
                // .caption などのDynamic Type対応フォントを使うと文字サイズ設定次第で
                // ラベルの矩形が大きくなり、center±radius+30 の位置から画面外へはみ出して
                // 見切れてしまう（「アタッカー」が「アタッカ」で切れる不具合はこれが原因）。
                // チャートラベルは可変長対応の来ないレイアウトなので、あえて
                // Dynamic Typeに追従しない固定サイズフォントにして事故を防ぐ。
                Text("ボマー")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: center.x, y: center.y - radius - 14)
                Text("アタッカー")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: center.x + radius + 30, y: center.y)
                Text("シューター")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: center.x, y: center.y + radius + 14)
                Text("ブロッカー")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: center.x - radius - 30, y: center.y)
            }
        }
    }

    private func pointFor(axis: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        // 0=上, 1=右, 2=下, 3=左
        let angle: Double
        switch axis {
        case 0: angle = -.pi / 2          // 上
        case 1: angle = 0                 // 右
        case 2: angle = .pi / 2           // 下
        case 3: angle = .pi               // 左
        default: angle = 0
        }
        let r = radius * CGFloat(value)
        return CGPoint(x: center.x + r * cos(angle),
                       y: center.y + r * sin(angle))
    }
}

/// ひし形（4軸レーダー用のグリッド）
private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        p.move(to: CGPoint(x: mid.x, y: mid.y - halfH))
        p.addLine(to: CGPoint(x: mid.x + halfW, y: mid.y))
        p.addLine(to: CGPoint(x: mid.x, y: mid.y + halfH))
        p.addLine(to: CGPoint(x: mid.x - halfW, y: mid.y))
        p.closeSubpath()
        return p
    }
}
