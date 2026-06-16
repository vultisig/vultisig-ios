//
//  NoonYieldProviderTests.swift
//  VultisigAppTests
//
//  Covers the Noon redemption state machine: how the on-chain read snapshot
//  maps to redemption rows (none/pending/claimable) and how the weekly
//  settlement date is derived for the pending-state copy.
//

import BigInt
import XCTest
@testable import VultisigApp

final class NoonYieldProviderTests: XCTestCase {

    // MARK: - Redemption derivation

    func testNoRedemptionWhenStateNone() {
        let position = NoonVaultPosition(
            shareBalance: BigInt(0),
            currentAssets: BigInt(0),
            claimableAssets: BigInt(0),
            claimableRedeemShares: BigInt(0),
            pendingRedeemShares: BigInt(0),
            redemptionState: .none
        )
        XCTAssertTrue(NoonYieldProvider.deriveRedemptions(from: position).isEmpty)
    }

    func testPendingRedemptionCarriesSettlementDate() {
        let position = NoonVaultPosition(
            shareBalance: BigInt(98_333_202),
            currentAssets: BigInt(101_000_000),
            claimableAssets: BigInt(0),
            claimableRedeemShares: BigInt(0),
            pendingRedeemShares: BigInt(98_333_202),
            redemptionState: .pending
        )

        let redemptions = NoonYieldProvider.deriveRedemptions(from: position)
        XCTAssertEqual(redemptions.count, 1)
        let redemption = redemptions[0]
        XCTAssertEqual(redemption.status, .pending)
        XCTAssertEqual(redemption.amount, Decimal(string: "98.333202"))
        XCTAssertNotNil(redemption.claimableAt, "a pending redemption must carry a settlement date")
        XCTAssertFalse(redemption.isClaimable, "a future-dated pending redemption is not yet claimable")
    }

    func testClaimableRedemptionIsImmediatelyClaimable() {
        let position = NoonVaultPosition(
            shareBalance: BigInt(96_000_000),
            currentAssets: BigInt(97_617_839),
            claimableAssets: BigInt(97_617_839),
            claimableRedeemShares: BigInt(96_000_000),
            pendingRedeemShares: BigInt(0),
            redemptionState: .claimable
        )

        let redemptions = NoonYieldProvider.deriveRedemptions(from: position)
        XCTAssertEqual(redemptions.count, 1)
        let redemption = redemptions[0]
        XCTAssertEqual(redemption.status, .claimable)
        XCTAssertEqual(redemption.amount, Decimal(string: "97.617839"))
        XCTAssertNil(redemption.claimableAt, "a claimable redemption has no remaining wait")
        XCTAssertTrue(redemption.isClaimable)
    }

    // MARK: - Claim guard

    @MainActor
    func testBuildClaimPayloadRejectsPendingRedemption() async {
        // A pending redemption's `amount` is in SHARE units; claiming it would
        // mis-denominate the withdraw, so the guard must reject it before any
        // network read or signed-bytes construction.
        let provider = NoonYieldProvider()
        let pending = YieldRedemption(
            id: "noon_pending",
            amount: Decimal(string: "98.333202") ?? .zero,
            requestedAt: Date(),
            claimableAt: nil,
            status: .pending
        )

        do {
            _ = try await provider.buildClaimPayload(
                vault: .example,
                recipient: "0x0000000000000000000000000000000000000001",
                redemption: pending
            )
            XCTFail("buildClaimPayload must reject a non-claimable redemption")
        } catch {
            // Expected — the guard throws up front.
        }
    }

    // MARK: - Settlement date

    func testNextSettlementDateIsWednesdayPlusSettlementWindowUtc() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        // A Monday — the next Wednesday window close is 2 days out, settling +7.
        let monday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))
        )

        let settlement = try XCTUnwrap(NoonYieldProvider.nextSettlementDate(now: monday))
        let components = calendar.dateComponents([.weekday, .hour], from: settlement)
        // Close is Wednesday (weekday 4); +7 days lands on a Wednesday again.
        XCTAssertEqual(components.weekday, 4)
        XCTAssertEqual(components.hour, NoonConstants.RedemptionWindow.closesHourUtc)
        XCTAssertGreaterThan(settlement, monday)
    }
}
