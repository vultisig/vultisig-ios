//
//  VultYieldProviderTests.swift
//  VultisigAppTests
//
//  Pure-logic tests for the VULT staking provider: the approve-bundle gating,
//  unit conversions, maturity mapping, and the cancel-action defaults that pin
//  Circle against regression from the new optional protocol method.
//

import BigInt
import XCTest
@testable import VultisigApp

final class VultYieldProviderTests: XCTestCase {

    // MARK: - Approve bundle gating

    func testApproveAttachedWhenAllowanceShort() {
        let payload = VultYieldProvider.depositApprovePayload(allowance: BigInt(0), amount: BigInt(100))
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.spender.lowercased(), VultConstants.stakedVult.lowercased())
        // The approve must target VULT (the keysign coin is native ETH).
        XCTAssertEqual(payload?.token.lowercased(), VultConstants.underlyingVult.lowercased())
        XCTAssertEqual(payload?.amount, BigInt(100))
    }

    func testApproveSkippedWhenAllowanceSufficient() {
        XCTAssertNil(VultYieldProvider.depositApprovePayload(allowance: BigInt(100), amount: BigInt(100)))
        XCTAssertNil(VultYieldProvider.depositApprovePayload(allowance: BigInt(500), amount: BigInt(100)))
    }

    // MARK: - Conversions (18 decimals)

    func testHumanAmountRoundTrips() {
        let units = BigInt("1500000000000000000000")  // 1500 VULT
        XCTAssertEqual(VultYieldProvider.humanAmount(units), Decimal(1500))
        XCTAssertEqual(VultYieldProvider.baseUnits(Decimal(1500)), units)
    }

    func testMaturityDateMapsUnixSeconds() {
        let date = VultYieldProvider.maturityDate(BigInt(1_750_000_000))
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_750_000_000))
    }

    func testMaturityDateNilForZero() {
        XCTAssertNil(VultYieldProvider.maturityDate(.zero))
    }

    // MARK: - Presentation

    func testPresentationHasNoStaticApyAndSupportsCancel() {
        let presentation = VultYieldProvider().presentation
        XCTAssertNil(presentation.staticApyText, "VULT has no APY")
        XCTAssertTrue(presentation.supportsCancel)
        XCTAssertFalse(presentation.usesComputedSettlementWindow, "VULT reads per-request maturity, not a weekly window")
        XCTAssertEqual(presentation.assetTicker, "VULT")
        XCTAssertEqual(presentation.sharesTicker, "sVULT")
    }

    func testProviderConfig() {
        let provider = VultYieldProvider()
        XCTAssertEqual(provider.id, .vult)
        XCTAssertEqual(provider.chain, .ethereum)
        XCTAssertEqual(provider.assetDecimals, 18)
        XCTAssertEqual(provider.assetContract.lowercased(), VultConstants.underlyingVult.lowercased())
        XCTAssertEqual(provider.depositRecipient.lowercased(), VultConstants.stakedVult.lowercased())
        XCTAssertTrue(provider.hasWindowedRedemption)
        XCTAssertFalse(provider.requiresAccountSetup)
    }

    // MARK: - Cancel defaults (Circle regression guard)

    func testCircleDoesNotSupportCancel() {
        XCTAssertFalse(CircleYieldProvider().presentation.supportsCancel)
    }

    func testCircleUsesPresentationDefaults() {
        // The presentation defaults keep instant USDC providers (Circle) intact.
        XCTAssertTrue(CircleYieldProvider().presentation.usesComputedSettlementWindow)
        XCTAssertEqual(CircleYieldProvider().presentation.assetTicker, "USDC")
    }

    @MainActor
    func testCircleCancelDefaultThrowsUnsupported() async {
        let redemption = YieldRedemption(id: "1", amount: 1, requestedAt: Date(), claimableAt: nil, status: .pending)
        do {
            _ = try await CircleYieldProvider().buildCancelUnstakePayload(
                vault: Vault(name: "t"),
                recipient: "0x0",
                redemption: redemption
            )
            XCTFail("Circle must not support cancel")
        } catch {
            XCTAssertTrue(error is DefiYieldError)
        }
    }
}
