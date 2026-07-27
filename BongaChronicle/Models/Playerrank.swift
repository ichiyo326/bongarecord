import Foundation

/// プレイヤーのランク（クラス）。
///
/// `rawValue` の昇順がそのまま強さの全順序になっている：
/// スーパースター < マスター < グランドマスター、各クラス内は C < B < A。
/// 昇格・降格の判定（カレンダーのランク変動表示など）はこの順序で行う。
enum PlayerRank: Int, CaseIterable, Identifiable, Comparable, Codable {
    case superstarC = 0
    case superstarB
    case superstarA
    case masterC
    case masterB
    case masterA
    case grandmasterC
    case grandmasterB
    case grandmasterA

    var id: Int { rawValue }

    /// クラス名（スーパースター / マスター / グランドマスター）
    var className: String {
        switch self {
        case .superstarC, .superstarB, .superstarA:       return "スーパースター"
        case .masterC, .masterB, .masterA:                return "マスター"
        case .grandmasterC, .grandmasterB, .grandmasterA: return "グランドマスター"
        }
    }

    /// クラス内のサブ（A / B / C）
    var tier: String {
        switch self {
        case .superstarA, .masterA, .grandmasterA: return "A"
        case .superstarB, .masterB, .grandmasterB: return "B"
        case .superstarC, .masterC, .grandmasterC: return "C"
        }
    }

    /// 表示用フルネーム（例：スーパースターC）
    var label: String { "\(className)\(tier)" }

    static func < (lhs: PlayerRank, rhs: PlayerRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
