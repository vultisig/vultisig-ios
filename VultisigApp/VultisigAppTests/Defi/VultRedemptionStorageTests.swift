//
//  VultRedemptionStorageTests.swift
//  VultisigAppTests
//
//  Guards the storage primitives that make the VULT pending-unstake list
//  authoritative (Decision 5): appending a captured requestId, refreshing only
//  the balance without wiping the locally-captured rows, and idempotent re-capture
//  of the same requestId.
//

import XCTest
import SwiftData
@testable import VultisigApp

@MainActor
final class VultRedemptionStorageTests: XCTestCase {

    private var token: TestContextToken!
    private let service = YieldPositionStorageService()

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    private func redemption(_ id: String, status: YieldRedemption.Status = .pending) -> YieldRedemption {
        YieldRedemption(id: id, amount: 500, requestedAt: .now, claimableAt: .now, status: status)
    }

    func testAppendRedemptionCreatesPositionAndRow() throws {
        let vault = TestStore.makeVault(pubKey: "vult-append")
        try service.appendRedemption(
            redemption("42"),
            providerID: .vult,
            depositedBalance: 1000,
            nativeGasBalance: 0.1,
            for: vault
        )

        let rows = service.redemptions(for: vault, providerID: .vult)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "42")
        XCTAssertEqual(service.position(for: vault, providerID: .vult)?.depositedBalance, 1000)
    }

    func testAppendMultipleConcurrentRequests() throws {
        let vault = TestStore.makeVault(pubKey: "vult-multi")
        for id in ["1", "2", "3"] {
            try service.appendRedemption(redemption(id), providerID: .vult, depositedBalance: 1000, nativeGasBalance: 0.1, for: vault)
        }
        XCTAssertEqual(Set(service.redemptions(for: vault, providerID: .vult).map(\.id)), ["1", "2", "3"])
    }

    func testAppendIsIdempotentOnRequestId() throws {
        let vault = TestStore.makeVault(pubKey: "vult-idem")
        try service.appendRedemption(redemption("42", status: .pending), providerID: .vult, depositedBalance: 1000, nativeGasBalance: 0.1, for: vault)
        // Re-capture the same id with a new status — must update, not duplicate.
        try service.appendRedemption(redemption("42", status: .claimable), providerID: .vult, depositedBalance: 1000, nativeGasBalance: 0.1, for: vault)

        let rows = service.redemptions(for: vault, providerID: .vult)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.status, .claimable)
    }

    func testBalanceOnlyRefreshPreservesCapturedRows() throws {
        // The crux of Decision 5: a balance refresh must NOT wipe locally-captured
        // pending requests (they can't be re-enumerated without eth_getLogs).
        let vault = TestStore.makeVault(pubKey: "vult-preserve")
        try service.appendRedemption(redemption("42"), providerID: .vult, depositedBalance: 1000, nativeGasBalance: 0.1, for: vault)

        try service.upsertBalanceOnly(providerID: .vult, depositedBalance: 500, nativeGasBalance: 0.05, for: vault)

        let rows = service.redemptions(for: vault, providerID: .vult)
        XCTAssertEqual(rows.count, 1, "balance-only refresh must keep the captured request")
        XCTAssertEqual(service.position(for: vault, providerID: .vult)?.depositedBalance, 500)
    }

    func testReplaceRedemptionsAfterRefreshPrunesSettled() throws {
        // After refresh merges fresh on-chain state, replaceRedemptions writes the
        // surviving set (settled ids dropped).
        let vault = TestStore.makeVault(pubKey: "vult-prune")
        for id in ["1", "2"] {
            try service.appendRedemption(redemption(id), providerID: .vult, depositedBalance: 1000, nativeGasBalance: 0.1, for: vault)
        }
        // Request "1" settled → only "2" survives.
        try service.replaceRedemptions(
            [redemption("2", status: .claimable)],
            providerID: .vult,
            depositedBalance: 600,
            nativeGasBalance: 0.1,
            for: vault
        )

        let rows = service.redemptions(for: vault, providerID: .vult)
        XCTAssertEqual(rows.map(\.id), ["2"])
        XCTAssertEqual(rows.first?.status, .claimable)
    }
}
