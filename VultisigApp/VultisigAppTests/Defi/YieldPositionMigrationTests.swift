//
//  YieldPositionMigrationTests.swift
//  VultisigAppTests
//
//  Guards the CirclePosition -> YieldPosition migration. The refactor promotes
//  the Circle-only balance cache to a generalized per-provider `YieldPosition`;
//  users who already deposited via Circle must keep their cached position. The
//  backfill is one-time and idempotent.
//

import XCTest
import SwiftData
@testable import VultisigApp

@MainActor
final class YieldPositionMigrationTests: XCTestCase {

    private var token: TestContextToken!
    private let service = YieldPositionStorageService()

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    func testLegacyCirclePositionMigratesToYieldPosition() throws {
        let vault = TestStore.makeVault(pubKey: "migrate-me")
        let legacy = CirclePosition(usdcBalance: 123.45, ethBalance: 0.6, vault: vault)
        Storage.shared.insert(legacy)
        try Storage.shared.save()

        XCTAssertNil(service.position(for: vault, providerID: .circle))

        try service.migrateCirclePositionIfNeeded(for: vault)

        let migrated = try XCTUnwrap(service.position(for: vault, providerID: .circle))
        XCTAssertEqual(migrated.depositedBalance, 123.45)
        XCTAssertEqual(migrated.nativeGasBalance, 0.6)
        XCTAssertEqual(migrated.providerID, .circle)
        XCTAssertEqual(migrated.id, "circle_migrate-me")
    }

    func testMigrationIsIdempotent() throws {
        let vault = TestStore.makeVault(pubKey: "idempotent")
        Storage.shared.insert(CirclePosition(usdcBalance: 10, ethBalance: 1, vault: vault))
        try Storage.shared.save()

        try service.migrateCirclePositionIfNeeded(for: vault)
        try service.migrateCirclePositionIfNeeded(for: vault)

        XCTAssertEqual(vault.yieldPositions.filter { $0.providerRawID == "circle" }.count, 1)
    }

    func testMigrationNoOpWhenNoLegacyPosition() throws {
        let vault = TestStore.makeVault(pubKey: "no-legacy")
        try service.migrateCirclePositionIfNeeded(for: vault)
        XCTAssertTrue(vault.yieldPositions.isEmpty)
    }

    func testUpsertWritesRedemptionRows() throws {
        let vault = TestStore.makeVault(pubKey: "yield-rows")
        let redemption = YieldRedemption(
            id: "req-1",
            amount: 95,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            claimableAt: Date(timeIntervalSince1970: 1_700_600_000),
            status: .pending
        )

        try service.upsert(
            providerID: .circle,
            depositedBalance: 100,
            nativeGasBalance: 0.2,
            redemptions: [redemption],
            for: vault
        )

        let position = try XCTUnwrap(service.position(for: vault, providerID: .circle))
        XCTAssertEqual(position.depositedBalance, 100)
        XCTAssertEqual(position.redemptions.count, 1)
        XCTAssertEqual(position.redemptions.first?.id, "req-1")
        XCTAssertEqual(position.redemptions.first?.status, .pending)
    }

    func testUpsertReplacesStaleRedemptionRows() throws {
        let vault = TestStore.makeVault(pubKey: "yield-replace")
        let pending = YieldRedemption(id: "req-1", amount: 95, requestedAt: .now, claimableAt: .now, status: .pending)
        try service.upsert(providerID: .circle, depositedBalance: 100, nativeGasBalance: 0.2, redemptions: [pending], for: vault)

        let claimable = YieldRedemption(id: "req-1", amount: 95, requestedAt: .now, claimableAt: .now, status: .claimable)
        try service.upsert(providerID: .circle, depositedBalance: 100, nativeGasBalance: 0.2, redemptions: [claimable], for: vault)

        let position = try XCTUnwrap(service.position(for: vault, providerID: .circle))
        XCTAssertEqual(position.redemptions.count, 1)
        XCTAssertEqual(position.redemptions.first?.status, .claimable)
    }
}
