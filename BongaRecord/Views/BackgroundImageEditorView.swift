import SwiftUI

/// 背景画像として保存する前に、ユーザーが表示範囲を自由に選べる編集画面。
///
/// `PuzzleBackground`は背景画像を画面いっぱいに`scaledToFill`で表示するため、
/// 何も考えずに保存すると常に画像の中央だけが自動的に使われ、見せたい部分が
/// 切れてしまうことがあった。この画面ではピンチで拡大・ドラッグで位置調整をした上で
/// 「決定」を押すと、画面に実際に表示されている範囲を元画像のピクセル解像度の
/// まま切り出す（＝先に画像全体を縮小してからクロップするのではなく、
/// クロップしてから必要な場合だけ`ThemeManager.maxBackgroundDimension`で
/// 上限を掛ける）。ズームインして選んだ範囲ほど元画像の解像度をそのまま活かせる。
struct BackgroundImageEditorView: View {
    @ObservedObject private var theme = ThemeManager.shared
    let originalImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let base = baseSize(container: container)
            let maxScale = maximumScale(container: container, base: base)
            let currentScale = min(max(scale * gestureScale, 1), maxScale)
            let displayed = CGSize(width: base.width * currentScale, height: base.height * currentScale)
            let liveOffset = clampedOffset(
                displayed: displayed, container: container,
                raw: CGSize(width: offset.width + gestureOffset.width,
                            height: offset.height + gestureOffset.height))

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: originalImage)
                    .resizable()
                    .frame(width: displayed.width, height: displayed.height)
                    .offset(liveOffset)
                    .frame(width: container.width, height: container.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in gestureScale = value }
                                .onEnded { value in
                                    let committed = min(max(scale * value, 1), maxScale)
                                    let committedDisplayed = CGSize(width: base.width * committed,
                                                                     height: base.height * committed)
                                    scale = committed
                                    gestureScale = 1
                                    offset = clampedOffset(displayed: committedDisplayed, container: container, raw: offset)
                                },
                            DragGesture()
                                .onChanged { value in gestureOffset = value.translation }
                                .onEnded { value in
                                    let raw = CGSize(width: offset.width + value.translation.width,
                                                      height: offset.height + value.translation.height)
                                    offset = clampedOffset(displayed: displayed, container: container, raw: raw)
                                    gestureOffset = .zero
                                }
                        )
                    )

                VStack {
                    Spacer()
                    bottomPanel(container: container, base: base, maxScale: maxScale,
                                bottomSafeInset: geo.safeAreaInsets.bottom)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// 決定・キャンセル・ズームスライダーをまとめた下部パネル。
    /// 親指で操作しやすいよう、画面下端にまとめて配置している
    /// （上部の角に置くと片手操作で届きにくく押しづらいという指摘を受けて変更）。
    private func bottomPanel(container: CGSize, base: CGSize, maxScale: CGFloat,
                              bottomSafeInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            Text("ドラッグで位置を調整できます")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))

            // ピンチ操作の代わりに指1本でも拡大率を調整できるスライダー
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.white.opacity(0.8))
                Slider(value: scaleBinding(container: container, base: base),
                       in: 1...max(maxScale, 1.01))
                    .tint(.white)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.white.opacity(0.8))
            }

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("キャンセル")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(14)
                }

                Button {
                    confirm(container: container)
                } label: {
                    Text("決定")
                        .font(.bongaEmphasis(.headline))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.bongaPurple)
                        .cornerRadius(14)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, bottomSafeInset + 16)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom)
        )
    }

    /// スライダーの値をそのまま`scale`に反映し、はみ出さないよう`offset`も同時に補正する。
    private func scaleBinding(container: CGSize, base: CGSize) -> Binding<CGFloat> {
        Binding(
            get: { scale },
            set: { newValue in
                scale = newValue
                let displayed = CGSize(width: base.width * newValue, height: base.height * newValue)
                offset = clampedOffset(displayed: displayed, container: container, raw: offset)
            }
        )
    }

    private func confirm(container: CGSize) {
        // ジェスチャー終了後は gestureScale=1 / gestureOffset=.zero に確定しているので、
        // scale と offset がそのまま「今画面に表示されている範囲」を表す。
        onConfirm(currentCrop(container: container) ?? originalImage)
    }

    // MARK: - サイズ計算

    /// scale = 1 のとき、画像がコンテナ全体を隙間なく覆う基準サイズ（アスペクト比は維持したまま拡大縮小）
    private func baseSize(container: CGSize) -> CGSize {
        let imageSize = originalImage.size
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            let height = container.height
            return CGSize(width: height * imageAspect, height: height)
        } else {
            let width = container.width
            return CGSize(width: width, height: width / imageAspect)
        }
    }

    /// ピンチ／スライダーで拡大できる倍率の上限。
    /// 以前はRetina実解像度（nativeScale倍）を基準にしていたため、多くの写真で
    /// 上限が1〜2倍程度しかなく拡大の余地がほとんど無かった。ここでは基準を緩め、
    /// 画面のポイント解像度に対する情報量で判定することで、余裕を持って拡大できるようにする
    /// （＝多少ぼやけても構わないので、狙った部分を大きく強調したいという要望に合わせた）。
    /// 低解像度の画像でも最低3倍までは拡大でき、高解像度の画像は最大8倍まで拡大できる。
    private func maximumScale(container: CGSize, base: CGSize) -> CGFloat {
        guard let cgImage = originalImage.cgImage, base.width > 0 else { return 6 }
        let usable = CGFloat(cgImage.width) / base.width
        return max(3.0, min(8.0, usable))
    }

    private func clampedOffset(displayed: CGSize, container: CGSize, raw: CGSize) -> CGSize {
        let maxX = max(0, (displayed.width - container.width) / 2)
        let maxY = max(0, (displayed.height - container.height) / 2)
        return CGSize(width: min(max(raw.width, -maxX), maxX),
                      height: min(max(raw.height, -maxY), maxY))
    }

    // MARK: - 切り出し

    /// ジェスチャー確定後の scale / offset を元に、現在表示されている範囲を計算してクロップする。
    private func currentCrop(container: CGSize) -> UIImage? {
        guard let cgImage = originalImage.cgImage else { return nil }
        // `container`は呼び出し元（bottomPanel）がbody内のGeometryReaderから
        // 受け取った実際のコンテナサイズをそのまま渡してもらったもの。
        // 以前はここで`UIScreen.main.bounds.size`を代用していたが、
        // `UIScreen.main`はiOS 26で非推奨になったため、実測値を引数で受け取る形に変更した。
        let base = baseSize(container: container)
        let displayed = CGSize(width: base.width * scale, height: base.height * scale)
        let clamped = clampedOffset(displayed: displayed, container: container, raw: offset)

        let pixelWidth = CGFloat(cgImage.width)
        guard displayed.width > 0 else { return nil }
        let pixelsPerPoint = pixelWidth / displayed.width

        let imageOriginX = (container.width - displayed.width) / 2 + clamped.width
        let imageOriginY = (container.height - displayed.height) / 2 + clamped.height

        var cropRect = CGRect(
            x: -imageOriginX * pixelsPerPoint,
            y: -imageOriginY * pixelsPerPoint,
            width: container.width * pixelsPerPoint,
            height: container.height * pixelsPerPoint
        )
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: pixelWidth, height: CGFloat(cgImage.height)))
        guard !cropRect.isEmpty, let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }
}
