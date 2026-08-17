import SwiftUI

/// アプリ全体の背景。
/// ユーザーが背景画像を設定していればそれを表示し、なければ
/// Android版のパズルピース柄背景を簡易再現したパターンを表示する。
struct PuzzleBackground: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Group {
            // 表示には`backgroundImage`ではなく`displayBackgroundImage`を使う。
            // ぼかし設定が有効なときはこちらが事前にぼかし済みの画像になっており、
            // ライブの`.blur()`修飾子を画面階層で使わずに済む
            // （ライブblurは`CMPhotoCompressionSession`のデッドロックを引き起こした既知の問題）。
            if let uiImage = theme.displayBackgroundImage {
                // 重要：scaledToFill した画像はコンテナより大きくなるため、
                // .frame で画面サイズに固定 → .clipped() ではみ出しを切らないと、
                // 画像の本来サイズがレイアウトに漏れて ZStack 全体（＝前面の
                // コンテンツも含む）を画像サイズまで押し広げてしまう。
                // その結果、各画面のコンテンツが拡大・画面外へはみ出し、
                // カレンダーの列が見切れる／月送りが押せない等の不具合が起きていた。
                // GeometryReader で実寸を取り、画像をその枠に閉じ込める。
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(dimOverlay)
                }
            } else {
                puzzlePattern
            }
        }
        .ignoresSafeArea()
    }

    /// 半透明の重ねが有効なときだけ表示するオーバーレイ。
    /// 色は「現在の見た目（ライト/ダーク）」ではなく、背景画像自体の明暗判定
    /// （`backgroundImageIsDark`）に合わせて黒/白を選ぶ。こうしないと、配色の
    /// 自動調整（画像の明暗→ライト/ダーク判定）が、その判定結果を使って
    /// 描かれるオーバーレイの色に依存してしまい、堂々巡りになってしまうため。
    @ViewBuilder
    private var dimOverlay: some View {
        if theme.backgroundDimEnabled {
            (theme.backgroundImageIsDark == true ? Color.black : Color.white)
                .opacity(theme.backgroundDimOpacity)
        }
    }

    private var puzzlePattern: some View {
        Canvas { context, size in
            let tile: CGFloat = 56
            let cols = Int(size.width / tile) + 2
            let rows = Int(size.height / tile) + 2
            for r in 0..<rows {
                for c in 0..<cols {
                    let x = CGFloat(c) * tile
                    let y = CGFloat(r) * tile
                    // パズルピース風：丸い切り欠きを表現するため複数の円を重ねる
                    let pieceRect = CGRect(x: x + 4, y: y + 4,
                                            width: tile - 8, height: tile - 8)
                    let path = Path(roundedRect: pieceRect, cornerRadius: 10)
                    context.fill(path, with: .color(.gray.opacity(0.08)))

                    // 切り欠きの円（隣接タイルとの噛み合わせ）
                    let knob = tile / 4
                    let knobPath = Path(ellipseIn: CGRect(
                        x: x + tile/2 - knob/2,
                        y: y - knob/2,
                        width: knob, height: knob))
                    context.fill(knobPath, with: .color(.gray.opacity(0.08)))
                }
            }
        }
        .background(Color.bongaBackground)
    }
}
