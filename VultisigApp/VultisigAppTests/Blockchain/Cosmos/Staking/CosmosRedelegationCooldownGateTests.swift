//
//  CosmosRedelegationCooldownGateTests.swift
//  VultisigAppTests
//
//  Pins the 21-day redelegation cooldown gate per Spec Risk 4.
//

@testable import VultisigApp
import XCTest

final class CosmosRedelegationCooldownGateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_716_307_200)  // 2024-05-21T16:00:00Z
    private let src = "terravaloper1src"
    private let dst1 = "terravaloper1dst1"
    private let dst2 = "terravaloper1dst2"
    private let otherSrc = "terravaloper1other"

    func testAvailableWhenNoRedelegations() {
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [],
            now: now
        )
        XCTAssertEqual(state, .available)
    }

    func testBlockedWhenPendingRedelegationExistsFromSource() {
        let unlock = now.addingTimeInterval(10 * 24 * 3600)  // 10 days out
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: src, dstValidator: dst1, completionTime: unlock)
            ],
            now: now
        )
        XCTAssertEqual(state, .blocked(unlocksAt: unlock))
    }

    func testEarliestUnlockIsSurfacedWhenMultipleRedelegationsPending() {
        let earlier = now.addingTimeInterval(5 * 24 * 3600)
        let later = now.addingTimeInterval(15 * 24 * 3600)
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: src, dstValidator: dst1, completionTime: later),
                CosmosRedelegationEntry(srcValidator: src, dstValidator: dst2, completionTime: earlier)
            ],
            now: now
        )
        XCTAssertEqual(state, .blocked(unlocksAt: earlier))
    }

    func testExpiredRedelegationsDoNotBlock() {
        let expired = now.addingTimeInterval(-1)  // 1 second past
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: src, dstValidator: dst1, completionTime: expired)
            ],
            now: now
        )
        XCTAssertEqual(state, .available)
    }

    func testRedelegationsFromOtherValidatorDoNotBlockUs() {
        // The cosmos-sdk cooldown is per-source-validator. A pending
        // redelegation FROM a different source must not block us.
        let pending = now.addingTimeInterval(10 * 24 * 3600)
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: otherSrc, dstValidator: dst1, completionTime: pending)
            ],
            now: now
        )
        XCTAssertEqual(state, .available)
    }
}
