import Foundation

enum Rarity: String, Codable, CaseIterable {
    case common, rare, epic, legendary

    var title: String {
        switch self {
        case .common: return "Обычный"
        case .rare: return "Редкий"
        case .epic: return "Эпический"
        case .legendary: return "Легендарный"
        }
    }

    // Prototype tuning, not final economy. Boundaries total exactly 100.
    static func roll(_ value: Int) -> Rarity {
        precondition((0..<100).contains(value))
        switch value {
        case 0..<65: return .common
        case 65..<90: return .rare
        case 90..<99: return .epic
        default: return .legendary
        }
    }
}

enum HuntRules {
    static let minimumDistance: Float = 0.5
    static let maximumDistance: Float = 3.0

    static func inRange(_ distance: Float) -> Bool {
        distance.isFinite && (minimumDistance...maximumDistance).contains(distance)
    }

    static func ringScale(elapsed: TimeInterval) -> Double {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: 2.0) / 2.0
        return 1.0 - 0.7 * phase
    }

    static func probability(rarity: Rarity, ring: Double) -> Double {
        let base: Double
        switch rarity {
        case .common: base = 0.62
        case .rare: base = 0.44
        case .epic: base = 0.28
        case .legendary: base = 0.14
        }
        return min(0.95, base + (ring <= 0.52 ? 0.28 : 0.0))
    }
}

struct CapturedMonster: Codable, Identifiable {
    let id: UUID
    let species: String
    let rarity: Rarity
    let caughtAt: Date
}

final class CaptureStore {
    private let url: URL
    private(set) var monsters: [CapturedMonster]

    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            monsters = try JSONDecoder().decode([CapturedMonster].self, from: Data(contentsOf: url))
        } else {
            monsters = []
        }
    }

    func append(_ monster: CapturedMonster) throws {
        // A repeated completion cannot award the same creature twice.
        guard !monsters.contains(where: { $0.id == monster.id }) else { return }
        let updated = monsters + [monster]
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        monsters = updated
    }
}
