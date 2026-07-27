import SwiftUI

struct MatsubiNotificationView: View {
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var manager = MatsubiNotificationManager.shared

    @State private var selectedMatsubi: Int? = nil
    @State private var startTime = Calendar.current.date(
        from: DateComponents(hour: 15, minute: 0)) ?? Date()
    @State private var endTime = Calendar.current.date(
        from: DateComponents(hour: 19, minute: 0)) ?? Date()
    @State private var secondsText: String = "10"
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showHelp = false

    // 0〜9, 12 の11個
    private let matsubiValues = Array(0...9) + [12]

    var body: some View {
        ZStack {
            PuzzleBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // ── 説明 ──
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showHelp.toggle() }
                        } label: {
                            HStack {
                                Image(systemName: "questionmark.circle.fill")
                                Text("この機能について")
                                    .font(.bongaEmphasis(.subheadline))
                                Spacer()
                                Image(systemName: showHelp ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(.bongaPurple)
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal).padding(.top, 8)

                        if showHelp {
                            VStack(alignment: .leading, spacing: 8) {
                                helpRow("🎮", "ボンバーガールの対戦開始時刻（末尾）に合わせて通知します")
                                helpRow("🔢", "「末尾」＝時計の分の下1桁。例：末尾0 → 毎時00分,10分,20分...")
                                helpRow("⏰", "iPhoneのアラームは00秒にしか鳴らないため、指定した秒数だけ「前」に通知を出します")
                                helpRow("📅", "設定した通知はその日限りで、翌日には自動的に無効になります")
                                helpRow("📱", "アプリを閉じていても通知は届きます")
                            }
                            .padding(12)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }

                        // ── 末尾選択（単一）──
                        SectionLabel(text: "末尾")
                            .padding(.horizontal).padding(.top, 4)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                            spacing: 8
                        ) {
                            ForEach(matsubiValues, id: \.self) { v in
                                Button {
                                    selectedMatsubi = (selectedMatsubi == v) ? nil : v
                                } label: {
                                    Text("\(v)")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedMatsubi == v
                                                ? Color.bongaPurple
                                                : Color(uiColor: .tertiarySystemBackground)
                                        )
                                        .foregroundColor(
                                            selectedMatsubi == v ? .white : .primary
                                        )
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    selectedMatsubi == v
                                                        ? Color.bongaPurple
                                                        : Color.gray.opacity(0.3),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)

                        if let sel = selectedMatsubi {
                            Text("対象: 毎時 \(previewMinutesText(for: sel))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }

                        // ── 時間帯 ──
                        SectionLabel(text: "時間帯")
                            .padding(.horizontal).padding(.top, 4)

                        HStack {
                            DatePicker("", selection: $startTime,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            Text("〜").foregroundColor(.secondary)
                            DatePicker("", selection: $endTime,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal)

                        // ── 秒数 ──
                        SectionLabel(text: "何秒前に通知")
                            .padding(.horizontal).padding(.top, 4)

                        HStack(spacing: 8) {
                            TextField("10", text: $secondsText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("秒前")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        // ── プレビュー ──
                        if selectedMatsubi != nil {
                            let count = previewNotificationCount
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("通知予定: \(count)件")
                                if count > 60 {
                                    Text("（上限60件まで設定されます）")
                                        .foregroundColor(.orange)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        }

                        // ── ステータス ──
                        if manager.scheduledCount > 0 {
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.bongaPurple)
                                Text("\(manager.scheduledCount)件の通知を設定済み（本日限り）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("クリア") { manager.clearNotifications() }
                                    .font(.bongaEmphasis(.caption))
                                    .foregroundColor(.red)
                            }
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }

                        // ── 通知未許可 ──
                        if !manager.isAuthorized {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("通知の許可が必要です。ボタンを押すと許可を求めます。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 16)
                }

                // ── 設定ボタン（常に下部固定）──
                PrimaryButton(title: "通知を設定") {
                    onSchedule()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .disabled(selectedMatsubi == nil)
            }
        }
        .bongaNavigationBar(title: "末尾通知")
        .onAppear {
            manager.checkAuthorization()
            manager.refreshCount()
        }
        .alert("末尾通知", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Help Row

    private func helpRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.callout)
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func onSchedule() {
        guard let sel = selectedMatsubi else { return }

        if !manager.isAuthorized {
            manager.requestPermission { granted in
                if granted { doSchedule(sel) }
                else {
                    alertMessage = "通知が許可されていません。設定アプリから許可してください。"
                    showAlert = true
                }
            }
            return
        }
        doSchedule(sel)
    }

    private func doSchedule(_ matsubi: Int) {
        let cal = Calendar.current
        let sc = cal.dateComponents([.hour, .minute], from: startTime)
        let ec = cal.dateComponents([.hour, .minute], from: endTime)
        let secs = Int(secondsText) ?? 10

        manager.scheduleNotifications(
            matsubiValues: [matsubi],
            startHour: sc.hour ?? 15,   startMinute: sc.minute ?? 0,
            endHour:   ec.hour ?? 19,   endMinute:   ec.minute ?? 0,
            secondsBefore: secs
        ) { count in
            alertMessage = "\(count)件の通知を設定しました（本日限り）"
            showAlert = true
        }
    }

    // MARK: - Preview Helpers

    private func previewMinutesText(for value: Int) -> String {
        let mins = manager.matchingMinutes(for: [value])
        return mins.map { String(format: ":%02d", $0) }.joined(separator: " ")
    }

    private var previewNotificationCount: Int {
        guard let sel = selectedMatsubi else { return 0 }
        let cal = Calendar.current
        let sc = cal.dateComponents([.hour, .minute], from: startTime)
        let ec = cal.dateComponents([.hour, .minute], from: endTime)
        return manager.previewCount(
            matsubiValues: [sel],
            startHour: sc.hour ?? 15,   startMinute: sc.minute ?? 0,
            endHour:   ec.hour ?? 19,   endMinute:   ec.minute ?? 0
        )
    }
}
