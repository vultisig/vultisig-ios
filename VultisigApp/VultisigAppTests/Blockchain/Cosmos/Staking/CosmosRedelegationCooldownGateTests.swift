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

    func testTransitiveRedelegationBlocksNewRedelegationFromSource() {
        // After `otherSrc -> src`, redelegating from src is blocked - cosmos-sdk
        // `HasReceivingRedelegation(delAddr, src)` returns true because src
        // was the DESTINATION of an active redelegation.
        let unlock = now.addingTimeInterval(10 * 24 * 3600)  // 10 days out
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: otherSrc, dstValidator: src, completionTime: unlock)
            ],
            now: now
        )
        XCTAssertEqual(state, .blocked(unlocksAt: unlock))
    }

    func testEarliestUnlockIsSurfacedWhenMultipleRedelegationsTargetSrcAsDst() {
        let earlier = now.addingTimeInterval(5 * 24 * 3600)
        let later = now.addingTimeInterval(15 * 24 * 3600)
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: dst1, dstValidator: src, completionTime: later),
                CosmosRedelegationEntry(srcValidator: dst2, dstValidator: src, completionTime: earlier)
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
                CosmosRedelegationEntry(srcValidator: otherSrc, dstValidator: src, completionTime: expired)
            ],
            now: now
        )
        XCTAssertEqual(state, .available)
    }

    func testOutgoingRedelegationsDoNotBlockNewSrcRedelegate() {
        // The chain only blocks new `B -> C` when B was a recent DST. An
        // active `A -> B` does NOT prevent another `A -> C` (different dst).
        // The gate must not over-block.
        let pending = now.addingTimeInterval(10 * 24 * 3600)
        let state = CosmosRedelegationCooldownGate.evaluate(
            sourceValidator: src,
            redelegations: [
                CosmosRedelegationEntry(srcValidator: src, dstValidator: dst1, completionTime: pending)
            ],
            now: now
        )
        XCTAssertEqual(state, .available)
    }
}
