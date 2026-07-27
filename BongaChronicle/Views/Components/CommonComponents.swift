import SwiftUI

// MARK: - Primary Button（紫背景・白文字）

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var background: Color = .bongaPurple

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.bongaOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background)
                .cornerRadius(4)
        }
    }
}

// MARK: - Radio Button

struct RadioButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .bongaCyan : .gray)
                    .font(.system(size: 20))
                Text(label)
                    .foregroundColor(.primary)
            }
            // SectionLabelと同じ理由（背景画像が透けて読みにくくなるのを防ぐ）
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Label（フォームラベル）

struct SectionLabel: View {
    let text: String

    var body: some View {
        // `SectionLabel`はアプリ全体のほぼ全画面（プロフィール、各種登録/編集フォーム、
        // 検索条件など）で使われている共通部品。以前は背景が無く、ユーザーが背景画像を
        // 設定すると写真がそのまま透けて文字が読めなくなる問題が全画面で起きていた
        // （1画面ずつ直すといたちごっこになるため、ここを直すことで一括対応する）。
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Form Card（背景の入力枠）

struct FormCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(uiColor: .systemGray4)),
                alignment: .bottom
            )
    }
}

// MARK: - Standard NavigationBar style helper

extension View {
    /// 共通のNavigationBarスタイル（紫背景・白文字タイトル）
    func bongaNavigationBar(title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bongaPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(Color.bongaPurple.overlayColorScheme, for: .navigationBar)
    }
}
