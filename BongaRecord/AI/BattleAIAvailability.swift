import Foundation
import FoundationModels

/// Foundation Models（Apple Intelligence）の利用可否をUIから扱いやすい形にまとめたもの。
///
/// 指示書9章「Foundation Modelsをボンガレコード自体の必須機能にはしない」に従い、
/// AI画面はこれを確認してから機能を出し分ける。非対応端末・未有効化の場合でも
/// 戦績記録・集計など既存機能はそのまま使えることが前提（Phase 6の確認項目）。
///
/// - Note: `SystemLanguageModel.Availability.UnavailableReason`のケース名はSDKの
///   バージョンで変わる可能性がある。実装時は最新のFoundationModelsで確認すること
///   （指示書10章の注意書きと同様）。
enum BattleAIAvailability {
    enum Status: Equatable {
        case available
        case unavailable(reason: String)
    }

    @MainActor
    static var current: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: description(for: reason))
        @unknown default:
            return .unavailable(reason: "この端末では現在AI機能を利用できません")
        }
    }

    private static func description(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "この端末はApple Intelligenceに対応していません"
        case .appleIntelligenceNotEnabled:
            return "設定でApple Intelligenceを有効にすると利用できます"
        case .modelNotReady:
            return "AIモデルを準備中です。しばらくしてからもう一度お試しください"
        @unknown default:
            return "現在この機能は利用できません"
        }
    }
}
