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

    private let sampleUser = "0x8b937c5395d95a8c8948c7c5b844e1541798d90c"

    private func usdcCoin() -> Coin {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "usdc",
            decimals: NoonConstants.assetDecimals,
            priceProviderId: "usd-coin",
            contractAddress: NoonConstants.usdcMainnet,
            isNativeToken: false
        )
        return Coin(asset: asset, address: sampleUser, hexPublicKey: "HexPublicKeyExample")
    }

    private func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Bundled approve gating

    func testDepositBundlesApproveWhenAllowanceShort() throws {
        let amount = BigInt(100_000_000)
        let approve = NoonYieldProvider.depositApprovePayload(allowance: BigInt(0), amount: amount)
        let payload = try XCTUnwrap(approve)
        XCTAssertEqual(payload.amount, amount)
        XCTAssertEqual(
            payload.spender.lowercased(),
            NoonConstants.vaultAddress.lowercased(),
            "the approve spender must be the vault"
        )
    }

    func testDepositSkipsApproveWhenAllowanceSufficient() {
        let amount = BigInt(100_000_000)
        // Allowance exactly covers, and strictly exceeds: both skip the approve.
        XCTAssertNil(NoonYieldProvider.depositApprovePayload(allowance: amount, amount: amount))
        XCTAssertNil(NoonYieldProvider.depositApprovePayload(allowance: BigInt(200_000_000), amount: amount))
    }

    /// The bundled approve's (spender, amount) must reproduce the SDK golden
    /// `approve(vault, amount)` calldata (selector 0x095ea7b3) byte-for-byte.
    func testBundledApproveMatchesGoldenCalldata() throws {
        let amount = BigInt(100_000_000)
        let approve = try XCTUnwrap(
            NoonYieldProvider.depositApprovePayload(allowance: BigInt(0), amount: amount)
        )
        // Re-encode the same (spender, amount) the bundled approve authorizes.
        XCTAssertEqual(approve.spender.lowercased(), NoonConstants.vaultAddress.lowercased())
        let calldata = try NoonService.shared.encodeUsdcApprove(amount: approve.amount)
        XCTAssertEqual(
            hex(calldata),
            "0x095ea7b3000000000000000000000000a73424f1ac94b3ef0d0c9af4f2967c87d4af25d90000000000000000000000000000000000000000000000000000000005f5e100"
        )
    }

    // MARK: - Generic deposit payload (calldata in quote.tx)

    func testGenericDepositPayloadCarriesDepositCalldataByteEqual() throws {
        let amount = BigInt(100_000_000)
        let depositData = try NoonService.shared.encodeDeposit(assets: amount, receiver: sampleUser)
        let depositHex = hex(depositData)

        let payload = NoonYieldProvider.makeGenericDepositPayload(
            usdcCoin: usdcCoin(),
            sender: sampleUser,
            depositDataHex: depositHex,
            depositAmount: amount,
            gasPrice: BigInt(20_000_000_000),
            gasLimit: BigInt(300_000)
        )

        // The deposit call rides quote.tx, byte-equal to the SDK golden vector.
        XCTAssertEqual(
            payload.quote.tx.data,
            "0x6e553f650000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c"
        )
        XCTAssertEqual(payload.quote.tx.to.lowercased(), NoonConstants.vaultAddress.lowercased())
        XCTAssertEqual(payload.quote.tx.value, "0", "a Noon deposit sends no ETH value")
        XCTAssertEqual(payload.quote.tx.gasPrice, "20000000000")
        XCTAssertEqual(payload.quote.tx.gas, Int64(300_000))
        XCTAssertEqual(payload.fromCoin.ticker, "USDC")
        XCTAssertEqual(payload.fromAmount, amount)
        XCTAssertEqual(payload.provider, .oneInch)
    }

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
