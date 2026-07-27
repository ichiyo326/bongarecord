import SwiftUI
import PhotosUI

/// 配色・書体・背景画像の設定。
/// `ThemeManager` を監視しているので、操作すると即座にプレビュー・アプリ全体へ反映される。
struct ThemeSettingsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingImage = false
    /// PhotosPickerで選んだ直後の、まだ範囲を決めていない画像（向き正規化済み）
    @State private var pendingImage: UIImage?
    @State private var showBackgroundEditor = false

    /// プリセットを選ぶたびに増やすカウンタ。
    /// `ColorPicker`は一度ユーザーが操作すると内部に選択状態を持ってしまい、
    /// その後にプリセット側から`theme.accent`等をプログラム的に書き換えても
    /// ピッカーの表示・以降のドラッグ操作が追従しなくなる（＝一見「変更できなくなる」ように
    /// 見える）SwiftUIの既知の癖がある。`.id()`にこの値を紐付けて変更のたびに
    /// ColorPicker・文字のデザイン/太さの行を丸ごと作り直すことで、内部状態を確実にリセットする。
    @State private var presetGeneration = 0

    var body: some View {
        ZStack {
            PuzzleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard
                        .padding(.horizontal)
                        .padding(.top, 12)

                    presetSection
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        colorRow("アクセント色",  binding(\.accent,      default: theme.backgroundImageAccent ?? ThemeManager.Defaults.accent))
                        Divider()
                        colorRow("文字色（ボタン上）", binding(\.onAccent,  default: ThemeManager.Defaults.onAccent))
                        Divider()
                        colorRow("アイコン色",    binding(\.icon,        default: theme.backgroundImageAccent ?? ThemeManager.Defaults.icon))
                        Divider()
                        colorRow("背景色",        binding(\.background,   default: ThemeManager.Defaults.background))
                        Divider()
                        colorRow("テーブルヘッダ色", binding(\.tableHeader, default: ThemeManager.Defaults.tableHeader))
                    }
                    .id(presetGeneration) // プリセット適用直後にColorPickerの内部状態を作り直す
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)

                    if theme.backgroundImageAccent != nil, theme.accent == nil || theme.icon == nil {
                        Text("背景画像から自動で色を提案しています。上のアクセント色・アイコン色から、いつでも好きな色に変更できます。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    fontDesignSection
                        .id(presetGeneration)
                        .padding(.horizontal)

                    fontWeightSection
                        .padding(.horizontal)

                    backgroundImageSection
                        .padding(.horizontal)

                    if theme.backgroundImage != nil {
                        backgroundAppearanceSection
                            .padding(.horizontal)
                    }

                    Button(role: .destructive) {
                        theme.resetToDefaults()
                    } label: {
                        Text("既定の配色に戻す")
                            .font(.bongaEmphasis(.subheadline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .foregroundColor(theme.isCustomized ? .red : .secondary)
                            .cornerRadius(8)
                    }
                    .disabled(!theme.isCustomized)
                    .padding(.horizontal)

                    Text("配色・書体・背景画像は未設定だと既定（端末のライト/ダークに自動追従するパズル柄）に戻ります。背景画像はこの端末にのみ保存され、他の端末（iCloud同期）には反映されません。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
            }
        }
        .bongaNavigationBar(title: "配色設定")
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            isLoadingImage = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    // 向き（EXIF回転）をここで正規化しておく。編集画面のクロップ処理は
                    // cgImageのピクセル座標を直接扱うため、正規化しないと横向きに
                    // 撮った写真などでクロップ範囲がずれてしまう。
                    pendingImage = uiImage.normalizedOrientation()
                    showBackgroundEditor = true
                }
                isLoadingImage = false
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showBackgroundEditor) {
            if let pendingImage {
                // pendingImage は常に「クロップ前の元画像」。新規選択時はPhotosPickerで
                // 選んだ画像そのもの、「範囲を調整」時は保存済みのbackgroundSourceImageを渡すため、
                // 何度調整してもここで保存する元画像は劣化しない。
                BackgroundImageEditorView(originalImage: pendingImage) { cropped in
                    showBackgroundEditor = false
                    isLoadingImage = true
                    Task {
                        await theme.setBackgroundImage(source: pendingImage, croppedImage: cropped)
                        isLoadingImage = false
                    }
                } onCancel: {
                    showBackgroundEditor = false
                }
            }
        }
    }

    // MARK: - プリセット

    // 10種類になったので横一列のHStackだと画面に収まらない。折り返すグリッドにする。
    private let presetGridColumns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プリセット")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.secondary)
            LazyVGrid(columns: presetGridColumns, spacing: 12) {
                ForEach(ThemeManager.Preset.allCases) { preset in
                    Button {
                        theme.apply(preset: preset)
                        presetGeneration += 1
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(preset.accent)
                                .frame(width: 28, height: 28)
                            Text(preset.label)
                                .font(.system(.caption, design: preset.fontDesign).bold())
                                .foregroundColor(preset.background.readableForeground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(preset.background)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("タップすると配色と書体をまとめて切り替えます（背景画像は変わりません）。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 色

    private func colorRow(_ title: String, _ value: Binding<Color>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            ColorPicker("", selection: value, supportsOpacity: false)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Optional な theme プロパティを、ColorPicker 用の非Optional Binding に橋渡しする。
    private func binding(_ keyPath: ReferenceWritableKeyPath<ThemeManager, Color?>,
                         default def: Color) -> Binding<Color> {
        Binding(
            get: { theme[keyPath: keyPath] ?? def },
            set: { theme[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - 文字のデザイン

    private var fontDesignOptions: [(label: String, design: Font.Design?)] {
        [("標準", nil), ("丸め（かわいい系）", .rounded), ("明朝風", .serif), ("等幅", .monospaced)]
    }

    private var fontDesignSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文字のデザイン")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(fontDesignOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        theme.fontDesign = option.design
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(.subheadline, design: option.design))
                            Spacer()
                            if theme.fontDesign == option.design {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.bongaPurple)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if index != fontDesignOptions.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
        }
    }

    // MARK: - 文字の太さ

    private var fontWeightOptions: [(label: String, weight: Font.Weight?)] {
        [("標準", nil), ("細め", .light), ("少し太め", .medium),
         ("太め", .semibold), ("かなり太め", .bold), ("極太", .heavy)]
    }

    /// `fontDesign`（標準／丸め／明朝風／等幅）だけだと4種類しかなく、特に日本語の
    /// 文章では書体による違いが分かりにくいことがある。太さの軸を独立して選べるようにし、
    /// デザイン×太さの組み合わせでバリエーションを増やしている
    /// （プリセットで太さが変わることはないので、プリセット適用後もここは常に独立して選べる）。
    private var fontWeightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文字の太さ")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(fontWeightOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        theme.fontWeight = option.weight
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(.subheadline, design: theme.fontDesign, weight: option.weight))
                            Spacer()
                            if theme.fontWeight == option.weight {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.bongaPurple)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if index != fontWeightOptions.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
        }
    }

    // MARK: - 背景画像

    private var backgroundImageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("背景画像")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.secondary)

            if let image = theme.backgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(theme.backgroundImage == nil ? "画像を選ぶ" : "画像を変更", systemImage: "photo")
                        .font(.bongaEmphasis(.subheadline))
                        .foregroundColor(.bongaOnAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.bongaPurple)
                        .cornerRadius(8)
                }

                if let currentImage = theme.backgroundImage {
                    Button {
                        // クロップ済みのcurrentImageではなく、保存してある元画像
                        // （backgroundSourceImage）を編集画面に渡す。こうしないと、
                        // 調整するたびに選べる範囲が狭まり画質も落ちてしまう。
                        // 元画像が無い（本アップデート以前に設定した）背景の場合のみ、
                        // やむを得ずcurrentImageを元画像として扱う。
                        pendingImage = theme.backgroundSourceImage ?? currentImage
                        showBackgroundEditor = true
                    } label: {
                        Label("範囲を調整", systemImage: "crop")
                            .font(.bongaEmphasis(.subheadline))
                            .foregroundColor(.bongaPurple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }

                    Button(role: .destructive) {
                        theme.clearBackgroundImage()
                    } label: {
                        Text("削除")
                            .font(.bongaEmphasis(.subheadline))
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }

                if isLoadingImage {
                    ProgressView()
                }
            }

            Text("画像を選ぶとピンチ・ドラッグで表示範囲を選べます。端末内のみに保存されます（iCloud同期の対象外）。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 背景の見え方（半透明・ぼかし）

    /// 背景画像を「暗く/明るく落として文字を読みやすくするか」「ぼかしを入れるか」を
    /// ユーザー自身が選べるようにするセクション。以前はどちらも固定（半透明0.7・ぼかし無し）
    /// だったが、写真をくっきり見せたい／もっと落ち着いた見た目にしたい、といった好みの
    /// 違いに対応できるようにした。
    private var backgroundAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("背景の見え方")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                Toggle("画像を暗く/明るくして文字を読みやすくする", isOn: $theme.backgroundDimEnabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                if theme.backgroundDimEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("濃さ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $theme.backgroundDimOpacity, in: 0...1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                Divider()

                Toggle("ぼかしを入れる", isOn: $theme.backgroundBlurEnabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                if theme.backgroundBlurEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ぼかしの強さ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $theme.backgroundBlurRadius, in: 2...40)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
        }
    }

    // MARK: - プレビュー

    private var previewCard: some View {
        VStack(spacing: 0) {
            // 疑似ナビバー
            Text("プレビュー")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(Color.bongaPurple.readableForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.bongaPurple)

            VStack(spacing: 12) {
                // 疑似ボタン
                Text("ボタン")
                    .font(.headline)
                    .foregroundColor(.bongaOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.bongaPurple)
                    .cornerRadius(6)

                // アイコン見本
                HStack(spacing: 18) {
                    Image(systemName: "flame.fill")
                    Image(systemName: "scope")
                    Image(systemName: "cube.fill")
                }
                .font(.title3)
                .foregroundColor(.bongaIcon)

                // 疑似テーブルヘッダ
                HStack {
                    Text("使用ガール")
                    Spacer()
                    Text("勝率")
                }
                .font(.bongaEmphasis(.caption))
                .foregroundColor(Color.bongaCyanLight.readableForeground)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.bongaCyanLight)
                .cornerRadius(4)
            }
            .padding(14)
            .background(Color.bongaBackground)
        }
        .fontDesign(theme.fontDesign)
        .fontWeight(theme.fontWeight)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
