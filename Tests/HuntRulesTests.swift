import XCTest
@testable import MonsterHunt

final class HuntRulesTests: XCTestCase {
    func testRarityDistributionHasCorrectBoundaries() {
        let rolls = (0..<100).map(Rarity.roll)
        XCTAssertEqual(rolls.filter { $0 == .common }.count, 65)
        XCTAssertEqual(rolls.filter { $0 == .rare }.count, 25)
        XCTAssertEqual(rolls.filter { $0 == .epic }.count, 9)
        XCTAssertEqual(rolls.filter { $0 == .legendary }.count, 1)
    }

    func testTimingAndRange() {
        XCTAssertEqual(HuntRules.ringScale(elapsed: 0), 1)
        XCTAssertEqual(HuntRules.ringScale(elapsed: 2), 1)
        XCTAssertLessThan(HuntRules.ringScale(elapsed: 1.8), 0.52)
        XCTAssertFalse(HuntRules.inRange(.nan))
        XCTAssertFalse(HuntRules.inRange(0.49))
        XCTAssertTrue(HuntRules.inRange(0.5))
        XCTAssertTrue(HuntRules.inRange(3))
        XCTAssertFalse(HuntRules.inRange(3.01))
        for rarity in Rarity.allCases {
            XCTAssertGreaterThan(HuntRules.probability(rarity: rarity, ring: 0.4),
                                 HuntRules.probability(rarity: rarity, ring: 0.9))
        }
    }

    func testCaptureSurvivesReloadAndIsNotDuplicated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("captures.json")
        let store = try CaptureStore(url: url)
        let monster = CapturedMonster(id: UUID(), species: "mossling", rarity: .rare, caughtAt: Date())
        try store.append(monster)
        try store.append(monster)
        let reloaded = try CaptureStore(url: url)
        XCTAssertEqual(reloaded.monsters.count, 1)
        XCTAssertEqual(reloaded.monsters.first?.id, monster.id)
        XCTAssertEqual(reloaded.monsters.first?.rarity, .rare)
    }

    func testCorruptedSaveIsNotSilentlyOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("not valid json".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try CaptureStore(url: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
