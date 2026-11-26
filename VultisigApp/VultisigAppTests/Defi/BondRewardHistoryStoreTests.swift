//
//  BondRewardHistoryStoreTests.swift
//  VultisigAppTests
//
//  The on-device copy of realized bond rewards.
//

import XCTest
@testable import VultisigApp

final class BondRewardHistoryStoreTests: XCTestCase {

    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var store = BondRewardHistoryStore()

    override func setUp() {
        super.setUp()
        suiteName = "BondRewardHistoryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = BondRewardHistoryStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func entry(_ height: Int, amount: Decimal = 1) -> BondRewardHistoryEntry {
        BondRewardHistoryEntry(churnHeight: height, churnDate: Date(timeIntervalSince1970: Double(height)), amount: amount)
    }

    private func saved(bond: String = "thor1bond", node: String = "thor1node") async throws -> [Int: BondRewardHistoryEntry] {
        var known: [Int: BondRewardHistoryEntry] = [:]
        _ = try await store.fetch(bondAddress: bond, nodeAddress: node) { saved in
            known = saved
            return []
        }
        return known
    }

    func testRewardsFetchedOnceAreHandedToTheNextFetch() async throws {
        let first = [entry(300, amount: 5), entry(200, amount: 7)]
        _ = try await store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { saved in
            XCTAssertTrue(saved.isEmpty)
            return first
        }

        let known = try await saved()

        XCTAssertEqual(known[300]?.amount, 5)
        XCTAssertEqual(known[200]?.amount, 7)
        XCTAssertEqual(known[200]?.date, Date(timeIntervalSince1970: 200))
    }

    func testKeepsEverySavedRewardIncludingOnesThatPaidNothing() async throws {
        _ = try await store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { _ in
            (1...500).reversed().map { self.entry($0, amount: $0 == 1 ? 0 : 1) }
        }

        let known = try await saved()

        XCTAssertEqual(known.keys.sorted(), Array(1...500))
        XCTAssertEqual(known[1]?.amount, 0)
    }

    func testRewardsAreKeptPerBondAddressAndNode() async throws {
        _ = try await store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { _ in
            [entry(300)]
        }

        let otherNode = try await saved(node: "thor1other")
        let otherBond = try await saved(bond: "thor1other")

        XCTAssertTrue(otherNode.isEmpty)
        XCTAssertTrue(otherBond.isEmpty)
    }

    /// The card and the sheet fetch one key at once; each started from an empty copy and
    /// must still keep the rows the other saved while it was loading.
    func testOverlappingFetchesKeepEachOthersRows() async throws {
        _ = try await store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { _ in
            _ = try await self.store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { _ in
                [self.entry(200), self.entry(100)]
            }
            return [self.entry(300)]
        }

        let known = try await saved()

        XCTAssertEqual(Set(known.keys), [300, 200, 100])
    }

    /// Forty writers at once: only the lock around the read-merge-write keeps every
    /// row. A merge into a stale copy, or an unlocked re-read, drops rows.
    func testConcurrentFetchesKeepEveryRow() async throws {
        let store = store
        await withTaskGroup(of: Void.self) { group in
            for height in 1...40 {
                group.addTask {
                    _ = try? await store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { _ in
                        let entry = BondRewardHistoryEntry(
                            churnHeight: height,
                            churnDate: Date(timeIntervalSince1970: Double(height)),
                            amount: 1
                        )
                        return [entry]
                    }
                }
            }
        }

        let known = try await saved()

        XCTAssertEqual(known.keys.sorted(), Array(1...40))
    }

    func testAFailedFetchSavesNothingAndRethrows() async throws {
        do {
            _ = try await store.fetch(bondAddress: "thor1bond", nodeAddress: "thor1node") { _ -> [BondRewardHistoryEntry] in
                throw MockBondInteractor.StubError.unreachable
            }
            XCTFail("the fetch error must reach the caller")
        } catch {
            // Expected.
        }

        let known = try await saved()
        XCTAssertTrue(known.isEmpty)
    }
}
