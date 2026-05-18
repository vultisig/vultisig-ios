//
//  BondNodeStateTests.swift
//  VultisigAppTests
//
//  Lock in the unbond/bond gating rules for Maya and THORChain bond nodes.
//

import XCTest
@testable import VultisigApp

final class BondNodeStateTests: XCTestCase {

    // MARK: - canUnbond — any non-Active state

    func testCanUnbondActiveIsFalse() {
        XCTAssertFalse(BondNodeState.active.canUnbond)
    }

    func testCanUnbondStandbyIsTrue() {
        XCTAssertTrue(BondNodeState.standby.canUnbond)
    }

    func testCanUnbondReadyIsTrue() {
        // The reported bug: Ready nodes were wrongly disabled. Maya itself
        // accepts unbond txs from Ready nodes (status != "Active").
        XCTAssertTrue(BondNodeState.ready.canUnbond)
    }

    func testCanUnbondDisabledIsTrue() {
        XCTAssertTrue(BondNodeState.disabled.canUnbond)
    }

    func testCanUnbondWhitelistedIsTrue() {
        XCTAssertTrue(BondNodeState.whitelisted.canUnbond)
    }

    func testCanUnbondUnknownIsTrue() {
        // Stale or missing status shouldn't strand users behind a greyed-out
        // button — let them try; THORNode rejects bad txs at submit.
        XCTAssertTrue(BondNodeState.unknown.canUnbond)
    }

    func testCanUnbondOnlyActiveBlocked() {
        // Sweep all cases to lock in the single-state exclusion shape so a
        // future enum addition doesn't silently re-enable the gating bug.
        for state in BondNodeState.allCases {
            XCTAssertEqual(state.canUnbond, state != .active, "canUnbond mismatch for \(state)")
        }
    }

    // MARK: - canBond — guard against regressions in the sibling rule

    func testCanBondAllowsWhitelistedStandbyReadyActive() {
        XCTAssertTrue(BondNodeState.whitelisted.canBond)
        XCTAssertTrue(BondNodeState.standby.canBond)
        XCTAssertTrue(BondNodeState.ready.canBond)
        XCTAssertTrue(BondNodeState.active.canBond)
    }

    func testCanBondBlocksDisabledAndUnknown() {
        XCTAssertFalse(BondNodeState.disabled.canBond)
        XCTAssertFalse(BondNodeState.unknown.canBond)
    }

    // MARK: - isEarningRewards

    func testIsEarningRewardsOnlyTrueForActive() {
        for state in BondNodeState.allCases {
            XCTAssertEqual(state.isEarningRewards, state == .active, "isEarningRewards mismatch for \(state)")
        }
    }

    // MARK: - init(fromAPIStatus:)

    func testInitFromAPIStatusKnownStrings() {
        XCTAssertEqual(BondNodeState(fromAPIStatus: "Active"), .active)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "active"), .active)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "ACTIVE"), .active)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "Standby"), .standby)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "Ready"), .ready)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "Whitelisted"), .whitelisted)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "Disabled"), .disabled)
    }

    func testInitFromAPIStatusUnknownFallsBackToUnknown() {
        XCTAssertEqual(BondNodeState(fromAPIStatus: ""), .unknown)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "Banned"), .unknown)
        XCTAssertEqual(BondNodeState(fromAPIStatus: "garbage"), .unknown)
    }
}
