import Foundation

/// アプリ全体の「まだ正式リリースしない機能」を一箇所に集約するフラグ。
///
/// 実装自体は完成させておきたいが、正式にリリース（App Storeでのアナウンス・
/// 本格運用）はまだしたくない機能はここでfalseにしておく。
/// UI側はこのフラグを見て「ベータ」バッジの表示切り替えなどに使う
/// （機能自体を隠すのではなく、ベータであることを明示する運用を想定）。
///
/// 正式リリースする際は、対応するフラグをtrueに変えるだけでよい。
enum FeatureFlags {
    /// 配信連携（OBS）機能。正式リリース済み。
    static let obsStreamingReleased = true

    /// 戦績AI（Foundation Modelsを使ったAIコーチ）機能。同じく正式リリースまではfalseのまま。
    static let battleAIReleased = false
}
